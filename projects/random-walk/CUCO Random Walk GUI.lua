-- @description CUCO Random Walk (GUI) — Advanced parameter automation with smart grouping and multiple iterations
-- @version 3.0.0
-- @author curl+tony
-- @changelog
--   3.0.0  Major update: Added FX list with smart parameter grouping, iterative processing, render-to-takes, settings persistence
--   2.0.1  Fix: use reaper.ImGui_* API directly (no nil table); added ReaImGui presence guard.
--   2.0.0  First GUI: sliders, write button + show-env toggle, 3 exclude preset toggles.
-- @about
--   Advanced random-walk automation system with intelligent parameter grouping.
--   Features: FX-specific parameter groups, multiple iterations, render-to-takes, settings persistence.
--   Uses REAL parameter values with smart exclusion based on actual loaded plugins.

--------------------------------------------------------
-- REQUIREMENT CHECK
--------------------------------------------------------
local r = reaper
if not r.ImGui_CreateContext then
  r.ShowMessageBox(
    "This script requires the ReaImGui extension.\n\nInstall via ReaPack:\nExtensions > ReaPack > Browse Packages…\nSearch 'ReaImGui' and install/update, then restart REAPER.",
    "Chain Drunk Walk (GUI)", 0)
  return
end

--------------------------------------------------------
-- DEFAULTS
--------------------------------------------------------
local DEFAULT_SEVERITY         = 0.25  -- 0..1 fraction of param range per point
local DEFAULT_POINTS_PER_PARAM = 64    -- >= 2
local DEFAULT_SHOW_ENVS        = true  -- force-show envelopes after write
local DEFAULT_NUM_ITERATIONS   = 3     -- number of iterations for batch processing
local DEFAULT_RENDER_TO_TAKES  = true  -- render each iteration to new takes
local DEFAULT_ADD_REALIMIT     = false -- add ReaLimit before rendering

-- Window (larger size for new features)
local WINDOW_W, WINDOW_H = 460, 700
local WINDOW_TITLE = "CUCO Random Walk"

--------------------------------------------------------
-- CUSTOM BLACKLISTS & SETTINGS
--------------------------------------------------------
-- Category-specific custom blacklists with defaults
local custom_blacklists = {
  VOL_GAIN_AMP = "volume, gain, level, amp, amplitude",
  PITCH = "pitch, transpose, semitone, coarse, tune, key, hz",
  TYPE_BINARY = "on, off, solo, mute, mode, type, send, return, delta, Src1, Src2, Active FX1, Active FX2",
  GLOBAL = "bypass, master volume, mix"
}

-- Settings file
local settings_file = r.GetResourcePath() .. "/Scripts/CUCO Random Walk Settings.txt"

--------------------------------------------------------
-- STATE
--------------------------------------------------------
local severity          = DEFAULT_SEVERITY
local points_per_param  = DEFAULT_POINTS_PER_PARAM
local show_envs         = DEFAULT_SHOW_ENVS
local num_iterations    = DEFAULT_NUM_ITERATIONS
local render_to_takes   = DEFAULT_RENDER_TO_TAKES
local add_realimit      = DEFAULT_ADD_REALIMIT
local ex_vol_gain_amp   = true   -- preset defaults (adjust to taste)
local ex_pitch          = false
local ex_type_binary    = true
local is_processing     = false  -- track iterative processing state

-- FX list management
local fx_list = {}
local fx_list_needs_update = true

--------------------------------------------------------
-- HELPERS
--------------------------------------------------------
local function clamp(x, a, b) if x<a then return a elseif x>b then return b else return x end end
local function lower(s) return (s and s:lower()) or "" end

-- Settings persistence functions
local function save_settings()
  local scripts_dir = r.GetResourcePath() .. "/Scripts"
  r.RecursiveCreateDirectory(scripts_dir, 0)
  
  local settings = {
    severity = severity,
    points_per_param = points_per_param,
    show_envs = show_envs,
    num_iterations = num_iterations,
    render_to_takes = render_to_takes,
    add_realimit = add_realimit,
    ex_vol_gain_amp = ex_vol_gain_amp,
    ex_pitch = ex_pitch,
    ex_type_binary = ex_type_binary,
    custom_blacklists = custom_blacklists
  }
  
  local file = io.open(settings_file, "w")
  if file then
    file:write("-- CUCO Random Walk Settings (auto-generated)\n")
    for key, value in pairs(settings) do
      if type(value) == "table" then
        file:write(key .. " = {\n")
        for subkey, subvalue in pairs(value) do
          file:write("  " .. subkey .. " = \"" .. tostring(subvalue) .. "\",\n")
        end
        file:write("}\n")
      else
        file:write(key .. " = " .. tostring(value) .. "\n")
      end
    end
    file:close()
  end
end

local function load_settings()
  local file = io.open(settings_file, "r")
  if file then
    local content = file:read("*all")
    file:close()
    
    -- Simple parsing to restore settings
    local loaded_blacklists = {}
    local in_custom_blacklists = false
    
    for line in content:gmatch("([^\n]+)") do
      if not line:match("^%-%-") then  -- skip comments
        if line:match("^custom_blacklists") then
          in_custom_blacklists = true
        elseif in_custom_blacklists and line:match("^}") then
          in_custom_blacklists = false
        elseif in_custom_blacklists then
          local key, value = line:match("%s*(%w+)%s*=%s*\"(.+)\"")
          if key and value then
            loaded_blacklists[key] = value
          end
        else
          local key, value = line:match("(%w+)%s*=%s*(.+)")
          if key and value then
            if key == "severity" and tonumber(value) then
              severity = tonumber(value)
            elseif key == "points_per_param" and tonumber(value) then
              points_per_param = tonumber(value)
            elseif key == "num_iterations" and tonumber(value) then
              num_iterations = tonumber(value)
            elseif key == "show_envs" then
              show_envs = (value == "true")
            elseif key == "render_to_takes" then
              render_to_takes = (value == "true")
            elseif key == "add_realimit" then
              add_realimit = (value == "true")
            elseif key == "ex_vol_gain_amp" then
              ex_vol_gain_amp = (value == "true")
            elseif key == "ex_pitch" then
              ex_pitch = (value == "true")
            elseif key == "ex_type_binary" then
              ex_type_binary = (value == "true")
            end
          end
        end
      end
    end
    
    -- Apply loaded custom blacklists
    for key, value in pairs(loaded_blacklists) do
      if custom_blacklists[key] then
        custom_blacklists[key] = value
      end
    end
  end
end

local function build_exclude_list()
  local list = {}
  
  -- Always add GLOBAL blacklist terms
  for term in custom_blacklists.GLOBAL:gmatch("([^,]+)") do
    local trimmed = term:match("^%s*(.-)%s*$")
    if trimmed and trimmed ~= "" then
      list[#list + 1] = trimmed:lower()
    end
  end
  
  -- Add category-specific terms based on checkboxes
  if ex_vol_gain_amp then
    for term in custom_blacklists.VOL_GAIN_AMP:gmatch("([^,]+)") do
      local trimmed = term:match("^%s*(.-)%s*$")
      if trimmed and trimmed ~= "" then
        list[#list + 1] = trimmed:lower()
      end
    end
  end
  
  if ex_pitch then
    for term in custom_blacklists.PITCH:gmatch("([^,]+)") do
      local trimmed = term:match("^%s*(.-)%s*$")
      if trimmed and trimmed ~= "" then
        list[#list + 1] = trimmed:lower()
      end
    end
  end
  
  if ex_type_binary then
    for term in custom_blacklists.TYPE_BINARY:gmatch("([^,]+)") do
      local trimmed = term:match("^%s*(.-)%s*$")
      if trimmed and trimmed ~= "" then
        list[#list + 1] = trimmed:lower()
      end
    end
  end
  
  return list
end

local function is_excluded_param(track, fx, p, exclude_list)
  local ok, name = r.TrackFX_GetParamName(track, fx, p, "")
  if not ok then return false end
  local lname = lower(name)
  for _, ex in ipairs(exclude_list) do
    if lname:find(ex, 1, true) then return true end
  end
  return false
end

local function get_time_selection()
  local a,b = r.GetSet_LoopTimeRange(false,false,0,0,false)
  
  -- If we have a valid time selection, use it
  if a and b and b > a then
    return a, b
  end
  
  -- No time selection - try to use selected items
  local item_count = r.CountSelectedMediaItems(0)
  if item_count == 0 then
    -- No items selected either - check if there are any items on selected tracks
    local sel_track_count = r.CountSelectedTracks(0)
    if sel_track_count > 0 then
      local earliest = math.huge
      local latest = -math.huge
      
      for i = 0, sel_track_count - 1 do
        local track = r.GetSelectedTrack(0, i)
        local track_item_count = r.CountTrackMediaItems(track)
        
        for j = 0, track_item_count - 1 do
          local item = r.GetTrackMediaItem(track, j)
          local item_start = r.GetMediaItemInfo_Value(item, "D_POSITION")
          local item_length = r.GetMediaItemInfo_Value(item, "D_LENGTH")
          local item_end = item_start + item_length
          
          earliest = math.min(earliest, item_start)
          latest = math.max(latest, item_end)
        end
      end
      
      if earliest < math.huge and latest > -math.huge then
        r.ShowConsoleMsg(("[CUCO Random Walk] Auto-detected time range from track items: %.3f to %.3f\n"):format(earliest, latest))
        return earliest, latest
      end
    end
    return nil  -- No items found
  end
  
  -- Use selected items to determine time range
  local earliest = math.huge
  local latest = -math.huge
  
  for i = 0, item_count - 1 do
    local item = r.GetSelectedMediaItem(0, i)
    local item_start = r.GetMediaItemInfo_Value(item, "D_POSITION")
    local item_length = r.GetMediaItemInfo_Value(item, "D_LENGTH")
    local item_end = item_start + item_length
    
    earliest = math.min(earliest, item_start)
    latest = math.max(latest, item_end)
  end
  
  if earliest < math.huge and latest > -math.huge then
    r.ShowConsoleMsg(("[CUCO Random Walk] Auto-detected time range from selected items: %.3f to %.3f\n"):format(earliest, latest))
    return earliest, latest
  end
  
  return nil  -- No valid range found
end

-- Build FX list from currently selected tracks
local function update_fx_list()
  fx_list = {}
  local sel_cnt = r.CountSelectedTracks(0)
  
  for track_idx = 0, sel_cnt - 1 do
    local track = r.GetSelectedTrack(0, track_idx)
    local track_name = select(2, r.GetSetMediaTrackInfo_String(track, "P_NAME", "", false))
    if track_name == "" then
      track_name = "Track " .. (r.GetMediaTrackInfo_Value(track, "IP_TRACKNUMBER"))
    end
    
    local fx_count = r.TrackFX_GetCount(track)
    local track_data = {
      track = track,
      track_name = track_name,
      fx_count = fx_count,
      fx = {}
    }
    
    for fx_idx = 0, fx_count - 1 do
      local fx_name = select(2, r.TrackFX_GetFXName(track, fx_idx, ""))
      track_data.fx[fx_idx] = {
        name = fx_name,
        enabled = true  -- default to enabled
      }
    end
    
    fx_list[track_idx] = track_data
  end
  
  fx_list_needs_update = false
end

-- Evenly spaced timestamps across [t1, t2], endpoints included
local function uniform_times(t1, t2, count)
  local times = {}
  count = math.max(2, math.floor(count or 2))
  local span = t2 - t1
  if span <= 0 then times[1]=t1; times[2]=t1; return times end
  for i=0, count-1 do
    local frac = i/(count-1)
    times[#times+1] = t1 + frac*span
  end
  return times
end

-- Show/arm via API when available, with robust chunk fallback
local has_SetEnv = type(r.SetEnvelopeInfo_Value)=="function"
local function safe_env_flag(env, key, val) if has_SetEnv then r.SetEnvelopeInfo_Value(env, key, val) end end

local function force_show_env_chunk(env)
  local ok, chunk = r.GetEnvelopeStateChunk(env, "", false)
  if not ok or not chunk or #chunk==0 then return end
  chunk = chunk:gsub("ACT%s+[01]", "ACT 1")
  chunk = chunk:gsub("ARM%s+[01]", "ARM 1")
  local had_vis=false
  chunk = chunk:gsub("VIS%s+[01]%s+[01]%s*[01]?", function() had_vis=true; return "VIS 1 1 1" end)
  if not had_vis then chunk = chunk:gsub("(ACT%s+1[^\n]*\n)", "%1VIS 1 1 1\n") end
  r.SetEnvelopeStateChunk(env, chunk, true)
end

local function ensure_env(track, fx, p)
  return r.GetFXEnvelope(track, fx, p, true)
end

local function fx_ok(track, fx)
  if not r.TrackFX_GetEnabled(track, fx) then return false end
  if r.TrackFX_GetOffline and r.TrackFX_GetOffline(track, fx) then return false end
  return true
end

-- Write using REAL parameter values (min..max), uniform points
local function write_param_real(track, fx, p, t1, t2, count, sev, exclude_list, do_show_envs)
  if is_excluded_param(track, fx, p, exclude_list) then return 0 end

  local cur, minv, maxv = r.TrackFX_GetParam(track, fx, p)
  if not cur then return 0 end
  minv = tonumber(minv) or 0.0
  maxv = tonumber(maxv) or 1.0
  if maxv == minv then maxv = minv + 1.0 end
  local span = (maxv - minv)

  local env = ensure_env(track, fx, p); if not env then return 0 end
  local times = uniform_times(t1, t2, count)

  -- Replace existing points in range
  r.DeleteEnvelopePointRange(env, times[1], times[#times])

  -- Brownian walk
  local v = clamp(cur, minv, maxv)
  for i=1, #times do
    local step = ((math.random()*2 - 1) * sev) * span
    v = clamp(v + step, minv, maxv)
    r.InsertEnvelopePoint(env, times[i], v, 0, 0, false, true)
  end
  r.Envelope_SortPoints(env)

  if do_show_envs then
    safe_env_flag(env,"VIS",1); safe_env_flag(env,"ARM",1)
    force_show_env_chunk(env)
  end
  return 1
end

-- Render automation to new takes
local function render_to_new_takes(iteration_num)
  local t1, t2 = get_time_selection()
  if not t1 then return false end
  
  local sel_cnt = r.CountSelectedTracks(0)
  
  -- Clear item selection first
  r.Main_OnCommand(40289, 0) -- Item: Unselect all items
  
  -- Select all items within time selection on selected tracks AND set to original take
  for i = 0, sel_cnt - 1 do
    local track = r.GetSelectedTrack(0, i)
    local item_count = r.CountTrackMediaItems(track)
    
    for j = 0, item_count - 1 do
      local item = r.GetTrackMediaItem(track, j)
      local item_start = r.GetMediaItemInfo_Value(item, "D_POSITION")
      local item_end = item_start + r.GetMediaItemInfo_Value(item, "D_LENGTH")
      
      -- Check if item overlaps with time selection
      if item_start < t2 and item_end > t1 then
        r.SetMediaItemSelected(item, true)
        
        -- CRITICAL: Set active take to the FIRST take (original)
        local first_take = r.GetTake(item, 0)
        if first_take then
          r.SetActiveTake(first_take)
        end
      end
    end
  end
  
  -- Add ReaLimit if requested
  local added_realimit = {}
  if add_realimit then
    for i = 0, sel_cnt - 1 do
      local track = r.GetSelectedTrack(0, i)
      local realimit_idx = r.TrackFX_AddByName(track, "ReaLimit", false, -1)
      if realimit_idx >= 0 then
        added_realimit[track] = realimit_idx
      end
    end
  end
  
  -- Force all envelopes to be visible and armed before applying FX
  for i = 0, sel_cnt - 1 do
    local track = r.GetSelectedTrack(0, i)
    local fx_count = r.TrackFX_GetCount(track)
    for fx = 0, fx_count - 1 do
      if fx_ok(track, fx) then
        local param_count = r.TrackFX_GetNumParams(track, fx)
        for p = 0, param_count - 1 do
          local env = r.GetFXEnvelope(track, fx, p, false)
          if env then
            safe_env_flag(env,"VIS",1)
            safe_env_flag(env,"ARM",1)
            force_show_env_chunk(env)
          end
        end
      end
    end
  end
  
  -- Apply track/take FX to selected items to create new takes
  r.Main_OnCommand(40209, 0) -- Item: Apply track/take FX to items (mono output)
  
  -- Remove ReaLimit if we added it
  if add_realimit then
    for track, fx_idx in pairs(added_realimit) do
      if r.ValidatePtr(track, "MediaTrack*") then
        r.TrackFX_Delete(track, fx_idx)
      end
    end
  end
  
  -- Rename the newly created takes
  for i = 0, sel_cnt - 1 do
    local track = r.GetSelectedTrack(0, i)
    local item_count = r.CountTrackMediaItems(track)
    
    for j = 0, item_count - 1 do
      local item = r.GetTrackMediaItem(track, j)
      local take_count = r.CountTakes(item)
      
      if take_count > 0 then
        -- Get the most recent take (likely the one we just created)
        local newest_take = r.GetTake(item, take_count - 1)
        if newest_take then
          local ok, current_name = r.GetSetMediaItemTakeInfo_String(newest_take, "P_NAME", "", false)
          current_name = tostring(current_name or "")
          -- Only rename if it doesn't already have an RW_ prefix (to avoid renaming existing takes)
          if not current_name:find("^RW_") then
            r.GetSetMediaItemTakeInfo_String(newest_take, "P_NAME", "RW_" .. iteration_num, true)
          end
        end
      end
    end
  end
  
  return true
end

--------------------------------------------------------
-- WRITE ACTION
--------------------------------------------------------
-- Single iteration of random walk + envelope generation
local function do_single_write(iteration_num, exclude_list, pts)
  local t1, t2 = get_time_selection()
  if not t1 then return 0, 0, 0 end

  local sel_cnt = r.CountSelectedTracks(0)
  local scanned_fx, scanned_params, written = 0, 0, 0

  for i=0, sel_cnt-1 do
    local tr = r.GetSelectedTrack(0,i)
    local fxN = r.TrackFX_GetCount(tr)
    for fx=0, fxN-1 do
      if fx_ok(tr,fx) then
        scanned_fx = scanned_fx + 1
        local pn = r.TrackFX_GetNumParams(tr, fx)
        for p=0, pn-1 do
          scanned_params = scanned_params + 1
          written = written + write_param_real(tr, fx, p, t1, t2, pts, severity, exclude_list, show_envs)
        end
      end
    end
  end
  
  return scanned_fx, scanned_params, written
end

-- Original single write function (for backward compatibility)
local function do_write()
  local t1, t2 = get_time_selection()
  if not t1 then
    r.ShowMessageBox("No valid time range found.\n\nPlease either:\n• Set a time selection, or\n• Select some items, or\n• Select tracks with items", WINDOW_TITLE, 0)
    return
  end

  local pts = math.max(2, math.floor(points_per_param or 64))
  local seed = (os.time() + math.floor(r.time_precise()*1000) % 9973)
  math.randomseed(seed)

  local exclude_list = build_exclude_list()

  r.Undo_BeginBlock()
  r.PreventUIRefresh(1)

  local scanned_fx, scanned_params, written = do_single_write(1, exclude_list, pts)

  r.TrackList_AdjustWindows(false)
  r.UpdateArrange()
  r.PreventUIRefresh(-1)
  r.Undo_EndBlock("CUCO Random Walk: rewrite envelopes (uniform, real values)", -1)

  r.ShowConsoleMsg(("[CUCO Random Walk] tracks=%d  fx=%d  params=%d  envs_written=%d  pts/param=%d  severity=%.3f  show_env=%s\n")
    :format(r.CountSelectedTracks(0), scanned_fx, scanned_params, written, pts, severity, tostring(show_envs)))
end

-- Multi-iteration processing with rendering
local function do_iterative_write()
  local t1, t2 = get_time_selection()
  if not t1 then
    r.ShowMessageBox("No valid time range found.\n\nPlease either:\n• Set a time selection, or\n• Select some items, or\n• Select tracks with items", WINDOW_TITLE, 0)
    return
  end

  if is_processing then
    r.ShowMessageBox("Processing is already in progress.", WINDOW_TITLE, 0)
    return
  end

  is_processing = true
  
  local pts = math.max(2, math.floor(points_per_param or 64))
  local exclude_list = build_exclude_list()
  
  r.Undo_BeginBlock()
  
  for iteration = 1, num_iterations do
    r.ShowConsoleMsg(("[CUCO Random Walk] Starting iteration %d/%d\n"):format(iteration, num_iterations))
    
    -- Generate new random seed for this iteration
    local seed = (os.time() * iteration + math.floor(r.time_precise()*10000) % 999983) + iteration * 12345
    math.randomseed(seed)
    
    -- STEP 1: Write random automation (EXACTLY like Write Once)
    r.PreventUIRefresh(1)
    local scanned_fx, scanned_params, written = do_single_write(iteration, exclude_list, pts)
    r.TrackList_AdjustWindows(false)
    r.UpdateArrange()
    r.PreventUIRefresh(-1)
    
    r.ShowConsoleMsg(("[CUCO Random Walk] Wrote %d envelopes, now rendering...\n"):format(written))
    
    -- STEP 2: Render to new takes 
    if render_to_takes then
      render_to_new_takes(iteration)
    end
    
    r.ShowConsoleMsg(("[CUCO Random Walk] Completed iteration %d/%d (seed=%d)\n"):format(iteration, num_iterations, seed))
  end
  
  r.Undo_EndBlock("CUCO Random Walk: iterative processing " .. num_iterations .. " iterations", -1)
  
  is_processing = false
  
  r.ShowConsoleMsg(("[CUCO Random Walk] All iterations complete!\n"))
end

--------------------------------------------------------
-- INITIALIZATION
--------------------------------------------------------
-- Load settings on startup
load_settings()

--------------------------------------------------------
-- GUI
--------------------------------------------------------
local ctx = r.ImGui_CreateContext(WINDOW_TITLE)

-- Popup state tracking
local popup_states = {
  VOL_GAIN_AMP = false,
  PITCH = false,
  TYPE_BINARY = false,
  GLOBAL = false
}

-- Temporary text storage for popup editing
local temp_blacklist_text = {
  VOL_GAIN_AMP = "",
  PITCH = "",
  TYPE_BINARY = "",
  GLOBAL = ""
}

-- Track change detection
local last_selected_tracks = -1

local function loop()
  -- Check if selected tracks changed
  local current_selected_tracks = r.CountSelectedTracks(0)
  if current_selected_tracks ~= last_selected_tracks then
    fx_list_needs_update = true
    last_selected_tracks = current_selected_tracks
  end
  
  -- Check if FX counts changed on existing tracks
  if not fx_list_needs_update then
    for i = 0, current_selected_tracks - 1 do
      local track = r.GetSelectedTrack(0, i)
      if track then
        local current_fx_count = r.TrackFX_GetCount(track)
        if fx_list[i] and fx_list[i].fx_count ~= current_fx_count then
          fx_list_needs_update = true
          break
        end
      end
    end
  end
  
  r.ImGui_SetNextWindowSize(ctx, WINDOW_W, WINDOW_H, r.ImGui_Cond_Always())
  local visible, open = r.ImGui_Begin(ctx, WINDOW_TITLE, true,
      r.ImGui_WindowFlags_NoResize() | r.ImGui_WindowFlags_NoCollapse())

  if visible then
    r.ImGui_PushItemWidth(ctx, WINDOW_W - 24)

    -- 1) FX Exclusion List (moved to top)
    -- Update FX list if needed
    if fx_list_needs_update then
      update_fx_list()
    end
    
    -- Scrollable area for FX list
    r.ImGui_BeginChild(ctx, "FX_List", WINDOW_W - 24, 120)
    
    for track_idx = 0, #fx_list do
      local track_data = fx_list[track_idx]
      if track_data and track_data.fx and track_data.fx_count and track_data.fx_count > 0 then
        r.ImGui_Text(ctx, track_data.track_name .. ":")
        
        -- Iterate through FX in correct order (0 to fx_count-1)
        for fx_idx = 0, track_data.fx_count - 1 do
          local fx_data = track_data.fx[fx_idx]
          if fx_data then
            local changed, enabled = r.ImGui_Checkbox(ctx, "##fx_" .. track_idx .. "_" .. fx_idx, fx_data.enabled)
            if changed then
              fx_data.enabled = enabled
            end
            r.ImGui_SameLine(ctx)
            r.ImGui_Text(ctx, fx_data.name)
          end
        end
        
        r.ImGui_Spacing(ctx)
      end
    end
    
    r.ImGui_EndChild(ctx)
    
    r.ImGui_Separator(ctx)

    -- 2) Severity slider
    local changed1, s = r.ImGui_SliderDouble(ctx, "Severity", severity, 0.0, 1.0, "%.3f")
    if changed1 then severity = s end

    -- 3) Points per param slider
    local changed2, p = r.ImGui_SliderInt(ctx, "Points per param", points_per_param, 2, 1024)
    if changed2 then points_per_param = p end

    -- 4) Number of iterations slider
    local changed3, n = r.ImGui_SliderInt(ctx, "Iterations", num_iterations, 1, 20)
    if changed3 then num_iterations = n end

    r.ImGui_Separator(ctx)

    -- 5) Write buttons
    local button_width = (WINDOW_W - 32) / 2
    if r.ImGui_Button(ctx, "Write Once", button_width, 26) then do_write() end
    r.ImGui_SameLine(ctx)
    
    local button_label = is_processing and "Processing..." or ("Write " .. num_iterations .. " + Render")
    r.ImGui_BeginDisabled(ctx, is_processing)
    if r.ImGui_Button(ctx, button_label, button_width, 26) then 
      do_iterative_write() 
    end
    r.ImGui_EndDisabled(ctx)

    -- 6) Show Envelopes toggle
    local toggled, val = r.ImGui_Checkbox(ctx, "Show envelopes after write", show_envs)
    if toggled then show_envs = val end

    -- 7) Render to takes toggle
    local toggled2, val2 = r.ImGui_Checkbox(ctx, "Render to new takes", render_to_takes)
    if toggled2 then render_to_takes = val2 end

    -- 8) Add ReaLimit toggle
    local toggled3, val3 = r.ImGui_Checkbox(ctx, "Add ReaLimit before render", add_realimit)
    if toggled3 then add_realimit = val3 end

    r.ImGui_Separator(ctx)

    -- 9) Parameter Exclusion Categories
    r.ImGui_Text(ctx, "Parameter Exclusion Categories:")
    
    -- VOL_GAIN_AMP category
    local changed_vol, val_vol = r.ImGui_Checkbox(ctx, "Volume/Gain/Amp Parameters", ex_vol_gain_amp)
    if changed_vol then ex_vol_gain_amp = val_vol end
    r.ImGui_SameLine(ctx)
    if r.ImGui_Button(ctx, "Edit##VOL", 40, 0) then
      popup_states.VOL_GAIN_AMP = true
      temp_blacklist_text.VOL_GAIN_AMP = custom_blacklists.VOL_GAIN_AMP
    end
    
    -- PITCH category
    local changed_pitch, val_pitch = r.ImGui_Checkbox(ctx, "Pitch/Transpose Parameters", ex_pitch)
    if changed_pitch then ex_pitch = val_pitch end
    r.ImGui_SameLine(ctx)
    if r.ImGui_Button(ctx, "Edit##PITCH", 40, 0) then
      popup_states.PITCH = true
      temp_blacklist_text.PITCH = custom_blacklists.PITCH
    end
    
    -- TYPE_BINARY category
    local changed_binary, val_binary = r.ImGui_Checkbox(ctx, "Binary/Mode/Type Parameters", ex_type_binary)
    if changed_binary then ex_type_binary = val_binary end
    r.ImGui_SameLine(ctx)
    if r.ImGui_Button(ctx, "Edit##BINARY", 40, 0) then
      popup_states.TYPE_BINARY = true
      temp_blacklist_text.TYPE_BINARY = custom_blacklists.TYPE_BINARY
    end
    
    -- GLOBAL category (always active, no checkbox)
    r.ImGui_Text(ctx, "Global Exclusions (always active):")
    r.ImGui_SameLine(ctx)
    if r.ImGui_Button(ctx, "Edit##GLOBAL", 40, 0) then
      popup_states.GLOBAL = true
      temp_blacklist_text.GLOBAL = custom_blacklists.GLOBAL
    end
    
    -- Popup windows for editing blacklists
    -- VOL_GAIN_AMP popup
    if popup_states.VOL_GAIN_AMP then
      r.ImGui_SetNextWindowSize(ctx, 450, 200)
      r.ImGui_OpenPopup(ctx, "Edit Volume/Gain/Amp Blacklist")
    end
    
    if r.ImGui_BeginPopupModal(ctx, "Edit Volume/Gain/Amp Blacklist", true) then
      r.ImGui_Text(ctx, "Edit Volume/Gain/Amp exclusion terms (comma-separated):")
      local text_changed, new_text = r.ImGui_InputTextMultiline(ctx, "##vol_blacklist", temp_blacklist_text.VOL_GAIN_AMP, 430, 120)
      if text_changed then
        temp_blacklist_text.VOL_GAIN_AMP = new_text
      end
      
      if r.ImGui_Button(ctx, "OK", 100, 0) then
        custom_blacklists.VOL_GAIN_AMP = temp_blacklist_text.VOL_GAIN_AMP
        save_settings()
        popup_states.VOL_GAIN_AMP = false
        r.ImGui_CloseCurrentPopup(ctx)
      end
      r.ImGui_SameLine(ctx)
      if r.ImGui_Button(ctx, "Cancel", 100, 0) then
        popup_states.VOL_GAIN_AMP = false
        r.ImGui_CloseCurrentPopup(ctx)
      end
      r.ImGui_EndPopup(ctx)
    end
    
    -- PITCH popup
    if popup_states.PITCH then
      r.ImGui_SetNextWindowSize(ctx, 450, 200)
      r.ImGui_OpenPopup(ctx, "Edit Pitch/Transpose Blacklist")
    end
    
    if r.ImGui_BeginPopupModal(ctx, "Edit Pitch/Transpose Blacklist", true) then
      r.ImGui_Text(ctx, "Edit Pitch/Transpose exclusion terms (comma-separated):")
      local text_changed, new_text = r.ImGui_InputTextMultiline(ctx, "##pitch_blacklist", temp_blacklist_text.PITCH, 430, 120)
      if text_changed then
        temp_blacklist_text.PITCH = new_text
      end
      
      if r.ImGui_Button(ctx, "OK", 100, 0) then
        custom_blacklists.PITCH = temp_blacklist_text.PITCH
        save_settings()
        popup_states.PITCH = false
        r.ImGui_CloseCurrentPopup(ctx)
      end
      r.ImGui_SameLine(ctx)
      if r.ImGui_Button(ctx, "Cancel", 100, 0) then
        popup_states.PITCH = false
        r.ImGui_CloseCurrentPopup(ctx)
      end
      r.ImGui_EndPopup(ctx)
    end
    
    -- TYPE_BINARY popup
    if popup_states.TYPE_BINARY then
      r.ImGui_SetNextWindowSize(ctx, 450, 200)
      r.ImGui_OpenPopup(ctx, "Edit Binary/Mode/Type Blacklist")
    end
    
    if r.ImGui_BeginPopupModal(ctx, "Edit Binary/Mode/Type Blacklist", true) then
      r.ImGui_Text(ctx, "Edit Binary/Mode/Type exclusion terms (comma-separated):")
      local text_changed, new_text = r.ImGui_InputTextMultiline(ctx, "##binary_blacklist", temp_blacklist_text.TYPE_BINARY, 430, 120)
      if text_changed then
        temp_blacklist_text.TYPE_BINARY = new_text
      end
      
      if r.ImGui_Button(ctx, "OK", 100, 0) then
        custom_blacklists.TYPE_BINARY = temp_blacklist_text.TYPE_BINARY
        save_settings()
        popup_states.TYPE_BINARY = false
        r.ImGui_CloseCurrentPopup(ctx)
      end
      r.ImGui_SameLine(ctx)
      if r.ImGui_Button(ctx, "Cancel", 100, 0) then
        popup_states.TYPE_BINARY = false
        r.ImGui_CloseCurrentPopup(ctx)
      end
      r.ImGui_EndPopup(ctx)
    end
    
    -- GLOBAL popup
    if popup_states.GLOBAL then
      r.ImGui_SetNextWindowSize(ctx, 450, 200)
      r.ImGui_OpenPopup(ctx, "Edit Global Blacklist")
    end
    
    if r.ImGui_BeginPopupModal(ctx, "Edit Global Blacklist", true) then
      r.ImGui_Text(ctx, "Edit Global exclusion terms (comma-separated):")
      local text_changed, new_text = r.ImGui_InputTextMultiline(ctx, "##global_blacklist", temp_blacklist_text.GLOBAL, 430, 120)
      if text_changed then
        temp_blacklist_text.GLOBAL = new_text
      end
      
      if r.ImGui_Button(ctx, "OK", 100, 0) then
        custom_blacklists.GLOBAL = temp_blacklist_text.GLOBAL
        save_settings()
        popup_states.GLOBAL = false
        r.ImGui_CloseCurrentPopup(ctx)
      end
      r.ImGui_SameLine(ctx)
      if r.ImGui_Button(ctx, "Cancel", 100, 0) then
        popup_states.GLOBAL = false
        r.ImGui_CloseCurrentPopup(ctx)
      end
      r.ImGui_EndPopup(ctx)
    end

    r.ImGui_PopItemWidth(ctx)
  end
  
  r.ImGui_End(ctx)

  if open then 
    r.defer(loop) 
  else 
    save_settings()
    r.ImGui_DestroyContext(ctx) 
  end
end

r.defer(loop)
