# T-026/T-027 — verify byte-identical MIDI output after events[] refactor

**Status:** Refactor committed (09b5835), UNVERIFIED in REAPER.

## What landed
Combined T-026 + T-027 in commit 09b5835:
- `make_executor` closure-owns `events = {}`; `emit_event` helper pushes records
- `flush_voice`/`flush_all` write-mode branches → `emit_event` (was: `insert_notes`)
- Returns `exec_window, events, flush_all`
- Write-mode call site flushes trailing voices via `flush_all()` then `write_events_to_midi(take, events)` does the terminal write pass
- Plan mode untouched (still uses recorder callback)

## Verification needed
Pure refactor must produce byte-identical MIDI output vs pre-refactor (commit 2a8ed96).

**Check procedure:**
1. In REAPER, take a MIDI item with a known v0.8.1 pattern (chord + arp + hold, e.g. `c4.maj7 _ d4 _`)
2. Run `Scripts/CUCO/projects/tidal-notation/CUCO Tidal Notation 0.8.1.lua` — capture MIDI hash via `mcp__reaper__get_midi_hash` or manually compare note start/end PPQ + pitch + vel + chan
3. `git stash` the refactor (or checkout 2a8ed96), regenerate, hash again
4. Hashes must match exactly

If mismatch: most likely culprit is iteration order in `flush_all` (Lua `pairs` over sparse `voice_current` is non-deterministic, but `MIDI_InsertNote` was previously called in the same non-deterministic order, so order-of-insertion shouldn't differ — but if hash differs, sort `events` by `sQN, pitch` before write).

## On success
- Close T-026 + T-027
- Clear handover_pending on T-026
- Move to Phase 0b/c (next foundation work) or v1.0 grammar implementation
