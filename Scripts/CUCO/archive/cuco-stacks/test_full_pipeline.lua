-- Full pipeline test: input string -> tokenization -> note_to_midi conversion
-- This simulates the complete flow that CUCO-Stacks uses

-- PC_BASE and note_to_midi function (from fixed version)
local PC_BASE = { c = 0, d = 2, e = 4, f = 5, g = 7, a = 9, b = 11 }

local function note_to_midi(note)
  if type(note) ~= "string" then return nil end
  
  local l, a, o
  
  -- First, try to match with explicit sharp
  l, o = note:match("^([a-gA-G])#(%-?%d+)$")
  if l then
    a = "#"
  else
    -- Try to match with explicit flat  
    l, o = note:match("^([a-gA-G])b(%-?%d+)$")
    if l then
      a = "b"
    else
      -- Try natural note (no accidental)
      l, o = note:match("^([a-gA-G])(%-?%d+)$")
      if l then
        a = ""
      end
    end
  end
  
  if not l then return nil end
  
  local pc = PC_BASE[l:lower()] or 0
  
  -- Apply accidental
  if a == "#" then 
    pc = pc + 1
  elseif a == "b" then 
    pc = pc - 1
  end
  
  return (tonumber(o)+1)*12 + pc
end

-- Simplified tokenizer that extracts notes from input strings
local function extract_notes_from_input(input)
    local notes = {}
    local clean_input = input:gsub("~%d+", ""):gsub("%s+", " "):gsub("^%s+", ""):gsub("%s+$", "")
    
    -- Extract notes using the same patterns as the main tokenizer
    for word in clean_input:gmatch("%S+") do
        local note
        -- Try sharp note first
        note = word:match("^([a-gA-G]#%-?%d+)")
        if not note then
            -- Try flat note
            note = word:match("^([a-gA-G]b%-?%d+)")
        end
        if not note then
            -- Try natural note
            note = word:match("^([a-gA-G]%-?%d+)")
        end
        
        if note then
            table.insert(notes, note)
        end
    end
    
    return notes
end

-- Test cases simulating real CUCO-Stacks inputs
local test_cases = {
    {
        input = "~4 c#4 d#4 e4 f#4",
        expected_notes = {"c#4", "d#4", "e4", "f#4"},
        expected_midi = {61, 63, 64, 66}
    },
    {
        input = "~4 db4 eb4 f4 gb4", 
        expected_notes = {"db4", "eb4", "f4", "gb4"},
        expected_midi = {61, 63, 65, 66}
    },
    {
        input = "~8 c4 c#4 db4 d4",
        expected_notes = {"c4", "c#4", "db4", "d4"},
        expected_midi = {60, 61, 61, 62}
    },
    {
        input = "~4 a#3 bb3 c#4 db4",
        expected_notes = {"a#3", "bb3", "c#4", "db4"},
        expected_midi = {58, 58, 61, 61}
    }
}

print("CUCO-Stacks Full Pipeline Test: Input -> Tokenization -> MIDI")
print("=" .. string.rep("=", 70))

local all_passed = true

for i, test in ipairs(test_cases) do
    print(string.format("\nTest Case %d: %s", i, test.input))
    print(string.rep("-", 50))
    
    -- Step 1: Extract notes from input
    local extracted_notes = extract_notes_from_input(test.input)
    
    -- Step 2: Convert notes to MIDI
    local midi_results = {}
    for _, note in ipairs(extracted_notes) do
        local midi = note_to_midi(note)
        table.insert(midi_results, midi)
    end
    
    -- Step 3: Verify results
    local notes_match = true
    local midi_match = true
    
    -- Check if extracted notes match expected
    if #extracted_notes ~= #test.expected_notes then
        notes_match = false
    else
        for j, note in ipairs(extracted_notes) do
            if note ~= test.expected_notes[j] then
                notes_match = false
                break
            end
        end
    end
    
    -- Check if MIDI values match expected
    if #midi_results ~= #test.expected_midi then
        midi_match = false
    else
        for j, midi in ipairs(midi_results) do
            if midi ~= test.expected_midi[j] then
                midi_match = false
                break
            end
        end
    end
    
    -- Display results
    print("Extracted notes: [" .. table.concat(extracted_notes, ", ") .. "]")
    print("Expected notes:  [" .. table.concat(test.expected_notes, ", ") .. "]")
    print("Notes match:     " .. (notes_match and "✅ YES" or "❌ NO"))
    
    print("MIDI results:    [" .. table.concat(midi_results, ", ") .. "]")
    print("Expected MIDI:   [" .. table.concat(test.expected_midi, ", ") .. "]")
    print("MIDI match:      " .. (midi_match and "✅ YES" or "❌ NO"))
    
    local test_passed = notes_match and midi_match
    print("Test Result:     " .. (test_passed and "✅ PASS" or "❌ FAIL"))
    
    if not test_passed then
        all_passed = false
    end
end

print("\n" .. string.rep("=", 70))
print("OVERALL RESULT: " .. (all_passed and "✅ ALL TESTS PASSED" or "❌ SOME TESTS FAILED"))

if all_passed then
    print("\n🎉 SUCCESS: Accidental parsing is working correctly!")
    print("   - Sharp notes (c#4, d#4, etc.) are properly parsed and converted")
    print("   - Flat notes (db4, eb4, etc.) are properly parsed and converted")  
    print("   - The tokenization -> MIDI conversion pipeline preserves accidentals")
else
    print("\n❌ FAILURE: There are still issues with accidental parsing")
end

return all_passed