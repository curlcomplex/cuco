-- name: timing_complex
notation = [[
~16 @96
melody = [c4 d4 e4 f4]
ch1 = melody
ch2 = melody !transpose(7)
ch3 = melody !transpose(-5)
]]

expected = {
  -- Channel 1: c4 d4 e4 f4 starting at 0.0
  {pitch=60, s=0.0, e=0.25, vel=96, ch=1},    -- c4
  {pitch=62, s=0.25, e=0.5, vel=96, ch=1},    -- d4  
  {pitch=64, s=0.5, e=0.75, vel=96, ch=1},    -- e4
  {pitch=65, s=0.75, e=1.0, vel=96, ch=1},    -- f4
  -- Channel 2: melody+7 semitones, also starting at 0.0
  {pitch=67, s=0.0, e=0.25, vel=96, ch=2},    -- g4 (c4+7)
  {pitch=69, s=0.25, e=0.5, vel=96, ch=2},    -- a4 (d4+7)
  {pitch=71, s=0.5, e=0.75, vel=96, ch=2},    -- b4 (e4+7)
  {pitch=72, s=0.75, e=1.0, vel=96, ch=2},    -- c5 (f4+7)
  -- Channel 3: melody-5 semitones, also starting at 0.0  
  {pitch=55, s=0.0, e=0.25, vel=96, ch=3},    -- g3 (c4-5)
  {pitch=57, s=0.25, e=0.5, vel=96, ch=3},    -- a3 (d4-5)
  {pitch=59, s=0.5, e=0.75, vel=96, ch=3},    -- b3 (e4-5)
  {pitch=60, s=0.75, e=1.0, vel=96, ch=3},    -- c4 (f4-5)
}