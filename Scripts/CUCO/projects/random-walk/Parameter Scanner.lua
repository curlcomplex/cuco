-- Parameter Scanner for Plugin Analysis
-- This script scans all FX on selected tracks and outputs parameter names to a text file

local r = reaper

local function scan_fx_parameters()
  local sel_tracks = r.CountSelectedTracks(0)
  
  if sel_tracks == 0 then
    r.ShowMessageBox("Please select at least one track with FX loaded.", "Parameter Scanner", 0)
    return
  end
  
  -- Create output file on Desktop (more accessible)
  local output_path = os.getenv("HOME") .. "/Desktop/Parameter_Scan_Output.txt"
  local file = io.open(output_path, "w")
  
  if not file then
    r.ShowMessageBox("Could not create output file at: " .. output_path, "Parameter Scanner", 0)
    return
  end
  
  local function write_output(text)
    file:write(text)
    r.ShowConsoleMsg(text)  -- Also show in console for progress
  end
  
  write_output("=== PARAMETER SCANNER OUTPUT ===\n\n")
  
  for track_idx = 0, sel_tracks - 1 do
    local track = r.GetSelectedTrack(0, track_idx)
    local track_name = select(2, r.GetSetMediaTrackInfo_String(track, "P_NAME", "", false))
    if track_name == "" then
      track_name = "Track " .. (r.GetMediaTrackInfo_Value(track, "IP_TRACKNUMBER"))
    end
    
    local fx_count = r.TrackFX_GetCount(track)
    
    write_output(string.format(">>> TRACK: %s (FX Count: %d)\n", track_name, fx_count))
    
    if fx_count == 0 then
      write_output("    No FX on this track.\n\n")
    else
      for fx_idx = 0, fx_count - 1 do
        local fx_name = select(2, r.TrackFX_GetFXName(track, fx_idx, ""))
        local param_count = r.TrackFX_GetNumParams(track, fx_idx)
        
        write_output(string.format("\n=== FX %d: %s (%d parameters) ===\n", fx_idx + 1, fx_name, param_count))
        
        if param_count > 0 then
          for param_idx = 0, param_count - 1 do
            local param_name = select(2, r.TrackFX_GetParamName(track, fx_idx, param_idx, ""))
            local min_val, max_val = r.TrackFX_GetParamEx(track, fx_idx, param_idx)
            local current_val = r.TrackFX_GetParam(track, fx_idx, param_idx)
            
            -- Format parameter info
            write_output(string.format("  %3d: %-40s [%.3f - %.3f] = %.3f\n", 
              param_idx, param_name, min_val, max_val, current_val))
          end
        else
          write_output("    No parameters on this FX.\n")
        end
      end
      
      write_output("\n" .. string.rep("-", 80) .. "\n")
    end
  end
  
  write_output("\n=== END PARAMETER SCANNER OUTPUT ===\n")
  
  file:close()
  
  r.ShowConsoleMsg(string.format("\nOutput saved to: %s\n", output_path))
  r.ShowMessageBox("Parameter scan complete!\n\nOutput saved to:\n" .. output_path .. "\n\nYou can now copy the contents of this file for analysis.", "Parameter Scanner", 0)
end

-- Run the scanner
scan_fx_parameters()
