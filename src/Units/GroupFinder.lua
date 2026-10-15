-- Units/GroupFinder.lua
-- SuuUI's Group Finder (design component GroupFinder) on ForeverLFG
-- (SuuUI.LFG, Docs/ForeverLFG.md): the game's group finder window (I) in
-- SuuUI's look (the windows module) with SuuUI's pages over Blizzard's.
--   Browse  one list of groups and players looking, from the tool and from
--           chat, in Groups and Players; filters; the tool's age and
--           Refresh (the tool searches only on a click)
--   List yourself  the game's own listing panel in SuuUI's look (its
--           controls stay the game's: addons can't list you)
--   Notes   ForeverLFG's eleven kinds as SuuUI notifications (design board
--           "Notifications · Group Finder"), each on or off with its
--           options (defaults from "Settings · Group Finder ·
--           Notifications"; the settings page comes in stage 4)
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
    self.cover:SetShown(on and true or false)
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
    self:StartNotes()
end

function M:OnDisable()
    LFG.Stop()
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
