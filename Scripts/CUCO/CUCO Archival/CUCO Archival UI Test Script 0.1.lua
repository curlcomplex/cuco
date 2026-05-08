-- Load ReaImGui and Reaper API
local r = reaper
local ctx = r.ImGui_CreateContext('CUCO Archival Tool GUI') -- Create an ImGui context

-- Configurable options (default values)
local UNUSED_ASSETS_FOLDER = "unused media assets"
local IGNORED_FOLDERS = "RENDER, RENDERS, impulses, impulse"
local VERBOSE_MODE = true
local GENERATE_REPORT = true
local DELETE_UNUSED_FOLDER = false
local OPEN_UNUSED_FOLDER = false
local COPY_SESSION = false
local COPY_LOCATION = ""
local DUPLICATE_HANDLING = 1 -- 1 = "Date Modified", 2 = "Deepest Subfolder"
local MOVE_OLD_SESSIONS = true
local DELETE_OLD_SESSIONS = false
local ORGANIZE_INTO_SUBFOLDERS = true
local DELETE_BACKUPS = false
local DELETE_AUTOSAVES = false
local DELETE_RPP_UNDO = false
local DELETE_PEAKS = false
local COPY_EXTERNAL_ASSETS = false
local BACKUP_FOLDER_NAME = "backup" -- Change this to your backup folder name
local AUTOSAVE_FOLDER_NAME = "AutoSaves" -- Change this to your autosave folder name

-- Helper function to trim whitespace from a string
local function trim(str)
    return str:match("^%s*(.-)%s*$")
end

-- Helper function to get the modified date of a file
local function get_modified_date(file_path)
    local command
    if r.GetOS():match("Win") then
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

-- Helper function to log messages
local function log_message(message)
    local log_file = io.open("archival_log.txt", "a")
    if log_file then
        log_file:write(os.date("%Y-%m-%d %H:%M:%S") .. " - " .. message .. "\n")
        log_file:close()
    end
    if VERBOSE_MODE then
        r.ShowConsoleMsg(message .. "\n")
    end
end

-- Helper function to get the root folder of the current session
local function get_root_folder()
    local media_folder = r.GetProjectPath("")
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

-- Helper function to check if a file is in an ignored folder
local function is_ignored_folder(file_path)
    for folder in IGNORED_FOLDERS:gmatch("[^,]+") do
        folder = trim(folder):lower()
        if file_path:lower():match("/" .. folder .. "/") then
            return true
        end
    end
    return false
end

-- Helper function to move files to the unused media assets folder
local function move_to_unused_folder(file_path, root_folder)
    local unused_folder = root_folder .. "/" .. UNUSED_ASSETS_FOLDER
    local file_type = "other"
    if ORGANIZE_INTO_SUBFOLDERS then
        if file_path:lower():match("%.wav$") or file_path:lower():match("%.aif$") or file_path:lower():match("%.flac$") then
            file_type = "audio"
        elseif file_path:lower():match("%.mp4$") or file_path:lower():match("%.mov$") or file_path:lower():match("%.avi$") then
            file_type = "video"
        elseif file_path:lower():match("%.mid$") or file_path:lower():match("%.midi$") then
            file_type = "midi"
        elseif file_path:lower():match("%.rpp%-undo$") or file_path:lower():match("%.rpp%-bak%-undo$") then
            file_type = "session undos"
        end
    end
    local dest_folder = unused_folder .. (ORGANIZE_INTO_SUBFOLDERS and ("/" .. file_type) or "")
    if r.GetOS():match("Win") then
        os.execute(string.format('mkdir "%s"', dest_folder))
    else
        os.execute(string.format('mkdir -p "%s"', dest_folder))
    end
    local dest_path = dest_folder .. "/" .. file_path:match("([^/]+)$")
    os.execute(string.format('mv "%s" "%s"', file_path, dest_path))
    log_message("Moved unused file: " .. file_path .. " to " .. dest_path)
end

-- Helper function to write archive report to a CSV file
local function write_archive_report(root_folder, unused_files)
    local date_time = os.date("%Y%m%d_%H%M%S")
    local report_file_path = root_folder .. "/archive_report_" .. date_time .. ".csv"
    local report_file = io.open(report_file_path, "w")
    if not report_file then
        log_message("ERROR: Could not create archive report file.")
        return
    end

    -- Write detailed header
    report_file:write("**CUCO Archival Tool Report**\n")
    report_file:write("Generated on: " .. os.date("%Y-%m-%d %H:%M:%S") .. "\n")
    report_file:write("Session Folder: " .. root_folder .. "\n")
    report_file:write("Settings Used:\n")
    report_file:write("  - Delete Unused Assets Folder: " .. tostring(DELETE_UNUSED_FOLDER) .. "\n")
    report_file:write("  - Open Unused Assets Folder: " .. tostring(OPEN_UNUSED_FOLDER) .. "\n")
    report_file:write("  - Move Old Sessions: " .. tostring(MOVE_OLD_SESSIONS) .. "\n")
    report_file:write("  - Delete Old Sessions: " .. tostring(DELETE_OLD_SESSIONS) .. "\n")
    report_file:write("  - Organize Assets into Subfolders: " .. tostring(ORGANIZE_INTO_SUBFOLDERS) .. "\n")
    report_file:write("  - Delete Backups: " .. tostring(DELETE_BACKUPS) .. "\n")
    report_file:write("  - Delete Autosaves: " .. tostring(DELETE_AUTOSAVES) .. "\n")
    report_file:write("  - Delete .rpp-undo Files: " .. tostring(DELETE_RPP_UNDO) .. "\n")
    report_file:write("  - Delete Peaks Files: " .. tostring(DELETE_PEAKS) .. "\n")
    report_file:write("  - Copy External Assets: " .. tostring(COPY_EXTERNAL_ASSETS) .. "\n")
    report_file:write("  - Backup Folder Name: " .. BACKUP_FOLDER_NAME .. "\n")
    report_file:write("  - Autosave Folder Name: " .. AUTOSAVE_FOLDER_NAME .. "\n")
    report_file:write("\n**Unused Media Assets**\n")
    report_file:write("File Name,File Path,Modified Date\n")

    -- Write unused files
    for _, file_path in ipairs(unused_files) do
        local modified_date = get_modified_date(file_path)
        report_file:write("\"" .. file_path:match("([^/]+)$") .. "\",\"" .. file_path .. "\",\"" .. (modified_date or "ERROR") .. "\"\n")
    end
    report_file:close()
    log_message("Archive report written to: " .. report_file_path)
end

-- Helper function to delete the unused assets folder
local function delete_unused_folder(root_folder)
    local unused_folder = root_folder .. "/" .. UNUSED_ASSETS_FOLDER
    if r.GetOS():match("Win") then
        os.execute(string.format('rmdir /s /q "%s"', unused_folder))
    else
        os.execute(string.format('rm -rf "%s"', unused_folder))
    end
    log_message("Deleted unused assets folder: " .. unused_folder)
end

-- Helper function to open the unused assets folder
local function open_unused_folder(root_folder)
    local unused_folder = root_folder .. "/" .. UNUSED_ASSETS_FOLDER
    if r.GetOS():match("Win") then
        os.execute(string.format('explorer "%s"', unused_folder))
    else
        os.execute(string.format('open "%s"', unused_folder))
    end
    log_message("Opened unused assets folder: " .. unused_folder)
end

-- Helper function to copy the archived session to a new location
local function copy_archived_session(root_folder, destination)
    local command
    if r.GetOS():match("Win") then
        command = string.format('xcopy /E /I "%s" "%s"', root_folder, destination)
    else
        command = string.format('cp -r "%s" "%s"', root_folder, destination)
    end
    os.execute(command)
    log_message("Archived session copied to: " .. destination)
end

-- Helper function to move old sessions to a folder called "old sessions"
local function move_old_sessions(root_folder)
    local old_sessions_folder = root_folder .. "/old sessions"
    if r.GetOS():match("Win") then
        os.execute(string.format('mkdir "%s"', old_sessions_folder))
    else
        os.execute(string.format('mkdir -p "%s"', old_sessions_folder))
    end
    local current_session = r.GetProjectName(""):match("([^/\\]+)$"):lower()
    local i = 0
    while true do
        local file_name = r.EnumerateFiles(root_folder, i)
        if not file_name then break end
        if file_name:lower():match("%.rpp$") and file_name:lower() ~= current_session then
            local file_path = root_folder .. "/" .. file_name
            local dest_path = old_sessions_folder .. "/" .. file_name
            os.execute(string.format('mv "%s" "%s"', file_path, dest_path))
            log_message("Moved old session: " .. file_path .. " to " .. dest_path)
        end
        i = i + 1
    end
end

-- Helper function to delete old sessions
local function delete_old_sessions(root_folder)
    local current_session = r.GetProjectName(""):match("([^/\\]+)$"):lower()
    local i = 0
    while true do
        local file_name = r.EnumerateFiles(root_folder, i)
        if not file_name then break end
        if file_name:lower():match("%.rpp$") and file_name:lower() ~= current_session then
            local file_path = root_folder .. "/" .. file_name
            os.execute(string.format('rm -f "%s"', file_path))
            log_message("Deleted old session: " .. file_path)
        end
        i = i + 1
    end
end

-- Helper function to delete backup files/folders
local function delete_backups(root_folder)
    -- Delete .rpp-bak files
    local command
    if r.GetOS():match("Win") then
        command = string.format('forfiles /P "%s" /M "*.rpp-bak" /C "cmd /c del /f /q @path"', root_folder)
    else
        command = string.format('find "%s" -name "*.rpp-bak" -exec rm -f {} +', root_folder)
    end
    os.execute(command)
    log_message("Deleted .rpp-bak files")

    -- Delete backup folder
    local backup_folder_path = root_folder .. "/" .. BACKUP_FOLDER_NAME
    if r.GetOS():match("Win") then
        command = string.format('rmdir /s /q "%s"', backup_folder_path)
    else
        command = string.format('rm -rf "%s"', backup_folder_path)
    end
    os.execute(command)
    log_message("Deleted backup folder: " .. backup_folder_path)
end

-- Helper function to delete autosave files/folders
local function delete_autosaves(root_folder)
    -- Delete autosave folder
    local autosave_folder_path = root_folder .. "/" .. AUTOSAVE_FOLDER_NAME
    if r.GetOS():match("Win") then
        command = string.format('rmdir /s /q "%s"', autosave_folder_path)
    else
        command = string.format('rm -rf "%s"', autosave_folder_path)
    end
    os.execute(command)
    log_message("Deleted autosave folder: " .. autosave_folder_path)
end

-- Helper function to delete or move .rpp-undo and .rpp-bak-undo files
local function handle_rpp_undo_files(root_folder)
    local i = 0
    while true do
        local file_name = r.EnumerateFiles(root_folder, i)
        if not file_name then break end
        if file_name:lower():match("%.rpp%-undo$") or file_name:lower():match("%.rpp%-bak%-undo$") then
            local file_path = root_folder .. "/" .. file_name
            if DELETE_RPP_UNDO then
                os.execute(string.format('rm -f "%s"', file_path))
                log_message("Deleted .rpp-undo file: " .. file_path)
            else
                local session_name = file_name:match("(.+)%.rpp%-undo$"):lower()
                local session_folder = root_folder .. "/" .. session_name
                if r.GetOS():match("Win") then
                    os.execute(string.format('mkdir "%s"', session_folder))
                else
                    os.execute(string.format('mkdir -p "%s"', session_folder))
                end
                local dest_path = session_folder .. "/" .. file_name
                os.execute(string.format('mv "%s" "%s"', file_path, dest_path))
                log_message("Moved .rpp-undo file: " .. file_path .. " to " .. dest_path)
            end
        end
        i = i + 1
    end
end

-- Helper function to delete peak files
local function delete_peak_files(root_folder)
    local i = 0
    while true do
        local file_name = r.EnumerateFiles(root_folder, i)
        if not file_name then break end
        if file_name:lower():match("%.reapeaks$") then
            local file_path = root_folder .. "/" .. file_name
            os.execute(string.format('rm -f "%s"', file_path))
            log_message("Deleted peak file: " .. file_path)
        end
        i = i + 1
    end
end

-- Helper function to copy assets from external sources
local function copy_external_assets(root_folder)
    local media_folder = root_folder .. "/Media"
    if r.GetOS():match("Win") then
        os.execute(string.format('mkdir "%s"', media_folder))
    else
        os.execute(string.format('mkdir -p "%s"', media_folder))
    end

    local i = 0
    while true do
        local file_name = r.EnumerateFiles(root_folder, i)
        if not file_name then break end
        if not file_name:match("^" .. root_folder) then
            local file_path = root_folder .. "/" .. file_name
            local dest_path = media_folder .. "/" .. file_name
            os.execute(string.format('cp "%s" "%s"', file_path, dest_path))
            log_message("Copied external asset: " .. file_path .. " to " .. dest_path)
        end
        i = i + 1
    end
end

-- Main archival function
local function run_archival_process()
    log_message("Starting CUCO Archival Tool...")
    local root_folder = get_root_folder()
    if not root_folder then return end

    -- Move or delete old sessions
    if MOVE_OLD_SESSIONS and not DELETE_OLD_SESSIONS then
        move_old_sessions(root_folder)
    elseif DELETE_OLD_SESSIONS then
        delete_old_sessions(root_folder)
    end

    -- Delete backup files/folders
    if DELETE_BACKUPS then
        delete_backups(root_folder)
    end

    -- Delete autosave files/folders
    if DELETE_AUTOSAVES then
        delete_autosaves(root_folder)
    end

    -- Handle .rpp-undo and .rpp-bak-undo files
    handle_rpp_undo_files(root_folder)

    -- Delete peak files
    if DELETE_PEAKS then
        delete_peak_files(root_folder)
    end

    -- Copy assets from external sources
    if COPY_EXTERNAL_ASSETS then
        copy_external_assets(root_folder)
    end

    -- Find all media files in the session folder
    local all_media_files = {}
    local command
    local extensions = {
        ".AIF", ".AIFF", ".AVI", ".BWF", ".CDA", ".DAT", ".EDL", ".FLAC", ".GIF", ".JPEG", 
        ".JPG", ".KAR", ".LCF", ".M4A", ".M4V", ".MID", ".MIDI", ".MKV", ".MOGG", ".MOV", 
        ".MP2", ".MP3", ".MP4", ".MPEG", ".MPG", ".MUSICXML", ".MXL", ".OGG", ".OGV", 
        ".OPUS", ".PNG", ".QT", ".RCY", ".REX", ".RMI", ".RX2", ".SYX", ".W64", ".WAV", 
        ".WEBM", ".WMA", ".WMV", ".WV", ".XML"
    }
    if r.GetOS():match("Win") then
        local pattern = ""
        for _, ext in ipairs(extensions) do
            pattern = pattern .. string.format('"%s\\*%s" ', root_folder, ext)
        end
        command = string.format('dir /s /b %s', pattern)
    else
        local pattern = ""
        for _, ext in ipairs(extensions) do
            pattern = pattern .. string.format('-iname "*%s" -o ', ext)
        end
        pattern = pattern:sub(1, -5)
        command = string.format('find "%s" -type f \\( %s \\)', root_folder, pattern)
    end
    local handle = io.popen(command)
    if handle then
        for file_path in handle:lines() do
            file_path = file_path:gsub("\\", "/")
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

    -- Move unused files
    local unused_files = {}
    for _, file_path in ipairs(all_media_files) do
        move_to_unused_folder(file_path, root_folder)
        table.insert(unused_files, file_path)
    end

    -- Generate archive report
    if GENERATE_REPORT then
        write_archive_report(root_folder, unused_files)
    end

    -- Delete unused assets folder if enabled
    if DELETE_UNUSED_FOLDER then
        delete_unused_folder(root_folder)
    end

    -- Open unused assets folder if enabled
    if OPEN_UNUSED_FOLDER and not DELETE_UNUSED_FOLDER then
        open_unused_folder(root_folder)
    end

    -- Copy archived session if enabled
    if COPY_SESSION and COPY_LOCATION ~= "" then
        copy_archived_session(root_folder, COPY_LOCATION)
    end

    log_message("Archival process completed.")
end

-- Function to save settings to a file
local function save_settings()
    local settings_file = io.open("cuco_archival_tool_settings.ini", "w")
    if settings_file then
        settings_file:write("UNUSED_ASSETS_FOLDER=" .. UNUSED_ASSETS_FOLDER .. "\n")
        settings_file:write("IGNORED_FOLDERS=" .. IGNORED_FOLDERS .. "\n")
        settings_file:write("VERBOSE_MODE=" .. tostring(VERBOSE_MODE) .. "\n")
        settings_file:write("GENERATE_REPORT=" .. tostring(GENERATE_REPORT) .. "\n")
        settings_file:write("DELETE_UNUSED_FOLDER=" .. tostring(DELETE_UNUSED_FOLDER) .. "\n")
        settings_file:write("OPEN_UNUSED_FOLDER=" .. tostring(OPEN_UNUSED_FOLDER) .. "\n")
        settings_file:write("COPY_SESSION=" .. tostring(COPY_SESSION) .. "\n")
        settings_file:write("COPY_LOCATION=" .. COPY_LOCATION .. "\n")
        settings_file:write("DUPLICATE_HANDLING=" .. tostring(DUPLICATE_HANDLING) .. "\n")
        settings_file:write("MOVE_OLD_SESSIONS=" .. tostring(MOVE_OLD_SESSIONS) .. "\n")
        settings_file:write("DELETE_OLD_SESSIONS=" .. tostring(DELETE_OLD_SESSIONS) .. "\n")
        settings_file:write("ORGANIZE_INTO_SUBFOLDERS=" .. tostring(ORGANIZE_INTO_SUBFOLDERS) .. "\n")
        settings_file:write("DELETE_BACKUPS=" .. tostring(DELETE_BACKUPS) .. "\n")
        settings_file:write("DELETE_AUTOSAVES=" .. tostring(DELETE_AUTOSAVES) .. "\n")
        settings_file:write("DELETE_RPP_UNDO=" .. tostring(DELETE_RPP_UNDO) .. "\n")
        settings_file:write("DELETE_PEAKS=" .. tostring(DELETE_PEAKS) .. "\n")
        settings_file:write("COPY_EXTERNAL_ASSETS=" .. tostring(COPY_EXTERNAL_ASSETS) .. "\n")
        settings_file:write("BACKUP_FOLDER_NAME=" .. BACKUP_FOLDER_NAME .. "\n")
        settings_file:write("AUTOSAVE_FOLDER_NAME=" .. AUTOSAVE_FOLDER_NAME .. "\n")
        settings_file:close()
    end
end

-- Function to load settings from a file
local function load_settings()
    local settings_file = io.open("cuco_archival_tool_settings.ini", "r")
    if settings_file then
        for line in settings_file:lines() do
            local key, value = line:match("([^=]+)=(.+)")
            if key and value then
                if key == "UNUSED_ASSETS_FOLDER" then
                    UNUSED_ASSETS_FOLDER = value
                elseif key == "IGNORED_FOLDERS" then
                    IGNORED_FOLDERS = value
                elseif key == "VERBOSE_MODE" then
                    VERBOSE_MODE = value == "true"
                elseif key == "GENERATE_REPORT" then
                    GENERATE_REPORT = value == "true"
                elseif key == "DELETE_UNUSED_FOLDER" then
                    DELETE_UNUSED_FOLDER = value == "true"
                elseif key == "OPEN_UNUSED_FOLDER" then
                    OPEN_UNUSED_FOLDER = value == "true"
                elseif key == "COPY_SESSION" then
                    COPY_SESSION = value == "true"
                elseif key == "COPY_LOCATION" then
                    COPY_LOCATION = value
                elseif key == "DUPLICATE_HANDLING" then
                    DUPLICATE_HANDLING = tonumber(value)
                elseif key == "MOVE_OLD_SESSIONS" then
                    MOVE_OLD_SESSIONS = value == "true"
                elseif key == "DELETE_OLD_SESSIONS" then
                    DELETE_OLD_SESSIONS = value == "true"
                elseif key == "ORGANIZE_INTO_SUBFOLDERS" then
                    ORGANIZE_INTO_SUBFOLDERS = value == "true"
                elseif key == "DELETE_BACKUPS" then
                    DELETE_BACKUPS = value == "true"
                elseif key == "DELETE_AUTOSAVES" then
                    DELETE_AUTOSAVES = value == "true"
                elseif key == "DELETE_RPP_UNDO" then
                    DELETE_RPP_UNDO = value == "true"
                elseif key == "DELETE_PEAKS" then
                    DELETE_PEAKS = value == "true"
                elseif key == "COPY_EXTERNAL_ASSETS" then
                    COPY_EXTERNAL_ASSETS = value == "true"
                elseif key == "BACKUP_FOLDER_NAME" then
                    BACKUP_FOLDER_NAME = value
                elseif key == "AUTOSAVE_FOLDER_NAME" then
                    AUTOSAVE_FOLDER_NAME = value
                end
            end
        end
        settings_file:close()
    end
end

-- Function to create the GUI
function create_gui()
    -- Begin a new ImGui window
    local visible, open = r.ImGui_Begin(ctx, 'CUCO Archival Tool', true, r.ImGui_WindowFlags_None())
    if visible then
        -- Add a help button
        if r.ImGui_Button(ctx, 'Help') then
            r.ImGui_OpenPopup(ctx, 'Help Popup')
        end

        -- Help popup
        if r.ImGui_BeginPopup(ctx, 'Help Popup') then
            r.ImGui_Text(ctx, "CUCO Archival Tool v1.3")
            r.ImGui_Text(ctx, "This script helps archive Reaper sessions by:")
            r.ImGui_BulletText(ctx, "Copying external files into the 'Media' folder.")
            r.ImGui_BulletText(ctx, "Moving unused files into the 'unused media assets' folder.")
            r.ImGui_BulletText(ctx, "Handling duplicate files (keeping the newest or deepest).")
            r.ImGui_BulletText(ctx, "Updating file references in .rpp files.")
            r.ImGui_BulletText(ctx, "Organizing unused files into subfolders by type.")
            r.ImGui_BulletText(ctx, "Scans all sessions in the project folder to find all assets needed for all versions of the project.")
            r.ImGui_EndPopup(ctx)
        end

        -- Add a toggle for verbose mode
        local verbose_changed, verbose_state = r.ImGui_Checkbox(ctx, 'Verbose Mode', VERBOSE_MODE)
        if verbose_changed then
            VERBOSE_MODE = verbose_state
            save_settings()
        end
        if r.ImGui_IsItemHovered(ctx) and r.ImGui_GetTime(ctx) > 1 then
            r.ImGui_SetTooltip(ctx, "Logs detailed messages to the console and log file for debugging.")
        end

        -- Add a toggle for generating the archive report
        local report_changed, report_state = r.ImGui_Checkbox(ctx, 'Generate Archive Report', GENERATE_REPORT)
        if report_changed then
            GENERATE_REPORT = report_state
            save_settings()
        end
        if r.ImGui_IsItemHovered(ctx) and r.ImGui_GetTime(ctx) > 1 then
            r.ImGui_SetTooltip(ctx, "Generates a CSV report of unused files.")
        end

        -- Add a toggle for deleting the unused assets folder
        local delete_changed, delete_state = r.ImGui_Checkbox(ctx, 'Delete Unused Assets Folder', DELETE_UNUSED_FOLDER)
        if delete_changed then
            DELETE_UNUSED_FOLDER = delete_state
            save_settings()
        end
        if r.ImGui_IsItemHovered(ctx) and r.ImGui_GetTime(ctx) > 1 then
            r.ImGui_SetTooltip(ctx, "Deletes the unused assets folder after archiving.")
        end

        -- Add a toggle for opening the unused assets folder (hidden if delete is checked)
        if not DELETE_UNUSED_FOLDER then
            local open_changed, open_state = r.ImGui_Checkbox(ctx, 'Open Unused Assets Folder (on completion)', OPEN_UNUSED_FOLDER)
            if open_changed then
                OPEN_UNUSED_FOLDER = open_state
                save_settings()
            end
            if r.ImGui_IsItemHovered(ctx) and r.ImGui_GetTime(ctx) > 1 then
                r.ImGui_SetTooltip(ctx, "Opens the unused assets folder after archiving.")
            end
        end

        -- Add a dropdown for duplicate handling
        local duplicate_handling_options = "Date Modified\0Deepest Subfolder\0"
        local changed, new_option = r.ImGui_Combo(ctx, 'Duplicate Handling', DUPLICATE_HANDLING, duplicate_handling_options)
        if changed then
            DUPLICATE_HANDLING = new_option
            save_settings()
        end
        if r.ImGui_IsItemHovered(ctx) and r.ImGui_GetTime(ctx) > 1 then
            r.ImGui_SetTooltip(ctx, "Choose how to handle duplicate files: by date modified or deepest subfolder.")
        end

        -- Add a toggle for moving old sessions
        local move_changed, move_state = r.ImGui_Checkbox(ctx, 'Move Old Sessions to "old sessions" Folder', MOVE_OLD_SESSIONS)
        if move_changed then
            MOVE_OLD_SESSIONS = move_state
            save_settings()
        end
        if r.ImGui_IsItemHovered(ctx) and r.ImGui_GetTime(ctx) > 1 then
            r.ImGui_SetTooltip(ctx, "Moves all sessions in the main folder (except the current one) to a folder called 'old sessions'.")
        end

        -- Add a toggle for deleting old sessions
        local delete_old_changed, delete_old_state = r.ImGui_Checkbox(ctx, 'Delete Old Sessions', DELETE_OLD_SESSIONS)
        if delete_old_changed then
            DELETE_OLD_SESSIONS = delete_old_state
            save_settings()
        end
        if r.ImGui_IsItemHovered(ctx) and r.ImGui_GetTime(ctx) > 1 then
            r.ImGui_SetTooltip(ctx, "Deletes all sessions in the main folder (except the current one).")
        end

        -- Add a toggle for organizing into subfolders
        local organize_changed, organize_state = r.ImGui_Checkbox(ctx, 'Organize Assets into Subfolders', ORGANIZE_INTO_SUBFOLDERS)
        if organize_changed then
            ORGANIZE_INTO_SUBFOLDERS = organize_state
            save_settings()
        end
        if r.ImGui_IsItemHovered(ctx) and r.ImGui_GetTime(ctx) > 1 then
            r.ImGui_SetTooltip(ctx, "Organizes unused assets into subfolders by type.")
        end

        -- Add a toggle for deleting backup files/folders
        local backup_changed, backup_state = r.ImGui_Checkbox(ctx, 'Delete Backup Files/Folders', DELETE_BACKUPS)
        if backup_changed then
            DELETE_BACKUPS = backup_state
            save_settings()
        end
        if r.ImGui_IsItemHovered(ctx) and r.ImGui_GetTime(ctx) > 1 then
            r.ImGui_SetTooltip(ctx, "Deletes backup files/folders. Default folder name: " .. BACKUP_FOLDER_NAME .. ". Change this in the script header.")
        end

        -- Add a toggle for deleting autosave files/folders
        local autosave_changed, autosave_state = r.ImGui_Checkbox(ctx, 'Delete Autosave Files/Folders', DELETE_AUTOSAVES)
        if autosave_changed then
            DELETE_AUTOSAVES = autosave_state
            save_settings()
        end
        if r.ImGui_IsItemHovered(ctx) and r.ImGui_GetTime(ctx) > 1 then
            r.ImGui_SetTooltip(ctx, "Deletes autosave files/folders. Default folder name: " .. AUTOSAVE_FOLDER_NAME .. ". Change this in the script header.")
        end

        -- Add a toggle for deleting .rpp-undo files
        local rpp_undo_changed, rpp_undo_state = r.ImGui_Checkbox(ctx, 'Delete .rpp-undo Files', DELETE_RPP_UNDO)
        if rpp_undo_changed then
            DELETE_RPP_UNDO = rpp_undo_state
            save_settings()
        end
        if r.ImGui_IsItemHovered(ctx) and r.ImGui_GetTime(ctx) > 1 then
            r.ImGui_SetTooltip(ctx, "Deletes all .rpp-undo files.")
        end

        -- Add a toggle for deleting peak files
        local peaks_changed, peaks_state = r.ImGui_Checkbox(ctx, 'Delete Peak Files', DELETE_PEAKS)
        if peaks_changed then
            DELETE_PEAKS = peaks_state
            save_settings()
        end
        if r.ImGui_IsItemHovered(ctx) and r.ImGui_GetTime(ctx) > 1 then
            r.ImGui_SetTooltip(ctx, "Deletes all peak files in the project.")
        end

        -- Add a toggle for copying external assets
        local copy_external_changed, copy_external_state = r.ImGui_Checkbox(ctx, 'Copy Assets from External Sources', COPY_EXTERNAL_ASSETS)
        if copy_external_changed then
            COPY_EXTERNAL_ASSETS = copy_external_state
            save_settings()
        end
        if r.ImGui_IsItemHovered(ctx) and r.ImGui_GetTime(ctx) > 1 then
            r.ImGui_SetTooltip(ctx, "Copies assets from external sources into the project folder.")
        end

        -- Add a toggle for copying the archived session
        local copy_changed, copy_state = r.ImGui_Checkbox(ctx, 'Copy Archived Session', COPY_SESSION)
        if copy_changed then
            COPY_SESSION = copy_state
            save_settings()
        end
        if r.ImGui_IsItemHovered(ctx) and r.ImGui_GetTime(ctx) > 1 then
            r.ImGui_SetTooltip(ctx, "Copies the archived session to a new location.")
        end

        -- Add an input field for the copy location
        if COPY_SESSION then
            local copy_location_buffer = COPY_LOCATION
            local location_changed, new_location = r.ImGui_InputText(ctx, 'Copy Location', copy_location_buffer)
            if location_changed then
                COPY_LOCATION = new_location
                save_settings()
            end
            if r.ImGui_IsItemHovered(ctx) and r.ImGui_GetTime(ctx) > 1 then
                r.ImGui_SetTooltip(ctx, "The destination folder for the archived session.")
            end

            -- Add a button to open a file dialog for the copy location
            if r.ImGui_Button(ctx, 'Browse...') then
                local retval, folder_path = r.GetUserFileNameForRead("", "Select Copy Location", "")
                if retval then
                    COPY_LOCATION = folder_path
                    save_settings()
                end
            end
        end

        -- Add an input field for excluded folders
        local ignored_folders_buffer = IGNORED_FOLDERS
        local ignored_changed, new_ignored_folders = r.ImGui_InputText(ctx, 'Excluded Folders (comma-separated)', ignored_folders_buffer)
        if ignored_changed then
            IGNORED_FOLDERS = new_ignored_folders
            save_settings()
        end
        if r.ImGui_IsItemHovered(ctx) and r.ImGui_GetTime(ctx) > 1 then
            r.ImGui_SetTooltip(ctx, "Folders to ignore during the archival process.")
        end

        -- Add a button to start the archival process at the bottom
        r.ImGui_Separator(ctx)
        if r.ImGui_Button(ctx, 'Start Archival Process') then
            run_archival_process()
        end

        -- End the ImGui window
        r.ImGui_End(ctx)
    end

    -- Return whether the window is still open
    return open
end

-- Main loop to keep the GUI open
function main()
    -- Load settings from file
    load_settings()

    -- Set the window size (width, height, condition)
    r.ImGui_SetNextWindowSize(ctx, 450, 600, r.ImGui_Cond_FirstUseEver())

    -- Create the GUI and check if the window is still open
    local open = create_gui()

    -- If the window is closed, stop the script
    if not open then
        return
    end

    -- Continue running the script to keep the GUI open
    r.defer(main)
end

-- Start the script
main()
