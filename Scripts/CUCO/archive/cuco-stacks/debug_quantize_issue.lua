-- Debug script to test the quantize_to_scale issue with accidentals

-- Replicate the scale system from CUCO Stacks
local current_scale = {
  root = 0,        -- C = 0, C# = 1, etc.
  intervals = {0,2,4,5,7,9,11}, -- default to major
  quantize = "near" -- "up", "down", "near", "ignore"
}

local function quantize_to_scale(midi_note)
  if current_scale.quantize == "ignore" then
    -- Check if note is in scale, return nil if not
    local pc = midi_note % 12
    local root_offset = (pc - current_scale.root + 12) % 12
    for _, interval in ipairs(current_scale.intervals) do
      if math.abs(interval - root_offset) < 0.1 then -- allow small tolerance for microtonal
        return midi_note -- note is in scale
      end
    end
    return nil -- note not in scale, ignore it
  elseif current_scale.quantize == "near" or current_scale.quantize == "up" or current_scale.quantize == "down" then
    local octave = math.floor(midi_note / 12)
    local pc = midi_note % 12
    local root_offset = (pc - current_scale.root + 12) % 12
    
    -- Find closest scale degree
    local best_interval = current_scale.intervals[1] or 0
    local best_dist = math.abs(root_offset - best_interval)
    
    for _, interval in ipairs(current_scale.intervals) do
      local dist = math.abs(root_offset - interval)
      -- Handle wrap-around (e.g. 11 semitones vs 1 semitone for next octave)
      local wrap_dist = math.abs(root_offset - (interval + 12))
      local wrap_dist2 = math.abs((root_offset + 12) - interval)
      dist = math.min(dist, wrap_dist, wrap_dist2)
      
      if current_scale.quantize == "up" then
        -- Prefer higher intervals when equal distance
        if dist < best_dist or (dist == best_dist and interval > best_interval) then
          best_interval = interval
          best_dist = dist
        end
      elseif current_scale.quantize == "down" then
        -- Prefer lower intervals when equal distance
        if dist < best_dist or (dist == best_dist and interval < best_interval) then
          best_interval = interval
          best_dist = dist
        end
      else -- "near"
        if dist < best_dist or (dist == best_dist and interval < best_interval) then
          best_interval = interval
          best_dist = dist
        end
      end
    end
    
    -- Calculate final MIDI note
    local target_pc = (current_scale.root + best_interval) % 12
    return octave * 12 + target_pc
  else
    return midi_note -- no quantization
  end
end

local PC_NAME = {[0]="c",[1]="c#",[2]="d",[3]="d#",[4]="e",[5]="f",[6]="f#",[7]="g",[8]="g#",[9]="a",[10]="a#",[11]="b"}
local function midi_to_note(m) local o=math.floor(m/12)-1; local pc=((m%12)+12)%12; return (PC_NAME[pc] or "c")..tostring(o) end

reaper.ShowConsoleMsg("=== TESTING QUANTIZE_TO_SCALE ISSUE ===\n")
reaper.ShowConsoleMsg("Current scale: C major (0,2,4,5,7,9,11) with 'near' quantization\n\n")

-- Test notes that should have accidentals
local test_notes = {
  {60, "C4"}, {61, "C#4"}, {62, "D4"}, {63, "D#4/Eb4"}, 
  {64, "E4"}, {65, "F4"}, {66, "F#4/Gb4"}, {67, "G4"}
}

for _, test in ipairs(test_notes) do
  local midi_in = test[1]
  local name_in = test[2] 
  local midi_out = quantize_to_scale(midi_in)
  local name_out = midi_to_note(midi_out)
  
  local status = (midi_in == midi_out) and "UNCHANGED" or "QUANTIZED"
  reaper.ShowConsoleMsg(string.format("%s (%d) -> %s (%d) [%s]\n", 
    name_in, midi_in, name_out, midi_out, status))
end

reaper.ShowConsoleMsg("\n=== CONCLUSION ===\n")
reaper.ShowConsoleMsg("The quantize_to_scale function is altering accidentals!\n")
reaper.ShowConsoleMsg("C#4 (61) gets quantized to the nearest scale tone.\n")
reaper.ShowConsoleMsg("In C major scale, C# is not in scale, so it gets quantized\n")
reaper.ShowConsoleMsg("to either C (60) or D (62) - whichever is closer.\n")