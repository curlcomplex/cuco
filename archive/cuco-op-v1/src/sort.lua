-- CUCO-OP Sort System Functions
-- Implements sort-based sequence transformations including
-- ascending/descending sorts, type-specific sorting, and musical element comparison

local sort = {}

-- Utility Functions
local function copy_table(t)
    local result = {}
    for i, v in ipairs(t) do
        if type(v) == "table" then
            -- Deep copy for musical events
            local copy_v = {}
            for k, val in pairs(v) do
                copy_v[k] = val
            end
            result[i] = copy_v
        else
            result[i] = v
        end
    end
    return result
end

-- Validation Functions
local function validate_sortable_sequence(sequence)
    if #sequence == 0 then
        error("Cannot sort empty sequence")
    end
    if #sequence > 10000 then
        error("Sequence too long for sorting (max 10000 elements)")
    end
end

local function validate_sort_type(sort_type)
    local valid_types = {"full", "pitch", "length", "duration", "velocity"}
    for _, valid_type in ipairs(valid_types) do
        if sort_type == valid_type then
            return true
        end
    end
    error("Invalid sort type: " .. tostring(sort_type))
end

-- Musical Element Comparison Functions

-- Check if element is a musical event
local function is_musical_event(element)
    return type(element) == "table" and (element.pitch or element.type)
end

-- Check if element is a pitch name string (c4, d#3, etc.)
local function is_pitch_name(element)
    if type(element) ~= "string" then return false end
    return element:match("^[a-g][#b]?%-?%d*$") ~= nil
end

-- Convert pitch name to MIDI number (simplified)
local function pitch_name_to_midi(pitch_name)
    local note_offsets = {c=0, d=2, e=4, f=5, g=7, a=9, b=11}
    
    local note, accidental, flat, octave = pitch_name:match("^([a-g])([#b]?)([%-]?)(%d*)$")
    if not note then return 60 end  -- Default to C4
    
    octave = tonumber(octave) or 4
    local base = note_offsets[note:lower()] or 0
    
    -- Handle flat notation (c-3 = c3 with flat)
    if flat == "-" then
        accidental = "b"
    end
    
    -- Apply accidentals
    if accidental == "#" then
        base = base + 1
    elseif accidental == "b" then
        base = base - 1
    end
    
    return base + (octave * 12) + 12 -- +12 for MIDI octave offset
end

-- Core comparison function for musical elements
function sort.compare_musical_elements(a, b)
    -- Handle identical elements
    if a == b then return 0 end
    
    -- Both are numbers - direct comparison
    if type(a) == "number" and type(b) == "number" then
        return a < b and -1 or (a > b and 1 or 0)
    end
    
    -- Both are musical events - compare by pitch
    if is_musical_event(a) and is_musical_event(b) then
        local pitch_a = a.pitch or 60
        local pitch_b = b.pitch or 60
        return pitch_a < pitch_b and -1 or (pitch_a > pitch_b and 1 or 0)
    end
    
    -- Both are pitch names - convert to MIDI numbers
    if is_pitch_name(a) and is_pitch_name(b) then
        local midi_a = pitch_name_to_midi(a)
        local midi_b = pitch_name_to_midi(b)
        return midi_a < midi_b and -1 or (midi_a > midi_b and 1 or 0)
    end
    
    -- Default: string comparison
    local str_a, str_b = tostring(a), tostring(b)
    return str_a < str_b and -1 or (str_a > str_b and 1 or 0)
end

-- Specific comparison functions
function sort.compare_pitches(pitch_a, pitch_b)
    if type(pitch_a) == "number" and type(pitch_b) == "number" then
        return pitch_a < pitch_b and -1 or (pitch_a > pitch_b and 1 or 0)
    end
    return sort.compare_musical_elements(pitch_a, pitch_b)
end

function sort.compare_durations(dur_a, dur_b)
    -- Convert durations to decimal quarter notes for comparison
    local a_val = type(dur_a) == "number" and dur_a or 0.25
    local b_val = type(dur_b) == "number" and dur_b or 0.25
    return a_val < b_val and -1 or (a_val > b_val and 1 or 0)
end

function sort.compare_velocities(vel_a, vel_b)
    local a_val = type(vel_a) == "number" and vel_a or 64
    local b_val = type(vel_b) == "number" and vel_b or 64
    return a_val < b_val and -1 or (a_val > b_val and 1 or 0)
end

-- Core Sorting Algorithms

-- Sort sequence in ascending order
function sort.ascending(sequence, options)
    validate_sortable_sequence(sequence)
    
    local result = copy_table(sequence)
    table.sort(result, function(a, b)
        return sort.compare_musical_elements(a, b) < 0
    end)
    
    return result
end

-- Sort sequence in descending order  
function sort.descending(sequence, options)
    validate_sortable_sequence(sequence)
    
    local result = copy_table(sequence)
    table.sort(result, function(a, b)
        return sort.compare_musical_elements(a, b) > 0
    end)
    
    return result
end

-- Extraction utilities for type-specific sorting

function sort.extract_pitches(events)
    local pitches = {}
    for _, event in ipairs(events) do
        if is_musical_event(event) then
            table.insert(pitches, event.pitch or 60)
        else
            table.insert(pitches, 60) -- Default pitch
        end
    end
    return pitches
end

function sort.extract_durations(events)
    local durations = {}
    for _, event in ipairs(events) do
        if is_musical_event(event) and event.e and event.s then
            -- Calculate duration from timing
            table.insert(durations, event.e - event.s)
        else
            table.insert(durations, 0.25) -- Default quarter note
        end
    end
    return durations
end

function sort.extract_velocities(events)
    local velocities = {}
    for _, event in ipairs(events) do
        if is_musical_event(event) then
            table.insert(velocities, event.velocity or 64)
        else
            table.insert(velocities, 64) -- Default velocity
        end
    end
    return velocities
end

-- Reordering utilities

function sort.reorder_by_indices(events, sorted_indices)
    local result = {}
    for _, index in ipairs(sorted_indices) do
        if events[index] then
            table.insert(result, events[index])
        end
    end
    return result
end

-- Get sorted indices for a value array
local function get_sorted_indices(values, ascending)
    local indexed_values = {}
    for i, value in ipairs(values) do
        table.insert(indexed_values, {value = value, index = i})
    end
    
    table.sort(indexed_values, function(a, b)
        local comparison = sort.compare_musical_elements(a.value, b.value)
        if ascending then
            return comparison < 0
        else
            return comparison > 0
        end
    end)
    
    local indices = {}
    for _, item in ipairs(indexed_values) do
        table.insert(indices, item.index)
    end
    
    return indices
end

-- Type-Specific Sorting Functions

function sort.by_pitch(events, ascending)
    validate_sortable_sequence(events)
    
    -- Extract pitches with their original indices
    local pitch_index_pairs = {}
    for i, event in ipairs(events) do
        local pitch = 60  -- Default to C4
        if is_musical_event(event) then
            pitch = event.pitch or 60
        elseif type(event) == "number" then
            pitch = event
        elseif is_pitch_name(event) then
            pitch = pitch_name_to_midi(event)
        end
        
        table.insert(pitch_index_pairs, {
            pitch = pitch,
            index = i
        })
    end
    
    -- Sort by pitch
    table.sort(pitch_index_pairs, function(a, b)
        if ascending then
            return a.pitch < b.pitch
        else
            return a.pitch > b.pitch
        end
    end)
    
    -- Reorder events based on sorted pitch indices
    local result = {}
    for _, pair in ipairs(pitch_index_pairs) do
        table.insert(result, events[pair.index])
    end
    
    return result
end

function sort.by_duration(events, ascending)
    validate_sortable_sequence(events)
    
    local duration_index_pairs = {}
    for i, event in ipairs(events) do
        local duration = 0.25  -- Default quarter note
        if is_musical_event(event) and event.e and event.s then
            duration = event.e - event.s
        elseif type(event) == "number" then
            duration = event
        end
        
        table.insert(duration_index_pairs, {
            duration = duration,
            index = i
        })
    end
    
    -- Sort by duration
    table.sort(duration_index_pairs, function(a, b)
        if ascending then
            return a.duration < b.duration
        else
            return a.duration > b.duration
        end
    end)
    
    -- Reorder events based on sorted duration indices
    local result = {}
    for _, pair in ipairs(duration_index_pairs) do
        table.insert(result, events[pair.index])
    end
    
    return result
end

function sort.by_velocity(events, ascending)
    validate_sortable_sequence(events)
    
    local velocity_index_pairs = {}
    for i, event in ipairs(events) do
        local velocity = 64  -- Default velocity
        if is_musical_event(event) then
            velocity = event.velocity or 64
        elseif type(event) == "number" then
            velocity = event
        end
        
        table.insert(velocity_index_pairs, {
            velocity = velocity,
            index = i
        })
    end
    
    -- Sort by velocity
    table.sort(velocity_index_pairs, function(a, b)
        if ascending then
            return a.velocity < b.velocity
        else
            return a.velocity > b.velocity
        end
    end)
    
    -- Reorder events based on sorted velocity indices
    local result = {}
    for _, pair in ipairs(velocity_index_pairs) do
        table.insert(result, events[pair.index])
    end
    
    return result
end

-- Processor Integration Helper

-- Apply sort by type with integrated options
function sort.apply_sort_by_type(events, sort_type, ascending)
    validate_sort_type(sort_type)
    
    if sort_type == "pitch" then
        return sort.by_pitch(events, ascending)
    elseif sort_type == "length" or sort_type == "duration" then
        return sort.by_duration(events, ascending)
    elseif sort_type == "velocity" then
        return sort.by_velocity(events, ascending)
    else -- "full"
        if ascending then
            return sort.ascending(events)
        else
            return sort.descending(events)
        end
    end
end

-- Convenience function for processor integration
function sort.process_sort(events, direction, sort_type)
    local ascending = (direction ~= "desc")
    return sort.apply_sort_by_type(events, sort_type or "full", ascending)
end

return sort