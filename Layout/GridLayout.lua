local M = {}

--- Applies grid layout to a container's children.
-- @param container table  Needs _children, _padding, _gap, _cols
function M.Apply(container)
    local children = container._children
    local pad      = container._padding
    local gap      = container._gap or 0
    local cols     = container._cols or 2
    local cw       = (container._frame:GetWidth() - pad.left - pad.right - gap * (cols - 1)) / cols
    local x, y     = pad.left, -pad.top
    local col      = 0

    for _, child in ipairs(children) do
        child:SetWidth(cw)
        child:ClearAllPoints()
        child:SetPoint("TOPLEFT", container._frame, "TOPLEFT", x, y)
        col = col + 1
        if col >= cols then
            col = 0
            x   = pad.left
            y   = y - child:GetHeight() - gap
        else
            x = x + cw + gap
        end
    end
end

SuuUI._GridLayout = M
