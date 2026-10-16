-- Units/Notifications.lua
-- Notifications (step 2.4): a stack at the top left under the micro menu.
-- Requests are Blizzard's own popups (party invite, resurrection, summon,
-- duel, trade, release spirit, delete item, logout, battleground entry …)
-- and its battleground-ready and ready-check windows
-- shown as SuuUI cards; notes come from SuuUI.Notify (timed, sticky, or
-- until something happens). At most five show (the rest behind "+N more"),
-- requests first; in combat only requests and conditions.
-- A built-in module written against the public API only.
--
-- Hosting: SuuUI never answers a popup itself. Calling Blizzard's popup code
-- from an addon would make the popup system SuuUI's, and the game would
-- then refuse the answers it keeps for Blizzard (deleting an item, entering
-- a battleground, cancelling a logout: probed 2026-10-13). Instead the
-- popup goes off screen and its own buttons (and its "type DELETE" box) are
-- placed on the card and drawn in SuuUI's look: every click is Blizzard's
-- (a logout cancelled from a moved popup worked). Nothing is written on
-- Blizzard's frames but points, sizes, alphas and fonts, and all of it goes
-- back when the popup closes. Popups SuuUI doesn't know stay Blizzard's.

local UI, T = SuuUI.UI, SuuUI.Tokens
local S = T.space

local M = SuuUI.RegisterModule({
    id = "notifications",
    name = "Notifications",
    description = "Requests (invites, resurrection, summons, duels, trades, deleting items, logging out) and notes as SuuUI cards at the top left.",
    api = "0.11",
    combatSafe = true,
    reloadToToggle = true,
    defaults = {
        -- under the micro menu (28px down, 36px tall), space-5 clear
        position = { point = "TOPLEFT", x = 28, y = -76 },
        max = 5,
        requests = true,   -- Blizzard's popups as cards
        durability = true, -- a note while your gear is badly damaged or broken
        bagsFull = true,   -- a note while your bags are full
        talentPoints = true, -- a note while you have talent points to spend
        legacyPoints = true, -- a note while you have Legacy points to spend
        -- friends and guild members coming online / going offline
        presenceBnetOnline = true, presenceBnetOffline = true,
        presenceFriendOnline = true, presenceFriendOffline = true,
        presenceGuildOnline = true, presenceGuildOffline = false,
        presenceHideChat = true, -- the game's own lines in chat hidden
    },
})

local isSecret = issecretvalue or function() return false end
local function plain(v) return v ~= nil and not isSecret(v) end
local ACTION_H = 26
local OFF_SCREEN = 200

-- The popups SuuUI shows as cards: caption, glyph, tone, which button is the
-- main answer (primary) or the dangerous one, the item it's about.
local KINDS = {
    PARTY_INVITE = { category = "Party invite", glyph = "people", primary = 1 },
    GROUP_INVITE_CONFIRMATION = { category = "Group invite", glyph = "people", primary = 1 },
    RESURRECT = { category = "Resurrection", glyph = "plus", primary = 1 },
    RESURRECT_NO_SICKNESS = { category = "Resurrection", glyph = "plus", primary = 1 },
    RESURRECT_NO_TIMER = { category = "Resurrection", glyph = "plus", primary = 1 },
    CONFIRM_SUMMON = { category = "Summon", glyph = "map", primary = 1 },
    CONFIRM_SUMMON_SCENARIO = { category = "Summon", glyph = "map", primary = 1 },
    CONFIRM_SUMMON_STARTING_AREA = { category = "Summon", glyph = "map", primary = 1 },
    DUEL_REQUESTED = { category = "Duel", glyph = "sword", primary = 1 },
    DUEL_OUTOFBOUNDS = { category = "Duel", glyph = "sword", tone = "warning" },
    TRADE = { category = "Trade", glyph = "coin", primary = 1 },
    DEATH = { category = "You died", glyph = "skull", tone = "warning", primary = 1 },
    RECOVER_CORPSE = { category = "Your corpse", glyph = "skull", primary = 1 },
    RECOVER_CORPSE_INSTANCE = { category = "Your corpse", glyph = "skull" },
    AREA_SPIRIT_HEAL = { category = "Spirit healer", glyph = "skull", primary = 1 },
    XP_LOSS = { category = "Spirit healer", glyph = "skull", tone = "warning" },
    DELETE_ITEM = { category = "Delete item", glyph = "trash", tone = "danger", danger = 1, item = true },
    DELETE_GOOD_ITEM = { category = "Delete item", glyph = "trash", tone = "danger", danger = 1, item = true, confirm = true },
    DELETE_QUEST_ITEM = { category = "Delete quest item", glyph = "trash", tone = "danger", danger = 1, item = true },
    DELETE_GOOD_QUEST_ITEM = { category = "Delete quest item", glyph = "trash", tone = "danger", danger = 1, item = true, confirm = true },
    CAMP = { category = "Logging out", glyph = "door" },
    QUIT = { category = "Quitting", glyph = "door", danger = 1 },
    CONFIRM_BATTLEFIELD_ENTRY = { category = "Battleground", glyph = "flag", primary = 1 },
    BFMGR_INVITED_TO_ENTER = { category = "Battleground", glyph = "flag", primary = 1 },
    INSTANCE_LOCK = { category = "Instance lock", glyph = "hourglass", tone = "warning", primary = 1 },
    INSTANCE_BOOT = { category = "Leaving the instance", glyph = "door", tone = "danger" },
    LOOT_BIND = { category = "Binds when picked up", glyph = "gem", primary = 1 },
    EQUIP_BIND = { category = "Binds when equipped", glyph = "gem", primary = 1 },
    USE_BIND = { category = "Binds when used", glyph = "gem", primary = 1 },
    CONFIRM_LOOT_ROLL = { category = "Loot roll", glyph = "gem", primary = 1 },
    ABANDON_QUEST = { category = "Abandon quest", glyph = "scroll", tone = "danger", danger = 1 },
    QUEST_ACCEPT = { category = "Quest", glyph = "scroll", primary = 1 },
    CONFIRM_TALENT_WIPE = { category = "Talents", glyph = "tree", tone = "warning" },
}

--------------------------------------------------------------------------------
-- Notes (SuuUI.Notify)
--------------------------------------------------------------------------------

local nextNote = 0

-- def: { id?, kind = "timed"|"sticky"|"until"|"roll", category, title, body,
-- icon, tone, duration (timed, default 8), ["until"] (the text), actions }
-- → id. A request (roll) with duration and remaining counts down on its own
-- and stays until it is dismissed.
function M:Notify(def)
    if type(def) ~= "table" then return nil end
    nextNote = nextNote + 1
    local id = def.id or ("note:" .. nextNote)
    local d = {}
    for k, v in pairs(def) do d[k] = v end
    d.id = id
    d.kind = d.kind or "timed"
    if d.kind == "timed" then
        d.duration = d.duration or 8
        d.endsAt = GetTime() + d.duration
        d.remaining = d.duration
    elseif d.duration and d.remaining then
        d.endsAt = GetTime() + d.remaining
    end
    d.onClose = function() self:Dismiss(id) end
    -- the same id again: replaced in place
    if not self.notes[id] then self.noteOrder[#self.noteOrder + 1] = id end
    self.notes[id] = d
    self:Rebuild()
    return id
end

function M:Dismiss(id)
    if not self.notes[id] then return end
    self.notes[id] = nil
    for i, x in ipairs(self.noteOrder) do
        if x == id then table.remove(self.noteOrder, i) break end
    end
    self:Rebuild()
end

function M:DismissAll()
    for id, d in pairs(self.notes) do
        if d.kind == "sticky" then self:Dismiss(id) end
    end
end

--------------------------------------------------------------------------------
-- SuuUI's own notes about the game
--------------------------------------------------------------------------------

-- Your gear: the worst piece's durability (0 broken, nil nothing to wear out).
local function worstDurability()
    local worst
    for slot = 1, 19 do
        local cur, max = GetInventoryItemDurability(slot)
        if plain(cur) and plain(max) and cur and max and max > 0 then
            local r = cur / max
            if not worst or r < worst then worst = r end
        end
    end
    return worst
end

function M:CheckDurability()
    local worst = self:Get("durability") and worstDurability()
    -- only when it changes (durability moves with every hit in combat)
    local state = (worst and worst <= 0 and "broken") or (worst and worst <= 0.2 and "damaged") or "fine"
    if state == self.durabilityState then return end
    self.durabilityState = state
    if worst and worst <= 0 then
        self:Notify({ id = "suu:durability", kind = "until", tone = "danger", category = "Durability",
            title = "Some of your gear is broken", icon = { glyph = "anvil" }, ["until"] = "Goes when you repair" })
    elseif worst and worst <= 0.2 then
        self:Notify({ id = "suu:durability", kind = "until", tone = "warning", category = "Durability",
            title = "Your gear is badly damaged", icon = { glyph = "anvil" }, ["until"] = "Goes when you repair" })
    elseif self.notes["suu:durability"] then
        self:Dismiss("suu:durability")
    end
end

-- Free slots in your general bags (backpack and bags 1-4; special bags
-- hold only their own kind).
local function freeSlots()
    local free = 0
    for bag = 0, (NUM_BAG_SLOTS or 4) do
        local n, family = C_Container.GetContainerNumFreeSlots(bag)
        if plain(n) and n and (not plain(family) or family == 0 or family == nil) then free = free + n end
    end
    return free
end

function M:CheckBags()
    if self:Get("bagsFull") and freeSlots() == 0 then
        if not self.notes["suu:bags"] then
            self:Notify({ id = "suu:bags", kind = "until", tone = "warning", category = "Bags",
                title = "Your bags are full", icon = { glyph = "bag" }, ["until"] = "Goes when you free a slot" })
        end
    elseif self.notes["suu:bags"] then
        self:Dismiss("suu:bags")
    end
end

-- Talent points not spent yet (the active talent config's points to spend).
local function unspentTalents()
    if not (C_ClassTalents and C_ClassTalents.GetActiveConfigID and C_Traits) then return 0 end
    local ok, configID = pcall(C_ClassTalents.GetActiveConfigID)
    if not ok or not plain(configID) or not configID then return 0 end
    local info = C_Traits.GetConfigInfo(configID)
    local treeID = info and info.treeIDs and info.treeIDs[1]
    if not treeID then return 0 end
    local ok2, currency = pcall(C_Traits.GetTreeCurrencyInfo, configID, treeID, false)
    local q = ok2 and currency and currency[1] and currency[1].quantity
    return plain(q) and q or 0
end

function M:CheckTalents()
    local n = self:Get("talentPoints") and unspentTalents() or 0
    if n == self.talentPointsShown then return end
    self.talentPointsShown = n
    if n > 0 then
        local talents = SuuUI.GetModule("talents")
        local actions
        if talents and talents:IsEnabled() then
            actions = { { label = "Open talents", variant = "primary", onClick = function()
                if not SuuUI.TalentsShown() then SuuUI.ToggleTalents() end
            end } }
        end
        self:Notify({ id = "suu:talents", kind = "until", tone = "info", category = "Talents",
            title = n == 1 and "1 talent point to spend" or (n .. " talent points to spend"),
            icon = { glyph = "tree" }, ["until"] = "Goes when you spend them", actions = actions })
    elseif self.notes["suu:talents"] then
        self:Dismiss("suu:talents")
    end
end

-- Legacy points this character can still spend (the Legacy trees' currency;
-- one config for all three trees: 1187 is Professions).
local LEGACY_TREE = 1187
local function unspentLegacy()
    if not (C_Traits and C_Traits.GetConfigIDByTreeID) then return 0 end
    local ok, configID = pcall(C_Traits.GetConfigIDByTreeID, LEGACY_TREE)
    if not ok or not plain(configID) or not configID then return 0 end
    local ok2, currency = pcall(C_Traits.GetTreeCurrencyInfo, configID, LEGACY_TREE, false)
    local q = ok2 and currency and currency[1] and currency[1].quantity
    return plain(q) and q or 0
end

-- Open Legacy: Blizzard's own key (ToggleLegacySystemUI) only shows the
-- window, which isn't one of the panels Blizzard's window manager places,
-- so showing it from here taints nothing Esc relies on (checked in
-- Blizzard's code, 2026-10-14).
local function openLegacy()
    if not _G.LegacySystemFrame and C_AddOns and C_AddOns.LoadAddOn then pcall(C_AddOns.LoadAddOn, "Blizzard_LegacySystem") end
    local f = _G.LegacySystemFrame
    if f and not f:IsShown() then f:Show() end
end

function M:CheckLegacy()
    local n = self:Get("legacyPoints") and unspentLegacy() or 0
    if n == self.legacyPointsShown then return end
    self.legacyPointsShown = n
    if n > 0 then
        self:Notify({ id = "suu:legacy", kind = "until", tone = "info", category = "Legacy",
            title = n == 1 and "1 Legacy point to spend" or (n .. " Legacy points to spend"),
            icon = { glyph = "trophy" }, ["until"] = "Goes when you spend them",
            actions = { { label = "Open Legacy", variant = "primary", onClick = openLegacy } } })
    elseif self.notes["suu:legacy"] then
        self:Dismiss("suu:legacy")
    end
end

--------------------------------------------------------------------------------
-- Friends and guild members coming online and going offline (design board
-- "Notifications · Friends"; probed 2026-10-14). Character friends and
-- guild members come as the game's system line ("[Name] has come online.",
-- "Name has gone offline."); Battle.net friends as their own events. Who it
-- is decides the card: a Battle.net friend, a friend, a guild member.
-- Arrivals within a few seconds share one card; in combat they wait. The
-- game's own lines in chat (and its Battle.net toast) can be hidden.
--------------------------------------------------------------------------------

-- A pattern from one of the game's format strings: "%s" a capture, the
-- rest literal.
local function patternOf(fmt)
    if type(fmt) ~= "string" then return nil end
    local parts = {}
    -- the text between the "%s"s (one more "%s" at the end closes the last)
    for piece in (fmt .. "%s"):gmatch("(.-)%%s") do
        parts[#parts + 1] = (piece:gsub("([%^%$%(%)%%%.%[%]%*%+%-%?])", "%%%1"))
    end
    return "^" .. table.concat(parts, "(.-)") .. "$"
end

local ONLINE = patternOf(ERR_FRIEND_ONLINE_SS)    -- link, name
local OFFLINE = patternOf(ERR_FRIEND_OFFLINE_S)   -- name
local BATCH = 2.5                                  -- seconds that share one card

local CLASS_FILES = {}
for _, list in ipairs({ LOCALIZED_CLASS_NAMES_MALE or {}, LOCALIZED_CLASS_NAMES_FEMALE or {} }) do
    for file, name in pairs(list) do CLASS_FILES[name] = file end
end

local GAMES = { App = "Battle.net", BSAp = "Battle.net Mobile", WTCG = "Hearthstone", Hero = "Heroes of the Storm",
                Pro = "Overwatch", S2 = "StarCraft II", S1 = "StarCraft", D3 = "Diablo III", Fen = "Diablo IV",
                ANBS = "Diablo Immortal", VIPR = "Call of Duty", W3 = "Warcraft III", GRY = "Warcraft Rumble" }

local function classIcon(file)
    local c = file and CLASS_ICON_TCOORDS and CLASS_ICON_TCOORDS[file]
    if not c then return nil end
    return { texture = "Interface\\Glues\\CharacterCreate\\UI-CharacterCreate-Classes", coords = c }
end

local function classColor(file)
    return file and T.color["class-" .. file:lower()] and ("class-" .. file:lower()) or nil
end

local function whisper(name)
    local tell = (ChatFrameUtil and ChatFrameUtil.SendTell) or ChatFrame_SendTell
    if tell then tell(name) end
end

local function invite(name)
    local fn = (C_PartyInfo and C_PartyInfo.InviteUnit) or InviteUnit
    if fn then pcall(fn, name) end
end

-- A character friend or guild member by name: kind and the card's person.
function M:WhoIs(name)
    local short = Ambiguate and Ambiguate(name, "short") or name
    local fl = C_FriendList
    local info = fl and fl.GetFriendInfo and fl.GetFriendInfo(short)
    if info and plain(info.name) then
        local file = info.guid and select(2, GetPlayerInfoByGUID(info.guid)) or CLASS_FILES[info.className or ""]
        local where = {}
        if info.level and info.level > 0 then where[#where + 1] = "Level " .. info.level end
        if plain(info.area) and info.area and info.area ~= "" then where[#where + 1] = info.area end
        return "friend", { name = short, color = classColor(file), icon = classIcon(file),
            detail = table.concat(where, " · "), whisper = function() whisper(name) end, inviteName = name }
    end
    if IsInGuild() then
        for i = 1, (GetNumGuildMembers()) or 0 do
            local full, rank, _, level, _, zone, _, _, _, _, file = GetGuildRosterInfo(i)
            if full and (Ambiguate and Ambiguate(full, "short") or full) == short then
                local where = {}
                if rank and rank ~= "" then where[#where + 1] = rank end
                if level and level > 0 then where[#where + 1] = "Level " .. level end
                if zone and zone ~= "" then where[#where + 1] = zone end
                return "guild", { name = short, color = classColor(file), icon = classIcon(file),
                    detail = table.concat(where, " · "), whisper = function() whisper(full) end, inviteName = full }
            end
        end
    end
    return nil
end

-- A Battle.net friend's card person (their account name is protected text
-- the game draws; SuuUI never reads it).
function M:BnetPerson(accountID)
    local info = C_BattleNet and C_BattleNet.GetAccountInfoByID and C_BattleNet.GetAccountInfoByID(accountID)
    if not info then return nil end
    local game = info.gameAccountInfo or {}
    local person = { name = info.accountName or info.battleTag or "?" }
    if plain(info.battleTag) and info.battleTag then person.tag = info.battleTag:match("(#%d+)$") end
    person.whisper = function()
        local tell = (ChatFrameUtil and ChatFrameUtil.SendBNetTell) or ChatFrame_SendBNetTell
        if tell and info.accountName then tell(info.accountName) end
    end
    if game.clientProgram == (BNET_CLIENT_WOW or "WoW") and plain(game.characterName) and game.characterName then
        local file = CLASS_FILES[game.className or ""]
        person.color = classColor(file)
        person.icon = classIcon(file)
        local where = plain(game.richPresence) and game.richPresence ~= "" and game.richPresence
            or (plain(game.areaName) and game.areaName) or "World of Warcraft"
        person.detail = game.characterName .. " · " .. where
        -- invited by their game account, as the game's friends list does (by
        -- name and realm the game didn't find them; found in game)
        if game.wowProjectID == WOW_PROJECT_ID and game.gameAccountID then
            local id = game.gameAccountID
            person.invite = function()
                local fn = (C_BattleNet and C_BattleNet.InviteFriend) or BNInviteFriend
                if fn then pcall(fn, id) end
            end
        end
    else
        person.detail = GAMES[game.clientProgram or ""] or "Battle.net"
    end
    return person
end

local KINDS_OF = {
    bnet = { setting = "presenceBnet", source = "Battle.net", plural = "Battle.net friends", glyph = "people" },
    friend = { setting = "presenceFriend", source = "Friend", plural = "friends", glyph = "people" },
    guild = { setting = "presenceGuild", plural = "guild members", glyph = "flag" },
}

-- One more arrival or departure; a card once the burst is over.
function M:Presence(kind, online, person)
    local k = KINDS_OF[kind]
    if not (k and person) then return end
    if not self:Get(k.setting .. (online and "Online" or "Offline")) then return end
    self.presence = self.presence or {}
    local key = kind .. (online and "+" or "-")
    local q = self.presence[key]
    if not q then
        q = { kind = kind, online = online, people = {} }
        self.presence[key] = q
        C_Timer.After(BATCH, function() self:FlushPresence(key) end)
    end
    for _, x in ipairs(q.people) do if x.name == person.name then return end end
    q.people[#q.people + 1] = person
end

function M:FlushPresence(key)
    local q = self.presence and self.presence[key]
    if not q then return end
    -- in combat they wait for the fight's end
    if InCombatLockdown() then q.held = true return end
    self.presence[key] = nil
    if not self:IsEnabled() or #q.people == 0 then return end
    local k = KINDS_OF[q.kind]
    local source = k.source or (GetGuildInfo("player")) or "Guild"
    local single = #q.people == 1 and q.people[1]
    self.presenceCount = (self.presenceCount or 0) + 1
    self:Notify({ id = "suu:presence:" .. self.presenceCount, kind = "timed", duration = q.online and 6 or 4,
        presence = { online = q.online, source = source, people = q.people, plural = k.plural, glyph = k.glyph,
                     invite = q.online and single and (single.invite
                         or single.inviteName and function() invite(single.inviteName) end) or nil } })
end

-- The game's system line: who, and whether it's theirs to show.
function M:SystemLine(msg)
    if not plain(msg) or type(msg) ~= "string" then return end
    local online, name = true, nil
    if ONLINE then
        local _, n = msg:match(ONLINE)
        name = n
    end
    if not name and OFFLINE then
        name = msg:match(OFFLINE)
        online = false
    end
    if not name or Ambiguate(name, "short") == SuuUI.FullName("player") then return end
    -- a link's name keeps its colour codes out
    name = name:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
    local kind, person = self:WhoIs(name)
    if kind then self:Presence(kind, online, person) end
end

-- Is this one of the game's online/offline lines (for the chat filter)?
local function isPresenceLine(msg)
    if not plain(msg) or type(msg) ~= "string" then return false end
    return (ONLINE and msg:match(ONLINE) ~= nil) or (OFFLINE and msg:match(OFFLINE) ~= nil)
end

function M:HookPresence()
    if self.presenceHooked then return end
    self.presenceHooked = true
    local add = (ChatFrameUtil and ChatFrameUtil.AddMessageEventFilter) or ChatFrame_AddMessageEventFilter
    if add then
        add("CHAT_MSG_SYSTEM", function(_, _, msg)
            if self:IsEnabled() and self:Get("presenceHideChat") and isPresenceLine(msg) then return true end
            return false
        end)
        add("CHAT_MSG_BN_INLINE_TOAST_ALERT", function(_, _, process)
            if self:IsEnabled() and self:Get("presenceHideChat")
                and (process == "FRIEND_ONLINE" or process == "FRIEND_OFFLINE") then return true end
            return false
        end)
    end
    -- Battle.net's own toast (bottom right) for the same: away while SuuUI
    -- shows Battle.net friends
    local toast = _G.BNToastFrame
    if toast then
        toast:HookScript("OnShow", function(f)
            if not self:IsEnabled() then return end
            local t = f.toastType
            local online = t == (BN_TOAST_TYPE_ONLINE or 1)
            local offline = t == (BN_TOAST_TYPE_OFFLINE or 2)
            if (online and self:Get("presenceBnetOnline")) or (offline and self:Get("presenceBnetOffline")) then f:Hide() end
        end)
    end
end

-- Test: one card of each (no one has to log in). The single cards are your
-- own character, so Whisper and Invite really act (on you); the group card
-- is made up.
function M:TestPresence()
    -- the whole name: Forever's characters have a surname (UnitName's
    -- second value), which whispers need
    local full = SuuUI.FullName("player")
    local me = full
    local _, file = UnitClass("player")
    local zone = GetRealZoneText and GetRealZoneText() or ""
    local function mine(detail)
        return { name = me, color = classColor(file), icon = classIcon(file), detail = detail,
                 whisper = function() whisper(full) end, inviteName = full }
    end
    local function sample(name, f)
        return { name = name, color = classColor(f), icon = classIcon(f), whisper = function() whisper(name) end }
    end
    local function card(kind, online, people)
        local k = KINDS_OF[kind]
        local single = #people == 1 and people[1]
        self.presenceCount = (self.presenceCount or 0) + 1
        self:Notify({ id = "suu:presence:" .. self.presenceCount, kind = "timed", duration = online and 20 or 15,
            presence = { online = online, source = k.source or (GetGuildInfo("player")) or "Guild", people = people,
                         plural = k.plural, glyph = k.glyph,
                         invite = online and single and single.inviteName and function() invite(single.inviteName) end or nil } })
    end
    local bn = mine(me .. " · " .. zone)
    bn.tag = "#1137"
    card("bnet", true, { bn })
    card("friend", true, { mine("Level " .. UnitLevel("player") .. " · " .. zone) })
    local rank = select(2, GetGuildInfo("player"))
    card("guild", true, { mine((rank and (rank .. " · ") or "") .. "Level " .. UnitLevel("player") .. " · " .. zone) })
    card("guild", true, { sample("Lyra", "MAGE"), sample("Thorn", "ROGUE"), sample("Maelis", "PALADIN"), sample("Durn", "HUNTER") })
    card("guild", false, { sample("Ysolde", "DRUID") })
end

--------------------------------------------------------------------------------
-- Hosting Blizzard's popups
--------------------------------------------------------------------------------

local function buttonsOf(dialog)
    local out = {}
    local bc = dialog.ButtonContainer
    for i = 1, 4 do
        local b = (bc and bc["Button" .. i]) or _G[dialog:GetName() .. "Button" .. i]
        if b and b:IsShown() then out[#out + 1] = { button = b, index = i } end
    end
    return out
end

local function savePoints(f)
    local pts = {}
    for i = 1, f:GetNumPoints() do pts[i] = { f:GetPoint(i) } end
    return pts
end

local function restorePoints(f, pts)
    f:ClearAllPoints()
    for _, p in ipairs(pts or {}) do f:SetPoint(unpack(p)) end
end

-- What we change on a Blizzard button or edit box, and how it was.
function M:Remember(h, f)
    h.saved = h.saved or {}
    if h.saved[f] then return h.saved[f] end
    local s = { points = savePoints(f), width = f:GetWidth(), height = f:GetHeight(), alphas = {},
        strata = f:GetFrameStrata(), level = f:GetFrameLevel() }
    for _, r in ipairs({ f:GetRegions() }) do
        if r:GetObjectType() == "Texture" then s.alphas[r] = r:GetAlpha() end
    end
    -- a button's state textures (not always among its regions)
    for _, get in ipairs({ "GetNormalTexture", "GetPushedTexture", "GetHighlightTexture", "GetDisabledTexture",
                           "GetCheckedTexture", "GetDisabledCheckedTexture" }) do
        local t = f[get] and f[get](f)
        if t and s.alphas[t] == nil then s.alphas[t] = t:GetAlpha() end
    end
    local fs = f.GetFontString and f:GetFontString()
    if fs then s.font, s.fs, s.color = fs:GetFontObject(), fs, { fs:GetTextColor() } end
    if f.GetFontObject and f:GetObjectType() == "EditBox" then s.font = f:GetFontObject() end
    h.saved[f] = s
    return s
end

function M:Undo(h)
    -- every part loose first: the buttons hang off each other here (each
    -- beside the next) and in Blizzard's layout the other way round, so
    -- restoring one by one anchored a button to one depending on it (an
    -- error, found in game)
    for f in pairs(h.saved or {}) do f:ClearAllPoints() end
    for f, s in pairs(h.saved or {}) do
        if self.widths then self.widths[f] = nil end
        restorePoints(f, s.points)
        f:SetSize(s.width, s.height)
        if s.strata then f:SetFrameStrata(s.strata) end
        if s.level then f:SetFrameLevel(s.level) end
        for r, a in pairs(s.alphas) do r:SetAlpha(a) end
        if s.fs and s.font then s.fs:SetFontObject(s.font) end
        if s.fs and s.color then s.fs:SetTextColor(unpack(s.color)) end
        if f:GetObjectType() == "EditBox" and s.font then f:SetFontObject(s.font) end
        local art = self.arts[f]
        if art then art:Hide() end
    end
    h.saved = nil
end

-- SuuUI's look behind a Blizzard button: quiet (surface-raised, gilt-line),
-- primary (arcane) or danger (ember edge); hover brightens the edge.
function M:ArtFor(b)
    local art = self.arts[b]
    if art then return art end
    art = CreateFrame("Frame", nil, self.stack)
    art.fill = UI.Fill(art, "surface-raised", "BACKGROUND")
    art.fill:SetAllPoints()
    art.edge = UI.Border(art, "gilt-line")
    art.glow = UI.Shadow(art, "glow-arcane")
    art.glow:SetShown(false)
    self.arts[b] = art
    b:HookScript("OnEnter", function()
        if not art:IsShown() then return end
        if art.variant == "primary" then art.glow:SetShown(true) else art.edge:SetColor(art.variant == "danger" and "ember" or "gilt") end
    end)
    b:HookScript("OnLeave", function()
        if not art:IsShown() then return end
        art.glow:SetShown(false)
        art.edge:SetColor(art.variant == "primary" and "arcane" or art.variant == "danger" and "ember" or "gilt-line")
    end)
    return art
end

function M:StyleButton(h, b, variant)
    local s = self:Remember(h, b)
    for r in pairs(s.alphas) do r:SetAlpha(0) end
    local fs = b:GetFontString()
    if fs then
        fs:SetFontObject(SuuUI.Fonts.Get("label"))
        fs:SetTextColor(UI.RGBA(variant == "primary" and "on-signal" or variant == "danger" and "ember-text" or "ink"))
    end
    local w = math.max(64, math.ceil((fs and fs:GetUnboundedStringWidth() or 40) + S["space-4"] * 2))
    -- and kept: Blizzard sizes its popup buttons again after showing them
    -- (both 120 wide on the death popup, found in game: Release Spirit
    -- over Recap)
    self.widths = self.widths or {}
    self.widths[b] = w
    if not self.widthHooked then self.widthHooked = {} end
    if not self.widthHooked[b] then
        self.widthHooked[b] = true
        local function keep()
            local want = self.widths[b]
            if not want or self.sizing or math.abs(b:GetWidth() - want) < 0.5 then return end
            self.sizing = true
            b:SetSize(want, ACTION_H)
            self.sizing = false
        end
        hooksecurefunc(b, "SetWidth", keep)
        hooksecurefunc(b, "SetSize", keep)
    end
    b:SetSize(w, ACTION_H)
    local art = self:ArtFor(b)
    art.variant = variant
    art:SetFrameStrata(b:GetFrameStrata())
    art:SetFrameLevel(math.max(0, b:GetFrameLevel() - 1))
    art:ClearAllPoints()
    art:SetAllPoints(b)
    art.fill:SetColorTexture(UI.RGBA(variant == "primary" and "arcane" or "surface-raised"))
    art.edge:SetColor(variant == "primary" and "arcane" or variant == "danger" and "ember" or "gilt-line")
    art.glow:SetShown(false)
    art:Show()
    return w
end

function M:StyleEditBox(h, eb, box)
    local s = self:Remember(h, eb)
    for r in pairs(s.alphas) do r:SetAlpha(0) end
    eb:SetFontObject(SuuUI.Fonts.Get("body"))
    eb:ClearAllPoints()
    eb:SetPoint("TOPLEFT", box, "TOPLEFT", S["space-4"], 0)
    eb:SetPoint("BOTTOMRIGHT", box, "BOTTOMRIGHT", -S["space-4"], 0)
end

-- The card's data for a hosted popup.
function M:CardData(h)
    local kind = h.kind
    local text = h.text()
    local d = {
        id = h.id, kind = "action", tone = kind.tone, category = kind.category,
        title = plain(text) and text or (kind.title or ""), icon = { glyph = kind.glyph },
        host = { buttons = #h.buttons(), roles = h.roles and #h.roles() or nil },
    }
    local warning = h.warning and h.warning()
    if plain(warning) and warning and warning ~= "" then d.warning = warning end
    local duration, remaining = h.time()
    if duration then d.duration, d.remaining = duration, remaining end
    if kind.item then
        local what, _, link = GetCursorInfo()
        if what == "item" and plain(link) and link then
            local name, _, quality, _, _, _, _, _, _, icon = C_Item.GetItemInfo(link)
            local qualities = { [0] = "poor", "common", "uncommon", "rare", "epic", "legendary" }
            d.item = { icon = icon, label = name or link, quality = qualities[quality or 1] or "common" }
        end
    end
    if kind.confirm and h.editBox and h.editBox:IsShown() then
        d.confirmText = (DELETE_ITEM_CONFIRM_STRING or "DELETE")
    end
    return d
end

-- The popup's own buttons and edit box onto its card.
function M:Attach(h)
    local card = self.stack:CardFor(h.id)
    if not card then
        -- not among the shown cards: its parts back in the (off screen) popup
        self:Undo(h)
        h.card = nil
        return
    end
    h.card = card
    local kind = h.kind
    -- right to left, each beside the one after it: a width Blizzard sets
    -- later can't make them overlap
    local list = h.buttons()
    local after
    for k = #list, 1, -1 do
        local b, index = list[k].button, list[k].index
        local variant = (index == kind.primary and "primary") or (index == kind.danger and "danger") or "quiet"
        -- over their card, which is on the dialog layer now
        self:Remember(h, b)
        b:SetFrameStrata(card:GetFrameStrata())
        b:SetFrameLevel(card:GetFrameLevel() + 10)
        self:StyleButton(h, b, variant)
        b:ClearAllPoints()
        if after then
            b:SetPoint("RIGHT", after, "LEFT", -S["space-3"], 0)
        else
            b:SetPoint("RIGHT", card.actionsRow, "RIGHT", 0, 0)
        end
        after = b
    end
    local eb = h.editBox
    if card.data and card.data.confirmText and eb then
        self:Remember(h, eb)
        eb:SetFrameStrata(card:GetFrameStrata())
        eb:SetFrameLevel(card:GetFrameLevel() + 10)
        self:StyleEditBox(h, eb, card.confirmBox)
    end
    if h.roles and card.rolesRow then
        for i, b in ipairs(h.roles()) do self:HostRole(h, card, b, i) end
    end
end

-- A group invite's role buttons (the game's, with their checkboxes, clicks
-- and tooltips) as SuuUI's round role toggles on the card: the icon in a
-- circle, the role's name under it, a 14px box on its corner. On: arcane;
-- one the game has disabled (your class can't, or the group has no room;
-- its tooltip says which) at opacity-disabled.
local ROLE_TEX = { TANK = "RoleTank.tga", HEALER = "RoleHealer.tga", DAMAGER = "RoleDamage.tga" }
local ROLE_WORD = { TANK = TANK or "Tank", HEALER = HEALER or "Healer", DAMAGER = DAMAGER or "Damage" }
local TEXTURES = "Interface\\AddOns\\SuuUI\\Media\\Textures\\"

function M:RoleArt(b)
    local art = self.arts[b]
    if art then return art end
    art = CreateFrame("Frame", nil, self.stack)
    art:EnableMouse(false)
    local function circle(file, layer)
        local t = art:CreateTexture(nil, layer)
        t:SetTexture(TEXTURES .. file)
        t:SetAllPoints()
        return t
    end
    art.fill = circle("CircleFill.tga", "BACKGROUND")
    art.edge = circle("CircleBand.tga", "BORDER")
    art.glyph = art:CreateTexture(nil, "ARTWORK")
    art.glyph:SetSize(18, 18)
    art.glyph:SetPoint("CENTER")
    art.word = UI.Text(art, "caption", "ink-muted")
    art.word:SetPoint("TOP", art, "BOTTOM", 0, -S["space-2"])
    art.box = CreateFrame("Frame", nil, art)
    art.box:SetSize(14, 14)
    art.box:EnableMouse(false)
    art.boxFill = UI.Fill(art.box, "surface-sunk")
    art.boxFill:SetAllPoints()
    art.boxEdge = UI.Border(art.box, "gilt-line")
    art.tick = art.box:CreateTexture(nil, "OVERLAY")
    art.tick:SetTexture(TEXTURES .. "Glyphs\\check.tga")
    art.tick:SetSize(10, 10)
    art.tick:SetPoint("CENTER")
    art.tick:SetVertexColor(UI.RGBA("on-signal"))
    local cb = b.checkButton
    function art.draw()
        if not art:IsShown() then return end
        local on = cb and cb:GetChecked() and true or false
        art.edge:SetVertexColor(UI.RGBA(on and "arcane" or (art.hover and "gilt" or "gilt-line")))
        art.fill:SetVertexColor(UI.RGBA(on and "surface-raised" or "surface-sunk"))
        art.glyph:SetVertexColor(UI.RGBA(on and "ink" or "ink-faint"))
        art.word:SetColor(on and "ink" or "ink-muted")
        art.box:SetShown(cb and cb:IsShown() and true or false)
        art.boxFill:SetColorTexture(UI.RGBA(on and "arcane" or "surface-sunk"))
        art.boxEdge:SetColor(on and "arcane" or "gilt-line")
        art.tick:SetShown(on)
        art:SetAlpha(b:IsEnabled() and 1 or T.opacity["opacity-disabled"])
    end
    for _, m in ipairs({ "Enable", "Disable", "SetEnabled" }) do hooksecurefunc(b, m, art.draw) end
    if cb then
        for _, m in ipairs({ "SetChecked", "Show", "Hide" }) do hooksecurefunc(cb, m, art.draw) end
        cb:HookScript("OnClick", art.draw)
    end
    b:HookScript("OnEnter", function() art.hover = true; art.draw() end)
    b:HookScript("OnLeave", function() art.hover = false; art.draw() end)
    self.arts[b] = art
    return art
end

function M:HostRole(h, card, b, i)
    local cb = b.checkButton
    local s = self:Remember(h, b)
    for r in pairs(s.alphas) do r:SetAlpha(0) end
    b:SetFrameStrata(card:GetFrameStrata())
    b:SetFrameLevel(card:GetFrameLevel() + 10)
    b:SetSize(36, 36)
    b:ClearAllPoints()
    b:SetPoint("TOP", card.rolesRow, "TOPLEFT", 30 + (i - 1) * 60, 0)
    if cb then
        local cs = self:Remember(h, cb)
        for r in pairs(cs.alphas) do r:SetAlpha(0) end
        -- 14px on screen (the game draws it at 0.7)
        local scale = cb:GetScale() > 0 and cb:GetScale() or 1
        cb:SetSize(14 / scale, 14 / scale)
        cb:ClearAllPoints()
        cb:SetPoint("BOTTOMRIGHT", b, "BOTTOMRIGHT", 3 / scale, -3 / scale)
    end
    local art = self:RoleArt(b)
    art:SetFrameStrata(card:GetFrameStrata())
    art:SetFrameLevel(card:GetFrameLevel() + 9)
    art:ClearAllPoints()
    art:SetAllPoints(b)
    art.glyph:SetTexture(TEXTURES .. (ROLE_TEX[b.role] or "RoleDamage.tga"))
    art.word:SetValue(ROLE_WORD[b.role] or "")
    if cb then
        art.box:ClearAllPoints()
        art.box:SetPoint("BOTTOMRIGHT", art, "BOTTOMRIGHT", 3, -3)
    end
    art:Show()
    art.draw()
end

-- A Blizzard popup: its buttons, text, time left and edit box.
function M:Host(dialog, which)
    local kind = KINDS[which]
    if not kind then return end
    local info = StaticPopupDialogs and StaticPopupDialogs[which]
    self:HostFrame(dialog, which, kind, {
        buttons = function() return buttonsOf(dialog) end,
        text = function() return dialog.Text and dialog.Text:GetText() end,
        time = function()
            local timeout = info and info.timeout
            if plain(timeout) and type(timeout) == "number" and timeout > 0 and plain(dialog.timeleft) and dialog.timeleft then
                return timeout, dialog.timeleft
            end
        end,
        editBox = dialog.EditBox,
    })
end

-- Any Blizzard request window: `parts` says where its buttons ({ button,
-- index } in order), text, time (duration, remaining) and edit box are.
function M:HostFrame(dialog, which, kind, parts)
    if not self:Get("requests") then return end
    local h = self.hosts[dialog]
    if h and h.which ~= which then self:Undo(h) end
    if not h then
        h = { dialog = dialog, order = GetTime() }
        self.hosts[dialog] = h
        if not self.hookedHide[dialog] then
            self.hookedHide[dialog] = true
            dialog:HookScript("OnHide", function() self:Release(dialog) end)
        end
    end
    h.which, h.kind = which, kind
    h.buttons, h.text, h.time, h.editBox = parts.buttons, parts.text, parts.time or function() end, parts.editBox
    h.roles, h.warning = parts.roles, parts.warning
    h.id = "popup:" .. (dialog:GetName() or tostring(dialog))
    -- the popup itself out of sight (its parts come onto the card); kept on
    -- screen by its clamp otherwise
    if h.clamped == nil then h.clamped = dialog:IsClampedToScreen() and true or false end
    dialog:SetClampedToScreen(false)
    dialog:ClearAllPoints()
    dialog:SetPoint("BOTTOMRIGHT", UIParent, "TOPLEFT", -OFF_SCREEN, OFF_SCREEN)
    h.data = self:CardData(h)
    self:Rebuild()
end

function M:Release(dialog)
    local h = self.hosts[dialog]
    if not h then return end
    self:Undo(h)
    if h.clamped ~= nil then dialog:SetClampedToScreen(h.clamped) end
    self.hosts[dialog] = nil
    self:Rebuild()
end

-- Blizzard's request windows that aren't popups: the battleground's "enter"
-- (its answer is forbidden to addons: hosted like the popups) and the ready
-- check (hosted the same way, so it sits with the rest).
local function shownButtons(...)
    local out = {}
    for i = 1, select("#", ...) do
        local b = select(i, ...)
        if b and b:IsShown() then out[#out + 1] = { button = b, index = i } end
    end
    return out
end

-- The battleground waiting for you to enter.
local function battlefieldReady()
    if not (GetMaxBattlefieldID and GetBattlefieldStatus) then return nil end
    for i = 1, GetMaxBattlefieldID() do
        local status = GetBattlefieldStatus(i)
        if status == "confirm" then return i end
    end
end

local WINDOWS = {
    -- a group invite that asks for your role (the group finder's; not a
    -- shared popup): its role buttons come onto the card too
    {
        name = "LFGInvitePopup",
        kind = { category = "Party invite", glyph = "people", primary = 1 },
        parts = function(f)
            return {
                buttons = function() return shownButtons(_G.LFGInvitePopupAcceptButton, _G.LFGInvitePopupDeclineButton) end,
                text = function() return _G.LFGInvitePopupText and _G.LFGInvitePopupText:GetText() end,
                time = function()
                    local total, left = StaticPopupTimeoutSec, f.timeOut
                    if plain(total) and plain(left) and type(total) == "number" and type(left) == "number" and total > 0 then
                        return total, math.max(0, left)
                    end
                end,
                roles = function() return f.RoleButtons or {} end,
                warning = function()
                    local w = f.QueueWarningText
                    if w and w:IsShown() then return w:GetText() end
                end,
            }
        end,
    },
    {
        name = "PVPReadyDialog",
        kind = { category = "Battleground", glyph = "flag", primary = 1, title = "Your battleground is ready" },
        parts = function(f)
            local total -- the first reading: the whole time to enter
            return {
                buttons = function() return shownButtons(f.enterButton, f.leaveButton) end,
                text = function() return f.label and f.label:GetText() end,
                time = function()
                    local i = battlefieldReady()
                    local t = i and GetBattlefieldPortExpiration and GetBattlefieldPortExpiration(i)
                    if plain(t) and t and t > 0 then
                        -- seconds on some clients, milliseconds on others
                        local left = t > 1000 and t / 1000 or t
                        total = total or left
                        return total, left
                    end
                end,
            }
        end,
    },
    {
        name = "ReadyCheckFrame",
        kind = { category = "Ready check", glyph = "flag", primary = 1, title = "Are you ready?" },
        parts = function(f)
            local l = _G.ReadyCheckListenerFrame or f
            return {
                buttons = function() return shownButtons(l.YesButton, l.NoButton) end,
                text = function() return l.Text and l.Text:GetText() end,
                time = function()
                    if M.readyEndsAt then return M.readyDuration, math.max(0, M.readyEndsAt - GetTime()) end
                end,
            }
        end,
    },
}

function M:HookWindows()
    for _, w in ipairs(WINDOWS) do
        local f = _G[w.name]
        if f and not self.hookedHide[f] then
            self.hookedHide[f] = true
            f:HookScript("OnShow", function(frame)
                if self:IsEnabled() then self:HostFrame(frame, w.name, w.kind, w.parts(frame)) end
            end)
            f:HookScript("OnHide", function(frame) self:Release(frame) end)
            if f:IsShown() then self:HostFrame(f, w.name, w.kind, w.parts(f)) end
        end
    end
end

--------------------------------------------------------------------------------
-- The stack
--------------------------------------------------------------------------------

function M:Items()
    local items = {}
    local hosts = {}
    for _, h in pairs(self.hosts) do hosts[#hosts + 1] = h end
    table.sort(hosts, function(a, b) return a.order < b.order end)
    for _, h in ipairs(hosts) do items[#items + 1] = h.data end
    for _, id in ipairs(self.noteOrder) do items[#items + 1] = self.notes[id] end
    return items
end

function M:Rebuild()
    if not self.stack then return end
    self.stack:SetItems(self:Items(), InCombatLockdown())
    for _, h in pairs(self.hosts) do self:Attach(h) end
    self:SecureActions()
end

-- A note's action with `macro` (0.13): a secure button over its button
-- that runs the macro, for what only a secure click may do (opening the
-- game's Group Finder at its listing panel: opened from addon code, the
-- panel's listing would be refused). Placed by screen position, never
-- anchored to the card (a secure frame anchored to it would make the
-- stack protected); out of combat only: hidden as a fight starts, the
-- plain button then says why it can't.
function M:SecureActions()
    if InCombatLockdown() or not self.stack then return end
    self.secure = self.secure or {}
    local used = {}
    local ui = UIParent:GetEffectiveScale()
    for id, d in pairs(self.notes) do
        for i, a in ipairs(d.actions or {}) do
            local card = a.macro and self.stack:CardFor(id)
            local pool = card and card.buttons and card.buttons[a.variant or "quiet"]
            local b = pool and pool[i]
            if b and b:IsVisible() and b:GetLeft() then
                local key = id .. "#" .. i
                local s = self.secure[key]
                if not s then
                    s = CreateFrame("Button", nil, UIParent, "SecureActionButtonTemplate")
                    s:RegisterForClicks("LeftButtonDown", "LeftButtonUp")
                    s:SetFrameStrata("DIALOG")
                    s:SetScript("OnEnter", function(self) local fn = self.button and self.button:GetScript("OnEnter"); if fn then fn(self.button) end end)
                    s:SetScript("OnLeave", function(self) local fn = self.button and self.button:GetScript("OnLeave"); if fn then fn(self.button) end end)
                    s:SetScript("PostClick", function(self) if self.after then self.after() end end)
                    self.secure[key] = s
                end
                local scale = b:GetEffectiveScale() / ui
                s:ClearAllPoints()
                s:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", b:GetLeft() * scale, b:GetBottom() * scale)
                s:SetSize(b:GetWidth() * scale, b:GetHeight() * scale)
                s:SetAttribute("type1", "macro")
                s:SetAttribute("macrotext1", type(a.macro) == "function" and a.macro() or a.macro)
                s.button, s.after = b, a.onClick and function() a.onClick(card) end or nil
                s:Show()
                used[key] = true
            end
        end
    end
    for key, s in pairs(self.secure) do
        if not used[key] then s:Hide(); s:ClearAllPoints(); s.button, s.after = nil, nil end
    end
end

function M:HideSecureActions()
    for _, s in pairs(self.secure or {}) do s:Hide(); s:ClearAllPoints(); s.button, s.after = nil, nil end
end

-- A few times a second: counting titles (logging out in 12 s), time left,
-- timed notes going, hosted parts kept on their cards (Blizzard lays its
-- popups out again now and then), popups anchored to a hosted one put back
-- on screen.
function M:Tick()
    -- notes hide while an open window covers them (requests stay)
    if self.stack and SuuUI.UI.IsCoveredByWindow then
        self.stack:SetNotesHidden(SuuUI.UI.IsCoveredByWindow(self.stack))
    end
    local now = GetTime()
    local changed = false
    for id, d in pairs(self.notes) do
        if d.kind ~= "timed" and d.endsAt then
            d.remaining = math.max(0, d.endsAt - now)
            local card = self.stack:CardFor(id)
            if card then card:SetRemaining(d.remaining) end
        elseif d.kind == "timed" and d.endsAt then
            d.remaining = d.endsAt - now
            if d.remaining <= 0 then
                self.notes[id] = nil
                for i, x in ipairs(self.noteOrder) do if x == id then table.remove(self.noteOrder, i) break end end
                changed = true
            else
                local card = self.stack:CardFor(id)
                if card then card:SetRemaining(d.remaining) end
            end
        end
    end
    if changed then self:Rebuild() else self:SecureActions() end
    for dialog, h in pairs(self.hosts) do
        local card = h.card
        if card then
            local text = h.text()
            if plain(text) and text and text ~= h.data.title then
                h.data.title = text
                card:SetTitle(text)
            end
            if h.data.duration then
                local _, remaining = h.time()
                if remaining then card:SetRemaining(remaining) end
            end
            local point, rel = dialog:GetPoint(1)
            if point ~= "BOTTOMRIGHT" or rel ~= UIParent then
                dialog:ClearAllPoints()
                dialog:SetPoint("BOTTOMRIGHT", UIParent, "TOPLEFT", -OFF_SCREEN, OFF_SCREEN)
            end
            local list = h.buttons()
            local first = list[#list] and list[#list].button
            if first then
                local _, brel = first:GetPoint(1)
                if brel ~= card.actionsRow then self:Attach(h) end
            end
            -- disabled until typed (delete): Blizzard's own rule, shown dim
            for _, x in ipairs(list) do
                local art = self.arts[x.button]
                if art then art:SetAlpha(x.button:IsEnabled() and 1 or T.opacity["opacity-disabled"]) end
            end
        end
    end
    -- a popup Blizzard anchored under a hosted one would be off screen too
    for i = 1, 4 do
        local d = _G["StaticPopup" .. i]
        if d and d:IsShown() and not self.hosts[d] then
            local _, rel = d:GetPoint(1)
            if rel and self.hosts[rel] then
                d:ClearAllPoints()
                d:SetPoint("TOP", UIParent, "TOP", 0, -135)
            end
        end
    end
end

--------------------------------------------------------------------------------
-- Settings
--------------------------------------------------------------------------------

local PREVIEW = {
    { id = "p1", kind = "action", category = "Party invite", title = "Ysolde invites you to a group.", icon = { glyph = "people" },
      duration = 60, remaining = 42, actions = { { label = "Accept", variant = "primary" }, { label = "Decline" } } },
    { id = "p2", kind = "action", tone = "danger", category = "Delete item", title = "Do you want to destroy Ember Pelt?",
      icon = { glyph = "trash" }, item = { icon = 134075, label = "Ember Pelt", quality = "uncommon" }, confirmText = "DELETE",
      actions = { { label = "Yes", variant = "danger" }, { label = "No" } } },
    { id = "p3", kind = "until", category = "Durability", title = "Your gear is badly damaged", icon = { glyph = "anvil" },
      tone = "warning", ["until"] = "Goes when you repair" },
    { id = "p4", kind = "timed", presence = { online = true, source = "Battle.net", people = {
        { name = "Kaelith", tag = "#1137", color = "class-priest", detail = "Kaelith · Eastern Plaguelands",
          icon = { texture = "Interface\\Glues\\CharacterCreate\\UI-CharacterCreate-Classes",
                   coords = CLASS_ICON_TCOORDS and CLASS_ICON_TCOORDS.PRIEST } } }, invite = function() end },
      duration = 6, remaining = 4 },
    { id = "p5", kind = "timed", presence = { online = false, source = "Guild", people = { { name = "Ysolde" } } },
      duration = 4, remaining = 3 },
}

function M:PreviewView(parent)
    if not self.preview then
        self.preview = UI.NotificationStack(parent, { max = 5 })
        self.preview:SetItems(PREVIEW, false)
    end
    self.preview:SetParent(parent)
    return self.preview
end

local SECTION = {
    id = "notifications", label = "Notifications", category = "General", order = 30,
    preview = function(parent) return M:PreviewView(parent) end,
    groups = {
        { title = "Notifications", description = "Requests and notes at the top left, under the micro menu: requests first, then what waits on something, then notes. In combat only requests and conditions show. Move them in edit mode.", rows = {
            { key = "requests", label = "Blizzard's popups as cards", control = "toggle",
              description = "Invites, resurrection, summons, duels, trades, release spirit, deleting items, logging out, battleground entry: Blizzard's own buttons on SuuUI's cards, so every answer is still Blizzard's. Off: Blizzard's popups as they are." },
            { key = "max", label = "Shown at once", control = "slider", min = 3, max = 8, step = 1,
              description = "The rest wait behind \"+N more\"." },
        } },
        { title = "Notes", rows = {
            { key = "durability", label = "Damaged gear", control = "toggle",
              description = "Amber while a piece is at 20% or less, ember once one breaks; goes when you repair." },
            { key = "bagsFull", label = "Full bags", control = "toggle",
              description = "While your bags have no free slot; goes when one frees up." },
            { key = "talentPoints", label = "Talent points to spend", control = "toggle",
              description = "While you have talent points left, with a button that opens your talents; goes when you spend them." },
            { key = "legacyPoints", label = "Legacy points to spend", control = "toggle",
              description = "While this character has Legacy points left, with a button that opens the Legacy window; goes when you spend them." },
        } },
        { title = "Friends and guild", description = "A card when someone comes online or goes offline: who, what they're playing or where they are; click it to whisper them. Several at once share one card; in combat they wait. /suu presence shows one of each.", rows = {
            { key = "presenceBnetOnline", label = "Battle.net friends online", control = "toggle" },
            { key = "presenceBnetOffline", label = "Battle.net friends offline", control = "toggle" },
            { key = "presenceFriendOnline", label = "Friends online", control = "toggle" },
            { key = "presenceFriendOffline", label = "Friends offline", control = "toggle" },
            { key = "presenceGuildOnline", label = "Guild members online", control = "toggle" },
            { key = "presenceGuildOffline", label = "Guild members offline", control = "toggle" },
            { key = "presenceHideChat", label = "Hide the game's online and offline lines in chat", control = "toggle",
              description = "The \"has come online\" and \"has gone offline\" lines, and Battle.net's own popup for them while SuuUI shows Battle.net friends." },
        } },
    },
}

--------------------------------------------------------------------------------
-- Lifecycle
--------------------------------------------------------------------------------

function M:OnEnable()
    self.notes = self.notes or {}
    self.noteOrder = self.noteOrder or {}
    self.hosts = self.hosts or {}
    self.hookedHide = self.hookedHide or {}
    self.arts = self.arts or {}
    if not self.frame then
        self.frame = CreateFrame("Frame", "SuuUINotifications", SuuUI.Root)
        -- under open windows (HIGH): notes; requests raise themselves
        self.frame:SetFrameStrata("MEDIUM")
        self.frame:SetSize(T.size["notice-w"], 200)
        self.stack = UI.NotificationStack(self.frame, { max = self:Get("max") })
        self.stack:SetPoint("TOPLEFT")
        self.stack.onExpand = function() self:Rebuild() end
        self.stack.onClearAll = function() self:DismissAll() end
        local wait = 0
        self.frame:SetScript("OnUpdate", function(_, elapsed)
            wait = wait - elapsed
            if wait > 0 then return end
            wait = 0.1
            self:Tick()
        end)
    end
    self:RegisterMover(self.frame, { key = "position", label = "Notifications" })
    self:RegisterSettings(SECTION)
    self:Watch("max", function(v) self.stack.max = v; self:Rebuild() end)
    self:Watch("requests", function(on)
        if not on then for dialog in pairs(self.hosts) do self:Release(dialog) end end
    end)
    if StaticPopup_Show and not self.hooked then
        self.hooked = true
        hooksecurefunc("StaticPopup_Show", function(which, _, _, data)
            if not self:IsEnabled() then return end
            local dialog = StaticPopup_FindVisible and StaticPopup_FindVisible(which, data)
            if dialog then self:Host(dialog, which) end
        end)
    end
    self:HookWindows()
    -- request windows whose addon loads later
    self:OnGameEvent("ADDON_LOADED", function() self:HookWindows() end)
    -- notes about the game
    local valid = C_EventUtils and C_EventUtils.IsEventValid
    for _, e in ipairs({ "UPDATE_INVENTORY_DURABILITY", "PLAYER_ENTERING_WORLD" }) do
        if not valid or valid(e) then self:OnGameEvent(e, function() self:CheckDurability() end) end
    end
    for _, e in ipairs({ "BAG_UPDATE_DELAYED", "PLAYER_ENTERING_WORLD" }) do
        if not valid or valid(e) then self:OnGameEvent(e, function() self:CheckBags() end) end
    end
    self:Watch("durability", function() self:CheckDurability() end)
    self:Watch("bagsFull", function() self:CheckBags() end)
    for _, e in ipairs({ "TRAIT_CONFIG_UPDATED", "TRAIT_TREE_CURRENCY_INFO_UPDATED", "PLAYER_TALENT_UPDATE",
                         "CHARACTER_POINTS_CHANGED", "PLAYER_LEVEL_UP", "PLAYER_ENTERING_WORLD" }) do
        if not valid or valid(e) then
            -- a moment later: the points read right only after the change has landed
            self:OnGameEvent(e, function() C_Timer.After(0.2, function() if self:IsEnabled() then self:CheckTalents(); self:CheckLegacy() end end) end)
        end
    end
    if not valid or valid("MAJOR_FACTION_RENOWN_LEVEL_CHANGED") then
        self:OnGameEvent("MAJOR_FACTION_RENOWN_LEVEL_CHANGED", function() C_Timer.After(0.2, function() if self:IsEnabled() then self:CheckLegacy() end end) end)
    end
    self:Watch("talentPoints", function() self:CheckTalents() end)
    self:Watch("legacyPoints", function() self:CheckLegacy() end)
    -- the ready check's time
    self:OnGameEvent("READY_CHECK", function(_, _, timeLeft)
        if plain(timeLeft) and type(timeLeft) == "number" and timeLeft > 0 then
            self.readyDuration, self.readyEndsAt = timeLeft, GetTime() + timeLeft
        end
    end)
    self:OnGameEvent("READY_CHECK_FINISHED", function() self.readyEndsAt = nil end)
    -- in combat notes wait; out of it they come back
    self:OnGameEvent("PLAYER_REGEN_DISABLED", function() self:HideSecureActions(); self:Rebuild() end)
    self:OnGameEvent("PLAYER_REGEN_ENABLED", function()
        self:Rebuild()
        -- online/offline held in the fight
        for key, q in pairs(self.presence or {}) do if q.held then self:FlushPresence(key) end end
    end)
    -- friends and guild members coming and going (handlers take the event
    -- first, then its values: these read one value too far, the companion
    -- app flag and the sender, and no note ever came; found with /suu probe
    -- social)
    self:HookPresence()
    self:OnGameEvent("CHAT_MSG_SYSTEM", function(_, msg) self:SystemLine(msg) end)
    if not valid or valid("BN_FRIEND_ACCOUNT_ONLINE") then
        self:OnGameEvent("BN_FRIEND_ACCOUNT_ONLINE", function(_, id)
            if plain(id) and id then self:Presence("bnet", true, self:BnetPerson(id)) end
        end)
        self:OnGameEvent("BN_FRIEND_ACCOUNT_OFFLINE", function(_, id)
            if plain(id) and id then self:Presence("bnet", false, self:BnetPerson(id)) end
        end)
    end
    -- the roster asked for now and then, so a guild member's line finds them
    if IsInGuild() and C_GuildInfo and C_GuildInfo.GuildRoster then pcall(C_GuildInfo.GuildRoster) end
    self:RegisterCommand("presence", "test: shows a card for each kind of friend coming online and going offline", function()
        self:TestPresence()
    end)
    self:RegisterCommand("notify", "test: shows one notification of each kind", function()
        self:Notify({ kind = "timed", category = "Test", title = "A timed note", body = "It goes by itself after 8 seconds.", icon = { glyph = "bell" } })
        self:Notify({ kind = "sticky", category = "Test", title = "A sticky note", body = "It stays until you close it.", icon = { glyph = "mail" } })
        self:Notify({ kind = "until", category = "Test", title = "A condition", ["until"] = "Goes when the test ends", icon = { glyph = "hourglass" }, tone = "warning" })
    end)
end

function M:OnDisable()
    for dialog in pairs(self.hosts or {}) do self:Release(dialog) end
    if self.frame then self.frame:Hide() end
end
