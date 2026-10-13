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
    api = "0.11",
    reloadToToggle = true,
    defaults = {
        position = { point = "BOTTOMRIGHT", x = -28, y = 96 },
        columns = 10,
        reagentBag = true,
        keyring = false,
        bank = true,
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
    if not self.inv then return end
    self:Fill(self.inv, self:Bags())
    local note
    if self:Get("reagentBag") and numSlots(REAGENT) > 0 then
        local f = C_Container.GetContainerNumFreeSlots(REAGENT)
        note = ("Reagent bag: %d free"):format(plain(f) and f or 0)
    end
    self.inv:SetNote(note)
    self.inv:SetMoney(GetMoney())
end

function M:RebuildBank()
    if not (self.bank and self.bank:IsShown()) then return end
    local tabs = self:BankBags()
    local total = self:Fill(self.bank, tabs)
    self.bank:SetNote(("%s · %d slots"):format(#tabs > 1 and (#tabs .. " tabs") or "Bank", total))
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
        self:Rebuild()
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
        local inv = UI.Inventory(parent, { title = "Bags", columns = self:Get("columns") })
        inv.onClose = function() end
        local slots = {}
        for i = 1, 40 do
            local b = UI.ItemSlot(inv.grid)
            b.skin:SetItem(PREVIEW_ITEMS[i])
            slots[i] = b
        end
        inv.previewSlots = slots
        inv:LayoutSlots(slots)
        inv:SetMeta("28 free of 40")
        inv:SetNote("Reagent bag: 6 free")
        inv:SetMoney(12043709)
        self.preview = inv
    end
    self.preview:SetParent(parent)
    return self.preview
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
        self.inv = UI.Inventory(SuuUI.Root, { name = "SuuUIBags", title = "Bags", columns = self:Get("columns") })
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
            from.search.onTextChanged = function(text)
                other.search:SetValue(text or "")
                if C_Container.SetItemSearch then C_Container.SetItemSearch(text or "") end
            end
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
        for _, inv in ipairs({ self.inv, self.bank }) do
            inv.columns = v
            inv.search:SetWidth(inv:GridWidth() - 30 - S["space-3"])
            inv.grid:SetWidth(inv:GridWidth())
        end
        self:Rebuild()
        self:RebuildBank()
    end)
    self:Watch("bank", function(on)
        self:HideBlizzardBank()
        if not on then self:HideBank() end
    end)
    self:Watch("reagentBag", function() self:Rebuild() end)
    self:Watch("keyring", function() self:Rebuild() end)
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
            if self.inv:IsShown() then self:Rebuild() end
            self:RebuildBank()
        end)
    end
    for _, e in ipairs({ "BANK_TABS_CHANGED", "PLAYERBANKSLOTS_CHANGED" }) do
        self:OnGameEvent(e, function() self:RebuildBank() end)
    end
    self:OnGameEvent("BANKFRAME_OPENED", function() self:ShowBank() end)
    self:OnGameEvent("BANKFRAME_CLOSED", function() self:HideBank() end)
    self:OnGameEvent("ITEM_LOCK_CHANGED", function(_, bag, slot)
        if not (plain(bag) and plain(slot) and bag and slot) then return end
        local inv = self:InvFor(bag)
        if inv and inv:IsShown() then self:UpdateSlot(bag, slot) end
    end)
    for _, e in ipairs({ "BAG_UPDATE_COOLDOWN", "INVENTORY_SEARCH_UPDATE" }) do
        self:OnGameEvent(e, function() self:UpdateShown() end)
    end
    self:OnGameEvent("PLAYER_MONEY", function() if self.inv:IsShown() then self.inv:SetMoney(GetMoney()) end end)
    self:Sync()
end

function M:OnDisable()
    if self.inv then self.inv:Hide() end
    if self.bank then self.bank:Hide() end
end
