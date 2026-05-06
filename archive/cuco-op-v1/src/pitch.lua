-- CUCO-OP Pitch System Functions
-- Implements chord literals, voicing algorithms, pitch transformations
-- API: pitch.* functions for direct use and DSL integration

local pitch = {}

-- Chord quality definitions (intervals from root in semitones)
local CHORD_QUALITIES = {
    -- Triads
    ["maj"] = {0, 4, 7},           -- Major
    [""] = {0, 4, 7},              -- Major (default)
    ["min"] = {0, 3, 7},           -- Minor
    ["dim"] = {0, 3, 6},           -- Diminished
    ["aug"] = {0, 4, 8},           -- Augmented
    ["sus2"] = {0, 2, 7},          -- Suspended 2nd
    ["sus4"] = {0, 5, 7},          -- Suspended 4th

    -- Seventh chords
    ["maj7"] = {0, 4, 7, 11},      -- Major 7th
    ["7"] = {0, 4, 7, 10},         -- Dominant 7th
    ["min7"] = {0, 3, 7, 10},      -- Minor 7th
    ["dim7"] = {0, 3, 6, 9},       -- Diminished 7th (fully diminished)
    ["m7b5"] = {0, 3, 6, 10},      -- Half-diminished 7th
    ["maj7#11"] = {0, 4, 7, 11, 18}, -- Major 7#11
    ["minmaj7"] = {0, 3, 7, 11},   -- Minor major 7th

    -- Extended chords
    ["9"] = {0, 4, 7, 10, 14},     -- Dominant 9th
    ["maj9"] = {0, 4, 7, 11, 14},  -- Major 9th
    ["min9"] = {0, 3, 7, 10, 14},  -- Minor 9th
    ["11"] = {0, 4, 7, 10, 14, 17}, -- Dominant 11th
    ["13"] = {0, 4, 7, 10, 14, 21}, -- Dominant 13th

    -- Altered chords
    ["7alt"] = {0, 4, 7, 10, 13, 15, 17, 21}, -- Altered dominant
    ["7b9"] = {0, 4, 7, 10, 13},   -- Dominant 7b9
    ["7#9"] = {0, 4, 7, 10, 15},   -- Dominant 7#9
    ["7b5"] = {0, 4, 6, 10},       -- Dominant 7b5
    ["7#5"] = {0, 4, 8, 10},       -- Dominant 7#5
}

-- Note name to semitone offset from C
local NOTE_TO_SEMITONE = {
    ["c"] = 0, ["c#"] = 1, ["db"] = 1, ["d"] = 2, ["d#"] = 3, ["eb"] = 3,
    ["e"] = 4, ["f"] = 5, ["f#"] = 6, ["gb"] = 6, ["g"] = 7, ["g#"] = 8,
    ["ab"] = 8, ["a"] = 9, ["a#"] = 10, ["bb"] = 10, ["b"] = 11
}

-- Voicing algorithms
local VOICING_TYPES = {
    CLOSE = "close",       -- Stack in closest position
    OPEN = "open",         -- Spread voices
    DROP2 = "drop2",       -- Drop 2nd highest voice an octave
    DROP3 = "drop3",       -- Drop 3rd highest voice an octave
    FOURTHS = "fourths",   -- Stack in 4ths instead of 3rds
    QUARTAL = "quartal"    -- Quartal harmony
}

-- Parse chord symbol (e.g., "CM7", "F#m7", "B°7/D")
function pitch.parse_chord_symbol(symbol)
    if not symbol or symbol == "" or type(symbol) ~= "string" then
        return nil
    end

    -- Normalize spacing but preserve case for parsing
    symbol = symbol:gsub("%s+", "")

    -- Parse pattern: Root+Quality/Bass or Root+Quality
    local root_part, quality_part, bass_part = symbol:match("^([A-G][#b]?)([^/]*)/([A-G][#b]?)$")

    if not root_part then
        -- No bass note specified
        root_part, quality_part = symbol:match("^([A-G][#b]?)(.*)$")
        if not root_part then
            error("Invalid chord symbol: " .. symbol)
        end
    end

    -- Convert root to lowercase for lookup
    local root_lower = root_part:lower()

    -- Default quality is major if empty
    if quality_part == "" or quality_part == "M" then
        quality_part = "maj"
    elseif quality_part == "m" then
        quality_part = "min"
    elseif quality_part == "°" or quality_part == "dim" then
        quality_part = "dim"
    elseif quality_part == "°7" or quality_part == "dim7" then
        quality_part = "dim7"
    elseif quality_part == "ø" or quality_part == "ø7" then
        quality_part = "m7b5"
    elseif quality_part == "M7" then
        quality_part = "maj7"
    elseif quality_part == "m7" then
        quality_part = "min7"
    -- Add more mappings as needed
    end

    return {
        root = root_lower,
        quality = quality_part,
        bass = bass_part and bass_part:lower()  -- nil if no bass note
    }
end

-- Get chord intervals for a quality
function pitch.get_chord_intervals(quality)
    local intervals = CHORD_QUALITIES[quality]
    if not intervals then
        error("Unknown chord quality: " .. quality)
    end
    return intervals
end

-- Convert note name to MIDI number (with octave)
function pitch.note_to_midi(note_name, octave)
    octave = octave or 4  -- Default to octave 4

    -- Handle flat notation (eb -> d#)
    local normalized = note_name:lower()

    local semitone = NOTE_TO_SEMITONE[normalized]
    if not semitone then
        error("Invalid note name: " .. note_name)
    end

    return (octave + 1) * 12 + semitone
end

-- Convert MIDI number to note name
function pitch.midi_to_note(midi_num)
    local octave = math.floor(midi_num / 12) - 1
    local semitone = midi_num % 12

    local note_names = {"c", "c#", "d", "d#", "e", "f", "f#", "g", "g#", "a", "a#", "b"}
    local note_name = note_names[semitone + 1]

    return note_name, octave
end

-- Generate chord notes from chord symbol and root octave
function pitch.chord_to_notes(symbol, root_octave, voicing_type)
    root_octave = root_octave or 4
    voicing_type = voicing_type or VOICING_TYPES.CLOSE

    local parsed = pitch.parse_chord_symbol(symbol)
    if not parsed then
        error("Failed to parse chord symbol: " .. tostring(symbol))
    end

    local intervals = pitch.get_chord_intervals(parsed.quality)

    -- Get root MIDI number
    local root_midi = pitch.note_to_midi(parsed.root, root_octave)

    -- Generate basic chord notes
    local notes = {}
    for _, interval in ipairs(intervals) do
        table.insert(notes, root_midi + interval)
    end

    -- Apply voicing algorithm
    notes = pitch.apply_voicing(notes, voicing_type)

    -- Handle bass note if specified
    if parsed.bass and parsed.bass ~= "" then
        local bass_midi = pitch.note_to_midi(parsed.bass, root_octave - 1)
        table.insert(notes, 1, bass_midi)  -- Insert at beginning
    end

    return notes
end

-- Apply voicing algorithm to chord notes
function pitch.apply_voicing(notes, voicing_type)
    if not notes or #notes == 0 then
        return notes
    end

    -- Make a copy to avoid modifying original
    local voiced_notes = {}
    for _, note in ipairs(notes) do
        table.insert(voiced_notes, note)
    end

    if voicing_type == VOICING_TYPES.CLOSE then
        -- Already in close position, no change needed
        return voiced_notes

    elseif voicing_type == VOICING_TYPES.OPEN then
        -- Spread voices across wider range
        for i = 2, #voiced_notes do
            if i % 2 == 0 then
                voiced_notes[i] = voiced_notes[i] + 12  -- Octave up for even positions
            end
        end

    elseif voicing_type == VOICING_TYPES.DROP2 then
        -- Drop 2nd highest voice an octave
        if #voiced_notes >= 2 then
            voiced_notes[#voiced_notes - 1] = voiced_notes[#voiced_notes - 1] - 12
        end

    elseif voicing_type == VOICING_TYPES.DROP3 then
        -- Drop 3rd highest voice an octave
        if #voiced_notes >= 3 then
            voiced_notes[#voiced_notes - 2] = voiced_notes[#voiced_notes - 2] - 12
        end

    elseif voicing_type == VOICING_TYPES.FOURTHS then
        -- Stack in 4ths (5 semitones apart) instead of 3rds
        for i = 2, #voiced_notes do
            voiced_notes[i] = voiced_notes[1] + (i - 1) * 5
        end
    end

    -- Sort notes from low to high
    table.sort(voiced_notes)

    return voiced_notes
end

-- Transpose chord or note by semitones
function pitch.transpose(notes, semitones)
    if type(notes) == "number" then
        -- Single note
        return notes + semitones
    elseif type(notes) == "table" then
        -- Array of notes
        local transposed = {}
        for _, note in ipairs(notes) do
            table.insert(transposed, note + semitones)
        end
        return transposed
    end

    error("Invalid input to transpose: " .. type(notes))
end

-- Invert chord (flip intervals)
function pitch.invert(notes, inversion_num)
    if type(notes) ~= "table" or #notes == 0 then
        return notes
    end

    inversion_num = inversion_num or 1
    local inverted = {}

    -- Copy original notes
    for _, note in ipairs(notes) do
        table.insert(inverted, note)
    end

    -- Apply inversions
    for i = 1, inversion_num do
        if #inverted > 1 then
            -- Move lowest note up an octave
            local lowest = table.remove(inverted, 1)
            table.insert(inverted, lowest + 12)
        end
    end

    return inverted
end

-- Voice leading: find closest path between two chords
function pitch.closest_path(from_notes, to_notes)
    if not from_notes or not to_notes then
        return to_notes
    end

    if #from_notes == 0 then
        return to_notes
    end

    if #to_notes == 0 then
        return {}
    end

    local result = {}

    -- Simple closest voice leading: match each voice to closest available target
    local available_targets = {}
    for _, note in ipairs(to_notes) do
        table.insert(available_targets, note)
    end

    for _, from_note in ipairs(from_notes) do
        local closest_idx = 1
        local min_distance = math.abs(available_targets[1] - from_note)

        -- Find closest available target
        for i = 2, #available_targets do
            local distance = math.abs(available_targets[i] - from_note)
            if distance < min_distance then
                min_distance = distance
                closest_idx = i
            end
        end

        -- Use closest target and remove from available
        table.insert(result, available_targets[closest_idx])
        table.remove(available_targets, closest_idx)
    end

    -- Add any remaining targets
    for _, remaining in ipairs(available_targets) do
        table.insert(result, remaining)
    end

    return result
end

-- Export constants and functions
pitch.CHORD_QUALITIES = CHORD_QUALITIES
pitch.VOICING_TYPES = VOICING_TYPES
pitch.NOTE_TO_SEMITONE = NOTE_TO_SEMITONE

return pitch
