-- Chip and Avatar: the two atoms the chat rail and input bar are built from.
local H = require("harness")

describe("Chip", function()
    before_each(function() H.setup() end)

    local GUILD = { 0.25, 1, 0.25, 1 }

    local function make(props)
        return H.mount(H.C.Chip(props or {}, H.parent(200, 40)))
    end

    describe("construction", function()
        it("renders the text it was given, in the case it was given", function()
            local chip = make({ text = "Guild" })
            expect(chip:GetText())
                .as("WoW has no text-transform, so case is the caller's choice").eq("Guild")
        end)

        it("hugs its own text plus padding", function()
            local narrow = make({ text = "G" })
            local wide   = make({ text = "→ Sylvaine" })
            expect(H.box(wide).width).gt(H.box(narrow).width)
        end)

        it("takes its height from a token, floored by the font", function()
            local chip = make({ text = "Say" })
            expect(H.box(chip).height).eq(H.controlHeight("sizeControlSm", "sm"))
        end)

        it("re-hugs on a text change and says so", function()
            local chip = make({ text = "G" })
            local spy = H.signalSpy(chip, H.S.SIGNALS.TEXT_CHANGED)
            local before = H.box(chip).width
            chip:SetText("→ Sylvaine")
            expect(H.box(chip).width).gt(before)
            expect(spy.count).eq(1)
        end)

        it("drops an unchanged SetText", function()
            local chip = make({ text = "Say" })
            local spy = H.signalSpy(chip, H.S.SIGNALS.TEXT_CHANGED)
            chip:SetText("Say")
            expect(spy.count).as("a resting chip is rewritten on every channel poll").eq(0)
        end)

        it("does not clip its own label", function()
            local chip = make({ text = "→ Sylvaine" })
            H.expectTextNotClipped(chip._label)
        end)
    end)

    describe("colour", function()
        it("takes a LITERAL colour, because a channel's colour is a game fact", function()
            local chip = make({ text = "Guild", color = GUILD })
            local r, g, b = chip._label:GetTextColor()
            expect(r).near(GUILD[1], 0.01)
            expect(g).near(GUILD[2], 0.01)
            expect(b).near(GUILD[3], 0.01)
        end)

        it("also takes a token key", function()
            local chip = make({ text = "Say", color = "colorAccent" })
            local accent = H.token("colorAccent")
            local r = chip._label:GetTextColor()
            expect(r).near(accent[1], 0.01)
        end)

        it("tints its surface with its own colour at the chip wash", function()
            local chip = make({ text = "Guild", color = GUILD })
            -- The surface is a NEUTRAL panel colour; only the ring and the label carry the channel.
            -- Read off the frame's own BACKDROP: the chip is square now, so there is no pill whose
            -- internals to reach into -- and a backdrop is what the concept's zero border radius asks
            -- for anyway.
            local bg = H.token("colorBg")
            local br, bg2, bb = chip._f:GetBackdropColor()
            expect(br).as("the chip surface is colorBg, not the channel colour").near(bg[1], 0.02)
            expect(bg2).near(bg[2], 0.02)
            expect(bb).near(bg[3], 0.02)
        end)

        it("does NOT wash its surface with the channel colour", function()
            -- The regression guard for a bug found by looking at the game. Say's ChatTypeInfo
            -- colour is pure WHITE, and a wash of it renders a light grey pill that reads as a
            -- BUTTON rather than a label -- over the game world, with no panel behind it.
            local white = { 1, 1, 1, 1 }
            local chip = make({ text = "Say", color = white })
            local r, g, b = chip._f:GetBackdropColor()
            expect(r + g + b)
                .as("a white channel must not produce a pale surface")
                .lt(1.5)
            -- The channel is still legible, through the ring and the label rather than the fill.
            local lr, lg, lb = chip._label:GetTextColor()
            expect(lr + lg + lb).as("the label carries the channel colour").gt(2.5)
        end)

        it("rings itself in the channel colour, which is the signal that survives", function()
            local chip = make({ text = "Guild", color = GUILD })
            local _, g = chip._f:GetBackdropBorderColor()
            expect(g).as("the ring is the channel's own colour").near(GUILD[2], 0.02)
            expect(H.token("opacityChipBorder"))
                .as("the ring carries the chip over bright terrain").gt(0)
        end)

        it("SetColor repaints", function()
            local chip = make({ text = "x", color = { 1, 0, 0, 1 } })
            chip:SetColor({ 0, 0, 1, 1 })
            local r, _, b = chip._label:GetTextColor()
            expect(r).near(0, 0.01)
            expect(b).near(1, 0.01)
        end)
    end)

    describe("variant", function()
        it("has NO outline variant, because Pill cannot draw one", function()
            -- This replaces three tests that passed while asserting a lie. `Backdrop.Pill` fakes
            -- its ring by drawing a SOLID border-coloured pill on BACKGROUND and covering the
            -- middle with the bg on BORDER, so a transparent bg does not hollow the ring -- it
            -- reveals the whole border pill. `outline` rendered as the DENSEST chip available.
            --
            -- The old spec could not catch that: it asserted the fill layer's alpha was 0, which
            -- was true, rather than what the player sees. A weak assertion, in the exact shape
            -- TESTING.md warns about.
            local chip = make({ text = "x" })
            expect(chip.GetVariant).as("the variant is gone, not merely unused").eq(nil)
            expect(chip.SetVariant).eq(nil)
        end)

        it("draws a REAL border, so no fill opacity is load-bearing", function()
            -- This replaces an assertion about the Pill's fake ring: it drew a solid
            -- border-coloured pill and covered the middle, so the fill HAD to be opaque enough to
            -- hide it or the ring collapsed into a solid shape. A square backdrop has an actual
            -- edge, so that whole coupling is gone -- which is the simplification squaring bought.
            local chip = make({ text = "x", color = GUILD })
            local _, _, _, ringA = chip._f:GetBackdropBorderColor()
            expect(ringA).as("the ring carries the chip's alpha directly")
                .near(H.token("opacityChipBorder"), 0.02)
        end)
    end)

    describe("theme reaction", function()
        it("re-hugs when the font token grows", function()
            local chip = make({ text = "Guild" })
            local before = H.box(chip).width
            H.T:CreateUserTheme("Big", "Modern")
            H.T:SetUserToken("Big", "fontSizeSm", 22)
            H.T:SetActive("Big")
            expect(H.box(chip).width).gt(before)
        end)

        it("keeps a literal colour across a theme change", function()
            local chip = make({ text = "Guild", color = GUILD })
            H.fireEvent("SUUUI_THEME_CHANGED")
            local _, g = chip._label:GetTextColor()
            expect(g).as("a game fact must survive a retint").near(GUILD[2], 0.01)
        end)
    end)

    describe("teardown", function()
        it("hides and disconnects", function()
            local chip = make({ text = "x" })
            chip:Destroy()
            expect(chip:IsShown()).eq(false)
            expect(function() H.fireEvent("SUUUI_THEME_CHANGED") end).notThrows()
        end)
    end)
end)

describe("Avatar", function()
    before_each(function() H.setup() end)

    local PALADIN = { 0.96, 0.55, 0.73, 1 }

    local function make(props)
        return H.mount(H.C.Avatar(props or {}, H.parent(200, 40)))
    end

    describe("the disc", function()
        it("derives its initial from the label", function()
            local a = make({ label = "Sylvaine" })
            expect(a._initialText:GetText()).eq("S")
        end)

        it("uppercases a lowercase name", function()
            expect(make({ label = "sylvaine" })._initialText:GetText()).eq("S")
        end)

        it("takes a pinned glyph, for a channel that is not a name", function()
            local a = make({ label = "General", initial = "#" })
            expect(a._initialText:GetText())
                .as("a channel shows # rather than G").eq("#")
        end)

        it("keeps a pinned glyph when the label changes", function()
            local a = make({ label = "General", initial = "#" })
            a:SetLabel("Trade")
            expect(a._initialText:GetText()).eq("#")
        end)

        it("re-derives an unpinned initial when the label changes", function()
            local a = make({ label = "Sylvaine" })
            a:SetLabel("Brakkus")
            expect(a._initialText:GetText()).eq("B")
        end)

        it("takes a class colour as a literal", function()
            local a = make({ label = "Sylvaine", color = PALADIN })
            expect(a._color).deepEq(PALADIN)
        end)

        it("inks the glyph with the darkest neutral, not the text token", function()
            local a = make({ label = "Sylvaine", color = PALADIN })
            local ink = H.token("colorGray950")
            local r, g, b = a._initialText:GetFrame():GetTextColor()
            expect(r).as("colorText on Rogue yellow is illegible").near(ink[1], 0.02)
            expect(g).near(ink[2], 0.02)
            expect(b).near(ink[3], 0.02)
        end)
    end)

    describe("the unread badge", function()
        it("is hidden with no count", function()
            expect(make({ label = "S" })._badge:IsShown()).eq(false)
        end)

        it("is hidden at zero, not shown reading 0", function()
            local a = make({ label = "S", count = 0 })
            expect(a:GetCount()).eq(nil)
            expect(a._badge:IsShown())
                .as("the client reports 0 for plenty of things; a 0 badge on every entry is noise")
                .eq(false)
        end)

        it("shows the number when there is one", function()
            local a = make({ label = "S", count = 2 })
            expect(a:GetCount()).eq(2)
            expect(a._badge:IsShown()).eq(true)
            expect(a._badgeText:GetText()).eq("2")
        end)

        it("hides again when the conversation is read", function()
            local a = make({ label = "S", count = 3 })
            a:SetCount(nil)
            expect(a._badge:IsShown()).eq(false)
        end)

        it("rides the disc, so it does not drift when the label appears", function()
            local a = make({ label = "Sylvaine", count = 2 })
            expect(a._badge:GetParent()).eq(a._discFrame)
        end)

        it("stays within the row's bounds", function()
            local a = make({ label = "Sylvaine", count = 9 })
            H.expectTextNotClipped(a._badgeText:GetFrame())
        end)
    end)

    describe("active state", function()
        it("defaults to inactive with a muted name", function()
            local a = make({ label = "Sylvaine" })
            expect(a:IsActive()).eq(false)
            local r = a._labelText:GetFrame():GetTextColor()
            expect(r).near(H.token("colorTextMuted")[1], 0.02)
        end)

        it("brightens the name when active", function()
            local a = make({ label = "Sylvaine", active = true })
            expect(a:IsActive()).eq(true)
            local r = a._labelText:GetFrame():GetTextColor()
            expect(r).near(H.token("colorText")[1], 0.02)
        end)

        it("does NOT dim the class disc", function()
            -- A dimmed class colour reads as a different class, so the cue is the label.
            local a = make({ label = "Sylvaine", color = PALADIN, active = false })
            expect(a._discFrame:GetAlpha()).near(1, 0.001)
        end)

        it("flips at runtime", function()
            local a = make({ label = "S" })
            a:SetActive(true)
            expect(a:IsActive()).eq(true)
            a:SetActive(false)
            expect(a:IsActive()).eq(false)
        end)
    end)

    describe("collapsed and expanded", function()
        it("HIDES the label when asked, for the collapsed rail", function()
            -- It is created either way now, because the rail toggles it on hover and a
            -- construction-time branch could not. Hidden is what collapses the row: flow skips a
            -- hidden child, so the width falls back to the marker plus the disc.
            local av = H.mount(H.C.Avatar({ initial = "S", label = "Sylvaine",
                                            showLabel = false }, H.parent(120, 30)))
            expect(av._labelText).as("the handle keeps it").notNil()
            expect(av:IsShowingLabel()).as("but it is not shown").falsy()
        end)

        it("shows and hides the label at runtime", function()
            local av = H.mount(H.C.Avatar({ initial = "S", label = "Sylvaine",
                                            showLabel = false }, H.parent(120, 30)))
            local collapsed = av:GetWidth()
            av:SetShowLabel(true)
            expect(av:IsShowingLabel()).truthy()
            expect(av:GetWidth()).as("the row widens to the name").gt(collapsed)
            av:SetShowLabel(false)
            expect(av:GetWidth()).as("and collapses back").eq(collapsed)
        end)

        it("shadows its label, because the rail overlays the log", function()
            -- The expanded rail draws over chat text rather than pushing it, so the name is read
            -- against terrain and messages. The concept gives `.lbl` a text-shadow for this.
            local av = H.mount(H.C.Avatar({ initial = "S", label = "Sylvaine" },
                                          H.parent(140, 30)))
            local _, _, _, a = av._labelText:GetFrame():GetShadowColor()
            expect(a).near(H.token("opacityTextShadow"), 0.01)
        end)

        it("reserves the marker column even when inactive", function()
            -- Otherwise every row shifts sideways by 2 units the moment it becomes active.
            local off = H.mount(H.C.Avatar({ initial = "A", showLabel = false }, H.parent(80, 30)))
            local on  = H.mount(H.C.Avatar({ initial = "A", showLabel = false,
                                             active = true }, H.parent(80, 30)))
            expect(off:GetWidth()).eq(on:GetWidth())
            -- And an ABSOLUTE width, because comparing the two cannot see a column missing from
            -- both -- which is exactly the mutation that survived the relative assertion.
            expect(off:GetWidth())
                .as("2px marker + gap + disc")
                .near(H.SuuUI.Pixel.Line(2) + H.token("spaceXs") + H.token("sizeControlSm"), 0.5)
        end)

        it("paints the marker only on the active row", function()
            local off = H.mount(H.C.Avatar({ initial = "A", showLabel = false }, H.parent(80, 30)))
            local on  = H.mount(H.C.Avatar({ initial = "A", showLabel = false,
                                             active = true }, H.parent(80, 30)))
            local _, _, _, offA = off._marker:GetVertexColor()
            local ar, ag, ab, onA = on._marker:GetVertexColor()
            expect(offA).as("transparent at rest, so a row reads as one shape").near(0, 0.01)
            expect(onA).near(1, 0.01)
            local accent = H.token("colorAccent")
            expect(ar).near(accent[1], 0.02)
            expect(ag).near(accent[2], 0.02)
            expect(ab).near(accent[3], 0.02)
        end)

        it("is narrower collapsed than expanded", function()
            local collapsed = make({ label = "Sylvaine", showLabel = false })
            local expanded  = make({ label = "Sylvaine" })
            expect(H.box(collapsed).width).lt(H.box(expanded).width)
        end)
    end)

    describe("input", function()
        it("emits CLICKED with the button", function()
            local a = make({ label = "S" })
            local spy = H.signalSpy(a, H.S.SIGNALS.CLICKED)
            H.click(a)
            expect(spy.count).eq(1)
        end)

        it("emits hover in and out", function()
            local a = make({ label = "S" })
            local enter = H.signalSpy(a, H.S.SIGNALS.MOUSE_ENTER)
            local leave = H.signalSpy(a, H.S.SIGNALS.MOUSE_LEAVE)
            a:GetFrame():GetScript("OnEnter")(a:GetFrame())
            a:GetFrame():GetScript("OnLeave")(a:GetFrame())
            expect(enter.count).eq(1)
            expect(leave.count).eq(1)
        end)

        it("refuses the click when disabled", function()
            local a = make({ label = "S" })
            local spy = H.signalSpy(a, H.S.SIGNALS.CLICKED)
            a:SetEnabled(false)
            a:GetFrame():GetScript("OnMouseUp")(a:GetFrame(), "LeftButton")
            expect(spy.count).as("the internal guard holds, not just the client's routing").eq(0)
        end)
    end)

    describe("teardown", function()
        it("hides and disconnects", function()
            local a = make({ label = "S", count = 2 })
            a:Destroy()
            expect(a:IsShown()).eq(false)
            expect(function() H.fireEvent("SUUUI_THEME_CHANGED") end).notThrows()
        end)
    end)
end)
