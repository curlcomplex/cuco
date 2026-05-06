-- name: debug_tokenization
notation = [[
~16
ch1 = [c4 _ d4 _ _ c4]
]]

expected = {
  {pitch=60, s=0.0, e=0.25, vel=96, ch=1},   -- c4
  -- _ extends c4 to 0.5
  {pitch=62, s=0.5, e=0.75, vel=96, ch=1},   -- d4 
  -- _ _ extends d4 to 1.25
  {pitch=60, s=1.25, e=1.5, vel=96, ch=1},   -- final c4
}