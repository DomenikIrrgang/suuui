local H = require("harness")

describe("Container", function()
    local host

    before_each(function()
        H.setup()
        host = H.parent(300, 200)
    end)

    local function child(w, h)
        local f = H.env.CreateFrame("Frame", nil, host)
        f:SetSize(w or 50, h or 20)
        return f
    end

    describe("construction", function()
        it("requires a parent or a host", function()
            expect(function() H.Layout:CreateContainer({ layout = "flow" }) end)
                .throws("parent or host required")
        end)

        it("self-anchors to its parent's top-left", function()
            local c = H.Layout:CreateContainer({ parent = host, layout = "flow" })
            H.expectOffset(c, host, 0, 0)
        end)

        it("defaults its width to the parent's width", function()
            local c = H.Layout:CreateContainer({ parent = host, layout = "flow" })
            expect(c:GetWidth()).eq(300)
        end)

        it("takes an explicit width over the parent's", function()
            local c = H.Layout:CreateContainer({ parent = host, layout = "flow", w = 120 })
            expect(c:GetWidth()).eq(120)
        end)

        it("adopts a host frame instead of creating one", function()
            local c = H.Layout:CreateContainer({ host = host, layout = "stack" })
            expect(c:GetFrame()).eq(host)
        end)

        it("unwraps a container passed as parent", function()
            local outer = H.Layout:CreateContainer({ parent = host, layout = "flow" })
            local inner = H.Layout:CreateContainer({ parent = outer, layout = "flow" })
            expect(inner:GetFrame():GetParent()).eq(outer:GetFrame())
        end)

        it("mirrors the parent size with fill=true", function()
            local c = H.Layout:CreateContainer({ parent = host, layout = "anchor", fill = true })
            expect(c:GetWidth()).eq(300)
            expect(c:GetHeight()).eq(200)
        end)

        it("tracks later parent resizes with fill=true", function()
            local c = H.Layout:CreateContainer({ parent = host, layout = "anchor", fill = true })
            host:SetSize(500, 400)
            expect(c:GetWidth()).eq(500)
            expect(c:GetHeight()).eq(400)
        end)
    end)

    describe("host adoption", function()
        it("chains onto an existing OnSizeChanged instead of replacing it", function()
            local pre = 0
            host:SetScript("OnSizeChanged", function() pre = pre + 1 end)
            local c = H.Layout:CreateContainer({ host = host, layout = "flow" })
            local a = child()
            c:Add(a, { width = "fill", height = 10 })
            host:SetSize(400, 200)
            expect(pre).as("the pre-existing hook still fires").gte(1)
            expect(a:GetWidth()).as("and the container re-laid out").eq(400)
        end)

        it("re-lays out when the host is shown", function()
            local hidden = H.parent(100, 100)
            hidden:Hide()
            local c = H.Layout:CreateContainer({ host = hidden, layout = "flow" })
            local a = child()
            c:Add(a, { width = "fill", height = 10 })
            hidden:SetWidth(180)
            hidden:Show()
            expect(a:GetWidth()).eq(180)
        end)
    end)

    describe("hugging", function()
        it("sizes its height to its content when no height is given", function()
            local c = H.Layout:CreateContainer({ parent = host, layout = "flow",
                                                 dir = "vertical", gap = 4 })
            c:Add(child(10, 20), { width = "fill", height = 20 })
            c:Add(child(10, 30), { width = "fill", height = 30 })
            expect(c:GetHeight()).as("20 + 4 + 30").eq(54)
        end)

        it("includes vertical padding in the hugged height", function()
            local c = H.Layout:CreateContainer({
                parent = host, layout = "flow", dir = "vertical", gap = 0,
                padding = { top = 6, bottom = 9 },
            })
            c:Add(child(10, 20), { width = "fill", height = 20 })
            expect(c:GetHeight()).eq(35)
        end)

        it("grows when a child is added and shrinks when one is removed", function()
            local c = H.Layout:CreateContainer({ parent = host, layout = "flow",
                                                 dir = "vertical", gap = 0 })
            local a, b = child(10, 20), child(10, 20)
            c:Add(a, { width = "fill", height = 20 })
            expect(c:GetHeight()).eq(20)
            c:Add(b, { width = "fill", height = 20 })
            expect(c:GetHeight()).eq(40)
            c:Remove(b)
            expect(c:GetHeight()).eq(20)
        end)

        it("stops hugging once an explicit height is given", function()
            local c = H.Layout:CreateContainer({ parent = host, layout = "flow",
                                                 dir = "vertical", h = 150 })
            c:Add(child(10, 20), { width = "fill", height = 20 })
            expect(c:GetHeight()).eq(150)
        end)

        it("does not hug when fill is set", function()
            local c = H.Layout:CreateContainer({ parent = host, layout = "flow",
                                                 dir = "vertical", fill = true })
            c:Add(child(10, 20), { width = "fill", height = 20 })
            expect(c:GetHeight()).eq(200)
        end)

        it("does not hug an adopted host frame", function()
            local c = H.Layout:CreateContainer({ host = host, layout = "flow", dir = "vertical" })
            c:Add(child(10, 20), { width = "fill", height = 20 })
            expect(host:GetHeight()).as("the host keeps its own height").eq(200)
        end)

        it("resolves cross-axis alignment against the settled hugged height", function()
            local c = H.Layout:CreateContainer({ parent = host, layout = "flow",
                                                 dir = "horizontal", gap = 0 })
            local tall  = child(20, 40)
            local short = child(20, 10)
            c:Add(tall, { width = 20, height = 40 })
            c:Add(short, { width = 20, height = 10, align = "center" })
            expect(c:GetHeight()).eq(40)
            H.expectOffset(short, c, 20, 15)
        end)
    end)

    describe("Add", function()
        it("accepts a raw frame", function()
            local c = H.Layout:CreateContainer({ parent = host, layout = "flow" })
            local a = child()
            c:Add(a, { width = "fill", height = 10 })
            expect(c:GetChildren()[1]).eq(a)
        end)

        it("unwraps a component handle to its frame", function()
            local c = H.Layout:CreateContainer({ parent = host, layout = "flow" })
            local btn = H.C.Button({ label = "Go" }, c:GetFrame())
            c:Add(btn)
            expect(c:GetChildren()[1]).eq(btn:GetFrame())
        end)

        it("accepts a nested container", function()
            local outer = H.Layout:CreateContainer({ parent = host, layout = "flow",
                                                     dir = "vertical", gap = 0 })
            local inner = H.Layout:CreateContainer({ parent = outer, layout = "flow",
                                                     dir = "horizontal", gap = 0 })
            inner:Add(child(30, 20), { width = 30, height = 20 })
            outer:Add(inner, { width = "fill" })
            expect(outer:GetChildren()[1]).eq(inner:GetFrame())
            H.expectOffset(inner, outer, 0, 0)
        end)

        it("returns the child it was given", function()
            local c = H.Layout:CreateContainer({ parent = host, layout = "flow" })
            local a = child()
            expect(c:Add(a)).eq(a)
        end)

        it("re-lays out when a child reports a new size", function()
            local c = H.Layout:CreateContainer({ parent = host, layout = "flow",
                                                 dir = "vertical", gap = 0 })
            local first  = H.C.Text({ text = "one" }, c:GetFrame())
            local second = child(10, 20)
            c:Add(first, { width = "fill" })
            c:Add(second, { width = "fill", height = 20 })
            local topBefore = H.box(second).top

            first:SetText("a much much much longer label that wraps onto more lines")
            c:SetWidth(60)
            expect(H.box(second).top).as("the following child moved down").gt(topBefore)
        end)

        it("clears a nested container's hug when the parent pins its height", function()
            local outer = H.Layout:CreateContainer({ parent = host, layout = "flow",
                                                     dir = "vertical" })
            local inner = H.Layout:CreateContainer({ parent = outer, layout = "flow" })
            inner:Add(child(10, 20), { width = "fill", height = 20 })
            outer:Add(inner, { width = "fill", height = 90 })
            expect(inner:GetHeight()).eq(90)
        end)
    end)

    describe("Remove and Clear", function()
        it("drops the child and re-lays out the rest", function()
            local c = H.Layout:CreateContainer({ parent = host, layout = "flow",
                                                 dir = "vertical", gap = 0 })
            local a, b, d = child(10, 20), child(10, 20), child(10, 20)
            c:Add(a, { width = "fill", height = 20 })
            c:Add(b, { width = "fill", height = 20 })
            c:Add(d, { width = "fill", height = 20 })
            c:Remove(b)
            expect(#c:GetChildren()).eq(2)
            H.expectStackedVertically({ a, d }, 0)
        end)

        it("accepts either the handle or its frame", function()
            local c = H.Layout:CreateContainer({ parent = host, layout = "flow" })
            local btn = H.C.Button({ label = "X" }, c:GetFrame())
            c:Add(btn)
            c:Remove(btn:GetFrame())
            expect(#c:GetChildren()).eq(0)
        end)

        it("leaves another listener's connection on the child intact", function()
            local c = H.Layout:CreateContainer({ parent = host, layout = "flow" })
            local text = H.C.Text({ text = "hi" }, c:GetFrame())
            local spy = H.signalSpy(text, H.S.SIGNALS.SIZE_CHANGED)
            c:Add(text, { width = "fill" })
            c:Remove(text)
            spy:reset()
            H.S:Emit(text, H.S.SIGNALS.SIZE_CHANGED, 10, 10)
            expect(spy.count).as("external listener still connected").eq(1)
            expect(H.S:HasConnections(text, H.S.SIGNALS.SIZE_CHANGED)).truthy()
        end)

        it("hides and forgets every child on Clear", function()
            local c = H.Layout:CreateContainer({ parent = host, layout = "flow" })
            local a, b = child(), child()
            c:Add(a)
            c:Add(b)
            c:Clear()
            expect(#c:GetChildren()).eq(0)
            expect(a:IsShown()).falsy()
            expect(b:IsShown()).falsy()
        end)

        it("ignores removing something never added", function()
            local c = H.Layout:CreateContainer({ parent = host, layout = "flow" })
            expect(function() c:Remove(child()) end).notThrows()
        end)
    end)

    describe("signals", function()
        it("emits SIZE_CHANGED when the computed size changes", function()
            local c = H.Layout:CreateContainer({ parent = host, layout = "flow",
                                                 dir = "vertical", gap = 0 })
            local spy = H.signalSpy(c, H.S.SIGNALS.SIZE_CHANGED)
            c:Add(child(10, 25), { width = "fill", height = 25 })
            expect(spy.count).gte(1)
            expect(spy:arg(2)).eq(25)
        end)

        it("does not re-emit when a layout pass leaves the size unchanged", function()
            local c = H.Layout:CreateContainer({ parent = host, layout = "flow",
                                                 dir = "vertical", h = 100 })
            c:Add(child(10, 20), { width = "fill", height = 20 })
            local spy = H.signalSpy(c, H.S.SIGNALS.SIZE_CHANGED)
            c:Layout()
            c:Layout()
            expect(spy.count).eq(0)
        end)

        it("emits VISIBILITY_CHANGED from Show and Hide", function()
            local c = H.Layout:CreateContainer({ parent = host, layout = "flow" })
            local spy = H.signalSpy(c, H.S.SIGNALS.VISIBILITY_CHANGED)
            c:Hide()
            c:Show()
            expect(spy.count).eq(2)
            expect(spy:arg(1, 1)).falsy()
            expect(spy:arg(1, 2)).truthy()
        end)
    end)

    describe("re-entrancy", function()
        it("does not recurse when a child resize triggers a re-layout", function()
            local c = H.Layout:CreateContainer({ parent = host, layout = "flow",
                                                 dir = "vertical", gap = 2 })
            for _ = 1, 10 do
                c:Add(H.C.Text({ text = "row of text" }, c:GetFrame()), { width = "fill" })
            end
            expect(function() c:SetWidth(80) end).notThrows()
            expect(function() c:SetWidth(300) end).notThrows()
        end)

        it("settles a nested hierarchy in a bounded number of passes", function()
            local outer = H.Layout:CreateContainer({ parent = host, layout = "flow",
                                                     dir = "vertical", gap = 4 })
            for _ = 1, 5 do
                local row = H.Layout:CreateContainer({ parent = outer, layout = "flow",
                                                       dir = "horizontal", gap = 4 })
                row:Add(H.C.Text({ text = "label" }, row:GetFrame()), { width = "fill" })
                row:Add(H.C.Toggle({}, row:GetFrame()), { width = 36, height = 18 })
                outer:Add(row, { width = "fill" })
            end
            expect(H.state.settleIterations).lte(20)
            expect(outer:GetHeight()).gt(0)
        end)
    end)

    describe("SetChildProps", function()
        it("changes a child's sizing without re-adding it", function()
            local c = H.Layout:CreateContainer({ parent = host, layout = "stack" })
            local a = child()
            c:Add(a, { inset = 0 })
            c:SetChildProps(a, { inset = 10 })
            H.expectOffset(a, c, 10, 10)
        end)

        it("accepts nil props to drop all layout properties", function()
            local c = H.Layout:CreateContainer({ host = host, layout = "stack" })
            local a = child()
            c:Add(a, { inset = 10 })
            c:SetChildProps(a, nil)
            H.expectOffset(a, host, 0, 0)
        end)
    end)

    describe("Destroy", function()
        it("drops children and destroys the ones that can be", function()
            local c = H.Layout:CreateContainer({ parent = host, layout = "flow" })
            local btn = H.C.Button({ label = "Bye" }, c:GetFrame())
            c:Add(btn)
            c:Destroy()
            expect(#c:GetChildren()).eq(0)
            expect(btn:IsShown()).falsy()
        end)

        it("hides its own frame but not an adopted host", function()
            local own = H.Layout:CreateContainer({ parent = host, layout = "flow" })
            local adopted = H.Layout:CreateContainer({ host = host, layout = "stack" })
            own:Destroy()
            expect(own:GetFrame():IsShown()).falsy()
            adopted:Destroy()
            expect(host:IsShown()).as("an adopted host is not ours to hide").truthy()
        end)
    end)

    describe("floating host", function()
        it("returns the same shared container every time", function()
            expect(H.Layout:GetFloatingHost()).eq(H.Layout:GetFloatingHost())
        end)

        it("uses the UI root as its frame", function()
            expect(H.Layout:GetFloatingHost():GetFrame()).eq(H.SuuUI.UIRoot:GetRoot())
        end)

        it("places panels relative to arbitrary frames", function()
            local hostContainer = H.Layout:GetFloatingHost()
            local trigger = H.parent(80, 24)
            local panel = H.env.CreateFrame("Frame", nil, H.UIParent)
            hostContainer:Add(panel, { anchor = {
                point = "TOPLEFT", relativeTo = trigger, relativePoint = "BOTTOMLEFT",
                x = 0, y = -2, width = 80, height = 60,
            } })
            H.expectOffset(panel, trigger, 0, 26)
            hostContainer:Remove(panel)
        end)
    end)
end)
