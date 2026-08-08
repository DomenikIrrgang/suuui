local type, ipairs, max = type, ipairs, math.max
local floor = math.floor
local snap, pxfloor, pxceil = SuuUI.Pixel.Snap, SuuUI.Pixel.Floor, SuuUI.Pixel.Ceil

local M = {}

-- Centring halves an odd difference, so the offset is snapped back onto the pixel grid.
local function crossOffset(align, available, childSize)
    if align == "center" then
        return snap(max(0, (available - childSize) / 2))
    elseif align == "end" then
        return max(0, available - childSize)
    end
    return 0
end

-- The width of a child's own content, free of whatever width a previous layout pinned
-- on it. A font string reports GetStringWidth clamped to its assigned width, so a label
-- that was first laid out while empty would keep reporting zero after its text arrives —
-- the unbounded measurement is the only reading that survives a text change.
-- @param child frame|fontstring
-- @return number
function M.NaturalWidth(child)
    if child.GetUnboundedStringWidth then
        return pxceil(child:GetUnboundedStringWidth() or 0)
    elseif child.GetStringWidth then
        return pxceil(child:GetStringWidth() or 0)
    end
    return snap(child:GetWidth() or 0)
end

local function resolveWidth(child, props, align, cw, vertical, fillSize)
    if props.width == "fill" then
        return vertical and cw or (fillSize or 0)
    elseif props.width == "auto" then
        return M.NaturalWidth(child)
    elseif type(props.width) == "number" then
        return snap(props.width)
    elseif vertical and align == "stretch" then
        return cw
    end
    return snap(child:GetWidth() or 0)
end

-- A font string's height depends on the width the layout gives it, and on the font
-- size token, which changes at runtime. Assign the width first, then read the
-- measured string height back rather than trusting a previously pinned height.
-- Ceil, not round: half a pixel short and the client clips the descenders.
local function naturalHeight(child, childW)
    if child.GetStringHeight then
        if childW and childW > 0 then child:SetWidth(childW) end
        local h = child:GetStringHeight()
        if h and h > 0 then return pxceil(h) end
    end
    return snap(child:GetHeight() or 0)
end

-- Splits the leftover main-axis space between the "fill" children, on the pixel grid.
--
-- Flooring an equal share loses up to fillCount-1 pixels, which shows up as the last
-- child in a filled row or column stopping short of the edge. The remainder is handed
-- out one grid step at a time instead, so the run reaches the edge and no two fill
-- children differ by more than a step.
-- @return number, number  base size, number of children that get one extra step
local function fillShare(availSpace, fillCount)
    if fillCount <= 0 then return 0, 0 end
    if availSpace <= 0 then return 0, 0 end
    local grid  = SuuUI.Pixel.grid
    local base  = pxfloor(availSpace / fillCount)
    local steps = (grid > 0) and floor((availSpace - base * fillCount) / grid + 1e-9) or 0
    if steps > fillCount then steps = fillCount end
    return base, steps
end

--- Applies flow layout to a container's children.
-- Child layout props: { width="fill"|"auto"|number, height="fill"|number, align="start"|"center"|"end"|"stretch" }
-- "fill" distributes remaining space on the main axis; "auto" hugs the child's own
-- content width (re-measured every pass); "stretch" fills the cross axis.
-- @param container table  Container handle
function M.Apply(container)
    local children = container._children
    local n        = #children
    if n == 0 then return end

    local pad      = container._padding
    local gap      = snap(container._gap or 0)
    local vertical = container._dir ~= "horizontal"
    -- Floor: the content box must never round up past the frame that holds it.
    local cw       = pxfloor(max(0, (container._frame:GetWidth()  or 0) - pad.left - pad.right))
    local ch       = pxfloor(max(0, (container._frame:GetHeight() or 0) - pad.top  - pad.bottom))

    -- First pass: measure fixed children so remaining space can be split
    local fillCount, usedSpace = 0, 0
    for _, child in ipairs(children) do
        local props = child._layoutProps or {}
        local mainProp = vertical and props.height or props.width
        if mainProp == "fill" then
            fillCount = fillCount + 1
        elseif type(mainProp) == "number" then
            usedSpace = usedSpace + snap(mainProp)
        elseif vertical then
            local align = props.align or container._align
            usedSpace = usedSpace
                + naturalHeight(child, resolveWidth(child, props, align, cw, true, nil))
        else
            -- Routed through resolveWidth so a content-hug child is measured here too:
            -- summing its stale pinned width would mis-budget the row's fill space.
            usedSpace = usedSpace
                + resolveWidth(child, props, props.align or container._align, cw, false, nil)
        end
    end

    local totalGap   = gap * (n - 1)
    local availSpace = (vertical and ch or cw) - usedSpace - totalGap
    local fillBase, fillSteps = fillShare(availSpace, fillCount)
    local gridStep   = SuuUI.Pixel.grid

    -- Second pass: size and position
    local cursor = snap(vertical and pad.top or pad.left)
    local crossBase = snap(vertical and pad.left or pad.top)
    for _, child in ipairs(children) do
        local props = child._layoutProps or {}
        local align = props.align or container._align

        -- Each fill child takes the base share; the first `fillSteps` of them take one
        -- extra grid step so the run still lands exactly on the far edge.
        local fillSize = fillBase
        if (vertical and props.height or props.width) == "fill" and fillSteps > 0 then
            fillSize  = fillBase + gridStep
            fillSteps = fillSteps - 1
        end

        local childW = resolveWidth(child, props, align, cw, vertical, fillSize)
        local childH

        if props.height == "fill" then
            childH = vertical and fillSize or ch
        elseif type(props.height) == "number" then
            childH = snap(props.height)
        elseif not vertical and align == "stretch" then
            childH = ch
        else
            childH = naturalHeight(child, childW)
        end

        child:SetSize(childW, childH)
        child:ClearAllPoints()

        if vertical then
            local x = crossBase + crossOffset(align, cw, childW)
            child:SetPoint("TOPLEFT", container._frame, "TOPLEFT", x, -cursor)
            cursor = cursor + childH + gap
        else
            local y = crossBase + crossOffset(align, ch, childH)
            child:SetPoint("TOPLEFT", container._frame, "TOPLEFT", cursor, -y)
            cursor = cursor + childW + gap
        end
    end
end

SuuUI._FlowLayout = M
