-- Diagnostics/SocialProbe.lua
-- "/suu probe social": what Forever's social APIs give an addon, for
-- SuuUI's Social, Guild and Group Finder windows and the friends' online
-- notifications (step 3.4). Saved in SuuUIProbe.social on /reload.
--   * friends (C_FriendList), Battle.net friends (C_BattleNet), the guild
--     (roster, ranks, notes and what you may edit, the message of the day),
--     the raid
--   * the group finder: C_LFGList's functions, categories, activities
--   * Blizzard's frames for all of it (FriendsFrame, CommunitiesFrame,
--     LFGListFrame...) and their tabs
--   * how the game announces people coming online and going offline: the
--     global strings, the chat filter API, which events exist; and for ten
--     minutes after the command, every such event as it comes (with its
--     text), so log in a friend or wait for a guild member
--
--   /suu probe social    then play a while, then /reload

local _, ns = ...

local SP = {}
ns.SocialProbe = SP

local isSecret = issecretvalue or function() return false end

local function show(v, depth)
    depth = depth or 0
    if isSecret(v) then return "secret" end
    if v == nil then return "nil" end
    if type(v) == "table" then
        if depth > 2 then return "{…}" end
        local parts = {}
        for k, x in pairs(v) do
            parts[#parts + 1] = tostring(k) .. "=" .. show(x, depth + 1)
            if #parts > 40 then break end
        end
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

local function raw(fn, ...)
    if type(fn) ~= "function" then return nil end
    local ok, a, b, c, d, e = pcall(fn, ...)
    if ok then return a, b, c, d, e end
end

local function namesIn(t)
    local out = {}
    if type(t) ~= "table" then return { "missing" } end
    for k, v in pairs(t) do if type(k) == "string" and type(v) == "function" then out[#out + 1] = k end end
    table.sort(out)
    return out
end

local PRESENCE_EVENTS = { "FRIENDLIST_UPDATE", "BN_FRIEND_ACCOUNT_ONLINE", "BN_FRIEND_ACCOUNT_OFFLINE",
    "BN_FRIEND_INFO_CHANGED", "BN_CONNECTED", "GUILD_ROSTER_UPDATE", "CHAT_MSG_SYSTEM",
    "CHAT_MSG_BN_INLINE_TOAST_ALERT", "CHAT_MSG_GUILD_ACHIEVEMENT", "CLUB_MEMBER_PRESENCE_UPDATED",
    "GUILD_MOTD", "PLAYER_GUILD_UPDATE" }

local function frameInfo(name)
    local f = _G[name]
    if not f then return "missing" end
    local tabs = {}
    for i = 1, 8 do
        local t = _G[name .. "Tab" .. i]
        if t then
            local fs = t.Text or t.text
            tabs[#tabs + 1] = i .. ":" .. show(fs and fs:GetText())
        end
    end
    return ("shown=%s protected=%s w=%s h=%s tabs=%s"):format(show(f:IsShown()), show(f:IsProtected()),
        show(f:GetWidth()), show(f:GetHeight()), table.concat(tabs, " "))
end

function SP.Sample()
    SuuUIProbe = SuuUIProbe or {}
    local store = SuuUIProbe.social or {}
    SuuUIProbe.social = store
    store.at = date("%Y-%m-%d %H:%M:%S")
    store.level, store.class = UnitLevel("player"), select(2, UnitClass("player"))
    -- friends
    local fl = C_FriendList
    store.friends = {
        count = call(fl and fl.GetNumFriends), online = call(fl and fl.GetNumOnlineFriends),
        api = namesIn(fl), first = {},
    }
    for i = 1, math.min(4, tonumber((raw(fl and fl.GetNumFriends))) or 0) do
        store.friends.first[i] = call(fl.GetFriendInfoByIndex, i)
    end
    store.ignores = call(fl and fl.GetNumIgnores)
    -- Battle.net
    store.bnet = { count = call(BNGetNumFriends), api = namesIn(C_BattleNet), first = {},
                   connected = call(BNConnected), myInfo = call(BNGetInfo) }
    local bnCount = (raw(BNGetNumFriends))
    store.bnet.games = {}
    for i = 1, math.min(4, tonumber(bnCount) or 0) do
        store.bnet.first[i] = call(C_BattleNet and C_BattleNet.GetFriendAccountInfo, i)
        -- what they're playing: each game account (character, zone, client)
        local n = (raw(C_BattleNet and C_BattleNet.GetFriendNumGameAccounts, i))
        store.bnet.games[i] = { count = show(n) }
        for j = 1, math.min(3, tonumber(n) or 0) do
            store.bnet.games[i][j] = call(C_BattleNet.GetFriendGameAccountInfo, i, j)
        end
    end
    -- the guild
    store.guild = {
        inGuild = call(IsInGuild), info = call(GetGuildInfo, "player"), members = call(GetNumGuildMembers),
        motd = call(GetGuildRosterMOTD), ranks = call(GuildControlGetNumRanks),
        canEditPublic = call(CanEditPublicNote), canEditOfficer = call(CanEditOfficerNote),
        canViewOfficer = call(C_GuildInfo and C_GuildInfo.CanViewOfficerNote), canInvite = call(CanGuildInvite),
        canRemove = call(CanGuildRemove), canPromote = call(CanGuildPromote), isLeader = call(IsGuildLeader),
        guildInfoApi = namesIn(C_GuildInfo), clubApi = namesIn(C_Club), first = {}, rankNames = {},
    }
    for i = 1, math.min(5, tonumber((raw(GetNumGuildMembers))) or 0) do
        store.guild.first[i] = call(GetGuildRosterInfo, i)
    end
    for i = 1, math.min(10, tonumber((raw(GuildControlGetNumRanks))) or 0) do
        store.guild.rankNames[i] = call(GuildControlGetRankName, i)
    end
    -- the guild's community: its chat streams (the Guild window's Chat)
    local clubID = raw(C_Club and C_Club.GetGuildClubId)
    store.guild.club = show(clubID)
    if clubID then
        store.guild.clubInfo = call(C_Club.GetClubInfo, clubID)
        store.guild.streams = call(C_Club.GetStreams, clubID)
        store.guild.memberCount = show(#(raw(C_Club.GetClubMembers, clubID) or {}))
        local me = raw(C_Club.GetMemberInfoForSelf, clubID)
        store.guild.self = show(me)
    end
    store.guild.news = call(C_GuildInfo and C_GuildInfo.GetGuildNewsInfo, 1)
    store.guild.events = call(GetNumGuildEvents)
    -- the raid
    store.raid = { inRaid = call(IsInRaid), members = call(GetNumGroupMembers), first = call(GetRaidRosterInfo, 1) }
    -- the group finder
    local lfg = C_LFGList
    store.lfg = { api = namesIn(lfg), categories = {}, active = call(lfg and lfg.HasActiveEntryInfo) }
    local cats = raw(lfg and lfg.GetAvailableCategories) or {}
    for i, cat in ipairs(cats) do
        if i > 12 then break end
        local c = { id = cat, info = call(lfg.GetLfgCategoryInfo or lfg.GetCategoryInfo, cat), activities = {} }
        local acts = raw(lfg.GetAvailableActivities, cat) or {}
        c.activityCount = #acts
        for j, a in ipairs(acts) do
            if j > 6 then break end
            c.activities[j] = show(a) .. " " .. call(lfg.GetActivityInfoTable, a)
        end
        store.lfg.categories[#store.lfg.categories + 1] = c
    end
    store.lfgBrowse = namesIn(C_LFGBrowse)
    store.lfg.activeEntry = call(lfg and lfg.GetActiveEntryInfo)
    store.lfg.filters = call(lfg and lfg.GetAvailableLanguageSearchFilter)
    -- Blizzard's frames
    store.frames = {}
    for _, name in ipairs({ "FriendsFrame", "CommunitiesFrame", "GuildFrame", "LFGListFrame", "PVEFrame",
                            "LFGParentFrame", "LFGBrowseFrame", "GroupFinderFrame", "RaidFrame", "WhoFrame",
                            "ChannelFrame", "BNToastFrame", "GuildMicroButton", "LFDMicroButton",
                            "SocialsMicroButton", "FriendsMicroButton", "QuickJoinToastButton" }) do
        store.frames[name] = frameInfo(name)
    end
    -- how online and offline are announced
    store.strings = {
        ERR_FRIEND_ONLINE_SS = show(ERR_FRIEND_ONLINE_SS), ERR_FRIEND_OFFLINE_S = show(ERR_FRIEND_OFFLINE_S),
        BN_INLINE_TOAST_FRIEND_ONLINE = show(BN_INLINE_TOAST_FRIEND_ONLINE),
        BN_INLINE_TOAST_FRIEND_OFFLINE = show(BN_INLINE_TOAST_FRIEND_OFFLINE),
        GUILD_MEMBER_ONLINE = show(_G.GUILD_MEMBER_ONLINE), GUILD_MEMBER_OFFLINE = show(_G.GUILD_MEMBER_OFFLINE),
    }
    store.chatFilter = {
        util = (ChatFrameUtil and ChatFrameUtil.AddMessageEventFilter) and "ChatFrameUtil.AddMessageEventFilter" or "missing",
        global = ChatFrame_AddMessageEventFilter and "ChatFrame_AddMessageEventFilter" or "missing",
    }
    local valid = C_EventUtils and C_EventUtils.IsEventValid
    store.eventsValid = {}
    for _, e in ipairs(PRESENCE_EVENTS) do store.eventsValid[e] = valid and tostring(valid(e)) or "?" end
    return store
end

-- Ten minutes of presence events, as they come.
local listener
function SP.Listen(store)
    store.events = store.events or {}
    if not listener then listener = CreateFrame("Frame") end
    listener:UnregisterAllEvents()
    local valid = C_EventUtils and C_EventUtils.IsEventValid
    for _, e in ipairs(PRESENCE_EVENTS) do
        if not valid or valid(e) then listener:RegisterEvent(e) end
    end
    local untilTime = GetTime() + 600
    listener:SetScript("OnEvent", function(_, event, ...)
        if GetTime() > untilTime then listener:UnregisterAllEvents() return end
        local events = SuuUIProbe.social.events
        -- the roster's own updates come in floods: a count, not each
        if event == "GUILD_ROSTER_UPDATE" or event == "FRIENDLIST_UPDATE" or event == "BN_FRIEND_INFO_CHANGED" then
            events.counts = events.counts or {}
            events.counts[event] = (events.counts[event] or 0) + 1
            return
        end
        if #events >= 60 then return end
        local args = {}
        for i = 1, math.min(14, select("#", ...)) do args[i] = show((select(i, ...))) end
        events[#events + 1] = date("%H:%M:%S") .. " " .. event .. ": " .. table.concat(args, " | "):sub(1, 400)
    end)
end

-- One group finder search in the first category: whether an addon may
-- search, and what a result looks like.
function SP.Search(store)
    local lfg = C_LFGList
    local cat = (raw(lfg and lfg.GetAvailableCategories) or {})[1]
    store.lfgSearch = { category = show(cat) }
    if not cat then return end
    local f = CreateFrame("Frame")
    f:RegisterEvent("LFG_LIST_SEARCH_RESULTS_RECEIVED")
    f:RegisterEvent("LFG_LIST_SEARCH_FAILED")
    f:SetScript("OnEvent", function(self, event)
        self:UnregisterAllEvents()
        local s = SuuUIProbe.social.lfgSearch
        s.event = event
        local count, list = raw(lfg.GetSearchResults)
        s.count = show(count)
        s.results = {}
        for i, id in ipairs(list or {}) do
            if i > 4 then break end
            s.results[i] = call(lfg.GetSearchResultInfo, id)
            s["members" .. i] = call(lfg.GetSearchResultMemberCounts, id)
            s["leader" .. i] = call(lfg.GetSearchResultMemberInfo, id, 1)
        end
    end)
    store.lfgSearch.call = call(lfg.Search, cat)
end

-- Forever's two-part names ("Suther Stargazer"): what each API gives for
-- your own character, and the C_PlayerInfo functions there are.
function SP.Names()
    SuuUIProbe = SuuUIProbe or {}
    local n = { at = date("%Y-%m-%d %H:%M:%S") }
    SuuUIProbe.names = n
    n.UnitName = call(UnitName, "player")
    n.UnitFullName = call(UnitFullName, "player")
    n.GetUnitName = call(GetUnitName, "player", true)
    n.UnitNameUnmodified = call(UnitNameUnmodified, "player")
    n.UnitNameFull = call(_G.UnitNameFull, "player")
    n.UnitNameWithSurname = call(_G.UnitNameWithSurname, "player")
    n.realm = call(GetNormalizedRealmName)
    n.guid = call(UnitGUID, "player")
    n.byGUID = call(GetPlayerInfoByGUID, UnitGUID("player"))
    n.playerInfoApi = namesIn(C_PlayerInfo)
    local surname = {}
    for k, v in pairs(_G) do
        if type(k) == "string" and type(v) == "function" and (k:lower():find("surname") or k:lower():find("fullname")) then
            surname[#surname + 1] = k .. " = " .. call(v, "player")
        end
    end
    table.sort(surname)
    n.globals = surname
    local club = raw(C_Club and C_Club.GetGuildClubId)
    n.clubSelf = club and call(C_Club.GetMemberInfoForSelf, club) or "no guild"
    n.target = call(UnitName, "target")
    n.targetFull = call(UnitFullName, "target")
    ns.Print("Names probe: saved; /reload. (Target another player first if you can.)")
    return n
end

-- What the windows are made of: each child (its key on the parent, or its
-- global name), shown, protected, size, and its own children two levels
-- down. Open each window once before (they load on first use).
local function children(f, depth, out, prefix)
    if depth > 3 or not f or not f.GetChildren then return end
    -- keys on the parent, for frames without a global name
    local keys = {}
    for k, v in pairs(f) do if type(k) == "string" and type(v) == "table" and v.GetObjectType then keys[v] = k end end
    for _, c in ipairs({ f:GetChildren() }) do
        if #out >= 400 then return end
        local name = c:GetName() or keys[c] or "?"
        local text = ""
        local fs = c.Text or c.text or (c.GetFontString and c:GetFontString())
        if fs and fs.GetText then text = " \"" .. show(fs:GetText()) .. "\"" end
        out[#out + 1] = ("%s%s [%s] shown=%s prot=%s %dx%d%s"):format(prefix, name, c:GetObjectType(), show(c:IsShown()),
            show(c:IsProtected()), math.floor(c:GetWidth() or 0), math.floor(c:GetHeight() or 0), text)
        children(c, depth + 1, out, prefix .. "  ")
    end
end

function SP.Frames()
    SuuUIProbe = SuuUIProbe or {}
    local store = { at = date("%Y-%m-%d %H:%M:%S") }
    SuuUIProbe.socialFrames = store
    for _, addon in ipairs({ "Blizzard_Communities", "Blizzard_GuildUI", "Blizzard_RaidUI", "Blizzard_LookingForGroupUI" }) do
        if C_AddOns and C_AddOns.LoadAddOn then pcall(C_AddOns.LoadAddOn, addon) end
    end
    for _, name in ipairs({ "FriendsFrame", "RaidFrame", "CommunitiesFrame", "LFGParentFrame", "LFGBrowseFrame",
                            "LFGListingFrame", "WhoFrame" }) do
        local f = _G[name]
        local out = {}
        if f then children(f, 1, out, "") end
        store[name] = f and out or "missing"
    end
    -- the functions that open them
    store.openers = {}
    for _, fn in ipairs({ "ToggleFriendsFrame", "ToggleGuildFrame", "ToggleCommunitiesFrame", "ToggleLFGParentFrame",
                          "ToggleRaidFrame", "FriendsFrame_ShowSubFrame", "ToggleLFDParentFrame", "PVEFrame_ToggleFrame" }) do
        store.openers[fn] = type(_G[fn])
    end
    ns.Print("Social frames probe: saved; /reload.")
end

-- What's under the mouse, and every shown frame named like a social one:
-- for windows that aren't the ones probed before (Forever's own friends
-- window). Hover the window, then run it.
function SP.Mouse()
    SuuUIProbe = SuuUIProbe or {}
    local store = { at = date("%Y-%m-%d %H:%M:%S"), chain = {}, named = {}, tree = {} }
    SuuUIProbe.socialMouse = store
    local foci = GetMouseFoci and GetMouseFoci() or { GetMouseFocus and GetMouseFocus() }
    local top
    local f = foci and foci[1]
    local guard = 0
    while f and guard < 20 do
        local name = f.GetName and f:GetName() or "?"
        store.chain[#store.chain + 1] = ("%s [%s] prot=%s %dx%d"):format(tostring(name), f.GetObjectType and f:GetObjectType() or "?",
            show(f.IsProtected and f:IsProtected()), math.floor((f.GetWidth and f:GetWidth()) or 0), math.floor((f.GetHeight and f:GetHeight()) or 0))
        if f.GetName and f:GetName() then top = f end
        f = f.GetParent and f:GetParent()
        if f == UIParent then break end
        guard = guard + 1
    end
    for k, v in pairs(_G) do
        if type(k) == "string" and type(v) == "table" and v.IsShown and v.GetObjectType
            and (k:find("Friend") or k:find("Social") or k:find("Contact")) then
            local ok, shown = pcall(v.IsShown, v)
            if ok and shown then store.named[#store.named + 1] = k .. " [" .. v:GetObjectType() .. "]" end
        end
    end
    table.sort(store.named)
    -- the topmost named frame under the mouse: what it's made of
    if top then
        store.top = top:GetName()
        children(top, 1, store.tree, "")
    end
    ns.Print(("Mouse probe: %s under the mouse; /reload."):format(tostring(store.top)))
end

-- Recent Allies and Friend Requests: what their APIs give.
function SP.Lists()
    SuuUIProbe = SuuUIProbe or {}
    local store = { at = date("%Y-%m-%d %H:%M:%S") }
    SuuUIProbe.socialLists = store
    local ra = C_RecentAllies
    store.recentApi = namesIn(ra)
    store.recentEnabled = call(ra and ra.IsSystemEnabled)
    store.recentReady = call(ra and ra.IsRecentAllyDataReady)
    -- (TryRequestRecentAlliesData is protected: an addon's call is blocked)
    local list = raw(ra and ra.GetRecentAllies) or {}
    store.recentCount = #list
    store.recent = {}
    for i, a in ipairs(list) do
        if i > 4 then break end
        store.recent[i] = show(a, 0)
        local inter = a.interactionData and a.interactionData.interactions
        store["interactions" .. i] = show(inter, -2)
    end
    store.invites = { count = call(BNGetNumFriendInvites), first = call(BNGetFriendInviteInfo, 1),
                      accept = type(BNAcceptFriendInvite), decline = type(BNDeclineFriendInvite),
                      cbn = call(C_BattleNet and C_BattleNet.GetFriendInviteInfo, 1) }
    -- the lists' own frames: what their rows hold (the first row's keys)
    local f = _G.SocialUIFrame
    for _, key in ipairs({ "RecentAlliesList", "FriendRequestsList" }) do
        local lst = f and f[key]
        local box = lst and lst.ScrollBox
        local target = box and box.ScrollTarget
        local first = target and select(1, target:GetChildren())
        local keys = {}
        if first then for k in pairs(first) do if type(k) == "string" then keys[#keys + 1] = k end end end
        table.sort(keys)
        store[key] = { shown = show(lst and lst:IsShown()), rowKeys = keys }
    end
    -- the side buttons: their fields (which page each opens)
    store.sideButtons = {}
    if f then
        for _, c in ipairs({ f:GetChildren() }) do
            if c:GetObjectType() == "Button" and not c:GetName() and math.abs((c:GetWidth() or 0) - 54) < 3 then
                local fields = {}
                for k, v in pairs(c) do
                    if type(k) == "string" and type(v) ~= "table" and type(v) ~= "function" then fields[#fields + 1] = k .. "=" .. tostring(v) end
                end
                table.sort(fields)
                store.sideButtons[#store.sideButtons + 1] = ("top=%d %s"):format(math.floor(c:GetTop() or 0), table.concat(fields, " "))
            end
        end
    end
    ns.Print(("Lists probe: %d recent allies, %s friend requests; /reload."):format(store.recentCount, tostring(store.invites.count)))
end

function SP.Command(rest)
    if rest == "names" then SP.Names() return end
    if rest == "lists" then SP.Lists() return end
    if rest == "mouse" then SP.Mouse() return end
    if rest == "frames" then SP.Frames() return end
    -- the roster asked for first: it's often empty until then
    if C_GuildInfo and C_GuildInfo.GuildRoster then pcall(C_GuildInfo.GuildRoster) elseif GuildRoster then pcall(GuildRoster) end
    local store = SP.Sample()
    SP.Listen(store)
    SP.Search(store)
    -- again once the roster has come in
    C_Timer.After(3, function() SP.Sample() end)
    ns.Print(("Social probe: %s friends, %s Battle.net friends, guild members %s. Listening for online/offline for ten minutes; /reload after."):format(
        store.friends.count, store.bnet.count, store.guild.members))
end
