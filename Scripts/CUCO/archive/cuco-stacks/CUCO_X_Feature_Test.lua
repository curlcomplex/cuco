-- CUCO X Feature Comprehensive Test
-- This script tests all aspects of X functionality in CUCO-Stacks

local function restart_cuco_script()
  reaper.Main_OnCommand(reaper.NamedCommandLookup("_RS170b99c2dea725579f195be69ffed170f7be0d34"), 0)
  reaper.time_precise_sleepMS(100) -- Wait for restart
end

local function test_x_feature(test_name, midi_text)
  print(string.format("\n=== Testing: %s ===", test_name))
  print(string.format("Input: %s", midi_text))
  
  local take = reaper.MIDIEditor_GetTake(reaper.MIDIEditor_GetActive())
  if not take then
    print("ERROR: No active MIDI take found")
    return
  end
  
  -- Clear existing MIDI
  reaper.MIDI_DeleteEvt(take, 0, true) -- Clear all notes
  
  -- Set the item name to trigger CUCO processing
  local item = reaper.GetMediaItemTake_Item(take)
  reaper.GetSetMediaItemTakeInfo_String(take, "P_NAME", midi_text, true)
  
  -- Process with CUCO
  reaper.defer(function()
    restart_cuco_script()
    reaper.time_precise_sleepMS(500) -- Wait for processing
    
    -- Count and report results
    local _, notes = reaper.MIDI_CountEvts(take)
    print(string.format("Result: %d MIDI notes generated", notes))
    
    -- Log note details
    for i = 0, notes - 1 do
      local _, _, _, start, end_, _, pitch, vel = reaper.MIDI_GetNote(take, i)
      local start_qn = reaper.MIDI_GetPPQPosFromProjQN(take, reaper.MIDI_GetProjQNFromPPQPos(take, start))
      local end_qn = reaper.MIDI_GetPPQPosFromProjQN(take, reaper.MIDI_GetProjQNFromPPQPos(take, end_))
      print(string.format("  Note %d: Pitch=%d, Start=%.3f, End=%.3f, Vel=%d", 
        i+1, pitch, start_qn, end_qn, vel))
    end
    
    print("Test completed.")
  end)
end

-- Test Suite
local function run_comprehensive_x_tests()
  local tests = {
    -- Basic X mirroring tests
    {
      name = "Basic chord then x mirror",
      input = "[c4 e4 g4] x"
    },
    {
      name = "Single note then x mirror",
      input = "c4 x"
    },
    {
      name = "Multiple x mirrors",
      input = "[c4 e4 g4] x x x"
    },
    
    -- X outside stacks (reference previous stack)
    {
      name = "X reference after stack (chord only)",
      input = "[c4 e4 g4] X"
    },
    {
      name = "X^ inheritance (should be same as X when stack had no processors)",
      input = "[c4 e4 g4] X^"
    },
    {
      name = "X with offset",
      input = "[c4 e4 g4] X+12"
    },
    {
      name = "X^ with negative offset",
      input = "[c4 e4 g4] X^-5"
    },
    
    -- X with processors
    {
      name = "X with arp up",
      input = "[c4 e4 g4] X!arp(up,4)"
    },
    {
      name = "X with arp down",
      input = "[c4 e4 g4] X!arp(down,6)"
    },
    {
      name = "X with arp random",
      input = "[c4 e4 g4] X!arp(rand,8)"
    },
    {
      name = "X with arp updown",
      input = "[c4 e4 g4] X!arp(updown,5)"
    },
    {
      name = "X with arp pendulum",
      input = "[c4 e4 g4] X!arp(pend,5)"
    },
    {
      name = "X with arp inside-out",
      input = "[c4 e4 g4] X!arp(io,6)"
    },
    {
      name = "X with arp outside-in",
      input = "[c4 e4 g4] X!arp(oi,6)"
    },
    {
      name = "X with arp span (2 octaves)",
      input = "[c4 e4 g4] X!arp(up,8,2)"
    },
    {
      name = "X with arp offset + processor",
      input = "[c4 e4 g4] X+7!arp(up,4)"
    },
    
    -- X^ inheritance tests (the key difference!)
    {
      name = "Stack with processor, then X (chord only)",
      input = "[c4 e4 g4]!arp(up,4) X"
    },
    {
      name = "Stack with processor, then X^ (chord + processor inheritance)",
      input = "[c4 e4 g4]!arp(up,4) X^"
    },
    {
      name = "Stack with arp down, then X^ inheritance",
      input = "[c4 e4 g4]!arp(down,6) X^"
    },
    {
      name = "Multiple X references",
      input = "[c4 e4 g4] X X+12 X-12"
    },
    {
      name = "Demonstrate X vs X^ difference",
      input = "[c4 e4 g4]!arp(up,3) X X^"
    },
    {
      name = "Mixed x (mirror) and X^ (stack reference with inheritance)",
      input = "[c4 e4 g4]!arp(pend,4) x X^"
    },
    
    -- Edge cases
    {
      name = "X without previous stack (should use defaults)",
      input = "X"
    },
    {
      name = "X with complex multi-octave arp",
      input = "[c4 e4 g4 c5] X!arp(updown,12,3)"
    },
    {
      name = "Transpose context with X",
      input = "+7 [c4 e4 g4] X"
    }
  }
  
  print("Starting Comprehensive CUCO X Feature Tests")
  print("============================================")
  
  for i, test in ipairs(tests) do
    reaper.time_precise_sleepMS(1000) -- Pause between tests
    test_x_feature(string.format("Test %d: %s", i, test.name), test.input)
    reaper.time_precise_sleepMS(2000) -- Wait for processing
  end
  
  print("\n=== All X Feature Tests Completed ===")
end

-- Execute the test suite
run_comprehensive_x_tests()