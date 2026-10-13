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
--               duration, remaining, soonAt, ["until"], item = { icon,
--               label, quality }, confirmText, actions = { { label,
--               variant = "primary"|"quiet"|"danger", onClick,
--               count, pressed, disabled, tooltip } },
--               host = { buttons = n, confirm = true }, closable, onClose })
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
        art:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        art:ClearAllPoints()
        art:SetPoint("TOPLEFT", 1, -1)
        art:SetPoint("BOTTOMRIGHT", -1, 1)
        art:SetVertexColor(1, 1, 1, 1)
    end
end

function Note:SetTitle(text)
    self.title:SetValue(text or "")
end

function Note:SetData(d)
    self.data = d
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
        card:SetData(d)
        card:ClearAllPoints()
        card:SetPoint("TOPLEFT", 0, -y)
        card:Show()
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
