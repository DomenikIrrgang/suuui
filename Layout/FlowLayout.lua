local type, ipairs, max = type, ipairs, math.max

local M = {}

local function crossOffset(align, available, childSize)
    if align == "center" then
        return max(0, (available - childSize) / 2)
    elseif align == "end" then
        return max(0, available - childSize)
    end
    return 0
end

local function resolveWidth(child, props, align, cw, vertical, fillSize)
    if props.width == "fill" then
        return vertical and cw or (fillSize or 0)
    elseif type(props.width) == "number" then
        return props.width
    elseif vertical and align == "stretch" then
        return cw
    end
    return child:GetWidth() or 0
end

-- A font string's height depends on the width the layout gives it, and on the font
-- size token, which changes at runtime. Assign the width first, then read the
-- measured string height back rather than trusting a previously pinned height.
local function naturalHeight(child, childW)
    if child.GetStringHeight then
        if childW and childW > 0 then child:SetWidth(childW) end
        local h = child:GetStringHeight()
        if h and h > 0 then return h end
    end
    return child:GetHeight() or 0
end

--- Applies flow layout to a container's children.
-- Child layout props: { width="fill"|number, height="fill"|number, align="start"|"center"|"end"|"stretch" }
-- "fill" distributes remaining space on the main axis; "stretch" fills the cross axis.
-- @param container table  Container handle
function M.Apply(container)
    local children = container._children
    local n        = #children
    if n == 0 then return end

    local pad      = container._padding
    local gap      = container._gap or 0
    local vertical = container._dir ~= "horizontal"
    local cw       = max(0, (container._frame:GetWidth()  or 0) - pad.left - pad.right)
    local ch       = max(0, (container._frame:GetHeight() or 0) - pad.top  - pad.bottom)

    -- First pass: measure fixed children so remaining space can be split
    local fillCount, usedSpace = 0, 0
    for _, child in ipairs(children) do
        local props = child._layoutProps or {}
        local mainProp = vertical and props.height or props.width
        if mainProp == "fill" then
            fillCount = fillCount + 1
        elseif type(mainProp) == "number" then
            usedSpace = usedSpace + mainProp
        elseif vertical then
            local align = props.align or container._align
            usedSpace = usedSpace
                + naturalHeight(child, resolveWidth(child, props, align, cw, true, nil))
        else
            usedSpace = usedSpace + (child:GetWidth() or 0)
        end
    end

    local totalGap   = gap * (n - 1)
    local availSpace = (vertical and ch or cw) - usedSpace - totalGap
    local fillSize   = (fillCount > 0) and max(0, availSpace / fillCount) or 0

    -- Second pass: size and position
    local cursor = vertical and pad.top or pad.left
    for _, child in ipairs(children) do
        local props = child._layoutProps or {}
        local align = props.align or container._align
        local childW = resolveWidth(child, props, align, cw, vertical, fillSize)
        local childH

        if props.height == "fill" then
            childH = vertical and fillSize or ch
        elseif type(props.height) == "number" then
            childH = props.height
        elseif not vertical and align == "stretch" then
            childH = ch
        else
            childH = naturalHeight(child, childW)
        end

        child:SetSize(childW, childH)
        child:ClearAllPoints()

        if vertical then
            local x = pad.left + crossOffset(align, cw, childW)
            child:SetPoint("TOPLEFT", container._frame, "TOPLEFT", x, -cursor)
            cursor = cursor + childH + gap
        else
            local y = pad.top + crossOffset(align, ch, childH)
            child:SetPoint("TOPLEFT", container._frame, "TOPLEFT", cursor, -y)
            cursor = cursor + childW + gap
        end
    end
end

SuuUI._FlowLayout = M
