-- Diagnostics/DurabilityProbe.lua
-- "/suu probe durability" (asked 2026-10-19: a durability feature; the
-- build waits on it): what Forever tells about worn gear and repairs.
--   now:   for every equipment slot (1-19) its durability, its alert state
--          and whatever repair cost the game gives for it (the tooltip
--          data, and a hidden tooltip's SetInventoryItem); whether the
--          game's DurabilityFrame exists and shows; the client's
--          documentation for durability and repairs
--   then (this session, by itself): the same 2 s into each of your next
--          fights (is durability readable in combat?); every
--          UPDATE_INVENTORY_DURABILITY and UPDATE_INVENTORY_ALERTS, timed,
--          in combat or not; at each merchant what repairs would cost
--   autorepair: only after "/suu probe durability autorepair" (for this
--          session, once): RepairAllItems() at the next merchant that
--          repairs, with no click, and whether it errored, was blocked or
--          spent the gold. It spends gold, so nothing repairs without it.
-- Saved in SuuUIProbe.durability on /reload. Values the game hides read SECRET.
--
--   /suu probe durability                 snapshot and listen
--   /suu probe durability autorepair      also repair at the next merchant
--   /suu probe durability autorepair off  not after all

local _, ns = ...

local DP = {}
ns.DurabilityProbe = DP

local isSecret = issecretvalue or function() return false end
local function show(v)
    if isSecret(v) then return "SECRET" end
    return tostring(v)
end

-- A function that may not exist, may error or may answer secret.
local function call(fn, ...)
    if type(fn) ~= "function" then return "missing" end
    local ok, a, b, c, d = pcall(fn, ...)
    if not ok then return "error: " .. tostring(a):sub(1, 120) end
    return a, b, c, d
end

local function plain(v) return v ~= nil and not isSecret(v) end

local function out()
    SuuUIProbe = SuuUIProbe or {}
    SuuUIProbe.durability = SuuUIProbe.durability or {}
    return SuuUIProbe.durability
end

local MAX_SAMPLES = 6
local MAX_EVENTS = 80

-- A hidden tooltip: GameTooltip:SetInventoryItem returns hasItem,
-- hasCooldown, repairCost on the clients that still do.
local tip
local function tipCost(slot)
    if not tip then
        local ok, t = pcall(CreateFrame, "GameTooltip", "SuuUIDurabilityProbeTip", nil, "GameTooltipTemplate")
        if not ok then return "no tooltip: " .. tostring(t):sub(1, 80) end
        tip = t
    end
    pcall(tip.SetOwner, tip, WorldFrame, "ANCHOR_NONE")
    local ok, hasItem, cooldown, cost = pcall(tip.SetInventoryItem, tip, "player", slot)
    pcall(tip.Hide, tip)
    if not ok then return "error: " .. tostring(hasItem):sub(1, 80) end
    return ("hasItem %s, cooldown %s, repairCost %s"):format(show(hasItem), show(cooldown), show(cost))
end

-- The tooltip data's plain fields, and its lines about repairs or durability.
local function tooltipData(slot)
    local T = C_TooltipInfo or {}
    local data = call(T.GetInventoryItem, "player", slot)
    if type(data) ~= "table" then return show(data) end
    if isSecret(data) then return "SECRET" end
    local parts = {}
    for k, v in pairs(data) do
        if type(v) ~= "table" then parts[#parts + 1] = tostring(k) .. "=" .. show(v) end
    end
    table.sort(parts)
    for _, line in ipairs(data.lines or {}) do
        local text = line.leftText
        if plain(text) and type(text) == "string" and (text:lower():find("repair") or text:lower():find("durab")) then
            parts[#parts + 1] = "line: " .. text .. (line.price and (" price=" .. show(line.price)) or "")
        elseif plain(line.price) and line.price then
            parts[#parts + 1] = "price line: " .. show(text) .. " " .. show(line.price)
        end
    end
    return table.concat(parts, "  ")
end

local function slots(withTooltips)
    local list = {}
    for slot = 1, 19 do
        local link = call(GetInventoryItemLink, "player", slot)
        local cur, max = call(GetInventoryItemDurability, slot)
        local entry = ("%d %s: durability %s/%s, alert %s"):format(slot, show(link), show(cur), show(max),
            show(call(GetInventoryAlertStatus, slot)))
        if withTooltips and link ~= nil then
            entry = entry .. "; tip " .. tipCost(slot) .. "; data " .. tooltipData(slot)
        end
        list[slot] = entry
    end
    return list
end

local function frameState()
    local f = _G.DurabilityFrame
    if not f then return "missing" end
    local okS, shown = pcall(f.IsShown, f)
    local okV, visible = pcall(f.IsVisible, f)
    return ("exists, shown %s, visible %s"):format(okS and show(shown) or "?", okV and show(visible) or "?")
end

local function merchant()
    local cost, can = call(GetRepairAllCost)
    return { canRepair = show(call(CanMerchantRepair)), repairAllCost = show(cost), repairAllCan = show(can),
        guildBank = show(call(CanGuildBankRepair)), money = show(call(GetMoney)) }
end

local function sample(why)
    return { at = date("%H:%M:%S"), why = why, inCombat = InCombatLockdown() and true or false,
        durabilityFrame = frameState(), slots = slots(true) }
end

local function snapshot()
    local o = out()
    o.now = sample("asked")
    o.now.merchantNow = merchant()
    o.api = {}
    for _, name in ipairs({ "GetInventoryItemDurability", "GetInventoryAlertStatus", "GetRepairAllCost", "CanMerchantRepair",
            "RepairAllItems", "CanGuildBankRepair", "ShowRepairCursor", "HideRepairCursor", "InRepairMode" }) do
        o.api[name] = type(_G[name]) == "function" and "yes" or "missing"
    end
    o.api["C_TooltipInfo.GetInventoryItem"] = C_TooltipInfo and type(C_TooltipInfo.GetInventoryItem) == "function" and "yes" or "missing"
    if ns.ApiDocs and ns.ApiDocs.Dump then
        local lines, err = ns.ApiDocs.Dump({ "durability", "repair", "inventoryalert" })
        o.docs = lines or err
        local flags, ferr = ns.ApiDocs.Flags({ "RepairAllItems", "GetRepairAllCost", "CanMerchantRepair",
            "GetInventoryItemDurability", "GetInventoryAlertStatus" })
        o.docFlags = flags or ferr
    end
end

--------------------------------------------------------------------------------
-- At a merchant: what repairs cost, and the repair test when it was asked for
--------------------------------------------------------------------------------

local autorepair = false

local function repairTest(o, before)
    autorepair = false -- once: it spends gold
    local r = { at = date("%H:%M:%S"), before = before, blocked = {} }
    o.autorepair = o.autorepair or {}
    o.autorepair[#o.autorepair + 1] = r
    local watch = CreateFrame("Frame")
    watch:RegisterEvent("ADDON_ACTION_BLOCKED")
    watch:RegisterEvent("ADDON_ACTION_FORBIDDEN")
    watch:RegisterEvent("UI_ERROR_MESSAGE")
    watch:SetScript("OnEvent", function(_, event, a, b)
        r.blocked[#r.blocked + 1] = ("%s %s %s%s"):format(event, show(a), show(b), a == ns.name and " (SuuUI)" or "")
    end)
    -- at MERCHANT_SHOW, with no click
    local ok, err = pcall(RepairAllItems)
    r.call = ok and "ran" or ("error: " .. tostring(err):sub(1, 120))
    C_Timer.After(1.5, function()
        watch:UnregisterAllEvents()
        r.after = merchant()
        local m0, m1 = before.money, r.after.money
        r.moneyWentDown = tostring(tonumber(m1) and tonumber(m0) and tonumber(m1) < tonumber(m0))
        r.slotsAfter = slots(false)
        ns.Print(("Durability probe: RepairAllItems at the merchant: %s; cost now %s (was %s); %d blocked or error messages. /reload to save it."):format(
            r.call, r.after.repairAllCost, before.repairAllCost, #r.blocked))
    end)
end

local function atMerchant()
    local o = out()
    local m = merchant()
    m.at = date("%H:%M:%S")
    o.merchants = o.merchants or {}
    if #o.merchants < MAX_SAMPLES then o.merchants[#o.merchants + 1] = m end
    if autorepair and m.canRepair == "true" then
        repairTest(o, m)
    elseif autorepair then
        ns.Print("Durability probe: this merchant doesn't repair; the repair test waits for one that does.")
    else
        ns.Print(("Durability probe: repairs here cost %s; recorded (nothing repaired)."):format(m.repairAllCost))
    end
end

--------------------------------------------------------------------------------
-- Listening for the session
--------------------------------------------------------------------------------

local listening
local function listen()
    if listening then return end
    listening = CreateFrame("Frame")
    for _, e in ipairs({ "UPDATE_INVENTORY_DURABILITY", "UPDATE_INVENTORY_ALERTS", "PLAYER_REGEN_DISABLED", "MERCHANT_SHOW" }) do
        pcall(listening.RegisterEvent, listening, e)
    end
    listening:SetScript("OnEvent", function(_, event)
        local o = out()
        if event == "PLAYER_REGEN_DISABLED" then
            C_Timer.After(2, function()
                o.inCombat = o.inCombat or {}
                if #o.inCombat < MAX_SAMPLES then
                    o.inCombat[#o.inCombat + 1] = sample("2 s after entering combat")
                    ns.Print("Durability probe: durability read 2 s into the fight.")
                end
            end)
        elseif event == "MERCHANT_SHOW" then
            -- in the event itself (the repair test's point: no click), and
            -- the cost once more a moment later, in case it came late
            atMerchant()
            C_Timer.After(0.5, function()
                local last = o.merchants and o.merchants[#o.merchants]
                if last and not last.costLater then last.costLater = merchant().repairAllCost end
            end)
        else
            o.events = o.events or {}
            if #o.events < MAX_EVENTS then
                o.events[#o.events + 1] = ("%s %s%s"):format(date("%H:%M:%S"), event, InCombatLockdown() and " in combat" or "")
            end
        end
    end)
end

function DP.Command(arg)
    if arg == "autorepair off" then
        autorepair = false
        ns.Print("Durability probe: no repair after all.")
        return
    end
    snapshot()
    listen()
    if arg == "autorepair" then
        autorepair = true
        ns.Print("Durability probe: armed. The next merchant that repairs will repair all your gear at once, with no click, using your own gold (once; /suu probe durability autorepair off to drop it). Open a repair merchant, then /reload.")
        return
    end
    ns.Print("Durability probe: your gear recorded. Get into a fight (it reads again 2 s in), open a merchant that repairs (nothing is repaired: that spends gold, only after /suu probe durability autorepair); then /reload to save it.")
end
