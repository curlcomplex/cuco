-- Take Markers → FX Bypass Envelope Points (any container depth)
-- Marker name (case-insensitive):
--   "slot N on"            -> unbypass top-level FX slot N at marker time
--   "slot N.M on"          -> unbypass child M inside container at slot N
--   "slot N.M.K off"       -> bypass deeper descendant, any depth
-- Separators: '.' or ':' ; spaces optional.
--
-- Notes:
-- - Writes to the FX's *Bypass* envelope via param ident ":bypass" (reliable at any depth).
-- - Envelope value: 0.0 = ON (unbypassed) for "on"; 1.0 = OFF (bypassed) for "off".
-- - Processes selected items by default.

local r = reaper

-- ========= config =========
local SELECTED_ITEMS_ONLY   = true   -- true: only selected items; false: all items in project
local MAKE_ENV_VISIBLE      = true   -- show/arm created bypass envelopes
local POINT_SHAPE           = 1      -- 0=linear, 1=square
local POINT_TENSION         = 0
local TOLERANCE_SEC         = 1e-6   -- for envelope sort/dupe merge
-- ==========================

local function tolower(s) return s:lower() end
local function log(s) r.ShowConsoleMsg((s or "") .. "\n") end

-- -------- parsing "slot ..." --------
-- returns path {numbers...}, state "on"/"off" or nil if no match
local function parse_marker_name(name)
  if not name or name == "" then return nil end
  local s = tolower(name):gsub("%s+", " "):gsub("^%s*(.-)%s*$","%1")
  -- "slot 1.2.3 on" / "slot1:2 off"
  local block, state = s:match("^slot%s*([%d%.:%s]+)%s*(on)$")
  if not block then block, state = s:match("^slot%s*([%d%.:%s]+)%s*(off)$") end
  if block and state then
    local path = {}
    for num in block:gmatch("(%d+)") do path[#path+1] = tonumber(num) end
    if #path > 0 then return path, state end
  end
  -- "slot3 on"
  local n, st = s:match("^slot(%d+)%s*(on)$")
  if not n then n, st = s:match("^slot(%d+)%s*(off)$") end
  if n and st then return {tonumber(n)}, st end
  return nil
end

-- -------- container addressing (REAPER 7+) --------
-- Encoded child index: 0x2000000 + child(1b)*(top_cnt+1) + parent_ref(1b or encoded)
local function encode_child(parent_ref_1b_or_encoded, child_1b, top_cnt)
  return 0x2000000 + child_1b * (top_cnt + 1) + parent_ref_1b_or_encoded
end

local function child_count(track, fx_any_index)
  local ok, val = r.TrackFX_GetNamedConfigParm(track, fx_any_index, "container_count")
  if not ok or not val then return 0 end
  return tonumber(val) or 0
end

local function is_container(track, fx_any_index)
  return child_count(track, fx_any_index) > 0
end

-- Resolve {N,M,K,...} to an FX address usable in all TrackFX_* calls:
--   top-level -> 0-based index
--   nested    -> encoded index
-- returns addr, top_cnt, err
local function resolve_fx_address(track, path)
  local top_cnt = r.TrackFX_GetCount(track)
  if #path == 0 then return nil, top_cnt, "empty path" end
  local slot1 = path[1]
  if slot1 < 1 or slot1 > top_cnt then return nil, top_cnt, "top slot out of range" end

  if #path == 1 then
    return slot1 - 1, top_cnt, nil
  end

  if not is_container(track, slot1 - 1) then
    return nil, top_cnt, "top slot is not a container"
  end

  local parent_ref = slot1 -- 1-based reference at top
  for i = 2, #path do
    local child_idx = path[i]
    local cc = (parent_ref <= top_cnt) and child_count(track, parent_ref - 1)
                                   or   child_count(track, parent_ref)
    if child_idx < 1 or child_idx > cc then
      return nil, top_cnt, ("child %d out of %d at level %d"):format(child_idx, cc, i)
    end
    parent_ref = encode_child(parent_ref, child_idx, top_cnt)
  end
  return parent_ref, top_cnt, nil
end

-- -------- BYPASS envelope helpers --------
-- Bypass param index is obtained via ident ":bypass"
local function get_bypass_env(track, fx_addr, make_visible)
  local pidx = r.TrackFX_GetParamFromIdent(track, fx_addr, ":bypass")
  if not pidx or pidx < 0 then return nil, "bypass param not found" end
  local env = r.GetFXEnvelope(track, fx_addr, pidx, true)
  if not env then return nil, "envelope create failed" end
  if make_visible then
    r.SetEnvelopeInfo_Value(env, "VISIBLE", 1)
    r.SetEnvelopeInfo_Value(env, "ARM", 1)
  end
  return env
end

local function insert_bypass_point(env, time_sec, state_on)
  if not env then return end
  local val = state_on and 0.0 or 1.0   -- 0 = enabled (unbypassed), 1 = bypassed
  r.InsertEnvelopePointEx(env, -1, time_sec, val, POINT_SHAPE, POINT_TENSION, false, true)
end

-- -------- Take-marker time → project time --------
-- Take marker position is in take-time. Convert:
--   proj = item_start + (take_pos - startoffs) / playrate
local function take_marker_to_project_time(item, take, take_pos)
  local item_start = r.GetMediaItemInfo_Value(item, "D_POSITION")
  local rate       = r.GetMediaItemTakeInfo_Value(take, "D_PLAYRATE") or 1.0
  local startoffs  = r.GetMediaItemTakeInfo_Value(take, "D_STARTOFFS") or 0.0
  return item_start + (take_pos - startoffs) / (rate ~= 0 and rate or 1e-12)
end

-- -------- Take marker iteration (REAPER 7+) --------
local function iter_take_markers(take)
  local n = r.GetNumTakeMarkers and r.GetNumTakeMarkers(take) or 0
  local i = 0
  return function()
    if i >= n then return nil end
    local ok, name, pos, col = r.GetTakeMarker(take, i)
    i = i + 1
    if ok == 1 or ok == true then
      return name or "", pos or 0.0, col or 0
    else
      return "", pos or 0.0, col or 0
    end
  end
end

-- -------- Core: process one item --------
local function process_item(item)
  local take_cnt = r.CountTakes(item)
  if take_cnt == 0 then return end
  local track = r.GetMediaItem_Track(item)
  for tk = 0, take_cnt - 1 do
    local take = r.GetMediaItemTake(item, tk)
    if take then
      for name, tpos, _ in iter_take_markers(take) do
        local path, state = parse_marker_name(name)
        if path then
          local fx_addr, _, err = resolve_fx_address(track, path)
          if fx_addr then
            local env, e2 = get_bypass_env(track, fx_addr, MAKE_ENV_VISIBLE)
            if env then
              local proj_t = take_marker_to_project_time(item, take, tpos)
              insert_bypass_point(env, proj_t, state == "on")
            else
              log(("Skip marker '%s': %s"):format(name, e2 or "env error"))
            end
          else
            log(("Skip marker '%s': %s"):format(name, err or "resolve error"))
          end
        end
      end
    end
  end
end

-- -------- Run --------
r.Undo_BeginBlock()

if SELECTED_ITEMS_ONLY then
  local sel = r.CountSelectedMediaItems(0)
  for i = 0, sel - 1 do
    local it = r.GetSelectedMediaItem(0, i)
    if it then process_item(it) end
  end
else
  local cnt = r.CountMediaItems(0)
  for i = 0, cnt - 1 do
    local it = r.GetMediaItem(0, i)
    if it then process_item(it) end
  end
end

-- Sort any envelopes we touched (cheap to do all tracks)
local trc = r.CountTracks(0)
for ti = 0, trc - 1 do
  local tr = r.GetTrack(0, ti)
  local fx_cnt = r.TrackFX_GetCount(tr)
  for fx = 0, fx_cnt - 1 do
    -- top-level bypass env (if exists)
    local pidx = r.TrackFX_GetParamFromIdent(tr, fx, ":bypass")
    if pidx and pidx >= 0 then
      local env = r.GetFXEnvelope(tr, fx, pidx, false)
      if env then r.Envelope_SortPointsEx(env, -1) end
    end
    -- scan container descendants and sort if present
    local cc = child_count(tr, fx)
    if cc > 0 then
      local top = fx_cnt
      for ci = 1, cc do
        local enc = encode_child(fx + 1, ci, top)
        local pidx2 = r.TrackFX_GetParamFromIdent(tr, enc, ":bypass")
        if pidx2 and pidx2 >= 0 then
          local envc = r.GetFXEnvelope(tr, enc, pidx2, false)
          if envc then r.Envelope_SortPointsEx(envc, -1) end
        end
      end
    end
  end
end

r.UpdateArrange()
r.Undo_EndBlock("Write FX bypass envelope points from take markers", -1)
