-- diff_engine.lua
-- CUCO-DIFF diffing engine
-- Compares two .rpp files and emits semantic events.

require 'modules.Reateam_RPP-Parser'

local diff_engine = {}

-- Event category constants
diff_engine.CATEGORIES = {
  TRACKS = "tracks",
  ITEMS = "media_items",
  FX = "fx_plugins",
  AUTOMATION = "automation",
  PROJECT = "project_settings",
  NOTES = "notes",
  HOUSEKEEPING = "housekeeping",
}

local function get_tracks(rpp_root)
  if not rpp_root then return {} end
  return rpp_root:findAllChunksByName("TRACK")
end

local function get_track_name(track_chunk)
    local name_node = track_chunk:findFirstNodeByName("NAME")
    if name_node then
        return name_node:getParam(1):getString()
    end
    return "Unnamed Track"
end

local function get_track_guid(track_chunk)
    local guid_node = track_chunk:findFirstNodeByName("TRACKID")
    if guid_node then
        return guid_node:getParam(1):getString()
    end
    return nil
end

local function get_track_key(track_chunk, index)
    -- Use GUID if available, otherwise fall back to position + name
    local guid = get_track_guid(track_chunk)
    if guid then
        return "guid:" .. guid
    else
        local name = get_track_name(track_chunk)
        return "pos:" .. index .. ":" .. name
    end
end

local function get_items(track_chunk)
  if not track_chunk then return {} end
  return track_chunk:findAllChunksByName("ITEM")
end

local function get_fx_chain(track_chunk)
  if not track_chunk then return nil end
  return track_chunk:findFirstChunkByName("FXCHAIN")
end

local function get_fx_list(fx_chain)
  if not fx_chain then return {} end
  local fx_list = {}
  -- Get all FX types
  local vst_fx = fx_chain:findAllChunksByName("VST") or {}
  local au_fx = fx_chain:findAllChunksByName("AU") or {}
  local js_fx = fx_chain:findAllChunksByName("JS") or {}
  local dx_fx = fx_chain:findAllChunksByName("DX") or {}
  
  -- Combine all FX types
  for _, fx in ipairs(vst_fx) do table.insert(fx_list, fx) end
  for _, fx in ipairs(au_fx) do table.insert(fx_list, fx) end
  for _, fx in ipairs(js_fx) do table.insert(fx_list, fx) end
  for _, fx in ipairs(dx_fx) do table.insert(fx_list, fx) end
  
  return fx_list
end

local function get_envelopes(track_chunk)
  if not track_chunk then return {} end
  local envelopes = {}
  -- Get all envelope types
  local vol_env = track_chunk:findAllChunksByName("VOLENV") or {}
  local pan_env = track_chunk:findAllChunksByName("PANENV") or {}
  local mute_env = track_chunk:findAllChunksByName("MUTEENV") or {}
  local parm_env = track_chunk:findAllChunksByName("PARMENV") or {}
  
  -- Combine all envelope types
  for _, env in ipairs(vol_env) do table.insert(envelopes, env) end
  for _, env in ipairs(pan_env) do table.insert(envelopes, env) end
  for _, env in ipairs(mute_env) do table.insert(envelopes, env) end
  for _, env in ipairs(parm_env) do table.insert(envelopes, env) end
  
  return envelopes
end

local function get_project_settings(rpp_root)
  if not rpp_root then return {} end
  local settings = {}
  -- Get tempo
  local tempo_node = rpp_root:findFirstNodeByName("TEMPO")
  if tempo_node then settings.tempo = tempo_node:getParam(1):getString() end
  -- Get time signature
  local timesig_node = rpp_root:findFirstNodeByName("TIMESIG")
  if timesig_node then settings.timesig = timesig_node:getParam(1):getString() .. "/" .. timesig_node:getParam(2):getString() end
  return settings
end

local function get_notes(rpp_root)
  if not rpp_root then return "" end
  local notes_chunk = rpp_root:findFirstChunkByName("NOTES")
  if notes_chunk then
    return notes_chunk:getTextNotes()
  end
  return ""
end

function diff_engine.Compare(rpp_content_old, rpp_content_new)
  local rpp_old = ReadRPPChunk(rpp_content_old)
  local rpp_new = ReadRPPChunk(rpp_content_new)

  local result = {
    events = {},
    summary = "",
    timestamp = os.time(),
  }

  local tracks_old = get_tracks(rpp_old)
  local tracks_new = get_tracks(rpp_new)

  -- Track changes - use GUID-based or position-based matching
  local tracks_old_by_key = {}
  for i, track in ipairs(tracks_old) do
    local key = get_track_key(track, i)
    tracks_old_by_key[key] = track
  end

  local tracks_new_by_key = {}
  for i, track in ipairs(tracks_new) do
    local key = get_track_key(track, i)
    tracks_new_by_key[key] = track
  end

  -- Detect added/removed tracks
  -- Added tracks (exist in new but not in old)
  for key, new_track in pairs(tracks_new_by_key) do
    if not tracks_old_by_key[key] then
      local name = get_track_name(new_track)
      table.insert(result.events, {
        type = "TRACK_ADD",
        track = name,
        category = diff_engine.CATEGORIES.TRACKS,
        action = "added",
        description = "Added track: " .. name,
      })
    end
  end

  -- Removed tracks (exist in old but not in new)
  for key, old_track in pairs(tracks_old_by_key) do
    if not tracks_new_by_key[key] then
      local name = get_track_name(old_track)
      table.insert(result.events, {
        type = "TRACK_REMOVE",
        track = name,
        category = diff_engine.CATEGORIES.TRACKS,
        action = "removed",
        description = "Removed track: " .. name,
      })
    end
  end

  -- Compare tracks that exist in both versions
  for key, new_track in pairs(tracks_new_by_key) do
    local old_track = tracks_old_by_key[key]
    if old_track then
      local name = get_track_name(new_track)
      
      -- Compare items
      local old_items = get_items(old_track)
      local new_items = get_items(new_track)
      if #new_items > #old_items then
        table.insert(result.events, {
          type = "ITEM_ADD",
          track = name,
          category = diff_engine.CATEGORIES.ITEMS,
          action = "added",
          description = string.format("Added %d item(s) on track: %s", #new_items - #old_items, name),
        })
      elseif #new_items < #old_items then
        table.insert(result.events, {
          type = "ITEM_REMOVE",
          track = name,
          category = diff_engine.CATEGORIES.ITEMS,
          action = "removed",
          description = string.format("Removed %d item(s) from track: %s", #old_items - #new_items, name),
        })
      end

      -- Compare FX
      local old_fx_chain = get_fx_chain(old_track)
      local new_fx_chain = get_fx_chain(new_track)
      local old_fx = get_fx_list(old_fx_chain)
      local new_fx = get_fx_list(new_fx_chain)
      if #new_fx > #old_fx then
        table.insert(result.events, {
          type = "FX_ADD",
          track = name,
          category = diff_engine.CATEGORIES.FX,
          action = "added",
          description = string.format("Added %d FX plugin(s) on track: %s", #new_fx - #old_fx, name),
        })
      elseif #new_fx < #old_fx then
        table.insert(result.events, {
          type = "FX_REMOVE",
          track = name,
          category = diff_engine.CATEGORIES.FX,
          action = "removed",
          description = string.format("Removed %d FX plugin(s) from track: %s", #old_fx - #new_fx, name),
        })
      end

      -- Compare automation envelopes
      local old_env = get_envelopes(old_track)
      local new_env = get_envelopes(new_track)
      if #new_env > #old_env then
        table.insert(result.events, {
          type = "AUTOMATION_ADD",
          track = name,
          category = diff_engine.CATEGORIES.AUTOMATION,
          action = "added",
          description = string.format("Added automation on track: %s", name),
        })
      elseif #new_env < #old_env then
        table.insert(result.events, {
          type = "AUTOMATION_REMOVE",
          track = name,
          category = diff_engine.CATEGORIES.AUTOMATION,
          action = "removed",
          description = string.format("Removed automation from track: %s", name),
        })
      end
    end
  end

  -- Compare project settings
  local old_settings = get_project_settings(rpp_old)
  local new_settings = get_project_settings(rpp_new)
  if old_settings.tempo ~= new_settings.tempo then
    table.insert(result.events, {
      type = "TEMPO_CHANGE",
      category = diff_engine.CATEGORIES.PROJECT,
      action = "changed",
      description = string.format("Tempo changed from %s to %s", old_settings.tempo or "unknown", new_settings.tempo or "unknown"),
    })
  end
  if old_settings.timesig ~= new_settings.timesig then
    table.insert(result.events, {
      type = "TIMESIG_CHANGE",
      category = diff_engine.CATEGORIES.PROJECT,
      action = "changed",
      description = string.format("Time signature changed from %s to %s", old_settings.timesig or "unknown", new_settings.timesig or "unknown"),
    })
  end

  -- Compare notes
  local old_notes = get_notes(rpp_old)
  local new_notes = get_notes(rpp_new)
  if old_notes ~= new_notes then
    table.insert(result.events, {
      type = "NOTES_CHANGE",
      category = diff_engine.CATEGORIES.NOTES,
      action = "changed",
      description = "Project notes changed",
    })
  end

  -- Generate summary
  local event_counts = {}
  for _, event in ipairs(result.events) do
    event_counts[event.category] = (event_counts[event.category] or 0) + 1
  end

  local summary_parts = {}
  for category, count in pairs(event_counts) do
    table.insert(summary_parts, string.format("%d %s change(s)", count, category))
  end

  if #summary_parts > 0 then
    result.summary = table.concat(summary_parts, "; ")
  else
    result.summary = "No significant changes detected"
  end

  return result
end

local function read_file(path)
  local f = io.open(path, 'r')
  if not f then return nil end
  local c = f:read('*a'); f:close(); return c
end

function diff_engine.CompareFiles(path_old, path_new)
  local c1 = read_file(path_old)
  local c2 = read_file(path_new)
  if not c1 or not c2 then
    return { events = {}, summary = 'Failed to read one or both files', timestamp = os.time() }
  end
  return diff_engine.Compare(c1, c2)
end

return diff_engine
