-- Quick test script to validate current notation features
package.path = package.path .. ";/Users/f.god/Library/Application Support/REAPER/Scripts/CUCO/CUCO-OP/src/?.lua"

local engine = require("engine")

-- Test basic repeat functionality
print("=== Testing Repeat (*N) ===")
local plan1 = engine.process_notation([[
~16
ch1 = [c4*3]
]])

print("Generated events:")
for i, event in ipairs(plan1) do
    print(string.format("  %d: pitch=%d, s=%.3f, e=%.3f, vel=%d, ch=%d",
                      i, event.pitch, event.s, event.e, event.vel, event.ch))
end

-- Test rests
print("\n=== Testing Rests (_) ===")
local plan2 = engine.process_notation([[
~16
ch1 = [c4 _ d4]
]])

print("Generated events:")
for i, event in ipairs(plan2) do
    print(string.format("  %d: pitch=%d, s=%.3f, e=%.3f, vel=%d, ch=%d",
                      i, event.pitch, event.s, event.e, event.vel, event.ch))
end

-- Test sustain
print("\n=== Testing Sustain (.) ===")
local plan3 = engine.process_notation([[
~16
ch1 = [c4 . d4]
]])

print("Generated events:")
for i, event in ipairs(plan3) do
    print(string.format("  %d: pitch=%d, s=%.3f, e=%.3f, vel=%d, ch=%d",
                      i, event.pitch, event.s, event.e, event.vel, event.ch))
end

-- Test chords
print("\n=== Testing Chords ((c4 e4 g4)) ===")
local plan4 = engine.process_notation([[
~16
ch1 = [(c4 e4 g4)]
]])

print("Generated events:")
for i, event in ipairs(plan4) do
    print(string.format("  %d: pitch=%d, s=%.3f, e=%.3f, vel=%d, ch=%d",
                      i, event.pitch, event.s, event.e, event.vel, event.ch))
end
