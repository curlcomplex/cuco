-- @description Toggle mute on all items of selected track with GUI
-- @version 1.1
-- @author curl

local reaper = reaper
local ctx = reaper.ImGui_CreateContext('Track Item Mute Toggler')
local visible = true

local itemStates = {}
local itemRefs = {}
local last_track = nil

-- Fetch all items from the first selected track
function refreshItemList()
  local track = reaper.GetSelectedTrack(0, 0)
  if not track then
    itemStates = {}
    itemRefs = {}
    last_track = nil
    return
  end

  -- Only refresh if track changed
  if track == last_track then return end
  last_track = track

  itemStates = {}
  itemRefs = {}

  local item_count = reaper.CountTrackMediaItems(track)
  for i = 0, item_count - 1 do
    local item = reaper.GetTrackMediaItem(track, i)
    local mute = reaper.GetMediaItemInfo_Value(item, "B_MUTE") == 1
    table.insert(itemRefs, item)
    table.insert(itemStates, mute)
  end
end

-- Draw the GUI
function main()
  if not reaper.ImGui_Begin(ctx, 'Track Item Mute Toggler', true, reaper.ImGui_WindowFlags_AlwaysAutoResize()) then
    reaper.ImGui_End(ctx)
    return
  end

  local track = reaper.GetSelectedTrack(0, 0)

  if not track then
    reaper.ImGui_Text(ctx, "No track selected.")
  else
    refreshItemList()

    if #itemRefs == 0 then
      reaper.ImGui_Text(ctx, "Track has no items.")
    else
      for i, item in ipairs(itemRefs) do
        local item_name = "Item " .. i
        local mute = itemStates[i]
        local label = mute and ("Unmute " .. item_name) or ("Mute " .. item_name)

        if reaper.ImGui_Button(ctx, label) then
          mute = not mute
          itemStates[i] = mute
          reaper.SetMediaItemInfo_Value(item, "B_MUTE", mute and 1 or 0)
          reaper.UpdateArrange()
        end

        -- Optional: show item position or length info
        local pos = reaper.GetMediaItemInfo_Value(item, "D_POSITION")
        local len = reaper.GetMediaItemInfo_Value(item, "D_LENGTH")
        reaper.ImGui_SameLine(ctx)
        reaper.ImGui_Text(ctx, string.format("(%.2fs – %.2fs)", pos, pos + len))
      end
    end
  end

  reaper.ImGui_End(ctx)
end

-- Loop wrapper
function loop()
  if visible then
    main()
    reaper.defer(loop)
  else
    reaper.ImGui_DestroyContext(ctx)
  end
end

-- Kick it off
reaper.defer(loop)
