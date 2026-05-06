-- Simple test version
local x, y = reaper.GetMousePosition()
local item = reaper.GetItemFromPoint(x, y, true)

if item then
    reaper.SelectAllMediaItems(0, false)
    reaper.SetMediaItemSelected(item, true)
    local item_pos = reaper.GetMediaItemInfo_Value(item, "D_POSITION")
    reaper.SetEditCurPos(item_pos, true, true)
    reaper.UpdateArrange()
end