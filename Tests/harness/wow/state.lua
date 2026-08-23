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

-- Per-unit data, keyed by unit token: state.units.target = { health = 40, reaction = 2 }.
-- A field absent here falls back to the flat M.unitX value below, so a spec that only cares
-- about one unit never has to name one. Set through H.setUnit / H.clearUnit rather than
-- written directly, so a typo'd field name is caught rather than silently ignored.
M.units = {}

-- In-flight spellcast, exactly as UnitCastingInfo / UnitChannelInfo report one. nil means
-- the unit is idle. Times are milliseconds, like the client's, so a spec that forgets the
-- unit conversion fails here the way it would in game.
M.cast    = nil
M.channel = nil

-- The payload CombatLogGetCurrentEventInfo() returns for the event currently being
-- dispatched, as an array. nil outside a combat log event, which is what the client does
-- too — a handler that reads it at any other time gets nothing.
M.combatLogEvent = nil

-- Combat lockdown, as InCombatLockdown() reports it. While this is true the client refuses
-- addon-driven geometry on a PROTECTED frame — and on any frame whose subtree contains one,
-- because moving the parent would move the protected child.
--
-- False by default, and deliberately so: out of combat is the state an addon does all its
-- setup work in, and it is the state every geometry spec in this suite is written against.
-- Turning lockdown on by default would fail specs about code that is correct.
M.inCombat = false

-- Every geometry call the client refused because of that lockdown, in call order.
--
-- Recorded rather than raised, because the live client does not raise either: the call
-- returns having changed nothing and the player gets "Interface action failed because of an
-- AddOn" in chat. A silent refusal is otherwise unassertable — the frame simply keeps the
-- size it had, which is exactly how the aura-band drift bug survived 2728 assertions — so
-- this record is the only observable a spec has. Read through H.getBlockedActions().
M.blockedActions = {}

-- Action bar slots, keyed by slot number: state.actions[1] = { type = "spell", id = 143 }.
--
-- An EMPTY slot is the ABSENCE of a record, not a record of zeroes, because HasAction has to
-- be able to say no -- a button reading an all-zero record would render an icon for nothing.
-- Set through H.setAction / H.clearAction so a typo'd field is caught rather than ignored.
M.actions = {}

-- Which page the main bar is on, as GetActionBarPage() reports it. Phase 0 measured 6 pages
-- of 12 slots on this client, and pages 3..6 are the same slots the other four bars own.
M.actionBarPage = 1

-- What the cursor is carrying after a PickupAction, or nil. The client's drag model moves a
-- slot's CONTENTS, which is why dropping onto an occupied slot swaps rather than overwrites.
M.pickedUpAction = nil

-- Whether the client considers the action bars locked, as the LOCK_ACTIONBAR global reports
-- it. A string "0"/"1" rather than a boolean, matching the CVar-backed global.
M.actionBarLocked = "0"

-- Key bindings, keyed by command: state.bindings.ACTIONBUTTON1 = "1". Read by GetBindingKey.
M.bindings = {}

-- Override bindings installed through SetOverrideBindingClick, in call order.
M.overrideBindings = {}

-- Secure state drivers, keyed by frame: state.stateDrivers[header].page = "[bonusbar:1] 7; 1".
--
-- RECORDED, NEVER EVALUATED. A driver string is a macro conditional, and resolving one here
-- would mean the harness guessing what the client decides -- after which a spec would be
-- asserting against the guess rather than against the client. A spec asserts the string; the
-- consequence is checked in game.
M.stateDrivers = {}

-- What the client's own secure handler did with an `action` click: which slot, which button.
-- The action-slot counterpart to targetedUnit / unitMenu.
M.usedAction = nil

-- Shapeshift / stance forms, keyed by form index: state.stanceForms[1] = { spellID = 2458 }.
--
-- CONTIGUOUS FROM 1, because GetNumShapeshiftForms answers a COUNT and every consumer loops
-- 1..count. A gap would make the count disagree with what is reachable, which the client
-- cannot express -- so H.setStanceForm refuses one rather than modelling it.
--
-- Absence of a record is the empty state, as with actions: a class with no forms (a mage) has
-- an empty table and a count of zero, which is the signal the whole bar hides on.
M.stanceForms = {}

-- What CastShapeshiftForm was asked to do, so a spec can assert the cast without the harness
-- having to decide what changing form does to the rest of the client.
M.castStance = nil

-- Pet action slots, keyed by slot index: state.petActions[1] = { name = "Attack" }.
--
-- `isToken` is the field to understand here. When it is true, `name` and `texture` are NOT a
-- display name and a texture path -- they are the NAMES OF GLOBALS holding those values, and
-- the consumer has to resolve them through _G. The harness returns them exactly as staged and
-- resolves nothing, because resolving here would hide the distinction the consumer must handle.
M.petActions = {}

-- Whether the pet has a usable action bar at all, as PetHasActionBar() reports it. DISTINCT from
-- whether a pet exists (H.setUnit("pet", ...)): a pet can be present with its bar unusable, and
-- the two drive different outcomes -- greyed icons versus a hidden bar.
M.petHasActionBar = false

-- What TogglePetAutocast was asked to do, in call order.
M.petAutocastToggles = {}

-- GetBonusBarOffset(), which is how a druid's form or a rogue's stealth shifts the paged bar.
-- Zero means no offset. Parked as a deliberate unknown in the plan until Phase 6.
M.bonusBarOffset = 0

-- CVars the addon reads, by name. Only booleans are modelled; an unset name answers false, which
-- is what the client does for one it does not know. Set through H.setCVarBool.
M.cvars = {}

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
    -- The clock tracks GetTime(); reset it so each test starts from 0. Cast bar specs
    -- use relative timing (clock at startCast), so resetting is safe.
    M.clock          = 0
    -- Wall clock for time()/date(), an instant in UTC. Reset to a fixed default so an
    -- unconfigured clock widget renders the same string in every run and on every machine:
    -- 2026-08-22 14:32:07 UTC, which reads as "14:32". See env.date in wow/api.lua.
    M.wallClock      = 1787409127
    -- Realm time, nil meaning "agrees with the wall clock". Reset because a spec that stages
    -- a divergent realm clock would otherwise leave every later clock assertion reading it.
    M.realmHour      = nil
    M.realmMinute    = nil
    -- Performance readings for GetFramerate / GetNetStats. Reset so a spec staging a bad
    -- framerate or a laggy connection cannot leave the next file's readout in its warning
    -- state and pass for the wrong reason. netLatencyWorld = false models the older
    -- three-return GetNetStats; nil means the four-return shape reporting 0.
    M.framerate        = 60
    M.netDown          = 0
    M.netUp            = 0
    M.netLatencyHome   = 0
    M.netLatencyWorld  = nil
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
    -- Same reasoning one unit wider. A leaked units.target would leave the next spec file
    -- believing a target is selected, and a "no target" assertion that passes because
    -- nothing staged one is exactly the kind that stops passing for the right reason.
    --
    -- Note this cannot be staged before boot the way the flat family can, because reset
    -- runs first. Nothing needs it to be: a unit frame is built whether or not its unit is
    -- there, which is what lets it appear the moment one is.
    M.units          = {}
    -- What the client's own secure handler did on the last click: which unit it targeted,
    -- and which unit's context menu it opened. Reset because a leaked menu record makes
    -- the next spec's right-click assertion pass before the click happens.
    M.targetedUnit   = nil
    M.unitMenu       = nil
    -- Per-unit aura lists, keyed by unit token. Each entry is a table with "helpful" and
    -- "harmful" arrays. Set through H.setAuras / H.clearAuras.
    M.auras          = {}
    -- GameTooltip state: last owner/anchor/aura pointed at, so specs can assert
    -- what a mouseover produced.
    M.tooltip        = nil
    -- CancelUnitBuff call log, so specs can assert it fired with the right args.
    M.cancelBuff     = nil
    -- Combat lockdown and the refusals it produced. Both cleared, for the same reason the
    -- unit table is: a leaked inCombat would leave the next spec file's frames silently
    -- unresizable, so its geometry assertions would fail somewhere far from the cause — and
    -- a leaked refusal record would let a "the resize was blocked" assertion pass before the
    -- call under test ever happened. A reset() that forgot a field is a bug this harness has
    -- already shipped once.
    M.inCombat       = false
    M.blockedActions = {}
    -- Action slots and everything keyed off them. Cleared for the reason every other store
    -- here is: a leaked slot would let a "the button drew an icon" assertion pass before the
    -- spec staged anything, and a leaked page would put bar 1 on someone else's slots. The
    -- cursor is cleared too -- a spec that picks an action up and never drops it would
    -- otherwise hand the next file a loaded cursor, and its first PlaceAction would appear
    -- to work for the wrong reason.
    M.actions         = {}
    M.actionBarPage   = 1
    M.pickedUpAction  = nil
    M.actionBarLocked = "0"
    M.bindings         = {}
    M.overrideBindings = {}
    -- Frame-keyed, so this also drops the only reference the harness holds to a torn-down
    -- secure header.
    M.stateDrivers    = {}
    M.usedAction      = nil
    -- Cleared for the same reason as the action slots: a leaked stance form would give the next
    -- spec's bar a button count it never staged, and a leaked pet bar would make a class that has
    -- no pet render one. A count of zero and an absent pet are the states these must reset TO,
    -- because they are what the bars are supposed to hide on.
    M.stanceForms        = {}
    M.castStance         = nil
    M.petActions         = {}
    M.petHasActionBar    = false
    M.petAutocastToggles = {}
    M.bonusBarOffset     = 0
    -- Cleared for the usual reason: a leaked ActionButtonUseKeyDown would put every later spec's
    -- buttons on the press path, and their click assertions would fail somewhere far from here.
    M.cvars           = {}
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
