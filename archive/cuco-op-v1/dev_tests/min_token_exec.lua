-- Minimal local test: chord literal execution
-- Runs tokenizer+parser+executor directly (no OSC) to inspect plan

package.path = package.path .. ';./src/?.lua'

local tokenizer = require('tokenizer')
local parser = require('parser')
local executor = require('executor')

local notation = [[CM F#m7 B°7 DM7/F#]]

local tokens = tokenizer.tokenize(notation)
print('--- TOKENS ---')
for i,t in ipairs(tokens) do
  if t.type ~= 'whitespace' then
    print(i, t.type, t.raw or t.value)
  end
end

local ast = parser.parse(tokens)
print('\n--- AST ---')
parser.print_ast(ast)

local plan, ctx = executor.execute(ast)
print('\n--- PLAN ---')
for i,e in ipairs(plan) do
  print(i, e.pitch, e.s, e.e, e.vel, e.ch)
end
print('\nTotal events:', #plan)
