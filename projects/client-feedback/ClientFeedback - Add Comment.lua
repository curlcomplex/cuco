-- ClientFeedback - Add Comment.lua
-- Minimal, no-API client feedback capture for REAPER
-- Places a marker at the edit cursor and appends a CSV row in the project directory.
-- CSV columns: project_name, take_name, time_seconds, timecode, user, comment
-- Markers will be named like: FB: [user] comment

-- Helper: format seconds to HH:MM:SS.mmm based on project timebase
local function format_timecode(time)
  local hours = math.floor(time / 3600)
  time = time - hours * 3600
  local minutes = math.floor(time / 60)
  local seconds = time - minutes * 60
  return string.format("%02d:%02d:%06.3f", hours, minutes, seconds)
end

-- Helper: CSV escaping
local function csv_escape(s)
  if s == nil then return "" end
  s = tostring(s)
  if s:find('[,\"\n]') then
    s = '"' .. s:gsub('"', '""') .. '"'
  end
  return s
end

local function get_project_info()
  local _, proj_path = reaper.EnumProjects(-1, "")
  local proj_name = reaper.GetProjectName(0, "", 512)
  local proj_dir = proj_path:match("^(.*)[/\\]") or reaper.GetProjectPathEx(0, "")
  if proj_dir == nil or proj_dir == "" then
    proj_dir = reaper.GetProjectPathEx(0, "")
  end
  return proj_name, proj_dir
end

local function get_active_take_name()
  local item = reaper.GetSelectedMediaItem(0, 0)
  if not item then return "" end
  local take = reaper.GetActiveTake(item)
  if not take then return "" end
  local _, take_name = reaper.GetSetMediaItemTakeInfo_String(take, "P_NAME", "", false)
  return take_name or ""
end

local function prompt_user()
  local retval, inputs = reaper.GetUserInputs("Add Client Comment", 2, "Your name,Comment", ",")
  if not retval then return nil end
  local name, comment = inputs:match("^(.-),(.*)$")
  name = name or ""
  comment = comment or ""
  return name, comment
end

local function append_csv_row(path, row)
  local file = io.open(path, "a")
  if not file then return false, "Could not open CSV for appending: " .. tostring(path) end
  file:write(table.concat(row, ",") .. "\n")
  file:close()
  return true
end

local function ensure_csv_with_header(path)
  local f = io.open(path, "r")
  if f then f:close(); return end
  local header = table.concat({
    "project_name","take_name","time_seconds","timecode","user","comment"
  }, ",")
  local wf = io.open(path, "w")
  if wf then wf:write(header .. "\n"); wf:close() end
end

local function main()
  reaper.Undo_BeginBlock()

  local name, comment = prompt_user()
  if not name then return end

  local time = reaper.GetCursorPosition()
  local timecode = format_timecode(time)
  local take_name = get_active_take_name()
  local proj_name, proj_dir = get_project_info()

  -- Create marker
  local marker_name = string.format("FB: [%s] %s", name ~= "" and name or "anon", comment)
  reaper.AddProjectMarker2(0, false, time, 0, marker_name, -1, 0x00AAFF)

  -- CSV path in project dir
  local csv_path = proj_dir .. "/client_feedback.csv"
  ensure_csv_with_header(csv_path)

  local row = {
    csv_escape(proj_name),
    csv_escape(take_name),
    string.format("%.3f", time),
    csv_escape(timecode),
    csv_escape(name),
    csv_escape(comment)
  }

  local ok, err = append_csv_row(csv_path, row)
  if not ok then
    reaper.ShowMessageBox("Failed to append to CSV: " .. err, "ClientFeedback", 0)
  end

  reaper.Undo_EndBlock("ClientFeedback: Add Comment", -1)
end

reaper.defer(main)

