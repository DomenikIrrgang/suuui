local H = require("harness")

-- FlyoutPanel: the floating icon-and-name roster. Two of the assertions here exist because of
-- a defect that FROZE THE CLIENT, and they are the reason this file leads with construction
-- rather than with geometry.
--
-- The first build nested a hugging horizontal flow inside a stack child with valign
-- "stretch". A container with no height of its own takes its height from its content; a
-- stretched stack child takes its height from its parent; a container that is both takes its
-- height from the stack while the stack takes its height from it, and they ping-pong for ever
-- on the first layout pass. Rows are built lazily on first open, so the hang landed exactly
-- on mouseover and nothing before it. "the panel opens with rows" is therefore not a trivial
-- smoke test -- with that structure it never returns, and the whole suite hangs with it.
--
-- The second is that Container:Add is MEMBERSHIP, not an upsert. SetRows runs on every open,
-- every theme change and every icon-size change, so re-adding an adopted frame appended it
-- again each time and every pass cost more than the last.

local function root()
    return H.SuuUI.UIRoot:GetRootContainer():GetFrame()
end

-- A stand-in for a foreign addon's minimap button: a real Button with a name that looks like
-- one, which is all the collector's filter and the panel's adoption care about.
local function fakeButton(name)
    local f = H.env.CreateFrame("Button", name, root())
    f:SetSize(31, 31)
    return f
end

local function entriesOf(n, withClick)
    local list = {}
    for i = 1, n do
        list[i] = {
            key   = "Addon" .. i .. "MinimapButton",
            label = "Addon " .. i,
            frame = fakeButton("Addon" .. i .. "MinimapButton"),
        }
        if withClick then list[i].onClick = function() end end
    end
    return list
end

describe("Components.FlyoutPanel – the floating icon-and-name roster", function()

    describe("the concept's spacing", function()
        -- Pinned because the panel passed every other spec while reading as "super cramped" in game:
        -- geometry assertions about rows and columns say nothing about the space AROUND them.
        local function roster()
            local p = H.mount(H.C.FlyoutPanel({ filter = true, maxRows = 8 }, H.UIParent))
            p:SetRows({
                { key = "a", label = "Velementina", meta = "12h", onClick = function() end },
                { key = "b", label = "Tangolock",   meta = "15h", onClick = function() end },
            })
            p:Open()
            return p
        end

        it("pads the panel by spaceSm, not spaceXs", function()
            local p = roster()
            local pad = H.token("spaceSm")
            expect(H.box(p._rows[1]).left - H.box(p).left)
                .as("the row clears the panel edge by a full spaceSm").eq(pad)
        end)

        it("leaves spaceXs above and below each disc", function()
            local p = roster()
            local want = p:GetIconSize() and (p:GetIconSize() + H.token("spaceXs") * 2)
                      or (H.token("sizeIcon") + H.token("spaceXs") * 2)
            expect(H.box(p._rows[1]).height)
                .as("a row is tall enough not to pack the discs together").gte(want)
        end)

        it("insets the search field from the panel border", function()
            -- Shipped flush against the border: the field's inset was stated once at construction from
            -- the OLD pad, so the panel's padding grew and the field did not move.
            local p = roster()
            local pad = H.token("spaceSm")
            expect(H.box(p._search).left - H.box(p).left).eq(pad)
            expect(H.box(p._search).top - H.box(p).top).eq(pad)
        end)

        it("is wide enough for its own placeholder", function()
            -- The panel hugs its ROWS, so a roster of short names produced a panel narrower than its own
            -- field and the placeholder rendered as "Search conversatio...".
            local p = roster()
            H.expectTextNotClipped(p._search._phText or p._search:GetFrame())
            local font = H.SuuUI.Fonts:Path(H.SuuUI.Theme:GetToken("fontFamilyMain"))
            -- The panel's OWN placeholder, not a literal: the helper takes the default, so measuring
            -- the chat plugin's longer string asserted against a value this panel never received.
            local need = H.SuuUI.TextMetrics.Box(p._placeholder, font,
                                                 H.SuuUI.Theme:GetFontSize("md"))
            expect(H.box(p._search).width).as("the field can draw its placeholder").gte(need)
        end)

        it("widens for a LONG placeholder that the rows alone would not fit", function()
            -- The default "Search…" is short enough that the row widths already cover it, so the floor
            -- is only observable with a placeholder longer than the roster -- which is exactly the chat
            -- plugin's case ("Search conversations…") and where it shipped truncated.
            local short = H.mount(H.C.FlyoutPanel({ filter = true, maxRows = 8 }, H.UIParent))
            short:SetRows({ { key = "a", label = "Al", onClick = function() end } })
            short:Open()
            local long = H.mount(H.C.FlyoutPanel({
                filter = true, maxRows = 8, filterPlaceholder = "Search conversations…",
            }, H.UIParent))
            long:SetRows({ { key = "a", label = "Al", onClick = function() end } })
            long:Open()
            expect(H.box(long).width).as("the longer field widens the panel").gt(H.box(short).width)
            local font = H.SuuUI.Fonts:Path(H.SuuUI.Theme:GetToken("fontFamilyMain"))
            expect(H.box(long._search).width).gte(
                H.SuuUI.TextMetrics.Box("Search conversations…", font,
                                        H.SuuUI.Theme:GetFontSize("md")))
        end)

        it("keeps the LAST row clear of the count line", function()
            -- The footer height was read off a Text nothing had laid out yet, which answers 0 -- so only
            -- a gap was reserved and the last row drew straight through the count.
            local p = roster()
            local last = p._rows[p:GetRowCount()]
            expect(last).notNil()
            H.expectNoOverlap({ last, p._count })
            expect(H.box(p._count).top).as("the count sits below the last row")
                .gte(H.box(last).top + H.box(last).height)
        end)

        it("floors rows and the field at sizeRow, which is the mockup's row height", function()
            -- The mockup draws a 28-unit row around an 18-unit disc and a field of about the same.
            -- spaceXs around the disc alone gives 26, and those two units were what still read as
            -- cramped after the panel padding had already been matched.
            --
            -- The field is asserted as at least a row tall rather than strictly taller: they floor at the
            -- same token now, and a field SHORTER than a row is the thing to prevent, because then it
            -- reads as the first entry rather than as a field.
            local p = roster()
            expect(H.box(p._rows[1]).height).eq(H.token("sizeRow"))
            expect(H.box(p._search).height).gte(H.box(p._rows[1]).height)
        end)
    end)

    describe("quadrant placement", function()
        -- A panel that always opens downward runs off the bottom of the screen when its anchor sits in
        -- a bottom corner, which is exactly where the chat window starts.
        local function anchoredAt(fx, fy)
            local root = H.SuuUI.UIRoot:GetRoot()
            local host = H.UIParent
            local a = H.env.CreateFrame("Frame", nil, root)
            a:SetSize(30, 30)
            a:SetPoint("BOTTOMLEFT", root, "BOTTOMLEFT",
                       root:GetWidth() * fx, root:GetHeight() * fy)
            local p = H.mount(H.C.FlyoutPanel({ anchorTo = a, align = "auto" }, host))
            p:SetRows({ { key = "k", label = "Row", onClick = function() end } })
            p:Open()
            return p, a
        end

        it("opens UP and RIGHT from the bottom-left", function()
            local p, a = anchoredAt(0.05, 0.05)
            expect(H.box(p).top + H.box(p).height)
                .as("the panel sits above the anchor").lte(H.box(a).top + 1)
            expect(H.box(p).left).as("and extends rightward from the anchor's left edge")
                .eq(H.box(a).left)
        end)

        it("opens UP and LEFT from the bottom-right", function()
            local p, a = anchoredAt(0.9, 0.05)
            expect(H.box(p).top + H.box(p).height).lte(H.box(a).top + 1)
            expect(H.box(p).left + H.box(p).width)
                .as("right edges together, extending leftward").eq(H.box(a).left + H.box(a).width)
        end)

        it("opens DOWN from the top-left, as before", function()
            local p, a = anchoredAt(0.05, 0.9)
            expect(H.box(p).top).as("below the anchor").gte(H.box(a).top + H.box(a).height - 1)
            expect(H.box(p).left).eq(H.box(a).left)
        end)

        it("opens DOWN and LEFT from the top-right", function()
            local p, a = anchoredAt(0.9, 0.9)
            expect(H.box(p).top).gte(H.box(a).top + H.box(a).height - 1)
            expect(H.box(p).left + H.box(p).width).eq(H.box(a).left + H.box(a).width)
        end)

        it("falls back to the stated align when there is no anchor to measure", function()
            -- A frame that has never been laid out reports no centre, and guessing a quadrant from nil
            -- would place the panel somewhere arbitrary.
            local p = H.mount(H.C.FlyoutPanel({ align = "auto" }, H.UIParent))
            p:SetRows({ { key = "k", label = "Row", onClick = function() end } })
            expect(function() p:Open() end).notThrows()
        end)
    end)

    describe("the meta column", function()
        local function withMeta()
            local p = H.mount(H.C.FlyoutPanel({ maxRows = 8 }, H.UIParent))
            p:SetRows({
                { key = "a", label = "Velementina", meta = "12h", onClick = function() end },
                { key = "b", label = "Tangolock",   meta = "15h", onClick = function() end },
            })
            p:Open()
            return p
        end

        it("draws meta in its own column, dim and right-aligned", function()
            local p = withMeta()
            expect(p._rows[1]._metaT:GetText()).eq("12h")
            expect(p._rows[1]._labelT:GetText()).as("the label carries the name alone").eq("Velementina")
        end)

        it("keeps the label clear of the meta column", function()
            -- A long name must be truncated by the layout rather than drawn underneath the age.
            local p = withMeta()
            H.expectNoOverlap({ p._rows[1]._label, p._rows[1]._meta })
        end)

        it("reserves NO column when no entry carries meta", function()
            -- An empty column would silently narrow every label. Asserted on the PANEL's width rather
            -- than the label's: the column grows to fit the meta, so the label keeps its own width and
            -- is not squeezed -- which is the behaviour worth pinning.
            local bare = H.mount(H.C.FlyoutPanel({ maxRows = 8 }, H.UIParent))
            bare:SetRows({ { key = "a", label = "Velementina", onClick = function() end } })
            bare:Open()
            local bareW = H.box(bare).width
            local q = withMeta()
            expect(H.box(q).width).as("meta widens the panel").gt(bareW)
            expect(H.box(q._rows[1]._label).width)
                .as("without squeezing the label").eq(H.box(bare._rows[1]._label).width)
        end)
    end)

    describe("the search filter", function()
        local function panelOf(n)
            local host = H.UIParent
            local p = H.mount(H.C.FlyoutPanel({ filter = true, maxRows = 3 }, host))
            local rows = {}
            for i = 1, n do rows[i] = { key = "k" .. i, label = "Name" .. i, onClick = function() end } end
            p:SetRows(rows)
            return p
        end

        it("does not draw the first row OVER the search field", function()
            -- Shipped exactly this: ApplyTheme re-states the grid's padding from tokens and runs AFTER
            -- the header is built, so the reservation set at construction was wiped and the rows were
            -- laid out at the plain top padding, drawing through the search box.
            local p = panelOf(5)
            p:Open()
            local box = H.box(p._search)
            local row = H.box(p._rows[1])
            expect(box).notNil()
            expect(row).notNil()
            -- `.top` grows DOWNWARD, so a row below the field has the LARGER top.
            expect(row.top).as("the first row starts below the search field").gte(box.top + box.height)
            H.expectNoOverlap({ p._search, p._rows[1] })
        end)

        it("spans the search field across the panel", function()
            local p = panelOf(5)
            p:Open()
            -- The panel pads by spaceSm; spaceXs was the old value and left this spec measuring 4.
            local pad = H.token("spaceSm")
            expect(H.box(p._search).width)
                .as("full width less the padding").eq(H.box(p._panel).width - pad * 2)
        end)

        it("caps what it DRAWS while keeping the full set searchable", function()
            -- This panel's overflow strategy is COLUMNS, not scrolling, so an uncapped roster of 300
            -- lays out 300 rows across a dozen columns spanning the screen.
            local p = panelOf(10)
            expect(p:GetRowCount()).as("drawn").eq(3)
            H.typeText(p._search, "Name7")
            expect(p:GetRowCount()).as("an entry past the cap is still reachable").eq(1)
            expect(p._entries[1].label).eq("Name7")
        end)

        it("matches on the label, case-insensitively", function()
            local p = panelOf(5)
            H.typeText(p._search, "NAME2")
            expect(p:GetRowCount()).eq(1)
            expect(p._entries[1].label).eq("Name2")
        end)

        it("treats the query as PLAIN TEXT, not a Lua pattern", function()
            -- A player name can contain `-` (a realm suffix) and a conversation label can contain `(`.
            -- Used as a pattern those either match nothing or raise from inside a keystroke handler.
            local p = H.mount(H.C.FlyoutPanel({ filter = true, maxRows = 8 }, H.UIParent))
            p:SetRows({ { key = "a", label = "Thal-Thunderstrike", onClick = function() end },
                        { key = "b", label = "Quest (3525)", onClick = function() end } })
            -- An UNFINISHED CAPTURE is the discriminating query: as a pattern `find("(3525")` raises
            -- "unfinished capture" from inside a keystroke handler, while plain-text find matches the
            -- label. A balanced "(3525)" does NOT discriminate -- it happens to match either way, which
            -- is why the first version of this spec let the mutation survive.
            expect(function() H.typeText(p._search, "(3525") end).notThrows()
            expect(p:GetRowCount()).as("a bracketed query matches literally").eq(1)
            -- A `%` alone is a malformed pattern for the same reason.
            expect(function() H.typeText(p._search, "%") end).notThrows()
        end)

        it("shows nothing when nothing matches, without raising", function()
            local p = panelOf(5)
            H.typeText(p._search, "zzzz")
            expect(p:GetRowCount()).eq(0)
        end)

        it("says how many were found when the cap is hiding some", function()
            local p = panelOf(10)
            expect(p._count:GetText():find("of 10", 1, true)).as("the total is stated").notNil()
        end)

        it("restores the full roster when the query is cleared", function()
            -- The filtered view must never become the stored list, or clearing the box would leave the
            -- roster permanently narrowed.
            local p = panelOf(10)
            H.typeText(p._search, "Name7")
            H.typeText(p._search, "")
            expect(p:GetRowCount()).eq(3)
            expect(#p._all).as("the full set survived filtering").eq(10)
        end)

        it("keeps the full roster across a THEME change", function()
            -- ApplyTheme re-renders, and re-seeding it from the drawn view would discard every entry
            -- past the cap for good.
            local p = panelOf(10)
            p:ApplyTheme()
            expect(#p._all).eq(10)
            expect(p:GetRowCount()).eq(3)
        end)
    end)
    local anchor, anchorBox, panel

    before_each(function()
        H.setup()
        -- MOUNTED, not merely created. An unpositioned frame has no rect, and a panel
        -- anchored to a rectless frame never resolves one either -- so every geometry
        -- assertion below would read nil for a reason that has nothing to do with the panel.
        -- In production this is the data bar's own field, which the bar lays out.
        anchor    = H.env.CreateFrame("Frame", nil, root())
        anchorBox = H.SuuUI.Layout:CreateContainer({ parent = root(), layout = "anchor" })
        anchorBox:Add(anchor, { anchor = {
            point = "TOPRIGHT", relativePoint = "TOPRIGHT",
            x = -120, y = -8, width = 90, height = H.token("sizeRow"),
        } })
        panel = H.C.FlyoutPanel({ anchorTo = anchor, align = "right" }, root())
    end)

    -----------------------------------------------------------------------------
    describe("opening", function()
        it("starts closed and paints nothing", function()
            expect(panel:IsOpen()).as("a roster is not shown until it is asked for").eq(false)
            expect(panel:GetRowCount()).eq(0)
        end)

        it("opens with rows, and RETURNS", function()
            -- The freeze regression. With the nested hugging-and-stretched container this
            -- call never comes back, so reaching the assertion at all is the assertion.
            panel:SetRows(entriesOf(3, true))
            panel:Open()
            expect(panel:IsOpen()).eq(true)
            expect(panel:GetRowCount()).eq(3)
        end)

        it("is shown before its rows are placed, so adopted frames resolve a rect", function()
            -- A hidden frame has no rect and a child anchored to one never resolves a
            -- position: it reports the size it was given, reports as shown, and draws
            -- nothing. The panel must therefore already be visible when the rows land.
            local list = entriesOf(2, true)
            panel:SetRows(list)
            panel:Open()
            for _, entry in ipairs(list) do
                expect(H.box(entry.frame))
                    .as("the adopted button resolved a real rect").notNil()
            end
        end)

        it("gives every row a real, non-zero box inside the panel", function()
            panel:SetRows(entriesOf(3, true))
            panel:Open()
            for i = 1, 3 do
                local row = panel._rows[i]
                expect(H.box(row).height).gt(0)
                H.expectInside(row, panel:GetFrame())
            end
        end)

        it("stacks the rows without overlapping each other", function()
            panel:SetRows(entriesOf(3, true))
            panel:Open()
            H.expectNoOverlap({ panel._rows[1], panel._rows[2] })
            H.expectNoOverlap({ panel._rows[2], panel._rows[3] })
        end)
    end)

    -----------------------------------------------------------------------------
    describe("adoption", function()
        it("reparents the frame into its row, since only parentage hides it", function()
            local list = entriesOf(1, true)
            panel:SetRows(list)
            panel:Open()
            -- Anchoring alone would leave the button on screen after the panel closed. The
            -- row is also the stack's own host frame, which is what lets the placement
            -- resolve at all.
            expect(list[1].frame:GetParent())
                .as("the adopted button is parented into its row").eq(panel._rows[1])
        end)

        it("releases a pinned strata, or the icon stays behind the backdrop", function()
            local list = entriesOf(1, true)
            local btn = list[1].frame
            -- Exactly what LibDBIcon does to every button it creates.
            btn:SetFrameStrata("MEDIUM")
            btn:SetFixedFrameStrata(true)
            btn:SetFrameLevel(8)
            btn:SetFixedFrameLevel(true)

            panel:SetRows(list)
            panel:Open()

            -- The pin has to come off FIRST: a pinned frame ignores the strata write, and the
            -- symptom is a roster of names with no icons in it.
            expect(btn:IsFixedFrameStrata())
                .as("the strata pin is released").eq(false)
            expect(btn:GetFrameStrata())
                .as("the adopted icon sits on the panel's own rung")
                .eq(panel:GetFrame():GetFrameStrata())
            expect(btn:GetFrameLevel())
                .as("above the panel's backdrop, not behind it")
                .gt(panel:GetFrame():GetFrameLevel())
        end)

        it("does not append the same frame again on a rebuild", function()
            local list = entriesOf(2, true)
            panel:SetRows(list)
            panel:Open()
            local before = #panel._rows[1]._box:GetChildren()

            panel:SetRows(list)
            panel:SetRows(list)
            expect(#panel._rows[1]._box:GetChildren())
                .as("Add is membership, not an upsert").eq(before)
        end)

        it("swaps the held frame when the roster changes", function()
            local first = entriesOf(1, true)
            panel:SetRows(first)
            panel:Open()
            local count = #panel._rows[1]._box:GetChildren()

            local second = entriesOf(1, true)
            panel:SetRows(second)
            expect(panel._rows[1]._held).as("the new frame is held").eq(second[1].frame)
            expect(#panel._rows[1]._box:GetChildren())
                .as("and the old one left rather than accumulating").eq(count)
        end)
    end)

    -----------------------------------------------------------------------------
    describe("the name column", function()
        it("renders each label without clipping it", function()
            panel:SetRows(entriesOf(3, true))
            panel:Open()
            for i = 1, 3 do
                H.expectTextNotClipped(panel._rows[i]._label)
            end
        end)

        it("sizes the panel from the WIDEST label, not the first", function()
            local list = entriesOf(2, true)
            list[2].label = "A Very Much Longer Addon Name"
            panel:SetRows(list)
            panel:Open()
            for i = 1, 2 do
                H.expectTextNotClipped(panel._rows[i]._label)
                H.expectInside(panel._rows[i]._label, panel:GetFrame())
            end
        end)

        it("keeps the label clear of the icon column", function()
            local list = entriesOf(1, true)
            panel:SetRows(list)
            panel:Open()
            H.expectNoOverlap({ list[1].frame, panel._rows[1]._label })
        end)
    end)

    -----------------------------------------------------------------------------
    describe("what a row promises", function()
        it("takes the mouse and paints a rail only when it can be clicked", function()
            panel:SetRows(entriesOf(1, true))
            panel:Open()
            local row = panel._rows[1]
            expect(row:IsMouseEnabled()).as("a clickable row takes the mouse").eq(true)
            row:GetScript("OnEnter")(row)
            expect(row._rail:IsShown()).as("and shows the rail on hover").eq(true)
        end)

        it("stays inert and railless for a row with nothing behind it", function()
            -- The message states used for "no buttons found" and the MBB conflict. A rail
            -- there would promise an interaction that is not there.
            panel:SetRows({ { key = "_message", label = "No addon buttons found" } })
            panel:Open()
            local row = panel._rows[1]
            expect(row:IsMouseEnabled()).eq(false)
            row:GetScript("OnEnter")(row)
            expect(row._rail:IsShown()).as("no rail without a click target").eq(false)
        end)

        it("hands the mouse button through to the row's own handler", function()
            local got
            local list = entriesOf(1, false)
            list[1].onClick = function(_, btn) got = btn end
            panel:SetRows(list)
            panel:Open()
            panel._rows[1]:GetScript("OnMouseUp")(panel._rows[1], "RightButton")
            expect(got).as("a right click reaches the row as a right click").eq("RightButton")
        end)
    end)

    -----------------------------------------------------------------------------
    describe("closing when the cursor leaves", function()
        it("stays open while the cursor is over the panel", function()
            panel:SetRows(entriesOf(2, true))
            panel:Open()
            local f = panel:GetFrame()
            H.cursor(f:GetLeft() + 2, f:GetBottom() + 2, f)
            H.tick(0.5)
            expect(panel:IsOpen()).as("the cursor is inside, so it stays").eq(true)
        end)

        it("closes once the cursor has been outside for the grace period", function()
            panel:SetRows(entriesOf(2, true))
            panel:Open()
            local f = panel:GetFrame()
            H.cursor(f:GetLeft() - 200, f:GetBottom() - 200, f)
            H.tick(0.5)
            expect(panel:IsOpen()).as("cursor left, panel closed").eq(false)
        end)

        it("does not close on the first frame outside", function()
            -- The cursor crosses a seam between the field and the panel where neither rect
            -- contains it. Closing on that single sample would shut the roster during the
            -- one movement that matters: the reach from the field down onto a row.
            panel:SetRows(entriesOf(2, true))
            panel:Open()
            local f = panel:GetFrame()
            H.cursor(f:GetLeft() - 200, f:GetBottom() - 200, f)
            H.tick(0.016)
            expect(panel:IsOpen()).as("one frame outside is not a departure").eq(true)
        end)
    end)

    -----------------------------------------------------------------------------
    describe("staying on screen", function()
        it("is a single column when the roster fits", function()
            panel:SetMaxHeight(2000)
            panel:SetRows(entriesOf(3, true))
            panel:Open()
            expect(panel:GetColumnCount()).as("a short roster is a plain list").eq(1)
        end)

        it("continues in another column instead of running off the bottom", function()
            panel:SetRows(entriesOf(8, true))
            panel:Open()
            local full = H.box(panel:GetFrame()).height

            panel:SetMaxHeight(full / 2)
            expect(panel:GetColumnCount()).as("split rather than overflowing").gte(2)
            expect(H.box(panel:GetFrame()).height)
                .as("and no taller than the cap it was given").lte(full / 2 + 1)
        end)

        it("gets wider rather than taller when it splits", function()
            panel:SetRows(entriesOf(8, true))
            panel:Open()
            local before = H.box(panel:GetFrame())

            panel:SetMaxHeight(before.height / 2)
            local after = H.box(panel:GetFrame())
            expect(after.width).as("wider").gt(before.width)
            expect(after.height).as("and shorter").lt(before.height)
        end)

        it("keeps every row inside the panel, so none has to be scrolled to", function()
            -- The reason this is columns and not a scroll viewport: every row stays within the
            -- panel's own box, so there is no clip for an adopted icon's re-stated strata to
            -- escape, and nothing is unreachable.
            panel:SetRows(entriesOf(9, true))
            panel:Open()
            panel:SetMaxHeight(H.box(panel:GetFrame()).height / 3)
            for i = 1, 9 do
                H.expectInside(panel._rows[i], panel:GetFrame())
            end
        end)

        it("still places a row when the cap is smaller than one row", function()
            panel:SetRows(entriesOf(3, true))
            panel:Open()
            panel:SetMaxHeight(1)
            expect(panel:GetColumnCount())
                .as("one row per column, never zero-row columns").eq(3)
        end)

        it("treats no cap as unlimited", function()
            panel:SetMaxHeight(0)
            panel:SetRows(entriesOf(12, true))
            panel:Open()
            expect(panel:GetColumnCount()).eq(1)
        end)
    end)

    -----------------------------------------------------------------------------
    describe("hovering", function()
        it("paints the row's BACKGROUND, not only its rail", function()
            -- The rail is a plain texture and works with no backdrop behind it, so asserting
            -- only the rail is what let the highlight ship invisible: SetBg tints a backdrop,
            -- and a row that never had Backdrop.Apply called on it has none to tint.
            local list = entriesOf(1, true)
            panel:SetRows(list)
            panel:Open()
            local row = panel._rows[1]

            H.cursor(row:GetLeft() + 2, row:GetBottom() + 2, row)
            H.hover(row)
            H.expectTokenColor({ row:GetBackdropColor() }, "colorBgHover")
        end)

        it("paints the row when the cursor enters the adopted icon directly", function()
            -- ONLY the hook on the adopted frame can satisfy this, which is what makes it the
            -- discriminating test: the row's own OnEnter never fires when the cursor lands on
            -- the icon, because the client gives mouse focus to the child. Approaching the
            -- panel from outside and arriving on an icon is the ordinary way this happens.
            local list = entriesOf(1, true)
            panel:SetRows(list)
            panel:Open()
            local row, btn = panel._rows[1], list[1].frame

            expect(row._rail:IsShown()).as("nothing painted to begin with").eq(false)
            H.cursor(btn:GetLeft() + 1, btn:GetBottom() + 1, btn)
            H.hover(btn)
            expect(row._rail:IsShown())
                .as("the icon's hook painted the whole row").eq(true)
        end)

        it("does not unpaint while the cursor is still within the row", function()
            -- Crossing from the label onto the icon fires a leave on the row, in an order the
            -- client does not promise relative to the icon's enter. Unpainting unconditionally
            -- would drop the highlight mid-crossing, so the leave asks where the cursor is.
            local list = entriesOf(1, true)
            panel:SetRows(list)
            panel:Open()
            local row, btn = panel._rows[1], list[1].frame

            H.cursor(row:GetLeft() + 2, row:GetBottom() + 2, row)
            H.hover(row)
            expect(row._rail:IsShown()).as("hovering the row paints it").eq(true)

            H.cursor(btn:GetLeft() + 1, btn:GetBottom() + 1, btn)
            H.unhover(row)
            expect(row._rail:IsShown())
                .as("the cursor is on the icon, which is still inside the row").eq(true)
        end)

        it("unpaints once the cursor is outside the row entirely", function()
            local list = entriesOf(1, true)
            panel:SetRows(list)
            panel:Open()
            local row = panel._rows[1]

            H.cursor(row:GetLeft() + 2, row:GetBottom() + 2, row)
            H.hover(row)
            expect(row._rail:IsShown()).eq(true)

            H.cursor(row:GetLeft() - 300, row:GetBottom() - 300, row)
            H.unhover(row)
            expect(row._rail:IsShown()).as("cursor left, highlight gone").eq(false)
        end)
    end)

    -----------------------------------------------------------------------------
    describe("teardown", function()
        it("hides, and releases the adopted frames without restoring them", function()
            local list = entriesOf(2, true)
            panel:SetRows(list)
            panel:Open()
            panel:Destroy()
            expect(panel:IsShown()).eq(false)
            -- Released from the layout, deliberately NOT put back: the panel never knew
            -- where these came from, so the owner restores them after this.
            expect(panel._rows[1]._held).isNil()
        end)

        it("leaves the shared floating host alive for every other panel", function()
            panel:SetRows(entriesOf(1, true))
            panel:Open()
            local host = H.SuuUI.Layout:GetFloatingHost()
            panel:Destroy()
            expect(H.SuuUI.Layout:GetFloatingHost())
                .as("the host is shared: drop your panel, never the host").eq(host)
        end)
    end)

    -----------------------------------------------------------------------------
    describe("the panel's unit space", function()
        -- The host PLACES the panel; its PARENT decides what a unit is. The fallback used to be
        -- UIParent, which does not carry the pixel grid's scale the UI root does -- so a panel built
        -- without an explicit parent rendered its own text and rows at the ratio between the two
        -- scales, 1.4062 at 1080p. Dropdown shipped exactly that and it reached the player as option
        -- rows visibly larger than the control they hung off.
        --
        -- Every caller here passes a parent, so the fallback is the untravelled branch -- which is
        -- precisely why it needs a spec: nothing else would ever notice it was wrong.
        it("falls back to the floating host rather than UIParent", function()
            H.setup({ physicalHeight = 1080 })
            local root = H.SuuUI.UIRoot:GetRoot()
            expect(root:GetEffectiveScale())
                .as("the 1080p client must actually scale the root, or this proves nothing").neq(1)

            local p = H.C.FlyoutPanel({})
            expect(p:GetFrame():GetEffectiveScale())
                .as("the panel measures units as the root does").near(root:GetEffectiveScale(), 0.0001)
            p:Destroy()
        end)
    end)
end)
