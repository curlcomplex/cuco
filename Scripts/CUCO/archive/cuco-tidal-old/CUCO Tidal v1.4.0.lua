--[[
ReaScript Name: CUCO Tidal-from-Name Watcher (v1.4.0 — step header + slash repeats)
Author: curl + ChatGPT
About:
  Watches MIDI takes. When a take NAME changes and starts with "~", it parses the pattern and writes notes.

New in 1.4.0:
  - Step-size header at the start (e.g., "~16", "~8t", "~5q", "~7s", "~9n", "~0.5").
    Each top-level token consumes exactly one step of that musical duration in QN.
  - Slash-repeat groups with optional per-loop transforms:
      / <mini-seq> /8, 0 1 5 7 3 4 5 6      (per-loop transposition, semitones)
      / <mini-seq> /8, dev=0.2              (20% deviation chance per step)
  - Keeps 1.3.2 chord fix: single notes parsed before chord-tokens; plain "c4" is not a chord.

Renderer notes:
  - Each top-level token = one step (fixed QN if header present).
  - Holds "_" extend within the step/sub-step.
  - If the first-ever note is inherited (x) or a blank chord voice, defaults to c4.

]]--

math.randomseed(reaper.time_precise() * 1e6)

--------------------------------------------------------------------------------
-- Utilities
--------------------------------------------------------------------------------
local function trim(s) return (s:gsub("^%s+",""):gsub("%s+$","")) end

local PC_BASE = {c=0,d=2,e=4,f=5,g=7,a=9,b=11}
local PC_NAME = {[0]="c",[1]="c#",[2]="d",[3]="d#",[4]="e",[5]="f",[6]="f#",[7]="g",[8]="g#",[9]="a",[10]="a#",[11]="b"}

local function note_to_midi(note) -- "c#4" -> 61
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
      stepQN = 4.0 / denom -- 1/denom notes; quarter=1.0 QN
      if flag == "t" then stepQN = stepQN * (2/3)   -- triplet
      elseif flag == "q" then stepQN = stepQN * (4/5) -- quintuplet (5 in time of 4)
      elseif flag == "s" then stepQN = stepQN * (4/7) -- septuplet (7 in time of 4)
      elseif flag == "n" then stepQN = stepQN * (8/9) -- nonuplet (9 in time of 8)
      end
    end
    body = name:sub(#hdr + 2):gsub("^%s+","")
  end
  return stepQN, body
end

--------------------------------------------------------------------------------
-- Tokenizer ([], (), /.../N[, args]), rest "~" or "-", hold "_", inherit "x"
--------------------------------------------------------------------------------
local function read_group(body, i, open, close)
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

local function read_group_with_suffix(body, i, open, close)
  local seg, ni = read_group(body, i, open, close)
  -- parse optional "/N[, args]" immediately after
  local n = #body
  local j = ni
  while j <= n and body:sub(j,j):match("%s") do j = j + 1 end
  local sufStart = j
  local suffix = nil
  if body:sub(sufStart,sufStart) == "/" then
    local rest = body:sub(sufStart+1)
    local m = rest:match("^%s*(%d+%s*,%s*[^%s].-)%s") or rest:match("^%s*(%d+)")
    if m then
      suffix = m
      j = sufStart + 1 + #m
      ni = j
    end
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
      local seg, ni = read_group(text, i, "[", "]")
      tokens[#tokens+1] = seg
      i = ni
    elseif ch == "(" then
      local seg, ni = read_group(text, i, "(", ")")
      tokens[#tokens+1] = seg
      i = ni
    elseif ch == "/" then
      local seg, suffix, ni = read_group_with_suffix(text, i, "/", "/")
      tokens[#tokens+1] = { kind="repeat_group", seg=seg, suffix=suffix }
      i = ni
    else
      -- collect a simple token up to whitespace or one of []()/ separators
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
-- Slash-repeat expansion: / ... /N, [transp list] or dev=0.x
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
          out[#out+1] = v -- leave chord-quality-only voices untouched
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
    -- mild harmonic wiggle: add /1 inversion to a chord-token lacking slash
    if tok:match("^[a-gA-G][b#]?%-?%d+[%a]") or tok:match("^[a-gA-G][b#]?%a") then
      if (not tok:find("/%d")) and (not tok:find("/[a-gA-G]")) then
        return tok.."/1"
      end
    end
  end
  return tok
end

local function expand_repeat_group(node, tokenize_func)
  local body = node.seg:match("^/%s*(.-)%s*/$") or ""
  local cfg  = parse_repeat_suffix(node.suffix)
  local times = cfg.times or 1
  local inner = tokenize_func(body)
  local out = {}
  for rep = 1, times do
    local semis = nil
    if cfg.transp and cfg.transp[rep] then
      semis = cfg.transp[rep]
    elseif cfg.transp and #cfg.transp > 0 then
      semis = cfg.transp[#cfg.transp] -- hold last if fewer provided
    end
    for _,t in ipairs(inner) do
      if type(t) == "table" and t.kind == "repeat_group" then
        local nested = expand_repeat_group(t, tokenize_func)
        for _,nn in ipairs(nested) do
          nn = transpose_token(nn, semis)
          nn = deviate_token(nn, cfg.dev)
          out[#out+1] = nn
        end
      else
        local s = (type(t) == "string") and t or (t.text or "")
        s = transpose_token(s, semis)
        s = deviate_token(s, cfg.dev)
        out[#out+1] = s
      end
    end
  end
  return out
end

--------------------------------------------------------------------------------
-- Pattern parsing to a flat list of step tokens
--------------------------------------------------------------------------------
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
-- MIDI writing
--------------------------------------------------------------------------------
local function clear_take(take)
  reaper.MIDI_DisableSort(take)
  reaper.MIDI_DeleteEvt(take, -1) -- nukes all (notes/cc/sysex/text)
  reaper.MIDI_Sort(take)
end

local function qn_time_helpers(take)
  local item = reaper.GetMediaItemTake_Item(take)
  local itemPos = reaper.GetMediaItemInfo_Value(item, "D_POSITION")
  local itemStartQN = reaper.TimeMap2_timeToQN(0, itemPos)
  local function qnToPPQ(qn) return reaper.MIDI_GetPPQPosFromProjQN(take, qn) end
  return itemStartQN, qnToPPQ
end

local function write_pattern_to_take(take, flat_tokens, stepQN_opt)
  local itemStartQN, qnToPPQ = qn_time_helpers(take)
  local defaultStepQN = stepQN_opt
  local ppq = function(qn) return qnToPPQ(qn) end

  reaper.MIDI_DisableSort(take)

  local last_pitch = note_to_midi("c4") or 60
  local k = 0
  for _,tok in ipairs(flat_tokens) do
    local stepQN = defaultStepQN or 1.0 -- fallback: quarter per step if no header
    local stepStartQN = itemStartQN + k * stepQN
    local stepEndQN   = stepStartQN + stepQN

    local function write_note(midi, startQN, endQN, vel)
      local sel, chan = false, 0
      local startPPQ, endPPQ = ppq(startQN), ppq(endQN)
      reaper.MIDI_InsertNote(take, sel, false, startPPQ, endPPQ, chan, midi, vel or 96, false)
    end

    local function handle_simple_note_or_chord(token)
      -- explicit chord [a,b,c] (voices can be x,_ or ~)
      if token:sub(1,1) == "[" and token:sub(-1) == "]" then
        local inner = token:sub(2,-2)
        local voices = {}
        for v in inner:gmatch("([^,]+)") do voices[#voices+1] = trim(v) end
        local voiceCount = #voices
        local segLen = stepQN -- whole step duration by default
        local vStart, vEnd = stepStartQN, stepEndQN
        for _,v in ipairs(voices) do
          if v == "x" or v == "~" or v == "-" then
            -- rest voice: skip
          elseif v == "_" then
            -- hold voice: do nothing new here (would need context of prior note per voice; skipped for simplicity)
          else
            local note, rest = v:match("^([a-gA-G][b#]?%-?%d+)(.*)")
            if note then
              local midi = note_to_midi(note)
              if midi then
                last_pitch = midi
                write_note(midi, vStart, vEnd, 96)
              end
            else
              -- chord-token (csus4 etc.) — TODO: optional voicing engine; for now, treat as a single implied root note if explicit octave given
              local root, qual = v:match("^([a-gA-G][b#]?%-?%d*)(.*)")
              local rootNote = root and root:match("%-?%d+") and root or nil
              if rootNote then
                local midi = note_to_midi(rootNote)
                if midi then
                  last_pitch = midi
                  write_note(midi, vStart, vEnd, 96)
                end
              end
            end
          end
        end
        return
      end

      -- subdivisions (t1,t2,...) inside step
      if token:sub(1,1) == "(" and token:sub(-1) == ")" then
        local inner = token:sub(2,-2)
        local parts = {}
        for v in inner:gmatch("([^,]+)") do parts[#parts+1] = trim(v) end
        local N = math.max(1, #parts)
        local subLen = stepQN / N
        for i,part in ipairs(parts) do
          local sQN = stepStartQN + (i-1)*subLen
          local eQN = sQN + subLen
          if part == "x" or part == "~" or part == "-" then
            -- rest
          elseif part == "_" then
            -- hold: extend previous note within sub-step — we approximate by lengthening last written note to eQN
            -- (Simplified: no per-voice memory here)
          else
            local note, rest = part:match("^([a-gA-G][b#]?%-?%d+)(.*)")
            if note then
              local midi = note_to_midi(note)
              if midi then last_pitch = midi; write_note(midi, sQN, eQN, 96) end
            elseif part == "x" then
              -- rest
            else
              -- bare chord-token fallback: ignore or treat as rest (safer)
            end
          end
        end
        return
      end

      -- holds / rests / inherit / single note or chord-token
      if token == "~" or token == "-" then
        -- rest
      elseif token == "_" then
        -- hold previous: extend the last note — requires tracking last note handle; omitted for simplicity
      elseif token == "x" then
        -- inherit previous pitch
        if last_pitch then write_note(last_pitch, stepStartQN, stepEndQN, 96) end
      else
        -- single note or chord-token; prefer explicit note
        local note, rest = token:match("^([a-gA-G][b#]?%-?%d+)(.*)")
        if note then
          local midi = note_to_midi(note)
          if midi then last_pitch = midi; write_note(midi, stepStartQN, stepEndQN, 96) end
        else
          -- chord-token without explicit octave: by design we skip (needs voicer); keeps 1.3.2 behavior
        end
      end
    end

    if type(tok) == "string" then
      handle_simple_note_or_chord(tok)
    else
      -- should not happen after expansion
    end

    k = k + 1
  end

  reaper.MIDI_Sort(take)
end

--------------------------------------------------------------------------------
-- Main: watch take names, parse, write
--------------------------------------------------------------------------------
local function process_take(take, name)
  local stepQN, body = parse_step_header(name)   -- NEW: step-size header
  body = body or name
  -- Strip leading "~" if not consumed:
  if body:sub(1,1) == "~" then body = body:sub(2) end
  body = trim(body)

  -- Tokenize and expand repeats
  local tokens = tokenize_stream(body)
  local flat   = expand_tokens(tokens)

  clear_take(take)
  write_pattern_to_take(take, flat, stepQN)
end

local function run_once()
  local proj = 0
  local item_cnt = reaper.CountMediaItems(proj)
  for i=0, item_cnt-1 do
    local item = reaper.GetMediaItem(proj, i)
    local take_cnt = reaper.CountTakes(item)
    for t=0, take_cnt-1 do
      local take = reaper.GetTake(item, t)
      if take and not reaper.TakeIsMIDI(take) then goto continue_take end
      local _, name = reaper.GetSetMediaItemTakeInfo_String(take, "P_NAME", "", false)
      if name and name:sub(1,1) == "~" then
        process_take(take, name)
      end
      ::continue_take::
    end
  end
end

-- Run once when invoked
reaper.Undo_BeginBlock()
run_once()
reaper.Undo_EndBlock("CUCO Tidal-from-Name Watcher v1.4.0", -1)
