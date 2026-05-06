--[[
ReaScript Name: CUCO Keyframe
Author: ChatGPT / curl-enhanced
Version: 0.2.9
Description: Hold & write FX parameter snapshots as envelope keyframes on track or take FX.
             Latch-preview on Recall, proper ImGui ctx usage, close/reopen cleanly, replace/add.
Dependencies: ReaImGui (ImGui for Reaper)
]]--

-- ########################################
-- ## GLOBAL STATE                       ##
-- ########################################
local snapshots   = {}   -- array of { name, time, data=held, checked=checked }
local activeSnap  = 0
local writeMode   = 1    -- 1 = cursor, 2 = sel start/end
local targetMode  = 1    -- 1 = track FX, 2 = take FX
local replaceMode = true -- true = replace existing, false = add new

-- ########################################
-- ## HELPERS                            ##
-- ########################################
local function GetSourceGUID(source)
  if reaper.ValidatePtr(source, "MediaItem*") then
    return select(2, reaper.GetSetMediaItemInfo_String(source, "GUID", "", false))
  else
    return select(2, reaper.GetSetMediaTrackInfo_String(source, "GUID", "", false))
  end
end

local function cloneHeld(src)
  local dst = {}
  for id,data in pairs(src) do
    local copy = { type=data.type, source=data.source, fx={} }
    for fxIdx,params in pairs(data.fx) do
      copy.fx[fxIdx] = {}
      for pIdx,val in pairs(params) do
        copy.fx[fxIdx][pIdx] = val
      end
    end
    dst[id] = copy
  end
  return dst
end

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

local function buildHeld()
  local held = {}
  if targetMode == 1 then
    -- Track FX
    for i=0, reaper.CountSelectedTracks(0)-1 do
      local tr = reaper.GetSelectedTrack(0, i)
      local id = GetSourceGUID(tr)
      held[id] = { type="track", source=tr, fx={} }
      for fx=0, reaper.TrackFX_GetCount(tr)-1 do
        held[id].fx[fx] = {}
        for p=0, reaper.TrackFX_GetNumParams(tr,fx)-1 do
          held[id].fx[fx][p] = reaper.TrackFX_GetParam(tr,fx,p)
        end
      end
    end
  else
    -- Take FX
    for i=0, reaper.CountSelectedMediaItems(0)-1 do
      local item = reaper.GetSelectedMediaItem(0, i)
      local take = reaper.GetActiveTake(item)
      if take then
        local id = GetSourceGUID(item)
        held[id] = { type="take", source=take, fx={} }
        for fx=0, reaper.TakeFX_GetCount(take)-1 do
          held[id].fx[fx] = {}
          for p=0, reaper.TakeFX_GetNumParams(take,fx)-1 do
            held[id].fx[fx][p] = reaper.TakeFX_GetParam(take,fx,p)
          end
        end
      end
    end
  end
  return held
end

local function EnsureEnvelope(data, fxIdx, pIdx)
  local env = (data.type=="track")
    and reaper.GetFXEnvelope(data.source, fxIdx, pIdx, true)
    or reaper.TakeFX_GetEnvelope(data.source, fxIdx, pIdx, true)
  if env then
    local _, chunk = reaper.GetEnvelopeStateChunk(env, "", false)
    chunk = chunk:gsub("VIS %d","VIS 1"):gsub("ARM %d","ARM 1")
    reaper.SetEnvelopeStateChunk(env, chunk, false)
  end
  return env
end

local function DeleteRange(env, s, e) reaper.DeleteEnvelopePointRange(env, s, e) end
local function DeletePoint(env, t)    reaper.DeleteEnvelopePointRange(env, t-1e-6, t+1e-6) end
local function WritePoint(env, t, v)  reaper.InsertEnvelopePoint(env, t, v, 0, 0, false, false) end

-- ########################################
-- ## SNAPSHOT OPERATIONS               ##
-- ########################################
local function HoldSnapshot()
  local cur = reaper.GetCursorPosition()
  local held = buildHeld()
  if not next(held) then return end
  snapshots[#snapshots+1] = {
    name    = string.format("Snap %d @ %.3f", #snapshots+1, cur),
    time    = cur,
    data    = held,
    checked = cloneChecked(held)
  }
  activeSnap = #snapshots
end

local function DeleteSnapshot()
  if activeSnap > 0 then
    table.remove(snapshots, activeSnap)
    activeSnap = math.min(activeSnap, #snapshots)
  end
end

local function RecallSnapshot(snap)
  if not snap then return end
  -- set selected tracks to Latch Preview mode (I_AUTOMODE=4)
  for i=0, reaper.CountSelectedTracks(0)-1 do
    local tr = reaper.GetSelectedTrack(0, i)
    reaper.SetMediaTrackInfo_Value(tr, "I_AUTOMODE", 4)
  end
  -- apply parameters live
  for id,data in pairs(snap.data) do
    for fxIdx,params in pairs(data.fx) do
      for pIdx,val in pairs(params) do
        if data.type=="track" then
          reaper.TrackFX_SetParam(data.source, fxIdx, pIdx, val)
        else
          reaper.TakeFX_SetParamNormalized(data.source, fxIdx, pIdx, val)
        end
      end
    end
  end
end

-- ########################################
-- ## WRITE AUTOMATION                  ##
-- ########################################
local function WriteAutomation()
  if activeSnap < 1 or not snapshots[activeSnap] then return end
  local snap = snapshots[activeSnap]
  local t0,t1 = reaper.GetSet_LoopTimeRange(false, false, 0, 0, false)
  local cur   = reaper.GetCursorPosition()
  local times = (writeMode==1) and {cur} or ((t1>t0) and {t0,t1} or {cur})

  for id,data in pairs(snap.data) do
    for fxIdx,params in pairs(data.fx) do
      for pIdx,val in pairs(params) do
        if snap.checked[id].fx[fxIdx][pIdx] then
          local env = EnsureEnvelope(data, fxIdx, pIdx)
          if env then
            if writeMode==2 and replaceMode then DeleteRange(env, t0, t1) end
            for _, tm in ipairs(times) do
              local wt = tm
              if data.type=="take" then
                local item = reaper.GetMediaItemTake_Item(data.source)
                local pos  = reaper.GetMediaItemInfo_Value(item, "D_POSITION")
                wt = tm - pos
              end
              if writeMode==1 and replaceMode then DeletePoint(env, wt) end
              WritePoint(env, wt, val)
            end
          end
        end
      end
    end
  end

  reaper.Undo_OnStateChange("CUCO Keyframe: wrote '"..snap.name.."'")
end

-- ########################################
-- ## GUI (ReaImGui)                    ##
-- ########################################
local ctx = reaper.ImGui_CreateContext('CUCO Keyframe')

local function loop()
  reaper.ImGui_SetNextWindowSize(ctx, 520, 650, reaper.ImGui_Cond_FirstUseEver())
  local visible, isOpen = reaper.ImGui_Begin(ctx, 'CUCO Keyframe 0.2.9', true)

  if not visible then
    reaper.ImGui_End(ctx)
    reaper.ImGui_DestroyContext(ctx)
    return
  end

  -- Top controls
  if reaper.ImGui_RadioButton(ctx, 'Track FX', targetMode==1) then targetMode=1 end
  reaper.ImGui_SameLine(ctx)
  if reaper.ImGui_RadioButton(ctx, 'Take FX',  targetMode==2) then targetMode=2 end
  reaper.ImGui_SameLine(ctx)
  if reaper.ImGui_RadioButton(ctx, 'Cursor',   writeMode==1) then writeMode=1 end
  reaper.ImGui_SameLine(ctx)
  if reaper.ImGui_RadioButton(ctx, 'Sel Start/End', writeMode==2) then writeMode=2 end
  reaper.ImGui_SameLine(ctx)
  local ch, val = reaper.ImGui_Checkbox(ctx, 'Replace existing', replaceMode)
  if ch then replaceMode = val end

  reaper.ImGui_Separator(ctx)

  -- Actions
  if reaper.ImGui_Button(ctx, 'Hold Snapshot') then HoldSnapshot() end
  reaper.ImGui_SameLine(ctx)
  if reaper.ImGui_Button(ctx, 'Recall')       then RecallSnapshot(snapshots[activeSnap]) end
  reaper.ImGui_SameLine(ctx)
  if reaper.ImGui_Button(ctx, 'Write')        then WriteAutomation() end
  reaper.ImGui_SameLine(ctx)
  if reaper.ImGui_Button(ctx, 'Delete')       then DeleteSnapshot() end

  reaper.ImGui_Separator(ctx)

  -- Snapshot list
  for i,s in ipairs(snapshots) do
    local sel = (i==activeSnap)
    if reaper.ImGui_Selectable(ctx, string.format("%d: %s @ %.3f", i, s.name, s.time), sel) then
      activeSnap = i
    end
  end

  reaper.ImGui_Separator(ctx)

  -- Name/time
  if activeSnap>0 then
    local s = snapshots[activeSnap]
    reaper.ImGui_Text(ctx, 'Name:')
    local ch2, nm = reaper.ImGui_InputText(ctx, '##name', s.name, 256)
    if ch2 then s.name = nm end
    reaper.ImGui_SameLine(ctx)
    reaper.ImGui_Text(ctx, string.format('@ %.3f', s.time))
  end

  reaper.ImGui_Separator(ctx)

  -- Parameter checklist
  if activeSnap>0 then
    local s = snapshots[activeSnap]
    for id,data in pairs(s.data) do
      local label = (data.type=='track' and 'Track ' or 'Take ')..id
      if reaper.ImGui_TreeNode(ctx, label) then
        for fxIdx,params in pairs(data.fx) do
          local fxName = data.type=='track'
            and select(2, reaper.TrackFX_GetFXName(data.source, fxIdx, "")) 
            or select(2, reaper.TakeFX_GetFXName(data.source, fxIdx, "")) 
          if reaper.ImGui_TreeNode(ctx, fxName) then
            for pIdx,val in pairs(params) do
              local pName = data.type=='track'
                and select(2, reaper.TrackFX_GetParamName(data.source,fxIdx,pIdx,""))
                or select(2, reaper.TakeFX_GetParamName(data.source,fxIdx,pIdx,""))
              local key  = id..'.'..fxIdx..'.'..pIdx
              local flag = s.checked[id].fx[fxIdx][pIdx]
              local ch3, nf = reaper.ImGui_Checkbox(ctx, key, flag)
              if ch3 then s.checked[id].fx[fxIdx][pIdx] = nf end
              reaper.ImGui_SameLine(ctx)
              reaper.ImGui_Text(ctx, pName..': '..string.format('%.3f', val))
            end
            reaper.ImGui_TreePop(ctx)
          end
        end
        reaper.ImGui_TreePop(ctx)
      end
    end
  else
    reaper.ImGui_Text(ctx, '(No snapshots yet)')
  end

  reaper.ImGui_End(ctx)
  reaper.defer(loop)
end

reaper.defer(loop)
