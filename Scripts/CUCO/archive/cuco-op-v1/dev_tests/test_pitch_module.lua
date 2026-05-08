-- Test pitch module standalone
local pitch = require("src.pitch")

print("Testing pitch module...")

-- Test chord symbol parsing
local parsed = pitch.parse_chord_symbol("c-maj7")
print("Parsed c-maj7:", parsed.root, parsed.quality, parsed.bass)

-- Test chord to notes conversion
local notes = pitch.chord_to_notes("c-maj", 4)
print("c-maj notes:")
for i, note in ipairs(notes) do
    print("  ", i, note)
end

-- Test f#-min7
local fsharp_notes = pitch.chord_to_notes("f#-min7", 4)
print("f#-min7 notes:")
for i, note in ipairs(fsharp_notes) do
    print("  ", i, note)
end

print("Pitch module test complete")
