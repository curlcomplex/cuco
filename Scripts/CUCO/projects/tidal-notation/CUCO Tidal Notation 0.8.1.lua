--[[
ReaScript Name: CUCO Tidal Notation — v0.8.1
Author: curl + ChatGPT

What’s in this version
  • Watcher split-proof + name-only triggers for "~..."
  • 2.1: ~grid + notes + x/./_  (x, ., _ work without whitespace)
  • Hold fix: "_" ties extend properly to grid
  • 2.2: Stacks "[ ... ]" per-voice semantics (notes, x, _, .; omitted = rest)
  • 2.3: Subdivisions "( ... )"  (nested groups supported)
  • Debugger v1 (//debug //full|//brief //cap=N //notes)
  • //trace: PLAN-time per-voice action logs (start/extend/close/hold-start)
  • Robust SCAN (nil-safe, stable sorting)
  • Edge-smart PLAN binning + bin dump + REC bin logs
  • PLAN built from per-bin TRACE (append-only)
  • Debug helpers handle sparse voice maps 
  • SCAN rebuilt deterministically — per-note routing to closest bin-start
  • PPQ-aware epsilon for PLAN + SCAN to avoid tick-rounding mis-bins (//trace-scan)
  • NEW (0.7.0): Repeats `*N` on any token — note/x/./_, stack, group. `_ * N` behaves like `_` (extend once through the outer window).
]]

-------------------------------------------------------------------------------
-- Config / Globals
-------------------------------------------------------------------------------
local PROJ_NS          = "CUCO_TIDAL_NOTATION_ORIGINS"
local __BOOTED         = false
local VERBOSE_WATCHER  = false

-------------------------------------------------------------------------------
-- Console helpers (with cap)
-------------------------------------------------------------------------------
local __CAP = 300
local __LINES = 0
local function clog_reset(cap) __CAP = math.max(1, cap or 300); __LINES = 0; reaper.ShowConsoleMsg("") end
local function logln(s) if __LINES < __CAP then reaper.ShowConsoleMsg((s or "").."\n"); __LINES = __LINES + 1 end end

-------------------------------------------------------------------------------
-- Watcher state
-------------------------------------------------------------------------------i've
local STATE = { last_seen = {}, seeded = false, next_scan = 0.0, interval = 0.20 }

local function take_key(take)
  local item = reaper.GetMediaItemTake_Item(take)
  local _, guid = reaper.GetSetMediaItemInfo_String(item, "GUID", "", false)
  local idx, nt = -1, reaper.CountTakes(item)
  for t=0, nt-1 do if reaper.GetTake(item, t) == take then idx = t; break end end
  return guid.."::"..tostring(idx), item
end

-------------------------------------------------------------------------------
-- Item notes helpers (CTN origin tag)
-------------------------------------------------------------------------------
local function get_item_notes(item) local _, notes = reaper.GetSetMediaItemInfo_String(item, "P_NOTES", "", false); return notes or "" end
local function set_item_notes(item, notes) reaper.GetSetMediaItemInfo_String(item, "P_NOTES", notes or "", true) end
local function extract_ctn(notes) return notes:match("CTN:([%x]+)") end
local function add_ctn_if_missing(item)
  local notes = get_item_notes(item); local id = extract_ctn(notes)
  if id then return id end
  local t = reaper.time_precise(); local r = math.floor((t*1e6) % 0xffffffff)
  local new_id = string.format("%08x", r)
  set_item_notes(item, (notes ~= "" and (notes.."\n") or "").."CTN:"..new_id)
  logln(string.format("[ASSIGN-ORIGIN] origin=%s", new_id)); return new_id
end

-------------------------------------------------------------------------------
-- Project ExtState (committed name per origin)
-------------------------------------------------------------------------------
local function get_committed_name(origin_id) local ret,val=reaper.GetProjExtState(0,PROJ_NS,origin_id or ""); if ret==0 then return nil end; return (val~="" and val) or nil end
local function set_committed_name(origin_id, name) reaper.SetProjExtState(0, PROJ_NS, origin_id or "", name or "") end

-------------------------------------------------------------------------------
-- Music utils
-------------------------------------------------------------------------------
local PC_BASE = {c=0,d=2,e=4,f=5,g=7,a=9,b=11}
local PC_NAME = {[0]="c",[1]="c#",[2]="d",[3]="d#",[4]="e",[5]="f",[6]="f#",[7]="g",[8]="g#",[9]="a",[10]="a#",[11]="b"}
local function trim(s) return (s or ""):gsub("^%s+",""):gsub("%s+$","") end
local function note_to_midi(note)
  if type(note) ~= "string" then return nil end
  local l, a, o = note:match("^([a-gA-G])([b#]?)(%-?%d+)$"); if not l then return nil end
  local pc = PC_BASE[l:lower()] or 0; if a=="#" then pc=pc+1 elseif a=="b" then pc=pc-1 end
  return (tonumber(o)+1)*12 + pc
end
local function midi_to_note(m) local o=math.floor(m/12)-1; local pc=((m%12)+12)%12; return (PC_NAME[pc] or "c")..tostring(o) end
local function fmt_qn(x) return string.format("%.6f QN", x) end

-- QN epsilon based on MIDI PPQ resolution (≈ 1.5 ticks)
local function compute_eps_qn(take)
  local ppq0 = reaper.MIDI_GetPPQPosFromProjQN(take, 0)
  local ppq1 = reaper.MIDI_GetPPQPosFromProjQN(take, 1)
  local tpq  = math.max(1, (ppq1 - ppq0))
  return 1.5 / tpq
end

-------------------------------------------------------------------------------
-- Flags + header parsing
-------------------------------------------------------------------------------
local function parse_flags(name)
  local flags = { debug=false, full=false, brief=true, cap=300, notes=false, trace=false, trace_scan=false }
  for flag in name:gmatch("//%s*([^\n]+)") do
    local f = flag:lower()
    if f:find("debug") then flags.debug=true end
    if f:find("full") then flags.full=true; flags.brief=false end
    if f:find("brief") then flags.full=false; flags.brief=true end
    local cap=f:match("cap%s*=%s*(%d+)"); if cap then flags.cap=tonumber(cap) or flags.cap end
    if f:find("notes") then flags.notes=true end
    if f:find("trace%-?scan") then flags.trace_scan=true; flags.debug=true end
    if f:find("trace") and not f:find("trace%-?scan") then flags.trace=true; flags.debug=true end
  end
  return flags
end

local function parse_step_header(name)
  local stepQN, body = nil, name
  local hdr = name:match("^~%s*([%d%.]+%s*[tqsn]?)")
  if hdr then
    local num = hdr:match("^[%d%.]+"); local flag = hdr:match("[tqsn]$"); local denom = tonumber(num)
    if denom and denom>0 then
      stepQN = 4.0/denom
      if flag=="t" then stepQN=stepQN*(2/3)
      elseif flag=="q" then stepQN=stepQN*(4/5)
      elseif flag=="s" then stepQN=stepQN*(4/7)
      elseif flag=="n" then stepQN=stepQN*(8/9) end
    end
    body = name:sub(#hdr+2):gsub("^%s+","")
  end
  body = trim(body); if body:sub(1,1)=="~" then body=body:sub(2) end
  local body_clean = body:gsub("%s//.*$", "")
  return stepQN, body, trim(body_clean)
end

-------------------------------------------------------------------------------
-- Tokenizer (notes/x/./_, [stack], (group), repeat *N) — allows nested groups
-------------------------------------------------------------------------------
-- Optional: wrap a node with transpose (+/-N) if present after it
local function maybe_wrap_transpose_after(body, i, n, node)
  -- Look ahead from i (cursor at first char AFTER node)
  local k = i
  while k <= n and body:sub(k,k):match("%s") do k = k + 1 end
  local off = body:sub(k):match("^([+-]%d+)")
  if off then
    return { kind="transpose", n=tonumber(off) or 0, inner=node }, k + #off
  end
  return node, i
end

local function maybe_wrap_repeat_after(body, i, n, node)
  -- Look ahead from i (current cursor already at first char AFTER node)
  local k = i
  while k <= n and body:sub(k,k):match("%s") do k = k + 1 end
  local m = body:sub(k):match("^%*(%d+)")
  if m then
    local N = math.max(1, tonumber(m) or 1)
    return { kind="repeat", n=N, inner=node }, k + 1 + #m
  end
  return node, i
end

local function scan_chunk_with_repeats(chunk, out)
  local i, n = 1, #chunk
  while i <= n do
    local sub = chunk:sub(i)

    -- note(+/-tp)*rep
    local base, tp, rep = sub:match("^([a-gA-G][b#]?%-?%d+)([+-]%d+)%*(%d+)")
    if base and tp and rep then
      local node = { kind="transpose", n=tonumber(tp), inner=base }
      out[#out+1] = { kind="repeat", n=tonumber(rep), inner=node }
      i = i + #base + #tp + 1 + #rep
    else
      -- note*rep
      local note, rep2 = sub:match("^([a-gA-G][b#]?%-?%d+)%*(%d+)")
      if note and rep2 then
        out[#out+1] = { kind="repeat", n=tonumber(rep2), inner=note }
        i = i + #note + 1 + #rep2
      else
        -- note(+/-tp)
        local base2, tp2 = sub:match("^([a-gA-G][b#]?%-?%d+)([+-]%d+)")
        if base2 and tp2 then
          out[#out+1] = { kind="transpose", n=tonumber(tp2), inner=base2 }
          i = i + #base2 + #tp2
        else
          -- note
          local note2 = sub:match("^([a-gA-G][b#]?%-?%d+)")
          if note2 then
            out[#out+1] = note2
            i = i + #note2
          else
            -- x(+/-tp)*rep
            local x1, tpX, repX = sub:match("^([xX])([+-]%d+)%*(%d+)")
            if x1 and tpX and repX then
              local node = { kind="inherit", n=tonumber(tpX) or 0 }
              out[#out+1] = { kind="repeat", n=tonumber(repX), inner=node }
              i = i + 1 + #tpX + 1 + #repX
            else
              -- x(+/-tp)
              local x2, tpX2 = sub:match("^([xX])([+-]%d+)")
              if x2 and tpX2 then
                out[#out+1] = { kind="inherit", n=tonumber(tpX2) or 0 }
                i = i + 1 + #tpX2
              else
                -- symbol*rep
                local sym, rep3 = sub:match("^([xX%.%_])%*(%d+)")
                if sym then
                  out[#out+1] = { kind="repeat", n=tonumber(rep3), inner=sym:lower() }
                  i = i + 1 + 1 + #rep3
                else
                  -- symbol
                  local sym2 = sub:match("^([xX%.%_])")
                  if sym2 then
                    out[#out+1] = sym2:lower()
                    i = i + 1
                  else
                    -- skip unknown
                    i = i + 1
                  end
                end
              end
            end
          end
        end
      end
    end
  end
end

local function tokenize(body_clean)
  local toks = {}; local i, n = 1, #body_clean
  while i <= n do
    local ch = body_clean:sub(i,i)
    if ch:match("%s") then
      i = i + 1

    elseif ch=="[" then
      local j=i+1; while j<=n and body_clean:sub(j,j) ~= "]" do j=j+1 end
      local inner=body_clean:sub(i+1, math.min(j-1,n)); local entries={}
      for part in inner:gmatch("%S+") do entries[#entries+1]=part end
      local node = { kind="stack", entries=entries }
      -- Phase 3: allow [ ... ]+N and ensure transpose happens before repeat
      local node2, k2 = maybe_wrap_transpose_after(body_clean, j+1, n, node)
      local wrapped, ni = maybe_wrap_repeat_after(body_clean, k2, n, node2)
      toks[#toks+1] = wrapped; i = ni

    elseif ch=="(" then
      local j=i+1; while j<=n and body_clean:sub(j,j) ~= ")" do j=j+1 end
      local inner=body_clean:sub(i+1, math.min(j-1,n))
      local node = { kind="group", entries=tokenize(inner) }
      -- Phase 5: allow ( ... )+N and ensure transpose happens before repeat
      local node2, k2 = maybe_wrap_transpose_after(body_clean, j+1, n, node)
      local wrapped, ni = maybe_wrap_repeat_after(body_clean, k2, n, node2)
      toks[#toks+1] = wrapped; i = ni

    else
      local j=i
      while j<=n do local c=body_clean:sub(j,j); if c:match("%s") or c=="[" or c=="(" then break end; j=j+1 end
      local chunk = body_clean:sub(i, j-1)
      scan_chunk_with_repeats(chunk, toks)
      i = j
    end
  end
  return toks
end

-------------------------------------------------------------------------------
-- MIDI helpers
-------------------------------------------------------------------------------
local function get_item_pos_info(take)
  local item = reaper.GetMediaItemTake_Item(take)
  local pos = reaper.GetMediaItemInfo_Value(item, "D_POSITION")
  local len = reaper.GetMediaItemInfo_Value(item, "D_LENGTH")
  local sQN = reaper.TimeMap2_timeToQN(0, pos)
  local eQN = reaper.TimeMap2_timeToQN(0, pos+len)
  return pos, len, sQN, eQN
end
local function clear_take(take) reaper.MIDI_DisableSort(take); reaper.MIDI_SetAllEvts(take,""); reaper.MIDI_Sort(take) end
local function insert_notes(take,pitches,sQN,eQN,vel)
  local sPPQ=reaper.MIDI_GetPPQPosFromProjQN(take,sQN); local ePPQ=reaper.MIDI_GetPPQPosFromProjQN(take,eQN)
  for _,m in ipairs(pitches) do reaper.MIDI_InsertNote(take,false,false,sPPQ,ePPQ,0,m,vel or 96,false) end
end
local function write_events_to_midi(take, events)
  for _,ev in ipairs(events) do
    local sPPQ = reaper.MIDI_GetPPQPosFromProjQN(take, ev.sQN)
    local ePPQ = reaper.MIDI_GetPPQPosFromProjQN(take, ev.eQN)
    reaper.MIDI_InsertNote(take, false, false, sPPQ, ePPQ, ev.ch or 0, ev.pitch, ev.vel or 96, false)
  end
end
local function compute_step_qn_or_fallback(take, stepQN_opt, step_count)
  if stepQN_opt then return stepQN_opt end
  step_count=math.max(1, tonumber(step_count) or 1)
  local _,_,sQN,eQN=get_item_pos_info(take); local itemLenQN=math.max(1e-6, eQN-sQN)
  return itemLenQN/step_count
end

-------------------------------------------------------------------------------
-- Executor builder (supports write/plan; recursive groups; repeats; PLAN tracing)
-------------------------------------------------------------------------------
local function make_executor(take, default_pitch, last_voices, voice_current, mode, recorder, trace)
  -- Phase 0: closure-owned event list (write-mode intermediate; one record per emitted note)
  local events = {}
  local function emit_event(pitch, sQN, eQN)
    events[#events+1] = { pitch=pitch, sQN=sQN, eQN=eQN, vel=96, ch=0, attrs={} }
  end
  -- Anchor pitch for top-level inherit; set by real notes only (not by x)
  local anchor_pitch = nil
  -- Phase 7: anchor voices (baked chord/group) for external x / x±N
  local anchor_voices = {}
  -- Phase 7: replayable token for external x / x±N (e.g., groups)
  local anchor_replay = nil
  -- Phase 7: store the transpose offset that was applied when the group was baked
  local anchor_replay_offset = 0
  -- Phase 7: optional callback for collecting pitches during group baking
  local group_collect_cb = nil
  local function dlog(fmt, ...)
    if trace then logln(string.format(fmt, ...)) end
  end
  local function rec_emit(voice,pitch,sQN,eQN) if recorder then recorder(voice,pitch,sQN,eQN) end end
  local function start_voice(i,pitch,sQN,eQN)
    if mode=="plan" then dlog("PLAN start v%d %d %.3f→%.3f", i, pitch, sQN, eQN) end
    voice_current[i]={pitch=pitch,startQN=sQN,endQN=eQN}
    -- If a group is baking, collect every emitted pitch
    if group_collect_cb then group_collect_cb(i, pitch, sQN, eQN) end
  end
  local function flush_voice(i)
    local blk=voice_current[i]; if blk then
      if mode=="plan" then dlog("PLAN close v%d %d %.3f→%.3f", i, blk.pitch, blk.startQN, blk.endQN) end
      if mode=="write" then emit_event(blk.pitch, blk.startQN, blk.endQN) else rec_emit(i,blk.pitch,blk.startQN,blk.endQN) end
      voice_current[i]=nil
    end
  end
  local function flush_all()
    for i,blk in pairs(voice_current) do
      if blk then
        if mode=="plan" then dlog("PLAN close v%d %d %.3f→%.3f", i, blk.pitch, blk.startQN, blk.endQN) end
        if mode=="write" then emit_event(blk.pitch, blk.startQN, blk.endQN) else rec_emit(i,blk.pitch,blk.startQN,blk.endQN) end
        voice_current[i]=nil
      end
    end
  end
  local function extend_all(eQN)
    for i,blk in pairs(voice_current) do
      if blk then
        if mode=="plan" then dlog("PLAN extend v%d %.3f→%.3f", i, blk.endQN, eQN) end
        blk.endQN=eQN
      end
    end
  end
  local function set_last_from_array(arr) for i=1, math.max(#last_voices,#arr) do last_voices[i]=arr[i] end end

  local exec_token -- forward
  local function exec_window(tok, sQN, eQN, tp_offset)
    tp_offset = tp_offset or 0

    if type(tok)=="table" and tok.kind=="transpose" then
      local n = tonumber(tok.n) or 0
      exec_window(tok.inner, sQN, eQN, tp_offset + n)
      return
    end

    if type(tok)=="table" and tok.kind=="group" then
      -- Phase 6+7: group-local scope for x / x±N; then expose baked group externally as UNION of pitches
      -- Shadow outer state during group evaluation
      local outer_last = last_voices
      local outer_anchor_pitch = anchor_pitch
      local outer_anchor_voices = anchor_voices
      local outer_anchor_replay = anchor_replay
      local outer_anchor_replay_offset = anchor_replay_offset
      local outer_collect = group_collect_cb

      last_voices   = {}   -- group-local last
      anchor_pitch  = nil  -- group-local note anchor
      anchor_voices = {}   -- group-local chord anchor
      anchor_replay = nil  -- group-local: don't reuse an outer group's replay inside
      anchor_replay_offset = 0

      -- Collect every pitch emitted inside the group
      local seen = {}
      group_collect_cb = function(_, pitch) seen[pitch] = true end

      -- Evaluate group entries across its window (time-subdivided as before)
      local N = math.max(1, #tok.entries)
      local subLen = (eQN - sQN) / N
      for i,subtok in ipairs(tok.entries) do
        local sSub = sQN + (i-1)*subLen; local eSub = sSub + subLen
        exec_window(subtok, sSub, eSub, tp_offset)
      end

      -- Build baked chord = union of pitches encountered inside the group
      local baked = {}
      for m,_ in pairs(seen) do baked[#baked+1] = m end
      table.sort(baked)  -- stable voice ordering

      -- Restore outer containers
      group_collect_cb = outer_collect
      last_voices      = outer_last
      anchor_pitch     = outer_anchor_pitch
      anchor_voices    = outer_anchor_voices
      anchor_replay    = outer_anchor_replay
      anchor_replay_offset = outer_anchor_replay_offset

      -- Publish baked chord AND a replayable group to outer scope
      if #baked > 0 then
        set_last_from_array(baked)   -- bare x can mirror the chord if needed
        anchor_voices = baked        -- x±N can transpose the baked chord
        anchor_pitch  = baked[1]
        -- Keep a replayable copy of the group so bare x / x±N can repeat group timing
        local repl = { kind="group", entries = {} }
        for i,u in ipairs(tok.entries) do repl.entries[i] = u end
        anchor_replay = repl
        anchor_replay_offset = tp_offset   -- << remember the group's applied transpose
      else
        anchor_replay = nil
        anchor_replay_offset = 0
      end
      return
    end

    if type(tok)=="table" and tok.kind=="repeat" then
      local N = math.max(1, tonumber(tok.n) or 1)
      -- Special case: underscore repeat acts like a single extend through the outer window
      if N > 1 and type(tok.inner)=="string" and tok.inner:lower()=="_" then
        exec_token("_", sQN, eQN, tp_offset)
        return
      end
      if N <= 1 then
        exec_window(tok.inner, sQN, eQN, tp_offset)
        return
      end
      local sliceLen = (eQN - sQN) / N
      for i=1,N do
        local sSub = sQN + (i-1)*sliceLen
        local eSub = sSub + sliceLen
        exec_window(tok.inner, sSub, eSub, tp_offset)
      end
      return
    end

    exec_token(tok, sQN, eQN, tp_offset)
  end

  exec_token = function(tok, sQN, eQN, tp_offset)
    tp_offset = tp_offset or 0

    -- Inherit with offset: prefer replaying the last group; fallback to baked chord, then pitch
    if type(tok)=="table" and tok.kind=="inherit" then
      local offset = (tonumber(tok.n) or 0) + (tp_offset or 0)
      flush_all()
      if anchor_replay and type(anchor_replay)=="table" and anchor_replay.kind=="group" then
        -- Re-run the group's timing over this window, including the original group's transpose
        exec_window(anchor_replay, sQN, eQN, offset + (anchor_replay_offset or 0))
      elseif anchor_voices and #anchor_voices > 0 then
        local new_last = {}
        for i,base in ipairs(anchor_voices) do
          local m = base + offset
          start_voice(i, m, sQN, eQN)
          new_last[i] = m
        end
        set_last_from_array(new_last)
      else
        local base = anchor_pitch or default_pitch
        local m = base + offset
        start_voice(1, m, sQN, eQN)
        last_voices[1] = m
        for i=2,#last_voices do last_voices[i]=nil end
      end
      return
    end

    if type(tok)=="table" and tok.kind=="stack" then
      local entries = tok.entries; local new_last={}
      for i,entry in ipairs(entries) do
        if type(entry)~="string" then
          -- (group-inside-stack is parked — ignore non-strings here)
          flush_voice(i); new_last[i]=nil
        else
          local el=entry:lower()
          if el=="." then
            flush_voice(i); new_last[i]=nil
          elseif el=="_" then
            if voice_current[i] then
              if mode=="plan" then dlog("PLAN extend v%d %.3f→%.3f", i, voice_current[i].endQN, eQN) end
              voice_current[i].endQN=eQN; new_last[i]=voice_current[i].pitch
            elseif last_voices[i] then
              if mode=="plan" then dlog("PLAN hold-start v%d %d %.3f→%.3f", i, last_voices[i], sQN, eQN) end
              start_voice(i,last_voices[i],sQN,eQN); new_last[i]=last_voices[i]
            else
              new_last[i]=nil
            end
          elseif el=="x" then
            local prev=last_voices[i]
            if prev then
              flush_voice(i)
              start_voice(i,prev,sQN,eQN); new_last[i]=prev
            else
              flush_voice(i); new_last[i]=nil
            end
          else
            local m=note_to_midi(entry)
            if m then
              m = m + (tp_offset or 0)
              flush_voice(i)
              start_voice(i,m,sQN,eQN); new_last[i]=m
            else
              flush_voice(i); new_last[i]=nil
            end
          end
        end
      end
      local max_prev=#last_voices
      for i=#entries+1, max_prev do flush_voice(i); new_last[i]=nil end
      set_last_from_array(new_last)
      -- Phase 7: expose baked stack as anchor for external x / x±N
      anchor_voices = {}
      for i=1,#new_last do anchor_voices[i] = new_last[i] end
      if anchor_voices[1] then anchor_pitch = anchor_voices[1] end
      -- New: last “structure” is a stack → stop replaying an old group
      anchor_replay = nil
      anchor_replay_offset = 0

    else
      if type(tok)~="string" then return end
      local tl=tok:lower()
      if tl=="." then
        flush_all()
      elseif tl=="_" then
        extend_all(eQN)
      elseif tl=="x" then
        flush_all()
        if anchor_replay and type(anchor_replay)=="table" and anchor_replay.kind=="group" then
          -- Re-run the group's timing exactly as baked (including the original transpose)
          exec_window(anchor_replay, sQN, eQN, anchor_replay_offset or 0)
        else
          -- Fallback: mirror the last chord/voices
          local any=false
          local src = (anchor_voices and #anchor_voices>0) and anchor_voices or last_voices
          for i,p in ipairs(src) do if p then start_voice(i,p,sQN,eQN); any=true end end
          if not any then
            start_voice(1, default_pitch, sQN,eQN)
            last_voices[1]=default_pitch; for i=2,#last_voices do last_voices[i]=nil end
            anchor_voices = { default_pitch }
            anchor_pitch  = default_pitch
          end
        end
      else
        local m=note_to_midi(tok)
        if m then
          m = m + tp_offset
          flush_all()
          start_voice(1,m,sQN,eQN)
          last_voices[1]=m
          for i=2,#last_voices do last_voices[i]=nil end
          anchor_pitch  = m
          anchor_voices = { m }
          anchor_replay = nil
          anchor_replay_offset = 0
        end
      end
    end
  end

  return exec_window, events, flush_all
end

-------------------------------------------------------------------------------
-- Debug helpers (sparse-map aware)
-------------------------------------------------------------------------------
local function plan_differs(a, b)
  if a == b then return false end
  a, b = a or {}, b or {}
  local seen = {}
  for v,_ in pairs(a) do seen[v] = true end
  for v,_ in pairs(b) do seen[v] = true end
  for v,_ in pairs(seen) do
    local va, vb = a[v], b[v]
    if (va and not vb) or (vb and not va) then return true end
    if va and vb then
      if va.pitch ~= vb.pitch
         or math.abs((va.s or 0) - (vb.s or 0)) > 1e-9
         or math.abs((va.e or 0) - (vb.e or 0)) > 1e-9 then
        return true
      end
    end
  end
  return false
end

local function fmt_voice_row(row, notesFlag)
  local tmp = {}
  for v,ev in pairs(row or {}) do
    if ev and ev.pitch and ev.s and ev.e then
      tmp[#tmp+1] = { v=v, pitch=ev.pitch, s=ev.s, e=ev.e }
    end
  end
  table.sort(tmp, function(a,b) return a.v < b.v end)
  local parts = {}
  for _,ev in ipairs(tmp) do
    local p = tostring(ev.pitch)
    if notesFlag then p = p.."("..midi_to_note(ev.pitch)..")" end
    parts[#parts+1] = string.format("v%d=%s %.3f→%.3f", ev.v, p, ev.s, ev.e)
  end
  return table.concat(parts, "  ")
end

local function copy_row(row)
  local t = {}
  for v,ev in pairs(row or {}) do
    if ev and ev.pitch and ev.s and ev.e then
      t[v] = { pitch=ev.pitch, s=ev.s, e=ev.e }
    end
  end
  return t
end

local function collect_leaf_bins(token, sQN, eQN, out_bins)
  if type(token)=="table" and token.kind=="group" then
    local N = math.max(1, #token.entries); local subLen=(eQN - sQN)/N
    for i,subtok in ipairs(token.entries) do local sSub=sQN+(i-1)*subLen; local eSub=sSub+subLen; collect_leaf_bins(subtok, sSub, eSub, out_bins) end
  else
    out_bins[#out_bins+1] = { s=sQN, e=eQN, plan={}, actual={}, trace={} }
  end
end

-------------------------------------------------------------------------------
-- Deterministic SCAN (rebuild): route each actual note to closest bin-start
-------------------------------------------------------------------------------
local function scan_actual_bins_rebuild(take, bins, flags, eps_qn)
  -- 1) Load all notes
  local notes = {}
  local _, noteCount = reaper.MIDI_CountEvts(take)
  for i=0, noteCount-1 do
    local ok, _, _, sPPQ, ePPQ, _, pitch = reaper.MIDI_GetNote(take, i)
    if ok then
      local sQN = reaper.MIDI_GetProjQNFromPPQPos(take, sPPQ)
      local eQN = reaper.MIDI_GetProjQNFromPPQPos(take, ePPQ)
      notes[#notes+1] = { pitch=pitch, s=sQN, e=eQN }
    end
  end
  -- 2) route to best bin by closest start within [s-eps, e+eps]
  for _,ev in ipairs(notes) do
    local sQN, eQN, pitch = ev.s, ev.e, ev.pitch
    local best_idx, best_dist = nil, 1e9
    for i,bb in ipairs(bins) do
      local s, e = bb.s, bb.e
      if s and e and (sQN >= s - eps_qn) and (sQN <= e + eps_qn) then
        local d = math.abs(sQN - s)
        if d < best_dist then best_dist = d; best_idx = i end
      end
    end
    if best_idx then
      local bb = bins[best_idx]
      bb.actual[#bb.actual+1] = { pitch=pitch, s=sQN, e=eQN }
      if flags and flags.trace_scan then
        logln(string.format("SCAN bin %02d p%d %.3f→%.3f", best_idx, pitch, sQN, eQN))
      end
    elseif flags and flags.trace_scan then
      logln(string.format("SCAN no-bin p%d %.3f→%.3f", pitch, sQN, eQN))
    end
  end
end

local function safe_sort_events(evts, fallback_s, fallback_e)
  table.sort(evts, function(a,b)
    local ap = a and a.pitch or -1
    local bp = b and b.pitch or -1
    if ap ~= bp then return ap < bp end
    local as = (a and a.s) or fallback_s or 0
    local bs = (b and b.s) or fallback_s or 0
    if math.abs(as - bs) > 1e-9 then return as < bs end
    local ae = (a and a.e) or fallback_e or as
    local be = (b and b.e) or fallback_e or bs
    return ae < be
  end)
end

-------------------------------------------------------------------------------
-- Process up to repeats (with optional debug)
-------------------------------------------------------------------------------
local function process_notation_step24(take, name)
  local flags = parse_flags(name)
  local stepQN_opt, _, body_clean = parse_step_header(name)
  local tokens = tokenize(body_clean)

  local stepQN = compute_step_qn_or_fallback(take, stepQN_opt, #tokens)
  local _,_,itemStartQN = get_item_pos_info(take)
  local default_pitch = 60
  local eps_qn = compute_eps_qn(take)

  -- DEBUG: parse echo
  if flags.debug then
    clog_reset(flags.cap)
    logln(string.format("[DEBUG] name='%s'", name))
    logln(string.format("[PARSE] stepLen=%s steps=%d", fmt_qn(stepQN), #tokens))
    if flags.full then
      local function ts(t)
        if type(t)=="string" then return t
        elseif t.kind=="stack" then return "stack["..table.concat(t.entries," ").."]"
        elseif t.kind=="group" then local xs={}; for _,u in ipairs(t.entries) do xs[#xs+1]=ts(u) end; return "group("..table.concat(xs," ")..")"
        elseif t.kind=="repeat" then return "repeat("..ts(t.inner).."*"..tostring(t.n)..")"
        elseif t.kind=="transpose" then return "transpose("..ts(t.inner).."@"..tostring(t.n)..")"
        elseif t.kind=="inherit" then return "inherit("..tostring(t.n)..")"
        end
        return "?"
      end
      local xs={}; for _,t in ipairs(tokens) do xs[#xs+1]=ts(t) end
      logln("[TOKENS] "..table.concat(xs,"  "))
    end
  end

  -- Plan bins (leaf-level)
  local bins = nil
  if flags.debug then
    bins = {}
    for k, tok in ipairs(tokens) do
      local sQN = itemStartQN + (k-1)*stepQN; local eQN = sQN + stepQN
      collect_leaf_bins(tok, sQN, eQN, bins)
    end
    if flags.trace then
      logln("[BINS]")
      for i,bb in ipairs(bins) do
        logln(string.format("  %02d: %.6f→%.6f", i, bb.s or -1, bb.e or -1))
      end
    end
  end

  -- PLAN pass
  if flags.debug then
    local last_voices, voice_current = {}, {}

    local function recorder(voice, pitch, sQN, eQN)
      local best_idx, best_dist = nil, 1e9
      for i,bb in ipairs(bins) do
        local s, e = bb.s, bb.e
        if s and e and (sQN >= s - eps_qn) and (sQN <= e + eps_qn) then
          local d = math.abs(sQN - s)
          if d < best_dist then best_dist = d; best_idx = i end
        end
      end
      if best_idx then
        local bb = bins[best_idx]
        bb.trace[#bb.trace+1] = { voice=voice, pitch=pitch, s=sQN, e=eQN }
        if flags.trace then
          logln(string.format("REC bin %02d v%d %d %.3f→%.3f", best_idx, voice, pitch, sQN, eQN))
        end
      elseif flags.trace then
        logln(string.format("REC no-bin v%d %d %.3f→%.3f", voice, pitch, sQN, eQN))
      end
    end

    local exec = make_executor(take, default_pitch, last_voices, voice_current, "plan", recorder, flags.trace)
    for k, tok in ipairs(tokens) do
      local sQN = itemStartQN + (k-1)*stepQN; local eQN = sQN + stepQN
      exec(tok, sQN, eQN, 0)
    end
    for v,blk in pairs(voice_current) do recorder(v, blk.pitch, blk.startQN, blk.endQN) end

    -- Build PLAN rows from trace: last event per voice within that bin (sparse map)
    for _,bb in ipairs(bins) do
      local last_per_voice = {}
      for _,ev in ipairs(bb.trace) do
        last_per_voice[ev.voice] = { pitch=ev.pitch, s=ev.s, e=ev.e }
      end
      bb.plan = last_per_voice
    end

    if flags.full then
      logln("[PLAN] (state changes only)")
      local prev=nil
      for i,bb in ipairs(bins) do
        if plan_differs(bb.plan, prev) then
          local snap = copy_row(bb.plan)
          logln(string.format("  bin %02d  %.3f→%.3f  %s", i, bb.s, bb.e, fmt_voice_row(snap, flags.notes)))
          prev = snap
        end
      end
    end
  end

  -- WRITE pass
  clear_take(take)
  do
    local last_voices, voice_current = {}, {}
    local step_exec, events, flush_all = make_executor(take, default_pitch, last_voices, voice_current, "write", nil, false)
    for k, tok in ipairs(tokens) do
      local sQN = itemStartQN + (k-1)*stepQN; local eQN = sQN + stepQN
      step_exec(tok, sQN, eQN, 0)
    end
    flush_all()
    write_events_to_midi(take, events)
  end
  reaper.MIDI_Sort(take)

  -- SCAN + DIFF (rebuild)
  if flags.debug and bins then
    scan_actual_bins_rebuild(take, bins, flags, eps_qn)

    if flags.full then
      logln("[SCAN] (state changes only)")
      local prev=nil
      for i,bb in ipairs(bins) do
        safe_sort_events(bb.actual, bb.s, bb.e)
        local row={}
        for idx,ev in ipairs(bb.actual) do
          if ev and ev.pitch and ev.s and ev.e then row[idx]={pitch=ev.pitch,s=ev.s,e=ev.e} end
        end
        if plan_differs(row, prev) then
          local snap = copy_row(row)
          logln(string.format("  bin %02d  %.3f→%.3f  %s", i, bb.s, bb.e, fmt_voice_row(snap, flags.notes)))
          prev = snap
        end
      end
    end

    local function canon(row)
      local t={}
      for _,ev in pairs(row or {}) do
        if type(ev)=="table" and ev.pitch and ev.s and ev.e then
          t[#t+1]=string.format("%d@%.6f→%.6f",ev.pitch,ev.s,ev.e)
        end
      end
      table.sort(t); return table.concat(t,"|")
    end

    local mism=0
    for _,bb in ipairs(bins) do
      safe_sort_events(bb.actual, bb.s, bb.e)
      local plan_row, actual_row = bb.plan, {}
      for idx,ev in ipairs(bb.actual) do
        if ev and ev.pitch and ev.s and ev.e then actual_row[idx]={pitch=ev.pitch,s=ev.s,e=ev.e} end
      end
      if canon(plan_row) ~= canon(actual_row) then mism=mism+1 end
    end
    logln(string.format("[CHECK] bins=%d mismatches=%d", #bins, mism))
  end

  logln(string.format("[WRITE] steps=%d stepLen=%s", #tokens, fmt_qn(stepQN)))
end

-------------------------------------------------------------------------------
-- Trigger handler
-------------------------------------------------------------------------------
local function handle_trigger(take, name)
  local key, item = take_key(take)
  local origin_id = add_ctn_if_missing(item)
  local committed = get_committed_name(origin_id)
  if committed and committed == name then logln(string.format("[IGNORED-SPLIT] '%s' origin=%s", name, origin_id)); return end
  logln(string.format("[TRIGGER] '%s' origin=%s", name, origin_id))
  local ok, err = pcall(process_notation_step24, take, name)
  if not ok then logln("[CUCO Tidal Notation Error] "..tostring(err)); return end
  set_committed_name(origin_id, name)
end

-------------------------------------------------------------------------------
-- Boot seed + watcher
-------------------------------------------------------------------------------
local function seed_cache_once()
  if STATE.seeded then return end
  local proj=0; local count=0; local item_cnt=reaper.CountMediaItems(proj)
  for i=0,item_cnt-1 do
    local item=reaper.GetMediaItem(proj,i); local take_cnt=reaper.CountTakes(item)
    for t=0,take_cnt-1 do
      local take=reaper.GetTake(item,t)
      if take and reaper.TakeIsMIDI(take) then
        local _,nm=reaper.GetSetMediaItemTakeInfo_String(take,"P_NAME","",false)
        local key=take_key(take); STATE.last_seen[key]=nm or ""; count=count+1
      end
    end
  end
  STATE.seeded=true; logln(string.format("[SEED] cached %d takes", count))
end

local function scan_once()
  local now=reaper.time_precise(); if now<STATE.next_scan then return end; STATE.next_scan=now+STATE.interval
  if not __BOOTED then logln("[CUCO Tidal Notation] Watcher running (v0.8.1)"); __BOOTED=true; seed_cache_once() end
  local proj=0; local item_cnt=reaper.CountMediaItems(proj)
  for i=0,item_cnt-1 do
    local item=reaper.GetMediaItem(proj,i); local take_cnt=reaper.CountTakes(item)
    for t=0,take_cnt-1 do
      local take=reaper.GetTake(item,t)
      if take and reaper.TakeIsMIDI(take) then
        local _,name=reaper.GetSetMediaItemTakeInfo_String(take,"P_NAME","",false); name=name or ""
        local key, itm = take_key(take); local prev=STATE.last_seen[key]
        if prev==nil then STATE.last_seen[key]=name
          if VERBOSE_WATCHER then
            local id=extract_ctn(get_item_notes(itm))
            if id then logln(string.format("[NEW-TAKE] cached '%s' origin=%s", name, id)) else logln(string.format("[NEW-TAKE] cached '%s' (no origin)", name)) end
          end
        elseif prev ~= name then
          STATE.last_seen[key]=name
          if name:sub(1,1) ~= "~" then logln(string.format("[SKIP-NOPREFIX] '%s'", name))
          else local ok,err=pcall(handle_trigger,take,name); if not ok then logln("[Watcher Error] "..tostring(err)) end end
        end
      end
    end
  end
end

local function main_loop() local ok,err=pcall(scan_once); if not ok then logln("[Watcher Error] "..tostring(err)) end; reaper.defer(main_loop) end

-- Start
reaper.Undo_BeginBlock(); main_loop(); reaper.Undo_EndBlock("CUCO Tidal Notation — v0.8.1", -1)
