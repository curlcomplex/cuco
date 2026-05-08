-- CUCO OP - IDE Interface
-- Author: Felix (felixtatic)
-- License: MIT
-- Description: Full-featured IDE interface for CUCO-OP with text editor, syntax highlighting, and engine integration

local SCRIPT_NAME = "CUCO OP"

-- Get script directory for engine access
local function get_script_dir()
  local info = debug.getinfo(1,'S')
  local src = info and info.source or ''
  local path = src:match('^@(.+)/[^/]+$') or ''
  return path
end

local ROOT = get_script_dir()
local SRC_DIR = ROOT .. "/src"

-- Add engine path
package.path = package.path .. ";" .. SRC_DIR .. "/?.lua"

-- Load CUCO-OP engine
local engine = nil
local engine_error = nil
local ok, result = pcall(require, "engine")
if ok then
    engine = result
else
    engine_error = "Failed to load engine: " .. tostring(result)
end

-- Load script library system
local script_library = require("script_library")
local template_migration = require("template_migration")
local undo_manager = require("undo_manager")

-- Try to load ReaImGui
local has_imgui, ctx = pcall(reaper.ImGui_CreateContext, SCRIPT_NAME)

-- Application State
local state = {
    open = true,

    -- Text Editor
    editor = {
        content = "~16\ntest = [c4 d4 e4 f4]\nch1 = test",
        cursor_line = 1,
        cursor_col = 1,
        is_dirty = false,
        file_path = nil,
        syntax_tokens = {},
        error_markers = {}
    },

    -- Execution Engine
    execution = {
        last_result = nil,
        last_error = nil,
        auto_execute = false,
        output_events = {},
        is_executing = false,
        auto_update_item = false,
        auto_update_locked = false,
        target_item = nil,
        last_selected_item = nil
    },

    -- UI State
    ui = {
        show_templates = true,
        show_documentation = true,
        show_output = true,
        window_width = 1200,
        window_height = 800,
        left_panel_width = 300,
        bottom_panel_height = 200,

        -- Script library state
        script_library = nil,
        selected_script = nil,
        selected_folder = "projects",
        preview_content = "",
        library_filter = "",

        -- Inline editing state
        editing_script_id = nil,
        editing_text = "",
        editing_is_new = false,
        editing_folder_id = nil,

        -- Panel sizing
        browser_height_ratio = 0.6, -- 60% browser, 40% preview

        -- Undo/redo stacks
        undo_stacks = {
            main_editor = nil,  -- Will be initialized with undo_manager
            preview = nil
        },

        -- Context menu state
        show_context_menu = false,
        context_menu_target = nil,
        context_menu_pos = {0, 0}
    },

    -- Legacy templates (now migrated to script library)
    -- Keeping minimal structure for backward compatibility
    template_categories = {},
    templates = {
        -- Basic Notation
        {
            name = "Basic Sequence",
            category = "Basic Notation",
            code = "~16 @c.major\nmelody = [c4 d4 e4 f4]\nch1 = melody"
        },
        {
            name = "Grid 16th Notes",
            category = "Basic Notation",
            code = "~16\nmelody = [c4 d4 e4 f4]\nch1 = melody"
        },
        {
            name = "Grid 8th Notes",
            category = "Basic Notation",
            code = "~8\nmelody = [c4 d4 e4 f4]\nch1 = melody"
        },
        {
            name = "Grid Quarter Notes",
            category = "Basic Notation",
            code = "~4\nmelody = [c4 d4 e4 f4]\nch1 = melody"
        },
        {
            name = "Scale Context",
            category = "Basic Notation",
            code = "~16 @f#.minor\nmelody = [c4 d4 e4 f4]\nch1 = melody"
        },

        -- Chord Progressions
        {
            name = "Chord Progress maj7-min7",
            category = "Chord Progressions",
            code = "~16 @c.major\nprog = [c4.maj7 d4.min7 g4.7 c4.maj7]\nch1 = prog"
        },
        {
            name = "Minor Chord Progression",
            category = "Chord Progressions",
            code = "~16\nprog = [a4.min d4.min e4.min f4.maj]\nch1 = prog"
        },
        {
            name = "Jazz Chords",
            category = "Chord Progressions",
            code = "~8\njazz = [c4.maj7 a4.min7 d4.min7 g4.7]\nch1 = jazz"
        },
        {
            name = "Manual Chord Notes",
            category = "Chord Progressions",
            code = "~16\nchord1 = (c4 e4 g4)\nchord2 = (d4 f4 a4)\nseq = [chord1 chord2]\nch1 = seq"
        },
        {
            name = "Basic Chord Qualities",
            category = "Chord Progressions",
            code = "~8\nbasic = [c4.maj d4.min e4.dim f4.aug]\nch1 = basic"
        },
        {
            name = "Seventh Chords",
            category = "Chord Progressions",
            code = "~8\nsevenths = [c4.maj7 d4.min7 e4.7 f4.dim7]\nch1 = sevenths"
        },
        {
            name = "Extended Chords",
            category = "Chord Progressions",
            code = "~4\nextended = [c4.9 f4.maj9 g4.min9]\nch1 = extended"
        },
        {
            name = "Chord Octaves",
            category = "Chord Progressions",
            code = "~8\noctaves = [c3.maj7 c4.maj7 c5.maj7]\nch1 = octaves"
        },
        {
            name = "Chord + Scale Context",
            category = "Chord Progressions",
            code = "~16 @f#.minor\nscaled_chords = [c4.maj7 d4.min7 e4.7]\nch1 = scaled_chords"
        },

        -- Rhythm Patterns
        {
            name = "Sustain Pattern",
            category = "Rhythm Patterns",
            code = "~16\ndrums = [- _ - _]*4\nch10 = drums"
        },
        {
            name = "Repeat Pattern",
            category = "Rhythm Patterns",
            code = "~16\npattern = [c4 d4]*8\nch1 = pattern"
        },
        {
            name = "Multi-Channel",
            category = "Rhythm Patterns",
            code = "~16\nkick = [- _ _ _]*4\nsnare = [_ - _ -]*4\nch1 = kick\nch2 = snare"
        },
        {
            name = "Rest Pattern",
            category = "Rhythm Patterns",
            code = "~16\npattern = [c4 . d4 . e4 . f4 .]\nch1 = pattern"
        },
        {
            name = "Inherit Pattern",
            category = "Rhythm Patterns",
            code = "~16\npattern = [c4 - - - d4 - - -]\nch1 = pattern"
        },

        -- Velocity Processors
        {
            name = "Vel Linear Envelope",
            category = "Processors",
            code = "~16\nmelody = [c4 d4 e4 f4] !vel(linear,60,120)\nch1 = melody"
        },
        {
            name = "Vel Fixed Value",
            category = "Processors",
            code = "~16\nmelody = [c4 d4 e4 f4] !vel(80)\nch1 = melody"
        },
        {
            name = "Vel Relative +20",
            category = "Processors",
            code = "~16\nmelody = [c4 d4 e4 f4] !vel(+20)\nch1 = melody"
        },
        {
            name = "Vel Relative -10",
            category = "Processors",
            code = "~16\nmelody = [c4 d4 e4 f4] !vel(-10)\nch1 = melody"
        },

        -- Envelope Processors
        {
            name = "Env Velocity Linear",
            category = "Processors",
            code = "~16\nmelody = [c4 d4 e4 f4] !env(velocity,linear,50,100)\nch1 = melody"
        },
        {
            name = "Env Velocity Exponential",
            category = "Processors",
            code = "~16\nmelody = [c4 d4 e4 f4] !env(velocity,exponential,30,127)\nch1 = melody"
        },
        {
            name = "Env Velocity ADSR",
            category = "Processors",
            code = "~16\nmelody = [c4 d4 e4 f4] !env(velocity,adsr,0.2,0.1,0.7,0.3)\nch1 = melody"
        },

        -- Transform Processors
        {
            name = "Transpose Up +7",
            category = "Processors",
            code = "~16\nmelody = [c4 d4 e4 f4] !transpose(7)\nch1 = melody"
        },
        {
            name = "Transpose Down -5",
            category = "Processors",
            code = "~16\nmelody = [c4 d4 e4 f4] !transpose(-5)\nch1 = melody"
        },
        {
            name = "Retrograde",
            category = "Processors",
            code = "~16\nmelody = [c4 d4 e4 f4] !retro()\nch1 = melody"
        },
        {
            name = "Rotate +1",
            category = "Processors",
            code = "~16\nmelody = [c4 d4 e4 f4] !rotate(1)\nch1 = melody"
        },
        {
            name = "Rotate -2",
            category = "Processors",
            code = "~16\nmelody = [c4 d4 e4 f4] !rotate(-2)\nch1 = melody"
        },
        {
            name = "Sort Ascending",
            category = "Processors",
            code = "~16\nmelody = [f4 c4 e4 d4] !sort_asc()\nch1 = melody"
        },
        {
            name = "Sort Descending",
            category = "Processors",
            code = "~16\nmelody = [c4 d4 e4 f4] !sort_desc()\nch1 = melody"
        },
        {
            name = "Transpose Chords",
            category = "Processors",
            code = "~16\nchords = [c4.maj7 f4.maj7 g4.7] !transpose(5)\nch1 = chords"
        },
        {
            name = "Chord + Velocity Envelope",
            category = "Processors",
            code = "~8\nchords = [c4.maj7 d4.min7 e4.min7 f4.maj7] !env(velocity,linear,50,100)\nch1 = chords"
        },

        -- Probability Processors
        {
            name = "Random Velocity",
            category = "Processors",
            code = "~16\nmelody = [c4 d4 e4 f4] !rand(uniform,velocity,50,100)\nch1 = melody"
        },
        {
            name = "Probability Gate 50%",
            category = "Processors",
            code = "~16\nmelody = [c4 d4 e4 f4] !prob(0.5)\nch1 = melody"
        },
        {
            name = "Human Timing",
            category = "Processors",
            code = "~16\nmelody = [c4 d4 e4 f4] !human(ms=10,vel=5,pct=50)\nch1 = melody"
        },
        -- Permutation Processors
        {
            name = "Perm All",
            category = "Processors",
            code = "~16\nmelody = [c4 d4 e4 f4] !perm(all)\nch1 = melody"
        },
        {
            name = "Perm Random",
            category = "Processors",
            code = "~16\nmelody = [c4 d4 e4 f4] !perm(random)\nch1 = melody"
        },
        {
            name = "Perm Messiaen Primary",
            category = "Processors",
            code = "~16\nmelody = [c4 d4 e4 f4] !perm(messiaen,primary)\nch1 = melody"
        },
        {
            name = "Perm Messiaen Open Fan",
            category = "Processors",
            code = "~16\nmelody = [c4 d4 e4 f4] !perm(messiaen,open)\nch1 = melody"
        },
        {
            name = "Perm Messiaen Closed Fan",
            category = "Processors",
            code = "~16\nmelody = [c4 d4 e4 f4] !perm(messiaen,closed)\nch1 = melody"
        },
        {
            name = "Perm Custom Order",
            category = "Processors",
            code = "~16\nmelody = [c4 d4 e4 f4] !perm(messiaen,3,0,2,1)\nch1 = melody"
        },
        {
            name = "Perm Pitch Only",
            category = "Processors",
            code = "~16\nmelody = [c4 d4 e4 f4] !perm(all,type=pitch)\nch1 = melody"
        },
        {
            name = "Perm Rhythm Only",
            category = "Processors",
            code = "~16\nmelody = [c4 d4 e4 f4] !perm(all,type=rhythm)\nch1 = melody"
        },
        {
            name = "Retro Pitch Only",
            category = "Processors",
            code = "~16\nmelody = [c4 d4 e4 f4] !retro(type=pitch)\nch1 = melody"
        },
        {
            name = "Retro Rhythm Only",
            category = "Processors",
            code = "~16\nmelody = [c4 d4 e4 f4] !retro(type=rhythm)\nch1 = melody"
        },
        {
            name = "Rotate Left/Right",
            category = "Processors",
            code = "~16\nmelody = [c4 d4 e4 f4] !rotate(left)\nch1 = melody"
        },
        {
            name = "Rotate Pitch Only",
            category = "Processors",
            code = "~16\nmelody = [c4 d4 e4 f4] !rotate(2,type=pitch)\nch1 = melody"
        },
        {
            name = "Sort Pitch Only",
            category = "Processors",
            code = "~16\nmelody = [f4 c4 e4 d4] !sort(asc,type=pitch)\nch1 = melody"
        },

        -- Advanced Probability Processors
        {
            name = "Rand Gaussian Velocity",
            category = "Processors",
            code = "~16\nmelody = [c4 d4 e4 f4] !rand(gaussian,velocity,mean=80,std=10)\nch1 = melody"
        },
        {
            name = "Rand Exponential Timing",
            category = "Processors",
            code = "~16\nmelody = [c4 d4 e4 f4] !rand(exponential,timing,lambda=0.1)\nch1 = melody"
        },
        {
            name = "Rand Beta Velocity",
            category = "Processors",
            code = "~16\nmelody = [c4 d4 e4 f4] !rand(beta,velocity,alpha=2,beta=5,min=60,max=120)\nch1 = melody"
        },
        {
            name = "Prob Gate 75%",
            category = "Processors",
            code = "~16\nmelody = [c4 d4 e4 f4] !prob(0.75)\nch1 = melody"
        },
        {
            name = "Human Heavy Timing",
            category = "Processors",
            code = "~16\nmelody = [c4 d4 e4 f4] !human(ms=20,vel=15,pct=100)\nch1 = melody"
        },

        -- Ambitus Functions
        {
            name = "Ambitus Transpose",
            category = "Ambitus Functions",
            code = "~16\nmelody = [c4 d4 e4 f4 g4] !ambitus(c3,c5)\nch1 = melody"
        },
        {
            name = "Ambitus Filter",
            category = "Ambitus Functions",
            code = "~16\nmelody = [c2 d4 e4 f4 g6] !ambitus_filter(c3,c5)\nch1 = melody"
        },
        {
            name = "Ambitus Invert",
            category = "Ambitus Functions",
            code = "~16\nmelody = [c2 d4 e4 f4 g6] !ambitus_invert(c3,c5)\nch1 = melody"
        },
        {
            name = "Ambitus Field",
            category = "Ambitus Functions",
            code = "~16\nmelody = [c2 d2 e2 f2 g2] !ambitus_field(c4,c5)\nch1 = melody"
        },
        {
            name = "Ambitus Octaves",
            category = "Ambitus Functions",
            code = "~16\nmelody = [c2 d6 e1 f7 g0] !ambitus_octaves(c4,2)\nch1 = melody"
        },

        -- Existing Test Suite
        {
            name = "Permutations Basic",
            category = "Existing Tests",
            code = "~16 \nch1 = [c4 d4 e4 f4]\nch2 = [c4 d4 e4 f4] !retro()\nch3 = [c4 d4 e4 f4] !rotate(1)\nch4 = [c4 d4 e4 f4] !rotate(-1)"
        },
        {
            name = "Probability Basic",
            category = "Existing Tests",
            code = "@seed(12345)\n~16 @c.major\nuniform_test = [c4 d4 e4 f4] !rand(uniform, velocity, min=60, max=100)\nch1 = uniform_test\nnormal_test = [c5 d5 e5 f5] !rand(normal, velocity, mean=80, std=10)\nch2 = normal_test\nhuman_test = [c3 d3 e3 f3] !human(ms=5, vel=8, pct=100)\nch3 = human_test"
        },
        {
            name = "Envelopes Basic",
            category = "Existing Tests",
            code = "~16 @96\nseq1 = [ c4 d4 e4 f4 g4 ] !env(linear,60,120)\nch1 = seq1"
        },
        {
            name = "Ambitus Basic",
            category = "Existing Tests",
            code = "~16\ntest_seq = [c2 d4 e4 f4 g6]\nch1 = test_seq !ambitus(c3,c5)"
        },
        {
            name = "Notation Chords",
            category = "Existing Tests",
            code = "~16 @c.major\nch1 = [c4.maj7 d4.min7 e4.min7 f4.maj7]\nch2 = [(c4 e4 g4) (d4 f4 a4)]\nch3 = [c4.maj7] !transpose(7)"
        },
        {
            name = "Notation Repeats",
            category = "Existing Tests",
            code = "~16\nch1 = [c4 d4]*4\nch2 = [[c4 e4]*2 [d4 f4]*2]\nch3 = [c4 d4 e4]*2"
        },
        {
            name = "Notation Sustain",
            category = "Existing Tests",
            code = "~16\nch1 = [c4 _ d4 _]\nch2 = [c4 d4 _ _ e4]\nch3 = [(c4 e4) _ _ (d4 f4)]"
        },
        {
            name = "Pitch System",
            category = "Existing Tests",
            code = "~16 @c.major\nch1 = [c4 d4 e4 f4]\nch2 = [c#4 d#4 e4 f#4]\nch3 = [cb4 db4 e4 fb4]"
        },

        -- New Chord Quality Tests
        {
            name = "Chord Quality Comprehensive",
            category = "Existing Tests",
            code = "~16 @c.major\n-- Basic triads\nbasic = [c4.maj d4.min e4.dim f4.aug]\nch1 = basic\n\n-- Seventh chords\nsevenths = [c4.maj7 d4.min7 e4.7 f4.dim7]\nch2 = sevenths\n\n-- Extended chords\nextended = [c4.9 f4.maj9 g4.min9]\nch3 = extended\n\n-- Different octaves\noctaves = [c3.maj7 c4.maj7 c5.maj7]\nch4 = octaves"
        },
        {
            name = "Chord Quality + Processors",
            category = "Existing Tests",
            code = "~8\n-- Chords with scale context\nscaled = [c4.maj7 d4.min7 e4.min7] @f#.minor\nch1 = scaled\n\n-- Chords with transpose\ntransposed = [c4.maj7 f4.7 g4.min7] !transpose(7)\nch2 = transposed\n\n-- Chords with velocity envelope\nvelenv = [c4.maj7 d4.min7 e4.7 f4.maj7] !env(velocity,linear,50,120)\nch3 = velenv"
        },

        -- Debug Tests (Only broken ones)
        {
            name = "Inherit Test - BROKEN",
            category = "Debug Tests (Broken)",
            code = "~16\nseq = [c4 - d4 -]\nch1 = seq"
        },
        {
            name = "Rest Pattern - BROKEN",
            category = "Debug Tests (Broken)",
            code = "~16\ndrums = [- . - .]*4\nch10 = drums"
        },
        {
            name = "Undefined Variable - BROKEN",
            category = "Debug Tests (Broken)",
            code = "~16\ndrums = [- _ - _]*4\nch10 = drum"
        }
    }
}

-- Initialize Script Library System
local function init_script_library()
    -- Initialize undo stacks
    state.ui.undo_stacks.main_editor = undo_manager.create_stack()
    state.ui.undo_stacks.preview = undo_manager.create_stack()

    -- Load or create script library
    local library = script_library.load_library()

    -- Check if we need to migrate templates
    if not library.migrated_templates then
        reaper.ShowConsoleMsg("CUCO-OP: Migrating templates to script library...\n")
        library = template_migration.migrate_templates(script_library)
        library.migrated_templates = true
        script_library.save_library(library)
        reaper.ShowConsoleMsg("CUCO-OP: Template migration completed\n")
    end

    -- Set up session folder
    local session_folder = script_library.get_session_folder(library)
    state.ui.selected_folder = session_folder
    script_library.save_library(library)

    state.ui.script_library = library

    -- Initialize main editor with initial content
    undo_manager.push_state(state.ui.undo_stacks.main_editor, state.editor.content, "Initial")
end

-- Initialize library on startup
init_script_library()

-- Utility Functions
local function defer(loop)
    reaper.defer(loop)
end

-- Text Editor Functions
local function parse_and_validate(text)
    if not engine then
        return nil, "Engine not loaded: " .. (engine_error or "Unknown error")
    end

    local ok, result = pcall(function()
        return engine.parse(text)
    end)

    if ok then
        return result, nil
    else
        return nil, tostring(result)
    end
end

local function execute_code(text)
    if not engine then
        local error_msg = "Engine not loaded: " .. (engine_error or "Unknown error")
        reaper.ShowConsoleMsg("CUCO-OP Error: " .. error_msg .. "\n")
        return nil, error_msg
    end

    state.execution.is_executing = true

    local ok, result = pcall(function()
        return engine.process_notation(text)
    end)

    state.execution.is_executing = false

    if ok then
        state.execution.last_result = result
        state.execution.output_events = result
        state.execution.last_error = nil
        reaper.ShowConsoleMsg(string.format("CUCO-OP: Generated %d MIDI events\n",
                             result and #result or 0))
        return result, nil
    else
        local error_msg = tostring(result)
        state.execution.last_error = error_msg
        state.execution.output_events = {}
        reaper.ShowConsoleMsg("CUCO-OP Error: " .. error_msg .. "\n")
        return nil, error_msg
    end
end

local function get_selected_midi_item()
    local item = reaper.GetSelectedMediaItem(0, 0)
    if item then
        local take = reaper.GetActiveTake(item)
        if take and reaper.TakeIsMIDI(take) then
            return item, take
        end
    end
    return nil, nil
end

local function check_selection_change()
    if state.execution.auto_update_locked then
        return -- Don't reset if locked
    end

    local current_item = reaper.GetSelectedMediaItem(0, 0)
    if current_item ~= state.execution.last_selected_item then
        state.execution.last_selected_item = current_item
        if current_item ~= state.execution.target_item then
            -- Selection changed to different item, reset auto-update
            state.execution.auto_update_item = false
            state.execution.target_item = nil
        end
    end
end

local function update_target_item()
    if not state.execution.output_events or #state.execution.output_events == 0 then
        return false
    end

    local item, take = get_selected_midi_item()
    if not item or not take then
        return false
    end

    -- Clear existing notes
    reaper.MIDI_DisableSort(take)

    -- Remove all notes (backwards to avoid index issues)
    local _, notes = reaper.MIDI_CountEvts(take)
    for i = notes - 1, 0, -1 do
        reaper.MIDI_DeleteNote(take, i)
    end

    -- Add new notes with beat-based timing
    local item_pos = reaper.GetMediaItemInfo_Value(item, "D_POSITION")
    local item_start_ppq = reaper.MIDI_GetPPQPosFromProjTime(take, item_pos)

    -- Get current BPM for time calculations
    local bpm = reaper.Master_GetTempo()
    local quarter_note_duration = 60.0 / bpm

    for _, event in ipairs(state.execution.output_events) do
        -- Convert CUCO beat positions to time offsets using BPM
        local start_offset = event.s * quarter_note_duration
        local end_offset = event.e * quarter_note_duration

        -- Convert to PPQ relative to item start
        local start_ppq = reaper.MIDI_GetPPQPosFromProjTime(take, item_pos + start_offset) - item_start_ppq
        local end_ppq = reaper.MIDI_GetPPQPosFromProjTime(take, item_pos + end_offset) - item_start_ppq

        reaper.MIDI_InsertNote(take, false, false, start_ppq, end_ppq,
                              (event.ch or 1) - 1, event.pitch, event.vel or 96, true)
    end

    reaper.MIDI_Sort(take)
    reaper.UpdateArrange()

    reaper.ShowConsoleMsg(string.format("CUCO-OP: Updated target item with %d MIDI events\n",
                         #state.execution.output_events))
    return true
end

local function export_debug_csv(notation, events, error_msg)
    -- Create timestamp for unique filename
    local timestamp = os.date("%Y%m%d_%H%M%S")
    local csv_filename = string.format("cuco_debug_%s.csv", timestamp)
    local csv_path = ROOT .. "/tests/user-reports/" .. csv_filename

    -- Open file for writing
    local file = io.open(csv_path, "w")
    if not file then
        reaper.ShowConsoleMsg("CUCO-OP Error: Could not create CSV file: " .. csv_path .. "\n")
        return nil
    end

    -- Write CSV header
    file:write("# CUCO-OP Debug Export\n")
    file:write("# Timestamp: " .. os.date("%Y-%m-%d %H:%M:%S") .. "\n")
    if error_msg then
        file:write("# ERROR: " .. error_msg .. "\n")
    end
    file:write("# Notation:\n")
    -- Write notation as comments
    for line in notation:gmatch("[^\n]+") do
        file:write("# " .. line .. "\n")
    end
    file:write("#\n")

    if error_msg then
        file:write("# No events generated due to error\n")
        file:write("error,message\n")
        file:write("1,\"" .. error_msg:gsub('"', '""') .. "\"\n")
    else
        file:write("# Event Data:\n")
        file:write("event_id,pitch,start_beat,end_beat,velocity,channel\n")

        -- Write event data
        if events and #events > 0 then
            for i, event in ipairs(events) do
                file:write(string.format("%d,%d,%.6f,%.6f,%d,%d\n",
                                        i, event.pitch, event.s, event.e, event.vel or 96, event.ch or 1))
            end
        else
            file:write("# No events generated\n")
        end
    end

    file:close()
    if error_msg then
        reaper.ShowConsoleMsg("CUCO-OP: Error debug data exported to " .. csv_path .. "\n")
    else
        reaper.ShowConsoleMsg("CUCO-OP: Debug data exported to " .. csv_path .. "\n")
    end
    return csv_path
end

local function generate_item_name(notation)
    -- Collect all meaningful notation lines and concatenate into single line
    local notation_lines = {}

    for line in notation:gmatch("[^\n]+") do
        local trimmed = line:match("^%s*(.-)%s*$")
        if trimmed ~= "" and not trimmed:match("^%-%-") then
            -- Clean the line for item naming (remove problematic characters)
            local clean_line = trimmed:gsub("[^%w%s@~%[%]=%-#,.()!_|+*]", "")
            if clean_line ~= "" then
                table.insert(notation_lines, clean_line)
            end
        end
    end

    -- Create comprehensive single-line name
    local timestamp = os.date("%H:%M:%S")

    if #notation_lines > 0 then
        -- Join all lines with " | " separator
        local full_notation = table.concat(notation_lines, " | ")

        -- Limit total length to reasonable size for item names
        if #full_notation > 80 then
            full_notation = full_notation:sub(1, 77) .. "..."
        end

        return string.format("CUCO %s - %s", timestamp, full_notation)
    else
        return string.format("CUCO %s - Empty", timestamp)
    end
end

local function send_to_reaper()
    -- Always execute first
    local result, error_msg = execute_code(state.editor.content)

    -- Always export CSV, even on error
    if error_msg then
        export_debug_csv(state.editor.content, nil, error_msg)
        return -- Error already logged in execute_code
    end

    -- Export debug CSV for successful execution
    export_debug_csv(state.editor.content, state.execution.output_events)

    if not state.execution.output_events or #state.execution.output_events == 0 then
        reaper.ShowConsoleMsg("CUCO-OP: No MIDI events to send\n")
        return
    end

    -- If auto-update is enabled and we have a target, update it
    if state.execution.auto_update_item and state.execution.target_item then
        if update_target_item() then
            return -- Successfully updated target item
        end
    end

    -- Get selected track or create new one if none selected
    local track = reaper.GetSelectedTrack(0, 0)
    if not track then
        local track_count = reaper.CountTracks(0)
        reaper.InsertTrackAtIndex(track_count, true)
        track = reaper.GetTrack(0, track_count)
        reaper.GetSetMediaTrackInfo_String(track, 'P_NAME', 'CUCO-OP Output', true)
        reaper.SetOnlyTrackSelected(track)
        reaper.ShowConsoleMsg("CUCO-OP: Created new track for output\n")
    end

    -- Create MIDI item at edit cursor using beats timebase
    local cursor_pos = reaper.GetCursorPosition()

    -- Find the maximum beat end from events
    local max_beat_end = 0
    for _, event in ipairs(state.execution.output_events) do
        if event.e > max_beat_end then max_beat_end = event.e end
    end

    -- Calculate item length using direct BPM calculation
    -- Get current BPM (more reliable than beat conversion functions)
    local bpm = reaper.Master_GetTempo()
    local quarter_note_duration = 60.0 / bpm  -- Duration of quarter note in seconds
    local item_length = max_beat_end * quarter_note_duration  -- CUCO beats are quarter-note units


    local item = reaper.CreateNewMIDIItemInProj(track, cursor_pos, cursor_pos + item_length, false)
    local take = reaper.GetActiveTake(item)

    -- Create clean item name with just timestamp for arrange view
    local timestamp = os.date("%H:%M:%S")
    local clean_item_name = string.format("CUCO %s", timestamp)

    -- Set the take name (this is what shows up in the arrange view)
    if take then
        reaper.GetSetMediaItemTakeInfo_String(take, "P_NAME", clean_item_name, true)
    end

    -- Set item notes to contain the full notation for detailed reference
    local clean_notation = state.editor.content:gsub("\n+", "\n"):gsub("^%s+", ""):gsub("%s+$", "")
    reaper.GetSetMediaItemInfo_String(item, "P_NOTES", clean_notation, true)

    -- Add notes with beat-based timing
    reaper.MIDI_DisableSort(take)
    for _, event in ipairs(state.execution.output_events) do
        -- Convert CUCO beat positions to time offsets using BPM
        local start_offset = event.s * quarter_note_duration
        local end_offset = event.e * quarter_note_duration

        -- Convert to PPQ relative to item start
        local start_ppq = reaper.MIDI_GetPPQPosFromProjTime(take, cursor_pos + start_offset)
        local end_ppq = reaper.MIDI_GetPPQPosFromProjTime(take, cursor_pos + end_offset)
        local item_start_ppq = reaper.MIDI_GetPPQPosFromProjTime(take, cursor_pos)

        start_ppq = start_ppq - item_start_ppq
        end_ppq = end_ppq - item_start_ppq

        reaper.MIDI_InsertNote(take, false, false, start_ppq, end_ppq,
                              (event.ch or 1) - 1, event.pitch, event.vel or 96, true)
    end
    reaper.MIDI_Sort(take)
    reaper.UpdateArrange()

    reaper.ShowConsoleMsg(string.format("CUCO-OP: Sent %d MIDI events to selected track at cursor position %.3fs (Item: %s)\n",
                         #state.execution.output_events, cursor_pos, clean_item_name))
end

-- ImGui Interface Functions
local function render_menu_bar()
    if reaper.ImGui_BeginMenuBar(ctx) then
        if reaper.ImGui_BeginMenu(ctx, "File") then
            if reaper.ImGui_MenuItem(ctx, "New") then
                state.editor.content = ""
                state.editor.is_dirty = false
                state.editor.file_path = nil
            end
            if reaper.ImGui_MenuItem(ctx, "Quick Save", "Ctrl+S") then
                -- Trigger new script creation with timestamp
                local timestamp = os.date("%H-%M-%S")
                state.ui.editing_script_id = "new_script_temp"
                state.ui.editing_text = string.format("Script_%s", timestamp)
                state.ui.editing_is_new = true
                state.ui.editing_folder_id = state.ui.selected_folder
            end
            reaper.ImGui_EndMenu(ctx)
        end

        if reaper.ImGui_BeginMenu(ctx, "Code") then
            if reaper.ImGui_MenuItem(ctx, "Send to REAPER", "F5") then
                send_to_reaper()
            end
            reaper.ImGui_Separator(ctx)
            local auto_execute_changed, auto_execute = reaper.ImGui_Checkbox(ctx, "Auto Send", state.execution.auto_execute)
            if auto_execute_changed then
                state.execution.auto_execute = auto_execute
            end
            reaper.ImGui_EndMenu(ctx)
        end

        if reaper.ImGui_BeginMenu(ctx, "View") then
            local templates_changed, show_templates = reaper.ImGui_Checkbox(ctx, "Templates", state.ui.show_templates)
            if templates_changed then
                state.ui.show_templates = show_templates
            end
            local docs_changed, show_docs = reaper.ImGui_Checkbox(ctx, "Documentation", state.ui.show_documentation)
            if docs_changed then
                state.ui.show_documentation = show_docs
            end
            local output_changed, show_output = reaper.ImGui_Checkbox(ctx, "Output", state.ui.show_output)
            if output_changed then
                state.ui.show_output = show_output
            end
            reaper.ImGui_EndMenu(ctx)
        end

        reaper.ImGui_EndMenuBar(ctx)
    end
end

-- Helper function to check if folder has matching content
local function folder_matches_filter(library, folder, filter)
    if filter == "" then return true end

    -- Check folder name
    if string.find(folder.name:lower(), filter:lower()) then
        return true
    end

    -- Check scripts in folder
    for _, script_id in ipairs(folder.children or {}) do
        local script = library.scripts[script_id]
        if script then
            if string.find(script.name:lower(), filter:lower()) then
                return true
            end
        else
            -- Check if it's a subfolder
            local subfolder = library.subfolders and library.subfolders[script_id]
            if subfolder and folder_matches_filter(library, subfolder, filter) then
                return true
            end
        end
    end

    -- Check template categories for templates folder
    if folder.id == "templates" and library.template_categories then
        for category_id, category_folder in pairs(library.template_categories) do
            if folder_matches_filter(library, category_folder, filter) then
                return true
            end
        end
    end

    return false
end

-- Helper function to render scripts in a folder
local function render_scripts_in_folder(scripts, folder_children, filter, context_prefix, folder_id)
    context_prefix = context_prefix or ""

    for _, script_id in ipairs(folder_children or {}) do
        local script = scripts[script_id]
        if script then
            local display_name = script.name
            if filter == "" or string.find(display_name:lower(), filter:lower()) then
                local is_selected = (state.ui.selected_script == script_id)
                local is_editing = (state.ui.editing_script_id == script_id)
                reaper.ImGui_PushID(ctx, script_id)
                if is_editing then
                    -- Inline editing mode
                    reaper.ImGui_SetKeyboardFocusHere(ctx)
                    local editing_changed, new_text = reaper.ImGui_InputText(ctx, "##edit", state.ui.editing_text)
                    if editing_changed then
                        state.ui.editing_text = new_text
                    end
                    -- Handle Enter/Escape
                    if reaper.ImGui_IsKeyPressed(ctx, reaper.ImGui_Key_Enter()) then
                        -- Save the edit
                        if state.ui.editing_text ~= "" and state.ui.editing_text ~= script.name then
                            -- Check for name collisions
                            local final_name = state.ui.editing_text
                            local counter = 1
                            local name_exists = true
                            while name_exists do
                                name_exists = false
                                for _, other_script in pairs(scripts) do
                                    if other_script.name == final_name and other_script.id ~= script_id then
                                        name_exists = true
                                        final_name = state.ui.editing_text .. "_" .. counter
                                        counter = counter + 1
                                        break
                                    end
                                end
                            end
                            script_library.update_script(state.ui.script_library, script_id, final_name, script.code)
                            script_library.save_library(state.ui.script_library)
                            reaper.ShowConsoleMsg(string.format("CUCO-OP: Renamed script to '%s'\n", final_name))
                        end
                        state.ui.editing_script_id = nil
                        state.ui.editing_text = ""
                    elseif reaper.ImGui_IsKeyPressed(ctx, reaper.ImGui_Key_Escape()) then
                        -- Cancel edit
                        state.ui.editing_script_id = nil
                        state.ui.editing_text = ""
                    end
                else
                    -- Normal display mode
                    if reaper.ImGui_Selectable(ctx, display_name, is_selected) then
                        state.ui.selected_script = script_id
                        state.ui.preview_content = script.code
                    end
                    -- Double-click to edit
                    if reaper.ImGui_IsItemHovered(ctx) and reaper.ImGui_IsMouseDoubleClicked(ctx, 0) then
                        state.ui.editing_script_id = script_id
                        state.ui.editing_text = script.name
                        state.ui.editing_is_new = false
                    end
                    -- Right-click context menu
                    if reaper.ImGui_IsItemClicked(ctx, reaper.ImGui_MouseButton_Right()) then
                        state.ui.show_context_menu = true
                        state.ui.context_menu_target = script_id
                        state.ui.context_menu_pos = {reaper.ImGui_GetMousePos(ctx)}
                    end
                    -- Quick action buttons
                    reaper.ImGui_SameLine(ctx)
                    if reaper.ImGui_SmallButton(ctx, "▶") then
                        -- Run script directly
                        local original_content = state.editor.content
                        state.editor.content = script.code
                        send_to_reaper()
                        state.editor.content = original_content
                        reaper.ShowConsoleMsg(string.format("CUCO-OP: Executed '%s'\n", script.name))
                    end
                    if reaper.ImGui_IsItemHovered(ctx) then
                        reaper.ImGui_SetTooltip(ctx, "Run script")
                    end
                    reaper.ImGui_SameLine(ctx)
                    if reaper.ImGui_SmallButton(ctx, "⇥") then
                        -- Load into editor
                        undo_manager.push_state(state.ui.undo_stacks.main_editor, state.editor.content, "Before Load")
                        state.editor.content = script.code
                        state.editor.is_dirty = false
                        undo_manager.push_state(state.ui.undo_stacks.main_editor, state.editor.content, "Load: " .. script.name)
                    end
                    if reaper.ImGui_IsItemHovered(ctx) then
                        reaper.ImGui_SetTooltip(ctx, "Load into editor")
                    end
                end
                reaper.ImGui_PopID(ctx)
            end
        end
    end

    -- Handle double-click on empty space to create new script
    if reaper.ImGui_IsWindowHovered(ctx) and reaper.ImGui_IsMouseDoubleClicked(ctx, 0) and folder_id then
        -- Check if we didn't click on any item
        if not reaper.ImGui_IsAnyItemHovered(ctx) then
            state.ui.editing_script_id = "new_script_temp"
            state.ui.editing_text = "New Script"
            state.ui.editing_is_new = true
            state.ui.editing_folder_id = folder_id
        end
    end

    -- Render new script creation if active
    if state.ui.editing_is_new and state.ui.editing_script_id == "new_script_temp" then
        reaper.ImGui_SetKeyboardFocusHere(ctx)
        local editing_changed, new_text = reaper.ImGui_InputText(ctx, "##new_script", state.ui.editing_text)
        if editing_changed then
            state.ui.editing_text = new_text
        end

        if reaper.ImGui_IsKeyPressed(ctx, reaper.ImGui_Key_Enter()) then
            -- Create new script
            if state.ui.editing_text ~= "" and state.editor.content ~= "" then
                -- Check for name collisions
                local final_name = state.ui.editing_text
                local counter = 1
                local name_exists = true
                while name_exists do
                    name_exists = false
                    for _, script in pairs(scripts) do
                        if script.name == final_name then
                            name_exists = true
                            final_name = state.ui.editing_text .. "_" .. counter
                            counter = counter + 1
                            break
                        end
                    end
                end

                local script_id = script_library.add_script(state.ui.script_library, state.ui.editing_folder_id, final_name, state.editor.content)
                script_library.save_library(state.ui.script_library)

                -- Add to undo history
                undo_manager.push_state(state.ui.undo_stacks.main_editor, state.editor.content, "Save: " .. final_name)

                state.editor.is_dirty = false
                reaper.ShowConsoleMsg(string.format("CUCO-OP: Saved script '%s'\n", final_name))
            end
            state.ui.editing_script_id = nil
            state.ui.editing_text = ""
            state.ui.editing_is_new = false
            state.ui.editing_folder_id = nil
        elseif reaper.ImGui_IsKeyPressed(ctx, reaper.ImGui_Key_Escape()) then
            -- Cancel new script
            state.ui.editing_script_id = nil
            state.ui.editing_text = ""
            state.ui.editing_is_new = false
            state.ui.editing_folder_id = nil
        end
    end
end

-- Helper function to render folder with subfolders
local function render_folder_recursive(library, folder, depth)
    depth = depth or 0
    local indent_size = depth * 4  -- Reduced indentation

    -- Check if folder should be shown based on filter
    if not folder_matches_filter(library, folder, state.ui.library_filter) then
        return
    end

    if indent_size > 0 then
        reaper.ImGui_Indent(ctx, indent_size)
    end

    -- Auto-expand folders when filtering
    local should_expand = folder.expanded or (state.ui.library_filter ~= "")
    local folder_flags = should_expand and reaper.ImGui_TreeNodeFlags_DefaultOpen() or 0

    if reaper.ImGui_CollapsingHeader(ctx, folder.name, folder_flags) then
        folder.expanded = true
        reaper.ImGui_Indent(ctx)

        -- Handle template categories specially
        if folder.id == "templates" and library.template_categories then
            for category_id, category_folder in pairs(library.template_categories) do
                render_folder_recursive(library, category_folder, depth + 1)
            end
        else
            -- Render subfolders if they exist
            if library.subfolders then
                for _, child_id in ipairs(folder.children or {}) do
                    local subfolder = library.subfolders[child_id]
                    if subfolder then
                        render_folder_recursive(library, subfolder, depth + 1)
                    else
                        -- It's a script, render it
                        render_scripts_in_folder(library.scripts, {child_id}, state.ui.library_filter, folder.name, folder.id)
                    end
                end
            else
                -- No subfolders, just render scripts
                render_scripts_in_folder(library.scripts, folder.children, state.ui.library_filter, folder.name, folder.id)
            end
        end

        reaper.ImGui_Unindent(ctx)

        -- Folder context menu (only for non-template folders)
        if reaper.ImGui_IsItemClicked(ctx, reaper.ImGui_MouseButton_Right()) and folder.id ~= "templates" then
            state.ui.show_context_menu = true
            state.ui.context_menu_target = folder.id
            state.ui.context_menu_pos = {reaper.ImGui_GetMousePos(ctx)}
        end
    else
        folder.expanded = false
    end

    if indent_size > 0 then
        reaper.ImGui_Unindent(ctx, indent_size)
    end
end

-- Main script browser function with split layout
local function render_script_browser()
    if not state.ui.show_templates then return end
    if not state.ui.script_library then return end

    local panel_height = state.ui.window_height - state.ui.bottom_panel_height - 80
    local browser_height = panel_height * state.ui.browser_height_ratio
    local preview_height = panel_height - browser_height - 40

    if reaper.ImGui_BeginChild(ctx, "ScriptLibraryContainer", state.ui.left_panel_width, panel_height) then
        -- === BROWSER PANEL (TOP) ===
        if reaper.ImGui_BeginChild(ctx, "Browser", state.ui.left_panel_width - 10, browser_height, reaper.ImGui_ChildFlags_None()) then
            reaper.ImGui_Text(ctx, "Script Library")
            reaper.ImGui_Separator(ctx)
            -- Render folders and scripts
            for _, folder in ipairs(state.ui.script_library.folders) do
                render_folder_recursive(state.ui.script_library, folder, 0)
            end
            reaper.ImGui_EndChild(ctx)
        end
        -- === SAVE INSTRUCTIONS ===
        reaper.ImGui_Separator(ctx)
        reaper.ImGui_TextWrapped(ctx, "💡 Double-click empty space to create new script, or double-click script name to rename")
        reaper.ImGui_Separator(ctx)
        -- === PREVIEW PANEL (BOTTOM) ===
        if reaper.ImGui_BeginChild(ctx, "Preview", state.ui.left_panel_width - 10, math.max(120, preview_height), reaper.ImGui_ChildFlags_Border) then
            if state.ui.selected_script then
                local script = state.ui.script_library.scripts[state.ui.selected_script]
                if script then
                    reaper.ImGui_Text(ctx, script.name)
                    reaper.ImGui_Separator(ctx)
                    reaper.ImGui_TextWrapped(ctx, script.code)
                end
            else
                reaper.ImGui_Text(ctx, "Select a script to preview")
            end
            reaper.ImGui_EndChild(ctx)
        end
        reaper.ImGui_EndChild(ctx)
    end

    -- Context menu rendering
    if state.ui.show_context_menu then
        reaper.ImGui_OpenPopup(ctx, "ContextMenu")
        state.ui.show_context_menu = false
    end

    if reaper.ImGui_BeginPopup(ctx, "ContextMenu") then
        if state.ui.context_menu_target then
            local target = state.ui.context_menu_target
            local is_script = state.ui.script_library.scripts[target] ~= nil

            local is_script = state.ui.script_library.scripts[target] ~= nil
            local is_folder = not is_script and script_library.find_folder(state.ui.script_library, target) ~= nil

            if is_script then
                if reaper.ImGui_MenuItem(ctx, "Rename Script") then
                    -- Start inline editing
                    local script = state.ui.script_library.scripts[target]
                    if script then
                        state.ui.editing_script_id = target
                        state.ui.editing_text = script.name
                        state.ui.editing_is_new = false
                    end
                end
                if reaper.ImGui_MenuItem(ctx, "Delete Script") then
                    script_library.delete_script(state.ui.script_library, target)
                    script_library.save_library(state.ui.script_library)
                    state.ui.selected_script = nil
                    state.ui.preview_content = ""
                    reaper.ShowConsoleMsg("CUCO-OP: Script deleted\n")
                end
            elseif is_folder then
                local folder = script_library.find_folder(state.ui.script_library, target)
                if folder and folder.type == "user" then  -- Only allow operations on user folders
                    if reaper.ImGui_MenuItem(ctx, "New Subfolder") then
                        -- TODO: Implement new folder functionality
                        reaper.ShowConsoleMsg("CUCO-OP: New folder functionality coming soon\n")
                    end
                end
            end
        end

        reaper.ImGui_EndPopup(ctx)
    end
end

local function render_documentation_panel()
    if not state.ui.show_documentation then return end

    if reaper.ImGui_BeginChild(ctx, "Documentation", state.ui.left_panel_width, state.ui.bottom_panel_height) then
        reaper.ImGui_Text(ctx, "Documentation")
        reaper.ImGui_Separator(ctx)

        -- Search box
        local search_text = ""
        local search_changed, new_search = reaper.ImGui_InputText(ctx, "Search", search_text)

        -- Function list
        local functions = {
            "ambitus(low, high)", "ambitus_filter(range)", "ambitus_field(range)",
            "vel(curve, start, end)", "env(type, params)", "arp(direction, steps)",
            "transpose(semitones)", "retro()", "rotate(amount)", "sort(direction)"
        }

        for _, func in ipairs(functions) do
            if reaper.ImGui_Selectable(ctx, func) then
                -- TODO: Show function documentation
            end
        end

        reaper.ImGui_EndChild(ctx)
    end
end

local function render_text_editor()
    local available_width = state.ui.window_width - (state.ui.show_templates and state.ui.left_panel_width or 0) - 20
    local available_height = state.ui.window_height - (state.ui.show_output and state.ui.bottom_panel_height or 0) - 80

    if reaper.ImGui_BeginChild(ctx, "Editor", available_width, available_height) then
        reaper.ImGui_Text(ctx, "CUCO-OP Editor")

        -- Undo/Redo controls
        local undo_stack = state.ui.undo_stacks.main_editor
        if undo_stack then
            local state_info = undo_manager.get_state_info(undo_stack)

            -- Undo button
            if not state_info.can_undo then
                reaper.ImGui_PushStyleVar(ctx, reaper.ImGui_StyleVar_Alpha(), 0.5)
            end
            if reaper.ImGui_Button(ctx, "↶ Undo") and state_info.can_undo then
                local content, err = undo_manager.undo(undo_stack)
                if content then
                    state.editor.content = content
                    state.editor.is_dirty = true
                end
            end
            if not state_info.can_undo then
                reaper.ImGui_PopStyleVar(ctx)
            end

            reaper.ImGui_SameLine(ctx)

            -- Redo button
            if not state_info.can_redo then
                reaper.ImGui_PushStyleVar(ctx, reaper.ImGui_StyleVar_Alpha(), 0.5)
            end
            if reaper.ImGui_Button(ctx, "↷ Redo") and state_info.can_redo then
                local content, err = undo_manager.redo(undo_stack)
                if content then
                    state.editor.content = content
                    state.editor.is_dirty = true
                end
            end
            if not state_info.can_redo then
                reaper.ImGui_PopStyleVar(ctx)
            end

            reaper.ImGui_SameLine(ctx)
            reaper.ImGui_Text(ctx, string.format("History: %d/%d", state_info.current_index, state_info.total_states))
        end

        reaper.ImGui_Separator(ctx)

        -- Main text editor
        local editor_height = available_height - 80 -- Leave space for undo/redo controls
        local editor_changed, new_content = reaper.ImGui_InputTextMultiline(ctx, "##editor",
                                                                           state.editor.content,
                                                                           available_width - 20,
                                                                           editor_height)
        if editor_changed then
            -- Add to undo history before changing
            if undo_stack then
                undo_manager.push_state(undo_stack, state.editor.content, "Edit")
            end

            state.editor.content = new_content
            state.editor.is_dirty = true

            -- Auto-send if enabled
            if state.execution.auto_execute then
                send_to_reaper()
            end
        end

        reaper.ImGui_EndChild(ctx)
    end
end

local function render_output_panel()
    if not state.ui.show_output then return end

    local available_width = state.ui.window_width - (state.ui.show_templates and state.ui.left_panel_width or 0) - 20

    if reaper.ImGui_BeginChild(ctx, "Output", available_width, state.ui.bottom_panel_height) then
        reaper.ImGui_Text(ctx, "Output & Status")
        reaper.ImGui_Separator(ctx)

        -- Send button
        if reaper.ImGui_Button(ctx, "Send to REAPER (F5)") then
            send_to_reaper()
        end
        reaper.ImGui_SameLine(ctx)
        if reaper.ImGui_Button(ctx, "Clear Output") then
            state.execution.output_events = {}
            state.execution.last_result = nil
            state.execution.last_error = nil
        end

        -- Auto-update toggle with smart behavior
        reaper.ImGui_Separator(ctx)

        local button_text = "Auto-Update Item"
        if state.execution.auto_update_locked then
            button_text = "🔒 Auto-Update (Locked)"
        elseif state.execution.auto_update_item then
            button_text = "✅ Auto-Update Item"
        end

        local item, take = get_selected_midi_item()
        local has_selection = (item ~= nil)

        if not has_selection then
            reaper.ImGui_PushStyleVar(ctx, reaper.ImGui_StyleVar_Alpha(), 0.5)
        end

        if reaper.ImGui_Button(ctx, button_text) then
            if has_selection then
                if reaper.ImGui_IsMouseClicked(ctx, reaper.ImGui_MouseButton_Right()) then
                    -- Right-click: Lock mode
                    state.execution.auto_update_locked = not state.execution.auto_update_locked
                    if state.execution.auto_update_locked then
                        state.execution.auto_update_item = true
                        state.execution.target_item = item
                    end
                else
                    -- Left-click: Normal toggle
                    state.execution.auto_update_item = not state.execution.auto_update_item
                    state.execution.auto_update_locked = false
                    if state.execution.auto_update_item then
                        state.execution.target_item = item
                    else
                        state.execution.target_item = nil
                    end
                end
            end
        end

        if not has_selection then
            reaper.ImGui_PopStyleVar(ctx)
        end

        -- Show status
        if state.execution.auto_update_item and state.execution.target_item then
            local target_name = "Selected MIDI Item"
            if state.execution.auto_update_locked then
                reaper.ImGui_Text(ctx, "🔒 Locked to: " .. target_name)
            else
                reaper.ImGui_Text(ctx, "📝 Updating: " .. target_name)
            end
        elseif not has_selection then
            reaper.ImGui_Text(ctx, "No MIDI item selected")
        end

        reaper.ImGui_Separator(ctx)

        -- Status display
        if state.execution.is_executing then
            reaper.ImGui_Text(ctx, "⏳ Executing...")
        elseif state.execution.last_error then
            reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Text(), 0xFF4444FF)
            reaper.ImGui_TextWrapped(ctx, "❌ Error: " .. state.execution.last_error)
            reaper.ImGui_PopStyleColor(ctx)
        elseif state.execution.output_events and #state.execution.output_events > 0 then
            reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Text(), 0xFF44AA44)
            reaper.ImGui_Text(ctx, "✅ Generated " .. #state.execution.output_events .. " MIDI events")
            reaper.ImGui_PopStyleColor(ctx)
        else
            reaper.ImGui_Text(ctx, "Ready")
        end

        -- Event details
        if state.execution.output_events and #state.execution.output_events > 0 then
            if reaper.ImGui_CollapsingHeader(ctx, "Event Details") then
                for i, event in ipairs(state.execution.output_events) do
                    local event_str = string.format("Event %d: pitch=%d, s=%.3f, e=%.3f, vel=%d, ch=%d",
                                                   i, event.pitch, event.s, event.e, event.vel or 96, event.ch or 1)
                    reaper.ImGui_Text(ctx, event_str)
                    if i > 10 then  -- Limit display for performance
                        reaper.ImGui_Text(ctx, "... and " .. (#state.execution.output_events - 10) .. " more events")
                        break
                    end
                end
            end
        end

        reaper.ImGui_EndChild(ctx)
    end
end

-- Main ImGui Loop
local function run_imgui(ctx)
    local function loop()
        if not state.open then return end

        -- Check for selection changes (unless locked)
        check_selection_change()

        -- Main window
        reaper.ImGui_SetNextWindowSize(ctx, state.ui.window_width, state.ui.window_height, reaper.ImGui_Cond_FirstUseEver())
        local visible, open = reaper.ImGui_Begin(ctx, SCRIPT_NAME, true, reaper.ImGui_WindowFlags_MenuBar())
        state.open = open

        if visible then
            -- Get current window size
            local window_width, window_height = reaper.ImGui_GetWindowSize(ctx)
            state.ui.window_width = window_width
            state.ui.window_height = window_height

            -- Handle keyboard shortcuts
            if reaper.ImGui_IsKeyPressed(ctx, reaper.ImGui_Key_F5()) then
                send_to_reaper()
            end

            -- Ctrl+Z for undo
            if reaper.ImGui_IsKeyPressed(ctx, reaper.ImGui_Key_Z()) and reaper.ImGui_IsKeyDown(ctx, reaper.ImGui_Mod_Ctrl()) then
                local undo_stack = state.ui.undo_stacks.main_editor
                if undo_stack then
                    local content, err = undo_manager.undo(undo_stack)
                    if content then
                        state.editor.content = content
                        state.editor.is_dirty = true
                    end
                end
            end

            -- Ctrl+Y for redo
            if reaper.ImGui_IsKeyPressed(ctx, reaper.ImGui_Key_Y()) and reaper.ImGui_IsKeyDown(ctx, reaper.ImGui_Mod_Ctrl()) then
                local undo_stack = state.ui.undo_stacks.main_editor
                if undo_stack then
                    local content, err = undo_manager.redo(undo_stack)
                    if content then
                        state.editor.content = content
                        state.editor.is_dirty = true
                    end
                end
            end

            -- Ctrl+S for quick save (start inline editing)
            if reaper.ImGui_IsKeyPressed(ctx, reaper.ImGui_Key_S()) and reaper.ImGui_IsKeyDown(ctx, reaper.ImGui_Mod_Ctrl()) then
                if not state.ui.editing_is_new then  -- Only if not already creating a new script
                    local timestamp = os.date("%H-%M-%S")
                    state.ui.editing_script_id = "new_script_temp"
                    state.ui.editing_text = string.format("Script_%s", timestamp)
                    state.ui.editing_is_new = true
                    state.ui.editing_folder_id = state.ui.selected_folder
                end
            end

            render_menu_bar()

            -- Layout panels
            if state.ui.show_templates then
                render_script_browser()
                reaper.ImGui_SameLine(ctx)
            end

            reaper.ImGui_BeginGroup(ctx)
            render_text_editor()
            if state.ui.show_output then
                render_output_panel()
            end
            reaper.ImGui_EndGroup(ctx)

            if state.ui.show_documentation and state.ui.show_templates then
                reaper.ImGui_SetCursorPosX(ctx, 10)
                reaper.ImGui_SetCursorPosY(ctx, window_height - state.ui.bottom_panel_height - 10)
                render_documentation_panel()
            end
        end

        reaper.ImGui_End(ctx)

        if state.open then defer(loop) end
    end

    loop()
end

-- GFX Fallback (simplified for now)
local function run_gfx()
    local W, H = 800, 600
    gfx.clear = 0x202020
    gfx.init(SCRIPT_NAME, W, H, 0)

    local function loop()
        if not state.open then return end

        gfx.x = 20; gfx.y = 20; gfx.set(1,1,1,1)
        gfx.drawstr("CUCO OP Enhanced")
        gfx.drawstr("\\nImGui not available - using basic fallback")
        gfx.drawstr("\\nInstall ReaImGui for full interface")

        local char = gfx.getchar()
        if char == -1 then state.open = false end
        if state.open then defer(loop) end
        gfx.update()
    end

    loop()
end

-- Entry Point
if has_imgui then
    run_imgui(ctx)
else
    run_gfx()
end
