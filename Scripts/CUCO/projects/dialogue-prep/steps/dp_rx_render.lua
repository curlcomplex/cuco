-- Dialogue Prep step 4: render every region through its take FX (mono), list the results, discard the scratch tab.
package.path = (debug.getinfo(1, "S").source:match("^@(.+/)") or "") .. "../modules/?.lua;" .. package.path
local J = require("dp_job")

local APPLY_MONO = 40361 -- Item: Apply track/take FX to items (mono output)

J.run("rx_render", function(D, C)
  local proj, fn = reaper.EnumProjects(-1)
  if not fn:find("dp_blank", 1, true) then return J.status(D, "rx_render", "ABORT active tab is not the scratch tab: " .. fn) end
  local name = reaper.kbd_getTextFromCmd(APPLY_MONO, 0)
  if not name:find("mono") then return J.status(D, "rx_render", "ABORT action " .. APPLY_MONO .. " is: " .. name) end
  reaper.Main_OnCommand(40289, 0) -- unselect all items
  for i = 0, reaper.CountMediaItems(proj) - 1 do reaper.SetMediaItemSelected(reaper.GetMediaItem(proj, i), true) end
  reaper.Main_OnCommand(APPLY_MONO, 0)
  local out = io.open(D .. "/renders.tsv", "w")
  local n = 0
  for i = 0, reaper.CountMediaItems(proj) - 1 do
    local it = reaper.GetMediaItem(proj, i)
    if reaper.CountTakes(it) == 2 then
      local src = reaper.GetMediaItemTake_Source(reaper.GetActiveTake(it))
      out:write(reaper.GetTakeName(reaper.GetTake(it, 0)), "\t", reaper.GetMediaSourceFileName(src), "\n")
      n = n + 1
    end
  end
  out:close()
  local total = reaper.CountMediaItems(proj)
  reaper.Main_openProject("noprompt:" .. C.blank) -- drop the scratch edits without a save prompt
  reaper.Main_OnCommand(40860, 0)                  -- close the scratch tab
  local target = J.find_project(C.project)
  if target then reaper.SelectProjectInstance(target) end
  if n ~= total then return J.status(D, "rx_render", "ABORT rendered " .. n .. " of " .. total) end
  J.status(D, "rx_render", "DONE " .. n .. " rendered")
end)
