-- name: timing_test
notation = [[
~16 @96
ch1 = [c4 d4]
ch2 = [e4 f4]
]]

expected = {
  -- Channel 1 should start at 0.0
  {pitch=60, s=0.0, e=0.25, vel=96, ch=1},    -- c4
  {pitch=62, s=0.25, e=0.5, vel=96, ch=1},    -- d4
  -- Channel 2 should also start at 0.0 (simultaneous)
  {pitch=64, s=0.0, e=0.25, vel=96, ch=2},    -- e4
  {pitch=65, s=0.25, e=0.5, vel=96, ch=2},    -- f4
}