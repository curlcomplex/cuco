# AudioSuite+ — Design Plan (First Pass, Non-Binding)

> **STATUS: FIRST_PASS_DRAFT.** Captured from a brainstorming session on 2026-05-07.
> Not binding. Decisions, phasing, and APIs may all shift once Phase 1 reveals the
> real blockers. Use this as a thinking aid, not a contract.

---

## TLDR_VISION

A take-FX-based per-clip processor that fills the role of Pro Tools AudioSuite in
REAPER, with extensions REAPER's flexibility makes possible. Per-clip, with
user-controlled handle length (including whole-file mode), preview, smart
retention of pre-existing take FX, render-or-keep-as-FX choice, and project-level
chain presets organized into named lists.

---

## CORE_PROBLEMS

1. **Per-item write** — separate, isolated render per selected item.
2. **Handle length control** — render beyond the visible item edges, up to full
   source length, with pre/post handle sliders. Whole-file mode for audio only.
3. **Per-clip preview** — audition the configured chain on the selection without
   touching transport or solo state.
4. **Apply-as-new-take while preserving handles** — the load-bearing trick:
   expand item to source length (with ripple + trim-behind temporarily off),
   render, trim back. New take has source audio extending beyond visible edges.
5. **Render vs keep-as-FX** — let the user bake to audio or just leave the
   configured chain live on the take.

---

## LOCKED_DECISIONS

### preview_engine
SWS `CF_CreatePreviewFromMediaItem` + `CF_Preview_Play` / `CF_Preview_Stop`.
Cleaner than transport/solo manipulation. Includes take FX. Concurrent-safe.

### duplicate_mode
Kept, reframed as "recursive destructive processing." Render bakes the FX in
AND retains it live → next render layers on top. Useful for stacking saturation
or other progressive effects.

### tail_handling
**Updated 2026-05-07:** REAPER's render action adds a tail of length
`RENDER_TAILMS` project-info value (in ms) automatically. This means the engine
already gives us free tail capture per render. AudioSuite+ tail slider writes
`GetSetProjectInfo(0, "RENDER_TAILMS", value, true)` before each render and
restores after. Combined with post-handle slider, covers most reverb/delay
cases without audio analysis. Phase 6 (auto-trim silence) likely unneeded;
re-evaluate after Phase 5.

### chain_presets_structure
Two-level: `list_name → preset_name → {fx_chain_state}`. Lists are user-defined
buckets like "Sound Design," "Dialog Editing," "Music Editing." Richer than PT.

### scope
One floating AudioSuite+ panel per project. Always operates on current selection.

### new_take_metadata
- Take name: `<original_name> [<preset_name>]`
- Item notes: stamped with preset name + chain summary (for searchability)

### undo_granularity
One undo block per item, batch-wrapped at the action level. Single undo for a
multi-item batch with descriptive string mentioning item + FX counts.

### post_render_active_take
New take active by default. Future option: preserve original active for A/B.

### handle_units
- Audio: seconds, with whole-file mode toggle.
- MIDI: beats only, no whole-file mode.

---

## OPEN_QUESTIONS

1. **Undo granularity per-FX:** user mentioned "combined per FX plugin
   potentially, not sure 100% what I mean by that." Possible interpretations:
   - Each plugin in the chain becomes its own undo step within an item (requires
     N renders per item, slow but possible)
   - Each FX plugin contributes its own labeled sub-block to a combined undo
   - Some other model
   Defaulting to "one undo per item, batch-wrapped" until clarified.

2. **Variations mode mechanics:** most plugins are deterministic, so N passes of
   the same chain produce N identical outputs. Strategies under consideration:
   - Random Walk classifier integration: jitter "good to jitter" params per pass
   - User-controlled "variation strength" slider feeding param scramble
   - Trust stochastic plugins (granular, randomized delay, etc.) to vary naturally
   Likely will need a hybrid; pick at Phase 5 design time.

3. **Preview modes:** SWS `CF_Preview` plays the source with take FX, no track
   FX context. Should we ALSO offer a "mix preview" (Schappler-style) that
   includes track FX? Not blocking; can add later.

4. **Existing-take-FX state capture mechanism:** plan assumes
   `TakeFX_GetNamedConfigParm("chunk")` returns full plugin state restorable via
   `SetNamedConfigParm`. Some plugin types may need different chunk keys
   (`vst_chunk`, `vst3_chunk`). Verify at Phase 3.

---

## BUILD_PHASES

### PHASE_1_core_render_with_handles
Foundation. Everything depends on this. The handle trick is the load-bearing
architectural commitment.

**Tasks:**
- Per-item iteration loop with selection save/restore
- Project state save/restore for ripple modes (40310/40311/40312) and
  trim-content-behind (41117)
- Pre/post handle sliders, audio whole-file mode, MIDI beats-only mode
- Expand → render → trim flow with correct `D_STARTOFFS` math
- Item type detection (audio vs MIDI) for branching

**Verification target (UNVERIFIED_BLOCKER):** does
"Item: Apply track/take FX to items as new take" actually print the expanded
region when the item is widened beforehand? If yes, architecture works as
designed. If no, we need a different render path (offline render, CF_Preview
capture, or per-item bounce).

**APIs:**
- `GetMediaItemInfo_Value` / `SetMediaItemInfo_Value` — D_POSITION, D_LENGTH
- `GetMediaItemTakeInfo_Value` / `SetMediaItemTakeInfo_Value` — D_STARTOFFS
- `GetMediaItemTake_Source` + `GetMediaSourceLength`
- `TakeIsMIDI` — branching
- `GetToggleCommandState` + `Main_OnCommand` — ripple, trim-behind
- `Main_OnCommand` — render action (verify exact ID at impl time)
- `Undo_BeginBlock` / `Undo_EndBlock` — combined undo

---

### PHASE_2_staging_chain_and_presets
AudioSuite+ owns its own FX chain, decoupled from any track or take. Presets
organized into user-named lists.

**Tasks:**
- Internal staging chain data structure + persistence
- Plugin add/remove/reorder UI
- Plugin state capture/restore via FX chunk APIs
- Preset list management (create list, save preset to list, load preset, rename,
  delete)
- Apply-to-selection: bake mode (default) vs keep-live mode

**APIs:**
- `TakeFX_AddByName`, `TakeFX_Delete`, `TakeFX_GetCount`
- `TakeFX_GetNamedConfigParm("chunk")` / `SetNamedConfigParm` for state
- `TakeFX_Show` for floating editor
- `TakeFX_GetPresetIndex` / `SetPreset` / `NavigatePresets` for native presets
- `GetItemStateChunk` / `SetItemStateChunk` as fallback for full chain state

**Persistence:**
- Preset storage: own file in REAPER Scripts/ (similar pattern to Random Walk)
- Format: Lua-readable, two-level dict

---

### PHASE_3_smart_existing_fx_retention
Per-FX bake/preserve/duplicate modes for the source take's pre-existing chain.

**Tasks:**
- UI: list of source take's existing FX, per-FX mode dropdown, global default
- State save/restore for `TakeFX_GetEnabled` per FX before/after render
- Post-render copy of preserve+duplicate FX onto new take with full state
- Take name stamping + item notes metadata

**APIs:**
- `TakeFX_GetEnabled` / `SetEnabled` — toggle per FX during render
- `TakeFX_GetOffline` / `SetOffline` — for heavy CPU plugins, optional
- `TakeFX_CopyToTake` — copy FX between takes
- `GetSetMediaItemTakeInfo_String` — set take name
- `GetSetMediaItemInfo_String` — set item notes (P_NOTES)

---

### PHASE_4_preview
CF_Preview-based audition, integrated as a state machine in the main loop.

**Tasks:**
- State machine: idle → previewing → stopping → idle
- Preview button → CF_CreatePreviewFromMediaItem with current chain temporarily
  applied to take, CF_Preview_Play
- Stop button or auto-stop at item end
- Cleanup on stop: remove temp chain if not committed

**APIs (SWS):**
- `CF_CreatePreviewFromMediaItem` — preview source with take FX
- `CF_Preview_Play` / `CF_Preview_Stop`
- (verify exact API signatures at Phase 4)

**Dependency:** SWS extension. Acceptable — near-universal install.

---

### PHASE_5_variations_and_lanes
N-pass render with per-pass parameter perturbation. Fixed-take-lanes support.

**Tasks:**
- N-variations slider in render config
- Per-pass parameter jitter strategy (Random Walk integration TBD at design time)
- Variation strength slider
- Fixed-lanes project setting save/disable/restore (or auto-respect existing)

**APIs:**
- `TakeFX_GetParam` / `SetParam` for jitter
- Random Walk classifier read (potential reuse of plugin library file)
- `GetSetProjectInfo` for fixed-lanes mode

---

### PHASE_6_auto_trim_optional
Render-with-extra + post-analyze + trim. Only if Phase 1 handles prove
insufficient for reverb/delay tails in practice.

**Tasks:**
- Configurable render endpoint (handle + tail buffer)
- Post-render audio scan via AudioAccessor, backward from end
- Threshold (default -60dBFS), min-tail, max-tail safeguards
- Auto-fadeout on trimmed boundary

**APIs:**
- `CreateTakeAudioAccessor` / `DestroyAudioAccessor`
- `GetAudioAccessorSamples` — read sample buffer
- `GetAudioAccessorEndTime` — accessor extent

**UNVERIFIED_BLOCKER:** confirm `GetAudioAccessorSamples` performance on long
buffers (~30s @ 48k stereo = ~3M samples). Should be sub-second in 4k chunks
but worth measuring.

---

## UNVERIFIED_BLOCKERS_SUMMARY

1. **Phase 1: RESOLVED 2026-05-07.** Action `40601`
   ("Item: Render items as new take") is the correct render action — prints
   take FX, does NOT include track FX. Audiosuite+ is a take-FX processor, so
   forcing track FX into the new take would be wrong. Test with `40361` showed
   the expand-render-trim mechanism works (architecture sound), but 40361 was
   the wrong action because it bakes track FX too. Production build uses 40601.
2. **Phase 3:** confirm `TakeFX_GetNamedConfigParm("chunk")` round-trips state
   reliably for VST2/VST3/AU/JSFX/CLAP. Likely yes, but plugin-type quirks may
   exist.
3. **Phase 4:** confirm `CF_CreatePreviewFromMediaItem` actually applies take FX
   in the preview output. Strong expectation yes (the API's documented purpose).
4. **Phase 6:** `GetAudioAccessorSamples` perf on long buffers.

Each is a sub-30-minute test. Run before architecture commits in respective phase.

---

## KNOWN_RELATED_INFRASTRUCTURE

- `projects/_shared/cuco_imgui_theme.lua` — shared theme module, already in use
- Random Walk plugin classifier at `~/Library/Application Support/REAPER/Scripts/CUCO Random Walk Plugin Library.lua` — potential variations-mode integration
- Schappler's `SPS Scripts/Items/Solo Play Selected Item(s).lua` — pattern reference for transport-state save/restore (not used directly; CF_Preview replaces it)

---

## CHANGELOG

- 2026-05-07: First draft from brainstorming session.
- 2026-05-07: Phase 1 blocker resolved. Initial test used `40361` to confirm
  expand-render-trim architecture works. Corrected action to `40601`
  ("Render items as new take") — 40361 also bakes track FX which is wrong for
  Audiosuite+. Tail handling reframed around `RENDER_TAILMS` project info —
  engine provides tail automatically; Phase 6 likely unnecessary.
- 2026-05-07: Phase 1 production build shipped (v0.6.0).
