# Permutations API Design

**Date**: 2025-09-26  
**Author**: AI Assistant  
**Project**: CUCO-OP DSL  
**Function Tier**: Tier 1  
**Status**: API Design Complete  

## DSL Syntax Design

### Core Permutation Processors

Following established CUCO-OP processor patterns:

```lua
-- Basic permutation processor
sequence = [c4 d4 e4 f4] !perm()         -- All permutations
sequence = [c4 d4 e4 f4] !perm(all)      -- Explicit all permutations  
sequence = [c4 d4 e4 f4] !perm(random)   -- Random permutation
sequence = [c4 d4 e4 f4] !perm(cycle)    -- Cycle through permutations

-- Messiaen permutation types  
sequence = [c4 d4 e4 f4] !perm(messiaen)           -- Primary permutation
sequence = [c4 d4 e4 f4] !perm(messiaen,primary)   -- Explicit primary
sequence = [c4 d4 e4 f4] !perm(messiaen,open)      -- Open fan (even length)
sequence = [c4 d4 e4 f4] !perm(messiaen,closed)    -- Closed fan (even length)
sequence = [c4 d4 e4 f4] !perm(messiaen,0,2,1,3)   -- Custom order indices

-- Classical transformations
sequence = [c4 d4 e4 f4] !retro()        -- Retrograde
sequence = [c4 d4 e4 f4] !rotate(2)      -- Rotate right 2 positions
sequence = [c4 d4 e4 f4] !rotate(-1)     -- Rotate left 1 position
sequence = [c4 d4 e4 f4] !rotate(left)   -- Rotate left 1 position
sequence = [c4 d4 e4 f4] !rotate(right)  -- Rotate right 1 position

-- Type-specific transformations
sequence = [c4 d4 e4 f4] !perm(all,type=pitch)     -- Permute pitches only
sequence = [q e q s]     !perm(all,type=rhythm)    -- Permute rhythms only  
sequence = [c4 d4 e4 f4] !retro(type=pitch)        -- Retrograde pitches only
sequence = [q e q s]     !rotate(2,type=rhythm)    -- Rotate rhythms only
```

### Integration with Existing Syntax

```lua
~16 @c.major
// Combined with other processors
melody = [c4 d4 e4 f4] !perm(messiaen) !arp(up,7)
ch1 = melody

// With velocity and envelope processing
prog = [CM7 Dm7 G7] !perm(cycle) !vel(linear,60,120) !env(adsr,0.8,0.2)
ch2 = prog

// Type-specific with context
bass = [c2 d2 e2 f2]*4 !retro(type=pitch) @c.major
ch3 = bass
```

## Lua API Structure

### Core Module: `src/permutation.lua`

```lua
local permutation = {}

-- Core permutation algorithms
permutation.all_permutations = function(sequence, max_count)
    -- Generate all permutations up to max_count limit
    -- Returns: array of permuted sequences
end

permutation.random_permutation = function(sequence, rng)
    -- Generate single random permutation
    -- Uses provided RNG for reproducibility
    -- Returns: single permuted sequence
end

-- Messiaen permutation techniques
permutation.messiaen_primary = function(sequence)
    -- Primary permutation technique
    -- Returns: array of permuted sequences until cycle complete
end

permutation.messiaen_open_fan = function(sequence)
    -- Open fan permutation (requires even length)
    -- Returns: single permuted sequence
end

permutation.messiaen_closed_fan = function(sequence)
    -- Closed fan permutation (requires even length)  
    -- Returns: single permuted sequence
end

permutation.messiaen_custom_order = function(sequence, order)
    -- Custom order permutation with user-defined indices
    -- Returns: array of permuted sequences until cycle complete
end

-- Classical transformations
permutation.retrograde = function(sequence)
    -- Simple retrograde/reverse
    -- Returns: single reversed sequence
end

permutation.rotate = function(sequence, amount)
    -- Rotate sequence by amount (positive=right, negative=left)
    -- Returns: single rotated sequence  
end

-- Type-specific transformation utilities
permutation.extract_pitches = function(events)
    -- Extract pitch information from event sequence
end

permutation.extract_rhythms = function(events)
    -- Extract rhythm information from event sequence  
end

permutation.apply_pitch_permutation = function(events, perm_pitches)
    -- Apply permuted pitches back to event sequence
end

permutation.apply_rhythm_permutation = function(events, perm_rhythms)
    -- Apply permuted rhythms back to event sequence
end

return permutation
```

### Integration Points

#### 1. Tokenizer Integration (`src/tokenizer.lua`)

```lua
-- Add permutation processor patterns
{pattern = "!perm%(([^)]*)%)", token_type = "PROCESSOR"},
{pattern = "!retro%(([^)]*)%)", token_type = "PROCESSOR"}, 
{pattern = "!rotate%(([^)]*)%)", token_type = "PROCESSOR"},
```

#### 2. Parser Integration (`src/parser.lua`)

```lua
-- Add processor parsing for permutation types
function parse_processor_args(name, args_str)
    if name == "perm" then
        return parse_perm_args(args_str)
    elseif name == "retro" then
        return parse_retro_args(args_str)
    elseif name == "rotate" then
        return parse_rotate_args(args_str)
    end
    -- ... existing processors
end

function parse_perm_args(args_str)
    -- Parse: (), (all), (random), (messiaen), (messiaen,primary), etc.
    -- Parse: (messiaen,0,2,1,3) for custom order
    -- Parse: (all,type=pitch) for type-specific
end
```

#### 3. Executor Integration (`src/executor.lua`)

```lua
-- Add permutation processor handlers
local function handle_perm_processor(events, processor, context)
    local perm = require("src.permutation")
    
    local perm_type = processor.args.type or "all"
    local target_type = processor.args.target_type or "full"
    
    if target_type == "pitch" then
        local pitches = perm.extract_pitches(events)
        local perm_pitches = apply_permutation_by_type(pitches, perm_type, perm)
        return perm.apply_pitch_permutation(events, perm_pitches)
    elseif target_type == "rhythm" then
        local rhythms = perm.extract_rhythms(events)
        local perm_rhythms = apply_permutation_by_type(rhythms, perm_type, perm)
        return perm.apply_rhythm_permutation(events, perm_rhythms)
    else
        -- Full event permutation
        return apply_permutation_by_type(events, perm_type, perm)
    end
end

local function handle_retro_processor(events, processor, context)
    local perm = require("src.permutation")
    local target_type = processor.args.target_type or "full"
    
    if target_type == "pitch" then
        local pitches = perm.extract_pitches(events)
        local retro_pitches = perm.retrograde(pitches)
        return perm.apply_pitch_permutation(events, retro_pitches)
    elseif target_type == "rhythm" then
        local rhythms = perm.extract_rhythms(events)
        local retro_rhythms = perm.retrograde(rhythms)
        return perm.apply_rhythm_permutation(events, retro_rhythms)
    else
        return perm.retrograde(events)
    end
end

local function handle_rotate_processor(events, processor, context)
    local perm = require("src.permutation")
    local amount = processor.args.amount or 1
    local target_type = processor.args.target_type or "full"
    
    if target_type == "pitch" then
        local pitches = perm.extract_pitches(events)
        local rot_pitches = perm.rotate(pitches, amount)
        return perm.apply_pitch_permutation(events, rot_pitches)
    elseif target_type == "rhythm" then
        local rhythms = perm.extract_rhythms(events)
        local rot_rhythms = perm.rotate(rhythms, amount)
        return perm.apply_rhythm_permutation(events, rot_rhythms)
    else
        return perm.rotate(events, amount)
    end
end
```

## Data Structures

### Permutation State

```lua
-- For processors that cycle through permutations
local permutation_state = {
    sequence_id = hash(original_sequence),
    permutation_type = "messiaen_primary",
    current_index = 0,
    permutation_cache = {},
    cycle_complete = false
}
```

### Event Transformation

```lua
-- Event structure preservation during permutation
local event = {
    pitch = 60,    -- MIDI note number
    s = 0.0,       -- Start time (quarter notes)
    e = 0.25,      -- End time (quarter notes)  
    vel = 64,      -- Velocity (1-127)
    ch = 1         -- MIDI channel (1-16)
}

-- Permutation preserves timing structure while transforming content
```

## Algorithm Specifications

### 1. All Permutations with Limits

```lua
-- Practical limits to prevent memory explosion
local MAX_PERMUTATIONS = 40320  -- 8! = 40,320 (reasonable limit)
local MAX_SEQUENCE_LENGTH = 8   -- Maximum for all permutations

function all_permutations_limited(sequence, max_count)
    if #sequence > MAX_SEQUENCE_LENGTH then
        error("Sequence too long for all permutations (max 8 elements)")
    end
    
    local count = factorial(#sequence)
    if count > MAX_PERMUTATIONS and not max_count then
        max_count = MAX_PERMUTATIONS
    end
    
    return generate_permutations_heaps(sequence, max_count)
end
```

### 2. Messiaen Primary Permutation

```lua
-- Based on Messiaen's systematic transformation
function messiaen_transform_index(i, n)
    -- Messiaen's specific index transformation pattern
    -- This creates systematic non-repeating cycles
    if i == 1 then
        return n
    elseif i == n then  
        return 1
    else
        return ((i - 1) % (n - 1)) + 1
    end
end
```

### 3. Performance Optimization

```lua
-- Lazy generation for large permutation sets
local PermutationIterator = {
    sequence = nil,
    current_perm = nil,
    state = {}
}

function PermutationIterator:new(sequence, type)
    local iter = {
        sequence = sequence,
        type = type,
        state = initialize_state(sequence, type)
    }
    setmetatable(iter, self)
    self.__index = self
    return iter
end

function PermutationIterator:next()
    return generate_next_permutation(self.state)
end
```

## Error Handling

### Validation Rules

```lua
local validation = {
    -- Fan permutations require even length
    validate_fan_permutation = function(sequence, fan_type)
        if #sequence % 2 ~= 0 then
            error(string.format("%s fan permutation requires even-length sequence (got %d)", 
                  fan_type, #sequence))
        end
    end,
    
    -- Custom order validation
    validate_custom_order = function(sequence, order)
        if #order ~= #sequence then
            error("Custom order length must match sequence length")
        end
        
        -- Check for valid indices (0-based)
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
    end,
    
    -- Sequence length limits
    validate_sequence_length = function(sequence, operation)
        if #sequence == 0 then
            error("Cannot " .. operation .. " empty sequence")
        end
        if #sequence > 20 then
            error(operation .. " not practical for sequences longer than 20 elements")
        end
    end
}
```

## Testing Strategy

### Unit Tests

```lua
-- Test deterministic permutation algorithms
local test_cases = {
    {
        input = {60, 62, 64},  -- C4, D4, E4
        expected_retro = {64, 62, 60},
        expected_rotate_1 = {64, 60, 62},
        expected_messiaen_primary = {{60, 62, 64}, {64, 60, 62}, {62, 64, 60}}
    }
}
```

### Integration Tests

```lua
-- Test with CUCO notation
local integration_tests = {
    {
        notation = "~16 [c4 d4 e4 f4] !retro()",
        expected_events = {
            {pitch=65, s=0.0, e=0.25, vel=64, ch=1},  -- F4
            {pitch=64, s=0.25, e=0.5, vel=64, ch=1},  -- E4  
            {pitch=62, s=0.5, e=0.75, vel=64, ch=1},  -- D4
            {pitch=60, s=0.75, e=1.0, vel=64, ch=1}   -- C4
        }
    }
}
```

## Implementation Status

**Phase 1 Complete**: Research and API design  
**Next Phase**: Core permutation module implementation  
**Target**: Full OSC-validated integration with existing CUCO-OP pipeline  

---

This API design provides comprehensive permutation functionality while maintaining consistency with existing CUCO-OP patterns and ensuring practical performance limitations.