-- Frame and its subtypes: EditBox, ScrollFrame, Button.
local state   = require("harness.wow.state")
local widget  = require("harness.wow.widget")
local regions = require("harness.wow.regions")
local font    = require("harness.wow.font")
local anim    = require("harness.wow.animation")

local Base = widget.Base
local M = {}

local function derive(parentMeta)
    local meta = setmetatable({}, { __index = parentMeta })
    meta.__index = meta
    return meta
end

local FrameMeta = derive(Base)
FrameMeta._canScript = true
M.FrameMeta = FrameMeta

----------------------------------------------------------------------------------
-- Child regions
----------------------------------------------------------------------------------

function FrameMeta:CreateTexture(name, layer, template, subLayer)
    local t = widget.new("Texture", name, self, regions.TextureMeta)
    t._drawLayer, t._subLayer = layer or "ARTWORK", subLayer
    t._template = template
    return t
end

function FrameMeta:CreateMaskTexture(name, layer)
    local t = widget.new("MaskTexture", name, self, regions.MaskMeta)
    t._drawLayer = layer or "ARTWORK"
    return t
end

function FrameMeta:CreateFontString(name, layer, inherits)
    local fs = widget.new("FontString", name, self, regions.FontStringMeta)
    fs._drawLayer = layer or "ARTWORK"
    fs._inherits = inherits
    -- Inheriting a font object gives a default size, as GameFontNormal does in game
    fs._fontSize = 12
    fs._font = "Fonts/FRIZQT__.TTF"
    return fs
end

function FrameMeta:CreateLine(name, layer)
    local t = widget.new("Line", name, self, regions.TextureMeta)
    t._drawLayer = layer or "ARTWORK"
    return t
end

function FrameMeta:GetChildren()    return table.unpack(self._childFrames) end
function FrameMeta:GetNumChildren() return #self._childFrames end
function FrameMeta:GetRegions()     return table.unpack(self._regions) end
function FrameMeta:GetNumRegions()  return #self._regions end

----------------------------------------------------------------------------------
-- Backdrop
----------------------------------------------------------------------------------

-- The client puts the backdrop methods on a frame ONLY when it was created from
-- BackdropTemplate; on any other frame they are simply absent, so the call dies with
-- "attempt to call method 'SetBackdrop' (a nil value)" and takes the whole calling stack
-- with it. Modelled as a raise rather than a silent store, because the silent store is
-- exactly what let a component paint a Layout container's own plain frame and ship green:
-- the page build died on the real client while 2925 assertions here noticed nothing.
--
-- `_hasBackdropTemplate` is set in api.lua's CreateFrame and, until this guard existed, was
-- written and never read. Only the SETTERS are gated: those are what production code calls,
-- and a spec probing a getter on an unpainted frame is asking a fair question.
local function requireBackdropTemplate(self, method)
    if not self._hasBackdropTemplate then
        error(("%s called on a frame created WITHOUT BackdropTemplate (template: %s). "):
              format(method, tostring(self._template))
              .. "The real client has no such method on this frame and would raise here.", 3)
    end
end

function FrameMeta:SetBackdrop(backdrop)
    requireBackdropTemplate(self, "SetBackdrop")
    self._backdrop = backdrop
end

function FrameMeta:GetBackdrop() return self._backdrop end

function FrameMeta:SetBackdropColor(r, g, b, a)
    requireBackdropTemplate(self, "SetBackdropColor")
    -- Colouring a backdrop that was never CREATED paints nothing in the client: SetBackdrop is
    -- what makes the textures exist and SetBackdropColor only tints them. Modelled as a no-op
    -- rather than an error, because silently nothing is exactly what the client does -- and
    -- recording the colour anyway is what let a component ship a hover highlight that was
    -- invisible in game while its spec read the colour back perfectly happily.
    if not self._backdrop then return end
    self._backdropColor = { r, g, b, a == nil and 1 or a }
end

function FrameMeta:GetBackdropColor()
    local c = self._backdropColor
    if not c then return nil end
    return c[1], c[2], c[3], c[4]
end

function FrameMeta:SetBackdropBorderColor(r, g, b, a)
    requireBackdropTemplate(self, "SetBackdropBorderColor")
    -- Same rule as SetBackdropColor above: no backdrop, nothing to tint.
    if not self._backdrop then return end
    self._backdropBorderColor = { r, g, b, a == nil and 1 or a }
end

function FrameMeta:GetBackdropBorderColor()
    local c = self._backdropBorderColor
    if not c then return nil end
    return c[1], c[2], c[3], c[4]
end

----------------------------------------------------------------------------------
-- Strata and level
----------------------------------------------------------------------------------

local STRATA_ORDER = {
    BACKGROUND = 1, LOW = 2, MEDIUM = 3, HIGH = 4,
    DIALOG = 5, FULLSCREEN = 6, FULLSCREEN_DIALOG = 7, TOOLTIP = 8,
}

M.STRATA_ORDER = STRATA_ORDER

-- SetFixedFrameStrata / SetFixedFrameLevel PIN a frame: while pinned the client ignores further
-- strata (or level) writes, and crucially the frame does not re-inherit its new parent's strata
-- when reparented. Honoured here rather than stored and ignored, because a stored-only flag
-- makes the interesting assertion vacuous: a caller that forgot to release the pin before
-- re-stating the strata would have looked identical to one that released it, and the visible
-- consequence in game -- an adopted icon drawing behind a panel that is above it -- would have
-- been invisible to every spec. LibDBIcon pins every minimap button it creates.
function FrameMeta:SetFrameStrata(s)
    assert(STRATA_ORDER[s], "harness: unknown frame strata " .. tostring(s))
    if self._fixedStrata then return end
    self._strata = s
end

function FrameMeta:GetFrameStrata()
    if self._strata then return self._strata end
    return self._parent and self._parent:GetFrameStrata() or "MEDIUM"
end

function FrameMeta:SetFrameLevel(n)
    if self._fixedLevel then return end
    self._level = n
end

function FrameMeta:GetFrameLevel()
    if self._level then return self._level end
    return (self._parent and self._parent.GetFrameLevel and self._parent:GetFrameLevel() or 0) + 1
end

function FrameMeta:SetToplevel(v) self._toplevel = v end
function FrameMeta:Raise()  self._level = self:GetFrameLevel() + 1 end
function FrameMeta:Lower()  self._level = math.max(0, self:GetFrameLevel() - 1) end
-- A clipping frame is a WINDOW: the client scissors its whole descendant subtree to this
-- frame's rect, so a child taller than the window draws only the overlapping part. The
-- flag is readable, as in the client, because a write-only flag cannot be asserted — a
-- spec claiming "these rows do not spill outside their window" would pass with clipping
-- off. H.clipsChildren / H.visibleBox / H.isClipped are built on this getter.
function FrameMeta:SetClipsChildren(v) self._clipsChildren = v and true or false end
function FrameMeta:DoesClipChildren() return self._clipsChildren == true end
function FrameMeta:SetIgnoreParentScale(v) self._ignoreParentScale = v end

----------------------------------------------------------------------------------
-- Input
----------------------------------------------------------------------------------

function FrameMeta:EnableMouse(on)  self._mouseEnabled = on and true or false end

function FrameMeta:IsMouseEnabled()
    if self._mouseEnabled ~= nil then return self._mouseEnabled end
    -- A Button and an EditBox accept mouse input without EnableMouse; a plain Frame does
    -- not. This matters beyond tidiness: third-party code relies on the Button default and
    -- never calls EnableMouse, so with the default withheld its clicks were dropped by the
    -- harness's own input routing while working perfectly in game.
    return self._mouseEnabledByDefault == true
end
function FrameMeta:EnableMouseWheel(on) self._mouseWheelEnabled = on and true or false end

-- Defaults to FALSE, like a plain Frame's mouse. Nothing in the client enables the wheel for you --
-- Blizzard's own scroll templates say `enableMouseWheel="true"` in XML -- so a frame that sets an
-- OnMouseWheel script and never enables the wheel has a script the player cannot reach. There was
-- no getter at all before this, which is why `H.scroll` fired unconditionally and two shipped
-- components had exactly that defect with a green suite.
function FrameMeta:IsMouseWheelEnabled() return self._mouseWheelEnabled == true end

function FrameMeta:EnableKeyboard(on)  self._keyboardEnabled = on and true or false end
function FrameMeta:IsKeyboardEnabled() return self._keyboardEnabled == true end
function FrameMeta:SetPropagateKeyboardInput(on) self._propagateKeyboard = on end

function FrameMeta:SetHitRectInsets(l, r, t, b)
    self._hitInsets = { left = l, right = r, top = t, bottom = b }
end

function FrameMeta:RegisterForDrag(...)   self._dragButtons = { ... } end
function FrameMeta:RegisterForClicks(...) self._clickButtons = { ... } end

-- A frame's numeric id. Mundane everywhere else in the API, but LOAD-BEARING for a stance
-- button: Blizzard's StanceButtonTemplate carries no `type` attribute (probed) and works out
-- which form to cast entirely from GetID(). The id IS the wiring, so a button created without
-- one silently casts nothing.
function FrameMeta:SetID(id) self._id = id end
function FrameMeta:GetID()   return self._id or 0 end

----------------------------------------------------------------------------------
-- Secure attributes
--
-- Every frame carries an arbitrary key/value store, and a frame built from a secure
-- template is DRIVEN by it: the template's own OnClick handler reads `unit` and a
-- per-button `type` attribute and performs the action itself. That is what lets an addon
-- target a unit or open its context menu at all — both are protected, so no addon call
-- can do it — and it is why modelling the store alone is not enough. See M.secureAction
-- below for the client half.
----------------------------------------------------------------------------------

function FrameMeta:SetAttribute(key, value)
    self._attributes = self._attributes or {}
    self._attributes[key] = value
end

function FrameMeta:GetAttribute(key)
    return self._attributes and self._attributes[key]
end

-- Frame references: the secure environment's ONLY way to reach another frame. A snippet is a
-- string compiled by the client, so it captures no Lua upvalue and closes over nothing -- a
-- header that has to touch its buttons is handed each one BY NAME out of combat and looks it up
-- when the state driver fires.
--
-- Like SetAttribute, this is not gated by the lockdown model even though the live client refuses
-- it on a protected frame in combat, so "references are set once, out of combat" is a structural
-- assertion here rather than an enforced one. See TESTING.md.
function FrameMeta:SetFrameRef(name, frame)
    self._frameRefs = self._frameRefs or {}
    self._frameRefs[name] = frame
end

function FrameMeta:GetFrameRef(name)
    return self._frameRefs and self._frameRefs[name]
end

-- The attribute vocabulary the client uses for a mouse button.
local BUTTON_INDEX = {
    LeftButton = "1", RightButton = "2", MiddleButton = "3",
    Button4 = "4", Button5 = "5",
}

-- One attribute as the client resolves it for a given button. The real lookup also walks
-- modifier prefixes ("shift-type1"); this covers the unmodified forms, which is the whole
-- vocabulary a unit frame states.
local function modifiedAttribute(f, name, button)
    local idx = BUTTON_INDEX[button or "LeftButton"] or "1"
    return f:GetAttribute("*" .. name .. idx)
        or f:GetAttribute(name .. idx)
        or f:GetAttribute("*" .. name .. "*")
        or f:GetAttribute(name .. "*")
        or f:GetAttribute(name)
end

--- The client's own handler for a frame built from a secure action template: read the
--- attributes, perform the action. Installed as the frame's OnClick when it is created
--- (see CreateFrame in api.lua), exactly as the real template installs it — so code that
--- calls SetScript("OnClick") on a secure button replaces this and silently breaks every
--- action, and a spec sees that break rather than passing on a frame that does nothing.
---
--- THE `down` GATE IS MODELLED, because leaving it out let a broken button pass. The live handler
--- compares the flag it is given against the frame's `useOnKeyDown` attribute and RETURNS EARLY
--- when they disagree — which is how an action button registered for the wrong event ends up with
--- correct attributes, a correct template, a working tooltip, working drag, and no action at all.
--- That shipped. Without this gate no assertion here could tell the two apart.
-- @param f table       The secure button
-- @param button string Which mouse button was clicked
-- @param down boolean  True for the press, false for the release
function M.secureAction(f, button, down)
    local kind = modifiedAttribute(f, "type", button)
    local unit = modifiedAttribute(f, "unit", button)
    down = down and true or false

    -- PreClick fires either way: the template's hooks are about the click, not the action.
    f:_fire("PreClick", button, down)

    -- THE GATE APPLIES TO THE ACTION PATH ONLY. `useOnKeyDown` is an action-button setting -- the
    -- client's ActionButtonUseKeyDown CVar, overridable per button -- while targeting and the unit
    -- menu act on whichever click the button registered for. Gating those too would break a unit
    -- button that deliberately registers one phase.
    --
    -- Resolved from the ATTRIBUTE if the button states one, else from the CVar. That order is what
    -- the live client does, and it is why the shipped bug happened: the button stated no attribute,
    -- the CVar said act on the press, and the button had only registered for the release -- so it
    -- never received the phase the client would have acted on. Correct attributes, correct
    -- template, and no action.
    -- THE GATE APPLIES TO THE PET PATH TOO, and that was measured rather than assumed: a pet button
    -- that registered only the release while stating `useOnKeyDown` from the CVar (which said "act on
    -- the press") stopped working on BOTH mouse buttons in game. Before this line the harness gated
    -- only the action path, so that failure was invisible to 3,900 tests -- the same shape of gap that
    -- let the identical Phase 3 bug ship.
    --
    -- `click` is deliberately NOT gated: the forward runs once per registered phase, which is why a
    -- pet button registers exactly one.
    if kind == "action" or kind == "pet" then
        local attr = f:GetAttribute("useOnKeyDown")
        local wantDown
        if attr == nil then
            wantDown = state.cvars["ActionButtonUseKeyDown"] and true or false
        else
            wantDown = attr and true or false
        end
        if down ~= wantDown then
            f:_fire("PostClick", button, down)
            return
        end
    end

    if kind == "click" then
        -- The client presses another button on this one's behalf, and it PRESERVES THE MOUSE BUTTON
        -- -- which is the whole point for pet autocast, whose target handler branches on
        -- `button == "RightButton"`. Read through modifiedAttribute so a per-button `clickbutton2`
        -- resolves, exactly as `type2` does.
        --
        -- This is how an addon reaches a protected function legitimately: it never calls it, the
        -- client does, from a handler the client itself trusts.
        local target = modifiedAttribute(f, "clickbutton", button)
        if type(target) == "table" and type(target.Click) == "function" then
            target:Click(button, down)
        end
        f:_fire("PostClick", button, down)
        return
    end

    if kind == "pet" then
        -- Recorded, like the action path: the spec's question is whether the button asked the client
        -- to use this pet slot, not what the pet then did.
        state.usedPetAction = {
            slot = tonumber(modifiedAttribute(f, "action", button)),
            button = button,
            down = down,
        }
        f:_fire("PostClick", button, down)
        return
    end

    if kind == "target" then
        -- The client's own targeting. Recorded rather than simulated: what a spec is
        -- asking is "did the frame ask the client to target this unit", and staging a new
        -- target here would also have to fire PLAYER_TARGET_CHANGED and re-answer every
        -- Unit* call, which is the client's job and not what the assertion is about.
        state.targetedUnit = unit
    elseif kind == "togglemenu" then
        -- The client opens the unit's context menu itself, from the unit attribute. No
        -- addon call is involved, which is exactly why the menu carries every entry the
        -- client would offer.
        state.unitMenu = { unit = unit }
    elseif kind == "action" then
        -- The client uses the slot named by the `action` attribute. Recorded rather than
        -- executed, for the same reason targeting is: the spec's question is "did the button
        -- ask the client to use this slot", and actually resolving the spell would mean
        -- modelling cooldowns, range, reagents and the global cooldown -- the client's job.
        --
        -- The attribute is read through modifiedAttribute, so a per-button `action2` is
        -- honoured. It arrives as whatever the addon set: SetAttribute stores a number as a
        -- number, but a secure snippet writes strings, so both shapes are normalised here
        -- rather than at every assertion.
        local slot = modifiedAttribute(f, "action", button)
        state.usedAction = { slot = tonumber(slot) or slot, button = button }
    elseif kind == "macro" then
        -- `type = "macro"` with `macrotext` is how a Classic-era client reaches an action an addon may
        -- not call directly: the client runs the macro body from inside its own secure handler, so
        -- `/use <bag> <slot>` performs a container use that `UseContainerItem` from tainted Lua is
        -- refused for.
        --
        -- Recorded rather than EXECUTED, and deliberately so: running the body would mean the harness
        -- implementing a slash-command parser and then deciding what `/use` does to the bags, which is
        -- the client's job. What a spec can prove is that the button asked for the right body.
        local body = modifiedAttribute(f, "macrotext", button)
        state.usedMacro = { text = body, button = button }
    elseif kind == "item" then
        -- `type = "item"` with a CONTAINER POSITION. The client reads `bag` and `slot` and calls
        -- UseContainerItem on them from inside its own secure handler -- which is the whole point,
        -- because that call is refused on a tainted stack. A bag cell reaches "use this item" no
        -- other way.
        --
        -- Recorded rather than enacted, exactly as the action case is: the spec's question is "did
        -- the button ask the client to use this container position", and actually resolving it would
        -- mean modelling cooldowns, casts and whether the item is usable at all.
        --
        -- The two attributes are read through modifiedAttribute so a per-button `bag2` / `slot2` is
        -- honoured -- which matters here, since a cell sets `type2` to put this on the RIGHT button
        -- and leaves left-click to its own pickup handler.
        local bag = modifiedAttribute(f, "bag", button)
        local slot = modifiedAttribute(f, "slot", button)
        state.usedSecureItem = {
            bag = tonumber(bag) or bag, slot = tonumber(slot) or slot, button = button,
        }
    end
    f:_fire("PostClick", button, down)
end

----------------------------------------------------------------------------------
-- Events
----------------------------------------------------------------------------------

function FrameMeta:RegisterEvent(event)
    self._events = self._events or {}
    self._events[event] = true
    return true
end

function FrameMeta:UnregisterEvent(event)
    if self._events then self._events[event] = nil end
end

function FrameMeta:UnregisterAllEvents()
    self._events = {}
end

function FrameMeta:IsEventRegistered(event)
    return (self._events and self._events[event]) == true
end

function FrameMeta:RegisterUnitEvent(event) return self:RegisterEvent(event) end

----------------------------------------------------------------------------------
-- Movement and sizing (drag simulation is state only; tests set geometry directly)
----------------------------------------------------------------------------------

function FrameMeta:SetMovable(v)   self._movable = v and true or false end
function FrameMeta:IsMovable()     return self._movable == true end
function FrameMeta:SetResizable(v) self._resizable = v and true or false end
function FrameMeta:IsResizable()   return self._resizable == true end
function FrameMeta:SetClampedToScreen(v) self._clamped = v and true or false end
function FrameMeta:SetUserPlaced(v)      self._userPlaced = v and true or false end
function FrameMeta:IsUserPlaced()        return self._userPlaced == true end
function FrameMeta:SetMinResize(w, h)    self._minResize = { w, h } end
function FrameMeta:SetMaxResize(w, h)    self._maxResize = { w, h } end
function FrameMeta:SetResizeBounds(minW, minH, maxW, maxH)
    self._minResize, self._maxResize = { minW, minH }, { maxW, maxH }
end

function FrameMeta:GetResizeBounds()
    local minr, maxr = self._minResize, self._maxResize
    return minr and minr[1], minr and minr[2], maxr and maxr[1], maxr and maxr[2]
end

-- The client drives a user resize itself while StartSizing is active, clamping the
-- result to the resize bounds. Programmatic SetSize is deliberately NOT clamped, which
-- matches the real client: the bounds govern user resizing only.
function FrameMeta:_userResize(w, h)
    assert(self._sizing, "harness: _userResize without an active StartSizing")
    local minr, maxr = self._minResize, self._maxResize
    if minr then
        w, h = math.max(w, minr[1] or w), math.max(h, minr[2] or h)
    end
    if maxr then
        w, h = math.min(w, maxr[1] or w), math.min(h, maxr[2] or h)
    end
    self:SetSize(w, h)
end

function FrameMeta:StartMoving()
    assert(self._movable, "harness: StartMoving on a frame that is not movable")
    self._moving = true
end

function FrameMeta:StartSizing(point)
    assert(self._resizable, "harness: StartSizing on a frame that is not resizable")
    self._sizing = point or "BOTTOMRIGHT"
end

function FrameMeta:StopMovingOrSizing()
    self._moving, self._sizing = false, nil
end

function FrameMeta:IsDragging() return self._moving == true end

----------------------------------------------------------------------------------
-- Animation groups
----------------------------------------------------------------------------------

-- SuuUI never calls this -- it runs its own shared-OnUpdate animator -- but embedded
-- third-party code does, and the load dies without it. See wow/animation.lua for why the
-- model records configuration rather than ticking.
function FrameMeta:CreateAnimationGroup(name)
    local g = anim.newGroup(self, name)
    self._animGroups = self._animGroups or {}
    self._animGroups[#self._animGroups + 1] = g
    return g
end

--- Every animation group created on this frame, in creation order. Harness-only: the
--- client offers GetAnimationGroups, but a spec wants the list without naming them.
function FrameMeta:GetAnimationGroups() return self._animGroups or {} end

----------------------------------------------------------------------------------
-- Strata and level pinning
----------------------------------------------------------------------------------

-- The client uses these to stop its own layout passes from re-deriving a frame's place in
-- the z-order. Stored and readable rather than enforced: nothing in the harness re-derives
-- strata, so there is no automatic adjustment here for the flag to suppress. Modelled
-- because third-party code calls them unconditionally.
function FrameMeta:SetFixedFrameStrata(fixed) self._fixedStrata = fixed and true or false end
function FrameMeta:HasFixedFrameStrata()      return self._fixedStrata == true end
function FrameMeta:SetFixedFrameLevel(fixed)  self._fixedLevel = fixed and true or false end
function FrameMeta:HasFixedFrameLevel()       return self._fixedLevel == true end
-- The Is… spelling as well, because the client's getter is named Is… on some generations and
-- Has… on others while the SETTER is stable. Both answer here so code that probes either name
-- is genuinely exercised rather than silently taking its "no getter" fallback in every spec.
function FrameMeta:IsFixedFrameStrata()       return self._fixedStrata == true end
function FrameMeta:IsFixedFrameLevel()        return self._fixedLevel == true end

----------------------------------------------------------------------------------
-- EditBox
----------------------------------------------------------------------------------

-- An EditBox accepts mouse input without EnableMouse, unlike a plain Frame.
local EditBoxMeta = derive(FrameMeta)
EditBoxMeta._mouseEnabledByDefault = true
M.EditBoxMeta = EditBoxMeta

function EditBoxMeta:SetText(text)
    text = text == nil and "" or tostring(text)
    if self._maxLetters and #text > self._maxLetters then
        text = text:sub(1, self._maxLetters)
    end
    self._text = text
    self._cursor = #text
    -- The real client fires OnTextChanged for programmatic SetText too, which is why
    -- Input.lua guards it with a silent flag. Preserving that is the point.
    self:_fire("OnTextChanged", false)
end

function EditBoxMeta:GetText() return self._text or "" end
function EditBoxMeta:SetNumber(n) self:SetText(tostring(n)) end
function EditBoxMeta:GetNumber()  return tonumber(self._text) or 0 end

function EditBoxMeta:SetAutoFocus(on)
    self._autoFocus = on and true or false
    if self._autoFocus then self:SetFocus() end
end

function EditBoxMeta:SetMaxLetters(n) self._maxLetters = n end
function EditBoxMeta:GetMaxLetters()  return self._maxLetters end
function EditBoxMeta:SetCursorPosition(p) self._cursor = p end
function EditBoxMeta:GetCursorPosition()  return self._cursor or 0 end
function EditBoxMeta:SetMultiLine(on)     self._multiLine = on and true or false end
function EditBoxMeta:SetNumeric(on)       self._numeric = on and true or false end
-- Recorded, not a no-op. It was an empty stub, which made "the value is selected" unassertable --
-- and a focused box with an unselected value is precisely how a copy dialog ships uncopyable. No
-- arguments means the whole value, which is the client's own contract.
function EditBoxMeta:HighlightText(from, to)
    self._highlight = { from = from or 0, to = to or -1 }
end

-- nil when nothing is selected. `to == -1` is the client's "to the end".
function EditBoxMeta:GetHighlight() return self._highlight end

function EditBoxMeta:SetTextInsets(...)   self._textInsets = { ... } end
-- Readable, so a spec can assert the insets an adopted box was given. Write-only, the
-- adoption's inset tightening could not be asserted at all.
function EditBoxMeta:GetTextInsets()
    local t = self._textInsets or {}
    return t[1] or 0, t[2] or 0, t[3] or 0, t[4] or 0
end

--- Raises for an asset the client cannot load, as the real client does.
--- See FontStringMeta:SetFont.
function EditBoxMeta:SetFont(path, size, flags)
    if not font.hasFace(path) then
        error("EditBox:SetFont(): Invalid font asset (" .. tostring(path)
              .. "): file not found", 2)
    end
    self._font, self._fontSize, self._fontFlags = path, size, flags
    return true
end

function EditBoxMeta:GetFont() return self._font, self._fontSize, self._fontFlags end

function EditBoxMeta:SetTextColor(r, g, b, a)
    self._textColor = { r, g, b, a == nil and 1 or a }
end

function EditBoxMeta:GetTextColor()
    local c = self._textColor or { 1, 1, 1, 1 }
    return c[1], c[2], c[3], c[4]
end

function EditBoxMeta:SetFocus()
    if state.focused == self then return end
    local prev = state.focused
    state.focused = self
    if prev then prev:_fire("OnEditFocusLost") end
    self:_fire("OnEditFocusGained")
end

function EditBoxMeta:ClearFocus()
    if state.focused ~= self then return end
    state.focused = nil
    self:_fire("OnEditFocusLost")
end

function EditBoxMeta:HasFocus() return state.focused == self end

function EditBoxMeta:SetEnabled(on)
    self._editEnabled = on and true or false
end

function EditBoxMeta:IsEnabled() return self._editEnabled ~= false end
function EditBoxMeta:Enable()    self:SetEnabled(true) end
function EditBoxMeta:Disable()   self:SetEnabled(false) end

----------------------------------------------------------------------------------
-- ScrollFrame
----------------------------------------------------------------------------------

local ScrollFrameMeta = derive(FrameMeta)
M.ScrollFrameMeta = ScrollFrameMeta

local function anchorScrollChild(self)
    local child = self._scrollChild
    if not child then return end
    child:ClearAllPoints()
    child:SetPoint("TOPLEFT", self, "TOPLEFT",
        -(self._hScroll or 0), (self._vScroll or 0))
end

function ScrollFrameMeta:SetScrollChild(child)
    self._scrollChild = child
    child:SetParent(self)
    anchorScrollChild(self)
end

function ScrollFrameMeta:GetScrollChild() return self._scrollChild end

function ScrollFrameMeta:SetVerticalScroll(v)
    self._vScroll = v or 0
    anchorScrollChild(self)
    self:_fire("OnVerticalScroll", self._vScroll)
end

function ScrollFrameMeta:GetVerticalScroll() return self._vScroll or 0 end

function ScrollFrameMeta:SetHorizontalScroll(v)
    self._hScroll = v or 0
    anchorScrollChild(self)
end

function ScrollFrameMeta:GetHorizontalScroll() return self._hScroll or 0 end

function ScrollFrameMeta:GetVerticalScrollRange()
    local child = self._scrollChild
    if not child then return 0 end
    return math.max(0, child:GetHeight() - self:GetHeight())
end

function ScrollFrameMeta:UpdateScrollChildRect() anchorScrollChild(self) end

----------------------------------------------------------------------------------
-- Button (present for completeness; SuuUI builds its controls from plain frames)
----------------------------------------------------------------------------------

local ButtonMeta = derive(FrameMeta)
ButtonMeta._mouseEnabledByDefault = true
M.ButtonMeta = ButtonMeta

function ButtonMeta:SetText(t)  self._buttonText = t end
function ButtonMeta:GetText()   return self._buttonText end
function ButtonMeta:SetEnabled(on) self._buttonEnabled = on and true or false end
function ButtonMeta:IsEnabled()    return self._buttonEnabled ~= false end
function ButtonMeta:Enable()  self:SetEnabled(true) end
function ButtonMeta:Disable() self:SetEnabled(false) end
function ButtonMeta:Click(button) self:_fire("OnClick", button or "LeftButton") end

-- CheckButton's own state. A stance button uses this to show which form is active, so it is the
-- observable a spec asserts against rather than an internal flag on the component.
function ButtonMeta:SetChecked(on) self._checked = on and true or false end
function ButtonMeta:GetChecked()   return self._checked == true end
-- The four texture setters REFUSE nil, exactly as the client does:
--   bad argument #2 to '?' (Usage: self:SetNormalTexture(asset))
--
-- Modelled strictly because the permissive version hid a real bug: a component cleared the
-- template's art by passing nil, every spec passed, and in game the call raised during construction
-- and took the whole bar down. To CLEAR one of these, take the Texture from the getter and hide it.
local function requireAsset(method, asset)
    if asset == nil then
        error(("bad argument #2 to '?' (Usage: self:%s(asset))"):format(method), 3)
    end
end

function ButtonMeta:SetNormalTexture(t)
    requireAsset("SetNormalTexture", t)
    self._normalTexture = t
end
function ButtonMeta:GetNormalTexture()  return self._normalTexture end

-- The rest of a Button's texture slots, plus the highlight lock. Stored rather than drawn:
-- the harness models geometry and state, and none of these change a rect. A drag
-- implementation locks the highlight for the duration of the gesture, so the lock is
-- readable -- a write-only flag could not be asserted.
function ButtonMeta:SetPushedTexture(t)
    requireAsset("SetPushedTexture", t)
    self._pushedTexture = t
end
function ButtonMeta:GetPushedTexture()     return self._pushedTexture end
function ButtonMeta:SetDisabledTexture(t)
    requireAsset("SetDisabledTexture", t)
    self._disabledTexture = t
end
function ButtonMeta:GetDisabledTexture()   return self._disabledTexture end
function ButtonMeta:SetHighlightTexture(t, blend)
    requireAsset("SetHighlightTexture", t)
    self._highlightTexture = t
    self._highlightBlend   = blend
end
function ButtonMeta:GetHighlightTexture()  return self._highlightTexture end
function ButtonMeta:LockHighlight()        self._highlightLocked = true end
function ButtonMeta:UnlockHighlight()      self._highlightLocked = false end
function ButtonMeta:IsHighlightLocked()    return self._highlightLocked == true end
function ButtonMeta:SetMotionScriptsWhileDisabled(on)
    self._motionWhileDisabled = on and true or false
end

----------------------------------------------------------------------------------
-- Cooldown
----------------------------------------------------------------------------------

local CooldownMeta = derive(FrameMeta)
M.CooldownMeta = CooldownMeta

function CooldownMeta:SetCooldown(start, duration)
    self._cdStart    = start
    self._cdDuration = duration
end

function CooldownMeta:GetCooldownTimes()
    return self._cdStart or 0, self._cdDuration or 0, 0
end

function CooldownMeta:Clear()
    self._cdStart, self._cdDuration = nil, nil
end

function CooldownMeta:SetDrawSwipe(on)       self._drawSwipe = on and true or false end
function CooldownMeta:SetDrawEdge(on)        self._drawEdge = on and true or false end
function CooldownMeta:SetHideCountdownNumbers(on) self._hideNumbers = on and true or false end
function CooldownMeta:SetReverse(on)         self._reverse = on and true or false end
function CooldownMeta:SetSwipeColor(r, g, b, a)
    self._swipeColor = { r, g, b, a == nil and 1 or a }
end

----------------------------------------------------------------------------------
-- StatusBar
----------------------------------------------------------------------------------

-- A real type rather than the bare Frame this used to be. SuuUI's own StatusBar component
-- does not use the client's -- it drives fractional stack children through the layout
-- engine on purpose -- so nothing here needed it until a BLIZZARD status bar had to be
-- driven: GameTooltipStatusBar is the client's, and a tooltip health bar is read through
-- SetValue / GetValue / SetStatusBarColor and through nothing else.
--
-- The value is CLAMPED to the range, which is what the client does and what makes the
-- difference between "the bar is full" and "the bar was handed a number larger than max".
-- A consumer that computes a fraction from GetValue would otherwise read past 1.
local StatusBarMeta = derive(FrameMeta)
M.StatusBarMeta = StatusBarMeta

function StatusBarMeta:SetMinMaxValues(min, max)
    self._barMin = min
    self._barMax = max
    -- Re-clamp: the client does not leave a value stranded outside a newly narrowed range.
    if self._barValue ~= nil then self:SetValue(self._barValue) end
end

function StatusBarMeta:GetMinMaxValues()
    return self._barMin or 0, self._barMax or 100
end

function StatusBarMeta:SetValue(v)
    if type(v) ~= "number" or v ~= v then return end
    local min, max = self:GetMinMaxValues()
    if v < min then v = min end
    if v > max then v = max end
    local old = self._barValue
    self._barValue = v
    if old ~= v then self:_fire("OnValueChanged", v) end
end

function StatusBarMeta:GetValue() return self._barValue or 0 end

function StatusBarMeta:SetStatusBarTexture(tex)
    self._barTexture = tex
end

function StatusBarMeta:GetStatusBarTexture()
    return self._barTexture
end

function StatusBarMeta:SetStatusBarColor(r, g, b, a)
    self._barColor = { r, g, b, a == nil and 1 or a }
end

function StatusBarMeta:GetStatusBarColor()
    local c = self._barColor
    if not c then return 1, 1, 1, 1 end
    return c[1], c[2], c[3], c[4]
end

function StatusBarMeta:SetOrientation(o) self._barOrientation = o end
function StatusBarMeta:GetOrientation() return self._barOrientation or "HORIZONTAL" end

function StatusBarMeta:SetReverseFill(on) self._barReverse = not not on end
function StatusBarMeta:GetReverseFill() return self._barReverse == true end

----------------------------------------------------------------------------------
-- GameTooltip
----------------------------------------------------------------------------------

-- A frame TYPE rather than the one bolted-on singleton this used to be, because the client
-- lets anyone create their own instance and embedded third-party code does exactly that
-- (LibDBIcon makes LibDBIconTooltip at load, and CreateFrame refused the type outright).
-- api.lua now builds the shared GameTooltip from this same meta, so there is ONE
-- implementation instead of two drifting ones.
--
-- Text is recorded, never rendered: a spec can count lines and read them back, which is
-- what an assertion about a tooltip's CONTENT needs, but no font metrics are involved and
-- nothing here wraps or measures. state.tooltip records the LAST tooltip interaction from
-- any instance, so H.getTooltipState() answers for whichever tooltip was used most recently.
local GameTooltipMeta = derive(FrameMeta)
M.GameTooltipMeta = GameTooltipMeta

function GameTooltipMeta:SetOwner(owner, anchor)
    self._owner  = owner
    self._anchor = anchor
    self._lines  = {}
    state.tooltip = state.tooltip or {}
    state.tooltip.owner  = owner
    state.tooltip.anchor = anchor
    state.tooltip.aura   = nil
end

function GameTooltipMeta:GetOwner()  return self._owner end
function GameTooltipMeta:GetAnchorType() return self._anchor end

function GameTooltipMeta:SetUnitBuff(unit, index)
    state.tooltip = state.tooltip or {}
    state.tooltip.aura = { unit = unit, index = index, filter = "HELPFUL" }
end

function GameTooltipMeta:SetUnitDebuff(unit, index)
    state.tooltip = state.tooltip or {}
    state.tooltip.aura = { unit = unit, index = index, filter = "HARMFUL" }
end

function GameTooltipMeta:SetUnitAura(unit, index, filter)
    state.tooltip = state.tooltip or {}
    state.tooltip.aura = { unit = unit, index = index, filter = filter or "HELPFUL" }
end

-- The client builds an action's whole tooltip itself -- name, cost, range, cast time, the lot --
-- from the slot alone. Recorded rather than rendered, for the same reason the aura setters are:
-- the question a spec asks is "was the tooltip pointed at this slot", and reproducing the client's
-- formatting here would be asserting against the harness's version of it.
function GameTooltipMeta:SetAction(slot)
    state.tooltip = state.tooltip or {}
    state.tooltip.action = slot
    self._tooltipShown = true

    -- It DOES fire OnTooltipSetSpell, and GetSpell answers for the slot. MEASURED in game: an
    -- action-button tooltip showed the spell id TWICE, once from a consumer's SetAction hook and
    -- once from its OnTooltipSetSpell hook.
    --
    -- This model previously claimed the opposite, with a comment defending it -- and that wrong
    -- claim is what hid the duplicate, since in the harness only one path could ever fire. Same
    -- failure as a harness that is too generous, in reverse: a model that is too STINGY makes a
    -- redundant code path look necessary.
    local infoFn = state.env and state.env.GetActionInfo
    if type(infoFn) == "function" then
        local kind, id = infoFn(slot)
        if kind == "spell" and type(id) == "number" then
            self._ttSpell = id
            self:_fire("OnTooltipSetSpell")
        elseif kind == "item" and type(id) == "number" then
            self._ttItem = tostring(id)
            self:_fire("OnTooltipSetItem")
        end
    end
end

function GameTooltipMeta:ClearLines()
    self._lines = {}
    state.tooltip = state.tooltip or {}
    state.tooltip.aura = nil
    -- The client fires this, and a consumer resetting per-show state (a quality-coloured
    -- border, reserved padding) hangs its whole reset off it. A model that stayed silent
    -- would let a spec assert the reset by calling the handler by hand -- which passes
    -- while nothing in production ever reaches it.
    self:_fire("OnTooltipCleared")
end

-- Publishes the per-line font strings the way the CLIENT does, in both shapes it ships:
--
--   tt.TextLeft<i>  -- an INSTANCE field, present on every tooltip. This is the one production
--                      code should read, because it is correct for any instance.
--   GameTooltipTextLeft<i>  -- a GLOBAL, and only for the shared tooltip.
--
-- Both are modelled because a consumer reading the wrong one is a real bug: the globals are nil
-- for a ShoppingTooltip, so code that works on GameTooltip silently does nothing there.
--
-- Stale entries survive a ClearLines, exactly as the client's own pooled font strings do. A
-- consumer iterating 1..NumLines() never reaches them; one indexing blindly past the line count
-- gets the same wrong answer it would get in game.
local function publishLineGlobals(tt)
    local n = #(tt._lines or {})
    for i = 1, n do
        tt["TextLeft" .. i]  = tt:_lineFontString(i, "left")
        tt["TextRight" .. i] = tt:_lineFontString(i, "right")
    end
    local env = state.env
    if not env or env.GameTooltip ~= tt then return end
    for i = 1, n do
        env["GameTooltipTextLeft" .. i]  = tt["TextLeft" .. i]
        env["GameTooltipTextRight" .. i] = tt["TextRight" .. i]
    end
end

function GameTooltipMeta:AddLine(text, r, g, b, wrap)
    self._lines = self._lines or {}
    self._lines[#self._lines + 1] = { text = text, r = r, g = g, b = b, wrap = wrap }
    publishLineGlobals(self)
end

-- The right-hand colours are RECORDED. They used to be accepted and thrown away, which made
-- every assertion about a right-hand value's colour vacuous -- and a right-hand value is
-- exactly where a tooltip puts a tone-coloured reading (an item level, a count, a latency).
function GameTooltipMeta:AddDoubleLine(left, right, lr, lg, lb, rr, rg, rb)
    self._lines = self._lines or {}
    self._lines[#self._lines + 1] = {
        text = left, right = right,
        r = lr, g = lg, b = lb,
        rr = rr, rg = rg, rb = rb,
    }
    publishLineGlobals(self)
end

function GameTooltipMeta:SetText(text, r, g, b)
    self._lines = { { text = text, r = r, g = g, b = b } }
    publishLineGlobals(self)
end

function GameTooltipMeta:NumLines() return #(self._lines or {}) end

--- The text of one line, 1-based, as the client's GameTooltipTextLeft<i> would carry it.
-- Harness-only convenience: reading a global font string per line models nothing useful.
function GameTooltipMeta:GetLine(i)
    local line = (self._lines or {})[i]
    return line and line.text, line and line.right
end

--- The colours of one line: left r,g,b then right r,g,b. Harness-only, and separate from
--- GetLine so the existing two-value contract is untouched.
function GameTooltipMeta:GetLineColor(i)
    local l = (self._lines or {})[i]
    if not l then return nil end
    return l.r, l.g, l.b, l.rr, l.rg, l.rb
end

--- The per-line font string, as the client's GameTooltipTextLeft<i> global.
--
-- TESTING.md used to say NOT to model these, on the grounds that reading a global font string
-- per line models nothing useful. That was true while nothing needed to WRITE one -- and it
-- stopped being true the moment a reskin had to RECOLOUR a line the client itself wrote (the
-- level line, by creature difficulty). There is no other route to that: the text belongs to
-- Blizzard, so the only handle on it is its font string.
--
-- So these are real, and deliberately BACKED BY THE SAME LINE RECORD GetLine reads. A
-- SetTextColor here is visible through GetLineColor, which means a spec asserts the colour
-- through one channel however it was set -- rather than the two drifting apart, which is the
-- failure the original rule was guarding against.
function GameTooltipMeta:_lineFontString(i, side)
    self._lines = self._lines or {}
    local rec = self._lines[i]
    if not rec then return nil end
    local key = side == "right" and "_fsRight" or "_fsLeft"
    if rec[key] then return rec[key] end

    local fs = {
        _kind = "FontString",
        GetText = function() return side == "right" and rec.right or rec.text end,
        SetText = function(_, t)
            if side == "right" then rec.right = t else rec.text = t end
        end,
        SetTextColor = function(_, r, g, b)
            if side == "right" then
                rec.rr, rec.rg, rec.rb = r, g, b
            else
                rec.r, rec.g, rec.b = r, g, b
            end
        end,
        GetTextColor = function()
            if side == "right" then return rec.rr, rec.rg, rec.rb end
            return rec.r, rec.g, rec.b
        end,
        Show = function() rec.hidden = nil end,
        Hide = function() rec.hidden = true end,
        IsShown = function() return not rec.hidden end,
        SetFont = function() return true end,
    }
    rec[key] = fs
    return fs
end

----------------------------------------------------------------------------------
-- Tooltip content setters
--
-- Each one records what it was pointed at AND FIRES the client's matching script. The
-- firing is the point: those four scripts were stored by SetScript and never fired by any
-- harness path, so a spec could only reach a handler by invoking it by hand -- which passes
-- while nothing in production ever calls it. That exact mistake shipped a dead micro-menu
-- button, so the setters drive the scripts here instead.
--
-- Content is recorded, never formatted. Reproducing the client's own line layout would mean
-- asserting against the harness's version of it rather than against the client's.
----------------------------------------------------------------------------------

function GameTooltipMeta:SetUnit(unit)
    state.tooltip = state.tooltip or {}
    state.tooltip.unit = unit
    self._ttUnit = unit
    self._tooltipShown = true
    self:_fire("OnTooltipSetUnit")
end

function GameTooltipMeta:GetUnit()
    -- The client answers a NAME and a unit id, in that order.
    local unit = self._ttUnit
    if not unit then return nil, nil end
    local nameFn = state.env and state.env.UnitName
    return (type(nameFn) == "function" and nameFn(unit)) or unit, unit
end

function GameTooltipMeta:SetHyperlink(link)
    state.tooltip = state.tooltip or {}
    state.tooltip.item = link
    self._ttItem = link
    self._tooltipShown = true
    self:_fire("OnTooltipSetItem")
end

function GameTooltipMeta:SetBagItem(bag, slot)
    state.tooltip = state.tooltip or {}
    state.tooltip.bagItem = { bag = bag, slot = slot }
    self._ttItem = state.tooltip.item
    self._tooltipShown = true
    self:_fire("OnTooltipSetItem")
end

--- Returns hasItem, hasCooldown, repairCost, matching the client's own return order.
function GameTooltipMeta:SetInventoryItem(unit, slot)
    state.tooltip = state.tooltip or {}
    state.tooltip.inventoryItem = { unit = unit, slot = slot }
    local linkFn = state.env and state.env.GetInventoryItemLink
    local link = type(linkFn) == "function" and linkFn(unit, slot) or nil
    self._ttItem = link
    state.tooltip.item = link
    self._tooltipShown = true
    self:_fire("OnTooltipSetItem")
    return link ~= nil, false, 0
end

--- The item this tooltip is showing: name, link. Both nil when it is not showing one.
function GameTooltipMeta:GetItem()
    local link = self._ttItem
    if not link then return nil, nil end
    local infoFn = state.env and state.env.GetItemInfo
    local name = type(infoFn) == "function" and infoFn(link) or nil
    return name or link, link
end

function GameTooltipMeta:SetSpellByID(spellId)
    state.tooltip = state.tooltip or {}
    state.tooltip.spell = spellId
    self._ttSpell = spellId
    self._tooltipShown = true
    self:_fire("OnTooltipSetSpell")
end

function GameTooltipMeta:SetSpellBookItem(index, book)
    state.tooltip = state.tooltip or {}
    state.tooltip.spellBookItem = { index = index, book = book }
    self._tooltipShown = true
    self:_fire("OnTooltipSetSpell")
end

--- The spell this tooltip is showing: name, spellID. Removed in retail, present here.
function GameTooltipMeta:GetSpell()
    local id = self._ttSpell
    if not id then return nil, nil end
    return "Spell " .. tostring(id), id
end

----------------------------------------------------------------------------------
-- Padding
--
-- Verified present on this client in both the two-arg and four-arg forms, along with
-- GetPadding, so a caller reserving space at the bottom of a tooltip can read back what it
-- reserved. Modelled as pure state: the harness does not lay tooltips out, so padding
-- changes no geometry here and a spec must assert the VALUE rather than a height.
----------------------------------------------------------------------------------

function GameTooltipMeta:SetPadding(right, bottom, left, top)
    self._padRight  = right  or 0
    self._padBottom = bottom or 0
    self._padLeft   = left   or 0
    self._padTop    = top    or 0
end

function GameTooltipMeta:GetPadding()
    return self._padRight or 0, self._padBottom or 0, self._padLeft or 0, self._padTop or 0
end

--- Blizzard's own guard, checked at the top of nearly every tooltip entry point. Always
--- false here: a forbidden frame is a retail protected-frame concept with no model.
function GameTooltipMeta:IsForbidden() return false end

function GameTooltipMeta:Show()
    self._tooltipShown = true
    self._shown = true
end

function GameTooltipMeta:Hide()
    self._tooltipShown = false
    self._shown = false
end

function GameTooltipMeta:IsShown() return self._tooltipShown == true end

----------------------------------------------------------------------------------
-- ScrollingMessageFrame
----------------------------------------------------------------------------------

-- The client's own scrolling text log: word wrap, a line cap, timed fading, scrolling and
-- per-line hyperlink hit-testing, none of which an addon has to write. Two installed addons
-- create one on this client (DBM-GUI's panel prototype and ElvUI's AFK screen), so it is real
-- rather than assumed.
--
-- MODELLED WITH ITS REFUSALS, not just its capabilities, because this harness's documented
-- failure mode is permissiveness -- it hands every frame every method, which is how the combat
-- lockdown and hidden-frame gaps let broken code stay green. Two refusals are modelled here:
--   * AddMessage exists ONLY on this meta, so calling it on a plain Frame raises. A consumer
--     that creates the wrong frame type cannot silently appear to work.
--   * A log with no font set DRAWS NOTHING. The client cannot lay out a line without a font,
--     and the failure in game is silent -- the frame is present, sized and reports its
--     messages, and renders empty. H.getChatLines() is the observable; see its comment for why
--     that lives on H rather than on the frame.
local ScrollingMessageFrameMeta = derive(FrameMeta)
M.ScrollingMessageFrameMeta = ScrollingMessageFrameMeta

-- Blizzard's own default, set in ChatFrame_OnLoad. Modelled as the default so a consumer that
-- never raises it inherits the real ceiling rather than an unlimited buffer -- 128 is the number
-- to beat, and a spec asserting a deeper scrollback has to say so.
local DEFAULT_MAX_LINES = 128

function ScrollingMessageFrameMeta:_initMessages()
    if not self._messages then
        self._messages   = {}
        self._maxLines   = DEFAULT_MAX_LINES
        self._scroll     = 0
        self._insertMode = "BOTTOM"
    end
end

--- Appends one message. Index 1 is the OLDEST, which is the order ElvUI's copy-chat loop reads
--- them in (`for i = 1, GetNumMessages()`), so a consumer that walks them builds the transcript
--- top to bottom.
function ScrollingMessageFrameMeta:AddMessage(text, r, g, b, id)
    self:_initMessages()
    assert(type(text) == "string" or type(text) == "number",
        "harness: AddMessage needs a string, got " .. type(text))
    table.insert(self._messages, {
        text = tostring(text), r = r, g = g, b = b, id = id,
    })
    -- The cap trims the OLDEST, which is what makes a log a rolling window.
    while #self._messages > self._maxLines do table.remove(self._messages, 1) end
    -- A new message at the bottom does not move a reader who has scrolled up: the client holds
    -- their position and the unread simply accumulates below them. That is the behaviour a
    -- jump-to-bottom affordance exists for, so modelling it wrongly would make that untestable.
    if self._scroll > 0 then
        self._scroll = math.min(self._scroll + 1, math.max(0, #self._messages - 1))
    end
end

function ScrollingMessageFrameMeta:GetNumMessages()
    self:_initMessages()
    return #self._messages
end

--- Returns message, r, g, b, id for one line, oldest first. Five values, as the client's does.
function ScrollingMessageFrameMeta:GetMessageInfo(i)
    self:_initMessages()
    local rec = self._messages[i]
    if not rec then return nil end
    return rec.text, rec.r, rec.g, rec.b, rec.id
end

function ScrollingMessageFrameMeta:Clear()
    self:_initMessages()
    self._messages = {}
    self._scroll   = 0
end

-- Horizontal justification. Modelled with the CLIENT's default of "CENTER" rather than "LEFT",
-- which is the whole reason it is here: a bare CreateFrame("ScrollingMessageFrame") centres every
-- line, Blizzard's own chat frames are LEFT only because their XML template says so, and with
-- this absent from the harness nothing could tell the two apart. A centre-justified chat log
-- shipped and was found by looking at the game -- one line sat 135 units right of the chip below
-- it, which is exactly half the slack in a 460-wide frame.
--
-- The harness lays out no text, so this is a recorder: it proves the CALL was made, not that the
-- glyphs moved. See "GameTooltip ... renders nothing" in TESTING.md for the same contract.
-- A message frame carries FontInstance's shadow methods, and a frameless log over the game world
-- needs them: the concept gives every chat line a text-shadow because there is no panel behind it.
function ScrollingMessageFrameMeta:SetShadowColor(r, g, b, a)
    self._shadowColor = { r, g, b, a == nil and 1 or a }
end
function ScrollingMessageFrameMeta:GetShadowColor()
    local c = self._shadowColor
    if not c then return 0, 0, 0, 0 end
    return c[1], c[2], c[3], c[4]
end
function ScrollingMessageFrameMeta:SetShadowOffset(x, y) self._shadowX, self._shadowY = x, y end
function ScrollingMessageFrameMeta:GetShadowOffset() return self._shadowX or 0, self._shadowY or 0 end

function ScrollingMessageFrameMeta:SetJustifyH(j) self._justifyH = j end
function ScrollingMessageFrameMeta:GetJustifyH()  return self._justifyH or "CENTER" end
function ScrollingMessageFrameMeta:SetJustifyV(j) self._justifyV = j end
function ScrollingMessageFrameMeta:GetJustifyV()  return self._justifyV or "MIDDLE" end

function ScrollingMessageFrameMeta:SetMaxLines(n)    self:_initMessages()
    self._maxLines = n
    while #self._messages > self._maxLines do table.remove(self._messages, 1) end
end

function ScrollingMessageFrameMeta:GetMaxLines()
    self:_initMessages()
    return self._maxLines
end

-- Fading is the whole reason a frameless chat is affordable: the client times it, so the addon
-- sets three values and writes no ticker. Stored rather than simulated -- the harness has no
-- render loop, and a spec asserting "it faded" would be asserting against our own timer instead
-- of the client's. What a spec CAN prove is that a channel log enables it and a conversation log
-- does not, which is the design rule these back.
function ScrollingMessageFrameMeta:SetFading(on)          self._fading = on and true or false end
function ScrollingMessageFrameMeta:GetFading()            return self._fading == true end
function ScrollingMessageFrameMeta:SetTimeVisible(secs)   self._timeVisible = secs end
function ScrollingMessageFrameMeta:GetTimeVisible()       return self._timeVisible end
function ScrollingMessageFrameMeta:SetFadeDuration(secs)  self._fadeDuration = secs end

-- ResetAllFadeTimes: COUNTED rather than enacted. In the client this restarts every line's fade
-- clock, which is what brings faded text back -- ElvUI calls it immediately before its own frame
-- fade-in. Per-line clocks are not modelled here, so the observable is that it was CALLED: a reveal
-- that sets alpha and forgets this leaves the text visible for one frame and gone the next, and a
-- count is the only thing a spec can hold onto. Model what a caller can observe, nothing beyond.
function ScrollingMessageFrameMeta:ResetAllFadeTimes()
    self._fadeResets = (self._fadeResets or 0) + 1
end

function ScrollingMessageFrameMeta:GetFadeResetCount() return self._fadeResets or 0 end
function ScrollingMessageFrameMeta:GetFadeDuration()      return self._fadeDuration end

function ScrollingMessageFrameMeta:SetInsertMode(mode)
    self:_initMessages()
    self._insertMode = mode
end
function ScrollingMessageFrameMeta:GetInsertMode()
    self:_initMessages()
    return self._insertMode
end

-- Hyperlink hit-testing, and the refusal that matters: dispatch does NOTHING until a consumer
-- calls SetHyperlinksEnabled(true). In game that presents as item links that look perfect and
-- are dead to the click, so leaving it permissive would hide the single most likely wiring bug
-- in a chat log. Enforced in H.clickHyperlink.
function ScrollingMessageFrameMeta:SetHyperlinksEnabled(on)
    self._hyperlinksEnabled = on and true or false
end
function ScrollingMessageFrameMeta:GetHyperlinksEnabled()
    return self._hyperlinksEnabled == true
end

-- The scroll window. Offset 0 is the BOTTOM (newest), counting upward, which is the direction
-- the client's ScrollUp moves. The ceiling is the message count rather than a computed
-- lines-per-page: the harness has no line layout, and inventing one would let a spec assert a
-- page size the client never agreed to.
function ScrollingMessageFrameMeta:ScrollUp()
    self:_initMessages()
    self._scroll = math.min(self._scroll + 1, math.max(0, #self._messages - 1))
end
function ScrollingMessageFrameMeta:ScrollDown()
    self:_initMessages()
    self._scroll = math.max(self._scroll - 1, 0)
end
function ScrollingMessageFrameMeta:PageUp()
    self:_initMessages()
    self._scroll = math.min(self._scroll + 10, math.max(0, #self._messages - 1))
end
function ScrollingMessageFrameMeta:PageDown()
    self:_initMessages()
    self._scroll = math.max(self._scroll - 10, 0)
end
function ScrollingMessageFrameMeta:ScrollToTop()
    self:_initMessages()
    self._scroll = math.max(0, #self._messages - 1)
end
function ScrollingMessageFrameMeta:ScrollToBottom()
    self:_initMessages()
    self._scroll = 0
end
-- MEASURED on this client (interface 20504): the getter is `GetScrollOffset`, and
-- `GetCurrentScroll` DOES NOT EXIST -- probed directly, it answers nil while every other method this
-- addon calls on a ScrollingMessageFrame answers `function`. It was modelled here under the wrong
-- name, so the whole scroll block of 00_harness_spec passed against an API the client does not have
-- and the first wheel turn in game raised "attempt to call a nil value" 29 times. Deliberately NOT
-- aliased to both names: modelling a method the client lacks is what let this ship.
function ScrollingMessageFrameMeta:GetScrollOffset()
    self:_initMessages()
    return self._scroll
end
function ScrollingMessageFrameMeta:AtBottom()
    self:_initMessages()
    return self._scroll == 0
end

-- The font. A message frame is a FontInstance, so it carries these directly rather than through
-- a child region -- and SetFont RAISES on an unloadable asset exactly as FontString:SetFont
-- does here and in the client, because that throw has already cost this addon a broken login.
function ScrollingMessageFrameMeta:SetFont(path, size, flags)
    if not font.hasFace(path) then
        error("ScrollingMessageFrame:SetFont(): Invalid font asset (" .. tostring(path)
              .. "): file not found", 2)
    end
    self._fontPath, self._fontSize, self._fontFlags = path, size, flags
end
function ScrollingMessageFrameMeta:GetFont()
    return self._fontPath, self._fontSize, self._fontFlags
end
function ScrollingMessageFrameMeta:SetFontObject(obj) self._fontObject = obj end
function ScrollingMessageFrameMeta:GetFontObject()    return self._fontObject end

--- Whether this log could draw a line at all: false until a font or font object is set. Not a
--- client API -- see H.getChatLines.
function ScrollingMessageFrameMeta:_hasFont()
    return self._fontPath ~= nil or self._fontObject ~= nil
end

M.metaFor = {
    Frame       = FrameMeta,
    EditBox     = EditBoxMeta,
    ScrollFrame = ScrollFrameMeta,
    Button      = ButtonMeta,
    CheckButton = ButtonMeta,
    -- ItemButton is a real frame TYPE on this client, and the two bag-cell templates
    -- (ContainerFrameItemButtonTemplate, BankItemButtonGenericTemplate) are declared as it -- which
    -- is why ElvUI creates its cells with CreateFrame('ItemButton', ...). Modelled as a Button
    -- because everything a consumer can observe about it here is Button behaviour: it takes the
    -- mouse by default, it has click phases, and it carries the template's scripts. Without the
    -- type, a consumer that asks for it correctly gets "does not simulate type ItemButton" and its
    -- feature-detect falls back to Button -- so the harness would silently test the fallback path.
    ItemButton  = ButtonMeta,
    StatusBar   = StatusBarMeta,
    Slider      = FrameMeta,
    Cooldown    = CooldownMeta,
    GameTooltip = GameTooltipMeta,
    ScrollingMessageFrame = ScrollingMessageFrameMeta,
}

return M
