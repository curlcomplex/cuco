---
description: Write end-of-session handover doc to .planning/handovers/ and flag the umbrella IG node
---

<objective>
Hand-off so the next session can resume without re-reading the whole transcript. Writes a tracked, IG-flagged handover doc — not gitignored session state. Step 0 reconciliation is preserved because losing it once is how stale handovers compound.

**Output**: `.planning/handovers/<DATE>-<NODE-ID>-<slug>.md` (tracked).
**Side effect**: umbrella IG node gets `properties.handover_pending: true` + `handover_doc: <path>` + `handover_session: s<NNN>`.
</objective>

<process>

### Step 0 — Reconcile prior handover (mandatory, runs FIRST)

Find any IG node with `properties.handover_pending: true`:

```bash
node scripts/ig/cuco_scripts_ig.cjs --search "" 2>&1 | head  # or query by props
```

If a pending handover exists:

1. **Read its doc end-to-end.** Identify every concrete claim:
   - Turn-1 action — did it run? skipped? redirected?
   - In-progress — what shipped, what's still in-progress, what got dropped
   - Caveats — were they hit, worked around, or proved wrong?
   - Done this session — were any of those reverted or amended?

2. **Append a CONSUMED block to the bottom of the prior doc** before writing the new one:
   ```
   ---
   ## ✅ CONSUMED <ISO-date>
   - Turn-1 outcome: <one-line>
   - Shipped: <commits/files>
   - Carried forward: <items now in new handover>
   - Superseded: <decisions reversed>
   - Caveats hit: <which proved real>
   ```

3. **Clear the prior node's flag**:
   ```bash
   node scripts/ig/cuco_scripts_ig.cjs update <prior-id> --props '{"handover_pending":false}'
   ```

4. **Print close-out summary**:
   ```
   🧹 Close-out: prior handover <prior-id> reconciled — N shipped, M carried, K superseded.
   ```
   First-run: `🧹 Close-out: no prior handover (first run).`

### Step 1 — Identify or create the umbrella IG node

The umbrella node represents the work this handover bridges. Usually a milestone or feature. Examples: M-001, F-002. If no fitting node exists, create one (likely a `task` node) before writing the doc.

### Step 2 — Survey current state

- `git log --oneline -10`
- `git status --short`
- Files touched this session (from conversation context)
- Any in-progress edits or pending decisions
- Current IG snapshot: `node scripts/ig/cuco_scripts_ig.cjs --stats`

### Step 3 — Compose the doc

Write to `.planning/handovers/<DATE>-<NODE-ID>-<slug>.md` with these sections, in order:

1. **Status** — one sentence: where we are. Branch + HEAD short hash.
2. **Read first** — 3–6 files a fresh agent should open, with one-line WHY each. Lead with the most load-bearing.
3. **Done this session** — bullet list. Each line: short description + commit hash if applicable.
4. **In progress** — what we paused mid-way through. Be specific: "the file is half-edited at X" / "the script change is committed but not tested in REAPER yet."
5. **Turn-1 action** — concrete first move when resuming. Phrase as imperative. 2–4 specifics worth verifying.
6. **Caveats** — gotchas worth flagging. Failure modes, surprises from this session, things that LOOK done but aren't tested yet. Skip if clean.

### Step 4 — Flag the umbrella IG node

```bash
node scripts/ig/cuco_scripts_ig.cjs update <NODE-ID> --props '{
  "handover_pending": true,
  "handover_doc": ".planning/handovers/<DATE>-<NODE-ID>-<slug>.md",
  "handover_session": "s<NNN>"
}'
```

### Step 5 — Quality check

- Status anchor names the actual branch + commit
- Every commit hash / file path verifiable (no placeholders)
- Turn-1 is concrete, not "continue working on X"
- "In progress" is honest about what's tested vs untested
- IG node flagged
- Length: ~one screen. Tight beats comprehensive.

</process>

<success_criteria>
- `.planning/handovers/<DATE>-<NODE-ID>-<slug>.md` exists and reflects actual current state
- Umbrella IG node has `handover_pending: true` + `handover_doc` + `handover_session` set
- If a prior handover existed, its node's flag is cleared and CONSUMED block appended to its doc
- Close-out summary printed before composing the new doc
- Every reference (commit / path / decision / IG node ID) traces to something verifiable
</success_criteria>
