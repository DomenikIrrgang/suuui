-- Verifies the code examples printed in .kiro/steering/TESTING.md and UI_SIGNALS.md.
-- A steering example that does not work teaches the wrong thing.
local H = require("harness")

describe("steering doc examples", function()
    local host
    before_each(function()
        H.setup()
        host = H.parent(300, 200)
    end)

    it("TESTING.md: unmounted component has unresolvable inner geometry", function()
        local nav = H.C.NavItem({ label = "General" }, host)
        expect(H.box(nav._label)).as("the anti-example really does fail").isNil()
    end)

    it("TESTING.md: H.mount makes inner geometry assertable", function()
        local nav = H.mount(H.C.NavItem({ label = "General" }, host))
        H.expectCenteredV(nav._label, nav:GetFrame())
    end)

    it("TESTING.md: adding to a container also resolves it", function()
        local col = H.Layout:CreateContainer({ parent = host, layout = "flow", dir = "vertical" })
        local nav = H.C.NavItem({ label = "General" }, col:GetFrame())
        col:Add(nav, { width = "fill", height = H.token("sizeNavRow") })
        H.expectCenteredV(nav._label, nav:GetFrame())
    end)

    it("TESTING.md: the button size derivation is correct", function()
        local btn = H.C.Button({ label = "OK" }, host)
        local size = H.token("fontSizeMd")
        local padX = H.token("spaceSm") + H.token("borderWidth")
        local padY = H.token("spaceXs") + H.token("borderWidth")
        H.expectSize(btn, H.textWidth("OK", size) + 2 + padX * 2,
                          H.lineHeight(size) + padY * 2)
    end)

    it("TESTING.md: width='fill' produces the container width", function()
        local container = H.Layout:CreateContainer({ parent = host, layout = "flow",
                                                    dir = "vertical" })
        local child = H.C.Frame({ w = 10, h = 20 }, container:GetFrame())
        container:Add(child, { width = "fill", height = 20 })
        H.expectSize(child, container:GetWidth(), nil)
    end)

    it("TESTING.md: H.runAnimations settles queued animations", function()
        local f = H.parent(10, 10)
        H.SuuUI.Anim.Presets.FadeIn(f, 0.2)
        H.runAnimations()
        expect(f:GetAlpha()).eq(1)
    end)

    it("UI_SIGNALS.md: the toggle signal spy example", function()
        local tog = H.C.Toggle({}, host)
        local spy = H.signalSpy(tog, H.S.SIGNALS.VALUE_CHANGED)
        H.click(tog)
        expect(spy:arg(1)).truthy()
        expect(spy:arg(2)).falsy()
        tog:SetValue(false)
        expect(spy.count).as("setters do not emit").eq(1)
    end)

    it("TESTING.md: disabled controls stop client input and hold internally", function()
        local btn = H.C.Button({ label = "Go" }, host)
        btn:SetEnabled(false)
        expect(H.click(btn)).falsy()
        expect(function() H.forceClick(btn) end).notThrows()
    end)
end)
