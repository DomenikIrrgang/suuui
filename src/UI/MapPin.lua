-- UI/MapPin.lua
-- One mark on the world map (design component MapPin): a diamond on surface
-- with an edge, so it reads on any terrain, and a glyph or a character in
-- it. Quests, places, rares and treasures are 26 px with a 13 px glyph;
-- services are small, 21 px with an 11 px glyph (the design's 22 and 17 px
-- read too small on the map; found in game). A merged pin carries a
-- count in micro on a surface-raised tab at its lower right; a rare elite a
-- second ring.
--
--   local pin = UI.MapPin(parent)
--   pin:SetData({
--       glyph = "anvil",          -- a glyph's name, or
--       char = "!",               -- a character ("!", "?", "3")
--       color = "ink",            -- the glyph's (or character's) token
--       edge = "gilt-line",       -- the edge's token
--       small = false,            -- the service size
--       ring = nil,               -- a token: a second ring outside the edge
--       count = nil,              -- a merged pin's count (2 and up)
--   })
--   pin:PinSize() -> its size in px
--   pin:SetHighlight(state)  -- true: an ink ring around it (one of the
--                            -- hovered quest's pins); "dim": faded back;
--                            -- nil: as it was
-- The pin is a Button; its owner sets its clicks and hover.

local _, ns = ...

local UI = ns.UI

local GLYPHS = "Interface\\AddOns\\SuuUI\\Media\\Textures\\Glyphs\\"
local WHITE = "Interface\\Buttons\\WHITE8X8"
local SIZE, SMALL = 26, 21
local ROOT2 = math.sqrt(2)

-- A square turned 45° whose corners touch a box `box` px wide.
local function diamond(parent, layer, sub)
    local t = parent:CreateTexture(nil, layer, nil, sub)
    t:SetTexture(WHITE)
    t:SetRotation(math.rad(45))
    t:SetPoint("CENTER")
    return t
end
local function fit(t, box) local side = box / ROOT2; t:SetSize(side, side) end

local Pin = {}

function Pin:PinSize() return self.size end

function Pin:SetHighlight(state)
    self.hl:SetShown(state == true)
    if state == true then fit(self.hl, self.size + 8) end
    self:SetAlpha(state == "dim" and 0.3 or 1)
end

function Pin:SetData(d)
    local size = d.small and SMALL or SIZE
    self.size = size
    self:SetSize(size, size)
    -- the second ring: the ring's colour, a gap of surface, then the pin
    self.ringOuter:SetShown(d.ring ~= nil)
    self.ringGap:SetShown(d.ring ~= nil)
    if d.ring then
        fit(self.ringOuter, size + 8)
        self.ringOuter:SetVertexColor(UI.RGBA(d.ring))
        fit(self.ringGap, size + 5)
        self.ringGap:SetVertexColor(UI.RGBA("surface"))
    end
    fit(self.edge, size)
    self.edge:SetVertexColor(UI.RGBA(d.edge or "gilt-line"))
    fit(self.fill, size - 3)
    self.fill:SetVertexColor(UI.RGBA("surface"))
    local inner = d.small and 11 or 13
    if d.glyph then
        self.glyph:SetTexture(GLYPHS .. d.glyph .. ".tga")
        self.glyph:SetSize(inner, inner)
        self.glyph:SetVertexColor(UI.RGBA(d.color or "ink"))
        self.glyph:Show()
        self.char:Hide()
    else
        self.glyph:Hide()
        self.char:SetValue(d.char or "")
        self.char:SetColor(d.color or "ink")
        self.char:Show()
    end
    local n = d.count
    if n and n > 1 then
        self.countText:SetValue(n > 99 and "99+" or tostring(n))
        self.countTab:SetSize(math.ceil(self.countText:GetUnboundedStringWidth()) + 4, 11)
        self.countTab:Show()
    else
        self.countTab:Hide()
    end
end

function UI.MapPin(parent)
    local b = CreateFrame("Button", nil, parent)
    Mixin(b, Pin)
    b.hl = diamond(b, "BACKGROUND", 0)
    b.hl:SetVertexColor(UI.RGBA("ink"))
    b.hl:Hide()
    b.ringOuter = diamond(b, "BACKGROUND", 1)
    b.ringGap = diamond(b, "BACKGROUND", 2)
    b.edge = diamond(b, "BORDER", 1)
    b.fill = diamond(b, "BORDER", 2)
    b.glyph = b:CreateTexture(nil, "ARTWORK")
    b.glyph:SetPoint("CENTER")
    b.char = UI.Text(b, "label", "ink")
    b.char:SetPoint("CENTER", 0, 0)
    -- "!" and "?" at 14 px, with the larger pins
    local charFont = _G.SuuUIMapPinChar
    if not charFont then
        charFont = CreateFont("SuuUIMapPinChar")
        local file, _, flags = ns.Fonts.Get("label"):GetFont()
        charFont:SetFont(file, 14, flags or "")
    end
    b.char:SetFontObject(charFont)
    b.countTab = CreateFrame("Frame", nil, b)
    b.countTab:SetPoint("CENTER", b, "BOTTOMRIGHT", -1, 2)
    b.countTab:SetFrameLevel(b:GetFrameLevel() + 2)
    UI.Fill(b.countTab, "surface-raised"):SetAllPoints()
    UI.Border(b.countTab, "gilt-line")
    b.countText = UI.Text(b.countTab, "micro", "ink")
    b.countText:SetPoint("CENTER", 0, 0)
    b:SetData({})
    return b
end
