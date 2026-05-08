--[[
REAPER RPP Track Parser - Enhanced Version
Combines original project goals with robust parsing from reference implementation
--]]

-- Parser Infrastructure (updated based on reference)
RNode = { parent = nil, line = nil }

local bit = not reaper and require("bit") or {
    band = function(a,b) return a & b end,
    rshift = function(a,b) return a >> b end
}

function RNode:new(o)
    o = o or {}
    setmetatable(o, self)
    self.__index = self
    if o.parent then o.parent:addNode(o) end
    return o
end

function RNode:getTokens()
    if not self.tokens then
        self.tokens = {}
        if self.line then
            for token in self.line:gmatch("([^%s]+)") do
                table.insert(self.tokens, {
                    getString = function() return token end,
                    getNumber = function() return tonumber(token) or 0 end,
                    getBoolean = function() return token ~= "0" end
                })
            end
        end
    end
    return self.tokens
end

function RNode:getToken(index)
    local tokens = self:getTokens()
    return tokens[index] or {
        getString = function() return "" end,
        getNumber = function() return 0 end,
        getBoolean = function() return false end
    }
end

function RNode:getName()
    return self:getToken(1):getString()
end

function RNode:getParam(index)
    return self:getToken(index + 1)
end

RChunk = RNode:new{}

function RChunk:findFirstNodeByName(name)
    if not self.children then return nil end
    for _, child in ipairs(self.children) do
        if child:getName() == name then
            return child
        end
    end
    return nil
end

function RChunk:findFirstChunkByName(name)
    for _, child in ipairs(self.children) do
        if getmetatable(child) == RChunk and child:getName() == name then
            return child
        end
    end
    return nil
end

function RChunk:findAllNodesByName(name)
    local t = {}
    if not self.children then return t end
    for _, child in ipairs(self.children) do
        if child:getName() == name then
            table.insert(t, child)
        end
    end
    return t
end

function RChunk:findAllChunksByName(name)
    local t = {}
    for _, child in ipairs(self.children) do
        if getmetatable(child) == RChunk and child:getName() == name then
            table.insert(t, child)
        end
    end
    return t
end

function RChunk:addNode(node)
    if not self.children then self.children = {} end
    node.parent = self
    table.insert(self.children, node)
    return node
end

-- Core Parser Functions (updated)
function ReadRPP(filename)
    local file, err = io.open(filename, "r")
    if not file then
        reaper.ShowConsoleMsg("ERROR: "..err.."\n")
        return nil
    end
    
    local lines = {}
    for line in file:lines() do
        line = line:match("^%s*(.-)%s*$") or line -- Trim
        if line ~= "" then
            table.insert(lines, line)
        end
    end
    file:close()
    
    return ParseRPPLines(lines)
end

function ParseRPPLines(lines)
    local root, current_parent = nil, nil
    local stack = {}
    
    for _, line in ipairs(lines) do
        local first_char = line:sub(1, 1)
        
        if first_char == "<" then
            local chunk = RChunk:new{line = line:sub(2)}
            if current_parent then
                chunk.parent = current_parent
                current_parent:addNode(chunk)
            end
            table.insert(stack, current_parent)
            current_parent = chunk
            
            if not root and chunk:getName() == "REAPER_PROJECT" then
                root = chunk
            end
            
        elseif first_char == ">" then
            current_parent = table.remove(stack)
            
        elseif current_parent then
            current_parent:addNode(RNode:new{line = line})
        end
    end
    
    return root
end

function GetTrackInfo(track)
    local info = {
        name = "Unnamed",
        guid = "",
        items = 0,
        mute = false,
        solo = false,
        solo_mode = 0,
        volume = 1.0,
        pan = 0.0,
        width = 1.0,
        color = 0,
        peak_color = 0,
        peak_rgb = {r=0, g=0, b=0},
        height = 0,
        fx_count = 0,
        fx = {},
        folder_state = "Normal",
        folder_flags = {is_parent=false, is_closed=false, is_end=false},
        receives = {},
        sends = {},
        phase_inverted = false,
        automation_mode = 0,
        record_armed = false
    }

    
    -- Get track height with minimum of 29 pixels
    local MIN_TRACK_HEIGHT = 29
    local trackheight_node = track:findFirstNodeByName("TRACKHEIGHT")
    if trackheight_node and #trackheight_node:getTokens() >= 2 then
        info.height = math.max(trackheight_node:getToken(2):getNumber() or MIN_TRACK_HEIGHT, MIN_TRACK_HEIGHT)
        info.height_data = {}
        for i = 2, #trackheight_node:getTokens() do
            table.insert(info.height_data, trackheight_node:getToken(i):getNumber() or 0)
        end
    else
        info.height = MIN_TRACK_HEIGHT
        info.height_data = {MIN_TRACK_HEIGHT, 0, 0, 0, 0, 0, 0}
    end
    
    -- Get track name (handling quoted names)
    local name_node = track:findFirstNodeByName("NAME")
    if name_node then
        local raw_name = name_node.line:match("NAME%s+(.*)") or ""
        
        -- Your exact rules:
        local first_char = raw_name:sub(1,1)
        local last_char = raw_name:sub(-1)
        
        if first_char == '"' and last_char == '"' and not raw_name:match("'") then
            info.name = raw_name:sub(2, -2)  -- Pure double-quoted case
        elseif first_char == "'" and last_char == "'" then
            info.name = raw_name:sub(2, -2)  -- Single-quote wrapped case
        else
            info.name = raw_name  -- All others unchanged
        end
    end
    
   -- Get track GUID from TRACKID
       local trackid_node = track:findFirstNodeByName("TRACKID")
       if trackid_node then
           info.guid = trackid_node:getToken(2):getString() or ""
           info.guid = info.guid:gsub("[{}]", "")
       end
       
       -- IPHASE phase inversion button (modern REAPER)
       info.phase_inverted = false  -- Default to false
       local iphase_node = track:findFirstNodeByName("IPHASE")
       if iphase_node then
           local phase_val = iphase_node:getToken(2):getString()
           -- Handle all possible formats: "1", 1, "true", etc.
           info.phase_inverted = (phase_val == "1") or (tonumber(phase_val) == 1)
       end
        
    -- Get item count
    local items = track:findAllChunksByName("ITEM")
    info.items = items and #items or 0
    
    -- CORRECTED MUTE/SOLO PARSING (using MUTESOLO)
    local mutesolo_node = track:findFirstNodeByName("MUTESOLO")
    if mutesolo_node then
        info.mute = mutesolo_node:getToken(2):getString() == "1"
        local solo_val = mutesolo_node:getToken(3):getString()
        info.solo = (solo_val ~= "0")
        info.solo_mode = tonumber(solo_val) or 0
    end
    
    -- Get volume and pan (from VOLPAN)
    local volpan = track:findFirstNodeByName("VOLPAN")
    if volpan then
        info.volume = volpan:getToken(2):getNumber() or 1.0
        info.pan = volpan:getToken(3):getNumber() or 0.0
    else
        info.volume = 1.0
        info.pan = 0.0
    end
    
    -- Get width (from separate WIDTH parameter)
    local width_node = track:findFirstNodeByName("WIDTH")
    if width_node then
        info.width = width_node:getToken(2):getNumber() or 1.0
    else
        info.width = 1.0
    end
    
    -- Get PEAKCOL (meter peak color)
    local peakcol_node = track:findFirstNodeByName("PEAKCOL")
    if peakcol_node then
        info.peak_color = peakcol_node:getToken(2):getNumber() or 0
        
        -- Native bit operations (works in ReaScript)
        info.peak_rgb = {
            r = (info.peak_color >> 16) & 0xFF,
            g = (info.peak_color >> 8) & 0xFF,
            b = info.peak_color & 0xFF
        }
    end
    
    -- Get record-arm state (corrected version)
    info.record_armed = false
    local rec_node = track:findFirstNodeByName("REC")
    if rec_node then
        local rec_val = rec_node:getToken(2):getString()
        info.record_armed = (rec_val == "1") or (tonumber(rec_val) == 1)
    end
    
    local automode_node = track:findFirstNodeByName("AUTOMODE")
    if automode_node then
        info.automation_mode = automode_node:getToken(2):getNumber() or 0
    end
    
    -- Get color
    info.color = track:findFirstNodeByName("TRACKID") and track:findFirstNodeByName("TRACKID"):getToken(2):getNumber() or 0
    
    -- Get FX information
    local fxchain = track:findFirstChunkByName("FXCHAIN")
    if fxchain then
        local fx_chunks = fxchain:findAllChunksByName("FX")
        info.fx_count = #fx_chunks
        for _, fx in ipairs(fx_chunks) do
            local fx_info = {
                name = fx:findFirstNodeByName("NAME") and fx:findFirstNodeByName("NAME"):getToken(2):getString() or "Unknown",
                guid = fx:findFirstNodeByName("FXID") and fx:findFirstNodeByName("FXID"):getToken(2):getString() or ""
            }
            table.insert(info.fx, fx_info)
        end
    end
    
    -- Get folder state
    info.folder_state = "Normal"  -- Default
    info.folder_flags = {
        is_parent = false,
        is_closed = false,
        is_end = false
    }
    
    local isbus_node = track:findFirstNodeByName("ISBUS")
    if isbus_node then
        local parent_state = isbus_node:getToken(2):getNumber() or 0
        local child_state = isbus_node:getToken(3):getNumber() or 0
        
        -- Set flags
        info.folder_flags = {
            is_parent = (parent_state > 0),
            is_closed = (parent_state == 2),
            is_end = (child_state == -1)
        }
        
        -- Set display state
        if child_state == -1 then
            info.folder_state = "End"
        elseif parent_state == 1 then
            info.folder_state = "Open"
        elseif parent_state == 2 then
            info.folder_state = "Closed"
        end
    end
    
    -- Get sends/receives
    local receives = track:findAllChunksByName("RECEIVE")
    for _, recv in ipairs(receives) do
        table.insert(info.receives, {
            track = recv:getToken(2):getNumber(),
            volume = recv:getToken(3):getNumber(),
            pan = recv:getToken(4):getNumber()
        })
    end
    
    local sends = track:findAllChunksByName("SEND")
    for _, send in ipairs(sends) do
        table.insert(info.sends, {
            track = send:getToken(2):getNumber(),
            volume = send:getToken(3):getNumber(),
            pan = send:getToken(4):getNumber()
        })
    end
    
    -- Enhanced color detection with fallbacks
    info.color = 0
    info.color_source = "None"  -- For debugging
    
    -- Check all possible color locations (in order of priority)
    local color_node = track:findFirstNodeByName("COLOR")
    local trackid_node = track:findFirstNodeByName("TRACKID")
    local custom_color_node = track:findFirstNodeByName("CUSTOMCOLOR")
    
    -- 1. Modern COLOR node
    if color_node then
        info.color = color_node:getToken(2):getNumber() or 0
        info.color_source = "COLOR node"
    
    -- 2. Legacy TRACKID with color (3 tokens)
    elseif trackid_node and #trackid_node:getTokens() >= 3 then
        info.color = trackid_node:getToken(3):getNumber() or 0
        info.color_source = "TRACKID color"
    
    -- 3. CUSTOMCOLOR node (older versions)
    elseif custom_color_node then
        info.color = custom_color_node:getToken(2):getNumber() or 0
        info.color_source = "CUSTOMCOLOR node"
    
    -- 4. Check for hidden color data in other parameters
    else
        -- Some versions hide color in unexpected places
        local hidden_color = track:findFirstNodeByName("BCOLOR") or 
                           track:findFirstNodeByName("TCOLOR") or
                           track:findFirstNodeByName("FCOLOR")
        
        if hidden_color then
            info.color = hidden_color:getToken(2):getNumber() or 0
            info.color_source = "Hidden color node ("..hidden_color:getName()..")"
        end
    end
    
    -- Convert to RGB
    info.rgb = {
        r = info.color & 0xFF,
        g = (info.color >> 8) & 0xFF,
        b = (info.color >> 16) & 0xFF
    }
    
    -- Debug output
    ShowProgress(string.format(
        "COLOR DEBUG: '%s' | Source: %s | Value: #%06X (R:%d G:%d B:%d)",
        info.name,
        info.color_source,
        info.color,
        info.rgb.r, info.rgb.g, info.rgb.b
    ))
    
    info.nchan = track:findFirstNodeByName("NCHAN") and track:findFirstNodeByName("NCHAN"):getToken(2):getNumber() or 2
    info.mainsend = track:findFirstNodeByName("MAINSEND") and track:findFirstNodeByName("MAINSEND"):getToken(2):getNumber() or 1
    info.automode = track:findFirstNodeByName("AUTOMODE") and track:findFirstNodeByName("AUTOMODE"):getToken(2):getNumber() or 0
    info.panlawflags = track:findFirstNodeByName("PANLAWFLAGS") and track:findFirstNodeByName("PANLAWFLAGS"):getToken(2):getNumber() or 0
    
    info.beat_timebase = -1  -- Default to project timebase
    local beat_node = track:findFirstNodeByName("BEAT")
    if beat_node then
        local beat_val = beat_node:getToken(2):getNumber()
        -- Only accept valid timebase values (0-3), otherwise keep default -1
        if beat_val >= 0 and beat_val <= 3 then
            info.beat_timebase = beat_val
        end
    end
    
   -- DIRECT CONSOLE OUTPUT (simplified)
   local peakcol_display = ""
   if info.peak_color ~= 0 then
       peakcol_display = string.format("R%d G%d B%d",
           (info.peak_color >> 16) & 0xFF,
           (info.peak_color >> 8) & 0xFF,
           info.peak_color & 0xFF)
   end
   
       -- Modify your existing console output line (add new fields at the end)
       reaper.ShowConsoleMsg(string.format(
           "%-24.24s | %-5s | %-7s | %-6s | %-5s | %-5s | %-6d | %-7s | %-5s | %-8s | %-3d | %-3d | %-12s | %-3s | %-4d | %-4s | %-4d | %-11d | %-8s\n",
           info.name,
           info.mute and "ON" or "OFF",
           info.solo_mode == 1 and "SOLO" or info.solo_mode == 2 and "SIP" or "OFF",
           string.format("%.2f", info.volume),
           string.format("%.2f", info.pan),
           string.format("%.2f", info.width),
           info.height,
           (info.color ~= 0 and string.format("#%06X", info.color) or "None"),  -- Hex color
           info.phase_inverted and "ON" or "OFF",
           info.folder_state,
           info.fx_count,
           info.items,
           info.guid ~= "" and info.guid:sub(1,8).."..."..info.guid:sub(-5) or "no-id",
           info.record_armed and "ON" or "OFF",
           info.nchan or 2,
           info.mainsend == 1 and "ON" or "OFF",
           info.automode or 0,
           info.panlawflags or 0,
           info.beat_timebase == -1 and "Project" or 
           (info.beat_timebase == 0 and "Time" or
           (info.beat_timebase == 1 and "Beats(pos)" or
           (info.beat_timebase == 2 and "Beats(len)" or
           "Beats(both)")))
       ))
  end

-- Improved UI and Output
function ShowProgress(msg)
    reaper.ShowConsoleMsg(msg.."\n")
end

function SelectRPPFile()
    local ret, file_path = reaper.GetUserFileNameForRead(
        "",
        "Select REAPER Project",
        "RPP"
    )
    if not ret then return nil end
    return file_path
end

function FormatValue(value, valueType)
    if valueType == "boolean" then
        return value and "ON" or "OFF"
    elseif valueType == "number" then
        return string.format("%.2f", value)
    elseif valueType == "solomode" then
        return value == 1 and "SOLO" or value == 2 and "SIP" or "OFF"
    else
        return tostring(value)
    end
end

function ParseAndLogTrackData(file_path)
    reaper.ClearConsole()
    
    -- Header
    reaper.ShowConsoleMsg(string.format(
        "%-24s | %-5s | %-7s | %-6s | %-5s | %-5s | %-6s | %-7s | %-5s | %-8s | %-3s | %-3s | %-12s | %-3s | %-4s | %-4s | %-4s | %-11s | %-8s\n",
        "Name", "Mute", "Solo", "Vol", "Pan", "Width", "Height", "ColorHex", "Phase", "Folder", "FX", "Items", "TRACKID", "REC", "Ch", "Send", "Auto", "PanLaw", "Timebase"
    ))
    reaper.ShowConsoleMsg(string.rep("-", 154).."\n")
    
    local project = ReadRPP(file_path)
    if not project then
        reaper.ShowConsoleMsg("ERROR: Failed to parse project file\n")
        return 
    end
    
    local tracks = project:findAllChunksByName("TRACK") or {}
    if #tracks == 0 then
        reaper.ShowConsoleMsg("No tracks found in project\n")
        return
    end
    
    -- Process tracks (output happens inside GetTrackInfo now)
    for i, track in ipairs(tracks) do
        GetTrackInfo(track)
    end
    
    reaper.ShowConsoleMsg("\nFound "..#tracks.." tracks\n")
end

-- Main execution
local retval, file_path = reaper.GetUserFileNameForRead("", "Select REAPER Project", "RPP")
if retval and file_path then
    ParseAndLogTrackData(file_path)
end


