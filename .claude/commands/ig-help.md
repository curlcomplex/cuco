---
description: Print the Issue Graph CLI reference
---

Print the Issue Graph reference in this exact format. No additional commentary.

```
=== ISSUE GRAPH (IG) — CLI REFERENCE ===

Binary: node scripts/ig/cuco_scripts_ig.cjs
State:  .issues.json (do NOT edit by hand)

NODE TYPES:
  milestone (M)   feature (F)   subfeature (SF)   future_feature (FF)
  bug (B)         task (T)      knowledge (K)     concept (CON)
  specification (SPEC)

EDGE TYPES:
  part_of (hierarchy, multi-parent allowed)
  blocks  relates_to  causes  affects  same_root_cause  subsumes  revealed_by

READS:
  --stats                        graph statistics
  --type <t> [--status <s>]      filter by type/status
  --children <id>                nodes part_of <id>
  --parents <id>                 what <id> is part_of
  --ready [--next N]             ready=true + status=open
  --search <q>                   search title + description
  --recent N                     last N touched
  --next N                       top N priority
  --blocked                      blocked nodes with chain
  --blocks <id>                  what <id> blocks
  --blocked-by <id>              what blocks <id>
  --edges [--source=<id>] [--target=<id>] [--type=<t>] [--all]
  --board                        ASCII kanban (5 columns)
  --mermaid [blocked|bug|feature|knowledge]
  <id>                           single node detail

WRITES (single op):
  create <type> <title> [--desc <d>|--desc-file <p>|--desc -]
    [--tags a,b,c] [--tag a --tag b ...] [--priority N] [--ready yes]
    [--props '{JSON}'|--props-from-file <p>] [--doc <path>]

  update <id> [--dry-run]
    --status <s> | --note <text> | --note-file <path> | --note -
    --title <t>  | --desc <d>    | --desc-file <path> | --desc -
    --tag <t> (repeatable) | --ready <bool> | --doc <path>
    --type <type> | --priority <n>
    --props '{JSON}' | --props-from-file <path>

  delete <id>
  edge <source> <target> [type]    create edge
  edge --delete <edgeId>           delete edge

WRITES (batch):
  apply <file|-> [--dry-run]       atomic batch ops (JSON array)
    Ops: create | update | delete | edge | edge-delete | reparent
    Use _ref:"$NAME" on creates, "$NAME" on edges to cross-reference
    within a single batch (atomic, validated, ~20× cheaper than loops).

HYGIENE:
  hygiene [--apply]                sweep stale blocks + dupe edges

RICH CONTENT:
  Use --desc-file / --note-file for multi-line, backticks, em-dashes.
  Inline --desc "..." only for one-liners.

DOCUMENT PAIRING:
  Significant nodes pair with .planning/research/<file>.md via
  properties.research_doc. Specifications pair with .planning/specs/
  via properties.doc_path.

WHAT TO LOG:
  Decisions, permanent facts, blockers encountered/resolved.
  NOT implementation traces.
```
