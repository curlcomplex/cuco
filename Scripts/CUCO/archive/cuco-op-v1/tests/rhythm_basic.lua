-- name: rhythm_basic
notation = [[
~16 @96
ch1 = [c4 d4 e4 f4]
]]

expected = {
  {pitch=60, s=0.0, e=0.25, vel=96, ch=1},
  {pitch=62, s=0.25, e=0.5, vel=96, ch=1},
  {pitch=64, s=0.5, e=0.75, vel=96, ch=1},
  {pitch=65, s=0.75, e=1.0, vel=96, ch=1}
}