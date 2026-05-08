--[[
ReaScript Name: Parse SPEAR TXT to JSFX Array
Description: Converts a SPEAR .txt file into a JSFX array include for use in JSFX plugins.
Author: ChatGPT + curl
--]]

local function split_numbers(line)
  local nums = {}
  for num in line:gmatch("[-]?%d+%.?%d*[eE]?[-+]?%d*") do
    if tonumber(num) then
      nums[#nums+1] = num
    end
  end
  return nums
end

-- 1. Ask user for input file
local ok, infile = reaper.GetUserFileNameForRead("", "Select SPEAR TXT", ".txt")
if not ok or not infile or infile == "" then
  reaper.ShowConsoleMsg("No file selected.\n")
  return
end

-- 2. Read all numbers from the file
local all_numbers = {}
for line in io.lines(infile) do
  local nums = split_numbers(line)
  for _, n in ipairs(nums) do
    all_numbers[#all_numbers+1] = n
  end
end

-- 3. Output file in same directory, "_parsed.jsfx-inc"
local outbase = infile:gsub("%.txt$", ""):gsub("%.TXT$", "")
local outfile = outbase .. "_parsed.jsfx-inc"

-- 4. Write to output file as JSFX code
local out = io.open(outfile, "w")
if not out then
  reaper.ShowConsoleMsg("Can't open output file: "..outfile.."\n")
  return
end

out:write(string.format("data_len = %d;\ndata[] =\n", #all_numbers))
local line = ""
for i, n in ipairs(all_numbers) do
  line = line .. n
  if i < #all_numbers then line = line .. ", " end
  if (i % 10 == 0) or (i == #all_numbers) then
    out:write(line .. "\n")
    line = ""
  end
end
out:write(";")
out:close()

reaper.ShowMessageBox("Wrote "..#all_numbers.." values to:\n"..outfile, "Done", 0)
