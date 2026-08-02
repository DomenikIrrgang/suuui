local type, ipairs, max = type, ipairs, math.max

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

-- Resolves one axis: returns offset from the box start and the child's size.
local function axis(align, boxSize, natural, explicit)
    if align == "stretch" or align == nil then
        return 0, boxSize
    end
    local size = explicit or natural or 0
    if align == "center" then
        return max(0, (boxSize - size) / 2), size
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
    local cw  = max(0, (container._frame:GetWidth()  or 0) - pad.left - pad.right)
    local chh = max(0, (container._frame:GetHeight() or 0) - pad.top  - pad.bottom)

    for _, child in ipairs(container._children) do
        local props = child._layoutProps or {}
        local it, ir, ib, il = insetOf(props)

        local boxW = max(0, cw - il - ir)
        local boxH = max(0, chh - it - ib)

        local dx, w = axis(props.align  or container._align,  boxW, child:GetWidth(),  props.width)
        local dy, h = axis(props.valign or container._valign, boxH, child:GetHeight(), props.height)

        child:SetSize(w, h)
        child:ClearAllPoints()
        child:SetPoint("TOPLEFT", container._frame, "TOPLEFT",
            pad.left + il + dx, -(pad.top + it + dy))
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
        maxW = max(maxW, (props.width  or child:GetWidth()  or 0) + il + ir)
        maxH = max(maxH, (props.height or child:GetHeight() or 0) + it + ib)
    end
    return maxW + pad.left + pad.right, maxH + pad.top + pad.bottom
end

SuuUI._StackLayout = M
