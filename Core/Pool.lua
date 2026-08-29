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

--- The FRAME behind a pooled entry, which may be a component handle rather than a raw frame.
---
--- A factory is free to return a component handle -- `chat.log` does, and pooling was the whole
--- reason that factory exists -- but a handle deliberately exposes no `ClearAllPoints`, `HasScript`
--- or `SetScale`, so every reset call below would raise on one. That never surfaced because the only
--- handle-returning pool in the addon was acquired and NEVER released, so the recycle path had never
--- run; the first release raised `attempt to call a nil value (method 'ClearAllPoints')`.
---
--- Additive on purpose: a raw frame has no GetFrame, so every existing caller is untouched.
local function frameOf(f)
    if type(f) == "table" and type(f.GetFrame) == "function" then
        local inner = f:GetFrame()
        if inner then return inner end
    end
    return f
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
        -- Through the frame: a handle has no SetParent, and re-parenting is what makes a recycled
        -- entry belong to its new owner.
        frameOf(f):SetParent(parent)
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
local function reset(entry)
    local frame = frameOf(entry)
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
    --
    -- Deliberately the FRAME, not a handle entry. A component factory wires its own signals ONCE per
    -- physical instance -- `chat.log` connects HYPERLINK_CLICK in the factory precisely so a recycled
    -- log cannot accumulate a second connection -- and purging the handle here would strip that
    -- wiring on release, so a reissued log would silently stop responding to link clicks. The
    -- consequence for callers: connect to a POOLED handle in its factory, not after Acquire, because
    -- a per-acquire connection is not cleaned up here and would accumulate.
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
