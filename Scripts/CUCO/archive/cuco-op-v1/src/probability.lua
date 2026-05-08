-- Probability and Randomization system for CUCO-OP
-- Implements System Function: Probability & Randomization (stochastic elements)
--
-- Based on research: docs/research/completed/probability_randomization_research_2025-09-26.md
-- API Design: docs/system_functions/probability_api_design.md
--
-- Provides controlled random value generation, humanization effects, and deterministic 
-- pseudo-random sequences for musical composition with reproducibility through seeding.

local probability = {}

-- Dependencies for integration
local velocity  -- Lazy load to avoid circular dependency

-- Constants
probability.DEFAULT_SEED = nil
probability.MIN_VELOCITY = 1
probability.MAX_VELOCITY = 127
probability.MAX_TIMING_MS = 1000     -- Maximum timing offset in milliseconds
probability.MAX_PITCH_OFFSET = 24    -- Maximum pitch offset in semitones
probability.MAX_DURATION_MULT = 4.0  -- Maximum duration multiplier

-- LCG parameters (from Knuth recommendations)
local LCG_A = 1664525      -- Multiplier
local LCG_C = 1013904223   -- Increment  
local LCG_M = 4294967296   -- Modulus (2^32)

-- Internal RNG state
local rng_state = {
    seed = nil,           -- Current seed value
    current = nil,        -- Current LCG state
    normal_cache = nil,   -- Cached Box-Muller normal value
    has_cached = false    -- Whether cached normal value is available
}

-- Default humanization settings
probability.DEFAULT_HUMANIZATION = {
    timing_ms = 5,        -- Default timing variance in milliseconds
    velocity = 8,         -- Default velocity variance
    percentage = 80       -- Default percentage of events to humanize
}

------- CORE RANDOM NUMBER GENERATION -------

-- Set seed for reproducible randomization
function probability.set_seed(seed)
    if seed == nil then
        -- Use system time
        seed = os.time()
    elseif type(seed) ~= "number" or seed <= 0 or seed ~= math.floor(seed) then
        -- Invalid seed, use system time fallback
        seed = os.time()
    end
    
    rng_state.seed = seed
    rng_state.current = seed
    rng_state.has_cached = false  -- Invalidate cached normal
    
    return seed
end

-- Get current seed value
function probability.get_seed()
    return rng_state.seed
end

-- Generate next random number (0.0 to 1.0) using LCG
function probability.random()
    -- Initialize with system time if no seed set
    if rng_state.current == nil then
        probability.set_seed(nil)
    end
    
    -- LCG: X(n+1) = (a * X(n) + c) mod m
    rng_state.current = (LCG_A * rng_state.current + LCG_C) % LCG_M
    
    -- Convert to 0.0-1.0 range
    return rng_state.current / LCG_M
end

------- DISTRIBUTION FUNCTIONS -------

-- Generate uniform random number in range [min, max]
function probability.uniform(min, max)
    if min == nil or max == nil then
        return 0
    end
    
    if min > max then
        min, max = max, min  -- Swap if reversed
    end
    
    return min + (probability.random() * (max - min))
end

-- Generate normally distributed random number using Box-Muller transform
function probability.normal(mean, std_dev)
    mean = mean or 0
    std_dev = std_dev or 1
    
    if std_dev <= 0 then
        return mean  -- Degenerate case
    end
    
    -- Check for cached value from previous Box-Muller computation
    if rng_state.has_cached then
        rng_state.has_cached = false
        return mean + std_dev * rng_state.normal_cache
    end
    
    -- Box-Muller transform: generate two normal values
    local u1, u2
    repeat
        u1 = probability.random()
    until u1 > 0  -- Avoid log(0)
    
    u2 = probability.random()
    
    local mag = std_dev * math.sqrt(-2.0 * math.log(u1))
    local z0 = mag * math.cos(2.0 * math.pi * u2)
    local z1 = mag * math.sin(2.0 * math.pi * u2)
    
    -- Cache one value for next call
    rng_state.normal_cache = z1
    rng_state.has_cached = true
    
    return mean + z0
end

-- Generate exponentially distributed random number
function probability.exponential(lambda)
    lambda = lambda or 1.0
    
    if lambda <= 0 then
        return 0  -- Degenerate case
    end
    
    local u
    repeat
        u = probability.random()
    until u > 0  -- Avoid log(0)
    
    return -math.log(u) / lambda
end

-- Random choice from discrete values (with optional weights)
function probability.choice(values, weights)
    if not values or #values == 0 then
        return nil
    end
    
    if #values == 1 then
        return values[1]
    end
    
    if not weights or #weights ~= #values then
        -- Uniform choice
        local index = math.floor(probability.random() * #values) + 1
        return values[math.min(index, #values)]
    end
    
    -- Weighted choice
    local total_weight = 0
    for _, weight in ipairs(weights) do
        if type(weight) == "number" and weight >= 0 then
            total_weight = total_weight + weight
        end
    end
    
    if total_weight <= 0 then
        -- Fall back to uniform if all weights invalid
        local index = math.floor(probability.random() * #values) + 1
        return values[math.min(index, #values)]
    end
    
    local rand_weight = probability.random() * total_weight
    local cumulative = 0
    
    for i, weight in ipairs(weights) do
        if type(weight) == "number" and weight >= 0 then
            cumulative = cumulative + weight
            if rand_weight <= cumulative then
                return values[i]
            end
        end
    end
    
    -- Fallback (shouldn't reach here)
    return values[#values]
end

------- PARAMETER CLAMPING -------

-- Clamp parameter to valid MIDI ranges
function probability.clamp_parameter(value, parameter)
    if parameter == "velocity" then
        return math.max(probability.MIN_VELOCITY, 
                       math.min(probability.MAX_VELOCITY, math.floor(value + 0.5)))
    elseif parameter == "timing" then
        return math.max(-probability.MAX_TIMING_MS, 
                       math.min(probability.MAX_TIMING_MS, value))
    elseif parameter == "pitch" then
        return math.max(-probability.MAX_PITCH_OFFSET, 
                       math.min(probability.MAX_PITCH_OFFSET, math.floor(value + 0.5)))
    elseif parameter == "duration" then
        return math.max(0.1, math.min(probability.MAX_DURATION_MULT, value))
    else
        return value  -- Unknown parameter, return as-is
    end
end

------- HUMANIZATION FUNCTIONS -------

-- Apply humanization to event sequence
function probability.humanize_events(events, options)
    options = options or {}
    local timing_ms = options.ms or options.timing_ms or probability.DEFAULT_HUMANIZATION.timing_ms
    local velocity_var = options.vel or options.velocity or probability.DEFAULT_HUMANIZATION.velocity
    local percentage = options.pct or options.percentage or probability.DEFAULT_HUMANIZATION.percentage
    
    -- Validate parameters
    timing_ms = math.max(0, timing_ms or 0)
    velocity_var = math.max(0, velocity_var or 0)
    percentage = math.max(0, math.min(100, percentage or 100))
    
    if timing_ms == 0 and velocity_var == 0 then
        return events  -- No humanization to apply
    end
    
    -- Create modified events table
    local humanized_events = {}
    
    for _, event in ipairs(events) do
        local humanized_event = {}
        
        -- Copy all original event properties
        for k, v in pairs(event) do
            humanized_event[k] = v
        end
        
        -- Apply humanization with probability check
        if percentage >= 100 or (probability.random() * 100) <= percentage then
            
            -- Apply timing humanization (convert ms to quarter notes approximately)
            if timing_ms > 0 and event.s and event.e then
                local timing_offset_ms = probability.normal(0, timing_ms / 3)  -- 3-sigma within range
                local timing_offset_qn = timing_offset_ms / 1000.0 * 2.0  -- Approximate: 120 BPM = 2 QN/sec
                
                humanized_event.s = event.s + timing_offset_qn
                humanized_event.e = event.e + timing_offset_qn
                
                -- Ensure positive timing
                if humanized_event.s < 0 then
                    local adjustment = -humanized_event.s
                    humanized_event.s = 0
                    humanized_event.e = humanized_event.e + adjustment
                end
            end
            
            -- Apply velocity humanization
            if velocity_var > 0 and event.vel then
                local velocity_offset = probability.normal(0, velocity_var / 3)  -- 3-sigma within range
                humanized_event.vel = probability.clamp_parameter(event.vel + velocity_offset, "velocity")
            end
        end
        
        table.insert(humanized_events, humanized_event)
    end
    
    return humanized_events
end

------- PARAMETER RANDOMIZATION -------

-- Apply random distribution to specific parameter across events
function probability.randomize_parameter(events, parameter, distribution, params)
    if not events or #events == 0 then
        return events
    end
    
    params = params or {}
    local modified_events = {}
    
    for _, event in ipairs(events) do
        local modified_event = {}
        
        -- Copy all original event properties
        for k, v in pairs(event) do
            modified_event[k] = v
        end
        
        -- Generate random value based on distribution
        local random_value = 0
        
        if distribution == "uniform" then
            local min_val = params.min or 0
            local max_val = params.max or 100
            random_value = probability.uniform(min_val, max_val)
            
        elseif distribution == "normal" then
            local mean = params.mean or 50
            local std_dev = params.std or params.std_dev or 15
            random_value = probability.normal(mean, std_dev)
            
        elseif distribution == "exponential" then
            local lambda = params.lambda or 1.0
            random_value = probability.exponential(lambda)
            
        elseif distribution == "choice" then
            random_value = probability.choice(params.values, params.weights)
            
        else
            -- Unknown distribution, fall back to uniform
            random_value = probability.uniform(0, 100)
        end
        
        -- Apply random value to specified parameter
        if parameter == "velocity" and event.vel then
            if params.absolute ~= false then  -- Default to absolute replacement
                modified_event.vel = probability.clamp_parameter(random_value, "velocity")
            else  -- Relative adjustment
                modified_event.vel = probability.clamp_parameter(event.vel + random_value, "velocity")
            end
            
        elseif parameter == "pitch" and event.pitch then
            local pitch_offset = math.floor(random_value + 0.5)
            modified_event.pitch = event.pitch + probability.clamp_parameter(pitch_offset, "pitch")
            
        elseif parameter == "timing" and event.s and event.e then
            local timing_offset_ms = random_value
            local timing_offset_qn = timing_offset_ms / 1000.0 * 2.0  -- Approximate conversion
            
            modified_event.s = event.s + timing_offset_qn
            modified_event.e = event.e + timing_offset_qn
            
            -- Ensure positive timing
            if modified_event.s < 0 then
                local adjustment = -modified_event.s
                modified_event.s = 0
                modified_event.e = modified_event.e + adjustment
            end
            
        elseif parameter == "duration" and event.s and event.e then
            local duration_mult = probability.clamp_parameter(random_value, "duration")
            local original_duration = event.e - event.s
            modified_event.e = event.s + (original_duration * duration_mult)
        end
        
        table.insert(modified_events, modified_event)
    end
    
    return modified_events
end

------- PROBABILITY GATE -------

-- Apply probability gate to event processing
function probability.apply_probability_gate(events, probability_value)
    probability_value = probability_value or 1.0
    
    -- Clamp to valid range
    probability_value = math.max(0.0, math.min(1.0, probability_value))
    
    if probability_value >= 1.0 then
        return events  -- All events pass
    end
    
    if probability_value <= 0.0 then
        return {}  -- No events pass
    end
    
    local filtered_events = {}
    
    for _, event in ipairs(events) do
        if probability.random() <= probability_value then
            table.insert(filtered_events, event)
        end
    end
    
    return filtered_events
end

------- PROCESSOR INTEGRATION FUNCTIONS -------

-- Parse processor arguments from string format
local function parse_processor_args(args_string)
    if not args_string then
        return {}
    end
    
    -- Remove outer parentheses if present
    args_string = args_string:match("^%s*%((.*%)%s*$") or args_string
    
    local params = {}
    
    -- Parse key=value pairs and simple values
    for key_value in args_string:gmatch("([^,]+)") do
        key_value = key_value:match("^%s*(.-)%s*$")  -- Trim whitespace
        
        local key, value = key_value:match("^([%w_]+)%s*=%s*(.+)$")
        if key and value then
            -- Handle different value types
            if value:match("^%d+%.%d+$") then
                params[key] = tonumber(value)
            elseif value:match("^%d+$") then
                params[key] = tonumber(value)
            elseif value:match("^%[.*%]$") then
                -- Simple array parsing [1,2,3]
                local array = {}
                for item in value:gmatch("[%d%.]+") do
                    table.insert(array, tonumber(item))
                end
                params[key] = array
            else
                params[key] = value  -- String value
            end
        else
            -- Simple positional value
            if #params == 0 then
                params[1] = key_value
            else
                table.insert(params, key_value)
            end
        end
    end
    
    return params
end

-- Main processor function for !rand() syntax
function probability.process_rand(events, args_string)
    local params = parse_processor_args(args_string)
    
    if #params < 3 then
        return events  -- Need at least distribution, parameter, and one param
    end
    
    local distribution = params[1]
    local parameter = params[2]
    
    -- Build parameter table from remaining arguments
    local dist_params = {}
    for k, v in pairs(params) do
        if type(k) == "string" then
            dist_params[k] = v
        end
    end
    
    return probability.randomize_parameter(events, parameter, distribution, dist_params)
end

-- Enhanced humanization processor for !human() syntax  
function probability.process_human(events, args_string)
    local params = parse_processor_args(args_string)
    
    local options = {
        ms = params.ms or params.timing or params.timing_ms,
        vel = params.vel or params.velocity,
        pct = params.pct or params.percentage or params.prob
    }
    
    return probability.humanize_events(events, options)
end

-- Probability gate processor for !prob() syntax
function probability.process_prob(events, args_string)
    local params = parse_processor_args(args_string)
    
    local prob_value = 1.0
    if params[1] then
        prob_value = tonumber(params[1]) or 1.0
    end
    
    return probability.apply_probability_gate(events, prob_value)
end

------- INITIALIZATION -------

-- Initialize with default seed on first load
if rng_state.seed == nil then
    probability.set_seed(nil)  -- Use system time
end

return probability