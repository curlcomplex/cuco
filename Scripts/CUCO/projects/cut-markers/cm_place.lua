-- Cut Markers REAPER step: reads ~/.cuco/cut-markers/job.txt (project=, clear=, then "time<TAB>name" rows),
-- adds the markers to that project tab in one undo block, writes DONE/ABORT to ~/.cuco/cut-markers/status.
local dir = os.getenv("HOME") .. "/.cuco/cut-markers/"

local function status(msg)
  local f = io.open(dir .. "status", "w")
  f:write(msg, "\n")
  f:close()
end

local function main()
  local cfg, rows = {}, {}
  for l in io.lines(dir .. "job.txt") do
    local t, n = l:match("^([%d.]+)\t(.+)$")
    if t then rows[#rows + 1] = { tonumber(t), n } else
      local k, v = l:match("^(%w+)=(.*)$")
      if k then cfg[k] = v end
    end
  end
  local proj, i = nil, 0
  while true do
    local p, fn = reaper.EnumProjects(i)
    if not p then break end
    if fn:find(cfg.project, 1, true) then proj = p break end
    i = i + 1
  end
  if not proj then return status("ABORT no open tab matches " .. cfg.project) end

  local old = {}
  for j = 0, reaper.CountProjectMarkers(proj) - 1 do
    local _, isr, _, _, name = reaper.EnumProjectMarkers3(proj, j)
    if not isr then old[#old + 1] = j end
    if not isr and cfg.clear ~= "1" and name:match("^CUT%??$") then
      return status("ABORT cut markers already there; rerun with --clear")
    end
  end

  reaper.Undo_BeginBlock2(proj)
  if cfg.clear == "1" then
    for j = #old, 1, -1 do reaper.DeleteProjectMarkerByIndex(proj, old[j]) end
  end
  local col = reaper.ColorToNative(255, 140, 0) | 0x1000000
  for _, r in ipairs(rows) do reaper.AddProjectMarker2(proj, false, r[1], 0, r[2], -1, col) end
  reaper.Undo_EndBlock2(proj, "Picture cut markers", -1)
  local _, nm, nr = reaper.CountProjectMarkers(proj)
  status(string.format("DONE %d cut markers added%s; project now has %d markers, %d regions",
    #rows, cfg.clear == "1" and (", " .. #old .. " removed") or "", nm, nr))
end

local ok, err = xpcall(main, debug.traceback)
if not ok then status("ABORT " .. tostring(err)) end
