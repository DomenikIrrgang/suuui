-- Libs/ForeverLFG/Interest.lua
-- What you're after, and which entries concern you.
--   your listing (its activities), your roles (GetLFGRoles), the quests in
--   your log, your level and zone, activities you watch, your friends and
--   guild; your languages (Forever's preferred play settings, the client's,
--   extras).
--
--   LFG.Interest()            -- { listed, roles, quests, level, zone, watches }
--   LFG.Watch(key, on)        -- an activity to hear about without listing
--   LFG.Watches()             -- { key = true } of those
--   LFG.Languages()           -- the language modules to read with
--   LFG.MatchReasons(entry)   -- { "role", "activity", ... } for one entry
--   events: Match(entry, newReasons), Contacted(entry, what)
--     reasons: "role" (a group for your activity needs your role),
--     "activity" (a group for your activity), "player" (a player for your
--     group), "quest" (a quest in your log), "zone" (open world in your
--     zone, near your level), "boss" (a world boss or event), "friend" (a
--     friend or guild member)
--     what (a group you whispered): "full", "gone", "reposted"

local _, ns = ...
local LFG = ns.LFG

local I = {}

I.watches = {}

--------------------------------------------------------------------------------
-- Languages
--------------------------------------------------------------------------------

-- Forever's preferred play locales by the names its API gives (probed:
-- English, LatAm Spanish, Brazilian Portuguese on NA).
local LOCALE_BY_NAME = { ["English"] = "enUS", ["LatAm Spanish"] = "esMX", ["Brazilian Portuguese"] = "ptBR" }

local function readPreferred()
    local acc = C_AccountServices
    if not (acc and acc.GetPreferredPlaySettings and acc.GetPreferredLocales) then return end
    local ok, loaded, localeID = pcall(acc.GetPreferredPlaySettings)
    if not (ok and loaded and localeID) then return end
    local okL, ids, names = pcall(acc.GetPreferredLocales)
    if not okL or type(ids) ~= "table" then return end
    for i, id in ipairs(ids) do
        if id == localeID then I.preferred = LOCALE_BY_NAME[names and names[i] or ""] end
    end
end

function LFG.Languages()
    local out, seen = {}, {}
    local function use(code) if code and not seen[code] then seen[code] = true; out[#out + 1] = code end end
    use(I.preferred)
    use(GetLocale and GetLocale())
    for code, on in pairs(LFG.config.extraLanguages or {}) do if on then use(code) end end
    return out
end

--------------------------------------------------------------------------------
-- What you're after
--------------------------------------------------------------------------------

local quests, social = {}, {}

local function readQuests()
    wipe(quests)
    local ql = C_QuestLog
    if not (ql and ql.GetNumQuestLogEntries and ql.GetInfo) then return end
    for i = 1, (ql.GetNumQuestLogEntries()) or 0 do
        local ok, info = pcall(ql.GetInfo, i)
        if ok and type(info) == "table" and not info.isHeader and info.questID then quests[info.questID] = true end
    end
end

-- Friends' characters (Battle.net) and guild members, by whole name.
local function readSocial()
    wipe(social)
    if IsInGuild() then
        for i = 1, (GetNumGuildMembers()) or 0 do
            local ok, name = pcall(GetGuildRosterInfo, i)
            if ok and type(name) == "string" then social[Ambiguate(name, "short")] = "guild" end
        end
    end
    local bn = C_BattleNet
    if bn and bn.GetFriendAccountInfo and BNGetNumFriends then
        for i = 1, (BNGetNumFriends()) or 0 do
            local ok, info = pcall(bn.GetFriendAccountInfo, i)
            local game = ok and type(info) == "table" and info.gameAccountInfo
            if game and type(game.characterName) == "string" then social[game.characterName] = "friend" end
        end
    end
end

local function zoneKey()
    local name = GetRealZoneText and GetRealZoneText()
    if type(name) ~= "string" then return nil end
    for _, a in ipairs(LFG.Catalogue.All("zone")) do
        if a.name == name then return a.key end
    end
end

function LFG.Interest()
    local listing = LFG.Listing and LFG.Listing()
    local roles = {}
    local ok, _, tank, healer, dps = pcall(GetLFGRoles)
    if ok then roles = { tank = tank or nil, healer = healer or nil, damage = dps or nil } end
    return {
        listed = listing and listing.activities or {}, listing = listing, roles = roles, quests = quests,
        level = UnitLevel("player"), zone = zoneKey(), watches = I.watches,
    }
end

function LFG.Watch(key, on)
    I.watches[key] = on and true or nil
end

function LFG.Watches() return I.watches end

--------------------------------------------------------------------------------
-- Matching
--------------------------------------------------------------------------------

local function expandSet(list, extra)
    local set = {}
    for _, key in ipairs(list or {}) do for _, k in ipairs(LFG.Catalogue.Expand(key)) do set[k] = true end end
    for key in pairs(extra or {}) do for _, k in ipairs(LFG.Catalogue.Expand(key)) do set[k] = true end end
    return set
end

local function anyIn(list, set)
    for _, key in ipairs(list or {}) do
        for _, k in ipairs(LFG.Catalogue.Expand(key)) do if set[k] then return true end end
    end
    return false
end

function LFG.MatchReasons(e, interest)
    if not e or e.you then return {} end
    interest = interest or LFG.Interest()
    local mine = expandSet(interest.listed, interest.watches)
    local reasons = {}
    local forMine = anyIn(e.activities, mine)
    if e.intent == "group" and forMine then
        reasons[#reasons + 1] = "activity"
        for role in pairs(e.roles.needed) do
            if interest.roles[role] then reasons[#reasons + 1] = "role" break end
        end
    end
    -- a player for your group: you're listed and lead a group (listed alone,
    -- you're a player looking yourself, found in game)
    if e.intent == "player" and forMine and interest.listing and IsInGroup() and UnitIsGroupLeader("player") then
        reasons[#reasons + 1] = "player"
    end
    for _, q in ipairs(e.quests) do if interest.quests[q] then reasons[#reasons + 1] = "quest" break end end
    for _, key in ipairs(e.activities) do
        local a = LFG.Catalogue.Get(key)
        if a and a.kind == "zone" and key == interest.zone then
            local lvl = e.level and e.level[1]
            if not lvl or math.abs(lvl - (interest.level or lvl)) <= 6 then reasons[#reasons + 1] = "zone" end
        elseif a and a.kind == "boss" then
            reasons[#reasons + 1] = "boss"
        end
    end
    local who = e.leader and e.leader.name or e.key
    if social[who] or social[Ambiguate and Ambiguate(who, "short") or who] then reasons[#reasons + 1] = "friend" end
    return reasons
end

-- Each entry's reasons so far: Match fires for new ones only.
local matched = setmetatable({}, { __mode = "k" })

local function check(e)
    local reasons = LFG.MatchReasons(e)
    local had = matched[e] or {}
    local new = {}
    for _, r in ipairs(reasons) do if not had[r] then new[#new + 1] = r; had[r] = true end end
    matched[e] = had
    if #new > 0 then LFG.Fire("Match", e, new) end
end

-- The groups you whispered: what happens to them.
local contacted = {}

local function contactedUpdate(e, removed)
    if not contacted[e.key] then return end
    if removed then
        contacted[e.key] = nil
        LFG.Fire("Contacted", e, "gone")
    elseif e.intent == "group" and e.need == 0 then
        LFG.Fire("Contacted", e, "full")
    end
end

local frame

LFG.AddPart({
    Start = function()
        readQuests()
        readSocial()
        readPreferred()
        if C_AccountServices and C_AccountServices.RequestPreferredPlaySettings then
            pcall(C_AccountServices.RequestPreferredPlaySettings)
        end
        frame = frame or CreateFrame("Frame")
        for _, ev in ipairs({ "QUEST_LOG_UPDATE", "GUILD_ROSTER_UPDATE", "BN_FRIEND_INFO_CHANGED",
                              "PREFERRED_PLAY_SETTINGS_UPDATED", "CHAT_MSG_WHISPER_INFORM" }) do
            pcall(frame.RegisterEvent, frame, ev)
        end
        frame:SetScript("OnEvent", function(_, event, a1, a2)
            if event == "QUEST_LOG_UPDATE" then readQuests()
            elseif event == "PREFERRED_PLAY_SETTINGS_UPDATED" then readPreferred()
            elseif event == "CHAT_MSG_WHISPER_INFORM" then
                -- you whispered someone: a leader you contacted
                if type(a2) == "string" and LFG.Entry(a2) then contacted[a2] = true end
            else readSocial() end
        end)
        I.onAdded = I.onAdded or function(e) check(e) end
        I.onUpdated = I.onUpdated or function(e) check(e); contactedUpdate(e) end
        I.onRefreshed = I.onRefreshed or function(e)
            if contacted[e.key] and e.intent == "group" and (e.need or 1) > 0 then LFG.Fire("Contacted", e, "reposted") end
        end
        I.onRemoved = I.onRemoved or function(e) contactedUpdate(e, true) end
        LFG.On("EntryAdded", I.onAdded)
        LFG.On("EntryUpdated", I.onUpdated)
        LFG.On("EntryRefreshed", I.onRefreshed)
        LFG.On("EntryRemoved", I.onRemoved)
    end,
    Stop = function()
        if frame then frame:UnregisterAllEvents() end
        LFG.Off("EntryAdded", I.onAdded)
        LFG.Off("EntryUpdated", I.onUpdated)
        LFG.Off("EntryRefreshed", I.onRefreshed)
        LFG.Off("EntryRemoved", I.onRemoved)
    end,
})
