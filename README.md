# CUCO

Felix Godden's REAPER scripts collection. Mix of named projects, small utility scripts, research experiments, and archived/superseded work.

## Layout

```
projects/        Named systems with their own architecture
utilities/       Small one-shot scripts grouped by domain
experiments/     Research / incomplete / non-Lua tooling
archive/         Superseded but kept for reference
```

## Active projects

| Project | What it does |
|---|---|
| `projects/curlop/` | DSL → MIDI IDE (was CUCO-OP V2; now spinning out as standalone app) |
| `projects/cuco-diff/` | Session time logging + `.rpp` diffing for client transparency |
| `projects/client-feedback/` | `FB:` markers → CSV, no API needed |
| `projects/auto-prefix/` | Folder/leaf track auto-naming with `>chain` prefixes |
| `projects/keyframe/` | Snapshot/recall FX param states with envelope writing |
| `projects/random-walk/` | Drunk-walk envelopes across all FX params over time selection |
| `projects/tidal-notation/` | TidalCycles-style pattern notation → MIDI |
| `projects/cuco-tidal/` | Earlier Tidal-style script (separate lineage from `tidal-notation`) |
| `projects/audiosuite-plus/` | Apply track FX as new take, preserving envelopes |

## Utilities

| Folder | Contents |
|---|---|
| `utilities/editing/` | Razor edits, ripple duplicate, select empty items |
| `utilities/items/` | Mouse-based item selection / cursor moves / glue |
| `utilities/organisation/` | Track reordering, hiding, vertical alignment |

## Experiments

| Folder | Contents |
|---|---|
| `experiments/sound-semantic-parser-panns/` | PANNs-based audio tagging (Python heavy) |
| `experiments/sound-semantic-parser-whisper-at/` | Whisper-AT alternative |
| `experiments/additive-spear/` | SPEAR data → gmem |
| `experiments/metadata-workflow/` | Metadata match criteria script |

## Conventions

See [CONVENTIONS.md](CONVENTIONS.md).

## Rebinding REAPER actions after the reorg

See [REBIND.md](REBIND.md) — every script's old → new path mapping for actions/toolbars.
