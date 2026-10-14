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
    out.settings = { enabled = call(IsGuildLeader), why = "Only the Guild Master can change the guild's settings." }
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

local SLASH = { promote = "/gpromote ", demote = "/gdemote ", remove = "/gremove " }

-- A secure button over one of the panel's buttons (on UIParent: a secure
-- child would make the guild window protected).
local function secureOver(button)
    local s = CreateFrame("Button", nil, UIParent, "SecureActionButtonTemplate")
    s:RegisterForClicks("LeftButtonDown", "LeftButtonUp")
    s.target = button
    s:SetScript("OnEnter", function() local fn = button:GetScript("OnEnter"); if fn then fn(button) end end)
    s:SetScript("OnLeave", function() local fn = button:GetScript("OnLeave"); if fn then fn(button) end end)
    s:Hide()
    return s
end

-- The roster foot's Promote, Demote and Remove: secure buttons on top that
-- run the slash command for the selected member (out of combat).
function M:FootOverlays(m, actions)
    local page = self.roster
    if not page then return end
    self.overs = self.overs or {}
    local combat = InCombatLockdown()
    for key in pairs(SLASH) do
        local btn = page.buttons[key]
        local over = self.overs[key]
        if not over and btn and not combat then
            over = secureOver(btn)
            over:HookScript("PostClick", function()
                if InCombatLockdown() then return end
                if key == "remove" and not over.armed then
                    -- the first click arms it
                    over.armed = true
                    btn:SetLabel("Click again")
                    over:SetAttribute("type1", "macro")
                    return
                end
                over.armed = nil
                if key == "remove" then btn:SetLabel("Remove"); over:SetAttribute("type1", nil) end
                C_Timer.After(0.5, function() if C_GuildInfo.GuildRoster then pcall(C_GuildInfo.GuildRoster) end end)
            end)
            self.overs[key] = over
        end
        if over and not combat then
            local on = m and actions[key] and actions[key].enabled and page:IsVisible()
            if over.member ~= m then
                over.armed = nil
                if key == "remove" then btn:SetLabel("Remove") end
            end
            over.member = m
            over:SetAttribute("type1", (on and key ~= "remove" or (on and over.armed)) and "macro" or nil)
            over:SetAttribute("macrotext1", m and (SLASH[key] .. m.full) or "")
            -- a layer over the window's own (HIGH): a window comes to the
            -- front when clicked and covered it, so the click reached the
            -- plain button under it (found in game)
            over:SetFrameStrata("DIALOG")
            -- anchored only while shown: a secure button anchored to the
            -- roster made the whole guild window protected (it couldn't
            -- open in combat then)
            over:ClearAllPoints()
            if on then over:SetAllPoints(btn) end
            over:SetShown(on and true or false)
        end
    end
end

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
    local actions = self:Actions(selected)
    page:SetData({ online = online, total = total, showOffline = showOffline, sort = self.sort or "rank",
                   members = shown, selected = self.selected, actions = actions })
    self:FootOverlays(selected, actions)
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

-- Guild settings: Blizzard's own guild control window (ranks and what each
-- may do) hosted on the Settings tab (asked for in game: the settings in a
-- tab of their own, for those who may change them). SuuUI can't change
-- them itself (GuildControlSetRank, SetMOTD and SetInfoText are forbidden
-- to addons: /suu probe social guildcontrol), but your clicks inside
-- Blizzard's window are yours and save (found in game). UI.GuildControl
-- lays its controls out in SuuUI's look (design component GuildControl).
function M:GuildSettings() self:ShowOwn("settings") end

function M:HostSettings(on)
    local f = self.frame
    if not f then return end
    if on and not _G.GuildControlUI and C_AddOns and C_AddOns.LoadAddOn then pcall(C_AddOns.LoadAddOn, "Blizzard_GuildControlUI") end
    local ui = _G.GuildControlUI
    -- a cover over Blizzard's own page underneath
    if not self.settingsCover then
        local cover = CreateFrame("Frame", nil, f)
        cover:SetPoint("TOPLEFT", f, "TOPLEFT", 20, -44)
        cover:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -20, 16)
        cover:SetFrameLevel(f:GetFrameLevel() + 150)
        cover:EnableMouse(true)
        -- solid: the chat underneath never shows through
        UI.Fill(cover, "surface"):SetAllPoints()
        cover.suuOwn = true
        cover:Hide()
        self.settingsCover = cover
    end
    self.settingsCover:SetShown(on and true or false)
    if not ui then return end
    if on then
        ui:SetFrameLevel(self.settingsCover:GetFrameLevel() + 5)
        if not self.hostedSettings then
            self.hostedSettings = UI.GuildControl(self.settingsCover, ui)
        end
        ui:Show()
        self.hostedSettings:Layout()
    elseif self.hostedSettings and ui:IsShown() then
        ui:Hide()
    end
end

function M:Act(action, m)
    if action == "settings" then self:GuildSettings() return end
    if action == "guildInvite" then
        UI.Confirm({ title = "Invite to the guild", text = "Their character's whole name.",
            input = { label = "Name", placeholder = "Name" }, confirm = "Invite",
            onConfirm = function(text) pcall(C_GuildInfo.Invite, text) end })
        return
    end
    if not m then return end
    if SLASH[action] then
        -- the click reached the plain button, not the secure one on top
        self:Print(("%s: the secure button wasn't under the mouse (%s)."):format(action,
            InCombatLockdown() and "in combat" or (self.overs and self.overs[action] and (self.overs[action]:IsShown() and "shown" or "hidden") or "not made")))
        return
    end
    if action == "whisper" then
        local tell = (ChatFrameUtil and ChatFrameUtil.SendTell) or ChatFrame_SendTell
        if tell then tell(m.full) end
    elseif action == "invite" then
        local fn = (C_PartyInfo and C_PartyInfo.InviteUnit) or InviteUnit
        if fn then pcall(fn, m.full) end
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
    end)
end

function M:Wire(page)
    page.onSearch = function(text) self.search = text; self:QueueRender() end
    page.onShowOffline = function(on) self:Set("showOffline", on and true or false); self:Render() end
    page.onSort = function(key) self.sort = key; self:Render() end
    page.onSelect = function(key)
        self.selected = key
        self:Render()
        -- a click opens their details, as Blizzard's roster did
        for _, m in ipairs(self.members or {}) do if m.key == key then self:ShowDetails(m) end end
    end
    page.onAction = function(action, m) self:Act(action, m) end
    page.onMenu = function(m, owner) self:Menu(m, owner) end
end

--------------------------------------------------------------------------------
-- A member's details: a SuuUI panel beside the window (Blizzard's roster
-- opens one on a click; SuuUI's did nothing, found in game): who, where,
-- the notes with Edit, Whisper and Invite. Promote, Demote and Remove stay
-- on the roster's foot (asked for in game), where they're secure: they're
-- forbidden to addon code, so secure buttons on top of them run the game's
-- own slash commands (/gpromote, /gdemote, /gremove) on your click; Remove
-- asks for a second click.
--------------------------------------------------------------------------------

function M:BuildDetails()
    if self.details then return self.details end
    local f = self.frame
    local S = T.space
    local p = UI.Panel(f, { title = " ", width = 320, closable = true, solid = true })
    p.suuOwn = true
    p:SetFrameLevel(f:GetFrameLevel() + 200)
    p:SetPoint("TOPLEFT", f, "TOPRIGHT", 12, 0)
    local b = p.body
    p.line1 = UI.Text(b, "label", "ink")
    p.line1:SetPoint("TOPLEFT")
    p.line2 = UI.Text(b, "caption", "ink-muted")
    p.line2:SetPoint("TOPLEFT", p.line1, "BOTTOMLEFT", 0, -2)
    local function noteBlock(label, below, officer)
        local head = UI.Text(b, "caption", "gilt-text")
        head:SetPoint("TOPLEFT", below, "BOTTOMLEFT", 0, -S["space-5"])
        head:SetValue(label)
        local edit = UI.Button(b, { text = "Edit", variant = "quiet", onClick = function()
            if p.member then self:Note(p.member, officer) end
        end })
        edit:SetPoint("RIGHT", b, "RIGHT", 0, 0)
        edit:SetPoint("TOP", head, "TOP", 0, 4)
        local text = UI.Text(b, "body", "ink")
        text:SetPoint("TOPLEFT", head, "BOTTOMLEFT", 0, -S["space-3"])
        text:SetPoint("RIGHT", b, "RIGHT")
        text:SetJustifyH("LEFT")
        text:SetWordWrap(true)
        return head, edit, text
    end
    p.noteHead, p.noteEdit, p.note = noteBlock("Note", p.line2, false)
    p.officerHead, p.officerEdit, p.officer = noteBlock("Officer note", p.note, true)
    -- the actions: Whisper, Invite; Promote, Demote, Remove (secure)
    p.row1 = CreateFrame("Frame", nil, b)
    p.row1:SetHeight(26)
    p.whisper = UI.Button(p.row1, { text = "Whisper", variant = "quiet", onClick = function() if p.member then self:Act("whisper", p.member) end end })
    p.whisper:SetPoint("LEFT")
    p.invite = UI.Button(p.row1, { text = "Invite", variant = "quiet", onClick = function() if p.member then self:Act("invite", p.member) end end })
    p.invite:SetPoint("LEFT", p.whisper, "RIGHT", S["space-3"], 0)
    self.details = p
    return p
end

function M:ShowDetails(m)
    if not m then return end
    local p = self:BuildDetails()
    p.member = m
    p:SetTitle(m.name)
    local who = {}
    if m.level then who[#who + 1] = "Level " .. m.level end
    if m.class then
        local name = LOCALIZED_CLASS_NAMES_MALE and LOCALIZED_CLASS_NAMES_MALE[m.class]
        who[#who + 1] = name or m.class
    end
    p.line1:SetValue(table.concat(who, " "))
    p.line1:SetColor(m.class and T.color["class-" .. m.class:lower()] and ("class-" .. m.class:lower()) or "ink")
    p.line2:SetValue((m.rank or "") .. " · " .. (m.online and (m.zone or "Online") or (m.lastOnline or "Offline")))
    p.note:SetValue((m.note and m.note ~= "") and m.note or "|cff" .. T.color["ink-faint"].hex .. "No note|r")
    p.noteEdit:SetEnabledState((call(CanEditPublicNote) or m.you) and true or false)
    local canView = C_GuildInfo and call(C_GuildInfo.CanViewOfficerNote)
    p.officerHead:SetShown(canView and true or false)
    p.officer:SetShown(canView and true or false)
    p.officerEdit:SetShown(canView and true or false)
    p.officer:SetValue((m.officerNote and m.officerNote ~= "") and m.officerNote or "|cff" .. T.color["ink-faint"].hex .. "No officer note|r")
    p.officerEdit:SetEnabledState(C_GuildInfo and call(C_GuildInfo.CanEditOfficerNote) and true or false)
    -- the rows placed from the body's top by the texts' heights, never
    -- anchored to a text: the secure buttons hang off them, and a secure
    -- frame can't be anchored to a text ("Cannot anchor protected frames to
    -- regions", found in game)
    local S = T.space
    p.note:SetWidth(p.body:GetWidth())
    p.officer:SetWidth(p.body:GetWidth())
    local cap, lbl = T.type.caption.lineHeight, T.type.label.lineHeight
    local y = lbl + 2 + cap
    y = y + S["space-5"] + cap + S["space-3"] + math.max(T.type.body.lineHeight, math.ceil(p.note:GetStringHeight()))
    if canView then
        y = y + S["space-5"] + cap + S["space-3"] + math.max(T.type.body.lineHeight, math.ceil(p.officer:GetStringHeight()))
    end
    y = y + S["space-5"]
    p.row1:ClearAllPoints()
    p.row1:SetPoint("TOPLEFT", p.body, "TOPLEFT", 0, -y)
    p.row1:SetPoint("RIGHT", p.body, "RIGHT")
    p.body:SetHeight(y + 26)
    local a = self:Actions(m)
    p.whisper:SetEnabledState(a.whisper.enabled and true or false)
    p.invite:SetEnabledState(a.invite.enabled and true or false)
    p:Fit()
    p:Show()
end

--------------------------------------------------------------------------------
-- Over Blizzard's window
--------------------------------------------------------------------------------

-- The Info page's data.
function M:RenderInfo()
    local page = self.infoPage
    if not (page and page:IsVisible()) then return end
    local counts = {}
    for _, m in ipairs((self:Members())) do counts[m.rankIndex] = (counts[m.rankIndex] or 0) + 1 end
    local ranks = {}
    for i = 1, (call(GuildControlGetNumRanks)) or 0 do
        ranks[#ranks + 1] = { name = call(GuildControlGetRankName, i), count = counts[i - 1] or 0 }
    end
    local motd = call(GetGuildRosterMOTD)
    local info = call(GetGuildInfoText)
    page:SetData({ motd = plain(motd) and motd or nil, info = plain(info) and info or nil,
                   canEditMotd = call(CanEditMOTD), canEditInfo = call(CanEditGuildInfo), ranks = ranks })
end

-- Edit: Blizzard's own edit box for it (SetMOTD and SetInfoText are
-- forbidden to addon code; what you save in Blizzard's box is yours):
-- its "[Click to edit]" for the message of the day or the guild's
-- information, clicked.
function M:EditInfo(key)
    local details = self.frame and self.frame.GuildDetailsFrame
    local found = {}
    local function walk(fr, depth)
        if depth > 5 or not fr or not fr.GetChildren then return end
        for _, c in ipairs({ fr:GetChildren() }) do
            if c.GetObjectType and c:GetObjectType() == "Button" then
                local fs = c.GetFontString and c:GetFontString()
                local text = (fs and fs:GetText()) or (c.GetText and c:GetText()) or ""
                if type(text) == "string" and text:lower():find("edit") then found[#found + 1] = c end
            end
            walk(c, depth + 1)
        end
    end
    walk(details, 0)
    -- the left column's two, top to bottom: the message of the day, then the information
    table.sort(found, function(a, b)
        local al, bl = a:GetLeft() or 0, b:GetLeft() or 0
        if math.abs(al - bl) > 40 then return al < bl end
        return (a:GetTop() or 0) > (b:GetTop() or 0)
    end)
    local button = found[key == "motd" and 1 or 2]
    if button and button.Click then
        button:Click()
        return
    end
    self:EditInfoOwn(key)
end

function M:EditInfoOwn(key)
    local motd = key == "motd"
    local current = motd and call(GetGuildRosterMOTD) or call(GetGuildInfoText)
    UI.Confirm({ title = motd and "Message of the day" or "Guild information",
        text = motd and "Everyone in the guild sees it when they log in." or "What the guild is about, for its members.",
        input = { label = motd and "Message" or "Information", value = plain(current) and current or "" }, confirm = "Save",
        onConfirm = function(text)
            if motd then
                local set = (C_GuildInfo and C_GuildInfo.SetMOTD) or GuildSetMOTD
                if set then pcall(set, text) end
            else
                local set = (C_GuildInfo and C_GuildInfo.SetInfoText) or SetGuildInfoText
                if set then pcall(set, text) end
            end
            C_Timer.After(0.5, function() self:RenderInfo() end)
        end })
end

--------------------------------------------------------------------------------
-- The log, the club picker, Join or create
--------------------------------------------------------------------------------

local LOG = {
    invite = "%s invited %s", join = "%s joined the guild", promote = "%s promoted %s to %s",
    demote = "%s demoted %s to %s", remove = "%s removed %s", quit = "%s left the guild",
}

function M:RenderLog()
    local page = self.logPage
    if not (page and page:IsVisible()) then return end
    local lines = {}
    local n = (call(GetNumGuildEvents)) or 0
    for i = n, 1, -1 do
        local kind, p1, p2, rank, y, mo, d, h = call(GetGuildEventInfo, i)
        local fmt = LOG[kind or ""]
        if fmt then
            local text = fmt:format(p1 or "?", p2 or "?", rank or "?")
            local when
            if (y or 0) > 0 then when = y .. (y == 1 and " year ago" or " years ago")
            elseif (mo or 0) > 0 then when = mo .. (mo == 1 and " month ago" or " months ago")
            elseif (d or 0) > 0 then when = d .. (d == 1 and " day ago" or " days ago")
            elseif (h or 0) > 0 then when = h .. (h == 1 and " hour ago" or " hours ago")
            else when = "just now" end
            lines[#lines + 1] = { text = text, when = when }
        end
    end
    page:SetData({ lines = lines })
end

-- SuuUI's own pages over the window: "log", "settings", or nil (Blizzard's
-- tab's own page).
function M:ShowOwn(key)
    self.ownPage = key
    if key == "log" and QueryGuildEventLog then pcall(QueryGuildEventLog) end
    self:Follow()
    local chrome = self.frame and self.frame.suuChrome
    if chrome then chrome:UpdateTabs() end
end

-- Your guild and communities, the guild first.
function M:Clubs()
    local out = {}
    for _, c in ipairs((C_Club and call(C_Club.GetSubscribedClubs)) or {}) do
        if c.clubId and plain(c.name) then
            out[#out + 1] = { value = c.clubId, label = c.name, guild = c.clubType == (Enum.ClubType and Enum.ClubType.Guild or 2) }
        end
    end
    table.sort(out, function(a, b)
        if a.guild ~= b.guild then return a.guild end
        return a.label < b.label
    end)
    return out
end

-- Blizzard's own Join or Create Community entry in its (hidden) list.
function M:JoinOrCreate()
    local list = self.frame and self.frame.CommunitiesList
    local box = list and list.ScrollBox
    local found
    if box and box.ForEachFrame then
        box:ForEachFrame(function(b)
            local fs = b.Name or b.Text or (b.GetFontString and b:GetFontString())
            local text = fs and fs.GetText and fs:GetText()
            if not found and type(text) == "string" and (text:find("Join") or text:find("Create")) then found = b end
        end)
    end
    if found and found.Click then found:Click() else self:Print("The game's Join or Create Community isn't available here.") end
end

-- The picker in the header's tab row, right, and the + beside it.
function M:BuildPicker()
    local f = self.frame
    local chrome = f and f.suuChrome
    if not chrome or self.picker then return end
    local S = T.space
    local plus = CreateFrame("Button", nil, chrome.head)
    plus:SetSize(22, 22)
    plus:SetPoint("BOTTOMRIGHT", chrome.head, "BOTTOMRIGHT", -S["space-5"], 2)
    plus.edge = UI.Border(plus, "gilt-line")
    plus.glyph = plus:CreateTexture(nil, "ARTWORK")
    plus.glyph:SetTexture("Interface\\AddOns\\SuuUI\\Media\\Textures\\Glyphs\\plus.tga")
    plus.glyph:SetSize(12, 12)
    plus.glyph:SetVertexColor(UI.RGBA("ink-muted"))
    plus.glyph:SetPoint("CENTER")
    plus:SetScript("OnEnter", function(self2)
        self2.edge:SetColor("gilt")
        GameTooltip:SetOwner(self2, "ANCHOR_BOTTOMRIGHT")
        GameTooltip_SetTitle(GameTooltip, "Join or create a community")
        GameTooltip:Show()
    end)
    plus:SetScript("OnLeave", function(self2) self2.edge:SetColor("gilt-line"); GameTooltip:Hide() end)
    plus:SetScript("OnClick", function() self:JoinOrCreate() end)
    local picker = UI.Select(chrome.head, { bare = true, width = 220, textStyle = "label", textColor = "ink",
        options = self:Clubs(), onChange = function(id)
            self.ownPage = nil
            if f.SelectClub then f:SelectClub(id) end
        end })
    picker:SetPoint("RIGHT", plus, "LEFT", -S["space-3"], 0)
    self.picker, self.plus = picker, plus
end

function M:UpdatePicker()
    if not self.picker then return end
    self.picker:SetOptions(self:Clubs())
    local f = self.frame
    local club = f.GetSelectedClubId and f:GetSelectedClubId()
    if club then self.picker:SetValue(club) end
end

-- Blizzard's communities list on the left, folded away (the picker has its
-- job: asked for in game); kept as thin as a line, so the window's own
-- panes, which hang off it, move left into its place.
function M:FoldList()
    local f = self.frame
    local list = f and f.CommunitiesList
    if not list then return end
    list:SetAlpha(0)
    -- its width comes from its anchors: anchored again as a 1px strip at the
    -- window's left edge (setting the width alone left a gap, found in game)
    self.folding = true
    list:ClearAllPoints()
    list:SetPoint("TOPLEFT", f, "TOPLEFT", 8, -44)
    list:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 8, 16)
    list:SetWidth(1)
    self.folding = false
    if not self.listHooked then
        self.listHooked = true
        local function again() if not self.folding then C_Timer.After(0, function() self:FoldList() end) end end
        hooksecurefunc(list, "SetWidth", again)
        hooksecurefunc(list, "SetSize", again)
        hooksecurefunc(list, "SetPoint", again)
    end
    -- Blizzard's View Log and Invite Member: the Log tab and the roster
    -- (Invite to guild) have their jobs (asked for in game)
    self:HideButtons(f, 0)
    -- and by their keys, whatever their labels say (Invite Member was still
    -- there by label alone, found in game)
    -- off screen, and kept there (only see-through, the game showed it again)
    for _, b in ipairs({ f.InviteButton, f.GuildLogButton, f.CommunitiesControlFrame and f.CommunitiesControlFrame.InviteButton }) do
        if b then self:Away(b) end
    end
    -- Blizzard's control strip (Guild settings, recruitment, community
    -- settings): the roster's own Guild settings has its job (asked for)
    if f.CommunitiesControlFrame then self:Away(f.CommunitiesControlFrame) end
    self:LayChat()
end

local HIDDEN_BUTTONS = { ["View Log"] = true, ["Invite Member"] = true }

-- A Blizzard part off screen, back there whenever Blizzard places it.
function M:Away(part)
    self.awayParts = self.awayParts or {}
    if self.awayParts[part] or InCombatLockdown() then return end
    self.awayParts[part] = true
    local placing = false
    local function away()
        if InCombatLockdown() then return end
        placing = true
        part:ClearAllPoints()
        part:SetPoint("TOPLEFT", UIParent, "TOPRIGHT", 5000, 0)
        placing = false
    end
    away()
    hooksecurefunc(part, "SetPoint", function() if not placing then C_Timer.After(0, away) end end)
end

function M:HideButtons(frame, depth)
    if depth > 4 or not frame or not frame.GetChildren then return end
    for _, c in ipairs({ frame:GetChildren() }) do
        if c.GetObjectType and c:GetObjectType() == "Button" and not c.suuOwn then
            local fs = c.GetFontString and c:GetFontString()
            local text = (fs and fs:GetText()) or (c.GetText and c:GetText())
            if type(text) == "string" and (HIDDEN_BUTTONS[text] or text == _G.GUILD_VIEW_LOG) then
                c:SetAlpha(0)
                c:EnableMouse(false)
            end
        end
        if not c.suuOwn then self:HideButtons(c, depth + 1) end
    end
end

-- The chat across the whole width: Blizzard's member list beside it out of
-- sight (the roster has it: asked for in game), the stream menu over the
-- chat's left edge (it sat further right, found in game). Anchored to the
-- window, and again whenever Blizzard places them.
function M:LayChat()
    local f = self.frame
    if not f or not f.Chat then return end
    local S = T.space
    self.layingChat = true
    if f.StreamDropdown then
        f.StreamDropdown:ClearAllPoints()
        f.StreamDropdown:SetPoint("TOPLEFT", f, "TOPLEFT", 20, -44)
    end
    -- the messages in SuuUI's own box (Blizzard's inset frame and its
    -- corner art away), and the input line under it on its own: both edge
    -- to edge at the pages' 20px (they overlapped and differed in width,
    -- found in game)
    local EDIT_H = 28
    if f.Chat.InsetFrame then f.Chat.InsetFrame:SetAlpha(0) end
    -- the messages keep their own colours and spacing: the restyle pass
    -- recoloured and re-fonted the lines on show, until a scroll redrew
    -- them (found in game)
    if f.Chat.MessageFrame then f.Chat.MessageFrame.suuOwn = true end
    if not f.Chat.suuBox then
        f.Chat.suuBox = f.Chat:CreateTexture(nil, "BACKGROUND", nil, -7)
        f.Chat.suuBox:SetColorTexture(UI.RGBA("surface-sunk"))
        f.Chat.suuBox:SetAllPoints()
        f.Chat.suuEdge = UI.Border(f.Chat, "gilt-faint")
    end
    f.Chat:ClearAllPoints()
    f.Chat:SetPoint("TOPLEFT", f, "TOPLEFT", 20, -(44 + 24 + S["space-4"]))
    f.Chat:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -20, 16 + EDIT_H + S["space-3"])
    local edit = f.ChatEditBox
    if edit then
        if UI.ReskinEditBox then UI.ReskinEditBox(edit) end
        -- its look stands 4px out to the left (Reskin's field)
        edit:ClearAllPoints()
        edit:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 20 + 4, 16 + 1)
        edit:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -20, 16 + 1)
        edit:SetHeight(EDIT_H - 2)
    end
    -- the voice chat headset over the chat: out of sight
    if f.VoiceChatHeadset then f.VoiceChatHeadset:SetAlpha(0); f.VoiceChatHeadset:EnableMouse(false) end
    -- the member list beside the chat (in the chat's mode; the roster mode's
    -- is under SuuUI's roster page anyway)
    local modes = COMMUNITIES_FRAME_DISPLAY_MODES or {}
    local mode = f.GetDisplayMode and f:GetDisplayMode()
    if f.MemberList and mode == modes.CHAT then f.MemberList:SetAlpha(0) end
    self.layingChat = false
    if not self.chatHooked then
        self.chatHooked = true
        local function again() if not self.layingChat then C_Timer.After(0, function() self:LayChat() end) end end
        hooksecurefunc(f.Chat, "SetPoint", again)
        if f.ChatEditBox then hooksecurefunc(f.ChatEditBox, "SetPoint", again) end
        if f.StreamDropdown then hooksecurefunc(f.StreamDropdown, "SetPoint", again) end
        -- the hidden member list takes no clicks in the chat's mode
        if f.MemberList then
            f.MemberList:HookScript("OnShow", again)
        end
    end
    -- its clicks: none while hidden there
    if f.MemberList then
        local hidden = mode == modes.CHAT
        f.MemberList:EnableMouse(not hidden)
        if f.MemberList.ScrollBox then f.MemberList.ScrollBox:SetShown(not hidden) end
    end
end

-- The roster page while the window shows your guild's roster.
function M:Follow()
    local f = self.frame
    if not (f and self.roster) then return end
    local modes = COMMUNITIES_FRAME_DISPLAY_MODES or {}
    local mode = f.GetDisplayMode and f:GetDisplayMode()
    local club = f.GetSelectedClubId and f:GetSelectedClubId()
    local guild = C_Club and C_Club.GetGuildClubId and C_Club.GetGuildClubId()
    local isGuild = f:IsShown() and guild and club == guild
    if not isGuild then self.ownPage = nil end
    local onLog = isGuild and self.ownPage == "log"
    local onSettings = isGuild and self.ownPage == "settings"
    self:HostSettings(onSettings)
    local onRoster = isGuild and not self.ownPage and mode ~= nil and mode == modes.ROSTER
    local onInfo = isGuild and not self.ownPage and mode ~= nil and mode == modes.GUILD_INFO
    if self.logPage then
        self.logPage:SetShown(onLog and true or false)
        if onLog then self:RenderLog() end
    end
    self:BuildPicker()
    self:UpdatePicker()
    self:FoldList()
    if self.infoPage then
        self.infoPage:SetShown(onInfo and true or false)
        local blizz = f.GuildDetailsFrame
        if blizz then blizz:SetAlpha(onInfo and 0 or 1) end
        if onInfo then self:RenderInfo() end
    end
    -- the rest in SuuUI's look: Blizzard's own parts restyled in place
    C_Timer.After(0, function() if f:IsShown() then UI.Reskin(f) end end)
    self.roster:SetShown(onRoster and true or false)
    if not onRoster and not InCombatLockdown() then
        for _, over in pairs(self.overs or {}) do over:Hide(); over:ClearAllPoints() end
    end
    -- Blizzard's member list: under SuuUI's roster, and out of sight beside
    -- the chat (LayChat)
    if f.MemberList then f.MemberList:SetAlpha((onRoster or mode == modes.CHAT) and 0 or 1) end
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
    -- from the window's left edge (Blizzard's list is folded away)
    page:SetPoint("TOPLEFT", f, "TOPLEFT", 20, -44)
    page:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -20, 16)
    page:SetFrameLevel(f:GetFrameLevel() + 100)
    page:EnableMouse(true)
    page:Hide()
    self.roster = page
    page.suuOwn = true
    self:Wire(page)
    -- the Info page
    local info = UI.GuildInfo(f)
    info:SetAllPoints(page)
    info:SetFrameLevel(f:GetFrameLevel() + 100)
    info:EnableMouse(true)
    info:Hide()
    info.suuOwn = true
    info.onEdit = function(key) self:EditInfo(key) end
    self.infoPage = info
    -- the Log page: over the whole content, the chat's parts included
    local log = UI.GuildLog(f)
    log:SetAllPoints(page)
    log:SetFrameLevel(f:GetFrameLevel() + 150)
    log:EnableMouse(true)
    log:Hide()
    log.suuOwn = true
    self.logPage = log
    f:HookScript("OnShow", function() self:Follow() end)
    f:HookScript("OnHide", function()
        GameTooltip:Hide()
        if self.details then self.details:Hide() end
        -- the secure buttons let go of the window (it stays unprotected)
        if not InCombatLockdown() then for _, over in pairs(self.overs or {}) do over:Hide(); over:ClearAllPoints() end end
    end)
    if f.SetDisplayMode then hooksecurefunc(f, "SetDisplayMode", function() self:Follow() end) end
    if f.SelectClub then hooksecurefunc(f, "SelectClub", function() C_Timer.After(0, function() self:Follow() end) end) end
    self:Follow()
end

function M:OnEnable()
    self:Build()
    self:OnGameEvent("ADDON_LOADED", function() self:Build() end)
    local valid = C_EventUtils and C_EventUtils.IsEventValid
    -- the details' secure buttons away when a fight starts (rank changes
    -- wait for its end)
    self:OnGameEvent("PLAYER_REGEN_DISABLED", function()
        for _, over in pairs(self.overs or {}) do over:Hide() end
    end)
    self:OnGameEvent("PLAYER_REGEN_ENABLED", function() self:QueueRender() end)
    if not valid or valid("GUILD_MOTD") then self:OnGameEvent("GUILD_MOTD", function() self:RenderInfo() end) end
    if not valid or valid("GUILD_EVENT_LOG_UPDATE") then self:OnGameEvent("GUILD_EVENT_LOG_UPDATE", function() self:RenderLog() end) end
    if not valid or valid("CLUB_ADDED") then
        for _, e in ipairs({ "CLUB_ADDED", "CLUB_REMOVED", "CLUB_UPDATED" }) do
            self:OnGameEvent(e, function() self:UpdatePicker() end)
        end
    end
    for _, e in ipairs({ "GUILD_ROSTER_UPDATE", "PLAYER_GUILD_UPDATE", "GUILD_RANKS_UPDATE", "GROUP_ROSTER_UPDATE" }) do
        if not valid or valid(e) then
            self:OnGameEvent(e, function() if self.roster and self.roster:IsVisible() then self:QueueRender() end end)
        end
    end
end
