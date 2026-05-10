# Control-driven JSFX — Architecture

The CUCO JSFX suite (a subset of it — opt-in, not house style) follows a
recursive **control-driven** architecture. The musical intelligence lives
in upstream control data; each JSFX unit is a clean transfer function from
sliders → output.

## The three layers

```
┌────────────────────────────────────────────────────┐
│ FRAMERS                                            │  Generate control data.
│   Keyframer · Random Walk · REAPER envelope lanes  │  Write into sliders
│   Tidal Notation                                   │  (REAPER automation
└─────────────────┬──────────────────────────────────┘   surface).
                  │ slider values (automation)
                  ▼
┌────────────────────────────────────────────────────┐
│ SEQUENCERS                                         │  Take slider values
│   (control-driven JSFX MIDI/CC sources)            │  → emit MIDI/CC.
│                                                    │  Their OWN sliders
│   sequence shape = sliders                         │  are themselves
│   density · swing · scale · gate · range · etc.    │  framer-receptive.
└─────────────────┬──────────────────────────────────┘
                  │ MIDI events (sample-accurate)
                  ▼
┌────────────────────────────────────────────────────┐
│ PROCESSORS                                         │  Take slider values
│   (control-driven JSFX audio effects/generators)   │  + audio in
│                                                    │  → emit audio out.
│   transfer function = sliders                      │
└────────────────────────────────────────────────────┘
```

The structural invariant repeats at every layer: **simple, focused,
mono-purpose units with every meaningful parameter exposed as a smooth,
bipolar-where-natural, automation-receptive slider**. Only the I/O domain
changes.

## Why JSFX is the right format for this

- **Uniform automation surface.** Every slider on every JSFX unit is
  automatable from REAPER envelope lanes, recordable from external
  controllers, writable by Keyframer / Random Walk, visible in the
  *Param* menu, and selectable in the envelope picker. Zero plumbing.
- **Single FX chain.** Sequencers and processors live on the same FX
  chain on the same track. MIDI events flow downstream via REAPER's
  built-in routing — sample-accurate, no IPC.
- **Hidden-slider trick.** Prefix every slider label with `-` and
  REAPER's auto-rendered parameter strip collapses to zero height; the
  FX window shows only the `@gfx` canvas. Sliders remain fully
  automatable, preset-saveable, and envelope-pickable. The GUI is for
  setup; **performance is automation**.
- **`ui_automate(slider, value)`** writes a slider *and* posts an undo
  point — the correct integration for envelope-writing workflows.

## Opt-in, not mandatory

This pattern is **tagged**, not universal. CUCO JSFX outside the
control-driven suite — mixing utilities (`CUCO ReCenter`), metering
(`CUCO Multiband Correlation Meter`), analysis tools — are exempt. They
have their own contracts.

A JSFX opts in by:

1. Declaring intent in its `desc:` line: `desc: CUCO Sweep [control-driven]`
   (or in a header comment block — convention TBD).
2. Conforming to the appropriate domain SPEC:
   - Audio in / audio out → **SPEC-005** (processors).
   - MIDI/CC out → **SPEC-006** (sequencers).
3. Living under `Effects/Modulation/`, `Effects/Generators/`, or
   `Effects/Sequencers/` — not the utility/mixing/metering buckets.

## What is *not* claimed here

- Not a sound-design ethos. The pattern says nothing about *what*
  effects should sound like. CUCO Sweep, a phaser, and a distortion
  could all conform.
- Not a UI ethos. Within the constraints (`@gfx`-only window, `ui_automate`
  for slider writes), each unit is free in its visual direction.
- Not a DSP discipline. The pattern is about the *control surface*, not
  the audio algorithm.

## Cross-references

- `.planning/specs/control-driven-jsfx-processors.md` — processor contract (SPEC-005).
- `.planning/specs/control-driven-jsfx-sequencers.md` — sequencer contract (SPEC-006).
- `.planning/research/jsfx-capabilities.md` — what JSFX can do (lines 180-199 list practical guidelines this architecture builds on).
- `.planning/research/gui-research.md` — `geraintluff/jsfx-ui-lib` foundation + theme/widget plan.
