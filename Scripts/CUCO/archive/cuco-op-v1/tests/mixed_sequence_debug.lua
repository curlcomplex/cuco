-- name: mixed_sequence_debug
notation = [[
~16 @96
-- Test the specific failing patterns
ch1 = [c4 c4.maj7]
ch2 = [c4.maj7 d4]
]]

expected = {
  -- From ch1: c4 + c4.maj7 (4 notes from chord)
  {pitch=60, s=0.0, e=0.25, vel=96, ch=1},    -- c4
  {pitch=60, s=0.25, e=0.5, vel=96, ch=1},    -- c4.maj7 c
  {pitch=64, s=0.25, e=0.5, vel=96, ch=1},    -- c4.maj7 e
  {pitch=67, s=0.25, e=0.5, vel=96, ch=1},    -- c4.maj7 g
  {pitch=71, s=0.25, e=0.5, vel=96, ch=1},    -- c4.maj7 b
  -- From ch2: c4.maj7 + d4 (4 notes from chord + 1 note)
  {pitch=60, s=0.0, e=0.25, vel=96, ch=2},    -- c4.maj7 c
  {pitch=64, s=0.0, e=0.25, vel=96, ch=2},    -- c4.maj7 e
  {pitch=67, s=0.0, e=0.25, vel=96, ch=2},    -- c4.maj7 g
  {pitch=71, s=0.0, e=0.25, vel=96, ch=2},    -- c4.maj7 b
  {pitch=62, s=0.25, e=0.5, vel=96, ch=2},    -- d4
}