-- Simple test to verify the accidental parsing fix
-- Tests the note pattern directly

-- Test the new comprehensive note pattern
local function test_comprehensive_pattern()
    print("=== TESTING COMPREHENSIVE NOTE PATTERN ===")
    
    local test_notes = {
        "c4", "c#4", "d4", "d#4", "eb4", "e4", 
        "f4", "f#4", "gb4", "g4", "a4", "bb4", "c5"
    }
    
    print("Testing pattern: ^([a-gA-G][b#]?%-?%d+)")
    
    for _, note in ipairs(test_notes) do
        local captured = note:match("^([a-gA-G][b#]?%-?%d+)")
        local status = captured and "✓" or "✗"
        print(string.format("  %s %s -> '%s'", status, note, captured or "NO MATCH"))
        
        if captured ~= note then
            print(string.format("    ERROR: Expected '%s', got '%s'", note, captured or "nil"))
        end
    end
    
    print("\nTesting with repeats (*N):")
    local repeat_tests = {"c#4*2", "eb4*3", "f#4*4"}
    for _, test in ipairs(repeat_tests) do
        local note, rep = test:match("^([a-gA-G][b#]?%-?%d+)%*(%d+)")
        local status = (note and rep) and "✓" or "✗"
        print(string.format("  %s %s -> note:'%s' repeat:%s", status, test, note or "nil", rep or "nil"))
    end
    
    print("\nTesting with transpose (+/-N):")
    local transpose_tests = {"c#4+2", "eb4-1", "f#4+5"}
    for _, test in ipairs(transpose_tests) do
        local note, tp = test:match("^([a-gA-G][b#]?%-?%d+)([+-]%d+)")
        local status = (note and tp) and "✓" or "✗"
        print(string.format("  %s %s -> note:'%s' transpose:%s", status, test, note or "nil", tp or "nil"))
    end
    
    print("\nTesting with transpose and repeat:")
    local complex_tests = {"c#4+2*3", "eb4-1*2"}
    for _, test in ipairs(complex_tests) do
        local note, tp, rep = test:match("^([a-gA-G][b#]?%-?%d+)([+-]%d+)%*(%d+)")
        local status = (note and tp and rep) and "✓" or "✗"
        print(string.format("  %s %s -> note:'%s' transpose:%s repeat:%s", status, test, note or "nil", tp or "nil", rep or "nil"))
    end
end

-- Run the test
test_comprehensive_pattern()
print("\n=== TEST COMPLETE ===")

-- Test specific problem case
print("\nTesting the specific problem case from your issue:")
local problem_notes = {"c#4", "d#4", "eb4", "f#4", "gb4", "bb4"}
for _, note in ipairs(problem_notes) do
    local captured = note:match("^([a-gA-G][b#]?%-?%d+)")
    local status = (captured == note) and "✓ FIXED" or "✗ STILL BROKEN"
    print(string.format("  %s %s", status, note))
end