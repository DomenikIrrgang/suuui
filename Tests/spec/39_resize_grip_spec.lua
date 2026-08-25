local H = require("harness")

describe("Components.ResizeGrip", function()
    local host
    before_each(function()
        H.setup()
        host = H.parent(300, 200)
    end)

    -- The lattice is three diagonal runs of 1, 2 and 3 dots. Derived here rather than
    -- hardcoded so the expectations move with the tokens the component reads.
    local function lattice()
        local dot   = H.token("spaceXxs")
        local pitch = H.token("spaceXs")
        return dot, pitch, 2 * pitch + dot
    end

    describe("construction and defaults", function()
        it("falls back to the sizeIcon token when no size is given", function()
            local s = H.token("sizeIcon")
            H.expectSize(H.C.ResizeGrip({}, host), s, s)
        end)

        it("props.size pins both axes", function()
            H.expectSize(H.C.ResizeGrip({ size = 24 }, host), 24, 24)
        end)

        it("takes mouse input: it is the thing the user grabs", function()
            expect(H.C.ResizeGrip({}, host):GetFrame():IsMouseEnabled()).truthy()
        end)

        it("starts enabled and unhovered", function()
            local g = H.C.ResizeGrip({}, host)
            expect(g:IsEnabled()).truthy()
            expect(g._hovered).eq(false)
        end)
    end)

    describe("glyph geometry", function()
        it("draws three diagonal runs of one, two and three dots", function()
            expect(#H.C.ResizeGrip({}, host)._dots).eq(6)
        end)

        it("sizes each dot from the smallest spacing step", function()
            local g = H.mount(H.C.ResizeGrip({}, host))
            local dot = select(1, lattice())
            for i = 1, 6 do
                local b = H.box(g._dots[i])
                expect(b.width).as("dot " .. i .. " width").eq(dot)
                expect(b.height).as("dot " .. i .. " height").eq(dot)
            end
        end)

        it("keeps every dot inside the grip box", function()
            local g = H.mount(H.C.ResizeGrip({}, host))
            for i = 1, 6 do
                H.expectInside(g._dots[i], g:GetFrame())
            end
        end)

        it("centres the lattice in the box, so it stays balanced", function()
            local g = H.mount(H.C.ResizeGrip({}, host))
            local _, _, extent = lattice()
            local fb = H.box(g)
            local inset = math.floor((fb.width - extent) / 2)
            -- The corner dot is the first one placed: nearest the bottom-right. H.box is
            -- top-down, so the bottom inset is the frame's bottom minus the dot's.
            local d = H.box(g._dots[1])
            expect(fb.right - d.right).as("right inset").eq(inset)
            expect(fb.bottom - d.bottom).as("bottom inset").eq(inset)
        end)

        it("steps the dots by one pitch along each axis", function()
            local g = H.mount(H.C.ResizeGrip({}, host))
            local _, pitch = lattice()
            -- Row 0 runs right-to-left: dots 1, 2, 3 share a bottom edge one pitch apart.
            local d1, d2, d3 = H.box(g._dots[1]), H.box(g._dots[2]), H.box(g._dots[3])
            expect(d1.bottom).eq(d2.bottom)
            expect(d2.bottom).eq(d3.bottom)
            expect(d1.right - d2.right).eq(pitch)
            expect(d2.right - d3.right).eq(pitch)
            -- Dot 4 opens the next run: one pitch up, back at the corner column.
            local d4 = H.box(g._dots[4])
            expect(d4.right).eq(d1.right)
            expect(d1.bottom - d4.bottom).eq(pitch)
        end)

        it("runs the dots as true diagonals, parallel to the corner", function()
            local g = H.mount(H.C.ResizeGrip({}, host))
            local _, pitch = lattice()
            -- The longest run is the three dots furthest from the corner: 3, 5 and 6.
            -- A diagonal steps one pitch right for every pitch up, so consecutive dots
            -- differ by exactly one pitch on both axes.
            local a, b, c = H.box(g._dots[3]), H.box(g._dots[5]), H.box(g._dots[6])
            expect(b.right - a.right).as("5 right of 3").eq(pitch)
            expect(a.bottom - b.bottom).as("5 above 3").eq(pitch)
            expect(c.right - b.right).as("6 right of 5").eq(pitch)
            expect(b.bottom - c.bottom).as("6 above 5").eq(pitch)
            -- And the two-dot run behaves the same way, one step nearer the corner.
            local d2, d4 = H.box(g._dots[2]), H.box(g._dots[4])
            expect(d4.right - d2.right).eq(pitch)
            expect(d2.bottom - d4.bottom).eq(pitch)
        end)

        it("never lets two dots overlap", function()
            local g = H.mount(H.C.ResizeGrip({}, host))
            for i = 1, 6 do
                for j = i + 1, 6 do
                    H.expectNoOverlap({ g._dots[i], g._dots[j] })
                end
            end
        end)
    end)

    describe("colour", function()
        local function dotColor(g)
            return { g._dots[1]:GetColorTexture() }
        end

        it("paints the dots in the muted text token when idle", function()
            local g = H.C.ResizeGrip({}, host)
            local t = H.token("colorTextMuted")
            local c = dotColor(g)
            expect(c[1]).near(t[1], 0.001)
            expect(c[2]).near(t[2], 0.001)
            expect(c[3]).near(t[3], 0.001)
            expect(c[4]).near(t[4], 0.001)
        end)

        it("takes the accent token on hover and gives it back on leave", function()
            local g = H.mount(H.C.ResizeGrip({}, host))
            local muted, accent = H.token("colorTextMuted"), H.token("colorAccent")
            expect(H.hover(g)).truthy()
            expect(dotColor(g)[1]).near(accent[1], 0.001)
            H.unhover(g)
            expect(dotColor(g)[1]).near(muted[1], 0.001)
        end)

        it("paints every dot, not just the first", function()
            local g = H.mount(H.C.ResizeGrip({}, host))
            H.hover(g)
            local accent = H.token("colorAccent")
            for i = 1, 6 do
                local r = g._dots[i]:GetColorTexture()
                expect(r).as("dot " .. i).near(accent[1], 0.001)
            end
        end)
    end)

    describe("signals", function()
        it("reports a drag gesture instead of resizing anything itself", function()
            local g = H.mount(H.C.ResizeGrip({}, host))
            local RG = H.C.RESIZEGRIP_SIGNALS
            local down = H.signalSpy(g, RG.DRAG_START)
            local up   = H.signalSpy(g, RG.DRAG_STOP)
            expect(H.mouseDown(g)).truthy()
            expect(down.count).as("DRAG_START on press").eq(1)
            expect(up.count).as("no DRAG_STOP yet").eq(0)
            H.mouseUp(g)
            expect(up.count).as("DRAG_STOP on release").eq(1)
        end)

        it("emits MOUSE_ENTER and MOUSE_LEAVE", function()
            local g = H.mount(H.C.ResizeGrip({}, host))
            local enter = H.signalSpy(g, H.S.SIGNALS.MOUSE_ENTER)
            local leave = H.signalSpy(g, H.S.SIGNALS.MOUSE_LEAVE)
            H.hover(g)
            H.unhover(g)
            expect(enter.count).eq(1)
            expect(leave.count).eq(1)
        end)

        it("emits SIZE_CHANGED when a layout resizes it", function()
            local g = H.mount(H.C.ResizeGrip({}, host))
            local spy = H.signalSpy(g, H.S.SIGNALS.SIZE_CHANGED)
            g:GetFrame():SetSize(28, 28)
            expect(spy.count).gte(1)
            expect(spy:arg(1)).eq(28)
        end)

        it("re-places the lattice when a layout resizes it", function()
            local g = H.mount(H.C.ResizeGrip({}, host))
            g:GetFrame():SetSize(32, 32)
            local _, _, extent = lattice()
            local fb, d = H.box(g), H.box(g._dots[1])
            expect(fb.right - d.right).eq(math.floor((32 - extent) / 2))
            H.expectInside(g._dots[6], g:GetFrame())
        end)
    end)

    describe("disabled", function()
        it("fades the whole grip to opacityDisabled", function()
            local g = H.C.ResizeGrip({}, host)
            g:SetEnabled(false)
            expect(g:GetFrame():GetAlpha()).near(H.token("opacityDisabled"), 0.001)
        end)

        it("stops taking mouse input, so no gesture is reported", function()
            local g = H.mount(H.C.ResizeGrip({}, host))
            local spy = H.signalSpy(g, H.C.RESIZEGRIP_SIGNALS.DRAG_START)
            g:SetEnabled(false)
            expect(H.mouseDown(g)).as("the client stops routing input").falsy()
            H.forceClick(g)
            expect(spy.count).as("the component's own guard holds too").eq(0)
        end)

        it("re-asserts the fade on a live opacityDisabled edit", function()
            local g = H.C.ResizeGrip({}, host)
            g:SetEnabled(false)
            H.T:CreateUserTheme("Faded", "Modern")
            H.T:SetUserToken("Faded", "opacityDisabled", 0.2)
            H.T:SetActive("Faded")
            expect(g:GetFrame():GetAlpha()).near(0.2, 0.001)
        end)
    end)

    describe("theme reaction", function()
        it("regrows with the sizeIcon token", function()
            local g = H.mount(H.C.ResizeGrip({}, host))
            H.T:CreateUserTheme("BigIcon", "Modern")
            H.T:SetUserToken("BigIcon", "sizeIcon", 28)
            H.T:SetActive("BigIcon")
            H.expectSize(g, 28, 28)
            for i = 1, 6 do H.expectInside(g._dots[i], g:GetFrame()) end
        end)

        it("re-spaces the lattice with the spacing scale", function()
            local g = H.mount(H.C.ResizeGrip({ size = 32 }, host))
            H.T:CreateUserTheme("Wide", "Modern")
            H.T:SetUserToken("Wide", "spaceXs", 8)
            H.T:SetActive("Wide")
            local d1, d2 = H.box(g._dots[1]), H.box(g._dots[2])
            expect(d1.right - d2.right).eq(8)
        end)

        it("keeps a pinned size through a token change", function()
            local g = H.mount(H.C.ResizeGrip({ size = 24 }, host))
            H.T:CreateUserTheme("BigIcon2", "Modern")
            H.T:SetUserToken("BigIcon2", "sizeIcon", 40)
            H.T:SetActive("BigIcon2")
            H.expectSize(g, 24, 24)
        end)

        it("recolours on a token edit", function()
            local g = H.C.ResizeGrip({}, host)
            H.T:CreateUserTheme("Red", "Modern")
            H.T:SetUserToken("Red", "colorGray400", { 1, 0, 0, 1 })
            H.T:SetActive("Red")
            expect(g._dots[1]:GetColorTexture()).near(1, 0.001)
        end)
    end)

    describe("teardown", function()
        it("hides, disconnects and unsubscribes", function()
            local g = H.mount(H.C.ResizeGrip({}, host))
            local spy = H.signalSpy(g, H.S.SIGNALS.MOUSE_ENTER)
            g:Destroy()
            expect(g:IsShown()).falsy()
            expect(H.S:HasConnections(g, H.S.SIGNALS.MOUSE_ENTER)).falsy()
            expect(spy.count).eq(0)
        end)
    end)
end)
