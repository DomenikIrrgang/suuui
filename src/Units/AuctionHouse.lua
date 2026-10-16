-- Units/AuctionHouse.lua
-- SuuUI's own auction house (plan 3.6, design component AuctionHouseWindow;
-- asked 2026-10-16: "ready for new features in the future"). The game's
-- AuctionHouseFrame stays open (it holds the conversation) but out of sight;
-- this window searches, shows and buys through C_AuctionHouse with its own
-- buttons (/suu probe ahpost: the game lets them post and cancel; bidding
-- and buying are restricted the same way). Step 1: Buy (search, the game's
-- categories, results, an item's auctions, a commodity's offers and its
-- purchase). Sell and Auctions follow; until then their tabs open the
-- game's own window.
-- A built-in module written against the public API only.

local UI, T = SuuUI.UI, SuuUI.Tokens
local S = T.space

local M = SuuUI.RegisterModule({
    id = "auctionhouse",
    name = "Auction house",
    description = "SuuUI's auction house window: search, the game's categories, an item's auctions and a commodity's offers, buying.",
    api = "0.16",
    reloadToToggle = true,
    defaults = {},
})

local isSecret = issecretvalue or function() return false end
local function call(fn, ...)
    if type(fn) ~= "function" then return nil end
    local ok, a, b, c, d, e = pcall(fn, ...)
    if ok then return a, b, c, d, e end
end

local AH = C_AuctionHouse
local WIDTH, HEIGHT = 840, 580
local CAT_W = 170
local ROW_H = 32
local QUALITY = { [0] = "poor", "common", "uncommon", "rare", "epic", "legendary", "legendary", "legendary" }
local BAND = { [0] = "Short", "Medium", "Long", "Very long" }

local function coins(copper)
    copper = math.max(0, math.floor(copper or 0))
    local g, s, c = math.floor(copper / 10000), math.floor(copper / 100) % 100, copper % 100
    local parts = {}
    local function part(v, unit, token) parts[#parts + 1] = v .. "|cff" .. T.color[token].hex .. unit .. "|r" end
    if g > 0 then part(g, "g", "coin-gold") end
    if s > 0 or (g > 0 and c > 0) then part(s, "s", "coin-silver") end
    if c > 0 or #parts == 0 then part(c, "c", "coin-copper") end
    return table.concat(parts, " ")
end

local function sorts()
    local O = Enum.AuctionHouseSortOrder or {}
    local list = {}
    if O.Price then list[#list + 1] = { sortOrder = O.Price, reverseSort = false } end
    if O.Name then list[#list + 1] = { sortOrder = O.Name, reverseSort = false } end
    return list
end

-- An item key's name, icon, quality and kind (nil until the game has it:
-- ITEM_KEY_ITEM_INFO_RECEIVED).
local function keyInfo(key)
    return key and call(AH.GetItemKeyInfo, key)
end

--------------------------------------------------------------------------------
-- The foot's note: info (ink-muted), ok (fel), error (ember-text)
--------------------------------------------------------------------------------

local TONE = { info = "ink-muted", ok = "fel", error = "ember-text" }

function M:Note(text, tone)
    if not self.note then return end
    self.note:SetValue(text or "")
    self.note:SetColor(TONE[tone or "info"])
end

--------------------------------------------------------------------------------
-- Tables: a header row of captions, then rows of cells
--------------------------------------------------------------------------------

-- cols: { { label, w (nil: the rest), right } }
local function buildTable(parent, cols)
    local t = CreateFrame("Frame", nil, parent)
    t.cols, t.rows = cols, {}
    t.head = CreateFrame("Frame", nil, t)
    t.head:SetPoint("TOPLEFT")
    t.head:SetPoint("TOPRIGHT")
    t.head:SetHeight(20)
    t.headCells = {}
    t.list = UI.ScrollArea(t, S["space-3"])
    t.list:SetPoint("TOPLEFT", 0, -22)
    t.list:SetPoint("BOTTOMRIGHT", -(S["space-3"] + 3), 0)
    t.list:HookScript("OnSizeChanged", function(sc, w) sc.child:SetWidth(w); t:LayoutCols() end)
    local rule = UI.Fill(t, "gilt-faint", "ARTWORK")
    rule:SetPoint("TOPLEFT", 0, -20)
    rule:SetPoint("TOPRIGHT", 0, -20)
    rule:SetHeight(1)
    function t:SetCols(c)
        self.cols = c
        for i, h in ipairs(self.headCells) do h:SetShown(c[i] ~= nil) end
        for i, col in ipairs(c) do
            local h = self.headCells[i]
            if not h then
                h = UI.Text(self.head, "caption", "ink-muted")
                self.headCells[i] = h
            end
            h:SetValue(col.label or "")
            h:SetJustifyH(col.right and "RIGHT" or "LEFT")
            h:Show()
        end
        self:LayoutCols()
    end
    -- each column's x and width in a row of width w
    function t:Places(w)
        local fixed = 0
        for _, col in ipairs(self.cols) do fixed = fixed + (col.w or 0) + S["space-4"] end
        local x, out = S["space-3"], {}
        for i, col in ipairs(self.cols) do
            local cw = col.w or math.max(40, w - fixed - S["space-3"] * 2)
            out[i] = { x = x, w = cw }
            x = x + cw + S["space-4"]
        end
        return out
    end
    function t:LayoutCols()
        local places = self:Places(self.list:GetWidth())
        for i, h in ipairs(self.headCells) do
            if places[i] then
                h:ClearAllPoints()
                h:SetPoint("LEFT", self.head, "LEFT", places[i].x, 0)
                h:SetWidth(places[i].w)
            end
        end
    end
    t:SetCols(cols)
    return t
end

-- A row: a button with a hover and a chosen fill, a rule under it, and up to
-- six cells (frames, placed by the table's columns).
local function tableRow(t, i)
    local r = t.rows[i]
    if r then return r end
    local c = t.list.child
    r = CreateFrame("Button", nil, c)
    r:SetHeight(ROW_H)
    r.sel = UI.Fill(r, "arcane-soft", "BACKGROUND")
    r.sel:SetAllPoints()
    r.sel:Hide()
    r.hover = UI.Fill(r, "surface-raised", "BACKGROUND", 1)
    r.hover:SetAllPoints()
    r.hover:SetAlpha(0.6)
    r.hover:Hide()
    r.rule = UI.Fill(r, "gilt-faint", "ARTWORK")
    r.rule:SetPoint("BOTTOMLEFT")
    r.rule:SetPoint("BOTTOMRIGHT")
    r.rule:SetHeight(1)
    r:SetScript("OnEnter", function(self) self.hover:Show(); if self.onEnter then self.onEnter(self) end end)
    r:SetScript("OnLeave", function(self) self.hover:Hide(); GameTooltip:Hide() end)
    r.cells = {}
    t.rows[i] = r
    return r
end

-- Places a row's cells (frames or font strings) by the table's columns.
local function placeCells(t, r, cells)
    local places = t:Places(t.list:GetWidth())
    for i, cell in ipairs(cells) do
        local p = places[i]
        if p and cell then
            cell:ClearAllPoints()
            if t.cols[i].right then
                cell:SetPoint("RIGHT", r, "LEFT", p.x + p.w, 0)
            else
                cell:SetPoint("LEFT", r, "LEFT", p.x, 0)
            end
            if cell.SetWidth and cell.GetObjectType and cell:GetObjectType() == "FontString" then cell:SetWidth(p.w) end
        end
    end
end

--------------------------------------------------------------------------------
-- Buy: the search bar, the categories, the results
--------------------------------------------------------------------------------

-- The game's category tree (AuctionCategories, from its auction house UI),
-- WoW Token left out (its auctions are unavailable on Forever).
local function categories()
    local out = {}
    for _, c in ipairs(rawget(_G, "AuctionCategories") or {}) do
        if not (c.flags and c.flags.WOW_TOKEN_FLAG) then out[#out + 1] = c end
    end
    return out
end

function M:Search(text)
    self.view = "browse"
    self.query = { searchString = text or (self.search and self.search.edit:GetText()) or "", sorts = sorts(),
                   filters = self:QueryFilters(), itemClassFilters = self.catFilters or {} }
    self.results = {}
    self.searched = true
    self:Note("Searching…")
    local ok, err = pcall(AH.SendBrowseQuery, self.query)
    if not ok then self:Note("The search didn't go out: " .. tostring(err), "error") end
    self:Refresh()
end

function M:Favorites()
    self.view = "browse"
    self.results = {}
    self.searched = true
    self.query = { searchString = "★" }
    self:Note("Your favourites…")
    call(AH.SearchForFavorites, sorts())
    self:Refresh()
end

-- The filter menu's choices as the game's filters.
function M:QueryFilters()
    local F = Enum.AuctionHouseFilter or {}
    local v = self.filterValue or {}
    local out = {}
    for _, t in ipairs(v.only or {}) do
        if t == "usable" and F.UsableOnly then out[#out + 1] = F.UsableOnly end
    end
    local rarity = { poor = F.PoorQuality, common = F.CommonQuality, uncommon = F.UncommonQuality, rare = F.RareQuality, epic = F.EpicQuality }
    local chosen = v.rarity or {}
    for _, q in ipairs(chosen) do if rarity[q] then out[#out + 1] = rarity[q] end end
    return out
end

function M:BuildBuy(page)
    -- the search bar: favourites, the search, Filter, Search
    local bar = CreateFrame("Frame", nil, page)
    bar:SetPoint("TOPLEFT")
    bar:SetPoint("TOPRIGHT")
    bar:SetHeight(30)
    local fav = CreateFrame("Button", nil, bar)
    fav:SetSize(30, 30)
    fav:SetPoint("LEFT")
    UI.Fill(fav, "surface-sunk"):SetAllPoints()
    fav.edge = UI.Border(fav, "gilt-line")
    fav.glyph = fav:CreateTexture(nil, "ARTWORK")
    fav.glyph:SetTexture("Interface\\AddOns\\SuuUI\\Media\\Textures\\Glyphs\\star.tga")
    fav.glyph:SetSize(14, 14)
    fav.glyph:SetPoint("CENTER")
    fav.glyph:SetVertexColor(UI.RGBA("gilt"))
    fav:SetScript("OnClick", function() self:Favorites() end)
    fav:SetScript("OnEnter", function(b) b.edge:SetColor("gilt"); UI.ShowTooltip(b, { title = "Favourites", description = "The items you marked as favourites." }) end)
    fav:SetScript("OnLeave", function(b) b.edge:SetColor("gilt-line"); UI.HideTooltip() end)
    self.search = UI.TextField(bar, { width = 300, placeholder = "Search" })
    self.search:SetPoint("LEFT", fav, "RIGHT", S["space-2"], 0)
    self.search.edit:HookScript("OnEnterPressed", function() self:Search() end)
    self.filter = UI.FilterMenu(bar, {
        groups = {
            { key = "only", label = "Show", kind = "toggles", options = { { value = "usable", label = "Usable only" } } },
            { key = "rarity", label = "Rarity", kind = "many", options = {
                { value = "poor", label = "Poor", color = "quality-poor" }, { value = "common", label = "Common", color = "quality-common" },
                { value = "uncommon", label = "Uncommon", color = "quality-uncommon" }, { value = "rare", label = "Rare", color = "quality-rare" },
                { value = "epic", label = "Epic", color = "quality-epic" } } },
        },
        defaults = { only = {}, rarity = {} }, placeholder = "Filter", width = 110,
        onChange = function(v) self.filterValue = v end })
    self.filter:SetPoint("LEFT", self.search, "RIGHT", S["space-2"], 0)
    local go = UI.Button(bar, { text = "Search", variant = "primary", icon = "search", onClick = function() self:Search() end })
    go:SetPoint("LEFT", self.filter, "RIGHT", S["space-2"], 0)
    -- Scan all: after a thin divider, the button and when it last ran
    local div = UI.Fill(bar, "gilt-faint", "ARTWORK")
    div:SetSize(1, 22)
    div:SetPoint("LEFT", go, "RIGHT", S["space-4"], 0)
    self.scanButton = UI.Button(bar, { text = "Scan all", icon = "sort", onClick = function() self:Scan() end })
    self.scanButton:SetPoint("LEFT", div, "RIGHT", S["space-4"], 0)
    self.scanWhen = UI.Text(bar, "caption", "ink-muted")
    self.scanWhen:SetPoint("LEFT", self.scanButton, "RIGHT", S["space-3"], 0)
    -- the categories down the left
    local cats = UI.ScrollArea(page, S["space-2"])
    cats:SetPoint("TOPLEFT", 0, -(30 + S["space-4"]))
    cats:SetPoint("BOTTOMLEFT")
    cats:SetWidth(CAT_W)
    cats.child:SetWidth(CAT_W)
    self.catList, self.catButtons = cats, {}
    -- the main column: results, an item's auctions or a commodity's offers
    local main = CreateFrame("Frame", nil, page)
    main:SetPoint("TOPLEFT", CAT_W + S["space-3"] + S["space-5"], -(30 + S["space-4"]))
    main:SetPoint("BOTTOMRIGHT")
    self.main = main
    self.results_t = buildTable(main, { { label = "Name" }, { label = "Item level", w = 70, right = true },
        { label = "Available", w = 70, right = true }, { label = "Lowest price", w = 120, right = true } })
    self.results_t:SetAllPoints()
    self.empty = UI.Text(main, "body", "ink-muted")
    self.empty:SetPoint("TOP", 0, -60)
    self.more = UI.Button(main, { text = "More results", onClick = function() call(AH.RequestMoreBrowseResults) end })
    self.more:SetPoint("BOTTOM", 0, S["space-2"])
    self.more:Hide()
    self:BuildItemView(main)
end

-- The category tree: top categories, the chosen one's subcategories under it.
function M:DrawCategories()
    local c = self.catList.child
    local y, n = 0, 0
    local function button(label, depth, chosen, onClick)
        n = n + 1
        local b = self.catButtons[n]
        if not b then
            b = CreateFrame("Button", nil, c)
            b:SetHeight(24)
            b.sel = UI.Fill(b, "arcane-soft", "BACKGROUND")
            b.sel:SetAllPoints()
            b.text = UI.Text(b, "body", "ink")
            b.text:SetPoint("LEFT", S["space-3"], 0)
            b.text:SetPoint("RIGHT", -S["space-2"], 0)
            b.text:SetWordWrap(false)
            b:SetScript("OnEnter", function(self) if not self.chosen then self.text:SetColor("ink") end end)
            b:SetScript("OnLeave", function(self) if not self.chosen then self.text:SetColor(self.depth > 0 and "ink-muted" or "ink") end end)
            self.catButtons[n] = b
        end
        b.depth, b.chosen = depth, chosen
        b:ClearAllPoints()
        b:SetPoint("TOPLEFT", depth * S["space-4"], -y)
        b:SetPoint("RIGHT", c, "RIGHT")
        b.text:SetStyle(depth > 0 and "caption" or "body")
        b.text:SetValue(label)
        b.text:SetColor(chosen and "arcane" or (depth > 0 and "ink-muted" or "ink"))
        b.sel:SetShown(chosen)
        b:SetScript("OnClick", onClick)
        b:Show()
        y = y + 24
    end
    for _, cat in ipairs(categories()) do
        local open = self.category == cat
        button(cat.name or "?", 0, open and not self.subcategory, function()
            if self.category == cat and not self.subcategory then
                self.category, self.catFilters = nil, nil
            else
                self.category, self.subcategory, self.catFilters = cat, nil, cat.filters
            end
            self:Search()
        end)
        if open then
            for _, sub in ipairs(cat.subCategories or {}) do
                button(sub.name or "?", 1, self.subcategory == sub, function()
                    self.subcategory, self.catFilters = sub, sub.filters
                    self:Search()
                end)
            end
        end
    end
    for i = n + 1, #self.catButtons do self.catButtons[i]:Hide() end
    c:SetHeight(math.max(1, y))
end

function M:DrawResults()
    local t = self.results_t
    local results = call(AH.GetBrowseResults) or {}
    local n = 0
    for i, r in ipairs(results) do
        n = i
        local row = tableRow(t, i)
        local info = keyInfo(r.itemKey) or {}
        if not row.slot then
            row.slot = UI.ItemSlot(row, 24)
            row.slot:EnableMouse(false)
            row.name = UI.Text(row, "label", "ink")
            row.name:SetWordWrap(false)
            row.mine = UI.Text(row, "micro", "arcane")
            row.ilvl = UI.Text(row, "numeric", "ink-muted")
            row.ilvl:SetJustifyH("RIGHT")
            row.qty = UI.Text(row, "numeric", "ink")
            row.qty:SetJustifyH("RIGHT")
            row.price = UI.Money(row)
        end
        row:ClearAllPoints()
        row:SetPoint("TOPLEFT", 0, -(i - 1) * ROW_H)
        row:SetPoint("RIGHT", t.list.child, "RIGHT")
        row.slot.skin:SetItem({ icon = info.iconFileID, quality = QUALITY[info.quality or 1] or "common" })
        row.name:SetValue(info.itemName or "…")
        row.name:SetColor((info.quality and info.quality ~= 1) and ("quality-" .. (QUALITY[info.quality] or "common")) or "ink")
        row.mine:SetValue(r.containsOwnerItem and "Yours" or "")
        row.ilvl:SetValue(info.isEquipment and r.itemKey.itemLevel and tostring(r.itemKey.itemLevel) or "")
        row.qty:SetValue(tostring(r.totalQuantity or ""))
        row.price:SetCopper(r.minPrice or 0)
        self:Seen(r.itemKey.itemID, r.minPrice)
        -- the name cell: the slot, the name, Yours
        local places = t:Places(t.list:GetWidth())
        row.slot:ClearAllPoints()
        row.slot:SetPoint("LEFT", places[1].x, 0)
        row.name:ClearAllPoints()
        row.name:SetPoint("LEFT", row.slot, "RIGHT", S["space-3"], 0)
        row.name:SetWidth(math.max(20, places[1].w - 24 - S["space-3"] - (r.containsOwnerItem and 40 or 0)))
        row.mine:ClearAllPoints()
        row.mine:SetPoint("LEFT", row.name, "RIGHT", S["space-2"], 0)
        placeCells(t, row, { false, row.ilvl, row.qty, row.price })
        row.key = r.itemKey
        row.onEnter = function(btn)
            GameTooltip:SetOwner(btn, "ANCHOR_RIGHT")
            if GameTooltip.SetItemKey then
                pcall(GameTooltip.SetItemKey, GameTooltip, btn.key.itemID, btn.key.itemLevel, btn.key.itemSuffix)
            else
                GameTooltip:SetItemByID(btn.key.itemID)
            end
            GameTooltip:Show()
        end
        row:SetScript("OnClick", function(btn) self:OpenItem(btn.key) end)
        row:Show()
    end
    for i = n + 1, #t.rows do t.rows[i]:Hide() end
    t.list.child:SetHeight(math.max(1, n * ROW_H))
    local full = call(AH.HasFullBrowseResults)
    self.more:SetShown(n > 0 and full == false)
    self.empty:SetShown(n == 0)
    if n == 0 then
        local q = self.query and self.query.searchString or ""
        self.empty:SetValue(self.searched and (q ~= "" and ("Nothing for “" .. q .. "”.") or "Nothing here.") or "Search, or choose a category.")
    end
end

--------------------------------------------------------------------------------
-- An item's auctions, and a commodity's offers
--------------------------------------------------------------------------------

function M:BuildItemView(main)
    local v = CreateFrame("Frame", nil, main)
    v:SetAllPoints()
    v:Hide()
    self.itemView = v
    -- the head: the item, back
    v.slot = UI.ItemSlot(v)
    v.slot:SetPoint("TOPLEFT")
    v.slot:SetScript("OnEnter", function(b)
        local key = self.itemKey
        if not key then return end
        GameTooltip:SetOwner(b, "ANCHOR_RIGHT")
        if GameTooltip.SetItemKey then pcall(GameTooltip.SetItemKey, GameTooltip, key.itemID, key.itemLevel, key.itemSuffix) else GameTooltip:SetItemByID(key.itemID) end
        GameTooltip:Show()
    end)
    v.slot:SetScript("OnLeave", function() GameTooltip:Hide() end)
    v.name = UI.Text(v, "unit-name-lg", "ink")
    v.name:SetPoint("LEFT", v.slot, "RIGHT", S["space-4"], 0)
    v.back = UI.Button(v, { text = "Back", icon = "reset", onClick = function() self.view = "browse"; self:Refresh() end })
    v.back:SetPoint("TOPRIGHT")
    -- the foot: bid, buy out; a commodity's quantity, unit price, total, buy now
    v.foot = CreateFrame("Frame", nil, v)
    v.foot:SetPoint("BOTTOMLEFT")
    v.foot:SetPoint("BOTTOMRIGHT")
    v.foot:SetHeight(30)
    v.buyout = UI.Button(v.foot, { text = "Buy out", variant = "primary", onClick = function() self:BuyOut() end })
    v.buyout:SetPoint("RIGHT")
    v.bidButton = UI.Button(v.foot, { text = "Bid", onClick = function() self:Bid() end })
    v.bidButton:SetPoint("RIGHT", v.buyout, "LEFT", -S["space-2"], 0)
    v.bid = UI.MoneyInput(v.foot)
    v.bid:SetPoint("RIGHT", v.bidButton, "LEFT", -S["space-4"], 0)
    v.bidLabel = UI.Text(v.foot, "caption", "ink-muted")
    v.bidLabel:SetValue("Your bid")
    v.bidLabel:SetPoint("RIGHT", v.bid, "LEFT", -S["space-3"], 0)
    v.buyNow = UI.Button(v.foot, { text = "Buy now", variant = "primary", onClick = function() self:BuyCommodity() end })
    v.buyNow:SetPoint("RIGHT")
    v.qtyLabel = UI.Text(v.foot, "caption", "ink-muted")
    v.qtyLabel:SetValue("Quantity")
    v.qtyLabel:SetPoint("LEFT")
    v.qty = UI.TextField(v.foot, { width = 70, onTextChanged = function() self:DrawCommodityFoot() end })
    v.qty.edit:SetNumeric(true)
    v.qty.edit:SetMaxLetters(6)
    v.qty:SetPoint("LEFT", v.qtyLabel, "RIGHT", S["space-3"], 0)
    v.max = UI.Button(v.foot, { text = "Max", onClick = function()
        local total = 0
        for _, o in ipairs(self.offers or {}) do total = total + (o.quantity or 0) end
        v.qty:SetValue(tostring(total))
        self:DrawCommodityFoot()
    end })
    v.max:SetPoint("LEFT", v.qty, "RIGHT", S["space-2"], 0)
    v.unitLabel = UI.Text(v.foot, "caption", "ink-muted")
    v.unitLabel:SetValue("Unit price")
    v.unitLabel:SetPoint("LEFT", v.max, "RIGHT", S["space-5"], 0)
    v.unit = UI.Money(v.foot)
    v.unit:SetPoint("LEFT", v.unitLabel, "RIGHT", S["space-3"], 0)
    v.totalLabel = UI.Text(v.foot, "caption", "ink-muted")
    v.totalLabel:SetValue("Total")
    v.totalLabel:SetPoint("LEFT", v.unit, "RIGHT", S["space-5"], 0)
    v.total = UI.Money(v.foot)
    v.total:SetPoint("LEFT", v.totalLabel, "RIGHT", S["space-3"], 0)
    -- the auctions or offers between head and foot
    v.table = buildTable(v, { { label = "Buyout", w = 120 } })
    v.table:SetPoint("TOPLEFT", v.slot, "BOTTOMLEFT", 0, -S["space-4"])
    v.table:SetPoint("BOTTOMRIGHT", v.foot, "TOPRIGHT", 0, S["space-4"])
end

function M:OpenItem(key)
    local info = keyInfo(key) or {}
    self.view = info.isCommodity and "commodity" or "item"
    self.itemKey, self.chosen, self.offers, self.auctions = key, nil, {}, {}
    self.itemView.qty:SetValue("1")
    self:Note(info.isCommodity and "Asking for the offers…" or "Asking for the auctions…")
    call(AH.SendSearchQuery, key, sorts(), true)
    self:Refresh()
end

function M:DrawItemView()
    local v, key = self.itemView, self.itemKey
    local info = keyInfo(key) or {}
    v.slot.skin:SetItem({ icon = info.iconFileID, quality = QUALITY[info.quality or 1] or "common" })
    v.name:SetValue(info.itemName or "…")
    v.name:SetColor((info.quality and info.quality ~= 1) and ("quality-" .. (QUALITY[info.quality] or "common")) or "ink")
    local commodity = self.view == "commodity"
    for _, w in ipairs({ v.buyout, v.bidButton, v.bid, v.bidLabel }) do w:SetShown(not commodity) end
    for _, w in ipairs({ v.buyNow, v.qtyLabel, v.qty, v.max, v.unitLabel, v.unit, v.totalLabel, v.total }) do w:SetShown(commodity) end
    local t = v.table
    local rows = {}
    if commodity then
        t:SetCols({ { label = "Unit price", w = 140 }, { label = "Available", w = 90, right = true }, { label = "Sellers" } })
        self.offers = {}
        for i = 1, (call(AH.GetNumCommoditySearchResults, key.itemID) or 0) do
            local o = call(AH.GetCommoditySearchResultInfo, key.itemID, i)
            if o then self.offers[#self.offers + 1] = o end
        end
        if self.offers[1] then self:Seen(key.itemID, self.offers[1].unitPrice) end
        for _, o in ipairs(self.offers) do
            local who
            if o.containsOwnerItem then who = "|cff" .. T.color["arcane"].hex .. "Yours|r"
            elseif o.owners and o.owners[1] and (o.totalNumberOfOwners or 0) <= 1 then who = o.owners[1]
            else who = (o.totalNumberOfOwners or 0) .. " sellers" end
            rows[#rows + 1] = { o.unitPrice or 0, tostring(o.quantity or 0), who }
        end
    else
        self.auctions = {}
        for i = 1, (call(AH.GetNumItemSearchResults, key) or 0) do
            local a = call(AH.GetItemSearchResultInfo, key, i)
            if a then self.auctions[#self.auctions + 1] = a end
        end
        local withBid, low = false, nil
        for _, a in ipairs(self.auctions) do
            if a.bidAmount or a.minBid then withBid = true end
            if a.buyoutAmount and a.buyoutAmount > 0 and (a.quantity or 1) > 0 then
                local each = math.floor(a.buyoutAmount / (a.quantity or 1))
                if not low or each < low then low = each end
            end
        end
        self:Seen(key.itemID, low)
        local cols = {}
        if withBid then cols[#cols + 1] = { label = "Bid", w = 120 } end
        cols[#cols + 1] = { label = "Buyout", w = 120 }
        cols[#cols + 1] = { label = "Quantity", w = 70, right = true }
        cols[#cols + 1] = { label = "Time left" }
        t:SetCols(cols)
        for _, a in ipairs(self.auctions) do
            local cells = {}
            if withBid then cells[#cells + 1] = (a.bidAmount or a.minBid) or false end
            cells[#cells + 1] = a.buyoutAmount or "none"
            cells[#cells + 1] = tostring(a.quantity or 1)
            cells[#cells + 1] = BAND[a.timeLeft or -1] or "?"
            rows[#rows + 1] = cells
        end
    end
    for i, cells in ipairs(rows) do
        local row = tableRow(t, i)
        row.money = row.money or {}
        row.texts = row.texts or {}
        local frames = {}
        for k, val in ipairs(cells) do
            if type(val) == "number" then
                row.money[k] = row.money[k] or UI.Money(row)
                row.money[k]:SetCopper(val)
                row.money[k]:Show()
                if row.texts[k] then row.texts[k]:Hide() end
                frames[k] = row.money[k]
            else
                row.texts[k] = row.texts[k] or UI.Text(row, k == 1 and "caption" or "body", "ink")
                row.texts[k]:SetValue(val == false and "—" or tostring(val))
                row.texts[k]:SetJustifyH(t.cols[k] and t.cols[k].right and "RIGHT" or "LEFT")
                row.texts[k]:Show()
                if row.money[k] then row.money[k]:Hide() end
                frames[k] = row.texts[k]
            end
        end
        for k = #cells + 1, 6 do
            if row.money[k] then row.money[k]:Hide() end
            if row.texts[k] then row.texts[k]:Hide() end
        end
        row:ClearAllPoints()
        row:SetPoint("TOPLEFT", 0, -(i - 1) * ROW_H)
        row:SetPoint("RIGHT", t.list.child, "RIGHT")
        placeCells(t, row, frames)
        row.index = i
        row.sel:SetShown(not commodity and self.chosen == i)
        row.onEnter = nil
        row:SetScript("OnClick", function(btn)
            if commodity then return end
            self.chosen = btn.index
            self:DrawItemFoot()
            self:DrawItemView()
        end)
        row:Show()
    end
    for i = #rows + 1, #t.rows do t.rows[i]:Hide() end
    t.list.child:SetHeight(math.max(1, #rows * ROW_H))
    if commodity then self:DrawCommodityFoot() else self:DrawItemFoot() end
end

-- An item's foot: Bid only for an auction with one, Buy out for one with a buyout.
function M:DrawItemFoot()
    local v = self.itemView
    local a = self.chosen and self.auctions and self.auctions[self.chosen]
    local hasBid = a and (a.bidAmount or a.minBid)
    for _, w in ipairs({ v.bidButton, v.bid, v.bidLabel }) do w:SetShown(hasBid and true or false) end
    if hasBid then
        local min = a.minBid or a.bidAmount or 0
        if (v.bid:GetCopper() or 0) < min then v.bid:SetCopper(min) end
    end
    v.buyout:SetEnabledState(a and a.buyoutAmount and a.buyoutAmount > 0 and (GetMoney() or 0) >= a.buyoutAmount or false)
    v.buyout.tooltip = not a and { title = "Buy out", description = "Choose an auction." }
        or (a.buyoutAmount and (GetMoney() or 0) < a.buyoutAmount) and { title = "Buy out", description = "Not enough money." } or nil
end

-- A commodity's foot: what a quantity costs, cheapest offers first.
function M:CommodityPrice(qty)
    local left, total = qty, 0
    for _, o in ipairs(self.offers or {}) do
        if left <= 0 then break end
        local n = math.min(left, o.quantity or 0)
        total = total + n * (o.unitPrice or 0)
        left = left - n
    end
    return total, left > 0
end

function M:DrawCommodityFoot()
    local v = self.itemView
    local qty = tonumber(v.qty.edit:GetText()) or 0
    local total, short = self:CommodityPrice(qty)
    v.unit:SetCopper(qty > 0 and math.floor(total / qty + 0.5) or 0)
    v.total:SetCopper(total)
    local money = GetMoney() or 0
    local ok = qty > 0 and not short and total <= money
    v.buyNow:SetEnabledState(ok)
    v.buyNow.tooltip = (not ok) and { title = "Buy now",
        description = qty <= 0 and "How many?" or short and "There aren't that many." or "Not enough money." } or nil
end

function M:BuyOut()
    local a = self.chosen and self.auctions and self.auctions[self.chosen]
    if not (a and a.buyoutAmount) then return end
    local info = keyInfo(self.itemKey) or {}
    UI.Confirm({ title = "Buy out " .. (info.itemName or "this") .. "?", text = ("For %s."):format(coins(a.buyoutAmount)), confirm = "Buy out",
        onConfirm = function()
            local ok, err = pcall(AH.PlaceBid, a.auctionID, a.buyoutAmount)
            if not ok then self:Note("Couldn't buy out: " .. tostring(err), "error") end
        end })
end

function M:Bid()
    local a = self.chosen and self.auctions and self.auctions[self.chosen]
    if not a then return end
    local amount = self.itemView.bid:GetCopper()
    local ok, err = pcall(AH.PlaceBid, a.auctionID, amount)
    if not ok then self:Note("Couldn't bid: " .. tostring(err), "error") else self:Note("Bid " .. coins(amount) .. ".") end
end

-- Buy now asks the game; it answers with the final price (COMMODITY_PRICE_UPDATED).
function M:BuyCommodity()
    local qty = tonumber(self.itemView.qty.edit:GetText()) or 0
    if qty <= 0 or not self.itemKey then return end
    self.buying = { itemID = self.itemKey.itemID, qty = qty, expected = (self:CommodityPrice(qty)) }
    self:Note("Asking for the final price…")
    local ok, err = pcall(AH.StartCommoditiesPurchase, self.itemKey.itemID, qty)
    if not ok then
        self.buying = nil
        self:Note("Couldn't buy: " .. tostring(err), "error")
    end
end

function M:OnCommodityPrice(unit, total)
    local b = self.buying
    if not b then return end
    local info = keyInfo(self.itemKey) or {}
    local changed = b.expected and total and total ~= b.expected
    UI.Confirm({ title = ("Buy %d %s?"):format(b.qty, info.itemName or "of this"),
        text = ("The game's final price: %s (%s each).%s"):format(coins(total), coins(unit),
            changed and " It changed since you searched: someone bought or posted." or ""),
        confirm = "Buy",
        onConfirm = function()
            local ok, err = pcall(AH.ConfirmCommoditiesPurchase, b.itemID, b.qty)
            if not ok then self:Note("Couldn't buy: " .. tostring(err), "error") end
        end,
        onCancel = function()
            call(AH.CancelCommoditiesPurchase)
            self:Note("")
        end })
    self.buying = nil
end

--------------------------------------------------------------------------------
-- What SuuUI remembers per item (by item ID), kept per character and read
-- across all of them: the lowest buyout seen (each search; Scan all fills it
-- too) and the price you last posted at
--------------------------------------------------------------------------------

function M:Seen(itemID, price)
    if not (itemID and price and price > 0) then return end
    local d = self:CharData()
    d.seen = d.seen or {}
    local now = time()
    local e = d.seen[itemID]
    -- a newer search replaces an old low; within a day the lower one stays
    if not e or now - (e.at or 0) > 86400 or price < e.price then d.seen[itemID] = { price = price, at = now } end
end

-- The newest entry for an item across your characters.
local function newest(self, key, itemID)
    local best
    for _, d in pairs(self:AllCharData()) do
        local e = d[key] and d[key][itemID]
        if e and (not best or (e.at or 0) > (best.at or 0)) then best = e end
    end
    return best
end
function M:LowestSeen(itemID) return newest(self, "seen", itemID) end
function M:LastPosted(itemID) return newest(self, "posted", itemID) end

local function when(at)
    if not at then return "" end
    local d = date("*t", at)
    local today = date("*t")
    if d.year == today.year and d.yday == today.yday then return ("today %02d:%02d"):format(d.hour, d.min) end
    local days = math.floor((time() - at) / 86400)
    return days <= 1 and "yesterday" or (days .. " days ago")
end


--------------------------------------------------------------------------------
-- Scan all: every auction once (the game allows it every 15 minutes); the
-- lowest buyout per item into the memory the sell view and tooltips use
--------------------------------------------------------------------------------

local SCAN_WAIT = 15 * 60

-- When any of your characters last scanned (the game's wait is per account).
function M:LastScan()
    local last
    for _, d in pairs(self:AllCharData()) do
        if d.scanAt and (not last or d.scanAt > last) then last = d.scanAt end
    end
    return last
end

function M:DrawScan()
    if not self.scanButton then return end
    local last = self:LastScan()
    local wait = last and (last + SCAN_WAIT - time()) or 0
    if self.scanning then
        self.scanButton:SetEnabledState(false)
        self.scanWhen:SetValue(self.scanning.note or "Scanning…")
        self.scanWhen:SetColor("ink-muted")
    elseif wait > 0 then
        local text = ("Again in %d min"):format(math.ceil(wait / 60))
        self.scanButton:SetEnabledState(false)
        self.scanButton.tooltip = { title = "Scan all", description = "The game allows one full scan every 15 minutes. " .. text .. "." }
        self.scanWhen:SetValue(text)
        self.scanWhen:SetColor("amber")
    else
        self.scanButton:SetEnabledState(true)
        self.scanButton.tooltip = { title = "Scan all", description = "Read every auction once, for the lowest buyouts in the sell view and tooltips." }
        self.scanWhen:SetValue(last and ("Last scan " .. when(last)) or "Not scanned yet")
        self.scanWhen:SetColor("ink-muted")
    end
end

function M:Scan()
    if self.scanning then return end
    self.scanning = { started = GetTime(), note = "Scanning… (about 20 s)" }
    self:Note("Asking for every auction…")
    local ok, err = pcall(AH.ReplicateItems)
    if not ok then
        self.scanning = nil
        self:Note("Couldn't scan: " .. tostring(err), "error")
    else
        -- no answer in a minute: the game didn't run it
        C_Timer.After(60, function()
            if self.scanning and not self.scanning.reading then
                self.scanning = nil
                self:Note("The scan didn't come back; try again later.", "error")
                self:DrawScan()
            end
        end)
    end
    self:DrawScan()
end

-- The list came: read it a slice a frame (tens of thousands of auctions),
-- the lowest buyout per item (per unit for stacks), then keep them.
function M:ReadScan()
    local sc = self.scanning
    if not sc or sc.reading then return end
    sc.reading = true
    local n = call(AH.GetNumReplicateItems) or 0
    local low, i = {}, 0
    local ticker
    ticker = C_Timer.NewTicker(0, function()
        local stop = math.min(n, i + 2500)
        for k = i, stop - 1 do
            -- (all 17 values: the helper `call` passes on only five)
            local ok, _, _, count, _, _, _, _, _, _, buyout, _, _, _, _, _, _, itemID = pcall(AH.GetReplicateItemInfo, k)
            if ok and itemID and buyout and buyout > 0 then
                local each = math.floor(buyout / math.max(1, count or 1))
                if not low[itemID] or each < low[itemID] then low[itemID] = each end
            end
        end
        i = stop
        sc.note = ("Reading %d of %d…"):format(i, n)
        self:DrawScan()
        if i >= n then
            ticker:Cancel()
            local d = self:CharData()
            d.seen = d.seen or {}
            local now, items = time(), 0
            for itemID, price in pairs(low) do
                d.seen[itemID] = { price = price, at = now }
                items = items + 1
            end
            d.scanAt = now
            self.scanning = nil
            self:Note(("Scan done: %d auctions, %d items, in %d s."):format(n, items, math.floor(GetTime() - sc.started + 0.5)))
            self:QueueRefresh()
        end
    end)
end

-- Item tooltips anywhere: the lowest buyout seen.
function M:HookTooltips()
    if self.tooltipHooked or not (TooltipDataProcessor and TooltipDataProcessor.AddTooltipPostCall and Enum.TooltipDataType) then return end
    self.tooltipHooked = true
    TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Item, function(tooltip, data)
        if not self:IsEnabled() or not data or isSecret(data.id) then return end
        local itemID = data.id
        if type(itemID) ~= "number" then return end
        local e = self:LowestSeen(itemID)
        if not e then return end
        local stack = select(8, C_Item.GetItemInfo(itemID))
        local each = (stack and stack > 1) and " each" or ""
        tooltip:AddLine(("Lowest buyout seen: %s%s · %s"):format(coins(e.price), each, when(e.at)), 0.75, 0.75, 0.75)
    end)
end

--------------------------------------------------------------------------------
-- Sell: the item, its prices, the duration, the deposit, Post; your items
--------------------------------------------------------------------------------

local DURATIONS = { { value = 1, label = "12 hours" }, { value = 2, label = "24 hours" }, { value = 3, label = "48 hours" } }

-- The items in your bags the auction house takes, one entry per item.
local function sellable()
    local out, byID = {}, {}
    for bag = 0, 4 do
        for slot = 1, (call(C_Container.GetContainerNumSlots, bag) or 0) do
            local info = call(C_Container.GetContainerItemInfo, bag, slot)
            if info and info.itemID and not (info.isBound) then
                local loc = ItemLocation:CreateFromBagAndSlot(bag, slot)
                if call(AH.IsSellItemValid, loc, false) then
                    local e = byID[info.itemID]
                    if not e then
                        e = { itemID = info.itemID, loc = loc, icon = info.iconFileID, quality = info.quality,
                              link = info.hyperlink, count = 0 }
                        byID[info.itemID] = e
                        out[#out + 1] = e
                    end
                    e.count = e.count + (info.stackCount or 1)
                end
            end
        end
    end
    table.sort(out, function(a, b) return (a.link or "") < (b.link or "") end)
    return out
end

function M:BuildSell(page)
    local sell = {}
    self.sell = sell
    local FORM_W = 430
    local form = CreateFrame("Frame", nil, page)
    form:SetPoint("TOPLEFT")
    form:SetPoint("BOTTOMLEFT")
    form:SetWidth(FORM_W)
    -- the item: drop it here, or pick it from your items
    sell.slot = UI.ItemSlot(form)
    sell.slot:SetPoint("TOPLEFT")
    sell.slot:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    local function fromCursor()
        local loc = C_Cursor and C_Cursor.GetCursorItem and C_Cursor.GetCursorItem()
        if loc then
            ClearCursor()
            self:SetSellItem(loc)
        end
    end
    sell.slot:SetScript("OnReceiveDrag", fromCursor)
    sell.slot:SetScript("OnClick", function(_, button)
        if button == "RightButton" then self:SetSellItem(nil) else fromCursor() end
    end)
    sell.slot:SetScript("OnEnter", function(b)
        if not sell.loc then return end
        GameTooltip:SetOwner(b, "ANCHOR_RIGHT")
        local bag, slot = sell.loc:GetBagAndSlot()
        if bag then GameTooltip:SetBagItem(bag, slot) end
        GameTooltip:Show()
    end)
    sell.slot:SetScript("OnLeave", function() GameTooltip:Hide() end)
    sell.name = UI.Text(form, "unit-name-lg", "ink")
    sell.name:SetPoint("TOPLEFT", sell.slot, "TOPRIGHT", S["space-4"], 0)
    sell.name:SetPoint("RIGHT", form, "RIGHT")
    sell.name:SetWordWrap(false)
    sell.last = UI.Text(form, "caption", "ink-muted")
    sell.last:SetPoint("TOPLEFT", sell.name, "BOTTOMLEFT", 0, -3)
    sell.lowest = UI.Text(form, "caption", "ink-muted")
    sell.lowest:SetPoint("TOPLEFT", sell.last, "BOTTOMLEFT", 0, -2)
    -- the fields, each a caption over its control
    local y = 36 + S["space-6"] + 14
    local function field(label)
        local l = UI.Text(form, "caption", "ink-muted")
        l:SetValue(label)
        l:SetPoint("TOPLEFT", 0, -y - 8)
        local holder = CreateFrame("Frame", nil, form)
        holder:SetPoint("TOPLEFT", 110, -y)
        holder:SetSize(FORM_W - 110, 30)
        y = y + 30 + S["space-4"]
        return holder, l
    end
    local qh = field("Quantity")
    sell.qty = UI.TextField(qh, { width = 80, onTextChanged = function() self:DrawSell() end })
    sell.qty.edit:SetNumeric(true)
    sell.qty.edit:SetMaxLetters(6)
    sell.qty:SetPoint("LEFT")
    sell.max = UI.Button(qh, { text = "Max", onClick = function()
        sell.qty:SetValue(tostring(sell.loc and call(AH.GetAvailablePostCount, sell.loc) or 1))
        self:DrawSell()
    end })
    sell.max:SetPoint("LEFT", sell.qty, "RIGHT", S["space-2"], 0)
    local bh
    bh, sell.bidLabel = field("Starting bid")
    sell.bidHolder = bh
    sell.bid = UI.MoneyInput(bh, { onChange = function() self:DrawSell() end })
    sell.bid:SetPoint("LEFT")
    local ph
    ph, sell.priceLabel = field("Buyout")
    sell.price = UI.MoneyInput(ph, { onChange = function()
        sell.priceTyped = true -- yours from now on: no undercut over it
        self:DrawSell()
    end })
    sell.price:SetPoint("LEFT")
    local dh = field("Duration")
    sell.duration = UI.Segmented(dh, { options = DURATIONS, value = 2, onChange = function() self:DrawSell() end })
    sell.duration:SetPoint("LEFT")
    -- deposit and total
    local th = field("Deposit")
    sell.deposit = UI.Money(th)
    sell.deposit:SetPoint("LEFT")
    local th2 = field("Total")
    sell.total = UI.Money(th2)
    sell.total:SetPoint("LEFT")
    sell.post = UI.Button(form, { text = "Post", variant = "primary", width = 120, onClick = function() self:Post() end })
    sell.post:SetPoint("TOPRIGHT", form, "TOPLEFT", FORM_W, -y - S["space-2"])
    -- your items
    local list = CreateFrame("Frame", nil, page)
    list:SetPoint("TOPLEFT", FORM_W + S["space-6"], 0)
    list:SetPoint("BOTTOMRIGHT")
    local head = UI.Text(list, "header", "gilt-text")
    head:SetValue("Your items")
    head:SetPoint("TOPLEFT")
    sell.list = UI.ScrollArea(list, S["space-3"])
    sell.list:SetPoint("TOPLEFT", 0, -28)
    sell.list:SetPoint("BOTTOMRIGHT", -(S["space-3"] + 3), 0)
    sell.list:HookScript("OnSizeChanged", function(sc, w) sc.child:SetWidth(w) end)
    sell.rows = {}
    sell.none = UI.Text(sell.list.child, "body", "ink-muted")
    sell.none:SetPoint("TOPLEFT", 0, -S["space-4"])
    sell.none:SetValue("Nothing in your bags to sell here.")
end

function M:SetSellItem(loc)
    local sell = self.sell
    if loc and not call(AH.IsSellItemValid, loc, true) then
        self:Note("The auction house doesn't take that.", "error")
        return
    end
    sell.loc = loc
    sell.offered = nil -- until the background search answers
    sell.itemID = loc and C_Item.GetItemID(loc)
    sell.commodity = false
    if loc then
        local status = call(AH.GetItemCommodityStatus, loc)
        sell.commodity = Enum.ItemCommodityStatus and status == Enum.ItemCommodityStatus.Commodity or false
        -- the price you last posted at, else the lowest seen
        -- the price you last posted at, else the lowest seen, until the
        -- house says what it goes for now (then 1c under that: SellLowest)
        local last, low = self:LastPosted(sell.itemID), self:LowestSeen(sell.itemID)
        sell.priceTyped = false
        sell.price:SetCopper((last and last.price) or (low and low.price) or 0)
        sell.bid:Clear()
        sell.qty:SetValue(tostring(sell.commodity and (call(AH.GetAvailablePostCount, loc) or 1) or 1))
        -- what it goes for now: a commodity's offers through the sell
        -- search; anything else by a search for its exact name (the sell
        -- search brought nothing back for single items, found in game)
        local key = call(AH.GetItemKeyFromItem, loc)
        self.sellKey, self.sellBrowse = key, nil
        if sell.commodity and key then
            call(AH.SendSellSearchQuery, key, sorts(), true)
        else
            local name = C_Item.GetItemName(loc)
            local F = Enum.AuctionHouseFilter or {}
            if name then
                self.sellBrowse = sell.itemID
                call(AH.SendBrowseQuery, { searchString = name, sorts = sorts(), filters = { F.ExactMatch }, itemClassFilters = {} })
            end
        end
    end
    self:DrawSell()
end

function M:DrawSell()
    local sell = self.sell
    if not sell then return end
    local loc = sell.loc
    local valid = loc and loc:IsValid()
    if loc and not valid then sell.loc, loc = nil, nil end
    local link = loc and C_Item.GetItemLink(loc)
    sell.slot.skin:SetItem(loc and { icon = C_Item.GetItemIcon(loc), quality = QUALITY[C_Item.GetItemQuality(loc) or 1] or "common",
        count = call(AH.GetAvailablePostCount, loc) } or nil)
    sell.name:SetValue(loc and (C_Item.GetItemName(loc) or "?") or "Drop an item here, or choose one from your items")
    sell.name:SetStyle(loc and "unit-name-lg" or "caption")
    local q = loc and C_Item.GetItemQuality(loc)
    sell.name:SetColor(loc and ((q and q ~= 1) and ("quality-" .. (QUALITY[q] or "common")) or "ink") or "ink-muted")
    local last = loc and self:LastPosted(sell.itemID)
    local low = loc and self:LowestSeen(sell.itemID)
    sell.last:SetValue(last and ("Last posted at " .. coins(last.price) .. " · " .. when(last.at)) or "")
    -- what the background search found: nobody selling it now is worth saying
    local lowText = low and ("Lowest buyout seen: " .. coins(low.price) .. " · " .. when(low.at)) or ""
    if loc and sell.offered == false then
        lowText = (lowText ~= "" and (lowText .. "  ·  ") or "") .. "Nobody sells it right now."
    end
    sell.lowest:SetValue(lowText)
    -- a commodity: a unit price, no starting bid
    sell.bidHolder:SetShown(not sell.commodity)
    sell.bidLabel:SetShown(not sell.commodity)
    sell.priceLabel:SetValue(sell.commodity and "Unit price" or "Buyout")
    local qty = tonumber(sell.qty.edit:GetText()) or 0
    local dur = sell.duration.value or 2
    local deposit = 0
    if loc then
        if sell.commodity then deposit = call(AH.CalculateCommodityDeposit, sell.itemID, dur, qty) or 0
        else deposit = call(AH.CalculateItemDeposit, loc, dur, qty) or 0 end
    end
    sell.deposit:SetCopper(deposit)
    local price, bid = sell.price:GetCopper(), sell.bid:GetCopper()
    sell.total:SetCopper(sell.commodity and price * qty or price)
    -- Post, or why not
    local why
    if not loc then why = "Choose an item."
    elseif qty <= 0 then why = "How many?"
    elseif qty > (call(AH.GetAvailablePostCount, loc) or 0) then why = "You don't have that many."
    elseif sell.commodity and price <= 0 then why = "Give it a unit price."
    elseif not sell.commodity and price <= 0 and bid <= 0 then why = "Give it a buyout or a starting bid."
    elseif not sell.commodity and price > 0 and bid > price then why = "The starting bid is above the buyout."
    elseif deposit > (GetMoney() or 0) then why = "Not enough money for the deposit (" .. coins(deposit) .. ")." end
    sell.post:SetEnabledState(why == nil and not self.posting)
    sell.post.tooltip = why and { title = "Post", description = why } or nil
    self:DrawSellList()
end

function M:DrawSellList()
    local sell = self.sell
    local items = sellable()
    local c = sell.list.child
    for i, e in ipairs(items) do
        local r = sell.rows[i]
        if not r then
            r = CreateFrame("Button", nil, c)
            r:SetHeight(ROW_H)
            r.sel = UI.Fill(r, "arcane-soft", "BACKGROUND")
            r.sel:SetAllPoints()
            r.hover = UI.Fill(r, "surface-raised", "BACKGROUND", 1)
            r.hover:SetAllPoints()
            r.hover:SetAlpha(0.6)
            r.hover:Hide()
            r.slot = UI.ItemSlot(r, 24)
            r.slot:EnableMouse(false)
            r.slot:SetPoint("LEFT", S["space-2"], 0)
            r.seen = UI.Money(r)
            r.seen:SetPoint("RIGHT", -S["space-2"], 0)
            r.name = UI.Text(r, "label", "ink")
            r.name:SetPoint("LEFT", r.slot, "RIGHT", S["space-3"], 0)
            r.name:SetPoint("RIGHT", r.seen, "LEFT", -S["space-3"], 0)
            r.name:SetWordWrap(false)
            r:SetScript("OnEnter", function(b)
                b.hover:Show()
                GameTooltip:SetOwner(b, "ANCHOR_RIGHT")
                local bag, slot = b.loc:GetBagAndSlot()
                if bag then GameTooltip:SetBagItem(bag, slot) end
                GameTooltip:Show()
            end)
            r:SetScript("OnLeave", function(b) b.hover:Hide(); GameTooltip:Hide() end)
            r:SetScript("OnClick", function(b) self:SetSellItem(b.loc) end)
            sell.rows[i] = r
        end
        r.loc = e.loc
        r:ClearAllPoints()
        r:SetPoint("TOPLEFT", 0, -(i - 1) * ROW_H)
        r:SetPoint("RIGHT", c, "RIGHT")
        r.slot.skin:SetItem({ icon = e.icon, count = e.count, quality = QUALITY[e.quality or 1] or "common" })
        local name = e.link and e.link:match("%[(.-)%]") or "?"
        r.name:SetValue(name)
        r.name:SetColor((e.quality and e.quality ~= 1) and ("quality-" .. (QUALITY[e.quality] or "common")) or "ink")
        local low = self:LowestSeen(e.itemID)
        r.seen:SetShown(low ~= nil)
        if low then r.seen:SetCopper(low.price) end
        r.sel:SetShown(sell.itemID == e.itemID)
        r:Show()
    end
    for i = #items + 1, #sell.rows do sell.rows[i]:Hide() end
    c:SetHeight(math.max(1, #items * ROW_H))
    sell.none:SetShown(#items == 0)
end

function M:Post()
    local sell = self.sell
    local loc = sell.loc
    if not (loc and loc:IsValid()) then return end
    local qty = tonumber(sell.qty.edit:GetText()) or 0
    local dur = sell.duration.value or 2
    local price, bid = sell.price:GetCopper(), sell.bid:GetCopper()
    self.posting = { itemID = sell.itemID, price = price, qty = qty, name = C_Item.GetItemName(loc) }
    local ok, needs
    if sell.commodity then
        ok, needs = pcall(AH.PostCommodity, loc, dur, qty, price)
        if ok and needs then ok = pcall(AH.ConfirmPostCommodity, loc, dur, qty, price) end
    else
        ok, needs = pcall(AH.PostItem, loc, dur, qty, bid > 0 and bid or nil, price > 0 and price or nil)
        if ok and needs then ok = pcall(AH.ConfirmPostItem, loc, dur, qty, bid > 0 and bid or nil, price > 0 and price or nil) end
    end
    if not ok then
        self.posting = nil
        self:Note("Couldn't post: " .. tostring(needs), "error")
    end
    self:DrawSell()
end

-- What the item goes for now: the price 1c under it (your own cheapest
-- offer: the same price, not under yourself), unless you typed one.
function M:SellLowest(low, mine)
    local sell = self.sell
    if not (sell and sell.loc and low and low > 0) or sell.priceTyped then return end
    sell.price:SetCopper(mine and low or math.max(1, low - 1))
    if not sell.commodity then sell.bid:Clear() end
end

-- The game confirmed a post: remember its price, say so.
function M:Posted()
    local p = self.posting
    self.posting = nil
    if not p then return end
    if p.price and p.price > 0 then
        local d = self:CharData()
        d.posted = d.posted or {}
        d.posted[p.itemID] = { price = p.price, at = time() }
    end
    self:Note(("Posted: %s ×%d."):format(p.name or "?", p.qty or 1), "ok")
    self:SetSellItem(nil)
end

--------------------------------------------------------------------------------
-- The window
--------------------------------------------------------------------------------

function M:Build()
    local w = UI.WindowFrame(SuuUI.Root, { name = "SuuUIAuctionHouseWindow", title = "Auction house", width = WIDTH, height = HEIGHT,
        footer = true, onClose = function(win) win:Hide() end,
        tabs = { { key = "buy", label = "Buy" }, { key = "sell", label = "Sell" }, { key = "auctions", label = "Auctions" } },
        onTab = function(key)
            self.tab = key
            for k, page in pairs(self.pages) do page:SetShown(k == key) end
            self:Refresh()
        end })
    w:SetPoint("TOPLEFT", UIParent, "TOPLEFT", 16, -116)
    w:Hide()
    w:HookScript("OnHide", function()
        if self.open and not self.gameWindow then call(AH.CloseAuctionHouse) end
    end)
    w.scroll:Hide()
    self.window = w
    self.pages = {}
    for _, key in ipairs({ "buy", "sell", "auctions" }) do
        local page = CreateFrame("Frame", nil, w.body)
        page:SetAllPoints()
        page:Hide()
        self.pages[key] = page
    end
    self:BuildBuy(self.pages.buy)
    self:BuildSell(self.pages.sell)
    -- Auctions comes next: meanwhile the game's own window
    for _, key in ipairs({ "auctions" }) do
        local page = self.pages[key]
        local text = UI.Text(page, "body", "ink-muted")
        text:SetPoint("TOP", 0, -80)
        text:SetValue((key == "sell" and "Selling" or "Your auctions and bids") .. " come in the next step of SuuUI's auction house.")
        local b = UI.Button(page, { text = "Open the game's window", onClick = function() self:ShowGameWindow(key) end })
        b:SetPoint("TOP", text, "BOTTOM", 0, -S["space-5"])
    end
    -- the foot: the note at the left, your money at the right
    self.note = UI.Text(w.footer, "caption", "ink-muted")
    self.note:SetPoint("LEFT")
    self.note:SetPoint("RIGHT", -160, 0)
    self.note:SetWordWrap(false)
    self.money = UI.Money(w.footer)
    self.money:SetPoint("RIGHT")
end

-- The game's own window back, for what SuuUI's doesn't do yet; closing it
-- closes the auction house.
function M:ShowGameWindow(tab)
    local f = _G.AuctionHouseFrame
    if not f then return end
    self.gameWindow = true
    self.window:Hide()
    self.placing = true
    f:SetAlpha(1)
    f:ClearAllPoints()
    f:SetPoint("TOPLEFT", UIParent, "TOPLEFT", 16, -116)
    self.placing = false
    if tab == "sell" and f.SetDisplayMode and AuctionHouseFrameDisplayMode then pcall(f.SetDisplayMode, f, AuctionHouseFrameDisplayMode.ItemSell) end
    if tab == "auctions" and f.SetDisplayMode and AuctionHouseFrameDisplayMode then pcall(f.SetDisplayMode, f, AuctionHouseFrameDisplayMode.Auctions) end
end

function M:Refresh()
    if not (self.window and self.window:IsShown() and self.open) then return end
    self.money:SetCopper(GetMoney() or 0)
    if self.tab == "sell" then self:DrawSell() return end
    if (self.tab or "buy") ~= "buy" then return end
    self:DrawCategories()
    self:DrawScan()
    local browse = (self.view or "browse") == "browse"
    self.results_t:SetShown(browse)
    self.itemView:SetShown(not browse)
    if browse then
        self.empty:SetShown(false)
        self:DrawResults()
    else
        self.empty:Hide()
        self.more:Hide()
        self:DrawItemView()
    end
end

function M:QueueRefresh()
    if self.refreshPending then return end
    self.refreshPending = true
    C_Timer.After(0.05, function()
        self.refreshPending = nil
        self:Refresh()
    end)
end

-- The game's frame out of sight: see-through and off screen, still shown,
-- and back off screen whenever the game places it again (unless it was
-- asked for: ShowGameWindow).
function M:Away(frame)
    if not frame then return end
    local function away()
        if not self:IsEnabled() or self.gameWindow then return end
        self.placing = true
        frame:SetAlpha(0)
        frame:ClearAllPoints()
        frame:SetPoint("TOPLEFT", UIParent, "TOPRIGHT", 5000, 0)
        self.placing = false
    end
    away()
    if not self.awayHooked then
        self.awayHooked = true
        hooksecurefunc(frame, "SetPoint", function() if not self.placing then C_Timer.After(0, away) end end)
    end
end

function M:OnEnable()
    if not self.window then self:Build() end
    self:OnGameEvent("AUCTION_HOUSE_SHOW", function()
        self.open, self.gameWindow = true, false
        self.view, self.searched, self.category, self.subcategory, self.catFilters = "browse", false, nil, nil, nil
        C_Timer.After(0, function()
            local f = _G.AuctionHouseFrame
            self:Away(f)
            -- a bag item right-clicked here goes to the game's sell form:
            -- to SuuUI's Sell instead
            if f and f.SetPostItem and not self.postHooked then
                self.postHooked = true
                hooksecurefunc(f, "SetPostItem", function(_, loc)
                    if not self:IsEnabled() or self.gameWindow or not loc then return end
                    self.window:SetTab("sell")
                    self:SetSellItem(loc)
                end)
            end
        end)
        self.window:Show()
        self.window:SetTab("buy")
        self:Note("")
    end)
    self:OnGameEvent("AUCTION_HOUSE_CLOSED", function()
        self.open = false
        self.gameWindow = false
        self.window:Hide()
    end)
    for _, e in ipairs({ "AUCTION_HOUSE_BROWSE_RESULTS_UPDATED", "AUCTION_HOUSE_BROWSE_RESULTS_ADDED", "ITEM_KEY_ITEM_INFO_RECEIVED",
                         "ITEM_SEARCH_RESULTS_UPDATED", "ITEM_SEARCH_RESULTS_ADDED", "COMMODITY_SEARCH_RESULTS_UPDATED",
                         "COMMODITY_SEARCH_RESULTS_ADDED", "PLAYER_MONEY", "AUCTION_HOUSE_FAVORITES_UPDATED" }) do
        self:OnGameEvent(e, function()
            if e:find("RESULTS") then self:Note("") end
            self:QueueRefresh()
        end)
    end
    -- the sell view's search by name: the item's lowest price among the results
    self:OnGameEvent("AUCTION_HOUSE_BROWSE_RESULTS_UPDATED", function()
        local id = self.sellBrowse
        if not id or self.tab ~= "sell" or not self.sell then return end
        self.sellBrowse = nil
        local low
        for _, r in ipairs(call(AH.GetBrowseResults) or {}) do
            if r.itemKey and r.itemKey.itemID == id and r.minPrice and r.minPrice > 0 then
                if not low or r.minPrice < low then low = r.minPrice end
            end
        end
        self:Seen(id, low)
        self:SellLowest(low, false)
        self.sell.offered = low and true or false
        self:QueueRefresh()
    end)
    self:OnGameEvent("AUCTION_HOUSE_BROWSE_FAILURE", function() self:Note("The search failed; try again in a moment.", "error") end)
    self:OnGameEvent("COMMODITY_PRICE_UPDATED", function(_, unit, total) self:OnCommodityPrice(unit, total) end)
    self:OnGameEvent("COMMODITY_PRICE_UNAVAILABLE", function()
        self.buying = nil
        self:Note("That price isn't available any more: search again.", "error")
    end)
    self:OnGameEvent("COMMODITY_PURCHASE_SUCCEEDED", function() self:Note("Bought.", "ok"); if self.itemKey then call(AH.SendSearchQuery, self.itemKey, sorts(), true) end end)
    self:OnGameEvent("COMMODITY_PURCHASE_FAILED", function() self:Note("The purchase failed.", "error") end)
    self:OnGameEvent("AUCTION_HOUSE_PURCHASE_COMPLETED", function()
        self:Note("Bought.", "ok")
        self.chosen = nil
        if self.itemKey then call(AH.SendSearchQuery, self.itemKey, sorts(), true) end
    end)
    self:OnGameEvent("AUCTION_HOUSE_AUCTION_CREATED", function() self:Posted() end)
    self:OnGameEvent("REPLICATE_ITEM_LIST_UPDATE", function() self:ReadScan() end)
    self:HookTooltips()
    -- the wait counts down while the window is open
    C_Timer.NewTicker(30, function() if self.window and self.window:IsShown() then self:DrawScan() end end)
    self:OnGameEvent("BAG_UPDATE_DELAYED", function() if self.tab == "sell" then self:QueueRefresh() end end)
    self:OnGameEvent("AUCTION_HOUSE_POST_ERROR", function()
        self.posting = nil
        self:Note("Couldn't post.", "error")
    end)
    -- the sell search: what the chosen item goes for now
    for _, e in ipairs({ "COMMODITY_SEARCH_RESULTS_UPDATED", "ITEM_SEARCH_RESULTS_UPDATED", "ITEM_SEARCH_RESULTS_ADDED" }) do
        self:OnGameEvent(e, function(_, answered)
            local key = self.sellKey
            if not key or self.tab ~= "sell" then return end
            -- an item's results come under the house's own key for it (its
            -- item level and suffix as the house sees them), not always the
            -- one made from the bag item
            if type(answered) == "table" and answered.itemID == key.itemID then key = answered end
            local low, mine
            if self.sell.commodity then
                local o = call(AH.GetCommoditySearchResultInfo, key.itemID, 1)
                low, mine = o and o.unitPrice, o and o.containsOwnerItem
            else
                -- the cheapest buyout per item among the auctions
                for i = 1, (call(AH.GetNumItemSearchResults, key) or 0) do
                    local a = call(AH.GetItemSearchResultInfo, key, i)
                    if a and a.buyoutAmount and a.buyoutAmount > 0 then
                        local each = math.floor(a.buyoutAmount / (a.quantity or 1))
                        if not low or each < low then low, mine = each, a.containsOwnerItem end
                    end
                end
            end
            self:Seen(key.itemID, low)
            self:SellLowest(low, mine)
            self.sell.offered = low and true or false
            self:QueueRefresh()
        end)
    end
    self:OnGameEvent("AUCTION_HOUSE_SHOW_ERROR", function(_, err) self:Note("The auction house said no (" .. tostring(err) .. ").", "error") end)
end

function M:OnDisable()
    if self.window then self.window:Hide() end
end
