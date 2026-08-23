local H = require("harness")

-- Accordion and AccordionGroup.
--
-- Four things in Components/Accordion.lua are load-bearing, and the header comment there
-- names each as a trap the codebase has already paid for once. Every one of them is a
-- geometry consequence rather than a stored flag, so each is asserted through produced
-- pixels here and named in the assertion message:
--
--   * the window is a SEPARATE container with an explicit height, so it never hugs
--   * the window is SHOWN before it is animated, and hidden only once a close finishes
--   * the root column's gap is ZERO, so no group below pops at the end of a close
--   * the header and the body surface are SIBLINGS painted with the same token
--
-- and the group owns ONE animation for a close and an open together, not two.

describe("Components.Accordion", function()
    local host
    before_each(function()
        H.setup()
        host = H.parent(400, 600)
    end)

    ------------------------------------------------------------------------------
    -- Derivations. Every expected number in this file comes from one of these, from
    -- H.token / H.textBox / H.controlHeight, or from another widget's measured box.
    ------------------------------------------------------------------------------

    -- The rail is floored at one physical pixel: a rail that rounds away is the only cue
    -- distinguishing the open group from the closed ones.
    local function rail()    return H.SuuUI.Pixel.Line(H.token("sizeRail")) end
    local function gap()     return H.token("spaceXs") end
    local function pad()     return H.token("spaceSm") end
    local function headerH() return H.controlHeight("sizeRow") end
    local function rowH()    return H.token("sizeControlSm") end
    local function dur()     return H.token("animFast") end

    -- The rule _chevWidth STATES: the column is the WIDER of the two glyphs at the font
    -- actually in force, measured as a BOX (the client truncates with zero tolerance), so
    -- swapping ">" for "v" can never shift the label sideways.
    --
    -- The harness font model gives every glyph the same advance, so the max between the two
    -- glyphs is degenerate — which is exactly why the label's own left edge is asserted
    -- separately below. That is the assertion that catches a column measured from the
    -- CURRENT glyph, and it holds today.
    local function chevColumnIntended(acc)
        local path, size = H.fontOf(acc._chev)
        return math.max(H.textBox("v", size, path), H.textBox(">", size, path))
    end

    -- What the body wants right now, measured the way the component measures it.
    local function bodyH(acc)
        local _, h = acc:GetBody():GetContentSize()
        return h
    end

    local function clipH(acc)
        return acc._clip:GetFrame():GetHeight()
    end

    -- Rows are caller content, so they are plain frames at a token height: exact, and the
    -- assertions still move with the theme.
    local function addRows(acc, n, h)
        h = h or rowH()
        local body, out = acc:GetBody(), {}
        for i = 1, n do
            local f = H.env.CreateFrame("Frame", nil, body:GetFrame())
            f:SetHeight(h)
            body:Add(f, { width = "fill", height = h })
            out[i] = f
        end
        return out
    end

    -- Mounted, because every position inside an accordion is asserted here and a
    -- component never positions itself.
    local function accordion(props, rows)
        local acc = H.mount(H.C.Accordion(props or {}, host))
        if rows then addRows(acc, rows) end
        return acc
    end

    -- A real page: accordions laid out by a vertical flow column, as SettingsUI does it.
    local function column(n, rows, colGap)
        local col = H.Layout:CreateContainer({
            parent = host, layout = "flow", dir = "vertical", gap = colGap or pad(),
        })
        local accs = {}
        for i = 1, n do
            local a = H.C.Accordion({ label = "Group " .. i }, col:GetFrame())
            addRows(a, rows or 2)
            col:Add(a, { width = "fill" })
            accs[i] = a
        end
        return col, accs
    end

    local function groupOf(n, rows)
        local col, accs = column(n, rows)
        local grp = H.C.AccordionGroup()
        for i = 1, n do grp:Add(accs[i]) end
        return grp, accs, col
    end

    ------------------------------------------------------------------------------
    describe("construction and defaults", function()
        it("starts collapsed, with the window hidden rather than zero-height", function()
            local acc = accordion({ label = "General" }, 2)
            expect(acc:IsOpen()).as("closed unless props say otherwise").falsy()
            expect(acc:GetReveal()).eq(0)
            expect(acc._clip:IsShown())
                .as("flow skips a hidden child, so a collapsed group costs no height").falsy()
        end)

        it("snaps straight to open when props.open is set, without animating", function()
            local acc = accordion({ label = "General", open = true }, 2)
            expect(acc:IsOpen()).truthy()
            expect(acc:GetReveal()).as("construction snaps: an animation would run during login").eq(1)
            expect(H.SuuUI.Anim:GetActiveCount(acc)).eq(0)
            expect(clipH(acc)).eq(bodyH(acc))
        end)

        it("coerces a truthy non-boolean open prop to closed", function()
            expect(accordion({ open = "yes" }, 1):IsOpen()).as("only true counts").falsy()
        end)

        it("defaults the label to the empty string", function()
            expect(accordion({}):GetLabel()).eq("")
        end)

        it("shows the collapsed chevron closed and the expanded one open", function()
            local acc = accordion({ label = "General" }, 1)
            expect(acc._chev:GetText()).as("ASCII: the faces do not reliably carry U+25B8").eq(">")
            acc:SetOpen(true, { animate = false })
            expect(acc._chev:GetText()).eq("v")
        end)

        it("takes mouse input on the header, which is the thing the user clicks", function()
            expect(accordion({ label = "General" }):GetHeader():IsMouseEnabled()).truthy()
        end)

        it("heights the header from the row control token, floored against the font", function()
            H.expectSize(accordion({ label = "General" }):GetHeader(), nil, headerH())
        end)

        it("hugs its own content height: header alone when closed", function()
            local acc = accordion({ label = "General" }, 3)
            H.expectSize(acc, nil, headerH())
        end)

        it("hugs header plus window when open, with no gap between them", function()
            local acc = accordion({ label = "General", open = true }, 3)
            H.expectSize(acc, nil, headerH() + bodyH(acc))
        end)
    end)

    ------------------------------------------------------------------------------
    describe("the rail gutter", function()
        it("reserves the rail's width as the column's left padding", function()
            local acc = accordion({ label = "General" }, 1)
            expect(acc._root:GetPadding().left).eq(rail())
        end)

        it("sizes the rail to that gutter and stretches it down the whole column", function()
            local acc = accordion({ label = "General", open = true }, 3)
            local rb, ab = H.box(acc._rail), H.box(acc)
            expect(rb.width).eq(rail())
            expect(rb.left).eq(ab.left)
            expect(rb.height).as("a stack child valigned stretch spans the column").eq(ab.height)
        end)

        it("keeps the rail out of the header and the body, never overlapping their fills", function()
            local acc = accordion({ label = "General", open = true }, 3)
            H.expectNoOverlap({ acc._rail, acc:GetHeader(), acc._clip:GetFrame() })
        end)

        it("indents the header and the window by the gutter", function()
            local acc = accordion({ label = "General", open = true }, 2)
            local ab = H.box(acc)
            expect(H.box(acc:GetHeader()).left).eq(ab.left + rail())
            expect(H.box(acc._clip).left).eq(ab.left + rail())
            H.expectInside(acc:GetHeader(), acc:GetFrame())
            H.expectInside(acc._clip:GetFrame(), acc:GetFrame())
        end)

        it("lights the rail while any part of the body shows, and darkens it only at zero", function()
            local acc = accordion({ label = "General" }, 2)
            expect(acc._rail:IsShown()).as("nothing revealed, no rail").falsy()
            acc:SetReveal(0.2)
            expect(acc._rail:IsShown())
                .as("tied to the REVEAL: a body still showing with no rail reads as a glitch").truthy()
            acc:SetReveal(0)
            expect(acc._rail:IsShown()).falsy()
        end)

        it("paints the rail with the accent token", function()
            local acc = accordion({ label = "General", open = true }, 1)
            H.expectTokenColor({ acc._rail:GetColorTexture() }, "colorAccent")
        end)
    end)

    ------------------------------------------------------------------------------
    describe("header geometry", function()
        it("sizes the chevron column at the wider of the two glyph BOXES", function()
            local acc = accordion({ label = "General" }, 1)
            -- `_chevWidth` captures each Box width into a local before comparing them.
            -- Measured inline as max(B(a), B(b)) it compared w1, w2 AND h2, because Lua
            -- expands the LAST call's returns and Box's second return is the glyph HEIGHT —
            -- which won at every shipped font size and made the column track the line
            -- height ratio rather than the glyph advance, so a swap to a narrow face would
            -- shrink the glyph and leave the column where it was.
            expect(H.box(acc._chev).width)
                .as("the glyph advance, never the line height")
                .eq(chevColumnIntended(acc))
        end)

        it("never moves the label when the chevron swaps", function()
            local acc = accordion({ label = "General" }, 1)
            local closedLeft = H.box(acc._label).left
            local closedW    = H.box(acc._chev).width
            acc:SetOpen(true, { animate = false })
            expect(H.box(acc._chev).width)
                .as("the column is state-independent, measured from both glyphs").eq(closedW)
            expect(H.box(acc._label).left)
                .as("the label's left edge is identical open and closed").eq(closedLeft)
            acc:SetOpen(false, { animate = false })
            expect(H.box(acc._label).left).eq(closedLeft)
        end)

        it("insets the row by the spacing token and separates the parts by the gap", function()
            local acc = accordion({ label = "General" }, 1)
            local hb = H.box(acc:GetHeader())
            expect(H.box(acc._chev).left).eq(hb.left + pad())
            H.expectRowHorizontally({ acc._chev, acc._label }, gap())
            expect(H.box(acc._label).right).eq(hb.right - pad())
        end)

        it("centres both parts vertically in the header", function()
            local acc = accordion({ label = "General" }, 1)
            H.expectCenteredV(acc._chev, acc:GetHeader())
            H.expectCenteredV(acc._label, acc:GetHeader())
        end)

        it("keeps the chevron and the label inside the header and apart", function()
            local acc = accordion({ label = "General" }, 1)
            H.expectInside(acc._chev, acc:GetHeader())
            H.expectInside(acc._label, acc:GetHeader())
            H.expectNoOverlap({ acc._chev, acc._label })
        end)

        it("does not clip the label, the long one included", function()
            H.expectTextNotClipped(accordion({ label = "General" }, 1)._label)
            H.expectTextNotClipped(
                accordion({ label = "Advanced Nameplate and Aura Options" }, 1)._label)
        end)

        it("does not clip the chevron in either state", function()
            local acc = accordion({ label = "General" }, 1)
            H.expectTextNotClipped(acc._chev)
            acc:SetOpen(true, { animate = false })
            H.expectTextNotClipped(acc._chev)
        end)

        it("keeps the label unclipped after a font token grows it", function()
            local acc = accordion({ label = "Nameplates" }, 1)
            H.T:CreateUserTheme("BigFont", "Modern")
            H.T:SetUserToken("BigFont", "fontSizeMd", 20)
            H.T:SetActive("BigFont")
            H.expectTextNotClipped(acc._label)
            H.expectTextNotClipped(acc._chev)
        end)

        it("colours the label and chevron by state, muted closed and lit open", function()
            local acc = accordion({ label = "General" }, 1)
            H.expectTokenColor(H.textColor(acc._label), "colorTextMuted")
            H.expectTokenColor(H.textColor(acc._chev), "colorTextMuted")
            acc:SetOpen(true, { animate = false })
            H.expectTokenColor(H.textColor(acc._label), "colorText")
            H.expectTokenColor(H.textColor(acc._chev), "colorAccent")
        end)

        it("tints the header on hover and gives the surface back on leave", function()
            local acc = accordion({ label = "General" }, 1)
            H.expectTokenColor(H.backdropColor(acc:GetHeader()), "colorBgAlt")
            expect(H.hover(acc:GetHeader())).truthy()
            H.expectTokenColor(H.backdropColor(acc:GetHeader()), "colorBgHover")
            H.unhover(acc:GetHeader())
            H.expectTokenColor(H.backdropColor(acc:GetHeader()), "colorBgAlt")
        end)
    end)

    ------------------------------------------------------------------------------
    describe("the header and the body surface are siblings", function()
        it("paints both with the same surface token", function()
            local acc = accordion({ label = "General", open = true }, 2)
            H.expectTokenColor(H.backdropColor(acc:GetHeader()), "colorBgAlt")
            H.expectTokenColor(H.backdropColor(acc._clip:GetFrame()), "colorBgAlt")
        end)

        it("never nests one inside the other, which would blend the fill against itself", function()
            local acc = accordion({ label = "General", open = true }, 2)
            H.expectNoOverlap({ acc:GetHeader(), acc._clip:GetFrame() })
            expect(H.clipAncestor(acc:GetHeader()))
                .as("the header is not inside the window: both carry opacityPanel").isNil()
        end)

        it("stacks them flush, with no seam and no gap", function()
            local acc = accordion({ label = "General", open = true }, 2)
            H.expectStackedVertically({ acc:GetHeader(), acc._clip:GetFrame() }, 0)
        end)
    end)

    ------------------------------------------------------------------------------
    describe("the window does not hug", function()
        -- A container with no height of its own hugs its content and re-states that
        -- height from inside Layout() -- on the very tick an animation set it. Animating
        -- a hugging container is a fight the hug always wins.
        it("holds a half reveal through a body layout pass", function()
            local acc = accordion({ label = "General", open = true }, 3)
            local full = bodyH(acc)
            acc:SetReveal(0.5)
            local half = H.SuuUI.Pixel.Ceil(full * 0.5)
            expect(clipH(acc)).eq(half)

            acc:GetBody():Layout()
            expect(clipH(acc))
                .as("the window must NOT hug: a hugging container re-states its content height from inside Layout()")
                .eq(half)
            expect(clipH(acc)).as("and it must not have snapped to the full body height").lt(full)
        end)

        it("holds a half reveal through a row being re-added below the cut", function()
            local acc = accordion({ label = "General", open = true }, 2)
            local full = bodyH(acc)
            acc:SetReveal(0.5)
            local half = H.SuuUI.Pixel.Ceil(full * 0.5)
            acc:GetBody():Layout()
            acc:GetBody():Layout()
            expect(clipH(acc)).as("re-laying out the body twice must not grow the window").eq(half)
        end)

        it("still reports the body at its full assigned height behind the cut", function()
            local acc = accordion({ label = "General", open = true }, 3)
            local full = bodyH(acc)
            acc:SetReveal(0.5)
            expect(H.box(acc:GetBody()).height)
                .as("the body keeps its full height; only the window over it shrinks").eq(full)
        end)
    end)

    ------------------------------------------------------------------------------
    describe("re-measures a body built while the window was hidden", function()
        -- The client gives a hidden frame NO rect, so every row of a collapsed section is
        -- built and measured blind -- and OnShow fires only for the frame whose own
        -- visibility changed, never for a descendant when an ANCESTOR is shown, so
        -- Container's per-container OnShow hook cannot rescue it. In game this drew as a
        -- blank band at the top of a section the first time it was opened.
        --
        -- The harness gives hidden frames a rect (see TESTING.md, Known Gaps), so it cannot
        -- reproduce the CONSEQUENCE. It can pin the INVARIANT: the subtree is re-laid out at
        -- the moment the window first becomes shown.
        it("lays out the body subtree the first time the window is shown", function()
            local acc = accordion({ label = "General" }, 3)
            local body, calls = acc:GetBody(), 0
            local real = body.LayoutTree
            body.LayoutTree = function(self, ...) calls = calls + 1; return real(self, ...) end

            expect(acc._clip:IsShown()).as("collapsed, so the window is hidden").falsy()
            expect(calls).as("nothing re-measured while it stays collapsed").eq(0)

            acc:SetOpen(true, { animate = false })
            expect(calls)
                .as("the window became shown, so the blind-measured subtree is re-measured")
                .eq(1)
        end)

        it("does not re-measure again on a later open", function()
            local acc = accordion({ label = "General" }, 3)
            acc:SetOpen(true, { animate = false })
            local body, calls = acc:GetBody(), 0
            local real = body.LayoutTree
            body.LayoutTree = function(self, ...) calls = calls + 1; return real(self, ...) end

            acc:SetOpen(false, { animate = false })
            acc:SetOpen(true, { animate = false })
            expect(calls)
                .as("the window is only newly-shown once; later opens need no re-measure")
                .eq(1)
        end)
    end)

    describe("shown before animated", function()
        it("does not write geometry from Play, only from the first tick", function()
            local acc = accordion({ label = "General" }, 3)
            acc:SetOpen(true)
            expect(acc:IsOpen()).as("the logical state flips immediately").truthy()
            expect(acc:GetReveal()).as("Play() queues; it does not write").eq(0)
        end)

        it("shows the window as soon as the reveal leaves zero", function()
            local acc = accordion({ label = "General" }, 3)
            acc:SetOpen(true)
            H.tick(dur() * 0.25)
            expect(acc:GetReveal()).as("the first tick starts the reveal").gt(0)
            expect(acc._clip:IsShown())
                .as("SHOWN before it is animated: the animator skips writes on a hidden target and flow skips a hidden child")
                .truthy()
        end)

        it("settles at exactly one, with the window the height of the body's content", function()
            local acc = accordion({ label = "General" }, 3)
            acc:SetOpen(true)
            H.runAnimations()
            expect(acc:GetReveal()).eq(1)
            expect(clipH(acc)).eq(bodyH(acc))
            expect(acc._clip:IsShown()).truthy()
        end)

        it("keeps the window shown for the whole of a close", function()
            local acc = accordion({ label = "General", open = true }, 3)
            acc:SetOpen(false)
            H.tick(dur() * 0.5)
            expect(acc:GetReveal()).as("mid-close").between(0.0001, 0.9999)
            expect(acc._clip:IsShown()).as("hidden only once the close FINISHES").truthy()
        end)

        it("leaves the window hidden after a full open and close cycle", function()
            local acc = accordion({ label = "General" }, 3)
            acc:SetOpen(true)
            H.runAnimations()
            acc:SetOpen(false)
            H.runAnimations()
            expect(acc:GetReveal()).eq(0)
            expect(acc._clip:IsShown()).as("a cycle ends hidden, not at zero height").falsy()
            expect(H.SuuUI.Anim:GetActiveCount(acc)).eq(0)
        end)

        it("ceils the window height, so a full reveal never clips the last descenders", function()
            local acc = accordion({ label = "General", open = true }, 3)
            acc:SetReveal(1 / 3)
            expect(clipH(acc)).eq(H.SuuUI.Pixel.Ceil(bodyH(acc) / 3))
        end)
    end)

    ------------------------------------------------------------------------------
    describe("the window actually clips", function()
        it("makes the window a clipping frame", function()
            local acc = accordion({ label = "General", open = true }, 3)
            expect(H.clipsChildren(acc._clip:GetFrame()))
                .as("without a clip the rows draw straight over the group below").truthy()
            expect(H.clipAncestor(acc:GetBody()))
                .as("the body is inside the window").eq(acc._clip:GetFrame())
        end)

        it("cuts a row that straddles the window edge mid-reveal", function()
            local acc = accordion({ label = "General", open = true }, 3)
            local rows = acc:GetBody():GetChildren()
            local full = bodyH(acc)
            local r1   = H.box(rows[1])
            -- Put the window's bottom edge through the middle of the first row, derived
            -- from the row's own measured box rather than picked.
            local cut  = (r1.top - H.box(acc:GetBody()).top) + r1.height / 2
            acc:SetReveal(cut / full)

            expect(H.isClipped(rows[1]))
                .as("the row spills past the window, so the client scissors it").truthy()
            local vis = H.visibleBox(rows[1])
            expect(vis).notNil()
            expect(vis.height)
                .as("only the band inside the window draws -- this is the assertion that catches rows spilling over the group below")
                .lt(r1.height)
            expect(vis.top).eq(r1.top)
            expect(vis.bottom).eq(H.box(acc._clip).bottom)
        end)

        it("draws nothing at all of a row entirely below the cut", function()
            local acc = accordion({ label = "General", open = true }, 3)
            local rows = acc:GetBody():GetChildren()
            acc:SetReveal(H.token("spaceXs") / bodyH(acc))
            expect(H.box(rows[3])).as("the solver still places it").notNil()
            expect(H.visibleBox(rows[3])).as("none of it draws").isNil()
        end)

        it("clips nothing at a full reveal", function()
            local acc = accordion({ label = "General", open = true }, 3)
            local rows = acc:GetBody():GetChildren()
            for i = 1, 3 do
                expect(H.isClipped(rows[i])).as("row " .. i .. " fits at full reveal").falsy()
                expect(H.visibleBox(rows[i])).deepEq(H.box(rows[i]))
            end
        end)

        it("keeps a mid-reveal row from reaching the group below it", function()
            local _, accs = column(2, 3)
            local a, b = accs[1], accs[2]
            a:SetOpen(true, { animate = false })
            local rows = a:GetBody():GetChildren()
            a:SetReveal(0.4)
            local below = H.box(b).top
            for i = 1, 3 do
                local vis = H.visibleBox(rows[i])
                if vis then
                    expect(vis.bottom)
                        .as("row " .. i .. " draws nothing below the next group's top edge")
                        .lte(below)
                end
            end
        end)
    end)

    ------------------------------------------------------------------------------
    describe("body and rows", function()
        it("pads the body above and below and gaps the rows by the spacing tokens", function()
            local acc = accordion({ label = "General", open = true }, 3)
            local rows = acc:GetBody():GetChildren()
            local bb = H.box(acc:GetBody())
            expect(H.box(rows[1]).top - bb.top).eq(gap())
            H.expectStackedVertically(rows, gap())
            expect(bb.bottom - H.box(rows[3]).bottom).eq(pad())
        end)

        it("fills the row width to the window", function()
            local acc = accordion({ label = "General", open = true }, 2)
            local rows = acc:GetBody():GetChildren()
            expect(H.box(rows[1]).width).eq(H.box(acc._clip).width)
        end)

        it("measures the window from the body's own content, padding included", function()
            local acc = accordion({ label = "General", open = true }, 3)
            expect(clipH(acc)).eq(gap() + rowH() * 3 + gap() * 2 + pad())
        end)

        it("re-derives the window when a row arrives while open", function()
            local acc = accordion({ label = "General", open = true }, 2)
            local before = clipH(acc)
            addRows(acc, 1)
            expect(clipH(acc))
                .as("a row appearing changes the body's height and the window is not derived from it")
                .eq(bodyH(acc))
            expect(clipH(acc)).eq(before + gap() + rowH())
        end)

        it("re-derives the window when a row grows while open", function()
            local acc = accordion({ label = "General", open = true }, 2)
            local rows = acc:GetBody():GetChildren()
            acc:GetBody():SetChildProps(rows[1], { width = "fill", height = rowH() * 2 })
            expect(clipH(acc)).eq(bodyH(acc))
        end)

        it("closes the hole a row leaves when it hides", function()
            local acc = accordion({ label = "General", open = true }, 3)
            local rows = acc:GetBody():GetChildren()
            local before = clipH(acc)
            rows[2]:Hide()
            acc:SetReveal(1)
            expect(clipH(acc)).eq(before - rowH() - gap())
        end)

        it("leaves an empty body at its padding, without erroring", function()
            local acc = accordion({ label = "Empty", open = true })
            expect(clipH(acc)).eq(gap() + pad())
            expect(acc._clip:IsShown()).truthy()
        end)
    end)

    ------------------------------------------------------------------------------
    describe("reveal clamping", function()
        it("clamps a negative reveal to zero and hides the window", function()
            local acc = accordion({ label = "General", open = true }, 2)
            acc:SetReveal(-5)
            expect(acc:GetReveal()).eq(0)
            expect(acc._clip:IsShown()).falsy()
        end)

        it("clamps a reveal above one back to one", function()
            local acc = accordion({ label = "General" }, 2)
            acc:SetReveal(7)
            expect(acc:GetReveal()).eq(1)
            expect(clipH(acc)).eq(bodyH(acc))
        end)

        it("leaves the logical state alone: the reveal is geometry, not policy", function()
            local acc = accordion({ label = "General" }, 2)
            acc:SetReveal(1)
            expect(acc:IsOpen()).as("SetReveal paints; it does not decide").falsy()
        end)

        it("flips the logical state without touching geometry via SetOpenState", function()
            local acc = accordion({ label = "General" }, 2)
            acc:SetOpenState(true)
            expect(acc:IsOpen()).truthy()
            expect(acc:GetReveal()).as("the owner drives the reveal itself").eq(0)
            expect(acc._chev:GetText()).as("but the header repaints").eq("v")
        end)
    end)

    ------------------------------------------------------------------------------
    describe("signals", function()
        it("emits CLICKED from the header, with the button, and opens nothing itself", function()
            local acc = accordion({ label = "General" }, 2)
            local spy = H.signalSpy(acc, H.S.SIGNALS.CLICKED)
            expect(H.click(acc:GetHeader())).truthy()
            expect(spy.count).eq(1)
            expect(spy:arg(1)).eq("LeftButton")
            expect(acc:IsOpen()).as("Accordion does not open itself: connect CLICKED or use a group").falsy()
        end)

        it("reports a right click as a right click", function()
            local acc = accordion({ label = "General" }, 2)
            local spy = H.signalSpy(acc, H.S.SIGNALS.CLICKED)
            H.click(acc:GetHeader(), "RightButton")
            expect(spy:arg(1)).eq("RightButton")
        end)

        it("stays silent on CLICKED when opened programmatically", function()
            local acc = accordion({ label = "General" }, 2)
            local spy = H.signalSpy(acc, H.S.SIGNALS.CLICKED)
            acc:SetOpen(true)
            H.runAnimations()
            acc:SetOpen(false, { animate = false })
            acc:SetReveal(0.5)
            expect(spy.count).as("setters are silent by contract").eq(0)
        end)

        it("re-emits the column's SIZE_CHANGED, so a parent container hears the open", function()
            local _, accs = column(1, 2)
            local spy = H.signalSpy(accs[1], H.S.SIGNALS.SIZE_CHANGED)
            accs[1]:SetOpen(true, { animate = false })
            expect(spy.count).as("a parent connects to the HANDLE, not the column").gte(1)
            expect(spy:arg(2)).eq(headerH() + bodyH(accs[1]))
        end)

        it("emits MOUSE_ENTER and MOUSE_LEAVE from the header", function()
            local acc = accordion({ label = "General" }, 1)
            local enter = H.signalSpy(acc, H.S.SIGNALS.MOUSE_ENTER)
            local leave = H.signalSpy(acc, H.S.SIGNALS.MOUSE_LEAVE)
            H.hover(acc:GetHeader())
            H.unhover(acc:GetHeader())
            expect(enter.count).eq(1)
            expect(leave.count).eq(1)
        end)

        it("emits VISIBILITY_CHANGED from Show and Hide", function()
            local acc = accordion({ label = "General" }, 1)
            local spy = H.signalSpy(acc, H.S.SIGNALS.VISIBILITY_CHANGED)
            acc:Hide()
            expect(spy:arg(1)).falsy()
            expect(acc:IsShown()).falsy()
            acc:Show()
            expect(spy:arg(1)).truthy()
            expect(spy.count).eq(2)
        end)

        it("emits TEXT_CHANGED from SetLabel and reports the new label", function()
            local acc = accordion({ label = "General" }, 1)
            local spy = H.signalSpy(acc, H.S.SIGNALS.TEXT_CHANGED)
            acc:SetLabel("Nameplates")
            expect(acc:GetLabel()).eq("Nameplates")
            expect(spy.count).eq(1)
            expect(spy:arg(1)).eq("Nameplates")
            H.expectTextNotClipped(acc._label)
        end)
    end)

    ------------------------------------------------------------------------------
    describe("no SetEnabled, deliberately", function()
        it("installs no enabled state at all", function()
            local acc = accordion({ label = "General" }, 1)
            expect(acc.SetEnabled)
                .as("an accordion HOLDS controls rather than being one: there is no value to grey")
                .isNil()
            expect(acc.IsEnabled).isNil()
        end)

        it("never fades its root, so a disabled row inside cannot multiply with it", function()
            local acc = accordion({ label = "General", open = true }, 2)
            expect(acc:GetFrame():GetAlpha())
                .as("a root fade would multiply with a disabled row's own (0.40 x 0.40 = 0.16)")
                .eq(1)
        end)

        it("keeps the base frame interface InstallBase provides", function()
            local acc = accordion({ label = "General" }, 1)
            expect(type(acc.GetFrame)).eq("function")
            expect(type(acc.GetWidth)).eq("function")
            expect(type(acc.SetSize)).eq("function")
            expect(type(acc.IsShown)).eq("function")
        end)
    end)

    ------------------------------------------------------------------------------
    describe("token-driven sizing", function()
        it("re-gutters the column and re-widens the rail when sizeRail grows", function()
            local acc = accordion({ label = "General", open = true }, 2)
            expect(acc._root:GetPadding().left).eq(rail())
            H.T:CreateUserTheme("WideRail", "Modern")
            H.T:SetUserToken("WideRail", "sizeRail", 6)
            H.T:SetActive("WideRail")

            expect(rail()).as("the token really moved").eq(6)
            expect(acc._root:GetPadding().left).eq(rail())
            expect(H.box(acc._rail).width).eq(rail())
            expect(H.box(acc:GetHeader()).left).eq(H.box(acc).left + rail())
            H.expectNoOverlap({ acc._rail, acc:GetHeader(), acc._clip:GetFrame() })
        end)

        it("grows the header and re-measures the chevron column when fontSizeMd grows", function()
            local acc = accordion({ label = "General" }, 2)
            local wasH, wasChev = acc:GetHeader():GetHeight(), H.box(acc._chev).width
            H.T:CreateUserTheme("BigFont", "Modern")
            H.T:SetUserToken("BigFont", "fontSizeMd", 24)
            H.T:SetActive("BigFont")

            expect(acc:GetHeader():GetHeight()).as("floored against the font").eq(headerH())
            expect(acc:GetHeader():GetHeight()).gt(wasH)
            expect(select(2, H.fontOf(acc._chev))).eq(24)
            expect(H.box(acc._chev).width).as("the column re-measures at the new font").eq(chevColumnIntended(acc))
            expect(H.box(acc._chev).width).gt(wasChev)
            H.expectInside(acc._chev, acc:GetHeader())
            H.expectInside(acc._label, acc:GetHeader())
            H.expectNoOverlap({ acc._chev, acc._label })
            H.expectTextNotClipped(acc._label)
            H.expectSize(acc, nil, headerH())
        end)

        it("keeps the header text unclipped even at a font the row token cannot contain", function()
            -- Above roughly 32pt the shipped floor in Theme:GetControlHeight -- max(sizeRow,
            -- fontSizeMd + spaceXs * 2) -- comes out SHORTER than the font's own line
            -- height, so the header box is a couple of units under its glyphs. That floor
            -- is shared by every text-bearing control rather than being the Accordion's,
            -- so what is asserted here is the part the Accordion owns: the header still
            -- re-derives from the token, and neither font string is clipped.
            local acc = accordion({ label = "General" }, 2)
            H.T:CreateUserTheme("HugeFont", "Modern")
            H.T:SetUserToken("HugeFont", "fontSizeMd", 40)
            H.T:SetActive("HugeFont")

            expect(acc:GetHeader():GetHeight()).eq(headerH())
            H.expectTextNotClipped(acc._label)
            H.expectTextNotClipped(acc._chev)
            expect(H.box(acc._chev).width).eq(chevColumnIntended(acc))
            H.expectNoOverlap({ acc._chev, acc._label })
            expect(H.box(acc._label).left)
                .as("the label still starts after the chevron column and the gap")
                .eq(H.box(acc:GetHeader()).left + pad() + chevColumnIntended(acc) + gap())
        end)

        it("re-derives an open window when the spacing scale grows", function()
            local acc = accordion({ label = "General", open = true }, 3)
            local was = clipH(acc)
            H.T:CreateUserTheme("Airy", "Modern")
            H.T:SetUserToken("Airy", "spaceXs", 10)
            H.T:SetActive("Airy")

            expect(clipH(acc))
                .as("a spacing edit moves every row, so an open window re-derives or clips the last one")
                .eq(bodyH(acc))
            expect(clipH(acc)).gt(was)
            local rows = acc:GetBody():GetChildren()
            H.expectStackedVertically(rows, gap())
            expect(H.isClipped(rows[3])).as("the last row still fits").falsy()
        end)

        it("snaps instead of animating when animFast is zero", function()
            H.T:CreateUserTheme("Instant", "Modern")
            H.T:SetUserToken("Instant", "animFast", 0)
            H.T:SetActive("Instant")
            local acc = accordion({ label = "General" }, 3)

            acc:SetOpen(true)
            expect(acc:GetReveal()).as("animFast 0 degrades to a snap").eq(1)
            expect(clipH(acc)).eq(bodyH(acc))
            expect(H.SuuUI.Anim:GetActiveCount(acc)).as("nothing animating").eq(0)
            acc:SetOpen(false)
            expect(acc:GetReveal()).eq(0)
            expect(H.SuuUI.Anim:GetActiveCount(acc)).eq(0)
        end)

        it("snaps when the caller asks for it, whatever the token says", function()
            local acc = accordion({ label = "General" }, 3)
            acc:SetOpen(true, { animate = false })
            expect(acc:GetReveal()).eq(1)
            expect(H.SuuUI.Anim:GetActiveCount(acc)).eq(0)
        end)

        it("does nothing when SetOpen is handed the state it already has", function()
            local acc = accordion({ label = "General", open = true }, 3)
            acc:SetOpen(true)
            expect(H.SuuUI.Anim:GetActiveCount(acc)).as("from == to, so no tween").eq(0)
            expect(acc:GetReveal()).eq(1)
        end)
    end)

    ------------------------------------------------------------------------------
    describe("layout integration", function()
        it("fills the width a parent column gives it", function()
            local col, accs = column(1, 2)
            expect(H.box(accs[1]).width).eq(col:GetWidth())
            expect(H.box(accs[1]:GetHeader()).width).eq(col:GetWidth() - rail())
        end)

        it("re-fills the header when the parent column is resized", function()
            local col, accs = column(1, 2)
            accs[1]:SetOpen(true, { animate = false })
            col:SetWidth(260)
            expect(H.box(accs[1]:GetHeader()).width).eq(260 - rail())
            expect(H.box(accs[1]._clip).width).eq(260 - rail())
            local rows = accs[1]:GetBody():GetChildren()
            expect(H.box(rows[1]).width).eq(260 - rail())
            H.expectTextNotClipped(accs[1]._label)
        end)

        it("stacks the groups by the column's own gap while all are closed", function()
            local col, accs = column(3, 2)
            H.expectStackedVertically({ accs[1], accs[2], accs[3] }, pad())
            expect(H.box(accs[3]).bottom - H.box(accs[1]).top)
                .as("three collapsed headers plus two column gaps")
                .eq(headerH() * 3 + pad() * 2)
            expect(col:GetHeight()).eq(headerH() * 3 + pad() * 2)
        end)

        it("pushes the groups below down by exactly the window height when one opens", function()
            local _, accs = column(3, 2)
            local before = { H.box(accs[2]).top, H.box(accs[3]).top }
            accs[1]:SetOpen(true, { animate = false })
            local grown = clipH(accs[1])
            expect(H.box(accs[2]).top).as("displaced by the window alone").eq(before[1] + grown)
            expect(H.box(accs[3]).top).eq(before[2] + grown)
            H.expectStackedVertically({ accs[1], accs[2], accs[3] }, pad())
        end)
    end)

    ------------------------------------------------------------------------------
    describe("no end-of-close gap pop", function()
        -- A collapsed window contributes no height either way, but a SHOWN one would also
        -- contribute the column's gap -- which then vanishes the instant it is hidden,
        -- popping every group below it by spaceXs at the end of every close. So the root
        -- column's gap is ZERO, with the spacing carried inside the header and the body.
        it("displaces the group below by the window alone while open", function()
            local _, accs = column(2, 3)
            local a, b = accs[1], accs[2]
            local top0 = H.box(b).top

            a:SetOpen(true)
            H.runAnimations()
            expect(H.box(b).top - top0)
                .as("the root column's gap is ZERO: an open group displaces by its window and nothing else")
                .eq(clipH(a))
        end)

        it("displaces by the window alone at every point of a close", function()
            local _, accs = column(2, 3)
            local a, b = accs[1], accs[2]
            local top0 = H.box(b).top

            a:SetOpen(true)
            H.runAnimations()
            a:SetOpen(false)
            H.tick(dur() * 0.5)
            expect(a._clip:IsShown()).as("still mid-close").truthy()
            expect(H.box(b).top - top0)
                .as("mid-close: displaced by the visible window, never by a gap that is about to vanish")
                .eq(clipH(a))
        end)

        it("returns the group below to exactly its original top after a full close", function()
            local _, accs = column(2, 3)
            local a, b = accs[1], accs[2]
            local top0 = H.box(b).top

            a:SetOpen(true)
            H.runAnimations()
            a:SetOpen(false)
            H.runAnimations()
            expect(H.box(b).top)
                .as("no pop at the end of the close: the second group's top is EXACTLY where it started")
                .eq(top0)
        end)

        it("survives repeated cycles without drifting", function()
            local _, accs = column(3, 2)
            local tops = { H.box(accs[2]).top, H.box(accs[3]).top }
            for _ = 1, 3 do
                accs[1]:SetOpen(true)
                H.runAnimations()
                accs[1]:SetOpen(false)
                H.runAnimations()
            end
            expect(H.box(accs[2]).top).eq(tops[1])
            expect(H.box(accs[3]).top).eq(tops[2])
        end)
    end)

    ------------------------------------------------------------------------------
    describe("theme reaction", function()
        it("restyles on a theme switch without losing the open window", function()
            local acc = accordion({ label = "General", open = true }, 3)
            H.T:SetActive("Default")
            expect(acc:IsOpen()).truthy()
            expect(clipH(acc)).eq(bodyH(acc))
            expect(acc:GetHeader():GetHeight()).eq(headerH())
            expect(acc._root:GetPadding().left).eq(rail())
            H.expectTokenColor(H.backdropColor(acc:GetHeader()), "colorBgAlt")
            H.expectTokenColor(H.backdropColor(acc._clip:GetFrame()), "colorBgAlt")
        end)

        it("recolours the rail on an accent edit", function()
            local acc = accordion({ label = "General", open = true }, 1)
            H.T:CreateUserTheme("Red", "Modern")
            H.T:SetUserToken("Red", "colorAccent", { 1, 0, 0, 1 })
            H.T:SetActive("Red")
            H.expectTokenColor({ acc._rail:GetColorTexture() }, "colorAccent")
            expect(acc._rail:GetColorTexture()).near(1, 0.001)
        end)

        it("leaves a closed group closed and its window hidden through a restyle", function()
            local acc = accordion({ label = "General" }, 3)
            H.T:SetActive("Default")
            expect(acc:GetReveal()).eq(0)
            expect(acc._clip:IsShown()).as("a restyle must not reveal a closed group").falsy()
        end)
    end)

    ------------------------------------------------------------------------------
    describe("edge cases", function()
        it("builds from an empty props table", function()
            local acc = accordion({})
            expect(acc:GetLabel()).eq("")
            expect(acc:IsOpen()).falsy()
            H.expectSize(acc, nil, headerH())
        end)

        it("does not clip an empty label, and reserves no chevron shift for it", function()
            local acc = accordion({ label = "" }, 1)
            H.expectTextNotClipped(acc._label)
            expect(H.box(acc._chev).width).eq(chevColumnIntended(acc))
        end)

        it("accepts a label set to the empty string later", function()
            local acc = accordion({ label = "General" }, 1)
            local left = H.box(acc._label).left
            acc:SetLabel("")
            expect(acc:GetLabel()).eq("")
            expect(H.box(acc._label).left).as("the chevron column does not move").eq(left)
        end)

        it("opens a body that has no rows at all", function()
            local acc = accordion({ label = "Empty" }, nil)
            acc:SetOpen(true)
            H.runAnimations()
            expect(acc:GetReveal()).eq(1)
            expect(clipH(acc)).eq(bodyH(acc))
        end)

        it("keeps the window inside the column at every reveal fraction", function()
            local acc = accordion({ label = "General", open = true }, 3)
            for _, f in ipairs({ 0.1, 0.25, 0.5, 0.75, 1 }) do
                acc:SetReveal(f)
                H.expectInside(acc._clip:GetFrame(), acc:GetFrame())
                H.expectNoOverlap({ acc:GetHeader(), acc._clip:GetFrame() })
            end
        end)
    end)

    ------------------------------------------------------------------------------
    describe("teardown", function()
        it("hides and disconnects its signals", function()
            local acc = accordion({ label = "General" }, 2)
            local spy = H.signalSpy(acc, H.S.SIGNALS.CLICKED)
            acc:Destroy()
            expect(acc:IsShown()).falsy()
            expect(H.S:HasConnections(acc, H.S.SIGNALS.CLICKED)).falsy()
            expect(H.S:HasConnections(acc, H.S.SIGNALS.SIZE_CHANGED)).falsy()
            expect(spy.count).eq(0)
        end)

        it("unsubscribes from SUUUI_THEME_CHANGED, so a later token edit cannot re-gutter it", function()
            local acc = accordion({ label = "General" }, 2)
            local was = acc._root:GetPadding().left
            acc:Destroy()
            H.T:CreateUserTheme("Later", "Modern")
            H.T:SetUserToken("Later", "sizeRail", 8)
            H.T:SetActive("Later")
            expect(acc._root:GetPadding().left).as("a destroyed accordion must not restyle").eq(was)
        end)

        it("takes its owned Text handles with it: they stop re-measuring too", function()
            local acc = accordion({ label = "General" }, 2)
            local was = acc._label:GetHeight()
            acc:Destroy()
            H.T:CreateUserTheme("Later", "Modern")
            H.T:SetUserToken("Later", "fontSizeMd", 40)
            H.T:SetActive("Later")
            expect(acc._label:GetHeight()).as("the adopted header box was destroyed explicitly").eq(was)
        end)

        it("leaves nothing animating", function()
            local acc = accordion({ label = "General" }, 3)
            acc:SetOpen(true)
            H.tick(dur() * 0.25)
            expect(H.SuuUI.Anim:GetActiveCount(acc)).as("a tween is genuinely in flight").eq(1)
            acc:Destroy()
            expect(H.SuuUI.Anim:GetActiveCount(acc))
                .as("an animation left running keeps writing into freed state").eq(0)
            H.runAnimations()
            expect(H.SuuUI.Anim:GetActiveCount(acc)).eq(0)
        end)

        it("cascades to the rows a caller added", function()
            local acc = accordion({ label = "General", open = true }, 3)
            local rows = acc:GetBody():GetChildren()
            acc:Destroy()
            expect(acc._clip:IsShown()).as("the column cascades into the window").falsy()
            expect(acc:GetBody():IsShown()).as("and on into the body").falsy()
            expect(rows[1]:IsVisible())
                .as("a row draws nothing once its body is hidden, even though its own flag is untouched")
                .falsy()
        end)

        it("stops emitting from the header after Destroy", function()
            local acc = accordion({ label = "General" }, 2)
            local spy = H.signalSpy(acc, H.S.SIGNALS.CLICKED)
            acc:Destroy()
            H.forceClick(acc:GetHeader())
            expect(spy.count).as("the signal has no listeners left").eq(0)
        end)
    end)
end)

----------------------------------------------------------------------------------

describe("Components.AccordionGroup", function()
    local host
    before_each(function()
        H.setup()
        host = H.parent(400, 700)
    end)

    local function rowH() return H.token("sizeControlSm") end
    local function dur()  return H.token("animFast") end

    local function addRows(acc, n)
        local body = acc:GetBody()
        for _ = 1, n do
            local f = H.env.CreateFrame("Frame", nil, body:GetFrame())
            f:SetHeight(rowH())
            body:Add(f, { width = "fill", height = rowH() })
        end
    end

    local function groupOf(n, rows)
        local col = H.Layout:CreateContainer({
            parent = host, layout = "flow", dir = "vertical", gap = H.token("spaceSm"),
        })
        local grp, accs = H.C.AccordionGroup(), {}
        for i = 1, n do
            local a = H.C.Accordion({ label = "Group " .. i }, col:GetFrame())
            addRows(a, rows or 2)
            col:Add(a, { width = "fill" })
            grp:Add(a)
            accs[i] = a
        end
        return grp, accs, col
    end

    local function reveals(accs)
        local out = {}
        for i = 1, #accs do out[i] = accs[i]:GetReveal() end
        return out
    end

    local function openCount(accs)
        local n = 0
        for i = 1, #accs do if accs[i]:IsOpen() then n = n + 1 end end
        return n
    end

    ------------------------------------------------------------------------------
    describe("construction", function()
        it("owns no frame: it arbitrates, it is not a widget", function()
            local grp = H.C.AccordionGroup()
            expect(grp.GetFrame).as("never laid out, so it needs no frame").isNil()
            expect(grp:GetOpen()).isNil()
            expect(grp:GetMembers()).len(0)
        end)

        it("keeps members in the order they were added and returns the handle for chaining", function()
            local grp, accs = groupOf(3)
            local members = grp:GetMembers()
            expect(members).len(3)
            for i = 1, 3 do expect(members[i]).eq(accs[i]) end
        end)

        it("starts with every member collapsed", function()
            local _, accs = groupOf(3)
            expect(openCount(accs)).eq(0)
            expect(reveals(accs)).deepEq({ 0, 0, 0 })
        end)
    end)

    ------------------------------------------------------------------------------
    describe("one animation, not two", function()
        it("drives a close and an open from a single tween", function()
            local grp, accs = groupOf(3)
            grp:Open(accs[1])
            H.runAnimations()
            expect(H.SuuUI.Anim:GetActiveCount()).as("settled").eq(0)

            grp:Open(accs[2])
            expect(H.SuuUI.Anim:GetActiveCount())
                .as("ONE tween for both members: two height animations would re-flow the whole page twice per frame")
                .eq(1)
            expect(H.SuuUI.Anim:GetActiveCount(grp))
                .as("and it is owned by the group, not by either member").eq(1)
            expect(H.SuuUI.Anim:GetActiveCount(accs[1])).eq(0)
            expect(H.SuuUI.Anim:GetActiveCount(accs[2])).eq(0)
        end)

        it("moves both members in step within that one tween", function()
            local grp, accs = groupOf(3)
            grp:Open(accs[1])
            H.runAnimations()
            grp:Open(accs[2])
            H.tick(dur() * 0.5)
            local r = reveals(accs)
            expect(r[1]).as("the outgoing member is part-way out").between(0.0001, 0.9999)
            expect(r[2]).as("the incoming member is part-way in").between(0.0001, 0.9999)
            expect(r[1] + r[2]).as("one tween, so the two are exact complements").near(1, 0.0001)
        end)

        it("still runs one tween opening from an all-closed board", function()
            local grp, accs = groupOf(3)
            grp:Open(accs[2])
            expect(H.SuuUI.Anim:GetActiveCount()).eq(1)
            H.runAnimations()
            expect(accs[2]:GetReveal()).eq(1)
        end)

        it("continues an interrupted transition from where it actually is", function()
            local grp, accs = groupOf(3)
            grp:Open(accs[1])
            H.runAnimations()
            grp:Open(accs[2])
            H.tick(dur() * 0.5)
            local mid = accs[2]:GetReveal()
            grp:Open(accs[3])
            expect(accs[2]:GetReveal())
                .as("`from` is the member's CURRENT reveal, so nothing snaps on interruption")
                .near(mid, 0.0001)
            expect(H.SuuUI.Anim:GetActiveCount())
                .as("the new tween pre-empts the old one on (group, value)").eq(1)
        end)
    end)

    ------------------------------------------------------------------------------
    describe("exclusivity", function()
        it("keeps exactly one member open as each header is clicked", function()
            local grp, accs = groupOf(3)
            for i = 1, 3 do
                expect(H.click(accs[i]:GetHeader())).as("header " .. i .. " takes the click").truthy()
                H.runAnimations()
                expect(openCount(accs)).as("exactly one open after clicking header " .. i).eq(1)
                expect(accs[i]:IsOpen()).truthy()
                expect(grp:GetOpen()).eq(accs[i])
                for j = 1, 3 do
                    if j ~= i then
                        expect(accs[j]:GetReveal())
                            .as("member " .. j .. " returned to zero").eq(0)
                        expect(accs[j]._clip:IsShown())
                            .as("member " .. j .. "'s window is hidden, costing no height").falsy()
                    end
                end
            end
        end)

        it("drives the reveal only from the group, never from the member itself", function()
            local grp, accs = groupOf(3)
            H.click(accs[1]:GetHeader())
            expect(H.SuuUI.Anim:GetActiveCount(grp))
                .as("the group owns the motion").eq(1)
            for i = 1, 3 do
                expect(H.SuuUI.Anim:GetActiveCount(accs[i]))
                    .as("member " .. i .. " runs no tween of its own: a self-toggling member would fight the group's single tween")
                    .eq(0)
            end
            H.tick(dur() * 0.5)
            H.click(accs[2]:GetHeader())
            for i = 1, 3 do
                expect(H.SuuUI.Anim:GetActiveCount(accs[i]))
                    .as("member " .. i .. " still runs no tween of its own mid-transition").eq(0)
            end
            H.runAnimations()
            expect(openCount(accs)).eq(1)
            expect(grp:GetOpen()).eq(accs[2])
        end)

        it("leaves only the open member's window contributing height", function()
            local grp, accs = groupOf(3)
            H.click(accs[2]:GetHeader())
            H.runAnimations()
            expect(accs[1]:GetFrame():GetHeight()).eq(H.controlHeight("sizeRow"))
            expect(accs[3]:GetFrame():GetHeight()).eq(H.controlHeight("sizeRow"))
            expect(accs[2]:GetFrame():GetHeight())
                .eq(H.controlHeight("sizeRow") + accs[2]._clip:GetFrame():GetHeight())
            expect(grp:GetOpen()).eq(accs[2])
        end)

        it("never lets two windows draw at once, even mid-transition", function()
            local grp, accs = groupOf(3)
            H.click(accs[1]:GetHeader())
            H.runAnimations()
            H.click(accs[2]:GetHeader())
            H.tick(dur() * 0.5)
            H.expectNoOverlap({ accs[1]._clip:GetFrame(), accs[2]._clip:GetFrame(),
                                accs[3]:GetHeader() })
            expect(grp:GetOpen()).eq(accs[2])
        end)

        it("closes whichever was open when Open is called directly", function()
            local grp, accs = groupOf(3)
            grp:Open(accs[1], { animate = false })
            grp:Open(accs[3], { animate = false })
            expect(reveals(accs)).deepEq({ 0, 0, 1 })
            expect(openCount(accs)).eq(1)
        end)

        it("collapses everything when handed nil", function()
            local grp, accs = groupOf(3)
            grp:Open(accs[2])
            H.runAnimations()
            grp:Open(nil)
            H.runAnimations()
            expect(grp:GetOpen()).isNil()
            expect(reveals(accs)).deepEq({ 0, 0, 0 })
        end)
    end)

    ------------------------------------------------------------------------------
    describe("clicking the open header collapses it", function()
        it("empties the group: one at a time does not mean one always", function()
            local grp, accs = groupOf(3)
            H.click(accs[2]:GetHeader())
            H.runAnimations()
            expect(grp:GetOpen()).eq(accs[2])

            H.click(accs[2]:GetHeader())
            H.runAnimations()
            expect(grp:GetOpen())
                .as("an all-closed page is how a player scans a long one for the group they want")
                .isNil()
            expect(reveals(accs)).deepEq({ 0, 0, 0 })
            expect(openCount(accs)).eq(0)
            for i = 1, 3 do
                expect(accs[i]._clip:IsShown()).as("window " .. i .. " hidden").falsy()
            end
        end)

        it("returns the whole column to its collapsed heights", function()
            local grp, accs = groupOf(3)
            local was = { accs[1]:GetFrame():GetHeight(), H.box(accs[2]).top, H.box(accs[3]).top }
            H.click(accs[1]:GetHeader())
            H.runAnimations()
            H.click(accs[1]:GetHeader())
            H.runAnimations()
            expect(accs[1]:GetFrame():GetHeight()).eq(was[1])
            expect(H.box(accs[2]).top).as("no pop: the groups below are back where they started").eq(was[2])
            expect(H.box(accs[3]).top).eq(was[3])
            expect(grp:GetOpen()).isNil()
        end)

        it("re-opens on the next click", function()
            local grp, accs = groupOf(3)
            H.click(accs[1]:GetHeader())
            H.runAnimations()
            H.click(accs[1]:GetHeader())
            H.runAnimations()
            H.click(accs[1]:GetHeader())
            H.runAnimations()
            expect(grp:GetOpen()).eq(accs[1])
            expect(accs[1]:GetReveal()).eq(1)
        end)
    end)

    ------------------------------------------------------------------------------
    describe("interruption", function()
        -- Setup shared by the pair below: member 1 open, member 2 half-way in, then a
        -- click on member 3. Member 1 is mid-CLOSE at that moment, driven by a tween the
        -- third click pre-empts.
        local function interrupted()
            local grp, accs, col = groupOf(3)
            H.click(accs[1]:GetHeader())
            H.runAnimations()
            H.click(accs[2]:GetHeader())
            H.tick(dur() * 0.5)
            H.click(accs[3]:GetHeader())
            H.runAnimations()
            return grp, accs, col
        end

        it("brings the member that was clicked last fully open", function()
            local grp, accs = interrupted()
            expect(accs[3]:GetReveal()).as("the incoming member finishes its reveal").eq(1)
            expect(grp:GetOpen()).eq(accs[3])
            expect(openCount(accs)).as("exactly one member is logically open").eq(1)
            expect(H.SuuUI.Anim:GetActiveCount()).as("nothing still running").eq(0)
        end)

        it("closes the member the new tween did take over", function()
            local _, accs = interrupted()
            expect(accs[2]:GetReveal())
                .as("member 2 was the new tween's `prev`, so it was driven to zero").eq(0)
            expect(accs[2]._clip:IsShown()).falsy()
        end)

        it("strands nothing part-open when a third header is clicked mid-transition", function()
            local _, accs = interrupted()
            -- `Open` drives EVERY member from its one tween, not just `prev` and `acc`.
            -- Member 1 is neither by the time the third click lands — it was being closed
            -- by the SECOND tween, which Play() pre-empts on (group, "value") — so driving
            -- only those two left it stranded at a fractional reveal with its window shown,
            -- permanently contributing height while IsOpen() reported closed.
            local r = reveals(accs)
            local ones, zeroes = 0, 0
            for i = 1, 3 do
                if r[i] == 1 then ones = ones + 1 elseif r[i] == 0 then zeroes = zeroes + 1 end
            end
            expect(ones).as("exactly one member ends open").eq(1)
            expect(zeroes).as("and every other lands at exactly zero").eq(2)
            expect(accs[1]._clip:IsShown())
                .as("the pre-empted close finished, so its window is hidden again").falsy()
            expect(accs[1]:GetFrame():GetHeight())
                .as("a collapsed group is exactly its header")
                .near(H.controlHeight("sizeRow"), 0.51)
        end)

        it("ignores a body resize mid-tween instead of snapping the reveal to full", function()
            local _, accs = groupOf(3)
            H.click(accs[1]:GetHeader())
            H.tick(dur() * 0.4)
            local mid = accs[1]:GetReveal()
            expect(mid).as("genuinely mid-tween").between(0.0001, 0.9999)

            -- A row appearing while the reveal runs -- a dependency ungreying a control, a
            -- font re-measure -- resizes the body and emits SIZE_CHANGED. The tween owns the
            -- reveal for its duration, so that handler has to stand down. It is gated on
            -- `_animating`, which the GROUP path did not set: the guard existed but was dead
            -- on the only path the settings UI uses.
            addRows(accs[1], 1)
            expect(accs[1]:GetReveal())
                .as("a body resize must not snap the reveal while the group's tween owns it")
                .lt(1)
            H.runAnimations()
            expect(accs[1]:GetReveal()).as("and it still finishes").eq(1)
            expect(accs[1]._clip:GetHeight())
                .as("landing on the body's NEW height, row included")
                .eq(select(2, accs[1]:GetBody():GetContentSize()))
        end)

        it("continues the incoming member from where it actually is, never snapping it back", function()            local grp, accs = groupOf(3)
            H.click(accs[1]:GetHeader())
            H.runAnimations()
            H.click(accs[2]:GetHeader())
            H.tick(dur() * 0.5)
            local mid = accs[2]:GetReveal()
            H.click(accs[3]:GetHeader())
            expect(accs[2]:GetReveal())
                .as("`from` is each member's CURRENT reveal, so an interruption does not jump")
                .near(mid, 0.0001)
            expect(grp:GetOpen()).eq(accs[3])
        end)

        it("leaves the column consistent when the interruption only involves two members", function()
            local grp, accs = groupOf(3)
            local tops = { H.box(accs[2]).top, H.box(accs[3]).top }
            H.click(accs[1]:GetHeader())
            H.runAnimations()
            H.click(accs[2]:GetHeader())
            H.tick(dur() * 0.5)
            H.click(accs[1]:GetHeader())
            H.runAnimations()
            H.click(accs[1]:GetHeader())
            H.runAnimations()
            expect(grp:GetOpen()).isNil()
            expect(reveals(accs)).as("both members involved were driven home").deepEq({ 0, 0, 0 })
            expect(H.box(accs[2]).top).eq(tops[1])
            expect(H.box(accs[3]).top).eq(tops[2])
        end)

        it("survives a burst of clicks across every member", function()
            local grp, accs = groupOf(3)
            for _, i in ipairs({ 1, 2, 3, 1, 3, 2 }) do
                H.click(accs[i]:GetHeader())
                H.tick(dur() * 0.3)
            end
            H.runAnimations()
            expect(openCount(accs)).as("exactly one member logically open").eq(1)
            expect(grp:GetOpen()).eq(accs[2])
            expect(accs[2]:GetReveal()).as("and it is fully revealed").eq(1)
            expect(H.SuuUI.Anim:GetActiveCount()).as("nothing left running").eq(0)
        end)

        it("settles every member when each transition is allowed to finish", function()
            local grp, accs = groupOf(3)
            for _, i in ipairs({ 1, 2, 3, 1, 3, 2 }) do
                H.click(accs[i]:GetHeader())
                H.runAnimations()
            end
            expect(reveals(accs)).deepEq({ 0, 1, 0 })
            expect(grp:GetOpen()).eq(accs[2])
        end)
    end)

    ------------------------------------------------------------------------------
    describe("degradation without a clip", function()
        it("snaps rather than spilling rows over the group below", function()
            local grp, accs = groupOf(2)
            -- Feature-detected in the component; forced off here to exercise the fallback.
            accs[1]._clips = false
            grp:Open(accs[1])
            expect(accs[1]:GetReveal())
                .as("a member that cannot clip would spill its rows for the whole tween").eq(1)
            expect(H.SuuUI.Anim:GetActiveCount(grp)).eq(0)
        end)

        it("snaps the whole group when any single member cannot clip", function()
            local grp, accs = groupOf(3)
            accs[3]._clips = false
            grp:Open(accs[1])
            expect(accs[1]:GetReveal()).eq(1)
            grp:Open(accs[2])
            expect(reveals(accs)).deepEq({ 0, 1, 0 })
            expect(H.SuuUI.Anim:GetActiveCount(grp)).eq(0)
        end)
    end)

    ------------------------------------------------------------------------------
    describe("signals", function()
        it("emits OPEN_CHANGED with the new member and the previous one", function()
            local grp, accs = groupOf(3)
            local spy = H.signalSpy(grp, H.C.ACCORDION_SIGNALS.OPEN_CHANGED)
            grp:Open(accs[1])
            expect(spy.count).eq(1)
            expect(spy:arg(1)).eq(accs[1])
            expect(spy:arg(2)).as("nothing was open before").isNil()

            grp:Open(accs[2])
            expect(spy.count).eq(2)
            expect(spy:arg(1)).eq(accs[2])
            expect(spy:arg(2)).eq(accs[1])
        end)

        it("emits a nil open member when the group collapses", function()
            local grp, accs = groupOf(3)
            grp:Open(accs[1])
            local spy = H.signalSpy(grp, H.C.ACCORDION_SIGNALS.OPEN_CHANGED)
            grp:Open(accs[1])
            expect(spy.count).eq(1)
            expect(spy:arg(1)).as("nil means the group is fully collapsed").isNil()
            expect(spy:arg(2)).eq(accs[1])
        end)

        it("stays silent when asked for the state it already has", function()
            local grp, accs = groupOf(3)
            local spy = H.signalSpy(grp, H.C.ACCORDION_SIGNALS.OPEN_CHANGED)
            grp:Open(nil)
            expect(spy.count).as("already collapsed, so nothing changed").eq(0)
            grp:Open(accs[1])
            grp:Open(accs[1], { animate = false })
            expect(spy.count).as("the second call collapsed it, which is a change").eq(2)
        end)

        it("emits once per click, not once per member repainted", function()
            local grp, accs = groupOf(3)
            local spy = H.signalSpy(grp, H.C.ACCORDION_SIGNALS.OPEN_CHANGED)
            H.click(accs[1]:GetHeader())
            H.runAnimations()
            H.click(accs[3]:GetHeader())
            H.runAnimations()
            expect(spy.count).eq(2)
        end)
    end)

    ------------------------------------------------------------------------------
    describe("edge cases", function()
        it("handles Open on an empty group", function()
            local grp = H.C.AccordionGroup()
            grp:Open(nil)
            expect(grp:GetOpen()).isNil()
        end)

        it("honours an explicit duration and easing override", function()
            local col = H.Layout:CreateContainer({ parent = host, layout = "flow", dir = "vertical" })
            local grp = H.C.AccordionGroup({ duration = 0, easing = "linear" })
            local a = H.C.Accordion({ label = "A" }, col:GetFrame())
            addRows(a, 2)
            col:Add(a, { width = "fill" })
            grp:Add(a)
            grp:Open(a)
            expect(a:GetReveal()).as("duration 0 degrades to a snap").eq(1)
            expect(H.SuuUI.Anim:GetActiveCount(grp)).eq(0)
        end)

        it("arbitrates a single-member group", function()
            local grp, accs = groupOf(1)
            H.click(accs[1]:GetHeader())
            H.runAnimations()
            expect(grp:GetOpen()).eq(accs[1])
            H.click(accs[1]:GetHeader())
            H.runAnimations()
            expect(grp:GetOpen()).isNil()
        end)

        it("takes over the member's header click, so the member never self-toggles", function()
            local col = H.Layout:CreateContainer({ parent = host, layout = "flow", dir = "vertical" })
            local a = H.C.Accordion({ label = "A" }, col:GetFrame())
            addRows(a, 2)
            col:Add(a, { width = "fill" })
            H.click(a:GetHeader())
            H.runAnimations()
            expect(a:IsOpen()).as("ungrouped, a header click opens nothing by itself").falsy()

            local grp = H.C.AccordionGroup()
            grp:Add(a)
            H.click(a:GetHeader())
            H.runAnimations()
            expect(a:IsOpen()).as("the group is what turns a click into an open").truthy()
        end)
    end)

    ------------------------------------------------------------------------------
    describe("teardown", function()
        it("stops arbitrating: a click on a member reopens nothing", function()
            local grp, accs = groupOf(3)
            grp:Destroy()
            expect(H.click(accs[1]:GetHeader())).as("the header still takes input").truthy()
            H.runAnimations()
            expect(grp:GetOpen()).isNil()
            expect(accs[1]:IsOpen()).falsy()
            expect(reveals(accs)).deepEq({ 0, 0, 0 })
        end)

        it("drops its own CLICKED subscriptions from every member", function()
            local grp, accs = groupOf(3)
            grp:Destroy()
            for i = 1, 3 do
                expect(H.S:HasConnections(accs[i], H.S.SIGNALS.CLICKED))
                    .as("member " .. i .. " has no group listener left").falsy()
            end
            expect(grp:GetMembers()).len(0)
        end)

        it("cancels a transition still in flight", function()
            local grp, accs = groupOf(3)
            grp:Open(accs[1])
            H.tick(dur() * 0.25)
            expect(H.SuuUI.Anim:GetActiveCount(grp)).eq(1)
            grp:Destroy()
            expect(H.SuuUI.Anim:GetActiveCount(grp)).eq(0)
            H.runAnimations()
            expect(H.SuuUI.Anim:GetActiveCount(grp)).eq(0)
        end)

        it("does NOT destroy its members: the container that lays them out owns them", function()
            local grp, accs = groupOf(3)
            grp:Destroy()
            for i = 1, 3 do
                expect(accs[i]:IsShown()).as("member " .. i .. " survives its group").truthy()
                expect(accs[i]:GetHeader():IsMouseEnabled()).truthy()
            end
        end)

        it("drops its OPEN_CHANGED listeners", function()
            local grp, accs = groupOf(3)
            local spy = H.signalSpy(grp, H.C.ACCORDION_SIGNALS.OPEN_CHANGED)
            grp:Destroy()
            expect(H.S:HasConnections(grp, H.C.ACCORDION_SIGNALS.OPEN_CHANGED)).falsy()
            expect(spy.count).eq(0)
        end)
    end)
end)
