--[[
ReaScript Name: CUCO Keyframe
Author: curl + ChatGPT
Version: 0.4.11
Description: Raw param keyframes + persistence + stable UI + sticky Recall + markers + auto write dest. Default target Track; hold Cmd/Ctrl for Take (override). Toggle to lock.
Dependencies: ReaImGui (ImGui for Reaper)
]]--

------------------------------------------------------------
-- State / Settings
------------------------------------------------------------
local EXT_NS = "CUCO_Keyframe"
local snapshots   = {}
local activeSnap  = 0

-- Target mode: 1 = Track FX (default), 2 = Take FX
local targetMode  = 1
-- Write destination: AUTO (Selection if present, else Cursor)
-- (No persistent toggle; computed per click, but we persist the last UI state for completeness)
local writeMode   = 0 -- kept for compatibility with persisted UI, not shown

local replaceMode = true
local addMarkersOnWrite = true

local recall_mode   = false -- sticky recall/edit mode
local recall_staged = false
local in_edit_mode  = false
local last_status   = "Ready."

------------------------------------------------------------
-- Utils
------------------------------------------------------------
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
  return (name or ""):gsub("^%b{}", ""):gsub("^%s+", "")
end

local function GetSourceGUID(source)
  if reaper.ValidatePtr(source, "MediaItem*") then
    return select(2, reaper.GetSetMediaItemInfo_String(source, "GUID", "", false))
  else
    return select(2, reaper.GetSetMediaTrackInfo_String(source, "GUID", "", false))
  end
end

-- Pointer-safe UI helpers
local function SafeLabel(data)
  if data.type == "track" then
    if reaper.ValidatePtr(data.source, "MediaTrack*") then
      return GetTrackName(data.source)
    else
      return "[missing track]"
    end
  else
    local ok_item = data.item and reaper.ValidatePtr(data.item, "MediaItem*")
    local ok_take = data.source and reaper.ValidatePtr(data.source, "MediaItem_Take*")
    if ok_item and ok_take then
      return GetTakeLabel(data.source, data.item)
    else
      return "[missing take]"
    end
  end
end

local function SafeFXName(data, fxIdx)
  if data.type == "track" and reaper.ValidatePtr(data.source, "MediaTrack*") then
    return StripGUIDfromFXName(select(2, reaper.TrackFX_GetFXName(data.source, fxIdx, "")) or "")
  elseif data.type == "take" and reaper.ValidatePtr(data.source, "MediaItem_Take*") then
    return StripGUIDfromFXName(select(2, reaper.TakeFX_GetFXName(data.source, fxIdx, "")) or "")
  end
  return "[fx]"
end

local function SafeParamName(data, fxIdx, pIdx)
  if data.type == "track" and reaper.ValidatePtr(data.source, "MediaTrack*") then
    return select(2, reaper.TrackFX_GetParamName(data.source, fxIdx, pIdx, "")) or ("Param "..pIdx)
  elseif data.type == "take" and reaper.ValidatePtr(data.source, "MediaItem_Take*") then
    return select(2, reaper.TakeFX_GetParamName(data.source, fxIdx, pIdx, "")) or ("Param "..pIdx)
  end
  return "Param "..pIdx
end

-- Modifiers (Cmd/Ctrl = Shortcut, Alt = Alt)
local function get_mods(ctx)
  local mods = reaper.ImGui_GetKeyMods(ctx)
  local shortcut = (mods & (reaper.ImGui_Mod_Shortcut and reaper.ImGui_Mod_Shortcut() or reaper.ImGui_Mod_Ctrl())) ~= 0
  local alt      = (mods & reaper.ImGui_Mod_Alt()) ~= 0
  return shortcut, alt
end

-- Effective target for a given click:
-- default = targetMode (Track=1 / Take=2)
-- hold Cmd/Ctrl -> force Take (2)
-- hold Alt      -> force Track (1)
local function effective_target(ctx)
  local shortcut, alt = get_mods(ctx)
  if shortcut then return 2, "Take (override)" end
  if alt      then return 1, "Track (override)" end
  return targetMode, (targetMode==1 and "Track" or "Take")
end

-- Write times: selection if valid, else cursor
local function has_time_selection()
  local t0,t1 = reaper.GetSet_LoopTimeRange(false, false, 0, 0, false)
  return (t1 or 0) > (t0 or 0), t0 or 0, t1 or 0
end

local function compute_write_times()
  local hasTS, t0, t1 = has_time_selection()
  if hasTS and t1>t0 then return {t0,t1}, "Selection" end
  local cur = reaper.GetCursorPosition()
  return {cur}, "Cursor"
end

------------------------------------------------------------
-- Persistence (Lua table serializer)
------------------------------------------------------------
local DATA_VER = 3

local function is_array(t)
  local maxk, count = 0, 0
  for k, _ in pairs(t) do
    if type(k) ~= "number" or k < 1 or k % 1 ~= 0 then return false end
    if k > maxk then maxk = k end
    count = count + 1
  end
  return count == maxk
end

local function esc_str(s)
  return (tostring(s)
    :gsub("\\","\\\\")
    :gsub("\n","\\n")
    :gsub("\r","\\r")
    :gsub("\t","\\t")
    :gsub("\"","\\\""))
end

local function encode_lua(v)
  local tv = type(v)
  if tv == "number" then
    return tostring(v)
  elseif tv == "boolean" then
    return v and "true" or "false"
  elseif tv == "string" then
    return '"' .. esc_str(v) .. '"'
  elseif tv == "table" then
    if is_array(v) then
      local parts = {}
      for i = 1, #v do parts[#parts+1] = encode_lua(v[i]) end
      return "{" .. table.concat(parts, ",") .. "}"
    else
      local parts = {}
      for k, val in pairs(v) do
        local key
        if type(k) == "string" and k:match("^[A-Za-z_][A-Za-z0-9_]*$") then
          key = k
        else
          key = "[" .. encode_lua(k) .. "]"
        end
        parts[#parts+1] = key .. "=" .. encode_lua(val)
      end
      return "{" .. table.concat(parts, ",") .. "}"
    end
  else
    return "nil"
  end
end

local function decode_lua(s)
  if not s or s == "" then return nil end
  local env = {}
  local f = load("return " .. s, "persist", "t", env)
  if not f then return nil end
  local ok, res = pcall(f)
  if ok then return res end
  return nil
end

-- Live -> persistable
local function snapshots_to_persist(snaps)
  local out = {
    __ver = DATA_VER,
    list = {},
    ui = {
      activeSnap = activeSnap,
      targetMode = targetMode,
      replaceMode= replaceMode,
      addMarkers = addMarkersOnWrite
    }
  }
  for _, s in ipairs(snaps) do
    local ps = { name=s.name, time=s.time, type=s.type, data={}, checked={} }
    for id, data in pairs(s.data) do
      local entry = { id=id, type=data.type, item_guid=nil, fx={} }
      if data.type == "take" and data.item and reaper.ValidatePtr(data.item, "MediaItem*") then
        entry.item_guid = select(2, reaper.GetSetMediaItemInfo_String(data.item, "GUID", "", false))
      end
      for fxIdx, params in pairs(data.fx) do
        local parr = {}
        for pIdx, val in pairs(params) do parr[#parr+1] = {p=pIdx, v=val} end
        table.sort(parr, function(a,b) return a.p < b.p end)
        entry.fx[#entry.fx+1] = { fx=fxIdx, params=parr }
      end
      table.sort(entry.fx, function(a,b) return a.fx < b.fx end)
      ps.data[#ps.data+1] = entry
    end
    for id, chk in pairs(s.checked or {}) do
      local cfx = {}
      for fxIdx, params in pairs(chk.fx or {}) do
        local parr = {}
        for pIdx, flag in pairs(params) do if flag then parr[#parr+1] = pIdx end end
        table.sort(parr)
        cfx[#cfx+1] = { fx=fxIdx, params=parr }
      end
      table.sort(cfx, function(a,b) return a.fx < b.fx end)
      ps.checked[#ps.checked+1] = { id=id, fx=cfx }
    end
    out.list[#out.list+1] = ps
  end
  return out
end

-- Persist -> live
local function persist_to_snapshots(p)
  local list = {}
  if not p or type(p) ~= "table" or type(p.list) ~= "table" then return list end

  local trackByGUID = {}
  for i=0, reaper.CountTracks(0)-1 do
    local tr = reaper.GetTrack(0,i)
    local guid = select(2, reaper.GetSetMediaTrackInfo_String(tr, "GUID", "", false))
    trackByGUID[guid] = tr
  end
  local itemByGUID = {}
  for i=0, reaper.CountMediaItems(0)-1 do
    local it = reaper.GetMediaItem(0,i)
    local guid = select(2, reaper.GetSetMediaItemInfo_String(it, "GUID", "", false))
    itemByGUID[guid] = it
  end

  for _, ps in ipairs(p.list) do
    local s = { name=ps.name, time=ps.time, type=ps.type, data = {}, checked = {} }

    for _, entry in ipairs(ps.data or {}) do
      local id = entry.id
      if entry.type == "track" then
        local tr = trackByGUID[id]
        if tr then
          local rec = { type="track", source=tr, fx={} }
          for _, fxrec in ipairs(entry.fx or {}) do
            local fx = fxrec.fx
            rec.fx[fx] = rec.fx[fx] or {}
            for _, pp in ipairs(fxrec.params or {}) do
              rec.fx[fx][pp.p] = pp.v
            end
          end
          s.data[id] = rec
        end
      else
        local item = itemByGUID[entry.item_guid or ""]
        local take = item and reaper.GetActiveTake(item) or nil
        if take then
          local rec = { type="take", source=take, item=item, fx={} }
          for _, fxrec in ipairs(entry.fx or {}) do
            local fx = fxrec.fx
            rec.fx[fx] = rec.fx[fx] or {}
            for _, pp in ipairs(fxrec.params or {}) do
              rec.fx[fx][pp.p] = pp.v
            end
          end
          s.data[id] = rec
        end
      end
    end

    for _, c in ipairs(ps.checked or {}) do
      local id = c.id
      s.checked[id] = s.checked[id] or {fx={}}
      for _, fxset in ipairs(c.fx or {}) do
        local fx = fxset.fx
        s.checked[id].fx[fx] = s.checked[id].fx[fx] or {}
        for _, pIdx in ipairs(fxset.params or {}) do
          s.checked[id].fx[fx][pIdx] = true
        end
      end
    end

    list[#list+1] = s
  end

  if p.ui then
    activeSnap        = tonumber(p.ui.activeSnap or 0) or 0
    targetMode        = tonumber(p.ui.targetMode or 1) or 1
    replaceMode       = not (p.ui.replaceMode == false)
    addMarkersOnWrite = not (p.ui.addMarkers == false)
  end

  return list
end

local function save_state()
  local blob = snapshots_to_persist(snapshots)
  local s = encode_lua(blob)
  reaper.SetProjExtState(0, EXT_NS, "state", s or "")
end

local function load_state()
  local ok, s = reaper.GetProjExtState(0, EXT_NS, "state")
  if ok == 0 or not s or s == "" then return end
  local tbl = decode_lua(s)
  local rec = persist_to_snapshots(tbl)
  if #rec > 0 then
    snapshots = rec
    if activeSnap < 1 then activeSnap = 1 end
    if activeSnap > #snapshots then activeSnap = #snapshots end
  end
end

------------------------------------------------------------
-- Clone helpers
------------------------------------------------------------
local function cloneHeld(src)
  local dst = {}
  for id,data in pairs(src) do
    local copy = { type=data.type, source=data.source, item=data.item, fx={} }
    for fxIdx,params in pairs(data.fx) do
      copy.fx[fxIdx] = {}
      for pIdx,val in pairs(params) do
        copy.fx[fxIdx][pIdx] = val
      end
    end
    dst[id] = copy
  end
  return dst
end

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

------------------------------------------------------------
-- Build capture set (RAW values)
------------------------------------------------------------
local function buildHeld(target)
  local held = {}
  if target == 1 then -- Track
    for i=0, reaper.CountSelectedTracks(0)-1 do
      local tr = reaper.GetSelectedTrack(0, i)
      if reaper.ValidatePtr(tr, "MediaTrack*") then
        local id = GetSourceGUID(tr)
        held[id] = { type="track", source=tr, fx={} }
        for fx=0, reaper.TrackFX_GetCount(tr)-1 do
          held[id].fx[fx] = {}
          for p=0, reaper.TrackFX_GetNumParams(tr,fx)-1 do
            held[id].fx[fx][p] = reaper.TrackFX_GetParam(tr,fx,p)
          end
        end
      end
    end
  else -- Take
    for i=0, reaper.CountSelectedMediaItems(0)-1 do
      local item = reaper.GetSelectedMediaItem(0, i)
      local take = item and reaper.GetActiveTake(item) or nil
      if take and reaper.ValidatePtr(take, "MediaItem_Take*") then
        local id = GetSourceGUID(item)
        held[id] = { type="take", source=take, item=item, fx={} }
        for fx=0, reaper.TakeFX_GetCount(take)-1 do
          held[id].fx[fx] = {}
          for p=0, reaper.TakeFX_GetNumParams(take,fx)-1 do
            held[id].fx[fx][p] = reaper.TakeFX_GetParam(take,fx,p)
          end
        end
      end
    end
  end
  return held
end

------------------------------------------------------------
-- Envelopes (hidden/unarmed)
------------------------------------------------------------
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
    local ok, chunk = reaper.GetEnvelopeStateChunk(env, "", false)
    if ok and chunk then
      chunk = chunk:gsub("VIS %d", "VIS 0"):gsub("ARM %d", "ARM 0")
      reaper.SetEnvelopeStateChunk(env, chunk, false)
    end
  end
  return env
end

local function DeleteRange(env, s, e) reaper.DeleteEnvelopePointRange(env, s, e) end
local function DeletePoint(env, t)    reaper.DeleteEnvelopePointRange(env, t-1e-6, t+1e-6) end
local function WritePoint(env, t, v)  reaper.InsertEnvelopePoint(env, t, v, 0, 0, false, false) end

------------------------------------------------------------
-- Snapshot actions
------------------------------------------------------------
local function HoldSnapshot(ctx)
  local tgt,_ = effective_target(ctx)
  local held = buildHeld(tgt)
  if not next(held) then last_status = "Nothing selected for "..(tgt==1 and "Track" or "Take").." FX."; return end

  local cur = reaper.GetCursorPosition()
  local snapType = (tgt == 1) and "track" or "take"
  local names = {}
  for _, data in pairs(held) do
    if snapType == "track" then
      table.insert(names, select(2, reaper.GetTrackName(data.source, "")))
    else
      table.insert(names, GetTakeLabel(data.source, data.item))
    end
  end
  local namePrefix = (snapType == "track") and (#names==1 and names[1] or "Multiple Tracks")
                    or (#names==1 and (names[1] ~= "" and names[1] or "(unnamed)") or "Multiple Takes")
  local n = 1
  for _, snap in ipairs(snapshots) do if snap.type == snapType then n = n + 1 end end
  local name = string.format("%s Keyframe %d @ %.3f", namePrefix, n, cur)

  snapshots[#snapshots+1] = {
    name    = name,
    time    = cur,
    data    = held,
    checked = cloneChecked(held),
    type    = snapType
  }
  activeSnap = #snapshots
  save_state()
  last_status = "Captured: "..name

  if recall_mode then
    local s = snapshots[activeSnap]
    if s then
      for _, d in pairs(s.data) do
        if s.type == "track" and d.type == "track" and reaper.ValidatePtr(d.source, "MediaTrack*") then
          for fxIdx,params in pairs(d.fx) do for pIdx,val in pairs(params) do reaper.TrackFX_SetParam(d.source, fxIdx, pIdx, val) end end
        elseif s.type == "take" and d.type == "take" and reaper.ValidatePtr(d.source, "MediaItem_Take*") then
          for fxIdx,params in pairs(d.fx) do for pIdx,val in pairs(params) do reaper.TakeFX_SetParam(d.source, fxIdx, pIdx, val) end end
        end
      end
    end
  end
end

local function DeleteSnapshot()
  if activeSnap > 0 then
    local removed = snapshots[activeSnap].name or "(unnamed)"
    table.remove(snapshots, activeSnap)
    activeSnap = math.min(activeSnap, #snapshots)
    save_state()
    last_status = "Deleted: "..removed
  end
end

local function OverwriteSnapshot(ctx)
  if activeSnap < 1 or not snapshots[activeSnap] then last_status = "No active snapshot."; return end
  local tgt,_ = effective_target(ctx)
  local held = buildHeld(tgt)
  if not next(held) then last_status = "Nothing selected to overwrite for "..(tgt==1 and "Track" or "Take").." FX."; return end
  local snap = snapshots[activeSnap]
  snap.data = held
  snap.checked = cloneChecked(held)
  save_state()
  last_status = "Overwrote: "..(snap.name or "(unnamed)")
end

local function SetRecallMode(on)
  if on then
    reaper.Main_OnCommand(40885, 0) -- Bypass all envelopes (ON)
  else
    reaper.Main_OnCommand(40876, 0) -- No automation override (OFF)
  end
  in_edit_mode = on
  recall_mode  = on
  recall_staged= on
  if on and snapshots[activeSnap] then
    local s = snapshots[activeSnap]
    for _, d in pairs(s.data) do
      if s.type == "track" and d.type == "track" and reaper.ValidatePtr(d.source, "MediaTrack*") then
        for fxIdx,params in pairs(d.fx) do for pIdx,val in pairs(params) do reaper.TrackFX_SetParam(d.source, fxIdx, pIdx, val) end end
      elseif s.type == "take" and d.type == "take" and reaper.ValidatePtr(d.source, "MediaItem_Take*") then
        for fxIdx,params in pairs(d.fx) do for pIdx,val in pairs(params) do reaper.TakeFX_SetParam(d.source, fxIdx, pIdx, val) end end
      end
    end
  end
end

local function ApplySnapshotIfRecallMode()
  if not recall_mode then return end
  local s = snapshots[activeSnap]
  if not s then return end
  for _, d in pairs(s.data) do
    if s.type == "track" and d.type == "track" and reaper.ValidatePtr(d.source, "MediaTrack*") then
      for fxIdx,params in pairs(d.fx) do for pIdx,val in pairs(params) do reaper.TrackFX_SetParam(d.source, fxIdx, pIdx, val) end end
    elseif s.type == "take" and d.type == "take" and reaper.ValidatePtr(d.source, "MediaItem_Take*") then
      for fxIdx,params in pairs(d.fx) do for pIdx,val in pairs(params) do reaper.TakeFX_SetParam(d.source, fxIdx, pIdx, val) end end
    end
  end
  last_status = "Applied: "..(s.name or "(unnamed)").." (Recall Mode)"
end

local function WriteAutomation(ctx)
  if activeSnap < 1 or not snapshots[activeSnap] then last_status = "No active snapshot to write."; return end
  local snap = snapshots[activeSnap]
  if recall_mode then SetRecallMode(false) end

  local times, modeLabel = compute_write_times()
  local envCount, ptCount, skippedMissing = 0, 0, 0

  for _,data in pairs(snap.data) do
    local valid = (data.type=="track" and reaper.ValidatePtr(data.source, "MediaTrack*"))
               or (data.type=="take"  and reaper.ValidatePtr(data.source, "MediaItem_Take*"))
    if not valid then
      skippedMissing = skippedMissing + 1
    else
      for fxIdx,params in pairs(data.fx) do
        for pIdx,val in pairs(params) do
          local id = GetSourceGUID(data.type=="track" and (data.source) or (data.item or data.source))
          if id and snap.checked and snap.checked[id] and snap.checked[id].fx[fxIdx] and snap.checked[id].fx[fxIdx][pIdx] then
            local env = EnsureEnvelope(data, fxIdx, pIdx)
            if env then
              envCount = envCount + 1
              if modeLabel == "Selection" and replaceMode then
                local t0, t1 = times[1], times[2]
                DeleteRange(env, t0, t1)
              end
              for _, tm in ipairs(times) do
                local wt = tm
                if data.type=="take" then
                  local item = data.item or (reaper.ValidatePtr(data.source, "MediaItem_Take*") and reaper.GetMediaItemTake_Item(data.source))
                  local pos  = item and reaper.GetMediaItemInfo_Value(item, "D_POSITION") or 0
                  wt = tm - pos
                end
                if modeLabel == "Cursor" and replaceMode then DeletePoint(env, wt) end
                WritePoint(env, wt, val)
                ptCount = ptCount + 1
              end
            end
          end
        end
      end
    end
  end

  if addMarkersOnWrite then
    for _, tm in ipairs(times) do
      local name = "KF: "..(snap.name or "(unnamed)")
      reaper.AddProjectMarker2(0, false, tm, 0, name, -1, 0)
    end
  end

  save_state()
  reaper.Undo_OnStateChange("CUCO Keyframe: wrote '"..(snap.name or "?").."'")
  last_status = string.format("Wrote %d pts on %d envs (%s) | Skipped %d sources",
                              ptCount, envCount, modeLabel, skippedMissing)
end

------------------------------------------------------------
-- UI (ImGui) with pcall guard
------------------------------------------------------------
local ctx = reaper.ImGui_CreateContext('CUCO Keyframe')
load_state()

local function ButtonCol(ctx, active, colA, colB)
  reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Button(), active and colA or colB)
end

local function loop()
  reaper.ImGui_SetNextWindowSize(ctx, 580, 700, reaper.ImGui_Cond_FirstUseEver())
  local visible, isOpen = reaper.ImGui_Begin(ctx, 'CUCO Keyframe 0.4.11', true)
  if not visible or (isOpen == false) then
    save_state()
    reaper.ImGui_End(ctx)
    return
  end

  local ok_ui = pcall(function()
    -- Target selector with live override preview
    local effTarget, effLabel = effective_target(ctx)
    local tint = (effTarget==2) and 0x9B59B6FF or 0x3B82F6FF -- Take=purple, Track=blue
    ButtonCol(ctx, true, tint, 0x303030FF)
    local baseLabel = (targetMode==1 and "Track" or "Take")
    local btnLabel  = (effLabel ~= baseLabel) and (effLabel .. " ▶") or baseLabel
    if reaper.ImGui_Button(ctx, btnLabel, 120, 0) then
      -- toggle to lock
      targetMode = (targetMode==1) and 2 or 1
      save_state()
    end
    reaper.ImGui_PopStyleColor(ctx)
    reaper.ImGui_SameLine(ctx)
    reaper.ImGui_Text(ctx, "(hold Cmd/Ctrl for Take; Alt for Track)")

    -- Replace + Markers toggles
    reaper.ImGui_SameLine(ctx)
    local ch, val = reaper.ImGui_Checkbox(ctx, 'Replace', replaceMode)
    if ch then replaceMode = val save_state() end
    reaper.ImGui_SameLine(ctx)
    local chm, valm = reaper.ImGui_Checkbox(ctx, 'Markers', addMarkersOnWrite)
    if chm then addMarkersOnWrite = valm save_state() end

    reaper.ImGui_Separator(ctx)

    -- Actions
    if reaper.ImGui_Button(ctx, 'Capture Keyframe', 150, 0) then HoldSnapshot(ctx) end
    reaper.ImGui_SameLine(ctx)
    if reaper.ImGui_Button(ctx, 'Overwrite', 100, 0) then OverwriteSnapshot(ctx) end
    reaper.ImGui_SameLine(ctx)
    if reaper.ImGui_Button(ctx, 'Delete', 100, 0) then DeleteSnapshot() end

    -- Right-aligned: Recall Mode + Write (with dynamic context)
    local ww = reaper.ImGui_GetWindowWidth(ctx)
    reaper.ImGui_SetCursorPosX(ctx, ww - 260)
    reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Button(), recall_mode and 0xFFD050FF or 0x555555FF)
    if reaper.ImGui_Button(ctx, recall_mode and "Recall Mode: ON" or "Recall Mode: OFF", 150, 0) then
      SetRecallMode(not recall_mode)
      last_status = recall_mode and "Recall Mode enabled" or "Recall Mode disabled"
    end
    reaper.ImGui_PopStyleColor(ctx)

    reaper.ImGui_SameLine(ctx)
    local _, whereLabel = compute_write_times()
    local writeText = string.format("Write (%s • %s)", (effTarget==1 and "Track" or "Take"), whereLabel)
    reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Button(), tint)
    if reaper.ImGui_Button(ctx, writeText, 150, 0) then WriteAutomation(ctx) end
    reaper.ImGui_PopStyleColor(ctx)

    reaper.ImGui_Separator(ctx)

    -- Filtered snapshot list (by locked base targetMode only, as before)
    local filtered = {}
    local n = 0
    for i,s in ipairs(snapshots) do
      if (targetMode == 1 and s.type == "track") or (targetMode == 2 and s.type == "take") then
        n = n + 1
        table.insert(filtered, {i=i, s=s, n=n})
      end
    end

    for _, rec in ipairs(filtered) do
      local i, s, num = rec.i, rec.s, rec.n
      local sel = (i==activeSnap)
      if reaper.ImGui_Selectable(ctx, string.format("%d: %s", num, s.name or "(unnamed)"), sel) then
        local changed = (activeSnap ~= i)
        activeSnap = i
        save_state()
        if changed and recall_mode then
          ApplySnapshotIfRecallMode()
        end
      end
    end

    reaper.ImGui_Separator(ctx)

    -- Active snapshot details
    if activeSnap>0 and snapshots[activeSnap] then
      local s = snapshots[activeSnap]
      reaper.ImGui_Text(ctx, 'Name:')
      local ch2, nm = reaper.ImGui_InputText(ctx, '##name', s.name or "", 256)
      if ch2 then s.name = nm save_state() end
      reaper.ImGui_SameLine(ctx)
      reaper.ImGui_Text(ctx, string.format('@ %.3f', s.time or 0))
    end

    reaper.ImGui_Separator(ctx)

    -- Tree with param checkboxes (pointer-safe)
    if activeSnap>0 and snapshots[activeSnap] then
      local s = snapshots[activeSnap]
      for id,data in pairs(s.data) do
        if (targetMode == 1 and data.type == "track") or (targetMode == 2 and data.type == "take") then
          local label = SafeLabel(data)
          if reaper.ImGui_TreeNode(ctx, label) then
            for fxIdx,params in pairs(data.fx) do
              local fxLabel = SafeFXName(data, fxIdx)
              if reaper.ImGui_TreeNode(ctx, fxLabel) then
                for pIdx,val in pairs(params) do
                  local pName = SafeParamName(data, fxIdx, pIdx)
                  local key  = (id or "?")..'.'..fxIdx..'.'..pIdx
                  local flag = s.checked[id] and s.checked[id].fx[fxIdx] and s.checked[id].fx[fxIdx][pIdx]
                  local ch3, nf = reaper.ImGui_Checkbox(ctx, key, flag and true or false)
                  if ch3 then
                    s.checked[id] = s.checked[id] or {fx={}}
                    s.checked[id].fx[fxIdx] = s.checked[id].fx[fxIdx] or {}
                    s.checked[id].fx[fxIdx][pIdx] = nf
                    save_state()
                  end
                  reaper.ImGui_SameLine(ctx)
                  reaper.ImGui_Text(ctx, string.format("%s = %.3f", pName, val or 0))
                end
                reaper.ImGui_TreePop(ctx)
              end
            end
            reaper.ImGui_TreePop(ctx)
          end
        end
      end
    else
      reaper.ImGui_Text(ctx, '(No snapshots yet)')
    end

    reaper.ImGui_Separator(ctx)
    reaper.ImGui_Text(ctx, last_status or "")
  end) -- pcall

  reaper.ImGui_End(ctx)
  reaper.defer(loop)
end

reaper.defer(loop)
