local tinsert, tremove = table.insert, table.remove
local pairs, ipairs, type = pairs, ipairs, type

local M = {}
local listeners = {}  -- [event] = { {cb, owner, once}, ... }

local function getList(event)
    if not listeners[event] then listeners[event] = {} end
    return listeners[event]
end

--- Subscribes callback to event. Owner is used for bulk unsubscribe.
-- @param event string
-- @param callback function
-- @param owner string
function M:On(event, callback, owner)
    tinsert(getList(event), { cb = callback, owner = owner, once = false })
end

--- Subscribes callback to event, fires once then auto-removes.
-- @param event string
-- @param callback function
-- @param owner string
function M:Once(event, callback, owner)
    tinsert(getList(event), { cb = callback, owner = owner, once = true })
end

--- Unsubscribes all callbacks registered by owner for event.
-- @param event string
-- @param owner string
function M:Off(event, owner)
    local list = listeners[event]
    if not list then return end
    for i = #list, 1, -1 do
        if list[i].owner == owner then tremove(list, i) end
    end
end

--- Unsubscribes owner from all events.
-- @param owner string
function M:OffAll(owner)
    for _, list in pairs(listeners) do
        for i = #list, 1, -1 do
            if list[i].owner == owner then tremove(list, i) end
        end
    end
end

--- Fires event with optional payload arguments.
-- @param event string
function M:Emit(event, ...)
    local list = listeners[event]
    if not list then return end
    for i = #list, 1, -1 do
        local entry = list[i]
        if entry.once then tremove(list, i) end
        local ok, err = pcall(entry.cb, ...)
        if not ok then SuuUI.Debug("EventBus error [" .. event .. "]: " .. tostring(err)) end
    end
end

SuuUI.Events = M
