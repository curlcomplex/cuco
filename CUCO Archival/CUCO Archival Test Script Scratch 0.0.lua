--[[
CUCO Archival Tool v1.3

Description:
This script helps archive Reaper sessions by:
1. Copying external files into the "Media" folder.
2. Moving unused files into the "unused media assets" folder.
3. Handling duplicate files (keeping the newest or deepest).
4. Updating file references in .rpp files.
5. Organizing unused files into subfolders by type.

Usage:
1. Save your Reaper session.
2. Run this script.
3. Check the "archive_report.csv" and "archival_log.txt" for details.

Developer Notes:
- External files are copied to "/Media".
- Unused files are moved to "/unused media assets".
- Files in "RENDER", "RENDERS", "impulses", or "impulse" folders are ignored.
]]

-- Configurable options
local UNUSED_ASSETS_FOLDER = "unused media assets"
local IGNORED_FOLDERS = { "RENDER", "RENDERS", "impulses", "impulse" }
local VERBOSE_MODE = true

-- Helper function to log messages
local function log_message(message)
    local log_file = io.open("archival_log.txt", "a")
    if log_file then
        log_file:write(os.date("%Y-%m-%d %H:%M:%S") .. " - " .. message .. "\n")
        log_file:close()
    end
    if VERBOSE_MODE then
        reaper.ShowConsoleMsg(message .. "\n")
    end
end

-- Helper function to get the root folder of the current session
local function get_root_folder()
    local media_folder = reaper.GetProjectPath("")
    if media_folder == "" then
        log_message("ERROR: No session folder detected! Save the session first.")
        return nil
    end
    local root_folder = media_folder:match("^(.*)/")
    if not root_folder then
        log_message("ERROR: Could not determine the root folder.")
        return nil
    end
    return root_folder
end

-- Helper function to recursively find all .RPP files in a folder
local function find_rpp_files(folder_path)
    local files = {}
    local function scan_folder(path)
        log_message("Scanning folder: " .. path)
        local i = 0
        while true do
            local file_name = reaper.EnumerateFiles(path, i)
            if not file_name then break end
            local full_path = path .. "/" .. file_name
            if not file_name:match("^%.") and not file_name:match("%.RPP%-UNDO$") and not file_name:match("debug_output_.*%.csv$") then
                if file_name:match("%.RPP$") then
                    log_message("Found session file: " .. full_path)
                    table.insert(files, full_path)
                elseif reaper.EnumerateSubdirectories(path, i) then
                    log_message("Entering subfolder: " .. full_path)
                    scan_folder(full_path)
                end
            end
            i = i + 1
        end
    end
    scan_folder(folder_path)
    return files
end

-- Helper function to normalize paths (convert to absolute and consistent separators)
local function normalize_path(path, root_folder)
    if not path:match("^/") and not path:match("^%a:") then
        path = root_folder .. "/" .. path
    end
    path = path:gsub("\\", "/")
    return path
end

-- Helper function to check if a file is in an ignored folder
local function is_ignored_folder(file_path)
    for _, folder in ipairs(IGNORED_FOLDERS) do
        if file_path:lower():match("/" .. folder:lower() .. "/") then
            return true
        end
    end
    return false
end

-- Helper function to extract media file paths from an .RPP file
local function extract_media_files(rpp_file_path, root_folder)
    local media_files = {}
    local file = io.open(rpp_file_path, "r")
    if not file then
        log_message("ERROR: Could not open file: " .. rpp_file_path)
        return nil
    end
    local file_content = file:read("*a")
    file:close()
    for file_path in file_content:gmatch('<SOURCE.-FILE "(.-)"') do
        file_path = normalize_path(file_path, root_folder)
        log_message("Found media file in session: " .. file_path)
        table.insert(media_files, file_path)
    end
    return media_files
end

-- Helper function to create a master list of used files
local function create_master_used_files_list(rpp_files, root_folder)
    local master_used_files = {}
    for _, rpp_file in ipairs(rpp_files) do
        local media_files, err = extract_media_files(rpp_file, root_folder)
        if media_files then
            for _, file_path in ipairs(media_files) do
                master_used_files[file_path] = true
            end
        else
            log_message(err)
        end
    end
    return master_used_files
end

-- Helper function to find all media files in the session folder using system commands
local function find_all_media_files_in_session(folder_path)
    local all_media_files = {}
    local command
    local extensions = {
        ".AIF", ".AIFF", ".AVI", ".BWF", ".CDA", ".DAT", ".EDL", ".FLAC", ".GIF", ".JPEG", 
        ".JPG", ".KAR", ".LCF", ".M4A", ".M4V", ".MID", ".MIDI", ".MKV", ".MOGG", ".MOV", 
        ".MP2", ".MP3", ".MP4", ".MPEG", ".MPG", ".MUSICXML", ".MXL", ".OGG", ".OGV", 
        ".OPUS", ".PNG", ".QT", ".RCY", ".REX", ".RMI", ".RX2", ".SYX", ".W64", ".WAV", 
        ".WEBM", ".WMA", ".WMV", ".WV", ".XML"
    }
    if reaper.GetOS():match("Win") then
        local pattern = ""
        for _, ext in ipairs(extensions) do
            pattern = pattern .. string.format('"%s\\*%s" ', folder_path, ext)
        end
        command = string.format('dir /s /b %s', pattern)
    else
        local pattern = ""
        for _, ext in ipairs(extensions) do
            pattern = pattern .. string.format('-iname "*%s" -o ', ext)
        end
        pattern = pattern:sub(1, -5)
        command = string.format('find "%s" -type f \\( %s \\)', folder_path, pattern)
    end
    local handle = io.popen(command)
    if handle then
        for file_path in handle:lines() do
            file_path = normalize_path(file_path, folder_path)
            if not is_ignored_folder(file_path) then
                table.insert(all_media_files, file_path)
            else
                log_message("Ignoring file in excluded folder: " .. file_path)
            end
        end
        handle:close()
    else
        log_message("ERROR: Could not execute system command to find media files.")
    end
    return all_media_files
end

-- Helper function to get the modified date of a file
local function get_modified_date(file_path)
    local command
    if reaper.GetOS():match("Win") then
        command = string.format('forfiles /P "%s" /M "%s" /C "cmd /c echo @fdate @ftime"', file_path:match("^(.*[/\\])"), file_path:match("[^/\\]+$"))
    else
        command = string.format('stat -f "%%Sm" -t "%%Y-%%m-%%d %%H:%%M:%%S" "%s"', file_path)
    end
    local handle = io.popen(command)
    if handle then
        local result = handle:read("*a")
        handle:close()
        return result:match("%S+ %S+")
    else
        return nil, "ERROR: Could not get modified date for " .. file_path
    end
end

-- Helper function to move files to the unused media assets folder
local function move_to_unused_folder(file_path, root_folder)
    local unused_folder = root_folder .. "/" .. UNUSED_ASSETS_FOLDER
    local file_type = "other"
    if file_path:match("%.wav$") or file_path:match("%.aif$") or file_path:match("%.flac$") then
        file_type = "audio"
    elseif file_path:match("%.mp4$") or file_path:match("%.mov$") or file_path:match("%.avi$") then
        file_type = "video"
    elseif file_path:match("%.mid$") or file_path:match("%.midi$") then
        file_type = "midi"
    elseif file_path:match("%.rpp%-undo$") then
        file_type = "session undos"
    end
    local dest_folder = unused_folder .. "/" .. file_type
    if reaper.GetOS():match("Win") then
        os.execute(string.format('mkdir "%s"', dest_folder))
    else
        os.execute(string.format('mkdir -p "%s"', dest_folder))
    end
    local dest_path = dest_folder .. "/" .. file_path:match("([^/]+)$")
    os.execute(string.format('mv "%s" "%s"', file_path, dest_path))
    log_message("Moved unused file: " .. file_path .. " to " .. dest_path)
end

-- Helper function to copy external files to the Media folder
local function copy_to_media_folder(file_path, root_folder)
    local media_folder = root_folder .. "/Media"
    if reaper.GetOS():match("Win") then
        os.execute(string.format('mkdir "%s"', media_folder))
    else
        os.execute(string.format('mkdir -p "%s"', media_folder))
    end
    local dest_path = media_folder .. "/" .. file_path:match("([^/]+)$")
    os.execute(string.format('cp "%s" "%s"', file_path, dest_path))
    log_message("Copied external file: " .. file_path .. " to " .. dest_path)
    return dest_path
end

-- Helper function to update .rpp file references
local function update_rpp_references(rpp_file_path, old_path, new_path)
    local file = io.open(rpp_file_path, "r")
    if not file then
        log_message("ERROR: Could not open file: " .. rpp_file_path)
        return nil
    end
    local file_content = file:read("*a")
    file:close()
    file_content = file_content:gsub(old_path, new_path)
    file = io.open(rpp_file_path, "w")
    if not file then
        log_message("ERROR: Could not write to file: " .. rpp_file_path)
        return nil
    end
    file:write(file_content)
    file:close()
end

-- Helper function to update media sources in the current session
local function update_media_sources(old_path, new_path)
    for i = 0, reaper.CountTracks(0) - 1 do
        local track = reaper.GetTrack(0, i)
        for j = 0, reaper.CountTrackMediaItems(track) - 1 do
            local item = reaper.GetTrackMediaItem(track, j)
            local take = reaper.GetActiveTake(item)
            if take then
                local source = reaper.GetMediaItemTake_Source(take)
                if source then
                    local source_path = reaper.GetMediaSourceFileName(source, "")
                    if source_path == old_path then
                        local new_source = reaper.PCM_Source_CreateFromFile(new_path)
                        if new_source then
                            reaper.SetMediaItemTake_Source(take, new_source)
                            reaper.UpdateItemInProject(item)
                        else
                            log_message("ERROR: Could not create new source for " .. new_path)
                        end
                    end
                else
                    log_message("WARNING: No valid source found for item " .. j .. " on track " .. i)
                end
            end
        end
    end
end

-- Helper function to delete a file
local function delete_file(file_path)
    if reaper.GetOS():match("Win") then
        os.execute(string.format('del /f /q "%s"', file_path))
    else
        os.execute(string.format('rm -f "%s"', file_path))
    end
    log_message("Deleted file: " .. file_path)
end

-- Helper function to compare files by name, depth, and modified date
local function handle_duplicates(all_media_files, master_used_files, root_folder)
    local files_by_name = {}
    local duplicates = {}
    for _, file_path in ipairs(all_media_files) do
        local file_name = file_path:match("([^/]+)$")
        if not files_by_name[file_name] then
            files_by_name[file_name] = {}
        end
        table.insert(files_by_name[file_name], file_path)
    end
    for file_name, files in pairs(files_by_name) do
        if #files > 1 then
            table.sort(files, function(a, b)
                local depth_a = select(2, a:gsub("/", ""))
                local depth_b = select(2, b:gsub("/", ""))
                if depth_a == depth_b then
                    local date_a = get_modified_date(a)
                    local date_b = get_modified_date(b)
                    return date_a > date_b
                else
                    return depth_a > depth_b
                end
            end)
            for i = 2, #files do
                if not master_used_files[files[i]] then
                    move_to_unused_folder(files[i], root_folder)
                    delete_file(files[i])
                else
                    log_message("Skipping used duplicate: " .. files[i])
                end
            end
        end
    end
end

-- Helper function to write archive report to a CSV file
local function write_archive_report(root_folder, external_files, unused_files)
    local date_time = os.date("%Y%m%d_%H%M%S")
    local report_file_path = root_folder .. "/archive_report_" .. date_time .. ".csv"
    local report_file = io.open(report_file_path, "w")
    if not report_file then
        log_message("ERROR: Could not create archive report file.")
        return
    end
    report_file:write("**Archive Report - " .. os.date("%Y-%m-%d %H:%M:%S") .. "**\n")
    report_file:write("**External Media Assets**\n")
    report_file:write("File Name,File Path,Modified Date\n")
    for _, file_path in ipairs(external_files) do
        local modified_date = get_modified_date(file_path)
        report_file:write("\"" .. file_path:match("([^/]+)$") .. "\",\"" .. file_path .. "\",\"" .. (modified_date or "ERROR") .. "\"\n")
    end
    report_file:write("\n**Unused Media Assets**\n")
    report_file:write("File Name,File Path,Modified Date\n")
    for _, file_path in ipairs(unused_files) do
        local modified_date = get_modified_date(file_path)
        report_file:write("\"" .. file_path:match("([^/]+)$") .. "\",\"" .. file_path .. "\",\"" .. (modified_date or "ERROR") .. "\"\n")
    end
    report_file:close()
    log_message("Archive report written to: " .. report_file_path)
    if reaper.GetOS():match("Win") then
        os.execute('explorer /select,"' .. report_file_path .. '"')
    else
        os.execute('open -R "' .. report_file_path .. '"')
    end
end

-- Helper function to move .rpp-undo files to unused media assets
local function move_rpp_undo_files(root_folder)
    local unused_folder = root_folder .. "/" .. UNUSED_ASSETS_FOLDER .. "/session undos"
    if reaper.GetOS():match("Win") then
        os.execute(string.format('mkdir "%s"', unused_folder))
    else
        os.execute(string.format('mkdir -p "%s"', unused_folder))
    end
    local i = 0
    while true do
        local file_name = reaper.EnumerateFiles(root_folder, i)
        if not file_name then break end
        if file_name:match("%.RPP%-UNDO$") and not file_name:match(reaper.GetProjectName("")) then
            local file_path = root_folder .. "/" .. file_name
            local dest_path = unused_folder .. "/" .. file_name
            os.execute(string.format('mv "%s" "%s"', file_path, dest_path))
            log_message("Moved .rpp-undo file: " .. file_path .. " to " .. dest_path)
        end
        i = i + 1
    end
end

-- Helper function to list and copy used external files
local function handle_used_external_files(master_used_files, root_folder)
    local used_external_files = {}
    for file_path, _ in pairs(master_used_files) do
        if not file_path:match("^" .. root_folder) then
            table.insert(used_external_files, file_path)
            local new_path = copy_to_media_folder(file_path, root_folder)
            for _, rpp_file in ipairs(find_rpp_files(root_folder)) do
                update_rpp_references(rpp_file, file_path, new_path)
            end
            update_media_sources(file_path, new_path)
        end
    end
    return used_external_files
end

-- Main script logic
local function main()
    log_message("Starting CUCO Archival Tool...")
    local root_folder, err = get_root_folder()
    if not root_folder then
        log_message(err)
        return
    end
    log_message("Root Folder: " .. root_folder)
    local rpp_files = find_rpp_files(root_folder)
    if #rpp_files == 0 then
        log_message("No session files found in the root folder.")
        return
    end
    local master_used_files = create_master_used_files_list(rpp_files, root_folder)
    local all_media_files = find_all_media_files_in_session(root_folder)
    log_message("Found " .. #all_media_files .. " media files in the session folder.")
    handle_duplicates(all_media_files, master_used_files, root_folder)
    local unused_files = {}
    local external_files = {}
    for _, file_path in ipairs(all_media_files) do
        if not master_used_files[file_path] then
            if not file_path:match("^" .. root_folder) then
                table.insert(external_files, file_path)
                local new_path = copy_to_media_folder(file_path, root_folder)
                for _, rpp_file in ipairs(rpp_files) do
                    update_rpp_references(rpp_file, file_path, new_path)
                end
                update_media_sources(file_path, new_path)
            else
                table.insert(unused_files, file_path)
                move_to_unused_folder(file_path, root_folder)
            end
        else
            log_message("File is used: " .. file_path)
        end
    end
    move_rpp_undo_files(root_folder)
    local used_external_files = handle_used_external_files(master_used_files, root_folder)
    log_message("Copied " .. #used_external_files .. " used external files to /Media.")
    write_archive_report(root_folder, external_files, unused_files)
    log_message("Script completed successfully.")
end

-- Run the script
main()
