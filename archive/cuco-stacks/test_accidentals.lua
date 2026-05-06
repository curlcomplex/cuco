-- Test accidental parsing to verify the fixes are working
-- This script tests the note_to_midi function directly

-- PC_BASE table (from the main script)
local PC_BASE = {
  c = 0, d = 2, e = 4, f = 5, g = 7, a = 9, b = 11
}

-- note_to_midi function (copy from the fixed version)
local function note_to_midi(note)
  if type(note) ~= "string" then return nil end
  
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

-- Test cases
local test_cases = {
  -- Natural notes
  {"c4", 60},
  {"d4", 62}, 
  {"e4", 64},
  {"f4", 65},
  {"g4", 67},
  {"a4", 69},
  {"b4", 71},
  
  -- Sharp notes
  {"c#4", 61},
  {"d#4", 63},
  {"f#4", 66},
  {"g#4", 68},
  {"a#4", 70},
  
  -- Flat notes
  {"db4", 61},
  {"eb4", 63},
  {"gb4", 66},
  {"ab4", 68},
  {"bb4", 70},
  
  -- Different octaves
  {"c#3", 49},
  {"db5", 73},
}

print("Testing note_to_midi function with accidentals:")
print("=" .. string.rep("=", 50))

local all_passed = true
for _, test in ipairs(test_cases) do
  local input, expected = test[1], test[2]
  local result = note_to_midi(input)
  local status = (result == expected) and "PASS" or "FAIL"
  
  if result ~= expected then
    all_passed = false
  end
  
  print(string.format("%-6s -> %3s (expected %3s) [%s]", 
    input, 
    result and tostring(result) or "nil", 
    tostring(expected), 
    status))
end

print("=" .. string.rep("=", 50))
print("Overall result:", all_passed and "ALL TESTS PASSED" or "SOME TESTS FAILED")

return all_passed