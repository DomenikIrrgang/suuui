-- Public harness API used by spec files.
--
-- Run:  lua Tests/run.lua                      (from the addon root)
--       lua Tests/run.lua --filter Button
--       lua Tests/run.lua Tests/spec/11_button_spec.lua -v
--
-- A spec file looks like this:
--
--   local H = require("harness")
--
--   describe("Components.Thing", function()
--       local host
--       before_each(function()
--           H.setup()                 -- fresh addon in a fresh simulated client
--           host = H.parent(300, 200)  -- a parent frame with real geometry
--           host = H.backdropParent(300, 200)  -- ... that can also take a backdrop
--       end)
--
--       it("hugs its label", function()
--           local thing = H.C.Thing({ label = "Go" }, host)
--           H.expectSize(thing, H.textWidth("Go", H.token("fontSizeMd")) + 18, nil)
--       end)
--
--       it("centres its label", function()
--           local thing = H.mount(H.C.Thing({ label = "Go" }, host))
--           H.expectCenteredH(thing._label, thing:GetFrame())
--       end)
--   end)
--
-- Two rules make component geometry assertions work:
--
--   * Components never position themselves; a container does. A component built for a
--     test and never added to one has no anchors, so every position inside it is
--     unresolvable. Either add it to a container or call H.mount(handle).
--   * Derive expected pixel values from tokens and H.textWidth/H.lineHeight rather than
--     hardcoding them, so the assertion survives a theme change.
--
-- Assertions:  expect(v).eq/.near/.gt/.gte/.lt/.lte/.between/.deepEq/.truthy/.falsy
--              .isNil/.notNil/.matches/.contains/.len/.throws/.notThrows, and .as("note")
-- Geometry:    H.box H.offset H.expectBox H.expectSize H.expectOffset H.expectInside
--              H.expectNoOverlap H.expectStackedVertically H.expectRowHorizontally
--              H.expectCenteredH H.expectCenteredV H.expectTokenColor H.expectDrawsAbove
-- Clipping:    H.clipsChildren H.clipAncestor H.visibleBox H.isClipped
--              (H.box reports the rect a widget was ASSIGNED; H.visibleBox what draws)
-- Colour:      H.backdropColor H.borderColor H.vertexColor H.textColor
-- Text:        H.textWidth H.textBox H.textHeight H.lineHeight H.fontOf H.expectTextNotClipped
--              (each measuring helper takes an optional font path: faces differ)
-- Input:       H.click H.forceClick H.mouseDown H.mouseUp H.hover H.unhover H.scroll
--              H.dragResize H.key H.typeText H.pressEnter H.pressEscape H.cursor
--              H.cursorOn H.setMouseDown H.mods
-- Units:       H.setUnit H.clearUnit H.setTarget
-- Combat:      H.setCombat H.inCombat H.getBlockedActions H.resetBlockedActions
--              H.hasProtectedDescendant
-- Auras:       H.setAuras H.clearAuras H.getCancelBuff H.resetCancelBuff
--              H.getTooltipState H.resetTooltipState
-- Spellcasts:  H.startCast H.startChannel H.stopCast H.finishCast H.interruptCast
--              H.failCast H.stopChannel H.delayCast H.updateChannel H.combatLogInterrupt
--              H.combatLogSpell
-- Observation: H.signalSpy H.eventSpy H.debugLog H.tick H.runAnimations
-- Client:      H.setGradientSupported  (take the gradient API away, to reach a fallback)
-- Actions:     H.setAction H.clearAction H.setActionBarPage H.setActionBarLocked
--              H.getPickedUpAction H.getUsedAction H.resetUsedAction
-- Bindings:    H.setBinding H.getOverrideBindings H.getStateDriver
--              H.setTempShapeshiftPage  (the page a temporary shapeshift uses)
-- Stance:      H.setStanceForm H.popStanceForm H.clearStanceForms H.getCastStance
--              H.setSpellTexture
-- Watch bars:  H.setXP H.setWatchedFaction H.setRepApi
-- Bags:        H.setBags H.setBagApi H.setBagItem H.clearBagItem H.setBankOpen
--              H.setMerchantOpen H.getCursorItem H.getUsedContainerItems
--              H.resetUsedContainerItems
-- Pet:         H.setPetAction H.clearPetAction H.setPetActionBar H.getPetAutocastToggles
--              H.setBonusBarOffset H.getUsedPetAction
--
-- H.setup() reloads the whole addon into a fresh sandbox against a fresh simulated
-- client, so every test starts from a known state.
local geometry = require("harness.wow.geometry")
local state    = require("harness.wow.state")
local font     = require("harness.wow.font")
local regions  = require("harness.wow.regions")
local widget   = require("harness.wow.widget")
local addon    = require("harness.addon")

local M = {}

M.geometry = geometry
M.state    = state
M.font     = font

M.root = "."

----------------------------------------------------------------------------------
-- Lifecycle
----------------------------------------------------------------------------------

--- Loads a fresh addon instance. Returns the SuuUI namespace.
-- screenWidth/Height are unit space (always 768 tall in the real client);
-- physicalWidth/Height are pixels and drive the pixel grid. They default to unit space,
-- which gives mult == 1 and integer snapping. Pass physicalHeight = 1080 to exercise a
-- fractional grid.
--
-- Status bar fill transitions default to "instant" for the same reason: a value written
-- under the shipped "smooth" default arrives over several frames, so a spec asserting a
-- fill width straight after SetValue would be measuring a value still in transit. The
-- simple configuration by default, the real one where the spec is about it — pass
-- barTransitions = true for that.
-- @param opts table  { boot = true, debug = false, screenWidth, screenHeight,
--                      physicalWidth, physicalHeight, uiScale, barTransitions,
--                      castBarGlobals }
-- @return table  SuuUI
function M.setup(opts)
    opts = opts or {}
    state.screenWidth  = opts.screenWidth  or 1024
    state.screenHeight = opts.screenHeight or 768
    state.uiScale      = opts.uiScale or 1
    state.physicalWidth  = opts.physicalWidth  or state.screenWidth
    state.physicalHeight = opts.physicalHeight or state.screenHeight
    -- Which player-cast-bar globals this client admits to having. nil means both
    -- generations, which is the default the CastBars plugin has to cope with. Assigned on
    -- every setup so a spec that narrows it cannot leak into the next one.
    state.castBarGlobals = opts.castBarGlobals

    local loaded = addon.load({ root = M.root, boot = opts.boot, debug = opts.debug })
    M.env      = loaded.env
    M.SuuUI    = loaded.SuuUI
    M.wow      = loaded.wow
    M.UIParent = loaded.wow.UIParent
    M.Minimap  = loaded.wow.Minimap
    M.GameTooltip = loaded.wow.GameTooltip
    M.C        = loaded.SuuUI.Components
    M.S        = loaded.SuuUI.UISignals
    M.T        = loaded.SuuUI.Theme
    M.Layout   = loaded.SuuUI.Layout
    if not opts.barTransitions then
        M.SuuUI.Anim.Transitions:SetDefault("instant")
    end
    return M.SuuUI
end

--- Fires a WoW event to every frame registered for it.
function M.fireEvent(event, ...)
    return M.wow.fireEvent(event, ...)
end

--- Returns a themed token value.
-- @param key string
function M.token(key) return M.T:GetToken(key) end

--- Returns the token-derived height for a text-bearing control.
function M.controlHeight(sizeKey, fontKey) return M.T:GetControlHeight(sizeKey, fontKey) end

--- Creates a plain parent frame with real geometry, anchored to the screen top-left.
-- @param w number
-- @param h number
-- @return frame
function M.parent(w, h)
    local f = M.env.CreateFrame("Frame", nil, M.UIParent)
    f:SetSize(w or 400, h or 300)
    f:SetPoint("TOPLEFT", M.UIParent, "TOPLEFT", 0, 0)
    return f
end

--- A test parent that can actually take a backdrop.
-- The client only puts SetBackdrop on a frame created from BackdropTemplate, and the
-- simulated client enforces that, so a spec calling SuuUI.Backdrop.Apply on a plain
-- M.parent() is asserting something the client would refuse. Use this instead.
-- @param w number|nil
-- @param h number|nil
-- @return table  frame
function M.backdropParent(w, h)
    local f = M.env.CreateFrame("Frame", nil, M.UIParent, "BackdropTemplate")
    f:SetSize(w or 400, h or 300)
    f:SetPoint("TOPLEFT", M.UIParent, "TOPLEFT", 0, 0)
    return f
end

--- Unwraps a component handle or container to its frame. Passes frames through.
-- @param target table
-- @return table
function M.frameOf(target)
    if type(target) == "table" and target.GetFrame then return target:GetFrame() end
    return target
end

--- Anchors a component inside its parent so its geometry resolves.
--
-- Components never position themselves: in real code a container does it. A component
-- built for a test and never added to a container therefore has no anchors, and every
-- position inside it is unresolvable. Mounting it through an anchor container is what
-- the addon does, so the resulting geometry is the real thing.
-- @param target table   Component handle, container, or frame
-- @param opts table     { x, y, parent, width, height }
-- @return table  The target, for chaining
function M.mount(target, opts)
    opts = opts or {}
    local f = M.frameOf(target)
    local parent = opts.parent and M.frameOf(opts.parent) or f:GetParent()
    assert(parent, "harness: mount needs a parent frame")

    local box = M.Layout:CreateContainer({ host = parent, layout = "anchor" })
    box:Add(f, { anchor = {
        point = "TOPLEFT", relativePoint = "TOPLEFT",
        x = opts.x or 0, y = opts.y or 0,
        width = opts.width, height = opts.height,
    } })
    return target
end

----------------------------------------------------------------------------------
-- Simulated frame loop
----------------------------------------------------------------------------------

--- Runs one simulated frame.
-- @param dt number  Seconds (default 1/60)
function M.tick(dt)
    state.clock = (state.clock or 0) + (dt or 1 / 60)
    state.tick(dt or 1 / 60)
end

--- Advances far enough for every queued animation, including chained sequences, to
--- finish. Sequences enqueue their next step during a tick, so several passes run.
-- @param passes number  Default 8
function M.runAnimations(passes)
    for _ = 1, passes or 8 do M.tick(10) end
end

----------------------------------------------------------------------------------
-- Units
--
-- The client answers every Unit* question per unit token. The harness models that with a
-- per-unit override table over the flat state.unitX values, so a spec about one unit says
-- nothing about units, and a spec about two says exactly which is which.
----------------------------------------------------------------------------------

-- Every per-unit field the simulated client reads. Listed so a typo is an error rather
-- than a field the client silently never looks at — which would leave a spec asserting
-- against the flat fallback and passing for the wrong reason.
local UNIT_FIELDS = {
    exists = true, name = true, level = true, reaction = true,
    class = true, classless = true, isPlayer = true,
    health = true, healthMax = true,
    power = true, powerMax = true, powerType = true,
    -- What UnitGroupRolesAssigned answers. The client's own strings are "TANK" / "HEALER" /
    -- "DAMAGER" / "NONE" -- measured in game, and NOT "DPS", which is what a consumer that
    -- guessed would print verbatim. Unstaged units read "NONE".
    role = true,
    -- What GetGuildInfo answers: name, rank name, rank index. Three fields rather than one,
    -- because a guild with no rank staged is a real state -- the client returns the name and
    -- leaves the rank nil for a unit it has not fully resolved.
    guild = true, guildRank = true, guildRankIndex = true,
}

--- Stages a unit: makes UnitExists true for it and sets whatever fields are given.
--
-- Merges into whatever the unit already had, so a spec can stage a target once and then
-- move its health alone. Fields omitted fall back to the flat state.unitX values, which is
-- what keeps `H.setUnit("target", { reaction = 2 })` a complete statement of "a hostile
-- something is targeted".
-- @param unit string   Unit token, e.g. "target"
-- @param props table|nil  { exists, name, level, reaction, class, classless, isPlayer,
--                           health, healthMax, power, powerMax, powerType }
-- @return table  The unit's stored record
function M.setUnit(unit, props)
    assert(type(unit) == "string" and unit ~= "", "H.setUnit: unit token required")
    local u = state.units[unit]
    if not u then
        u = {}
        state.units[unit] = u
    end
    for k, v in pairs(props or {}) do
        assert(UNIT_FIELDS[k], "H.setUnit: unknown unit field '" .. tostring(k) .. "'")
        u[k] = v
    end
    return u
end

--- Moves the wall clock that time() and date() report, as a UTC instant.
--
-- Accepts an epoch number, or a table of UTC parts for readability. Deliberately UTC: the
-- harness formats dates in UTC so an assertion about what a clock widget SAYS holds on every
-- machine, which delegating to the local timezone would not.
--
-- This is not GetTime(). GetTime is uptime and starts at 0 (H.tick moves it); this is the
-- epoch, and nothing about advancing one moves the other.
-- @param when number|table  Epoch seconds, or { year, month, day, hour, min, sec } in UTC
-- @return number  The epoch value now in force
function M.setClock(when)
    if type(when) == "table" then
        local days = 0
        -- Days since the epoch, computed rather than taken from os.time, which interprets a
        -- table in the machine's local timezone and would reintroduce the dependency this
        -- helper exists to remove.
        local y = when.year or 1970
        for yy = 1970, y - 1 do
            days = days + ((yy % 4 == 0 and (yy % 100 ~= 0 or yy % 400 == 0)) and 366 or 365)
        end
        local leap = (y % 4 == 0 and (y % 100 ~= 0 or y % 400 == 0))
        local mdays = { 31, leap and 29 or 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31 }
        for mm = 1, (when.month or 1) - 1 do days = days + mdays[mm] end
        days = days + ((when.day or 1) - 1)
        state.wallClock = days * 86400 + (when.hour or 0) * 3600
            + (when.min or 0) * 60 + (when.sec or 0)
    else
        state.wallClock = tonumber(when) or 0
    end
    return state.wallClock
end

--- Sets the realm clock GetGameTime() reports, or clears it back to matching the wall clock.
-- @param hour number|nil
-- @param minute number|nil
function M.setRealmTime(hour, minute)
    state.realmHour   = hour
    state.realmMinute = minute
end

--- Sets what GetFramerate() reports.
-- @param fps number
function M.setFramerate(fps)
    state.framerate = fps
end

--- Sets what GetNetStats() reports.
--
-- Pass `world = false` to model the OLDER three-return client, which reports a single latency
-- in the third slot and nothing in the fourth. That is the shape a reader has to survive, and
-- it cannot be reproduced by passing 0 — a present-but-zero value is a different fact from an
-- absent one.
-- @param down number|nil   Bandwidth in
-- @param up number|nil     Bandwidth out
-- @param home number|nil   Home latency, ms
-- @param world number|false|nil  World latency, ms; false to omit the fourth return entirely
function M.setNetStats(down, up, home, world)
    state.netDown         = down
    state.netUp           = up
    state.netLatencyHome  = home
    state.netLatencyWorld = world
end

--- Removes a unit, so UnitExists reports false for it again — losing a target.
--
-- Deliberately does NOT fire PLAYER_TARGET_CHANGED: the state and the announcement are
-- separate in the client too, and a spec that wants both calls H.setTarget.
-- @param unit string
function M.clearUnit(unit)
    state.units[unit] = nil
end

--- Selects or clears the target, announcing it the way the client does.
--
-- Pass a props table to acquire a target, or nil to lose one. Either way
-- PLAYER_TARGET_CHANGED fires afterwards, because the state moving without the event is a
-- situation the client never produces — and a frame that only reads on the event would
-- look correct in a spec that skipped it.
-- @param props table|nil  Same shape as setUnit's props
-- @return table|nil  The target's record, or nil when cleared
function M.setTarget(props)
    local u = nil
    if props == nil then
        M.clearUnit("target")
    else
        u = M.setUnit("target", props)
    end
    M.fireEvent("PLAYER_TARGET_CHANGED", "player")
    return u
end

----------------------------------------------------------------------------------
-- Combat lockdown and protected frames
--
-- The client refuses addon-driven geometry on a protected frame, and on any frame whose
-- SUBTREE holds one, while in combat. It refuses silently — the call returns having changed
-- nothing — so a spec asserts the refusal through H.getBlockedActions() and the frame's
-- unchanged size, never through an error.
--
-- Protection propagates DOWN (a descendant of a secure frame is protected). The REFUSAL
-- propagates UP (a plain frame with one secure grandchild cannot be resized). That
-- asymmetry is the bug: a unit frame with a secure click surface inside it could not grow
-- mid-fight, so an arriving debuff band was carved out of its existing box instead.
----------------------------------------------------------------------------------

--- Enters or leaves combat, announcing it the way the client does.
--
-- Entering fires PLAYER_REGEN_DISABLED and leaving fires PLAYER_REGEN_ENABLED, for the same
-- reason H.setTarget fires PLAYER_TARGET_CHANGED: the state moving without the announcement
-- is a situation the client never produces, and code that defers work to the end of combat
-- reads that event to know when to run it. Only a real transition announces, as in game —
-- calling this twice with the same value fires once.
--
-- @param inCombat bool      true to enter combat, false to leave
-- @param opts table|nil     { silent = true } to move the flag without firing, for a spec
--                           specifically about a reader that ignores the event
-- @return bool  The flag as it now stands
function M.setCombat(inCombat, opts)
    local want = inCombat and true or false
    local changed = state.inCombat ~= want
    state.inCombat = want
    if changed and not (opts and opts.silent) then
        M.fireEvent(want and "PLAYER_REGEN_DISABLED" or "PLAYER_REGEN_ENABLED")
    end
    return state.inCombat
end

--- Whether the simulated client is in combat, i.e. what InCombatLockdown() answers.
-- @return bool
function M.inCombat() return state.inCombat == true end

--------------------------------------------------------------------------------
-- Client capabilities
--------------------------------------------------------------------------------

--- Adds or removes the texture gradient API, modelling a client generation without it.
--
-- Phase 0 measured SetGradient present and SetGradientAlpha absent on this build, so the
-- gradient path is the one the real client takes. Pass false to reach the flat-fill
-- fallback a component keeps for a client that has neither: absence is real here, the
-- method is deleted rather than stubbed, so `type(tex.SetGradient) == "function"` answers
-- the way it would on that client.
--
-- Restored automatically on the next H.setup(), so a spec cannot leak it to the next file.
-- @param on boolean
function M.setGradientSupported(on)
    regions.setGradientSupported(on and true or false)
end

--- Stages a boolean CVar, as GetCVarBool reports it.
--
-- `ActionButtonUseKeyDown` is the one that matters: an action button reads it to decide whether the
-- client acts on the press or the release, and a button registered for the wrong event has correct
-- attributes, a correct template, a working tooltip, working drag -- and no action at all.
-- @param name string
-- @param on boolean
function M.setCVarBool(name, on)
    assert(type(name) == "string" and name ~= "", "H.setCVarBool: cvar name required")
    state.cvars[name] = on and true or false
end

--- Clicks a secure button on the PRESS only.
--
-- H.click fires a WHOLE click -- OnMouseDown, then OnClick(down=true) if the button registered for
-- Down, then OnMouseUp, then OnClick(down=false) if it registered for Up -- so that is the tool for
-- "what does one physical click do". These two drive a single half, which is what shows WHICH half
-- the client acts on.
-- @param target table|handle
-- @param button string|nil  defaults to "LeftButton"
function M.clickDown(target, button)
    local f = M.frameOf(target)
    local script = f and f.GetScript and f:GetScript("OnClick")
    assert(script, "H.clickDown: target has no OnClick handler")
    script(f, button or "LeftButton", true)
end

--- Clicks a secure button on the RELEASE only. See H.clickDown.
-- @param target table|handle
-- @param button string|nil  defaults to "LeftButton"
function M.clickUp(target, button)
    local f = M.frameOf(target)
    local script = f and f.GetScript and f:GetScript("OnClick")
    assert(script, "H.clickUp: target has no OnClick handler")
    script(f, button or "LeftButton", false)
end

--------------------------------------------------------------------------------
-- Action bar slots
--------------------------------------------------------------------------------

-- Known action fields. Listed so a typo is an error rather than a silently ignored key.
local ACTION_FIELDS = {
    type = true, id = true, subType = true, texture = true, text = true, count = true,
    cooldownStart = true, cooldownDuration = true, cooldownEnable = true,
    usable = true, notEnoughMana = true, inRange = true, current = true, autoRepeat = true,
}

--- Stages one action slot and fires ACTIONBAR_SLOT_CHANGED.
--
-- Merges into whatever the slot already held, so a spec can put a spell in a slot and then
-- start its cooldown without restating the spell.
--
-- @param slot number  Action slot, 1..72 on this client
-- @param props table  Any subset of ACTION_FIELDS above
-- @param opts table|nil  { silent = true } to stage without announcing
-- @return table  the stored record
function M.setAction(slot, props, opts)
    assert(type(slot) == "number", "H.setAction: slot number required")
    local a = state.actions[slot]
    if not a then
        a = {}
        state.actions[slot] = a
    end
    for k, v in pairs(props or {}) do
        assert(ACTION_FIELDS[k], "H.setAction: unknown action field '" .. tostring(k) .. "'")
        a[k] = v
    end
    if not (opts and opts.silent) then
        M.fireEvent("ACTIONBAR_SLOT_CHANGED", slot)
    end
    return a
end

--- Empties a slot, so HasAction answers false, and fires ACTIONBAR_SLOT_CHANGED.
-- @param slot number
-- @param opts table|nil  { silent = true }
function M.clearAction(slot, opts)
    assert(type(slot) == "number", "H.clearAction: slot number required")
    state.actions[slot] = nil
    if not (opts and opts.silent) then
        M.fireEvent("ACTIONBAR_SLOT_CHANGED", slot)
    end
end

--- Moves the main bar to a page and fires ACTIONBAR_PAGE_CHANGED.
-- @param page number  1..NUM_ACTIONBAR_PAGES
-- @param opts table|nil  { silent = true }
function M.setActionBarPage(page, opts)
    assert(type(page) == "number" and page >= 1, "H.setActionBarPage: page number required")
    state.actionBarPage = page
    if not (opts and opts.silent) then
        M.fireEvent("ACTIONBAR_PAGE_CHANGED")
    end
end

--- Binds a key to a command, so GetBindingKey answers it.
-- @param command string  e.g. "ACTIONBUTTON1"
-- @param key string|nil  nil unbinds
function M.setBinding(command, key)
    assert(type(command) == "string" and command ~= "", "H.setBinding: command required")
    state.bindings[command] = key
end

--- Whether the client reports the bars locked, which gates drag-and-drop.
-- Writes the plain global the client exposes, not a harness-only flag.
-- @param locked boolean
function M.setActionBarLocked(locked)
    state.actionBarLocked = locked and "1" or "0"
    if M.env then M.env.LOCK_ACTIONBAR = state.actionBarLocked end
end

--- What the cursor is carrying after a PickupAction, or nil.
-- @return table|nil
function M.getPickedUpAction() return state.pickedUpAction end

-- Known stance-form fields. Listed so a typo is an error rather than a silently ignored key.
local STANCE_FIELDS = {
    texture = true, isActive = true, isCastable = true, spellID = true,
    cooldownStart = true, cooldownDuration = true, cooldownActive = true,
}

--- Stages one shapeshift / stance form and announces it.
--
-- FORMS MUST BE CONTIGUOUS FROM 1. GetNumShapeshiftForms answers a count and every consumer
-- loops 1..count, so a gap would make the count disagree with what is reachable -- a shape the
-- client cannot produce. Staging form 3 with no form 2 is refused rather than modelled.
--
-- WHICH EVENT FIRES DEPENDS ON WHAT CHANGED, matching the client's own two events: creating a
-- form changes the SET, so UPDATE_SHAPESHIFT_FORMS (plural) fires; updating an existing one
-- changes which is active or castable, so UPDATE_SHAPESHIFT_FORM (singular) fires. The
-- distinction is load-bearing -- a bar that listens only to the plural rebuilds its buttons but
-- never restyles them, and a bar that listens only to the singular never grows a new button.
-- Pass opts.event to override.
--
-- Setting isActive = true CLEARS it on every other form, because GetShapeshiftForm is derived
-- from these records and two active forms is not a state the client can be in.
--
-- @param index number  Form index, contiguous from 1
-- @param props table  Any subset of STANCE_FIELDS
-- @param opts table|nil  { silent = true } to stage quietly, { event = "..." } to force one
-- @return table  the stored record
function M.setStanceForm(index, props, opts)
    assert(type(index) == "number" and index >= 1, "H.setStanceForm: form index required")
    assert(index == 1 or state.stanceForms[index - 1],
        "H.setStanceForm: forms must be contiguous from 1 -- form " .. index ..
        " needs form " .. (index - 1) .. " staged first")

    local f = state.stanceForms[index]
    local created = f == nil
    if created then
        f = {}
        state.stanceForms[index] = f
    end
    for k, v in pairs(props or {}) do
        assert(STANCE_FIELDS[k], "H.setStanceForm: unknown stance field '" .. tostring(k) .. "'")
        f[k] = v
    end

    -- One active form at a time, or the derived GetShapeshiftForm would answer the lower index
    -- while a consumer reading isActive saw both.
    if props and props.isActive == true then
        for i, other in pairs(state.stanceForms) do
            if i ~= index then other.isActive = false end
        end
    end

    if not (opts and opts.silent) then
        M.fireEvent((opts and opts.event)
            or (created and "UPDATE_SHAPESHIFT_FORMS" or "UPDATE_SHAPESHIFT_FORM"))
    end
    return f
end

--- Removes the highest stance form, so the count shrinks. Contiguity is preserved by only ever
-- removing from the end -- removing from the middle would leave a gap the client cannot express.
-- @param opts table|nil  { silent = true }
function M.popStanceForm(opts)
    local n = 0
    while state.stanceForms[n + 1] do n = n + 1 end
    if n == 0 then return end
    state.stanceForms[n] = nil
    if not (opts and opts.silent) then
        M.fireEvent("UPDATE_SHAPESHIFT_FORMS")
    end
end

--- Removes every stance form, which is the state a class with no forms is in.
-- @param opts table|nil  { silent = true }
function M.clearStanceForms(opts)
    state.stanceForms = {}
    if not (opts and opts.silent) then
        M.fireEvent("UPDATE_SHAPESHIFT_FORMS")
    end
end

--- Stages a spell's icon, so GetSpellTexture answers it.
-- @param spellID number
-- @param texture string|nil  nil removes it
function M.setSpellTexture(spellID, texture)
    assert(type(spellID) == "number", "H.setSpellTexture: spell id required")
    state.spellTextures[spellID] = texture
end

--- What CastShapeshiftForm was last asked to cast, or nil.
-- @return number|nil
function M.getCastStance() return state.castStance end

-- Known pet-action fields. Listed so a typo is an error rather than a silently ignored key.
local PET_FIELDS = {
    name = true, texture = true, isToken = true, isActive = true,
    autoCastAllowed = true, autoCastEnabled = true, spellID = true,
    cooldownStart = true, cooldownDuration = true, usable = true, attack = true,
}

--- Stages one pet action slot and fires PET_BAR_UPDATE.
--
-- ON isToken: setting it true means `name` and `texture` are the NAMES OF GLOBALS rather than a
-- display name and a texture path. Nothing is resolved for you -- stage the globals too
-- (H.env.PET_ACTION_FOLLOW = "Follow") if the consumer under test resolves them, because that
-- resolution is exactly what such a test exists to check.
--
-- @param index number  Pet slot, 1..NUM_PET_ACTION_SLOTS
-- @param props table  Any subset of PET_FIELDS
-- @param opts table|nil  { silent = true } to stage without announcing
-- @return table  the stored record
function M.setPetAction(index, props, opts)
    assert(type(index) == "number" and index >= 1, "H.setPetAction: pet slot number required")
    local p = state.petActions[index]
    if not p then
        p = {}
        state.petActions[index] = p
    end
    for k, v in pairs(props or {}) do
        assert(PET_FIELDS[k], "H.setPetAction: unknown pet field '" .. tostring(k) .. "'")
        p[k] = v
    end
    if not (opts and opts.silent) then
        M.fireEvent("PET_BAR_UPDATE")
    end
    return p
end

--- Empties a pet slot, so GetPetActionInfo answers nil.
-- @param index number
-- @param opts table|nil  { silent = true }
function M.clearPetAction(index, opts)
    assert(type(index) == "number", "H.clearPetAction: pet slot number required")
    state.petActions[index] = nil
    if not (opts and opts.silent) then
        M.fireEvent("PET_BAR_UPDATE")
    end
end

--- Sets whether the pet's action bar is usable, as PetHasActionBar() reports it.
--
-- DELIBERATELY NOT the same thing as the pet existing -- use H.setUnit("pet", {...}) for that.
-- A present pet with an unusable bar greys its icons; an absent pet hides the bar entirely. Two
-- mechanisms, and a consumer that collapses them gets one of the two cases wrong.
--
-- @param has boolean
-- @param opts table|nil  { silent = true }
function M.setPetActionBar(has, opts)
    state.petHasActionBar = has and true or false
    if not (opts and opts.silent) then
        -- Filtered on unit "player" by every consumer, which is what the client sends for a pet
        -- gained or lost. UNIT_FLAGS is the one filtered on "pet" -- getting the two the wrong
        -- way round silently kills every update.
        M.fireEvent("UNIT_PET", "player")
    end
end

-- Known experience fields, so a typo raises rather than being ignored.
local XP_FIELDS = { current = true, max = true, rested = true, disabled = true }

--- Stages the player's experience and fires PLAYER_XP_UPDATE.
--
-- Merges, so a spec can set the level's progress and then add a rested bonus without restating it.
-- Pass rested = false to clear it -- nil would be indistinguishable from "leave it alone", and the
-- difference between no rested bonus and a bonus of zero is visible on the bar.
--
-- @param props table  any subset of XP_FIELDS
-- @param opts table|nil  { silent = true }
function M.setXP(props, opts)
    for k, v in pairs(props or {}) do
        assert(XP_FIELDS[k], "H.setXP: unknown xp field '" .. tostring(k) .. "'")
        if k == "rested" and v == false then
            state.xp.rested = nil
        else
            state.xp[k] = v
        end
    end
    if not (opts and opts.silent) then
        M.fireEvent("PLAYER_XP_UPDATE", "player")
    end
    return state.xp
end

--- Stages the watched faction, or clears it with nil, and fires UPDATE_FACTION.
-- @param props table|nil  { name, standing, min, max, value }; nil watches nothing
-- @param opts table|nil  { silent = true }
function M.setWatchedFaction(props, opts)
    state.watchedFaction = props
    if not (opts and opts.silent) then
        M.fireEvent("UPDATE_FACTION")
    end
end

--- Which reputation API this simulated client has.
--
-- The addon must survive all three, and they are genuinely different situations: a modern backend may
-- carry only the table-returning `C_Reputation.GetWatchedFactionData`, and "no API at all" must NOT
-- look like "no faction watched" -- conflating those two is what hid the bar on a character that had a
-- faction tracked.
--
-- Installs and removes the actual global, because the addon tests for its presence rather than
-- consulting harness state.
-- @param mode string  "legacy" (default) | "modern" | "none"
function M.setRepApi(mode)
    mode = mode or "legacy"
    assert(mode == "legacy" or mode == "modern" or mode == "none",
        "H.setRepApi: mode must be 'legacy', 'modern' or 'none', got '" .. tostring(mode) .. "'")
    state.repApi = mode

    -- M.env, NOT _G. The addon's chunks run against the harness environment, so nil-ing the real _G
    -- changes a table nothing under test ever reads -- the switch looked like it worked and the addon
    -- carried on seeing the old API.
    local env = M.env
    assert(env, "H.setRepApi: call H.setup() first")

    -- A modern client does not carry BOTH. Removing the legacy global in "modern" mode is what makes
    -- the modern test meaningful: if it stayed, the addon's legacy branch would answer first and the
    -- table path would never run.
    env.GetWatchedFactionInfo = (mode == "legacy") and state.legacyRepFn or nil

    if mode == "modern" then
        env.C_Reputation = {
            GetWatchedFactionData = function()
                local w = state.watchedFaction
                if not w then return nil end
                return {
                    name = w.name,
                    reaction = w.standing or 4,
                    currentReactionThreshold = w.min or 0,
                    nextReactionThreshold = w.max or 0,
                    currentStanding = w.value or 0,
                    factionID = w.factionID or 1168,
                }
            end,
        }
    else
        env.C_Reputation = nil
    end
end

--- Stages the character's bags.
--
-- Indexed BY BAG ID FROM 0: bag 0 is the backpack, 1..4 the bag slots. Each entry is
-- { free = n, slots = n, bagType = n }, where a bagType other than 0 marks a specialised container
-- whose free slots cannot hold loot.
-- @param bags table  { [0] = { free = 4, slots = 16 }, [1] = { free = 0, slots = 12, bagType = 2 } }
function M.setBags(bags, opts)
    state.bags = bags
    if not (opts and opts.silent) then
        M.fireEvent("BAG_UPDATE_DELAYED")
    end
end

--- Which container API this simulated client has.
--
-- Same three cases as H.setRepApi, and the same reason for "none": a missing API must be
-- distinguishable from an empty result, or a silently blank field looks like a full inventory.
-- Mutates M.env, NOT _G -- the addon's chunks resolve globals through the harness environment.
--
-- "modern" is the DEFAULT because that is what this client measured as: C_Container exists and
-- every bare container global is nil. See state.bagApi for the measurement.
-- @param mode string  "modern" (default) | "legacy" | "none"
function M.setBagApi(mode)
    mode = mode or "modern"
    assert(mode == "legacy" or mode == "modern" or mode == "none",
        "H.setBagApi: mode must be 'legacy', 'modern' or 'none', got '" .. tostring(mode) .. "'")
    assert(state.applyBagApi, "H.setBagApi: call H.setup() first")
    state.bagApi = mode
    state.applyBagApi(mode)
end

-- The fields a bag-slot record may carry: exactly the set GetContainerItemInfo returns on this
-- client, measured 2026-08-24. An unknown name RAISES rather than being dropped, so a typo is a
-- failure instead of a passing test asserting nothing.
local BAG_ITEM_FIELDS = {
    hasLoot = true, hasNoValue = true, hyperlink = true, iconFileID = true,
    isBound = true, isFiltered = true, isLocked = true, isReadable = true,
    itemID  = true, itemName   = true, quality  = true, stackCount = true,
}

--- Stages one container slot's contents.
--
-- MERGES, so a spec can put an item in a slot and then lock it without restating the item -- the
-- same shape as H.setAction and H.setUnit.
--
-- Bag ids: 0 the backpack, 1..4 the bag slots, -1 the bank, 5..11 the bank bags. Staging a BANK
-- slot does not make it readable: that is gated on H.setBankOpen, which is the measured behaviour.
-- @param bag number
-- @param slot number
-- @param props table  any subset of the measured field set
-- @param opts table|nil  { silent = true } stages without firing BAG_UPDATE
function M.setBagItem(bag, slot, props, opts)
    assert(type(bag) == "number", "H.setBagItem: bag must be a number, got " .. type(bag))
    assert(type(slot) == "number", "H.setBagItem: slot must be a number, got " .. type(slot))
    props = props or {}
    for k in pairs(props) do
        assert(BAG_ITEM_FIELDS[k], "H.setBagItem: unknown field '" .. tostring(k) .. "'")
    end
    state.containerItems[bag] = state.containerItems[bag] or {}
    local rec = state.containerItems[bag][slot] or {}
    for k, v in pairs(props) do rec[k] = v end
    -- Defaults an occupied slot always carries, so a spec staging only a name still yields a usable
    -- record. The client never reports stackCount 0 for a slot that has something in it.
    if rec.stackCount == nil then rec.stackCount = 1 end
    if rec.quality    == nil then rec.quality    = 1 end
    state.containerItems[bag][slot] = rec
    if not (opts and opts.silent) then M.fireEvent("BAG_UPDATE", bag) end
end

--- Empties one container slot, so GetContainerItemInfo answers nil for it.
-- @param bag number
-- @param slot number
-- @param opts table|nil  { silent = true }
function M.clearBagItem(bag, slot, opts)
    local perBag = state.containerItems[bag]
    if perBag then perBag[slot] = nil end
    if not (opts and opts.silent) then M.fireEvent("BAG_UPDATE", bag) end
end

--- Opens or closes the bank frame.
--
-- This GATES bank contents rather than merely recording a flag, because that is what was measured:
-- with the frame shut, GetContainerNumSlots(-1) answers 28 while every slot reads nil and free
-- reads 0. Fires only on a real transition, so a spec cannot assert an event that did not happen.
-- @param open boolean
-- @param opts table|nil  { silent = true }
function M.setBankOpen(open, opts)
    open = not not open
    local was = state.bankOpen
    state.bankOpen = open
    -- DRIVES BLIZZARD'S OWN FRAME, as the client does: talking to a banker SHOWS BankFrame. That
    -- matters because the frame's OnHide calls CloseBankFrame(), so a consumer that suppresses the
    -- frame closes the session -- and with the frame left inert here, that whole failure was
    -- invisible to the suite while making the bank window unusable in game.
    --
    -- Set BEFORE the event fires, so a handler that reads the frame sees the state the event announces.
    local bank = M.env and M.env.BankFrame
    if bank then
        if open then bank:Show() else bank:Hide() end
        -- The frame's own scripts write state.bankOpen, so re-assert what the caller asked for: a
        -- consumer may legitimately keep the frame shown while the bank is logically closed.
        state.bankOpen = open
    end
    if was ~= open and not (opts and opts.silent) then
        M.fireEvent(open and "BANKFRAME_OPENED" or "BANKFRAME_CLOSED")
    end
end

--- Opens or closes a merchant window.
--
-- This is what decides whether UseContainerItem sells or is refused as a protected use -- see the
-- note in wow/api.lua. Fires only on a real transition.
-- @param open boolean
-- @param opts table|nil  { silent = true }
function M.setMerchantOpen(open, opts)
    open = not not open
    local was = state.merchantOpen
    state.merchantOpen = open
    if was ~= open and not (opts and opts.silent) then
        M.fireEvent(open and "MERCHANT_SHOW" or "MERCHANT_CLOSED")
    end
end

--- Stages an item cooldown on one slot, as GetContainerItemCooldown reports it.
--
-- Pass duration 0 (or nil) to clear it. `enable` defaults to 1 and is a NUMBER on purpose: the
-- client answers 0 for "no cooldown", and a consumer testing truthiness paints a permanent sweep.
-- @param bag number
-- @param slot number
-- @param start number|nil
-- @param duration number|nil
-- @param enable number|nil
function M.setBagCooldown(bag, slot, start, duration, enable)
    state.containerCooldowns[bag] = state.containerCooldowns[bag] or {}
    if not duration or duration <= 0 then
        state.containerCooldowns[bag][slot] = nil
        return
    end
    state.containerCooldowns[bag][slot] =
        { start = start or 0, duration = duration, enable = enable or 1 }
end

--- What the cursor is carrying after a PickupContainerItem, or nil.
-- @return table|nil
function M.getCursorItem() return state.cursorItem end

--- The character's money in copper, as GetMoney() reports it.
-- @param copper number
function M.setMoney(copper) state.money = copper or 0 end

--- Every UseContainerItem call the client ACCEPTED, in order, as { bag, slot }.
--
-- Returns a COPY, so a spec reading it cannot mutate the record the next assertion reads. A call
-- the client REFUSED is in H.getBlockedActions() instead, which is what keeps "sold" and "blocked"
-- distinguishable.
-- @return table
function M.getUsedContainerItems()
    local out = {}
    for i, v in ipairs(state.usedContainerItems) do
        out[i] = { bag = v.bag, slot = v.slot, via = v.via }
    end
    return out
end

--- Clears the accepted-sale record.
function M.resetUsedContainerItems() state.usedContainerItems = {} end

--- The page the client swaps bar 1 to for a temporary shapeshift, i.e. what
--- GetTempShapeshiftBarIndex() answers. Pass nil to model a client that will not say.
--
-- Staged rather than fixed because the addon calls the client for it instead of hardcoding a number
-- nothing has measured -- so a spec must be able to move it to prove that.
-- @param page number|nil
function M.setTempShapeshiftPage(page)
    state.tempShapeshiftBarIndex = page
end

--- Panel toggles the addon called, in order, as { name = ..., arg = ... }.
-- @return table
function M.getPanelToggles() return state.panelToggles end

--- Micro buttons whose OnClick fired, by global name, in order.
-- @return table
function M.getMicroClicks() return state.microClicks end

--- What the client's secure handler did with the last `pet` click, or nil.
-- @return table|nil  { slot, button, down }
function M.getUsedPetAction() return state.usedPetAction end

--- Every slot index TogglePetAutocast was called on, in order.
-- @return table
function M.getPetAutocastToggles() return state.petAutocastToggles end

--- Sets GetBonusBarOffset(), which is how a druid's form or a rogue's stealth moves the paged bar.
-- @param offset number
-- @param opts table|nil  { silent = true }
function M.setBonusBarOffset(offset, opts)
    assert(type(offset) == "number", "H.setBonusBarOffset: offset number required")
    state.bonusBarOffset = offset
    if not (opts and opts.silent) then
        M.fireEvent("UPDATE_BONUS_ACTIONBAR")
    end
end

--- Every override binding installed so far, in call order.
-- Each entry is { owner, isPriority, key, button, mouseButton }.
-- @return table
function M.getOverrideBindings()
    local out = {}
    for i, b in ipairs(state.overrideBindings) do out[i] = b end
    return out
end

--- The conditional string a frame registered for a secure state, or nil.
--
-- The harness records driver strings and never evaluates them, so this is the whole
-- observable: assert the string, and check what the client does with it in game.
-- @param frame table|handle
-- @param stateName string  e.g. "page"
-- @return string|nil
function M.getStateDriver(frame, stateName)
    local rec = state.stateDrivers[M.frameOf(frame)]
    return rec and rec[stateName]
end

--- What the client's secure handler did with the last `action` click, or nil.
-- { slot = <number>, button = <"LeftButton"> }.
-- @return table|nil
function M.getUsedAction() return state.usedAction end

--- Forgets the last action click, so one spec can assert a second one cleanly.
function M.resetUsedAction() state.usedAction = nil end

--- Every geometry call the lockdown refused, oldest first.
--
-- Each entry is { action = "SetSize", frame = <widget>, name = <frame name or nil>,
-- protected = <bool, whether the frame itself was protected rather than merely holding a
-- protected descendant> }. Returns a copy, so a spec can hold the list across further calls.
-- @return table
function M.getBlockedActions()
    local out = {}
    for i, rec in ipairs(state.blockedActions) do out[i] = rec end
    return out
end

--- Forgets the refusals so far, so one spec can assert a second call cleanly.
function M.resetBlockedActions()
    state.blockedActions = {}
end

--- Whether any frame in this widget's subtree is protected — the question the refusal asks.
--
-- The invariant a resizing frame has to hold: true here means every geometry change on it is
-- refused for the duration of a fight.
-- @param target table  A widget or a SuuUI component handle
-- @return bool
function M.hasProtectedDescendant(target)
    return widget.hasProtectedDescendant(M.frameOf(target))
end

----------------------------------------------------------------------------------
-- Spellcasts
--
-- The client reports a cast through UnitCastingInfo / UnitChannelInfo and announces the
-- transitions through UNIT_SPELLCAST_* events. These helpers move both together, because
-- a spec that fires the event without moving the state (or the reverse) tests a situation
-- the client never produces.
----------------------------------------------------------------------------------

local function castRecord(opts)
    opts = opts or {}
    local nowMS = (state.clock or 0) * 1000
    local dur   = (opts.duration or 2.5) * 1000
    local start = opts.startTime or nowMS
    local unit  = opts.unit or "player"
    -- A unit that does not exist cannot be casting, and the client reports nothing about
    -- one — so staging a cast on an unstaged unit would build a state it never produces.
    -- Naming a unit in startCast IS saying that unit is there, so make it so. Harmless for
    -- a unit already staged, and for the player, whose record falls back to the flat values.
    if not M.env.UnitExists(unit) then M.setUnit(unit, {}) end
    return {
        unit      = unit,
        name      = opts.name or "Fireball",
        text      = opts.text,
        texture   = opts.texture or "Interface\\Icons\\Spell_Fire_FlameBolt",
        startTime = start,
        endTime   = opts.endTime or (start + dur),
        castID    = opts.castID or "cast-1",
        spellId   = opts.spellId or 133,
        notInterruptible = opts.notInterruptible or false,
        isTradeSkill     = opts.isTradeSkill or false,
    }
end

--- Starts a cast and fires UNIT_SPELLCAST_START.
-- @param opts table  { unit, name, texture, duration, startTime, endTime, spellId,
--                      castID, notInterruptible, isTradeSkill }
-- @return table  The cast record, so a spec can read startTime/endTime back
function M.startCast(opts)
    local c = castRecord(opts)
    state.cast, state.channel = c, nil
    M.fireEvent("UNIT_SPELLCAST_START", c.unit, c.castID, c.spellId)
    return c
end

--- Starts a channel and fires UNIT_SPELLCAST_CHANNEL_START.
-- @param opts table  Same shape as startCast
-- @return table
function M.startChannel(opts)
    local c = castRecord(opts)
    state.channel, state.cast = c, nil
    M.fireEvent("UNIT_SPELLCAST_CHANNEL_START", c.unit, c.castID, c.spellId)
    return c
end

-- Clears the cast BEFORE firing, which is the order the client uses: by the time a stop
-- event arrives, UnitCastingInfo already reports nothing.
local function endCast(unit, event)
    local c = state.cast or state.channel
    local u = unit or (c and c.unit) or "player"
    local castID, spellId = c and c.castID, c and c.spellId
    state.cast, state.channel = nil, nil
    M.fireEvent(event, u, castID, spellId)
end

--- Ends a cast with UNIT_SPELLCAST_STOP.
function M.stopCast(unit) endCast(unit, "UNIT_SPELLCAST_STOP") end

--- Completes a cast with UNIT_SPELLCAST_SUCCEEDED.
function M.finishCast(unit) endCast(unit, "UNIT_SPELLCAST_SUCCEEDED") end

--- Delivers one SPELL_INTERRUPT combat log line against a unit.
--
-- The interrupter's name exists ONLY here: UNIT_SPELLCAST_INTERRUPTED does not carry it.
-- The payload is laid out exactly as CombatLogGetCurrentEventInfo() returns it, and is
-- cleared again afterwards, so code that reads it outside the handler gets nothing — the
-- same failure it would hit in game.
-- @param opts table  { unit, by, destName, spell, spellId, interrupted, interruptedId }
--   by:          the interrupter's name (source)
--   spell:       the interrupting spell (default "Counterspell")
--   interrupted: the spell that was stopped (extraSpell in the client's payload)
-- @return table  The payload delivered
function M.combatLogInterrupt(opts)
    opts = opts or {}
    local unit = opts.unit or "player"
    local payload = {
        state.clock or 0,                                   -- 1  timestamp
        "SPELL_INTERRUPT",                                  -- 2  subevent
        false,                                              -- 3  hideCaster
        "GUID-src-" .. tostring(opts.by or "interrupter"),  -- 4  sourceGUID
        opts.by or "Interrupter",                           -- 5  sourceName
        0, 0,                                               -- 6  sourceFlags, 7 raidFlags
        M.env.UnitGUID(unit),                               -- 8  destGUID
        opts.destName or "Testchar",                        -- 9  destName
        0, 0,                                               -- 10 destFlags, 11 raidFlags
        opts.spellId or 2139,                               -- 12 interrupting spell id
        opts.spell or "Counterspell",                       -- 13 interrupting spell name
        0,                                                  -- 14 school
        opts.interruptedId or 133,                          -- 15 extraSpellId
        opts.interrupted or "Fireball",                     -- 16 extraSpellName
        0,                                                  -- 17 extraSchool
    }
    payload.n = #payload
    state.combatLogEvent = payload
    M.fireEvent("COMBAT_LOG_EVENT_UNFILTERED")
    state.combatLogEvent = nil
    return payload
end

--- Delivers one spell-carrying combat log line.
--
-- This is the ONLY route by which a spell's school reaches the UI: no client API maps a
-- spell to its school, so anything that colours by school has to learn it here. The
-- subevent is a parameter because which one carries a given spell differs — a cast fires
-- SPELL_CAST_START, a channel never does and is only described by its ticks.
-- @param opts table  { unit, subevent, spellId, spell, school, destName }
--   unit:     the CASTER, whose GUID lands in sourceGUID (default "player")
--   subevent: default "SPELL_CAST_START"
--   school:   the school mask (default 0x04, Fire)
-- @return table  The payload delivered
function M.combatLogSpell(opts)
    opts = opts or {}
    local unit = opts.unit or "player"
    local payload = {
        state.clock or 0,                        -- 1  timestamp
        opts.subevent or "SPELL_CAST_START",     -- 2  subevent
        false,                                   -- 3  hideCaster
        M.env.UnitGUID(unit),                    -- 4  sourceGUID
        opts.sourceName or "Testchar",           -- 5  sourceName
        0, 0,                                    -- 6  sourceFlags, 7 raidFlags
        opts.destGUID or M.env.UnitGUID("target"),  -- 8  destGUID
        opts.destName or "Target",               -- 9  destName
        0, 0,                                    -- 10 destFlags, 11 raidFlags
        opts.spellId or 133,                     -- 12 spellId
        opts.spell or "Fireball",                -- 13 spellName
        opts.school or 0x04,                     -- 14 spellSchool
    }
    payload.n = #payload
    state.combatLogEvent = payload
    M.fireEvent("COMBAT_LOG_EVENT_UNFILTERED")
    state.combatLogEvent = nil
    return payload
end

--- Interrupts a cast with UNIT_SPELLCAST_INTERRUPTED.
--
-- Pass `by` to also deliver the SPELL_INTERRUPT combat log line, which is the only source
-- of the interrupter's name. The client does not guarantee which of the two arrives first,
-- so `logAfter` produces the other order — anything that correlates them has to survive
-- both.
-- @param opts nil|string|table  unit token, or { unit, by, logAfter }
function M.interruptCast(opts)
    local unit, by, logAfter
    if type(opts) == "string" then
        unit = opts
    elseif type(opts) == "table" then
        unit, by, logAfter = opts.unit, opts.by, opts.logAfter
    end
    local active = state.cast or state.channel
    unit = unit or (active and active.unit) or "player"
    local spellName = active and active.name

    if by and not logAfter then
        M.combatLogInterrupt({ unit = unit, by = by, interrupted = spellName })
    end
    endCast(unit, "UNIT_SPELLCAST_INTERRUPTED")
    if by and logAfter then
        M.combatLogInterrupt({ unit = unit, by = by, interrupted = spellName })
    end
end

--- Fails a cast with UNIT_SPELLCAST_FAILED.
function M.failCast(unit) endCast(unit, "UNIT_SPELLCAST_FAILED") end

-- A SECOND spell attempt ending, while the cast already in flight carries on untouched.
--
-- This is the one place where leaving the state alone is the faithful model rather than a
-- shortcut: press a spell while already casting and the client fails the new attempt and
-- reports it against the unit, but the original cast is still running and UnitCastingInfo
-- still reports it. So the state deliberately does not move, and the castID deliberately
-- does not match the one in flight — that mismatch is the whole signal a reader has.
local function foreignCastEnd(opts, event)
    opts = opts or {}
    local active = state.cast or state.channel
    local unit = opts.unit or (active and active.unit) or "player"
    M.fireEvent(event, unit, opts.castID or "cast-other", opts.spellId or 686)
end

--- Fires UNIT_SPELLCAST_FAILED for a DIFFERENT attempt, leaving the in-flight cast alone.
-- @param opts nil|table  { unit, castID, spellId }
function M.failOtherCast(opts) foreignCastEnd(opts, "UNIT_SPELLCAST_FAILED") end

--- Fires UNIT_SPELLCAST_INTERRUPTED for a DIFFERENT attempt, leaving the cast alone.
-- @param opts nil|table  { unit, castID, spellId }
function M.interruptOtherCast(opts) foreignCastEnd(opts, "UNIT_SPELLCAST_INTERRUPTED") end

--- Ends a channel with UNIT_SPELLCAST_CHANNEL_STOP.
function M.stopChannel(unit) endCast(unit, "UNIT_SPELLCAST_CHANNEL_STOP") end

--- Pushes a cast's end time out and fires UNIT_SPELLCAST_DELAYED, as spell pushback does.
-- @param seconds number  Added to the end time (default 0.5)
-- @param unit string
-- @return table|nil  The cast record, or nil when nothing is casting
function M.delayCast(seconds, unit)
    local c = state.cast
    if not c then return nil end
    c.endTime = c.endTime + (seconds or 0.5) * 1000
    M.fireEvent("UNIT_SPELLCAST_DELAYED", unit or c.unit, c.castID, c.spellId)
    return c
end

--- Moves a channel's end time and fires UNIT_SPELLCAST_CHANNEL_UPDATE.
-- @param seconds number  Added to the end time; negative shortens the channel
-- @param unit string
-- @return table|nil
function M.updateChannel(seconds, unit)
    local c = state.channel
    if not c then return nil end
    c.endTime = c.endTime + (seconds or 0.5) * 1000
    M.fireEvent("UNIT_SPELLCAST_CHANNEL_UPDATE", unit or c.unit, c.castID, c.spellId)
    return c
end

----------------------------------------------------------------------------------
-- Auras
--
-- Staged per-unit, mirroring the H.setUnit/H.setTarget pattern. Moving the aura state
-- fires UNIT_AURA for that unit, because the state moving without the event is a
-- situation the client never produces. Opt out with silent = true for testing a reader
-- that explicitly ignores the event.
----------------------------------------------------------------------------------

-- Known aura entry fields. Listed so a typo is an error.
local AURA_FIELDS = {
    name = true, icon = true, count = true, debuffType = true,
    duration = true, expirationTime = true, source = true, isStealable = true,
    spellId = true, canApplyAura = true, isBossDebuff = true, castByPlayer = true,
    timeMod = true, nameplateShowPersonal = true, nameplateShowAll = true,
}

--- Stages aura lists for a unit and fires UNIT_AURA.
--
-- @param unit string  Unit token, e.g. "player" or "target"
-- @param lists table  { helpful = { {...}, ... }, harmful = { {...}, ... } }
-- @param opts table|nil  { silent = true } to suppress the event
function M.setAuras(unit, lists, opts)
    assert(type(unit) == "string" and unit ~= "", "H.setAuras: unit token required")
    lists = lists or {}
    -- Validate entries
    for _, key in ipairs({ "helpful", "harmful" }) do
        local list = lists[key]
        if list then
            for _, entry in ipairs(list) do
                for k in pairs(entry) do
                    assert(AURA_FIELDS[k], "H.setAuras: unknown aura field '" .. tostring(k) .. "'")
                end
            end
        end
    end
    state.auras[unit] = {
        helpful = lists.helpful or {},
        harmful = lists.harmful or {},
    }
    if not (opts and opts.silent) then
        M.fireEvent("UNIT_AURA", unit)
    end
end

--- Clears all auras for a unit and fires UNIT_AURA.
-- @param unit string
-- @param opts table|nil  { silent = true } to suppress the event
function M.clearAuras(unit, opts)
    state.auras[unit] = nil
    if not (opts and opts.silent) then
        M.fireEvent("UNIT_AURA", unit)
    end
end

--- Returns the last CancelUnitBuff call record { unit, index }, or nil.
function M.getCancelBuff()
    return state.cancelBuff
end

--- Clears the CancelUnitBuff record (call between assertions in multi-step specs).
function M.resetCancelBuff()
    state.cancelBuff = nil
end

--- Returns the GameTooltip state: { owner, anchor, aura = { unit, index, filter } }, or nil.
function M.getTooltipState()
    return state.tooltip
end

--- Stages what GetItemInfo answers for one link.
--
-- Field names are VALIDATED rather than merged blindly, for the reason every other staging
-- helper here validates: a typo would silently stage nothing and the test would pass while
-- asserting against an unstaged item.
--
-- `quality` is the field that matters most -- it drives the tooltip's signal border, and the
-- threshold that border applies (uncommon and above) can only be tested by staging both sides
-- of it.
-- @param link string|number  The item link or id a consumer will look up
-- @param props table  { name, quality, itemLevel, reqLevel, class, subclass, maxStack,
--                       equipSlot, texture, sellPrice }
function M.setItemInfo(link, props)
    assert(state.env, "H.setup() must run before H.setItemInfo")
    assert(type(link) == "string" or type(link) == "number", "link must be a string or number")
    props = props or {}
    local allowed = {
        name = true, quality = true, itemLevel = true, reqLevel = true, class = true,
        subclass = true, maxStack = true, equipSlot = true, texture = true, sellPrice = true,
        -- What GetItemCount answers. Two numbers rather than one, because the client's
        -- includeBank argument returns the TOTAL and a consumer wanting the bank's own figure
        -- has to subtract -- so a spec has to be able to stage a case where those differ.
        countBags = true, countBank = true,
    }
    for k in pairs(props) do
        assert(allowed[k], "unknown item field: " .. tostring(k))
    end
    state.items = state.items or {}
    state.items[link] = {
        name      = props.name      or "Item " .. tostring(link),
        link      = type(link) == "string" and link or ("|Hitem:" .. tostring(link) .. "|h"),
        quality   = props.quality   or 1,
        itemLevel = props.itemLevel or 1,
        reqLevel  = props.reqLevel  or 1,
        class     = props.class     or "Miscellaneous",
        subclass  = props.subclass  or "Junk",
        maxStack  = props.maxStack  or 1,
        equipSlot = props.equipSlot or "",
        texture   = props.texture   or "Interface\\Icons\\INV_Misc_QuestionMark",
        sellPrice = props.sellPrice or 0,
        countBags = props.countBags or 0,
        countBank = props.countBank or 0,
    }
    return state.items[link]
end

--- Forgets every staged item, so GetItemInfo answers nothing -- the client's uncached state.
function M.clearItems()
    state.items = {}
end

--- Clears the tooltip state record.
function M.resetTooltipState()
    state.tooltip = nil
end

----------------------------------------------------------------------------------
-- Input simulation
----------------------------------------------------------------------------------

--- Places the cursor, given coordinates in a frame's own space.
--
-- GetCursorPosition reports raw screen coordinates; a frame's GetLeft/GetBottom are in
-- that frame's space. The two differ by the frame's effective scale, so the space the
-- coordinates belong to has to be named. Defaults to UIParent, which is the same thing
-- only while nothing in the chain carries a scale.
-- @param x number
-- @param y number
-- @param space table  Optional frame or handle whose space x/y are expressed in
function M.cursor(x, y, space)
    local f = space and M.frameOf(space) or M.UIParent
    local scale = f:GetEffectiveScale()
    if type(scale) ~= "number" or scale <= 0 then scale = 1 end
    state.cursorX, state.cursorY = x * scale, y * scale
end

--- Places the cursor at the centre of a widget, in that widget's own space.
-- @param target table
function M.cursorOn(target)
    local f = M.frameOf(target)
    local cx, cy = f:GetCenter()
    assert(cx, "harness: cursorOn target has no resolvable position")
    M.cursor(cx, cy, f)
end

--- Sets a mouse button's held state, as IsMouseButtonDown reports it.
-- @param button string
-- @param down bool
function M.setMouseDown(button, down)
    state.mouseDown[button or "LeftButton"] = down and true or false
end

--- Sets modifier key state for IsControlKeyDown and friends.
-- @param mods table  { ctrl, alt, shift }
function M.mods(mods)
    mods = mods or {}
    state.ctrlDown  = mods.ctrl == true
    state.altDown   = mods.alt == true
    state.shiftDown = mods.shift == true
end

local function deliverable(f)
    return f and f:IsVisible() and f:IsMouseEnabled()
end

-- A Button fires OnClick only for the buttons and the phase it registered for, and it
-- registers for left-up alone until told otherwise. That default is the point: a surface
-- that wants a right-click has to opt in, and forgetting to is invisible in every other
-- assertion — the frame is still there, still sized, still mouse-enabled, and the click
-- simply never reaches the handler.
local DEFAULT_CLICKS = { "LeftButtonUp" }

local function firesClick(f, button, phase)
    -- ASKED THROUGH THE TYPE HIERARCHY, not a hardcoded pair. This was
    -- `f._kind ~= "Button" and f._kind ~= "CheckButton"`, which silently dropped every OnClick on an
    -- ItemButton -- the type the bag-cell templates are declared as -- while the frame still reported
    -- as present, mouse-enabled, and carrying an OnClick script. H.click returned TRUE the whole time,
    -- because a truthy return means the input was delivered rather than that a handler ran.
    -- IsObjectType covers Button, CheckButton, ItemButton and anything added later for free.
    if not (f.IsObjectType and f:IsObjectType("Button")) then return false end
    local list = f._clickButtons or DEFAULT_CLICKS
    -- The client is CASE-INSENSITIVE here: "anyUp", "AnyUp" and "ANYUP" are the same
    -- registration, and third-party code freely uses the lower-cased spelling. Comparing
    -- case-sensitively dropped every click from such a button while the frame still
    -- reported as present, sized and mouse-enabled.
    local want = ("Any" .. phase):lower()
    local wantButton = (button .. phase):lower()
    local legacy = button:lower()
    for i = 1, #list do
        local entry = tostring(list[i]):lower()
        if entry == want or entry == wantButton then return true end
        -- The legacy spelling, which names the button and means the up phase.
        if phase == "Up" and entry == legacy then return true end
    end
    return false
end

--- Presses and releases the mouse over a widget, as the client would.
-- Returns false without firing anything when the widget cannot receive mouse input,
-- which is how a disabled control behaves in game.
-- @param target table
-- @param button string  Default "LeftButton"
-- @return bool  Whether the click was delivered
function M.click(target, button)
    local f = M.frameOf(target)
    if not deliverable(f) then return false end
    button = button or "LeftButton"
    M.setMouseDown(button, true)
    f:_fire("OnMouseDown", button)
    if firesClick(f, button, "Down") then f:_fire("OnClick", button, true) end
    M.setMouseDown(button, false)
    f:_fire("OnMouseUp", button)
    if firesClick(f, button, "Up") then f:_fire("OnClick", button, false) end
    return true
end

--- Fires the click scripts regardless of mouse-enabled state, to exercise a
--- component's own internal guard rather than the client's input routing.
function M.forceClick(target, button)
    local f = M.frameOf(target)
    button = button or "LeftButton"
    f:_fire("OnMouseDown", button)
    if firesClick(f, button, "Down") then f:_fire("OnClick", button, true) end
    f:_fire("OnMouseUp", button)
    if firesClick(f, button, "Up") then f:_fire("OnClick", button, false) end
    return true
end

function M.mouseDown(target, button)
    local f = M.frameOf(target)
    if not deliverable(f) then return false end
    M.setMouseDown(button or "LeftButton", true)
    f:_fire("OnMouseDown", button or "LeftButton")
    return true
end

function M.mouseUp(target, button)
    local f = M.frameOf(target)
    if not deliverable(f) then return false end
    M.setMouseDown(button or "LeftButton", false)
    f:_fire("OnMouseUp", button or "LeftButton")
    return true
end

--- Drags a resize grip by a delta, the way the client resizes a frame: press the grip,
--- let the client move the edge, release. The client clamps the result to the frame's
--- resize bounds, so a drag past a bound simply stops there.
-- @param grip table    The grip widget that calls StartSizing
-- @param dw number     Width delta in pixels
-- @param dh number     Height delta in pixels
-- @return bool  Whether the drag was delivered
function M.dragResize(grip, dw, dh)
    local g = M.frameOf(grip)
    if not M.mouseDown(g) then return false end
    local f = g
    while f and not f._sizing do f = f:GetParent() end
    assert(f, "harness: dragResize found no frame sizing after OnMouseDown")
    f:_userResize(f:GetWidth() + (dw or 0), f:GetHeight() + (dh or 0))
    M.mouseUp(g)
    return true
end

function M.hover(target)
    local f = M.frameOf(target)
    if not deliverable(f) then return false end
    f:_fire("OnEnter")
    return true
end

function M.unhover(target)
    local f = M.frameOf(target)
    if not f then return false end
    f:_fire("OnLeave")
    return true
end

----------------------------------------------------------------------------------
-- Unit actions the client performed itself
--
-- Targeting and the unit context menu are protected, so they are never an addon call:
-- they happen inside the secure template's own click handler, driven by the frame's
-- attributes. These read back what the client did, which is the only observable a spec
-- has — and the right one, since the assertion is about what the frame ASKED for.
----------------------------------------------------------------------------------

--- The unit the client last targeted from a secure click, or nil.
-- @return string|nil
function M.targetedUnit() return state.targetedUnit end

--- The unit context menu the client last opened, as { unit = ... }, or nil.
-- @return table|nil
function M.unitMenu() return state.unitMenu end

--- Forgets both, so one spec can assert a second click without the first still standing.
function M.clearUnitActions()
    state.targetedUnit = nil
    state.unitMenu     = nil
end

--- Sends a mouse wheel notch.
-- @param target table
-- @param delta number  1 up, -1 down
function M.scroll(target, delta)
    local f = M.frameOf(target)
    f:_fire("OnMouseWheel", delta or -1)
end

--- Sends a key press to a widget with keyboard input enabled.
-- @param target table
-- @param key string
-- @return bool  Whether the key was delivered
function M.key(target, key)
    local f = M.frameOf(target)
    if not (f:IsVisible() and f:IsKeyboardEnabled()) then return false end
    f:_fire("OnKeyDown", key)
    return true
end

--- Types into an Input handle the way a user does: focus, set text, fire the change.
-- @param inputHandle table  SuuUI Input component handle
-- @param text string
function M.typeText(inputHandle, text)
    local eb = inputHandle._eb or inputHandle
    eb:SetFocus()
    eb._text = text
    eb._cursor = #text
    eb:_fire("OnTextChanged", true)
end

--- Presses Enter in an Input handle.
function M.pressEnter(inputHandle)
    local eb = inputHandle._eb or inputHandle
    eb:_fire("OnEnterPressed")
end

--- Presses Escape in an Input handle.
function M.pressEscape(inputHandle)
    local eb = inputHandle._eb or inputHandle
    eb:_fire("OnEscapePressed")
end

----------------------------------------------------------------------------------
-- Observation
----------------------------------------------------------------------------------

--- Records every emission of a UI signal on an object.
-- @param obj table  Component handle or container
-- @param signal string
-- @return table  { count, calls, last, args, reset() }
function M.signalSpy(obj, signal)
    local spy = { count = 0, calls = {} }
    spy.id = M.S:Connect(obj, signal, function(...)
        spy.count = spy.count + 1
        local args = { n = select("#", ...), ... }
        spy.calls[spy.count] = args
        spy.last = args
    end)
    function spy:reset()
        self.count = 0
        self.calls = {}
        self.last = nil
    end
    function spy:arg(i, callIndex)
        local call = self.calls[callIndex or self.count]
        return call and call[i]
    end
    return spy
end

--- Records every emission of an addon-wide event.
-- @param event string
-- @return table  { count, calls, last }
function M.eventSpy(event)
    local spy = { count = 0, calls = {} }
    local owner = "harness_spy_" .. event .. "_" .. tostring(math.random(1e9))
    spy.owner = owner
    M.SuuUI.Events:On(event, function(...)
        spy.count = spy.count + 1
        local args = { n = select("#", ...), ... }
        spy.calls[spy.count] = args
        spy.last = args
    end, owner)
    function spy:arg(i, callIndex)
        local call = self.calls[callIndex or self.count]
        return call and call[i]
    end
    return spy
end

--- Returns lines captured from SuuUI.Debug / print.
function M.debugLog() return state.debugLog end

----------------------------------------------------------------------------------
-- Geometry access
----------------------------------------------------------------------------------

--- Rect of a widget in top-down screen coordinates.
-- @param target table
-- @return table|nil  { left, top, width, height, right, bottom }
function M.box(target)
    return geometry.boxFromTop(M.frameOf(target), state.screenHeight)
end

--- Offset of a child's top-left from an ancestor's top-left.
-- dy grows downward, matching how the layout engine expresses padding and gaps.
-- @param child table
-- @param ancestor table
-- @return number, number  dx, dy
function M.offset(child, ancestor)
    return geometry.offsetFrom(M.frameOf(child), M.frameOf(ancestor))
end

----------------------------------------------------------------------------------
-- Clipping
--
-- `SetClipsChildren(true)` makes a frame a WINDOW: the client scissors its whole
-- descendant subtree to that frame's rect, so a child taller than the window draws only
-- the part that overlaps it. A shrinking window over a full-height body is how an
-- Accordion collapses, and with no clip its rows would draw straight over whatever sits
-- below.
--
-- These are QUERIES laid on top of the solver, which does not clip and must not start:
-- H.box still reports the rect a widget was ASSIGNED, because that is what the suite
-- measures — StackLayout sizes a progress fill at 0% deliberately, and dozens of specs
-- assert deliberately-hidden or deliberately-oversized children. So ask H.box what a
-- widget was given and H.visibleBox what would actually be drawn.
--
-- Clipping follows PARENTAGE, exactly as in the client: a frame merely ANCHORED to a
-- window is not inside it and is not clipped by it.
----------------------------------------------------------------------------------

-- Intersection of two boxes in the top-down screen space H.box reports (`top` grows
-- downward, so the surviving band starts at the LARGER top and ends at the smaller
-- bottom). Returns nil for an empty result: a widget with no overlap left draws nothing.
local function intersectBox(a, b)
    local left   = math.max(a.left, b.left)
    local right  = math.min(a.right, b.right)
    local top    = math.max(a.top, b.top)
    local bottom = math.min(a.bottom, b.bottom)
    if right <= left or bottom <= top then return nil end
    return {
        left = left, top = top,
        width = right - left, height = bottom - top,
        right = right, bottom = bottom,
    }
end

--- Whether a frame clips its children, i.e. what the client's DoesClipChildren() answers.
--
-- Regions (textures, font strings) have no children to clip, so they answer false rather
-- than raising — a spec can ask about anything it holds.
-- @param target table  Frame, region, component handle or container
-- @return bool
function M.clipsChildren(target)
    local f = M.frameOf(target)
    if not (f and f.DoesClipChildren) then return false end
    return f:DoesClipChildren()
end

--- The nearest ancestor clipping this widget, or nil when nothing does.
--
-- EXCLUSIVE of the widget itself, because that is the client's rule: SetClipsChildren
-- clips a frame's DESCENDANTS and never its own rect. So the window frame that clips a
-- body is not clipped by its own clip — H.clipAncestor(window) answers what clips the
-- window, and nil when it is free to draw its full rect. Ask H.clipsChildren(f) for the
-- other question, "does this frame clip what is inside it".
--
-- Walks the whole parent chain, so a clip several generations up still answers, and a
-- non-clipping frame in between is stepped over rather than ending the walk.
-- @param target table  Frame, region, component handle or container
-- @return table|nil  The clipping frame
function M.clipAncestor(target)
    local f = M.frameOf(target)
    if not f then return nil end
    local p = f:GetParent()
    while p do
        if M.clipsChildren(p) then return p end
        p = p:GetParent()
    end
    return nil
end

--- The part of a widget's box that would actually be drawn: its box intersected with
--- every clipping ancestor's box, so nested windows compose the way the client's scissor
--- rects do.
--
-- Same shape H.box returns, so anything reading a box reads this one too. Returns nil
-- when the widget is clipped away entirely, when it has no resolvable rect of its own,
-- and when a clipping ancestor has none — an ancestor with no rect draws nothing, so
-- nothing inside it draws either.
-- @param target table  Frame, region, component handle or container
-- @return table|nil  { left, top, width, height, right, bottom }
function M.visibleBox(target)
    local f = M.frameOf(target)
    if not f then return nil end
    local box = M.box(f)
    if not box then return nil end
    local p = f:GetParent()
    while p do
        if M.clipsChildren(p) then
            local window = M.box(p)
            if not window then return nil end
            box = intersectBox(box, window)
            if not box then return nil end
        end
        p = p:GetParent()
    end
    return box
end

--- Whether any part of a widget falls outside a clipping ancestor.
--
-- False when nothing clips it, and false for a widget with no resolvable rect: there is
-- no geometry to cut, and H.box already reports that case as nil.
-- @param target table  Frame, region, component handle or container
-- @param tol number  Edge tolerance in pixels, default 0.01
-- @return bool
function M.isClipped(target, tol)
    tol = tol or 0.01
    local f = M.frameOf(target)
    if not M.clipAncestor(f) then return false end
    local box = M.box(f)
    if not box then return false end
    local vis = M.visibleBox(f)
    if not vis then return true end
    return math.abs(vis.left - box.left) > tol
        or math.abs(vis.top - box.top) > tol
        or math.abs(vis.width - box.width) > tol
        or math.abs(vis.height - box.height) > tol
end

--- Measured text width using the harness font model. Use this instead of literals so
--- assertions stay valid if the model's ratios change.
-- @param text string
-- @param size number
-- @param path string  Optional font path; omitted uses the base metric model
-- @return number
function M.textWidth(text, size, path)
    return font.unbounded(text, size or M.token("fontSizeMd"), path)
end

--- The width the layout engine RESERVES for a string, as distinct from the width the
--- string measures. `TextMetrics.Box` adds one physical pixel on top of the metric,
--- because the client truncates with zero tolerance and its rendered extent need not
--- match the metric exactly. Assert against this wherever a font string's own box is
--- sized from its text — a `width = "auto"` child, a centred Divider label — and against
--- H.textWidth where a component measures text and then adds its own padding.
-- @param text string
-- @param size number
-- @param path string  Optional font path
-- @return number
function M.textBox(text, size, path)
    local w = M.textWidth(text, size, path)
    if w <= 0 then return 0 end
    return M.SuuUI.Pixel.Ceil(w + (M.SuuUI.Pixel.mult or 0))
end

--- Measured text height using the harness font model.
function M.textHeight(text, size, wrap, bound, path)
    local _, h = font.measure(text, size or M.token("fontSizeMd"), wrap, bound, false, path)
    return h
end

--- Single-line height at a font size.
function M.lineHeight(size, path)
    return font.lineHeight(size or M.token("fontSizeMd"), path)
end

--- Makes a font face loadable and gives the client a font object reporting it, the way
--- a locale client or a media addon adds one. The addon's GetFonts harvest can then see
--- it. Faces reset on every H.setup().
-- @param name string   Font object global name
-- @param path string   Font file path
-- @param ratios table  Optional { widthRatio, heightRatio }
-- @return string  The path
function M.addFont(name, path, ratios)
    ratios = ratios or {}
    font.addFace(path, ratios.widthRatio, ratios.heightRatio)
    M.wow.addFontObject(name, path)
    return path
end

--- Font path in force on a widget, component handle or region.
-- @param target table
-- @return string, number, string  path, size, flags
function M.fontOf(target)
    local f = M.frameOf(target)
    assert(f and f.GetFont, "harness: fontOf target has no GetFont")
    return f:GetFont()
end

require("harness.expect_layout")(M)

return M
