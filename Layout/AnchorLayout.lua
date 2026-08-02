local M = {}

--- Applies anchor layout. Each child must have an _anchor or _layoutProps.anchor descriptor:
--  { point, relativeTo, relativePoint, x, y, width, height }
--  relativeTo can be a frame or the string "parent" or nil (defaults to parent).
-- @param container table
function M.Apply(container)
    local parent = container._frame
    for _, child in ipairs(container._children) do
        -- Get anchor from _layoutProps.anchor or fallback to _anchor
        local a = (child._layoutProps and child._layoutProps.anchor) or child._anchor
        
        if a then
            local rel = (a.relativeTo == "parent" or not a.relativeTo) and parent or a.relativeTo
            child:ClearAllPoints()
            
            -- Apply size if specified
            if a.width or a.height then
                local w = a.width or child:GetWidth()
                local h = a.height or child:GetHeight()
                child:SetSize(w, h)
            end
            
            -- Apply anchor point
            child:SetPoint(
                a.point or "TOPLEFT", 
                rel, 
                a.relativePoint or a.point or "TOPLEFT",
                a.x or 0, 
                a.y or 0
            )
        end
    end
end

--- Attaches anchor metadata to a frame for use by AnchorLayout.
-- @param frame frame
-- @param anchor table  { point, relativeTo, relativePoint, x, y, width, height }
function M.SetAnchor(frame, anchor)
    frame._anchor = anchor
end

SuuUI._AnchorLayout = M
