-- Units/Merchant.lua
-- SuuUI's own merchant window (plan 3.6, design component MerchantWindow):
-- the game's MerchantFrame stays open (it drives the conversation) but out of
-- sight, and this window shows the goods as one scrolling list with a
-- search, buys any number of items in the merchant's stack sizes, shows how
-- many you have and what you already know, buys back, repairs and sells
-- junk. None of it is protected (/suu probe windows, 2026-10-16).
-- A built-in module written against the public API only.

local UI, T = SuuUI.UI, SuuUI.Tokens
local S = T.space

local M = SuuUI.RegisterModule({
    id = "merchant",
    name = "Merchant",
    description = "SuuUI's merchant window: one list with a search, a quantity to buy, what you have and know, buy back, repair and sell junk.",
    api = "0.17",
    reloadToToggle = true,
    defaults = {},
})

local isSecret = issecretvalue or function() return false end
local function plain(v) return v ~= nil and not isSecret(v) end
local function call(fn, ...)
    if type(fn) ~= "function" then return nil end
    local ok, a, b, c, d, e, f, g, h = pcall(fn, ...)
    if ok then return a, b, c, d, e, f, g, h end
end

local WIDTH, HEIGHT = 440, 600
local ROW_H = 46
local QUALITY = { [0] = "poor", "common", "uncommon", "rare", "epic", "legendary", "legendary", "legendary" }
local HIGH_PRICE = 1500000 -- 150g: the game asks before a purchase this dear

-- "1g 20s" in the coin colours, zero coins at the end left out.
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

local function icon(texture) return texture and ("|T" .. texture .. ":12:12:0:0|t") or "" end

--------------------------------------------------------------------------------
-- The goods
--------------------------------------------------------------------------------

-- "Already known" in the item's tooltip: a recipe, pet or mount you have.
local function isKnown(index)
    local data = C_TooltipInfo and call(C_TooltipInfo.GetMerchantItem, index)
    for _, line in ipairs(data and data.lines or {}) do
        if plain(line.leftText) and line.leftText == ITEM_SPELL_KNOWN then return true end
    end
    return false
end

-- How many of an item (or currency) you have.
local function haveOf(link, isCurrency)
    if not link then return 0 end
    if isCurrency then
        local info = C_CurrencyInfo and call(C_CurrencyInfo.GetCurrencyInfoFromLink, link)
        return info and info.quantity or 0
    end
    return call(C_Item.GetItemCount, link, true, false, true) or 0
end

-- One merchant item as the list shows it.
function M:Item(index)
    local info = call(C_MerchantFrame.GetItemInfo, index)
    if not info or not info.name then return nil end
    local link = call(GetMerchantItemLink, index)
    local quality = link and select(3, call(C_Item.GetItemInfo, link))
    local e = {
        index = index, name = info.name, texture = info.texture, link = link,
        quality = QUALITY[quality or 1] or "common",
        price = info.price or 0, stack = math.max(1, info.stackCount or 1),
        stock = info.numAvailable or -1, usable = info.isUsable, purchasable = info.isPurchasable,
        maxStack = math.max(1, call(GetMerchantItemMaxStack, index) or 1),
        costs = {},
    }
    if info.hasExtendedCost then
        for k = 1, (call(GetMerchantItemCostInfo, index) or 0) do
            local texture, value, costLink, currencyName = call(GetMerchantItemCostItem, index, k)
            if value and value > 0 then
                e.costs[#e.costs + 1] = { texture = texture, value = value, link = costLink, currency = currencyName ~= nil,
                                          name = currencyName }
            end
        end
    end
    e.have = link and haveOf(link) or 0
    e.known = isKnown(index)
    return e
end

-- How many purchases you can make of an item, and why not more (nil: no cap
-- but the merchant's own).
local function purchaseCap(e)
    local cap, why = math.huge, nil
    if e.stock >= 0 then cap, why = e.stock, "left" end
    if e.price > 0 then
        local afford = math.floor((GetMoney() or 0) / e.price)
        if afford < cap then cap, why = afford, "afford" end
    end
    for _, c in ipairs(e.costs) do
        local afford = math.floor(haveOf(c.link, c.currency) / c.value)
        if afford < cap then cap, why = afford, "afford" end
    end
    return cap, why
end

-- What a quantity (in items) really buys: whole purchases of the stack size,
-- capped. Returns purchases, items, and a note for the row.
local function plan(e, qty)
    qty = math.max(1, math.floor(qty or e.stack))
    local purchases = math.ceil(qty / e.stack)
    local cap, why = purchaseCap(e)
    local note
    if purchases > cap then
        purchases = math.max(0, cap)
        note = why == "left" and "Capped at what's left" or ("Capped: you can afford " .. purchases)
    end
    local items = purchases * e.stack
    if not note and e.stack > 1 and purchases > 1 then
        note = ("= %d purchases%s"):format(purchases, items ~= qty and (", " .. items .. " items") or "")
    elseif not note and e.stack > 1 and items ~= qty then
        note = ("= %d items"):format(items)
    end
    return purchases, items, note
end

-- Buys `items` of a merchant item, in calls the merchant takes (whole stacks,
-- up to its most a time), a moment apart.
function M:Buy(e, items)
    if items <= 0 then return end
    local per = math.max(e.stack, math.floor(e.maxStack / e.stack) * e.stack)
    local queue, left = {}, items
    while left > 0 do
        local n = math.min(per, left)
        queue[#queue + 1] = n
        left = left - n
    end
    local k = 0
    local function step()
        k = k + 1
        if not queue[k] or not self.open then return end
        BuyMerchantItem(e.index, queue[k])
        if queue[k + 1] then C_Timer.After(0.3, step) end
    end
    step()
end

-- Asks first where the game would: other costs, or a dear purchase.
function M:ConfirmBuy(e, purchases, items)
    local money = e.price * purchases
    local costs = {}
    for _, c in ipairs(e.costs) do costs[#costs + 1] = (c.value * purchases) .. " " .. icon(c.texture) end
    if money > 0 then costs[#costs + 1] = coins(money) end
    if #e.costs == 0 and money < HIGH_PRICE then
        self:Buy(e, items)
        return
    end
    UI.Confirm({ title = "Buy " .. e.name .. "?",
        text = ("%d × %s for %s."):format(items, e.name, table.concat(costs, ", ")),
        confirm = "Buy", onConfirm = function() self:Buy(e, items) end })
end

--------------------------------------------------------------------------------
-- The window
--------------------------------------------------------------------------------

local function slotTooltip(b)
    if not b.index then return end
    GameTooltip:SetOwner(b, "ANCHOR_RIGHT")
    if b.buyback then GameTooltip:SetBuybackItem(b.index) else GameTooltip:SetMerchantItem(b.index) end
    GameTooltip:Show()
end

local function buildRow(parent)
    local r = CreateFrame("Frame", nil, parent)
    r:SetHeight(ROW_H)
    r.rule = UI.Fill(r, "gilt-faint", "ARTWORK")
    r.rule:SetPoint("BOTTOMLEFT")
    r.rule:SetPoint("BOTTOMRIGHT")
    r.rule:SetHeight(1)
    r.slot = UI.ItemSlot(r)
    r.slot:SetPoint("LEFT", 0, 0)
    r.slot:SetScript("OnEnter", slotTooltip)
    r.slot:SetScript("OnLeave", function() GameTooltip:Hide() end)
    r.slot:SetScript("OnClick", function(b) if b.link then HandleModifiedItemClick(b.link) end end)
    r.tint = r.slot:CreateTexture(nil, "OVERLAY")
    r.tint:SetPoint("TOPLEFT", 1, -1)
    r.tint:SetPoint("BOTTOMRIGHT", -1, 1)
    r.tint:SetColorTexture(0.9, 0, 0, 0.45)
    r.buy = UI.Button(r, { text = "Buy", width = 64 })
    r.buy:SetPoint("RIGHT", 0, 0)
    r.qty = UI.TextField(r, { width = 52 })
    r.qty:SetPoint("RIGHT", r.buy, "LEFT", -S["space-2"], 0)
    r.qty.edit:SetNumeric(true)
    r.qty.edit:SetMaxLetters(4)
    r.name = UI.Text(r, "label", "ink")
    r.name:SetPoint("TOPLEFT", r.slot, "TOPRIGHT", S["space-4"], 1)
    r.name:SetPoint("RIGHT", r.qty, "LEFT", -S["space-4"], 0)
    r.name:SetWordWrap(false)
    r.money = UI.Money(r)
    r.money:SetPoint("TOPLEFT", r.name, "BOTTOMLEFT", 0, -4)
    r.costs = UI.Text(r, "caption", "ink")
    r.costs:SetPoint("TOPLEFT", r.name, "BOTTOMLEFT", 0, -4)
    r.status = UI.Text(r, "caption", "ink-muted")
    r.status:SetWordWrap(false)
    return r
end

-- The line under the name: the price, then what's left, what you have and
-- the quantity's note.
local function drawStatus(r, parts)
    local anchor = r.money:IsShown() and r.money or r.costs
    r.status:ClearAllPoints()
    r.status:SetPoint("LEFT", anchor, "RIGHT", S["space-4"], 0)
    r.status:SetPoint("RIGHT", r.qty, "LEFT", -S["space-4"], 0)
    r.status:SetValue(table.concat(parts, "  ·  "))
end

local function amber(text) return "|cff" .. T.color["amber"].hex .. text .. "|r" end

function M:DrawGoodsRow(r, e)
    r.entry = e
    r.slot.index, r.slot.buyback, r.slot.link = e.index, nil, e.link
    r.slot.skin:SetItem({ icon = e.texture, count = e.stack, quality = e.quality, dim = e.known })
    r.tint:SetShown(not e.known and (not e.usable or not e.purchasable))
    r.name:SetValue(e.name)
    r.name:SetColor(e.known and "ink-faint" or ((e.quality ~= "common") and ("quality-" .. e.quality) or "ink"))
    if e.known then
        r.money:Hide()
        r.costs:Show()
        r.costs:SetValue("|cff" .. T.color["fel"].hex .. "✓ Known|r")
    elseif #e.costs > 0 then
        local parts = {}
        for _, c in ipairs(e.costs) do parts[#parts + 1] = c.value .. " " .. icon(c.texture) end
        if e.price > 0 then parts[#parts + 1] = coins(e.price) end
        r.money:Hide()
        r.costs:Show()
        r.costs:SetValue(table.concat(parts, "  "))
    else
        r.costs:Hide()
        r.money:Show()
        r.money:SetCopper(e.price)
    end
    r.qty:SetShown(not e.known)
    -- the quantity typed for this item at this vendor, else one purchase
    local key = e.link or e.name
    if r.qtyFor ~= key or not r.qty.edit:HasFocus() then
        r.qty:SetValue(tostring(self.qty[key] or e.stack))
    end
    r.qtyFor = key
    local function refreshNote()
        local qty = tonumber(r.qty.edit:GetText()) or e.stack
        if qty ~= e.stack then self.qty[key] = qty else self.qty[key] = nil end
        local purchases, _, note = plan(e, qty)
        local parts = {}
        if e.stock >= 0 then parts[#parts + 1] = amber(e.stock .. " left") end
        if e.have > 0 then parts[#parts + 1] = "You have " .. e.have end
        if note and not e.known then parts[#parts + 1] = note:find("^Capped") and amber(note) or note end
        drawStatus(r, parts)
        r.qty.border:SetColor(note and note:find("^Capped") and "gilt" or "gilt-line")
        r.buy:SetEnabledState(not e.known and purchases > 0 and e.purchasable)
    end
    r.qty.onTextChanged = refreshNote
    r.qty.onChange = refreshNote
    refreshNote()
    r.buy:SetLabel("Buy")
    r.buy:SetScript("OnClick", function()
        local qty = tonumber(r.qty.edit:GetText()) or e.stack
        local purchases, items = plan(e, qty)
        if purchases > 0 then self:ConfirmBuy(e, purchases, items) end
    end)
end

function M:DrawBuybackRow(r, i, undo)
    local name, texture, price, quantity, _, usable = call(GetBuybackItemInfo, i)
    local link = call(GetBuybackItemLink, i)
    local quality = link and select(3, call(C_Item.GetItemInfo, link))
    r.entry = nil
    r.slot.index, r.slot.buyback, r.slot.link = i, true, link
    r.slot.skin:SetItem({ icon = texture, count = quantity, quality = QUALITY[quality or 1] or "common" })
    r.tint:SetShown(usable == false)
    r.name:SetValue(name or "?")
    r.name:SetColor((quality and quality ~= 1) and ("quality-" .. (QUALITY[quality] or "common")) or "ink")
    r.costs:Hide()
    r.money:Show()
    r.money:SetCopper(price or 0)
    r.qty:Hide()
    drawStatus(r, {})
    r.buy:SetLabel(undo and "Undo" or "Buy back")
    r.buy:SetEnabledState((GetMoney() or 0) >= (price or 0))
    r.buy:SetScript("OnClick", function() BuybackItem(i) end)
end

function M:Build()
    local w = UI.WindowFrame(SuuUI.Root, { name = "SuuUIMerchantWindow", title = "Merchant", width = WIDTH, height = HEIGHT,
        footer = true, onClose = function(win) win:Hide() end,
        tabs = { { key = "buy", label = "Merchant" }, { key = "buyback", label = "Buy back" } },
        onTab = function(key)
            self.tab = key
            if self.list then self.list:SetVerticalScroll(0) end
            self:Refresh()
        end })
    w:SetPoint("TOPLEFT", UIParent, "TOPLEFT", 16, -116)
    w:Hide()
    w:HookScript("OnHide", function()
        if self.open then CloseMerchant() end
    end)
    self.window = w
    -- the tools stay on top; only the list under them scrolls (with a bar)
    w.scroll:Hide()
    local tools = CreateFrame("Frame", nil, w.body)
    tools:SetPoint("TOPLEFT")
    tools:SetPoint("TOPRIGHT")
    tools:SetHeight(30)
    self.tools = tools
    local BAR = S["space-3"]
    self.list = UI.ScrollArea(w.body, BAR)
    self.list:SetPoint("BOTTOMLEFT")
    self.list:SetPoint("BOTTOMRIGHT", -(BAR + 3), 0)
    local c = self.list.child
    self.list:HookScript("OnSizeChanged", function(scroll, width) c:SetWidth(width) end)
    self.content = c
    -- the tools: a search over the goods, the game's filter
    self.search = UI.TextField(tools, { width = 240, placeholder = "Search", onTextChanged = function() self:Refresh() end })
    self.search:SetPoint("TOPLEFT")
    local options = {}
    if LE_LOOT_FILTER_ALL then options[#options + 1] = { value = LE_LOOT_FILTER_ALL, label = "All items" } end
    if LE_LOOT_FILTER_CLASS then options[#options + 1] = { value = LE_LOOT_FILTER_CLASS, label = "Your class" } end
    if LE_LOOT_FILTER_BOE then options[#options + 1] = { value = LE_LOOT_FILTER_BOE, label = "Bind on equip" } end
    self.filter = UI.Select(tools, { width = 160, options = options, onChange = function(v)
        call(SetMerchantFilter, v)
        self:Refresh()
    end })
    self.filter:SetPoint("TOPRIGHT")
    self.hasFilter = #options > 0
    self.rows = {}
    -- the item you sold last, with Undo: fixed under the list
    local last = CreateFrame("Frame", nil, w.body)
    last:SetPoint("BOTTOMLEFT")
    last:SetPoint("BOTTOMRIGHT", -(S["space-3"] + 3), 0)
    last:SetHeight(S["space-4"] + T.type.caption.lineHeight + S["space-2"] + ROW_H)
    self.last = last
    self.lastRule = UI.Hairline(last, "gilt-faint")
    self.lastRule:SetPoint("TOPLEFT")
    self.lastRule:SetPoint("TOPRIGHT")
    self.lastLabel = UI.Text(last, "caption", "ink-muted")
    self.lastLabel:SetValue("Last sold")
    self.lastLabel:SetPoint("TOPLEFT", 0, -S["space-4"])
    self.lastRow = buildRow(last)
    self.lastRow:SetPoint("BOTTOMLEFT")
    self.lastRow:SetPoint("BOTTOMRIGHT")
    self.lastRow.rule:Hide()
    last:Hide()
    self.empty = UI.Text(c, "body", "ink-muted")
    -- the foot: repair, guild repair, sell junk; your money at the right
    local f = w.footer
    self.money = UI.Money(f)
    self.money:SetPoint("RIGHT", 0, 0)
    self.repair = UI.Button(f, { text = "Repair all", onClick = function() call(RepairAllItems, false) end })
    self.repair:SetPoint("LEFT", 0, 0)
    self.repairOne = UI.Button(f, { text = "One", width = 52, onClick = function()
        if InRepairMode and InRepairMode() then call(HideRepairCursor) else call(ShowRepairCursor) end
    end, tooltip = { title = "Repair one item", description = "Then click the item: on your character or in your bags." } })
    self.repairOne:SetPoint("LEFT", self.repair, "RIGHT", S["space-2"], 0)
    self.guild = UI.Button(f, { text = "Guild", onClick = function() call(RepairAllItems, true) end })
    self.guild:SetPoint("LEFT", self.repairOne, "RIGHT", S["space-2"], 0)
    self.junk = UI.Button(f, { text = "Sell junk", onClick = function() self:SellJunk() end })
end

-- Keeps n rows in the list, positioned from y; returns them.
function M:Rows(n, y)
    local c = self.content
    for i = 1, math.max(n, #self.rows) do
        local r = self.rows[i]
        if i <= n then
            if not r then
                r = buildRow(c)
                self.rows[i] = r
            end
            r:ClearAllPoints()
            r:SetPoint("TOPLEFT", 0, -(y + (i - 1) * ROW_H))
            r:SetPoint("RIGHT", c, "RIGHT")
            r.rule:Show()
            r:Show()
        elseif r then
            r:Hide()
        end
    end
    return self.rows
end

function M:Refresh()
    local w = self.window
    if not (w and w:IsShown() and self.open) then return end
    local c = self.content
    local name = UnitName("npc")
    w:SetTitle(plain(name) and name or "Merchant")
    local buy = (self.tab or "buy") == "buy"
    self.tools:SetShown(buy)
    self.filter:SetShown(self.hasFilter)
    if buy then self.filter:SetValue(call(GetMerchantFilter)) end
    -- the last sold item under the list (Merchant tab, once you sold one)
    local lastN = call(GetNumBuybackItems) or 0
    local showLast = buy and lastN > 0
    self.last:SetShown(showLast)
    if showLast then self:DrawBuybackRow(self.lastRow, lastN, true) end
    self.list:ClearAllPoints()
    self.list:SetPoint("TOPLEFT", 0, buy and -(30 + S["space-4"]) or 0)
    if showLast then
        self.list:SetPoint("BOTTOMRIGHT", self.last, "TOPRIGHT", 0, S["space-2"])
    else
        self.list:SetPoint("BOTTOMRIGHT", -(S["space-3"] + 3), 0)
    end
    local y = 0
    self.empty:Hide()
    local used = 0
    if buy then
        local query = (self.search.edit:GetText() or ""):lower()
        local list = {}
        for i = 1, (call(GetMerchantNumItems) or 0) do
            local e = self:Item(i)
            if e and (query == "" or e.name:lower():find(query, 1, true)) then list[#list + 1] = e end
        end
        local rows = self:Rows(#list, y)
        for i, e in ipairs(list) do self:DrawGoodsRow(rows[i], e) end
        used = #list
        y = y + used * ROW_H
        if used > 0 then rows[used].rule:Hide() end
        if used == 0 then
            self.empty:ClearAllPoints()
            self.empty:SetPoint("TOPLEFT", 0, -(y + S["space-4"]))
            self.empty:SetValue(query ~= "" and "Nothing here matches." or "This merchant has nothing to sell.")
            self.empty:Show()
            y = y + 40
        end
    else
        local n = call(GetNumBuybackItems) or 0
        local rows = self:Rows(n, y)
        for i = 1, n do self:DrawBuybackRow(rows[i], i) end
        if n > 0 then rows[n].rule:Hide() end
        y = y + n * ROW_H
        if n == 0 then
            self.empty:ClearAllPoints()
            self.empty:SetPoint("TOPLEFT", 0, -S["space-4"])
            self.empty:SetValue("Nothing sold to buy back.")
            self.empty:Show()
            y = 40
        end
    end
    c:SetHeight(math.max(1, y))
    self:RefreshFoot()
end

-- The grey items in your bags and what they fetch.
local function junkSlots()
    local list, copper = {}, 0
    for bag = 0, 4 do
        for slot = 1, (call(C_Container.GetContainerNumSlots, bag) or 0) do
            local info = call(C_Container.GetContainerItemInfo, bag, slot)
            if info and plain(info.quality) and info.quality == 0 and not (plain(info.hasNoValue) and info.hasNoValue)
                and not (plain(info.isLocked) and info.isLocked) then
                local price = plain(info.hyperlink) and select(11, call(C_Item.GetItemInfo, info.hyperlink)) or 0
                list[#list + 1] = { bag = bag, slot = slot }
                copper = copper + (price or 0) * (plain(info.stackCount) and info.stackCount or 1)
            end
        end
    end
    return list, copper
end

-- One grey item a moment until none is left or the merchant closes.
function M:SellJunk()
    if self.selling then return end
    self.selling = C_Timer.NewTicker(0.2, function(ticker)
        local list = junkSlots()
        if not self.open or #list == 0 or InCombatLockdown() then
            ticker:Cancel()
            self.selling = nil
            self:RefreshFoot()
            return
        end
        C_Container.UseContainerItem(list[1].bag, list[1].slot)
    end)
end

function M:RefreshFoot()
    if not self.window then return end
    self.money:SetCopper(GetMoney() or 0)
    local canRepair = call(CanMerchantRepair)
    local cost, needed = call(GetRepairAllCost)
    cost = cost or 0
    self.repair:SetShown(canRepair and true or false)
    self.repairOne:SetShown(canRepair and true or false)
    if canRepair then
        self.repair:SetLabel(cost > 0 and ("Repair all  " .. coins(cost)) or "Repair all")
        self.repair:SetEnabledState(needed and cost > 0 and (GetMoney() or 0) >= cost)
    end
    local guild = canRepair and call(CanGuildBankRepair)
    self.guild:SetShown(guild and true or false)
    if guild then
        local left = call(GetGuildBankWithdrawMoney)
        self.guild.tooltip = { title = "Repair from the guild bank",
            description = left and left >= 0 and ("The guild can still pay " .. coins(left) .. " today.") or nil }
        self.guild:SetEnabledState(needed and cost > 0)
    end
    local list, copper = junkSlots()
    self.junk:SetLabel(#list > 0 and ("Sell junk  " .. coins(copper)) or "Sell junk")
    self.junk:SetEnabledState(#list > 0 and not self.selling)
    self.junk.tooltip = #list == 0 and { title = "Sell junk", description = "No grey items in your bags." } or nil
    self.junk:ClearAllPoints()
    local prev = (guild and self.guild) or (canRepair and self.repairOne) or nil
    if prev then self.junk:SetPoint("LEFT", prev, "RIGHT", S["space-2"], 0) else self.junk:SetPoint("LEFT", 0, 0) end
    -- the merchant's currencies in the header
    local meta = {}
    for _, id in ipairs((C_MerchantFrame.GetMerchantCurrencies and call(C_MerchantFrame.GetMerchantCurrencies)) or {}) do
        local info = call(C_CurrencyInfo.GetCurrencyInfo, id)
        if info and #meta < 6 then meta[#meta + 1] = (info.quantity or 0) .. " " .. icon(info.iconFileID) end
    end
    if self.window.meta then self.window.meta:SetValue(table.concat(meta, "   ")) end
end

-- A burst of updates draws once.
function M:QueueRefresh()
    if self.refreshPending then return end
    self.refreshPending = true
    C_Timer.After(0.05, function()
        self.refreshPending = nil
        self:Refresh()
    end)
end

--------------------------------------------------------------------------------
-- Over the game's merchant frame
--------------------------------------------------------------------------------

-- The game's frame out of sight: see-through and off screen, still shown,
-- and back off screen whenever the game places it again.
function M:Away(frame)
    if not frame or self.away then return end
    self.away = true
    local placing = false
    local function away()
        if not self:IsEnabled() then return end
        placing = true
        frame:SetAlpha(0)
        frame:ClearAllPoints()
        frame:SetPoint("TOPLEFT", UIParent, "TOPRIGHT", 5000, 0)
        placing = false
    end
    away()
    hooksecurefunc(frame, "SetPoint", function() if not placing then C_Timer.After(0, away) end end)
    frame:HookScript("OnShow", function() C_Timer.After(0, away) end)
end

function M:OnEnable()
    self.qty = {}
    if not self.window then self:Build() end
    self:OnGameEvent("MERCHANT_SHOW", function()
        self.open = true
        self.qty = {} -- quantities start over at every vendor
        self:Away(MerchantFrame)
        call(ResetSetMerchantFilter)
        self.search:SetValue("")
        self.window:Show()
        self.window:SetTab("buy")
    end)
    self:OnGameEvent("MERCHANT_CLOSED", function()
        self.open = false
        if InRepairMode and InRepairMode() then HideRepairCursor() end
        self.window:Hide()
    end)
    for _, e in ipairs({ "MERCHANT_UPDATE", "MERCHANT_FILTER_ITEM_UPDATE", "BAG_UPDATE_DELAYED", "GET_ITEM_INFO_RECEIVED",
                         "UPDATE_INVENTORY_DURABILITY", "CURRENCY_DISPLAY_UPDATE" }) do
        self:OnGameEvent(e, function() self:QueueRefresh() end)
    end
    self:OnGameEvent("PLAYER_MONEY", function() self:QueueRefresh() end)
end

function M:OnDisable()
    if self.window then self.window:Hide() end
end
