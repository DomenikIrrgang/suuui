-- Shared mutable state for the simulated client: widget registry, the resize settle
-- pass, the frame ticker, cursor and keyboard focus.
local geometry = require("harness.wow.geometry")

local M = {}

M.screenWidth  = 1024
M.screenHeight = 768
M.uiScale      = 1

-- Physical pixels of the drawing area, which is a different thing from the unit-space
-- screen size above: GetScreenHeight() is always 768 units, while a 1080p monitor draws
-- those 768 units across 1080 pixels. Pixel snapping depends on the ratio, so the
-- simulated client has to model both. Defaults match unit space, giving a 1:1 grid.
M.physicalWidth  = 1024
M.physicalHeight = 768

M.widgets   = {}   -- every widget, creation order
M.frames    = {}   -- frames only (things that can hold scripts)
M.cursorX   = 0    -- raw cursor coords, as GetCursorPosition() reports them
M.cursorY   = 0
M.mouseDown = {}   -- [buttonName] = true
M.focused   = nil  -- focused EditBox
M.debugLog  = {}

-- In-flight spellcast, exactly as UnitCastingInfo / UnitChannelInfo report one. nil means
-- the unit is idle. Times are milliseconds, like the client's, so a spec that forgets the
-- unit conversion fails here the way it would in game.
M.cast    = nil
M.channel = nil

-- The payload CombatLogGetCurrentEventInfo() returns for the event currently being
-- dispatched, as an array. nil outside a combat log event, which is what the client does
-- too — a handler that reads it at any other time gets nothing.
M.combatLogEvent = nil

local pending, pendingSet
local dependents

--- Clears all widgets and input state. Called when the harness reloads the addon.
function M.reset()
    -- The solver converts between screen space and region units, so it needs the client
    -- UI scale. It cannot require this file back, so push the value across.
    geometry.uiScale = M.uiScale
    M.widgets   = {}
    M.frames    = {}
    M.cursorX   = 0
    M.cursorY   = 0
    M.mouseDown = {}
    M.focused   = nil
    M.debugLog  = {}
    M.cast      = nil
    M.channel   = nil
    M.combatLogEvent = nil
    -- The unit's class, read by UnitClass. Reset because a spec that paints an NPC sets
    -- unitClassless and a spec that paints a mage sets unitClass, and neither is a value
    -- the next spec file should inherit: a leaked unitClassless makes every class-colour
    -- assertion downstream fall through to its fallback and pass for the wrong reason.
    --
    -- The unitHealth / unitLevel / unitPowerType family is deliberately NOT reset here.
    -- Those are set BEFORE the client is built (see Tests/spec/35_attach_login_spec.lua,
    -- which seeds them and then boots), so clearing them during reset would wipe the very
    -- values the spec just staged.
    M.unitClass      = nil
    M.unitClassless  = nil
    M._settling = false
    M.settleIterations = 0
    pending    = {}
    pendingSet = setmetatable({}, { __mode = "k" })
    dependents = setmetatable({}, { __mode = "k" })
    geometry.invalidate()
end

--- Registers a newly created widget.
-- @param w table
function M.track(w)
    M.widgets[#M.widgets + 1] = w
    if w._canScript then M.frames[#M.frames + 1] = w end
end

--- Records that `widget` is anchored against `target`, so moving the target can
--- re-resolve the widget even though it is not a descendant. A dropdown panel hanging
--- off its button is the case that needs this.
-- @param target table
-- @param widget table
function M.addDependent(target, widget)
    if not target or target == widget then return end
    local set = dependents[target]
    if not set then
        set = setmetatable({}, { __mode = "k" })
        dependents[target] = set
    end
    set[widget] = true
end

--- Queues a widget for the settle pass.
-- @param w table
function M.markDirty(w)
    if not w or pendingSet[w] then return end
    pendingSet[w] = true
    pending[#pending + 1] = w
end

--- Marks geometry dirty and runs the resize settle pass.
--
-- WoW notifies OnSizeChanged whenever a widget's resolved size changes, including when
-- the change comes from an ancestor resizing or an anchor moving. Walking only the
-- affected subtrees reproduces that without rescanning every frame on every mutation.
-- @param w table  The widget whose geometry changed
function M.invalidate(w)
    geometry.invalidate()
    M.markDirty(w)
    M.settle()
end

local MAX_PASSES = 400

-- Visits a widget and everything whose geometry can follow from it: its own children
-- and regions, plus anything anchored against it.
local function visit(root, seen)
    local stack, top = { root }, 1
    while top > 0 do
        local w = stack[top]
        top = top - 1

        if w and not seen[w] and not w._destroyed then
            seen[w] = true

            if w._canScript then
                local width  = geometry.width(w)
                local height = geometry.height(w)
                if w._notifiedW == nil
                   or math.abs(w._notifiedW - width) > 0.01
                   or math.abs((w._notifiedH or -1) - height) > 0.01 then
                    w._notifiedW, w._notifiedH = width, height
                    local script = w._scripts and w._scripts.OnSizeChanged
                    if script then script(w, width, height) end
                end
            end

            for _, child in ipairs(w._childFrames) do top = top + 1 stack[top] = child end
            for _, region in ipairs(w._regions) do top = top + 1 stack[top] = region end
            local deps = dependents[w]
            if deps then
                for dep in pairs(deps) do top = top + 1 stack[top] = dep end
            end
        end
    end
end

--- Fires OnSizeChanged for every affected widget, looping until sizes stop moving.
function M.settle()
    if M._settling then return end
    M._settling = true

    local passes = 0
    while #pending > 0 do
        passes = passes + 1
        if passes > MAX_PASSES then
            M._settling = false
            pending, pendingSet = {}, setmetatable({}, { __mode = "k" })
            error("SuuUI harness: layout did not stabilise after " .. MAX_PASSES ..
                  " passes (probable resize feedback loop)", 0)
        end

        local batch = pending
        pending    = {}
        pendingSet = setmetatable({}, { __mode = "k" })

        -- One shared seen set per batch: a widget reached twice in the same batch has
        -- already been re-measured against the current geometry generation.
        local seen = {}
        for i = 1, #batch do visit(batch[i], seen) end
    end

    M.settleIterations = passes
    M._settling = false
end

--- Runs one simulated frame: calls OnUpdate on every visible frame that has one.
-- @param dt number  Elapsed seconds
function M.tick(dt)
    local list, n = {}, #M.frames
    for i = 1, n do list[i] = M.frames[i] end
    for i = 1, n do
        local f = list[i]
        if not f._destroyed and f._scripts and f._scripts.OnUpdate and f:IsVisible() then
            f._scripts.OnUpdate(f, dt)
        end
    end
end

M._settling = false
M.settleIterations = 0
pending    = {}
pendingSet = setmetatable({}, { __mode = "k" })
dependents = setmetatable({}, { __mode = "k" })

return M
