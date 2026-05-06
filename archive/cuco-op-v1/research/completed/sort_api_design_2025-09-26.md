# Sort API Design

**Date**: 2025-09-26  
**Author**: AI Assistant  
**Project**: CUCO-OP DSL  
**Function Tier**: Tier 1  
**Status**: API Design Complete  

## DSL Syntax Design

### Core Sort Processors

Following established CUCO-OP processor patterns:

```lua
-- Basic sort processors
sequence = [d4 c4 f4 e4] !sort()         -- Ascending by default
sequence = [d4 c4 f4 e4] !sort(asc)      -- Explicit ascending
sequence = [d4 c4 f4 e4] !sort(desc)     -- Descending

-- Alternative explicit syntax
sequence = [d4 c4 f4 e4] !sort_asc()     -- Ascending
sequence = [d4 c4 f4 e4] !sort_desc()    -- Descending  

-- Type-specific sorting
sequence = [d4 c4 f4 e4] !sort(asc,type=pitch)     -- Sort pitches only
sequence = [q e h s]     !sort(asc,type=length)    -- Sort durations only
sequence = [c4@96 d4@60 e4@127] !sort(desc,type=velocity) -- Sort velocities only

-- Combined with other processors
melody = [d4 c4 f4 e4] !sort(asc) !arp(up,7)
ch1 = melody

// Complex sorting with type specification
prog = [CM7@ff Dm7@p G7@mf] !sort(desc,type=velocity) !vel(linear,60,120)
ch2 = prog
```

### Integration with Existing Syntax

```lua
~16 @c.major

// Basic pitch sorting
ascending = [b4 d4 g4 a4 e4 c4 f4] !sort(asc)
ch1 = ascending

// Duration-based sorting  
rhythm_sort = [h q e s] !sort(desc,type=length) 
ch2 = rhythm_sort

// Velocity sorting with dynamics
dynamics = [c4@pp d4@fff e4@p f4@mf] !sort(asc,type=velocity)
ch3 = dynamics
```

## Lua API Structure

### Core Module: `src/sort.lua`

```lua
local sort = {}

-- Core sorting algorithms
sort.ascending = function(sequence, options)
    -- Sort sequence in ascending order
    -- Returns: single sorted sequence
end

sort.descending = function(sequence, options)
    -- Sort sequence in descending order  
    -- Returns: single sorted sequence
end

-- Type-specific sorting utilities
sort.by_pitch = function(events, ascending)
    -- Sort events by pitch value while preserving other properties
    -- Returns: reordered events with sorted pitches
end

sort.by_duration = function(events, ascending)
    -- Sort events by duration while preserving other properties
    -- Returns: reordered events with sorted durations
end

sort.by_velocity = function(events, ascending)
    -- Sort events by velocity while preserving other properties
    -- Returns: reordered events with sorted velocities
end

-- Musical element comparison
sort.compare_pitches = function(pitch_a, pitch_b)
    -- Compare two pitch values (MIDI note numbers)
    -- Returns: -1, 0, 1 for less, equal, greater
end

sort.compare_durations = function(dur_a, dur_b)
    -- Compare two duration values (quarter note decimals)
    -- Returns: -1, 0, 1 for less, equal, greater  
end

sort.compare_velocities = function(vel_a, vel_b)
    -- Compare two velocity values (1-127)
    -- Returns: -1, 0, 1 for less, equal, greater
end

-- Generic comparison for musical elements
sort.compare_musical_elements = function(element_a, element_b)
    -- Smart comparison that handles different musical data types
    -- Returns: -1, 0, 1 for less, equal, greater
end

-- Extraction utilities for type-specific sorting
sort.extract_pitches = function(events)
    -- Extract pitch information from event sequence
    -- Returns: array of pitch values
end

sort.extract_durations = function(events)
    -- Extract duration information from event sequence
    -- Returns: array of duration values (in quarter notes)
end

sort.extract_velocities = function(events)
    -- Extract velocity information from event sequence
    -- Returns: array of velocity values
end

-- Reordering utilities
sort.reorder_by_indices = function(events, sorted_indices)
    -- Reorder events based on sorted indices
    -- Returns: reordered event sequence
end

return sort
```

### Integration Points

#### 1. Tokenizer Integration (Already Compatible)

Existing processor pattern in `src/tokenizer.lua` handles sort processors:
```lua
-- Pattern: "!([%w_]+)([(/][^)]*[)]?)" already matches:
-- !sort(), !sort(asc), !sort(desc), !sort_asc(), !sort_desc()
```

#### 2. Parser Integration (`src/parser.lua`)

```lua
-- Add processor parsing for sort types
function parse_processor_args(name, args_str)
    if name == "sort" then
        return parse_sort_args(args_str)
    elseif name == "sort_asc" then
        return {direction = "asc", type = "full"}
    elseif name == "sort_desc" then
        return {direction = "desc", type = "full"}
    end
    -- ... existing processors
end

function parse_sort_args(args_str)
    -- Parse: (), (asc), (desc), (asc,type=pitch), (desc,type=velocity)
    local direction = "asc"  -- default
    local target_type = "full"  -- default
    
    if args_str and args_str ~= "" then
        local clean_args = args_str:match('%((.-)%)')
        if clean_args then
            -- Parse direction
            if clean_args:match("desc") then
                direction = "desc"
            end
            
            -- Parse type parameter
            local type_match = clean_args:match("type=(%w+)")
            if type_match then
                target_type = type_match
            end
        end
    end
    
    return {
        direction = direction,
        type = target_type
    }
end
```

#### 3. Executor Integration (`src/executor.lua`)

```lua
-- Add sort processor handlers
local function handle_sort_processor(events, processor, context)
    local sort_mod = require("src.sort")
    
    local direction = processor.args.direction or "asc"
    local target_type = processor.args.type or "full"
    local ascending = (direction == "asc")
    
    if target_type == "pitch" then
        return sort_mod.by_pitch(events, ascending)
    elseif target_type == "length" or target_type == "duration" then
        return sort_mod.by_duration(events, ascending)
    elseif target_type == "velocity" then
        return sort_mod.by_velocity(events, ascending)
    else
        -- Full event sorting
        if ascending then
            return sort_mod.ascending(events)
        else
            return sort_mod.descending(events)
        end
    end
end

-- In evaluate_processor function:
elseif lname == 'sort' or lname == 'sort_asc' or lname == 'sort_desc' then
    local events = target.type and {target} or target
    return handle_sort_processor(events, node, ctx)
```

## Data Structures

### Sort Options

```lua
local sort_options = {
    direction = "asc" | "desc",          -- Sort direction
    type = "full" | "pitch" | "length" | "velocity", -- What to sort by
    section = nil | {0, 2, 4},           -- Future: section processing
    exclude = nil | {1, 3}               -- Future: exclude processing
}
```

### Musical Element Types

```lua
-- Pitch representation (MIDI note numbers)
local pitch_element = {
    type = "note",
    pitch = 60,    -- MIDI note number (C4 = 60)
    velocity = 96,
    articulation = nil
}

-- Duration representation (quarter notes)
local duration_info = {
    duration = 0.25,  -- Quarter note = 0.25 QN
    start_time = 0.0,
    end_time = 0.25
}

-- Velocity representation
local velocity_info = {
    velocity = 96,   -- MIDI velocity (1-127)
    dynamic_marking = "mf"  -- Optional symbolic representation
}
```

## Algorithm Specifications

### 1. Musical Element Comparison

```lua
function sort.compare_musical_elements(a, b)
    -- Handle different data types appropriately
    
    -- Both are numbers
    if type(a) == "number" and type(b) == "number" then
        return a < b and -1 or (a > b and 1 or 0)
    end
    
    -- Both are musical events (compare by pitch)
    if type(a) == "table" and type(b) == "table" and a.pitch and b.pitch then
        return a.pitch < b.pitch and -1 or (a.pitch > b.pitch and 1 or 0)
    end
    
    -- Both are pitch names (convert to MIDI numbers)
    if is_pitch_name(a) and is_pitch_name(b) then
        local midi_a = pitch_name_to_midi(a)
        local midi_b = pitch_name_to_midi(b)
        return midi_a < midi_b and -1 or (midi_a > midi_b and 1 or 0)
    end
    
    -- Default: string comparison
    local str_a, str_b = tostring(a), tostring(b)
    return str_a < str_b and -1 or (str_a > str_b and 1 or 0)
end
```

### 2. Type-Specific Sorting

```lua
function sort.by_pitch(events, ascending)
    -- Extract pitches with their original indices
    local pitch_index_pairs = {}
    for i, event in ipairs(events) do
        table.insert(pitch_index_pairs, {
            pitch = event.pitch or 60,  -- Default to C4 if no pitch
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
```

### 3. Performance Optimization

```lua
-- Efficient sorting with stable sort preservation
function sort.stable_sort(sequence, comparator)
    -- Add original indices to maintain stability
    local indexed_sequence = {}
    for i, element in ipairs(sequence) do
        table.insert(indexed_sequence, {element = element, original_index = i})
    end
    
    -- Sort with stability preservation
    table.sort(indexed_sequence, function(a, b)
        local comparison = comparator(a.element, b.element)
        if comparison == 0 then
            -- Equal elements: preserve original order
            return a.original_index < b.original_index
        else
            return comparison < 0
        end
    end)
    
    -- Extract sorted elements
    local result = {}
    for _, item in ipairs(indexed_sequence) do
        table.insert(result, item.element)
    end
    
    return result
end
```

## Error Handling

### Validation Rules

```lua
local validation = {
    -- Validate sortable sequence
    validate_sortable_sequence = function(sequence)
        if #sequence == 0 then
            error("Cannot sort empty sequence")
        end
        if #sequence > 10000 then
            error("Sequence too long for sorting (max 10000 elements)")
        end
    end,
    
    -- Validate type parameter
    validate_sort_type = function(sort_type)
        local valid_types = {"full", "pitch", "length", "duration", "velocity"}
        local is_valid = false
        for _, valid_type in ipairs(valid_types) do
            if sort_type == valid_type then
                is_valid = true
                break
            end
        end
        if not is_valid then
            error("Invalid sort type: " .. tostring(sort_type))
        end
    end,
    
    -- Validate mixed types don't break comparison
    validate_comparable_elements = function(sequence)
        -- Check that we can meaningfully compare elements
        local first_type = type(sequence[1])
        local has_mixed_uncomparable = false
        
        for i = 2, #sequence do
            if type(sequence[i]) ~= first_type and 
               not are_comparable(sequence[1], sequence[i]) then
                has_mixed_uncomparable = true
                break
            end
        end
        
        if has_mixed_uncomparable then
            error("Sequence contains uncomparable mixed types")
        end
    end
}
```

## Testing Strategy

### Unit Tests

```lua
-- Test deterministic sorting algorithms
local test_cases = {
    {
        input = {65, 60, 64, 62},  -- F4, C4, E4, D4 (MIDI numbers)
        expected_asc = {60, 62, 64, 65},  -- C4, D4, E4, F4
        expected_desc = {65, 64, 62, 60}  -- F4, E4, D4, C4
    },
    {
        input = {"b4", "d4", "g4", "a4", "e4", "c4", "f4"},
        expected_asc = {"c4", "d4", "e4", "f4", "g4", "a4", "b4"},
        expected_desc = {"b4", "a4", "g4", "f4", "e4", "d4", "c4"}
    }
}
```

### Integration Tests

```lua
-- Test with CUCO notation
local integration_tests = {
    {
        notation = "~16 [d4 c4 f4 e4] !sort(asc)",
        expected_events = {
            {pitch=60, s=0.0, e=0.25, vel=96, ch=1},  -- C4
            {pitch=62, s=0.25, e=0.5, vel=96, ch=1},  -- D4
            {pitch=64, s=0.5, e=0.75, vel=96, ch=1},  -- E4
            {pitch=65, s=0.75, e=1.0, vel=96, ch=1}   -- F4
        }
    }
}
```

## Implementation Status

**Phase 2 Complete**: API design and specifications  
**Next Phase**: Core sort module implementation  
**Target**: Full OSC-validated integration with CUCO-OP pipeline  

---

This API design provides comprehensive sorting functionality while maintaining consistency with existing CUCO-OP patterns and ensuring efficient performance for musical sequence organization.