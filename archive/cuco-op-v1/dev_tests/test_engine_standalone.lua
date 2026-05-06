#!/usr/bin/env lua
-- Standalone test for CUCO-OP Engine
-- Run with: lua test_engine_standalone.lua

-- Add src path
local src_path = arg[0]:match("(.+)/") .. "src/"
package.path = package.path .. ";" .. src_path .. "?.lua"

-- Load the engine
local engine = require("engine")

-- Test cases
local test_cases = {
    {
        name = "Basic notes",
        notation = [[
~16
seq = [c4 d4 e4]
ch1 = seq
]],
        expected_count = 3,
        expected_first_pitch = 60,
        expected_last_pitch = 64
    },

    {
        name = "With sustain",
        notation = [[
~16
seq = [c4 . d4]
ch1 = seq
]],
        expected_count = 2,
        expected_first_pitch = 60,
        -- c4 should be extended by sustain
        custom_check = function(plan)
            if plan[1].e ~= 0.5 then
                return false, "Expected c4 to be extended to 0.5 QN, got " .. plan[1].e
            end
            return true
        end
    },

    {
        name = "With rest",
        notation = [[
~16
seq = [c4 _ d4]
ch1 = seq
]],
        expected_count = 2,
        expected_first_pitch = 60,
        custom_check = function(plan)
            -- d4 should start at 0.5 due to rest
            if plan[2].s ~= 0.5 then
                return false, "Expected d4 to start at 0.5 QN, got " .. plan[2].s
            end
            return true
        end
    },

    {
        name = "With repeat",
        notation = [[
~16
seq = [c4*3]
ch1 = seq
]],
        expected_count = 3,
        expected_first_pitch = 60,
        expected_last_pitch = 60
    },

    {
        name = "Basic chord",
        notation = [[
~16
seq = [(c4 e4 g4)]
ch1 = seq
]],
        expected_count = 3,
        expected_first_pitch = 60,
        custom_check = function(plan)
            -- All chord notes should start at same time
            if plan[1].s ~= plan[2].s or plan[2].s ~= plan[3].s then
                return false, "Chord notes should start simultaneously"
            end
            -- Check pitches are c4, e4, g4
            local pitches = {plan[1].pitch, plan[2].pitch, plan[3].pitch}
            table.sort(pitches)
            if pitches[1] ~= 60 or pitches[2] ~= 64 or pitches[3] ~= 67 then
                return false, "Expected C major triad pitches [60, 64, 67]"
            end
            return true
        end
    },

    {
        name = "Chord with repeat",
        notation = [[
~16
seq = [(c4 e4)*2]
ch1 = seq
]],
        expected_count = 4,
        custom_check = function(plan)
            -- Should have two chords
            if plan[1].s ~= 0.0 or plan[2].s ~= 0.0 then
                return false, "First chord should start at 0.0"
            end
            if plan[3].s ~= 0.25 or plan[4].s ~= 0.25 then
                return false, "Second chord should start at 0.25"
            end
            return true
        end
    }
}

-- Run tests
local passed = 0
local failed = 0

print("Running CUCO-OP Engine Tests...")
print("================================")

for i, test in ipairs(test_cases) do
    print(string.format("\n%d. %s", i, test.name))

    local ok, result = pcall(function()
        local plan = engine.process_notation(test.notation)

        -- Check event count
        if test.expected_count and #plan ~= test.expected_count then
            error(string.format("Expected %d events, got %d", test.expected_count, #plan))
        end

        -- Check first pitch
        if test.expected_first_pitch and #plan > 0 and plan[1].pitch ~= test.expected_first_pitch then
            error(string.format("Expected first pitch %d, got %d", test.expected_first_pitch, plan[1].pitch))
        end

        -- Check last pitch
        if test.expected_last_pitch and #plan > 0 and plan[#plan].pitch ~= test.expected_last_pitch then
            error(string.format("Expected last pitch %d, got %d", test.expected_last_pitch, plan[#plan].pitch))
        end

        -- Run custom check if provided
        if test.custom_check then
            local ok, msg = test.custom_check(plan)
            if not ok then
                error("Custom check failed: " .. (msg or "unknown reason"))
            end
        end

        return plan
    end)

    if ok then
        print("   ✓ PASSED (" .. #result .. " events generated)")
        passed = passed + 1
    else
        print("   ✗ FAILED: " .. tostring(result))
        failed = failed + 1
    end
end

-- Summary
print("\n================================")
print(string.format("Results: %d passed, %d failed", passed, failed))

if failed == 0 then
    print("🎉 All tests PASSED!")

    -- Run self-test
    print("\nRunning engine self-test...")
    engine.self_test()

else
    print("❌ Some tests FAILED!")
    os.exit(1)
end
