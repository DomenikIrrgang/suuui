-- Units/GroupFinder.lua
-- SuuUI's Group Finder (design component GroupFinder) on ForeverLFG
-- (SuuUI.LFG, Docs/ForeverLFG.md): the game's group finder window (I) in
-- SuuUI's look (the windows module) with SuuUI's pages over Blizzard's.
--   Browse  one list of groups and players looking, from the tool and from
--           chat, in Groups and Players; filters; the tool's age and
--           Refresh (the tool searches only on a click)
--   List yourself  the game's own listing panel in SuuUI's look (its
--           controls stay the game's: addons can't list you)
-- Starting the module starts the library (it joins LookingForGroup and keeps
-- it out of chat); turning it off stops it.
-- A built-in module written against the public API only.

local UI = SuuUI.UI
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
        chatExpiry = 300, staleAfter = 300,
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
    local slots = {}
    if e.intent == "group" then
        local have = e.members and e.members[1] or 0
        for _ = 1, have do slots[#slots + 1] = "member" end
        local needed = 0
        for _, role in ipairs({ "tank", "healer", "damage" }) do
            local n = e.roles.needed[role]
            n = (type(n) == "number" and n) or (n and 1) or 0
            for _ = 1, n do slots[#slots + 1] = "need:" .. role; needed = needed + 1 end
        end
        local max = e.members and e.members[2]
        if max and max <= 10 then
            for _ = 1, math.max(0, max - have - needed) do slots[#slots + 1] = "open" end
        end
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
        slots = slots, mine = interest.roles, members = e.members, sources = sources, age = ago(age),
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
    self:Wire(b)
    -- List yourself: the game's own panel, restyled (stage 3)
    if _G.LFGListingFrame then UI.SkinGroupFinderListing(_G.LFGListingFrame) end
    f:HookScript("OnShow", function() self:Follow() end)
    f:HookScript("OnHide", function() GameTooltip:Hide() end)
    for _, c in ipairs({ _G.LFGBrowseFrame, _G.LFGListingFrame, _G.LFGWhoListFrame }) do
        if c then
            c:HookScript("OnShow", function() self:Follow() end)
            c:HookScript("OnHide", function() self:Follow() end)
        end
    end
    self:Follow()
end

function M:OnEnable()
    LFG.Configure({ chatExpiry = self:Get("chatExpiry"), staleAfter = self:Get("staleAfter") })
    LFG.Start()
    -- the list follows the library
    for _, ev in ipairs({ "EntryAdded", "EntryUpdated", "EntryRemoved", "ListingChanged" }) do
        LFG.On(ev, function() self:QueueRender() end)
    end
    LFG.On("ToolSearched", function() self.searching = nil; self:QueueRender() end)
    LFG.On("ToolSearchFailed", function() self.searching = nil; self:QueueRender() end)
    -- the tool's age moves on
    C_Timer.NewTicker(15, function() if self.browse and self.browse:IsVisible() then self:Render() end end)
    self:Build()
    self:OnGameEvent("ADDON_LOADED", function() self:Build() end)
end

function M:OnDisable()
    LFG.Stop()
end
