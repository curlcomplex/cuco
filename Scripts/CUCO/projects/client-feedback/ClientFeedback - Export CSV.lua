-- ClientFeedback - Export CSV.lua
-- Rebuilds client_feedback.csv from FB markers in the project.
-- This is useful if you moved markers or want a clean CSV without duplicates.

local function format_timecode(time)
  local hours = math.floor(time / 3600)
  time = time - hours * 3600
  local minutes = math.floor(time / 60)
  local seconds = time - minutes * 60
  return string.format("%02d:%02d:%06.3f", hours, minutes, seconds)
end

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

local function get_take_name_at_time(pos)
  -- Find first item under cursor at pos and get active take name
  local track_count = reaper.CountTracks(0)
  for t = 0, track_count - 1 do
    local track = reaper.GetTrack(0, t)
    local item_count = reaper.CountTrackMediaItems(track)
    for i = 0, item_count - 1 do
      local item = reaper.GetTrackMediaItem(track, i)
      local item_pos = reaper.GetMediaItemInfo_Value(item, "D_POSITION")
      local item_len = reaper.GetMediaItemInfo_Value(item, "D_LENGTH")
      if pos >= item_pos and pos <= item_pos + item_len then
        local take = reaper.GetActiveTake(item)
        if take then
          local _, take_name = reaper.GetSetMediaItemTakeInfo_String(take, "P_NAME", "", false)
          return take_name or ""
        end
      end
    end
  end
  return ""
end

local function main()
  reaper.Undo_BeginBlock()

  local proj_name, proj_dir = get_project_info()
  local csv_path = proj_dir .. "/client_feedback.csv"
  local header = table.concat({
    "project_name","take_name","time_seconds","timecode","user","comment"
  }, ",")

  local markers = {}
  local retval, num_markers, num_regions = reaper.CountProjectMarkers(0)
  if retval ~= 1 then num_markers = 0 end

  for i = 0, num_markers + num_regions - 1 do
    local rv, isrgn, pos, rgnend, name = reaper.EnumProjectMarkers(i)
    if rv and not isrgn and name and name:sub(1, 3) == "FB:" then
      -- parse name: FB: [user] comment
      local user, comment = name:match("^FB:%s*%[(.-)%]%s*(.*)$")
      user = user or ""
      comment = comment or name
      table.insert(markers, { pos = pos, user = user, comment = comment })
    end
  end

  table.sort(markers, function(a,b) return a.pos < b.pos end)

  local f = io.open(csv_path, "w")
  if not f then
    reaper.ShowMessageBox("Failed to write CSV: " .. csv_path, "ClientFeedback", 0)
    reaper.Undo_EndBlock("ClientFeedback: Export CSV", -1)
    return
  end
  f:write(header .. "\n")

  for _, m in ipairs(markers) do
    local tc = format_timecode(m.pos)
    local take_name = get_take_name_at_time(m.pos)
    local row = {
      csv_escape(proj_name),
      csv_escape(take_name),
      string.format("%.3f", m.pos),
      csv_escape(tc),
      csv_escape(m.user),
      csv_escape(m.comment),
    }
    f:write(table.concat(row, ",") .. "\n")
  end
  f:close()

  reaper.Undo_EndBlock("ClientFeedback: Export CSV", -1)
end

reaper.defer(main)

