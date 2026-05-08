-- Track Importer Script with Debugging
-- Version 1.1 - Crash-proof with console logging

local r = reaper
local console = {}

function console.log(msg)
    r.ShowConsoleMsg(tostring(msg).."\n")
end

function console.error(msg)
    r.ShowConsoleMsg("ERROR: "..tostring(msg).."\n")
end

function SafeImGuiCall(func, ...)
    local success, ret = pcall(func, ...)
    if not success then
        console.error("ImGui call failed: "..tostring(ret))
        return false
    end
    return ret
end

-- Load the RPP Parser functions would go here
-- [Previous RPP parser code]

function Main()
    console.log("Starting Track Importer")
    
    local ctx = SafeImGuiCall(r.ImGui_CreateContext, 'Track Importer')
    if not ctx then 
        console.error("Failed to create ImGui context")
        return 
    end
    
    local open = true
    local selected_file = ""
    local tracks = {}
    local refresh_tracks = true
    
    local function UpdateTracks()
        console.log("Updating tracks from: "..selected_file)
        if selected_file == "" then return end
        
        local project_chunk, err = ReadRPP(selected_file)
        if not project_chunk then
            console.error("Failed to parse RPP: "..tostring(err))
            return
        end
        
        local track_chunks = project_chunk:findAllChunksByName("TRACK")
        if not track_chunks then
            console.error("No TRACK chunks found in project")
            return
        end
        
        tracks = {}
        for i, track in ipairs(track_chunks) do
            local name_node = track:findFirstNodeByName("NAME")
            local name = "Unnamed Track "..i
            if name_node and name_node.getParam then
                local param = name_node:getParam(1)
                if param and param.getString then
                    name = param:getString() or name
                end
            end
            table.insert(tracks, {
                name = name,
                chunk = track,
                selected = false
            })
            console.log("Found track: "..name)
        end
        refresh_tracks = false
    end

    while open do
        local visible = SafeImGuiCall(r.ImGui_Begin, ctx, 'Track Importer', open)
        if not visible then break end
        
        -- File selection
        if SafeImGuiCall(r.ImGui_Button, ctx, 'Browse...') then
            local ret, file = r.GetUserFileNameForRead("", "Select REAPER Project", "RPP")
            if ret then
                selected_file = file
                refresh_tracks = true
                console.log("Selected file: "..selected_file)
            end
        end
        
        SafeImGuiCall(r.ImGui_SameLine, ctx)
        SafeImGuiCall(r.ImGui_Text, ctx, selected_file ~= "" and selected_file or "No file selected")
        
        -- Parse and display tracks when file is selected
        if selected_file ~= "" and refresh_tracks then
            UpdateTracks()
        end
        
        -- Display track list
        if #tracks > 0 then
            SafeImGuiCall(r.ImGui_Separator, ctx)
            SafeImGuiCall(r.ImGui_Text, ctx, "Select Tracks to Import:")
            
            for i, track in ipairs(tracks) do
                local changed, state = SafeImGuiCall(r.ImGui_Checkbox, ctx, "##track"..i, track.selected)
                if changed then
                    track.selected = state
                    console.log("Track "..track.name.." selection changed to: "..tostring(state))
                end
                
                SafeImGuiCall(r.ImGui_SameLine, ctx)
                SafeImGuiCall(r.ImGui_Text, ctx, track.name)
            end
        end
        
        -- Import button
        if #tracks > 0 and SafeImGuiCall(r.ImGui_Button, ctx, 'Import Selected Tracks') then
            console.log("Import button clicked")
            
            -- Find selected tracks
            local selected_chunks = {}
            for _, track in ipairs(tracks) do
                if track.selected then
                    table.insert(selected_chunks, track.chunk)
                end
            end
            
            if #selected_chunks > 0 then
                console.log("Starting import of "..#selected_chunks.." tracks")
                
                -- Create temporary RPP
                local temp_project = CreateRPP()
                if not temp_project then
                    console.error("Failed to create temp project")
                else
                    local temp_tracks_chunk = AddRChunk(temp_project, {"TRACKS"})
                    if not temp_tracks_chunk then
                        console.error("Failed to create TRACKS chunk")
                    else
                        -- Process selected tracks
                        for _, chunk in ipairs(selected_chunks) do
                            if chunk and chunk.StripGUID then
                                chunk:StripGUID()
                                local copied = chunk:copy(temp_tracks_chunk)
                                if not copied then
                                    console.error("Failed to copy track chunk")
                                end
                            end
                        end
                        
                        -- Save temp file
                        local temp_path = r.GetExePath() .. "/Scripts/temp_import.RPP"
                        console.log("Writing temp file to: "..temp_path)
                        local success, err = WriteRPP(temp_path, temp_project)
                        
                        if success then
                            console.log("Temp file written successfully")
                            -- Import into current project
                            local ret = r.Main_openProject("noprompt:"..temp_path)
                            console.log("Import result: "..tostring(ret))
                            
                            -- Clean up
                            os.remove(temp_path)
                            console.log("Temp file removed")
                        else
                            console.error("Failed to write temp file: "..tostring(err))
                        end
                    end
                end
            else
                console.log("No tracks selected for import")
            end
            
            open = false -- Close window after import
        end
        
        SafeImGuiCall(r.ImGui_End, ctx)
        
        if open then
            r.defer(Main)
        else
            SafeImGuiCall(r.ImGui_DestroyContext, ctx)
            console.log("Script finished")
        end
    end
end

-- Run the script with error handling
local ok, err = pcall(Main)
if not ok then
    console.error("Script crashed: "..tostring(err))
    local trace = debug.traceback()
    console.error(trace)
end
