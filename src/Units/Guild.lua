-- Units/Guild.lua
-- SuuUI's Guild pages (step 3.4, design component GuildWindow) over
-- Blizzard's Communities window (J; probed 2026-10-14: its communities list
-- on the left, Chat, Roster, Info and play-style tabs, the member list, the
-- chat; none of it protected), the way the Social pages sit over theirs:
-- the window is in SuuUI's look (the windows module), Blizzard's own part
-- for a page see-through in place under it (it drives it).
--   Roster  search, Show offline, sortable columns, the selected member's
--           Whisper, Invite, Promote, Demote, Remove as your rank allows,
--           Invite to guild; notes in a right click
-- Only for your guild: a community keeps Blizzard's own pages.
-- A built-in module written against the public API only.

local UI, T = SuuUI.UI, SuuUI.Tokens

local M = SuuUI.RegisterModule({
    id = "guild",
    name = "Guild",
    description = "SuuUI's Guild window: the roster with what your rank allows.",
    api = "0.13",
    reloadToToggle = true,
    defaults = { showOffline = false },
})

local isSecret = issecretvalue or function() return false end
local function plain(v) return v ~= nil and not isSecret(v) end

local function call(fn, ...)
    if type(fn) ~= "function" then return nil end
    local ok, a, b, c, d, e, f, g, h, i, j, k, l, m, n, o, p, q = pcall(fn, ...)
    if ok then return a, b, c, d, e, f, g, h, i, j, k, l, m, n, o, p, q end
end

local function lastOnline(i)
    local y, mo, d, h = call(GetGuildRosterLastOnline, i)
    if not (y or mo or d or h) then return "Offline" end
    y, mo, d, h = y or 0, mo or 0, d or 0, h or 0
    if y > 0 then return y .. (y == 1 and " year ago" or " years ago") end
    if mo > 0 then return mo .. (mo == 1 and " month ago" or " months ago") end
    if d > 0 then return d .. (d == 1 and " day ago" or " days ago") end
    if h > 0 then return h .. (h == 1 and " hour ago" or " hours ago") end
    return "less than an hour ago"
end

--------------------------------------------------------------------------------
-- The game's data
--------------------------------------------------------------------------------

function M:MyRank()
    local _, _, rankIndex = call(GetGuildInfo, "player")
    return rankIndex or 0
end

function M:Members()
    local all, online = {}, 0
    if not IsInGuild() then return all, 0, 0 end
    local me = SuuUI.FullName("player")
    for i = 1, (call(GetNumGuildMembers)) or 0 do
        local name, rank, rankIndex, level, _, zone, note, officerNote, isOnline, status, file = call(GetGuildRosterInfo, i)
        local guid = select(17, call(GetGuildRosterInfo, i))
        if plain(name) and name then
            local short = Ambiguate(name, "guild")
            local m = { key = name, full = name, name = short, rank = rank, rankIndex = rankIndex or 0, level = level,
                        zone = plain(zone) and zone or nil, note = plain(note) and note or nil,
                        officerNote = plain(officerNote) and officerNote or nil, online = isOnline and true or false,
                        away = status == 1, busy = status == 2, class = file, guid = guid,
                        you = Ambiguate(name, "short") == Ambiguate(me, "short") }
            if not m.online then m.lastOnline = lastOnline(i) end
            if m.online then online = online + 1 end
            all[#all + 1] = m
        end
    end
    return all, online, #all
end

local SORTS = {
    rank = function(a, b) if a.rankIndex ~= b.rankIndex then return a.rankIndex < b.rankIndex end return a.name < b.name end,
    name = function(a, b) return a.name < b.name end,
    level = function(a, b) if (a.level or 0) ~= (b.level or 0) then return (a.level or 0) > (b.level or 0) end return a.name < b.name end,
    zone = function(a, b)
        local x, y = a.online and (a.zone or "") or "~", b.online and (b.zone or "") or "~"
        if x ~= y then return x < y end
        return a.name < b.name
    end,
    note = function(a, b)
        local x, y = a.note or "~", b.note or "~"
        if x ~= y then return x < y end
        return a.name < b.name
    end,
}

-- What you may do with a member: { enabled, why } each.
function M:Actions(m)
    local out = {}
    local inviteGuild = call(CanGuildInvite)
    out.guildInvite = { enabled = inviteGuild, why = "Your rank can't invite to the guild." }
    if not m then return out end
    local mine = self:MyRank()
    local below = m.rankIndex > mine
    local lowest = (call(GuildControlGetNumRanks) or 1) - 1
    out.whisper = { enabled = m.online and not m.you, why = m.you and "That's you." or "They're offline." }
    local canGroup = not IsInGroup() or UnitIsGroupLeader("player") or UnitIsGroupAssistant("player")
    out.invite = { enabled = m.online and not m.you and canGroup,
                   why = m.you and "That's you." or (not m.online and "They're offline.") or "Only your group's leader or an assistant can invite." }
    local function rule(can, extra, whyRank, whyExtra)
        if not can then return { enabled = false, why = whyRank } end
        if m.you then return { enabled = false, why = "That's you." } end
        if not below then return { enabled = false, why = "Only for members ranked below you." } end
        if extra == false then return { enabled = false, why = whyExtra } end
        return { enabled = true }
    end
    out.promote = rule(call(CanGuildPromote), m.rankIndex - 1 > mine, "Your rank can't promote.", "They'd reach your own rank.")
    out.demote = rule(call(CanGuildDemote), m.rankIndex < lowest, "Your rank can't demote.", "They're at the lowest rank already.")
    out.remove = rule(call(CanGuildRemove), true, "Your rank can't remove members.")
    return out
end

--------------------------------------------------------------------------------
-- The page
--------------------------------------------------------------------------------

function M:Render()
    local page = self.roster
    if not (page and page:IsVisible()) then return end
    local all, online, total = self:Members()
    local showOffline = self:Get("showOffline")
    local search = self.search and self.search ~= "" and self.search:lower() or nil
    local shown, selected = {}, nil
    for _, m in ipairs(all) do
        local keep = (showOffline or m.online)
        if keep and search then
            local hay = (m.name .. " " .. (m.zone or "") .. " " .. (m.rank or "") .. " " .. (m.note or "")):lower()
            keep = hay:find(search, 1, true) ~= nil
        end
        if keep then shown[#shown + 1] = m end
        if m.key == self.selected then selected = m end
    end
    table.sort(shown, SORTS[self.sort or "rank"] or SORTS.rank)
    self.members = all
    page:SetData({ online = online, total = total, showOffline = showOffline, sort = self.sort or "rank",
                   members = shown, selected = self.selected, actions = self:Actions(selected) })
end

function M:QueueRender()
    if self.renderQueued then return end
    self.renderQueued = true
    C_Timer.After(0.15, function()
        self.renderQueued = nil
        if self:IsEnabled() then self:Render() end
    end)
end

function M:Note(m, officer)
    UI.Confirm({ title = officer and "Officer note" or "Note",
        text = officer and ("Only officers who may read officer notes see this one on " .. m.name .. ".")
            or ("Everyone in the guild sees " .. m.name .. "'s note."),
        input = { label = officer and "Officer note" or "Note", value = (officer and m.officerNote or m.note) or "" }, confirm = "Save",
        onConfirm = function(text)
            if C_GuildInfo and C_GuildInfo.SetNote and m.guid then
                pcall(C_GuildInfo.SetNote, m.guid, text, not officer)
            end
            self:QueueRender()
        end })
end

function M:Act(action, m)
    if action == "guildInvite" then
        UI.Confirm({ title = "Invite to the guild", text = "Their character's whole name.",
            input = { label = "Name", placeholder = "Name" }, confirm = "Invite",
            onConfirm = function(text) pcall(C_GuildInfo.Invite, text) end })
        return
    end
    if not m then return end
    if action == "whisper" then
        local tell = (ChatFrameUtil and ChatFrameUtil.SendTell) or ChatFrame_SendTell
        if tell then tell(m.full) end
    elseif action == "invite" then
        local fn = (C_PartyInfo and C_PartyInfo.InviteUnit) or InviteUnit
        if fn then pcall(fn, m.full) end
    elseif action == "promote" then
        pcall(C_GuildInfo.Promote, m.full)
    elseif action == "demote" then
        pcall(C_GuildInfo.Demote, m.full)
    elseif action == "remove" then
        UI.Confirm({ title = "Remove " .. m.name .. "?", text = "They leave the guild. They can be invited again.",
            confirm = "Remove", onConfirm = function() pcall(C_GuildInfo.Uninvite, m.full) end })
    end
    C_Timer.After(0.5, function() if C_GuildInfo.GuildRoster then pcall(C_GuildInfo.GuildRoster) end end)
end

function M:Menu(m, owner)
    local a = self:Actions(m)
    UI.ContextMenuFrom(owner, function(_, root)
        root:CreateTitle(m.name)
        if a.whisper.enabled then root:CreateButton("Whisper", function() self:Act("whisper", m) end) end
        if a.invite.enabled then root:CreateButton("Invite", function() self:Act("invite", m) end) end
        if call(CanEditPublicNote) or m.you then root:CreateButton("Set note", function() self:Note(m, false) end) end
        if C_GuildInfo and call(C_GuildInfo.CanEditOfficerNote) then
            root:CreateButton("Set officer note", function() self:Note(m, true) end)
        end
        if a.promote.enabled or a.demote.enabled or a.remove.enabled then
            root:CreateDivider()
            if a.promote.enabled then root:CreateButton("Promote", function() self:Act("promote", m) end) end
            if a.demote.enabled then root:CreateButton("Demote", function() self:Act("demote", m) end) end
            if a.remove.enabled then root:CreateButton("Remove from guild", function() self:Act("remove", m) end) end
        end
    end)
end

function M:Wire(page)
    page.onSearch = function(text) self.search = text; self:QueueRender() end
    page.onShowOffline = function(on) self:Set("showOffline", on and true or false); self:Render() end
    page.onSort = function(key) self.sort = key; self:Render() end
    page.onSelect = function(key) self.selected = key; self:Render() end
    page.onAction = function(action, m) self:Act(action, m) end
    page.onMenu = function(m, owner) self:Menu(m, owner) end
end

--------------------------------------------------------------------------------
-- Over Blizzard's window
--------------------------------------------------------------------------------

-- The roster page while the window shows your guild's roster.
function M:Follow()
    local f = self.frame
    if not (f and self.roster) then return end
    local modes = COMMUNITIES_FRAME_DISPLAY_MODES or {}
    local mode = f.GetDisplayMode and f:GetDisplayMode()
    local club = f.GetSelectedClubId and f:GetSelectedClubId()
    local guild = C_Club and C_Club.GetGuildClubId and C_Club.GetGuildClubId()
    local onRoster = f:IsShown() and guild and club == guild and mode ~= nil and mode == modes.ROSTER
    self.roster:SetShown(onRoster and true or false)
    if f.MemberList then f.MemberList:SetAlpha(onRoster and 0 or 1) end
    if f.GuildMemberListDropdown then f.GuildMemberListDropdown:SetAlpha(onRoster and 0 or 1) end
    if onRoster then
        if C_GuildInfo and C_GuildInfo.GuildRoster then pcall(C_GuildInfo.GuildRoster) end
        self:Render()
    end
end

function M:Build()
    local f = _G.CommunitiesFrame
    if not f or self.roster then return end
    self.frame = f
    local page = UI.GuildRoster(f)
    local left = f.CommunitiesList
    if left then
        page:SetPoint("TOPLEFT", left, "TOPRIGHT", 12, 0)
    else
        page:SetPoint("TOPLEFT", f, "TOPLEFT", 20, -44)
    end
    page:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -20, 16)
    page:SetFrameLevel(f:GetFrameLevel() + 100)
    page:EnableMouse(true)
    page:Hide()
    self.roster = page
    self:Wire(page)
    f:HookScript("OnShow", function() self:Follow() end)
    f:HookScript("OnHide", function() GameTooltip:Hide() end)
    if f.SetDisplayMode then hooksecurefunc(f, "SetDisplayMode", function() self:Follow() end) end
    if f.SelectClub then hooksecurefunc(f, "SelectClub", function() C_Timer.After(0, function() self:Follow() end) end) end
    self:Follow()
end

function M:OnEnable()
    self:Build()
    self:OnGameEvent("ADDON_LOADED", function() self:Build() end)
    local valid = C_EventUtils and C_EventUtils.IsEventValid
    for _, e in ipairs({ "GUILD_ROSTER_UPDATE", "PLAYER_GUILD_UPDATE", "GUILD_RANKS_UPDATE", "GROUP_ROSTER_UPDATE" }) do
        if not valid or valid(e) then
            self:OnGameEvent(e, function() if self.roster and self.roster:IsVisible() then self:QueueRender() end end)
        end
    end
end
