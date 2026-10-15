-- Units/GroupFinder.lua
-- SuuUI's Group Finder (design component GroupFinder) on ForeverLFG
-- (SuuUI.LFG, Docs/ForeverLFG.md): the game's group finder window (I) in
-- SuuUI's look (the windows module) with SuuUI's pages over Blizzard's.
--   Browse  one list of groups and players looking, from the tool and from
--           chat, in Groups and Players; filters; the tool's age and
--           Refresh (the tool searches only on a click)
--   List yourself  the game's own listing panel in SuuUI's look (its
--           controls stay the game's: addons can't list you)
--   My listing  while you're listed: your listing (Delist, Update opens the
--           game's panel) and an ad for chat, posted only on your click
--   Who     who is online, with the game's own Filter menu (class, race,
--           zone, sort); Add friend, Whisper and Invite for the chosen one
--   Notes   ForeverLFG's eleven kinds as SuuUI notifications (design board
--           "Notifications · Group Finder"), each on or off with its
--           options (defaults from "Settings · Group Finder ·
--           Notifications"; the settings page comes in stage 4)
-- Starting the module starts the library (it joins LookingForGroup and keeps
-- it out of chat); turning it off stops it.
-- A built-in module written against the public API only.

local UI, T = SuuUI.UI, SuuUI.Tokens
local LFG = SuuUI.LFG

local M = SuuUI.RegisterModule({
    id = "groupfinder",
    name = "Group Finder",
    description = "One list of groups and players looking, from the game's group finder and from chat.",
    api = "0.13",
    reloadToToggle = true,
    defaults = {
        category = "all", activities = {}, fits = false, show = "both",
        collapsed = { groups = false, players = false },
        adChannel = "LookingForGroup",
        -- the chat channels read (tool listings always are), LookingForGroup
        -- joined and kept out of the chat windows, Latin-script languages besides yours
        channels = { "LookingForGroup", "General", "Trade", "Say" },
        joinLFG = true,
        extraLanguages = {},
        chatExpiry = 300, staleAfter = 300,
        -- each kind: on, sound, from the tool, from chat, the least chat
        -- confidence (%), shown in combat, shown in instances (off holds
        -- the note until you're out)
        notify = {
            role = { on = true, sound = true, tool = true, chat = true, conf = 70, combat = false, inst = false },
            fresh = { on = true, sound = false, tool = true, chat = true, conf = 70, combat = false, inst = false },
            player = { on = true, sound = true, tool = true, chat = true, conf = 70, combat = false, inst = false },
            quest = { on = true, sound = false, tool = true, chat = true, conf = 70, combat = false, inst = false },
            zone = { on = true, sound = false, tool = true, chat = true, conf = 50, combat = false, inst = false },
            boss = { on = false, sound = false, tool = true, chat = true, conf = 70, combat = false, inst = false },
            friends = { on = true, sound = false, tool = true, chat = true, conf = 50, combat = false, inst = false },
            stale = { on = true, sound = false, combat = false, inst = false },
            runout = { on = true, sound = true, combat = false, inst = true },
            delisted = { on = true, sound = false, combat = false, inst = true },
            contacted = { on = true, sound = false, tool = true, chat = true, conf = 70, combat = false, inst = false },
        },
    },
})

local DUNGEONS, ZONES, CUSTOM = 2, 116, 120

-- The Browse page's categories: kinds of activity, and the tool's category
-- each refreshes.
local CATEGORIES = {
    { value = "all", label = "All", kinds = nil, tool = DUNGEONS },
    { value = "dungeon", label = "Dungeons", kinds = { dungeon = true }, tool = DUNGEONS },
    { value = "raid", label = "Raids", kinds = { raid = true }, tool = DUNGEONS },
    { value = "zone", label = "Quests & Zones", kinds = { zone = true, quest = true }, tool = ZONES },
    { value = "world", label = "Open world", kinds = { boss = true }, tool = ZONES },
    { value = "custom", label = "Custom", kinds = { custom = true }, tool = CUSTOM },
}
local BY_VALUE = {}
for _, c in ipairs(CATEGORIES) do BY_VALUE[c.value] = c end

local REASON_TEXT = {
    role = "Needs your role", activity = "For your listing", player = "Player for your group",
    quest = "Quest in your log", zone = "In your zone", boss = "World boss", friend = "Friend or guild",
}
local REASON_ORDER = { "role", "player", "quest", "friend", "activity", "zone", "boss" }

--------------------------------------------------------------------------------
-- Entries to rows
--------------------------------------------------------------------------------

local function ago(seconds)
    if not seconds then return "" end
    seconds = math.max(0, seconds)
    if seconds < 60 then return "now" end
    if seconds < 3600 then return math.floor(seconds / 60) .. "m" end
    return math.floor(seconds / 3600) .. "h"
end

local ROLE_WORD = { tank = "Tank", healer = "Healer", damage = "Damage" }

-- A group's spots (design: RoleSlots, capped with your role first): what it
-- has, greyed (its members by the role each chose, then members with no
-- role; chat gives only a count), what it needs (tank, healer, damage, your
-- roles first, no more than its free spots: the game's needed roles aren't
-- capped and roles aren't enforced), then open spots. Groups above 10: no
-- member slots ("12/40" says it). Also the hover text: all it has and needs.
local function groupSlots(e, mine)
    local slots = {}
    local have = e.members and e.members[1] or 0
    local max = e.members and e.members[2]
    local small = not max or max <= 10
    local has = e.roles.has
    local shown = 0
    if small then
        for _, role in ipairs({ "tank", "healer", "damage", "none" }) do
            for _ = 1, has and has[role] or 0 do slots[#slots + 1] = "has:" .. role; shown = shown + 1 end
        end
        for _ = shown + 1, have do slots[#slots + 1] = "has:none" end
    end
    local needed = {}
    local function add(role)
        local n = e.roles.needed[role]
        n = (type(n) == "number" and n) or (n and 1) or 0
        for _ = 1, n do needed[#needed + 1] = role end
    end
    for _, role in ipairs({ "tank", "healer", "damage" }) do if mine[role] then add(role) end end
    for _, role in ipairs({ "tank", "healer", "damage" }) do if not mine[role] then add(role) end end
    local free = max and math.max(0, max - have)
    local fit = free and math.min(#needed, free) or #needed
    for i = 1, fit do slots[#slots + 1] = "need:" .. needed[i] end
    if max and small then
        for _ = 1, free - fit do slots[#slots + 1] = "open" end
    end
    -- the hover text
    local function list(counts)
        local out = {}
        for _, role in ipairs({ "tank", "healer", "damage" }) do
            local n = counts[role] or 0
            if n > 0 then out[#out + 1] = n .. " " .. ROLE_WORD[role] end
        end
        if (counts.none or 0) > 0 then out[#out + 1] = counts.none .. " without a role" end
        return table.concat(out, ", ")
    end
    local hasCounts = {}
    if has then for k, v in pairs(has) do hasCounts[k] = v end else hasCounts.none = have end
    local needCounts = {}
    for _, role in ipairs(needed) do needCounts[role] = (needCounts[role] or 0) + 1 end
    local tip = {}
    if have > 0 then tip[#tip + 1] = "Has: " .. list(hasCounts) end
    if #needed > 0 then tip[#tip + 1] = "Needs: " .. list(needCounts) end
    if free and #needed > free then
        tip[#tip + 1] = ("%d free %s: any of these"):format(free, free == 1 and "spot" or "spots")
    end
    return slots, table.concat(tip, "\n")
end

local function className(file)
    return file and LOCALIZED_CLASS_NAMES_MALE and LOCALIZED_CLASS_NAMES_MALE[file] or nil
end

function M:Row(e, interest)
    local names = {}
    for i, key in ipairs(e.activities) do
        if i > 2 then names[#names + 1] = "+" .. (#e.activities - 2) break end
        names[#names + 1] = LFG.Catalogue.Name(key)
    end
    if #names == 0 and #e.quests > 0 then
        local title = C_QuestLog and C_QuestLog.GetTitleForQuestID and C_QuestLog.GetTitleForQuestID(e.quests[1])
        names[1] = title or ("Quest " .. e.quests[1])
    end
    local reasons = LFG.MatchReasons(e, interest)
    local has = {}
    for _, r in ipairs(reasons) do has[r] = true end
    local reason
    for _, r in ipairs(REASON_ORDER) do if has[r] then reason = REASON_TEXT[r] break end end
    local tool, chat = e.sources.tool, e.sources.chat
    local now = LFG.Now()
    local age = tool and tool.age and (tool.age + (now - (tool.seenAt or now))) or (chat and (now - chat.lastPost))
    local sources = {}
    if tool then sources[#sources + 1] = "Tool" end
    if chat then sources[#sources + 1] = chat.channel == "SAY" and "Say" or (chat.channel == "YELL" and "Yell" or chat.channel) end
    -- roles: a group's spots, or what a player offers
    local slots, rolesTip = {}, nil
    if e.intent == "group" then
        slots, rolesTip = groupSlots(e, interest.roles or {})
    else
        for _, role in ipairs({ "tank", "healer", "damage" }) do
            if e.roles.offered[role] then slots[#slots + 1] = role end
        end
    end
    local who
    local lvl = e.leader and e.leader.level
    local cls = className(e.leader and e.leader.class)
    if lvl or cls then who = (lvl and ("Lvl " .. lvl .. " ") or "") .. (cls or "") end
    -- the chat post, else the listing's comment
    local post = chat and chat.text or e.text
    if post == "" or (issecretvalue and issecretvalue(post)) then post = nil end
    local playstyle
    if tool and tool.playstyle and GetGeneralPlaystyleString then
        local ok, s = pcall(GetGeneralPlaystyleString, tool.playstyle)
        if ok and type(s) == "string" and s ~= "" then playstyle = s end
    end
    return {
        key = e.key, entry = e, isPlayer = e.intent == "player",
        activity = table.concat(names, ", "), level = e.level and e.level[1] and (e.level[1] .. "+") or nil,
        newPlayerFriendly = tool and tool.newPlayerFriendly, reason = reason, match = reason ~= nil,
        leader = e.leader and e.leader.name or e.key, class = e.leader and e.leader.class, who = who,
        playstyle = playstyle, post = post,
        slots = slots, rolesTip = rolesTip ~= "" and rolesTip or nil, mine = interest.roles, members = e.members, sources = sources, age = ago(age),
        canInvite = LFG.CanInvite(e),
    }
end

-- The level that fits: an activity's range around yours.
local function fits(e, interest)
    local lvl = interest.level or 0
    for _, key in ipairs(e.activities) do
        for _, k in ipairs(LFG.Catalogue.Expand(key)) do
            local a = LFG.Catalogue.Get(k)
            local range = a and a.level
            if range and range[2] and lvl >= (range[1] or 0) - 3 and lvl <= range[2] + 3 then return true end
            if a and not range then return true end
        end
    end
    if e.level and e.level[1] then return math.abs(e.level[1] - lvl) <= 6 end
    return #e.activities == 0
end

function M:Data()
    local interest = LFG.Interest()
    local cat = BY_VALUE[self:Get("category")] or BY_VALUE.all
    local acts = {}
    for _, v in ipairs(self:Get("activities") or {}) do acts[v] = true end
    local filter = { kinds = cat.kinds, activities = next(acts) and acts or nil, search = self.search,
                     minConfidence = 0, notYou = false }
    local show = self:Get("show")
    local groups, players = {}, {}
    for _, e in ipairs(LFG.Entries(filter)) do
        local ok = true
        if self:Get("fits") then
            ok = fits(e, interest)
            if ok and e.intent == "group" and next(e.roles.needed) then
                ok = false
                for role in pairs(e.roles.needed) do if interest.roles[role] then ok = true end end
            end
        end
        if ok and (show == "both" or show == e.intent) then
            local row = self:Row(e, interest)
            if e.intent == "player" then players[#players + 1] = row else groups[#groups + 1] = row end
        end
    end
    -- matches first, then the newest
    local function order(a, b)
        if a.match ~= b.match then return a.match end
        return (a.entry.lastSeen or 0) > (b.entry.lastSeen or 0)
    end
    table.sort(groups, order)
    table.sort(players, order)
    -- the activities this category has, for the filter
    local options = {}
    for _, kind in ipairs({ "dungeon", "raid", "zone", "boss", "custom" }) do
        if not cat.kinds or cat.kinds[kind] then
            for _, a in ipairs(LFG.Catalogue.All(kind)) do
                options[#options + 1] = { value = a.key, label = LFG.Catalogue.Name(a.key) }
            end
        end
    end
    table.sort(options, function(a, b) return a.label < b.label end)
    local age = LFG.ToolAge(cat.tool)
    local categories = {}
    for _, c in ipairs(CATEGORIES) do categories[#categories + 1] = { value = c.value, label = c.label } end
    return {
        groups = groups, players = players, collapsed = self:Get("collapsed"),
        -- loading: the tool's first search for this category (chat shows meanwhile)
        tool = { age = age, stale = age and age > (self:Get("staleAfter") or 300), searching = self.searching,
                 loading = self.searching and not age },
        category = cat.value, categories = categories, activities = self:Get("activities") or {},
        activityOptions = options, search = self.search or "", fits = self:Get("fits"), show = show,
    }
end

function M:Render()
    if not (self.browse and self.browse:IsVisible()) then return end
    self.browse:SetData(self:Data())
end

function M:QueueRender()
    if self.renderQueued then return end
    self.renderQueued = true
    C_Timer.After(0.2, function()
        self.renderQueued = nil
        if self:IsEnabled() then self:Render() end
    end)
end

--------------------------------------------------------------------------------
-- The window
--------------------------------------------------------------------------------

function M:Wire(b)
    b.onFilter = function(t)
        if t.category then self:Set("category", t.category); self:Set("activities", {}) end
        if t.activities then self:Set("activities", t.activities) end
        if t.fits ~= nil then self:Set("fits", t.fits and true or false) end
        if t.show then self:Set("show", t.show) end
        if t.search ~= nil then self.search = t.search end
        self:QueueRender()
    end
    -- the tool searches on this click (the game's rule)
    b.onRefresh = function()
        local cat = BY_VALUE[self:Get("category")] or BY_VALUE.all
        self.searching = LFG.Refresh(cat.tool) and true or nil
        self:Render()
    end
    b.onClear = function()
        self:Set("category", "all"); self:Set("activities", {}); self:Set("fits", false); self:Set("show", "both")
        self.search = nil
        self:Render()
    end
    b.onWhisper = function(row) LFG.Whisper(row.entry) end
    b.onInvite = function(row) LFG.Invite(row.entry) end
    b.onToggle = function(key)
        local c = self:Get("collapsed") or {}
        c[key] = not c[key]
        self:Set("collapsed", c)
        self:Render()
    end
end

function M:Follow()
    local f = self.frame
    if not (f and self.browse) then return end
    local browse = _G.LFGBrowseFrame
    local on = f:IsShown() and browse and browse:IsShown()
    self.browse:SetShown(on and true or false)
    if browse then browse:SetAlpha(on and 0 or 1) end
    if on then self:Render() end
    -- Who over the game's page
    local whoPage = _G.LFGWhoListFrame
    local whoOn = f:IsShown() and whoPage and whoPage:IsShown()
    self.who:SetShown(whoOn and true or false)
    if whoPage then
        whoPage:SetAlpha(whoOn and 0 or 1)
        -- its search box is on the HIGH layer: no clicks through our page
        if whoPage.EditBox then whoPage.EditBox:EnableMouse(not whoOn) end
    end
    if whoOn then self:RenderWho() end
    -- My listing over the game's panel while you're listed (Update shows the panel)
    local panel = _G.LFGListingFrame
    local listed = f:IsShown() and panel and panel:IsShown() and LFG.Listing() ~= nil and not self.editing
    self.listed:SetShown(listed and true or false)
    -- the game's panel out of sight under it (its own buttons showed through);
    -- back for Update
    if panel then panel:SetAlpha(listed and 0 or 1) end
    if listed then self:RenderListed() end
    self.cover:SetShown((on or listed or whoOn) and true or false)
end

--------------------------------------------------------------------------------
-- My listing and the ad
--------------------------------------------------------------------------------

local function joinWith(list, last)
    if #list <= 1 then return list[1] or "" end
    return table.concat(list, ", ", 1, #list - 1) .. " " .. last .. " " .. list[#list]
end

local function minutesText(seconds)
    if not seconds then return nil end
    local m = math.floor(seconds / 60)
    if m < 1 then return "a moment" end
    if m < 60 then return m .. "m" end
    return math.floor(m / 60) .. "h " .. (m % 60) .. "m"
end

-- Your listing as one chat line, in English: what you're after, for what,
-- and your details. A group asks for the roles a 1 / 1 / 3 group still
-- lacks by its members' roles; alone, the roles you offer and who you are.
function M:AdFromListing(listing)
    if not listing then return "" end
    local names = {}
    for _, key in ipairs(listing.activities or {}) do names[#names + 1] = LFG.Catalogue.Name(key) end
    local acts = joinWith(names, "or")
    local text
    if IsInGroup() then
        local have = { TANK = 0, HEALER = 0, DAMAGER = 0 }
        local units = { "player" }
        for i = 1, (GetNumSubgroupMembers and GetNumSubgroupMembers() or 0) do units[#units + 1] = "party" .. i end
        for _, u in ipairs(units) do
            local r = UnitGroupRolesAssigned(u)
            if have[r] then have[r] = have[r] + 1 end
        end
        local need = {}
        if have.TANK < 1 then need[#need + 1] = "Tank" end
        if have.HEALER < 1 then need[#need + 1] = "Healer" end
        local dps = math.max(0, 3 - have.DAMAGER)
        if dps > 0 then need[#need + 1] = dps .. " DPS" end
        text = ("LFM %sfor %s (%d/5)."):format(#need > 0 and (joinWith(need, "and") .. " ") or "", acts, #units)
    else
        local roles = {}
        local r = listing.roles or {}
        if r.tank then roles[#roles + 1] = "Tank" end
        if r.healer then roles[#roles + 1] = "Healer" end
        if r.damage then roles[#roles + 1] = "DPS" end
        local _, class = UnitClass("player")
        local cname = class and LOCALIZED_CLASS_NAMES_MALE and LOCALIZED_CLASS_NAMES_MALE[class]
        text = ("LFG %s(%d %s) for %s."):format(#roles > 0 and (joinWith(roles, "or") .. " ") or "", UnitLevel("player"),
            (cname or ""):lower(), acts)
    end
    local comment = listing.comment
    if type(comment) == "string" and comment ~= "" and not (issecretvalue and issecretvalue(comment)) then
        text = text .. " " .. comment
    end
    return text
end

local AD_CHANNELS = { "LookingForGroup", "General", "Trade", "Say", "Yell" }

-- A channel's number by its name ("General" is "General - Orgrimmar").
local function channelId(name)
    local list = { GetChannelList() }
    for i = 1, #list, 3 do
        local id, n = list[i], list[i + 1]
        if type(n) == "string" and (n == name or n:find("^" .. name .. " %-")) then return id end
    end
    local id = GetChannelName(name)
    return (type(id) == "number" and id > 0) and id or nil
end

-- The ad goes out from the Post click (the game sends public chat only
-- from a click).
function M:PostAd(channel, text)
    if not (text and text:match("%S")) then return end
    local send = (C_ChatInfo and C_ChatInfo.SendChatMessage) or SendChatMessage
    if channel == "Say" then
        send(text, "SAY")
    else
        local id = channelId(channel)
        if not id then
            self:Print(("You're not in %s; join it to post there."):format(channel))
            return
        end
        send(text, "CHANNEL", nil, id)
    end
    self.lastPost = GetTime()
    self:RenderListed()
end

function M:RenderListed()
    if not (self.listed and self.listed:IsShown()) then return end
    local listing = LFG.Listing()
    if not listing then return end
    local names = {}
    for _, key in ipairs(listing.activities or {}) do names[#names + 1] = LFG.Catalogue.Name(key) end
    local roles = {}
    for _, r in ipairs({ "tank", "healer", "damage" }) do if listing.roles and listing.roles[r] then roles[#roles + 1] = r end end
    local playstyle
    if listing.playstyle and GetGeneralPlaystyleString then
        local ok, ps = pcall(GetGeneralPlaystyleString, listing.playstyle)
        if ok and type(ps) == "string" then playstyle = ps end
    end
    local category
    if listing.category and C_LFGList and C_LFGList.GetLfgCategoryInfo then
        local ok, info = pcall(C_LFGList.GetLfgCategoryInfo, listing.category)
        if ok and type(info) == "table" then category = info.name end
    end
    local voice = listing.voiceMode and _G.LFGVoiceChat and _G.LFGVoiceChat.VoiceModeLabels
        and _G.LFGVoiceChat.VoiceModeLabels[listing.voiceMode]
    local comment = listing.comment
    if issecretvalue and issecretvalue(comment) then comment = nil end
    if not self.adEdited then self.adText = self:AdFromListing(listing) end
    local channels = {}
    for _, c in ipairs(AD_CHANNELS) do channels[#channels + 1] = { value = c, label = c } end
    self.listed:SetData({
        listing = { listedFor = minutesText(self.listedAt and (LFG.Now() - self.listedAt)),
                    left = minutesText(listing.duration), category = category, activities = names, roles = roles,
                    playstyle = playstyle, comment = comment, voice = voice or "None" },
        ad = { text = self.adText or "", channel = self:Get("adChannel"), channels = channels,
               lastPost = self.lastPost and minutesText(GetTime() - self.lastPost) or nil, max = 255 },
    })
end

--------------------------------------------------------------------------------
-- Who (stage 5; probed 2026-10-15: SendWho works from a click)
--------------------------------------------------------------------------------

function M:ReadWho()
    local fl = C_FriendList
    local ok, num, total = pcall(fl.GetNumWhoResults)
    if not ok or type(num) ~= "number" then return end
    local results = {}
    for i = 1, num do
        local okI, info = pcall(fl.GetWhoInfo, i)
        if okI and type(info) == "table" and not (issecretvalue and issecretvalue(info.fullName)) then
            results[#results + 1] = { name = info.fullName, level = info.level, race = info.raceStr,
                class = info.filename, className = info.classStr, guild = info.fullGuildName, zone = info.area }
        end
    end
    self.whoData = { state = #results > 0 and "results" or "none", query = self.whoQuery or "",
                     total = total or #results, capped = (total or 0) > num, results = results }
end

function M:RenderWho()
    if not (self.who and self.who:IsShown()) then return end
    self.who:SetData(self.whoData or { state = "idle" })
end

function M:WireWho(w)
    -- the search goes out from the click or Enter (the game allows nothing else)
    w.onSearch = function(text)
        local fl = C_FriendList
        self.whoQuery = text
        pcall(fl.SetWhoToUi, true)
        local filters = _G.LFGWhoListFilterUtil and _G.LFGWhoListFilterUtil.GetWhoFilters and _G.LFGWhoListFilterUtil.GetWhoFilters()
        local origin = Enum and Enum.SocialWhoOrigin and Enum.SocialWhoOrigin.Social
        fl.SendWho(text or "", origin, filters)
    end
    -- the game's own filter menu (class, race, zone, sort), opened under our button
    w.onFilter = function(button)
        local page = _G.LFGWhoListFrame
        local dd = page and page.FilterDropdown
        if not dd then return end
        if not self.whoDropdownSkinned then
            self.whoDropdownSkinned = true
            UI.ReskinDropdown(dd)
        end
        dd:ClearAllPoints()
        dd:SetPoint("TOPLEFT", button, "TOPLEFT", 0, 0)
        dd:SetSize(button:GetWidth(), button:GetHeight())
        if dd.OpenMenu then dd:OpenMenu() elseif dd.Click then dd:Click() end
    end
    w.onMenu = function(row)
        if FriendsFrame_ShowDropdown then FriendsFrame_ShowDropdown(row.name, 1) end
    end
    w.onWhisper = function(row)
        local tell = (ChatFrameUtil and ChatFrameUtil.SendTell) or ChatFrame_SendTell
        if tell then tell(row.name) end
    end
    w.onInvite = function(row)
        local invite = (C_PartyInfo and C_PartyInfo.InviteUnit) or InviteUnit
        if invite then pcall(invite, row.name) end
    end
    w.onAddFriend = function(row)
        if C_FriendList.AddFriend then pcall(C_FriendList.AddFriend, row.name) end
    end
    self:OnGameEvent("WHO_LIST_UPDATE", function()
        self:ReadWho()
        self:RenderWho()
    end)
end

function M:WireListed(p)
    p.onDelist = function() LFG.Delist() end
    p.onUpdate = function()
        -- the game's own panel, to change the listing; back here once it's saved
        self.editing = true
        self:Follow()
    end
    p.onChannel = function(v) self:Set("adChannel", v); self:RenderListed() end
    p.onText = function(t) self.adText, self.adEdited = t, true end
    p.onRewrite = function() self.adEdited = false; self:RenderListed() end
    p.onPost = function(channel, text) self:PostAd(channel, text) end
end

-- Opening the window searches the tool for the chosen category (the key
-- press or click that opened it allows that: probed 2026-10-15), unless it
-- searched in the last minute.
function M:SearchOnOpen()
    local cat = BY_VALUE[self:Get("category")] or BY_VALUE.all
    local age = LFG.ToolAge(cat.tool)
    if age and age < 60 then return end
    self.searching = LFG.Refresh(cat.tool) and true or nil
end

function M:Build()
    local f = _G.LFGParentFrame
    if not f or self.browse then return end
    self.frame = f
    local b = UI.GroupFinderBrowse(f)
    b:SetPoint("TOPLEFT", f, "TOPLEFT", 20, -44)
    b:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -20, 16)
    b:SetFrameLevel(f:GetFrameLevel() + 100)
    b:EnableMouse(true)
    b.suuOwn = true
    b:Hide()
    self.browse = b
    -- Blizzard's own Browse page stays shown (out of sight) under ours: a
    -- cover over all of it below the tab row, so none of its rows, buttons
    -- or tooltips can be reached around our page's edges (its tooltip for
    -- a listing that was gone errored, found in game)
    local cover = CreateFrame("Frame", nil, f)
    cover:SetPoint("TOPLEFT", f, "TOPLEFT", 0, -24)
    cover:SetPoint("BOTTOMRIGHT")
    cover:SetFrameLevel(f:GetFrameLevel() + 99)
    cover:EnableMouse(true)
    cover:Hide()
    self.cover = cover
    self:Wire(b)
    -- List yourself: the game's own panel, restyled (stage 3)
    if _G.LFGListingFrame then UI.SkinGroupFinderListing(_G.LFGListingFrame) end
    -- Who
    local wp = UI.GroupFinderWho(f)
    wp:SetPoint("TOPLEFT", f, "TOPLEFT", 20, -44)
    wp:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -20, 16)
    wp:SetFrameLevel(f:GetFrameLevel() + 100)
    wp:EnableMouse(true)
    wp.suuOwn = true
    wp:Hide()
    self.who = wp
    self:WireWho(wp)
    -- My listing, over it while you're listed
    local l = UI.GroupFinderListed(f)
    l:SetPoint("TOPLEFT", f, "TOPLEFT", 20, -44)
    l:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -20, 16)
    l:SetFrameLevel(f:GetFrameLevel() + 100)
    l:EnableMouse(true)
    l.suuOwn = true
    l:Hide()
    self.listed = l
    self:WireListed(l)
    if _G.LFGListingFrame then
        -- leaving the panel ends an Update
        _G.LFGListingFrame:HookScript("OnHide", function() self.editing = nil end)
    end
    f:HookScript("OnShow", function()
        self:SearchOnOpen()
        self:Follow()
    end)
    f:HookScript("OnHide", function() GameTooltip:Hide() end)
    for _, c in ipairs({ _G.LFGBrowseFrame, _G.LFGListingFrame, _G.LFGWhoListFrame }) do
        if c then
            c:HookScript("OnShow", function() self:Follow() end)
            c:HookScript("OnHide", function() self:Follow() end)
        end
    end
    self:Follow()
end

-- The library by your settings.
function M:Configure()
    local channels = {}
    for _, c in ipairs(self:Get("channels") or {}) do channels[c == "Say" and "SAY" or (c == "Yell" and "YELL" or c)] = true end
    local extra = {}
    for _, code in ipairs(self:Get("extraLanguages") or {}) do extra[code] = true end
    LFG.Configure({ chatExpiry = self:Get("chatExpiry"), staleAfter = self:Get("staleAfter"), channels = channels,
                    joinLookingForGroup = self:Get("joinLFG"), hideLookingForGroup = self:Get("joinLFG"),
                    extraLanguages = extra })
end

function M:OnEnable()
    self:Configure()
    for _, key in ipairs({ "channels", "joinLFG", "chatExpiry", "extraLanguages" }) do
        self:Watch(key, function() self:Configure() end)
    end
    self:RegisterSettings(self:SettingsSection())
    LFG.Start()
    -- the list follows the library
    for _, ev in ipairs({ "EntryAdded", "EntryUpdated", "EntryRemoved", "ListingChanged" }) do
        LFG.On(ev, function() self:QueueRender() end)
    end
    LFG.On("ToolSearched", function() self.searching = nil; self:QueueRender() end)
    LFG.On("ToolSearchFailed", function() self.searching = nil; self:QueueRender() end)
    -- the tool's age moves on
    C_Timer.NewTicker(15, function()
        if self.browse and self.browse:IsVisible() then self:Render() end
        if self.listed and self.listed:IsVisible() then self:RenderListed() end
    end)
    -- your listing made, changed or gone: My listing follows
    LFG.On("ListingChanged", function()
        self.editing = nil
        self:Follow()
    end)
    self:Build()
    self:OnGameEvent("ADDON_LOADED", function() self:Build() end)
    self:StartNotes()
end

function M:OnDisable()
    LFG.Stop()
end

--------------------------------------------------------------------------------
-- Settings › Group Finder (stage 4; design boards "Settings · Group Finder",
-- "Settings · Group Finder · Notifications")
--------------------------------------------------------------------------------

local CHAT_CHANNELS = { "LookingForGroup", "General", "Trade", "Services", "Say", "Yell" }
local LANGUAGE_NAMES = { enUS = "English", enGB = "English", deDE = "German", frFR = "French", esES = "Spanish",
    esMX = "Spanish", ptBR = "Portuguese", itIT = "Italian", koKR = "Korean", zhCN = "Chinese", zhTW = "Chinese",
    ruRU = "Russian" }
local LATIN = { "deDE", "frFR", "esES", "ptBR", "itIT" }
local SCRIPTS = { { "koKR", "Korean" }, { "zhCN", "Chinese" }, { "ruRU", "Russian" } }

local NOTIFY_ROWS = {
    { key = "role", label = "Your role is needed" },
    { key = "fresh", label = "New group for your activity" },
    { key = "player", label = "A player for your group" },
    { key = "quest", label = "Quest group" },
    { key = "zone", label = "In your zone" },
    { key = "boss", label = "World boss or event" },
    { key = "friends", label = "Friends and guild" },
    { key = "stale", label = "Results are stale" },
    { key = "runout", label = "Your listing runs out soon" },
    { key = "delisted", label = "You were delisted" },
    { key = "contacted", label = "A group you contacted" },
}

local function plainText(parent, text, color)
    local f = CreateFrame("Frame", nil, parent)
    f.text = UI.Text(f, "body", color or "ink")
    f.text:SetPoint("TOPLEFT")
    f.text:SetJustifyH("LEFT")
    f.text:SetValue(text)
    f:SetSize(math.max(1, math.ceil(f.text:GetUnboundedStringWidth())), math.ceil(f.text:GetStringHeight()))
    return f
end

function M:SettingsSection()
    local modules = (LFG.Lang and LFG.Lang.modules) or {}
    return {
        id = "groupfinder", label = "Group Finder", category = "World", order = 30,
        preview = function(parent) return self:SettingsPreview(parent) end,
        groups = {
            { title = "Group Finder", description = "One list from the game’s group finder and the public chat channels. The tool searches when you open the window or press Refresh; chat is read as it’s written.", rows = {
                { key = "channels", label = "Channels to read", description = "Posts in these channels join the list. Tool listings always do.",
                  control = "custom", build = function(parent, onChange)
                      local opts = {}
                      for _, c in ipairs(CHAT_CHANNELS) do opts[#opts + 1] = { value = c, label = c } end
                      return UI.ToggleChips(parent, { options = opts, onChange = onChange })
                  end, stacked = true },
                { key = "joinLFG", label = "Join LookingForGroup", control = "toggle",
                  description = "Joins the channel when you log in and keeps it out of your chat windows: its posts show here instead." },
                { label = "Chat posts expire after", control = "slider", min = 1, max = 15, step = 1, unit = " min",
                  description = "A post leaves the list this long after its last repost. Posting again brings it back.",
                  get = function() return math.floor((self:Get("chatExpiry") or 300) / 60 + 0.5) end,
                  set = function(v) self:Set("chatExpiry", v * 60) end,
                  isDefault = function() return (self:Get("chatExpiry") or 300) == 300 end,
                  reset = function() self:Set("chatExpiry", 300) end },
            } },
            { title = "Languages", description = "What the chat parser understands. Activity, zone and quest names come from the game in your client’s language; a language module adds the words players type around them.", rows = {
                { label = "Always read", description = "Your Forever language preference and your client’s language.",
                  control = "custom", build = function(parent)
                      local names, seen = {}, {}
                      for _, code in ipairs(LFG.Languages()) do
                          local n = LANGUAGE_NAMES[code] or code
                          if not seen[n] then seen[n] = true; names[#names + 1] = n end
                      end
                      return plainText(parent, table.concat(names, ", "))
                  end },
                { label = "Other scripts", description = "Posts in Hangul, Chinese characters or Cyrillic are read with that language’s module whenever SuuUI has one.",
                  control = "custom", build = function(parent)
                      local lines = {}
                      for _, sc in ipairs(SCRIPTS) do
                          local ready = modules[sc[1]] ~= nil
                          lines[#lines + 1] = "|cff" .. T.color[ready and "ink" or "ink-faint"].hex .. sc[2] .. "|r |cff"
                              .. T.color[ready and "ink-muted" or "ink-faint"].hex .. (ready and "· module ready" or "· no module yet") .. "|r"
                      end
                      return plainText(parent, table.concat(lines, "\n"))
                  end },
                { key = "extraLanguages", label = "Also read", description = "Other Latin-script languages. Off by default: their words overlap with English, so each one adds false matches.",
                  control = "custom", stacked = true, build = function(parent, onChange)
                      local opts = {}
                      for _, code in ipairs(LATIN) do
                          if modules[code] then opts[#opts + 1] = { value = code, label = LANGUAGE_NAMES[code] } end
                      end
                      if #opts == 0 then
                          local f = plainText(parent, "No other language modules yet.", "ink-faint")
                          f.SetValue = function() end
                          return f
                      end
                      return UI.ToggleChips(parent, { options = opts, onChange = onChange })
                  end },
            } },
            { title = "Your ad", rows = {
                { key = "adChannel", label = "Channel for your ad", control = "select", width = 180,
                  description = "Where the ad on My listing posts by default. You can pick another each time; it’s only ever sent on your click.",
                  options = (function()
                      local o = {}
                      for _, c in ipairs(AD_CHANNELS) do o[#o + 1] = { value = c, label = c } end
                      return o
                  end)() },
            } },
            { title = "Notifications", description = "Each kind on or off, with its options. Tool and Chat: where it may come from. Confidence: how sure the chat parser must be. In combat and In instances: off holds the note until you’re out. The same group never notifies twice within a few minutes. /suu lfgnotes shows each.", rows = {
                { key = "notify", label = "Group Finder notifications", control = "custom", stacked = true,
                  build = function(parent, onChange)
                      local conf = { { value = 0, label = "Any" }, { value = 50, label = "50%" }, { value = 70, label = "70%" }, { value = 90, label = "90%" } }
                      return UI.SettingsMatrix(parent, { width = 540, onChange = onChange, rows = NOTIFY_ROWS, columns = {
                          { key = "on", label = "On", width = 28, master = true },
                          { key = "sound", label = "Sound", width = 38 },
                          { key = "tool", label = "Tool", width = 30 },
                          { key = "chat", label = "Chat", width = 30 },
                          { key = "conf", label = "Confidence", width = 62, kind = "select", options = conf,
                            title = "The least the chat parser must be sure of a post" },
                          { key = "combat", label = "In combat", width = 50 },
                          { key = "inst", label = "In instances", width = 58 },
                      } })
                  end },
            } },
        },
    }
end

-- The live preview: a note of each Group Finder kind most people meet.
function M:SettingsPreview(parent)
    if not self.preview then
        self.preview = UI.NotificationStack(parent, { max = 3 })
        local kessra = { key = "Kessra", intent = "group", activities = { "dungeon:rfk" }, quests = {}, members = { 3, 5 }, level = { 29, 29 },
            leader = { name = "Kessra", class = "MAGE", level = 31 }, roles = { needed = { healer = 1, tank = 1 }, offered = {} },
            sources = { tool = {}, chat = { channel = "LookingForGroup", text = "LFM Heal / Tank (drood) or Pala for RFK", confidence = 0.9 } }, text = "" }
        local morrow = { key = "Morrow", intent = "player", activities = { "dungeon:wc" }, quests = {}, leader = { name = "Morrow", class = "ROGUE", level = 20 },
            roles = { needed = {}, offered = { damage = true } }, sources = { chat = { channel = "LookingForGroup", text = "20 rogue lfg WC", confidence = 0.8 } }, text = "" }
        local items = {}
        for _, n in ipairs({ { "role", kessra }, { "player", morrow } }) do
            local d = self:MatchNote(n[1], n[2])
            d.id = "preview:" .. n[1]
            d.remaining = d.duration
            for _, a in ipairs(d.actions or {}) do a.onClick = function() end end
            items[#items + 1] = d
        end
        self.preview:SetItems(items, false)
    end
    self.preview:SetParent(parent)
    return self.preview
end

--------------------------------------------------------------------------------
-- Notes (stage 2; design board "Notifications · Group Finder")
--------------------------------------------------------------------------------

local TEX = "Interface\\AddOns\\SuuUI\\Media\\Textures\\"
local ROLE_TEX = { tank = TEX .. "RoleTank.tga", healer = TEX .. "RoleHealer.tga", damage = TEX .. "RoleDamage.tga" }
local A_ROLE = { tank = "a tank", healer = "a healer", damage = "a damage dealer" }
-- a match's reasons, most telling first, and the kind of note each makes
local NOTE_ORDER = { "role", "player", "quest", "friend", "activity", "zone", "boss" }
local NOTE_KIND = { role = "role", player = "player", quest = "quest", friend = "friends", activity = "fresh", zone = "zone", boss = "boss" }
local AGAIN = 300 -- the same group never notifies twice within this

local function joinAnd(list)
    if #list <= 1 then return list[1] or "" end
    return table.concat(list, ", ", 1, #list - 1) .. " and " .. list[#list]
end

local function activityText(e)
    local names = {}
    for i, key in ipairs(e.activities) do
        if i > 2 then names[#names + 1] = "+" .. (#e.activities - 2) break end
        names[#names + 1] = LFG.Catalogue.Name(key)
    end
    return table.concat(names, ", ")
end

local function questTitle(e)
    local id = e.quests[1]
    local t = id and C_QuestLog and C_QuestLog.GetTitleForQuestID and C_QuestLog.GetTitleForQuestID(id)
    return t or (id and ("Quest " .. id)) or nil
end

-- "needs a healer and 2 damage"
local function needsText(e)
    local out = {}
    for _, role in ipairs({ "tank", "healer", "damage" }) do
        local n = e.roles.needed[role]
        n = (type(n) == "number" and n) or (n and 1) or 0
        if n == 1 then out[#out + 1] = A_ROLE[role]
        elseif n > 1 then out[#out + 1] = n .. (role == "damage" and " damage" or (" " .. role .. "s")) end
    end
    return #out > 0 and ("needs " .. joinAnd(out)) or nil
end

local function offersText(e)
    local out = {}
    for _, role in ipairs({ "tank", "healer", "damage" }) do
        if e.roles.offered[role] then out[#out + 1] = role end
    end
    return #out > 0 and ("offers " .. table.concat(out, " or ")) or nil
end

local function lines(...)
    local out = {}
    for i = 1, select("#", ...) do
        local v = select(i, ...)
        if v and v ~= "" then out[#out + 1] = v end
    end
    return table.concat(out, " · ")
end

-- Where it came from: the tool and/or the channel, the post as written.
local function sourceOf(e)
    local tool, chat = e.sources.tool, e.sources.chat
    local channel = chat and (chat.channel == "SAY" and "Say" or (chat.channel == "YELL" and "Yell" or chat.channel))
    local text = chat and chat.text
    if text and issecretvalue and issecretvalue(text) then text = nil end
    return { tool = tool and true or nil, channel = channel, text = text }
end

local function classIcon(class)
    local coords = class and CLASS_ICON_TCOORDS and CLASS_ICON_TCOORDS[class]
    if not coords then return nil end
    return { texture = "Interface\\Glues\\CharacterCreate\\UI-CharacterCreate-Classes", coords = coords }
end

-- May this kind show for this entry (its sources, the parser's confidence)?
function M:Allowed(e, cfg)
    if e.sources.tool and cfg.tool then return true end
    if e.sources.chat and cfg.chat then
        local c = (e.sources.chat.confidence or e.confidence or 0) * 100
        return c >= (cfg.conf or 0)
    end
    return false
end

-- Show a note now, or hold it while you fight or are in an instance (each
-- kind's choice); held notes are checked again when you're out.
function M:Note(kind, build)
    local cfg = (self:Get("notify") or {})[kind]
    if not (cfg and cfg.on) then return end
    local inInstance = IsInInstance and select(1, IsInInstance())
    if (InCombatLockdown() and not cfg.combat) or (inInstance and not cfg.inst) then
        -- the latest few only: a dungeon's worth of chat shouldn't arrive at once
        self.held = self.held or {}
        self.held[#self.held + 1] = { kind = kind, build = build }
        if #self.held > 5 then table.remove(self.held, 1) end
        return
    end
    local def = build()
    if not def then return end
    if cfg.sound and UI.TrackerSound then UI.TrackerSound("chime") end
    return SuuUI.Notify(def)
end

function M:FlushHeld()
    local held = self.held
    self.held = nil
    for _, h in ipairs(held or {}) do self:Note(h.kind, h.build) end
end

-- A group or player that concerns you: one note, for its most telling reason.
function M:OnMatch(e, reasons)
    if e.you then return end
    local now = LFG.Now()
    self.noted = self.noted or {}
    if self.noted[e.key] and now - self.noted[e.key] < AGAIN then return end
    local has = {}
    for _, r in ipairs(reasons) do has[r] = true end
    local notify = self:Get("notify") or {}
    for _, reason in ipairs(NOTE_ORDER) do
        local kind = NOTE_KIND[reason]
        local cfg = notify[kind]
        if has[reason] and cfg and cfg.on and self:Allowed(e, cfg) then
            self.noted[e.key] = now
            self:Note(kind, function()
                -- still there?
                local cur = LFG.Entry(e.key)
                if not cur then return nil end
                return self:MatchNote(kind, cur)
            end)
            return
        end
    end
end

function M:MatchNote(kind, e)
    local leader = e.leader and e.leader.name or e.key
    local cls = e.leader and e.leader.class
    local who
    local lvl = e.leader and e.leader.level
    local cname = cls and LOCALIZED_CLASS_NAMES_MALE and LOCALIZED_CLASS_NAMES_MALE[cls]
    if lvl or cname then who = ((lvl and ("Lvl " .. lvl .. " ")) or "") .. (cname or "") end
    local tool = e.sources.tool
    local playstyle
    if tool and tool.playstyle and GetGeneralPlaystyleString then
        local ok, ps = pcall(GetGeneralPlaystyleString, tool.playstyle)
        if ok and type(ps) == "string" and ps ~= "" then playstyle = ps end
    end
    local size = e.members and e.members[2] and (e.members[1] .. "/" .. e.members[2]) or nil
    local level = e.level and e.level[1] and (e.level[1] .. "+") or nil
    local act = activityText(e)
    local whisper = { label = "Whisper", icon = "chat", onClick = function() LFG.Whisper(e) end }
    local d = { id = "lfg:" .. e.key, kind = "timed", duration = 8, source = sourceOf(e),
                icon = classIcon(cls) or { glyph = "people" } }
    if kind == "role" then
        local mine = (LFG.Interest().roles) or {}
        local role
        for _, r in ipairs({ "tank", "healer", "damage" }) do if mine[r] and e.roles.needed[r] then role = r break end end
        d.duration, d.category = 12, "Your role is needed"
        d.icon = role and { texture = ROLE_TEX[role], coords = { 0, 1, 0, 1 } } or d.icon
        d.title = ("%s needs %s for %s"):format(leader, A_ROLE[role] or "your role", act ~= "" and act or "a group")
        d.body = lines(size, who, playstyle, level)
        whisper.variant = "primary"
        d.actions = { whisper }
    elseif kind == "fresh" then
        d.category, d.icon = "New group for your activity", { glyph = "door" }
        d.title = "A group for " .. (act ~= "" and act or "your activity")
        d.body = lines(leader, size, needsText(e), playstyle)
    elseif kind == "quest" then
        local q = questTitle(e)
        d.category, d.icon = "Quest group", { glyph = "scroll" }
        d.title = e.intent == "player" and (leader .. " is looking for " .. (q or "a quest")) or ("A group for " .. (q or "a quest in your log"))
        d.body = lines(act, leader, size, "a quest in your log")
        d.actions = { whisper }
    elseif kind == "zone" then
        local zone = GetRealZoneText and GetRealZoneText()
        d.category, d.icon = "In your zone", { glyph = "map" }
        d.title = e.intent == "player" and (leader .. " is looking for a group here") or ("A group in " .. (type(zone) == "string" and zone or "your zone"))
        d.body = lines(leader, who, size)
        d.actions = { whisper }
    elseif kind == "boss" then
        d.category, d.icon = "World boss or event", { glyph = "skull" }
        d.title = "A raid forming for " .. (act ~= "" and act or "a world boss")
        d.body = lines(leader, e.members and e.members[2] and (e.members[1] .. " of " .. e.members[2]) or nil)
        d.actions = { whisper }
    elseif kind == "friends" then
        local social = LFG.Social and LFG.Social(leader)
        d.category = "Friends and guild"
        d.title = e.intent == "player" and (leader .. " is looking for " .. (act ~= "" and act or "a group"))
            or (leader .. "’s group for " .. (act ~= "" and act or "an activity"))
        d.body = lines(social == "guild" and "Guild" or (social == "friend" and "Friend" or nil), who,
            e.intent == "player" and offersText(e) or needsText(e), playstyle)
        d.actions = { whisper }
    elseif kind == "player" then
        d.kind, d.duration, d.category = "sticky", nil, "A player for your group"
        d.title = leader .. " wants " .. (act ~= "" and act or "your activity")
        d.body = lines(who, offersText(e))
        d.actions = { whisper }
        if LFG.CanInvite(e) then
            d.actions[2] = { label = "Invite", variant = "primary", icon = "plus", onClick = function(card) LFG.Invite(e); SuuUI.DismissNotification(d.id) end }
        end
    end
    return d
end

-- A group you whispered: posted again, full, or gone.
function M:OnContacted(e, what)
    local cfg = (self:Get("notify") or {}).contacted
    if not (cfg and cfg.on and self:Allowed(e, cfg)) then return end
    self:Note("contacted", function()
        local leader = e.leader and e.leader.name or e.key
        local act = activityText(e)
        local at = LFG.ContactedAt and LFG.ContactedAt(e.key)
        local ago = at and math.max(1, math.floor((LFG.Now() - at) / 60)) .. "m ago"
        local d = { id = "lfg:contacted:" .. e.key, kind = "timed", category = "A group you contacted",
                    icon = classIcon(e.leader and e.leader.class) or { glyph = "people" }, source = sourceOf(e) }
        if what == "reposted" then
            local need = needsText(e)
            d.duration = 10
            d.title = leader .. " posted again" .. (need and (", still " .. (need:gsub("^needs", "needing"))) or "")
            d.body = lines(act, e.members and e.members[2] and (e.members[1] .. "/" .. e.members[2]) or nil, ago and ("you whispered " .. ago))
            d.actions = { { label = "Whisper", icon = "chat", variant = "primary", onClick = function() LFG.Whisper(e) end } }
        elseif what == "full" then
            d.duration = 6
            d.title = leader .. "’s group for " .. (act ~= "" and act or "its activity") .. " is full"
            d.body = ago and ("You whispered " .. leader .. " " .. ago .. ".") or nil
        else
            d.duration = 6
            d.title = e.sources.tool and (leader .. " delisted " .. (act ~= "" and act or "the group"))
                or (leader .. " stopped posting for " .. (act ~= "" and act or "the group"))
            d.body = ago and ("You whispered " .. leader .. " " .. ago .. ".") or nil
            d.source = nil
        end
        return d
    end)
end

-- What you're listed for, in words ("Shadowfang Keep and 2 more").
local function listedText(listing, all)
    local names = {}
    for _, key in ipairs(listing and listing.activities or {}) do names[#names + 1] = LFG.Catalogue.Name(key) end
    if all then return joinAnd(names) end
    if #names > 1 then return names[1] .. " and " .. (#names - 1) .. " more" end
    return names[1] or "your activity"
end

function M:OnStale(category, age)
    self:Note("stale", function()
        local listing = LFG.Listing()
        if not listing and not next(LFG.Watches()) then return nil end
        local minutes = age and math.floor(age / 60) or nil
        local actions = {}
        if listing then
            actions[#actions + 1] = { label = "Delist", icon = "close", onClick = function()
                LFG.Delist(); SuuUI.DismissNotification("lfg:stale") end }
        end
        actions[#actions + 1] = { label = "Refresh", variant = "primary", icon = "reset", onClick = function()
            if LFG.Refresh(category) then self.searching = true end
            SuuUI.DismissNotification("lfg:stale")
        end }
        return { id = "lfg:stale", kind = "until", tone = "warning", category = "Results are stale",
                 icon = { glyph = "hourglass" },
                 title = minutes and ("Tool results are " .. minutes .. " minutes old") or "The tool hasn’t searched yet",
                 body = (listing and ("You’re listed for " .. listedText(listing) .. ". ") or "")
                     .. "Chat stays live; the tool only searches on your click.",
                 ["until"] = "Goes when you refresh", actions = actions }
    end)
end

-- Opening the game's Group Finder at its listing panel is a secure click
-- (opened from addon code, the panel's listing would be refused): the
-- micro menu's button when it's closed, then the listing tab.
local function openListingMacro()
    local f = _G.LFGParentFrame
    if f and f:IsShown() then return "/click LFGParentFrameTab1" end
    return "/click LFDMicroButton\n/click LFGParentFrameTab1"
end

function M:OnExpiring(seconds)
    self:Note("runout", function()
        local listing = LFG.Listing()
        if not listing then return nil end
        local minutes = math.max(1, math.ceil(seconds / 60))
        return { id = "lfg:runout", kind = "action", duration = seconds, remaining = seconds,
                 category = "Your listing runs out soon", icon = { glyph = "hourglass" },
                 title = ("Your listing runs out in %d %s"):format(minutes, minutes == 1 and "minute" or "minutes"),
                 body = lines(table.concat((function()
                     local t = {}
                     for _, key in ipairs(listing.activities or {}) do t[#t + 1] = LFG.Catalogue.Name(key) end
                     return t
                 end)(), " · ")),
                 actions = {
                     { label = "Delist", icon = "close", onClick = function() LFG.Delist(); SuuUI.DismissNotification("lfg:runout") end },
                     { label = "Open listing", variant = "primary", icon = "scroll", macro = openListingMacro, onClick = function()
                         if InCombatLockdown() then
                             self:Print("The listing opens out of combat.")
                         else
                             SuuUI.DismissNotification("lfg:runout")
                         end
                     end },
                 } }
    end)
end

function M:OnListingChanged(listing)
    if listing then
        self.listedAt = self.listedAt or LFG.Now()
        self.lastListing = listing
    end
end

function M:OnDelisted()
    SuuUI.DismissNotification("lfg:runout")
    if not next(LFG.Watches()) then SuuUI.DismissNotification("lfg:stale") end
    local listing, since = self.lastListing, self.listedAt
    self.lastListing, self.listedAt = nil, nil
    -- you took it down yourself: nothing to tell
    if self.delistedByYou and GetTime() - self.delistedByYou < 5 then return end
    self:Note("delisted", function()
        local minutes = since and math.max(1, math.floor((LFG.Now() - since) / 60))
        return { id = "lfg:delisted", kind = "sticky", category = "You were delisted", icon = { glyph = "close" },
                 title = "Your listing has ended",
                 body = listing and (("Listed %s for %s."):format(minutes and (minutes .. " minutes") or "a while",
                     listedText(listing, true))) or nil }
    end)
end

function M:StartNotes()
    if self.notesOn then return end
    self.notesOn = true
    LFG.On("Match", function(e, reasons) self:OnMatch(e, reasons) end)
    LFG.On("Contacted", function(e, what) self:OnContacted(e, what) end)
    LFG.On("ToolStale", function(category, age) self:OnStale(category, age) end)
    LFG.On("ToolSearched", function() SuuUI.DismissNotification("lfg:stale") end)
    LFG.On("ListingExpiring", function(seconds) self:OnExpiring(seconds) end)
    LFG.On("ListingChanged", function(listing) self:OnListingChanged(listing) end)
    LFG.On("Delisted", function() self:OnDelisted() end)
    -- your own delisting (the game's Unlist, a note's Delist)
    if C_LFGList and C_LFGList.RemoveListing then
        hooksecurefunc(C_LFGList, "RemoveListing", function() self.delistedByYou = GetTime() end)
    end
    self:OnGameEvent("PLAYER_REGEN_ENABLED", function() self:FlushHeld() end)
    self:OnGameEvent("PLAYER_ENTERING_WORLD", function() self:FlushHeld() end)
    self:OnListingChanged(LFG.Listing())
    self:RegisterCommand("lfgnotes", "test: shows one Group Finder note of each kind, from made-up groups", function()
        self:TestNotes()
    end)
end

-- Made-up groups and players for /suu lfgnotes.
function M:TestNotes()
    local function entry(t)
        t.quests = t.quests or {}
        t.roles = t.roles or { needed = {}, offered = {} }
        t.roles.needed, t.roles.offered = t.roles.needed or {}, t.roles.offered or {}
        t.sources = t.sources or {}
        t.text = t.text or ""
        return t
    end
    local kessra = entry({ key = "Kessra", intent = "group", activities = { "dungeon:rfk" }, members = { 3, 5 }, level = { 29, 29 },
        leader = { name = "Kessra", class = "MAGE", level = 31 }, roles = { needed = { healer = 1, tank = 1 } },
        sources = { tool = {}, chat = { channel = "LookingForGroup", text = "LFM Heal / Tank (drood) or Pala for RFK", confidence = 0.9 } } })
    local brannoc = entry({ key = "Brannoc", intent = "group", activities = { "dungeon:sfk" }, members = { 2, 5 },
        leader = { name = "Brannoc", class = "WARRIOR", level = 22 }, roles = { needed = { healer = 1, damage = 2 } }, sources = { tool = {} } })
    local morrow = entry({ key = "Morrow", intent = "player", activities = { "dungeon:wc" }, leader = { name = "Morrow", class = "ROGUE", level = 20 },
        roles = { offered = { damage = true } }, sources = { chat = { channel = "LookingForGroup", text = "20 rogue lfg WC", confidence = 0.8 } } })
    local dorran = entry({ key = "Dorran", intent = "group", activities = { "zone:wetlands" }, members = { 3, 5 },
        leader = { name = "Dorran", class = "PALADIN", level = 26 }, sources = { chat = { channel = "SAY", text = "LF2M Wetlands elites", confidence = 0.6 } } })
    for _, n in ipairs({ { "role", kessra }, { "fresh", brannoc }, { "zone", dorran }, { "friends", morrow }, { "player", morrow } }) do
        local d = self:MatchNote(n[1], n[2])
        d.id = d.id .. ":" .. n[1]
        -- a test never whispers or invites anyone
        for _, a in ipairs(d.actions or {}) do a.onClick = function() SuuUI.DismissNotification(d.id) end end
        SuuUI.Notify(d)
    end
    SuuUI.Notify({ id = "lfg:test:stale", kind = "until", tone = "warning", category = "Results are stale", icon = { glyph = "hourglass" },
        title = "Tool results are 9 minutes old", body = "You’re listed for Shadowfang Keep and 2 more. Chat stays live; the tool only searches on your click.",
        ["until"] = "Goes when you refresh", actions = { { label = "Delist", icon = "close", onClick = function() SuuUI.DismissNotification("lfg:test:stale") end },
            { label = "Refresh", variant = "primary", icon = "reset", onClick = function() SuuUI.DismissNotification("lfg:test:stale") end } } })
    SuuUI.Notify({ id = "lfg:test:delisted", kind = "sticky", category = "You were delisted", icon = { glyph = "close" },
        title = "Your listing has ended", body = "Listed 30 minutes for Shadowfang Keep, Deadmines and Wailing Caverns." })
end
