# SPEC-006 — Control-driven JSFX Sequencers

**Status:** open · draft · v0.1
**Type:** specification
**Scope:** MIDI/CC-emitting JSFX in the CUCO control-driven suite
**Companion:** `.planning/research/control-driven-jsfx-architecture.md` (K-006 — umbrella philosophy)

## Purpose

Define the contract a CUCO JSFX must satisfy to be classified as a
**control-driven sequencer**: a MIDI/CC source whose entire sequence
shape (steps, density, swing, scale, range, gate, etc.) is encoded as
sliders that are *themselves* automation-receptive — so framers
(Keyframer, Random Walk, envelope lanes) can modulate the sequence in
real time *while it plays*.

A sequencer in this class is **a peer to Keyframer and Random Walk in
the framer hierarchy**, but lives in the FX chain rather than in
ReaScript. It is a control transformer: control data in (via its
sliders) → MIDI events out.

## Opt-in criteria

A JSFX is a control-driven sequencer if and only if **all** of:

1. **MIDI/CC out.** Emits via `midisend` (or `midisend_buf`) at
   sample-accurate offsets within `@block` / `@sample`.
2. **Sequence shape is sliders.** Step values, density, swing, scale,
   range, gate length, probability — all of it slider-encoded. Hidden
   internal step buffers that aren't reachable from automation are
   forbidden (see *Step storage* below for the legal exception).
3. **Framer-receptive.** Sliders that define the sequence (not just
   transport / setup) must respond to envelope-lane modulation while
   the sequence plays without reset, glitch, or phase loss.
4. **Transport-synced.** Uses `play_position` / `beat_position` /
   `tempo` / `ts_num` / `ts_denom` for timing. Free-running
   ("untethered") sequencers belong outside this class.

## Required conventions

### MIDI emission

- **Sample-accurate offset.** `midisend(offset, msg1, msg23)` where
  `offset` is the per-sample position within the current block.
  Compute it by snapping `beat_position`-derived event times to sample
  positions, *not* by counting `@sample` ticks (drifts under tempo
  changes).
- **Declare the MIDI stance** in the header comment block, one of:
  - `MIDI: replace` — incoming MIDI is dropped; only sequencer events
    pass through.
  - `MIDI: passthrough` — incoming MIDI is forwarded unchanged
    *alongside* sequencer events.
  - `MIDI: merge` — incoming MIDI is forwarded *and* may modulate the
    sequencer (e.g. transposition follows incoming notes).
  - `MIDI: filter` — the sequencer consumes specific message types
    (CC#, channel, note range) and forwards the rest.
- **Channel.** Output channel is a slider unless the unit is
  fundamentally polyphonic across channels.
- **Note-off discipline.** Every emitted note-on must have a matched
  note-off. On transport stop, on plugin reset, on slider edit that
  truncates an active note — emit all-notes-off cleanup. Stuck notes
  in REAPER are a pain to debug; engineer them out.

### Sliders

- **Prefix every slider label with `-`.** GUI-only window
  (see SPEC-005 *Sliders* for full rationale).
- **Bipolar where natural** — swing (`-1..1`, 0 = straight),
  transposition (`-12..12`), velocity bias, gate-length offset.
- **Slider budget.** 256 slots is plenty for shape parameters but
  *tight* for direct-encoded step data. A 32-step × 4-voice grid of
  per-step pitches alone is 128 sliders; add per-step velocity, gate,
  probability and you exhaust the budget. **Strategies** (pick one
  per unit, document in header):
  - **Generative:** sliders define *generators* (range, scale,
    distribution, density), no per-step storage. The sequence is
    re-derived per cycle. Best fit for the philosophy.
  - **Compact step storage:** pack pitch+gate+velocity into a single
    slider per step via integer encoding. Lose step-level automation
    granularity; gain compactness.
  - **Per-step automation lane:** dedicate sliders only to the
    *currently-edited* step; use `@serialize` for the full grid (with
    the 32-bit-float caveat — store integers). Editable but the grid
    is not framer-modulatable per step.

### Step storage (the exception to slider-completeness)

Bulk step data — long sequences, drum grids — may live in `@serialize`
*if and only if* it is editable only via the GUI, never modulated by
framers, and stored as integers (or 32-bit floats with explicit
quantization to integer at load). Anything a framer might want to
modulate must be a slider.

### Transport sync

- **Drive timing from `beat_position`,** not sample counters. Tempo
  changes and loop boundaries are handled correctly only via host
  position.
- **Loop-aware:** detect `play_position` discontinuities (looping,
  jumps) and either reset phase or quantize to the next bar — declare
  the choice in the header.
- **Pre-roll:** sequencers should cope with negative `play_position`
  during pre-count. Don't emit notes until `play_state & 1`.

### GUI

- Same conventions as SPEC-005: build on `geraintluff/jsfx-ui-lib` +
  `cuco_theme.jsfx-inc` + `cuco_widgets.jsfx-inc`. Use
  `ui_automate(slider, value)` for slider writes. Direct
  `sliderN = …` from `@gfx` forbidden.
- **Visualize sequence state.** A sequencer's GUI must show what's
  currently playing (current step, active notes, upcoming events) —
  the framer-modulation case otherwise leaves the user blind.

### Persistence

- All sliders auto-persist.
- `@serialize` for non-slider state (step grids, RNG seed if
  deterministic, GUI scroll position). 32-bit float precision —
  re-derive anything that needs full precision in `@init`.

## Forbidden

- Hidden sequence state that affects MIDI output without a slider
  (except the bulk step grid exception above).
- Free-running timing (sample counters, wall-clock) instead of host
  transport.
- Allocation in `@slider`.
- Direct `sliderN = …` writes from `@gfx`.
- Stuck notes — every note-on **must** be matched by a note-off under
  every termination path.
- Swallowing incoming MIDI silently. The MIDI stance must be declared.

## Currently in the suite

None. No JSFX MIDI sequencer exists in CUCO yet. This SPEC defines the
contract for future work. First reference implementation tracked under
a future T-NNN.

## Versioning

**v0.1** (draft). Promote to v1.0 once one reference sequencer is
built, framer-driven through Keyframer + Random Walk, and all stuck-note
/ transport-sync edge cases are validated.

## Open questions

- How does a sequencer's slider budget interact with REAPER's *Param*
  menu UX? 256 sliders, even hidden, may clutter the menu. Possibly
  group hidden parametric "step" sliders behind a single navigable
  collapse.
- MIDI stance: should `passthrough` be the default, or should
  sequencers default to `replace`? Prior art (Saike's StereoBouncer,
  Tale's MIDI step sequencer) varies.
- Should sequencers also accept incoming CC for slider modulation, or
  defer entirely to REAPER's "MIDI learn → automation" surface?
  Probably defer — the sliders *are* the automation surface.
- Header tag for opt-in declaration: `desc: CUCO ... [control-driven-sequencer]`
  vs comment block. Should match SPEC-005's eventual choice.
