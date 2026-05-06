-- watcher.lua (modules/watcher.lua)
-- CUCO-DIFF watcher module
-- Tracks active user time inside Reaper sessions with AFK detection.

-- Set up module path
local info = debug.getinfo(1,'S')
local script_path = info.source:match[[^@?(.*[\/])[^\/]-$]]
package.path = package.path .. ';' .. script_path .. '?.lua'

local data_store = require('data_store')
local utils = require('utils')

local watcher = {}

-- Configurable defaults
watcher.config = {
  poll_interval = 10,       -- seconds between ticks
  afk_threshold = 60,       -- seconds of inactivity before pausing accounting
  extstate_namespace = 'CUCO-DIFF',
}

-- Runtime state
watcher.state = {
  project_path = nil,
  total_time = 0,
  last_active = os.time(),
  last_tick = os.time(),
  is_running = false,
  source = 'watcher',
  last_undo_count = nil,
  last_input_time = os.time(),
}

local R = rawget(_G, 'reaper')

-- Internal: update input activity using undo state and transport heuristics
local function update_input_activity(now)
  if R and R.GetProjectStateChangeCount then
    local proj = 0 -- current project
    local c = R.GetProjectStateChangeCount(proj)
    if watcher.state.last_undo_count == nil then
      watcher.state.last_undo_count = c
      watcher.state.last_input_time = now
    elseif c ~= watcher.state.last_undo_count then
      watcher.state.last_undo_count = c
      watcher.state.last_input_time = now
    end
  end
  if R and R.GetPlayState then
    local ps = R.GetPlayState()
    if ps == 1 or ps == 4 then -- playing or recording
      watcher.state.last_input_time = now
    end
  end
  -- outside Reaper or no signals: keep last_input_time as-is
  return watcher.state.last_input_time
end

local function flush()
  if not watcher.state.project_path then return end
  local payload = {
    project_path = watcher.state.project_path,
    total_time = watcher.state.total_time,
    last_active = watcher.state.last_active,
    afk_threshold = watcher.config.afk_threshold,
    source = watcher.state.source,
    last_save = os.time(),
  }
  data_store.SaveProjectData(watcher.state.project_path, payload)
end

-- Public API
function watcher.Init(cfg)
  cfg = cfg or {}
  for k, v in pairs(cfg) do watcher.config[k] = v end
  return watcher
end

function watcher.Start(project_path)
  watcher.state.project_path = project_path or (R and select(2, R.EnumProjects(-1))) or 'unknown_project'
  watcher.state.last_active = os.time()
  watcher.state.last_tick = os.time()
  watcher.state.is_running = true

  -- In Reaper, establish a defer loop
  if R and R.defer then
    local function loop()
      if not watcher.state.is_running then return end
      watcher.Tick()
      R.defer(loop)
    end
    R.defer(loop)
  end
end

function watcher.Stop()
  watcher.state.is_running = false
  flush()
end

function watcher.Tick()
  local now = os.time()
  local dt = now - (watcher.state.last_tick or now)
  watcher.state.last_tick = now

  -- Skip if below poll interval when driven by external schedulers
  if dt < watcher.config.poll_interval then return end

  local last_input = update_input_activity(now)
  local inactive_for = now - (last_input or now)

  if inactive_for <= watcher.config.afk_threshold then
    watcher.state.total_time = (watcher.state.total_time or 0) + dt
    watcher.state.last_active = now
  end

  -- Periodically flush (on each tick for simplicity)
  flush()
end

-- Utility for formatting current total time
function watcher.GetFormattedTotal()
  return utils.FormatSeconds(watcher.state.total_time or 0)
end

return watcher
