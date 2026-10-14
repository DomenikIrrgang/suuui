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
                if game.wowProjectID == WOW_PROJECT_ID and game.realmName and game.realmName ~= "" then
                    row.invite, row.inviteName = true, game.characterName .. "-" .. game.realmName
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
    view:SetData({ view = self.mode or "friends", status = self:Status(), online = online, total = #friends,
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
                    pcall(C_FriendList.AddFriend, text)
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
            root:CreateButton("Remove friend", function() self:Remove(row) end)
        end)
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
    local list = self.friendsList
    local onContacts = f:IsShown() and list and list:IsShown()
    self.view:SetShown(onContacts and true or false)
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
    view:SetPoint("TOPLEFT", f, "TOPLEFT", 20, -44)
    view:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -20, 16)
    view:SetFrameLevel(f:GetFrameLevel() + 100)
    view:EnableMouse(true)
    view:Hide()
    self.view = view
    self:Wire(view)
    -- Blizzard's friends list and Battle.net bar out of sight (the page has
    -- both); Recent Allies, Friend Requests and Raid stay Blizzard's for now
    self:Away(list)
    self:Away(f.BattleNetBar)
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
end
