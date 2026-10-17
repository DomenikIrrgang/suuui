-- Diagnostics/BankSlotsProbe.lua
-- "/suu probe bankslots" (at a banker): can SuuUI's bags and bank windows
-- change bags and buy bank slots (asked 2026-10-17)? On Forever the bank's
-- "tabs" are bank bag slots (tab 1 the bank itself, 2 and up a bag each);
-- buying one is C_Bank.PurchaseBankTab, restricted for addon code, through
-- the game's confirmation popup. This records the bank's slot data, the
-- game's purchase button and bag slot buttons (protected or not), and puts
-- up a secure button that clicks the game's own purchase button: the game's
-- popup should open untainted. Click it and answer No (or Yes to buy one),
-- then Check. Saved in SuuUIProbe.bankSlots on /reload.

local _, ns = ...

local BP = {}
ns.BankSlotsProbe = BP

local UI = ns.UI

local function call(fn, ...)
    if type(fn) ~= "function" then return "missing" end
    local res = { pcall(fn, ...) }
    if not res[1] then return "error " .. tostring(res[2]):sub(1, 100) end
    local parts = {}
    for i = 2, math.max(2, #res) do
        local v = res[i]
        if type(v) == "table" then
            local kv = {}
            for k, x in pairs(v) do kv[#kv + 1] = tostring(k) .. "=" .. tostring(type(x) == "table" and "{…}" or x) end
            table.sort(kv)
            v = "{" .. table.concat(kv, ", ") .. "}"
        end
        parts[#parts + 1] = tostring(v)
    end
    return table.concat(parts, ", ")
end

local function frameInfo(name)
    local f = _G[name]
    if not f then return "missing" end
    return ("%s shown=%s visible=%s protected=%s"):format(f:GetObjectType(), tostring(f:IsShown()), tostring(f:IsVisible()), tostring(f:IsProtected()))
end

local function record(out)
    local C = Enum.BankType and Enum.BankType.Character
    out.bankType = tostring(C)
    out.maxTabs = call(C_Bank.FetchMaxNumBankTabs, C)
    out.purchased = call(C_Bank.FetchNumPurchasedBankTabs, C)
    out.canPurchase = call(C_Bank.CanPurchaseBankTab, C)
    out.hasMax = call(C_Bank.HasMaxBankTabs, C)
    out.next = call(C_Bank.FetchNextPurchasableBankTabData, C)
    out.tabIDs = call(C_Bank.FetchPurchasedBankTabIDs, C)
    -- each bank bag slot: the bag item in it and its size
    local tabBag = Enum.BagIndex and Enum.BagIndex.Characterbanktab
    out.tabBagIndex = tostring(tabBag)
    out.slots = {}
    for slot = 1, 9 do
        local item = call(C_Container.GetContainerItemID, tabBag, slot)
        local bagID = Enum.BagIndex and Enum.BagIndex["CharacterBankTab_" .. slot]
        local size = bagID and call(C_Container.GetContainerNumSlots, bagID) or "?"
        out.slots[slot] = ("item=%s bag=%s size=%s inv=%s"):format(item, tostring(bagID), size,
            call(C_Bank.BankBagTypeAndIDToInvSlot, C, slot))
    end
    out.frames = {}
    for _, name in ipairs({ "BankFrame", "BankFramePurchaseButton", "MainMenuBarBackpackButton", "CharacterBag0Slot",
                            "CharacterBag1Slot", "CharacterBag2Slot", "CharacterBag3Slot", "CharacterReagentBag0Slot", "BagsBar" }) do
        out.frames[name] = frameInfo(name)
    end
    local dialog = StaticPopupDialogs and StaticPopupDialogs.CONFIRM_BUY_BANK_TAB
    out.dialog = dialog and "present" or "missing"
    out.money = GetMoney()
end

function BP.Command(rest)
    SuuUIProbe = SuuUIProbe or {}
    local out = SuuUIProbe.bankSlots or {}
    SuuUIProbe.bankSlots = out
    out.at = date("%Y-%m-%d %H:%M:%S")
    record(out)
    if rest == "check" then
        out.check = { at = date("%H:%M:%S") }
        record(out.check)
        local d = StaticPopupDialogs and StaticPopupDialogs.CONFIRM_BUY_BANK_TAB
        if d then
            local ok, by = issecurevariable(d, "OnAccept")
            out.check.onAcceptSecure = tostring(ok) .. " " .. tostring(by)
        end
        out.check.errors = {}
        for _, e in ipairs(SuuUIDB and SuuUIDB.blocked or {}) do
            if e.time and e.time >= (out.clickedAt or out.at) then out.check.errors[#out.check.errors + 1] = tostring(e.func) end
        end
        ns.Print("Bank slots probe: checked. /reload to save it.")
        return
    end
    if InCombatLockdown() then ns.Print("Bank slots probe: out of combat, at a banker.") return end
    local p = BP.panel or UI.Panel(UIParent, { title = "Bank slots probe", width = 300, height = 150, solid = true })
    BP.panel = p
    p:SetFrameStrata("DIALOG")
    p:ClearAllPoints()
    p:SetPoint("LEFT", 40, 0)
    if not p.built then
        p.built = true
        local note = UI.Text(p.body, "caption", "ink-muted")
        note:SetPoint("TOPLEFT")
        note:SetWidth(276)
        note:SetJustifyH("LEFT")
        note:SetWordWrap(true)
        note:SetValue("1. Click the button: the game's own purchase popup should open. Answer No (or Yes to buy a slot). 2. /suu probe bankslots check. 3. /reload.")
        local b = UI.Button(p.body, { text = "Buy next bank slot (game's button)", width = 276 })
        b:SetPoint("BOTTOMLEFT")
        -- the secure button on top: clicks the game's own purchase button
        local over = CreateFrame("Button", nil, UIParent, "SecureActionButtonTemplate")
        over:RegisterForClicks("LeftButtonDown", "LeftButtonUp")
        over:SetAttribute("type1", "click")
        over:SetAttribute("clickbutton1", _G.BankFramePurchaseButton)
        over:SetFrameStrata("FULLSCREEN_DIALOG")
        over:SetAllPoints(b)
        over:HookScript("PostClick", function()
            out.clickedAt = date("%Y-%m-%d %H:%M:%S")
            out.popupShown = tostring(StaticPopup_Visible and StaticPopup_Visible("CONFIRM_BUY_BANK_TAB"))
        end)
        p.over = over
    end
    p:Show()
    ns.Print("Bank slots probe: at a banker, click the button, answer the popup, then /suu probe bankslots check and /reload.")
end
