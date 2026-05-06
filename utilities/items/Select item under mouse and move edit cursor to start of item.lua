-- Select item under mouse and move edit cursor to start of item
-- Simple ReaScript for mouse modifier action

reaper.GetTakeStretchMarker

-- Get current mouse position
local x, y = reaper.GetMousePosition()

-- Convert screen coordinates to arrange view coordinates and find item
local item = reaper.GetItemFromPoint(x, y, true)

if item then
    -- Clear current selection
    reaper.SelectAllMediaItems(0, false)
    
    -- Select the item under mouse
    reaper.SetMediaItemSelected(item, true)
    
    -- Get item position and move edit cursor there
    local item_pos = reaper.GetMediaItemInfo_Value(item, "D_POSITION")
    reaper.SetEditCurPos(item_pos, true, true)
    
    -- Update arrange view
    reaper.UpdateArrange()
else
    -- No item under mouse - optionally show debug message
    -- reaper.ShowConsoleMsg("No item found under mouse cursor\n")
end

-- No undo point needed for this simple action