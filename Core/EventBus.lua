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
-- Entries are flagged dead before removal so an Emit already in flight skips them: a
-- listener that unsubscribes a sibling must not still see that sibling called.
-- @param event string
-- @param owner string
function M:Off(event, owner)
    local list = listeners[event]
    if not list then return end
    for i = #list, 1, -1 do
        if list[i].owner == owner then
            list[i]._dead = true
            tremove(list, i)
        end
    end
end

--- Unsubscribes owner from all events.
-- @param owner string
function M:OffAll(owner)
    for _, list in pairs(listeners) do
        for i = #list, 1, -1 do
            if list[i].owner == owner then
                list[i]._dead = true
                tremove(list, i)
            end
        end
    end
end

--- Fires event with optional payload arguments.
--
-- Dispatch runs over a snapshot. Callbacks routinely unsubscribe during their own event —
-- a control tearing itself down, a page rebuild dropping the previous page's listeners —
-- and mutating the live list under the cursor silently double-fires whatever slid into the
-- vacated index, or skips it. The snapshot plus the dead flag makes the set of callbacks
-- for one emit fixed at the moment it starts, minus anything removed since.
-- @param event string
function M:Emit(event, ...)
    local list = listeners[event]
    if not list then return end

    local n = #list
    if n == 0 then return end
    local snapshot = {}
    for i = 1, n do snapshot[i] = list[i] end

    local firedOnce = false
    for i = 1, n do
        local entry = snapshot[i]
        if not entry._dead then
            if entry.once then
                entry._dead = true
                firedOnce = true
            end
            local ok, err = pcall(entry.cb, ...)
            if not ok then SuuUI.Debug("EventBus error [" .. event .. "]: " .. tostring(err)) end
        end
    end

    -- Compact once, after dispatch, rather than removing under the cursor.
    if firedOnce then
        for i = #list, 1, -1 do
            if list[i]._dead then tremove(list, i) end
        end
    end
end

SuuUI.Events = M
