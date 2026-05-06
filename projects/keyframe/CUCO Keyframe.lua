--[[
@description CUCO Keyframe — snapshot and recall FX parameter states with envelope writing
@author      felixtatic
@version     0.6.0
@about
  Capture FX parameter states across selected tracks (or take FX on items),
  recall them safely with envelope bypass, and write them as automation
  envelope points — at the cursor, or across a time selection.

  Per-parameter checkboxes scope what gets recalled/written. Recall is a
  two-stage preview: first click overrides envelopes and applies the
  snapshot, second click cancels. Selection changes auto-cancel.

  Snapshots persist per-project (saved into the .rpp via project ExtState),
  so they survive REAPER restarts.

@dependencies ReaImGui
@license      MIT
]]--

local SCRIPT_VERSION = "0.6.0"
local EXT_SECTION    = "CUCO_Keyframe"
local EXT_KEY        = "snapshots"

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

-- Transient status line shown under the action buttons; auto-clears after a few seconds.
local status_msg   = ""
local status_until = 0
local function setStatus(msg, duration)
  status_msg   = msg or ""
  status_until = reaper.time_precise() + (duration or 3.0)
end

-- Inline-edit state for the keyframe-list row name
local editing_idx          = nil   -- index of snapshot currently being renamed inline
local editing_just_started = false -- one-frame flag to grab keyboard focus

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
-- Persistence: serialize / deserialize / GUID resolution
-------------------------------------
-- Lua source serializer. Skips userdata/functions (e.g. raw REAPER pointers),
-- which is what lets us strip MediaTrack* / MediaItem_Take* fields safely.
local function serialize(v)
  local t = type(v)
  if t == "nil"     then return "nil" end
  if t == "boolean" then return tostring(v) end
  if t == "number"  then return string.format("%.17g", v) end
  if t == "string"  then return string.format("%q", v) end
  if t == "table" then
    local parts = {}
    for k, val in pairs(v) do
      local sval = serialize(val)
      if sval ~= "nil" then -- skip pointer fields entirely
        local key
        if type(k) == "number" then
          key = "[" .. k .. "]"
        elseif type(k) == "string" then
          key = "[" .. string.format("%q", k) .. "]"
        else
          key = nil -- skip unsupported key types
        end
        if key then parts[#parts + 1] = key .. "=" .. sval end
      end
    end
    return "{" .. table.concat(parts, ",") .. "}"
  end
  return "nil"
end

local function deserialize(s)
  if not s or s == "" then return nil end
  local fn = load("return " .. s, "snapshots", "t", {}) -- empty env: no globals
  if not fn then return nil end
  local ok, result = pcall(fn)
  return ok and result or nil
end

local function findTrackByGUID(guid)
  for i = 0, reaper.CountTracks(0) - 1 do
    local tr = reaper.GetTrack(0, i)
    if tr then
      local _, g = reaper.GetSetMediaTrackInfo_String(tr, "GUID", "", false)
      if g == guid then return tr end
    end
  end
  return nil
end

local function findItemByGUID(guid)
  for i = 0, reaper.CountMediaItems(0) - 1 do
    local it = reaper.GetMediaItem(0, i)
    if it then
      local _, g = reaper.GetSetMediaItemInfo_String(it, "GUID", "", false)
      if g == guid then return it end
    end
  end
  return nil
end

-- Strip pointer fields from a snapshot list so it can be serialized.
local function snapshotsToSerializable(snaps)
  local out = {}
  for i, snap in ipairs(snaps) do
    local data_clean = {}
    for id, d in pairs(snap.data) do
      data_clean[id] = { type = d.type, fx = d.fx } -- drop source/item
    end
    out[i] = {
      name    = snap.name,
      time    = snap.time,
      type    = snap.type,
      data    = data_clean,
      checked = snap.checked,
    }
  end
  return out
end

-- Walk loaded snapshot data and re-bind GUIDs to live track/take pointers.
-- Drops entries whose tracks/items no longer exist in this project.
local function rehydrateSnapshots(loaded)
  local out = {}
  for i, snap in ipairs(loaded) do
    local data = {}
    for id, d in pairs(snap.data or {}) do
      if d.type == "track" then
        local tr = findTrackByGUID(id)
        if tr then data[id] = { type = "track", source = tr, fx = d.fx } end
      elseif d.type == "take" then
        local it = findItemByGUID(id)
        local take = it and reaper.GetActiveTake(it) or nil
        if it and take then
          data[id] = { type = "take", source = take, item = it, fx = d.fx }
        end
      end
    end
    out[i] = {
      name    = snap.name or "(unnamed)",
      time    = snap.time or 0,
      type    = snap.type or "track",
      data    = data,
      checked = snap.checked or {},
    }
  end
  return out
end

local function saveSnapshots()
  local s = serialize(snapshotsToSerializable(snapshots))
  reaper.SetProjExtState(0, EXT_SECTION, EXT_KEY, s)
end

local function loadSnapshots()
  local _, s = reaper.GetProjExtState(0, EXT_SECTION, EXT_KEY)
  if not s or s == "" then return end
  local loaded = deserialize(s)
  if type(loaded) == "table" then
    snapshots = rehydrateSnapshots(loaded)
    activeSnap = math.min(activeSnap, #snapshots)
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
  saveSnapshots()
end

local function DeleteSnapshot()
  if activeSnap > 0 then
    table.remove(snapshots, activeSnap)
    activeSnap = math.min(activeSnap, #snapshots)
    saveSnapshots()
  end
end

local function OverwriteSnapshot()
  if activeSnap < 1 or not snapshots[activeSnap] then return end
  local held = buildHeld()
  if not next(held) then return end
  local snap = snapshots[activeSnap]
  snap.data = held
  snap.checked = cloneChecked(held)
  saveSnapshots()
end

-- Drop entries from the active snapshot that point at tracks, items, FX, or
-- params that no longer exist. Setting keys to nil during pairs() is safe in
-- Lua so long as we don't add new keys, which we don't.
local function PruneSnapshot()
  if activeSnap < 1 or not snapshots[activeSnap] then return 0 end
  local snap = snapshots[activeSnap]
  local removed = 0

  for id, data in pairs(snap.data) do
    local srcOk = (data.type == "track" and reaper.ValidatePtr(data.source, "MediaTrack*"))
               or (data.type == "take"  and reaper.ValidatePtr(data.source, "MediaItem_Take*"))
    if not srcOk then
      snap.data[id] = nil
      if snap.checked then snap.checked[id] = nil end
      removed = removed + 1
    else
      local fxCount = (data.type == 'track') and reaper.TrackFX_GetCount(data.source)
                                              or reaper.TakeFX_GetCount(data.source)
      for fxIdx, params in pairs(data.fx) do
        if fxIdx >= fxCount then
          data.fx[fxIdx] = nil
          if snap.checked[id] and snap.checked[id].fx then
            snap.checked[id].fx[fxIdx] = nil
          end
          removed = removed + 1
        else
          local maxP = (data.type == 'track')
            and reaper.TrackFX_GetNumParams(data.source, fxIdx)
            or  reaper.TakeFX_GetNumParams(data.source, fxIdx)
          for pIdx in pairs(params) do
            if pIdx >= maxP then
              params[pIdx] = nil
              if snap.checked[id] and snap.checked[id].fx and snap.checked[id].fx[fxIdx] then
                snap.checked[id].fx[fxIdx][pIdx] = nil
              end
              removed = removed + 1
            end
          end
        end
      end
    end
  end

  if removed > 0 then saveSnapshots() end
  return removed
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
        local maxP = (data.type=='track') and reaper.TrackFX_GetNumParams(data.source, fxIdx)
                                          or  reaper.TakeFX_GetNumParams (data.source, fxIdx)
        for pIdx,val in pairs(params) do
          if maxP and pIdx < maxP
             and snap.checked[id] and snap.checked[id].fx[fxIdx]
             and snap.checked[id].fx[fxIdx][pIdx] then
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
  local visible = reaper.ImGui_Begin(ctx, 'CUCO Keyframe ' .. SCRIPT_VERSION, true)

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
  reaper.ImGui_SameLine(ctx)
  if reaper.ImGui_Button(ctx, 'Prune stale') then
    local n = PruneSnapshot()
    setStatus(n > 0 and string.format("Pruned %d stale entr%s", n, n == 1 and "y" or "ies")
                     or "Nothing to prune")
  end

  local windowWidth = reaper.ImGui_GetWindowWidth(ctx)
  reaper.ImGui_SetCursorPosX(ctx, windowWidth - 110)
  reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Button(), 0x00CC44FF)
  if reaper.ImGui_Button(ctx, 'Write', 100, 0) then WriteAutomation() end
  reaper.ImGui_PopStyleColor(ctx)

  -- Transient status line (muted gray); fades out by simply not rendering after timeout.
  if status_msg ~= "" and reaper.time_precise() < status_until then
    reaper.ImGui_TextColored(ctx, 0xAAAAAAFF, status_msg)
  end

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

  -- Reserve right strip for time + action buttons. Tuned for default ImGui font.
  local RIGHT_STRIP_W = 180
  local content_w = reaper.ImGui_GetContentRegionAvail(ctx)
  local name_w = math.max(120, content_w - RIGHT_STRIP_W)

  local sel_flags = (reaper.ImGui_SelectableFlags_AllowDoubleClick()
                     | reaper.ImGui_SelectableFlags_AllowItemOverlap())

  for _, rec in ipairs(filtered) do
    local i, s, num = rec.i, rec.s, rec.n
    local sel = (i == activeSnap)

    reaper.ImGui_PushID(ctx, i)

    if editing_idx == i then
      -- Inline rename. Grab keyboard on first frame, commit on Enter or
      -- click-away (only if value actually changed); Esc reverts.
      if editing_just_started then
        reaper.ImGui_SetKeyboardFocusHere(ctx)
        editing_just_started = false
      end
      reaper.ImGui_SetNextItemWidth(ctx, name_w)
      local _, nm = reaper.ImGui_InputText(ctx, "##edit", s.name or "", 256,
        reaper.ImGui_InputTextFlags_EnterReturnsTrue() | reaper.ImGui_InputTextFlags_AutoSelectAll())
      if reaper.ImGui_IsItemDeactivated(ctx) then
        if reaper.ImGui_IsItemDeactivatedAfterEdit(ctx) then
          s.name = nm
          saveSnapshots()
        end
        editing_idx = nil
      end
    else
      local label = string.format("  %2d   %s", num, (s.name ~= "" and s.name) or "(unnamed)")
      if reaper.ImGui_Selectable(ctx, label, sel, sel_flags, name_w, 0) then
        if activeSnap ~= i then recall_staged = false end
        activeSnap = i
        if reaper.ImGui_IsMouseDoubleClicked(ctx, 0) then
          editing_idx = i
          editing_just_started = true
        end
      end
    end

    -- Time, muted, fixed-ish slot
    reaper.ImGui_SameLine(ctx)
    reaper.ImGui_TextColored(ctx, 0x888888FF, string.format("@%.3f", s.time or 0))

    -- Per-row action buttons. SmallButton is compact; tooltips clarify intent.
    reaper.ImGui_SameLine(ctx)
    if reaper.ImGui_SmallButton(ctx, "R") then
      if activeSnap ~= i then recall_staged = false end
      activeSnap = i
      RecallSnapshot(s)
    end
    if reaper.ImGui_IsItemHovered(ctx) then
      reaper.ImGui_SetTooltip(ctx, "Recall (preview snapshot; click again to cancel)")
    end

    reaper.ImGui_SameLine(ctx)
    if reaper.ImGui_SmallButton(ctx, "O") then
      activeSnap = i
      OverwriteSnapshot()
      setStatus(string.format("Overwrote '%s'", s.name or "?"))
    end
    if reaper.ImGui_IsItemHovered(ctx) then
      reaper.ImGui_SetTooltip(ctx, "Overwrite snapshot from current FX state")
    end

    reaper.ImGui_SameLine(ctx)
    reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Button(), 0x803030FF)
    reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_ButtonHovered(), 0xB04040FF)
    if reaper.ImGui_SmallButton(ctx, "x") then
      activeSnap = i
      DeleteSnapshot()
      reaper.ImGui_PopStyleColor(ctx, 2)
      reaper.ImGui_PopID(ctx)
      -- snapshots indices shifted; remaining `rec` entries reference stale i.
      -- Break and let next frame rebuild `filtered` with fresh indices.
      break
    end
    reaper.ImGui_PopStyleColor(ctx, 2)
    if reaper.ImGui_IsItemHovered(ctx) then
      reaper.ImGui_SetTooltip(ctx, "Delete snapshot")
    end

    reaper.ImGui_PopID(ctx)
  end

  reaper.ImGui_Separator(ctx)

  -- Tree of params with checkboxes (start)
  if activeSnap>0 and snapshots[activeSnap] then
    local s = snapshots[activeSnap]
    for id,data in pairs(s.data) do
      if (targetMode == 1 and data.type == "track") or (targetMode == 2 and data.type == "take") then
        local label = (data.type == "track") and GetTrackName(data.source) or GetTakeLabel(data.source, data.item)
        -- ##id suffix gives ImGui a stable unique ID independent of label text,
        -- so duplicate or empty labels can't cause "conflicting ID" errors.
        if reaper.ImGui_TreeNode(ctx, label .. "##" .. id) then
          local fxCount = (data.type == 'track') and reaper.TrackFX_GetCount(data.source)
                                                  or reaper.TakeFX_GetCount(data.source)
          for fxIdx,params in pairs(data.fx) do
            local fxExists = fxIdx < fxCount
            local fxName
            if fxExists then
              fxName = (data.type=='track')
                and select(2, reaper.TrackFX_GetFXName(data.source, fxIdx, ""))
                or  select(2, reaper.TakeFX_GetFXName(data.source, fxIdx, ""))
              fxName = StripGUIDfromFXName(fxName)
              if fxName == "" then fxName = "FX " .. fxIdx end
            else
              fxName = string.format("FX %d (removed)", fxIdx)
            end
            if reaper.ImGui_TreeNode(ctx, fxName .. "##fx" .. fxIdx) then
              local maxP = fxExists and ((data.type=='track')
                and reaper.TrackFX_GetNumParams(data.source, fxIdx)
                or  reaper.TakeFX_GetNumParams(data.source, fxIdx)) or 0
              for pIdx,val in pairs(params) do
                local pExists = pIdx < maxP
                local pName
                if pExists then
                  pName = (data.type=='track')
                    and select(2, reaper.TrackFX_GetParamName(data.source,fxIdx,pIdx,""))
                    or  select(2, reaper.TakeFX_GetParamName(data.source,fxIdx,pIdx,""))
                  if pName == "" then pName = "Param " .. pIdx end
                else
                  pName = string.format("Param %d (removed)", pIdx)
                end
                local key  = id..'.'..fxIdx..'.'..pIdx
                local flag = s.checked[id].fx[fxIdx][pIdx]
                -- "##key" makes the checkbox label invisible but ID-unique,
                -- so we get a clean checkbox + readable text via SameLine.
                local ch3, nf = reaper.ImGui_Checkbox(ctx, "##" .. key, flag)
                if ch3 then s.checked[id].fx[fxIdx][pIdx] = nf; saveSnapshots() end
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

loadSnapshots()
reaper.defer(loop)
