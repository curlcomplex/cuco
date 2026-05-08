--[[
  CUCO Archival Tool v2.0 — Polished Edition
  Dependencies: dkjson.lua (place in script dir)
--]]

local r = reaper
local ctx = r.ImGui_CreateContext("CUCO Archival Tool GUI")
local json = assert(loadfile(r.GetResourcePath() .. "/Scripts/dkjson.lua"))()

-- ==== Defaults / Config ====
local CONFIG_FILE = r.GetResourcePath() .. "/Scripts/cuco_config.json"
local default_cfg = {
  UNUSED_ASSETS_FOLDER    = "unused media assets",
  IGNORED_FOLDERS         = { "RENDER", "RENDERS", "impulses", "impulse" },
  VERBOSE_MODE            = true,
  GENERATE_REPORT         = true,
  DELETE_UNUSED_FOLDER    = false,
  OPEN_UNUSED_FOLDER      = false,
  COPY_SESSION            = false,
  COPY_LOCATION           = "",
  DUPLICATE_HANDLING      = 1,        -- 1=Date Modified, 2=Deepest Subfolder
  MOVE_OLD_SESSIONS       = true,
  DELETE_OLD_SESSIONS     = false,
  ORGANIZE_INTO_SUBFOLDERS= true,
  DELETE_BACKUPS          = false,
  DELETE_AUTOSAVES        = false,
  DELETE_RPP_UNDO         = false,
  DELETE_PEAKS            = false,
  COPY_EXTERNAL_ASSETS    = false,
  BACKUP_FOLDER_NAME      = "backups",
  AUTOSAVE_FOLDER_NAME    = "AutoSaves",
}

local cfg = {}

-- ==== Utils ====
local function log(msg)
  if cfg.VERBOSE_MODE then r.ShowConsoleMsg(msg.."\n") end
  local f = io.open("cuco_archival_log.txt","a")
  if f then f:write(os.date("%Y-%m-%d %H:%M:%S").."  "..msg.."\n"); f:close() end
end

-- Normalize paths to use forward slashes
local function norm_path(p) return p:gsub("\\", "/") end

-- Load or create config
local function load_config()
  local f = io.open(CONFIG_FILE, "r")
  if f then
    local txt = f:read("*a"); f:close()
    local parsed, _, err = json.decode(txt)
    if parsed then
      for k,v in pairs(default_cfg) do cfg[k] = parsed[k] ~= nil and parsed[k] or v end
      return
    end
    log("Error parsing config: "..err)
  end
  -- fallback: copy defaults
  for k,v in pairs(default_cfg) do cfg[k] = v end
end

-- Save config
local function save_config()
  local f = io.open(CONFIG_FILE, "w")
  if f then
    f:write(json.encode(cfg, { indent = true })) 
    f:close()
  else
    log("ERROR: Unable to save config.")
  end
end

-- Generic processor: applies action to all files matching predicate
local function process_files(root, pred, action)
  local total, done = 0, 0
  local function scan(dir)
    -- files
    local i = 0
    while true do
      local fn = r.EnumerateFiles(dir, i)
      if not fn then break end
      local fp = dir .. "/" .. fn
      if pred(fp) then
        total = total + 1
      end
      i = i + 1
    end
    -- subdirs
    local j = 0
    while true do
      local sd = r.EnumerateSubdirectories(dir, j)
      if not sd then break end
      scan(dir .. "/" .. sd)
      j = j + 1
    end
  end

  scan(root)
  -- actual processing with progress bar
  local function do_action(dir)
    local i = 0
    while true do
      local fn = r.EnumerateFiles(dir, i)
      if not fn then break end
      local fp = dir .. "/" .. fn
      if pred(fp) then
        local ok, err = pcall(action, fp)
        if not ok then log("Error on "..fp..": "..err) end
        done = done + 1
        r.ImGui_ProgressBar(ctx, done/total, nil, 
          string.format("Processing %d/%d", done, total))
      end
      i = i + 1
    end
    local j = 0
    while true do
      local sd = r.EnumerateSubdirectories(dir, j)
      if not sd then break end
      do_action(dir.."/"..sd)
      j = j + 1
    end
  end

  do_action(root)
end

-- Various predicates & actions:
local function is_ignored(fp)
  local lower = fp:lower()
  for _,fld in ipairs(cfg.IGNORED_FOLDERS) do
    if lower:match("/" .. fld:lower() .. "/") then return true end
  end
  return false
end

local function is_media(fp)
  local exts = { "%.wav$", "%.aif$", "%.flac$", "%.mp3$", "%.mid$", "%.rpp%-undo$", "%.reapeaks$" }
  for _,e in ipairs(exts) do
    if fp:lower():match(e) then return true end
  end
  return false
end

local function move_to_unused(fp)
  local root = norm_path(r.GetProjectPath("")):match("^(.*)/")
  local uf = root .. "/" .. cfg.UNUSED_ASSETS_FOLDER
  local sub = ""
  if cfg.ORGANIZE_INTO_SUBFOLDERS then
    if fp:lower():match("%.wav$") then sub = "/audio"
    elseif fp:lower():match("%.mid$") then sub = "/midi"
    elseif fp:lower():match("%.rpp%-undo$") then sub = "/undo"
    elseif fp:lower():match("%.reapeaks$") then sub = "/peaks" end
  end
  os.execute(string.format('mkdir -p "%s%s"', uf, sub))
  os.rename(fp, uf..sub.."/"..fp:match("([^/]+)$"))
  log("Moved: "..fp.." → "..uf..sub)
end

-- (Similar actions for delete peaks, backups, etc.)

-- ==== Report Writer ====
local function write_report(unused_list)
  local root = norm_path(r.GetProjectPath("")):match("^(.*)/")
  local fname = string.format("archive_report_%s.csv", os.date("%Y%m%d_%H%M%S"))
  local full = root.."/"..fname
  local f = io.open(full,"w")
  if not f then return log("Unable to write report") end
  f:write("File,Original Path,Modified\n")
  for _,fp in ipairs(unused_list) do
    local attr = r.EnumerateProjectMarkers2(0)--placeholder for real date fetch
    f:write(string.format("%q,%q,%q\n",
      fp:match("([^/]+)$"), fp, os.date("%Y-%m-%d %H:%M:%S")))
  end
  f:close()
  log("Report saved: "..full)
end

-- ==== GUI ====
local summary = { moved=0, deleted=0 }

local function create_gui()
  local visible, open = r.ImGui_Begin(ctx, "CUCO Archival Tool", true)
  if visible then
    if r.ImGui_Button(ctx, "Help") then r.ImGui_OpenPopup(ctx, "Help") end
    if r.ImGui_BeginPopup(ctx, "Help") then
      r.ImGui_Text(ctx, "CUCO Archival Tool v2.0")
      r.ImGui_BulletText(ctx, "Clean, archive, and report on your Reaper sessions")
      r.ImGui_EndPopup(ctx)
    end

    -- Session Cleanup
    if r.ImGui_CollapsingHeader(ctx, "Session Cleanup", 
          r.ImGui_TreeNodeFlags_DefaultOpen()) then
      cfg.MOVE_OLD_SESSIONS = select(2, r.ImGui_Checkbox(ctx, 
        'Move Old Sessions', cfg.MOVE_OLD_SESSIONS))
      cfg.DELETE_OLD_SESSIONS = select(2, r.ImGui_Checkbox(ctx, 
        'Delete Old Sessions', cfg.DELETE_OLD_SESSIONS))
      cfg.DELETE_BACKUPS      = select(2, r.ImGui_Checkbox(ctx, 
        'Delete Backups', cfg.DELETE_BACKUPS))
      cfg.DELETE_AUTOSAVES    = select(2, r.ImGui_Checkbox(ctx, 
        'Delete Autosaves', cfg.DELETE_AUTOSAVES))
    end

    -- Asset Archiving
    if r.ImGui_CollapsingHeader(ctx, "Asset Archiving", 
          r.ImGui_TreeNodeFlags_DefaultOpen()) then
      cfg.GENERATE_REPORT         = select(2, r.ImGui_Checkbox(ctx, 
        'Generate Report', cfg.GENERATE_REPORT))
      cfg.DELETE_UNUSED_FOLDER    = select(2, r.ImGui_Checkbox(ctx, 
        'Delete Unused Folder', cfg.DELETE_UNUSED_FOLDER))
      cfg.OPEN_UNUSED_FOLDER      = select(2, r.ImGui_Checkbox(ctx, 
        'Open After Archiving', cfg.OPEN_UNUSED_FOLDER))
      cfg.ORGANIZE_INTO_SUBFOLDERS = select(2, r.ImGui_Checkbox(ctx, 
        'Organize Into Subfolders', cfg.ORGANIZE_INTO_SUBFOLDERS))
    end

    -- Advanced
    if r.ImGui_CollapsingHeader(ctx, "Advanced", 
          r.ImGui_TreeNodeFlags_DefaultOpen()) then
      r.ImGui_TextWrapped(ctx, 
        "Customize copy location, duplicate handling, ignored folders, etc.")
      -- (Add more inputs...)
    end

    if r.ImGui_Button(ctx, "Start Archival") then
      save_config()
      -- Run archival in one go:
      local project_root = norm_path(r.GetProjectPath("")):match("^(.*)/")
      if not project_root then return end

      -- Example: move all unused media
      process_files(project_root,
        function(fp) return is_media(fp) and not is_ignored(fp) end,
        move_to_unused)

      if cfg.GENERATE_REPORT then
        write_report({})  -- fill with real list
      end

      r.ImGui_OpenPopup(ctx, "DonePopup")
    end

    if r.ImGui_BeginPopupModal(ctx, "DonePopup", true, 0) then
      r.ImGui_Text(ctx, "Archival complete!")
      if r.ImGui_Button(ctx, "OK") then r.ImGui_CloseCurrentPopup(ctx) end
      r.ImGui_EndPopup(ctx)
    end

    r.ImGui_End(ctx)
  end
  return open
end

-- ==== Main Loop ====
local function main()
  load_config()
  r.ImGui_SetNextWindowSize(ctx, 480, 640, r.ImGui_Cond_FirstUseEver())
  if create_gui() then r.defer(main) end
end

main()
