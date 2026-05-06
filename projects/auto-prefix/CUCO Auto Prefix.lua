--[[
CUCO Auto Prefix — Single Script (toggle + apply + strip)

Usage:
- MODE = "auto"  → toggles the watcher on/off
- MODE = "apply" → one-shot apply
- MODE = "strip" → restore stored basenames

Headers: any FOLDER track whose name starts with ">" (e.g., ">FX", ">DIA").

Naming:
- Folders: ">" .. chain .. " " .. basename
- Leaves:  ">" .. chain .. "-" .. leafIndex
  where 'chain' is the sequence of folder indices from the header down.

Example:
>FX
  >01 Treadmill
    >01-01
  >02 Transition Boom
    >02-01
    >02-01 Layers
      >02-01-01
--]]

---------------------------
-- Config
---------------------------
local MODE         = "auto"   -- "auto" | "apply" | "strip"
local PAD_DIGITS   = 2        -- zero-pad width for indices (e.g., 2 => 01..99)
local IGNORE_TAG   = "@noprefix"
local LEAF_SHOW_BASENAME = true  -- show numbers + original name on leaf tracks
local LOG_CONSOLE = false          -- master console logging toggle
local function log(msg) if LOG_CONSOLE then reaper.ShowConsoleMsg(msg) end end
local DEBOUNCE_MS  = 200
local EXT_SECTION  = "aprefix"
local MAX_DEPTH    = 64

---------------------------
-- Toggle helpers (toolbar)
---------------------------
local function set_toggle(on)
  local _, _, sectionID, cmdID = reaper.get_action_context()
  if sectionID and cmdID then
    reaper.SetToggleCommandState(sectionID, cmdID, on and 1 or 0)
    reaper.RefreshToolbar2(sectionID, cmdID)
  end
end

---------------------------
-- Shared utils
---------------------------
local function fmt(fmtstr, ...) return string.format(fmtstr, ...) end
local function guid(track) return reaper.GetTrackGUID(track) end
local function get_name(track)
  local _, name = reaper.GetSetMediaTrackInfo_String(track, "P_NAME", "", false)
  return name or ""
end
local function set_name(track, name)
  reaper.GetSetMediaTrackInfo_String(track, "P_NAME", name, true)
end
local function get_pad_pattern(n) return string.rep("%d", n) end
local function starts_with(s, prefix) return s:sub(1, #prefix) == prefix end
local function is_header(track)
  local name = get_name(track)
  local folderDelta = reaper.GetMediaTrackInfo_Value(track, "I_FOLDERDEPTH") or 0
  return starts_with(name, ">") and folderDelta == 1
end
local function get_proj_flag(key)
  local _, val = reaper.GetProjExtState(0, EXT_SECTION, key)
  return val
end
local function set_proj_flag(key, val)
  reaper.SetProjExtState(0, EXT_SECTION, key, tostring(val))
end
local function get_track_ext(track, key)
  local _, val = reaper.GetSetMediaTrackInfo_String(track, "P_EXT:"..key, "", false)
  return val or ""
end
local function set_track_ext(track, key, val)
  reaper.GetSetMediaTrackInfo_String(track, "P_EXT:"..key, val, true)
end

---------------------------
-- Core planner (compute changes)
---------------------------
local function compute_changes()
  local changes = {}
  local N = reaper.CountTracks(0)
  if N == 0 then return changes end

  local i = 0
  while i < N do
    local tr = reaper.GetTrack(0, i)
    if is_header(tr) then
      local depthH = reaper.GetTrackDepth(tr)
      local stack = {}
      stack[depthH] = { track = tr, guid = guid(tr), level = 0, isHeader = true, name = get_name(tr) }

      local children = {}
      local meta = {}
      local entryByGUID = {}

      local function add_child(parentGUID, e)
        children[parentGUID] = children[parentGUID] or {}
        table.insert(children[parentGUID], e)
      end

      local j = i + 1
      while j < N do
        local t = reaper.GetTrack(0, j)
        local d = reaper.GetTrackDepth(t)
        if d <= depthH then break end

        -- prune any stale entries at depths >= current depth
        for dd = MAX_DEPTH, d, -1 do
          if stack[dd] then stack[dd] = nil end
        end

        local parent = stack[d - 1]
        if parent then
          local tname = get_name(t)
          local foldDelta = reaper.GetMediaTrackInfo_Value(t, "I_FOLDERDEPTH") or 0
          local e = { track = t, guid = guid(t), depth = d, parentGUID = parent.guid, parentName = parent.name or get_name(parent.track) }
          if foldDelta == 1 then
            e.type = "folder"
            e.level = parent.isHeader and 1 or (parent.level + 1)
            stack[d] = { track = t, guid = e.guid, level = e.level, isHeader = false, name = tname }
          else
            e.type = "leaf"
            e.level = parent.isHeader and 1 or parent.level
          end
          e.oldname = tname
          meta[#meta+1] = e
          entryByGUID[e.guid] = e
          add_child(parent.guid, e)
        end
        j = j + 1
      end

      -- assign per-parent indices (padded)
      local function pad_num(n)
        if PAD_DIGITS <= 1 then return tostring(n) end
        return fmt("%0"..PAD_DIGITS.."d", n)
      end
      for parentGUID, list in pairs(children) do
        for idx = 1, #list do
          list[idx].idx = pad_num(idx)
        end
      end

      -- folder index chain: header->...->this folder (indices only)
      local chain_memo = {}
      local function folder_chain_for(entry)
        if not entry then return {} end
        if chain_memo[entry.guid] then return chain_memo[entry.guid] end
        local parent = entryByGUID[entry.parentGUID]
        local chain = {}
        if parent then
          local up = folder_chain_for(parent)
          for k = 1, #up do chain[#chain+1] = up[k] end
        end
        if entry.type == "folder" then
          chain[#chain+1] = entry.idx or "01"
        end
        chain_memo[entry.guid] = chain
        return chain
      end

      -- build desired names
      local stripPatFolders = "^>([0-9%-]+)%s+(.+)$" -- folders: >01-02 Name
local stripPatLeaves  = "^>([0-9%-]+)%s+(.+)$" -- leaves:  >01-02-03 Name  (if you ever enable tails)
      for _, e in ipairs(meta) do
        local t = e.track
        local cur = e.oldname
        if not cur:match("^%s*" .. IGNORE_TAG) then
          local desired
          if e.type == "folder" then
            -- Folder: numeric chain + space + readable basename (stored)
            local chain = folder_chain_for(e)
            local prefix = ">" .. table.concat(chain, "-")
            local base = get_track_ext(t, "ap_base")
            if base == "" then
              local _, tail = cur:match(stripPatFolders)
              base = tail or cur
              set_track_ext(t, "ap_base", base)
            end
            desired = prefix .. " " .. base
          else
            -- Leaf: parent folder chain + "-" + own index (numbers only)
-- Capture a real basename only if present; never store numbers-only as base.
local base = get_track_ext(t, "ap_base")
if base == "" then
  -- If current name already has a tail, harvest it; otherwise only store if unprefixed
  local _, tail = cur:match(stripPatLeaves)
  if tail and tail ~= "" then
    base = tail
  elseif not cur:match("^>%d") then
    -- unprefixed human name; good to store
    base = cur
  else
    base = "" -- current is numbers-only; do NOT store a fake base
  end
  if base ~= "" then set_track_ext(t, "ap_base", base) end
end

local parent = entryByGUID[e.parentGUID]
local chain = folder_chain_for(parent)
local idx = (e.idx or "01")
local prefix
if #chain > 0 then
  prefix = ">" .. table.concat(chain, "-") .. "-" .. idx
else
  -- leaf directly under header
  prefix = ">" .. idx
end
if LEAF_SHOW_BASENAME and base ~= "" then
  desired = prefix .. " " .. base
else
  desired = prefix
end
          end

          if cur ~= desired then
            changes[#changes+1] = { track = t, old = cur, new = desired }
          end
        end
      end

      i = j -- jump to end of this header region
    else
      i = i + 1
    end
  end

  return changes
end

---------------------------
-- Apply / Strip
---------------------------
local function apply_changes()
  local changes = compute_changes()
  if #changes == 0 then return 0 end
  reaper.Undo_BeginBlock2(0)
  reaper.PreventUIRefresh(1)
  for _, ch in ipairs(changes) do
    set_name(ch.track, ch.new)
    -- optional: store last applied prefix head if you need audits later
    -- set_track_ext(ch.track, "ap_last", ch.new:match("^(>[%d%-]+)"))
  end
  reaper.PreventUIRefresh(-1)
  reaper.Undo_EndBlock2(0, "AutoPrefix: apply changes", -1)
  log(("AutoPrefix: renamed %d track(s)\n"):format(#changes))
  return #changes
end

local function strip_prefixes()
  local N = reaper.CountTracks(0)
  if N == 0 then return 0 end
  local changed = 0
  reaper.Undo_BeginBlock2(0)
  reaper.PreventUIRefresh(1)
  for i = 0, N-1 do
    local t = reaper.GetTrack(0, i)
    local base = get_track_ext(t, "ap_base")
    if base ~= "" then
      set_name(t, base)
      changed = changed + 1
    end
  end
  reaper.PreventUIRefresh(-1)
  reaper.Undo_EndBlock2(0, "AutoPrefix: strip prefixes", -1)
  log(("AutoPrefix: stripped %d track(s)\n"):format(changed))
  return changed
end

---------------------------
-- Mode dispatch (single script)
---------------------------
local function consume_ext_cmd()
  local _, cmd = reaper.GetProjExtState(0, EXT_SECTION, "ap_cmd")
  if cmd ~= nil and cmd ~= "" then
    reaper.SetProjExtState(0, EXT_SECTION, "ap_cmd", "")
    return cmd
  end
  return nil
end

local ext_cmd = consume_ext_cmd()
if ext_cmd then MODE = ext_cmd end

if MODE == "apply" then
  apply_changes()
  return
elseif MODE == "strip" then
  strip_prefixes()
  return
end

-- MODE == "auto" (watcher toggle)
local enabled = get_proj_flag("watch_enabled") == "1"
if not enabled then
  set_proj_flag("watch_enabled", "1")
  log("AutoPrefix: watcher ENABLED\n")
  set_toggle(true)
  local lastCount = reaper.GetProjectStateChangeCount(0)
  local lastTickChangeAt = nil
  local function loop()
    if get_proj_flag("watch_enabled") ~= "1" then
      set_toggle(false)
      return
    end
    local c = reaper.GetProjectStateChangeCount(0)
    if c ~= lastCount then
      lastCount = c
      lastTickChangeAt = reaper.time_precise()
    end
    if lastTickChangeAt then
      local dt_ms = (reaper.time_precise() - lastTickChangeAt) * 1000.0
      if dt_ms >= DEBOUNCE_MS then
        apply_changes()
        lastTickChangeAt = nil
      end
    end
    reaper.defer(loop)
  end
  loop()
else
  set_proj_flag("watch_enabled", "0")
  log("AutoPrefix: watcher DISABLED\n")
  set_toggle(false)
end