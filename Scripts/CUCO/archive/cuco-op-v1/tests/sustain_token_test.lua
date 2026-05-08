-- name: sustain_token_test
notation = [[
~16

-- Test sustain token (_) functionality - should extend previous note
ch1 = [c4 _ d4 _ _ c4]
]]

expected = {
  {pitch=60, s=0.0, e=0.5, vel=96, ch=1},   -- c4 extended by _
  {pitch=62, s=0.5, e=1.25, vel=96, ch=1}, -- d4 extended by _ _
  {pitch=60, s=1.25, e=1.5, vel=96, ch=1}, -- final c4
}
