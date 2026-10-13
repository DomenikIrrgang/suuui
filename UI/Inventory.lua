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
-- With opts.characters (design board "Bags window"): a character picker in
-- the header (inv.who, a bare Select, in place of the title), a row with
-- Bags/Bank (inv.view, a Segmented) and "All characters" (inv.all, a
-- Toggle), a line over the grid (inv:SetBanner(text): an eye and "… read
-- only"), and a list of found items in place of the grid
-- (inv:SetResults(list): { icon, quality, label, count, places }).
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
local ROW = 30 -- the tool rows: search and sort; Bags/Bank and All characters
local MAX_RESULTS = 10

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
    if copper then self.money:SetCopper(copper) end
    self.money:SetShown(copper ~= nil)
end

function Inv:SetNote(text)
    self.note:SetValue(text or "")
end

-- The line over the grid ("Thessaly's bags as of 2 days ago · read only").
function Inv:SetBanner(text)
    if not self.banner then return end
    self.banner.text:SetValue(text or "")
    self.banner:SetShown(text ~= nil and text ~= "")
    self:FitBody()
end

-- Found items in place of the grid (nil: the grid again). At most
-- MAX_RESULTS rows; returns how many were left out.
function Inv:SetResults(list)
    if not self.results then return 0 end
    local rows = self.resultRows
    local n = list and math.min(#list, MAX_RESULTS) or 0
    for i = 1, n do
        local r = rows[i]
        if not r then
            r = CreateFrame("Frame", nil, self.results)
            r:SetHeight(SLOT)
            r.slot = UI.ItemSlot(r)
            r.slot:SetPoint("LEFT")
            r.slot:EnableMouse(false)
            r.total = UI.Text(r, "numeric", "ink")
            r.total:SetPoint("RIGHT")
            r.total:SetJustifyH("RIGHT")
            r.label = UI.Text(r, "label", "ink")
            r.label:SetPoint("TOPLEFT", r.slot, "TOPRIGHT", S["space-4"], -1)
            r.label:SetPoint("RIGHT", r.total, "LEFT", -S["space-4"], 0)
            r.label:SetJustifyH("LEFT")
            r.label:SetWordWrap(false)
            r.places = UI.Text(r, "caption", "ink-muted")
            r.places:SetPoint("BOTTOMLEFT", r.slot, "BOTTOMRIGHT", S["space-4"], 1)
            r.places:SetPoint("RIGHT", r.total, "LEFT", -S["space-4"], 0)
            r.places:SetJustifyH("LEFT")
            r.places:SetWordWrap(false)
            r:SetScript("OnEnter", function(self) if self.onEnter then self.onEnter(self) end end)
            r:SetScript("OnLeave", function(self) if self.onLeave then self.onLeave(self) end end)
            rows[i] = r
        end
        local item = list[i]
        r.item = item
        r.slot.skin:SetItem({ icon = item.icon, quality = item.quality })
        r.label:SetValue(item.label or "")
        r.label:SetColor((item.quality and item.quality ~= "common") and ("quality-" .. item.quality) or "ink")
        r.places:SetValue(item.places or "")
        r.total:SetValue(item.count and ("×" .. item.count) or "")
        r:ClearAllPoints()
        r:SetPoint("TOPLEFT", 0, -(i - 1) * (SLOT + GAP))
        r:SetWidth(self:GridWidth())
        r:Show()
    end
    for i = n + 1, #rows do rows[i]:Hide() end
    -- never shorter than the grid it stands in for: the window keeps its size
    if not self.showResults or not self.resultsMin then self.resultsMin = self.grid:GetHeight() end
    self.results:SetHeight(math.max(SLOT, self.resultsMin or 0, n * SLOT + math.max(0, n - 1) * GAP))
    self.showResults = list ~= nil
    self:FitBody()
    return list and (#list - n) or 0
end

-- Rows from the top: tools, the picker row, the banner, then the grid (or
-- the found items), a rule and the foot. The panel follows the body.
function Inv:FitBody()
    local y = ROW + S["space-4"]
    if self.view then
        self.pickRow:SetPoint("TOPLEFT", 0, -y)
        y = y + ROW + S["space-4"]
    end
    if self.banner and self.banner:IsShown() then
        self.banner:SetPoint("TOPLEFT", 0, -y)
        y = y + T.type.caption.lineHeight + S["space-4"]
    end
    local content = self.grid
    if self.results then
        self.results:SetShown(self.showResults)
        self.grid:SetShown(not self.showResults)
        if self.showResults then content = self.results end
    end
    content:ClearAllPoints()
    content:SetPoint("TOPLEFT", 0, -y)
    content:SetWidth(self:GridWidth())
    self.rule:ClearAllPoints()
    self.rule:SetPoint("TOPLEFT", content, "BOTTOMLEFT", 0, -S["space-4"])
    self.rule:SetPoint("TOPRIGHT", content, "BOTTOMRIGHT", 0, -S["space-4"])
    local h = y + content:GetHeight() + S["space-4"] + 1 + S["space-4"] + T.type.numeric.lineHeight
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
        if self:IsEnabled() then self.edge:SetColor("gilt") end
        if tip then UI.ShowTooltip(self, tip) end
    end)
    b:SetScript("OnLeave", function(self) self.edge:SetColor("gilt-line"); UI.HideTooltip() end)
    hooksecurefunc(b, "SetEnabled", function(self, on) self:SetAlpha(on and 1 or T.opacity["opacity-disabled"]) end)
    return b
end

-- The header's character picker, the Bags/Bank and All characters row, the
-- banner and the found items.
local function buildCharacters(inv, body)
    inv.title:Hide()
    inv.who = UI.Select(inv, { bare = true, width = 220, textStyle = "header", textColor = "gilt-text", options = {} })
    inv.who:SetPoint("LEFT", inv, "TOPLEFT", S["space-5"] - S["space-2"], -(S["space-5"] + T.type.header.lineHeight / 2))
    inv.pickRow = CreateFrame("Frame", nil, body)
    inv.pickRow:SetSize(1, ROW)
    inv.view = UI.Segmented(inv.pickRow, { value = "bags", options = { { value = "bags", label = "Bags" }, { value = "bank", label = "Bank" } } })
    inv.view:SetPoint("LEFT")
    inv.allLabel = UI.Text(body, "label", "ink-muted")
    inv.allLabel:SetValue("All characters")
    inv.all = UI.Toggle(body, { value = false })
    inv.all:SetPoint("RIGHT", inv.pickRow, "LEFT", inv:GridWidth(), 0)
    inv.allLabel:SetPoint("RIGHT", inv.all, "LEFT", -S["space-4"], 0)
    inv.banner = CreateFrame("Frame", nil, body)
    inv.banner:SetSize(inv:GridWidth(), T.type.caption.lineHeight)
    inv.banner.eye = inv.banner:CreateTexture(nil, "ARTWORK")
    inv.banner.eye:SetTexture(GLYPHS .. "eye.tga")
    inv.banner.eye:SetSize(12, 12)
    inv.banner.eye:SetPoint("LEFT")
    inv.banner.eye:SetVertexColor(UI.RGBA("ink-muted"))
    inv.banner.text = UI.Text(inv.banner, "caption", "ink-muted")
    inv.banner.text:SetPoint("LEFT", inv.banner.eye, "RIGHT", S["space-3"], 0)
    inv.banner:Hide()
    inv.results = CreateFrame("Frame", nil, body)
    inv.results:SetSize(inv:GridWidth(), SLOT)
    inv.results:Hide()
    inv.resultRows = {}
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
    inv.grid:SetWidth(inv:GridWidth())
    inv.grid:SetHeight(SLOT)
    if opts.characters then buildCharacters(inv, body) end
    -- the foot: a note and the money, over a gilt-faint rule
    inv.rule = body:CreateTexture(nil, "ARTWORK")
    inv.rule:SetColorTexture(UI.RGBA("gilt-faint"))
    inv.rule:SetHeight(1)
    inv.note = UI.Text(body, "caption", "ink-muted")
    inv.note:SetPoint("TOPLEFT", inv.rule, "BOTTOMLEFT", 0, -S["space-4"])
    inv.money = UI.Money(body)
    inv.money:SetPoint("TOPRIGHT", inv.rule, "BOTTOMRIGHT", 0, -S["space-4"])
    inv.money:Hide() -- until SetMoney: a bank holds no money
    inv:FitBody()
    return inv
end

-- After `columns` changed: the widths that follow it.
function Inv:SetColumns(columns)
    self.columns = columns
    local w = self:GridWidth()
    self.search:SetWidth(w - 30 - S["space-3"])
    self.grid:SetWidth(w)
    if self.all then
        self.all:SetPoint("RIGHT", self.pickRow, "LEFT", w, 0)
        self.banner:SetWidth(w)
    end
    self:FitBody()
end
