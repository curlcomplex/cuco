# Handover — SPEC-005/006 open questions + CUCO Sweep audit (s327 → next)

📋 Citation check skipped — `scripts/check-handover.sh` not installed in CUCO. Manual review for canonical citations applied.

---

## 🛑 PROTOCOLS FIRST (mandatory — read before Turn-1)

This opener is **context, not directive.** Run session-start protocols before touching any file:

1. **CLAUDE.md Session Workflow 1–4** — read the SessionStart hook output (active milestones, blockers, ready work, knowledge nodes). Don't re-run those queries verbatim. Intent-verify: this handover claims `bb4038b` shipped K-006 + SPEC-005 + SPEC-006 — verify against `git log --oneline -3` and `node tools/ig/cuco_scripts_ig.cjs K-006`. State a one-line brief with citation before any work.
2. **Canonical-source verify pass.** Every "deferred / open question / convention applies" claim below cites a canonical doc. Open the cited SPEC or research doc and verify the claim is in the source — do NOT inherit forward-looking framing unchecked. Three canonical sources are listed below.
3. **Governing specs** — read `.planning/specs/control-driven-jsfx-processors.md` and `.planning/specs/control-driven-jsfx-sequencers.md` end-to-end before answering any Turn-1 question. The Open Questions sections are the work surface.
4. **`ig SPEC-005`, `ig SPEC-006`, `ig K-006`** — surfaces description read-mandates and the `relates_to` cross-links.
5. **REAPER/ReaImGui doc check** — only relevant if Turn-1 advances to actual JSFX code (e.g. CUCO Sweep audit edits). For SPEC-conformance auditing of `Effects/Modulation/CUCO Sweep` (a JSFX, *not* a Lua/ReaImGui script), no `reaper.ImGui_*` is in scope; consult the JSFX language reference at <https://www.reaper.fm/sdk/js/js.php> if any function call is unfamiliar.

ABSOLUTE BAN 5 (discuss before writing code) and 7 (citations for every alignment claim) apply.

---

## Status anchor

Three docs landed at `bb4038b` on `main`: **K-006** (control-driven JSFX architecture, umbrella philosophy, recursive framers→sequencers→processors), **SPEC-005** (control-driven JSFX processors, v0.1 draft), **SPEC-006** (control-driven JSFX sequencers, v0.1 draft). Both SPECs ship with **Open Questions** sections — six total, three each — gating promotion to v1.0. No JSFX code touched this session; CUCO Sweep is named as the only existing audio JSFX likely to conform but is unaudited.

---

## Mandatory reading (4 surfaces)

### 1. Source

- `Effects/Modulation/CUCO Sweep` — the only existing audio JSFX expected to conform to SPEC-005. Read the `desc:`, `slider*:` declarations, and `@init`/`@slider`/`@sample`/`@gfx` sections to audit against SPEC-005 *Required conventions*. Path is a directory (JSFX file inside).
- `Effects/lib/cuco_theme.jsfx-inc` and `Effects/lib/cuco_widgets.jsfx-inc` — referenced by both SPECs as the GUI foundation. Skim to confirm they exist + what they currently export.
- N/A for sequencers — no JSFX sequencer exists in repo, SPEC-006 defines a future contract.

### 2. IG nodes

- **SPEC-005** `control-driven-jsfx-processors` — domain contract for audio-domain JSFX. Has the CUCO Sweep audit candidate.
- **SPEC-006** `control-driven-jsfx-sequencers` — domain contract for MIDI/CC-emitting JSFX. No conformer yet; gates first reference sequencer build.
- **K-006** `Control-driven JSFX architecture` — umbrella philosophy. Both SPECs have `relates_to → K-006` edges.
- **F-008** `Shared theme module` — separately maintained; both SPECs assume `cuco_theme.jsfx-inc` exists. No cross-edge yet.

### 3. Specs

- `.planning/specs/control-driven-jsfx-processors.md` — entire doc, especially **Opt-in criteria**, **Required conventions**, **Forbidden**, **Open questions** (3 items).
- `.planning/specs/control-driven-jsfx-sequencers.md` — entire doc, especially **Required conventions § Sliders** (slider-budget strategies), **§ MIDI emission** (declared MIDI stance), **Open questions** (3 items).

### 4. Research / handover

- `.planning/research/control-driven-jsfx-architecture.md` — umbrella philosophy + recursive layering diagram. Read first; it's the shared frame both SPECs cite.
- `.planning/research/jsfx-capabilities.md` lines 180-199 — the "Practical guidelines for the CUCO suite" section is what the SPECs codify and extend. Pre-existing; not authored this session.
- `.planning/research/gui-research.md` — the `geraintluff/jsfx-ui-lib` + `cuco_theme` + `cuco_widgets` plan that the SPECs assume.
- `.planning/handovers/2026-05-10-T-026-events-refactor-verify.md` and `.planning/handovers/2026-05-10-T-043-reapack-import-verify.md` — **carried forward from prior session, NOT consumed s327.** Still pending. Independent of this handover; surface alongside it at next session start.

---

## Canonical sources

- **`.planning/research/control-driven-jsfx-architecture.md` (K-006)** — authorizes: the recursive three-layer framing (framers → sequencers → processors), the "tagged design pattern, not house style" stance, the opt-in declaration mechanism (header tag form TBD).
- **`.planning/specs/control-driven-jsfx-processors.md` § Open questions** — authorizes the three processor open questions: header-tag opt-in form; smoothing-coefficient defaults (per-unit vs suite-wide); channel handling (stereo-only vs mono-tolerant).
- **`.planning/specs/control-driven-jsfx-sequencers.md` § Open questions** — authorizes the three sequencer open questions: slider-budget strategy default (generative vs compact-step-storage vs per-step-automation-lane); default MIDI stance (`replace` vs `passthrough`); CC-input handling (accept for slider modulation vs defer to REAPER's MIDI-learn).
- **`.planning/research/jsfx-capabilities.md` lines 180-199** — authorizes the underlying "Practical guidelines" the SPECs codify (every-param-a-slider, smooth-in-`@sample`, allocate-in-`@init`, bipolar-where-natural, `ui_automate()` for GUI writes).

---

## Turn-1 action

After protocols above, propose this sequencing to the user (do not execute without agreement — ABSOLUTE BAN 5):

1. **Resolve the shared header-tag question first** [per SPEC-005 § Open questions and SPEC-006 § Open questions]. Both SPECs cross-reference each other's choice; resolving it for one resolves it for both. Two viable forms recorded: `desc: ... [control-driven-processor]` suffix vs `// CUCO-CONFORMS: SPEC-005 v1.0` comment block. Pick one with reasoning, update both SPECs in lockstep.
2. **Audit `Effects/Modulation/CUCO Sweep` against SPEC-005** [per SPEC-005 § Currently in the suite]. Output a list of conformances + gaps. This is the empirical validation that promotes SPEC-005 from v0.1 draft → v1.0 (or surfaces SPEC bugs). Do NOT modify the JSFX yet — just report.
3. **Resolve remaining open questions in priority order:**
   - SPEC-006 slider-budget default (highest leverage — gates first reference sequencer's whole architecture).
   - SPEC-006 default MIDI stance (`replace` recommended; check Saike's StereoBouncer + Tale's MIDI step sequencer for prior art).
   - SPEC-005 smoothing-coefficient default + channel handling.
   - SPEC-006 CC-input handling.
4. **Promote SPECs to v1.0** once all six open questions are resolved AND CUCO Sweep audit reports either full conformance or a planned remediation. Update `properties.version` from `0.1-draft` to `1.0` via `cuco_scripts_ig.cjs update`.

**Verify before declaring v1.0:**
- Each open question's resolution recorded in the SPEC body (not just the changelog).
- CUCO Sweep audit either lands as conformant or a T-NNN node tracks the remediation work.
- `node tools/ig/cuco_scripts_ig.cjs SPEC-005` and `… SPEC-006` show `version: 1.0` in properties.

---

## Discipline rules (picked for this work's failure modes)

- **ABSOLUTE BAN 5 — discuss before writing code.** This Turn-1 is decision work, not implementation. Resolve open questions in conversation; only then propose JSFX edits.
- **ABSOLUTE BAN 7 — citations for every alignment claim.** Every "CUCO Sweep conforms to X" or "SPEC says Y" needs spec-line + IG node citation. The audit output is invalid without them.
- **Debugging rule 2 — codebase is not source of truth.** When auditing CUCO Sweep, the SPEC is the authority; if Sweep does something the SPEC forbids, that's a Sweep bug, not a SPEC concession. (Unless the audit reveals the SPEC itself is wrong, in which case STOP and discuss.)
- **Obstacle = Stop and Ask.** If the SPECs themselves prove unworkable mid-audit (e.g. ui-lib doesn't actually expose `ui_automate` as documented), surface the obstacle with options — don't reframe the SPEC silently.
- **Log decisions to IG immediately on agreement (Session Workflow rule 4).** Each open question's resolution is a "decision made" — `update SPEC-NNN --note "[s<NNN>] resolved Q-X: <answer>. Reason: <one line>."` *before* moving to the next question, not at session end.

---

## Branch + recent commits

- Branch: **`main`**
- HEAD: **`bb4038b`**
- Last 5:
  - `bb4038b` docs(specs): K-006 + SPEC-005/006 — control-driven JSFX architecture
  - `5b12fbb` feat(ig): T-043 handover — verify ReaPack import in fresh REAPER
  - `803d9de` feat(reapack): T-021 generate index.xml — publish Keyframer 0.7.0 + Random Walk 4.0.0
  - `fcbba0f` docs(handover): T-026 events[] refactor — verify byte-identical MIDI output next session
  - `09b5835` refactor(tidal): T-026/T-027 — events[] intermediate + terminal MIDI write

---

## End-state

"Done" for this handover means **all six open questions resolved + CUCO Sweep audit complete + both SPECs at v1.0** with `properties.version` flipped in IG. On completion:

1. Commit each SPEC's v1.0 promotion as one commit per spec (`docs(spec): promote SPEC-005 to v1.0 — open questions resolved`).
2. `update SPEC-005 --note "[s<NNN>] v1.0 promoted. Q-A: <answer>. Q-B: <answer>. Q-C: <answer>. CUCO Sweep audit: <conformant | T-NNN remediation tracked>."` and same for SPEC-006.
3. Clear this handover's pending flag: `node tools/ig/cuco_scripts_ig.cjs update SPEC-005 --props '{"handover_pending":false}'`.
4. If CUCO Sweep audit surfaces remediation work, log a T-NNN under F-008 (or under a new F-NNN for the JSFX suite if missing) and `part_of` SPEC-005.
5. If sequencer reference build is the natural next step, log a T-NNN under SPEC-006 and either start a new milestone or fold into M-001/M-004.

---

## Caveats / context

- **Two prior handovers remain pending and were NOT consumed this session.** T-026 (events[] refactor verify) and T-043 (ReaPack import verify) are independent of this work. Next session's SessionStart hook will surface all three. User chose to pivot to SPEC drafting; the prior handovers' work is genuinely deferred, not stale.
- **No JSFX code was written this session** — all output is documentation. Don't treat any SPEC convention as battle-tested until at least one JSFX has been audited or built against it.
- **`F-008 Shared theme module`** is referenced by both SPECs (the `cuco_theme.jsfx-inc` + `cuco_widgets.jsfx-inc` foundation). It exists in `Effects/lib/` but is not currently linked to SPEC-005/006 in IG. If the audit reveals theme-module work, surface it as part of F-008 or create a `relates_to` edge.
- **The "header-tag opt-in" mechanism is unfixed across all three docs.** K-006 says "convention TBD"; both SPECs list it as Q-1. Resolving it is a global edit, not a single-doc edit — make sure all three docs land the same form.
- **No CON-NNN created for the umbrella.** Considered briefly; rejected because the architecture is settled, not hypothetical (K-NNN is the right type per IG schema). If next session disagrees, the demotion path is `update K-006 --type concept` but it's a surprising move.
