-- Texture, MaskTexture and FontString. Regions carry no scripts and no children.
local geometry = require("harness.wow.geometry")
local state    = require("harness.wow.state")
local widget   = require("harness.wow.widget")
local font     = require("harness.wow.font")

local Base = widget.Base
local M = {}

local function derive(parentMeta)
    local meta = setmetatable({}, { __index = parentMeta })
    meta.__index = meta
    return meta
end

----------------------------------------------------------------------------------
-- Texture
----------------------------------------------------------------------------------

local TextureMeta = derive(Base)
TextureMeta._canScript = false
M.TextureMeta = TextureMeta

function TextureMeta:SetTexture(path, wrapH, wrapV)
    self._texture = path
    self._wrapH, self._wrapV = wrapH, wrapV
    self._colorTexture = nil
end

function TextureMeta:GetTexture() return self._texture end

function TextureMeta:SetColorTexture(r, g, b, a)
    self._colorTexture = { r, g, b, a == nil and 1 or a }
    self._texture = "Interface\\Buttons\\WHITE8x8"
end

--- Harness accessor: the colour set by SetColorTexture, as {r,g,b,a}.
function TextureMeta:GetColorTexture()
    local c = self._colorTexture
    if not c then return nil end
    return c[1], c[2], c[3], c[4]
end

function TextureMeta:SetVertexColor(r, g, b, a)
    self._vertexColor = { r, g, b, a == nil and 1 or a }
end

function TextureMeta:GetVertexColor()
    local c = self._vertexColor or { 1, 1, 1, 1 }
    return c[1], c[2], c[3], c[4]
end

function TextureMeta:SetGradient(orientation, from, to)
    self._gradient = { orientation = orientation, from = from, to = to }
end

function TextureMeta:GetGradient() return self._gradient end

function TextureMeta:SetDesaturated(on)
    self._desaturated = on and true or false
    return true
end

function TextureMeta:IsDesaturated() return self._desaturated == true end

function TextureMeta:SetDrawLayer(layer, sub)
    self._drawLayer, self._subLayer = layer, sub
end

function TextureMeta:GetDrawLayer() return self._drawLayer, self._subLayer end

function TextureMeta:SetTexCoord() end
function TextureMeta:SetBlendMode(mode) self._blendMode = mode end
function TextureMeta:SetRotation(r) self._rotation = r end

function TextureMeta:AddMaskTexture(mask)
    self._masks = self._masks or {}
    self._masks[#self._masks + 1] = mask
end

function TextureMeta:RemoveMaskTexture(mask)
    if not self._masks then return end
    for i = #self._masks, 1, -1 do
        if self._masks[i] == mask then table.remove(self._masks, i) end
    end
end

--- Harness accessor: masks applied to this texture.
function TextureMeta:GetMaskTextures() return self._masks or {} end

local MaskMeta = derive(TextureMeta)
MaskMeta._canScript = false
M.MaskMeta = MaskMeta

----------------------------------------------------------------------------------
-- FontString
----------------------------------------------------------------------------------

local FontStringMeta = derive(Base)
FontStringMeta._canScript = false
M.FontStringMeta = FontStringMeta

function FontStringMeta:SetText(text)
    self._text = text == nil and "" or tostring(text)
    state.invalidate(self)
end

function FontStringMeta:GetText() return self._text or "" end

function FontStringMeta:SetFormattedText(fmt, ...)
    self:SetText(string.format(fmt, ...))
end

function FontStringMeta:SetFont(path, size, flags)
    self._font, self._fontSize, self._fontFlags = path, size, flags
    state.invalidate(self)
    return true
end

function FontStringMeta:GetFont()
    return self._font, self._fontSize or font.defaultSize, self._fontFlags or ""
end

function FontStringMeta:SetFontObject(obj) self._fontObject = obj end
function FontStringMeta:GetFontObject()    return self._fontObject end

function FontStringMeta:SetTextColor(r, g, b, a)
    self._textColor = { r, g, b, a == nil and 1 or a }
end

function FontStringMeta:GetTextColor()
    local c = self._textColor or { 1, 1, 1, 1 }
    return c[1], c[2], c[3], c[4]
end

function FontStringMeta:SetJustifyH(j) self._justifyH = j end
function FontStringMeta:GetJustifyH()  return self._justifyH or "CENTER" end
function FontStringMeta:SetJustifyV(j) self._justifyV = j end
function FontStringMeta:GetJustifyV()  return self._justifyV or "MIDDLE" end

-- WoW defaults word wrap on for font strings.
function FontStringMeta:SetWordWrap(on)
    self._wordWrap = on and true or false
    state.invalidate(self)
end

function FontStringMeta:CanWordWrap()
    return self._wordWrap ~= false
end

-- WoW defaults non-space wrap off: a word wider than the box is clipped, not broken.
function FontStringMeta:SetNonSpaceWrap(on)
    self._nonSpaceWrap = on and true or false
    state.invalidate(self)
end

function FontStringMeta:CanNonSpaceWrap()
    return self._nonSpaceWrap == true
end

function FontStringMeta:SetMaxLines(n)      self._maxLines = n end
function FontStringMeta:SetDrawLayer(layer, sub)
    self._drawLayer, self._subLayer = layer, sub
end

-- The width a layout has assigned, if any. Text metrics are clamped to it, which is
-- the behaviour TextMetrics.lua exists to work around.
local function boundWidth(self)
    if geometry.hasDerivedWidth(self) then return geometry.width(self) end
    return self._w
end

--- Rendered text width, clamped to the assigned width like the real client.
function FontStringMeta:GetStringWidth()
    local size = self._fontSize or font.defaultSize
    local w = font.measure(self._text, size, self:CanWordWrap(), boundWidth(self),
                           self:CanNonSpaceWrap())
    return w
end

--- Text width free of any layout-assigned bound.
function FontStringMeta:GetUnboundedStringWidth()
    return font.unbounded(self._text, self._fontSize or font.defaultSize)
end

--- Rendered text height, accounting for wrapping at the assigned width.
function FontStringMeta:GetStringHeight()
    local size = self._fontSize or font.defaultSize
    local _, h = font.measure(self._text, size, self:CanWordWrap(), boundWidth(self),
                              self:CanNonSpaceWrap())
    return h
end

function FontStringMeta:GetNumLines()
    local size = self._fontSize or font.defaultSize
    local _, _, n = font.measure(self._text, size, self:CanWordWrap(), boundWidth(self),
                                 self:CanNonSpaceWrap())
    return n
end

--- Harness accessor: whether the assigned box is too small for the rendered text, so
--- the client would draw a clipped glyph. No real API reports this, but it is exactly
--- what a user sees when a layout pins a font string to a stale or unmeasured size,
--- so specs need to be able to assert against it.
-- @return bool, number, number, number, number  clipped, boxW, boxH, needW, needH
function FontStringMeta:IsTextClipped()
    if (self._text or "") == "" then return false, 0, 0, 0, 0 end
    local size = self._fontSize or font.defaultSize
    local boxW = boundWidth(self)
    local boxH = geometry.hasDerivedHeight(self) and geometry.height(self) or self._h

    -- With word wrap on, a narrow box re-flows between words rather than cutting glyphs,
    -- so the height usually reveals the clip. It cannot re-flow inside a word unless
    -- non-space wrap is on, so a box narrower than its widest word still clips — that
    -- is the single-glyph label pinned to a too-small column.
    local needW = font.minWidth(self._text, size, self:CanWordWrap(), self:CanNonSpaceWrap())
    local needH = select(2, font.measure(self._text, size, self:CanWordWrap(), boxW,
                                         self:CanNonSpaceWrap()))

    local clipped = false
    if boxH and boxH + 0.5 < needH then clipped = true end
    if boxW and needW > 0 and boxW + 0.5 < needW then clipped = true end
    return clipped, boxW, boxH, needW, needH
end

-- A font string with neither an explicit size nor opposing anchors reports its text
-- extent, which is what flow layout measures when height is omitted.
function FontStringMeta:GetWidth()
    if geometry.hasDerivedWidth(self) then return geometry.width(self) end
    if self._w then return self._w end
    return self:GetUnboundedStringWidth()
end

function FontStringMeta:GetHeight()
    if geometry.hasDerivedHeight(self) then return geometry.height(self) end
    if self._h then return self._h end
    return self:GetStringHeight()
end

return M
