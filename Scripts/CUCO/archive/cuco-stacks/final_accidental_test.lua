--[[
Final Accidental Test Script for REAPER
This script creates a MIDI item with the test pattern and processes it to verify accidentals work.
]]

-- Create a test MIDI item and process it
local function test_accidentals_in_reaper()
    reaper.ShowConsoleMsg("=== FINAL ACCIDENTAL TEST ===\n")
    
    -- Clear any existing items
    reaper.SelectAllMediaItems(0, true)
    reaper.DeleteMediaItems(0, true)
    
    -- Create a new MIDI item
    local track = reaper.GetTrack(0, 0)
    if not track then
        -- Create track if none exists
        reaper.InsertTrackAtIndex(0, false)
        track = reaper.GetTrack(0, 0)
    end
    
    -- Create MIDI item
    local start_time = 0
    local length = 4.0  -- 4 seconds
    local item = reaper.CreateNewMIDIItemInProj(track, start_time, start_time + length)
    local take = reaper.GetActiveTake(item)
    
    -- Set the test pattern that was failing
    local test_pattern = "~4 c#4 d#4 eb4 f#4 gb4 a4 bb4 c5"
    reaper.GetSetMediaItemTakeInfo_String(take, "P_NAME", test_pattern, true)
    
    -- Verify what was set
    local _, actual_name = reaper.GetSetMediaItemTakeInfo_String(take, "P_NAME", "", false)
    reaper.ShowConsoleMsg("Test pattern set: " .. test_pattern .. "\n")
    reaper.ShowConsoleMsg("Actual name read: " .. (actual_name or "nil") .. "\n")
    
    -- Select the item for processing
    reaper.SelectAllMediaItems(0, false)
    reaper.SetMediaItemSelected(item, true)
    
    reaper.ShowConsoleMsg("✓ MIDI item created and ready for CUCO-Stacks processing\n")
    reaper.ShowConsoleMsg("Now manually run CUCO-Stacks to process this item.\n")
    
    -- After processing, we'll check what MIDI notes were created
    reaper.ShowConsoleMsg("\n--- Expected MIDI Notes ---\n")
    local expected = {
        {name="c#4", midi=61},
        {name="d#4", midi=63}, 
        {name="eb4", midi=63},
        {name="f#4", midi=66},
        {name="gb4", midi=66},
        {name="a4", midi=69},
        {name="bb4", midi=70},
        {name="c5", midi=72}
    }
    
    for _, note_info in ipairs(expected) do
        reaper.ShowConsoleMsg(string.format("%s -> MIDI %d\n", note_info.name, note_info.midi))
    end
    
    reaper.ShowConsoleMsg("\nRun this script again after processing to check results.\n")
    reaper.ShowConsoleMsg("=== TEST SETUP COMPLETE ===\n")
    
    -- Also check if there are already notes in the item (post-processing check)
    check_processed_notes(take)
end

local function check_processed_notes(take)
    local retval, midi_data = reaper.MIDI_GetAllEvts(take, "")
    if not retval or #midi_data == 0 then
        reaper.ShowConsoleMsg("\n(No MIDI notes found yet - run CUCO-Stacks first)\n")
        return
    end
    
    reaper.ShowConsoleMsg("\n--- ACTUAL PROCESSED NOTES ---\n")
    
    -- Parse MIDI events to find notes
    local pos = 1
    local note_count = 0
    
    while pos <= #midi_data do
        local offset, flags, msg_len = string.unpack("i4Bi4", midi_data, pos)
        pos = pos + 9
        
        if msg_len > 0 then
            local msg = midi_data:sub(pos, pos + msg_len - 1)
            pos = pos + msg_len
            
            local msg_type = string.byte(msg, 1)
            
            -- Handle Note On (0x90-0x9F)
            if msg_type >= 0x90 and msg_type <= 0x9F then
                local note = string.byte(msg, 2)
                local velocity = string.byte(msg, 3)
                
                if velocity > 0 then
                    note_count = note_count + 1
                    local note_names = {"C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "B"}
                    local octave = math.floor(note / 12) - 1
                    local note_name = note_names[(note % 12) + 1] .. octave
                    reaper.ShowConsoleMsg(string.format("Note %d: MIDI %d (%s)\n", note_count, note, note_name))
                end
            end
        end
    end
    
    if note_count > 0 then
        reaper.ShowConsoleMsg(string.format("\n✓ Found %d processed notes\n", note_count))
        reaper.ShowConsoleMsg("Compare with expected values above to verify accidentals were preserved.\n")
    end
end

-- Run the test
test_accidentals_in_reaper()