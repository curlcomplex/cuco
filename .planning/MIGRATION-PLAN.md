# CUCO Project Management Migration Plan

**Goal**: Adopt CURLOP's project-management method, scaled to CUCO's reality (personal Lua/REAPER script collection, single developer, no build pipeline, no audio thread).

**Source of method**: `/Users/f.god/Work/Development/CURLOP/CLAUDE.md` + `.planning/` + `.claude/hooks/` + `.claude/commands/cuco/`.

**Principle**: copy the *load-bearing parts*, skip the parts that exist because CURLOP is a 280K-LOC C++/JUCE/Elementary product with multi-day cuts. CUCO is a script collection — same discipline, less ceremony.

---

## What CURLOP has, and what CUCO should take

| CURLOP system | What it is | CUCO verdict |
|---|---|---|
| `.planning/` directory | Canonical home for all process artifacts | **Adopt fully** |
| `.gsd/` symlink + GSD core docs | Vestigial — CURLOP's CLAUDE.md explicitly deprecates STATE/CAPTAINS-LOG/REFLECTIONS as "historical reference only"; IG replaced them | **Skip** |
| Versioned milestones (v5.0…v16.0) with REQUIREMENTS/ROADMAP/AUDIT | Shippable horizons — but these live as IG `milestone` nodes in CURLOP, not as GSD docs | **Adopt as IG milestone nodes**, not as filesystem docs |
| Numbered phases with RESEARCH + PLAN + SUMMARY per cut | Execution unit | **Adopt** — already used informally (`projects/audiosuite-plus/PLAN.md`) |
| Date-prefixed handovers in `.planning/handovers/` | Session bridge | **Adopt fully** — already use `.session/HANDOVER.md`, formalize to CURLOP convention |
| ADRs in `.planning/adrs/` | Architecture decision records | **Adopt** — small, durable, high-value |
| Specs in `.planning/specs/` | Canonical contracts (vs concept-docs in `research/`) | **Adopt** — already have de-facto spec material in `memory/` and CLAUDE.md fragments |
| `.issues.json` + `tools/ig/ig.cjs` (Issue Graph) | Structured node graph; replaces STATE/CAPTAINS-LOG | **Adopt fully** — port `ig.cjs` + schema, start with empty `.issues.json`, populate as work surfaces |
| `.upg` (Unified Product Graph) | Personas, journeys, strategy | **Skip** — CUCO is personal tooling, no users/journeys |
| Persona slash commands (Julian/Jim/Urs/Smith/Gilfoyle/Dieter/Sean/Gerhard) | Character-driven advisors | **Adopt small set** — REAPER/Lua expert, ImGui UX critic, Lua quality reviewer; defer until Phase 4 |
| Hooks: `session-start-context.cjs`, `manifesto.sh`, `fresh-handovers.cjs`, `handover-log-nudge.cjs`, `post-edit-verify-cpp.cjs` | Session discipline | **Adopt subset** — session-start context (lean), handover-log-nudge, optional luacheck post-edit |
| K-024 pathology taxonomy + `scripts/invariants/*.sh` | Mechanical audits, AI-codebase failure-mode index | **Skip mechanical audits**; **adopt the K-024 doc as reference** |
| `/cuco:handover-prompt`, `/cuco:release`, `/cuco:ig-help`, `/cuco:rules`, `/cuco:build`, etc. | Operational slash commands | **Adopt subset** — handover-prompt already exists; add rules, ig-help, fresh-eyes |
| Manifesto (`.claude/hooks/manifesto.sh`) | Scope guard printed at session start | **Adopt** — CUCO needs one too: each script does one thing, no monoliths |
| Build rules | C++ rebuild orchestration | **Skip** — N/A for Lua |

---

## Plan: 5 phases

Each phase is independently committable and yields value alone. Stop after any phase that's enough.

### Phase 1 — Bootstrap `.planning/` skeleton

**Goal**: There's a place for everything.

1. Create directory structure:
   ```
   .planning/
   ├── adrs/
   ├── handovers/
   ├── phases/
   ├── research/
   ├── specs/
   ├── parked/
   └── _archive/
   ```
   No GSD bootstrap. No PROJECT.md / STATE.md / KNOWLEDGE.md / DECISIONS.md / REQUIREMENTS.md / CODEBASE.md. Those are deprecated in CURLOP — IG replaced them. Project identity, knowledge, decisions, and current state all live as IG nodes (Phase 5).

2. Migrate existing material into the new tree:
   - `projects/audiosuite-plus/PLAN.md` → `.planning/phases/audiosuite-plus-phase-2/PLAN.md`
   - `.session/HANDOVER.md` → `.planning/handovers/2026-05-07-random-walk-classifier-overhaul.md`
   - `memory/*` stays put for now — content gets migrated to IG knowledge nodes + specs in Phase 5.

**Done when**: `.planning/` tree exists, the open phase plan and current handover are in canonical locations.

**Cost**: 30 minutes.

---

### Phase 2 — Operational spine: CUCO `CLAUDE.md`

**Goal**: A single auto-loaded operational rules file that future sessions read first. Modeled on CURLOP's CLAUDE.md (441 lines), but trimmed to CUCO's actual surface.

Sections to include (adapted, not copied):

1. **Handover system** — date-prefixed in `.planning/handovers/`, fresh-handover hook surfaces pending ones at session start, `/cuco:handover-prompt` writes them at session end. (CUCO's `/handover` already exists — align its output format to the convention.)
2. **ABSOLUTE BANs** — derived from real CUCO failures:
   - **NO subagents for implementation** (CURLOP rule, applies equally — past sessions have shown subagent-written Lua misses REAPER API quirks)
   - **NO API guessing** — query `/cfillion/reaimgui` via context7 + REAPER's SDK docs first (already in memory; promote to CLAUDE.md)
   - **NO destructure assumptions for REAPER API** — the `TrackFX_GetParam` bug. Always read the SDK page.
   - **NO full-read of plugin library file** (57MB) — use line-anchored greps
   - **DISCUSS before writing code** — same reason as CURLOP
3. **Golden Rule: Check ReaImGui + REAPER SDK docs FIRST** — direct adaptation of CURLOP's "Check JUCE first" rule.
4. **Project structure** — directory map + the `_shared/` theme module convention.
5. **Session workflow** — session-start hook output (IG snapshot), intent-verify pass (does prior handover's claim match working tree?), one-line brief before work, **log multi-step plans to IG immediately upon agreement** (CURLOP's rule 4 — verbatim adopt; the rule exists because conversation state doesn't survive `/clear`).
6. **Issue Graph section** — schema summary, session-start reads (`ig --type milestone --status open`, `ig --children M-NNN`, `ig --ready --next 5`, `ig --type knowledge`), write surface (single-op create/update/edge, `ig apply` for ≥3 writes, `--desc-file`/`--note-file` for rich content), Document Pairing Rule, hygiene cadence.
7. **Commit format** — conventional commits (already used).
8. **Personas** (forward reference; populated in Phase 4).
9. **Obstacle = Stop and Ask** — verbatim adopt.
10. **No Exceptions / Tool Failures / General Rules** — verbatim adopt.

**Done when**: Root `CLAUDE.md` exists, auto-loads, references all the right `.planning/` paths, replaces ad-hoc rules currently scattered in `memory/` and inline session reminders.

**Cost**: 1 session, ~2 hours of writing.

---

### Phase 3 — Hooks: lean session-start + handover discipline

**Goal**: Future sessions open with the right ~5KB of context auto-injected, and don't drift out of scope without flagging.

Three hooks, all in `.claude/hooks/`:

1. **`session-start-context.cjs`** (port of CURLOP's same-named hook, IG-aware):
   - Read `.issues.json` and emit structured queries (matches CURLOP exactly):
     - Active milestones (orientation)
     - Resume point (any node tagged `resume-here`)
     - Top-10 blockers for current milestone, with feature-parent context
     - Top-5 ready work (priority-sorted)
     - All knowledge nodes (load-bearing constraints)
   - Plus: newest handover from `.planning/handovers/` (one line)
   - Plus: git status one-liner (modified + untracked counts)
   - **Target output: ≤ 5-15KB** (CURLOP's actual budget). Structured queries, not doc dumps.
2. **`fresh-handovers.cjs`** — port from CURLOP. Reads IG nodes with `properties.handover_pending: true` + `handover_doc: <path>` and surfaces them at session start with "resume it?". After consuming, agent clears via `ig update <id> --props '{"handover_pending":false}'`. (CURLOP's `handover_pending` flag schema is the right model — adopt it.)
3. **`handover-log-nudge.sh`** (Stop hook) — watch the assistant's response for phrases like "out of scope" / "for another session" / "park for later" / "circling back" without an accompanying handover-log invocation, and block stop. Bypassable with env var. Direct port of CURLOP's `.cjs`.

Wire them in `.claude/settings.json` under `hooks.SessionStart` and `hooks.Stop`.

**Done when**: Session start auto-prints the structured snapshot, fresh handovers surface, scope-creep phrases are nudged.

**Cost**: 1 session, ~3 hours.

---

### Phase 4 — Slash commands: handover-prompt + rules + fresh-eyes

**Goal**: Reusable session operations as `/cuco:*` commands.

Migrate or create in `.claude/commands/cuco/`:

1. **`/cuco:rules`** — print the CLAUDE.md operational rules summary (one-screen).
2. **`/cuco:handover-prompt`** — generate end-of-session handover doc to `.planning/handovers/<DATE>-<NODE-ID>-<slug>.md`, **and** flag the umbrella IG node with `handover_pending: true` + `handover_doc: <path>` + `handover_session: s<NNN>`. Direct port of CURLOP's flow.
3. **`/cuco:handover-log <NODE-ID>`** — mid-session out-of-scope finding: writes debug doc, flags node, returns to current work in one line. Pairs with the handover-log-nudge stop hook.
4. **`/cuco:ig-help`** — print the IG CLI reference (commands, schema, `ig apply` batch ops, `$ref` symbolic refs). Direct port; ig.cjs has no built-in help that matches the agent-facing conventions.
5. **`/cuco:fresh-eyes`** — re-read working tree from scratch, ignoring conversation context, report observed-vs-claimed. Direct adaptation — useful when "rotting in realtime" sets in.
6. **`/cuco:park-decision`** — write parked-decision doc to `.planning/parked/`, create `concept` IG node (CON-NNN) for it, return to current work in one line.
7. **(Optional, defer)** Persona commands: `/cuco:ask-reaper-expert`, `/cuco:ask-imgui-critic`, `/cuco:ask-lua-quality`. Three is enough — don't replicate CURLOP's eight.

**Done when**: The four operational commands exist and are invokable. Personas optional.

**Cost**: 1 session, ~2 hours.

---

### Phase 5 — Issue Graph + ADR/spec migration

**Goal**: Port CURLOP's IG (engineering brain) so STATE.md / handovers / scattered TODO comments stop being the source of truth, and seed it with current CUCO reality.

**Port from CURLOP**:

1. **`tools/ig/ig.cjs`** — copy from `/Users/f.god/Work/Development/CURLOP/tools/ig/ig.cjs`. The CLI is project-agnostic (reads/writes `.issues.json` in cwd). Verify by running `node tools/ig/ig.cjs --stats` against an empty `.issues.json`.
2. **`.issues.json`** — start empty: `{"version":"0.3.0","nodes":[],"edges":[]}`.
3. **Schema** — adopt CURLOP's v0.3.0 node types, retyped for CUCO:
   - `milestone` (M-NNN) — broad direction (e.g. "Random Walk v1.0 distribution-ready")
   - `feature` (F-NNN) — current capability per script (Random Walk, Audiosuite+, Keyframe, Metadata Match, Shared Theme, Apply-FX, Archival, Import-Session-Track)
   - `subfeature` (SF-NNN) — committed scope under a feature
   - `future_feature` (FF-NNN) — prospective, promotes to SF when committed
   - `bug` (B-NNN) — broken behavior; `part_of` ≥1 feature + blocking milestone
   - `task` (T-NNN) — refactor / tooling / migration / testing infra
   - `knowledge` (K-NNN) — durable facts (TrackFX_GetParam destructure, ReaImGui-vs-Dear-ImGui divergence, 57MB plugin library handling)
   - `concept` (CON-NNN) — unproven design hypothesis
   - `specification` (SPEC-NNN) — paired with `.planning/specs/<file>.md`
   - Drop CURLOP-specific deprecated types (`cluster`, `vision`, `root-cause`, etc.)
4. **Edges** — `part_of` (hierarchy, multi-parent allowed), `blocks`, `relates_to`. Same as CURLOP.
5. **Hygiene + apply** — port `ig hygiene` and `ig apply <ops.json>` for batch ops with `$ref` symbolic refs. Already in `ig.cjs`.

**Seed data** — populate IG with what we already know:

- **M-001** "Random Walk v1.0 distribution-ready"
- **M-002** "Audiosuite+ Phase 2 (chain-on-takes)"
- **M-003** "CUCO project-management migration" (this plan itself)
- **F-001..F-008** one per script
- **K-001** TrackFX_GetParam returns 3 values, not 4
- **K-002** TrackFX_GetNumParamSteps doesn't exist; use format-sampling
- **K-003** ReaImGui diverges from Dear ImGui; check `/cfillion/reaimgui` first
- **K-004** Plugin library file is 57MB — line-anchored greps only
- **SPEC-001** `shared-theme-contract.md`
- **SPEC-002** `reaimgui-usage.md`
- **SPEC-003** `reaper-api-conventions.md`
- **CON-001** Random Walk weighted-distribution shape picker (current implementation; promote to SF after distribution-polish phase)
- **T-NNN** open work items pulled from current handover's "In progress / unresolved" block

**ADRs** (`.planning/adrs/`, paired with `specification` IG nodes via `doc_path`):
- `ADR-001-shared-theme-module.md`
- `ADR-002-random-walk-classifier-strategy.md` — 5-path approach, metadata-override > name-patterns
- `ADR-003-audiosuite-plus-chain-on-takes.md`

**Specs** (`.planning/specs/`):
- `shared-theme-contract.md` — the `_shared/cuco_imgui_theme.lua` API
- `reaimgui-usage.md` — patterns + footguns (Begin/End contract, AllowItemOverlap absence, Viewport_GetWorkSize fallback)
- `reaper-api-conventions.md` — destructure rules, format-sampling for steps, 57MB-library handling

**Document Pairing Rule** — adopt verbatim from CURLOP: any IG node capturing significant technical finding gets a companion doc in `.planning/research/` referenced via `properties.research_doc`.

**`memory/` deprecation**: contents migrated to IG knowledge nodes + specs. The auto-memory layer (Claude's `MEMORY.md`) stays — but it points at IG nodes / spec paths instead of duplicating content.

**Done when**: `.issues.json` populated with milestones + features + the seed knowledge/spec/concept nodes, three ADRs exist, three specs exist, `node tools/ig/ig.cjs --stats` returns sane numbers, current handover's open items are logged as task nodes.

**Cost**: 1 session, ~4 hours (most of it data entry, not code).

---

## Sequencing

Phases are ordered by dependency — each unlocks the next:

- **Phase 1 → 2**: CLAUDE.md references paths created in Phase 1.
- **Phase 2 → 3**: hooks reference rules established in CLAUDE.md.
- **Phase 3 → 4**: slash commands assume hook output is the session-start state.
- **Phase 5**: depends only on Phase 1; can run in parallel with 2-4 if appetite exists.

**Recommended order**: 1 → 5 → 2 → 3 → 4. Reason: IG (Phase 5) is now the spine that CLAUDE.md and the hooks reference. Land it before writing rules that cite it. Phase 5 also captures durable knowledge while it's freshest.

---

## Explicit non-goals

- **No UPG** (product graph). CUCO has no users to journey-map.
- **No mechanical invariant audits** (`scripts/invariants/*.sh`). Lua isn't worth the tooling.
- **No build rules section.** Lua interprets; REAPER reloads on save.
- **No release protocol.** CUCO ships via ReaPack and personal Dropbox; not a versioned product cut.
- **No K-024 pathology audit script.** The doc itself can be referenced from CLAUDE.md as a reading; no enforcement.

---

## Risks

1. **Over-ceremony.** CUCO is a personal toolkit. If `.planning/` becomes a chore, the discipline rots. Mitigation: every artifact must answer "does future-me thank present-me for this?" — if no, skip.
2. **Migration drift.** Doing this incrementally means the working tree gets bigger before any commits. Mitigation: do Phase 1 in a single session and commit it whole; same for each subsequent phase.
3. **Hook noise.** CURLOP's session-start output is finely tuned over 380 sessions. CUCO's first version will be too verbose or too sparse. Mitigation: ship lean, iterate over 3-5 sessions before declaring it done.

---

## First action after approval

Recommended order is **1 → 5 → 2 → 3 → 4**. So:

1. Create `.planning/` subdirectory tree.
2. Move `projects/audiosuite-plus/PLAN.md` and `.session/HANDOVER.md` into canonical locations.
3. Commit as `chore: bootstrap .planning/ tree (Phase 1 of CURLOP migration)`.
4. Then start Phase 5 (port `ig.cjs`, seed `.issues.json`).

Stop after each phase. Read the result. Decide if the next is worth it.
