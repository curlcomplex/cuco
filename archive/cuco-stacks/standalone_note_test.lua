-- Standalone test for note_to_midi function
-- Extracted functions from CUCO Stacks for testing without REAPER

-- Music utilities (note name to pitch class conversion) 
local PC_BASE = {c=0,d=2,e=4,f=5,g=7,a=9,b=11}

local function note_to_midi(note)
  if type(note) ~= "string" then return nil end
  
  -- DEBUG: Log every note conversion attempt
  print("[DEBUG] note_to_midi called with: '" .. tostring(note) .. "'")
  
  -- More robust pattern matching with explicit accidental handling
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

print("=== STANDALONE NOTE PARSING TEST ===")

-- Test the note_to_midi function directly
local test_notes = {
    "c4", "c#4", "d4", "d#4", "eb4", "f4", "f#4", "gb4", "a4", "bb4", "c5"
}

local expected_midi = {
    60, 61, 62, 63, 63, 65, 66, 66, 69, 70, 72
}

print("\nTesting note_to_midi function:")
for i, note in ipairs(test_notes) do
    local result = note_to_midi(note)
    local expected = expected_midi[i]
    local status = (result == expected) and "✓" or "✗"
    print(string.format("  %s %s -> %d (expected %d)", status, note, result or -999, expected))
    if result ~= expected then
        print(string.format("    ERROR: Got %d, expected %d", result or -999, expected))
    end
end

print("\n=== TEST COMPLETE ===")