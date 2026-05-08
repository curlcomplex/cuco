-- @description CUCO Random Walk (GUI) — Advanced parameter automation with smart grouping and multiple iterations
-- @version 4.0.0
-- @author curl+tony
-- @changelog
--   4.0.0  UI overhaul: themed surfaces, bottom-fixed footer, inline blacklist editors (no more modal popups), flexible-height window, fixed Begin/End contract for current ReaImGui.
--   3.0.0  Major update: Added FX list with smart parameter grouping, iterative processing, render-to-takes, settings persistence
--   2.0.1  Fix: use reaper.ImGui_* API directly (no nil table); added ReaImGui presence guard.
--   2.0.0  First GUI: sliders, write button + show-env toggle, 3 exclude preset toggles.
-- @about
--   Advanced random-walk automation system with intelligent parameter grouping.
--   Features: FX-specific parameter groups, multiple iterations, render-to-takes, settings persistence.
--   Uses REAL parameter values with smart exclusion based on actual loaded plugins.

--------------------------------------------------------
-- REQUIREMENT CHECK
--------------------------------------------------------
local r = reaper
if not r.ImGui_CreateContext then
  r.ShowMessageBox(
    "This script requires the ReaImGui extension.\n\nInstall via ReaPack:\nExtensions > ReaPack > Browse Packages…\nSearch 'ReaImGui' and install/update, then restart REAPER.",
    "Chain Drunk Walk (GUI)", 0)
  return
end

--------------------------------------------------------
-- DEFAULTS
--------------------------------------------------------
local DEFAULT_SEVERITY         = 0.25  -- 0..1 fraction of param range per point
local DEFAULT_POINTS_PER_PARAM = 64    -- >= 2
local DEFAULT_SHOW_ENVS        = true  -- force-show envelopes after write
local DEFAULT_NUM_ITERATIONS   = 3     -- number of iterations for batch processing
local DEFAULT_RENDER_TO_TAKES  = true  -- render each iteration to new takes
local DEFAULT_ADD_REALIMIT     = false -- add ReaLimit before rendering

-- Envelope-point shape passed to InsertEnvelopePoint(). REAPER values:
--   0=Linear, 1=Square, 2=Slow start/end, 3=Fast start, 4=Fast end, 5=Bezier
--
-- The picker is now a *weighted distribution* across shapes — each shape has
-- a 0..1 weight, and per-point the writer samples a shape proportional to
-- those weights. This subsumes the old "Random" sentinel: setting all six
-- weights equal produces uniform-random shape selection; setting one to 1
-- and the rest to 0 reproduces the previous single-pick behaviour.
local DEFAULT_BEZIER_TENSION   = 0.0  -- −1..+1, REAPER convention
-- Names match REAPER's official envelope-point shape labels, consistent
-- with the Keyframer plugin's picker. The picker renders small curve
-- thumbnails (see shape_picker_cell) instead of text buttons because the
-- full names don't fit horizontally; tooltips carry the labels.
local SHAPE_DEFS = {
  { id = 0, name = "Linear" },
  { id = 1, name = "Square" },
  { id = 2, name = "Slow start/end" },
  { id = 3, name = "Fast start" },
  { id = 4, name = "Fast end" },
  { id = 5, name = "Bezier" },
}

-- Window: fixed width, flexible height (constraints applied each frame).
local WINDOW_W      = 600
local WINDOW_H_INIT = 460
local WINDOW_H_MIN  = 260
local WINDOW_TITLE  = "CUCO Random Walk"

--------------------------------------------------------
-- PARAM CLASSIFICATION — family + sub-kind + per-param intensity
--------------------------------------------------------
-- Every parameter is assigned a (family, sub_kind) by the classifier.
-- Each sub-kind has a `mult` 0..N that scales the family's master intensity to
-- produce the param's effective intensity. The writer multiplies global severity
-- by this effective intensity per param.
--
-- Families are role-based — they describe what a sound designer reaches for the
-- param FOR, not what data type it holds. The user gets one slider per family
-- to play with everything in that role at once.
--
-- Hint matching is case-insensitive substring; first family with a sub-kind
-- match wins. Order in FAMILY_ORDER controls match priority for ambiguous
-- names (e.g. a "Filter Pitch Mod" should land in cutoffs, not pitch).

local FAMILY_ORDER = {
  "locked",       -- always wins: bypass / master out / never-walked
  "switches",     -- step count <= 8 enums
  "cutoffs",      -- filter cutoff / reso / filter env amount
  "mod_amts",     -- LFO depth, env amount, mod-matrix amounts
  "mod_times",    -- LFO rate, env ADSR, delay time
  "drive",        -- saturation, distortion, lo-fi
  "pitch_jumps",  -- semitone / transpose / octave (default 0 intensity)
  "pitch_detail", -- detune / fine / vibrato
  "blends",       -- mix / wet-dry / send / layer level
  "stereo",       -- pan / width / spread
  "walk",         -- catch-all
}

-- Each family: master_intensity / variance / locked / seed are RUNTIME state
-- (mutable, persisted in settings). label/color/sub_kinds are static.
local FAMILY_DEFS = {
  cutoffs = {
    label = "Cutoffs",
    color = 0x40A0E0FF,
    default_intensity = 0.80,
    default_variance  = 0.20,
    sub_kinds = {
      cutoff  = { mult = 1.0, hints = {
        "cutoff", "filter freq", "filter cutoff", "lp freq", "hp freq", "bp freq",
        "highpass", "lowpass", "bandpass", "filt freq",
        -- Plain "freq" / "frequency" — most often a filter / cutoff
        -- knob in synthesizers and effects.
        "freq", "frequency",
        -- Short-form filter cuts common on channel-strip plugins
        "low cut", "lowcut", "high cut", "highcut", "hpf", "lpf",
      }},
      reso    = { mult = 0.7, hints = {
        "resonance", " reso", " q ", "q factor", "filt q", "filter q",
      }},
      env_amt = { mult = 0.9, hints = {
        "filter env", "fenv ", "filter amount", "filter mod", "filter depth",
        "cutoff mod", "cutoff depth",
      }},
    },
  },
  mod_amts = {
    label = "Mod amounts",
    color = 0x60D070FF,
    default_intensity = 0.65,
    default_variance  = 0.30,
    sub_kinds = {
      lfo_depth = { mult = 1.0, hints = {
        "lfo amount", "lfo depth", "lfo amt", "lfo mod", "lfo>",
      }},
      env_amt   = { mult = 1.0, hints = {
        "env amount", "env depth", "env amt", "env mod", "envelope amount",
        "envelope depth", "mod env amount", "modulation amount",
      }},
      mod_amt   = { mult = 0.9, hints = {
        "mod amount", "mod amt", "modulation depth", "modulation", "amount", "depth",
        "feedback", " fb ", "fdbk",
        -- Reverb damping behaves like feedback on a frequency-dependent
        -- recirculation path; treating it as a mod-amount knob makes it walk.
        "damping", "damp",
        -- Sidechain / bias knobs on dynamics & saturation also feel like
        -- "how much modulation" rather than gain or filter.
        "sidechain", "bias",
        -- FM / phase mod amount.
        " fm ", "fm amount", "fm depth", "phase mod", "phase",
        -- Reverb size / room size — modulates the recirculation length.
        "size", "room size", "room",
        -- Generic "movement" / "offset" knobs on motion-style plugins.
        "movement", "offset",
      }},
      -- Broad "this is part of the modulation system" catch — must come last so
      -- more specific compound matches above win first.
      mod_generic = { mult = 0.85, hints = {
        " lfo", "lfo ", " env ", " env1", " env2", " env3", "envelope",
        "macro", " mod ", "mod1", "mod2", "mod3", " mod->",
        "velocity", "vel sens", "aftertouch", "mod wheel", "modwheel",
        "key track", "keytrack", "key follow",
      }},
    },
  },
  mod_times = {
    label = "Mod times",
    color = 0xD0A040FF,
    default_intensity = 0.45,
    default_variance  = 0.40,
    sub_kinds = {
      lfo_rate = { mult = 0.6, hints = {
        "lfo rate", "lfo speed", "lfo freq", "lfo hz",
      }},
      env_atk  = { mult = 0.7, hints = { "attack", " atk", "atk time", "atk" } },
      env_dec  = { mult = 0.8, hints = { "decay",  " dec", "dec time", "dec" } },
      env_rel  = { mult = 0.7, hints = { "release", " rel", "rel time", "rel" } },
      env_sus  = { mult = 0.5, hints = { "sustain", " sus", "sus level" } },
      delay_t  = { mult = 0.4, hints = {
        "delay time", "dly time", "delay length", "predelay",
        -- Plain "delay" — almost always the time/length param on a delay
        -- effect (depth/feedback have their own dedicated names).
        "delay",
      }},
      -- Broad time/rate/speed catch
      time_generic = { mult = 0.5, hints = {
        " rate", "rate ", " speed", "speed ", " time", "time ", " hz", "hz ",
        " ratio", "ratio ",
      }},
    },
  },
  drive = {
    label = "Drive & color",
    color = 0xE07040FF,
    default_intensity = 0.55,
    default_variance  = 0.30,
    sub_kinds = {
      drive = { mult = 1.0, hints = {
        "drive", "saturation", "saturate", " sat ", "overdrive", "warmth", "input gain",
      }},
      dist  = { mult = 0.8, hints = {
        "distortion", "distort", "fuzz", "crunch", "grit", "color",
        "edge", "tone", "character", "bite", "presence", "shape",
        "timbre", "tight",
        -- Tape/cassette flutter & wow are dist-flavoured texture controls.
        "flutter", "wow",
        -- Tone-shaping shelves common in EQs / channel strips
        "brightness", "bass", "treble", "mid", "lows", "highs",
      }},
      dyn   = { mult = 0.6, hints = {
        "threshold", "thresh", "ratio", "knee", "compression", "compress",
        "transient", "punch", "glue", " gate", "gating",
      }},
      lofi  = { mult = 0.7, hints = {
        "bit", "crush", "decimat", "downsample", "lo-fi", "lofi", "sample rate",
        "derez",
      }},
    },
  },
  pitch_detail = {
    label = "Pitch detail",
    color = 0xC080D0FF,
    default_intensity = 0.30,
    default_variance  = 0.40,
    sub_kinds = {
      detune  = { mult = 1.0, hints = { "detune", " fine", "cents" } },
      vibrato = { mult = 1.0, hints = { "vibrato", "vib amount", "vib depth" } },
      unison  = { mult = 0.9, hints = { "unison spread", "unison detune", "uni spread", "unison" } },
      drift   = { mult = 0.8, hints = { "drift", "wander", "glide", "portamento" } },
      -- Plain "pitch" with no other modifier — default to gentle drift
      generic = { mult = 0.8, hints = { "pitch" } },
    },
  },
  pitch_jumps = {
    label = "Pitch jumps",
    color = 0x8050A8FF,
    default_intensity = 0.0,   -- usually 0 — chromatic random walking is atonal
    default_variance  = 0.0,
    sub_kinds = {
      transpose = { mult = 1.0, hints = {
        "transpose", "semitone", "octave", "coarse", " key ", " tune", "tuning",
      }},
    },
  },
  blends = {
    label = "Blends",
    color = 0xE0C060FF,
    default_intensity = 0.40,
    default_variance  = 0.30,
    sub_kinds = {
      mix     = { mult = 1.0, hints = {
        " mix", "wet", "dry", "blend", "balance",
        "drywet", "wetness",
        -- Synthesizer noise level — blend rather than gain.
        "noise",
      } },
      send    = { mult = 0.8, hints = { "send", "return", "aux", "bus" } },
      layer   = { mult = 0.7, hints = { "voice level", "layer", " osc level", "osc1 level", "osc2 level", "sub level" } },
      lvl_amp = { mult = 0.0, hints = {
        "volume", "gain", "level", "amp", "amplitude", "trim", "output",
        "main vol", "main level", "out vol", "out level",
        -- Standalone in/out short-forms common as channel I/O on plugins
        "input", "in level", "in gain", "out", "input 1", "input 2",
        "in 1", "in 2", "out 1", "out 2",
        "fader",
      }},
    },
  },
  stereo = {
    label = "Stereo",
    color = 0xE060A0FF,
    default_intensity = 0.30,
    default_variance  = 0.40,
    sub_kinds = {
      pan     = { mult = 0.8, hints = { "pan", "panning" } },
      width   = { mult = 1.0, hints = { "width", "spread", " stereo", "image" } },
    },
  },
  switches = {
    label = "Switches",
    color = 0x808890FF,
    default_intensity = 0.0,
    default_variance  = 0.0,
    sub_kinds = {
      -- These are normally caught by step count (≤8 steps), but step count
      -- isn't available during name-only reclassification of the cache, and
      -- some plugins expose continuous-range "type" knobs that aren't
      -- meaningful to walk. Hint matching catches both.
      mode  = { mult = 0.0, hints = {
        "mode", "type", "filter type", "filter mode", "algorithm", "model",
        "voicing", "routing", "engine", "preset", "scale type",
        "slope", "polarity", "invert", "waveform", "wave shape",
      }},
      qual  = { mult = 0.0, hints = {
        "oversampling", "oversample", "fft size", "quality",
        "buffer size", "block size", "bit depth",
        -- Filter slope steps (2-pole / 4-pole / 24dB)
        "poles", "slope",
        -- Synth osc sync, range / scaling settings
        "sync", "range", "scaling",
        -- Generic processing-pipeline switch
        "processing",
      }},
    },
  },
  locked = {
    label  = "Locked (bypass)",
    color  = 0xC03030FF,
    default_intensity = 0.0,
    default_variance  = 0.0,
    locked = true,    -- the family is hard-locked at 0; not user-tweakable
    hidden = true,    -- not shown in the UI
    sub_kinds = {
      bypass    = { mult = 0.0, hints = { "bypass" } },
      master_vol = { mult = 0.0, hints = { "master volume", "master out", "master gain", "main out" } },
    },
  },
  walk = {
    label = "Walk (other)",
    color = 0x40C070FF,
    default_intensity = 1.0,
    default_variance  = 0.20,
    sub_kinds = {},   -- catch-all default
  },
}

-- Settings + per-plugin classification storage (separate file so the user can wipe
-- one without nuking the other).
local settings_file    = r.GetResourcePath() .. "/Scripts/CUCO Random Walk Settings.txt"
local plugin_lib_file  = r.GetResourcePath() .. "/Scripts/CUCO Random Walk Plugin Library.lua"

-- plugin_lib[fx_name] = {
--   [param_idx] = {
--     name        = string,
--     family      = "cutoffs"|"mod_amts"|...|"walk",
--     sub_kind    = string|nil,
--     base_mult   = number 0..N,    -- sub-kind multiplier × adjustments
--     user_int    = number 0..1|nil -- per-param override of effective intensity
--   }
-- }
local plugin_lib       = {}

-- Last scan summary, shown in the UI footer of the exclusions section.
local last_scan_summary = nil  -- { plugins = N, params = M, new = K, time = "..." }

--------------------------------------------------------
-- STATE
--------------------------------------------------------
local severity          = DEFAULT_SEVERITY
local points_per_param  = DEFAULT_POINTS_PER_PARAM
local show_envs         = DEFAULT_SHOW_ENVS
local num_iterations    = DEFAULT_NUM_ITERATIONS
local render_to_takes   = DEFAULT_RENDER_TO_TAKES
local add_realimit      = DEFAULT_ADD_REALIMIT
local is_processing     = false  -- track iterative processing state

-- Per-shape weights (0..1). Default is "Linear only" (the previous default
-- behaviour). The writer samples a shape per envelope point in proportion
-- to these weights — see pick_shape().
local shape_weights = { [0] = 1.0, [1] = 0, [2] = 0, [3] = 0, [4] = 0, [5] = 0 }
-- Last-non-zero value per shape, restored when the user toggles a shape
-- back on after muting it (parallel to per-family prev_intensity).
local shape_prev_weights = { [0] = 1.0, [1] = 1.0, [2] = 1.0, [3] = 1.0, [4] = 1.0, [5] = 1.0 }
local bezier_tension = DEFAULT_BEZIER_TENSION

-- True only on the frame an InvisibleButton press has moved past the click
-- threshold, used by the cell handler to distinguish click from drag.
local _shape_drag_active   = nil  -- shape id currently being dragged
local _shape_drag_start    = nil  -- weight value at start of drag
local _shape_drag_threshold_crossed = false

-- Master seed for the random-walk writer. User-visible, editable, persisted.
-- Same seed + same settings → identical envelopes. The "Write envelope" button
-- generates a new seed each press; users can also pick from the seed history
-- popup or type a value directly.
local walk_seed         = (os.time() % 1000000) + math.floor(r.time_precise()*1000) % 9973

-- Seed history — persisted per-project via SetProjExtState. Most recent first.
-- Capped so it doesn't grow unbounded across long sessions.
local SEED_HISTORY_MAX  = 32
local seed_history      = {}
local PROJEXT_SECTION   = "CUCO_RandomWalk"
local PROJEXT_KEY_HIST  = "seed_history"
local _last_project     = nil  -- tracked per frame to detect tab switches
local _takes_drag_start = 1    -- value snapshot at start of a vertical drag on the Takes box

-- Transient inline error message: shows in the GUI for a few seconds when set,
-- auto-clears. Replaces ShowMessageBox popups for non-fatal "couldn't run"
-- conditions like "no time range selected".
local _error_msg   = nil
local _error_until = 0
local function set_inline_error(msg)
  _error_msg   = msg
  _error_until = (r.time_precise() or os.clock()) + 4.0
end

-- All-row sliders are now one-directional: they store their own target value
-- and broadcast downward to per-family sliders when changed. Per-family
-- changes do NOT propagate back into these targets, so editing one family
-- doesn't visually drag the All slider with it.
local all_intensity_target = 0.5
local all_variance_target  = 0.3
local all_prev_intensity   = 0.5  -- restored when toggling All off → on

-- Storage format: "seed:unix_ts,seed:unix_ts,...". For backward compatibility
-- with the previous seed-only CSV format, entries without a colon are parsed
-- as seeds with a zero timestamp (rendered as "—" in the popup).
local function load_seed_history()
  local _, csv = r.GetProjExtState(0, PROJEXT_SECTION, PROJEXT_KEY_HIST)
  seed_history = {}
  if csv and csv ~= "" then
    for entry in csv:gmatch("([^,]+)") do
      local s_str, t_str = entry:match("^([^:]+):(.+)$")
      local s = tonumber(s_str or entry)
      local t = tonumber(t_str) or 0
      if s then seed_history[#seed_history + 1] = { s = math.floor(s), t = math.floor(t) } end
    end
  end
end

local function save_seed_history()
  local parts = {}
  for i = 1, math.min(#seed_history, SEED_HISTORY_MAX) do
    local h = seed_history[i]
    parts[i] = string.format("%d:%d", h.s, h.t)
  end
  r.SetProjExtState(0, PROJEXT_SECTION, PROJEXT_KEY_HIST, table.concat(parts, ","))
end

-- Add a seed (with current wall-clock time) to the front of the history.
-- De-dups: if the most recent entry is the same value, it's a no-op — but
-- we still update its timestamp so "current" entries always show the latest
-- time. (We keep one entry per distinct seed at the front.)
local function record_seed(s)
  s = math.floor(tonumber(s) or 0)
  local now = os.time()
  if seed_history[1] and seed_history[1].s == s then
    seed_history[1].t = now
  else
    table.insert(seed_history, 1, { s = s, t = now })
    if #seed_history > SEED_HISTORY_MAX then
      for i = #seed_history, SEED_HISTORY_MAX + 1, -1 do seed_history[i] = nil end
    end
  end
  save_seed_history()
end

-- Generate a fresh seed for the random walk. Important: this must not depend
-- on the global PRNG state, because do_write() seeds that with walk_seed —
-- if we used math.random() here, "Write → ↻ → Write" would deterministically
-- pick the next seed from the previous walk's state. Using time_precise()
-- gives us a non-PRNG source that varies per call.
local function new_random_seed()
  local t = (r.time_precise() or os.clock()) * 1000000
  -- Mix in os.time so two calls within the same microsecond still differ when
  -- time_precise has poor resolution on some platforms.
  local mix = math.floor(t) ~ (os.time() * 2654435761)
  return mix & 2147483647  -- clamp to 31-bit unsigned
end

-- FX list management
local fx_list = {}
local fx_list_needs_update = true

--------------------------------------------------------
-- HELPERS
--------------------------------------------------------
local function clamp(x, a, b) if x<a then return a elseif x>b then return b else return x end end
local function lower(s) return (s and s:lower()) or "" end

-- ─────────────────────────────────────────────────────────────────────────
-- Plugin library: load + save (Lua-serialized; sandboxed dofile on read)
-- ─────────────────────────────────────────────────────────────────────────
local function escape_quoted(s)
  return (tostring(s or ""):gsub("\\", "\\\\"):gsub("\"", "\\\""))
end

local function save_plugin_lib()
  local scripts_dir = r.GetResourcePath() .. "/Scripts"
  r.RecursiveCreateDirectory(scripts_dir, 0)
  local file = io.open(plugin_lib_file, "w")
  if not file then return end
  file:write("-- CUCO Random Walk Plugin Library (auto-generated)\n")
  file:write("-- Per-plugin parameter classifications. Re-scan from the GUI to refresh.\n")
  file:write("return {\n")
  for fx_name, params in pairs(plugin_lib) do
    file:write(string.format("  [\"%s\"] = {\n", escape_quoted(fx_name)))
    -- Stable key order: sort numerically so diffs/inspection are sane
    local keys = {}
    for k in pairs(params) do keys[#keys+1] = k end
    table.sort(keys)
    for _, idx in ipairs(keys) do
      local p = params[idx]
      -- is_toggle / step_count are written only when present so old-format
      -- entries don't bloat with nil fields. The loader handles their
      -- absence the same way it handles legacy records.
      local extras = ""
      if p.is_toggle then extras = extras .. ", is_toggle=true" end
      if p.step_count then extras = extras .. string.format(", step_count=%d", p.step_count) end
      file:write(string.format(
        "    [%d] = { name=\"%s\", family=\"%s\", sub_kind=%s, base_mult=%.4f, user_int=%s%s },\n",
        idx, escape_quoted(p.name),
        p.family or "walk",
        p.sub_kind and ("\"" .. p.sub_kind .. "\"") or "nil",
        p.base_mult or 1.0,
        p.user_int and string.format("%.4f", p.user_int) or "nil",
        extras))
    end
    file:write("  },\n")
  end
  file:write("}\n")
  file:close()
end

local function load_plugin_lib()
  local file = io.open(plugin_lib_file, "r")
  if not file then return end
  local content = file:read("*all")
  file:close()
  local fn, err = load(content, "plugin_lib", "t", {})  -- empty env: no globals
  if not fn then return end
  local ok, data = pcall(fn)
  if ok and type(data) == "table" then plugin_lib = data end
end

-- ─────────────────────────────────────────────────────────────────────────
-- Per-family runtime state. Initialized from FAMILY_DEFS, persisted in settings.
-- Declared here (before save/load_settings) so those closures capture it as an
-- upvalue — Lua resolves free variables at parse time, so a `local` declared
-- later would leave the references bound to the (nil) global.
-- ─────────────────────────────────────────────────────────────────────────
local family_state = {}
for fam, def in pairs(FAMILY_DEFS) do
  family_state[fam] = {
    intensity      = def.default_intensity,
    -- Snapshot of the last non-zero intensity, so the on/off toggle can
    -- restore it after muting. Initialized to default so first toggle-on
    -- after starting at zero gives a sensible value.
    prev_intensity = def.default_intensity,
    variance       = def.default_variance,
    locked         = def.locked or false,
    seed           = math.random(),
  }
end

-- ─────────────────────────────────────────────────────────────────────────
-- Settings persistence: numeric/boolean knobs only. Plugin lib is its own file.
-- ─────────────────────────────────────────────────────────────────────────
local function save_settings()
  local scripts_dir = r.GetResourcePath() .. "/Scripts"
  r.RecursiveCreateDirectory(scripts_dir, 0)
  local file = io.open(settings_file, "w")
  if not file then return end
  file:write("-- CUCO Random Walk Settings (auto-generated)\n")
  local kv = {
    severity         = severity,
    points_per_param = points_per_param,
    show_envs        = show_envs,
    num_iterations   = num_iterations,
    render_to_takes  = render_to_takes,
    add_realimit     = add_realimit,
    walk_seed        = walk_seed,
    bezier_tension   = bezier_tension,
    all_intensity_target = all_intensity_target,
    all_variance_target  = all_variance_target,
    all_prev_intensity   = all_prev_intensity,
  }
  for k, v in pairs(kv) do file:write(k .. " = " .. tostring(v) .. "\n") end
  -- Shape weights and the prev-snapshot used by click-to-mute.
  for id = 0, 5 do
    file:write(string.format("shape_weight_%d = %.4f\n",      id, shape_weights[id] or 0))
    file:write(string.format("shape_prev_weight_%d = %.4f\n", id, shape_prev_weights[id] or 1.0))
  end
  -- Family runtime state. Format: "fam_<name>_<key> = value"
  for fam, st in pairs(family_state) do
    file:write(string.format("fam_%s_intensity = %.4f\n",      fam, st.intensity))
    file:write(string.format("fam_%s_prev_intensity = %.4f\n", fam, st.prev_intensity or st.intensity))
    file:write(string.format("fam_%s_variance = %.4f\n",       fam, st.variance))
    file:write(string.format("fam_%s_locked = %s\n",           fam, tostring(st.locked)))
    file:write(string.format("fam_%s_seed = %.6f\n",           fam, st.seed))
  end
  file:close()
end

local function load_settings()
  local file = io.open(settings_file, "r")
  if not file then return end
  local content = file:read("*all"); file:close()
  for line in content:gmatch("([^\n]+)") do
    if not line:match("^%-%-") then
      local key, value = line:match("(%w+)%s*=%s*(.+)")
      if key and value then
        if     key == "severity"         and tonumber(value) then severity = tonumber(value)
        elseif key == "points_per_param" and tonumber(value) then points_per_param = tonumber(value)
        elseif key == "num_iterations"   and tonumber(value) then num_iterations = tonumber(value)
        elseif key == "walk_seed"        and tonumber(value) then walk_seed = math.floor(tonumber(value))
        elseif key == "all_intensity_target" and tonumber(value) then all_intensity_target = tonumber(value)
        elseif key == "all_variance_target"  and tonumber(value) then all_variance_target  = tonumber(value)
        elseif key == "all_prev_intensity"   and tonumber(value) then all_prev_intensity   = tonumber(value)
        elseif key == "bezier_tension"   and tonumber(value) then bezier_tension = tonumber(value)
        elseif key == "point_shape"      and tonumber(value) then
          -- Migration from the old single-shape model (pre-weighted-shapes
          -- release). -1 was "random" → uniform weights; 0..5 was a single
          -- pick → that shape gets weight 1, others 0.
          local s = math.floor(tonumber(value))
          if s == -1 then
            for id = 0, 5 do shape_weights[id] = 1.0 end
          elseif s >= 0 and s <= 5 then
            for id = 0, 5 do shape_weights[id] = (id == s) and 1.0 or 0.0 end
          end
        elseif key:match("^shape_weight_%d$") and tonumber(value) then
          local id = tonumber(key:match("^shape_weight_(%d)$"))
          if id and id >= 0 and id <= 5 then
            local v = tonumber(value); if v < 0 then v = 0 elseif v > 1 then v = 1 end
            shape_weights[id] = v
          end
        elseif key:match("^shape_prev_weight_%d$") and tonumber(value) then
          local id = tonumber(key:match("^shape_prev_weight_(%d)$"))
          if id and id >= 0 and id <= 5 then
            local v = tonumber(value); if v < 0 then v = 0 elseif v > 1 then v = 1 end
            shape_prev_weights[id] = v
          end
        elseif key == "show_envs"        then show_envs        = (value == "true")
        elseif key == "render_to_takes"  then render_to_takes  = (value == "true")
        elseif key == "add_realimit"     then add_realimit     = (value == "true")
        else
          -- Family settings: fam_<name>_<key>
          local fam, fkey = key:match("^fam_(.-)_(prev_intensity)$")
          if not fam then fam, fkey = key:match("^fam_(.-)_(intensity)$") end
          if not fam then fam, fkey = key:match("^fam_(.-)_(variance)$") end
          if not fam then fam, fkey = key:match("^fam_(.-)_(locked)$") end
          if not fam then fam, fkey = key:match("^fam_(.-)_(seed)$") end
          if fam and family_state[fam] then
            if fkey == "locked" then
              family_state[fam].locked = (value == "true")
            elseif tonumber(value) then
              family_state[fam][fkey] = tonumber(value)
            end
          end
        end
      end
    end
  end
end

-- Persist on commit. Call right after any ImGui slider / input / toggle so
-- the change makes it to disk on release-after-edit (one save per drag, not
-- per frame). Falls back to no-op when the API isn't exposed in the build.
-- The on-close save still runs as a safety net.
local function save_on_commit(ctx)
  if r.ImGui_IsItemDeactivatedAfterEdit and
     r.ImGui_IsItemDeactivatedAfterEdit(ctx) then
    save_settings()
  end
end

-- ─────────────────────────────────────────────────────────────────────────
-- Classifier
-- ─────────────────────────────────────────────────────────────────────────

-- Detect what unit a param's formatted samples expose. Returned hint biases the
-- final family choice (e.g. "dB" → blends/lvl_amp, "Hz" → cutoffs/cutoff,
-- "st"/"cent" → pitch_detail or pitch_jumps depending on range).
local function unit_hint(samples)
  for _, s in ipairs(samples) do
    local ls = lower(s)
    if ls:find("db", 1, true)       then return "db"   end
    if ls:find(" st", 1, true)
      or ls:find("semitone", 1, true) then return "st"   end
    if ls:find("cent", 1, true)     then return "cent" end
    if ls:find("hz", 1, true)
      or ls:find("khz", 1, true)    then return "hz"   end
  end
  return nil
end

local function looks_like_enum_format(samples)
  local enum_words = { "on","off","yes","no","true","false","enable","disable","bypass" }
  for _, s in ipairs(samples) do
    local ls = lower(s)
    for _, w in ipairs(enum_words) do
      if ls == w then return true end
    end
  end
  return false
end

-- Try to find a sub-kind hint match within a single family. Returns sub_kind name + mult.
-- When multiple hints match, the longest hint wins — this lets specific compound
-- patterns ("filter cutoff") beat broad single-word ones ("filter") within the
-- same family, regardless of pairs() iteration order.
-- System / noise / non-synthesis param names. Anything matching these
-- patterns is auto-locked so it's never written. Mostly MIDI-CC slots,
-- MPE expression rails, vendor placeholders, and UI command stubs that
-- get exposed as VST params for host automation but aren't real controls.
-- Patterns are Lua patterns (not plain strings); applied to the lowercased
-- param name. Order doesn't matter — first match wins.
local SYSTEM_PATTERNS = {
  -- Empty / placeholder names
  "^$", "^%-$", "^param$", "^param %d*$",
  "^dummy$", "^default$", "^class$", "^deprecated$", "^group$",
  "^fx%d ?$", "^bank$", "^bank select", "^midi channel$",
  "^expression$",  -- MIDI CC 11 in most synths
  "^note$",        -- usually keyboard-mapping input on samplers

  -- Bypass anywhere in the name (catches "BypassFx", "Bypass Slot 9", etc.
  -- — word-boundary matching on the locked/bypass hint missed these).
  "bypass",

  -- Structural slot/band toggles. FabFilter Pro-Q exposes `Band N Used`
  -- (slot allocation) and `Band N Enabled` (soft mute) for all 24 bands;
  -- many other multi-band plugins do the same. Walking these creates &
  -- destroys bands mid-playback — never musical, always zippery. Match
  -- the word at end-of-name so we catch both "Used" alone and
  -- "Band 3 Used", but not "Mused" or "Refused".
  "%f[%a]used$", "%f[%a]enabled$", "%f[%a]disabled$",
  "%f[%a]is on$", "%f[%a]is off$",

  -- MIDI passthrough / CC slots (multiple naming conventions)
  "^midi$", "^midi cc", "^midi controller$", "midi cc %d+|",
  "^cc %d+$", "^cc %d+%(", "^midi program",

  -- MIDI 1.0 spec controllers (lots of synths expose all 128 CCs as params)
  "^general purpose controller", "foot controller%(", "^expression%(",
  "^data entry", "^data increment", "^data decrement",
  "^effect control %d+", "^sound controller", "^modulation wheel%(",
  "^registered parameter", "^non %- registered", "^non%-registered",
  "^channel pressure%(", "^aftertouch%(", "^breath controller%(",
  "^poly%-?key pressure",

  -- Abbreviated forms that some synths (e.g. older / hardware-emulator
  -- VSTs) use for the same MIDI spec controllers. Patterns are deliberately
  -- broad because one specific instrument in the library exposes ~30 named
  -- variants of the MIDI 1.0 spec; listing each individually would bloat
  -- this list, so we match prefix patterns instead.
  "^soundcont", "^reg ?msb", "^reg ?lsb", "^non%-?reg",
  "^gen%.purp", "^gen%. ?purp", "^gen%.p%.", "^genpurp",
  "^reset ctrl",
  "^porta%.", "^port%.t",
  "^modul%.", "^mainvol",
  "^local ctrl",
  "^fxcontrol", "^fx ?ctrl", "^foot ?ct", "^foot ?ctrl",
  "^expr%.",
  "^dataent", "^data ?inc", "^data ?dec",
  "^damper",
  "^contr%.", "^contr %d+", "^ctrl %d+",

  -- MIDI mode / channel commands (with abbreviated variants).
  -- Broad prefix matches catch dropped-letter forms ("omnimodoff", which
  -- doesn't include the trailing "e" in "omnimode").
  "^all notes off$", "^all sound off$", "^poly mode", "^omni mode",
  "^polymo", "^omnimo", "^monom",
  "^local control", "^reset all controllers",
  "^soft pedal", "^sostenuto", "^legato",
  "^hold ?%d*$", "^sustain ?pedal$", "^pitchbend$", "^pitch bend$",

  -- MPE expression rails
  "^mpe_",

  -- VST program-change wrappers
  "^vst_programchange",

  -- Vendor placeholders / unused slots
  "%(reserved%)", "^reserved$", "^blank$", "^not mapped$", "^unknown$",
  "^delta$", "^x %(", "%(unused%)",

  -- Preset / browser commands
  "^select preset", "^next preset", "^previous preset",
  "%(preset trigger%)", "navigate through", "^browse ", "^saves the",
  "^undo the", "^redo the", "active filter preset",
  "active filter category", "clear filters", "add/remove selected filter",
  "^select multi filter", "^select keylabmk2 filter", "^program$",

  -- Controller surface mappings (Arturia KeyLab etc.)
  "^hardware%a*control", "^hw controller", "^oct plus$", "^oct minus$",

  -- Generic on/off / power switches (non-musical)
  "^on/off$", "^on / off$", "^power$",

  -- UI bridge controls
  "sendvaluestomidicontroller",

  -- Key range pickers (not walkable — they configure the playable range)
  "%(midi note #%)", "^note min$", "^note max$", "^low ?note$", "^high ?note$",
}

local function is_system_noise(lname)
  for _, pat in ipairs(SYSTEM_PATTERNS) do
    if lname:find(pat) then return true end
  end
  return false
end

-- Word-boundary hint matching. Plain `find(h, 1, true)` matched anywhere in
-- the param name, which produced two failure modes:
--   1. Substring false positives: "damping" matched the "amp" hint;
--      "sendvaluestomidicontroller" matched the "send" hint.
--   2. Space-padded hints (e.g. " mix") couldn't match standalone names
--      ("Mix") because the surrounding spaces weren't present.
--
-- Fix is dual-mode based on hint shape:
--   • Pure word-character hints (e.g. "wet", "drive", "mix") match via Lua
--     frontier patterns %f[%w]hint%f[%W], which require non-word boundaries
--     on either side. Punctuation counts as a boundary, so "wet" still
--     matches inside "dry/wet" or "wet (db)" but NOT inside "sendvalues…".
--   • Hints containing spaces/punctuation (e.g. "lfo amount", " key ",
--     "lfo>") fall back to plain substring on the space-padded name, which
--     preserves the original semantics for those entries.
--
-- The frontier path doesn't need Lua-pattern escaping because pure-word
-- hints by definition contain no pattern specials. The plain-find path
-- works on raw bytes.
local function hint_matches(lname, padded, hint)
  if hint:find("^[%w]+$") then
    return lname:find("%f[%w]" .. hint .. "%f[%W]") ~= nil
  end
  return padded:find(hint, 1, true) ~= nil
end

local function match_sub_kind(family_def, lname)
  if not family_def or not family_def.sub_kinds then return nil end
  local padded = " " .. lname .. " "
  local best_sk, best_mult, best_len = nil, nil, 0
  for sk, def in pairs(family_def.sub_kinds) do
    for _, h in ipairs(def.hints) do
      if #h > best_len and hint_matches(lname, padded, h) then
        best_sk, best_mult, best_len = sk, def.mult, #h
      end
    end
  end
  return best_sk, best_mult
end

-- Classify a single param into (family, sub_kind, base_mult). The classifier walks
-- families in FAMILY_ORDER and stops at the first match; this means earlier families
-- in the order win for ambiguous names. Step count and units inform the choice
-- when no name pattern matches.
local function classify_one(track, fx, p)
  local ok_n, name = r.TrackFX_GetParamName(track, fx, p, "")
  if not ok_n then return "walk", nil, 1.0, "" end
  local lname = lower(name)

  -- 0) System/noise auto-lock (MIDI CC, MPE rails, vendor placeholders, UI
  --    command stubs). Catches ~70% of params on a fully-loaded track and
  --    must run BEFORE family matching to prevent garbage classifications.
  if is_system_noise(lname) then
    return "locked", "system", 0.0, name
  end

  -- 1) Hard "locked" detection wins absolutely (bypass / master out / etc.)
  do
    local sk, m = match_sub_kind(FAMILY_DEFS.locked, lname)
    if sk then return "locked", sk, m or 0, name end
  end

  -- 2) Step / toggle detection from REAPER's own param-flags. Two APIs:
  --    a) GetParameterStepSizes — returns isToggle (true for 2-state booleans).
  --       These are always structural; never musically useful to walk.
  --    b) GetNumParamSteps — number of discrete values; <=16 reads as a
  --       discrete selector (mode/algorithm/routing).
  -- Both run BEFORE name hints because step state is authoritative — REAPER
  -- already enforces snapping in the envelope lane, so walking a stepped
  -- param produces stair-stepped envelopes anyway.
  if r.TrackFX_GetParameterStepSizes then
    local has_steps, _step, _ssm, _slg, is_toggle =
      r.TrackFX_GetParameterStepSizes(track, fx, p)
    if has_steps and is_toggle then
      return "locked", "toggle", 0.0, name
    end
  end
  if r.TrackFX_GetNumParamSteps then
    local steps = r.TrackFX_GetNumParamSteps(track, fx, p)
    if steps and steps > 0 and steps <= 16 then
      return "switches", nil, 0.0, name
    end
  end

  -- 3) Walk families in priority order; first hint match wins.
  for _, fam in ipairs(FAMILY_ORDER) do
    -- `switches` participates here so named switches like "Filter Type" /
    -- "Algorithm" / "Oversampling" classify correctly via hint matching.
    -- Step-count detection (in classify_one step 2) still acts as a
    -- fallback for unnamed switches like "Knob 1" with ≤8 steps.
    if fam ~= "locked" and fam ~= "walk" then
      local sk, m = match_sub_kind(FAMILY_DEFS[fam], lname)
      if sk then
        -- Guard: a "level / volume / amp" name in blends is the lvl_amp sub-kind
        -- which should default to 0 — we still record it under blends so the user
        -- can drag it up if they want gain wobble.
        return fam, sk, m or 1.0, name
      end
    end
  end

  -- 4) Unit hints: if formatted units strongly indicate a class even though no
  --    name pattern matched (e.g. "Knob 1" formatted as "12.0 dB"), use them.
  -- TrackFX_GetParam returns 3 values: current, minval, maxval.
  if r.TrackFX_FormatParamValue then
    local _, mn, mx = r.TrackFX_GetParam(track, fx, p)
    if mn and mx and mx > mn then
      local samples = {}
      for _, t in ipairs({ 0.0, 0.5, 1.0 }) do
        local v = mn + (mx - mn) * t
        local _, s = r.TrackFX_FormatParamValue(track, fx, p, v, "")
        if s and s ~= "" then samples[#samples + 1] = s end
      end
      if looks_like_enum_format(samples) then
        return "switches", nil, 0.0, name
      end
      local u = unit_hint(samples)
      if u == "db"   then return "blends",       "lvl_amp",   0.0, name end
      if u == "st"   then
        -- Range: ≥ 12 semitones means tonal jumps; smaller means detail.
        if (mx - mn) >= 12 then return "pitch_jumps",  "transpose", 1.0, name
        else                    return "pitch_detail", "detune",    1.0, name end
      end
      if u == "cent" then return "pitch_detail", "detune",    1.0, name end
      if u == "hz"   then return "cutoffs",      "cutoff",    1.0, name end
    end
  end

  return "walk", nil, 1.0, name
end

-- Name-only classifier. Re-runs the name-driven steps of classify_one
-- (system-noise patterns, locked sub_kinds, family hint matching) using
-- only a cached param name string — no live FX required. Used by the
-- "Re-classify saved cache" maintenance action so users can apply new
-- classifier rules across all 100s of plugins in their library without
-- having to re-instantiate every plugin in REAPER.
--
-- Optional `is_toggle` and `step_count` arguments come from cached records
-- that captured live REAPER step info during a previous full scan. When
-- present they're authoritative — REAPER's own flag for "this is a toggle"
-- or "this has N discrete steps" beats anything we could infer from name.
--
-- Trade-off vs. classify_one: skips unit-hint detection (step 4). Params
-- with cryptic names ("Knob 1") that previously got non-walk classifications
-- via that path will fall back to walk here. Users wanting maximum precision
-- should run "Re-classify selected tracks" instead.
local function classify_by_name(name, is_toggle, step_count)
  local lname = lower(name or "")

  -- Step 0: system / noise auto-lock. Empty names are caught by the "^$"
  -- system pattern, so we deliberately do NOT short-circuit empty input —
  -- letting it flow through is_system_noise lets ~880 empty-name params
  -- across the cache land in `locked` instead of `walk`.
  if is_system_noise(lname) then
    return "locked", "system", 0.0
  end

  -- Step 0.5: cached step / toggle metadata (when available). isToggle is
  -- the strongest signal we can get — REAPER itself says "this is a 2-state
  -- boolean", which is always structural.
  if is_toggle then
    return "locked", "toggle", 0.0
  end
  if step_count and step_count > 0 and step_count <= 16 then
    return "switches", nil, 0.0
  end

  -- Step 1: hard-locked names (bypass / master out / etc.).
  do
    local sk, m = match_sub_kind(FAMILY_DEFS.locked, lname)
    if sk then return "locked", sk, m or 0 end
  end

  -- Step 3: walk families in priority order.
  for _, fam in ipairs(FAMILY_ORDER) do
    -- `switches` participates here so named switches like "Filter Type" /
    -- "Algorithm" / "Oversampling" classify correctly via hint matching.
    -- Step-count detection (in classify_one step 2) still acts as a
    -- fallback for unnamed switches like "Knob 1" with ≤8 steps.
    if fam ~= "locked" and fam ~= "walk" then
      local sk, m = match_sub_kind(FAMILY_DEFS[fam], lname)
      if sk then return fam, sk, m or 1.0 end
    end
  end

  return "walk", nil, 1.0
end

-- Ensure plugin_lib has classifications for every param of the given FX. Records
-- the family / sub_kind / base_mult per param. `force` re-classifies even cached.
local function ensure_classified(track, fx_idx, force)
  local ok_fx, fx_name = r.TrackFX_GetFXName(track, fx_idx, "")
  if not ok_fx or fx_name == "" then return nil, 0 end

  local entry = plugin_lib[fx_name]
  if not entry or force then
    entry = entry or {}
    local nparams = r.TrackFX_GetNumParams(track, fx_idx) or 0
    local new_count = 0
    for p = 0, nparams - 1 do
      -- Only re-classify if forced or absent OR if the cached entry uses the
      -- old (pre-family) format.
      if force or not entry[p] or not entry[p].family then
        local fam, sk, m, pname = classify_one(track, fx_idx, p)
        local prev_user = entry[p] and entry[p].user_int or nil

        -- Capture REAPER's authoritative step / toggle flags so future
        -- name-only reclasses can respect them without needing live FX.
        --
        -- API per https://www.reaper.fm/sdk/reascript/reascripthelp.html:
        --   TrackFX_GetParameterStepSizes(track, fx, param)
        --     → retval, step, smallstep, largestep, istoggle
        -- `istoggle` is reliable for 2-state booleans. The numeric step
        -- value is *not* reliably populated even when retval is true (many
        -- plugins don't report it), so we don't trust it for step counts.
        --
        -- For non-toggle stepped detection we sample the param's range via
        -- TrackFX_FormatParamValue and count distinct formatted strings.
        -- A truly stepped param produces ≤N distinct strings across N+
        -- samples; a continuous param produces a different string per
        -- sample. Threshold 16 distinct values = "switches family" cutoff.
        local is_toggle, step_count = false, 0
        if r.TrackFX_GetParameterStepSizes then
          local _retval, _step, _ss, _sl, tog =
            r.TrackFX_GetParameterStepSizes(track, fx_idx, p)
          if tog then is_toggle = true end
        end
        if r.TrackFX_FormatParamValue and r.TrackFX_GetParam then
          -- TrackFX_GetParam returns: current, minval, maxval (3 values).
          local _, mn, mx = r.TrackFX_GetParam(track, fx_idx, p)
          if mn and mx and mx > mn then
            local SAMPLES = 24      -- enough to distinguish 12-step menus
            local CUTOFF  = 16      -- bail early if more than this distinct
            local seen, distinct = {}, 0
            for i = 0, SAMPLES - 1 do
              local v = mn + (mx - mn) * i / (SAMPLES - 1)
              local _, s = r.TrackFX_FormatParamValue(track, fx_idx, p, v, "")
              if s and s ~= "" and not seen[s] then
                seen[s] = true
                distinct = distinct + 1
                if distinct > CUTOFF then break end
              end
            end
            if distinct > 0 and distinct <= CUTOFF then step_count = distinct end
          end
        end
        -- step_count == 2 is just another name for "toggle" — promote the
        -- flag so name-only reclassification of cached entries treats them
        -- correctly without needing both fields.
        if step_count == 2 then is_toggle = true end

        -- Authoritative override: REAPER's live step/toggle detection beats
        -- whatever family classify_one chose by name. A param named "Shape"
        -- can be a continuous tone knob OR a 3-step filter-shape selector;
        -- the only way to know is the live API. Step info wins.
        --
        -- Skip the override when classify_one already chose `locked` (e.g.
        -- bypass via system pattern) — those should stay locked even if
        -- REAPER reports a step count, because they're structural toggles
        -- the user should never walk anyway.
        if fam ~= "locked" then
          if is_toggle then
            fam, sk, m = "locked", "toggle", 0.0
          elseif step_count > 0 and step_count <= 16 then
            fam, sk, m = "switches", nil, 0.0
          end
        end

        entry[p] = {
          name       = pname,
          family     = fam,
          sub_kind   = sk,
          base_mult  = m,
          user_int   = prev_user,
          is_toggle  = is_toggle or nil,   -- omit when false to keep file lean
          step_count = (step_count > 0) and step_count or nil,
        }
        new_count = new_count + 1
      end
    end
    plugin_lib[fx_name] = entry
    return entry, new_count
  end
  return entry, 0
end

-- Deterministic 0..1 jitter from a string seed + family seed. Used to spread
-- per-param intensities around the family mean according to family.variance.
local function param_jitter(fx_name, p, seed)
  local h = 2166136261
  local s = (fx_name or "") .. "#" .. tostring(p) .. "#" .. tostring(seed)
  for i = 1, #s do
    h = ((h ~ s:byte(i)) * 16777619) & 0xFFFFFFFF
  end
  return (h % 1000000) / 1000000  -- 0..1
end

-- Effective walk intensity for a single param: 0 = excluded, 1 = full severity.
-- Combines family.intensity, family.variance (deterministic jitter), and the
-- param's base_mult. user_int overrides the whole thing if set.
local function param_intensity(fx_name, p, rec)
  if not rec then return 1.0 end
  if rec.user_int then return rec.user_int end
  local fam = family_state[rec.family]
  local def = FAMILY_DEFS[rec.family]
  if not fam or not def then return 1.0 end
  if def.locked then return 0.0 end

  local base = fam.intensity * (rec.base_mult or 1.0)
  if fam.variance > 0 then
    local jitter = (param_jitter(fx_name, p, fam.seed) * 2 - 1) * fam.variance
    base = base + jitter
  end
  if base < 0 then base = 0 elseif base > 1 then base = 1 end
  return base
end

-- Writer-facing helpers. The "is_excluded_param" name kept for back-compat with
-- existing call sites in the writer; the new semantics are continuous.
local function is_excluded_param(track, fx, p, _unused)
  local ok, fx_name = r.TrackFX_GetFXName(track, fx, "")
  if not ok then return false, 1.0 end
  local entry = plugin_lib[fx_name]
  if not entry or not entry[p] or not entry[p].family then
    entry = ensure_classified(track, fx, false)
  end
  local intensity = param_intensity(fx_name, p, entry and entry[p])
  return (intensity <= 0.0001), intensity, entry and entry[p]
end

local function build_exclude_list() return {} end -- back-compat stub

local function get_time_selection()
  local a,b = r.GetSet_LoopTimeRange(false,false,0,0,false)
  
  -- If we have a valid time selection, use it
  if a and b and b > a then
    return a, b
  end
  
  -- No time selection - try to use selected items
  local item_count = r.CountSelectedMediaItems(0)
  if item_count == 0 then
    -- No items selected either - check if there are any items on selected tracks
    local sel_track_count = r.CountSelectedTracks(0)
    if sel_track_count > 0 then
      local earliest = math.huge
      local latest = -math.huge
      
      for i = 0, sel_track_count - 1 do
        local track = r.GetSelectedTrack(0, i)
        local track_item_count = r.CountTrackMediaItems(track)
        
        for j = 0, track_item_count - 1 do
          local item = r.GetTrackMediaItem(track, j)
          local item_start = r.GetMediaItemInfo_Value(item, "D_POSITION")
          local item_length = r.GetMediaItemInfo_Value(item, "D_LENGTH")
          local item_end = item_start + item_length
          
          earliest = math.min(earliest, item_start)
          latest = math.max(latest, item_end)
        end
      end
      
      if earliest < math.huge and latest > -math.huge then
        return earliest, latest
      end
    end
    return nil  -- No items found
  end
  
  -- Use selected items to determine time range
  local earliest = math.huge
  local latest = -math.huge
  
  for i = 0, item_count - 1 do
    local item = r.GetSelectedMediaItem(0, i)
    local item_start = r.GetMediaItemInfo_Value(item, "D_POSITION")
    local item_length = r.GetMediaItemInfo_Value(item, "D_LENGTH")
    local item_end = item_start + item_length
    
    earliest = math.min(earliest, item_start)
    latest = math.max(latest, item_end)
  end
  
  if earliest < math.huge and latest > -math.huge then
    return earliest, latest
  end
  
  return nil  -- No valid range found
end

-- Build FX list from currently selected tracks
local function update_fx_list()
  fx_list = {}
  local sel_cnt = r.CountSelectedTracks(0)
  
  for track_idx = 0, sel_cnt - 1 do
    local track = r.GetSelectedTrack(0, track_idx)
    local track_name = select(2, r.GetSetMediaTrackInfo_String(track, "P_NAME", "", false))
    if track_name == "" then
      track_name = "Track " .. (r.GetMediaTrackInfo_Value(track, "IP_TRACKNUMBER"))
    end
    
    local fx_count = r.TrackFX_GetCount(track)
    local track_data = {
      track = track,
      track_name = track_name,
      fx_count = fx_count,
      fx = {}
    }
    
    for fx_idx = 0, fx_count - 1 do
      local fx_name = select(2, r.TrackFX_GetFXName(track, fx_idx, ""))
      track_data.fx[fx_idx] = {
        name = fx_name,
        enabled = true  -- default to enabled
      }
    end
    
    fx_list[track_idx] = track_data
  end
  
  fx_list_needs_update = false
end

-- Evenly spaced timestamps across [t1, t2], endpoints included
local function uniform_times(t1, t2, count)
  local times = {}
  count = math.max(2, math.floor(count or 2))
  local span = t2 - t1
  if span <= 0 then times[1]=t1; times[2]=t1; return times end
  for i=0, count-1 do
    local frac = i/(count-1)
    times[#times+1] = t1 + frac*span
  end
  return times
end

-- Show/arm via API when available, with robust chunk fallback
local has_SetEnv = type(r.SetEnvelopeInfo_Value)=="function"
local function safe_env_flag(env, key, val) if has_SetEnv then r.SetEnvelopeInfo_Value(env, key, val) end end

local function force_show_env_chunk(env)
  local ok, chunk = r.GetEnvelopeStateChunk(env, "", false)
  if not ok or not chunk or #chunk==0 then return end
  chunk = chunk:gsub("ACT%s+[01]", "ACT 1")
  chunk = chunk:gsub("ARM%s+[01]", "ARM 1")
  local had_vis=false
  chunk = chunk:gsub("VIS%s+[01]%s+[01]%s*[01]?", function() had_vis=true; return "VIS 1 1 1" end)
  if not had_vis then chunk = chunk:gsub("(ACT%s+1[^\n]*\n)", "%1VIS 1 1 1\n") end
  r.SetEnvelopeStateChunk(env, chunk, true)
end

local function ensure_env(track, fx, p)
  return r.GetFXEnvelope(track, fx, p, true)
end

local function fx_ok(track, fx)
  if not r.TrackFX_GetEnabled(track, fx) then return false end
  if r.TrackFX_GetOffline and r.TrackFX_GetOffline(track, fx) then return false end
  return true
end

-- Write using REAL parameter values (min..max), uniform points.
-- The per-param intensity (returned by is_excluded_param's second value) scales
-- the global severity for this specific param. intensity=0 → skip entirely.
local function write_param_real(track, fx, p, t1, t2, count, sev, exclude_list, do_show_envs)
  local skip, intensity = is_excluded_param(track, fx, p, exclude_list)
  if skip then return 0 end

  local effective_sev = sev * intensity
  if effective_sev <= 0 then return 0 end

  local cur, minv, maxv = r.TrackFX_GetParam(track, fx, p)
  if not cur then return 0 end
  minv = tonumber(minv) or 0.0
  maxv = tonumber(maxv) or 1.0
  if maxv == minv then maxv = minv + 1.0 end
  local span = (maxv - minv)

  local env = ensure_env(track, fx, p); if not env then return 0 end
  local times = uniform_times(t1, t2, count)

  -- Replace existing points in range
  r.DeleteEnvelopePointRange(env, times[1], times[#times])

  -- Brownian walk, scaled per-param by `effective_sev`. Each point's curve
  -- shape is sampled per-point from the user's weighted shape distribution.
  -- Bezier shapes additionally use bezier_tension (non-zero tension produces
  -- visible curvature; tension=0 looks the same as Linear in REAPER).
  local total_w = 0
  for id = 0, 5 do total_w = total_w + (shape_weights[id] or 0) end

  local v = clamp(cur, minv, maxv)
  for i=1, #times do
    local step = ((math.random()*2 - 1) * effective_sev) * span
    v = clamp(v + step, minv, maxv)

    -- Pick a shape proportional to weights. Falls back to Linear (0) when
    -- every weight is 0 — a degenerate config but worth handling cleanly.
    local shape = 0
    if total_w > 0 then
      local r_val = math.random() * total_w
      local acc = 0
      for id = 0, 5 do
        acc = acc + (shape_weights[id] or 0)
        if r_val <= acc then shape = id; break end
      end
    end
    local tension = (shape == 5) and bezier_tension or 0
    r.InsertEnvelopePoint(env, times[i], v, shape, tension, false, true)
  end
  r.Envelope_SortPoints(env)

  if do_show_envs then
    safe_env_flag(env,"VIS",1); safe_env_flag(env,"ARM",1)
    force_show_env_chunk(env)
  end
  return 1
end

-- Render automation to new takes
local function render_to_new_takes(iteration_num)
  local t1, t2 = get_time_selection()
  if not t1 then return false end
  
  local sel_cnt = r.CountSelectedTracks(0)
  
  -- Clear item selection first
  r.Main_OnCommand(40289, 0) -- Item: Unselect all items
  
  -- Select all items within time selection on selected tracks AND set to original take
  for i = 0, sel_cnt - 1 do
    local track = r.GetSelectedTrack(0, i)
    local item_count = r.CountTrackMediaItems(track)
    
    for j = 0, item_count - 1 do
      local item = r.GetTrackMediaItem(track, j)
      local item_start = r.GetMediaItemInfo_Value(item, "D_POSITION")
      local item_end = item_start + r.GetMediaItemInfo_Value(item, "D_LENGTH")
      
      -- Check if item overlaps with time selection
      if item_start < t2 and item_end > t1 then
        r.SetMediaItemSelected(item, true)
        
        -- CRITICAL: Set active take to the FIRST take (original)
        local first_take = r.GetTake(item, 0)
        if first_take then
          r.SetActiveTake(first_take)
        end
      end
    end
  end
  
  -- Add ReaLimit if requested
  local added_realimit = {}
  if add_realimit then
    for i = 0, sel_cnt - 1 do
      local track = r.GetSelectedTrack(0, i)
      local realimit_idx = r.TrackFX_AddByName(track, "ReaLimit", false, -1)
      if realimit_idx >= 0 then
        added_realimit[track] = realimit_idx
      end
    end
  end
  
  -- Force all envelopes to be visible and armed before applying FX
  for i = 0, sel_cnt - 1 do
    local track = r.GetSelectedTrack(0, i)
    local fx_count = r.TrackFX_GetCount(track)
    for fx = 0, fx_count - 1 do
      if fx_ok(track, fx) then
        local param_count = r.TrackFX_GetNumParams(track, fx)
        for p = 0, param_count - 1 do
          local env = r.GetFXEnvelope(track, fx, p, false)
          if env then
            safe_env_flag(env,"VIS",1)
            safe_env_flag(env,"ARM",1)
            force_show_env_chunk(env)
          end
        end
      end
    end
  end
  
  -- Apply track/take FX to selected items to create new takes
  r.Main_OnCommand(40209, 0) -- Item: Apply track/take FX to items (mono output)
  
  -- Remove ReaLimit if we added it
  if add_realimit then
    for track, fx_idx in pairs(added_realimit) do
      if r.ValidatePtr(track, "MediaTrack*") then
        r.TrackFX_Delete(track, fx_idx)
      end
    end
  end
  
  -- Rename the newly created takes
  for i = 0, sel_cnt - 1 do
    local track = r.GetSelectedTrack(0, i)
    local item_count = r.CountTrackMediaItems(track)
    
    for j = 0, item_count - 1 do
      local item = r.GetTrackMediaItem(track, j)
      local take_count = r.CountTakes(item)
      
      if take_count > 0 then
        -- Get the most recent take (likely the one we just created)
        local newest_take = r.GetTake(item, take_count - 1)
        if newest_take then
          local ok, current_name = r.GetSetMediaItemTakeInfo_String(newest_take, "P_NAME", "", false)
          current_name = tostring(current_name or "")
          -- Only rename if it doesn't already have an RW_ prefix (to avoid renaming existing takes)
          if not current_name:find("^RW_") then
            r.GetSetMediaItemTakeInfo_String(newest_take, "P_NAME", "RW_" .. iteration_num, true)
          end
        end
      end
    end
  end
  
  return true
end

--------------------------------------------------------
-- WRITE ACTION
--------------------------------------------------------
-- Single iteration of random walk + envelope generation
local function do_single_write(iteration_num, exclude_list, pts)
  local t1, t2 = get_time_selection()
  if not t1 then return 0, 0, 0 end

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
          written = written + write_param_real(tr, fx, p, t1, t2, pts, severity, exclude_list, show_envs)
        end
      end
    end
  end
  
  return scanned_fx, scanned_params, written
end

-- Original single write function (for backward compatibility)
local function do_write()
  local t1, t2 = get_time_selection()
  if not t1 then
    set_inline_error("No time range. Make a time selection, select items, or select tracks with items.")
    return
  end

  local pts = math.max(2, math.floor(points_per_param or 64))
  -- Use the user-visible master seed so re-runs with the same seed reproduce.
  math.randomseed(walk_seed)

  local exclude_list = build_exclude_list()

  r.Undo_BeginBlock()
  r.PreventUIRefresh(1)

  local scanned_fx, scanned_params, written = do_single_write(1, exclude_list, pts)

  r.TrackList_AdjustWindows(false)
  r.UpdateArrange()
  r.PreventUIRefresh(-1)
  r.Undo_EndBlock("CUCO Random Walk: rewrite envelopes (uniform, real values)", -1)

end

-- Multi-iteration processing with rendering
local function do_iterative_write()
  local t1, t2 = get_time_selection()
  if not t1 then
    set_inline_error("No time range. Make a time selection, select items, or select tracks with items.")
    return
  end

  if is_processing then
    set_inline_error("Already bouncing. Wait for the current run to finish.")
    return
  end

  is_processing = true
  
  local pts = math.max(2, math.floor(points_per_param or 64))
  local exclude_list = build_exclude_list()
  
  r.Undo_BeginBlock()
  
  for iteration = 1, num_iterations do
    -- Derive a per-iteration sub-seed from the master walk_seed so the whole
    -- N-iteration batch is reproducible from one user-facing number, while
    -- each iteration still walks differently.
    local seed = walk_seed + iteration * 12345
    math.randomseed(seed)

    -- STEP 1: Write random automation (EXACTLY like Write Once)
    r.PreventUIRefresh(1)
    do_single_write(iteration, exclude_list, pts)
    r.TrackList_AdjustWindows(false)
    r.UpdateArrange()
    r.PreventUIRefresh(-1)

    -- STEP 2: Render this pass into a new take. The "Bounce N takes" button
    -- always renders — that's the whole point of the action.
    render_to_new_takes(iteration)
  end

  r.Undo_EndBlock("CUCO Random Walk: iterative processing " .. num_iterations .. " iterations", -1)
  is_processing = false
end

--------------------------------------------------------
-- INITIALIZATION
--------------------------------------------------------
-- Load settings + plugin classification library on startup
load_settings()
load_plugin_lib()
load_seed_history()

--------------------------------------------------------
-- GUI
--------------------------------------------------------
local ctx = r.ImGui_CreateContext(WINDOW_TITLE)

-- Shared CUCO theme module: palette + apply/revert + button helpers + tooltip.
local theme = (function()
  local s = debug.getinfo(1, "S").source:sub(2)
  local cuco = s:match("(.*/CUCO/)")
  return dofile(cuco .. "projects/_shared/cuco_imgui_theme.lua")
end)()
local COL     = theme.COL
local pushBtn = theme.pushBtn
local popBtn  = theme.popBtn
local tooltip = theme.tooltip

-- Track change detection
local last_selected_tracks = -1

-- Auto-scan: classify any FX on selected tracks that aren't yet in plugin_lib.
-- Runs every frame from the GUI loop; the early-out via the cached fingerprint
-- means it does ~zero work when nothing has changed.
local _autoscan_fingerprint = ""
local function auto_scan_new_fx()
  -- Single pass: build a fingerprint AND collect any unknown FX as we go.
  -- The fingerprint includes FX names (not just count) so swapping a plugin
  -- in place — which keeps fx_count constant — still trips the rescan.
  local fp_parts = {}
  local unknown  = {}  -- list of {track, fx_idx} pointing at FX missing from plugin_lib
  local seen     = {}  -- de-dup the same plugin instance across selected tracks
  local sel_n    = r.CountSelectedTracks(0)
  for ti = 0, sel_n - 1 do
    local tr = r.GetSelectedTrack(0, ti)
    if tr then
      local nfx = r.TrackFX_GetCount(tr) or 0
      fp_parts[#fp_parts + 1] = tostring(r.GetMediaTrackInfo_Value(tr, "IP_TRACKNUMBER")) .. ":" .. nfx
      for fi = 0, nfx - 1 do
        local _, fx_name = r.TrackFX_GetFXName(tr, fi, "")
        if fx_name and fx_name ~= "" then
          fp_parts[#fp_parts + 1] = fx_name
          if not seen[fx_name] then
            -- An entry "needs scan" if missing OR if it's been pre-seeded
            -- (e.g., post-wipe with only user_int preserved — no family).
            local entry = plugin_lib[fx_name]
            local needs_scan = not entry
            if not needs_scan then
              for _, rec in pairs(entry) do
                if type(rec) == "table" and not rec.family then
                  needs_scan = true; break
                end
              end
            end
            if needs_scan then
              seen[fx_name] = true
              unknown[#unknown + 1] = { tr, fi }
            end
          end
        end
      end
    end
  end
  local fp = table.concat(fp_parts, "|")
  if fp == _autoscan_fingerprint then return end
  _autoscan_fingerprint = fp

  -- Classify any unknown FX. Existing entries are left untouched.
  local newly_scanned = 0
  for _, u in ipairs(unknown) do
    local _, new_count = ensure_classified(u[1], u[2], false)
    if new_count and new_count > 0 then newly_scanned = newly_scanned + new_count end
  end

  if newly_scanned > 0 then
    save_plugin_lib()
    last_scan_summary = {
      plugins = nil, params = nil,
      new     = newly_scanned,
      when    = os.date("%H:%M:%S"),
      auto    = true,  -- flag so the status line can label it
    }
  end
end

-- Scan all FX on selected tracks. Records each plugin's parameter classifications
-- in plugin_lib (creates entries on first encounter; preserves user overrides when
-- force-rescanning). Persists. Returns a summary table.
local function scan_selected_tracks(force)
  local n_plugins, n_params, n_new = 0, 0, 0
  local seen = {}  -- avoid double-counting the same plugin instance across selected tracks
  for ti = 0, r.CountSelectedTracks(0) - 1 do
    local tr = r.GetSelectedTrack(0, ti)
    if tr then
      local nfx = r.TrackFX_GetCount(tr) or 0
      for fi = 0, nfx - 1 do
        local _, fx_name = r.TrackFX_GetFXName(tr, fi, "")
        if fx_name and fx_name ~= "" and not seen[fx_name] then
          seen[fx_name] = true
          local entry, new_count = ensure_classified(tr, fi, force)
          if entry then
            n_plugins = n_plugins + 1
            for _ in pairs(entry) do n_params = n_params + 1 end
            n_new = n_new + (new_count or 0)
          end
        end
      end
    end
  end
  save_plugin_lib()
  last_scan_summary = {
    plugins = n_plugins, params = n_params, new = n_new,
    when    = os.date("%H:%M:%S"),
  }
  return last_scan_summary
end

-- Render one "amount" row — used for both the meta "All" row and the
-- per-family rows in Walk amounts. Caller passes the displayed values plus
-- callbacks for each control. This keeps the All row visually identical to
-- the family rows and avoids drift between the two layouts.
--
-- opts fields:
--   id              — unique PushID string (e.g., "all" or "fam_cutoffs")
--   label           — display name ("All", "Cutoffs", …)
--   color           — color of the leading dot
--   count           — integer shown next to the label
--   samples         — optional list of strings shown as a hover tooltip on the label
--   intensity       — 0..1 currently displayed value
--   variance        — 0..1
--   locked          — bool
--   can_reroll      — bool: gates the R button (in addition to `locked`)
--   on_intensity(v) — fired when the intensity slider changes
--   on_variance(v)  — fired when the variance slider changes
--   on_lock(new)    — fired when Lock is clicked; receives the toggled state
--   on_reroll()     — fired when R is clicked
--   *_tooltip       — optional override strings for each control
local function render_amount_row(ctx, opts)
  r.ImGui_PushID(ctx, opts.id)

  -- Color dot doubles as the on/off toggle. Full colour = on (intensity > 0);
  -- faint = off. Click to mute or unmute. The colour-coded identity stays
  -- intact while gaining a second purpose, so the row doesn't grow another
  -- button.
  local is_on    = (opts.intensity or 0) > 0.0001
  local dot_col  = is_on and opts.color or COL.faint
  r.ImGui_TextColored(ctx, dot_col, "●")
  if r.ImGui_IsItemClicked(ctx) and opts.on_toggle then
    opts.on_toggle(not is_on)
    save_settings()
  end
  if r.ImGui_IsItemHovered(ctx) then
    r.ImGui_SetTooltip(ctx, opts.toggle_tooltip
      or (is_on and "Click to mute (sets walk to 0; remembers prior value)."
                or  "Click to unmute (restores prior walk value)."))
  end
  r.ImGui_SameLine(ctx, 0, 6)

  -- Label + count
  local count = opts.count or 0
  local label_text = string.format("%s  %d", opts.label, count)
  r.ImGui_AlignTextToFramePadding(ctx)
  local label_col = (count == 0) and COL.faint or COL.text
  r.ImGui_TextColored(ctx, label_col, label_text)
  if count > 0 and opts.samples and r.ImGui_IsItemHovered(ctx) then
    local samples = opts.samples
    local extra = (count > #samples) and string.format("\n  …and %d more", count - #samples) or ""
    r.ImGui_SetTooltip(ctx, table.concat(samples, "\n") .. extra)
  end

  -- Right-side cluster: intensity slider | variance slider | Lock | R
  r.ImGui_SameLine(ctx, 130)
  local cw           = r.ImGui_GetContentRegionAvail(ctx)
  local var_slider_w = 70
  local right_w      = var_slider_w + 90
  r.ImGui_SetNextItemWidth(ctx, math.max(60, cw - right_w))

  -- Intensity slider — disabled when locked.
  r.ImGui_BeginDisabled(ctx, opts.locked)
  local int_fmt = (opts.intensity > 0.001)
    and string.format("%d%%%%", math.floor(opts.intensity * 100 + 0.5))
    or "off"
  local i_changed, i_new = r.ImGui_SliderDouble(ctx, "##int", opts.intensity, 0, 1, int_fmt)
  if i_changed and opts.on_intensity then opts.on_intensity(i_new) end
  save_on_commit(ctx)
  tooltip(ctx, opts.intensity_tooltip or "How much this family contributes to the walk. 0% = excluded.")
  r.ImGui_EndDisabled(ctx)

  -- Variance slider.
  r.ImGui_SameLine(ctx, 0, 6)
  r.ImGui_SetNextItemWidth(ctx, var_slider_w)
  local var_fmt = string.format("V%d%%%%", math.floor(opts.variance * 100 + 0.5))
  local v_changed, v_new = r.ImGui_SliderDouble(ctx, "##var", opts.variance, 0, 1, var_fmt)
  if v_changed and opts.on_variance then opts.on_variance(v_new) end
  save_on_commit(ctx)
  tooltip(ctx, opts.variance_tooltip or
    "Variance: how much each individual param's intensity deviates from the family value (0–100%).")

  -- Lock toggle.
  r.ImGui_SameLine(ctx, 0, 4)
  pushBtn(ctx, opts.locked and COL.warn or COL.bg_frame,
               opts.locked and COL.warn_hi or COL.bg_frame_hi)
  if r.ImGui_SmallButton(ctx, "Lock") then
    if opts.on_lock then opts.on_lock(not opts.locked) end
    save_settings()
  end
  popBtn(ctx)
  tooltip(ctx, opts.lock_tooltip
    or (opts.locked and "Locked. Click to unlock." or "Unlocked. Click to lock."))

  -- Re-roll variance distribution.
  r.ImGui_SameLine(ctx, 0, 4)
  local can_reroll = (opts.can_reroll ~= false) and not opts.locked
  r.ImGui_BeginDisabled(ctx, not can_reroll)
  if r.ImGui_SmallButton(ctx, "R") then
    if opts.on_reroll then opts.on_reroll() end
    save_settings()
  end
  r.ImGui_EndDisabled(ctx)
  tooltip(ctx, opts.reroll_tooltip or "Re-roll variance distribution (new per-param jitter).")

  r.ImGui_PopID(ctx)
end

-- Visual approximations of REAPER's envelope curves for the picker
-- thumbnails. They aren't pixel-accurate matches to the renderer (REAPER's
-- internal curves include tension; ours are simplified) but each shape is
-- recognizable. Mirrors the implementation in CUCO Keyframe.lua so the two
-- scripts present envelope shapes identically.
local function shape_y(shape, t)
  if     shape == 0 then return t                                     -- Linear
  elseif shape == 1 then return (t < 1) and 0 or 1                    -- Square
  elseif shape == 2 then return t * t * (3 - 2 * t)                   -- Slow start/end
  elseif shape == 3 then return t * t                                 -- Fast start
  elseif shape == 4 then return 1 - (1 - t) * (1 - t)                 -- Fast end
  elseif shape == 5 then return 0.5 - 0.5 * math.cos(t * math.pi)     -- Bezier
  end
  return t
end

-- Shape-weight cell: a curve thumbnail with a green fill rising from the
-- bottom proportional to its weight (0..1).
--
-- Interactions:
--   • Drag up/down → continuous weight adjustment. Drag distance equal to
--     the cell height covers the full 0..1 range, so the weight visually
--     tracks the cursor as a "fill level".
--   • Click without drag → toggle between 0 and the stored prev_weight
--     (parallel to the family on/off dot toggle). If prev is 0, restores
--     to 1.
--
-- Returns: new_weight, new_prev_weight, changed (bool). Caller writes back
-- both into shape_weights[id] and shape_prev_weights[id] and calls
-- save_settings on changed=true.
local function shape_weight_cell(ctx, shape_id, weight, prev_weight, w, h)
  r.ImGui_PushID(ctx, "swc" .. tostring(shape_id))
  local x, y = r.ImGui_GetCursorScreenPos(ctx)
  r.ImGui_InvisibleButton(ctx, "##cell", w, h)
  local hovered = r.ImGui_IsItemHovered(ctx)
  local active  = r.ImGui_IsItemActive(ctx)

  local new_weight, new_prev = weight, prev_weight or 1.0
  local changed = false

  -- Press-edge: snapshot start value, reset drag-delta and drag-flag.
  if r.ImGui_IsItemActivated(ctx) then
    _shape_drag_active   = shape_id
    _shape_drag_start    = weight
    _shape_drag_threshold_crossed = false
    r.ImGui_ResetMouseDragDelta(ctx, 0)
  end

  if active then
    local _, dy = r.ImGui_GetMouseDragDelta(ctx, 0, 0)
    -- 4px movement threshold to distinguish click from drag.
    if math.abs(dy) > 4 then _shape_drag_threshold_crossed = true end
    if _shape_drag_threshold_crossed then
      -- Drag distance == ~80 px covers full 0..1 range. Previously this
      -- was "1 cell-height = full range" (28 px = 100%) which felt jumpy;
      -- decoupling from cell height gives a feel similar to a normal drag
      -- slider regardless of how tall the cells are rendered.
      local v_speed = 1.0 / 80
      local target = (_shape_drag_start or weight) - dy * v_speed
      if target < 0 then target = 0 elseif target > 1 then target = 1 end
      if target ~= weight then
        new_weight = target
        if target > 0.0001 then new_prev = target end
        changed = true
      end
    end
  end

  -- Release-edge: if we never crossed the drag threshold, treat as a click.
  -- Persist on every release (whether drag or click) so shape weights stick
  -- across script close/open cycles without depending on the on-close save.
  local saved_this_release = false
  if r.ImGui_IsItemDeactivated(ctx) and _shape_drag_active == shape_id then
    if not _shape_drag_threshold_crossed then
      if weight > 0.0001 then
        -- Mute: snapshot current as prev, set to 0.
        new_prev   = weight
        new_weight = 0
      else
        -- Unmute: restore prev (or 1 if prev is also 0).
        new_weight = (prev_weight and prev_weight > 0.0001) and prev_weight or 1.0
      end
      changed = true
    end
    saved_this_release = true
    _shape_drag_active   = nil
    _shape_drag_threshold_crossed = false
  end

  -- Cursor hint for the drag affordance.
  if hovered or active then
    r.ImGui_SetMouseCursor(ctx, r.ImGui_MouseCursor_ResizeNS())
  end

  -- Render: bg, weight fill from bottom, then curve on top.
  local dl = r.ImGui_GetWindowDrawList(ctx)
  local bg = (hovered or active) and COL.bg_frame_hi or COL.bg_frame
  r.ImGui_DrawList_AddRectFilled(dl, x, y, x + w, y + h, bg, 4)
  if weight > 0.001 then
    local fill_h = h * weight
    -- Use a dimmed primary so the curve stays readable on top of the fill.
    -- COL.primary is the "active" green from the theme.
    r.ImGui_DrawList_AddRectFilled(dl, x, y + h - fill_h, x + w, y + h, COL.primary, 4)
  end

  -- Curve overlay (white-ish for contrast over both empty and filled bg).
  local fg = (weight > 0.5) and 0xFFFFFFFF or 0xC8C8D0FF
  local pad_x, pad_y = 5, 4
  local x0, y0 = x + pad_x, y + h - pad_y
  local x1, y1 = x + w - pad_x, y + pad_y
  local N = 24
  local px, py = x0, y0
  for i = 1, N do
    local t  = i / N
    local sy = shape_y(shape_id, t)
    local nx = x0 + (x1 - x0) * t
    local ny = y0 + (y1 - y0) * sy
    r.ImGui_DrawList_AddLine(dl, px, py, nx, ny, fg, 1.5)
    px, py = nx, ny
  end
  r.ImGui_DrawList_AddCircleFilled(dl, x0, y0, 1.8, fg)
  r.ImGui_DrawList_AddCircleFilled(dl, x1, y1, 1.8, fg)

  r.ImGui_PopID(ctx)
  return new_weight, new_prev, changed, saved_this_release
end

local function loop()
  -- Check if selected tracks changed
  local current_selected_tracks = r.CountSelectedTracks(0)
  if current_selected_tracks ~= last_selected_tracks then
    fx_list_needs_update = true
    last_selected_tracks = current_selected_tracks
  end
  
  -- Check if FX counts changed on existing tracks
  if not fx_list_needs_update then
    for i = 0, current_selected_tracks - 1 do
      local track = r.GetSelectedTrack(0, i)
      if track then
        local current_fx_count = r.TrackFX_GetCount(track)
        if fx_list[i] and fx_list[i].fx_count ~= current_fx_count then
          fx_list_needs_update = true
          break
        end
      end
    end
  end
  
  -- Cap height so the window never opens taller than the user's display.
  -- Wrapped in pcall in case the viewport API isn't available on a given
  -- ReaImGui build; falls back to a conservative cap.
  local screen_h = 1000
  local ok, vp = pcall(r.ImGui_GetMainViewport, ctx)
  if ok and vp then
    local ok2, _, h = pcall(r.ImGui_Viewport_GetWorkSize, vp)
    if ok2 and h and h > 0 then screen_h = h end
  end
  local max_h  = math.max(WINDOW_H_MIN, math.floor(screen_h * 0.9))
  local init_h = math.min(WINDOW_H_INIT, max_h)
  r.ImGui_SetNextWindowSizeConstraints(ctx, WINDOW_W, WINDOW_H_MIN, WINDOW_W, max_h)
  r.ImGui_SetNextWindowSize(ctx, WINDOW_W, init_h, r.ImGui_Cond_FirstUseEver())

  local theme_token = theme.apply(ctx)

  -- ReaImGui contract: End() ONLY when Begin returned visible=true. `open` is the
  -- close-button state; when X is clicked, `open` becomes false and we stop deferring.
  local visible, open = r.ImGui_Begin(ctx, WINDOW_TITLE, true)

  if visible then
    if fx_list_needs_update then update_fx_list() end

    -- Catch newly-added FX on selected tracks the moment they appear, without
    -- requiring the user to hit "Scan tracks". Cheap when nothing changed.
    auto_scan_new_fx()

    -- Reload the seed history when REAPER's active project changes — history
    -- is per-project, so swapping tabs should swap visible history too.
    local cur_proj = r.EnumProjects(-1, "")
    if cur_proj ~= _last_project then
      _last_project = cur_proj
      load_seed_history()
    end

    -- Reserve footer height for: step size + point density + shape (with
    -- Bezier tension on the same row) + separator + inline-error spacer
    -- + 4-row action panels (heading + pref + state + button) + paddings.
    local frame_h  = r.ImGui_GetFrameHeightWithSpacing(ctx)
    local footer_h = frame_h * 9 + 28

    -- ─────────────────────────────────────────────────────────────
    -- Top scrollable pane: FX list + exclusion presets (in flow)
    -- ─────────────────────────────────────────────────────────────
    if r.ImGui_BeginChild(ctx, "scroll_pane", 0, -footer_h, 0) then
      r.ImGui_PushStyleVar(ctx, r.ImGui_StyleVar_ItemSpacing(), 6, 4)

      -- FX list section
      if r.ImGui_CollapsingHeader(ctx, "FX list", r.ImGui_TreeNodeFlags_DefaultOpen()) then
        local any = false
        for track_idx = 0, #fx_list do
          local track_data = fx_list[track_idx]
          if track_data and track_data.fx and track_data.fx_count and track_data.fx_count > 0 then
            any = true
            r.ImGui_TextColored(ctx, COL.muted, track_data.track_name)
            r.ImGui_Indent(ctx, 14)
            for fx_idx = 0, track_data.fx_count - 1 do
              local fx_data = track_data.fx[fx_idx]
              if fx_data then
                local ch, en = r.ImGui_Checkbox(ctx,
                  fx_data.name .. "##fx_" .. track_idx .. "_" .. fx_idx, fx_data.enabled)
                if ch then fx_data.enabled = en end
              end
            end
            r.ImGui_Unindent(ctx, 14)
            r.ImGui_Dummy(ctx, 0, 2)
          end
        end
        if not any then
          r.ImGui_TextColored(ctx, COL.faint, "  Select tracks with FX to populate this list.")
        end
      end

      r.ImGui_Dummy(ctx, 0, 4)

      -- ───────────────────────────────────────────────────────────
      -- Family controls — one row per family with intensity / variance / lock / re-roll
      -- ───────────────────────────────────────────────────────────
      -- Walk amounts header. Scan/Re-scan are gone — auto-scan handles new FX.
      -- The "All" meta-row is rendered ALWAYS (regardless of header state) so
      -- when this section is collapsed users still see one quick master
      -- control. Per-family rows show only when expanded.
      local walk_expanded = r.ImGui_CollapsingHeader(ctx, "Walk amounts", r.ImGui_TreeNodeFlags_DefaultOpen())

      -- Compute live per-family counts + sample names. Done unconditionally
      -- because the All row needs the total even when collapsed.
      local fam_counts, fam_samples = {}, {}
      local SAMPLE_LIMIT = 30
      local sel_cnt = r.CountSelectedTracks(0)
      for ti = 0, sel_cnt - 1 do
        local tr = r.GetSelectedTrack(0, ti)
        local fx_n = r.TrackFX_GetCount(tr)
        for fi = 0, fx_n - 1 do
          local fx_name = select(2, r.TrackFX_GetFXName(tr, fi, ""))
          local entry = plugin_lib[fx_name]
          if entry then
            for _, rec in pairs(entry) do
              if type(rec) == "table" and rec.family then
                fam_counts[rec.family] = (fam_counts[rec.family] or 0) + 1
                fam_samples[rec.family] = fam_samples[rec.family] or {}
                if #fam_samples[rec.family] < SAMPLE_LIMIT then
                  fam_samples[rec.family][#fam_samples[rec.family] + 1] =
                    string.format("  %s — %s", fx_name:match("([^:]+)%s*$") or fx_name, rec.name or "?")
                end
              end
            end
          end
        end
      end

      -- Aggregate counts only — the All row's intensity/variance are stored
      -- targets (not averages), so per-family changes don't drag the All
      -- slider with them. We still derive `all_locked` from family state so
      -- the lock button reflects whether anything would actually move.
      local n_unlocked, n_visible = 0, 0
      local total_count = 0
      for fam, st in pairs(family_state) do
        local def = FAMILY_DEFS[fam]
        if def and not def.hidden then
          n_visible = n_visible + 1
          total_count = total_count + (fam_counts[fam] or 0)
          if not st.locked then n_unlocked = n_unlocked + 1 end
        end
      end
      local all_locked = (n_unlocked == 0 and n_visible > 0)
      -- "All on" iff the stored target is non-zero. The toggle stores/restores
      -- the target itself (parallel to per-family prev_intensity).
      local all_is_on  = (all_intensity_target > 0.0001)

      -- ── ALL meta-row: always visible ─────────────────────────────────────
      -- One-directional: the slider's value is `all_intensity_target` (a
      -- stored target), and dragging it broadcasts down to all unlocked
      -- families. Editing a family slider does NOT change this target.
      render_amount_row(ctx, {
        id            = "all",
        label         = "All",
        color         = COL.text,    -- neutral dot
        count         = total_count,
        samples       = nil,
        intensity     = all_intensity_target,
        variance      = all_variance_target,
        locked        = all_locked,
        can_reroll    = (n_unlocked > 0),
        intensity_tooltip = "Master walk amount. Dragging sets every unlocked family to this value. " ..
                            "Editing a single family doesn't move this slider back.",
        variance_tooltip  = "Master variance. Dragging sets every unlocked family's variance to this value.",
        lock_tooltip      = all_locked
          and "All families are locked. Click to unlock all."
          or  "Lock every family at once.",
        reroll_tooltip    = "Re-roll variance distribution for every unlocked family.",
        on_intensity = function(v)
          all_intensity_target = v
          if v > 0.0001 then all_prev_intensity = v end
          for fam, st in pairs(family_state) do
            local def = FAMILY_DEFS[fam]
            if def and not def.hidden and not st.locked then st.intensity = v end
          end
        end,
        on_variance = function(v)
          all_variance_target = v
          for fam, st in pairs(family_state) do
            local def = FAMILY_DEFS[fam]
            if def and not def.hidden and not st.locked then st.variance = v end
          end
        end,
        on_lock = function(new_locked)
          for fam, st in pairs(family_state) do
            local def = FAMILY_DEFS[fam]
            if def and not def.hidden then st.locked = new_locked end
          end
        end,
        on_reroll = function()
          for fam, st in pairs(family_state) do
            local def = FAMILY_DEFS[fam]
            if def and not def.hidden and not st.locked then st.seed = math.random() end
          end
          save_settings()
        end,
        on_toggle = function(turning_on)
          if turning_on then
            -- Restore the stored target and broadcast down. If somehow prev
            -- is 0, fall back to a useful default so the click does
            -- something visible.
            local restore = (all_prev_intensity > 0.0001) and all_prev_intensity or 0.5
            all_intensity_target = restore
            for fam, st in pairs(family_state) do
              local def = FAMILY_DEFS[fam]
              if def and not def.hidden and not st.locked then
                local fr = (st.prev_intensity and st.prev_intensity > 0.0001)
                  and st.prev_intensity or def.default_intensity
                st.intensity = fr
              end
            end
          else
            if all_intensity_target > 0.0001 then all_prev_intensity = all_intensity_target end
            all_intensity_target = 0
            for fam, st in pairs(family_state) do
              local def = FAMILY_DEFS[fam]
              if def and not def.hidden and not st.locked then
                if st.intensity > 0.0001 then st.prev_intensity = st.intensity end
                st.intensity = 0
              end
            end
          end
        end,
        toggle_tooltip = all_is_on
          and "Click to mute (sets every unlocked family + this target to 0)."
          or  "Click to unmute (restores the previous All target and family values).",
      })

      -- ── Per-family rows: only when the section is expanded ───────────────
      if walk_expanded then
        -- Auto-scan status line — visible only when expanded so the collapsed
        -- view stays clean with just the All row.
        --
        -- Hidden affordance: right-click this line to open a context menu
        -- with maintenance commands (force re-classify, wipe cache). These
        -- aren't surfaced as buttons because they're rare and destructive;
        -- right-click on the most contextually relevant text keeps them
        -- discoverable for power users without cluttering the UI.
        if last_scan_summary then
          local s = last_scan_summary
          local msg
          if s.auto then
            msg = string.format("auto: +%d new params · %s", s.new or 0, s.when or "")
          else
            msg = string.format("%d plugins · %d params · %d new · %s",
              s.plugins or 0, s.params or 0, s.new or 0, s.when or "")
            -- Append step-metadata coverage when a full re-classify ran.
            if s.toggles or s.stepped then
              msg = msg .. string.format(" · %d toggles · %d stepped",
                s.toggles or 0, s.stepped or 0)
            end
          end
          r.ImGui_TextColored(ctx, COL.muted, msg)
        else
          r.ImGui_TextColored(ctx, COL.faint, "Auto-scan watching selected tracks. (right-click for options)")
        end

        -- Right-click on the status line opens the maintenance popup.
        if r.ImGui_IsItemHovered(ctx) and r.ImGui_IsMouseClicked(ctx, 1) then
          r.ImGui_OpenPopup(ctx, "scan_maintenance")
        end
        if r.ImGui_BeginPopup(ctx, "scan_maintenance") then
          r.ImGui_TextColored(ctx, COL.muted, "Maintenance")
          r.ImGui_Separator(ctx)

          -- Re-classify EVERY plugin in the saved cache using name-based
          -- rules. No live FX required — works on the cached `name` field
          -- of each param record. This is the right action after changing
          -- the system-noise patterns or hint lists, since it covers the
          -- entire library (often 100s of plugins) without the user having
          -- to re-load every plugin in REAPER. user_int overrides are
          -- preserved.
          if r.ImGui_Selectable(ctx, "Re-classify saved cache (all plugins)") then
            local n_plugins, n_params = 0, 0
            local n_changed = 0
            for fx_name, entry in pairs(plugin_lib) do
              if type(entry) == "table" then
                n_plugins = n_plugins + 1
                for p, rec in pairs(entry) do
                  if type(rec) == "table" and rec.name then
                    n_params = n_params + 1
                    local fam, sk, m = classify_by_name(rec.name, rec.is_toggle, rec.step_count)
                    if rec.family ~= fam or rec.sub_kind ~= sk
                       or math.abs((rec.base_mult or 0) - (m or 0)) > 0.0001 then
                      n_changed = n_changed + 1
                    end
                    rec.family    = fam
                    rec.sub_kind  = sk
                    rec.base_mult = m
                    -- user_int preserved automatically (we only mutate the
                    -- three classification fields).
                  end
                end
              end
            end
            save_plugin_lib()
            _autoscan_fingerprint = ""
            last_scan_summary = {
              plugins = n_plugins, params = n_params, new = n_changed,
              when    = os.date("%H:%M:%S"), auto = false,
            }
          end
          if r.ImGui_IsItemHovered(ctx) then
            r.ImGui_SetTooltip(ctx,
              "Re-run name-based classification on every plugin in the cache.\n" ..
              "Fast: no FX re-instantiation needed.\n" ..
              "Skips step-count and unit-hint detection — for that, also run\n" ..
              "'Re-classify selected tracks' on plugins with cryptic param names.")
          end

          -- Force re-classify every FX on currently-selected tracks. Uses
          -- ensure_classified(force=true) so the classifier re-runs against
          -- the live FX (re-tests unit hints, step counts, names) and
          -- preserves any user_int overrides per param.
          if r.ImGui_Selectable(ctx, "Re-classify selected tracks (full)") then
            local n_plugins, n_params = 0, 0
            local n_toggles, n_stepped = 0, 0
            local seen = {}
            for ti = 0, r.CountSelectedTracks(0) - 1 do
              local tr = r.GetSelectedTrack(0, ti)
              if tr then
                local nfx = r.TrackFX_GetCount(tr) or 0
                for fi = 0, nfx - 1 do
                  local _, fname = r.TrackFX_GetFXName(tr, fi, "")
                  if fname and fname ~= "" and not seen[fname] then
                    seen[fname] = true
                    local entry = ensure_classified(tr, fi, true)
                    if entry then
                      n_plugins = n_plugins + 1
                      for _, rec in pairs(entry) do
                        if type(rec) == "table" then
                          n_params = n_params + 1
                          if rec.is_toggle then n_toggles = n_toggles + 1 end
                          if rec.step_count then n_stepped = n_stepped + 1 end
                        end
                      end
                    end
                  end
                end
              end
            end
            save_plugin_lib()
            -- Reset auto-scan fingerprint so the next frame doesn't think
            -- "nothing changed" and skip the live-counts refresh.
            _autoscan_fingerprint = ""
            last_scan_summary = {
              plugins = n_plugins, params = n_params, new = 0,
              toggles = n_toggles, stepped = n_stepped,
              when    = os.date("%H:%M:%S"), auto = false,
            }
          end
          if r.ImGui_IsItemHovered(ctx) then
            r.ImGui_SetTooltip(ctx,
              "Re-run the classifier on every FX on currently-selected tracks.\n" ..
              "Uses the current rules; preserves your per-param overrides.")
          end

          -- Nuclear option: wipe the entire cache. Plugins on selected tracks
          -- get re-classified immediately by the next auto-scan frame; others
          -- will be re-classified the next time their host track is selected.
          if r.ImGui_Selectable(ctx, "Wipe plugin cache (force fresh scans)") then
            -- Preserve per-param user overrides so the user doesn't lose work.
            local saved_overrides = {}
            for fname, entry in pairs(plugin_lib) do
              for p, rec in pairs(entry) do
                if type(rec) == "table" and rec.user_int ~= nil then
                  saved_overrides[fname] = saved_overrides[fname] or {}
                  saved_overrides[fname][p] = rec.user_int
                end
              end
            end
            plugin_lib = {}
            -- Pre-seed the cache with empty entries containing only user_int,
            -- so when ensure_classified runs it picks them up via the existing
            -- prev_user logic.
            for fname, params in pairs(saved_overrides) do
              plugin_lib[fname] = {}
              for p, ui in pairs(params) do
                plugin_lib[fname][p] = { user_int = ui }
              end
            end
            save_plugin_lib()
            _autoscan_fingerprint = ""
            last_scan_summary = nil
          end
          if r.ImGui_IsItemHovered(ctx) then
            r.ImGui_SetTooltip(ctx,
              "Clear the entire classification cache.\n" ..
              "Per-param user overrides are preserved.\n" ..
              "Auto-scan will rebuild as you select tracks.")
          end

          r.ImGui_EndPopup(ctx)
        end

        r.ImGui_Dummy(ctx, 0, 4)

        for _, fam in ipairs(FAMILY_ORDER) do
          local def = FAMILY_DEFS[fam]
          local st  = family_state[fam]
          if def and st and not def.hidden then
            render_amount_row(ctx, {
              id        = "fam_" .. fam,
              label     = def.label,
              color     = def.color,
              count     = fam_counts[fam] or 0,
              samples   = fam_samples[fam],
              intensity = st.intensity,
              variance  = st.variance,
              locked    = st.locked,
              on_intensity = function(v)
                st.intensity = v
                if v > 0.0001 then st.prev_intensity = v end
              end,
              on_variance  = function(v) st.variance  = v end,
              on_lock      = function(new_locked) st.locked = new_locked end,
              on_reroll    = function() st.seed = math.random() end,
              on_toggle    = function(turning_on)
                if turning_on then
                  local restore = (st.prev_intensity and st.prev_intensity > 0.0001)
                    and st.prev_intensity or def.default_intensity
                  st.intensity = restore
                else
                  if st.intensity > 0.0001 then st.prev_intensity = st.intensity end
                  st.intensity = 0
                end
              end,
            })
          end
        end

        r.ImGui_Dummy(ctx, 0, 4)
        r.ImGui_TextColored(ctx, COL.muted,
          "Locked families (bypass / master out) are always 0. Switches default to 0; raise to flicker.")
      end

      -- ───────────────────────────────────────────────────────────
      -- Per-plugin overrides — fine-tune individual params
      -- ───────────────────────────────────────────────────────────
      if next(plugin_lib) ~= nil then
        r.ImGui_Dummy(ctx, 0, 4)
        if r.ImGui_CollapsingHeader(ctx, "Per-plugin overrides") then
          r.ImGui_TextColored(ctx, COL.muted,
            "Drag a param's intensity slider to override its family treatment.")
          r.ImGui_Dummy(ctx, 0, 2)
          local names = {}
          for n in pairs(plugin_lib) do names[#names + 1] = n end
          table.sort(names)
          for _, fx_name in ipairs(names) do
            local entry = plugin_lib[fx_name]
            if r.ImGui_TreeNode(ctx, fx_name) then
              local idxs = {}
              for k in pairs(entry) do idxs[#idxs + 1] = k end
              table.sort(idxs)
              for _, p in ipairs(idxs) do
                local rec = entry[p]
                if rec.family then  -- skip stale-format entries
                  local def = FAMILY_DEFS[rec.family]
                  r.ImGui_PushID(ctx, "ov_" .. fx_name .. "_" .. p)

                  -- Family dot
                  r.ImGui_TextColored(ctx, (def and def.color) or COL.muted, "●")
                  r.ImGui_SameLine(ctx, 0, 6)
                  r.ImGui_AlignTextToFramePadding(ctx)
                  r.ImGui_Text(ctx, string.format("%3d  %s", p, rec.name or "?"))

                  -- Right-aligned intensity slider + clear-override button
                  r.ImGui_SameLine(ctx)
                  local cw = r.ImGui_GetContentRegionAvail(ctx)
                  local slider_w = math.max(60, cw - 24)
                  r.ImGui_SetCursorPosX(ctx, r.ImGui_GetCursorPosX(ctx) + cw - slider_w - 24)

                  -- Compute the AUTO intensity for display (what the family gives)
                  local auto_int = param_intensity(fx_name, p, { family = rec.family,
                    sub_kind = rec.sub_kind, base_mult = rec.base_mult })
                  local cur_int = rec.user_int or auto_int

                  r.ImGui_SetNextItemWidth(ctx, slider_w)
                  -- Pre-bake percent label (slider value is 0..1; '%%%%' → literal '%').
                  local fmt = string.format(rec.user_int and "user %d%%%%" or "auto %d%%%%",
                    math.floor(cur_int * 100 + 0.5))
                  local ich, iv = r.ImGui_SliderDouble(ctx, "##int", cur_int, 0, 1, fmt)
                  if ich then
                    rec.user_int = iv
                    save_plugin_lib()
                  end
                  tooltip(ctx,
                    rec.user_int and "Manual override. Right-click ✕ to reset to auto."
                    or               "Following family settings. Drag to override.")

                  -- Clear-override button (only enabled when overridden)
                  r.ImGui_SameLine(ctx, 0, 4)
                  r.ImGui_BeginDisabled(ctx, rec.user_int == nil)
                  if r.ImGui_SmallButton(ctx, "✕") then
                    rec.user_int = nil
                    save_plugin_lib()
                  end
                  r.ImGui_EndDisabled(ctx)
                  tooltip(ctx, "Reset to auto (family-driven)")

                  r.ImGui_PopID(ctx)
                end
              end
              r.ImGui_TreePop(ctx)
            end
          end
        end
      end

      r.ImGui_PopStyleVar(ctx)
      r.ImGui_EndChild(ctx)
    end

    -- ─────────────────────────────────────────────────────────────
    -- Footer — walk shape, action surface
    -- Layout intent:
    --   Walk-shape group (always applies):
    --     Step size      [slider]
    --     Point density  [slider]
    --     Shape          [Lin][Hold][Smooth][In][Out][Bezier]│[Random]
    --     ☐ Show envelopes
    --   Action surface:
    --     [Write Once]   Iters [3]   [Write N× + Render ▶]
    --                    ☐ Render to takes  ☐ Add ReaLimit
    -- ─────────────────────────────────────────────────────────────
    r.ImGui_Separator(ctx)

    local LABEL_W = 110

    -- Step size (was "Severity") — fraction of param range per walk step.
    r.ImGui_AlignTextToFramePadding(ctx)
    r.ImGui_TextColored(ctx, COL.muted, "Step size")
    r.ImGui_SameLine(ctx, LABEL_W)
    r.ImGui_SetNextItemWidth(ctx, -1)
    local ch1, sv = r.ImGui_SliderDouble(ctx, "##stepsize", severity, 0.0, 1.0, "%.3f")
    if ch1 then severity = sv end
    save_on_commit(ctx)
    tooltip(ctx, "Walk step as a fraction of each parameter's range. Higher = bigger jumps per point.")

    -- Point density (was "Points / param") — number of envelope points per param.
    r.ImGui_AlignTextToFramePadding(ctx)
    r.ImGui_TextColored(ctx, COL.muted, "Point density")
    r.ImGui_SameLine(ctx, LABEL_W)
    r.ImGui_SetNextItemWidth(ctx, -1)
    local ch2, pv = r.ImGui_SliderInt(ctx, "##density", points_per_param, 2, 1024)
    if ch2 then points_per_param = pv end
    save_on_commit(ctx)
    tooltip(ctx, "Number of envelope points written across the time range, per parameter.")

    -- Shape row — weighted picker cells, with the Bezier-tension slider
    -- packed onto the same row to save vertical space. Each cell displays
    -- the curve thumbnail with a green fill rising from the bottom equal
    -- to the cell's weight. Drag vertically to set the weight; click to
    -- toggle between 0 and the last non-zero value. Per-point shape
    -- selection at write-time samples the distribution proportionally.
    r.ImGui_AlignTextToFramePadding(ctx)
    r.ImGui_TextColored(ctx, COL.muted, "Shape")
    r.ImGui_SameLine(ctx, LABEL_W)
    local CELL_W, CELL_H = 44, 28
    for i, sd in ipairs(SHAPE_DEFS) do
      if i > 1 then r.ImGui_SameLine(ctx, 0, 4) end
      local nw, np, changed, saved = shape_weight_cell(
        ctx, sd.id,
        shape_weights[sd.id] or 0,
        shape_prev_weights[sd.id] or 1.0,
        CELL_W, CELL_H)
      if changed then
        shape_weights[sd.id]      = nw
        shape_prev_weights[sd.id] = np
      end
      if saved then save_settings() end
      tooltip(ctx, string.format("%s — drag for weight, click to mute/unmute. (current: %d%%)",
        sd.name, math.floor((shape_weights[sd.id] or 0) * 100 + 0.5)))
    end

    -- Bezier tension on the same row, right of the cells. Disabled when
    -- Bezier weight ≤ 0 (no need to set tension if Bezier won't be sampled).
    r.ImGui_SameLine(ctx, 0, 12)
    r.ImGui_AlignTextToFramePadding(ctx)
    r.ImGui_TextColored(ctx, COL.muted, "Bezier")
    r.ImGui_SameLine(ctx, 0, 6)
    r.ImGui_BeginDisabled(ctx, (shape_weights[5] or 0) <= 0.001)
    r.ImGui_SetNextItemWidth(ctx, -1)
    local bch, bnv = r.ImGui_SliderDouble(ctx, "##beztension", bezier_tension, -1.0, 1.0, "%.2f")
    if bch then bezier_tension = bnv end
    save_on_commit(ctx)
    r.ImGui_EndDisabled(ctx)
    tooltip(ctx, "Bezier curve tension (-1..+1). Only used when the Bezier shape has weight > 0.")

    -- (Show envelopes moved into the Envelope-mode panel below.)

    -- Action surface ----------------------------------------------------------
    -- Two symmetric panels separated by a vertical divider. Both follow the
    -- rhythm:  heading → preference → state/config → primary action button.
    --
    -- ENVELOPE MODE                            │  RENDER-TO-TAKES MODE
    --                                          │
    -- ☐ Show envelopes after write             │  ☐ Add limiter
    -- Seed [N]   [<] [>]   Recent ▾            │  Takes [N]
    -- [          Write envelope          ]     │  [   Bounce N takes ▶   ]
    --
    -- Both panels render as 4 natural rows; buttons line up by construction.
    r.ImGui_Separator(ctx)

    -- Inline error line — reserves a fixed row height even when empty so
    -- the action panels below don't shift when an error appears/disappears.
    -- Errors expire automatically after a few seconds (set_inline_error).
    local err_row_h = r.ImGui_GetTextLineHeight(ctx)
    if _error_msg then
      local now = r.time_precise() or os.clock()
      if now < _error_until then
        r.ImGui_TextColored(ctx, COL.warn, "⚠  " .. _error_msg)
      else
        _error_msg = nil
        r.ImGui_Dummy(ctx, 0, err_row_h)
      end
    else
      r.ImGui_Dummy(ctx, 0, err_row_h)
    end

    local total_w   = r.ImGui_GetContentRegionAvail(ctx)
    local divider_w = 12
    local panel_w   = math.floor((total_w - divider_w) * 0.5)
    local action_x, action_y = r.ImGui_GetCursorScreenPos(ctx)
    local right_x = action_x + panel_w + divider_w

    -- ── LEFT PANEL: Envelope mode ────────────────────────────────────────────
    r.ImGui_BeginGroup(ctx)
      r.ImGui_TextColored(ctx, COL.muted, "ENVELOPE MODE")

      -- Row 2: Show envelopes after write — set-and-forget preference.
      local tg, tv = r.ImGui_Checkbox(ctx, "Show envelopes after write", show_envs)
      if tg then show_envs = tv; save_settings() end
      tooltip(ctx, "Make written envelopes visible & armed after the walk. Applies to bounces too.")

      -- Row 3: seed state + history navigation.
      -- Layout: Seed [input]  [<] [>]  Recent ▾
      -- The seed value sits left as the focal "you are here" readout; nav
      -- buttons sit immediately right of it; Recent jumps to the far right
      -- as a less-frequent action.
      r.ImGui_AlignTextToFramePadding(ctx)
      r.ImGui_TextColored(ctx, COL.faint, "Seed")
      r.ImGui_SameLine(ctx, 0, 6)
      -- Width budget: panel_w − label − nav cluster − Recent button − gaps.
      local NAV_W   = 24 + 2 + 24            -- < + gap + >
      local REC_W   = 78
      local GAPS    = 6 + 12 + 8             -- after label, before nav cluster, before Recent
      local input_w = math.max(80, panel_w - 40 - NAV_W - REC_W - GAPS)
      r.ImGui_SetNextItemWidth(ctx, input_w)
      local s_changed, s_new = r.ImGui_InputInt(ctx, "##envseed", walk_seed, 0, 0)
      if s_changed then
        if s_new < 0 then s_new = 0 end
        walk_seed = math.floor(s_new)
        record_seed(walk_seed)
        save_settings()
      end
      tooltip(ctx, "Master seed. Edit + Enter to set. < / > step through history; Recent ▾ for the full list.")

      -- Find walk_seed's position in history so we know whether < / > can move.
      -- Index 1 is the newest entry; higher indices are older.
      local hist_idx
      for i, h in ipairs(seed_history) do
        if h.s == walk_seed then hist_idx = i; break end
      end
      local can_go_older = hist_idx and hist_idx < #seed_history
      local can_go_newer = hist_idx and hist_idx > 1

      -- < older
      r.ImGui_SameLine(ctx, 0, 12)
      r.ImGui_BeginDisabled(ctx, not can_go_older)
      if r.ImGui_SmallButton(ctx, "<##histback") then
        walk_seed = seed_history[hist_idx + 1].s
        save_settings()
        do_write()
      end
      r.ImGui_EndDisabled(ctx)
      tooltip(ctx, "Previous seed in history (older). Loads + writes.")

      -- > newer
      r.ImGui_SameLine(ctx, 0, 2)
      r.ImGui_BeginDisabled(ctx, not can_go_newer)
      if r.ImGui_SmallButton(ctx, ">##histfwd") then
        walk_seed = seed_history[hist_idx - 1].s
        save_settings()
        do_write()
      end
      r.ImGui_EndDisabled(ctx)
      tooltip(ctx, "Next seed in history (newer). Loads + writes.")

      -- Recent ▾ — popup. Click row → replay.
      r.ImGui_SameLine(ctx, 0, 8)
      if r.ImGui_SmallButton(ctx, "Recent ▾") then r.ImGui_OpenPopup(ctx, "seed_history") end
      tooltip(ctx, "Past seeds for this project. Click any row to replay (loads + writes).")
      if r.ImGui_BeginPopup(ctx, "seed_history") then
        if #seed_history == 0 then
          r.ImGui_TextColored(ctx, COL.faint, "(empty — write something first)")
        else
          r.ImGui_TextColored(ctx, COL.muted, "Click any row to replay")
          r.ImGui_Separator(ctx)
          for i, h in ipairs(seed_history) do
            r.ImGui_PushID(ctx, "hist" .. i)
            local is_current = (h.s == walk_seed)
            if r.ImGui_Selectable(ctx, string.format("%-12d##sel", h.s), false, 0, 110, 0) then
              walk_seed = h.s
              save_settings()
              do_write()
              r.ImGui_CloseCurrentPopup(ctx)
            end
            r.ImGui_SameLine(ctx, 0, 8)
            if is_current then
              r.ImGui_TextColored(ctx, COL.primary, "← current")
            elseif h.t and h.t > 0 then
              r.ImGui_TextColored(ctx, COL.faint, os.date("%H:%M:%S", h.t))
            else
              r.ImGui_TextColored(ctx, COL.faint, "—")
            end
            r.ImGui_PopID(ctx)
          end
        end
        r.ImGui_EndPopup(ctx)
      end

      -- Row 4: primary action button.
      pushBtn(ctx, COL.primary, COL.primary_hi)
      if r.ImGui_Button(ctx, "Write envelope", panel_w, 0) then
        walk_seed = new_random_seed()
        record_seed(walk_seed)
        save_settings()
        do_write()
      end
      popBtn(ctx)
      tooltip(ctx, "Generate a new seed and write one random-walk pass. Use < / > or Recent ▾ to revisit a past seed.")
    r.ImGui_EndGroup(ctx)

    local _, left_bottom = r.ImGui_GetCursorScreenPos(ctx)

    -- ── RIGHT PANEL: Render-to-takes mode ───────────────────────────────────
    r.ImGui_SetCursorScreenPos(ctx, right_x, action_y)
    r.ImGui_BeginGroup(ctx)
      r.ImGui_TextColored(ctx, COL.muted, "RENDER-TO-TAKES MODE")

      -- Row 2: Add limiter — set-and-forget preference, mirrors Show envelopes.
      local tg3, tv3 = r.ImGui_Checkbox(ctx, "Add limiter", add_realimit)
      if tg3 then add_realimit = tv3; save_settings() end
      tooltip(ctx, "Insert ReaLimit on each track before bouncing — catches peaks from extreme walks.")

      -- Row 3: Takes count — vertical-drag spinner. ImGui's DragInt is
      -- hard-coded to horizontal mouse motion, so we roll our own with an
      -- InvisibleButton + GetMouseDragDelta on the Y axis. Drag UP to
      -- increase, DOWN to decrease, matching most DAW knob conventions.
      r.ImGui_AlignTextToFramePadding(ctx)
      r.ImGui_TextColored(ctx, COL.faint, "Takes")
      r.ImGui_SameLine(ctx, 0, 6)

      do
        local box_w   = 64
        local box_h   = r.ImGui_GetFrameHeight(ctx)
        local v_speed = 0.18              -- units per pixel of Y-drag
        local x0, y0  = r.ImGui_GetCursorScreenPos(ctx)
        r.ImGui_InvisibleButton(ctx, "##takes_y", box_w, box_h)
        local hovered = r.ImGui_IsItemHovered(ctx)
        local active  = r.ImGui_IsItemActive(ctx)

        -- On press: snapshot the current value and zero the drag accumulator
        -- so subsequent GetMouseDragDelta reads are relative to this click.
        if r.ImGui_IsItemActivated(ctx) then
          _takes_drag_start = num_iterations
          r.ImGui_ResetMouseDragDelta(ctx, 0)
        end
        if active then
          local _, dy = r.ImGui_GetMouseDragDelta(ctx, 0, 0)
          -- Negative dy = drag upward = increase. floor() gives a stable
          -- step so the value lands on integers as the cursor crosses each
          -- v_speed-pixel boundary.
          local offset = math.floor(-dy * v_speed)
          local target = _takes_drag_start + offset
          if target < 1 then target = 1 elseif target > 20 then target = 20 end
          num_iterations = target
        end
        -- Persist on release so Takes count survives close/open.
        if r.ImGui_IsItemDeactivated(ctx) then save_settings() end

        -- Show a NS-resize cursor while hovered/active so the gesture is
        -- discoverable without a tooltip.
        if hovered or active then
          r.ImGui_SetMouseCursor(ctx, r.ImGui_MouseCursor_ResizeNS())
        end

        -- Paint the box ourselves: rounded rectangle + centred number.
        local dl   = r.ImGui_GetWindowDrawList(ctx)
        local bg   = (active or hovered) and COL.bg_frame_hi or COL.bg_frame
        r.ImGui_DrawList_AddRectFilled(dl, x0, y0, x0 + box_w, y0 + box_h, bg, 4)
        local text   = tostring(num_iterations)
        local tw, th = r.ImGui_CalcTextSize(ctx, text)
        r.ImGui_DrawList_AddText(dl, x0 + (box_w - tw) * 0.5,
                                     y0 + (box_h - th) * 0.5,
                                     COL.text, text)
      end
      tooltip(ctx, "Drag up/down to change. How many take variations the bounce button produces.")

      -- Row 4: primary action button.
      local big_label = is_processing
        and "Bouncing…"
        or  string.format("Bounce %d takes ▶", num_iterations)
      r.ImGui_BeginDisabled(ctx, is_processing)
      pushBtn(ctx, COL.warn, COL.warn_hi)
      if r.ImGui_Button(ctx, big_label, panel_w, 0) then do_iterative_write() end
      popBtn(ctx)
      r.ImGui_EndDisabled(ctx)
      tooltip(ctx, "Run a fresh random walk N times and bounce each into a new take.")
    r.ImGui_EndGroup(ctx)

    local _, right_bottom = r.ImGui_GetCursorScreenPos(ctx)

    -- Vertical divider spans the taller of the two panels.
    local dl = r.ImGui_GetWindowDrawList(ctx)
    local div_x = math.floor(action_x + panel_w + divider_w * 0.5)
    local div_bottom = math.max(left_bottom, right_bottom)
    r.ImGui_DrawList_AddLine(dl, div_x, action_y, div_x, div_bottom, COL.bg_frame_hi, 1.0)

    r.ImGui_End(ctx)
  end

  theme.revert(ctx, theme_token)

  if open then
    r.defer(loop)
  else
    save_settings()
    -- Modern ReaImGui: contexts are managed by GC + Attach; no explicit DestroyContext.
  end
end

r.defer(loop)
