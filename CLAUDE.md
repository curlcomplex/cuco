# CUCO: Claude AI Workflow Rules

Auto-loads every session. Operational rules only — not project history.

**Always read first**: the SessionStart hook injects an IG snapshot (active milestones, top blockers, ready work, knowledge nodes). Read it. Don't re-run those queries verbatim.

---

## Handover system (session-end + mid-session)

Caveman:

- **Session start.** Hook prints fresh-handovers + IG snapshot. Read both.
- **Fresh handover** = pending work from past session. `.claude/hooks/fresh-handovers.cjs` reads IG nodes with `properties.handover_pending: true`. Surface to user. Ask "start it?".
- **IG flag schema.** `properties.handover_pending: true` + `handover_doc: <path>` + `handover_session: s<NNN>`. Doc lives in `.planning/handovers/<DATE>-<NODE-ID>-<slug>.md`.
- **After consuming a handover.** Clear flag: `node scripts/ig/cuco_scripts_ig.cjs update <id> --props '{"handover_pending":false}'`.
- **End of session.** `/handover-prompt` writes the next-session opener + flags umbrella IG node. Opener leads with protocols-first block; reconciles prior handovers in-place (no archive moves).
- **Mid-session out-of-scope find.** `/handover-log <NODE-ID>` (or bare to create a node). Writes a deferred-work doc, flags node, returns to current work in one line. Do not derail.
- **Stop hook watches.** Saying "out of scope" / "for another session" / "park for later" / etc. without invoking `/handover-log` → hook blocks stop, demands either a handover-log call or an explicit `HANDOVER-LOG-NUDGE: FALSE-POSITIVE` marker. Bypass with `HANDOVER_NUDGE_OFF=1`.

---

## ABSOLUTE BANs — READ BEFORE DOING ANYTHING

1. **NO subagents for implementation.** Never use the Agent tool / Task() / any subagent to write Lua. Write all implementation code yourself. Subagents miss REAPER API quirks (the `TrackFX_GetParam` destructure bug, ReaImGui divergence) and ship plausible-looking nonsense.
2. **NO REAPER API guessing.** Before writing or fixing any `reaper.*` call you're not 100% sure of, query context7 (`/cfillion/reaimgui` for ImGui, REAPER's SDK help page for everything else). Don't reason from mental model. The API is truth — your memory of it is not. See K-003 (ReaImGui divergence) and K-002 (`TrackFX_GetNumParamSteps` doesn't exist — was invented for hours one session).
3. **NO destructure assumptions for REAPER API return tuples.** REAPER returns specific arities; getting it wrong silently corrupts downstream code without erroring. Read the SDK page; count the return values. See K-001: `TrackFX_GetParam` returns 3 values not 4. The bug hid in Random Walk's classifier from inception until 2026-05-07.
4. **NO full-read of the plugin library file.** `~/Library/Application Support/REAPER/Scripts/CUCO Random Walk Plugin Library.lua` is 57MB / 566K lines. Use line-anchored greps (`^M\[` for plugin entries) or sed with line ranges. Watch for non-UTF8 byte-sequence errors in `awk`. See K-004.
5. **DISCUSS before writing code.** Don't plan alone. Don't execute alone. Talk to the user about approach first. The user's time is the most expensive resource here.
6. **Read the IG snapshot before any non-trivial action.** The session-start hook loads active milestones, top blockers, ready work, and knowledge nodes. Re-running those queries is redundant work. For deeper context: `ig <id>` for node detail, `ig --children <M-id>` for the full blocker list, `ig --search <q>` for keyword.
7. **NEVER claim alignment without citations.** When the user asks whether work matches intention or spec, the answer must cite (a) the spec/roadmap line the work advances toward, (b) the IG node(s) it closes/advances. A response without those is invalid. If you can't produce them, the answer is "not verified — let me check," never "yes."

---

## Golden Rule: Check ReaImGui + REAPER SDK docs FIRST

ReaImGui is not Dear ImGui. The binding diverges. Flags like `AllowItemOverlap` may not exist; `Begin/End` contracts have specific patterns; `Viewport_GetWorkSize` may be absent on older builds (wrap in `pcall`).

Before any work on `reaper.ImGui_*`:

1. **Query context7** with library ID `/cfillion/reaimgui`. Get the current binding signature.
2. **For non-ImGui REAPER API**, check the official SDK help: `curl -s https://www.reaper.fm/sdk/reascript/reascripthelp.html | grep -A5 <FunctionName>`. The SDK page lists exact return tuples. Don't WebFetch it — the summary is lossy on return-value count.
3. **Then write code.**

Never build what ReaImGui or the REAPER SDK already provides. If the API has it, use it.

---

## Project structure

```
CUCO/
├── CLAUDE.md                       — this file (operational rules)
├── .planning/                      — process artifacts
│   ├── MIGRATION-PLAN.md           — CURLOP-method adoption plan
│   ├── adrs/                       — architecture decision records
│   ├── handovers/                  — date-prefixed session bridges
│   ├── phases/<feature>-phase-N/   — multi-cut feature work
│   ├── research/                   — companion docs paired to IG nodes
│   ├── specs/                      — canonical contracts (vs concepts)
│   └── parked/                     — deferred decisions
├── .issues.json                    — IG state (do not edit by hand)
├── .claude/                        — Claude tooling
│   ├── commands/                   — /<name> slash commands
│   ├── hooks/                      — session-start, stop, etc.
│   └── settings.json               — hook wiring
├── scripts/ig/cuco_scripts_ig.cjs  — IG CLI
├── projects/<script>/              — actual CUCO scripts
└── projects/_shared/               — shared theme module + helpers
```

The `_shared/` module (`projects/_shared/cuco_imgui_theme.lua`) holds the palette + theme helpers consumed by all CUCO ImGui scripts. Don't redefine theme primitives locally. See SPEC-001.

---

## Issue Graph (IG) — Schema + Workflow

The IG is the single source of truth for active work. Schema v0.3.0; every node has `id`, `type`, `status`, `title`, `description`, `tags[]`, `priority` (1-5, 1=highest), `ready`, `properties{}`.

### Node types

```
milestone       M-NNN     broad direction / shippable target
feature         F-NNN     current capability (one per script + shared theme)
subfeature      SF-NNN    committed scope under a feature
future_feature  FF-NNN    prospective; promotes to subfeature on commit
bug             B-NNN     broken behavior; part_of ≥1 feature + blocking milestone
task            T-NNN     refactor / tooling / migration / testing
knowledge       K-NNN     durable architectural fact, load-bearing constraint
concept         CON-NNN   unproven hypothesis — promotes to knowledge/SF or discards
specification   SPEC-NNN  canonical doc; paired with `.planning/specs/<file>.md`
```

Hierarchy edges are all `part_of`. Multi-parent allowed. Other edges: `blocks`, `relates_to`, `causes`, `affects`, `same_root_cause`, `subsumes`, `revealed_by`.

### Reads

```
node scripts/ig/cuco_scripts_ig.cjs --type milestone --status open
node scripts/ig/cuco_scripts_ig.cjs --children M-NNN --status open
node scripts/ig/cuco_scripts_ig.cjs --ready --next 5
node scripts/ig/cuco_scripts_ig.cjs --type knowledge
node scripts/ig/cuco_scripts_ig.cjs <id>
node scripts/ig/cuco_scripts_ig.cjs --search <q>
node scripts/ig/cuco_scripts_ig.cjs --stats
```

Full reference: `/ig-help`.

### Writes

- **Rich content** — use `--desc-file <p>` / `--note-file <p>` for multi-line, backticks, em-dashes. Inline `--desc "..."` only for one-liners (shell-escape failures silently corrupt descriptions).
- **Bulk ops (≥3 writes)** — use `apply <ops.json>` with `$ref` for cross-references. Atomic, validated, fast. Never loop single-op writes.
- **Idempotency** — `update` is compare-before-set; pass `--dry-run` to preview.
- **Hygiene** — `hygiene` sweeps stale blocks + dupe edges. Run after closing a batch of tasks.

### What to log

Decisions made, permanent facts established, blockers encountered/resolved. NOT implementation traces. Pair significant findings with a doc via `--doc <path>` (Document Pairing Rule — companion in `.planning/research/`).

---

## Session Workflow

1. **Session-start context is already loaded by the hook.** Don't re-run those queries verbatim.
2. **Intent-verify pass** for every prior-session claim that says work "landed" / "shipped" / "is done":
   - State the claimed **Intent** in plain language.
   - Run a **Verify** check (read the file, run the script, query the IG node).
   - Report: `Intent: X. Verify: ran Y. Result: MATCH | MISMATCH (details).`
   - Mismatch → stop. Flag to user.
3. **Present a one-line session brief** before starting work — what you understand the goal to be, with citation (IG node ID, spec section).
4. **Log multi-step plans to IG IMMEDIATELY upon agreement — BEFORE executing any step.** If a plan has structure (numbered phases, sequenced tasks, "we'll do X then Y then Z") and the user agrees, create the nodes + edges first as an `apply` batch. Don't rely on conversation state — `/clear` and compaction don't preserve it. Trigger signal: any response where you enumerate steps AND the user agrees ("yep" / "go" / "sounds good"). That is the log moment, not later.
5. **Implement.**
6. **Document learnings** in `.planning/research/` and pair with the IG node via `properties.research_doc`.
7. **At session end:** `update <id> --note <text>` for significant decisions/facts. Commit.

---

## Commit Format

```
type: brief description
```

Where `type` is `feat`, `fix`, `docs`, `refactor`, `chore`, etc. Conventional commits.

---

## Personas

**(Forward reference — populated when persona commands ship.)** When invoked, agent stays fully in character; one persona at a time; user can override.

---

## Obstacle = Stop and Ask

When a technical obstacle changes what you're building, **stop**. Tell the user what you found and what the options are. Do not:

- Reframe the limitation as a feature
- Pick an alternative approach without asking
- Present a workaround as if it was the plan all along
- Optimize for forward momentum over alignment with intent

**What to do instead**: "I hit obstacle. Here's what I found: [technical fact]. Here are options: [A, B, C]. Which direction?"

---

## Debugging & Research Rules

1. **Never assume something is broken — research first.** Problem is almost always incorrect usage, not a broken library.
2. **Codebase is not source of truth for architecture.** Codebase contains accumulated mistakes. Specs and ADRs are.
3. **5-tweak halt.** After 5 consecutive small changes without verified improvement, STOP. Write down what you KNOW vs what you ASSUME.
4. **Verify foundation before building.** Verify what existing code *produces*, not that it compiles/loads.
5. **Persistent debug logs.** Don't add and remove diagnostics churnously. Keep logs behind a runtime toggle.
6. **Research EXTERNALLY.** Documentation, forums, GitHub issues, working examples. Not the codebase.
7. **Verify before declaring fixed.** Reload the script in REAPER and exercise the change. Don't tell the user "fixed" until confirmed running.
8. **Always read existing code before making changes.** Regressions from not reading first are unacceptable.

---

## No Exceptions

Rules are non-optional. If blocked, document the blocker rather than bypassing.

---

## Tool Failures

When MCP tools or hooks fail, STOP immediately and report. Don't spend a session trying to discover/locate tools or fall back to workarounds without explicit approval.

---

## General Rules

- **Check it yourself.** When asked to check something (bug status, code state, git status), check it yourself by reading code or running commands. Never ask the user to check or report stale/incorrect status.
- **No subagents unless explicitly asked.** Direct execution preferred.
- **Memory points at IG, not at content.** Claude's auto-memory layer (`MEMORY.md`) should reference IG node IDs and spec paths, not duplicate their content. The IG is canonical.
