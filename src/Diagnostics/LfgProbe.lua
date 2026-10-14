-- Diagnostics/LfgProbe.lua
-- "/suu probe lfg": what ForeverLFG (the group finder library: the game's
-- tool and the public chat channels as one list) can rely on.
--   The tool: its categories and activities (Dungeons, Quests & Zones,
--   Custom, ...) and their activities (per activity group, the game's
--   way), its functions, your own listing.
--   "/suu probe lfg timer" also searches from a timer, two seconds later:
--   blocked (ADDON_ACTION_BLOCKED, 2026-10-14), the tool can't refresh by
--   itself.
--   Chat: the channels you're in.
-- "/suu probe lfg click": a button; its click searches and saves your
-- listing again unchanged (is a click enough for both?).
-- "/suu probe lfg join": joins LookingForGroup and takes it off every chat
-- window. "/suu probe lfg delist": a button whose click delists you.
-- "/suu probe lfg record": the public channels' messages (and say/yell),
-- as they arrive, with the channel, author, zone, whether you were in
-- combat or an instance and whether the text was secret; kept across
-- /reloads until "/suu probe lfg stop" (the parser is tuned on them).
-- Saved in SuuUIProbe.lfg on /reload; only on this computer.

local _, ns = ...

local LP = {}
ns.LfgProbe = LP

local isSecret = issecretvalue or function() return false end
local MAX_LINES = 4000

local function show(v)
    if isSecret(v) then return "<secret>" end
    if type(v) ~= "table" then return tostring(v) end
    local parts = {}
    for k, x in pairs(v) do
        local s = isSecret(x) and "<secret>" or (type(x) == "table" and "{...}" or tostring(x))
        parts[#parts + 1] = tostring(k) .. "=" .. s
    end
    table.sort(parts)
    return "{" .. table.concat(parts, ", ") .. "}"
end

local function names(t)
    local out = {}
    if type(t) ~= "table" then return out end
    for k, v in pairs(t) do if type(v) == "function" then out[#out + 1] = k end end
    table.sort(out)
    return out
end

local function store()
    SuuUIProbe = SuuUIProbe or {}
    SuuUIProbe.lfg = SuuUIProbe.lfg or {}
    return SuuUIProbe.lfg
end

-- what a search result holds (compact), and its member counts
local function result(lfg, id)
    local ok, info = pcall(lfg.GetSearchResultInfo, id)
    if not ok then return "error: " .. tostring(info) end
    if not info then return "nil" end
    if isSecret(info) then return "<secret table>" end
    local acts = {}
    for _, a in ipairs(info.activityIDs or { info.activityID }) do acts[#acts + 1] = tostring(a) end
    local okC, counts = pcall(lfg.GetSearchResultMemberCounts, id)
    local need = ""
    if okC and type(counts) == "table" and not isSecret(counts) then
        need = ("need T%s H%s D%s"):format(tostring(counts.TANK_REMAINING), tostring(counts.HEALER_REMAINING), tostring(counts.DAMAGER_REMAINING))
    end
    return ("acts=%s leader=%s members=%s age=%s delisted=%s quest=%s name=%s comment=%s %s"):format(
        table.concat(acts, ","), show(info.leaderName), show(info.numMembers), show(info.age), show(info.isDelisted),
        show(info.questID), show(info.name), show(info.comment), need)
end

function LP.Snapshot()
    local s = store()
    s.at = date("%Y-%m-%d %H:%M:%S")
    local lfg = C_LFGList
    if not lfg then s.tool = "no C_LFGList" return end
    s.functions = names(lfg)
    -- categories and their activities
    s.categories = {}
    local okCats, cats = pcall(lfg.GetAvailableCategories)
    for _, cat in ipairs(okCats and cats or {}) do
        local okI, info = pcall(lfg.GetLfgCategoryInfo, cat)
        local entry = { id = cat, info = show(okI and info or nil), activities = {} }
        -- the game's way: per activity group, then the ones in none
        local acts, seen = {}, {}
        local okG, groups = pcall(lfg.GetAvailableActivityGroups, cat)
        entry.groups = {}
        for _, g in ipairs(okG and groups or {}) do
            local okN, gname = pcall(lfg.GetActivityGroupInfo, g)
            local okGA, ga = pcall(lfg.GetAvailableActivities, cat, g)
            entry.groups[#entry.groups + 1] = ("%s %s: %d"):format(tostring(g), tostring(okN and gname), okGA and type(ga) == "table" and #ga or -1)
            for _, a in ipairs(okGA and ga or {}) do if not seen[a] then seen[a] = true; acts[#acts + 1] = a end end
        end
        local okA, all = pcall(lfg.GetAvailableActivities, cat, nil)
        entry.ungroupedCall = okA and type(all) == "table" and #all or ("error: " .. tostring(all))
        for _, a in ipairs(okA and all or {}) do if not seen[a] then seen[a] = true; acts[#acts + 1] = a end end
        for i, a in ipairs(acts) do
            if i > 120 then entry.activities[#entry.activities + 1] = "... " .. #acts .. " in all" break end
            local okT, t = pcall(lfg.GetActivityInfoTable, a)
            if okT and type(t) == "table" then
                entry.activities[#entry.activities + 1] = ("%d %s lvl %s-%s max %s group %s"):format(a, tostring(t.fullName),
                    tostring(t.minLevel), tostring(t.maxLevelSuggestion), tostring(t.maxNumPlayers), tostring(t.groupFinderActivityGroupID))
            else
                entry.activities[#entry.activities + 1] = tostring(a)
            end
        end
        s.categories[#s.categories + 1] = entry
    end
    -- your own listing
    local okE, entry = pcall(lfg.GetActiveEntryInfo)
    s.ownListing = okE and show(entry) or ("error: " .. tostring(entry))
    if okE and type(entry) == "table" and not isSecret(entry) and entry.activityIDs then
        s.ownActivities = show(entry.activityIDs)
    end
    local okR, a, b, c = pcall(GetLFGRoles)
    s.ownRoles = okR and ("leader=%s tank=%s healer=%s dps=%s"):format(tostring(a), tostring(b), tostring(c), tostring(select(4, GetLFGRoles()))) or "no GetLFGRoles"
    -- the chat channels you're in
    s.serverChannels = {}
    if EnumerateServerChannels then
        for _, name in ipairs({ EnumerateServerChannels() }) do s.serverChannels[#s.serverChannels + 1] = tostring(name) end
    end
    local okL, lfgIndex, lfgName = pcall(GetChannelName, "LookingForGroup")
    s.lookingForGroupJoined = okL and (tostring(lfgIndex) .. " " .. tostring(lfgName)) or "error"
    s.channels = {}
    local list = { GetChannelList() }
    for i = 1, #list, 3 do
        s.channels[#s.channels + 1] = ("%s %s%s"):format(tostring(list[i]), tostring(list[i + 1]), list[i + 2] and " (disabled)" or "")
    end
end

-- A search from a timer: nothing you pressed behind it.
function LP.TimerSearch()
    local s = store()
    local lfg = C_LFGList
    local okCats, cats = pcall(lfg.GetAvailableCategories)
    local cat = okCats and cats and cats[1]
    s.timerSearch = { category = tostring(cat), blocked = {} }
    if not cat then return end
    local f = CreateFrame("Frame")
    for _, e in ipairs({ "LFG_LIST_SEARCH_RESULTS_RECEIVED", "LFG_LIST_SEARCH_FAILED", "ADDON_ACTION_BLOCKED", "ADDON_ACTION_FORBIDDEN" }) do
        f:RegisterEvent(e)
    end
    f:SetScript("OnEvent", function(self, event, a1, a2)
        local t = s.timerSearch
        if event == "ADDON_ACTION_BLOCKED" or event == "ADDON_ACTION_FORBIDDEN" then
            t.blocked[#t.blocked + 1] = event .. " " .. tostring(a1) .. " " .. tostring(a2)
            return
        end
        self:UnregisterAllEvents()
        t.event = event
        local okR, count, ids = pcall(lfg.GetSearchResults)
        t.count = okR and show(count) or ("error: " .. tostring(count))
        t.results = {}
        for i, id in ipairs(okR and type(ids) == "table" and ids or {}) do
            if i > 25 then break end
            t.results[i] = result(lfg, id)
        end
        ns.Print(("LFG probe: the timer's search %s (%s results); /reload."):format(event == "LFG_LIST_SEARCH_FAILED" and "failed" or "came back", t.count))
    end)
    C_Timer.After(2, function()
        local ok, err = pcall(lfg.Search, cat)
        s.timerSearch.call = ok and "called" or ("error: " .. tostring(err))
        C_Timer.After(10, function()
            if not s.timerSearch.event then
                f:UnregisterAllEvents()
                s.timerSearch.event = "nothing came back in 10 seconds"
                ns.Print("LFG probe: the timer's search got no answer (saved); /reload.")
            end
        end)
    end)
end

-- A click: a search, and your listing saved again unchanged (only if you
-- have one), each with the game's verdict.
function LP.ClickTest()
    local s = store()
    local lfg = C_LFGList
    s.clickTest = { blocked = {} }
    local f = CreateFrame("Frame")
    for _, e in ipairs({ "LFG_LIST_SEARCH_RESULTS_RECEIVED", "LFG_LIST_SEARCH_FAILED", "LFG_LIST_ACTIVE_ENTRY_UPDATE",
                         "ADDON_ACTION_BLOCKED", "ADDON_ACTION_FORBIDDEN" }) do f:RegisterEvent(e) end
    f:SetScript("OnEvent", function(_, event, a1, a2)
        local t = s.clickTest
        t.blocked[#t.blocked + 1] = date("%H:%M:%S ") .. event .. " " .. tostring(a1) .. " " .. tostring(a2)
        if event == "LFG_LIST_SEARCH_RESULTS_RECEIVED" then
            local okR, count = pcall(lfg.GetSearchResults)
            t.count = okR and show(count) or "error"
        end
    end)
    local b = LP.button or CreateFrame("Button", nil, UIParent, "UIPanelButtonTemplate")
    LP.button = b
    b:SetSize(320, 30)
    b:ClearAllPoints()
    b:SetPoint("CENTER", UIParent, "CENTER", 0, 160)
    b:SetFrameStrata("DIALOG")
    b:SetText("LFG probe: click to search and re-save your listing")
    b:SetScript("OnClick", function(self)
        local t = s.clickTest
        local okCats, cats = pcall(lfg.GetAvailableCategories)
        local cat = okCats and cats and cats[1]
        local ok, err = pcall(lfg.Search, cat, 0, 0, nil, false, nil, nil)
        t.search = ok and "called" or ("error: " .. tostring(err))
        local okE, entry = pcall(lfg.GetActiveEntryInfo)
        if okE and type(entry) == "table" and not isSecret(entry) then
            local okU, errU = pcall(lfg.UpdateListing, { activityIDs = entry.activityIDs,
                newPlayerFriendly = entry.newPlayerFriendly, voiceMode = entry.voiceMode })
            t.update = okU and "called" or ("error: " .. tostring(errU))
        else
            t.update = "no listing: skipped"
        end
        self:Hide()
        C_Timer.After(5, function()
            f:UnregisterAllEvents()
            ns.Print("LFG probe: click test done; /reload.")
        end)
    end)
    b:Show()
    ns.Print("LFG probe: click the button at the top of the screen once.")
end

-- Watch for the game's verdict on what follows.
local function verdicts(list, seconds)
    local f = CreateFrame("Frame")
    for _, e in ipairs({ "ADDON_ACTION_BLOCKED", "ADDON_ACTION_FORBIDDEN", "CHANNEL_UI_UPDATE", "CHAT_MSG_CHANNEL_NOTICE",
                         "LFG_LIST_ACTIVE_ENTRY_UPDATE" }) do f:RegisterEvent(e) end
    f:SetScript("OnEvent", function(_, event, a1, a2)
        list[#list + 1] = date("%H:%M:%S ") .. event .. " " .. tostring(a1) .. " " .. tostring(a2)
    end)
    C_Timer.After(seconds or 5, function() f:UnregisterAllEvents() end)
end

local function windowsWith(channel)
    local out = {}
    for i = 1, (NUM_CHAT_WINDOWS or 10) do
        local list = { GetChatWindowChannels(i) }
        for j = 1, #list, 2 do
            if type(list[j]) == "string" and list[j]:lower() == channel:lower() then out[#out + 1] = i end
        end
    end
    return out
end

-- Join LookingForGroup (from your command), then take it off every chat
-- window: can the library read it without it showing in chat?
function LP.Join()
    local s = store()
    local t = { events = {} }
    s.join = t
    verdicts(t.events, 6)
    local ok, err = pcall(JoinChannelByName, "LookingForGroup")
    t.call = ok and "called" or ("error: " .. tostring(err))
    C_Timer.After(1.5, function()
        local okN, index, name = pcall(GetChannelName, "LookingForGroup")
        t.joined = okN and (tostring(index) .. " " .. tostring(name)) or "error"
        local before = windowsWith("LookingForGroup")
        t.windowsBefore = table.concat(before, ",")
        for _, i in ipairs(before) do
            local cf = _G["ChatFrame" .. i]
            if cf and cf.RemoveChannel then
                local okR, errR = pcall(cf.RemoveChannel, cf, "LookingForGroup")
                t["remove" .. i] = okR and "called" or ("error: " .. tostring(errR))
            end
        end
        C_Timer.After(1, function()
            t.windowsAfter = table.concat(windowsWith("LookingForGroup"), ",")
            ns.Print(("LFG probe: LookingForGroup %s, on windows %s, after removing: %s; /reload."):format(t.joined,
                t.windowsBefore ~= "" and t.windowsBefore or "none", t.windowsAfter ~= "" and t.windowsAfter or "none"))
        end)
    end)
end

-- Leave LookingForGroup, then join it again from a timer (nothing you
-- pressed behind it, as the library would at login).
function LP.TimerJoin()
    local s = store()
    local t = { events = {} }
    s.timerJoin = t
    verdicts(t.events, 8)
    pcall(LeaveChannelByName, "LookingForGroup")
    C_Timer.After(3, function()
        local ok, err = pcall(JoinChannelByName, "LookingForGroup")
        t.call = ok and "called" or ("error: " .. tostring(err))
        C_Timer.After(2, function()
            local okN, index, name = pcall(GetChannelName, "LookingForGroup")
            t.joined = okN and (tostring(index) .. " " .. tostring(name)) or "error"
            t.windows = table.concat(windowsWith("LookingForGroup"), ",")
            ns.Print(("LFG probe: joined from a timer: %s (windows %s); /reload."):format(t.joined, t.windows ~= "" and t.windows or "none"))
        end)
    end)
end

-- A button whose click removes your listing (you're delisted).
function LP.Delist()
    local s = store()
    local t = { events = {} }
    s.delist = t
    local lfg = C_LFGList
    local okH, has = pcall(lfg.HasActiveEntryInfo)
    t.listedBefore = okH and tostring(has) or "error"
    local b = LP.delistButton or CreateFrame("Button", nil, UIParent, "UIPanelButtonTemplate")
    LP.delistButton = b
    b:SetSize(320, 30)
    b:ClearAllPoints()
    b:SetPoint("CENTER", UIParent, "CENTER", 0, 160)
    b:SetFrameStrata("DIALOG")
    b:SetText("LFG probe: click to delist yourself")
    b:SetScript("OnClick", function(self)
        verdicts(t.events, 4)
        local ok, err = pcall(lfg.RemoveListing)
        t.call = ok and "called" or ("error: " .. tostring(err))
        self:Hide()
        C_Timer.After(2, function()
            local okA, after = pcall(lfg.HasActiveEntryInfo)
            t.listedAfter = okA and tostring(after) or "error"
            ns.Print(("LFG probe: listed before %s, after %s; /reload."):format(t.listedBefore, t.listedAfter))
        end)
    end)
    b:Show()
    ns.Print("LFG probe: click the button at the top of the screen to delist yourself.")
end

-- Forever's language preference (its "preferred play settings", which
-- shard players by language): what an addon can read of it, plus the
-- client's own locale and the tool's language filters.
function LP.Lang()
    local s = store()
    local t = {}
    s.lang = t
    t.clientLocale = tostring(GetLocale and GetLocale())
    local acc = C_AccountServices
    t.api = acc and "C_AccountServices" or "missing"
    local function read(label)
        if not acc then return end
        local ok, loaded, localeID, dcID, localeDate, dcDate, cooldown = pcall(acc.GetPreferredPlaySettings)
        t[label] = ok and ("loaded=%s locale=%s datacenter=%s localeChanged=%s cooldownDays=%s"):format(tostring(loaded),
            tostring(localeID), tostring(dcID), tostring(localeDate), tostring(cooldown)) or ("error: " .. tostring(loaded))
    end
    read("before")
    if acc then
        local okL, ids, names = pcall(acc.GetPreferredLocales)
        t.locales = {}
        if okL and type(ids) == "table" then
            for i, id in ipairs(ids) do t.locales[#t.locales + 1] = tostring(id) .. " " .. tostring(names and names[i]) end
        else
            t.locales[1] = "error: " .. tostring(ids)
        end
        local okD, dids, dnames = pcall(acc.GetPreferredDatacenterLocalities)
        t.datacenters = {}
        for i, id in ipairs(okD and type(dids) == "table" and dids or {}) do t.datacenters[#t.datacenters + 1] = tostring(id) .. " " .. tostring(dnames and dnames[i]) end
        local okF, canLocale, canDC = pcall(acc.GetPreferredPlaySettingsFeatures)
        t.features = okF and ("canChangeLocale=%s canChangeDatacenter=%s"):format(tostring(canLocale), tostring(canDC)) or "error"
    end
    -- the tool's language filters
    local lfg = C_LFGList
    if lfg then
        for _, fn in ipairs({ "GetLanguageSearchFilter", "GetDefaultLanguageSearchFilter", "GetAvailableLanguageSearchFilter" }) do
            local ok, v = pcall(lfg[fn])
            t[fn] = ok and show(v) or ("error: " .. tostring(v))
        end
    end
    -- ask for it, and read again when it comes
    local f = CreateFrame("Frame")
    f:RegisterEvent("PREFERRED_PLAY_SETTINGS_UPDATED")
    f:SetScript("OnEvent", function(self)
        self:UnregisterAllEvents()
        t.event = "PREFERRED_PLAY_SETTINGS_UPDATED"
        read("after")
        ns.Print("LFG probe: language preference read; /reload.")
    end)
    if acc and acc.RequestPreferredPlaySettings then
        local ok, started = pcall(acc.RequestPreferredPlaySettings)
        t.request = ok and tostring(started) or ("error: " .. tostring(started))
    end
    C_Timer.After(6, function()
        if not t.event then
            f:UnregisterAllEvents()
            read("after6s")
            ns.Print("LFG probe: language preference: no event in 6 seconds (saved); /reload.")
        end
    end)
end

-- The recorder: public chat as it arrives.
local recorder
local CHAT_EVENTS = { "CHAT_MSG_CHANNEL", "CHAT_MSG_SAY", "CHAT_MSG_YELL" }

local function record(event, text, author, _, channelName, _, _, _, _, channelBase)
    local s = store()
    local r = s.record
    if not (r and r.on) then return end
    -- every event that arrives, saved or not
    r.seen = r.seen or {}
    r.seen[event] = (r.seen[event] or 0) + 1
    local inInstance, kind = IsInInstance()
    local line = {
        date("%H:%M:%S"),
        event == "CHAT_MSG_CHANNEL" and (isSecret(channelBase) and "<secret>" or tostring(channelBase or channelName)) or event:sub(10):lower(),
        isSecret(author) and "<secret>" or tostring(author),
        isSecret(text) and "<secret>" or tostring(text),
        (InCombatLockdown() and "combat " or "") .. (inInstance and (tostring(kind) .. " ") or "") .. tostring(GetZoneText()),
    }
    r.lines[#r.lines + 1] = table.concat(line, " | ")
    if isSecret(text) then r.secret = (r.secret or 0) + 1 end
    while #r.lines > MAX_LINES do table.remove(r.lines, 1) end
end

local function arm()
    if recorder then return end
    recorder = CreateFrame("Frame")
    for _, e in ipairs(CHAT_EVENTS) do recorder:RegisterEvent(e) end
    recorder:SetScript("OnEvent", function(_, event, ...) record(event, ...) end)
end

function LP.Record(on)
    local s = store()
    s.record = s.record or { lines = {} }
    s.record.on = on and true or false
    if on then
        s.record.since = s.record.since or date("%Y-%m-%d %H:%M:%S")
        arm()
        ns.Print(("LFG recorder: on (%d lines so far); it keeps recording after /reload until \"/suu probe lfg stop\"."):format(#s.record.lines))
    else
        if recorder then recorder:UnregisterAllEvents() end
        ns.Print(("LFG recorder: off, %d lines kept; /reload to save them."):format(#s.record.lines))
    end
end

-- after a /reload: recording again if it was on
local resume = CreateFrame("Frame")
resume:RegisterEvent("PLAYER_LOGIN")
resume:SetScript("OnEvent", function()
    local s = SuuUIProbe and SuuUIProbe.lfg
    if s and s.record and s.record.on then arm() end
end)

function LP.Command(rest)
    rest = (rest or ""):lower()
    if rest == "record" then LP.Record(true) return end
    if rest == "stop" then LP.Record(false) return end
    if rest == "click" then LP.ClickTest() return end
    if rest == "join" then LP.Join() return end
    if rest == "timerjoin" then LP.TimerJoin() return end
    if rest == "lang" then LP.Lang() return end
    if rest == "delist" then LP.Delist() return end
    if rest == "clear" then
        local s = store()
        s.record = { lines = {}, on = s.record and s.record.on or false }
        ns.Print("LFG recorder: lines cleared.")
        return
    end
    LP.Snapshot()
    if rest == "timer" then LP.TimerSearch() end
    local s = store()
    ns.Print(("LFG probe: %d categories, %d channels saved; /reload."):format(#(s.categories or {}), #(s.channels or {})))
end
