-- Diagnostics/QuestProbe.lua
-- "/suu probe quest": what Forever offers for SuuUI's objective tracker
-- (step 2.3). Saved in SuuUIProbe.quest on /reload.
--   * which quest functions exist (C_QuestLog, the older globals, quest
--     items, difficulty colours, super tracking) and which events are valid
--   * Blizzard's tracker frames (ObjectiveTrackerFrame and its modules)
--   * your quest log as the client gives it: each quest's info fields,
--     watched or not, objectives, finished / ready to turn in, its quest item,
--     the difficulty colour, and whether any value is secret
--   * whether the quest item template exists and is protected
--
--   /suu probe quest          sample (with some quests in your log, a quest
--                             item among them if you have one)
--   /suu probe quest item     a test button for your first quest item: click it
--                             out of combat and in combat, then /reload
--   /suu probe quest item off hide it

local _, ns = ...

local QP = {}
ns.QuestProbe = QP

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

local function call(fn, ...)
    if type(fn) ~= "function" then return "missing" end
    local res = { pcall(fn, ...) }
    if not res[1] then return "error: " .. tostring(res[2]):sub(1, 160) end
    local parts = {}
    for i = 2, math.max(2, select("#", unpack(res))) do parts[#parts + 1] = show(res[i]) end
    return table.concat(parts, " | ")
end

local function namesIn(t)
    local out = {}
    if type(t) ~= "table" then return { "missing" } end
    for k, v in pairs(t) do if type(k) == "string" and type(v) == "function" then out[#out + 1] = k end end
    table.sort(out)
    return out
end

local GLOBALS = {
    "GetNumQuestLogEntries", "GetQuestLogTitle", "GetQuestLogLeaderBoard", "GetNumQuestLeaderBoards",
    "GetNumQuestWatches", "GetQuestIndexForWatch", "AddQuestWatch", "RemoveQuestWatch", "IsQuestWatched",
    "GetQuestLogSpecialItemInfo", "GetQuestLogSpecialItemCooldown", "UseQuestLogSpecialItem",
    "IsQuestLogSpecialItemInRange", "GetQuestDifficultyColor", "GetDifficultyColor", "GetQuestGreenRange",
    "UnitQuestTrivialLevelRange", "GetQuestLogIndexByID", "IsQuestComplete", "GetQuestTimers",
    "GetQuestLogCompletionText", "QuestUtils_GetQuestName", "QuestUtil", "QuestMapFrame_OpenToQuestDetails",
    "ShowQuestLog", "ToggleQuestLog", "QuestLogFrame", "QuestMapFrame", "WorldMapFrame", "QuestFrame",
    "ObjectiveTrackerFrame", "ObjectiveTrackerManager", "QuestObjectiveTracker", "CampaignQuestObjectiveTracker",
    "ScenarioObjectiveTracker", "AchievementObjectiveTracker", "BonusObjectiveTracker", "WorldQuestObjectiveTracker",
    "ProfessionsRecipeTracker", "MonthlyActivitiesObjectiveTracker", "QuestWatchFrame", "WatchFrame",
    "ObjectiveTracker_Collapse", "ObjectiveTracker_Expand", "QuestObjectiveItemButtonMixin",
}

local EVENTS = {
    "QUEST_LOG_UPDATE", "QUEST_WATCH_LIST_CHANGED", "QUEST_WATCH_UPDATE", "QUEST_ACCEPTED", "QUEST_REMOVED",
    "QUEST_TURNED_IN", "QUEST_POI_UPDATE", "UNIT_QUEST_LOG_CHANGED", "SUPER_TRACKING_CHANGED",
    "QUEST_AUTOCOMPLETE", "QUEST_LOG_CRITERIA_UPDATE", "ENCOUNTER_START", "ENCOUNTER_END",
    "BAG_UPDATE_COOLDOWN", "QUEST_ITEM_UPDATE", "ZONE_CHANGED_NEW_AREA",
}

-- One quest log entry, every field and what goes with it.
local function quest(index)
    local q = { index = index }
    local info
    if C_QuestLog and C_QuestLog.GetInfo then
        local ok, r = pcall(C_QuestLog.GetInfo, index)
        if ok then info = r end
        q.info = ok and show(r) or ("error: " .. tostring(r))
    elseif GetQuestLogTitle then
        q.title = call(GetQuestLogTitle, index)
    end
    if type(info) ~= "table" then return q end
    if info.isHeader then q.header = true return q end
    local id = info.questID
    q.questID = show(id)
    if not id or isSecret(id) then return q end
    local QL = C_QuestLog
    q.watchType = call(QL.GetQuestWatchType, id)
    q.isComplete = call(QL.IsComplete, id)
    q.readyForTurnIn = call(QL.ReadyForTurnIn, id)
    q.isFailed = call(QL.IsFailed, id)
    q.difficultyLevel = call(QL.GetQuestDifficultyLevel, id)
    q.title = call(QL.GetTitleForQuestID, id)
    q.logIndexForID = call(QL.GetLogIndexForQuestID, id)
    q.tagInfo = call(QL.GetQuestTagInfo, id)
    q.timeLeft = call(QL.GetTimeAllowed, id)
    q.requiredMoney = call(QL.GetRequiredMoney, id)
    q.distance = call(QL.GetDistanceSqToQuest, id)
    q.isOnMap = call(QL.IsOnMap, id)
    local objectives = {}
    if QL.GetQuestObjectives then
        local ok, list = pcall(QL.GetQuestObjectives, id)
        if ok and type(list) == "table" then
            for i, o in ipairs(list) do objectives[i] = show(o) end
        else
            objectives[1] = ok and show(list) or ("error: " .. tostring(list))
        end
    end
    q.objectives = objectives
    if GetQuestLogLeaderBoard then
        local board = {}
        for i = 1, 5 do
            local r = call(GetQuestLogLeaderBoard, i, index)
            if r == "nil | nil | nil" or r == "nil" then break end
            board[i] = r
        end
        q.leaderBoard = board
    end
    q.completionText = call(GetQuestLogCompletionText, index)
    q.specialItem = call(GetQuestLogSpecialItemInfo, index)
    q.specialItemCooldown = call(GetQuestLogSpecialItemCooldown, index)
    q.specialItemInRange = call(IsQuestLogSpecialItemInRange, index)
    local level = info.difficultyLevel or info.level
    if level and not isSecret(level) then
        q.difficultyColor = call(GetQuestDifficultyColor, level)
        q.difficultyColorByLevel = call(GetDifficultyColor, level)
    end
    return q
end

local function frameInfo(f)
    if not f then return "missing" end
    local out = { name = f.GetName and f:GetName() or "?", shown = show(f:IsShown()), protected = show(f:IsProtected()) }
    local kids = {}
    for k, v in pairs(f) do
        if type(k) == "string" and type(v) == "table" and v.GetObjectType then kids[#kids + 1] = k end
    end
    table.sort(kids)
    out.children = kids
    if f.GetPoint then out.point = call(f.GetPoint, f, 1) end
    return out
end

function QP.Sample()
    SuuUIProbe = SuuUIProbe or {}
    local store = { at = date("%H:%M:%S") }
    SuuUIProbe.quest = store
    store.context = {
        level = show(UnitLevel("player")),
        instance = select(2, IsInInstance()) or "none",
        combat = InCombatLockdown() and "in combat" or "out of combat",
        trivialRange = call(UnitQuestTrivialLevelRange, "player"),
        greenRange = call(GetQuestGreenRange),
    }
    store.C_QuestLog = namesIn(C_QuestLog)
    store.C_SuperTrack = namesIn(C_SuperTrack)
    store.C_QuestInfoSystem = namesIn(C_QuestInfoSystem)
    local globals = {}
    for _, name in ipairs(GLOBALS) do globals[name] = _G[name] and type(_G[name]) or "missing" end
    store.globals = globals
    local valid = C_EventUtils and C_EventUtils.IsEventValid
    local events = {}
    for _, e in ipairs(EVENTS) do events[e] = valid and show(valid(e)) or "unknown" end
    store.events = events
    store.cvars = {
        autoQuestWatch = show(GetCVar("autoQuestWatch")),
        autoQuestProgress = show(GetCVar("autoQuestProgress")),
        trackQuestSorting = show(GetCVar("trackQuestSorting")),
    }
    -- Blizzard's tracker
    store.tracker = frameInfo(ObjectiveTrackerFrame)
    store.questTracker = frameInfo(QuestObjectiveTracker)
    -- the quest item template: does it exist, is it protected
    local ok, b = pcall(CreateFrame, "Button", nil, UIParent, "QuestObjectiveItemButtonTemplate")
    if ok and b then
        store.itemTemplate = { exists = true, protected = show(b:IsProtected()), type = show(b:GetAttribute("type")) }
        b:Hide()
    else
        store.itemTemplate = { exists = false, error = tostring(b):sub(1, 160) }
    end
    -- the log
    local n = C_QuestLog and C_QuestLog.GetNumQuestLogEntries and select(1, C_QuestLog.GetNumQuestLogEntries())
        or (GetNumQuestLogEntries and GetNumQuestLogEntries()) or 0
    store.entries = show(n)
    store.quests = {}
    if not isSecret(n) then
        for i = 1, math.min(n or 0, 40) do store.quests[#store.quests + 1] = quest(i) end
    end
    -- watches
    local watches = {}
    if C_QuestLog and C_QuestLog.GetNumQuestWatches then
        local count = C_QuestLog.GetNumQuestWatches()
        watches.count = show(count)
        if not isSecret(count) then
            for i = 1, count or 0 do watches[#watches + 1] = call(C_QuestLog.GetQuestIDForQuestWatchIndex, i) end
        end
    end
    store.watches = watches
    store.superTracked = C_SuperTrack and call(C_SuperTrack.GetSuperTrackedQuestID) or "missing"
    return store
end

-- A test button for your first quest item: a plain secure "item" button,
-- the way SuuUI's tracker would make it. Counts clicks, notes blocked
-- actions and the spell casts that follow.
local testButton
local function firstQuestItem()
    local n = C_QuestLog and C_QuestLog.GetNumQuestLogEntries and C_QuestLog.GetNumQuestLogEntries() or 0
    for i = 1, n do
        local ok, link, icon = pcall(GetQuestLogSpecialItemInfo, i)
        if ok and link and not isSecret(link) then return link, icon, i end
    end
end

local function itemTest(off)
    if off then
        if testButton then testButton:Hide() end
        ns.Print("Quest probe: test button hidden.")
        return
    end
    if InCombatLockdown() then ns.Print("Quest probe: make the button out of combat.") return end
    local link, icon, index = firstQuestItem()
    if not link then ns.Print("Quest probe: no quest item in your log (a quest that gives a usable item).") return end
    SuuUIProbe = SuuUIProbe or {}
    local log = { item = link, logIndex = index, clicks = {}, blocked = {}, casts = {} }
    SuuUIProbe.questItem = log
    if not testButton then
        testButton = CreateFrame("Button", "SuuUIQuestProbeItem", UIParent, "SecureActionButtonTemplate")
        testButton:SetSize(36, 36)
        testButton:SetPoint("CENTER", 0, 120)
        testButton:RegisterForClicks("AnyDown", "AnyUp")
        testButton.icon = testButton:CreateTexture(nil, "ARTWORK")
        testButton.icon:SetAllPoints()
        testButton:HookScript("PostClick", function(_, button, down)
            local l = SuuUIProbe.questItem
            if l then l.clicks[#l.clicks + 1] = date("%H:%M:%S") .. (InCombatLockdown() and " in combat" or " out of combat") .. (down and " down" or " up") end
        end)
        local ev = CreateFrame("Frame")
        ev:RegisterEvent("ADDON_ACTION_BLOCKED")
        ev:RegisterEvent("ADDON_ACTION_FORBIDDEN")
        ev:RegisterUnitEvent("UNIT_SPELLCAST_SUCCEEDED", "player")
        ev:RegisterUnitEvent("UNIT_SPELLCAST_FAILED", "player")
        ev:SetScript("OnEvent", function(_, event, a, b, c)
            local l = SuuUIProbe.questItem
            if not l then return end
            if event == "UNIT_SPELLCAST_SUCCEEDED" or event == "UNIT_SPELLCAST_FAILED" then
                l.casts[#l.casts + 1] = event .. " spell " .. show(c) .. (InCombatLockdown() and " in combat" or "")
            else
                l.blocked[#l.blocked + 1] = event .. " " .. show(a) .. " " .. show(b)
            end
        end)
    end
    testButton:SetAttribute("type", "item")
    testButton:SetAttribute("item", link)
    testButton.icon:SetTexture(icon)
    testButton:Show()
    ns.Print("Quest probe: a test button for " .. link .. " above the middle of the screen. Use it out of combat and in combat (where the item works), then /reload.")
end

function QP.Command(arg)
    if arg == "item" then return itemTest(false) end
    if arg == "item off" then return itemTest(true) end
    local s = QP.Sample()
    ns.Print(("Quest probe: %d log entries, %d watched. /reload to save it."):format(
        tonumber(s.entries) or 0, #s.watches))
end
