-- Units/Social.lua
-- SuuUI's Social pages (step 3.4, design component SocialWindow) over
-- Forever's own social window (SocialUIFrame, O: not the classic
-- FriendsFrame, which it no longer shows; found with /suu probe social
-- mouse, 2026-10-14), the way the Legacy and Professions pages sit over
-- theirs: the key, the micro menu and Esc stay Blizzard's, the window is in
-- SuuUI's look (the windows module), and Blizzard's own friends list and
-- Battle.net bar are off screen (still shown: they drive it). The window:
-- the Battle.net bar, the friends list (search, filter, Add New Friend),
-- Recent Allies, Friend Requests, Raid, four tabs down its right side;
-- the ignored in a small window of its own. None of it protected.
--   Contacts  Battle.net and character friends, online first, with their
--             notes; Whisper, Invite, Add friend; the ignored; your status
-- A built-in module written against the public API only.

local UI, T = SuuUI.UI, SuuUI.Tokens

local M = SuuUI.RegisterModule({
    id = "social",
    name = "Social",
    description = "SuuUI's Social window: your Battle.net and character friends, the ignored, your status.",
    api = "0.13",
    reloadToToggle = true,
    defaults = {},
})

local isSecret = issecretvalue or function() return false end
local function plain(v) return v ~= nil and not isSecret(v) end

local function call(fn, ...)
    if type(fn) ~= "function" then return nil end
    local ok, a, b, c, d, e, f, g, h = pcall(fn, ...)
    if ok then return a, b, c, d, e, f, g, h end
end


local CLASS_FILES = {}
for _, list in ipairs({ LOCALIZED_CLASS_NAMES_MALE or {}, LOCALIZED_CLASS_NAMES_FEMALE or {} }) do
    for file, name in pairs(list) do CLASS_FILES[name] = file end
end
local function classColor(className)
    local file = CLASS_FILES[className or ""]
    return file and T.color["class-" .. file:lower()] and ("class-" .. file:lower()) or nil
end

local GAMES = { App = "the Battle.net app", BSAp = "Battle.net mobile", WTCG = "Hearthstone", Hero = "Heroes of the Storm",
                Pro = "Overwatch", S2 = "StarCraft II", S1 = "StarCraft", D3 = "Diablo III", Fen = "Diablo IV",
                ANBS = "Diablo Immortal", VIPR = "Call of Duty", W3 = "Warcraft III", GRY = "Warcraft Rumble" }

-- "3 days ago" from a time() stamp.
local function ago(stamp)
    if not plain(stamp) or not stamp or stamp == 0 then return nil end
    local s = math.max(0, time() - stamp)
    if s < 3600 then return "less than an hour ago" end
    if s < 86400 then local h = math.floor(s / 3600); return h .. (h == 1 and " hour ago" or " hours ago") end
    local d = math.floor(s / 86400)
    if d < 30 then return d .. (d == 1 and " day ago" or " days ago") end
    local m = math.floor(d / 30)
    return m .. (m == 1 and " month ago" or " months ago")
end

--------------------------------------------------------------------------------
-- The game's data
--------------------------------------------------------------------------------

function M:Friends()
    local out, online = {}, 0
    -- Battle.net friends (their account name is protected text the game
    -- draws; never read)
    for i = 1, (call(BNGetNumFriends)) or 0 do
        local info = C_BattleNet and C_BattleNet.GetFriendAccountInfo and call(C_BattleNet.GetFriendAccountInfo, i)
        if info then
            local game = info.gameAccountInfo or {}
            local isOnline = game.isOnline and true or false
            local row = { key = "bn:" .. tostring(info.bnetAccountID), bnet = true, bnetID = info.bnetAccountID,
                          name = info.accountName or info.battleTag or "?", sort = (plain(info.battleTag) and info.battleTag or ""):lower(),
                          online = isOnline, note = plain(info.note) and info.note ~= "" and info.note or nil,
                          away = info.isAFK or game.isGameAFK, busy = info.isDND or game.isGameBusy, whisper = isOnline }
            if isOnline and game.clientProgram == (BNET_CLIENT_WOW or "WoW") and plain(game.characterName) and game.characterName then
                row.character = game.characterName
                row.color = classColor(game.className)
                local where = {}
                if game.characterLevel and game.characterLevel > 0 then where[#where + 1] = "Level " .. game.characterLevel end
                if plain(game.className) and game.className then where[#where + 1] = game.className end
                local zone = plain(game.areaName) and game.areaName or nil
                local detail = table.concat(where, " ")
                row.detail = zone and zone ~= "" and (detail .. " · " .. zone) or detail
                if game.wowProjectID == WOW_PROJECT_ID and game.gameAccountID then
                    -- by their game account, as the game's friends list does
                    -- (by name and realm the game didn't find them: the realm
                    -- is the server's own name; found in game); on your side.
                    -- No realm check: Forever's realms are rulesets, and a
                    -- realm ID that differs still groups (asked 2026-10-18:
                    -- "the realm doesn't match" for a friend you could invite)
                    if not (plain(game.factionName) and game.factionName == UnitFactionGroup("player")) then
                        row.why = "They're in the other faction."
                    else
                        row.invite, row.gameAccountID = true, game.gameAccountID
                    end
                else
                    row.why = "They're playing another version of World of Warcraft."
                    row.detail = "Playing World of Warcraft"
                end
            elseif isOnline then
                row.detail = "Playing " .. (GAMES[game.clientProgram or ""] or "on Battle.net")
                row.why = "They aren't in World of Warcraft Forever."
            else
                local when = ago(info.lastOnlineTime)
                row.detail = when and ("Last online " .. when) or "Offline"
                row.why = "They're offline."
            end
            if isOnline then online = online + 1 end
            out[#out + 1] = row
        end
    end
    -- character friends
    local fl = C_FriendList
    for i = 1, (fl and call(fl.GetNumFriends)) or 0 do
        local f = call(fl.GetFriendInfoByIndex, i)
        if f and plain(f.name) and f.name then
            local isOnline = f.connected and true or false
            local row = { key = "c:" .. f.name, name = f.name, sort = f.name:lower(), online = isOnline,
                          color = classColor(f.className), note = plain(f.notes) and f.notes ~= "" and f.notes or nil,
                          away = f.afk, busy = f.dnd, whisper = isOnline, invite = isOnline, inviteName = f.name }
            if isOnline then
                local detail = (f.level and f.level > 0 and ("Level " .. f.level .. " ") or "") .. (f.className or "")
                row.detail = (plain(f.area) and f.area and f.area ~= "") and (detail .. " · " .. f.area) or detail
                online = online + 1
            else
                row.detail = "Offline"
                row.why = "They're offline."
            end
            out[#out + 1] = row
        end
    end
    table.sort(out, function(a, b)
        if a.online ~= b.online then return a.online end
        return a.sort < b.sort
    end)
    return out, online
end

function M:Ignored()
    local out = {}
    local fl = C_FriendList
    for i = 1, (fl and call(fl.GetNumIgnores)) or 0 do
        local name = call(fl.GetIgnoreName, i)
        if plain(name) and name then out[#out + 1] = name end
    end
    return out
end

function M:BattleTag()
    local _, tag = call(BNGetInfo)
    return plain(tag) and tag or nil
end

function M:Status()
    local _, _, _, _, afk, dnd = call(BNGetInfo)
    if dnd then return "busy" elseif afk then return "away" end
    return "available"
end

--------------------------------------------------------------------------------
-- The page
--------------------------------------------------------------------------------

function M:Render()
    local view = self.view
    if not (view and view:IsVisible()) then return end
    local friends, online = self:Friends()
    self.friends = friends
    view:SetData({ view = self.mode or "friends", status = self:Status(), me = self:BattleTag(), online = online, total = #friends,
                   friends = friends, ignored = self:Ignored(), selected = self.selected })
end

function M:QueueRender()
    if self.renderQueued then return end
    self.renderQueued = true
    C_Timer.After(0.1, function()
        self.renderQueued = nil
        if self:IsEnabled() then self:Render() end
    end)
end

local function whisper(row)
    if row.bnet then
        local tell = (ChatFrameUtil and ChatFrameUtil.SendBNetTell) or ChatFrame_SendBNetTell
        if tell and row.name then tell(row.name) end
    else
        local tell = (ChatFrameUtil and ChatFrameUtil.SendTell) or ChatFrame_SendTell
        if tell then tell(row.name) end
    end
end

local function invite(row)
    if row.gameAccountID then
        local fn = (C_BattleNet and C_BattleNet.InviteFriend) or BNInviteFriend
        if fn then pcall(fn, row.gameAccountID) end
        return
    end
    local fn = (C_PartyInfo and C_PartyInfo.InviteUnit) or InviteUnit
    if fn and row.inviteName then pcall(fn, row.inviteName) end
end

function M:SetNote(row)
    UI.Confirm({ title = "Note", text = "A note about this friend: only you see it.",
        input = { label = "Note", value = row.note or "" }, confirm = "Save",
        onConfirm = function(text)
            if row.bnet then
                local set = BNSetFriendNote or (C_BattleNet and C_BattleNet.SetFriendNote)
                if set then pcall(set, row.bnetID, text) end
            else
                pcall(C_FriendList.SetFriendNotes, row.name, text)
            end
            self:QueueRender()
        end })
end

function M:Remove(row)
    UI.Confirm({ title = "Remove friend?", text = "They leave your friends list. You can add them again any time.",
        confirm = "Remove", onConfirm = function()
            if row.bnet then
                local remove = BNRemoveFriend or (C_BattleNet and C_BattleNet.RemoveFriend)
                if remove then pcall(remove, row.bnetID) end
            else
                pcall(C_FriendList.RemoveFriend, row.name)
            end
            self.selected = nil
            self:QueueRender()
        end })
end

function M:Wire(view)
    view.onView = function(v) self.mode = v; self:Render() end
    view.onSelect = function(key) self.selected = key; self:Render() end
    view.onWhisper = whisper
    view.onInvite = invite
    view.onStatus = function(v)
        local bn = C_BattleNet
        local afk = (bn and bn.SetAFK) or BNSetAFK
        local dnd = (bn and bn.SetDND) or BNSetDND
        if afk then pcall(afk, v == "away") end
        if dnd then pcall(dnd, v == "busy") end
        C_Timer.After(0.3, function() self:QueueRender() end)
    end
    view.onAdd = function()
        UI.Confirm({ title = "Add a friend", text = "Their character's whole name (first and last), or their BattleTag such as Kaelith#1234.",
            input = { label = "Name or BattleTag", placeholder = "Name or BattleTag" }, confirm = "Add",
            onConfirm = function(text)
                if text:find("#") then
                    local send = BNSendFriendInvite or (C_BattleNet and C_BattleNet.SendFriendInvite)
                    if send then pcall(send, text) else self:Print("Battle.net friend requests aren't available here.") end
                else
                    self:AddFriend(text)
                end
                self:QueueRender()
            end })
    end
    view.onIgnore = function()
        UI.Confirm({ title = "Ignore a player", text = "You won't see their messages, invites or trades.",
            input = { label = "Their whole name", placeholder = "Name" }, confirm = "Ignore",
            onConfirm = function(text) pcall(C_FriendList.AddIgnore, text); self:QueueRender() end })
    end
    view.onUnignore = function(name) pcall(C_FriendList.DelIgnore, name); self:QueueRender() end
    view.onMenu = function(row, owner)
        UI.ContextMenuFrom(owner, function(_, root)
            root:CreateTitle(row.character or row.name)
            if row.whisper then root:CreateButton("Whisper", function() whisper(row) end) end
            if row.invite then root:CreateButton("Invite", function() invite(row) end) end
            root:CreateButton("Set note", function() self:SetNote(row) end)
            root:CreateDivider()
            if not row.bnet then root:CreateButton("Ignore", function() self:Ignore(row.name) end) end
            root:CreateButton("Remove friend", function() self:Remove(row) end)
        end, "friend", { row = row })
    end
end

--------------------------------------------------------------------------------
-- Recent allies and friend requests (probed 2026-10-14: C_RecentAllies'
-- characterData, stateData, interactionData; pins and notes; Battle.net
-- invites through BNGetFriendInviteInfo)
--------------------------------------------------------------------------------

local function classFileOf(classID)
    if not classID then return nil end
    local info = C_CreatureInfo and C_CreatureInfo.GetClassInfo and C_CreatureInfo.GetClassInfo(classID)
    if info and info.classFile then return info.classFile end
    local _, file = GetClassInfo and GetClassInfo(classID)
    return file
end

-- How you met them: the first interaction's own words, when it has any.
local function metBy(a)
    local list = a.interactionData and a.interactionData.interactions
    local first = list and list[1]
    if type(first) ~= "table" then return nil end
    for _, key in ipairs({ "description", "text", "contextName", "name" }) do
        local v = first[key]
        if plain(v) and type(v) == "string" and v ~= "" then return v end
    end
end

-- Pinned: what was just chosen until the game's own data agrees (it comes
-- back a moment later: a pin seemed to need two clicks, found in game).
function M:Pinned(guid)
    if not guid then return false end
    local ra = C_RecentAllies
    local actual = (ra and call(ra.IsRecentAllyPinned, guid)) and true or false
    local wanted = self.pinWanted and self.pinWanted[guid]
    if wanted == nil then return actual end
    if wanted == actual then self.pinWanted[guid] = nil end
    return wanted
end

function M:Allies()
    local ra = C_RecentAllies
    local out = {}
    for _, a in ipairs((ra and call(ra.GetRecentAllies)) or {}) do
        local cd, sd = a.characterData or {}, a.stateData or {}
        local name = plain(cd.fullName) and cd.fullName or cd.name
        if name then
            local file = classFileOf(cd.classID)
            local online = sd.isOnline and true or false
            local detail = {}
            if cd.level and cd.level > 0 then detail[#detail + 1] = "Level " .. cd.level end
            detail[#detail + 1] = online and (plain(sd.currentLocation) and sd.currentLocation or "Online") or "Offline"
            local met = metBy(a)
            if met then detail[#detail + 1] = met end
            local guid = cd.guid
            local row = { key = guid or name, guid = guid, name = name, online = online,
                          color = file and T.color["class-" .. file:lower()] and ("class-" .. file:lower()) or nil,
                          detail = table.concat(detail, " · "),
                          note = a.interactionData and plain(a.interactionData.note) and a.interactionData.note ~= "" and a.interactionData.note or nil,
                          pinned = self:Pinned(guid),
                          friend = guid and C_FriendList.IsFriend and call(C_FriendList.IsFriend, guid) or false,
                          sent = sd.friendRequestSentThisSession }
            local actions = {}
            if online then actions[#actions + 1] = { label = "Whisper", onClick = function(r) self:Whisper(r.name) end } end
            if not row.friend then
                actions[#actions + 1] = { label = row.sent and "Requested" or "Add friend", disabled = row.sent,
                    onClick = function(r) self:AddFriend(r.name); C_Timer.After(0.5, function() self:RenderLists() end) end }
            end
            row.actions = actions
            out[#out + 1] = row
        end
    end
    table.sort(out, function(a, b)
        if (a.pinned and true or false) ~= (b.pinned and true or false) then return a.pinned and true or false end
        if a.online ~= b.online then return a.online end
        return a.name < b.name
    end)
    return out
end

function M:Requests()
    local out = {}
    for i = 1, (call(BNGetNumFriendInvites)) or 0 do
        local id, accountName, _, _, sent = call(BNGetFriendInviteInfo, i)
        if id then
            local when = ago(sent)
            out[#out + 1] = { key = "inv:" .. tostring(id), glyph = true, online = true, name = accountName or "?",
                detail = when and ("Sent " .. when) or "Wants to be your Battle.net friend",
                actions = {
                    { label = "Decline", onClick = function() if BNDeclineFriendInvite then pcall(BNDeclineFriendInvite, id) end; self:QueueRender() end },
                    { label = "Accept", variant = "primary", onClick = function() if BNAcceptFriendInvite then pcall(BNAcceptFriendInvite, id) end; self:QueueRender() end },
                } }
        end
    end
    return out
end

-- A friend request by a character's whole name. Forever's classic friends
-- list is off (IsLegacyFriendSystemEnabled false: C_FriendList.AddFriend did
-- nothing, found in game); its own window sends a title friend invite
-- (C_BattleNet.SendTitleFriendInviteByName, watched with /suu probe social
-- friends, 2026-10-14).
function M:AddFriend(name)
    if SuuUI.AddFriend(name) then self:Print("Friend request sent to " .. name .. ".") end
end

-- Ignore a player by their whole name (a confirmation first).
function M:Ignore(name)
    if not name or name == "" then return end
    UI.Confirm({ title = "Ignore " .. name .. "?", text = "You won't see their messages, invites or trades. Unignore them on the Ignored list.",
        confirm = "Ignore", onConfirm = function()
            pcall(C_FriendList.AddIgnore, name)
            C_Timer.After(0.3, function() self:QueueRender() end)
        end })
end

function M:Whisper(name)
    local tell = (ChatFrameUtil and ChatFrameUtil.SendTell) or ChatFrame_SendTell
    if tell and name then tell(name) end
end

function M:RenderLists()
    if self.alliesPage and self.alliesPage:IsVisible() then
        self.alliesPage:SetData({ title = "Recent allies", rows = self:Allies(),
            empty = "No one yet: the people you group with show up here." })
    end
    if self.requestsPage and self.requestsPage:IsVisible() then
        self.requestsPage:SetData({ title = "Friend requests", rows = self:Requests(), empty = "No friend requests." })
    end
end

function M:AllyMenu(row, owner)
    local ra = C_RecentAllies
    UI.ContextMenuFrom(owner, function(_, root)
        root:CreateTitle(row.name)
        if row.online then
            root:CreateButton("Whisper", function() self:Whisper(row.name) end)
            root:CreateButton("Invite", function()
                local fn = (C_PartyInfo and C_PartyInfo.InviteUnit) or InviteUnit
                if fn then pcall(fn, row.name) end
            end)
        end
        if row.guid and ra and ra.SetRecentAllyPinned then
            root:CreateButton(row.pinned and "Unpin" or "Pin", function()
                local want = not row.pinned
                pcall(ra.SetRecentAllyPinned, row.guid, want)
                self.pinWanted = self.pinWanted or {}
                self.pinWanted[row.guid] = want
                self:RenderLists()
                -- and again once the game has it
                C_Timer.After(1, function() self:RenderLists() end)
            end)
        end
        root:CreateButton("Ignore", function() self:Ignore(row.name) end)
        if row.guid and ra and ra.SetRecentAllyNote and (not ra.CanSetRecentAllyNote or call(ra.CanSetRecentAllyNote)) then
            root:CreateButton("Set note", function()
                UI.Confirm({ title = "Note", text = "A note about this ally: only you see it.",
                    input = { label = "Note", value = row.note or "" }, confirm = "Save",
                    onConfirm = function(text)
                        pcall(ra.SetRecentAllyNote, row.guid, text)
                        C_Timer.After(0.2, function() self:RenderLists() end)
                    end })
            end)
        end
    end, "recentAlly", { row = row })
end

--------------------------------------------------------------------------------
-- The Raid page
--------------------------------------------------------------------------------

local TEST_NAMES = { { "Kaelith Dawnmere", "PRIEST", "HEALER" }, { "Brannoc Ironvale", "WARRIOR", "TANK" },
    { "Lyra Sunwhisper", "MAGE", "DAMAGER" }, { "Thorn Blackmoor", "ROGUE", "DAMAGER" }, { "Maelis Brightforge", "PALADIN", "HEALER" },
    { "Durn Stonehoof", "HUNTER", "DAMAGER" }, { "Ysolde Thornvale", "DRUID", "DAMAGER" }, { "Ardent Stormcall", "SHAMAN", "HEALER" },
    { "Vesh Nightfall", "WARLOCK", "DAMAGER" }, { "Corwin Hale", "WARRIOR", "DAMAGER" }, { "Sable Ashgrove", "MAGE", "DAMAGER" },
    { "Mira Quell", "PRIEST", "HEALER" }, { "Torvald Grim", "WARRIOR", "TANK" }, { "Elric Vane", "ROGUE", "DAMAGER" },
    { "Nessa Brook", "HUNTER", "DAMAGER" }, { "Ulric Moss", "DRUID", "HEALER" } }

function M:TestRaid()
    if self.raidTest then self.raidTest = nil; self:RenderRaid(); return end
    local members = { { index = 1, name = SuuUI.FullName("player"), class = select(2, UnitClass("player")), role = "DAMAGER",
                        group = 1, leader = true, online = true, you = true } }
    for i, t in ipairs(TEST_NAMES) do
        members[#members + 1] = { index = i + 1, name = t[1], class = t[2], role = t[3], group = math.floor(i / 5) + 1,
                                  assistant = i == 3, online = i ~= 9, level = 60 }
    end
    self.raidTest = members
    self:Print("Raid test: 17 made-up members; drag them between groups. /suu raidtest again to end it.")
    self:RenderRaid()
end

-- Raid Info: your lockouts in a SuuUI panel beside the window (Blizzard's
-- own box wasn't in SuuUI's look, found in game): each saved instance, its
-- difficulty, how far you got and when it resets.
function M:Lockouts()
    local out = {}
    for i = 1, (call(GetNumSavedInstances)) or 0 do
        local name, _, reset, _, locked, extended, _, isRaid, maxPlayers, difficultyName, numEncounters, progress = call(GetSavedInstanceInfo, i)
        if plain(name) and name and (locked or extended) then
            out[#out + 1] = { name = name, difficulty = difficultyName, reset = reset, extended = extended,
                              raid = isRaid, size = maxPlayers, bosses = numEncounters, done = progress }
        end
    end
    return out
end

function M:DrawLockouts()
    local p = self.lockoutPanel
    if not (p and p:IsShown()) then return end
    local list = self:Lockouts()
    p.rows = p.rows or {}
    local y = 0
    for i, l in ipairs(list) do
        local r = p.rows[i]
        if not r then
            r = CreateFrame("Frame", nil, p.body)
            r.name = UI.Text(r, "label", "ink")
            r.name:SetPoint("TOPLEFT")
            r.progress = UI.Text(r, "numeric", "ink")
            r.progress:SetPoint("TOPRIGHT")
            r.detail = UI.Text(r, "caption", "ink-muted")
            r.detail:SetPoint("TOPLEFT", r.name, "BOTTOMLEFT", 0, -2)
            p.rows[i] = r
        end
        -- set each time: a theme can change the text styles
        r:SetHeight(T.type.label.lineHeight + T.type.caption.lineHeight + 2)
        r:ClearAllPoints()
        r:SetPoint("TOPLEFT", p.body, "TOPLEFT", 0, -y)
        r:SetPoint("RIGHT", p.body, "RIGHT")
        r.name:SetValue(l.name)
        r.progress:SetValue((l.bosses and l.bosses > 0) and (l.done .. " / " .. l.bosses) or "")
        local detail = {}
        if plain(l.difficulty) and l.difficulty and l.difficulty ~= "" then detail[#detail + 1] = l.difficulty end
        if l.reset and l.reset > 0 then detail[#detail + 1] = "resets in " .. (SecondsToTime and SecondsToTime(l.reset, true) or (math.ceil(l.reset / 3600) .. " h")) end
        if l.extended then detail[#detail + 1] = "extended" end
        r.detail:SetValue(table.concat(detail, " · "))
        r:Show()
        y = y + r:GetHeight() + T.space["space-4"]
    end
    for i = #list + 1, #p.rows do p.rows[i]:Hide() end
    p.empty:SetShown(#list == 0)
    p.body:SetHeight(math.max(T.type.body.lineHeight, y))
    p:Fit()
end

function M:ToggleLockouts()
    local f = self.frame
    if not f then return end
    local p = self.lockoutPanel
    if not p then
        p = UI.Panel(f, { title = "Raid lockouts", width = 300, closable = true, solid = true })
        p:SetFrameLevel(f:GetFrameLevel() + 200)
        p.empty = UI.Text(p.body, "body", "ink-muted")
        p.empty:SetPoint("TOPLEFT")
        p.empty:SetValue("No active lockouts.")
        p:Hide()
        self.lockoutPanel = p
    end
    p:ClearAllPoints()
    -- beside the window, past its tabs down the right side
    p:SetPoint("TOPLEFT", f, "TOPRIGHT", 72, 0)
    p:SetShown(not p:IsShown())
    if p:IsShown() then
        if RequestRaidInfo then RequestRaidInfo() end
        self:DrawLockouts()
    end
end

function M:RaidMembers()
    if self.raidTest then return self.raidTest end
    local out = {}
    if not IsInRaid() then return out end
    for i = 1, GetNumGroupMembers() do
        local name, rank, group, level, className, file, zone, online, dead, _, _, combatRole = GetRaidRosterInfo(i)
        if plain(name) and name then
            local unit = "raid" .. i
            local role = (plain(combatRole) and combatRole ~= "NONE" and combatRole) or UnitGroupRolesAssigned(unit)
            out[#out + 1] = { index = i, unit = unit, name = name, class = file, className = className, level = level, zone = zone,
                              role = role ~= "NONE" and role or nil, group = group, leader = rank == 2, assistant = rank == 1,
                              online = online and true or false, dead = dead, you = UI.Flag(UnitIsUnit(unit, "player")) }
        end
    end
    return out
end

function M:RenderRaid()
    local page = self.raidPage
    if not (page and page:IsVisible()) then return end
    local test = self.raidTest ~= nil
    local canLead = test or UnitIsGroupLeader("player") or UnitIsGroupAssistant("player")
    page:SetData({ inRaid = test or IsInRaid(), inParty = IsInGroup() and not IsInRaid(), canLead = canLead and true or false,
                   reason = InCombatLockdown() and "Not in combat." or nil, size = 40, members = self:RaidMembers() })
end

function M:WireRaid(page)
    page.onReadyCheck = function() if DoReadyCheck then DoReadyCheck() end end
    page.onRoleCheck = function() if InitiateRolePoll then pcall(InitiateRolePoll) end end
    page.onRaidInfo = function() self:ToggleLockouts() end
    page.onConvert = function()
        local convert = (C_PartyInfo and C_PartyInfo.ConvertToRaid) or ConvertToRaid
        if convert then pcall(convert) end
    end
    page.onMove = function(index, group)
        if self.raidTest then
            for _, m in ipairs(self.raidTest) do if m.index == index then m.group = group end end
            return self:RenderRaid()
        end
        if InCombatLockdown() then return end
        pcall(SetRaidSubgroup, index, group)
    end
    page.onSwap = function(a, b)
        if self.raidTest then
            local ma, mb
            for _, m in ipairs(self.raidTest) do
                if m.index == a then ma = m elseif m.index == b then mb = m end
            end
            if ma and mb then ma.group, mb.group = mb.group, ma.group end
            return self:RenderRaid()
        end
        if InCombatLockdown() then return end
        pcall(SwapRaidSubgroup, a, b)
    end
    page.onMember = function(m, button, owner)
        if button ~= "RightButton" then return end
        local lead = UnitIsGroupLeader("player")
        UI.ContextMenuFrom(owner, function(_, root)
            root:CreateTitle(m.name)
            if not m.you then
                root:CreateButton("Whisper", function()
                    local tell = (ChatFrameUtil and ChatFrameUtil.SendTell) or ChatFrame_SendTell
                    if tell then tell(m.name) end
                end)
                root:CreateButton("Ignore", function() self:Ignore(m.name) end)
            end
            if lead and not m.you and m.unit then
                root:CreateDivider()
                if m.assistant then
                    root:CreateButton("Demote from assistant", function() pcall(DemoteAssistant, m.unit) end)
                else
                    root:CreateButton("Promote to assistant", function() pcall(PromoteToAssistant, m.unit) end)
                end
                root:CreateButton("Make leader", function() pcall(PromoteToLeader, m.unit) end)
                root:CreateButton("Remove from group", function()
                    local remove = (C_PartyInfo and C_PartyInfo.UninviteUnit) or UninviteUnit
                    if remove then pcall(remove, m.unit) end
                end)
            end
        end, "groupMember", { member = m })
    end
end

--------------------------------------------------------------------------------
-- Over Blizzard's window
--------------------------------------------------------------------------------

-- A Blizzard part out of sight: see-through and off screen, still shown,
-- and back off screen whenever Blizzard places it again.
function M:Away(part)
    if not part or self.awayParts[part] then return end
    self.awayParts[part] = true
    part:SetAlpha(0)
    local placing = false
    local function away()
        placing = true
        part:ClearAllPoints()
        part:SetPoint("TOPLEFT", UIParent, "TOPRIGHT", 5000, 0)
        placing = false
    end
    away()
    hooksecurefunc(part, "SetPoint", function() if not placing then C_Timer.After(0, away) end end)
end



-- The window's friends list: the content frame with a filter bar that is
-- neither Recent Allies nor Friend Requests.
local function friendsList(f)
    for _, c in ipairs({ f:GetChildren() }) do
        if c.FilterBar and c ~= f.RecentAlliesList and c ~= f.FriendRequestsList then return c end
    end
end

-- The Contacts page while the window shows its friends list.
function M:Follow()
    local f = self.frame
    if not (f and self.view) then return end
    -- a probe asked SuuUI's pages to step aside (the game's own in use)
    if SuuUI.ProbeShowsBlizzardSocial and SuuUI.ProbeShowsBlizzardSocial() then
        for _, page in ipairs({ self.view, self.raidPage, self.alliesPage, self.requestsPage }) do if page then page:Hide() end end
        for _, part in ipairs({ self.friendsList, f.RaidFrame, f.RecentAlliesList, f.FriendRequestsList, f.BattleNetBar }) do
            if part then part:SetAlpha(1) end
        end
        if self.friendsList then self.friendsList:ClearAllPoints(); self.friendsList:SetAllPoints(f.RecentAlliesList or f) end
        return
    end
    local list = self.friendsList
    local onContacts = f:IsShown() and list and list:IsShown()
    self.view:SetShown(onContacts and true or false)
    -- the Raid page over Blizzard's (see-through, in place: Raid Info hangs
    -- off it)
    local raid = f.RaidFrame
    local onRaid = f:IsShown() and raid and raid:IsShown()
    -- Recent allies and Requests over Blizzard's lists (see-through, in place)
    local onAllies = f:IsShown() and f.RecentAlliesList and f.RecentAlliesList:IsShown()
    local onRequests = f:IsShown() and f.FriendRequestsList and f.FriendRequestsList:IsShown()
    if self.alliesPage then
        self.alliesPage:SetShown(onAllies and true or false)
        f.RecentAlliesList:SetAlpha(onAllies and 0 or 1)
    end
    if self.requestsPage then
        self.requestsPage:SetShown(onRequests and true or false)
        f.FriendRequestsList:SetAlpha(onRequests and 0 or 1)
    end
    if onAllies or onRequests then self:RenderLists() end
    -- the Battle.net bar see-through under SuuUI's pages (it sat over the
    -- Raid page's head, found in game), and the pages above its buttons
    local bar = f.BattleNetBar
    if bar then
        local ours = onContacts or onRaid or onAllies or onRequests
        bar:SetAlpha(ours and 0 or 1)
        local level = math.max(f:GetFrameLevel() + 100, bar:GetFrameLevel() + 30)
        for _, page in ipairs({ self.view, self.raidPage, self.alliesPage, self.requestsPage }) do
            if page then page:SetFrameLevel(level) end
        end
    end
    if self.raidPage then
        self.raidPage:SetShown(onRaid and true or false)
        if raid then raid:SetAlpha(onRaid and 0 or 1) end
        if onRaid then self:RenderRaid() end
    end
    if onContacts then
        if C_FriendList and C_FriendList.ShowFriends then pcall(C_FriendList.ShowFriends) end
        self:QueueRender()
    end
end

function M:Build()
    local f = _G.SocialUIFrame
    if not f or self.view then return end
    local list = friendsList(f)
    if not list then return end
    self.frame, self.friendsList = f, list
    self.awayParts = {}
    local view = UI.Contacts(f)
    -- 18px higher than the other pages: your name's row sat far under the
    -- header's divider (asked for in game)
    view:SetPoint("TOPLEFT", f, "TOPLEFT", 20, -26)
    view:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -20, 16)
    view:SetFrameLevel(f:GetFrameLevel() + 100)
    view:EnableMouse(true)
    view:Hide()
    self.view = view
    self:Wire(view)
    -- Recent allies and Requests
    local function listPage()
        local page = UI.PeopleList(f)
        page:SetPoint("TOPLEFT", f, "TOPLEFT", 20, -44)
        page:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -20, 16)
        page:EnableMouse(true)
        page:Hide()
        return page
    end
    if f.RecentAlliesList then
        self.alliesPage = listPage()
        self.alliesPage.onMenu = function(row, owner) self:AllyMenu(row, owner) end
    end
    if f.FriendRequestsList then self.requestsPage = listPage() end
    -- the Raid page
    if f.RaidFrame then
        local page = UI.RaidGroups(f)
        page:SetPoint("TOPLEFT", f, "TOPLEFT", 20, -44)
        page:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -20, 16)
        page:SetFrameLevel(f:GetFrameLevel() + 100)
        page:EnableMouse(true)
        page:Hide()
        self.raidPage = page
        self:WireRaid(page)
    end
    -- Blizzard's friends list out of sight (the page has its own); the
    -- Battle.net bar stays where it is (the other tabs hang under it: moved
    -- away, they went with it, found in game), only see-through while the
    -- page covers it. Recent Allies, Friend Requests and Raid stay
    -- Blizzard's for now.
    self:Away(list)
    -- the page follows the window's content
    f:HookScript("OnShow", function() self:Follow() end)
    f:HookScript("OnHide", function() GameTooltip:Hide() end)
    for _, c in ipairs({ list, f.RecentAlliesList, f.FriendRequestsList, f.RaidFrame }) do
        if c then
            c:HookScript("OnShow", function() self:Follow() end)
            c:HookScript("OnHide", function() self:Follow() end)
        end
    end
    self:Follow()
end

function M:OnEnable()
    self:Build()
    -- the window may load on demand
    self:OnGameEvent("ADDON_LOADED", function() self:Build() end)
    local valid = C_EventUtils and C_EventUtils.IsEventValid
    for _, e in ipairs({ "FRIENDLIST_UPDATE", "BN_FRIEND_INFO_CHANGED", "BN_FRIEND_ACCOUNT_ONLINE",
                         "BN_FRIEND_ACCOUNT_OFFLINE", "BN_FRIEND_LIST_SIZE_CHANGED", "IGNORELIST_UPDATE",
                         "BN_INFO_CHANGED", "PLAYER_FLAGS_CHANGED", "BN_CONNECTED", "BN_DISCONNECTED" }) do
        if not valid or valid(e) then
            self:OnGameEvent(e, function() if self.view and self.view:IsVisible() then self:QueueRender() end end)
        end
    end
    -- requests and allies
    for _, e in ipairs({ "BN_FRIEND_INVITE_ADDED", "BN_FRIEND_INVITE_REMOVED", "BN_FRIEND_INVITE_LIST_INITIALIZED",
                         "FRIENDLIST_UPDATE" }) do
        if not valid or valid(e) then self:OnGameEvent(e, function() self:RenderLists() end) end
    end
    -- the raid's changes
    for _, e in ipairs({ "GROUP_ROSTER_UPDATE", "PARTY_LEADER_CHANGED", "PLAYER_ROLES_ASSIGNED", "UNIT_CONNECTION",
                         "PLAYER_REGEN_DISABLED", "PLAYER_REGEN_ENABLED" }) do
        if not valid or valid(e) then
            self:OnGameEvent(e, function()
                if self.raidPage and self.raidPage:IsVisible() then C_Timer.After(0.1, function() self:RenderRaid() end) end
            end)
        end
    end
    -- the lockouts as they come in
    if not valid or valid("UPDATE_INSTANCE_INFO") then
        self:OnGameEvent("UPDATE_INSTANCE_INFO", function() self:DrawLockouts() end)
    end
    -- their rows' heights come from the text styles
    self:On("SUUUI_THEME_CHANGED", function() self:DrawLockouts() end)
    self:RegisterCommand("raidtest", "test: the Raid page with 17 made-up members to drag around", function() self:TestRaid() end)
end
