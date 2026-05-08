-- @description Audiosuite+ — Per-clip take FX renderer with handles
-- @version 0.6.0
-- @author CUCO
-- @changelog
--   0.6.0  Phase 1 rebuild: take-FX-based render with user-controllable pre/post handles,
--          whole-file mode for audio, project-tail control via RENDER_TAILMS, per-item
--          expand→render→trim flow. Uses 40601 (Render items as new take, take FX only).
--   0.5    Adopt CUCO theme; fix Begin/End polarity; drop obsolete DestroyContext call.

local r = reaper

-- Shared CUCO theme module
local theme = (function()
  local s = debug.getinfo(1, "S").source:sub(2)
  local cuco = s:match("(.*/CUCO/)")
  return dofile(cuco .. "projects/_shared/cuco_imgui_theme.lua")
end)()
local COL = theme.COL

local SETTINGS_FILE = r.GetResourcePath() .. "/Scripts/CUCO Audiosuite+ Settings.lua"

-- Render action: 40601 prints take FX only (no track FX bake).
local RENDER_ACTION = 40601  -- Item: Render items as new take

-- Tail length is REAPER's project-info value, applied automatically by 40361.
-- We save→override→restore around each batch.
local TAIL_PROJINFO = "RENDER_TAILMS"

-- ────────────────────────────────────────────────────────────────────────────
-- State (persisted)
-- ────────────────────────────────────────────────────────────────────────────
local pre_handle_s   = 0.5
local post_handle_s  = 1.0
local whole_file     = false
local tail_ms        = 1000

-- Status (transient, not persisted)
local status_msg     = ""
local status_alpha   = 0.0  -- 0..1 fade

local function set_status(msg)
  status_msg = msg
  status_alpha = 1.0
end

-- ────────────────────────────────────────────────────────────────────────────
-- Settings persistence
-- ────────────────────────────────────────────────────────────────────────────
local function save_settings()
  local f = io.open(SETTINGS_FILE, "w")
  if not f then return end
  f:write("-- CUCO Audiosuite+ settings (auto-generated)\n")
  f:write(string.format("pre_handle_s = %.4f\n", pre_handle_s))
  f:write(string.format("post_handle_s = %.4f\n", post_handle_s))
  f:write(string.format("whole_file = %s\n", tostring(whole_file)))
  f:write(string.format("tail_ms = %d\n", math.floor(tail_ms)))
  f:close()
end

local function load_settings()
  local f = io.open(SETTINGS_FILE, "r")
  if not f then return end
  local content = f:read("*all"); f:close()
  for line in content:gmatch("([^\n]+)") do
    if not line:match("^%-%-") then
      local k, v = line:match("(%w+)%s*=%s*(.+)")
      if k and v then
        if     k == "pre_handle_s"  and tonumber(v) then pre_handle_s  = tonumber(v)
        elseif k == "post_handle_s" and tonumber(v) then post_handle_s = tonumber(v)
        elseif k == "tail_ms"       and tonumber(v) then tail_ms       = tonumber(v)
        elseif k == "whole_file"                    then whole_file    = (v == "true")
        end
      end
    end
  end
end

load_settings()

-- ────────────────────────────────────────────────────────────────────────────
-- Project state save/restore
-- Ripple modes: 40309 set off / 40310 set per-track / 40311 set all
-- Trim content behind: 41117 toggle
-- ────────────────────────────────────────────────────────────────────────────
local function snapshot_project_state()
  return {
    ripple_pertrack = r.GetToggleCommandState(40310),
    ripple_all      = r.GetToggleCommandState(40311),
    trim_behind     = r.GetToggleCommandState(41117),
    tail_ms         = r.GetSetProjectInfo(0, TAIL_PROJINFO, 0, false),
  }
end

local function force_render_safe_state(target_tail_ms)
  -- Ripple OFF
  if r.GetToggleCommandState(40310) == 1 or r.GetToggleCommandState(40311) == 1 then
    r.Main_OnCommand(40309, 0)
  end
  -- Trim-content-behind OFF
  if r.GetToggleCommandState(41117) == 1 then
    r.Main_OnCommand(41117, 0)
  end
  -- Tail
  r.GetSetProjectInfo(0, TAIL_PROJINFO, target_tail_ms, true)
end

local function restore_project_state(snap)
  -- Ripple
  if snap.ripple_pertrack == 1 then
    r.Main_OnCommand(40310, 0)
  elseif snap.ripple_all == 1 then
    r.Main_OnCommand(40311, 0)
  else
    if r.GetToggleCommandState(40310) == 1 or r.GetToggleCommandState(40311) == 1 then
      r.Main_OnCommand(40309, 0)
    end
  end
  -- Trim behind
  if r.GetToggleCommandState(41117) ~= snap.trim_behind then
    r.Main_OnCommand(41117, 0)
  end
  -- Tail
  r.GetSetProjectInfo(0, TAIL_PROJINFO, snap.tail_ms, true)
end

-- ────────────────────────────────────────────────────────────────────────────
-- Per-item render
-- Returns: ok (bool), msg (string)
-- ────────────────────────────────────────────────────────────────────────────
local function process_one_item(item)
  local take = r.GetActiveTake(item)
  if not take then return false, "no active take" end

  local is_midi = r.TakeIsMIDI(take)

  local orig_pos  = r.GetMediaItemInfo_Value(item, "D_POSITION")
  local orig_len  = r.GetMediaItemInfo_Value(item, "D_LENGTH")
  local orig_offs = r.GetMediaItemTakeInfo_Value(take, "D_STARTOFFS")
  local rate      = r.GetMediaItemTakeInfo_Value(take, "D_PLAYRATE")
  if rate <= 0 then rate = 1 end

  -- Decide pre/post in item-time
  local pre_handle, post_handle = pre_handle_s, post_handle_s

  if not is_midi and whole_file then
    local source = r.GetMediaItemTake_Source(take)
    local src_len = r.GetMediaSourceLength(source)  -- audio: seconds
    pre_handle  = orig_offs / rate
    post_handle = (src_len - orig_offs - orig_len * rate) / rate
  end

  -- Clamp to source bounds for audio (MIDI sources have no meaningful bound here)
  if not is_midi then
    local source = r.GetMediaItemTake_Source(take)
    local src_len = r.GetMediaSourceLength(source)
    local pre_room  = orig_offs / rate
    local post_room = (src_len - orig_offs - orig_len * rate) / rate
    if pre_handle  > pre_room  then pre_handle  = pre_room  end
    if post_handle > post_room then post_handle = post_room end
  end

  if pre_handle  < 0 then pre_handle  = 0 end
  if post_handle < 0 then post_handle = 0 end

  -- Don't push position negative
  if orig_pos - pre_handle < 0 then pre_handle = orig_pos end

  local new_pos  = orig_pos - pre_handle
  local new_offs = orig_offs - pre_handle * rate
  local new_len  = pre_handle + orig_len + post_handle

  -- Expand
  r.SetMediaItemTakeInfo_Value(take, "D_STARTOFFS", new_offs)
  r.SetMediaItemInfo_Value(item, "D_POSITION", new_pos)
  r.SetMediaItemInfo_Value(item, "D_LENGTH", new_len)

  -- Isolate selection to this item only (the action operates on selected items)
  r.SelectAllMediaItems(0, false)
  r.SetMediaItemSelected(item, true)

  -- Render
  local takes_before = r.GetMediaItemNumTakes(item)
  r.Main_OnCommand(RENDER_ACTION, 0)
  local takes_after = r.GetMediaItemNumTakes(item)

  if takes_after <= takes_before then
    -- Roll back the expand
    r.SetMediaItemTakeInfo_Value(take, "D_STARTOFFS", orig_offs)
    r.SetMediaItemInfo_Value(item, "D_POSITION", orig_pos)
    r.SetMediaItemInfo_Value(item, "D_LENGTH", orig_len)
    return false, "render produced no new take"
  end

  local new_take = r.GetMediaItemTake(item, takes_after - 1)

  -- Restore the ORIGINAL take's start offset — we changed it during expand
  r.SetMediaItemTakeInfo_Value(take, "D_STARTOFFS", orig_offs)

  -- New take is a freshly rendered file; its playrate is 1.0, so item-seconds
  -- and source-seconds are equivalent. Visible region of the new take should
  -- align with where the original audio was: start at pre_handle into source.
  r.SetMediaItemTakeInfo_Value(new_take, "D_STARTOFFS", pre_handle)

  -- Trim item back to original visible bounds
  r.SetMediaItemInfo_Value(item, "D_POSITION", orig_pos)
  r.SetMediaItemInfo_Value(item, "D_LENGTH", orig_len)

  return true, string.format("pre=%.2fs post=%.2fs", pre_handle, post_handle)
end

-- ────────────────────────────────────────────────────────────────────────────
-- Batch render: iterate selection, restore state on the way out
-- ────────────────────────────────────────────────────────────────────────────
local function run_render()
  local n = r.CountSelectedMediaItems(0)
  if n == 0 then set_status("No items selected.") return end

  -- Capture original selection so we can restore it
  local original_items = {}
  for i = 0, n - 1 do original_items[#original_items + 1] = r.GetSelectedMediaItem(0, i) end

  local snap = snapshot_project_state()
  force_render_safe_state(tail_ms)

  r.Undo_BeginBlock()
  r.PreventUIRefresh(1)

  local ok_count, fail_count = 0, 0
  local last_msg = ""
  for _, item in ipairs(original_items) do
    local ok, msg = process_one_item(item)
    if ok then ok_count = ok_count + 1; last_msg = msg
    else      fail_count = fail_count + 1; last_msg = msg end
  end

  -- Restore selection (the new takes are now active on each item)
  r.SelectAllMediaItems(0, false)
  for _, item in ipairs(original_items) do r.SetMediaItemSelected(item, true) end

  r.PreventUIRefresh(-1)
  restore_project_state(snap)
  r.UpdateArrange()

  r.Undo_EndBlock(string.format("Audiosuite+: rendered %d item(s)", ok_count), -1)

  if fail_count == 0 then
    set_status(string.format("Rendered %d item(s)  •  %s", ok_count, last_msg))
  else
    set_status(string.format("Rendered %d  •  %d failed  •  last: %s", ok_count, fail_count, last_msg))
  end
end

-- ────────────────────────────────────────────────────────────────────────────
-- Selection helpers for the header
-- ────────────────────────────────────────────────────────────────────────────
local function selection_summary()
  local n = r.CountSelectedMediaItems(0)
  if n == 0 then return nil, 0, 0, 0 end
  local audio_ct, midi_ct = 0, 0
  local first_track
  for i = 0, n - 1 do
    local it = r.GetSelectedMediaItem(0, i)
    local tk = r.GetActiveTake(it)
    if tk then
      if r.TakeIsMIDI(tk) then midi_ct = midi_ct + 1 else audio_ct = audio_ct + 1 end
    end
    if i == 0 then first_track = r.GetMediaItem_Track(it) end
  end
  return first_track, n, audio_ct, midi_ct
end

local function track_label(tr)
  if not tr then return "(no selection)" end
  local _, name = r.GetTrackName(tr, "")
  if name == "" then
    return "Track " .. tostring(r.GetMediaTrackInfo_Value(tr, "IP_TRACKNUMBER"))
  end
  return name
end

-- ────────────────────────────────────────────────────────────────────────────
-- GUI
-- ────────────────────────────────────────────────────────────────────────────
local ctx = r.ImGui_CreateContext("Audiosuite+")

local function loop()
  r.ImGui_SetNextWindowSize(ctx, 520, 0, r.ImGui_Cond_FirstUseEver())
  local theme_token = theme.apply(ctx)

  local visible, open = r.ImGui_Begin(ctx, "Audiosuite+", true,
    r.ImGui_WindowFlags_AlwaysAutoResize())

  if visible then
    -- ── Header: track + selection summary
    local tr, n_sel, n_audio, n_midi = selection_summary()
    r.ImGui_TextColored(ctx, COL.muted, "Track")
    r.ImGui_SameLine(ctx, 0, 8)
    r.ImGui_Text(ctx, track_label(tr))
    r.ImGui_SameLine(ctx, 0, 16)
    r.ImGui_TextColored(ctx, COL.muted, "Items")
    r.ImGui_SameLine(ctx, 0, 8)
    r.ImGui_Text(ctx, string.format("%d  (audio %d  •  MIDI %d)", n_sel, n_audio, n_midi))

    r.ImGui_Separator(ctx)

    -- ── Take FX chain shortcut
    local fx_enabled = (n_sel > 0)
    r.ImGui_BeginDisabled(ctx, not fx_enabled)
    if r.ImGui_Button(ctx, "Open Take FX Chain", 200, 28) and fx_enabled then
      r.Main_OnCommand(40638, 0)  -- Item: Show take FX chain
    end
    r.ImGui_EndDisabled(ctx)
    r.ImGui_SameLine(ctx, 0, 8)
    r.ImGui_AlignTextToFramePadding(ctx)
    r.ImGui_TextColored(ctx, COL.faint, "Configure FX on the take, then render below.")

    r.ImGui_Separator(ctx)

    -- ── Handles
    r.ImGui_TextColored(ctx, COL.muted, "Handles  (seconds)")

    local rv
    r.ImGui_BeginDisabled(ctx, whole_file)
    rv, pre_handle_s  = r.ImGui_SliderDouble(ctx, "Pre",  pre_handle_s,  0.0, 30.0, "%.2f s")
    if rv then save_settings() end
    rv, post_handle_s = r.ImGui_SliderDouble(ctx, "Post", post_handle_s, 0.0, 30.0, "%.2f s")
    if rv then save_settings() end
    r.ImGui_EndDisabled(ctx)

    rv, whole_file = r.ImGui_Checkbox(ctx, "Whole file (audio only — uses full source length)", whole_file)
    if rv then save_settings() end

    if n_midi > 0 then
      r.ImGui_TextColored(ctx, COL.faint,
        "MIDI items: handles applied in seconds (musical-units mode planned for later phase).")
    end

    r.ImGui_Separator(ctx)

    -- ── Tail
    r.ImGui_TextColored(ctx, COL.muted, "Tail  (RENDER_TAILMS — extra time captured after the visible region)")
    local tail_s = tail_ms / 1000.0
    rv, tail_s = r.ImGui_SliderDouble(ctx, "Tail", tail_s, 0.0, 10.0, "%.2f s")
    if rv then tail_ms = math.floor(tail_s * 1000); save_settings() end

    r.ImGui_Separator(ctx)

    -- ── Render
    r.ImGui_BeginDisabled(ctx, n_sel == 0)
    theme.pushBtn(ctx, COL.primary, COL.primary_hi)
    if r.ImGui_Button(ctx, "Render ▶", 200, 40) then run_render() end
    theme.popBtn(ctx)
    r.ImGui_EndDisabled(ctx)

    -- ── Status
    if status_alpha > 0.01 and status_msg ~= "" then
      r.ImGui_SameLine(ctx, 0, 16)
      r.ImGui_AlignTextToFramePadding(ctx)
      r.ImGui_TextColored(ctx, theme.fade_color(COL.status, status_alpha), status_msg)
      status_alpha = status_alpha - 0.005  -- ~3s fade at 60fps
    end

    r.ImGui_End(ctx)
  end

  theme.revert(ctx, theme_token)

  if open then r.defer(loop) end
end

r.defer(loop)
