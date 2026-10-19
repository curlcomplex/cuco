-- Dialogue Prep step 5: add each cleaned file as the clip's active take (original kept underneath), then save.
-- rx_map.tsv rows: id, track, item index, item position, cleaned file, handle (s)
package.path = (debug.getinfo(1, "S").source:match("^@(.+/)") or "") .. "../modules/?.lua;" .. package.path
local J = require("dp_job")

J.run("add_takes", function(D, C)
  local proj = J.find_project(C.project)
  if not proj then return J.status(D, "add_takes", "ABORT no open project tab matching " .. C.project) end
  local rows = J.rows(D .. "/rx_map.tsv")
  -- check everything before touching anything: the clips must still be where the dump found them
  local items = {}
  for i, r in ipairs(rows) do
    local tr = reaper.GetTrack(proj, tonumber(r[2]) - 1)
    local it = tr and reaper.GetTrackMediaItem(tr, tonumber(r[3]))
    if not it or math.abs(reaper.GetMediaItemInfo_Value(it, "D_POSITION") - tonumber(r[4])) > 1e-6
      or reaper.GetTakeName(reaper.GetActiveTake(it)):find("_RX_", 1, true) then
      return J.status(D, "add_takes", "ABORT clip " .. r[1] .. " moved or changed since the dump; nothing applied")
    end
    items[i] = it
  end
  reaper.SelectProjectInstance(proj)
  reaper.Undo_BeginBlock2(proj)
  for i, r in ipairs(rows) do
    local tk = reaper.AddTakeToMediaItem(items[i])
    reaper.SetMediaItemTake_Source(tk, reaper.PCM_Source_CreateFromFile(r[5]))
    reaper.SetMediaItemTakeInfo_Value(tk, "D_STARTOFFS", tonumber(r[6]))
    reaper.SetMediaItemTakeInfo_Value(tk, "I_CHANMODE", 0)
    reaper.GetSetMediaItemTakeInfo_String(tk, "P_NAME", r[5]:match("([^/]+)$"), true)
    reaper.SetActiveTake(tk)
  end
  reaper.Undo_EndBlock2(proj, "Dialogue Prep: add De-crackle + HPF takes", -1)
  reaper.UpdateArrange()
  reaper.Main_SaveProject(proj, false)
  J.status(D, "add_takes", "DONE " .. #rows .. " takes added, project saved")
end)
