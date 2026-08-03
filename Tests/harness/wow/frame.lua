-- Frame and its subtypes: EditBox, ScrollFrame, Button.
local state   = require("harness.wow.state")
local widget  = require("harness.wow.widget")
local regions = require("harness.wow.regions")
local font    = require("harness.wow.font")

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

function FrameMeta:SetBackdrop(backdrop)
    self._backdrop = backdrop
end

function FrameMeta:GetBackdrop() return self._backdrop end

function FrameMeta:SetBackdropColor(r, g, b, a)
    self._backdropColor = { r, g, b, a == nil and 1 or a }
end

function FrameMeta:GetBackdropColor()
    local c = self._backdropColor
    if not c then return nil end
    return c[1], c[2], c[3], c[4]
end

function FrameMeta:SetBackdropBorderColor(r, g, b, a)
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

function FrameMeta:SetFrameStrata(s)
    assert(STRATA_ORDER[s], "harness: unknown frame strata " .. tostring(s))
    self._strata = s
end

function FrameMeta:GetFrameStrata()
    if self._strata then return self._strata end
    return self._parent and self._parent:GetFrameStrata() or "MEDIUM"
end

function FrameMeta:SetFrameLevel(n) self._level = n end

function FrameMeta:GetFrameLevel()
    if self._level then return self._level end
    return (self._parent and self._parent.GetFrameLevel and self._parent:GetFrameLevel() or 0) + 1
end

function FrameMeta:SetToplevel(v) self._toplevel = v end
function FrameMeta:Raise()  self._level = self:GetFrameLevel() + 1 end
function FrameMeta:Lower()  self._level = math.max(0, self:GetFrameLevel() - 1) end
function FrameMeta:SetClipsChildren(v) self._clipsChildren = v end
function FrameMeta:SetIgnoreParentScale(v) self._ignoreParentScale = v end

----------------------------------------------------------------------------------
-- Input
----------------------------------------------------------------------------------

function FrameMeta:EnableMouse(on)  self._mouseEnabled = on and true or false end

function FrameMeta:IsMouseEnabled()
    if self._mouseEnabled ~= nil then return self._mouseEnabled end
    -- EditBox accepts mouse input without EnableMouse; a plain Frame does not
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

M.metaFor = {
    Frame       = FrameMeta,
    EditBox     = EditBoxMeta,
    ScrollFrame = ScrollFrameMeta,
    Button      = ButtonMeta,
    CheckButton = ButtonMeta,
    StatusBar   = FrameMeta,
    Slider      = FrameMeta,
}

return M
