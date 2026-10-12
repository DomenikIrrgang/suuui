-- Units/Bags.lua
-- Your bags (step 2.5a, design board "Bags"): one window, every bag's slots
-- in one grid (backpack, bags 1-4, the reagent bag; the keyring if you want
-- it), "18 free of 80", search (the game's own item search) and Blizzard's
-- sort, your money in the foot. It opens and closes with Blizzard's bags
-- (B, the bag buttons, the mailbox, a vendor, the bank): Blizzard's bag
-- frames still open and close, under a hidden parent, and SuuUI's window
-- follows them. Bottom right, movable in edit mode.
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
    },
})

local isSecret = issecretvalue or function() return false end
local function plain(v) return v ~= nil and not isSecret(v) end
local QUALITY = { [0] = "poor", "common", "uncommon", "rare", "epic", "legendary", "legendary", "legendary" }
local KEYRING = -1
local REAGENT = 5

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

--------------------------------------------------------------------------------
-- Slots
--------------------------------------------------------------------------------

-- A bag's frame: its ID is the bag (Blizzard's slot buttons read it).
function M:BagFrame(bag)
    local f = self.bagFrames[bag]
    if f then return f end
    f = CreateFrame("Frame", nil, self.inv.grid)
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
    local name = ("SuuUIBag%dSlot%d"):format(bag + 2, slot)
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

-- Every slot laid out again (bags or sizes changed), the counts, the money.
function M:Rebuild()
    if not self.inv then return end
    local list = {}
    local total, free = 0, 0
    local shown = {}
    for _, bag in ipairs(self:Bags()) do
        shown[bag] = true
        local n = numSlots(bag)
        for slot = 1, n do
            local b = self:SlotButton(bag, slot)
            list[#list + 1] = b
            self:UpdateSlot(bag, slot)
        end
        -- hide what the bag no longer has
        for slot = n + 1, #(self.buttons[bag] or {}) do self.buttons[bag][slot]:Hide() end
        if bag >= 0 and bag <= 4 then
            total = total + n
            local f = C_Container.GetContainerNumFreeSlots(bag)
            if plain(f) and f then free = free + f end
        end
    end
    for bag, slots in pairs(self.buttons) do
        if not shown[bag] then for _, b in ipairs(slots) do b:Hide() end end
    end
    self.inv:LayoutSlots(list)
    self.inv:SetMeta(("%d free of %d"):format(free, total))
    local note
    if self:Get("reagentBag") and numSlots(REAGENT) > 0 then
        local f = C_Container.GetContainerNumFreeSlots(REAGENT)
        note = ("Reagent bag: %d free"):format(plain(f) and f or 0)
    end
    self.inv:SetNote(note)
    self.inv:SetMoney(GetMoney())
end

--------------------------------------------------------------------------------
-- Opening with Blizzard's bags
--------------------------------------------------------------------------------

local hidden = CreateFrame("Frame")
hidden:Hide()

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
        if f then
            if f:GetParent() ~= hidden then f:SetParent(hidden) end
            if not self.parentHooked[f] then
                self.parentHooked[f] = true
                hooksecurefunc(f, "SetParent", function(frame, parent)
                    if parent ~= hidden and self:IsEnabled() then
                        C_Timer.After(0, function() if frame:GetParent() ~= hidden then frame:SetParent(hidden) end end)
                    end
                end)
            end
        end
    end
end

local function anyBagOpen()
    if not IsBagOpen then return false end
    for bag = KEYRING, REAGENT do
        if IsBagOpen(bag) then return true end
    end
    return false
end

function M:Sync()
    if not self.inv then return end
    local open = anyBagOpen()
    if open and not self.inv:IsShown() then
        self.inv:Show()
        self:Rebuild()
    elseif not open and self.inv:IsShown() then
        self.inv:Hide()
    end
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
        self.inv.search.onTextChanged = function(text)
            if C_Container.SetItemSearch then C_Container.SetItemSearch(text or "") end
        end
        self.inv.sort:SetScript("OnClick", function()
            if C_Container.SortBags then pcall(C_Container.SortBags) end
        end)
        self.inv:HookScript("OnHide", function()
            -- a search ends with the window
            if self.inv.search.edit:GetText() ~= "" then
                self.inv.search:SetValue("")
                if C_Container.SetItemSearch then C_Container.SetItemSearch("") end
            end
        end)
    end
    self:HideBlizzardBags()
    self:RegisterMover(self.inv, { key = "position", label = "Bags" })
    self:RegisterSettings(SECTION)
    self:Watch("columns", function(v)
        self.inv.columns = v
        self.inv.search:SetWidth(self.inv:GridWidth() - 30 - SuuUI.Tokens.space["space-3"])
        self.inv.grid:SetWidth(self.inv:GridWidth())
        self:Rebuild()
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
        if self.inv:IsShown() and plain(bag) then self:UpdateBag(bag) end
    end)
    for _, e in ipairs({ "BAG_UPDATE_DELAYED", "BAG_CONTAINER_UPDATE", "PLAYER_ENTERING_WORLD" }) do
        self:OnGameEvent(e, function() if self.inv:IsShown() then self:Rebuild() end end)
    end
    self:OnGameEvent("ITEM_LOCK_CHANGED", function(_, bag, slot)
        if self.inv:IsShown() and plain(bag) and plain(slot) and slot then self:UpdateSlot(bag, slot) end
    end)
    for _, e in ipairs({ "BAG_UPDATE_COOLDOWN", "INVENTORY_SEARCH_UPDATE" }) do
        self:OnGameEvent(e, function()
            if not self.inv:IsShown() then return end
            for _, bag in ipairs(self:Bags()) do self:UpdateBag(bag) end
        end)
    end
    self:OnGameEvent("PLAYER_MONEY", function() if self.inv:IsShown() then self.inv:SetMoney(GetMoney()) end end)
    self:Sync()
end

function M:OnDisable()
    if self.inv then self.inv:Hide() end
end
