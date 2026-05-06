-- Velocity and dynamics system for CUCO-OP
-- Implements System Function: Velocity (dynamics shaping)
--
-- Based on AIMS.md specification:
-- - Velocity per token: c4@96, range 1–127; relative @+10, @-15 adjusts from context
-- - Accent shorthand: ^ raises velocity by accent amount set via @accent(Δ); ! for strong accent
-- - Staccato/legato: c4.stac shortens to staccato percentage; c4.leg lengthens to legato overlap
-- - Articulation tags map to processors: .ten, .marc, .ghost, configurable tables
-- - Humanize: @human(ms=5, vel=6, pct=40) or token-level !human(ms=3, vel=4)

local velocity = {}

-- Default velocity values and ranges
velocity.DEFAULT_VELOCITY = 96
velocity.MIN_VELOCITY = 1
velocity.MAX_VELOCITY = 127

-- Default accent amounts
velocity.DEFAULT_ACCENT = 12     -- Standard accent increase
velocity.DEFAULT_STRONG_ACCENT = 24  -- Strong accent (!) increase

-- Default articulation settings
velocity.DEFAULT_STACCATO = 0.5   -- Staccato duration multiplier
velocity.DEFAULT_LEGATO = 1.1     -- Legato duration multiplier

-- Articulation mapping table (configurable)
velocity.ARTICULATION_MAP = {
    ten = "tenuto",       -- Full value
    marc = "marcato",     -- Accented and separated
    ghost = "ghost",      -- Soft, muted
    stac = "staccato",    -- Short and detached
    leg = "legato"        -- Smooth and connected
}

-- Context for tracking velocity state
velocity.Context = {
    base_velocity = velocity.DEFAULT_VELOCITY,
    accent_amount = velocity.DEFAULT_ACCENT,
    strong_accent_amount = velocity.DEFAULT_STRONG_ACCENT,
    staccato_factor = velocity.DEFAULT_STACCATO,
    legato_factor = velocity.DEFAULT_LEGATO,
    humanize_velocity = 0,  -- Velocity randomization amount
    humanize_timing = 0,    -- Timing randomization amount (ms)
    humanize_percent = 100  -- Percentage of events to humanize
}

function velocity.create_context()
    return {
        base_velocity = velocity.DEFAULT_VELOCITY,
        accent_amount = velocity.DEFAULT_ACCENT,
        strong_accent_amount = velocity.DEFAULT_STRONG_ACCENT,
        staccato_factor = velocity.DEFAULT_STACCATO,
        legato_factor = velocity.DEFAULT_LEGATO,
        humanize_velocity = 0,
        humanize_timing = 0,
        humanize_percent = 100
    }
end

-- Clamp velocity to valid MIDI range
function velocity.clamp_velocity(vel)
    return math.max(velocity.MIN_VELOCITY, math.min(velocity.MAX_VELOCITY, math.floor(vel + 0.5)))
end

-- Parse velocity specification from token
-- Supports: @96, @+10, @-15
function velocity.parse_velocity_spec(spec, context_velocity)
    context_velocity = context_velocity or velocity.DEFAULT_VELOCITY

    if not spec then
        return context_velocity
    end

    -- Remove @ prefix if present
    if spec:sub(1, 1) == "@" then
        spec = spec:sub(2)
    end

    -- Handle relative adjustments
    if spec:sub(1, 1) == "+" then
        local adjustment = tonumber(spec:sub(2))
        if adjustment then
            return velocity.clamp_velocity(context_velocity + adjustment)
        end
    elseif spec:sub(1, 1) == "-" then
        local adjustment = tonumber(spec:sub(2))
        if adjustment then
            return velocity.clamp_velocity(context_velocity - adjustment)
        end
    else
        -- Absolute velocity value
        local value = tonumber(spec)
        if value then
            return velocity.clamp_velocity(value)
        end
    end

    return context_velocity
end

-- Apply accent to velocity
-- accent_type: "normal" (^) or "strong" (!)
function velocity.apply_accent(base_vel, accent_type, context)
    context = context or velocity.Context

    if accent_type == "normal" then
        return velocity.clamp_velocity(base_vel + context.accent_amount)
    elseif accent_type == "strong" then
        return velocity.clamp_velocity(base_vel + context.strong_accent_amount)
    end

    return base_vel
end

-- Set accent amount via @accent(Δ)
function velocity.set_accent_amount(context, amount)
    context.accent_amount = math.max(0, amount or velocity.DEFAULT_ACCENT)
end

-- Apply articulation to note duration and velocity
-- Returns: {duration_multiplier, velocity_multiplier}
function velocity.apply_articulation(articulation, context)
    context = context or velocity.Context

    if articulation == "stac" or articulation == "staccato" then
        return {
            duration_multiplier = context.staccato_factor,
            velocity_multiplier = 1.0
        }
    elseif articulation == "leg" or articulation == "legato" then
        return {
            duration_multiplier = context.legato_factor,
            velocity_multiplier = 1.0
        }
    elseif articulation == "ten" or articulation == "tenuto" then
        return {
            duration_multiplier = 1.0,
            velocity_multiplier = 1.0
        }
    elseif articulation == "marc" or articulation == "marcato" then
        return {
            duration_multiplier = 0.9,  -- Slightly detached
            velocity_multiplier = 1.2   -- Accented
        }
    elseif articulation == "ghost" then
        return {
            duration_multiplier = 0.8,  -- Shortened
            velocity_multiplier = 0.6   -- Softened
        }
    end

    -- Default: no change
    return {
        duration_multiplier = 1.0,
        velocity_multiplier = 1.0
    }
end

-- Set humanization parameters
function velocity.set_humanize(context, timing_ms, velocity_amount, percentage)
    context.humanize_timing = math.max(0, timing_ms or 0)
    context.humanize_velocity = math.max(0, velocity_amount or 0)
    context.humanize_percent = math.max(0, math.min(100, percentage or 100))
end

-- Apply humanization to an event
-- Returns modified event (timing and velocity)
function velocity.apply_humanize(event, context, rng)
    context = context or velocity.Context
    rng = rng or math.random

    -- Check if this event should be humanized
    if context.humanize_percent < 100 and (rng() * 100) > context.humanize_percent then
        return event  -- No humanization
    end

    local humanized_event = {}
    for k, v in pairs(event) do
        humanized_event[k] = v
    end

    -- Apply timing humanization (convert ms to quarter notes)
    if context.humanize_timing > 0 then
        local timing_offset_ms = (rng() - 0.5) * 2 * context.humanize_timing
        local timing_offset_qn = timing_offset_ms / 1000.0 * 2.0  -- Approximate: 120 BPM = 2 QN/sec

        humanized_event.s = event.s + timing_offset_qn
        humanized_event.e = event.e + timing_offset_qn
    end

    -- Apply velocity humanization
    if context.humanize_velocity > 0 then
        local velocity_offset = (rng() - 0.5) * 2 * context.humanize_velocity
        humanized_event.vel = velocity.clamp_velocity(event.vel + velocity_offset)
    end

    return humanized_event
end

-- Create velocity curve processor
-- curve_type: "linear", "exp", "log", "sine", "custom"
-- start_vel, end_vel: velocity range
-- curve_data: for custom curves, array of velocity values
function velocity.create_velocity_curve(curve_type, start_vel, end_vel, curve_data)
    start_vel = start_vel or velocity.DEFAULT_VELOCITY
    end_vel = end_vel or velocity.DEFAULT_VELOCITY

    return function(events)
        local result = {}

        for i, event in ipairs(events) do
            local progress = (#events > 1) and ((i - 1) / (#events - 1)) or 0
            local curve_velocity = start_vel

            if curve_type == "linear" then
                curve_velocity = start_vel + (end_vel - start_vel) * progress
            elseif curve_type == "exp" then
                curve_velocity = start_vel + (end_vel - start_vel) * (progress * progress)
            elseif curve_type == "log" then
                curve_velocity = start_vel + (end_vel - start_vel) * math.sqrt(progress)
            elseif curve_type == "sine" then
                local sine_progress = (1 - math.cos(progress * math.pi)) / 2
                curve_velocity = start_vel + (end_vel - start_vel) * sine_progress
            elseif curve_type == "custom" and curve_data then
                local curve_index = math.floor(progress * (#curve_data - 1)) + 1
                curve_velocity = curve_data[curve_index] or start_vel
            end

            local modified_event = {}
            for k, v in pairs(event) do
                modified_event[k] = v
            end
            modified_event.vel = velocity.clamp_velocity(curve_velocity)

            table.insert(result, modified_event)
        end

        return result
    end
end

-- Common velocity curves
velocity.CURVES = {
    crescendo = function(events)
        return velocity.create_velocity_curve("exp", 60, 110)(events)
    end,

    diminuendo = function(events)
        return velocity.create_velocity_curve("exp", 110, 60)(events)
    end,

    swell = function(events)
        local mid_point = math.ceil(#events / 2)
        local first_half = {}
        local second_half = {}

        for i = 1, mid_point do
            table.insert(first_half, events[i])
        end
        for i = mid_point + 1, #events do
            table.insert(second_half, events[i])
        end

        local crescendo_first = velocity.create_velocity_curve("sine", 70, 110)(first_half)
        local diminuendo_second = velocity.create_velocity_curve("sine", 110, 70)(second_half)

        local result = {}
        for _, event in ipairs(crescendo_first) do
            table.insert(result, event)
        end
        for _, event in ipairs(diminuendo_second) do
            table.insert(result, event)
        end

        return result
    end
}

-- Processor function for DSL integration: !vel(...)
function velocity.processor_vel(params, events, context)
    if not params or #params == 0 then
        return events
    end

    local command = params[1]

    -- Direct velocity setting: !vel(96)
    if type(command) == "number" then
        local target_velocity = velocity.clamp_velocity(command)
        local result = {}

        for _, event in ipairs(events) do
            local modified_event = {}
            for k, v in pairs(event) do
                modified_event[k] = v
            end
            modified_event.vel = target_velocity
            table.insert(result, modified_event)
        end

        return result
    end

    -- Curve commands: !vel(crescendo), !vel(diminuendo), !vel(swell)
    if type(command) == "string" then
        if velocity.CURVES[command] then
            return velocity.CURVES[command](events)
        end

        -- Custom curve: !vel("linear", 60, 110)
        if command == "linear" or command == "exp" or command == "log" or command == "sine" then
            local start_vel = params[2] or velocity.DEFAULT_VELOCITY
            local end_vel = params[3] or velocity.DEFAULT_VELOCITY
            return velocity.create_velocity_curve(command, start_vel, end_vel)(events)
        end
    end

    return events
end

return velocity
