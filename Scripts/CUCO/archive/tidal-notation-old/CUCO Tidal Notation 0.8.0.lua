--[[
ReaScript Name: CUCO Tidal Notation — v0.8.0 (Phase A)
Author: curl + ChatGPT

Phase A Scope:
  • New rest token ":" (colon). Hyphen "-" reserved for transpose.
  • Transpose suffix ±N on notes, x, and stacks (groups unchanged in Phase A).
  • x / x±N uses S_anchor (last explicit note/stack outside groups, UNTRANSPOSED). x does not mutate the anchor.
  • Precedence: transpose → repeat (apply transpose before *N subdivisions).
  • Debugger kept as in 0.7.x; wording overhaul shelved.
]]--

------------------------------------------------------------
-- Config / Globals
------------------------------------------------------------
local PROJ_NS          = "CUCO_TIDAL_NOTATION_ORIGINS"
local __BOOTED         = false
local VERBOSE_WATCHER  = false

------------------------------------------------------------
-- Console helpers (with cap)
------------------------------------------------------------
local __CAP = 300
local __LINES = 0
local function clog_reset(cap) __CAP = math.max(1, cap or 300); __LINES = 0; reaper.ShowConsoleMsg("") end
local function logln(s) if __LINES < __CAP then reaper.ShowConsoleMsg((s or "").."\n"); __LINES = __LINES + 1 end end

------------------------------------------------------------
-- Watcher state
------------------------------------------------------------
local STATE = { last_seen = {}, seeded = false, next_scan = 0.0, interval = 0.20 }

local function take_key(take)
  local item = reaper.GetMediaItemTake_Item(take)
  local _, guid = reaper.GetSetMediaItemInfo_String(item, "GUID", "", false)
  local idx, nt = -1, reaper.CountTakes(item)
  for t=0, nt-1 do if reaper.GetTake(item, t) == take then idx = t; break end end
  return guid.."::"..tostring(idx), item
end

------------------------------------------------------------
-- Item notes helpers (CTN origin tag)
------------------------------------------------------------
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

------------------------------------------------------------
-- Project ExtState (committed name per origin)
------------------------------------------------------------
local function get_committed_name(origin_id) local ret,val=reaper.GetProjExtState(0,PROJ_NS,origin_id or ""); if ret==0 then return nil end; return (val~="" and val) or nil end
local function set_committed_name(origin_id, name) reaper.SetProjExtState(0, PROJ_NS, origin_id or "", name or "") end

------------------------------------------------------------
-- Music utils + normalization
------------------------------------------------------------
local PC_BASE = {c=0,d=2,e=4,f=5,g=7,a=9,b=11}
local PC_NAME = {[0]="c",[1]="c#",[2]="d",[3]="d#",[4]="e",[5]="f",[6]="f#",[7]="g",[8]="g#",[9]="a",[10]="a#",[11]="b"}

local function trim(s) s = s or ""; s = s:gsub("^%s+", ""):gsub("%s+$",""); return s end

-- Strip hidden/invisible characters that break parsing (BOM, ZWSP, NBSP)
local function strip_invisible(s)
  s = s or ""
  -- UTF-8 BOM
  s = s:gsub("\239\187\191", "")
  -- zero-width space & friends
  s = s:gsub("\226\128\139", "")   -- ZWSP
  s = s:gsub("\226\128\140", "")   -- ZWNJ
  s = s:gsub("\226\128\141", "")   -- WJ
  -- NBSP → regular space
  s = s:gsub("\194\160", " ")
  return s
end

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

------------------------------------------------------------
-- Flags + header parsing
------------------------------------------------------------
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
  name = strip_invisible(name)
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
  body = strip_invisible(body)
  body = trim(body); if body:sub(1,1)=="~" then body=body:sub(2) end
  local body_clean = body:gsub("%s//.*$", "")
  body_clean = strip_invisible(body_clean)
  return stepQN, body, trim(body_clean)
end

------------------------------------------------------------
-- Robust tokenizer (split on spaces outside containers)
------------------------------------------------------------
local function split_top_level(body)
  local toks, buf = {}, {}
  local depth_sq, depth_par = 0, 0
  local i, n = 1, #body
  local function push_buf()
    if #buf > 0 then
      toks[#toks+1] = table.concat(buf)
      buf = {}
    end
  end
  while i <= n do
    local ch = body:sub(i,i)
    if ch == "[" then depth_sq = depth_sq + 1; buf[#buf+1]=ch
    elseif ch == "]" then depth_sq = math.max(0, depth_sq - 1); buf[#buf+1]=ch
    elseif ch == "(" then depth_par = depth_par + 1; buf[#buf+1]=ch
    elseif ch == ")" then depth_par = math.max(0, depth_par - 1); buf[#buf+1]=ch
    elseif ch:match("%s") and depth_sq==0 and depth_par==0 then
      push_buf()
    else
      buf[#buf+1]=ch
    end
    i = i + 1
  end
  push_buf()
  return toks
end

local function split_inner_atoms(inner)
  local out = {}
  inner = strip_invisible(inner)
  for part in inner:gmatch("%S+") do out[#out+1] = part end
  return out
end

local function parse_top_token(tok)
  tok = strip_invisible(tok)
  -- Stack: [ ... ] (+optional transpose, +optional *N)
  if tok:sub(1,1) == "[" then
    local inner, rest = tok:match("^%[(.*)%](.*)$")
    inner = inner or ""
    local node = { kind="stack", entries = split_inner_atoms(trim(inner)) }
    local tp, tail = nil, rest or ""
    local sign, num, after = tail:match("^%s*([%+%-])(%d+)(.*)$")
    if sign and num then tp = (sign=="-" and -tonumber(num) or tonumber(num)); tail = after or "" end
    local rep = nil; local repnum = tail:match("^%s*%*(%d+)%s*$")
    if repnum then rep = math.max(1, tonumber(repnum) or 1) end
    if tp or rep then return { kind="mod", transpose=tp, repeat_n=rep, inner=node } end
    return node
  end
  -- Group: ( ... ) (+optional *N only in Phase A)
  if tok:sub(1,1) == "(" then
    local inner, rest = tok:match("^%((.*)%)%s*(.*)$")
    inner = inner or ""
    local node = { kind="group", entries = tokenize(trim(inner)) }
    local rep = nil; local repnum = rest:match("^%*%s*(%d+)%s*$")
    if repnum then return { kind="mod", transpose=nil, repeat_n=math.max(1, tonumber(repnum) or 1), inner=node } end
    return node
  end
  -- Otherwise: atom
  return tok
end

function tokenize(body_clean)
  body_clean = strip_invisible(body_clean)
  local raw = split_top_level(body_clean)
  local ast = {}
  for _,tok in ipairs(raw) do
    tok = trim(strip_invisible(tok))
    if tok ~= "" then ast[#ast+1] = parse_top_token(tok) end
  end
  return ast
end

------------------------------------------------------------
-- MIDI helpers
------------------------------------------------------------
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
local function compute_step_qn_or_fallback(take, stepQN_opt, step_count)
  if stepQN_opt then return stepQN_opt end
  step_count=math.max(1, tonumber(step_count) or 1)
  local _,_,sQN,eQN=get_item_pos_info(take); local itemLenQN=math.max(1e-6, eQN-sQN)
  return itemLenQN/step_count
end

------------------------------------------------------------
-- PLAN helpers
------------------------------------------------------------
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
  elseif type(token)=="table" and token.kind=="mod" then
    collect_leaf_bins(token.inner, sQN, eQN, out_bins)
  else
    out_bins[#out_bins+1] = { s=sQN, e=eQN, plan={}, actual={}, trace={} }
  end
end

------------------------------------------------------------
-- SCAN (rebuild)
------------------------------------------------------------
local function scan_actual_bins_rebuild(take, bins, flags, eps_qn)
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

------------------------------------------------------------
-- Executor (Phase A)
------------------------------------------------------------
local function parse_atom_with_transpose(atom)
  atom = strip_invisible(atom)
  atom = atom:gsub("^%s+",""):gsub("%s+$","")
  if atom == ":" or atom == "_" then return {type=atom, tps=0, rep=1} end
  local core, rep = atom:match("^(.-)%*(%d+)$")
  core, rep = core or atom, tonumber(rep or "1")
  local xsign, xnum = core:match("^x([+-])(%d+)$")
  if core=="x" or xsign then
    local tps = xsign and ((xsign=="-" and -tonumber(xnum) or tonumber(xnum))) or 0
    return {type="x", tps=tps, rep=rep}
  end
  local note, nsign, nnum = core:match("^([a-gA-G][b#]?%-?%d+)([+-])?(%d*)$")
  if note then
    local tps = (nsign and nnum~="") and ((nsign=="-" and -tonumber(nnum) or tonumber(nnum))) or 0
    return {type="note", base=note, tps=tps, rep=rep}
  end
  return {type="?", tps=0, rep=rep}
end

local function make_executor(take, default_pitch, mode, recorder, trace)
  local function dlog(fmt, ...) if trace then logln(string.format(fmt, ...)) end end
  local function rec_emit(voice,pitch,sQN,eQN) if recorder then recorder(voice,pitch,sQN,eQN) end end

  local last_voices = {}
  local voice_current = {}
  local S_anchor = nil

  -- PATCH 1: record on start in PLAN mode so bin 01 is captured
  local function start_voice(i,pitch,sQN,eQN)
    voice_current[i]={pitch=pitch,startQN=sQN,endQN=eQN}
    if mode=="plan" then rec_emit(i, pitch, sQN, eQN) end
  end
  local function flush_voice(i)
    local blk=voice_current[i]; if blk then
      if mode=="plan" then dlog("PLAN close v%d %d %.3f→%.3f", i, blk.pitch, blk.startQN, blk.endQN) end
      if mode=="write" then insert_notes(take,{blk.pitch},blk.startQN,blk.endQN,96) else rec_emit(i,blk.pitch,blk.startQN,blk.endQN) end
      voice_current[i]=nil
    end
  end
  local function flush_all() for i,_ in pairs(voice_current) do flush_voice(i) end end
  local function extend_all(eQN) for _,blk in pairs(voice_current) do blk.endQN=eQN end end
  local function set_last_from_array(arr) for i=1, math.max(#last_voices,#arr) do last_voices[i]=arr[i] end end

  local exec_node

  local function exec_with_mod(node, sQN, eQN, tp)
    if type(node)=="table" and node.kind=="mod" then
      local ntp = (tp or 0) + (node.transpose or 0)
      local N = math.max(1, node.repeat_n or 1)
      local slice=(eQN - sQN)/N
      for i=1,N do local ss=sQN+(i-1)*slice; local ee=ss+slice; exec_with_mod(node.inner, ss, ee, ntp) end
      return
    end
    exec_node(node, sQN, eQN, tp or 0)
  end

  exec_node = function(tok, sQN, eQN, tp)
    tp = tp or 0

    -- STACK
    if type(tok)=="table" and tok.kind=="stack" then
      local entries = tok.entries
      local new_last = {}
      local snaps = {}
      local any_emit = false

      for i,raw in ipairs(entries) do
        local a = parse_atom_with_transpose(raw)
        if a.type == ":" then
          flush_voice(i); new_last[i]=nil
        elseif a.type == "_" then
          if voice_current[i] then voice_current[i].endQN=eQN end
          if last_voices[i] then new_last[i]=last_voices[i] end
        elseif a.type == "note" then
          local m = note_to_midi(a.base)
          if m then
            flush_voice(i)
            local pitch = m + tp + a.tps
            start_voice(i,pitch,sQN,eQN)
            new_last[i] = pitch
            snaps[#snaps+1] = m
            any_emit = true
          end
        elseif a.type == "x" then
          flush_voice(i)
          local prev = last_voices[i]
          if prev then
            local pitch = prev + tp + a.tps
            start_voice(i,pitch,sQN,eQN)
            new_last[i] = prev
            any_emit = true
          else
            new_last[i]=nil
          end
        else
          flush_voice(i); new_last[i]=nil
        end
      end

      for i=#entries+1, math.max(#last_voices,#entries) do flush_voice(i); new_last[i]=nil end
      set_last_from_array(new_last)

      -- PATCH 2: always (re)build S_anchor from explicit stack notes
      if any_emit then
        local tmp = {}
        for _,p in ipairs(snaps) do tmp[#tmp+1] = p end
        if #tmp == 0 then
          for _,p in ipairs(last_voices) do if p then tmp[#tmp+1] = p end end
        end
        S_anchor = (#tmp > 0) and tmp or {60}
      end
      return
    end

    -- GROUP
    if type(tok)=="table" and tok.kind=="group" then
      local N = math.max(1, #tok.entries)
      local subLen=(eQN - sQN)/N
      for i,sub in ipairs(tok.entries) do local ss=sQN+(i-1)*subLen; local ee=ss+subLen; exec_with_mod(sub, ss, ee, tp) end
      return
    end

    -- ATOMS
    if type(tok)=="string" then
      local a = parse_atom_with_transpose(tok)

      if a.type == ":" then
        flush_all()

      elseif a.type == "_" then
        extend_all(eQN)

      elseif a.type == "note" then
        local m = note_to_midi(a.base)
        if m then
          flush_all()
          local pitch = m + tp + a.tps
          start_voice(1,pitch,sQN,eQN)
          S_anchor = { m }   -- store untransposed source
          last_voices[1]=pitch
          for i=2,#last_voices do last_voices[i]=nil end
        end

      elseif a.type == "x" then
        -- PATCH 3: replay ALL pitches in anchor
        local src = S_anchor
        if not src or #src == 0 then src = { 60 } end
        flush_all()
        for vi,p in ipairs(src) do
          local pitch = p + tp + a.tps
          start_voice(vi, pitch, sQN, eQN)
          last_voices[vi] = pitch
        end
        for i=#src+1, #last_voices do last_voices[i]=nil end
      end
      return
    end
  end

  return {
    run = function(tok, sQN, eQN) exec_with_mod(tok, sQN, eQN, 0) end,
    flush = function()
      for i,_ in pairs(voice_current) do
        local blk=voice_current[i]
        if blk then
          if mode=="write" then insert_notes(take,{blk.pitch},blk.startQN,blk.endQN,96) else rec_emit(i,blk.pitch,blk.startQN,blk.endQN) end
          voice_current[i]=nil
        end
      end
    end
  }
end

------------------------------------------------------------
-- Process notation (PLAN optional, WRITE, SCAN optional)
------------------------------------------------------------
local function process_notation_step24(take, name)
  local flags = parse_flags(name)
  local stepQN_opt, _, body_clean = parse_step_header(name)
  local tokens = tokenize(body_clean)

  local stepQN = compute_step_qn_or_fallback(take, stepQN_opt, #tokens)
  local _,_,itemStartQN = get_item_pos_info(take)
  local default_pitch = 60
  local eps_qn = compute_eps_qn(take)

  local bins = nil
  if flags.debug then
    clog_reset(flags.cap)
    logln(string.format("[DEBUG] name='%s'", name))
    logln(string.format("[PARSE] stepLen=%s steps=%d", fmt_qn(stepQN), #tokens))
    if flags.full then
      local function ts(t)
        if type(t)=="string" then return t
        elseif t.kind=="stack" then return "stack["..table.concat(t.entries," ").."]"
        elseif t.kind=="group" then local xs={}; for _,u in ipairs(t.entries) do xs[#xs+1]=ts(u) end; return "group("..table.concat(xs," ")..")"
        elseif t.kind=="mod" then return "mod("..ts(t.inner).." tp="..tostring(t.transpose or 0).." rep="..tostring(t.repeat_n or 1)..")"
        end
        return "?"
      end
      local xs={}; for _,t in ipairs(tokens) do xs[#xs+1]=ts(t) end
      logln("[TOKENS] "..table.concat(xs,"  "))
    end

    bins = {}
    for k, tok in ipairs(tokens) do
      local sQN = itemStartQN + (k-1)*stepQN; local eQN = sQN + stepQN
      collect_leaf_bins(tok, sQN, eQN, bins)
    end
    if flags.trace then
      logln("[BINS]"); for i,bb in ipairs(bins) do logln(string.format("  %02d: %.6f→%.6f", i, bb.s or -1, bb.e or -1)) end
    end

    -- PLAN pass
    do
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
          if flags.trace then logln(string.format("REC bin %02d v%d %d %.3f→%.3f", best_idx, voice, pitch, sQN, eQN)) end
        end
      end
      local ex = make_executor(take, default_pitch, "plan", recorder, flags.trace)
      for k, tok in ipairs(tokens) do
        local sQN = itemStartQN + (k-1)*stepQN; local eQN = sQN + stepQN
        ex.run(tok, sQN, eQN)
      end
      ex.flush()  -- ensure final PLAN events are recorded
      -- Build PLAN rows from trace
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
            local snap=copy_row(bb.plan)
            logln(string.format("  bin %02d  %.3f→%.3f  %s", i, bb.s, bb.e, fmt_voice_row(snap, flags.notes)))
            prev=snap
          end
        end
      end
    end
  end

  -- WRITE pass
  clear_take(take)
  do
    local ex = make_executor(take, default_pitch, "write", nil, false)
    for k, tok in ipairs(tokens) do
      local sQN = itemStartQN + (k-1)*stepQN; local eQN = sQN + stepQN
      ex.run(tok, sQN, eQN)
    end
    ex.flush()
  end
  reaper.MIDI_Sort(take)

  -- SCAN + DIFF
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

------------------------------------------------------------
-- Watcher
------------------------------------------------------------
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

local function scan_once()
  local now=reaper.time_precise(); if now<STATE.next_scan then return end; STATE.next_scan=now+STATE.interval
  if not __BOOTED then logln("[CUCO Tidal Notation] Watcher running (v0.8.0-PhaseA)"); __BOOTED=true; seed_cache_once() end
  local proj=0; local item_cnt=reaper.CountMediaItems(proj)
  for i=0,item_cnt-1 do
    local item=reaper.GetMediaItem(proj,i); local take_cnt=reaper.CountTakes(item)
    for t=0,take_cnt-1 do
      local take=reaper.GetTake(item,t)
      if take and reaper.TakeIsMIDI(take) then
        local _,name=reaper.GetSetMediaItemTakeInfo_String(take,"P_NAME","",false); name=name or ""
        local key = take_key(take); local prev=STATE.last_seen[key]
        if prev==nil then STATE.last_seen[key]=name
          if VERBOSE_WATCHER then
            local id=extract_ctn(get_item_notes(item))
            if id then logln(string.format("[NEW-TAKE] cached '%s' origin=%s", name, id)) else logln(string.format("[NEW-TAKE] cached '%s' (no origin)", name)) end
          end
        elseif prev ~= name then
          STATE.last_seen[key]=name
          if name:sub(1,1) ~= "~" then logln(string.format("[SKIP-NOPREFIX] '%s'", name))
          else local ok,err=pcall(handle_trigger,take,name); if not ok then logln("[Watcher Error] "..tostring(err)) end end
        end
      end
    end
  end--[[
  ReaScript Name: CUCO Tidal Notation — v0.8.0 (Phase A)
  Author: curl + ChatGPT
  
  Phase A Scope:
    • New rest token ":" (colon). Hyphen "-" reserved for transpose.
    • Transpose suffix ±N on notes, x, and stacks (groups unchanged in Phase A).
    • x / x±N uses S_anchor (last explicit note/stack outside groups, UNTRANSPOSED). x does not mutate the anchor.
    • Precedence: transpose → repeat (apply transpose before *N subdivisions).
    • Debugger kept as in 0.7.x; wording overhaul shelved.
  ]]--
  
  ------------------------------------------------------------
  -- Config / Globals
  ------------------------------------------------------------
  local PROJ_NS          = "CUCO_TIDAL_NOTATION_ORIGINS"
  local __BOOTED         = false
  local VERBOSE_WATCHER  = false
  
  ------------------------------------------------------------
  -- Console helpers (with cap)
  ------------------------------------------------------------
  local __CAP = 300
  local __LINES = 0
  local function clog_reset(cap) __CAP = math.max(1, cap or 300); __LINES = 0; reaper.ShowConsoleMsg("") end
  local function logln(s) if __LINES < __CAP then reaper.ShowConsoleMsg((s or "").."\n"); __LINES = __LINES + 1 end end
  
  ------------------------------------------------------------
  -- Watcher state
  ------------------------------------------------------------
  local STATE = { last_seen = {}, seeded = false, next_scan = 0.0, interval = 0.20 }
  
  local function take_key(take)
    local item = reaper.GetMediaItemTake_Item(take)
    local _, guid = reaper.GetSetMediaItemInfo_String(item, "GUID", "", false)
    local idx, nt = -1, reaper.CountTakes(item)
    for t=0, nt-1 do if reaper.GetTake(item, t) == take then idx = t; break end end
    return guid.."::"..tostring(idx), item
  end
  
  ------------------------------------------------------------
  -- Item notes helpers (CTN origin tag)
  ------------------------------------------------------------
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
  
  ------------------------------------------------------------
  -- Project ExtState (committed name per origin)
  ------------------------------------------------------------
  local function get_committed_name(origin_id) local ret,val=reaper.GetProjExtState(0,PROJ_NS,origin_id or ""); if ret==0 then return nil end; return (val~="" and val) or nil end
  local function set_committed_name(origin_id, name) reaper.SetProjExtState(0, PROJ_NS, origin_id or "", name or "") end
  
  ------------------------------------------------------------
  -- Music utils + normalization
  ------------------------------------------------------------
  local PC_BASE = {c=0,d=2,e=4,f=5,g=7,a=9,b=11}
  local PC_NAME = {[0]="c",[1]="c#",[2]="d",[3]="d#",[4]="e",[5]="f",[6]="f#",[7]="g",[8]="g#",[9]="a",[10]="a#",[11]="b"}
  
  local function trim(s) s = s or ""; s = s:gsub("^%s+", ""):gsub("%s+$",""); return s end
  
  -- Strip hidden/invisible characters that break parsing (BOM, ZWSP, NBSP)
  local function strip_invisible(s)
    s = s or ""
    s = s:gsub("\239\187\191", "") -- BOM
    s = s:gsub("\226\128\139", "") -- ZWSP
    s = s:gsub("\226\128\140", "") -- ZWNJ
    s = s:gsub("\226\128\141", "") -- WJ
    s = s:gsub("\194\160", " ")    -- NBSP→space
    return s
  end
  
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
  
  ------------------------------------------------------------
  -- Flags + header parsing
  ------------------------------------------------------------
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
    name = strip_invisible(name)
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
    body = strip_invisible(body)
    body = trim(body); if body:sub(1,1)=="~" then body=body:sub(2) end
    local body_clean = body:gsub("%s//.*$", "")
    body_clean = strip_invisible(body_clean)
    return stepQN, body, trim(body_clean)
  end
  
  ------------------------------------------------------------
  -- Robust tokenizer (split on spaces outside containers)
  ------------------------------------------------------------
  local function split_top_level(body)
    local toks, buf = {}, {}
    local depth_sq, depth_par = 0, 0
    local i, n = 1, #body
    local function push_buf()
      if #buf > 0 then
        toks[#toks+1] = table.concat(buf)
        buf = {}
      end
    end
    while i <= n do
      local ch = body:sub(i,i)
      if ch == "[" then depth_sq = depth_sq + 1; buf[#buf+1]=ch
      elseif ch == "]" then depth_sq = math.max(0, depth_sq - 1); buf[#buf+1]=ch
      elseif ch == "(" then depth_par = depth_par + 1; buf[#buf+1]=ch
      elseif ch == ")" then depth_par = math.max(0, depth_par - 1); buf[#buf+1]=ch
      elseif ch:match("%s") and depth_sq==0 and depth_par==0 then
        push_buf()
      else
        buf[#buf+1]=ch
      end
      i = i + 1
    end
    push_buf()
    return toks
  end
  
  local function split_inner_atoms(inner)
    local out = {}
    inner = strip_invisible(inner)
    for part in inner:gmatch("%S+") do out[#out+1] = part end
    return out
  end
  
  local function parse_top_token(tok)
    tok = strip_invisible(tok)
    if tok:sub(1,1) == "[" then
      local inner, rest = tok:match("^%[(.*)%](.*)$")
      inner = inner or ""
      local node = { kind="stack", entries = split_inner_atoms(trim(inner)) }
      local tp, tail = nil, rest or ""
      local sign, num, after = tail:match("^%s*([%+%-])(%d+)(.*)$")
      if sign and num then tp = (sign=="-" and -tonumber(num) or tonumber(num)); tail = after or "" end
      local rep = nil; local repnum = tail:match("^%s*%*(%d+)%s*$")
      if repnum then rep = math.max(1, tonumber(repnum) or 1) end
      if tp or rep then return { kind="mod", transpose=tp, repeat_n=rep, inner=node } end
      return node
    end
    if tok:sub(1,1) == "(" then
      local inner, rest = tok:match("^%((.*)%)%s*(.*)$")
      inner = inner or ""
      local node = { kind="group", entries = tokenize(trim(inner)) }
      local rep = nil; local repnum = rest:match("^%*%s*(%d+)%s*$")
      if repnum then return { kind="mod", transpose=nil, repeat_n=math.max(1, tonumber(repnum) or 1), inner=node } end
      return node
    end
    return tok
  end
  
  function tokenize(body_clean)
    body_clean = strip_invisible(body_clean)
    local raw = split_top_level(body_clean)
    local ast = {}
    for _,tok in ipairs(raw) do
      tok = trim(strip_invisible(tok))
      if tok ~= "" then ast[#ast+1] = parse_top_token(tok) end
    end
    return ast
  end
  
  ------------------------------------------------------------
  -- MIDI helpers
  ------------------------------------------------------------
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
  local function compute_step_qn_or_fallback(take, stepQN_opt, step_count)
    if stepQN_opt then return stepQN_opt end
    step_count=math.max(1, tonumber(step_count) or 1)
    local _,_,sQN,eQN=get_item_pos_info(take); local itemLenQN=math.max(1e-6, eQN-sQN)
    return itemLenQN/step_count
  end
  
  ------------------------------------------------------------
  -- PLAN helpers
  ------------------------------------------------------------
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
    elseif type(token)=="table" and token.kind=="mod" then
      collect_leaf_bins(token.inner, sQN, eQN, out_bins)
    else
      out_bins[#out_bins+1] = { s=sQN, e=eQN, plan={}, actual={}, trace={} }
    end
  end
  
  ------------------------------------------------------------
  -- SCAN (rebuild)
  ------------------------------------------------------------
  local function scan_actual_bins_rebuild(take, bins, flags, eps_qn)
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
      local bp = b and a.pitch or -1
      if ap ~= bp then return ap < bp end
      local as = (a and a.s) or fallback_s or 0
      local bs = (b and b.s) or fallback_s or 0
      if math.abs(as - bs) > 1e-9 then return as < bs end
      local ae = (a and a.e) or fallback_e or as
      local be = (b and b.e) or fallback_e or bs
      return ae < be
    end)
  end
  
  ------------------------------------------------------------
  -- Executor (Phase A)
  ------------------------------------------------------------
  local function parse_atom_with_transpose(atom)
    atom = strip_invisible(atom)
    atom = atom:gsub("^%s+",""):gsub("%s+$","")
    if atom == ":" or atom == "_" then return {type=atom, tps=0, rep=1} end
    local core, rep = atom:match("^(.-)%*(%d+)$")
    core, rep = core or atom, tonumber(rep or "1")
    local xsign, xnum = core:match("^x([+-])(%d+)$")
    if core=="x" or xsign then
      local tps = xsign and ((xsign=="-" and -tonumber(xnum) or tonumber(xnum))) or 0
      return {type="x", tps=tps, rep=rep}
    end
    local note, nsign, nnum = core:match("^([a-gA-G][b#]?%-?%d+)([+-])?(%d*)$")
    if note then
      local tps = (nsign and nnum~="") and ((nsign=="-" and -tonumber(nnum) or tonumber(nnum))) or 0
      return {type="note", base=note, tps=tps, rep=rep}
    end
    return {type="?", tps=0, rep=rep}
  end
  
  local function make_executor(take, default_pitch, mode, recorder, trace)
    local function dlog(fmt, ...) if trace then logln(string.format(fmt, ...)) end end
    local function rec_emit(voice,pitch,sQN,eQN) if recorder then recorder(voice,pitch,sQN,eQN) end end
  
    local last_voices = {}
    local voice_current = {}
    local S_anchor = nil
  
    local function start_voice(i,pitch,sQN,eQN)
      voice_current[i]={pitch=pitch,startQN=sQN,endQN=eQN}
      if mode=="plan" then rec_emit(i, pitch, sQN, eQN) end
    end
    local function flush_voice(i)
      local blk=voice_current[i]; if blk then
        if mode=="plan" then dlog("PLAN close v%d %d %.3f→%.3f", i, blk.pitch, blk.startQN, blk.endQN) end
        if mode=="write" then insert_notes(take,{blk.pitch},blk.startQN,blk.endQN,96) else rec_emit(i,blk.pitch,blk.startQN,blk.endQN) end
        voice_current[i]=nil
      end
    end
    local function flush_all() for i,_ in pairs(voice_current) do flush_voice(i) end end
    local function extend_all(eQN) for _,blk in pairs(voice_current) do blk.endQN=eQN end end
    local function set_last_from_array(arr) for i=1, math.max(#last_voices,#arr) do last_voices[i]=arr[i] end end
  
    local exec_node
  
    local function exec_with_mod(node, sQN, eQN, tp)
      if type(node)=="table" and node.kind=="mod" then
        local ntp = (tp or 0) + (node.transpose or 0)
        local N = math.max(1, node.repeat_n or 1)
        local slice=(eQN - sQN)/N
        for i=1,N do local ss=sQN+(i-1)*slice; local ee=ss+slice; exec_with_mod(node.inner, ss, ee, ntp) end
        return
      end
      exec_node(node, sQN, eQN, tp or 0)
    end
  
    exec_node = function(tok, sQN, eQN, tp)
      tp = tp or 0
  
      if type(tok)=="table" and tok.kind=="stack" then
        local entries = tok.entries
        local new_last = {}
        local snaps = {}
        local any_emit = false
  
        for i,raw in ipairs(entries) do
          local a = parse_atom_with_transpose(raw)
          if a.type == ":" then
            flush_voice(i); new_last[i]=nil
          elseif a.type == "_" then
            if voice_current[i] then voice_current[i].endQN=eQN end
            if last_voices[i] then new_last[i]=last_voices[i] end
          elseif a.type == "note" then
            local m = note_to_midi(a.base)
            if m then
              flush_voice(i)
              local pitch = m + tp + a.tps
              start_voice(i,pitch,sQN,eQN)
              new_last[i] = pitch
              snaps[#snaps+1] = m
              any_emit = true
            end
          elseif a.type == "x" then
            flush_voice(i)
            local prev = last_voices[i]
            if prev then
              local pitch = prev + tp + a.tps
              start_voice(i,pitch,sQN,eQN)
              new_last[i] = prev
              any_emit = true
            else
              new_last[i]=nil
            end
          else
            flush_voice(i); new_last[i]=nil
          end
        end
  
        for i=#entries+1, math.max(#last_voices,#entries) do flush_voice(i); new_last[i]=nil end
        set_last_from_array(new_last)
  
        if any_emit then
          local tmp = {}
          for _,p in ipairs(snaps) do tmp[#tmp+1] = p end
          if #tmp == 0 then
            for _,p in ipairs(last_voices) do if p then tmp[#tmp+1] = p end end
          end
          S_anchor = (#tmp > 0) and tmp or {60}
        end
        return
      end
  
      if type(tok)=="table" and tok.kind=="group" then
        local N = math.max(1, #tok.entries)
        local subLen=(eQN - sQN)/N
        for i,sub in ipairs(tok.entries) do local ss=sQN+(i-1)*subLen; local ee=ss+subLen; exec_with_mod(sub, ss, ee, tp) end
        return
      end
  
      if type(tok)=="string" then
        local a = parse_atom_with_transpose(tok)
  
        if a.type == ":" then
          flush_all()
  
        elseif a.type == "_" then
          extend_all(eQN)
  
        elseif a.type == "note" then
          local m = note_to_midi(a.base)
          if m then
            flush_all()
            local pitch = m + tp + a.tps
            start_voice(1,pitch,sQN,eQN)
            S_anchor = { m }
            last_voices[1]=pitch
            for i=2,#last_voices do last_voices[i]=nil end
          end
  
        elseif a.type == "x" then
          local src = S_anchor
          if not src or #src == 0 then src = { 60 } end
          flush_all()
          for vi,p in ipairs(src) do
            local pitch = p + tp + a.tps
            start_voice(vi, pitch, sQN, eQN)
            last_voices[vi] = pitch
          end
          for i=#src+1, #last_voices do last_voices[i]=nil end
        end
        return
      end
    end
  
    return {
      run = function(tok, sQN, eQN) exec_with_mod(tok, sQN, eQN, 0) end,
      flush = function()
        for i,_ in pairs(voice_current) do
          local blk=voice_current[i]
          if blk then
            if mode=="write" then insert_notes(take,{blk.pitch},blk.startQN,blk.endQN,96) else rec_emit(i,blk.pitch,blk.startQN,blk.endQN) end
            voice_current[i]=nil
          end
        end
      end
    }
  end
  
  ------------------------------------------------------------
  -- Process notation (PLAN optional, WRITE, SCAN optional)
  ------------------------------------------------------------
  local function process_notation_step24(take, name)
    local flags = parse_flags(name)
    local stepQN_opt, _, body_clean = parse_step_header(name)
    local tokens = tokenize(body_clean)
  
    local stepQN = compute_step_qn_or_fallback(take, stepQN_opt, #tokens)
    local _,_,itemStartQN = get_item_pos_info(take)
    local default_pitch = 60
    local eps_qn = compute_eps_qn(take)
  
    local bins = nil
    if flags.debug then
      clog_reset(flags.cap)
      logln(string.format("[DEBUG] name='%s'", name))
      logln(string.format("[PARSE] stepLen=%s steps=%d", fmt_qn(stepQN), #tokens))
      if flags.full then
        local function ts(t)
          if type(t)=="string" then return t
          elseif t.kind=="stack" then return "stack["..table.concat(t.entries," ").."]"
          elseif t.kind=="group" then local xs={}; for _,u in ipairs(t.entries) do xs[#xs+1]=ts(u) end; return "group("..table.concat(xs," ")..")"
          elseif t.kind=="mod" then return "mod("..ts(t.inner).." tp="..tostring(t.transpose or 0).." rep="..tostring(t.repeat_n or 1)..")"
          end
          return "?"
        end
        local xs={}; for _,t in ipairs(tokens) do xs[#xs+1]=ts(t) end
        logln("[TOKENS] "..table.concat(xs,"  "))
      end
  
      bins = {}
      for k, tok in ipairs(tokens) do
        local sQN = itemStartQN + (k-1)*stepQN; local eQN = sQN + stepQN
        collect_leaf_bins(tok, sQN, eQN, bins)
      end
      if flags.trace then
        logln("[BINS]"); for i,bb in ipairs(bins) do logln(string.format("  %02d: %.6f→%.6f", i, bb.s or -1, bb.e or -1)) end
      end
  
      -- PLAN pass (execute token 1 explicitly, then the rest)
      do
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
            if flags.trace then logln(string.format("REC bin %02d v%d %d %.3f→%.3f", best_idx, voice, pitch, sQN, eQN)) end
          end
        end
        local ex = make_executor(take, default_pitch, "plan", recorder, flags.trace)
        if #tokens >= 1 then
          local s1 = itemStartQN
          local e1 = s1 + stepQN
          ex.run(tokens[1], s1, e1)
        end
        for k=2, #tokens do
          local sQN = itemStartQN + (k-1)*stepQN; local eQN = sQN + stepQN
          ex.run(tokens[k], sQN, eQN)
        end
        ex.flush()
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
              local snap=copy_row(bb.plan)
              logln(string.format("  bin %02d  %.3f→%.3f  %s", i, bb.s, bb.e, fmt_voice_row(snap, flags.notes)))
              prev=snap
            end
          end
        end
      end
    end
  
    -- WRITE pass (same explicit-first-token trick)
    clear_take(take)
    do
      local ex = make_executor(take, default_pitch, "write", nil, false)
      if #tokens >= 1 then
        local s1 = itemStartQN
        local e1 = s1 + stepQN
        ex.run(tokens[1], s1, e1)
      end
      for k=2, #tokens do
        local sQN = itemStartQN + (k-1)*stepQN; local eQN = sQN + stepQN
        ex.run(tokens[k], sQN, eQN)
      end
      ex.flush()
    end
    reaper.MIDI_Sort(take)
  
    -- SCAN + DIFF
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
  
  ------------------------------------------------------------
  -- Watcher
  ------------------------------------------------------------
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
  
  local function scan_once()
    local now=reaper.time_precise(); if now<STATE.next_scan then return end; STATE.next_scan=now+STATE.interval
    if not __BOOTED then logln("[CUCO Tidal Notation] Watcher running (v0.8.0-PhaseA)"); __BOOTED=true; seed_cache_once() end
    local proj=0; local item_cnt=reaper.CountMediaItems(proj)
    for i=0,item_cnt-1 do
      local item=reaper.GetMediaItem(proj,i); local take_cnt=reaper.CountTakes(item)
      for t=0,take_cnt-1 do
        local take=reaper.GetTake(item,t)
        if take and reaper.TakeIsMIDI(take) then
          local _,name=reaper.GetSetMediaItemTakeInfo_String(take,"P_NAME","",false); name=name or ""
          local key = take_key(take); local prev=STATE.last_seen[key]
          if prev==nil then STATE.last_seen[key]=name
            if VERBOSE_WATCHER then
              local id=extract_ctn(get_item_notes(item))
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
  reaper.Undo_BeginBlock(); main_loop(); reaper.Undo_EndBlock("CUCO Tidal Notation — v0.8.0 (Phase A)", -1)
  
  --[[ ======================================================================
  TEST STRINGS (paste these as take names after installing the script)
  ======================================================================
  
  1) Note + inherit
     ~16 c3 x+2 x-1 : _ x //debug //full //notes
  
  2) Stack anchor + recall
     ~8 [c4 e4] x+5 x //debug //full //notes
  
  3) Stack-level transpose + recall
     ~8 [c4 e4]+12 : x-12 //debug //full //notes
  
  4) Precedence (transpose → repeat)
     ~4 [c4 e4]-12*2 //debug //full //notes
  
  ]]--
end

local function main_loop() local ok,err=pcall(scan_once); if not ok then logln("[Watcher Error] "..tostring(err)) end; reaper.defer(main_loop) end

-- Start
reaper.Undo_BeginBlock(); main_loop(); reaper.Undo_EndBlock("CUCO Tidal Notation — v0.8.0 (Phase A)", -1)

--[[ ======================================================================
TEST STRINGS (paste these as take names after installing the script)
======================================================================

1) Note + inherit
   ~16 c3 x+2 x-1 : _ x //debug //full //notes

2) Stack anchor + recall
   ~8 [c4 e4] x+5 x //debug //full //notes

3) Stack-level transpose + recall
   ~8 [c4 e4]+12 : x-12 //debug //full //notes

4) Precedence (transpose → repeat)
   ~4 [c4 e4]-12*2 //debug //full //notes

]]--
