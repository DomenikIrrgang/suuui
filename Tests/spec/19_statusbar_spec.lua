local H = require("harness")

describe("Components.StatusBar", function()
    local host

    before_each(function()
        H.setup()
        host = H.parent(400, 300)
    end)

    describe("construction and defaults", function()
        it("creates with default props", function()
            local bar = H.C.StatusBar({}, host)
            expect(bar).notNil()
            expect(bar:GetFrame()).notNil()
            expect(bar:GetValue()).eq(0)
            expect(bar:GetMax()).eq(1)
            expect(bar:GetPercent()).eq(0)
        end)

        it("accepts initial value and max", function()
            local bar = H.C.StatusBar({ value = 50, max = 100 }, host)
            expect(bar:GetValue()).eq(50)
            expect(bar:GetMax()).eq(100)
            expect(bar:GetPercent()).near(0.5, 0.001)
        end)

        it("applies explicit width and height", function()
            local bar = H.C.StatusBar({ w = 200, h = 20 }, host)
            H.mount(bar)
            H.expectSize(bar, 200, 20)
        end)

        it("applies fill colour from props", function()
            local color = {0.5, 0.3, 0.8, 1}
            local bar = H.C.StatusBar({ fillColor = color }, host)
            -- The bar texture should have the specified colour
            expect(bar._fillColor[1]).eq(0.5)
            expect(bar._fillColor[2]).eq(0.3)
            expect(bar._fillColor[3]).eq(0.8)
        end)

        it("defaults to white fill if no colour specified", function()
            local bar = H.C.StatusBar({}, host)
            expect(bar._fillColor[1]).eq(1)
            expect(bar._fillColor[2]).eq(1)
            expect(bar._fillColor[3]).eq(1)
        end)
    end)

    describe("value and max", function()
        it("SetValue updates the current value", function()
            local bar = H.C.StatusBar({ max = 100 }, host)
            bar:SetValue(75)
            expect(bar:GetValue()).eq(75)
            expect(bar:GetPercent()).near(0.75, 0.001)
        end)

        it("SetValue clamps to 0", function()
            local bar = H.C.StatusBar({ max = 100 }, host)
            bar:SetValue(-10)
            expect(bar:GetValue()).eq(0)
        end)

        it("SetValue clamps to max", function()
            local bar = H.C.StatusBar({ max = 100 }, host)
            bar:SetValue(200)
            expect(bar:GetValue()).eq(100)
        end)

        it("SetMax updates the maximum", function()
            local bar = H.C.StatusBar({ value = 50, max = 100 }, host)
            bar:SetMax(200)
            expect(bar:GetMax()).eq(200)
            expect(bar:GetPercent()).near(0.25, 0.001)
        end)

        it("SetMax clamps negative to 0", function()
            local bar = H.C.StatusBar({ max = 100 }, host)
            bar:SetMax(-5)
            expect(bar:GetMax()).eq(0)
            expect(bar:GetPercent()).eq(0)
        end)

        it("handles max of 0 without division error", function()
            local bar = H.C.StatusBar({ value = 10, max = 0 }, host)
            expect(bar:GetPercent()).eq(0)
        end)
    end)

    describe("fill geometry", function()
        it("fill width matches percentage of available space", function()
            local bar = H.C.StatusBar({ w = 100, h = 16, value = 50, max = 100 }, host)
            H.mount(bar)
            local bw = H.SuuUI.Pixel.Line(H.token("borderWidth"))
            local innerW = 100 - bw * 2
            local expectedFillW = H.SuuUI.Pixel.Floor(innerW * 0.5)
            expect(bar._fillFrame:GetWidth()).near(expectedFillW, 1)
        end)

        it("fill is hidden at 0%", function()
            local bar = H.C.StatusBar({ w = 100, h = 16, value = 0, max = 100 }, host)
            H.mount(bar)
            expect(bar._fillFrame:IsShown()).eq(false)
        end)

        it("fill spans full inner width at 100%", function()
            local bar = H.C.StatusBar({ w = 100, h = 16, value = 100, max = 100 }, host)
            H.mount(bar)
            local bw = H.SuuUI.Pixel.Line(H.token("borderWidth"))
            local innerW = 100 - bw * 2
            expect(bar._fillFrame:GetWidth()).near(innerW, 1)
        end)

        it("fill updates when value changes", function()
            local bar = H.C.StatusBar({ w = 100, h = 16, value = 50, max = 100 }, host)
            H.mount(bar)
            bar:SetValue(80)
            local bw = H.SuuUI.Pixel.Line(H.token("borderWidth"))
            local innerW = 100 - bw * 2
            local expectedFillW = H.SuuUI.Pixel.Floor(innerW * 0.8)
            expect(bar._fillFrame:GetWidth()).near(expectedFillW, 1)
        end)

        it("fill updates when parent resizes via container", function()
            local bar = H.C.StatusBar({ h = 16, value = 50, max = 100 }, host)
            local col = H.Layout:CreateContainer({
                host   = host,
                layout = "flow",
                dir    = "vertical",
                fill   = true,
            })
            col:Add(bar, { width = "fill", height = 16 })
            -- The bar should fill the container width (400)
            local bw = H.SuuUI.Pixel.Line(H.token("borderWidth"))
            local innerW = 400 - bw * 2
            local expectedFillW = H.SuuUI.Pixel.Floor(innerW * 0.5)
            expect(bar._fillFrame:GetWidth()).near(expectedFillW, 1)
        end)
    end)

    describe("colour", function()
        it("SetFillColor changes the bar texture colour", function()
            local bar = H.C.StatusBar({ w = 100, h = 16, value = 50, max = 100 }, host)
            bar:SetFillColor({0.8, 0.2, 0.1, 1})
            expect(bar._fillColor[1]).eq(0.8)
            expect(bar._fillColor[2]).eq(0.2)
            expect(bar._fillColor[3]).eq(0.1)
        end)

        it("SetBgColor changes the background", function()
            local bar = H.C.StatusBar({ w = 100, h = 16 }, host)
            bar:SetBgColor("colorBg")
            expect(bar._bgColor).eq("colorBg")
        end)
    end)

    describe("signals", function()
        it("emits VALUE_CHANGED on SetValue", function()
            local bar = H.C.StatusBar({ max = 100 }, host)
            local spy = H.signalSpy(bar, H.S.SIGNALS.VALUE_CHANGED)
            bar:SetValue(42)
            expect(spy.count).eq(1)
            expect(spy:arg(1)).eq(42)
            expect(spy:arg(2)).eq(0)  -- old value
        end)

        it("does not emit VALUE_CHANGED when value unchanged", function()
            local bar = H.C.StatusBar({ value = 50, max = 100 }, host)
            local spy = H.signalSpy(bar, H.S.SIGNALS.VALUE_CHANGED)
            bar:SetValue(50)
            expect(spy.count).eq(0)
        end)

        it("emits SIZE_CHANGED from OnSizeChanged hook", function()
            local bar = H.C.StatusBar({ w = 100, h = 16 }, host)
            H.mount(bar)
            local spy = H.signalSpy(bar, H.S.SIGNALS.SIZE_CHANGED)
            -- Resize via container
            local col = H.Layout:CreateContainer({
                host   = host,
                layout = "flow",
                dir    = "vertical",
                fill   = true,
            })
            col:Add(bar, { width = "fill", height = 20 })
            expect(spy.count).gt(0)
        end)
    end)

    describe("layout integration", function()
        it("works inside a flow container", function()
            local col = H.Layout:CreateContainer({
                host   = host,
                layout = "flow",
                dir    = "vertical",
                fill   = true,
            })
            local bar = H.C.StatusBar({ h = 16, value = 75, max = 100 }, host)
            col:Add(bar, { width = "fill", height = 16 })
            -- Bar should take the full container width
            expect(bar:GetWidth()).near(400, 1)
        end)
    end)

    describe("theme reaction", function()
        it("restyles on theme change", function()
            local bar = H.C.StatusBar({ w = 100, h = 16, value = 50, max = 100, border = true }, host)
            H.mount(bar)
            -- Fire theme change
            H.SuuUI.Events:Emit("SUUUI_THEME_CHANGED", "Modern")
            -- Should not error, backdrop is re-applied
            expect(bar._f._backdrop).notNil()
        end)
    end)

    describe("border option", function()
        it("shows border by default", function()
            local bar = H.C.StatusBar({ w = 100, h = 16 }, host)
            expect(bar._showBorder).eq(true)
        end)

        it("hides border when border=false", function()
            local bar = H.C.StatusBar({ w = 100, h = 16, border = false }, host)
            expect(bar._showBorder).eq(false)
        end)
    end)

    describe("destroy", function()
        it("hides and disconnects signals", function()
            local bar = H.C.StatusBar({ w = 100, h = 16 }, host)
            H.mount(bar)
            bar:Destroy()
            expect(bar:GetFrame():IsShown()).eq(false)
        end)
    end)
end)
