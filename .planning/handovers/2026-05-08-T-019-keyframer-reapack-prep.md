# T-019 — Keyframer ReaPack prep (next: T-019 → T-020 → T-021 publish)

> ✅ **CONSUMED s327** — Both T-019 and T-020 closed this session. T-019 landed at `bf9e167`; T-020 landed at `163dba1` and includes a post-T-019 correction (rename-on-install via `@provides ... > cuco_imgui_theme.lua` + dual-path resolver — see "Caveats" → ReaPack rejected the original cross-package shared `@provides` at check time, forcing the pivot). T-021 (publish) remains open and unblocked. The "unnamed index" warning from `reapack-index --check` was deferred to T-021. Stop here unless picking up T-021 publish.

📋 Citation check skipped — `scripts/check-handover.sh` not installed in CUCO. Manual review for canonical citations applied.

## 🛑 PROTOCOLS FIRST (mandatory, leads opener)

Before Turn-1, run session-start protocols. **Opener = CONTEXT, not bypass.**

1. **CLAUDE.md Session Workflow 1–4** — read SessionStart hook output (active milestones, ready work, K-001..K-005). Run intent-verify on every "shipped/landed/closed" claim below by inspecting source/IG, not this opener.
2. **Canonical-source verify pass** — for every "deferred / pattern / out-of-scope" claim below, open the cited canonical doc and verify. Do not inherit forward-looking framing unchecked.
3. **Governing specs** — `.planning/specs/*.md` — every alignment claim cites spec-line per CLAUDE.md ABSOLUTE BAN 7.
4. **`ig <id>`** for **T-019**, **T-020**, **T-021**, **M-004**, **M-001** before touching any related code.
5. **REAPER/ReaImGui doc check** — for any `reaper.*` call you write or fix, query context7 `/cfillion/reaimgui` (ImGui) or `curl` REAPER's SDK help page first per CLAUDE.md Golden Rule. K-003 (ReaImGui divergence), K-005 (Begin/End contract) load-bearing.

## Status anchor

T-017 monorepo migration done at `8d279f6`; T-018 ReaPack scaffolding done at `1fc1909`; ReaPack plan (M-004 + T-019/T-020/T-021) logged at `cb86097`. Working tree clean at `37c3d93` on `main`. **22 commits ahead of origin/main, no push yet.**

## Mandatory reading (4 surfaces)

**Source:**
- `Scripts/CUCO/projects/keyframe/CUCO Keyframe.lua:1-25` — current ReaPack-style header (note `@version 0.6.0` mismatch with `local SCRIPT_VERSION = "0.7.0"` at L21)
- `Scripts/CUCO/projects/keyframe/CUCO Keyframe.lua:545-555` — current `dofile` resolution using `(.*/CUCO/)` regex (the line that breaks post-ReaPack-install; same pattern in Random Walk + Audiosuite+ + metadata-workflow)
- `Scripts/CUCO/projects/random-walk/CUCO Random Walk GUI.lua:1-15` — current header (missing `@provides` and `@license`)
- `Scripts/CUCO/projects/_shared/cuco_imgui_theme.lua` — the bundled module
- `.reapack-index.conf` — whitelist config; only Keyframe.lua + Random Walk GUI.lua match

**IG nodes (run `ig <id>`):**
- **T-019** Keyframer ReaPack prep — *the umbrella*. Immediate Turn-1.
- **T-020** Random Walk ReaPack prep — parallel sibling under M-001.
- **T-021** Generate index.xml, commit, push, verify ReaPack import — blocked by T-019 + T-020.
- **M-004** Keyframer v1.0 distribution-ready — new milestone (this session).
- **M-001** Random Walk v1.0 distribution-ready — existing milestone, picks up T-020 + T-021 piece.
- **K-003** ReaImGui diverges from upstream Dear ImGui — load-bearing for any ImGui edits.
- **K-005** ReaImGui Begin/End modern contract — load-bearing.

**Specs/research:**
- `.planning/research/jsfx-capabilities.md`, `.planning/research/gui-research.md`, `.planning/research/boom-recenter-reference.md` — moved here in T-017 migration; not directly load-bearing for T-019 but in scope for any JSFX follow-ups.

**Memory (`~/.claude/projects/.../memory/`):**
- `reference_reapack_index.md` — install path (`~/.gem/ruby/4.0.0/bin/reapack-index` via brew Ruby) + conf-file gotchas (lines need `--` prefix, quoted values, NO `#` comments). **Will save context if read first.**
- `reference_cuco_theme.md`, `feedback_reaimgui_check_docs.md` — pre-existing.

## Canonical sources

- **T-019 IG description** — authorizes the four sub-steps for Keyframer prep (version drift fix, `dofile` refactor, `@provides`, `@changelog`). All forward-looking work below cites this `[per T-019 desc]`.
- **T-020 IG description** — authorizes Random Walk prep (`dofile` refactor, `@provides`, `@license`).
- **T-021 IG description** — authorizes the publish step including the `git push origin main` confirmation point.
- **`.reapack-index.conf`** — authorizes the publication scope: only `keyframe/CUCO Keyframe.lua` and `random-walk/CUCO Random Walk GUI.lua` are exposed; everything else explicitly ignored.
- **CLAUDE.md** — operational rules (ABSOLUTE BANs, Obstacle = Stop and Ask, log multi-step plans IMMEDIATELY).

## Turn-1 action

After protocols above, **start T-019 (Keyframer prep)**. Concrete sub-steps in order [per T-019 desc]:

1. **Rename file** `Scripts/CUCO/projects/keyframe/CUCO Keyframe.lua` → `CUCO Keyframer.lua` via `git mv` (user confirmed in s327). Note: existing local action-list binding will break — re-add after. → **shipped at `bf9e167`**.
2. **Fix version drift**: header `@version 0.6.0` → match `local SCRIPT_VERSION`. **Decision needed before this step**: bump `SCRIPT_VERSION` from `0.7.0` to `1.0.0` if this is the publication-ready cut, OR keep `0.7.0`. Ask user. → **user chose stay at 0.7.0; shipped at `bf9e167`**.
3. **Refactor `dofile` resolution** — replace the `(.*/CUCO/)` regex anchor with a script-relative resolver:
   ```lua
   local theme = (function()
     local s = debug.getinfo(1, "S").source:sub(2)
     local dir = s:match("(.*[/\\])") or ""
     return dofile(dir .. "../_shared/cuco_imgui_theme.lua")
   end)()
   ```
   Survives ReaPack install where the package dir is NOT named `CUCO`. → **[SUPERSEDED s327] shipped initially at `bf9e167`, then revised at `163dba1` to dual-path (same-dir → `../_shared/` fallback) when rename-on-install was forced. See "Caveats" below.**
4. **Add `@provides`** header line: `@provides ../_shared/cuco_imgui_theme.lua` so ReaPack bundles the theme module. → **[SUPERSEDED s327] shipped at `bf9e167` initially; revised at `163dba1` to `@provides ../_shared/cuco_imgui_theme.lua > cuco_imgui_theme.lua` (rename-on-install). Plain form rejected by `reapack-index --check` because both Keyframer and Random Walk claim the same destination — ReaPack disallows cross-package shared `@provides`. Rename gives each package its own dest path.**
5. **Tighten `@changelog`** — add a 0.7.0 entry (envelope shape picker + shared theme) for `reapack-index` per-version changelog generation. → **shipped at `bf9e167` (added 0.7.0 + 0.6.0 entries)**.
6. **Verify load** — REAPER reload + run Keyframer once from the action list (path must be re-added due to rename); confirm GUI renders + theme applied. → **user-confirmed in s327 ("confirmed working" + "all good" after T-020 also landed)**.

After T-019 lands, T-020 mirrors the pattern for Random Walk (no rename, just `dofile` + `@provides` + `@license`). → **shipped at `163dba1`. Plus an unplanned rename: user requested `CUCO Random Walk GUI.lua` → `CUCO Random Walk.lua` (drop legacy "GUI" suffix); the stale "Chain Drunk Walk (GUI)" dialog title at line 23 was also fixed in the same commit.**

### Caveats from s327 (additive)

- **ReaPack cross-package shared-file rule discovered.** Two packages cannot both `@provides` the same destination path. Forced a pivot to the `source > destination` rename-on-install syntax for the shared theme module. Both Keyframer and Random Walk now bundle their own copy at install (single source of truth in repo at `_shared/`; renamed into each package's dir on install). Resolver became dual-path: same-dir for installed users, `../_shared/` fallback for dev mode.
- **"Unnamed index" warning still surfaces from `reapack-index --check`** despite `--name="CUCO - REAPER Scripts"` being present in `.reapack-index.conf`. Deferred to T-021 (publish step) — needs diagnosis before generating the published `index.xml`.

## Discipline rules (this work's failure modes)

1. **No subagents for implementation** (CLAUDE.md ABSOLUTE BAN 1) — write the Lua refactor yourself.
2. **No REAPER API guessing** (BAN 2) — `debug.getinfo(1,"S").source` is standard Lua, not REAPER, but if you touch any `reaper.*` call, query context7 `/cfillion/reaimgui` first.
3. **Verify before declaring fixed** (Debugging Rules §7) — both scripts must reload in REAPER and exercise the GUI. Static checks only ≠ verified.
4. **Discuss before writing code** (BAN 5) — confirm version-bump decision (0.7.0 vs 1.0.0) with user before editing.
5. **Obstacle = Stop and Ask** — if `@provides` doesn't bundle as expected (e.g. relative-path resolution differs from doc), stop and surface.

## Branch + recent commits

Branch: `main` (22 ahead of `origin/main`).

```
37c3d93 feat(ig): close T-001 — commit-staging pass done in Phase A of T-017
3939d70 fix(claude): repoint hook paths post-migration
c145a5e feat(ig): close T-018 — ReaPack scaffolding done
1fc1909 feat(reapack): add .reapack-index.conf — whitelist Keyframer + Random Walk
cb86097 feat(ig): log ReaPack publication plan (M-004 + T-018..T-021)
166ba52 docs(research): update post-migration path in jsfx-capabilities
330d511 chore(effects): bucket the 5 unclassified JSFX
2f33eea feat(ig): close T-017 — monorepo migration landed
8d279f6 chore: restructure as CUCO-reaper monorepo (Lua + JSFX)
```

(7 pre-migration per-project commits below `8d279f6`, see `git log`.)

## End-state

T-019 is "done" when:
- File renamed (`git mv`), tracked at new path.
- `@version` matches `SCRIPT_VERSION`; `@provides`, `@license`, `@changelog` correct.
- `dofile` resolves via script-relative anchor; verified loading from dev symlink path.
- `~/.gem/ruby/4.0.0/bin/reapack-index --check` reports 0 failures for Keyframer.
- IG: `T-019 → status closed --note <commit>`.

After both T-019 and T-020 close, T-021 publishes via `reapack-index` real run + `git push origin main` (currently 22+ commits ahead).

## REAPER verify steps (T-019)

- Reload action list (`Actions > Show action list`).
- Add `CUCO Keyframer.lua` from new path; remove old `CUCO Keyframe.lua` binding.
- Run; confirm theme applies (palette colors match Random Walk's), shape picker renders.
- Touch a parameter, write keyframe, recall — sanity-check the v0.7.0 envelope-shape picker still works post-refactor.

## Caveats

- **Symlink asymmetry**: `REAPER/Scripts/CUCO` → `repo/Scripts/CUCO/` (one level deeper than repo root). Anything in `.claude/`, `.planning/`, `tools/` at repo root is invisible from REAPER's path. This bit `.claude/settings.json` Stop hook this session (fixed at `3939d70`). If you add new hooks/commands referencing absolute paths, hardcode the `~/Work/Development/CUCO-reaper/.claude/...` form, NOT the REAPER path.
- **Suggested**: launch Claude Code from `~/Work/Development/CUCO-reaper` (repo root) next session, not from the REAPER symlink path. Removes the asymmetry for future config edits.
- **JSFX side untested**: `CUCO Sweep` and `CUCO ReCenter v5` load post-migration NOT yet REAPER-verified. Imports look correct (`grep` confirms no `CUCO_plugins` left). User has REAPER closed; first launch verifies.
- **5 JSFX in `Effects/Experimental/`** (Additive, Spear) and other categories — none are in scope for ReaPack publication right now (`.reapack-index.conf` ignores `Effects/`).

## Don't re-litigate

- **Catalog name = "CUCO - REAPER Scripts"**, **category = "CUCO"**, **theme strategy = bundle-per-script via `@provides`**, **tooling = `reapack-index` CLI** — all decided in s327. Don't re-prompt.
- **`scripts/` → `tools/` rename** was forced by APFS case-insensitivity, NOT a free choice. T-017 actually specified `tools/` originally; the live repo just hadn't aligned. Don't propose reverting.
- **JSFX bucketing** (Mixing/Metering/Modulation/Experimental) — settled per user direction in s327.
