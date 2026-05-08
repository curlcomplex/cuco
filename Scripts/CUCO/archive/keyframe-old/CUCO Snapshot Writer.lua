--[[
ReaScript Name: Snapshot Writer (FX Parameters)
Author: ChatGPT / curl-enhanced
Version: 1.4
Description: Hold & write current FX parameter values as envelope points at edit cursor or time-selection ends.
Dependencies: ReaImGui (ImGui for Reaper)
]]--

-- ########################################
-- ## GLOBAL STATE                       ##
-- ########################################
local held          = {}   -- held[trackGUID] = { track = MediaTrack, fx = { [fxidx] = { [paramidx] = value } } }
local checked       = {}   -- mirror of held: which params to write
local lastSnapTime  = nil  -- playback cursor position at last Hold
local lastSnapCount = 0    -- number of params captured
local writeMode     = 1    -- 1 = at cursor, 2 = at selection ends

-- ########################################
-- ## HELPERS                            ##
-- ########################################

local function GetTrackGUID(track)
  local _, guid = reaper.GetSetMediaTrackInfo_String(track, "GUID", "", false)
  return guid
end

-- Capture all FX parameter values on selected tracks
local function CaptureSnapshot()
  held = {}
  checked = {}
  lastSnapTime  = reaper.GetCursorPosition()
  lastSnapCount = 0

  for i = 0, reaper.CountSelectedTracks(0)-1 do
    local tr   = reaper.GetSelectedTrack(0, i)
    local guid = GetTrackGUID(tr)
    held[guid] = { track = tr, fx = {} }

    for fx = 0, reaper.TrackFX_GetCount(tr)-1 do
      held[guid].fx[fx] = {}
      for p = 0, reaper.TrackFX_GetNumParams(tr, fx)-1 do
        local val = reaper.TrackFX_GetParam(tr, fx, p)
        held[guid].fx[fx][p] = val
        lastSnapCount = lastSnapCount + 1
      end
    end
  end

  -- init checked flags
  for guid, data in pairs(held) do
    checked[guid] = { fx = {} }
    for fxIdx, params in pairs(data.fx) do
      checked[guid].fx[fxIdx] = {}
      for pIdx in pairs(params) do
        checked[guid].fx[fxIdx][pIdx] = true
      end
    end
  end
end

local function EnsureFXEnvelope(track, fxIdx, parmIdx)
  local env = reaper.GetFXEnvelope(track, fxIdx, parmIdx, true)
  if env then
    local _, chunk = reaper.GetEnvelopeStateChunk(env, "", false)
    chunk = chunk
      :gsub("VIS %d","VIS 1")
      :gsub("ARM %d","ARM 1")
    reaper.SetEnvelopeStateChunk(env, chunk, false)
  end
  return env
end

local function WritePoint(env, time, value)
  reaper.InsertEnvelopePoint(env, time, value, 0, 0, false, true)
end

-- ########################################
-- ## WRITE AUTOMATION                  ##
-- ########################################
local function WriteAutomation()
  -- decide time(s) based on writeMode
  local t0, t1 = reaper.GetSet_LoopTimeRange(false,false,0,0,false)
  local cur    = reaper.GetCursorPosition()
  local times  = {}

  if writeMode == 1 then
    times = { cur }
  else
    if t1>t0 then times = { t0, t1 }
    else           times = { cur } end
  end

  for guid, data in pairs(held) do
    local tr = data.track
    for fxIdx, params in pairs(data.fx) do
      for pIdx, val in pairs(params) do
        if checked[guid].fx[fxIdx][pIdx] then
          local env = EnsureFXEnvelope(tr, fxIdx, pIdx)
          if env then
            for _, tm in ipairs(times) do
              WritePoint(env, tm, val)
            end
          end
        end
      end
    end
  end

  reaper.Undo_OnStateChange("Snapshot Writer: wrote held parameters")
end

-- ########################################
-- ## GUI (ReaImGui)                    ##
-- ########################################
local ctx = reaper.ImGui_CreateContext('Snapshot Writer')

local function loop()
  reaper.ImGui_SetNextWindowSize(ctx, 460, 580, reaper.ImGui_Cond_FirstUseEver())
  if reaper.ImGui_Begin(ctx, 'Snapshot Writer', true) then

    -- top row: Write + Hold
    if reaper.ImGui_Button(ctx, 'Write Held to Automation') then
      WriteAutomation()
    end
    reaper.ImGui_SameLine(ctx)
    if reaper.ImGui_Button(ctx, 'Hold Current Values') then
      CaptureSnapshot()
    end

    -- snapshot feedback
    if lastSnapTime then
      reaper.ImGui_Text(ctx,
        string.format('Last snap at %.3f s (%d params)', lastSnapTime, lastSnapCount)
      )
    end

    reaper.ImGui_Separator(ctx)

    -- choose write mode
    if reaper.ImGui_RadioButton(ctx, 'At Cursor',           writeMode==1) then writeMode=1 end
    reaper.ImGui_SameLine(ctx)
    if reaper.ImGui_RadioButton(ctx, 'At Sel Start & End', writeMode==2) then writeMode=2 end

    reaper.ImGui_Separator(ctx)

    -- parameter checklist at bottom
    if next(held) then
      for guid, data in pairs(held) do
        local _, trName = reaper.GetTrackName(data.track, "")
        if reaper.ImGui_TreeNode(ctx, trName.." ("..guid..")") then
          for fxIdx, params in pairs(data.fx) do
            local _, fxName = reaper.TrackFX_GetFXName(data.track, fxIdx, "")
            if reaper.ImGui_TreeNode(ctx, fxName) then
              for pIdx, val in pairs(params) do
                local _, pName = reaper.TrackFX_GetParamName(data.track, fxIdx, pIdx, "")
                local key  = guid..'.'..fxIdx..'.'..pIdx
                local flag = checked[guid].fx[fxIdx][pIdx]
                if reaper.ImGui_Checkbox(ctx, key, flag) then
                  checked[guid].fx[fxIdx][pIdx] = not flag
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
