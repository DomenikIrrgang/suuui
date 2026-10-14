-- UI/Guild.lua
-- The Guild window's Roster page (design component GuildWindow, "Roster"):
-- search, Show offline (off by default), "7 online · 26 members"; columns
-- Name, Level, Class (its icon and name), Zone, Rank, Note (click a heading to sort; rank order by
-- default); names in class colour with the class diamond, Away and Busy as
-- neutral badges, offline members' names in class colour too but faded
-- (opacity-disabled) and the rest of their row in ink-faint, with how long ago in place
-- of the zone. The selected member's actions along the foot: Whisper and
-- Invite; Promote, Demote and Remove only when your rank may and only for
-- members below you (Remove in ember); anything your rank can't do stays
-- visible, disabled, with the reason. Invite to guild bottom left.
--
--   local r = UI.GuildRoster(parent)
--   r:SetData({ online, total, showOffline, search, sort, members = { m },
--       selected, actions = { whisper, invite, promote, demote, remove } })
--     m = { key, name, class (its file name), className, level, zone, rank, rankIndex, note, officerNote,
--       online, away, busy, lastOnline ("3 days ago") }
--     actions.x = { enabled, why } (also guildInvite, which needs
--     no member)
--   r.onSearch(text), r.onShowOffline(on), r.onSort(column), r.onSelect(key),
--   r.onAction(name, member) ("whisper", "invite", "promote", "demote",
--   "remove", "guildInvite"), r.onMenu(member, owner), r.onRowEnter(row, member) and
--   r.onRowLeave(row) (a layer over the hovered row: the row's own scripts are
--   row:Click(button), row's OnEnter/OnLeave/OnDoubleClick)

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
    { key = "class", label = "Class", fixed = 104 },
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
    r.classIcon = r:CreateTexture(nil, "ARTWORK")
    r.classIcon:SetSize(16, 16)
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
        if g.onRowEnter and self.member then g.onRowEnter(self, self.member) end
        local m = self.member
        if m and m.officerNote and m.officerNote ~= "" then
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip_SetTitle(GameTooltip, m.name)
            if m.note and m.note ~= "" then GameTooltip_AddNormalLine(GameTooltip, "Note: " .. m.note) end
            GameTooltip_AddNormalLine(GameTooltip, "Officer note: " .. m.officerNote)
            GameTooltip:Show()
        end
    end)
    r:SetScript("OnLeave", function(self)
        self.hover:Hide()
        GameTooltip:Hide()
        if g.onRowLeave then g.onRowLeave(self) end
    end)
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
        -- the name in its class colour, online or not (asked for in game);
        -- an offline member's other columns stay ink-faint
        local color = m.class and T.color["class-" .. m.class:lower()] and ("class-" .. m.class:lower()) or (m.online and "ink" or "ink-faint")
        -- offline: still the class colour, greyed out like the rest of the row
        local fade = m.online and 1 or T.opacity["opacity-disabled"]
        r.diamond:SetVertexColor(UI.RGBA(color, fade))
        r.diamond:ClearAllPoints()
        r.diamond:SetPoint("CENTER", r, "LEFT", cols[1].x - 8, 0)
        local values = { name = m.name, level = m.level and tostring(m.level) or "", class = m.className or "",
                         zone = m.online and (m.zone or "") or (m.lastOnline or "Offline"), rank = m.rank or "", note = m.note or "" }
        for i, t in ipairs(r.cells) do
            local key = COLUMNS[i].key
            -- the class column: its icon, then its name
            local indent = key == "class" and (16 + S["space-3"]) or 0
            t:ClearAllPoints()
            t:SetPoint("LEFT", r, "LEFT", cols[i].x + indent, 0)
            t:SetWidth(cols[i].w - indent)
            t:SetValue(values[key] or "")
            if i == 1 then t:SetColor(color, fade)
            else t:SetColor(m.online and (key == "note" and "ink-muted" or "ink") or "ink-faint") end
            if key == "class" then
                local atlas = m.class and GetClassAtlas and GetClassAtlas(m.class)
                local coords = m.class and CLASS_ICON_TCOORDS and CLASS_ICON_TCOORDS[m.class]
                if atlas then
                    r.classIcon:SetAtlas(atlas)
                    r.classIcon:SetTexCoord(0, 1, 0, 1)
                elseif coords then
                    r.classIcon:SetTexture("Interface\\TargetingFrame\\UI-Classes-Circles")
                    r.classIcon:SetTexCoord(unpack(coords))
                end
                r.classIcon:SetShown((atlas or coords) and true or false)
                r.classIcon:SetDesaturated(not m.online)
                r.classIcon:SetAlpha(fade)
                r.classIcon:ClearAllPoints()
                r.classIcon:SetPoint("LEFT", r, "LEFT", cols[i].x, 0)
            end
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
-- The Info page (design component GuildWindow, "Info"): the guild
-- information down the whole left side (Edit when your rank may), the ranks
-- with how many hold each at the right. The message of the day lives on the
-- Chat tab (GuildMotdBanner).
--
--   local i = UI.GuildInfo(parent)
--   i:SetData({ info, canEditInfo, ranks = { { name, count } } })
--   i.onEdit("info")
--------------------------------------------------------------------------------

local I = {}

function I:SetData(d)
    self.data = d
    local function block(b, text, can, empty)
        b.text:SetValue((text and text ~= "") and text or ("|cff" .. T.color["ink-faint"].hex .. empty .. "|r"))
        b.edit:SetShown(can and true or false)
    end
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

-- The guild information down the left column, the ranks right.
function I:Layout()
    local w = self:GetWidth()
    if not w or w <= 0 then return end
    local gap = S["space-6"]
    local left = math.floor((w - gap) * 0.62)
    local b = self.info
    b:ClearAllPoints()
    b:SetPoint("TOPLEFT", self, "TOPLEFT", 0, 0)
    b:SetPoint("BOTTOMLEFT", self, "BOTTOMLEFT", 0, 0)
    b:SetWidth(left)
    b.text:SetWidth(left - S["space-5"] * 2)
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
    i.info = infoBlock(i, "Guild information", "info")
    i.ranks = CreateFrame("Frame", nil, i)
    i.ranks.head = UI.Text(i.ranks, "header", "gilt-text")
    i.ranks.head:SetPoint("TOPLEFT")
    i.ranks.head:SetValue("Ranks")
    i:SetScript("OnSizeChanged", function(self) if self.data then self:Layout() end end)
    return i
end

--------------------------------------------------------------------------------
-- The Log page: the guild's event log (who invited, promoted, demoted,
-- removed whom; who joined or left), newest first, how long ago at the right.
--
--   local l = UI.GuildLog(parent)
--   l:SetData({ lines = { { text, when } } })
--------------------------------------------------------------------------------

local L = {}

function L:SetData(d)
    self.data = d
    local child = self.list.child
    child:SetWidth(math.max(1, self.list:GetWidth()))
    local y = 0
    for i, line in ipairs(d.lines or {}) do
        local r = self.rows[i]
        if not r then
            r = CreateFrame("Frame", nil, child)
            r:SetHeight(T.type.body.lineHeight + S["space-3"])
            r.when = UI.Text(r, "caption", "ink-faint")
            r.when:SetPoint("RIGHT", -S["space-4"], 0)
            r.text = UI.Text(r, "body", "ink")
            r.text:SetPoint("LEFT", S["space-5"], 0)
            r.text:SetPoint("RIGHT", r.when, "LEFT", -S["space-4"], 0)
            r.text:SetJustifyH("LEFT")
            r.rule = UI.Fill(r, "gilt-faint", "ARTWORK")
            r.rule:SetHeight(1)
            r.rule:SetPoint("BOTTOMLEFT", S["space-4"], 0)
            r.rule:SetPoint("BOTTOMRIGHT", -S["space-4"], 0)
            self.rows[i] = r
        end
        r:ClearAllPoints()
        r:SetPoint("TOPLEFT", child, "TOPLEFT", 0, -y)
        r:SetPoint("RIGHT", child, "RIGHT")
        r.text:SetValue(line.text or "")
        r.when:SetValue(line.when or "")
        r:Show()
        y = y + r:GetHeight()
    end
    for i = #(d.lines or {}) + 1, #self.rows do self.rows[i]:Hide() end
    self.empty:SetShown(#(d.lines or {}) == 0)
    child:SetHeight(math.max(1, y))
end

function UI.GuildLog(parent)
    local l = CreateFrame("Frame", nil, parent)
    Mixin(l, L)
    l.rows = {}
    UI.Fill(l, "surface-sunk"):SetAllPoints()
    UI.Border(l, "gilt-faint")
    l.list = UI.ScrollArea(l, 2)
    l.list:SetPoint("TOPLEFT", 1, -S["space-2"])
    l.list:SetPoint("BOTTOMRIGHT", -S["space-4"], S["space-2"])
    l.list:HookScript("OnSizeChanged", function() if l.data then l:SetData(l.data) end end)
    l.empty = UI.Text(l, "caption", "ink-muted")
    l.empty:SetPoint("CENTER")
    l.empty:SetValue("Nothing has happened in the guild yet.")
    return l
end

--------------------------------------------------------------------------------
-- GuildMotdBanner: the guild's message of the day pinned to the top of the
-- Chat tab's messages box (design component GuildMotdBanner): surface-raised
-- with a gilt-faint edge (its bottom is the box's top), a pushpin and
-- "Message of the day" in `header` gilt-text, the message in `body` ink,
-- all centred on its middle with the same room above and below, two lines
-- at most (cut short with an ellipsis, the whole message in a
-- tooltip then). Edit at the right only when your rank may. No message, no
-- banner.
--
--   local b = UI.GuildMotdBanner(parent)
--   b:SetData({ text, canEdit })   -- b:Height(): the text's height and its padding, 0 when empty
--   b.onEdit()                      -- b.edit is the Edit button
--------------------------------------------------------------------------------

local GLYPHS = "Interface\\AddOns\\SuuUI\\Media\\Textures\\Glyphs\\"
local MB = {}

function MB:SetData(d)
    self.data = d
    local text = d and d.text
    local has = type(text) == "string" and text ~= ""
    self.has = has
    self:SetShown(has)
    if not has then return end
    self.edit:SetShown(d.canEdit and true or false)
    self.message:SetText(text)
    self:Layout()
end

function MB:Layout()
    if not self.has then return end
    local w = self:GetWidth()
    if not w or w < 100 then return end
    -- space-6 between the message and Edit (a little more room, asked for in game)
    local right = self.edit:IsShown() and (self.edit:GetWidth() + S["space-5"] + S["space-6"]) or S["space-5"]
    local left = S["space-5"] + 12 + S["space-3"] + self.head:GetStringWidth() + S["space-6"]
    self.message:SetWidth(math.max(60, w - left - right))
    -- as tall as the text really is, the same room above and below it
    local th = math.max(self.message:GetStringHeight() or 0, self.head:GetStringHeight() or 0, 14)
    local h = math.ceil(2 * S["space-4"] + th)
    if math.abs(self:GetHeight() - h) > 0.5 then self:SetHeight(h) end
end

function MB:Height()
    return self.has and self:GetHeight() or 0
end

function UI.GuildMotdBanner(parent)
    local b = CreateFrame("Frame", nil, parent)
    Mixin(b, MB)
    b:SetHeight(2 * S["space-4"] + T.type.body.lineHeight)
    UI.Fill(b, "surface-raised"):SetAllPoints()
    UI.Border(b, "gilt-faint")
    b:EnableMouse(true)
    b.pin = b:CreateTexture(nil, "OVERLAY")
    b.pin:SetTexture(GLYPHS .. "pushpin.tga")
    b.pin:SetSize(12, 12)
    b.pin:SetVertexColor(UI.RGBA("gilt-text"))
    -- all of it centred on the banner's middle, one line or two
    b.pin:SetPoint("LEFT", S["space-5"], 0)
    b.head = UI.Text(b, "header", "gilt-text")
    b.head:SetValue("Message of the day")
    b.head:SetPoint("LEFT", b.pin, "RIGHT", S["space-3"], 0)
    b.message = b:CreateFontString(nil, "OVERLAY")
    ns.Fonts.Apply(b.message, "body")
    b.message:SetTextColor(UI.RGBA("ink"))
    b.message:SetJustifyH("LEFT")
    b.message:SetJustifyV("TOP")
    b.message:SetWordWrap(true)
    b.message:SetMaxLines(2)
    -- space-6 after the label (a little more room, asked for in game)
    b.message:SetPoint("LEFT", b.head, "RIGHT", S["space-6"], 0)
    b.edit = UI.Button(b, { text = "Edit", variant = "quiet", onClick = function() if b.onEdit then b.onEdit() end end })
    b.edit:SetHeight(22)
    b.edit:SetPoint("RIGHT", -S["space-5"], 0)
    b:SetScript("OnSizeChanged", function() b:Layout() end)
    -- cut short: the whole message on hover
    b:SetScript("OnEnter", function(self)
        if not (self.has and self.message:IsTruncated()) then return end
        GameTooltip:SetOwner(self.message, "ANCHOR_BOTTOMLEFT", 0, 0)
        GameTooltip_SetTitle(GameTooltip, "Message of the day")
        GameTooltip_AddNormalLine(GameTooltip, self.data.text, true)
        GameTooltip:Show()
    end)
    b:SetScript("OnLeave", function() GameTooltip:Hide() end)
    b:Hide()
    return b
end
