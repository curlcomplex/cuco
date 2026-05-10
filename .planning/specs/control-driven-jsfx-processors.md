# SPEC-005 — Control-driven JSFX Processors

**Status:** open · draft · v0.1
**Type:** specification
**Scope:** audio-domain JSFX in the CUCO control-driven suite
**Companion:** `.planning/research/control-driven-jsfx-architecture.md` (K-006 — umbrella philosophy)

## Purpose

Define the contract a CUCO JSFX must satisfy to be classified as a
**control-driven processor**: an audio-in/audio-out (or audio-out
generator) unit whose entire musical surface is a slider-saturated,
automation-receptive transfer function. Designed to be *driven* by
upstream framers (Keyframer, Random Walk, envelope lanes, sequencers),
not played at directly.

## Opt-in criteria

A JSFX is a control-driven processor if and only if **all** of:

1. **Audio I/O.** Reads `spl0..N` and/or writes `spl0..N`. (MIDI-only
   units are sequencers — see SPEC-006.)
2. **Mono-purpose.** Does one thing. A "swiss-army modulator" with five
   modes is five processors, not one. Splitting reduces the slider
   surface per unit and keeps the transfer function legible.
3. **Slider-complete.** Every musical decision is a slider. No hidden
   internal state that affects sound output but isn't reachable from
   automation.
4. **Gestural.** The unit is intended to be *swept* — its parameters
   make musical sense under continuous, dense automation. Static
   utility (matching levels, decoding mid/side) belongs outside this
   class.

## Required conventions

### Sliders

- **Prefix every slider label with `-`.** REAPER collapses the
  auto-rendered parameter strip → GUI-only window. Sliders remain
  fully automatable, preset-saveable, *Param*-menu-visible, and
  envelope-pickable.
- **Bipolar where natural.** Tilt, warp, drive, balance, asymmetry —
  centre on `0` with `<-1, 1, step>` so a Brownian walk centred on 0
  is musically neutral. Reserve unipolar `<0, 1>` for parameters that
  genuinely have no negative direction (mix amount, density).
- **Curves matter.** Use the `<min, max, step>` step value
  thoughtfully; for log-perceptual parameters (frequency, time)
  consider `slider_next_chan` shaping or a curve argument when wrapped
  via `control_slider_x`.
- **Limit count.** JSFX has 256 slots; aim for under 32 user-facing
  sliders per unit. If you need more, the unit is doing too many things
  (see *Mono-purpose*).

### DSP discipline

- **Allocate in `@init`, never in `@slider`.** Tables, delay lines, FFT
  workspaces — built once. `@slider` rebuilding under fast automation
  starves the audio thread.
- **Smooth in `@sample`, target in `@slider`.** Pattern: `@slider`
  sets `target_x`; `@sample` runs `x += (target_x - x) * coef;`.
  Eliminates zipper noise under dense automation. The smoothing
  coefficient is itself a candidate slider — but default it to a
  musical value (~10ms time constant).
- **Pre-compute per-block** when results don't change sample-to-sample
  (LFO increments, filter coefficients).
- **No per-sample FFTs.** Prefer recursive filters, all-pass networks,
  delay lines, and table lookups. FFT processing belongs in a
  different unit class.

### GUI

- **Build on `geraintluff/jsfx-ui-lib`** + project-local
  `Effects/lib/cuco_theme.jsfx-inc` + `cuco_widgets.jsfx-inc`. Don't
  redefine theme primitives.
- **`ui_automate(slider, value)` for all GUI slider writes.** Posts an
  undo point and respects host automation. Direct `sliderN = value`
  from `@gfx` is **forbidden** — it desyncs from the host and breaks
  framer integration.
- **Retina:** `gfx_ext_retina = 1` in `@init`.
- **Free phosphor decay** for trails: accumulate into an offscreen
  buffer, multiply by ~0.95 each frame via `gfx_muladdrect`, blit back.

### Persistence

- **`@serialize` for non-slider state only.** All sliders auto-persist.
  Caveat: `@serialize` saves at **32-bit float precision** — never
  round-trip filter state or phase accumulators through it. Recompute
  in `@init`.

## Forbidden

- Hidden internal state that affects audio output without a slider.
- Allocation in `@slider`.
- Direct `sliderN = …` writes from `@gfx`.
- Per-sample FFT/IFFT.
- Loading external libraries beyond the lib/ folder, file I/O during
  the audio thread, blocking calls.
- Reading from `tk_lib` or duplicating ui-lib's primitives.

## Currently in the suite

| JSFX | Path | Status |
|---|---|---|
| CUCO Sweep | `Effects/Modulation/CUCO Sweep` | Probable conformer — needs audit before claiming SPEC-005-conformant |

(No other audio-domain JSFX in the repo currently target control-driven
status. Audit results land in T-NNN follow-ups.)

## Explicitly *not* in the suite

| JSFX | Why exempt |
|---|---|
| CUCO ReCenter (and variants) | Mixing utility — static-use M/S processor, not gestural. |
| CUCO Multiband Correlation Meter | Metering — no audio modification. |
| JM_ana_Correlation | Metering. |
| ABLevelMatching_Modified | Utility. |
| CUCO Additive | Experimental — uses file I/O + drag-drop, may eventually opt in but not yet conforming. |

## Versioning

This SPEC is **v0.1** (draft). Once a reference processor is built
against it and all conventions are validated under live framer driving,
promote to **v1.0**.

## Open questions

- How is opt-in declared in the JSFX header? Proposals: `desc: ...
  [control-driven-processor]` suffix; or a comment-block tag
  `// CUCO-CONFORMS: SPEC-005 v1.0`. Pick one before v1.0.
- Smoothing coefficient defaults: per-unit tuning, or a single suite
  constant? Per-unit is more flexible; suite-wide is more predictable
  under cross-unit automation.
- Channel handling: enforce `num_ch >= 2` stereo-only, or support mono?
  Probably defer to per-unit choice.
