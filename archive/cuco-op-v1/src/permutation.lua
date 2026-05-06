-- CUCO-OP Permutation System Functions
-- Implements permutation-based sequence transformations including
-- all permutations, Messiaen techniques, retrograde, and rotation

local permutation = {}

-- Performance limits to prevent memory explosion
local MAX_PERMUTATIONS = 40320  -- 8! = 40,320 (reasonable limit)
local MAX_SEQUENCE_LENGTH = 8   -- Maximum for factorial permutation generation (8! = 40,320)

-- Utility Functions
local function copy_table(t)
    local result = {}
    for i, v in ipairs(t) do
        result[i] = v
    end
    return result
end

local function factorial(n)
    if n <= 1 then return 1 end
    local result = 1
    for i = 2, n do
        result = result * i
    end
    return result
end

local function sequences_equal(seq1, seq2)
    if #seq1 ~= #seq2 then return false end
    for i = 1, #seq1 do
        if seq1[i] ~= seq2[i] then return false end
    end
    return true
end

-- Validation Functions
local function validate_sequence_length(sequence, operation)
    if #sequence == 0 then
        error("Cannot " .. operation .. " empty sequence")
    end
    -- No arbitrary length limits for simple operations like retrograde/rotate
end

local function validate_complex_sequence_length(sequence, operation)
    if #sequence == 0 then
        error("Cannot " .. operation .. " empty sequence")
    end
    
    -- Only restrict operations that generate factorial combinations (all permutations)
    if operation:match("all permutations") and #sequence > 8 then
        error("All permutations not practical for sequences longer than 8 elements (factorial explosion)")
    elseif #sequence > 100 then
        -- General sanity limit for complex operations to prevent memory issues
        error(operation .. " not practical for sequences longer than 100 elements")
    end
end

local function validate_fan_permutation(sequence, fan_type)
    if #sequence % 2 ~= 0 then
        error(string.format("%s fan permutation requires even-length sequence (got %d)", 
              fan_type, #sequence))
    end
end

local function validate_custom_order(sequence, order)
    if #order ~= #sequence then
        error("Custom order length must match sequence length")
    end
    
    -- Check for valid indices (0-based as per OpenMusic)
    local used = {}
    for _, idx in ipairs(order) do
        if idx < 0 or idx >= #sequence then
            error("Custom order indices must be 0 to " .. (#sequence - 1))
        end
        if used[idx] then
            error("Custom order cannot have duplicate indices")  
        end
        used[idx] = true
    end
end

-- Core Permutation Algorithms

-- Generate all permutations using Heap's algorithm (limited for performance)
function permutation.all_permutations(sequence, max_count)
    validate_complex_sequence_length(sequence, "generate all permutations of")
    
    if #sequence > MAX_SEQUENCE_LENGTH then
        error("Sequence too long for all permutations (max " .. MAX_SEQUENCE_LENGTH .. " elements)")
    end
    
    local count = factorial(#sequence)
    max_count = max_count or (count > MAX_PERMUTATIONS and MAX_PERMUTATIONS or count)
    
    local results = {}
    local current = copy_table(sequence)
    
    local function heaps_generate(k)
        if #results >= max_count then return end
        
        if k == 1 then
            table.insert(results, copy_table(current))
            return
        end
        
        for i = 0, k-1 do
            heaps_generate(k-1)
            if #results >= max_count then return end
            
            -- Swap elements
            local swap_idx1, swap_idx2
            if k % 2 == 0 then
                swap_idx1, swap_idx2 = i+1, k
            else
                swap_idx1, swap_idx2 = 1, k
            end
            
            current[swap_idx1], current[swap_idx2] = current[swap_idx2], current[swap_idx1]
        end
    end
    
    heaps_generate(#sequence)
    return results
end

-- Generate single random permutation (Fisher-Yates shuffle)
function permutation.random_permutation(sequence, rng)
    validate_sequence_length(sequence, "randomly permute")
    
    local result = copy_table(sequence)
    rng = rng or math.random  -- Use provided RNG or default
    
    for i = #result, 2, -1 do
        local j = rng(i)
        result[i], result[j] = result[j], result[i]
    end
    
    return result
end

-- Messiaen Permutation Techniques

-- Messiaen's primary permutation technique
function permutation.messiaen_primary(sequence)
    validate_complex_sequence_length(sequence, "apply Messiaen primary permutation to")
    
    local function messiaen_transform_index(i, n)
        -- Messiaen's specific index transformation pattern
        if i == 1 then
            return n
        elseif i == n then  
            return 1
        else
            -- Cycle through middle elements
            return (i % (n - 1)) + 1
        end
    end
    
    local current = copy_table(sequence)
    local results = {copy_table(current)}
    local original = copy_table(sequence)
    
    repeat
        local next_seq = {}
        for i = 1, #current do
            local new_idx = messiaen_transform_index(i, #current)
            next_seq[i] = current[new_idx]
        end
        current = next_seq
        table.insert(results, copy_table(current))
    until sequences_equal(current, original)
    
    -- Remove the final duplicate of original
    table.remove(results)
    
    return results
end

-- Open fan permutation (interleave from outside inward)
function permutation.messiaen_open_fan(sequence)
    validate_fan_permutation(sequence, "open")
    
    local mid = #sequence / 2
    local result = {}
    
    for i = 1, mid do
        table.insert(result, sequence[i])
        table.insert(result, sequence[mid + i])
    end
    
    return result
end

-- Closed fan permutation (interleave from center outward) 
function permutation.messiaen_closed_fan(sequence)
    validate_fan_permutation(sequence, "closed")
    
    local mid = #sequence / 2
    local result = {}
    
    for i = 1, mid do
        table.insert(result, sequence[mid + 1 - i])
        table.insert(result, sequence[mid + i])
    end
    
    return result
end

-- Custom order permutation with user-defined indices
function permutation.messiaen_custom_order(sequence, order)
    validate_custom_order(sequence, order)
    
    local current = copy_table(sequence)
    local results = {copy_table(current)}
    local original = copy_table(sequence)
    
    repeat
        local next_seq = {}
        for i = 1, #current do
            -- Use 0-based indexing as per OpenMusic
            local src_idx = order[i] + 1  -- Convert to 1-based for Lua
            next_seq[i] = current[src_idx]
        end
        current = next_seq
        table.insert(results, copy_table(current))
    until sequences_equal(current, original)
    
    -- Remove the final duplicate of original
    table.remove(results)
    
    return results
end

-- Classical Transformations

-- Simple retrograde/reverse
function permutation.retrograde(sequence)
    validate_sequence_length(sequence, "retrograde")
    
    local result = {}
    for i = #sequence, 1, -1 do
        table.insert(result, sequence[i])
    end
    return result
end

-- Rotate sequence by specified amount
function permutation.rotate(sequence, amount)
    validate_sequence_length(sequence, "rotate")
    
    if amount == 0 then
        return copy_table(sequence)
    end
    
    local n = #sequence
    -- Normalize amount to positive value within sequence length
    amount = ((amount % n) + n) % n
    
    local result = {}
    for i = 1, n do
        local src_idx = ((i - 1 - amount) % n) + 1
        result[i] = sequence[src_idx]
    end
    
    return result
end

-- Type-specific transformation utilities for musical events

-- Extract pitch information from event sequence  
function permutation.extract_pitches(events)
    local pitches = {}
    for _, event in ipairs(events) do
        table.insert(pitches, event.pitch)
    end
    return pitches
end

-- Extract rhythm information from event sequence
function permutation.extract_rhythms(events)
    local rhythms = {}
    for _, event in ipairs(events) do
        -- Store duration (end - start time)
        table.insert(rhythms, event.e - event.s)
    end
    return rhythms
end

-- Apply permuted pitches back to event sequence
function permutation.apply_pitch_permutation(events, perm_pitches)
    if #events ~= #perm_pitches then
        error("Pitch permutation length must match event sequence length")
    end
    
    local result = {}
    for i, event in ipairs(events) do
        local new_event = {}
        for k, v in pairs(event) do
            new_event[k] = v  -- Copy all fields
        end
        new_event.pitch = perm_pitches[i]  -- Apply permuted pitch
        table.insert(result, new_event)
    end
    
    return result
end

-- Apply permuted rhythms back to event sequence
function permutation.apply_rhythm_permutation(events, perm_rhythms)
    if #events ~= #perm_rhythms then
        error("Rhythm permutation length must match event sequence length")
    end
    
    local result = {}
    local current_time = events[1] and events[1].s or 0.0
    
    for i, event in ipairs(events) do
        local new_event = {}
        for k, v in pairs(event) do
            new_event[k] = v  -- Copy all fields
        end
        
        -- Apply permuted duration while maintaining timeline
        new_event.s = current_time
        new_event.e = current_time + perm_rhythms[i]
        current_time = new_event.e
        
        table.insert(result, new_event)
    end
    
    return result
end

-- Processor Integration Helpers

-- Apply permutation by type with integrated RNG support
function permutation.apply_permutation_by_type(events, perm_type, perm_args, rng)
    if perm_type == "all" then
        return permutation.all_permutations(events, perm_args.max_count)
    elseif perm_type == "random" then
        return {permutation.random_permutation(events, rng)}
    elseif perm_type == "messiaen" or perm_type == "messiaen_primary" then
        return permutation.messiaen_primary(events)
    elseif perm_type == "messiaen_open" then
        return {permutation.messiaen_open_fan(events)}
    elseif perm_type == "messiaen_closed" then
        return {permutation.messiaen_closed_fan(events)}
    elseif perm_type == "messiaen_custom" and perm_args.order then
        return permutation.messiaen_custom_order(events, perm_args.order)
    elseif perm_type == "cycle" then
        -- For cycle mode, return messiaen primary by default
        -- Executor will handle cycling through results
        return permutation.messiaen_primary(events)
    else
        error("Unknown permutation type: " .. tostring(perm_type))
    end
end

-- Convenience function for getting single permutation result
function permutation.get_single_permutation(events, perm_type, perm_args, index, rng)
    local results = permutation.apply_permutation_by_type(events, perm_type, perm_args, rng)
    
    if #results == 1 then
        return results[1]
    else
        -- For multiple results (like all permutations or messiaen cycles)
        -- Return the specified index or first result
        index = index or 1
        return results[((index - 1) % #results) + 1]
    end
end

return permutation