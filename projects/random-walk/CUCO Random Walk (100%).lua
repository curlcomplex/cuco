-- @description Chain Drunk Walk - uniform points across time selection for ALL FX params (real values, excl list)
-- @version 1.0.10
-- @author curl+tony

-------------------------
-- USER SETTINGS (EDIT) --
-------------------------

local SEVERITY = 0.25               -- 0..1 : step size as fraction of param range (real units)
local POINTS_PER_PARAM = 100         -- >=2; start & end included
local SEED = nil                    -- integer for repeatability, or nil
local INCLUDE_BYPASSED_FX = false
local WRITE_MODE = "replace"        -- "replace" clears selection first; "merge" just adds points
local FORCE_SHOW_ENVS = true
local LOG = false

-- Always skip any param whose *name* contains one of these (case-insensitive substrings)
local EXCLUDE_NAMES = {
  "bypass",
  "volume",
  "delta",
  "on",
  "off",
  "return",
  "send",
  "type",
  "gain",
  "level",
  "solo",
  "mute",
  "amp",
  "mode",
  "wet",
  "freeze",
  "mixlock"
}

-------------------------
-- IMPLEMENTATION ------
-------------------------

local r = reaper
local function clamp(x, a, b) if x<a then return a elseif x>b then return b else return x end end
local function lower(s) return (s and s:lower()) or "" end
local has_SetEnv = type(r.SetEnvelopeInfo_Value)=="function"
local function safe_env_flag(env, key, val) if has_SetEnv then r.SetEnvelopeInfo_Value(env, key, val) end end

local function force_show_env_chunk(env)
  if not FORCE_SHOW_ENVS then return end
  local ok, chunk = r.GetEnvelopeStateChunk(env, "", false)
  if not ok or not chunk or #chunk==0 then return end
  chunk = chunk:gsub("ACT%s+[01]", "ACT 1")
  chunk = chunk:gsub("ARM%s+[01]", "ARM 1")
  local had_vis=false
  chunk = chunk:gsub("VIS%s+[01]%s+[01]%s*[01]?", function() had_vis=true; return "VIS 1 1 1" end)
  if not had_vis then chunk = chunk:gsub("(ACT%s+1[^\n]*\n)", "%1VIS 1 1 1\n") end
  r.SetEnvelopeStateChunk(env, chunk, true)
end

local function is_excluded_param(track, fx, p)
  local ok, name = r.TrackFX_GetParamName(track, fx, p, "")
  if not ok then return false end
  local lname = lower(name)
  for _, ex in ipairs(EXCLUDE_NAMES) do
    if lname:find(ex, 1, true) then return true end
  end
  return false
end

local function get_time_selection()
  local a,b = r.GetSet_LoopTimeRange(false,false,0,0,false)
  if not a or not b or b<=a then return nil end
  return a,b
end

local function uniform_times(t1, t2, count)
  local times = {}
  count = math.max(2, math.floor(count or 2))
  local span = t2 - t1
  if span <= 0 then times[1]=t1; times[2]=t1; return times end
  for i = 0, count-1 do
    local frac = i/(count-1)
    times[#times+1] = t1 + frac * span
  end
  return times
end

local function ensure_env(track, fx, p)
  return r.GetFXEnvelope(track, fx, p, true)
end

local function fx_ok(track, fx)
  if not INCLUDE_BYPASSED_FX then
    if not r.TrackFX_GetEnabled(track, fx) then return false end
    if r.TrackFX_GetOffline and r.TrackFX_GetOffline(track, fx) then return false end
  end
  return true
end

local function write_param_real(track, fx, p, t1, t2, count, severity)
  if is_excluded_param(track, fx, p) then return 0 end

  local cur, minv, maxv = r.TrackFX_GetParam(track, fx, p)
  if not cur then return 0 end
  minv = tonumber(minv) or 0.0
  maxv = tonumber(maxv) or 1.0
  if maxv == minv then maxv = minv + 1.0 end
  local span = (maxv - minv)

  local env = ensure_env(track, fx, p); if not env then return 0 end
  local times = uniform_times(t1, t2, count)

  if WRITE_MODE=="replace" then r.DeleteEnvelopePointRange(env, times[1], times[#times]) end

  local v = clamp(cur, minv, maxv)
  for i=1,#times do
    local step = ((math.random()*2 - 1) * severity) * span
    v = clamp(v + step, minv, maxv)
    r.InsertEnvelopePoint(env, times[i], v, 0, 0, false, true)
  end
  r.Envelope_SortPoints(env)

  safe_env_flag(env,"VIS",1); safe_env_flag(env,"ARM",1)
  force_show_env_chunk(env)
  return 1
end

local function main()
  local t1,t2 = get_time_selection()
  if not t1 then r.ShowMessageBox("Set a valid time selection first.","Chain Drunk Walk",0); return end

  local pts = math.max(2, tonumber(POINTS_PER_PARAM) or 64)
  local seed = (SEED~=nil) and tonumber(SEED) or (os.time() + math.floor(r.time_precise()*1000)%9973)
  math.randomseed(seed)

  r.Undo_BeginBlock(); r.PreventUIRefresh(1)

  local sel_cnt = r.CountSelectedTracks(0)
  local scanned_fx, scanned_params, written = 0, 0, 0

  for i=0, sel_cnt-1 do
    local tr = r.GetSelectedTrack(0,i)
    local fxN = r.TrackFX_GetCount(tr)
    for fx=0, fxN-1 do
      if fx_ok(tr,fx) then
        scanned_fx = scanned_fx + 1
        local pn = r.TrackFX_GetNumParams(tr, fx)
        for p=0, pn-1 do
          scanned_params = scanned_params + 1
          written = written + write_param_real(tr, fx, p, t1, t2, pts, SEVERITY)
        end
      end
    end
  end

  r.TrackList_AdjustWindows(false)
  r.UpdateArrange()
  r.PreventUIRefresh(-1)
  r.Undo_EndBlock("Drunk Walk: rewrite envelopes (uniform, excl list)", -1)

  if LOG then
    r.ShowConsoleMsg(("[Drunk Walk] tracks=%d  fx=%d  params_scanned=%d  envelopes_written=%d  points/param=%d  severity=%.3f\n")
      :format(sel_cnt, scanned_fx, scanned_params, written, pts, SEVERITY))
  end
end

main()
