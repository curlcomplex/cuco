--[[
@description CUCO Keyframer — snapshot and recall FX parameter states with envelope writing
@author      felixtatic
@version     0.7.0
@provides    ../_shared/cuco_imgui_theme.lua > cuco_imgui_theme.lua
@about
  Capture FX parameter states across selected tracks (or take FX on items),
  recall them safely with envelope bypass, and write them as automation
  envelope points — at the cursor, or across a time selection.

  Per-parameter checkboxes scope what gets recalled/written. Recall is a
  two-stage preview: first click overrides envelopes and applies the
  snapshot, second click cancels. Selection changes auto-cancel.

  Snapshots persist per-project (saved into the .rpp via project ExtState),
  so they survive REAPER restarts.

@dependencies ReaImGui
@license      MIT
@changelog
  0.7.0
    - Add envelope shape picker (per-shape icons) for time-selection writes.
    - Adopt shared CUCO theme module (palette + button helpers).
    - ReaPack distribution: script-relative dofile resolver, bundled theme
      via @provides.
  0.6.0
    - Initial public preview.
]]--

local SCRIPT_VERSION = "0.7.0"
local EXT_SECTION    = "CUCO_Keyframe"
local EXT_KEY        = "snapshots"

-------------------------------------
-- State & Settings
-------------------------------------
local snapshots   = {}
local activeSnap  = 0
local writeMode   = 1       -- 1: cursor, 2: time selection
local writeShape  = 0       -- 0=Linear 1=Square 2=Slow 3=FastStart 4=FastEnd 5=Bezier
local writeTension = 0.0    -- only used by Bezier (-1..1)
local targetMode  = 1       -- 1: Track FX, 2: Take FX
local replaceMode = true
local recall_respects_checks = true

local recall_staged = false
local in_edit_mode  = false

-- Transient status line shown under the action buttons; auto-clears after a few seconds.
local status_msg   = ""
local status_until = 0
local function setStatus(msg, duration)
  status_msg   = msg or ""
  status_until = reaper.time_precise() + (duration or 3.0)
end

-- Inline-edit state for the keyframe-list row name
local editing_idx          = nil   -- index of snapshot currently being renamed inline
local editing_just_started = false -- one-frame flag to grab keyboard focus

-------------------------------------
-- Helpers: Names & GUIDs
-------------------------------------
local function GetTrackName(tr)
  local _, name = reaper.GetTrackName(tr, "")
  local idx = reaper.GetMediaTrackInfo_Value(tr, "IP_TRACKNUMBER")
  return string.format("Track %d: %s", idx or 0, name ~= "" and name or "(unnamed)")
end

local function GetTakeLabel(take, item)
  local name = reaper.GetTakeName(take)
  if not name or name == "" then
    if item then
      local _, itemchunk = reaper.GetSetMediaItemInfo_String(item, "P_NAME", "", false)
      name = itemchunk ~= "" and itemchunk or "(unnamed)"
    else
      name = "(unnamed)"
    end
  end
  return name
end

local function StripGUIDfromFXName(name)
  return name:gsub("^%b{}", ""):gsub("^%s+", "")
end

local function GetSourceGUID(source)
  if reaper.ValidatePtr(source, "MediaItem*") then
    return select(2, reaper.GetSetMediaItemInfo_String(source, "GUID", "", false))
  else
    return select(2, reaper.GetSetMediaTrackInfo_String(source, "GUID", "", false))
  end
end

-------------------------------------
-- Persistence: serialize / deserialize / GUID resolution
-------------------------------------
-- Lua source serializer. Skips userdata/functions (e.g. raw REAPER pointers),
-- which is what lets us strip MediaTrack* / MediaItem_Take* fields safely.
local function serialize(v)
  local t = type(v)
  if t == "nil"     then return "nil" end
  if t == "boolean" then return tostring(v) end
  if t == "number"  then return string.format("%.17g", v) end
  if t == "string"  then return string.format("%q", v) end
  if t == "table" then
    local parts = {}
    for k, val in pairs(v) do
      local sval = serialize(val)
      if sval ~= "nil" then -- skip pointer fields entirely
        local key
        if type(k) == "number" then
          key = "[" .. k .. "]"
        elseif type(k) == "string" then
          key = "[" .. string.format("%q", k) .. "]"
        else
          key = nil -- skip unsupported key types
        end
        if key then parts[#parts + 1] = key .. "=" .. sval end
      end
    end
    return "{" .. table.concat(parts, ",") .. "}"
  end
  return "nil"
end

local function deserialize(s)
  if not s or s == "" then return nil end
  local fn = load("return " .. s, "snapshots", "t", {}) -- empty env: no globals
  if not fn then return nil end
  local ok, result = pcall(fn)
  return ok and result or nil
end

local function findTrackByGUID(guid)
  for i = 0, reaper.CountTracks(0) - 1 do
    local tr = reaper.GetTrack(0, i)
    if tr then
      local _, g = reaper.GetSetMediaTrackInfo_String(tr, "GUID", "", false)
      if g == guid then return tr end
    end
  end
  return nil
end

local function findItemByGUID(guid)
  for i = 0, reaper.CountMediaItems(0) - 1 do
    local it = reaper.GetMediaItem(0, i)
    if it then
      local _, g = reaper.GetSetMediaItemInfo_String(it, "GUID", "", false)
      if g == guid then return it end
    end
  end
  return nil
end

-- Strip pointer fields from a snapshot list so it can be serialized.
local function snapshotsToSerializable(snaps)
  local out = {}
  for i, snap in ipairs(snaps) do
    local data_clean = {}
    for id, d in pairs(snap.data) do
      data_clean[id] = { type = d.type, fx = d.fx } -- drop source/item
    end
    out[i] = {
      name    = snap.name,
      time    = snap.time,
      type    = snap.type,
      data    = data_clean,
      checked = snap.checked,
    }
  end
  return out
end

-- Walk loaded snapshot data and re-bind GUIDs to live track/take pointers.
-- Drops entries whose tracks/items no longer exist in this project.
local function rehydrateSnapshots(loaded)
  local out = {}
  for i, snap in ipairs(loaded) do
    local data = {}
    for id, d in pairs(snap.data or {}) do
      if d.type == "track" then
        local tr = findTrackByGUID(id)
        if tr then data[id] = { type = "track", source = tr, fx = d.fx } end
      elseif d.type == "take" then
        local it = findItemByGUID(id)
        local take = it and reaper.GetActiveTake(it) or nil
        if it and take then
          data[id] = { type = "take", source = take, item = it, fx = d.fx }
        end
      end
    end
    out[i] = {
      name    = snap.name or "(unnamed)",
      time    = snap.time or 0,
      type    = snap.type or "track",
      data    = data,
      checked = snap.checked or {},
    }
  end
  return out
end

local function saveSnapshots()
  local s = serialize(snapshotsToSerializable(snapshots))
  reaper.SetProjExtState(0, EXT_SECTION, EXT_KEY, s)
end

local function loadSnapshots()
  local _, s = reaper.GetProjExtState(0, EXT_SECTION, EXT_KEY)
  if not s or s == "" then return end
  local loaded = deserialize(s)
  if type(loaded) == "table" then
    snapshots = rehydrateSnapshots(loaded)
    activeSnap = math.min(activeSnap, #snapshots)
  end
end

-------------------------------------
-- Helpers: Clone tables
-------------------------------------
local function cloneChecked(src)
  local dst = {}
  for id,data in pairs(src) do
    dst[id] = { fx={} }
    for fxIdx,params in pairs(data.fx) do
      dst[id].fx[fxIdx] = {}
      for pIdx,_ in pairs(params) do
        dst[id].fx[fxIdx][pIdx] = true
      end
    end
  end
  return dst
end

-------------------------------------
-- Normalized param getters/setters
-------------------------------------
local function capParam(data, fx, p)
  if data.type == "track" then
    return reaper.TrackFX_GetParamNormalized(data.source, fx, p)
  else
    return reaper.TakeFX_GetParamNormalized(data.source, fx, p)
  end
end

local function setParam(data, fx, p, val)
  if data.type == "track" then
    reaper.TrackFX_SetParamNormalized(data.source, fx, p, val)
  else
    reaper.TakeFX_SetParamNormalized(data.source, fx, p, val)
  end
end

-------------------------------------
-- Build capture set (selected tracks/takes)
-------------------------------------
local function buildHeld()
  local held = {}
  if targetMode == 1 then
    for i=0, reaper.CountSelectedTracks(0)-1 do
      local tr = reaper.GetSelectedTrack(0, i)
      if reaper.ValidatePtr(tr, "MediaTrack*") then
        local id = GetSourceGUID(tr)
        held[id] = { type="track", source=tr, fx={} }
        local fxCount = reaper.TrackFX_GetCount(tr)
        for fx=0, fxCount-1 do
          held[id].fx[fx] = {}
          local pCount = reaper.TrackFX_GetNumParams(tr, fx)
          for p=0, pCount-1 do
            held[id].fx[fx][p] = capParam(held[id], fx, p)
          end
        end
      end
    end
  else
    for i=0, reaper.CountSelectedMediaItems(0)-1 do
      local item = reaper.GetSelectedMediaItem(0, i)
      local take = item and reaper.GetActiveTake(item) or nil
      if take and reaper.ValidatePtr(take, "MediaItem_Take*") then
        local id = GetSourceGUID(item)
        held[id] = { type="take", source=take, item=item, fx={} }
        local fxCount = reaper.TakeFX_GetCount(take)
        for fx=0, fxCount-1 do
          held[id].fx[fx] = {}
          local pCount = reaper.TakeFX_GetNumParams(take, fx)
          for p=0, pCount-1 do
            held[id].fx[fx][p] = capParam(held[id], fx, p)
          end
        end
      end
    end
  end
  return held
end

-------------------------------------
-- Envelopes
-------------------------------------
local function EnsureEnvelope(data, fxIdx, pIdx)
  local env
  if data.type == "track" then
    if reaper.ValidatePtr(data.source, "MediaTrack*") then
      env = reaper.GetFXEnvelope(data.source, fxIdx, pIdx, true)
    end
  else
    if reaper.ValidatePtr(data.source, "MediaItem_Take*") then
      env = reaper.TakeFX_GetEnvelope(data.source, fxIdx, pIdx, true)
    end
  end
  if env then
    local _, chunk = reaper.GetEnvelopeStateChunk(env, "", false)
    chunk = chunk:gsub("VIS %d","VIS 1"):gsub("ARM %d","ARM 1")
    reaper.SetEnvelopeStateChunk(env, chunk, false)
  end
  return env
end

local function DeleteRange(env, s, e) reaper.DeleteEnvelopePointRange(env, s, e) end
local function DeletePoint(env, t)    reaper.DeleteEnvelopePointRange(env, t-1e-6, t+1e-6) end

-- Envelope scaling fix: values are stored normalized 0..1, convert to env mode when writing.
-- shape: REAPER envelope point shape (0..5). tension: only meaningful for Bezier (5).
local function WritePoint(env, t, norm_v, shape, tension)
  local mode = reaper.GetEnvelopeScalingMode(env) or 0
  local v = reaper.ScaleToEnvelopeMode(mode, norm_v or 0.0)
  reaper.InsertEnvelopePointEx(env, -1, t, v, shape or 0, tension or 0.0, false, true)
end

-------------------------------------
-- Snapshots
-------------------------------------
local function HoldSnapshot()
  local cur = reaper.GetCursorPosition()
  local held = buildHeld()
  if not next(held) then return end
  local snapType = (targetMode == 1) and "track" or "take"
  local names = {}
  for _, data in pairs(held) do
    if snapType == "track" then
      table.insert(names, select(2, reaper.GetTrackName(data.source, "")))
    else
      table.insert(names, GetTakeLabel(data.source, data.item))
    end
  end
  local namePrefix = "Multiple Tracks"
  if snapType == "track" and #names == 1 then namePrefix = names[1] end
  if snapType == "take" then
    namePrefix = #names == 1 and (names[1] ~= "" and names[1] or "(unnamed)") or "Multiple Takes"
  end
  local n = 1
  for _, snap in ipairs(snapshots) do
    if snap.type == snapType then n = n + 1 end
  end
  local name = string.format("%s Keyframe %d @ %.3f", namePrefix, n, cur)
  snapshots[#snapshots+1] = {
    name    = name,
    time    = cur,
    data    = held,
    checked = cloneChecked(held),
    type    = snapType
  }
  activeSnap = #snapshots
  saveSnapshots()
end

local function DeleteSnapshot()
  if activeSnap > 0 then
    table.remove(snapshots, activeSnap)
    activeSnap = math.min(activeSnap, #snapshots)
    saveSnapshots()
  end
end

local function OverwriteSnapshot()
  if activeSnap < 1 or not snapshots[activeSnap] then return end
  local held = buildHeld()
  if not next(held) then return end
  local snap = snapshots[activeSnap]
  snap.data = held
  snap.checked = cloneChecked(held)
  saveSnapshots()
end

-- Drop entries from the active snapshot that point at tracks, items, FX, or
-- params that no longer exist. Setting keys to nil during pairs() is safe in
-- Lua so long as we don't add new keys, which we don't.
local function PruneSnapshot()
  if activeSnap < 1 or not snapshots[activeSnap] then return 0 end
  local snap = snapshots[activeSnap]
  local removed = 0

  for id, data in pairs(snap.data) do
    local srcOk = (data.type == "track" and reaper.ValidatePtr(data.source, "MediaTrack*"))
               or (data.type == "take"  and reaper.ValidatePtr(data.source, "MediaItem_Take*"))
    if not srcOk then
      snap.data[id] = nil
      if snap.checked then snap.checked[id] = nil end
      removed = removed + 1
    else
      local fxCount = (data.type == 'track') and reaper.TrackFX_GetCount(data.source)
                                              or reaper.TakeFX_GetCount(data.source)
      for fxIdx, params in pairs(data.fx) do
        if fxIdx >= fxCount then
          data.fx[fxIdx] = nil
          if snap.checked[id] and snap.checked[id].fx then
            snap.checked[id].fx[fxIdx] = nil
          end
          removed = removed + 1
        else
          local maxP = (data.type == 'track')
            and reaper.TrackFX_GetNumParams(data.source, fxIdx)
            or  reaper.TakeFX_GetNumParams(data.source, fxIdx)
          for pIdx in pairs(params) do
            if pIdx >= maxP then
              params[pIdx] = nil
              if snap.checked[id] and snap.checked[id].fx and snap.checked[id].fx[fxIdx] then
                snap.checked[id].fx[fxIdx][pIdx] = nil
              end
              removed = removed + 1
            end
          end
        end
      end
    end
  end

  if removed > 0 then saveSnapshots() end
  return removed
end

-------------------------------------
-- Edit Mode
-------------------------------------
local function SetEditMode(on)
  if on then
    reaper.Main_OnCommand(40885, 0) -- Bypass all envelopes (ON)
  else
    reaper.Main_OnCommand(40876, 0) -- No automation override (OFF)
  end
  in_edit_mode = on
end

-------------------------------------
-- Recall
-------------------------------------
local function RecallSnapshot(snap)
  if not snap then return end

  if not recall_staged then
    if not in_edit_mode then SetEditMode(true) end
    reaper.Undo_BeginBlock2(0)

    for id, data in pairs(snap.data) do
      if (data.type == "track" and reaper.ValidatePtr(data.source, "MediaTrack*"))
      or (data.type == "take"  and reaper.ValidatePtr(data.source, "MediaItem_Take*")) then
        for fxIdx, params in pairs(data.fx) do
          local maxP = (data.type=='track') and reaper.TrackFX_GetNumParams(data.source, fxIdx)
                                          or  reaper.TakeFX_GetNumParams (data.source, fxIdx)
          if maxP and maxP > 0 then
            for pIdx, val in pairs(params) do
              if pIdx < maxP then
                if (not recall_respects_checks) or (snap.checked and snap.checked[id] and snap.checked[id].fx[fxIdx] and snap.checked[id].fx[fxIdx][pIdx]) then
                  setParam(data, fxIdx, pIdx, val)
                end
              end
            end
          end
        end
      end
    end

    reaper.Undo_EndBlock2(0, "CUCO Keyframe: Recall '" .. (snap.name or "?") .. "'", -1)
    recall_staged = true
  else
    SetEditMode(false)
    recall_staged = false
  end
end

-------------------------------------
-- Write
-------------------------------------
local function WriteAutomation()
  if activeSnap < 1 or not snapshots[activeSnap] then return end
  local snap = snapshots[activeSnap]
  SetEditMode(false)
  recall_staged = false

  local t0,t1 = reaper.GetSet_LoopTimeRange(false, false, 0, 0, false)
  local cur   = reaper.GetCursorPosition()
  local times = (writeMode==1) and {cur} or ((t1>t0) and {t0,t1} or {cur})

  reaper.Undo_BeginBlock2(0)

  for id,data in pairs(snap.data) do
    if ((snap.type == "track" and data.type == "track") or (snap.type == "take" and data.type == "take"))
    and ((data.type == "track" and reaper.ValidatePtr(data.source, "MediaTrack*"))
      or (data.type == "take"  and reaper.ValidatePtr(data.source, "MediaItem_Take*"))) then
      for fxIdx,params in pairs(data.fx) do
        local maxP = (data.type=='track') and reaper.TrackFX_GetNumParams(data.source, fxIdx)
                                          or  reaper.TakeFX_GetNumParams (data.source, fxIdx)
        for pIdx,val in pairs(params) do
          if maxP and pIdx < maxP
             and snap.checked[id] and snap.checked[id].fx[fxIdx]
             and snap.checked[id].fx[fxIdx][pIdx] then
            local env = EnsureEnvelope(data, fxIdx, pIdx)
            if env then
              if writeMode==2 and replaceMode then DeleteRange(env, t0, t1) end
              for _, tm in ipairs(times) do
                local wt = tm
                if data.type=="take" then
                  local item = data.item or (reaper.ValidatePtr(data.source, "MediaItem_Take*") and reaper.GetMediaItemTake_Item(data.source))
                  local pos  = item and reaper.GetMediaItemInfo_Value(item, "D_POSITION") or 0
                  wt = tm - pos
                end
                if writeMode==1 and replaceMode then DeletePoint(env, wt) end
                WritePoint(env, wt, val, writeShape, writeTension)
              end
              reaper.Envelope_SortPoints(env)
            end
          end
        end
      end
    end
  end

  reaper.Undo_EndBlock2(0, "CUCO Keyframe: Write '"..(snap.name or "?").."'", -1)
end

-------------------------------------
-- Selection-change auto-cancel
-------------------------------------
local prevSelHash = ""
local function selHash()
  local ids = {}
  if targetMode == 1 then
    for i=0, reaper.CountSelectedTracks(0)-1 do
      local tr = reaper.GetSelectedTrack(0,i)
      if tr then ids[#ids+1] = select(2, reaper.GetSetMediaTrackInfo_String(tr, "GUID", "", false)) end
    end
  else
    for i=0, reaper.CountSelectedMediaItems(0)-1 do
      local it = reaper.GetSelectedMediaItem(0,i)
      if it then ids[#ids+1] = select(2, reaper.GetSetMediaItemInfo_String(it, "GUID", "", false)) end
    end
  end
  table.sort(ids)
  return table.concat(ids, "|")
end

-------------------------------------
-- UI
-------------------------------------
local ctx = reaper.ImGui_CreateContext('CUCO Keyframe')

-- Shared CUCO theme module: palette + apply/revert + button helpers + segmented + tooltip.
-- Resolver tries same-dir first (ReaPack install: theme bundled via @provides rename),
-- then falls back to ../_shared/ (dev mode: running from repo).
local theme = (function()
  local s = debug.getinfo(1, "S").source:sub(2)
  local dir = s:match("(.*[/\\])") or ""
  local ok, mod = pcall(dofile, dir .. "cuco_imgui_theme.lua")
  if ok then return mod end
  return dofile(dir .. "../_shared/cuco_imgui_theme.lua")
end)()
local COL       = theme.COL
local pushBtn   = theme.pushBtn
local popBtn    = theme.popBtn
local segmented = theme.segmented
local tooltip   = theme.tooltip

-- Sample a normalized 0..1 progression for each REAPER envelope shape across t∈[0,1].
-- These are *visual* approximations for the picker icons, not the actual REAPER curves
-- (which are renderer-internal). Close enough that each shape is recognizable.
local SHAPE_NAMES = { [0]="Linear", [1]="Square", [2]="Slow start/end",
                      [3]="Fast start", [4]="Fast end", [5]="Bezier" }
local SHAPE_ORDER = { 0, 1, 2, 3, 4, 5 }

local function shape_y(shape, t)
  if     shape == 0 then return t                                     -- Linear
  elseif shape == 1 then return (t < 1) and 0 or 1                    -- Square (step at end)
  elseif shape == 2 then return t * t * (3 - 2 * t)                   -- Slow start/end (smoothstep)
  elseif shape == 3 then return t * t                                 -- Fast start (ease-in)
  elseif shape == 4 then return 1 - (1 - t) * (1 - t)                 -- Fast end (ease-out)
  elseif shape == 5 then return 0.5 - 0.5 * math.cos(t * math.pi)     -- Bezier (gentle s)
  end
  return t
end

-- Draw a small shape thumbnail and return whether it was clicked.
-- Renders into an InvisibleButton's bounds so it gets hover/click behavior for free.
local function shapePickerCell(ctx, shape, selected, w, h)
  reaper.ImGui_PushID(ctx, "sp" .. shape)
  local x, y = reaper.ImGui_GetCursorScreenPos(ctx)
  local clicked = reaper.ImGui_InvisibleButton(ctx, "##cell", w, h)
  local hovered = reaper.ImGui_IsItemHovered(ctx)

  local dl = reaper.ImGui_GetWindowDrawList(ctx)
  -- Cell background
  local bg     = selected and COL.toggle_on or (hovered and COL.toggle_hi or COL.toggle_off)
  reaper.ImGui_DrawList_AddRectFilled(dl, x, y, x + w, y + h, bg, 4)
  -- Inset for the curve
  local pad_x, pad_y = 5, 4
  local x0, y0 = x + pad_x, y + h - pad_y
  local x1, y1 = x + w - pad_x, y + pad_y
  -- Curve color (lighter when selected)
  local curve = selected and 0xFFFFFFFF or 0xC8C8D0FF
  -- Sample N segments and stroke
  local N = 24
  local px, py = x0, y0
  for i = 1, N do
    local t  = i / N
    local sy = shape_y(shape, t)
    local nx = x0 + (x1 - x0) * t
    local ny = y0 + (y1 - y0) * sy
    reaper.ImGui_DrawList_AddLine(dl, px, py, nx, ny, curve, 1.5)
    px, py = nx, ny
  end
  -- Endpoint dots
  reaper.ImGui_DrawList_AddCircleFilled(dl, x0, y0, 1.8, curve)
  reaper.ImGui_DrawList_AddCircleFilled(dl, x1, y1, 1.8, curve)
  reaper.ImGui_PopID(ctx)
  return clicked
end

local function ButtonCol(ctx, mode, cur, colA, colB)
  if mode == cur then
    reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Button(), colA)
  else
    reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Button(), colB)
  end
end

local function loop()
  -- Fixed width, flexible height. Constraints apply every frame so resize
  -- handles can only stretch vertically.
  local FIXED_W = 600
  reaper.ImGui_SetNextWindowSizeConstraints(ctx, FIXED_W, 280, FIXED_W, 1e6)
  reaper.ImGui_SetNextWindowSize(ctx, FIXED_W, 520, reaper.ImGui_Cond_FirstUseEver())

  -- Theme applies to the window itself (incl. title bar), so push BEFORE Begin.
  local theme_token = theme.apply(ctx)

  -- ReaImGui contract (NOT same as Dear ImGui upstream): End() must be called
  -- ONLY when Begin returned visible=true. `open` is the close-button state;
  -- when the user clicks X, `open` becomes false and we stop the defer loop.
  local visible, open = reaper.ImGui_Begin(ctx, 'CUCO Keyframe ' .. SCRIPT_VERSION, true)

  if visible then
    -- Auto-cancel if user changed selection mid-stage
    local h = selHash()
    if h ~= prevSelHash then
      prevSelHash = h
      if recall_staged or in_edit_mode then
        SetEditMode(false)
        recall_staged = false
      end
    end

    -- ─────────────────────────────────────────────────────────────
    -- Filter snapshots by current target type
    -- ─────────────────────────────────────────────────────────────
    local filtered = {}
    local n = 0
    for i, s in ipairs(snapshots) do
      if (targetMode == 1 and s.type == "track") or (targetMode == 2 and s.type == "take") then
        n = n + 1
        table.insert(filtered, { i = i, s = s, n = n })
      end
    end
    local has_any = (#snapshots > 0)
    local has_filtered = (#filtered > 0)
    local has_active = (activeSnap > 0 and snapshots[activeSnap] ~= nil)

    -- ─────────────────────────────────────────────────────────────
    -- Snapshot list — fills available height above the footer
    -- ─────────────────────────────────────────────────────────────
    -- Reserve footer space: status (cond) + toggles + shape + actions + separator + paddings.
    -- The footer is ALWAYS at the bottom — list_pane absorbs height changes, not the footer.
    local frame_h   = reaper.ImGui_GetFrameHeightWithSpacing(ctx)
    local has_status = status_msg ~= "" and reaper.time_precise() < status_until
    local footer_h  = frame_h * (has_status and 4 or 3) + 28

    -- No border on the list child — the rounded ChildBg surface + footer separator
    -- already give enough visual structure. Doubling them up looks heavy.
    if reaper.ImGui_BeginChild(ctx, "list_pane", 0, -footer_h, 0) then

    if not has_filtered then
      reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Text(), COL.faint)
      reaper.ImGui_Dummy(ctx, 0, 12)
      local msg = has_any and "No snapshots for this target type." or "No keyframes yet — capture one below."
      local tw = reaper.ImGui_CalcTextSize(ctx, msg)
      local cw = reaper.ImGui_GetContentRegionAvail(ctx)
      reaper.ImGui_SetCursorPosX(ctx, math.max(0, (cw - tw) * 0.5))
      reaper.ImGui_Text(ctx, msg)
      reaper.ImGui_PopStyleColor(ctx)
    else
      local sel_flags = reaper.ImGui_SelectableFlags_AllowDoubleClick()
      local set_overlap = reaper.ImGui_SetNextItemAllowOverlap

      reaper.ImGui_PushStyleVar(ctx, reaper.ImGui_StyleVar_ItemSpacing(), 4, 6)

      for _, rec in ipairs(filtered) do
        local i, s, num = rec.i, rec.s, rec.n
        local is_active = (i == activeSnap)

        reaper.ImGui_PushID(ctx, i)

        -- Active row: subtle full-row tint + bright accent stripe on the left edge.
        if is_active then
          local cx, cy = reaper.ImGui_GetCursorScreenPos(ctx)
          local cw     = reaper.ImGui_GetContentRegionAvail(ctx)
          local rh     = reaper.ImGui_GetFrameHeight(ctx) + 6
          local dl     = reaper.ImGui_GetWindowDrawList(ctx)
          reaper.ImGui_DrawList_AddRectFilled(dl, cx - 2, cy - 2, cx + cw, cy + rh, COL.active_row, 5)
          -- 3px vertical stripe in the toggle accent color
          reaper.ImGui_DrawList_AddRectFilled(dl, cx - 8, cy - 2, cx - 5, cy + rh, COL.toggle_on, 1)
        end

        if editing_idx == i then
          if editing_just_started then
            reaper.ImGui_SetKeyboardFocusHere(ctx)
            editing_just_started = false
          end
          reaper.ImGui_SetNextItemWidth(ctx, -120)
          local _, nm = reaper.ImGui_InputText(ctx, "##edit", s.name or "",
            reaper.ImGui_InputTextFlags_EnterReturnsTrue() | reaper.ImGui_InputTextFlags_AutoSelectAll())
          if reaper.ImGui_IsItemDeactivated(ctx) then
            if reaper.ImGui_IsItemDeactivatedAfterEdit(ctx) then
              s.name = nm
              saveSnapshots()
            end
            editing_idx = nil
          end
        else
          -- Number badge (muted, monospace-feel via fixed format)
          reaper.ImGui_TextColored(ctx, COL.muted, string.format("%2d", num))
          reaper.ImGui_SameLine(ctx, 0, 12)

          -- Selectable spans the rest of the row width minus the action strip.
          if set_overlap then set_overlap(ctx) end
          local name = (s.name ~= "" and s.name) or "(unnamed)"
          local row_w = reaper.ImGui_GetContentRegionAvail(ctx) - 165 -- room for action buttons
          if reaper.ImGui_Selectable(ctx, name, is_active, sel_flags, row_w, 0) then
            if activeSnap ~= i then recall_staged = false end
            activeSnap = i
            if reaper.ImGui_IsMouseDoubleClicked(ctx, 0) then
              editing_idx = i
              editing_just_started = true
            end
          end
        end

        -- Right-aligned action strip (Recall · Overwrite · Delete)
        reaper.ImGui_SameLine(ctx)
        local cw = reaper.ImGui_GetContentRegionAvail(ctx)
        reaper.ImGui_SetCursorPosX(ctx, reaper.ImGui_GetCursorPosX(ctx) + cw - 155)

        if reaper.ImGui_SmallButton(ctx, "Recall") then
          if activeSnap ~= i then recall_staged = false end
          activeSnap = i
          RecallSnapshot(s)
        end
        tooltip(ctx, "Preview the snapshot's values; click again to cancel")

        reaper.ImGui_SameLine(ctx)
        if reaper.ImGui_SmallButton(ctx, "Overwrite") then
          activeSnap = i
          OverwriteSnapshot()
          setStatus(string.format("Overwrote '%s'", name or "?"))
        end
        tooltip(ctx, "Replace this snapshot with the current FX state")

        reaper.ImGui_SameLine(ctx)
        pushBtn(ctx, COL.danger, COL.danger_hi)
        if reaper.ImGui_SmallButton(ctx, "x") then
          activeSnap = i
          DeleteSnapshot()
          popBtn(ctx)
          reaper.ImGui_PopID(ctx)
          break -- indices shifted; rebuild next frame
        end
        popBtn(ctx)
        tooltip(ctx, "Delete snapshot")

        reaper.ImGui_PopID(ctx)
      end

      reaper.ImGui_PopStyleVar(ctx)
    end

      -- Captured params lives inside the scroll pane so the footer stays put.
      -- Re-resolve `s` here: an in-frame Delete may have invalidated the cached has_active.
      local active_snap = (activeSnap > 0) and snapshots[activeSnap] or nil
      if active_snap then
        reaper.ImGui_Dummy(ctx, 0, 4)
        if reaper.ImGui_CollapsingHeader(ctx, "Captured params") then
          local s = active_snap
          for id, data in pairs(s.data) do
            if (targetMode == 1 and data.type == "track") or (targetMode == 2 and data.type == "take") then
              local lbl = (data.type == "track") and GetTrackName(data.source) or GetTakeLabel(data.source, data.item)
              if reaper.ImGui_TreeNode(ctx, lbl .. "##" .. id) then
                local fxCount = (data.type == 'track') and reaper.TrackFX_GetCount(data.source)
                                                       or  reaper.TakeFX_GetCount(data.source)
                for fxIdx, params in pairs(data.fx) do
                  local fxExists = fxIdx < fxCount
                  local fxName
                  if fxExists then
                    fxName = (data.type == 'track')
                      and select(2, reaper.TrackFX_GetFXName(data.source, fxIdx, ""))
                      or  select(2, reaper.TakeFX_GetFXName(data.source, fxIdx, ""))
                    fxName = StripGUIDfromFXName(fxName)
                    if fxName == "" then fxName = "FX " .. fxIdx end
                  else
                    fxName = string.format("FX %d (removed)", fxIdx)
                  end
                  if reaper.ImGui_TreeNode(ctx, fxName .. "##fx" .. fxIdx) then
                    local maxP = fxExists and ((data.type == 'track')
                      and reaper.TrackFX_GetNumParams(data.source, fxIdx)
                      or  reaper.TakeFX_GetNumParams(data.source, fxIdx)) or 0
                    for pIdx, val in pairs(params) do
                      local pExists = pIdx < maxP
                      local pName
                      if pExists then
                        pName = (data.type == 'track')
                          and select(2, reaper.TrackFX_GetParamName(data.source, fxIdx, pIdx, ""))
                          or  select(2, reaper.TakeFX_GetParamName(data.source, fxIdx, pIdx, ""))
                        if pName == "" then pName = "Param " .. pIdx end
                      else
                        pName = string.format("Param %d (removed)", pIdx)
                      end
                      local key  = id .. '.' .. fxIdx .. '.' .. pIdx
                      local flag = s.checked[id].fx[fxIdx][pIdx]
                      local ch3, nf = reaper.ImGui_Checkbox(ctx, "##" .. key, flag)
                      if ch3 then s.checked[id].fx[fxIdx][pIdx] = nf; saveSnapshots() end
                      reaper.ImGui_SameLine(ctx)
                      reaper.ImGui_Text(ctx, string.format('%s: %.3f', pName, val))
                    end
                    reaper.ImGui_TreePop(ctx)
                  end
                end
                reaper.ImGui_TreePop(ctx)
              end
            end
          end
        end
      end

      reaper.ImGui_EndChild(ctx)
    end -- BeginChild list_pane

    -- ─────────────────────────────────────────────────────────────
    -- Footer — status + toggles + actions, fixed at the bottom
    -- ─────────────────────────────────────────────────────────────
    reaper.ImGui_Separator(ctx)

    -- Status line with smooth alpha fade in the last 0.6s
    if has_status then
      local remaining = status_until - reaper.time_precise()
      local alpha = math.min(1.0, remaining / 0.6)
      reaper.ImGui_TextColored(ctx, theme.fade_color(COL.status, alpha), status_msg)
    end

    -- Row 1: stateful toggles
    local edit_label = in_edit_mode and "Edit Mode · ON" or "Edit Mode · off"
    pushBtn(ctx,
      in_edit_mode and COL.warn      or COL.toggle_off,
      in_edit_mode and COL.warn_hi   or COL.toggle_hi)
    if reaper.ImGui_Button(ctx, edit_label, 130, 0) then
      SetEditMode(not in_edit_mode)
      recall_staged = false
    end
    popBtn(ctx)
    tooltip(ctx, "Bypass automation envelopes for live preview & recall")

    reaper.ImGui_SameLine(ctx, 0, 12)
    targetMode = segmented(ctx, "tgt", "Track FX", "Take FX", targetMode, 180)
    tooltip(ctx, "Snapshot scope: track FX or take FX")

    reaper.ImGui_SameLine(ctx, 0, 16)
    local rc, rv = reaper.ImGui_Checkbox(ctx, "Replace existing", replaceMode)
    if rc then replaceMode = rv end
    tooltip(ctx, "When writing, replace overlapping envelope points")

    reaper.ImGui_SameLine(ctx, 0, 12)
    local rcc, rvc = reaper.ImGui_Checkbox(ctx, "Respect ✓", recall_respects_checks)
    if rcc then recall_respects_checks = rvc end
    tooltip(ctx, "Recall only checked params (in the captured params list)")

    -- Row 2: shape picker — six custom-drawn thumbnails for the envelope point shape.
    reaper.ImGui_AlignTextToFramePadding(ctx)
    reaper.ImGui_TextColored(ctx, COL.muted, "Shape")
    reaper.ImGui_SameLine(ctx, 0, 10)
    local CELL_W, CELL_H = 36, 22
    for _, shape in ipairs(SHAPE_ORDER) do
      if shapePickerCell(ctx, shape, writeShape == shape, CELL_W, CELL_H) then
        writeShape = shape
      end
      tooltip(ctx, SHAPE_NAMES[shape])
      reaper.ImGui_SameLine(ctx, 0, 4)
    end
    -- Bezier tension slider — only visible when Bezier is selected.
    if writeShape == 5 then
      reaper.ImGui_SameLine(ctx, 0, 12)
      reaper.ImGui_SetNextItemWidth(ctx, 160)
      local tch, tv = reaper.ImGui_SliderDouble(ctx, "##tension", writeTension, -1.0, 1.0, "tension %.2f")
      if tch then writeTension = tv end
      tooltip(ctx, "Bezier tension: -1 sharp, 0 smooth, +1 sharp the other way")
    else
      reaper.ImGui_NewLine(ctx)
    end

    -- Row 3: actions
    pushBtn(ctx, COL.primary, COL.primary_hi)
    if reaper.ImGui_Button(ctx, "+ Capture", 110, 0) then HoldSnapshot() end
    popBtn(ctx)
    tooltip(ctx, "Capture the current FX state as a new keyframe")

    reaper.ImGui_SameLine(ctx, 0, 8)
    if reaper.ImGui_Button(ctx, "Prune stale", 100, 0) then
      local n = PruneSnapshot()
      setStatus(n > 0 and string.format("Pruned %d stale entr%s", n, n == 1 and "y" or "ies")
                       or "Nothing to prune")
    end
    tooltip(ctx, "Remove references to deleted FX/params from all snapshots")

    reaper.ImGui_SameLine(ctx, 0, 16)
    writeMode = segmented(ctx, "wm", "Cursor", "Selection", writeMode, 160)
    tooltip(ctx, "Write target: at edit cursor, or across the time selection")

    -- Right-aligned big primary Write button
    reaper.ImGui_SameLine(ctx)
    local cw_remaining = reaper.ImGui_GetContentRegionAvail(ctx)
    if cw_remaining > 110 then
      reaper.ImGui_SetCursorPosX(ctx, reaper.ImGui_GetCursorPosX(ctx) + cw_remaining - 110)
    end
    pushBtn(ctx, COL.primary, COL.primary_hi)
    if reaper.ImGui_Button(ctx, "Write ▶", 110, 0) then WriteAutomation() end
    popBtn(ctx)
    tooltip(ctx, "Write the active snapshot's values into automation envelopes")

    reaper.ImGui_End(ctx)
  end -- if visible

  theme.revert(ctx, theme_token)

  if open then reaper.defer(loop) end
end

loadSnapshots()
reaper.defer(loop)
