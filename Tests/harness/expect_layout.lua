-- Layout-focused assertions. Attached onto the harness table by harness/init.lua.
local framework = require("harness.framework")
local geometry  = require("harness.wow.geometry")

local fmt = framework.fmt

local function bail(msg)
    error({ __assertion = true, message = msg }, 3)
end

--- Installs the layout assertions onto the harness table.
-- @param H table
return function(H)

    local function label(target)
        local f = H.frameOf(target)
        if not f then return "<nil>" end
        return (f:GetName() or f._kind or "widget") .. "#" .. tostring(f._serial)
    end

    --- Asserts a widget's rect in top-down screen coordinates.
    -- Only the keys present in expected are checked.
    -- @param target table
    -- @param expected table  { left, top, width, height, right, bottom }
    -- @param tol number  Default 0.5
    function H.expectBox(target, expected, tol)
        tol = tol or 0.5
        local box = H.box(target)
        if not box then
            bail(label(target) .. " has no resolvable position (no anchors)")
        end
        for key, want in pairs(expected) do
            local got = box[key]
            if got == nil then bail("unknown box key " .. fmt(key)) end
            if math.abs(got - want) > tol then
                bail(string.format("%s.%s: expected %s, got %s", label(target), key, fmt(want), fmt(got)))
            end
        end
        return box
    end

    --- Asserts a widget's size, ignoring position.
    -- @param target table
    -- @param w number
    -- @param h number
    function H.expectSize(target, w, h, tol)
        tol = tol or 0.5
        local f = H.frameOf(target)
        if w ~= nil and math.abs(f:GetWidth() - w) > tol then
            bail(string.format("%s width: expected %s, got %s", label(target), fmt(w), fmt(f:GetWidth())))
        end
        if h ~= nil and math.abs(f:GetHeight() - h) > tol then
            bail(string.format("%s height: expected %s, got %s", label(target), fmt(h), fmt(f:GetHeight())))
        end
    end

    --- Asserts a child's top-left offset from an ancestor's top-left.
    -- dy is positive downward, matching padding and gap semantics.
    -- @param child table
    -- @param ancestor table
    -- @param dx number
    -- @param dy number
    function H.expectOffset(child, ancestor, dx, dy, tol)
        tol = tol or 0.5
        local gotX, gotY = H.offset(child, ancestor)
        if gotX == nil then
            bail(label(child) .. " or " .. label(ancestor) .. " has no resolvable position")
        end
        if dx ~= nil and math.abs(gotX - dx) > tol then
            bail(string.format("%s dx from %s: expected %s, got %s",
                label(child), label(ancestor), fmt(dx), fmt(gotX)))
        end
        if dy ~= nil and math.abs(gotY - dy) > tol then
            bail(string.format("%s dy from %s: expected %s, got %s",
                label(child), label(ancestor), fmt(dy), fmt(gotY)))
        end
    end

    --- Asserts the inner widget lies entirely within the outer widget.
    function H.expectInside(inner, outer, tol)
        local i, o = H.frameOf(inner), H.frameOf(outer)
        if not geometry.containsRect(o, i, tol or 0.51) then
            local ib, ob = H.box(inner), H.box(outer)
            bail(string.format("%s %s is not inside %s %s",
                label(inner), fmt(ib), label(outer), fmt(ob)))
        end
    end

    --- Asserts none of the listed widgets overlap each other.
    -- @param targets table  Array of handles or frames
    function H.expectNoOverlap(targets, tol)
        -- REFUSE A MIS-SHAPED CALL. This takes an ARRAY, and `H.expectNoOverlap(a, b)` reads
        -- perfectly: it binds `b` to `tol`, leaves `#targets == 0`, and both loops below never
        -- execute -- so the assertion passes whatever the geometry is. 24 call sites across 12
        -- spec files were doing exactly that, asserting nothing at all, and the only reason it
        -- was ever noticed is that a mutation survived. A helper whose misuse is silent will be
        -- misused again, so the misuse is now an error.
        if type(targets) ~= "table" then
            bail("expectNoOverlap needs an ARRAY of targets, got " .. type(targets))
        end
        if tol ~= nil and type(tol) ~= "number" then
            bail("expectNoOverlap takes (targets, tol): pass the widgets as ONE array, " ..
                 "e.g. H.expectNoOverlap({ a, b }) -- not H.expectNoOverlap(a, b)")
        end
        if #targets == 0 then
            bail("expectNoOverlap got an empty or non-array table -- a single widget cannot " ..
                 "overlap anything, so this asserted nothing. Pass { a, b }.")
        end
        for i = 1, #targets do
            for j = i + 1, #targets do
                local a, b = H.frameOf(targets[i]), H.frameOf(targets[j])
                if geometry.overlaps(a, b, tol or 0.01) then
                    bail(string.format("%s %s overlaps %s %s",
                        label(targets[i]), fmt(H.box(targets[i])),
                        label(targets[j]), fmt(H.box(targets[j]))))
                end
            end
        end
    end

    --- Asserts widgets are laid out top to bottom in order, separated by exactly gap.
    -- @param targets table  Array in expected visual order
    -- @param gap number
    function H.expectStackedVertically(targets, gap, tol)
        tol = tol or 0.5
        gap = gap or 0
        for i = 2, #targets do
            local prev = H.box(targets[i - 1])
            local cur  = H.box(targets[i])
            if not (prev and cur) then bail("unresolvable position in vertical stack") end
            local actualGap = cur.top - prev.bottom
            if math.abs(actualGap - gap) > tol then
                bail(string.format("gap between item %d and %d: expected %s, got %s",
                    i - 1, i, fmt(gap), fmt(actualGap)))
            end
            if math.abs(cur.left - prev.left) > tol then
                bail(string.format("item %d left edge %s does not align with item %d left edge %s",
                    i, fmt(cur.left), i - 1, fmt(prev.left)))
            end
        end
    end

    --- Asserts widgets are laid out left to right in order, separated by exactly gap.
    -- @param targets table
    -- @param gap number
    function H.expectRowHorizontally(targets, gap, tol)
        tol = tol or 0.5
        gap = gap or 0
        for i = 2, #targets do
            local prev = H.box(targets[i - 1])
            local cur  = H.box(targets[i])
            if not (prev and cur) then bail("unresolvable position in horizontal row") end
            local actualGap = cur.left - prev.right
            if math.abs(actualGap - gap) > tol then
                bail(string.format("gap between item %d and %d: expected %s, got %s",
                    i - 1, i, fmt(gap), fmt(actualGap)))
            end
        end
    end

    --- Asserts a widget is horizontally centred inside another.
    function H.expectCenteredH(inner, outer, tol)
        tol = tol or 0.5
        local i, o = H.box(inner), H.box(outer)
        if not (i and o) then bail("unresolvable position in centring check") end
        local innerMid = i.left + i.width / 2
        local outerMid = o.left + o.width / 2
        if math.abs(innerMid - outerMid) > tol then
            bail(string.format("%s horizontal centre %s vs %s centre %s",
                label(inner), fmt(innerMid), label(outer), fmt(outerMid)))
        end
    end

    --- Asserts a widget is vertically centred inside another.
    function H.expectCenteredV(inner, outer, tol)
        tol = tol or 0.5
        local i, o = H.box(inner), H.box(outer)
        if not (i and o) then bail("unresolvable position in centring check") end
        local innerMid = i.top + i.height / 2
        local outerMid = o.top + o.height / 2
        if math.abs(innerMid - outerMid) > tol then
            bail(string.format("%s vertical centre %s vs %s centre %s",
                label(inner), fmt(innerMid), label(outer), fmt(outerMid)))
        end
    end

    --- Asserts a font string's box is big enough to render its text uncut.
    -- The client silently clips instead of overflowing, so a layout that pins a font
    -- string to a stale size produces a half-drawn glyph and no other assertion fails.
    -- @param target table  A font string, or a handle whose frame is one
    function H.expectTextNotClipped(target)
        local fs = H.frameOf(target)
        if not fs.IsTextClipped then
            bail(label(target) .. " is not a font string")
        end
        local clipped, boxW, boxH, needW, needH = fs:IsTextClipped()
        if clipped then
            bail(string.format("%s text %s is clipped: box %sx%s, needs %sx%s",
                label(target), fmt(fs:GetText()),
                fmt(boxW), fmt(boxH), fmt(needW), fmt(needH)))
        end
    end

    --- Asserts one widget draws over another, the way the client resolves it: strata rung
    --- first, frame level only as the tie-break inside a rung. Comparing levels alone is
    --- how a z-order bug hides — a deeper-nested frame outranks a shallow one inside a
    --- shared strata even though it was never meant to cover it.
    -- @param target table  The widget expected on top
    -- @param under table   The widget expected underneath
    function H.expectDrawsAbove(target, under)
        local order = require("harness.wow.frame").STRATA_ORDER
        local a, b = H.frameOf(target), H.frameOf(under)
        if not (a and b) then bail("expectDrawsAbove needs two widgets") end
        local sa, sb = a:GetFrameStrata(), b:GetFrameStrata()
        if order[sa] ~= order[sb] then
            if order[sa] < order[sb] then
                bail(string.format("%s is on strata %s, below %s on %s",
                    label(target), sa, label(under), sb))
            end
            return
        end
        if a:GetFrameLevel() <= b:GetFrameLevel() then
            bail(string.format("%s and %s share strata %s, and level %d is not above %d",
                label(target), label(under), sa, a:GetFrameLevel(), b:GetFrameLevel()))
        end
    end

    ------------------------------------------------------------------------------
    -- Hit testing
    --
    -- The client delivers a click to the TOPMOST visible, mouse-enabled frame under the
    -- cursor. The harness delivers H.click straight to the widget you name, which is
    -- convenient but means a frame can be completely covered by another and still pass a
    -- click test — exactly the bug class that put the player frame over the settings
    -- window. These helpers resolve a point the way the client would, so occlusion
    -- becomes assertable.
    ------------------------------------------------------------------------------

    -- A frame is only hittable if it AND every ancestor is shown: hiding a parent hides
    -- the subtree, and the client's hit test walks the same chain.
    local function effectivelyVisible(f)
        local cur = f
        while cur do
            if cur.IsShown and not cur:IsShown() then return false end
            cur = cur.GetParent and cur:GetParent() or nil
        end
        return true
    end

    local function screenBox(f)
        local st = require("harness.wow.state")
        return geometry.boxFromTop(f, st.screenHeight)
    end

    --- Returns the frame a click at (x, y) would actually reach, or nil.
    -- Ranks by strata first, then frame level, then creation order — the client's own
    -- ordering, and the same ladder expectDrawsAbove uses.
    -- @param x number  Screen coordinate, left-to-right
    -- @param y number  Screen coordinate, TOP-DOWN (matches H.box)
    -- @return table|nil
    function H.topmostAt(x, y)
        local st    = require("harness.wow.state")
        local order = require("harness.wow.frame").STRATA_ORDER
        local best, bestRank, bestLevel
        for i = 1, #st.frames do
            local f = st.frames[i]
            if f.IsMouseEnabled and f:IsMouseEnabled() and effectivelyVisible(f) then
                local b = screenBox(f)
                if b and x >= b.left and x <= b.right and y >= b.top and y <= b.bottom then
                    local rank  = order[f:GetFrameStrata()] or 0
                    local level = f:GetFrameLevel() or 0
                    -- >= on level so a later-created sibling at the same level wins, which
                    -- is how the client resolves a tie.
                    if not best or rank > bestRank
                       or (rank == bestRank and level >= bestLevel) then
                        best, bestRank, bestLevel = f, rank, level
                    end
                end
            end
        end
        return best
    end

    --- Returns the centre point of a widget in top-down screen coordinates.
    -- @param target table
    -- @return number, number
    function H.centerPoint(target)
        local f = H.frameOf(target)
        if not f then bail("centerPoint needs a widget") end
        local b = screenBox(f)
        if not b then bail(label(target) .. " has no resolvable position (no anchors)") end
        return b.left + b.width / 2, b.top + b.height / 2
    end

    --- Asserts a click at (x, y) reaches the expected widget rather than something above it.
    -- @param expected table
    -- @param x number
    -- @param y number
    function H.expectHitTarget(expected, x, y)
        local want = H.frameOf(expected)
        local got  = H.topmostAt(x, y)
        if got ~= want then
            bail(string.format("click at (%s, %s) reaches %s, expected %s",
                fmt(x), fmt(y), got and label(got) or "nothing", label(expected)))
        end
    end

    --- Asserts nothing covers a widget: a click at its own centre reaches it.
    -- @param target table
    function H.expectClickable(target)
        local f = H.frameOf(target)
        if not (f.IsMouseEnabled and f:IsMouseEnabled()) then
            bail(label(target) .. " is not mouse-enabled, so no click can reach it")
        end
        local x, y = H.centerPoint(target)
        H.expectHitTarget(target, x, y)
    end

    --- Asserts `over` swallows a click aimed at `under`'s centre.
    -- The occlusion counterpart to expectDrawsAbove: drawing above is about pixels, this
    -- is about input. Use it for a panel or modal that must capture clicks meant for
    -- whatever it covers.
    -- @param over table
    -- @param under table
    function H.expectOccludes(over, under)
        local x, y = H.centerPoint(under)
        local got = H.topmostAt(x, y)
        local want = H.frameOf(over)
        if got ~= want then
            bail(string.format("%s does not occlude %s: a click at its centre reaches %s",
                label(over), label(under), got and label(got) or "nothing"))
        end
    end

    --- Asserts a colour tuple matches a theme token's resolved value.
    -- @param got table  { r, g, b, a } or four return values collected by the caller
    -- @param tokenKey string
    function H.expectTokenColor(got, tokenKey, tol)
        tol = tol or 0.001
        local want = H.token(tokenKey)
        if type(want) ~= "table" then bail("token " .. fmt(tokenKey) .. " is not a colour") end
        if type(got) ~= "table" then bail("expected a colour table, got " .. fmt(got)) end
        for i = 1, 4 do
            if math.abs((got[i] or 0) - (want[i] or 0)) > tol then
                bail(string.format("colour component %d: expected %s (%s), got %s",
                    i, fmt(want[i]), tokenKey, fmt(got[i])))
            end
        end
    end

    --- Convenience: a widget's backdrop background colour as a table.
    function H.backdropColor(target)
        local f = H.frameOf(target)
        local r, g, b, a = f:GetBackdropColor()
        if r == nil then return nil end
        return { r, g, b, a }
    end

    --- Convenience: a widget's backdrop border colour as a table.
    function H.borderColor(target)
        local f = H.frameOf(target)
        local r, g, b, a = f:GetBackdropBorderColor()
        if r == nil then return nil end
        return { r, g, b, a }
    end

    --- Convenience: a texture's vertex colour as a table. This is how a masked texture
    --- carries its colour: a mask cuts the shape out of a solid white fill, and replacing
    --- that fill with SetColorTexture would swap the texture the mask is attached to. Any
    --- rounded surface is therefore tinted rather than recoloured, so it is this and not
    --- H.backdropColor that reports what a stadium or a disc is painted.
    function H.vertexColor(target)
        local r, g, b, a = H.frameOf(target):GetVertexColor()
        if r == nil then return nil end
        return { r, g, b, a }
    end

    --- Convenience: a font string's text colour as a table.
    function H.textColor(target)
        local f = H.frameOf(target)
        local r, g, b, a = f:GetTextColor()
        return { r, g, b, a }
    end
end
