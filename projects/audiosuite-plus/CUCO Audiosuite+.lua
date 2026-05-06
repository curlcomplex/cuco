-- @description Audiosuite MVP UI
-- @version 0.4

local ctx = reaper.ImGui_CreateContext('Audiosuite MVP')

function get_selected_track_and_items()
    local num_sel_items = reaper.CountSelectedMediaItems(0)
    local tr = nil
    if num_sel_items > 0 then
        local first_item = reaper.GetSelectedMediaItem(0, 0)
        tr = reaper.GetMediaItem_Track(first_item)
    end
    return tr, num_sel_items
end

function get_track_name(tr)
    if not tr then return "(none)" end
    local _, name = reaper.GetTrackName(tr, "")
    if name == "" then
        local tr_idx = reaper.GetMediaTrackInfo_Value(tr, 'IP_TRACKNUMBER')
        return 'Track '..tostring(tr_idx)
    else
        return name
    end
end

function core_render()
    reaper.ClearConsole()
    reaper.Undo_BeginBlock()

    local num_sel_items = reaper.CountSelectedMediaItems(0)
    reaper.ShowConsoleMsg("Selected items: " .. num_sel_items .. "\n")
    if num_sel_items == 0 then
        reaper.ShowConsoleMsg("No items selected.\n")
        reaper.Undo_EndBlock("Audiosuite MVP: No items", -1)
        return
    end

    local items = {}
    for i = 0, num_sel_items-1 do
        items[#items+1] = reaper.GetSelectedMediaItem(0, i)
    end

    for i, item in ipairs(items) do
        if item then
            local take = reaper.GetActiveTake(item)
            if take then
                local fx_count = reaper.TakeFX_GetCount(take)
                reaper.ShowConsoleMsg("Item " .. i .. ": Active take, FX count: " .. fx_count .. "\n")
                -- Offline all take FX
                for fx = 0, fx_count-1 do
                    reaper.TakeFX_SetOffline(take, fx, true)
                    reaper.ShowConsoleMsg("  Set take FX " .. fx .. " offline.\n")
                end
                -- Select only this item
                reaper.Main_OnCommand(40289, 0) -- Unselect all items
                reaper.SetMediaItemSelected(item, true)
                -- Render track FX to new take
                local num_takes_before = reaper.GetMediaItemNumTakes(item)
                reaper.Main_OnCommand(40209, 0) -- Item: Apply track FX to items as new take
                local num_takes_after = reaper.GetMediaItemNumTakes(item)
                reaper.ShowConsoleMsg("  Takes before: " .. num_takes_before .. ", after: " .. num_takes_after .. "\n")
                if num_takes_after > num_takes_before then
                    reaper.ShowConsoleMsg("  New take successfully created!\n")
                    -- Restore take FX online for original take
                    local orig_take = reaper.GetMediaItemTake(item, 0)
                    for fx = 0, fx_count-1 do
                        reaper.TakeFX_SetOffline(orig_take, fx, false)
                        reaper.ShowConsoleMsg("    Set take FX " .. fx .. " ONLINE on original take.\n")
                    end
                    -- Copy take FX from original to new take (which is now last)
                    local processed_take = reaper.GetMediaItemTake(item, num_takes_after-1)
                    if processed_take then
                        -- Delete any FX on the processed take first
                        for fx = reaper.TakeFX_GetCount(processed_take)-1, 0, -1 do
                            reaper.TakeFX_Delete(processed_take, fx)
                            reaper.ShowConsoleMsg("      Deleted FX " .. fx .. " on processed take.\n")
                        end
                        for fx = 0, fx_count-1 do
                            local ok = reaper.TakeFX_CopyToTake(orig_take, fx, processed_take, -1, false)
                            reaper.ShowConsoleMsg("      Copied FX " .. fx .. " from original to processed take: " .. tostring(ok) .. "\n")
                        end
                    else
                        reaper.ShowConsoleMsg("    Couldn't get processed (new) take!\n")
                    end
                else
                    reaper.ShowConsoleMsg("  WARNING: No new take created.\n")
                end
            else
                reaper.ShowConsoleMsg("Item " .. i .. ": No active take.\n")
            end
        else
            reaper.ShowConsoleMsg("No item at index " .. i .. ".\n")
        end
    end

    reaper.Undo_EndBlock("Offline take FX, render, restore, copy take FX (multi-item)", -1)
    reaper.ShowConsoleMsg("Done.\n")
end

function loop()
    reaper.ImGui_SetNextWindowSize(ctx, 430, 120, reaper.ImGui_Cond_FirstUseEver())
    local visible, open = reaper.ImGui_Begin(ctx, 'Audiosuite MVP', true, reaper.ImGui_WindowFlags_AlwaysAutoResize())

    if visible then
        local tr, num_items = get_selected_track_and_items()
        local tr_name = get_track_name(tr)
        reaper.ImGui_Text(ctx, "Track: " .. tr_name .. "   |   Selected Items: " .. tostring(num_items))

        reaper.ImGui_SetCursorPosX(ctx, 10)
        local fx_enabled = (tr ~= nil)
        if not fx_enabled then
            reaper.ImGui_BeginDisabled(ctx)
        end
        if reaper.ImGui_Button(ctx, "Open FX Browser", 170, 40) and fx_enabled then
            reaper.TrackFX_AddByName(tr, "", false, -1000)
        end
        if not fx_enabled then
            reaper.ImGui_EndDisabled(ctx)
            reaper.ImGui_SameLine(ctx, nil, 8)
            reaper.ImGui_Text(ctx, "← Select an item to enable FX browser")
        end

        reaper.ImGui_SameLine(ctx, 0)
        reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Button(), 0xFF0000FF)
        if reaper.ImGui_Button(ctx, "Render", 170, 40) then
            core_render()
        end
        reaper.ImGui_PopStyleColor(ctx)
    end

    reaper.ImGui_End(ctx) -- <- always called, outside `if visible`
    if open then
        reaper.defer(loop)
    else
        reaper.ImGui_DestroyContext(ctx)
    end
end

reaper.defer(loop)
