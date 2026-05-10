# T-043 — Verify ReaPack import in fresh REAPER (T-021 steps 6-7)

**Date:** 2026-05-10
**Predecessor:** T-021 (closed when this verification passes)
**Closes on success:** M-001 (Random Walk v1.0 distribution-ready), M-004 (Keyframer v1.0 distribution-ready)

## Context

T-021 (steps 1-5) is **complete**:

- `index.xml` generated with 2 `<reapack>` entries — Keyframer 0.7.0, Random Walk 4.0.0
- Committed: `803d9de feat(reapack): T-021 generate index.xml — publish Keyframer 0.7.0 + Random Walk 4.0.0`
- Pushed to `origin/main`
- Repo `curlcomplex/cuco` flipped from private → **public**
- Raw URL verified live: `curl -sI https://raw.githubusercontent.com/curlcomplex/cuco/main/index.xml` → HTTP 200

Steps 6-7 require a fresh REAPER session and a human at the keyboard.

## ReaPack import URL

```
https://raw.githubusercontent.com/curlcomplex/cuco/main/index.xml
```

CDN caches this for 5 minutes (`cache-control: max-age=300`). If you re-push `index.xml` and don't see the change in ReaPack, wait 5 minutes.

## Verification checklist

### Step 6 — import the repo

1. Open REAPER.
2. Extensions → ReaPack → Manage repositories.
3. Import/export → Import repositories…
4. Paste the URL above. Click OK.
5. Browse packages (`Ctrl+B` / `Cmd+B`).
6. **Expect:** 2 packages appear, both under category `Scripts/CUCO/projects/keyframe` and `Scripts/CUCO/projects/random-walk` respectively. (Note: the category is the file's directory path, not a hand-set "CUCO" — that's how `reapack-index` works by default. T-021's original "category 'CUCO'" wording was inaccurate.)

### Step 7 — install + exercise

For **each** of `CUCO Keyframer.lua` and `CUCO Random Walk.lua`:

1. Right-click → Install. Confirm.
2. Apply changes.
3. Verify the post-install layout in `~/Library/Application Support/REAPER/Scripts/`:
   - **Keyframer:** `CUCO/projects/keyframe/CUCO Keyframer.lua` AND `CUCO/projects/_shared/cuco_imgui_theme.lua`
   - **Random Walk:** `CUCO/projects/random-walk/CUCO Random Walk.lua` AND `CUCO/projects/random-walk/cuco_imgui_theme.lua` (renamed alongside via `@provides ... > cuco_imgui_theme.lua`)
4. Open REAPER's action list (`?`), search "CUCO". Both scripts should be listed.
5. Run each script.
6. **Expect for both:** GUI launches, no errors in the ReaScript console (View → ReaScript Console).
7. Specifically: confirm theme is applied (CUCO color palette, not default ImGui grey). If theme failed to load, the script either errors or renders ungainly — both signal `dofile` resolution broke.

### Why the asymmetric `@provides` matters

The two scripts use different bundling strategies and matching `dofile` resolvers (verified self-consistent during T-021):

- **Keyframer** — `@provides ../_shared/cuco_imgui_theme.lua` (no rename). Resolver: `dofile(dir .. "../_shared/cuco_imgui_theme.lua")`.
- **Random Walk** — `@provides ../_shared/cuco_imgui_theme.lua > cuco_imgui_theme.lua` (rename to alongside script). Resolver: tries same-dir first, falls back to `../_shared/` for dev-mode.

If only one of the two fails, the failure is bundling-strategy-specific, not generic ReaPack breakage.

## On success

Run these IG ops:

```bash
node tools/ig/cuco_scripts_ig.cjs update T-043 --status closed --note "Closed: verified ReaPack import in fresh REAPER. Both packages installed, GUIs launched, theme loaded."
node tools/ig/cuco_scripts_ig.cjs update T-021 --status closed --note "Closed via T-043 verification. Steps 1-5 done in s328; 6-7 verified in s<NNN>."
node tools/ig/cuco_scripts_ig.cjs update M-001 --status closed
node tools/ig/cuco_scripts_ig.cjs update M-004 --status closed
node tools/ig/cuco_scripts_ig.cjs update T-043 --props '{"handover_pending":false}'
```

Then commit (no code change — IG state only).

## On failure

Capture: which package, what error, screenshot if GUI-visible. File a B-NNN bug node, link `revealed_by → T-043`. Do NOT close T-021 or the milestones.

Common failures and where to look:

- **`dofile` error mentioning `cuco_imgui_theme`** — ReaPack didn't land the theme file at the expected path. Inspect actual on-disk layout vs. expected in Step 7 #3 above.
- **Script-not-found in action list** — ReaPack install reported success but file missing. Check the ReaPack log (Extensions → ReaPack → Browse logs).
- **`reaper.ImGui_*` errors** — ReaImGui extension not installed. That's a user-environment issue, not a CUCO bug; install ReaImGui via ReaPack's default repos.
