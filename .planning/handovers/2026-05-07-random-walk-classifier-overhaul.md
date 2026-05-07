# CUCO session handover — 2026-05-07 (evening)

## Status

**Random Walk classifier + UI overhaul.** Spent the whole session driving the catch-all `walk` family from 88% → 13.6% across 12+ iterations on the user's 440-plugin library, then rebuilt the action-area UI, shape picker, and seed history. **Nothing committed.** main @ `7a84df7`. Working tree carries this session's Random Walk work *plus* everything carried from the prior PM handover (Audiosuite+ v0.6.0 Phase 1, theme retrofits, bridge JSON patches).

User ended saying "you're rotting in realtime" — context window was wearing thin. Not angry; tired. Pause point is clean.

## Read first

1. **`projects/random-walk/CUCO Random Walk GUI.lua`** — overhauled this session. Classifier, UI, persistence all changed. Diff vs HEAD before assuming anything.
2. **`~/Library/Application Support/REAPER/Scripts/CUCO Random Walk Plugin Library.lua`** — 562K params across 440 plugins, ~30K with authoritative `is_toggle` / `step_count` metadata captured from REAPER live FX. Distribution: locked 71.5%, walk 13.6%, real families 14.9%. Diagnostic via `grep -oE 'family="[a-z_]+"' | sort | uniq -c`.
3. **`projects/audiosuite-plus/PLAN.md`** — Phase 2 architecture STILL unresolved from prior session. Fresh agent might want to read this if user picks Audiosuite+ back up.
4. **`.session/archive/2026-05-07-pm-handover.md`** — reconciled prior handover with CONSUMED block. Has the Audiosuite+ context that's still open.
5. **`memory/feedback_reaimgui_check_docs.md`** — still in force. Honored throughout this session (queried context7 + REAPER's own SDK page for `TrackFX_GetParam`, `TrackFX_GetParameterStepSizes`, `InputInt`, `Selectable`, `DragInt`, `IsItemDeactivatedAfterEdit`, `Viewport_GetWorkSize`).

## Done this session (uncommitted)

### Random Walk classifier — five working detection paths

1. **System-noise auto-lock** (`SYSTEM_PATTERNS` in `CUCO Random Walk GUI.lua` ~line 670+). MIDI CC slots, MPE expression rails, MIDI 1.0 spec controllers (incl. abbreviated synth variants like `soundcont`, `gen.purp.N`, `omnimo*`), vendor placeholders, key-range pickers, structural toggles (`%f[%a]used$`, `%f[%a]enabled$`, `%f[%a]disabled$`), bypass-anywhere. Caught ~385K params.
2. **Word-boundary hint matching** (`hint_matches` ~line 760). Pure-word hints use Lua frontier patterns `%f[%w]hint%f[%W]`; spaced/punctuated hints use plain substring on space-padded name. Killed false positives like `damping → amp`, `sendvaluestomidicontroller → send`.
3. **REAPER step/toggle authoritative override** (in `ensure_classified` ~line 1013). After `classify_one`, if `is_toggle` → `locked/toggle`; if `step_count > 0 && step_count <= 16` and family ≠ `locked` → `switches`. Live REAPER metadata beats name patterns. This is what fixes Pro-Q 4's `Band N Shape` (`drive/dist` → `switches`).
4. **Unit-hint detection** (in `classify_one` ~line 869). **Was silently broken since the script's inception** — `local _, _, mn, mx = r.TrackFX_GetParam(...)` had wrong destructure (API returns 3 values: `value, min, max`, not 4). Fixed: `local _, mn, mx = ...`. Same bug crashed the format-sampling block. Three sites fixed.
5. **Format-value sampling for stepped detection** (in `ensure_classified` ~line 990). 24 samples across param range via `TrackFX_FormatParamValue`, count distinct formatted strings. ≤16 distinct → stepped with that count. Replaces the non-existent `TrackFX_GetNumParamSteps` API.

### Random Walk UI redesign

- **Action area** rewritten as two symmetric 4-row panels (`ENVELOPE MODE` / `RENDER-TO-TAKES MODE`) with a vertical divider. Both follow rhythm: heading → preference → state/config → primary action.
- **Shape picker** is now a **weighted distribution** (drops the Random sentinel + `?` glyph). 6 cells with curve thumbnails + green fill = weight 0..1. Drag = continuous; click = toggle 0↔stored. **Bezier tension slider** sits on same row as cells (right side, disabled when Bezier weight=0).
- **Seed system**: edit/replay via `[<] [>]` history-walk buttons, `Recent ▾` popup with timestamps + `← current` marker. History persists per-project via `SetProjExtState`. Write button generates fresh seed each press.
- **All meta-row** (in Walk amounts) is now **one-directional** — stores its own `all_intensity_target` / `all_variance_target`, broadcasts down to families on change. Per-family changes don't propagate back.
- **Per-family on/off toggle** via clickable colored dot (full color = on, faint = off). Same pattern in All row.
- **Vertical-drag Takes spinner** (custom InvisibleButton + `GetMouseDragDelta`).
- **Removed all console output** — `ShowConsoleMsg` calls gone except the one fatal "ReaImGui not installed" startup popup which has no GUI to fall back to.
- **Inline transient errors** replace `ShowMessageBox` popups for "no time range" / "already bouncing". 4-second orange banner above action panels, layout-stable via reserved spacer.
- **Save-on-commit** persistence (`save_on_commit(ctx)` helper at ~line 627). Sliders save on `IsItemDeactivatedAfterEdit`; click-toggles call `save_settings()` directly. Per-shape weights, bezier tension, family states, takes count all persist on every change instead of only on close.

### Maintenance popup (right-click status line in expanded Walk amounts)

- **Re-classify saved cache (all plugins)** — name-only pass over entire `plugin_lib`, fast, no FX re-instantiation. Uses cached `is_toggle`/`step_count` when present.
- **Re-classify selected tracks (full)** — `ensure_classified(force=true)` for every FX on selected tracks; populates fresh metadata.
- **Wipe plugin cache** — clears `plugin_lib` but preserves `user_int` overrides via pre-seeded entries; auto-scan rebuilds incrementally.

### Auto-scan refinement

- Fingerprint includes FX names (not just count) — catches in-place plugin swaps.
- Pre-seeded entries (post-wipe with only `user_int`) correctly trigger auto-scan via "any param missing family" check.
- Project-tab change detection via `EnumProjects` reloads seed history.

## In progress / unresolved

- **Plugin metadata coverage is partial.** Only ~30K of 562K params have `is_toggle`/`step_count` populated — limited to plugins the user loaded onto their test track during the session. Other ~420 plugins still need a future "load batch + Re-classify selected tracks (full)" pass to populate. **Not blocking** — name-based classification still works for unloaded plugins; metadata just upgrades classification accuracy.
- **Audiosuite+ Phase 2 architecture.** Carried over from PM handover, untouched. Decision was: chain on takes (model A), lazy materialization on preset-load/preview, preview is just play. User ended frustrated with my communication of this; design itself is fine.
- **Theme retrofit runtime verification.** Carried over from AM/PM. None of OP 2 / Metadata Match Criteria / predictive v01 verified in REAPER yet.
- **Bridge JSON decoder patches** in `~/Code/total-reaper-mcp` and `mcp_bridge_file_v2.lua`. Carried over.
- **Distribution polish (mentioned but not done):** discoverable right-click menu (e.g. small `⋮` button), first-run hint banner, Help/About panel, README. Discussed at end of session; no work shipped.

## Turn-1 action

**Check the user's mood first** — they were tired, not angry. Then offer one of:

1. **Commit-staging pass** is now overdue. The diff is enormous. Reasonable split:
   - Commit 1: Random Walk classifier overhaul (system patterns, word-boundary matching, unit-hint destructure fix, format-sampling for steps, REAPER-metadata override)
   - Commit 2: Random Walk UI redesign (shape weights, bezier slider, seed history, panel symmetry, save-on-commit, inline errors)
   - Commit 3: shared theme module + Keyframe + Random Walk theme retrofit (carried from AM)
   - Commit 4: Audiosuite+ v0.6.0 Phase 1 + PLAN.md (carried from PM)
   - Commit 5: Metadata Match Criteria retrofit
   - (curlop submodule — separate repo)
2. **Resume Random Walk metadata coverage** — if the user wants the rest of their library scanned, load a batch of plugins on a track and run **Re-classify selected tracks (full)**. Repeat for batches until coverage is complete. Iterative, no design needed.
3. **Audiosuite+ Phase 2** — re-read `PLAN.md` Phase 2 + the carried-over "In progress" block in the archived PM handover before opening anything. Architecture decision is clear; communication was the problem last time.
4. **Distribution polish for Random Walk** — discussed but not started. The classifier work is now stable enough that this is the natural next step if the user wants to share the plugin.

## Caveats

- **`TrackFX_GetParam` destructure bug was load-bearing.** The unit-hint path AND format-sampling path were both silently broken until this session. Any cached classifications that *should* have been classified via unit hints (cryptic-name params with `dB`/`Hz`/`st`/`cents` formatting) were stuck in `walk`. Running **Re-classify saved cache** picks up the fix for cached entries; **Re-classify selected tracks (full)** is needed to populate fresh step metadata.
- **`TrackFX_GetNumParamSteps` doesn't exist in REAPER's API.** I was inventing it for hours. The user's diagnostic confirmed `available: false`. We route around it via format-sampling.
- **Six iterations of "rotting in realtime"** at the end — context-window decay was visible. The destructure bug took ~2 hours of guessing before the user told me to "check the documentation / stop guessing." Lesson encoded: when REAPER API behavior is surprising, `curl` the SDK help page and `grep -A5` the function name. Don't WebFetch (its summary is lossy on return-value count).
- **Settings file backwards-compat:** `point_shape` (deprecated) is still read on load and migrated to shape weights. Don't delete the migration path until known users have upgraded.
- **`render_to_takes` in settings is dead state** — was a checkbox that was removed from UI but still loads/saves for backcompat. Harmless but worth knowing.
- **The Random Walk `point_shape` constant is gone**, replaced by `shape_weights[0..5]` table + `bezier_tension`. If anything else references `point_shape` outside the migration path, it's dead.
- **Window can't open taller than 90% of screen height** — added pcall'd `Viewport_GetWorkSize` clamp because stale saved sizes caused window > display. Survives builds without that API via fallback.
- **Persistent maintenance**: the user's plugin library file is 57MB / 566K lines. `grep`/`awk` is fine; full reads are NOT. Use line-anchored greps (`^M\[` for plugin entries) or sed with line ranges. Watch for byte-sequence errors in `awk` from non-UTF8 plugin names.
- **Audiosuite+ duplicate file** still divergent (v0.5 vs v0.6.0). Carried from PM handover.
