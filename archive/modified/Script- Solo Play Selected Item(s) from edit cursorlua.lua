-- @description Solo Selected Media Items, Set Time Selection, and Play, Unsolo on Stop
-- @version 1.3-mod
-- @about
--   Solo selected media items, set time selection to their range, play them FROM THE EDIT CURSOR, and unsolo when playback stops
-- @author Stephen Schappler, modded by curl/tony

local start_pos = reaper.GetCursorPosition()
local time_sel_start, time_sel_end = reaper.GetSet_LoopTimeRange(false, false, 0, 0, false)

local selected_items = {}
local num_selected_items = reaper.CountSelectedMediaItems(0)
for i = 0, num_selected_items - 1 do
    selected_items[#selected_items + 1] = reaper.GetSelectedMediaItem(0, i)
end

local stop_at_loop_cmd = 41834
local original_stop_at_loop_setting = reaper.GetToggleCommandState(stop_at_loop_cmd)
if original_stop_at_loop_setting ~= 1 then
    reaper.Main_OnCommand(stop_at_loop_cmd, 0)
end

local function SoloItems(solo)
    for _, item in ipairs(selected_items) do
        local take = reaper.GetActiveTake(item)
        if take then
            local track = reaper.GetMediaItem_Track(item)
            reaper.SetMediaTrackInfo_Value(track, "I_SOLO", solo and 1 or 0)
        end
    end
end

local function UnsoloItemsAfterDelay()
    reaper.defer(function()
        SoloItems(false)
        reaper.GetSet_LoopTimeRange(true, false, time_sel_start, time_sel_end, false)
        reaper.SetEditCurPos(start_pos, false, false)
        if reaper.GetToggleCommandState(stop_at_loop_cmd) ~= original_stop_at_loop_setting then
            reaper.Main_OnCommand(stop_at_loop_cmd, 0)
        end
    end)
end

local function StopAtTimeSelectionEnd(end_time)
    if reaper.GetPlayState() == 0 then
        reaper.defer(UnsoloItemsAfterDelay)
        return
    end

    if reaper.GetPlayPosition() >= end_time then
        reaper.OnStopButton()
        reaper.defer(UnsoloItemsAfterDelay)
        return
    end

    reaper.defer(function() StopAtTimeSelectionEnd(end_time) end)
end

-- Set time selection from selected items, but DON'T move the cursor!
if #selected_items > 0 then
    local earliest_start_pos = reaper.GetMediaItemInfo_Value(selected_items[1], "D_POSITION")
    local latest_end_pos = earliest_start_pos + reaper.GetMediaItemInfo_Value(selected_items[1], "D_LENGTH")

    for _, item in ipairs(selected_items) do
        local item_start_pos = reaper.GetMediaItemInfo_Value(item, "D_POSITION")
        local item_end_pos = item_start_pos + reaper.GetMediaItemInfo_Value(item, "D_LENGTH")
        if item_start_pos < earliest_start_pos then
            earliest_start_pos = item_start_pos
        end
        if item_end_pos > latest_end_pos then
            latest_end_pos = item_end_pos
        end
    end

    -- REMOVE THIS LINE TO PREVENT MOVING CURSOR:
    -- reaper.SetEditCurPos(earliest_start_pos, false, false)

    -- Still set time selection for context:
    reaper.GetSet_LoopTimeRange(true, false, earliest_start_pos, latest_end_pos, false)
end

SoloItems(true)
reaper.OnPlayButton()

if #selected_items > 0 then
    local latest_end_pos = reaper.GetMediaItemInfo_Value(selected_items[1], "D_POSITION") + reaper.GetMediaItemInfo_Value(selected_items[1], "D_LENGTH")
    for _, item in ipairs(selected_items) do
        local item_end_pos = reaper.GetMediaItemInfo_Value(item, "D_POSITION") + reaper.GetMediaItemInfo_Value(item, "D_LENGTH")
        if item_end_pos > latest_end_pos then
            latest_end_pos = item_end_pos
        end
    end
    reaper.defer(function() StopAtTimeSelectionEnd(latest_end_pos) end)
end 
