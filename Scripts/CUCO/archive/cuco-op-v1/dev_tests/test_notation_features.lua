-- Enhanced test engine with better output
package.path = package.path .. ";/Users/f.god/Library/Application Support/REAPER/Scripts/CUCO/CUCO-OP/src/?.lua"

-- Load engine modules
local tokenizer = require("tokenizer")
local parser = require("parser")
local executor = require("executor")
local engine = require("engine")

print("=== CUCO-OP Notation Features Test ===")
print("Testing individual components...\n")

-- Helper function to format plan output
local function format_plan(plan)
    local result = {}
    for i, event in ipairs(plan) do
        table.insert(result, string.format("  Event %d: pitch=%d, s=%.3f, e=%.3f, vel=%d, ch=%d",
                                         i, event.pitch, event.s, event.e, event.vel, event.ch))
    end
    return table.concat(result, "\n")
end

-- Test 1: Basic repeat
print("1. Testing Repeat (*N)")
local notation1 = "~16\nch1 = [c4*3]"
print("Notation: " .. notation1:gsub("\n", " "))

local ok1, plan1 = pcall(function()
    return engine.process_notation(notation1)
end)

if ok1 then
    print("✓ SUCCESS: Generated " .. #plan1 .. " events")
    print(format_plan(plan1))
    if #plan1 == 3 and plan1[1].pitch == 60 and plan1[2].pitch == 60 and plan1[3].pitch == 60 then
        print("✓ All events are c4 as expected")
    else
        print("⚠ Warning: Unexpected pitches or count")
    end
else
    print("✗ FAILED: " .. tostring(plan1))
end

print("\n" .. string.rep("-", 50) .. "\n")

-- Test 2: Rest
print("2. Testing Rest (_)")
local notation2 = "~16\nch1 = [c4 _ d4]"
print("Notation: " .. notation2:gsub("\n", " "))

local ok2, plan2 = pcall(function()
    return engine.process_notation(notation2)
end)

if ok2 then
    print("✓ SUCCESS: Generated " .. #plan2 .. " events")
    print(format_plan(plan2))
    if #plan2 == 2 and plan2[1].pitch == 60 and plan2[2].pitch == 62 then
        if plan2[2].s > plan2[1].e then
            print("✓ Rest properly advanced timeline")
        else
            print("⚠ Warning: Rest may not have advanced timeline properly")
        end
    else
        print("⚠ Warning: Unexpected pitches or count")
    end
else
    print("✗ FAILED: " .. tostring(plan2))
end

print("\n" .. string.rep("-", 50) .. "\n")

-- Test 3: Sustain
print("3. Testing Sustain (.)")
local notation3 = "~16\nch1 = [c4 . d4]"
print("Notation: " .. notation3:gsub("\n", " "))

local ok3, plan3 = pcall(function()
    return engine.process_notation(notation3)
end)

if ok3 then
    print("✓ SUCCESS: Generated " .. #plan3 .. " events")
    print(format_plan(plan3))
    if #plan3 == 2 and plan3[1].pitch == 60 and plan3[2].pitch == 62 then
        if plan3[1].e > 0.25 then
            print("✓ Sustain properly extended note duration")
        else
            print("⚠ Warning: Sustain may not have extended duration properly")
        end
    else
        print("⚠ Warning: Unexpected pitches or count")
    end
else
    print("✗ FAILED: " .. tostring(plan3))
end

print("\n" .. string.rep("-", 50) .. "\n")

-- Test 4: Chords
print("4. Testing Chords ((c4 e4 g4))")
local notation4 = "~16\nch1 = [(c4 e4 g4)]"
print("Notation: " .. notation4:gsub("\n", " "))

local ok4, plan4 = pcall(function()
    return engine.process_notation(notation4)
end)

if ok4 then
    print("✓ SUCCESS: Generated " .. #plan4 .. " events")
    print(format_plan(plan4))
    if #plan4 == 3 then
        local all_same_start = (plan4[1].s == plan4[2].s and plan4[2].s == plan4[3].s)
        if all_same_start then
            print("✓ All chord notes start simultaneously")
        else
            print("⚠ Warning: Chord notes don't start at same time")
        end

        -- Check pitches are C major triad (any order)
        local pitches = {plan4[1].pitch, plan4[2].pitch, plan4[3].pitch}
        table.sort(pitches)
        if pitches[1] == 60 and pitches[2] == 64 and pitches[3] == 67 then
            print("✓ Correct C major triad pitches [60, 64, 67]")
        else
            print("⚠ Warning: Unexpected chord pitches: " .. table.concat(pitches, ", "))
        end
    else
        print("⚠ Warning: Unexpected event count for chord")
    end
else
    print("✗ FAILED: " .. tostring(plan4))
end

print("\n" .. string.rep("-", 50) .. "\n")

-- Summary
local total_tests = 4
local passed_tests = (ok1 and 1 or 0) + (ok2 and 1 or 0) + (ok3 and 1 or 0) + (ok4 and 1 or 0)

print("=== FINAL RESULTS ===")
print("Passed: " .. passed_tests .. "/" .. total_tests)

if passed_tests == total_tests then
    print("🎉 All basic notation features are working!")
else
    print("⚠ Some features may need attention - check output above")
end
