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
local BACKUP_FOLDER_NAME = "backups" -- Changed to "backups"
local AUTOSAVE_FOLDER_NAME = "AutoSaves" -- Change this to your autosave folder name

-- Helper functions (trim, get_modified_date, log_message, etc.) remain the same as in your original script

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
