---
description: Park a decision — write a parked-decision doc, create concept IG node, return to current work in one line
---

<objective>
Capture an unresolved decision (architecture choice, design tradeoff, design hypothesis) without committing to it. Becomes a `concept` IG node + companion doc in `.planning/parked/`. Returns to current work in **one line** afterward.
</objective>

<process>

### Step 1 — Write the parked-decision doc

`.planning/parked/<DATE>-<slug>.md`. Sections:

1. **Decision needed** — phrase as a question
2. **Options on the table** — 2–4 options, one paragraph each, with the tradeoff that distinguishes them
3. **What we'd need to know to decide** — what evidence / experience / spike would unlock the choice
4. **Why parked** — current constraint / blocker / not-the-time

Tight. Half a screen.

### Step 2 — Create the concept IG node

```bash
node tools/ig/cuco_scripts_ig.cjs create concept "<one-line title>" \
  --desc-file .planning/parked/<DATE>-<slug>.md \
  --doc .planning/parked/<DATE>-<slug>.md \
  --priority 4
```

If the parked decision relates to an existing feature, edge it:

```bash
node tools/ig/cuco_scripts_ig.cjs edge CON-NNN F-NNN relates_to
```

### Step 3 — Return to current work in ONE line

Examples:
- "Parked as CON-007. Back to the random-walk distribution polish."
- "Parked as CON-008, related to F-002. Back to the chain-on-takes refactor."

No summary. No recap. One line. Resume.

</process>

<success_criteria>
- Parked-decision doc exists at `.planning/parked/<DATE>-<slug>.md`
- Concept IG node created with `doc_path` pointing at it
- If relevant, `relates_to` edge created
- Final line returns to current work — no fanfare
</success_criteria>
