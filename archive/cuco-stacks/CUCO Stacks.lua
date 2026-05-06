--[[
ReaScript Name: CUCO Stacks — v0.0.2 — ACCIDENTAL FIXES TEST
Author: curl + ChatGPT

What’s in this version
  • New branch: CUCO Stacks — stacks are the primary container
  • Groups “( … )” removed (use stacks only)
  • Core tokens: notes + x / . / _  (no whitespace required)
  • New token: x^ (processed inherit flag) — parsed now, behaves like x until processors land
  • In-stack offsets: note±N (e.g. c3+2) and x±N (e.g. x-5); stack-level +/− applies to x too
  • Stacks "[ … ]" use per-slot semantics (notes, x, _, .; omitted = rest)
  • Repeats `*N` on any token; per-note ±N transpose suffix retained
  • Debugger v1 (//debug //full|//brief //cap=N //notes //trace //trace-scan)
  • Deterministic PLAN/WRITE and robust SCAN (unchanged)
]]

-------------------------------------------------------------------------------
-- Config / Globals
-------------------------------------------------------------------------------
-- Immediate startup log to confirm script loading
reaper.ShowConsoleMsg("[CUCO Stacks] Script loading/reloading at " .. os.date("%H:%M:%S") .. "\n")
local debug_file = io.open("/tmp/cuco_debug.log", "a")
if debug_file then
  debug_file:write("[SCRIPT-START] CUCO Stacks script loading at " .. os.date("%H:%M:%S") .. "\n")
  debug_file:flush()
  debug_file:close()
end

local PROJ_NS          = "CUCO_STACKS_ORIGINS"
local __BOOTED         = false
local VERBOSE_WATCHER  = false

-- Safety limits (temporarily relaxed for debugging)
local MAX_NAME_LEN     = 1000000    -- effectively disabled during investigation
local MAX_PARSE_STEPS  = 1000000000 -- effectively disabled during investigation

-- Defaults
local DEFAULT_PITCH    = 60   -- C4
local DEFAULT_CH       = 0    -- MIDI channel
local DEFAULT_VEL      = 96   -- Velocity

-- Debug toggle (must be defined before functions that reference it)
DEBUG_TOK = true

-------------------------------------------------------------------------------
-- Scale database (intervals in semitones from root)
-------------------------------------------------------------------------------
local SCALES = {
  -- Western Traditional
  major = {0,2,4,5,7,9,11}, maj = {0,2,4,5,7,9,11}, M = {0,2,4,5,7,9,11},
  minor = {0,2,3,5,7,8,10}, min = {0,2,3,5,7,8,10}, m = {0,2,3,5,7,8,10},
  dorian = {0,2,3,5,7,9,10}, dor = {0,2,3,5,7,9,10},
  phrygian = {0,1,3,5,7,8,10}, phr = {0,1,3,5,7,8,10},
  lydian = {0,2,4,6,7,9,11}, lyd = {0,2,4,6,7,9,11},
  mixolydian = {0,2,4,5,7,9,10}, mix = {0,2,4,5,7,9,10},
  locrian = {0,1,3,5,6,8,10}, loc = {0,1,3,5,6,8,10},
  harmonic = {0,2,3,5,7,8,11}, harm = {0,2,3,5,7,8,11},
  melodic = {0,2,3,5,7,9,11}, mel = {0,2,3,5,7,9,11},
  pentatonic = {0,2,4,7,9}, pent = {0,2,4,7,9},
  pentmin = {0,3,5,7,10}, pentm = {0,3,5,7,10},
  blues = {0,3,5,6,7,10},
  chromatic = {0,1,2,3,4,5,6,7,8,9,10,11}, chrom = {0,1,2,3,4,5,6,7,8,9,10,11},
  
  -- Middle Eastern & Arabic
  maqam_hijaz = {0,1,4,5,7,8,11}, hijaz = {0,1,4,5,7,8,11},
  maqam_rast = {0,2,4,5,7,9,11}, rast = {0,2,4,5,7,9,11}, -- approximated
  maqam_bayati = {0,2,3,5,7,9,10}, bayati = {0,2,3,5,7,9,10}, -- approximated
  maqam_saba = {0,2,3,4,6,8,10}, saba = {0,2,3,4,6,8,10}, -- approximated
  maqam_kurd = {0,1,3,5,7,8,10}, kurd = {0,1,3,5,7,8,10},
  persian = {0,1,4,5,6,8,11},
  double_harmonic = {0,1,4,5,7,8,11}, byzantine = {0,1,4,5,7,8,11},
  
  -- Asian Traditional
  japanese = {0,2,3,7,8}, hirajoshi = {0,2,3,7,8},
  kumoi = {0,2,3,7,9},
  iwato = {0,1,5,6,10},
  in_sen = {0,1,5,7,10}, insen = {0,1,5,7,10},
  yo = {0,2,5,7,9},
  chinese = {0,2,4,7,9},
  mongolian = {0,2,4,7,9},
  pelog = {0,1,3,7,8},
  slendro = {0,2,5,7,9},
  
  -- Indian Classical
  raga_bilawal = {0,2,4,5,7,9,11}, bilawal = {0,2,4,5,7,9,11},
  raga_kafi = {0,2,3,5,7,9,10}, kafi = {0,2,3,5,7,9,10},
  raga_bhairav = {0,1,4,5,7,8,11}, bhairav = {0,1,4,5,7,8,11},
  raga_malkauns = {0,3,5,8,10}, malkauns = {0,3,5,8,10},
  raga_yaman = {0,2,4,6,7,9,11}, yaman = {0,2,4,6,7,9,11},
  raga_bhimpalasi = {0,2,3,5,7,9,10}, bhimpalasi = {0,2,3,5,7,9,10},
  
  -- African Traditional
  african_pentatonic = {0,3,5,7,10}, afropent = {0,3,5,7,10},
  ethiopian = {0,2,3,5,7,8,11}, tezeta = {0,2,3,5,7,8,11},
  west_african = {0,2,3,5,7,9,10},
  pygmy = {0,2,4,7,9},
  saharan = {0,1,4,5,7,8,10},
  
  -- European Folk
  gypsy = {0,1,4,5,7,8,11}, romani = {0,1,4,5,7,8,11},
  hungarian_minor = {0,2,3,6,7,8,11}, hungarian = {0,2,3,6,7,8,11},
  neapolitan_minor = {0,1,3,5,7,8,11}, neapolitan = {0,1,3,5,7,8,11},
  ukrainian_dorian = {0,2,3,6,7,9,10}, ukrainian = {0,2,3,6,7,9,10},
  flamenco = {0,1,4,5,7,8,11},
  
  -- Exotic & Experimental
  whole_tone = {0,2,4,6,8,10}, wholetone = {0,2,4,6,8,10},
  diminished = {0,1,3,4,6,7,9,10}, octatonic = {0,1,3,4,6,7,9,10},
  augmented = {0,3,4,7,8,11},
  prometheus = {0,2,4,6,9,10},
  tritone = {0,1,4,6,7,10},
  enigmatic = {0,1,4,6,8,10,11},
  super_locrian = {0,1,3,4,6,8,10}, altered = {0,1,3,4,6,8,10},
  bebop_dominant = {0,2,4,5,7,9,10,11}, bebop = {0,2,4,5,7,9,10,11},
  
  -- Microtonal (approximated to 12-TET)
  quarter_tone = {0,0.5,1,1.5,2,2.5,3,3.5,4,4.5,5,5.5,6,6.5,7,7.5,8,8.5,9,9.5,10,10.5,11,11.5}, -- 24tet subset
  ['24tet'] = {0,0.5,1,1.5,2,2.5,3,3.5,4,4.5,5,5.5,6,6.5,7,7.5,8,8.5,9,9.5,10,10.5,11,11.5}
}

-- Music utilities (note name to pitch class conversion)
local PC_BASE = {c=0,d=2,e=4,f=5,g=7,a=9,b=11}
local PC_NAME = {[0]="c",[1]="c#",[2]="d",[3]="d#",[4]="e",[5]="f",[6]="f#",[7]="g",[8]="g#",[9]="a",[10]="a#",[11]="b"}

-- Scale context state
local current_scale = {
  root = 0,        -- C = 0, C# = 1, etc.
  intervals = {0,2,4,5,7,9,11}, -- default to major
  quantize = "near", -- "up", "down", "near", "ignore"
  explicit = false -- flag to track if scale was explicitly set via notation
}

-- Scale utility functions
local function parse_scale_spec(spec)
  -- Parse @root.scale.quantize format, e.g. "@c.major.up" or "@f#.blues.ignore"
  local root_str, scale_name, quantize_mode = spec:match("^@([a-gA-G][b#]?)%.([%w_]+)%.?([%w]*)$")
  if not root_str or not scale_name then
    -- Try simpler format: @root.scale
    root_str, scale_name = spec:match("^@([a-gA-G][b#]?)%.([%w_]+)$")
  end
  
  if not root_str or not scale_name then return nil end
  
  -- Parse root note
  local root_pc = PC_BASE[root_str:sub(1,1):lower()] or 0
  if root_str:len() > 1 then
    local acc = root_str:sub(2,2)
    if acc == '#' then root_pc = root_pc + 1
    elseif acc == 'b' then root_pc = root_pc - 1
    end
  end
  root_pc = root_pc % 12
  
  -- Look up scale intervals
  local intervals = SCALES[scale_name:lower()]
  if not intervals then return nil end
  
  -- Parse quantize mode
  local qmode = "near" -- default
  if quantize_mode and quantize_mode ~= "" then
    local q = quantize_mode:lower()
    if q == "up" or q == "down" or q == "near" or q == "ignore" then
      qmode = q
    end
  end
  
  return { root = root_pc, intervals = intervals, quantize = qmode }
end

local function apply_scale_context(scale_ctx)
  current_scale.root = scale_ctx.root or current_scale.root
  current_scale.intervals = scale_ctx.intervals or current_scale.intervals
  current_scale.quantize = scale_ctx.quantize or current_scale.quantize
  current_scale.explicit = true -- mark that scale was explicitly set
  
  -- DEBUG: Log scale context application
  local debug_file = io.open("/tmp/cuco_debug.log", "a")
  if debug_file then
    debug_file:write("[APPLY_SCALE] Applied scale context:\n")
    debug_file:write("[APPLY_SCALE] Root: " .. tostring(current_scale.root) .. "\n")
    debug_file:write("[APPLY_SCALE] Intervals: " .. table.concat(current_scale.intervals, ",") .. "\n")
    debug_file:write("[APPLY_SCALE] Quantize: " .. tostring(current_scale.quantize) .. "\n")
    debug_file:write("[APPLY_SCALE] Explicit: " .. tostring(current_scale.explicit) .. "\n")
    debug_file:flush()
    debug_file:close()
  end
end

local function quantize_to_scale(midi_note)
  if current_scale.quantize == "ignore" then
    -- Check if note is in scale, return nil if not
    local pc = midi_note % 12
    local root_offset = (pc - current_scale.root + 12) % 12
    for _, interval in ipairs(current_scale.intervals) do
      if math.abs(interval - root_offset) < 0.1 then -- allow small tolerance for microtonal
        return midi_note -- note is in scale
      end
    end
    return nil -- note not in scale, ignore it
  elseif current_scale.quantize == "near" or current_scale.quantize == "up" or current_scale.quantize == "down" then
    local octave = math.floor(midi_note / 12)
    local pc = midi_note % 12
    local root_offset = (pc - current_scale.root + 12) % 12
    
    -- First check if note is already in scale (exact match)
    for _, interval in ipairs(current_scale.intervals) do
      if math.abs(interval - root_offset) < 0.1 then -- allow small tolerance for microtonal
        return midi_note -- note is already in scale, no quantization needed
      end
    end
    
    -- Find closest scale degree
    local best_interval = current_scale.intervals[1] or 0
    local best_dist = math.abs(root_offset - best_interval)
    
    for _, interval in ipairs(current_scale.intervals) do
      local dist = math.abs(root_offset - interval)
      -- Handle wrap-around (e.g. 11 semitones vs 1 semitone for next octave)
      local wrap_dist = math.abs(root_offset - (interval + 12))
      local wrap_dist2 = math.abs((root_offset + 12) - interval)
      dist = math.min(dist, wrap_dist, wrap_dist2)
      
      if current_scale.quantize == "up" then
        -- Prefer higher intervals when equal distance
        if dist < best_dist or (dist == best_dist and interval > best_interval) then
          best_interval = interval
          best_dist = dist
        end
      elseif current_scale.quantize == "down" then
        -- Prefer lower intervals when equal distance
        if dist < best_dist or (dist == best_dist and interval < best_interval) then
          best_interval = interval
          best_dist = dist
        end
      else -- "near"
        if dist < best_dist or (dist == best_dist and interval < best_interval) then
          best_interval = interval
          best_dist = dist
        end
      end
    end
    
    -- Calculate final MIDI note
    local target_pc = (current_scale.root + best_interval) % 12
    return octave * 12 + target_pc
  else
    return midi_note -- no quantization
  end
end

-------------------------------------------------------------------------------
-- Console helpers (with cap)
-------------------------------------------------------------------------------
local __CAP = 300
local __LINES = 0
local function clog_reset(cap) __CAP = math.max(1, cap or 300); __LINES = 0; reaper.ShowConsoleMsg("") end
local function logln(s) if __LINES < __CAP then reaper.ShowConsoleMsg((s or "").."\n"); __LINES = __LINES + 1 end end

-------------------------------------------------------------------------------
-- Watcher state 
-------------------------------------------------------------------------------
local STATE = { last_seen = {}, seeded = false, next_scan = 0.0, interval = 0.33 }

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
local function trim(s) return (s or ""):gsub("^%s+",""):gsub("%s+$","") end
local function note_to_midi(note)
  if type(note) ~= "string" then return nil end
  
  -- DEBUG: Log every note conversion attempt to file
  local debug_file = io.open("/tmp/cuco_debug.log", "a")
  if debug_file then
    debug_file:write("[NOTE_TO_MIDI] Input: '" .. tostring(note) .. "'\n")
    debug_file:flush()
    debug_file:close()
  end
  
  -- More robust pattern matching with explicit accidental handling
  local l, a, o
  
  -- First, try to match with explicit sharp
  l, o = note:match("^([a-gA-G])#(%-?%d+)$")
  if l then
    a = "#"
    local debug_file = io.open("/tmp/cuco_debug.log", "a")
    if debug_file then
      debug_file:write("[NOTE_TO_MIDI] Sharp match: l='" .. tostring(l) .. "' o='" .. tostring(o) .. "'\n")
      debug_file:close()
    end
  else
    -- Try to match with explicit flat  
    l, o = note:match("^([a-gA-G])b(%-?%d+)$")
    if l then
      a = "b"
      local debug_file = io.open("/tmp/cuco_debug.log", "a")
      if debug_file then
        debug_file:write("[NOTE_TO_MIDI] Flat match: l='" .. tostring(l) .. "' o='" .. tostring(o) .. "'\n")
        debug_file:close()
      end
    else
      -- Try natural note (no accidental)
      l, o = note:match("^([a-gA-G])(%-?%d+)$")
      if l then
        a = ""
        local debug_file = io.open("/tmp/cuco_debug.log", "a")
        if debug_file then
          debug_file:write("[NOTE_TO_MIDI] Natural match: l='" .. tostring(l) .. "' o='" .. tostring(o) .. "'\n")
          debug_file:close()
        end
      end
    end
  end
  
  if not l then return nil end
  
  local pc = PC_BASE[l:lower()] or 0
  
  -- Apply accidental
  if a == "#" then 
    pc = pc + 1
  elseif a == "b" then 
    pc = pc - 1
  end
  
  local result = (tonumber(o)+1)*12 + pc
  
  -- DEBUG: Log the result
  local debug_file = io.open("/tmp/cuco_debug.log", "a")
  if debug_file then
    debug_file:write("[NOTE_TO_MIDI] Result: " .. tostring(result) .. "\n")
    debug_file:flush()
    debug_file:close()
  end
  
  return result
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
  local flags = { debug=false, full=false, brief=true, cap=300, notes=false, trace=false, trace_scan=false, debug_all=false }
  for flag in name:gmatch("//%s*([^\n]+)") do
    local f = flag:lower()
    if f:find("debug") then flags.debug=true end
    if f:find("full") then flags.full=true; flags.brief=false end
    if f:find("brief") then flags.full=false; flags.brief=true end
    local cap=f:match("cap%s*=%s*(%d+)"); if cap then flags.cap=tonumber(cap) or flags.cap end
    if f:find("notes") then flags.notes=true end
    if f:find("trace%-?scan") then flags.trace_scan=true; flags.debug=true end
    if f:find("trace") and not f:find("trace%-?scan") then flags.trace=true; flags.debug=true end
    -- One-shot exhaustive mode: //all, //debug-all, or //everything
    if f:find("debug%-?all") or f:match("%f[%w]all%f[%W]") or f:match("%f[%w]everything%f[%W]") then
      flags.debug_all = true
    end
  end
  if flags.debug_all then
    flags.debug = true
    flags.full = true
    flags.brief = false
    flags.notes = true
    flags.trace = true
    flags.trace_scan = true
    flags.cap = math.max(flags.cap or 300, 20000)
  end
  return flags
end

local function parse_step_header(name)
  local stepQN, scale_ctx, body = nil, nil, name
  
  -- First, look for step resolution: ~N[flag]
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
  
  -- Next, look for scale specification: @root.scale.quantize
  local scale_spec = body:match("^(@[a-gA-G][b#]?%.[%w_]+%.?[%w]*)")
  if scale_spec then
    -- Debug: Log scale parsing
    local debug_file = io.open("/tmp/cuco_debug.log", "a")
    if debug_file then
      debug_file:write("[SCALE_PARSE] Found scale spec: '" .. tostring(scale_spec) .. "'\n")
      debug_file:close()
    end
    
    scale_ctx = parse_scale_spec(scale_spec)
    if scale_ctx then
      -- Debug: Log parsed scale context
      local debug_file = io.open("/tmp/cuco_debug.log", "a")
      if debug_file then
        debug_file:write("[SCALE_PARSE] Parsed scale context: root=" .. tostring(scale_ctx.root) .. " quantize=" .. tostring(scale_ctx.quantize) .. "\n")
        debug_file:close()
      end
      body = body:sub(#scale_spec+1):gsub("^%s+","")
    else
      -- Debug: Log parsing failure
      local debug_file = io.open("/tmp/cuco_debug.log", "a")
      if debug_file then
        debug_file:write("[SCALE_PARSE] Failed to parse scale spec: '" .. tostring(scale_spec) .. "'\n")
        debug_file:close()
      end
    end
  end
  
  body = trim(body); if body:sub(1,1)=="~" then body=body:sub(2) end
  local body_clean = body:gsub("%s//.*$", "")
  
  -- Debug: Log the parsed body
  local debug_file = io.open("/tmp/cuco_debug.log", "a")
  if debug_file then
    debug_file:write("[PARSE_HEADER] body='" .. tostring(body) .. "'\n")
    debug_file:write("[PARSE_HEADER] body_clean='" .. tostring(trim(body_clean)) .. "'\n")
    debug_file:close()
  end
  
  return stepQN, scale_ctx, body, trim(body_clean)
end

-------------------------------------------------------------------------------
-- Tokenizer (notes/x/./_, [stack], repeat *N, loop |...|N) — groups removed in CUCO Stacks
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

-- Parse chained processors like !arp(up,7), !arp/7, and shorthands !up/3, !down/4, !rand/5
local function maybe_parse_processors_after(body, i, n, node)
  local k = i
  local procs = nil
  local function attach(target)
    if not procs or #procs == 0 then return target, k end
    -- Attach processors to the innermost meaningful node (before repeat handling)
    target.procs = target.procs or {}
    for _,p in ipairs(procs) do table.insert(target.procs, p) end
    return target, k
  end
  while k <= n do
    while k <= n and body:sub(k,k):match("%s") do k = k + 1 end
    if body:sub(k,k) ~= '!' then break end
    -- !name(args)
    local nam, argstr = body:sub(k):match("^!([%a_][%w_]*)%(([^%)]*)%)")
    if nam then
      k = k + 1 + #nam + 1 + #argstr + 1
      local name = nam:lower()
      procs = procs or {}
      if name == 'arp' then
        -- !arp(dir, N[, span[, one_shot]]) where dir supports the stable set.
        -- span: stretch factor across subdivisions (>=1). one_shot: if 1, do not loop order.
        local dir4, num4, span4, oneshot4 = argstr:match("^%s*([%w_]+)%s*,%s*(%d+)%s*,%s*(%d+)%s*,%s*(%d+)%s*$")
        local dir3, num3, span3 = nil, nil, nil
        if not dir4 then dir3, num3, span3 = argstr:match("^%s*([%w_]+)%s*,%s*(%d+)%s*,%s*(%d+)%s*$") end
        local dir2, num2 = nil, nil
        if not dir4 and not dir3 then dir2, num2 = argstr:match("^%s*([%w_]+)%s*,%s*(%d+)%s*$") end
        if dir4 then
          local dir = dir4:lower(); local nval = tonumber(num4) or 0; local span = math.max(1, tonumber(span4) or 1); local loop = not ((tonumber(oneshot4) or 0) == 1)
          local k = nil
          local sk = dir:match('^skip(%d+)$'); if sk then k = tonumber(sk); dir = 'skip' end
          local rk = dir:match('^rot(%d+)$');  if rk then k = tonumber(rk); dir = 'rotate' end
          local rk2 = dir:match('^rotate(%d+)$'); if rk2 then k = tonumber(rk2); dir = 'rotate' end
          if dir == 'random' then dir = 'rand' end
          if dir == 'pendulum' then dir = 'pend' end
          if dir == 'inside_out' then dir = 'io' end
          if dir == 'outside_in' then dir = 'oi' end
          if dir == 'zigzag' then dir = 'zz' end
          table.insert(procs, { kind='proc', name='arp', dir=dir, n=nval, span=span, loop=loop, k=k })
        elseif dir3 then
          local dir = dir3:lower(); local nval = tonumber(num3) or 0; local span = math.max(1, tonumber(span3) or 1); local loop = true
          local k = nil
          local sk = dir:match('^skip(%d+)$'); if sk then k = tonumber(sk); dir = 'skip' end
          local rk = dir:match('^rot(%d+)$');  if rk then k = tonumber(rk); dir = 'rotate' end
          local rk2 = dir:match('^rotate(%d+)$'); if rk2 then k = tonumber(rk2); dir = 'rotate' end
          if dir == 'random' then dir = 'rand' end
          if dir == 'pendulum' then dir = 'pend' end
          if dir == 'inside_out' then dir = 'io' end
          if dir == 'outside_in' then dir = 'oi' end
          if dir == 'zigzag' then dir = 'zz' end
          table.insert(procs, { kind='proc', name='arp', dir=dir, n=nval, span=span, loop=loop, k=k })
        elseif dir2 then
          local dir = dir2:lower(); local nval = tonumber(num2) or 0; local span = 1; local loop = true
          local k = nil
          local sk = dir:match('^skip(%d+)$'); if sk then k = tonumber(sk); dir = 'skip' end
          local rk = dir:match('^rot(%d+)$');  if rk then k = tonumber(rk); dir = 'rotate' end
          local rk2 = dir:match('^rotate(%d+)$'); if rk2 then k = tonumber(rk2); dir = 'rotate' end
          if dir == 'random' then dir = 'rand' end
          if dir == 'pendulum' then dir = 'pend' end
          if dir == 'inside_out' then dir = 'io' end
          if dir == 'outside_in' then dir = 'oi' end
          if dir == 'zigzag' then dir = 'zz' end
          table.insert(procs, { kind='proc', name='arp', dir=dir, n=nval, span=span, loop=loop, k=k })
        end
      elseif name == 'poly' then
        -- !poly(n1,n2,n3,...) - euclidean rhythms for each stack voice
        -- Each argument specifies the number of hits for that voice
        local subdivisions = {}
        for num in argstr:gmatch("(%d+)") do
          table.insert(subdivisions, tonumber(num) or 1)
        end
        if #subdivisions > 0 then
          table.insert(procs, { kind='proc', name='poly', subdivisions=subdivisions })
        end
      elseif name == 'up' or name == 'down' or name == 'rand' or name == 'random'
            or name == 'updown' or name == 'pend' or name == 'pendulum'
            or name == 'inside_out' or name == 'io' or name == 'outside_in' or name == 'oi'
            or name == 'zigzag' or name == 'zz' or name:match('^skip%d+$') or name:match('^rot%d+$') or name:match('^rotate%d+$') then
        local dir = name
        local k = nil
        if dir == 'random' then dir = 'rand' end
        if dir == 'pendulum' then dir = 'pend' end
        if dir == 'inside_out' then dir = 'io' end
        if dir == 'outside_in' then dir = 'oi' end
        if dir == 'zigzag' then dir = 'zz' end
        local sk = dir:match('^skip(%d+)$'); if sk then k = tonumber(sk); dir = 'skip' end
        local rk = dir:match('^rot(%d+)$');  if rk then k = tonumber(rk); dir = 'rotate' end
        local rk2 = dir:match('^rotate(%d+)$'); if rk2 then k = tonumber(rk2); dir = 'rotate' end
        local num = tonumber((argstr or ''):match("(%d+)") or '') or 0
        table.insert(procs, { kind='proc', name='arp', dir=dir, n=num, loop=true, k=k })
      else
        -- Unknown processor; store raw for future use
        table.insert(procs, { kind='proc', name=name, raw=argstr })
      end
    else
      -- !name/number shorthand
      local nam2, rate = body:sub(k):match("^!([%a_][%w_]*)/(%d+)")
      if nam2 then
        k = k + 1 + #nam2 + 1 + #rate
        local name = nam2:lower()
        procs = procs or {}
        if name == 'arp' or name == 'up' or name == 'down' or name == 'rand' or name == 'random'
           or name == 'updown' or name == 'pend' or name == 'pendulum'
           or name == 'inside_out' or name == 'io' or name == 'outside_in' or name == 'oi'
           or name == 'zigzag' or name == 'zz' or name:match('^skip%d+$') or name:match('^rot%d+$') or name:match('^rotate%d+$') then
          local dir = (name == 'arp') and 'up' or (name == 'random' and 'rand' or name)
          local k = nil
          if dir == 'pendulum' then dir = 'pend' end
          if dir == 'inside_out' then dir = 'io' end
          if dir == 'outside_in' then dir = 'oi' end
          if dir == 'zigzag' then dir = 'zz' end
          local sk = dir:match('^skip(%d+)$'); if sk then k = tonumber(sk); dir = 'skip' end
          local rk = dir:match('^rot(%d+)$');  if rk then k = tonumber(rk); dir = 'rotate' end
          local rk2 = dir:match('^rotate(%d+)$'); if rk2 then k = tonumber(rk2); dir = 'rotate' end
          table.insert(procs, { kind='proc', name='arp', dir=dir, n=tonumber(rate) or 0, span=1, loop=true, k=k })
        else
          table.insert(procs, { kind='proc', name=name, n=tonumber(rate) or 0 })
        end
      else
        break
      end
    end
  end
  return attach(node)
end

local function maybe_parse_inline_procs(s, idx)
  local k = idx
  local procs = {}
  while k <= #s do
    if s:sub(k,k) ~= '!' then break end
    -- !name(args)
    local nam, argstr = s:sub(k):match("^!([%a_][%w_]*)%(([^%)]*)%)")
    if nam then
      k = k + 1 + #nam + 1 + #argstr + 1
      local name = nam:lower()
      if name == 'arp' then
        -- !arp(dir, N[, span[, one_shot]])
        local dir4, num4, span4, oneshot4 = argstr:match("^%s*([%w_]+)%s*,%s*(%d+)%s*,%s*(%d+)%s*,%s*(%d+)%s*$")
        local dir3, num3, span3 = nil, nil, nil
        if not dir4 then dir3, num3, span3 = argstr:match("^%s*([%w_]+)%s*,%s*(%d+)%s*,%s*(%d+)%s*$") end
        local dir2, num2 = nil, nil
        if not dir4 and not dir3 then dir2, num2 = argstr:match("^%s*([%w_]+)%s*,%s*(%d+)%s*$") end
        if dir4 then
          local dir = dir4:lower(); local nval = tonumber(num4) or 0; local span = math.max(1, tonumber(span4) or 1); local loop = not ((tonumber(oneshot4) or 0) == 1)
          local k = nil
          local sk = dir:match('^skip(%d+)$'); if sk then k = tonumber(sk); dir = 'skip' end
          local rk = dir:match('^rot(%d+)$');  if rk then k = tonumber(rk); dir = 'rotate' end
          local rk2 = dir:match('^rotate(%d+)$'); if rk2 then k = tonumber(rk2); dir = 'rotate' end
          if dir == 'random' then dir = 'rand' end
          if dir == 'pendulum' then dir = 'pend' end
          if dir == 'inside_out' then dir = 'io' end
          if dir == 'outside_in' then dir = 'oi' end
          if dir == 'zigzag' then dir = 'zz' end
          table.insert(procs, { kind='proc', name='arp', dir=dir, n=nval, span=span, loop=loop, k=k })
        elseif dir3 then
          local dir = dir3:lower(); local nval = tonumber(num3) or 0; local span = math.max(1, tonumber(span3) or 1); local loop = true
          local k = nil
          local sk = dir:match('^skip(%d+)$'); if sk then k = tonumber(sk); dir = 'skip' end
          local rk = dir:match('^rot(%d+)$');  if rk then k = tonumber(rk); dir = 'rotate' end
          local rk2 = dir:match('^rotate(%d+)$'); if rk2 then k = tonumber(rk2); dir = 'rotate' end
          if dir == 'random' then dir = 'rand' end
          if dir == 'pendulum' then dir = 'pend' end
          if dir == 'inside_out' then dir = 'io' end
          if dir == 'outside_in' then dir = 'oi' end
          if dir == 'zigzag' then dir = 'zz' end
          table.insert(procs, { kind='proc', name='arp', dir=dir, n=nval, span=span, loop=loop, k=k })
        end
      elseif name == 'poly' then
        -- !poly(n1,n2,n3,...) - euclidean rhythms for each stack voice
        local subdivisions = {}
        for num in argstr:gmatch("(%d+)") do
          table.insert(subdivisions, tonumber(num) or 1)
        end
        if #subdivisions > 0 then
          table.insert(procs, { kind='proc', name='poly', subdivisions=subdivisions })
        end
      elseif name == 'arp' then
        -- Handle remaining arp cases
        local dir2, num2 = argstr:match("^%s*([%w_]+)%s*,%s*(%d+)%s*$")
        if dir2 then
          local dir = dir2:lower(); local nval = tonumber(num2) or 0; local span = 1; local loop = true
          local k = nil
          local sk = dir:match('^skip(%d+)$'); if sk then k = tonumber(sk); dir = 'skip' end
          local rk = dir:match('^rot(%d+)$');  if rk then k = tonumber(rk); dir = 'rotate' end
          local rk2 = dir:match('^rotate(%d+)$'); if rk2 then k = tonumber(rk2); dir = 'rotate' end
          if dir == 'random' then dir = 'rand' end
          if dir == 'pendulum' then dir = 'pend' end
          if dir == 'inside_out' then dir = 'io' end
          if dir == 'outside_in' then dir = 'oi' end
          if dir == 'zigzag' then dir = 'zz' end
          table.insert(procs, { kind='proc', name='arp', dir=dir, n=nval, span=span, loop=loop, k=k })
        end
      elseif name == 'up' or name == 'down' or name == 'rand' or name == 'random'
             or name == 'updown' or name == 'pend' or name == 'pendulum'
             or name == 'inside_out' or name == 'io' or name == 'outside_in' or name == 'oi'
             or name == 'zigzag' or name == 'zz' or name:match('^skip%d+$') or name:match('^rot%d+$') or name:match('^rotate%d+$') then
        local dir = name
        local k = nil
        if dir == 'random' then dir = 'rand' end
        if dir == 'pendulum' then dir = 'pend' end
        if dir == 'inside_out' then dir = 'io' end
        if dir == 'outside_in' then dir = 'oi' end
        if dir == 'zigzag' then dir = 'zz' end
        local sk = dir:match('^skip(%d+)$'); if sk then k = tonumber(sk); dir = 'skip' end
        local rk = dir:match('^rot(%d+)$');  if rk then k = tonumber(rk); dir = 'rotate' end
        local rk2 = dir:match('^rotate(%d+)$'); if rk2 then k = tonumber(rk2); dir = 'rotate' end
          local num = tonumber((argstr or ''):match("(%d+)") or '') or 0
          table.insert(procs, { kind='proc', name='arp', dir=dir, n=num, span=1, loop=true, k=k })
      else
        table.insert(procs, { kind='proc', name=name, raw=argstr })
      end
    else
      local nam2, rate = s:sub(k):match("^!([%a_][%w_]*)/(%d+)")
      if nam2 then
        k = k + 1 + #nam2 + 1 + #rate
        local name = nam2:lower()
        if name == 'arp' or name == 'up' or name == 'down' or name == 'rand' or name == 'random' then
        local dir = (name == 'arp') and 'up' or (name == 'random' and 'rand' or name)
        table.insert(procs, { kind='proc', name='arp', dir=dir, n=tonumber(rate) or 0, span=1, loop=true })
        else
          table.insert(procs, { kind='proc', name=name, n=tonumber(rate) or 0 })
        end
      else
        break
      end
    end
  end
  return procs, k
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

local function scan_chunk_with_repeats(chunk, out, warnings)
  local i, n = 1, #chunk
  local steps = 0
  if DEBUG_TOK then logln("[CHUNK] "..chunk) end
  while i <= n do
    steps = steps + 1
    local sub = chunk:sub(i)
    local advanced = false

    -- X/X^ with optional offset and processors (e.g. X+12!arp(up,7))
    do
      local p = 1
      local c1 = sub:sub(p,p)
      if c1 == 'x' or c1 == 'X' then
        p = p + 1
        -- optional spaces
        while p <= #sub and sub:sub(p,p):match('%s') do p = p + 1 end
        -- optional caret
        local inherit = false
        if sub:sub(p,p) == '^' then inherit = true; p = p + 1 end
        while p <= #sub and sub:sub(p,p):match('%s') do p = p + 1 end
        -- optional +/- offset
        local off = sub:sub(p):match('^([+-]%d+)')
        if off then p = p + #off end
        while p <= #sub and sub:sub(p,p):match('%s') do p = p + 1 end
        -- processors start with '!'
        if sub:sub(p,p) == '!' then
          local rest = sub:sub(p)
          local node = { kind='xref', inherit=inherit, n=tonumber(off) or 0 }
          local procs = select(1, maybe_parse_inline_procs(rest, 1))
          if procs and #procs > 0 then node.procs = procs end
          out[#out+1] = node
          if DEBUG_TOK then logln(string.format("[SCAN] XREF+PROCS chunk='%s' parsed at p=%d", sub, p)) end
          i = i + (p - 1) + #rest
          advanced = true
        end
      end
    end

    if not advanced then
      -- bare X^ with optional +/-N (no procs)
      local xs_bare, caret_bare, xoff_bare = sub:match("^([xX])(%^)([+-]%d+)?")
      if xs_bare then
        out[#out+1] = { kind='xref', inherit=true, n=tonumber(xoff_bare) or 0 }
        i = i + 1 + #caret_bare + (xoff_bare and #xoff_bare or 0)
        advanced = true
      end
    end

    if not advanced then
      -- note(+/-tp)*rep
      local base, tp, rep = sub:match("^([a-gA-G][b#]?%-?%d+)([+-]%d+)%*(%d+)")
      if base and tp and rep then
        if DEBUG_TOK then logln(string.format("[SCAN] NOTE+TP*REP captured: '%s%s*%s'", base, tp, rep)) end
        local node = { kind='transpose', n=tonumber(tp), inner=base }
        out[#out+1] = { kind='repeat', n=tonumber(rep), inner=node }
        i = i + #base + #tp + 1 + #rep
        advanced = true
      end
    end

    if not advanced then
      -- note*rep
      local note, rep2 = sub:match("^([a-gA-G][b#]?%-?%d+)%*(%d+)")
      if note and rep2 then
        if DEBUG_TOK then logln(string.format("[SCAN] NOTE*REP captured: '%s*%s'", note, rep2)) end
        out[#out+1] = { kind='repeat', n=tonumber(rep2), inner=note }
        i = i + #note + 1 + #rep2
        advanced = true
      end
    end

    if not advanced then
      -- note(+/-tp)
      local base2, tp2 = sub:match("^([a-gA-G][b#]?%-?%d+)([+-]%d+)")
      if base2 and tp2 then
        if DEBUG_TOK then logln(string.format("[SCAN] NOTE+TP captured: '%s%s'", base2, tp2)) end
        out[#out+1] = { kind='transpose', n=tonumber(tp2), inner=base2 }
        i = i + #base2 + #tp2
        advanced = true
      end
    end

    if not advanced then
      -- processed inherit variants x^±N*R, x^*R, x^±N, x^
      local xs1, tpPr, repPr = sub:match("^([xX])%^([+-]%d+)%*(%d+)")
      if xs1 and tpPr and repPr then
        local node = { kind='inherit', n=tonumber(tpPr) or 0, processed=true }
        out[#out+1] = { kind='repeat', n=tonumber(repPr), inner=node }
        i = i + 1 + 1 + #tpPr + 1 + #repPr
        advanced = true
      else
        local xs2, repPr2 = sub:match("^([xX])%^%*(%d+)")
        if xs2 and repPr2 then
          local node = { kind='inherit', n=0, processed=true }
          out[#out+1] = { kind='repeat', n=tonumber(repPr2), inner=node }
          i = i + 1 + 1 + 1 + #repPr2
          advanced = true
        else
          local xs3, tpPr3 = sub:match("^([xX])%^([+-]%d+)")
          if xs3 and tpPr3 then
            out[#out+1] = { kind='inherit', n=tonumber(tpPr3) or 0, processed=true }
            i = i + 1 + 1 + #tpPr3
            advanced = true
          else
            local xs4 = sub:match("^([xX])%^")
            if xs4 then
              out[#out+1] = { kind='inherit', n=0, processed=true }
              i = i + 2
              advanced = true
            end
          end
        end
      end
    end

    if not advanced then
      -- legacy x variants: x±N*R, x±N
      local x1, tpX, repX = sub:match("^([xX])([+-]%d+)%*(%d+)")
      if x1 and tpX and repX then
        local node = { kind='inherit', n=tonumber(tpX) or 0 }
        out[#out+1] = { kind='repeat', n=tonumber(repX), inner=node }
        i = i + 1 + #tpX + 1 + #repX
        advanced = true
      else
        local x2, tpX2 = sub:match("^([xX])([+-]%d+)")
        if x2 and tpX2 then
          out[#out+1] = { kind='inherit', n=tonumber(tpX2) or 0 }
          i = i + 1 + #tpX2
          advanced = true
        end
      end
    end

    if not advanced then
      -- symbol*rep (x . _ -)
      local sym, rep3 = sub:match("^([xX%._%-])%*(%d+)")
      if sym then
        out[#out+1] = { kind='repeat', n=tonumber(rep3), inner=sym:lower() }
        i = i + 2 + #rep3
        advanced = true
      end
    end

    if not advanced then
      -- symbol (x . _ -)
      local sym2 = sub:match("^([xX%._%-])")
      if sym2 then
        out[#out+1] = sym2:lower()
        i = i + 1
        advanced = true
      end
    end

    if not advanced then
      -- plain note - try explicit patterns for better accidental handling
      local note2
      -- Try comprehensive note pattern that handles all accidental cases
      -- Pattern explanation: ([a-gA-G]) = note letter, ([b#]?) = optional accidental, (%-?%d+) = octave with optional minus
      note2 = sub:match("^([a-gA-G][b#]?%-?%d+)")
      
      if note2 then
        -- Debug: Log what we captured to file
        local debug_file = io.open("/tmp/cuco_debug.log", "a")
        if debug_file then
          debug_file:write("[TOKENIZE] NOTE captured: '" .. tostring(note2) .. "' from '" .. sub:sub(1, math.min(10, #sub)) .. "'\n")
          debug_file:close()
        end
        out[#out+1] = note2
        i = i + #note2
        advanced = true
      end
    end

    if not advanced then
      -- skip unknown char
      if warnings then warnings[#warnings+1] = sub:sub(1,1) end
      i = i + 1
    end
  end
end

-- DEBUG_TOK is global above; do not redeclare locally here

local function tokenize(body_clean, warnings)
  local toks = {}; local i, n = 1, #body_clean
  local steps = 0
  while i <= n do
    steps = steps + 1
    local ch = body_clean:sub(i,i)
    if DEBUG_TOK and steps % 64 == 1 then
      logln(string.format("[TOK] i=%d rem='%s'", i, body_clean:sub(i, math.min(i+40, n))))
    end
    if ch:match("%s") then
      i = i + 1


    elseif ch=="[" then
      local j=i+1; while j<=n and body_clean:sub(j,j) ~= "]" do j=j+1 end
      local inner=body_clean:sub(i+1, math.min(j-1,n)); local entries={}
      for part in inner:gmatch("%S+") do entries[#entries+1]=part end
      local node = { kind="stack", entries=entries }
      -- Order: transpose, processors, transpose, then repeat
      local node2, k2 = maybe_wrap_transpose_after(body_clean, j+1, n, node)
      local node3, k3 = maybe_parse_processors_after(body_clean, k2, n, node2)
      local node4, k4 = maybe_wrap_transpose_after(body_clean, k3, n, node3)
      local wrapped, ni = maybe_wrap_repeat_after(body_clean, k4, n, node4)
      toks[#toks+1] = wrapped; i = ni

    elseif ch=="(" then
      -- Groups removed in CUCO Stacks: skip legacy group syntax entirely
      local j=i+1; while j<=n and body_clean:sub(j,j) ~= ")" do j=j+1 end
      i = math.min(j+1, n+1)
    elseif ch=="@" then
      -- Inline scale specification: @root.scale.quantize
      local scale_spec = body_clean:sub(i):match("^(@[a-gA-G][b#]?%.[%w_]+%.?[%w]*)")
      if scale_spec then
        local scale_ctx = parse_scale_spec(scale_spec)
        if scale_ctx then
          local node = { kind = "scale", scale_ctx = scale_ctx, spec = scale_spec }
          toks[#toks+1] = node
          i = i + #scale_spec
        else
          -- Invalid scale spec, treat as unknown char
          if warnings then warnings[#warnings+1] = ch end
          i = i + 1
        end
      else
        -- Not a valid scale spec, treat as unknown char
        if warnings then warnings[#warnings+1] = ch end
        i = i + 1
      end
    elseif ch=="|" then
      -- Loop region: | ... |N  where N is required integer >=1
      local j=i+1; local nest=1
      -- We allow nested loops by counting '|' and '|' pairs; inner '|' must be escaped? For now, support single-level only
      while j<=n do
        local cj = body_clean:sub(j,j)
        if cj == '|' then break end
        j=j+1
      end
      local inner = body_clean:sub(i+1, math.min(j-1,n))
      -- parse repeat count right after closing '|'
      local k = j+1
      while k<=n and body_clean:sub(k,k):match('%s') do k=k+1 end
      local num = body_clean:sub(k):match("^(%d+)")
      if not num then
        -- no count; treat as plain characters to avoid infinite loop
        if warnings then warnings[#warnings+1] = '|' end
        i = i + 1
      else
        local entries = tokenize(inner, warnings)
        local node = { kind = "loop", n = math.max(1, tonumber(num) or 1), entries = entries }
        toks[#toks+1] = node
        i = k + #num
      end
    else
      local j=i
      local paren=0
      while j<=n do
        local c=body_clean:sub(j,j)
        if c=="(" then paren=paren+1
        elseif c==")" and paren>0 then paren=paren-1 end
        if paren==0 and (c:match("%s") or c=="[") then break end
        j=j+1
      end
      local chunk = body_clean:sub(i, j-1)
      -- Fallback: explicitly detect X/X^ with inline processors in this chunk
      do
        local xsig, caret, xoff, proc = chunk:match("^%s*([xX])%s*(%^?)%s*([+-]%d+)?%s*(![%a_][%w_]*%b())%s*$")
        if xsig and proc then
          local node = { kind = 'xref', inherit = (caret == '^'), n = tonumber(xoff) or 0 }
          local procs = select(1, maybe_parse_inline_procs(proc, 1))
          if procs and #procs > 0 then node.procs = procs end
          toks[#toks+1] = node
        else
          scan_chunk_with_repeats(chunk, toks, warnings)
        end
      end
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
local function insert_notes(take,pitches,sQN,eQN,vel,ch)
  -- DEBUG: Log all pitches being inserted
  local debug_file = io.open("/tmp/cuco_debug.log", "a")
  if debug_file then
    debug_file:write("[INSERT_NOTES] Pitches to insert: " .. table.concat(pitches, ",") .. "\n")
    debug_file:write("[INSERT_NOTES] Time range: " .. tostring(sQN) .. " to " .. tostring(eQN) .. " QN\n")
    debug_file:flush()
    debug_file:close()
  end
  
  local sPPQ=reaper.MIDI_GetPPQPosFromProjQN(take,sQN); local ePPQ=reaper.MIDI_GetPPQPosFromProjQN(take,eQN)
  for _,m in ipairs(pitches) do 
    -- DEBUG: Log each individual note insertion
    local debug_file = io.open("/tmp/cuco_debug.log", "a")
    if debug_file then
      debug_file:write("[MIDI_INSERT] Inserting MIDI note " .. tostring(m) .. " at PPQ " .. tostring(sPPQ) .. "-" .. tostring(ePPQ) .. "\n")
      debug_file:flush()
      debug_file:close()
    end
    reaper.MIDI_InsertNote(take,false,false,sPPQ,ePPQ,ch or DEFAULT_CH,m,vel or DEFAULT_VEL,false) 
  end
end
local function compute_step_qn_or_fallback(take, stepQN_opt, step_count)
  if stepQN_opt then return stepQN_opt end
  step_count=math.max(1, tonumber(step_count) or 1)
  local _,_,sQN,eQN=get_item_pos_info(take); local itemLenQN=math.max(1e-6, eQN-sQN)
  return itemLenQN/step_count
end

-------------------------------------------------------------------------------
-- Token span calculation (shared by executor and scheduler)
-------------------------------------------------------------------------------
local function token_arp_span(tok)
  local function unwrap(t)
    while type(t) == 'table' and (t.kind == 'transpose' or t.kind == 'repeat') do t = t.inner end
    return t
  end
  local t = unwrap(tok)
  -- Scale tokens don't take up rhythmic space
  if type(t) == 'table' and t.kind == 'scale' then
    return 0
  end
  -- For arp processors, always return 1 to respect the ~4 subdivision setting
  -- The span parameter should not affect subdivision size, only internal timing within the subdivision
  if type(t) == 'table' and t.kind == 'stack' and t.procs and t.procs[1] and t.procs[1].name == 'arp' then
    return 1
  end
  if type(t) == 'table' and t.kind == 'xref' and t.procs and t.procs[1] and t.procs[1].name == 'arp' then
    return 1
  end
  if type(t) == 'table' and t.kind == 'loop' then
    -- total span units of a loop body = sum of child spans
    local total = 0
    for _,inner_t in ipairs(t.entries or {}) do
      total = total + token_arp_span(inner_t)
    end
    local loop_body_span = math.max(1, total)
    return loop_body_span * math.max(1, tonumber(t.n) or 1)
  end
  return 1
end

-------------------------------------------------------------------------------
-- Executor builder (supports write/plan; stacks; repeats; PLAN tracing)
-------------------------------------------------------------------------------
local function make_executor(take, default_pitch, last_voices, voice_current, mode, recorder, trace)
  -- Anchor pitch for top-level inherit; set by real notes only (not by x)
  local anchor_pitch = nil
  -- Anchor voices (baked chord) for external x / x±N
  local anchor_voices = {}
  local function dlog(fmt, ...)
    if trace then logln(string.format(fmt, ...)) end
  end
  local function rec_emit(voice,pitch,sQN,eQN) if recorder then recorder(voice,pitch,sQN,eQN) end end
  local function start_voice(i,pitch,sQN,eQN)
    if mode=="plan" then dlog("PLAN start v%d %d %.3f→%.3f", i, pitch, sQN, eQN) end
    voice_current[i]={pitch=pitch,startQN=sQN,endQN=eQN}
  end
  local function flush_voice(i)
    local blk=voice_current[i]; if blk then
      if mode=="plan" then dlog("PLAN close v%d %d %.3f→%.3f", i, blk.pitch, blk.startQN, blk.endQN) end
      if mode=="write" then insert_notes(take,{blk.pitch},blk.startQN,blk.endQN,DEFAULT_VEL,DEFAULT_CH) else rec_emit(i,blk.pitch,blk.startQN,blk.endQN) end
      voice_current[i]=nil
    end
  end
  local function flush_all()
    for i,blk in pairs(voice_current) do
      if blk then
        if mode=="plan" then dlog("PLAN close v%d %d %.3f→%.3f", i, blk.pitch, blk.startQN, blk.endQN) end
        if mode=="write" then insert_notes(take,{blk.pitch},blk.startQN,blk.endQN,DEFAULT_VEL,DEFAULT_CH) else rec_emit(i,blk.pitch,blk.startQN,blk.endQN) end
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

    -- (group) removed in CUCO Stacks

    if type(tok)=="table" and tok.kind=="loop" then
      local N = math.max(1, tonumber(tok.n) or 1)
      if N <= 0 then N = 1 end
      if N == 1 then
        -- execute contents once across the whole window
        local sliceLen = (eQN - sQN)
        local cur = sQN
        -- calculate total span of loop body
        local total_body_span = 0
        for _,innerTok in ipairs(tok.entries or {}) do
          total_body_span = total_body_span + token_arp_span(innerTok)
        end
        total_body_span = math.max(1, total_body_span)
        for _,innerTok in ipairs(tok.entries or {}) do
          local span = token_arp_span(innerTok)
          local eSub = cur + sliceLen * (span / total_body_span)
          exec_window(innerTok, cur, eSub, tp_offset)
          cur = eSub
        end
        return
      end
      -- Divide the window into N passes; each pass plays the loop body once
      -- Save current scale state before loop
      local saved_scale = {
        root = current_scale.root,
        intervals = current_scale.intervals,
        quantize = current_scale.quantize
      }
      local passLen = (eQN - sQN) / N
      for pass=1,N do
        -- Restore scale state at start of each iteration
        current_scale.root = saved_scale.root
        current_scale.intervals = saved_scale.intervals
        current_scale.quantize = saved_scale.quantize
        
        local sPass = sQN + (pass-1)*passLen
        local ePass = sPass + passLen
        local cur = sPass
        -- calculate total span of loop body
        local total_body_span = 0
        for _,innerTok in ipairs(tok.entries or {}) do
          total_body_span = total_body_span + token_arp_span(innerTok)
        end
        total_body_span = math.max(1, total_body_span)
        for _,innerTok in ipairs(tok.entries or {}) do
          local span = token_arp_span(innerTok)
          local eSub = cur + passLen * (span / total_body_span)
          exec_window(innerTok, cur, eSub, tp_offset)
          cur = eSub
        end
      end
      -- Restore scale state after loop (scale changes inside loop don't persist)
      current_scale.root = saved_scale.root
      current_scale.intervals = saved_scale.intervals
      current_scale.quantize = saved_scale.quantize
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
    
    -- DEBUG: Log which token is being executed
    local debug_file = io.open("/tmp/cuco_debug.log", "a")
    if debug_file then
      debug_file:write("[EXEC_TOKEN] Processing token: '" .. tostring(tok) .. "' (type: " .. type(tok) .. ")\n")
      if type(tok) == "table" then
        debug_file:write("[EXEC_TOKEN] Token kind: " .. tostring(tok.kind) .. "\n")
      end
      debug_file:flush()
      debug_file:close()
    end

    -- Handle scale tokens directly in the executor by updating the current scale context
    if type(tok)=="table" and tok.kind=="scale" then
      apply_scale_context(tok.scale_ctx)
      if trace then
        local scale_name = ""
        for name, intervals in pairs(SCALES) do
          if intervals == current_scale.intervals then scale_name = name; break end
        end
        dlog("[SCALE-UPDATE] root=%s scale=%s quantize=%s", 
          PC_NAME[current_scale.root] or tostring(current_scale.root),
          scale_name,
          current_scale.quantize)
      end
      return
    end

    -- Inherit with offset: use baked chord (anchor_voices) if available; else single anchor pitch
    if type(tok)=="table" and tok.kind=="inherit" then
      local offset = (tonumber(tok.n) or 0) + (tp_offset or 0)
      -- If this is a processed inherit (X^) or processors are attached or available from last stack,
      -- treat it like X/X^ with possible processors.
      local want_procs = (tok.processed == true) or (tok.procs ~= nil)
      local base_chord = {}
      if last_stack_ctx and last_stack_ctx.chord and #last_stack_ctx.chord > 0 then
        for _,p in ipairs(last_stack_ctx.chord) do if p then table.insert(base_chord, p) end end
      else
        if anchor_voices and #anchor_voices > 0 then
          for _,p in ipairs(anchor_voices) do if p then table.insert(base_chord, p) end end
        else
          for _,p in ipairs(last_voices) do if p then table.insert(base_chord, p) end end
        end
      end
      if #base_chord > 0 then
        for i2=1,#base_chord do base_chord[i2] = base_chord[i2] + offset end
      end
      local apply_procs = tok.procs
      if (tok.processed == true) and (not apply_procs) and last_stack_ctx and last_stack_ctx.procs then
        apply_procs = last_stack_ctx.procs
      end
      if want_procs and apply_procs and #apply_procs > 0 and apply_procs[1].name == 'arp' then
        flush_all()
        local proc = apply_procs[1]
        local chord = {}
        for _,p in ipairs(base_chord) do table.insert(chord,p) end
        local dir = proc.dir or 'up'
        local N = tonumber(proc.n or 0) or 0
        local S = math.max(1, tonumber(proc.span or 1) or 1)
        local loop = (proc.loop ~= false)
        if N <= 0 then N = math.max(1,#chord) end
          -- Build playback order according to dir/k (original simpler set)
          local function build_order(ch)
            local m = #ch
            local order = {}
            if m == 0 then return order end
            local d = dir
            local k = tonumber(proc.k or 0) or 0
            if d=='down' then
              table.sort(ch, function(a,b) return a>b end)
              for i=1,m do order[#order+1] = ch[i] end
            elseif d=='up' then
              table.sort(ch, function(a,b) return a<b end)
              for i=1,m do order[#order+1] = ch[i] end
            elseif d=='rand' or d=='random' then
              local tmp = {table.unpack(ch)}
              for i=m,2,-1 do local j=math.random(i); tmp[i],tmp[j]=tmp[j],tmp[i] end
              for i=1,m do order[#order+1] = tmp[i] end
            elseif d=='updown' then
              table.sort(ch, function(a,b) return a<b end)
              for i=1,m do order[#order+1] = ch[i] end
              for i=m,1,-1 do order[#order+1] = ch[i] end
            elseif d=='pend' then
              table.sort(ch, function(a,b) return a<b end)
              for i=1,m do order[#order+1] = ch[i] end
              for i=m-1,2,-1 do order[#order+1] = ch[i] end
            elseif d=='io' then
              table.sort(ch, function(a,b) return a<b end)
              local midL = math.floor((m+1)/2)
              local midR = (m%2==0) and (midL+1) or midL
              local iL, iR = midL, midR
              order[#order+1] = ch[iL]
              if iR~=iL then order[#order+1] = ch[iR] end
              local step=1
              while (iL-step)>=1 or (iR+step)<=m do
                if (iL-step)>=1 then order[#order+1] = ch[iL-step] end
                if (iR+step)<=m then order[#order+1] = ch[iR+step] end
                step=step+1
              end
            elseif d=='oi' or d=='zz' then
              table.sort(ch, function(a,b) return a<b end)
              local l, r = 1, m
              while l<r do
                order[#order+1] = ch[l]
                if l~=r then order[#order+1] = ch[r] end
                l=l+1; r=r-1
              end
            elseif d=='skip' then
              table.sort(ch, function(a,b) return a<b end)
              local step = (k and k>0) and k or 2
              local visited = {}
              local idx = 1
              for _=1,m do
                order[#order+1] = ch[idx]
                visited[idx]=true
                idx = ((idx-1 + step) % m) + 1
                local guard=0
                while visited[idx] and guard<m do idx = (idx % m)+1; guard=guard+1 end
              end
            elseif d=='rotate' then
              table.sort(ch, function(a,b) return a<b end)
              local rot = (k or 0) % m
              for i=1,m do
                order[#order+1] = ch[((rot + i -1) % m) + 1]
              end
            else
              table.sort(ch, function(a,b) return a<b end)
              for i=1,m do order[#order+1] = ch[i] end
            end
            return order
          end
          local order = build_order(chord)
          if #order>0 then
            local totalLen=(eQN-sQN)
            local sliceLen=totalLen/N
            for idx=1,N do
              local sSub=sQN+(idx-1)*sliceLen
              local eSub=sSub+sliceLen
              local p=nil
              if loop then p = order[((idx-1)%#order)+1] else if idx<=#order then p=order[idx] end end
              if p then
                if mode=="write" then insert_notes(take,{p},sSub,eSub,DEFAULT_VEL,DEFAULT_CH) else rec_emit(1,p,sSub,eSub) end
              end
            end
          end
        -- Update anchors based on mirrored/processed chord
        anchor_voices = {}
        for i2=1,#base_chord do anchor_voices[i2]=base_chord[i2] end
        if anchor_voices[1] then anchor_pitch=anchor_voices[1] end
        return
      end

      -- Fallback: mirror chord behavior (legacy X)
      flush_all()
      if anchor_voices and #anchor_voices > 0 then
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
      -- If processors attached, resolve chord and process (currently supports !arp)
      if tok.procs and #tok.procs > 0 then
        local chord = {}
        for i,entry in ipairs(entries) do
          local p = nil
          if type(entry) == 'string' then
            local el = entry:lower()
            if el == '.' or el == '-' then
              p = nil -- rest marker
            elseif el == '_' then
              p = (voice_current[i] and voice_current[i].pitch) or last_voices[i]
            elseif el == 'x' or el == 'x^' or el:match('^x[%^]?[+-]%d+$') then
              local off = 0
              local m1 = el:match('^x%^([+-]%d+)$')
              local m2 = el:match('^x([+-]%d+)$')
              if m1 then off = tonumber(m1) or 0 elseif m2 then off = tonumber(m2) or 0 end
              -- Look left in current stack for the first REAL NOTE SOURCE (actual notes only, not x tokens)
              local left = nil
              for j = i-1, 1, -1 do
                local entry_j = entries[j]
                if entry_j and type(entry_j) == "string" then
                  local el_j = entry_j:lower()
                  -- Only consider actual note sources, not x tokens or other symbols
                  if not (el_j == "." or el_j == "_" or el_j:match("^x[%^]?[+-]?%d*$") or el_j:match("^[+-]%d+$")) then
                    -- This is a real note source
                    if new_last[j] then left = new_last[j]; break end
                  end
                end
              end
              local base = left or last_voices[i] or anchor_pitch or default_pitch
              if base then p = base + (tp_offset or 0) + off end
              -- Debug chord building
              if trace then
                dlog("CHORD BUILD pos %d: %s off=%d left=%s base=%s result=%s", 
                  i, el, off, tostring(left), tostring(base), tostring(p))
              end
            elseif el:match('^[+-]%d+$') then
              local delta = tonumber(el) or 0
              local left = nil
              for j = i-1, 1, -1 do if new_last[j] then left = new_last[j]; break end end
              if left then
                p = left + delta
              else
                local base = last_voices[i] or anchor_pitch or default_pitch
                if base then p = base + (tp_offset or 0) + delta end
              end
            else
              local b, off = entry:match('^([a-gA-G][b#]?%-?%d+)([+-]%d+)$')
              if b and off then
                p = note_to_midi(b)
                if p then p = p + (tp_offset or 0) + (tonumber(off) or 0) end
              else
                p = note_to_midi(entry)
                if p then p = p + (tp_offset or 0) end
              end
            end
          end
          new_last[i] = p
        end
        
        -- Build the chord array explicitly to ensure all positions are included
        local chord_length = #entries  -- Track chord length manually since # operator fails with nils
        for i = 1, #entries do
          chord[i] = new_last[i]  -- This includes both notes and nils (rests)
        end
        chord.count = chord_length  -- Store the actual count
        
        -- Apply first processor: arp or poly
        local proc = tok.procs[1]
        if proc and proc.name == 'poly' then
          -- Euclidean polyrhythm processor
          local subdivisions = proc.subdivisions or {}
          local totalLen = (eQN - sQN)
          
          -- Default to 16 steps if not specified
          local total_steps = 16
          
          dlog("POLY processor: %d voices, %d total steps", #subdivisions, total_steps)
          
          -- Generate euclidean patterns for each voice
          for voice_idx = 1, #entries do
            local pitch = new_last[voice_idx]
            if pitch then  -- Only process actual notes, not rests
              local hits = subdivisions[voice_idx] or 1  -- Default to 1 hit if not specified
              local pattern = euclidean_rhythm(hits, total_steps)
              
              dlog("Voice %d (pitch %d): %d hits in %d steps", voice_idx, pitch, hits, total_steps)
              
              -- Generate notes based on euclidean pattern
              local step_duration = totalLen / total_steps
              for step = 1, total_steps do
                if pattern[step] then  -- Hit on this step
                  local step_start = sQN + (step - 1) * step_duration
                  local step_end = step_start + step_duration
                  if mode=="write" then
                    insert_notes(take, {pitch}, step_start, step_end, DEFAULT_VEL, DEFAULT_CH)
                  else
                    rec_emit(voice_idx, pitch, step_start, step_end)
                  end
                end
              end
            end
          end
          
          -- Update last/anchor voices
          set_last_from_array(new_last)
          anchor_voices = {}
          for i=1,#new_last do anchor_voices[i] = new_last[i] end
          if anchor_voices[1] then anchor_pitch = anchor_voices[1] end
          
          -- Remember last stack context for X/X^ sourcing
          last_stack_ctx = { chord = {}, procs = tok.procs }
          for _,p in ipairs(chord) do table.insert(last_stack_ctx.chord, p) end
          dlog("POLY stack captured chord n=%d first=%s", #last_stack_ctx.chord, tostring(last_stack_ctx.chord[1] or 'nil'))
          return
          
        elseif proc and proc.name == 'arp' then
          local dir = (proc.dir or 'up')
          local N = tonumber(proc.n or 0) or 0
          local S = math.max(1, tonumber(proc.span or 1) or 1)
          local loop = (proc.loop ~= false) -- default true
          if N <= 0 then N = math.max(1, chord_length) end  -- Use manual count instead of #chord
          -- Debug: show what's in chord (use manual count to show all positions)
          if trace then
            local chord_debug = {}
            for i = 1, chord_length do  -- Use chord_length instead of #chord
              chord_debug[i] = (chord[i] and tostring(chord[i])) or 'REST'
            end
            dlog("CHORD DEBUG: [%s] (%d elements)", table.concat(chord_debug, ', '), chord_length)
          end
          -- Build playback order according to dir/k
          local function build_order(ch)
            local m = #ch
            local order = {}
            if m == 0 then return order end
            local d = dir
            local k = tonumber(proc.k or 0) or 0
            
            -- Check if there are any rests in the original chord (use manual count)
            local chord_has_rests = false
            local ch_count = ch.count or #ch  -- Use manual count if available
            for i = 1, ch_count do
              if trace then
                dlog("REST CHECK pos %d: value=%s is_nil=%s", i, tostring(ch[i]), tostring(ch[i] == nil))
              end
              if ch[i] == nil then chord_has_rests = true; break end
            end
            if trace then
              dlog("CHORD_HAS_RESTS: %s (chord length %d)", tostring(chord_has_rests), ch_count)
            end
            
            if not chord_has_rests then
              -- No rests: use the existing pitched-notes-only logic
              local pitched_notes = {}
              for i = 1, #ch do
                local note = ch[i]
                if note then table.insert(pitched_notes, note) end
              end
              
              if d=='down' then
                table.sort(pitched_notes, function(a,b) return a > b end)
                for i=1,#pitched_notes do order[#order+1] = pitched_notes[i] end
              elseif d=='up' then
                table.sort(pitched_notes, function(a,b) return a < b end)
                for i=1,#pitched_notes do order[#order+1] = pitched_notes[i] end
              elseif d=='rand' or d=='random' then
                local tmp = {table.unpack(pitched_notes)}
                for i=#pitched_notes,2,-1 do local j=math.random(i); tmp[i],tmp[j]=tmp[j],tmp[i] end
                for i=1,#pitched_notes do order[#order+1] = tmp[i] end
              elseif d=='updown' then
                table.sort(pitched_notes, function(a,b) return a < b end)
                for i=1,#pitched_notes do order[#order+1] = pitched_notes[i] end
                for i=#pitched_notes,1,-1 do order[#order+1] = pitched_notes[i] end
              elseif d=='pend' then
                table.sort(pitched_notes, function(a,b) return a < b end)
                for i=1,#pitched_notes do order[#order+1] = pitched_notes[i] end
                for i=#pitched_notes-1,2,-1 do order[#order+1] = pitched_notes[i] end
              elseif d=='io' then
                table.sort(pitched_notes, function(a,b) return a < b end)
                local midL = math.floor((#pitched_notes+1)/2)
                local midR = (#pitched_notes%2==0) and (midL+1) or midL
                local iL, iR = midL, midR
                order[#order+1] = pitched_notes[iL]
                if iR~=iL and iR <= #pitched_notes then order[#order+1] = pitched_notes[iR] end
                local step=1
                while (iL-step)>=1 or (iR+step)<=#pitched_notes do
                  if (iL-step)>=1 then order[#order+1] = pitched_notes[iL-step] end
                  if (iR+step)<=#pitched_notes then order[#order+1] = pitched_notes[iR+step] end
                  step=step+1
                end
              elseif d=='oi' or d=='zz' then
                table.sort(pitched_notes, function(a,b) return a < b end)
                local l, r = 1, #pitched_notes
                while l<=r do
                  order[#order+1] = pitched_notes[l]
                  if l~=r then order[#order+1] = pitched_notes[r] end
                  l=l+1; r=r-1
                end
              elseif d=='skip' then
                table.sort(pitched_notes, function(a,b) return a < b end)
                local step = (k and k>0) and k or 2
                local visited = {}
                local idx = 1
                for _=1,#pitched_notes do
                  order[#order+1] = pitched_notes[idx]
                  visited[idx]=true
                  idx = ((idx-1 + step) % #pitched_notes) + 1
                  local guard=0
                  while visited[idx] and guard<#pitched_notes do idx = (idx % #pitched_notes)+1; guard=guard+1 end
                end
              elseif d=='rotate' then
                table.sort(pitched_notes, function(a,b) return a < b end)
                local rot = (k or 0) % #pitched_notes
                for i=1,#pitched_notes do
                  order[#order+1] = pitched_notes[((rot + i -1) % #pitched_notes) + 1]
                end
              else
                table.sort(pitched_notes, function(a,b) return a < b end)
                for i=1,#pitched_notes do order[#order+1] = pitched_notes[i] end
              end
            else
              -- Rests present: create arpeggio that properly interleaves rests
              -- Strategy: For each note in the arpeggio pattern, traverse the original
              -- chord structure around that note's position, including any rests
              
              -- First, extract the pitched notes with their original chord positions (use manual count)
              local pitched_entries = {}
              for i = 1, ch_count do
                if ch[i] then
                  pitched_entries[#pitched_entries + 1] = {pitch = ch[i], pos = i}
                end
              end
              
              -- Sort these entries by pitch according to direction
              if d=='down' then
                table.sort(pitched_entries, function(a,b) return a.pitch > b.pitch end)
              else -- up, pend, etc. - all start with ascending
                table.sort(pitched_entries, function(a,b) return a.pitch < b.pitch end)
              end
              
              -- Build the base arpeggio pattern (notes only)
              local arp_pattern = {}
              if d=='pend' then
                -- Pendulum: up then back down (excluding first/last duplicate)
                for i=1,#pitched_entries do arp_pattern[#arp_pattern+1] = pitched_entries[i] end
                for i=#pitched_entries-1,2,-1 do arp_pattern[#arp_pattern+1] = pitched_entries[i] end
              elseif d=='updown' then
                -- Up-down: up then all the way back down
                for i=1,#pitched_entries do arp_pattern[#arp_pattern+1] = pitched_entries[i] end
                for i=#pitched_entries,1,-1 do arp_pattern[#arp_pattern+1] = pitched_entries[i] end
              elseif d=='down' then
                -- Already sorted descending
                for i=1,#pitched_entries do arp_pattern[#arp_pattern+1] = pitched_entries[i] end
              elseif d=='io' then
                -- Inside-out: start from middle and work outwards
                local midL = math.floor((#pitched_entries+1)/2)
                local midR = (#pitched_entries%2==0) and (midL+1) or midL
                local iL, iR = midL, midR
                arp_pattern[#arp_pattern+1] = pitched_entries[iL]
                if iR~=iL and iR <= #pitched_entries then arp_pattern[#arp_pattern+1] = pitched_entries[iR] end
                local step=1
                while (iL-step)>=1 or (iR+step)<=#pitched_entries do
                  if (iL-step)>=1 then arp_pattern[#arp_pattern+1] = pitched_entries[iL-step] end
                  if (iR+step)<=#pitched_entries then arp_pattern[#arp_pattern+1] = pitched_entries[iR+step] end
                  step=step+1
                end
              elseif d=='oi' or d=='zz' then
                -- Outside-in/zigzag: alternate between lowest and highest
                local l, r = 1, #pitched_entries
                while l<=r do
                  arp_pattern[#arp_pattern+1] = pitched_entries[l]
                  if l~=r then arp_pattern[#arp_pattern+1] = pitched_entries[r] end
                  l=l+1; r=r-1
                end
              elseif d=='skip' then
                -- Skip pattern: step through with k interval
                local step = (k and k>0) and k or 2
                local visited = {}
                local idx = 1
                for _=1,#pitched_entries do
                  arp_pattern[#arp_pattern+1] = pitched_entries[idx]
                  visited[idx]=true
                  idx = ((idx-1 + step) % #pitched_entries) + 1
                  local guard=0
                  while visited[idx] and guard<#pitched_entries do idx = (idx % #pitched_entries)+1; guard=guard+1 end
                end
              elseif d=='rotate' then
                -- Rotate pattern: shift starting position by k
                local rot = (k or 0) % #pitched_entries
                for i=1,#pitched_entries do
                  arp_pattern[#arp_pattern+1] = pitched_entries[((rot + i -1) % #pitched_entries) + 1]
                end
              elseif d=='rand' or d=='random' then
                -- Random: shuffle the pitched entries
                local tmp = {table.unpack(pitched_entries)}
                for i=#pitched_entries,2,-1 do local j=math.random(i); tmp[i],tmp[j]=tmp[j],tmp[i] end
                for i=1,#pitched_entries do arp_pattern[#arp_pattern+1] = tmp[i] end
              else -- d=='up' or default
                -- Up: ascending order (already sorted)
                for i=1,#pitched_entries do arp_pattern[#arp_pattern+1] = pitched_entries[i] end
              end
              
              -- Debug: show the arp pattern
              if trace then
                local arp_debug = {}
                for i, entry in ipairs(arp_pattern) do
                  arp_debug[i] = string.format("%d@pos%d", entry.pitch, entry.pos)
                end
                dlog("ARP PATTERN: [%s] (%d elements)", table.concat(arp_debug, ', '), #arp_pattern)
              end
              
              -- Create arpeggio sequence that respects rest positions by creating gaps
              -- Strategy: For each position in the arpeggio pattern, check if it corresponds
              -- to a rest position in the original chord, and if so, insert nil for silence
              
              -- The key insight: we need to map arpeggio steps back to chord positions
              -- to preserve the rhythmic structure including rests
              
              -- Use a different approach: track order length manually since Lua arrays with nil holes are tricky
              local order_count = 0
              
              for i = 1, #arp_pattern do
                local entry = arp_pattern[i]
                local chord_pos = entry.pos  -- original position in chord
                
                -- Add the current note
                order_count = order_count + 1
                order[order_count] = entry.pitch
                
                -- Check for rest gaps between this note and the next one
                if i < #arp_pattern then
                  local next_entry = arp_pattern[i + 1]
                  local next_pos = next_entry.pos
                  
                  -- If there are rest positions between current and next note positions,
                  -- add nil entries to create gaps
                  for pos = chord_pos + 1, next_pos - 1 do
                    if ch[pos] == nil then
                      order_count = order_count + 1
                      order[order_count] = nil  -- This creates a silent gap
                      if trace then
                        dlog("ADDING REST GAP after pos %d (between %d and %d)", pos, chord_pos, next_pos)
                      end
                    end
                  end
                end
              end
              
              -- Store the actual count since #order won't work with nils
              order.count = order_count
              
              -- Debug: show the order with rests (use manual iteration to show nils)
              if trace then
                local final_debug = {}
                for i = 1, order_count do
                  final_debug[i] = (order[i] and tostring(order[i])) or 'REST'
                end
                dlog("FINAL ORDER (with rests): [%s] (%d elements)", table.concat(final_debug, ', '), order_count)
                dlog("NOTE: Rests create silent gaps in playback sequence")
              end
            end
            
            return order
          end
          local order = build_order(chord)
          -- Debug: show the built order (use stored count if available)
          if trace then
            local count_to_use = order.count or #order
            local order_debug = {}
            for i = 1, count_to_use do
              order_debug[i] = (order[i] and tostring(order[i])) or 'REST'
            end
            dlog("ORDER DEBUG: [%s] (%d elements)", table.concat(order_debug, ', '), count_to_use)
          end
          local count_to_use = order.count or #order
          if count_to_use > 0 then
            -- The subdivision size is fixed by the ~4 header (totalLen = eQN - sQN)
            -- N controls how many notes from the arpeggio pattern to play within that subdivision
            local totalLen = (eQN - sQN)
            local sliceLen = totalLen / N  -- Each note gets equal time within the subdivision
            for idx=1,N do
              local sSub = sQN + (idx-1)*sliceLen
              local eSub = sSub + sliceLen
              local p = nil
              if loop then
                p = order[((idx-1) % count_to_use) + 1]
              else
                if idx <= count_to_use then p = order[idx] end
              end
              -- Only emit notes for non-nil values (rests are silent)
              if p then
                if mode=="write" then insert_notes(take,{p},sSub,eSub,DEFAULT_VEL,DEFAULT_CH) else rec_emit(1,p,sSub,eSub) end
              end
              -- Note: when p is nil (rest), we simply skip emission, creating a gap
            end
          end
        end
        -- update last/anchor for downstream tokens
        set_last_from_array(new_last)
        anchor_voices = {}
        for i=1,#new_last do anchor_voices[i] = new_last[i] end
        if anchor_voices[1] then anchor_pitch = anchor_voices[1] end
        -- remember last stack context for X/X^ sourcing (use the resolved chord before any future X offsets)
        last_stack_ctx = { chord = {} , procs = tok.procs }
        for _,p in ipairs(chord) do table.insert(last_stack_ctx.chord, p) end
        dlog("STACK captured chord n=%d first=%s (with procs)", #last_stack_ctx.chord, tostring(last_stack_ctx.chord[1] or 'nil'))
        return
      end
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
          elseif el=="x" or el=="x^" or el:match("^x[%^]?[+-]%d+$") then
            -- In-stack inherit: look for the first REAL NOTE SOURCE (not x tokens) within this stack row (to the left),
            -- then fall back to same-slot from previous step, then anchor, then default.
            local off = 0
            local m1 = el:match("^x%^([+-]%d+)$")
            local m2 = el:match("^x([+-]%d+)$")
            if m1 then off = tonumber(m1) or 0 elseif m2 then off = tonumber(m2) or 0 end

            -- Look left in current stack for the first REAL NOTE SOURCE (actual notes only, not x tokens)
            local left = nil
            for j = i-1, 1, -1 do
              local entry_j = entries[j]
              if entry_j and type(entry_j) == "string" then
                local el_j = entry_j:lower()
                -- Only consider actual note sources, not x tokens or other symbols
                if not (el_j == "." or el_j == "_" or el_j:match("^x[%^]?[+-]?%d*$") or el_j:match("^[+-]%d+$")) then
                  -- This is a real note source
                  if new_last[j] then left = new_last[j]; break end
                end
              end
            end

            local prev_same_slot = last_voices[i]
            local base = left or prev_same_slot or anchor_pitch or default_pitch
            if base then
              local p = base + (tp_offset or 0) + off
              -- Apply scale quantization to in-stack x tokens
              -- DEBUG: Log scale quantization for x tokens
              local debug_file = io.open("/tmp/cuco_debug.log", "a")
              if debug_file then
                debug_file:write("[SCALE-QUANTIZE-X] Input MIDI: " .. tostring(p) .. " (x token)\n")
                debug_file:write("[SCALE-QUANTIZE-X] Scale root: " .. tostring(current_scale.root) .. "\n")
                debug_file:write("[SCALE-QUANTIZE-X] Scale intervals: " .. table.concat(current_scale.intervals, ",") .. "\n")
                debug_file:write("[SCALE-QUANTIZE-X] Quantize mode: " .. tostring(current_scale.quantize) .. "\n")
                debug_file:flush()
                debug_file:close()
              end
              
              local quantized = quantize_to_scale(p)
              
              -- DEBUG: Log the result
              local debug_file = io.open("/tmp/cuco_debug.log", "a")
              if debug_file then
                debug_file:write("[SCALE-QUANTIZE-X] Output MIDI: " .. tostring(quantized) .. "\n")
                debug_file:write("[SCALE-QUANTIZE-X] " .. (p == quantized and "UNCHANGED" or "CHANGED") .. "\n\n")
                debug_file:flush()
                debug_file:close()
              end
              
              if quantized then
                flush_voice(i)
                start_voice(i, quantized, sQN, eQN); new_last[i] = quantized
              else
                -- Note was filtered out by "ignore" mode
                flush_voice(i); new_last[i]=nil
              end
            else
              flush_voice(i); new_last[i]=nil
            end

          elseif el:match("^[+-]%d+$") then
            -- In-stack horizontal relative: +N / -N (relative to last resolved pitch in THIS stack)
            local delta = tonumber(el) or 0
            -- Look left for the most recent pitch we just resolved in this stack:
            local left = nil
            for j = i-1, 1, -1 do if new_last[j] then left = new_last[j]; break end end
            if left then
              -- left already includes tp_offset; don't add it again
              local p = left + delta
              flush_voice(i); start_voice(i, p, sQN, eQN); new_last[i] = p
            else
              -- fallback if no left pitch yet: use vertical/anchor/default, then apply tp_offset
              local base = last_voices[i] or anchor_pitch or default_pitch
              if base then
                local p = base + (tp_offset or 0) + delta
                flush_voice(i); start_voice(i, p, sQN, eQN); new_last[i] = p
              else
                flush_voice(i); new_last[i]=nil
              end
            end

          else
            -- Notes may have an in-stack ±N suffix: e.g., c3+2 / d4-1
            local b, off = entry:match("^([a-gA-G][b#]?%-?%d+)([+-]%d+)$")
            local m
            if b and off then
              m = note_to_midi(b)
              if m then m = m + (tp_offset or 0) + (tonumber(off) or 0) end
            else
              m = note_to_midi(entry)
              if m then m = m + (tp_offset or 0) end
            end
            -- Apply scale quantization if we have a MIDI note
            if m then
              -- DEBUG: Log scale quantization
              local debug_file = io.open("/tmp/cuco_debug.log", "a")
              if debug_file then
                debug_file:write("[SCALE-QUANTIZE] Input MIDI: " .. tostring(m) .. " (from note_to_midi)\n")
                debug_file:write("[SCALE-QUANTIZE] Scale root: " .. tostring(current_scale.root) .. "\n")
                debug_file:write("[SCALE-QUANTIZE] Scale intervals: " .. table.concat(current_scale.intervals, ",") .. "\n")
                debug_file:write("[SCALE-QUANTIZE] Quantize mode: " .. tostring(current_scale.quantize) .. "\n")
                debug_file:flush()
                debug_file:close()
              end
              
              local quantized = quantize_to_scale(m)
              
              -- DEBUG: Log the result
              local debug_file = io.open("/tmp/cuco_debug.log", "a")
              if debug_file then
                debug_file:write("[SCALE-QUANTIZE] Output MIDI: " .. tostring(quantized) .. "\n")
                debug_file:write("[SCALE-QUANTIZE] " .. (m == quantized and "UNCHANGED" or "CHANGED") .. "\n\n")
                debug_file:flush()
                debug_file:close()
              end
              
              if quantized then
                flush_voice(i)
                start_voice(i, quantized, sQN, eQN); new_last[i]=quantized
              else
                -- Note was filtered out by "ignore" mode
                flush_voice(i); new_last[i]=nil
              end
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
      -- Also capture last stack chord for X/X^ sourcing (preserve processors for X^ inheritance)
      last_stack_ctx = { chord = {}, procs = tok.procs }
      for i=1,#new_last do if new_last[i] then table.insert(last_stack_ctx.chord, new_last[i]) end end
      dlog("STACK captured chord n=%d first=%s procs=%s", #last_stack_ctx.chord, tostring(last_stack_ctx.chord[1] or 'nil'), (tok.procs and tok.procs[1] and tok.procs[1].name) or 'none')
      -- Groups removed: no replay anchor to clear

    else
      if type(tok) == "table" and tok.kind == 'xref' then
        -- Handle X/X^ references (with optional processors)
        flush_all()
        -- Determine base chord from previous stack context (always from the most recent stack)
        local base_chord = {}
        local src = 'empty'
        if last_stack_ctx and last_stack_ctx.chord and #last_stack_ctx.chord > 0 then
          for _,p in ipairs(last_stack_ctx.chord) do if p then table.insert(base_chord, p) end end
          src = 'stack'
        else
          -- Fallbacks if no stack context was captured (should be rare)
          if anchor_voices and #anchor_voices > 0 then
            for _,p in ipairs(anchor_voices) do if p then table.insert(base_chord,p) end end
            src = 'anchor'
          else
            for _,p in ipairs(last_voices) do if p then table.insert(base_chord,p) end end
            if #base_chord > 0 then src = 'last' end
          end
        end
        -- Apply offset and tp_offset
        local offset = (tonumber(tok.n) or 0) + (tp_offset or 0)
        for i2=1,#base_chord do base_chord[i2] = base_chord[i2] + offset end

        -- Determine processors to apply
        local apply_procs = tok.procs
        if tok.inherit and (not apply_procs) and last_stack_ctx and last_stack_ctx.procs then
          apply_procs = last_stack_ctx.procs
        end
        dlog("XREF src=%s chord=%d procs=%s", src, #base_chord, (apply_procs and apply_procs[1] and apply_procs[1].name) or 'none')

        if apply_procs and #apply_procs > 0 and apply_procs[1].name == 'arp' then
          local proc = apply_procs[1]
          local chord = {}
          for _,p in ipairs(base_chord) do table.insert(chord,p) end
          local dir = proc.dir or 'up'
          local N = tonumber(proc.n or 0) or 0
          local S = math.max(1, tonumber(proc.span or 1) or 1)
          local loop = (proc.loop ~= false)
          if N <= 0 then N = math.max(1,#chord) end
          -- Build playback order according to dir/k (original simpler set)
          local function build_order(ch)
            local m = #ch
            local order = {}
            if m == 0 then return order end
            local d = dir
            local k = tonumber(proc.k or 0) or 0
            if d=='down' then
              table.sort(ch, function(a,b) return a>b end)
              for i=1,m do order[#order+1] = ch[i] end
            elseif d=='up' then
              table.sort(ch, function(a,b) return a<b end)
              for i=1,m do order[#order+1] = ch[i] end
            elseif d=='rand' or d=='random' then
              local tmp = {table.unpack(ch)}
              for i=m,2,-1 do local j=math.random(i); tmp[i],tmp[j]=tmp[j],tmp[i] end
              for i=1,m do order[#order+1] = tmp[i] end
            elseif d=='updown' then
              table.sort(ch, function(a,b) return a<b end)
              for i=1,m do order[#order+1] = ch[i] end
              for i=m,1,-1 do order[#order+1] = ch[i] end
            elseif d=='pend' then
              table.sort(ch, function(a,b) return a<b end)
              for i=1,m do order[#order+1] = ch[i] end
              for i=m-1,2,-1 do order[#order+1] = ch[i] end
            elseif d=='io' then
              table.sort(ch, function(a,b) return a<b end)
              local midL = math.floor((m+1)/2)
              local midR = (m%2==0) and (midL+1) or midL
              local iL, iR = midL, midR
              order[#order+1] = ch[iL]
              if iR~=iL then order[#order+1] = ch[iR] end
              local step=1
              while (iL-step)>=1 or (iR+step)<=m do
                if (iL-step)>=1 then order[#order+1] = ch[iL-step] end
                if (iR+step)<=m then order[#order+1] = ch[iR+step] end
                step=step+1
              end
            elseif d=='oi' or d=='zz' then
              table.sort(ch, function(a,b) return a<b end)
              local l, r = 1, m
              while l<r do
                order[#order+1] = ch[l]
                if l~=r then order[#order+1] = ch[r] end
                l=l+1; r=r-1
              end
            elseif d=='skip' then
              table.sort(ch, function(a,b) return a<b end)
              local step = (k and k>0) and k or 2
              local visited = {}
              local idx = 1
              for _=1,m do
                order[#order+1] = ch[idx]
                visited[idx]=true
                idx = ((idx-1 + step) % m) + 1
                local guard=0
                while visited[idx] and guard<m do idx = (idx % m)+1; guard=guard+1 end
              end
            elseif d=='rotate' then
              table.sort(ch, function(a,b) return a<b end)
              local rot = (k or 0) % m
              for i=1,m do
                order[#order+1] = ch[((rot + i -1) % m) + 1]
              end
            else
              table.sort(ch, function(a,b) return a<b end)
              for i=1,m do order[#order+1] = ch[i] end
            end
            return order
          end
          local order = build_order(chord)
          if #order>0 then
            dlog("XREF processors path: arp dir=%s n=%d chord=%d", tostring(dir), N, #chord)
            local totalLen=(eQN-sQN)
            local sliceLen=totalLen/N
            for idx=1,N do
              local sSub=sQN+(idx-1)*sliceLen
              local eSub=sSub+sliceLen
              local p=nil
              if loop then p = order[((idx-1)%#order)+1] else if idx<=#order then p=order[idx] end end
              if p then
                if mode=="write" then insert_notes(take,{p},sSub,eSub,DEFAULT_VEL,DEFAULT_CH) else rec_emit(1,p,sSub,eSub) end
              end
            end
          end
        else
          -- No processors: mirror chord across window with scale quantization
          if #base_chord>0 then
            dlog("XREF mirror path: chord=%d", #base_chord)
            local quantized_chord = {}
            for _,p in ipairs(base_chord) do
              local quantized = quantize_to_scale(p)
              if quantized then
                quantized_chord[#quantized_chord + 1] = quantized
                if mode=="write" then insert_notes(take,{quantized},sQN,eQN,DEFAULT_VEL,DEFAULT_CH) else rec_emit(1,quantized,sQN,eQN) end
              end
            end
            -- Update base_chord to reflect quantized values for anchor updates
            base_chord = quantized_chord
          else
            -- fallback: default pitch with scale quantization
            local m = default_pitch + (tp_offset or 0) + (tonumber(tok.n) or 0)
            local quantized = quantize_to_scale(m)
            if quantized then
              start_voice(1,quantized,sQN,eQN); last_voices[1]=quantized
              base_chord = {quantized}  -- Update base_chord for anchor
            else
              start_voice(1,m,sQN,eQN); last_voices[1]=m
              base_chord = {m}  -- Update base_chord for anchor
            end
          end
        end
        -- Update anchors based on mirrored chord
        anchor_voices = {}
        for i2=1,#base_chord do anchor_voices[i2]=base_chord[i2] end
        if anchor_voices[1] then anchor_pitch=anchor_voices[1] end
      elseif type(tok) == "string" then
        local tl=tok:lower()
        if tl=="." then
          flush_all()
        elseif tl=="_" then
          extend_all(eQN)
        elseif tl=="x" then
          flush_all()
          -- Reference the most recent source (same logic as X tokens)
          local base_chord = {}
          local src = 'empty'
          if last_stack_ctx and last_stack_ctx.chord and #last_stack_ctx.chord > 0 then
            for _,p in ipairs(last_stack_ctx.chord) do if p then table.insert(base_chord, p) end end
            src = 'stack'
          else
            -- Fallbacks if no stack context was captured
            if anchor_voices and #anchor_voices > 0 then
              for _,p in ipairs(anchor_voices) do if p then table.insert(base_chord,p) end end
              src = 'anchor'
            else
              for _,p in ipairs(last_voices) do if p then table.insert(base_chord,p) end end
              if #base_chord > 0 then src = 'last' end
            end
          end
          dlog("X/x src=%s chord=%d", src, #base_chord)
          
          if #base_chord>0 then
            local quantized_chord = {}
            for _,p in ipairs(base_chord) do
              local quantized = quantize_to_scale(p)
              if quantized then
                quantized_chord[#quantized_chord + 1] = quantized
                if mode=="write" then insert_notes(take,{quantized},sQN,eQN,DEFAULT_VEL,DEFAULT_CH) else rec_emit(1,quantized,sQN,eQN) end
              end
            end
            -- Update anchors based on mirrored chord
            anchor_voices = {}
            for i2=1,#quantized_chord do anchor_voices[i2]=quantized_chord[i2] end
            if anchor_voices[1] then anchor_pitch=anchor_voices[1] end
          else
            -- fallback: default pitch with scale quantization
            local quantized = quantize_to_scale(default_pitch)
            if quantized then
              start_voice(1,quantized,sQN,eQN)
              last_voices[1]=quantized; for i=2,#last_voices do last_voices[i]=nil end
              anchor_voices = { quantized }
              anchor_pitch = quantized
            else
              start_voice(1,default_pitch,sQN,eQN)
              last_voices[1]=default_pitch; for i=2,#last_voices do last_voices[i]=nil end
              anchor_voices = { default_pitch }
              anchor_pitch = default_pitch
            end
          end
        else
          -- Debug: Log what token the executor receives
          local debug_file = io.open("/tmp/cuco_debug.log", "a")
          if debug_file then
            debug_file:write("[EXECUTOR] Processing token: '" .. tostring(tok) .. "'\n")
            debug_file:close()
          end
          
          local m=note_to_midi(tok)
          if m then
            m = m + tp_offset
            
            -- DEBUG: Log scale quantization for standalone note tokens (FILE + CONSOLE)
            local scale_intervals = table.concat(current_scale.intervals, ",")
            local debug_msg = "[SCALE-QUANTIZATION] Input: " .. tostring(m) .. " scale: (" .. scale_intervals .. ") mode: " .. tostring(current_scale.quantize)
            local debug_file = io.open("/tmp/cuco_debug.log", "a")
            if debug_file then
              debug_file:write(debug_msg .. "\n")
              debug_file:flush()
              debug_file:close()
            end
            logln(debug_msg)
            
            -- Apply scale quantization only when explicitly requested via scale notation
            local quantized
            if current_scale.explicit then
              -- Explicit scale context - apply quantization
              quantized = quantize_to_scale(m)
            else
              -- No explicit scale context - preserve accidentals as-is
              quantized = m
            end
            
            -- DEBUG: Log the result (FILE + CONSOLE)
            local result_msg = "[SCALE-QUANTIZATION] Result: " .. tostring(quantized) .. " " .. (m == quantized and "(UNCHANGED)" or "(CHANGED!)")
            local debug_file = io.open("/tmp/cuco_debug.log", "a")
            if debug_file then
              debug_file:write(result_msg .. "\n\n")
              debug_file:flush()
              debug_file:close()
            end
            logln(result_msg)
            
            if quantized then
              flush_all()
              start_voice(1,quantized,sQN,eQN)
              last_voices[1]=quantized
              for i=2,#last_voices do last_voices[i]=nil end
              anchor_pitch  = quantized
              anchor_voices = { quantized }
            end
          end
        end
      end
    end
  end

  return exec_window
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
  -- Groups removed: every token occupies one bin
  out_bins[#out_bins+1] = { s=sQN, e=eQN, plan={}, actual={}, trace={} }
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
-- Scale region tracking and post-processing quantization
-------------------------------------------------------------------------------
-- Flatten nested tokens to extract all scale tokens and their positions
local function flatten_tokens_with_scales(tokens)
  local flat_tokens = {}
  local position = 0
  
  local function flatten_recursive(token_list, pos_offset)
    local current_pos = pos_offset
    
    for _, token in ipairs(token_list) do
      if type(token) == "table" then
        if token.kind == "scale" then
          -- Scale token - add to flat list with position
          flat_tokens[#flat_tokens + 1] = {
            type = "scale",
            position = current_pos,
            scale_ctx = token.scale_ctx,
            spec = token.spec
          }
        elseif token.kind == "loop" then
          -- Loop: flatten its entries and replicate for each loop iteration
          local loop_count = math.max(1, tonumber(token.n) or 1)
          local loop_entries = token.entries or {}
          
          -- Calculate span of one loop iteration
          local loop_body_span = 0
          for _, entry in ipairs(loop_entries) do
            loop_body_span = loop_body_span + token_arp_span(entry)
          end
          loop_body_span = math.max(1, loop_body_span)
          
          -- Process each loop iteration
          for loop_iter = 1, loop_count do
            local iter_start = current_pos + (loop_iter - 1) * loop_body_span
            flatten_recursive(loop_entries, iter_start)
          end
          
          current_pos = current_pos + loop_count * loop_body_span
        elseif token.kind == "repeat" then
          -- Repeat: flatten inner token and replicate
          local repeat_count = math.max(1, tonumber(token.n) or 1)
          local inner_span = token_arp_span(token.inner)
          
          for rep_iter = 1, repeat_count do
            local iter_start = current_pos + (rep_iter - 1) * inner_span
            if type(token.inner) == "table" then
              flatten_recursive({token.inner}, iter_start)
            else
              -- String token, add as regular token
              flat_tokens[#flat_tokens + 1] = {
                type = "token",
                position = iter_start,
                token = token.inner,
                span = inner_span
              }
            end
          end
          
          current_pos = current_pos + repeat_count * inner_span
        else
          -- Regular token (stack, transpose, etc.)
          local span = token_arp_span(token)
          flat_tokens[#flat_tokens + 1] = {
            type = "token",
            position = current_pos,
            token = token,
            span = span
          }
          current_pos = current_pos + span
        end
      else
        -- String token
        local span = token_arp_span(token)
        flat_tokens[#flat_tokens + 1] = {
          type = "token",
          position = current_pos,
          token = token,
          span = span
        }
        current_pos = current_pos + span
      end
    end
    
    return current_pos
  end
  
  flatten_recursive(tokens, 0)
  
  -- Sort by position to ensure proper order
  table.sort(flat_tokens, function(a, b) return a.position < b.position end)
  
  return flat_tokens
end

local function split_tokens_by_scale_regions(tokens, initial_scale_ctx)
  -- Get flattened tokens with scale positions
  local flat_tokens = flatten_tokens_with_scales(tokens)
  
  local regions = {}
  local current_ctx = initial_scale_ctx or current_scale
  local region_tokens = {}
  local current_region_start = 0
  
  -- Process flattened tokens to create regions
  for _, flat_item in ipairs(flat_tokens) do
    if flat_item.type == "scale" then
      -- End current region if it has tokens
      if #region_tokens > 0 then
        regions[#regions + 1] = {
          scale_ctx = current_ctx,
          tokens = region_tokens,
          start_pos = current_region_start,
          end_pos = flat_item.position
        }
        region_tokens = {}
      end
      -- Update scale context and start new region
      current_ctx = flat_item.scale_ctx
      current_region_start = flat_item.position
    elseif flat_item.type == "token" then
      -- Only add non-scale tokens to region
      region_tokens[#region_tokens + 1] = flat_item.token
    end
  end
  
  -- Add final region if it has tokens
  if #region_tokens > 0 then
    regions[#regions + 1] = {
      scale_ctx = current_ctx,
      tokens = region_tokens,
      start_pos = current_region_start,
      end_pos = math.huge -- end of sequence
    }
  end
  
  -- If no regions were created, create one with all tokens
  if #regions == 0 then
    local all_tokens = {}
    for _, flat_item in ipairs(flat_tokens) do
      if flat_item.type == "token" then
        all_tokens[#all_tokens + 1] = flat_item.token
      end
    end
    if #all_tokens > 0 then
      regions[#regions + 1] = {
        scale_ctx = current_ctx,
        tokens = all_tokens,
        start_pos = 0,
        end_pos = math.huge
      }
    end
  end
  
  return regions
end

local function apply_scale_quantization_to_notes(notes, scale_ctx)
  local quantized_notes = {}
  local old_scale = {
    root = current_scale.root,
    intervals = current_scale.intervals,
    quantize = current_scale.quantize
  }
  
  -- Temporarily apply scale context
  current_scale.root = scale_ctx.root
  current_scale.intervals = scale_ctx.intervals
  current_scale.quantize = scale_ctx.quantize
  
  for _, note in ipairs(notes) do
    local quantized = quantize_to_scale(note.pitch)
    if quantized then
      quantized_notes[#quantized_notes + 1] = {
        pitch = quantized,
        startQN = note.startQN,
        endQN = note.endQN,
        vel = note.vel or DEFAULT_VEL,
        ch = note.ch or DEFAULT_CH
      }
    end
  end
  
  -- Restore original scale
  current_scale.root = old_scale.root
  current_scale.intervals = old_scale.intervals
  current_scale.quantize = old_scale.quantize
  
  return quantized_notes
end

-------------------------------------------------------------------------------
-- Process up to repeats (with optional debug)
-------------------------------------------------------------------------------
local function process_notation_step24(take, name)
  -- Debug: log what name is received
  local debug_file = io.open("/tmp/cuco_debug.log", "a")
  if debug_file then
    debug_file:write(string.format("\n=== PROCESS START ===\n[PROCESS] name='%s'\n", name or "nil"))
    debug_file:flush()
    debug_file:close()
  end
  local flags = parse_flags(name)
  local stepQN_opt, scale_ctx, _, body_clean = parse_step_header(name)
  
  -- Apply scale context if provided
  if scale_ctx then
    apply_scale_context(scale_ctx)
    if flags.debug then
      local scale_name = ""
      for name, intervals in pairs(SCALES) do
        if intervals == current_scale.intervals then scale_name = name; break end
      end
      logln(string.format("[SCALE] root=%s scale=%s quantize=%s", 
        PC_NAME[current_scale.root] or tostring(current_scale.root),
        scale_name,
        current_scale.quantize))
    end
  end
  
  -- Safety: log if extremely long, but do not abort during investigation
  if #body_clean > MAX_NAME_LEN then
    logln(string.format("[WARN] very long name len=%d; continuing due to debug mode", #body_clean))
  end
  local __warn_unknown = {}
  DEBUG_TOK = flags.debug -- enable tokenizer trace when debugging
  local tokens = tokenize(body_clean, __warn_unknown)
  DEBUG_TOK = false
  
  -- Debug: Log tokenization results
  local debug_file = io.open("/tmp/cuco_debug.log", "a")
  if debug_file then
    debug_file:write("[TOKENIZE_RESULT] found " .. tostring(#tokens) .. " tokens\n")
    for i, token in ipairs(tokens) do
      if type(token) == "string" then
        debug_file:write("  Token " .. i .. ": '" .. tostring(token) .. "'\n")
      else
        debug_file:write("  Token " .. i .. ": " .. tostring(token.kind or "table") .. "\n")
      end
    end
    debug_file:close()
  end
  -- Fallback: if tokenizer produced nothing, try a direct X/X^ quick-parse
  if (#tokens == 0) then
    local xsig, caret, xoff, proc_str = body_clean:match("^([xX])(%^?)([+-]%d+)?(![%a_][%w_]*%b())$")
    if xsig then
      local node = { kind = 'xref', inherit = (caret == '^'), n = tonumber(xoff) or 0 }
      if proc_str then
        local procs = select(1, maybe_parse_inline_procs(proc_str, 1))
        if procs and #procs > 0 then node.procs = procs end
      end
      tokens = { node }
    end
  end

  -- Determine effective span per token for ripple scheduling
  -- (token_arp_span function is now defined globally above)
  local eff_steps = 0
  for _,t in ipairs(tokens) do eff_steps = eff_steps + token_arp_span(t) end

  local stepQN = compute_step_qn_or_fallback(take, stepQN_opt, eff_steps)
  local _,_,itemStartQN = get_item_pos_info(take)
  local default_pitch = DEFAULT_PITCH
  local eps_qn = compute_eps_qn(take)

  if flags.debug and #__warn_unknown > 0 then
    -- summarize up to first 20 unknown chars
    local seen, list = {}, {}
    for _,ch in ipairs(__warn_unknown) do if not seen[ch] then seen[ch]=true; list[#list+1]=ch end end
    local preview = table.concat(list, " ")
    logln(string.format("[WARN] Unknown token characters encountered: %s", preview))
  end
  if #tokens == 0 then
    if flags.debug then logln("[PARSE] no tokens found (nothing to write)") end
  end

  -- Limit heavy debug work for very large token counts
  local dbg_token_limit = nil
  if flags.debug and not flags.full and #tokens > 4096 then
    dbg_token_limit = 512
    logln(string.format("[DEBUG] too many tokens (%d); limiting PLAN/SCAN to first %d bins", #tokens, dbg_token_limit))
  end

  -- DEBUG: parse echo
  if flags.debug then
    clog_reset(flags.cap)
    logln(string.format("[DEBUG] name='%s'", name))
    logln(string.format("[PARSE] stepLen=%s steps=%d", fmt_qn(stepQN), #tokens))
    if flags.full then
      local function ts(t)
        if type(t)=="string" then return t
        elseif t.kind=="stack" then return "stack["..table.concat(t.entries," ").."]"
        elseif t.kind=="repeat" then return "repeat("..ts(t.inner).."*"..tostring(t.n)..")"
        elseif t.kind=="transpose" then return "transpose("..ts(t.inner).."@"..tostring(t.n)..")"
        elseif t.kind=="loop" then
          local inner_strs = {}
          for _,inner_t in ipairs(t.entries or {}) do
            inner_strs[#inner_strs+1] = ts(inner_t)
          end
          return "loop(|"..table.concat(inner_strs," ").."| * "..tostring(t.n)..")"
        elseif t.kind=="inherit" then
          local tag = (t.processed and "inherit^" or "inherit")
          return tag.."("..tostring(t.n)..")"
        elseif t.kind=="xref" then
          local tag = (t.inherit and "xref^" or "xref")
          local p = t.procs and t.procs[1] and (t.procs[1].name.."/"..tostring(t.procs[1].n or "")) or ""
          return tag.."("..tostring(t.n or 0)..")"..(p ~= "" and ("!"..p) or "")
        elseif t.kind=="scale" then
          return "scale("..tostring(t.spec or "unknown")..")"
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
    local max_k = dbg_token_limit and math.min(#tokens, dbg_token_limit) or #tokens
    local cur = itemStartQN
    for k = 1, max_k do
      local tok = tokens[k]
      local span = token_arp_span(tok)
      local sQN = cur; local eQN = sQN + stepQN * span
      collect_leaf_bins(tok, sQN, eQN, bins)
      cur = eQN
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
    do
      local max_k = (dbg_token_limit and math.min(#tokens, dbg_token_limit)) or #tokens
      local cur = itemStartQN
      for k = 1, max_k do
        local tok = tokens[k]
        local span = token_arp_span(tok)
        local sQN = cur; local eQN = sQN + stepQN * span
        exec(tok, sQN, eQN, 0)
        cur = eQN
      end
    end
    for v,blk in pairs(voice_current) do recorder(v, blk.pitch, blk.startQN, blk.endQN) end

    -- Build PLAN rows from trace: last event per voice within that bin (sparse map)
    -- Additionally, capture all planned events per bin for 1:1 comparison with SCAN
    for _,bb in ipairs(bins) do
      local last_per_voice = {}
      local all_emits = {}
      for _,ev in ipairs(bb.trace) do
        last_per_voice[ev.voice] = { pitch=ev.pitch, s=ev.s, e=ev.e }
        if ev and ev.pitch and ev.s and ev.e then
          all_emits[#all_emits+1] = { pitch=ev.pitch, s=ev.s, e=ev.e }
        end
      end
      bb.plan = last_per_voice
      bb.plan_events = all_emits
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
    if flags.debug_all then
      logln("[PLAN-ALL] (every bin)")
      for i,bb in ipairs(bins) do
        local snap = copy_row(bb.plan)
        logln(string.format("  bin %02d  %.3f→%.3f  %s", i, bb.s, bb.e, fmt_voice_row(snap, flags.notes)))
      end
    end
  end

  -- Scale context is now applied directly during execution
  
  -- WRITE pass with persistent scale context
  clear_take(take)
  do
    -- Reset scale context to initial state before WRITE phase
    if scale_ctx then
      apply_scale_context(scale_ctx)
    else
      -- Reset to default if no header scale was provided
      current_scale = {
        root = 0,        -- C = 0
        intervals = {0,2,4,5,7,9,11}, -- major
        quantize = "near"
      }
    end
    
    local last_voices, voice_current = {}, {}
    local cur = itemStartQN
    
    -- Apply scale context directly during execution instead of post-processing
    local exec = make_executor(take, default_pitch, last_voices, voice_current, "write", nil, false)
    
    for k, tok in ipairs(tokens) do
      -- Execute all tokens (scale tokens are handled in the executor now)
      local span = token_arp_span(tok)
      local sQN = cur; local eQN = sQN + stepQN * span
      exec(tok, sQN, eQN, 0)
      cur = eQN
    end
    
    -- Flush any remaining notes from voice_current
    for i, blk in pairs(voice_current) do
      if blk then
        insert_notes(take, {blk.pitch}, blk.startQN, blk.endQN, DEFAULT_VEL, DEFAULT_CH)
        voice_current[i] = nil
      end
    end
    
    -- CRITICAL: Set item length to cover full sequence including trailing rests
    -- This ensures that when loop mode is enabled, the full rhythmic pattern is respected
    local item = reaper.GetMediaItemTake_Item(take)
    local finalEndQN = cur  -- cur now points to the end of the last token (including rests)
    local durationQN = finalEndQN - itemStartQN  -- Total duration in quarter notes
    
    -- Get original item length before we change it
    local originalLength = reaper.GetMediaItemInfo_Value(item, "D_LENGTH")
    
    -- Convert duration from QN to time - use the tempo at the item start position
    local itemStartTime = reaper.TimeMap2_QNToTime(0, itemStartQN)
    local itemEndTime = reaper.TimeMap2_QNToTime(0, finalEndQN)
    local newItemLength = itemEndTime - itemStartTime
    reaper.SetMediaItemInfo_Value(item, "D_LENGTH", newItemLength)
    
    -- Verify the length was actually set
    local actualLength = reaper.GetMediaItemInfo_Value(item, "D_LENGTH")
    
    if flags.debug then
      logln(string.format("[ITEM-LENGTH] original=%.6fs, calculated=%.6fs, actual=%.6fs (%.6f QN) for %d subdivisions", 
        originalLength, newItemLength, actualLength, finalEndQN - itemStartQN, #tokens))
      logln(string.format("[ITEM-LENGTH] itemStart=%.6f QN, finalEnd=%.6f QN, startTime=%.6fs, endTime=%.6fs", 
        itemStartQN, finalEndQN, itemStartTime, itemEndTime))
    end
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
    if flags.debug_all then
      logln("[SCAN-ALL] (every bin)")
      for i,bb in ipairs(bins) do
        safe_sort_events(bb.actual, bb.s, bb.e)
        local row={}
        for idx,ev in ipairs(bb.actual) do
          if ev and ev.pitch and ev.s and ev.e then row[idx]={pitch=ev.pitch,s=ev.s,e=ev.e} end
        end
        local snap = copy_row(row)
        logln(string.format("  bin %02d  %.3f→%.3f  %s", i, bb.s, bb.e, fmt_voice_row(snap, flags.notes)))
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
      local plan_row, actual_row = {}, {}
      for _,ev in ipairs(bb.plan_events or {}) do
        if ev and ev.pitch and ev.s and ev.e then plan_row[#plan_row+1] = { pitch=ev.pitch, s=ev.s, e=ev.e } end
      end
      for _,ev in ipairs(bb.actual) do
        if ev and ev.pitch and ev.s and ev.e then actual_row[#actual_row+1] = { pitch=ev.pitch, s=ev.s, e=ev.e } end
      end
      safe_sort_events(plan_row, bb.s, bb.e)
      safe_sort_events(actual_row, bb.s, bb.e)
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
  
  -- Debug: Log trigger to file
  local debug_file = io.open("/tmp/cuco_debug.log", "a")
  if debug_file then
    debug_file:write("[TRIGGER] name='" .. tostring(name) .. "'\n")
    debug_file:close()
  end
  reaper.Undo_BeginBlock()
  local ok, err = pcall(process_notation_step24, take, name)
  if not ok then
    logln("[CUCO Stacks Error] "..tostring(err))
    reaper.Undo_EndBlock("CUCO Stacks — v0.0.0 (error)", -1)
    return
  end
  -- Automatically enable loop mode for the processed item
  local current_loop = reaper.GetMediaItemInfo_Value(item, "B_LOOPSRC")
  if current_loop == 0 then
    reaper.SetMediaItemInfo_Value(item, "B_LOOPSRC", 1)
    logln(string.format("[LOOP-MODE] enabled for origin=%s", origin_id))
  end
  set_committed_name(origin_id, name)
  reaper.Undo_EndBlock("CUCO Stacks — v0.0.0", -1)
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
  -- One-time boot banner + seed
  if not __BOOTED then
    logln("[CUCO Stacks] Watcher running (v0.0.0)")
    -- Seed RNG once so random-based modes vary per run
    local seed = math.floor(reaper.time_precise()*1e9) + (os.time() or 0)
    math.randomseed(seed)
    -- throw away first few values (Lua RNG warm-up)
    math.random(); math.random(); math.random()
    seed_cache_once()
    __BOOTED = true
  end

  local now=reaper.time_precise(); if now<STATE.next_scan then return end; STATE.next_scan=now+STATE.interval
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

-- Cleanup function to log when script is closing
local function cleanup()
  logln("[CUCO Stacks] Script closing/terminating...")
  local debug_file = io.open("/tmp/cuco_debug.log", "a")
  if debug_file then
    debug_file:write("[SCRIPT-CLOSE] CUCO Stacks script terminating\n")
    debug_file:flush()
    debug_file:close()
  end
end

-- Register cleanup for when script terminates
reaper.atexit(cleanup)

-- Start
main_loop()
