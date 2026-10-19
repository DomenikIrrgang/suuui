-- UI/MapPin.lua
-- One mark on the world map (design component MapPin): a disc on surface
-- with an edge, so it reads on any terrain, and a glyph or a character in
-- it. Quests, places, rares and treasures are 26 px with a 17 px glyph;
-- services are small, 21 px with a 14 px glyph. A disc, not the diamond it
-- was: a diamond only holds a glyph half its width, too small to tell
-- apart on the map (found in game). A merged pin carries a count in micro
-- on a surface-raised tab at its lower right; a rare elite a second ring.
--
--   local pin = UI.MapPin(parent)
--   pin:SetData({
--       glyph = "anvil",          -- a glyph's name, or
--       char = "!",               -- a character ("!", "?", "3")
--       color = "ink",            -- the glyph's (or character's) token
--       edge = "gilt-line",       -- the edge's token
--       edgeWidth = 1,            -- px (a mark's is 2)
--       small = false,            -- the service size
--       ring = nil,               -- a token: a second ring outside the edge
--       count = nil,              -- a merged pin's count (2 and up)
--       spin = nil,               -- true: the glyph turns, once in 6 s (a
--                                 -- dungeon's portal); the disc stays still
--       outline = false,          -- 0.17: a 1 px surface line outside the edge,
--                                 -- so a coloured edge holds on light art
--       arcs = nil,               -- 0.17: { token, … } a split edge, one arc per
--                                 -- item (2-4), clockwise from the top
--       bar = nil,                -- 0.17: a token: a 16 x 4 bar under the pin
--       glow = nil,               -- 0.17: a token: a soft glow around the pin
--                                 -- (a convergence while you lack its blessing)
--   })
-- The quest pins' difficulty (design "Map quest difficulty", direction D):
-- the edge a 2 px ring in the quest's colour (split per quest for a giver
-- with several), outlined; the bar under a group quest.
--   pin:PinSize() -> its size in px
--   pin:SetHighlight(state)  -- true: an ink ring around it (one of the
--                            -- hovered quest's pins), fully opaque; "dim":
--                            -- faded back; nil: as it was
--   pin:SetBaseAlpha(a)      -- its usual opacity (0.15; the map's setting)
-- The pin is a Button; its owner sets its clicks and hover.

local _, ns = ...

local UI = ns.UI

local GLYPHS = "Interface\\AddOns\\SuuUI\\Media\\Textures\\Glyphs\\"
local DISC = "Interface\\AddOns\\SuuUI\\Media\\Textures\\CircleFill.tga"
local SOFT = "Interface\\AddOns\\SuuUI\\Media\\Textures\\CircleSoft.tga"
local ARC = "Interface\\AddOns\\SuuUI\\Media\\Textures\\RingArc"
local SIZE, SMALL = 26, 21

-- A disc, centred; its size set with fit.
local function disc(parent, layer, sub)
    local t = parent:CreateTexture(nil, layer, nil, sub)
    t:SetTexture(DISC)
    t:SetPoint("CENTER")
    return t
end
local function fit(t, box) t:SetSize(box, box) end

-- "!" and "?" at 16 px, with the glyphs, in label's face (again when a
-- theme changes it)
local function charFont()
    local font = _G.SuuUIMapPinChar
    if not font then
        font = CreateFont("SuuUIMapPinChar")
        local function face()
            local file, _, flags = ns.Fonts.Get("label"):GetFont()
            font:SetFont(file, 16, flags or "")
        end
        face()
        ns.Events.On("SUUUI_THEME_CHANGED", face, "MapPin")
    end
    return font
end

local Pin = {}

function Pin:PinSize() return self.size end

function Pin:SetHighlight(state)
    self.hl:SetShown(state == true)
    if state == true then fit(self.hl, self.size + 6) end
    -- (a ringed pin full, a dimmed one fainter than its usual opacity)
    local base = self.baseAlpha or 1
    self:SetAlpha(state == true and 1 or state == "dim" and 0.3 * base or base)
end

function Pin:SetBaseAlpha(a)
    self.baseAlpha = a
    self:SetAlpha(a)
end

function Pin:SetData(d)
    local size = d.small and SMALL or SIZE
    self.size = size
    self:SetSize(size, size)
    -- the second ring: the ring's colour, a gap of surface, then the pin
    self.ringOuter:SetShown(d.ring ~= nil)
    self.ringGap:SetShown(d.ring ~= nil)
    if d.ring then
        fit(self.ringOuter, size + 6)
        UI.Paint(self.ringOuter, d.ring)
        fit(self.ringGap, size + 3)
        UI.Paint(self.ringGap, "surface")
    end
    self.glow:SetShown(d.glow ~= nil)
    if d.glow then
        fit(self.glow, size + 16)
        UI.Paint(self.glow, d.glow)
    end
    self.outline:SetShown(d.outline and true or false)
    if d.outline then
        fit(self.outline, size + 2)
        UI.Paint(self.outline, "surface")
    end
    -- a split edge: the edge itself in surface (the gaps), an arc per item
    local arcs = d.arcs and #d.arcs > 1 and d.arcs or nil
    local n = arcs and math.min(#arcs, 4) or 0
    fit(self.edge, size)
    UI.Paint(self.edge, arcs and "surface" or (d.edge or "gilt-line"))
    fit(self.fill, size - 2 * (d.edgeWidth or 1))
    UI.Paint(self.fill, "surface")
    for k = 1, 4 do
        local t = self.arcs[k]
        if k <= n then
            t:SetTexture(ARC .. n .. ".tga")
            fit(t, size)
            UI.Paint(t, arcs[k])
            -- clockwise from the top: each arc turned by its share
            t:SetRotation(-(k - 1) * 2 * math.pi / n)
            t:Show()
        else
            t:Hide()
        end
    end
    -- the bar under the pin (a group quest), 4 px below, outlined
    self.barEdge:SetShown(d.bar ~= nil)
    self.bar:SetShown(d.bar ~= nil)
    if d.bar then
        UI.PaintFill(self.bar, d.bar)
        UI.PaintFill(self.barEdge, "surface")
    end
    local inner = d.small and 14 or 17
    if d.glyph then
        self.glyph:SetTexture(GLYPHS .. d.glyph .. ".tga")
        self.glyph:SetSize(inner, inner)
        UI.Paint(self.glyph, d.color or "ink")
        self.glyph:Show()
        self.char:Hide()
        if d.spin then
            if not self.spin:IsPlaying() then self.spin:Play() end
        else
            self.spin:Stop()
        end
    else
        self.spin:Stop()
        self.glyph:Hide()
        self.char:SetValue(d.char or "")
        self.char:SetColor(d.color or "ink")
        self.char:Show()
    end
    local n = d.count
    if n and n > 1 then
        self.countText:SetValue(n > 99 and "99+" or tostring(n))
        self.countTab:SetSize(math.ceil(self.countText:GetUnboundedStringWidth()) + 4, 11)
        -- on the disc's edge at its lower right
        local off = math.floor(size * 0.36 + 0.5)
        self.countTab:ClearAllPoints()
        self.countTab:SetPoint("CENTER", self, "CENTER", off, -off)
        self.countTab:Show()
    else
        self.countTab:Hide()
    end
end

function UI.MapPin(parent)
    local b = CreateFrame("Button", nil, parent)
    Mixin(b, Pin)
    b.glow = disc(b, "BACKGROUND", -1)
    b.glow:SetTexture(SOFT)
    b.hl = disc(b, "BACKGROUND", 0)
    UI.Paint(b.hl, "ink")
    b.hl:Hide()
    b.ringOuter = disc(b, "BACKGROUND", 1)
    b.ringGap = disc(b, "BACKGROUND", 2)
    b.outline = disc(b, "BACKGROUND", 3)
    b.edge = disc(b, "BORDER", 1)
    b.fill = disc(b, "BORDER", 2)
    b.arcs = {}
    for k = 1, 4 do
        local t = b:CreateTexture(nil, "BORDER", nil, 3)
        t:SetPoint("CENTER")
        t:Hide()
        b.arcs[k] = t
    end
    b.barEdge = b:CreateTexture(nil, "BACKGROUND", nil, 4)
    b.barEdge:SetSize(18, 6)
    b.barEdge:SetPoint("TOP", b, "BOTTOM", 0, -3)
    b.bar = b:CreateTexture(nil, "BORDER", nil, 4)
    b.bar:SetSize(16, 4)
    b.bar:SetPoint("TOP", b, "BOTTOM", 0, -4)
    b.glyph = b:CreateTexture(nil, "ARTWORK")
    b.glyph:SetPoint("CENTER")
    -- the turn: clockwise, as the game's instance portals turn (seen in
    -- game; a positive angle turns counter-clockwise)
    b.spin = b.glyph:CreateAnimationGroup()
    b.spin:SetLooping("REPEAT")
    local turn = b.spin:CreateAnimation("Rotation")
    turn:SetDegrees(-360)
    turn:SetDuration(6)
    turn:SetOrigin("CENTER", 0, 0)
    b.char = UI.Text(b, "label", "ink")
    b.char:SetPoint("CENTER", 0, 0)
    b.char:SetFontObject(charFont())
    b.countTab = CreateFrame("Frame", nil, b)
    b.countTab:SetFrameLevel(b:GetFrameLevel() + 2)
    UI.Fill(b.countTab, "surface-raised"):SetAllPoints()
    UI.Border(b.countTab, "gilt-line")
    b.countText = UI.Text(b.countTab, "micro", "ink")
    b.countText:SetPoint("CENTER", 0, 0)
    b:SetData({})
    return b
end
