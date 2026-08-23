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

function FrameMeta:EnableKeyboard(on)  self._keyboardEnabled = on and true or false end
function FrameMeta:IsKeyboardEnabled() return self._keyboardEnabled == true end
function FrameMeta:SetPropagateKeyboardInput(on) self._propagateKeyboard = on end

function FrameMeta:SetHitRectInsets(l, r, t, b)
    self._hitInsets = { left = l, right = r, top = t, bottom = b }
end

function FrameMeta:RegisterForDrag(...)   self._dragButtons = { ... } end
function FrameMeta:RegisterForClicks(...) self._clickButtons = { ... } end

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
-- @param f table       The secure button
-- @param button string Which mouse button was clicked
function M.secureAction(f, button)
    local kind = modifiedAttribute(f, "type", button)
    local unit = modifiedAttribute(f, "unit", button)
    -- The template's own hooks, fired around the action exactly as the client fires them:
    -- they are the only way to observe a click on a secure button without replacing the
    -- handler that performs it.
    f:_fire("PreClick", button, false)
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
    end
    f:_fire("PostClick", button, false)
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
function EditBoxMeta:HighlightText()      end
function EditBoxMeta:SetTextInsets(...)   self._textInsets = { ... } end

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
function ButtonMeta:SetNormalTexture(t) self._normalTexture = t end
function ButtonMeta:GetNormalTexture()  return self._normalTexture end

-- The rest of a Button's texture slots, plus the highlight lock. Stored rather than drawn:
-- the harness models geometry and state, and none of these change a rect. A drag
-- implementation locks the highlight for the duration of the gesture, so the lock is
-- readable -- a write-only flag could not be asserted.
function ButtonMeta:SetPushedTexture(t)    self._pushedTexture = t end
function ButtonMeta:GetPushedTexture()     return self._pushedTexture end
function ButtonMeta:SetDisabledTexture(t)  self._disabledTexture = t end
function ButtonMeta:GetDisabledTexture()   return self._disabledTexture end
function ButtonMeta:SetHighlightTexture(t, blend)
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

function GameTooltipMeta:ClearLines()
    self._lines = {}
    state.tooltip = state.tooltip or {}
    state.tooltip.aura = nil
end

function GameTooltipMeta:AddLine(text, r, g, b, wrap)
    self._lines = self._lines or {}
    self._lines[#self._lines + 1] = { text = text, r = r, g = g, b = b, wrap = wrap }
end

function GameTooltipMeta:AddDoubleLine(left, right, lr, lg, lb, rr, rg, rb)
    self._lines = self._lines or {}
    self._lines[#self._lines + 1] = { text = left, right = right, r = lr, g = lg, b = lb }
end

function GameTooltipMeta:SetText(text, r, g, b)
    self._lines = { { text = text, r = r, g = g, b = b } }
end

function GameTooltipMeta:NumLines() return #(self._lines or {}) end

--- The text of one line, 1-based, as the client's GameTooltipTextLeft<i> would carry it.
-- Harness-only convenience: reading a global font string per line models nothing useful.
function GameTooltipMeta:GetLine(i)
    local line = (self._lines or {})[i]
    return line and line.text, line and line.right
end

function GameTooltipMeta:Show()
    self._tooltipShown = true
    self._shown = true
end

function GameTooltipMeta:Hide()
    self._tooltipShown = false
    self._shown = false
end

function GameTooltipMeta:IsShown() return self._tooltipShown == true end

M.metaFor = {
    Frame       = FrameMeta,
    EditBox     = EditBoxMeta,
    ScrollFrame = ScrollFrameMeta,
    Button      = ButtonMeta,
    CheckButton = ButtonMeta,
    StatusBar   = FrameMeta,
    Slider      = FrameMeta,
    Cooldown    = CooldownMeta,
    GameTooltip = GameTooltipMeta,
}

return M
