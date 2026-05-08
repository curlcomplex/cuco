-- Test tokenization patterns to verify accidental handling
-- This extracts the key pattern matching logic from the main script

-- Test the pattern matching used in scan_chunk_with_repeats
local function test_note_patterns()
    local test_cases = {
        -- Sharp notes
        "c#4", "d#4", "f#4", "g#4", "a#4",
        -- Flat notes  
        "db4", "eb4", "gb4", "ab4", "bb4",
        -- Natural notes
        "c4", "d4", "e4", "f4", "g4", "a4", "b4",
        -- With repeats
        "c#4*2", "db4*3",
        -- With transpose
        "c#4+2", "db4-1",
        -- With transpose and repeat
        "c#4+2*3", "db4-1*2"
    }
    
    print("Testing note pattern matching from tokenization:")
    print("=" .. string.rep("=", 60))
    
    for _, test_input in ipairs(test_cases) do
        local results = {}
        
        -- Test plain note pattern (lines 797-806 in main script)
        local note2
        note2 = test_input:match("^([a-gA-G]#%-?%d+)")  -- Sharp
        if not note2 then
            note2 = test_input:match("^([a-gA-G]b%-?%d+)")  -- Flat
        end
        if not note2 then
            note2 = test_input:match("^([a-gA-G]%-?%d+)")  -- Natural
        end
        if note2 then
            table.insert(results, "plain:" .. note2)
        end
        
        -- Test note*rep pattern (lines 686-695)
        local note, rep2
        note, rep2 = test_input:match("^([a-gA-G]#%-?%d+)%*(%d+)")  -- Sharp
        if not note then
            note, rep2 = test_input:match("^([a-gA-G]b%-?%d+)%*(%d+)")  -- Flat
        end
        if not note then
            note, rep2 = test_input:match("^([a-gA-G]%-?%d+)%*(%d+)")  -- Natural
        end
        if note and rep2 then
            table.insert(results, "repeat:" .. note .. "*" .. rep2)
        end
        
        -- Test note+/-N pattern (lines 706-715)
        local base2, tp2
        base2, tp2 = test_input:match("^([a-gA-G]#%-?%d+)([+-]%d+)")  -- Sharp
        if not base2 then
            base2, tp2 = test_input:match("^([a-gA-G]b%-?%d+)([+-]%d+)")  -- Flat
        end
        if not base2 then
            base2, tp2 = test_input:match("^([a-gA-G]%-?%d+)([+-]%d+)")  -- Natural
        end
        if base2 and tp2 then
            table.insert(results, "transpose:" .. base2 .. tp2)
        end
        
        -- Test note+/-N*rep pattern (lines 665-674)
        local base, tp, rep
        base, tp, rep = test_input:match("^([a-gA-G]#%-?%d+)([+-]%d+)%*(%d+)")  -- Sharp
        if not base then
            base, tp, rep = test_input:match("^([a-gA-G]b%-?%d+)([+-]%d+)%*(%d+)")  -- Flat
        end
        if not base then
            base, tp, rep = test_input:match("^([a-gA-G]%-?%d+)([+-]%d+)%*(%d+)")  -- Natural
        end
        if base and tp and rep then
            table.insert(results, "transpose_repeat:" .. base .. tp .. "*" .. rep)
        end
        
        -- Display results
        local result_str = #results > 0 and table.concat(results, ", ") or "NO MATCH"
        local status = #results > 0 and "PASS" or "FAIL"
        print(string.format("%-12s -> %-40s [%s]", test_input, result_str, status))
    end
    
    print("=" .. string.rep("=", 60))
end

-- Test stack parsing patterns 
local function test_stack_patterns()
    local test_cases = {
        "c#4+2", "db4-1", "f#4", "gb4", "c4"
    }
    
    print("\nTesting stack entry patterns:")
    print("=" .. string.rep("=", 60))
    
    for _, entry in ipairs(test_cases) do
        -- Test pattern from line 1329/1723 in main script
        local b, off = entry:match("^([a-gA-G][b#]?%-?%d+)([+-]%d+)$")
        
        local result = "NO MATCH"
        if b and off then
            result = "note:" .. b .. " offset:" .. off
        else
            -- Test plain note
            local note = entry:match("^([a-gA-G][b#]?%-?%d+)$")
            if note then
                result = "note:" .. note
            end
        end
        
        local status = (result ~= "NO MATCH") and "PASS" or "FAIL"
        print(string.format("%-8s -> %-35s [%s]", entry, result, status))
    end
    
    print("=" .. string.rep("=", 60))
end

-- Run tests
test_note_patterns()
test_stack_patterns()

print("\nNote: These tests verify that the pattern matching extracts accidentals correctly.")
print("If all tests pass, the tokenization should preserve sharps (#) and flats (b).")