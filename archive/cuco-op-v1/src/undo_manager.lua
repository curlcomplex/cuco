-- CUCO-OP Undo/Redo Management System
-- Handles undo/redo functionality for main editor and script preview

local undo_manager = {}

-- Configuration
local MAX_HISTORY_SIZE = 50

-- Create new undo stack
function undo_manager.create_stack()
    return {
        history = {},
        index = 0,  -- 0 means no history, 1+ points to current state
        max_size = MAX_HISTORY_SIZE
    }
end

-- Add state to undo stack
function undo_manager.push_state(stack, content, description)
    description = description or "Edit"
    
    -- Don't add duplicate states
    if stack.index > 0 and stack.history[stack.index].content == content then
        return
    end
    
    -- Remove any history after current index (when undoing then making new changes)
    while #stack.history > stack.index do
        table.remove(stack.history)
    end
    
    -- Add new state
    local state = {
        content = content,
        description = description,
        timestamp = os.time()
    }
    
    table.insert(stack.history, state)
    stack.index = #stack.history
    
    -- Trim history if too large
    if #stack.history > stack.max_size then
        table.remove(stack.history, 1)
        stack.index = #stack.history
    end
end

-- Undo operation
function undo_manager.undo(stack)
    if stack.index <= 1 then
        return nil, "Nothing to undo"
    end
    
    stack.index = stack.index - 1
    return stack.history[stack.index].content, nil
end

-- Redo operation
function undo_manager.redo(stack)
    if stack.index >= #stack.history then
        return nil, "Nothing to redo"
    end
    
    stack.index = stack.index + 1
    return stack.history[stack.index].content, nil
end

-- Get current state info
function undo_manager.get_state_info(stack)
    return {
        current_index = stack.index,
        total_states = #stack.history,
        can_undo = stack.index > 1,
        can_redo = stack.index < #stack.history,
        current_description = stack.index > 0 and stack.history[stack.index].description or "Initial"
    }
end

-- Clear history
function undo_manager.clear_stack(stack)
    stack.history = {}
    stack.index = 0
end

-- Get history summary for display
function undo_manager.get_history_summary(stack, max_items)
    max_items = max_items or 10
    local summary = {}
    
    local start_idx = math.max(1, stack.index - max_items + 1)
    local end_idx = math.min(#stack.history, stack.index + max_items)
    
    for i = start_idx, end_idx do
        local state = stack.history[i]
        local is_current = (i == stack.index)
        table.insert(summary, {
            index = i,
            description = state.description,
            timestamp = state.timestamp,
            is_current = is_current
        })
    end
    
    return summary
end

return undo_manager