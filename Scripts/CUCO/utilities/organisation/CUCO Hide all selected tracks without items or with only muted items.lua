--[[
  @description Hide selected tracks with no unmuted items; folders only if all descendants are empty or muted (uses action 41593)
  @author curl + ChatGPT
  @version 1.1
  @about
    For each selected track: hides if empty or only muted items (folders only if no unmuted items in self or descendants). Uses standard action 41593.
]]

function has_unmuted_item_or_descendants(track)
  -- Check own items
  local item_cnt = reaper.CountTrackMediaItems(track)
  for i = 0, item_cnt-1 do
    local item = reaper.GetTrackMediaItem(track, i)
    if reaper.GetMediaItemInfo_Value(item, "B_MUTE") < 0.5 then
      return true
    end
  end
  -- Check children if folder
  if reaper.GetMediaTrackInfo_Value(track, "I_FOLDERDEPTH") == 1 then
    local idx = reaper.GetMediaTrackInfo_Value(track, "IP_TRACKNUMBER") - 1
    local total = reaper.CountTracks(0)
    local folder_depth = 1
    for i = idx + 1, total - 1 do
      local t = reaper.GetTrack(0, i)
      local d = reaper.GetMediaTrackInfo_Value(t, "I_FOLDERDEPTH")
      folder_depth = folder_depth + d
      if folder_depth <= 0 then break end
      if has_unmuted_item_or_descendants(t) then
        return true
      end
    end
  end
  return false
end

function main()
  reaper.Undo_BeginBlock()

  -- Save current track selection
  local orig_sel = {}
  for i = 0, reaper.CountTracks(0)-1 do
    local tr = reaper.GetTrack(0, i)
    if reaper.IsTrackSelected(tr) then table.insert(orig_sel, tr) end
  end

  -- Build list of tracks to hide
  local to_hide = {}
  for _, tr in ipairs(orig_sel) do
    local is_folder = reaper.GetMediaTrackInfo_Value(tr, "I_FOLDERDEPTH") == 1
    if not is_folder then
      local item_cnt = reaper.CountTrackMediaItems(tr)
      local any_unmuted = false
      for j = 0, item_cnt-1 do
        local item = reaper.GetTrackMediaItem(tr, j)
        if reaper.GetMediaItemInfo_Value(item, "B_MUTE") < 0.5 then
          any_unmuted = true
          break
        end
      end
      if item_cnt == 0 or not any_unmuted then
        table.insert(to_hide, tr)
      end
    else
      if not has_unmuted_item_or_descendants(tr) then
        table.insert(to_hide, tr)
      end
    end
  end

  -- Deselect all, then select only tracks to hide
  reaper.Main_OnCommand(40297, 0) -- Unselect all tracks
  for _, tr in ipairs(to_hide) do
    reaper.SetTrackSelected(tr, true)
  end

  if #to_hide > 0 then
    reaper.Main_OnCommand(41593, 0) -- Track: Hide selected tracks in TCP and MCP
  end

  -- Restore original selection
  reaper.Main_OnCommand(40297, 0)
  for _, tr in ipairs(orig_sel) do
    reaper.SetTrackSelected(tr, true)
  end

  reaper.Undo_EndBlock("Hide selected tracks with no unmuted items (folders only if all descendants muted/empty)", -1)
end

main()
