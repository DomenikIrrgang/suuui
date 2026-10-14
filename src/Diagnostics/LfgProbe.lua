-- Diagnostics/LfgProbe.lua
-- "/suu probe lfg": what ForeverLFG (the group finder library: the game's
-- tool and the public chat channels as one list) can rely on.
--   The tool: its categories and activities (Dungeons, Quests & Zones,
--   Custom, ...), its functions, your own listing, and a search started
--   two seconds later from a timer (no key or click behind it: can the
--   library refresh by itself, for "a new group needs your role"?), with
--   what a result holds and whether any of it is secret.
--   Chat: the channels you're in.
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
        local okA, acts = pcall(lfg.GetAvailableActivities, cat)
        for i, a in ipairs(okA and acts or {}) do
            if i > 60 then entry.activities[#entry.activities + 1] = "... " .. #acts .. " in all" break end
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

-- The recorder: public chat as it arrives.
local recorder
local CHAT_EVENTS = { "CHAT_MSG_CHANNEL", "CHAT_MSG_SAY", "CHAT_MSG_YELL" }

local function record(event, text, author, _, channelName, _, _, _, _, channelBase)
    local s = store()
    local r = s.record
    if not (r and r.on) then return end
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
    if rest == "clear" then
        local s = store()
        s.record = { lines = {}, on = s.record and s.record.on or false }
        ns.Print("LFG recorder: lines cleared.")
        return
    end
    LP.Snapshot()
    LP.TimerSearch()
    local s = store()
    ns.Print(("LFG probe: %d categories, %d channels; a search from a timer in 2 seconds..."):format(#(s.categories or {}), #(s.channels or {})))
end
