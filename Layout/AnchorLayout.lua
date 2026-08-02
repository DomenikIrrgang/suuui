local ipairs = ipairs

local M = {}

--- Applies anchor layout. Each child needs an anchor descriptor in
--  _layoutProps.anchor (preferred) or _anchor:
--  { point, relativeTo, relativePoint, x, y, width, height }
--  relativeTo may be a frame, a component handle, the string "parent", or nil.
--  Use this strategy for absolute or fraction-driven placement (sliders, thumbs)
--  and update it through container:SetChildAnchor(child, desc).
-- @param container table
function M.Apply(container)
    local parent = container._frame
    for _, child in ipairs(container._children) do
        local a = (child._layoutProps and child._layoutProps.anchor) or child._anchor

        if a then
            local rel = a.relativeTo
            if rel == "parent" or not rel then
                rel = parent
            elseif rel.GetFrame then
                rel = rel:GetFrame()
            end

            child:ClearAllPoints()

            if a.width or a.height then
                child:SetSize(a.width or child:GetWidth(), a.height or child:GetHeight())
            end

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
