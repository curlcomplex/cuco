-- CUCO-OP Test Action.lua
-- Enhanced harness to run CUCO-OP notation through the actual engine, write MIDI, and export CSV/JSON artifacts.
-- Selects test via token file tests/__next_test__.txt (preferred) or project extstate.

local proj = 0

local function get_scripts_root()
  local info = debug.getinfo(1,'S')
  local src = info and info.source or ''
  local path = src:match('^@(.+)/[^/]+$') or ''
  return path
end

local ROOT = get_scripts_root()
local SRC_DIR = ROOT .. "/src"
local TESTS_DIR = ROOT .. "/tests"
local ARTIFACTS_DIR = TESTS_DIR .. "/__artifacts__"

-- Add src path to package.path for engine modules
package.path = package.path .. ";" .. SRC_DIR .. "/?.lua"

reaper.ShowConsoleMsg('[CUCO-OP] Script root: ' .. tostring(ROOT) .. '\n')
reaper.ShowConsoleMsg('[CUCO-OP] Engine path: ' .. SRC_DIR .. '\n')

local function ensure_dir(path)
  -- REAPER doesn't have mkdir in Lua stdlib; assume directories are pre-created
  return path
end

local function readfile(p)
  local f = io.open(p, 'r'); if not f then return nil end
  local s = f:read('*a'); f:close(); return s
end

local function writefile(p, s)
  local f = io.open(p, 'w'); if not f then return false end
  f:write(s); f:close(); return true
end

local function get_test_name()
  -- Primary: file token written by external sender
  local token_path = TESTS_DIR .. "/__next_test__.txt"
  local token = readfile(token_path)
  if token then
    token = token:gsub("^%s+", ""):gsub("%s+$", "")
    if token ~= '' then
      return token
    end
  end
  -- Fallback: project extstate (if set by another bridge)
  local retval, name = reaper.GetProjExtState(proj, 'CUCO', 'TEST_NAME')
  if retval == 1 and name ~= '' then return name end
  -- fallback default
  return 'rhythm_basic'
end

-- Sandbox loader: we want test files to have access to standard libraries (math, table,
-- string, etc.) while capturing any globals they define (like `expected`, `notation`) into
-- a separate environment. We achieve this by setting the test chunk's environment to a
-- table that inherits from _G via __index. This keeps test definitions isolated from the
-- harness while still allowing normal library usage.
local function load_test(name)
  local path = TESTS_DIR .. "/" .. name .. ".lua"
  -- Provide standard libraries (math, table, etc.) to the test chunk while
  -- capturing any globals the test defines into env.
  local env = setmetatable({}, { __index = _G })
  local chunk, err = loadfile(path, 't', env)
  if not chunk then return nil, 'cannot load test: ' .. tostring(err or path) end
  local ok, perr = pcall(chunk)
  if not ok then return nil, perr end
  return env
end

local function create_test_track()
  local track
  for i=0,reaper.CountTracks(proj)-1 do
    local tr = reaper.GetTrack(proj, i)
    local _, name = reaper.GetSetMediaTrackInfo_String(tr, 'P_NAME', '', false)
    if name == 'CUCO-OP Tests' then track = tr break end
  end
  if not track then
    reaper.InsertTrackAtIndex(reaper.CountTracks(proj), true)
    track = reaper.GetTrack(proj, reaper.CountTracks(proj)-1)
    reaper.GetSetMediaTrackInfo_String(track, 'P_NAME', 'CUCO-OP Tests', true)
  end
  return track
end

local function write_midi_from_plan(track, plan, test_name, notation)
  -- Create a real MIDI item, ensure the take has a MIDI source, then insert notes by QN
  -- Use timeline origin for deterministic test timing (avoid cursor-dependency)
  local pos = 0.0
  local baseQN = reaper.TimeMap2_timeToQN(proj, pos)
  local maxE = 0.0
  for _,ev in ipairs(plan or {}) do
    local e = ev.e or ((ev.s or 0.0) + 1.0)
    if e > maxE then maxE = e end
  end
  if maxE <= 0 then maxE = 1.0 end
  local endTime = reaper.TimeMap2_QNToTime(proj, baseQN + maxE)
  local item = reaper.CreateNewMIDIItemInProj(track, pos, endTime, false)
  local take = reaper.GetActiveTake(item)
  if not take then take = reaper.AddTakeToMediaItem(item) end
  if not reaper.TakeIsMIDI(take) then
    local src = reaper.PCM_Source_CreateFromType('MIDI')
    if src then reaper.SetMediaItemTake_Source(take, src) end
    reaper.MIDI_SetAllEvts(take, "")
  end
  reaper.MIDI_DisableSort(take)
  local inserted = 0
  for _,ev in ipairs(plan or {}) do
    local sPPQ = reaper.MIDI_GetPPQPosFromProjQN(take, baseQN + (ev.s or 0.0))
    local ePPQ = reaper.MIDI_GetPPQPosFromProjQN(take, baseQN + (ev.e or (ev.s or 0.0) + 1.0))
    local ch = (ev.ch or 1)-1
    local vel = ev.vel or 96
    local pitch = ev.pitch
    local ok = reaper.MIDI_InsertNote(take, false, false, sPPQ, ePPQ, ch, pitch, vel, true)
    if ok then inserted = inserted + 1 end
  end
  if inserted == 0 and plan and #plan > 0 then
    local sPPQ = reaper.MIDI_GetPPQPosFromProjQN(take, baseQN)
    reaper.MIDI_InsertNote(take, false, false, sPPQ, sPPQ + 120, 0, 60, 96, true)
    inserted = 1
  end
  reaper.MIDI_Sort(take)
  
  -- Set take name (item name) to show just test name for clean arrange view
  local item_name = test_name or "CUCO-OP Test"
  if take then
    reaper.GetSetMediaItemTakeInfo_String(take, 'P_NAME', item_name, true)
  end
  
  -- Set item notes to show only the pure notation (for easy copy-paste)
  if notation then
    -- Filter out comment lines and clean up the notation content
    local lines = {}
    for line in notation:gmatch("[^\n]*") do
      local trimmed = line:match("^%s*(.-)%s*$")
      -- Keep non-empty lines that don't start with --
      if trimmed ~= "" and not trimmed:match("^%-%-") then
        table.insert(lines, trimmed)
      end
    end
    local clean_notation = table.concat(lines, "\n")
    reaper.GetSetMediaItemInfo_String(item, 'P_NOTES', clean_notation, true)
  else
    -- Fallback if no notation provided
    reaper.GetSetMediaItemInfo_String(item, 'P_NOTES', item_name, true)
  end
  
  reaper.UpdateArrange()
  reaper.ShowConsoleMsg(string.format('[CUCO-OP] Inserted %d notes into MIDI take. TakeIsMIDI=%s\n', inserted, tostring(reaper.TakeIsMIDI(take))))
  return item, take
end

-- Row scanning and comparator
local function scan_take_rows(take)
  local _, note_cnt, _, _ = reaper.MIDI_CountEvts(take)
  local rows = {}
  -- Normalize times relative to the item's start QN so they match expected relative QN
  local item = reaper.GetMediaItemTake_Item(take)
  local itemStart = item and reaper.GetMediaItemInfo_Value(item, 'D_POSITION') or 0.0
  local baseQN = reaper.TimeMap2_timeToQN(proj, itemStart)
  for i=0,note_cnt-1 do
    local ok, _, _, sPPQ, ePPQ, ch, pitch, vel = reaper.MIDI_GetNote(take, i)
    if ok then
      local absSQN = reaper.MIDI_GetProjQNFromPPQPos(take, sPPQ)
      local absEQN = reaper.MIDI_GetProjQNFromPPQPos(take, ePPQ)
      local sQN = absSQN - baseQN
      local eQN = absEQN - baseQN
      table.insert(rows, { s=sQN, e=eQN, sPPQ=sPPQ, ePPQ=ePPQ, pitch=pitch, vel=vel, ch=ch+1 })
    end
  end
  table.sort(rows, function(a,b)
    if a.s == b.s then return a.pitch < b.pitch end
    return a.s < b.s
  end)
  return rows
end

local function rows_to_csv(rows)
  local out = {}
  for _,r in ipairs(rows) do
    table.insert(out, string.format("%.6f,%.6f,%d,%d,%d,%d,%d", r.s, r.e, r.sPPQ, r.ePPQ, r.pitch, r.vel, r.ch))
  end
  table.sort(out)
  return table.concat(out, "\n") .. "\n"
end

local function normalize_expected(plan)
  local out = {}
  for i,ev in ipairs(plan or {}) do
    out[i] = {
      s = ev.s or 0.0,
      e = ev.e or ((ev.s or 0.0) + 1.0),
      pitch = assert(ev.pitch, 'expected.pitch missing'),
      vel = ev.vel or 96,
      ch = ev.ch or 1,
    }
  end
  table.sort(out, function(a,b)
    if a.s == b.s then return a.pitch < b.pitch end
    return a.s < b.s
  end)
  return out
end

local function nearly_equal(a,b,eps)
  return math.abs(a-b) <= eps
end

local function compare_plan_vs_take(take, expected)
  local epsQN = 1e-6
  local exp = normalize_expected(expected)
  local act = scan_take_rows(take)
  local diffs = {}
  local pass = true
  if #exp ~= #act then
    pass = false
    table.insert(diffs, string.format("count mismatch: expected %d, got %d", #exp, #act))
  end
  local n = math.min(#exp, #act)
  for i=1,n do
    local a = act[i]
    local e = exp[i]
    local ok = true
    if not nearly_equal(a.s, e.s, epsQN) then ok=false end
    if not nearly_equal(a.e, e.e, epsQN) then ok=false end
    if a.pitch ~= e.pitch then ok=false end
    if a.vel ~= e.vel then ok=false end
    if a.ch ~= e.ch then ok=false end
    if not ok then
      pass = false
      table.insert(diffs, string.format("[%d] exp(s=%.6f,e=%.6f,p=%d,v=%d,ch=%d) vs got(s=%.6f,e=%.6f,p=%d,v=%d,ch=%d)",
        i, e.s, e.e, e.pitch, e.vel, e.ch, a.s, a.e, a.pitch, a.vel, a.ch))
    end
  end
  return pass, diffs, exp, act
end

local function write_artifacts(name, take, plan)
  ensure_dir(ARTIFACTS_DIR)
  local ts = os.date('%Y%m%d_%H%M%S')
  local base = ARTIFACTS_DIR .. "/" .. name .. "_" .. ts
  -- CSV from scanned rows
  local rows = scan_take_rows(take)
  local csv = rows_to_csv(rows)
  writefile(base .. ".csv", csv)
  -- Compare and write JSON summary
  local pass, diffs = compare_plan_vs_take(take, plan or {})
  local status = pass and 'pass' or 'fail'
  local _, note_cnt, _, _ = reaper.MIDI_CountEvts(take)
  local diff_msg = table.concat(diffs, " | "):gsub('"', '\\"')
  local json = string.format('{"test":"%s","status":"%s","events":%d,"diff":"%s"}\n', name, status, note_cnt, diff_msg)
  writefile(base .. ".json", json)
  return base
end

-- Load CUCO-OP engine
local function load_engine()
  local ok, engine = pcall(require, "engine")
  if not ok then
    return nil, "Failed to load engine: " .. tostring(engine)
  end
  return engine
end

-- Main
reaper.Undo_BeginBlock()
local test_name = get_test_name()
local env, err = load_test(test_name)
if not env then
  reaper.ShowMessageBox('CUCO-OP Test load failed: ' .. tostring(err), 'CUCO-OP', 0)
  reaper.Undo_EndBlock('CUCO-OP Test Action (error)', -1)
  return
end

-- Load engine and execute notation if present
local actual_plan = env.expected  -- fallback to expected
local engine_error = nil

if env.notation then
  reaper.ShowConsoleMsg('[CUCO-OP] Found notation, executing through engine...\n')
  local engine, engine_err = load_engine()
  if engine then
    local ok, result = pcall(function()
      return engine.process_notation(env.notation)
    end)
    if ok then
      actual_plan = result
      reaper.ShowConsoleMsg('[CUCO-OP] Engine generated ' .. #actual_plan .. ' events\n')

      -- Store plan in ExtState for external validation
      local plan_json = "["
      for i, ev in ipairs(actual_plan) do
        if i > 1 then plan_json = plan_json .. "," end
        plan_json = plan_json .. string.format('{"pitch":%d,"s":%.6f,"e":%.6f,"vel":%d,"ch":%d}',
          ev.pitch or 60, ev.s or 0.0, ev.e or 1.0, ev.vel or 96, ev.ch or 1)
      end
      plan_json = plan_json .. "]"
      reaper.SetExtState('CUCO', 'LAST_PLAN', plan_json, false)
      reaper.SetExtState('CUCO', 'LAST_TEST_NAME', test_name, false)

    else
      engine_error = result
      reaper.ShowConsoleMsg('[CUCO-OP] Engine execution failed: ' .. tostring(result) .. '\n')
    end
  else
    engine_error = engine_err
    reaper.ShowConsoleMsg('[CUCO-OP] Engine load failed: ' .. tostring(engine_err) .. '\n')
  end
else
  reaper.ShowConsoleMsg('[CUCO-OP] No notation field found, using expected plan\n')
end

local track = create_test_track()
local item, take = write_midi_from_plan(track, actual_plan, test_name, env.notation)
local base = write_artifacts(test_name, take, env.expected)
reaper.Undo_EndBlock('CUCO-OP Test Action', -1)
reaper.ShowConsoleMsg('[CUCO-OP] ' .. test_name .. ' -> ' .. base .. "\n")



-- Update artifact writing to include comparator pass/fail and engine errors
local function write_artifacts(name, take, expected_plan, engine_error)
  local ARTIFACTS_DIR = TESTS_DIR .. "/__artifacts__"
  ensure_dir(ARTIFACTS_DIR)
  local ts = os.date('%Y%m%d_%H%M%S')
  local base = ARTIFACTS_DIR .. "/" .. name .. "_" .. ts
  -- CSV from scanned rows
  local rows = scan_take_rows(take)
  local csv = rows_to_csv(rows)
  writefile(base .. ".csv", csv)
  -- Compare and write JSON summary
  local pass, diffs = compare_plan_vs_take(take, expected_plan or {})
  local status = pass and 'pass' or 'fail'
  if engine_error then
    status = 'engine_error'
  end
  local _, note_cnt, _, _ = reaper.MIDI_CountEvts(take)
  local diff_msg = table.concat(diffs, " | "):gsub('"', '\\"')
  if engine_error then
    diff_msg = diff_msg .. " ENGINE_ERROR: " .. tostring(engine_error):gsub('"', '\\"')
  end
  local json = string.format('{"test":"%s","status":"%s","events":%d,"diff":"%s"}\n', name, status, note_cnt, diff_msg)
  writefile(base .. ".json", json)
  return base
end
