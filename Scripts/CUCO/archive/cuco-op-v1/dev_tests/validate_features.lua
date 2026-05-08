-- Simple validation test for CUCO-OP notation features
-- This creates a minimal test that can run without external Lua interpreters

-- Mock print function that collects output
local test_output = {}
local original_print = print
print = function(...)
    local args = {...}
    local str = ""
    for i, v in ipairs(args) do
        if i > 1 then str = str .. "\t" end
        str = str .. tostring(v)
    end
    table.insert(test_output, str)
    original_print(str)
end

-- Add src path for requires
local current_dir = "/Users/f.god/Library/Application Support/REAPER/Scripts/CUCO/CUCO-OP/"
package.path = package.path .. ";" .. current_dir .. "src/?.lua"

-- Test function
local function test_notation_feature(name, notation_str, expected_event_count, validator)
    print("Testing: " .. name)

    local ok, result = pcall(function()
        local engine = require("engine")
        local plan = engine.process_notation(notation_str)

        if expected_event_count and #plan ~= expected_event_count then
            error("Expected " .. expected_event_count .. " events, got " .. #plan)
        end

        if validator then
            local valid, msg = validator(plan)
            if not valid then
                error("Validation failed: " .. (msg or "unknown"))
            end
        end

        return plan
    end)

    if ok then
        print("✓ PASSED (" .. #result .. " events)")
        return true
    else
        print("✗ FAILED: " .. tostring(result))
        return false
    end
end

-- Run tests
local passed = 0
local failed = 0

print("=== CUCO-OP Notation Features Test ===")

-- Test 1: Basic repeat
if test_notation_feature("Repeat *N", [[
~16
ch1 = [c4*3]
]], 3) then
    passed = passed + 1
else
    failed = failed + 1
end

-- Test 2: Rest
if test_notation_feature("Rest _", [[
~16
ch1 = [c4 _ d4]
]], 2, function(plan)
    -- d4 should start after the rest
    if plan[2].s <= plan[1].e then
        return false, "Rest didn't advance timeline properly"
    end
    return true
end) then
    passed = passed + 1
else
    failed = failed + 1
end

-- Test 3: Sustain
if test_notation_feature("Sustain .", [[
~16
ch1 = [c4 . d4]
]], 2, function(plan)
    -- c4 should be extended by sustain
    if plan[1].e <= 0.25 then
        return false, "Sustain didn't extend note duration"
    end
    return true
end) then
    passed = passed + 1
else
    failed = failed + 1
end

-- Test 4: Basic chord
if test_notation_feature("Chord (c4 e4 g4)", [[
~16
ch1 = [(c4 e4 g4)]
]], 3, function(plan)
    -- All chord notes should start at same time
    if plan[1].s ~= plan[2].s or plan[2].s ~= plan[3].s then
        return false, "Chord notes don't start simultaneously"
    end
    return true
end) then
    passed = passed + 1
else
    failed = failed + 1
end

-- Test 5: Absolute velocity
if test_notation_feature("Absolute velocity @N", [[
~16
ch1 = [c4@80 d4@120]
]], 2, function(plan)
    if plan[1].vel ~= 80 or plan[2].vel ~= 120 then
        return false, "Absolute velocity not applied correctly: got " .. plan[1].vel .. ", " .. plan[2].vel
    end
    return true
end) then
    passed = passed + 1
else
    failed = failed + 1
end

-- Test 6: Relative velocity
if test_notation_feature("Relative velocity @±N", [[
~16
ch1 = [c4@+10 d4@-5]
]], 2, function(plan)
    -- Baseline is 96, so should be 106 and 91
    if plan[1].vel ~= 106 or plan[2].vel ~= 91 then
        return false, "Relative velocity not applied correctly: got " .. plan[1].vel .. ", " .. plan[2].vel
    end
    return true
end) then
    passed = passed + 1
else
    failed = failed + 1
end

-- Test 7: Accents
if test_notation_feature("Accents ^ and !", [[
~16
ch1 = [c4^ d4!]
]], 2, function(plan)
    -- Normal accent +12, strong accent +24 (from baseline 96)
    if plan[1].vel ~= 108 or plan[2].vel ~= 120 then
        return false, "Accents not applied correctly: got " .. plan[1].vel .. ", " .. plan[2].vel
    end
    return true
end) then
    passed = passed + 1
else
    failed = failed + 1
end

-- Test 8: Articulations
if test_notation_feature("Articulations .stac/.leg", [[
~16
ch1 = [c4.stac d4.leg]
]], 2, function(plan)
    -- Staccato: 0.5x duration, Legato: 1.1x duration
    local expected_stac = 0.25 * 0.5  -- 0.125
    local expected_leg = 0.25 * 1.1   -- 0.275
    local stac_dur = plan[1].e - plan[1].s
    local leg_dur = plan[2].e - plan[2].s
    if math.abs(stac_dur - expected_stac) > 0.01 or math.abs(leg_dur - expected_leg) > 0.01 then
        return false, "Articulation durations incorrect: stac=" .. stac_dur .. ", leg=" .. leg_dur
    end
    return true
end) then
    passed = passed + 1
else
    failed = failed + 1
end

-- Test 9: Velocity curve processor
if test_notation_feature("Velocity curve !vel(linear,60,100)", [[
~16
ch1 = [c4 d4 e4]!vel(linear,60,100)
]], 3, function(plan)
    -- Linear interpolation: 60, 80, 100
    if plan[1].vel ~= 60 or plan[2].vel ~= 80 or plan[3].vel ~= 100 then
        return false, "Velocity curve incorrect: got " .. plan[1].vel .. ", " .. plan[2].vel .. ", " .. plan[3].vel
    end
    return true
end) then
    passed = passed + 1
else
    failed = failed + 1
end

-- Test 10: Accent header
if test_notation_feature("Accent header @accent(8)", [[
~16
@accent(8)
ch1 = [c4^]
]], 1, function(plan)
    -- Custom accent delta: 96 + 8 = 104
    if plan[1].vel ~= 104 then
        return false, "Accent header not applied: got " .. plan[1].vel .. ", expected 104"
    end
    return true
end) then
    passed = passed + 1
else
    failed = failed + 1
end

-- Test 11: Combined features
if test_notation_feature("Combined features", [[
~16
ch1 = [(c4 e4)*2 _ d4@80^ .]
]], 5, function(plan)
    -- Should have chord repeated, then rest, then velocity + accent note, extended by sustain
    if #plan ~= 5 then
        return false, "Expected 5 events for combined test, got " .. #plan
    end
    -- d4 should have velocity 80 + accent 12 = 92
    local d4_event = plan[5] -- Last event should be d4
    if d4_event.vel ~= 92 then
        return false, "Combined velocity+accent incorrect: got " .. d4_event.vel .. ", expected 92"
    end
    return true
end) then
    passed = passed + 1
else
    failed = failed + 1
end

-- Summary
print("\n=== Results ===")
print("Passed: " .. passed)
print("Failed: " .. failed)

if failed == 0 then
    print("🎉 All notation features working correctly!")
else
    print("❌ Some features need fixing")
end

-- Restore original print
print = original_print
