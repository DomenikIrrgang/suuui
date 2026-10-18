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
--     stop = { at, icon, quality, collected, onEnter(owner), onLeave() }
--       (its name goes in the tooltip onEnter shows)
--     a strip for the window's foot: the account's points and the rewards

local _, ns = ...

local UI, T = ns.UI, ns.Tokens
local S = T.space

local GLYPHS = "Interface\\AddOns\\SuuUI\\Media\\Textures\\Glyphs\\"
local function hex(token) return T.color[token].hex end
local live = setmetatable({}, { __mode = "k" }) -- built pages -> "points", "challenges", "track"

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

local function blockHeight() return T.type.caption.lineHeight + 1 + 24 end

local function block(f, caption)
    local b = CreateFrame("Frame", nil, f)
    b.caption = UI.Text(b, "caption", "ink-muted")
    b.caption:SetPoint("TOPLEFT")
    b.caption:SetValue(caption)
    b.big = bigNumber(b)
    b.big:SetPoint("TOPLEFT", b.caption, "BOTTOMLEFT", 0, -1)
    b.rest = UI.Text(b, "caption", "ink-muted")
    b.rest:SetPoint("BOTTOMLEFT", b.big, "BOTTOMRIGHT", 0, 3)
    b:SetHeight(blockHeight())
    return b
end

-- after a theme change: the caption's height and the numbers' face
local function restyleBlock(b)
    b:SetHeight(blockHeight())
    b.big:SetFont(T.type.numeric.file, 20, "")
end

function Points:SetPoints(d)
    d = d or {}
    self.data = d
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
    live[f] = "points"
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
    UI.Paint(r.check, "ink-muted")
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
    -- a refresh (progress changed) keeps the open list where it was scrolled
    if self.openIndex then self:Open(self.openIndex, true) end
end

--------------------------------------------------------------------------------
-- One category's full list (asked for in game: groups you can't miss, real
-- progress, a back button you can't miss): a bar with "All challenges", the
-- category and its progress; each sub-category its own panel (small ones two
-- to a row); a challenge with steps opens to show each step done or to do.
--------------------------------------------------------------------------------

local BAR_W = 64      -- a challenge's progress bar
local STEP_W = 168    -- a step's column
local STEP_H = T.type.body.lineHeight
local INDENT = 12 + S["space-3"]

-- a thin bar: track and fill
local function thinBar(parent, h)
    local b = CreateFrame("Frame", nil, parent)
    b:SetHeight(h or 3)
    b.track = UI.Fill(b, "track", "ARTWORK")
    b.track:SetAllPoints()
    b.fill = UI.Fill(b, "progress-fill", "ARTWORK", 1)
    b.fill:SetPoint("TOPLEFT")
    b.fill:SetPoint("BOTTOMLEFT")
    function b:SetFraction(f)
        f = math.max(0, math.min(1, f or 0))
        local w = self:GetWidth()
        self.fill:SetShown(f > 0 and w and w > 0)
        if w and w > 0 then self.fill:SetWidth(math.max(0.01, w * f)) end
        self.fraction = f
    end
    b:SetScript("OnSizeChanged", function(self) if self.fraction then self:SetFraction(self.fraction) end end)
    return b
end

-- a step: a check (done, muted) or a hollow diamond (to do, bright), its text
local function makeStep(parent)
    local c = CreateFrame("Frame", nil, parent)
    c:SetSize(STEP_W, STEP_H)
    c.check = c:CreateTexture(nil, "ARTWORK")
    c.check:SetTexture(GLYPHS .. "check.tga")
    c.check:SetSize(10, 10)
    c.check:SetPoint("LEFT", 0, 0)
    UI.Paint(c.check, "ink-muted")
    c.ring = UI.Diamond(c, 7, "gilt-line", "ARTWORK", 1)
    c.ring:SetPoint("CENTER", c, "LEFT", 5, 0)
    c.hole = UI.Diamond(c, 4, "surface-sunk", "ARTWORK", 2)
    c.hole:SetPoint("CENTER", c.ring, "CENTER")
    c.text = UI.Text(c, "body", "ink")
    c.text:SetPoint("LEFT", c, "LEFT", 16, 0)
    c.text:SetPoint("RIGHT", c, "RIGHT", -S["space-3"], 0)
    c.text:SetJustifyH("LEFT")
    return c
end

-- a challenge in a panel: open/closed chevron (with steps), check or bullet,
-- the name, its progress with a bar, its Legacy points
local function makeDetailRow(view, parent)
    local r = CreateFrame("Button", nil, parent)
    r:SetHeight(ROW_H + 2)
    r.hover = UI.Fill(r, "gilt-faint", "BACKGROUND", 1)
    r.hover:SetAllPoints()
    r.hover:Hide()
    r.chevron = r:CreateTexture(nil, "ARTWORK")
    r.chevron:SetSize(10, 10)
    r.chevron:SetPoint("LEFT", 0, 0)
    UI.Paint(r.chevron, "gilt-text")
    r.check = r:CreateTexture(nil, "ARTWORK")
    r.check:SetTexture(GLYPHS .. "check.tga")
    r.check:SetSize(11, 11)
    r.check:SetPoint("LEFT", 0, 0)
    UI.Paint(r.check, "ink-muted")
    r.bullet = UI.Diamond(r, 4, "ink-muted", "ARTWORK", 1)
    r.bullet:SetPoint("CENTER", r, "LEFT", 5, 0)
    r.worth = UI.Text(r, "caption", "gilt-text")
    r.worth:SetPoint("RIGHT", r, "RIGHT", -S["space-2"], 0)
    r.bar = thinBar(r, 3)
    r.bar:SetWidth(BAR_W)
    r.bar:SetPoint("RIGHT", r.worth, "LEFT", -S["space-5"], 0)
    r.progress = UI.Text(r, "numeric", "ink")
    r.progress:SetPoint("RIGHT", r.bar, "LEFT", -S["space-4"], 0)
    r.name = UI.Text(r, "body", "ink")
    r.name:SetPoint("LEFT", r, "LEFT", INDENT, 0)
    r.name:SetPoint("RIGHT", r.progress, "LEFT", -S["space-4"], 0)
    r.name:SetJustifyH("LEFT")
    r:SetScript("OnEnter", function(self)
        if self.item and self.item.stepsN then self.hover:Show() end
        if self.item and self.item.onEnter then self.item.onEnter(self) end
    end)
    r:SetScript("OnLeave", function(self)
        self.hover:Hide()
        if self.item and self.item.onLeave then self.item.onLeave() end
    end)
    r:SetScript("OnClick", function(self)
        local item = self.item
        if not (item and item.stepsN) then return end
        view.expanded[item.id] = not view.expanded[item.id]
        view:Open(view.openIndex, true)
    end)
    return r
end

local function fillDetailRow(view, r, item)
    r.item = item
    local steps = item.stepsN and item.stepsN > 1
    local open = steps and view.expanded[item.id]
    r.chevron:SetShown(steps and not item.done)
    r.chevron:SetTexture(GLYPHS .. (open and "chevronDown" or "chevronRight") .. ".tga")
    r.check:SetShown(item.done and true or false)
    r.bullet:SetShown(not item.done and not steps)
    r.name:SetValue(item.name or "")
    r.name:SetColor(item.done and "ink-muted" or "ink")
    -- progress: steps done, or the count
    local frac
    if item.done then
        r.progress:SetValue("")
    elseif steps then
        r.progress:SetValue((item.stepsDone or 0) .. "/" .. item.stepsN)
        frac = (item.stepsDone or 0) / item.stepsN
    elseif item.count then
        r.progress:SetValue(item.count[1] .. "/" .. item.count[2])
        frac = item.count[1] / item.count[2]
    else
        r.progress:SetValue("")
    end
    r.bar:SetShown(frac ~= nil)
    if frac then r.bar:SetFraction(frac) end
    r.worth:SetValue(item.points and ("+" .. item.points) or "")
    r.worth:SetColor(item.done and "ink-muted" or "gilt-text")
end

local PANEL_PAD = S["space-5"]
local PANEL_HEAD = T.type.header.lineHeight + S["space-3"] + 3 + S["space-4"]

local function makePanel(parent)
    local p = CreateFrame("Frame", nil, parent)
    UI.Fill(p, "surface-sunk"):SetAllPoints()
    UI.Border(p, "gilt-faint")
    p.name = UI.Text(p, "header", "gilt-text")
    p.name:SetPoint("TOPLEFT", PANEL_PAD, -PANEL_PAD)
    p.count = UI.Text(p, "caption", "ink-muted")
    p.count:SetPoint("TOPRIGHT", -PANEL_PAD, -PANEL_PAD - 2)
    p.bar = thinBar(p, 3)
    p.bar:SetPoint("TOPLEFT", p.name, "BOTTOMLEFT", 0, -S["space-3"])
    p.bar:SetPoint("RIGHT", p, "RIGHT", -PANEL_PAD, 0)
    p.rows, p.steps, p.subrows = {}, {}, {}
    return p
end

-- Open steps from x, y: steps that are achievements as rows (they open in
-- turn, one step further in), the others in columns; returns the new y.
function Challenges:LayoutSteps(p, list, x, y, width)
    local plainSteps = {}
    local function grid()
        if #plainSteps == 0 then return end
        local cols = math.max(1, math.floor(width / STEP_W))
        for n, step in ipairs(plainSteps) do
            p.stepIndex = p.stepIndex + 1
            local c = p.steps[p.stepIndex] or makeStep(p)
            p.steps[p.stepIndex] = c
            local col, row = (n - 1) % cols, math.floor((n - 1) / cols)
            c:ClearAllPoints()
            c:SetPoint("TOPLEFT", p, "TOPLEFT", x + col * STEP_W, -(y + S["space-1"] + row * STEP_H))
            c.check:SetShown(step.done and true or false)
            c.ring:SetShown(not step.done)
            c.hole:SetShown(not step.done)
            local label = step.text or ""
            if step.count then label = label .. "  |cff" .. hex("ink-muted") .. step.count[1] .. "/" .. step.count[2] .. "|r" end
            c.text:SetValue(label)
            c.text:SetColor(step.done and "ink-muted" or "ink")
            c:Show()
        end
        y = y + S["space-1"] + math.ceil(#plainSteps / cols) * STEP_H + S["space-3"]
        plainSteps = {}
    end
    for _, step in ipairs(list) do
        if step.steps then
            grid()
            p.subIndex = p.subIndex + 1
            local r = p.subrows[p.subIndex] or makeDetailRow(self, p)
            p.subrows[p.subIndex] = r
            r:ClearAllPoints()
            r:SetPoint("TOPLEFT", p, "TOPLEFT", x, -y)
            r:SetWidth(width)
            fillDetailRow(self, r, { id = step.id, name = step.text, done = step.done,
                stepsN = step.stepsN, stepsDone = step.stepsDone, steps = step.steps })
            r:Show()
            y = y + ROW_H + 2 + S["space-1"]
            if self.expanded[step.id] and not step.done then
                y = self:LayoutSteps(p, step.steps(), x + INDENT, y, width - INDENT)
            end
        else
            plainSteps[#plainSteps + 1] = step
        end
    end
    grid()
    return y
end

-- A panel's rows and open steps; returns its height.
local function fillPanel(view, p, g, width)
    p:SetWidth(width)
    p.name:SetValue(g.name ~= "" and g.name or view.list[view.openIndex].name)
    p.count:SetValue(g.done .. "/" .. #g.items)
    p.bar:SetFraction(#g.items > 0 and g.done / #g.items or 0)
    local y = PANEL_PAD + PANEL_HEAD
    local inner = width - PANEL_PAD * 2
    p.stepIndex, p.subIndex = 0, 0
    for k, item in ipairs(g.items) do
        local r = p.rows[k] or makeDetailRow(view, p)
        p.rows[k] = r
        r:ClearAllPoints()
        r:SetPoint("TOPLEFT", p, "TOPLEFT", PANEL_PAD, -y)
        r:SetWidth(inner)
        fillDetailRow(view, r, item)
        r:Show()
        y = y + ROW_H + 2 + S["space-1"]
        if item.stepsN and view.expanded[item.id] and item.steps then
            y = view:LayoutSteps(p, item.steps(), PANEL_PAD + INDENT, y, inner - INDENT)
        end
    end
    for k = #g.items + 1, #p.rows do p.rows[k]:Hide() end
    for k = p.stepIndex + 1, #p.steps do p.steps[k]:Hide() end
    for k = p.subIndex + 1, #p.subrows do p.subrows[k]:Hide() end
    local h = y + PANEL_PAD - S["space-1"]
    p:SetHeight(h)
    return h
end

function Challenges:Open(i, keep)
    local d = self.list[i]
    if not d then return self:Close() end
    self.openIndex = i
    self.grid:Hide()
    self.detail:Show()
    self.detailTitle:SetValue(d.name or "")
    self.detailCount:SetValue((d.done or 0) .. "/" .. (d.total or 0))
    self.detailBar:SetFraction((d.total or 0) > 0 and d.done / d.total or 0)
    local scroll = self.scroll
    local offset = keep and scroll:GetVerticalScroll() or 0
    local child = scroll.child
    local W = math.max(1, scroll:GetWidth() - S["space-5"])
    child:SetWidth(W)
    local gap = S["space-5"]
    local half = math.floor((W - gap) / 2)
    -- small groups two to a row, the rest the full width
    local y, k, pending = 0, 0, nil
    local function flush()
        if pending then y = y + pending + gap; pending = nil end
    end
    for _, g in ipairs(d.groups or {}) do
        k = k + 1
        local p = self.panels[k] or makePanel(child)
        self.panels[k] = p
        local wide = #g.items > 4
        for _, item in ipairs(g.items) do if item.stepsN and item.stepsN > 1 then wide = true end end
        p:ClearAllPoints()
        if wide then
            flush()
            local h = fillPanel(self, p, g, W)
            p:SetPoint("TOPLEFT", child, "TOPLEFT", 0, -y)
            y = y + h + gap
        elseif pending then
            local h = fillPanel(self, p, g, half)
            p:SetPoint("TOPLEFT", child, "TOPLEFT", half + gap, -y)
            pending = math.max(pending, h)
            flush()
        else
            local h = fillPanel(self, p, g, half)
            p:SetPoint("TOPLEFT", child, "TOPLEFT", 0, -y)
            pending = h
        end
        p:Show()
    end
    flush()
    for n = k + 1, #self.panels do self.panels[n]:Hide() end
    child:SetHeight(math.max(1, y - gap))
    scroll:SetVerticalScroll(keep and math.min(offset, math.max(0, y - scroll:GetHeight())) or 0)
end

function Challenges:Close()
    self.openIndex = nil
    self.detail:Hide()
    self.grid:Show()
end

function UI.LegacyChallenges(parent)
    local f = CreateFrame("Frame", nil, parent)
    Mixin(f, Challenges)
    f.cards = {}
    f.grid = CreateFrame("Frame", nil, f)
    f.grid:SetAllPoints()
    -- the full list of one category: a bar with the way back, the panels
    f.expanded, f.panels = {}, {}
    f.detail = CreateFrame("Frame", nil, f)
    f.detail:SetAllPoints()
    f.detail:Hide()
    f.back = UI.Button(f.detail, { text = "All challenges", variant = "quiet", onClick = function() f:Close() end })
    f.back.fixedWidth = true
    f.back:SetWidth(f.back.label:GetUnboundedStringWidth() + S["space-5"] * 2 + 14)
    f.back.label:ClearAllPoints()
    f.back.label:SetPoint("CENTER", 7, 0)
    -- the press moves the label 1px down: keep it beside the chevron
    f.back:HookScript("OnMouseDown", function(b) if b:IsEnabled() then b.label:SetPoint("CENTER", 7, -1) end end)
    f.back:HookScript("OnMouseUp", function(b) b.label:SetPoint("CENTER", 7, 0) end)
    f.back.chevron = f.back:CreateTexture(nil, "OVERLAY")
    f.back.chevron:SetTexture(GLYPHS .. "chevronLeft.tga")
    f.back.chevron:SetSize(10, 10)
    f.back.chevron:SetPoint("LEFT", S["space-5"], 0)
    UI.Paint(f.back.chevron, "gilt-text")
    f.back:SetPoint("TOPLEFT")
    f.detailTitle = UI.Text(f.detail, "header", "gilt-text")
    f.detailTitle:SetPoint("LEFT", f.back, "RIGHT", S["space-6"], 0)
    f.detailCount = UI.Text(f.detail, "caption", "ink-muted")
    f.detailCount:SetPoint("LEFT", f.detailTitle, "RIGHT", S["space-4"], 0)
    f.detailBar = thinBar(f.detail, 4)
    f.detailBar:SetPoint("LEFT", f.detailCount, "RIGHT", S["space-5"], 0)
    f.detailBar:SetPoint("RIGHT", f.detail, "RIGHT", 0, 0)
    f.scroll = UI.ScrollArea(f.detail, 6)
    f.scroll:SetPoint("TOPLEFT", f.back, "BOTTOMLEFT", 0, -S["space-5"])
    f.scroll:SetPoint("BOTTOMRIGHT", f.detail, "BOTTOMRIGHT", -10, 0)
    f:SetScript("OnSizeChanged", function() f:Layout() end)
    live[f] = "challenges"
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
local function trackHeight()
    return TRACK_TOP + 6 + S["space-3"] + T.type.numeric.lineHeight + S["space-2"] + T.type.caption.lineHeight
end
UI.LEGACY_TRACK_H = trackHeight()

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
            UI.Paint(st.check, "fel")
            st.mark = UI.Diamond(st, 9, "gilt-line", "OVERLAY", 3)
            st.mark:SetPoint("CENTER", st, "TOP", 0, -(TRACK_TOP + 3))
            st.at = UI.Text(st, "numeric", "ink-muted")
            st.at:SetPoint("TOP", st, "TOP", 0, -(TRACK_TOP + 6 + S["space-3"]))
            self.stops[i] = st
        end
        local got = earned >= (s.at or 0)
        st.slot.stop = s
        st.slot.skin:SetItem({ icon = s.icon, quality = s.quality, dim = not got })
        UI.Paint(st.mark, got and "gilt" or "gilt-line")
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
    live[f] = "track"
    return f
end

-- A theme can change the caption style (the heights above) and the colours
-- in the texts: measured and drawn again. (The public copies of the two
-- heights too: the Legacy window sizes itself from them.)
ns.Events.On("SUUUI_THEME_CHANGED", function()
    UI.LEGACY_CARD_H, UI.LEGACY_TRACK_H = cardHeight(), trackHeight()
    local public = ns.API and ns.API.UI
    if public then public.LEGACY_CARD_H, public.LEGACY_TRACK_H = UI.LEGACY_CARD_H, UI.LEGACY_TRACK_H end
    for f, kind in pairs(live) do
        if kind == "points" then
            restyleBlock(f.account)
            restyleBlock(f.char)
            f:SetHeight(f.account:GetHeight())
            if f.data then f:SetPoints(f.data) end
        elseif kind == "challenges" then
            f:Layout()
            if f.openIndex then f:Open(f.openIndex, true) end
        else
            restyleBlock(f.points)
            f:SetHeight(UI.LEGACY_TRACK_H)
            for _, st in ipairs(f.stops) do st:SetHeight(UI.LEGACY_TRACK_H) end
        end
    end
end, "UI.Legacy")
