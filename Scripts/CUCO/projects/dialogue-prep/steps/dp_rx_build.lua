-- Dialogue Prep step 2: in a scratch tab, one track per clip holding the source region with handles + De-crackle.
-- regions.tsv rows: id, source path, chanmode, start, end (source seconds)
package.path = (debug.getinfo(1, "S").source:match("^@(.+/)") or "") .. "../modules/?.lua;" .. package.path
local J = require("dp_job")

J.run("rx_build", function(D, C)
  reaper.Main_OnCommand(40859, 0) -- New project tab
  reaper.Main_openProject("noprompt:" .. C.blank)
  local proj, fn = reaper.EnumProjects(-1)
  if not fn:find("dp_blank", 1, true) then return J.status(D, "rx_build", "ABORT scratch tab did not open, active tab is " .. fn) end
  reaper.GetSetProjectInfo_String(proj, "RECORD_PATH", D .. "/renders", true)
  local n = 0
  for _, r in ipairs(J.rows(D .. "/regions.tsv")) do
    local id, src, cm, a, b = r[1], r[2], tonumber(r[3]), tonumber(r[4]), tonumber(r[5])
    reaper.InsertTrackAtIndex(n, false)
    local it = reaper.AddMediaItemToTrack(reaper.GetTrack(proj, n))
    local tk = reaper.AddTakeToMediaItem(it)
    reaper.SetMediaItemTake_Source(tk, reaper.PCM_Source_CreateFromFile(src))
    reaper.SetMediaItemInfo_Value(it, "D_POSITION", 0)
    reaper.SetMediaItemInfo_Value(it, "D_LENGTH", b - a)
    reaper.SetMediaItemTakeInfo_Value(tk, "D_STARTOFFS", a)
    reaper.SetMediaItemTakeInfo_Value(tk, "I_CHANMODE", cm)
    reaper.GetSetMediaItemTakeInfo_String(tk, "P_NAME", id, true)
    if reaper.TakeFX_AddByName(tk, C.plugin, -1) ~= 0 then
      return J.status(D, "rx_build", "ABORT could not add '" .. C.plugin .. "' to " .. id)
    end
    n = n + 1
  end
  J.status(D, "rx_build", "DONE " .. n .. " regions")
end)
