-- name: original_user_issue
notation = [[
~16
seq = [c4 CM d4 CM]
ch1 = seq !transpose(-3)
]]

expected = {
  {pitch=57, s=0.0, e=0.25, vel=96, ch=1},     -- c4 -> a3
  {pitch=57, s=0.25, e=0.5, vel=96, ch=1},     -- CM C -> a3
  {pitch=61, s=0.25, e=0.5, vel=96, ch=1},     -- CM E -> c#4
  {pitch=64, s=0.25, e=0.5, vel=96, ch=1},     -- CM G -> e4
  {pitch=59, s=0.5, e=0.75, vel=96, ch=1},     -- d4 -> b3
  {pitch=57, s=0.75, e=1.0, vel=96, ch=1},     -- CM C -> a3
  {pitch=61, s=0.75, e=1.0, vel=96, ch=1},     -- CM E -> c#4
  {pitch=64, s=0.75, e=1.0, vel=96, ch=1},     -- CM G -> e4
}