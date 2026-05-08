-- Direct test of tokenization
local function trim(s) return (s or ""):gsub("^%s+",""):gsub("%s+$","") end

-- Copy the key functions from CUCO Stacks
local function parse_step_header(name)
  local stepQN, scale_ctx, body = nil, nil, name
  
  -- First, look for step resolution: ~N[flag]
  local hdr = name:match("^~%s*([%d%.]+%s*[tqsn]?)")
  if hdr then
    local num = hdr:match("^[%d%.]+"); local flag = hdr:match("[tqsn]$"); local denom = tonumber(num)
    if denom and denom>0 then
      stepQN = 4.0/denom
      if flag=="t" then stepQN=stepQN*(2/3)
      elseif flag=="q" then stepQN=stepQN*(4/5)
      elseif flag=="s" then stepQN=stepQN*(4/7)
      elseif flag=="n" then stepQN=stepQN*(8/9) end
    end
    body = name:sub(#hdr+2):gsub("^%s+","")
  end
  
  body = trim(body); if body:sub(1,1)=="~" then body=body:sub(2) end
  local body_clean = body:gsub("%s//.*$", "")
  return stepQN, scale_ctx, body, trim(body_clean)
end

-- Simple tokenizer test
local function test_tokenize_simple(input)
  local tokens = {}
  local i, n = 1, #input
  
  while i <= n do
    local ch = input:sub(i,i)
    if ch:match("%s") then
      i = i + 1
    else
      local j = i
      while j <= n and not input:sub(j,j):match("%s") do
        j = j + 1
      end
      local token = input:sub(i, j-1)
      
      -- Test note pattern
      local note_match = token:match("^([a-gA-G][b#]?%-?%d+)")
      if note_match then
        tokens[#tokens+1] = note_match
        print("Found note: " .. note_match)
      else
        tokens[#tokens+1] = token
        print("Found token: " .. token)
      end
      
      i = j
    end
  end
  
  return tokens
end

-- Test
local test_input = "~4 c#4 d#4 eb4 f#4 gb4 a4 bb4 c5"
print("Testing input: " .. test_input)

local stepQN, scale_ctx, body, body_clean = parse_step_header(test_input)
print("stepQN: " .. tostring(stepQN))
print("body: " .. tostring(body))  
print("body_clean: " .. tostring(body_clean))

print("\nTokenizing body_clean:")
local tokens = test_tokenize_simple(body_clean)

print("\nResults:")
for i, token in ipairs(tokens) do
  print(i .. ": " .. token)
end