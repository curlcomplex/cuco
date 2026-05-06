# CUCO-DIFF

CUCO-DIFF is a ReaScript suite to log active Reaper session time, diff .rpp project versions and generate human-readable summaries for auditing and client transparency.

## Files

- `CUCO-DIFF.lua` - Main entrypoint (loads modules from the `modules/` subfolder)
- `modules/`
  - `watcher.lua` - Tracks active session time
  - `diff_engine.lua` - Compares .rpp files and produces semantic events
  - `data_store.lua` - Wrapper for Reaper ExtState persistence
  - `ui_main.lua` - ReaImGui interface skeleton
  - `utils.lua` - Helper utilities
  - `json_wrapper.lua` - JSON encode/decode wrapper
  - `demo.lua` (or `demotool.lua`) - Demo/test module

## Quick Start (development outside Reaper)

1. From a Lua-capable environment, run the demo:

```bash
cd "$(pwd)"
lua modules/demo.lua
```

2. For full functionality, install the script in Reaper's Scripts folder and run from Reaper.

## Notes for Developers

- The code uses `reaper.*` APIs when running inside Reaper. Outside Reaper, modules fallback to local file operations.
- To enable JSON functionality, install either `cjson` or `dkjson` for Lua.

## Next Steps

- Implement RPP parser integration and detailed diffing logic in `diff_engine.lua`.
- Implement Reaper defer loop and activity detection in `watcher.lua`.
- Implement ReaImGui UI in `ui_main.lua` and wire buttons to scanning/diffing functions.

## Developer Notes

- All modules are located in the `modules/` subfolder; ensure require paths are updated accordingly.
- When running outside Reaper, fallback logic is provided. In Reaper, the native `reaper.*` API will be used.
- To enable full JSON functionality, install either `cjson` or `dkjson` for Lua.
- Future enhancements: integrate a robust RPP parser and expand ReaImGui UI features.
