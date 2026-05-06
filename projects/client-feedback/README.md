# ClientFeedback v2 (No-API)

This is a minimal client feedback workflow for REAPER that requires no external services or API keys.

What it does:
- Add timestamped client comments as markers (prefixed with `FB:`)
- Append each comment to `client_feedback.csv` in the project folder
- Rebuild/export the CSV at any time from the project’s markers

## Files
- "ClientFeedback - Add Comment.lua": prompt for name and comment, place a marker, append to CSV
- "ClientFeedback - Export CSV.lua": scan `FB:` markers and rebuild `client_feedback.csv`

## Install
1) Put these Lua files in your REAPER Scripts folder (already here):
   `~/Library/Application Support/REAPER/Scripts/CUCO/ClientFeedback-v2`
2) In REAPER, open: Actions > Show action list…
3) Click: ReaScript > Load, and select both scripts.
4) Assign shortcuts or toolbar buttons as you like.

## Use
- With the edit cursor at the desired location, run:
  - ClientFeedback - Add Comment
    - Enter your name and the comment text.
    - A marker like `FB: [Name] Comment text` is added at the cursor.
    - A CSV row is appended to `client_feedback.csv` in the project folder with:
      project_name, take_name (if available), time_seconds, timecode, user, comment
- To regenerate the CSV from markers (clean, deduped, sorted by time):
  - Run: ClientFeedback - Export CSV

## Notes
- The CSV is stored next to your .rpp project file. If the project is unsaved, it uses the default project path.
- Markers use color cyan by default; adjust in the script if you want.
- Take name is looked up from the active take under the comment time when exporting; during Add it uses the currently selected item’s active take.

## Customization
- Change the CSV filename: search for `client_feedback.csv` in the scripts.
- Change marker prefix or color: edit `marker_name` and `AddProjectMarker2` arguments.
- Add more fields: extend the header and row generation.

