-- name: timing_debug  
notation = [[
~16 @96
ch1 = [c4 d4]
ch2 = [e4 f4]
]]

expected = {
  -- Correct expectations - both channels start at 0.0
  {pitch=60, s=0.0, e=0.25, vel=96, ch=1},    -- c4
  {pitch=62, s=0.25, e=0.5, vel=96, ch=1},    -- d4
  {pitch=64, s=0.0, e=0.25, vel=96, ch=2},    -- e4 - starts at 0.0
  {pitch=65, s=0.25, e=0.5, vel=96, ch=2},    -- f4 - continues at 0.25
}
