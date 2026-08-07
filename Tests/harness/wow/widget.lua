-- Base widget: everything a Frame, Texture, FontString, EditBox or ScrollFrame has
-- in common. Geometry, visibility, anchors, scripts.
local geometry = require("harness.wow.geometry")
local state    = require("harness.wow.state")

local M = {}

local Base = {}
Base.__index = Base
M.Base = Base

local nextSerial = 1

--- Creates a raw widget table. Callers layer type-specific methods on the metatable.
-- @param kind string     "Frame" | "Texture" | "FontString" | ...
-- @param name string|nil
-- @param parent table|nil
-- @param meta table      Metatable to attach
-- @return table
function M.new(kind, name, parent, meta)
    local w = setmetatable({
        _kind        = kind,
        _name        = name,
        _parent      = parent,
        _serial      = nextSerial,
        _points      = {},
        _shown       = true,
        _alpha       = 1,
        _scale       = 1,
        _childFrames = {},
        _regions     = {},
    }, meta or Base)
    nextSerial = nextSerial + 1

    if parent then
        if w._canScript then
            parent._childFrames[#parent._childFrames + 1] = w
        else
            parent._regions[#parent._regions + 1] = w
        end
    end

    state.track(w)
    geometry.invalidate()
    return w
end

--- Resets the serial counter. Keeps frame identity strings stable across reloads.
function M.resetSerial() nextSerial = 1 end

----------------------------------------------------------------------------------
-- Identity
----------------------------------------------------------------------------------

function Base:GetName()       return self._name end
function Base:GetObjectType()  return self._kind end
function Base:IsObjectType(t)  return self._kind == t end
function Base:GetParent()      return self._parent end

function Base:SetParent(parent)
    local old = self._parent
    if old then
        local list = self._canScript and old._childFrames or old._regions
        for i = #list, 1, -1 do
            if list[i] == self then table.remove(list, i) break end
        end
    end
    self._parent = parent
    if parent then
        local list = self._canScript and parent._childFrames or parent._regions
        list[#list + 1] = self
    end
    state.invalidate(self)
end

----------------------------------------------------------------------------------
-- Size
----------------------------------------------------------------------------------

function Base:SetWidth(w)
    self._w = w
    state.invalidate(self)
end

function Base:SetHeight(h)
    self._h = h
    state.invalidate(self)
end

function Base:SetSize(w, h)
    self._w, self._h = w, h
    state.invalidate(self)
end

function Base:GetSize()
    return self:GetWidth(), self:GetHeight()
end

function Base:GetWidth()  return geometry.width(self) end
function Base:GetHeight() return geometry.height(self) end

function Base:GetLeft()   return geometry.left(self) end
function Base:GetRight()  return geometry.right(self) end
function Base:GetTop()    return geometry.top(self) end
function Base:GetBottom() return geometry.bottom(self) end

function Base:GetCenter()
    local r = geometry.resolve(self)
    if not r then return nil end
    return r.left + r.width / 2, r.bottom + r.height / 2
end

function Base:GetRect()
    local r = geometry.resolve(self)
    if not r then return nil end
    return r.left, r.bottom, r.width, r.height
end

----------------------------------------------------------------------------------
-- Anchors
----------------------------------------------------------------------------------

local VALID_POINT = {}
for k in pairs(geometry.POINTS) do VALID_POINT[k] = true end

-- SetPoint is overloaded in WoW. Supported call shapes:
--   (point)
--   (point, x, y)
--   (point, relativeTo)
--   (point, relativeTo, relativePoint)
--   (point, relativeTo, x, y)
--   (point, relativeTo, relativePoint, x, y)
local function parsePoint(self, a, b, c, d, e)
    local point = a
    local relativeTo, relativePoint, x, y

    if type(b) == "number" or b == nil then
        relativeTo, relativePoint, x, y = self._parent, point, b or 0, c or 0
    else
        relativeTo = b
        if type(c) == "number" or c == nil then
            relativePoint, x, y = point, c or 0, d or 0
        else
            relativePoint, x, y = c, d or 0, e or 0
        end
    end

    return point, relativeTo, relativePoint, x, y
end

function Base:SetPoint(a, b, c, d, e)
    local point, relativeTo, relativePoint, x, y = parsePoint(self, a, b, c, d, e)

    point = tostring(point):upper()
    relativePoint = tostring(relativePoint or point):upper()
    assert(VALID_POINT[point], "harness: invalid anchor point " .. tostring(point))
    assert(VALID_POINT[relativePoint], "harness: invalid relative point " .. tostring(relativePoint))
    assert(relativeTo ~= self, "harness: frame cannot be anchored to itself")

    -- WoW replaces an existing anchor that uses the same point name
    for i, p in ipairs(self._points) do
        if p.point == point then table.remove(self._points, i) break end
    end

    self._points[#self._points + 1] = {
        point = point, relativeTo = relativeTo,
        relativePoint = relativePoint, x = x, y = y,
    }
    -- A widget anchored to something that is not its parent still has to re-resolve
    -- when that target moves, so record the reverse edge for the settle pass.
    state.addDependent(relativeTo, self)
    state.invalidate(self)
end

function Base:SetAllPoints(relativeTo)
    relativeTo = relativeTo or self._parent
    self._points = {}
    self:SetPoint("TOPLEFT", relativeTo, "TOPLEFT", 0, 0)
    self:SetPoint("BOTTOMRIGHT", relativeTo, "BOTTOMRIGHT", 0, 0)
end

function Base:ClearAllPoints()
    self._points = {}
    state.invalidate(self)
end

function Base:GetNumPoints() return #self._points end

--- Returns one anchor as point, relativeTo, relativePoint, x, y.
-- @param i number  1-based index
function Base:GetPoint(i)
    local p = self._points[i or 1]
    if not p then return nil end
    return p.point, p.relativeTo, p.relativePoint, p.x, p.y
end

----------------------------------------------------------------------------------
-- Visibility
----------------------------------------------------------------------------------

--- True when this widget's own shown flag is set, regardless of ancestors.
function Base:IsShown() return self._shown == true end

--- True when this widget and every ancestor are shown.
function Base:IsVisible()
    if not self._shown then return false end
    local p = self._parent
    while p do
        if not p._shown then return false end
        p = p._parent
    end
    return true
end

local function fireVisibility(w, visible)
    local script = w._scripts and (visible and w._scripts.OnShow or w._scripts.OnHide)
    if script then script(w) end
    for _, child in ipairs(w._childFrames) do
        if child._shown then fireVisibility(child, visible) end
    end
    for _, region in ipairs(w._regions) do
        if region._shown and region._scripts then fireVisibility(region, visible) end
    end
end

function Base:Show()
    if self._shown then return end
    self._shown = true
    local parentVisible = true
    local p = self._parent
    while p do
        if not p._shown then parentVisible = false break end
        p = p._parent
    end
    state.invalidate(self)
    if parentVisible then fireVisibility(self, true) end
end

function Base:Hide()
    if not self._shown then return end
    local wasVisible = self:IsVisible()
    self._shown = false
    state.invalidate(self)
    if wasVisible then fireVisibility(self, false) end
end

function Base:SetShown(shown)
    if shown then self:Show() else self:Hide() end
end

----------------------------------------------------------------------------------
-- Alpha and scale
----------------------------------------------------------------------------------

function Base:SetAlpha(a) self._alpha = a end
function Base:GetAlpha()  return self._alpha end

function Base:SetScale(s)
    self._scale = s
    state.invalidate(self)
end
function Base:GetScale() return self._scale end

-- Detaches a region from the parent scale chain, so its effective scale is its own
-- scale alone. Pixel-grid code uses this to hold a known scale regardless of what the
-- player's UI Scale slider is set to.
function Base:SetIgnoreParentScale(ignore)
    self._ignoreParentScale = ignore and true or false
    state.invalidate(self)
end
function Base:IsIgnoringParentScale() return self._ignoreParentScale == true end

function Base:GetEffectiveScale()
    local s = self._scale or 1
    if self._ignoreParentScale then return s end
    local p = self._parent
    while p do
        s = s * (p._scale or 1)
        if p._ignoreParentScale then return s end
        p = p._parent
    end
    return s * state.uiScale
end

----------------------------------------------------------------------------------
-- Scripts
----------------------------------------------------------------------------------

local SCRIPTABLE = {
    OnShow=true, OnHide=true, OnSizeChanged=true, OnUpdate=true, OnEvent=true,
    OnEnter=true, OnLeave=true, OnMouseDown=true, OnMouseUp=true, OnClick=true,
    OnMouseWheel=true, OnKeyDown=true, OnKeyUp=true, OnDragStart=true, OnDragStop=true,
    OnTextChanged=true, OnEnterPressed=true, OnEscapePressed=true, OnTabPressed=true,
    OnEditFocusGained=true, OnEditFocusLost=true, OnValueChanged=true, OnCursorChanged=true,
    OnAttributeChanged=true, OnReceiveDrag=true, OnHyperlinkClick=true, OnChar=true,
    OnSpacePressed=true, OnLoad=true, OnVerticalScroll=true, OnScrollRangeChanged=true,
}

function Base:SetScript(name, fn)
    assert(self._canScript, "harness: " .. tostring(self._kind) .. " cannot have scripts")
    assert(SCRIPTABLE[name], "harness: unknown script handler " .. tostring(name))
    self._scripts = self._scripts or {}
    self._scripts[name] = fn
end

function Base:GetScript(name)
    return self._scripts and self._scripts[name]
end

function Base:HasScript(name) return SCRIPTABLE[name] == true end

function Base:HookScript(name, fn)
    local prev = self:GetScript(name)
    self:SetScript(name, function(...)
        if prev then prev(...) end
        fn(...)
    end)
end

--- Invokes a script handler if present. Harness convenience, not a WoW method.
-- @param name string
function Base:_fire(name, ...)
    local fn = self._scripts and self._scripts[name]
    if fn then return fn(self, ...) end
end

return M
