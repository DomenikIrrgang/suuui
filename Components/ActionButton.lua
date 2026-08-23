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

---------------------------------------------------------------------------
-- Shared event frame
---------------------------------------------------------------------------
-- ONE frame carrying the union of every action event, for every button in the addon,
-- registered only while at least one button exists. Sixty buttons with an event frame each
-- would be sixty frames and sixty dispatches for the same six events -- the shape
-- Plugins/DataBar/DataBarWidget.lua uses, and for the same reason.

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
    local texture = slot and HasAction(slot) and GetActionTexture(slot) or nil
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
    if not (slot and HasAction(slot)) then
        self._cooldown:SetCooldown(0, 0)
        return
    end
    local start, duration, enable = GetActionCooldown(slot)
    if enable and enable ~= 0 and duration and duration > 0 then
        self._cooldown:SetCooldown(start, duration)
    else
        self._cooldown:SetCooldown(0, 0)
    end
end

function ActionButtonMeta:_paintCount()
    if not self._countText then return end
    local slot = self:_slotNow()
    local count = slot and HasAction(slot) and GetActionCount(slot) or 0
    -- Above one, matching AuraIcon's stack threshold: the client reports 1 for a single
    -- charge and a "1" in the corner of every consumable is noise.
    if self._showCount and count and count > 1 then
        self._countText:SetText(tostring(count))
        self._countText:Show()
    else
        self._countText:Hide()
    end
end

function ActionButtonMeta:_paintMacroText()
    if not self._macroText then return end
    local slot = self:_slotNow()
    local text = slot and HasAction(slot) and GetActionText(slot) or nil
    -- nil for a spell or an item -- which is why GetActionText cannot be used to decide
    -- whether the slot is occupied. HasAction answers that.
    if self._showMacroText and text and text ~= "" then
        self._macroText:SetText(text)
        self._macroText:Show()
    else
        self._macroText:Hide()
    end
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
    if not (slot and HasAction(slot)) then
        self._usable, self._noResource = true, false
        self:_applyTint()
        return
    end
    local usable, noMana = IsUsableAction(slot)
    self._usable = usable and true or false
    self._noResource = noMana and true or false
    self:_applyTint()
end

function ActionButtonMeta:_paintRange()
    local slot = self:_slotNow()
    local inRange
    if slot and HasAction(slot) then
        inRange = IsActionInRange(slot)
    end
    -- nil means range is not a question for this action -- a self buff, a macro with no
    -- target. That is NOT the same as being out of range, and painting it red would put a
    -- danger tint on every self-cast on the bar.
    local out = (inRange == false)
    if out == self._outOfRange then return end
    self._outOfRange = out
    self:_applyTint()
end

function ActionButtonMeta:_readState()
    local slot = self:_slotNow()
    if not (slot and HasAction(slot)) then
        self._current, self._autoRepeat = false, false
        return
    end
    self._current = IsCurrentAction(slot) and true or false
    self._autoRepeat = IsAutoRepeatAction(slot) and true or false
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
    if type(GameTooltip) ~= "table" or type(GameTooltip.SetAction) ~= "function" then return end
    local slot = self:_slotNow()
    -- Nothing to say about an empty cell, and SetAction on one shows an empty frame rather than
    -- nothing at all.
    if not (slot and HasAction(slot)) then return end
    GameTooltip:SetOwner(self._f, self._tooltipAnchor)
    GameTooltip:SetAction(slot)
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
    return (slot and HasAction(slot)) and true or false
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
    -- Both drop to nothing once the last button goes, rather than leaving a registered
    -- OnUpdate and nine events running for no one.
    syncRangeTicker()
    syncEventFrame()
    if self._countText then self._countText:Destroy() end
    if self._macroText then self._macroText:Destroy() end
    if self._hotkeyText then self._hotkeyText:Destroy() end
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
    f:RegisterForClicks("AnyDown", "AnyUp")
    -- Left button only: dragging with the right button is how a player rotates the camera.
    f:RegisterForDrag("LeftButton")

    -- Stated once, here, and never again. See the note at the top of this file.
    f:SetAttribute("type", "action")
    f:SetAttribute("action", props.slot)
    -- Which of the two events the client should act on. Read from the client's OWN CVar so this
    -- button agrees with every other action button on screen, rather than imposing a preference: a
    -- player who chose key-down elsewhere expects it here too.
    f:SetAttribute("useOnKeyDown", useKeyDown())

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
    local overlay = CreateFrame("Frame", nil, f)
    box:Add(overlay, { align = "stretch", valign = "stretch" })
    SuuUI.UIRoot:RaiseAbove(overlay, iconFrame, 2)
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

    local id = "actionbutton_" .. tostring(f)
    handle = setmetatable({
        _f             = f,
        _box           = box,
        _iconComp      = iconComp,
        _cooldown      = cooldown,
        _cdProps       = cdProps,
        _overlay       = overlay,
        _overlayBox    = overlayBox,
        _hotkeyText    = hotkeyText,
        _countText     = countText,
        _macroText     = macroText,
        _eid           = id,
        _binding       = props.binding,
        _showHotkey    = props.showHotkey ~= false,
        _showMacroText = props.showMacroText ~= false,
        _showCount     = props.showCount ~= false,
        _tooltip       = props.tooltip ~= false,
        _tooltipAnchor = props.tooltipAnchor or "ANCHOR_RIGHT",
        _usable        = true,
        _noResource    = false,
        _outOfRange    = false,
        _current       = false,
        _autoRepeat    = false,
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
    eventFrame = function() return evt end,
    abbreviateKey = abbreviateKey,
    rangeThrottle = RANGE_THROTTLE,
}
