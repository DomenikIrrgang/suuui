-- Keybind overlays: what a bindable button LOOKS like while keybind mode is open.
--
-- Visual reference: artifact `suuui-keybind-mode-concept`. That artifact is the spec for this file
-- -- the wash colours, the key chip, the multi-bind dot and the state sequence all come from it.
--
-- The mode's STATE lives in Core/KeybindMode.lua, which owns nothing visual and knows nothing
-- about bars. This file registers a PROVIDER with it and draws. Capture and the binding write are
-- Phase 5; this file deliberately installs no keyboard handler yet, so the overlays are inert.
--
-- FRAME LEVEL. The overlay parents to the BUTTON and is raised 4 above it. The button's own
-- overlay -- the one carrying the hotkey, count and macro text plus the current-action bar -- sits
-- at host+4, so 4 puts us at host+5, above its text rather than behind it. Strata stays MEDIUM:
-- GameTooltip lives at TOOLTIP and must keep rendering above us, and promoting would also put us
-- over the settings window.
--
-- WHY REBUILDING IS NOT OPTIONAL. ActionBarGrid DESTROYS and recreates its buttons whenever the
-- count or a slot changes, so an overlay attached to a button handle outlives the frame it was
-- drawn on. Every tracked grid's CHILDREN_CHANGED is therefore a rebuild trigger -- the same
-- signal ActionBars' own binding routing hangs off, and for the same reason.
local ipairs, pairs, type = ipairs, pairs, type

local M = {}

local S = SuuUI.UISignals
local T = SuuUI.Theme

-- [button handle] = { f, bg, chip, chipText, dot, state, prevHotkey }
local overlays = {}
-- [grid handle] = CHILDREN_CHANGED connection id. Kept because UISignals keys a connection by the
-- id Connect returns, not by an owner token, so it has to be held to be released.
local tracked = {}
-- The button the pointer is on, or nil. One at a time by construction -- a pointer is in one place
-- -- which is what lets the ARMED wash be a single-button state rather than a set.
local armed = nil

-- The concept's four state washes, plus the resting tint every bindable button carries. HOVERED
-- reuses colorEditOverlay rather than a token of its own: it is the same accent-at-0.20 "you can
-- act on this" wash edit mode already means by it.
local WASH = {
    rest    = "colorKeybindRest",
    armed   = "colorEditOverlay",
    pending = "colorWarningSubtle",
    ok      = "colorSuccessSubtle",
    cleared = "colorDangerSubtle",
}

-- The ring, and the chip's border. nil for rest: an unhovered button gets a tint and no outline,
-- so the hovered one is the only bordered cell on the bar.
local EDGE = {
    rest    = false,
    armed   = "colorAccent",
    pending = "colorWarning",
    ok      = "colorSuccess",
    cleared = "colorDanger",
}

-- Chip text colour per state, so the key itself carries the state as well as the border.
local INK = {
    rest    = "text",
    armed   = "text",
    pending = "warning",
    ok      = "success",
    cleared = "danger",
}

--- Every key bound to a command, in the client's own order.
--
-- GetBindingKey returns VARARGS -- measured in game, `1 CTRL-F9` for one command -- so this
-- collects them rather than taking the first. The chip can only show one; the tooltip lists all.
-- @param command string|nil
-- @return table  list of key strings, empty when unbound
local function keysFor(command)
    if not command then return {} end
    if type(GetBindingKey) ~= "function" then return {} end
    return { GetBindingKey(command) }
end

--- Which command currently owns a key, or nil.
---
--- Treats BOTH nil and "" as unowned. The client's documented answer for an unbound key is the
--- empty string, but that is the one thing in this area never measured in game -- the Phase 0 probe
--- only established that the function exists -- so the guard covers both rather than betting.
local function ownerOf(combo)
    if type(GetBindingAction) ~= "function" then return nil end
    local owner = GetBindingAction(combo)
    if owner == nil or owner == "" then return nil end
    return owner
end

M._ownerOf = ownerOf

--- A command rendered the way the player sees it in the Key Bindings UI.
---
--- The client publishes a display name per binding as BINDING_NAME_<command>, which is how
--- "TOGGLEWORLDMAP" becomes "World Map". Falls back to the raw command, because a name we cannot
--- resolve is still far more useful than saying the key is "in use" and not saying by what.
local function readableCommand(command)
    if not command then return nil end
    local pretty = _G and _G["BINDING_NAME_" .. command]
    return pretty or command
end

M._readableCommand = readableCommand

-- The write waiting on confirmation: { button, combo, owner }. One at a time, because it belongs to
-- the hovered button and only one button is ever hovered.
local pending = nil

--- The conflict awaiting confirmation, or nil.
function M.PendingConflict() return pending end

M._keysFor = keysFor

-- Keys that are NOT bindings. Bare modifiers land here because a keyup on Shift alone is the
-- player reaching for a combination, not choosing one.
local IGNORED = {
    LSHIFT = true, RSHIFT = true, LCTRL = true, RCTRL = true,
    LALT = true, RALT = true, UNKNOWN = true,
}

--- Whether a captured key should be discarded rather than bound.
local function ignored(key)
    if type(key) ~= "string" or key == "" then return true end
    if IGNORED[key] then return true end
    -- BARE CMD, on macOS. Matched by PATTERN rather than an exact token: the probe that was meant
    -- to capture the client's name for a bare Cmd keyup never fired, but `META-` is confirmed as
    -- the modifier PREFIX -- seen in one of the player's own real bindings, META-Q. So any bare key
    -- whose name carries META or COMMAND is a modifier, whichever spelling this client uses.
    -- ElvUI's own ignore list has exactly this hole, which is why a bare Cmd can bind there.
    if key:find("META") or key:find("COMMAND") then return true end
    return false
end

M._ignored = ignored

--- Builds the binding string for a key plus whatever modifiers are held.
---
--- MODIFIER ORDER IS ALT-CTRL-SHIFT-META-, copied from ElvUI, which ships a working keybind mode on
--- this exact client. It is not arbitrary: the client stores one canonical order and a string in a
--- different order is a different binding. This is an in-game check by construction -- nothing local
--- can tell a wrong order from a right one, because the harness stores whatever string it is given.
local function comboFor(key)
    local alt   = (type(IsAltKeyDown) == "function" and IsAltKeyDown()) and "ALT-" or ""
    local ctrl  = (type(IsControlKeyDown) == "function" and IsControlKeyDown()) and "CTRL-" or ""
    local shift = (type(IsShiftKeyDown) == "function" and IsShiftKeyDown()) and "SHIFT-" or ""
    local meta  = (type(IsMetaKeyDown) == "function" and IsMetaKeyDown()) and "META-" or ""
    return alt .. ctrl .. shift .. meta .. key
end

M._comboFor = comboFor

--- Normalises a mouse button name to the form the binding system uses.
local function normalizeMouse(btn)
    if type(btn) ~= "string" then return nil end
    if btn == "MiddleButton" then return "BUTTON3" end
    -- Button4 / Button5 -> BUTTON4 / BUTTON5. Left and Right carry no digit and pass through as
    -- they are, which is what the binding system expects for them.
    if btn:find("Button%d") then return btn:upper() end
    return btn
end

M._normalizeMouse = normalizeMouse

-- The change counter lives on SuuUI.KeybindMode, not here: it is MODE state that the panel reads,
-- and a second provider (bags, the spellbook) must add to the same total rather than keep its own.
local function noteChange(n)
    if SuuUI.KeybindMode then SuuUI.KeybindMode:NoteChange(n or 1) end
end

--- What the chip reads, for a state.
---
--- THE CHIP IS TWO DIFFERENT CONTROLS depending on state, and that is the fix for a defect the
--- concept could not show. The concept drew 44-unit cells; the real default is 32, and a full
--- combination like CTRL-ALT-F is about 60 units at 11px text. Sizing every chip to its own text
--- made neighbours overlap into an unreadable smear -- measured in game, five chips reading
--- `ALT-RLT-ALT-ZLT-ALT-GLT-V` across one bar, and `unboundunboundunbound` across another.
---
--- So: AT REST the chip shows the ABBREVIATED key, which fits a 32-unit cell, and shows NOTHING at
--- all when the button is unbound -- the word "unbound" is the longest string of the lot and it was
--- on every empty button at once. HOVERED, it expands to the full unabbreviated key, which is the
--- concept's actual point: confirming exactly what a keypress bound. Only one button is ever
--- hovered, so exactly one chip can overflow and nothing collides with it.
-- @param keys table  every key on the command
-- @param state string
-- @return string label, bool isEmpty
local function chipLabel(keys, state)
    local resting = (state == nil or state == "rest")
    if #keys == 0 then
        -- Nothing to say, and at rest saying it costs more than it is worth. The tooltip carries
        -- "No keybind set." for the hovered button, which is where a player is actually asking.
        if resting then return "", true end
        return "unbound", true
    end
    if resting then
        local short = SuuUI._ActionButtonInternals
            and SuuUI._ActionButtonInternals.abbreviateKey
        return (short and short(keys[1])) or keys[1], false
    end
    return keys[1], false
end

--- Repaints one overlay for its current state.
local function paint(rec)
    local state = rec.state or "rest"
    SuuUI.Backdrop.SetBg(rec.f, WASH[state] or WASH.rest)

    local edge = EDGE[state]
    SuuUI.Backdrop.SetBorder(rec.f, edge or false)

    local keys = keysFor(rec.command)
    local label, isEmpty = chipLabel(keys, state)
    rec.chipText:SetText(label)
    rec.chipText:SetColor(isEmpty and "muted" or (INK[state] or "text"))
    SuuUI.Backdrop.SetBorder(rec.chip, edge or "colorBorder")

    if label == "" then
        -- An empty chip is a bordered box saying nothing, which on a bar of unbound buttons is
        -- pure noise. The wash alone already says "the mode reaches here".
        rec.chip:Hide()
    else
        rec.chip:Show()
        local pad = T:GetToken("spaceXxs") or 2
        local w = (rec.chipText:GetWidth() or 0) + pad * 4
        -- AT REST the chip is clamped to the button, so it cannot reach its neighbours. Hovered, it
        -- is allowed to overflow: the full key is the whole point of the hovered state, and only one
        -- button is ever hovered.
        if state == nil or state == "rest" then
            local host = rec.button.GetWidth and rec.button:GetWidth() or nil
            if host and host > 0 and w > host then w = host end
        end
        rec.chip:SetSize(w, (T:GetToken("sizeControlSm") or 18) - pad * 2)
    end

    -- Top-left is the only free corner on the button, and more than one key is the only thing the
    -- chip cannot say by itself.
    if #keys > 1 then rec.dot:Show() else rec.dot:Hide() end
end

--- Builds the overlay for one button, or returns the one it already has.
local function overlayFor(button)
    local rec = overlays[button]
    if rec then return rec end

    local host = button:GetFrame()
    if not host then return nil end

    local f = CreateFrame("Frame", nil, host, "BackdropTemplate")
    SuuUI.UIRoot:RaiseAbove(f, host, 4)
    SuuUI.Backdrop.Apply(f, { bg = false, border = false, inset = 0 })

    -- SetAllPoints, NOT a host container. A container's `host` branch places children but sizes
    -- NOTHING, so the overlay came out zero-sized and everything centred inside it landed in the
    -- wrong place -- reported in game as "it doesn't seem centered". This project has paid for that
    -- lesson once already, on the inventory snapshot wash. Anchoring to all four corners also means
    -- the overlay tracks the button through a button_size change for free.
    f:SetAllPoints(host)


    local chip = CreateFrame("Frame", nil, f, "BackdropTemplate")
    SuuUI.UIRoot:RaiseAbove(chip, f, 1)
    SuuUI.Backdrop.Apply(chip, { bg = "colorBg", border = "colorBorder" })
    local chipText = SuuUI.Components.Text({
        text = "", size = "sm", color = "text", justify = "CENTER", wrap = false,
    }, chip)
    chipText:GetFrame():SetPoint("CENTER", chip, "CENTER", 0, 0)

    -- ANCHORED EXPLICITLY, not through a container, and this is the second sizing bug in this file.
    -- A stack container computes a child's placement offset from the size it has AT Add TIME; paint()
    -- then resizes the chip on every repaint, leaving that offset stale, so the chip grew sideways
    -- out of centre. Reported in game twice as "it's still not in the center". A CENTER-to-CENTER
    -- anchor re-resolves itself on every SetSize, so the chip cannot drift however often it is
    -- resized. Containers are the right tool for a fixed-size child and the wrong one here.
    chip:SetPoint("CENTER", f, "CENTER", 0, 0)

    local dot = f:CreateTexture(nil, "OVERLAY")
    dot:SetSize(SuuUI.Pixel.Line(4), SuuUI.Pixel.Line(4))
    local accent = T:GetToken("colorAccent") or { 0.3, 0.6, 1, 1 }
    dot:SetColorTexture(accent[1], accent[2], accent[3], accent[4] or 1)
    local pad = T:GetToken("spaceXxs") or 2
    dot:SetPoint("TOPLEFT", f, "TOPLEFT", pad, -pad)
    dot:Hide()

    rec = {
        f = f, chip = chip, chipText = chipText, dot = dot,
        button = button, command = button.GetBinding and button:GetBinding() or nil,
        state = "rest",
    }
    overlays[button] = rec

    -- The overlay takes the mouse, so it is what the pointer reports rather than the button. That
    -- is required rather than incidental: Phase 5's key capture has to be enabled on ENTER and
    -- released on LEAVE, and only the frame receiving the events can do that.
    f:EnableMouse(true)
    f:SetScript("OnEnter", function() M.Arm(button) end)
    f:SetScript("OnLeave", function() M.Disarm(button) end)

    -- CAPTURE IS EXCLUSIVE AND SCOPED TO HOVER. Exclusive because it is the only mode that works:
    -- a frame with SetPropagateKeyboardInput(true) receives no OnKeyUp at all on this client
    -- (measured -- the probe printed nothing for any key). Scoped to hover because exclusive
    -- capture swallows EVERYTHING, so a mode-wide listener would eat chat and movement for as long
    -- as the mode is open. Keyboard goes on in Arm and off in Disarm; the pointer is the switch.
    f:SetPropagateKeyboardInput(false)
    f:EnableKeyboard(false)
    f:EnableMouseWheel(true)

    -- ON RELEASE, not press, matching ElvUI: a modifier still held when the main key comes up is
    -- part of the combination, and releasing the modifier first is not how anyone types one.
    f:SetScript("OnKeyUp", function(_, key) M.Capture(button, key) end)
    f:SetScript("OnMouseUp", function(_, btn) M.Capture(button, normalizeMouse(btn)) end)
    f:SetScript("OnMouseWheel", function(_, delta)
        M.Capture(button, (delta or 0) > 0 and "MOUSEWHEELUP" or "MOUSEWHEELDOWN")
    end)

    paint(rec)
    return rec
end

local function destroy(rec)
    if not rec then return end
    -- Restore the player's own hotkey setting before the overlay goes: the mode borrowed it, it
    -- does not own it.
    if rec.prevHotkey ~= nil and rec.button.SetShowHotkey then
        rec.button:SetShowHotkey(rec.prevHotkey)
    end
    -- ARMED MUST NOT OUTLIVE ITS OVERLAY. A dangling `armed` makes the next Arm skip its
    -- `Disarm(armed)` -- the record is gone, so Disarm returns early -- and whatever that overlay
    -- was leaves the keyboard enabled. Two listeners then race for one keypress and the write can
    -- land on the wrong button.
    if armed == rec.button then armed = nil end
    if pending and pending.button == rec.button then pending = nil end
    if rec.f then
        -- RELEASED EXPLICITLY. Hiding and reparenting a frame does not undo EnableKeyboard, and the
        -- invariant this whole design rests on is that exactly ONE overlay is listening at a time.
        if rec.f.EnableKeyboard then rec.f:EnableKeyboard(false) end
        rec.f:SetScript("OnEnter", nil)
        rec.f:SetScript("OnLeave", nil)
        rec.f:SetScript("OnKeyUp", nil)
        rec.f:SetScript("OnMouseUp", nil)
        rec.f:SetScript("OnMouseWheel", nil)
        rec.f:EnableMouse(false)
        rec.f:Hide()
        rec.f:SetParent(nil)
    end
    overlays[rec.button] = nil
end

--- Arms one button: the hovered state, and the only button showing a ring.
-- @param button table
function M.Arm(button)
    if armed and armed ~= button then M.Disarm(armed) end
    local rec = overlays[button]
    if not rec then return end

    -- SILENCE EVERY OTHER OVERLAY, not just the one we think was armed. This is the invariant the
    -- whole write path depends on -- exactly ONE overlay listening -- and `armed` is a single
    -- variable that can be wrong: a grid rebuild, a bar being disabled mid-hover, or an OnLeave the
    -- client never delivered all leave a second frame with EnableKeyboard(true), and then a keypress
    -- can be answered by a button the pointer is nowhere near. Asserting it here costs one loop over
    -- at most a few dozen frames and makes the guarantee structural rather than hopeful.
    for other, orec in pairs(overlays) do
        if other ~= button and orec.f and orec.f.EnableKeyboard then
            orec.f:EnableKeyboard(false)
        end
    end

    armed = button
    rec.state = "armed"
    if rec.f.EnableKeyboard then rec.f:EnableKeyboard(true) end
    paint(rec)
    M._showTooltip(rec)
end

--- Returns a button to the resting wash.
-- @param button table
function M.Disarm(button)
    local rec = overlays[button]
    if armed == button then armed = nil end
    if not rec then return end
    -- LEAVING CANCELS A PENDING STEAL. That is the cancel gesture -- ESC already means clear-all, so
    -- it cannot also mean "never mind", and a pending write belongs to the hover it was made in.
    if pending and pending.button == button then pending = nil end
    rec.state = "rest"
    -- RELEASED HERE, and this is the line that keeps chat and movement working: while a button is
    -- hovered the overlay swallows every key, so leaving it must hand the keyboard straight back.
    if rec.f.EnableKeyboard then rec.f:EnableKeyboard(false) end
    paint(rec)
    M._hideTooltip(rec)
end

--- The armed button, or nil.
function M.GetArmed() return armed end

--- Flashes a result state on a button. Phase 5 drives this from the write path.
-- @param button table
-- @param state string  "pending" | "ok" | "cleared"
function M.SetState(button, state)
    local rec = overlays[button]
    if not rec then return end
    rec.state = state
    paint(rec)
end

--- The overlay record for a button, for specs and for Phase 5.
function M.OverlayFor(button) return overlays[button] end

--- Returns a button to its settled look after a result flash.
local function settle(button)
    local rec = overlays[button]
    if not rec then return end
    rec.state = (armed == button) and "armed" or "rest"
    paint(rec)
    if armed == button then M._showTooltip(rec) end
end

M._settle = settle

local function flash(button, state)
    M.SetState(button, state)
    -- The flash is a READING, so it has to persist long enough to be read. C_Timer is guarded
    -- because a client without it should still bind -- it just settles on the next hover instead.
    if type(C_Timer) == "table" and type(C_Timer.After) == "function" then
        C_Timer.After(0.6, function() settle(button) end)
    end
end

--- Writes a key onto a hovered button. THIS IS THE MECHANIC.
---
--- Everything the write needs is one SetBinding call: the client fires UPDATE_BINDINGS
--- synchronously, ActionBars re-runs applyOwnBindings on that event and re-routes the override to
--- our own button, and ActionButton repaints its hotkey from the same event. Measured end to end in
--- game -- a key written this way fired the hovered button's action.
--- @param button table
--- @param key string  a raw key name, already mouse-normalised
--- @return bool  whether a binding was written
function M.Capture(button, key)
    local rec = overlays[button]
    if not rec then return false end

    -- ESCAPE is not a binding, it is the clear gesture. Checked before the ignore list so it can
    -- never be swallowed as noise.
    if key == "ESCAPE" then return M.ClearAll(button) end

    if ignored(key) then return false end
    if not rec.command then return false end

    -- GATED, NOT ATTEMPTED. In combat SetBinding returns false AND the client prints "Interface
    -- action failed because of an AddOn" -- measured -- so trying and checking the result still
    -- shows the player an error. The mode refuses to OPEN in combat too; this is the second gate,
    -- for combat starting while it is already open.
    if type(InCombatLockdown) == "function" and InCombatLockdown() then return false end
    if type(SetBinding) ~= "function" then return false end

    local combo = comboFor(key)

    -- CONFIRM BEFORE STEALING. A key belongs to exactly one command, so binding one that is already
    -- in use silently unbinds it elsewhere -- ElvUI does precisely that and never says so, which its
    -- own behaviour makes the worst hole in it.
    --
    -- CONFIRMED BY PRESSING THE SAME KEY AGAIN, not by a modal. Three reasons: the concept puts this
    -- warning in the hovered button's TOOLTIP, which is already on screen; a modal takes the pointer
    -- off the button and so cancels the hover the pending write belongs to; and ESC is already the
    -- clear-all gesture, so it cannot also mean "cancel". Moving away cancels instead, which needs
    -- no key at all.
    local owner = ownerOf(combo)
    if owner and owner ~= rec.command then
        if not (pending and pending.button == button and pending.combo == combo) then
            pending = { button = button, combo = combo, owner = owner }
            M.SetState(button, "pending")
            M._showTooltip(rec)
            return false
        end
        -- Second press of the same combination on the same button: that is the confirmation.
    end
    pending = nil

    if not SetBinding(combo, rec.command) then return false end

    noteChange(1)
    flash(button, "ok")
    return true
end

--- Clears EVERY key bound to a button's command.
---
--- Iterating is the whole point: GetBindingKey returns varargs and a command can hold several keys,
--- so clearing only the first would leave the button still bound while reporting success.
--- @param button table
--- @return bool  whether anything was cleared
function M.ClearAll(button)
    local rec = overlays[button]
    if not rec or not rec.command then return false end
    if type(InCombatLockdown) == "function" and InCombatLockdown() then return false end
    if type(SetBinding) ~= "function" then return false end

    local keys = keysFor(rec.command)
    if #keys == 0 then return false end
    for _, k in ipairs(keys) do
        -- SetBinding with the command omitted is the unbind form -- measured, returns true.
        SetBinding(k)
        noteChange(1)
    end
    flash(button, "cleared")
    return true
end

function M._showTooltip(rec)
    if type(GameTooltip) ~= "table" then return end
    local host = rec.f
    GameTooltip:SetOwner(host, "ANCHOR_TOP")
    -- ClearLines IS REQUIRED, and leaving it out is what produced "the player tooltip will come".
    -- SetOwner re-anchors and re-owns the tooltip but does NOT empty it, so our lines were appended
    -- to whatever it last showed -- a unit frame's contents with a keybind list stapled underneath.
    if GameTooltip.ClearLines then GameTooltip:ClearLines() end
    local name = rec.button.GetFrame and rec.button:GetFrame()
    GameTooltip:AddLine(rec.command or "Unbound", 1, 1, 1)
    local keys = keysFor(rec.command)
    if #keys == 0 then
        GameTooltip:AddLine("No keybind set.", 0.6, 0.6, 0.6)
    else
        for i, k in ipairs(keys) do
            GameTooltip:AddDoubleLine("Binding " .. i, k, 0.6, 0.6, 0.6, 1, 1, 1)
        end
    end
    GameTooltip:AddLine("ESC clears every key on this button.", 0.6, 0.6, 0.6)

    -- THE CONFLICT WARNING, in the tooltip because that is where the concept draws it and because
    -- it is already on screen under the pointer. Naming the current owner is the whole point: "that
    -- key is in use" without saying by what leaves the player unable to decide.
    if pending and pending.button == rec.button then
        GameTooltip:AddLine(" ")
        GameTooltip:AddLine(
            pending.combo .. " is on " .. (readableCommand(pending.owner) or "another action"),
            0.95, 0.84, 0.22)
        GameTooltip:AddLine("Press it again to take it. Move away to cancel.", 0.6, 0.6, 0.6)
    end

    GameTooltip:Show()
    rec._tooltipShown = true
    return name
end

function M._hideTooltip(rec)
    if type(GameTooltip) ~= "table" then return end
    if not rec._tooltipShown then return end
    rec._tooltipShown = nil
    -- Only if it is still OURS -- a pointer that moved onto something else in the same frame must
    -- not have its tooltip hidden out from under it. Same guard ActionButton uses.
    if GameTooltip.GetOwner and GameTooltip:GetOwner() ~= rec.f then return end
    GameTooltip:Hide()
end

--- Every button this module can draw on, for KeybindMode's provider.
-- @return table
function M.Buttons()
    local out = {}
    for grid in pairs(tracked) do
        if grid.GetButtons then
            for _, b in ipairs(grid:GetButtons()) do out[#out + 1] = b end
        end
    end
    return out
end

--- Builds or tears down every overlay to match the mode.
function M.Refresh()
    local active = SuuUI.KeybindMode and SuuUI.KeybindMode:IsActive()
    if not active then
        for _, rec in pairs(overlays) do destroy(rec) end
        armed = nil
        return
    end
    -- Rebuild from the CURRENT button set. A stale record whose button the grid destroyed is
    -- dropped rather than repainted, which is the whole reason CHILDREN_CHANGED is subscribed.
    local live = {}
    for _, b in ipairs(M.Buttons()) do live[b] = true end
    for button, rec in pairs(overlays) do
        if not live[button] then destroy(rec) end
    end
    for _, b in ipairs(M.Buttons()) do
        local rec = overlayFor(b)
        if rec then
            rec.command = b.GetBinding and b:GetBinding() or nil
            -- The concept REPLACES the corner hotkey with the chip: the abbreviated key and the
            -- full one side by side is two readings of one fact. The player's own setting is
            -- remembered so leaving the mode gives it back.
            if rec.prevHotkey == nil and b.IsShowingHotkey and b.SetShowHotkey then
                rec.prevHotkey = b:IsShowingHotkey()
                b:SetShowHotkey(false)
            end
            paint(rec)
        end
    end
end

--- Starts drawing on a grid's buttons.
-- @param grid table  an ActionBarGrid handle
function M.Register(grid)
    if not grid or tracked[grid] then return end
    tracked[grid] = S:Connect(grid, S.SIGNALS.CHILDREN_CHANGED, function()
        M.Refresh()
    end)
    M.Refresh()
end

--- Stops drawing on a grid, releasing its overlays and its subscription.
-- @param grid table
function M.Unregister(grid)
    if not grid then return end
    local id = tracked[grid]
    if id then S:Disconnect(grid, S.SIGNALS.CHILDREN_CHANGED, id) end
    tracked[grid] = nil
    if grid.GetButtons then
        for _, b in ipairs(grid:GetButtons()) do
            destroy(overlays[b])
        end
    end
end

SuuUI.ActionBarKeybind = M

if SuuUI.KeybindMode then
    SuuUI.KeybindMode:RegisterProvider("action_bars", M.Buttons)
end

-- EVERY overlay repaints, not just the one that was written to. Binding a key REMOVES it from
-- whichever command held it before, so the button that lost it has to stop advertising it -- and
-- that button is somewhere else on another bar. Repainting only the hovered one would leave the
-- same key visibly claimed twice, which is the exact confusion the conflict warning exists to
-- prevent. Cheap: a repaint is a colour and a string, and the event only fires on a real change.
local evt = CreateFrame("Frame")
evt:RegisterEvent("UPDATE_BINDINGS")
evt:SetScript("OnEvent", function()
    if not (SuuUI.KeybindMode and SuuUI.KeybindMode:IsActive()) then return end
    for button, rec in pairs(overlays) do
        rec.command = button.GetBinding and button:GetBinding() or rec.command
        paint(rec)
    end
end)
M._evt = evt

SuuUI.Settings:Watch("_layout", "keybind_mode", function()
    M.Refresh()
end, "_actionbar_keybind_overlays", { immediate = true })
