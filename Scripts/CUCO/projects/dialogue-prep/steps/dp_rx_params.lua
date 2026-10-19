-- Dialogue Prep step 3: set De-crackle Quality/Strength on every region.
-- RX 11 De-crackle ignores parameter changes unless it is processing, so this plays the scratch tab
-- (master muted) from 0 s, sets the parameters 0.5 s in, stops at 2 s and reads them back.
-- Param 0 Quality: normalized 0 Low / 1/3 Medium / 1 High. Param 1 Strength 1-10: normalized (s - 1) / 9.
package.path = (debug.getinfo(1, "S").source:match("^@(.+/)") or "") .. "../modules/?.lua;" .. package.path
local J = require("dp_job")

local QUALITY = { low = 0, medium = 1 / 3, high = 1 }

J.run("rx_params", function(D, C)
  local proj, fn = reaper.EnumProjects(-1)
  if not fn:find("dp_blank", 1, true) then return J.status(D, "rx_params", "ABORT active tab is not the scratch tab: " .. fn) end
  local q, s = QUALITY[C.quality], tonumber(C.strength)
  local takes = {}
  for t = 0, reaper.CountTracks(proj) - 1 do takes[#takes + 1] = reaper.GetActiveTake(reaper.GetTrackMediaItem(reaper.GetTrack(proj, t), 0)) end
  local master = reaper.GetMasterTrack(proj)
  reaper.SetMediaTrackInfo_Value(master, "B_MUTE", 1)
  reaper.SetEditCurPos2(proj, 0, false, false)
  reaper.CSurf_OnPlay()
  local t0, set = reaper.time_precise(), false
  local function step()
    local ok, err = xpcall(function()
      local dt = reaper.time_precise() - t0
      if dt > 0.5 and not set then
        for _, tk in ipairs(takes) do
          reaper.TakeFX_SetParamNormalized(tk, 0, 0, q)
          reaper.TakeFX_SetParamNormalized(tk, 0, 1, (s - 1) / 9)
        end
        set = true
      end
      if dt < 2 then reaper.defer(step) return end
      reaper.CSurf_OnStop()
      reaper.SetMediaTrackInfo_Value(master, "B_MUTE", 0)
      local bad = {}
      for _, tk in ipairs(takes) do
        local _, qv = reaper.TakeFX_GetFormattedParamValue(tk, 0, 0)
        local _, sv = reaper.TakeFX_GetFormattedParamValue(tk, 0, 1)
        if qv:lower() ~= C.quality or math.abs((tonumber(sv) or -1) - s) > 0.01 then
          bad[#bad + 1] = reaper.GetTakeName(tk) .. "=" .. qv .. "/" .. sv
        end
      end
      if #bad > 0 then return J.status(D, "rx_params", "ABORT parameters not applied: " .. table.concat(bad, " ")) end
      J.status(D, "rx_params", "DONE " .. #takes .. " takes at " .. C.quality .. "/" .. C.strength)
    end, debug.traceback)
    if not ok then
      reaper.CSurf_OnStop()
      reaper.SetMediaTrackInfo_Value(master, "B_MUTE", 0)
      J.status(D, "rx_params", "ABORT " .. tostring(err))
    end
  end
  reaper.defer(step)
end)
