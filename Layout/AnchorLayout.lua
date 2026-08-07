local ipairs = ipairs
-- Descriptors carry caller-computed positions — a slider thumb at pct * trackWidth, a
-- scrollbar thumb at a fraction of its track — so this is where those land on the grid.
local snap = SuuUI.Pixel.Snap

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
                child:SetSize(
                    snap(a.width  or child:GetWidth()),
                    snap(a.height or child:GetHeight())
                )
            end

            child:SetPoint(
                a.point or "TOPLEFT",
                rel,
                a.relativePoint or a.point or "TOPLEFT",
                snap(a.x or 0),
                snap(a.y or 0)
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
