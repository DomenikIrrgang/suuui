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

-- Text metrics taken in the space the text will actually render in, or nil for a child
-- that is not a font string. This never consults the region's own rect: a font string the
-- client has not laid out yet reports nothing, and one sized by an earlier pass is stale
-- the moment a fontSize token moves.
local function textBox(child)
    if child.GetStringHeight and child.GetFont and SuuUI.TextMetrics then
        local font, size, flags = child:GetFont()
        if font and size then
            return SuuUI.TextMetrics.Box(child:GetText() or "", font, size, flags)
        end
    end
    return nil
end

-- The width of a child's own content, free of whatever width a previous layout pinned
-- on it. A font string reports GetStringWidth clamped to its assigned width, so a label
-- that was first laid out while empty would keep reporting zero after its text arrives —
-- a real measurement is the only reading that survives a text change.
-- @param child frame|fontstring
-- @return number
function M.NaturalWidth(child)
    local tw = textBox(child)
    if tw then return tw end
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
        -- The client's own wrapped height comes first, so multi-line text re-flows.
        local h = child:GetStringHeight()
        if h and h > 0 then return pxceil(h) end
        -- It reports nothing for a font string it has not laid out — every label built
        -- inside a window that has never been shown is in that state. Measure rather than
        -- fall through to the region's rect, which reports zero and pins the label to zero
        -- height, where it silently never draws.
        local _, th = textBox(child)
        if th and th > 0 then return th end
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

-- The children that actually take part in the flow.
--
-- A hidden child must not hold a slot: it would keep its share of the main axis AND its
-- gap, leaving a hole in the middle of the row that nothing occupies. `IsShown` is the
-- right test rather than `IsVisible` — a child hidden because the whole panel is hidden
-- has not opted out of the layout, and skipping those would collapse every container the
-- moment its window closes.
--
-- Stack and anchor layouts deliberately do NOT do this: their children each occupy the
-- whole box independently, so a hidden one costs nothing, and skipping it would strand
-- components that hide a child and then resize it before showing it again (a progress
-- fill at 0% is exactly that).
-- @param children table
-- @return table, number  visible children, count
local function visibleChildren(children)
    local out, n = {}, 0
    for i = 1, #children do
        local c = children[i]
        if not c.IsShown or c:IsShown() then
            n = n + 1
            out[n] = c
        end
    end
    return out, n
end

M.visibleChildren = visibleChildren

-- Wrapping horizontal layout: positions children in lines, breaking when a child would
-- overflow the content width. `lineGap` separates lines (defaults to `gap`). When
-- `lineOrder` is "reverse" lines stack bottom-up so the first line is at the bottom
-- and new lines grow upward — useful for an aura band above a frame that keeps row 1
-- adjacent to the frame edge.
--
-- In a wrapping row, `width = "fill"` and `height = "fill"` are meaningless: fill
-- distributes leftover main-axis space, but a wrapping line has no fixed right edge to
-- distribute against. Both are treated as natural/auto width (the child's own size).
local function applyWrap(container, children, n)
    local pad     = container._padding
    local gap     = snap(container._gap or 0)
    local lineGap = snap(container._lineGap or gap)
    local cw      = pxfloor(max(0, (container._frame:GetWidth()  or 0) - pad.left - pad.right))
    local reverse = container._lineOrder == "reverse"

    -- First pass: partition children into lines and measure each line's height.
    local lines = {}          -- lines[i] = { children = {}, heights = {}, widths = {}, lineH = n }
    local curLine = { children = {}, heights = {}, widths = {}, lineH = 0 }
    local cursor = 0
    local lineChildCount = 0

    for _, child in ipairs(children) do
        local props = child._layoutProps or {}
        local align = props.align or container._align

        -- In a wrapping row, fill is natural width (no space to distribute)
        local childW
        if props.width == "fill" or props.width == "auto" then
            childW = M.NaturalWidth(child)
        elseif type(props.width) == "number" then
            childW = snap(props.width)
        else
            childW = snap(child:GetWidth() or 0)
        end

        local childH
        if type(props.height) == "number" then
            childH = snap(props.height)
        elseif align == "stretch" then
            childH = 0 -- resolved after line height is known
        else
            childH = naturalHeight(child, childW)
        end

        -- Break rule: if adding this child would exceed content width, start a new line.
        -- Exception: if this is the first child on the line it gets its own line regardless
        -- (a child wider than the container never infinite-loops).
        local widthWithGap = (lineChildCount > 0) and (cursor + gap + childW) or childW
        if lineChildCount > 0 and widthWithGap > cw then
            -- Finalise current line
            lines[#lines + 1] = curLine
            curLine = { children = {}, heights = {}, widths = {}, lineH = 0 }
            cursor = 0
            lineChildCount = 0
        end

        local idx = #curLine.children + 1
        curLine.children[idx] = child
        curLine.widths[idx] = childW
        curLine.heights[idx] = childH
        if childH > curLine.lineH then curLine.lineH = childH end

        cursor = (lineChildCount == 0) and childW or (cursor + gap + childW)
        lineChildCount = lineChildCount + 1
    end
    -- Last line
    if #curLine.children > 0 then
        lines[#lines + 1] = curLine
    end

    -- Resolve stretch heights now that line heights are known
    for _, line in ipairs(lines) do
        for i, child in ipairs(line.children) do
            local props = child._layoutProps or {}
            local align = props.align or container._align
            if align == "stretch" and line.heights[i] == 0 then
                line.heights[i] = line.lineH
            end
        end
    end

    -- Compute total content height for the container
    local totalH = pad.top + pad.bottom
    for i, line in ipairs(lines) do
        totalH = totalH + line.lineH
        if i < #lines then totalH = totalH + lineGap end
    end
    -- Store for GetContentSize
    container._wrapContentH = totalH

    -- Second pass: position children. Lines are iterated top-down for normal order,
    -- bottom-up for reversed order.
    local ch = pxfloor(max(0, (container._frame:GetHeight() or 0) - pad.top - pad.bottom))
    local lineCursor
    if reverse then
        -- First line at the bottom, new lines grow upward
        lineCursor = snap(pad.top + ch)
        for li = 1, #lines do
            local line = lines[li]
            lineCursor = lineCursor - line.lineH
            local xCursor = snap(pad.left)
            for i, child in ipairs(line.children) do
                local props = child._layoutProps or {}
                local align = props.align or container._align
                local childW = line.widths[i]
                local childH = line.heights[i]
                -- Cross-axis alignment resolves against THIS line's height
                local y = lineCursor + crossOffset(align, line.lineH, childH)
                child:SetSize(childW, childH)
                child:ClearAllPoints()
                child:SetPoint("TOPLEFT", container._frame, "TOPLEFT", xCursor, -y)
                xCursor = xCursor + childW + gap
            end
            if li < #lines then lineCursor = lineCursor - lineGap end
        end
    else
        lineCursor = snap(pad.top)
        for li = 1, #lines do
            local line = lines[li]
            local xCursor = snap(pad.left)
            for i, child in ipairs(line.children) do
                local props = child._layoutProps or {}
                local align = props.align or container._align
                local childW = line.widths[i]
                local childH = line.heights[i]
                local y = lineCursor + crossOffset(align, line.lineH, childH)
                child:SetSize(childW, childH)
                child:ClearAllPoints()
                child:SetPoint("TOPLEFT", container._frame, "TOPLEFT", xCursor, -y)
                xCursor = xCursor + childW + gap
            end
            lineCursor = lineCursor + line.lineH + lineGap
        end
    end
end

--- Applies flow layout to a container's children.
-- Child layout props: { width="fill"|"auto"|number, height="fill"|number, align="start"|"center"|"end"|"stretch" }
-- "fill" distributes remaining space on the main axis; "auto" hugs the child's own
-- content width (re-measured every pass); "stretch" fills the cross axis.
-- Hidden children are skipped entirely, so hiding one closes its gap.
-- @param container table  Container handle
function M.Apply(container)
    local children, n = visibleChildren(container._children)
    if n == 0 then return end

    -- Wrapping is horizontal only; vertical ignores the flag.
    if container._wrap and container._dir == "horizontal" then
        return applyWrap(container, children, n)
    end

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
