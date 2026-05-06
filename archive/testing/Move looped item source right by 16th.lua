-- Slip SOURCE start offset RIGHT by a musical step under a fixed loop section
-- Configure: how big is one step?
local STEP_QN = 0.25   -- 1/16 note. Try 0.5 for 1/8, 1 for quarter, etc.

reaper.Undo_BeginBlock()
local proj = 0
for i = 0, reaper.CountSelectedMediaItems(proj)-1 do
  local item = reaper.GetSelectedMediaItem(proj, i)
  local take = item and reaper.GetActiveTake(item)
  if take and not reaper.TakeIsMIDI(take) then
    -- convert QN to seconds at item position
    local pos = reaper.GetMediaItemInfo_Value(item, "D_POSITION")
    local qn  = reaper.TimeMap_timeToQN(pos)
    local new_time = reaper.TimeMap_QNToTime(qn + STEP_QN)
    local delta = new_time - pos

    local offs = reaper.GetMediaItemTakeInfo_Value(take, "D_STARTOFFS")
    reaper.SetMediaItemTakeInfo_Value(take, "D_STARTOFFS", offs + delta)
  end
end
reaper.UpdateArrange()
reaper.Undo_EndBlock("Slip SOURCE start offset RIGHT by QN step", -1)
