-- COMPLETE TRACK IMPORTER WITH GUI
-- Version 2.3 - Combines robust RPP parsing with your original GUI

local ctx = reaper.ImGui_CreateContext('Track Importer')
local version = reaper.ImGui_GetVersion()
local selected_file = nil
local track_data = {}

-- SAFE DEBUG LOGGING
local function debug_log(msg)
    reaper.ShowConsoleMsg(tostring(msg).."\n")
end

-- IMPROVED RPP PARSER (WITH YOUR GUI)
local function parse_rpp(file_path)
    if not file_path then return {} end
    
    local file = io.open(file_path, 'r')
    if not file then 
        debug_log("Error opening file: "..tostring(file_path))
        return {} 
    end
    
    local tracks = {}
    local current_track = nil
    local stack = {}
    
    for line in file:lines() do
        local clean_line = line:match('^%s*(.-)%s*$') or ""
        
        -- Track start
        if clean_line:find('<TRACK') then
            current_track = {
                name = "Unnamed",
                muted = false,
                solo = 0,
                folder = {
                    depth = 0,
                    parent = nil
                }
            }
            table.insert(tracks, current_track)
            table.insert(stack, current_track)
        
        -- Track end
        elseif clean_line == '>' then
            if #stack > 0 then
                table.remove(stack)
                current_track = (#stack > 0) and stack[#stack] or nil
            end
        
        -- Track properties
        elseif current_track then
            if clean_line:find('NAME') then
                current_track.name = clean_line:match('NAME "(.*)"') or current_track.name
            elseif clean_line:find('MUTESOLO') then
                local mute, solo = clean_line:match('MUTESOLO (%d+) (%d+)')
                current_track.muted = (tonumber(mute or 0) == 1)
                current_track.solo = tonumber(solo or 0)
            elseif clean_line:find('ISBUS') then
                local state, comp = clean_line:match('ISBUS (%d+) (%d+)')
                if tonumber(state) == 1 and tonumber(comp) == 1 then
                    current_track.folder.depth = 1
                elseif tonumber(state) == 2 and tonumber(comp) == -1 then
                    current_track.folder.depth = -1
                end
            end
        end
    end
    
    file:close()
    
    -- Build folder hierarchy
    local folder_stack = {}
    for i, track in ipairs(tracks) do
        if track.folder.depth == 1 then
            table.insert(folder_stack, i)
        elseif track.folder.depth == -1 and #folder_stack > 0 then
            table.remove(folder_stack)
        end
        
        if #folder_stack > 0 then
            track.folder.parent = folder_stack[#folder_stack]
        end
    end
    
    return tracks
end

-- YOUR ORIGINAL FILE DIALOG CODE
local function open_file_dialog()
    local ret, file_path = reaper.GetUserFileNameForRead("", "Select REAPER Project", "")
    if ret then
        selected_file = file_path
        track_data = parse_rpp(file_path)
        debug_log("Loaded "..#track_data.." tracks")
        
        -- Debug print all tracks
        for i, track in ipairs(track_data) do
            debug_log(string.format("Track %d: %s (Mute: %s, Solo: %d, Folder: %s)",
                i, 
                track.name,
                track.muted and "ON" or "OFF",
                track.solo,
                track.folder.depth == 1 and "START" or 
                (track.folder.depth == -1 and "END" or "NORMAL")
            ))
        end
    end
end

-- YOUR ORIGINAL IMPORT FUNCTION (UPDATED)
local function import_tracks()
    if not selected_file or #track_data == 0 then 
        debug_log("Import failed: No file selected")
        return 
    end

    reaper.PreventUIRefresh(1)
    reaper.Undo_BeginBlock()
    
    local created_tracks = {}
    
    for i, track in ipairs(track_data) do
        -- Create track
        local track_idx = reaper.CountTracks(0)
        reaper.InsertTrackAtIndex(track_idx, false)
        local new_track = reaper.GetTrack(0, track_idx)
        created_tracks[i] = new_track
        
        -- Set properties
        reaper.GetSetMediaTrackInfo_String(new_track, "P_NAME", track.name, true)
        reaper.SetMediaTrackInfo_Value(new_track, "B_MUTE", track.muted and 1 or 0)
        reaper.SetMediaTrackInfo_Value(new_track, "I_SOLO", track.solo)
        
        -- Set folder state
        reaper.SetMediaTrackInfo_Value(new_track, "I_FOLDERDEPTH", track.folder.depth)
        
        -- Set parent if in folder
        if track.folder.parent then
            local parent_ptr = reaper.GetMediaTrackInfo_Value(
                created_tracks[track.folder.parent], "P_TRACK")
            reaper.SetMediaTrackInfo_Value(new_track, "P_PARTRACK", parent_ptr)
        end
    end
    
    reaper.Undo_EndBlock("Import Tracks with Folders", -1)
    reaper.PreventUIRefresh(-1)
    reaper.UpdateArrange()
end

-- YOUR ORIGINAL GUI CODE
local function loop()
    local visible, open = reaper.ImGui_Begin(ctx, 'Track Importer', true)
    if not visible then 
        if not open then
            reaper.ImGui_DestroyContext(ctx)
        end
        return 
    end

    reaper.ImGui_Text(ctx, "Track Importer v2.3")
    reaper.ImGui_Separator(ctx)
    
    if selected_file then
        reaper.ImGui_Text(ctx, "Selected: "..selected_file)
        reaper.ImGui_Text(ctx, string.format("%d tracks ready", #track_data))
        
        if reaper.ImGui_Button(ctx, 'Import Tracks') then
            import_tracks()
        end
        
        if reaper.ImGui_Button(ctx, 'Show Debug Log') then
            reaper.ShowConsoleMsg("")
        end
    else
        reaper.ImGui_Text(ctx, "No project selected")
        if reaper.ImGui_Button(ctx, 'Select Project') then
            open_file_dialog()
        end
    end

    reaper.ImGui_End(ctx)
    
    if open then
        reaper.defer(loop)
    else
        reaper.ImGui_DestroyContext(ctx)
    end
end

-- INITIALIZATION
debug_log("Track Importer initialized")
reaper.defer(loop)
