-- @description Move selected items to new individual tracks (auto vertical align)
-- @author Mordi (modded)
-- @version 1.1
-- @link Mordi's website http://www.mordi.net/
-- @screenshot https://i.imgur.com/wESKPou.gif
-- @about
--   Takes all selected items and moves them to new individual tracks.
--   Automatically lines them up vertically at the first selected item's position (no popup).

local SCRIPT_TITLE = "Move selected items to new individual tracks (vertical)"

-- Gather data on selected items
local function get_selected_items_data()
  local t = {}
  for i = 1, reaper.CountSelectedMediaItems(0) do
    local item = reaper.GetSelectedMediaItem(0, i - 1)
    if item then
      local track = reaper.GetMediaItemTrack(item)
      local pos   = reaper.GetMediaItemInfo_Value(item, "D_POSITION")
      local tk_id = reaper.GetMediaItemInfo_Value(item, "I_CURTAKE")
      local tk    = reaper.GetMediaItemTake(item, tk_id)
      local _, name = "", ""
      if tk then _, name = reaper.GetSetMediaItemTakeInfo_String(tk, "P_NAME", "", false) end
      t[#t + 1] = { item = item, track = track, pos = pos, name = name or "" }
    end
  end
  return t
end

-- Get track id of the last track with selected items on it
local function get_last_track_with_selected_items(sel_items_data)
  local count = reaper.CountTracks(0)
  local last_id = 0
  for i = 0, count - 1 do
    local tr = reaper.GetTrack(0, i)
    for n = 1, #sel_items_data do
      if tr == sel_items_data[n].track then
        last_id = i
      end
    end
  end
  return last_id
end

-- Initialize
local sel = get_selected_items_data()
if next(sel) == nil then
  reaper.ShowMessageBox("No items selected", SCRIPT_TITLE, 0)
  return
end

local first_pos = sel[1].pos

reaper.Undo_BeginBlock()
reaper.PreventUIRefresh(1)

local items_track_id = get_last_track_with_selected_items(sel)

-- Loop through selected items
for i = 1, #sel do
  -- Add new track after the last track that had selected items (stacking downward)
  local tr_index = items_track_id + i
  reaper.InsertTrackAtIndex(tr_index, true)

  -- Get new track
  local tr = reaper.GetTrack(0, tr_index)

  -- Rename track to take name (if any)
  reaper.GetSetMediaTrackInfo_String(tr, "P_NAME", sel[i].name, true)

  -- Move item to this new track
  reaper.MoveMediaItemToTrack(sel[i].item, tr)

  -- Align item position to the first selected item's position (vertical line-up)
  reaper.SetMediaItemPosition(sel[i].item, first_pos, false)
end

reaper.PreventUIRefresh(-1)
reaper.Undo_EndBlock(SCRIPT_TITLE, 0)
reaper.UpdateArrange()
