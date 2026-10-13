-- Units/Bags.lua
-- Your bags (step 2.5a, design board "Bags"): one window, every bag's slots
-- in one grid (backpack, bags 1-4, the reagent bag; the keyring if you want
-- it), "18 free of 80", search (the game's own item search) and Blizzard's
-- sort, your money in the foot. It opens and closes with Blizzard's bags
-- (B, the bag buttons, the mailbox, a vendor, the bank): Blizzard's bag
-- frames still open and close, under a hidden parent, and SuuUI's window
-- follows them. Bottom right, movable in edit mode.
--
-- The bank (step 2.5b, boards "Bank" and "At the bank"): the same window
-- with every purchased bank tab's slots, opened at a banker top centre with
-- your bags beside it. Blizzard's bank frame opens and closes as always,
-- off screen; SuuUI's window follows BANKFRAME_OPENED/CLOSED.
-- One search runs across both.
--
-- Every character's bags and bank (step 2.5c, board "Bags window"): what
-- each character carries is saved as it changes (the bank while you are at
-- a banker), so the picker in the bags window's header shows another
-- character's bags or bank from anywhere, read only and dated. "All
-- characters" turns the search into a list of everything found on every
-- character, and where. Settings › Bags › Characters forgets one.
--
-- Item counts: an item's tooltip says which of your characters has how
-- many, and where (bags, bank, equipped), from the same saved copies.
--
-- Sell junk: at a vendor, with grey items in your bags, a button in the
-- foot sells them one at a time, each slot read again just before it sells
-- (still grey, still sellable, not locked, the vendor still open).
-- A built-in module written against the public API only.
--
-- The slots are Blizzard's own bag slot buttons (its template), each in a
-- frame whose ID is its bag: clicks, drags, shift-click links, tooltips and
-- using items are Blizzard's code, so they work in combat wherever the game
-- allows it (probed 2026-10-13). SuuUI only draws on them; nothing is
-- written on the buttons.

local UI, T = SuuUI.UI, SuuUI.Tokens

local M = SuuUI.RegisterModule({
    id = "bags",
    name = "Bags",
    description = "SuuUI's bags: every bag in one window with search, sort and your money.",
    api = "0.12",
    reloadToToggle = true,
    defaults = {
        position = { point = "BOTTOMRIGHT", x = -28, y = 96 },
        columns = 10,
        reagentBag = true,
        keyring = false,
        bank = true,
        itemCounts = true,
        bankPosition = { point = "TOP", x = -216, y = -240 },
    },
})

local isSecret = issecretvalue or function() return false end
local function plain(v) return v ~= nil and not isSecret(v) end
local QUALITY = { [0] = "poor", "common", "uncommon", "rare", "epic", "legendary", "legendary", "legendary" }
local KEYRING = -1
local REAGENT = 5
local BANK_FIRST = (Enum.BagIndex and Enum.BagIndex.CharacterBankTab_1) or 6
local BANK_LAST = (Enum.BagIndex and Enum.BagIndex.CharacterBankTab_9) or 14
local BANK_TYPE = Enum.BankType and Enum.BankType.Character
local S = T.space

local function isBank(bag) return bag >= BANK_FIRST and bag <= BANK_LAST end

-- The bags shown, in order.
function M:Bags()
    local list = { 0, 1, 2, 3, 4 }
    if self:Get("reagentBag") then list[#list + 1] = REAGENT end
    if self:Get("keyring") then list[#list + 1] = KEYRING end
    return list
end

local function numSlots(bag)
    local n = C_Container.GetContainerNumSlots(bag)
    return (plain(n) and n) or 0
end

-- The bank tabs you own, in order (the game's list; else every tab with slots).
function M:BankBags()
    local list = {}
    if BANK_TYPE and C_Bank and C_Bank.FetchPurchasedBankTabIDs then
        local ok, ids = pcall(C_Bank.FetchPurchasedBankTabIDs, BANK_TYPE)
        if ok and type(ids) == "table" then
            for _, id in ipairs(ids) do
                if plain(id) and isBank(id) then list[#list + 1] = id end
            end
        end
    end
    if #list == 0 then
        for bag = BANK_FIRST, BANK_LAST do
            if numSlots(bag) > 0 then list[#list + 1] = bag end
        end
    end
    return list
end

-- The window a bag's slots are in (nil: neither shows it).
function M:InvFor(bag)
    if isBank(bag) then return self.bank end
    return self.inv
end

--------------------------------------------------------------------------------
-- Slots
--------------------------------------------------------------------------------

-- A bag's frame: its ID is the bag (Blizzard's slot buttons read it).
function M:BagFrame(bag)
    local f = self.bagFrames[bag]
    if f then return f end
    f = CreateFrame("Frame", nil, self:InvFor(bag).grid)
    f:SetID(bag)
    f:SetSize(1, 1)
    f:SetPoint("TOPLEFT")
    self.bagFrames[bag] = f
    return f
end

function M:SlotButton(bag, slot)
    self.buttons[bag] = self.buttons[bag] or {}
    local b = self.buttons[bag][slot]
    if b then return b end
    local name = isBank(bag) and ("SuuUIBank%dSlot%d"):format(bag - BANK_FIRST + 1, slot)
        or ("SuuUIBag%dSlot%d"):format(bag + 2, slot)
    b = CreateFrame("ItemButton", name, self:BagFrame(bag), "ContainerFrameItemButtonTemplate")
    b:SetID(slot)
    self.skins[b] = UI.SkinItemSlot(b)
    self.buttons[bag][slot] = b
    return b
end

local function cooldownOf(b)
    return b.Cooldown or (b:GetName() and _G[b:GetName() .. "Cooldown"])
end

function M:UpdateSlot(bag, slot)
    local b = self.buttons[bag] and self.buttons[bag][slot]
    if not b then return end
    local info = C_Container.GetContainerItemInfo(bag, slot)
    local skin = self.skins[b]
    if info and plain(info.iconFileID) then
        skin:SetItem({
            icon = info.iconFileID,
            count = plain(info.stackCount) and info.stackCount or 1,
            quality = plain(info.quality) and QUALITY[info.quality] or "common",
            dim = plain(info.isFiltered) and info.isFiltered or false,
            locked = plain(info.isLocked) and info.isLocked or false,
        })
    else
        skin:SetItem(nil)
    end
    local cd = cooldownOf(b)
    if cd then
        local ok, start, duration, enable = pcall(C_Container.GetContainerItemCooldown, bag, slot)
        if ok and plain(duration) and duration and duration > 0 and enable ~= 0 and enable ~= false then
            pcall(cd.SetCooldown, cd, start, duration)
        else
            cd:Clear()
        end
    end
end

function M:UpdateBag(bag)
    for slot = 1, numSlots(bag) do self:UpdateSlot(bag, slot) end
end

-- Every slot of every bag a shown window holds.
function M:UpdateShown()
    if self.inv and self.inv:IsShown() then
        for _, bag in ipairs(self:Bags()) do self:UpdateBag(bag) end
    end
    if self.bank and self.bank:IsShown() then
        for _, bag in ipairs(self:BankBags()) do self:UpdateBag(bag) end
    end
end

-- One window's slots laid out in order: returns its slot count and free count.
function M:Fill(inv, bags)
    local list, shown = {}, {}
    local total, free = 0, 0
    for _, bag in ipairs(bags) do
        shown[bag] = true
        local n = numSlots(bag)
        for slot = 1, n do
            list[#list + 1] = self:SlotButton(bag, slot)
            self:UpdateSlot(bag, slot)
        end
        -- hide what the bag no longer has
        for slot = n + 1, #(self.buttons[bag] or {}) do self.buttons[bag][slot]:Hide() end
        if bag ~= REAGENT and bag ~= KEYRING then
            total = total + n
            local f = C_Container.GetContainerNumFreeSlots(bag)
            if plain(f) and f then free = free + f end
        end
    end
    for bag, slots in pairs(self.buttons) do
        if not shown[bag] and self:InvFor(bag) == inv then
            for _, b in ipairs(slots) do b:Hide() end
        end
    end
    inv:LayoutSlots(list)
    inv:SetMeta(("%d free of %d"):format(free, total))
    return total, free
end

-- Every slot laid out again (bags or sizes changed), the counts, the money.
function M:Rebuild()
    if not (self.inv and self:IsLive()) then return end
    self:Fill(self.inv, self:Bags())
    self:Foot()
end

function M:RebuildBank()
    if not (self.bank and self.bank:IsShown()) then return end
    local tabs = self:BankBags()
    local total = self:Fill(self.bank, tabs)
    self.bank:SetNote(("%s · %d slots"):format(#tabs > 1 and (#tabs .. " tabs") or "Bank", total))
end

--------------------------------------------------------------------------------
-- Every character's bags and bank
--------------------------------------------------------------------------------

local DIAMOND = "Interface\\AddOns\\SuuUI\\Media\\Textures\\ChatDiamond.tga"

local function thousands(n)
    local s = tostring(n)
    while true do
        local k
        s, k = s:gsub("^(%d+)(%d%d%d)", "%1,%2")
        if k == 0 then break end
    end
    return s
end

-- "just now", "12 min ago", "3 hours ago", "yesterday", "9 days ago"
local function ago(t)
    if type(t) ~= "number" then return "a while ago" end
    local s = math.max(0, time() - t)
    if s < 60 then return "just now" end
    if s < 3600 then return ("%d min ago"):format(s / 60) end
    if s < 86400 then
        local h = math.floor(s / 3600)
        return h == 1 and "an hour ago" or ("%d hours ago"):format(h)
    end
    local d = math.floor(s / 86400)
    return d == 1 and "yesterday" or ("%d days ago"):format(d)
end

local function nameOf(link)
    return type(link) == "string" and link:match("%[(.-)%]") or nil
end

local function itemTip(owner, link, extra)
    local ref = type(link) == "string" and (link:match("|H(item:[^|]+)|h") or (link:match("^item:") and link))
    if not ref then return end
    GameTooltip:SetOwner(owner, "ANCHOR_RIGHT")
    GameTooltip:SetHyperlink(ref)
    if extra then
        GameTooltip:AddLine(" ")
        for _, line in ipairs(extra) do GameTooltip:AddLine(line, 0.85, 0.82, 0.76) end
    end
    GameTooltip:Show()
end

local function classDiamond(class)
    local c = class and T.color["class-" .. class:lower()]
    if not c then return "" end
    return ("|T%s:0:0:0:0:32:32:0:32:0:32:%d:%d:%d|t "):format(DIAMOND, c[1] * 255, c[2] * 255, c[3] * 255)
end

-- What the listed bags hold now: { slots = { {t, c, q, l} or false … }, size, free, seen }.
local function snapshot(bags)
    local slots, size, free = {}, 0, 0
    for _, bag in ipairs(bags) do
        local n = numSlots(bag)
        for slot = 1, n do
            local info = C_Container.GetContainerItemInfo(bag, slot)
            local e = false
            if info and plain(info.iconFileID) and info.iconFileID then
                e = { t = info.iconFileID, c = plain(info.stackCount) and info.stackCount or 1,
                      q = plain(info.quality) and info.quality or 1, l = plain(info.hyperlink) and info.hyperlink or nil }
            end
            slots[#slots + 1] = e
        end
        if bag ~= REAGENT and bag ~= KEYRING then
            size = size + n
            local f = C_Container.GetContainerNumFreeSlots(bag)
            if plain(f) and f then free = free + f end
        end
    end
    return { slots = slots, size = size, free = free, seen = time() }
end

-- This character's entry: who, money, bags (and the bank while at a banker).
-- An empty read (bags not in yet at login) never replaces a saved one.
function M:SaveMe()
    local d = self:CharData()
    d.name, d.realm = UnitName("player"), GetRealmName()
    d.class, d.level = select(2, UnitClass("player")), UnitLevel("player")
    d.money, d.seen = GetMoney(), time()
    local bags = snapshot(self:Bags())
    if bags.size > 0 then d.bags = bags end
    if self.atBank then
        local bank = snapshot(self:BankBags())
        if bank.size > 0 then d.bank = bank end
    end
    -- what you wear: item links by slot (head 1 … tabard 19)
    local worn = {}
    for slot = 1, 19 do
        local link = GetInventoryItemLink("player", slot)
        if plain(link) and link then worn[#worn + 1] = link end
    end
    d.equipped = worn
end

function M:QueueSave()
    if self.saveTimer then return end
    self.saveTimer = C_Timer.NewTimer(1, function()
        self.saveTimer = nil
        if self:IsEnabled() then self:SaveMe() end
    end)
end

-- Saved characters, you first, then by name: { key, d, me }.
function M:Characters()
    local me, list = self:CharKey(), {}
    for key, d in pairs(self:AllCharData()) do
        if key == me or d.bags then list[#list + 1] = { key = key, d = d, me = key == me } end
    end
    table.sort(list, function(a, b)
        if a.me ~= b.me then return a.me end
        return (a.d.name or a.key) < (b.d.name or b.key)
    end)
    return list
end

local function label(c, myRealm)
    local name = c.d.name or c.key
    if c.d.realm and c.d.realm ~= myRealm then name = name .. "-" .. c.d.realm end
    return c.d.level and (name .. " · " .. c.d.level) or name
end

function M:UpdatePicker()
    local inv = self.inv
    if not inv.who then return end
    local opts, myRealm = {}, GetRealmName()
    for _, c in ipairs(self:Characters()) do
        opts[#opts + 1] = { value = c.key, label = label(c, myRealm), note = c.me and "you" or ago(c.d.seen) }
    end
    inv.who:SetOptions(opts)
    inv.who:SetValue(self.who or self:CharKey())
    inv.view:SetValue(self.view or "bags")
end

function M:ShowingResults()
    return self.inv.all and self.inv.all.value and (self.query or "") ~= ""
end

-- Your own bags: Blizzard's live slots. Anything else is a saved copy.
function M:IsLive()
    if not self.inv then return false end
    local who = self.who or self:CharKey()
    return who == self:CharKey() and (self.view or "bags") == "bags" and not self:ShowingResults()
end

-- A saved slot: SuuUI's own, read only; its tooltip from the item's link,
-- shift-click links it.
function M:SavedSlot(i)
    local b = self.savedSlots[i]
    if b then return b end
    b = UI.ItemSlot(self.inv.grid)
    b:SetScript("OnEnter", function(slot) itemTip(slot, slot.link) end)
    b:SetScript("OnLeave", function() GameTooltip:Hide() end)
    b:SetScript("OnClick", function(slot)
        if slot.link and IsModifiedClick() and HandleModifiedItemClick then HandleModifiedItemClick(slot.link) end
    end)
    self.savedSlots[i] = b
    return b
end

function M:HideSaved()
    for _, b in ipairs(self.savedSlots) do b:Hide() end
end

function M:ShowSaved()
    local inv, me = self.inv, self:CharKey()
    local who, view = self.who or me, self.view or "bags"
    local d = self:AllCharData()[who]
    local box = d and d[view]
    local q = (self.query or ""):lower()
    local list = {}
    for i, e in ipairs(box and box.slots or {}) do
        local b = self:SavedSlot(i)
        b.link = e and e.l or nil
        if e then
            local name = nameOf(e.l)
            b.skin:SetItem({ icon = e.t, count = e.c, quality = QUALITY[e.q] or "common",
                dim = q ~= "" and not (name and name:lower():find(q, 1, true)) })
        else
            b.skin:SetItem(nil)
        end
        list[i] = b
    end
    for i = #list + 1, #self.savedSlots do self.savedSlots[i]:Hide() end
    inv:LayoutSlots(list)
    inv:SetMeta(box and ("%d free of %d"):format(box.free or 0, box.size or 0) or "")
    local where = view == "bank" and "bank" or "bags"
    local banner
    if who == me then
        banner = box and ("Your bank as of your last visit (%s) · read only"):format(ago(box.seen))
            or "Your bank shows here once you have visited a banker"
    else
        local name = d and d.name or who
        banner = box and ("%s's %s as of %s · read only"):format(name, where, ago(box.seen or d.seen))
            or ("%s's %s show here once %s has opened them"):format(name, where, name)
    end
    inv:SetBanner(banner)
end

-- "All characters": every item whose name holds the search, on every
-- character's bags and bank, most first.
function M:ShowResults()
    local inv, me = self.inv, self:CharKey()
    self:SaveMe()
    local q = (self.query or ""):lower()
    local found, order = {}, {}
    for _, c in ipairs(self:Characters()) do
        for _, where in ipairs({ "bags", "bank" }) do
            local box = c.d[where]
            for _, e in ipairs(box and box.slots or {}) do
                local name = e and nameOf(e.l)
                if name and name:lower():find(q, 1, true) then
                    local id = e.l:match("item:(%d+)") or name
                    local r = found[id]
                    if not r then
                        r = { icon = e.t, quality = QUALITY[e.q] or "common", label = name, link = e.l, count = 0, at = {} }
                        found[id] = r
                        order[#order + 1] = r
                    end
                    r.count = r.count + (e.c or 1)
                    local at = r.at[#r.at]
                    if not (at and at.c == c and at.where == where) then
                        at = { c = c, where = where, count = 0 }
                        r.at[#r.at + 1] = at
                    end
                    at.count = at.count + (e.c or 1)
                end
            end
        end
    end
    table.sort(order, function(a, b)
        if a.count ~= b.count then return a.count > b.count end
        return a.label < b.label
    end)
    for _, r in ipairs(order) do
        local parts, lines = {}, {}
        for _, at in ipairs(r.at) do
            local text = ("%s · %s ×%d"):format(at.c.d.name or at.c.key, at.where == "bank" and "Bank" or "Bags", at.count)
            parts[#parts + 1] = classDiamond(at.c.d.class) .. text
            lines[#lines + 1] = text
        end
        r.places = table.concat(parts, "   ")
        r.lines = lines
    end
    self.more = inv:SetResults(order)
    for _, row in ipairs(inv.resultRows) do
        row:EnableMouse(true)
        row.onEnter = function(rowFrame) if rowFrame.item then itemTip(rowFrame, rowFrame.item.link, rowFrame.item.lines) end end
        row.onLeave = function() GameTooltip:Hide() end
    end
    inv:SetMeta(#order == 1 and "1 item" or ("%d items"):format(#order))
    inv:SetBanner(nil)
end

-- The foot: the reagent bag on your own bags, else every character's gold;
-- the money of whoever is shown.
function M:Foot()
    local inv, me = self.inv, self:CharKey()
    local who = self.who or me
    local chars, gold, money = self:Characters(), 0, nil
    for _, c in ipairs(chars) do
        local m = c.me and GetMoney() or c.d.money or 0
        gold = gold + math.floor(m / 10000)
        if c.key == who then money = m end
    end
    local note
    if self:ShowingResults() and (self.more or 0) > 0 then
        note = ("%d more: narrow the search"):format(self.more)
    elseif self:IsLive() and self:Get("reagentBag") and numSlots(REAGENT) > 0 then
        local f = C_Container.GetContainerNumFreeSlots(REAGENT)
        note = ("Reagent bag: %d free"):format(plain(f) and f or 0)
    elseif #chars > 1 then
        note = ("%d characters · %sg in all"):format(#chars, thousands(gold))
    end
    inv:SetNote(note)
    inv:SetMoney(money)
end

--------------------------------------------------------------------------------
-- Item counts in tooltips
--------------------------------------------------------------------------------

local WHERE = { { key = "bags", label = "Bags" }, { key = "bank", label = "Bank" }, { key = "equipped", label = "Equipped" } }

-- How many of item `id` each saved character has: { { c, total, bags, bank, equipped } } in picker order.
function M:CountsFor(id)
    local out = {}
    local key = tostring(id)
    for _, c in ipairs(self:Characters()) do
        local n = { c = c, total = 0, bags = 0, bank = 0, equipped = 0 }
        for _, where in ipairs({ "bags", "bank" }) do
            local box = c.d[where]
            for _, e in ipairs(box and box.slots or {}) do
                if e and e.l and e.l:match("item:(%d+)") == key then
                    n[where] = n[where] + (e.c or 1)
                end
            end
        end
        for _, link in ipairs(c.d.equipped or {}) do
            if link:match("item:(%d+)") == key then n.equipped = n.equipped + 1 end
        end
        n.total = n.bags + n.bank + n.equipped
        if n.total > 0 then out[#out + 1] = n end
    end
    return out
end

function M:AddCounts(tooltip, data)
    if not self:Get("itemCounts") then return end
    local id = data and data.id
    if not plain(id) or type(id) ~= "number" then return end
    local counts = self:CountsFor(id)
    if #counts == 0 then return end
    -- only you, only in your bags: you're looking at them already
    if #counts == 1 and counts[1].c.me and counts[1].bags == counts[1].total then return end
    local muted, gilt = T.color["ink-muted"], T.color["gilt-text"]
    tooltip:AddLine(" ")
    local all = 0
    for _, n in ipairs(counts) do
        local parts = {}
        for _, w in ipairs(WHERE) do
            if n[w.key] > 0 then parts[#parts + 1] = w.label .. " " .. n[w.key] end
        end
        local class = n.c.d.class and T.color["class-" .. n.c.d.class:lower()]
        local name = n.c.d.name or n.c.key
        if n.c.d.realm and n.c.d.realm ~= GetRealmName() then name = name .. "-" .. n.c.d.realm end
        local left = classDiamond(n.c.d.class) .. (class and ("|cff" .. class.hex .. name .. "|r") or name)
        tooltip:AddDoubleLine(left, table.concat(parts, " · "), 1, 1, 1, muted[1], muted[2], muted[3])
        all = all + n.total
    end
    if #counts > 1 then
        tooltip:AddDoubleLine("Total", tostring(all), gilt[1], gilt[2], gilt[3], gilt[1], gilt[2], gilt[3])
    end
    tooltip:Show() -- fit the new lines
end

--------------------------------------------------------------------------------
-- Sell junk
--------------------------------------------------------------------------------

-- A grey item the vendor will buy: its sell price per item, or nil.
local function junkAt(bag, slot)
    local info = C_Container.GetContainerItemInfo(bag, slot)
    if not (info and plain(info.quality) and info.quality == 0) then return nil end
    if plain(info.hasNoValue) and info.hasNoValue then return nil end
    if plain(info.isLocked) and info.isLocked then return nil end
    local price = 0
    if info.hyperlink and plain(info.hyperlink) then
        local get = (C_Item and C_Item.GetItemInfo) or GetItemInfo
        price = select(11, get(info.hyperlink)) or 0
    end
    return price, plain(info.stackCount) and info.stackCount or 1
end

-- The grey items in your bags and what they fetch.
function M:Junk()
    local n, copper = 0, 0
    for _, bag in ipairs(self:Bags()) do
        if bag ~= KEYRING then
            for slot = 1, numSlots(bag) do
                local price, count = junkAt(bag, slot)
                if price then n, copper = n + 1, copper + price * count end
            end
        end
    end
    return n, copper
end

local function coins(copper)
    local g, s, c = math.floor(copper / 10000), math.floor(copper / 100) % 100, copper % 100
    if g > 0 then return ("%dg %ds"):format(g, s) end
    if s > 0 then return ("%ds %dc"):format(s, c) end
    return ("%dc"):format(c)
end

-- One grey item a tick until none is left or the vendor closes.
function M:SellJunk()
    if self.selling then return end
    self.selling = C_Timer.NewTicker(0.2, function(ticker)
        local sold = false
        if self.atMerchant and not InCombatLockdown() then
            for _, bag in ipairs(self:Bags()) do
                if bag ~= KEYRING then
                    for slot = 1, numSlots(bag) do
                        if junkAt(bag, slot) then
                            C_Container.UseContainerItem(bag, slot)
                            sold = true
                            break
                        end
                    end
                end
                if sold then break end
            end
        end
        if not sold then
            ticker:Cancel()
            self.selling = nil
            self:UpdateJunk()
        end
    end)
end

-- The Sell junk button: at a vendor with something grey to sell.
function M:UpdateJunk()
    if not self.inv then return end
    local n, copper = 0, 0
    if self.atMerchant and self:IsLive() then n, copper = self:Junk() end
    if n > 0 then
        self.inv:SetAction({ text = "Sell junk", onClick = function() self:SellJunk() end,
            tooltip = { title = "Sell junk", description = ("Sells your %d grey item%s for %s. Each is checked again just before it sells."):format(n, n == 1 and "" or "s", coins(copper)) } })
    else
        self.inv:SetAction(nil)
    end
end

-- A refresh a moment after the typing stops (and after the game's own item
-- search has run).
function M:QueueRefresh()
    if self.refreshTimer then self.refreshTimer:Cancel() end
    self.refreshTimer = C_Timer.NewTimer(0.15, function()
        self.refreshTimer = nil
        if self:IsEnabled() then self:Guard(self.Refresh)(self) end
    end)
end

-- The window as the picker, Bags/Bank, All characters and the search say.
function M:Refresh()
    local inv = self.inv
    if not (inv and inv:IsShown()) then return end
    local live = self:IsLive()
    for bag, f in pairs(self.bagFrames) do
        if not isBank(bag) then f:SetShown(live) end
    end
    inv.sort:SetEnabled(live)
    self.more = nil
    if self:ShowingResults() then
        self:HideSaved()
        self:ShowResults()
    elseif live then
        self:HideSaved()
        inv:SetResults(nil)
        inv:SetBanner(nil)
        self:Rebuild()
    else
        inv:SetResults(nil)
        self:ShowSaved()
    end
    self:Foot()
    self:UpdateJunk()
end

--------------------------------------------------------------------------------
-- Opening with Blizzard's bags
--------------------------------------------------------------------------------

local hidden = CreateFrame("Frame")
hidden:Hide()

-- A Blizzard frame under the hidden parent, kept there (if Blizzard moves it
-- again) while keep() says so.
function M:KeepHidden(f, keep)
    if f:GetParent() ~= hidden then f:SetParent(hidden) end
    if self.parentHooked[f] then return end
    self.parentHooked[f] = true
    hooksecurefunc(f, "SetParent", function(frame, parent)
        if parent ~= hidden and self:IsEnabled() and keep() then
            C_Timer.After(0, function()
                if frame:GetParent() ~= hidden and self:IsEnabled() and keep() then frame:SetParent(hidden) end
            end)
        end
    end)
end

-- Blizzard's bank frame opens and closes as always but out of sight: moved
-- off screen and see-through, not hidden (its OnShow opens your bags, its
-- OnHide ends the visit at the banker, Esc included). The game's panel
-- manager places it again whenever panels change: it goes back off screen
-- a frame later. With the setting off it returns to where Blizzard put it.
function M:HideBlizzardBank()
    local f = _G.BankFrame
    if not f then return end
    local on = self:IsEnabled() and self:Get("bank")
    if not self.bankHooked then
        self.bankHooked = true
        self.bankClamped = f:IsClampedToScreen()
        hooksecurefunc(f, "SetPoint", function(_, ...)
            if self.movingBank then return end
            self.bankPoint = { ... } -- where Blizzard put it
            if self:IsEnabled() and self:Get("bank") then self:QueueBankAway() end
        end)
        f:HookScript("OnShow", function() if self:IsEnabled() and self:Get("bank") then self:BankAway() end end)
    end
    if on then
        self:BankAway()
    else
        f:SetAlpha(1)
        f:SetClampedToScreen(self.bankClamped and true or false)
        if self.bankPoint then
            self.movingBank = true
            f:ClearAllPoints()
            f:SetPoint(unpack(self.bankPoint))
            self.movingBank = false
        end
    end
end

function M:BankAway()
    local f = _G.BankFrame
    f:SetAlpha(0)
    f:SetClampedToScreen(false)
    self.movingBank = true
    f:ClearAllPoints()
    f:SetPoint("BOTTOMRIGHT", UIParent, "TOPLEFT", -200, 200)
    self.movingBank = false
end

function M:QueueBankAway()
    if self.bankAwayQueued then return end
    self.bankAwayQueued = true
    _G.BankFrame:SetAlpha(0)
    C_Timer.After(0, function()
        self.bankAwayQueued = nil
        if self:IsEnabled() and self:Get("bank") then self:BankAway() end
    end)
end

-- Blizzard's bag frames under a hidden parent: they keep opening and
-- closing (so every way of opening bags still works), out of sight.
function M:HideBlizzardBags()
    local names = { "ContainerFrameContainer", "ContainerFrameCombinedBags" }
    for i = 1, (NUM_CONTAINER_FRAMES or 13) do names[#names + 1] = "ContainerFrame" .. i end
    local container = _G.ContainerFrameContainer
    for _, name in ipairs(names) do
        local f = _G[name]
        -- frames inside Blizzard's container go with it
        if f and f ~= container and container and f:GetParent() == container then f = nil end
        if f then self:KeepHidden(f, function() return true end) end
    end
end

local function anyBagOpen()
    if not IsBagOpen then return false end
    for bag = KEYRING, REAGENT do
        if IsBagOpen(bag) then return true end
    end
    return false
end

-- The bags at their place, or beside the bank while it is open.
function M:PlaceBags()
    local inv = self.inv
    inv:ClearAllPoints()
    if self.bank and self.bank:IsShown() then
        inv:SetPoint("TOPLEFT", self.bank, "TOPRIGHT", S["space-5"], 0)
    else
        local pos = self:Get("position")
        inv:SetPoint(pos.point or "CENTER", SuuUI.Root, pos.point or "CENTER", pos.x or 0, pos.y or 0)
    end
end

function M:Sync()
    if not self.inv then return end
    local open = anyBagOpen()
    if open and not self.inv:IsShown() then
        self:PlaceBags()
        self.inv:Show()
        self:UpdatePicker()
        self:Refresh()
    elseif not open and self.inv:IsShown() then
        self.inv:Hide()
    end
end

-- At a banker (BANKFRAME_OPENED) and away again.
function M:ShowBank()
    if not (self.bank and self:Get("bank")) then return end
    self:HideBlizzardBank()
    self.bank:Show()
    self:RebuildBank()
    self:PlaceBags()
end

function M:HideBank()
    if not self.bank or not self.bank:IsShown() then return end
    self.bank:Hide()
    self:PlaceBags()
end

local function closeBank()
    if C_Bank and C_Bank.CloseBankFrame then C_Bank.CloseBankFrame()
    elseif CloseBankFrame then CloseBankFrame() end
end

local function sortBank()
    if not C_Container.SortBank then return end
    if not (BANK_TYPE and pcall(C_Container.SortBank, BANK_TYPE)) then pcall(C_Container.SortBank) end
end

function M:QueueSync()
    if self.syncQueued then return end
    self.syncQueued = true
    C_Timer.After(0, function()
        self.syncQueued = nil
        if self:IsEnabled() then self:Sync() end
    end)
end

--------------------------------------------------------------------------------
-- Settings
--------------------------------------------------------------------------------

local PREVIEW_ITEMS = {
    { icon = 134414 }, { icon = 132796, count = 5 }, { icon = 132889, count = 20 }, { icon = 135232, count = 6 },
    { icon = 134566, count = 14 }, { icon = 134074, count = 2, quality = "uncommon" }, { icon = 134939, quality = "rare" },
    { icon = 135637, quality = "poor" }, { icon = 134075, quality = "uncommon" }, { icon = 134173 },
    { icon = 133972, count = 12 }, { icon = 134937, quality = "epic" },
}

function M:PreviewView(parent)
    if not self.preview then
        local inv = UI.Inventory(parent, { title = "Bags", columns = self:Get("columns"), characters = true })
        inv.onClose = function() end
        inv.who:SetOptions({ { value = 1, label = (UnitName("player") or "You") .. " · " .. (UnitLevel("player") or 1) } })
        inv.who:SetValue(1)
        local slots = {}
        for i = 1, 40 do
            local b = UI.ItemSlot(inv.grid)
            b.skin:SetItem(PREVIEW_ITEMS[i])
            slots[i] = b
        end
        inv.previewSlots = slots
        inv:LayoutSlots(slots)
        inv:SetMeta("28 free of 40")
        inv:SetNote("3 characters · 2,112g in all")
        inv:SetMoney(12043709)
        self.preview = inv
    end
    self.preview:SetParent(parent)
    return self.preview
end

-- A saved character to forget, and the button (click it twice).
function M:ForgetRow(parent)
    local f = CreateFrame("Frame", nil, parent)
    local choice, timer
    local function options()
        local out, myRealm = {}, GetRealmName()
        for _, c in ipairs(self:Characters()) do
            if not c.me then out[#out + 1] = { value = c.key, label = label(c, myRealm), note = ago(c.d.seen) } end
        end
        return out
    end
    f.select = UI.Select(f, { width = 190, placeholder = "Choose a character", options = options(),
        onChange = function(v) choice = v end })
    f.select:SetPoint("LEFT")
    f.button = UI.Button(f, { text = "Forget", onClick = function(b)
        if not choice then return end
        if not timer then
            b:SetLabel("Click again")
            timer = C_Timer.NewTimer(3, function() timer = nil; b:SetLabel("Forget") end)
            return
        end
        timer:Cancel()
        timer = nil
        b:SetLabel("Forget")
        self:ForgetCharData(choice)
        choice = nil
        f.select:SetOptions(options())
        f.select:SetValue(nil)
    end })
    f.button:SetPoint("LEFT", f.select, "RIGHT", S["space-3"], 0)
    f:SetSize(190 + S["space-3"] + f.button:GetWidth(), 30)
    f:SetScript("OnShow", function() f.select:SetOptions(options()) end)
    return f
end

local SECTION = {
    id = "bags", label = "Bags", category = "General", order = 20,
    preview = function(parent) return M:PreviewView(parent) end,
    groups = {
        { title = "Bags", description = "Every bag in one window: it opens wherever Blizzard's bags would (B, the bag buttons, the mailbox, a vendor, the bank). Items work as always: right click to use, drag to move, shift-click to link. Move it in edit mode.", rows = {
            { key = "columns", label = "Slots per row", control = "slider", min = 6, max = 16, step = 1 },
            { key = "reagentBag", label = "Reagent bag", control = "toggle", description = "Its slots after your bags'." },
            { key = "keyring", label = "Keyring", control = "toggle", description = "Your keys after everything else." },
        } },
        { title = "Characters", description = "The bags window's header picks a character: their bags or bank as they last were, read only, from anywhere. \"All characters\" searches every character's bags and bank at once. A character's bank shows once they have visited a banker.", rows = {
            { key = "itemCounts", label = "Counts in item tooltips", control = "toggle",
              description = "An item's tooltip lists which of your characters has how many, in their bags, bank or worn." },
            { label = "Forget a character", control = "custom", build = function(p) return M:ForgetRow(p) end,
              description = "Takes their bags and bank out of the picker and the search, until they log in again." },
        } },
        { title = "Bank", description = "At a banker your bank opens in the same window, top centre, your bags beside it. Every bank tab you own in one grid; items move between them as always (right click, drag). One search runs across both. Move it in edit mode.", rows = {
            { key = "bank", label = "SuuUI's bank", control = "toggle", description = "Off: Blizzard's bank window." },
        } },
    },
}

--------------------------------------------------------------------------------
-- Lifecycle
--------------------------------------------------------------------------------

function M:OnEnable()
    if not C_Container then return end
    self.bagFrames = self.bagFrames or {}
    self.buttons = self.buttons or {}
    self.skins = self.skins or {}
    self.parentHooked = self.parentHooked or {}
    if not self.inv then
        self.savedSlots = {}
        self.inv = UI.Inventory(SuuUI.Root, { name = "SuuUIBags", title = "Bags", columns = self:Get("columns"), characters = true })
        self.inv.who.onChange = self:Guard(function(key) self.who = key; self:Refresh() end)
        self.inv.view.onChange = self:Guard(function(v) self.view = v; self:Refresh() end)
        self.inv.all.onChange = self:Guard(function(on)
            self.inv.search.placeholder:SetValue(on and "Search every character" or "Search")
            self:Refresh()
        end)
        -- back to your own bags when it closes
        self.inv:HookScript("OnHide", function()
            self.who, self.view, self.query = nil, "bags", ""
        end)
        self.inv:SetFrameStrata("MEDIUM")
        self.inv:SetToplevel(true)
        self.inv:EnableMouse(true)
        self.inv:Hide()
        self.inv.onClose = function() CloseAllBags() end
        self.inv.suuManagedShow = true -- it follows Blizzard's bags, not edit mode
        self.inv.sort:SetScript("OnClick", function()
            if C_Container.SortBags then pcall(C_Container.SortBags) end
        end)
        self.bank = UI.Inventory(SuuUI.Root, { name = "SuuUIBank", title = "Bank", columns = self:Get("columns"),
            sortTip = "Blizzard's own sort for your bank." })
        self.bank:SetFrameStrata("MEDIUM")
        self.bank:SetToplevel(true)
        self.bank:EnableMouse(true)
        self.bank:Hide()
        self.bank.suuManagedShow = true -- shown at a banker
        self.bank.onClose = closeBank
        self.bank.sort:SetScript("OnClick", sortBank)
        -- one search across both windows; it ends with them
        local function search(from, other)
            from.search.onTextChanged = self:Guard(function(text)
                other.search:SetValue(text or "")
                if C_Container.SetItemSearch then C_Container.SetItemSearch(text or "") end
                local wasLive = self:IsLive()
                self.query = text or ""
                if not (wasLive and self:IsLive()) then self:QueueRefresh() end
            end)
            from:HookScript("OnHide", function()
                if other:IsShown() then return end
                if from.search.edit:GetText() ~= "" or other.search.edit:GetText() ~= "" then
                    from.search:SetValue("")
                    other.search:SetValue("")
                    if C_Container.SetItemSearch then C_Container.SetItemSearch("") end
                end
            end)
        end
        search(self.inv, self.bank)
        search(self.bank, self.inv)
    end
    self:HideBlizzardBags()
    self:HideBlizzardBank()
    self:RegisterMover(self.inv, { key = "position", label = "Bags" })
    self:RegisterMover(self.bank, { key = "bankPosition", label = "Bank" })
    self:RegisterSettings(SECTION)
    self:Watch("columns", function(v)
        self.inv:SetColumns(v)
        self.bank:SetColumns(v)
        self:Refresh()
        self:RebuildBank()
    end)
    self:Watch("bank", function(on)
        self:HideBlizzardBank()
        if not on then self:HideBank() end
    end)
    self:Watch("reagentBag", function() self:Refresh() end)
    self:Watch("keyring", function() self:Refresh() end)
    -- Blizzard opening or closing bags, by any of its ways
    if not self.hooked then
        self.hooked = true
        for _, name in ipairs({ "ToggleAllBags", "OpenAllBags", "CloseAllBags", "ToggleBag", "OpenBag", "CloseBag",
                                "ToggleBackpack", "OpenBackpack", "CloseBackpack" }) do
            if type(_G[name]) == "function" then
                hooksecurefunc(name, function() if self:IsEnabled() then self:QueueSync() end end)
            end
        end
    end
    for _, e in ipairs({ "BAG_OPEN", "BAG_CLOSED" }) do self:OnGameEvent(e, function() self:QueueSync() end) end
    -- what changes in the bags
    self:OnGameEvent("BAG_UPDATE", function(_, bag)
        if not plain(bag) then return end
        local inv = self:InvFor(bag)
        if inv and inv:IsShown() then self:UpdateBag(bag) end
    end)
    for _, e in ipairs({ "BAG_UPDATE_DELAYED", "BAG_CONTAINER_UPDATE", "PLAYER_ENTERING_WORLD" }) do
        self:OnGameEvent(e, function()
            if self.inv:IsShown() then self:Rebuild(); self:UpdateJunk() end
            self:RebuildBank()
            if e ~= "PLAYER_ENTERING_WORLD" then self:QueueSave() end
        end)
    end
    for _, e in ipairs({ "BANK_TABS_CHANGED", "PLAYERBANKSLOTS_CHANGED" }) do
        self:OnGameEvent(e, function() self:RebuildBank() end)
    end
    self:OnGameEvent("BANKFRAME_OPENED", function()
        self.atBank = true
        self:ShowBank()
        self:QueueSave()
    end)
    self:OnGameEvent("BANKFRAME_CLOSED", function()
        if self.atBank then self:SaveMe() end
        self.atBank = false
        self:HideBank()
    end)
    self:OnGameEvent("PLAYER_LEVEL_UP", function() self:QueueSave() end)
    self:OnGameEvent("PLAYER_EQUIPMENT_CHANGED", function() self:QueueSave() end)
    if not self.tipHooked and TooltipDataProcessor and TooltipDataProcessor.AddTooltipPostCall and Enum.TooltipDataType then
        self.tipHooked = true
        TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Item, function(tooltip, data)
            if not self:IsEnabled() then return end
            if tooltip ~= GameTooltip and tooltip ~= ItemRefTooltip then return end
            self:Guard(self.AddCounts)(self, tooltip, data)
        end)
    end
    self:OnGameEvent("MERCHANT_SHOW", function() self.atMerchant = true; self:UpdateJunk() end)
    self:OnGameEvent("MERCHANT_CLOSED", function() self.atMerchant = false; self:UpdateJunk() end)
    self:OnGameEvent("PLAYER_LOGOUT", function() self:SaveMe() end)
    self:OnGameEvent("ITEM_LOCK_CHANGED", function(_, bag, slot)
        if not (plain(bag) and plain(slot) and bag and slot) then return end
        local inv = self:InvFor(bag)
        if inv and inv:IsShown() then self:UpdateSlot(bag, slot) end
    end)
    for _, e in ipairs({ "BAG_UPDATE_COOLDOWN", "INVENTORY_SEARCH_UPDATE" }) do
        self:OnGameEvent(e, function() self:UpdateShown() end)
    end
    self:OnGameEvent("PLAYER_MONEY", function()
        self:CharData().money = GetMoney()
        if self.inv:IsShown() then self:Foot() end
    end)
    self:Sync()
end

function M:OnDisable()
    if self.inv then self.inv:Hide() end
    if self.bank then self.bank:Hide() end
end
