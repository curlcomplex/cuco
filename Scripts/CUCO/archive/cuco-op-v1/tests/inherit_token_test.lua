-- name: inherit_token_test
notation = [[
~16

-- Test inherit token (-) functionality
ch1 = [c4 d4 - e4]
]]

expected = {
  {pitch=60, s=0.0, e=0.25, vel=96, ch=1},  -- c4
  {pitch=62, s=0.25, e=0.5, vel=96, ch=1},  -- d4
  {pitch=62, s=0.5, e=0.75, vel=96, ch=1},  -- - (inherit d4)
  {pitch=64, s=0.75, e=1.0, vel=96, ch=1},  -- e4
}