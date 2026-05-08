--[[
  @description Hierarchical timeline sort: Each sibling group reordered by earliest unmuted item (folder structure preserved)
  @author curl + ChatGPT
  @version 1.4
  @about
    Recursively sorts selected tracks and all their children by timeline (earliest unmuted item).
    Siblings are only reordered among themselves, never leaving their parent. Muted items are ignored.
]]

-- things to update: handle folder tracks correctly. at the moment running the script on a selection of tracks with different hierarchies breaks the folder structure completely

-- Returns the earliest unmuted item position for a track and all descendants (nil if none)
function get_earliest_unmuted_item(track)
  local earliest = nil
  -- Check own items
  local cnt = reaper.CountTrackMediaItems(track)
  for i = 0, cnt-1 do
    local item = reaper.GetTrackMediaItem(track, i)
    local muted = reaper.GetMediaItemInfo_Value(item, "B_MUTE")
    if muted < 0.5 then
      local pos = reaper.GetMediaItemInfo_Value(item, "D_POSITION")
      if not earliest or pos < earliest then earliest = pos end
    end
  end
  -- Check children if folder
  local idx = reaper.GetMediaTrackInfo_Value(track, "IP_TRACKNUMBER") - 1
  if reaper.GetMediaTrackInfo_Value(track, "I_FOLDERDEPTH") == 1 then
    local depth = 1
    local total = reaper.CountTracks(0)
    for i = idx+1, total-1 do
      local t = reaper.GetTrack(0, i)
      local d = reaper.GetMediaTrackInfo_Value(t, "I_FOLDERDEPTH")
      depth = depth + d
      if depth <= 0 then break end
      local child_earliest = get_earliest_unmuted_item(t)
      if child_earliest and (not earliest or child_earliest < earliest) then
        earliest = child_earliest
      end
    end
  end
  return earliest
end

-- Get the immediate children (contiguous block) of a folder or parent at parent_idx
function get_immediate_children(parent_idx)
  local children = {}
  local total = reaper.CountTracks(0)
  local parent = parent_idx and reaper.GetTrack(0, parent_idx) or nil
  local i = (parent_idx and parent_idx+1) or 0
  local depth = parent and 1 or 0
  while i < total do
    local t = reaper.GetTrack(0, i)
    if parent then
      local d = reaper.GetMediaTrackInfo_Value(t, "I_FOLDERDEPTH")
      depth = depth + d
      if depth <= 0 then break end
    end
    -- Only count as child if direct child (not nested deeper)
    if not parent or (reaper.GetParentTrack and reaper.GetParentTrack(t) == parent) then
      table.insert(children, i)
    elseif parent then
      -- If nested deeper, skip; we only want immediate children
      local d = reaper.GetMediaTrackInfo_Value(t, "I_FOLDERDEPTH")
      if d == 1 then
        local folder_depth = 1
        while folder_depth > 0 and i < total-1 do
          i = i + 1
          t = reaper.GetTrack(0, i)
          local d2 = reaper.GetMediaTrackInfo_Value(t, "I_FOLDERDEPTH")
          folder_depth = folder_depth + d2
        end
      end
    end
    i = i + 1
  end
  return children
end

-- Recursively sort each sibling group (indices)
function sort_sibling_group(indices)
  if #indices < 2 then return end
  -- Get tracks and their earliest item position
  local siblings = {}
  for _, idx in ipairs(indices) do
    local tr = reaper.GetTrack(0, idx)
    table.insert(siblings, {
      idx = idx,
      track = tr,
      earliest = get_earliest_unmuted_item(tr)
    })
  end
  -- Sort by earliest item (tracks with no unmuted items go last)
  table.sort(siblings, function(a, b)
    if a.earliest == b.earliest then return a.idx < b.idx
    elseif not a.earliest then return false
    elseif not b.earliest then return true
    else return a.earliest < b.earliest end
  end)
  -- Move tracks in order, always to first original index + offset (only among these siblings!)
  local min_idx = math.huge
  for i = 1, #siblings do
    if siblings[i].idx < min_idx then min_idx = siblings[i].idx end
  end
  for i = 1, #siblings do
    reaper.SetOnlyTrackSelected(siblings[i].track)
    reaper.ReorderSelectedTracks(min_idx + i - 1, 0)
  end
  -- Now recursively sort children of any folder among these siblings
  for i = 1, #siblings do
    local tr = siblings[i].track
    if reaper.GetMediaTrackInfo_Value(tr, "I_FOLDERDEPTH") == 1 then
      local folder_idx = reaper.GetMediaTrackInfo_Value(tr, "IP_TRACKNUMBER") - 1
      -- Get immediate children
      local children = {}
      local total = reaper.CountTracks(0)
      local depth = 1
      for j = folder_idx + 1, total - 1 do
        local t = reaper.GetTrack(0, j)
        local d = reaper.GetMediaTrackInfo_Value(t, "I_FOLDERDEPTH")
        depth = depth + d
        if depth <= 0 then break end
        -- Only direct children
        if not (reaper.GetMediaTrackInfo_Value(t, "I_FOLDERDEPTH") == 1) then
          table.insert(children, j)
        end
      end
      if #children > 1 then
        sort_sibling_group(children)
      end
    end
  end
end

function main()
  reaper.Undo_BeginBlock()

  -- For every contiguous selected top-level track group, sort recursively
  local total = reaper.CountTracks(0)
  local i = 0
  while i < total do
    local tr = reaper.GetTrack(0, i)
    if reaper.IsTrackSelected(tr) then
      -- Find contiguous block
      local block = {i}
      local j = i + 1
      while j < total and reaper.IsTrackSelected(reaper.GetTrack(0, j)) do
        table.insert(block, j)
        j = j + 1
      end
      sort_sibling_group(block)
      i = j
    else
      i = i + 1
    end
  end

  reaper.Undo_EndBlock("Hierarchical sort: each sibling group by earliest unmuted item, preserve folders", -1)
end

main()
