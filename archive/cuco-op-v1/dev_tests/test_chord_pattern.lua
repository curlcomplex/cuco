-- Standalone test for chord literal pattern matching

-- Pattern from tokenizer
local chord_pattern = "^([A-G][#b]?[%w°ø#b/]*)"

-- Test cases
local test_cases = {
    "C",
    "CM",
    "Cmaj",
    "CM7",
    "F#m7",
    "B°7",
    "DM7/F#"
}

print("Testing chord literal pattern: " .. chord_pattern)
print("=" .. string.rep("=", 50))

for _, test_case in ipairs(test_cases) do
    local match = test_case:match(chord_pattern)
    print(string.format("'%s' -> '%s'", test_case, tostring(match)))
end

-- Test the exact input from our failing test
local bracket_test = "[C]"
local content = bracket_test:sub(2, -2) -- Remove brackets
print("\nBracket test:")
print(string.format("'[C]' content -> '%s'", content))
local match = content:match(chord_pattern)
print(string.format("Match result: '%s'", tostring(match)))
