# ReaSessionDiff Automated Test Session Generation Spec

## Project Purpose
Create deterministic Reaper `.rpp` session pairs for testing the Lua diff engine.  
Each test defines a minimal “Session A” (baseline) and “Session B” (modified) so that the diff engine can verify its output against a known, expected result.  
The tests are automatically generated, stored, and validated.

---

## 1. Directory Structure

```
/tests/
   /cases/
       /001_add_track/
           Test_A.rpp
           Test_B.rpp
           manifest.json
       /002_remove_track/
           ...
   /lib/
       generator.lua
       templates.lua
   plugin_list.json
   run_tests.lua
```

### File Roles
- **generator.lua** – Builds `.rpp` sessions from Lua tables.  
- **templates.lua** – Stores reusable RPP blocks (base session, track, FX, item).  
- **plugin_list.json** – Static list of FX/plugin names available on the system.  
- **manifest.json** – Contains expected diff result and metadata for each test.  
- **run_tests.lua** – Executes diff engine, compares output to manifests, reports pass/fail.

---

## 2. Naming Convention

Each test case folder:
```
/tests/cases/{index}_{scenario_name}/
```

Example:
```
/tests/cases/003_add_fx/
```

Within each:
```
Test_A.rpp    → baseline session  
Test_B.rpp    → modified session  
manifest.json → expected_diff, categories, granularity
```

---

## 3. Session Generation API

```lua
function CreateSession(name, opts) end
function AddTrack(session, trackName, fxList, items) end
function AddFX(track, fxName) end
function SaveSession(session, path) end
```

All functions operate on Lua tables representing RPP node hierarchies.  
The output must be valid REAPER `.rpp` syntax.

---

## 4. Base Template (Minimal Session)

```rpp
<REAPER_PROJECT 0.1 "6.50/OSX64" 0
  RIPPLE 0
  AUTOXFADE 1
  <TEMPOENVEX
    ACT 0
    VIS 1
  >
>
```

---

## 5. Test Definition Table

```lua
local tests = {
  { id = "001", name = "add_track",
    A = { tracks = { "Drums" } },
    B = { tracks = { "Drums", "Bass" } },
    expect = { "Added track 'Bass'" }
  },
  { id = "002", name = "remove_track",
    A = { tracks = { "Drums", "Bass" } },
    B = { tracks = { "Drums" } },
    expect = { "Removed track 'Bass'" }
  },
  { id = "003", name = "add_fx",
    A = { tracks = { "Vocal" } },
    B = { tracks = { "Vocal" }, fx = { "ReaComp" } },
    expect = { "Added FX 'ReaComp' to track 'Vocal'" }
  }
}
```

---

## 6. Manifest Format

```json
{
  "id": "001",
  "scenario": "Add Track",
  "expected_diff": ["Added track 'Bass'"],
  "granularity": "summary",
  "category": "structure"
}
```

---

## 7. Plugin Reference List

```json
[
  "ReaEQ",
  "ReaComp",
  "ValhallaRoom",
  "FabFilter Pro-Q 3"
]
```

---

## 8. Test Case Scenarios

### Structural
1. Add track  
2. Remove track  
3. Rename track  
4. Reorder tracks  
5. Create folder hierarchy  

### Media Items
6. Add item  
7. Remove item  
8. Move item  
9. Rename item  
10. Change item length  
11. Switch take  

### FX / Plugin
12. Add FX  
13. Remove FX  
14. Reorder FX  
15. Change FX parameter  
16. Apply preset  

### Automation
17. Add envelope  
18. Modify envelope  
19. Remove envelope  

### Project Settings
20. Change tempo  
21. Change time signature  
22. Change render settings  
23. Add project notes  

### Cosmetic
24. Change track color  
25. Change icon  
26. Toggle visibility  

### Edge / Mixed
27. Identical sessions  
28. Large session (100 tracks)  
29. Track deletion + FX change  
30. Missing media reference  

---

## 9. Validation Logic

```lua
for test in tests do
  local a = ParseRPP(test.A)
  local b = ParseRPP(test.B)
  local diff = GenerateDiff(a, b)
  CompareToManifest(test.id, diff)
end
```

---

## 10. Edge-Case Generation

- Randomized GUID assignment per track  
- Deterministic naming for repeatable diffs  
- Optional whitespace reordering noise injection  
- Automatic cleanup of temp directories

---

## 11. Execution

### Terminal
```
reaper -batch run_tests.lua
```

### VS Code
```json
"command": "lua ./tests/run_tests.lua"
```

### CI
```yaml
- name: Run ReaSessionDiff Tests
  run: lua tests/run_tests.lua
```

---

## 12. Success Criteria

- All `.rpp` files open cleanly in REAPER  
- Diff results match manifests exactly  
- Log shows 100% pass rate  
- Copilot can add new tests without breaking structure  

---

## 13. Future Extension

- Generate mixed tests automatically  
- Add schema validation for manifests  
- Integrate watcher time estimates  
- Optional auto plugin list from ReaScript API  
