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
--
--  A CHILD WHOSE ANCHOR HAS NOT MOVED IS SKIPPED, and that is correctness rather than
--  optimisation. Re-anchoring is `ClearAllPoints` + `SetPoint`, and the client REFUSES both on
--  a frame holding a protected descendant while InCombatLockdown() is true. Moving one root
--  element runs a pass over all of them, so without this guard a unit frame growing for a
--  debuff mid-fight re-states every other element's unchanged anchor -- and an action bar,
--  which contains secure buttons by construction, earns the player an "Interface action failed
--  because of an AddOn" for a move it never needed. Found by the lockdown model, as two
--  refusals with protected=false.
--
--  The guard is skipped entirely when the descriptor carries a width or a height, because
--  those resolve against the child's CURRENT size and so cannot be compared against a
--  requested one. It compares against the child's LIVE anchor rather than a remembered one,
--  which matters: a window dragged by the player has its points set directly, bypassing this
--  container, so "the descriptor did not change" does not mean "the frame is still where that
--  descriptor put it" -- and a re-centre after a drag has to re-apply.
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

            local sized    = (a.width or a.height) and true or false
            local point    = a.point or "TOPLEFT"
            local relPoint = a.relativePoint or a.point or "TOPLEFT"
            local x, y     = snap(a.x or 0), snap(a.y or 0)

            -- Exactly one point, because a frame anchored several ways is not one this
            -- comparison can speak about.
            local same = false
            if not sized and child.GetPoint and child.GetNumPoints
               and (child:GetNumPoints() or 0) == 1 then
                local cp, crel, crp, cx, cy = child:GetPoint(1)
                same = cp == point and crel == rel and crp == relPoint
                    and cx == x and cy == y
            end

            if not same then
                child:ClearAllPoints()

                if sized then
                    child:SetSize(
                        snap(a.width  or child:GetWidth()),
                        snap(a.height or child:GetHeight())
                    )
                end

                child:SetPoint(point, rel, relPoint, x, y)
            end
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
