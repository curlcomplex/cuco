---
description: Compose next-session opener at session-end. Surveys this session (commits, IG, specs, deferred work), writes handover doc + flags IG node as pending, prints same opener to terminal as backup. Adapts to work shape — feature/bug/refactor/planning/milestone-start.
---

<objective>
Hands-off handover. Next session's SessionStart hook surfaces "📬 Fresh handover: <ID> <title>". User says "hi" → agent reads doc, runs protocols, proposes Turn-1.

**Two outputs:**
1. **File** — `.planning/handovers/<YYYY-MM-DD>-<NODE-ID>-<slug>.md` (canonical content).
2. **IG flag** — set `handover_pending: true` + `handover_doc: <path>` + `handover_session: s<NNN>` on the umbrella IG node (the task/bug/feature/milestone the handover is about).

Terminal print between `---` markers retained as backup so the user can paste manually if needed.

**Opener = CONTEXT, not directive bypass.** Must lead with protocols-first block. Failure mode guarded: agent reads Turn-1 directive ("execute X" / "decide A vs B"), skips Session Workflow + IG snapshot + spec reads, ships wrong direction.
</objective>

<context>
- `git log --oneline -15` + `git branch --show-current`
- `git status --short`
- IG: `node tools/ig/cuco_scripts_ig.cjs --search s<NNN>` + scan today's `updated`
- Specs/research touched: `git diff --name-only HEAD~N | grep .planning`
- CLAUDE.md: @CLAUDE.md
</context>

<process>
**Close-out → survey → classify → compose.** Don't write before reading state, and don't author a new handover while prior ones are still flagged.

### Step 0 — Close out prior handovers (mandatory, runs FIRST)

Failure pattern this guards: prior handover stays `handover_pending: true` while new work ships, so next session's `fresh-handovers` hook surfaces stale work. Cleanup = **content reconciliation**, NOT file movement.

1. **Find every node with the flag set:**
   ```bash
   node -e 'const d=JSON.parse(require("fs").readFileSync(".issues.json","utf8"));
            for (const n of d.nodes||[]) if (n.properties?.handover_pending===true)
              console.log(n.id, "|", n.status, "|", n.title);'
   ```
2. **For each pending node — RECONCILE THE DOC, do NOT archive.** The handover doc is the human-readable record of what *was promised*. After consuming it, that record needs the *outcome* attached, in-place, so future readers (including next session) see what shipped vs what carried vs what was superseded.

   For each pending node `<prior-id>`:

   **a. Read the handover doc end-to-end.** Identify every concrete claim/promise:
      - "Turn-1 action: [step list]" — which steps actually ran, which were skipped, which were redirected
      - Plan/spike/integration sections — which path got taken, which got rejected, what the empirical result was
      - "End-state" success criteria — were they met, partially met, or rendered moot
      - Listed open questions, untaken options, parked alternatives — which are now resolved + how

   **b. Update the doc IN PLACE with outcomes, in-line.** Patterns:
      - **Top-of-file CONSUMED banner** — quote-block near the title with: "✅ CONSUMED s<NNN> — [one-sentence outcome]." Followed by: concrete decision/result, captured artifacts (commits, IG IDs, research docs, branches), untaken options, "stop here unless..." signal for future readers.
      - **In-line "→ shipped at <commit>" / "→ superseded by <X>" annotations** at each step/section the outcome touches. Don't bury closures in a footer.
      - **Strikethrough or "[SUPERSEDED s<NNN>]" prefix** on sections invalidated by later work.
      - **Remove no content.** The original promise stays readable so a future grep can find context. Outcomes are additive overlays.

   **c. Walk children (`ig <id>` → `Blocks:` list) and update IG status:**
      - Child landed this session → `--status fixed --verification uat` (if user verified) or `pending-verify` (if code-landed, eye-pending).
      - Child not landed and being deferred → leave open; the new handover carries it.
      - If the prior node's children are all closed/pending-verify, set the prior node itself to `pending-verify`.
      - If it has open children deferring to a NEW node, leave the prior node `open` but the closure banner records the carry.

   **d. Append an IG closure note + clear the flag:**
      ```bash
      node tools/ig/cuco_scripts_ig.cjs update <prior-id> --note "[s<NNN>] consumed — N fixed, M pending-verify, K carried to <new-id>. Doc reconciled in-place at <doc-path>."
      node tools/ig/cuco_scripts_ig.cjs update <prior-id> --props '{"handover_pending":false}'
      ```

   **e. Do NOT move the doc.** It stays at its original `.planning/handovers/<date>-<id>-<slug>.md` path. The reconciled banner + in-line annotations are how future readers see it's consumed. **Filesystem hygiene (archiving) is NOT cleanup — content currency is.** If a prior-session handover has open children whose work is ongoing, the doc MUST stay visible in the top-level dir so it's not silently buried.
3. **Update referenced research/spec docs** the prior handover named. Mark closures + carry-overs at the line, not in a footer. Same in-place principle.
4. **Print a close-out summary BEFORE the new opener block:**
   ```
   🧹 Close-out:
     <prior-id-A> reconciled — N fixed, M wontfix, K → <new-id>. Doc updated in-place. Flag cleared.
     <prior-id-B> reconciled — N pending-verify. Doc updated in-place. Flag cleared.
   ```
   If nothing to close, print `🧹 Close-out: no prior handover flags set.` and proceed.
5. **Hard rules:**
   - Do not proceed to Step 1 with any `handover_pending: true` node OTHER than the one this command is about to write.
   - **Cleanup means content reconciliation, not file movement.** Handover docs stay where they were authored. Archiving/moving on disk is forbidden — open work in prior-session handovers must remain visible at top-level so it's not buried. The CONSUMED banner + in-line annotations are how a doc signals "done" without disappearing.

### Step 1 — Survey (parallel)

- branch, last 10 commits, status
- IG nodes touched/created this session (`knowledge`, `bug`, `task`, `concept`, `subfeature`, `specification`)
- Spec/research session-log entries

### Step 2 — Classify work shape

Pick one. Opener structure adapts.

- **Feature/phase** — multi-step + closure criteria → scoreboard + gate-closure order
- **Bug** — hypothesis chain → current hypothesis + next probe + ruled-out
- **Refactor** — invariant audit gates → pass-state + remaining sites + safety net
- **Planning** — parked specs → open questions + adversarial-audit checklist
- **Milestone start** — fresh → bias forward, journey doc, first phase
- **Tool/infra fix** — small surface → "follow up on X" line; ask user if full structure wanted

Mixed → pick dominant, secondary as one-line aside.

### Step 3 — Compose

Print between `---`. Sections = menu, not checklist. **Order below is mandatory.**

#### Always include — IN ORDER

1. **🛑 PROTOCOLS FIRST (mandatory, leads opener).** Block at literal top: "Before Turn-1, run session-start protocols. Opener = CONTEXT, not bypass."

   Enumerate per work shape:
   - **CLAUDE.md Session Workflow 1–4** — hook output, intent-verify on every "shipped/landed/flipped" claim (confirm against source, not against summary docs), one-line brief w/ spec citation before work, log multi-step plans to IG immediately on agreement
   - **Canonical-source verify pass (mandatory for multi-session work)** — for every "deferred / out of scope / spike required / pattern applies / completed" claim this opener inherits or makes about future work, open the cited canonical doc (SPEC / ADR / research doc / plan) and verify the classification. **Do NOT inherit forward-looking framing from a predecessor handover unchecked.**
   - **Governing specs** — `.planning/specs/*.md` — every alignment claim cites spec-line + invariant per CLAUDE.md ABSOLUTE BAN 7
   - **`ig <id>`** for every umbrella node — surfaces description read-mandates
   - **REAPER/ReaImGui doc check** — for any `reaper.*` call in scope, query context7 `/cfillion/reaimgui` (ImGui) or `curl` REAPER's SDK help page first per CLAUDE.md Golden Rule

   Tailor list per shape. Never omit "do this before Turn-1" framing. Block = literal first read.

2. **Status anchor** — one sentence: done / not-done, branch, HEAD, native-vocab. Examples:
   - Feature: "T-005 distribution polish 3/5 done at HEAD a1b2c3d on main."
   - Bug: "Hypothesis 2-of-4 confirmed at f4e5d6a on fix-keyframe-prune."
   - Refactor: "F-003 Keyframe theme retrofit landed; runtime-verify pending."
   - Planning: "ADR-002 classifier-strategy parked at PARKED.md, fresh-eyes pending."

3. **Mandatory reading (4 surfaces)** — must span ALL:
   1. **Source** — paths + `file:line` ranges
   2. **IG nodes** — every touched/blocked-by/load-bearing. Inline subjects (`B-007 keyframe persistence drift`, not bare `B-007`)
   3. **Specs** — `.planning/specs/*.md` + section
   4. **Research/handover** — `.planning/research/*.md` companions + prior briefs

   Each: path-or-ID + one-line WHY. Order: parent task / load-bearing first. Tell next agent NOT to re-litigate session-log decisions. Surface genuinely N/A → state with reason. Don't silent-omit.

4. **Canonical sources (mandatory for multi-session work; OPTIONAL ONLY for one-shot bug fixes / single-session tasks).** A bullet list naming the load-bearing docs from which this handover derives forward-looking claims (governing SPEC, ADR, prior plan, research doc). For each: path + one-line WHAT-IT-AUTHORIZES. Required because every "deferred / spike required / pattern applies / out of scope / remaining" claim further down MUST cite back to one of these sources inline (`[per <doc> §<section>]` or `[per <doc>:line]`). If a claim has no canonical-source citation, it is unsourced and must be reframed as "agent's read, not yet verified" or removed.

5. **Turn-1 action** — phrased "after protocols above, [action]". 2–4 specifics to verify (REAPER reload + reproduce, IG flag clear, file:line check). Bias "verify hypothesis encoded in K-NNN" over "implement T-NNN" — knowledge/source drift is #1 failure.

6. **Discipline rules** — 3–5 from memory/CLAUDE.md, picked for THIS work's failure modes. One-liner each: requires + why now. Not generic dump.

7. **Branch + recent commits** — exact branch + 5–8 commits w/ one-line summaries.

8. **End-state** — what counts as "done", what to do then (commit/push/mark/surface).

#### Include only when relevant

- **REAPER verify steps** — only if running-script verification scoped (load script, exercise UI, observe). List actual probes. Skip for engine/IG/planning/doc-only.
- **Closure-step list w/ observables** — only finite-remaining + verifiable end-states. Each step needs observable: file:line check, IG status, REAPER reload + UI behaviour. "Implement and test" too vague. Exploratory → "next probe" instead.
- **"Land first" tag** — only real dependency-bearing unblocker. No fabrication.
- **Caveats** — surprises + cycle-burns from this session. Failure mode + workaround. Skip if clean.
- **"Don't re-litigate"** — only if spec corrections this session. Point at session-log entry.

### Step 4 — Quality check (drop checks N/A to shape)

- **🛑 Opener LEADS w/ protocols block.** Status anchor + Turn-1 BELOW. Reordered → FAIL.
- **Turn-1 phrased downstream of protocols** — bare "do X" w/o "after protocols above" prefix → FAIL.
- **Anchor commit + branch correct** — re-run `git rev-parse HEAD` if uncertain.
- **Every IG ID / path / hash verifiable** — no placeholders, no hallucinations.
- **Reading covers 4 surfaces** — source / IG / specs / research. Omitted surface needs one-line reason. Bare IG IDs = FAIL.
- **Canonical sources section present (multi-session work)** — names ≥1 load-bearing canonical doc with its `WHAT-IT-AUTHORIZES` line. Single-session / one-shot bug fix → may omit with explicit reason. Missing without reason → FAIL.
- **Forward-looking claims inline-cited** — every "deferred / spike required / pattern applies / out of scope / N batches remaining" claim carries a `[per <doc> §<section>]` or `[per <doc>:line]` citation back to a Canonical sources entry. Uncited forward claim → FAIL (must be reframed "agent's read, not yet verified" or removed).
- **Citations (mirrors ABSOLUTE BAN 7)** — every prior-state claim ("X flipped", "Y closed", "Z spec says…") paired w/ file:line / IG-ID / spec section / commit. Unsourced → cut.
- **No forced framing** — gate-scoreboard for bug-investigation = force-fit. Reframe in native vocab.
- **No N/A mandatory sections** — REAPER verify probes for doc-only = drop.
- **Closure observables concrete** — every "do X" has "verify by Y".
- **Caveats captured** — failures, not just successes.
- **No re-litigation invite** — this-session decisions tagged "don't re-debate".
- **Length** — ~one screen rendered. Tight beats comprehensive.

### Step 5 — Pick the umbrella IG node

The handover is *about* a node. Pick one:
- Feature/phase work → the task/subfeature/feature being advanced
- Bug investigation → the bug node
- Refactor → the umbrella task
- Planning → the parked spec or its tracking node
- Milestone start → the milestone node

If genuinely no fitting node exists, create one first (`cuco_scripts_ig.cjs create task "<short title>" --desc-file ...`) and use that. Bare-floor handovers (no IG anchor) are forbidden — the SessionStart hook keys off node properties.

### Step 6 — Write file + flag IG

1. **Slug** the title — lowercase, dashes, ≤40 chars.
2. **Filename** — `.planning/handovers/<YYYY-MM-DD>-<NODE-ID>-<slug>.md` (date = today, ISO).
3. **Write** the opener content (everything that would have gone between the `---` markers) to that path.
4. **Citation check** — CUCO does not yet have `scripts/check-handover.sh` (CURLOP-only tooling, optional port). Until installed, multi-session work must include one line printed before the opener block:
   ```
   📋 Citation check skipped — scripts/check-handover.sh not installed in CUCO. Manual review for canonical citations applied.
   ```
   Single-session bug fix may skip with reason as in CURLOP. Skipping silently is FAIL.
5. **Set the doc on the node FIRST:**
   ```bash
   node tools/ig/cuco_scripts_ig.cjs update <node-id> --doc <filename>
   ```
   Then **flag pending** in a SEPARATE call so a partial-write can't leave the flag without a doc:
   ```bash
   node tools/ig/cuco_scripts_ig.cjs update <node-id> --props '{"handover_pending":true,"handover_doc":"<filename>","handover_session":"s<NNN>"}'
   ```
6. **Verify** — `node tools/ig/cuco_scripts_ig.cjs <node-id>` shows `doc:` populated AND the three properties; file exists at the path. Both must hold.

### Step 7 — Output

Print the same opener to terminal between `---` as paste-fallback (in case the hook is bypassed or the user wants to inspect immediately). After the block, print one summary line:
```
📬 Handover written: <path> · IG flagged on <NODE-ID>. Next session's SessionStart hook will surface it.
```

Need to flag concern (priority ambiguous, work shape mixed)? One–two lines BEFORE the block, not inside.
</process>

<success_criteria>
- **Step 0 close-out ran FIRST.** No `handover_pending: true` exists on any IG node OTHER than the one this command just flagged. Verify: `node -e 'const d=JSON.parse(require("fs").readFileSync(".issues.json","utf8")); for (const n of d.nodes||[]) if (n.properties?.handover_pending===true) console.log(n.id);'` → exactly one ID, matching this handover's umbrella node.
- **Each consumed handover doc reconciled in-place.** Top-of-file CONSUMED banner + in-line outcome annotations on every claim it made. Doc still at its original path — no archive moves. Verify by reading the doc itself, not by counting files.
- **Each closed-out IG node has a closure note + cleared flag** — `node tools/ig/cuco_scripts_ig.cjs <prior-id>` shows new `[s<NNN>] consumed —` note (which references the in-place doc reconciliation), `handover_pending` absent/false, `doc_path` unchanged.
- **No archive directory created.** `ls .planning/handovers/archive/` should not exist (or be empty). Filesystem hygiene is NOT what cleanup means — see Step 0 hard rule.
- **Referenced research/spec docs updated** — closures + carry-overs marked at-line, not in a footer.
- **Opener LEADS w/ protocols-first block.** Status + Turn-1 below. Reordered → fail.
- **Turn-1 downstream of protocols.** "After protocols above, [action]" or equiv. Bare "do X" → fail.
- **Canonical sources section present + forward claims inline-cited** for any multi-session work (campaign cut, refactor batch, milestone phase). Single-session bug fix may omit with reason. Citation-check tool not yet installed in CUCO — manual review applied with explicit print line.
- Survey ran first; opener reflects actual state.
- Work shape named explicitly; structure adapted (no force-fit gate-scoreboard / REAPER probes).
- Every reference (hash, IG-ID, path, observable) verifiable.
- Caveats captured.
- ~one screen rendered. Tight beats comprehensive.
- **File written** at `.planning/handovers/<YYYY-MM-DD>-<NODE-ID>-<slug>.md` containing the opener content.
- **IG node flagged** with `handover_pending:true` + `handover_doc:<path>` + `handover_session:s<NNN>` via `cuco_scripts_ig.cjs` CLI.
- **Verified** — `node tools/ig/cuco_scripts_ig.cjs <node-id>` shows the three properties; file exists; SessionStart hook would surface it next session.
- **Terminal block printed** between `---` as paste-fallback, plus the one-line summary `📬 Handover written: ...`.
</success_criteria>
