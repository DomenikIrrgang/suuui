-- UI/Guild.lua
-- The Guild window's Roster page (design component GuildWindow, "Roster"):
-- search, Show offline (off by default), "7 online · 26 members"; columns
-- Name, Level, Zone, Rank, Note (click a heading to sort; rank order by
-- default); names in class colour with the class diamond, Away and Busy as
-- neutral badges, offline members in ink-faint with how long ago in place
-- of the zone. The selected member's actions along the foot: Whisper and
-- Invite; Promote, Demote and Remove only when your rank may and only for
-- members below you (Remove in ember); anything your rank can't do stays
-- visible, disabled, with the reason. Invite to guild bottom left.
--
--   local r = UI.GuildRoster(parent)
--   r:SetData({ online, total, showOffline, search, sort, members = { m },
--       selected, actions = { whisper, invite, promote, demote, remove } })
--     m = { key, name, class, level, zone, rank, rankIndex, note, officerNote,
--       online, away, busy, lastOnline ("3 days ago") }
--     actions.x = { enabled, why }
--   r.onSearch(text), r.onShowOffline(on), r.onSort(column), r.onSelect(key),
--   r.onAction(name, member) ("whisper", "invite", "promote", "demote",
--   "remove", "guildInvite"), r.onMenu(member, owner)

local _, ns = ...

local UI, T = ns.UI, ns.Tokens
local S = T.space

local ROW_H = 24
local HEAD_ROW_H = 22
local TOP_H = 30
local FOOT_H = 26

-- the columns: their share of the width after the fixed ones
local COLUMNS = {
    { key = "name", label = "Name", width = 0.30 },
    { key = "level", label = "Level", fixed = 44, align = "RIGHT" },
    { key = "zone", label = "Zone", width = 0.26 },
    { key = "rank", label = "Rank", width = 0.18 },
    { key = "note", label = "Note", width = 0.26 },
}

local G = {}

-- Each column's x and width for a row `w` wide.
local function columnsFor(w)
    local fixed = 0
    for _, c in ipairs(COLUMNS) do if c.fixed then fixed = fixed + c.fixed end end
    local gaps = S["space-4"] * (#COLUMNS - 1)
    local room = math.max(0, w - fixed - gaps - S["space-5"] * 2)
    local out, x = {}, S["space-5"]
    for i, c in ipairs(COLUMNS) do
        local cw = c.fixed or math.floor(room * c.width)
        out[i] = { x = x, w = cw }
        x = x + cw + S["space-4"]
    end
    return out
end

local function makeRow(g)
    local r = CreateFrame("Button", nil, g.list.child)
    r:SetHeight(ROW_H)
    r:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    r.sel = UI.Fill(r, "arcane-soft", "BACKGROUND")
    r.sel:SetAllPoints()
    r.edge = UI.Fill(r, "arcane", "ARTWORK")
    r.edge:SetWidth(2)
    r.edge:SetPoint("TOPLEFT")
    r.edge:SetPoint("BOTTOMLEFT")
    r.hover = UI.Fill(r, "gilt-faint", "BACKGROUND", 1)
    r.hover:SetAllPoints()
    r.hover:Hide()
    r.diamond = UI.Diamond(r, 6, "ink")
    r.cells = {}
    for i, c in ipairs(COLUMNS) do
        local t = UI.Text(r, i == 1 and "label" or "caption", "ink")
        t:SetJustifyH(c.align or "LEFT")
        r.cells[i] = t
    end
    r.badge = CreateFrame("Frame", nil, r)
    r.badge:SetHeight(14)
    UI.Fill(r.badge, "surface-raised"):SetAllPoints()
    UI.Border(r.badge, "gilt-line")
    r.badge.text = UI.Text(r.badge, "micro", "ink-muted")
    r.badge.text:SetPoint("CENTER")
    r:SetScript("OnEnter", function(self)
        self.hover:Show()
        local m = self.member
        if m and m.officerNote and m.officerNote ~= "" then
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip_SetTitle(GameTooltip, m.name)
            if m.note and m.note ~= "" then GameTooltip_AddNormalLine(GameTooltip, "Note: " .. m.note) end
            GameTooltip_AddNormalLine(GameTooltip, "Officer note: " .. m.officerNote)
            GameTooltip:Show()
        end
    end)
    r:SetScript("OnLeave", function(self) self.hover:Hide(); GameTooltip:Hide() end)
    r:SetScript("OnClick", function(self, button)
        if not self.member then return end
        if g.onSelect then g.onSelect(self.member.key) end
        if button == "RightButton" and g.onMenu then g.onMenu(self.member, self) end
    end)
    r:SetScript("OnDoubleClick", function(self)
        if self.member and self.member.online and g.onAction then g.onAction("whisper", self.member) end
    end)
    return r
end

function G:Draw()
    local d = self.data or {}
    local child = self.list.child
    local w = math.max(1, self.list:GetWidth())
    child:SetWidth(w)
    local cols = columnsFor(w)
    -- the headings
    for i, h in ipairs(self.heads) do
        h:ClearAllPoints()
        h:SetPoint("LEFT", self.headRow, "LEFT", cols[i].x, 0)
        h:SetWidth(cols[i].w)
        local on = (d.sort or "rank") == COLUMNS[i].key
        h.text:SetColor(on and "gilt-text" or "ink-muted")
        h.text:SetJustifyH(COLUMNS[i].align or "LEFT")
    end
    local y, selected = 0, nil
    for n, m in ipairs(d.members or {}) do
        local r = self.rows[n] or makeRow(self)
        self.rows[n] = r
        r.member = m
        r:ClearAllPoints()
        r:SetPoint("TOPLEFT", child, "TOPLEFT", 0, -y)
        r:SetPoint("RIGHT", child, "RIGHT")
        local color = m.online and (m.class and T.color["class-" .. m.class:lower()] and ("class-" .. m.class:lower()) or "ink") or "ink-faint"
        r.diamond:SetVertexColor(UI.RGBA(color))
        r.diamond:ClearAllPoints()
        r.diamond:SetPoint("CENTER", r, "LEFT", cols[1].x - 8, 0)
        local values = { m.name, m.level and tostring(m.level) or "", m.online and (m.zone or "") or (m.lastOnline or "Offline"),
                         m.rank or "", m.note or "" }
        for i, t in ipairs(r.cells) do
            t:ClearAllPoints()
            t:SetPoint("LEFT", r, "LEFT", cols[i].x, 0)
            t:SetWidth(cols[i].w)
            t:SetValue(values[i] or "")
            t:SetColor(i == 1 and color or (m.online and (i == 5 and "ink-muted" or "ink") or "ink-faint"))
        end
        local status = m.busy and "Busy" or (m.away and "Away") or nil
        r.badge:SetShown(status ~= nil and m.online)
        if status then
            r.badge.text:SetValue(status)
            r.badge:SetWidth(math.ceil(r.badge.text:GetUnboundedStringWidth()) + S["space-3"] * 2)
            r.badge:ClearAllPoints()
            r.badge:SetPoint("LEFT", r, "LEFT", cols[1].x + math.min(cols[1].w - 30,
                math.ceil(r.cells[1]:GetUnboundedStringWidth()) + S["space-3"]), 0)
        end
        local on = m.key == d.selected
        r.sel:SetShown(on); r.edge:SetShown(on)
        if on then selected = m end
        r:Show()
        y = y + ROW_H
    end
    for n = #(d.members or {}) + 1, #self.rows do self.rows[n]:Hide() end
    self.empty:SetShown(#(d.members or {}) == 0)
    child:SetHeight(math.max(1, y))
    -- the foot
    local a = d.actions or {}
    for key, b in pairs(self.buttons) do
        local s = a[key] or {}
        b:SetEnabledState(selected ~= nil and s.enabled and true or false)
        b.reason = not selected and "Choose a member first." or (not s.enabled and s.why) or nil
    end
    self.guildInvite:SetEnabledState(a.guildInvite and a.guildInvite.enabled and true or false)
    self.guildInvite.reason = a.guildInvite and not a.guildInvite.enabled and a.guildInvite.why or nil
    self.selectedMember = selected
end

function G:SetData(d)
    self.data = d
    self.count:SetValue((d.online or 0) .. " online · " .. (d.total or 0) .. (d.total == 1 and " member" or " members"))
    self.offline:SetValue(d.showOffline and true or false)
    self:Draw()
end

local function footButton(parent, text, variant, onClick)
    local b = UI.Button(parent, { text = text, variant = variant, onClick = onClick })
    b:HookScript("OnEnter", function(self)
        if self.reason and not self:IsEnabled() then UI.ShowTooltip(self, { title = text, description = self.reason }) end
    end)
    b:HookScript("OnLeave", function() UI.HideTooltip() end)
    return b
end

function UI.GuildRoster(parent)
    local g = CreateFrame("Frame", nil, parent)
    Mixin(g, G)
    g.rows, g.heads, g.buttons = {}, {}, {}
    -- the top: search, Show offline, the count
    g.search = UI.TextField(g, { width = 200, placeholder = "Search the roster",
        onTextChanged = function(text) if g.onSearch then g.onSearch(text) end end })
    g.search:SetPoint("TOPLEFT")
    g.offline = UI.Checkbox(g, { label = "Show offline", onChange = function(on) if g.onShowOffline then g.onShowOffline(on) end end })
    g.offline:SetPoint("LEFT", g.search, "RIGHT", S["space-5"], 0)
    g.count = UI.Text(g, "caption", "ink-muted")
    g.count:SetPoint("RIGHT", g, "TOPRIGHT", 0, -TOP_H / 2)
    -- the foot: Invite to guild left; the member's actions right
    g.guildInvite = footButton(g, "Invite to guild", "quiet", function() if g.onAction then g.onAction("guildInvite") end end)
    g.guildInvite:SetPoint("BOTTOMLEFT")
    local prev
    for _, def in ipairs({ { "remove", "Remove", "danger" }, { "demote", "Demote", "quiet" }, { "promote", "Promote", "quiet" },
                           { "invite", "Invite", "primary" }, { "whisper", "Whisper", "quiet" } }) do
        local key = def[1]
        local b = footButton(g, def[2], def[3] == "danger" and "quiet" or def[3], function()
            if g.selectedMember and g.onAction then g.onAction(key, g.selectedMember) end
        end)
        if def[3] == "danger" then
            b.border:SetColor("ember")
            b.label:SetColor("ember-text")
        end
        if prev then b:SetPoint("RIGHT", prev, "LEFT", -S["space-3"], 0) else b:SetPoint("BOTTOMRIGHT") end
        g.buttons[key] = b
        prev = b
    end
    -- the list: a heading row, then the members
    g.box = CreateFrame("Frame", nil, g)
    g.box:SetPoint("TOPLEFT", g, "TOPLEFT", 0, -(TOP_H + S["space-4"]))
    g.box:SetPoint("BOTTOMRIGHT", g, "BOTTOMRIGHT", 0, FOOT_H + S["space-4"])
    UI.Fill(g.box, "surface-sunk"):SetAllPoints()
    UI.Border(g.box, "gilt-faint")
    g.headRow = CreateFrame("Frame", nil, g.box)
    g.headRow:SetPoint("TOPLEFT", 1, -1)
    g.headRow:SetPoint("TOPRIGHT", -S["space-4"], -1)
    g.headRow:SetHeight(HEAD_ROW_H)
    local rule = UI.Fill(g.box, "gilt-faint", "ARTWORK")
    rule:SetHeight(1)
    rule:SetPoint("TOPLEFT", g.headRow, "BOTTOMLEFT")
    rule:SetPoint("TOPRIGHT", g.headRow, "BOTTOMRIGHT")
    for i, c in ipairs(COLUMNS) do
        local h = CreateFrame("Button", nil, g.headRow)
        h:SetHeight(HEAD_ROW_H)
        h.text = UI.Text(h, "caption", "ink-muted")
        h.text:SetAllPoints()
        h.text:SetValue(c.label)
        h:SetScript("OnClick", function() if g.onSort then g.onSort(c.key) end end)
        h:SetScript("OnEnter", function(self) self.text:SetColor("ink") end)
        h:SetScript("OnLeave", function(self)
            local on = ((g.data and g.data.sort) or "rank") == c.key
            self.text:SetColor(on and "gilt-text" or "ink-muted")
        end)
        g.heads[i] = h
    end
    g.list = UI.ScrollArea(g.box, 2)
    g.list:SetPoint("TOPLEFT", g.headRow, "BOTTOMLEFT", 0, -1)
    g.list:SetPoint("BOTTOMRIGHT", g.box, "BOTTOMRIGHT", -S["space-4"], S["space-2"])
    g.list:HookScript("OnSizeChanged", function() if g.data then g:Draw() end end)
    g.empty = UI.Text(g.box, "caption", "ink-muted")
    g.empty:SetPoint("CENTER")
    g.empty:SetValue("No one matches.")
    return g
end

--------------------------------------------------------------------------------
-- The Info page (design component GuildWindow, "Info"): the message of the
-- day, the guild information and the ranks with how many hold each; Edit
-- on the first two when your rank may.
--
--   local i = UI.GuildInfo(parent)
--   i:SetData({ motd, info, canEditMotd, canEditInfo, ranks = { { name, count } } })
--   i.onEdit("motd" | "info")
--------------------------------------------------------------------------------

local I = {}

function I:SetData(d)
    self.data = d
    local function block(b, text, can, empty)
        b.text:SetValue((text and text ~= "") and text or ("|cff" .. T.color["ink-faint"].hex .. empty .. "|r"))
        b.edit:SetShown(can and true or false)
    end
    block(self.motd, d.motd, d.canEditMotd, "No message of the day.")
    block(self.info, d.info, d.canEditInfo, "No guild information yet.")
    self:Layout()
    for i, r in ipairs(d.ranks or {}) do
        local row = self.rankRows[i]
        if not row then
            row = CreateFrame("Frame", nil, self.ranks)
            row:SetHeight(T.type.body.lineHeight + S["space-2"])
            row.name = UI.Text(row, "body", "ink")
            row.name:SetPoint("LEFT")
            row.count = UI.Text(row, "numeric", "ink-muted")
            row.count:SetPoint("RIGHT")
            self.rankRows[i] = row
        end
        row:ClearAllPoints()
        row:SetPoint("TOPLEFT", self.ranks, "TOPLEFT", 0, -(T.type.header.lineHeight + S["space-3"] + (i - 1) * row:GetHeight()))
        row:SetPoint("RIGHT", self.ranks, "RIGHT")
        row.name:SetValue(r.name or "")
        row.count:SetValue(tostring(r.count or 0))
        row:Show()
    end
    for i = #(d.ranks or {}) + 1, #self.rankRows do self.rankRows[i]:Hide() end
end

-- The two text blocks one under another in the left column, the ranks right.
function I:Layout()
    local w = self:GetWidth()
    if not w or w <= 0 then return end
    local gap = S["space-6"]
    local left = math.floor((w - gap) * 0.62)
    local y = 0
    for _, b in ipairs({ self.motd, self.info }) do
        b:ClearAllPoints()
        b:SetPoint("TOPLEFT", self, "TOPLEFT", 0, -y)
        b:SetWidth(left)
        b.text:SetWidth(left - S["space-5"] * 2)
        local h = T.type.header.lineHeight + S["space-3"] + math.max(T.type.body.lineHeight * 2, math.ceil(b.text:GetStringHeight())) + S["space-5"] * 2
        b:SetHeight(h)
        y = y + h + S["space-5"]
    end
    self.ranks:ClearAllPoints()
    self.ranks:SetPoint("TOPLEFT", self, "TOPLEFT", left + gap, 0)
    self.ranks:SetPoint("BOTTOMRIGHT", self, "BOTTOMRIGHT")
end

local function infoBlock(i, title, key)
    local b = CreateFrame("Frame", nil, i)
    UI.Fill(b, "surface-sunk"):SetAllPoints()
    UI.Border(b, "gilt-faint")
    b.head = UI.Text(b, "header", "gilt-text")
    b.head:SetPoint("TOPLEFT", S["space-5"], -S["space-5"])
    b.head:SetValue(title)
    b.edit = UI.Button(b, { text = "Edit", variant = "quiet", onClick = function() if i.onEdit then i.onEdit(key) end end })
    b.edit:SetPoint("TOPRIGHT", -S["space-4"], -S["space-3"])
    b.text = UI.Text(b, "body", "ink")
    b.text:SetPoint("TOPLEFT", b.head, "BOTTOMLEFT", 0, -S["space-3"])
    b.text:SetJustifyH("LEFT")
    b.text:SetWordWrap(true)
    return b
end

function UI.GuildInfo(parent)
    local i = CreateFrame("Frame", nil, parent)
    Mixin(i, I)
    i.rankRows = {}
    i.motd = infoBlock(i, "Message of the day", "motd")
    i.info = infoBlock(i, "Guild information", "info")
    i.ranks = CreateFrame("Frame", nil, i)
    i.ranks.head = UI.Text(i.ranks, "header", "gilt-text")
    i.ranks.head:SetPoint("TOPLEFT")
    i.ranks.head:SetValue("Ranks")
    i:SetScript("OnSizeChanged", function(self) if self.data then self:Layout() end end)
    return i
end
