-- UI/Legacy.lua
-- The Legacy window's pages (design boards "Legacy · Tree / Challenges /
-- Reward track"): Forever's account progression.
--
--   UI.LegacyPoints(parent):SetPoints({ earned, total, spent, cap, pending, character })
--     "Legacy points · account  16 of 81 earned", "Spent on Veyra  9 of 16"
--     (the design's pips left out: the numbers say it, asked for in game)
--   UI.LegacyChallenges(parent):SetCategories(list)
--     list = { { name, done, total, items = { item }, groups = { { name, items } } } }
--     item = { name, done, progress ("45/150"), points, onEnter(owner), onLeave() }
--     six cards, three to a row: a category's done/total, its bar and the
--     challenges you're closest to (up to five); a card opens its full list
--     (scrolling, by sub-category), "All challenges" goes back
--   UI.LegacyTrack(parent):SetTrack({ earned, total, max, next, stops = { stop } })
--     stop = { at, name, icon, quality, collected, onEnter(owner), onLeave() }
--     a strip for the window's foot: the account's points and the rewards

local _, ns = ...

local UI, T = ns.UI, ns.Tokens
local S = T.space

local GLYPHS = "Interface\\AddOns\\SuuUI\\Media\\Textures\\Glyphs\\"
local function hex(token) return T.color[token].hex end

-- Big tabular figures (the design's 20px numbers).
local function bigNumber(parent)
    local fs = UI.Text(parent, "numeric", "ink")
    local spec = T.type.numeric
    fs:SetFont(spec.file, 20, "")
    return fs
end

--------------------------------------------------------------------------------
-- The points
--------------------------------------------------------------------------------

local Points = {}

local function block(f, caption)
    local b = CreateFrame("Frame", nil, f)
    b.caption = UI.Text(b, "caption", "ink-muted")
    b.caption:SetPoint("TOPLEFT")
    b.caption:SetValue(caption)
    b.big = bigNumber(b)
    b.big:SetPoint("TOPLEFT", b.caption, "BOTTOMLEFT", 0, -1)
    b.rest = UI.Text(b, "caption", "ink-muted")
    b.rest:SetPoint("BOTTOMLEFT", b.big, "BOTTOMRIGHT", 0, 3)
    b:SetHeight(T.type.caption.lineHeight + 1 + 24)
    return b
end

function Points:SetPoints(d)
    d = d or {}
    local earned, total = d.earned or 0, d.total or 0
    local spent, cap, pending = d.spent or 0, d.cap or 0, d.pending or 0
    self.account.big:SetText(tostring(earned))
    self.account.rest:SetText(" of " .. total .. " earned")
    self.char.caption:SetValue("Spent on " .. (d.character or "this character"))
    self.char.big:SetText(tostring(spent))
    self.char.rest:SetText(" of " .. cap .. (pending > 0 and ("|cff" .. hex("arcane") .. " · " .. pending .. " not applied|r") or ""))
    local w = math.max(self.account.caption:GetUnboundedStringWidth(),
        self.account.big:GetUnboundedStringWidth() + self.account.rest:GetUnboundedStringWidth())
    self.account:SetWidth(math.ceil(w) + 2)
end

-- opts.account = false: this character's points only (the account's are
-- on the track at the window's foot)
function UI.LegacyPoints(parent, opts)
    local f = CreateFrame("Frame", nil, parent)
    Mixin(f, Points)
    f.account = block(f, "Legacy points · account")
    f.account:SetPoint("TOPLEFT")
    f.char = block(f, "Spent on this character")
    if opts and opts.account == false then
        f.account:Hide()
        f.char:SetPoint("TOPLEFT")
    else
        f.char:SetPoint("TOPLEFT", f.account, "TOPRIGHT", S["space-6"], 0)
    end
    f.char:SetWidth(200)
    f:SetHeight(f.account:GetHeight())
    return f
end

--------------------------------------------------------------------------------
-- A challenge row: a check (done) or a bullet, the name, its progress, its
-- Legacy points
--------------------------------------------------------------------------------

local ROW_H = T.type.body.lineHeight + 2

local function makeRow(parent)
    local r = CreateFrame("Frame", nil, parent)
    r:SetHeight(ROW_H)
    r:EnableMouse(true)
    r.check = r:CreateTexture(nil, "ARTWORK")
    r.check:SetTexture(GLYPHS .. "check.tga")
    r.check:SetSize(11, 11)
    r.check:SetPoint("LEFT", 0, 0)
    r.check:SetVertexColor(UI.RGBA("ink-muted"))
    r.bullet = UI.Diamond(r, 4, "ink-muted", "ARTWORK", 1)
    r.bullet:SetPoint("CENTER", r, "LEFT", 5, 0)
    r.worth = UI.Text(r, "caption", "ink-muted")
    r.worth:SetPoint("RIGHT", r, "RIGHT", 0, 0)
    r.progress = UI.Text(r, "numeric", "ink")
    r.progress:SetPoint("RIGHT", r.worth, "LEFT", -S["space-3"], 0)
    r.name = UI.Text(r, "body", "ink")
    r.name:SetPoint("LEFT", r, "LEFT", 12 + S["space-3"], 0)
    r.name:SetPoint("RIGHT", r.progress, "LEFT", -S["space-3"], 0)
    r.name:SetJustifyH("LEFT")
    r:SetScript("OnEnter", function(self) if self.item and self.item.onEnter then self.item.onEnter(self) end end)
    r:SetScript("OnLeave", function(self) if self.item and self.item.onLeave then self.item.onLeave() end end)
    return r
end

local function fillRow(r, item)
    r.item = item
    r.check:SetShown(item.done and true or false)
    r.bullet:SetShown(not item.done)
    r.name:SetValue(item.name or "")
    r.name:SetColor(item.done and "ink-muted" or "ink")
    r.progress:SetValue(item.progress or "")
    r.worth:SetValue(item.points and ("+" .. item.points) or "")
end

--------------------------------------------------------------------------------
-- Challenges
--------------------------------------------------------------------------------

local Challenges = {}
local CARD_ROWS = 5
local COLS = 3

local function cardHeight()
    return S["space-4"] * 2 + T.type.header.lineHeight + S["space-3"] + 6 + S["space-3"]
        + CARD_ROWS * (ROW_H + S["space-2"]) + T.type.caption.lineHeight
end
UI.LEGACY_CARD_H = cardHeight()

local function makeCard(view)
    local c = CreateFrame("Button", nil, view.grid)
    UI.Fill(c, "surface-sunk"):SetAllPoints()
    c.border = UI.Border(c, "gilt-faint")
    c.name = UI.Text(c, "header", "gilt-text")
    c.name:SetPoint("TOPLEFT", S["space-4"], -S["space-4"])
    c.count = UI.Text(c, "caption", "ink-muted")
    c.count:SetPoint("TOPRIGHT", -S["space-4"], -S["space-4"] - 2)
    c.track = UI.Fill(c, "track", "ARTWORK")
    c.track:SetHeight(6)
    c.track:SetPoint("TOPLEFT", c.name, "BOTTOMLEFT", 0, -S["space-3"])
    c.track:SetPoint("RIGHT", c, "RIGHT", -S["space-4"], 0)
    c.fill = UI.Fill(c, "progress-fill", "ARTWORK", 1)
    c.fill:SetHeight(6)
    c.fill:SetPoint("TOPLEFT", c.track, "TOPLEFT")
    c.rows = {}
    c.all = UI.Text(c, "caption", "gilt-text")
    c.all:SetPoint("BOTTOMLEFT", S["space-4"], S["space-4"])
    c:SetScript("OnEnter", function(self) self.border:SetColor("gilt-line") end)
    c:SetScript("OnLeave", function(self) self.border:SetColor("gilt-faint") end)
    c:SetScript("OnClick", function(self) view:Open(self.index) end)
    return c
end

function Challenges:Layout()
    local w = self:GetWidth()
    if not w or w <= 0 then return end
    local gap = S["space-5"]
    local cw = math.floor((w - gap * (COLS - 1)) / COLS)
    local ch = cardHeight()
    for i, c in ipairs(self.cards) do
        local col, row = (i - 1) % COLS, math.floor((i - 1) / COLS)
        c:ClearAllPoints()
        c:SetPoint("TOPLEFT", self.grid, "TOPLEFT", col * (cw + gap), -row * (ch + gap))
        c:SetSize(cw, ch)
        -- the bar as far as done of total
        local d = c.data
        local frac = (d and d.total and d.total > 0) and (d.done / d.total) or 0
        local trackW = cw - S["space-4"] * 2
        c.fill:SetWidth(math.max(0.01, trackW * math.min(1, frac)))
        c.fill:SetShown(frac > 0)
    end
end

function Challenges:SetCategories(list)
    self.list = list or {}
    for i, d in ipairs(self.list) do
        local c = self.cards[i] or makeCard(self)
        self.cards[i] = c
        c.index, c.data = i, d
        c.name:SetValue(d.name or "")
        c.count:SetValue((d.done or 0) .. "/" .. (d.total or 0))
        for k = 1, CARD_ROWS do
            local item = d.items and d.items[k]
            local r = c.rows[k]
            if item then
                if not r then
                    r = makeRow(c)
                    c.rows[k] = r
                    r:SetPoint("TOPLEFT", c.track, "BOTTOMLEFT", 0, -S["space-3"] - (k - 1) * (ROW_H + S["space-2"]))
                    r:SetPoint("RIGHT", c, "RIGHT", -S["space-4"], 0)
                end
                fillRow(r, item)
                r:Show()
            elseif r then
                r:Hide()
            end
        end
        local more = (d.total or 0) - math.min(CARD_ROWS, #(d.items or {}))
        c.all:SetValue(more > 0 and ("All " .. d.total .. " challenges") or "")
        c:Show()
    end
    for i = #self.list + 1, #self.cards do self.cards[i]:Hide() end
    self:Layout()
    if self.openIndex then self:Open(self.openIndex) end
end

-- One category's full list, by sub-category.
function Challenges:Open(i)
    local d = self.list[i]
    if not d then return self:Close() end
    self.openIndex = i
    self.grid:Hide()
    self.detail:Show()
    self.detailTitle:SetValue(d.name or "")
    self.detailCount:SetValue((d.done or 0) .. "/" .. (d.total or 0))
    local child = self.scroll.child
    child:SetWidth(math.max(1, self.scroll:GetWidth()))
    local y, n = 0, 0
    for _, h in ipairs(self.heads) do h:Hide() end
    for _, r in ipairs(self.detailRows) do r:Hide() end
    local hi = 0
    for _, g in ipairs(d.groups or {}) do
        if g.name and g.name ~= "" and #(d.groups) > 1 then
            hi = hi + 1
            local h = self.heads[hi]
            if not h then
                h = UI.Text(child, "label", "gilt-text")
                self.heads[hi] = h
            end
            h:ClearAllPoints()
            h:SetPoint("TOPLEFT", child, "TOPLEFT", 0, -y - (y > 0 and S["space-4"] or 0))
            h:SetValue(g.name .. "  |cff" .. hex("ink-muted") .. g.done .. "/" .. #g.items .. "|r")
            h:Show()
            y = y + (y > 0 and S["space-4"] or 0) + T.type.label.lineHeight + S["space-2"]
        end
        for _, item in ipairs(g.items) do
            n = n + 1
            local r = self.detailRows[n]
            if not r then
                r = makeRow(child)
                self.detailRows[n] = r
            end
            r:ClearAllPoints()
            r:SetPoint("TOPLEFT", child, "TOPLEFT", 0, -y)
            r:SetPoint("RIGHT", child, "RIGHT", -S["space-5"], 0)
            fillRow(r, item)
            r:Show()
            y = y + ROW_H + S["space-2"]
        end
    end
    child:SetHeight(math.max(1, y))
end

function Challenges:Close()
    self.openIndex = nil
    self.detail:Hide()
    self.grid:Show()
end

function UI.LegacyChallenges(parent)
    local f = CreateFrame("Frame", nil, parent)
    Mixin(f, Challenges)
    f.cards, f.heads, f.detailRows = {}, {}, {}
    f.grid = CreateFrame("Frame", nil, f)
    f.grid:SetAllPoints()
    -- the full list of one category
    f.detail = CreateFrame("Frame", nil, f)
    f.detail:SetAllPoints()
    f.detail:Hide()
    f.back = CreateFrame("Button", nil, f.detail)
    f.back.label = UI.Text(f.back, "caption", "gilt-text")
    f.back.label:SetPoint("LEFT", 14, 0)
    f.back.label:SetValue("All challenges")
    f.back.glyph = f.back:CreateTexture(nil, "ARTWORK")
    f.back.glyph:SetTexture(GLYPHS .. "chevronLeft.tga")
    f.back.glyph:SetSize(10, 10)
    f.back.glyph:SetPoint("LEFT")
    f.back.glyph:SetVertexColor(UI.RGBA("gilt-text"))
    f.back:SetSize(120, T.type.caption.lineHeight)
    f.back:SetPoint("TOPLEFT")
    f.back:SetScript("OnClick", function() f:Close() end)
    f.back:SetScript("OnEnter", function(self) self.label:SetColor("ink") end)
    f.back:SetScript("OnLeave", function(self) self.label:SetColor("gilt-text") end)
    f.detailTitle = UI.Text(f.detail, "header", "gilt-text")
    f.detailTitle:SetPoint("TOPLEFT", f.back, "BOTTOMLEFT", 0, -S["space-4"])
    f.detailCount = UI.Text(f.detail, "caption", "ink-muted")
    f.detailCount:SetPoint("LEFT", f.detailTitle, "RIGHT", S["space-4"], 0)
    f.scroll = UI.ScrollArea(f.detail, 6)
    f.scroll:SetPoint("TOPLEFT", f.detailTitle, "BOTTOMLEFT", 0, -S["space-5"])
    f.scroll:SetPoint("BOTTOMRIGHT", f.detail, "BOTTOMRIGHT", -10, 0)
    f:SetScript("OnSizeChanged", function() f:Layout() end)
    return f
end

--------------------------------------------------------------------------------
-- The reward track: a strip along the window's foot (asked for in game, in
-- place of its own tab): the account's points on the left, then the bar
-- with a diamond at each reward's level, the reward's icon above it (dim
-- until reached, a check once collected) and the level under it; the next
-- reward under the bar. Names are in the icons' tooltips.
--------------------------------------------------------------------------------

local Track = {}
local ICON = 24
local LEFT_W = 150
local TRACK_TOP = ICON + S["space-3"]
UI.LEGACY_TRACK_H = TRACK_TOP + 6 + S["space-3"] + T.type.numeric.lineHeight + S["space-2"] + T.type.caption.lineHeight

function Track:SetTrack(d)
    d = d or {}
    self.data = d
    local stops = d.stops or {}
    local max = (d.max and d.max > 0) and d.max or 1
    local earned = d.earned or 0
    self.points.big:SetText(tostring(earned))
    self.points.rest:SetText(" of " .. (d.total or 0) .. " earned")
    local w = self:GetWidth()
    if not w or w <= 0 then w = 800 end
    local left = LEFT_W + ICON / 2
    local inner = math.max(10, w - left - ICON / 2 - 4)
    self.bar:ClearAllPoints()
    self.bar:SetPoint("TOPLEFT", self, "TOPLEFT", left, -TRACK_TOP)
    self.bar:SetWidth(inner)
    self.fill:SetWidth(math.max(0.01, inner * math.min(1, earned / max)))
    self.fill:SetShown(earned > 0)
    for i, s in ipairs(stops) do
        local st = self.stops[i]
        if not st then
            st = CreateFrame("Frame", nil, self)
            st:SetSize(ICON, UI.LEGACY_TRACK_H)
            st.slot = UI.ItemSlot(st, ICON)
            st.slot:SetPoint("TOP", st, "TOP", 0, 0)
            st.slot:SetScript("OnEnter", function(b) if b.stop and b.stop.onEnter then b.stop.onEnter(b) end end)
            st.slot:SetScript("OnLeave", function(b) if b.stop and b.stop.onLeave then b.stop.onLeave() end end)
            st.over = CreateFrame("Frame", nil, st.slot)
            st.over:SetAllPoints()
            st.over:SetFrameLevel(st.slot:GetFrameLevel() + 5)
            st.check = st.over:CreateTexture(nil, "OVERLAY", nil, 7)
            st.check:SetTexture(GLYPHS .. "check.tga")
            st.check:SetSize(10, 10)
            st.check:SetPoint("TOPRIGHT", st.slot, "TOPRIGHT", 3, 3)
            st.check:SetVertexColor(UI.RGBA("fel"))
            st.mark = UI.Diamond(st, 9, "gilt-line", "OVERLAY", 3)
            st.mark:SetPoint("CENTER", st, "TOP", 0, -(TRACK_TOP + 3))
            st.at = UI.Text(st, "numeric", "ink-muted")
            st.at:SetPoint("TOP", st, "TOP", 0, -(TRACK_TOP + 6 + S["space-3"]))
            self.stops[i] = st
        end
        local got = earned >= (s.at or 0)
        st.slot.stop = s
        st.slot.skin:SetItem({ icon = s.icon, quality = s.quality, dim = not got })
        st.mark:SetVertexColor(UI.RGBA(got and "gilt" or "gilt-line"))
        st.at:SetValue(tostring(s.at or 0))
        st.at:SetColor(got and "gilt-text" or "ink-muted")
        st.check:SetShown(s.collected and true or false)
        st:ClearAllPoints()
        st:SetPoint("TOP", self, "TOPLEFT", left + inner * math.min(1, (s.at or 0) / max), 0)
        st:Show()
    end
    for i = #stops + 1, #self.stops do self.stops[i]:Hide() end
    self.next:SetValue(d.next or "")
end

function UI.LegacyTrack(parent)
    local f = CreateFrame("Frame", nil, parent)
    Mixin(f, Track)
    f:SetHeight(UI.LEGACY_TRACK_H)
    f.stops = {}
    -- the account's points
    f.points = block(f, "Legacy · account")
    f.points:SetPoint("TOPLEFT", f, "TOPLEFT", 0, -(TRACK_TOP - 18))
    f.points:SetWidth(LEFT_W - 8)
    f.bar = UI.Fill(f, "track", "ARTWORK")
    f.bar:SetHeight(6)
    f.fill = UI.Fill(f, "progress-fill", "ARTWORK", 1)
    f.fill:SetHeight(6)
    f.fill:SetPoint("TOPLEFT", f.bar, "TOPLEFT")
    f.next = UI.Text(f, "caption", "ink-muted")
    f.next:SetPoint("BOTTOM", f, "BOTTOM", LEFT_W / 2, 0)
    f:SetScript("OnSizeChanged", function() if f.data then f:SetTrack(f.data) end end)
    return f
end
