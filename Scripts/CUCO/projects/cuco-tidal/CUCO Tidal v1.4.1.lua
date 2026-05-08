--[[
ReaScript Name: CUCO Tidal (v1.4.12 — unified master)
Author: curl + ChatGPT

What’s new in 1.4.12
  • Fix: newline literals that caused "unfinished string near '""'" (use "\n").
  • Repeat suffix parsing hardened: captures comma- or space-separated transpositions reliably.
  • Transpose debug: when //log is present, each /…/N suffix logs times/dev/transp.

Carryovers
  • Chords in tokens: c3sus4, a#2m7, f4maj7add9, g3dim, d3aug/e3+, e3m, 5-chords.
  • Inheritance repeats last CHORD (x), not just a single note.
  • Keeps rename‑only behavior across splits/duplicates using TAKE extstate.
  • Live watcher (defer loop).
  • Fixed-grid headers: ~16, ~8t, ~5q, ~7s, ~9n, ~0.5.
  • Slash repeat blocks: "/ … /N[, transp ...]" or "/ … /N, dev=0.2".
  • Fallback (no header): stepQN = itemLenQN / #expandedSteps.
  • Console logger: //log, //log=brief, //log=notes, //cap=N (flags stripped from body).
  • Flags: //go forces rewrite; //pos forces location dump.
  • Symbols: x=inherit, "~"/"-"=rest, "_"=hold placeholder.
]]--

math.randomseed(reaper.time_precise() * 1e6)

--------------------------------------------------------------------------------
-- Small utils
--------------------------------------------------------------------------------
local function trim(s) return (s:gsub("^%s+",""):gsub("%s+$","")) end
local PC_BASE = {c=0,d=2,e=4,f=5,g=7,a=9,b=11}
local PC_NAME = {[0]="c",[1]="c#",[2]="d",[3]="d#",[4]="e",[5]="f",[6]="f#",[7]="g",[8]="g#",[9]="a",[10]="a#",[11]="b"}

local function note_to_midi(note)
  local letter, acc, oct = note:match("^([a-gA-G])([b#]?)(%-?%d+)$")
  if not letter then return nil end
  local pc = PC_BASE[letter:lower()] or 0
  if acc == "#" then pc = pc + 1 elseif acc == "b" then pc = pc - 1 end
  return (tonumber(oct)+1)*12 + pc
end

local function midi_to_note(m)
  local oct = math.floor(m/12) - 1
  local pc  = ((m % 12) + 12) % 12
  return (PC_NAME[pc] or "c")..tostring(oct)
end

-- Chord parsing: expand token like "c3sus4", "a#2m7", "f4maj7add9", "g3dim7", "d3aug"/"e3+", "e3m", "c4"
local function chord_notes_from_token(tok)
  tok = trim(tok or "")
  if tok == "" then return nil end
  if tok == "x" or tok == "_" or tok == "~" or tok == "-" then return nil end

  local root, suffix = tok:match("^([a-gA-G][b#]?%-?%d+)(.*)$")
  if not root then return nil end
  local base = note_to_midi(root)
  if not base then return nil end

  suffix = (suffix or ""):gsub("%s+", ""):lower()
  if suffix == "" then return { base } end

  -- Choose base chord template (intervals in semitones from root)
  local ivals
  if     suffix:find("^mmaj7")             then ivals = {0,3,7,11}
  elseif suffix:find("^maj7")              then ivals = {0,4,7,11}
  elseif suffix:find("^dim7")              then ivals = {0,3,6,9}
  elseif suffix:find("^m7") or suffix:find("^min7") then ivals = {0,3,7,10}
  elseif suffix:find("^7")                 then ivals = {0,4,7,10}
  elseif suffix:find("^dim") or suffix:find("^°")   then ivals = {0,3,6}
  elseif suffix:find("^aug") or suffix:find("^%+")  then ivals = {0,4,8}
  elseif suffix:find("^m") or suffix:find("^min")   then ivals = {0,3,7}
  elseif suffix:find("^5")                 then ivals = {0,7}
  elseif suffix:find("^sus4")              then ivals = {0,5,7}
  elseif suffix:find("^sus2")              then ivals = {0,2,7}
  else                                            ivals = {0,4,7}
  end

  -- Extensions / adds
  local function add_iv(v)
    for _,x in ipairs(ivals) do if x == v then return end end
    ivals[#ivals+1] = v
  end
  if suffix:find("6") and not suffix:find("16") then add_iv(9) end
  if suffix:find("add2") or suffix:find("add9") then add_iv(14) end
  if suffix:find("9") and not suffix:find("add9") then add_iv(14) end
  if suffix:find("11") then add_iv(17) end
  if suffix:find("13") then add_iv(21) end

  local out = {}
  for _,iv in ipairs(ivals) do out[#out+1] = base + iv end
  return out
end

--------------------------------------------------------------------------------
-- Logger flags
--------------------------------------------------------------------------------
local __LOG_COUNT, __LOG_CAP = 0, 500
local function _has_flag(name, key) return (name or ""):find("//%s*" .. key) ~= nil end
local function log_enabled(name) return _has_flag(name, "log") end
local function log_mode(name)
  local m = (name or ""):match("//%s*log%s*=%s*([%w_]+)")
  if m == "brief" or m == "notes" then return m end
  return "full"
end
local function logcap(name)
  local c = tonumber((name or ""):match("//%s*cap%s*=%s*(%d+)") or "")
  return c and math.max(1, c) or 500
end
local function pos_enabled(name) return _has_flag(name, "pos") end
local function force_go(name) return (name or ""):find("//%s*go") ~= nil end
local function clog_reset(cap) __LOG_COUNT=0; __LOG_CAP=cap or 500; reaper.ShowConsoleMsg("") end
local function clog(...)
  if __LOG_COUNT < __LOG_CAP then
    reaper.ShowConsoleMsg(table.concat({...}, " ").."\n")
    __LOG_COUNT=__LOG_COUNT+1
  end
end
local function fmt_qn(x) return string.format("%.6f QN", x) end
local function fmt_ppq(x) return string.format("%.2f PPQ", x) end

--------------------------------------------------------------------------------
-- Step-size header (~16, ~8t, ~5q, ~7s, ~9n, ~0.5)
--------------------------------------------------------------------------------
local function parse_step_header(name)
  local stepQN, body = nil, name
  local hdr = name:match("^~%s*([%d%.]+%s*[tqsn]?)")
  if hdr then
    local num  = hdr:match("^[%d%.]+")
    local flag = hdr:match("[tqsn]$")
    local denom = tonumber(num)
    if denom and denom > 0 then
      stepQN = 4.0 / denom -- quarter=1.0 QN
      if flag == "t" then stepQN = stepQN * (2/3)
      elseif flag == "q" then stepQN = stepQN * (4/5)
      elseif flag == "s" then stepQN = stepQN * (4/7)
      elseif flag == "n" then stepQN = stepQN * (8/9)
      end
    end
    body = name:sub(#hdr + 2):gsub("^%s+","")
  end
  return stepQN, body
end

--------------------------------------------------------------------------------
-- Tokenizer ([], (), /.../N[, args]), rest "~" or "-", hold "_", inherit "x"
--------------------------------------------------------------------------------
local function read_bracketed(body, i, open, close)
  local n, depth, start = #body, 0, i
  while i <= n do
    local ch = body:sub(i,i)
    if ch == open then depth = depth + 1
    elseif ch == close then
      depth = depth - 1
      if depth == 0 then
        local seg = body:sub(start, i)
        i = i + 1
        return seg, i
      end
    end
    i = i + 1
  end
  return body:sub(start), i
end

-- Read "/ ... /" and capture optional suffix written as "N[, args]" or "/N[, args]"
-- Hardened to greedily consume trailing signed integers separated by commas and/or spaces, e.g. "/4, +0 +2 -1 +0" or "/4, +0, +2, -1, +0"
local function read_slash_group(body, i)
  local n = #body
  local start = i
  i = i + 1
  while i <= n and body:sub(i,i):match("%s") do i = i + 1 end

  local close_pos = body:find("/", i, true)
  if not close_pos then
    return body:sub(start), nil, n+1
  end
  local seg = body:sub(start, close_pos)
  local ni  = close_pos + 1

  -- Move to first non-space after closing '/'
  local j = ni
  while j <= n and body:sub(j,j):match("%s") do j = j + 1 end

  local suffix = nil
  local tail = body:sub(j)
  -- Expect times (digits) first
  local times = tail:match("^(%d+)")
  if times then
    suffix = times
    local p = #times + 1
    -- Greedily eat any sequence of [spaces or commas] + signed int
    while true do
      local rest = tail:sub(p)
      if rest == "" then break end
      local full, signed = rest:match("^(%s*[, ]%s*([%+%-]?%d+))")
      if not full then break end
      suffix = suffix .. " " .. signed
      p = p + #full
    end
    ni = j + p - 1
  end

  return seg, suffix, ni
end

local function tokenize_stream(text)
  local tokens = {}
  local i, n = 1, #text
  while i <= n do
    local ch = text:sub(i,i)
    if ch:match("%s") then
      i = i + 1
    elseif ch == "[" then
      local seg, ni = read_bracketed(text, i, "[", "]")
      tokens[#tokens+1] = seg
      i = ni
    elseif ch == "(" then
      local seg, ni = read_bracketed(text, i, "(", ")")
      tokens[#tokens+1] = seg
      i = ni
    elseif ch == "/" then
      local seg, suffix, ni = read_slash_group(text, i)
      tokens[#tokens+1] = { kind="repeat_group", seg=seg, suffix=suffix }
      i = ni
    else
      local j = i
      while j <= n do
        local c = text:sub(j,j)
        if c:match("%s") or c=="[" or c=="]" or c=="(" or c==")" or c=="/" then break end
        j = j + 1
      end
      tokens[#tokens+1] = text:sub(i, j-1)
      i = j
    end
  end
  return tokens
end

--------------------------------------------------------------------------------
-- Repeat expansion
--------------------------------------------------------------------------------
local function parse_repeat_suffix(suf)
  if not suf then return {times=1} end
  local times = tonumber(suf:match("^(%d+)")) or 1
  local rest  = suf:gsub("^%d+%s*,?%s*", "")
  local t = { times = math.max(1, times) }
  if rest ~= "" then
    local dev = rest:match("dev%s*=%s*([%d%.]+)")
    if dev then
      t.dev = math.max(0, math.min(1, tonumber(dev) or 0))
    else
      local offs = {}
      for num in rest:gmatch("([%+%-]?%d+)") do offs[#offs+1] = tonumber(num) end
      if #offs > 0 then t.transp = offs end
    end
  end
  return t
end

local function transpose_token(tok, semis)
  if not semis or semis == 0 then return tok end
  if tok == "~" or tok == "-" or tok == "_" or tok == "x" then return tok end
  if tok:sub(1,1) == "[" then
    local inside = tok:sub(2,-2)
    local out = {}
    for v in inside:gmatch("([^,]+)") do
      v = trim(v)
      if v == "x" or v == "_" or v == "~" or v == "-" then
        out[#out+1] = v
      else
        local note, rest = v:match("^([a-gA-G][b#]?%-?%d+)(.*)")
        if note then
          local midi = note_to_midi(note)
          if midi then out[#out+1] = midi_to_note(midi + semis)..(rest or "") else out[#out+1] = v end
        else
          out[#out+1] = v
        end
      end
    end
    return "["..table.concat(out, ",").."]"
  else
    local note, rest = tok:match("^([a-gA-G][b#]?%-?%d+)(.*)")
    if note then
      local midi = note_to_midi(note)
      if midi then return midi_to_note(midi + semis)..(rest or "") end
    end
    return tok
  end
end

local function deviate_token(tok, p)
  if not p or p <= 0 then return tok end
  if math.random() >= p then return tok end
  if tok == "_" then return "~"
  elseif tok == "~" or tok == "-" then return "_"
  else
    if tok:match("^[a-gA-G][b#]?%-?%d+[%a]") or tok:match("^[a-gA-G][b#]?%a") then
      if (not tok:find("/%d")) and (not tok:find("/[a-gA-G]")) then
        return tok.."/1"
      end
    end
  end
  return tok
end

-- Global logging switches set per processed take name
_G.__CUCO_LOG = false
_G.__CUCO_LOG_MODE = "full"

local function expand_repeat_group(node, tokenize_func)
  local body = node.seg:match("^/%s*(.-)%s*/$") or ""
  local cfg  = parse_repeat_suffix(node.suffix)
  local times = cfg.times or 1

  if _G.__CUCO_LOG and _G.__CUCO_LOG_MODE ~= "notes" then
    local tr = ""
    if cfg.transp and #cfg.transp>0 then
      for i,v in ipairs(cfg.transp) do tr = tr .. (i==1 and tostring(v) or (", "..tostring(v))) end
    end
    clog(string.format("[repeat] suffix='%s'  times=%d  dev=%s  transp=[%s]", tostring(node.suffix), times, tostring(cfg.dev), tr))
  end

  local inner = tokenize_func(body)
  local out = {}
  for rep = 1, times do
    local semis = nil
    if cfg.transp and cfg.transp[rep] then semis = cfg.transp[rep]
    elseif cfg.transp and #cfg.transp > 0 then semis = cfg.transp[#cfg.transp] end
    for _,t in ipairs(inner) do
      if type(t) == "table" and t.kind == "repeat_group" then
        local nested = expand_repeat_group(t, tokenize_func)
        for _,nn in ipairs(nested) do
          nn = transpose_token(nn, semis); nn = deviate_token(nn, cfg.dev)
          out[#out+1] = nn
        end
      else
        local s = (type(t) == "string") and t or (t.text or "")
        s = transpose_token(s, semis); s = deviate_token(s, cfg.dev)
        out[#out+1] = s
      end
    end
  end
  return out
end

local function expand_tokens(tokens)
  local out = {}
  for _,t in ipairs(tokens) do
    if type(t) == "table" and t.kind == "repeat_group" then
      local ex = expand_repeat_group(t, tokenize_stream)
      for _,u in ipairs(ex) do out[#out+1] = u end
    else
      out[#out+1] = t
    end
  end
  return out
end

--------------------------------------------------------------------------------
-- Rename-only fingerprint (TAKE extstate)
--------------------------------------------------------------------------------
local EXT_KEY = "P_EXT:CUCO_TIDAL_KEY"
local function make_pattern_key(stepQN, body_clean)
  local hdr = stepQN and string.format("H=%.6f;", stepQN) or "H=nil;"
  return hdr .. "B=" .. body_clean
end
local function get_ext_key(take)
  local _, val = reaper.GetSetMediaItemTakeInfo_String(take, EXT_KEY, "", false)
  if val == "" then return nil end
  return val
end
local function set_ext_key(take, key)
  reaper.GetSetMediaItemTakeInfo_String(take, EXT_KEY, key or "", true)
end
local function take_has_any_events(take)
  local _, n, c, t = reaper.MIDI_CountEvts(take)
  return (n > 0) or (c > 0) or (t > 0)
end

--------------------------------------------------------------------------------
-- MIDI write + timing + debug
--------------------------------------------------------------------------------
local function clear_take(take)
  reaper.MIDI_DisableSort(take)
  reaper.MIDI_SetAllEvts(take, "") -- nuke everything
  reaper.MIDI_Sort(take)
end

local function item_pos_info(take)
  local item = reaper.GetMediaItemTake_Item(take)
  local pos  = reaper.GetMediaItemInfo_Value(item, "D_POSITION")
  local len  = reaper.GetMediaItemInfo_Value(item, "D_LENGTH")
  local startQN = reaper.TimeMap2_timeToQN(0, pos)
  local endQN   = reaper.TimeMap2_timeToQN(0, pos + len)
  return pos, len, startQN, endQN
end

local function note_span_info(take)
  local _, noteCount = reaper.MIDI_CountEvts(take)
  if noteCount == 0 then return nil end
  local firstPPQ, lastPPQ = nil, nil
  for i=0, noteCount-1 do
    local ok, sel, muted, startppq, endppq = reaper.MIDI_GetNote(take, i)
    if ok then
      if not firstPPQ or startppq < firstPPQ then firstPPQ = startppq end
      if not lastPPQ  or endppq   > lastPPQ  then lastPPQ  = endppq  end
    end
  end
  if not firstPPQ then return nil end
  local firstQN = reaper.MIDI_GetProjQNFromPPQPos(take, firstPPQ)
  local lastQN  = reaper.MIDI_GetProjQNFromPPQPos(take, lastPPQ)
  return {firstPPQ=firstPPQ, lastPPQ=lastPPQ, firstQN=firstQN, lastQN=lastQN}
end

local function debug_log_locations(take, stepQN, stepCount, name_for_log)
  local wantPos = pos_enabled(name_for_log or "") or log_enabled(name_for_log or "")
  if not wantPos then return end
  local pos, len, sQN, eQN = item_pos_info(take)
  local steps_str   = (stepCount and tostring(stepCount)) or "?"
  local steplen_str = (stepQN and fmt_qn(stepQN)) or "?"
  clog(string.format("[item] pos=%.6fs len=%.6fs  start=%s end=%s  steps=%s stepLen=%s",
    pos, len, fmt_qn(sQN), fmt_qn(eQN), steps_str, steplen_str))
  local span = note_span_info(take)
  if span then
    clog(string.format("[notes] span: %s → %s  (%s → %s)",
      fmt_ppq(span.firstPPQ), fmt_ppq(span.lastPPQ), fmt_qn(span.firstQN), fmt_qn(span.lastQN)))
  else
    clog("[notes] span: (no notes)")
  end
end

local function qn_time_helpers(take)
  local item = reaper.GetMediaItemTake_Item(take)
  local pos  = reaper.GetMediaItemInfo_Value(item, "D_POSITION")
  local itemStartQN = reaper.TimeMap2_timeToQN(0, pos)
  local function qnToPPQ(qn) return reaper.MIDI_GetPPQPosFromProjQN(take, qn) end
  return itemStartQN, qnToPPQ
end

local function compute_fallback_stepQN(take, step_count)
  step_count = math.max(1, tonumber(step_count) or 1)
  local item = reaper.GetMediaItemTake_Item(take)
  local pos  = reaper.GetMediaItemInfo_Value(item, "D_POSITION")
  local len  = reaper.GetMediaItemInfo_Value(item, "D_LENGTH")
  local startQN = reaper.TimeMap2_timeToQN(0, pos)
  local endQN   = reaper.TimeMap2_timeToQN(0, pos + len)
  local itemLenQN = math.max(0.000001, endQN - startQN)
  return itemLenQN / step_count
end

local function write_pattern_to_take(take, flat_tokens, stepQN_opt, name_for_log, body_clean)
  local itemStartQN, qnToPPQ = qn_time_helpers(take)
  local stepQN = stepQN_opt or 1.0
  local toPPQ = function(qn) return reaper.MIDI_GetPPQPosFromProjQN(take, qn) end
  local mode = log_mode(name_for_log or "")
  local wantLog = log_enabled(name_for_log or "")
  local notes_only = (mode == "notes")

  reaper.MIDI_DisableSort(take)

  local last_notes = { note_to_midi("c4") or 60 }

  local function log_step(k, tok, sQN, eQN)
    if wantLog and not notes_only then
      clog(string.format("[STEP %03d] %-14s  start=%s  end=%s  len=%s", k, tostring(tok), fmt_qn(sQN), fmt_qn(eQN), fmt_qn(stepQN)))
    end
  end
  local function log_note(midi, vel, sPPQ, ePPQ)
    if not wantLog then return end
    clog(string.format("  note  %-4s (MIDI=%3d)  vel=%3d  %s → %s  dur=%s",
      midi_to_note(midi), midi, vel or 96, fmt_ppq(sPPQ), fmt_ppq(ePPQ),
      fmt_qn(reaper.MIDI_GetProjQNFromPPQPos(take, ePPQ) - reaper.MIDI_GetProjQNFromPPQPos(take, sPPQ))))
  end
  local function write_notes(notes, startQN, endQN, vel)
    local sPPQ, ePPQ = toPPQ(startQN), toPPQ(endQN)
    for _,m in ipairs(notes) do
      reaper.MIDI_InsertNote(take, false, false, sPPQ, ePPQ, 0, m, vel or 96, false)
      log_note(m, vel, sPPQ, ePPQ)
    end
  end

  for k, tok in ipairs(flat_tokens) do
    local sQN = itemStartQN + (k-1)*stepQN
    local eQN = sQN + stepQN

    log_step(k, tok, sQN, eQN)

    local token = tok
    if token:sub(1,1) == "[" and token:sub(-1) == "]" then
      local inner = token:sub(2,-2)
      for v in inner:gmatch("([^,]+)") do
        v = trim(v)
        if v == "x" then
          write_notes(last_notes, sQN, eQN, 96)
        elseif v ~= "_" and v ~= "~" and v ~= "-" then
          local notes = chord_notes_from_token(v)
          if notes and #notes > 0 then last_notes = notes; write_notes(notes, sQN, eQN, 96) end
        end
      end

    elseif token:sub(1,1) == "(" and token:sub(-1) == ")" then
      local inner = token:sub(2,-2)
      local parts = {}
      for v in inner:gmatch("([^,]+)") do parts[#parts+1] = trim(v) end
      local N = math.max(1, #parts)
      local subLen = stepQN / N
      for i,part in ipairs(parts) do
        local sQNsub = sQN + (i-1)*subLen
        local eQNsub = sQNsub + subLen
        if part == "x" then
          write_notes(last_notes, sQNsub, eQNsub, 96)
        elseif part ~= "~" and part ~= "-" and part ~= "_" then
          local notes = chord_notes_from_token(part)
          if notes and #notes > 0 then last_notes = notes; write_notes(notes, sQNsub, eQNsub, 96) end
        end
      end

    else
      if token == "~" or token == "-" then
        -- rest
      elseif token == "_" then
        -- hold (unimplemented)
      elseif token == "x" then
        write_notes(last_notes, sQN, eQN, 96)
      else
        local notes = chord_notes_from_token(token)
        if notes and #notes > 0 then last_notes = notes; write_notes(notes, sQN, eQN, 96) end
      end
    end
  end

  -- persist fingerprint (survives splits/dupes)
  set_ext_key(take, make_pattern_key(stepQN_opt, body_clean))

  reaper.MIDI_Sort(take)

  -- Post-write location dump (only after actual write)
  debug_log_locations(take, stepQN, #flat_tokens, name_for_log)
end

--------------------------------------------------------------------------------
-- Pipeline
--------------------------------------------------------------------------------
local function strip_flags_from_body(body)
  return (body:gsub("%s//.*$", "")) -- strip trailing //flags
end

local function process_name(take, name)
  local wantLog = log_enabled(name)
  local mode    = log_mode(name)
  local cap     = logcap(name)

  -- set global logging switches for nested helpers
  _G.__CUCO_LOG = wantLog
  _G.__CUCO_LOG_MODE = mode

  if wantLog then
    clog_reset(cap)
    clog("[CUCO Tidal] ===============================================")
    clog("[CUCO Tidal] take name: ", name)
  end

  local stepQN, body = parse_step_header(name)
  body = body or name
  if body:sub(1,1) == "~" then body = body:sub(2) end
  body = trim(body)
  local body_clean = strip_flags_from_body(body)

  -- Rename-only gate
  if not force_go(name) then
    local want_key = make_pattern_key(stepQN, body_clean)
    local have_key = get_ext_key(take)
    if have_key and have_key == want_key then
      if wantLog and mode ~= "notes" then clog("[skip] extstate matches previous render (rename-only).") end
      if pos_enabled(name) then
        -- explicit //pos: dump minimal location info on skip (no step metrics)
        debug_log_locations(take, nil, nil, name)
      end
      return
    end
    if (not have_key) and take_has_any_events(take) then
      if wantLog and mode ~= "notes" then clog("[skip] events exist but no extstate → assuming split/duplicate; use //go to refresh.") end
      if pos_enabled(name) then
        debug_log_locations(take, nil, nil, name)
      end
      return
    end
  end

  if wantLog and mode ~= "notes" then
    clog(string.format("[parse] stepQN=%s  body='%s'", stepQN and fmt_qn(stepQN) or "nil", body_clean))
  end

  local tokens = tokenize_stream(body_clean)
  if wantLog and mode == "full" then
    clog("[tokens] raw:")
    for i,t in ipairs(tokens) do
      if type(t)=="table" and t.kind=="repeat_group" then
        clog(string.format("  %02d: [repeat] seg='%s' suffix='%s'", i, t.seg, t.suffix or ""))
      else
        clog(string.format("  %02d: %s", i, tostring(t)))
      end
    end
  end

  local flat = expand_tokens(tokens)
  if wantLog and mode ~= "notes" then
    clog("[expand] flat tokens (", #flat, "):")
    local preview = math.min(#flat, 128)
    for i=1, preview do clog(string.format("  %03d: %s", i, tostring(flat[i]))) end
    if #flat > preview then clog(string.format("  ... (%d more)", #flat - preview)) end
  end

  if not stepQN then
    stepQN = compute_fallback_stepQN(take, #flat)
    if wantLog and mode ~= "notes" then clog(string.format("[fallback] stepQN (itemLen/#steps) = %s", fmt_qn(stepQN))) end
  end

  clear_take(take)
  write_pattern_to_take(take, flat, stepQN, name, body_clean)

  if wantLog then
    clog("[done] wrote ", #flat, " steps.", stepQN and (" stepLen="..fmt_qn(stepQN)) or " (default stepLen=1.0 QN)")
  end
end

--------------------------------------------------------------------------------
-- Live watcher (defer loop)
--------------------------------------------------------------------------------
local STATE = { last = {}, next_scan = 0.0, interval = 0.20 } -- 200ms

local function take_guid(take)
  local item = reaper.GetMediaItemTake_Item(take)
  local _, guid = reaper.GetSetMediaItemInfo_String(item, "GUID", "", false)
  local idx = -1
  local it = reaper.CountTakes(item)
  for t=0, it-1 do if reaper.GetTake(item, t) == take then idx = t; break end end
  return guid .. "::" .. tostring(idx)
end

local function scan_once()
  local now = reaper.time_precise()
  if now < STATE.next_scan then return end
  STATE.next_scan = now + STATE.interval

  local proj = 0
  local item_cnt = reaper.CountMediaItems(proj)
  for i=0, item_cnt-1 do
    local item = reaper.GetMediaItem(proj, i)
    local take_cnt = reaper.CountTakes(item)
    for t=0, take_cnt-1 do
      local take = reaper.GetTake(item, t)
      if take and reaper.TakeIsMIDI(take) then
        local _, name = reaper.GetSetMediaItemTakeInfo_String(take, "P_NAME", "", false)
        if name and name ~= "" and name:sub(1,1) == "~" then
          local key = take_guid(take)
          local changed = (STATE.last[key] ~= name)
          local force   = force_go(name)
          if changed or force then
            STATE.last[key] = name
            local ok, err = pcall(process_name, take, name)
            if not ok then reaper.ShowConsoleMsg("[CUCO Tidal Error] "..tostring(err).."\n") end
          end
        end
      end
    end
  end
end

local function main_loop()
  local ok, err = pcall(scan_once)
  if not ok then reaper.ShowConsoleMsg("[CUCO Tidal Error] "..tostring(err).."\n") end
  reaper.defer(main_loop)
end

-- Start watcher
reaper.Undo_BeginBlock()
main_loop()
reaper.Undo_EndBlock("CUCO Tidal v1.4.12 (live)", -1)

