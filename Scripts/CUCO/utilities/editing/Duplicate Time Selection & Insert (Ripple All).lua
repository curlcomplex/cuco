-- Script: Duplicate Time Selection to New Space (Ripple All)
-- Description: Copies all content (Items, Envelopes, Markers) in time selection, inserts space after, and pastes the copy.

function main()
  local start_time, end_time = reaper.GetSet_LoopTimeRange(false, false, 0, 0, false)
  
  -- Check if time selection exists
  if start_time == end_time then
    reaper.ShowMessageBox("Please make a time selection first.", "Error", 0)
    return
  end

  local length = end_time - start_time
  
  reaper.PreventUIRefresh(1)
  reaper.Undo_BeginBlock()

  -- 1. SAVE CURRENT STATE (Selection)
  local saved_cursor = reaper.GetCursorPosition()
  
  -- 2. COLLECT MARKERS & REGIONS IN SELECTION
  -- We must manually copy markers because standard Copy/Paste ignores them
  local markers = {}
  local i = 0
  while true do
    local ret, isrgn, pos, rgnend, name, idx = reaper.EnumProjectMarkers(i)
    if not ret then break end
    
    -- Check if marker/region starts within our selection
    if pos >= start_time and pos < end_time then
      -- Calculate relative position for the copy
      local rel_start = pos - start_time
      local rel_end = 0
      if isrgn then rel_end = rgnend - start_time end
      
      table.insert(markers, {isrgn = isrgn, pos = rel_start, rgnend = rel_end, name = name, color = 0}) 
      -- Note: Color handling in Lua is tricky, we default to 0 (default color) for simplicity
    end
    i = i + 1
  end

  -- 3. COPY CONTENT (Items & Automation)
  -- Select All Tracks to ensure we grab everything
  reaper.Main_OnCommand(40296, 0) -- Track: Select all tracks
  reaper.Main_OnCommand(40718, 0) -- Item: Select all items on selected tracks in current time selection
  reaper.Main_OnCommand(40034, 0) -- Envelope: Select all points in time selection
  reaper.Main_OnCommand(40060, 0) -- Item: Copy selected area of items (Smart Copy)

  -- 4. INSERT EMPTY SPACE
  -- We set the selection to the "target" area to define the insert size
  reaper.GetSet_LoopTimeRange(true, false, end_time, end_time + length, false)
  reaper.Main_OnCommand(40200, 0) -- Time selection: Insert empty space at time selection (moving later items)

  -- 5. PASTE CONTENT
  reaper.SetEditCurPos(end_time, false, false)
  reaper.Main_OnCommand(40058, 0) -- Item: Paste items/tracks

  -- 6. RESTORE MARKERS IN NEW SECTION
  for _, m in ipairs(markers) do
    local new_pos = end_time + m.pos
    local new_end = end_time + m.rgnend
    reaper.AddProjectMarker(0, m.isrgn, new_pos, new_end, m.name, -1)
  end

  -- 7. CLEANUP & SET SELECTION TO NEW BLOCK
  -- This allows you to spam the key to keep duplicating forward
  reaper.GetSet_LoopTimeRange(true, false, end_time, end_time + length, false)
  
  reaper.Undo_EndBlock("Duplicate Time Selection (Insert/Ripple)", -1)
  reaper.PreventUIRefresh(-1)
  reaper.UpdateArrange()
end

main()
