-- Simple CUCO X Functionality Test
-- This demonstrates the key differences between X and X^

local take = reaper.MIDIEditor_GetTake(reaper.MIDIEditor_GetActive())
if not take then
  reaper.ShowMessageBox("Please open a MIDI editor with an active take", "Error", 0)
  return
end

local function test_cuco_notation(test_name, notation)
  print(string.format("\n=== %s ===", test_name))
  print(string.format("Testing: %s", notation))
  
  -- Clear existing MIDI
  local i = 0
  while true do
    local ok = reaper.MIDI_DeleteNote(take, 0)
    if not ok then break end
    i = i + 1
    if i > 1000 then break end -- Safety valve
  end
  
  -- Set the MIDI item name to trigger CUCO processing
  local item = reaper.GetMediaItemTake_Item(take)
  reaper.GetSetMediaItemTakeInfo_String(take, "P_NAME", notation, true)
  
  -- Restart CUCO script to process the new notation
  reaper.Main_OnCommand(reaper.NamedCommandLookup("_RS170b99c2dea725579f195be69ffed170f7be0d34"), 0)
  reaper.time_precise_sleepMS(500) -- Wait for processing
  
  -- Count result notes
  local _, note_count = reaper.MIDI_CountEvts(take)
  print(string.format("Result: %d MIDI notes generated", note_count))
  
  -- Brief pause before next test
  reaper.time_precise_sleepMS(1000)
end

-- Run the tests
print("CUCO X Functionality Test")
print("==========================")
print("Testing the difference between X (chord only) and X^ (chord + processors)")

-- Test 1: Basic stack reference
test_cuco_notation("Test 1: Stack then X (chord reference)", "[c4 e4 g4] X")

-- Test 2: Stack with processor, then X (should only get chord)
test_cuco_notation("Test 2: Stack with arp, then X (chord only)", "[c4 e4 g4]!arp(up,4) X")

-- Test 3: Stack with processor, then X^ (should get chord + inherited arp)
test_cuco_notation("Test 3: Stack with arp, then X^ (chord + inherited arp)", "[c4 e4 g4]!arp(up,4) X^")

-- Test 4: Multiple X^ calls to show inheritance
test_cuco_notation("Test 4: Multiple X^ inheritance", "[c4 e4 g4]!arp(pend,3) X^ X^+12")

-- Test 5: Compare x (mirror) vs X^ (stack reference with inheritance)
test_cuco_notation("Test 5: Compare x vs X^", "[c4 e4 g4]!arp(down,5) x X^")

print("\nTest completed! Check the MIDI editor to see the results.")
print("Key differences:")
print("- X: References just the chord pitches from the last stack")
print("- X^: References the chord AND inherits any processors from the last stack")
print("- x: Mirrors the current last_voices/anchor_voices (not stack-specific)")