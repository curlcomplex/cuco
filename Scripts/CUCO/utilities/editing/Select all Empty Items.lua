-- @description Select all EMPTY-source items (Insert -> Empty item / note items)
-- @version 1.1
-- @about
--   Selects items whose takes are "EMPTY" media sources (i.e. REAPER empty items).
--   If an item has multiple takes, it is considered "empty" only if ALL takes are empty-source.

local CLEAR_EXISTING_SELECTION = true -- true = replace selection, false = add to selection

local function take_is_empty_source(take)
  if not take then return false end
  local src = reaper.GetMediaItemTake_Source(take)
  if not src then return false end
  local typ = reaper.GetMediaSourceType(src, "")
  -- Typical is "EMPTY". Extra fallbacks included because some contexts return ""/NULL-ish.
  return typ == "EMPTY" or typ == "" or typ == "NULL"
end

local function item_is_empty_item(item)
  local nt = reaper.CountTakes(item)

  -- Rare case: item truly has no takes (keep this for completeness)
  if nt == 0 then return true end

  -- Consider item empty only if ALL takes are empty-source
  for t = 0, nt - 1 do
    local take = reaper.GetMediaItemTake(item, t)
    if not take_is_empty_source(take) then
      return false
    end
  end
  return true
end

local proj = 0
local itemCount = reaper.CountMediaItems(proj)
local selectedCount = 0

reaper.Undo_BeginBlock()
reaper.PreventUIRefresh(1)

for i = 0, itemCount - 1 do
  local item = reaper.GetMediaItem(proj, i)
  local isEmpty = item_is_empty_item(item)

  if CLEAR_EXISTING_SELECTION then
    reaper.SetMediaItemSelected(item, isEmpty)
  else
    if isEmpty then reaper.SetMediaItemSelected(item, true) end
  end

  if isEmpty then selectedCount = selectedCount + 1 end
end

reaper.UpdateArrange()
reaper.PreventUIRefresh(-1)
reaper.Undo_EndBlock("Select all empty items (EMPTY source)", -1)

reaper.ShowConsoleMsg(("Selected %d empty items\n"):format(selectedCount))
