local pairs, assert, type, ipairs = pairs, assert, type, ipairs
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

-- Scripts a pooled frame may have picked up from its previous owner. A stale handler is
-- the dangerous half of recycling: the frame looks fresh, but its OnMouseUp still closes
-- the dropdown that released it, and the closure keeps that dropdown alive.
local SCRIPTS = {
    "OnEnter", "OnLeave", "OnMouseDown", "OnMouseUp", "OnClick",
    "OnUpdate", "OnSizeChanged", "OnShow", "OnHide",
    "OnDragStart", "OnDragStop", "OnKeyDown", "OnKeyUp", "OnValueChanged",
}

--- Strips everything the previous owner put on a frame, so the next Acquire hands back a
--- frame in its factory-fresh state rather than one carrying someone else's wiring.
local function reset(frame)
    frame:Hide()
    frame:ClearAllPoints()

    for _, script in ipairs(SCRIPTS) do
        -- Not every frame type supports every script; setting an unsupported one throws.
        if frame.HasScript and frame:HasScript(script) then
            frame:SetScript(script, nil)
        end
    end

    -- Signals are keyed by object, so a recycled frame would otherwise still deliver to
    -- listeners registered by whoever held it last.
    if SuuUI.UISignals then SuuUI.UISignals:DisconnectAll(frame) end
    -- An in-flight tween writes to the frame after release and holds a reference to it.
    if SuuUI.Anim and SuuUI.Anim.CancelAll then SuuUI.Anim:CancelAll(frame) end

    frame:SetAlpha(1)
    frame:SetScale(1)
    if frame.EnableMouse then frame:EnableMouse(false) end
    if frame.SetMovable  then frame:SetMovable(false) end
    if frame.RegisterForDrag then frame:RegisterForDrag() end
    -- Layout metadata: a leftover _layoutProps would have the next container lay the frame
    -- out with the previous owner's width/fraction/anchor.
    frame._layoutProps = nil
    frame._anchor      = nil
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
            reset(frame)
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
        reset(f)
        tinsert(pool, f)
    end
end

SuuUI.Pool = M
