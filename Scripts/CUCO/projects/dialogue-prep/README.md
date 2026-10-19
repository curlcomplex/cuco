# Dialogue Prep

One command that preps lav dialogue the way the Check This EP3/EP4 mix did (2026-10-19, IG F-015):

1. **RX 11 De-crackle** (High, strength 4) on each clip's source region with ±5 s handles.
2. **40 Hz 2-pole high-pass**.
3. The result becomes the clip's **active take** (`<source>_RX_<tag>-NN.wav` in `Media/Dialogue RX/`). The original stays underneath.
4. **Setting E clip gain**:
   - A cut-only take volume envelope that pulls down peaks and resonances with smooth bends and gentle sentence ramps.
   - An item gain boost that lands the speech median at −26.9 dBFS (400 ms).
   - Leave the lifting to the compressor.

```bash
python3 dialogue_prep.py --project EP4_MAIN --tracks 5,9 --tag EP4
```

`--project` is any part of the open tab's file path. REAPER must be running with that project open.

## Behaviour

- **Which clips:** active, unmuted audio clips on the listed tracks. A clip whose active take is already an `_RX_` take is skipped, so reruns only process new clips.
- **Fragments under 0.5 s** are too short to measure. They get the item gain of the nearest clip on the same track and no line.
- **Stops before touching the project if:**
  - a render doesn't line up with its source (cross-correlation lag ≠ 0)
  - a clip moved between steps
  - an output file already exists
  - De-crackle didn't take its settings
- **Saves:** the project is saved after the takes are added and again after the gain is applied. Each is its own undo point.
- **Time:** about 1.6× realtime for the De-crackle render. 15 clips (110 s) took 5 minutes.

Options (defaults are setting E as approved): `--strength 0.4 --ceiling 50 --decrackle 4 --quality high --hpf 40 --handle 5 --rx-dir <dir>`.

## How it works

`dialogue_prep.py` drives six REAPER steps (`steps/dp_*.lua`) through `REAPER -nonewinst`. Each step reads the job from `~/.cuco/dialogue-prep/current.txt` and writes `<job>/<step>.status` (`DONE …` or `ABORT …`). Lua errors become an ABORT status, not a modal dialog.

| Step | What |
|---|---|
| `dump` | list clips → `clips.tsv` |
| `rx_build` | scratch tab, one track per clip region (same channel mode), De-crackle on each take |
| `rx_params` | set De-crackle parameters during one muted playback |
| `rx_render` | action 40361 (apply take FX, mono), list renders, discard the scratch tab |
| (python) | lag check + ffmpeg HPF into the final files |
| `add_takes` | final files as active takes, project saved |
| (python) | plan setting E (`modules/setting_e.py`) |
| `apply_gain` | item gain + take volume envelope, project saved |

Intermediate renders and plans stay in the job folder under `~/.cuco/dialogue-prep/`.

## Gotchas

- **De-crackle ignores parameter changes unless it's processing.** `TakeFX_SetParamNormalized` returns true, but the value doesn't stick on an idle instance. `rx_params` sets them 0.5 s into a muted playback, then reads back the formatted values.
- **De-crackle parameters:** Quality is param 0 (normalised 0 / ⅓ / 1 = Low / Medium / High). Strength is param 1, range 1–10, normalised `(s − 1) / 9`.
- **New project tabs load the user template.** The scratch tab is replaced at once by a blank project (`noprompt:`), and it's discarded the same way, so no save dialog appears.
- **The planner reads the cleaned take's audio.** Its offset is the handle, so it plans on what you'll actually hear.

## Tests

`python3 tests/test_dialogue_prep.py` runs the planner and fragment-rule self-checks (needs ffmpeg + numpy).

End-to-end check: a stripped copy of the EP3 session reproduced the hand-run result exactly. All 15 clips had the same item gains and envelope points, and the cleaned audio was bit-identical.
