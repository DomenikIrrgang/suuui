-- UI/Crest.lua
-- The rare and elite crest (design "Rare and elite units", option B "Crest",
-- chosen 2026-10-18): the dragon flattened into a diamond with 1 px wings
-- that run out and fade. Gilt for elite, silver (an ink outline on
-- surface-sunk) for rare, silver wings with a gilt jewel ringed in silver for
-- a rare elite; a world boss gets longer wings and three jewels.
--   frame: on a unit frame's top edge over its right end, wings both ways
--   plate: just outside a nameplate bar's right end, one wing outward
--
--   local crest = UI.Crest(parent, "frame")   -- or "plate"
--   crest:SetPoint("CENTER", frame, "TOPRIGHT", -64, 0)
--   crest:SetClassification(UnitClassification(unit))   -- nil/"normal"/…: hidden

local _, ns = ...

local UI = ns.UI

local WHITE = "Interface\\Buttons\\WHITE8X8"
local KINDS = { elite = true, rare = true, rareelite = true, worldboss = true }

local Crest = {}

-- A diamond jewel: gilt, silver or both, `size` px a side, centred at x, y.
local function jewel(c, kind, size, x, y)
    local parts = {}
    local function d(px, color, sub, alpha)
        local t = UI.Diamond(c, px, color, "OVERLAY", sub)
        if alpha then t:SetVertexColor(0, 0, 0, alpha) end
        t:SetPoint("CENTER", c, "CENTER", x, y)
        parts[#parts + 1] = t
    end
    if kind == "gilt" then
        d(size + 2, "ink", 1, 0.65)
        d(size, "gilt", 3)
    elseif kind == "silver" then
        d(size + 5, "ink", 1, 0.65)
        d(size + 3, "ink", 2)
        d(size, "surface-sunk", 3)
    else -- both: a gilt jewel ringed in silver
        d(size + 4, "ink", 1)
        d(size + 2, "surface-sunk", 2)
        d(size, "gilt", 3)
    end
    return parts
end

-- A 1 px wing from x outward by `length`, fading toward its tip.
local function wing(c, color, x, y, length, toLeft)
    local t = c:CreateTexture(nil, "OVERLAY", nil, 0)
    t:SetTexture(WHITE)
    t:SetSize(length, 1)
    t:SetPoint(toLeft and "RIGHT" or "LEFT", c, "CENTER", x, y)
    local r, g, b, a = UI.RGBA(color)
    local solid, clear = CreateColor(r, g, b, a), CreateColor(r, g, b, 0)
    if not pcall(t.SetGradient, t, "HORIZONTAL", toLeft and clear or solid, toLeft and solid or clear) then
        t:SetVertexColor(r, g, b, a)
    end
    return { t }
end

-- The pieces of one look, made once.
function Crest:Look(kind)
    self.looks = self.looks or {}
    if self.looks[kind] then return self.looks[kind] end
    local parts, plate = {}, self.variant == "plate"
    local function add(list) for _, t in ipairs(list) do parts[#parts + 1] = t end end
    local metal = (kind == "elite" or kind == "worldboss") and "gilt" or "ink"
    local stone = kind == "rare" and "silver" or kind == "rareelite" and "both" or "gilt"
    if plate then
        add(jewel(self, stone, 5, 0, 0))
        add(wing(self, metal, 3.5, 0, 10))
        if kind == "worldboss" then add(jewel(self, "gilt", 3, 8, 0)) end
    elseif kind == "worldboss" then
        add(wing(self, "gilt", -6, 0, 44, true))
        add(wing(self, "gilt", 6, 0, 44))
        add(jewel(self, "gilt", 5, -10.5, 0))
        add(jewel(self, "gilt", 5, 10.5, 0))
        add(jewel(self, "gilt", 9, 0, 0))
    else
        add(wing(self, metal, -4, 0, 26, true))
        add(wing(self, metal, 4, 0, 26))
        add(jewel(self, stone, 7, 0, 0))
    end
    for _, t in ipairs(parts) do t:Hide() end
    self.looks[kind] = parts
    return parts
end

-- The unit's classification (a secret one: hidden, like the meta words).
function Crest:SetClassification(c)
    if issecretvalue and issecretvalue(c) then c = nil end
    local kind = KINDS[c] and c or nil
    if kind == self.kind then return end
    if self.kind then for _, t in ipairs(self:Look(self.kind)) do t:Hide() end end
    self.kind = kind
    if kind then for _, t in ipairs(self:Look(kind)) do t:Show() end end
    self:SetShown(kind ~= nil)
end

function UI.Crest(parent, variant)
    local c = CreateFrame("Frame", nil, parent)
    Mixin(c, Crest)
    c.variant = variant or "frame"
    c:SetSize(1, 1)
    c:SetFrameLevel(parent:GetFrameLevel() + 8)
    c:Hide()
    return c
end
