local H = require("harness")

describe("Components.Tooltip", function()
    local host
    -- Vertical padding around the tip text. Tighter than any space token, so the
    -- component keeps it as a named constant and so does the spec.
    local PAD_Y = 10
    local function padX() return H.token("spaceSm") * 2 end

    before_each(function()
        H.setup()
        host = H.parent(300, 200)
    end)

    it("starts hidden", function()
        expect(H.C.Tooltip({}, host):IsShown()).falsy()
    end)

    it("lives on the shared floating host", function()
        local tip = H.C.Tooltip({}, host)
        expect(tip._host).eq(H.Layout:GetFloatingHost())
    end)

    it("defaults its parent to UIParent", function()
        expect(H.C.Tooltip({}):GetFrame():GetParent()).eq(H.UIParent)
    end)

    it("shows on ShowTip and raises to the tooltip strata", function()
        local tip = H.C.Tooltip({}, host)
        tip:ShowTip("Hello")
        expect(tip:IsShown()).truthy()
        expect(tip:GetFrame():GetFrameStrata()).eq("TOOLTIP")
    end)

    it("sizes itself to the text plus padding", function()
        local tip = H.C.Tooltip({}, host)
        tip:ShowTip("Hello")
        local size = H.token("fontSizeSm")
        H.expectSize(tip, H.textBox("Hello", size) + padX(), H.lineHeight(size) + PAD_Y)
    end)

    it("anchors above a trigger frame with spaceXs of clearance", function()
        -- Placed well down the screen on purpose: above is the PREFERENCE, and it only
        -- applies where there is room. A trigger left at the screen's top edge takes the
        -- flip instead, which is the next test.
        local trigger = H.parent(60, 20)
        H.SuuUI.Layout:GetFloatingHost():Add(trigger, { anchor = {
            point = "TOPLEFT", relativePoint = "TOPLEFT", x = 100, y = -300,
            width = 60, height = 20 } })
        local tip = H.C.Tooltip({}, host)
        tip:ShowTip("Info", trigger)
        local tb, tipBox = H.box(trigger), H.box(tip)
        expect(tipBox.bottom).as("bottom of tip meets top of trigger")
            .eq(tb.top - H.token("spaceXs"))
        H.expectCenteredH(tip, trigger)
    end)

    it("flips below a trigger that has no room above it", function()
        -- Where the data bar puts every one of its fields: flush against the screen's top
        -- edge. Anchored above, the whole tip renders off-screen and the player sees nothing
        -- at all -- measured on the clock, whose field has top = 0 and whose tip landed at
        -- top = -42.
        local trigger = H.parent(60, 20)
        local tip = H.C.Tooltip({}, host)
        tip:ShowTip("Info", trigger)
        local tb, tipBox = H.box(trigger), H.box(tip)
        expect(tb.top).as("the trigger really is against the top edge").eq(0)
        expect(tipBox.top).as("top of tip meets bottom of trigger, plus the token gap")
            .eq(tb.bottom + H.token("spaceXs"))
        H.expectCenteredH(tip, trigger)
    end)

    it("follows the cursor with a spaceMd offset when no trigger is given", function()
        local tip = H.C.Tooltip({}, host)
        H.cursor(400, 300)
        tip:ShowTip("Follow")
        local off = H.token("spaceMd")
        local box = H.box(tip)
        expect(box.left).eq(400 + off)
        expect(H.state.screenHeight - box.bottom).eq(300 + off)
    end)

    it("fades in to full opacity", function()
        local tip = H.C.Tooltip({}, host)
        tip:ShowTip("Hello")
        expect(tip:GetFrame():GetAlpha()).eq(0)
        H.runAnimations()
        expect(tip:GetFrame():GetAlpha()).eq(1)
    end)

    it("fades out and hides on HideTip", function()
        local tip = H.C.Tooltip({}, host)
        tip:ShowTip("Hello")
        H.runAnimations()
        tip:HideTip()
        H.runAnimations()
        expect(tip:IsShown()).falsy()
        expect(tip:GetFrame():GetAlpha()).eq(0)
    end)

    it("emits VISIBILITY_CHANGED both ways", function()
        local tip = H.C.Tooltip({}, host)
        local spy = H.signalSpy(tip, H.S.SIGNALS.VISIBILITY_CHANGED)
        tip:ShowTip("Hello")
        tip:HideTip()
        expect(spy.count).eq(2)
        expect(spy:arg(1, 1)).truthy()
        expect(spy:arg(1, 2)).falsy()
    end)

    it("re-shows the current text from Show", function()
        local tip = H.C.Tooltip({}, host)
        tip:ShowTip("Kept")
        tip:HideTip()
        H.runAnimations()
        tip:Show()
        expect(tip._text:GetText()).eq("Kept")
        expect(tip:IsShown()).truthy()
    end)

    it("treats nil text as empty", function()
        local tip = H.C.Tooltip({}, host)
        expect(function() tip:ShowTip(nil) end).notThrows()
        expect(tip._text:GetText()).eq("")
    end)

    it("centres the text inside the frame", function()
        local tip = H.C.Tooltip({}, host)
        tip:ShowTip("Centred text")
        H.expectCenteredH(tip._text, tip:GetFrame())
        H.expectCenteredV(tip._text, tip:GetFrame())
    end)

    it("uses the small font and the text colour token", function()
        local tip = H.C.Tooltip({}, host)
        local _, size = tip._text:GetFont()
        expect(size).eq(H.token("fontSizeSm"))
        H.expectTokenColor({ tip._text:GetTextColor() }, "colorText")
    end)

    it("keeps a long single line on one line, growing instead of wrapping", function()
        -- The intent this test has always had, now asserted as the CONSEQUENCE rather than as
        -- the CanWordWrap flag. Wrap is enabled so an explicit newline renders as two rows,
        -- and implicit wrapping still never happens: the tip is sized to its widest line, so
        -- there is always room for it.
        local tip = H.C.Tooltip({}, host)
        local size = H.token("fontSizeSm")
        local long = "a fairly long single line of tooltip text"
        tip:ShowTip(long)
        expect(tip._text:GetNumLines()).as("one row, not a wrapped paragraph").eq(1)
        H.expectSize(tip, H.textBox(long, size) + padX(), H.lineHeight(size) + PAD_Y)
        H.expectTextNotClipped(tip._text)
    end)

    it("renders an explicit newline as two rows", function()
        -- The data bar's clock shows local and realm time on separate rows. With wrap OFF the
        -- client collapsed both onto one row and truncated at the width of the widest line --
        -- measured in game, GetStringHeight reported 13 (a single row) for a two-row string,
        -- and the tip rendered "Local  22:17...".
        local tip = H.C.Tooltip({}, host)
        local size = H.token("fontSizeSm")
        -- Both lines are the same length in the harness font model, so either is the widest.
        tip:ShowTip("Local  22:21\nRealm  22:20")
        expect(tip._text:GetNumLines()).as("two rows").eq(2)
        H.expectSize(tip, H.textBox("Local  22:21", size) + padX(),
                          H.lineHeight(size) * 2 + PAD_Y)
        H.expectTextNotClipped(tip._text)
    end)

    it("re-anchors on each ShowTip rather than accumulating anchors", function()
        local tip = H.C.Tooltip({}, host)
        H.cursor(100, 100)
        tip:ShowTip("One")
        H.cursor(500, 400)
        tip:ShowTip("Two")
        expect(tip:GetFrame():GetNumPoints()).eq(1)
        expect(H.box(tip).left).eq(500 + H.token("spaceMd"))
    end)

    it("grows to fit a longer second tip", function()
        -- Regression guard: measuring a font string a layout has already sized clamps
        -- the result to the old width, which would leave the tip too narrow.
        local tip = H.C.Tooltip({}, host)
        local size = H.token("fontSizeSm")
        local long = "a considerably longer tooltip caption than the first"
        tip:ShowTip("short")
        H.expectSize(tip, H.textBox("short", size) + padX(), nil)
        tip:ShowTip(long)
        H.expectSize(tip, H.textBox(long, size) + padX(), nil)
    end)

    it("draws its text uncut at the size it settles on", function()
        local tip = H.C.Tooltip({}, host)
        tip:ShowTip("a caption that must render in full")
        H.expectTextNotClipped(tip._text)
    end)

    it("re-measures and regrows when the fontSizeSm token changes", function()
        -- The Text component owns the font token and re-measures on a change; the tip
        -- reads the new metrics back so a bigger font is not clipped by a stale box.
        local tip = H.C.Tooltip({}, host)
        tip:ShowTip("Resizable caption")
        local before = H.box(tip)

        H.T:CreateUserTheme("Big", "Modern")
        H.T:SetUserToken("Big", "fontSizeSm", H.token("fontSizeSm") * 2)
        H.T:SetActive("Big")

        local size = H.token("fontSizeSm")
        H.expectSize(tip, H.textBox("Resizable caption", size) + padX(),
                          H.lineHeight(size) + PAD_Y)
        expect(H.box(tip).width).as("a bigger font needs a wider tip").gt(before.width)
        expect(H.box(tip).height).gt(before.height)
        H.expectTextNotClipped(tip._text)
    end)

    it("keeps the surface tokens across a theme change", function()
        local tip = H.C.Tooltip({}, host)
        tip:ShowTip("Themed")
        H.expectTokenColor(H.backdropColor(tip), "colorBg")
        H.expectTokenColor(H.borderColor(tip), "colorBorder")
        H.T:SetActive("Default")
        H.expectTokenColor(H.backdropColor(tip), "colorBg")
        H.expectTokenColor(H.borderColor(tip), "colorBorder")
        H.expectTokenColor(H.textColor(tip._text), "colorText")
    end)

    it("emits SIZE_CHANGED from an explicit SetSize", function()
        local tip = H.C.Tooltip({}, host)
        local spy = H.signalSpy(tip, H.S.SIGNALS.SIZE_CHANGED)
        tip:SetSize(200, 40)
        H.expectSize(tip, 200, 40)
        expect(spy.count).eq(1)
        expect(spy:arg(1)).eq(200)
    end)

    it("drops its frame from the shared host on Destroy but leaves the host", function()
        local floating = H.Layout:GetFloatingHost()
        local tip = H.C.Tooltip({}, host)
        local before = #floating:GetChildren()
        tip:Destroy()
        expect(#floating:GetChildren()).eq(before - 1)
        expect(floating:GetFrame():IsShown()).truthy()
    end)

    -- Tooltip is not a control. Removing SetEnabled ensures Dependency.lua's guard
    -- (`if target.SetEnabled`) correctly skips it.
    it("does not expose SetEnabled", function()
        expect(H.C.Tooltip({}, host).SetEnabled)
            .as("Tooltip is not a control; Dependency skips it").isNil()
    end)
end)

describe("Components.Modal", function()
    before_each(function() H.setup() end)

    describe("structure", function()
        it("defaults to 360 wide", function()
            H.expectSize(H.C.Modal({ title = "T" }), 360, nil)
        end)

        it("honours an explicit width", function()
            H.expectSize(H.C.Modal({ title = "T", w = 500 }), 500, nil)
        end)

        it("covers the parent with its shell at dialog strata", function()
            local m = H.C.Modal({ title = "T" })
            H.expectSize(m._shell, H.UIParent:GetWidth(), H.UIParent:GetHeight())
            expect(m._shell:GetFrameStrata()).eq("DIALOG")
        end)

        it("centres the window in the parent", function()
            local m = H.C.Modal({ title = "T", message = "M" })
            m:Show()
            H.expectCenteredH(m:GetFrame(), m._shell)
            H.expectCenteredV(m:GetFrame(), m._shell)
        end)

        it("sizes its height to the composed content", function()
            local short = H.C.Modal({ title = "T" })
            local tall  = H.C.Modal({ title = "T", message = "M", input = true })
            expect(tall:GetHeight()).gt(short:GetHeight())
        end)

        it("honours an explicit height", function()
            H.expectSize(H.C.Modal({ title = "T", h = 300 }), nil, 300)
        end)

        it("starts hidden, overlay and all", function()
            local m = H.C.Modal({ title = "T" })
            expect(m:IsShown()).falsy()
            expect(m._overlay:IsShown()).falsy()
        end)

        it("dims the screen with the overlay opacity token", function()
            local m = H.C.Modal({ title = "T" })
            local overlayTex = m._overlay._regions[1]
            local _, _, _, a = overlayTex:GetColorTexture()
            expect(a).eq(H.token("opacityOverlay"))
        end)

        it("blocks clicks reaching through the overlay", function()
            local m = H.C.Modal({ title = "T" })
            expect(m._overlay:IsMouseEnabled()).truthy()
        end)

        it("uses the base surface and border tokens for the window", function()
            local m = H.C.Modal({ title = "T" })
            H.expectTokenColor(H.backdropColor(m), "colorBg")
            H.expectTokenColor(H.borderColor(m), "colorBorder")
        end)

        it("derives the window backdrop insets from the borderWidth token", function()
            local m = H.C.Modal({ title = "T" })
            local bw = H.token("borderWidth")
            expect(m:GetFrame():GetBackdrop().edgeSize).eq(bw)
            expect(m:GetFrame():GetBackdrop().insets)
                .deepEq({ left = bw, right = bw, top = bw, bottom = bw })
        end)

        it("follows the borderWidth token when the theme changes it", function()
            local m = H.C.Modal({ title = "T" })
            H.T:CreateUserTheme("Thick", "Modern")
            H.T:SetUserToken("Thick", "borderWidth", 3)
            H.T:SetActive("Thick")
            expect(m:GetFrame():GetBackdrop().edgeSize).eq(3)
        end)

        it("has no SetEnabled, being a composed dialog", function()
            local m = H.C.Modal({ title = "T" })
            expect(m.SetEnabled).as("nothing about a dialog is enabled or disabled").isNil()
        end)

        it("reads its geometry and visibility off the window", function()
            local m = H.C.Modal({ title = "T" })
            expect(m:GetFrame()).eq(m._window)
            expect(m:GetWidth()).eq(m._window:GetWidth())
            expect(m:GetHeight()).eq(m._window:GetHeight())
            expect(m:IsShown()).falsy()
        end)

        it("keeps the width it was composed at when SetSize is called", function()
            -- Modal shares the standard accessors, so SetSize reaches the window. The
            -- shell still owns the width it was composed at, and re-asserts it as soon
            -- as the resize re-runs the content layout. Pinned so a change is visible.
            local m = H.C.Modal({ title = "T", w = 400 })
            m:SetSize(500, 200)
            H.expectSize(m, 400, 200)
        end)
    end)

    describe("buttons", function()
        local function buttonsOf(m)
            local found = {}
            local function walk(frame)
                for _, child in ipairs(frame._childFrames) do
                    for _, region in ipairs(child._regions) do
                        if region._kind == "FontString" and region:GetText() ~= "" then
                            found[region:GetText()] = child
                        end
                    end
                    walk(child)
                end
            end
            walk(m:GetFrame())
            return found
        end

        it("shows Confirm and Cancel by default", function()
            local found = buttonsOf(H.C.Modal({ title = "T" }))
            expect(found["Confirm"]).notNil()
            expect(found["Cancel"]).notNil()
        end)

        it("uses custom button captions", function()
            local found = buttonsOf(H.C.Modal({ title = "T", confirmText = "Delete",
                                                cancelText = "Keep" }))
            expect(found["Delete"]).notNil()
            expect(found["Keep"]).notNil()
        end)

        it("drops the cancel button when dismissOnly", function()
            local found = buttonsOf(H.C.Modal({ title = "T", dismissOnly = true }))
            expect(found["Confirm"]).notNil()
            expect(found["Cancel"]).isNil()
        end)

        it("tints the confirm button with the intent variant", function()
            local m = H.C.Modal({ title = "T", confirmText = "Delete", confirmVariant = "danger" })
            local found = buttonsOf(m)
            local r, g, b, a = found["Delete"]:GetBackdropBorderColor()
            H.expectTokenColor({ r, g, b, a }, "colorDanger")
        end)

        it("leaves the cancel button neutral beside a danger confirm", function()
            local m = H.C.Modal({ title = "T", confirmVariant = "danger" })
            local found = buttonsOf(m)
            local r, g, b, a = found["Cancel"]:GetBackdropBorderColor()
            H.expectTokenColor({ r, g, b, a }, "colorBorder")
        end)

        it("keeps both buttons inside the window without overlap", function()
            local m = H.C.Modal({ title = "T", message = "Are you sure?" })
            m:Show()
            local found = buttonsOf(m)
            H.expectInside(found["Confirm"], m:GetFrame())
            H.expectInside(found["Cancel"], m:GetFrame())
            H.expectNoOverlap({ found["Confirm"], found["Cancel"] })
        end)
    end)

    describe("confirm and cancel", function()
        it("calls onConfirm and emits CONFIRMED", function()
            local called = 0
            local m = H.C.Modal({ title = "T", onConfirm = function() called = called + 1 end })
            local spy = H.signalSpy(m, H.C.MODAL_SIGNALS.CONFIRMED)
            m:Show()
            H.S:Emit(m, H.C.MODAL_SIGNALS.CONFIRMED)
            expect(spy.count).eq(1)
            expect(called).eq(0)
        end)

        it("passes nil to CONFIRMED when there is no input", function()
            local seen = "unset"
            local m = H.C.Modal({ title = "T", input = false,
                                  onConfirm = function(v) seen = v end })
            m:Show()
            H.pressEnter({ _eb = m._window })
            expect(seen).eq("unset")
        end)

        it("passes the typed value to onConfirm and CONFIRMED", function()
            local seen
            local m = H.C.Modal({ title = "T", input = true,
                                  onConfirm = function(v) seen = v end })
            local spy = H.signalSpy(m, H.C.MODAL_SIGNALS.CONFIRMED)
            m:Show()
            H.typeText(m._input, "Profile name")
            H.pressEnter(m._input)
            expect(seen).eq("Profile name")
            expect(spy:arg(1)).eq("Profile name")
        end)

        it("cancels on Escape, emitting CANCELLED and calling onCancel", function()
            local cancelled = 0
            local m = H.C.Modal({ title = "T", onCancel = function() cancelled = cancelled + 1 end })
            local spy = H.signalSpy(m, H.C.MODAL_SIGNALS.CANCELLED)
            m:Show()
            expect(H.key(m:GetFrame(), "ESCAPE")).truthy()
            expect(cancelled).eq(1)
            expect(spy.count).eq(1)
        end)

        it("ignores other keys", function()
            local cancelled = 0
            local m = H.C.Modal({ title = "T", onCancel = function() cancelled = cancelled + 1 end })
            m:Show()
            H.key(m:GetFrame(), "SPACE")
            expect(cancelled).eq(0)
        end)

        it("does not let keys leak to the game while open", function()
            local m = H.C.Modal({ title = "T" })
            expect(m:GetFrame()._propagateKeyboard).falsy()
        end)
    end)

    describe("show and hide", function()
        it("fades the window and overlay in", function()
            local m = H.C.Modal({ title = "T" })
            m:Show()
            expect(m:IsShown()).truthy()
            H.runAnimations()
            expect(m:GetFrame():GetAlpha()).eq(1)
            expect(m._overlay:GetAlpha()).eq(1)
        end)

        it("focuses the input on show", function()
            local m = H.C.Modal({ title = "T", input = true })
            m:Show()
            expect(m._input._eb:HasFocus()).truthy()
        end)

        it("prefills the input from inputValue", function()
            -- It hardcoded `value = ""`, so a caller wanting the current name or a URL in the box had
            -- to reach past the handle into `_input`.
            local m = H.C.Modal({ title = "T", input = true, inputValue = "https://wow.gg" })
            expect(m._input:GetValue()).eq("https://wow.gg")
        end)

        it("SELECTS a prefilled value on show, or Ctrl-C copies nothing", function()
            -- Focus alone is not enough, and the difference is invisible until someone tries to copy:
            -- a copy-a-link dialog shipped focused-but-unselected and could not be copied from.
            local m = H.C.Modal({ title = "T", input = true, inputValue = "https://wow.gg" })
            m:Show()
            local hl = m._input._eb:GetHighlight()
            expect(hl).as("the whole value is selected, ready to copy").notNil()
            expect(hl.from).eq(0)
            expect(hl.to).as("-1 is the client's 'to the end'").eq(-1)
        end)

        it("does not select an EMPTY input, where there is nothing to select", function()
            local m = H.C.Modal({ title = "T", input = true })
            m:Show()
            expect(m._input._eb:GetHighlight()).eq(nil)
            expect(m._input._eb:HasFocus()).as("but it still takes focus").truthy()
        end)

        it("hides the window once the fade finishes", function()
            local m = H.C.Modal({ title = "T" })
            m:Show()
            H.runAnimations()
            m:Hide()
            expect(m:IsShown()).as("still visible mid-fade").truthy()
            H.runAnimations()
            expect(m:IsShown()).falsy()
        end)

        it("clears the input when it closes", function()
            local m = H.C.Modal({ title = "T", input = true })
            m:Show()
            H.typeText(m._input, "leftover")
            m:Hide()
            H.runAnimations()
            expect(m._input:GetValue()).eq("")
        end)

        it("emits VISIBILITY_CHANGED both ways", function()
            local m = H.C.Modal({ title = "T" })
            local spy = H.signalSpy(m, H.S.SIGNALS.VISIBILITY_CHANGED)
            m:Show()
            m:Hide()
            expect(spy.count).eq(2)
        end)

        it("frees itself after hiding when autoDestroy is set", function()
            local m = H.C.Modal({ title = "T", autoDestroy = true })
            m:Show()
            H.runAnimations()
            m:Hide()
            H.runAnimations()
            expect(m:IsShown()).falsy()
            expect(m._shell:IsShown()).as("the whole shell is torn down").falsy()
        end)

        it("keeps a reusable modal alive after hiding", function()
            local m = H.C.Modal({ title = "T" })
            m:Show()
            H.runAnimations()
            m:Hide()
            H.runAnimations()
            expect(m._shell:IsShown()).truthy()
            m:Show()
            expect(m:IsShown()).truthy()
        end)
    end)

    describe("Notice", function()
        it("opens immediately, dismiss-only and self-freeing", function()
            local n = H.C.Notice({ title = "Not Allowed", message = "Nope" })
            expect(n:IsShown()).truthy()
            expect(n._autoDestroy).truthy()
        end)

        it("labels its single button OK by default", function()
            local n = H.C.Notice({ title = "T", message = "M" })
            local labels = {}
            local function walk(frame)
                for _, child in ipairs(frame._childFrames) do
                    for _, region in ipairs(child._regions) do
                        if region._kind == "FontString" then labels[region:GetText()] = true end
                    end
                    walk(child)
                end
            end
            walk(n:GetFrame())
            expect(labels["OK"]).truthy()
            expect(labels["Cancel"]).falsy()
        end)

        it("passes the tone through as the confirm variant", function()
            local n = H.C.Notice({ title = "T", message = "M", tone = "warning" })
            local found
            local function walk(frame)
                for _, child in ipairs(frame._childFrames) do
                    for _, region in ipairs(child._regions) do
                        if region._kind == "FontString" and region:GetText() == "OK" then
                            found = child
                        end
                    end
                    walk(child)
                end
            end
            walk(n:GetFrame())
            expect(found).notNil()
            H.expectTokenColor({ found:GetBackdropBorderColor() }, "colorWarning")
        end)

        it("does not accumulate frames when called repeatedly", function()
            local shells = {}
            for i = 1, 5 do
                local n = H.C.Notice({ title = "T", message = "M " .. i })
                n:Hide()
                H.runAnimations()
                shells[i] = n._shell
            end
            for _, shell in ipairs(shells) do
                expect(shell:IsShown()).as("each notice frees itself").falsy()
            end
        end)
    end)
end)

describe("Components.ClickAway", function()
    local panel, guard

    before_each(function()
        H.setup()
        local host = H.parent(400, 400)
        panel = H.env.CreateFrame("Frame", nil, host)
        panel:SetSize(100, 100)
        panel:SetPoint("TOPLEFT", host, "TOPLEFT", 0, 0)
        guard = H.env.CreateFrame("Frame", nil, host)
        guard:SetSize(50, 20)
        guard:SetPoint("TOPLEFT", host, "TOPLEFT", 200, 0)
    end)

    local function releaseAt(x, y)
        H.cursor(x, y)
        H.setMouseDown("LeftButton", true)
        H.tick(0.05)
        H.setMouseDown("LeftButton", false)
        H.tick(0.05)
    end

    it("does nothing until armed", function()
        local calls = 0
        H.C.ClickAway({ frame = panel, onOutside = function() calls = calls + 1 end })
        releaseAt(900, 900)
        expect(calls).eq(0)
    end)

    it("swallows the release that armed it", function()
        local calls = 0
        local away = H.C.ClickAway({ frame = panel, onOutside = function() calls = calls + 1 end })
        away:Arm()
        H.cursor(900, 900)
        H.setMouseDown("LeftButton", false)
        H.tick(0.05)
        expect(calls).as("the click that opened the panel does not close it").eq(0)
    end)

    it("fires on the next outside release", function()
        local calls = 0
        local away = H.C.ClickAway({ frame = panel, onOutside = function() calls = calls + 1 end })
        away:Arm()
        H.tick(0.05)
        releaseAt(900, 900)
        expect(calls).eq(1)
    end)

    it("stays quiet for a release inside the panel", function()
        local calls = 0
        local away = H.C.ClickAway({ frame = panel, onOutside = function() calls = calls + 1 end })
        away:Arm()
        H.tick(0.05)
        local box = H.box(panel)
        releaseAt(box.left + 10, H.state.screenHeight - box.bottom + 10)
        expect(calls).eq(0)
    end)

    it("treats extra guard frames as inside", function()
        local calls = 0
        local away = H.C.ClickAway({ frame = panel, guards = { guard },
                                     onOutside = function() calls = calls + 1 end })
        away:Arm()
        H.tick(0.05)
        local box = H.box(guard)
        releaseAt(box.left + 5, H.state.screenHeight - box.bottom + 5)
        expect(calls).eq(0)
    end)

    it("accepts a guard added later", function()
        local calls = 0
        local away = H.C.ClickAway({ frame = panel, onOutside = function() calls = calls + 1 end })
        away:AddGuard(guard)
        away:Arm()
        H.tick(0.05)
        local box = H.box(guard)
        releaseAt(box.left + 5, H.state.screenHeight - box.bottom + 5)
        expect(calls).eq(0)
    end)

    it("also watches the right mouse button", function()
        local calls = 0
        local away = H.C.ClickAway({ frame = panel, onOutside = function() calls = calls + 1 end })
        away:Arm()
        H.tick(0.05)
        H.cursor(900, 900)
        H.setMouseDown("RightButton", true)
        H.tick(0.05)
        H.setMouseDown("RightButton", false)
        H.tick(0.05)
        expect(calls).eq(1)
    end)

    it("stops after Disarm", function()
        local calls = 0
        local away = H.C.ClickAway({ frame = panel, onOutside = function() calls = calls + 1 end })
        away:Arm()
        H.tick(0.05)
        away:Disarm()
        releaseAt(900, 900)
        expect(calls).eq(0)
    end)

    it("disarms itself when the watched panel is hidden", function()
        local calls = 0
        local away = H.C.ClickAway({ frame = panel, onOutside = function() calls = calls + 1 end })
        away:Arm()
        panel:Hide()
        H.tick(0.05)
        expect(away._watcher:IsShown()).falsy()
        releaseAt(900, 900)
        expect(calls).eq(0)
    end)

    it("polls nothing while idle", function()
        local away = H.C.ClickAway({ frame = panel, onOutside = function() end })
        expect(away._watcher:IsVisible()).as("no idle OnUpdate cost").falsy()
        away:Arm()
        expect(away._watcher:IsVisible()).truthy()
    end)

    it("stops polling after Destroy", function()
        local calls = 0
        local away = H.C.ClickAway({ frame = panel, onOutside = function() calls = calls + 1 end })
        away:Arm()
        H.tick(0.05)
        away:Destroy()
        releaseAt(900, 900)
        expect(calls).eq(0)
        expect(away._watcher:GetScript("OnUpdate")).isNil()
    end)

    it("treats an unresolvable frame as outside", function()
        local orphan = H.env.CreateFrame("Frame", nil, H.UIParent)
        orphan:ClearAllPoints()
        orphan:SetSize(10, 10)
        local calls = 0
        local away = H.C.ClickAway({ frame = panel, guards = { orphan },
                                     onOutside = function() calls = calls + 1 end })
        away:Arm()
        H.tick(0.05)
        releaseAt(900, 900)
        expect(calls).eq(1)
    end)
end)
