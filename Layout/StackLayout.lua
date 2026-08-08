local type, ipairs, max, min = type, ipairs, math.max, math.min
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
local function axis(align, boxSize, natural, explicit, fraction)
    -- A fractional child takes its size FROM the box, so it resolves before stretch:
    -- "stretch with a fraction" means a fraction of the box it would have stretched to.
    -- Floor, never snap: a fill must not round up past the track it sits in.
    if type(fraction) == "number" then
        local fr = fraction
        if fr < 0 then fr = 0 elseif fr > 1 then fr = 1 end
        local size = pxfloor(max(0, boxSize * fr))
        if align == "center" then
            return snap(max(0, (boxSize - size) / 2)), size
        elseif align == "end" then
            return max(0, boxSize - size), size
        end
        return 0, size
    end

    if align == "stretch" or align == nil then
        return 0, boxSize
    end
    -- Only a number describes a size on this axis. Keywords like "fill" belong to flow
    -- layout, and handing one to the pixel grid would throw on a string arithmetic.
    local size = snap(type(explicit) == "number" and explicit or natural or 0)
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
--   widthFraction / heightFraction = 0..1  size as a share of the inner box on that
--     axis, recomputed every pass. This is what a progress fill needs: a bar that is
--     60% full is 60% of whatever width the container currently has, so the fill has no
--     business anchoring itself. Overrides width/height and stretch on the same axis;
--     placement still follows align/valign (default "start", i.e. left/top-aligned).
-- Use this for backgrounds, overlays, centred labels, edge-spanning children, and fills.
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
        local frW, frH = props.widthFraction, props.heightFraction

        -- Only measure when an axis actually needs a natural size. A fractional axis
        -- never does: its size comes from the box.
        local nw, nh
        if (alignH and alignH ~= "stretch" and not props.width  and not frW)
        or (alignV and alignV ~= "stretch" and not props.height and not frH) then
            nw, nh = naturalSize(child)
        end

        local dx, w = axis(alignH, boxW, nw, props.width,  frW)
        local dy, h = axis(alignV, boxH, nh, props.height, frH)

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
        -- A fractional child is sized FROM the box, so measuring it here would ask the
        -- container to hug something that is defined by the container. It contributes
        -- nothing on that axis.
        local exW = type(props.width)  == "number" and props.width  or nil
        local exH = type(props.height) == "number" and props.height or nil
        local frW = type(props.widthFraction)  == "number"
        local frH = type(props.heightFraction) == "number"

        local nw, nh
        if not ((exW or frW) and (exH or frH)) then nw, nh = naturalSize(child) end

        local cw = frW and 0 or snap(exW or nw or 0)
        local ch = frH and 0 or snap(exH or nh or 0)
        maxW = max(maxW, cw + snap(il) + snap(ir))
        maxH = max(maxH, ch + snap(it) + snap(ib))
    end
    -- Ceil: a hugging container must not round below the content it wraps, or the client
    -- clips the last row of glyphs.
    return SuuUI.Pixel.Ceil(maxW + pad.left + pad.right),
           SuuUI.Pixel.Ceil(maxH + pad.top + pad.bottom)
end

SuuUI._StackLayout = M
