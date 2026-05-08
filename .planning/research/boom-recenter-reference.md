# BOOM ReCenter — Reference Spec

Notes from the official manual + product pages + third-party reviews,
captured here as the canonical reference for what CUCO ReCenter is trying
to be.

> **Source:** BOOM Library ReCenter Manual (PDF), product page, BOOM blog
> launch post, MusicRadar review, David Dumais Audio review.
> See "Sources" at end of file.

## What it is

A stereo centering processor. Continuously analyzes the **directionality**
of a stereo or M/S signal and dynamically **rotates** it toward a target
angle in real time — without narrowing the stereo width. Then offers
post-rotation Width and Output adjustment.

Marketing tagline: *"The instant stereo fix."*

Three adjustment dimensions exposed to the user:
- **Intensity** — *how hard* it corrects
- **Response** — *how fast* it corrects
- **Mono Filter / Multiband** — *how precisely* it corrects

## GUI layout

```
┌───────── boom logo ─────── RECENTER ──────────────────┐
│                                                       │
│  Intensity              [ Stereo Monitor ]   Response │
│   ( knob )              L            R       ( knob ) │
│   83 %                                       29 %     │
│                            (signal viz)               │
│  Mono Filter            IN ●            ● OUT  Look-  │
│   ( knob )                                    ahead   │
│   22.96 Hz                  C                ( knob ) │
│                                              4.84 ms  │
│                                                       │
│  Angle    ─────────────|─────────────       0.0       │
│  Width    ─────────|─────────────────       100 %     │
│                                                       │
│  ☐ MS Input    ☐ Multiband    Output  0.0 dB  ▮▮▮▮ │
└───────────────────────────────────────────────────────┘
```

- **Top-left quadrant** — Intensity knob, Mono Filter knob (column)
- **Top-right quadrant** — Response knob, Lookahead knob (column)
- **Center** — Stereo Monitor (semicircular scope, signal cloud inside an
  L/C/R fan). IN / OUT toggles overlaid in lower corners.
- **Below the monitor** — two horizontal sliders: Angle, Width.
- **Bottom strip** — MS Input + Multiband checkboxes, Output dB readout,
  output level meter (a thin horizontal bar at right).

## Parameters

### Stereo Monitor (display, not a control)
Radial scatter showing where the signal currently sits in the stereo
field. Fan goes from L (left edge) through C (center, bottom) to R (right
edge). Higher radial distance = more energy at that azimuth.

- **IN toggle** — show the unaltered input signal cloud.
- **OUT toggle (default)** — show the processed result.
  Lets you A/B before vs. after at a glance.

### Intensity (knob)
*"Specifies the amount of correction. At 100% the plug-in will work at
full capacity to center the stereo signal. Go above 100% to over-compensate
and force the correct alignment where necessary."*

- Range: **0–200%**
- Default: 100%
- 0% = bypass the auto-correction
- 100% = unity correction toward the target angle
- >100% = over-rotate (forces alignment harder than what the analyzer
  thinks is needed; useful when source is *very* off and analysis
  under-shoots)

### Response (knob)
*"Determines the speed at which the plug-in corrects the signal. Lower
values cause less artifacts, whereas higher values respond faster, as the
Stereo Monitor will also show."*

- Range: **0–100%**
- Default: ~29% (per stock screenshot)
- Lower = slower, smoother, fewer artifacts under transient material
- Higher = faster tracking, more artifacts on percussive sources
- The Stereo Monitor visibly tracks faster at higher Response values

### Mono Filter (knob)
*"If needed, the Mono Filter reduces all audio to mono below a certain
threshold, which can be adjusted with this control. Turning it all the
way down disables the filter."*

- Range: **20 Hz – 10 kHz** (per MusicRadar review)
- "All the way down" = OFF (no monoization)
- Above the threshold: stereo intact
- Below the threshold: forced to mono (centers low-end energy, prevents
  phase cancellation in lows)

Tips section adds: *"Using the Mono Filter helps to get punchier and more
defined low frequency responses."*

### Lookahead (knob)
*"Controls how far ahead the incoming signal is analyzed. Values above
0 ms introduce latency but usually yield more robust results."*

- Range: **0 ms – ?** (screenshots show up to ~5 ms; reviewers describe it
  as "trades latency off against accuracy")
- 0 = zero-latency, less accurate on transients
- >0 = the rotation can preempt direction changes that haven't reached
  the output yet, smoothing transitions

### Angle (horizontal slider)
*"Rotates the signal to an angle you specify. This is 0° by default
(center)."*

- Range: ~ **±90°** (slider visually centered with mid tick)
- Default: 0.0 (center)
- **This is the AIM POINT for the auto-correction.** The plugin doesn't
  just blindly center — it pulls the analyzed direction *toward Angle*.
  Setting Angle to +30° tells the plugin "I want this material to sit at
  +30°, regardless of where the source mic was pointing."
- (Reviews confirm: *"You can set the target angle manually if you're not
  aiming for the centre, or automate it for re-panning."*)

### Width (horizontal slider)
*"Expands or reduces the final stereo width."*

- **0%** = mono
- **100%** = original stereo width (default)
- **200%** = highly widened
- Range: **−200% to +200%** (MusicRadar: *"Width ranges from mono to '200%
  wide', and can be inverted to flip left and right."*)
- Negative values: invert the stereo image (swap L/R sides through M/S
  side-flip)

### MS Input (checkbox)
*"If you are working with a Mid-Side recording, activate this checkbox to
enable automatic MS decoding. The signal will be converted to LR before
[and] after processing."*

- Default: OFF
- ON = decode incoming M/S to L/R, process, then re-encode to M/S on
  output (so the plugin appears transparent to the M/S pipeline).

### Multiband (checkbox)
*"Toggles multiband processing. While slightly increasing the plug-in's
CPU load, it can yield better results, especially when the signal features
different directionality in different frequency ranges. Multiband mode
operates with four frequency bands:"*

- Band 1: **0 – 150 Hz**
- Band 2: **150 – 1,200 Hz**
- Band 3: **1,200 – 5,500 Hz**
- Band 4: **5,500 – 20,000 Hz**

Each band gets its own directionality analysis and its own rotation,
recombined at the output.

Default: OFF. Used when the source has different positional content per
frequency range (typical of complex field recordings).

### Output (numeric, bottom strip)
*"Adjusts the final output volume of your signal."*
- Range: dB trim, around the 0.0 dB default. Likely ±24 dB based on the
  reviewers' descriptions.

## Algorithm understanding

From the manual and external reviews — no source code published, this is
inferred:

1. **Analysis window** runs continuously, sized by Response.
2. **Directionality** (azimuth) computed from L²/R² energy and L·R
   correlation. This is the standard `0.5 * atan2(ER - EL, 2C)` formula —
   visible in CUCO ReCenter's code, and the math that produces a single
   azimuth angle per analysis window.
3. **Target angle** = Angle slider. Correction = `−Intensity × (azimuth − target)`.
4. **Smoothing** time constant scaled by Response (lower Response = longer
   tau; less artifact-y).
5. **Rotation matrix** applied per-sample (or per-band, in Multiband mode):
   `[L', R'] = [cos α · L − sin α · R, sin α · L + cos α · R]`.
6. **Lookahead delay** ahead of the rotation: analysis runs `look_ms` ahead
   of where the rotation is being applied, so direction-change attacks are
   already known when the rotation reaches them.
7. **Width** in M/S domain *after* rotation: `S *= width_factor` then back to L/R.
8. **Mono Filter** in M/S domain: low-frequency Side content set to zero
   (LP4 on Side, subtract). This is the phase-safe approach (manual:
   "without altering the stereo width" — but Mono Filter does narrow the
   lows, which is a separate, opt-in operation).
9. **Multiband**: chained crossovers at 150 / 1200 / 5500 Hz (LR4 typical).
   Per-band azimuth analysis, per-band rotation, sum.

## Tips & tricks (from manual)

### Perceived vs. technical center
*"The technical center (as seen in the Stereo Monitor) may sometimes
differ from the perceived center (what you hear). In that case, lower the
Stereo Width and use the Angle parameter to pinpoint and move the signal
to the perceived center. You can also try modifying Intensity to over-/
undercompensate for the detected source direction."*

→ Implication: when ear and analyzer disagree, **Angle is the override**.
Engineer puts the technical answer somewhere off-center on purpose to make
the *perceived* answer correct. Worth surfacing this in CUCO ReCenter UX.

### Headphones vs. speakers
*"Most applications require the signal to sound correct on both headphones
and speakers. If possible, cross-check the result frequently on both
systems, as factors like perceived center and stereo width usually vary
depending on your monitoring device."*

### Mono Filter
*"Using the Mono Filter helps to get punchier and more defined low
frequency responses."*

### Multiband
*"While Multiband mode utilizes more processing power, it is not always
the best choice. Use your ears and best judgement to determine which
option fits your input signal best."*

## Mapping to CUCO's existing implementations

| BOOM control | CUCO ReCenter (Simple) | CUCO ReCenter Spec |
|---|---|---|
| Intensity 0–200% | `Center 0–200%` ✓ same | `Intensity 0–200%` ✓ same |
| Response 0–100% | `Speed 0..1` (different scale, same idea) | `Response 0–100%` ✓ same |
| Mono Filter 20–10000 Hz | `Mono Bass Fc 0–200 Hz` ⚠ much narrower range | `Mono Filter 0–300 Hz` ⚠ still narrow vs spec |
| Lookahead | (not implemented) | `Lookahead 0–60 ms` ✓ |
| Angle (target / aim) | `Target Angle ±45°` ✓ semantically correct (aim point) | `Angle ±90°` ⚠ used as **manual base added to** auto, **not** as aim point |
| Width −200% to +200% | `Width 0–200%` ⚠ no inversion | `Width −200% to +200%` ✓ matches |
| MS Input | (not implemented) | `MS Input on/off` ✓ |
| Multiband on/off | `Mode Single/Multi(4)` ✓ same band split | `Multiband on/off` ✓ same band split |
| Output dB | `Output ±12 dB` ✓ | `Output ±24 dB` ✓ |
| IN/OUT monitor toggle | (single-meter view) | (single-meter view) |
| Freeze | `Freeze` ⚠ **not in BOOM** — extra | (not implemented) |

### Discrepancies worth fixing for "compatibility with BOOM"

1. **`Angle` semantics in Spec are wrong.** BOOM's Angle is the *target* the
   auto-correction pulls toward. Spec adds it as a manual rotation on top
   of the auto-correction. Simple gets this right ("Target Angle"). When
   merging, take Simple's interpretation.
2. **Mono Filter range is too narrow** in both versions. BOOM goes up to
   10 kHz. Simple caps at 200 Hz. Spec at 300 Hz. Open the range up.
3. **Width inversion (negative %)** missing in Simple. Add it.
4. **Lookahead** missing in Simple. The Spec implementation can be ported.
5. **MS Input** missing in Simple. Port from Spec.
6. **IN/OUT monitor toggle** missing in both. The user-facing "is this
   doing anything" affordance is important; the Stereo Monitor with IN/OUT
   A/B is one of BOOM's defining UX features.
7. **Stereo Monitor (semicircular signal cloud)** missing in both. Both
   CUCO versions show level + correlation bars instead. The radial-fan
   visualization is BOOM's signature; worth implementing.
8. **`Freeze`** is a CUCO extension, not in BOOM. Keep or drop — doesn't
   conflict, but it's not "ReCenter compatible."

### What to *keep* from CUCO that BOOM doesn't have

- **Spec's `biquad_tick_id` indexed-state pattern** — cleaner than hand
  inlining, reusable across the suite.
- **Spec's slew limiter and error-adaptive smoothing** — exactly the
  audio-rate guardrails that make envelope-driven sweeps work cleanly.
  BOOM probably has equivalents internally; CUCO making them explicit and
  exposed is a good thing.
- **Spec's PDC reporting** — proper `pdc_delay` for Lookahead is
  non-negotiable for production use.

## Sources

- [BOOM Library ReCenter Manual (PDF)](https://www.boomlibrary.com/manuals/00_ReCenter_Manual.pdf)
- [BOOM Library ReCenter product page](https://www.boomlibrary.com/sound-effects/recenter/)
- [BOOM Library blog — ReCenter release post](https://www.boomlibrary.com/blog/new-release-recenter/)
- [MusicRadar review](https://www.musicradar.com/reviews/boom-library-recenter)
- [David Dumais Audio review](https://www.daviddumaisaudio.com/review-recenter-by-boom-library/)
- [The Sound Board forum thread](https://thesoundboard.net/viewtopic.php?t=3426)
