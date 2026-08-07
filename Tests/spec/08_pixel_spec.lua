local H = require("harness")

-- One unit spans physicalHeight/768 pixels once the frame's own scale is folded in.
-- A value is crisp when it lands on a whole number of those pixels, which is the only
-- property that actually matters here — asserting the unit value alone would pass for a
-- number that still straddles a pixel boundary.
local function pixelsPerUnit()
    local P = H.SuuUI.Pixel
    return P.physicalHeight * P.scale / 768
end

local function expectWholePixels(v, note)
    local px = v * pixelsPerUnit()
    expect(math.abs(px - math.floor(px + 0.5))).as(note or ("lands off-pixel: " .. tostring(v)))
        .lt(1e-6)
end

describe("Core.Pixel", function()
    describe("grid derivation", function()
        it("is a 1:1 grid when units already equal pixels", function()
            H.setup()
            local P = H.SuuUI.Pixel
            expect(P.physicalHeight).eq(768)
            expect(P.multiplier).eq(1)
            expect(P.scale).near(1, 1e-9)
            expect(P.grid).eq(1)
            expect(P.mult).as("one pixel is one unit").near(1, 1e-9)
        end)

        it("scales the root to 768/physicalHeight at 1080p", function()
            H.setup({ physicalWidth = 1920, physicalHeight = 1080 })
            local P = H.SuuUI.Pixel
            expect(P.multiplier).eq(1)
            expect(P.scale).near(768 / 1080, 1e-9)
            expect(P.grid).as("whole units are pixel-aligned").eq(1)
            expectWholePixels(1)
            expectWholePixels(H.token("borderWidth"))
        end)

        it("gives the root frame exactly the computed effective scale", function()
            H.setup({ physicalWidth = 1920, physicalHeight = 1080 })
            local root = H.env.SuuUI_UIRoot
            expect(root).notNil()
            expect(root:GetEffectiveScale()).near(H.SuuUI.Pixel.scale, 1e-6)
        end)

        it("holds its scale against the player's UI Scale slider", function()
            H.setup({ physicalWidth = 1920, physicalHeight = 1080, uiScale = 0.9 })
            local P = H.SuuUI.Pixel
            expect(H.env.SuuUI_UIRoot:GetEffectiveScale()).near(P.scale, 1e-6)
            expectWholePixels(1)
        end)

        it("steps up to an integer multiple on a high-DPI display", function()
            H.setup({ physicalWidth = 3840, physicalHeight = 2160 })
            local P = H.SuuUI.Pixel
            expect(P.multiplier).eq(2)
            expect(P.scale).near(2 * 768 / 2160, 1e-9)
            expect(P.grid).as("still whole units").eq(1)
            expect(P.mult).as("one pixel is half a unit").near(0.5, 1e-9)
            expectWholePixels(1, "a 1-unit border is exactly 2 pixels")
        end)

        it("picks the multiplier from the physical height alone", function()
            H.setup()
            local P = H.SuuUI.Pixel
            expect(P:AutoMultiplier(768)).eq(1)
            expect(P:AutoMultiplier(1080)).eq(1)
            expect(P:AutoMultiplier(1440)).eq(1)
            expect(P:AutoMultiplier(2160)).eq(2)
            expect(P:AutoMultiplier(4320)).eq(4)
        end)

        it("never returns a multiplier below 1", function()
            H.setup()
            expect(H.SuuUI.Pixel:AutoMultiplier(600)).eq(1)
        end)
    end)

    describe("snapping", function()
        before_each(function() H.setup() end)

        it("rounds to whole units on a 1:1 grid", function()
            local P = H.SuuUI.Pixel
            expect(P.Snap(13.7)).eq(14)
            expect(P.Snap(13.2)).eq(13)
            expect(P.Snap(13.5)).eq(14)
            expect(P.Snap(-2.4)).eq(-2)
        end)

        it("floors and ceils to the grid", function()
            local P = H.SuuUI.Pixel
            expect(P.Floor(13.9)).eq(13)
            expect(P.Ceil(13.1)).eq(14)
            expect(P.Floor(13)).eq(13)
            expect(P.Ceil(13)).eq(13)
        end)

        it("passes zero and nil through", function()
            local P = H.SuuUI.Pixel
            expect(P.Snap(0)).eq(0)
            expect(P.Snap(nil)).eq(0)
            expect(P.Floor(nil)).eq(0)
            expect(P.Ceil(nil)).eq(0)
        end)

        it("is idempotent, so a re-layout cannot drift", function()
            local P = H.SuuUI.Pixel
            for _, v in ipairs({ 0.4, 13.7, 27.5, 100.0001 }) do
                expect(P.Snap(P.Snap(v))).as("snap(snap(v)) == snap(v)").eq(P.Snap(v))
            end
        end)

        it("keeps a line thickness from rounding out of existence", function()
            local P = H.SuuUI.Pixel
            expect(P.Line(1)).eq(1)
            expect(P.Line(0.3)).as("would snap to 0").eq(P.grid)
            expect(P.Line(0)).eq(P.grid)
            expect(P.Line(nil)).eq(P.grid)
            expect(P.Line(2.6)).eq(3)
        end)
    end)

    describe("with scaling disabled", function()
        before_each(function()
            H.setup({ physicalWidth = 1920, physicalHeight = 1080 })
            H.SuuUI.Pixel:SetEnabled(false)
        end)

        it("restores the root scale", function()
            expect(H.env.SuuUI_UIRoot:GetScale()).near(1, 1e-9)
        end)

        it("snaps to real pixels instead of whole units", function()
            local P = H.SuuUI.Pixel
            expect(P.grid).as("a pixel is now a fraction of a unit").near(768 / 1080, 1e-9)
            expect(P.grid).lt(1)
            expectWholePixels(P.Snap(13.7))
            expectWholePixels(P.Snap(4))
        end)

        it("still gives a border exactly one pixel", function()
            local P = H.SuuUI.Pixel
            expect(P.Line(1)).as("1 unit would be 1.4 pixels").near(768 / 1080, 1e-9)
            expectWholePixels(P.Line(1))
        end)

        it("comes back on", function()
            local P = H.SuuUI.Pixel
            P:SetEnabled(true)
            expect(P.grid).eq(1)
            expect(H.env.SuuUI_UIRoot:GetEffectiveScale()).near(P.scale, 1e-6)
        end)
    end)

    describe("multiplier override", function()
        before_each(function() H.setup({ physicalWidth = 1920, physicalHeight = 1080 }) end)

        it("forces a chosen multiple and keeps the grid crisp", function()
            local P = H.SuuUI.Pixel
            P:SetMultiplier(2)
            expect(P.multiplier).eq(2)
            expect(P.scale).near(2 * 768 / 1080, 1e-9)
            expect(P.grid).eq(1)
            expectWholePixels(1)
        end)

        it("rounds a fractional multiplier, which would defeat the grid", function()
            local P = H.SuuUI.Pixel
            P:SetMultiplier(1.6)
            expect(P.multiplier).eq(2)
            expectWholePixels(1)
        end)

        it("rejects a multiplier below 1", function()
            local P = H.SuuUI.Pixel
            expect(function() P:SetMultiplier(0) end).throws()
        end)

        it("returns to automatic selection on nil", function()
            local P = H.SuuUI.Pixel
            P:SetMultiplier(3)
            P:SetMultiplier(nil)
            expect(P.multiplier).eq(P:AutoMultiplier(1080))
        end)
    end)

    describe("grid changes", function()
        it("emits SUUUI_PIXEL_GRID_CHANGED when the grid moves", function()
            H.setup({ physicalWidth = 1920, physicalHeight = 1080 })
            local spy = H.eventSpy("SUUUI_PIXEL_GRID_CHANGED")
            H.SuuUI.Pixel:SetMultiplier(2)
            expect(spy.count).eq(1)
        end)

        it("stays quiet when a refresh changes nothing", function()
            H.setup()
            local spy = H.eventSpy("SUUUI_PIXEL_GRID_CHANGED")
            H.SuuUI.Pixel:Refresh()
            H.SuuUI.Pixel:Refresh()
            expect(spy.count).as("no geometry moved").eq(0)
        end)

        it("restyles the UI through a theme change", function()
            H.setup({ physicalWidth = 1920, physicalHeight = 1080 })
            local spy = H.eventSpy("SUUUI_THEME_CHANGED")
            H.SuuUI.Pixel:SetMultiplier(2)
            expect(spy.count).gte(1)
        end)

        it("recomputes when the display size changes", function()
            H.setup({ physicalWidth = 1920, physicalHeight = 1080 })
            local P = H.SuuUI.Pixel
            expect(P.multiplier).eq(1)
            H.state.physicalHeight = 2160
            H.state.physicalWidth  = 3840
            H.fireEvent("DISPLAY_SIZE_CHANGED")
            expect(P.physicalHeight).eq(2160)
            expect(P.multiplier).eq(2)
        end)
    end)
end)

-- The module above is only useful if the layout engine actually routes through it. These
-- assert the geometry the strategies produce, which is the thing that reaches the screen.
describe("pixel snapping in the layout engine", function()
    local function expectIntegral(v, note)
        expect(v).notNil()
        expect(math.abs(v - math.floor(v + 0.5))).as(note or ("off-grid: " .. tostring(v)))
            .lt(1e-6)
    end

    describe("flow layout", function()
        before_each(function() H.setup() end)

        it("snaps a centred child when the leftover is odd", function()
            local p = H.parent(101, 60)
            local col = H.Layout:CreateContainer({ parent = p, layout = "flow",
                dir = "vertical", w = 101, align = "center" })
            local child = H.env.CreateFrame("Frame", nil, p)
            child:SetSize(50, 20)
            col:Add(child, { width = 50, height = 20 })

            -- (101 - 50) / 2 = 25.5, which would straddle a pixel.
            local dx = H.offset(child, col)
            expectIntegral(dx, "centred x must be whole")
        end)

        it("snaps a fractional container width out of its children", function()
            local p = H.parent(200, 60)
            local col = H.Layout:CreateContainer({ parent = p, layout = "flow",
                dir = "vertical", w = 100.4 })
            local child = H.env.CreateFrame("Frame", nil, p)
            col:Add(child, { width = "fill", height = 20 })
            expectIntegral(child:GetWidth(), "fill width must be whole")
            expect(child:GetWidth()).eq(100)
        end)

        it("distributes fill space without losing pixels", function()
            local p = H.parent(200, 100)
            local col = H.Layout:CreateContainer({ parent = p, layout = "flow",
                dir = "vertical", w = 200, h = 100, gap = 0 })
            local kids = {}
            for i = 1, 3 do
                kids[i] = H.env.CreateFrame("Frame", nil, p)
                col:Add(kids[i], { width = "fill", height = "fill" })
            end

            local total = 0
            for _, k in ipairs(kids) do
                expectIntegral(k:GetHeight(), "each fill share is whole")
                total = total + k:GetHeight()
            end
            -- 100 / 3 = 33.33: flooring each share would total 99 and leave a gap.
            expect(total).as("shares fill the container exactly").eq(100)

            local _, lastDy = H.offset(kids[3], col)
            expect(lastDy + kids[3]:GetHeight())
                .as("last child reaches the bottom edge").eq(100)
        end)

        it("keeps fill shares within one pixel of each other", function()
            local p = H.parent(200, 100)
            local col = H.Layout:CreateContainer({ parent = p, layout = "flow",
                dir = "vertical", w = 200, h = 100, gap = 0 })
            local kids = {}
            for i = 1, 3 do
                kids[i] = H.env.CreateFrame("Frame", nil, p)
                col:Add(kids[i], { width = "fill", height = "fill" })
            end
            local lo, hi = math.huge, 0
            for _, k in ipairs(kids) do
                lo = math.min(lo, k:GetHeight())
                hi = math.max(hi, k:GetHeight())
            end
            expect(hi - lo).as("no child is visibly larger").lte(1)
        end)

        it("distributes horizontal fill space the same way", function()
            local p = H.parent(200, 40)
            local row = H.Layout:CreateContainer({ parent = p, layout = "flow",
                dir = "horizontal", w = 100, h = 40, gap = 0 })
            local kids = {}
            for i = 1, 3 do
                kids[i] = H.env.CreateFrame("Frame", nil, p)
                row:Add(kids[i], { width = "fill", height = 20 })
            end
            local total = 0
            for _, k in ipairs(kids) do
                expectIntegral(k:GetWidth())
                total = total + k:GetWidth()
            end
            expect(total).eq(100)
            local lastDx = H.offset(kids[3], row)
            expect(lastDx + kids[3]:GetWidth()).as("row reaches the right edge").eq(100)
        end)

        it("never rounds a text child below its own height", function()
            local p = H.parent(200, 60)
            local col = H.Layout:CreateContainer({ parent = p, layout = "flow",
                dir = "vertical", w = 200 })
            local label = H.C.Text({ text = "Descenders gjpqy", size = "md" }, p)
            col:Add(label, { width = "fill" })
            expectIntegral(label:GetHeight())
            H.expectTextNotClipped(label:GetFrame())
        end)
    end)

    describe("stack layout", function()
        before_each(function() H.setup() end)

        it("snaps a centred child when the leftover is odd", function()
            local p = H.parent(101, 41)
            local box = H.Layout:CreateContainer({ host = p, layout = "stack" })
            local child = H.env.CreateFrame("Frame", nil, p)
            child:SetSize(50, 20)
            box:Add(child, { align = "center", valign = "center",
                             width = 50, height = 20 })
            local dx, dy = H.offset(child, p)
            expectIntegral(dx, "centred x")
            expectIntegral(dy, "centred y")
        end)

        it("floors a stretched child into a fractional box", function()
            local p = H.parent(100, 100)
            p:SetSize(100.6, 40.4)
            local box = H.Layout:CreateContainer({ host = p, layout = "stack" })
            local child = H.env.CreateFrame("Frame", nil, p)
            box:Add(child)
            expect(child:GetWidth()).as("must not overflow the parent").eq(100)
            expect(child:GetHeight()).eq(40)
        end)
    end)

    describe("grid layout", function()
        before_each(function() H.setup() end)

        it("spreads the column remainder so the row reaches the edge", function()
            local p = H.parent(200, 100)
            local grid = H.Layout:CreateContainer({ parent = p, layout = "grid",
                cols = 3, gap = 0, w = 100 })
            local kids = {}
            for i = 1, 3 do
                kids[i] = H.env.CreateFrame("Frame", nil, p)
                kids[i]:SetHeight(20)
                grid:Add(kids[i])
            end

            local total = 0
            for _, k in ipairs(kids) do
                expectIntegral(k:GetWidth())
                total = total + k:GetWidth()
            end
            expect(total).as("100 / 3 columns still fills 100").eq(100)

            local lastDx = H.offset(kids[3], grid)
            expect(lastDx + kids[3]:GetWidth()).eq(100)
        end)

        it("gives a column the same width in every row", function()
            local p = H.parent(200, 200)
            local grid = H.Layout:CreateContainer({ parent = p, layout = "grid",
                cols = 3, gap = 0, w = 100 })
            local kids = {}
            for i = 1, 6 do
                kids[i] = H.env.CreateFrame("Frame", nil, p)
                kids[i]:SetHeight(20)
                grid:Add(kids[i])
            end
            for c = 1, 3 do
                expect(kids[c + 3]:GetWidth())
                    .as("column " .. c .. " matches row above").eq(kids[c]:GetWidth())
            end
        end)
    end)

    describe("anchor layout", function()
        before_each(function() H.setup() end)

        it("snaps a caller-computed offset", function()
            local p = H.parent(200, 100)
            local box = H.Layout:CreateContainer({ host = p, layout = "anchor" })
            local child = H.env.CreateFrame("Frame", nil, p)
            box:Add(child, { anchor = { point = "TOPLEFT", relativePoint = "TOPLEFT",
                                        x = 13.7, y = -4.2, width = 20.6, height = 10.5 } })
            local dx, dy = H.offset(child, p)
            expectIntegral(dx)
            expectIntegral(dy)
            expect(child:GetWidth()).eq(21)
            expect(child:GetHeight()).eq(11)
        end)

        it("keeps a slider thumb on the grid at every value", function()
            local p = H.parent(300, 60)
            local col = H.Layout:CreateContainer({ parent = p, layout = "flow",
                dir = "vertical", w = 300 })
            local sl = H.C.Slider({ min = 0, max = 100, value = 0, step = 1 }, p)
            col:Add(sl, { width = "fill" })
            for _, v in ipairs({ 0, 7, 33, 50, 66, 99, 100 }) do
                sl:SetValue(v)
                local b = H.box(sl._thumb)
                expect(b).notNil()
                expectIntegral(b.left, "thumb left at value " .. v)
            end
        end)
    end)

    describe("borders", function()
        before_each(function() H.setup() end)

        it("keeps a backdrop edge on the grid", function()
            local p = H.parent(100, 40)
            H.SuuUI.Backdrop.Apply(p, { bg = "colorBg", border = "colorBorder" })
            local bd = p:GetBackdrop()
            expect(bd.edgeSize).eq(H.SuuUI.Pixel.Line(H.token("borderWidth")))
            expectIntegral(bd.edgeSize)
        end)

        it("never lets a hairline round away", function()
            local p = H.parent(100, 40)
            H.SuuUI.Backdrop.Apply(p, { bg = "colorBg", border = "colorBorder",
                                        borderWidth = 0.2 })
            expect(p:GetBackdrop().edgeSize).gte(H.SuuUI.Pixel.grid)
        end)
    end)

    describe("on a fractional grid", function()
        -- Scaling off at 1080p: a pixel is 0.711 units, so nothing lands on an integer
        -- and snapping has to target pixels instead. This is the configuration that
        -- proves the grid indirection earns its keep.
        local function pixelsOf(v)
            local P = H.SuuUI.Pixel
            return v * P.physicalHeight * P.scale / 768
        end
        local function expectWholePixels(v, note)
            local px = pixelsOf(v)
            expect(math.abs(px - math.floor(px + 0.5))).as(note or "off-pixel").lt(1e-6)
        end

        before_each(function()
            H.setup({ physicalWidth = 1920, physicalHeight = 1080 })
            H.SuuUI.Pixel:SetEnabled(false)
        end)

        it("places a centred child on a pixel boundary, not an integer unit", function()
            local p = H.parent(101, 41)
            local box = H.Layout:CreateContainer({ host = p, layout = "stack" })
            local child = H.env.CreateFrame("Frame", nil, p)
            box:Add(child, { align = "center", valign = "center",
                             width = 50, height = 20 })
            box:Layout()
            local dx, dy = H.offset(child, p)
            expectWholePixels(dx, "centred x on a pixel")
            expectWholePixels(dy, "centred y on a pixel")
        end)

        it("distributes fill space on pixel boundaries", function()
            local p = H.parent(200, 100)
            local col = H.Layout:CreateContainer({ parent = p, layout = "flow",
                dir = "vertical", w = 200, h = 100, gap = 0 })
            local kids = {}
            for i = 1, 3 do
                kids[i] = H.env.CreateFrame("Frame", nil, p)
                col:Add(kids[i], { width = "fill", height = "fill" })
            end
            col:Layout()
            for _, k in ipairs(kids) do expectWholePixels(k:GetHeight()) end
            local _, dy = H.offset(kids[3], col)
            expectWholePixels(dy + kids[3]:GetHeight(), "run still ends on a pixel")
        end)

        it("gives a border exactly one pixel rather than 1.4", function()
            local p = H.parent(100, 40)
            H.SuuUI.Backdrop.Apply(p, { bg = "colorBg", border = "colorBorder" })
            local edge = p:GetBackdrop().edgeSize
            expect(edge).lt(1)
            expectWholePixels(edge, "one whole pixel")
        end)
    end)
end)

-- Scaling the root gives everything under it an effective scale that differs from
-- UIParent's. GetCursorPosition reports raw screen coordinates, so any hit test that
-- divides by the wrong scale is off by the ratio between the two — a slider would track
-- roughly 40% too far at 1080p. Nothing under a scaled root is exercised by the specs
-- that build their hosts on UIParent, so these mount on the real root.
describe("cursor math under a scaled root", function()
    local host

    before_each(function()
        H.setup({ physicalWidth = 1920, physicalHeight = 1080 })
        local root = H.env.SuuUI_UIRoot
        host = H.env.CreateFrame("Frame", nil, root)
        host:SetSize(400, 300)
        H.Layout:CreateContainer({ host = root, layout = "anchor" })
            :Add(host, { anchor = { point = "TOPLEFT", relativePoint = "TOPLEFT",
                                    x = 0, y = 0, width = 400, height = 300 } })
    end)

    it("puts the root on a different scale from UIParent", function()
        expect(host:GetEffectiveScale())
            .as("otherwise this whole block proves nothing")
            .lt(H.UIParent:GetEffectiveScale())
    end)

    it("tracks a slider drag against the track's own scale", function()
        local s = H.mount(H.C.Slider({ min = 0, max = 100, value = 0, w = 200, step = 1 },
                                     host))
        local tb = H.box(s._track)
        H.cursor(tb.left + tb.width * 0.75, tb.top, s._track)
        H.mouseDown(s._hit, "LeftButton")
        H.tick(0.05)
        expect(s:GetValue()).as("cursor read in the wrong space").near(75, 1)
    end)

    it("reaches both ends of the track", function()
        local s = H.mount(H.C.Slider({ min = 0, max = 100, value = 50, w = 200, step = 1 },
                                     host))
        local tb = H.box(s._track)
        H.cursor(tb.left, tb.top, s._track)
        H.mouseDown(s._hit, "LeftButton")
        H.tick(0.05)
        expect(s:GetValue()).eq(0)

        H.cursor(tb.left + tb.width, tb.top, s._track)
        H.tick(0.05)
        expect(s:GetValue()).eq(100)
    end)

    it("picks the colour under the cursor", function()
        local cp = H.mount(H.C.ColorPicker({ value = { 1, 1, 1, 1 } }, host))
        local sv = cp._svFrame
        -- The square's own coordinate space, which is what _pickFromSV compares against.
        -- Top-right is fully saturated at full brightness.
        H.cursor(sv:GetRight() - 1, sv:GetTop() - 1, sv)
        H.mouseDown(sv, "LeftButton")
        H.tick(0.05)
        expect(cp._s).as("saturation from a mis-scaled cursor").gt(0.8)
        expect(cp._v).gt(0.8)
    end)

    it("treats a click inside a guarded panel as inside", function()
        -- Well away from the origin: a scale error shrinks the coordinate toward 0, so a
        -- panel hugging the top-left would still contain the wrong point and pass.
        local panel = H.env.CreateFrame("Frame", nil, host)
        H.Layout:CreateContainer({ host = host, layout = "anchor" })
            :Add(panel, { anchor = { point = "TOPLEFT", relativePoint = "TOPLEFT",
                                     x = 250, y = -200, width = 100, height = 50 } })
        local outside = 0
        local ca = H.C.ClickAway({ frame = panel,
                                   onOutside = function() outside = outside + 1 end })
        ca:Arm()
        H.cursorOn(panel)

        local function clickCycle()
            H.setMouseDown("LeftButton", true)
            H.tick(0.05)
            H.setMouseDown("LeftButton", false)
            H.tick(0.05)
        end

        -- Arm() deliberately swallows the release that opened the panel, so the first
        -- cycle never reaches the hit test. The second one is the real assertion.
        clickCycle()
        clickCycle()
        expect(outside).as("a mis-scaled cursor reads as outside").eq(0)
    end)
end)

-- Thin lines are the visible symptom pixel-perfect exists to fix: a 1-unit rule is 1.4
-- pixels at 1080p, which the client resolves as 1 or 2 depending on where the frame
-- happens to sit, so identical dividers draw at different thicknesses.
describe("hairlines and drag-produced geometry", function()
    local host

    before_each(function()
        H.setup()
        host = H.parent(300, 200)
    end)

    it("draws a divider at the snapped border width", function()
        local d = H.mount(H.C.Divider({ w = 200 }, host))
        expect(d:GetHeight()).eq(H.SuuUI.Pixel.Line(H.token("borderWidth")))
    end)

    it("insets a colour swatch by the snapped border width", function()
        local sw = H.mount(H.C.ColorSwatch({ value = { 1, 0, 0, 1 } }, host))
        local expected = H.SuuUI.Pixel.Line(H.token("borderWidth"))
        local outer, inner = H.box(sw._border), H.box(sw._swatch)
        expect(inner.left - outer.left).eq(expected)
        expect(outer.right - inner.right).eq(expected)
    end)

    it("keeps a divider a whole pixel on a fractional grid", function()
        H.setup({ physicalWidth = 1920, physicalHeight = 1080 })
        H.SuuUI.Pixel:SetEnabled(false)
        local P = H.SuuUI.Pixel
        host = H.parent(300, 200)
        local d = H.mount(H.C.Divider({ w = 200 }, host))
        local px = d:GetHeight() * P.physicalHeight * P.scale / 768
        expect(d:GetHeight()).as("1 unit would be 1.4 pixels").lt(1)
        expect(math.abs(px - math.floor(px + 0.5))).as("exactly one pixel").lt(1e-6)
    end)

    it("snaps a window back onto the grid after a resize drag", function()
        local win = H.Layout:CreateWindow({ id = "pixel_test", title = "T",
            w = 300, h = 200, minW = 100, minH = 80, resizable = true })
        win:Show()
        -- The client writes a drag-resize straight onto the frame, bypassing every layout.
        H.dragResize(win._gripBox:GetChildren()[1], 40.7, -13.4)
        local f = win:GetFrame()
        expect(f:GetWidth() % 1).as("width off the grid").lt(1e-6)
        expect(f:GetHeight() % 1).as("height off the grid").lt(1e-6)
        win:Hide()
    end)
end)
