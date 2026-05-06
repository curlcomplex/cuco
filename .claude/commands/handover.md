---
description: Compose handover doc for next session — reconciles prior handover (Step 0) then writes fresh one at .session/HANDOVER.md
---

<objective>
Hand-off so the next session can resume without re-reading the whole transcript. The CUCO scale is small (one developer, no IG, no specs) so this is intentionally lighter than the curlop equivalent — but the **Step 0 reconciliation rule is preserved** because losing it once is how stale handovers compound.

**Output:** `.session/HANDOVER.md` (gitignored — session state, not project content). Single live file overwritten each invocation. The PRIOR contents must be reconciled, not discarded.
</objective>

<process>

### Step 0 — Reconcile prior handover (mandatory, runs FIRST)

If `.session/HANDOVER.md` does NOT exist, skip to Step 1. (First-run case — nothing to reconcile.)

If it does exist:

1. **Read it end-to-end.** Identify every concrete claim:
   - "Turn-1 action" — did it run? skipped? redirected?
   - "In progress" — what shipped, what's still in-progress, what got dropped
   - "Caveats" — were they hit, worked around, or proved wrong?
   - "Done this session" — were any of those reverted or amended?

2. **Append a CONSUMED block to the bottom of the existing doc** before overwriting:
   ```
   ---
   ## ✅ CONSUMED <ISO-date>
   - Turn-1 outcome: <one-line>
   - Shipped: <commits/files>
   - Carried forward: <items now in new handover>
   - Superseded: <decisions reversed>
   - Caveats hit: <which proved real>
   ```
   Then move the consumed file to `.session/archive/<date>-handover.md` so prior outcomes stay readable but don't clutter the live state.

3. **Print close-out summary** before composing the new doc:
   ```
   🧹 Close-out: prior handover reconciled — N shipped, M carried, K superseded.
                 Archived to .session/archive/<date>-handover.md
   ```
   First-run: print `🧹 Close-out: no prior handover (first run).`

### Step 1 — Survey current state (parallel reads)

- `git log --oneline -10`
- `git status --short`
- Files touched this session (from conversation context — list them)
- Any in-progress edits or pending decisions

### Step 2 — Compose

Write `.session/HANDOVER.md` with these sections, in order:

1. **Status** — one sentence: where we are. Branch + HEAD short hash. e.g. "Keyframe v0.6.0 polished + persistence; REAPER MCP installed pending bridge-load. main @ 1292e94."

2. **Read first** — 3–6 files a fresh agent should open, with one-line WHY each. Lead with the most load-bearing.

3. **Done this session** — bullet list. Each line: short description + commit hash if applicable.

4. **In progress** — what we paused mid-way through. Be specific: "the file is half-edited at X" / "the script change is committed but not tested in REAPER yet."

5. **Turn-1 action** — concrete first move when resuming. Phrase as imperative ("Reload Keyframe in REAPER, click Capture, verify..."). 2–4 specifics worth verifying.

6. **Caveats** — gotchas worth flagging. Failure modes, surprises from this session, things that LOOK done but aren't tested yet. Skip if clean.

### Step 3 — Quality check

- Status anchor names the actual branch + commit
- Every commit hash / file path verifiable (no placeholders)
- Turn-1 is concrete, not "continue working on X"
- "In progress" is honest about what's tested vs untested
- Length: ~one screen. Tight beats comprehensive.

</process>

<success_criteria>
- `.session/HANDOVER.md` exists and reflects the actual current state
- If a prior handover existed, it's been moved to `.session/archive/` with a CONSUMED block appended
- Close-out summary printed before the new doc
- Every reference (commit / path / decision) traces to something verifiable
</success_criteria>
