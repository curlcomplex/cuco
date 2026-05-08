# T-017 — Migrate to CUCO-reaper monorepo

## Status

Migration designed, not started. JSFX work landed at `~/Library/Application Support/REAPER/Effects/CUCO_plugins/` outside any git repo this session; needs to come into a unified dev-folder repo alongside the existing Lua scripts. Project repo at `main 96fa38e`.

## Read first

1. **`T-017`** (`node tools/ig/cuco_scripts_ig.cjs T-017`) — full migration sequence in the description; read it first before doing anything.
2. **`~/Library/Application Support/REAPER/Effects/CUCO_plugins/docs/jsfx-capabilities.md`** — JSFX gotchas this session learned (EEL2 has no `<<`; `ui_setup() ≠ ui_start()`; `-`-prefix sliders; widget memory must live above `m[~2940]`). Stays valid after the move; will land in `.planning/research/` per migration step 6.
3. **`~/Library/Application Support/REAPER/Effects/CUCO_plugins/docs/boom-recenter-reference.md`** — BOOM ReCenter spec, reference for `CUCO ReCenter v5`.
4. **`~/Library/Application Support/REAPER/Effects/CUCO_plugins/docs/gui-research.md`** — GUI library landscape; the `Tukan/ui-lib.jsfx-inc` is `geraintluff/jsfx-ui-lib`.
5. **`/CLAUDE.md`** — operational rules. Specifically the "log multi-step plans IMMEDIATELY upon agreement" rule and "discuss before writing code" rule.

## Done this session

- Built `lib/cuco_theme.jsfx-inc` + `lib/cuco_widgets.jsfx-inc` (knob, hbar, checkbox, stereo-monitor; retina-correct).
- Built `CUCO Sweep` — 6-stage all-pass phaser, 5 sliders, GUI verified.
- Built `CUCO ReCenter v5` — merge of existing `CUCO ReCenter` (Stage 4.0 Simple) + `CUCO ReCenter Spec` (Stage 4.3) targeting BOOM ReCenter parity. 10 visible sliders + 2 hidden monitor toggles. GUI verified at default 700×360. **DSP not audio-tested.**
- Wrote 4 docs at `Effects/CUCO_plugins/docs/`: `gui-research.md`, `jsfx-capabilities.md`, `boom-recenter-reference.md`, `handover.md` (placeholder; canonical handover is this file).
- Convention: every slider gets `-` prefix → REAPER's auto-strip stays empty → `@gfx` is the only UI.
- No commits — JSFX work entirely outside any repo. Project repo `/Scripts/CUCO/` at `main 96fa38e`, untouched except for this handover.

## In progress

- **Migration not started.** All work is described in `T-017`'s description; no files mid-edit.
- **`/Scripts/CUCO/` has pre-existing uncommitted Lua mods** (Keyframe, Audiosuite+, Random Walk GUI, plus untracked dirs `CUCO Archival/`, `CUCO Import Session Track/`, `archive/random-walk-old/`, `projects/_shared/`). None from this session, all yours from before. **User decision at session end: these need to be committed before the migration** so the move is a clean tree-shape change. That's the very first action of next session.
- **`CUCO ReCenter v5` audio-untested.** GUI confirmed. The full 10-step audio-test plan is documented in the JSFX docs; testing it is *not* part of T-017 — that's a separate task to register after migration completes.

## Turn-1 action

After protocols (CLAUDE.md Session Workflow, IG snapshot from session-start hook):

**Step 1 first: commit the pending Lua-side mods.** `git status` shows pre-existing modifications (Keyframe, Audiosuite+, Random Walk GUI) plus untracked dirs (`CUCO Archival/`, `CUCO Import Session Track/`, `archive/random-walk-old/`, `projects/_shared/`). User explicitly directed: commit these before the migration so the move is a clean tree-shape change. Group into logical commits if appropriate (per-project), confirm messages with user.

**Then discuss the migration plan with the user. Get explicit agreement. Then execute T-017's sequence (steps 2–9 in its description).**

Specifics worth verifying:
- Step 2: confirm `~/Work/Development/CUCO-reaper/` does not already exist (if it does, target name needs to change or directory cleared with user agreement).
- Step 5: imports must use `CUCO/lib/...` (no underscore). Easy to grep-verify post-edit.
- Step 8: load `CUCO ReCenter v5` from new location — if it shows `Error: #` or doesn't render, imports didn't resolve.

## Caveats

- **Process violation from this session**: per CLAUDE.md "log multi-step plans IMMEDIATELY upon agreement", the BOOM-merger plan and migration plan should have been logged when agreed. They weren't. This handover + `T-017` is the retroactive fix for the migration; the JSFX-suite scope (audio test, future plugins, ReaPack metadata) still needs IG nodes — register those next session as work surfaces, not all at once.
- **`CUCO ReCenter v5` filename is provisional.** After audio validation (separate task), decide: replace `CUCO ReCenter` (archive Simple + Spec) or keep as parallel canonical version.
- **Imports break on rename.** `CUCO_plugins/lib/...` → `CUCO/lib/...` in 2 JSFX files. Easy to forget.
- **`Tukan/ui-lib.jsfx-inc` is environmental, not vendored.** Imported from REAPER's `Effects/Tukan/`. ReaPack distribution will need to bundle or declare external dep — out of scope for T-017.
- **`CUCO_MEM_BASE = 1048576`** in both plugins — `@sample` state parked above ui-lib's reservation. Don't reduce.
- **My session damage was reverted**: I created `M-004` in the IG (wrong scope) and patched the CLI's `s327→s1` fallback (also wrong, that's CURLOP-derived but not for me to change here). Both `git checkout`'d back. The IG (M-001 Random Walk, M-002 Audiosuite+, M-003 project-management migration, plus children) is real project content and was untouched.
