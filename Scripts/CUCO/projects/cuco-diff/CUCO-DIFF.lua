-- CUCO-DIFF.lua
-- Main entry point for the CUCO-DIFF ReaScript

-- Add libraries and modules to package path
local info = debug.getinfo(1,'S')
local script_path = info.source:match[[^@?(.*[\/])[^\/]-$]]
package.path = package.path .. ';' .. script_path .. 'libraries/?.lua'
package.path = package.path .. ';' .. script_path .. 'modules/?.lua'

local watcher = require('watcher')
local diff_engine = require('diff_engine')
local data_store = require('data_store')
local ui = require('ui_main')

-- Safe reference to Reaper API
local R = rawget(_G, 'reaper')

local M = {}

local function exists(path)
  local f = io.open(path, 'r'); if f then f:close(); return true end; return false
end

local function log(msg)
  if R and R.ShowConsoleMsg then R.ShowConsoleMsg(tostring(msg) .. "\n") end
end

local function write_json(path, tbl)
  local json = require('json_wrapper')
  local ok, payload = pcall(function() return json.encode(tbl) end)
  if not ok then return false end
  local f = io.open(path, 'w'); if not f then return false end
  f:write(payload); f:close(); return true
end

local function list_rpp(dir)
  local out = {}
  if not R or not R.EnumerateFiles then return out end
  local i = 0
  while true do
    local name = R.EnumerateFiles(dir, i)
    if not name then break end
    if name:lower():match('%.rpp$') then table.insert(out, dir .. name) end
    i = i + 1
  end
  table.sort(out)
  return out
end

local function find_sample_pair()
  local samples_dir = script_path .. 'samples/'
  local v1 = samples_dir .. 'Project_V01.rpp'
  local v2 = samples_dir .. 'Project_V02.rpp'
  if exists(v1) and exists(v2) then return v1, v2 end
  -- Fallback: pick first two .rpp files in samples
  local files = list_rpp(samples_dir)
  if #files >= 2 then return files[#files-1], files[#files] end
  return nil, nil
end

function M.Main()
  -- Initialize modules
  watcher.Init()
  watcher.Start()
  ui.Init()

  local older, newer = find_sample_pair()
  if older and newer then
    local result = diff_engine.CompareFiles(older, newer)
    log('CUCO-DIFF: Sample diff run:')
    log('From: ' .. older)
    log('To  : ' .. newer)
    log('Summary: ' .. (result.summary or ''))
    log('Events:')
    for i, e in ipairs(result.events or {}) do
      log(string.format('- [%s] %s', e.type or 'UNKNOWN', e.description or ''))
    end
    local out_json = newer .. '.cuco-diff.json'
    if write_json(out_json, { summary = result.summary, timestamp = result.timestamp, events = result.events }) then
      log('Wrote JSON result: ' .. out_json)
    end
    if R and R.MB then R.MB('Sample diff complete. See ReaScript console and JSON next to newer file.', 'CUCO-DIFF', 0) end
  else
    if R and R.MB then
      R.MB('CUCO-DIFF loaded. Watcher started.\n\nTo see a sample diff, place two .rpp files in:\n' .. script_path .. 'samples/\n(e.g., Project_V01.rpp and Project_V02.rpp)\nThen re-run this script.', 'CUCO-DIFF', 0)
    end
    log('CUCO-DIFF initialized. Add two .rpp files to samples/ to run a sample diff.')
  end
end

if not ... then
  -- If run as a script directly, call Main
  M.Main()
end

return M
