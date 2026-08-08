local H = require("harness")

-- Hidden children and the layout engine.
--
-- Flow and grid allocate main-axis space and gaps, so a hidden child there used to keep
-- its slot AND its gap — a hole in the middle of a row that nothing occupied. Stack and
-- anchor deliberately keep laying hidden children out: their children each own the whole
-- box, so a hidden one costs nothing, and skipping it would strand any component that
-- hides a child and resizes it before showing it again. A progress fill at 0% is exactly
-- that, so the StatusBar round-trip below is the regression guard for the distinction.
describe("layout: hidden children", function()
    local host

    before_each(function()
        H.setup()
        host = H.parent(400, 300)
    end)

    local function row(container, w, h)
        local f = H.env.CreateFrame("Frame", nil, container:GetFrame())
        f:SetSize(w, h)
        container:Add(f, { width = w, height = h })
        return f
    end

    describe("flow closes the gap", function()
        it("a hidden child consumes no main-axis space", function()
            local col = H.SuuUI.Layout:CreateContainer({
                parent = host, layout = "flow", dir = "vertical", gap = 10, w = 200,
            })
            local a, b, c = row(col, 100, 20), row(col, 100, 20), row(col, 100, 20)

            local topC = H.box(c).top
            b:Hide()
            col:Layout()
            -- c moves up by b's height plus one gap
            expect(H.box(c).top).as("c rises by 20 + 10").near(topC - 30, 0.5)
            -- and a is untouched
            expect(H.box(a).top).near(H.box(col).top, 0.5)
        end)

        it("re-showing the child restores the original layout", function()
            local col = H.SuuUI.Layout:CreateContainer({
                parent = host, layout = "flow", dir = "vertical", gap = 10, w = 200,
            })
            row(col, 100, 20)
            local b = row(col, 100, 20)
            local c = row(col, 100, 20)

            local before = H.box(c).top
            b:Hide();  col:Layout()
            b:Show();  col:Layout()
            expect(H.box(c).top).near(before, 0.5)
        end)

        it("hiding the last child leaves no trailing gap in content height", function()
            local col = H.SuuUI.Layout:CreateContainer({
                parent = host, layout = "flow", dir = "vertical", gap = 10, w = 200,
            })
            row(col, 100, 20)
            local b = row(col, 100, 20)

            local _, hBoth = col:GetContentSize()
            b:Hide()
            col:Layout()
            local _, hOne = col:GetContentSize()
            expect(hBoth - hOne).as("one child plus one gap disappears").near(30, 0.5)
        end)

        it("all children hidden collapses content to padding", function()
            local col = H.SuuUI.Layout:CreateContainer({
                parent = host, layout = "flow", dir = "vertical", gap = 10, w = 200,
                padding = { top = 5, right = 5, bottom = 5, left = 5 },
            })
            local a, b = row(col, 100, 20), row(col, 100, 20)
            a:Hide(); b:Hide()
            col:Layout()
            local _, h = col:GetContentSize()
            expect(h).as("top + bottom padding only").near(10, 0.5)
        end)

        it("works on the horizontal axis too", function()
            local strip = H.SuuUI.Layout:CreateContainer({
                parent = host, layout = "flow", dir = "horizontal", gap = 8, w = 300, h = 40,
            })
            row(strip, 50, 20)
            local b = row(strip, 50, 20)
            local c = row(strip, 50, 20)

            local leftC = H.box(c).left
            b:Hide()
            strip:Layout()
            expect(H.box(c).left).as("c shifts left by 50 + 8").near(leftC - 58, 0.5)
        end)
    end)

    describe("grid skips the cell", function()
        it("a hidden child does not hold an empty cell", function()
            local grid = H.SuuUI.Layout:CreateContainer({
                parent = host, layout = "grid", cols = 2, gap = 6, w = 200,
            })
            local a = row(grid, 90, 20)
            local b = row(grid, 90, 20)
            local c = row(grid, 90, 20)

            -- c starts on row 2; hiding b promotes it into b's slot on row 1
            expect(H.box(c).top).as("c begins on the second row").gt(H.box(a).top)
            b:Hide()
            grid:Layout()
            expect(H.box(c).top).as("c moves onto row 1").near(H.box(a).top, 0.5)
            expect(H.box(c).left).as("c takes column 2").gt(H.box(a).left)
        end)
    end)

    describe("stack keeps laying hidden children out", function()
        it("a hidden stack child is still sized and placed", function()
            local box = H.SuuUI.Layout:CreateContainer({ host = host, layout = "stack" })
            local f = H.env.CreateFrame("Frame", nil, host)
            box:Add(f, { inset = 4 })
            f:Hide()
            box:Layout()
            -- Still stretched to the inset box, ready to be shown at the right size
            H.expectSize(f, H.box(host).width - 8, H.box(host).height - 8)
        end)
    end)

    -- The reason stack must not skip: StatusBar hides its fill at 0% and needs the layout
    -- engine to keep sizing it, or the bar can never come back.
    describe("StatusBar survives a 0% round trip", function()
        it("returns to the right width after passing through zero", function()
            local bar = H.C.StatusBar({ w = 200, h = 20, max = 100, value = 50, border = false }, host)
            H.mount(bar, { width = 200, height = 20 })

            bar:SetValue(50)
            local half = bar._fillFrame:GetWidth()
            expect(half).as("half of a 200px borderless track").near(100, 1)

            bar:SetValue(0)
            expect(bar._fillFrame:IsShown()).as("hidden at 0%").eq(false)

            bar:SetValue(50)
            expect(bar._fillFrame:IsShown()).as("shown again").eq(true)
            expect(bar._fillFrame:GetWidth()).as("and back to half width").near(half, 1)
        end)

        it("a bar at 0% still tracks a resize of its track", function()
            local bar = H.C.StatusBar({ w = 200, h = 20, max = 100, value = 0, border = false }, host)
            H.mount(bar, { width = 200, height = 20 })
            bar:SetSize(300, 20)
            bar:SetValue(100)
            expect(bar._fillFrame:GetWidth()).as("full width of the NEW track").near(300, 1)
        end)
    end)
end)
