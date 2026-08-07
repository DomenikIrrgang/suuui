local ipairs = ipairs
local snap, pxfloor = SuuUI.Pixel.Snap, SuuUI.Pixel.Floor

local M = {}

-- Column widths for one grid, all on the pixel grid and summing to the space available.
--
-- Flooring an equal share loses up to cols-1 pixels, which would leave the last column
-- short of the right edge. The remainder is handed out one grid step at a time to the
-- leftmost columns instead, so the row reaches the edge and no column is more than one
-- step wider than another. Computed once for the whole grid rather than per row, so a
-- column is the same width all the way down.
local function columnWidths(container)
    local cols = container._cols or 2
    local pad  = container._padding
    local gap  = snap(container._gap or 0)
    local grid = SuuUI.Pixel.grid

    local avail = (container._frame:GetWidth() or 0) - pad.left - pad.right
                  - gap * (cols - 1)
    if avail < 0 then avail = 0 end

    local base  = pxfloor(avail / cols)
    local steps = (grid > 0) and math.floor((avail - base * cols) / grid + 1e-9) or 0

    local widths = {}
    for c = 1, cols do
        widths[c] = base + ((c <= steps) and grid or 0)
    end
    return widths, gap
end

M.columnWidths = columnWidths

--- Applies grid layout to a container's children.
-- @param container table  Needs _children, _padding, _gap, _cols
function M.Apply(container)
    local children = container._children
    local pad      = container._padding
    local cols     = container._cols or 2
    local widths, gap = columnWidths(container)

    local left  = snap(pad.left)
    local x, y  = left, -snap(pad.top)
    local col   = 1
    local rowH  = 0

    for _, child in ipairs(children) do
        local w = widths[col]
        child:SetWidth(w)
        child:ClearAllPoints()
        child:SetPoint("TOPLEFT", container._frame, "TOPLEFT", x, y)

        local h = snap(child:GetHeight() or 0)
        if h > rowH then rowH = h end

        if col >= cols then
            col  = 1
            x    = left
            y    = y - rowH - gap
            rowH = 0
        else
            x   = x + w + gap
            col = col + 1
        end
    end
end

SuuUI._GridLayout = M
