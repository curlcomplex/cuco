--[[
ReaScript Name: CUCO Test Trigger
Author: Assistant + curl

Simple trigger script for testing CUCO-Stacks functionality.

What this script does:
1. Changes the name of the first MIDI item to a test CUCO syntax
2. Exports the processed MIDI data to a CSV file for analysis

Usage:
1. Load this script in REAPER
2. Assign it to a keyboard shortcut 
3. Trigger via OSC using that shortcut
4. Check the CSV output to verify CUCO-Stacks behavior
--]]

-- Configuration
local CSV_OUTPUT_PATH = "/tmp/cuco_test_output.csv"

-- Test CUCO syntax - Test euclidean poly processor
-- Should create polyrhythmic patterns with different subdivisions per voice
local TEST_SYNTAX = "~4 [c3 e3 g3]!poly(3,5,7)"

function log_message(msg)
  reaper.ShowConsoleMsg("CUCO Test: " .. msg .. "\n")
  
  -- Also log to file for debugging
  local log_file = io.open("/tmp/cuco_test_debug.log", "a")
  if log_file then
    log_file:write(os.date("%Y-%m-%d %H:%M:%S") .. " - " .. msg .. "\n")
    log_file:close()
  end
end

-- Convert MIDI note number to note name (e.g. 60 -> "C4")
function midi_note_to_name(note_num)
  local note_names = {"C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "B"}
  local octave = math.floor(note_num / 12) - 1
  local note = note_names[(note_num % 12) + 1]
  return note .. octave
end

-- Calculate musical timing from project time
function get_musical_timing(time_seconds, bpm, bpi)
  local beats_per_second = bpm / 60.0
  local total_beats = time_seconds * beats_per_second
  local bars = math.floor(total_beats / bpi)
  local beat_in_bar = (total_beats % bpi)
  return total_beats, bars + 1, beat_in_bar + 1  -- 1-based for display
end

function main()
  log_message("=== CUCO Test Trigger Started ===")
  
  -- Step 0: Restart CUCO Stacks script to ensure latest code is loaded
  log_message("Restarting CUCO Stacks script...")
  reaper.Main_OnCommand(reaper.NamedCommandLookup("_RS170b99c2dea725579f195be69ffed170f7be0d34"), 0)
  
  -- Wait a brief moment for the script to initialize
  local start_time = reaper.time_precise()
  while reaper.time_precise() - start_time < 0.5 do
    -- Wait 500ms for script to load
  end
  
  log_message("✓ CUCO Stacks script restarted")
  
  -- Step 1: Find the first MIDI item
  local project = 0
  local item_count = reaper.CountMediaItems(project)
  
  if item_count == 0 then
    log_message("ERROR: No MIDI items found in project")
    return
  end
  
  local item = reaper.GetMediaItem(project, 0) -- First item
  if not item then
    log_message("ERROR: Could not get first MIDI item")
    return
  end
  
  local take = reaper.GetActiveTake(item)
  if not take then
    log_message("ERROR: No active take found in MIDI item")
    return
  end
  
  -- Step 2: Set the MIDI item name to test syntax
  -- Add a space and timestamp to ensure name changes each time
  local timestamp = tostring(reaper.time_precise()):sub(-6) -- last 6 digits
  local test_name = TEST_SYNTAX .. " " .. timestamp
  
  log_message("Setting MIDI item name to: " .. test_name)
  reaper.GetSetMediaItemTakeInfo_String(take, "P_NAME", test_name, true)
  
  -- Verify what was actually set
  local _, actual_name = reaper.GetSetMediaItemTakeInfo_String(take, "P_NAME", "", false)
  log_message("Actual name read back: '" .. (actual_name or "nil") .. "'")
  
  -- Test character by character to see if accidentals are preserved
  for i = 1, #TEST_SYNTAX do
    local char = TEST_SYNTAX:sub(i, i)
    log_message(string.format("Original char %d: '%s' (byte %d)", i, char, string.byte(char)))
  end
  
  if actual_name then
    for i = 1, #actual_name do
      local char = actual_name:sub(i, i)
      log_message(string.format("Read-back char %d: '%s' (byte %d)", i, char, string.byte(char)))
    end
  end
  
  -- Select the item and update display
  reaper.SelectAllMediaItems(project, false)
  reaper.SetMediaItemSelected(item, true)
  reaper.UpdateArrange()
  reaper.MarkProjectDirty(project)
  
  log_message("✓ MIDI item name changed")
  log_message("Now run CUCO-Stacks to process the item...")
  log_message("Then run this script again to export CSV")
  
  -- Wait a moment for MIDI processing to complete
  local wait_start = reaper.time_precise()
  while reaper.time_precise() - wait_start < 5.0 do
    -- Wait 5 seconds for MIDI processing
  end
  
  -- Force update project state
  reaper.UpdateArrange()
  
  -- Step 3: Export MIDI data to CSV
  export_to_csv(take)
  
  log_message("=== CUCO Test Trigger Complete ===")
end

function export_to_csv(take)
  log_message("Exporting MIDI data to: " .. CSV_OUTPUT_PATH)
  
  -- Create directory if needed
  local dir = string.match(CSV_OUTPUT_PATH, "(.+)/[^/]+$")
  if dir then
    reaper.RecursiveCreateDirectory(dir, 0)
  end
  
  -- Get project timing info
  local project = 0
  local bpm, bpi = reaper.GetProjectTimeSignature2(project)
local project_start_time = 0 -- Assuming project start time is 0 as GetProjectStartTime is nil
  
  -- Open CSV file for writing
  local file = io.open(CSV_OUTPUT_PATH, "w")
  if not file then
    log_message("ERROR: Could not create CSV file: " .. CSV_OUTPUT_PATH)
    return
  end
  
  -- Write comprehensive CSV header
  file:write("note_number,note_name,velocity,start_time,end_time,duration,channel,start_ppq,end_ppq,start_beats,end_beats,start_bars,start_beat_in_bar,end_bars,end_beat_in_bar,project_bpm,time_signature\n")
  
  -- Also create a simple summary for scale testing
  local summary_file = io.open("/tmp/cuco_scale_summary.txt", "w")
  if summary_file then
    summary_file:write("=== Scale Quantization Summary ===\n")
    summary_file:write("Time\tInput\tOutput\tChanged\n")
  end
  
  -- Get MIDI data
  local retval, midi_data = reaper.MIDI_GetAllEvts(take, "")
  if not retval or #midi_data == 0 then
    log_message("WARNING: No MIDI data found in take")
    file:close()
    return
  end
  
  -- Parse MIDI events
  local pos = 1
  local ppq_pos = 0
  local notes_on = {} -- Track note on events
  local note_count = 0
  
  while pos <= #midi_data do
    local offset, flags, msg_len = string.unpack("i4Bi4", midi_data, pos)
    pos = pos + 9
    
    if msg_len > 0 then
      local msg = midi_data:sub(pos, pos + msg_len - 1)
      pos = pos + msg_len
      
      ppq_pos = ppq_pos + offset
      local msg_type = string.byte(msg, 1)
      
      -- Handle Note On (0x90-0x9F)
      if msg_type >= 0x90 and msg_type <= 0x9F then
        local channel = msg_type & 0x0F
        local note = string.byte(msg, 2)
        local velocity = string.byte(msg, 3)
        
        if velocity > 0 then
          -- Real note on
          local note_key = channel * 128 + note
          local start_time = reaper.MIDI_GetProjTimeFromPPQPos(take, ppq_pos)
          notes_on[note_key] = {
            note = note,
            velocity = velocity,
            channel = channel,
            start_time = start_time,
            start_ppq = ppq_pos
          }
        else
          -- Note on with velocity 0 = note off
          local note_key = channel * 128 + note
          if notes_on[note_key] then
            local note_on = notes_on[note_key]
            local end_time = reaper.MIDI_GetProjTimeFromPPQPos(take, ppq_pos)
            local duration = end_time - note_on.start_time
            
            -- Calculate comprehensive timing data
            local note_name = midi_note_to_name(note_on.note)
            local start_beats, start_bars, start_beat_in_bar = get_musical_timing(note_on.start_time, bpm, bpi)
            local end_beats, end_bars, end_beat_in_bar = get_musical_timing(end_time, bpm, bpi)
            local time_sig = string.format("%.0f/4", bpi)
            
            file:write(string.format("%d,%s,%d,%.6f,%.6f,%.6f,%d,%d,%d,%.6f,%.6f,%.1f,%.3f,%.1f,%.3f,%.1f,%s\n", 
              note_on.note, note_name, note_on.velocity, note_on.start_time, end_time, duration, note_on.channel,
              note_on.start_ppq, ppq_pos, start_beats, end_beats, start_bars, start_beat_in_bar, end_bars, end_beat_in_bar, bpm, time_sig))
            
            -- Add to summary file for scale testing
            if summary_file then
              -- Estimate original input note based on position in sequence
              local chromatic_notes = {"C4", "C#4", "D4", "D#4", "E4", "F4", "F#4", "G4", "G#4", "A4", "A#4", "B4", "C5"}
              local expected_input = chromatic_notes[note_count + 1] or "?"
              local changed = (expected_input ~= note_name) and "YES" or "NO"
              summary_file:write(string.format("%.3f\t%s\t%s\t%s\n", note_on.start_time, expected_input, note_name, changed))
            end
            
            note_count = note_count + 1
          end
        end
        
      -- Handle Note Off (0x80-0x8F)
      elseif msg_type >= 0x80 and msg_type <= 0x8F then
        local channel = msg_type & 0x0F
        local note = string.byte(msg, 2)
        local note_key = channel * 128 + note
        
        if notes_on[note_key] then
          local note_on = notes_on[note_key]
          local end_time = reaper.MIDI_GetProjTimeFromPPQPos(take, ppq_pos)
          local duration = end_time - note_on.start_time
          
          -- Calculate comprehensive timing data
          local note_name = midi_note_to_name(note_on.note)
          local start_beats, start_bars, start_beat_in_bar = get_musical_timing(note_on.start_time, bpm, bpi)
          local end_beats, end_bars, end_beat_in_bar = get_musical_timing(end_time, bpm, bpi)
          local time_sig = string.format("%.0f/4", bpi)
          
          file:write(string.format("%d,%s,%d,%.6f,%.6f,%.6f,%d,%d,%d,%.6f,%.6f,%.1f,%.3f,%.1f,%.3f,%.1f,%s\n", 
            note_on.note, note_name, note_on.velocity, note_on.start_time, end_time, duration, note_on.channel,
            note_on.start_ppq, ppq_pos, start_beats, end_beats, start_bars, start_beat_in_bar, end_bars, end_beat_in_bar, bpm, time_sig))
          
          notes_on[note_key] = nil
          note_count = note_count + 1
        end
      end
    end
  end
  
  -- Handle any remaining note ons (notes without explicit note offs)
  for note_key, note_on in pairs(notes_on) do
    local end_time = note_on.start_time + 0.1 -- Default 0.1s duration
    local duration = 0.1
    local end_ppq = note_on.start_ppq + (0.1 * 960) -- Approximate PPQ for 0.1s
    
    -- Calculate comprehensive timing data
    local note_name = midi_note_to_name(note_on.note)
    local start_beats, start_bars, start_beat_in_bar = get_musical_timing(note_on.start_time, bpm, bpi)
    local end_beats, end_bars, end_beat_in_bar = get_musical_timing(end_time, bpm, bpi)
    local time_sig = string.format("%.0f/4", bpi)
    
    file:write(string.format("%d,%s,%d,%.6f,%.6f,%.6f,%d,%d,%d,%.6f,%.6f,%.1f,%.3f,%.1f,%.3f,%.1f,%s\n", 
      note_on.note, note_name, note_on.velocity, note_on.start_time, end_time, duration, note_on.channel,
      note_on.start_ppq, end_ppq, start_beats, end_beats, start_bars, start_beat_in_bar, end_bars, end_beat_in_bar, bpm, time_sig))
    
    note_count = note_count + 1
  end
  
  file:close()
  
  if summary_file then
    summary_file:close()
    log_message("✓ Scale summary written to /tmp/cuco_scale_summary.txt")
  end
  
  log_message("✓ CSV export complete - " .. note_count .. " notes exported")
  log_message("CSV file: " .. CSV_OUTPUT_PATH)
end

-- Add startup logging
local startup_log = io.open("/tmp/cuco_test_debug.log", "a")
if startup_log then
  startup_log:write(os.date("%Y-%m-%d %H:%M:%S") .. " - CUCO_Test_Trigger.lua STARTED\n")
  startup_log:close()
end

-- Run the main function
main()
