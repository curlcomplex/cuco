-- Dialogue Prep step 6: write planned item gain + take volume envelope to every clip, then save.
-- plans.tsv lists plan files; each plan: first line "track item item_db", then "time amplitude" lines.
package.path = (debug.getinfo(1, "S").source:match("^@(.+/)") or "") .. "../modules/?.lua;" .. package.path
local J = require("dp_job")

local TAKE_VOLUME_ENVELOPE = 40693 -- Take: Toggle take volume envelope

J.run("apply_gain", function(D, C)
  local proj = J.find_project(C.project)
  if not proj then return J.status(D, "apply_gain", "ABORT no open project tab matching " .. C.project) end
  local plans = {}
  for _, r in ipairs(J.rows(D .. "/plans.tsv")) do
    local lines = {}
    for l in io.lines(r[1]) do lines[#lines + 1] = l end
    local tn, k, db = lines[1]:match("(%S+) (%S+) (%S+)")
    local tr = reaper.GetTrack(proj, tonumber(tn) - 1)
    local it = tr and reaper.GetTrackMediaItem(tr, tonumber(k))
    if not it or not reaper.GetTakeName(reaper.GetActiveTake(it)):find("_RX_", 1, true) then
      return J.status(D, "apply_gain", "ABORT clip " .. tn .. "-" .. k .. " has no active RX take; nothing applied")
    end
    plans[#plans + 1] = { it = it, db = tonumber(db), lines = lines }
  end
  reaper.SelectProjectInstance(proj)
  reaper.Undo_BeginBlock2(proj)
  for _, p in ipairs(plans) do
    local tk = reaper.GetActiveTake(p.it)
    reaper.SetMediaItemInfo_Value(p.it, "D_VOL", 10 ^ (p.db / 20))
    local env = reaper.GetTakeEnvelopeByName(tk, "Volume")
    if not env then
      reaper.Main_OnCommand(40289, 0)
      reaper.SetMediaItemSelected(p.it, true)
      reaper.Main_OnCommand(TAKE_VOLUME_ENVELOPE, 0)
      env = reaper.GetTakeEnvelopeByName(tk, "Volume")
    end
    local mode = reaper.GetEnvelopeScalingMode(env)
    reaper.DeleteEnvelopePointRange(env, -1, reaper.GetMediaItemInfo_Value(p.it, "D_LENGTH") + 1)
    for i = 2, #p.lines do
      local t, a = p.lines[i]:match("(%S+) (%S+)")
      reaper.InsertEnvelopePoint(env, tonumber(t), reaper.ScaleToEnvelopeMode(mode, tonumber(a)), 0, 0, false, true)
    end
    reaper.Envelope_SortPoints(env)
  end
  reaper.Main_OnCommand(40289, 0)
  reaper.Undo_EndBlock2(proj, "Dialogue Prep: clip gain (setting E) on " .. #plans .. " clips", -1)
  reaper.UpdateArrange()
  reaper.Main_SaveProject(proj, false)
  J.status(D, "apply_gain", "DONE " .. #plans .. " clips, project saved")
end)
