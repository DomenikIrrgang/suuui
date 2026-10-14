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
--       "busy", online, total, friends = { row }, ignored = { name },
--       selected = key })
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
local HEAD_H = T.type.caption.lineHeight + S["space-3"]
local TOP_H = 30
local FOOT_H = 26

local C = {}

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
    r.diamond:SetPoint("CENTER", r, "TOPLEFT", S["space-5"], -(S["space-3"] + T.type.label.lineHeight / 2))
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
    h:SetHeight(HEAD_H)
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
        h:ClearAllPoints()
        h:SetPoint("TOPLEFT", child, "TOPLEFT", 0, -y)
        h:SetPoint("RIGHT", child, "RIGHT")
        h:Show()
        y = y + HEAD_H + S["space-1"]
    end
    local function row()
        nRow = nRow + 1
        local r = self.rows[nRow] or makeRow(self)
        self.rows[nRow] = r
        r:ClearAllPoints()
        r:SetPoint("TOPLEFT", child, "TOPLEFT", 0, -y)
        r:SetPoint("RIGHT", child, "RIGHT")
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
                    r.diamond:SetVertexColor(UI.RGBA(f.online and (f.color or "ink") or "ink-faint"))
                    r.glyph:SetVertexColor(UI.RGBA(f.online and "arcane" or "ink-faint"))
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
            r.diamond:SetVertexColor(UI.RGBA("ink-faint"))
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

function C:SetData(d)
    self.data = d
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
    c.views = UI.Segmented(c, { options = { { value = "friends", label = "Friends" }, { value = "ignored", label = "Ignored" } },
        onChange = function(v) if c.onView then c.onView(v) end end })
    c.views:SetPoint("TOPLEFT")
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
    c.box:SetPoint("TOPLEFT", c, "TOPLEFT", 0, -(TOP_H + S["space-4"]))
    c.box:SetPoint("BOTTOMRIGHT", c, "BOTTOMRIGHT", 0, FOOT_H + S["space-4"])
    UI.Fill(c.box, "surface-sunk"):SetAllPoints()
    UI.Border(c.box, "gilt-faint")
    c.list = UI.ScrollArea(c.box, 2)
    c.list:SetPoint("TOPLEFT", 1, -S["space-2"])
    c.list:SetPoint("BOTTOMRIGHT", -S["space-4"], S["space-2"])
    c.list:HookScript("OnSizeChanged", function() if c.data then c:Draw() end end)
    c.empty = UI.Text(c.box, "caption", "ink-muted")
    c.empty:SetPoint("CENTER")
    return c
end
