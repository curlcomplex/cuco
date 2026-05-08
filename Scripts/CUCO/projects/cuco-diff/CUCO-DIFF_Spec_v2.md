# CUCO-DIFF – Implementation Specification (v2)

## Overview
A Lua ReaScript that logs active session work time, compares `.rpp` project versions, and generates human-readable summaries of what changed.  
The goal: an auditable, readable record of what work was done and how long it took, suitable for client transparency and internal archiving.

---

## Core Architecture
The system is composed of three main modules and one shared data layer.

| Module | Role |
|---------|------|
| `watcher.lua` | Tracks active user time inside Reaper sessions. |
| `diff_engine.lua` | Compares `.rpp` files and generates categorized change events. |
| `ui_main.lua` | Provides ReaImGui interface for viewing, editing, and exporting data. |
| `data_store.lua` | Handles saving/loading state via Reaper’s ExtState and JSON encoding. |

Each module can run independently and communicate via shared tables or serialized JSON.

---

## 1. Watcher Module

**Purpose:** track actual time spent working, excluding idle/AFK periods.

**Key Behaviors:**
- Starts automatically when a project loads.
- Every N seconds (configurable, e.g. 10 s):
  - Checks last mouse/keyboard activity (`reaper.GetLastMouseMoveTime()`, etc).
  - If user active → add elapsed time to current session’s total.
- On project close or save → flush totals to extstate:
  ```lua
  reaper.SetExtState("CUCO-DIFF", project_path, json.encode({total_time=seconds, last_save=os.time()}), true)
  ```

**Fields to track:**
```lua
{
  project_path = string,
  total_time   = number,  -- in seconds
  last_active  = number,  -- timestamp
  afk_threshold = 60,     -- seconds of inactivity before pause
}
```

---

## 2. Diff Engine Module

**Purpose:** compare two `.rpp` session files, identify differences, and produce categorized, human-readable summaries.

**Workflow:**
1. Use the community RPP Parser to load `.rpp` files into Lua tables.
2. Compare only *immediate predecessor* version pairs (sorted by version index).
3. Detect structural and semantic differences:

   | Category | Detection |
   |-----------|------------|
   | Tracks | Added, removed, renamed `<TRACK>` chunks |
   | Media Items | Added/removed `<ITEM>` nodes |
   | FX | Changes inside `<FXCHAIN>` chunks |
   | Automation | Envelope count or point data change |
   | Project Settings | Tempo/time sig/render fields |
   | Notes | `<NOTES>` chunk diff |
   | Housekeeping | Color/icon visibility changes |

4. Group low-level differences into semantic “events.”

**Example event:**
```lua
{
  type        = "FX_ADD",
  track       = "Vox Lead",
  fx_name     = "LA-2A (UAD)",
  category    = "fx_plugins",
  action      = "added",
  description = "Inserted LA-2A compressor on Vox Lead"
}
```

**Output format for a version pair:**
```lua
{
  from_version = "V02",
  to_version   = "V03",
  summary      = "Added 2 plugins; edited 4 clips",
  events       = { event1, event2, ... },
  hash         = "sha1 of new file",
  timestamp    = os.time()
}
```

**Performance guidance:**
- Parse, diff, summarize, and then discard raw node data.
- Only store semantic events.
- Use cached hashes to skip re-diffs on unchanged files.

---

## 3. Data Store Module

**Purpose:** provide a thin wrapper for saving and retrieving structured data.

**Functions:**
```lua
SaveProjectData(project_id, data_table)
LoadProjectData(project_id)
GetAllProjectData()
ClearProjectData(project_id)
```

**Implementation Details:**
- Use `reaper.SetExtState` / `reaper.GetExtState` with persistent flag `true`.
- Encode data as JSON (using a lightweight library).
- Each key corresponds to a base project folder or deliverable group.

---

## 4. UI Module (ReaImGui)

**Purpose:** central control panel for user interaction.

**Layout:**
- **Header:** project folder selector + “Scan” / “Rebuild Diffs” buttons.
- **Main Table:**  
  | Deliverable | Version | Last Modified | Active Time | Summary |
  |--------------|----------|----------------|--------------|----------|
- Expandable rows show detailed diffs per version.
- Sidebar / menu:
  - “Detail Level” selector (Summary / Detailed / Full Audit).
  - “Export CSV” button.
  - “Manual Rebuild All Diffs.”

**Behaviors:**
- On load, scans folder for `.rpp` files.
- Groups by base name, sorts by version index.
- Loads extstate data (watcher + diff summaries).
- Displays computed stats in a sortable, scrollable table.
- Export to CSV via standard file dialog (`reaper.JS_Dialog_BrowseForSaveFile`).

---

## 5. File & Version Detection

**Naming Convention:**
```
<ProjectName>_V01.rpp
<ProjectName>_V02.rpp
<ProjectName>_V03.rpp
```

**Detection Logic:**
- Regex match `_V%d+` at end of filename (before `.rpp`).
- Base name before that is used as “deliverable” group ID.
- Within each group, sort versions numerically.

---

## 6. Auto-Scan and Manual Update

**Auto-Scan:**
- Runs on UI open.
- For each project file:
  - Compare file hash with stored hash.
  - If new or changed → run diff engine, update extstate.

**Manual Update:**
- Button: *“Rebuild All Diffs.”*
- Re-runs diffs on all detected version pairs.
- Overwrites cached data with new summaries.

---

## 7. CSV Export Specification

**Columns:**
| Deliverable | Version | Date Modified | Active Time (hh:mm:ss) | Changes Summary | Detail Level (if exported full) |

**Implementation:**
- Generated directly from current UI data.
- Saved using Reaper’s file dialog.
- Encoded UTF-8, comma-separated.

---

## 8. Error Handling & Safeguards
- Skip unreadable or malformed `.rpp` files gracefully.
- Cap stored event count per diff (e.g. 2000) to prevent runaway logs.
- Always back up extstate data before manual rebuild.

---

## 9. Optional Enhancements
- Add search/filter bar in UI.
- Add “show only changed deliverables.”
- Implement color-coded diff severity (minor/major).

---

## 10. Handling Sessions Without Watcher Data

**Goal:** Estimate active work time for sessions that predate the watcher or where watcher data is missing.  

**Logic Flow:**

1. **Check for Watcher Record**
   - When scanning a project file, look up extstate or sidecar entry.  
   - If found → use stored active time as normal.  

2. **If Missing: Fallback to Backup Folder Analysis**
   - Locate Reaper’s automatic backup folder (`/Backups` or user-defined path).  
   - Filter backups matching the same session base name (`Project_V03_YYYYMMDD_HHMM.rpp-bak`).  
   - Sort by timestamp.  
   - Identify *contiguous clusters* of backups spaced ≤ N minutes apart (default = 2).  
     - Each cluster ≈ a working session.  
     - Duration = time between first and last backup in cluster.  
   - Sum durations of all clusters for that file.  
   - Store this as **estimated active time** with a confidence flag.

3. **Store Result**
   ```lua
   {
     project_path  = "/Projects/Ep05/Project_V03.rpp",
     active_time   = 8640,        -- seconds
     source        = "backup_estimate",  -- or "watcher"
     confidence    = 0.7
   }
   ```
   - `confidence` helps flag estimates versus measured time in UI/CSV.

4. **Display in UI**
   - Show estimated times in italic or gray text with tooltip:  
     > “Estimated from 18 backups between 14:22 – 15:35.”  
   - Option to *“Convert to watcher record”* once a file is opened and watcher starts logging.

5. **Rebuild Logic**
   - On manual “Rebuild Diffs,” also rerun the backup scan for any files still missing watcher data.  
   - If watcher data later appears, it overwrites the estimate.

**Implementation Notes**
- Use Reaper’s API to fetch the project’s backup directory:  
  `reaper.GetProjectPath("")` → append `/Backups` or read from user prefs.  
- Parse timestamps from filenames; no need to open the `.rpp-bak` files.  
- Backup frequency assumption (1 per minute when edited) can be user-configurable in the script settings.  
- Keep this fallback lightweight; it’s for context, not billing precision.  

---

## Code Organization
```
CUCO-DIFF/
│
├── watcher.lua
├── diff_engine.lua
├── data_store.lua
├── ui_main.lua
├── utils.lua
└── CUCO-DIFF.lua
```

---

## General Implementation Principles
- Keep all state tables small and serializable.
- Never diff in real time — only on command or file change.
- Avoid assumptions about user naming; allow manual regrouping.
- Write descriptive logs for debugging, not prints to console.
- Use small helper functions and predictable naming (`GetProjectFiles`, `ComputeDiffs`, `RenderTableRow`, etc).

---
