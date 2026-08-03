local H = require("harness")

describe("StackLayout", function()
    local host

    before_each(function()
        H.setup()
        host = H.parent(200, 100)
    end)

    local function stack(props)
        props = props or {}
        props.host = host
        props.layout = "stack"
        return H.Layout:CreateContainer(props)
    end

    local function child(w, h)
        local f = H.env.CreateFrame("Frame", nil, host)
        if w then f:SetSize(w, h or w) end
        return f
    end

    it("stretches a child over the whole box by default", function()
        local box = stack()
        local bg = child()
        box:Add(bg)
        H.expectSize(bg, 200, 100)
        H.expectOffset(bg, host, 0, 0)
    end)

    it("insets a child uniformly with a numeric inset", function()
        local box = stack()
        local icon = child()
        box:Add(icon, { inset = 3 })
        H.expectSize(icon, 200 - 6, 100 - 6)
        H.expectOffset(icon, host, 3, 3)
    end)

    it("insets each edge independently with a table inset", function()
        local box = stack()
        local t = child()
        box:Add(t, { inset = { left = 6, right = 16, top = 2, bottom = 4 } })
        H.expectSize(t, 200 - 6 - 16, 100 - 2 - 4)
        H.expectOffset(t, host, 6, 2)
    end)

    it("centres a natural-sized child on both axes", function()
        local box = stack()
        local lbl = child(40, 20)
        box:Add(lbl, { align = "center", valign = "center" })
        H.expectSize(lbl, 40, 20)
        H.expectCenteredH(lbl, host)
        H.expectCenteredV(lbl, host)
    end)

    it("pins a child to the right edge with align='end' plus an inset", function()
        local box = stack()
        local arrow = child()
        box:Add(arrow, { align = "end", valign = "center", width = 8, inset = { right = 4 } })
        local hostBox, arrowBox = H.box(host), H.box(arrow)
        expect(arrowBox.right).eq(hostBox.right - 4)
        expect(arrowBox.width).eq(8)
    end)

    it("spans edges vertically centred, the label-with-room-for-arrow pattern", function()
        local box = stack()
        local text = host:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        text:SetFont("Fonts/FRIZQT__.TTF", 12, "")
        text:SetText("Selected option")
        box:Add(text, { valign = "center", inset = { left = 6, right = 16 } })
        H.expectSize(text, 200 - 22, H.lineHeight(12))
        H.expectOffset(text, host, 6, (100 - H.lineHeight(12)) / 2)
    end)

    it("collapses an unsized frame on the axis it is not stretched on", function()
        -- valign without a height leaves the natural height, which for a bare frame
        -- with no size is zero. Real callers pass font strings or an explicit height.
        local box = stack()
        local bare = child()
        box:Add(bare, { valign = "center", inset = { left = 6 } })
        H.expectSize(bare, 200 - 6, 0)
    end)

    it("respects an explicit width when the axis is not stretched", function()
        local box = stack()
        local a = child(999, 999)
        box:Add(a, { align = "start", valign = "start", width = 25, height = 12 })
        H.expectSize(a, 25, 12)
        H.expectOffset(a, host, 0, 0)
    end)

    it("overlays several children on the same box", function()
        local box = stack()
        local layers = { child(), child(), child() }
        for _, l in ipairs(layers) do box:Add(l) end
        for _, l in ipairs(layers) do
            H.expectSize(l, 200, 100)
            H.expectOffset(l, host, 0, 0)
        end
    end)

    it("applies container padding before the child inset", function()
        local box = stack({ padding = { top = 5, right = 5, bottom = 5, left = 5 } })
        local a = child()
        box:Add(a, { inset = 2 })
        H.expectOffset(a, host, 7, 7)
        H.expectSize(a, 200 - 14, 100 - 14)
    end)

    it("honours container-level align and valign", function()
        local box = stack({ align = "end", valign = "end" })
        local a = child(30, 10)
        box:Add(a)
        local hostBox, aBox = H.box(host), H.box(a)
        expect(aBox.right).eq(hostBox.right)
        expect(aBox.bottom).eq(hostBox.bottom)
    end)

    it("never produces a negative size when insets exceed the box", function()
        local small = H.parent(10, 10)
        local box = H.Layout:CreateContainer({ host = small, layout = "stack" })
        local a = H.env.CreateFrame("Frame", nil, small)
        box:Add(a, { inset = 50 })
        expect(a:GetWidth()).eq(0)
        expect(a:GetHeight()).eq(0)
    end)

    it("positions textures and font strings, not just frames", function()
        local box = stack()
        local tex = host:CreateTexture(nil, "BACKGROUND")
        local fs  = host:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        fs:SetFont("Fonts/FRIZQT__.TTF", 12, "")
        fs:SetText("centred")
        box:Add(tex)
        box:Add(fs, { align = "center", valign = "center" })
        H.expectSize(tex, 200, 100)
        H.expectCenteredH(fs, host)
    end)

    describe("content size", function()
        it("reports the widest and tallest child plus insets and padding", function()
            local box = stack({ padding = { top = 2, right = 3, bottom = 4, left = 5 } })
            box:Add(child(50, 10), { align = "start", valign = "start", width = 50, height = 10 })
            box:Add(child(20, 40), { align = "start", valign = "start", width = 20, height = 40,
                                     inset = { left = 4, right = 4 } })
            local w, h = box:GetContentSize()
            expect(w).as("widest is 50 + horizontal padding").eq(50 + 5 + 3)
            expect(h).as("tallest is 40 + vertical padding").eq(40 + 2 + 4)
        end)

        it("reports only padding with no children", function()
            local box = stack({ padding = { top = 2, right = 3, bottom = 4, left = 5 } })
            local w, h = box:GetContentSize()
            expect(w).eq(8)
            expect(h).eq(6)
        end)
    end)
end)

describe("GridLayout", function()
    local host

    before_each(function()
        H.setup()
        host = H.parent(300, 200)
    end)

    local function child(h)
        local f = H.env.CreateFrame("Frame", nil, host)
        f:SetSize(10, h or 20)
        return f
    end

    it("divides the inner width evenly between columns", function()
        local grid = H.Layout:CreateContainer({
            host = host, layout = "grid", cols = 3, gap = 10,
            padding = { left = 5, right = 5 },
        })
        local cells = {}
        for i = 1, 3 do cells[i] = child() grid:Add(cells[i]) end
        -- (300 - 10 - 20) / 3
        local expected = (300 - 10 - 20) / 3
        for _, cell in ipairs(cells) do H.expectSize(cell, expected, nil) end
    end)

    it("wraps to the next row after the column count", function()
        local grid = H.Layout:CreateContainer({ host = host, layout = "grid", cols = 2, gap = 8 })
        local cells = {}
        for i = 1, 4 do cells[i] = child(20) grid:Add(cells[i]) end
        local r1a, r1b = H.box(cells[1]), H.box(cells[2])
        local r2a = H.box(cells[3])
        expect(r1a.top).as("first row shares a top edge").eq(r1b.top)
        expect(r2a.top).as("second row sits a row height plus gap lower").eq(r1a.bottom + 8)
        expect(r2a.left).eq(r1a.left)
    end)

    it("separates columns by the gap", function()
        local grid = H.Layout:CreateContainer({ host = host, layout = "grid", cols = 2, gap = 12 })
        local a, b = child(), child()
        grid:Add(a)
        grid:Add(b)
        H.expectRowHorizontally({ a, b }, 12)
    end)

    it("keeps every cell inside the container", function()
        local grid = H.Layout:CreateContainer({
            host = host, layout = "grid", cols = 3, gap = 6,
            padding = { top = 6, right = 6, bottom = 6, left = 6 },
        })
        local cells = {}
        for i = 1, 6 do cells[i] = child(20) grid:Add(cells[i]) end
        for _, cell in ipairs(cells) do H.expectInside(cell, host) end
        H.expectNoOverlap(cells)
    end)

    it("reports content size across rows", function()
        local grid = H.Layout:CreateContainer({ host = host, layout = "grid", cols = 2, gap = 10 })
        for _ = 1, 4 do grid:Add(child(30)) end
        local _, h = grid:GetContentSize()
        expect(h).as("two rows of 30 plus one gap").eq(70)
    end)
end)

describe("AnchorLayout", function()
    local host

    before_each(function()
        H.setup()
        host = H.parent(200, 100)
    end)

    local function anchorBox()
        return H.Layout:CreateContainer({ host = host, layout = "anchor" })
    end

    it("places a child at the descriptor's offset", function()
        local box = anchorBox()
        local thumb = H.env.CreateFrame("Frame", nil, host)
        box:Add(thumb, { anchor = { point = "LEFT", relativePoint = "LEFT",
                                    x = 30, y = 0, width = 12, height = 12 } })
        H.expectSize(thumb, 12, 12)
        local hostBox, thumbBox = H.box(host), H.box(thumb)
        expect(thumbBox.left).eq(hostBox.left + 30)
        H.expectCenteredV(thumb, host)
    end)

    it("moves a child when the descriptor is re-applied", function()
        local box = anchorBox()
        local thumb = H.env.CreateFrame("Frame", nil, host)
        local desc = { point = "LEFT", relativePoint = "LEFT", x = 0, y = 0, width = 8, height = 8 }
        box:Add(thumb, { anchor = desc })
        desc.x = 75
        box:SetChildAnchor(thumb, desc)
        expect(H.box(thumb).left).eq(H.box(host).left + 75)
    end)

    it("anchors relative to another frame when relativeTo is given", function()
        local box = anchorBox()
        local reference = H.env.CreateFrame("Frame", nil, host)
        reference:SetSize(20, 20)
        reference:SetPoint("TOPLEFT", host, "TOPLEFT", 50, -10)

        local panel = H.env.CreateFrame("Frame", nil, host)
        box:Add(panel, { anchor = {
            point = "TOPLEFT", relativeTo = reference, relativePoint = "BOTTOMLEFT",
            x = 0, y = -2, width = 40, height = 30,
        } })
        H.expectOffset(panel, reference, 0, 22)
    end)

    it("unwraps a component handle passed as relativeTo", function()
        local box = anchorBox()
        local btn = H.C.Button({ label = "Ref" }, host)
        box:Add(btn, { anchor = { point = "TOPLEFT", x = 20, y = -20 } })

        local panel = H.env.CreateFrame("Frame", nil, host)
        box:Add(panel, { anchor = {
            point = "TOPLEFT", relativeTo = btn, relativePoint = "BOTTOMLEFT",
            x = 0, y = 0, width = 10, height = 10,
        } })
        H.expectOffset(panel, btn:GetFrame(), 0, btn:GetHeight())
    end)

    it("treats relativeTo='parent' and nil as the container itself", function()
        local box = anchorBox()
        local a = H.env.CreateFrame("Frame", nil, host)
        local b = H.env.CreateFrame("Frame", nil, host)
        box:Add(a, { anchor = { point = "TOPLEFT", relativeTo = "parent", x = 5, y = -5,
                                width = 10, height = 10 } })
        box:Add(b, { anchor = { point = "TOPLEFT", x = 5, y = -5, width = 10, height = 10 } })
        expect(H.box(a).left).eq(H.box(b).left)
        expect(H.box(a).top).eq(H.box(b).top)
    end)

    it("leaves a child with no descriptor untouched", function()
        local box = anchorBox()
        local orphan = H.env.CreateFrame("Frame", nil, host)
        orphan:SetSize(10, 10)
        orphan:ClearAllPoints()
        expect(function() box:Add(orphan) end).notThrows()
        expect(orphan:GetLeft()).isNil()
    end)

    it("keeps the child's own size when the descriptor omits width and height", function()
        local box = anchorBox()
        local a = H.env.CreateFrame("Frame", nil, host)
        a:SetSize(33, 17)
        box:Add(a, { anchor = { point = "TOPLEFT", x = 0, y = 0 } })
        H.expectSize(a, 33, 17)
    end)
end)
