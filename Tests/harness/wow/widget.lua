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

-- The client's widget inheritance, which IsObjectType answers against: a Button IS a Frame and
-- says so, a CheckButton is both a Button and a Frame, and every widget is a Region.
--
-- Modelled rather than exact-matched because the exact-match version made an entire class of
-- caller untestable: anything filtering foreign frames with IsObjectType("Frame") -- which is
-- how you tell a widget from a plain table when scanning somebody else's children -- saw every
-- Button answer false here and true in game. A spec written against it would have proved the
-- opposite of what the client does.
local INHERITS = {
    Region      = {},
    Frame       = { Region = true },
    Button      = { Frame = true, Region = true },
    CheckButton = { Button = true, Frame = true, Region = true },
    -- ItemButton is a real type on this client and the bag-cell templates are declared as it, so it
    -- inherits Button exactly as CheckButton does -- which is what makes it mouse-enabled by default
    -- and what makes IsObjectType('Button') answer true for a bag cell.
    ItemButton  = { Button = true, Frame = true, Region = true },
    EditBox     = { Frame = true, Region = true },
    ScrollFrame = { Frame = true, Region = true },
    StatusBar   = { Frame = true, Region = true },
    Slider      = { Frame = true, Region = true },
    Cooldown    = { Frame = true, Region = true },
    GameTooltip = { Frame = true, Region = true },
    -- A scrolling text log. In the hierarchy for the same reason every other subtype is: code
    -- that filters foreign children with IsObjectType("Frame") must see one, or it tests the
    -- fallback path here and the real path in game.
    ScrollingMessageFrame = { Frame = true, Region = true },
    Texture     = { Region = true },
    FontString  = { Region = true },
}

function Base:IsObjectType(t)
    if self._kind == t then return true end
    local chain = INHERITS[self._kind]
    return (chain ~= nil and chain[t] == true)
end

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
-- Protection and combat lockdown
--
-- A frame built from a secure template is PROTECTED, and protection propagates DOWN: every
-- descendant of a protected frame is protected too, implicitly.
--
-- The geometry refusal propagates the other way — UP. The client refuses an addon-driven
-- geometry change on a protected frame, and also on any frame whose SUBTREE contains one,
-- because moving the parent would move the protected child. So a plain frame with a single
-- secure grandchild cannot be resized in combat, which is the whole shape of the bug this
-- models: the unit frame wanted height 227, stayed at 188, and every spec passed.
--
-- The client does not raise on a refusal. The call returns having changed nothing and the
-- player gets "Interface action failed because of an AddOn" in chat, so the harness records
-- the refusal instead of erroring — see state.blockedActions.
----------------------------------------------------------------------------------

--- Whether this widget is protected, and whether that protection is its own.
--
-- Two return values, as the client's method has: `isProtected, isProtectedExplicitly`.
-- Explicit means built from a secure template; a widget is implicitly protected when any
-- ANCESTOR is explicitly protected. Regions answer too, because the client's do.
-- @return bool isProtected
-- @return bool isProtectedExplicitly
function Base:IsProtected()
    if self._secure then return true, true end
    local p = self._parent
    while p do
        if p._secure then return true, false end
        p = p._parent
    end
    return false, false
end

--- Whether any frame in this widget's subtree is explicitly protected.
--
-- Only explicit protection is searched for, and that is complete rather than a shortcut: an
-- implicitly protected descendant is only protected because some ancestor between it and the
-- root is explicit, and that ancestor is inside this subtree too unless it is the root — in
-- which case IsProtected() already answers.
-- @param w table
-- @return bool
local function hasProtectedDescendant(w)
    local stack, top = { w }, 1
    while top > 0 do
        local f = stack[top]
        top = top - 1
        for _, child in ipairs(f._childFrames) do
            if child._secure then return true end
            top = top + 1
            stack[top] = child
        end
    end
    return false
end
M.hasProtectedDescendant = hasProtectedDescendant

--- Whether the client would refuse this geometry call, recording it when it does.
--
-- Cheap out of combat: the flag is tested before anything walks a tree, so the guard costs
-- one comparison for the whole suite while lockdown is off.
-- @param w table
-- @param action string  The method name, e.g. "SetSize"
-- @return bool
local function refused(w, action)
    if not state.inCombat then return false end
    -- REGIONS ARE NOT PROTECTED OBJECTS. Protection is a property of FRAMES: a texture or a
    -- font string inside a protected button carries none of its own, and the client lets an
    -- addon retint, retext, show and hide one during a fight. Blizzard's own action buttons
    -- depend on that -- a potion's stack count changes as it is used, which is a font string
    -- being shown and hidden inside a protected button mid-combat.
    --
    -- Without this clause the ancestor walk in IsProtected() reports every region of a secure
    -- button as protected, which pushes a component into deferring readout updates the client
    -- would have accepted -- a setting that visibly does nothing until the fight ends.
    --
    -- NOTE: this makes the harness MORE PERMISSIVE, which is the direction that has burned
    -- this project four times, so it is deliberately narrow. `_canScript` is false for exactly
    -- Texture, MaskTexture and FontString, so nothing about FRAMES changes -- and hiding a
    -- frame inside a protected button stays refused, which is what caught ActionButton hiding
    -- its icon frame on every action pickup.
    if not w._canScript then return false end
    local isProtected = w:IsProtected()
    if not (isProtected or hasProtectedDescendant(w)) then return false end
    local log = state.blockedActions
    log[#log + 1] = {
        action    = action,
        frame     = w,
        name      = w._name,
        protected = isProtected,
    }
    return true
end

----------------------------------------------------------------------------------
-- Size
----------------------------------------------------------------------------------

function Base:SetWidth(w)
    if refused(self, "SetWidth") then return end
    self._w = w
    state.invalidate(self)
end

function Base:SetHeight(h)
    if refused(self, "SetHeight") then return end
    self._h = h
    state.invalidate(self)
end

function Base:SetSize(w, h)
    if refused(self, "SetSize") then return end
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
    return geometry.center(self)
end

function Base:GetRect()
    return geometry.ownRect(self)
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
    if refused(self, "SetPoint") then return end
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
    -- Guarded in its own right rather than left to the SetPoint calls below: it clears the
    -- existing anchors first, so a refusal that only stopped the SetPoint half would leave
    -- the widget with NO anchors at all — a state change on a call that is supposed to have
    -- changed nothing.
    if refused(self, "SetAllPoints") then return end
    relativeTo = relativeTo or self._parent
    self._points = {}
    self:SetPoint("TOPLEFT", relativeTo, "TOPLEFT", 0, 0)
    self:SetPoint("BOTTOMRIGHT", relativeTo, "BOTTOMRIGHT", 0, 0)
end

function Base:ClearAllPoints()
    if refused(self, "ClearAllPoints") then return end
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
    -- Protection is tested BEFORE the already-shown short circuit, the way the client tests
    -- it: the refusal is a property of the frame and the lockdown, not of what it currently
    -- looks like. A spec asserting "Show was refused" therefore does not have to know whether
    -- the frame happened to be hidden first.
    if refused(self, "Show") then return end
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
    if refused(self, "Hide") then return end
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
-- Defaults to 1 like the client's own widgets: a frame nobody has faded is fully opaque,
-- so a disabled-state assertion can compare against 1 without the widget having been
-- explicitly painted first.
function Base:GetAlpha()  return self._alpha or 1 end

function Base:SetScale(s)
    self._scale = s
    -- A scale change moves this widget's whole subtree in screen space, and the solver
    -- caches by generation, so the invalidation has to be global rather than local.
    geometry.invalidate()
    state.invalidate(self)
end
function Base:GetScale() return self._scale end

-- Detaches a region from the parent scale chain, so its effective scale is its own
-- scale alone. Pixel-grid code uses this to hold a known scale regardless of what the
-- player's UI Scale slider is set to.
function Base:SetIgnoreParentScale(ignore)
    self._ignoreParentScale = ignore and true or false
    geometry.invalidate()
    state.invalidate(self)
end
function Base:IsIgnoringParentScale() return self._ignoreParentScale == true end

-- One implementation, shared with the geometry solver, which needs it to convert between
-- screen space and a widget's own region units.
function Base:GetEffectiveScale()
    return geometry.effScale(self)
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
    -- A message log's link HOVER, which is how a tooltip gets shown for an item in chat.
    -- OnHyperlinkClick was already here; these two were the missing half.
    OnHyperlinkEnter=true, OnHyperlinkLeave=true,
    OnSpacePressed=true, OnLoad=true, OnVerticalScroll=true, OnScrollRangeChanged=true,
    -- The two hooks a secure action template offers around its own OnClick. They exist so
    -- code can observe a click without replacing the handler that performs the action —
    -- which is the only reason a secure button is observable at all.
    PreClick=true, PostClick=true,
    -- The tooltip content scripts. On THIS client these are the only route to tooltip
    -- content: TooltipDataProcessor.AddTooltipPostCall exists but does not work here, so a
    -- reskin hangs everything off these four and nothing else.
    OnTooltipSetItem=true, OnTooltipSetSpell=true, OnTooltipSetUnit=true,
    OnTooltipCleared=true,
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
