-- Script: Create Razor Edit Bounding Box from Selected Items
-- Description: Creates a single razor edit from the earliest start to the latest end of selected items on their respective tracks.

function main()
  local count = reaper.CountSelectedMediaItems(0)
  if count == 0 then return end

  local min_start = math.huge
  local max_end = -math.huge
  local tracks = {}

  -- 1. Find the bounding box time range and involved tracks
  for i = 0, count - 1 do
    local item = reaper.GetSelectedMediaItem(0, i)
    local start_pos = reaper.GetMediaItemInfo_Value(item, "D_POSITION")
    local len = reaper.GetMediaItemInfo_Value(item, "D_LENGTH")
    local end_pos = start_pos + len
    local track = reaper.GetMediaItem_Track(item)

    if start_pos < min_start then min_start = start_pos end
    if end_pos > max_end then max_end = end_pos end
    
    tracks[track] = true -- Store track in a table (using track pointer as key to avoid duplicates)
  end

  reaper.PreventUIRefresh(1)
  reaper.Undo_BeginBlock()

  -- 2. Clear existing Razor Edits (Optional - remove this block if you want to add to existing selections)
  -- To clear, we usually just set a new one, but if you want to be safe you can iterate all tracks.
  -- For this workflow, setting the new string usually overrides or adds depending on API usage. 
  -- We will overwrite for cleanliness on the specific tracks.

  -- 3. Apply the Razor Edit to each involved track
  local razor_string = string.format('%.20f %.20f ""', min_start, max_end)
  
  for track, _ in pairs(tracks) do
    reaper.GetSetMediaTrackInfo_String(track, "P_RAZOREDITS", razor_string, true)
  end

  reaper.Undo_EndBlock("Set Razor Edit to Selection Bounding Box", -1)
  reaper.PreventUIRefresh(-1)
  reaper.UpdateArrange()
end

main()
