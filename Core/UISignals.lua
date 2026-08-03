local pairs, type = pairs, type

local M = {}

--- Signal registry per object
-- Structure: { [object] = { [signal] = { [id] = callback } } }
local registry = {}
setmetatable(registry, { __mode = "k" })  -- weak keys so objects can be GC'd

--- Standard UI signals that all components can emit
M.SIGNALS = {
    -- Layout signals
    SIZE_CHANGED       = "size_changed",        -- Emitted when element size changes. Args: width, height
    POSITION_CHANGED   = "position_changed",    -- Emitted when element position changes. Args: x, y
    VISIBILITY_CHANGED = "visibility_changed",  -- Emitted when element shown/hidden. Args: isVisible
    
    -- Interaction signals
    MOUSE_ENTER        = "mouse_enter",         -- Emitted when mouse enters element. Args: none
    MOUSE_LEAVE        = "mouse_leave",         -- Emitted when mouse leaves element. Args: none
    CLICKED            = "clicked",             -- Emitted when element clicked. Args: button
    
    -- Value signals
    VALUE_CHANGED      = "value_changed",       -- Emitted when element value changes. Args: newValue, oldValue
    TEXT_CHANGED       = "text_changed",        -- Emitted when text input changes. Args: newText
    
    -- Scroll signals
    SCROLL_CHANGED     = "scroll_changed",      -- Emitted when scroll position changes. Args: scrollY
    CONTENT_RESIZED    = "content_resized",     -- Emitted when scrollable content size changes. Args: contentHeight
    
    -- State signals
    ENABLED_CHANGED    = "enabled_changed",     -- Emitted when enabled state changes. Args: isEnabled
    FOCUSED            = "focused",             -- Emitted when element gains focus. Args: none
    UNFOCUSED          = "unfocused",           -- Emitted when element loses focus. Args: none
}

local nextId = 1

--- Connects a callback to a signal on an object.
-- @param obj table  The object (component handle or frame) emitting the signal
-- @param signal string  Signal name (use M.SIGNALS constants)
-- @param callback function  Function to call when signal emits
-- @return string  Connection ID for disconnecting later
function M:Connect(obj, signal, callback)
    assert(obj, "SuuUI.UISignals: obj required")
    assert(type(signal) == "string", "SuuUI.UISignals: signal must be string")
    assert(type(callback) == "function", "SuuUI.UISignals: callback must be function")
    
    if not registry[obj] then
        registry[obj] = {}
    end
    if not registry[obj][signal] then
        registry[obj][signal] = {}
    end
    
    local id = "sig_" .. nextId
    nextId = nextId + 1
    
    registry[obj][signal][id] = callback
    return id
end

--- Disconnects a specific callback from a signal.
-- @param obj table  The object
-- @param signal string  Signal name
-- @param connectionId string  The ID returned from Connect
function M:Disconnect(obj, signal, connectionId)
    if not registry[obj] or not registry[obj][signal] then return end
    registry[obj][signal][connectionId] = nil
end

--- Disconnects all callbacks for a signal on an object.
-- @param obj table  The object
-- @param signal string  Signal name
function M:DisconnectAll(obj, signal)
    if not registry[obj] then return end
    if signal then
        registry[obj][signal] = nil
    else
        registry[obj] = nil
    end
end

--- Emits a signal from an object, calling all connected callbacks.
-- @param obj table  The object emitting the signal
-- @param signal string  Signal name
-- @param ...  Arguments to pass to callbacks
function M:Emit(obj, signal, ...)
    if not registry[obj] or not registry[obj][signal] then return end
    
    -- Call all connected callbacks
    for _, callback in pairs(registry[obj][signal]) do
        local ok, err = pcall(callback, ...)
        if not ok then
            SuuUI.Debug("UISignals: Error in " .. signal .. " callback: " .. tostring(err))
        end
    end
end

--- Checks if an object has any connections for a signal.
-- @param obj table  The object
-- @param signal string  Signal name
-- @return bool
function M:HasConnections(obj, signal)
    if not registry[obj] or not registry[obj][signal] then return false end
    for _ in pairs(registry[obj][signal]) do
        return true
    end
    return false
end

SuuUI.UISignals = M
