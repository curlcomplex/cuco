-- name: chord_stacking_test
notation = [[
~16

-- Test that chords assigned to multiple channels are stacked (simultaneous)
jazz = [c4.maj7 d4.min7]
ch1 = jazz
ch2 = jazz
]]

expected = {
  -- First chord (c4.maj7) - both channels simultaneous at 0.0
  {pitch=60, s=0.0, e=0.25, vel=96, ch=1},    -- C 
  {pitch=60, s=0.0, e=0.25, vel=96, ch=2},    -- C 
  {pitch=64, s=0.0, e=0.25, vel=96, ch=1},    -- E 
  {pitch=64, s=0.0, e=0.25, vel=96, ch=2},    -- E 
  {pitch=67, s=0.0, e=0.25, vel=96, ch=1},    -- G
  {pitch=67, s=0.0, e=0.25, vel=96, ch=2},    -- G
  {pitch=71, s=0.0, e=0.25, vel=96, ch=1},    -- B
  {pitch=71, s=0.0, e=0.25, vel=96, ch=2},    -- B
  -- Second chord (d4.min7) - both channels simultaneous at 0.25
  {pitch=62, s=0.25, e=0.5, vel=96, ch=1},    -- D 
  {pitch=62, s=0.25, e=0.5, vel=96, ch=2},    -- D 
  {pitch=65, s=0.25, e=0.5, vel=96, ch=1},    -- F
  {pitch=65, s=0.25, e=0.5, vel=96, ch=2},    -- F
  {pitch=69, s=0.25, e=0.5, vel=96, ch=1},    -- A
  {pitch=69, s=0.25, e=0.5, vel=96, ch=2},    -- A
  {pitch=72, s=0.25, e=0.5, vel=96, ch=1},    -- C
  {pitch=72, s=0.25, e=0.5, vel=96, ch=2},    -- C
}
