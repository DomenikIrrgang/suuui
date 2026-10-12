-- Diagnostics/BagProbe.lua
-- "/suu probe bags": what Forever offers for SuuUI's bags and bank (step
-- 2.5). Saved in SuuUIProbe.bags on /reload.
--   * C_Container, C_Bank, C_NewItems, the bag numbering (Enum.BagIndex and
--     the old constants), Blizzard's sort and search, CVars, events
--   * every bag as the client gives it (slots, free, its name and family)
--     and each slot's item info fields; at a banker the bank too
--   * Blizzard's bag and bank frames, and the item button templates
--   * from now until /reload: which bag functions Blizzard calls when (the
--     B key, the bank, the mailbox, a vendor)
--
--   /suu probe bags          sample (run it once anywhere, once at a banker)
--   /suu probe bags item     a test item button made from Blizzard's bag
--                            slot template for your backpack's first slot:
--                            right click it out of combat and in combat (put
--                            something harmless there: a piece of gear to
--                            equip and swap back), then /reload
--   /suu probe bags item off hide it

local _, ns = ...

local BP = {}
ns.BagProbe = BP

local isSecret = issecretvalue or function() return false end

local function show(v)
    if isSecret(v) then return "secret" end
    if v == nil then return "nil" end
    if type(v) == "table" then
        local parts = {}
        for k, x in pairs(v) do parts[#parts + 1] = tostring(k) .. "=" .. (isSecret(x) and "secret" or tostring(x)) end
        table.sort(parts)
        return "{" .. table.concat(parts, ", ") .. "}"
    end
    return tostring(v)
end

local function namesIn(t)
    local out = {}
    if type(t) ~= "table" then return { "missing" } end
    for k, v in pairs(t) do if type(k) == "string" and type(v) == "function" then out[#out + 1] = k end end
    table.sort(out)
    return out
end

local GLOBALS = {
    "ToggleAllBags", "OpenAllBags", "CloseAllBags", "ToggleBag", "OpenBag", "CloseBag", "ToggleBackpack",
    "OpenBackpack", "CloseBackpack", "IsBagOpen", "ContainerFrame_GenerateFrame", "UpdateContainerFrameAnchors",
    "ContainerFrameCombinedBags", "ContainerFrameContainer", "ContainerFrame1", "ContainerFrame6", "ContainerFrame13",
    "BankFrame", "BankPanel", "AccountBankPanel", "ReagentBankFrame", "BankSlotsFrame", "BankFrameItem1",
    "BankFrame_Open", "BankFrame_ShowPanel", "CloseBankFrame", "OpenBankFrame", "BagsBar", "MainMenuBarBackpackButton",
    "CharacterBag0Slot", "NUM_BAG_SLOTS", "NUM_BANKBAGSLOTS", "NUM_TOTAL_EQUIPPED_BAG_SLOTS", "BANK_CONTAINER",
    "REAGENTBANK_CONTAINER", "KEYRING_CONTAINER", "BACKPACK_CONTAINER", "NUM_CONTAINER_FRAMES",
    "ContainerFrameItemButtonMixin", "BankFrameItemButtonMixin", "ItemButtonMixin", "SetItemButtonTexture",
    "SortBags", "SortBankBags", "GetMoney", "GetCoinTextureString", "C_CurrencyInfo",
}

local TEMPLATES = { "ContainerFrameItemButtonTemplate", "BankItemButtonGenericTemplate", "ItemButtonTemplate",
                    "SecureActionButtonTemplate" }

local EVENTS = {
    "BAG_UPDATE", "BAG_UPDATE_DELAYED", "BAG_NEW_ITEMS_UPDATED", "ITEM_LOCK_CHANGED", "BAG_UPDATE_COOLDOWN",
    "BANKFRAME_OPENED", "BANKFRAME_CLOSED", "PLAYERBANKSLOTS_CHANGED", "PLAYERBANKBAGSLOTS_CHANGED",
    "BAG_CONTAINER_UPDATE", "INVENTORY_SEARCH_UPDATE", "MERCHANT_SHOW", "MERCHANT_CLOSED", "MAIL_SHOW",
    "MAIL_CLOSED", "PLAYER_MONEY", "BAG_OPEN", "BAG_CLOSED", "USE_COMBINED_BAGS_CHANGED", "BANK_TABS_CHANGED",
    "BANK_BAG_SLOT_FLAGS_UPDATED", "BAG_SLOT_FLAGS_UPDATED", "AUCTION_HOUSE_SHOW", "TRADE_SHOW",
    "GUILDBANKFRAME_OPENED", "PLAYER_INTERACTION_MANAGER_FRAME_SHOW", "PLAYER_INTERACTION_MANAGER_FRAME_HIDE",
}

local function call(fn, ...)
    if type(fn) ~= "function" then return "missing" end
    local res = { pcall(fn, ...) }
    if not res[1] then return "error: " .. tostring(res[2]):sub(1, 160) end
    local parts = {}
    for i = 2, math.max(2, select("#", unpack(res))) do parts[#parts + 1] = show(res[i]) end
    return table.concat(parts, " | ")
end

-- One bag: its size, free slots, name, family and the first few items.
local function bag(index)
    local C = C_Container
    local b = { index = index }
    b.slots = call(C.GetContainerNumSlots, index)
    b.free = call(C.GetContainerNumFreeSlots, index)
    b.name = call(C.GetBagName, index)
    b.inventoryID = call(C.ContainerIDToInventoryID, index)
    local n = C.GetContainerNumSlots and C.GetContainerNumSlots(index) or 0
    if isSecret(n) then n = 0 end
    local items = {}
    for slot = 1, math.min(n or 0, 40) do
        local ok, info = pcall(C.GetContainerItemInfo, index, slot)
        if ok and info then
            items[#items + 1] = slot .. ": " .. show(info)
                .. (C_NewItems and C_NewItems.IsNewItem and (" new=" .. call(C_NewItems.IsNewItem, index, slot)) or "")
            if #items >= 4 then break end
        end
    end
    b.items = items
    return b
end

local logging = false
local function startLog(store)
    if logging then return end
    logging = true
    store.log = store.log or {}
    local function note(s)
        local log = SuuUIProbe.bags and SuuUIProbe.bags.log
        if not log then return end
        log[#log + 1] = date("%H:%M:%S") .. (InCombatLockdown() and " [combat] " or " ") .. s
        while #log > 200 do table.remove(log, 1) end
    end
    for _, name in ipairs({ "ToggleAllBags", "OpenAllBags", "CloseAllBags", "ToggleBag", "OpenBag", "CloseBag",
                            "ToggleBackpack", "OpenBackpack", "CloseBackpack" }) do
        if type(_G[name]) == "function" then
            hooksecurefunc(name, function(...)
                local parts = {}
                for i = 1, select("#", ...) do
                    local v = select(i, ...)
                    parts[#parts + 1] = (type(v) == "table" and v.GetName and (v:GetName() or "frame")) or show(v)
                end
                note(name .. "(" .. table.concat(parts, ", ") .. ")")
            end)
        end
    end
    local f = CreateFrame("Frame")
    local valid = C_EventUtils and C_EventUtils.IsEventValid
    for _, e in ipairs({ "BANKFRAME_OPENED", "BANKFRAME_CLOSED", "MERCHANT_SHOW", "MAIL_SHOW", "BAG_OPEN", "BAG_CLOSED",
                         "PLAYER_INTERACTION_MANAGER_FRAME_SHOW", "PLAYER_INTERACTION_MANAGER_FRAME_HIDE",
                         "ADDON_ACTION_BLOCKED", "ADDON_ACTION_FORBIDDEN" }) do
        if not valid or valid(e) then f:RegisterEvent(e) end
    end
    f:SetScript("OnEvent", function(_, event, a, b) note(event .. " " .. show(a) .. " " .. show(b)) end)
end

function BP.Sample()
    SuuUIProbe = SuuUIProbe or {}
    local store = SuuUIProbe.bags or {}
    SuuUIProbe.bags = store
    local at = date("%H:%M:%S")
    store.C_Container = namesIn(C_Container)
    store.C_Bank = namesIn(C_Bank)
    store.C_NewItems = namesIn(C_NewItems)
    store.C_Item = namesIn(C_Item)
    local globals = {}
    for _, name in ipairs(GLOBALS) do
        local v = _G[name]
        globals[name] = (type(v) == "number" or type(v) == "string") and (type(v) .. " " .. tostring(v)) or type(v)
    end
    store.globals = globals
    local enum = {}
    for k, v in pairs(Enum.BagIndex or {}) do enum[#enum + 1] = tostring(k) .. "=" .. tostring(v) end
    table.sort(enum)
    store.bagIndex = enum
    local valid = C_EventUtils and C_EventUtils.IsEventValid
    store.events = {}
    for _, e in ipairs(EVENTS) do store.events[e] = valid and show(valid(e)) or "unknown" end
    store.cvars = {}
    for _, c in ipairs({ "combinedBags", "sortBagsRightToLeft", "insertItemsLeftToRight", "expandBagBar", "colorblindMode" }) do
        store.cvars[c] = show(GetCVar(c))
    end
    store.sort = {
        sortRightToLeft = call(C_Container.GetSortBagsRightToLeft),
        insertLeftToRight = call(C_Container.GetInsertItemsLeftToRight),
        backpackAutosort = call(C_Container.GetBackpackAutosortDisabled),
    }
    store.templates = {}
    for _, t in ipairs(TEMPLATES) do
        local parent = CreateFrame("Frame", nil, UIParent)
        parent:SetID(0)
        local ok, b = pcall(CreateFrame, "ItemButton", nil, parent, t)
        if not ok then ok, b = pcall(CreateFrame, "Button", nil, parent, t) end
        if ok and b then
            store.templates[t] = "ok, " .. b:GetObjectType() .. ", protected=" .. show(b:IsProtected())
            b:Hide()
        else
            store.templates[t] = "error: " .. tostring(b):sub(1, 160)
        end
        parent:Hide()
    end
    store.frames = {}
    for _, name in ipairs({ "ContainerFrameCombinedBags", "ContainerFrame1", "BankFrame", "BankPanel", "AccountBankPanel" }) do
        local f = _G[name]
        if f then
            local kids = {}
            for k, v in pairs(f) do if type(k) == "string" and type(v) == "table" and v.GetObjectType then kids[#kids + 1] = k end end
            table.sort(kids)
            store.frames[name] = "protected=" .. show(f:IsProtected()) .. " shown=" .. show(f:IsShown()) .. " children: " .. table.concat(kids, " ")
        else
            store.frames[name] = "missing"
        end
    end
    -- the bags: every index the game names, and 0..12 besides
    local sample = { at = at, bankOpen = BankFrame and BankFrame:IsShown() and true or false, money = show(GetMoney()) }
    local seen, bags = {}, {}
    local indexes = {}
    for _, v in pairs(Enum.BagIndex or {}) do indexes[#indexes + 1] = v end
    for i = -3, 12 do indexes[#indexes + 1] = i end
    table.sort(indexes)
    for _, i in ipairs(indexes) do
        if not seen[i] then
            seen[i] = true
            local b = bag(i)
            if b.slots ~= "0" and b.slots ~= "nil" and b.slots ~= "missing" then bags[#bags + 1] = b end
        end
    end
    sample.bags = bags
    store.samples = store.samples or {}
    table.insert(store.samples, sample)
    while #store.samples > 4 do table.remove(store.samples, 1) end
    startLog(store)
    return store, sample
end

-- A test item button for the backpack's first slot, from Blizzard's own
-- template, in a parent whose ID is the bag (the template reads it).
local testParent
local function itemTest(off)
    if off then
        if testParent then testParent:Hide() end
        ns.Print("Bag probe: test button hidden.")
        return
    end
    if InCombatLockdown() then ns.Print("Bag probe: make it out of combat.") return end
    SuuUIProbe = SuuUIProbe or {}
    local log = { clicks = {}, blocked = {}, locks = {} }
    SuuUIProbe.bagItem = log
    if not testParent then
        testParent = CreateFrame("Frame", "SuuUIBagProbeParent", UIParent)
        testParent:SetID(0)
        testParent:SetSize(40, 40)
        testParent:SetPoint("CENTER", 0, 160)
        local ok, b = pcall(CreateFrame, "ItemButton", "SuuUIBagProbeItem", testParent, "ContainerFrameItemButtonTemplate")
        if not ok then
            log.error = tostring(b)
            ns.Print("Bag probe: the template didn't make a button: " .. tostring(b))
            return
        end
        b:SetID(1)
        b:SetAllPoints()
        b:HookScript("PostClick", function(_, button)
            local l = SuuUIProbe.bagItem
            if l then l.clicks[#l.clicks + 1] = date("%H:%M:%S") .. " " .. tostring(button) .. (InCombatLockdown() and " in combat" or "") end
        end)
        testParent.button = b
        local ev = CreateFrame("Frame")
        ev:RegisterEvent("ADDON_ACTION_BLOCKED")
        ev:RegisterEvent("ADDON_ACTION_FORBIDDEN")
        ev:RegisterEvent("ITEM_LOCK_CHANGED")
        ev:RegisterEvent("PLAYER_EQUIPMENT_CHANGED")
        ev:SetScript("OnEvent", function(_, event, a, b2)
            local l = SuuUIProbe.bagItem
            if not l then return end
            local entry = date("%H:%M:%S") .. " " .. event .. " " .. show(a) .. " " .. show(b2) .. (InCombatLockdown() and " in combat" or "")
            if event:find("ADDON_ACTION") then l.blocked[#l.blocked + 1] = entry else l.locks[#l.locks + 1] = entry end
        end)
    end
    local b = testParent.button
    local info = C_Container.GetContainerItemInfo(0, 1)
    -- the template starts hidden; its art from the game's own helper
    if SetItemButtonTexture then pcall(SetItemButtonTexture, b, info and info.iconFileID) end
    if b.icon and info then b.icon:SetTexture(info.iconFileID) end
    log.item = info and info.hyperlink or "empty"
    log.protected = show(b:IsProtected())
    -- which bag and slot the template thinks it is (from the parent's ID)
    log.bagID = b.GetBagID and call(b.GetBagID, b) or "no GetBagID"
    log.slotID = call(b.GetID, b)
    log.hasBagIDField = b.bagID ~= nil and show(b.bagID) or "no field"
    testParent:Show()
    b:Show()
    ns.Print("Bag probe: a test button for your backpack's first slot (" .. tostring(log.item) .. ") above the middle. Right click it out of combat and in combat, then /reload.")
end

function BP.Command(arg)
    if arg == "item" then return itemTest(false) end
    if arg == "item off" then return itemTest(true) end
    local _, sample = BP.Sample()
    ns.Print(("Bag probe: %d bags%s. Logging bag opens until /reload; at a banker run it again."):format(
        #sample.bags, sample.bankOpen and " (bank open)" or ""))
end
