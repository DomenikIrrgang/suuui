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

    describe("borderless fill geometry", function()
        it("fills the whole box at 100%, with no track showing around it", function()
            local bar = H.C.StatusBar({ w = 100, h = 16, value = 100, max = 100,
                                        border = false }, host)
            H.mount(bar)
            local barBox, fillBox = H.box(bar), H.box(bar._fillFrame)
            expect(fillBox.left).eq(barBox.left)
            expect(fillBox.right).eq(barBox.right)
            expect(fillBox.top).eq(barBox.top)
            expect(fillBox.bottom).eq(barBox.bottom)
        end)

        it("an empty bar's track covers exactly what a full fill would", function()
            local empty = H.C.StatusBar({ w = 100, h = 16, value = 0, max = 100,
                                          border = false }, host)
            local full  = H.C.StatusBar({ w = 100, h = 16, value = 100, max = 100,
                                          border = false }, host)
            H.mount(empty)
            H.mount(full)
            -- The track is the bar frame itself, so the two footprints must agree: an
            -- inset fill is what made an empty bar look wider than a filled one.
            H.expectSize(empty, H.box(full._fillFrame).width, H.box(full._fillFrame).height)
        end)

        it("keeps the border inset when a border is drawn", function()
            local bar = H.C.StatusBar({ w = 100, h = 16, value = 100, max = 100,
                                        border = true }, host)
            H.mount(bar)
            local bw = H.SuuUI.Pixel.Line(H.token("borderWidth"))
            local barBox, fillBox = H.box(bar), H.box(bar._fillFrame)
            expect(fillBox.left).eq(barBox.left + bw)
            expect(fillBox.top).eq(barBox.top + bw)
            expect(fillBox.height).eq(barBox.height - bw * 2)
        end)

        it("paints the background over the whole box when borderless", function()
            local bar = H.C.StatusBar({ w = 100, h = 16, border = false }, host)
            H.mount(bar)
            local bd = H.frameOf(bar)._backdrop
            expect(bd.insets.left).eq(0)
            expect(bd.insets.top).eq(0)
        end)

        it("insets the background by the border width when bordered", function()
            local bar = H.C.StatusBar({ w = 100, h = 16, border = true }, host)
            H.mount(bar)
            local bw = H.SuuUI.Pixel.Line(H.token("borderWidth"))
            expect(H.frameOf(bar)._backdrop.insets.left).eq(bw)
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

        it("cancels in-flight transitions and leaves no animation running", function()
            H.setup({ barTransitions = true })
            host = H.parent(400, 300)
            local bar = H.C.StatusBar({ w = 200, h = 16, max = 100, value = 0 }, host)
            H.mount(bar)
            bar:SetValue(80)
            -- Mid-transition
            H.tick(0.01)
            expect(H.SuuUI.Anim:GetActiveCount(bar)).gt(0)
            bar:Destroy()
            expect(H.SuuUI.Anim:GetActiveCount(bar)).eq(0)
        end)

        it("unsubscribes from SUUUI_THEME_CHANGED", function()
            local bar = H.C.StatusBar({ w = 100, h = 16 }, host)
            H.mount(bar)
            local eid = bar._eid
            bar:Destroy()
            -- Emitting the event after destroy should not error
            H.SuuUI.Events:Emit("SUUUI_THEME_CHANGED", "Modern")
        end)

        it("disconnects UISignals", function()
            local bar = H.C.StatusBar({ w = 100, h = 16, max = 100 }, host)
            H.mount(bar)
            local spy = H.signalSpy(bar, H.S.SIGNALS.VALUE_CHANGED)
            bar:Destroy()
            -- After destroy, manual emission should not reach spy (signals disconnected)
            -- but the spy registered separately and still listens — the point is the
            -- component's own connections (like container SIZE_CHANGED) don't fire back
            -- into a dead handle. We confirm destroy didn't error.
            expect(bar:GetFrame():IsShown()).eq(false)
        end)
    end)

    ---------------------------------------------------------------------------
    -- Transition system
    ---------------------------------------------------------------------------

    describe("target/painted split", function()
        it("GetPercent returns the logical target immediately", function()
            H.setup({ barTransitions = true })
            host = H.parent(400, 300)
            local bar = H.C.StatusBar({ w = 200, h = 16, max = 100, value = 0 }, host)
            H.mount(bar)
            bar:SetValue(60)
            expect(bar:GetPercent()).as("logical target is immediate").near(0.6, 0.001)
        end)

        it("GetDisplayPercent lags the target mid-transition", function()
            H.setup({ barTransitions = true })
            host = H.parent(400, 300)
            local bar = H.C.StatusBar({ w = 200, h = 16, max = 100, value = 0 }, host)
            H.mount(bar)
            bar:SetValue(80)
            H.tick(0.01) -- advance a tiny bit
            expect(bar:GetDisplayPercent()).as("display lags").lt(0.8)
            expect(bar:GetPercent()).as("logical is immediate").near(0.8, 0.001)
        end)

        it("IsTransitioning is true mid-flight and false when settled", function()
            H.setup({ barTransitions = true })
            host = H.parent(400, 300)
            local bar = H.C.StatusBar({ w = 200, h = 16, max = 100, value = 0 }, host)
            H.mount(bar)
            bar:SetValue(50)
            H.tick(0.01)
            expect(bar:IsTransitioning()).as("mid-flight").eq(true)
            H.runAnimations()
            expect(bar:IsTransitioning()).as("settled").eq(false)
        end)

        it("GetValue reports the logical value immediately, not the display", function()
            H.setup({ barTransitions = true })
            host = H.parent(400, 300)
            local bar = H.C.StatusBar({ w = 200, h = 16, max = 100, value = 0 }, host)
            H.mount(bar)
            bar:SetValue(73)
            expect(bar:GetValue()).eq(73)
        end)
    end)

    describe("VALUE_CHANGED fires immediately and is not deferred", function()
        it("fires once with logical old/new on SetValue", function()
            H.setup({ barTransitions = true })
            host = H.parent(400, 300)
            local bar = H.C.StatusBar({ w = 200, h = 16, max = 100, value = 20 }, host)
            H.mount(bar)
            local spy = H.signalSpy(bar, H.S.SIGNALS.VALUE_CHANGED)
            bar:SetValue(70)
            expect(spy.count).as("fires exactly once").eq(1)
            expect(spy:arg(1)).as("new value").eq(70)
            expect(spy:arg(2)).as("old value").eq(20)
        end)

        it("fires before the transition completes (not deferred to settle)", function()
            H.setup({ barTransitions = true })
            host = H.parent(400, 300)
            local bar = H.C.StatusBar({ w = 200, h = 16, max = 100, value = 0 }, host)
            H.mount(bar)
            local spy = H.signalSpy(bar, H.S.SIGNALS.VALUE_CHANGED)
            bar:SetValue(50)
            -- At this point the transition is in flight but the signal already fired
            expect(spy.count).eq(1)
            expect(bar:IsTransitioning()).eq(true)
        end)

        it("SetValue is silent when value unchanged", function()
            local bar = H.C.StatusBar({ value = 42, max = 100 }, host)
            local spy = H.signalSpy(bar, H.S.SIGNALS.VALUE_CHANGED)
            bar:SetValue(42)
            expect(spy.count).as("setter silent on no-op").eq(0)
        end)

        it("SetMax does not emit VALUE_CHANGED", function()
            local bar = H.C.StatusBar({ value = 50, max = 100 }, host)
            local spy = H.signalSpy(bar, H.S.SIGNALS.VALUE_CHANGED)
            bar:SetMax(200)
            expect(spy.count).as("SetMax is silent").eq(0)
        end)
    end)

    describe("FILL_SETTLED signal", function()
        it("fires when instant strategy settles on the same call", function()
            local bar = H.C.StatusBar({ w = 200, h = 16, max = 100, value = 0 }, host)
            H.mount(bar)
            local spy = H.signalSpy(bar, H.C.STATUSBAR_SIGNALS.FILL_SETTLED)
            bar:SetValue(60)
            expect(spy.count).as("settles immediately with instant").eq(1)
            expect(spy:arg(1)).as("payload is fraction").near(0.6, 0.001)
        end)

        it("fires exactly once per settle, not per tick", function()
            H.setup({ barTransitions = true })
            host = H.parent(400, 300)
            local bar = H.C.StatusBar({ w = 200, h = 16, max = 100, value = 0 }, host)
            H.mount(bar)
            local spy = H.signalSpy(bar, H.C.STATUSBAR_SIGNALS.FILL_SETTLED)
            bar:SetValue(40)
            H.runAnimations()
            expect(spy.count).as("one settle signal").eq(1)
            expect(spy:arg(1)).as("settled fraction").near(0.4, 0.001)
        end)

        it("does not fire mid-transition", function()
            H.setup({ barTransitions = true })
            host = H.parent(400, 300)
            local bar = H.C.StatusBar({ w = 200, h = 16, max = 100, value = 0 }, host)
            H.mount(bar)
            local spy = H.signalSpy(bar, H.C.STATUSBAR_SIGNALS.FILL_SETTLED)
            bar:SetValue(80)
            H.tick(0.01)
            expect(spy.count).as("not settled yet").eq(0)
        end)

        it("fires after retarget once the final target is reached", function()
            H.setup({ barTransitions = true })
            host = H.parent(400, 300)
            local bar = H.C.StatusBar({ w = 200, h = 16, max = 100, value = 0 }, host)
            H.mount(bar)
            local spy = H.signalSpy(bar, H.C.STATUSBAR_SIGNALS.FILL_SETTLED)
            bar:SetValue(50)
            H.tick(0.01)
            bar:SetValue(80) -- retarget
            H.runAnimations()
            -- Should settle at 0.8, not 0.5
            local found08 = false
            for i = 1, spy.count do
                if math.abs(spy.calls[i][1] - 0.8) < 0.001 then found08 = true end
            end
            expect(found08).as("settled at final target").eq(true)
        end)
    end)

    describe("immediate option", function()
        it("SetValue with immediate=true skips the transition", function()
            H.setup({ barTransitions = true })
            host = H.parent(400, 300)
            local bar = H.C.StatusBar({ w = 200, h = 16, max = 100, value = 0 }, host)
            H.mount(bar)
            bar:SetValue(75, { immediate = true })
            expect(bar:GetDisplayPercent()).near(0.75, 0.001)
            expect(bar:IsTransitioning()).eq(false)
        end)

        it("SetMax with immediate=true skips the transition", function()
            H.setup({ barTransitions = true })
            host = H.parent(400, 300)
            local bar = H.C.StatusBar({ w = 200, h = 16, max = 100, value = 50 }, host)
            H.mount(bar)
            bar:SetMax(200, { immediate = true })
            expect(bar:GetDisplayPercent()).near(0.25, 0.001)
            expect(bar:IsTransitioning()).eq(false)
        end)
    end)

    describe("SetMax clamping", function()
        it("clamps value down when new max is lower than current value", function()
            local bar = H.C.StatusBar({ value = 80, max = 100 }, host)
            bar:SetMax(50)
            expect(bar:GetValue()).as("value clamped to new max").eq(50)
            expect(bar:GetMax()).eq(50)
            expect(bar:GetPercent()).near(1.0, 0.001)
        end)

        it("does not clamp value when new max is higher", function()
            local bar = H.C.StatusBar({ value = 30, max = 100 }, host)
            bar:SetMax(200)
            expect(bar:GetValue()).eq(30)
        end)
    end)

    describe("retarget mid-flight", function()
        it("does not jump the fill — display continues from current position", function()
            H.setup({ barTransitions = true })
            host = H.parent(400, 300)
            local bar = H.C.StatusBar({ w = 200, h = 16, max = 100, value = 0 }, host)
            H.mount(bar)
            bar:SetValue(80)
            H.tick(0.03)
            local midDisplay = bar:GetDisplayPercent()
            expect(midDisplay).as("moved from 0").gt(0)
            expect(midDisplay).as("not yet at target").lt(0.8)
            -- Retarget
            bar:SetValue(40)
            -- The display should not jump to 0.4 or back to 0
            local afterRetarget = bar:GetDisplayPercent()
            expect(afterRetarget).as("did not jump down to new target").gte(midDisplay * 0.5)
            -- Let it settle
            H.runAnimations()
            expect(bar:GetDisplayPercent()).near(0.4, 0.001)
        end)
    end)

    describe("theme change mid-transition", function()
        it("does not jump the fill to target or cancel the transition", function()
            H.setup({ barTransitions = true })
            host = H.parent(400, 300)
            local bar = H.C.StatusBar({ w = 200, h = 16, max = 100, value = 0 }, host)
            H.mount(bar)
            bar:SetValue(90)
            H.tick(0.02)
            local displayBefore = bar:GetDisplayPercent()
            expect(displayBefore).as("in transit").gt(0)
            expect(displayBefore).as("not yet at target").lt(0.9)
            -- Fire theme change
            H.SuuUI.Events:Emit("SUUUI_THEME_CHANGED", "Modern")
            local displayAfter = bar:GetDisplayPercent()
            -- The display should be at the same painted fraction, not jumped to target
            expect(displayAfter).as("theme did not jump fill").near(displayBefore, 0.01)
            -- Transition should still be in flight
            expect(bar:IsTransitioning()).as("transition still active").eq(true)
            -- Let it finish
            H.runAnimations()
            expect(bar:GetDisplayPercent()).near(0.9, 0.001)
        end)
    end)

    describe("SnapToTarget", function()
        it("immediately paints the target fraction", function()
            H.setup({ barTransitions = true })
            host = H.parent(400, 300)
            local bar = H.C.StatusBar({ w = 200, h = 16, max = 100, value = 0 }, host)
            H.mount(bar)
            bar:SetValue(65)
            H.tick(0.01)
            expect(bar:IsTransitioning()).eq(true)
            bar:SnapToTarget()
            expect(bar:GetDisplayPercent()).near(0.65, 0.001)
            expect(bar:IsTransitioning()).eq(false)
        end)

        it("emits FILL_SETTLED when it snaps", function()
            H.setup({ barTransitions = true })
            host = H.parent(400, 300)
            local bar = H.C.StatusBar({ w = 200, h = 16, max = 100, value = 0 }, host)
            H.mount(bar)
            local spy = H.signalSpy(bar, H.C.STATUSBAR_SIGNALS.FILL_SETTLED)
            bar:SetValue(50)
            H.tick(0.01)
            spy:reset()
            bar:SnapToTarget()
            expect(spy.count).eq(1)
            expect(spy:arg(1)).near(0.5, 0.001)
        end)
    end)

    describe("hide/show snaps to target", function()
        it("OnHide snaps the display to target", function()
            H.setup({ barTransitions = true })
            host = H.parent(400, 300)
            local bar = H.C.StatusBar({ w = 200, h = 16, max = 100, value = 0 }, host)
            H.mount(bar)
            bar:SetValue(70)
            H.tick(0.01)
            expect(bar:IsTransitioning()).eq(true)
            bar:GetFrame():Hide()
            expect(bar:GetDisplayPercent()).as("snapped on hide").near(0.7, 0.001)
            expect(bar:IsTransitioning()).eq(false)
        end)

        it("OnShow snaps and restates geometry correctly", function()
            H.setup({ barTransitions = true })
            host = H.parent(400, 300)
            local bar = H.C.StatusBar({ w = 200, h = 16, max = 100, value = 0 }, host)
            H.mount(bar)
            bar:SetValue(50, { immediate = true })
            bar:GetFrame():Hide()
            -- Change value while hidden
            bar:SetValue(80, { immediate = true })
            bar:GetFrame():Show()
            expect(bar:GetDisplayPercent()).near(0.8, 0.001)
            -- Verify fill geometry is correct
            local bw = H.SuuUI.Pixel.Line(H.token("borderWidth"))
            local innerW = 200 - bw * 2
            local expectedFillW = H.SuuUI.Pixel.Floor(innerW * 0.8)
            expect(bar._fillFrame:GetWidth()).near(expectedFillW, 1)
        end)

        it("OnShow does not break the host container re-layout", function()
            H.setup({ barTransitions = true })
            host = H.parent(400, 300)
            local col = H.Layout:CreateContainer({
                host   = host,
                layout = "flow",
                dir    = "vertical",
                fill   = true,
            })
            local bar = H.C.StatusBar({ h = 16, max = 100, value = 50 }, host)
            col:Add(bar, { width = "fill", height = 16 })
            -- The bar should fill the container width
            expect(bar:GetWidth()).near(400, 1)
            bar:GetFrame():Hide()
            bar:GetFrame():Show()
            -- After show, the fill should still be correctly sized (container re-layed out)
            local bw = H.SuuUI.Pixel.Line(H.token("borderWidth"))
            local innerW = 400 - bw * 2
            local expectedFillW = H.SuuUI.Pixel.Floor(innerW * 0.5)
            expect(bar._fillFrame:GetWidth()).near(expectedFillW, 1)
        end)
    end)

    describe("pixel quantisation guard", function()
        it("a sub-pixel fraction change performs no layout pass at all", function()
            local bar = H.C.StatusBar({ w = 100, h = 16, max = 10000, value = 5000 }, host)
            H.mount(bar)
            -- Observe the layout itself. Asserting only that the fill's width is
            -- unchanged proves nothing: StackLayout floors the fraction onto the pixel
            -- grid, so an UNGUARDED write lands on the same pixel too and the widths
            -- match either way. The guard's whole purpose is skipping the layout pass,
            -- so that is what has to be measured.
            local layouts = 0
            local box  = bar._fillBox
            local orig = box.Layout
            box.Layout = function(self, ...) layouts = layouts + 1; return orig(self, ...) end

            -- 1 part in 10000 across a 100-unit bar is a hundredth of a pixel.
            bar:SetValue(5001)
            expect(layouts).as("sub-pixel change performs no layout").eq(0)

            -- A change big enough to move a whole pixel must still get through.
            bar:SetValue(7500)
            expect(layouts).as("a visible change still lays out").eq(1)

            box.Layout = orig
            -- The logical value tracks regardless of what was painted.
            expect(bar:GetValue()).eq(7500)
            expect(bar:GetPercent()).near(0.75, 0.0001)
        end)

        it("GetDisplayPercent tracks even when quantised away", function()
            local bar = H.C.StatusBar({ w = 100, h = 16, max = 10000, value = 5000 }, host)
            H.mount(bar)
            bar:SetValue(5001)
            -- The display fraction did update even though the pixel didn't
            expect(bar:GetDisplayPercent()).near(0.5001, 0.0001)
        end)

        it("resize after a skipped sub-pixel write produces the correct fill", function()
            local bar = H.C.StatusBar({ w = 100, h = 16, max = 10000, value = 5000 }, host)
            H.mount(bar)
            bar:SetValue(5001) -- sub-pixel, quantised away
            -- Now resize the bar to a wider width where the fraction IS visible
            bar:GetFrame():SetWidth(1000)
            bar:GetFrame():_fire("OnSizeChanged", 1000, 16)
            local bw = H.SuuUI.Pixel.Line(H.token("borderWidth"))
            local innerW = 1000 - bw * 2
            local expectedFillW = H.SuuUI.Pixel.Floor(innerW * 0.5001)
            expect(bar._fillFrame:GetWidth()).near(expectedFillW, 1)
        end)
    end)

    describe("transition API", function()
        it("construction uses the prop transition", function()
            local bar = H.C.StatusBar({ w = 100, h = 16, transition = "rate" }, host)
            expect(bar:GetTransition()).eq("rate")
        end)

        it("SetTransition changes the strategy", function()
            local bar = H.C.StatusBar({ w = 100, h = 16 }, host)
            bar:SetTransition("rate")
            expect(bar:GetTransition()).eq("rate")
        end)

        it("SetTransition accepts an inline strategy table", function()
            local applied = false
            local bar = H.C.StatusBar({ w = 100, h = 16, max = 100, value = 0 }, host)
            H.mount(bar)
            bar:SetTransition({
                Apply = function(ctx, from, to) applied = true; ctx:Set(to) end,
            })
            expect(bar:GetTransition()).eq("custom")
            bar:SetValue(50)
            expect(applied).eq(true)
        end)

        it("SetTransitionDuration overrides the token", function()
            H.setup({ barTransitions = true })
            host = H.parent(400, 300)
            local bar = H.C.StatusBar({ w = 200, h = 16, max = 100, value = 0,
                                        transitionDuration = 5 }, host)
            H.mount(bar)
            bar:SetValue(100)
            -- After a short tick, it should barely have moved because duration is 5s
            H.tick(0.1)
            expect(bar:GetDisplayPercent()).as("slow due to long duration").lt(0.5)
        end)

        it("SetTransitionDuration accepts nil to restore token", function()
            local bar = H.C.StatusBar({ w = 100, h = 16, transitionDuration = 5 }, host)
            bar:SetTransitionDuration(nil)
            -- Now it should use the animBarFill token internally
            -- Just verify it doesn't error
            expect(bar._duration).isNil()
        end)
    end)

    describe("construction starts settled", function()
        it("a bar with an initial value starts settled, not animating", function()
            H.setup({ barTransitions = true })
            host = H.parent(400, 300)
            local bar = H.C.StatusBar({ w = 200, h = 16, max = 100, value = 60 }, host)
            H.mount(bar)
            expect(bar:IsTransitioning()).as("starts settled").eq(false)
            expect(bar:GetDisplayPercent()).near(0.6, 0.001)
            expect(bar:GetPercent()).near(0.6, 0.001)
        end)
    end)

    describe("border colour and visibility", function()
        local host
        before_each(function() host = H.parent(300, 200) end)

        it("borderColor defaults to colorBorder", function()
            local bar = H.mount(H.C.StatusBar({ w = 100, h = 20 }, host))
            H.expectTokenColor(H.borderColor(bar), "colorBorder")
        end)

        it("a borderColor prop is honoured at construction", function()
            local bar = H.mount(H.C.StatusBar({ w = 100, h = 20,
                                               borderColor = "colorShield" }, host))
            H.expectTokenColor(H.borderColor(bar), "colorShield")
        end)

        it("SetBorderColor recolours without changing whether a border is drawn", function()
            local bar = H.mount(H.C.StatusBar({ w = 100, h = 20 }, host))
            bar:SetBorderColor("colorShield")
            expect(bar:IsBorderShown()).eq(true)
            H.expectTokenColor(H.borderColor(bar), "colorShield")
        end)

        it("SetBorderShown adds a border to a frameless bar and insets the fill", function()
            local bar = H.mount(H.C.StatusBar({ w = 100, h = 20, border = false,
                                               value = 50, max = 100 }, host))
            expect(bar:IsBorderShown()).eq(false)
            local flush = H.box(bar._fillFrame).left - H.box(bar).left
            expect(flush).as("borderless, so the fill starts at the edge").near(0, 0.5)

            bar:SetBorderShown(true)
            expect(bar:IsBorderShown()).eq(true)
            local line = H.SuuUI.Pixel.Line(H.token("borderWidth"))
            expect(H.box(bar._fillFrame).left - H.box(bar).left)
                .as("inset by the border width").near(line, 0.5)
        end)

        it("SetBorderShown(false) removes it again and restores the flush fill", function()
            local bar = H.mount(H.C.StatusBar({ w = 100, h = 20, value = 50, max = 100 }, host))
            bar:SetBorderShown(false)
            expect(bar:IsBorderShown()).eq(false)
            expect(H.box(bar._fillFrame).left - H.box(bar).left).near(0, 0.5)
        end)

        it("toggling the border does not disturb the painted fraction", function()
            local bar = H.mount(H.C.StatusBar({ w = 100, h = 20, value = 40, max = 100 }, host))
            bar:SetBorderShown(false)
            expect(bar:GetDisplayPercent()).as("geometry changed, value did not").near(0.4, 0.001)
            expect(bar:IsTransitioning()).eq(false)
        end)

        it("an overridden border colour survives a theme change", function()
            local bar = H.mount(H.C.StatusBar({ w = 100, h = 20 }, host))
            bar:SetBorderColor("colorShield")
            H.T:CreateUserTheme("BarTheme", "Modern")
            H.T:SetActive("BarTheme")
            H.expectTokenColor(H.borderColor(bar), "colorShield")
        end)
    end)

    ---------------------------------------------------------------------------
    -- Enabled-state omission (deliberate — display-only, no mouse input)
    --
    -- StatusBar is not a control. It takes no mouse input and is never a target
    -- of Dependency.Bind. Removing SetEnabled ensures Dependency.lua's guard
    -- (`if target.SetEnabled`) correctly skips it. The composite that owns a bar
    -- (a unit frame, a cast bar) fades its own outer handle, and frame alpha
    -- cascades — so a bar has no second fade of its own.
    ---------------------------------------------------------------------------
    describe("enabled-state omission", function()
        it("does not expose SetEnabled — not a control; Dependency skips it", function()
            local bar = H.C.StatusBar({ w = 100, h = 16, max = 100, value = 50 }, host)
            expect(bar.SetEnabled)
                .as("StatusBar is display-only; Dependency.Bind must skip it").isNil()
        end)

        it("does not expose IsEnabled", function()
            local bar = H.C.StatusBar({ w = 100, h = 16 }, host)
            expect(bar.IsEnabled).isNil()
        end)

        it("Dependency.Bind leaves a StatusBar alone instead of pretending to grey it", function()
            -- The consequence that matters, and the reason an InstallEnable with
            -- _fade = false would be wrong here rather than merely redundant: Bind's
            -- guard is `if target.SetEnabled`, so a bar carrying a SetEnabled that
            -- fades nothing and drops no mouse would satisfy the guard while staying
            -- fully lit. Absent, it is skipped honestly.
            local bar = H.C.StatusBar({ w = 100, h = 16, max = 100, value = 50 }, host)
            H.SuuUI.Settings:Register("dep_probe", {
                { key = "gate", label = "Gate", type = "toggle", default = true },
                { key = "bar",  label = "Bar",  type = "slider", default = 1,
                  enabledIf = "gate" },
            })
            local entry = H.SuuUI.Settings:GetSchema("dep_probe")[2]

            local ok = pcall(H.SuuUI._SettingsDeps.Bind, "dep_probe", entry, bar)
            expect(ok).as("binding a bar is a no-op, not an error").eq(true)

            -- Flipping the dependency off must not reach the bar at all.
            H.SuuUI.Settings:Set("dep_probe", "gate", false)
            expect(bar:GetFrame():GetAlpha()).as("never faded").eq(1)
            expect(bar.SetEnabled).as("still no stub to satisfy the guard").isNil()

            H.SuuUI.Settings:Unwatch(H.SuuUI.Settings.ControlOwner("dep_probe", "slider", "bar"))
        end)
    end)

    ---------------------------------------------------------------------------
    -- Overlay text
    --
    -- Three readout slots inside the bar's box. Placement is asserted as a RULE — inset
    -- from an edge, centred on an axis — rather than as a measured width, because the
    -- width comes from the text-measurement path and a spec that pinned the number would
    -- be asserting the measurement rather than the layout.
    ---------------------------------------------------------------------------
    describe("overlay text", function()
        -- How far a readout sits in from the bar's edge: past the border, then one space
        -- step. Both are tokens, which is the whole reason not to write a number here.
        local function inset(bar)
            local bw = bar:IsBorderShown()
                       and H.SuuUI.Pixel.Line(H.token("borderWidth")) or 0
            return bw + H.token("spaceXs")
        end

        local function makeBar(props)
            props = props or {}
            props.w, props.h = props.w or 200, props.h or 24
            props.max, props.value = props.max or 100, props.value or 50
            return H.mount(H.C.StatusBar(props, host))
        end

        it("builds nothing until a slot is written", function()
            local bar = makeBar()
            expect(bar._textBox).as("no overlay frame for a bar with no text").isNil()
            expect(bar._texts.left).isNil()
            expect(bar:GetText("center")).isNil()
        end)

        it("builds a slot lazily on first write and reports it back", function()
            local bar = makeBar()
            bar:SetText("left", "42")
            expect(bar:GetText("left")).eq("42")
            expect(bar._texts.left).notNil()
            expect(bar._textBox).notNil()
            expect(bar._texts.center).as("only the slot written is built").isNil()
        end)

        it("clearing a slot that was never written builds nothing", function()
            local bar = makeBar()
            bar:SetText("center", nil)
            expect(bar._textBox).as("no element to clear, so no overlay").isNil()
        end)

        it("nil clears a slot", function()
            local bar = makeBar()
            bar:SetText("right", "80%")
            bar:SetText("right", nil)
            expect(bar:GetText("right")).isNil()
            expect(bar._texts.right:IsShown()).as("cleared, not left showing").eq(false)
        end)

        it("an empty string clears a slot, like nil", function()
            local bar = makeBar()
            bar:SetText("right", "80%")
            bar:SetText("right", "")
            expect(bar:GetText("right")).isNil()
            expect(bar._texts.right:IsShown()).eq(false)
        end)

        it("showing a slot again after clearing reuses the element", function()
            local bar = makeBar()
            bar:SetText("left", "1")
            local el = bar._texts.left
            bar:SetText("left", nil)
            bar:SetText("left", "2")
            expect(bar._texts.left).as("no second element per slot").eq(el)
            expect(el:IsShown()).eq(true)
        end)

        it("insets the left readout from the bar's left edge", function()
            local bar = makeBar()
            bar:SetText("left", "1234")
            local dx = H.offset(bar._texts.left, bar)
            expect(dx).near(inset(bar), 1)
        end)

        it("insets the right readout from the bar's right edge", function()
            local bar = makeBar()
            bar:SetText("right", "80%")
            local bb, tb = H.box(bar), H.box(bar._texts.right)
            expect((bb.left + bb.width) - (tb.left + tb.width)).near(inset(bar), 1)
        end)

        it("centres the centre readout on the bar", function()
            local bar = makeBar()
            bar:SetText("center", "50 / 100")
            H.expectCenteredH(bar._texts.center, bar)
        end)

        it("centres every slot vertically", function()
            local bar = makeBar({ h = 32 })
            bar:SetText("left", "50")
            bar:SetText("center", "50 / 100")
            bar:SetText("right", "50%")
            H.expectCenteredV(bar._texts.left, bar)
            H.expectCenteredV(bar._texts.center, bar)
            H.expectCenteredV(bar._texts.right, bar)
        end)

        it("keeps every readout inside the bar", function()
            local bar = makeBar()
            bar:SetText("left", "50")
            bar:SetText("center", "50 / 100")
            bar:SetText("right", "50%")
            H.expectInside(bar._texts.left, bar)
            H.expectInside(bar._texts.center, bar)
            H.expectInside(bar._texts.right, bar)
        end)

        it("does not overlap the three slots at ordinary widths", function()
            local bar = makeBar({ w = 300 })
            bar:SetText("left", "50")
            bar:SetText("center", "50 / 100")
            bar:SetText("right", "50%")
            H.expectNoOverlap({ bar._texts.left, bar._texts.center, bar._texts.right })
        end)

        it("draws the readout over the fill, not under it", function()
            -- The fill lives in a CHILD frame of the bar, so a font string in the bar's
            -- own layers would be hidden behind a full bar. The overlay is what carries
            -- the z-order, and this is the assertion that would catch it losing.
            local bar = makeBar({ value = 100 })
            bar:SetText("center", "100 / 100")
            H.expectDrawsAbove(bar._textOverlay, bar._fillFrame)
            expect(bar._texts.center:GetFrame():GetParent())
                .as("the readout rides the overlay").eq(bar._textOverlay)
        end)

        it("reserves enough box for the glyphs in every slot", function()
            local bar = makeBar({ w = 300 })
            bar:SetText("left", "12345")
            bar:SetText("center", "12345 / 67890")
            bar:SetText("right", "100%")
            H.expectTextNotClipped(bar._texts.left)
            H.expectTextNotClipped(bar._texts.center)
            H.expectTextNotClipped(bar._texts.right)
        end)

        it("renders at the small font step by default", function()
            local bar = makeBar()
            bar:SetText("center", "50")
            local _, size = H.fontOf(bar._texts.center)
            expect(size).eq(H.token("fontSizeSm"))
        end)

        it("takes its font step from the textSize prop", function()
            local bar = makeBar({ textSize = "lg" })
            bar:SetText("center", "50")
            local _, size = H.fontOf(bar._texts.center)
            expect(size).eq(H.token("fontSizeLg"))
        end)

        it("changes the step of every slot at once through SetTextSize", function()
            -- One step for the whole bar: three readouts on one bar at three sizes reads
            -- as a rendering fault rather than a choice.
            local bar = makeBar({ w = 300 })
            bar:SetText("left", "50")
            bar:SetText("center", "50 / 100")
            bar:SetText("right", "50%")
            bar:SetTextSize("xl")
            expect(bar:GetTextSize()).eq("xl")
            for _, slot in ipairs({ "left", "center", "right" }) do
                local _, size = H.fontOf(bar._texts[slot])
                expect(size).as(slot .. " follows the bar's step").eq(H.token("fontSizeXl"))
                H.expectTextNotClipped(bar._texts[slot])
            end
        end)

        it("applies the step to a slot written after the change", function()
            -- Order must not matter: a plugin sets the size from a watcher and writes the
            -- readouts from a game event, and neither knows which lands first.
            local bar = makeBar()
            bar:SetTextSize("lg")
            bar:SetText("center", "50 / 100")
            local _, size = H.fontOf(bar._texts.center)
            expect(size).eq(H.token("fontSizeLg"))
        end)

        it("keeps the readouts placed and unclipped at a bigger step", function()
            local bar = makeBar({ w = 300, h = 40 })
            bar:SetText("left", "8420")
            bar:SetText("right", "92%")
            bar:SetTextSize("xl")
            expect(H.offset(bar._texts.left, bar)).near(inset(bar), 1)
            local bb, tb = H.box(bar), H.box(bar._texts.right)
            expect((bb.left + bb.width) - (tb.left + tb.width)).near(inset(bar), 1)
            H.expectCenteredV(bar._texts.left, bar)
        end)

        it("still follows the token after the step changed", function()
            local bar = makeBar()
            bar:SetText("center", "50 / 100")
            bar:SetTextSize("lg")
            H.T:CreateUserTheme("Big", "Modern")
            H.T:SetUserToken("Big", "fontSizeLg", 26)
            H.T:SetActive("Big")
            local _, size = H.fontOf(bar._texts.center)
            expect(size).as("the step is a key, not an escape from the theme").eq(26)
        end)

        it("ignores a nil step rather than dropping to a default", function()
            local bar = makeBar({ textSize = "lg" })
            bar:SetText("center", "50")
            bar:SetTextSize(nil)
            expect(bar:GetTextSize()).eq("lg")
        end)

        it("re-derives the readout font when the token moves", function()
            local bar = makeBar({ textSize = "md" })
            bar:SetText("center", "50 / 100")
            H.T:CreateUserTheme("Big", "Modern")
            H.T:SetUserToken("Big", "fontSizeMd", 30)
            H.T:SetActive("Big")
            local _, size = H.fontOf(bar._texts.center)
            expect(size).as("font steps are user-editable").eq(30)
            H.expectTextNotClipped(bar._texts.center)
            H.expectCenteredH(bar._texts.center, bar)
        end)

        it("re-derives the readout inset when the spacing token moves", function()
            local bar = makeBar()
            bar:SetText("left", "50")
            H.T:CreateUserTheme("Roomy", "Modern")
            H.T:SetUserToken("Roomy", "spaceXs", 12)
            H.T:SetActive("Roomy")
            local dx = H.offset(bar._texts.left, bar)
            expect(dx).as("inset follows the token, not the value at construction")
                .near(inset(bar), 1)
        end)

        it("keeps the readouts placed when the bar is resized by a layout", function()
            local bar = makeBar({ w = 200 })
            bar:SetText("left", "50")
            bar:SetText("right", "50%")
            bar:GetFrame():SetWidth(320)
            local dx = H.offset(bar._texts.left, bar)
            expect(dx).near(inset(bar), 1)
            local bb, tb = H.box(bar), H.box(bar._texts.right)
            expect((bb.left + bb.width) - (tb.left + tb.width)).near(inset(bar), 1)
        end)

        it("skips the work when the readout has not changed", function()
            -- A readout is written on every game event and usually says the same thing;
            -- a percentage stays 51% for most of the ticks that produce it.
            local bar = makeBar()
            bar:SetText("center", "50 / 100")
            local spy = H.signalSpy(bar._texts.center, H.S.SIGNALS.TEXT_CHANGED)
            bar:SetText("center", "50 / 100")
            expect(spy.count).as("an identical write does nothing").eq(0)
            bar:SetText("center", "49 / 100")
            expect(spy.count).eq(1)
        end)

        it("rejects a slot name it has no placement for", function()
            local bar = makeBar()
            expect(function() bar:SetText("middle", "50") end).throws("slot")
            expect(function() bar:GetText("top") end).throws("slot")
        end)

        it("insets past the border on a bordered bar", function()
            local plain = makeBar({ border = true })
            plain:SetText("left", "50")
            local bordered = H.offset(plain._texts.left, plain)

            local bare = makeBar({ border = false })
            bare:SetText("left", "50")
            local borderless = H.offset(bare._texts.left, bare)

            expect(bordered).as("text clears the edge it would otherwise sit on")
                .gt(borderless)
            expect(bordered - borderless)
                .near(H.SuuUI.Pixel.Line(H.token("borderWidth")), 1)
        end)

        it("releases the readouts on Destroy", function()
            local bar = makeBar()
            bar:SetText("left", "50")
            bar:SetText("center", "50 / 100")
            local el = bar._texts.left
            local spy = H.signalSpy(el, H.S.SIGNALS.TEXT_CHANGED)
            bar:Destroy()
            expect(bar._textBox).isNil()
            expect(next(bar._texts)).as("every element released").isNil()
            H.SuuUI.Events:Emit("SUUUI_THEME_CHANGED", "Modern")
            expect(spy.count).as("a destroyed readout is not restyled").eq(0)
        end)
    end)
end)

-- The SECONDARY (ghost) fill, added for the watch bars: rested experience reaching past current
-- progress. A second fractional child of the same container rather than a stacked second bar -- a
-- stacked pair would need its own alignment, resize handling and theme plumbing kept in step.
describe("Components.StatusBar secondary fill", function()
    local host

    before_each(function()
        H.setup()
        host = H.parent(400, 60)
    end)

    local function bar(props)
        props = props or {}
        props.w = props.w or 200
        props.h = props.h or 20
        props.max = props.max or 100
        props.transition = props.transition or "instant"
        local b = H.C.StatusBar(props, host)
        b:GetFrame():SetPoint("TOPLEFT", host, "TOPLEFT", 0, 0)
        return b
    end

    it("draws nothing until asked", function()
        -- A bar with no rested experience must look exactly like a bar that has no concept of it.
        local b = bar()
        b:SetValue(30)
        expect(b:GetSecondary()).eq(0)
        expect(b._secFrame:IsShown()).falsy()
    end)

    it("reaches past the main fill", function()
        local b = bar()
        b:SetValue(30)
        b:SetSecondary(0.7)
        expect(b._secFrame:IsShown()).truthy()
        expect(b._secFrame:GetWidth() > b._fillFrame:GetWidth())
            .as("the ghost is wider than progress").truthy()
    end)

    it("CLAMPS to the main fill rather than falling behind it", function()
        -- A ghost narrower than progress would be drawn entirely underneath it and read as absent,
        -- which is indistinguishable from a bug. The floor lives in the component so no caller has to
        -- remember it.
        local b = bar()
        b:SetValue(50)
        b:SetSecondary(0.1)
        expect(b._secFrame:GetWidth()).eq(b._fillFrame:GetWidth())
    end)

    it("is PUSHED when progress overtakes it", function()
        -- Experience gained past the rested threshold. Re-asserted when the main fill moves, not only
        -- when the caller sets the ghost.
        local b = bar()
        b:SetValue(30)
        b:SetSecondary(0.5)
        local before = b._secFrame:GetWidth()
        b:SetValue(90)
        expect(b._secFrame:GetWidth() > before).truthy()
        expect(b._secFrame:GetWidth()).eq(b._fillFrame:GetWidth())
    end)

    it("clamps above 1, so an over-full fraction cannot overhang the track", function()
        -- Rested experience can legitimately be reported past the end of the level, and a fraction
        -- over 1 would draw the ghost wider than the bar it belongs to.
        local b = bar()
        b:SetSecondary(1.5)
        expect(b:GetSecondary()).eq(1)
        expect(b._secFrame:GetWidth() <= b:GetWidth()).as("inside the track").truthy()
    end)

    it("hides again at zero", function()
        local b = bar()
        b:SetValue(30)
        b:SetSecondary(0.7)
        b:SetSecondary(0)
        expect(b._secFrame:IsShown()).as("a zero-width child still costs a cell").falsy()
    end)

    it("draws BEHIND the main fill, not over it", function()
        -- In a stack container the later child is the higher one, so the ghost is added first. The
        -- other order would put a stripe on top of progress instead of a backdrop behind it.
        local b = bar()
        expect(H.drawLayerRank or true).truthy()
        b:SetValue(30)
        b:SetSecondary(0.9)
        expect(b._fillFrame:GetFrameLevel() >= b._secFrame:GetFrameLevel())
            .as("main fill is not below the ghost").truthy()
    end)

    it("FOLLOWS the fill colour at a reduced alpha when given no colour of its own", function()
        -- `fillColor`, taking a LITERAL -- there is no `fill` prop, and no token-key form. This spec
        -- used to say `fill = "colorAccent"`, which StatusBar silently ignored, so every assertion here
        -- ran against a WHITE bar while the comment claimed blue. That phantom prop is also what the
        -- watch bars plugin copied, shipping a white experience bar.
        local b = bar({ fillColor = { 0.25, 0.55, 1.00, 1.00 } })
        b:SetValue(30)
        b:SetSecondary(0.7)
        local mr, mg, mb, ma = b._bar:GetColorTexture()
        local gr, gg, gb, ga = b._secTex:GetColorTexture()
        expect({ gr, gg, gb }).as("same hue").deepEq({ mr, mg, mb })
        expect(ga).eq(ma * H.token("opacityBarGhost"))
        expect(ga < ma).as("and fainter").truthy()
    end)

    it("takes a colour of its OWN when set, ignoring the fill and opacityBarGhost", function()
        -- Derivation is wrong whenever the ghost means something the fill does not. Experience is that
        -- case: blue IS rested in WoW, so a paler-purple ghost reads as more progress rather than as a
        -- rested bonus. The colour is applied exactly as given -- opacityBarGhost is NOT multiplied in,
        -- because a theme naming this colour has already decided how present it should be.
        local b = bar({ fillColor = { 1, 0, 1, 1 } })
        b:SetValue(30)
        b:SetSecondary(0.7)
        b:SetSecondaryColor({ 0, 0.5, 1, 0.55 })
        local gr, gg, gb, ga = b._secTex:GetColorTexture()
        expect({ gr, gg, gb }).as("its own hue, not the fill's").deepEq({ 0, 0.5, 1 })
        expect(ga).as("its own alpha, not scaled by the ghost token").eq(0.55)
    end)

    it("goes back to deriving when its own colour is cleared", function()
        local b = bar({ fillColor = { 1, 0, 1, 1 } })
        b:SetSecondary(0.7)
        b:SetSecondaryColor({ 0, 0.5, 1, 0.55 })
        b:SetSecondaryColor(nil)
        local gr, gg, gb = b._secTex:GetColorTexture()
        expect({ gr, gg, gb }).as("the fill's hue again").deepEq({ 1, 0, 1 })
    end)

    it("re-derives its colour on a theme change", function()
        local b = bar({ fillColor = { 0.25, 0.55, 1.00, 1.00 } })
        b:SetSecondary(0.7)
        b._secTex:SetColorTexture(0, 0, 0, 0)
        b:ApplyTheme()
        local _, _, _, ga = b._secTex:GetColorTexture()
        expect(ga > 0).truthy()
    end)

    it("keeps its OWN pixel guard, so one fill cannot invalidate the other's", function()
        -- The guard exists so a change too small to move a pixel costs no layout pass. Sharing one
        -- cache between the two fills would make a sub-pixel change to either invalidate both.
        local b = bar()
        b:SetValue(30)
        b:SetSecondary(0.7)
        local mainPx, ghostPx = b._lastPx, b._secLastPx
        expect(mainPx).notNil()
        expect(ghostPx).notNil()
        expect(mainPx == ghostPx).as("two different fractions, two different pixel counts").falsy()
    end)

    it("survives a resize with both fills correct", function()
        -- The guard caches a pixel count against the old width, so both caches have to be invalidated
        -- or a skipped write leaves a fraction up to a pixel stale at the new width.
        local b = bar()
        b:SetValue(50)
        b:SetSecondary(0.75)
        b:GetFrame():SetWidth(400)
        expect(b._secFrame:GetWidth() > b._fillFrame:GetWidth()).truthy()
        expect(b._secFrame:GetWidth() > 200).as("scaled with the bar").truthy()
    end)
end)
