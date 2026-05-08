-- @description Play from Start of Selected Media Items (No Solo, No Time Selection)
-- @version 1.0
-- @about
--   Move edit cursor to the start of selected media items and play, without changing time selection or soloing.
-- @author Modified from Stephen Schappler

-- Save current edit cursor position
local start_pos = reaper.GetCursorPosition()

-- Get the selected media items
local selected_items = {}
local num_selected_items = reaper.CountSelectedMediaItems(0)
for i = 0, num_selected_items - 1 do
    selected_items[#selected_items + 1] = reaper.GetSelectedMediaItem(0, i)
end

-- Move cursor to earliest selected item (if any)
if #selected_items > 0 then
    local earliest_start_pos = reaper.GetMediaItemInfo_Value(selected_items[1], "D_POSITION")
    for _, item in ipairs(selected_items) do
        local item_start_pos = reaper.GetMediaItemInfo_Value(item, "D_POSITION")
        if item_start_pos < earliest_start_pos then
            earliest_start_pos = item_start_pos
        end
    end
    reaper.SetEditCurPos(earliest_start_pos, false, false)
end

-- Start playback
reaper.OnPlayButton()

-- Optional: Restore cursor position after playback stops
local function RestoreCursorAfterStop()
    if reaper.GetPlayState() == 0 then
        reaper.SetEditCurPos(start_pos, false, false)
    else
        reaper.defer(RestoreCursorAfterStop)
    end
end
reaper.defer(RestoreCursorAfterStop)
