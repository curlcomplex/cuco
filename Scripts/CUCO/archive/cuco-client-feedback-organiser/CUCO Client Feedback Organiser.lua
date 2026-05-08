--[[
CSV Feedback Table for REAPER (Each import = visible track at top, with take FX)
- Color buttons (no text): mute toggle (red=active, green=muted)
- Table includes picture version column (from track name, without @)
- Each CSV imports to its own visible track '@[filename]' (at top)
- Take FX is always applied to each new MIDI item's take via your supplied command ID
]]

-----------------------------------------------------------
-- GLOBALS & UTILS
-----------------------------------------------------------

local ctx = reaper.ImGui_CreateContext("CSV to MIDI & Live Notes")
local DEFAULT_LENGTH_SEC = 4
local START_OFFSET_SEC   = 2

notesData = {}
itemRefs = {}
itemStates = {}
itemTrackNames = {}

-- FX to apply to each new MIDI item take (from user)
local fxCmd = reaper.NamedCommandLookup("_FX8f9af1da5b41a4072736cc412a894bd1b1cabfa0")

-- Utility: Trim whitespace
local function trim(s)
  if not s then return "" end
  return s:match("^%s*(.-)%s*$")
end

-- Utility: Parse a CSV line (handles quoted fields)
local function parseCSVLine(line)
  local res, pos = {}, 1
  while pos <= #line do
    if line:sub(pos,pos) == '"' then
      local txt = ""; pos = pos + 1
      while pos <= #line do
        local c = line:sub(pos,pos)
        if c == '"' then
          if line:sub(pos+1,pos+1) == '"' then txt = txt..'"'; pos = pos+2
          else pos = pos+1; break end
        else txt = txt..c; pos = pos+1 end
      end
      table.insert(res, txt)
      if line:sub(pos,pos) == ',' then pos = pos+1 end
    else
      local nextComma = line:find(',',pos) or (#line+1)
      table.insert(res, line:sub(pos, nextComma-1))
      pos = nextComma + 1
    end
  end
  return res
end

-----------------------------------------------------------
-- TRACK MANAGEMENT: Top-only, never hidden, no folders
-----------------------------------------------------------

local function getBaseName(path)
  return path:match("^.+/(.+)$") or path:match("^.+\\(.+)$") or path
end

local function stripExt(name)
  return name:match("^(.-)%.") or name
end

local function findOrCreatePictureTrack(csv_path)
  local base = getBaseName(csv_path)
  local picture_version = stripExt(base)
  local target_name = "@" .. picture_version

  -- Look for an existing track with this name
  for i = 0, reaper.CountTracks(0)-1 do
    local tr = reaper.GetTrack(0, i)
    local _, tname = reaper.GetTrackName(tr, "")
    if tname == target_name then
      return tr, target_name, picture_version
    end
  end

  -- Not found: insert at top
  reaper.InsertTrackAtIndex(0, true)
  local tr = reaper.GetTrack(0, 0)
  reaper.GetSetMediaTrackInfo_String(tr, "P_NAME", target_name, true)
  -- Always visible
  reaper.SetMediaTrackInfo_Value(tr, "B_SHOWINTCP", 1)
  reaper.SetMediaTrackInfo_Value(tr, "B_SHOWINMIXER", 1)
  return tr, target_name, picture_version
end

-----------------------------------------------------------
-- CSV LOADING & ITEM CREATION (per version track)
-----------------------------------------------------------

local function loadCSV(path)
  if not path or path == "" then return end
  local file, err = io.open(path, "r")
  if not file then return end

  -- Parse header and get indexes
  local header = file:read("*l")
  if not header then file:close(); return end
  local cols = parseCSVLine(header)
  local idx = {}
  for i, name in ipairs(cols) do
    local key = string.lower((name or ""):gsub("%s+", ""))
    idx[key] = i
  end
  if not (idx["commenter"] and idx["comment"] and idx["timecodesourcein"] and idx["timecodesourceout"]) then
    file:close(); return
  end

  -- Group comments by timecode
  local groups = {}
  for line in file:lines() do
    if line:match('%S') then
      local f = parseCSVLine(line)
      local commenter = trim(f[idx["commenter"]])
      local comment   = trim(f[idx["comment"]])
      local inStr     = trim(f[idx["timecodesourcein"]])
      local outStr    = trim(f[idx["timecodesourceout"]])
      local key = inStr.."__"..outStr
      if not groups[key] then
        groups[key] = {inStr=inStr, outStr=outStr, comments={}}
      end
      table.insert(groups[key].comments, commenter .. ": " .. comment)
    end
  end
  file:close()

  reaper.Undo_BeginBlock()
  local picTrack, trackName, picVersion = findOrCreatePictureTrack(path)
  if not picTrack then reaper.Undo_EndBlock("CSV to MIDI fail", -1); return end

  for _, g in pairs(groups) do
    local inStr, outStr = g.inStr, g.outStr
    local inPos  = reaper.parse_timestr_pos(inStr, 0)
    local outPos = reaper.parse_timestr_pos(outStr, 0)
    local startPos, endPos
    if inPos and outPos and outPos > inPos then
      startPos, endPos = inPos, outPos
    else
      if inPos then
        startPos = math.max(0, inPos - START_OFFSET_SEC)
      else
        startPos = 0
      end
      endPos = startPos + DEFAULT_LENGTH_SEC
    end
    if startPos and endPos and endPos > startPos then
      local item = reaper.CreateNewMIDIItemInProj(picTrack, startPos, endPos)
      if item then
        local take = reaper.GetMediaItemTake(item, 0)
        local all_comments = table.concat(g.comments, "\n")
        reaper.GetSetMediaItemTakeInfo_String(take, "P_NAME", all_comments, true)
        reaper.GetSetMediaItemInfo_String(item, "P_NOTES", inStr..";"..outStr, true)
        reaper.SetMediaItemSelected(item, false)
        -- Take FX: apply if fxCmd is valid
        if fxCmd and fxCmd > 0 and take then
          reaper.Main_OnCommand(40289, 0) -- Unselect all items
          reaper.SetMediaItemSelected(item, true)
          reaper.Main_OnCommand(fxCmd, 0) -- Add take FX to active take
          reaper.SetMediaItemSelected(item, false)
        end
      end
    end
  end

  reaper.UpdateArrange()
  reaper.Undo_EndBlock("Import CSV as MIDI Items to Picture Track", -1)
end

-----------------------------------------------------------
-- TRACK -> LUA TABLE UPDATE: SCAN ALL VERSION TRACKS
-----------------------------------------------------------

local function updateNotesData()
  notesData = {}
  itemRefs = {}
  itemStates = {}
  itemTrackNames = {}

  for i = 0, reaper.CountTracks(0)-1 do
    local tr = reaper.GetTrack(0, i)
    local _, tname = reaper.GetTrackName(tr, "")
    if tname and tname:sub(1,1) == "@" then
      local picVersion = tname:sub(2)
      for j = 0, reaper.CountTrackMediaItems(tr)-1 do
        local itm  = reaper.GetTrackMediaItem(tr, j)
        local pos  = reaper.GetMediaItemInfo_Value(itm, 'D_POSITION')
        local len  = reaper.GetMediaItemInfo_Value(itm, 'D_LENGTH')
        local fin  = pos + len
        local _, noteStr = reaper.GetSetMediaItemInfo_String(itm, "P_NOTES", "", false)
        local origIn, origOut = noteStr and noteStr:match("([^;]*);(.*)")
        local timeIn  = origIn  or reaper.format_timestr_pos(pos, "", 0)
        local timeOut = origOut or reaper.format_timestr_pos(fin, "", 0)
        local take = reaper.GetMediaItemTake(itm, 0)
        local _, tn = reaper.GetSetMediaItemTakeInfo_String(take, "P_NAME", "", false)
        table.insert(notesData, {
          timeIn    = timeIn,
          timeOut   = timeOut,
          comments  = tn or "",
          picVersion = picVersion
        })
        table.insert(itemRefs, itm)
        table.insert(itemStates, reaper.GetMediaItemInfo_Value(itm, "B_MUTE") == 1)
        table.insert(itemTrackNames, picVersion)
      end
    end
  end
end

-----------------------------------------------------------
-- MAIN UI LOOP: ImGui Table & Bi-Directional Color Buttons
-----------------------------------------------------------

local function loop()
  updateNotesData() -- Always refresh UI from REAPER project!

  reaper.ImGui_SetNextWindowSize(ctx, 800, 600, reaper.ImGui_Cond_FirstUseEver())
  local visible, open = reaper.ImGui_Begin(ctx, "CSV to MIDI & Live Notes", true)
  if visible then

    -- Import Button (top)
    if reaper.ImGui_Button(ctx, "Import CSV...") then
      local ok, fn = reaper.GetUserFileNameForRead('', 'Select CSV file', '')
      if ok and fn ~= '' then loadCSV(fn) end
    end
    reaper.ImGui_Separator(ctx)

    -- Main Feedback Table
    if #notesData > 0 then
      if reaper.ImGui_BeginTable(ctx, "feedback-table", 5,
        reaper.ImGui_TableFlags_RowBg() |
        reaper.ImGui_TableFlags_Borders()
      ) then
        -- Columns: 4 auto-width, 1 stretch
        reaper.ImGui_TableSetupColumn(ctx, "", reaper.ImGui_TableColumnFlags_WidthFixed()) -- Color btn
        reaper.ImGui_TableSetupColumn(ctx, "Version", reaper.ImGui_TableColumnFlags_WidthFixed())
        reaper.ImGui_TableSetupColumn(ctx, "Time In", reaper.ImGui_TableColumnFlags_WidthFixed())
        reaper.ImGui_TableSetupColumn(ctx, "Time Out", reaper.ImGui_TableColumnFlags_WidthFixed())
        reaper.ImGui_TableSetupColumn(ctx, "Comments", reaper.ImGui_TableColumnFlags_WidthStretch())
        reaper.ImGui_TableHeadersRow(ctx)

        for i, e in ipairs(notesData) do
          reaper.ImGui_TableNextRow(ctx)
          reaper.ImGui_PushID(ctx, i)

          -- Color Button (toggle mute/unmute), NO TEXT
          reaper.ImGui_TableSetColumnIndex(ctx, 0)
          local mute = itemStates[i]
          local col = mute and 0x4ee44eff or 0xef3a3aff -- green or red
          reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Button(), col)
          reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_ButtonHovered(), col | 0x44000000)
          reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_ButtonActive(), col | 0x22000000)
          if reaper.ImGui_Button(ctx, "##colbtn", 28, 0) then
            mute = not mute
            itemStates[i] = mute
            local itm = itemRefs[i]
            if itm then
              reaper.SetMediaItemInfo_Value(itm, "B_MUTE", mute and 1 or 0)
              reaper.UpdateArrange()
            end
          end
          reaper.ImGui_PopStyleColor(ctx, 3)

          -- Version (track name w/o @)
          reaper.ImGui_TableSetColumnIndex(ctx, 1)
          reaper.ImGui_Text(ctx, e.picVersion or "")

          -- Time In (click to jump cursor)
          reaper.ImGui_TableSetColumnIndex(ctx, 2)
          if reaper.ImGui_Selectable(ctx, e.timeIn, false) then
            local pos = reaper.parse_timestr_pos(e.timeIn, 0)
            if pos then reaper.SetEditCurPos(pos, true, false) end
          end

          -- Time Out
          reaper.ImGui_TableSetColumnIndex(ctx, 3)
          reaper.ImGui_Text(ctx, e.timeOut or "")

          -- Comments
          reaper.ImGui_TableSetColumnIndex(ctx, 4)
          reaper.ImGui_Text(ctx, e.comments or "")

          reaper.ImGui_PopID(ctx)
        end
        reaper.ImGui_EndTable(ctx)
      end
    else
      reaper.ImGui_Text(ctx, "No notes found for any picture version.")
    end

    reaper.ImGui_End(ctx)
  end

  if open then reaper.defer(loop) else reaper.ImGui_DestroyContext(ctx) end
end

-----------------------------------------------------------
-- LAUNCH
-----------------------------------------------------------
reaper.defer(loop)
