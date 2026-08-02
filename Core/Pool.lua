local pairs, assert, type = pairs, assert, type
local tinsert, tremove = table.insert, table.remove

local M = {}
local factories = {}   -- [typeId] = createFn
local inactive  = {}   -- [typeId] = { frame, ... }
local active    = {}   -- [typeId] = { frame, ... }

--- Registers a factory function for a pool type.
-- @param typeId string  Unique type identifier (prefix with pluginId)
-- @param createFn function  Called with (parent) when pool is empty
function M:Register(typeId, createFn)
    assert(type(typeId) == "string", "SuuUI Pool: typeId must be string")
    assert(type(createFn) == "function", "SuuUI Pool: createFn must be function")
    factories[typeId] = createFn
    if not inactive[typeId] then inactive[typeId] = {} end
    if not active[typeId]   then active[typeId]   = {} end
end

--- Acquires a frame from the pool, creating one if needed.
-- @param typeId string
-- @param parent frame  WoW frame to parent to
-- @return frame
function M:Acquire(typeId, parent)
    assert(factories[typeId], "SuuUI Pool: unregistered typeId: " .. tostring(typeId))
    local pool = inactive[typeId]
    local f
    if #pool > 0 then
        f = tremove(pool)
        f:SetParent(parent)
    else
        f = factories[typeId](parent)
    end
    f:Show()
    tinsert(active[typeId], f)
    return f
end

--- Returns a frame to the pool.
-- @param typeId string
-- @param frame frame
function M:Release(typeId, frame)
    local act = active[typeId]
    if not act then return end
    for i = #act, 1, -1 do
        if act[i] == frame then
            tremove(act, i)
            frame:Hide()
            frame:ClearAllPoints()
            tinsert(inactive[typeId], frame)
            return
        end
    end
end

--- Returns all active frames of typeId to the pool.
-- @param typeId string
function M:ReleaseAll(typeId)
    local act = active[typeId]
    if not act then return end
    local pool = inactive[typeId]
    for i = #act, 1, -1 do
        local f = tremove(act, i)
        f:Hide()
        f:ClearAllPoints()
        tinsert(pool, f)
    end
end

SuuUI.Pool = M
