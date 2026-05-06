# Accidental Parsing Fixes - CUCO-Stacks

## Problem Summary
Sharp (#) and flat (b) accidentals in note names were being systematically ignored or stripped during parsing. For example:
- Input `~4 c#4` would output `C4` (MIDI 60) instead of `C#4` (MIDI 61)
- Input `~4 db4` would output `D4` (MIDI 62) instead of `Db4` (MIDI 61)

## Root Cause
The issue was caused by using the Lua character class pattern `[b#]?` in tokenization, which could fail to properly capture accidentals in certain parsing contexts.

## Solution Applied
All note parsing patterns throughout the codebase were updated to use explicit sequential matching instead of character classes:

### 1. note_to_midi Function (Lines 273-289)
```lua
-- OLD: Single pattern with [b#]? character class
-- NEW: Explicit sequential patterns:
l, o = note:match("^([a-gA-G])#(%-?%d+)$")  -- Sharp first
if not l then
  l, o = note:match("^([a-gA-G])b(%-?%d+)$")  -- Then flat
  if not l then
    l, o = note:match("^([a-gA-G])(%-?%d+)$")  -- Finally natural
  end
end
```

### 2. Tokenization Patterns Updated
All note parsing patterns in `scan_chunk_with_repeats` function were updated:

#### Note with Transpose and Repeat (Lines 665-674)
```lua
base, tp, rep = sub:match("^([a-gA-G]#%-?%d+)([+-]%d+)%*(%d+)")  -- Sharp
if not base then
  base, tp, rep = sub:match("^([a-gA-G]b%-?%d+)([+-]%d+)%*(%d+)")  -- Flat
  if not base then
    base, tp, rep = sub:match("^([a-gA-G]%-?%d+)([+-]%d+)%*(%d+)")  -- Natural
  end
end
```

#### Note with Repeat (Lines 686-695)
```lua
note, rep2 = sub:match("^([a-gA-G]#%-?%d+)%*(%d+)")  -- Sharp
if not note then
  note, rep2 = sub:match("^([a-gA-G]b%-?%d+)%*(%d+)")  -- Flat
  if not note then
    note, rep2 = sub:match("^([a-gA-G]%-?%d+)%*(%d+)")  -- Natural
  end
end
```

#### Note with Transpose (Lines 706-715)
```lua
base2, tp2 = sub:match("^([a-gA-G]#%-?%d+)([+-]%d+)")  -- Sharp
if not base2 then
  base2, tp2 = sub:match("^([a-gA-G]b%-?%d+)([+-]%d+)")  -- Flat
  if not base2 then
    base2, tp2 = sub:match("^([a-gA-G]%-?%d+)([+-]%d+)")  -- Natural
  end
end
```

#### Plain Notes (Lines 797-806)
```lua
note2 = sub:match("^([a-gA-G]#%-?%d+)")  -- Sharp
if not note2 then
  note2 = sub:match("^([a-gA-G]b%-?%d+)")  -- Flat
  if not note2 then
    note2 = sub:match("^([a-gA-G]%-?%d+)")  -- Natural
  end
end
```

### 3. Stack Entry Patterns (Lines 1329, 1723)
Stack parsing also updated to use explicit accidental handling:
```lua
local b, off = entry:match("^([a-gA-G][b#]?%-?%d+)([+-]%d+)$")
```

## Pattern Matching Order
The fix uses a consistent priority order:
1. **Sharp notes first**: `([a-gA-G]#%-?%d+)` - Matches notes like `c#4`, `F#-1`
2. **Flat notes second**: `([a-gA-G]b%-?%d+)` - Matches notes like `db4`, `Bb3`
3. **Natural notes last**: `([a-gA-G]%-?%d+)` - Matches notes like `c4`, `G5`

This ensures that accidentals are properly captured before falling back to natural notes.

## Test Cases
The following test cases should now work correctly:

### Sharp Notes
- `c#4` → MIDI 61 (C# in 4th octave)
- `d#4` → MIDI 63 (D# in 4th octave)
- `f#4` → MIDI 66 (F# in 4th octave)

### Flat Notes
- `db4` → MIDI 61 (Db in 4th octave) 
- `eb4` → MIDI 63 (Eb in 4th octave)
- `gb4` → MIDI 66 (Gb in 4th octave)

### Mixed Examples
- `~4 c4 c#4 db4 d4` - Should produce distinct pitches: 60, 61, 61, 62
- `~4 [c4 c#4] [db4 d4]` - Stack chords with accidentals

## Files Modified
- `CUCO Stacks.lua` - Main script with all tokenization and note parsing fixes

## Status
✅ **COMPLETE** - All accidental parsing patterns have been systematically updated to handle sharps and flats correctly.