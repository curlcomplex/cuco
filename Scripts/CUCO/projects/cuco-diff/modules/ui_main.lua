-- ui_main.lua
-- CUCO-DIFF ReaImGui UI skeleton

local ui = {}

-- Note: real UI requires ReaImGui; this is a non-blocking skeleton for development.
ui.state = {
  projects = {},
  selected = nil,
}

function ui.Init()
  -- Initialize state, load extstate index, etc.
  return ui
end

function ui.ScanFolder(path)
  -- Scan for .rpp files and group by naming convention
  -- Outside Reaper, use Lua's lfs or io.popen('ls') as fallback
  return {}
end

function ui.Render()
  -- In Reaper: draw tables, buttons and handle interactions
end

return ui