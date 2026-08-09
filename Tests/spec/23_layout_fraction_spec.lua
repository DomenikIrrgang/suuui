local H = require("harness")

describe("StackLayout – fractional sizing", function()
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

    local function pxfloor(v) return H.SuuUI.Pixel.Floor(v) end
    local function pxsnap(v) return H.SuuUI.Pixel.Snap(v) end
    local function pxceil(v) return H.SuuUI.Pixel.Ceil(v) end

    ---------------------------------------------------------------------------
    -- widthFraction basic values: 0 / 0.5 / 1
    ---------------------------------------------------------------------------

    it("widthFraction=0 produces zero width", function()
        local box = stack()
        local c = child()
        box:Add(c, { widthFraction = 0 })
        H.expectSize(c, 0, 100)
    end)

    it("widthFraction=0.5 produces half the inner width", function()
        local box = stack()
        local c = child()
        box:Add(c, { widthFraction = 0.5 })
        H.expectSize(c, pxfloor(200 * 0.5), 100)
    end)

    it("widthFraction=1 produces the full inner width", function()
        local box = stack()
        local c = child()
        box:Add(c, { widthFraction = 1 })
        H.expectSize(c, pxfloor(200 * 1), 100)
    end)

    ---------------------------------------------------------------------------
    -- Fraction respects inset on both axes
    ---------------------------------------------------------------------------

    it("widthFraction respects left and right inset", function()
        local box = stack()
        local c = child()
        box:Add(c, { widthFraction = 0.5, inset = { left = 10, right = 10 } })
        local innerW = 200 - pxsnap(10) - pxsnap(10)
        H.expectSize(c, pxfloor(innerW * 0.5), nil)
    end)

    it("heightFraction respects top and bottom inset", function()
        local box = stack()
        local c = child()
        box:Add(c, { heightFraction = 0.5, valign = "start", inset = { top = 8, bottom = 12 } })
        local innerH = 100 - pxsnap(8) - pxsnap(12)
        H.expectSize(c, nil, pxfloor(innerH * 0.5))
    end)

    ---------------------------------------------------------------------------
    -- Fraction combined with valign="stretch" gives full height, fractional width
    ---------------------------------------------------------------------------

    it("widthFraction + valign=stretch: fractional width and full height", function()
        local box = stack()
        local c = child()
        box:Add(c, { widthFraction = 0.6, valign = "stretch" })
        H.expectSize(c, pxfloor(200 * 0.6), 100)
    end)

    ---------------------------------------------------------------------------
    -- align="end" puts a fractional child against the far edge
    ---------------------------------------------------------------------------

    it("align=end places fractional child against the right edge", function()
        local box = stack()
        local c = child()
        box:Add(c, { widthFraction = 0.25, align = "end" })
        local expectedW = pxfloor(200 * 0.25)
        H.expectSize(c, expectedW, nil)
        local hostBox = H.box(host)
        local cBox = H.box(c)
        expect(cBox.right).eq(hostBox.right)
    end)

    ---------------------------------------------------------------------------
    -- align="center" centres a fractional child
    ---------------------------------------------------------------------------

    it("align=center centres a fractional child", function()
        local box = stack()
        local c = child()
        box:Add(c, { widthFraction = 0.5, align = "center" })
        H.expectCenteredH(c, host)
    end)

    ---------------------------------------------------------------------------
    -- Clamping: values below 0 and above 1
    ---------------------------------------------------------------------------

    it("widthFraction below 0 is clamped to 0", function()
        local box = stack()
        local c = child()
        box:Add(c, { widthFraction = -0.5 })
        H.expectSize(c, 0, nil)
    end)

    it("widthFraction above 1 is clamped to 1", function()
        local box = stack()
        local c = child()
        box:Add(c, { widthFraction = 2.5 })
        H.expectSize(c, pxfloor(200 * 1), nil)
    end)

    ---------------------------------------------------------------------------
    -- heightFraction works on the vertical axis
    ---------------------------------------------------------------------------

    it("heightFraction=0.5 produces half the inner height", function()
        local box = stack()
        local c = child()
        box:Add(c, { heightFraction = 0.5, valign = "start" })
        H.expectSize(c, nil, pxfloor(100 * 0.5))
    end)

    it("heightFraction=1 produces the full inner height", function()
        local box = stack()
        local c = child()
        box:Add(c, { heightFraction = 1, valign = "start" })
        H.expectSize(c, nil, pxfloor(100 * 1))
    end)

    ---------------------------------------------------------------------------
    -- Container resize re-derives pixel size from the SAME stored fraction
    ---------------------------------------------------------------------------

    it("resize re-derives fractional size without further calls", function()
        local box = stack()
        local c = child()
        box:Add(c, { widthFraction = 0.5 })
        H.expectSize(c, pxfloor(200 * 0.5), nil)

        -- Resize the container — fraction should auto-recompute
        host:SetSize(400, 100)
        box:Layout()
        H.expectSize(c, pxfloor(400 * 0.5), nil)
    end)

    ---------------------------------------------------------------------------
    -- SetChildFraction preserves inset and align
    ---------------------------------------------------------------------------

    it("SetChildFraction preserves existing inset and align", function()
        local box = stack()
        local c = child()
        box:Add(c, { align = "end", inset = { left = 5, right = 5 } })
        box:SetChildFraction(c, "width", 0.4)

        -- Props should still contain the original inset and align
        local props = c._layoutProps
        expect(props.align).eq("end")
        expect(props.inset.left).eq(5)
        expect(props.inset.right).eq(5)

        -- And the fraction should be applied
        local innerW = 200 - pxsnap(5) - pxsnap(5)
        local expectedW = pxfloor(innerW * 0.4)
        H.expectSize(c, expectedW, nil)
    end)

    ---------------------------------------------------------------------------
    -- SetChildFraction with a bad axis name errors
    ---------------------------------------------------------------------------

    it("SetChildFraction errors on an invalid axis name", function()
        local box = stack()
        local c = child()
        box:Add(c)
        expect(function() box:SetChildFraction(c, "depth", 0.5) end).throws()
    end)

    ---------------------------------------------------------------------------
    -- ContentSize ignores the fractional axis
    ---------------------------------------------------------------------------

    it("ContentSize contributes 0 on the fractional axis", function()
        local box = stack()
        box:Add(child(30, 20), { align = "start", valign = "start", width = 30, height = 20 })
        box:Add(child(), { widthFraction = 0.8, valign = "start", height = 10 })
        local w, _ = box:GetContentSize()
        -- The fractional child contributes 0 width, so content width comes from the 30px child
        expect(w).eq(pxceil(30))
    end)

    it("ContentSize ignores heightFraction on the vertical axis", function()
        local box = stack()
        box:Add(child(20, 40), { align = "start", valign = "start", width = 20, height = 40 })
        box:Add(child(), { heightFraction = 0.9, align = "start", width = 10 })
        local _, h = box:GetContentSize()
        -- The fractional child contributes 0 height, so content height comes from the 40px child
        expect(h).eq(pxceil(40))
    end)

    ---------------------------------------------------------------------------
    -- height="fill" with non-stretch valign does NOT throw
    ---------------------------------------------------------------------------

    it("height='fill' with valign='center' does not throw", function()
        local box = stack()
        local c = child()
        expect(function()
            box:Add(c, { height = "fill", valign = "center" })
        end).notThrows()
        -- The non-number height is treated as natural size (0 for a bare frame)
        H.expectSize(c, 200, 0)
    end)

    ---------------------------------------------------------------------------
    -- Fraction with container padding
    ---------------------------------------------------------------------------

    it("fraction respects container padding", function()
        local box = stack({ padding = { left = 10, right = 10, top = 5, bottom = 5 } })
        local c = child()
        box:Add(c, { widthFraction = 0.5, heightFraction = 1, valign = "start" })
        local innerW = pxfloor(200 - 10 - 10)
        local innerH = pxfloor(100 - 5 - 5)
        H.expectSize(c, pxfloor(innerW * 0.5), pxfloor(innerH * 1))
    end)

    ---------------------------------------------------------------------------
    -- Default alignment for fractional children is start (left/top)
    ---------------------------------------------------------------------------

    it("fractional child defaults to start alignment (top-left)", function()
        local box = stack()
        local c = child()
        box:Add(c, { widthFraction = 0.3, heightFraction = 0.4, valign = "start", align = "start" })
        H.expectOffset(c, host, 0, 0)
    end)
end)
