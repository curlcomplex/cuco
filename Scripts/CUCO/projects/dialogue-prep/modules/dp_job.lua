-- Shared plumbing for the Dialogue Prep step scripts.
-- The Python driver writes ~/.cuco/dialogue-prep/current.txt (path of the job dir) and <job>/job.txt (key=value).
-- Each step reports through <job>/<step>.status: first word DONE or ABORT, then a message.
local M = {}

function M.dir()
  local f = assert(io.open(os.getenv("HOME") .. "/.cuco/dialogue-prep/current.txt"), "no current Dialogue Prep job")
  local d = f:read("l")
  f:close()
  return d
end

function M.cfg(dir)
  local t = {}
  for l in io.lines(dir .. "/job.txt") do
    local k, v = l:match("^(%w+)=(.*)$")
    if k then t[k] = v end
  end
  return t
end

function M.status(dir, step, msg)
  local f = io.open(dir .. "/" .. step .. ".status", "w")
  f:write(msg, "\n")
  f:close()
end

function M.rows(path)
  local out = {}
  for l in io.lines(path) do
    local r = {}
    for v in (l .. "\t"):gmatch("([^\t]*)\t") do r[#r + 1] = v end
    out[#out + 1] = r
  end
  return out
end

-- First open project tab whose file path contains `sub` (plain match).
function M.find_project(sub)
  local i = 0
  while true do
    local p, fn = reaper.EnumProjects(i)
    if not p then return nil end
    if fn:find(sub, 1, true) then return p, fn end
    i = i + 1
  end
end

-- Run main() so any Lua error becomes an ABORT status instead of a modal REAPER error dialog.
function M.run(step, main)
  local dir = M.dir()
  local ok, err = xpcall(main, debug.traceback, dir, M.cfg(dir))
  if not ok then M.status(dir, step, "ABORT " .. tostring(err)) end
end

return M
