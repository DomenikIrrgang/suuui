-- UI/TabMarker.lua
-- The chosen tab's underline and jewel for a row of tabs, moved as the
-- website's nav marker moves (asked 2026-10-19, first on the chat tabs,
-- then for every tab row): the jewel glides to the tab under the pointer
-- and back to the chosen one when the pointer leaves, and both glide to a
-- newly chosen tab, the underline taking its width; dur-base, ease-in-out.
-- A vertical list (the settings nav, the professions rail) has the jewel
-- only, gliding up and down beside its entries. With reduced motion, while
-- the row is hidden, and the first time: there at once.
--
--   local marker = UI.TabMarker(row, { y = 0 })   -- a frame the tabs sit on
--   marker:Track(button)       -- its hover moves the jewel (once per button)
--   marker:SetChosen(button)   -- after the tabs are laid out or one is chosen;
--                              -- nil: hidden. Cheap when nothing moved.
--   marker:Aim()               -- again after the tabs moved
--
-- The marks sit on the row's frame and are placed by each button's own
-- rectangle, so the buttons may be anyone's (Blizzard's tabs in a skinned
-- window too); button.markLeft / button.markWidth override the left and
-- width when the caller lays the row out by offsets.
-- opts:
--   y       the line's and the jewel's centre above the tab's bottom (px; 0)
--   rule    a token (default "gilt-line"), or false: the jewel only
--   jewel   its size (5)
--   level   frame levels above the row (2)
--   vertical  true: entries above each other, the jewel beside them at
--           `side` ("LEFT" or "RIGHT" of the entry) + `x` px; no line

local _, ns = ...

local UI, T = ns.UI, ns.Tokens

local GLIDE = T.duration["dur-base"]
local EASE = T.easing["ease-in-out"].bezier

-- cubic-bezier(x1, y1, x2, y2) at time t: x solved for t by halving, then y
local function ease(t)
    local x1, y1, x2, y2 = EASE[1], EASE[2], EASE[3], EASE[4]
    local function at(a, b, u) return 3 * a * u * (1 - u) ^ 2 + 3 * b * u ^ 2 * (1 - u) + u ^ 3 end
    local lo, hi = 0, 1
    for _ = 1, 14 do
        local mid = (lo + hi) / 2
        if at(x1, x2, mid) < t then lo = mid else hi = mid end
    end
    return at(y1, y2, (lo + hi) / 2)
end

-- A moving place `p` with its size `s` (nil for the jewel): where it is
-- (at), was (from) and goes (to).
local function newMark() return { at = {}, from = {}, to = {} } end

local function aim(mark, p, s, now)
    local to = mark.to
    if mark.placed and to.p == p and to.s == s then return end
    if now or not mark.placed then
        mark.at.p, mark.at.s, mark.start = p, s, nil
    else
        mark.from.p, mark.from.s, mark.start = mark.at.p, mark.at.s, GetTime()
    end
    to.p, to.s, mark.placed = p, s, true
end

local function step(mark)
    if not mark.start then return false end
    local t = (GetTime() - mark.start) / GLIDE
    if t >= 1 then
        mark.at.p, mark.at.s, mark.start = mark.to.p, mark.to.s, nil
        return false
    end
    local e = ease(t)
    mark.at.p = mark.from.p + (mark.to.p - mark.from.p) * e
    if mark.to.s and mark.from.s then mark.at.s = mark.from.s + (mark.to.s - mark.from.s) * e end
    return true
end

local Marker = {}
Marker.__index = Marker

-- A button's left, bottom, width and height from the row's bottom left, in
-- the row's units (nil while it isn't laid out).
function Marker:Place(b)
    local row = self.row
    local l, bt, rl, rb = b:GetLeft(), b:GetBottom(), row:GetLeft(), row:GetBottom()
    if not (l and bt and rl and rb) then return nil end
    local k = b:GetEffectiveScale() / row:GetEffectiveScale()
    local left, width = l * k - rl, b:GetWidth() * k
    if b.markLeft then left, width = b.markLeft, b.markWidth or width end
    return left, bt * k - rb, width, b:GetHeight() * k
end

function Marker:Draw()
    local row = self.row
    local moving = step(self.ruleMark)
    moving = step(self.jewelMark) or moving
    local j = self.jewelMark.at
    self.jewel:ClearAllPoints()
    if self.vertical then
        self.jewel:SetPoint("CENTER", row, "BOTTOMLEFT", self.jewelX, j.p)
    else
        local y = self.base + self.y
        if self.rule then
            local r = self.ruleMark.at
            self.rule:ClearAllPoints()
            self.rule:SetPoint("BOTTOMLEFT", row, "BOTTOMLEFT", r.p, y)
            self.rule:SetWidth(math.max(1, r.s))
        end
        self.jewel:SetPoint("CENTER", row, "BOTTOMLEFT", j.p, y)
    end
    return moving
end

function Marker:Aim()
    local chosen = self.chosen
    local shown = chosen ~= nil and chosen:IsShown()
    if self.rule then self.rule:SetShown(shown) end
    self.jewel:SetShown(shown)
    if not shown then return end
    local left, bottom, width, height = self:Place(chosen)
    if not left then
        -- not laid out yet: next frame
        if not self.waiting then
            self.waiting = true
            C_Timer.After(0, function() self.waiting = false; self:Aim() end)
        end
        return
    end
    local now = ns.Motion.Reduced() or not self.row:IsVisible()
    local over = self.hovered
    local ol, ob, ow, oh = left, bottom, width, height
    if over and over ~= chosen and over:IsShown() then
        ol, ob, ow, oh = self:Place(over)
        if not ol then ol, ob, ow, oh = left, bottom, width, height end
    end
    if self.vertical then
        self.jewelX = left + (self.side == "RIGHT" and width or 0) + self.x
        aim(self.jewelMark, ob + oh / 2, nil, now)
    else
        self.base = bottom
        aim(self.ruleMark, left, width, now)
        aim(self.jewelMark, ol + ow / 2, nil, now)
    end
    if self:Draw() then
        self.holder:SetScript("OnUpdate", function()
            if not self:Draw() then self.holder:SetScript("OnUpdate", nil) end
        end)
    end
end

function Marker:SetChosen(button)
    self.chosen = button
    self:Aim()
end

function Marker:Track(button)
    if button.suuMarkTracked == self then return end
    button.suuMarkTracked = self
    button:HookScript("OnEnter", function(b) self.hovered = b; self:Aim() end)
    button:HookScript("OnLeave", function(b)
        if self.hovered == b then self.hovered = nil end
        self:Aim()
    end)
end

function UI.TabMarker(row, opts)
    opts = opts or {}
    local m = setmetatable({
        row = row, y = opts.y or 0, vertical = opts.vertical, side = opts.side or "LEFT", x = opts.x or 0,
        base = 0, jewelX = 0, ruleMark = newMark(), jewelMark = newMark(),
    }, Marker)
    -- one holder above the row's buttons: the line, then the jewel over it
    m.holder = CreateFrame("Frame", nil, row)
    m.holder:SetAllPoints()
    m.holder:SetFrameLevel(row:GetFrameLevel() + (opts.level or 2))
    if opts.rule ~= false and not opts.vertical then
        m.rule = UI.Hairline(m.holder, opts.rule or "gilt-line", "both")
        m.rule:Hide()
    end
    local top = CreateFrame("Frame", nil, m.holder)
    top:SetAllPoints()
    top:SetFrameLevel(m.holder:GetFrameLevel() + 2)
    m.jewel = UI.Diamond(top, opts.jewel or 5, "gilt")
    m.jewel:Hide()
    -- shown again after a change while hidden: placed at once
    row:HookScript("OnShow", function() m:Aim() end)
    return m
end
