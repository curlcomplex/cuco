---
description: Mid-session out-of-scope flag — write deferred-work doc, flag IG node, return to current work in one line
---

<objective>
Capture an out-of-scope finding without derailing current work. Writes a brief debug doc, flags the relevant IG node with `handover_pending: true`, then returns to whatever was in flight in **one line**.

Pairs with the `handover-log-nudge.cjs` Stop hook — saying phrases like "out of scope" / "for another session" / "park for later" without invoking this command will block stop.
</objective>

<process>

### Usage

- `/handover-log <NODE-ID>` — flag an existing node
- `/handover-log` (bare) — create a new node first, then flag it

### Step 1 — If bare, create the node

Ask one question: what kind? Most common is `task` for deferred work, `bug` for broken behavior found in passing, `concept` for an idea worth exploring later. Then create:

```bash
node tools/ig/cuco_scripts_ig.cjs create <type> "<title>" \
  --desc "<one-paragraph what + why>" \
  --priority <N>
```

Capture the new ID.

### Step 2 — Write the deferred-work doc

`.planning/handovers/<DATE>-<NODE-ID>-deferred-<slug>.md` — short. Three sections:

1. **Found while:** what current work surfaced this
2. **What:** the deferred thing — be specific enough that future-you doesn't need this conversation
3. **Why deferred:** what it'd take, why now isn't the time

Tight. 5-10 lines is fine.

### Step 3 — Flag the IG node

```bash
node tools/ig/cuco_scripts_ig.cjs update <NODE-ID> --props '{
  "handover_pending": true,
  "handover_doc": ".planning/handovers/<DATE>-<NODE-ID>-deferred-<slug>.md",
  "handover_session": "s<NNN>"
}'
```

### Step 4 — Return to current work in ONE line

Examples:
- "Logged as T-027. Back to the random-walk classifier."
- "Logged as B-012. Back to the keyframe persistence fix."

Do not summarize. Do not re-explain. One line. Resume.

</process>

<success_criteria>
- IG node exists and has `handover_pending: true` + `handover_doc` set
- Deferred-work doc exists at `.planning/handovers/`
- Final response line returns to in-flight work — no fanfare, no recap
</success_criteria>
