local type = type

local M = {}

--- Applies flow layout to a container's children.
-- Supports flexible sizing via child._layoutProps = { width="fill"|number, height="fill"|number }
-- @param container table  Container handle with _children, _padding, _gap, _dir
function M.Apply(container)
    local children = container._children
    local pad      = container._padding
    local gap      = container._gap or 0
    local vertical = container._dir ~= "horizontal"
    local cw       = container._frame:GetWidth() - pad.left - pad.right
    local ch       = container._frame:GetHeight() - pad.top - pad.bottom
    
    -- First pass: count fill children and calculate fixed sizes
    local fillCount = 0
    local usedSpace = 0
    for _, child in ipairs(children) do
        local props = child._layoutProps or {}
        if vertical then
            if props.height == "fill" then
                fillCount = fillCount + 1
            else
                usedSpace = usedSpace + child:GetHeight()
            end
        else
            if props.width == "fill" then
                fillCount = fillCount + 1
            else
                usedSpace = usedSpace + child:GetWidth()
            end
        end
    end
    
    local totalGap = gap * (#children - 1)
    local availSpace = (vertical and ch or cw) - usedSpace - totalGap
    local fillSize = fillCount > 0 and (availSpace / fillCount) or 0
    
    -- Second pass: position and size children
    local x, y = pad.left, -pad.top
    for _, child in ipairs(children) do
        local props = child._layoutProps or {}
        local childW, childH
        
        -- Apply flexible width (cw already accounts for left+right padding)
        if props.width == "fill" then
            childW = cw
        elseif type(props.width) == "number" then
            childW = props.width
        else
            childW = child:GetWidth()
        end
        
        -- Apply flexible height (ch already accounts for top+bottom padding)
        if props.height == "fill" then
            childH = vertical and fillSize or ch
        elseif type(props.height) == "number" then
            childH = props.height
        else
            childH = child:GetHeight()
        end
        
        child:SetSize(childW, childH)
        child:ClearAllPoints()
        child:SetPoint("TOPLEFT", container._frame, "TOPLEFT", x, y)
        
        if vertical then
            y = y - childH - gap
        else
            x = x + childW + gap
        end
    end
end

SuuUI._FlowLayout = M
