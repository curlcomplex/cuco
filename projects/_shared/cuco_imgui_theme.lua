-- CUCO shared ReaImGui theme + helpers.
-- Returns a module table with palette, theme push/pop, button color helpers,
-- and a few small utilities that every CUCO GUI uses.
--
-- Usage:
--   local function load_theme()
--     local s = debug.getinfo(1,"S").source:sub(2)
--     local cuco = s:match("(.*/CUCO/)")
--     return dofile(cuco .. "projects/_shared/cuco_imgui_theme.lua")
--   end
--   local theme = load_theme()
--   ...
--   local t = theme.apply(ctx)
--   local visible, open = reaper.ImGui_Begin(ctx, "My Window", true)
--   if visible then ... reaper.ImGui_End(ctx) end
--   theme.revert(ctx, t)

local r = reaper
local M = {}

-- ─────────────────────────────────────────────────────────────────────────
-- Palette — every color carries meaning. Keep this list short.
-- ─────────────────────────────────────────────────────────────────────────
M.COL = {
  -- Semantic action colors
  primary       = 0x2BB35EFF,   -- success / commit (Capture, Write)
  primary_hi    = 0x3FCB72FF,
  warn          = 0xE0A93AFF,   -- live state / slow ops
  warn_hi       = 0xF3BD4DFF,
  toggle_on     = 0x4860C8FF,   -- segmented selection
  toggle_off    = 0x252834FF,
  toggle_hi     = 0x5A72DCFF,
  danger        = 0x7A2C2CFF,   -- destructive
  danger_hi     = 0x9F3A3AFF,
  active_row    = 0x4860C835,   -- selected row tint
  muted         = 0x8A8A92FF,
  faint         = 0x6A6A72FF,
  status        = 0xC8C8D0FF,

  -- Surface tones
  bg_window     = 0x12141AFF,
  bg_child      = 0x191C24FF,
  bg_frame      = 0x232732FF,
  bg_frame_hi   = 0x2D3242FF,
  bg_frame_act  = 0x383E52FF,
  border        = 0x2A2D3A66,
  text          = 0xE6E6EEFF,
  text_dim      = 0x7A7A82FF,
  separator     = 0x2A2D3AAA,
  scroll_bg     = 0x12141AFF,
  scroll_grab   = 0x363D4DFF,
  scroll_hi     = 0x4A5266FF,
  scroll_act    = 0x5A6376FF,
  header        = 0x2A2F3DFF,
  header_hi     = 0x363D4DFF,
  header_act    = 0x404758FF,
  check         = 0x5A72DCFF,
}

-- Family-color palette (used by Random Walk; available for any per-category UI)
M.FAMILY_COLORS = {
  cutoffs      = 0x40A0E0FF,  -- cyan
  mod_amts     = 0x60D070FF,  -- green
  mod_times    = 0xD0A040FF,  -- gold
  drive        = 0xE07040FF,  -- orange-red
  pitch_detail = 0xC080D0FF,  -- light purple
  pitch_jumps  = 0x8050A8FF,  -- dark purple
  blends       = 0xE0C060FF,  -- yellow
  stereo       = 0xE060A0FF,  -- pink
  switches     = 0x808890FF,  -- gray
  walk         = 0x40C070FF,  -- green
  locked       = 0xC03030FF,  -- red
}

-- ─────────────────────────────────────────────────────────────────────────
-- Theme apply / revert. Push order doesn't matter; revert pops the exact
-- count we pushed via the returned token.
-- ─────────────────────────────────────────────────────────────────────────
function M.apply(ctx)
  -- Style vars: 12 entries (each one push/pop).
  r.ImGui_PushStyleVar(ctx, r.ImGui_StyleVar_WindowPadding(),     12, 10)
  r.ImGui_PushStyleVar(ctx, r.ImGui_StyleVar_FramePadding(),      10, 5)
  r.ImGui_PushStyleVar(ctx, r.ImGui_StyleVar_ItemSpacing(),       6,  6)
  r.ImGui_PushStyleVar(ctx, r.ImGui_StyleVar_ItemInnerSpacing(),  6,  4)
  r.ImGui_PushStyleVar(ctx, r.ImGui_StyleVar_WindowRounding(),    8)
  r.ImGui_PushStyleVar(ctx, r.ImGui_StyleVar_FrameRounding(),     5)
  r.ImGui_PushStyleVar(ctx, r.ImGui_StyleVar_GrabRounding(),      4)
  r.ImGui_PushStyleVar(ctx, r.ImGui_StyleVar_ChildRounding(),     6)
  r.ImGui_PushStyleVar(ctx, r.ImGui_StyleVar_ScrollbarRounding(), 6)
  r.ImGui_PushStyleVar(ctx, r.ImGui_StyleVar_ScrollbarSize(),     11)
  r.ImGui_PushStyleVar(ctx, r.ImGui_StyleVar_FrameBorderSize(),   0)
  r.ImGui_PushStyleVar(ctx, r.ImGui_StyleVar_WindowBorderSize(),  0)

  local cols = {
    { r.ImGui_Col_WindowBg(),             M.COL.bg_window  },
    { r.ImGui_Col_ChildBg(),              M.COL.bg_child   },
    { r.ImGui_Col_FrameBg(),              M.COL.bg_frame   },
    { r.ImGui_Col_FrameBgHovered(),       M.COL.bg_frame_hi },
    { r.ImGui_Col_FrameBgActive(),        M.COL.bg_frame_act },
    { r.ImGui_Col_Border(),               M.COL.border     },
    { r.ImGui_Col_Text(),                 M.COL.text       },
    { r.ImGui_Col_TextDisabled(),         M.COL.text_dim   },
    { r.ImGui_Col_Separator(),            M.COL.separator  },
    { r.ImGui_Col_ScrollbarBg(),          M.COL.scroll_bg  },
    { r.ImGui_Col_ScrollbarGrab(),        M.COL.scroll_grab },
    { r.ImGui_Col_ScrollbarGrabHovered(), M.COL.scroll_hi  },
    { r.ImGui_Col_ScrollbarGrabActive(),  M.COL.scroll_act },
    { r.ImGui_Col_Header(),               M.COL.header     },
    { r.ImGui_Col_HeaderHovered(),        M.COL.header_hi  },
    { r.ImGui_Col_HeaderActive(),         M.COL.header_act },
    { r.ImGui_Col_CheckMark(),            M.COL.check      },
    { r.ImGui_Col_TitleBg(),              M.COL.bg_window  },
    { r.ImGui_Col_TitleBgActive(),        M.COL.bg_child   },
    { r.ImGui_Col_TitleBgCollapsed(),     M.COL.bg_window  },
    { r.ImGui_Col_SliderGrab(),           M.COL.toggle_on  },
    { r.ImGui_Col_SliderGrabActive(),     M.COL.toggle_hi  },
  }
  for _, c in ipairs(cols) do r.ImGui_PushStyleColor(ctx, c[1], c[2]) end
  return { n_cols = #cols, n_vars = 12 }
end

function M.revert(ctx, t)
  if not t then return end
  r.ImGui_PopStyleColor(ctx, t.n_cols)
  r.ImGui_PopStyleVar(ctx, t.n_vars)
end

-- ─────────────────────────────────────────────────────────────────────────
-- Button color trio: push base / hover / active (active = hover for simplicity)
-- ─────────────────────────────────────────────────────────────────────────
function M.pushBtn(ctx, base, hover)
  r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Button(),        base)
  r.ImGui_PushStyleColor(ctx, r.ImGui_Col_ButtonHovered(), hover)
  r.ImGui_PushStyleColor(ctx, r.ImGui_Col_ButtonActive(),  hover)
end
function M.popBtn(ctx) r.ImGui_PopStyleColor(ctx, 3) end

-- ─────────────────────────────────────────────────────────────────────────
-- Convenience semantic-button shortcuts.
-- ─────────────────────────────────────────────────────────────────────────
function M.primaryBtn(ctx, label, w, h)
  M.pushBtn(ctx, M.COL.primary, M.COL.primary_hi)
  local clicked = r.ImGui_Button(ctx, label, w or 0, h or 0)
  M.popBtn(ctx)
  return clicked
end
function M.warnBtn(ctx, label, w, h)
  M.pushBtn(ctx, M.COL.warn, M.COL.warn_hi)
  local clicked = r.ImGui_Button(ctx, label, w or 0, h or 0)
  M.popBtn(ctx)
  return clicked
end
function M.dangerBtn(ctx, label, w, h)
  M.pushBtn(ctx, M.COL.danger, M.COL.danger_hi)
  local clicked = r.ImGui_Button(ctx, label, w or 0, h or 0)
  M.popBtn(ctx)
  return clicked
end

-- Two-option segmented control. Returns the (possibly new) selection.
-- `id` must be unique within the frame.
function M.segmented(ctx, id, opt_a, opt_b, current, total_w)
  local seg_w = (total_w or 180) * 0.5
  local a_on = (current == 1)
  M.pushBtn(ctx, a_on and M.COL.toggle_on or M.COL.toggle_off, M.COL.toggle_hi)
  if r.ImGui_Button(ctx, opt_a .. "##" .. id .. "a", seg_w, 0) then current = 1 end
  M.popBtn(ctx)
  r.ImGui_SameLine(ctx, 0, 0)
  local b_on = (current == 2)
  M.pushBtn(ctx, b_on and M.COL.toggle_on or M.COL.toggle_off, M.COL.toggle_hi)
  if r.ImGui_Button(ctx, opt_b .. "##" .. id .. "b", seg_w, 0) then current = 2 end
  M.popBtn(ctx)
  return current
end

-- ─────────────────────────────────────────────────────────────────────────
-- Tooltip — call directly after the widget you want the tip on.
-- ─────────────────────────────────────────────────────────────────────────
function M.tooltip(ctx, text)
  if r.ImGui_IsItemHovered(ctx) then r.ImGui_SetTooltip(ctx, text) end
end

-- ─────────────────────────────────────────────────────────────────────────
-- Color alpha utility — used for fading status text, etc.
-- col: 0xRRGGBBAA, alpha: 0..1 multiplier on the alpha channel.
-- ─────────────────────────────────────────────────────────────────────────
function M.fade_color(col, alpha)
  local rr = (col >> 24) & 0xFF
  local gg = (col >> 16) & 0xFF
  local bb = (col >> 8)  & 0xFF
  local aa = math.floor(((col & 0xFF) * (alpha or 1.0)) + 0.5)
  return (rr << 24) | (gg << 16) | (bb << 8) | aa
end

-- ─────────────────────────────────────────────────────────────────────────
-- Standard window-size helper. Fixed-width, flexible-height with constraints.
-- Call BEFORE r.ImGui_Begin().
-- ─────────────────────────────────────────────────────────────────────────
function M.fixed_width_window(ctx, width, init_h, min_h)
  r.ImGui_SetNextWindowSizeConstraints(ctx, width, min_h or 280, width, 1e6)
  r.ImGui_SetNextWindowSize(ctx, width, init_h or 520, r.ImGui_Cond_FirstUseEver())
end

return M
