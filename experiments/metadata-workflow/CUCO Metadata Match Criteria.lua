-- @description CUCO Metadata Match (match with BWF and iXML metadata)
-- @author curl (based on Rodilab)
-- @version 1.1
-- @changelog No modal popups, status at window bottom, robust match insert/take timing
-- @about
--   Search for matches to audio files in a folder, according to the matching criteria in the BWF and iXML metadata.
--   Imports matching files into new takes or tracks. Always opens UI, multi-item batch safe.

local r = reaper
local script_name = "CUCO Metadata Match"
local OS_Win = string.match(r.GetOS(),"Win")
local OS_Mac = string.match(r.GetOS(),"OSX")

---------------------------
-- Utility/version check
---------------------------
local function TestVersion(version,version_min)
  local i = 0
  for num in tostring(version):gmatch('%d+') do
    i = i + 1
    if version_min[i] and tonumber(num) > version_min[i] then
      return true
    elseif version_min[i] and tonumber(num) < version_min[i] then
      return false
    end
  end
  return i >= #version_min
end

---------------------------
-- Extensions check
---------------------------
if not r.APIExists('ImGui_CreateContext') then
  r.ShowMessageBox("Please install \"ReaImGui: ReaScript binding for Dear ImGui\" with ReaPack and restart Reaper",script_name,0)
  local ReaPack_exist = r.APIExists('ReaPack_BrowsePackages')
  if ReaPack_exist then r.ReaPack_BrowsePackages('ReaImGui: ReaScript binding for Dear ImGui') end
  return
end

local imgui_version, reaimgui_version = r.ImGui_GetVersion()
if not TestVersion(reaimgui_version,{0,5,0}) then
  r.ShowMessageBox("Please update v0.5.0 or later of \"ReaImGui: ReaScript binding for Dear ImGui\" with ReaPack and restart Reaper",script_name,0)
  local ReaPack_exist = r.APIExists('ReaPack_BrowsePackages')
  if ReaPack_exist then r.ReaPack_BrowsePackages('ReaImGui: ReaScript binding for Dear ImGui') end
  return
end

if not r.APIExists('JS_Dialog_BrowseForOpenFiles') then
  r.ShowMessageBox("Please install \"js_ReaScriptAPI: API functions for ReaScripts\" with ReaPack and restart Reaper",script_name,0)
  local ReaPack_exist = r.APIExists('ReaPack_BrowsePackages')
  if ReaPack_exist then r.ReaPack_BrowsePackages('js_ReaScriptAPI: API functions for ReaScripts') end
  return
end

dofile(r.GetResourcePath() .. '/Scripts/ReaTeam Extensions/API/imgui.lua')('0.6')
local menubar_color = r.ImGui_ColorConvertHSVtoRGB(0.59,0.65,0.5,1)
local child_heigth = 230
local button_width = 100
local separ = package.config:sub(1,1)
local list_ixml_tags = {
  "IXML:SPEED:TIMESTAMP_SAMPLES_SINCE_MIDNIGHT_LO",
  "IXML:BEXT:BWF_ORIGINATION_DATE",
  "IXML:PROJECT",
  "IXML:TAPE",
  "IXML:SCENE",
  "IXML:TAKE",
  "BWF:Description",
  "BWF:TimeReference"
}

---------------------------
-- ExtState
---------------------------
local conf = {}
local extstate_id = "CUCO_Metadata_Match"

local function ExtState_Load()
  local def = {
    txtbox_characters = 0,
    radio_import = 2,
    check_tc = false,
    check_date = false,
    check_project = true,
    check_tape = true,
    check_scene = true,
    check_take = true,
    mouse_pos = true, 
    BWF_Description = true,
    BWF_timecode = true,
    folder = false
  }
  for key in pairs(def) do
    if r.HasExtState(extstate_id,key) then
      local es_str = r.GetExtState(extstate_id,key)
      if es_str == 'true' then es_str = true
      elseif es_str == 'false' then es_str = false end
      conf[key] = tonumber(es_str) or es_str
      if (type(conf[key]) ~= 'number' and (key=='txtbox_characters' or key=='radio_import'))
      or (type(conf[key]) ~= 'boolean'and (key=='check_tc'
        or key=='check_date' or key=='check_project' or key=='check_tape'
        or key=='check_scene' or key=='check_take'
        or key=='BWF_Description' or key=='BWF_timecode')) then
        conf[key] = def[key]
      end
    else
      conf[key] = def[key]
    end
  end
  -- Erase old keys (window pos)
  for _, key in ipairs({'x','y','width','heigth'}) do
    if r.HasExtState(extstate_id,key) then
      r.DeleteExtState(extstate_id,key,true)
    end
  end
end

local function ExtState_Save()
  for key in pairs(conf) do
    local value = conf[key]
    if value == true then value = 'true'
    elseif value == false then value = 'false' end
    r.SetExtState(extstate_id,key,value,key ~= "folder")
  end
end

r.atexit(function() ExtState_Save() end)

---------------------------
-- Core functions
---------------------------
local function save_metadata(source,list_metadata)
  local value_list = {}
  for i, tag in ipairs(list_metadata) do
    local retval,value = r.GetMediaFileMetadata(source,tag)
    table.insert(value_list,value)
  end
  return value_list
end

local function new_items()
  local count_new_items = r.CountSelectedMediaItems(0)
  if count_new_items > 0 then
    local list_items = {}
    local list_tracks = {}
    for i=0, count_new_items-1 do
      local item = r.GetSelectedMediaItem(0,i)
      table.insert(list_items,item)
      local track = r.GetMediaItem_Track(item)
      list_tracks[track] = true
    end
    return list_items, list_tracks
  end
end

local function GetAllFiles(folderlist,filelist,metadatalist)
  if type(folderlist)   ~= 'table' then return end
  if type(filelist)     ~= 'table' then filelist     = {} end
  if type(metadatalist) ~= 'table' then metadatalist = {} end 
  local childs = {}
  for _, folder in ipairs(folderlist) do
    r.EnumerateFiles(folder,-1) -- Rescan
    local i = 0
    while r.EnumerateFiles(folder,i) do
      local filename = r.EnumerateFiles(folder,i)
      if string.upper(string.sub(filename,-4,-1)) == '.WAV' then
        local file = folder..separ..filename
        table.insert(filelist,file)
        local tmp_source = r.PCM_Source_CreateFromFile(file)
        metadatalist[file] = save_metadata(tmp_source,list_ixml_tags)
        r.PCM_Source_Destroy(tmp_source)
      end
      i = i + 1
    end
    r.EnumerateSubdirectories(folder,-1) -- Rescan
    i = 0
    while r.EnumerateSubdirectories(folder,i) do
      table.insert(childs,folder..separ..r.EnumerateSubdirectories(folder,i))
      i = i + 1
    end
  end
  if #childs == 0 then
    return filelist, metadatalist
  else
    return GetAllFiles(childs,filelist,metadatalist)
  end
end

local function ParseBWF(takeDesc, fileDesc)
  local takeT, fileT, matchedT = {}, {}, {}
  for v in takeDesc:gmatch('[^\n]+') do
    if v:match('SCENE') or v:match('TAKE') or v:match('TAPE') then
      table.insert(takeT, v)
    end
  end
  for v in fileDesc:gmatch('[^\n]+') do
    table.insert(fileT, v)
  end
  for _, tv in pairs(takeT) do
    local key
    local val = tv:sub(2):gsub('[-+*\n]','')
    key, val = val:match("%s*([^=]*)%s*%=%s*(.-)%s*$")
    for _, fv in pairs(fileT) do
      local key2
      local fval = fv:sub(2):gsub('[-+*\n]','')
      key2, fval = fval:match("%s*([^=]*)%s*%=%s*(.-)%s*$")
      if key == key2 and fval:find(val) then
        table.insert(matchedT, val)
        break
      end
    end
  end
  return #matchedT ~= 0 and #matchedT == #takeT
end

---------------------------
-- Main match function
---------------------------
local status_message = nil
local last_search_tick = 0

local function main()
  r.Undo_BeginBlock()
  r.PreventUIRefresh(1)
  local check_criteria = {
    conf.check_tc, conf.check_date, conf.check_project,
    conf.check_tape, conf.check_scene, conf.check_take,
    conf.BWF_Description, conf.BWF_timecode
  }
  local list_files, list_file_metadata = GetAllFiles({conf.folder})
  table.sort(list_files)
  local count_sel_items = r.CountSelectedMediaItems(0)
  local list_items = {}
  for i = 0, count_sel_items - 1 do
    list_items[i + 1] = r.GetSelectedMediaItem(0, i)
  end
  local list_match_items = {}

  for _, item in ipairs(list_items) do
    local take = r.GetActiveTake(item)
    if take then
      local source = r.GetMediaItemTake_Source(take)
      if r.GetMediaSourceType(source, "") == "WAVE" then
        local item_match = false
        local take_info_values = {
          ["D_STARTOFFS"] = r.GetMediaItemTakeInfo_Value(take, "D_STARTOFFS"),
          ["D_VOL"] = r.GetMediaItemTakeInfo_Value(take, "D_VOL"),
          ["D_PAN"] = r.GetMediaItemTakeInfo_Value(take, "D_PAN"),
          ["D_PANLAW"] = r.GetMediaItemTakeInfo_Value(take, "D_PANLAW"),
          ["D_PITCH"] = r.GetMediaItemTakeInfo_Value(take, "D_PITCH"),
          ["I_PITCHMODE"] = r.GetMediaItemTakeInfo_Value(take, "I_PITCHMODE"),
          ["I_CUSTOMCOLOR"] = r.GetMediaItemTakeInfo_Value(take, "I_CUSTOMCOLOR"),
        }
        local take_metadata = save_metadata(source, list_ixml_tags)
        local take_filename = r.GetMediaSourceFileName(source, ""):match('^.+' .. separ .. '(.+)$')
        local take_characters = string.sub(take_filename, 1, conf.txtbox_characters)

        for _, file in ipairs(list_files) do
          local file_metadata = list_file_metadata[file]
          local match = false
          for k, value in ipairs(take_metadata) do
            if check_criteria[k] == true then
              if k ~= #check_criteria then
                if k == #check_criteria - 1 then
                  match = ParseBWF(value, file_metadata[k])
                else
                  if value ~= file_metadata[k] or value == "" then
                    match = false break
                  else
                    match = true
                  end
                end
              end
            end
          end

          local filename = file:match("^.+" .. separ .. "(.+)$")
          local file_characters = string.sub(filename, 1, conf.txtbox_characters)
          if conf.txtbox_characters > 0 and match == true and take_characters ~= file_characters then
            match = false
          end

          if match == true and take_filename ~= filename then
            -- Reselect original item before every insert (fixes focus issues)
            r.Main_OnCommand(40289, 0) -- Unselect all
            r.SetMediaItemSelected(item, true)
            r.Main_OnCommand(40131, 0) -- Crop to active take
            r.InsertMedia(file, 3) -- insert as new take

            -- Reacquire correct item and new take pointer
            r.SetMediaItemSelected(item, true)
            local new_take = r.GetActiveTake(item)
            local new_source = r.GetMediaItemTake_Source(new_take)
            for tag, value in pairs(take_info_values) do
              r.SetMediaItemTakeInfo_Value(new_take, tag, value)
            end
            local _, aafSplTime = r.GetMediaFileMetadata(source, 'BWF:TimeReference')
            local aafSplRate = r.GetMediaSourceSampleRate(source)
            local aaftime = tonumber(aafSplTime) / aafSplRate
            local _, origSplTime = r.GetMediaFileMetadata(new_source, 'BWF:TimeReference')
            local origSplRate = r.GetMediaSourceSampleRate(new_source)
            local origtime = tonumber(origSplTime) / origSplRate
            local newOffs = take_info_values["D_STARTOFFS"] + (aaftime - origtime)
            r.SetMediaItemTakeInfo_Value(new_take, "D_STARTOFFS", newOffs)
            item_match = true
          end
        end

        -- BWF timecode fallback
        if check_criteria[#check_criteria] == true and not item_match then
          local aafSplTime = take_metadata[#check_criteria]
          if aafSplTime ~= '' then
            local aafSplRate = r.GetMediaSourceSampleRate(source)
            local aafStart = tonumber(aafSplTime) / aafSplRate
            local itemlength = r.GetMediaItemInfo_Value(item, 'D_LENGTH')
            local aafEnd = aafStart + take_info_values["D_STARTOFFS"] + itemlength

            for _, file in ipairs(list_files) do
              local src = r.PCM_Source_CreateFromFile(file)
              local fileLength, _ = r.GetMediaSourceLength(src)
              local _, origSplTime = r.GetMediaFileMetadata(src, 'BWF:TimeReference')
              local origSplRate = r.GetMediaSourceSampleRate(src)
              r.PCM_Source_Destroy(src)

              if origSplTime ~= '' then
                local origStart = tonumber(origSplTime) / origSplRate
                local origEnd = origStart + fileLength
                if origStart < aafEnd and origEnd > aafStart + take_info_values["D_STARTOFFS"] then
                  r.Main_OnCommand(40289, 0)
                  r.SetMediaItemSelected(item, true)
                  r.Main_OnCommand(40131, 0)
                  r.InsertMedia(file, 3)
                  r.SetMediaItemSelected(item, true)
                  local new_take = r.GetActiveTake(item)
                  local new_source = r.GetMediaItemTake_Source(new_take)
                  for tag, value in pairs(take_info_values) do
                    r.SetMediaItemTakeInfo_Value(new_take, tag, value)
                  end
                  local newOffs = take_info_values["D_STARTOFFS"] + (aafStart - origStart)
                  r.SetMediaItemTakeInfo_Value(new_take, "D_STARTOFFS", newOffs)
                  item_match = true
                end
              end
            end
          end
        end

        if item_match == true then
          table.insert(list_match_items, item)
        end
      end
    end
  end

  -- Batch UI update
  if #list_match_items > 0 then
    r.Main_OnCommand(40289, 0) -- Unselect all
    for _, item in ipairs(list_match_items) do
      r.SetMediaItemSelected(item, true)
    end
    if conf.radio_import == 2 then
      r.Main_OnCommand(40224, 0) -- Explode across tracks
      local list_new_items, list_new_tracks = new_items()
      r.Main_OnCommand(40289, 0)
      for _, item in ipairs(list_match_items) do
        r.SetMediaItemSelected(item, true)
        r.SetMediaItemInfo_Value(item, "I_CURTAKE", 0)
      end
      for new_track, _ in pairs(list_new_tracks) do
        r.SetTrackSelected(new_track, true)
      end
      for _, new_item in ipairs(list_new_items) do
        r.SetMediaItemSelected(new_item, true)
      end
      r.Main_OnCommand(40131, 0) -- Crop to active take
    end
    status_message = #list_match_items .. "/" .. #list_items .. " items have successfully matched."
  else
    status_message = "No match"
  end
  last_search_tick = r.time_precise()
  r.Undo_EndBlock(script_name, -1)
  r.PreventUIRefresh(-1)
  r.UpdateArrange()
end

---------------------------
-- ImGui UI
---------------------------
local ctx, font
local function StartContext()
  ctx = r.ImGui_CreateContext(script_name)
  font = r.ImGui_CreateFont('Arial',12)
  r.ImGui_AttachFont(ctx,font)
end

local match_button
local close
local function ImGuiBody()
  local rv
  local count_sel_items = r.CountSelectedMediaItems(0)
  local WindowSize = {r.ImGui_GetWindowSize(ctx)}

  r.ImGui_PushStyleVar(ctx,r.ImGui_StyleVar_FrameRounding(),4.0)

  if count_sel_items == 0 then
    r.ImGui_TextColored(ctx, 0xFF4444FF, "No items selected. Please select items to match.")
  else
    r.ImGui_Text(ctx, tostring(count_sel_items) .. " items selected.")
  end

  -- Folder
  if r.ImGui_Button(ctx,'Folder') then
    local rv, browse = r.JS_Dialog_BrowseForFolder('',conf.folder)
    if rv == 1 then conf.folder = browse end
  end
  r.ImGui_SameLine(ctx)
  r.ImGui_TextWrapped(ctx,conf.folder or "")
  r.ImGui_PushStyleVar(ctx,r.ImGui_StyleVar_ItemSpacing(),0,r.ImGui_GetTextLineHeight(ctx))
  r.ImGui_Spacing(ctx)
  r.ImGui_PopStyleVar(ctx)

  r.ImGui_PushStyleVar(ctx, r.ImGui_StyleVar_ChildRounding(),5.0)
  r.ImGui_PushStyleColor(ctx, r.ImGui_Col_MenuBarBg(),menubar_color)

  if r.ImGui_BeginChild(ctx, 'ChildL', WindowSize[1]*0.6, child_heigth, true, r.ImGui_WindowFlags_MenuBar()) then
    if r.ImGui_BeginMenuBar(ctx) then
      r.ImGui_Text(ctx,'Criteria')
      r.ImGui_EndMenuBar(ctx)
    end
    rv,conf.check_tc =      r.ImGui_Checkbox(ctx,'TC Start',conf.check_tc)
    rv,conf.check_date =    r.ImGui_Checkbox(ctx,'Date',conf.check_date)
    rv,conf.check_project = r.ImGui_Checkbox(ctx,'Project Name',conf.check_project)
    rv,conf.check_tape =    r.ImGui_Checkbox(ctx,'Tape',conf.check_tape)
    rv,conf.check_scene =   r.ImGui_Checkbox(ctx,'Scene',conf.check_scene)
    rv,conf.check_take =    r.ImGui_Checkbox(ctx,'Take',conf.check_take)
    rv,conf.BWF_Description = r.ImGui_Checkbox(ctx,'BWF Description (Scene, Take, Tape)',conf.BWF_Description)
    rv,conf.BWF_timecode = r.ImGui_Checkbox(ctx,'Use BWF timecode if other fields are empty',conf.BWF_timecode)
    r.ImGui_PushItemWidth(ctx,65)
    rv,conf.txtbox_characters = r.ImGui_InputInt(ctx,'First Characters',conf.txtbox_characters,1,1)
    r.ImGui_EndChild(ctx)
  end

  r.ImGui_SameLine(ctx)

  if r.ImGui_BeginChild(ctx, 'ChildR', 0, child_heigth, true, r.ImGui_WindowFlags_MenuBar()) then
    if r.ImGui_BeginMenuBar(ctx) then
      r.ImGui_Text(ctx,'Import files in')
      r.ImGui_EndMenuBar(ctx)
    end
    rv,conf.radio_import = r.ImGui_RadioButtonEx(ctx, 'New Takes', conf.radio_import,1)
    rv,conf.radio_import = r.ImGui_RadioButtonEx(ctx, 'New Tracks', conf.radio_import,2)
    r.ImGui_EndChild(ctx)
  end
  r.ImGui_PopStyleColor(ctx)
  r.ImGui_PopStyleVar(ctx)

  rv,conf.mouse_pos = r.ImGui_Checkbox(ctx,'Open window on mouse position',conf.mouse_pos)

  r.ImGui_PushStyleVar(ctx,r.ImGui_StyleVar_ItemSpacing(),0,r.ImGui_GetTextLineHeight(ctx))
  r.ImGui_Spacing(ctx)
  r.ImGui_PopStyleVar(ctx)

  r.ImGui_NewLine(ctx)
  r.ImGui_SameLine(ctx,(WindowSize[1]/2)-button_width-10)
  local criteria_ok = conf.check_tc or conf.check_date or conf.check_project or conf.check_tape or conf.check_scene or conf.check_take or conf.BWF_Description or conf.BWF_timecode or (conf.txtbox_characters and conf.txtbox_characters > 0)
  local can_match = count_sel_items > 0 and criteria_ok

  if not can_match then
    r.ImGui_BeginDisabled(ctx)
  end
  if r.ImGui_Button(ctx,'Match',button_width,30) or (can_match and r.ImGui_IsKeyDown(ctx,36)) then
    if can_match then
      match_button = 0
    end
  end
  if not can_match then
    r.ImGui_EndDisabled(ctx)
  end
  r.ImGui_SameLine(ctx,(WindowSize[1]/2)+10)
  if r.ImGui_Button(ctx,'Cancel',button_width,30) then
    close = true
  end
  r.ImGui_PopStyleVar(ctx,1)

  -- === BOTTOM STATUS / MESSAGE LINE ===
  r.ImGui_Separator(ctx)
  if match_button == 1 then
    r.ImGui_TextColored(ctx, 0xAAAAFFFF, "Searching, please wait...")
  elseif status_message then
    local color = status_message:match("No match") and 0xFF4444FF or 0x44FF44FF
    r.ImGui_TextColored(ctx, color, status_message)
    -- Clear message after 8 seconds
    if r.time_precise() - last_search_tick > 8 then status_message = nil end
  end
end

local loopcnt = 0
local function loop()
  r.ImGui_PushFont(ctx,font)
  r.ImGui_PushStyleColor(ctx,r.ImGui_Col_WindowBg(),0x333333ff)
  r.ImGui_PushStyleVar(ctx,r.ImGui_StyleVar_WindowTitleAlign(),0.5,0.5)

  if conf.mouse_pos then
    local cur_x, cur_y = r.GetMousePosition()
    if OS_Mac then
      local primary_monitor_height = ({r.BR_Win32_GetMonitorRectFromRect(false, 0, 0, 0, 0)})[4]
      cur_y = primary_monitor_height - cur_y
    end
    r.ImGui_SetNextWindowPos(ctx, cur_x, cur_y, r.ImGui_Cond_Once(), 0.5)
  end

  local window_flag = r.ImGui_WindowFlags_NoCollapse() | r.ImGui_WindowFlags_NoDocking()
  local visible, open = r.ImGui_Begin(ctx, script_name, true, window_flag)
  r.ImGui_PopStyleColor(ctx)
  if visible then
    ImGuiBody()
    if loopcnt == 0 then r.ImGui_SetWindowSize(ctx, 0, 0, nil ) end
    r.ImGui_End(ctx)
  end
  r.ImGui_PopStyleVar(ctx)
  r.ImGui_PopFont(ctx)
  if match_button then
    if match_button > 1 then
      match_button = false
      main()
    else
      match_button = match_button + 1
    end
  end
  if not open or r.ImGui_IsKeyDown(ctx,27) or close then
    r.ImGui_DestroyContext(ctx)
  else
    r.defer(loop)
  end
  loopcnt = loopcnt + 1
end

---------------------------
-- DO IT: Startup
---------------------------
ExtState_Load()
if conf.folder == false then conf.folder = r.GetProjectPath("") end
StartContext()
r.defer(loop)
