local H = require("harness")

-- AuraIcon is the only component that composes three sub-handles (an Icon, and two Texts
-- in an overlay frame) over a Blizzard Cooldown. Three things about it are load-bearing and
-- none is visible from its surface: the count readout hides at 1 AND at 0 because the live
-- client reports 0 for a non-stacking aura; the duration text carries a colour OVERRIDE
-- below five seconds, so the path that rots is the one that gives the colour back; and the
-- nested handles all opt out of the disabled fade, because the root frame fades the whole
-- thing and a second fade would multiply.
describe("Components.AuraIcon", function()
    local host
    before_each(function()
        H.setup()
        host = H.parent(300, 200)
    end)

    -- Every geometry assertion needs the handle mounted: a component built and never added
    -- to a container has no anchors, so H.box inside it returns nil.
    local function icon(props)
        return H.mount(H.C.AuraIcon(props or {}, host))
    end

    -- The container shape AuraBand really uses, so "the parent resized it" means the same
    -- thing here as it does in the plugin: a wrapping horizontal flow that pins each icon
    -- to the band's icon-size setting.
    local function band()
        return H.Layout:CreateContainer({
            parent = host, layout = "flow", dir = "horizontal",
            wrap = true, gap = H.token("spaceXxs"),
        })
    end

    -- Comfortably larger than sizeIcon so both readouts fit: the crowding a small icon
    -- produces is its own section below, and mixing it into every geometry assertion would
    -- hide whichever failure came second.
    local ROOMY = 48

    ---------------------------------------------------------------------------
    -- 1. Construction and defaults
    ---------------------------------------------------------------------------
    describe("construction and defaults", function()
        it("falls back to the sizeIcon token when no size is given", function()
            local s = H.token("sizeIcon")
            H.expectSize(H.C.AuraIcon({}, host), s, s)
        end)

        it("props.size pins both axes", function()
            H.expectSize(H.C.AuraIcon({ size = 28 }, host), 28, 28)
        end)

        it("shows the icon it was given, and nothing when it was given none", function()
            expect(H.C.AuraIcon({ icon = "Interface\\Icons\\Spell_Fire_FlameBolt" },
                                host):GetIcon()).eq("Interface\\Icons\\Spell_Fire_FlameBolt")
            expect(H.C.AuraIcon({}, host):GetIcon()).isNil()
        end)

        it("crops the baked bevel by default, and leaves the art alone when told not to", function()
            local l, r, t, b = H.C.AuraIcon({ icon = "x" }, host)._iconComp._icon:GetTexCoord()
            expect(l).as("left crop").gt(0)
            expect(r).lt(1)
            expect(t).gt(0)
            expect(b).lt(1)
            expect(H.C.AuraIcon({ icon = "x", trim = false }, host)._iconComp._icon:GetTexCoord())
                .as("trim = false leaves the file uncropped").isNil()
        end)

        it("shows a count above one and hides one that was never given", function()
            local a = H.C.AuraIcon({ count = 3 }, host)
            expect(a._countText:IsShown()).truthy()
            expect(a._countText:GetText()).eq("3")
            expect(H.C.AuraIcon({}, host)._countText:IsShown()).falsy()
        end)

        it("arms the swipe from duration and expirationTime given at construction", function()
            local a = H.C.AuraIcon({ duration = 20, expirationTime = 100 }, host)
            local start, dur = a._cooldown:GetCooldownTimes()
            expect(start).as("start is the expiry minus the duration").eq(80)
            expect(dur).eq(20)
        end)

        it("leaves the swipe unarmed when neither is given", function()
            local start, dur = H.C.AuraIcon({}, host)._cooldown:GetCooldownTimes()
            expect(start).eq(0)
            expect(dur).eq(0)
        end)

        it("shows the duration readout by default and honours showDuration = false", function()
            local on = H.C.AuraIcon({}, host)
            on:SetTimeLeft(30)
            expect(on._durationText:IsShown()).as("default is on").truthy()

            local off = H.C.AuraIcon({ showDuration = false }, host)
            off:SetTimeLeft(30)
            expect(off._durationText:IsShown()).as("showDuration = false").falsy()
        end)

        it("tints the border from typeColor at construction, or leaves it on the neutral ring", function()
            local tint = { 0.20, 0.60, 1.00, 1 }
            expect(H.borderColor(H.C.AuraIcon({ typeColor = tint }, host)._iconComp))
                .deepEq(tint)
            H.expectTokenColor(H.borderColor(H.C.AuraIcon({}, host)._iconComp), "colorBorderIcon")
        end)

        it("takes mouse input: the tooltip and the cancel click both need it", function()
            expect(H.C.AuraIcon({}, host):GetFrame():IsMouseEnabled()).truthy()
        end)

        it("suppresses the Cooldown's own countdown number", function()
            -- Otherwise the client draws its number over our duration readout.
            expect(H.C.AuraIcon({}, host)._cooldown._hideNumbers)
                .as("SetHideCountdownNumbers was called").eq(true)
        end)

        it("starts enabled", function()
            expect(H.C.AuraIcon({}, host):IsEnabled()).truthy()
        end)
    end)

    ---------------------------------------------------------------------------
    -- 2. Geometry
    ---------------------------------------------------------------------------
    describe("geometry", function()
        it("stretches the icon, the cooldown and the text overlay over the whole frame", function()
            local a = icon({ icon = "x", size = ROOMY })
            local fb = H.box(a)
            -- The icon and the overlay span the whole frame; the cooldown is deliberately
            -- inset by the border width so its swipe stops at the art and leaves the border
            -- ring alone. See "insets the swipe by the border width" below.
            for name, part in pairs({ icon = a._iconComp, overlay = a._overlay }) do
                local b = H.box(part)
                expect(b.width).as(name .. " width").eq(fb.width)
                expect(b.height).as(name .. " height").eq(fb.height)
                expect(b.left).as(name .. " left").eq(fb.left)
                expect(b.top).as(name .. " top").eq(fb.top)
            end
            local cb, bw = H.box(a._cooldown), H.token("borderWidth")
            expect(cb.width).as("cooldown width").eq(fb.width - bw * 2)
            expect(cb.left).as("cooldown left").eq(fb.left + bw)
        end)

        it("keeps every part inside the frame", function()
            local a = icon({ icon = "x", size = ROOMY, count = 9 })
            a:SetTimeLeft(45)
            for _, part in ipairs({ a._iconComp, a._cooldown, a._overlay,
                                    a._countText, a._durationText }) do
                H.expectInside(part, a:GetFrame())
            end
        end)

        it("insets the stack count off the bottom-right corner by one spacing step", function()
            local a = icon({ icon = "x", size = ROOMY, count = 9 })
            local pad = H.token("spaceXxs")
            local fb, cb = H.box(a), H.box(a._countText)
            expect(fb.right - cb.right).as("right inset").eq(pad)
            expect(fb.bottom - cb.bottom).as("bottom inset").eq(pad)
        end)

        it("centres the duration readout on the icon, both axes", function()
            local a = icon({ icon = "x", size = ROOMY })
            a:SetTimeLeft(45)
            H.expectCenteredH(a._durationText, a:GetFrame())
            H.expectCenteredV(a._durationText, a:GetFrame())
        end)

        it("draws the text overlay above both the icon art and the swipe", function()
            -- The reason the readouts live in a child frame at all: a font string parented
            -- to the root would sit BEHIND the cooldown's own layers.
            local a = icon({ icon = "x", size = ROOMY })
            H.expectDrawsAbove(a._overlay, a._cooldown)
            H.expectDrawsAbove(a._overlay, a._iconComp)
        end)

        it("insets the swipe by the border width so it never covers the border ring", function()
            -- A child frame draws above every layer of its parent, the backdrop border
            -- included, so a full-bleed cooldown paints over the one pixel the dispel colour
            -- is carried on. Measured in game as: icon frame level 6, cooldown level 7,
            -- cooldown width equal to the whole icon -- the ring was covered at every size.
            local a = icon({ icon = "x", size = ROOMY })
            local bw = H.token("borderWidth")
            local fb, cb = H.box(a), H.box(a._cooldown)
            expect(cb.left - fb.left).as("left").eq(bw)
            expect(fb.right - cb.right).as("right").eq(bw)
            expect(cb.top - fb.top).as("top").eq(bw)
            expect(fb.bottom - cb.bottom).as("bottom").eq(bw)
        end)

        it("keeps the swipe inset when the border width token changes", function()
            local a = icon({ icon = "x", size = ROOMY })
            H.T:CreateUserTheme("ThickEdge", "Modern")
            H.T:SetUserToken("ThickEdge", "borderWidth", 3)
            H.T:SetActive("ThickEdge")
            local fb, cb = H.box(a), H.box(a._cooldown)
            expect(cb.left - fb.left).as("re-derived from the token").eq(H.token("borderWidth"))
        end)

        it("gives both readouts a box big enough to render in", function()
            local a = icon({ icon = "x", size = ROOMY, count = 12 })
            a:SetTimeLeft(1800)
            H.expectTextNotClipped(a._countText)
            H.expectTextNotClipped(a._durationText)
        end)
    end)

    ---------------------------------------------------------------------------
    -- 3. Token-driven sizing
    ---------------------------------------------------------------------------
    describe("token-driven sizing", function()
        it("regrows with the sizeIcon token and carries every part with it", function()
            local a = icon({ icon = "x", count = 12 })
            a:SetTimeLeft(1800)
            H.T:CreateUserTheme("BigIcon", "Modern")
            H.T:SetUserToken("BigIcon", "sizeIcon", 56)
            H.T:SetActive("BigIcon")

            H.expectSize(a, 56, 56)
            H.expectSize(a._iconComp, 56, 56)
            H.expectSize(a._cooldown, 56 - H.token("borderWidth") * 2,
                                       56 - H.token("borderWidth") * 2)
            for _, part in ipairs({ a._countText, a._durationText }) do
                H.expectInside(part, a:GetFrame())
            end
        end)

        it("re-derives the readouts when the small font step grows, instead of clipping", function()
            local a = icon({ icon = "x", size = ROOMY, count = 12 })
            a:SetTimeLeft(1800)
            local before = H.box(a._durationText).height

            H.T:CreateUserTheme("BigText", "Modern")
            H.T:SetUserToken("BigText", "fontSizeSm", 20)
            H.T:SetActive("BigText")

            expect(H.box(a._durationText).height).as("readout follows the font step").gt(before)
            H.expectTextNotClipped(a._durationText)
            H.expectTextNotClipped(a._countText)
        end)

        it("grows on both tokens at once and still renders both readouts uncut", function()
            local a = icon({ icon = "x", count = 12 })
            a:SetTimeLeft(1800)
            H.T:CreateUserTheme("BigBoth", "Modern")
            H.T:SetUserToken("BigBoth", "sizeIcon", 64)
            H.T:SetUserToken("BigBoth", "fontSizeSm", 22)
            H.T:SetActive("BigBoth")

            H.expectSize(a, 64, 64)
            H.expectTextNotClipped(a._countText)
            H.expectTextNotClipped(a._durationText)
            H.expectInside(a._countText, a:GetFrame())
            H.expectInside(a._durationText, a:GetFrame())
        end)
    end)

    ---------------------------------------------------------------------------
    -- 4. Layout integration
    ---------------------------------------------------------------------------
    describe("layout integration", function()
        it("takes the size the band gives it, not the token", function()
            local b, a = band(), H.C.AuraIcon({ icon = "x", size = 24 }, host)
            b:Add(a, { width = 24, height = 24 })
            H.expectSize(a, 24, 24)
        end)

        it("reacts when the PARENT resizes it, which never calls the handle's SetSize", function()
            local b, a = band(), H.C.AuraIcon({ icon = "x", size = 24, count = 7 }, host)
            b:Add(a, { width = 24, height = 24 })
            a:SetTimeLeft(45)
            local spy = H.signalSpy(a, H.S.SIGNALS.SIZE_CHANGED)

            b:SetChildProps(a, { width = 40, height = 40 })

            expect(spy.count).as("the resize is announced").gte(1)
            expect(spy:arg(1)).eq(40)
            expect(spy:arg(2)).eq(40)
            H.expectSize(a, 40, 40)
            H.expectSize(a._iconComp, 40, 40)
            H.expectSize(a._cooldown, 40 - H.token("borderWidth") * 2,
                                       40 - H.token("borderWidth") * 2)
            for _, part in ipairs({ a._countText, a._durationText }) do
                H.expectInside(part, a:GetFrame())
            end
        end)

        it("keeps a band-pinned size through a sizeIcon token change", function()
            -- The band passes an explicit size, which is what stops the token reclaiming it.
            local b, a = band(), H.C.AuraIcon({ icon = "x", size = 24 }, host)
            b:Add(a, { width = 24, height = 24 })
            H.T:CreateUserTheme("Pinned", "Modern")
            H.T:SetUserToken("Pinned", "sizeIcon", 44)
            H.T:SetActive("Pinned")
            H.expectSize(a, 24, 24)
        end)

        it("rows up next to a sibling in the band, separated by the gap", function()
            local b = band()
            local one = H.C.AuraIcon({ icon = "x", size = 24 }, host)
            local two = H.C.AuraIcon({ icon = "y", size = 24 }, host)
            b:Add(one, { width = 24, height = 24 })
            b:Add(two, { width = 24, height = 24 })
            H.expectRowHorizontally({ one, two }, H.token("spaceXxs"))
        end)
    end)

    ---------------------------------------------------------------------------
    -- 5. Stack count
    --
    -- The live client answers count = 0 for a non-stacking aura, so 0 and 1 are the same
    -- statement — "there is only one of these" — and >1 is the visibility threshold.
    ---------------------------------------------------------------------------
    describe("stack count", function()
        it("hides at 0 and at 1, shows from 2 up", function()
            local a = icon({ icon = "x", size = ROOMY })
            a:SetCount(0)
            expect(a._countText:IsShown()).as("0: a non-stacking aura").falsy()
            a:SetCount(1)
            expect(a._countText:IsShown()).as("1: one application").falsy()
            a:SetCount(2)
            expect(a._countText:IsShown()).as("2: a real stack").truthy()
            expect(a._countText:GetText()).eq("2")
        end)

        it("hides again when a stack falls back to one", function()
            local a = icon({ icon = "x", size = ROOMY, count = 5 })
            expect(a._countText:IsShown()).truthy()
            a:SetCount(1)
            expect(a._countText:IsShown()).as("the readout has to go away again").falsy()
        end)

        it("hides on nil", function()
            local a = icon({ icon = "x", size = ROOMY, count = 5 })
            a:SetCount(nil)
            expect(a._countText:IsShown()).falsy()
        end)

        it("prints a two-digit stack", function()
            local a = icon({ icon = "x", size = ROOMY })
            a:SetCount(99)
            expect(a._countText:GetText()).eq("99")
            H.expectTextNotClipped(a._countText)
            H.expectInside(a._countText, a:GetFrame())
        end)
    end)

    ---------------------------------------------------------------------------
    -- 6. The swipe timer
    ---------------------------------------------------------------------------
    describe("the swipe timer", function()
        it("arms the cooldown with start = expiry - duration", function()
            local a = icon({ icon = "x", size = ROOMY })
            a:SetTimer(12, 1000)
            local start, dur = a._cooldown:GetCooldownTimes()
            expect(start).eq(988)
            expect(dur).eq(12)
        end)

        it("clears the swipe AND the duration readout on SetTimer(nil, nil)", function()
            local a = icon({ icon = "x", size = ROOMY, duration = 20, expirationTime = 100 })
            a:SetTimeLeft(15)
            expect(a._durationText:IsShown()).as("armed first").truthy()

            a:SetTimer(nil, nil)

            local start, dur = a._cooldown:GetCooldownTimes()
            expect(start).as("swipe cleared").eq(0)
            expect(dur).eq(0)
            expect(a._durationText:IsShown()).as("readout cleared with it").falsy()
        end)

        it("does not arm a swipe for a permanent aura, whose duration is 0", function()
            local a = icon({ icon = "x", size = ROOMY })
            a:SetTimer(0, 1000)
            local start, dur = a._cooldown:GetCooldownTimes()
            expect(start).as("a duration of 0 must not sweep").eq(0)
            expect(dur).eq(0)
        end)

        it("does not arm a swipe from a duration with no expiry, or the reverse", function()
            local a = icon({ icon = "x", size = ROOMY })
            a:SetTimer(20, nil)
            expect(select(2, a._cooldown:GetCooldownTimes())).eq(0)
            a:SetTimer(nil, 100)
            expect(select(2, a._cooldown:GetCooldownTimes())).eq(0)
        end)

        it("re-arms on a refresh, so a re-applied aura sweeps from its new start", function()
            local a = icon({ icon = "x", size = ROOMY })
            a:SetTimer(20, 100)
            a:SetTimer(20, 140)
            local start, dur = a._cooldown:GetCooldownTimes()
            expect(start).eq(120)
            expect(dur).eq(20)
        end)
    end)

    ---------------------------------------------------------------------------
    -- 7. Duration formatting
    ---------------------------------------------------------------------------
    describe("duration formatting", function()
        local function textAt(a, seconds)
            a:SetTimeLeft(seconds)
            return a._durationText:GetText()
        end

        it("steps hours, minutes, whole seconds and sub-second tenths", function()
            local a = icon({ icon = "x", size = ROOMY })
            expect(textAt(a, 7200)).eq("2h")
            expect(textAt(a, 1800)).eq("30m")
            expect(textAt(a, 45)).eq("45s")
            expect(textAt(a, 5.2)).as("whole seconds all the way down to one").eq("5s")
            expect(textAt(a, 0.4)).as("tenths only below a second").eq("0.4s")
        end)

        it("switches unit exactly at 3600, 60 and 1", function()
            local a = icon({ icon = "x", size = ROOMY })
            expect(textAt(a, 3600)).as("an hour is hours").eq("1h")
            expect(textAt(a, 3599)).as("a second under is minutes").eq("59m")
            expect(textAt(a, 60)).as("a minute is minutes").eq("1m")
            expect(textAt(a, 59)).as("a second under is seconds").eq("59s")
            expect(textAt(a, 10)).as("ten is whole seconds").eq("10s")
            expect(textAt(a, 9.4)).as("so is anything at or above one").eq("9s")
            expect(textAt(a, 1)).as("one second exactly is whole").eq("1s")
            -- Below a second the whole-second form would read "0s" for the entire final
            -- second, which is the one place a decimal earns its width.
            expect(textAt(a, 0.9)).as("under one is tenths").eq("0.9s")
        end)

        it("floors rather than rounds, so a readout never shows time that is gone", function()
            local a = icon({ icon = "x", size = ROOMY })
            expect(textAt(a, 119)).eq("1m")
            expect(textAt(a, 59.9)).eq("59s")
            -- The boundary the old "%.1f" got wrong: rounding printed "1.0s" from the branch
            -- that had already decided this was under a second.
            expect(textAt(a, 0.99)).as("a hair under one stays under one").eq("0.9s")
        end)

        it("takes colorWarning under five seconds and colorText at or above it", function()
            local a = icon({ icon = "x", size = ROOMY })
            a:SetTimeLeft(6)
            H.expectTokenColor(H.textColor(a._durationText), "colorText")
            a:SetTimeLeft(5)
            H.expectTokenColor(H.textColor(a._durationText), "colorText")
            a:SetTimeLeft(4.9)
            H.expectTokenColor(H.textColor(a._durationText), "colorWarning")
        end)

        it("gives the colour BACK when the value rises again", function()
            -- The component keeps an override flag, so this is the path that rots: a
            -- refreshed aura that went 3s -> 30s has to stop reading as expiring.
            local a = icon({ icon = "x", size = ROOMY })
            a:SetTimeLeft(3)
            H.expectTokenColor(H.textColor(a._durationText), "colorWarning")
            a:SetTimeLeft(30)
            H.expectTokenColor(H.textColor(a._durationText), "colorText")
            a:SetTimeLeft(2)
            H.expectTokenColor(H.textColor(a._durationText), "colorWarning")
            a:SetTimeLeft(90)
            H.expectTokenColor(H.textColor(a._durationText), "colorText")
        end)

        it("re-derives the warning colour from a live colorWarning edit", function()
            local a = icon({ icon = "x", size = ROOMY })
            a:SetTimeLeft(2)
            H.T:CreateUserTheme("Alarm", "Modern")
            H.T:SetUserToken("Alarm", "colorWarning", { 1, 0, 0, 1 })
            H.T:SetActive("Alarm")
            expect(H.textColor(a._durationText)).deepEq({ 1, 0, 0, 1 })
        end)

        it("hides the readout at nil, and keeps the last text visible until then", function()
            local a = icon({ icon = "x", size = ROOMY })
            a:SetTimeLeft(20)
            expect(a._durationText:IsShown()).truthy()
            a:SetTimeLeft(nil)
            expect(a._durationText:IsShown()).falsy()
        end)

        it("SetShowDuration hides and reveals a live readout", function()
            local a = icon({ icon = "x", size = ROOMY })
            a:SetTimeLeft(20)
            a:SetShowDuration(false)
            expect(a._durationText:IsShown()).falsy()
            a:SetShowDuration(true)
            expect(a._durationText:IsShown()).as("and back").truthy()
            expect(a._durationText:GetText()).eq("20s")
        end)

        it("keeps a suppressed readout hidden through a new timer", function()
            local a = icon({ icon = "x", size = ROOMY, showDuration = false })
            a:SetTimer(30, 1000)
            a:SetTimeLeft(30)
            expect(a._durationText:IsShown()).falsy()
            expect(select(2, a._cooldown:GetCooldownTimes()))
                .as("the swipe is unaffected by the text setting").eq(30)
        end)
    end)

    ---------------------------------------------------------------------------
    -- 8. Dispel-type border
    ---------------------------------------------------------------------------
    describe("dispel-type border", function()
        it("tints the border with the colour it is given", function()
            local a = icon({ icon = "x", size = ROOMY })
            local magic = H.SuuUI.Game:DebuffTypeColor("Magic")
            a:SetTypeColor(magic)
            expect(H.borderColor(a._iconComp)).deepEq(magic)
        end)

        it("returns the border to the neutral ring on nil", function()
            local a = icon({ icon = "x", size = ROOMY,
                             typeColor = { 0.60, 0.00, 1.00, 1 } })
            a:SetTypeColor(nil)
            H.expectTokenColor(H.borderColor(a._iconComp), "colorBorderIcon")
        end)

        it("swaps straight from one dispel type to another", function()
            local a = icon({ icon = "x", size = ROOMY })
            local G = H.SuuUI.Game
            a:SetTypeColor(G:DebuffTypeColor("Poison"))
            a:SetTypeColor(G:DebuffTypeColor("Curse"))
            expect(H.borderColor(a._iconComp)).deepEq(G:DebuffTypeColor("Curse"))
        end)

        it("keeps a tinted border through a theme change", function()
            local a = icon({ icon = "x", size = ROOMY })
            local tint = { 0.20, 0.60, 1.00, 1 }
            a:SetTypeColor(tint)
            H.T:SetActive("Default")
            expect(H.borderColor(a._iconComp))
                .as("a dispel type is not a theme colour").deepEq(tint)
        end)
    end)

    ---------------------------------------------------------------------------
    -- 9. Signals
    ---------------------------------------------------------------------------
    describe("signals", function()
        it("emits MOUSE_ENTER and MOUSE_LEAVE", function()
            local a = icon({ icon = "x", size = ROOMY })
            local enter = H.signalSpy(a, H.S.SIGNALS.MOUSE_ENTER)
            local leave = H.signalSpy(a, H.S.SIGNALS.MOUSE_LEAVE)
            H.hover(a)
            H.unhover(a)
            expect(enter.count).eq(1)
            expect(leave.count).eq(1)
        end)

        it("emits CLICKED carrying the button, so a right-click stays a right-click", function()
            -- The band reads this payload to decide whether to cancel a buff, so the
            -- string has to arrive as itself rather than normalised to LeftButton.
            local a = icon({ icon = "x", size = ROOMY })
            local spy = H.signalSpy(a, H.S.SIGNALS.CLICKED)
            expect(H.click(a, "RightButton")).truthy()
            expect(spy.count).eq(1)
            expect(spy:arg(1)).eq("RightButton")
            H.click(a, "LeftButton")
            expect(spy:arg(1)).eq("LeftButton")
            expect(spy.count).eq(2)
        end)

        it("emits SIZE_CHANGED when a layout resizes it", function()
            local a = icon({ icon = "x", size = ROOMY })
            local spy = H.signalSpy(a, H.S.SIGNALS.SIZE_CHANGED)
            a:GetFrame():SetSize(36, 36)
            expect(spy.count).gte(1)
            expect(spy:arg(1)).eq(36)
            expect(spy:arg(2)).eq(36)
        end)

        it("emits VISIBILITY_CHANGED on hide and show", function()
            local a = icon({ icon = "x", size = ROOMY })
            local spy = H.signalSpy(a, H.S.SIGNALS.VISIBILITY_CHANGED)
            a:Hide()
            expect(spy.count).eq(1)
            expect(spy:arg(1)).eq(false)
            a:Show()
            expect(spy.count).eq(2)
            expect(spy:arg(1)).eq(true)
        end)

        it("emits ENABLED_CHANGED with the new state", function()
            local a = icon({ icon = "x", size = ROOMY })
            local spy = H.signalSpy(a, H.S.SIGNALS.ENABLED_CHANGED)
            a:SetEnabled(false)
            expect(spy.count).eq(1)
            expect(spy:arg(1)).eq(false)
            a:SetEnabled(true)
            expect(spy:arg(1)).eq(true)
        end)

        it("keeps every setter silent, as the contract says", function()
            -- A band repaints an icon on every UNIT_AURA and ticks its duration ten times a
            -- second. A setter that emitted would turn that into a signal storm.
            local a = icon({ icon = "x", size = ROOMY })
            local spies = {}
            for _, sig in ipairs({ "SIZE_CHANGED", "VISIBILITY_CHANGED", "ENABLED_CHANGED",
                                   "CLICKED", "MOUSE_ENTER", "MOUSE_LEAVE",
                                   "VALUE_CHANGED", "TEXT_CHANGED" }) do
                spies[sig] = H.signalSpy(a, H.S.SIGNALS[sig])
            end

            a:SetIcon("Interface\\Icons\\Spell_Frost_FrostBolt")
            a:SetCount(4)
            a:SetTimer(20, 100)
            a:SetTimeLeft(3)
            a:SetTimeLeft(nil)
            a:SetTypeColor({ 1, 0, 0, 1 })
            a:SetTypeColor(nil)
            a:SetShowDuration(false)
            a:SetShowDuration(true)

            for sig, spy in pairs(spies) do
                expect(spy.count).as(sig .. " must stay silent for a setter").eq(0)
            end
        end)
    end)

    ---------------------------------------------------------------------------
    -- 10. Disabled
    ---------------------------------------------------------------------------
    describe("disabled", function()
        it("fades the whole icon to opacityDisabled", function()
            local a = icon({ icon = "x", size = ROOMY })
            a:SetEnabled(false)
            expect(a:GetFrame():GetAlpha()).near(H.token("opacityDisabled"), 0.001)
        end)

        it("fades exactly once: the nested handles must not multiply it", function()
            -- 0.40 twice is 0.16, which reads as black. The Icon and both Texts carry
            -- _fade = false for precisely this reason.
            local a = icon({ icon = "x", size = ROOMY, count = 3 })
            a:SetTimeLeft(20)
            a:SetEnabled(false)
            expect(a._iconComp:GetFrame():GetAlpha()).as("inner Icon").near(1, 0.001)
            expect(a._countText:GetFrame():GetAlpha()).as("count readout").near(1, 0.001)
            expect(a._durationText:GetFrame():GetAlpha()).as("duration readout").near(1, 0.001)
            expect(a._overlay:GetAlpha()).as("text overlay").near(1, 0.001)
            expect(a._cooldown:GetAlpha()).as("cooldown").near(1, 0.001)
        end)

        it("holds the fade opt-out even if a nested handle is disabled in its own right", function()
            -- The assertion above passes for a second reason too — nothing here disables the
            -- inner handles, so their alpha was never in play. This one disables each of them
            -- directly, which is the only thing that actually exercises _fade = false. Take
            -- it away and the composite lands at 0.40 x 0.40 = 0.16.
            local a = icon({ icon = "x", size = ROOMY, count = 3 })
            a:SetTimeLeft(20)
            a:SetEnabled(false)
            for name, part in pairs({ Icon = a._iconComp, count = a._countText,
                                      duration = a._durationText }) do
                part:SetEnabled(false)
                expect(part:GetFrame():GetAlpha())
                    .as(name .. " must not add a second fade").near(1, 0.001)
            end
        end)

        it("stops taking input, and its own guard holds even when input is forced", function()
            local a = icon({ icon = "x", size = ROOMY })
            local clicked = H.signalSpy(a, H.S.SIGNALS.CLICKED)
            local entered = H.signalSpy(a, H.S.SIGNALS.MOUSE_ENTER)
            a:SetEnabled(false)

            expect(H.click(a)).as("the client stops routing input").falsy()
            expect(H.hover(a)).as("and stops routing hover").falsy()
            H.forceClick(a)
            expect(clicked.count).as("the component's own guard holds too").eq(0)
            a:GetFrame():_fire("OnEnter")
            expect(entered.count).as("the enter guard holds too").eq(0)
        end)

        it("takes input again when re-enabled", function()
            local a = icon({ icon = "x", size = ROOMY })
            local spy = H.signalSpy(a, H.S.SIGNALS.CLICKED)
            a:SetEnabled(false)
            a:SetEnabled(true)
            expect(a:GetFrame():GetAlpha()).near(1, 0.001)
            expect(H.click(a)).truthy()
            expect(spy.count).eq(1)
        end)

        it("re-asserts the fade on a live opacityDisabled edit", function()
            local a = icon({ icon = "x", size = ROOMY })
            a:SetEnabled(false)
            H.T:CreateUserTheme("Faded", "Modern")
            H.T:SetUserToken("Faded", "opacityDisabled", 0.2)
            H.T:SetActive("Faded")
            expect(a:GetFrame():GetAlpha()).near(0.2, 0.001)
        end)
    end)

    ---------------------------------------------------------------------------
    -- 11. Theme reaction
    ---------------------------------------------------------------------------
    describe("theme reaction", function()
        it("re-resolves its border and readout colours on a theme switch", function()
            local a = icon({ icon = "x", size = ROOMY })
            a:SetTimeLeft(20)
            H.T:SetActive("Default")
            H.expectTokenColor(H.borderColor(a._iconComp), "colorBorderIcon")
            H.expectTokenColor(H.textColor(a._durationText), "colorText")
        end)

        it("keeps the warning colour across a theme switch while still expiring", function()
            -- The Texts restyle on the same event, so this asserts the override is
            -- re-applied AFTER they repaint rather than being overwritten by them.
            local a = icon({ icon = "x", size = ROOMY })
            a:SetTimeLeft(2)
            H.T:SetActive("Default")
            H.expectTokenColor(H.textColor(a._durationText), "colorWarning")
        end)

        it("restyles a themed border but leaves a dispel tint alone", function()
            local plain  = icon({ icon = "x", size = ROOMY })
            local tinted = icon({ icon = "y", size = ROOMY })
            local tint = { 0.00, 0.60, 0.00, 1 }
            tinted:SetTypeColor(tint)

            H.T:CreateUserTheme("Edged", "Modern")
            -- colorBorderIcon aliases onto colorGray400, so that is the primitive to
            -- move: retinting colorGray700 now only repaints panels.
            H.T:SetUserToken("Edged", "colorGray400", { 0.5, 0.1, 0.1, 1 })
            H.T:SetActive("Edged")

            expect(H.borderColor(plain._iconComp)).deepEq({ 0.5, 0.1, 0.1, 1 })
            expect(H.borderColor(tinted._iconComp)).deepEq(tint)
        end)
    end)

    ---------------------------------------------------------------------------
    -- 12. Edge cases
    ---------------------------------------------------------------------------
    describe("edge cases", function()
        it("builds with no props at all", function()
            local a = icon()
            local s = H.token("sizeIcon")
            H.expectSize(a, s, s)
            expect(a:GetIcon()).isNil()
            expect(a._countText:IsShown()).falsy()
            expect(a._durationText:IsShown()).falsy()
        end)

        it("clears an icon path back to nothing", function()
            local a = icon({ icon = "x", size = ROOMY })
            a:SetIcon(nil)
            expect(a:GetIcon()).isNil()
        end)

        it("treats a negative or zero time-left as no timer", function()
            local a = icon({ icon = "x", size = ROOMY })
            a:SetTimeLeft(20)
            a:SetTimeLeft(-5)
            expect(a._durationText:IsShown()).as("negative").falsy()
            a:SetTimeLeft(20)
            a:SetTimeLeft(0)
            expect(a._durationText:IsShown()).as("zero").falsy()
        end)

        it("accepts a size of 0 without erroring, and holds it against the token", function()
            local a = icon({ size = 0 })
            H.expectSize(a, 0, 0)
            H.T:CreateUserTheme("Zero", "Modern")
            H.T:SetUserToken("Zero", "sizeIcon", 40)
            H.T:SetActive("Zero")
            H.expectSize(a, 0, 0)
        end)

        it("takes a count with no icon and no timer", function()
            local a = icon({ size = ROOMY, count = 3 })
            expect(a._countText:IsShown()).truthy()
            H.expectInside(a._countText, a:GetFrame())
        end)

        it("survives a duration long enough to read in hours", function()
            local a = icon({ icon = "x", size = ROOMY })
            a:SetTimeLeft(86400)
            expect(a._durationText:GetText()).eq("24h")
        end)

        it("tolerates SetTypeColor(nil) on an already-untinted icon", function()
            local a = icon({ icon = "x", size = ROOMY })
            a:SetTypeColor(nil)
            H.expectTokenColor(H.borderColor(a._iconComp), "colorBorderIcon")
        end)
    end)

    ---------------------------------------------------------------------------
    -- 13. Crowding at the icon sizes the settings actually allow
    --
    -- Both readouts sit on the BOTTOM row — the count in the corner, the duration centred —
    -- while their font comes from fontSizeSm, which does not scale with the icon. At
    -- fontSizeSm = 11 the two need roughly 57 units of edge before they clear each other,
    -- and the icon-size slider tops out at 48 with a shipped default of 24. So the
    -- collision below is not a corner case: it is every timed aura that also stacks.
    --
    -- Pinned rather than asserted-away because the fix is a placement decision (moving the
    -- duration readout to the top edge is the usual answer) and the tests have to show it
    -- the day it changes.
    ---------------------------------------------------------------------------
    describe("crowding at small icon sizes", function()
        -- The two readouts used to share the bottom row -- count in the corner, duration
        -- centred on the same edge -- which put them through each other at every size the
        -- settings allow. Moving the duration to the centre of the icon buys real clearance
        -- at roomy sizes, but does NOT resolve it outright, and these pin where the line is.
        --
        -- The arithmetic, because it explains why no placement alone can: the readouts take
        -- fontSizeSm, whose line height is 14 units and does not scale with the icon. Two
        -- 14-tall boxes cannot be vertically disjoint inside a 24-unit icon, and a centred
        -- "45s" is 18 wide there, leaving 3 units a side. There is no free corner left.
        it("clears both readouts of each other at a roomy icon size", function()
            local a = icon({ icon = "x", size = ROOMY, count = 9 })
            a:SetTimeLeft(45)
            H.expectNoOverlap({ a._countText, a._durationText })
        end)

        it("still crosses the count at the shipped 24-unit band size", function()
            local a = icon({ icon = "x", size = 24, count = 9 })
            a:SetTimeLeft(45)
            local cb, db = H.box(a._countText), H.box(a._durationText)
            expect(db.right).as("the centred readout reaches the corner").gt(cb.left)
            expect(db.bottom).as("and their rows still meet").gt(cb.top)
        end)

        it("still overflows a frame narrower than its own text", function()
            -- At the bare sizeIcon default of 16 a three-glyph readout is wider than the icon
            -- it sits on. Clamping it would make the client truncate the glyphs instead,
            -- which is worse: a truncated timer misreads, where an overhanging one only
            -- looks untidy.
            local a = icon({ icon = "x" })
            a:SetTimeLeft(12)
            local fb, db = H.box(a), H.box(a._durationText)
            expect(db.width).as("the readout is wider than the icon").gt(fb.width)
        end)

        xit("keeps both readouts off each other at every size the slider allows", function()
            -- The invariant we want, for icon sizes 8..48 with a stacking, expiring aura.
            -- Centring the duration was the placement half of it; what remains is the count,
            -- and every route costs something a player would notice:
            --   1. Suppress the count while a duration is on screen (or the reverse).
            --      Cheapest, and hides a number the player asked to see.
            --   2. Give the readouts their own font scale derived from the icon size rather
            --      than fontSizeSm. The token scale bottoms out at 11pt / 14 units, so this
            --      needs a genuinely smaller step -- a new token, or a size not from the
            --      scale at all, which the no-magic-numbers rule would have to bless.
            --   3. Draw the duration BELOW the icon, outside it, and let the band's rows grow
            --      by a line height. The only option that also fixes the 16-unit overflow.
            -- Skipped pending that decision rather than deleted, so the question stays in the
            -- codebase instead of in a chat log.
        end)
    end)

    ---------------------------------------------------------------------------
    -- 14. Teardown
    ---------------------------------------------------------------------------
    describe("teardown", function()
        it("hides and disconnects its own signals", function()
            local a = icon({ icon = "x", size = ROOMY })
            local spy = H.signalSpy(a, H.S.SIGNALS.MOUSE_ENTER)
            a:Destroy()
            expect(a:IsShown()).falsy()
            expect(H.S:HasConnections(a, H.S.SIGNALS.MOUSE_ENTER)).falsy()
            expect(H.S:HasConnections(a, H.S.SIGNALS.CLICKED)).falsy()
            expect(spy.count).eq(0)
        end)

        it("unsubscribes from SUUUI_THEME_CHANGED, so a later token edit cannot resize it", function()
            local a = icon({ icon = "x" })
            local was = a:GetWidth()
            a:Destroy()
            H.T:CreateUserTheme("Later", "Modern")
            H.T:SetUserToken("Later", "sizeIcon", 44)
            H.T:SetActive("Later")
            expect(a:GetWidth()).as("a destroyed icon must not restyle").eq(was)
        end)

        it("frees the child handles: the inner Icon stops listening too", function()
            local a = icon({ icon = "x" })
            local iconWas = a._iconComp:GetWidth()
            local sizeSpy = H.signalSpy(a._iconComp, H.S.SIGNALS.SIZE_CHANGED)
            a:Destroy()
            expect(H.S:HasConnections(a._iconComp, H.S.SIGNALS.SIZE_CHANGED))
                .as("the Icon's connections went with it").falsy()
            H.T:CreateUserTheme("Later2", "Modern")
            H.T:SetUserToken("Later2", "sizeIcon", 44)
            H.T:SetActive("Later2")
            expect(a._iconComp:GetWidth()).as("nor does the Icon restyle").eq(iconWas)
            expect(sizeSpy.count).eq(0)
        end)

        it("survives being destroyed twice", function()
            local a = icon({ icon = "x", size = ROOMY })
            a:Destroy()
            expect(function() a:Destroy() end).notThrows()
        end)
    end)
end)
