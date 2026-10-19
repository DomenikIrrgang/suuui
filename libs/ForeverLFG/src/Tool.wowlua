-- Libs/ForeverLFG/Tool.lua
-- The tool source: the game's group finder (C_LFGList, its vanilla-style
-- UI on Forever). Probed 2026-10-14:
--   - a search works from your click or key press, never from a timer
--     (ADDON_ACTION_BLOCKED), so LFG.Refresh must be called from a click;
--     results go stale and the library says so (ToolStale);
--   - creating or updating a listing is blocked for addon code (the Group
--     Finder module hosts the game's own listing panel for that);
--   - RemoveListing works from a click (LFG.Delist);
--   - joining: no sign-up on Forever; Invite only for single players.
--
--   LFG.Refresh(categoryID)  -- from a click; Dungeons when nil
--   LFG.Listing()            -- your listing, or nil
--   LFG.Delist()             -- from a click
--   LFG.CanInvite(entry) / LFG.Invite(entry) / LFG.Whisper(entry)
--   LFG.ToolAge(categoryID)  -- seconds since its last search, or nil
--   events: ToolSearched(categoryID, count), ToolSearchFailed(categoryID),
--           ToolStale(categoryID, age), ListingChanged(listing|nil),
--           ListingExpiring(secondsLeft), Delisted()

local _, ns = ...
local LFG = ns.LFG

local T = {}
LFG.Tool = T

local isSecret = issecretvalue or function() return false end
local DUNGEONS = 2

local frame, ticker
T.lastSearch = {}       -- categoryID -> time
T.staleFired = {}       -- categoryID -> true once ToolStale went out
T.pending = nil

local function lfg() return C_LFGList end

local function tableOK(t) return type(t) == "table" and not isSecret(t) end

-- One result as the store's tool source.
local function readResult(id, category)
    local L = lfg()
    local ok, info = pcall(L.GetSearchResultInfo, id)
    if not ok or not tableOK(info) then return nil end
    local acts = {}
    for _, a in ipairs(info.activityIDs or { info.activityID }) do
        acts[#acts + 1] = LFG.Catalogue.ForTool(a) or ("tool:" .. a)
    end
    local data = {
        resultID = id, category = category, activities = acts,
        intent = (info.numMembers or 0) <= 1 and "player" or "group",
        comment = info.comment, age = info.age, delisted = info.isDelisted,
        newPlayerFriendly = info.newPlayerFriendly, playstyle = info.generalPlaystyle,
        self = info.hasSelf, needed = {}, offered = {}, seenAt = LFG.Now(),
    }
    local okC, counts = pcall(L.GetSearchResultMemberCounts, id)
    -- (for a single player these are a whole group's open spots: not theirs)
    if data.intent == "group" and okC and tableOK(counts) then
        local need = 0
        for role, field in pairs({ tank = "TANK_REMAINING", healer = "HEALER_REMAINING", damage = "DAMAGER_REMAINING" }) do
            local n = counts[field]
            if type(n) == "number" and n > 0 then data.needed[role] = n; need = need + n end
        end
        if data.intent == "group" then data.need = need end
        -- what it has: its members by the role each chose (the game doesn't
        -- enforce roles, so the remaining ones above can add up to more than
        -- the free spots: a group of four damage dealers still needs a tank
        -- and a healer, found in game)
        local has = {}
        for role, field in pairs({ tank = "TANK", healer = "HEALER", damage = "DAMAGER", none = "NOROLE" }) do
            local n = counts[field]
            if type(n) == "number" and n > 0 then has[role] = n end
        end
        data.has = has
    end
    local okL, leader = pcall(L.GetSearchResultLeaderInfo, id)
    if okL and tableOK(leader) then
        data.leader = { name = leader.name, class = leader.classFilename, level = leader.level }
        local roles = leader.lfgRoles
        if data.intent == "player" and tableOK(roles) then
            data.offered = { tank = roles.tank or nil, healer = roles.healer or nil, damage = roles.dps or nil }
        end
    end
    local first = LFG.Catalogue.Get(acts[1] or "")
    local size = first and first.size
    data.members = { info.numMembers or 1, size or 5 }
    local name = (data.leader and data.leader.name) or info.leaderName
    return (type(name) == "string" and not isSecret(name)) and name or ("tool:" .. id), data
end

-- Results by ID: the key each is stored under (a result's leader name
-- often comes a moment after the search, found in game: "tool:<id>" until then).
T.keys = {}

local function store(id, key, data)
    local old = T.keys[id]
    if old and old ~= key then LFG.Store.Rename(old, key) end
    T.keys[id] = key
    if data.delisted then LFG.Store.Drop(key, "tool", "delisted")
    else LFG.Store.Put(key, "tool", data) end
end

local function received()
    local L = lfg()
    local ok, count, ids = pcall(L.GetSearchResults)
    if not ok or not tableOK(ids) then T.pending = nil return end
    -- the category searched: ours, or (the game's own panel searched) the
    -- one its results are in
    local category = T.pending
    T.pending = nil
    if not category then
        for _, id in ipairs(ids) do
            local okI, info = pcall(L.GetSearchResultInfo, id)
            local first = okI and tableOK(info) and info.activityIDs and info.activityIDs[1]
            local a = first and LFG.Catalogue.Get(LFG.Catalogue.ForTool(first) or ("tool:" .. first))
            if a and a.category then category = a.category break end
        end
    end
    category = category or DUNGEONS
    local seen = {}
    for _, id in ipairs(ids) do
        local key, data = readResult(id, category)
        if key then
            seen[key] = true
            store(id, key, data)
        end
    end
    -- the ones this category's search no longer has
    local gone = {}
    LFG.Store.Each(function(key, e)
        local tool = e.sources.tool
        if tool and tool.category == category and not seen[key] then gone[#gone + 1] = key end
    end)
    for _, key in ipairs(gone) do LFG.Store.Drop(key, "tool", "gone") end
    T.lastSearch[category] = LFG.Now()
    T.staleFired[category] = nil
    LFG.Fire("ToolSearched", category, count)
end

local function updated(id)
    local category
    LFG.Store.Each(function(_, e)
        if e.sources.tool and e.sources.tool.resultID == id then category = e.sources.tool.category end
    end)
    local key, data = readResult(id, category)
    if not key then return end
    store(id, key, data)
end


--------------------------------------------------------------------------------
-- From a click
--------------------------------------------------------------------------------

function LFG.Refresh(category)
    local L = lfg()
    if not (L and L.Search) then return false end
    category = category or DUNGEONS
    T.pending = category
    local ok = pcall(L.Search, category, 0, 0, nil, false, nil, nil)
    return ok
end

function LFG.ToolAge(category)
    local t = T.lastSearch[category or DUNGEONS]
    return t and (LFG.Now() - t) or nil
end

function LFG.Listing()
    local L = lfg()
    if not (L and L.HasActiveEntryInfo) then return nil end
    local okH, has = pcall(L.HasActiveEntryInfo)
    if not okH or not has then return nil end
    local ok, info = pcall(L.GetActiveEntryInfo)
    if not ok or not tableOK(info) then return nil end
    local acts = {}
    for _, a in ipairs(info.activityIDs or {}) do acts[#acts + 1] = LFG.Catalogue.ForTool(a) or ("tool:" .. a) end
    local okR, leader, tank, healer, dps = pcall(GetLFGRoles)
    -- the category: the first activity's
    local category
    local first = info.activityIDs and info.activityIDs[1]
    local okA, a = pcall(L.GetActivityInfoTable, first)
    if okA and type(a) == "table" then category = a.categoryID end
    return {
        activities = acts, comment = info.comment, playstyle = info.generalPlaystyle, duration = info.duration,
        voiceMode = info.voiceMode, newPlayerFriendly = info.newPlayerFriendly, category = category,
        roles = okR and { leader = leader or nil, tank = tank or nil, healer = healer or nil, damage = dps or nil } or {},
    }
end

function LFG.Delist()
    local L = lfg()
    if L and L.RemoveListing then return pcall(L.RemoveListing) end
end

function LFG.CanInvite(e)
    if not (e and e.intent == "player") or e.you then return false end
    if IsInGroup() and not (UnitIsGroupLeader("player") or UnitIsGroupAssistant("player")) then return false end
    return true
end

function LFG.Invite(e)
    if not LFG.CanInvite(e) then return end
    local invite = (C_PartyInfo and C_PartyInfo.InviteUnit) or InviteUnit
    if invite then pcall(invite, e.key) end
end

-- An empty whisper to the leader.
function LFG.Whisper(e)
    if not e then return end
    local tell = (ChatFrameUtil and ChatFrameUtil.SendTell) or ChatFrame_SendTell
    if tell then tell(e.key) end
end

--------------------------------------------------------------------------------
-- Staleness, your listing
--------------------------------------------------------------------------------

local wasListed, expiringFired

local function watchedCategories()
    local cats = {}
    local listing = LFG.Listing()
    local function addFor(key)
        for _, k in ipairs(LFG.Catalogue.Expand(key)) do
            local a = LFG.Catalogue.Get(k)
            if a and a.category then cats[a.category] = true end
        end
    end
    for _, key in ipairs(listing and listing.activities or {}) do addFor(key) end
    for key in pairs(LFG.Watches and LFG.Watches() or {}) do addFor(key) end
    return cats, listing
end

local function tick()
    LFG.Store.Expire()
    local cats, listing = watchedCategories()
    local limit = LFG.config.staleAfter or 300
    for category in pairs(cats) do
        local age = LFG.ToolAge(category)
        if (not age or age > limit) and not T.staleFired[category] then
            T.staleFired[category] = true
            LFG.Fire("ToolStale", category, age)
        end
    end
    -- your listing running out
    if listing and type(listing.duration) == "number" then
        if listing.duration <= (LFG.config.expiringSoon or 120) and not expiringFired then
            expiringFired = true
            LFG.Fire("ListingExpiring", listing.duration)
        elseif listing.duration > (LFG.config.expiringSoon or 120) then
            expiringFired = nil
        end
    end
end

local function listingChanged()
    local listing = LFG.Listing()
    LFG.Fire("ListingChanged", listing)
    if wasListed and not listing then LFG.Fire("Delisted") end
    wasListed = listing ~= nil
    expiringFired = nil
end

LFG.AddPart({
    Start = function()
        frame = frame or CreateFrame("Frame")
        for _, e in ipairs({ "LFG_LIST_SEARCH_RESULTS_RECEIVED", "LFG_LIST_SEARCH_FAILED",
                             "LFG_LIST_SEARCH_RESULT_UPDATED", "LFG_LIST_ACTIVE_ENTRY_UPDATE" }) do
            pcall(frame.RegisterEvent, frame, e)
        end
        frame:SetScript("OnEvent", function(_, event, a1)
            if event == "LFG_LIST_SEARCH_RESULTS_RECEIVED" then received()
            elseif event == "LFG_LIST_SEARCH_FAILED" then
                LFG.Fire("ToolSearchFailed", T.pending)
                T.pending = nil
            elseif event == "LFG_LIST_SEARCH_RESULT_UPDATED" then updated(a1)
            elseif event == "LFG_LIST_ACTIVE_ENTRY_UPDATE" then listingChanged() end
        end)
        LFG.Catalogue.ReadTool()
        wasListed = LFG.Listing() ~= nil
        ticker = ticker or C_Timer.NewTicker(10, tick)
    end,
    Stop = function()
        if frame then frame:UnregisterAllEvents() end
        if ticker then ticker:Cancel(); ticker = nil end
    end,
})
