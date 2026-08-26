-- One action bar button: the client's own action system, wearing SuuUI's art.
--
-- Why this is attributes and not an onClick handler. Using an action is PROTECTED, so no
-- callback an addon writes can do it. The only route is the secure template: a Button
-- inheriting SecureActionButtonTemplate carries a `type` and an `action` attribute, and the
-- template's OWN click handler reads them and performs the action inside the client. This
-- component states those attributes and then gets out of the way -- it never sees the click
-- that matters. Components/UnitClickArea.lua is the same shape for targeting.
--
-- Four things about it are load-bearing:
--
--   * NEVER SetScript("OnClick"). The template installs the handler that performs the
--     action; replacing it breaks every button silently -- they still size, still take the
--     mouse, still report as shown. Observe through PostClick, which is the hook the
--     template offers for exactly this.
--   * RegisterForClicks is not optional. A Button fires for left-up alone until told
--     otherwise, so without it a right-click action never reaches the client. Pinned in
--     Tests/spec/00_harness_spec.lua after the spec for it failed.
--   * Attributes are stated ONCE, at construction. A frame built from a secure template is
--     protected and the client refuses SetAttribute on it in combat, which is why this
--     component exposes no way to re-point a live button. Paging is the state driver's job.
--   * THE SLOT IS READ FROM THE ATTRIBUTE, NEVER FROM A CACHED FIELD. This is the subtle
--     one. Bar 1 pages through six blocks of twelve, and the secure snippet that re-points
--     it rewrites `action` inside the secure environment -- where Lua cannot observe the
--     write. A button caching its slot in a local would keep drawing the spell it had
--     before the player changed stance. _slotNow() re-reads the attribute every refresh;
--     GetAttribute is a read and is never refused.
--
-- No border and no plate of its own: the A2 look is one glass plate under a whole grid with
-- hairline dividers between cells, so a per-button border would draw a second edge inside
-- the first. Components/ActionBarGrid.lua owns the surface.
local pairs, next, type, tonumber = pairs, next, type, tonumber
local ipairs, tostring = ipairs, tostring
local format, gsub, upper = string.format, string.gsub, string.upper
local S = SuuUI.UISignals

-- The longest cooldown that is STILL ONLY THE GLOBAL COOLDOWN, in seconds.
--
-- Why a filter exists at all: GetActionCooldown reports the GCD on EVERY slot at once, so an
-- unfiltered countdown puts a number on all ninety-six buttons on every single cast. What a player
-- asked for is the remaining cooldown of an ability that actually has one.
--
-- THE TEST IS ON THE COOLDOWN'S DURATION, NEVER ON ITS REMAINING TIME, and that distinction is the
-- whole reason this works: a six-second cooldown keeps its number all the way down to 0.1s, because
-- its DURATION is six regardless of how little is left, while a 1.5-second one is the global
-- cooldown and never draws at all.
--
-- 1.5 is not invented here. ElvUI ships `minDuration = 1500` (ms) as its cooldown default on this
-- exact client and hands it to the client's own SetMinimumCountdownDuration, so this is the same
-- line every other bar addon on the machine draws. It also covers the 1.0s GCD some energy
-- abilities use, since that sits below the ceiling rather than beside it.
--
-- The price is that a genuine cooldown of 1.5s or shorter shows no number. Nothing in this
-- expansion has one, and a player who wants the GCD counted is asking for the noise this removes.
local GCD_MAX_DURATION = 1.5

---------------------------------------------------------------------------
-- Shared event frame
---------------------------------------------------------------------------
-- ONE frame carrying the union of every action event, for every button in the addon,
-- registered only while at least one button exists. Sixty buttons with an event frame each
-- would be sixty frames and sixty dispatches for the same six events -- the shape
-- Plugins/DataBar/DataBarWidget.lua uses, and for the same reason.

-- WHAT A "KIND" IS, and why pet lives here rather than in a component of its own.
--
-- A pet button uses the SAME secure mechanism as an action slot: `SecureActionButtonTemplate` with
-- `type="pet"` and the slot index in the `action` attribute. That is not a guess -- it is what
-- LibActionButton-1.0 does inside a live secure snippet on this client:
--
--     self:SetAttribute("type", type)                          -- type can be "pet"
--     local action_field = (type == "pet") and "action" or type
--     self:SetAttribute(action_field, action)
--
-- Because the attribute NAME is the same, `_slotNow()` needs no change at all, and neither does the
-- press-versus-release gate. That gate is the reason this is a `kind` and not a `PetButton.lua`: it
-- was got wrong once and produced a button that looked perfect and did nothing, so it must exist in
-- exactly ONE place.
--
-- The stance bar could NOT share it -- a stance button has no secure attribute whatsoever -- which is
-- why that one is a separate component. Pet can share, so it does.
local PROVIDERS = {
    action = {
        attrType   = "action",
        drag       = true,
        has        = function(i) return HasAction(i) end,
        texture    = function(i) return GetActionTexture(i) end,
        cooldown   = function(i) return GetActionCooldown(i) end,
        count      = function(i) return GetActionCount(i) end,
        text       = function(i) return GetActionText(i) end,
        usable     = function(i) return IsUsableAction(i) end,
        inRange    = function(i) return IsActionInRange(i) end,
        current    = function(i) return IsCurrentAction(i) end,
        autoRepeat = function(i) return IsAutoRepeatAction(i) end,
        autocast   = nil,
        tooltip    = function(tt, i) tt:SetAction(i) end,
    },
    pet = {
        attrType = "pet",
        -- Drag is DISABLED for pet, matching LibActionButton, which excludes both action and pet
        -- from its drag path. A pet slot's contents are not the player's to rearrange.
        drag     = false,
        has      = function(i) return GetPetActionInfo(i) ~= nil end,
        texture  = function(i)
            local _, texture, isToken = GetPetActionInfo(i)
            if not texture then return nil end
            -- THE TRAP. With isToken true, `texture` is the NAME OF A GLOBAL rather than a path,
            -- and the same goes for the name. Resolving it is the consumer's job -- miss it and
            -- Attack, Follow and Stay draw blank icons, which is the most commonly missed detail
            -- in a pet bar.
            if isToken then return _G[texture] end
            return texture
        end,
        -- Two returns from the client, not three. A third of 1 is supplied so the shared painter's
        -- `enable ~= 0` check reads as "running" whenever there is a duration.
        cooldown = function(i)
            local start, duration = GetPetActionCooldown(i)
            return start, duration, 1
        end,
        -- A pet action has no charge count and no macro name. Answered rather than left nil so the
        -- shared painters need no per-kind branch.
        count      = function() return 0 end,
        text       = function() return nil end,
        usable     = function(i)
            -- TWO mechanisms, and they must not be collapsed: a pet whose bar is unusable at all
            -- greys every icon, while a single unusable slot greys only itself.
            if type(PetHasActionBar) == "function" and not PetHasActionBar() then
                return false, false
            end
            return GetPetActionSlotUsable(i), false
        end,
        -- Range is not a question for a pet command, and nil is how the shared painter says so.
        inRange    = function() return nil end,
        current    = function(i)
            local name, _, _, isActive = GetPetActionInfo(i)
            -- Follow is reported active whenever the pet is following, which is almost always, so
            -- showing it as the current action would leave that button permanently lit. ElvUI
            -- excludes it by the same token name.
            if name == "PET_ACTION_FOLLOW" then return false end
            return isActive
        end,
        autoRepeat = function() return false end,
        -- allowed, enabled. The overlay shows on `allowed`; the ring lights on `enabled`.
        autocast   = function(i)
            local _, _, _, _, allowed, enabled = GetPetActionInfo(i)
            return allowed, enabled
        end,
        -- NO Lua autocast toggle here. `TogglePetAutocast` is PROTECTED: calling it from a
        -- PostClick hook -- which does run in a hardware-event context -- raised
        --   "SuuUI has been blocked from an action only available to the Blizzard UI"
        -- in game. That is the second protected function this phase assumed was callable, after
        -- CastShapeshiftForm.
        --
        -- Right-click is handled instead by FORWARDING it into Blizzard's own pet button inside the
        -- secure environment -- see the `type2` / `clickbutton2` pair in the constructor. Blizzard's
        -- handler is trusted, so it may call the protected function; ours never has to.
        tooltip    = function(tt, i)
            if type(tt.SetPetAction) == "function" then tt:SetPetAction(i) end
        end,
    },
}

local EVENTS = {
    "ACTIONBAR_SLOT_CHANGED",
    "ACTIONBAR_UPDATE_COOLDOWN",
    "ACTIONBAR_UPDATE_USABLE",
    "ACTIONBAR_UPDATE_STATE",
    "ACTIONBAR_PAGE_CHANGED",
    "SPELL_UPDATE_COOLDOWN",
    "UPDATE_SHAPESHIFT_FORM",
    "UPDATE_BINDINGS",
    "PLAYER_ENTERING_WORLD",
}

-- Pet events, kept separate so the dispatch can repaint ONLY pet buttons on them. Registering them
-- in the shared list is fine; refreshing all ninety-six action buttons on every PET_BAR_UPDATE is
-- not. Unit filters are applied in the dispatch, not at registration -- UNIT_PET carries "player"
-- and UNIT_FLAGS carries "pet", and getting those the wrong way round silently kills every update.
local PET_EVENTS = {
    PET_BAR_UPDATE          = true,
    PET_BAR_UPDATE_COOLDOWN = true,
    PET_UI_UPDATE           = true,
    UNIT_PET                = "player",
    UNIT_FLAGS              = "pet",
    PLAYER_CONTROL_GAINED   = true,
    PLAYER_CONTROL_LOST     = true,
    SPELLS_CHANGED          = true,
}

-- Every live button, and the slot index over it.
--
-- The index is slot -> SET of buttons, not slot -> button, and that is a consequence of what
-- Phase 0 measured rather than defensive generality: bar 1's pages 3..6 are exactly the
-- slots the four multibars own, so a paged bar 1 and a fixed bar 3 legitimately address one
-- slot at the same time. A one-button-per-slot map would repaint whichever happened to be
-- found and leave the other showing a stale spell.
local live    = {}
local bySlot  = {}
local evt

-- Buttons whose cooldown the shared ticker is counting down.
--
-- Membership is decided by _setCooldownWindow off the client's own cooldown events, and the GCD is
-- filtered THERE rather than in the paint -- so a cast that puts the global cooldown on every slot
-- adds nothing to this set, and an idle bar walks nothing at all. The readout costs exactly as much
-- as there are real cooldowns running.
local onCooldown = {}

local function indexSlot(handle, slot)
    if not slot then return end
    local set = bySlot[slot]
    if not set then
        set = {}
        bySlot[slot] = set
    end
    set[handle] = true
end

local function deindexSlot(handle, slot)
    local set = slot and bySlot[slot]
    if not set then return end
    set[handle] = nil
    if next(set) == nil then bySlot[slot] = nil end
end

-- There is deliberately no rebuild-the-whole-index pass. It looks as though a page change
-- would need one, and an earlier draft had it -- but Refresh() re-reads the slot from the
-- ATTRIBUTE and fixes its own index entry when it moved, so a pass that refreshes every
-- button has already rebuilt the index by the time it finishes. Mutation testing is what
-- exposed the redundancy: deleting the rebuild changed no assertion, because the one
-- mechanism that keeps the index honest is the one in Refresh.

local function onEvent(_, event, arg1)
    -- PET EVENTS FIRST, and they repaint ONLY pet buttons. A shared frame is right -- one frame for
    -- every button in the addon -- but refreshing all ninety-six action buttons on every
    -- PET_BAR_UPDATE would make a hunter's pet cost the whole bar set a repaint.
    local petFilter = PET_EVENTS[event]
    if petFilter then
        -- The unit filter is applied HERE rather than at registration, because the client sends
        -- UNIT_PET for "player" and UNIT_FLAGS for "pet". Reversing those silently kills every
        -- update, which is why each is spelled out in PET_EVENTS rather than inferred.
        if type(petFilter) == "string" and arg1 ~= petFilter then return end
        for handle in pairs(live) do
            if handle._kind == "pet" then handle:Refresh() end
        end
        return
    end

    if event == "ACTIONBAR_SLOT_CHANGED" then
        -- The client fires this with no slot, or with 0, to mean "everything changed".
        local slot = tonumber(arg1)
        if slot and slot ~= 0 then
            local set = bySlot[slot]
            if set then
                for handle in pairs(set) do handle:Refresh() end
            end
            return
        end
        for handle in pairs(live) do handle:Refresh() end

    elseif event == "ACTIONBAR_PAGE_CHANGED" or event == "UPDATE_SHAPESHIFT_FORM"
        or event == "PLAYER_ENTERING_WORLD" then
        -- The slot under each button may have moved. A full refresh re-reads every
        -- attribute and re-indexes as it goes.
        for handle in pairs(live) do handle:Refresh() end

    elseif event == "ACTIONBAR_UPDATE_COOLDOWN" or event == "SPELL_UPDATE_COOLDOWN" then
        for handle in pairs(live) do handle:_paintCooldown() end

    elseif event == "ACTIONBAR_UPDATE_USABLE" then
        for handle in pairs(live) do handle:_paintUsable() end

    elseif event == "ACTIONBAR_UPDATE_STATE" then
        for handle in pairs(live) do handle:_readState() end

    elseif event == "UPDATE_BINDINGS" then
        for handle in pairs(live) do handle:_paintHotkey() end
    end
end

local function syncEventFrame()
    if next(live) ~= nil then
        if not evt then
            evt = CreateFrame("Frame")
            evt:SetScript("OnEvent", onEvent)
        end
        for _, e in ipairs(EVENTS) do
            -- pcall because an event absent on this client generation must not take the
            -- whole bar down; DataBarWidget registers the same way.
            pcall(evt.RegisterEvent, evt, e)
        end
        -- Registered unconditionally rather than only when a pet button exists: the set is small,
        -- and gating registration on the live set would mean re-registering every time the last pet
        -- button went away and came back.
        for e in pairs(PET_EVENTS) do
            pcall(evt.RegisterEvent, evt, e)
        end
    elseif evt then
        evt:UnregisterAllEvents()
    end
end

---------------------------------------------------------------------------
-- Shared range ticker
---------------------------------------------------------------------------
-- Nothing announces that a target walked out of range, so range is polled -- and polled on
-- ONE OnUpdate for every button in the addon, registered only while at least one button
-- exists. A per-button OnUpdate is sixty scripts running every frame forever, which is the
-- cost the plan singles out. Same shape as AuraBand's duration ticker.

-- Ten times a second. Not a design token: this is a poll rate for a fact the client never
-- announces, and it matches the client's own TOOLTIP_UPDATE_TIME convention closely enough
-- that a player never sees a stale range tint.
local RANGE_THROTTLE = 0.1

local rangeAccum, rangeTicker = 0, nil

local function onRangeTick(_, elapsed)
    rangeAccum = rangeAccum + elapsed
    if rangeAccum < RANGE_THROTTLE then return end
    rangeAccum = 0
    for handle in pairs(live) do
        handle:_paintRange()
    end
    -- The cooldown countdown rides THIS tick rather than adding a second OnUpdate frame, and the
    -- throttle already suits it exactly: Readout.Duration's decimal band is tenths, so ten times a
    -- second is precisely the rate at which the string it produces can change. Only buttons with a
    -- real cooldown running are walked -- see `onCooldown` -- so an idle bar pays a single `next`.
    for handle in pairs(onCooldown) do
        handle:_paintCooldownText()
    end
end

local function syncRangeTicker()
    if next(live) ~= nil then
        if not rangeTicker then rangeTicker = CreateFrame("Frame") end
        rangeTicker:SetScript("OnUpdate", onRangeTick)
    elseif rangeTicker then
        rangeTicker:SetScript("OnUpdate", nil)
    end
end

---------------------------------------------------------------------------
-- Hotkey abbreviation
---------------------------------------------------------------------------
-- The abbreviation lives IN the component for the same reason AuraIcon owns its duration
-- format: every bar would otherwise write the same substitutions. "SHIFT-BUTTON4" has to
-- become something that fits in the corner of a 32-unit cell, and the client's own binding
-- strings are far too long for that.

local KEY_SHORT = {
    ["SHIFT%-"] = "s", ["CTRL%-"] = "c", ["ALT%-"] = "a",
    ["BUTTON"] = "m", ["MOUSEWHEELUP"] = "wu", ["MOUSEWHEELDOWN"] = "wd",
    ["NUMPAD"] = "n", ["PAGEUP"] = "pu", ["PAGEDOWN"] = "pd",
    ["SPACE"] = "sp", ["INSERT"] = "ins", ["HOME"] = "hm", ["DELETE"] = "del",
    ["CAPSLOCK"] = "cl",
}

local function abbreviateKey(key)
    if not key or key == "" then return nil end
    local out = key
    for pattern, short in pairs(KEY_SHORT) do
        out = gsub(out, pattern, short)
    end
    return upper(out)
end

-- Whether this client acts on the press rather than the release, as the player has it set.
--
-- Read from the CVar rather than assumed, and read DEFENSIVELY: GetCVarBool is absent on some
-- client generations and the CVar itself may not exist, in which case the release is the safe
-- answer -- it is what every client did before the setting was introduced.
local function useKeyDown()
    if type(GetCVarBool) ~= "function" then return false end
    local ok, on = pcall(GetCVarBool, "ActionButtonUseKeyDown")
    return (ok and on) and true or false
end

---------------------------------------------------------------------------
-- Component
---------------------------------------------------------------------------

local ActionButtonMeta = {}
ActionButtonMeta.__index = ActionButtonMeta

--- The slot this button currently points at, read from the attribute rather than a field.
--
-- See the note at the top of this file: a secure snippet re-points `action` where Lua cannot
-- see it, so a cached value goes stale exactly when a player changes stance mid-fight.
-- @return number|nil
function ActionButtonMeta:_slotNow()
    return tonumber(self._f:GetAttribute("action"))
end

function ActionButtonMeta:_paintIcon()
    local slot = self:_slotNow()
    local p = self._p
    local texture = slot and p.has(slot) and p.texture(slot) or nil
    -- Clears the TEXTURE rather than hiding the icon frame, and that is not a style choice.
    -- Hiding a frame inside a protected button is refused in combat -- and an action appearing
    -- or disappearing mid-fight is the ordinary case, so the hide would fire exactly when it
    -- cannot land, costing the player a chat error every time. A texture with no file draws
    -- nothing and costs no protected call. Found by the lockdown model: 80 refusals.
    --
    -- The button also stays live for an empty slot on purpose: a player drags an action ONTO
    -- an empty cell, so it still has to take the mouse.
    self._iconComp:SetIcon(texture)
end

function ActionButtonMeta:_paintCooldown()
    local slot = self:_slotNow()
    if not (slot and self._p.has(slot)) then
        self._cooldown:SetCooldown(0, 0)
        self:_setCooldownWindow(nil, nil)
        return
    end
    local start, duration, enable = self._p.cooldown(slot)
    if enable and enable ~= 0 and duration and duration > 0 then
        self._cooldown:SetCooldown(start, duration)
        self:_setCooldownWindow(start, duration)
    else
        self._cooldown:SetCooldown(0, 0)
        self:_setCooldownWindow(nil, nil)
    end
end

--- Records the window the countdown reads from, and joins or leaves the shared ticker.
--
-- THE SWIPE AND THE NUMBER DELIBERATELY DISAGREE ABOUT THE GCD. The swipe takes every cooldown the
-- client reports, global one included, because a sweep across the whole bar is how a player reads
-- "everything is briefly unavailable" and it costs no text. The number is filtered to real
-- cooldowns, because ninety-six two-digit readouts flashing on every cast is noise rather than
-- information. Same event, two readings, on purpose -- see GCD_MAX_DURATION.
--
-- The filter lives here rather than in the paint so a GCD never joins `onCooldown` in the first
-- place: gating inside _paintCooldownText would leave every button on the ticker for the GCD's
-- duration, doing arithmetic to decide to draw nothing.
function ActionButtonMeta:_setCooldownWindow(start, duration)
    if start and duration and duration > GCD_MAX_DURATION then
        self._cdStart, self._cdDuration = start, duration
        onCooldown[self] = true
    else
        self._cdStart, self._cdDuration = nil, nil
        onCooldown[self] = nil
    end
    self:_paintCooldownText()
end

--- Draws the remaining cooldown as a number, and retires the button when it expires.
function ActionButtonMeta:_paintCooldownText()
    local text = self._cooldownText
    if not text then return end

    if not (self._cdStart and self._cdDuration) then
        self._cdText = nil
        text:Hide()
        return
    end

    local remaining = self._cdStart + self._cdDuration - GetTime()
    if remaining <= 0 then
        -- EXPIRED, and leaving the ticker here is the point rather than tidiness: the client
        -- announces a cooldown STARTING and does not reliably announce one finishing, so nothing
        -- else would ever drop this button from the walked set.
        self._cdStart, self._cdDuration = nil, nil
        onCooldown[self] = nil
        self._cdText = nil
        text:Hide()
        return
    end

    -- The toggle is checked AFTER the expiry branch, and that order is load-bearing for ticker
    -- hygiene rather than for anything on screen. Checked first, a cooldown that runs out while the
    -- readout is switched off would never reach the branch above that retires its button, so the
    -- ticker would keep walking it until some later cooldown event happened to clear the window.
    --
    -- Note what the order does NOT buy: both orders keep `_cdStart` intact, so switching the
    -- readout back on mid-cooldown shows the number either way. A mutation moving this check to the
    -- top of the function survived a spec asserting exactly that, which is why the spec now asserts
    -- the walked SET as well as the string.
    if not self._showCooldownText then
        self._cdText = nil
        text:Hide()
        return
    end

    local str = SuuUI.Readout.Duration(remaining)
    -- An unchanged write is dropped: this runs ten times a second per cooling button while the
    -- string only moves once a second above the decimal band. Same guard StatusBar's overlay
    -- readouts and DataField both carry, and for the same reason -- a re-measure per tick per
    -- button is the entire cost of the feature.
    if str ~= self._cdText then
        self._cdText = str
        text:SetText(str)
    end
    text:Show()
end

function ActionButtonMeta:_paintCount()
    if not self._countText then return end
    local slot = self:_slotNow()
    local count = slot and self._p.has(slot) and self._p.count(slot) or 0
    -- Above one, matching AuraIcon's stack threshold: the client reports 1 for a single
    -- charge and a "1" in the corner of every consumable is noise.
    if self._showCount and count and count > 1 then
        self._countText:SetText(tostring(count))
        self._countText:Show()
    else
        self._countText:Hide()
    end
    self:_reserveCountColumn()
end

--- Keeps the macro name clear of the count's corner.
--
-- Centring the macro name does NOT achieve this, which is what the code claimed for a long time:
-- a name wide enough spreads out of the centre in both directions and straight into the count.
-- Measured on a 36-unit button, a macro name occupied x 5..28 while the count sat at 23..30, on
-- the same row -- the two drew through each other. Its own spec asserted they must not and could
-- not fail, because H.expectNoOverlap was being called with two positional arguments instead of
-- an array.
--
-- The column is only reserved while the count is actually SHOWN. Reserving it permanently would
-- narrow every macro name on the bar for a stack size that is not there -- and most slots have no
-- count at all.
function ActionButtonMeta:_reserveCountColumn()
    if not (self._macroText and self._countText and self._overlayBox) then return end
    local pad = SuuUI.Theme:GetToken("spaceXxs") or 2
    local right = pad
    if self._countText:IsShown() then
        right = pad + (self._countText:GetWidth() or 0) + pad
    end
    self._overlayBox:SetChildProps(self._macroText, {
        align = "center", valign = "end", inset = { bottom = pad, right = right },
    })
end

function ActionButtonMeta:_paintMacroText()
    if not self._macroText then return end
    local slot = self:_slotNow()
    local text = slot and self._p.has(slot) and self._p.text(slot) or nil
    -- nil for a spell or an item -- which is why GetActionText cannot be used to decide
    -- whether the slot is occupied. HasAction answers that.
    if self._showMacroText and text and text ~= "" then
        self._macroText:SetText(text)
        self._macroText:Show()
    else
        self._macroText:Hide()
    end
    -- Both paths, because either readout changing moves the boundary between them.
    self:_reserveCountColumn()
end

function ActionButtonMeta:_paintHotkey()
    if not self._hotkeyText then return end
    local command = self._binding
    local key = command and GetBindingKey(command) or nil
    local short = abbreviateKey(key)
    if self._showHotkey and short then
        self._hotkeyText:SetText(short)
        self._hotkeyText:Show()
    else
        self._hotkeyText:Hide()
    end
end

-- The two tints share one texture, so they are applied in one place: range is checked last
-- because out of range is the more urgent reading -- a spell you cannot afford AND cannot
-- reach should say "too far", since walking closer is the action a player takes next.
function ActionButtonMeta:_applyTint()
    local icon = self._iconComp
    if not icon then return end

    if self._outOfRange then
        icon:SetArtDesaturated(false)
        icon:SetArtTint("colorDanger")
        return
    end

    if not self._usable then
        -- Fully unusable: desaturated AND dimmed.
        icon:SetArtDesaturated(true)
        icon:SetArtTint(nil, SuuUI.Theme:GetToken("opacityDisabled") or 0.4)
        return
    end

    if self._noResource then
        -- Short of mana/rage/energy: desaturated but NOT dimmed, so it reads as a different
        -- state from "cannot be used at all" without inventing a colour token. Blizzard
        -- tints this blue; matching that exactly would need a new palette entry.
        icon:SetArtDesaturated(true)
        icon:SetArtTint(nil)
        return
    end

    icon:SetArtDesaturated(false)
    icon:SetArtTint(nil)
end

function ActionButtonMeta:_paintUsable()
    local slot = self:_slotNow()
    if not (slot and self._p.has(slot)) then
        self._usable, self._noResource = true, false
        self:_applyTint()
        return
    end
    local usable, noMana = self._p.usable(slot)
    self._usable = usable and true or false
    self._noResource = noMana and true or false
    self:_applyTint()
end

function ActionButtonMeta:_paintRange()
    local slot = self:_slotNow()
    local inRange
    if slot and self._p.has(slot) then
        inRange = self._p.inRange(slot)
    end
    -- nil means range is not a question for this action -- a self buff, a macro with no
    -- target. That is NOT the same as being out of range, and painting it red would put a
    -- danger tint on every self-cast on the bar.
    local out = (inRange == false)
    if out == self._outOfRange then return end
    self._outOfRange = out
    self:_applyTint()
end

--- Draws whether a pet command is set to cast itself.
--
-- Only `autoCastEnabled` gets a visual. `autoCastAllowed` merely means the command COULD autocast,
-- which is true of most of them and would light up half the bar for no information -- what a player
-- needs to see is which ones actually are.
--
-- A ring rather than Blizzard's spinning shine: nothing in SuuUI animates a border, and the shine is
-- a Blizzard texture this component does not own.
--
-- GOLD, NOT ACCENT, and that was reported rather than designed. The first version used the accent
-- colour for this AND for the active-mode bar, and a player looking at a pet button could not tell
-- the two apart -- the bottom bar read as a broken border. Two indicators in one colour is one
-- indicator as far as a reader is concerned.
--
-- Gold specifically because Blizzard's own autocast indicator is a golden shine, so it is the colour a
-- WoW player already reads as "this casts itself". Accent stays reserved for "this is the live one",
-- which is what it means on the stance bar too -- one vocabulary across both.
function ActionButtonMeta:_paintAutocast()
    if not self._overlay then return end
    if not self._p.autocast then return end
    local slot = self:_slotNow()
    local enabled = false
    if slot and self._p.has(slot) then
        local _, on = self._p.autocast(slot)
        enabled = on and true or false
    end
    SuuUI.Backdrop.SetBorder(self._overlay, enabled and "colorWarning" or false)
end

--- Draws whether this slot is the active one.
--
-- For a pet that is its MODE (Passive / Defensive / Aggressive) or a toggled command; for an action
-- slot it is a channelled spell or a live aura. Same state, same indicator, one code path.
function ActionButtonMeta:_paintCurrent()
    if not self._currentBar then return end
    if self._current then
        local c = SuuUI.Theme:GetToken("colorAccent")
        if c then self._currentBar:SetColorTexture(c[1], c[2], c[3], c[4] or 1) end
        self._currentBar:Show()
    else
        self._currentBar:Hide()
    end
end

function ActionButtonMeta:_readState()
    local slot = self:_slotNow()
    if not (slot and self._p.has(slot)) then
        self._current, self._autoRepeat = false, false
        self:_paintCurrent()
        return
    end
    self._current = self._p.current(slot) and true or false
    self._autoRepeat = self._p.autoRepeat(slot) and true or false
    self:_paintCurrent()
end

---------------------------------------------------------------------------
-- Tooltip
---------------------------------------------------------------------------
-- OWNED BY THE COMPONENT, which is a deliberate departure from AuraIcon. AuraIcon emits
-- MOUSE_ENTER and lets its owner wire a tooltip, because it does not know which aura it shows and
-- the caller does. An action button DOES know: its slot is the whole answer, and
-- GameTooltip:SetAction builds the entire tooltip from it -- name, cost, range, cast time, the
-- lot. Nothing is left for an owner to supply.
--
-- It is owned here because the alternative was tried and failed. Phase 4a shipped this button
-- emitting the signals and nobody wired them, so an action bar with no tooltips reached the game.
-- A tooltip is not an optional garnish on an action button; leaving it to every owner invites
-- exactly that omission.
--
-- GameTooltip directly, not Components/Tooltip: reproducing the client's own spell tooltip
-- formatting is not on the table, and this is the same sanctioned client-widget exception the
-- Cooldown frame already takes.

function ActionButtonMeta:_showTooltip()
    if not self._tooltip then return end
    if type(GameTooltip) ~= "table" then return end
    local slot = self:_slotNow()
    -- Nothing to say about an empty cell, and a setter on one shows an empty frame rather than
    -- nothing at all.
    if not (slot and self._p.has(slot)) then return end
    GameTooltip:SetOwner(self._f, self._tooltipAnchor)
    -- Through the provider: an action slot uses SetAction, a pet slot SetPetAction. The pet setter
    -- is guarded inside the provider, so an absent one costs a tooltip rather than an error.
    self._p.tooltip(GameTooltip, slot)
    GameTooltip:Show()
end

function ActionButtonMeta:_hideTooltip()
    if not self._tooltip then return end
    if type(GameTooltip) ~= "table" then return end
    -- Only if it is OURS. A tooltip the player moved onto something else in the same frame must
    -- not be hidden out from under that thing.
    if GameTooltip.GetOwner and GameTooltip:GetOwner() ~= self._f then return end
    GameTooltip:Hide()
end

---------------------------------------------------------------------------
-- Public API
---------------------------------------------------------------------------

--- Re-reads everything about the slot and repaints.
function ActionButtonMeta:Refresh()
    local slot = self:_slotNow()
    -- Keep the shared index honest even when a refresh arrives without a page event.
    if slot ~= self._indexed then
        deindexSlot(self, self._indexed)
        self._indexed = slot
        indexSlot(self, slot)
    end
    self:_paintIcon()
    self:_paintCooldown()
    self:_paintCount()
    self:_paintMacroText()
    self:_paintHotkey()
    self:_paintUsable()
    self:_paintAutocast()
    self:_readState()
    -- Range last: _applyTint reads _usable, which _paintUsable has just settled.
    self._outOfRange = nil
    self:_paintRange()
end

--- The slot this button points at right now.
-- @return number|nil
function ActionButtonMeta:GetSlot()
    return self:_slotNow()
end

--- Whether the slot holds anything.
-- @return bool
function ActionButtonMeta:HasAction()
    local slot = self:_slotNow()
    return (slot and self._p.has(slot)) and true or false
end

--- Whether the client reports this action as the one currently being used.
--- Read but deliberately NOT rendered yet: the "this is active" treatment belongs on the
--- grid's glass plate, which does not exist until ActionBarGrid.
-- @return bool
function ActionButtonMeta:IsCurrent()
    return self._current == true
end

--- Whether this action is auto-repeating (auto-shot, wand). Also not rendered yet.
-- @return bool
function ActionButtonMeta:IsAutoRepeat()
    return self._autoRepeat == true
end

--- Whether the action is out of range of the current target.
-- @return bool
function ActionButtonMeta:IsOutOfRange()
    return self._outOfRange == true
end

--- Shows or hides the hotkey readout.
-- @param show bool
function ActionButtonMeta:SetShowHotkey(show)
    self._showHotkey = show ~= false
    self:_paintHotkey()
end

--- Shows or hides the macro name readout.
-- @param show bool
function ActionButtonMeta:SetShowMacroText(show)
    self._showMacroText = show ~= false
    self:_paintMacroText()
end

--- Shows or hides the stack count readout.
-- @param show bool
function ActionButtonMeta:SetShowCount(show)
    self._showCount = show ~= false
    self:_paintCount()
end

--- Shows or hides the remaining-cooldown number.
---
--- Only abilities with a cooldown of their own ever carry one; the global cooldown is filtered out
--- before a button joins the ticker. See GCD_MAX_DURATION.
-- @param show bool
function ActionButtonMeta:SetShowCooldownText(show)
    self._showCooldownText = show ~= false
    self:_paintCooldownText()
end

--- Sets the button's side. Called by its grid when the size setting changes.
---
--- A protected frame, so this is refused in combat like any other geometry -- the CALLER owns
--- the deferral, because it is the caller that knows the whole grid has to move together.
--- ActionBarGrid does it; see its header.
-- @param w number
-- @param h number
function ActionButtonMeta:SetSize(w, h)
    self._f:SetSize(w, h)
end

--- The binding command whose key this button displays, e.g. "ACTIONBUTTON3".
--- Set at construction; changing it re-reads the key but never touches an attribute.
-- @param command string|nil
function ActionButtonMeta:SetBinding(command)
    self._binding = command
    self:_paintHotkey()
end

function ActionButtonMeta:ApplyTheme()
    self:_paintCurrent()
    self._iconComp:ApplyTheme()
    self:_applyCooldownInset()
    self:_applyTint()
end

-- How far the cooldown sits inside the frame. A child frame draws above every layer of its
-- parent, so a full-bleed cooldown would paint over the grid's hairline divider at the cell
-- edge. Re-derived on a theme change because borderWidth is a token.
function ActionButtonMeta:_applyCooldownInset()
    local inset = SuuUI.Pixel.Line(SuuUI.Theme:GetToken("borderWidth") or 1)
    if self._cdProps.inset ~= inset then
        self._cdProps.inset = inset
        self._box:SetChildProps(self._cooldown, self._cdProps)
    end
end

--- Releases the button.
--
-- Attributes are left where they are: the frame is about to be hidden and dropped, and
-- clearing an attribute on a protected frame is one more call the client can refuse.
function ActionButtonMeta:Destroy()
    S:DisconnectAll(self)
    SuuUI.Events:Off("SUUUI_THEME_CHANGED", self._eid)
    deindexSlot(self, self._indexed)
    live[self] = nil
    -- Left in `onCooldown` this handle would be walked by the ticker after its frame is gone.
    onCooldown[self] = nil
    -- Both drop to nothing once the last button goes, rather than leaving a registered
    -- OnUpdate and nine events running for no one.
    syncRangeTicker()
    syncEventFrame()
    if self._countText then self._countText:Destroy() end
    if self._macroText then self._macroText:Destroy() end
    if self._hotkeyText then self._hotkeyText:Destroy() end
    if self._cooldownText then self._cooldownText:Destroy() end
    self._iconComp:Destroy()
    self._box:Destroy()
    self._f:Hide()
end

-- Fills in GetWidth, GetHeight, IsShown, GetFrame, Show, Hide.
SuuUI.Components.InstallBase(ActionButtonMeta, "_f")

-- Deliberately NO SetEnabled and no InstallEnable, for the reason UnitClickArea gives:
-- disabling means dropping mouse input, and that is a call the client refuses on a protected
-- frame in combat. A SetEnabled that cannot be honoured exactly when it matters is worse
-- than none -- Dependency.Bind's `if target.SetEnabled` guard would pass while nothing was
-- actually inert. An action that should not be used renders as unusable instead.

---------------------------------------------------------------------------
-- Constructor
---------------------------------------------------------------------------

--- Creates one secure action button.
--
-- Emits: CLICKED (button), MOUSE_ENTER, MOUSE_LEAVE, SIZE_CHANGED.
--
-- @param props table  { slot, size, binding, showHotkey, showMacroText, showCount,
--                       tooltip, tooltipAnchor, name }
--   slot:          the action slot, 1..72 on this client. Required.
--   size:          square side. Required -- a button's size is a PLUGIN SETTING, not a
--                  theme token, so the component does not invent a default for it.
--   binding:       binding command for the hotkey readout, e.g. "ACTIONBUTTON3"
--   showHotkey:    default true
--   showMacroText: default true
--   showCount:     default true
--   showCooldownText: default true. The remaining cooldown as a number, centred. Abilities with a
--                  cooldown of their own only -- the global cooldown never draws one.
--   tooltip:       show the client's action tooltip on hover (default true)
--   tooltipAnchor: GameTooltip anchor point (default "ANCHOR_RIGHT")
--   name:          optional global frame name, so /framestack and click-casting addons
--                  can name it
-- @param parent frame
-- @return table  ActionButton handle
function SuuUI.Components.ActionButton(props, parent)
    props = props or {}
    assert(type(props.slot) == "number", "SuuUI: ActionButton needs an action slot")
    assert(type(props.size) == "number", "SuuUI: ActionButton needs a size")

    local T = SuuUI.Theme

    -- A Button, because only a button carries the secure template's click handler.
    local provider = PROVIDERS[props.kind or "action"]
    assert(provider, "SuuUI: ActionButton unknown kind '" .. tostring(props.kind) .. "'")

    local f = CreateFrame("Button", props.name, parent, "SecureActionButtonTemplate")
    f:SetSize(props.size, props.size)
    f:EnableMouse(true)
    -- BOTH DOWN AND UP, and this is the difference between a button that works and one that looks
    -- perfect and does nothing.
    --
    -- This client drives action buttons on the DOWN event: Blizzard's own ActionButton1 carries an
    -- OnMouseDown handler, and the secure OnClick handler compares the `down` flag it is given
    -- against `useOnKeyDown` and RETURNS EARLY when they disagree. Registered for AnyUp alone the
    -- handler fired with down = false, disagreed, and bailed -- with the template, the attributes,
    -- the mouse and the tooltip all correct, which is exactly why it survived a green suite and an
    -- in-game session. Dragging kept working throughout, because drag never goes through that
    -- handler; that is what narrowed it down.
    --
    -- Registering both is what LibActionButton-1.0 does for this client family, and it is safe
    -- rather than double-firing precisely BECAUSE the handler checks `down`: whichever event
    -- disagrees with useOnKeyDown is discarded, so one physical click yields exactly one action. On
    -- an older client whose handler ignored `down` the same registration WOULD fire twice, which is
    -- why the library gates it on the client family.
    -- ONE PHASE FOR A PET BUTTON, TWO FOR AN ACTION SLOT -- and whichever it is, the registration
    -- and `useOnKeyDown` MUST AGREE. That agreement is the whole invariant, and breaking it is how
    -- this component has now failed twice:
    --
    --   Phase 3: registered AnyUp only, `useOnKeyDown` read from the CVar which said "act on the
    --            press" -- so the button never received the phase the client acts on. Every action
    --            button looked perfect and did nothing.
    --   Phase 6: the identical mistake on pet buttons, for the identical reason.
    --
    -- A pet button takes ONE phase because the autocast right-click is FORWARDED (see type2 below)
    -- and the client runs the handler once per registered phase -- two phases would forward twice and
    -- toggle autocast straight back. So it registers the release and STATES the release, rather than
    -- reading a preference it cannot honour. The press-versus-release setting exists to make casting
    -- feel responsive; Blizzard's own pet buttons act on the release regardless.
    local wantKeyDown
    if provider.attrType == "pet" then
        f:RegisterForClicks("AnyUp")
        wantKeyDown = false
    else
        f:RegisterForClicks("AnyDown", "AnyUp")
        -- Read from the client's OWN CVar so this button agrees with every other action button on
        -- screen, rather than imposing a preference.
        wantKeyDown = useKeyDown()
    end
    -- Left button only: dragging with the right button is how a player rotates the camera. Not
    -- registered at all for a pet button -- a pet slot's contents are not the player's to rearrange,
    -- and LibActionButton excludes pet from its drag path for the same reason.
    if provider.drag then f:RegisterForDrag("LeftButton") end

    -- Stated once, here, and never again. See the note at the top of this file.
    -- The kind's own secure type. Both kinds carry the slot in the SAME `action` attribute, which
    -- is why _slotNow needs no branch and why paging keeps working untouched.
    f:SetAttribute("type", provider.attrType)
    f:SetAttribute("action", props.slot)
    -- Which phase the client should act on. Always consistent with RegisterForClicks above -- see
    -- the note there for why that agreement is the invariant that matters.
    f:SetAttribute("useOnKeyDown", wantKeyDown)

    -- RIGHT-CLICK ON A PET COMMAND TOGGLES ITS AUTOCAST, and it has to be done in the secure
    -- environment: `TogglePetAutocast` is protected, so an addon calling it from any Lua context --
    -- including a PostClick hook during a real click -- is blocked outright.
    --
    -- `type2 = "click"` plus `clickbutton2` forwards the right-click to another button, which the
    -- client performs itself. The target is Blizzard's OWN pet button, whose handler is trusted and
    -- may therefore do what ours may not. This is the same mechanism Clique uses for click-casting
    -- and ElvUI's bags use for the purchase tab.
    --
    -- It also means Blizzard's pet buttons must keep EXISTING -- they are hidden with their
    -- container, which is fine, but they must not be destroyed or unparented.
    --
    -- Stated once, here, with the other attributes. `type2` also stops the right-click reaching the
    -- pet-cast path, so one click does one thing.
    if provider.attrType == "pet" then
        local blizz = _G["PetActionButton" .. tostring(props.slot)]
        if blizz then
            f:SetAttribute("type2", "click")
            f:SetAttribute("clickbutton2", blizz)
        end
    end

    local handle
    f:SetScript("OnSizeChanged", function(_, w, h)
        if not handle then return end
        S:Emit(handle, S.SIGNALS.SIZE_CHANGED, w, h)
    end)

    local box = SuuUI.Layout:CreateContainer({ host = f, layout = "stack" })

    -- No border: the grid's plate owns the surface and the dividers between cells. trim
    -- crops the bevel Blizzard bakes into its own icon files.
    local iconComp = SuuUI.Components.Icon({ icon = nil, border = false, trim = true }, f)
    iconComp._fade = false
    box:Add(iconComp, { align = "stretch", valign = "stretch" })

    -- Cooldown: the sanctioned Blizzard template exception AuraIcon already takes, because
    -- nothing else draws a radial sweep. Its own countdown numbers are off so they do not
    -- fight the readouts below.
    local iconFrame = iconComp:GetFrame()
    local cooldown = CreateFrame("Cooldown", nil, iconFrame, "CooldownFrameTemplate")
    cooldown:SetHideCountdownNumbers(true)
    local cdProps = { inset = 0 }
    box:Add(cooldown, cdProps)

    -- Text overlay above the swipe. A FontString on the root frame would sit behind the
    -- cooldown, because a child frame draws above its parent's layers. RaiseAbove is the
    -- only sanctioned z-order mechanism outside Core/UIRoot.lua.
    -- BackdropTemplate so a pet button can carry the AUTOCAST RING -- see _paintAutocast. Harmless
    -- for an action button, which simply never turns a border on.
    local overlay = CreateFrame("Frame", nil, f, "BackdropTemplate")
    box:Add(overlay, { align = "stretch", valign = "stretch" })
    SuuUI.UIRoot:RaiseAbove(overlay, iconFrame, 2)
    -- inset 0: this is a ring, not a plate, and must not paint over the icon.
    SuuUI.Backdrop.Apply(overlay, { bg = false, border = false, inset = 0 })
    -- THE ACTIVE-STATE BAR. A pet's mode -- Passive, Defensive, Aggressive -- is reported as the
    -- slot being ACTIVE, and so is a channelled spell or a live aura on an action bar. The component
    -- has always tracked that (`IsCurrent`) and never drawn it, which meant a player could not tell
    -- which mode their pet was in.
    --
    -- An EDGE BAR rather than a wash or a ring, and the channel matters: the overlay's border is
    -- already the autocast indicator, and two states expressed through one channel cannot be told
    -- apart. A bar along the bottom also leaves the icon art unobscured, which a tint does not.
    local currentBar = overlay:CreateTexture(nil, "OVERLAY")
    currentBar:SetPoint("BOTTOMLEFT", overlay, "BOTTOMLEFT", 0, 0)
    currentBar:SetPoint("BOTTOMRIGHT", overlay, "BOTTOMRIGHT", 0, 0)
    currentBar:SetHeight(SuuUI.Pixel.Line(2))
    currentBar:Hide()

    local overlayBox = SuuUI.Layout:CreateContainer({ host = overlay, layout = "stack" })

    local padXs = T:GetToken("spaceXxs") or 2

    -- Hotkey: top-right, muted. The reading a player uses least once the key is learned.
    local hotkeyText = SuuUI.Components.Text({
        text = "", size = "sm", color = "textMuted", justify = "RIGHT", wrap = false,
    }, overlay)
    hotkeyText._fade = false
    overlayBox:Add(hotkeyText, {
        align = "end", valign = "start", inset = { right = padXs, top = padXs },
    })
    hotkeyText:Hide()

    -- Count: bottom-right, same corner AuraIcon puts a stack in.
    local countText = SuuUI.Components.Text({
        text = "", size = "sm", color = "text", justify = "RIGHT", wrap = false,
    }, overlay)
    countText._fade = false
    overlayBox:Add(countText, {
        align = "end", valign = "end", inset = { right = padXs, bottom = padXs },
    })
    countText:Hide()

    -- Macro name: bottom edge, centred, so it does not collide with the count corner.
    local macroText = SuuUI.Components.Text({
        text = "", size = "sm", color = "text", justify = "CENTER", wrap = false,
    }, overlay)
    macroText._fade = false
    overlayBox:Add(macroText, {
        align = "center", valign = "end", inset = { bottom = padXs },
    })
    macroText:Hide()

    -- Remaining cooldown: CENTRED on the icon. The other three positions are taken -- hotkey
    -- top-right, count bottom-right, macro name along the bottom -- and the middle is also where it
    -- belongs on its own merits, for the reason AuraIcon centres its timer: it is the reading a
    -- player scans a cooling button for.
    --
    -- PLAIN colorText, and NOT AuraIcon's colorWarning under five seconds. On an aura that band
    -- means "about to fall off", which is worth shouting about; every cooldown in the game passes
    -- through it on its way to zero, so the same rule would turn the number yellow at the tail of
    -- every cast and mean nothing at all.
    local cooldownText = SuuUI.Components.Text({
        text = "", size = "sm", color = "text", justify = "CENTER", wrap = false,
    }, overlay)
    cooldownText._fade = false
    overlayBox:Add(cooldownText, { align = "center", valign = "center" })
    cooldownText:Hide()

    local id = "actionbutton_" .. tostring(f)
    handle = setmetatable({
        _f             = f,
        _box           = box,
        _iconComp      = iconComp,
        _cooldown      = cooldown,
        _cdProps       = cdProps,
        _overlay       = overlay,
        _overlayBox    = overlayBox,
        _currentBar    = currentBar,
        _hotkeyText    = hotkeyText,
        _countText     = countText,
        _macroText     = macroText,
        _cooldownText  = cooldownText,
        _eid           = id,
        _kind          = props.kind or "action",
        _p             = provider,
        _binding       = props.binding,
        _showHotkey    = props.showHotkey ~= false,
        _showMacroText = props.showMacroText ~= false,
        _showCount     = props.showCount ~= false,
        _showCooldownText = props.showCooldownText ~= false,
        _tooltip       = props.tooltip ~= false,
        _tooltipAnchor = props.tooltipAnchor or "ANCHOR_RIGHT",
        _usable        = true,
        _noResource    = false,
        _outOfRange    = false,
        _current       = false,
        _autoRepeat    = false,
        -- The cooldown window the countdown reads from, and the string currently on screen. All
        -- three nil until a real cooldown starts; _cdText is what makes an unchanged write free.
        _cdStart       = nil,
        _cdDuration    = nil,
        _cdText        = nil,
    }, ActionButtonMeta)

    -- PostClick, not OnClick: the template owns OnClick and it is what performs the action.
    -- Hooked rather than set, for the same reason -- a template that grows a PostClick of its
    -- own must keep it.
    --
    -- Gated on the SAME press-or-release rule the client's handler uses. With both events
    -- registered, OnClick fires twice for one physical click and so does PostClick -- so without
    -- this a consumer would see two CLICKED signals per click, and anything counting them (a
    -- flyout toggle, a cast counter) would be wrong in a way that looks like a double-click.
    f:HookScript("PostClick", function(_, btn, down)
        local acted = (down and true or false) == (f:GetAttribute("useOnKeyDown") and true or false)
        if not acted then return end
        S:Emit(handle, S.SIGNALS.CLICKED, btn or "LeftButton")
    end)
    f:HookScript("OnEnter", function()
        S:Emit(handle, S.SIGNALS.MOUSE_ENTER)
        handle:_showTooltip()
    end)
    f:HookScript("OnLeave", function()
        S:Emit(handle, S.SIGNALS.MOUSE_LEAVE)
        handle:_hideTooltip()
    end)

    -- Drag in and out. LOCK_ACTIONBAR is a CVar-backed PLAIN GLOBAL and therefore the string
    -- "0" or "1" -- and "0" is truthy in Lua, so it has to be compared, never tested. Pinned
    -- in the harness spec.
    local function barsLocked()
        return LOCK_ACTIONBAR == "1" or LOCK_ACTIONBAR == 1
    end

    f:SetScript("OnDragStart", function()
        if barsLocked() then return end
        local slot = handle:_slotNow()
        if slot then PickupAction(slot) end
    end)
    f:SetScript("OnReceiveDrag", function()
        if barsLocked() then return end
        local slot = handle:_slotNow()
        if slot then PlaceAction(slot) end
    end)

    -- Join the shared infrastructure before the first refresh, so the index is populated by
    -- the time anything can dispatch to it.
    live[handle] = true
    handle._indexed = props.slot
    indexSlot(handle, props.slot)
    syncEventFrame()
    syncRangeTicker()

    handle:ApplyTheme()
    handle:Refresh()
    SuuUI.Events:On("SUUUI_THEME_CHANGED", function() handle:ApplyTheme() end, id)
    return handle
end

-- Test seam, and only that: the shared index is module-local, so a spec cannot otherwise
-- assert that two buttons on one slot both got repainted, or that the ticker and the event
-- frame really do drop when the last button goes.
SuuUI._ActionButtonInternals = {
    liveCount = function()
        local n = 0
        for _ in pairs(live) do n = n + 1 end
        return n
    end,
    slotWatchers = function(slot)
        local n = 0
        for _ in pairs(bySlot[slot] or {}) do n = n + 1 end
        return n
    end,
    hasTicker = function()
        return rangeTicker ~= nil and rangeTicker:GetScript("OnUpdate") ~= nil
    end,
    -- How many buttons the ticker is counting a cooldown down for. The set is module-local, so
    -- without this a spec cannot tell "the GCD drew no number" from "the GCD is on the ticker
    -- drawing nothing", and cannot assert that an expired cooldown retires its button.
    onCooldownCount = function()
        local n = 0
        for _ in pairs(onCooldown) do n = n + 1 end
        return n
    end,
    gcdMaxDuration = GCD_MAX_DURATION,
    eventFrame = function() return evt end,
    abbreviateKey = abbreviateKey,
    rangeThrottle = RANGE_THROTTLE,
}
