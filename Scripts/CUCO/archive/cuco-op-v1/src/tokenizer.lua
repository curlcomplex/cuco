-- CUCO-OP Tokenizer (Updated to current DSL decisions)
-- Parses CUCO Stacks notation into tokens for AST construction.
--
-- Authoritative surface (docs/examples MUST conform):
-- - Stacks: [ ... ]  (one step per token by default)
-- - Notes: c4, d#4, f-2  (octave may be negative)
-- - Inherit: -  (inherits previous; before first explicit token, inherits c3 at execution time)
-- - Rest: _     (silence)
-- - Sustain: .  (continue previous note/chord for this step)
-- - Offsets (on notes): c3+2, c3-5
-- - Repeats: c3*4, [c3 d3]*2
-- - Grid: ~16, ~8t, ~4q, ~12s   (t=triplet, q=quintuplet, s=septuplet)
-- - Context: @c.major, @f#.minor.q
-- - Processors: !arp(up,7), !rand/3, !poly(3,5,2), !c.major, !f#.minor
-- - Headers: @accent(12), @human(ms=10,vel=5[,pct=30])
-- - Velocity (post-note): @96, @+10, @-15
-- - Named chords (exclusive form): noteOctave.identifier  (e.g., c4.maj7, f#3.min9)
-- - Note groups (simultaneity): (c3 e3 g3)   -- no commas
-- - Variables: name = [...]
-- - Channel assignments: ch1 = name   -- ch1..ch16 always output on MIDI channels 1..16
-- - Debugger comments: //debug, //full, //trace
--
-- Deprecated (no longer tokenized or treated as legacy/ignored):
-- - Quick output flags: @name = ...
-- - Chord literals: CM7, Dm7, G7/B
-- - Commas inside note groups: (c4,e4,g4)
-- - Articulations: .stac .leg .ten .marc .ghost
-- - Accent "!" as strong/full-velocity (use @accent(...) header if needed)

local tokenizer = {}

-- Token types
tokenizer.TOKEN_TYPES = {
    NOTE        = "note",        -- c4, d#3, f-2 (pitch + optional accidental + optional negative octave)
    INHERIT     = "inherit",     -- -
    REST        = "rest",        -- _
    SUSTAIN     = "sustain",     -- .
    REPEAT      = "repeat",      -- *N
    OFFSET      = "offset",      -- +N, -N (attached to a NOTE)
    GRID        = "grid",        -- ~16, ~8t, ~4q, ~12s
    CONTEXT     = "context",     -- @c.major, @f#.minor.q
    PROCESSOR   = "processor",   -- !arp(up,7), !rand/3, !poly(3,5,2)
    VELOCITY    = "velocity",    -- @96, @+10, @-15 (attached to preceding NOTE or after CHORD_ID; see parsing)
    ACCENT      = "accent",      -- ^ (optional; if used, semantics configured via @accent(...))
    HEADER      = "header",      -- @accent(...), @human(...)
    CHORD_OPEN  = "chord_open",  -- (
    CHORD_CLOSE = "chord_close", -- )
    STACK_OPEN  = "stack_open",  -- [
    STACK_CLOSE = "stack_close", -- ]
    CHORD_ID    = "chord_id",    -- .maj7 .min9 .7b9 (identifier after a NOTE)
    VARIABLE    = "variable",    -- identifier for variables
    ASSIGN      = "assign",      -- =
    CHANNEL     = "channel",     -- ch1, ch2, ..., ch16
    COMMENT     = "comment",     -- //debug, //full, //trace
    WHITESPACE  = "whitespace",
    EOF         = "eof"
}

-- Patterns for token matching
local patterns = {
    -- Whitespace (spaces, tabs, newlines)
    whitespace = "^%s+",

    -- Comments (debug statements)
    comment = "^//[%w_]*",

    -- Grid resolution (~16, ~8t, ~4q, ~12s)
    grid = "^~(%d+)([tqs]?)",

    -- Context (@c.major, @f#.minor.q)
    context = "^@([a-g][#b]?)%.([%w_]+)%.?([qh]?)",

    -- Headers (@accent(...), @human(...))
    header = "^@(accent%b()|human%b())",

    -- Processors (!arp(up,7), !rand/3, !poly(3,5,2)) and key processors (!c.major)
    processor = "^!([%w_#b%.]+)(%b()?)",

    -- Channel assignment (ch1, ch2, etc.)
    channel = "^ch(%d+)",

    -- Variables (identifiers)
    variable = "^([%a_][%w_]*)",

    -- Notes (pitch with optional accidental, optional NEGATIVE octave like f-2, and optional inline offset)
    -- Captures: note, accidental, neg_marker ('-' or ''), octave digits, offset sign, offset digits
    note = "^([a-g])([#b]?)(%-?)(%d*)([%+%-]?)(%d*)",

    -- Velocity spec following a note/chord: @96, @+10, @-15
    velocity = "^@([%+%-]?%d+)",

    -- Accent marker: '^' only (strong '!' accent deprecated)
    accent = "^(%^)",

    -- Chord identifier after a note: .maj7 .min9 .7b9 etc
    chord_id = "^%.([a-zA-Z0-9#°ø]+)",

    -- Inherit (-)
    inherit = "^(%-)",

    -- Repeat (*N)
    repeat_op = "^%*(%d+%.?%d*)",

    -- Single character tokens
    single_char = "^(.)"
}

-- Token structure
function tokenizer.create_token(type, value, line, column, raw)
    return {
        type   = type,
        value  = value,
        line   = line,
        column = column,
        raw    = raw or value
    }
end

-- Main tokenizer function
function tokenizer.tokenize(input)
    local tokens = {}
    local line, column, pos = 1, 1, 1
    local len = #input

    while pos <= len do
        local matched = false
        local remaining = input:sub(pos)

        -- Whitespace
        local match = remaining:match(patterns.whitespace)
        if match then
            for i = 1, #match do
                if match:sub(i,i) == "\n" then
                    line, column = line + 1, 1
                else
                    column = column + 1
                end
            end
            pos = pos + #match
            matched = true
        end

        -- Comments
        if not matched then
            match = remaining:match(patterns.comment)
            if match then
                table.insert(tokens, tokenizer.create_token(tokenizer.TOKEN_TYPES.COMMENT, match, line, column, match))
                pos = pos + #match
                column = column + #match
                matched = true
            end
        end

        -- Grid
        if not matched then
            local num, suffix = remaining:match(patterns.grid)
            if num then
                local raw = "~" .. num .. (suffix or "")
                table.insert(tokens, tokenizer.create_token(tokenizer.TOKEN_TYPES.GRID, { number = tonumber(num), suffix = suffix }, line, column, raw))
                pos = pos + #raw
                column = column + #raw
                matched = true
            end
        end

        -- Headers (@accent, @human)
        if not matched then
            local hmatch = remaining:match(patterns.header)
            if hmatch then
                table.insert(tokens, tokenizer.create_token(tokenizer.TOKEN_TYPES.HEADER, hmatch, line, column, hmatch))
                pos = pos + #hmatch
                column = column + #hmatch
                matched = true
            end
        end

        -- Context (@key.scale[.q])
        if not matched then
            local root, quality, quantize = remaining:match(patterns.context)
            if root then
                local raw = "@" .. root .. "." .. quality .. (quantize ~= "" and ("." .. quantize) or "")
                table.insert(tokens, tokenizer.create_token(tokenizer.TOKEN_TYPES.CONTEXT, { root = root, quality = quality, quantize = quantize }, line, column, raw))
                pos = pos + #raw
                column = column + #raw
                matched = true
            end
        end

        -- Processors
        if not matched then
            local name_with_parens, args = remaining:match("^!([%w_#b%.]+)(%b())")
            if name_with_parens then
                local raw = "!" .. name_with_parens .. args
                table.insert(tokens, tokenizer.create_token(tokenizer.TOKEN_TYPES.PROCESSOR, { name = name_with_parens, args = args }, line, column, raw))
                pos = pos + #raw
                column = column + #raw
                matched = true
            else
                local name_only = remaining:match("^!([%w_#b%.]+)")
                if name_only then
                    local raw = "!" .. name_only
                    table.insert(tokens, tokenizer.create_token(tokenizer.TOKEN_TYPES.PROCESSOR, { name = name_only, args = nil }, line, column, raw))
                    pos = pos + #raw
                    column = column + #raw
                    matched = true
                end
            end
        end

        -- Channel assignment (ch1..ch16)
        if not matched then
            local ch_num = remaining:match(patterns.channel)
            if ch_num then
                local raw = "ch" .. ch_num
                table.insert(tokens, tokenizer.create_token(tokenizer.TOKEN_TYPES.CHANNEL, tonumber(ch_num), line, column, raw))
                pos = pos + #raw
                column = column + #raw
                matched = true
            end
        end

        -- Inherit (-)
        if not matched then
            local inh = remaining:match(patterns.inherit)
            if inh then
                table.insert(tokens, tokenizer.create_token(tokenizer.TOKEN_TYPES.INHERIT, "-", line, column, "-"))
                pos = pos + 1
                column = column + 1
                matched = true
            end
        end

        -- Notes (with optional negative octave and inline offset)
        if not matched then
            local n, accidental, neg_marker, octave, offset_sign, offset_val = remaining:match(patterns.note)
            if n and (accidental ~= "" or neg_marker ~= "" or octave ~= "" or offset_sign ~= "") then
                local octave_num = nil
                if octave ~= "" then
                    local sign = (neg_marker == "-") and -1 or 1
                    octave_num = sign * tonumber(octave)
                end
                local offset_num = nil
                if offset_sign ~= "" and offset_val ~= "" then
                    offset_num = tonumber(offset_sign .. offset_val)
                end
                local raw = n .. (accidental or "") .. (neg_marker or "") .. (octave or "") .. (offset_sign or "") .. (offset_val or "")
                table.insert(tokens, tokenizer.create_token(tokenizer.TOKEN_TYPES.NOTE, {
                    note = n,
                    accidental = accidental,
                    octave = octave_num,
                    offset = offset_num
                }, line, column, raw))
                pos = pos + #raw
                column = column + #raw
                matched = true

                -- After a NOTE, greedily parse optional chained CHORD_ID, VELOCITY, ACCENT (any order, repeat until none)
                local continue = true
                while continue do
                    continue = false
                    local rem2 = input:sub(pos)

                    -- Chord identifier after note: .maj7, .min9, .7b9
                    local cid = rem2:match(patterns.chord_id)
                    if cid then
                        local craw = "." .. cid
                        table.insert(tokens, tokenizer.create_token(tokenizer.TOKEN_TYPES.CHORD_ID, cid, line, column, craw))
                        pos = pos + #craw
                        column = column + #craw
                        continue = true
                        rem2 = input:sub(pos)
                    end

                    -- Velocity
                    local vmatch = rem2:match(patterns.velocity)
                    if vmatch then
                        local vraw = "@" .. vmatch
                        table.insert(tokens, tokenizer.create_token(tokenizer.TOKEN_TYPES.VELOCITY, vmatch, line, column, vraw))
                        pos = pos + #vraw
                        column = column + #vraw
                        continue = true
                        rem2 = input:sub(pos)
                    end

                    -- Accent (^ only)
                    local amatch = rem2:match(patterns.accent)
                    if amatch then
                        table.insert(tokens, tokenizer.create_token(tokenizer.TOKEN_TYPES.ACCENT, "^", line, column, "^"))
                        pos = pos + 1
                        column = column + 1
                        continue = true
                    end
                end
            end
        end

        -- Repeat operator
        if not matched then
            local num = remaining:match(patterns.repeat_op)
            if num then
                local raw = "*" .. num
                table.insert(tokens, tokenizer.create_token(tokenizer.TOKEN_TYPES.REPEAT, tonumber(num), line, column, raw))
                pos = pos + #raw
                column = column + #raw
                matched = true
            end
        end

        -- Variables (must come after keywords to avoid clobbering)
        if not matched then
            local name = remaining:match(patterns.variable)
            if name then
                table.insert(tokens, tokenizer.create_token(tokenizer.TOKEN_TYPES.VARIABLE, name, line, column, name))
                pos = pos + #name
                column = column + #name
                matched = true
            end
        end

        -- Single character tokens
        if not matched then
            local char = remaining:sub(1,1)
            local token_type = nil

            if char == "(" then
                token_type = tokenizer.TOKEN_TYPES.CHORD_OPEN
            elseif char == ")" then
                token_type = tokenizer.TOKEN_TYPES.CHORD_CLOSE
            elseif char == "[" then
                token_type = tokenizer.TOKEN_TYPES.STACK_OPEN
            elseif char == "]" then
                token_type = tokenizer.TOKEN_TYPES.STACK_CLOSE
            elseif char == "=" then
                token_type = tokenizer.TOKEN_TYPES.ASSIGN
            elseif char == "_" then
                token_type = tokenizer.TOKEN_TYPES.REST
            elseif char == "." then
                -- Lone '.' as sustain (NOT followed by identifier) handled here
                token_type = tokenizer.TOKEN_TYPES.SUSTAIN
            else
                -- Unknown / deprecated characters (e.g., commas in groups) are skipped
                pos = pos + 1
                column = column + 1
                matched = true
            end

            if token_type then
                table.insert(tokens, tokenizer.create_token(token_type, char, line, column, char))
                pos = pos + 1
                column = column + 1
                matched = true
            end
        end

        -- Safety: advance to avoid infinite loop
        if not matched then
            pos = pos + 1
            column = column + 1
        end
    end

    -- EOF
    table.insert(tokens, tokenizer.create_token(tokenizer.TOKEN_TYPES.EOF, nil, line, column))

    return tokens
end

-- Utility: print tokens (for debugging)
function tokenizer.print_tokens(tokens)
    for i, token in ipairs(tokens) do
        print(string.format("%d: %s = %s (line %d, col %d)",
            i, token.type, tostring(token.value), token.line, token.column))
    end
end

return tokenizer
