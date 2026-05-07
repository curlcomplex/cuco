---
description: Re-read working tree from scratch ignoring conversation context — report observed-vs-claimed
---

<objective>
Counteract context decay ("rotting in realtime"). Drop everything you think you know from the conversation, re-survey the working tree from cold, and report what you actually see vs what conversation claims.
</objective>

<process>

### Step 1 — Forget the conversation

Pretend this is your first turn. The prior turns may be wrong, stale, or hallucinated. Treat them as untrusted input.

### Step 2 — Cold survey

Run, in parallel:

- `git status --short`
- `git log --oneline -10`
- `git diff --stat HEAD`
- `node scripts/ig/cuco_scripts_ig.cjs --stats`
- `node scripts/ig/cuco_scripts_ig.cjs --ready`
- `ls .planning/handovers/ | tail -3`

Read whatever the snapshot suggests is load-bearing. Skim the newest handover.

### Step 3 — Report observed vs claimed

Three columns. Be specific.

```
OBSERVED                    | CLAIMED IN CONVERSATION       | DELTA
---                         | ---                           | ---
main @ 8ad12d1              | "we just shipped X"           | OK / no commit yet / different commit
T-001 still open + ready    | "T-001 done"                  | MISMATCH
.planning/specs/ empty      | "we wrote SPEC-001"           | MISMATCH (only IG node, no doc)
```

If everything matches: say so plainly. "Working tree matches claims; no drift detected."

### Step 4 — Recommend

One paragraph. What's actually true, what was probably context decay, what to do next.

</process>

<success_criteria>
- Cold-survey commands run BEFORE any reasoning
- Report cites file paths, commit hashes, IG node IDs — not paraphrases
- Mismatches surface even if they're embarrassing
- Recommendation is concrete (a next action, not "let's discuss")
</success_criteria>
