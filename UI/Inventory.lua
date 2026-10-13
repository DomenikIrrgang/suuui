-- UI/Inventory.lua
-- Bags (design boards "Bags", "Item slot", "Money"): the item slot, money,
-- and the inventory panel (title, "18 free of 80", search and sort, a grid
-- of slots `slot` (36px) square, space-2 apart, money in the foot).
--
--   local skin = UI.SkinItemSlot(button)   -- SuuUI's look on any button
--   skin:SetItem({ icon, count, quality, dim, locked }) or skin:SetItem(nil) (empty)
--   UI.ItemSlot(parent)                     -- a plain slot (previews, saved bags)
--   local m = UI.Money(parent); m:SetCopper(n)
--   local inv = UI.Inventory(parent, { title = "Bags", columns = 10 })
--   inv:LayoutSlots(buttons)                -- in order, row by row
--   inv:SetMeta(text), inv:SetMoney(copper) (none shown until then), inv:SetNote(text)
--   inv.search (a TextField), inv.sort (a button), inv.onClose
--
-- The live slots are Blizzard's own bag slot buttons (their clicks, drags
-- and tooltips are Blizzard's: using an item stays allowed in combat); the
-- skin hides their art and draws SuuUI's, keeping its own state in a table
-- of its own (nothing written on the button).

local _, ns = ...

local UI, T = ns.UI, ns.Tokens
local S = T.space

local GLYPHS = "Interface\\AddOns\\SuuUI\\Media\\Textures\\Glyphs\\"
local SLOT = T.size["slot"]
local GAP = S["space-2"]
local PAD = S["space-5"]
local CROP = 0.08

--------------------------------------------------------------------------------
-- The item slot
--------------------------------------------------------------------------------

local Skin = {}
Skin.__index = Skin

-- The template's own art, out of sight (alpha, so its code showing a part
-- again shows nothing).
local TEMPLATE_PARTS = { "IconBorder", "IconOverlay", "IconOverlay2", "NewItemTexture", "BattlepayItemTexture",
                         "flash", "searchOverlay", "ItemContextOverlay", "Count", "Stock", "JunkIcon",
                         "UpgradeIcon", "ExtendedSlot", "ExtendedOverlay", "ExtendedOverlay2", "IconQuestTexture",
                         "ProfessionQualityOverlay", "LevelLinkLockTexture", "BagIndicator" }

local function hideTemplateArt(b)
    for _, key in ipairs(TEMPLATE_PARTS) do
        local r = b[key]
        if type(r) == "table" and r.SetAlpha then r:SetAlpha(0) end
    end
    local name = b:GetName()
    if name then
        for _, suffix in ipairs({ "Count", "Stock", "IconQuestTexture", "NormalTexture" }) do
            local r = _G[name .. suffix]
            if r and r.SetAlpha then r:SetAlpha(0) end
        end
    end
    for _, get in ipairs({ "GetNormalTexture", "GetPushedTexture", "GetHighlightTexture" }) do
        local t = b[get] and b[get](b)
        if t then t:SetAlpha(0) end
    end
end

function UI.SkinItemSlot(b)
    local s = setmetatable({ button = b }, Skin)
    hideTemplateArt(b)
    s.well = b:CreateTexture(nil, "BACKGROUND", nil, -7)
    s.well:SetAllPoints()
    s.icon = b.icon or b.Icon
    if not s.icon then
        s.icon = b:CreateTexture(nil, "ARTWORK")
    end
    s.icon:ClearAllPoints()
    s.icon:SetPoint("TOPLEFT", 1, -1)
    s.icon:SetPoint("BOTTOMRIGHT", -1, 1)
    s.icon:SetTexCoord(CROP, 1 - CROP, CROP, 1 - CROP)
    s.border = UI.Border(b, "gilt-hairline", { layer = "OVERLAY" })
    s.count = b:CreateFontString(nil, "OVERLAY")
    ns.Fonts.Apply(s.count, "micro")
    s.count:SetShadowColor(0, 0, 0, 1)
    s.count:SetShadowOffset(0, -1)
    s.count:SetPoint("BOTTOMRIGHT", -2, 1)
    s.count:SetJustifyH("RIGHT")
    b:HookScript("OnEnter", function() s.hover = true; s:Draw() end)
    b:HookScript("OnLeave", function() s.hover = false; s:Draw() end)
    s:SetItem(nil)
    return s
end

-- item: { icon, count, quality ("poor" … "legendary"), dim, locked } or nil.
function Skin:SetItem(item)
    self.item = item
    local b = self.button
    if item then
        self.icon:SetTexture(item.icon)
        self.icon:Show()
        self.count:SetText((item.count and item.count > 1) and item.count or "")
    else
        self.icon:SetTexture(nil)
        self.count:SetText("")
    end
    self:Draw()
    return b
end

function Skin:Draw()
    local item = self.item
    if not item then
        self.well:SetColorTexture(UI.RGBA("surface-sunk"))
        self.border:SetColor(self.hover and "gilt" or "gilt-faint")
        self.button:SetAlpha(1)
        return
    end
    self.well:SetColorTexture(UI.RGBA("surface-raised"))
    local q = item.quality
    local edge = (q and q ~= "common" and ("quality-" .. q)) or "gilt-hairline"
    self.border:SetColor(self.hover and "gilt" or edge)
    local grey = item.dim or item.locked
    self.icon:SetDesaturated(grey and true or false)
    self.icon:SetVertexColor(grey and 0.55 or 1, grey and 0.55 or 1, grey and 0.55 or 1)
    self.button:SetAlpha(item.dim and T.opacity["opacity-disabled"] or 1)
end

-- A plain slot: for previews and for bags SuuUI only remembers.
function UI.ItemSlot(parent, size)
    local b = CreateFrame("Button", nil, parent)
    b:SetSize(size or SLOT, size or SLOT)
    b.skin = UI.SkinItemSlot(b)
    return b
end

--------------------------------------------------------------------------------
-- Money: 1,204g 37s 9c (tabular figures, the units in coin colours)
--------------------------------------------------------------------------------

local Money = {}

local function thousands(n)
    local s = tostring(n)
    while true do
        local k
        s, k = s:gsub("^(%d+)(%d%d%d)", "%1,%2")
        if k == 0 then break end
    end
    return s
end

function Money:SetCopper(total)
    total = math.max(0, math.floor(tonumber(total) or 0))
    local g, s, c = math.floor(total / 10000), math.floor(total / 100) % 100, total % 100
    local parts = {}
    local function part(v, unit, token)
        parts[#parts + 1] = v .. "|cff" .. T.color[token].hex .. unit .. "|r"
    end
    if g > 0 then part(thousands(g), "g", "coin-gold") end
    if g > 0 or s > 0 then part(s, "s", "coin-silver") end
    part(c, "c", "coin-copper")
    self.text:SetText(table.concat(parts, "  "))
    self:SetSize(math.max(1, self.text:GetUnboundedStringWidth()), T.type.numeric.lineHeight)
end

function UI.Money(parent)
    local m = CreateFrame("Frame", nil, parent)
    Mixin(m, Money)
    m.text = UI.Text(m, "numeric", "ink")
    m.text:SetPoint("RIGHT")
    m:SetCopper(0)
    return m
end

--------------------------------------------------------------------------------
-- The inventory panel
--------------------------------------------------------------------------------

local Inv = {}

function Inv:GridWidth()
    return self.columns * SLOT + (self.columns - 1) * GAP
end

function Inv:LayoutSlots(buttons)
    local cols = self.columns
    for i, b in ipairs(buttons) do
        local r, c = math.floor((i - 1) / cols), (i - 1) % cols
        b:ClearAllPoints()
        b:SetPoint("TOPLEFT", self.grid, "TOPLEFT", c * (SLOT + GAP), -r * (SLOT + GAP))
        b:SetSize(SLOT, SLOT)
        b:Show()
    end
    local rows = math.max(1, math.ceil(#buttons / cols))
    self.grid:SetHeight(rows * SLOT + (rows - 1) * GAP)
    self:FitBody()
end

function Inv:SetMeta(text)
    if self.meta then self.meta:SetValue(text or "") end
end

function Inv:SetMoney(copper)
    self.money:SetCopper(copper)
    self.money:SetShown(copper ~= nil)
end

function Inv:SetNote(text)
    self.note:SetValue(text or "")
end

-- The body's size (the panel follows it).
function Inv:FitBody()
    local h = 30 + S["space-4"] + self.grid:GetHeight() + S["space-4"] + 1 + S["space-4"] + T.type.numeric.lineHeight
    self.body:SetSize(self:GridWidth(), h)
end

-- A small square button with a glyph (sort).
local function glyphButton(parent, glyph, tip)
    local b = CreateFrame("Button", nil, parent)
    b:SetSize(30, 30)
    UI.Fill(b, "surface-raised", "BACKGROUND"):SetAllPoints()
    b.edge = UI.Border(b, "gilt-line")
    b.glyph = b:CreateTexture(nil, "ARTWORK")
    b.glyph:SetTexture(GLYPHS .. glyph .. ".tga")
    b.glyph:SetSize(16, 16)
    b.glyph:SetPoint("CENTER")
    b.glyph:SetVertexColor(UI.RGBA("ink"))
    b:SetScript("OnEnter", function(self)
        self.edge:SetColor("gilt")
        if tip then UI.ShowTooltip(self, tip) end
    end)
    b:SetScript("OnLeave", function(self) self.edge:SetColor("gilt-line"); UI.HideTooltip() end)
    return b
end

function UI.Inventory(parent, opts)
    opts = opts or {}
    local columns = opts.columns or 10
    local inv = UI.Panel(parent, { name = opts.name, title = opts.title or "Bags", meta = "", closable = true,
        onClose = function(p) if p.onClose then p.onClose() else p:Hide() end end })
    Mixin(inv, Inv)
    inv.columns = columns
    local body = inv.body
    -- search and sort
    inv.sort = glyphButton(body, "sort", { title = "Sort", description = opts.sortTip or "Blizzard's own sort: stacks and orders your items." })
    inv.sort:SetPoint("TOPRIGHT")
    inv.search = UI.TextField(body, { width = inv:GridWidth() - 30 - S["space-3"], placeholder = "Search" })
    inv.search:SetPoint("TOPLEFT")
    -- the grid
    inv.grid = CreateFrame("Frame", nil, body)
    inv.grid:SetPoint("TOPLEFT", 0, -(30 + S["space-4"]))
    inv.grid:SetWidth(inv:GridWidth())
    inv.grid:SetHeight(SLOT)
    -- the foot: a note and the money, over a gilt-faint rule
    inv.rule = body:CreateTexture(nil, "ARTWORK")
    inv.rule:SetColorTexture(UI.RGBA("gilt-faint"))
    inv.rule:SetHeight(1)
    inv.rule:SetPoint("TOPLEFT", inv.grid, "BOTTOMLEFT", 0, -S["space-4"])
    inv.rule:SetPoint("TOPRIGHT", inv.grid, "BOTTOMRIGHT", 0, -S["space-4"])
    inv.note = UI.Text(body, "caption", "ink-muted")
    inv.note:SetPoint("TOPLEFT", inv.rule, "BOTTOMLEFT", 0, -S["space-4"])
    inv.money = UI.Money(body)
    inv.money:SetPoint("TOPRIGHT", inv.rule, "BOTTOMRIGHT", 0, -S["space-4"])
    inv.money:Hide() -- until SetMoney: a bank holds no money
    inv:FitBody()
    return inv
end
