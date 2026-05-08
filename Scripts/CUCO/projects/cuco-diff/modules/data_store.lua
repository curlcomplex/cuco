-- data_store.lua (modules/data_store.lua)
-- CUCO-DIFF: Thin wrapper for persistence via Reaper ExtState with fallback to file

-- Set up module path
local info = debug.getinfo(1,'S')
local script_path = info.source:match[[^@?(.*[\/])[^\/]-$]]
package.path = package.path .. ';' .. script_path .. '?.lua'

local json = require('json_wrapper')

local data_store = {}

-- Internal: get reaper global safely
local R = rawget(_G, 'reaper')

function data_store.SaveProjectData(project_id, data_table)
  local ok, payload = pcall(function() return json.encode(data_table) end)
  if not ok then return false, 'json_encode_failed' end
  if R and R.SetExtState then
    R.SetExtState('CUCO-DIFF', project_id, payload, true)
  else
    local fp = io.open(project_id .. '.cuco.json', 'w')
    if fp then fp:write(payload); fp:close() end
  end
  return true
end

function data_store.LoadProjectData(project_id)
  if R and R.GetExtState then
    local payload = R.GetExtState('CUCO-DIFF', project_id)
    if not payload or payload == '' then return nil end
    local ok, tbl = pcall(function() return json.decode(payload) end)
    if ok then return tbl else return nil end
  else
    local fp = io.open(project_id .. '.cuco.json', 'r')
    if not fp then return nil end
    local contents = fp:read('*a')
    fp:close()
    local ok, tbl = pcall(function() return json.decode(contents) end)
    if ok then return tbl else return nil end
  end
end

function data_store.ClearProjectData(project_id)
  if R and R.SetExtState then
    R.SetExtState('CUCO-DIFF', project_id, '', true)
  else
    os.remove(project_id .. '.cuco.json')
  end
end

-- Note: ExtState has no key enumeration; index management is handled elsewhere
function data_store.GetAllProjectData()
  return {}
end

return data_store
