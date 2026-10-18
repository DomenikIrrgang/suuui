-- UI/Timeline.lua
-- The encounter timeline (design board "Encounter timeline").
--
--   local t = UI.EncounterTimeline(parent, { variant = "track" | "list", window = 30, soonAt = 5 })
--   t:SetEvents(list)   -- { { id, label, endsAt (GetTime() it happens), paused (seconds
--                       --   left, frozen), icon, badge = { tone, text } }, ... }
--   t:SetVariant(v)
--
-- track: no panel, a thin gilt line `timeline-w` wide over the world, now at
-- its left end (an ink mark), ticks every 5 seconds, "30s" over the right
-- end. Each ability rides toward now: its icon (icon-md, a dark ring; amber
-- under `soonAt` seconds) on the line, its time and name centred under it,
-- a badge under those. What comes after the window is named right of the line
-- ("then Inferno in 0:52 · +1 more").
-- list: the older glass panel, soonest first, each row with a draining line.
-- The positions move every frame while something is on it.

local _, ns = ...

local UI, T = ns.UI, ns.Tokens
local S = T.space

local EV_W = 92
local TRACK_H = 70
local LINE_Y = 11

local function fmtTime(s)
    s = math.max(0, s)
    if s >= 60 then return ("%d:%02d"):format(math.floor(s / 60), math.floor(s % 60)) end
    if s < 10 then return ("%.1fs"):format(s) end
    return ("%ds"):format(math.floor(s))
end

local function remainingOf(e, now)
    if e.paused then return e.paused end
    return math.max(0, (e.endsAt or now) - now)
end

--------------------------------------------------------------------------------
-- Track
--------------------------------------------------------------------------------

local function trackEvent(t)
    local f = CreateFrame("Frame", nil, t.track)
    f:SetSize(EV_W, TRACK_H)
    f.icon = UI.Icon(f, "icon-md")
    f.ring = UI.Border(f.icon, { 0, 0, 0, 0.7 }, { width = 2, inset = -2 })
    f.time = UI.Text(f, "numeric", "ink")
    f.time:SetShadowed(true)
    f.name = UI.Text(f, "caption", "ink-muted")
    f.name:SetShadowed(true)
    f.name:SetWordWrap(false)
    f.name:SetWidth(EV_W)
    f.badge = UI.StateBadge(f, "warning", "Tank")
    return f
end

-- start / mid / end: centred under its icon, or held inside the line's ends
local function alignEvent(f, align)
    f.icon:ClearAllPoints()
    f.time:ClearAllPoints()
    f.name:ClearAllPoints()
    f.badge:ClearAllPoints()
    local point = align == "start" and "TOPLEFT" or align == "end" and "TOPRIGHT" or "TOP"
    local justify = align == "start" and "LEFT" or align == "end" and "RIGHT" or "CENTER"
    local iconX = align == "start" and 0 or align == "end" and 0 or 0
    f.icon:SetPoint(point, iconX, -(LINE_Y + 1 - UI.Size("icon-md") / 2))
    local below = align == "start" and "BOTTOMLEFT" or align == "end" and "BOTTOMRIGHT" or "BOTTOM"
    f.time:SetPoint(point, f.icon, below, 0, -2)
    f.time:SetJustifyH(justify)
    f.name:SetPoint(point, f.time, below, 0, -1)
    f.name:SetJustifyH(justify)
    f.badge:SetPoint(point, f.name, below, 0, -2)
end

local function layoutTrack(t, now)
    local win, soonAt = t.window, t.soonAt
    local w = t.track:GetWidth()
    local inWin, later = {}, {}
    for _, e in ipairs(t.events) do
        local r = remainingOf(e, now)
        if r <= win then inWin[#inWin + 1] = { e = e, r = r } else later[#later + 1] = { e = e, r = r } end
    end
    table.sort(inWin, function(a, b) return a.r < b.r end)
    table.sort(later, function(a, b) return a.r < b.r end)
    for i, x in ipairs(inWin) do
        local f = t.evs[i] or trackEvent(t)
        t.evs[i] = f
        local frac = x.r / win
        -- always centred under its icon (near now too: held inside the line,
        -- the label looked pushed aside)
        local align = "mid"
        if f.align ~= align then alignEvent(f, align); f.align = align end
        local px = math.floor(frac * w + 0.5)
        f:ClearAllPoints()
        if align == "start" then f:SetPoint("TOPLEFT", t.track, "TOPLEFT", px - 12, 0)
        elseif align == "end" then f:SetPoint("TOPRIGHT", t.track, "TOPLEFT", px + 12, 0)
        else f:SetPoint("TOP", t.track, "TOPLEFT", px, 0) end
        if f.id ~= x.e.id then
            f.id = x.e.id
            f.icon:SetArt(x.e.icon or 134400)
            f.name:SetValue(x.e.label or "")
            f.badge:SetShown(x.e.badge ~= nil)
            if x.e.badge then f.badge:SetState(x.e.badge.tone, x.e.badge.text) end
        end
        local soon = x.r <= soonAt
        f.time:SetValue(fmtTime(x.r))
        f.time:SetColor(soon and "amber" or "ink")
        f.name:SetColor(soon and "ink" or "ink-muted")
        if soon then f.ring:SetColor("amber") else f.ring:SetColor(0, 0, 0, 0.7) end
        f:Show()
    end
    for i = #inWin + 1, #t.evs do t.evs[i]:Hide(); t.evs[i].id = nil end
    if #later > 0 then
        local first = later[1]
        local more = #later > 1 and (" · +%d more"):format(#later - 1) or ""
        t.later:SetValue(("then %s in %s%s"):format(first.e.label or "?", fmtTime(first.r), more))
        t.later:SetVisible(true)
    else
        t.later:SetVisible(false)
    end
end

local function buildTrack(t)
    local track = CreateFrame("Frame", nil, t)
    track:SetPoint("TOPLEFT")
    track:SetSize(UI.Size("timeline-w"), TRACK_H)
    t.track = track
    local line = track:CreateTexture(nil, "ARTWORK")
    UI.PaintFill(line, "gilt-line")
    line:SetPoint("TOPLEFT", 0, -LINE_Y)
    line:SetPoint("TOPRIGHT", 0, -LINE_Y)
    line:SetHeight(2)
    local now = track:CreateTexture(nil, "OVERLAY")
    UI.PaintFill(now, "ink")
    now:SetSize(2, 18)
    now:SetPoint("TOPLEFT", -1, -3)
    t.ticks = {}
    for s = 5, t.window - 1, 5 do
        local tick = track:CreateTexture(nil, "ARTWORK")
        UI.PaintFill(tick, "gilt-line")
        tick:SetSize(1, 8)
        tick:SetPoint("TOPLEFT", math.floor(s / t.window * track:GetWidth() + 0.5), -8)
        t.ticks[#t.ticks + 1] = tick
    end
    t.endLabel = UI.Text(track, "micro", "ink-faint")
    t.endLabel:SetShadowed(true)
    t.endLabel:SetPoint("BOTTOM", track, "TOPRIGHT", 0, -10)
    t.endLabel:SetValue(("%ds"):format(t.window))
    t.later = UI.Text(track, "caption", "ink-muted")
    t.later:SetShadowed(true)
    t.later:SetPoint("TOPLEFT", track, "TOPRIGHT", S["space-4"], -4)
    t.later:SetVisible(false)
    t.evs = {}
end

--------------------------------------------------------------------------------
-- List
--------------------------------------------------------------------------------

local LIST_W, ROW_H = 280, 30

local function listRow(t, i)
    local r = CreateFrame("Frame", nil, t.list)
    r:SetSize(LIST_W - S["space-5"] * 2, ROW_H)
    r.icon = UI.Icon(r, "icon-md")
    r.icon:SetPoint("LEFT", 0, 2)
    r.name = UI.Text(r, "label", "ink")
    r.name:SetPoint("LEFT", r.icon, "RIGHT", S["space-4"], 0)
    r.name:SetWordWrap(false)
    r.time = UI.Text(r, "numeric", "ink")
    r.time:SetPoint("RIGHT", 0, 2)
    r.badge = UI.StateBadge(r, "warning", "Tank")
    r.badge:SetPoint("RIGHT", r.time, "LEFT", -S["space-4"], 0)
    r.track = r:CreateTexture(nil, "BACKGROUND")
    UI.PaintFill(r.track, "track")
    r.track:SetPoint("BOTTOMLEFT")
    r.track:SetPoint("BOTTOMRIGHT")
    r.track:SetHeight(2)
    r.drain = r:CreateTexture(nil, "ARTWORK")
    r.drain:SetPoint("BOTTOMLEFT")
    r.drain:SetHeight(2)
    t.rows[i] = r
    return r
end

local function layoutList(t, now)
    local list = {}
    for _, e in ipairs(t.events) do list[#list + 1] = { e = e, r = remainingOf(e, now) } end
    table.sort(list, function(a, b) return a.r < b.r end)
    local y = t.listTop
    local innerW = LIST_W - S["space-5"] * 2
    for i, x in ipairs(list) do
        local r = t.rows[i] or listRow(t, i)
        r:ClearAllPoints()
        r:SetPoint("TOPLEFT", S["space-5"], -y)
        r.icon:SetArt(x.e.icon or 134400)
        r.name:SetValue(x.e.label or "")
        r.badge:SetShown(x.e.badge ~= nil)
        if x.e.badge then r.badge:SetState(x.e.badge.tone, x.e.badge.text) end
        r.name:SetPoint("RIGHT", x.e.badge and r.badge or r.time, "LEFT", -S["space-4"], 0)
        local soon = x.r <= t.soonAt
        r.time:SetValue(fmtTime(x.r))
        r.time:SetColor(soon and "amber" or "ink")
        UI.PaintFill(r.drain, soon and "amber" or "ink-muted")
        r.drain:SetWidth(math.max(1, math.min(1, x.r / t.window) * innerW))
        r:Show()
        y = y + ROW_H + S["space-3"]
    end
    for i = #list + 1, #t.rows do t.rows[i]:Hide() end
    t.list:SetHeight(math.max(t.listTop + S["space-5"], y - S["space-3"] + S["space-5"]))
    t:SetHeight(t.list:GetHeight())
end

-- the rule under the title, and the rows under it, by the header's line
-- height (again when a theme changes it)
local lists = setmetatable({}, { __mode = "k" })
local function placeRule(t)
    local y = S["space-4"] * 2 + T.type.header.lineHeight
    local rule = t.list.rule
    rule:ClearAllPoints()
    rule:SetPoint("TOPLEFT", 1, -y)
    rule:SetPoint("TOPRIGHT", -1, -y)
    t.listTop = y + 1 + S["space-4"]
end

ns.Events.On("SUUUI_THEME_CHANGED", function()
    for t in pairs(lists) do
        placeRule(t)
        if t.variant == "list" then t:Layout() end
    end
end, "Timeline")

local function buildList(t)
    local p = CreateFrame("Frame", nil, t)
    p:SetPoint("TOPLEFT")
    p:SetWidth(LIST_W)
    UI.Fill(p, "surface-glass", "BACKGROUND"):SetAllPoints()
    UI.Border(p, "gilt-line")
    UI.Shadow(p, "shadow-panel")
    p.title = UI.Text(p, "header", "gilt-text")
    p.title:SetPoint("TOPLEFT", S["space-5"], -S["space-4"])
    p.title:SetValue("Timeline")
    p.meta = UI.Text(p, "caption", "ink-muted")
    p.meta:SetPoint("LEFT", p.title, "RIGHT", S["space-3"], 0)
    p.meta:SetPoint("RIGHT", -S["space-5"], 0)
    p.meta:SetWordWrap(false)
    p.rule = p:CreateTexture(nil, "BORDER")
    UI.PaintFill(p.rule, "gilt-faint")
    p.rule:SetHeight(1)
    t.list = p
    t.rows = {}
    placeRule(t)
    lists[t] = true
end

--------------------------------------------------------------------------------
-- The timeline
--------------------------------------------------------------------------------

local Timeline = {}

function Timeline:Layout()
    local now = GetTime()
    if self.variant == "list" then layoutList(self, now) else layoutTrack(self, now) end
end

function Timeline:SetEvents(list)
    self.events = list or {}
    self:Layout()
    self:SetScript("OnUpdate", #self.events > 0 and function(s) s:Layout() end or nil)
end

function Timeline:SetMeta(text)
    if self.list then self.list.meta:SetValue(text or "") end
end

function Timeline:SetVariant(variant)
    self.variant = variant == "list" and "list" or "track"
    if self.variant == "list" and not self.list then buildList(self) end
    if self.variant == "track" and not self.track then buildTrack(self) end
    if self.track then self.track:SetShown(self.variant == "track") end
    if self.list then self.list:SetShown(self.variant == "list") end
    if self.variant == "track" then
        self:SetSize(UI.Size("timeline-w"), TRACK_H)
    else
        self:SetWidth(LIST_W)
    end
    self:Layout()
end

function UI.EncounterTimeline(parent, opts)
    opts = opts or {}
    local t = CreateFrame("Frame", nil, parent)
    Mixin(t, Timeline)
    t.window, t.soonAt = opts.window or 30, opts.soonAt or 5
    t.events = {}
    t:SetVariant(opts.variant or "track")
    return t
end
