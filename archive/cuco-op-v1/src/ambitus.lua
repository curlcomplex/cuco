-- ambitus.lua - Voice range validation and constraint enforcement for CUCO-OP
-- Implements core OpenMusic ambitus functions adapted for note-event architecture

local ambitus = {}

-- Instrument range database (MIDI note numbers)
-- Based on OpenMusic ambitus-instrument comprehensive database
local INSTRUMENT_RANGES = {
    -- Strings
    violin = {55, 103},      -- G3 to G7
    viola = {48, 91},        -- C3 to G6  
    cello = {36, 77},        -- C2 to F5
    double_bass = {28, 67},  -- E1 to G4
    
    -- Woodwinds
    flute = {60, 96},        -- C4 to C7
    piccolo = {74, 108},     -- D5 to C8
    oboe = {58, 91},         -- Bb3 to G6
    clarinet = {50, 91},     -- D3 to G6
    bassoon = {34, 75},      -- Bb1 to Eb5
    
    -- Brass
    trumpet = {52, 82},      -- E3 to Bb5
    french_horn = {34, 77},  -- Bb1 to F5
    trombone = {40, 72},     -- E2 to C5
    tuba = {28, 58},         -- E1 to Bb3
    
    -- Voices
    soprano = {60, 84},      -- C4 to C6
    alto = {55, 79},         -- G3 to G5
    tenor = {48, 72},        -- C3 to C5
    bass = {40, 64},         -- E2 to E4
    
    -- Piano
    piano = {21, 108},       -- A0 to C8
}

-- Get instrument range by name
-- @param instrument_name: string name of instrument
-- @return table: {low_pitch, high_pitch} in MIDI numbers, or nil if unknown
function ambitus.get_instrument_range(instrument_name)
    return INSTRUMENT_RANGES[instrument_name]
end

-- Validate that pitch is within range
-- @param pitch: MIDI note number
-- @param low_pitch: lower boundary (MIDI number)
-- @param high_pitch: upper boundary (MIDI number)
-- @return boolean: true if within range
function ambitus.validate_pitch(pitch, low_pitch, high_pitch)
    return pitch >= low_pitch and pitch <= high_pitch
end

-- Transpose pitch by octaves to fit within range
-- @param pitch: MIDI note number to constrain
-- @param low_pitch: lower boundary
-- @param high_pitch: upper boundary  
-- @return number: transposed pitch within range
function ambitus.transpose_to_range(pitch, low_pitch, high_pitch)
    local result = pitch
    
    -- Move down octaves if too high
    while result > high_pitch do
        result = result - 12
    end
    
    -- Move up octaves if too low
    while result < low_pitch do
        result = result + 12
    end
    
    return result
end

-- Invert pitch around range boundaries when out-of-range
-- @param pitch: MIDI note number
-- @param low_pitch: lower boundary
-- @param high_pitch: upper boundary
-- @return number: inverted pitch or original if in range
function ambitus.invert_around_range(pitch, low_pitch, high_pitch)
    if pitch > high_pitch then
        -- Reflect around high boundary
        return high_pitch - (pitch - high_pitch)
    elseif pitch < low_pitch then
        -- Reflect around low boundary
        return low_pitch + (low_pitch - pitch)
    else
        return pitch  -- within range
    end
end

-- Scale pitch field proportionally to fit within range
-- @param events: array of note events
-- @param low_pitch: target low boundary
-- @param high_pitch: target high boundary
-- @return array: events with scaled pitches
function ambitus.field_scale(events, low_pitch, high_pitch)
    if #events == 0 then return events end
    
    -- Find current range
    local min_pitch = math.huge
    local max_pitch = -math.huge
    
    for _, event in ipairs(events) do
        if event.pitch then
            min_pitch = math.min(min_pitch, event.pitch)
            max_pitch = math.max(max_pitch, event.pitch)
        end
    end
    
    -- Handle single pitch or no range
    if min_pitch == max_pitch then
        local result = {}
        for _, event in ipairs(events) do
            local new_event = {}
            for k, v in pairs(event) do
                new_event[k] = v
            end
            if event.pitch then
                new_event.pitch = low_pitch + (high_pitch - low_pitch) / 2  -- Center of target range
            end
            table.insert(result, new_event)
        end
        return result
    end
    
    -- Scale proportionally
    local current_range = max_pitch - min_pitch
    local target_range = high_pitch - low_pitch
    local scale_factor = target_range / current_range
    
    local result = {}
    for _, event in ipairs(events) do
        local new_event = {}
        for k, v in pairs(event) do
            new_event[k] = v
        end
        if event.pitch then
            local normalized = event.pitch - min_pitch  -- 0 to current_range
            local scaled = normalized * scale_factor    -- 0 to target_range
            new_event.pitch = low_pitch + scaled
        end
        table.insert(result, new_event)
    end
    
    return result
end

-- Force pitches into specific octave range
-- @param events: array of note events
-- @param base_pitch: MIDI number of base octave (e.g., 60 for C4)
-- @param num_octaves: number of octaves to span
-- @return array: events with pitches forced into octave range
function ambitus.force_octaves(events, base_pitch, num_octaves)
    local result = {}
    local octave_span = num_octaves * 12
    local high_pitch = base_pitch + octave_span - 1
    
    for _, event in ipairs(events) do
        local new_event = {}
        for k, v in pairs(event) do
            new_event[k] = v
        end
        if event.pitch then
            -- Get pitch class (0-11)
            local pitch_class = event.pitch % 12
            -- Find best octave within range
            local target_pitch = base_pitch + pitch_class
            if target_pitch < base_pitch then
                target_pitch = target_pitch + 12
            end
            -- Ensure within octave span
            while target_pitch > high_pitch do
                target_pitch = target_pitch - 12
            end
            new_event.pitch = target_pitch
        end
        table.insert(result, new_event)
    end
    
    return result
end

-- Apply range constraint to events (core ambitus function)
-- @param events: array of note events or single event
-- @param low_pitch: lower boundary (MIDI number)
-- @param high_pitch: upper boundary (MIDI number)
-- @param mode: "transpose" (default), "invert", or "filter"
-- @return array: constrained events
function ambitus.apply_range_constraint(events, low_pitch, high_pitch, mode)
    mode = mode or "transpose"
    
    -- Handle single event vs array of events
    local is_single = (events.type ~= nil)
    local event_list = is_single and {events} or events
    local result = {}
    
    for _, event in ipairs(event_list) do
        local new_event = {}
        for k, v in pairs(event) do
            new_event[k] = v
        end
        
        -- Handle note events
        if event.type == "note" and event.pitch then
            if mode == "transpose" then
                new_event.pitch = ambitus.transpose_to_range(event.pitch, low_pitch, high_pitch)
            elseif mode == "invert" then
                new_event.pitch = ambitus.invert_around_range(event.pitch, low_pitch, high_pitch)
            elseif mode == "filter" then
                if not ambitus.validate_pitch(event.pitch, low_pitch, high_pitch) then
                    -- Convert to rest
                    new_event.type = "rest"
                    new_event.pitch = nil
                end
            end
        -- Handle chord events
        elseif event.type == "chord" and event.notes then
            for _, note in ipairs(new_event.notes) do
                if note.pitch then
                    if mode == "transpose" then
                        note.pitch = ambitus.transpose_to_range(note.pitch, low_pitch, high_pitch)
                    elseif mode == "invert" then
                        note.pitch = ambitus.invert_around_range(note.pitch, low_pitch, high_pitch)
                    elseif mode == "filter" then
                        if not ambitus.validate_pitch(note.pitch, low_pitch, high_pitch) then
                            -- For chords, we could remove the note or convert whole chord to rest
                            -- For now, just transpose out-of-range notes in chords
                            note.pitch = ambitus.transpose_to_range(note.pitch, low_pitch, high_pitch)
                        end
                    end
                end
            end
        end
        
        table.insert(result, new_event)
    end
    
    return is_single and result[1] or result
end

-- Apply instrument range constraint
-- @param events: array of note events
-- @param instrument_name: string name of instrument
-- @param mode: constraint mode (transpose/invert/filter)
-- @return array: constrained events, or nil if unknown instrument
function ambitus.apply_instrument_constraint(events, instrument_name, mode)
    local range = ambitus.get_instrument_range(instrument_name)
    if not range then
        return nil, "Unknown instrument: " .. tostring(instrument_name)
    end
    
    return ambitus.apply_range_constraint(events, range[1], range[2], mode)
end

-- Analyze actual ambitus of event sequence
-- @param events: array of note events
-- @return table: {lowest, highest, span} or nil if no pitches
function ambitus.analyze_sequence(events)
    local min_pitch = math.huge
    local max_pitch = -math.huge
    local has_pitches = false
    
    for _, event in ipairs(events) do
        if event.pitch then
            min_pitch = math.min(min_pitch, event.pitch)
            max_pitch = math.max(max_pitch, event.pitch)
            has_pitches = true
        end
    end
    
    if not has_pitches then
        return nil
    end
    
    return {
        lowest = min_pitch,
        highest = max_pitch,
        span = max_pitch - min_pitch
    }
end

return ambitus