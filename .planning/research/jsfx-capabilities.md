# JSFX — Capabilities Reference

What the JSFX language can and can't do, framed for building the CUCO
gestural-music plugin suite.

## The format

A JSFX is a **plain text file with no extension**. The filename is the
plugin name in REAPER. There's no manifest beyond the header comment block
and `slider:` declarations.

```jsfx
desc: CUCO Smear

slider1:0<0,1,0.001>Amount
slider2:0.5<0,1,0.001>Color

@init
  // allocate, build tables
@slider
  // recompute on parameter change
@block
  // per-block setup
@sample
  // per-sample DSP
@gfx 600 400
  // UI
@serialize
  // save/load non-slider state
```

## Code sections

| Section | Runs | Use for |
|---|---|---|
| `@init` | On load, samplerate change, transport play | Allocate `mem[]`, build wavetables, FFT setup, initialize state |
| `@slider` | Any slider or automation change | Recompute filter coefficients, smoother targets — must be cheap |
| `@block` | Every 128–2048 samples | Per-block smoothing, MIDI parsing, ramp setup |
| `@sample` | Every audio sample | The DSP — `spl0..spl63` are your I/O |
| `@serialize` | Save / load (project + presets) | Persist non-slider state. **32-bit precision only** |
| `@gfx [w] [h]` | ~30 fps when window open | UI. Runs on a different thread from audio |

The width/height after `@gfx` are *defaults* — the user can resize and
`gfx_w` / `gfx_h` will reflect the live size.

## Audio model

- **`spl0`, `spl1`, ... `spl63`** — read/write per-sample I/O for up to 64
  channels.
- **`srate`** — sample rate (Hz).
- **`num_ch`** — channel count for current pin config.
- **`samplesblock`** — current block size.
- **`tempo`**, **`play_state`**, **`play_position`**, **`beat_position`** —
  host transport.
- **`ts_num`**, **`ts_denom`** — time signature.

## Memory & data

- **Flat memory model** — `m[i]` indexes a single global array. You manage
  layout yourself: `buf_a = 0; buf_b = 65536; buf_c = 131072;`.
- **Stack via `__memtop()`** — total size scales automatically as needed.
- **`function name(args) local(x, y) ( ... )`** — first-class functions
  with locals. Variables outside `local()` are global.
- **`function name(args) instance(x, y) ( ... )`** — OO-ish: call as
  `obj.name()`, `x` and `y` are namespaced under the instance. Useful for
  filter / delay / oscillator objects.

## DSP toolkit

- **FFT/IFFT** — `fft(buf, size)`, `ifft(...)`, `fft_real`, real/complex
  variants. Size is power of 2, up to 32768.
- **MDCT** — `mdct`, `imdct`.
- **Convolution** — `convolve_c` for FFT-based.
- **Bit-reversal helpers** — `fft_permute`, `fft_ipermute`.
- **Math** — full set: `sin`, `cos`, `tan`, `atan2`, `exp`, `log`, `pow`,
  `sqrt`, `floor`, `ceil`, `abs`, `min`, `max`, `rand`.
- **String ops** — concatenation with `+`, `sprintf`, `strcmp`, `strlen`,
  `match`, `strcpy`, etc. Strings are stored in a separate string pool.
- **File I/O** — `file_open`, `file_read`, `file_close`, `file_avail`,
  `file_var`, `file_mem`. Used by `CUCO Additive` to load SPEAR data.
- **Drag-and-drop** — `gfx_getdropfile()` returns dropped filenames during
  `@gfx`.

## MIDI

- **`midirecv(offset, msg1, msg23)`** — pull a MIDI event from the queue
  (call repeatedly until empty).
- **`midisend(offset, msg1, msg23)`** — emit MIDI.
- **`midirecv_buf` / `midisend_buf`** — sysex-friendly variants.
- MIDI is processed in `@block` and `@sample` per current sample offset.

## Sliders — the automation surface

Each slider is automatable, envelope-able, and visible to ReaScript by
index. **This is the contract that makes JSFX ideal for CUCO Keyframe and
Random Walk**: every meaningful parameter must be a slider.

```
slider1:default<min, max, step>Label
slider2:default<min, max, step{val1=Name1, val2=Name2}>Enum Label
slider3:0<-12, 12, 0.01>Pitch (st)
```

- 256 slider slots available (`slider1` through `slider256`).
- Hidden sliders: prefix the label with `-` (still automatable).
- **Suite convention: prefix EVERY slider with `-`.** When all sliders are
  hidden, REAPER's auto-rendered parameter strip collapses to zero height
  and the FX window shows only the `@gfx` canvas. The sliders remain
  fully automatable, preset-saveable, visible in REAPER's *Param* menu,
  and selectable in the envelope picker — only the auto-strip is
  suppressed. This is how Tukan, Saike, Geraint, and every other serious
  JSFX-with-custom-UI plugin gets a clean, GUI-only window.
- Shape-only sliders (no actual stored value): use `slider_next_chan`.

## Graphics — `gfx_*`

JSFX ships an immediate-mode canvas. No built-in widget set; you draw
primitives and read `mouse_*` yourself, or use a library
(see `gui-research.md`).

### Primitives

- **Shapes**: `gfx_rect`, `gfx_rectto`, `gfx_circle`, `gfx_roundrect`,
  `gfx_arc`, `gfx_triangle` (also convex polygon).
- **Lines**: `gfx_line`, `gfx_lineto` (with optional antialias).
- **Pixels & effects**: `gfx_setpixel`, `gfx_getpixel`, `gfx_gradrect`
  (gradient fill), `gfx_muladdrect` (brightness/contrast — also useful for
  phosphor-decay buffers), `gfx_blurto`.
- **Text**: `gfx_drawstr` (with alignment flags), `gfx_drawnumber`,
  `gfx_printf`, `gfx_measurestr`, `gfx_setfont(idx, "Inter", 14)`,
  `gfx_drawchar`.
- **UI helpers**: `gfx_showmenu("a|b|>sub|c|<|d")` for popup menus,
  `gfx_setcursor`.

### Image buffers

- `gfx_dest = N` (0–127) selects an off-screen buffer to draw into; `-1`
  is the visible framebuffer.
- `gfx_setimgdim(N, w, h)` sizes a buffer.
- `gfx_loadimg(N, "file.png")` loads a PNG.
- `gfx_blit(src, scale, rotation)` and friends copy with transform.
- **Trick**: persistent oscilloscope/spectrum trails — accumulate into a
  buffer, multiply by `0.95` alpha each frame with `gfx_muladdrect`, blit
  back. Free phosphor decay.

### State variables

- **Color**: `gfx_r`, `gfx_g`, `gfx_b`, `gfx_a` (0..1). `gfx_a2` for image
  writes.
- **Blend**: `gfx_mode` (0 default, +1 additive, +2 ignore source alpha,
  +4 disable filtering).
- **Position**: `gfx_x`, `gfx_y` (current draw cursor).
- **Frame**: `gfx_w`, `gfx_h`, `gfx_clear` (packed RGB to clear to each
  frame), `gfx_dest`, `gfx_texth`.
- **HiDPI**: `gfx_ext_retina = 1` in `@init` to opt in.

### Input

- `mouse_x`, `mouse_y` — cursor in pixels.
- `mouse_cap` — bitfield: `1` left, `2` right, `4` Ctrl/Cmd, `8` Shift,
  `16` Alt, `32` Win/Ctrl, `64` middle.
- `mouse_wheel`, `mouse_hwheel` — clear after reading.
- `gfx_getchar([char, unicodechar])` — keyboard.

## What JSFX *can't* do

- No external libraries, no FFI, no shell-out.
- No threading; no blocking calls.
- No guaranteed `@gfx` frame rate — always tolerate variable timing.
- Audio thread and UI thread run concurrently; reads from one of values
  written by the other are not atomic. For shared state, accept the tear
  or guard via `@block`.
- `@serialize` saves at **32-bit float precision** — don't round-trip
  high-precision filter state through it; recompute in `@init` instead.
- No vector instructions, no SIMD intrinsics. The compiler is reasonably
  fast, but the language is scalar.
- No native dynamic allocation beyond the flat `m[]` array — all "data
  structures" are manual offsets.

## Practical guidelines for the CUCO suite

1. **Every musical parameter must be a slider.** Hidden internal state
   defeats Keyframe and Random Walk.
2. **Smooth in `@sample`**, not `@slider`. Pattern: `@slider` sets
   `target_x`, `@sample` does `x += (target_x - x) * coef;`. Eliminates
   zipper noise under fast envelopes.
3. **Allocate in `@init`, never in `@slider`.** Rebuilding tables on
   slider change starves the audio thread under fast automation.
4. **Bipolar ranges where they sound natural** (e.g. `-1..1` for "tilt"
   or "warp"). A Brownian walk centered on 0 is then neutral by default.
5. **Pre-compute per-block**, not per-sample, when results don't change
   sample-to-sample: filter coefficients, LFO increments, etc. Move that
   work into `@block`.
6. **Avoid per-sample FFTs.** Prefer recursive filters, all-pass networks,
   delay lines, and table lookups for the kind of swept textures the suite
   is targeting.
7. **Use `ui_automate(slider, value)`** (from ui-lib) when GUI controls
   write to sliders — it posts an undo point and respects host automation.
   Don't assign to `sliderN` directly from `@gfx`.

## References

- Reference: <https://www.reaper.fm/sdk/js/js.php>
- Graphics reference: <https://www.reaper.fm/sdk/js/gfx.php>
- Local example using file I/O + drag-drop: `Effects/Experimental/CUCO Additive`
