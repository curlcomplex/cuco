-- Envelopes System Functions for CUCO-OP
-- Provides time-based parameter interpolation for velocity, timing, and expression
-- Research: ai_workflows/research/in_progress/envelopes_research_2025-09-25.md

local envelopes = {}

-- Generate linear interpolation envelope
function envelopes.linear(start_val, end_val, steps)
    if not start_val or not end_val or not steps then
        return nil, "Invalid parameters for linear envelope"
    end

    if steps <= 0 then
        return {start_val}
    end

    if steps == 1 then
        return {start_val}
    end

    local envelope_values = {}
    local step_size = (end_val - start_val) / (steps - 1)

    for i = 0, steps - 1 do
        local value = start_val + (step_size * i)
        table.insert(envelope_values, value)
    end

    return envelope_values
end

-- Generate exponential curve envelope
function envelopes.exponential(start_val, end_val, steps, curve)
    if not start_val or not end_val or not steps then
        return nil, "Invalid parameters for exponential envelope"
    end

    curve = curve or 1.0  -- Default to linear if no curve specified

    if steps <= 0 then
        return {start_val}
    end

    if steps == 1 then
        return {start_val}
    end

    -- Handle edge cases for exponential calculation
    if start_val <= 0 or end_val <= 0 then
        -- Fall back to linear for zero/negative values
        return envelopes.linear(start_val, end_val, steps)
    end

    local envelope_values = {}
    local ratio = end_val / start_val

    for i = 0, steps - 1 do
        local t = i / (steps - 1)  -- Normalized time (0.0 to 1.0)

        if curve == 1.0 then
            -- Linear case
            local value = start_val + (end_val - start_val) * t
            table.insert(envelope_values, value)
        else
            -- Exponential curve: value = start * (ratio ^ (t ^ curve))
            local curved_t = t ^ curve
            local value = start_val * (ratio ^ curved_t)
            table.insert(envelope_values, value)
        end
    end

    return envelope_values
end

-- Generate ADSR envelope
function envelopes.adsr(attack_time, decay_time, sustain_level, release_time, total_steps)
    if not attack_time or not decay_time or not sustain_level or not release_time or not total_steps then
        return nil, "Invalid parameters for ADSR envelope"
    end

    if total_steps <= 0 then
        return {0}
    end

    -- Normalize times (should sum to <= 1.0)
    local total_time = attack_time + decay_time + release_time
    if total_time > 1.0 then
        -- Scale down proportionally
        local scale = 1.0 / total_time
        attack_time = attack_time * scale
        decay_time = decay_time * scale
        release_time = release_time * scale
    end

    local sustain_time = 1.0 - (attack_time + decay_time + release_time)
    if sustain_time < 0 then
        sustain_time = 0
    end

    -- Calculate steps for each phase
    local attack_steps = math.max(1, math.floor(attack_time * total_steps))
    local decay_steps = math.max(1, math.floor(decay_time * total_steps))
    local sustain_steps = math.max(0, math.floor(sustain_time * total_steps))
    local release_steps = math.max(1, total_steps - attack_steps - decay_steps - sustain_steps)

    local envelope_values = {}

    -- Attack phase (0.15 to 1.0) - start at usable velocity level
    local attack_env = envelopes.exponential(0.15, 1.0, attack_steps, 0.3)  -- Quick attack
    if attack_env then
        for _, val in ipairs(attack_env) do
            table.insert(envelope_values, val)
        end
    end

    -- Decay phase (1.0 to sustain_level)
    if decay_steps > 1 then
        local decay_env = envelopes.exponential(1.0, sustain_level, decay_steps, 2.0)  -- Natural decay
        if decay_env then
            -- Skip first value to avoid duplicate with attack peak
            for i = 2, #decay_env do
                table.insert(envelope_values, decay_env[i])
            end
        end
    elseif decay_steps == 1 then
        -- Single decay step, add sustain level directly
        table.insert(envelope_values, sustain_level)
    end

    -- Sustain phase (constant sustain_level)
    for i = 1, sustain_steps do
        table.insert(envelope_values, sustain_level)
    end

    -- Release phase (sustain_level to 0.15) - end at usable velocity level
    if release_steps > 1 then
        local release_env = envelopes.exponential(sustain_level, 0.15, release_steps, 2.0)  -- Natural release
        if release_env then
            -- Skip first value to avoid duplicate with sustain
            for i = 2, #release_env do
                table.insert(envelope_values, release_env[i])
            end
        end
    elseif release_steps == 1 then
        table.insert(envelope_values, 0.15)  -- Final release value - usable velocity level
    end
    
    -- Ensure we have exactly total_steps values by padding or truncating if needed
    while #envelope_values < total_steps do
        -- Pad with final value if we're short
        table.insert(envelope_values, envelope_values[#envelope_values] or sustain_level)
    end
    
    if #envelope_values > total_steps then
        -- Truncate if we have too many
        for i = total_steps + 1, #envelope_values do
            envelope_values[i] = nil
        end
    end

    return envelope_values
end

-- Generate custom multi-point envelope
function envelopes.custom(points, steps, curve_type)
    if not points or #points < 2 or not steps then
        return nil, "Invalid parameters for custom envelope"
    end

    curve_type = curve_type or "linear"

    if steps <= 0 then
        return {points[1].value}
    end

    -- Sort points by time
    table.sort(points, function(a, b) return a.time < b.time end)

    -- Normalize times to 0.0-1.0 range if needed
    local min_time = points[1].time
    local max_time = points[#points].time
    local time_range = max_time - min_time

    if time_range <= 0 then
        -- All points at same time, return first value
        return {points[1].value}
    end

    local envelope_values = {}

    for i = 0, steps - 1 do
        local t = i / (steps - 1)  -- Normalized time (0.0 to 1.0)
        local actual_time = min_time + (t * time_range)

        -- Find surrounding points
        local before_point = points[1]
        local after_point = points[#points]

        for j = 1, #points - 1 do
            if actual_time >= points[j].time and actual_time <= points[j + 1].time then
                before_point = points[j]
                after_point = points[j + 1]
                break
            end
        end

        -- Interpolate between points
        if before_point.time == after_point.time then
            -- Same time, use first point value
            table.insert(envelope_values, before_point.value)
        else
            local segment_t = (actual_time - before_point.time) / (after_point.time - before_point.time)

            if curve_type == "linear" then
                local value = before_point.value + (after_point.value - before_point.value) * segment_t
                table.insert(envelope_values, value)
            elseif curve_type == "exponential" then
                if before_point.value > 0 and after_point.value > 0 then
                    local ratio = after_point.value / before_point.value
                    local value = before_point.value * (ratio ^ segment_t)
                    table.insert(envelope_values, value)
                else
                    -- Fall back to linear for zero/negative values
                    local value = before_point.value + (after_point.value - before_point.value) * segment_t
                    table.insert(envelope_values, value)
                end
            else
                -- Default to linear
                local value = before_point.value + (after_point.value - before_point.value) * segment_t
                table.insert(envelope_values, value)
            end
        end
    end

    return envelope_values
end

-- Apply envelope to sequence of values (utility function)
function envelopes.apply_to_sequence(sequence, envelope_values, parameter)
    if not sequence or not envelope_values then
        return sequence
    end

    parameter = parameter or "velocity"  -- Default to velocity

    local result_sequence = {}

    for i, item in ipairs(sequence) do
        local new_item = {}
        -- Copy all existing properties
        for k, v in pairs(item) do
            new_item[k] = v
        end

        -- Apply envelope value
        local env_index = math.min(i, #envelope_values)
        local env_value = envelope_values[env_index]

        if parameter == "velocity" then
            new_item.velocity = math.floor(env_value)
        elseif parameter == "timing" then
            -- Apply as timing multiplier
            if new_item.duration then
                new_item.duration = new_item.duration * env_value
            end
        end

        table.insert(result_sequence, new_item)
    end

    return result_sequence
end

return envelopes
