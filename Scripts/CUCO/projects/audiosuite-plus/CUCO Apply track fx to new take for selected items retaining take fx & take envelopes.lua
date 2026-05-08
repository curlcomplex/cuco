-- @description Apply track FX to new take for selected items, retaining take FX & take envelopes
-- @version 0.5
-- @changelog
--   0.5  Adopt CUCO theme; fix Begin/End polarity; drop obsolete DestroyContext call.
-- @about
--   Same logic as CUCO Audiosuite+. Kept under a descriptive filename for action-list discoverability.

local r = reaper

-- Shared CUCO theme module
local theme = (function()
  local s = debug.getinfo(1, "S").source:sub(2)
  local cuco = s:match("(.*/CUCO/)")
  return dofile(cuco .. "projects/_shared/cuco_imgui_theme.lua")
end)()
local COL = theme.COL

local ctx = r.ImGui_CreateContext('Audiosuite MVP')

local function get_selected_track_and_items()
  local num_sel_items = r.CountSelectedMediaItems(0)
  local tr = nil
  if num_sel_items > 0 then
    local first_item = r.GetSelectedMediaItem(0, 0)
    tr = r.GetMediaItem_Track(first_item)
  end
  return tr, num_sel_items
end

local function get_track_name(tr)
  if not tr then return "(none)" end
  local _, name = r.GetTrackName(tr, "")
  if name == "" then
    local tr_idx = r.GetMediaTrackInfo_Value(tr, 'IP_TRACKNUMBER')
    return 'Track ' .. tostring(tr_idx)
  else
    return name
  end
end

local function core_render()
  r.ClearConsole()
  r.Undo_BeginBlock()

  local num_sel_items = r.CountSelectedMediaItems(0)
  r.ShowConsoleMsg("Selected items: " .. num_sel_items .. "\n")
  if num_sel_items == 0 then
    r.ShowConsoleMsg("No items selected.\n")
    r.Undo_EndBlock("Audiosuite MVP: No items", -1)
    return
  end

  local items = {}
  for i = 0, num_sel_items - 1 do
    items[#items + 1] = r.GetSelectedMediaItem(0, i)
  end

  for i, item in ipairs(items) do
    if item then
      local take = r.GetActiveTake(item)
      if take then
        local fx_count = r.TakeFX_GetCount(take)
        r.ShowConsoleMsg("Item " .. i .. ": Active take, FX count: " .. fx_count .. "\n")
        for fx = 0, fx_count - 1 do
          r.TakeFX_SetOffline(take, fx, true)
        end
        r.Main_OnCommand(40289, 0) -- Unselect all items
        r.SetMediaItemSelected(item, true)
        local num_takes_before = r.GetMediaItemNumTakes(item)
        r.Main_OnCommand(40209, 0) -- Item: Apply track FX to items as new take
        local num_takes_after = r.GetMediaItemNumTakes(item)
        if num_takes_after > num_takes_before then
          local orig_take = r.GetMediaItemTake(item, 0)
          for fx = 0, fx_count - 1 do
            r.TakeFX_SetOffline(orig_take, fx, false)
          end
          local processed_take = r.GetMediaItemTake(item, num_takes_after - 1)
          if processed_take then
            for fx = r.TakeFX_GetCount(processed_take) - 1, 0, -1 do
              r.TakeFX_Delete(processed_take, fx)
            end
            for fx = 0, fx_count - 1 do
              r.TakeFX_CopyToTake(orig_take, fx, processed_take, -1, false)
            end
          end
        end
      end
    end
  end

  r.Undo_EndBlock("Offline take FX, render, restore, copy take FX (multi-item)", -1)
  r.ShowConsoleMsg("Done.\n")
end

local function loop()
  r.ImGui_SetNextWindowSize(ctx, 480, 0, r.ImGui_Cond_FirstUseEver())
  local theme_token = theme.apply(ctx)

  local visible, open = r.ImGui_Begin(ctx, 'Audiosuite MVP', true,
    r.ImGui_WindowFlags_AlwaysAutoResize())

  if visible then
    local tr, num_items = get_selected_track_and_items()
    local tr_name = get_track_name(tr)
    r.ImGui_TextColored(ctx, COL.muted, "Track")
    r.ImGui_SameLine(ctx, 0, 8)
    r.ImGui_Text(ctx, tr_name)
    r.ImGui_SameLine(ctx, 0, 16)
    r.ImGui_TextColored(ctx, COL.muted, "Selected items")
    r.ImGui_SameLine(ctx, 0, 8)
    r.ImGui_Text(ctx, tostring(num_items))

    r.ImGui_Separator(ctx)

    local fx_enabled = (tr ~= nil)
    r.ImGui_BeginDisabled(ctx, not fx_enabled)
    if r.ImGui_Button(ctx, "Open FX Browser", 200, 40) and fx_enabled then
      r.TrackFX_AddByName(tr, "", false, -1000)
    end
    r.ImGui_EndDisabled(ctx)
    if not fx_enabled then
      r.ImGui_SameLine(ctx, 0, 8)
      r.ImGui_AlignTextToFramePadding(ctx)
      r.ImGui_TextColored(ctx, COL.faint, "← Select an item to enable")
    else
      r.ImGui_SameLine(ctx, 0, 8)
      theme.pushBtn(ctx, COL.primary, COL.primary_hi)
      if r.ImGui_Button(ctx, "Render ▶", 200, 40) then core_render() end
      theme.popBtn(ctx)
    end

    r.ImGui_End(ctx)
  end

  theme.revert(ctx, theme_token)

  if open then r.defer(loop) end
end

r.defer(loop)
