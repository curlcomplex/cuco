-- CUCO-OP Executor
-- Converts AST to plan table for MIDI generation
--
-- Plan format: array of {pitch, s, e, vel, ch} tables
-- - pitch: MIDI note number (0-127)
-- - s: start time in quarter notes (QN)
-- - e: end time in quarter notes (QN)
-- - vel: velocity (1-127)
-- - ch: MIDI channel (1-16)

local executor = {}
local parser = require("parser")
local pitch = require("pitch")
local envelopes = require("envelopes")
local probability = require("probability")
local permutation = require("permutation")
local sort = require("sort")
local ambitus = require("ambitus")
local tonality = require("tonality")
local velocity = require("velocity")

-- Default execution context
executor.DEFAULT_CONTEXT = {
    grid = 16,              -- 16th note grid
    grid_suffix = "",       -- t=triplet, q=quintuplet, s=septuplet
    step_duration = 0.25,   -- QN per step (1/4 for 16th notes)
    current_time = 0.0,     -- Current time in QN
    scale_root = "c",       -- Scale root
    scale_quality = "major", -- Scale quality
    last_pitch = 60,        -- Last played pitch (for inherit)
    default_velocity = 96,  -- Default velocity
    default_channel = 1,    -- Default channel
    variables = {},         -- Variable storage
    accent_delta = 12,      -- Default normal accent increment
    human_ms = 0,           -- Humanization timing in ms (converted later by host, placeholder)
    human_vel = 0,          -- Velocity jitter +- range
    human_pct = 0,          -- Percentage of notes affected (0-100)
    probability_seed = nil  -- Current random seed (nil = system time)
}

-- Create execution context
function executor.create_context(base)
    local ctx = {}
    for k, v in pairs(base or executor.DEFAULT_CONTEXT) do
        if type(v) == "table" then
            ctx[k] = {}
            for k2, v2 in pairs(v) do
                ctx[k][k2] = v2
            end
        else
            ctx[k] = v
        end
    end
    return ctx
end

-- Note name to MIDI number conversion
local NOTE_OFFSETS = {
    c = 0, d = 2, e = 4, f = 5, g = 7, a = 9, b = 11
}

-- Convert MIDI number to note name (helper)
function executor.midi_to_note_name(midi_num)
    local note_names = {"C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "B"}
    return note_names[(midi_num % 12) + 1]
end

function executor.note_to_midi(note_name, accidental, flat, octave)
    -- Handle flat notation (c-3 = c3 with flat)
    if flat then
        octave = octave or 4
        accidental = "b"
    end

    octave = octave or 4
    local base = NOTE_OFFSETS[note_name:lower()]
    if not base then
        error("Invalid note name: " .. note_name)
    end

    -- Apply accidentals
    if accidental == "#" then
        base = base + 1
    elseif accidental == "b" then
        base = base - 1
    end

    return base + (octave * 12) + 12 -- +12 for MIDI octave offset (C4 = 60)
end

-- Update grid settings
function executor.update_grid(ctx, number, suffix)
    ctx.grid = number
    ctx.grid_suffix = suffix or ""

    -- Calculate step duration based on grid
    local base_duration = 4.0 / number -- QN duration for one step

    -- Handle triplets, quintuplets, etc.
    if suffix == "t" then
        base_duration = base_duration * (2/3) -- Triplet adjustment
    elseif suffix == "q" then
        base_duration = base_duration * (4/5) -- Quintuplet adjustment
    elseif suffix == "s" then
        base_duration = base_duration * (4/7) -- Septuplet adjustment
    end

    ctx.step_duration = base_duration
end

-- Execute program (main entry point)
function executor.execute(ast, context)
    local ctx = executor.create_context(context)
    local plan = {}

    executor.execute_program(ast, ctx, plan)

    return plan, ctx
end

-- Execute program node
function executor.execute_program(node, ctx, plan)
    if node.type ~= parser.AST_TYPES.PROGRAM then
        error("Expected program node")
    end

    for _, stmt in ipairs(node.statements) do
        executor.execute_statement(stmt, ctx, plan)
    end
end

-- Execute statement
function executor.execute_statement(node, ctx, plan)
    if node.type == parser.AST_TYPES.CONTEXT then
        -- Update scale context
        ctx.scale_root = node.root
        ctx.scale_quality = node.quality

    elseif node.type == parser.AST_TYPES.GRID then
        -- Update grid settings
        executor.update_grid(ctx, node.number, node.suffix)

    elseif node.type == 'accent_header' then
        if node.value then ctx.accent_delta = math.max(0, math.min(48, tonumber(node.value) or ctx.accent_delta)) end

    elseif node.type == 'human_header' then
        if node.ms then ctx.human_ms = tonumber(node.ms) or ctx.human_ms end
        if node.vel then ctx.human_vel = tonumber(node.vel) or ctx.human_vel end
        if node.pct then ctx.human_pct = math.max(0, math.min(100, tonumber(node.pct) or ctx.human_pct)) end
    
    elseif node.type == 'seed_header' then
        -- Set global random seed for reproducible randomization
        local seed_value = node.value and tonumber(node.value) or nil
        probability.set_seed(seed_value)
        ctx.probability_seed = probability.get_seed()

    elseif node.type == parser.AST_TYPES.ASSIGNMENT then
        -- Execute assignment (supports chained assignments)
        local result = executor.evaluate_expression(node.expression, ctx)

        -- Handle both single target (backward compatibility) and multiple targets (chained)
        local targets = node.targets or (node.target and {node.target} or {})
        
        -- Check if this assignment has any channel outputs
        local has_channel_outputs = false
        for _, target in ipairs(targets) do
            if target.type == "channel" or target.type == "output" then
                has_channel_outputs = true
                break
            end
        end
        
        -- Save time before processing any channel outputs in this statement
        local saved_time = ctx.current_time
        
        for _, target in ipairs(targets) do
            if target.type == "variable" then
                -- Store variable
                ctx.variables[target.name] = result

            elseif target.type == "channel" or target.type == "output" then
                -- Generate MIDI events for channel output
                local channel = (target.type == "channel") and target.name or ctx.default_channel
                -- Reset to saved time so this channel starts from statement beginning
                ctx.current_time = saved_time
                -- Use preserve_ctx_time=true to prevent each channel from advancing global time
                executor.generate_events(result, ctx, plan, channel, has_channel_outputs)
            end
        end
        
        -- If this statement had no channel outputs, preserve time progression
        if not has_channel_outputs then
            -- Time was updated during expression evaluation, keep it
        else
            -- For channel assignments, don't advance time between statements
            ctx.current_time = saved_time
        end

    else
        -- Execute standalone expression
        local result = executor.evaluate_expression(node, ctx)
        -- NEW: Generate events for standalone top-level musical material.
        -- This allows sequences like "CM F#m7" without assignment to still produce MIDI.
        if type(result) == "table" then
            if result.type or #result > 0 then
                executor.generate_events(result, ctx, plan, ctx.default_channel, false)
            end
        end
    end
end

-- Evaluate expression to get sequence of elements
function executor.evaluate_expression(node, ctx)
    if node.type == parser.AST_TYPES.STACK then
        return executor.evaluate_stack(node, ctx)

    elseif node.type == parser.AST_TYPES.CHORD then
        return executor.evaluate_chord(node, ctx)


    elseif node.type == parser.AST_TYPES.NOTE then
        return executor.evaluate_note(node, ctx)

    elseif node.type == parser.AST_TYPES.INHERIT then
        return executor.evaluate_inherit(node, ctx)

    elseif node.type == parser.AST_TYPES.REST then
        return {type = "rest"}

    elseif node.type == parser.AST_TYPES.SUSTAIN then
        return {type = "sustain"}

    elseif node.type == parser.AST_TYPES.REPEAT then
        return executor.evaluate_repeat(node, ctx)

    elseif node.type == parser.AST_TYPES.PROCESSOR then
        return executor.evaluate_processor(node, ctx)

    elseif node.type == parser.AST_TYPES.VARIABLE_REF then
        local value = ctx.variables[node.name]
        if not value then
            error("Undefined variable: " .. node.name)
        end
        return value

    else
        error("Unknown expression type: " .. node.type)
    end
end

-- Evaluate stack [elem1, elem2, ...]
function executor.evaluate_stack(node, ctx)
    local sequence = {}

    for _, element in ipairs(node.elements) do
        local result = executor.evaluate_expression(element, ctx)

        if type(result) == "table" and result.type then
            -- Single element
            table.insert(sequence, result)
        elseif type(result) == "table" and #result > 0 then
            -- Array of elements (from repeat, etc.)
            for _, item in ipairs(result) do
                table.insert(sequence, item)
            end
        end
    end

    return sequence
end

-- Evaluate chord (note1, note2, ...)
function executor.evaluate_chord(node, ctx)
    local chord_notes = {}

    for _, note_node in ipairs(node.notes) do
        local note = executor.evaluate_expression(note_node, ctx)
        table.insert(chord_notes, note)
    end

    return {type = "chord", notes = chord_notes}
end


-- Evaluate note
function executor.evaluate_note(node, ctx)
    local midi_pitch = executor.note_to_midi(node.note, node.accidental, node.flat, node.octave)

    -- Apply scale transformation if scale context exists
    if ctx.scale_root and ctx.scale_quality then
        -- Get the note's scale degree in C major first
        local c_major_degree = tonality.get_scale_degree(midi_pitch, "c", "major")
        
        if c_major_degree and c_major_degree.degree then
            -- Get the target scale
            local target_scale = tonality.get_scale_notes(ctx.scale_root, ctx.scale_quality, math.floor(midi_pitch / 12) - 1)
            
            if target_scale and target_scale[c_major_degree.degree] then
                -- Transform to the corresponding degree in the target scale
                midi_pitch = target_scale[c_major_degree.degree].pitch
            end
        end
    end

    if node.offset then
        midi_pitch = midi_pitch + node.offset
    end

    local velocity = ctx.default_velocity
    -- Velocity spec (absolute or relative sign preserved as string)
    if node.velocity_spec then
        local sign = node.velocity_spec:sub(1,1)
        local num = tonumber(node.velocity_spec)
        if sign == '+' or sign == '-' then
            if num then velocity = math.max(1, math.min(127, velocity + num)) end
        else
            local abs = tonumber(node.velocity_spec)
            if abs then velocity = math.max(1, math.min(127, abs)) end
        end
    end

    -- Accent
    if node.accent == 'normal' then
        velocity = math.min(127, velocity + 12)
    elseif node.accent == 'strong' then
        velocity = math.min(127, velocity + 24)
    end

    -- Check if this note should become a chord
    if node.chord_quality then
        -- Generate chord from note + quality
        local chord_symbol = string.upper(executor.midi_to_note_name(midi_pitch % 12)) .. node.chord_quality
        local chord_octave = math.floor(midi_pitch / 12) - 1
        
        local chord_notes = pitch.chord_to_notes(chord_symbol, chord_octave, pitch.VOICING_TYPES.CLOSE)
        
        -- Convert to note objects
        local notes = {}
        for _, midi_note in ipairs(chord_notes) do
            table.insert(notes, {
                type = "note",
                pitch = midi_note,
                velocity = velocity,
                articulation = node.articulation
            })
        end
        
        return {type = "chord", notes = notes}
    else
        -- Regular single note
        return {
            type = 'note',
            pitch = midi_pitch,
            velocity = velocity,
            articulation = node.articulation
        }
    end
end

-- Evaluate inherit (x, x^)
function executor.evaluate_inherit(node, ctx)
    return {
        type = "inherit",
        processed = node.processed,
        pitch = ctx.last_pitch,
        velocity = ctx.default_velocity
    }
end

-- Evaluate repeat (*N)
function executor.evaluate_repeat(node, ctx)
    local target = executor.evaluate_expression(node.target, ctx)
    local result = {}

    for i = 1, node.count do
        if type(target) == "table" and #target > 0 then
            -- Repeat array - deep copy to avoid reference issues
            for _, item in ipairs(target) do
                if type(item) == "table" then
                    local copy = {}
                    for k, v in pairs(item) do
                        copy[k] = v
                    end
                    table.insert(result, copy)
                else
                    table.insert(result, item)
                end
            end
        else
            -- Repeat single item - deep copy if table
            if type(target) == "table" then
                local copy = {}
                for k, v in pairs(target) do
                    copy[k] = v
                end
                table.insert(result, copy)
            else
                table.insert(result, target)
            end
        end
    end

    return result
end

-- Evaluate processor (!name(args))
function executor.evaluate_processor(node, ctx)
    local target = executor.evaluate_expression(node.target, ctx)
    if not (node.name) then return target end
    
    -- Ensure target is a proper sequence - deep copy to avoid modifying original
    if type(target) == "table" and target.type then
        -- Single element - make it a sequence
        local copy = {}
        for k, v in pairs(target) do
            if type(v) == "table" then
                local inner_copy = {}
                for ik, iv in pairs(v) do
                    inner_copy[ik] = iv
                end
                copy[k] = inner_copy
            else
                copy[k] = v
            end
        end
        target = {copy}
    elseif type(target) == "table" and #target > 0 then
        -- Array of elements - deep copy to avoid modifying original
        local copy = {}
        for i, item in ipairs(target) do
            if type(item) == "table" then
                local item_copy = {}
                for k, v in pairs(item) do
                    if type(v) == "table" then
                        local inner_copy = {}
                        for ik, iv in pairs(v) do
                            inner_copy[ik] = iv
                        end
                        item_copy[k] = inner_copy
                    else
                        item_copy[k] = v
                    end
                end
                copy[i] = item_copy
            else
                copy[i] = item
            end
        end
        target = copy
    end
    local lname = node.name:lower()
    -- !vel(curve,start,end) or !vel(+10) or !vel(90)
    if lname == 'vel' then
        if type(target) == 'table' then
            local args = node.args or ''
            local curve, a1, a2 = args:match('%(([%a_]+)%s*,%s*([%-%d]+)%s*,%s*([%-%d]+)%)')
            if curve and a1 and a2 then
                -- Apply linear interpolation over sequence order
                local start_v = tonumber(a1)
                local end_v = tonumber(a2)
                local seq = target
                local count = #seq
                for i, e in ipairs(seq) do
                    if e.pitch then
                        local v = start_v + (end_v - start_v) * ((i-1)/(math.max(count-1,1)))
                        e.velocity = math.max(1, math.min(127, math.floor(v)))
                    elseif e.notes then
                        -- chord
                        for _, n in ipairs(e.notes) do
                            local v = start_v + (end_v - start_v) * ((i-1)/(math.max(count-1,1)))
                            n.velocity = math.max(1, math.min(127, math.floor(v)))
                        end
                    end
                end
            else
                -- Simple single number or relative
                local simple = args:match('%(([%)%w%+%-]+)%)')
                if simple then
                    local num = tonumber(simple)
                    local rel = simple:match('^[%+%-]') ~= nil and tonumber(simple)
                    for _, e in ipairs(target) do
                        if e.pitch then
                            if rel then
                                e.velocity = math.max(1, math.min(127, e.velocity + rel))
                            elseif num then
                                e.velocity = math.max(1, math.min(127, num))
                            end
                        elseif e.notes then
                            for _, n in ipairs(e.notes) do
                                if rel then
                                    n.velocity = math.max(1, math.min(127, n.velocity + rel))
                                elseif num then
                                    n.velocity = math.max(1, math.min(127, num))
                                end
                            end
                        end
                    end
                end
            end
        end
    elseif lname == 'env' then
        -- env(parameter,curve,start,end) or env(curve,start,end) applies envelope interpolation across sequence
        local args = node.args or ''

        -- Parse env arguments with parentheses: (curve,start,end) or (param,curve,start,end) or (param,curve,arg1,arg2,arg3,arg4) for ADSR
        local curve, start_val, end_val = args:match('%(([%a_]+)%s*,%s*([%-%d%.]+)%s*,%s*([%-%d%.]+)%)')
        local param = 'velocity' -- Default to velocity parameter
        local adsr_args = {}

        if not curve then
            -- Try 4-arg format: (param,curve,start,end)
            local param_str, curve_str, start_str, end_str = args:match('%(([%a_]+)%s*,%s*([%a_]+)%s*,%s*([%-%d%.]+)%s*,%s*([%-%d%.]+)%)')
            if param_str and curve_str and start_str and end_str then
                param = param_str
                curve = curve_str
                start_val = start_str
                end_val = end_str
            else
                -- Try ADSR format: (param,adsr,attack,decay,sustain,release) - 6 args total
                local param_str, attack_str, decay_str, sustain_str, release_str = args:match('%(([%a_]+)%s*,%s*adsr%s*,%s*([%-%d%.]+)%s*,%s*([%-%d%.]+)%s*,%s*([%-%d%.]+)%s*,%s*([%-%d%.]+)%)')
                if param_str and attack_str and decay_str and sustain_str and release_str then
                    param = param_str
                    curve = 'adsr'
                    adsr_args = {tonumber(attack_str), tonumber(decay_str), tonumber(sustain_str), tonumber(release_str)}
                else
                    -- Try 5-arg ADSR format (no param, defaults to velocity): (adsr,attack,decay,sustain,release)
                    local attack_str2, decay_str2, sustain_str2, release_str2 = args:match('%(adsr%s*,%s*([%-%d%.]+)%s*,%s*([%-%d%.]+)%s*,%s*([%-%d%.]+)%s*,%s*([%-%d%.]+)%)')
                    if attack_str2 and decay_str2 and sustain_str2 and release_str2 then
                        param = 'velocity'  -- Default parameter
                        curve = 'adsr'
                        adsr_args = {tonumber(attack_str2), tonumber(decay_str2), tonumber(sustain_str2), tonumber(release_str2)}
                    end
                end
            end
        end

        -- Handle different envelope types based on what was parsed
        local process_envelope = false
        local seq = target
        local seq_len = #seq
        local env_values = nil
        local success = false

        if curve == 'adsr' and #adsr_args == 4 then
            -- ADSR envelope with parsed parameters
            process_envelope = true
            local attack_time = adsr_args[1]
            local decay_time = adsr_args[2] 
            local sustain_level = math.max(0, math.min(1, adsr_args[3]))  -- Clamp to 0-1 range
            local release_time = adsr_args[4]
            env_values = envelopes.adsr(attack_time, decay_time, sustain_level, release_time, seq_len)
            if env_values then
                -- Scale ADSR 0-1 values to MIDI range
                for i = 1, #env_values do
                    if env_values[i] then
                        env_values[i] = math.floor(env_values[i] * 127)
                    end
                end
                success = true
            end
        elseif curve and start_val and end_val then
            -- Linear/exponential envelopes with start/end values
            local start_num = tonumber(start_val)
            local end_num = tonumber(end_val)
            if start_num and end_num then
                process_envelope = true

                if curve == 'linear' then
                    env_values = envelopes.linear(start_num, end_num, seq_len)
                    success = env_values ~= nil
                elseif curve == 'exp' or curve == 'exponential' then
                    env_values = envelopes.exponential(start_num, end_num, seq_len, 2.0)
                    success = env_values ~= nil
                else
                    -- Default to linear for unknown curve types
                    env_values = envelopes.linear(start_num, end_num, seq_len)
                    success = env_values ~= nil
                end
            end
        end

        if process_envelope and seq_len > 0 then
            -- Apply envelope to sequence if generation succeeded
            if success and env_values then
                for i, e in ipairs(seq) do
                    local env_val = env_values[i]
                    if env_val then
                        if param == 'velocity' or param == 'vel' then
                            if e.pitch then
                                e.velocity = math.max(1, math.min(127, math.floor(env_val)))
                            elseif e.notes then
                                for _, n in ipairs(e.notes) do
                                    n.velocity = math.max(1, math.min(127, math.floor(env_val)))
                                end
                            end
                        end
                        -- Future: timing, pan, other parameters can be added here
                    end
                end
            end
        end
        return target
    elseif lname == 'human' then
        -- Enhanced humanization using probability module
        local args = node.args or ''
        target = probability.process_human(target, args)
    elseif lname == 'rand' then
        -- rand(distribution, parameter, params...) applies random distribution to specified parameter
        local args = node.args or ''
        target = probability.process_rand(target, args)
    elseif lname == 'prob' then
        -- prob(probability) applies probability gate to events
        local args = node.args or ''
        target = probability.process_prob(target, args)
    elseif lname == 'perm' then
        -- perm() or perm(type) applies permutations to sequence
        local args = node.args or ''
        target = executor.process_perm(target, args, ctx)
    elseif lname == 'retro' then
        -- retro() or retro(type=pitch) applies retrograde to sequence
        local args = node.args or ''
        target = executor.process_retro(target, args)
    elseif lname == 'rotate' then
        -- rotate(amount) or rotate(amount,type=pitch) applies rotation to sequence
        local args = node.args or ''
        target = executor.process_rotate(target, args)
    elseif lname == 'sort' or lname == 'sort_asc' or lname == 'sort_desc' then
        -- sort() or sort(desc) or sort(asc,type=pitch) applies sorting to sequence
        local args = node.args or ''
        target = executor.process_sort(target, args, node.name)
    elseif lname == 'ambitus' then
        -- ambitus(low,high) or ambitus(instrument) applies range constraint to sequence
        local args = node.args or ''
        target = executor.process_ambitus(target, args, "transpose")
    elseif lname == 'ambitus_filter' then
        -- ambitus_filter(low,high) removes out-of-range notes (converts to rests)
        local args = node.args or ''
        target = executor.process_ambitus(target, args, "filter")
    elseif lname == 'ambitus_invert' then
        -- ambitus_invert(low,high) inverts out-of-range notes around boundaries
        local args = node.args or ''
        target = executor.process_ambitus(target, args, "invert")
    elseif lname == 'ambitus_field' then
        -- ambitus_field(low,high) scales entire pitch field to fit range
        local args = node.args or ''
        target = executor.process_ambitus_field(target, args)
    elseif lname == 'ambitus_octaves' then
        -- ambitus_octaves(base,num_octaves) forces pitches into octave range
        local args = node.args or ''
        target = executor.process_ambitus_octaves(target, args)
    elseif lname == 'arp' then
        -- arp(direction) applies arpeggio to chords  
        local args = node.args or ''
        target = executor.process_arp(target, args)
    elseif lname == 'transpose' then
        -- transpose(semitones) transposes all pitches by specified interval
        local args = node.args or ''
        target = executor.process_transpose(target, args)
    elseif lname == 'invert' then
        -- invert() or invert(inversion_num) applies pitch inversion
        local args = node.args or ''
        target = executor.process_invert(target, args)
    elseif node.name:match('^[a-g][#b]?%.%w+$') then
        -- Chord/scale processors: c.major, f#.minor, etc.
        target = executor.process_chord_scale(target, node.name, node.args)
    else
        -- Unknown processor - log warning but continue
        reaper.ShowConsoleMsg("CUCO-OP Warning: Unknown processor '" .. node.name .. "'\n")
    end
    
    -- Return unwrapped result if it was wrapped as single element
    if type(target) == "table" and #target == 1 and target[1].type then
        return target[1]
    end
    return target
end

-- Generate MIDI events from sequence
function executor.generate_events(sequence, ctx, plan, channel, preserve_ctx_time)
    local current_time = ctx.current_time

    -- Handle different types of sequences
    if type(sequence) == "table" and sequence.type then
        -- Single element with type
        current_time = executor.generate_element_events(sequence, ctx, plan, channel, current_time)
    elseif type(sequence) == "table" and #sequence > 0 then
        -- Array of elements
        for _, element in ipairs(sequence) do
            current_time = executor.generate_element_events(element, ctx, plan, channel, current_time)
        end
    end

    -- Update context time only if not preserving it (for multi-channel assignments)
    if not preserve_ctx_time then
        ctx.current_time = current_time
    end
end

-- Generate events for a single element
function executor.generate_element_events(element, ctx, plan, channel, start_time)
    if element.type == "note" then
        local dur = ctx.step_duration
        if element.sub_div and element.sub_div > 1 then
            dur = dur / element.sub_div
        end
        local vel = element.velocity
        if element.articulation == 'stac' or element.articulation == 'staccato' then
            dur = dur * 0.5
        elseif element.articulation == 'leg' or element.articulation == 'legato' then
            dur = dur * 1.1
        elseif element.articulation == 'marc' or element.articulation == 'marcato' then
            dur = dur * 0.9
            vel = math.min(127, math.floor(vel * 1.2))
        elseif element.articulation == 'ghost' then
            dur = dur * 0.8
            vel = math.max(1, math.floor(vel * 0.6))
        end
        -- Apply global accent delta if original node had accent flag (not stored separately here) handled earlier; for now accent_header influences only explicit accent markers already applied via delta in evaluate_note.
        table.insert(plan, {
            pitch = element.pitch,
            s = start_time,
            e = start_time + dur,
            vel = vel,
            ch = channel
        })
        ctx.last_pitch = element.pitch
        if element.sub_div and element.sub_div > 1 then
            return start_time + (ctx.step_duration / element.sub_div)
        else
            return start_time + ctx.step_duration
        end

    elseif element.type == "chord" then
        local max_pitch = 0
        for _, note in ipairs(element.notes) do
            local dur = ctx.step_duration
            local vel = note.velocity
            if note.articulation == 'stac' or note.articulation == 'staccato' then
                dur = dur * 0.5
            elseif note.articulation == 'leg' or note.articulation == 'legato' then
                dur = dur * 1.1
            elseif note.articulation == 'marc' or note.articulation == 'marcato' then
                dur = dur * 0.9
                vel = math.min(127, math.floor(vel * 1.2))
            elseif note.articulation == 'ghost' then
                dur = dur * 0.8
                vel = math.max(1, math.floor(vel * 0.6))
            end
            table.insert(plan, {
                pitch = note.pitch,
                s = start_time,
                e = start_time + dur,
                vel = vel,
                ch = channel
            })
            if note.pitch > max_pitch then max_pitch = note.pitch end
        end
        ctx.last_pitch = max_pitch
        return start_time + ctx.step_duration

    elseif element.type == "inherit" then
        -- Use last pitch
        table.insert(plan, {
            pitch = element.pitch,
            s = start_time,
            e = start_time + ctx.step_duration,
            vel = element.velocity,
            ch = channel
        })

        return start_time + ctx.step_duration

    elseif element.type == "rest" then
        -- Silent step
        return start_time + ctx.step_duration

    elseif element.type == "sustain" then
        -- Continue last note(s) - extend duration of all events that were just played
        -- Find all events that end at the current start_time and extend them
        local extend_by = ctx.step_duration
        -- If previous element used subdivision, sustain should extend by substep too
        if plan[#plan] and plan[#plan].e == start_time then
            extend_by = plan[#plan].e - plan[#plan].s
        end
        if #plan > 0 then
            for i = #plan, 1, -1 do
                local event = plan[i]
                if event.e == start_time and event.ch == channel then
                    event.e = start_time + extend_by
                else
                    break
                end
            end
        end

        return start_time + extend_by

    else
        -- Unknown element type - skip
        return start_time + ctx.step_duration
    end
end

-- Main execute notation function
function executor.execute_notation(notation_string, context)
    local ast = parser.parse_notation(notation_string)
    return executor.execute(ast, context)
end

-- Permutation processor implementations

-- Process perm() processor
function executor.process_perm(events, args, ctx)
    -- Parse args: (), (all), (random), (messiaen), (messiaen,open), etc.
    local perm_type = "all"  -- Default
    local perm_args = {}
    local target_type = "full"
    
    if args and args ~= '' then
        -- Remove parentheses and parse
        local clean_args = args:match('%((.-)%)')
        if clean_args then
            -- Parse type=pitch, type=rhythm parameters
            local type_match = clean_args:match('type=(%w+)')
            if type_match then
                target_type = type_match
                clean_args = clean_args:gsub('type=%w+[,%s]*', '')
            end
            
            -- Parse main permutation type
            if clean_args == '' then
                perm_type = "all"
            else
                local parts = {}
                for part in clean_args:gmatch('[^,]+') do
                    table.insert(parts, part:match('^%s*(.-)%s*$'))  -- trim
                end
                
                if parts[1] then
                    perm_type = parts[1]
                    if perm_type == "messiaen" and parts[2] then
                        if parts[2] == "open" then
                            perm_type = "messiaen_open"
                        elseif parts[2] == "closed" then
                            perm_type = "messiaen_closed"
                        elseif parts[2] == "primary" then
                            perm_type = "messiaen_primary"
                        else
                            -- Custom order indices
                            local order = {}
                            for i = 2, #parts do
                                local idx = tonumber(parts[i])
                                if idx then table.insert(order, idx) end
                            end
                            if #order > 0 then
                                perm_type = "messiaen_custom"
                                perm_args.order = order
                            end
                        end
                    end
                end
            end
        end
    end
    
    -- Apply permutation based on target type
    if target_type == "pitch" then
        local pitches = permutation.extract_pitches(events)
        local perm_result = permutation.get_single_permutation(pitches, perm_type, perm_args, 1, probability.get_rng())
        return permutation.apply_pitch_permutation(events, perm_result)
    elseif target_type == "rhythm" then
        local rhythms = permutation.extract_rhythms(events)
        local perm_result = permutation.get_single_permutation(rhythms, perm_type, perm_args, 1)
        return permutation.apply_rhythm_permutation(events, perm_result)
    else
        -- Full event permutation
        return permutation.get_single_permutation(events, perm_type, perm_args, 1, probability.get_rng())
    end
end

-- Process retro() processor
function executor.process_retro(events, args)
    local target_type = "full"
    
    if args and args ~= '' then
        local clean_args = args:match('%((.-)%)')
        if clean_args then
            local type_match = clean_args:match('type=(%w+)')
            if type_match then
                target_type = type_match
            end
        end
    end
    
    if target_type == "pitch" then
        local pitches = permutation.extract_pitches(events)
        local retro_pitches = permutation.retrograde(pitches)
        return permutation.apply_pitch_permutation(events, retro_pitches)
    elseif target_type == "rhythm" then
        local rhythms = permutation.extract_rhythms(events)
        local retro_rhythms = permutation.retrograde(rhythms)
        return permutation.apply_rhythm_permutation(events, retro_rhythms)
    else
        return permutation.retrograde(events)
    end
end

-- Process rotate() processor
function executor.process_rotate(events, args)
    local amount = 1  -- Default rotation
    local target_type = "full"
    
    if args and args ~= '' then
        local clean_args = args:match('%((.-)%)')
        if clean_args then
            -- Parse type=pitch, type=rhythm parameters
            local type_match = clean_args:match('type=(%w+)')
            if type_match then
                target_type = type_match
                clean_args = clean_args:gsub('type=%w+[,%s]*', '')
            end
            
            -- Parse rotation amount
            if clean_args == "left" then
                amount = -1
            elseif clean_args == "right" then
                amount = 1
            else
                local num = tonumber(clean_args:match('^%-?%d+'))
                if num then amount = num end
            end
        end
    end
    
    if target_type == "pitch" then
        local pitches = permutation.extract_pitches(events)
        local rot_pitches = permutation.rotate(pitches, amount)
        return permutation.apply_pitch_permutation(events, rot_pitches)
    elseif target_type == "rhythm" then
        local rhythms = permutation.extract_rhythms(events)
        local rot_rhythms = permutation.rotate(rhythms, amount)
        return permutation.apply_rhythm_permutation(events, rot_rhythms)
    else
        return permutation.rotate(events, amount)
    end
end

-- Process sort() processor
function executor.process_sort(events, args, processor_name)
    -- Parse args: (), (asc), (desc), (asc,type=pitch), etc.
    local direction = "asc"  -- Default
    local sort_type = "full" -- Default
    
    -- Override direction based on processor name
    if processor_name == "sort_asc" then
        direction = "asc"
    elseif processor_name == "sort_desc" then
        direction = "desc"
    end
    
    if args and args ~= '' then
        -- Remove parentheses and parse
        local clean_args = args:match('%((.-)%)')
        if clean_args then
            -- Parse type=pitch, type=velocity parameters
            local type_match = clean_args:match('type=(%w+)')
            if type_match then
                sort_type = type_match
            end
            
            -- Parse direction (only if not explicitly set by processor name)
            if processor_name == "sort" then
                if clean_args:match('desc') then
                    direction = "desc"
                elseif clean_args:match('asc') then
                    direction = "asc"
                end
            end
        end
    end
    
    -- Apply sort using the sort module
    return sort.process_sort(events, direction, sort_type)
end

-- Process ambitus() processor
function executor.process_ambitus(events, args, mode)
    local low_pitch = nil
    local high_pitch = nil
    local instrument = nil
    
    if args and args ~= '' then
        local clean_args = args:match('%((.-)%)')
        if clean_args then
            -- Try to parse as instrument name first
            local instrument_match = clean_args:match('^([%w_]+)$')
            if instrument_match then
                instrument = instrument_match
            else
                -- Try to parse as (low,high) MIDI numbers
                local low_str, high_str = clean_args:match('^%s*(%d+)%s*,%s*(%d+)%s*$')
                if low_str and high_str then
                    low_pitch = tonumber(low_str)
                    high_pitch = tonumber(high_str)
                end
            end
        end
    end
    
    -- Apply ambitus constraint
    if instrument then
        local result, err = ambitus.apply_instrument_constraint(events, instrument, mode)
        if result then
            return result
        else
            -- Error handling - return original events on unknown instrument
            return events
        end
    elseif low_pitch and high_pitch then
        return ambitus.apply_range_constraint(events, low_pitch, high_pitch, mode)
    else
        -- Invalid arguments - return original events
        return events
    end
end

-- Process ambitus_field() processor  
function executor.process_ambitus_field(events, args)
    local low_pitch = 48  -- Default C3
    local high_pitch = 72 -- Default C5
    
    if args and args ~= '' then
        local clean_args = args:match('%((.-)%)')
        if clean_args then
            local low_str, high_str = clean_args:match('^%s*(%d+)%s*,%s*(%d+)%s*$')
            if low_str and high_str then
                low_pitch = tonumber(low_str)
                high_pitch = tonumber(high_str)
            end
        end
    end
    
    return ambitus.field_scale(events, low_pitch, high_pitch)
end

-- Process ambitus_octaves() processor
function executor.process_ambitus_octaves(events, args)
    local base_pitch = 60  -- Default C4
    local num_octaves = 1  -- Default 1 octave
    
    if args and args ~= '' then
        local clean_args = args:match('%((.-)%)')
        if clean_args then
            local base_str, octaves_str = clean_args:match('^%s*(%d+)%s*,%s*(%d+)%s*$')
            if base_str and octaves_str then
                base_pitch = tonumber(base_str)
                num_octaves = tonumber(octaves_str)
            end
        end
    end
    
    return ambitus.force_octaves(events, base_pitch, num_octaves)
end

-- Process arp() processor
function executor.process_arp(events, args)
    local direction = "up"  -- Default direction
    local speed = 1  -- steps per subdivision within one step
    
    if args and args ~= '' then
        local clean_args = args:match('%((.-)%)')
        if clean_args then
            -- Parse direction and speed: arp(up, 2) or arp(down, 4)
            local dir, speed_str = clean_args:match('^%s*(%w+)%s*,%s*(%d+)%s*$')
            if dir and speed_str then
                direction = dir:lower()
                speed = tonumber(speed_str) or 1
            else
                -- Just direction: arp(up)
                local dir_only = clean_args:match('^%s*(%w+)%s*$')
                if dir_only then
                    direction = dir_only:lower()
                end
            end
        end
    end
    
    -- Apply arpeggio to chord events only, subdividing a single step into `speed` parts
    local result = {}
    for _, event in ipairs(events) do
        if event.type == "chord" and event.notes then
            -- Extract pitches and velocities
            local pitches = {}
            local velocities = {}
            for _, note in ipairs(event.notes) do
                table.insert(pitches, note.pitch)
                table.insert(velocities, note.velocity or 96)
            end
            
            -- Order by direction while preserving velocity pairing
            local idx = {}
            for i=1,#pitches do idx[i]=i end
            table.sort(idx, function(a,b)
                if direction == "down" then return pitches[a] > pitches[b] else return pitches[a] < pitches[b] end
            end)
            local ordered_pitches, ordered_vel = {}, {}
            for _,i in ipairs(idx) do
                table.insert(ordered_pitches, pitches[i])
                table.insert(ordered_vel, velocities[i])
            end
            
            -- Ensure valid speed
            if not speed or speed < 1 then speed = 1 end
            
            -- Emit exactly `speed` notes within this one step, cycling pitches if needed
            for sub=1,speed do
                local j = ((sub-1) % #ordered_pitches) + 1
                table.insert(result, {
                    type = "note",
                    pitch = ordered_pitches[j],
                    velocity = ordered_vel[j] or 96,
                    sub_div = speed  -- used to shorten duration/advance time
                })
            end
        else
            -- Non-chord events pass through unchanged
            table.insert(result, event)
        end
    end
    
    return result
end

-- Process transpose() processor
function executor.process_transpose(events, args)
    local semitones = 0  -- Default no transposition
    
    if args and args ~= '' then
        local clean_args = args:match('%((.-)%)')
        if clean_args then
            local semitone_value = tonumber(clean_args:match('^[%+%-]?%d+'))
            if semitone_value then
                semitones = semitone_value
            end
        end
    end
    
    -- Apply transposition to all note events
    local result = {}
    for _, event in ipairs(events) do
        if event.type == "note" then
            local transposed_event = {}
            for k, v in pairs(event) do
                transposed_event[k] = v
            end
            transposed_event.pitch = event.pitch + semitones
            table.insert(result, transposed_event)
        elseif event.type == "chord" then
            local transposed_event = {
                type = "chord",
                notes = {}
            }
            for _, note in ipairs(event.notes) do
                local transposed_note = {}
                for k, v in pairs(note) do
                    transposed_note[k] = v
                end
                transposed_note.pitch = note.pitch + semitones
                table.insert(transposed_event.notes, transposed_note)
            end
            table.insert(result, transposed_event)
        else
            -- Non-pitch events pass through unchanged
            table.insert(result, event)
        end
    end
    
    return result
end

-- Process chord/scale processor (c.major, f#.minor, etc.)
function executor.process_chord_scale(events, processor_name, args)
    -- Parse processor name: "c.major" -> root="c", quality="major"
    local root, quality = processor_name:match('^([a-g][#b]?)%.(%w+)$')
    if not root or not quality then
        reaper.ShowConsoleMsg("CUCO-OP Error: Invalid chord/scale processor format: " .. processor_name .. "\n")
        return events
    end
    
    -- Apply scale transformation to all note events
    local result = {}
    for _, event in ipairs(events) do
        if event.type == "note" then
            -- Transform note according to scale context
            local transformed_event = {}
            for k, v in pairs(event) do
                transformed_event[k] = v
            end
            
            -- Get the note's scale degree in C major first
            local c_major_degree = tonality.get_scale_degree(event.pitch, "c", "major")
            
            if c_major_degree and c_major_degree.degree then
                -- Get the target scale
                local target_scale = tonality.get_scale_notes(root, quality, math.floor(event.pitch / 12) - 1)
                
                if target_scale and target_scale[c_major_degree.degree] then
                    -- Transform to the corresponding degree in the target scale
                    transformed_event.pitch = target_scale[c_major_degree.degree].pitch
                end
            end
            
            table.insert(result, transformed_event)
        elseif event.type == "chord" then
            -- Transform chord notes according to scale context
            local transformed_event = {
                type = "chord",
                notes = {}
            }
            
            for _, note in ipairs(event.notes) do
                local transformed_note = {}
                for k, v in pairs(note) do
                    transformed_note[k] = v
                end
                
                -- Get the note's scale degree in C major first
                local c_major_degree = tonality.get_scale_degree(note.pitch, "c", "major")
                
                if c_major_degree and c_major_degree.degree then
                    -- Get the target scale
                    local target_scale = tonality.get_scale_notes(root, quality, math.floor(note.pitch / 12) - 1)
                    
                    if target_scale and target_scale[c_major_degree.degree] then
                        -- Transform to the corresponding degree in the target scale
                        transformed_note.pitch = target_scale[c_major_degree.degree].pitch
                    end
                end
                
                table.insert(transformed_event.notes, transformed_note)
            end
            
            table.insert(result, transformed_event)
        else
            -- Non-pitch events pass through unchanged
            table.insert(result, event)
        end
    end
    
    return result
end

-- Process invert() processor
function executor.process_invert(events, args)
    local inversion_num = 1  -- Default first inversion
    
    if args and args ~= '' then
        local clean_args = args:match('%((.-)%)')
        if clean_args then
            local inv_value = tonumber(clean_args:match('^%d+'))
            if inv_value then
                inversion_num = inv_value
            end
        end
    end
    
    -- Apply inversion to chord events only
    local result = {}
    for _, event in ipairs(events) do
        if event.type == "chord" and event.notes then
            -- Extract pitches for inversion
            local pitches = {}
            for _, note in ipairs(event.notes) do
                table.insert(pitches, note.pitch)
            end
            
            -- Apply pitch inversion
            local inverted_pitches = pitch.invert(pitches, inversion_num)
            
            -- Reconstruct chord with inverted pitches
            local inverted_event = {
                type = "chord",
                notes = {}
            }
            for i, inverted_pitch in ipairs(inverted_pitches) do
                local original_note = event.notes[i] or event.notes[#event.notes]
                local inverted_note = {}
                for k, v in pairs(original_note) do
                    inverted_note[k] = v
                end
                inverted_note.pitch = inverted_pitch
                table.insert(inverted_event.notes, inverted_note)
            end
            table.insert(result, inverted_event)
        else
            -- Non-chord events pass through unchanged
            table.insert(result, event)
        end
    end
    
    return result
end

return executor
