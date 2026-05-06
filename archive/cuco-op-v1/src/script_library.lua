-- CUCO-OP Script Library Management
-- Handles persistent storage and organization of user scripts and templates

local script_library = {}

-- Library structure
local SCRIPTS_DIR = "scripts"
local LIBRARY_FILE = SCRIPTS_DIR .. "/library.json"

-- Default library structure
local function create_default_library()
    return {
        version = "1.0",
        folders = {
            {
                id = "templates",
                name = "Templates",
                type = "builtin",
                expanded = true,
                children = {}
            },
            {
                id = "projects", 
                name = "Projects",
                type = "user",
                expanded = true,
                children = {}
            },
            {
                id = "tests",
                name = "Tests", 
                type = "user",
                expanded = false,
                children = {}
            }
        },
        scripts = {},
        next_id = 1
    }
end

-- Generate unique ID
local function generate_id(library)
    local id = "script_" .. library.next_id
    library.next_id = library.next_id + 1
    return id
end

-- File I/O utilities
local function file_exists(path)
    local f = io.open(path, "r")
    if f then
        f:close()
        return true
    end
    return false
end

local function read_file(path)
    local f = io.open(path, "r")
    if not f then return nil end
    local content = f:read("*all")
    f:close()
    return content
end

local function write_file(path, content)
    local f = io.open(path, "w")
    if not f then return false end
    f:write(content)
    f:close()
    return true
end

-- JSON utilities (simple implementation)
local function json_encode(obj)
    if type(obj) == "table" then
        local items = {}
        local is_array = true
        local count = 0
        
        -- Check if it's an array
        for k, v in pairs(obj) do
            count = count + 1
            if type(k) ~= "number" or k ~= count then
                is_array = false
                break
            end
        end
        
        if is_array then
            for i, v in ipairs(obj) do
                table.insert(items, json_encode(v))
            end
            return "[" .. table.concat(items, ",") .. "]"
        else
            for k, v in pairs(obj) do
                local key = '"' .. tostring(k) .. '"'
                local value = json_encode(v)
                table.insert(items, key .. ":" .. value)
            end
            return "{" .. table.concat(items, ",") .. "}"
        end
    elseif type(obj) == "string" then
        return '"' .. obj:gsub('"', '\\"'):gsub("\n", "\\n") .. '"'
    elseif type(obj) == "number" then
        return tostring(obj)
    elseif type(obj) == "boolean" then
        return obj and "true" or "false"
    else
        return "null"
    end
end

local function json_decode(str)
    -- Simple JSON decoder - in production would use proper JSON library
    -- For now, return default library if parsing fails
    return create_default_library()
end

-- Library management functions
function script_library.load_library()
    if not file_exists(LIBRARY_FILE) then
        local library = create_default_library()
        script_library.save_library(library)
        return library
    end
    
    local content = read_file(LIBRARY_FILE)
    if not content then
        return create_default_library()
    end
    
    local library = json_decode(content)
    return library or create_default_library()
end

function script_library.save_library(library)
    local json_str = json_encode(library)
    return write_file(LIBRARY_FILE, json_str)
end

-- Script operations
function script_library.add_script(library, folder_id, name, code)
    local script_id = generate_id(library)
    local timestamp = os.time()
    
    local script = {
        id = script_id,
        name = name,
        folder_id = folder_id,
        code = code,
        created = timestamp,
        modified = timestamp
    }
    
    library.scripts[script_id] = script
    
    -- Add to folder's children
    for _, folder in ipairs(library.folders) do
        if folder.id == folder_id then
            table.insert(folder.children, script_id)
            break
        end
    end
    
    return script_id
end

function script_library.get_script(library, script_id)
    return library.scripts[script_id]
end

function script_library.update_script(library, script_id, name, code)
    local script = library.scripts[script_id]
    if script then
        script.name = name or script.name
        script.code = code or script.code
        script.modified = os.time()
        return true
    end
    return false
end

function script_library.delete_script(library, script_id)
    local script = library.scripts[script_id]
    if not script then return false end
    
    -- Remove from folder's children
    for _, folder in ipairs(library.folders) do
        if folder.id == script.folder_id then
            for i, child_id in ipairs(folder.children) do
                if child_id == script_id then
                    table.remove(folder.children, i)
                    break
                end
            end
            break
        end
    end
    
    library.scripts[script_id] = nil
    return true
end

-- Folder operations  
function script_library.add_folder(library, parent_id, name)
    local folder_id = generate_id(library)
    
    local folder = {
        id = folder_id,
        name = name,
        type = "user",
        expanded = true,
        children = {}
    }
    
    if parent_id then
        -- Add as subfolder to existing folder
        for _, folder_ref in ipairs(library.folders) do
            if folder_ref.id == parent_id then
                table.insert(folder_ref.children or {}, folder_id)
                break
            end
        end
        library.subfolders = library.subfolders or {}
        library.subfolders[folder_id] = folder
    else
        table.insert(library.folders, folder)
    end
    
    return folder_id
end

function script_library.find_folder(library, folder_id)
    -- Check main folders first
    for _, folder in ipairs(library.folders) do
        if folder.id == folder_id then
            return folder
        end
    end
    
    -- Check subfolders
    if library.subfolders and library.subfolders[folder_id] then
        return library.subfolders[folder_id]
    end
    
    -- Check template categories
    if library.template_categories and library.template_categories[folder_id] then
        return library.template_categories[folder_id]
    end
    
    return nil
end

function script_library.get_session_folder(library)
    -- Get current REAPER project name
    local session_name = "Unsaved Session"
    
    -- Try to get project name (REAPER API call)
    if reaper and reaper.GetProjectName then
        local proj_name = reaper.GetProjectName(0, "")
        if proj_name and proj_name ~= "" then
            -- Remove file extension if present
            session_name = proj_name:match("(.+)%..+$") or proj_name
        end
    end
    
    -- Sanitize folder name
    session_name = session_name:gsub("[^%w%s%-_%.]", "_")
    
    local session_folder_id = "session_" .. session_name:lower():gsub("%s+", "_")
    
    -- Check if session folder already exists
    local existing_folder = script_library.find_folder(library, session_folder_id)
    if existing_folder then
        return session_folder_id
    end
    
    -- Create new session folder under Projects
    local folder_id = script_library.add_folder(library, "projects", session_name)
    
    -- Update the folder ID to be session-specific
    local projects_folder = script_library.find_folder(library, "projects")
    if projects_folder then
        -- Find and update the folder we just added
        for i, child_id in ipairs(projects_folder.children) do
            if child_id == folder_id then
                projects_folder.children[i] = session_folder_id
                break
            end
        end
        
        -- Update the actual folder
        if library.subfolders and library.subfolders[folder_id] then
            library.subfolders[folder_id].id = session_folder_id
            library.subfolders[session_folder_id] = library.subfolders[folder_id]
            library.subfolders[folder_id] = nil
        end
    end
    
    return session_folder_id
end

function script_library.delete_folder(library, folder_id)
    -- Remove from main folders
    for i, folder in ipairs(library.folders) do
        if folder.id == folder_id then
            table.remove(library.folders, i)
            return true
        end
    end
    
    -- Remove from subfolders
    if library.subfolders and library.subfolders[folder_id] then
        library.subfolders[folder_id] = nil
        -- Also remove reference from parent
        for _, folder in ipairs(library.folders) do
            if folder.children then
                for i, child_id in ipairs(folder.children) do
                    if child_id == folder_id then
                        table.remove(folder.children, i)
                        break
                    end
                end
            end
        end
        return true
    end
    
    return false
end

return script_library
