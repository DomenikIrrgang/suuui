-- UI/Layout.lua
-- Stacks and grids. A layout positions the children of one container and can
-- size the container to fit them. Changes only mark a layout dirty; all dirty
-- layouts are applied once, on the next frame, deepest container first, so a
-- build that adds fifty rows lays out once.
--
--   local stack = Layout.Stack(container, {
--       direction = "vertical",      -- or "horizontal"
--       gap = 4, padding = 12,       -- px; padding is a number or { left, right, top, bottom }
--       align = "start",             -- cross axis: start, center, end, stretch
--       autoSize = true,             -- true, "width", "height" or false
--   })
--   stack:Add(child[, { gapBefore = 8 }]); stack:Remove(child); stack:Invalidate()
--
--   local grid = Layout.Grid(container, { columns = 4, cellWidth = 36, cellHeight = 36, gap = 4, padding = 0 })
--
-- A child reports a changed size by itself: frames through OnSizeChanged and
-- OnShow/OnHide, SuuUI texts through SetValue and SetVisible. A container
-- holding protected frames is laid out after combat.

local _, ns = ...

local Layout = {}
ns.Layout = Layout

local Combat = ns.Combat
local isSecret = issecretvalue or function() return false end

local pending = {}
local flusher = CreateFrame("Frame")
flusher:Hide()

local function depth(frame)
    local d, p = 0, frame:GetParent()
    while p do
        d = d + 1
        p = p:GetParent()
    end
    return d
end

flusher:SetScript("OnUpdate", function(self)
    self:Hide()
    -- A container that grows dirties the layout it sits in; settle in a few passes.
    for _ = 1, 8 do
        if not next(pending) then return end
        local list = {}
        for l in pairs(pending) do list[#list + 1] = l end
        pending = {}
        table.sort(list, function(a, b) return a.depth > b.depth end)
        for _, l in ipairs(list) do l:ApplyNow() end
    end
end)

local function padding(p)
    if type(p) == "table" then
        return { left = p[1] or p.left or 0, right = p[2] or p.right or 0, top = p[3] or p.top or 0, bottom = p[4] or p.bottom or 0 }
    end
    p = p or 0
    return { left = p, right = p, top = p, bottom = p }
end

local function number(v, fallback)
    if v == nil or isSecret(v) then return fallback or 0 end
    return v
end

-- A child's size: its own GetLayoutSize, a text's natural size, or its frame size.
local function measure(child)
    if child.GetLayoutSize then return child:GetLayoutSize() end
    if child:GetObjectType() == "FontString" then
        local w = child.fixedWidth or number(child:GetUnboundedStringWidth())
        return w, number(child:GetStringHeight())
    end
    return number(child:GetWidth()), number(child:GetHeight())
end

--------------------------------------------------------------------------------
-- Shared behaviour
--------------------------------------------------------------------------------

local Base = {}

function Base:Invalidate()
    pending[self] = true
    flusher:Show()
end

local function onChildChanged(child, w, h)
    local l = child.layout
    if not l or l.applying then return end
    if w ~= nil then
        -- Ignore the echo of a size this layout itself caused.
        if isSecret(w) or isSecret(h) then return end
        local lw, lh = child.suuLayoutW, child.suuLayoutH
        if l.stretches then
            if l.direction == "vertical" and lh == h then return end
            if l.direction == "horizontal" and lw == w then return end
        elseif lw == w and lh == h then
            return
        end
    end
    l:Invalidate()
end

function Base:Add(child, opts)
    child.layout = self
    child.layoutOpts = opts
    self.children[#self.children + 1] = child
    if child.HookScript and not child.suuLayoutHooked then
        child.suuLayoutHooked = true
        child:HookScript("OnSizeChanged", onChildChanged)
        child:HookScript("OnShow", function(c) onChildChanged(c) end)
        child:HookScript("OnHide", function(c) onChildChanged(c) end)
    end
    self:Invalidate()
    return child
end

function Base:Remove(child)
    for i, c in ipairs(self.children) do
        if c == child then
            table.remove(self.children, i)
            child.layout = nil
            self:Invalidate()
            return
        end
    end
end

function Base:Clear()
    for _, c in ipairs(self.children) do c.layout = nil end
    wipe(self.children)
    self:Invalidate()
end

function Base:ApplyNow()
    local c = self.container
    if InCombatLockdown() and c:IsProtected() then
        Combat.Run("layout:" .. tostring(self), function() self:ApplyNow() end, "Layout")
        return
    end
    self.applying = true
    local w, h = self:Arrange()
    self.applying = false
    local a = self.autoSize
    local changed = false
    if (a == true or a == "width") and number(c:GetWidth()) ~= w then
        c:SetWidth(w)
        changed = true
    end
    if (a == true or a == "height") and number(c:GetHeight()) ~= h then
        c:SetHeight(h)
        changed = true
    end
    -- A container that changed size tells the layout it sits in.
    if changed and c.layout then c.layout:Invalidate() end
end

local function new(kind, container, opts)
    opts = opts or {}
    local l = setmetatable({
        container = container,
        children = {},
        gap = opts.gap or 0,
        padding = padding(opts.padding),
        autoSize = opts.autoSize == nil and true or opts.autoSize,
        depth = depth(container),
    }, { __index = kind })
    return l, opts
end

--------------------------------------------------------------------------------
-- Stack
--------------------------------------------------------------------------------

local Stack = setmetatable({}, { __index = Base })

function Stack:Arrange()
    local c, p, vertical = self.container, self.padding, self.direction == "vertical"
    local items, cross = {}, 0
    for _, child in ipairs(self.children) do
        if child:IsShown() then
            local w, h = measure(child)
            items[#items + 1] = { child = child, w = w, h = h }
            cross = math.max(cross, vertical and w or h)
        end
    end
    -- With a fixed cross size, align against it rather than the widest child.
    local a = self.autoSize
    if vertical and not (a == true or a == "width") then
        cross = number(c:GetWidth()) - p.left - p.right
    elseif not vertical and not (a == true or a == "height") then
        cross = number(c:GetHeight()) - p.top - p.bottom
    end

    local pos = 0
    for i, it in ipairs(items) do
        local child, w, h = it.child, it.w, it.h
        if i > 1 then
            local o = child.layoutOpts
            pos = pos + (o and o.gapBefore or self.gap)
        end
        local size = vertical and w or h
        local offset = 0
        if self.align == "center" then
            offset = (cross - size) / 2
        elseif self.align == "end" then
            offset = cross - size
        end
        child:ClearAllPoints()
        if vertical then
            child:SetPoint("TOPLEFT", c, "TOPLEFT", p.left + offset, -(p.top + pos))
            if self.align == "stretch" then child:SetPoint("TOPRIGHT", c, "TOPRIGHT", -p.right, -(p.top + pos)) end
            pos = pos + h
        else
            child:SetPoint("TOPLEFT", c, "TOPLEFT", p.left + pos, -(p.top + offset))
            if self.align == "stretch" then child:SetPoint("BOTTOMLEFT", c, "BOTTOMLEFT", p.left + pos, p.bottom) end
            pos = pos + w
        end
        child.suuLayoutW, child.suuLayoutH = w, h
    end

    if vertical then
        return cross + p.left + p.right, pos + p.top + p.bottom
    end
    return pos + p.left + p.right, cross + p.top + p.bottom
end

function Layout.Stack(container, opts)
    local l
    l, opts = new(Stack, container, opts)
    l.direction = opts.direction or "vertical"
    l.align = opts.align or "start"
    l.stretches = l.align == "stretch"
    return l
end

--------------------------------------------------------------------------------
-- Grid: fixed cells filled row by row.
--------------------------------------------------------------------------------

local Grid = setmetatable({}, { __index = Base })

function Grid:Arrange()
    local c, p = self.container, self.padding
    local cw, ch, cols = self.cellWidth, self.cellHeight, self.columns
    local n = 0
    for _, child in ipairs(self.children) do
        if child:IsShown() then
            local col, row = n % cols, math.floor(n / cols)
            child:ClearAllPoints()
            child:SetPoint("TOPLEFT", c, "TOPLEFT", p.left + col * (cw + self.gap), -(p.top + row * (ch + self.gap)))
            child.suuLayoutW, child.suuLayoutH = measure(child)
            n = n + 1
        end
    end
    local usedCols = math.min(n, cols)
    local rows = math.ceil(n / cols)
    local w = usedCols * cw + math.max(0, usedCols - 1) * self.gap
    local h = rows * ch + math.max(0, rows - 1) * self.gap
    return w + p.left + p.right, h + p.top + p.bottom
end

function Layout.Grid(container, opts)
    local l
    l, opts = new(Grid, container, opts)
    l.columns = opts.columns or 1
    l.cellWidth = opts.cellWidth or 32
    l.cellHeight = opts.cellHeight or l.cellWidth
    return l
end
