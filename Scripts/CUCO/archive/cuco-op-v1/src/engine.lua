-- CUCO-OP Engine
-- Main entry point for the parser/engine system
-- Provides high-level API for notation processing

local engine = {}

-- Load submodules
local tokenizer = require("tokenizer")
local parser = require("parser")
local executor = require("executor")

-- Engine version
engine.VERSION = "0.1.0"

-- Main API function: parse and execute notation string
function engine.process_notation(notation_string, context)
    -- Parse notation into AST
    local ast = parser.parse_notation(notation_string)

    -- Execute AST to generate plan
    local plan, final_context = executor.execute(ast, context)

    return plan, final_context, ast
end

-- Tokenize only (for debugging/inspection)
function engine.tokenize(notation_string)
    return tokenizer.tokenize(notation_string)
end

-- Parse only (for debugging/inspection)
function engine.parse(notation_string)
    return parser.parse_notation(notation_string)
end

-- Execute AST only (for debugging/inspection)
function engine.execute(ast, context)
    return executor.execute(ast, context)
end

-- Utility functions for debugging
function engine.debug_tokens(notation_string)
    local tokens = engine.tokenize(notation_string)
    tokenizer.print_tokens(tokens)
    return tokens
end

function engine.debug_ast(notation_string)
    local ast = engine.parse(notation_string)
    parser.print_ast(ast)
    return ast
end

function engine.debug_full(notation_string, context)
    print("=== TOKENS ===")
    local tokens = engine.debug_tokens(notation_string)

    print("\n=== AST ===")
    local ast = engine.debug_ast(notation_string)

    print("\n=== EXECUTION ===")
    local plan, final_context = engine.execute(ast, context)

    print("Generated " .. #plan .. " events:")
    for i, event in ipairs(plan) do
        print(string.format("  %d: pitch=%d, s=%.3f, e=%.3f, vel=%d, ch=%d",
                          i, event.pitch, event.s, event.e, event.vel, event.ch))
    end

    return plan, final_context, ast, tokens
end

-- Validate engine installation
function engine.self_test()
    local test_notation = [[
~16
seq = [c4 d4]
ch1 = seq
]]

    local ok, result = pcall(function()
        local plan = engine.process_notation(test_notation)

        -- Basic validation
        if #plan ~= 2 then
            error("Self-test failed: expected 2 events, got " .. #plan)
        end

        if plan[1].pitch ~= 60 or plan[2].pitch ~= 62 then
            error("Self-test failed: wrong pitches")
        end

        return plan
    end)

    if not ok then
        error("Engine self-test failed: " .. tostring(result))
    end

    print("CUCO-OP Engine v" .. engine.VERSION .. " - Self-test PASSED")
    return true
end

-- Export for use in other modules
return engine
