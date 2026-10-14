-- UI/ObjectiveTracker.lua
-- The objective tracker (design board "Objective tracker"): on the world,
-- no panel. A head (an 18px toggle with a plus or minus, "Quests" in the
-- header face, a gilt rule fading out, the meta caption), then the quests
-- space-4 apart: the title (label, the quest's difficulty colour), its
-- objectives indented space-4 (a 4px ink-muted diamond, or a check once
-- done in ink-muted; the count right-aligned in tabular figures), or an
-- arcane check and "Ready to turn in" once every objective is done.
--
--   local t = UI.ObjectiveTracker(parent, { width = 260, maxHeight = 440 })
--   t:SetQuests(quests, freeze)   -- { questID, zone, title, difficulty, complete,
--                                 --   failed, turnIn, objectives = { { text,
--                                 --   progress, done } }, item }; 0.13: color (a
--                                 --   token for the title), icon (16px before
--                                 --   it), count ("×3", arcane, after it): the
--                                 --   Recipes tracker draws recipes this way
--   t:SetCollapsed(on)            -- only the head
--   t:QuestTop(questID)           -- where a quest's title starts (px down
--                                 -- from the tracker's top), for its item;
--                                 -- nil while scrolled out of sight
--   t:ScrollBy(px), t:SetScrollLocked(on), t.onScroll() -- the wheel scrolls
--                                 -- the quests within maxHeight
--   t.onToggle, t.onQuestClick(questID, button) -- set by the owner
--   opts.toggle: the owner's own (secure) toggle button, drawn here, placed
--   by the owner over the head's left end (HEAD_H square at the top left)
--
-- Quests with a `zone` get its heading (caption, gilt-text, a fading rule)
-- wherever the zone changes; give them grouped.
-- `freeze` (in combat, when quest items are beside the titles): the quests
-- keep their places and a quest's height only grows, so a secure item
-- button set beside a title before combat stays beside it. New quests go
-- at the end; a quest gone leaves its space. The next SetQuests without
-- freeze lays everything out again.
-- `item.preview` draws a plain icon beside the title (the settings
-- preview); the real, secure item buttons belong to the owner.

local _, ns = ...

local UI, T = ns.UI, ns.Tokens
local S = T.space

local HEAD_H = 18
local TITLE_H = T.type.label.lineHeight
local LINE_H = T.type.caption.lineHeight
local INDENT = S["space-4"]
local ICON = 16

local DIFFICULTY = {
    impossible = "quest-impossible", ["very-difficult"] = "quest-very-difficult",
    difficult = "quest-difficult", standard = "quest-standard", trivial = "quest-trivial",
}

local Tracker = {}
UI.TRACKER_HEAD_H = HEAD_H

-- A diamond bullet: 4px, turned 45°, 3px either side.
local function bullet(parent)
    local d = UI.Diamond(parent, 4, "ink-muted", "ARTWORK")
    return d
end

local function objectiveLine(row)
    local l = CreateFrame("Frame", nil, row)
    l.bullet = bullet(l)
    l.bullet:SetPoint("TOPLEFT", 3, -(LINE_H - 4) / 2)
    l.check = UI.Check(l, 11, "ink-muted")
    l.check:SetPoint("TOPLEFT", -1, -(LINE_H - 11) / 2)
    l.text = UI.Text(l, "caption", "ink")
    l.text:SetShadowed(true)
    l.text:SetWordWrap(true)
    l.text:SetJustifyH("LEFT")
    l.text:SetPoint("TOPLEFT", 10 + S["space-3"], 0)
    l.count = UI.Text(l, "numeric", "ink")
    l.count:SetShadowed(true)
    l.count:SetPoint("TOPRIGHT", 0, 1)
    return l
end

local function questRow(t)
    local r = CreateFrame("Button", nil, t.list)
    r:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    r.title = UI.Text(r, "label", "quest-standard")
    r.title:SetShadowed(true)
    r.title:SetJustifyH("LEFT")
    -- 0.13: an entry's own icon before the title (a tracked recipe's
    -- product) and a count after it ("×3")
    r.icon = UI.Icon(r, ICON)
    r.icon:SetPoint("TOPLEFT", 0, -(TITLE_H - ICON) / 2)
    r.icon:Hide()
    r.count = UI.Text(r, "numeric", "arcane")
    r.count:SetShadowed(true)
    r.count:SetPoint("TOPRIGHT", 0, 0)
    r.lines = {}
    r.done = CreateFrame("Frame", nil, r)
    r.done.check = UI.Check(r.done, 12, "arcane")
    r.done.check:SetPoint("LEFT", INDENT, 0)
    r.done.text = UI.Text(r.done, "caption", "arcane")
    r.done.text:SetShadowed(true)
    r.done.text:SetPoint("LEFT", r.done.check, "RIGHT", S["space-2"], 0)
    r.done:SetHeight(LINE_H)
    -- the settings preview's item: a plain icon left of the title
    r.preview = UI.Icon(r, "icon-md")
    r.preview:SetPoint("TOPRIGHT", r, "TOPLEFT", -S["space-3"], 2)
    r.preview:Hide()
    r:SetScript("OnEnter", function(self)
        if self.quest and self.quest.tooltip then UI.ShowTooltip(self, self.quest.tooltip) end
    end)
    r:SetScript("OnLeave", function() UI.HideTooltip() end)
    r:SetScript("OnClick", function(self, button)
        if t.onQuestClick and self.quest then t.onQuestClick(self.quest.questID, button, self) end
    end)
    return r
end

-- One quest drawn into its row; the row's natural height.
function Tracker:DrawQuest(r, q)
    r.quest = q
    r.title:SetValue(q.title or "")
    r.title:SetColor(q.color or DIFFICULTY[q.difficulty or "standard"] or "quest-standard")
    r.icon:SetShown(q.icon ~= nil)
    if q.icon then r.icon:SetArt(q.icon) end
    r.count:SetValue(q.count or "")
    r.title:ClearAllPoints()
    r.title:SetPoint("TOPLEFT", q.icon and (ICON + S["space-3"]) or 0, 0)
    if q.count and q.count ~= "" then
        r.title:SetPoint("TOPRIGHT", r.count, "TOPLEFT", -S["space-3"], 0)
    else
        r.title:SetPoint("TOPRIGHT")
    end
    local w = self.contentWidth or self.width
    local y = TITLE_H + S["space-1"]
    for _, l in ipairs(r.lines) do l:Hide() end
    if q.complete or q.failed then
        r.done:ClearAllPoints()
        r.done:SetPoint("TOPLEFT", 0, -y)
        r.done:SetPoint("TOPRIGHT", 0, -y)
        r.done.check:SetShown(not q.failed)
        r.done.text:SetColor(q.failed and "ember-text" or "arcane")
        r.done.text:ClearAllPoints()
        if q.failed then r.done.text:SetPoint("LEFT", INDENT, 0)
        else r.done.text:SetPoint("LEFT", r.done.check, "RIGHT", S["space-2"], 0) end
        r.done.text:SetValue(q.failed and "Failed" or (q.turnIn or "Ready to turn in"))
        r.done:Show()
        y = y + LINE_H
    else
        r.done:Hide()
        for i, o in ipairs(q.objectives or {}) do
            local l = r.lines[i] or objectiveLine(r)
            r.lines[i] = l
            l.bullet:SetShown(not o.done)
            l.check:SetShown(o.done and true or false)
            l.text:SetColor(o.done and "ink-muted" or "ink")
            l.count:SetColor(o.done and "ink-muted" or "ink")
            l.count:SetValue(o.progress or "")
            local countW = (o.progress and o.progress ~= "") and (l.count:GetUnboundedStringWidth() + S["space-3"]) or 0
            local textW = w - INDENT - 10 - S["space-3"] - countW
            l.text:SetWidth(textW)
            l.text:SetValue(o.text or "")
            local h = math.max(LINE_H, math.ceil(l.text:GetStringHeight()))
            l:ClearAllPoints()
            l:SetPoint("TOPLEFT", INDENT, -y)
            l:SetSize(w - INDENT, h)
            l:Show()
            y = y + h + 1
        end
    end
    r.preview:SetShown(q.item and q.item.preview and true or false)
    if q.item and q.item.preview then r.preview:SetArt(q.item.icon) end
    return y
end

-- A zone's heading over its quests: caption in gilt-text, a gilt-line
-- hairline fading out after it.
local function zoneRow(t)
    local z = CreateFrame("Frame", nil, t.list)
    z:SetHeight(LINE_H)
    z.text = UI.Text(z, "caption", "gilt-text")
    z.text:SetShadowed(true)
    z.text:SetPoint("LEFT")
    z.rule = UI.Hairline(z, "gilt-line", "out")
    z.rule:SetPoint("LEFT", z.text, "RIGHT", S["space-3"], 0)
    z.rule:SetPoint("RIGHT")
    return z
end

-- The list's entries: a zone heading wherever the zone changes (quests
-- carry `zone`; none: no headings), then its quests.
local function entriesOf(quests)
    local entries, last = {}, nil
    for _, q in ipairs(quests) do
        if q.zone and q.zone ~= last then
            entries[#entries + 1] = { zone = q.zone }
            last = q.zone
        end
        entries[#entries + 1] = { id = q.questID, zone = q.zone }
    end
    return entries
end

-- While the quests scroll they make room for the thumb at the right edge.
local GUTTER = S["space-5"] + 1

function Tracker:SetQuests(quests, freeze)
    if freeze and self.contentWidth then
        -- frozen: the width stays too
        self:LayOut(quests, freeze)
    else
        self.contentWidth = self.width
        self:LayOut(quests, freeze)
        if self.maxHeight and (self.listHeight or 0) > self:ViewHeight() then
            self.contentWidth = self.width - GUTTER
            self:LayOut(quests, freeze)
        end
    end
    self.list:SetWidth(self.contentWidth)
    self:Fit()
    self:ApplyScroll()
end

function Tracker:LayOut(quests, freeze)
    quests = quests or {}
    local byID = {}
    for _, q in ipairs(quests) do byID[q.questID] = q end
    -- the entries: as given, or (frozen) the last ones with new quests after
    local entries
    if freeze and self.entries then
        entries = {}
        local seen, last = {}, nil
        for _, e in ipairs(self.entries) do
            entries[#entries + 1] = e
            if e.id then seen[e.id] = true end
            last = e.zone
        end
        for _, q in ipairs(quests) do
            if not seen[q.questID] then
                if q.zone and q.zone ~= last then entries[#entries + 1] = { zone = q.zone }; last = q.zone end
                entries[#entries + 1] = { id = q.questID, zone = q.zone }
            end
        end
    else
        entries = entriesOf(quests)
        self.heights = {}
    end
    self.entries = entries
    for _, r in ipairs(self.rows) do r.inUse = false end
    for _, z in ipairs(self.zoneRows) do z.inUse = false end
    self.tops = {}
    local y, prev = 0, nil
    local nQuest, nZone = 0, 0
    for _, e in ipairs(entries) do
        if e.id then
            nQuest = nQuest + 1
            local r = self.rows[nQuest] or questRow(self)
            self.rows[nQuest] = r
            local q = byID[e.id]
            local h = q and self:DrawQuest(r, q) or 0
            if freeze then h = math.max(h, self.heights[e.id] or 0) end
            -- space-4 between quests, space-2 under a zone's heading
            if prev == "quest" then y = y + S["space-4"] elseif prev == "zone" then y = y + S["space-2"] end
            self.heights[e.id] = h
            self.tops[e.id] = y
            r.top, r.height, r.inUse = y, h, q ~= nil
            r:SetSize(self.contentWidth, math.max(1, h))
            y = y + h
            prev = "quest"
        else
            nZone = nZone + 1
            local z = self.zoneRows[nZone] or zoneRow(self)
            self.zoneRows[nZone] = z
            -- space-5 over a zone's heading after the one before
            if prev then y = y + S["space-5"] end
            z.text:SetValue(e.zone)
            z:SetWidth(self.contentWidth)
            z.top, z.height, z.inUse = y, LINE_H, true
            y = y + LINE_H
            prev = "zone"
        end
    end
    self.listHeight = y
    self.list:SetHeight(math.max(1, y))
end

-- The quests' window: maxHeight less the head (all of them without one).
function Tracker:ViewHeight()
    if not self.maxHeight then return self.listHeight or 0 end
    return math.max(LINE_H, self.maxHeight - HEAD_H - S["space-4"])
end

function Tracker:ScrollBy(px)
    if self.scrollLocked then return end
    self:SetScroll((self.scroll or 0) + px)
end

function Tracker:SetScroll(v)
    local max = math.max(0, (self.listHeight or 0) - self:ViewHeight())
    v = math.max(0, math.min(max, math.floor(v + 0.5)))
    if v == self.scroll then return end
    self.scroll = v
    self:ApplyScroll()
    if self.onScroll then self.onScroll() end
end

-- In combat with secure item buttons beside the titles: the list stays put.
function Tracker:SetScrollLocked(on)
    self.scrollLocked = on and true or false
end

-- The rows in the window shown, the rest hidden (so nothing out of sight
-- takes a click); the thumb at the right edge while there's more.
function Tracker:ApplyScroll()
    local view = self:ViewHeight()
    local max = math.max(0, (self.listHeight or 0) - view)
    self.scroll = math.max(0, math.min(max, self.scroll or 0))
    local scroll = self.scroll
    for _, pool in ipairs({ self.rows, self.zoneRows }) do
        for _, r in ipairs(pool) do
            local visible = r.inUse and (r.top + r.height > scroll) and (r.top < scroll + view)
            if visible then
                r:ClearAllPoints()
                r:SetPoint("TOPLEFT", self.list, "TOPLEFT", 0, -(r.top - scroll))
                r:Show()
            else
                r:Hide()
            end
        end
    end
    if max > 0 then
        local trackH = view
        local thumbH = math.max(16, trackH * view / (self.listHeight or 1))
        self.thumb:ClearAllPoints()
        -- at the tracker's right edge, the quests GUTTER clear of it
        self.thumb:SetPoint("TOPRIGHT", self.list, "TOPLEFT", self.width, -((trackH - thumbH) * scroll / max))
        self.thumb:SetHeight(thumbH)
        self.thumb:Show()
    else
        self.thumb:Hide()
    end
end

-- Where a quest's title starts, down from the tracker's top (nil: not shown).
function Tracker:QuestTop(questID)
    local top = self.tops and self.tops[questID]
    if not top then return nil end
    top = top - (self.scroll or 0)
    -- the title scrolled out of the window (its item, 24px from 2px over the
    -- title, would hang past the window's bottom)
    if top < 0 or top - 2 + 24 > self:ViewHeight() then return nil end
    return HEAD_H + S["space-4"] + top
end

function Tracker:SetMeta(text)
    self.meta:SetValue(text or "")
    self.rule:ClearAllPoints()
    self.rule:SetPoint("LEFT", self.label, "RIGHT", S["space-3"], 0)
    if text and text ~= "" then
        self.rule:SetPoint("RIGHT", self.meta, "LEFT", -S["space-3"], 0)
    else
        self.rule:SetPoint("RIGHT", self.head, "RIGHT")
    end
end

function Tracker:SetTitle(text)
    self.label:SetValue(text or "Quests")
end

function Tracker:SetCollapsed(on)
    self.collapsed = on and true or false
    self.list:SetShown(not self.collapsed)
    self.plus:SetShown(self.collapsed)
    self.minus:SetShown(not self.collapsed)
    self:Fit()
end

function Tracker:Fit()
    local h = HEAD_H
    local list = math.min(self.listHeight or 0, self:ViewHeight())
    if not self.collapsed and list > 0 then h = h + S["space-4"] + list end
    self.clip:SetHeight(math.max(1, list))
    self:SetHeight(h)
end

function Tracker:SetMaxHeight(h)
    self.maxHeight = h
    self:Fit()
    self:ApplyScroll()
end

-- The toggle's look (the toggle itself may be a secure button the owner
-- made: t.toggle).
local function toggleArt(b)
    UI.Fill(b, "surface-glass", "BACKGROUND"):SetAllPoints()
    b.edge = UI.Border(b, "gilt-line")
    b:HookScript("OnEnter", function(self) self.edge:SetColor("gilt") end)
    b:HookScript("OnLeave", function(self) self.edge:SetColor("gilt-line") end)
end

function UI.ObjectiveTracker(parent, opts)
    opts = opts or {}
    local t = CreateFrame("Frame", opts.name, parent)
    Mixin(t, Tracker)
    t.width = opts.width or 260
    t.maxHeight = opts.maxHeight
    t:SetSize(t.width, HEAD_H)
    t.rows = {}
    t.zoneRows = {}
    t.heights = {}

    t.head = CreateFrame("Frame", nil, t)
    t.head:SetPoint("TOPLEFT")
    t.head:SetPoint("TOPRIGHT")
    t.head:SetHeight(HEAD_H)
    -- the toggle: a plain button, or the owner's (a secure one, placed by
    -- the owner over the head's left end: anchored into the tracker, which
    -- changes height in combat, it would lock the tracker's layout)
    local toggle = opts.toggle
    if not toggle then
        toggle = CreateFrame("Button", nil, t.head)
        toggle:SetPoint("LEFT")
        toggle:SetScript("OnClick", function() if t.onToggle then t.onToggle() end end)
    end
    toggle:SetSize(HEAD_H, HEAD_H)
    toggleArt(toggle)
    t.toggle = toggle
    t.plus = UI.Plus(toggle, "gilt-text")
    t.plus:SetPoint("CENTER")
    t.minus = UI.Minus(toggle, "gilt-text")
    t.minus:SetPoint("CENTER")
    t.plus:Hide()
    t.label = UI.Text(t.head, "header", "gilt-text")
    t.label:SetShadowed(true)
    t.label:SetPoint("LEFT", t.head, "LEFT", HEAD_H + S["space-3"], 0)
    t.meta = UI.Text(t.head, "caption", "ink-muted")
    t.meta:SetShadowed(true)
    t.meta:SetPoint("RIGHT")
    t.rule = UI.Hairline(t.head, "gilt-line", "out")
    t:SetTitle(opts.title)
    t:SetMeta(opts.meta)

    -- the quests' window: clips them (wide enough on the left for the
    -- preview's item icons beside the titles)
    local itemRoom = UI.Size("icon-md") + S["space-3"] + 2
    t.clip = CreateFrame("Frame", nil, t)
    t.clip:SetPoint("TOPLEFT", -itemRoom, -(HEAD_H + S["space-4"]))
    t.clip:SetPoint("TOPRIGHT", S["space-3"], -(HEAD_H + S["space-4"]))
    t.clip:SetHeight(1)
    t.clip:SetClipsChildren(true)
    t.list = CreateFrame("Frame", nil, t.clip)
    t.list:SetPoint("TOPLEFT", itemRoom, 0)
    t.list:SetWidth(t.width)
    t.list:SetHeight(1)
    -- where the window is in the list: a gilt-line thumb, 1px, right of the quests
    t.thumb = t.clip:CreateTexture(nil, "OVERLAY")
    t.thumb:SetColorTexture(UI.RGBA("gilt-line"))
    t.thumb:SetWidth(1)
    t.thumb:Hide()
    t.scroll = 0
    t:EnableMouseWheel(true)
    t:SetScript("OnMouseWheel", function(self, delta) self:ScrollBy(-delta * (TITLE_H + LINE_H * 2)) end)
    t:SetCollapsed(false)
    return t
end
