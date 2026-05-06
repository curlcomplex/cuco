--[[
ReaScript Name: CUCO Keyframe
Author: ChatGPT / curl-enhanced
Version: 0.1
Description: Hold & write current FX parameter values as envelope points on either track FX or take FX.
Dependencies: ReaImGui (ImGui for Reaper)
]]--

-- ########################################
-- ## GLOBAL STATE                       ##
-- ########################################
local held           = {}   -- held[id] = { type="track"/"take", source, fx = { [fxidx] = { [paramidx] = value } } }
local checked        = {}   -- mirror of held: which params to write
local lastSnapTime   = nil
local lastSnapCount  = 0
local writeMode      = 1    -- 1 = cursor, 2 = selection start/end
local targetMode     = 1    -- 1 = Track FX, 2 = Take FX

-- ########################################
-- ## HELPERS                            ##
-- ########################################

-- Get a GUID for a track or item
local function GetSourceGUID(source)
  if reaper.ValidatePtr(source, "MediaItem*") then
    local _, guid = reaper.GetSetMediaItemInfo_String(source, "GUID", "", false)
    return guid
  else
    local _, guid = reaper.GetSetMediaTrackInfo_String(source, "GUID", "", false)
    return guid
  end
end

-- Capture snapshot (branch for track vs take FX)
local function CaptureSnapshot()
  held = {}
  checked = {}
  lastSnapTime  = reaper.GetCursorPosition()
  lastSnapCount = 0

  if targetMode == 1 then
    -- Track FX mode
    for i = 0, reaper.CountSelectedTracks(0)-1 do
      local tr = reaper.GetSelectedTrack(0, i)
      local guid = GetSourceGUID(tr)
      held[guid] = { type="track", source=tr, fx = {} }
      for fx = 0, reaper.TrackFX_GetCount(tr)-1 do
        held[guid].fx[fx] = {}
        for p = 0, reaper.TrackFX_GetNumParams(tr, fx)-1 do
          local val = reaper.TrackFX_GetParam(tr, fx, p)
          held[guid].fx[fx][p] = val
          lastSnapCount = lastSnapCount + 1
        end
      end
    end
  else
    -- Take FX mode
    for i = 0, reaper.CountSelectedMediaItems(0)-1 do
      local item = reaper.GetSelectedMediaItem(0, i)
      local take = reaper.GetActiveTake(item)
      if take then
        local guid = GetSourceGUID(item)
        held[guid] = { type="take", source=take, fx = {} }
        for fx = 0, reaper.TakeFX_GetCount(take)-1 do
          held[guid].fx[fx] = {}
          for p = 0, reaper.TakeFX_GetNumParams(take, fx)-1 do
            local val = reaper.TakeFX_GetParam(take, fx, p)
            held[guid].fx[fx][p] = val
            lastSnapCount = lastSnapCount + 1
          end
        end
      end
    end
  end

  -- init checked flags
  for id, data in pairs(held) do
    checked[id] = { fx = {} }
    for fxIdx, params in pairs(data.fx) do
      checked[id].fx[fxIdx] = {}
      for pIdx in pairs(params) do
        checked[id].fx[fxIdx][pIdx] = true
      end
    end
  end
end

-- Ensure an envelope exists (track or take), arm & show it
local function EnsureEnvelope(data, fxIdx, parmIdx)
  local env
  if data.type == "track" then
    env = reaper.GetFXEnvelope(data.source, fxIdx, parmIdx, true)
  else
    env = reaper.TakeFX_GetEnvelope(data.source, fxIdx, parmIdx, true)
  end
  if env then
    local _, chunk = reaper.GetEnvelopeStateChunk(env, "", false)
    chunk = chunk
      :gsub("VIS %d","VIS 1")
      :gsub("ARM %d","ARM 1")
    reaper.SetEnvelopeStateChunk(env, chunk, false)
  end
  return env
end

-- Write a point
local function WritePoint(env, time, value, shape, tension)
  shape   = shape   or 0
  tension = tension or 0
  reaper.InsertEnvelopePoint(env, time, value, shape, tension, false, true)
end

-- ########################################
-- ## WRITE AUTOMATION                  ##
-- ########################################
local function WriteAutomation()
  local t0,t1 = reaper.GetSet_LoopTimeRange(false,false,0,0,false)
  local cur   = reaper.GetCursorPosition()
  local times = {}

  if writeMode == 1 then
    times = { cur }
  else
    times = (t1>t0) and {t0,t1} or {cur}
  end

  for id, data in pairs(held) do
    for fxIdx, params in pairs(data.fx) do
      for pIdx, val in pairs(params) do
        if checked[id].fx[fxIdx][pIdx] then
          local env = EnsureEnvelope(data, fxIdx, pIdx)
          if env then
            for _, tm in ipairs(times) do
              if data.type=="take" then
                local item = reaper.GetMediaItemTake_Item(data.source)
                local itemPos = reaper.GetMediaItemInfo_Value(item, "D_POSITION")
                local relTime = tm - itemPos
                WritePoint(env, relTime, val)
              else
                WritePoint(env, tm, val)
              end
            end
          end
        end
      end
    end
  end

  reaper.Undo_OnStateChange("CUCO Keyframe: wrote held parameters")
end

-- ########################################
-- ## GUI (ReaImGui)                    ##
-- ########################################
local ctx = reaper.ImGui_CreateContext('CUCO Keyframe')

local function loop()
  reaper.ImGui_SetNextWindowSize(ctx, 480, 600, reaper.ImGui_Cond_FirstUseEver())
  if reaper.ImGui_Begin(ctx, 'CUCO Keyframe', true) then

    -- Target mode
    if reaper.ImGui_RadioButton(ctx, 'Track FX', targetMode==1) then targetMode=1 end
    reaper.ImGui_SameLine(ctx)
    if reaper.ImGui_RadioButton(ctx, 'Take FX',  targetMode==2) then targetMode=2 end

    reaper.ImGui_Separator(ctx)

    -- Write / Hold
    if reaper.ImGui_Button(ctx, 'Write Held to Automation') then
      WriteAutomation()
    end
    reaper.ImGui_SameLine(ctx)
    if reaper.ImGui_Button(ctx, 'Hold Current Values') then
      CaptureSnapshot()
    end

    -- Snapshot feedback
    if lastSnapTime then
      reaper.ImGui_Text(ctx,
        string.format('Last snap at %.3f s (%d params)', lastSnapTime, lastSnapCount)
      )
    end

    reaper.ImGui_Separator(ctx)

    -- Write mode
    if reaper.ImGui_RadioButton(ctx, 'At Cursor',           writeMode==1) then writeMode=1 end
    reaper.ImGui_SameLine(ctx)
    if reaper.ImGui_RadioButton(ctx, 'At Sel Start & End', writeMode==2) then writeMode=2 end

    reaper.ImGui_Separator(ctx)

    -- Parameters checklist
    if next(held) then
      for id, data in pairs(held) do
        local label = (data.type=="track") and "Track" or "Take"
        local name  = data.type=="track"
          and ({reaper.GetTrackName(data.source, "")})[2] or ""
        if reaper.ImGui_TreeNode(ctx, label..' '..id..' '..name) then
          for fxIdx, params in pairs(data.fx) do
            local fxName = data.type=="track"
              and ({reaper.TrackFX_GetFXName(data.source, fxIdx, "")})[2]
              or ({reaper.TakeFX_GetFXName(data.source, fxIdx, "")})[2]
            if reaper.ImGui_TreeNode(ctx, fxName) then
              for pIdx, val in pairs(params) do
                local pName = data.type=="track"
                  and ({reaper.TrackFX_GetParamName(data.source,fxIdx,pIdx,"")})[2]
                  or ({reaper.TakeFX_GetParamName(data.source,fxIdx,pIdx,"")})[2]
                local key  = id..'.fx'..fxIdx..'.'..pIdx
                local flag = checked[id].fx[fxIdx][pIdx]
                if reaper.ImGui_Checkbox(ctx, key, flag) then
                  checked[id].fx[fxIdx][pIdx] = not flag
                end
                reaper.ImGui_SameLine(ctx)
                reaper.ImGui_Text(ctx, pName..': '..string.format('%.3f',val))
              end
              reaper.ImGui_TreePop(ctx)
            end
          end
          reaper.ImGui_TreePop(ctx)
        end
      end
    else
      reaper.ImGui_Text(ctx, '(No snapshot held yet)')
    end

    reaper.ImGui_End(ctx)
  end
  reaper.defer(loop)
end

reaper.defer(loop)
