# CUCO-Stacks Comprehensive Feature Test

## Core Features Testing Todo List

### ✅ COMPLETED TESTS
- [x] Basic chord syntax: `~4 [c4 e4 g4]` ✅ **WORKING**
- [x] Arpeggiator: `~4 [c4 e4 g4]!arp(up, 8)` ✅ **WORKING**

### 🔲 TODO: BASIC SYNTAX
- [ ] Single notes: `~4 c4`
- [ ] Note sequences: `~4 c4 d4 e4 f4`  
- [ ] Rests: `~4 c4 . e4 .`
- [ ] Note repeats: `~4 c4*3`
- [ ] Transpose offsets: `~4 c4+2 c4-1`
- [ ] Different octaves: `~4 c3 c4 c5`
- [ ] Sharps/flats: `~4 c#4 db4 f#4 bb4`

### 🔲 TODO: TIMING & RHYTHMS  
- [ ] Different step resolutions: `~8`, `~16`, `~2`
- [ ] Triplet timing: `~4t`
- [ ] Quintuplet timing: `~4q` 
- [ ] Septuplet timing: `~4s`
- [ ] Nonuplet timing: `~4n`
- [ ] Mixed timing: `~8 c4 d4 ~4 e4 f4`

### 🔲 TODO: STACK SYNTAX
- [ ] Basic stacks: `~4 [c4 e4 g4]`
- [ ] Mixed stacks: `~4 [c4 . e4] [d4 f4 .]`
- [ ] Stack with rests: `~4 [c4 . .] [. e4 g4]`
- [ ] Stack inheritance: `~4 [c4 e4 g4] x x`
- [ ] Stack with offsets: `~4 [c4 e4 g4] [+2 +1 +3]`

### 🔲 TODO: LOOP SYNTAX
- [ ] Basic loops: `~4 |c4 d4 e4|2`
- [ ] Stack loops: `~4 |[c4 e4 g4] [d4 f4 a4]|3`
- [ ] Mixed loops: `~4 c4 |d4 e4|2 f4`
- [ ] Nested loops: `~4 ||c4 d4|2 e4|3`
- [ ] Loop with inheritance: `~4 |[c4 e4 g4] x x|4`

### 🔲 TODO: SCALE SYSTEM
- [ ] Major scale: `~4 @c.major [c4 d4 e4 f4 g4 a4 b4 c5]`
- [ ] Minor scale: `~4 @a.minor [c4 d4 e4 f4 g4 a4 b4 c5]`
- [ ] Blues scale: `~4 @f.blues [c4 d4 e4 f4 g4 a4 b4 c5]`
- [ ] Pentatonic: `~4 @d.pentatonic [c4 d4 e4 g4 a4 c5]`
- [ ] Japanese scale: `~4 @a.japanese [c4 d4 e4 f4 g4 a4 b4 c5]`
- [ ] Quantization modes: `@c.major.up`, `@c.major.down`, `@c.major.near`, `@c.major.ignore`

### 🔲 TODO: ARPEGGIATOR VARIATIONS
- [ ] Arp directions: `!arp(down, 8)`, `!arp(updown, 8)`, `!arp(rand, 8)`
- [ ] Arp with span: `!arp(up, 8, 2)`
- [ ] Pendulum: `!arp(pend, 8)`
- [ ] Inside-out: `!arp(io, 8)`
- [ ] Outside-in: `!arp(oi, 8)`
- [ ] Zigzag: `!arp(zz, 8)`
- [ ] Skip patterns: `!arp(skip2, 8)`
- [ ] Rotate: `!arp(rot2, 8)`

### 🔲 TODO: SHORTHAND PROCESSORS
- [ ] Up shorthand: `!up/8`
- [ ] Down shorthand: `!down/8`
- [ ] Random shorthand: `!rand/8`
- [ ] Pendulum shorthand: `!pend/8`

### �2 TODO: COMPLEX COMBINATIONS
- [ ] Scale + Arp: `~4 @c.major [c4 e4 g4]!arp(up, 8)`
- [ ] Loop + Scale: `~4 @g.minor |[c4 e4 g4] [d4 f4 a4]|2`
- [ ] Loop + Arp: `~4 |[c4 e4 g4]!arp(up, 4) [d4 f4 a4]!arp(down, 4)|2`
- [ ] Multiple processors: `~4 [c4 e4 g4]!arp(up, 4)!rand/8`

### 🔲 TODO: EDGE CASES
- [ ] Empty syntax: `~4`
- [ ] All rests: `~4 . . . .`
- [ ] Single rest: `~4 .`
- [ ] Very long sequences: `~16 c4 d4 e4 f4 g4 a4 b4 c5 d5 e5 f5 g5 a5 b5 c6 d6`
- [ ] Very fast arps: `~4 [c4 e4 g4]!arp(up, 32)`

### 🔲 TODO: DEBUG & TRACING
- [ ] Basic debug: `~4 [c4 e4 g4] //debug`
- [ ] Full debug: `~4 [c4 e4 g4] //debug //full`
- [ ] Trace mode: `~4 [c4 e4 g4] //trace`
- [ ] Notes debug: `~4 [c4 e4 g4] //debug //notes`

## Test Results Log
Date: 2024-09-14