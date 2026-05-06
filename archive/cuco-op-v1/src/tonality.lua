-- Tonality System Functions for CUCO-OP
-- Provides key/scale awareness, transposition, and modal harmony support
-- Research: ai_workflows/research/in_progress/tonality_research_2025-09-25.md

local tonality = {}

-- Scale definitions with interval patterns (semitones)
local SCALE_DEFINITIONS = {
    major = {
        name = "major",
        intervals = {2, 2, 1, 2, 2, 2, 1}, -- T-T-S-T-T-T-S
        degrees = {"tonic", "supertonic", "mediant", "subdominant", "dominant", "submediant", "leading"},
        qualities = {"perfect", "major", "minor", "perfect", "perfect", "minor", "major"}
    },
    minor = {
        name = "minor",
        intervals = {2, 1, 2, 2, 1, 2, 2}, -- T-S-T-T-S-T-T (natural minor)
        degrees = {"tonic", "supertonic", "mediant", "subdominant", "dominant", "submediant", "subtonic"},
        qualities = {"perfect", "minor", "major", "perfect", "perfect", "major", "minor"}
    },
    dorian = {
        name = "dorian",
        intervals = {2, 1, 2, 2, 2, 1, 2}, -- Major with b3, b7
        degrees = {"tonic", "supertonic", "mediant", "subdominant", "dominant", "submediant", "subtonic"},
        qualities = {"perfect", "minor", "minor", "perfect", "perfect", "minor", "minor"}
    },
    mixolydian = {
        name = "mixolydian",
        intervals = {2, 2, 1, 2, 2, 1, 2}, -- Major with b7
        degrees = {"tonic", "supertonic", "mediant", "subdominant", "dominant", "submediant", "subtonic"},
        qualities = {"perfect", "major", "minor", "perfect", "perfect", "minor", "minor"}
    }
}

-- Circle of fifths for key signature calculation
-- Maps root note (0-11) to number of sharps (positive) or flats (negative)
-- Note: Enharmonic equivalents (like F#/Gb) are handled by context preference
local CIRCLE_OF_FIFTHS = {
    [0] = 0,   -- C: no accidentals
    [7] = 1,   -- G: 1 sharp
    [2] = 2,   -- D: 2 sharps
    [9] = 3,   -- A: 3 sharps
    [4] = 4,   -- E: 4 sharps
    [11] = 5,  -- B: 5 sharps (or Cb: 7 flats - context dependent)
    [6] = 6,   -- F#: 6 sharps (or Gb: 6 flats - context dependent)
    [1] = 7,   -- C#: 7 sharps (or Db: 5 flats - context dependent)
    [5] = -1,  -- F: 1 flat
    [10] = -2, -- Bb: 2 flats
    [3] = -3,  -- Eb: 3 flats
    [8] = -4,  -- Ab: 4 flats
}

-- Note name to chromatic number mapping
local NOTE_TO_CHROMATIC = {
    c = 0, ["c#"] = 1, db = 1, d = 2, ["d#"] = 3, eb = 3,
    e = 4, f = 5, ["f#"] = 6, gb = 6, g = 7, ["g#"] = 8,
    ab = 8, a = 9, ["a#"] = 10, bb = 10, b = 11
}

-- Chromatic number to note name (prefer sharps in sharp keys, flats in flat keys)
local CHROMATIC_TO_NOTE_SHARP = {"c", "c#", "d", "d#", "e", "f", "f#", "g", "g#", "a", "a#", "b"}
local CHROMATIC_TO_NOTE_FLAT = {"c", "db", "d", "eb", "e", "f", "gb", "g", "ab", "a", "bb", "b"}

-- Convert note name to chromatic number (0-11)
local function parse_note_name(note_name)
    local clean_name = string.lower(note_name or "")
    return NOTE_TO_CHROMATIC[clean_name]
end

-- Get appropriate note name based on key signature preference
local function get_note_name(chromatic_num, prefer_sharps)
    if prefer_sharps then
        return CHROMATIC_TO_NOTE_SHARP[chromatic_num + 1] -- Lua arrays are 1-indexed
    else
        return CHROMATIC_TO_NOTE_FLAT[chromatic_num + 1]
    end
end

-- Generate scale notes for given key and mode
function tonality.get_scale_notes(key, mode, octave)
    mode = mode or "major"
    octave = octave or 4

    local root_chromatic = parse_note_name(key)
    if not root_chromatic then
        return nil, "Invalid key name: " .. tostring(key)
    end

    local scale_def = SCALE_DEFINITIONS[mode]
    if not scale_def then
        return nil, "Invalid mode: " .. tostring(mode)
    end

    -- Determine if this key uses sharps or flats
    local key_signature = CIRCLE_OF_FIFTHS[root_chromatic] or 0
    local prefer_sharps = key_signature >= 0

    local scale_notes = {}
    local current_chromatic = root_chromatic
    local current_octave = octave

    for i, interval in ipairs(scale_def.intervals) do
        -- Add current note
        local midi_number = current_octave * 12 + current_chromatic + 12 -- +12 for MIDI offset
        local note_name = get_note_name(current_chromatic, prefer_sharps) .. current_octave

        table.insert(scale_notes, {
            pitch = midi_number,
            name = note_name,
            degree = i,
            degree_name = scale_def.degrees[i],
            quality = scale_def.qualities[i]
        })

        -- Move to next note
        current_chromatic = (current_chromatic + interval) % 12
        if current_chromatic < (scale_notes[i] and (scale_notes[i].pitch % 12) or 0) then
            current_octave = current_octave + 1
        end
    end

    return scale_notes
end

-- Get key signature information
function tonality.get_key_signature(key, mode)
    local root_chromatic = parse_note_name(key)
    if not root_chromatic then
        return nil, "Invalid key name: " .. tostring(key)
    end

    -- Adjust for minor keys (relative major is 3 semitones up)
    if mode == "minor" then
        root_chromatic = (root_chromatic + 3) % 12
    end

    -- Handle enharmonic equivalents based on key name preference
    local signature_value = CIRCLE_OF_FIFTHS[root_chromatic] or 0
    local clean_key = string.lower(key)

    -- Override for enharmonic keys that prefer flats
    if clean_key == "db" or clean_key == "gb" or clean_key == "cb" then
        if root_chromatic == 1 then signature_value = -5  -- Db major
        elseif root_chromatic == 6 then signature_value = -6  -- Gb major
        elseif root_chromatic == 11 then signature_value = -7 -- Cb major
        end
    end

    local result = {
        sharps = math.max(0, signature_value),
        flats = math.max(0, -signature_value),
        accidentals = {}
    }

    -- Generate accidental note names
    if signature_value > 0 then
        -- Sharp keys: F# C# G# D# A# E# B#
        local sharp_order = {6, 1, 8, 3, 10, 5, 0} -- F# C# G# D# A# E# B#
        for i = 1, signature_value do
            local note_chromatic = sharp_order[i]
            table.insert(result.accidentals, get_note_name(note_chromatic, true) .. "#")
        end
    elseif signature_value < 0 then
        -- Flat keys: Bb Eb Ab Db Gb Cb Fb
        local flat_order = {10, 3, 8, 1, 6, 11, 4} -- Bb Eb Ab Db Gb Cb Fb
        for i = 1, -signature_value do
            local note_chromatic = flat_order[i]
            table.insert(result.accidentals, get_note_name(note_chromatic, false) .. "b")
        end
    end

    return result
end

-- Analyze scale degree for pitch in key context
function tonality.get_scale_degree(pitch, key, mode)
    mode = mode or "major"

    local root_chromatic = parse_note_name(key)
    if not root_chromatic then
        return nil, "Invalid key name: " .. tostring(key)
    end

    local scale_def = SCALE_DEFINITIONS[mode]
    if not scale_def then
        return nil, "Invalid mode: " .. tostring(mode)
    end

    -- Convert pitch to chromatic class (0-11)
    local pitch_chromatic = pitch % 12
    local interval_from_root = (pitch_chromatic - root_chromatic + 12) % 12

    -- Find matching scale degree
    local cumulative_interval = 0
    for degree = 1, #scale_def.intervals do
        if cumulative_interval == interval_from_root then
            return {
                degree = degree,
                quality = scale_def.qualities[degree],
                name = scale_def.degrees[degree],
                chromatic_interval = interval_from_root
            }
        end
        cumulative_interval = (cumulative_interval + scale_def.intervals[degree]) % 12
    end

    -- Not a diatonic scale degree
    return {
        degree = nil,
        quality = "chromatic",
        name = "non-diatonic",
        chromatic_interval = interval_from_root
    }
end

-- Transpose maintaining scale relationships
function tonality.transpose_in_key(pitches, from_key, to_key, mode)
    mode = mode or "major"

    local from_root = parse_note_name(from_key)
    local to_root = parse_note_name(to_key)

    if not from_root or not to_root then
        return nil, "Invalid key names"
    end

    local transposition_interval = (to_root - from_root + 12) % 12
    local transposed_pitches = {}

    for _, pitch in ipairs(pitches) do
        local new_pitch = pitch + transposition_interval
        table.insert(transposed_pitches, new_pitch)
    end

    return transposed_pitches
end

-- Check if pitch collection fits in key
function tonality.analyze_key_fit(pitches, key, mode)
    mode = mode or "major"

    local scale_notes = tonality.get_scale_notes(key, mode, 0)
    if not scale_notes then
        return nil, "Invalid key/mode"
    end

    -- Create set of diatonic pitch classes
    local diatonic_set = {}
    for _, note in ipairs(scale_notes) do
        diatonic_set[note.pitch % 12] = true
    end

    local total_pitches = #pitches
    local diatonic_count = 0
    local non_diatonic = {}

    for _, pitch in ipairs(pitches) do
        local pitch_class = pitch % 12
        if diatonic_set[pitch_class] then
            diatonic_count = diatonic_count + 1
        else
            table.insert(non_diatonic, pitch)
        end
    end

    local fit_score = total_pitches > 0 and (diatonic_count / total_pitches) or 0

    return {
        fit_score = fit_score,
        non_diatonic = non_diatonic,
        diatonic_count = diatonic_count,
        total_count = total_pitches
    }
end

return tonality
