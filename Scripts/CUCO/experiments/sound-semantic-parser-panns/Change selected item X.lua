-- @description Change selected item X
-- @version 1.0
-- @author f.god

function main()
  -- Get the number of selected media items
  local selected_items_count = reaper.CountSelectedMediaItems(0)

  if selected_items_count == 0 then
    reaper.ShowConsoleMsg("No media items selected.\\n")
    return
  end

  -- Get the first selected media item
  local item = reaper.GetSelectedMediaItem(0, 0)

  if not item then
    reaper.ShowConsoleMsg("Error: Could not get selected item.\\n")
    return
  end

  -- Get the active take of the item
  local take = reaper.GetActiveTake(item)
  if not take then
    reaper.ShowConsoleMsg("Error: Selected item has no active take.\\n")
    return
  end

  -- Get the source of the take
  local source = reaper.GetMediaItemTake_Source(take)
  if not source then
    reaper.ShowConsoleMsg("Error: Could not get take source.\\n")
    return
  end

  -- Get the filename of the source
  local _, filename = reaper.GetMediaSourceFileName(source, "")
  if filename and filename ~= "" then
    reaper.ShowConsoleMsg("Selected item source file: " .. filename .. "\\n")

    -- Placeholder for your action "X"
    -- Example: Set item length to 1 second
    -- reaper.SetMediaItemInfo_Value(item, "D_LENGTH", 1.0)

  else
    reaper.ShowConsoleMsg("Selected item does not have a source file (e.g., it's empty or MIDI).\\n")
  end
end

-- Start the script
reaper.defer(main)