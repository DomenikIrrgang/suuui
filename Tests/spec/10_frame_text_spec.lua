local H = require("harness")

describe("Components.Frame", function()
    local host
    before_each(function()
        H.setup()
        host = H.parent(300, 200)
    end)

    -- THE SURFACE MUST FOLLOW THE FRAME, and nothing checked it. Measured in game: the inventory's
    -- grid plate kept its previous, larger size after the window shrank, drawing a dark rounded band
    -- below the content. Backdrop.Panel installs its own resize hook, and Frame's SetScript -- one line
    -- later -- REPLACED it, so no piece ever re-derived. Asserted on the PIECES rather than the frame,
    -- because the frame's own size was always correct and that is exactly what hid this.
    it("resizes a rounded surface's pieces with the frame", function()
        local fr = H.mount(H.C.Frame({ w = 200, h = 120, rounded = true }, host))
        local panel = fr._panel
        expect(panel).as("a rounded frame builds a panel").truthy()
        -- M is the fill layer's centre band: it spans the frame minus its rounded corners, so its
        -- height moves with the frame's.
        local band = panel._fill and panel._fill.M
        expect(band).as("the fill layer exposes a centre band").truthy()
        local before = band:GetHeight()
        expect(before).as("and it has a height to begin with").gt(0)
        fr:GetFrame():SetHeight(60)
        expect(band:GetHeight()).as("the surface followed the frame down").lt(before)
    end)

    it("applies both dimensions when w and h are given", function()
        local f = H.C.Frame({ w = 120, h = 40 }, host)
        H.expectSize(f, 120, 40)
    end)

    it("applies each dimension independently", function()
        H.expectSize(H.C.Frame({ w = 120 }, host), 120, 0)
        H.expectSize(H.C.Frame({ h = 40 }, host), 0, 40)
    end)

    it("leaves an omitted axis for the layout to decide", function()
        local col = H.Layout:CreateContainer({ parent = host, layout = "flow", dir = "vertical" })
        local f = H.C.Frame({ h = 30 }, col:GetFrame())
        col:Add(f, { width = "fill" })
        H.expectSize(f, 300, 30)
    end)

    it("stays at zero size when given neither dimension", function()
        H.expectSize(H.C.Frame({}, host), 0, 0)
    end)

    it("uses colorBg for the default variant", function()
        local f = H.C.Frame({ w = 10, h = 10 }, host)
        H.expectTokenColor(H.backdropColor(f), "colorBg")
    end)

    it("maps each variant onto its surface token", function()
        for variant, token in pairs({ bg = "colorBg", bgAlt = "colorBgAlt", bgActive = "colorBgActive" }) do
            local f = H.C.Frame({ w = 10, h = 10, variant = variant }, host)
            H.expectTokenColor(H.backdropColor(f), token)
        end
    end)

    it("clears the background for the transparent variant", function()
        local f = H.C.Frame({ w = 10, h = 10, variant = "transparent" }, host)
        expect(H.backdropColor(f)).deepEq({ 0, 0, 0, 0 })
    end)

    it("draws the border from colorBorder", function()
        local f = H.C.Frame({ w = 10, h = 10 }, host)
        H.expectTokenColor(H.borderColor(f), "colorBorder")
    end)

    it("hides the border with border=false", function()
        local f = H.C.Frame({ w = 10, h = 10, border = false }, host)
        expect(H.borderColor(f)).deepEq({ 0, 0, 0, 0 })
    end)

    it("sizes the backdrop edge from the borderWidth token", function()
        local f = H.C.Frame({ w = 10, h = 10 }, host)
        expect(f:GetFrame():GetBackdrop().edgeSize).eq(H.token("borderWidth"))
    end)

    describe("disabled state", function()
        it("fades to opacityDisabled when disabled", function()
            local f = H.C.Frame({ w = 10, h = 10 }, host)
            f:SetEnabled(false)
            expect(f:GetFrame():GetAlpha()).eq(H.token("opacityDisabled"))
        end)

        it("restores full alpha when re-enabled", function()
            local f = H.C.Frame({ w = 10, h = 10 }, host)
            f:SetEnabled(false)
            f:SetEnabled(true)
            expect(f:GetFrame():GetAlpha()).eq(1)
        end)

        it("fades both bg and bgAlt variants identically", function()
            for _, variant in ipairs({ "bg", "bgAlt" }) do
                local f = H.C.Frame({ w = 10, h = 10, variant = variant }, host)
                f:SetEnabled(false)
                expect(f:GetFrame():GetAlpha()).as(variant .. " disabled alpha")
                    .eq(H.token("opacityDisabled"))
            end
        end)

        it("keeps the variant's own background token while disabled", function()
            local f = H.C.Frame({ w = 10, h = 10, variant = "bgAlt" }, host)
            f:SetEnabled(false)
            H.expectTokenColor(H.backdropColor(f), "colorBgAlt")
        end)

        it("drops mouse input when disabled", function()
            local f = H.C.Frame({ w = 10, h = 10 }, host)
            f:GetFrame():EnableMouse(true)
            f:SetEnabled(false)
            expect(f:GetFrame():IsMouseEnabled()).falsy()
        end)

        it("restores mouse input when re-enabled", function()
            local f = H.C.Frame({ w = 10, h = 10 }, host)
            f:GetFrame():EnableMouse(true)
            f:SetEnabled(false)
            f:SetEnabled(true)
            expect(f:GetFrame():IsMouseEnabled()).truthy()
        end)

        -- Frame is a passive container: it never explicitly enables mouse. A round-trip
        -- through disable/enable must NOT force mouse on (it would start swallowing
        -- clicks meant for children underneath).
        it("does not enable mouse on a passive frame after a disable/enable round-trip", function()
            local f = H.C.Frame({ w = 10, h = 10 }, host)
            -- The default Frame never calls EnableMouse(true), so it starts off.
            expect(f:GetFrame():IsMouseEnabled()).falsy()
            f:SetEnabled(false)
            f:SetEnabled(true)
            expect(f:GetFrame():IsMouseEnabled()).as("passive frame stays non-mouse").falsy()
        end)

        it("re-reads opacityDisabled on theme change while already disabled", function()
            local f = H.C.Frame({ w = 10, h = 10 }, host)
            f:SetEnabled(false)
            H.T:CreateUserTheme("Dim", "Modern")
            H.T:SetUserToken("Dim", "opacityDisabled", 0.25)
            H.T:SetActive("Dim")
            expect(f:GetFrame():GetAlpha()).eq(0.25)
        end)

        it("reports IsEnabled correctly", function()
            local f = H.C.Frame({ w = 10, h = 10 }, host)
            expect(f:IsEnabled()).truthy()
            f:SetEnabled(false)
            expect(f:IsEnabled()).falsy()
        end)
    end)

    it("emits ENABLED_CHANGED with the new state", function()
        local f = H.C.Frame({ w = 10, h = 10 }, host)
        local spy = H.signalSpy(f, H.S.SIGNALS.ENABLED_CHANGED)
        f:SetEnabled(false)
        expect(spy.count).eq(1)
        expect(spy:arg(1)).falsy()
    end)

    it("emits SIZE_CHANGED exactly once when resized", function()
        local f = H.C.Frame({ w = 10, h = 10 }, host)
        local spy = H.signalSpy(f, H.S.SIGNALS.SIZE_CHANGED)
        f:SetSize(50, 60)
        expect(spy.count).as("the resize hook is the only emitter").eq(1)
        expect(spy:arg(1)).eq(50)
        expect(spy:arg(2)).eq(60)
    end)

    it("stays quiet when SetSize is a no-op", function()
        local f = H.C.Frame({ w = 10, h = 10 }, host)
        local spy = H.signalSpy(f, H.S.SIGNALS.SIZE_CHANGED)
        f:SetSize(10, 10)
        expect(spy.count).eq(0)
    end)

    it("emits SIZE_CHANGED when a parent layout resizes the frame directly", function()
        local col = H.Layout:CreateContainer({ parent = host, layout = "flow", dir = "vertical" })
        local f = H.C.Frame({ w = 10, h = 10 }, col:GetFrame())
        local spy = H.signalSpy(f, H.S.SIGNALS.SIZE_CHANGED)
        col:Add(f, { width = "fill", height = 44 })
        expect(spy.count).as("layout-driven resize must reach signal consumers").gte(1)
        expect(spy:arg(1)).eq(300)
        expect(spy:arg(2)).eq(44)
        H.expectSize(f, 300, 44)
    end)

    it("emits VISIBILITY_CHANGED from Show and Hide", function()
        local f = H.C.Frame({ w = 10, h = 10 }, host)
        local spy = H.signalSpy(f, H.S.SIGNALS.VISIBILITY_CHANGED)
        f:Hide()
        expect(f:IsShown()).falsy()
        f:Show()
        expect(spy.count).eq(2)
    end)

    it("restyles itself when the theme changes", function()
        local f = H.C.Frame({ w = 10, h = 10 }, host)
        H.T:CreateUserTheme("Custom", "Modern")
        H.T:SetUserToken("Custom", "colorGray900", { 1, 0, 0, 1 })
        H.T:SetActive("Custom")
        H.expectTokenColor(H.backdropColor(f), "colorBg")
        expect(H.backdropColor(f)[1]).eq(1)
    end)

    it("memoises the container returned by GetContainer", function()
        local f = H.C.Frame({ w = 100, h = 50 }, host)
        local a = f:GetContainer({ layout = "flow" })
        expect(f:GetContainer()).eq(a)
        expect(a:GetFrame()).eq(f:GetFrame())
    end)

    it("hides and unsubscribes on Destroy", function()
        local f = H.C.Frame({ w = 10, h = 10 }, host)
        f:Destroy()
        expect(f:IsShown()).falsy()
        expect(function() H.T:SetActive("Default") end).notThrows()
    end)
end)

describe("Components.Text", function()
    local host
    before_each(function()
        H.setup()
        host = H.parent(300, 200)
    end)

    it("draws no shadow by default", function()
        -- Opt-in: text inside a panel has a surface behind it already, where a shadow is muddy.
        local t = H.C.Text({ text = "Hello" }, host)
        local _, _, _, a = t:GetFrame():GetShadowColor()
        expect(a).eq(0)
        expect(t:HasShadow()).falsy()
    end)

    it("shadows on request, for text over the game world", function()
        local t = H.C.Text({ text = "Hello", shadow = true }, host)
        expect(t:HasShadow()).truthy()
        local r, g, b, a = t:GetFrame():GetShadowColor()
        local ink = H.token("colorGray950")
        expect(r).near(ink[1], 0.02)
        expect(g).near(ink[2], 0.02)
        expect(b).near(ink[3], 0.02)
        expect(a).near(H.token("opacityTextShadow"), 0.01)
    end)

    it("toggles the shadow at runtime", function()
        local t = H.C.Text({ text = "Hello" }, host)
        t:SetShadow(true)
        local _, _, _, on = t:GetFrame():GetShadowColor()
        expect(on).near(H.token("opacityTextShadow"), 0.01)
        t:SetShadow(false)
        local _, _, _, off = t:GetFrame():GetShadowColor()
        expect(off).eq(0)
    end)

    it("renders the text it was given", function()
        local t = H.C.Text({ text = "Hello" }, host)
        expect(t:GetText()).eq("Hello")
    end)

    -- THE DEFECT THIS PINS shipped three truncation bugs in one sitting -- two panel counters and a
    -- change list -- because the width was applied only when BOTH w and h were given. A caller
    -- passing `w` alone got NO width, and a FontString with no width CANNOT WRAP: the client draws
    -- one long line and the parent clips it, which reads as an ellipsis. None of the obvious
    -- assertions at the call sites could see it, because the harness derives a bound width from the
    -- layout container's anchors while the real client had nothing set at all. Asserted HERE, where
    -- the value is set rather than inferred.
    it("honours a width given without a height", function()
        local t = H.C.Text({ text = "x", w = 140 }, host)
        expect(t:GetFrame():GetWidth())
            .as("width alone must bind, or the label cannot wrap and the client truncates").eq(140)
    end)

    it("still owns its own height when only a width is given", function()
        local t = H.C.Text({ text = "x", w = 140 }, host)
        expect(t:GetFrame():GetHeight() > 0)
            .as("_fixed stays false without an explicit h, so _measure keeps sizing the height and "
                .. "a wrapped label can grow to the lines it needs").truthy()
    end)

    it("keeps owning the height when a height is given without a width", function()
        local t = H.C.Text({ text = "x", h = 40 }, host)
        expect(t:GetFrame():GetHeight() ~= 40)
            .as("there is deliberately NO height-only branch: _fixed stays false without a width, "
                .. "so _measure re-sizes the height on the next SetText and an h alone would be a "
                .. "line that reads as intent and does nothing").truthy()
    end)

    it("defaults to the medium font size token", function()
        local t = H.C.Text({ text = "x" }, host)
        local _, size = t:GetFrame():GetFont()
        expect(size).eq(H.token("fontSizeMd"))
    end)

    it("maps each size key onto its font token", function()
        for key, token in pairs({ sm = "fontSizeSm", md = "fontSizeMd",
                                  lg = "fontSizeLg", xl = "fontSizeXl" }) do
            local t = H.C.Text({ text = "x", size = key }, host)
            local _, size = t:GetFrame():GetFont()
            expect(size).as("size=" .. key).eq(H.token(token))
        end
    end)

    it("falls back to the medium size for an unknown size key", function()
        local t = H.C.Text({ text = "x", size = "enormous" }, host)
        local _, size = t:GetFrame():GetFont()
        expect(size).eq(H.token("fontSizeMd"))
    end)

    it("maps each colour key onto its content token", function()
        for key, token in pairs({ text = "colorText", muted = "colorTextMuted",
                                  textMuted = "colorTextMuted",
                                  disable = "colorTextDisabled", accent = "colorAccent" }) do
            local t = H.C.Text({ text = "x", color = key }, host)
            H.expectTokenColor(H.textColor(t), token)
        end
    end)

    -- Intent colours: a label whose VALUE carries state -- a readout that is fine, close to
    -- a threshold, or past it. Named for the intent rather than the hue, so a retint moves
    -- them with every other warning in the UI, which is why every expectation here resolves
    -- the token through the theme instead of naming an RGB.
    describe("intent colours", function()
        local INTENT = { success = "colorSuccess", warning = "colorWarning",
                         danger = "colorDanger" }

        -- Every assertion below rests on the intent tokens actually DIFFERING from the
        -- default one: "resolves colorWarning" and "degraded to colorText" would otherwise
        -- be the same claim, and the whole block would pass with colmap gutted.
        local function expectDistinctFromText(token)
            local a, b = H.token(token), H.token("colorText")
            local same = true
            for i = 1, 4 do if a[i] ~= b[i] then same = false; break end end
            expect(same).as(token .. " must differ from colorText for this to mean anything")
                .falsy()
        end

        it("maps each intent key onto its intent token", function()
            for key, token in pairs(INTENT) do
                expectDistinctFromText(token)
                local t = H.C.Text({ text = "42", color = key }, host)
                H.expectTokenColor(H.textColor(t), token)
            end
        end)

        it("repaints when SetColor names an intent", function()
            local t = H.C.Text({ text = "42" }, host)
            H.expectTokenColor(H.textColor(t), "colorText")
            t:SetColor("danger")
            H.expectTokenColor(H.textColor(t), "colorDanger")
            t:SetColor("success")
            H.expectTokenColor(H.textColor(t), "colorSuccess")
            t:SetColor("text")
            H.expectTokenColor(H.textColor(t), "colorText")
        end)

        it("degrades an unknown colour key to colorText rather than raising", function()
            -- Load-bearing rather than tidy: an intent colour is set from a ticker callback,
            -- where an error unwinds out of the refresh loop and takes every other widget's
            -- readout with it.
            local t
            expect(function()
                t = H.C.Text({ text = "42", color = "catastrophe" }, host)
            end).notThrows()
            H.expectTokenColor(H.textColor(t), "colorText")

            expect(function() t:SetColor("also nonsense") end).notThrows()
            H.expectTokenColor(H.textColor(t), "colorText")
        end)

        it("re-resolves an intent colour when the theme moves the token", function()
            local t = H.C.Text({ text = "42", color = "warning" }, host)
            H.T:CreateUserTheme("Hot", "Modern")
            H.T:SetUserToken("Hot", "colorWarning", { 1, 0, 0, 1 })
            H.T:SetActive("Hot")
            H.expectTokenColor(H.textColor(t), "colorWarning")
            expect(H.textColor(t)[1]).as("the switch really did move the token").eq(1)

            -- And again with that theme already active, which is the path a user editing the
            -- token takes: the subscription rather than the switch.
            H.T:SetUserToken("Hot", "colorWarning", { 0, 1, 0, 1 })
            H.expectTokenColor(H.textColor(t), "colorWarning")
            expect(H.textColor(t)[2]).as("a live token edit reaches the font string").eq(1)
        end)
    end)

    it("defaults to left justification and middle vertical justification", function()
        local t = H.C.Text({ text = "x" }, host)
        expect(t:GetFrame():GetJustifyH()).eq("LEFT")
        expect(t:GetFrame():GetJustifyV()).eq("MIDDLE")
    end)

    it("honours an explicit justify", function()
        local t = H.C.Text({ text = "x", justify = "CENTER" }, host)
        expect(t:GetFrame():GetJustifyH()).eq("CENTER")
    end)

    it("measures its own height from the font when not pinned", function()
        local t = H.C.Text({ text = "one line" }, host)
        expect(t:GetHeight()).eq(H.lineHeight(H.token("fontSizeMd")))
    end)

    describe("face override", function()
        it("follows the theme font token by default", function()
            local t = H.C.Text({ text = "x" }, host)
            expect((H.fontOf(t))).eq(H.token("fontFamilyMain"))
            expect(t:GetFontOverride()).isNil()
        end)

        it("renders in an explicit face from props", function()
            local t = H.C.Text({ text = "x", font = "Fonts/MORPHEUS.TTF" }, host)
            expect((H.fontOf(t))).eq("Fonts/MORPHEUS.TTF")
            expect(t:GetFontOverride()).eq("Fonts/MORPHEUS.TTF")
        end)

        it("keeps the size and colour tokens while overriding the face", function()
            local t = H.C.Text({ text = "x", size = "lg", color = "accent",
                                 font = "Fonts/ARIALN.TTF" }, host)
            local _, size = H.fontOf(t)
            expect(size).eq(H.token("fontSizeLg"))
            H.expectTokenColor(H.textColor(t), "colorAccent")
        end)

        it("re-measures for the override's own line height", function()
            local plain = H.C.Text({ text = "Sample" }, host)
            local tall  = H.C.Text({ text = "Sample", font = "Fonts/MORPHEUS.TTF" }, host)
            expect(tall:GetHeight()).as("a taller face reports a taller line")
                .gt(plain:GetHeight())
            expect(tall:GetHeight())
                .eq(H.lineHeight(H.token("fontSizeMd"), "Fonts/MORPHEUS.TTF"))
        end)

        it("switches face through SetFont", function()
            local t = H.mount(H.C.Text({ text = "Sample" }, host))
            t:SetFont("Fonts/MORPHEUS.TTF")
            expect((H.fontOf(t))).eq("Fonts/MORPHEUS.TTF")
            expect(t:GetHeight())
                .eq(H.lineHeight(H.token("fontSizeMd"), "Fonts/MORPHEUS.TTF"))
        end)

        it("reports the new height when a layout had pinned it", function()
            local col = H.Layout:CreateContainer({
                parent = host, layout = "flow", dir = "vertical", w = 200,
            })
            local t = H.C.Text({ text = "Sample" }, col:GetFrame())
            col:Add(t, { width = "fill", height = H.lineHeight(H.token("fontSizeMd")) })

            local spy = H.signalSpy(t, H.S.SIGNALS.SIZE_CHANGED)
            t:SetFont("Fonts/MORPHEUS.TTF")
            expect(spy.count).gte(1)
            expect(spy:arg(2))
                .gte(H.lineHeight(H.token("fontSizeMd"), "Fonts/MORPHEUS.TTF"))
        end)

        it("returns to the theme face when the override is cleared", function()
            local t = H.C.Text({ text = "x", font = "Fonts/ARIALN.TTF" }, host)
            t:SetFont(nil)
            expect((H.fontOf(t))).eq(H.token("fontFamilyMain"))
            expect(t:GetFontOverride()).isNil()
        end)

        it("degrades an unloadable override instead of raising", function()
            local t
            expect(function()
                t = H.C.Text({ text = "x", font = "Interface/AddOns/Nope/gone.ttf" }, host)
            end).notThrows()
            expect((H.fontOf(t))).eq(H.SuuUI.Fonts.FALLBACK)

            expect(function() t:SetFont("also nonsense") end).notThrows()
            expect(H.font.hasFace((H.fontOf(t)))).truthy()
        end)

        it("keeps the override across a theme change", function()
            local t = H.C.Text({ text = "x", font = "Fonts/ARIALN.TTF" }, host)
            H.T:CreateUserTheme("Other", "Modern")
            H.T:SetUserToken("Other", "fontFamilyMain", "Morpheus")
            H.T:SetActive("Other")
            expect((H.fontOf(t))).as("an explicit face is not a theme default")
                .eq("Fonts/ARIALN.TTF")
        end)
    end)

    describe("size step", function()
        it("switches step through SetFontSize", function()
            local t = H.mount(H.C.Text({ text = "Sample" }, host))
            expect(t:GetFontSize()).eq("md")
            t:SetFontSize("xl")
            local _, size = H.fontOf(t)
            expect(size).eq(H.token("fontSizeXl"))
            expect(t:GetFontSize()).eq("xl")
        end)

        it("re-measures for the new step", function()
            local t = H.mount(H.C.Text({ text = "Sample", size = "sm" }, host))
            local before = t:GetHeight()
            t:SetFontSize("xl")
            expect(t:GetHeight()).as("a bigger step is a taller line").gt(before)
            expect(t:GetHeight()).eq(H.lineHeight(H.token("fontSizeXl")))
        end)

        it("reports the new height so a layout that pinned it re-flows", function()
            local col = H.Layout:CreateContainer({
                parent = host, layout = "flow", dir = "vertical", w = 200,
            })
            local t = H.C.Text({ text = "Sample" }, col:GetFrame())
            col:Add(t, { width = "fill", height = H.lineHeight(H.token("fontSizeMd")) })

            local spy = H.signalSpy(t, H.S.SIGNALS.SIZE_CHANGED)
            t:SetFontSize("xl")
            expect(spy.count).gte(1)
            expect(spy:arg(2)).gte(H.lineHeight(H.token("fontSizeXl")))
        end)

        it("still follows the token after the step changed", function()
            -- The step is a KEY, not a size: an explicit step is not an escape from the
            -- theme, which is what lets a plugin expose it as a setting.
            local t = H.mount(H.C.Text({ text = "Sample" }, host))
            t:SetFontSize("lg")
            H.T:CreateUserTheme("Big", "Modern")
            H.T:SetUserToken("Big", "fontSizeLg", 40)
            H.T:SetActive("Big")
            local _, size = H.fontOf(t)
            expect(size).eq(40)
        end)

        it("keeps a face override while the step changes", function()
            local t = H.mount(H.C.Text({ text = "Sample", font = "Fonts/MORPHEUS.TTF" }, host))
            t:SetFontSize("lg")
            expect((H.fontOf(t))).eq("Fonts/MORPHEUS.TTF")
            local _, size = H.fontOf(t)
            expect(size).eq(H.token("fontSizeLg"))
        end)

        it("degrades an unknown step to the medium token rather than raising", function()
            local t = H.mount(H.C.Text({ text = "Sample" }, host))
            expect(function() t:SetFontSize("enormous") end).notThrows()
            local _, size = H.fontOf(t)
            expect(size).as("a hand-edited SavedVariable must not break a label")
                .eq(H.token("fontSizeMd"))
        end)
    end)

    it("does not re-measure when both w and h were given", function()
        local t = H.C.Text({ text = "pinned", w = 80, h = 9 }, host)
        expect(t:GetHeight()).as("an explicitly sized text stays put").eq(9)
    end)

    it("emits TEXT_CHANGED on SetText", function()
        local t = H.C.Text({ text = "a" }, host)
        local spy = H.signalSpy(t, H.S.SIGNALS.TEXT_CHANGED)
        t:SetText("b")
        expect(spy.count).eq(1)
        expect(spy:arg(1)).eq("b")
    end)

    it("emits SIZE_CHANGED when new text changes the measured height", function()
        local col = H.Layout:CreateContainer({ parent = host, layout = "flow",
                                               dir = "vertical", w = 60 })
        local t = H.C.Text({ text = "short" }, col:GetFrame())
        col:Add(t, { width = "fill" })
        local spy = H.signalSpy(t, H.S.SIGNALS.SIZE_CHANGED)
        t:SetText("a much longer run of words that has to wrap over several lines")
        expect(spy.count).gte(1)
    end)

    it("re-measures and reports a new height when the font token grows", function()
        local col = H.Layout:CreateContainer({ parent = host, layout = "flow", dir = "vertical" })
        local t = H.C.Text({ text = "Label" }, col:GetFrame())
        col:Add(t, { width = "fill" })
        local before = t:GetHeight()

        H.T:CreateUserTheme("Big", "Modern")
        H.T:SetUserToken("Big", "fontSizeMd", 30)
        H.T:SetActive("Big")

        expect(t:GetHeight()).as("text grows with the font token").gt(before)
        expect(col:GetHeight()).as("and the containing layout re-flows").gte(t:GetHeight())
    end)

    describe("disabled state", function()
        it("switches to the disabled colour via SetEnabled", function()
            local t = H.C.Text({ text = "x", color = "accent" }, host)
            t:SetEnabled(false)
            H.expectTokenColor(H.textColor(t), "colorTextDisabled")
        end)

        it("restores the original colour when re-enabled", function()
            local t = H.C.Text({ text = "x", color = "accent" }, host)
            t:SetEnabled(false)
            t:SetEnabled(true)
            H.expectTokenColor(H.textColor(t), "colorAccent")
        end)

        -- Regression guard: Text opts out of the alpha fade because a greyed label at
        -- 0.40 alpha is unreadable. If someone later 'unifies' the component onto the
        -- fade, this test breaks.
        it("keeps alpha 1 when disabled (no fade, only colour change)", function()
            local t = H.C.Text({ text = "x" }, host)
            t:SetEnabled(false)
            expect(t:GetFrame():GetAlpha()).as("Text must not fade; it uses colour alone").eq(1)
        end)

        it("uses colorTextDisabled which is distinct from all enabled colour keys", function()
            local t = H.C.Text({ text = "x" }, host)
            t:SetEnabled(false)
            local disabled = H.textColor(t)
            for _, key in ipairs({ "text", "muted", "accent" }) do
                local t2 = H.C.Text({ text = "x", color = key }, host)
                local enabled = H.textColor(t2)
                -- Manual deep-inequality: at least one channel must differ.
                local same = true
                for i = 1, 4 do
                    if disabled[i] ~= enabled[i] then same = false; break end
                end
                expect(same).as("disabled must differ from " .. key).falsy()
            end
        end)

        it("reports IsEnabled correctly", function()
            local t = H.C.Text({ text = "x" }, host)
            expect(t:IsEnabled()).truthy()
            t:SetEnabled(false)
            expect(t:IsEnabled()).falsy()
        end)

        it("emits ENABLED_CHANGED", function()
            local t = H.C.Text({ text = "x" }, host)
            local spy = H.signalSpy(t, H.S.SIGNALS.ENABLED_CHANGED)
            t:SetEnabled(false)
            expect(spy.count).eq(1)
            expect(spy:arg(1)).falsy()
        end)
    end)

    it("changes colour explicitly with SetColor", function()
        local t = H.C.Text({ text = "x" }, host)
        t:SetColor("muted")
        H.expectTokenColor(H.textColor(t), "colorTextMuted")
    end)

    it("stops restyling once destroyed", function()
        local t = H.C.Text({ text = "x", color = "accent" }, host)
        t:Destroy()
        local before = H.textColor(t)
        H.T:CreateUserTheme("Other", "Modern")
        H.T:SetUserToken("Other", "colorBlue400", { 0, 1, 0, 1 })
        H.T:SetActive("Other")
        expect(H.textColor(t)).deepEq(before)
    end)
end)

describe("Components.Divider", function()
    local host
    before_each(function()
        H.setup()
        host = H.parent(300, 200)
    end)

    it("defaults to a 200-wide horizontal rule one border width thick", function()
        local d = H.C.Divider({}, host)
        H.expectSize(d, 200, H.token("borderWidth"))
    end)

    it("defaults to a 20-tall vertical rule one border width thick", function()
        local d = H.C.Divider({ dir = "vertical" }, host)
        H.expectSize(d, H.token("borderWidth"), 20)
    end)

    it("takes its thickness from the borderWidth token", function()
        H.T:CreateUserTheme("Thick", "Modern")
        H.T:SetUserToken("Thick", "borderWidth", 3)
        H.T:SetActive("Thick")
        local d = H.mount(H.C.Divider({ w = 100 }, host))
        H.expectSize(d, 100, 3)
        H.expectSize(d._line, 100, 3)
    end)

    it("honours explicit dimensions", function()
        local d = H.C.Divider({ w = 88, h = 3 }, host)
        H.expectSize(d, 88, 3)
    end)

    it("colours the line with colorBorder", function()
        local d = H.C.Divider({ w = 100, h = 1 }, host)
        local r, g, b, a = d._line:GetColorTexture()
        H.expectTokenColor({ r, g, b, a }, "colorBorder")
    end)

    it("spans the full width and centres the line vertically", function()
        local d = H.mount(H.C.Divider({ w = 100, h = 20 }, host))
        H.expectSize(d._line, 100, H.token("borderWidth"))
        H.expectCenteredV(d._line, d:GetFrame())
    end)

    it("spans the full height and centres a vertical line", function()
        local d = H.mount(H.C.Divider({ dir = "vertical", w = 20, h = 100 }, host))
        H.expectSize(d._line, H.token("borderWidth"), 100)
        H.expectCenteredH(d._line, d:GetFrame())
    end)

    it("centres an optional label", function()
        local d = H.mount(H.C.Divider({ w = 200, h = 20, label = "Section" }, host))
        expect(d._label).notNil()
        H.expectCenteredH(d._label, d:GetFrame())
        H.expectCenteredV(d._label, d:GetFrame())
    end)

    it("creates no label for an empty string", function()
        local d = H.C.Divider({ w = 200, h = 20, label = "" }, host)
        expect(d._label).isNil()
    end)

    it("styles the label with the small font and muted colour", function()
        local d = H.C.Divider({ w = 200, h = 20, label = "Section" }, host)
        local _, size = d._label:GetFont()
        expect(size).eq(H.token("fontSizeSm"))
        local r, g, b, a = d._label:GetTextColor()
        H.expectTokenColor({ r, g, b, a }, "colorTextMuted")
    end)

    it("re-measures its label when the font size token grows", function()
        local d = H.mount(H.C.Divider({ w = 200, h = 40, label = "Section" }, host))
        local before = d._label:GetWidth()
        H.T:CreateUserTheme("Big", "Modern")
        H.T:SetUserToken("Big", "fontSizeSm", 26)
        H.T:SetActive("Big")
        expect(d._label:GetWidth()).as("a bigger font needs a wider box").gt(before)
        H.expectSize(d._label, H.textBox("Section", 26), H.lineHeight(26))
        H.expectTextNotClipped(d._label)
        H.expectCenteredH(d._label, d:GetFrame())
    end)

    it("re-measures its label when SetText lengthens it", function()
        local d = H.mount(H.C.Divider({ w = 200, h = 40, label = "A" }, host))
        d:SetText("A much longer section title")
        H.expectSize(d._label,
            H.textBox("A much longer section title", H.token("fontSizeSm")), nil)
        H.expectTextNotClipped(d._label)
    end)

    it("emits TEXT_CHANGED from SetText when a label exists", function()
        local d = H.C.Divider({ w = 200, h = 20, label = "A" }, host)
        local spy = H.signalSpy(d, H.S.SIGNALS.TEXT_CHANGED)
        d:SetText("B")
        expect(spy.count).eq(1)
        expect(d._label:GetText()).eq("B")
    end)

    it("ignores SetText when there is no label", function()
        local d = H.C.Divider({ w = 200, h = 1 }, host)
        local spy = H.signalSpy(d, H.S.SIGNALS.TEXT_CHANGED)
        expect(function() d:SetText("B") end).notThrows()
        expect(spy.count).eq(0)
    end)

    -- Divider does not expose SetEnabled — it is not a control. Dependency.lua's guard
    -- (`if target.SetEnabled`) correctly skips it.
    it("does not expose SetEnabled", function()
        local d = H.C.Divider({ w = 200, h = 1 }, host)
        expect(d.SetEnabled).as("Divider is not a control; Dependency skips it").isNil()
    end)

    it("emits SIZE_CHANGED once from an explicit resize", function()
        local d = H.C.Divider({ w = 200, h = 1 }, host)
        local spy = H.signalSpy(d, H.S.SIGNALS.SIZE_CHANGED)
        d:SetSize(120, 2)
        expect(spy.count).eq(1)
        expect(spy:arg(1)).eq(120)
    end)

    it("emits SIZE_CHANGED when a parent layout resizes it", function()
        local col = H.Layout:CreateContainer({ parent = host, layout = "flow", dir = "vertical" })
        local d = H.C.Divider({ w = 10, h = 1 }, col:GetFrame())
        local spy = H.signalSpy(d, H.S.SIGNALS.SIZE_CHANGED)
        col:Add(d, { width = "fill", height = 1 })
        expect(spy.count).gte(1)
        H.expectSize(d, 300, 1)
    end)
end)

-- Rounding is opt-in per surface, because turning it on by default would restyle every panel in the
-- addon at once and a full-bleed strip like the data bar wants square corners against the screen edge.
describe("Components/Frame rounded", function()
    local host
    before_each(function()
        H.setup()
        host = H.mountHost and H.mountHost() or H.SuuUI.UIRoot:GetRootContainer():GetFrame()
    end)

    it("is square by default, drawn with a backdrop", function()
        local f = H.C.Frame({ w = 60, h = 40 }, host)
        expect(f._panel).as("no panel unless asked for").eq(nil)
        expect(f:GetFrame().GetBackdrop and f:GetFrame():GetBackdrop() ~= nil)
            .as("a plain frame keeps its backdrop").truthy()
    end)

    it("draws a rounded surface when asked, and NEVER applies a backdrop as well", function()
        local f = H.C.Frame({ w = 60, h = 40, rounded = true }, host)
        expect(f._panel).as("a panel handle was built").truthy()
        -- A backdrop's corners are its texture's corners, so applying one as well would show square
        -- corners through the rounding. Asserting GetBackdrop() here was VACUOUS -- the simulated
        -- client answers nil either way, so the test passed with the guard removed. Counting the call
        -- is what actually discriminates, and it pins the load-bearing half: the ApplyTheme branch.
        local calls, real = 0, H.SuuUI.Backdrop.Apply
        H.SuuUI.Backdrop.Apply = function(...) calls = calls + 1 return real(...) end
        f:ApplyTheme()
        H.SuuUI.Backdrop.Apply = real
        expect(calls).as("a rounded surface must not also get a square backdrop").eq(0)
    end)

    it("still applies a backdrop for a square frame", function()
        local f = H.C.Frame({ w = 60, h = 40 }, host)
        local calls, real = 0, H.SuuUI.Backdrop.Apply
        H.SuuUI.Backdrop.Apply = function(...) calls = calls + 1 return real(...) end
        f:ApplyTheme()
        H.SuuUI.Backdrop.Apply = real
        expect(calls).as("the square path is the one that uses a backdrop").gte(1)
    end)

    it("recolours the rounded surface on a theme change rather than rebuilding it", function()
        local f = H.C.Frame({ w = 60, h = 40, rounded = true }, host)
        local panel = f._panel
        H.SuuUI.Theme:SetActive("Default")
        expect(f._panel).as("same panel handle after a restyle").eq(panel)
    end)

    it("frees the panel on Destroy", function()
        local f = H.C.Frame({ w = 60, h = 40, rounded = true }, host)
        f:Destroy()
        expect(f:IsShown()).falsy()
    end)
end)
