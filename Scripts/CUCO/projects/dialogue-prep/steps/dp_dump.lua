-- Dialogue Prep step 1: list the active, unmuted audio clips on the job's tracks -> clips.tsv
package.path = (debug.getinfo(1, "S").source:match("^@(.+/)") or "") .. "../modules/?.lua;" .. package.path
local J = require("dp_job")

J.run("dump", function(D, C)
  local proj, fn = J.find_project(C.project)
  if not proj then return J.status(D, "dump", "ABORT no open project tab matching " .. C.project) end
  local f = io.open(D .. "/project.txt", "w") f:write(fn, "\n") f:close()
  local out = io.open(D .. "/clips.tsv", "w")
  local n, done = 0, 0
  for tn in C.tracks:gmatch("%d+") do
    local tr = reaper.GetTrack(proj, tonumber(tn) - 1)
    if not tr then out:close() return J.status(D, "dump", "ABORT no track " .. tn) end
    for k = 0, reaper.CountTrackMediaItems(tr) - 1 do
      local it = reaper.GetTrackMediaItem(tr, k)
      local tk = reaper.GetActiveTake(it)
      if tk and not reaper.TakeIsMIDI(tk) and reaper.GetMediaItemInfo_Value(it, "B_MUTE") == 0 then
        if reaper.GetTakeName(tk):find("_RX_", 1, true) then
          done = done + 1 -- already processed
        else
          out:write(table.concat({tn .. "-" .. k, tn, k,
            reaper.GetMediaItemInfo_Value(it, "D_POSITION"), reaper.GetMediaItemInfo_Value(it, "D_LENGTH"),
            reaper.GetMediaItemTakeInfo_Value(tk, "D_STARTOFFS"), reaper.GetMediaItemTakeInfo_Value(tk, "D_PLAYRATE"),
            reaper.GetMediaItemTakeInfo_Value(tk, "I_CHANMODE"),
            reaper.GetMediaSourceFileName(reaper.GetMediaItemTake_Source(tk))}, "\t"), "\n")
          n = n + 1
        end
      end
    end
  end
  out:close()
  J.status(D, "dump", "DONE " .. n .. " clips (" .. done .. " already processed, skipped)")
end)
