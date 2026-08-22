local H = require("harness")

-- Components/DataField.lua -- a muted prefix and a value in ONE font string, with an
-- accent rail on hover.
--
-- Four things in it are load-bearing, and every one is a CONSEQUENCE rather than a stored
-- flag, so each is asserted here through what it produced and named in the message:
--
--   * ONE font string carrying an inline |cff escape, not two font strings at two sizes.
--     The muted colour is therefore BAKED INTO THE STRING, so a colorTextMuted change
--     reaches the screen only by RECOMPOSING it -- restyling the font cannot.
--   * TextMetrics.Box, not Measure. The label is a STRETCHED stack child, so the insets
--     the field subtracts are handed straight back to it and its own box lands at exactly
--     the metric -- where the client truncates with zero tolerance and draws an ellipsis.
--     A spec that only checked the NUMBER would pass while the client rendered "Play..."
--     for "Player", so every width assertion here is paired with expectLabelClears --
--     which is H.expectTextNotClipped PLUS the full-line comparison the helper is blind
--     to. See its comment: the helper alone does not catch this component's failure mode.
--   * the unchanged-value guard in SetText. The field is rewritten on every tick of the
--     shared ticker and usually says exactly what it said last time; re-measuring and
--     re-laying out for that would be the whole cost of the bar.
--   * the frame's own OnSizeChanged. A parent layout resizes the FRAME and never calls
--     the handle's SetSize, so that script is the only place a layout-driven resize is
--     seen, and the only route by which SIZE_CHANGED reaches the bar.
describe("Components.DataField", function()
    local host
    before_each(function()
        H.setup()
        host = H.parent(400, 200)
    end)

    ------------------------------------------------------------------------------
    -- Derivations. Every expected number in this file comes from one of these, from
    -- H.token / H.textBox / H.controlHeight, or from another widget's measured box.
    ------------------------------------------------------------------------------

    -- The inset the field pads with AND lays the label out with -- the same token on both
    -- sides, which is exactly why Box rather than Measure is the right metric.
    local function pad()   return H.token("spaceMd") end

    -- Floored against the font metrics, not the raw token: a field holding text must not
    -- be pinned to a height its own glyphs outgrow.
    local function rowH()  return H.controlHeight("sizeRow") end

    -- The rail is floored at one physical pixel: a rail that rounds away is the only cue
    -- that the field can be interacted with.
    local function rail()  return H.SuuUI.Pixel.Line(H.token("sizeRail")) end

    local function muted() return H.T:GetColorCode("colorTextMuted") end

    -- The string the component builds: muted prefix, reset, one space, value. The
    -- separator can only be a space because one font string has one font.
    local function composed(prefix, value)
        prefix, value = prefix or "", value or ""
        if prefix == "" then return value end
        if value == "" then return muted() .. prefix .. "|r" end
        return muted() .. prefix .. "|r " .. value
    end

    -- The rule _autosize states: the composed string's BOX plus the spaceMd inset on each
    -- side, measured at the font actually in force -- so this moves with a font token
    -- edit or a face swap instead of pinning today's pixels.
    local function hugWidth(field)
        local path, size = H.fontOf(field._label)
        return H.textBox(field._label:GetText() or "", size, path) + 2 * pad()
    end

    local function railColor(field)
        local r, g, b, a = field._railTex:GetColorTexture()
        if r == nil then return nil end
        return { r, g, b, a }
    end

    -- "The label is not cut off", asserted twice, because one of the two is blind here.
    --
    -- H.expectTextNotClipped is the sanctioned helper and is kept, but with word wrap on
    -- it compares the box against the widest WORD (the client can only re-flow between
    -- words), so a shortfall in LINE width registers only once a whole word re-flows onto
    -- a second line. A one-pixel shortfall never does that, and every prefixed field is a
    -- multi-word string -- so on its own the helper passes whether the field measured Box
    -- or Measure. Verified: swapping Box for Measure fails 14 assertions in this file and
    -- not one of them is a clip.
    --
    -- So the invariant is also stated directly, the way TESTING.md words it: the client
    -- truncates the whole line with zero tolerance, so a box AT the bare metric IS a clip
    -- and the label's own box has to CLEAR it.
    local function expectLabelClears(f)
        H.expectTextNotClipped(f._label)
        local path, size = H.fontOf(f._label)
        local text = f._label:GetText() or ""
        if text == "" then return end
        expect(H.box(f._label).width)
            .as("the label's box must CLEAR the full-line metric, not sit at it")
            .gt(H.textWidth(text, size, path))
    end

    -- The field pads its own width by spaceMd and lays the label out with spaceMd, and the
    -- two have to be the SAME number or the label is off-centre by the difference. Checked
    -- after every token change as well as at construction: ApplyTheme re-states the inset
    -- separately from the width, so dropping one of the two leaves the frame growing while
    -- the label keeps the old padding -- and every width assertion still passes.
    local function expectLabelInsets(f)
        local fb, lb = H.box(f), H.box(f._label)
        expect(lb.left - fb.left).as("left inset is spaceMd").eq(pad())
        expect(fb.right - lb.right).as("right inset is the same spaceMd").eq(pad())
    end

    -- Mounted: positions inside a field are asserted throughout this file, and a
    -- component never positions itself.
    local function field(props)
        return H.mount(H.C.DataField(props or {}, host))
    end

    -- A field laid out the way the data bar lays one out: a stretched child of a
    -- horizontal flow row, so its height is the row's and never its own.
    local function inRow(props, rowH_)
        local row = H.Layout:CreateContainer({
            parent = host, layout = "flow", dir = "horizontal", w = 300, h = rowH_ or 40,
        })
        local f = H.C.DataField(props or {}, row:GetFrame())
        row:Add(f, { align = "stretch" })
        return f, row
    end

    ------------------------------------------------------------------------------
    describe("construction and defaults", function()
        it("takes its height from the sizeRow control height", function()
            local f = field({ prefix = "HP", text = "100" })
            H.expectSize(f, nil, rowH())
        end)

        it("draws the rail by default, but only once hovered", function()
            local f = field({ prefix = "HP", text = "100" })
            expect(f._rail).as("rail defaults on").truthy()
            expect(f._railTex:IsShown()).as("at rest there is nothing to afford").falsy()
        end)

        it("props.rail = false opts the field out of the rail entirely", function()
            local f = field({ prefix = "HP", text = "100", rail = false })
            expect(f._rail).falsy()
        end)

        it("the prefix is optional and defaults to none", function()
            local f = field({ text = "100" })
            expect(f:GetPrefix()).eq("")
            expect(f._label:GetText()).eq("100")
        end)

        it("paints nothing at rest, so it never seams against the bar beneath it", function()
            local f = field({ prefix = "HP", text = "100" })
            expect(H.backdropColor(f)[4]).as("fully transparent, not a second panel").eq(0)
        end)

        it("starts enabled and mouse-enabled", function()
            local f = field({ prefix = "HP", text = "100" })
            expect(f:IsEnabled()).truthy()
            expect(f:GetFrame():IsMouseEnabled()).truthy()
        end)

        it("hugs its own text when no width is given", function()
            local f = field({ prefix = "HP", text = "100" })
            H.expectSize(f, hugWidth(f), nil)
        end)
    end)

    ------------------------------------------------------------------------------
    describe("the composed string", function()
        it("carries the muted colour escape when a prefix is set", function()
            local f = field({ prefix = "HP", text = "100" })
            local text = f._label:GetText()
            expect(text).as("the prefix's colour is baked in as an escape")
                .contains(H.T:GetColorCode("colorTextMuted"))
            expect(text).as("and closed again before the value").contains("|r")
            expect(text).eq(composed("HP", "100"))
        end)

        it("carries no escape at all when there is no prefix", function()
            local f = field({ text = "100" })
            local text = f._label:GetText()
            expect(text:find(H.T:GetColorCode("colorTextMuted"), 1, true))
                .as("nothing is muted, so nothing is coloured").isNil()
            expect(text:find("|c", 1, true)).as("no escape of any kind").isNil()
            expect(text).eq("100")
        end)

        it("GetText returns the value alone, without the prefix or the escape", function()
            local f = field({ prefix = "HP", text = "100" })
            expect(f:GetText()).eq("100")
            expect(f:GetText():find("HP", 1, true)).as("no prefix").isNil()
            expect(f:GetText():find("|c", 1, true)).as("no escape").isNil()
        end)

        it("SetPrefix recomposes the string rather than adding a second one", function()
            local f = field({ text = "100" })
            f:SetPrefix("HP")
            expect(f._label:GetText()).eq(composed("HP", "100"))
            expect(f:GetPrefix()).eq("HP")
            expect(f:GetText()).as("the value is untouched").eq("100")
        end)

        it("SetPrefix('') drops the escape again", function()
            local f = field({ prefix = "HP", text = "100" })
            f:SetPrefix("")
            expect(f._label:GetText()).eq("100")
            expect(f._label:GetText():find("|c", 1, true)).isNil()
        end)

        it("SetText recomposes, keeping the prefix and its escape", function()
            local f = field({ prefix = "HP", text = "100" })
            f:SetText("4321")
            expect(f._label:GetText()).eq(composed("HP", "4321"))
            expect(f:GetText()).eq("4321")
        end)

        it("an empty value with a prefix composes without a trailing separator", function()
            local f = field({ prefix = "HP", text = "" })
            expect(f._label:GetText()).eq(muted() .. "HP" .. "|r")
        end)
    end)

    ------------------------------------------------------------------------------
    describe("hugging geometry", function()
        it("is exactly its text's box plus the spaceMd inset on each side", function()
            local f = field({ prefix = "HP", text = "100" })
            local path, size = H.fontOf(f._label)
            H.expectSize(f, H.textBox(composed("HP", "100"), size, path) + 2 * pad(), nil)
        end)

        it("leaves the label uncut -- the whole reason it measures Box, not Measure", function()
            -- A single-word field first: with no prefix there is no space, so the widest
            -- word IS the whole line and H.expectTextNotClipped is sensitive to the one
            -- pixel Box adds. This is the case that makes the helper bite.
            local plain = field({ text = "Player" })
            expectLabelClears(plain)

            -- Then the real shape, a prefixed field. Two words, so the helper alone is
            -- blind and the direct metric comparison in expectLabelClears is what holds.
            local f = field({ prefix = "Rested", text = "Player" })
            expectLabelClears(f)
            H.expectInside(f._label, f:GetFrame())
        end)

        it("hands the label back exactly the inset it padded with", function()
            local f = field({ prefix = "HP", text = "100" })
            expectLabelInsets(f)
        end)

        it("re-hugs on every value change, uncut at each width", function()
            local f = field({ prefix = "HP", text = "1" })
            for _, v in ipairs({ "12", "123456", "1234567890123", "9" }) do
                f:SetText(v)
                H.expectSize(f, hugWidth(f), nil)
                expectLabelClears(f)
            end
        end)

        it("floors the width at minW when the text is narrower", function()
            local f = field({ prefix = "HP", text = "1", minW = 200 })
            H.expectSize(f, 200, nil)
            expect(hugWidth(f)).as("the text alone would be narrower").lt(200)
            expectLabelClears(f)
        end)

        it("minW is a floor, not a width: wider text still wins", function()
            local floorW = 2 * pad() + 4
            local f = field({ prefix = "HP", text = "a value long enough to pass the floor",
                              minW = floorW })
            expect(hugWidth(f)).gt(floorW)
            H.expectSize(f, hugWidth(f), nil)
            expectLabelClears(f)
        end)

        it("collapses to the insets alone when there is no text at all", function()
            local f = field({})
            H.expectSize(f, 2 * pad(), nil)
        end)

        it("measures an escape-bearing string exactly as wide as the plain text", function()
            -- The width rule rests on this: the field measures the COMPOSED string, so if
            -- the escape counted toward the metric every prefixed field would be padded by
            -- ten invisible glyphs. Both the harness model and the addon's own metric have
            -- to agree, because the spec's expectation is computed with one and the
            -- component's width with the other.
            local f = field({ prefix = "HP", text = "100" })
            local path, size = H.fontOf(f._label)
            local withEscape, plain = composed("HP", "100"), "HP 100"
            expect(withEscape).as("the two strings really do differ").neq(plain)
            expect(H.textBox(withEscape, size, path))
                .as("the harness font model strips colour escapes")
                .eq(H.textBox(plain, size, path))
            local addonEsc   = H.SuuUI.TextMetrics.Box(withEscape, path, size, "")
            local addonPlain = H.SuuUI.TextMetrics.Box(plain, path, size, "")
            expect(addonEsc).as("and so does the client the addon measures against")
                .eq(addonPlain)
            H.expectSize(f, addonEsc + 2 * pad(), nil)
        end)
    end)

    ------------------------------------------------------------------------------
    describe("token-driven sizing", function()
        it("re-derives its width when fontSizeMd grows", function()
            local f = field({ prefix = "HP", text = "100" })
            local before = f:GetWidth()
            local grown  = H.token("fontSizeMd") + 9

            H.T:CreateUserTheme("BigFont", "Modern")
            H.T:SetUserToken("BigFont", "fontSizeMd", grown)
            H.T:SetActive("BigFont")

            local path, size = H.fontOf(f._label)
            expect(size).as("the label actually took the new step").eq(grown)
            expect(f:GetWidth()).as("a font token edit moves a hugging field")
                .gt(before)
            H.expectSize(f, H.textBox(f._label:GetText(), size, path) + 2 * pad(), nil)
            expectLabelInsets(f)
        end)

        it("the label is still uncut after the font grows", function()
            -- The payoff of Box over Measure: the field re-measures and the label's own
            -- box clears the new metric, rather than keeping a stale width and rendering
            -- an ellipsis.
            local f = field({ prefix = "Rested", text = "Player" })
            H.T:CreateUserTheme("BigFont", "Modern")
            H.T:SetUserToken("BigFont", "fontSizeMd", H.token("fontSizeMd") + 9)
            H.T:SetActive("BigFont")
            expectLabelClears(f)
        end)

        it("re-derives its width when spaceMd grows", function()
            local f = field({ prefix = "HP", text = "100" })
            local before = f:GetWidth()
            local grown  = H.token("spaceMd") + 6

            H.T:CreateUserTheme("WidePad", "Modern")
            H.T:SetUserToken("WidePad", "spaceMd", grown)
            H.T:SetActive("WidePad")

            expect(pad()).eq(grown)
            expect(f:GetWidth()).eq(before + 2 * 6)
            H.expectSize(f, hugWidth(f), nil)
            -- The frame widening is only half of it: the label has to be laid out with the
            -- new inset too, or the field grows around a label that stayed where it was.
            expectLabelInsets(f)
            expectLabelClears(f)
        end)

        it("the rail's thickness follows sizeRail", function()
            local f = field({ prefix = "HP", text = "100" })
            H.hover(f)
            expect(H.box(f._railTex).height).eq(rail())

            local grown = H.token("sizeRail") + 4
            H.T:CreateUserTheme("FatRail", "Modern")
            H.T:SetUserToken("FatRail", "sizeRail", grown)
            H.T:SetActive("FatRail")

            expect(rail()).eq(grown)
            expect(H.box(f._railTex).height).as("the rail re-derives from the token")
                .eq(rail())
        end)

        it("re-derives its own height when the font outgrows it", function()
            -- The height counterpart of the width hug, and it exists for the same reason:
            -- font tokens are user-editable, so a height taken once at construction goes
            -- stale and the glyphs hang out of the box unclipped. On the bar this never bit,
            -- because the field is a stretched child and the bar drives its height --
            -- standalone it did, which is why the component owns it now rather than the
            -- header comment claiming a caller always will.
            local f = field({ prefix = "HP", text = "100" })
            local built = f:GetHeight()
            expect(built).eq(rowH())

            H.T:CreateUserTheme("HugeFont", "Modern")
            H.T:SetUserToken("HugeFont", "fontSizeMd", 40)
            H.T:SetActive("HugeFont")

            expect(f:GetHeight()).as("the field grew with the font").gt(built)
            -- The inverse of the edge comparison this used to pin: the label is contained
            -- again, so expectInside is the right tool once more.
            H.expectInside(f._label, f:GetFrame())
        end)

        it("never wraps its label onto a second line", function()
            -- A field is one line by construction. With the client's default of wrap ON, a box
            -- one pixel short does not truncate visibly -- it breaks a word onto a second line
            -- that a one-line-tall field then hides, so the value goes silently wrong instead
            -- of visibly clipped. It is also what makes the clip check exact: with wrap on the
            -- width a string is judged against is the widest WORD, so a full-line shortfall
            -- registers as no clip at all.
            local narrow = field({ prefix = "GUILD", text = "12 online now" })
            narrow:SetSize(40, rowH())          -- far narrower than the text could ever need
            -- GetNumLines recomputes against the CURRENT bound, which is what makes this
            -- discriminating. The label's GetHeight does not: Text measures on SetText and on
            -- ApplyTheme, so a height computed unbounded at construction survives a
            -- layout-driven width change and reports one line either way.
            expect(narrow._label:GetNumLines())
                .as("one line at a width that could not possibly fit the text")
                .eq(1)
            expect(narrow._label:CanWordWrap())
                .as("wrap is off, which is what makes that true").falsy()
        end)

        xit("a standalone field re-derives its own height when the font outgrows it", function()
            -- What the two assertions above add up to: after fontSizeMd goes from 13 to 40
            -- the label is a full line taller than the box holding it, so
            -- H.expectInside(f._label, f:GetFrame()) fails and the glyphs draw over
            -- whatever sits below. On the data bar this is harmless -- the field is
            -- stretched and the bar re-derives from GetControlHeight -- which is why it is
            -- pinned rather than fixed here.
            --
            -- Two ways to settle it, and the choice is a design decision:
            --   (a) ApplyTheme re-applies GetControlHeight("sizeRow") whenever the field
            --       still owns its height (no layout has resized it). Needs a flag
            --       mirroring _autoW for the vertical axis -- call it _autoH -- cleared by
            --       the same SetSize that clears _autoW.
            --   (b) leave the height to layouts, and make it the CALLER's contract that a
            --       DataField is always laid out. That is what the header comment already
            --       says, in which case the fix is a doc line and a bar-level spec.
            -- (a) matches how every other text-bearing component behaves; (b) matches what
            -- this file says. Someone has to pick.
        end)
    end)

    ------------------------------------------------------------------------------
    describe("layout integration", function()
        it("is exactly as tall as the row that stretches it", function()
            local f, row = inRow({ prefix = "HP", text = "100" }, 40)
            expect(f:GetHeight()).eq(row:GetFrame():GetHeight())
            H.expectSize(f, nil, 40)
        end)

        it("keeps hugging on the main axis while stretching on the cross axis", function()
            local f = inRow({ prefix = "HP", text = "100" }, 40)
            H.expectSize(f, hugWidth(f), 40)
            expectLabelClears(f)
        end)

        it("emits SIZE_CHANGED when the parent resizes it", function()
            local f, row = inRow({ prefix = "HP", text = "100" }, 40)
            local spy = H.signalSpy(f, H.S.SIGNALS.SIZE_CHANGED)
            row:GetFrame():SetHeight(64)
            expect(spy.count).as("the frame's own OnSizeChanged is the only route").gte(1)
            expect(spy:arg(1)).near(f:GetWidth(), 1)
            expect(spy:arg(2)).eq(64)
            H.expectSize(f, nil, 64)
        end)

        it("a parent-driven resize does not cost the field its hug", function()
            -- The proof that the resize never went through the handle's SetSize: that
            -- method is what clears _autoW, so a field that still re-hugs afterwards was
            -- resized on its frame.
            local f, row = inRow({ prefix = "HP", text = "1" }, 40)
            row:GetFrame():SetHeight(64)
            f:SetText("a much longer value")
            H.expectSize(f, hugWidth(f), 64)
            expectLabelClears(f)
        end)

        it("the label re-fits after a parent-driven resize", function()
            local f, row = inRow({ prefix = "Rested", text = "Player" }, 40)
            row:GetFrame():SetHeight(64)
            expectLabelClears(f)
            H.expectInside(f._label, f:GetFrame())
        end)

        it("sits in the row beside its neighbours without overlapping them", function()
            local row = H.Layout:CreateContainer({
                parent = host, layout = "flow", dir = "horizontal",
                w = 380, h = 40, gap = H.token("spaceSm"),
            })
            local a = H.C.DataField({ prefix = "HP", text = "100" }, row:GetFrame())
            local b = H.C.DataField({ prefix = "MP", text = "50" }, row:GetFrame())
            row:Add(a, { align = "stretch" })
            row:Add(b, { align = "stretch" })
            H.expectRowHorizontally({ a, b }, H.token("spaceSm"))
            H.expectNoOverlap({ a, b })
            expectLabelClears(a)
            expectLabelClears(b)
        end)
    end)

    ------------------------------------------------------------------------------
    describe("hover", function()
        it("paints colorBgHover and shows the rail together", function()
            local f = field({ prefix = "HP", text = "100" })
            H.hover(f)
            expect(f:IsHovered()).truthy()
            H.expectTokenColor(H.backdropColor(f), "colorBgHover")
            expect(f._railTex:IsShown()).truthy()
        end)

        it("MOUSE_LEAVE clears both the surface and the rail", function()
            local f = field({ prefix = "HP", text = "100" })
            H.hover(f)
            H.unhover(f)
            expect(f:IsHovered()).falsy()
            expect(H.backdropColor(f)[4]).as("back to painting nothing").eq(0)
            expect(f._railTex:IsShown()).as("the rail cannot outlive the hover").falsy()
        end)

        it("rail = false suppresses the rail while hover still paints the surface", function()
            local f = field({ prefix = "HP", text = "100", rail = false })
            H.hover(f)
            H.expectTokenColor(H.backdropColor(f), "colorBgHover")
            expect(f._railTex:IsShown()).as("a field with no hover behaviour affords none")
                .falsy()
        end)

        it("SetRail(false) hides a rail that is already showing", function()
            local f = field({ prefix = "HP", text = "100" })
            H.hover(f)
            expect(f._railTex:IsShown()).truthy()
            f:SetRail(false)
            expect(f._railTex:IsShown()).falsy()
            f:SetRail(true)
            expect(f._railTex:IsShown()).as("and brings it back while still hovered").truthy()
        end)

        it("the rail is the accent colour, along the bottom edge, full width", function()
            local f = field({ prefix = "HP", text = "100" })
            H.hover(f)
            H.expectTokenColor(railColor(f), "colorAccent")
            local fb, rb = H.box(f), H.box(f._railTex)
            expect(rb.bottom).eq(fb.bottom)
            expect(rb.width).eq(fb.width)
            H.expectInside(f._railTex, f:GetFrame())
        end)
    end)

    ------------------------------------------------------------------------------
    describe("signals", function()
        it("emits CLICKED once per click, carrying the button", function()
            local f = field({ prefix = "HP", text = "100" })
            local spy = H.signalSpy(f, H.S.SIGNALS.CLICKED)
            expect(H.click(f)).truthy()
            expect(spy.count).eq(1)
            expect(spy:arg(1)).eq("LeftButton")
            expect(H.click(f, "RightButton")).truthy()
            expect(spy.count).eq(2)
            expect(spy:arg(1)).eq("RightButton")
            expect(spy:arg(1, 1)).as("the first payload is untouched").eq("LeftButton")
        end)

        it("emits MOUSE_ENTER and MOUSE_LEAVE once each, with no payload", function()
            local f = field({ prefix = "HP", text = "100" })
            local enter = H.signalSpy(f, H.S.SIGNALS.MOUSE_ENTER)
            local leave = H.signalSpy(f, H.S.SIGNALS.MOUSE_LEAVE)
            H.hover(f)
            expect(enter.count).eq(1)
            expect(enter.last.n).eq(0)
            expect(leave.count).eq(0)
            H.unhover(f)
            expect(enter.count).eq(1)
            expect(leave.count).eq(1)
            expect(leave.last.n).eq(0)
        end)

        it("emits TEXT_CHANGED once, carrying the value alone", function()
            local f = field({ prefix = "HP", text = "100" })
            local spy = H.signalSpy(f, H.S.SIGNALS.TEXT_CHANGED)
            f:SetText("4321")
            expect(spy.count).eq(1)
            expect(spy:arg(1)).as("the value, not the composed string").eq("4321")
            expect(spy.last.n).eq(1)
        end)

        it("SetText with an unchanged value emits nothing and does not resize", function()
            -- Load-bearing: a readout is rewritten on every game event and every tick of
            -- the shared ticker, and usually says exactly what it said last time.
            local f = field({ prefix = "HP", text = "100" })
            local text = H.signalSpy(f, H.S.SIGNALS.TEXT_CHANGED)
            local size = H.signalSpy(f, H.S.SIGNALS.SIZE_CHANGED)
            local inner = H.signalSpy(f._labelText, H.S.SIGNALS.TEXT_CHANGED)
            local before = f:GetWidth()

            for _ = 1, 20 do f:SetText("100") end

            expect(text.count).as("nothing changed, so nothing is announced").eq(0)
            expect(size.count).as("and nothing is re-laid-out").eq(0)
            expect(inner.count).as("the font string is not even rewritten").eq(0)
            expect(f:GetWidth()).eq(before)
        end)

        it("a value that changes the width emits SIZE_CHANGED as well", function()
            local f = field({ prefix = "HP", text = "1" })
            local text = H.signalSpy(f, H.S.SIGNALS.TEXT_CHANGED)
            local size = H.signalSpy(f, H.S.SIGNALS.SIZE_CHANGED)
            f:SetText("1234567890")
            expect(text.count).eq(1)
            expect(size.count).as("the hug moved, so the bar has to re-flow").gte(1)
            expect(f:GetWidth()).eq(hugWidth(f))
        end)

        it("a value of the same width emits TEXT_CHANGED but no resize", function()
            local f = field({ prefix = "HP", text = "100" })
            local text = H.signalSpy(f, H.S.SIGNALS.TEXT_CHANGED)
            local size = H.signalSpy(f, H.S.SIGNALS.SIZE_CHANGED)
            f:SetText("999")
            expect(text.count).eq(1)
            expect(size.count).as("same glyph count, same box").eq(0)
        end)

        it("SetPrefix is silent: it changes configuration, not the value", function()
            local f = field({ text = "100" })
            local spy = H.signalSpy(f, H.S.SIGNALS.TEXT_CHANGED)
            f:SetPrefix("HP")
            expect(spy.count).as("TEXT_CHANGED carries the VALUE, which did not move").eq(0)
            expect(f._label:GetText()).as("the string was still recomposed")
                .eq(composed("HP", "100"))
        end)

        it("SetPrefix still resizes, so the bar re-flows around it", function()
            local f = field({ text = "100" })
            local spy = H.signalSpy(f, H.S.SIGNALS.SIZE_CHANGED)
            f:SetPrefix("Health")
            expect(spy.count).gte(1)
            expect(f:GetWidth()).eq(hugWidth(f))
        end)

        it("SetPrefix with an unchanged prefix does not resize either", function()
            -- The same guard as SetText's, for the same reason: ApplyTheme and the bar both
            -- re-state a field's prefix, and a re-layout per re-statement is not free.
            --
            -- Watched on the INNER Text handle, not on the field: an unchanged prefix
            -- produces an unchanged string, so the field's own SIZE_CHANGED stays silent
            -- either way and a spy on the field alone cannot tell the guard from its
            -- absence. What the guard actually buys is the font string not being rewritten.
            local f = field({ prefix = "HP", text = "100" })
            local outer = H.signalSpy(f, H.S.SIGNALS.SIZE_CHANGED)
            local inner = H.signalSpy(f._labelText, H.S.SIGNALS.TEXT_CHANGED)
            local before = f:GetWidth()

            for _ = 1, 10 do f:SetPrefix("HP") end

            expect(inner.count).as("the font string is never rewritten").eq(0)
            expect(outer.count).eq(0)
            expect(f:GetWidth()).eq(before)
        end)

        it("SetRail emits nothing", function()
            local f = field({ prefix = "HP", text = "100" })
            local text = H.signalSpy(f, H.S.SIGNALS.TEXT_CHANGED)
            local size = H.signalSpy(f, H.S.SIGNALS.SIZE_CHANGED)
            f:SetRail(false)
            f:SetRail(true)
            expect(text.count).eq(0)
            expect(size.count).eq(0)
        end)

        it("emits SIZE_CHANGED from the handle's SetSize too", function()
            local f = field({ prefix = "HP", text = "100" })
            local spy = H.signalSpy(f, H.S.SIGNALS.SIZE_CHANGED)
            f:SetSize(120, 30)
            expect(spy.count).eq(1)
            expect(spy:arg(1)).eq(120)
            expect(spy:arg(2)).eq(30)
        end)

        it("emits ENABLED_CHANGED on SetEnabled", function()
            local f = field({ prefix = "HP", text = "100" })
            local spy = H.signalSpy(f, H.S.SIGNALS.ENABLED_CHANGED)
            f:SetEnabled(false)
            expect(spy.count).eq(1)
            expect(spy:arg(1)).eq(false)
            f:SetEnabled(true)
            expect(spy.count).eq(2)
            expect(spy:arg(1, 2)).eq(true)
        end)
    end)

    ------------------------------------------------------------------------------
    describe("disabled state", function()
        it("fades to opacityDisabled", function()
            local f = field({ prefix = "HP", text = "100" })
            f:SetEnabled(false)
            expect(f:GetFrame():GetAlpha()).eq(H.token("opacityDisabled"))
        end)

        it("the client stops routing input to it", function()
            local f = field({ prefix = "HP", text = "100" })
            local spy = H.signalSpy(f, H.S.SIGNALS.CLICKED)
            f:SetEnabled(false)
            expect(f:GetFrame():IsMouseEnabled()).falsy()
            expect(H.click(f)).as("a disabled field takes no click").falsy()
            expect(H.hover(f)).as("nor a hover").falsy()
            expect(spy.count).eq(0)
        end)

        it("its own guard holds even when the scripts are fired directly", function()
            local f = field({ prefix = "HP", text = "100" })
            local spy = H.signalSpy(f, H.S.SIGNALS.CLICKED)
            H.forceClick(f)
            expect(spy.count).as("enabled: the guard lets it through").eq(1)

            f:SetEnabled(false)
            H.forceClick(f)
            expect(spy.count).as("disabled: the handler's own check refuses it").eq(1)
        end)

        it("restores alpha and input when re-enabled", function()
            local f = field({ prefix = "HP", text = "100" })
            f:SetEnabled(false)
            f:SetEnabled(true)
            expect(f:GetFrame():GetAlpha()).eq(1)
            expect(f:GetFrame():IsMouseEnabled()).truthy()
            expect(H.click(f)).truthy()
        end)

        it("a live opacityDisabled edit reaches a field already disabled", function()
            local f = field({ prefix = "HP", text = "100" })
            f:SetEnabled(false)
            H.T:CreateUserTheme("Dim", "Modern")
            H.T:SetUserToken("Dim", "opacityDisabled", 0.25)
            H.T:SetActive("Dim")
            expect(f:GetFrame():GetAlpha()).eq(0.25)
        end)
    end)

    ------------------------------------------------------------------------------
    describe("theme reaction", function()
        it("REBUILDS the prefix's escape rather than restyling the font string", function()
            -- The whole point of one font string: colorTextMuted is baked into the string,
            -- so a token edit reaches the screen only by recomposing it. Restyling the
            -- font would leave the old colour on screen with every other assertion green.
            local f = field({ prefix = "HP", text = "100" })
            local was = f._label:GetText()

            H.T:CreateUserTheme("RedMuted", "Modern")
            H.T:SetUserToken("RedMuted", "colorTextMuted", { 1, 0, 0, 1 })
            H.T:SetActive("RedMuted")

            local now = muted()
            expect(now).as("the token really did move").eq("|cffff0000")
            expect(f._label:GetText()).as("the escape in the string is the NEW one")
                .contains(now)
            expect(f._label:GetText()).neq(was)
            expect(f._label:GetText()).eq(composed("HP", "100"))
        end)

        it("a field with no prefix gains no escape from a muted-colour edit", function()
            local f = field({ text = "100" })
            H.T:CreateUserTheme("RedMuted", "Modern")
            H.T:SetUserToken("RedMuted", "colorTextMuted", { 1, 0, 0, 1 })
            H.T:SetActive("RedMuted")
            expect(f._label:GetText()).eq("100")
        end)

        it("the rail is repainted from colorAccent on a theme switch", function()
            local f = field({ prefix = "HP", text = "100" })
            H.T:CreateUserTheme("GreenAccent", "Modern")
            H.T:SetUserToken("GreenAccent", "colorAccent", { 0, 1, 0, 1 })
            H.T:SetActive("GreenAccent")
            H.expectTokenColor(railColor(f), "colorAccent")
            expect(railColor(f)[2]).eq(1)
        end)

        it("a hovered field keeps its surface and rail across a theme switch", function()
            local f = field({ prefix = "HP", text = "100" })
            H.hover(f)
            H.T:CreateUserTheme("Other", "Modern")
            H.T:SetActive("Other")
            H.expectTokenColor(H.backdropColor(f), "colorBgHover")
            expect(f._railTex:IsShown()).as("ApplyTheme repaints from the hovered state")
                .truthy()
        end)

        it("does not error on a theme change after Destroy", function()
            local f = field({ prefix = "HP", text = "100" })
            f:Destroy()
            expect(function()
                H.T:CreateUserTheme("Post", "Modern")
                H.T:SetActive("Post")
            end).notThrows()
        end)
    end)

    ------------------------------------------------------------------------------
    describe("edge cases", function()
        it("an empty value leaves the prefix alone on screen, uncut", function()
            local f = field({ prefix = "HP", text = "" })
            expect(f:GetText()).eq("")
            H.expectSize(f, hugWidth(f), nil)
            expectLabelClears(f)
        end)

        it("an empty prefix is the same as none", function()
            local a = field({ prefix = "", text = "100" })
            expect(a._label:GetText()).eq("100")
            expect(a:GetPrefix()).eq("")
            H.expectSize(a, hugWidth(a), nil)
        end)

        it("neither prefix nor value: the insets and nothing else", function()
            local f = field({})
            expect(f:GetText()).eq("")
            expect(f:GetPrefix()).eq("")
            expect(f._label:GetText()).eq("")
            H.expectSize(f, 2 * pad(), rowH())
        end)

        it("clearing the value collapses the field back to its insets", function()
            local f = field({ text = "1234567890" })
            expect(f:GetWidth()).gt(2 * pad())
            f:SetText("")
            H.expectSize(f, 2 * pad(), nil)
        end)

        it("SetText(nil) is the empty string, not an error", function()
            local f = field({ text = "100" })
            expect(function() f:SetText(nil) end).notThrows()
            expect(f:GetText()).eq("")
        end)

        it("a pinned props.w opts out of hugging for good", function()
            local f = field({ prefix = "HP", text = "1", w = 200 })
            H.expectSize(f, 200, nil)
            f:SetText("a value far wider than two hundred pixels would ever hug to")
            H.expectSize(f, 200, nil)
            f:SetPrefix("Health")
            H.expectSize(f, 200, nil)
        end)

        it("a pinned props.w survives a font token edit", function()
            local f = field({ prefix = "HP", text = "100", w = 200 })
            H.T:CreateUserTheme("BigFont", "Modern")
            H.T:SetUserToken("BigFont", "fontSizeMd", H.token("fontSizeMd") + 9)
            H.T:SetActive("BigFont")
            H.expectSize(f, 200, nil)
        end)

        it("handle:SetSize opts a hugging field out from then on", function()
            local f = field({ prefix = "HP", text = "1" })
            expect(f:GetWidth()).eq(hugWidth(f))
            f:SetSize(150, 30)
            H.expectSize(f, 150, 30)
            f:SetText("a much longer value")
            H.expectSize(f, 150, nil)
        end)

        it("props.h pins the height instead of the sizeRow control height", function()
            local f = field({ prefix = "HP", text = "100", h = 50 })
            H.expectSize(f, nil, 50)
        end)
    end)

    ------------------------------------------------------------------------------
    describe("teardown", function()
        it("Destroy hides the frame", function()
            local f = field({ prefix = "HP", text = "100" })
            f:Destroy()
            expect(f:GetFrame():IsShown()).eq(false)
        end)

        it("every signal is disconnected", function()
            local f = field({ prefix = "HP", text = "100" })
            local size = H.signalSpy(f, H.S.SIGNALS.SIZE_CHANGED)
            local text = H.signalSpy(f, H.S.SIGNALS.TEXT_CHANGED)
            local click = H.signalSpy(f, H.S.SIGNALS.CLICKED)
            f:Destroy()
            size:reset(); text:reset(); click:reset()

            f:GetFrame():SetSize(80, 20)
            f:SetText("4321")
            H.forceClick(f)

            expect(size.count).as("no SIZE_CHANGED after Destroy").eq(0)
            expect(text.count).as("no TEXT_CHANGED after Destroy").eq(0)
            expect(click.count).as("no CLICKED after Destroy").eq(0)
        end)

        it("unsubscribes from SUUUI_THEME_CHANGED", function()
            -- A subscription that outlives the field would re-measure and resize it on the
            -- next theme edit, so the width standing still IS the unsubscription.
            local f = field({ prefix = "HP", text = "100" })
            f:Destroy()
            local width = f:GetFrame():GetWidth()
            local label = f._label:GetText()

            H.T:CreateUserTheme("BigFont", "Modern")
            H.T:SetUserToken("BigFont", "fontSizeMd", H.token("fontSizeMd") + 9)
            H.T:SetActive("BigFont")

            expect(f:GetFrame():GetWidth()).as("no re-measure after Destroy").eq(width)
            expect(f._label:GetText()).as("and no recompose either").eq(label)
        end)

        it("Destroy is safe to call twice", function()
            local f = field({ prefix = "HP", text = "100" })
            f:Destroy()
            expect(function() f:Destroy() end).notThrows()
        end)
    end)
end)
