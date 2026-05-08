-- name: sequence_diagnostic
notation = [[
~16 @96
-- Test 1: Single note (should work)
ch1 = c4

-- Test 2: Single chord (should work)  
ch2 = c4.maj7

-- Test 3: Two notes (should work)
ch3 = [c4 d4]

-- Test 4: Note then chord (likely fails)
ch4 = [c4 c4.maj7]

-- Test 5: Chord then note (likely fails)
ch5 = [c4.maj7 d4]

-- Test 6: Two chords (likely fails)
ch6 = [c4.maj7 d4.min7]
]]

expected = {
  -- Just expect some events from working channels
  {pitch=60, s=0.0, e=0.25, vel=96, ch=1}
}