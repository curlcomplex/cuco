-- Manual Test Runner for CUCO-OP in REAPER
-- Run this script directly in REAPER to test notation features

-- Get script directory
local function get_script_dir()
  local info = debug.getinfo(1,'S')
  local src = info and info.source or ''
  local path = src:match('^@(.+)/[^/]+$') or ''
  return path
end

local ROOT = get_script_dir()
local SRC_DIR = ROOT .. "/src"

-- Add engine path
package.path = package.path .. ";" .. SRC_DIR .. "/?.lua"

-- Test function
local function test_notation(name, notation_str, description)
  reaper.ShowConsoleMsg('\n=== Testing: ' .. name .. ' ===\n')
  reaper.ShowConsoleMsg('Description: ' .. description .. '\n')
  reaper.ShowConsoleMsg('Notation: ' .. notation_str:gsub('\n', ' ') .. '\n')

  -- Load engine
  local ok, engine = pcall(require, "engine")
  if not ok then
    reaper.ShowConsoleMsg('ERROR: Failed to load engine: ' .. tostring(engine) .. '\n')
    return false
  end

  -- Process notation
  local success, result = pcall(function()
    return engine.process_notation(notation_str)
  end)

  if success then
    reaper.ShowConsoleMsg('SUCCESS: Generated ' .. #result .. ' events\n')
    for i, event in ipairs(result) do
      reaper.ShowConsoleMsg(string.format('  Event %d: pitch=%d, s=%.3f, e=%.3f, vel=%d, ch=%d\n',
                                        i, event.pitch, event.s, event.e, event.vel, event.ch))
    end
    return true, result
  else
    reaper.ShowConsoleMsg('ERROR: ' .. tostring(result) .. '\n')
    return false, result
  end
end

-- Run tests
reaper.ShowConsoleMsg('=== CUCO-OP Manual Test Runner ===\n')
reaper.ShowConsoleMsg('Engine path: ' .. SRC_DIR .. '\n')

local tests_run = 0
local tests_passed = 0

-- Test 1: Basic repeat
local ok1, plan1 = test_notation("Repeats", [[
~16
ch1 = [c4*3]
]], "Basic repeat functionality (*N)")

if ok1 then tests_passed = tests_passed + 1 end
tests_run = tests_run + 1

-- Test 2: Rest
local ok2, plan2 = test_notation("Rests", [[
~16
ch1 = [c4 _ d4]
]], "Rest functionality (_)")

if ok2 then tests_passed = tests_passed + 1 end
tests_run = tests_run + 1

-- Test 3: Sustain
local ok3, plan3 = test_notation("Sustain", [[
~16
ch1 = [c4 . d4]
]], "Sustain functionality (.)")

if ok3 then tests_passed = tests_passed + 1 end
tests_run = tests_run + 1

-- Test 4: Chords
local ok4, plan4 = test_notation("Chords", [[
~16
ch1 = [(c4 e4 g4)]
]], "Chord functionality ((c4 e4 g4))")

if ok4 then tests_passed = tests_passed + 1 end
tests_run = tests_run + 1

-- Summary
reaper.ShowConsoleMsg('\n=== TEST RESULTS ===\n')
reaper.ShowConsoleMsg('Passed: ' .. tests_passed .. '/' .. tests_run .. '\n')

if tests_passed == tests_run then
  reaper.ShowConsoleMsg('🎉 All tests PASSED! Engine is working correctly.\n')
else
  reaper.ShowConsoleMsg('⚠ Some tests failed. Check error messages above.\n')
end

-- If all tests passed, create MIDI items
if tests_passed == tests_run then
  reaper.ShowConsoleMsg('\n=== Creating MIDI Items ===\n')

  -- Create test track
  local track_count = reaper.CountTracks(0)
  reaper.InsertTrackAtIndex(track_count, true)
  local track = reaper.GetTrack(0, track_count)
  reaper.GetSetMediaTrackInfo_String(track, 'P_NAME', 'CUCO-OP Manual Test', true)

  -- Helper function to create MIDI from plan
  local function create_midi_item(track, plan, name)
    if not plan or #plan == 0 then return end

    local pos = reaper.GetCursorPosition()
    local baseQN = reaper.TimeMap2_timeToQN(0, pos)

    -- Calculate duration
    local max_end = 0
    for _, event in ipairs(plan) do
      if event.e > max_end then max_end = event.e end
    end

    local end_time = reaper.TimeMap2_QNToTime(0, baseQN + max_end)
    local item = reaper.CreateNewMIDIItemInProj(track, pos, end_time, false)
    local take = reaper.GetActiveTake(item)

    reaper.MIDI_DisableSort(take)
    for _, event in ipairs(plan) do
      local s_ppq = reaper.MIDI_GetPPQPosFromProjQN(take, baseQN + event.s)
      local e_ppq = reaper.MIDI_GetPPQPosFromProjQN(take, baseQN + event.e)
      reaper.MIDI_InsertNote(take, false, false, s_ppq, e_ppq, (event.ch or 1) - 1, event.pitch, event.vel, true)
    end
    reaper.MIDI_Sort(take)

    -- Set item name
    reaper.GetSetMediaItemInfo_String(item, 'P_NOTES', name, true)

    reaper.ShowConsoleMsg('Created MIDI item: ' .. name .. ' (' .. #plan .. ' events)\n')
  end

  -- Create MIDI items for each successful test
  if ok1 then create_midi_item(track, plan1, "Repeats Test") end
  if ok2 then create_midi_item(track, plan2, "Rests Test") end
  if ok3 then create_midi_item(track, plan3, "Sustain Test") end
  if ok4 then create_midi_item(track, plan4, "Chords Test") end

  reaper.UpdateArrange()
  reaper.ShowConsoleMsg('MIDI items created on track: CUCO-OP Manual Test\n')
end
