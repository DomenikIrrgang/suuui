-- UI/GroupFinder.lua
-- The Group Finder's Browse page (design component GroupFinder, "Browse"):
-- one list of groups and players looking, from the game's tool and from
-- chat (ForeverLFG), in two collapsible sections, Groups and Players.
--   The bar: category, filter by activity, search, "Only what fits me",
--   Show (groups / players / both); the tool's age and Refresh (the tool
--   only searches on a click; primary once the results are stale). Too
--   narrow, the search field gives way first, then the selects.
--   A row (44px): a crown for a group or the player's class icon; the
--   activity, a level chip, a sprout (new player friendly), the reason it
--   concerns you (arcane, with the row in arcane-soft and a 2px arcane
--   edge); the leader in class colour, "Lvl 31 Mage", the play style and
--   the post or the listing's comment in quotes (the whole of it on
--   hover); role slots and "3/5" (or the roles offered), source badges,
--   age; Whisper, and Invite for a player looking.
--   Searching the tool for the first time: skeleton rows under what chat
--   has so far. Nothing to show: Clear filters and Refresh.
--
--   local b = UI.GroupFinderBrowse(parent)
--   b:SetData({
--       groups = { row }, players = { row }, collapsed = { groups, players },
--       tool = { age = seconds | nil, stale = bool, searching = bool, loading = bool },
--       category = value, categories = { { value, label } },
--       activities = { value, ... }, activityOptions = { { value, label } },
--       search = "", fits = bool, show = "both" | "group" | "player",
--   })
--     row = { key, activity, level ("29+"), newPlayerFriendly, reason, match,
--             leader, class (file), who ("Lvl 31 Mage"), playstyle, post,
--             slots = { "tank" | "healer" | "damage" (offered) | "has:tank" | "has:none"
--                       (a member, greyed) | "need:tank" | "open" }, rolesTip (hover text),
--             offered = { tank, healer, damage }, members = { have, max },
--             sources = { "Tool", "LookingForGroup", ... }, age ("2m"), canInvite }
--   b.onRefresh(), b.onFilter(changes), b.onWhisper(row), b.onInvite(row),
--   b.onToggle("groups" | "players"), b.onClear()

local _, ns = ...

local UI, T = ns.UI, ns.Tokens
local S = T.space

local TEX = "Interface\\AddOns\\SuuUI\\Media\\Textures\\"
local GLYPHS = TEX .. "Glyphs\\"
local ROLE_TEX = { tank = TEX .. "RoleTank.tga", healer = TEX .. "RoleHealer.tga", damage = TEX .. "RoleDamage.tga" }

local BAR_H = 30
local HEAD_H = 26
local ROW_H = 44
local ICON = 18

--------------------------------------------------------------------------------
-- Small parts: a role icon, a source badge
--------------------------------------------------------------------------------

-- A role icon (design component RoleIcon): filled (offered), has (a member
-- with it: greyed, ink-faint in gilt-faint, no fill), needed (a dim edge),
-- your role (arcane), a member with no role (a greyed diamond), open (hollow).
local function roleIcon(parent)
    local f = CreateFrame("Frame", nil, parent)
    f:SetSize(ICON, ICON)
    f.bg = UI.Fill(f, "surface-raised")
    f.bg:SetAllPoints()
    f.edge = UI.Border(f, "gilt-line")
    f.glyph = f:CreateTexture(nil, "OVERLAY")
    f.glyph:SetSize(ICON - 6, ICON - 6)
    f.glyph:SetPoint("CENTER")
    f.dot = UI.Diamond(f, 5, "ink-muted")
    f.dot:SetPoint("CENTER")
    function f:Set(kind, mine)
        local need = kind:match("^need:(.+)$")
        local has = kind:match("^has:(.+)$")
        if kind == "member" then has = "none" end
        local role = need or has or kind
        self.dot:Hide()
        self.glyph:Show()
        self.bg:Show()
        self.edge:SetShown(true)
        if has then
            -- what the group has: greyed
            self.bg:Hide()
            if ROLE_TEX[has] then
                self.glyph:SetTexture(ROLE_TEX[has])
                UI.Paint(self.glyph, "ink-faint")
                self.edge:SetColor("gilt-faint")
            else
                self.glyph:Hide(); self.edge:SetShown(false)
                UI.Paint(self.dot, "ink-faint")
                self.dot:Show()
            end
        elseif ROLE_TEX[role] then
            self.glyph:SetTexture(ROLE_TEX[role])
            if need then
                self.bg:Hide()
                self.edge:SetColor(mine and "arcane" or "ink-faint")
                UI.Paint(self.glyph, mine and "arcane" or "ink-muted")
            else
                self.edge:SetColor("gilt-line")
                UI.Paint(self.glyph, "ink")
            end
        else
            -- an open spot
            self.glyph:Hide(); self.bg:Hide()
            self.edge:SetColor("ink-faint")
        end
    end
    return f
end

-- A source badge (design component SourceBadge): "Tool" or the channel.
local function badge(parent)
    local b = CreateFrame("Frame", nil, parent)
    b:SetHeight(16)
    UI.Fill(b, "surface-raised"):SetAllPoints()
    UI.Border(b, "gilt-line")
    b.text = UI.Text(b, "micro", "ink-muted")
    b.text:SetPoint("CENTER")
    function b:SetLabel(s)
        self.text:SetValue(s)
        self:SetWidth(math.ceil(self.text:GetUnboundedStringWidth()) + 10)
    end
    return b
end

--------------------------------------------------------------------------------
-- A row
--------------------------------------------------------------------------------

-- A quiet 24px button with a glyph (Whisper, Invite); its word in a tooltip.
local function iconButton(parent, glyph, title, description, onClick)
    local btn = UI.Button(parent, { text = "", width = 24, onClick = onClick,
        tooltip = { title = title, description = description } })
    btn:SetHeight(24)
    btn.glyph = btn:CreateTexture(nil, "ARTWORK")
    btn.glyph:SetTexture(GLYPHS .. glyph .. ".tga")
    btn.glyph:SetSize(12, 12)
    btn.glyph:SetPoint("CENTER")
    UI.Paint(btn.glyph, "ink")
    return btn
end

local function makeRow(b)
    local r = CreateFrame("Button", nil, b.list.child)
    r:SetHeight(ROW_H)
    r.match = UI.Fill(r, "arcane-soft", "BACKGROUND")
    r.match:SetAllPoints()
    r.edge = UI.Fill(r, "arcane", "ARTWORK")
    r.edge:SetWidth(2)
    r.edge:SetPoint("TOPLEFT")
    r.edge:SetPoint("BOTTOMLEFT")
    r.hover = UI.Fill(r, "gilt-faint", "BACKGROUND", 1)
    r.hover:SetAllPoints()
    r.hover:Hide()
    r.rule = UI.Fill(r, "gilt-faint", "ARTWORK")
    r.rule:SetHeight(1)
    r.rule:SetPoint("BOTTOMLEFT", S["space-4"], 0)
    r.rule:SetPoint("BOTTOMRIGHT", -S["space-4"], 0)
    -- the lead: centred in a 20px column (drawRow sizes it)
    r.lead = r:CreateTexture(nil, "ARTWORK")
    r.lead:SetSize(20, 20)
    r.lead:SetPoint("CENTER", r, "LEFT", S["space-4"] + 10, 0)
    -- line 1
    r.activity = UI.Text(r, "label", "ink")
    r.activity:SetPoint("TOPLEFT", r, "LEFT", S["space-4"] + 20 + S["space-4"], 18)
    r.levelChip = CreateFrame("Frame", nil, r)
    r.levelChip:SetHeight(14)
    UI.Fill(r.levelChip, "surface-sunk"):SetAllPoints()
    UI.Border(r.levelChip, "gilt-faint")
    r.levelChip.text = UI.Text(r.levelChip, "micro", "ink-muted")
    r.levelChip.text:SetPoint("CENTER")
    r.sprout = r:CreateTexture(nil, "ARTWORK")
    r.sprout:SetTexture(GLYPHS .. "leaf.tga")
    r.sprout:SetSize(11, 11)
    UI.Paint(r.sprout, "ink-muted")
    r.reason = UI.Text(r, "caption", "arcane")
    -- line 2
    r.leader = UI.Text(r, "caption", "ink")
    r.leader:SetPoint("TOPLEFT", r.activity, "BOTTOMLEFT", 0, -3)
    r.who = UI.Text(r, "caption", "ink-muted")
    r.who:SetPoint("LEFT", r.leader, "RIGHT", S["space-3"], 0)
    r.post = UI.Text(r, "caption", "ink-muted")
    r.post:SetPoint("LEFT", r.who, "RIGHT", S["space-4"], 0)
    -- the right: Invite, Whisper, age, sources, roles
    -- Whisper and Invite as 24px glyph buttons (asked for in game: words
    -- took too much room), the word on hover
    r.invite = iconButton(r, "plus", "Invite", "Invite this player to your group",
        function() if b.onInvite and r.data then b.onInvite(r.data) end end)
    r.invite:SetPoint("RIGHT", -S["space-4"], 0)
    r.whisper = iconButton(r, "chat", "Whisper", "An empty whisper to them",
        function() if b.onWhisper and r.data then b.onWhisper(r.data) end end)
    -- always where it is on a player's row, so the column lines up
    r.whisper:SetPoint("RIGHT", r.invite, "LEFT", -S["space-3"], 0)
    r.age = UI.Text(r, "caption", "ink-faint")
    r.age:SetJustifyH("RIGHT")
    r.age:SetWidth(30)
    r.badges, r.slots = {}, {}
    r.count = UI.Text(r, "numeric", "ink-muted")
    r.rolesLabel = UI.Text(r, "caption", "ink-muted")
    r.slotsHit = CreateFrame("Frame", nil, r)
    r.slotsHit:SetFrameLevel(r:GetFrameLevel() + 5)
    r.slotsHit:SetScript("OnEnter", function(self)
        r.hover:Show()
        UI.ShowTooltip(self, { title = "Roles", description = self.tip })
    end)
    r.slotsHit:SetScript("OnLeave", function() r.hover:Hide(); UI.HideTooltip() end)
    r.slotsHit:Hide()
    r:SetScript("OnEnter", function(self)
        self.hover:Show()
        local d = self.data
        if d and d.post and d.post ~= "" then
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip_SetTitle(GameTooltip, d.leader or "")
            GameTooltip_AddNormalLine(GameTooltip, d.post, true)
            GameTooltip:Show()
        end
    end)
    r:SetScript("OnLeave", function(self) self.hover:Hide(); GameTooltip:Hide() end)
    return r
end

local function drawRow(b, r, d, y, width)
    r.data = d
    r:ClearAllPoints()
    r:SetPoint("TOPLEFT", b.list.child, "TOPLEFT", 0, -y)
    r:SetWidth(width)
    r.match:SetShown(d.match and true or false)
    r.edge:SetShown(d.match and true or false)
    -- the leading icon: a group's crown, or the player's class (people
    -- when it isn't known)
    local atlas = d.class and GetClassAtlas and GetClassAtlas(d.class)
    r.lead:ClearAllPoints()
    if d.isPlayer and atlas then
        r.lead:SetAtlas(atlas)
        r.lead:SetVertexColor(1, 1, 1, 1)
        r.lead:SetSize(20, 20)
    else
        r.lead:SetTexture(GLYPHS .. (d.isPlayer and "people.tga" or "crown.tga"))
        UI.Paint(r.lead, "gilt-text")
        local size = d.isPlayer and 20 or 16
        r.lead:SetSize(size, size)
    end
    r.lead:SetPoint("CENTER", r, "LEFT", S["space-4"] + 10, 0)
    r.activity:SetValue(d.activity or "")
    if d.level then
        r.levelChip.text:SetValue(d.level)
        r.levelChip:SetWidth(math.ceil(r.levelChip.text:GetUnboundedStringWidth()) + 8)
        r.levelChip:ClearAllPoints()
        r.levelChip:SetPoint("LEFT", r.activity, "RIGHT", S["space-3"], 0)
        r.levelChip:Show()
    else
        r.levelChip:Hide()
    end
    local last = d.level and r.levelChip or r.activity
    r.sprout:SetShown(d.newPlayerFriendly and true or false)
    if d.newPlayerFriendly then
        r.sprout:ClearAllPoints()
        r.sprout:SetPoint("LEFT", last, "RIGHT", S["space-3"], 0)
        last = r.sprout
    end
    r.reason:SetValue(d.reason or "")
    r.reason:ClearAllPoints()
    r.reason:SetPoint("LEFT", last, "RIGHT", S["space-4"], 0)
    local color = d.class and T.color["class-" .. d.class:lower()] and ("class-" .. d.class:lower()) or "ink"
    r.leader:SetValue(d.leader or "")
    r.leader:SetColor(color)
    r.who:SetValue(d.who or "")
    local post = d.playstyle or ""
    if d.post and d.post ~= "" then post = (post ~= "" and (post .. "  ") or "") .. "\"" .. d.post .. "\"" end
    r.post:SetValue(post)
    -- the right side, from the right edge leftwards
    r.invite:SetShown(d.canInvite and true or false)
    r.age:SetValue(d.age or "")
    r.age:ClearAllPoints()
    r.age:SetPoint("RIGHT", r.whisper, "LEFT", -S["space-4"], 0)
    -- right to left: the age, then the role slots and "3/5" (always the
    -- same distance from the age, so they line up from row to row: after
    -- the badges, whose width varies, they didn't; asked for in game), then
    -- the source badges, then the text
    local anchor = r.age
    -- a group's size ("3/5"), after its slots, in a column of its own
    local members = not d.isPlayer and d.members
    local counted = members and members[1] and members[2] and true or false
    r.count:SetShown(counted)
    if counted then
        r.count:SetValue(members[1] .. "/" .. members[2])
        r.count:SetWidth(34)
        r.count:SetJustifyH("RIGHT")
        r.count:ClearAllPoints()
        r.count:SetPoint("RIGHT", anchor, "LEFT", -S["space-5"], 0)
        anchor = r.count
    end
    -- roles: a group's slots, or what a player offers
    local slots = d.slots or {}
    for i = #slots, 1, -1 do
        local sl = r.slots[i] or roleIcon(r)
        r.slots[i] = sl
        sl:Set(slots[i], d.mine and d.mine[slots[i]:match("^need:(.+)$") or ""])
        sl:ClearAllPoints()
        local gap = i < #slots and -3 or (counted and -(S["space-2"] + 3) or -S["space-5"])
        sl:SetPoint("RIGHT", anchor, "LEFT", gap, 0)
        sl:Show()
        anchor = sl
    end
    for i = #slots + 1, #r.slots do r.slots[i]:Hide() end
    -- hovering the slots: all the group has and needs
    r.slotsHit:ClearAllPoints()
    if #slots > 0 and d.rolesTip then
        r.slotsHit:SetPoint("TOPLEFT", r.slots[1], "TOPLEFT", -2, 2)
        r.slotsHit:SetPoint("BOTTOMRIGHT", r.slots[#slots], "BOTTOMRIGHT", 2, -2)
        r.slotsHit.tip = d.rolesTip
        r.slotsHit:Show()
    else
        r.slotsHit:Hide()
    end
    r.rolesLabel:SetValue(d.isPlayer and #slots > 0 and "Roles:" or "")
    r.rolesLabel:ClearAllPoints()
    r.rolesLabel:SetPoint("RIGHT", anchor, "LEFT", -S["space-3"], 0)
    if r.rolesLabel:GetText() ~= "" then anchor = r.rolesLabel end
    -- where it was seen
    for i = #(d.sources or {}), 1, -1 do
        local bd = r.badges[i] or badge(r)
        r.badges[i] = bd
        bd:SetLabel(d.sources[i])
        bd:ClearAllPoints()
        bd:SetPoint("RIGHT", anchor, "LEFT", i == #d.sources and -S["space-5"] or -S["space-3"], 0)
        bd:Show()
        anchor = bd
    end
    for i = #(d.sources or {}) + 1, #r.badges do r.badges[i]:Hide() end
    -- the text stops before the right side
    r.post:SetPoint("RIGHT", anchor, "LEFT", -S["space-4"], 0)
    r.post:SetWordWrap(false)
    r:Show()
end

--------------------------------------------------------------------------------
-- The page
--------------------------------------------------------------------------------

local B = {}

local function sectionHead(b, key, label)
    local h = CreateFrame("Button", nil, b.list.child)
    h:SetHeight(HEAD_H)
    h.text = UI.Text(h, "header", "gilt-text")
    h.text:SetPoint("LEFT", S["space-4"], 0)
    h.count = UI.Text(h, "caption", "ink-muted")
    h.count:SetPoint("LEFT", h.text, "RIGHT", S["space-3"], 0)
    h.glyph = h:CreateTexture(nil, "ARTWORK")
    h.glyph:SetSize(12, 12)
    h.glyph:SetPoint("RIGHT", -S["space-4"], 0)
    UI.Paint(h.glyph, "ink-muted")
    -- a note before the chevron ("from chat so far" while the tool searches)
    h.note = UI.Text(h, "caption", "ink-faint")
    h.note:SetPoint("RIGHT", h.glyph, "LEFT", -S["space-3"], 0)
    h.rule = UI.Hairline(h, "gilt-line", "out")
    h.rule:SetPoint("LEFT", h.count, "RIGHT", S["space-4"], 0)
    h.rule:SetPoint("RIGHT", h.note, "LEFT", -S["space-4"], 0)
    h.label = label
    h:SetScript("OnClick", function() if b.onToggle then b.onToggle(key) end end)
    return h
end

-- Skeleton rows stand in for the tool's while it searches the first time:
-- a square, two lines, a block at the right, in surface-raised.
local function makeSkeleton(b)
    local r = CreateFrame("Frame", nil, b.list.child)
    r:SetHeight(ROW_H)
    r.a = UI.Fill(r, "surface-raised")
    r.a:SetSize(14, 14)
    r.a:SetPoint("CENTER", r, "LEFT", S["space-4"] + 10, 0)
    r.b = UI.Fill(r, "surface-raised")
    r.b:SetHeight(10)
    r.b:SetPoint("LEFT", S["space-4"] * 2 + 20, 5)
    r.b2 = UI.Fill(r, "surface-raised")
    r.b2:SetHeight(6)
    r.b2:SetPoint("TOPLEFT", r.b, "BOTTOMLEFT", 0, -4)
    r.c = UI.Fill(r, "surface-raised")
    r.c:SetSize(92, 14)
    r.c:SetPoint("RIGHT", -S["space-4"], 0)
    r.rule = UI.Fill(r, "gilt-faint", "ARTWORK")
    r.rule:SetHeight(1)
    r.rule:SetPoint("BOTTOMLEFT", S["space-4"], 0)
    r.rule:SetPoint("BOTTOMRIGHT", -S["space-4"], 0)
    return r
end

function B:SetData(d)
    self.data = d
    -- the bar
    self.category:SetOptions(d.categories or {})
    self.category:SetValue(d.category)
    self.activity:SetOptions(d.activityOptions or {})
    self.activity:SetValue(d.activities or {})
    if self.search:GetValue() ~= (d.search or "") and not self.search.edit:HasFocus() then self.search:SetValue(d.search or "") end
    self.fits:SetValue(d.fits)
    self.show:SetValue(d.show or "both")
    -- the tool's age
    local tool = d.tool or {}
    local text
    if tool.searching then text = "Searching the tool…"
    elseif not tool.age then text = "Tool not searched yet"
    else
        local m = math.floor(tool.age / 60)
        text = "Tool results " .. (m < 1 and "just now" or (m .. "m old")) .. (tool.stale and " · stale" or "")
    end
    self.staleText:SetValue(text)
    self.staleText:SetColor(tool.stale and "amber" or "ink-muted")
    UI.Paint(self.hourglass, tool.stale and "amber" or "ink-muted")
    -- stale: Refresh is the suggested action
    local stale = tool.stale and not tool.searching
    self.refreshQuiet:SetShown(not stale)
    self.refreshPrimary:SetShown(stale and true or false)
    self.refresh = stale and self.refreshPrimary or self.refreshQuiet
    self:LayoutBar()
    self:Draw()
end

-- The bar's widths (design: 150, 190, 170, the checkbox, 120; the tool's age
-- and Refresh at the right). Too narrow: Search gives way first (down to
-- 56), then the three selects by their widths; the age is cut short last.
-- Refresh never shrinks.
local BAR_BASIS = { category = 150, activity = 190, search = 170, show = 120 }
local BAR_MIN = { category = 80, activity = 90, search = 56, show = 80 }

function B:LayoutBar()
    local width = self:GetWidth()
    if not width or width <= 1 then return end
    local g = S["space-3"]
    local textW = math.ceil(UI.MeasureText("caption", self.staleText:GetText() or ""))
    local fresh = 12 + g + textW
    local fixed = self.refresh:GetWidth() + self.fits:GetWidth() + g * 8
    local w = {}
    for k, v in pairs(BAR_BASIS) do w[k] = v end
    local over = fixed + fresh + w.category + w.activity + w.search + w.show - width
    if over > 0 then
        local cut = math.min(over, w.search - BAR_MIN.search)
        w.search, over = w.search - cut, over - cut
    end
    if over > 0 then
        local room = 0
        for _, k in ipairs({ "category", "activity", "show" }) do room = room + (w[k] - BAR_MIN[k]) end
        local share = math.min(1, over / math.max(1, room))
        for _, k in ipairs({ "category", "activity", "show" }) do
            local cut = math.floor((w[k] - BAR_MIN[k]) * share + 0.5)
            w[k], over = w[k] - cut, over - cut
        end
    end
    if over > 0 then fresh = math.max(12, fresh - over) end
    self.category:SetWidth(w.category)
    self.activity:SetWidth(w.activity)
    self.search:SetWidth(w.search)
    self.show:SetWidth(w.show)
    self.staleText:ClearAllPoints()
    self.staleText:SetPoint("RIGHT", self.refresh, "LEFT", -g, 0)
    self.staleText:SetWidth(math.max(1, fresh - 12 - g))
    self.staleText:SetShown(fresh > 12)
end

function B:Draw()
    local d = self.data
    if not d then return end
    local width = math.max(1, self.list:GetWidth())
    self.list.child:SetWidth(width)
    local loading = d.tool and d.tool.loading
    local none = #(d.groups or {}) + #(d.players or {}) == 0 and not loading
    local y = 0
    local used, skels = 0, 0
    for _, key in ipairs({ "groups", "players" }) do
        local rows = d[key] or {}
        local h = self.heads[key]
        h:SetShown(not none)
        if not none then
            h:ClearAllPoints()
            h:SetPoint("TOPLEFT", self.list.child, "TOPLEFT", 0, -y)
            h:SetWidth(width)
            h.text:SetValue(h.label)
            h.count:SetValue(tostring(#rows))
            h.note:SetValue(loading and "from chat so far" or "")
            local closed = d.collapsed and d.collapsed[key]
            h.glyph:SetTexture(GLYPHS .. (closed and "chevronRight.tga" or "chevronDown.tga"))
            y = y + HEAD_H
            if not closed then
                for _, row in ipairs(rows) do
                    used = used + 1
                    local r = self.rows[used] or makeRow(self)
                    self.rows[used] = r
                    drawRow(self, r, row, y, width)
                    y = y + ROW_H
                end
                -- the tool's rows still to come
                for _ = 1, loading and (key == "groups" and 3 or 2) or 0 do
                    skels = skels + 1
                    local r = self.skeletons[skels] or makeSkeleton(self)
                    self.skeletons[skels] = r
                    r:ClearAllPoints()
                    r:SetPoint("TOPLEFT", self.list.child, "TOPLEFT", 0, -y)
                    r:SetWidth(width)
                    r.b:SetWidth(math.max(40, (width - 20 - S["space-4"] * 4 - 132) * 0.62))
                    r.b2:SetWidth(math.max(36, r.b:GetWidth() - 4))
                    r:Show()
                    y = y + ROW_H
                end
            end
            y = y + S["space-3"]
        end
    end
    for i = used + 1, #self.rows do self.rows[i]:Hide() end
    for i = skels + 1, #self.skeletons do self.skeletons[i]:Hide() end
    self.loadNote:SetShown(loading and true or false)
    if loading then
        self.loadNote:ClearAllPoints()
        self.loadNote:SetPoint("TOP", self.list.child, "TOP", 0, -(y + S["space-5"]))
        y = y + S["space-5"] * 2 + 16
    end
    self.list.child:SetHeight(math.max(1, y))
    self.empty:SetShown(none)
end

function UI.GroupFinderBrowse(parent)
    local b = CreateFrame("Frame", nil, parent)
    Mixin(b, B)
    b.rows, b.heads, b.skeletons = {}, {}, {}
    -- the bar
    local function changed(t) if b.onFilter then b.onFilter(t) end end
    local g = S["space-3"]
    b.category = UI.Select(b, { width = 150, placeholder = "Category",
        onChange = function(v) changed({ category = v }) end })
    b.category:SetPoint("TOPLEFT")
    b.category:SetHeight(BAR_H)
    b.activity = UI.Select(b, { width = 190, multiple = true, maxShown = 1, placeholder = "Filter by activity", maxRows = 12,
        onChange = function(v) changed({ activities = v }) end })
    b.activity:SetPoint("LEFT", b.category, "RIGHT", g, 0)
    b.activity:SetHeight(BAR_H)
    b.search = UI.TextField(b, { width = 170, placeholder = "Search",
        onTextChanged = function(text) changed({ search = text }) end })
    b.search:SetPoint("LEFT", b.activity, "RIGHT", g, 0)
    b.fits = UI.Checkbox(b, { label = "Only what fits me", onChange = function(on) changed({ fits = on }) end })
    b.fits:SetPoint("LEFT", b.search, "RIGHT", g * 2, 0)
    b.show = UI.Select(b, { width = 120, options = {
        { value = "both", label = "Both" }, { value = "group", label = "Groups" }, { value = "player", label = "Players looking" } },
        onChange = function(v) changed({ show = v }) end })
    b.show:SetPoint("LEFT", b.fits, "RIGHT", g * 2, 0)
    b.show:SetHeight(BAR_H)
    -- the tool's age and Refresh, at the right (primary once stale)
    local function refresh() if b.onRefresh then b.onRefresh() end end
    b.refreshQuiet = UI.Button(b, { text = "Refresh", variant = "quiet", onClick = refresh,
        tooltip = { title = "Refresh", description = "Search the tool again (chat entries are live)" } })
    b.refreshPrimary = UI.Button(b, { text = "Refresh", variant = "primary", onClick = refresh,
        tooltip = { title = "Refresh", description = "Search the tool again (chat entries are live)" } })
    for _, r in ipairs({ b.refreshQuiet, b.refreshPrimary }) do
        r:SetHeight(BAR_H)
        r:SetPoint("TOPRIGHT")
    end
    b.refreshPrimary:Hide()
    b.refresh = b.refreshQuiet
    b.staleText = UI.Text(b, "caption", "ink-muted")
    b.staleText:SetWordWrap(false)
    b.staleText:SetJustifyH("RIGHT")
    b.staleText:SetPoint("RIGHT", b.refresh, "LEFT", -g, 0)
    b.hourglass = b:CreateTexture(nil, "ARTWORK")
    b.hourglass:SetTexture(GLYPHS .. "hourglass.tga")
    b.hourglass:SetSize(12, 12)
    UI.Paint(b.hourglass, "ink-muted")
    b.hourglass:SetPoint("RIGHT", b.staleText, "LEFT", -g, 0)
    b:HookScript("OnSizeChanged", function() b:LayoutBar() end)
    -- the list
    b.box = CreateFrame("Frame", nil, b)
    b.box:SetPoint("TOPLEFT", 0, -(BAR_H + S["space-4"]))
    b.box:SetPoint("BOTTOMRIGHT")
    UI.Fill(b.box, "surface-sunk"):SetAllPoints()
    UI.Border(b.box, "gilt-faint")
    b.list = UI.ScrollArea(b.box, 2)
    b.list:SetPoint("TOPLEFT", 1, -S["space-2"])
    b.list:SetPoint("BOTTOMRIGHT", -S["space-4"], S["space-2"])
    b.list:HookScript("OnSizeChanged", function() b:Draw() end)
    b.heads.groups = sectionHead(b, "groups", "Groups")
    b.heads.players = sectionHead(b, "players", "Players")
    b.loadNote = UI.Text(b.list.child, "caption", "ink-muted")
    b.loadNote:SetValue("Searching the tool… Chat posts show up as they’re written.")
    -- nothing to show: a faint search glyph, what happened, Clear filters and Refresh
    local e = CreateFrame("Frame", nil, b.box)
    e:SetSize(360, 140)
    e:SetPoint("CENTER")
    e.glyph = e:CreateTexture(nil, "ARTWORK")
    e.glyph:SetTexture(GLYPHS .. "search.tga")
    e.glyph:SetSize(24, 24)
    UI.Paint(e.glyph, "ink-faint")
    e.glyph:SetPoint("TOP")
    e.title = UI.Text(e, "label", "ink")
    e.title:SetPoint("TOP", e.glyph, "BOTTOM", 0, -g)
    e.title:SetValue("Nothing matches your filters")
    e.text = UI.Text(e, "caption", "ink-muted")
    e.text:SetWidth(360)
    e.text:SetJustifyH("CENTER")
    e.text:SetPoint("TOP", e.title, "BOTTOM", 0, -g)
    e.text:SetValue("Chat posts show up here as they’re written. Clear a filter, or refresh the tool for new listings.")
    e.clear = UI.Button(e, { text = "Clear filters", icon = "close", onClick = function() if b.onClear then b.onClear() end end })
    e.refresh = UI.Button(e, { text = "Refresh", icon = "reset", onClick = refresh })
    for _, btn in ipairs({ e.clear, e.refresh }) do btn:SetHeight(26) end
    e.clear:SetPoint("TOPRIGHT", e.text, "BOTTOM", -g / 2, -g * 2)
    e.refresh:SetPoint("TOPLEFT", e.text, "BOTTOM", g / 2, -g * 2)
    e:Hide()
    b.empty = e
    return b
end
