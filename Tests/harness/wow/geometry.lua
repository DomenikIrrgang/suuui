-- Anchor-graph geometry solver.
--
-- WoW derives a widget's on-screen rect from its anchor points plus, where the
-- anchors do not pin both edges of an axis, its explicitly set size. This resolves
-- the same way so tests can assert real pixel positions rather than intentions.
--
-- Coordinate space matches WoW: origin bottom-left of the screen, y grows upward,
-- SetPoint y offsets are positive-up.
local M = {}

local abs, floor = math.abs, math.floor

-- point name -> { xFraction, yFraction } within the widget's own box
local POINTS = {
    TOPLEFT     = { 0,   1   },
    TOP         = { 0.5, 1   },
    TOPRIGHT    = { 1,   1   },
    LEFT        = { 0,   0.5 },
    CENTER      = { 0.5, 0.5 },
    RIGHT       = { 1,   0.5 },
    BOTTOMLEFT  = { 0,   0   },
    BOTTOM      = { 0.5, 0   },
    BOTTOMRIGHT = { 1,   0   },
}

M.POINTS = POINTS

--- Returns the x/y fractions for an anchor point name, or nil when unknown.
-- @param name string
-- @return number, number
function M.fractions(name)
    local p = POINTS[(name or "TOPLEFT"):upper()]
    if not p then return nil end
    return p[1], p[2]
end

-- Bumped on every geometry mutation so cached rects invalidate in one step.
local generation = 0

--- Invalidates every cached rect.
function M.invalidate()
    generation = generation + 1
end

--- Returns the current generation counter (used by callers that cache).
function M.generation()
    return generation
end

-- Solves one axis from the collected anchor equations.
-- Each equation is { frac = f, value = v } meaning: pos + f * size == v.
-- Two equations with different fracs pin both edges and therefore derive the size.
local function solveAxis(eqs, explicitSize)
    local n = #eqs
    if n == 0 then return nil, explicitSize, false end

    local lo, hi = eqs[1], eqs[1]
    for i = 2, n do
        if eqs[i].frac < lo.frac then lo = eqs[i] end
        if eqs[i].frac > hi.frac then hi = eqs[i] end
    end

    if hi.frac - lo.frac > 1e-9 then
        local size = (hi.value - lo.value) / (hi.frac - lo.frac)
        if size < 0 then size = 0 end
        return lo.value - lo.frac * size, size, true
    end

    local size = explicitSize or 0
    return lo.value - lo.frac * size, size, false
end

--- Resolves a widget's screen rect.
-- Returns nil when the widget has no resolvable anchor chain, mirroring WoW, where
-- GetLeft() on an unanchored frame returns nil.
-- @param widget table
-- @return table|nil  { left, bottom, width, height }
function M.resolve(widget)
    if not widget then return nil end

    if widget._cacheGen == generation then return widget._cacheRect end
    if widget._resolving then return nil end

    widget._resolving = true

    local rect
    if widget._isScreenRoot then
        rect = { left = 0, bottom = 0, width = widget._w or 0, height = widget._h or 0 }
    else
        local xEqs, yEqs = {}, {}
        for _, p in ipairs(widget._points or {}) do
            local rel = p.relativeTo or widget._parent
            local relRect = rel and M.resolve(rel) or nil
            if relRect then
                local mfx, mfy = M.fractions(p.point)
                local rfx, rfy = M.fractions(p.relativePoint)
                if mfx and rfx then
                    xEqs[#xEqs + 1] = {
                        frac = mfx,
                        value = relRect.left + rfx * relRect.width + (p.x or 0),
                    }
                    yEqs[#yEqs + 1] = {
                        frac = mfy,
                        value = relRect.bottom + rfy * relRect.height + (p.y or 0),
                    }
                end
            end
        end

        if #xEqs == 0 and #yEqs == 0 then
            rect = nil
        else
            local left, width, derivedW   = solveAxis(xEqs, widget._w)
            local bottom, height, derivedH = solveAxis(yEqs, widget._h)
            rect = {
                left     = left,
                bottom   = bottom,
                width    = width  or widget._w or 0,
                height   = height or widget._h or 0,
                derivedW = derivedW,
                derivedH = derivedH,
            }
        end
    end

    widget._resolving = false
    widget._cacheGen  = generation
    widget._cacheRect = rect
    return rect
end

--- Resolved width: derived from opposing anchors when present, else the set width.
-- @param widget table
-- @return number
function M.width(widget)
    local r = M.resolve(widget)
    if r and r.derivedW then return r.width end
    return widget._w or (r and r.width) or 0
end

--- Resolved height: derived from opposing anchors when present, else the set height.
-- @param widget table
-- @return number
function M.height(widget)
    local r = M.resolve(widget)
    if r and r.derivedH then return r.height end
    return widget._h or (r and r.height) or 0
end

--- True when both edges of the horizontal axis are pinned by anchors.
function M.hasDerivedWidth(widget)
    local r = M.resolve(widget)
    return (r and r.derivedW) == true
end

--- True when both edges of the vertical axis are pinned by anchors.
function M.hasDerivedHeight(widget)
    local r = M.resolve(widget)
    return (r and r.derivedH) == true
end

--- Screen-space edges. Return nil for a widget with no resolvable anchors.
function M.left(widget)   local r = M.resolve(widget) return r and r.left end
function M.bottom(widget) local r = M.resolve(widget) return r and r.bottom end
function M.right(widget)  local r = M.resolve(widget) return r and (r.left + r.width) end
function M.top(widget)    local r = M.resolve(widget) return r and (r.bottom + r.height) end

--- Returns a widget's rect as left/top/width/height with top measured downward from
-- the screen top. Handy for asserting layout results, which are all TOPLEFT-based.
-- @param widget table
-- @param screenHeight number
-- @return table|nil  { left, top, width, height, right, bottom }
function M.boxFromTop(widget, screenHeight)
    local r = M.resolve(widget)
    if not r then return nil end
    return {
        left   = r.left,
        top    = screenHeight - (r.bottom + r.height),
        width  = r.width,
        height = r.height,
        right  = r.left + r.width,
        bottom = screenHeight - r.bottom,
    }
end

--- Offset of a child's top-left corner from its ancestor's top-left corner.
-- This is the frame of reference the layout engine works in, so it is the natural
-- unit for layout assertions.
-- @param child table
-- @param ancestor table
-- @return number, number  dx (rightward), dy (downward, positive)
function M.offsetFrom(child, ancestor)
    local c = M.resolve(child)
    local a = M.resolve(ancestor)
    if not (c and a) then return nil, nil end
    local dx = c.left - a.left
    local dy = (a.bottom + a.height) - (c.bottom + c.height)
    return dx, dy
end

--- True when the child's rect lies entirely within the ancestor's rect.
-- @param child table
-- @param ancestor table
-- @param tol number
function M.containsRect(outer, inner, tol)
    tol = tol or 0.01
    local o, i = M.resolve(outer), M.resolve(inner)
    if not (o and i) then return false end
    return i.left >= o.left - tol
       and i.bottom >= o.bottom - tol
       and (i.left + i.width) <= (o.left + o.width) + tol
       and (i.bottom + i.height) <= (o.bottom + o.height) + tol
end

--- True when two widget rects overlap by more than tol on both axes.
function M.overlaps(a, b, tol)
    tol = tol or 0.01
    local ra, rb = M.resolve(a), M.resolve(b)
    if not (ra and rb) then return false end
    local xOver = math.min(ra.left + ra.width, rb.left + rb.width) - math.max(ra.left, rb.left)
    local yOver = math.min(ra.bottom + ra.height, rb.bottom + rb.height) - math.max(ra.bottom, rb.bottom)
    return xOver > tol and yOver > tol
end

return M
