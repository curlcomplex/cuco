--[[
ReaScript Name: CUCO Keyframe
Author: ChatGPT / curl-enhanced
Version: 0.4.3
Description: Keyframe FX automation to tracks/takes. Focused UI, grouping, fixed toggles, live automode, multi-track, clean logic.
Dependencies: ReaImGui (ImGui for Reaper)
]]

local SCRIPT_NAME = "CUCO Keyframe"

---------------------------------------------------
-- GLOBAL STATE & UTILS
---------------------------------------------------
local keyframes   = {}   -- array of { name, time, data=held, checked=checked }
local activeKey   = 0
local writeMode   = 1    -- 1 = cursor, 2 = sel start/end
local targetMode  = 1    -- 1 = track FX, 2 = take FX
local replaceMode = true -- true = replace existing, false = add new
local autoOpen    = {}   -- keyframes to open on creation

---------------------------------------------------
-- Automation Mode Toggle
---------------------------------------------------
local function get_track_automode()
  local tr = reaper.GetSelectedTrack(0,0)
  if not tr then return -1 end
  return math.floor(reaper.GetMediaTrackInfo_Value(tr,"I_AUTOMODE") or 0)
end

local function automode_label_and_color(mode)
  -- 0=Trim/Read, 1=Read, 4=Latch, 5=Latch Preview
  if mode==0 or mode==1 then return "Trim/Read", 0x22DD44FF
  elseif mode==5 then return "Latch Preview", 0xFF44B4FF
  else return "Other", 0xAAAAAAFF end
end

local function set_automode(mode)
  for i=0,reaper.CountSelectedTracks(0)-1 do
    local tr = reaper.GetSelectedTrack(0,i)
    reaper.SetMediaTrackInfo_Value(tr,"I_AUTOMODE",mode)
  end
end

---------------------------------------------------
-- UTILS
---------------------------------------------------
local function GetSourceGUID(source)
  if reaper.ValidatePtr(source, "MediaItem*") then
    return select(2, reaper.GetSetMediaItemInfo_String(source, "GUID", "", false))
  else
    return select(2, reaper.GetSetMediaTrackInfo_String(source, "GUID", "", false))
  end
end

local function GetSourceName(data)
  if data.type == "track" then
    local _, name = reaper.GetTrackName(data.source, "")
    return name or "?"
  else
    local item = reaper.GetMediaItemTake_Item(data.source)
    local name = reaper.GetTakeName(data.source)
    return name or ("Item "..tostring(item))
  end
end

local function cloneHeld(src)
  local dst = {}
  for id,data in pairs(src) do
    local copy = { type=data.type, source=data.source, fx={} }
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

local function buildHeld()
  local held = {}
  if targetMode == 1 then
    -- Track FX
    for i=0, reaper.CountSelectedTracks(0)-1 do
      local tr = reaper.GetSelectedTrack(0, i)
      local id = GetSourceGUID(tr)
      held[id] = { type="track", source=tr, fx={} }
      for fx=0, reaper.TrackFX_GetCount(tr)-1 do
        held[id].fx[fx] = {}
        for p=0, reaper.TrackFX_GetNumParams(tr,fx)-1 do
          held[id].fx[fx][p] = reaper.TrackFX_GetParam(tr,fx,p)
        end
      end
    end
  else
    -- Take FX
    for i=0, reaper.CountSelectedMediaItems(0)-1 do
      local item = reaper.GetSelectedMediaItem(0, i)
      local take = reaper.GetActiveTake(item)
      if take then
        local id = GetSourceGUID(item)
        held[id] = { type="take", source=take, fx={} }
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

local function EnsureEnvelope(data, fxIdx, pIdx)
  local env = (data.type=="track")
    and reaper.GetFXEnvelope(data.source, fxIdx, pIdx, true)
    or reaper.TakeFX_GetEnvelope(data.source, fxIdx, pIdx, true)
  if env then
    local _, chunk = reaper.GetEnvelopeStateChunk(env, "", false)
    chunk = chunk:gsub("VIS %d","VIS 1"):gsub("ARM %d","ARM 1")
    reaper.SetEnvelopeStateChunk(env, chunk, false)
  end
  return env
end

local function DeleteRange(env, s, e) reaper.DeleteEnvelopePointRange(env, s, e) end
local function DeletePoint(env, t)    reaper.DeleteEnvelopePointRange(env, t-1e-6, t+1e-6) end
local function WritePoint(env, t, v)  reaper.InsertEnvelopePoint(env, t, v, 0, 0, false, false) end

---------------------------------------------------
-- CAPTURE / WRITE / DELETE
---------------------------------------------------
local function CaptureKeyframe()
  local cur = reaper.GetCursorPosition()
  local held = buildHeld()
  if not next(held) then return end

  -- Always name: [type] [name] @ [time]
  local mainId, mainData = next(held)
  local typeTxt = mainData and mainData.type or "?"
  local nameTxt = mainData and GetSourceName(mainData) or "?"
  local kfname = string.format("[%s] %s @ %.2fs", typeTxt, nameTxt, cur)

  keyframes[#keyframes+1] = {
    name    = kfname,
    time    = cur,
    data    = held,
    checked = cloneChecked(held),
  }
  activeKey = #keyframes
  autoOpen[activeKey] = true
end

local function DeleteKeyframe(idx)
  table.remove(keyframes, idx)
  if activeKey > #keyframes then activeKey = #keyframes end
end

local function WriteAutomation()
  if activeKey < 1 or not keyframes[activeKey] then return end
  local key = keyframes[activeKey]
  local t0,t1 = reaper.GetSet_LoopTimeRange(false, false, 0, 0, false)
  local cur   = reaper.GetCursorPosition()
  local times = (writeMode==1) and {cur} or ((t1>t0) and {t0,t1} or {cur})

  for id,data in pairs(key.data) do
    for fxIdx,params in pairs(data.fx) do
      for pIdx,val in pairs(params) do
        if key.checked[id].fx[fxIdx][pIdx] then
          local env = EnsureEnvelope(data, fxIdx, pIdx)
          if env then
            if writeMode==2 and replaceMode then DeleteRange(env, t0, t1) end
            for _, tm in ipairs(times) do
              local wt = tm
              if data.type=="take" then
                local item = reaper.GetMediaItemTake_Item(data.source)
                local pos  = reaper.GetMediaItemInfo_Value(item, "D_POSITION")
                wt = tm - pos
              end
              if writeMode==1 and replaceMode then DeletePoint(env, wt) end
              WritePoint(env, wt, val)
            end
          end
        end
      end
    end
  end

  -- On write, reset all affected tracks to Trim/Read (0)
  for id,data in pairs(key.data) do
    if data.type=="track" and reaper.ValidatePtr(data.source,"MediaTrack*") then
      reaper.SetMediaTrackInfo_Value(data.source,"I_AUTOMODE",0)
    end
  end

  reaper.Undo_OnStateChange(SCRIPT_NAME..": wrote '"..key.name.."'")
end

---------------------------------------------------
-- INFO TEXT
---------------------------------------------------
local function GetCaptureInfo()
  if targetMode == 1 then
    local n = reaper.CountSelectedTracks(0)
    if n==0 then return "No tracks selected"
    elseif n==1 then return "Capture Track Keyframe"
    else return "Capture Multi Track Keyframe" end
  else
    local n = reaper.CountSelectedMediaItems(0)
    if n==0 then return "No items selected"
    elseif n==1 then return "Capture Take FX Keyframe"
    else return "Capture Multi Take Keyframe" end
  end
end

---------------------------------------------------
-- GUI (ReaImGui)
---------------------------------------------------
local ctx = reaper.ImGui_CreateContext(SCRIPT_NAME)
local function loop()
  reaper.ImGui_SetNextWindowSize(ctx, 590, 750, reaper.ImGui_Cond_FirstUseEver())
  local visible = reaper.ImGui_Begin(ctx, SCRIPT_NAME.." v0.4.3", true)
  if not visible then
    reaper.ImGui_End(ctx)
    reaper.ImGui_DestroyContext(ctx)
    return
  end

  local winW = reaper.ImGui_GetWindowWidth(ctx)
  local pad, btnW = 16, 36

  -- === TOP BAR ===
  -- Target FX toggle (Track/Take)
  reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Button(), targetMode==1 and 0x0CC2F0FF or 0xF02C77FF)
  if reaper.ImGui_Button(ctx, targetMode==1 and "Track FX" or "Take FX", 70) then
    targetMode = (targetMode==1) and 2 or 1
  end
  reaper.ImGui_PopStyleColor(ctx)
  reaper.ImGui_SameLine(ctx, nil, 6)

  -- Capture Keyframe button
  if reaper.ImGui_Button(ctx, 'Capture Keyframe', 130) then CaptureKeyframe() end
  reaper.ImGui_SameLine(ctx)
  reaper.ImGui_Text(ctx, GetCaptureInfo())

  -- Write mode + replace toggles (right side)
  local x = winW-395
  reaper.ImGui_SetCursorPosX(ctx, x)
  if reaper.ImGui_RadioButton(ctx, 'At Cursor', writeMode==1) then writeMode=1 end
  reaper.ImGui_SameLine(ctx)
  if reaper.ImGui_RadioButton(ctx, 'Selection', writeMode==2) then writeMode=2 end
  reaper.ImGui_SameLine(ctx, nil, 14)
  local ch, val = reaper.ImGui_Checkbox(ctx, 'Replace Existing', replaceMode)
  if ch then replaceMode = val end

  -- Automode toggle (far right)
  reaper.ImGui_SameLine(ctx, winW-90)
  local live_mode = get_track_automode()
  local modeLabel, modeCol = automode_label_and_color(live_mode)
  reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Button(), modeCol)
  if reaper.ImGui_Button(ctx, modeLabel, 85) then
    local newMode = (live_mode==0 or live_mode==1) and 5 or 0
    set_automode(newMode)
  end
  reaper.ImGui_PopStyleColor(ctx)

  reaper.ImGui_Separator(ctx)

  -- === GROUP KEYFRAMES BY TRACK, SHOW MULTITRACK AT TOP ===
  local grouped = {}
  local multiTrack, sortedTracks = {}, {}
  for i, kf in ipairs(keyframes) do
    local ntracks = 0
    for id,data in pairs(kf.data) do
      if data.type=="track" then ntracks = ntracks+1 end
    end
    if ntracks > 1 then
      table.insert(multiTrack, { idx=i, kf=kf })
    elseif ntracks==1 then
      for id,data in pairs(kf.data) do
        if data.type=="track" then
          local trName = GetSourceName(data)
          grouped[trName] = grouped[trName] or { trackKeys={}, takeKeys={} }
          table.insert(grouped[trName].trackKeys, { idx=i, kf=kf })
        end
      end
      for id,data in pairs(kf.data) do
        if data.type=="take" then
          local tr = reaper.GetMediaItemTake_Track(data.source)
          local trName = reaper.GetTrackName(tr, "")
          trName = trName or "?"
          grouped[trName] = grouped[trName] or { trackKeys={}, takeKeys={} }
          table.insert(grouped[trName].takeKeys, { idx=i, kf=kf })
        end
      end
    end
  end
  for i=0,reaper.CountTracks(0)-1 do
    local tr = reaper.GetTrack(0,i)
    local _, name = reaper.GetTrackName(tr,"")
    if grouped[name] then table.insert(sortedTracks, { name=name, entry=grouped[name] }) end
  end

  local toDel, openByDefault

  -- --- MULTI TRACK KEYS ---
  if #multiTrack>0 then
    reaper.ImGui_Text(ctx, "Multi Track Keyframes")
    for _,item in ipairs(multiTrack) do
      local i, kf = item.idx, item.kf
      local sel = (i==activeKey)
      reaper.ImGui_PushID(ctx,i)
      local topY = reaper.ImGui_GetCursorPosY(ctx)
      reaper.ImGui_SetCursorPosX(ctx,pad)
      if reaper.ImGui_Selectable(ctx,string.format("%d: %s",i,kf.name),sel,0,winW-btnW-pad*2,0) then
        activeKey=i
      end
      reaper.ImGui_SetCursorPos(ctx,winW-btnW-pad*2,topY+1)
      reaper.ImGui_PushStyleColor(ctx,reaper.ImGui_Col_Button(),0x2222AAAA)
      if reaper.ImGui_Button(ctx,"X##"..i,btnW) then toDel=i end
      reaper.ImGui_PopStyleColor(ctx)
      reaper.ImGui_PopID(ctx)

      -- --- FX parameter dropdown (no redundant track header) ---
      openByDefault = autoOpen[i] or sel
      if openByDefault then autoOpen[i]=nil end
      if openByDefault and reaper.ImGui_TreeNode(ctx, "Parameters##multi"..i) then
        for id,data in pairs(kf.data) do
          for fxIdx,params in pairs(data.fx) do
            local fxName = data.type=='track'
              and select(2, reaper.TrackFX_GetFXName(data.source, fxIdx, "")) 
              or select(2, reaper.TakeFX_GetFXName(data.source, fxIdx, "")) 
            if reaper.ImGui_TreeNode(ctx, fxName.."##"..fxIdx..id..i) then
              for pIdx,val in pairs(params) do
                local pName = data.type=='track'
                  and select(2, reaper.TrackFX_GetParamName(data.source,fxIdx,pIdx,""))
                  or select(2, reaper.TakeFX_GetParamName(data.source,fxIdx,pIdx,""))
                local key  = id..'.'..fxIdx..'.'..pIdx
                local flag = kf.checked[id].fx[fxIdx][pIdx]
                local ch3, nf = reaper.ImGui_Checkbox(ctx, key, flag)
                if ch3 then kf.checked[id].fx[fxIdx][pIdx] = nf end
                reaper.ImGui_SameLine(ctx)
                reaper.ImGui_Text(ctx, pName..': '..string.format('%.3f', val))
              end
              reaper.ImGui_TreePop(ctx)
            end
          end
        end
        reaper.ImGui_TreePop(ctx)
      end
    end
    reaper.ImGui_Separator(ctx)
  end

  -- --- TRACK GROUPS ---
  for _,entry in ipairs(sortedTracks) do
    local name = entry.name
    local group = entry.entry
    reaper.ImGui_Text(ctx, "Track: "..name)
    -- Track group delete button (right)
    local y = reaper.ImGui_GetCursorPosY(ctx)-reaper.ImGui_GetTextLineHeight(ctx)
    reaper.ImGui_SetCursorPos(ctx,winW-btnW-pad*2,y)
    reaper.ImGui_PushStyleColor(ctx,reaper.ImGui_Col_Button(),0xFF4444DD)
    if reaper.ImGui_Button(ctx,"Delete Group##"..name,btnW+12) then
      for _,tkey in ipairs(group.trackKeys) do toDel=tkey.idx end
      for _,tkey in ipairs(group.takeKeys) do toDel=tkey.idx end
    end
    reaper.ImGui_PopStyleColor(ctx)
    reaper.ImGui_SetCursorPosX(ctx,pad)

    -- Track Keyframes
    for _,item in ipairs(group.trackKeys) do
      local i, kf = item.idx, item.kf
      local sel = (i==activeKey)
      reaper.ImGui_PushID(ctx,i)
      local topY = reaper.ImGui_GetCursorPosY(ctx)
      if reaper.ImGui_Selectable(ctx,string.format("%d: %s",i,kf.name),sel,0,winW-btnW-pad*2,0) then
        activeKey=i
      end
      reaper.ImGui_SetCursorPos(ctx,winW-btnW-pad*2,topY+1)
      reaper.ImGui_PushStyleColor(ctx,reaper.ImGui_Col_Button(),0x2222AAAA)
      if reaper.ImGui_Button(ctx,"X##"..i,btnW) then toDel=i end
      reaper.ImGui_PopStyleColor(ctx)
      reaper.ImGui_PopID(ctx)

      -- FX params
      openByDefault = autoOpen[i] or sel
      if openByDefault then autoOpen[i]=nil end
      if openByDefault and reaper.ImGui_TreeNode(ctx, "FX##tr"..i) then
        for id,data in pairs(kf.data) do
          if data.type=="track" then
            for fxIdx,params in pairs(data.fx) do
              local fxName = select(2, reaper.TrackFX_GetFXName(data.source, fxIdx, ""))
              if reaper.ImGui_TreeNode(ctx, fxName.."##"..fxIdx..id..i) then
                for pIdx,val in pairs(params) do
                  local pName = select(2, reaper.TrackFX_GetParamName(data.source,fxIdx,pIdx,""))
                  local key  = id..'.'..fxIdx..'.'..pIdx
                  local flag = kf.checked[id].fx[fxIdx][pIdx]
                  local ch3, nf = reaper.ImGui_Checkbox(ctx, key, flag)
                  if ch3 then kf.checked[id].fx[fxIdx][pIdx] = nf end
                  reaper.ImGui_SameLine(ctx)
                  reaper.ImGui_Text(ctx, pName..': '..string.format('%.3f', val))
                end
                reaper.ImGui_TreePop(ctx)
              end
            end
          end
        end
        reaper.ImGui_TreePop(ctx)
      end
    end
    -- Take Keyframes
    for _,item in ipairs(group.takeKeys) do
      local i, kf = item.idx, item.kf
      local sel = (i==activeKey)
      reaper.ImGui_PushID(ctx,i)
      local topY = reaper.ImGui_GetCursorPosY(ctx)
      if reaper.ImGui_Selectable(ctx,string.format("%d: %s",i,kf.name),sel,0,winW-btnW-pad*2,0) then
        activeKey=i
      end
      reaper.ImGui_SetCursorPos(ctx,winW-btnW-pad*2,topY+1)
      reaper.ImGui_PushStyleColor(ctx,reaper.ImGui_Col_Button(),0x2222AAAA)
      if reaper.ImGui_Button(ctx,"X##"..i,btnW) then toDel=i end
      reaper.ImGui_PopStyleColor(ctx)
      reaper.ImGui_PopID(ctx)

      -- FX params
      openByDefault = autoOpen[i] or sel
      if openByDefault then autoOpen[i]=nil end
      if openByDefault and reaper.ImGui_TreeNode(ctx, "FX##tk"..i) then
        for id,data in pairs(kf.data) do
          if data.type=="take" then
            for fxIdx,params in pairs(data.fx) do
              local fxName = select(2, reaper.TakeFX_GetFXName(data.source, fxIdx, ""))
              if reaper.ImGui_TreeNode(ctx, fxName.."##"..fxIdx..id..i) then
                for pIdx,val in pairs(params) do
                  local pName = select(2, reaper.TakeFX_GetParamName(data.source,fxIdx,pIdx,""))
                  local key  = id..'.'..fxIdx..'.'..pIdx
                  local flag = kf.checked[id].fx[fxIdx][pIdx]
                  local ch3, nf = reaper.ImGui_Checkbox(ctx, key, flag)
                  if ch3 then kf.checked[id].fx[fxIdx][pIdx] = nf end
                  reaper.ImGui_SameLine(ctx)
                  reaper.ImGui_Text(ctx, pName..': '..string.format('%.3f', val))
                end
                reaper.ImGui_TreePop(ctx)
              end
            end
          end
        end
        reaper.ImGui_TreePop(ctx)
      end
    end
    reaper.ImGui_Separator(ctx)
  end

  -- DELETE
  if toDel then DeleteKeyframe(toDel) end

  reaper.ImGui_End(ctx)
  reaper.defer(loop)
end

reaper.defer(loop)
