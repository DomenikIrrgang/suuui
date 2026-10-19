-- UI/Social.lua
-- The Social window's Contacts page (design component SocialWindow,
-- "Friends"): Friends / Ignored as a Segmented, "5 of 8 online", your own
-- status on the right; the list, online first then offline, each under a
-- caption heading with its count; a Battle.net friend shows the Battle.net
-- glyph and their Battle.net name, then the character they play in its
-- class colour; a character friend the class diamond and the name in class
-- colour. Under it: level, class and zone, "Playing Hearthstone", or "Last
-- online 2 days ago", then the note in quotes. Away and Busy are neutral
-- badges. Select a friend, then Whisper or Invite (disabled ones say why);
-- Add friend bottom left. Ignored: a row per name with Unignore; "Ignore a
-- player" instead of Add friend.
--
--   local c = UI.Contacts(parent)
--   c:SetData({ view = "friends" | "ignored", status = "available" | "away" |
--       "busy", me = "Suu#2397" (your BattleTag, shown at the top with the
--       status: the game's Battle.net bar's job), online, total,
--       friends = { row }, ignored = { name }, selected = key })
--     row = { key, bnet, name, character, color (class token), online,
--       detail, note, away, busy, whisper = bool, invite = bool, why (invite) }
--   c.onView(view), c.onStatus(status), c.onSelect(key), c.onWhisper(row),
--   c.onInvite(row), c.onAdd(), c.onIgnore(), c.onUnignore(name),
--   c.onMenu(row, owner)   -- a right click on a friend

local _, ns = ...

local UI, T = ns.UI, ns.Tokens
local S = T.space

local GLYPHS = "Interface\\AddOns\\SuuUI\\Media\\Textures\\Glyphs\\"
local ROW_H = 40
-- read when used: a theme can change the text styles
local function headH() return T.type.caption.lineHeight + S["space-3"] end
local TOP_H = 30
local FOOT_H = 26

local C = {}

-- the live pages, drawn again when the theme changes (colour codes in
-- their text, sizes from the text styles)
local contacts, peopleLists, raidGroups = {}, {}, {}
for _, set in ipairs({ contacts, peopleLists, raidGroups }) do setmetatable(set, { __mode = "k" }) end

-- the diamond at the name's middle
local function placeDiamond(r)
    r.diamond:SetPoint("CENTER", r, "TOPLEFT", S["space-5"], -(S["space-3"] + T.type.label.lineHeight / 2))
end

local function badge(parent)
    local b = CreateFrame("Frame", nil, parent)
    b:SetHeight(16)
    UI.Fill(b, "surface-raised"):SetAllPoints()
    UI.Border(b, "gilt-line")
    b.text = UI.Text(b, "micro", "ink-muted")
    b.text:SetPoint("CENTER")
    return b
end

local function makeRow(c)
    local r = CreateFrame("Button", nil, c.list.child)
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
    -- the head: a diamond (character) or the Battle.net glyph
    r.diamond = UI.Diamond(r, 7, "ink")
    placeDiamond(r)
    r.glyph = r:CreateTexture(nil, "ARTWORK")
    r.glyph:SetTexture(GLYPHS .. "people.tga")
    r.glyph:SetSize(14, 14)
    r.glyph:SetPoint("CENTER", r.diamond, "CENTER")
    r.name = UI.Text(r, "label", "ink")
    r.name:SetPoint("TOPLEFT", S["space-5"] + S["space-4"] + 2, -S["space-3"])
    r.name:SetJustifyH("LEFT")
    r.detail = UI.Text(r, "caption", "ink-muted")
    r.detail:SetPoint("TOPLEFT", r.name, "BOTTOMLEFT", 0, -1)
    r.detail:SetPoint("RIGHT", r, "RIGHT", -S["space-4"], 0)
    r.detail:SetJustifyH("LEFT")
    r.away = badge(r)
    r.away:SetPoint("TOPRIGHT", -S["space-4"], -S["space-3"])
    -- ignored: Unignore on the row
    r.unignore = UI.Button(r, { text = "Unignore", variant = "quiet", onClick = function()
        if r.ignoredName and c.onUnignore then c.onUnignore(r.ignoredName) end
    end })
    r.unignore:SetPoint("RIGHT", -S["space-4"], 0)
    r:SetScript("OnEnter", function(self) self.hover:Show() end)
    r:SetScript("OnLeave", function(self) self.hover:Hide() end)
    r:SetScript("OnClick", function(self, button)
        if not self.row then return end
        if c.onSelect then c.onSelect(self.row.key) end
        if button == "RightButton" and c.onMenu then c.onMenu(self.row, self) end
    end)
    r:SetScript("OnDoubleClick", function(self)
        if self.row and self.row.whisper and c.onWhisper then c.onWhisper(self.row) end
    end)
    return r
end

local function makeHead(c)
    local h = CreateFrame("Frame", nil, c.list.child)
    h:SetHeight(headH())
    h.text = UI.Text(h, "caption", "gilt-text")
    h.text:SetPoint("BOTTOMLEFT", S["space-4"], S["space-1"])
    h.rule = UI.Hairline(h, "gilt-line", "out")
    h.rule:SetPoint("LEFT", h.text, "RIGHT", S["space-3"], 0)
    h.rule:SetPoint("RIGHT", -S["space-4"], 0)
    return h
end

function C:Draw()
    local d = self.data or {}
    local view = d.view or "friends"
    local child = self.list.child
    child:SetWidth(math.max(1, self.list:GetWidth()))
    local y, nRow, nHead = 0, 0, 0
    local function head(text)
        nHead = nHead + 1
        local h = self.heads[nHead] or makeHead(self)
        self.heads[nHead] = h
        h.text:SetValue(text)
        h:SetHeight(headH())
        h:ClearAllPoints()
        h:SetPoint("TOPLEFT", child, "TOPLEFT", 0, -y)
        h:SetPoint("RIGHT", child, "RIGHT")
        h:Show()
        y = y + headH() + S["space-1"]
    end
    local function row()
        nRow = nRow + 1
        local r = self.rows[nRow] or makeRow(self)
        self.rows[nRow] = r
        r:ClearAllPoints()
        r:SetPoint("TOPLEFT", child, "TOPLEFT", 0, -y)
        r:SetPoint("RIGHT", child, "RIGHT")
        placeDiamond(r)
        r:Show()
        y = y + ROW_H
        return r
    end
    local selected
    if view == "friends" then
        local online, offline = {}, {}
        for _, f in ipairs(d.friends or {}) do
            if f.online then online[#online + 1] = f else offline[#offline + 1] = f end
        end
        for gi, group in ipairs({ { "Online", online }, { "Offline", offline } }) do
            if #group[2] > 0 then
                if gi == 2 and #online > 0 then y = y + S["space-3"] end
                head(group[1] .. " · " .. #group[2])
                for _, f in ipairs(group[2]) do
                    local r = row()
                    r.row, r.ignoredName = f, nil
                    r.unignore:Hide()
                    r.diamond:SetShown(not f.bnet)
                    r.glyph:SetShown(f.bnet and true or false)
                    UI.Paint(r.diamond, f.online and (f.color or "ink") or "ink-faint")
                    UI.Paint(r.glyph, f.online and "arcane" or "ink-faint")
                    -- Battle.net: their name, then the character in its class colour
                    local name = f.name or ""
                    if f.bnet and f.character and f.character ~= "" then
                        name = name .. "  |cff" .. T.color[f.color or "ink"].hex .. f.character .. "|r"
                    end
                    r.name:SetValue(name)
                    r.name:SetColor(f.online and (f.bnet and "ink" or (f.color or "ink")) or "ink-muted")
                    local detail = f.detail or ""
                    if f.note and f.note ~= "" then
                        detail = detail .. (detail ~= "" and "  " or "") .. "|cff" .. T.color["ink-faint"].hex .. "\"" .. f.note .. "\"|r"
                    end
                    r.detail:SetValue(detail)
                    r.detail:Show()
                    local status = f.busy and "Busy" or (f.away and "Away") or nil
                    r.away:SetShown(status ~= nil)
                    if status then
                        r.away.text:SetValue(status)
                        r.away:SetWidth(math.ceil(r.away.text:GetUnboundedStringWidth()) + S["space-4"] * 2)
                    end
                    r.name:SetPoint("RIGHT", status and r.away or r, status and "LEFT" or "RIGHT", -S["space-4"], 0)
                    local on = f.key == d.selected
                    r.sel:SetShown(on); r.edge:SetShown(on)
                    if on then selected = f end
                end
            end
        end
        self.empty:SetValue("No friends yet: Add friend, bottom left.")
    else
        if #(d.ignored or {}) > 0 then head("Ignored · " .. #d.ignored) end
        for _, name in ipairs(d.ignored or {}) do
            local r = row()
            r.row, r.ignoredName = nil, name
            r.diamond:Show()
            UI.Paint(r.diamond, "ink-faint")
            r.glyph:Hide()
            r.away:Hide()
            r.name:SetValue(name)
            r.name:SetColor("ink-muted")
            r.name:SetPoint("RIGHT", r.unignore, "LEFT", -S["space-4"], 0)
            r.detail:Hide()
            r.unignore:Show()
            r.sel:Hide(); r.edge:Hide()
        end
        self.empty:SetValue("You aren't ignoring anyone.")
    end
    for i = nRow + 1, #self.rows do self.rows[i]:Hide() end
    for i = nHead + 1, #self.heads do self.heads[i]:Hide() end
    self.empty:SetShown(nRow == 0)
    child:SetHeight(math.max(1, y))
    -- the foot
    local friends = view == "friends"
    self.add:SetLabel(friends and "Add friend" or "Ignore a player")
    self.whisper:SetShown(friends)
    self.invite:SetShown(friends)
    if friends then
        self.whisper:SetEnabledState(selected ~= nil and selected.whisper and true or false)
        self.whisper.reason = not selected and "Choose a friend first." or (not selected.whisper and "They're offline.") or nil
        self.invite:SetEnabledState(selected ~= nil and selected.invite and true or false)
        self.invite.reason = not selected and "Choose a friend first." or (not selected.invite and (selected.why or "They can't be invited.")) or nil
    end
    self.selectedRow = selected
end

local STATUS_COLOR = { available = "arcane", away = "amber", busy = "ember" }

function C:SetData(d)
    self.data = d
    -- you: your BattleTag (its number faint) and your status
    local me = d.me or ""
    local name, number = me:match("^(.-)(#%d+)$")
    self.me:SetValue(name and (name .. "|cff" .. T.color["ink-faint"].hex .. number .. "|r") or me)
    UI.Paint(self.meDot, STATUS_COLOR[d.status or "available"] or "arcane")
    self.views:SetValue(d.view or "friends")
    self.count:SetValue((d.online or 0) .. " of " .. (d.total or 0) .. " online")
    self.count:SetShown((d.view or "friends") == "friends")
    self.status:SetValue(d.status or "available")
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

function UI.Contacts(parent)
    local c = CreateFrame("Frame", nil, parent)
    Mixin(c, C)
    c.rows, c.heads = {}, {}
    -- the top: Friends / Ignored, how many are online, your status
    -- you: status diamond and BattleTag, the status menu on the right
    c.meDot = UI.Diamond(c, 9, "arcane")
    c.meDot:SetPoint("CENTER", c, "TOPLEFT", 6, -TOP_H / 2)
    c.me = UI.Text(c, "unit-name-lg", "ink")
    c.me:SetPoint("LEFT", c, "TOPLEFT", 6 + S["space-4"] + 2, -TOP_H / 2)
    c.views = UI.Segmented(c, { options = { { value = "friends", label = "Friends" }, { value = "ignored", label = "Ignored" } },
        onChange = function(v) if c.onView then c.onView(v) end end })
    c.views:SetPoint("TOPLEFT", 0, -(TOP_H + S["space-4"]))
    c.count = UI.Text(c, "caption", "ink-muted")
    c.count:SetPoint("LEFT", c.views, "RIGHT", S["space-5"], 0)
    c.status = UI.Select(c, { width = 120, value = "available", options = {
        { value = "available", label = "Available" }, { value = "away", label = "Away" }, { value = "busy", label = "Busy" } },
        onChange = function(v) if c.onStatus then c.onStatus(v) end end })
    c.status:SetPoint("TOPRIGHT")
    -- the foot
    c.add = footButton(c, "Add friend", "quiet", function()
        local view = c.data and c.data.view or "friends"
        if view == "friends" then if c.onAdd then c.onAdd() end elseif c.onIgnore then c.onIgnore() end
    end)
    c.add:SetPoint("BOTTOMLEFT")
    c.invite = footButton(c, "Invite", "primary", function()
        if c.selectedRow and c.onInvite then c.onInvite(c.selectedRow) end
    end)
    c.invite:SetPoint("BOTTOMRIGHT")
    c.whisper = footButton(c, "Whisper", "quiet", function()
        if c.selectedRow and c.onWhisper then c.onWhisper(c.selectedRow) end
    end)
    c.whisper:SetPoint("RIGHT", c.invite, "LEFT", -S["space-3"], 0)
    -- the list
    c.box = CreateFrame("Frame", nil, c)
    c.box:SetPoint("TOPLEFT", c, "TOPLEFT", 0, -(TOP_H * 2 + S["space-4"] * 2))
    c.box:SetPoint("BOTTOMRIGHT", c, "BOTTOMRIGHT", 0, FOOT_H + S["space-4"])
    UI.Fill(c.box, "surface-sunk"):SetAllPoints()
    UI.Border(c.box, "gilt-faint")
    c.list = UI.ScrollArea(c.box, 2)
    c.list:SetPoint("TOPLEFT", 1, -S["space-2"])
    c.list:SetPoint("BOTTOMRIGHT", -S["space-4"], S["space-2"])
    c.list:HookScript("OnSizeChanged", function() if c.data then c:Draw() end end)
    c.empty = UI.Text(c.box, "caption", "ink-muted")
    c.empty:SetPoint("CENTER")
    contacts[c] = true
    return c
end

--------------------------------------------------------------------------------
-- The Raid page (design component SocialWindow, "Raid"): "17 of 40", then
-- Ready check, Role check (leader or assistant; disabled with the reason
-- otherwise) and Raid Info; eight groups of five as surface-sunk wells,
-- each player a row with their role icon, the name in class colour, a
-- crown for the leader and a star for assistants; you in an ink border;
-- offline players at opacity-oor; empty slots in a faint edge. The leader
-- (and assistants) drag players between groups: onto an empty slot moves
-- them, onto a player swaps the two. Not in a raid: the explanation, and
-- "Convert to raid" in a party. With `plan` (0.17), a Plan button opens the
-- raid planner.
--
--   local r = UI.RaidGroups(parent)
--   r:SetData({ inRaid, inParty, canLead, reason, size, plan, members = { { index,
--       name, class, role, group, leader, assistant, online, dead, you } } })
--   r.onReadyCheck(), r.onRoleCheck(), r.onRaidInfo(), r.onConvert(), r.onPlan(),
--   r.onMove(index, group), r.onSwap(index, otherIndex), r.onMember(member, button, owner)
--------------------------------------------------------------------------------

local ROLE_ICON = {
    TANK = "Interface\\AddOns\\SuuUI\\Media\\Textures\\RoleTank.tga",
    HEALER = "Interface\\AddOns\\SuuUI\\Media\\Textures\\RoleHealer.tga",
    DAMAGER = "Interface\\AddOns\\SuuUI\\Media\\Textures\\RoleDamage.tga",
}
local SLOT_H = 22
local function groupLabelH() return T.type.caption.lineHeight + S["space-2"] end

local R = {}

local function slot(r, g, i)
    local b = CreateFrame("Button", nil, r.groups[g])
    b:SetHeight(SLOT_H)
    b:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    b:RegisterForDrag("LeftButton")
    b.group, b.pos = g, i
    b.fill = UI.Fill(b, "surface-raised")
    b.fill:SetAllPoints()
    b.edge = UI.Border(b, "gilt-faint")
    b.role = b:CreateTexture(nil, "ARTWORK")
    b.role:SetSize(12, 12)
    b.role:SetPoint("LEFT", S["space-3"], 0)
    b.name = UI.Text(b, "label", "ink")
    b.name:SetPoint("LEFT", b.role, "RIGHT", S["space-3"], 0)
    b.name:SetPoint("RIGHT", b, "RIGHT", -22, 0)
    b.name:SetJustifyH("LEFT")
    b.rank = b:CreateTexture(nil, "ARTWORK")
    b.rank:SetSize(12, 12)
    b.rank:SetPoint("RIGHT", -S["space-3"], 0)
    b:SetScript("OnEnter", function(self)
        if r.dragging and r.dragging ~= self then self.edge:SetColor("arcane") end
        if self.member then
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip_SetTitle(GameTooltip, self.member.name)
            local m = self.member
            local line = (m.level and m.level > 0 and ("Level " .. m.level .. " ") or "") .. (m.className or "")
            if line ~= "" then GameTooltip_AddNormalLine(GameTooltip, line) end
            if m.zone and m.zone ~= "" then GameTooltip_AddNormalLine(GameTooltip, m.zone) end
            if not m.online then GameTooltip_AddNormalLine(GameTooltip, "Offline") end
            GameTooltip:Show()
        end
    end)
    b:SetScript("OnLeave", function(self)
        self.edge:SetColor(self.member and (self.member.you and "ink" or "gilt-hairline") or "gilt-faint")
        GameTooltip:Hide()
    end)
    b:SetScript("OnClick", function(self, button)
        if self.member and r.onMember then r.onMember(self.member, button, self) end
    end)
    -- dragging: the member kept from the start (a roster update can redraw
    -- the slots meanwhile: their member was gone at the drop, found in
    -- game), a card following the cursor, the slot under it in arcane
    b:SetScript("OnDragStart", function(self)
        if not (self.member and r.data and r.data.canLead) or InCombatLockdown() then return end
        r.dragging, r.dragMember = self, self.member
        self:SetAlpha(0.5)
        r:StartGhost(self.member)
    end)
    b:SetScript("OnDragStop", function(self)
        self:SetAlpha(1)
        local member = r.dragMember
        local to = r:StopGhost()
        r.dragging, r.dragMember = nil, nil
        if not member then return end
        if not (to and to.group and to.pos) or to.member == member then r:Draw() return end
        if to.member then
            if r.onSwap then r.onSwap(member.index, to.member.index) end
        elseif r.onMove then
            r.onMove(member.index, to.group)
        end
    end)
    return b
end

-- The slot of this page under the cursor, if any.
function R:SlotUnderCursor()
    for g = 1, 8 do
        for i = 1, 5 do
            local b = self.slots[g][i]
            if b:IsVisible() and b:IsMouseOver() then return b end
        end
    end
end

function R:StartGhost(m)
    local gh = self.ghost
    if not gh then
        gh = CreateFrame("Frame", nil, UIParent)
        gh:SetFrameStrata("TOOLTIP")
        gh:SetSize(160, SLOT_H)
        UI.Fill(gh, "surface-raised"):SetAllPoints()
        UI.Border(gh, "arcane")
        gh.role = gh:CreateTexture(nil, "ARTWORK")
        gh.role:SetSize(12, 12)
        gh.role:SetPoint("LEFT", S["space-3"], 0)
        gh.name = UI.Text(gh, "label", "ink")
        gh.name:SetPoint("LEFT", gh.role, "RIGHT", S["space-3"], 0)
        gh:SetScript("OnUpdate", function(f)
            local scale = f:GetEffectiveScale()
            local x, y = GetCursorPosition()
            f:ClearAllPoints()
            f:SetPoint("LEFT", UIParent, "BOTTOMLEFT", x / scale + 12, y / scale)
            -- where they'd go
            local over = self:SlotUnderCursor()
            if over ~= self.overSlot then
                if self.overSlot then self.overSlot.edge:SetColor(self.overSlot.member and (self.overSlot.member.you and "ink" or "gilt-hairline") or "gilt-faint") end
                if over and over ~= self.dragging then over.edge:SetColor("arcane") end
                self.overSlot = over
            end
        end)
        self.ghost = gh
    end
    gh.role:SetShown(ROLE_ICON[m.role or ""] ~= nil)
    if ROLE_ICON[m.role or ""] then gh.role:SetTexture(ROLE_ICON[m.role]) end
    gh.name:SetValue(m.name or "")
    gh.name:SetColor(m.class and T.color["class-" .. m.class:lower()] and ("class-" .. m.class:lower()) or "ink")
    gh:SetWidth(math.max(120, math.ceil(gh.name:GetUnboundedStringWidth()) + 12 + S["space-3"] * 3))
    gh:Show()
end

-- The ghost away; the slot it was over (the drop's target).
function R:StopGhost()
    local over = self:SlotUnderCursor()
    if self.ghost then self.ghost:Hide() end
    if self.overSlot then
        self.overSlot.edge:SetColor(self.overSlot.member and (self.overSlot.member.you and "ink" or "gilt-hairline") or "gilt-faint")
        self.overSlot = nil
    end
    return over
end

function R:Draw()
    local d = self.data or {}
    local inRaid = d.inRaid
    self.notIn:SetShown(not inRaid)
    self.convert:SetShown(not inRaid and d.inParty and true or false)
    self.convert:SetEnabledState(d.canLead and true or false)
    for _, g in ipairs(self.groups) do g:SetShown(inRaid and true or false) end
    self.count:SetShown(inRaid and true or false)
    for _, b in ipairs({ self.ready, self.roles }) do
        b:SetShown(inRaid and true or false)
        b:SetEnabledState(d.canLead and true or false)
        b.reason = not d.canLead and (d.reason or "Only the leader or an assistant can.") or nil
    end
    self.info:Show()
    self.plan:SetShown(d.plan and true or false)
    local n = 0
    local byGroup = {}
    for _, m in ipairs(d.members or {}) do
        byGroup[m.group] = byGroup[m.group] or {}
        table.insert(byGroup[m.group], m)
        n = n + 1
    end
    self.count:SetValue(n .. " of " .. (d.size or 40))
    self:LayoutHead()
    if not inRaid then return end
    for g = 1, 8 do
        local list = byGroup[g] or {}
        for i = 1, 5 do
            local b = self.slots[g][i]
            local m = list[i]
            b.member = m
            if m then
                b.fill:Show()
                b.role:SetShown(ROLE_ICON[m.role or ""] ~= nil)
                if ROLE_ICON[m.role or ""] then
                    b.role:SetTexture(ROLE_ICON[m.role])
                    UI.Paint(b.role, m.role == "DAMAGER" and "ink-muted" or "ink")
                end
                b.name:SetValue(m.name or "")
                b.name:SetColor(m.class and T.color["class-" .. m.class:lower()] and ("class-" .. m.class:lower()) or "ink")
                b.rank:SetShown(m.leader or m.assistant or false)
                if m.leader then b.rank:SetTexture("Interface\\GroupFrame\\UI-Group-LeaderIcon")
                elseif m.assistant then b.rank:SetTexture("Interface\\GroupFrame\\UI-Group-AssistantIcon") end
                b.edge:SetColor(m.you and "ink" or "gilt-hairline")
                b:SetAlpha(m.online and 1 or T.opacity["opacity-oor"])
            else
                b.fill:Hide()
                b.role:Hide()
                b.rank:Hide()
                b.name:SetValue("")
                b.edge:SetColor("gilt-faint")
                b:SetAlpha(1)
            end
        end
    end
end

function R:SetData(d)
    self.data = d
    self:Draw()
end

-- Each group's slots under its label.
function R:PlaceSlots()
    for g = 1, 8 do
        for i = 1, 5 do
            self.slots[g][i]:SetPoint("TOPLEFT", self.groups[g], "TOPLEFT", S["space-2"], -(groupLabelH() + (i - 1) * (SLOT_H + S["space-1"])))
        end
    end
end

-- The head: the count at the left; right to left Raid Info, in a raid Role
-- check and Ready check, then Plan. The page is as wide as the game's
-- Social window, so when the count and every button don't fit in one row
-- (Plan covered the count, found in game) the buttons tighten their
-- padding and gaps; still too wide, the count goes under them, on a row of
-- its own, and the groups move down.
function R:LayoutHead()
    local inRaid = self.data and self.data.inRaid
    local list = { self.info }
    if inRaid then list[#list + 1] = self.roles; list[#list + 1] = self.ready end
    if self.plan:IsShown() then list[#list + 1] = self.plan end
    local countW = inRaid and math.ceil(UI.MeasureText("header", self.count:GetText() or "")) + S["space-5"] or 0
    local function width(pad, gap)
        local sum = gap * (#list - 1)
        for _, b in ipairs(list) do sum = sum + math.ceil(UI.MeasureText("label", b.text)) + pad * 2 end
        return sum
    end
    local w = self:GetWidth() or 0
    local pad, gap = S["space-5"], S["space-3"]
    if w > 0 and countW + width(pad, gap) > w then pad, gap = S["space-3"], S["space-2"] end
    local below = inRaid and w > 0 and countW + width(pad, gap) > w
    local prev
    for _, b in ipairs(list) do
        -- kept as the button's own width (it measures itself again on show)
        b.fixedWidth = math.ceil(UI.MeasureText("label", b.text)) + pad * 2
        b:SetWidth(b.fixedWidth)
        b:ClearAllPoints()
        if prev then b:SetPoint("RIGHT", prev, "LEFT", -gap, 0) else b:SetPoint("TOPRIGHT") end
        prev = b
    end
    self.count:ClearAllPoints()
    self.count:SetPoint("TOPLEFT", 0, below and -(30 + S["space-3"]) or -6)
    local h = below and (30 + S["space-3"] + T.type.header.lineHeight) or 30
    if h ~= self.headH then
        self.headH = h
        self:Layout()
    end
end

-- The groups laid out: two columns of four, filling the page's width.
function R:Layout()
    local w = self:GetWidth()
    if not w or w <= 0 then return end
    local gap = S["space-5"]
    local colW = math.floor((w - gap) / 2)
    local top = (self.headH or 30) + S["space-5"]
    local groupH = groupLabelH() + 5 * SLOT_H + 4 * S["space-1"]
    for g = 1, 8 do
        local col, row = (g - 1) % 2, math.floor((g - 1) / 2)
        local f = self.groups[g]
        f:ClearAllPoints()
        f:SetPoint("TOPLEFT", self, "TOPLEFT", col * (colW + gap), -(top + row * (groupH + S["space-5"])))
        f:SetSize(colW, groupH)
    end
end

local function headButton(parent, text, variant, onClick)
    local b = UI.Button(parent, { text = text, variant = variant, onClick = onClick })
    b.text = text
    b:HookScript("OnEnter", function(self)
        if self.reason and not self:IsEnabled() then UI.ShowTooltip(self, { title = text, description = self.reason }) end
    end)
    b:HookScript("OnLeave", function() UI.HideTooltip() end)
    return b
end

function UI.RaidGroups(parent)
    local r = CreateFrame("Frame", nil, parent)
    Mixin(r, R)
    r.count = UI.Text(r, "header", "gilt-text")
    r.count:SetPoint("TOPLEFT", 0, -6)
    -- (placed by LayoutHead)
    r.info = headButton(r, "Raid Info", "quiet", function() if r.onRaidInfo then r.onRaidInfo() end end)
    r.roles = headButton(r, "Role check", "quiet", function() if r.onRoleCheck then r.onRoleCheck() end end)
    r.ready = headButton(r, "Ready check", "quiet", function() if r.onReadyCheck then r.onReadyCheck() end end)
    r.plan = headButton(r, "Plan", "quiet", function() if r.onPlan then r.onPlan() end end)
    r.plan:Hide()
    r.groups, r.slots = {}, {}
    for g = 1, 8 do
        local f = CreateFrame("Frame", nil, r)
        UI.Fill(f, "surface-sunk"):SetAllPoints()
        f.label = UI.Text(f, "caption", "gilt-text")
        f.label:SetPoint("TOPLEFT", S["space-3"], -S["space-1"])
        f.label:SetValue("Group " .. g)
        r.groups[g] = f
        r.slots[g] = {}
        for i = 1, 5 do
            local b = slot(r, g, i)
            b:SetPoint("RIGHT", f, "RIGHT", -S["space-2"], 0)
            r.slots[g][i] = b
        end
    end
    r:PlaceSlots()
    -- not in a raid
    r.notIn = UI.Text(r, "body", "ink-muted")
    r.notIn:SetPoint("TOPLEFT", 0, -(30 + S["space-6"]))
    r.notIn:SetPoint("RIGHT", r, "RIGHT")
    r.notIn:SetWordWrap(true)
    r.notIn:SetJustifyH("LEFT")
    r.notIn:SetValue("You aren't in a raid. Raids are groups of more than five, for the biggest dungeons and fights. A party's leader can turn it into one.")
    r.convert = UI.Button(r, { text = "Convert to raid", variant = "primary",
        onClick = function() if r.onConvert then r.onConvert() end end })
    r.convert:SetPoint("TOPLEFT", r.notIn, "BOTTOMLEFT", 0, -S["space-5"])
    r:SetScript("OnSizeChanged", function(self) self:LayoutHead(); self:Layout() end)
    r:LayoutHead()
    raidGroups[r] = true
    return r
end

--------------------------------------------------------------------------------
-- A list of people (the Social window's Recent allies and Requests): a
-- caption heading with its count, then a row each like the friends list's
-- (class diamond, the name in class colour, a detail caption, a note in
-- quotes, a pin), with its own buttons at the right; a right click asks
-- the owner for a menu.
--
--   local l = UI.PeopleList(parent)
--   l:SetData({ title, empty, rows = { { key, name, color, glyph, online,
--       detail, note, pinned, actions = { { label, variant, onClick } } } } })
--   l.onMenu(row, owner)
--------------------------------------------------------------------------------

local PL = {}

local function plRow(l)
    local r = CreateFrame("Button", nil, l.list.child)
    r:SetHeight(ROW_H)
    r:RegisterForClicks("RightButtonUp")
    r.hover = UI.Fill(r, "gilt-faint", "BACKGROUND")
    r.hover:SetAllPoints()
    r.hover:Hide()
    r.diamond = UI.Diamond(r, 7, "ink")
    placeDiamond(r)
    r.glyph = r:CreateTexture(nil, "ARTWORK")
    r.glyph:SetTexture(GLYPHS .. "people.tga")
    r.glyph:SetSize(14, 14)
    r.glyph:SetPoint("CENTER", r.diamond, "CENTER")
    r.pin = r:CreateTexture(nil, "ARTWORK")
    r.pin:SetTexture(GLYPHS .. "flag.tga")
    r.pin:SetSize(11, 11)
    UI.Paint(r.pin, "gilt-text")
    r.name = UI.Text(r, "label", "ink")
    r.name:SetPoint("TOPLEFT", S["space-5"] + S["space-4"] + 2, -S["space-3"])
    r.name:SetJustifyH("LEFT")
    r.pin:SetPoint("LEFT", r.name, "RIGHT", S["space-3"], 0)
    r.detail = UI.Text(r, "caption", "ink-muted")
    r.detail:SetPoint("TOPLEFT", r.name, "BOTTOMLEFT", 0, -1)
    r.detail:SetJustifyH("LEFT")
    r.buttons = {}
    r:SetScript("OnEnter", function(self) self.hover:Show() end)
    r:SetScript("OnLeave", function(self) self.hover:Hide() end)
    r:SetScript("OnClick", function(self) if self.row and l.onMenu then l.onMenu(self.row, self) end end)
    return r
end

local function plButton(r, i, variant)
    r.buttons[variant] = r.buttons[variant] or {}
    local b = r.buttons[variant][i]
    if not b then
        b = UI.Button(r, { text = "", variant = variant })
        r.buttons[variant][i] = b
    end
    return b
end

function PL:Draw()
    local d = self.data or {}
    local child = self.list.child
    child:SetWidth(math.max(1, self.list:GetWidth()))
    local rows = d.rows or {}
    self.head.text:SetValue((d.title or "") .. " · " .. #rows)
    self.head:SetShown(#rows > 0)
    self.head:SetHeight(headH())
    local y = #rows > 0 and (headH() + S["space-1"]) or 0
    for i, row in ipairs(rows) do
        local r = self.rows[i] or plRow(self)
        self.rows[i] = r
        r.row = row
        r:ClearAllPoints()
        r:SetPoint("TOPLEFT", child, "TOPLEFT", 0, -y)
        r:SetPoint("RIGHT", child, "RIGHT")
        placeDiamond(r)
        r.diamond:SetShown(not row.glyph)
        r.glyph:SetShown(row.glyph and true or false)
        UI.Paint(r.diamond, row.online and (row.color or "ink") or "ink-faint")
        UI.Paint(r.glyph, row.online and "arcane" or "ink-muted")
        r.name:SetValue(row.name or "")
        r.name:SetColor(row.online ~= false and (row.color or "ink") or "ink-muted")
        r.pin:SetShown(row.pinned and true or false)
        local detail = row.detail or ""
        if row.note and row.note ~= "" then
            detail = detail .. (detail ~= "" and "  " or "") .. "|cff" .. T.color["ink-faint"].hex .. "\"" .. row.note .. "\"|r"
        end
        r.detail:SetValue(detail)
        -- its buttons, right-aligned
        for _, pool in pairs(r.buttons) do for _, b in ipairs(pool) do b:Hide() end end
        local x, used = 0, {}
        local actions = row.actions or {}
        for k = #actions, 1, -1 do
            local a = actions[k]
            local variant = a.variant or "quiet"
            used[variant] = (used[variant] or 0) + 1
            local b = plButton(r, used[variant], variant)
            b:SetLabel(a.label)
            b:SetEnabledState(not a.disabled)
            b:SetScript("OnClick", function() if a.onClick and not a.disabled then a.onClick(row) end end)
            b:ClearAllPoints()
            b:SetPoint("RIGHT", r, "RIGHT", -(S["space-4"] + x), 0)
            b:Show()
            x = x + b:GetWidth() + S["space-3"]
        end
        r.name:SetPoint("RIGHT", r, "RIGHT", -(S["space-4"] + x + 14), 0)
        r.detail:SetPoint("RIGHT", r, "RIGHT", -(S["space-4"] + x), 0)
        r:Show()
        y = y + ROW_H
    end
    for i = #rows + 1, #self.rows do self.rows[i]:Hide() end
    self.empty:SetValue(d.empty or "")
    self.empty:SetShown(#rows == 0)
    child:SetHeight(math.max(1, y))
end

function PL:SetData(d)
    self.data = d
    self:Draw()
end

function UI.PeopleList(parent)
    local l = CreateFrame("Frame", nil, parent)
    Mixin(l, PL)
    l.rows = {}
    UI.Fill(l, "surface-sunk"):SetAllPoints()
    UI.Border(l, "gilt-faint")
    l.list = UI.ScrollArea(l, 2)
    l.list:SetPoint("TOPLEFT", 1, -S["space-2"])
    l.list:SetPoint("BOTTOMRIGHT", -S["space-4"], S["space-2"])
    l.list:HookScript("OnSizeChanged", function() if l.data then l:Draw() end end)
    l.head = makeHead(l)
    l.head:SetPoint("TOPLEFT", l.list.child, "TOPLEFT")
    l.head:SetPoint("RIGHT", l.list.child, "RIGHT")
    l.empty = UI.Text(l, "caption", "ink-muted")
    l.empty:SetPoint("CENTER")
    peopleLists[l] = true
    return l
end

ns.Events.On("SUUUI_THEME_CHANGED", function()
    for c in pairs(contacts) do if c.data then c:SetData(c.data) end end
    for l in pairs(peopleLists) do if l.data then l:Draw() end end
    for r in pairs(raidGroups) do r:PlaceSlots(); r:LayoutHead(); r:Layout() end
end, "Social")
