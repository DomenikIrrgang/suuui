local type, ipairs, max = type, ipairs, math.max
local snap, pxfloor = SuuUI.Pixel.Snap, SuuUI.Pixel.Floor

local M = {}

local function insetOf(props)
    local i = props.inset
    if type(i) == "number" then
        return i, i, i, i
    elseif type(i) == "table" then
        return i.top or 0, i.right or 0, i.bottom or 0, i.left or 0
    end
    return 0, 0, 0, 0
end

-- A font string's natural size comes from its text and font, never from its current
-- rect. A region the client has not laid out yet reports 0, and one sized by an earlier
-- pass is stale the moment a fontSize token changes — either way, pinning that number
-- gives the string a box smaller than its glyphs and the client clips them.
local function naturalSize(child)
    if child.GetStringHeight and child.GetFont then
        local font, size, flags = child:GetFont()
        if font and size then
            return SuuUI.TextMetrics.Measure(child:GetText(), font, size, flags)
        end
    end
    return child:GetWidth() or 0, child:GetHeight() or 0
end

-- Resolves one axis: returns offset from the box start and the child's size.
-- Centring halves an odd difference, which is the one place this strategy leaves the
-- pixel grid, so the offset is snapped back onto it.
local function axis(align, boxSize, natural, explicit)
    if align == "stretch" or align == nil then
        return 0, boxSize
    end
    local size = snap(explicit or natural or 0)
    if align == "center" then
        return snap(max(0, (boxSize - size) / 2)), size
    elseif align == "end" then
        return max(0, boxSize - size), size
    end
    return 0, size
end

--- Applies stack layout: every child occupies the container box, offset by its inset.
-- Child layout props:
--   inset  = number | { top, right, bottom, left }  space from the container edges
--   align  = "start"|"center"|"end"|"stretch"  horizontal placement (default "stretch")
--   valign = "start"|"center"|"end"|"stretch"  vertical placement (default "stretch")
--   width / height = number  explicit size when the matching axis is not stretched
-- Use this for backgrounds, overlays, centred labels, and edge-spanning children.
-- @param container table  Container handle
function M.Apply(container)
    local pad = container._padding
    -- Floor rather than snap: the content box must never round up past the frame it
    -- sits in. Everything downstream derives from these, so the whole strategy stays on
    -- the grid once they are.
    local cw  = pxfloor(max(0, (container._frame:GetWidth()  or 0) - pad.left - pad.right))
    local chh = pxfloor(max(0, (container._frame:GetHeight() or 0) - pad.top  - pad.bottom))

    for _, child in ipairs(container._children) do
        local props = child._layoutProps or {}
        local it, ir, ib, il = insetOf(props)

        local boxW = max(0, cw - snap(il) - snap(ir))
        local boxH = max(0, chh - snap(it) - snap(ib))

        local alignH = props.align  or container._align
        local alignV = props.valign or container._valign

        -- Only measure when an axis actually needs a natural size
        local nw, nh
        if (alignH and alignH ~= "stretch" and not props.width)
        or (alignV and alignV ~= "stretch" and not props.height) then
            nw, nh = naturalSize(child)
        end

        local dx, w = axis(alignH, boxW, nw, props.width)
        local dy, h = axis(alignV, boxH, nh, props.height)

        child:SetSize(w, h)
        child:ClearAllPoints()
        child:SetPoint("TOPLEFT", container._frame, "TOPLEFT",
            snap(pad.left + il + dx), -snap(pad.top + it + dy))
    end
end

--- Returns the bounding size of a stack container's children.
-- @param container table
-- @return number, number
function M.ContentSize(container)
    local pad = container._padding
    local maxW, maxH = 0, 0
    for _, child in ipairs(container._children) do
        local props = child._layoutProps or {}
        local it, ir, ib, il = insetOf(props)
        local nw, nh
        if not (props.width and props.height) then nw, nh = naturalSize(child) end
        maxW = max(maxW, snap(props.width  or nw or 0) + snap(il) + snap(ir))
        maxH = max(maxH, snap(props.height or nh or 0) + snap(it) + snap(ib))
    end
    -- Ceil: a hugging container must not round below the content it wraps, or the client
    -- clips the last row of glyphs.
    return SuuUI.Pixel.Ceil(maxW + pad.left + pad.right),
           SuuUI.Pixel.Ceil(maxH + pad.top + pad.bottom)
end

SuuUI._StackLayout = M
