--[[
ReaScript Name: CUCO Tidal-from-Name Watcher (v1.3.3 — name-change only, per-take state, chord fix)
Author: curl + ChatGPT
About:
  Watches MIDI takes. Only when a take NAME actually changes and starts with "~",
  it parses the pattern and writes notes. Splitting items no longer causes rewrites.

Key updates vs 1.3.2:
  - **Name-change-only writes**: no write on item split/new take; writes trigger only after a real rename.
  - **Per-take state**: uses take GUIDs so each split has its own baseline without rewriting.
  - Keeps: robust clear; writes to the "~" take; chord fix; suffix normalization.
]]

---------------- User settings ----------------
local POLL_INTERVAL = 0.30
local DEBOUNCE_TIME = 0.40
local CHANNEL       = 0
local VELOCITY      = 110
local GATE          = 0.95   -- fraction of (step or sub-slot) length
local CLEAR_OLD     = true

---------------- tiny utils ----------------
local function now() return reaper.time_precise() end
local function trim(s) return (s or ""):gsub("^%s+",""):gsub("%s+$","") end
local function starts_with(s,p) return s:sub(1,#p)==p end
local function set_toggle_state(state)
  local _, _, sec, cmd = reaper.get_action_context()
  if cmd then reaper.SetToggleCommandState(sec, cmd, state and 1 or 0); reaper.RefreshToolbar2(sec, cmd) end
end

---------------- REAPER helpers ----------------
local function item_guid(item) local _, g = reaper.GetSetMediaItemInfo_String(item, "GUID", "", false); return g end
local function take_guid(take) local _, g = reaper.GetSetMediaItemTakeInfo_String(take, "GUID", "", false); return g end
local function get_take_name(take) local _, s = reaper.GetSetMediaItemTakeInfo_String(take, "P_NAME", "", false); return s or "" end
local function set_take_name(take, s) reaper.GetSetMediaItemTakeInfo_String(take, "P_NAME", s or "", true) end
local function qn_to_ppq(take, qn) return reaper.MIDI_GetPPQPosFromProjQN(take, qn) end

local function active_midi_take(item)
  local t = reaper.GetActiveTake(item)
  return (t and reaper.TakeIsMIDI(t)) and t or nil
end

-- Prefer a MIDI take whose name starts with "~". Otherwise return the active MIDI take.
local function find_watched_take(item)
  local n = reaper.CountTakes(item)
  local fallback = active_midi_take(item)
  for i=0,(n-1) do
    local t = reaper.GetTake(item, i)
    if t and reaper.TakeIsMIDI(t) then
      local nm = get_take_name(t)
      if starts_with(nm, "~") then return t end
      if not fallback then fallback = t end
    end
  end
  return fallback
end

---------------- note & chord helpers (C4=60) ----------------
local PC = { c=0, d=2, e=4, f=5, g=7, a=9, b=11 }
local function note_to_midi(tok)
  tok = tok:lower()
  local letter, acc, oct = tok:match("^([cdefgab])([#b]?)(%-?%d+)$")
  if not letter then return nil end
  local pc = PC[letter]; if acc=="#" then pc=pc+1 elseif acc=="b" then pc=pc-1 end
  local octave = tonumber(oct)
  local midi = (octave + 1)*12 + pc
  if midi < 0 then midi = 0 elseif midi > 127 then midi = 127 end
  return midi
end
local DEFAULT_MIDI = note_to_midi("c4")

-- Build chord offsets from quality/extensions string
local function build_chord_offsets(body)
  body = body:lower()
  local sus2  = body:find("sus2") ~= nil
  local sus4  = body:find("sus4") ~= nil
  local is_dim= body:find("dim") ~= nil or body:find("o") ~= nil
  local is_aug= body:find("aug") ~= nil or body:find("%+") ~= nil
  local is_min= (not sus2 and not sus4 and not is_dim and not is_aug)
                and (body:find("m") == 1 or body:find("^m") ~= nil or body:find("[^a]m[^a]") ~= nil)

  local deg
  if is_dim then deg={0,3,6}
  elseif is_aug then deg={0,4,8}
  elseif sus2  then deg={0,2,7}
  elseif sus4  then deg={0,5,7}
  elseif is_min then deg={0,3,7}
  else deg={0,4,7} end

  local want_maj7  = body:find("maj7") ~= nil
  local want_mMaj7 = body:find("mmaj7") ~= nil
  local want_dim7  = body:find("dim7") ~= nil
  local want_m7    = (body:find("m7") ~= nil) and not want_maj7 and not want_mMaj7
  local want_7     = (body:find("[^a]7") ~= nil) and not want_maj7 and not want_mMaj7 and not want_dim7

  if want_dim7 then deg={0,3,6,9}
  elseif want_mMaj7 then deg={0,3,7,11}
  elseif want_maj7 then table.insert(deg,11)
  elseif want_m7 or want_7 then table.insert(deg,10) end

  if body:find("add2") then table.insert(deg,2) end
  if body:find("add4") then table.insert(deg,5) end
  if body:find("add6") then table.insert(deg,9) end
  if body:find("add9") then table.insert(deg,14) end

  local ext9  = (body:find("[^a]9") ~= nil) and (not body:find("add9"))
  local ext11 = body:find("11") ~= nil
  local ext13 = body:find("13") ~= nil

  local have7=false; for _,v in ipairs(deg) do if v==9 or v==10 or v==11 then have7=true end end
  if (ext9 or ext11 or ext13) and not have7 and not want_mMaj7 and not want_dim7 then table.insert(deg,10) end
  if ext9  then table.insert(deg,14) end
  if ext11 then table.insert(deg,17) end
  if ext13 then table.insert(deg,21) end

  table.sort(deg)
  local uniq={}; for _,v in ipairs(deg) do if #uniq==0 or uniq[#uniq]~=v then uniq[#uniq+1]=v end end
  deg=uniq

  while #deg>4 do table.remove(deg,#deg) end
  return deg
end

-- CHANGED previously: plain notes are not chords
local function build_chord_pitches(chord_body)
  local rootL, acc, oct, rest = chord_body:lower():match("^([cdefgab])([#b]?)(%-?%d*)(.*)$")
  if not rootL then return nil end
  if rest == nil or rest == "" then return nil end
  local root_oct = tonumber(oct) or 4
  local root_pc  = PC[rootL]; if acc=="#" then root_pc=root_pc+1 elseif acc=="b" then root_pc=root_pc-1 end
  local root_midi= (root_oct+1)*12 + root_pc
  local deg = build_chord_offsets(rest or "")
  local pitches={}; for _,ofs in ipairs(deg) do pitches[#pitches+1]=root_midi+ofs end
  return pitches, root_midi
end

local function invert_pitches(pitches, n)
  if not pitches or #pitches==0 then return pitches end
  local k = n % #pitches; if k==0 then return pitches end
  local out={}; for i=1,#pitches do out[i]=pitches[i] end
  for i=1,k do local x=table.remove(out,1); table.insert(out, x+12) end
  return out
end

local function parse_bass_token(tok, default_root_midi)
  local m = note_to_midi(tok); if m then return m end
  local l,a = tok:lower():match("^([cdefgab])([#b]?)$")
  if l then
    local pc = PC[l]; if a=="#" then pc=pc+1 elseif a=="b" then pc=pc-1 end
    local root_oct = math.floor(default_root_midi/12)-1
    local cand = (root_oct+1)*12 + pc
    if cand > default_root_midi then cand = cand - 12 end
    return math.max(0, math.min(127, cand))
  end
  return nil
end

---------------- tokenizer (no spaces required) ----------------
local function tokenize_stream(body)
  local tokens = {}
  local i, n = 1, #body

  local function read_group(open, close)
    local depth = 0
    local start = i
    while i <= n do
      local ch = body:sub(i,i)
      if ch == open then
        depth = depth + 1
      elseif ch == close then
        depth = depth - 1
        if depth == 0 then
          local seg = body:sub(start, i)
          i = i + 1
          return seg
        end
      end
      i = i + 1
    end
    return body:sub(start)
  end

  local function looks_like_quality(idx)
    if idx > n then return false end
    local rem = body:sub(idx):lower()
    return rem:find("^mmaj")
        or rem:find("^maj")
        or rem:find("^m")
        or rem:find("^sus")
        or rem:find("^dim")
        or rem:find("^aug")
        or rem:find("^add")
        or rem:sub(1,1) == "+"
        or rem:sub(1,1) == "o"
        or rem:find("^7") or rem:find("^9") or rem:find("^11") or rem:find("^13")
  end

  while i <= n do
    local ch = body:sub(i,i)
    if ch:match("%s") then
      i = i + 1
    elseif ch == "[" then
      local seg = read_group("[", "]"); tokens[#tokens+1] = seg
    elseif ch == "(" then
      local seg = read_group("(", ")"); tokens[#tokens+1] = seg
    elseif ch == "x" or ch == "X" or ch == "_" or ch == "~" or ch == "-" then
      tokens[#tokens+1] = ch; i = i + 1
    elseif ch:match("[A-Ga-g]") then
      local start_i = i; i = i + 1
      if i <= n and body:sub(i,i):match("[#b]") then i = i + 1 end
      if i <= n and (body:sub(i,i):match("[%+%-]") or body:sub(i,i):match("%d")) then
        local k = i; if body:sub(k,k):match("[%+%-]") then k = k + 1 end
        while k <= n and body:sub(k,k):match("%d") do k = k + 1 end
        i = k
      end
      if looks_like_quality(i) then
        while i <= n do
          local c2 = body:sub(i,i)
          if c2 == "/" or c2 == "[" or c2 == "(" or c2 == ")" or c2 == "]" or c2 == "*" or c2:match("%s") then break end
          i = i + 1
        end
      end
      while i <= n and body:sub(i,i) == "/" do
        i = i + 1
        local k = i
        while k <= n do
          local c3 = body:sub(k,k)
          if c3 == "/" or c3 == "[" or c3 == "(" or c3 == ")" or c3 == "]" or c3 == "*" or c3:match("%s") then break end
          k = k + 1
        end
        i = k
      end
      if i <= n and body:sub(i,i) == "*" then
        local k = i + 1
        while k <= n and body:sub(k,k):match("%d") do k = k + 1 end
        if k > i + 1 then i = k end
      end
      tokens[#tokens+1] = body:sub(start_i, i-1)
    elseif ch == "*" then
      local k = i + 1
      while k <= n and body:sub(k,k):match("%d") do k = k + 1 end
      if tokens[#tokens] and k > i + 1 then
        tokens[#tokens] = tokens[#tokens] .. body:sub(i, k-1); i = k
      else
        i = i + 1
      end
    else
      i = i + 1
    end
  end
  return tokens
end

---------------- parse explicit [a,b,c] chord ----------------
local function parse_bracket_chord(tok)
  if tok:sub(1,1) ~= '[' or tok:sub(-1) ~= ']' then return nil end
  local inner = tok:sub(2,-2)
  local voices={}
  for part in inner:gmatch("[^,]+") do
    local v = trim(part)
    local midi = note_to_midi(v)
    if midi then voices[#voices+1]={type="note",midi=midi}
    elseif v=="x" or v=="X" then voices[#voices+1]={type="x"}
    elseif v=="_" then voices[#voices+1]={type="hold"}
    elseif v=="~" or v=="-" then voices[#voices+1]={type="rest"}
    else voices[#voices+1]={type="rest"} end
  end
  return { voices=voices }
end

---------------- parse subdivision (a,b,...) ----------------
local function parse_subdivision(tok)
  if tok:sub(1,1) ~= '(' or tok:sub(-1) ~= ')' then return nil end
  local inner = tok:sub(2,-2)
  local subs = {}
  local buf, depth = {}, 0
  for i=1,#inner do
    local ch = inner:sub(i,i)
    if ch=='[' then depth=depth+1; buf[#buf+1]=ch
    elseif ch==']' then depth=depth-1; buf[#buf+1]=ch
    elseif ch==',' and depth==0 then subs[#subs+1]=trim(table.concat(buf)); buf={}
    else buf[#buf+1]=ch end
  end
  if #buf>0 then subs[#subs+1]=trim(table.concat(buf)) end
  return subs
end

---------------- parse steps (top-level) ----------------
local function parse_steps_from_name(name)
  local pattern = name
  local cut = pattern:find("%s*//")
  if cut then pattern = trim(pattern:sub(1, cut-1)) end

  local body = trim(pattern:sub(2)) -- drop leading "~"
  if body == "" then return {}, 0, pattern end
  local raw = tokenize_stream(body)

  local function parse_token_to_event(tok)
    local base, repstr = tok:match("^(.-)%*(%d+)$")
    local repeatN = nil
    if base then tok = base; repeatN = tonumber(repstr) end

    local br = parse_bracket_chord(tok)
    if br then
      local ev = { kind="chord", voices=br.voices }
      if repeatN and repeatN>1 then return { kind="subdiv", subs = { ev, repeatN=repeatN } } end
      return ev
    end

    local midi = note_to_midi(tok)
    if midi then
      local ev = { kind="single", midi=midi }
      if repeatN and repeatN>1 then return { kind="subdiv", subs = { ev, repeatN=repeatN } } end
      return ev
    end

    local basePart, mods = tok:match("^([^/]+)(.*)$")
    local pitches, root_midi = nil, nil
    if basePart then pitches, root_midi = build_chord_pitches(basePart) end
    if pitches then
      local ext_bass = {}
      local stack_bass = nil
      local inv = 0
      local idx = 1
      while idx <= #mods do
        if mods:sub(idx,idx) ~= "/" then idx = idx + 1 goto continue end
        local j = mods:find("/", idx+1) or (#mods+1)
        local seg = trim(mods:sub(idx+1, j-1))
        if seg:match("^%d+$") then
          inv = inv + tonumber(seg)
        else
          local bass = parse_bass_token(seg, root_midi or DEFAULT_MIDI)
          if bass then
            if inv==0 and not stack_bass then stack_bass = bass else ext_bass[#ext_bass+1]=bass end
          end
        end
        idx = j
        ::continue::
      end
      local full = {}
      if stack_bass then full[#full+1]=stack_bass end
      for _,p in ipairs(pitches) do full[#full+1]=p end
      full = invert_pitches(full, inv)
      for _,b in ipairs(ext_bass) do table.insert(full, 1, b) end
      local ev = { kind="ctoken", pitches=full }
      if repeatN and repeatN>1 then return { kind="subdiv", subs = { ev, repeatN=repeatN } } end
      return ev
    end

    if tok=="x" or tok=="X" then return { kind="inherit" } end
    if tok=="_"           then return { kind="hold" } end
    if tok=="~" or tok=="-" then return { kind="rest" } end

    return nil
  end

  local steps = {}
  for _, tok in ipairs(raw) do
    if tok:sub(1,1) == '(' then
      local subs = parse_subdivision(tok)
      if subs then
        local events = {}
        for _, s in ipairs(subs) do
          local ev = nil
          if s:sub(1,1) == '[' then
            local br = parse_bracket_chord(s)
            ev = { kind="chord", voices=br and br.voices or {} }
          else
            ev = parse_token_to_event(s)
          end
          if ev then events[#events+1] = ev end
        end
        steps[#steps+1] = { kind="subdiv", subs = events }
      end
    else
      local ev = parse_token_to_event(tok)
      if ev then
        if ev.kind=="subdiv" and ev.subs and ev.subs.repeatN then
          local repeated = {}
          for i=1,ev.subs.repeatN do repeated[#repeated+1] = ev.subs[1] end
          steps[#steps+1] = { kind="subdiv", subs=repeated }
        else
          steps[#steps+1] = ev
        end
      end
    end
  end

  return steps, #steps, pattern
end

---------------- clear + writing engine ----------------
local function clear_take_all(take)
  reaper.MIDI_DisableSort(take)
  local _, noteCount, ccCount, textCount = reaper.MIDI_CountEvts(take)
  for i = noteCount-1, 0, -1 do reaper.MIDI_DeleteNote(take, i) end
  for i = ccCount-1,   0, -1 do reaper.MIDI_DeleteCC(take, i) end
  for i = textCount-1, 0, -1 do reaper.MIDI_DeleteTextSysexEvt(take, i) end
  reaper.MIDI_Sort(take)
end

local function write_steps(item, take, steps)
  if #steps==0 then return false, 0 end

  local pos  = reaper.GetMediaItemInfo_Value(item,"D_POSITION")
  local len  = reaper.GetMediaItemInfo_Value(item,"D_LENGTH")
  if len<=0 then return false, 0 end

  local q0 = reaper.TimeMap2_timeToQN(0,pos)
  local q1 = reaper.TimeMap2_timeToQN(0,pos+len)
  local totalQN = q1 - q0
  if totalQN<=0 then return false, 0 end

  local stepQN = totalQN / #steps

  local function insert_note(ppq_on, ppq_off, pitch)
    reaper.MIDI_InsertNote(take,false,false,ppq_on,ppq_off,CHANNEL,pitch,VELOCITY,true)
    local _, noteCount = reaper.MIDI_CountEvts(take)
    return noteCount-1
  end

  if CLEAR_OLD then clear_take_all(take) end

  local last_event_pitches = nil
  local chord_voice_memory = {}
  local last_idx_per_voice = {}
  local last_group_indices = nil
  local notes_written = 0

  reaper.MIDI_DisableSort(take)

  local function extend_group_to(qn_off)
    if not last_group_indices then return end
    for _, idx in ipairs(type(last_group_indices)=="table" and last_group_indices or {last_group_indices}) do
      local ok, sel, mute, sppq, eppq, chan, pit, vel = reaper.MIDI_GetNote(take, idx)
      if ok then reaper.MIDI_SetNote(take, idx, sel, mute, sppq, qn_to_ppq(take, qn_off), chan, pit, vel, true) end
    end
  end

  local function play_pitches_at(pitches, onQN, slotQN)
    local offQN = onQN + slotQN*GATE
    local onPPQ = qn_to_ppq(take, onQN)
    local offPPQ= qn_to_ppq(take, offQN)
    local idxs, played = {}, {}
    for _,p in ipairs(pitches) do
      local idx = insert_note(onPPQ, offPPQ, p)
      idxs[#idxs+1] = idx; played[#played+1] = p
      notes_written = notes_written + 1
    end
    if #played>0 then
      last_event_pitches = played
      last_group_indices = idxs
      for vi,p in ipairs(played) do chord_voice_memory[vi]=p; last_idx_per_voice[vi]=idxs[vi] end
    end
  end

  for si, S in ipairs(steps) do
    local stepOnQN  = q0 + (si-1)*stepQN
    local stepOffQN = stepOnQN + stepQN

    if S.kind == "subdiv" then
      local subs = S.subs or {}
      local subN = math.max(1, #subs)
      local subQN = stepQN / subN
      local local_last = last_event_pitches

      for k=1,subN do
        local sub = subs[k]
        local onQN = stepOnQN + (k-1)*subQN
        if sub.kind=="rest" then
        elseif sub.kind=="hold" then
          extend_group_to(onQN + subQN)
        elseif sub.kind=="inherit" then
          local pitches = local_last or last_event_pitches or { DEFAULT_MIDI }
          play_pitches_at(pitches, onQN, subQN)
          local_last = pitches
        elseif sub.kind=="single" then
          play_pitches_at({sub.midi}, onQN, subQN)
          local_last = { sub.midi }
        elseif sub.kind=="ctoken" then
          play_pitches_at(sub.pitches, onQN, subQN)
          local_last = { table.unpack(sub.pitches) }
        elseif sub.kind=="chord" then
          for vi=1,#sub.voices do if chord_voice_memory[vi]==nil then chord_voice_memory[vi]=DEFAULT_MIDI end end
          local offQN = onQN + subQN*GATE
          local onPPQ = qn_to_ppq(take, onQN)
          local offPPQ= qn_to_ppq(take, offQN)
          local idxs, played = {}, {}
          for vi,V in ipairs(sub.voices) do
            if V.type=="note" then
              local idx = insert_note(onPPQ, offPPQ, V.midi)
              chord_voice_memory[vi]=V.midi; last_idx_per_voice[vi]=idx
              idxs[#idxs+1]=idx; played[#played+1]=V.midi; notes_written = notes_written + 1
            elseif V.type=="x" then
              local p = chord_voice_memory[vi] or DEFAULT_MIDI
              local idx = insert_note(onPPQ, offPPQ, p)
              last_idx_per_voice[vi]=idx; idxs[#idxs+1]=idx; played[#played+1]=p; notes_written = notes_written + 1
            elseif V.type=="hold" then
              local idx = last_idx_per_voice[vi]
              if idx then
                local ok, sel, mute, sppq, eppq, chan, pit, vel = reaper.MIDI_GetNote(take, idx)
                if ok then reaper.MIDI_SetNote(take, idx, sel, mute, sppq, qn_to_ppq(take, onQN + subQN), chan, pit, vel, true) end
              end
            end
          end
          if #played>0 then
            last_event_pitches = played
            last_group_indices = idxs
            local_last = { table.unpack(played) }
          end
        end
      end

    elseif S.kind == "rest" then
    elseif S.kind == "hold" then
      extend_group_to(stepOffQN)
    elseif S.kind == "inherit" then
      local pitches = last_event_pitches or { DEFAULT_MIDI }
      play_pitches_at(pitches, stepOnQN, stepQN)
    elseif S.kind == "single" then
      play_pitches_at({S.midi}, stepOnQN, stepQN)
    elseif S.kind == "ctoken" then
      play_pitches_at(S.pitches, stepOnQN, stepQN)
    elseif S.kind == "chord" then
      for vi=1,#S.voices do if chord_voice_memory[vi]==nil then chord_voice_memory[vi]=DEFAULT_MIDI end end
      local offQN = stepOnQN + stepQN*GATE
      local onPPQ = qn_to_ppq(take, stepOnQN)
      local offPPQ= qn_to_ppq(take, offQN)
      local idxs, played = {}, {}
      for vi,V in ipairs(S.voices) do
        if V.type=="note" then
          local idx = insert_note(onPPQ, offPPQ, V.midi)
          chord_voice_memory[vi]=V.midi; last_idx_per_voice[vi]=idx
          idxs[#idxs+1]=idx; played[#played+1]=V.midi; notes_written = notes_written + 1
        elseif V.type=="x" then
          local p = chord_voice_memory[vi] or DEFAULT_MIDI
          local idx = insert_note(onPPQ, offPPQ, p)
          last_idx_per_voice[vi]=idx; idxs[#idxs+1]=idx; played[#played+1]=p; notes_written = notes_written + 1
        elseif V.type=="hold" then
          local idx = last_idx_per_voice[vi]
          if idx then
            local ok, sel, mute, sppq, eppq, chan, pit, vel = reaper.MIDI_GetNote(take, idx)
            if ok then reaper.MIDI_SetNote(take, idx, sel, mute, sppq, qn_to_ppq(take, stepOnQN + stepQN), chan, pit, vel, true) end
          end
        end
      end
      if #played>0 then
        last_event_pitches = played
        last_group_indices = idxs
      end
    end
  end

  reaper.MIDI_Sort(take)
  return true, notes_written
end

---------------- watcher with //N suffix (non-intrusive) ----------------
-- NEW: per-take state (prevents split-trigger writes)
-- takeState[TAKE_GUID] = { lastName="", lastPattern="", tChange=nil, byUs=false, initialized=false }
local takeState = {}

local function split_pattern_and_suffix(name)
  local body = trim(name)
  local cut = body:find("%s*//")
  if cut then
    local head = trim(body:sub(1,cut-1))
    local suf  = trim(body:sub(cut+2))
    return head, suf
  else
    return body, nil
  end
end

local function project_items()
  local t = {}; local n = reaper.CountMediaItems(0)
  for i=0,n-1 do t[#t+1]=reaper.GetMediaItem(0,i) end
  return t
end

local function process_items()
  local tnow = now()
  for _, item in ipairs(project_items()) do
    local take = find_watched_take(item)
    if not take then goto continue end

    local tkg = take_guid(take)
    local ts = takeState[tkg] or { lastName="", lastPattern="", tChange=nil, byUs=false, initialized=false }
    takeState[tkg] = ts

    local name = get_take_name(take)

    -- First time we see this take: register baseline, do NOT write.
    if not ts.initialized then
      ts.lastName = name
      ts.initialized = true
      goto continue
    end

    -- Record name changes for debounce
    if ts.lastName ~= name then
      ts.lastName = name
      ts.tChange = tnow
    end

    -- Fire ONLY after a real (post-initial) name change settles
    if ts.tChange and (tnow - ts.tChange) >= DEBOUNCE_TIME then
      if starts_with(name, "~") then
        local patternOnly = (split_pattern_and_suffix(name))
        -- We treat ANY user rename on a "~" name as a rewrite signal.
        -- (ts.byUs covers our suffix normalization to avoid loops.)
        if not ts.byUs then
          local steps, stepCount = parse_steps_from_name(patternOnly)
          reaper.Undo_BeginBlock()
          local ok, wrote = write_steps(item, take, steps)
          if ok and wrote == 0 and #steps > 0 then ok, wrote = write_steps(item, take, steps) end
          reaper.Undo_EndBlock("CUCO Tidal v1.3.3: wrote MIDI from name", -1)
          ts.lastPattern = patternOnly

          local newName = patternOnly .. " //" .. tostring(stepCount)
          if name ~= newName then
            ts.byUs = true
            set_take_name(take, newName)
            ts.lastName = newName
          end
        else
          -- We changed the name (suffix). Clear the flag and carry on.
          ts.byUs = false
        end
      else
        -- Name no longer starts with "~" → nothing to do (baseline is already updated)
        ts.byUs = false
      end
      ts.tChange = nil
    end

    ::continue::
  end
end

local running = true
local nextPoll = 0
local function loop()
  if not running then return end
  local t = now()
  if t >= nextPoll then process_items(); nextPoll = t + POLL_INTERVAL end
  reaper.defer(loop)
end

-- toggle via toolbar button
do
  if _G.__CUCO_TIDAL_NAME_WATCHER_V133__ then
    _G.__CUCO_TIDAL_NAME_WATCHER_V133__ = false
    running = false
    set_toggle_state(false)
    return
  end
  _G.__CUCO_TIDAL_NAME_WATCHER_V133__ = true
end

set_toggle_state(true)
reaper.atexit(function() _G.__CUCO_TIDAL_NAME_WATCHER_V133__ = false; set_toggle_state(false) end)
loop()
