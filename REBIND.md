# Rebinding REAPER actions after the reorg

REAPER stores absolute paths for action-list entries, toolbar buttons, and shortcuts. Any script you had bound is now broken until you re-add it.

## How to fix a binding

1. Open REAPER → **Actions** → **Show action list...**
2. Find the broken entry (the path will be the **OLD** path below — REAPER may show it greyed out or with a missing-file marker).
3. Right-click the entry → **Remove action**.
4. Click **ReaScript** → **Load...** and pick the file at its **NEW** path.
5. Re-bind any shortcut / toolbar button to the new entry.

REAPER does **not** remember the old shortcut automatically — write down what you had bound before rebinding.

## Old → new path mapping (active scripts)

All paths relative to `~/Library/Application Support/REAPER/Scripts/CUCO/`.

| Old path | New path |
|---|---|
| `CUCO-OP V2/CUCO OP 2.lua` | `projects/curlop/CUCO OP 2.lua` |
| `CUCO-DIFF/CUCO-DIFF.lua` | `projects/cuco-diff/CUCO-DIFF.lua` |
| `ClientFeedback-v2/ClientFeedback - Add Comment.lua` | `projects/client-feedback/ClientFeedback - Add Comment.lua` |
| `ClientFeedback-v2/ClientFeedback - Export CSV.lua` | `projects/client-feedback/ClientFeedback - Export CSV.lua` |
| `Auto Prefix/CUCO Auto Prefix.lua` | `projects/auto-prefix/CUCO Auto Prefix.lua` |
| `Random Walk/API_Test.lua` | `projects/random-walk/API_Test.lua` |
| `Random Walk/CUCO Random Walk (100%).lua` | `projects/random-walk/CUCO Random Walk (100%).lua` |
| `Random Walk/CUCO Random Walk GUI - EXPERIMENTAL.lua` | `projects/random-walk/CUCO Random Walk GUI - EXPERIMENTAL.lua` |
| `Random Walk/CUCO Random Walk GUI.lua` | `projects/random-walk/CUCO Random Walk GUI.lua` |
| `Random Walk/Parameter Scanner.lua` | `projects/random-walk/Parameter Scanner.lua` |
| `AudioSuite+/CUCO Apply track fx to new take for selected items retaining take fx & take envelopes.lua` | `projects/audiosuite-plus/CUCO Apply track fx to new take for selected items retaining take fx & take envelopes.lua` |
| `AudioSuite+/CUCO Audiosuite+.lua` | `projects/audiosuite-plus/CUCO Audiosuite+.lua` |
| `Keyframe/CUCO_Keyframe_v0_5_0.lua` | `projects/keyframe/CUCO_Keyframe_v0_5_0.lua` |
| `Tidal Notation/CUCO Tidal Notation 0.8.1.lua` | `projects/tidal-notation/CUCO Tidal Notation 0.8.1.lua` |
| `MIDI/CUCO Tidal v1.4.1.lua` | `projects/cuco-tidal/CUCO Tidal v1.4.1.lua` |
| `Editing/Create Razor Edit Area from Selected Items.lua` | `utilities/editing/Create Razor Edit Area from Selected Items.lua` |
| `Editing/Duplicate Time Selection & Insert (Ripple All).lua` | `utilities/editing/Duplicate Time Selection & Insert (Ripple All).lua` |
| `Editing/Select all Empty Items.lua` | `utilities/editing/Select all Empty Items.lua` |
| `Editing/Select item under mouse and move edit cursor to start of item.lua` | `utilities/editing/Select item under mouse and move edit cursor to start of item.lua` |
| `Item/Glue contiguous selected items with matching source file.lua` | `utilities/items/Glue contiguous selected items with matching source file.lua` |
| `Item/MouseItemSelect_CLEAN.lua` | `utilities/items/MouseItemSelect_CLEAN.lua` |
| `Item/Select item under mouse and move edit cursor to start of item.lua` | `utilities/items/Select item under mouse and move edit cursor to start of item.lua` |
| `Item/SelectItemUnderMouse.lua` | `utilities/items/SelectItemUnderMouse.lua` |
| `Item/test_simple.lua` | `utilities/items/test_simple.lua` |
| `Organisation/CUCO Hide all selected tracks without items or with only muted items.lua` | `utilities/organisation/CUCO Hide all selected tracks without items or with only muted items.lua` |
| `Organisation/CUCO Move selected items to new tracks aligned vertically to first item.lua` | `utilities/organisation/CUCO Move selected items to new tracks aligned vertically to first item.lua` |
| `Organisation/CUCO Reorder tracks in order of first occuring item.lua` | `utilities/organisation/CUCO Reorder tracks in order of first occuring item.lua` |

## Folders moved to archive

These projects' user-facing scripts were superseded — re-bind only if you actively use them:

| Old path | Archive location |
|---|---|
| `CUCO-OP/CUCO OP.lua` | `archive/cuco-op-v1/CUCO OP.lua` (replaced by `projects/curlop/CUCO OP 2.lua`) |
| `CUCO-Stacks/CUCO Stacks.lua` | `archive/cuco-stacks/CUCO Stacks.lua` |
| `CUCO-Client-Feedback-Organiser/CUCO Client Feedback Organiser.lua` | `archive/cuco-client-feedback-organiser/...` (replaced by `projects/client-feedback/`) |
| `Modified/Script- Play Selected Item(s).lua` | `archive/modified/Script- Play Selected Item(s).lua` |
| `Modified/Script- Solo Play Selected Item(s) from edit cursorlua.lua` | `archive/modified/...` |
| `TESTING/Move looped item source right by 16th.lua` | `archive/testing/...` |
| `TESTING/Unbypass FX slots based on midi item take name.lua` | `archive/testing/...` |

## Older versions moved to archive

- `Keyframe/CUCO Keyframe 0.{0..4}.lua` → `archive/keyframe-old/`
- `Tidal Notation/CUCO Tidal Notation 0.{1,7,8}.0.lua` → `archive/tidal-notation-old/`
- `MIDI/CUCO Tidal v1.4.0.lua` and `MIDI/CUCO Tidal.lua` → `archive/cuco-tidal-old/`

If a binding stops working and the script is one of these, either rebind to the latest version in `projects/` or recover the older file from `archive/`.
