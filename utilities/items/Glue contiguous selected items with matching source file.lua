-- @description Glue contiguous selected items that share the same source into single files (one glue per chain)
-- @version 1.0
-- @author You
-- @about
--   - Scans selected items per track, builds chains where:
--       * All items share the same active-take source filename
--       * Items are contiguous (touching or overlapping) within EPS seconds
--   - For each chain (len >= 2), performs ONE glue operation.
--   - Leaves the newly glued items selected (others unselected).
--
-- Notes:
--   * Uses active take to determine source.
--   * Overlaps are allowed; any real gap (> EPS) breaks the chain.
--   * Chains never cross tracks.

local r = reaper

-- Config
local EPS = 0.0005 -- seconds; tolerance for "touching"

-- Helpers
local function get_item_pos_len(item)
  local pos = r.GetMediaItemInfo_Value(item, "D_POSITION")
  local len = r.GetMediaItemInfo_Value(item, "D_LENGTH")
  return pos, len
end

local function item_end(item)
  local pos, len = get_item_pos_len(item)
  return pos + len
end

local function get_active_take_source_filename(item)
  local take = r.GetActiveTake(item)
  if not take or not r.TakeIsMIDI(take) then
    if not take then return nil end
    local src = r.GetMediaItemTake_Source(take)
    if not src then return nil end
    local buf = r.GetMediaSourceFileName(src, "")
    return buf ~= "" and buf or nil
  end
  -- MIDI take: treat as having no file source (won't join chains)
  return nil
end

local function collect_selected_items_by_track()
  local tracks = {}  -- { [track_ptr] = {item1, item2, ...} }
  local sel_count = r.CountSelectedMediaItems(0)
  for i = 0, sel_count - 1 do
    local it = r.GetSelectedMediaItem(0, i)
    local tr = r.GetMediaItem_Track(it)
    if not tracks[tr] then tracks[tr] = {} end
    table.insert(tracks[tr], it)
  end
  -- sort each track's items by position ascending
  for tr, list in pairs(tracks) do
    table.sort(list, function(a, b)
      local pa = r.GetMediaItemInfo_Value(a, "D_POSITION")
      local pb = r.GetMediaItemInfo_Value(b, "D_POSITION")
      if pa == pb then
        -- tie-break by length, then pointer
        local la = r.GetMediaItemInfo_Value(a, "D_LENGTH")
        local lb = r.GetMediaItemInfo_Value(b, "D_LENGTH")
        if la == lb then return tostring(a) < tostring(b) end
        return la < lb
      end
      return pa < pb
    end)
  end
  return tracks
end

-- Build chains per track:
-- A chain requires:
--   - same source filename across all items
--   - contiguous: next.start <= current_chain_end + EPS
local function build_chains_for_track(items_sorted)
  local chains = {} -- array of { items = {it1,it2,...}, src = "file", start = number, endpos = number }
  local i = 1
  while i <= #items_sorted do
    local it = items_sorted[i]
    local src = get_active_take_source_filename(it)
    if not src then
      -- cannot be part of a "same file" chain; skip as singleton (no glue)
      i = i + 1
    else
      local chain = { items = {}, src = src }
      local pos = r.GetMediaItemInfo_Value(it, "D_POSITION")
      local epos = item_end(it)
      table.insert(chain.items, it)
      local chain_end = epos
      -- extend while next item is contiguous and shares the same source
      local j = i + 1
      while j <= #items_sorted do
        local nxt = items_sorted[j]
        local nsrc = get_active_take_source_filename(nxt)
        if nsrc ~= src then break end
        local npos = r.GetMediaItemInfo_Value(nxt, "D_POSITION")
        if npos > (chain_end + EPS) then
          -- gap; stop chain
          break
        end
        table.insert(chain.items, nxt)
        local nend = item_end(nxt)
        if nend > chain_end then chain_end = nend end
        j = j + 1
      end
      chain.start = pos
      chain.endpos = chain_end
      table.insert(chains, chain)
      i = j
    end
  end
  return chains
end

local function unselect_all_items()
  r.Main_OnCommand(40289, 0) -- Item: Unselect all items
end

local function select_items(list, sel)
  for _, it in ipairs(list) do
    if r.ValidatePtr2(0, it, "MediaItem*") then
      r.SetMediaItemSelected(it, sel)
    end
  end
end

local function glue_selected_items_ignore_time()
  r.Main_OnCommand(41588, 0) -- Item: Glue items, ignoring time selection
end

-- Main
r.Undo_BeginBlock()
r.PreventUIRefresh(1)

-- Gather per-track items
local by_track = collect_selected_items_by_track()

-- Build all chains (project not modified yet)
local all_chains = {}
for tr, list in pairs(by_track) do
  local chains = build_chains_for_track(list)
  for _, ch in ipairs(chains) do
    if #ch.items >= 2 then
      table.insert(all_chains, ch)
    end
  end
end

-- Execute one glue per chain
-- Leave newly created glued items selected; others unselected.
unselect_all_items()
for _, ch in ipairs(all_chains) do
  select_items(ch.items, true)
  glue_selected_items_ignore_time()
  -- After glue, the old items are replaced by a single new item which remains selected.
  -- Prepare for next chain: clear selection for safety (we'll re-select next chain)
  -- But only if there are more chains; otherwise we leave the last glued item selected.
  if _ ~= all_chains[#all_chains] then
    unselect_all_items()
  end
end

r.PreventUIRefresh(-1)
r.UpdateArrange()
r.Undo_EndBlock("Glue contiguous selected items by source (single glue per chain)", -1)
