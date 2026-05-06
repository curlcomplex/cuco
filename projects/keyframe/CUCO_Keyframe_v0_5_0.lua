--[[
ReaScript Name: CUCO Keyframe
Author: ChatGPT / curl-enhanced
Version: 0.5.1
Description: Safe recall/edit: Envelope bypass via actions, recall cancel resets on selection, normalized params, robust pointer checks, undo-safe, correct envelope scaling when writing.
Dependencies: ReaImGui (ImGui for Reaper)
]]--

-------------------------------------
-- State & Settings
-------------------------------------
local snapshots   = {}
local activeSnap  = 0
local writeMode   = 1       -- 1: cursor, 2: time selection
local targetMode  = 1       -- 1: Track FX, 2: Take FX
local replaceMode = true
local recall_respects_checks = true

local recall_staged = false
local in_edit_mode  = false

-------------------------------------
-- Helpers: Names & GUIDs
-------------------------------------
local function GetTrackName(tr)
  local _, name = reaper.GetTrackName(tr, "")
  local idx = reaper.GetMediaTrackInfo_Value(tr, "IP_TRACKNUMBER")
  return string.format("Track %d: %s", idx or 0, name ~= "" and name or "(unnamed)")
end

local function GetTakeLabel(take, item)
  local name = reaper.GetTakeName(take)
  if not name or name == "" then
    if item then
      local _, itemchunk = reaper.GetSetMediaItemInfo_String(item, "P_NAME", "", false)
      name = itemchunk ~= "" and itemchunk or "(unnamed)"
    else
      name = "(unnamed)"
    end
  end
  return name
end

local function StripGUIDfromFXName(name)
  return name:gsub("^%b{}", ""):gsub("^%s+", "")
end

local function GetSourceGUID(source)
  if reaper.ValidatePtr(source, "MediaItem*") then
    return select(2, reaper.GetSetMediaItemInfo_String(source, "GUID", "", false))
  else
    return select(2, reaper.GetSetMediaTrackInfo_String(source, "GUID", "", false))
  end
end

-------------------------------------
-- Helpers: Clone tables
-------------------------------------
local function cloneChecked(src)
  local dst = {}
  for id,data in pairs(src) do
    dst[id] = { fx={} }
    for fxIdx,params in pairs(data.fx) do
      dst[id].fx[fxIdx] = {}
      for pIdx,_ in pairs(params) do
        dst[id].fx[fxIdx][pIdx] = true
      end
    end
  end
  return dst
end

-------------------------------------
-- Normalized param getters/setters
-------------------------------------
local function capParam(data, fx, p)
  if data.type == "track" then
    return reaper.TrackFX_GetParamNormalized(data.source, fx, p)
  else
    return reaper.TakeFX_GetParamNormalized(data.source, fx, p)
  end
end

local function setParam(data, fx, p, val)
  if data.type == "track" then
    reaper.TrackFX_SetParamNormalized(data.source, fx, p, val)
  else
    reaper.TakeFX_SetParamNormalized(data.source, fx, p, val)
  end
end

-------------------------------------
-- Build capture set (selected tracks/takes)
-------------------------------------
local function buildHeld()
  local held = {}
  if targetMode == 1 then
    for i=0, reaper.CountSelectedTracks(0)-1 do
      local tr = reaper.GetSelectedTrack(0, i)
      if reaper.ValidatePtr(tr, "MediaTrack*") then
        local id = GetSourceGUID(tr)
        held[id] = { type="track", source=tr, fx={} }
        local fxCount = reaper.TrackFX_GetCount(tr)
        for fx=0, fxCount-1 do
          held[id].fx[fx] = {}
          local pCount = reaper.TrackFX_GetNumParams(tr, fx)
          for p=0, pCount-1 do
            held[id].fx[fx][p] = capParam(held[id], fx, p)
          end
        end
      end
    end
  else
    for i=0, reaper.CountSelectedMediaItems(0)-1 do
      local item = reaper.GetSelectedMediaItem(0, i)
      local take = item and reaper.GetActiveTake(item) or nil
      if take and reaper.ValidatePtr(take, "MediaItem_Take*") then
        local id = GetSourceGUID(item)
        held[id] = { type="take", source=take, item=item, fx={} }
        local fxCount = reaper.TakeFX_GetCount(take)
        for fx=0, fxCount-1 do
          held[id].fx[fx] = {}
          local pCount = reaper.TakeFX_GetNumParams(take, fx)
          for p=0, pCount-1 do
            held[id].fx[fx][p] = capParam(held[id], fx, p)
          end
        end
      end
    end
  end
  return held
end

-------------------------------------
-- Envelopes
-------------------------------------
local function EnsureEnvelope(data, fxIdx, pIdx)
  local env
  if data.type == "track" then
    if reaper.ValidatePtr(data.source, "MediaTrack*") then
      env = reaper.GetFXEnvelope(data.source, fxIdx, pIdx, true)
    end
  else
    if reaper.ValidatePtr(data.source, "MediaItem_Take*") then
      env = reaper.TakeFX_GetEnvelope(data.source, fxIdx, pIdx, true)
    end
  end
  if env then
    local _, chunk = reaper.GetEnvelopeStateChunk(env, "", false)
    chunk = chunk:gsub("VIS %d","VIS 1"):gsub("ARM %d","ARM 1")
    reaper.SetEnvelopeStateChunk(env, chunk, false)
  end
  return env
end

local function DeleteRange(env, s, e) reaper.DeleteEnvelopePointRange(env, s, e) end
local function DeletePoint(env, t)    reaper.DeleteEnvelopePointRange(env, t-1e-6, t+1e-6) end

-- Envelope scaling fix: values are stored normalized 0..1, convert to env mode when writing
local function WritePoint(env, t, norm_v)
  local mode = reaper.GetEnvelopeScalingMode(env) or 0
  local v = reaper.ScaleToEnvelopeMode(mode, norm_v or 0.0)
  reaper.InsertEnvelopePointEx(env, -1, t, v, 0, 0.0, false, true)
end

-------------------------------------
-- Snapshots
-------------------------------------
local function HoldSnapshot()
  local cur = reaper.GetCursorPosition()
  local held = buildHeld()
  if not next(held) then return end
  local snapType = (targetMode == 1) and "track" or "take"
  local names = {}
  for _, data in pairs(held) do
    if snapType == "track" then
      table.insert(names, select(2, reaper.GetTrackName(data.source, "")))
    else
      table.insert(names, GetTakeLabel(data.source, data.item))
    end
  end
  local namePrefix = "Multiple Tracks"
  if snapType == "track" and #names == 1 then namePrefix = names[1] end
  if snapType == "take" then
    namePrefix = #names == 1 and (names[1] ~= "" and names[1] or "(unnamed)") or "Multiple Takes"
  end
  local n = 1
  for _, snap in ipairs(snapshots) do
    if snap.type == snapType then n = n + 1 end
  end
  local name = string.format("%s Keyframe %d @ %.3f", namePrefix, n, cur)
  snapshots[#snapshots+1] = {
    name    = name,
    time    = cur,
    data    = held,
    checked = cloneChecked(held),
    type    = snapType
  }
  activeSnap = #snapshots
end

local function DeleteSnapshot()
  if activeSnap > 0 then
    table.remove(snapshots, activeSnap)
    activeSnap = math.min(activeSnap, #snapshots)
  end
end

local function OverwriteSnapshot()
  if activeSnap < 1 or not snapshots[activeSnap] then return end
  local held = buildHeld()
  if not next(held) then return end
  local snap = snapshots[activeSnap]
  snap.data = held
  snap.checked = cloneChecked(held)
end

-------------------------------------
-- Edit Mode
-------------------------------------
local function SetEditMode(on)
  if on then
    reaper.Main_OnCommand(40885, 0) -- Bypass all envelopes (ON)
  else
    reaper.Main_OnCommand(40876, 0) -- No automation override (OFF)
  end
  in_edit_mode = on
end

-------------------------------------
-- Recall
-------------------------------------
local function RecallSnapshot(snap)
  if not snap then return end

  if not recall_staged then
    if not in_edit_mode then SetEditMode(true) end
    reaper.Undo_BeginBlock2(0)

    for id, data in pairs(snap.data) do
      if (data.type == "track" and reaper.ValidatePtr(data.source, "MediaTrack*"))
      or (data.type == "take"  and reaper.ValidatePtr(data.source, "MediaItem_Take*")) then
        for fxIdx, params in pairs(data.fx) do
          local maxP = (data.type=='track') and reaper.TrackFX_GetNumParams(data.source, fxIdx)
                                          or  reaper.TakeFX_GetNumParams (data.source, fxIdx)
          if maxP and maxP > 0 then
            for pIdx, val in pairs(params) do
              if pIdx < maxP then
                if (not recall_respects_checks) or (snap.checked and snap.checked[id] and snap.checked[id].fx[fxIdx] and snap.checked[id].fx[fxIdx][pIdx]) then
                  setParam(data, fxIdx, pIdx, val)
                end
              end
            end
          end
        end
      end
    end

    reaper.Undo_EndBlock2(0, "CUCO Keyframe: Recall '" .. (snap.name or "?") .. "'", -1)
    recall_staged = true
  else
    SetEditMode(false)
    recall_staged = false
  end
end

-------------------------------------
-- Write
-------------------------------------
local function WriteAutomation()
  if activeSnap < 1 or not snapshots[activeSnap] then return end
  local snap = snapshots[activeSnap]
  SetEditMode(false)
  recall_staged = false

  local t0,t1 = reaper.GetSet_LoopTimeRange(false, false, 0, 0, false)
  local cur   = reaper.GetCursorPosition()
  local times = (writeMode==1) and {cur} or ((t1>t0) and {t0,t1} or {cur})

  reaper.Undo_BeginBlock2(0)

  for id,data in pairs(snap.data) do
    if ((snap.type == "track" and data.type == "track") or (snap.type == "take" and data.type == "take"))
    and ((data.type == "track" and reaper.ValidatePtr(data.source, "MediaTrack*"))
      or (data.type == "take"  and reaper.ValidatePtr(data.source, "MediaItem_Take*"))) then
      for fxIdx,params in pairs(data.fx) do
        for pIdx,val in pairs(params) do
          if snap.checked[id].fx[fxIdx][pIdx] then
            local env = EnsureEnvelope(data, fxIdx, pIdx)
            if env then
              if writeMode==2 and replaceMode then DeleteRange(env, t0, t1) end
              for _, tm in ipairs(times) do
                local wt = tm
                if data.type=="take" then
                  local item = data.item or (reaper.ValidatePtr(data.source, "MediaItem_Take*") and reaper.GetMediaItemTake_Item(data.source))
                  local pos  = item and reaper.GetMediaItemInfo_Value(item, "D_POSITION") or 0
                  wt = tm - pos
                end
                if writeMode==1 and replaceMode then DeletePoint(env, wt) end
                WritePoint(env, wt, val) -- scale inside WritePoint
              end
              reaper.Envelope_SortPoints(env)
            end
          end
        end
      end
    end
  end

  reaper.Undo_EndBlock2(0, "CUCO Keyframe: Write '"..(snap.name or "?").."'", -1)
end

-------------------------------------
-- Selection-change auto-cancel
-------------------------------------
local prevSelHash = ""
local function selHash()
  local ids = {}
  if targetMode == 1 then
    for i=0, reaper.CountSelectedTracks(0)-1 do
      local tr = reaper.GetSelectedTrack(0,i)
      if tr then ids[#ids+1] = select(2, reaper.GetSetMediaTrackInfo_String(tr, "GUID", "", false)) end
    end
  else
    for i=0, reaper.CountSelectedMediaItems(0)-1 do
      local it = reaper.GetSelectedMediaItem(0,i)
      if it then ids[#ids+1] = select(2, reaper.GetSetMediaItemInfo_String(it, "GUID", "", false)) end
    end
  end
  table.sort(ids)
  return table.concat(ids, "|")
end

-------------------------------------
-- UI
-------------------------------------
local ctx = reaper.ImGui_CreateContext('CUCO Keyframe')

local function ButtonCol(ctx, mode, cur, colA, colB)
  if mode == cur then
    reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Button(), colA)
  else
    reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Button(), colB)
  end
end

local function loop()
  reaper.ImGui_SetNextWindowSize(ctx, 520, 650, reaper.ImGui_Cond_FirstUseEver())
  local visible = reaper.ImGui_Begin(ctx, 'CUCO Keyframe 0.5.1', true)

  if not visible then
    reaper.ImGui_End(ctx)
    reaper.ImGui_DestroyContext(ctx)
    return
  end

  -- Auto-cancel if user changed selection mid-stage
  local h = selHash()
  if h ~= prevSelHash then
    prevSelHash = h
    if recall_staged or in_edit_mode then
      SetEditMode(false)
      recall_staged = false
    end
  end

  -- Edit mode toggle
  local editLabel = in_edit_mode and "Edit Mode: On" or "Edit Mode: Off"
  reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Button(), in_edit_mode and 0xFFD050FF or 0x555555FF)
  if reaper.ImGui_Button(ctx, editLabel, 120, 0) then
    SetEditMode(not in_edit_mode)
    recall_staged = false
  end
  reaper.ImGui_PopStyleColor(ctx)

  -- Target mode toggle
  reaper.ImGui_SameLine(ctx)
  ButtonCol(ctx, targetMode, 1, 0x3232C8FF, 0x303030FF)
  local label1 = (targetMode == 1) and "Track FX" or "Take FX"
  if reaper.ImGui_Button(ctx, label1, 100, 0) then
    targetMode = (targetMode == 1) and 2 or 1
  end
  reaper.ImGui_PopStyleColor(ctx)

  -- Write mode toggle
  reaper.ImGui_SameLine(ctx)
  ButtonCol(ctx, writeMode, 1, 0x25A18EFF, 0x303030FF)
  local label2 = (writeMode == 1) and "Write at Cursor" or "Write to Selection"
  if reaper.ImGui_Button(ctx, label2, 140, 0) then
    writeMode = (writeMode == 1) and 2 or 1
  end
  reaper.ImGui_PopStyleColor(ctx)

  -- Replace checkbox
  reaper.ImGui_SameLine(ctx)
  local ch, val = reaper.ImGui_Checkbox(ctx, 'Replace existing', replaceMode)
  if ch then replaceMode = val end

  -- Recall respects checks
  reaper.ImGui_SameLine(ctx)
  local chR, nvR = reaper.ImGui_Checkbox(ctx, 'Recall: respect checked', recall_respects_checks)
  if chR then recall_respects_checks = nvR end

  reaper.ImGui_Separator(ctx)

  -- Action buttons
  if reaper.ImGui_Button(ctx, 'Capture Keyframe') then HoldSnapshot() end
  reaper.ImGui_SameLine(ctx)
  local recallBtnLabel = recall_staged and "Recall Cancel" or "Recall"
  if reaper.ImGui_Button(ctx, recallBtnLabel) then RecallSnapshot(snapshots[activeSnap]) end
  reaper.ImGui_SameLine(ctx)
  if reaper.ImGui_Button(ctx, 'Overwrite') then OverwriteSnapshot() end
  reaper.ImGui_SameLine(ctx)
  if reaper.ImGui_Button(ctx, 'Delete') then DeleteSnapshot() end

  local windowWidth = reaper.ImGui_GetWindowWidth(ctx)
  reaper.ImGui_SetCursorPosX(ctx, windowWidth - 110)
  reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Button(), 0x00CC44FF)
  if reaper.ImGui_Button(ctx, 'Write', 100, 0) then WriteAutomation() end
  reaper.ImGui_PopStyleColor(ctx)

  reaper.ImGui_Separator(ctx)

  -- Filtered list of snapshots by current target type
  local filtered = {}
  local n = 0
  for i,s in ipairs(snapshots) do
    if (targetMode == 1 and s.type == "track") or (targetMode == 2 and s.type == "take") then
      n = n + 1
      table.insert(filtered, {i=i, s=s, n=n})
    end
  end

  for _, rec in ipairs(filtered) do
    local i, s, num = rec.i, rec.s, rec.n
    local sel = (i==activeSnap)
    if reaper.ImGui_Selectable(ctx, string.format("%d: %s", num, s.name), sel) then
      if activeSnap ~= i then
        recall_staged = false
      end
      activeSnap = i
    end
  end

  reaper.ImGui_Separator(ctx)

  -- Active snapshot details
  if activeSnap>0 and snapshots[activeSnap] then
    local s = snapshots[activeSnap]
    reaper.ImGui_Text(ctx, 'Name:')
    local ch2, nm = reaper.ImGui_InputText(ctx, '##name', s.name or "", 256)
    if ch2 then s.name = nm end
    reaper.ImGui_SameLine(ctx)
    reaper.ImGui_Text(ctx, string.format('@ %.3f', s.time or 0))
  end

  reaper.ImGui_Separator(ctx)

  -- Tree of params with checkboxes (start)
  if activeSnap>0 and snapshots[activeSnap] then
    local s = snapshots[activeSnap]
    for id,data in pairs(s.data) do
      if (targetMode == 1 and data.type == "track") or (targetMode == 2 and data.type == "take") then
        local label = (data.type == "track") and GetTrackName(data.source) or GetTakeLabel(data.source, data.item)
        if reaper.ImGui_TreeNode(ctx, label) then
          for fxIdx,params in pairs(data.fx) do
            local fxName = (data.type=='track')
              and select(2, reaper.TrackFX_GetFXName(data.source, fxIdx, "")) 
              or select(2, reaper.TakeFX_GetFXName(data.source, fxIdx, "")) 
            fxName = StripGUIDfromFXName(fxName)
            if reaper.ImGui_TreeNode(ctx, fxName) then
              for pIdx,val in pairs(params) do
                local pName = (data.type=='track')
                  and select(2, reaper.TrackFX_GetParamName(data.source,fxIdx,pIdx,""))
                  or select(2, reaper.TakeFX_GetParamName(data.source,fxIdx,pIdx,""))
                local key  = id..'.'..fxIdx..'.'..pIdx
                local flag = s.checked[id].fx[fxIdx][pIdx]
                local ch3, nf = reaper.ImGui_Checkbox(ctx, key, flag)
                if ch3 then s.checked[id].fx[fxIdx][pIdx] = nf end
                reaper.ImGui_SameLine(ctx)
                reaper.ImGui_Text(ctx, string.format('%s: %.3f', pName, val))
              end
              reaper.ImGui_TreePop(ctx)
            end
          end
          reaper.ImGui_TreePop(ctx)
        end
      end
    end
  else
    reaper.ImGui_Text(ctx, '(No snapshots yet)')
  end

  reaper.ImGui_End(ctx)
  reaper.defer(loop)
end

reaper.defer(loop)
