-- Diagnostics/LootProbe.lua
-- "/suu probe loot": what Forever offers for SuuUI's loot window and loot
-- rolls (step 2.6). Saved in SuuUIProbe.loot on /reload.
--   * the loot and roll API (globals, C_Loot, C_LootHistory, C_PartyInfo),
--     loot CVars, events, Blizzard's loot frames
--   * from now until /reload, a log: each loot window's slots as the game
--     gives them (secret or not), each group roll (its item info, time),
--     roll results and loot history, chat loot lines, blocked actions
--
--   /suu probe loot          sample and start the log (then loot a few
--                            corpses, and roll on something in a group)
--   /suu probe loot take     the next loot window: SuuUI's code takes the
--                            first slot itself (LootSlot), to see whether an
--                            addon may; then /reload

local _, ns = ...

local LP = {}
ns.LootProbe = LP

local isSecret = issecretvalue or function() return false end

local function show(v)
    if isSecret(v) then return "secret" end
    if v == nil then return "nil" end
    if type(v) == "table" then
        local parts = {}
        for k, x in pairs(v) do
            parts[#parts + 1] = tostring(k) .. "=" .. (isSecret(x) and "secret" or (type(x) == "table" and "table" or tostring(x)))
        end
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

local function call(fn, ...)
    if type(fn) ~= "function" then return "missing" end
    local res = { pcall(fn, ...) }
    if not res[1] then return "error: " .. tostring(res[2]):sub(1, 160) end
    local parts = {}
    for i = 2, math.max(2, select("#", unpack(res))) do parts[#parts + 1] = show(res[i]) end
    return table.concat(parts, " | ")
end

local GLOBALS = {
    "GetNumLootItems", "GetLootSlotInfo", "GetLootSlotLink", "GetLootSlotType", "LootSlotHasItem", "LootSlot",
    "CloseLoot", "ConfirmLootSlot", "GetLootSourceInfo", "GetLootInfo", "IsFishingLoot", "GetLootThreshold",
    "GetLootMethod", "GetOptOutOfLoot", "SetOptOutOfLoot", "GetLootRollItemInfo", "GetLootRollItemLink",
    "GetLootRollTimeLeft", "RollOnLoot", "ConfirmLootRoll", "GetActiveLootRollIDs", "GetMasterLootCandidate",
    "GiveMasterLoot", "IsMasterLooter", "LootFrame", "LootFrame_Show", "LootFrame_OnEvent", "LootButton1",
    "GroupLootFrame1", "GroupLootContainer", "GroupLootHistoryFrame", "MasterLooterFrame", "BonusRollFrame",
    "LootHistoryFrame", "AlertFrame", "LootAlertSystem", "LootWonAlertSystem", "LootUpgradeAlertSystem",
    "MoneyWonAlertSystem", "GroupLootFrame_OpenNewFrame", "GroupLootContainer_AddFrame", "LOOT_ROLL_TYPE_NEED",
    "LOOT_ROLL_TYPE_GREED", "LOOT_ROLL_TYPE_PASS", "LOOT_ROLL_TYPE_DISENCHANT", "LOOT_ROLL_TYPE_TRANSMOG",
    "LootFrameItemElementMixin", "LootFrameMixin", "GetCVarBool",
}

local EVENTS = {
    "LOOT_READY", "LOOT_OPENED", "LOOT_SLOT_CLEARED", "LOOT_SLOT_CHANGED", "LOOT_CLOSED", "LOOT_BIND_CONFIRM",
    "START_LOOT_ROLL", "CANCEL_LOOT_ROLL", "CANCEL_ALL_LOOT_ROLLS", "CONFIRM_LOOT_ROLL", "CONFIRM_DISENCHANT_ROLL",
    "LOOT_ROLLS_COMPLETE", "MAIN_SPEC_NEED_ROLL", "LOOT_ITEM_ROLL_WON", "LOOT_ITEM_AVAILABLE",
    "LOOT_HISTORY_UPDATE_DRAW", "LOOT_HISTORY_UPDATE_ENCOUNTER", "LOOT_HISTORY_UPDATE_FULL", "LOOT_HISTORY_CLEAR_HISTORY",
    "LOOT_HISTORY_GO_TO_ENCOUNTER", "LOOT_HISTORY_ROLL_CHANGED", "LOOT_HISTORY_ROLL_COMPLETE", "LOOT_HISTORY_FULL_UPDATE",
    "OPEN_MASTER_LOOT_LIST", "UPDATE_MASTER_LOOT_LIST", "PARTY_LOOT_METHOD_CHANGED", "ENCOUNTER_LOOT_RECEIVED",
    "BONUS_ROLL_STARTED", "SHOW_LOOT_TOAST", "CHAT_MSG_LOOT", "CHAT_MSG_MONEY", "CHAT_MSG_CURRENCY",
    "ADDON_ACTION_BLOCKED", "ADDON_ACTION_FORBIDDEN",
}

local function frameInfo(name)
    local f = _G[name]
    if type(f) ~= "table" or not f.GetObjectType then return "missing" end
    local kids = {}
    for k, v in pairs(f) do if type(k) == "string" and type(v) == "table" and v.GetObjectType then kids[#kids + 1] = k end end
    table.sort(kids)
    return f:GetObjectType() .. " protected=" .. show(f:IsProtected()) .. " shown=" .. show(f:IsShown())
        .. " children: " .. table.concat(kids, " ")
end

local store
local function note(s)
    local log = store and store.log
    if not log then return end
    log[#log + 1] = date("%H:%M:%S") .. (InCombatLockdown() and " [combat] " or " ") .. s
    while #log > 300 do table.remove(log, 1) end
end

-- A loot window as the game gives it: every slot's info.
local function lootWindow()
    local n = GetNumLootItems and GetNumLootItems()
    local w = { at = date("%H:%M:%S"), count = show(n), fishing = call(IsFishingLoot), slots = {},
                autoLoot = call(GetCVarBool, "autoLootDefault"), method = call(C_PartyInfo and C_PartyInfo.GetLootMethod or GetLootMethod),
                threshold = call(GetLootThreshold) }
    if type(n) == "number" and not isSecret(n) then
        for i = 1, math.min(n, 12) do
            w.slots[#w.slots + 1] = i .. ": info=" .. call(GetLootSlotInfo, i) .. " type=" .. call(GetLootSlotType, i)
                .. " link=" .. call(GetLootSlotLink, i) .. " hasItem=" .. call(LootSlotHasItem, i)
                .. " source=" .. call(GetLootSourceInfo, i)
        end
    end
    w.info = call(GetLootInfo)
    return w
end

local takeNext = false
local logging = false
local function startLog()
    if logging then return end
    logging = true
    local f = CreateFrame("Frame")
    local valid = C_EventUtils and C_EventUtils.IsEventValid
    for _, e in ipairs(EVENTS) do
        if not valid or valid(e) then f:RegisterEvent(e) end
    end
    f:SetScript("OnEvent", function(_, event, ...)
        local args = {}
        for i = 1, math.min(select("#", ...), 6) do args[#args + 1] = show((select(i, ...))) end
        note(event .. " " .. table.concat(args, " "))
        if event == "LOOT_OPENED" or event == "LOOT_READY" then
            store.windows = store.windows or {}
            local w = lootWindow()
            w.event = event
            table.insert(store.windows, w)
            while #store.windows > 6 do table.remove(store.windows, 1) end
            if event == "LOOT_OPENED" and takeNext then
                takeNext = false
                store.take = { at = date("%H:%M:%S"), slot1 = call(GetLootSlotInfo, 1) }
                store.take.result = call(LootSlot, 1)
                ns.Print("Loot probe: SuuUI took the first slot itself. /reload to save what happened.")
            end
        elseif event == "START_LOOT_ROLL" then
            local rollID = ...
            store.rolls = store.rolls or {}
            table.insert(store.rolls, {
                at = date("%H:%M:%S"), rollID = show(rollID), time = show(select(2, ...)),
                info = call(GetLootRollItemInfo, rollID), link = call(GetLootRollItemLink, rollID),
                left = call(GetLootRollTimeLeft, rollID), active = call(GetActiveLootRollIDs),
            })
            while #store.rolls > 8 do table.remove(store.rolls, 1) end
        elseif event:find("^LOOT_HISTORY") and C_LootHistory then
            store.history = store.history or {}
            local h = { at = date("%H:%M:%S"), event = event }
            if C_LootHistory.GetAllEncounterInfos then
                local ok, list = pcall(C_LootHistory.GetAllEncounterInfos)
                h.encounters = ok and type(list) == "table" and #list or show(list)
                if ok and type(list) == "table" and list[#list] then
                    local e = list[#list]
                    h.lastEncounter = show(e)
                    if C_LootHistory.GetSortedDropsForEncounter and e.encounterID then
                        local ok2, drops = pcall(C_LootHistory.GetSortedDropsForEncounter, e.encounterID)
                        if ok2 and type(drops) == "table" and drops[1] then
                            h.firstDrop = show(drops[1])
                            h.firstDropRolls = drops[1].rollInfos and show(drops[1].rollInfos[1]) or "none"
                        end
                    end
                end
            end
            table.insert(store.history, h)
            while #store.history > 10 do table.remove(store.history, 1) end
        end
    end)
end

function LP.Sample()
    SuuUIProbe = SuuUIProbe or {}
    store = SuuUIProbe.loot or {}
    SuuUIProbe.loot = store
    store.at = date("%Y-%m-%d %H:%M:%S")
    store.C_Loot = namesIn(C_Loot)
    store.C_LootHistory = namesIn(C_LootHistory)
    store.C_PartyInfo = namesIn(C_PartyInfo)
    local globals = {}
    for _, name in ipairs(GLOBALS) do
        local v = _G[name]
        globals[name] = (type(v) == "number" or type(v) == "string") and (type(v) .. " " .. tostring(v)) or type(v)
    end
    store.globals = globals
    local valid = C_EventUtils and C_EventUtils.IsEventValid
    store.events = {}
    for _, e in ipairs(EVENTS) do store.events[e] = valid and show(valid(e)) or "unknown" end
    store.cvars = {}
    for _, c in ipairs({ "autoLootDefault", "lootUnderMouse", "autoLootKey", "showLootSpam", "lootLeftmostBag" }) do
        store.cvars[c] = show(GetCVar(c))
    end
    store.frames = {}
    for _, name in ipairs({ "LootFrame", "GroupLootFrame1", "GroupLootContainer", "GroupLootHistoryFrame",
                            "MasterLooterFrame", "BonusRollFrame", "LootHistoryFrame" }) do
        store.frames[name] = frameInfo(name)
    end
    store.now = {
        method = call(C_PartyInfo and C_PartyInfo.GetLootMethod or GetLootMethod),
        threshold = call(GetLootThreshold), optOut = call(GetOptOutOfLoot), activeRolls = call(GetActiveLootRollIDs),
    }
    store.log = store.log or {}
    startLog()
    return store
end

function LP.Command(arg)
    LP.Sample()
    if arg == "take" then
        takeNext = true
        ns.Print("Loot probe: open a corpse's loot (auto loot off, or hold the auto-loot key so the window stays); SuuUI will take the first slot itself.")
        return
    end
    ns.Print("Loot probe: sampled. Logging loot windows and rolls until /reload: loot a few corpses (auto loot on and off), roll on something in a group if you can, then /reload.")
end
