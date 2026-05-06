-- name: simple_tokens_test
notation = [[
~16

-- Simple test with rest, sustain, and inherit tokens
ch1 = [c4 . d4 _]
]]

expected = {
  {pitch=60, s=0.0, e=0.25, vel=96, ch=1},  -- c4
  -- . (rest) should produce no event
  {pitch=62, s=0.5, e=0.75, vel=96, ch=1},  -- d4 
  -- _ (sustain) should extend d4
}