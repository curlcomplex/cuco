-- Test note_to_midi function in isolation
local PC_BASE = {c=0,d=2,e=4,f=5,g=7,a=9,b=11}

local function note_to_midi(note)
  if type(note) ~= "string" then return nil end
  local l, a, o = note:match("^([a-gA-G])([b#]?)(%-?%d+)$")
  
  reaper.ShowConsoleMsg("=== Testing: " .. note .. " ===\n")
  reaper.ShowConsoleMsg("Pattern result - l: " .. (l or "nil") .. ", a: '" .. (a or "") .. "', o: " .. (o or "nil") .. "\n")
  
  if not l then return nil end
  local pc = PC_BASE[l:lower()] or 0
  
  reaper.ShowConsoleMsg("Base PC: " .. pc .. "\n")
  
  if a=="#" then 
    pc=pc+1
    reaper.ShowConsoleMsg("Sharp applied: " .. pc .. "\n")
  elseif a=="b" then 
    pc=pc-1
    reaper.ShowConsoleMsg("Flat applied: " .. pc .. "\n")
  end
  
  local result = (tonumber(o)+1)*12 + pc
  reaper.ShowConsoleMsg("Final MIDI note: " .. result .. "\n\n")
  return result
end

-- Test cases
local tests = {"c4", "c#4", "db4", "d4", "f#4", "bb4"}

for _, test_note in ipairs(tests) do
  local midi_num = note_to_midi(test_note)
  reaper.ShowConsoleMsg(test_note .. " -> MIDI " .. (midi_num or "FAILED") .. "\n")
end

reaper.ShowConsoleMsg("Expected results:\n")
reaper.ShowConsoleMsg("c4 -> 60, c#4 -> 61, db4 -> 61, d4 -> 62, f#4 -> 66, bb4 -> 70\n")