-- Test script to explore TrackFX API functions
local r = reaper

-- Get the first selected track and first FX
local track = r.GetSelectedTrack(0, 0)
if not track then
  r.ShowMessageBox("Please select a track with FX", "API Test", 0)
  return
end

local fx_count = r.TrackFX_GetCount(track)
if fx_count == 0 then
  r.ShowMessageBox("Please add some FX to the selected track", "API Test", 0)
  return
end

local fx_idx = 0  -- First FX
local param_count = r.TrackFX_GetNumParams(track, fx_idx)

r.ShowConsoleMsg("=== Testing TrackFX API Functions ===\n")
r.ShowConsoleMsg("FX Count: " .. fx_count .. "\n")
r.ShowConsoleMsg("Param Count on FX 0: " .. param_count .. "\n\n")

-- Test the first few parameters
for p = 0, math.min(param_count - 1, 5) do
  local param_name = select(2, r.TrackFX_GetParamName(track, fx_idx, p, ""))
  local current, minv, maxv = r.TrackFX_GetParam(track, fx_idx, p)
  
  r.ShowConsoleMsg(string.format("Param %d: %s\n", p, param_name))
  r.ShowConsoleMsg(string.format("  Current: %.6f, Min: %.6f, Max: %.6f, Range: %.6f\n", 
    current, minv, maxv, maxv - minv))
  
  -- Try TrackFX_GetParamEx if it exists
  if r.TrackFX_GetParamEx then
    local ex_min, ex_max = r.TrackFX_GetParamEx(track, fx_idx, p)
    r.ShowConsoleMsg(string.format("  GetParamEx: Min: %.6f, Max: %.6f\n", ex_min, ex_max))
  else
    r.ShowConsoleMsg("  GetParamEx: Not available\n")
  end
  
  -- Try to get step size information
  if r.TrackFX_GetParameterStepSizes then
    local step_info = r.TrackFX_GetParameterStepSizes(track, fx_idx, p)
    if step_info then
      r.ShowConsoleMsg("  Step Info: " .. tostring(step_info) .. "\n")
    else
      r.ShowConsoleMsg("  Step Info: nil\n")
    end
  end
  
  r.ShowConsoleMsg("\n")
end

r.ShowConsoleMsg("=== End API Test ===\n")
