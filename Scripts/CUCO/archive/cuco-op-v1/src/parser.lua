-- CUCO-OP Parser and AST Structure
-- Converts tokens into Abstract Syntax Tree for execution
--
-- AST Node Types:
-- - Program: root node containing statements
-- - Assignment: variable = expression, channel = expression
-- - Stack: [element1, element2, ...]
-- - Chord: (note1, note2, ...) or chord literal
-- - Note: pitch with properties
-- - Inherit: - token (inherits previous note/chord)
-- - Rest: . token (musical rest/silence)
-- - Sustain: _ token (sustains previous note/chord)
-- - Repeat: *N modifier on elements
-- - Context: @scale.mode headers
-- - Grid: ~N timing headers
-- - Processor: !name(args) modifiers

local parser = {}
local tokenizer = require("tokenizer")

-- AST Node types
parser.AST_TYPES = {
    PROGRAM = "program",
    ASSIGNMENT = "assignment",
    STACK = "stack",
    CHORD = "chord",
    NOTE = "note",
    INHERIT = "inherit",
    REST = "rest",
    SUSTAIN = "sustain",
    REPEAT = "repeat",
    CONTEXT = "context",
    GRID = "grid",
    PROCESSOR = "processor",
    VARIABLE_REF = "variable_ref"
}

-- Helper to parse header token raw string like @accent(12) or @human(ms=10,vel=5,pct=30)
local function parse_header_raw(raw)
    -- raw like @accent(12) or @human(ms=10,vel=5)
    local name, args = raw:match("@([%a_]+)%((.*)%)")
    if not name then return nil end
    local params = {}
    if args and args ~= "" then
        for part in args:gmatch("[^,]+") do
            local k,v = part:match("%s*([%a_]+)%s*=%s*([%-%d%.]+)%s*")
            if k and v then
                params[k] = tonumber(v) or v
            else
                -- single numeric for accent
                local lone = part:match("%s*([%-%d%.]+)%s*")
                if lone then
                    params.value = tonumber(lone) or lone
                end
            end
        end
    end
    return {name = name, params = params}
end

-- Create AST node
function parser.create_node(type, properties)
    local node = {type = type}
    if properties then
        for k, v in pairs(properties) do
            node[k] = v
        end
    end
    return node
end

-- Parser state
function parser.create_parser_state(tokens)
    return {
        tokens = tokens,
        pos = 1,
        current_token = tokens[1]
    }
end

-- Advance to next token
function parser.advance(state)
    if state.pos < #state.tokens then
        state.pos = state.pos + 1
        state.current_token = state.tokens[state.pos]
    end
    return state.current_token
end

-- Peek at next token without advancing
function parser.peek(state, offset)
    offset = offset or 1
    local peek_pos = state.pos + offset
    if peek_pos <= #state.tokens then
        return state.tokens[peek_pos]
    end
    return nil
end

-- Check if current token matches expected type
function parser.match(state, token_type)
    return state.current_token and state.current_token.type == token_type
end

-- Consume expected token type or error
function parser.expect(state, token_type, message)
    if not parser.match(state, token_type) then
        error(message or ("Expected " .. token_type .. " but got " .. (state.current_token and state.current_token.type or "EOF")))
    end
    local token = state.current_token
    parser.advance(state)
    return token
end

-- Main parse function
function parser.parse(tokens)
    local state = parser.create_parser_state(tokens)
    return parser.parse_program(state)
end

-- Parse program (top level)
function parser.parse_program(state)
    local statements = {}

    while not parser.match(state, tokenizer.TOKEN_TYPES.EOF) do
        local stmt = parser.parse_statement(state)
        if stmt then
            table.insert(statements, stmt)
        end
    end

    return parser.create_node(parser.AST_TYPES.PROGRAM, {statements = statements})
end

-- Parse statement (assignment, context, grid, etc.)
function parser.parse_statement(state)
    -- Skip comments
    if parser.match(state, tokenizer.TOKEN_TYPES.COMMENT) then
        parser.advance(state)
        return nil
    end

    -- Context header (@c.major)
    if parser.match(state, tokenizer.TOKEN_TYPES.CONTEXT) then
        local token = parser.expect(state, tokenizer.TOKEN_TYPES.CONTEXT)
        return parser.create_node(parser.AST_TYPES.CONTEXT, {
            root = token.value.root,
            quality = token.value.quality,
            quantize = token.value.quantize
        })
    end

    -- Accent / Humanization headers
    if parser.match(state, tokenizer.TOKEN_TYPES.HEADER) then
        local token = parser.expect(state, tokenizer.TOKEN_TYPES.HEADER)
        local parsed = parse_header_raw(token.raw)
        if parsed and parsed.name == 'accent' then
            return parser.create_node('accent_header', {value = parsed.params.value or 12})
        elseif parsed and parsed.name == 'human' then
            return parser.create_node('human_header', parsed.params)
        else
            return nil
        end
    end

    -- Grid header (~16)
    if parser.match(state, tokenizer.TOKEN_TYPES.GRID) then
        local token = parser.expect(state, tokenizer.TOKEN_TYPES.GRID)
        return parser.create_node(parser.AST_TYPES.GRID, {
            number = token.value.number,
            suffix = token.value.suffix
        })
    end

    -- Output flag assignment (@name = expr)
    if parser.match(state, tokenizer.TOKEN_TYPES.OUTPUT_FLAG) then
        local name_token = parser.expect(state, tokenizer.TOKEN_TYPES.OUTPUT_FLAG)
        parser.expect(state, tokenizer.TOKEN_TYPES.ASSIGN)
        local expr = parser.parse_expression(state)

        return parser.create_node(parser.AST_TYPES.ASSIGNMENT, {
            target = {type = "output", name = name_token.value},
            expression = expr
        })
    end

    -- Variable or channel assignment (including chained: ch1 = merge = [expr])
    if parser.match(state, tokenizer.TOKEN_TYPES.VARIABLE) or parser.match(state, tokenizer.TOKEN_TYPES.CHANNEL) then
        local targets = {}
        
        -- Collect all assignment targets (check for chained pattern: var = var = expr)
        while parser.match(state, tokenizer.TOKEN_TYPES.VARIABLE) or parser.match(state, tokenizer.TOKEN_TYPES.CHANNEL) do
            local target_token = state.current_token
            parser.advance(state)
            
            parser.expect(state, tokenizer.TOKEN_TYPES.ASSIGN)
            
            local target_type = (target_token.type == tokenizer.TOKEN_TYPES.CHANNEL) and "channel" or "variable"
            table.insert(targets, {type = target_type, name = target_token.value})
            
            -- Check if next token pattern is: VARIABLE/CHANNEL followed by ASSIGN (chained assignment)
            local next_token = state.current_token
            local peek_token = parser.peek(state, 1)
            
            if not ((next_token and (next_token.type == tokenizer.TOKEN_TYPES.VARIABLE or next_token.type == tokenizer.TOKEN_TYPES.CHANNEL)) and
                    (peek_token and peek_token.type == tokenizer.TOKEN_TYPES.ASSIGN)) then
                -- This is not a chained assignment pattern, stop collecting targets
                break
            end
            -- Otherwise continue the loop to collect the next target
        end
        
        local expr = parser.parse_expression(state)
        
        -- Create assignment node (maintain backward compatibility)
        if #targets == 1 then
            -- Single target - use old format for backward compatibility
            return parser.create_node(parser.AST_TYPES.ASSIGNMENT, {
                target = targets[1],
                expression = expr
            })
        else
            -- Multiple targets - use new chained format
            return parser.create_node(parser.AST_TYPES.ASSIGNMENT, {
                targets = targets,
                expression = expr
            })
        end
    end

    -- Check for EOF before trying standalone expression
    if parser.match(state, tokenizer.TOKEN_TYPES.EOF) then
        return nil
    end
    
    -- Standalone expression
    local expr = parser.parse_expression(state)
    return expr
end

-- Parse expression (stack, note, variable reference, etc.)
function parser.parse_expression(state)
    local expr = parser.parse_primary(state)

    -- Handle repeats (*N) FIRST
    if parser.match(state, tokenizer.TOKEN_TYPES.REPEAT) then
        local repeat_token = parser.expect(state, tokenizer.TOKEN_TYPES.REPEAT)
        expr = parser.create_node(parser.AST_TYPES.REPEAT, {
            target = expr,
            count = repeat_token.value
        })
    end

    -- Handle processors (!arp, !poly, etc.) AFTER repeats
    while parser.match(state, tokenizer.TOKEN_TYPES.PROCESSOR) do
        local proc_token = parser.expect(state, tokenizer.TOKEN_TYPES.PROCESSOR)
        expr = parser.create_node(parser.AST_TYPES.PROCESSOR, {
            name = proc_token.value.name,
            args = proc_token.value.args,
            target = expr
        })
    end

    return expr
end

-- Parse primary expression (stack, chord, note, variable, etc.)
function parser.parse_primary(state)
    -- Stack [...]
    if parser.match(state, tokenizer.TOKEN_TYPES.STACK_OPEN) then
        return parser.parse_stack(state)
    end

    -- Chord (...)
    if parser.match(state, tokenizer.TOKEN_TYPES.CHORD_OPEN) then
        return parser.parse_chord(state)
    end


    -- Note
    if parser.match(state, tokenizer.TOKEN_TYPES.NOTE) then
        local token = parser.expect(state, tokenizer.TOKEN_TYPES.NOTE)
        local node = parser.create_node(parser.AST_TYPES.NOTE, {
            note = token.value.note,
            accidental = token.value.accidental,
            flat = token.value.flat,
            octave = token.value.octave,
            offset = token.value.offset
        })
        parser.capture_expression_modifiers(state, node)
        return node
    end

    -- Inherit (-)
    if parser.match(state, tokenizer.TOKEN_TYPES.INHERIT) then
        local token = parser.expect(state, tokenizer.TOKEN_TYPES.INHERIT)
        return parser.create_node(parser.AST_TYPES.INHERIT, {
            processed = token.value.processed
        })
    end

    -- Rest (_)
    if parser.match(state, tokenizer.TOKEN_TYPES.REST) then
        parser.expect(state, tokenizer.TOKEN_TYPES.REST)
        return parser.create_node(parser.AST_TYPES.REST, {})
    end

    -- Sustain (.)
    if parser.match(state, tokenizer.TOKEN_TYPES.SUSTAIN) then
        parser.expect(state, tokenizer.TOKEN_TYPES.SUSTAIN)
        return parser.create_node(parser.AST_TYPES.SUSTAIN, {})
    end

    -- Variable reference
    if parser.match(state, tokenizer.TOKEN_TYPES.VARIABLE) then
        local token = parser.expect(state, tokenizer.TOKEN_TYPES.VARIABLE)
        return parser.create_node(parser.AST_TYPES.VARIABLE_REF, {
            name = token.value
        })
    end

    error("Unexpected token: " .. (state.current_token and state.current_token.type or "EOF"))
end

-- Capture trailing modifiers (velocity, accent, articulation) following a note or chord literal
function parser.capture_expression_modifiers(state, node)
    local tokenizer_ref = require("tokenizer")
    while true do
        local t = state.current_token
        if not t then break end
        if t.type == tokenizer_ref.TOKEN_TYPES.VELOCITY then
            node.velocity_spec = t.value  -- raw number with optional sign
            parser.advance(state)
        elseif t.type == tokenizer_ref.TOKEN_TYPES.ACCENT then
            if t.value == "^" then
                node.accent = "normal"
            elseif t.value == "!" then
                node.accent = "strong"
            end
            parser.advance(state)
        elseif t.type == tokenizer_ref.TOKEN_TYPES.ARTICULATION then
            -- Distinguish between regular articulations and chord qualities
            local art = t.value
            
            -- Known articulations
            local articulations = {stac = true, leg = true, ten = true, marc = true, ghost = true}
            
            if articulations[art] then
                -- Regular articulation
                node.articulation = art
            else
                -- Assume it's a chord quality
                node.chord_quality = art
            end
            parser.advance(state)
        else
            break
        end
    end
end

-- Parse stack [element1, element2, ...]
function parser.parse_stack(state)
    parser.expect(state, tokenizer.TOKEN_TYPES.STACK_OPEN)

    local elements = {}

    while not parser.match(state, tokenizer.TOKEN_TYPES.STACK_CLOSE) and
          not parser.match(state, tokenizer.TOKEN_TYPES.EOF) do
        local element = parser.parse_expression(state)
        table.insert(elements, element)
    end

    parser.expect(state, tokenizer.TOKEN_TYPES.STACK_CLOSE)

    return parser.create_node(parser.AST_TYPES.STACK, {elements = elements})
end

-- Parse chord (note1, note2, ...) or chord literal
function parser.parse_chord(state)
    parser.expect(state, tokenizer.TOKEN_TYPES.CHORD_OPEN)

    local notes = {}

    while not parser.match(state, tokenizer.TOKEN_TYPES.CHORD_CLOSE) and
          not parser.match(state, tokenizer.TOKEN_TYPES.EOF) do

        -- Parse note within chord
        if parser.match(state, tokenizer.TOKEN_TYPES.NOTE) then
            local note = parser.parse_primary(state)
            table.insert(notes, note)
        else
            error("Expected note in chord")
        end

        -- Optional comma separator
        if parser.match(state, tokenizer.TOKEN_TYPES.CHORD_SEP) then
            parser.advance(state)
        end
    end

    parser.expect(state, tokenizer.TOKEN_TYPES.CHORD_CLOSE)

    return parser.create_node(parser.AST_TYPES.CHORD, {notes = notes})
end

-- Utility function to print AST (for debugging)
function parser.print_ast(node, indent)
    indent = indent or 0
    local prefix = string.rep("  ", indent)

    print(prefix .. node.type)

    for k, v in pairs(node) do
        if k ~= "type" then
            if type(v) == "table" then
                if v.type then
                    -- It's an AST node
                    print(prefix .. "  " .. k .. ":")
                    parser.print_ast(v, indent + 2)
                elseif #v > 0 then
                    -- It's an array
                    print(prefix .. "  " .. k .. ":")
                    for i, item in ipairs(v) do
                        if type(item) == "table" and item.type then
                            parser.print_ast(item, indent + 2)
                        else
                            print(prefix .. "    " .. tostring(item))
                        end
                    end
                else
                    -- It's a regular table
                    print(prefix .. "  " .. k .. ": " .. tostring(v))
                end
            else
                print(prefix .. "  " .. k .. ": " .. tostring(v))
            end
        end
    end
end

-- Parse notation string (main entry point)
function parser.parse_notation(notation_string)
    local tokens = tokenizer.tokenize(notation_string)
    return parser.parse(tokens)
end

return parser
