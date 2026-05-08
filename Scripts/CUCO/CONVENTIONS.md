# Conventions

## Folder structure

```
projects/<project-name>/        Named projects (kebab-case)
  ├── <user-facing-script>.lua  Title Case With Spaces — shown in REAPER action list
  ├── modules/                  Internal Lua modules (snake_case)
  ├── tests/                    Tests, with tests/README.md
  ├── docs/ or README.md        Project docs
  └── ...

utilities/<domain>/             Single-file scripts grouped by domain
experiments/<name>/             Research/incomplete; not necessarily Lua
archive/<name>/                 Superseded but preserved
```

## Naming

| What | Convention | Example |
|---|---|---|
| Folders | `kebab-case` | `cuco-diff/`, `random-walk/` |
| User-facing scripts | `Title Case With Spaces.lua` | `CUCO Random Walk GUI.lua` |
| Internal modules | `snake_case.lua` | `diff_engine.lua`, `data_store.lua` |
| Test files | `test_<thing>.lua` | `test_tokenization.lua` |

User-facing scripts use spaces because REAPER's action list shows the filename verbatim — readability beats command-line ergonomics here.

## Versioning

- **Live versions** live in the file's `@version` header, NOT the filename.
- Old versions go to `archive/<project>-old/` if kept at all.
- No `v0.7.0` / `v0.8.1` / `v1.4.1` suffixes on filenames in `projects/`.

## Script header

Every user-facing script starts with a [ReaPack](https://reapack.com/)-compatible header:

```lua
--[[
@description Short one-liner shown in REAPER's action list
@author      felixtatic
@version     1.0.0
@about       Multi-line description of what the script does and how to use it.
             Include any setup steps, dependencies, or gotchas.
@license     MIT
]]--
```

This format gives a free upgrade path to publishing via ReaPack later.

## Modules

Project subfolders use `modules/` for internal Lua modules (CUCO-DIFF already follows this). Loaded via:

```lua
local script_path = debug.getinfo(1, 'S').source:match('^@(.+/)') or ''
package.path = script_path .. 'modules/?.lua;' .. package.path
local utils = require('utils')
```

## Tests

- One `tests/` folder per project.
- `tests/README.md` explains how to run them.
- No throwaway scratch files (`debug_*.lua`, `verify_*.lua`, `final_*.lua`) in committed code — those belong in `.gitignore` or get deleted.

## What goes in `archive/`

- Superseded versions (CUCO-OP v1, old Keyframe versions, etc.)
- Scratch/debug files preserved "just in case"
- Anything you'd otherwise be tempted to delete but isn't quite ready

Think of `archive/` as cold storage. If something's actively useful, it belongs in `projects/` or `utilities/`.

## Git

- Branches: `main` for stable, feature branches for work-in-progress.
- Commit messages: short imperative subject line ("Add CSV export to client-feedback"), optional body.
- `.DS_Store`, `*.venv/`, `.vscode/` (root), and other editor/OS detritus are gitignored.
