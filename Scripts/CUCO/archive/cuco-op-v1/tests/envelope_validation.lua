-- name: envelope_validation
notation = [[
~16
seq = [c4 d4 e4]
ch1 = seq !env(linear,60,120)
]]

expected = {
  {pitch=60, s=0.0, e=0.25, vel=60, ch=1},
  {pitch=62, s=0.25, e=0.5, vel=90, ch=1},
  {pitch=64, s=0.5, e=0.75, vel=120, ch=1},
}