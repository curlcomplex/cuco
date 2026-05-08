-- @description Chain Drunk Walk (GUI) — uniform points across time selection for ALL FX params (real values, with exclude presets) - EXPERIMENTAL BUILD
-- @version 2.1.0-experimental
-- @author curl+tony
-- @changelog
--   2.1.0-experimental  Created experimental build for feature development
--   2.0.1  Fix: use reaper.ImGui_* API directly (no nil table); added ReaImGui presence guard.
--   2.0.0  First GUI: sliders, write button + show-env toggle, 3 exclude preset toggles.
-- @about
--   Writes random-walk automation for ALL FX parameters on selected tracks within SELECTED ITEMS.
--   Uses REAL parameter values (min..max) with UNIFORMLY spaced points across the items.
--   Smart parameter grouping and exclude-by-name presets (case-insensitive substrings).
--   Automation is written ONLY within the time bounds of selected items, preserving existing automation elsewhere.
--   
--   EXPERIMENTAL BUILD - Contains new features and modifications for testing

--------------------------------------------------------
-- REQUIREMENT CHECK
--------------------------------------------------------
local r = reaper
if not r.ImGui_CreateContext then
  r.ShowMessageBox(
    "This script requires the ReaImGui extension.\n\nInstall via ReaPack:\nExtensions > ReaPack > Browse Packages…\nSearch 'ReaImGui' and install/update, then restart REAPER.",
    "Chain Drunk Walk (GUI) - EXPERIMENTAL", 0)
  return
end

--------------------------------------------------------
-- DEFAULTS
--------------------------------------------------------
local DEFAULT_SEVERITY         = 0.25  -- 0..1 fraction of param range per point
local DEFAULT_POINTS_PER_PARAM = 64    -- >= 2
local DEFAULT_SHOW_ENVS        = true  -- force-show envelopes after write

-- Window (expanded for new features including FX list and blacklist)
local WINDOW_W, WINDOW_H = 450, 580
local WINDOW_TITLE = "Chain Drunk Walk - EXPERIMENTAL"

--------------------------------------------------------
-- EXCLUDE PRESETS
--------------------------------------------------------
-- Always skip these
local BASE_EXCLUDES = { "bypass", "master volume", "mix"}

-- Toggleable groups
local PRESET_EXCLUDES = {
  VOL_GAIN_AMP = { "volume", "gain", "level", "amp", "amplitude" },
  PITCH        = { "pitch", "transpose", "semitone", "coarse", "tune", "key", "hz" },
  TYPE_BINARY  = { "on", "off", "solo", "mute", "mode", "type", "send", "return", "delta", "Src1", "Src2", "Active FX1", "Active FX2" },
}

--------------------------------------------------------
-- STATE
--------------------------------------------------------
local severity          = DEFAULT_SEVERITY
local points_per_param  = DEFAULT_POINTS_PER_PARAM
local show_envs         = DEFAULT_SHOW_ENVS

-- New iteration and rendering state
local num_iterations    = 1       -- number of iterations to perform
local render_to_takes   = true    -- true = new takes, false = new tracks
local add_realimit      = false   -- add ReaLimit before rendering
local is_processing     = false   -- flag to show processing status

-- FX exclusion state
local fx_list = {}  -- {track_idx = {fx_idx = {name = "FX Name", enabled = true}}
local fx_list_needs_update = true

-- Category exclusion state (restored)
local ex_vol_gain_amp   = true   -- preset defaults (adjust to taste)
local ex_pitch          = false
local ex_type_binary    = true

-- Custom blacklist - Global exclusions that should always be skipped
local custom_blacklists = {
  GLOBAL = "bypass, master volume, master gain, master level, master tuning, mix, delta, wet, delta"
}

-- Settings file
local settings_file = r.GetResourcePath() .. "/Scripts/CUCO Random Walk Settings.txt"

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
  
  -- Only use GLOBAL blacklist terms (basic exclusions like bypass, mix, etc.)
  for term in custom_blacklists.GLOBAL:gmatch("([^,]+)") do
    local trimmed = term:match("^%s*(.-)%s*$")
    if trimmed and trimmed ~= "" then
      list[#list + 1] = trimmed:lower()
    end
  end
  
  return list
end

local function is_excluded_param(track, fx, p, exclude_list)
  local ok, name = r.TrackFX_GetParamName(track, fx, p, "")
  if not ok then return false end
  local lname = lower(name)
  
  -- First check traditional blacklist exclusions
  for _, ex in ipairs(exclude_list) do
    if lname:find(ex, 1, true) then return true end
  end
  
  -- Then check smart parameter group exclusions
  local sel_cnt = r.CountSelectedTracks(0)
  for i = 0, sel_cnt - 1 do
    local selected_track = r.GetSelectedTrack(0, i)
    if selected_track == track then
      if fx_list[i] and fx_list[i].fx[fx] and fx_list[i].fx[fx].parameter_groups then
        -- Check if this parameter is in any disabled groups
        for group_name, group_data in pairs(fx_list[i].fx[fx].parameter_groups) do
          if not group_data.enabled then
            for _, param_data in ipairs(group_data.parameters) do
              if param_data.index == p then
                return true  -- Parameter is in a disabled group
              end
            end
          end
        end
      end
      break
    end
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
        r.ShowConsoleMsg(("[Drunk Walk] Auto-detected time range from track items: %.3f to %.3f\n"):format(earliest, latest))
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
    r.ShowConsoleMsg(("[Drunk Walk] Auto-detected time range from selected items: %.3f to %.3f\n"):format(earliest, latest))
    return earliest, latest
  end
  
  return nil  -- No valid range found
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
  if not had_vis then chunk = chunk:gsub("(ACT%s+1[^\\n]*\\n)", "%1VIS 1 1 1\\n") end
  r.SetEnvelopeStateChunk(env, chunk, true)
end

local function ensure_env(track, fx, p)
  return r.GetFXEnvelope(track, fx, p, true)
end

-- Helper function to categorize continuous parameters by name patterns
local function categorize_continuous_param_by_name(name)
  -- PRIORITY RULES FOR CONTINUOUS PARAMS (user specified)
  if name:match("lfo") then
    return "LFOs/Modulation"
  elseif name:match("pitch") or name:match("semitone") or name:match("semi") or name:match("hz") or name:match("herz") then
    return "Pitch"
  elseif name:match("send") or name:match("return") or name:match("pan") or name:match("width") then
    return "Mixing"
  elseif name:match("fx") then
    return "FX"
  
  -- EXISTING RULES (lower priority)
  elseif name:match("^env%d+:") or name:match("^eg %d+") or name:match("amp eg") or name:match("filter eg") then
    return "Envelopes"
  elseif (name:match("attack") or name:match("decay") or name:match("sustain") or name:match("release")) and
         not name:match("eq") and not name:match("band") and not name:match("reverb") then
    return "Envelopes"
  elseif name:match("^osc:") or name:match("^osc %d+") or name:match("[ab] osc %d+") then
    return "Oscillators"
  elseif name:match("^vcf%d*:") or name:match("^hpf:") or name:match("^lpf:") or 
         name:match("filter %d+") or name:match("[ab] filter %d+") then
    return "Filters"
  elseif name:match("^band %d+") or name:match("^eq band %d+") then
    return "EQ/Filters"
  elseif name:match("^delay tap %d+") or name:match("^tap %d+") or name:match("delay") or name:match("echo") or name:match("feedback") then
    return "Delay"
  elseif name:match("reverb") or name:match("room") or name:match("hall") or name:match("plate") then
    return "Reverb"
  elseif name:match("drive") or name:match("distortion") or name:match("overdrive") or name:match("saturation") then
    return "Drive/Distortion"
  elseif name:match("transpose") or name:match("coarse") or name:match("tune") then
    return "Pitch"
  elseif name:match("compressor") or name:match("limiter") or name:match("gate") or name:match("expander") then
    return "Dynamics"
  elseif name:match("volume") or name:match("gain") or name:match("level") or name:match("amplitude") then
    return "Volume/Gain"
  else
    return "Continuous Parameters"
  end
end

-- Check if parameter is in blacklist
local function is_param_blacklisted(param_name, blacklist)
  local lname = lower(param_name or "")
  for _, term in ipairs(blacklist) do
    if lname:find(term, 1, true) then
      return true
    end
  end
  return false
end

-- Final validation check to enforce user-specified categorization rules
-- NO API CALLS HERE - use the step info already obtained to prevent crashes
local function final_parameter_validation(param_name, current_category, param_type, has_steps, param_range, blacklist)
  local name = lower(param_name or "")
  
  -- FIRST: Check blacklist - these should NEVER appear in any category
  if is_param_blacklisted(param_name, blacklist) then
    return nil  -- Remove from all categories
  end
  
  -- SECOND: Enforce binary parameter rules (add "disable" to the list)
  if name:match("mute") or name:match("solo") or name:match("bypass") or name:match("delta") or name:match("mode") or name:match("disable") then
    return "Binary/Switches"  -- Force to binary regardless of current category
  end
  
  -- THIRD: CRITICAL SAFETY CHECK - Use the step info already obtained
  if has_steps then
    -- Reaper says this parameter has discrete steps - it CANNOT be in continuous categories
    if param_range <= 1.1 and param_range >= 0.9 then
      return "Binary/Switches"  -- 0-1 range with steps = binary
    else
      return "Type/Mode Selection"  -- Larger range with steps = discrete selector
    end
  end
  
  -- FOURTH: Only apply continuous rules if parameter is confirmed continuous (has_steps = nil/false)
  if not has_steps then
    -- Apply user-specified functional categorization for continuous parameters only
    if name:match("lfo") then
      return "LFOs/Modulation"
    elseif name:match("pitch") or name:match("semitone") or name:match("semi") or name:match("hz") or name:match("herz") then
      return "Pitch"
    elseif name:match("send") or name:match("return") or name:match("pan") or name:match("width") then
      return "Mixing"
    elseif name:match("fx") then
      return "FX"
    end
    
    -- If no specific continuous rules apply, return the current category (for continuous params only)
    return current_category
  end
  
  -- Should not reach here, but safety fallback
  return current_category
end

-- Analyze parameter characteristics using Reaper's native step size detection
-- BULLETPROOF: Let Reaper tell us which parameters have discrete steps!
local function analyze_parameter_characteristics(track, fx_idx, param_idx, param_name)
  local current, minv, maxv = r.TrackFX_GetParam(track, fx_idx, param_idx)
  if not current then return "function", "Other Parameters", "unknown", nil, 0 end
  
  minv = tonumber(minv) or 0.0
  maxv = tonumber(maxv) or 1.0
  local name = lower(param_name or "")
  local range = maxv - minv
  
  -- THE BULLETPROOF METHOD: Ask Reaper if this parameter has discrete steps (ONLY ONCE)
  local has_steps = r.TrackFX_GetParameterStepSizes(track, fx_idx, param_idx)
  
  if has_steps then
    -- Reaper says this parameter has discrete steps
    if range <= 1.1 and range >= 0.9 then
      -- 0-1 range with steps = binary parameter
      return "function", "Binary/Switches", "binary", has_steps, range
    else
      -- Larger range with steps = discrete selector
      return "function", "Type/Mode Selection", "discrete", has_steps, range
    end
  else
    -- Reaper says this parameter is continuous
    return "function", categorize_continuous_param_by_name(name), "continuous", has_steps, range
  end
end

local function group_fx_parameters(track, fx_idx, fx_name)
  local param_count = r.TrackFX_GetNumParams(track, fx_idx)
  local groups = {}
  
  -- Get blacklist for filtering
  local blacklist = build_exclude_list()
  
  for p = 0, param_count - 1 do
    local param_name = select(2, r.TrackFX_GetParamName(track, fx_idx, p, ""))
    
    -- Get initial categorization from Reaper's analysis (ONLY ONE API CALL)
    local group_type, initial_group_name, param_type, has_steps, param_range = analyze_parameter_characteristics(track, fx_idx, p, param_name)
    
    -- FINAL VALIDATION: Apply user-specified rules and blacklist check (NO ADDITIONAL API CALLS)
    local final_group_name = final_parameter_validation(param_name, initial_group_name, param_type, has_steps, param_range, blacklist)
    
    -- Only add parameter if it passes validation (not blacklisted)
    if final_group_name then
      local group_key = final_group_name
      
      -- Initialize group if it doesn't exist
      if not groups[group_key] then
        -- Default to DISABLED for categories that don't work well with random walks or are too destructive
        local default_enabled = not (
          group_key == "Binary/Switches" or 
          group_key == "Type/Mode Selection" or
          group_key == "Mixing" or
          group_key == "FX" or
          group_key == "Drive/Distortion" or
          group_key == "Volume/Gain" or
          group_key == "Pitch" or
          group_key == "Continuous Parameters"
        )
        
        groups[group_key] = {
          name = group_key,
          parameters = {},
          enabled = default_enabled
        }
      end
      
      -- Add parameter to group with additional info
      groups[group_key].parameters[#groups[group_key].parameters + 1] = {
        index = p,
        name = param_name,
        param_type = param_type  -- Store whether it's binary, discrete, continuous, etc.
      }
    end
    -- If final_group_name is nil, parameter is blacklisted and won't appear anywhere
  end
  
  return groups
end

-- Build FX list from currently selected tracks with smart grouping
local function update_fx_list()
  fx_list = {}
  local sel_cnt = r.CountSelectedTracks(0)
  
  for i = 0, sel_cnt - 1 do
    local track = r.GetSelectedTrack(0, i)
    local ok, track_name = r.GetSetMediaTrackInfo_String(track, "P_NAME", "", false)
    track_name = (ok and track_name ~= "") and track_name or ("Track " .. (i + 1))
    local fx_count = r.TrackFX_GetCount(track)
    
    fx_list[i] = {
      track = track,
      track_name = track_name,
      fx = {}
    }
    
    for fx = 0, fx_count - 1 do
      local ok, fx_name = r.TrackFX_GetFXName(track, fx, "")
      if ok then
        -- Clean up FX name (remove VST3:, etc.)
        fx_name = fx_name:gsub("^VST3?:%s*", ""):gsub("^JS:%s*", ""):gsub("^AU:%s*", "")
        
        -- Generate smart parameter groups for this FX
        local parameter_groups = group_fx_parameters(track, fx, fx_name)
        
        fx_list[i].fx[fx] = {
          name = fx_name,
          enabled = true,  -- FX level enabled/disabled
          parameter_groups = parameter_groups,
          show_groups = false  -- Whether to show the dropdown
        }
        
        -- Initialize expand state for each parameter group
        for group_name, group_data in pairs(parameter_groups) do
          group_data.show_parameters = false  -- Whether to show individual parameters
        end
      end
    end
    
    fx_list[i].fx_count = fx_count  -- Store count for change detection
  end
  
  fx_list_needs_update = false
end

local function fx_ok(track, fx)
  if not r.TrackFX_GetEnabled(track, fx) then return false end
  if r.TrackFX_GetOffline and r.TrackFX_GetOffline(track, fx) then return false end
  
  -- Check if this FX is excluded via the FX list
  local sel_cnt = r.CountSelectedTracks(0)
  for i = 0, sel_cnt - 1 do
    local selected_track = r.GetSelectedTrack(0, i)
    if selected_track == track then
      if fx_list[i] and fx_list[i].fx[fx] then
        return fx_list[i].fx[fx].enabled
      end
      break
    end
  end
  
  return true
end

-- Get selected items' time ranges for the given track
local function get_selected_item_ranges(track)
  local ranges = {}
  local item_count = r.CountSelectedMediaItems(0)
  
  -- If no items are selected, try items on the specific track
  if item_count == 0 then
    local track_item_count = r.CountTrackMediaItems(track)
    for j = 0, track_item_count - 1 do
      local item = r.GetTrackMediaItem(track, j)
      local item_start = r.GetMediaItemInfo_Value(item, "D_POSITION")
      local item_end = item_start + r.GetMediaItemInfo_Value(item, "D_LENGTH")
      ranges[#ranges + 1] = {start = item_start, end_pos = item_end}
    end
  else
    -- Use only selected items that are on this track
    for i = 0, item_count - 1 do
      local item = r.GetSelectedMediaItem(0, i)
      local item_track = r.GetMediaItem_Track(item)
      if item_track == track then
        local item_start = r.GetMediaItemInfo_Value(item, "D_POSITION")
        local item_end = item_start + r.GetMediaItemInfo_Value(item, "D_LENGTH")
        ranges[#ranges + 1] = {start = item_start, end_pos = item_end}
      end
    end
  end
  
  return ranges
end

-- Write using REAL parameter values (min..max), uniform points - ONLY within selected items
local function write_param_real(track, fx, p, t1, t2, count, sev, exclude_list, do_show_envs)
  if is_excluded_param(track, fx, p, exclude_list) then return 0 end

  local cur, minv, maxv = r.TrackFX_GetParam(track, fx, p)
  if not cur then return 0 end
  minv = tonumber(minv) or 0.0
  maxv = tonumber(maxv) or 1.0
  if maxv == minv then maxv = minv + 1.0 end
  local span = (maxv - minv)

  local env = ensure_env(track, fx, p); if not env then return 0 end
  
  -- Get selected item ranges for this track
  local item_ranges = get_selected_item_ranges(track)
  if #item_ranges == 0 then return 0 end  -- No items to process
  
  -- ONLY clear envelope points within selected item ranges (not entire envelope!)
  for _, range in ipairs(item_ranges) do
    r.DeleteEnvelopePointRange(env, range.start, range.end_pos)
  end

  -- Write automation points only within selected item ranges
  for _, range in ipairs(item_ranges) do
    local times = uniform_times(range.start, range.end_pos, count)
    
    -- Brownian walk starting from a random point for each item range
    local v = minv + math.random() * span  -- Start from random point
    for i=1, #times do
      local step = ((math.random()*2 - 1) * sev) * span
      v = clamp(v + step, minv, maxv)
      r.InsertEnvelopePoint(env, times[i], v, 0, 0, false, true)
    end
  end
  
  r.Envelope_SortPoints(env)

  if do_show_envs then
    safe_env_flag(env,"VIS",1); safe_env_flag(env,"ARM",1)
    force_show_env_chunk(env)
  end
  return 1
end

--------------------------------------------------------
-- RENDERING FUNCTIONS
--------------------------------------------------------

-- Render current processed audio to new takes
local function render_to_new_takes(iteration_num, is_final_iteration)
  local t1, t2 = get_time_selection()
  if not t1 then return false end
  
  local sel_cnt = r.CountSelectedTracks(0)
  if sel_cnt == 0 then return false end
  
  -- Clear any existing item selections first
  r.Main_OnCommand(40289, 0) -- Item: Unselect all items
  
  -- Store current active takes and select items within time selection
  local original_takes = {}  -- Store original active takes to restore later
  
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
        
        -- Store the currently active take (whatever it is)
        local current_active_take = r.GetActiveTake(item)
        if current_active_take then
          original_takes[item] = current_active_take
          -- Keep using the current active take (don't change it!)
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
  
  -- Restore original active takes ONLY if this is not the final iteration
  -- On final iteration, the newly created takes will automatically be active
  if not is_final_iteration then
    -- Restore to original takes for next iteration (safe - we know these are valid)
    for item, original_take in pairs(original_takes) do
      if r.ValidatePtr(item, "MediaItem*") and r.ValidatePtr(original_take, "MediaItem_Take*") then
        r.SetActiveTake(original_take)
      end
    end
  end
  -- On final iteration, do nothing - the newly created takes are already active
  
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
  r.Undo_EndBlock("Drunk Walk (GUI): rewrite envelopes (uniform, real values)", -1)

  r.ShowConsoleMsg(("[Drunk Walk GUI - EXPERIMENTAL] tracks=%d  fx=%d  params=%d  envs_written=%d  pts/param=%d  severity=%.3f  show_env=%s\n")
    :format(r.CountSelectedTracks(0), scanned_fx, scanned_params, written, pts, severity, tostring(show_envs)))
end

-- Multi-iteration processing with rendering - SIMPLE VERSION
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
    r.ShowConsoleMsg(("[Drunk Walk GUI - EXPERIMENTAL] Starting iteration %d/%d\n"):format(iteration, num_iterations))
    
    -- Generate new random seed for this iteration
    local seed = (os.time() * iteration + math.floor(r.time_precise()*10000) % 999983) + iteration * 12345
    math.randomseed(seed)
    
    -- STEP 1: Write random automation (EXACTLY like Write Once)
    r.PreventUIRefresh(1)
    local scanned_fx, scanned_params, written = do_single_write(iteration, exclude_list, pts)
    r.TrackList_AdjustWindows(false)
    r.UpdateArrange()
    r.PreventUIRefresh(-1)
    
    r.ShowConsoleMsg(("[Drunk Walk GUI - EXPERIMENTAL] Wrote %d envelopes, now rendering...\n"):format(written))
    
    -- STEP 2: Render to new takes 
    if render_to_takes then
      local is_final_iteration = (iteration == num_iterations)
      render_to_new_takes(iteration, is_final_iteration)
    end
    
    r.ShowConsoleMsg(("[Drunk Walk GUI - EXPERIMENTAL] Completed iteration %d/%d (seed=%d)\n"):format(iteration, num_iterations, seed))
  end
  
  r.Undo_EndBlock("Drunk Walk (GUI): iterative processing " .. num_iterations .. " iterations", -1)
  
  is_processing = false
  
  r.ShowConsoleMsg(("[Drunk Walk GUI - EXPERIMENTAL] All iterations complete!\n"))
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


-- Track change detection
local last_selected_tracks = -1
local fx_list_height = 250  -- Default height for FX list, user can resize

-- Popup state for global blacklist editing
local show_global_blacklist_popup = false
local temp_global_blacklist = ""

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
    
    -- Scrollable area for FX list with smart parameter groupings (resizable)
    r.ImGui_BeginChild(ctx, "FX_List", WINDOW_W - 24, fx_list_height)
    
    for track_idx = 0, #fx_list do
      local track_data = fx_list[track_idx]
      if track_data and track_data.fx and track_data.fx_count and track_data.fx_count > 0 then
        r.ImGui_Text(ctx, track_data.track_name .. ":")
        
        -- Iterate through FX in correct order (0 to fx_count-1)
        for fx_idx = 0, track_data.fx_count - 1 do
          local fx_data = track_data.fx[fx_idx]
          if fx_data then
            -- FX level checkbox
            local changed, enabled = r.ImGui_Checkbox(ctx, "##fx_" .. track_idx .. "_" .. fx_idx, fx_data.enabled)
            if changed then
              fx_data.enabled = enabled
            end
            r.ImGui_SameLine(ctx)
            
            -- FX name with dropdown toggle
            local dropdown_label = fx_data.show_groups and "[-] " or "[+] "
            if r.ImGui_Button(ctx, dropdown_label .. "##dropdown_" .. track_idx .. "_" .. fx_idx, 25, 0) then
              fx_data.show_groups = not fx_data.show_groups
            end
            r.ImGui_SameLine(ctx)
            r.ImGui_Text(ctx, fx_data.name)
            
            -- Show parameter groups if expanded
            if fx_data.show_groups and fx_data.parameter_groups then
              r.ImGui_Indent(ctx)
              
              -- Count total groups
              local group_count = 0
              for _ in pairs(fx_data.parameter_groups) do
                group_count = group_count + 1
              end
              
              if group_count > 0 then
                r.ImGui_Text(ctx, "Parameter Groups:")
                
                -- Sort groups for consistent display
                local sorted_groups = {}
                for group_name, group_data in pairs(fx_data.parameter_groups) do
                  sorted_groups[#sorted_groups + 1] = {name = group_name, data = group_data}
                end
                table.sort(sorted_groups, function(a, b) return a.name < b.name end)
                
                -- Display each group
                for _, group in ipairs(sorted_groups) do
                  local group_name = group.name
                  local group_data = group.data
                  local param_count = #group_data.parameters
                  
                  local group_changed, group_enabled = r.ImGui_Checkbox(
                    ctx, 
                    "##group_" .. track_idx .. "_" .. fx_idx .. "_" .. group_name, 
                    group_data.enabled
                  )
                  if group_changed then
                    group_data.enabled = group_enabled
                  end
                  r.ImGui_SameLine(ctx)
                  
                  -- Group expand/collapse button
                  local group_dropdown_label = group_data.show_parameters and "[-]" or "[+]"
                  if r.ImGui_Button(ctx, group_dropdown_label .. "##group_dropdown_" .. track_idx .. "_" .. fx_idx .. "_" .. group_name, 20, 0) then
                    group_data.show_parameters = not group_data.show_parameters
                  end
                  r.ImGui_SameLine(ctx)
                  r.ImGui_Text(ctx, group_name .. " (" .. param_count .. " params)")
                  
                  -- Show individual parameters if expanded
                  if group_data.show_parameters then
                    r.ImGui_Indent(ctx)
                    for _, param_data in ipairs(group_data.parameters) do
                      r.ImGui_Text(ctx, "• " .. param_data.name)
                    end
                    r.ImGui_Unindent(ctx)
                  end
                end
              else
                r.ImGui_Text(ctx, "No parameter groups detected")
              end
              
              r.ImGui_Unindent(ctx)
            end
          end
        end
        
        r.ImGui_Spacing(ctx)
      end
    end
    
    r.ImGui_EndChild(ctx)
    
    -- Simple height adjustment buttons
    if r.ImGui_Button(ctx, "+", 20, 0) then
      fx_list_height = math.min(500, fx_list_height + 50)
    end
    r.ImGui_SameLine(ctx)
    if r.ImGui_Button(ctx, "-", 20, 0) then
      fx_list_height = math.max(100, fx_list_height - 50)
    end
    r.ImGui_SameLine(ctx)
    r.ImGui_Text(ctx, "FX List Height: " .. fx_list_height .. "px")
    
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

    -- 4) Write buttons
    local button_width = (WINDOW_W - 32) / 2
    if r.ImGui_Button(ctx, "Write Once", button_width, 26) then do_write() end
    r.ImGui_SameLine(ctx)
    
    local button_label = is_processing and "Processing..." or ("Write " .. num_iterations .. " + Render")
    r.ImGui_BeginDisabled(ctx, is_processing)
    if r.ImGui_Button(ctx, button_label, button_width, 26) then 
      do_iterative_write() 
    end
    r.ImGui_EndDisabled(ctx)

    -- 5) Show Envelopes toggle
    local toggled, val = r.ImGui_Checkbox(ctx, "Show envelopes after write", show_envs)
    if toggled then show_envs = val end

    -- 6) Render to takes toggle
    local toggled2, val2 = r.ImGui_Checkbox(ctx, "Render to new takes", render_to_takes)
    if toggled2 then render_to_takes = val2 end

    -- 7) Add ReaLimit toggle
    local toggled3, val3 = r.ImGui_Checkbox(ctx, "Add ReaLimit before render", add_realimit)
    if toggled3 then add_realimit = val3 end

    r.ImGui_Separator(ctx)
    
    -- 8) Global Blacklist Editor
    r.ImGui_Text(ctx, "Global Parameter Blacklist (always excluded):")
    r.ImGui_SameLine(ctx)
    if r.ImGui_Button(ctx, "Edit##GLOBAL_BLACKLIST", 50, 0) then
      show_global_blacklist_popup = true
      temp_global_blacklist = custom_blacklists.GLOBAL
    end
    
    -- Global blacklist popup
    if show_global_blacklist_popup then
      r.ImGui_SetNextWindowSize(ctx, 500, 250)
      r.ImGui_OpenPopup(ctx, "Edit Global Blacklist")
    end
    
    if r.ImGui_BeginPopupModal(ctx, "Edit Global Blacklist", true) then
      r.ImGui_Text(ctx, "Edit Global Blacklist (comma-separated terms):")
      r.ImGui_Text(ctx, "These parameters will ALWAYS be excluded regardless of group settings.")
      r.ImGui_Spacing(ctx)
      
      local text_changed, new_text = r.ImGui_InputTextMultiline(ctx, "##global_blacklist_edit", temp_global_blacklist, 480, 150)
      if text_changed then
        temp_global_blacklist = new_text
      end
      
      r.ImGui_Spacing(ctx)
      if r.ImGui_Button(ctx, "OK", 100, 0) then
        custom_blacklists.GLOBAL = temp_global_blacklist
        save_settings()
        show_global_blacklist_popup = false
        r.ImGui_CloseCurrentPopup(ctx)
      end
      r.ImGui_SameLine(ctx)
      if r.ImGui_Button(ctx, "Cancel", 100, 0) then
        show_global_blacklist_popup = false
        r.ImGui_CloseCurrentPopup(ctx)
      end
      r.ImGui_SameLine(ctx)
      if r.ImGui_Button(ctx, "Reset to Defaults", 150, 0) then
        temp_global_blacklist = "bypass, master volume, master gain, master level, master tuning, mix, delta, wet"
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
