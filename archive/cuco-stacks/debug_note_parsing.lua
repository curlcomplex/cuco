-- Debug note parsing
local PC_BASE = {c=0,d=2,e=4,f=5,g=7,a=9,b=11}

local function note_to_midi(note)
  if type(note) ~= "string" then return nil end
  local l, a, o = note:match("^([a-gA-G])([b#]?)(%-?%d+)$")
  
  reaper.ShowConsoleMsg("DEBUG note_to_midi:\n")
  reaper.ShowConsoleMsg("  input: '" .. note .. "'\n")
  reaper.ShowConsoleMsg("  l: '" .. (l or "nil") .. "'\n")
  reaper.ShowConsoleMsg("  a: '" .. (a or "nil") .. "'\n")
  reaper.ShowConsoleMsg("  o: '" .. (o or "nil") .. "'\n")
  
  if not l then 
    reaper.ShowConsoleMsg("  PATTERN FAILED!\n")
    return nil 
  end
  
  local pc = PC_BASE[l:lower()] or 0
  reaper.ShowConsoleMsg("  base pc: " .. pc .. "\n")
  
  if a=="#" then 
    pc=pc+1
    reaper.ShowConsoleMsg("  sharp: pc=" .. pc .. "\n")
  elseif a=="b" then 
    pc=pc-1
    reaper.ShowConsoleMsg("  flat: pc=" .. pc .. "\n")
  end
  
  local result = (tonumber(o)+1)*12 + pc
  reaper.ShowConsoleMsg("  final result: " .. result .. "\n")
  return result
end

-- Test cases
local test_notes = {"c4", "c#4", "db4", "f#4", "bb4"}

reaper.ShowConsoleMsg("=== NOTE PARSING DEBUG ===\n")
for _, note in ipairs(test_notes) do
  local midi_num = note_to_midi(note)
  reaper.ShowConsoleMsg(note .. " -> " .. (midi_num or "NIL") .. "\n\n")
end