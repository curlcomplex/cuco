-- Debug script to test accidental parsing
-- This script tests the note_to_midi function directly and traces through tokenization

-- Load CUCO Stacks functions
dofile("CUCO Stacks.lua")

print("=== ACCIDENTAL PARSING DEBUG ===")

-- Test the note_to_midi function directly
local test_notes = {
    "c4", "c#4", "d4", "d#4", "eb4", "f4", "f#4", "gb4", "a4", "bb4", "c5"
}

local expected_midi = {
    60, 61, 62, 63, 63, 65, 66, 66, 69, 70, 72
}

print("\n1. Testing note_to_midi function directly:")
for i, note in ipairs(test_notes) do
    local result = note_to_midi(note)
    local expected = expected_midi[i]
    local status = (result == expected) and "✓" or "✗"
    print(string.format("  %s %s -> %d (expected %d)", status, note, result or -999, expected))
    if result ~= expected then
        print(string.format("    ERROR: Got %d, expected %d", result or -999, expected))
    end
end

-- Test tokenization specifically
print("\n2. Testing tokenization patterns:")
local test_string = "c#4 d#4 eb4 f#4 gb4 a4 bb4 c5"
local warnings = {}

-- Enable tokenization debug
DEBUG_TOK = true

-- Parse the test string
local tokens = tokenize(test_string, warnings)

print("\nTokens found:")
for i, token in ipairs(tokens) do
    print(string.format("  Token %d: %s (type: %s)", i, tostring(token), type(token)))
    if type(token) == "string" then
        local midi = note_to_midi(token)
        print(string.format("    -> MIDI: %d", midi or -999))
    end
end

if #warnings > 0 then
    print("\nWarnings:")
    for i, warning in ipairs(warnings) do
        print(string.format("  %d: %s", i, warning))
    end
end

-- Test complete pipeline with a simple item
print("\n3. Testing complete parsing pipeline:")
local test_item_name = "~4 c#4 d#4 eb4 f#4 gb4 a4 bb4 c5"
local stepQN, scale_ctx, body, body_clean = parse_step_header(test_item_name)

print(string.format("Step QN: %s", tostring(stepQN)))
print(string.format("Body: '%s'", body))
print(string.format("Body clean: '%s'", body_clean))

local tokens2 = tokenize(body_clean, {})
print(string.format("Tokens from complete pipeline: %d", #tokens2))
for i, token in ipairs(tokens2) do
    print(string.format("  Token %d: %s", tostring(token)))
    if type(token) == "string" then
        local midi = note_to_midi(token)
        print(string.format("    -> MIDI: %d", midi or -999))
    end
end

print("\n=== DEBUG COMPLETE ===")