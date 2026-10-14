-- UI/Notification.lua
-- Notifications (design boards "Notifications", "Notification stack"): a
-- glass card `notice-w` wide, gilt-line edge (amber for a warning, ember for
-- danger), space-4 inside: the head (a 24px icon, the category caption over
-- the title, the time for requests (amber under soonAt), a close button for
-- notes), then the body caption, the item it is about, the confirm field
-- ("Type DELETE to confirm"), what makes it go (hourglass, "Goes when you
-- repair"), the actions right-aligned, and a 2px drain along the foot.
--
--   local n = UI.Notification(parent)
--   n:SetData({ kind, tone, category, title, body, icon = { glyph | texture,
--               tooltip = fn(owner) },
--               bodyTooltip = { title, description },
--               duration, remaining, soonAt, ["until"], item = { icon,
--               label, quality }, confirmText, actions = { { label,
--               variant = "primary"|"quiet"|"danger", onClick,
--               count, pressed, disabled, tooltip } },
--               host = { buttons = n, confirm = true }, closable, onClose })
--   0.13: presence = { online, source ("Battle.net", "Friend", the guild's
--     name), people = { { name, color (a class token), tag (a BattleTag's
--     #1234), detail ("Kaelith · World of Warcraft Forever"), whisper = fn,
--     icon = { texture, coords } } }, invite = fn }: a friend or guild member
--     came online (a status diamond in arcane, their class icon, the name in
--     class colour, the detail, Invite; a click whispers) or went offline
--     (one quiet line: an ink-faint diamond, the name in ink-muted, where
--     they're from at the right). Several at once: one card, "4 guild members
--     came online", each name whispering them (design board "Notifications ·
--     Friends").
--   n:SetRemaining(seconds)   -- the drain and the time, without a layout
--   n:SetTitle(text)          -- a title that counts (logging out in 12 s)
--   n.actionsRow, n.confirmBox  -- where hosted buttons and an edit box go
--
-- `host`: the actions (and the confirm box) belong to someone else, Blizzard's
-- own popup buttons placed by the owner into n.actionsRow (right-aligned,
-- `host.width` wide) and n.confirmBox; the card only keeps the room.
--
--   local s = UI.NotificationStack(parent, { max = 5 })
--   s:SetItems(list, inCombat)  -- each with an `id`; requests first, then
--                               -- conditions, notes, timed ones; in combat
--                               -- only requests and conditions
--   s:CardFor(id)               -- the card showing that id
--   s.onClearAll

local _, ns = ...

local UI, T = ns.UI, ns.Tokens
local S = T.space

local GLYPHS = "Interface\\AddOns\\SuuUI\\Media\\Textures\\Glyphs\\"
local WIDTH = T.size["notice-w"]
local PAD = S["space-4"]
local ICON = 24
local ACTION_H = 26
local FIELD_H = 30

local TONE_EDGE = { warning = "amber", danger = "ember" }

local Note = {}

local function clock(s)
    s = math.max(0, math.floor(s + 0.5))
    if s >= 60 then return ("%d:%02d"):format(math.floor(s / 60), s % 60) end
    return tostring(s)
end

-- A quiet, primary or danger button of the card's own (a SuuUI note); one
-- pool per look (a button's variant is set when it's made).
local function noteButton(n, i, variant)
    local pool = n.buttons[variant]
    if not pool then pool = {}; n.buttons[variant] = pool end
    local b = pool[i]
    if b then return b end
    b = UI.Button(n.actionsRow, { text = "", variant = variant == "primary" and "primary" or "quiet" })
    b:SetHeight(ACTION_H)
    if variant == "danger" then
        b.border:SetColor("ember")
        b.label:SetColor("ember-text")
        b:HookScript("OnLeave", function(self) self.border:SetColor("ember") end)
    end
    -- a choice made stays pressed in arcane (a loot roll's)
    b.pressedBg = UI.Fill(b, "arcane-soft", "BACKGROUND", 1)
    b.pressedBg:SetAllPoints()
    b.pressedBg:Hide()
    b:HookScript("OnLeave", function(self) if self.pressed then self.border:SetColor("arcane") end end)
    pool[i] = b
    return b
end

function Note:SetIcon(icon)
    icon = icon or {}
    self.iconTip = icon.tooltip
    local art = self.iconArt
    if icon.glyph then
        art:SetTexture(GLYPHS .. icon.glyph .. ".tga")
        art:SetTexCoord(0, 1, 0, 1)
        art:ClearAllPoints()
        art:SetPoint("TOPLEFT", 4, -4)
        art:SetPoint("BOTTOMRIGHT", -4, 4)
        art:SetVertexColor(UI.RGBA(icon.color or "ink"))
    else
        art:SetTexture(icon.texture or (GLYPHS .. "bell.tga"))
        if icon.coords then art:SetTexCoord(unpack(icon.coords))
        else art:SetTexCoord(0.08, 0.92, 0.08, 0.92) end
        art:ClearAllPoints()
        art:SetPoint("TOPLEFT", 1, -1)
        art:SetPoint("BOTTOMRIGHT", -1, 1)
        art:SetVertexColor(1, 1, 1, 1)
    end
end

function Note:SetTitle(text)
    self.title:SetValue(text or "")
end

-- A name on a group presence card: whispers them.
local function nameButton(n, i)
    local b = n.names[i]
    if b then return b end
    b = CreateFrame("Button", nil, n.namesRow)
    b.text = UI.Text(b, "label", "ink")
    b.text:SetPoint("LEFT")
    b:SetScript("OnEnter", function(self) self.text:SetAlpha(0.75) end)
    b:SetScript("OnLeave", function(self) self.text:SetAlpha(1) end)
    b:SetScript("OnClick", function(self) if self.person and self.person.whisper then self.person.whisper() end end)
    n.names[i] = b
    return b
end

-- The presence layout (see SetData's presence).
function Note:SetPresence(d)
    local p = d.presence
    local people = p.people or {}
    local single = #people == 1
    for _, f in ipairs({ self.bodyRow, self.itemRow, self.confirmRow, self.untilRow }) do f:Hide() end
    for _, pool in pairs(self.buttons) do for _, b in ipairs(pool) do b:Hide() end end
    for _, b in ipairs(self.names) do b:Hide() end
    self.namesRow:Hide()
    self.time:Hide()
    self.drain:Hide()
    self.border:SetColor("gilt-line")
    self.status:Show()
    self.status:SetVertexColor(UI.RGBA(p.online and "arcane" or "ink-faint"))
    -- a click on the card: whisper the one person on it
    self.onCardClick = single and people[1].whisper or nil
    if not p.online then
        -- offline: one quiet line
        self.icon:Hide()
        self.close:Hide()
        self.category:Hide()
        local names = {}
        for i, person in ipairs(people) do
            if i > 2 then break end
            names[#names + 1] = person.name
        end
        local text = table.concat(names, ", ")
        if #people > 2 then text = text .. " and " .. (#people - 2) .. " more" end
        self.title:SetValue(text .. (single and " went offline" or " went offline"))
        self.title:SetColor("ink-muted")
        self.source:SetValue(p.source or "")
        self.source:Show()
        local lineH = T.type.label.lineHeight
        self.head:SetHeight(lineH)
        self.status:ClearAllPoints()
        self.status:SetPoint("CENTER", self.head, "LEFT", 4, 0)
        self.title:SetWidth(WIDTH - PAD * 2 - 14 - self.source:GetUnboundedStringWidth() - S["space-4"])
        self.title:ClearAllPoints()
        self.title:SetPoint("LEFT", self.head, "LEFT", 14, 0)
        self.source:ClearAllPoints()
        self.source:SetPoint("RIGHT", self.head, "RIGHT")
        self:SetHeight(PAD * 2 + lineH)
        return PAD * 2 + lineH
    end
    -- online
    self.icon:Show()
    self.source:Hide()
    self.close:Show()
    if single and people[1].icon then
        self:SetIcon(people[1].icon)
    else
        self:SetIcon({ glyph = p.glyph or "people" })
    end
    self.category:SetValue("Online · " .. (p.source or ""))
    self.category:Show()
    local title
    if single then
        local person = people[1]
        title = person.name .. (person.tag and ("|cff" .. T.color["ink-faint"].hex .. person.tag .. "|r") or "")
        self.title:SetColor(person.color or "ink")
    else
        title = #people .. " " .. (p.plural or "people") .. " came online"
        self.title:SetColor("ink")
    end
    self.title:SetValue(title)
    local textW = WIDTH - PAD * 2 - ICON - S["space-4"] - 22 - S["space-3"]
    self.title:SetWidth(textW)
    self.category:SetWidth(textW - 10)
    local titleH = T.type.label.lineHeight
    local catH = T.type.caption.lineHeight
    local headH = math.max(ICON, catH + titleH)
    self.head:SetHeight(headH)
    local top = math.max(0, (headH - catH - titleH) / 2)
    local x = ICON + S["space-4"]
    self.status:ClearAllPoints()
    self.status:SetPoint("CENTER", self.head, "TOPLEFT", x + 3, -(top + catH / 2))
    self.category:ClearAllPoints()
    self.category:SetPoint("TOPLEFT", x + 10, -top)
    self.title:ClearAllPoints()
    self.title:SetPoint("TOPLEFT", x, -(top + catH))
    local y = PAD + headH
    if single then
        local person = people[1]
        if person.detail and person.detail ~= "" then
            self.body:SetWidth(WIDTH - PAD * 2)
            self.body:SetValue(person.detail)
            local h = T.type.caption.lineHeight
            y = y + S["space-3"]
            self.bodyRow:ClearAllPoints()
            self.bodyRow:SetPoint("TOPLEFT", PAD, -y)
            self.bodyRow:SetPoint("TOPRIGHT", -PAD, -y)
            self.bodyRow:SetHeight(h)
            self.bodyRow:EnableMouse(false)
            self.bodyRow:Show()
            y = y + h
        end
        if p.invite then
            y = y + S["space-3"]
            self.actionsRow:ClearAllPoints()
            self.actionsRow:SetPoint("TOPLEFT", PAD, -y)
            self.actionsRow:SetPoint("TOPRIGHT", -PAD, -y)
            self.actionsRow:SetHeight(ACTION_H)
            self.actionsRow:Show()
            local b = noteButton(self, 1, "quiet")
            b:SetLabel("Invite")
            b.pressed = false
            b.pressedBg:SetShown(false)
            b.border:SetColor("gilt-line")
            b.label:SetColor("ink")
            b:SetEnabledState(true)
            b.tooltip = nil
            b:SetScript("OnClick", function() p.invite() end)
            b:ClearAllPoints()
            b:SetPoint("RIGHT")
            b:Show()
            y = y + ACTION_H
        else
            self.actionsRow:Hide()
        end
    else
        -- the names, each whispering them, wrapping
        self.actionsRow:Hide()
        y = y + S["space-3"]
        local inner, x2, rowY = WIDTH - PAD * 2, 0, 0
        local lineH = T.type.label.lineHeight
        for i, person in ipairs(people) do
            local b = nameButton(self, i)
            b.person = person
            local sep = i < #people and "," or ""
            b.text:SetValue(person.name .. sep)
            b.text:SetColor(person.color or "ink")
            local w = math.ceil(b.text:GetUnboundedStringWidth())
            if x2 > 0 and x2 + w > inner then x2 = 0; rowY = rowY + lineH + S["space-1"] end
            b:SetSize(w, lineH)
            b:ClearAllPoints()
            b:SetPoint("TOPLEFT", self.namesRow, "TOPLEFT", x2, -rowY)
            b:Show()
            x2 = x2 + w + S["space-3"]
        end
        local h = rowY + lineH
        self.namesRow:ClearAllPoints()
        self.namesRow:SetPoint("TOPLEFT", PAD, -y)
        self.namesRow:SetPoint("TOPRIGHT", -PAD, -y)
        self.namesRow:SetHeight(h)
        self.namesRow:Show()
        y = y + h
    end
    y = y + PAD
    self:SetHeight(y)
    -- the drain of a timed note
    if d.duration and d.remaining then
        self.drain:Show()
        self.drain:SetColorTexture(UI.RGBA("gilt-line"))
        self:SetRemaining(d.remaining)
    end
    return y
end

function Note:SetData(d)
    self.data = d
    self.status:Hide()
    self.source:Hide()
    self.namesRow:Hide()
    self.onCardClick = nil
    if d.presence then return self:SetPresence(d) end
    self.icon:Show()
    self.category:Show()
    self.title:SetColor("ink")
    local kind = d.kind or "timed"
    self.border:SetColor(TONE_EDGE[d.tone] or "gilt-line")
    self:SetIcon(d.icon)
    self.category:SetValue(d.category or "")
    self.category:SetShown(d.category ~= nil and d.category ~= "")
    self.title:SetValue(d.title or "")
    local closable = d.closable
    if closable == nil then closable = kind == "sticky" or kind == "timed" end
    self.close:SetShown(closable and true or false)
    local hasTime = d.duration and d.remaining
    self.time:SetShown(hasTime and kind ~= "timed" and true or false)
    -- the titles' width: what's left of the head
    local right = (closable and 22 + S["space-3"] or 0) + ((hasTime and kind ~= "timed") and 36 or 0)
    local textW = WIDTH - PAD * 2 - ICON - S["space-4"] - right
    self.title:SetWidth(textW)
    self.category:SetWidth(textW)
    local titleH = math.max(T.type.label.lineHeight, math.ceil(self.title:GetStringHeight()))
    local catH = self.category:IsShown() and T.type.caption.lineHeight or 0
    local headH = math.max(ICON, catH + titleH)
    self.head:SetHeight(headH)
    -- category over title, the two centred on the icon's height
    local top = math.max(0, (headH - catH - titleH) / 2)
    local x = ICON + S["space-4"]
    self.category:ClearAllPoints()
    self.category:SetPoint("TOPLEFT", x, -top)
    self.title:ClearAllPoints()
    self.title:SetPoint("TOPLEFT", x, -(top + catH))
    -- the time: left of the close button, or at the right edge
    self.time:ClearAllPoints()
    if closable then self.time:SetPoint("RIGHT", self.close, "LEFT", -S["space-3"], 0)
    else self.time:SetPoint("TOPRIGHT", 0, -(headH - T.type.numeric.lineHeight) / 2) end
    local y = PAD + headH
    local function place(f, h)
        y = y + S["space-3"]
        f:ClearAllPoints()
        f:SetPoint("TOPLEFT", PAD, -y)
        f:SetPoint("TOPRIGHT", -PAD, -y)
        f:SetHeight(h)
        f:Show()
        y = y + h
    end
    -- body
    if d.body and d.body ~= "" then
        self.body:SetWidth(WIDTH - PAD * 2)
        self.body:SetValue(d.body)
        local h = math.ceil(self.body:GetStringHeight())
        self.bodyRow:SetHeight(h)
        self.bodyRow:EnableMouse(d.bodyTooltip ~= nil)
        place(self.bodyRow, h)
    else
        self.bodyRow:Hide()
    end
    -- the item
    if d.item then
        self.item:SetArt(d.item.icon)
        self.item:SetBorder(d.item.quality and ("quality-" .. d.item.quality) or "gilt-hairline")
        self.itemLabel:SetValue(d.item.label or "")
        self.itemLabel:SetColor(d.item.quality and ("quality-" .. d.item.quality) or "ink")
        place(self.itemRow, 28)
    else
        self.itemRow:Hide()
    end
    -- the confirm field
    if d.confirmText then
        self.confirmLabel:SetValue("Type " .. d.confirmText .. " to confirm")
        place(self.confirmRow, T.type.caption.lineHeight + S["space-2"] + FIELD_H)
    else
        self.confirmRow:Hide()
    end
    -- what makes it go
    if d["until"] then
        self.untilText:SetValue(d["until"])
        place(self.untilRow, T.type.caption.lineHeight)
    else
        self.untilRow:Hide()
    end
    -- actions
    for _, pool in pairs(self.buttons) do
        for _, b in ipairs(pool) do b:Hide() end
    end
    local actions = d.actions or {}
    if d.host and d.host.buttons and d.host.buttons > 0 then
        place(self.actionsRow, ACTION_H)
    elseif #actions > 0 then
        place(self.actionsRow, ACTION_H)
        local x = 0
        for i = #actions, 1, -1 do
            local a = actions[i]
            local b = noteButton(self, i, a.variant or "quiet")
            -- a count after the label: how many chose it (a loot roll's votes)
            local text = a.label or ""
            if a.count then
                text = text .. "  |cff" .. T.color[a.count > 0 and "ink-muted" or "ink-faint"].hex .. a.count .. "|r"
            end
            b:SetLabel(text)
            b.pressed = a.pressed and true or false
            b.pressedBg:SetShown(b.pressed)
            if b.variant ~= "primary" then b.border:SetColor(b.pressed and "arcane" or (a.variant == "danger" and "ember" or "gilt-line")) end
            b.label:SetColor(b.pressed and "arcane" or (b.variant == "primary" and "on-signal" or (a.variant == "danger" and "ember-text" or "ink")))
            b:SetEnabledState(not a.disabled or b.pressed)
            b.tooltip = a.tooltip
            b:SetScript("OnClick", function() if a.onClick and not a.disabled then a.onClick(self) end end)
            b:ClearAllPoints()
            b:SetPoint("RIGHT", -x, 0)
            b:Show()
            x = x + b:GetWidth() + S["space-3"]
        end
    else
        self.actionsRow:Hide()
    end
    y = y + PAD
    self:SetHeight(y)
    -- the drain
    self.drain:SetShown(hasTime and true or false)
    self.drain:SetColorTexture(UI.RGBA(kind == "timed" and "gilt-line" or "ink-muted"))
    if hasTime then self:SetRemaining(d.remaining) end
    return y
end

function Note:SetRemaining(remaining)
    local d = self.data
    if not d or not d.duration then return end
    d.remaining = remaining
    local frac = math.max(0, math.min(1, remaining / math.max(0.01, d.duration)))
    self.drain:SetWidth(math.max(0.01, (WIDTH - 2) * frac))
    local soon = (d.kind or "timed") ~= "timed" and remaining <= (d.soonAt or 10)
    self.time:SetValue(clock(remaining))
    self.time:SetColor(soon and "amber" or "ink-muted")
    if soon then self.drain:SetColorTexture(UI.RGBA("amber")) end
end

function UI.Notification(parent)
    local n = CreateFrame("Frame", nil, parent)
    Mixin(n, Note)
    n:SetSize(WIDTH, 80)
    n.buttons = {}
    UI.Fill(n, "surface-glass", "BACKGROUND"):SetAllPoints()
    n.border = UI.Border(n, "gilt-line")
    UI.Shadow(n, "shadow-panel")
    n:EnableMouse(true)

    n.head = CreateFrame("Frame", nil, n)
    n.head:SetPoint("TOPLEFT", PAD, -PAD)
    n.head:SetPoint("TOPRIGHT", -PAD, -PAD)
    n.head:SetHeight(ICON)
    n.icon = CreateFrame("Frame", nil, n.head)
    n.icon:SetSize(ICON, ICON)
    UI.Fill(n.icon, "surface-sunk"):SetAllPoints()
    UI.Border(n.icon, "gilt-hairline", { layer = "OVERLAY" })
    n.iconArt = n.icon:CreateTexture(nil, "ARTWORK")
    -- icon.tooltip(owner): what hovering the icon shows (an item's tooltip)
    n.icon:EnableMouse(true)
    n.icon:SetScript("OnEnter", function(self) if n.iconTip then n.iconTip(self) end end)
    n.icon:SetScript("OnLeave", function() if n.iconTip then GameTooltip:Hide() end end)
    n.icon:SetPoint("TOPLEFT")
    n.category = UI.Text(n.head, "caption", "ink-muted")
    n.category:SetJustifyH("LEFT")
    n.title = UI.Text(n.head, "label", "ink")
    n.title:SetJustifyH("LEFT")
    n.title:SetWordWrap(true)
    n.time = UI.Text(n.head, "numeric", "ink-muted")
    n.close = UI.CloseButton(n.head, function()
        local d = n.data
        if d and d.onClose then d.onClose(n) end
    end)
    n.close:SetPoint("TOPRIGHT")

    n.bodyRow = CreateFrame("Frame", nil, n)
    n.body = UI.Text(n.bodyRow, "caption", "ink-muted")
    n.body:SetJustifyH("LEFT")
    n.body:SetWordWrap(true)
    n.body:SetPoint("TOPLEFT")
    -- bodyTooltip: what hovering the body shows (everyone still choosing)
    n.bodyRow:SetScript("OnEnter", function(self) if n.data and n.data.bodyTooltip then UI.ShowTooltip(self, n.data.bodyTooltip) end end)
    n.bodyRow:SetScript("OnLeave", function() UI.HideTooltip() end)

    n.itemRow = CreateFrame("Frame", nil, n)
    n.item = UI.Icon(n.itemRow, 28)
    n.item:SetPoint("LEFT")
    n.itemLabel = UI.Text(n.itemRow, "label", "ink")
    n.itemLabel:SetPoint("LEFT", n.item, "RIGHT", S["space-4"], 0)

    n.confirmRow = CreateFrame("Frame", nil, n)
    n.confirmLabel = UI.Text(n.confirmRow, "caption", "ink-muted")
    n.confirmLabel:SetPoint("TOPLEFT")
    -- the field a hosted edit box sits on
    n.confirmBox = CreateFrame("Frame", nil, n.confirmRow)
    n.confirmBox:SetPoint("BOTTOMLEFT")
    n.confirmBox:SetPoint("BOTTOMRIGHT")
    n.confirmBox:SetHeight(FIELD_H)
    UI.Fill(n.confirmBox, "surface-sunk", "BACKGROUND"):SetAllPoints()
    n.confirmBox.edge = UI.Border(n.confirmBox, "gilt-line")

    n.untilRow = CreateFrame("Frame", nil, n)
    n.untilGlyph = n.untilRow:CreateTexture(nil, "ARTWORK")
    n.untilGlyph:SetTexture(GLYPHS .. "hourglass.tga")
    n.untilGlyph:SetVertexColor(UI.RGBA("ink-muted"))
    n.untilGlyph:SetSize(11, 11)
    n.untilGlyph:SetPoint("LEFT")
    n.untilText = UI.Text(n.untilRow, "caption", "ink-muted")
    n.untilText:SetPoint("LEFT", n.untilGlyph, "RIGHT", S["space-2"], 0)

    n.actionsRow = CreateFrame("Frame", nil, n)

    -- presence: the status diamond, where they're from (offline), the names
    n.status = UI.Diamond(n.head, 6, "arcane")
    n.status:Hide()
    n.source = UI.Text(n.head, "caption", "ink-faint")
    n.source:Hide()
    n.namesRow = CreateFrame("Frame", nil, n)
    n.namesRow:Hide()
    n.names = {}
    n:SetScript("OnMouseUp", function(self, button)
        if button == "LeftButton" and self.onCardClick then self.onCardClick() end
    end)

    n.drain = n:CreateTexture(nil, "OVERLAY")
    n.drain:SetPoint("BOTTOMLEFT", 1, 1)
    n.drain:SetHeight(2)
    n.drain:Hide()
    return n
end

--------------------------------------------------------------------------------
-- The stack
--------------------------------------------------------------------------------

local ORDER = { action = 0, roll = 0, ["until"] = 1, sticky = 2, timed = 3 }

local Stack = {}

-- Notes out of sight (a window covers them), requests kept.
function Stack:SetNotesHidden(on)
    on = on and true or false
    if self.notesHidden == on then return end
    self.notesHidden = on
    for _, card in pairs(self.cards) do
        if card.data then card:SetShown(card.request or not on) end
    end
    self.foot:SetAlpha(on and 0 or 1)
end

function Stack:CardFor(id)
    return self.cards[id]
end

function Stack:SetItems(items, inCombat)
    local list, held = {}, 0
    for i, d in ipairs(items or {}) do
        local kind = d.kind or "timed"
        if inCombat and (kind == "sticky" or kind == "timed") then
            held = held + 1
        else
            list[#list + 1] = { d = d, i = i }
        end
    end
    table.sort(list, function(a, b)
        local oa, ob = ORDER[a.d.kind or "timed"] or 3, ORDER[b.d.kind or "timed"] or 3
        if oa ~= ob then return oa < ob end
        return a.i < b.i
    end)
    local max = self.expanded and #list or math.min(#list, self.max)
    local used = {}
    local y = 0
    for k = 1, max do
        local d = list[k].d
        local card = self.cards[d.id]
        if not card then
            card = table.remove(self.spare) or UI.Notification(self)
            self.cards[d.id] = card
        end
        used[d.id] = true
        -- requests (popups to answer, loot rolls) above open windows; notes
        -- at the stack's own layer, under them (asked for in game)
        local request = d.kind == "action" or d.kind == "roll"
        card.request = request
        card:SetFrameStrata(request and "DIALOG" or self:GetFrameStrata())
        card:SetData(d)
        card:ClearAllPoints()
        card:SetPoint("TOPLEFT", 0, -y)
        card:SetShown(request or not self.notesHidden)
        y = y + card:GetHeight() + S["space-3"]
    end
    for id, card in pairs(self.cards) do
        if not used[id] then
            card:Hide()
            card.data = nil
            self.cards[id] = nil
            self.spare[#self.spare + 1] = card
        end
    end
    -- the foot: more, held in combat, dismiss all
    local more = #list - max
    local sticky = 0
    for _, x in ipairs(list) do if (x.d.kind or "timed") == "sticky" then sticky = sticky + 1 end end
    self.moreLink:SetShown(more > 0)
    self.moreLink.label:SetValue("+" .. more .. " more")
    self.heldText:SetShown(held > 0)
    self.heldText:SetValue(held .. " waiting for the end of combat")
    self.clearLink:SetShown(sticky > 1 and not inCombat)
    local footShown = more > 0 or held > 0 or (sticky > 1 and not inCombat)
    self.foot:SetShown(footShown)
    if footShown then
        self.foot:ClearAllPoints()
        self.foot:SetPoint("TOPLEFT", S["space-2"], -y)
        self.foot:SetPoint("TOPRIGHT", -S["space-2"], -y)
        local x = 0
        for _, f in ipairs({ self.moreLink, self.heldText }) do
            if f:IsShown() then
                f:ClearAllPoints()
                f:SetPoint("LEFT", x, 0)
                x = x + (f.GetUnboundedStringWidth and f:GetUnboundedStringWidth() or f:GetWidth()) + S["space-4"]
            end
        end
        y = y + T.type.caption.lineHeight
    end
    self:SetHeight(math.max(1, y))
end

local function link(parent, text, onClick)
    local b = CreateFrame("Button", nil, parent)
    b.label = UI.Text(b, "caption", "gilt-text")
    b.label:SetPoint("LEFT")
    b.label:SetValue(text)
    b:SetSize(80, T.type.caption.lineHeight)
    b:SetScript("OnClick", onClick)
    b:SetScript("OnEnter", function(self) self.label:SetColor("ink") end)
    b:SetScript("OnLeave", function(self) self.label:SetColor("gilt-text") end)
    hooksecurefunc(b.label, "SetValue", function() b:SetWidth(b.label:GetUnboundedStringWidth() + 2) end)
    return b
end

function UI.NotificationStack(parent, opts)
    opts = opts or {}
    local s = CreateFrame("Frame", opts.name, parent)
    Mixin(s, Stack)
    s:SetSize(WIDTH, 1)
    s.max = opts.max or 5
    s.cards, s.spare = {}, {}
    s.foot = CreateFrame("Frame", nil, s)
    s.foot:SetHeight(T.type.caption.lineHeight)
    s.moreLink = link(s.foot, "+1 more", function()
        s.expanded = true
        if s.onExpand then s.onExpand() end
    end)
    s.heldText = UI.Text(s.foot, "caption", "ink-muted")
    s.clearLink = link(s.foot, "Dismiss all", function() if s.onClearAll then s.onClearAll() end end)
    s.clearLink:SetPoint("RIGHT")
    s.foot:Hide()
    return s
end
