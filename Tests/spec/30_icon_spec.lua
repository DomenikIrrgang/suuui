local H = require("harness")

describe("Components.Icon", function()
    local host
    before_each(function()
        H.setup()
        host = H.parent(300, 200)
    end)

    describe("construction and defaults", function()
        it("falls back to the sizeIcon token when no size is given", function()
            local icon = H.C.Icon({}, host)
            local s = H.token("sizeIcon")
            H.expectSize(icon, s, s)
        end)

        it("is square by default", function()
            local icon = H.C.Icon({}, host)
            expect(icon:GetWidth()).eq(icon:GetHeight())
        end)

        it("props.size pins both axes", function()
            local icon = H.C.Icon({ size = 24 }, host)
            H.expectSize(icon, 24, 24)
        end)

        it("props.w pins width only, height follows w (square)", function()
            local icon = H.C.Icon({ w = 20 }, host)
            H.expectSize(icon, 20, 20)
        end)

        it("props.h pins height, width follows size/token", function()
            local icon = H.C.Icon({ w = 30, h = 22 }, host)
            H.expectSize(icon, 30, 22)
        end)

        it("stores the icon path from props", function()
            local icon = H.C.Icon({ icon = "Interface\\Icons\\Spell_Fire" }, host)
            expect(icon:GetIcon()).eq("Interface\\Icons\\Spell_Fire")
        end)

        it("starts with nil icon when props.icon is omitted", function()
            local icon = H.C.Icon({}, host)
            expect(icon:GetIcon()).isNil()
        end)

        it("defaults border to false", function()
            local icon = H.C.Icon({}, host)
            expect(icon._border).eq(false)
        end)

        it("starts enabled", function()
            local icon = H.C.Icon({}, host)
            expect(icon:IsEnabled()).truthy()
        end)

        it("is display-only: mouse is never enabled", function()
            local icon = H.C.Icon({}, host)
            expect(icon:GetFrame():IsMouseEnabled()).falsy()
        end)
    end)

    describe("geometry", function()
        it("texture fills the frame when unbordered", function()
            local icon = H.mount(H.C.Icon({ icon = "x", size = 20 }, host))
            H.expectInside(icon._icon, icon:GetFrame())
            local ib = H.box(icon._icon)
            local fb = H.box(icon)
            expect(ib.width).eq(fb.width)
            expect(ib.height).eq(fb.height)
        end)

        it("texture is inset by borderWidth when border = true", function()
            local icon = H.mount(H.C.Icon({ icon = "x", size = 24, border = true }, host))
            local inset = H.SuuUI.Pixel.Line(H.token("borderWidth"))
            local fb = H.box(icon)
            local ib = H.box(icon._icon)
            expect(ib.left).near(fb.left + inset, 0.5)
            expect(ib.top).near(fb.top + inset, 0.5)
            expect(ib.width).near(fb.width - inset * 2, 0.5)
            expect(ib.height).near(fb.height - inset * 2, 0.5)
        end)

        it("texture stays inside the frame with border", function()
            local icon = H.mount(H.C.Icon({ icon = "x", size = 24, border = true }, host))
            H.expectInside(icon._icon, icon:GetFrame())
        end)
    end)

    describe("border", function()
        it("SetBorderColor recolours the border without hiding it", function()
            local icon = H.C.Icon({ icon = "x", size = 20, border = true }, host)
            icon:SetBorderColor("colorShield")
            H.expectTokenColor(H.borderColor(icon), "colorShield")
        end)

        it("SetBorderColor is a no-op on a borderless icon", function()
            local icon = H.C.Icon({ icon = "x", size = 20 }, host)
            expect(function() icon:SetBorderColor("colorShield") end).notThrows()
            expect(H.borderColor(icon)).as("still no backdrop at all").isNil()
        end)

        it("a borderColor prop is honoured at construction", function()
            local icon = H.C.Icon({ icon = "x", size = 20, border = true,
                                    borderColor = "colorShield" }, host)
            H.expectTokenColor(H.borderColor(icon), "colorShield")
        end)

        it("an overridden border colour survives a theme change", function()
            local icon = H.C.Icon({ icon = "x", size = 20, border = true }, host)
            icon:SetBorderColor("colorShield")
            H.T:CreateUserTheme("IconTheme", "Modern")
            H.T:SetActive("IconTheme")
            H.expectTokenColor(H.borderColor(icon), "colorShield")
        end)
    end)

    describe("border presence", function()
        it("border = true applies themed backdrop with correct border colour", function()
            local icon = H.C.Icon({ icon = "x", size = 20, border = true }, host)
            H.expectTokenColor(H.borderColor(icon), "colorBorder")
        end)

        it("border = false applies no backdrop", function()
            local icon = H.C.Icon({ icon = "x", size = 20, border = false }, host)
            -- No backdrop means no border colour
            expect(H.borderColor(icon)).isNil()
        end)

        it("default (no border prop) applies no backdrop", function()
            local icon = H.C.Icon({ icon = "x", size = 20 }, host)
            expect(H.borderColor(icon)).isNil()
        end)
    end)

    describe("trim", function()
        it("trim = true sets texture coordinates to crop the bevel", function()
            local icon = H.C.Icon({ icon = "x", size = 20, trim = true }, host)
            local l, r, t, b = icon._icon:GetTexCoord()
            expect(l).near(0.07, 0.001)
            expect(r).near(0.93, 0.001)
            expect(t).near(0.07, 0.001)
            expect(b).near(0.93, 0.001)
        end)

        it("without trim the tex coords are nil", function()
            local icon = H.C.Icon({ icon = "x", size = 20 }, host)
            local l = icon._icon:GetTexCoord()
            expect(l).isNil()
        end)
    end)

    describe("SetIcon / GetIcon", function()
        it("round-trips a texture path", function()
            local icon = H.C.Icon({}, host)
            icon:SetIcon("Interface\\Icons\\INV_Misc_Gem_01")
            expect(icon:GetIcon()).eq("Interface\\Icons\\INV_Misc_Gem_01")
        end)

        it("SetIcon(nil) clears the icon", function()
            local icon = H.C.Icon({ icon = "x" }, host)
            icon:SetIcon(nil)
            expect(icon:GetIcon()).isNil()
        end)

        it("GetIcon returns nil when never set", function()
            local icon = H.C.Icon({}, host)
            expect(icon:GetIcon()).isNil()
        end)
    end)

    describe("token-driven sizing", function()
        it("grows when sizeIcon token increases", function()
            local icon = H.C.Icon({}, host)
            local original = H.token("sizeIcon")
            H.T:CreateUserTheme("BigIcon", "Modern")
            H.T:SetUserToken("BigIcon", "sizeIcon", original + 10)
            H.T:SetActive("BigIcon")
            H.expectSize(icon, original + 10, original + 10)
        end)

        it("does not re-derive when props.size pinned it", function()
            local icon = H.C.Icon({ size = 20 }, host)
            H.T:CreateUserTheme("BigIcon", "Modern")
            H.T:SetUserToken("BigIcon", "sizeIcon", 40)
            H.T:SetActive("BigIcon")
            H.expectSize(icon, 20, 20)
        end)

        it("does not re-derive when props.w pinned it", function()
            local icon = H.C.Icon({ w = 18 }, host)
            H.T:CreateUserTheme("BigIcon", "Modern")
            H.T:SetUserToken("BigIcon", "sizeIcon", 40)
            H.T:SetActive("BigIcon")
            H.expectSize(icon, 18, 18)
        end)

        it("does not re-derive when props.h pinned it", function()
            local icon = H.C.Icon({ w = 22, h = 18 }, host)
            H.T:CreateUserTheme("BigIcon", "Modern")
            H.T:SetUserToken("BigIcon", "sizeIcon", 40)
            H.T:SetActive("BigIcon")
            H.expectSize(icon, 22, 18)
        end)
    end)

    describe("layout integration", function()
        it("reacts to being resized by a parent container", function()
            local icon = H.C.Icon({ icon = "x" }, host)
            local col = H.Layout:CreateContainer({
                host   = host,
                layout = "flow",
                dir    = "vertical",
                fill   = true,
            })
            col:Add(icon, { width = "fill", height = 30 })
            expect(icon:GetWidth()).near(300, 1)
            expect(icon:GetHeight()).near(30, 1)
        end)

        it("works as a horizontal flow child with width=n, height=fill (square result)", function()
            local containerH = 32
            local row = H.Layout:CreateContainer({
                parent = host,
                layout = "flow",
                dir    = "horizontal",
                w      = 200,
                h      = containerH,
            })
            local icon = H.C.Icon({ icon = "x" }, row:GetFrame())
            row:Add(icon, { width = containerH, height = "fill" })
            -- The icon should be square: width = containerH, height = containerH
            expect(icon:GetWidth()).near(containerH, 1)
            expect(icon:GetHeight()).near(containerH, 1)
        end)
    end)

    describe("signals", function()
        it("emits SIZE_CHANGED on a layout-driven resize", function()
            local icon = H.C.Icon({ icon = "x", size = 16 }, host)
            local spy = H.signalSpy(icon, H.S.SIGNALS.SIZE_CHANGED)
            local col = H.Layout:CreateContainer({
                host   = host,
                layout = "flow",
                dir    = "vertical",
                fill   = true,
            })
            col:Add(icon, { width = "fill", height = 40 })
            expect(spy.count).gte(1)
            expect(spy:arg(1)).near(300, 1)
            expect(spy:arg(2)).near(40, 1)
        end)

        it("emits SIZE_CHANGED from handle:SetSize", function()
            local icon = H.C.Icon({ icon = "x", size = 16 }, host)
            local spy = H.signalSpy(icon, H.S.SIGNALS.SIZE_CHANGED)
            icon:SetSize(32, 32)
            expect(spy.count).eq(1)
            expect(spy:arg(1)).eq(32)
            expect(spy:arg(2)).eq(32)
        end)

        it("emits VISIBILITY_CHANGED on Hide and Show", function()
            local icon = H.C.Icon({ icon = "x" }, host)
            local spy = H.signalSpy(icon, H.S.SIGNALS.VISIBILITY_CHANGED)
            icon:Hide()
            expect(spy.count).eq(1)
            expect(spy:arg(1)).eq(false)
            icon:Show()
            expect(spy.count).eq(2)
            expect(spy:arg(1, 2)).eq(true)
        end)

        it("emits ENABLED_CHANGED on SetEnabled", function()
            local icon = H.C.Icon({ icon = "x" }, host)
            local spy = H.signalSpy(icon, H.S.SIGNALS.ENABLED_CHANGED)
            icon:SetEnabled(false)
            expect(spy.count).eq(1)
            expect(spy:arg(1)).eq(false)
            icon:SetEnabled(true)
            expect(spy.count).eq(2)
            expect(spy:arg(1, 2)).eq(true)
        end)
    end)

    describe("disabled state", function()
        it("fades to opacityDisabled when disabled", function()
            local icon = H.C.Icon({ icon = "x" }, host)
            icon:SetEnabled(false)
            expect(icon:GetFrame():GetAlpha()).eq(H.token("opacityDisabled"))
        end)

        it("restores full alpha when re-enabled", function()
            local icon = H.C.Icon({ icon = "x" }, host)
            icon:SetEnabled(false)
            icon:SetEnabled(true)
            expect(icon:GetFrame():GetAlpha()).eq(1)
        end)

        it("ApplyTheme re-asserts the fade while already disabled", function()
            local icon = H.C.Icon({ icon = "x" }, host)
            icon:SetEnabled(false)
            H.T:CreateUserTheme("Dim", "Modern")
            H.T:SetUserToken("Dim", "opacityDisabled", 0.25)
            H.T:SetActive("Dim")
            expect(icon:GetFrame():GetAlpha()).eq(0.25)
        end)

        it("mouse is never enabled regardless of enabled state", function()
            local icon = H.C.Icon({ icon = "x" }, host)
            expect(icon:GetFrame():IsMouseEnabled()).falsy()
            icon:SetEnabled(false)
            expect(icon:GetFrame():IsMouseEnabled()).falsy()
            icon:SetEnabled(true)
            expect(icon:GetFrame():IsMouseEnabled()).falsy()
        end)
    end)

    describe("theme reaction", function()
        it("border colour follows the token on theme switch", function()
            local icon = H.C.Icon({ icon = "x", border = true }, host)
            H.T:CreateUserTheme("Custom", "Modern")
            H.T:SetUserToken("Custom", "colorGray700", { 1, 0, 0, 1 })
            H.T:SetActive("Custom")
            -- colorBorder aliases to colorGray700 so it should now be red
            H.expectTokenColor(H.borderColor(icon), "colorBorder")
            expect(H.borderColor(icon)[1]).eq(1)
        end)

        it("re-derives auto-sized icon on theme change", function()
            local icon = H.C.Icon({ icon = "x" }, host)
            H.T:CreateUserTheme("BigIcon", "Modern")
            H.T:SetUserToken("BigIcon", "sizeIcon", 32)
            H.T:SetActive("BigIcon")
            H.expectSize(icon, 32, 32)
        end)

        it("does not error on theme change after Destroy", function()
            local icon = H.C.Icon({ icon = "x" }, host)
            icon:Destroy()
            expect(function()
                H.T:CreateUserTheme("Post", "Modern")
                H.T:SetActive("Post")
            end).notThrows()
        end)
    end)

    describe("edge cases", function()
        it("survives with no props at all", function()
            local icon = H.C.Icon(nil, host)
            expect(icon).notNil()
            local s = H.token("sizeIcon")
            H.expectSize(icon, s, s)
        end)

        it("survives with empty props table", function()
            local icon = H.C.Icon({}, host)
            expect(icon).notNil()
            expect(icon:GetIcon()).isNil()
        end)

        it("handles zero size from props", function()
            local icon = H.C.Icon({ size = 0 }, host)
            H.expectSize(icon, 0, 0)
        end)

        it("handles negative size from props", function()
            local icon = H.C.Icon({ size = -5 }, host)
            -- Negative size is accepted as-is (no clamping)
            H.expectSize(icon, -5, -5)
        end)
    end)

    describe("teardown", function()
        it("Destroy hides the frame", function()
            local icon = H.C.Icon({ icon = "x" }, host)
            icon:Destroy()
            expect(icon:GetFrame():IsShown()).eq(false)
        end)

        it("signals are silent after Destroy", function()
            local icon = H.C.Icon({ icon = "x", size = 16 }, host)
            local spy = H.signalSpy(icon, H.S.SIGNALS.SIZE_CHANGED)
            icon:Destroy()
            spy:reset()
            icon:GetFrame():SetSize(50, 50)
            expect(spy.count).as("no signal after destroy").eq(0)
        end)

        it("theme change after Destroy does not restyle or error", function()
            local icon = H.C.Icon({ icon = "x", border = true }, host)
            icon:Destroy()
            expect(function()
                H.SuuUI.Events:Emit("SUUUI_THEME_CHANGED", "Default")
            end).notThrows()
        end)
    end)
end)

-- The bag grid's cells are rounded Icons. Opt-in for the same reason Frame's is: every aura and
-- action button in the addon is an Icon, and rounding all of them is a separate design decision.
describe("Components/Icon rounded", function()
    local host
    before_each(function()
        H.setup()
        host = H.mountHost and H.mountHost() or H.SuuUI.UIRoot:GetRootContainer():GetFrame()
    end)

    it("is square by default", function()
        local i = H.C.Icon({ border = true, size = 34 }, host)
        expect(i._panel).eq(nil)
    end)

    it("draws a rounded border when asked, and NEVER applies a backdrop as well", function()
        local i = H.C.Icon({ border = true, rounded = true, size = 34 }, host)
        expect(i._panel).as("a panel handle was built").truthy()
        -- See the Frame equivalent: GetBackdrop() is vacuous in the simulated client, so the call
        -- count is what discriminates and it pins the branch that actually matters.
        local calls, real = 0, H.SuuUI.Backdrop.Apply
        H.SuuUI.Backdrop.Apply = function(...) calls = calls + 1 return real(...) end
        i:ApplyTheme()
        H.SuuUI.Backdrop.Apply = real
        expect(calls).as("a rounded border must not also get a square backdrop").eq(0)
    end)

    it("still applies a backdrop for a square bordered icon", function()
        local i = H.C.Icon({ border = true, size = 34 }, host)
        local calls, real = 0, H.SuuUI.Backdrop.Apply
        H.SuuUI.Backdrop.Apply = function(...) calls = calls + 1 return real(...) end
        i:ApplyTheme()
        H.SuuUI.Backdrop.Apply = real
        expect(calls).as("the square path is the one that uses a backdrop").gte(1)
    end)

    -- There is nothing to round without a border, so the prop is inert rather than half-applied.
    it("ignores rounded on a borderless icon", function()
        local i = H.C.Icon({ rounded = true, size = 34 }, host)
        expect(i._panel).as("no border, nothing to round").eq(nil)
    end)

    it("still carries the quality edge colour through SetBorderColor", function()
        local i = H.C.Icon({ border = true, rounded = true, size = 34 }, host)
        i:SetBorderColor({ 0.64, 0.21, 0.93, 1 })
        expect(i._borderColor).truthy()
        expect(i._borderColor[3]).as("epic purple survived the rounding path").near(0.93, 0.01)
    end)

    -- THE ONE THAT MATTERS. Panel rounds the surface BEHIND the art, which a bag cell's icon covers
    -- edge to edge -- so without a mask on the art itself the cell renders hard square with the
    -- rounded surface correctly installed and invisible underneath it. Measured in game.
    it("masks the ART, not just the surface behind it", function()
        local i = H.C.Icon({ border = true, rounded = true, size = 34,
                             icon = "Interface\\Icons\\INV_Misc_Bag_08" }, host)
        expect(i._mask).as("a mask texture was created").truthy()
        -- ATTACHED, not merely created. The first version of this asserted a fallback expression that
        -- was truthy either way, and mutation testing caught it: deleting the AddMaskTexture call left
        -- the test green. The simulated client records attachments on the texture, so ask it.
        local masks = i._icon._masks or {}
        local found = false
        for _, m in ipairs(masks) do if m == i._mask then found = true end end
        expect(found).as("the mask is attached to the art texture").truthy()
    end)

    it("keeps the mask on the same inset as the art, so the rounding sits on the corner", function()
        local i = H.C.Icon({ border = true, rounded = true, size = 34 }, host)
        expect(i._maskProps).truthy()
        expect(i._maskProps.inset).as("mask follows the art's inset").eq(i._iconProps.inset)
    end)

    -- The ring and the art must share ONE curve. The mask is stretched, so its corner is a fraction
    -- of the frame; a ring on the absolute token disagreed with it, and whichever was shallower
    -- occluded the other -- which in game looked like the border missing at the corners.
    it("gives the ring the same proportional curve as the art mask", function()
        local i = H.C.Icon({ border = true, rounded = true, size = 40 }, host)
        expect(i._panel._radiusFrac).as("ring follows the mask's fraction").truthy()
        expect(i._panel._radius)
            .as("and resolves it against the frame").eq(H.SuuUI.Pixel.Floor(40 * i._panel._radiusFrac))
    end)

    it("re-derives the ring's curve when the icon is resized", function()
        local i = H.C.Icon({ border = true, rounded = true, size = 40 }, host)
        local before = i._panel._radius
        i:SetSize(80, 80)
        expect(i._panel._radius).as("a proportional corner grows with the cell").gt(before)
    end)

    it("lets an explicit radius override the proportional curve", function()
        local i = H.C.Icon({ border = true, rounded = true, size = 40, radius = 2 }, host)
        expect(i._panel._radiusFrac).as("explicit wins").eq(nil)
        expect(i._panel._radius).eq(2)
    end)

    -- PRECEDENCE, and it is not cosmetic: trim crops the bevel Blizzard bakes into its own icon
    -- FILES, an atlas of ours has no bevel, and applying both would crop a glyph to a quarter of
    -- itself -- so the glyph would render as a slice of the wrong picture. Documented in SetIcon and
    -- untested until mutation testing pointed out that swapping the branches changed nothing.
    it("lets atlas coords override trim rather than compounding with it", function()
        local coords = { 0, 0.5, 0, 0.5 }
        local i = H.C.Icon({ icon = "x", trim = true, coords = coords, size = 32 }, host)
        local l, r, t2, b = i._icon:GetTexCoord()
        expect(l).as("left is the atlas coord, not the trim").near(coords[1], 0.0001)
        expect(r).as("right is the atlas coord").near(coords[2], 0.0001)
        expect(t2).near(coords[3], 0.0001)
        expect(b).near(coords[4], 0.0001)
    end)

    it("still trims when no coords are given", function()
        local i = H.C.Icon({ icon = "x", trim = true, size = 32 }, host)
        local l = i._icon:GetTexCoord()
        expect(l).as("the bevel is cropped").gt(0)
    end)

    it("does not create a mask for a square icon", function()
        local i = H.C.Icon({ border = true, size = 34 }, host)
        expect(i._mask).as("nothing to mask when the corners are square").eq(nil)
    end)

    it("frees the panel on Destroy", function()
        local i = H.C.Icon({ border = true, rounded = true, size = 34 }, host)
        i:Destroy()
        expect(i:IsShown()).falsy()
    end)
end)
