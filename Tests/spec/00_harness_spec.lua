-- Self-tests for the harness itself. If these fail, every other spec is suspect.
local H = require("harness")

describe("harness: WoW API simulation", function()
    before_each(function() H.setup() end)

    describe("addon bootstrap", function()
        it("loads every file listed in the toc", function()
            expect(#require("harness.addon").readToc(H.root)).gte(50)
        end)

        it("creates the SuuUI namespace with all subsystems", function()
            local S = H.SuuUI
            expect(S.version).eq("0.1.0")
            for _, key in ipairs({ "Events", "UISignals", "Pool", "Profiles", "Settings",
                                   "Theme", "Plugins", "UIRoot", "Tween", "Anim",
                                   "Layout", "Components", "TextMetrics", "Utils" }) do
                expect(S[key]).as("SuuUI." .. key).notNil()
            end
        end)

        it("registers every component constructor", function()
            for _, name in ipairs({ "Frame", "Text", "ClickAway", "Button", "IconButton",
                                    "NavItem", "Toggle", "Slider", "Dropdown", "Input",
                                    "ColorSwatch", "ColorPicker", "KeyCapture",
                                    "ScrollFrame", "Tooltip", "Divider", "Modal", "Notice" }) do
                expect(type(H.C[name])).as("Components." .. name).eq("function")
            end
        end)

        it("boots profiles, theme and UI root from ADDON_LOADED", function()
            expect(H.SuuUI.Profiles:GetActiveName()).eq("Default")
            expect(H.T:GetActive()).eq("Modern")
            expect(H.SuuUI.UIRoot:GetRoot()).notNil()
        end)

        it("isolates state between setups", function()
            H.SuuUI.Settings:Register("iso_test", { { key = "a", type = "toggle", default = true } })
            H.setup()
            expect(H.SuuUI.Settings:GetSchema("iso_test")).isNil()
        end)
    end)

    describe("geometry solver", function()
        it("resolves a single anchor plus explicit size", function()
            local f = H.env.CreateFrame("Frame", nil, H.UIParent)
            f:SetSize(100, 50)
            f:SetPoint("TOPLEFT", H.UIParent, "TOPLEFT", 10, -20)
            H.expectBox(f, { left = 10, top = 20, width = 100, height = 50 })
        end)

        it("derives size from two opposing anchors", function()
            local p = H.parent(200, 100)
            local f = H.env.CreateFrame("Frame", nil, p)
            f:SetPoint("TOPLEFT", p, "TOPLEFT", 5, -5)
            f:SetPoint("BOTTOMRIGHT", p, "BOTTOMRIGHT", -15, 25)
            H.expectSize(f, 180, 70)
        end)

        it("treats SetAllPoints as a pair of corner anchors", function()
            local p = H.parent(120, 60)
            local f = H.env.CreateFrame("Frame", nil, p)
            f:SetAllPoints(p)
            H.expectSize(f, 120, 60)
            H.expectOffset(f, p, 0, 0)
        end)

        it("returns nil edges for an unanchored frame but keeps the set size", function()
            local f = H.env.CreateFrame("Frame", nil, H.UIParent)
            f:ClearAllPoints()
            f:SetSize(30, 40)
            expect(f:GetLeft()).isNil()
            expect(f:GetWidth()).eq(30)
            expect(f:GetHeight()).eq(40)
        end)

        it("resolves CENTER anchors against the midpoint", function()
            local f = H.env.CreateFrame("Frame", nil, H.UIParent)
            f:SetSize(100, 100)
            f:SetPoint("CENTER", H.UIParent, "CENTER", 0, 0)
            local box = H.box(f)
            expect(box.left).eq(1024 / 2 - 50)
            expect(box.top).eq(768 / 2 - 50)
        end)

        it("replaces an anchor that reuses the same point name", function()
            local f = H.env.CreateFrame("Frame", nil, H.UIParent)
            f:SetSize(10, 10)
            f:SetPoint("TOPLEFT", H.UIParent, "TOPLEFT", 0, 0)
            f:SetPoint("TOPLEFT", H.UIParent, "TOPLEFT", 40, -40)
            expect(f:GetNumPoints()).eq(1)
            H.expectBox(f, { left = 40, top = 40 })
        end)

        it("follows an anchor chain through several ancestors", function()
            local a = H.parent(300, 300)
            local b = H.env.CreateFrame("Frame", nil, a)
            b:SetSize(100, 100)
            b:SetPoint("TOPLEFT", a, "TOPLEFT", 10, -10)
            local c = H.env.CreateFrame("Frame", nil, b)
            c:SetSize(20, 20)
            c:SetPoint("TOPLEFT", b, "TOPLEFT", 5, -5)
            H.expectBox(c, { left = 15, top = 15, width = 20, height = 20 })
        end)

        it("reports a moved ancestor's children immediately", function()
            local a = H.parent(300, 300)
            local b = H.env.CreateFrame("Frame", nil, a)
            b:SetSize(50, 50)
            b:SetPoint("TOPLEFT", a, "TOPLEFT", 0, 0)
            a:SetPoint("TOPLEFT", H.UIParent, "TOPLEFT", 100, -100)
            H.expectBox(b, { left = 100, top = 100 })
        end)

        it("refuses self-anchoring", function()
            local f = H.parent(10, 10)
            expect(function() f:SetPoint("TOPLEFT", f, "TOPLEFT", 0, 0) end).throws()
        end)
    end)

    describe("resize notification", function()
        it("fires OnSizeChanged on an explicit resize", function()
            local f = H.parent(100, 100)
            local seen = {}
            f:SetScript("OnSizeChanged", function(_, w, h) seen[#seen + 1] = { w, h } end)
            f:SetSize(120, 80)
            expect(#seen).eq(1)
            expect(seen[1][1]).eq(120)
            expect(seen[1][2]).eq(80)
        end)

        it("does not fire when the size is unchanged", function()
            local f = H.parent(100, 100)
            local count = 0
            f:SetScript("OnSizeChanged", function() count = count + 1 end)
            f:SetSize(100, 100)
            expect(count).eq(0)
        end)

        it("fires for a child whose size derives from a resized parent", function()
            local p = H.parent(200, 200)
            local c = H.env.CreateFrame("Frame", nil, p)
            c:SetAllPoints(p)
            local seen
            c:SetScript("OnSizeChanged", function(_, w, h) seen = { w, h } end)
            p:SetSize(300, 150)
            expect(seen).notNil()
            expect(seen[1]).eq(300)
            expect(seen[2]).eq(150)
        end)
    end)

    describe("user resizing", function()
        local function sizable(w, h)
            local f = H.parent(w, h)
            f:SetResizable(true)
            f:EnableMouse(true)
            return f
        end

        it("clamps a user resize to the minimum bound", function()
            local f = sizable(400, 300)
            f:SetResizeBounds(300, 250, 900, 700)
            f:StartSizing("BOTTOMRIGHT")
            f:_userResize(100, 100)
            H.expectSize(f, 300, 250)
        end)

        it("clamps a user resize to the maximum bound", function()
            local f = sizable(400, 300)
            f:SetResizeBounds(300, 250, 900, 700)
            f:StartSizing("BOTTOMRIGHT")
            f:_userResize(5000, 5000)
            H.expectSize(f, 900, 700)
        end)

        it("reports the bounds back", function()
            local f = sizable(400, 300)
            f:SetResizeBounds(300, 250, 900, 700)
            local minW, minH, maxW, maxH = f:GetResizeBounds()
            expect(minW).eq(300)
            expect(minH).eq(250)
            expect(maxW).eq(900)
            expect(maxH).eq(700)
        end)

        it("leaves programmatic SetSize unclamped, as the client does", function()
            local f = sizable(400, 300)
            f:SetResizeBounds(300, 250, 900, 700)
            f:SetSize(50, 40)
            H.expectSize(f, 50, 40)
        end)

        it("requires an active StartSizing", function()
            local f = sizable(400, 300)
            expect(function() f:_userResize(200, 200) end).throws("StartSizing")
        end)

        it("drags a grip through the frame that is sizing", function()
            local f = sizable(400, 300)
            f:SetResizeBounds(300, 250, 900, 700)
            local grip = H.env.CreateFrame("Frame", nil, f)
            grip:EnableMouse(true)
            grip:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", 0, 0)
            grip:SetSize(16, 16)
            grip:SetScript("OnMouseDown", function() f:StartSizing("BOTTOMRIGHT") end)
            grip:SetScript("OnMouseUp", function() f:StopMovingOrSizing() end)
            expect(H.dragResize(grip, 100, 50)).truthy()
            H.expectSize(f, 500, 350)
            expect(f._sizing).isNil()
        end)
    end)

    describe("visibility", function()
        it("reports own shown state separately from effective visibility", function()
            local p = H.parent(10, 10)
            local c = H.env.CreateFrame("Frame", nil, p)
            expect(c:IsShown()).truthy()
            expect(c:IsVisible()).truthy()
            p:Hide()
            expect(c:IsShown()).as("own flag survives a hidden parent").truthy()
            expect(c:IsVisible()).falsy()
        end)

        it("fires OnHide down the tree when an ancestor hides", function()
            local p = H.parent(10, 10)
            local c = H.env.CreateFrame("Frame", nil, p)
            local hidden = false
            c:SetScript("OnHide", function() hidden = true end)
            p:Hide()
            expect(hidden).truthy()
        end)

        it("fires OnShow only on a real transition", function()
            local f = H.parent(10, 10)
            local count = 0
            f:SetScript("OnShow", function() count = count + 1 end)
            f:Show()
            expect(count).as("already shown").eq(0)
            f:Hide()
            f:Show()
            expect(count).eq(1)
        end)
    end)

    describe("scale and the pixel grid", function()
        it("reports physical pixels separately from unit space", function()
            H.setup({ physicalWidth = 1920, physicalHeight = 1080 })
            expect(H.env.GetScreenHeight()).as("unit space is always 768").eq(768)
            local pw, ph = H.env.GetPhysicalScreenSize()
            expect(pw).eq(1920)
            expect(ph).eq(1080)
        end)

        it("defaults physical size to unit space, giving a 1:1 grid", function()
            local _, ph = H.env.GetPhysicalScreenSize()
            expect(ph).eq(H.env.GetScreenHeight())
        end)

        it("multiplies scale down the parent chain", function()
            local p = H.parent(100, 100)
            local c = H.env.CreateFrame("Frame", nil, p)
            p:SetScale(0.5)
            c:SetScale(0.5)
            expect(c:GetEffectiveScale()).near(0.25, 1e-9)
        end)

        it("folds the client UI scale into the effective scale", function()
            H.setup({ uiScale = 0.8 })
            expect(H.parent(10, 10):GetEffectiveScale()).near(0.8, 1e-9)
        end)

        it("reports a scaled widget's rect in its own region units", function()
            local p = H.parent(100, 100)
            p:SetScale(0.5)
            -- Own units are unchanged by the scale; screen space halves.
            expect(p:GetWidth()).as("SetWidth is in own units").eq(100)
            expect(H.box(p).width).as("screen space is scaled").near(50, 1e-9)
        end)

        it("treats a SetPoint offset as the anchored widget's own units", function()
            local p = H.parent(200, 200)
            local c = H.env.CreateFrame("Frame", nil, p)
            c:SetSize(10, 10)
            c:SetScale(0.5)
            c:SetPoint("TOPLEFT", p, "TOPLEFT", 20, 0)
            -- 20 of the child's units is 10 screen units at half scale.
            expect(H.offset(c, p)).near(10, 1e-9)
            expect(c:GetLeft() - p:GetLeft() * 2).as("own units").near(20, 1e-9)
        end)

        it("makes a scaled frame see a taller screen than GetScreenHeight reports", function()
            local p = H.parent(10, 10)
            p:SetScale(0.5)
            -- This divergence is the whole point: a frame under a scaled ancestor measures
            -- the screen in its own units, and GetScreenHeight is in UIParent's. Code that
            -- mixes them is wrong on the vertical axis only.
            expect(H.env.GetScreenHeight()).eq(768)
            expect(H.UIParent:GetTop()).eq(768)
            expect(p:GetTop()).as("same screen, different ruler").near(1536, 1e-9)
        end)

        it("reports UIParent's own size through GetScreenHeight", function()
            H.setup({ uiScale = 0.8 })
            expect(H.env.GetScreenHeight()).near(768 / 0.8, 1e-9)
            expect(H.env.GetScreenHeight()).near(H.UIParent:GetHeight(), 1e-9)
        end)

        it("cuts the parent chain at SetIgnoreParentScale", function()
            H.setup({ uiScale = 0.8 })
            local p = H.parent(100, 100)
            p:SetScale(2)
            local c = H.env.CreateFrame("Frame", nil, p)
            c:SetScale(0.5)
            expect(c:IsIgnoringParentScale()).falsy()
            c:SetIgnoreParentScale(true)
            expect(c:IsIgnoringParentScale()).truthy()
            expect(c:GetEffectiveScale()).as("own scale alone").near(0.5, 1e-9)
        end)
    end)

    describe("font metrics", function()
        it("scales width with text length and font size", function()
            local narrow = H.textWidth("abcd", 10)
            local wide   = H.textWidth("abcdabcd", 10)
            local bigger = H.textWidth("abcd", 20)
            expect(wide).eq(narrow * 2)
            expect(bigger).eq(narrow * 2)
        end)

        it("clamps GetStringWidth to an assigned width but not GetUnbounded", function()
            local p = H.parent(200, 50)
            local fs = p:CreateFontString(nil, "OVERLAY", "GameFontNormal")
            fs:SetFont("Fonts/FRIZQT__.TTF", 12, "")
            fs:SetWordWrap(false)
            fs:SetText(string.rep("x", 100))
            fs:SetWidth(50)
            expect(fs:GetStringWidth()).eq(50)
            expect(fs:GetUnboundedStringWidth()).eq(600)
        end)

        it("wraps to more lines as the assigned width narrows", function()
            local p = H.parent(400, 100)
            local fs = p:CreateFontString(nil, "OVERLAY", "GameFontNormal")
            fs:SetFont("Fonts/FRIZQT__.TTF", 12, "")
            fs:SetText("one two three four five six seven eight nine ten")
            fs:SetWidth(400)
            local tall = fs:GetStringHeight()
            fs:SetWidth(60)
            expect(fs:GetStringHeight()).gt(tall)
        end)

        it("gives a font string with no explicit size its text extent", function()
            local p = H.parent(400, 100)
            local fs = p:CreateFontString(nil, "OVERLAY", "GameFontNormal")
            fs:SetFont("Fonts/FRIZQT__.TTF", 12, "")
            fs:SetText("hello")
            expect(fs:GetWidth()).eq(H.textWidth("hello", 12))
            expect(fs:GetHeight()).eq(H.lineHeight(12))
        end)

        it("ignores colour escape sequences when measuring", function()
            expect(H.font.unbounded("|cffff0000abc|r", 10)).eq(H.font.unbounded("abc", 10))
        end)

        it("measures a different face differently at the same point size", function()
            -- Without per-face metrics a spec asserting a font swap would measure the
            -- same before and after, and pass whether or not the swap happened.
            local wide   = H.textWidth("hello", 12, "Fonts/FRIZQT__.TTF")
            local narrow = H.textWidth("hello", 12, "Fonts/ARIALN.TTF")
            expect(narrow).lt(wide)
            expect(H.lineHeight(12, "Fonts/MORPHEUS.TTF")).gt(H.lineHeight(12, "Fonts/FRIZQT__.TTF"))
        end)

        it("measures a font string with the face it was given", function()
            local p = H.parent(400, 100)
            local fs = p:CreateFontString(nil, "OVERLAY", "GameFontNormal")
            fs:SetFont("Fonts/ARIALN.TTF", 12, "")
            fs:SetText("hello")
            expect(fs:GetUnboundedStringWidth()).eq(H.textWidth("hello", 12, "Fonts/ARIALN.TTF"))
            expect(fs:GetUnboundedStringWidth()).lt(H.textWidth("hello", 12, "Fonts/FRIZQT__.TTF"))
        end)

        it("raises on SetFont for an asset the client cannot load, changing nothing", function()
            -- The live client raises rather than returning false. Modelling it as a return
            -- value hid a login-breaking error: the unguarded probe in Fonts' validation
            -- unwound out of the PLAYER_LOGIN handler and cost plugin init.
            local p = H.parent(400, 100)
            local fs = p:CreateFontString(nil, "OVERLAY", "GameFontNormal")
            fs:SetFont("Fonts/ARIALN.TTF", 12, "")
            expect(function() fs:SetFont("Interface/AddOns/Nope/missing.ttf", 14, "") end)
                .throws("Invalid font asset")
            expect((fs:GetFont())).eq("Fonts/ARIALN.TTF")
            expect(select(2, fs:GetFont())).as("size untouched too").eq(12)
        end)

        it("raises the same way for an EditBox", function()
            local eb = H.env.CreateFrame("EditBox", nil, H.parent(100, 30))
            expect(function() eb:SetFont("Fonts/nope.ttf", 12, "") end)
                .throws("Invalid font asset")
        end)

        it("accepts a face added by H.addFont", function()
            local p = H.parent(400, 100)
            local fs = p:CreateFontString(nil, "OVERLAY", "GameFontNormal")
            H.addFont("TestLocaleFont", "Fonts/2002.TTF")
            expect(fs:SetFont("Fonts/2002.TTF", 12, "")).truthy()
        end)

        it("normalises font paths across slash style and case", function()
            local p = H.parent(400, 100)
            local fs = p:CreateFontString(nil, "OVERLAY", "GameFontNormal")
            expect(fs:SetFont("Fonts\\frizqt__.TTF", 12, "")).truthy()
        end)

        it("exposes client font objects through GetFonts with resolvable paths", function()
            local names = H.env.GetFonts()
            expect(#names).gt(0)
            local paths = {}
            for _, name in ipairs(names) do
                local obj = H.env[name]
                expect(obj).as(name .. " is a real font object").notNil()
                paths[select(1, obj:GetFont())] = true
            end
            expect(paths["Fonts/FRIZQT__.TTF"]).truthy()
            expect(paths["Fonts/ARIALN.TTF"]).as("objects report their own face").truthy()
        end)

        it("resets added faces between setups", function()
            H.addFont("TransientFont", "Fonts/transient.ttf")
            expect(H.font.hasFace("Fonts/transient.ttf")).truthy()
            H.setup()
            expect(H.font.hasFace("Fonts/transient.ttf")).falsy()
        end)

        it("reports no clip when the box reserves the render allowance", function()
            local p = H.parent(400, 100)
            local fs = p:CreateFontString(nil, "OVERLAY", "GameFontNormal")
            fs:SetFont("Fonts/FRIZQT__.TTF", 12, "")
            fs:SetText("hello")
            fs:SetSize(H.textBox("hello", 12), H.lineHeight(12))
            expect(fs:IsTextClipped()).falsy()
            expect(function() H.expectTextNotClipped(fs) end).notThrows()
        end)

        it("reports a clip for a box pinned to the bare metric width", function()
            -- The client truncates with zero tolerance, so the metric is not a fitting
            -- width — it is one physical pixel short of one. This is the whole reason
            -- TextMetrics.Box exists next to Measure, and modelling the metric as "fits"
            -- is what hid a real tab strip rendering "Play..." for "Player".
            local p = H.parent(400, 100)
            local fs = p:CreateFontString(nil, "OVERLAY", "GameFontNormal")
            fs:SetFont("Fonts/FRIZQT__.TTF", 12, "")
            fs:SetText("hello")
            fs:SetSize(H.textWidth("hello", 12), H.lineHeight(12))
            expect(fs:IsTextClipped()).as("metric width is a clip").truthy()
            expect(function() H.expectTextNotClipped(fs) end).throws("clipped")
        end)

        it("reports a clip when the font grows past a pinned box", function()
            local p = H.parent(400, 100)
            local fs = p:CreateFontString(nil, "OVERLAY", "GameFontNormal")
            fs:SetFont("Fonts/FRIZQT__.TTF", 12, "")
            fs:SetText("X")
            fs:SetSize(H.textWidth("X", 12), H.lineHeight(12))
            fs:SetFont("Fonts/FRIZQT__.TTF", 24, "")
            expect(fs:IsTextClipped()).as("box still sized for the 12pt font").truthy()
            expect(function() H.expectTextNotClipped(fs) end).throws("clipped")
        end)

        it("reports a horizontal clip when word wrap is off", function()
            local p = H.parent(400, 100)
            local fs = p:CreateFontString(nil, "OVERLAY", "GameFontNormal")
            fs:SetFont("Fonts/FRIZQT__.TTF", 12, "")
            fs:SetText("wide enough to wrap")
            fs:SetWordWrap(false)
            fs:SetSize(20, H.lineHeight(12))
            expect(fs:IsTextClipped()).as("no wrap, so a narrow box cuts glyphs").truthy()
        end)

        it("reports a clip for a word narrower than its box even with wrap on", function()
            -- Word wrap breaks between words, not inside one, so a single glyph in a
            -- column narrower than itself is clipped rather than re-flowed. This is the
            -- failure that renders as an ellipsis where an icon glyph should be.
            local p = H.parent(400, 100)
            local fs = p:CreateFontString(nil, "OVERLAY", "GameFontNormal")
            fs:SetFont("Fonts/FRIZQT__.TTF", 24, "")
            fs:SetText("v")
            fs:SetSize(8, H.lineHeight(24))
            expect(fs:IsTextClipped()).truthy()
            fs:SetWidth(H.textBox("v", 24))
            expect(fs:IsTextClipped()).as("a column that reserves the glyph fits").falsy()
        end)

        it("breaks inside a word once non-space wrap is enabled", function()
            local p = H.parent(400, 100)
            local fs = p:CreateFontString(nil, "OVERLAY", "GameFontNormal")
            fs:SetFont("Fonts/FRIZQT__.TTF", 12, "")
            fs:SetText(string.rep("x", 20))
            fs:SetWidth(H.textWidth("xxxxx", 12))
            local unbroken = fs:GetNumLines()
            fs:SetNonSpaceWrap(true)
            expect(fs:CanNonSpaceWrap()).truthy()
            expect(fs:GetNumLines()).as("the long word now splits").gt(unbroken)
        end)

        it("treats empty text as never clipped", function()
            local p = H.parent(400, 100)
            local fs = p:CreateFontString(nil, "OVERLAY", "GameFontNormal")
            fs:SetSize(0, 0)
            expect(fs:IsTextClipped()).falsy()
        end)
    end)

    describe("input simulation", function()
        it("does not deliver clicks to a mouse-disabled frame", function()
            local f = H.parent(50, 50)
            local clicked = false
            f:EnableMouse(false)
            f:SetScript("OnMouseUp", function() clicked = true end)
            expect(H.click(f)).falsy()
            expect(clicked).falsy()
        end)

        it("delivers clicks to a mouse-enabled visible frame", function()
            local f = H.parent(50, 50)
            local order = {}
            f:EnableMouse(true)
            f:SetScript("OnMouseDown", function() order[#order + 1] = "down" end)
            f:SetScript("OnMouseUp", function() order[#order + 1] = "up" end)
            expect(H.click(f)).truthy()
            expect(order).deepEq({ "down", "up" })
        end)

        it("does not deliver clicks to a hidden frame", function()
            local f = H.parent(50, 50)
            f:EnableMouse(true)
            f:Hide()
            expect(H.click(f)).falsy()
        end)

        it("reports the cursor in UI coordinates after scale division", function()
            H.cursor(300, 400)
            local x, y = H.env.GetCursorPosition()
            local scale = H.UIParent:GetEffectiveScale()
            expect(x / scale).eq(300)
            expect(y / scale).eq(400)
        end)

        it("runs OnUpdate only for visible frames", function()
            local shown  = H.parent(10, 10)
            local hidden = H.parent(10, 10)
            hidden:Hide()
            local a, b = 0, 0
            shown:SetScript("OnUpdate", function() a = a + 1 end)
            hidden:SetScript("OnUpdate", function() b = b + 1 end)
            H.tick(0.1)
            expect(a).eq(1)
            expect(b).eq(0)
        end)
    end)

    describe("EditBox fidelity", function()
        it("fires OnTextChanged for programmatic SetText, as the client does", function()
            local p = H.parent(100, 30)
            local eb = H.env.CreateFrame("EditBox", nil, p)
            local fired = 0
            eb:SetScript("OnTextChanged", function() fired = fired + 1 end)
            eb:SetText("abc")
            expect(fired).as("Input.lua's silent guard exists because of this").eq(1)
        end)

        it("truncates to max letters", function()
            local p = H.parent(100, 30)
            local eb = H.env.CreateFrame("EditBox", nil, p)
            eb:SetMaxLetters(4)
            eb:SetText("abcdefgh")
            expect(eb:GetText()).eq("abcd")
        end)

        it("moves focus between boxes, firing lost then gained", function()
            local p = H.parent(100, 30)
            local a = H.env.CreateFrame("EditBox", nil, p)
            local b = H.env.CreateFrame("EditBox", nil, p)
            local log = {}
            a:SetScript("OnEditFocusLost", function() log[#log + 1] = "a-lost" end)
            b:SetScript("OnEditFocusGained", function() log[#log + 1] = "b-gained" end)
            a:SetFocus()
            b:SetFocus()
            expect(a:HasFocus()).falsy()
            expect(b:HasFocus()).truthy()
            expect(log).deepEq({ "a-lost", "b-gained" })
        end)
    end)

    describe("spellcast simulation", function()
        it("reports nothing for UnitCastingInfo and UnitChannelInfo while idle", function()
            -- A caller treating nil name as an empty cast would show an empty bar forever.
            expect(H.env.UnitCastingInfo("player")).isNil()
            expect(H.env.UnitChannelInfo("player")).isNil()
        end)

        it("fires UNIT_SPELLCAST_START through event dispatch on H.startCast", function()
            local probe = H.env.CreateFrame("Frame", nil, H.UIParent)
            local received = {}
            probe:RegisterEvent("UNIT_SPELLCAST_START")
            probe:SetScript("OnEvent", function(_, ev, unit, ...)
                received.event = ev
                received.unit  = unit
            end)
            H.startCast({ unit = "player" })
            expect(received.event).eq("UNIT_SPELLCAST_START")
            expect(received.unit).eq("player")
        end)

        it("returns the positional shape: UnitCastingInfo has castID, UnitChannelInfo does not", function()
            H.startCast({ name = "Frostbolt", spellId = 116, castID = "c7" })
            local name, text, texture, startTime, endTime, isTrade, castID, notInt, spId
                = H.env.UnitCastingInfo("player")
            expect(name).eq("Frostbolt")
            expect(castID).as("castID is the 7th positional value").eq("c7")
            expect(spId).as("spellId is the 9th positional value").eq(116)

            H.startChannel({ name = "Blizzard", spellId = 10, castID = "c8" })
            local cn, ct, ctx, cs, ce, ciT, cNotInt, cSpId
                = H.env.UnitChannelInfo("player")
            expect(cn).eq("Blizzard")
            -- Channel has no castID; the 7th value is notInterruptible, the 8th is spellId
            expect(cNotInt).as("7th positional = notInterruptible, not castID").eq(false)
            expect(cSpId).as("8th positional = spellId").eq(10)
        end)

        it("reports startTime and endTime in milliseconds matching GetTime()*1000", function()
            H.tick(1.5)  -- advance clock to 1.5s
            local rec = H.startCast({ duration = 3 })
            local _, _, _, startTime, endTime = H.env.UnitCastingInfo("player")
            local nowMS = H.env.GetTime() * 1000
            expect(startTime).eq(nowMS)
            expect(endTime - startTime).as("span = duration * 1000").eq(3 * 1000)
        end)

        it("does not report a player cast for a different unit token", function()
            H.startCast({ unit = "player", name = "Fireball" })
            expect(H.env.UnitCastingInfo("target")).as("target has no cast").isNil()
            expect(H.env.UnitCastingInfo("player")).notNil()
        end)

        it("uses sensible defaults when H.startCast is called with no arguments", function()
            local rec = H.startCast()
            local name, text, texture, startTime, endTime, isTrade, castID, notInt, spId
                = H.env.UnitCastingInfo("player")
            expect(name).as("name defaults").notNil()
            expect(texture).as("texture defaults").notNil()
            expect(startTime).as("startTime defaults to clock").eq(H.env.GetTime() * 1000)
            expect((endTime - startTime) > 0).as("positive duration").truthy()
            expect(spId).as("spellId defaults").notNil()
            expect(notInt).as("not interruptible by default").eq(false)
        end)

        it("honours every override field in H.startCast", function()
            H.tick(2)
            H.startCast({
                unit = "target",
                name = "Greater Heal",
                texture = "Interface\\Icons\\Spell_Holy_GreaterHeal",
                duration = 4,
                spellId = 2060,
                castID = "abc",
                notInterruptible = true,
                startTime = 5000,
                endTime = 9000,
            })
            local name, _, tex, st, et, _, castID, notInt, spId
                = H.env.UnitCastingInfo("target")
            expect(name).eq("Greater Heal")
            expect(tex).eq("Interface\\Icons\\Spell_Holy_GreaterHeal")
            expect(st).eq(5000)
            expect(et).eq(9000)
            expect(castID).eq("abc")
            expect(notInt).eq(true)
            expect(spId).eq(2060)
        end)

        it("makes cast and channel mutually exclusive", function()
            H.startCast({ name = "Fireball" })
            expect(H.env.UnitCastingInfo("player")).notNil()
            H.startChannel({ name = "Drain Life" })
            expect(H.env.UnitCastingInfo("player")).as("cast cleared by channel").isNil()
            expect(H.env.UnitChannelInfo("player")).notNil()

            H.startCast({ name = "Frostbolt" })
            expect(H.env.UnitChannelInfo("player")).as("channel cleared by cast").isNil()
            expect(H.env.UnitCastingInfo("player")).notNil()
        end)

        it("clears state BEFORE firing stop events, matching the client's order", function()
            -- From inside a listener for UNIT_SPELLCAST_STOP, UnitCastingInfo must
            -- already report nil.
            local probe = H.env.CreateFrame("Frame", nil, H.UIParent)
            local infoInsideHandler = "not called"
            probe:RegisterEvent("UNIT_SPELLCAST_STOP")
            probe:SetScript("OnEvent", function()
                infoInsideHandler = H.env.UnitCastingInfo("player")
            end)
            H.startCast({ unit = "player" })
            H.stopCast()
            expect(infoInsideHandler).as("nil inside STOP handler").isNil()
        end)

        it("clears state before UNIT_SPELLCAST_SUCCEEDED", function()
            local probe = H.env.CreateFrame("Frame", nil, H.UIParent)
            local infoInside
            probe:RegisterEvent("UNIT_SPELLCAST_SUCCEEDED")
            probe:SetScript("OnEvent", function()
                infoInside = H.env.UnitCastingInfo("player")
            end)
            H.startCast({ unit = "player" })
            H.finishCast()
            expect(infoInside).isNil()
        end)

        it("clears state before UNIT_SPELLCAST_INTERRUPTED", function()
            local probe = H.env.CreateFrame("Frame", nil, H.UIParent)
            local infoInside
            probe:RegisterEvent("UNIT_SPELLCAST_INTERRUPTED")
            probe:SetScript("OnEvent", function()
                infoInside = H.env.UnitCastingInfo("player")
            end)
            H.startCast({ unit = "player" })
            H.interruptCast()
            expect(infoInside).isNil()
        end)

        it("clears state before UNIT_SPELLCAST_FAILED", function()
            local probe = H.env.CreateFrame("Frame", nil, H.UIParent)
            local infoInside
            probe:RegisterEvent("UNIT_SPELLCAST_FAILED")
            probe:SetScript("OnEvent", function()
                infoInside = H.env.UnitCastingInfo("player")
            end)
            H.startCast({ unit = "player" })
            H.failCast()
            expect(infoInside).isNil()
        end)

        it("clears state before UNIT_SPELLCAST_CHANNEL_STOP", function()
            local probe = H.env.CreateFrame("Frame", nil, H.UIParent)
            local infoInside
            probe:RegisterEvent("UNIT_SPELLCAST_CHANNEL_STOP")
            probe:SetScript("OnEvent", function()
                infoInside = H.env.UnitChannelInfo("player")
            end)
            H.startChannel({ unit = "player" })
            H.stopChannel()
            expect(infoInside).isNil()
        end)

        it("H.delayCast extends endTime and fires UNIT_SPELLCAST_DELAYED", function()
            H.tick(1)
            H.startCast({ duration = 3 })
            local _, _, _, _, endBefore = H.env.UnitCastingInfo("player")
            local probe = H.env.CreateFrame("Frame", nil, H.UIParent)
            local delayFired = false
            probe:RegisterEvent("UNIT_SPELLCAST_DELAYED")
            probe:SetScript("OnEvent", function() delayFired = true end)
            H.delayCast(0.5)
            local _, _, _, _, endAfter = H.env.UnitCastingInfo("player")
            expect(endAfter - endBefore).eq(500)
            expect(delayFired).truthy()
        end)

        it("H.delayCast returns nil and fires nothing when idle", function()
            local probe = H.env.CreateFrame("Frame", nil, H.UIParent)
            local fired = false
            probe:RegisterEvent("UNIT_SPELLCAST_DELAYED")
            probe:SetScript("OnEvent", function() fired = true end)
            local result = H.delayCast(1)
            expect(result).isNil()
            expect(fired).falsy()
        end)

        it("H.updateChannel adjusts endTime including negative deltas", function()
            H.tick(1)
            H.startChannel({ duration = 5 })
            local _, _, _, _, endBefore = H.env.UnitChannelInfo("player")
            local probe = H.env.CreateFrame("Frame", nil, H.UIParent)
            local updateFired = false
            probe:RegisterEvent("UNIT_SPELLCAST_CHANNEL_UPDATE")
            probe:SetScript("OnEvent", function() updateFired = true end)
            H.updateChannel(-1)
            local _, _, _, _, endAfter = H.env.UnitChannelInfo("player")
            expect(endAfter - endBefore).eq(-1000)
            expect(updateFired).truthy()
        end)

        it("H.updateChannel returns nil and fires nothing when idle", function()
            local probe = H.env.CreateFrame("Frame", nil, H.UIParent)
            local fired = false
            probe:RegisterEvent("UNIT_SPELLCAST_CHANNEL_UPDATE")
            probe:SetScript("OnEvent", function() fired = true end)
            local result = H.updateChannel(1)
            expect(result).isNil()
            expect(fired).falsy()
        end)

        it("state.cast and state.channel are cleared by H.setup()", function()
            H.startCast({ name = "Fireball" })
            H.startChannel({ name = "Drain Soul" })
            -- channel clears cast, so only channel should be set now
            expect(H.env.UnitChannelInfo("player")).notNil()
            H.setup()
            expect(H.env.UnitCastingInfo("player")).isNil()
            expect(H.env.UnitChannelInfo("player")).isNil()
        end)

        it("both player cast bar globals exist as frames", function()
            -- The live client renamed this frame when Edit Mode arrived, so the harness
            -- ships both names and the addon has to cope with either being the real one.
            for _, name in ipairs({ "PlayerCastingBarFrame", "CastingBarFrame" }) do
                expect(H.env[name]).as(name .. " exists").notNil()
                expect(H.env[name]:GetWidth()).gt(0)
            end
        end)

        it("castBarGlobals narrows which cast bar names the client has", function()
            H.setup({ castBarGlobals = { "PlayerCastingBarFrame" } })
            expect(H.env.PlayerCastingBarFrame).notNil()
            expect(H.env.CastingBarFrame).as("legacy name withheld").isNil()
        end)

        it("INTERRUPTED and FAILED globals are defined", function()
            expect(H.env.INTERRUPTED).eq("Interrupted")
            expect(H.env.FAILED).eq("Failed")
        end)
    end)

    describe("combat log simulation", function()
        it("UnitGUID is stable per unit token and differs between units", function()
            local a = H.env.UnitGUID("player")
            expect(a).notNil()
            expect(H.env.UnitGUID("player")).as("stable").eq(a)
            expect(H.env.UnitGUID("target")).as("distinct per unit").neq(a)
            expect(H.env.UnitGUID(nil)).isNil()
        end)

        it("CombatLogGetCurrentEventInfo returns nothing outside an event", function()
            -- The client's own behaviour: the accessor is only meaningful inside the
            -- handler, so code that caches it or reads it late must get nothing.
            expect(H.env.CombatLogGetCurrentEventInfo()).isNil()
        end)

        it("delivers a SPELL_INTERRUPT payload in the client's positional order", function()
            local seen
            local probe = H.env.CreateFrame("Frame", nil, H.UIParent)
            probe:RegisterEvent("COMBAT_LOG_EVENT_UNFILTERED")
            probe:SetScript("OnEvent", function()
                seen = { H.env.CombatLogGetCurrentEventInfo() }
            end)

            H.combatLogInterrupt({ unit = "player", by = "Kaelthas",
                                   interrupted = "Fireball" })

            expect(seen).notNil()
            expect(seen[2]).as("subevent").eq("SPELL_INTERRUPT")
            expect(seen[5]).as("sourceName is the interrupter").eq("Kaelthas")
            expect(seen[8]).as("destGUID is the interrupted unit").eq(H.env.UnitGUID("player"))
            expect(seen[13]).as("the interrupting spell").eq("Counterspell")
            expect(seen[16]).as("extraSpellName is the spell that was stopped").eq("Fireball")
        end)

        it("clears the payload again once the event has been dispatched", function()
            H.combatLogInterrupt({ by = "Kaelthas" })
            expect(H.env.CombatLogGetCurrentEventInfo())
                .as("no longer readable after dispatch").isNil()
        end)

        it("H.interruptCast with `by` delivers the log line before the cast event", function()
            local order = {}
            local probe = H.env.CreateFrame("Frame", nil, H.UIParent)
            probe:RegisterEvent("COMBAT_LOG_EVENT_UNFILTERED")
            probe:RegisterEvent("UNIT_SPELLCAST_INTERRUPTED")
            probe:SetScript("OnEvent", function(_, ev)
                order[#order + 1] = ev
            end)
            H.startCast({ name = "Fireball" })
            H.interruptCast({ by = "Kaelthas" })
            expect(order[1]).eq("COMBAT_LOG_EVENT_UNFILTERED")
            expect(order[2]).eq("UNIT_SPELLCAST_INTERRUPTED")
        end)

        it("logAfter reverses that order, which the client also produces", function()
            local order = {}
            local probe = H.env.CreateFrame("Frame", nil, H.UIParent)
            probe:RegisterEvent("COMBAT_LOG_EVENT_UNFILTERED")
            probe:RegisterEvent("UNIT_SPELLCAST_INTERRUPTED")
            probe:SetScript("OnEvent", function(_, ev)
                order[#order + 1] = ev
            end)
            H.startCast({ name = "Fireball" })
            H.interruptCast({ by = "Kaelthas", logAfter = true })
            expect(order[1]).eq("UNIT_SPELLCAST_INTERRUPTED")
            expect(order[2]).eq("COMBAT_LOG_EVENT_UNFILTERED")
        end)

        it("H.interruptCast still accepts a bare unit token", function()
            H.startCast({ unit = "player", name = "Fireball" })
            expect(function() H.interruptCast("player") end).notThrows()
            expect(H.env.UnitCastingInfo("player")).isNil()
        end)

        it("names the interrupted spell from the cast in flight", function()
            local seen
            local probe = H.env.CreateFrame("Frame", nil, H.UIParent)
            probe:RegisterEvent("COMBAT_LOG_EVENT_UNFILTERED")
            probe:SetScript("OnEvent", function()
                seen = { H.env.CombatLogGetCurrentEventInfo() }
            end)
            H.startCast({ name = "Pyroblast" })
            H.interruptCast({ by = "Kaelthas" })
            expect(seen[16]).eq("Pyroblast")
        end)

        it("state.combatLogEvent is cleared by H.setup()", function()
            H.combatLogInterrupt({ by = "Kaelthas" })
            H.setup()
            expect(require("harness.wow.state").combatLogEvent).isNil()
        end)
    end)

    describe("per-unit API simulation", function()
        it("per-unit override wins over the flat value for UnitHealth", function()
            H.state.unitHealth = 50
            H.setUnit("target", { health = 30 })
            expect(H.env.UnitHealth("target")).as("override wins").eq(30)
        end)

        it("per-unit override wins over the flat value for UnitHealthMax", function()
            H.state.unitHealthMax = 200
            H.setUnit("target", { healthMax = 400 })
            expect(H.env.UnitHealthMax("target")).as("override wins").eq(400)
        end)

        it("per-unit override wins over the flat value for UnitPower", function()
            H.state.unitPower = 60
            H.setUnit("target", { power = 20 })
            expect(H.env.UnitPower("target")).as("override wins").eq(20)
        end)

        it("per-unit override wins over the flat value for UnitPowerMax", function()
            H.state.unitPowerMax = 150
            H.setUnit("target", { powerMax = 300 })
            expect(H.env.UnitPowerMax("target")).as("override wins").eq(300)
        end)

        it("per-unit override wins over the flat value for UnitPowerType", function()
            H.state.unitPowerType = 0
            H.setUnit("target", { powerType = 3 })
            expect(H.env.UnitPowerType("target")).as("override wins").eq(3)
        end)

        it("per-unit override wins over the flat value for UnitName", function()
            H.setUnit("target", { name = "Onyxia" })
            expect(H.env.UnitName("target")).eq("Onyxia")
        end)

        it("per-unit override wins over the flat value for UnitLevel", function()
            H.state.unitLevel = 60
            H.setUnit("target", { level = 42 })
            expect(H.env.UnitLevel("target")).eq(42)
        end)

        it("per-unit override wins over the flat value for UnitClass", function()
            H.state.unitClass = "WARRIOR"
            H.setUnit("target", { class = "MAGE" })
            local _, classFile = H.env.UnitClass("target")
            expect(classFile).eq("MAGE")
        end)

        it("falls back to the flat value when per-unit record omits the field", function()
            -- This property is what keeps every pre-existing spec passing: a spec that
            -- stages a unit with { reaction = 2 } still reads health from the flat value.
            H.state.unitHealth = 55
            H.state.unitHealthMax = 110
            H.state.unitPower = 33
            H.state.unitPowerMax = 66
            H.state.unitPowerType = 1
            H.state.unitLevel = 45
            H.state.unitClass = "ROGUE"
            H.setUnit("target", { reaction = 4 })  -- only reaction staged

            expect(H.env.UnitHealth("target")).as("health falls back").eq(55)
            expect(H.env.UnitHealthMax("target")).as("healthMax falls back").eq(110)
            expect(H.env.UnitPower("target")).as("power falls back").eq(33)
            expect(H.env.UnitPowerMax("target")).as("powerMax falls back").eq(66)
            expect(H.env.UnitPowerType("target")).as("powerType falls back").eq(1)
            expect(H.env.UnitLevel("target")).as("level falls back").eq(45)
            local _, classFile = H.env.UnitClass("target")
            expect(classFile).as("class falls back").eq("ROGUE")
        end)

        it("falls back to hardcoded default when neither per-unit nor flat is set", function()
            H.state.unitHealth = nil
            H.state.unitHealthMax = nil
            H.state.unitPower = nil
            H.state.unitPowerMax = nil
            H.state.unitPowerType = nil
            H.state.unitLevel = nil
            H.state.unitClass = nil
            H.setUnit("target", { reaction = 2 })

            expect(H.env.UnitHealth("target")).as("health default 100").eq(100)
            expect(H.env.UnitHealthMax("target")).as("healthMax default 100").eq(100)
            expect(H.env.UnitPower("target")).as("power default 80").eq(80)
            expect(H.env.UnitPowerMax("target")).as("powerMax default 100").eq(100)
            expect(H.env.UnitPowerType("target")).as("powerType default 0").eq(0)
            expect(H.env.UnitLevel("target")).as("level default 60").eq(60)
            -- UnitClass defaults to WARRIOR when unitClass is nil and not classless
            local _, classFile = H.env.UnitClass("target")
            expect(classFile).as("class default WARRIOR").eq("WARRIOR")
        end)

        it("UnitName defaults to Testchar for player and nil for an unstaged unit", function()
            expect(H.env.UnitName("player")).eq("Testchar")
            expect(H.env.UnitName("target")).as("unstaged target").isNil()
        end)

        it("UnitName per-unit override wins for both player and target", function()
            H.setUnit("player", { name = "Arthas" })
            H.setUnit("target", { name = "Illidan" })
            expect(H.env.UnitName("player")).eq("Arthas")
            expect(H.env.UnitName("target")).eq("Illidan")
        end)

        it("per-unit classless overrides the flat independently of class", function()
            -- A classless unit returns nil while the player still reports its class.
            H.state.unitClass = "PALADIN"
            H.setUnit("target", { classless = true })
            expect(H.env.UnitClass("target")).as("classless target").isNil()
            local _, playerClass = H.env.UnitClass("player")
            expect(playerClass).as("player still reports class").eq("PALADIN")
        end)

        it("per-unit class overrides independently of per-unit classless", function()
            H.state.unitClass = "WARRIOR"
            H.setUnit("player", { class = "DRUID" })
            H.setUnit("target", { classless = true })
            local _, playerClass = H.env.UnitClass("player")
            expect(playerClass).eq("DRUID")
            expect(H.env.UnitClass("target")).isNil()
        end)

        it("UnitIsPlayer is true for player and false for a staged creature", function()
            expect(H.env.UnitIsPlayer("player")).as("the player always is").eq(true)
            expect(H.env.UnitIsPlayer("target")).as("unstaged").eq(false)
            H.setUnit("target", { name = "Vale Moth", reaction = 4 })
            expect(H.env.UnitIsPlayer("target")).as("staged without isPlayer").eq(false)
        end)

        it("UnitIsPlayer honours the per-unit isPlayer override", function()
            H.setUnit("target", { name = "Someone", isPlayer = true })
            expect(H.env.UnitIsPlayer("target")).eq(true)
        end)
    end)

    describe("UnitExists simulation", function()
        it("always true for player with nothing staged", function()
            expect(H.env.UnitExists("player")).truthy()
        end)

        it("false for target with nothing staged", function()
            expect(H.env.UnitExists("target")).falsy()
        end)

        it("true after H.setUnit", function()
            H.setUnit("target", { health = 50 })
            expect(H.env.UnitExists("target")).truthy()
        end)

        it("false again after H.clearUnit", function()
            H.setUnit("target", { health = 50 })
            H.clearUnit("target")
            expect(H.env.UnitExists("target")).falsy()
        end)

        it("false when staged with exists = false", function()
            H.setUnit("target", { exists = false })
            expect(H.env.UnitExists("target")).falsy()
        end)
    end)

    describe("UnitReaction simulation", function()
        it("returns the staged reaction for the first argument", function()
            H.setUnit("target", { reaction = 2 })
            expect(H.env.UnitReaction("target", "player")).eq(2)
        end)

        it("returns nil for an unstaged unit", function()
            expect(H.env.UnitReaction("target", "player")).isNil()
        end)

        it("is NOT symmetric: swapping the arguments gives nil", function()
            H.setUnit("target", { reaction = 4 })
            -- Reading reaction of "player" towards "target" gets nil because no per-unit
            -- reaction was set on "player".
            expect(H.env.UnitReaction("player", "target")).isNil()
        end)

        it("returns nil when either argument is missing", function()
            H.setUnit("target", { reaction = 5 })
            expect(H.env.UnitReaction(nil, "player")).isNil()
            expect(H.env.UnitReaction("target", nil)).isNil()
        end)
    end)

    describe("FACTION_BAR_COLORS", function()
        it("exists with 8 rows in {r, g, b} object shape", function()
            local fbc = H.env.FACTION_BAR_COLORS
            expect(fbc).notNil()
            for i = 1, 8 do
                expect(fbc[i]).as("row " .. i .. " exists").notNil()
                expect(type(fbc[i].r)).as("row " .. i .. " .r").eq("number")
                expect(type(fbc[i].g)).as("row " .. i .. " .g").eq("number")
                expect(type(fbc[i].b)).as("row " .. i .. " .b").eq("number")
            end
        end)
    end)

    describe("state.reset() clears state.units", function()
        it("UnitExists becomes false after H.setup()", function()
            H.setUnit("target", { health = 50 })
            expect(H.env.UnitExists("target")).truthy()
            H.setup()
            expect(H.env.UnitExists("target")).as("cleared by reset").falsy()
        end)

        it("flat unit family is NOT cleared by reset", function()
            -- This verifies that Tests/spec/35_attach_login_spec.lua pattern keeps working:
            -- state.unitHealth set before H.setup() must survive the reset within setup.
            H.state.unitHealth = 77
            H.state.unitLevel = 55
            H.setup()
            -- The flat values are preserved because they are set before the client build
            -- and reset does not touch them.
            expect(H.state.unitHealth).as("flat unitHealth survives").eq(77)
            expect(H.state.unitLevel).as("flat unitLevel survives").eq(55)
        end)
    end)

    describe("H.setUnit field validation", function()
        it("asserts on an unknown field name", function()
            expect(function()
                H.setUnit("target", { bogusField = 42 })
            end).throws()
        end)

        it("accepts every known field without error", function()
            expect(function()
                H.setUnit("target", {
                    exists = true, name = "Mob", level = 10, reaction = 4,
                    class = "MAGE", classless = false,
                    health = 100, healthMax = 100,
                    power = 50, powerMax = 100, powerType = 0,
                })
            end).notThrows()
        end)
    end)

    describe("H.setTarget event firing", function()
        it("fires PLAYER_TARGET_CHANGED when acquiring a target", function()
            local probe = H.env.CreateFrame("Frame", nil, H.UIParent)
            local fired = false
            probe:RegisterEvent("PLAYER_TARGET_CHANGED")
            probe:SetScript("OnEvent", function(_, ev)
                if ev == "PLAYER_TARGET_CHANGED" then fired = true end
            end)
            H.setTarget({ name = "Onyxia", health = 100, healthMax = 100 })
            expect(fired).as("fires on acquire").truthy()
        end)

        it("fires PLAYER_TARGET_CHANGED when clearing the target", function()
            H.setUnit("target", { name = "Ragnaros" })
            local probe = H.env.CreateFrame("Frame", nil, H.UIParent)
            local fired = false
            probe:RegisterEvent("PLAYER_TARGET_CHANGED")
            probe:SetScript("OnEvent", function(_, ev)
                if ev == "PLAYER_TARGET_CHANGED" then fired = true end
            end)
            H.setTarget(nil)
            expect(fired).as("fires on clear").truthy()
            expect(H.env.UnitExists("target")).as("target gone").falsy()
        end)

        it("H.clearUnit does NOT fire PLAYER_TARGET_CHANGED", function()
            H.setUnit("target", { name = "Nefarian" })
            local probe = H.env.CreateFrame("Frame", nil, H.UIParent)
            local fired = false
            probe:RegisterEvent("PLAYER_TARGET_CHANGED")
            probe:SetScript("OnEvent", function(_, ev)
                if ev == "PLAYER_TARGET_CHANGED" then fired = true end
            end)
            H.clearUnit("target")
            expect(fired).as("clearUnit is silent").falsy()
        end)
    end)

    describe("TargetFrame and TargetFrameSpellBar stubs", function()
        it("TargetFrame exists as a global frame", function()
            expect(H.env.TargetFrame).notNil()
            expect(H.env.TargetFrame:GetWidth()).gt(0)
        end)

        it("TargetFrameSpellBar exists and is a child of TargetFrame", function()
            expect(H.env.TargetFrameSpellBar).notNil()
            expect(H.env.TargetFrameSpellBar:GetParent()).eq(H.env.TargetFrame)
        end)

        it("TargetFrame re-shows itself from a Blizzard system event", function()
            -- Disable the UnitFrames plugin so its suppression hook is not active.
            H.SuuUI.Plugins:Get("unit_frames"):Disable()
            H.env.TargetFrame:Hide()
            expect(H.env.TargetFrame:IsShown()).falsy()
            H.fireEvent("PLAYER_ENTERING_WORLD")
            expect(H.env.TargetFrame:IsShown()).as("re-shown by its own OnEvent").truthy()
        end)

        it("TargetFrameSpellBar re-shows itself from a Blizzard system event", function()
            -- Disable both UnitFrames and CastBars plugins to remove suppression hooks.
            H.SuuUI.Plugins:Get("unit_frames"):Disable()
            local castBars = H.SuuUI.Plugins:Get("cast_bars")
            if castBars then castBars:Disable() end
            H.env.TargetFrameSpellBar:Hide()
            expect(H.env.TargetFrameSpellBar:IsShown()).falsy()
            H.fireEvent("PLAYER_ENTERING_WORLD")
            expect(H.env.TargetFrameSpellBar:IsShown())
                .as("re-shown by its own OnEvent").truthy()
        end)
    end)

    describe("texture crop (SetTexCoord / GetTexCoord)", function()
        it("round-trips a 4-argument SetTexCoord through GetTexCoord", function()
            local p = H.parent(100, 100)
            local tex = p:CreateTexture(nil, "ARTWORK")
            tex:SetTexCoord(0.1, 0.9, 0.2, 0.8)
            local l, r, t, b = tex:GetTexCoord()
            expect(l).near(0.1, 1e-9)
            expect(r).near(0.9, 1e-9)
            expect(t).near(0.2, 1e-9)
            expect(b).near(0.8, 1e-9)
        end)

        it("reports nil for an untouched texture", function()
            local p = H.parent(100, 100)
            local tex = p:CreateTexture(nil, "ARTWORK")
            expect(tex:GetTexCoord()).isNil()
        end)

        it("accepts the 8-argument corner form without error", function()
            local p = H.parent(100, 100)
            local tex = p:CreateTexture(nil, "ARTWORK")
            expect(function()
                tex:SetTexCoord(0, 0, 0, 1, 1, 0, 1, 1)
            end).notThrows()
        end)
    end)

    -- Secure buttons. Targeting a unit and opening its context menu are protected, so an
    -- addon cannot perform either: it states attributes and the client's own handler acts on
    -- them. Modelling that is the only way a spec can tell a correctly wired unit frame from
    -- a frame that takes the click and does nothing — which is what every other assertion
    -- about such a frame reports as healthy.
    describe("secure attributes and click dispatch", function()
        local function secureButton(unit)
            local p = H.parent(200, 100)
            local b = H.env.CreateFrame("Button", nil, p, "SecureUnitButtonTemplate")
            b:SetSize(200, 100)
            b:EnableMouse(true)
            b:RegisterForClicks("AnyUp")
            if unit then b:SetAttribute("unit", unit) end
            return b
        end

        it("round-trips an attribute", function()
            local b = secureButton()
            b:SetAttribute("*type2", "togglemenu")
            expect(b:GetAttribute("*type2")).eq("togglemenu")
            expect(b:GetAttribute("*type1")).as("an unset attribute reads nil").isNil()
        end)

        it("performs the button's own action, from its attributes", function()
            local b = secureButton("target")
            b:SetAttribute("*type1", "target")
            b:SetAttribute("*type2", "togglemenu")
            H.click(b)
            expect(H.targetedUnit()).eq("target")
            H.click(b, "RightButton")
            expect(H.unitMenu().unit).eq("target")
        end)

        it("resolves the unprefixed spelling too", function()
            local b = secureButton("player")
            b:SetAttribute("type2", "togglemenu")
            H.click(b, "RightButton")
            expect(H.unitMenu().unit).eq("player")
        end)

        it("does nothing for a button with no action stated", function()
            local b = secureButton("player")
            b:SetAttribute("*type1", "target")
            H.click(b, "RightButton")
            expect(H.unitMenu()).isNil()
            expect(H.targetedUnit()).as("a right click is not a left click").isNil()
        end)

        it("fires PreClick and PostClick around the action", function()
            local b = secureButton("player")
            b:SetAttribute("*type2", "togglemenu")
            local order = {}
            b:HookScript("PreClick",  function() order[#order + 1] = H.unitMenu() == nil end)
            b:HookScript("PostClick", function() order[#order + 1] = H.unitMenu() ~= nil end)
            H.click(b, "RightButton")
            expect(order).deepEq({ true, true })
        end)

        -- The trap the real client sets, modelled: the template's OnClick IS the action, so
        -- code that sets its own replaces it and every action silently stops happening.
        it("loses the action when OnClick is overwritten", function()
            local b = secureButton("player")
            b:SetAttribute("*type2", "togglemenu")
            b:SetScript("OnClick", function() end)
            H.click(b, "RightButton")
            expect(H.unitMenu()).isNil()
        end)

        it("keeps the action when OnClick is hooked instead", function()
            local b = secureButton("player")
            b:SetAttribute("*type2", "togglemenu")
            local hooked = 0
            b:HookScript("OnClick", function() hooked = hooked + 1 end)
            H.click(b, "RightButton")
            expect(hooked).eq(1)
            expect(H.unitMenu().unit).eq("player")
        end)

        describe("RegisterForClicks", function()
            it("delivers left-up only until told otherwise", function()
                local p = H.parent(200, 100)
                local b = H.env.CreateFrame("Button", nil, p, "SecureUnitButtonTemplate")
                b:EnableMouse(true)
                b:SetAttribute("unit", "player")
                b:SetAttribute("*type1", "target")
                b:SetAttribute("*type2", "togglemenu")
                H.click(b, "RightButton")
                expect(H.unitMenu()).as("a right click needs registering for").isNil()
                H.click(b)
                expect(H.targetedUnit()).as("left-up is the default").eq("player")
            end)

            it("honours a named button", function()
                local b = secureButton("player")
                b:RegisterForClicks("RightButtonUp")
                b:SetAttribute("*type1", "target")
                b:SetAttribute("*type2", "togglemenu")
                H.click(b)
                expect(H.targetedUnit()).isNil()
                H.click(b, "RightButton")
                expect(H.unitMenu().unit).eq("player")
            end)

            it("honours the down phase", function()
                local b = secureButton("player")
                b:RegisterForClicks("AnyDown")
                b:SetAttribute("*type2", "togglemenu")
                local atDown
                b:SetScript("OnMouseUp", function() atDown = H.unitMenu() ~= nil end)
                H.click(b, "RightButton")
                expect(atDown).as("the action ran on the press").eq(true)
            end)

            it("dispatches nothing for a plain frame", function()
                local p = H.parent(200, 100)
                local f = H.env.CreateFrame("Frame", nil, p, "SecureUnitButtonTemplate")
                f:EnableMouse(true)
                f:SetAttribute("unit", "player")
                f:SetAttribute("*type2", "togglemenu")
                H.click(f, "RightButton")
                expect(H.unitMenu()).as("only a button carries a click handler").isNil()
            end)
        end)

        it("forgets both actions on clearUnitActions", function()
            local b = secureButton("player")
            b:SetAttribute("*type1", "target")
            b:SetAttribute("*type2", "togglemenu")
            H.click(b)
            H.click(b, "RightButton")
            H.clearUnitActions()
            expect(H.targetedUnit()).isNil()
            expect(H.unitMenu()).isNil()
        end)
    end)

    ---------------------------------------------------------------------------
    -- Combat lockdown
    --
    -- The client refuses addon-driven geometry on a protected frame, and on any frame whose
    -- SUBTREE holds one, while in combat — silently, so the only symptom is a frame that
    -- keeps the size it had. That is not a corner case: it is how a shipped bug survived
    -- 2728 assertions. The unit frame held a secure click surface, so every mid-fight resize
    -- was refused; a debuff band arriving in combat was carved out of the frame's existing
    -- box and pushed the bars down by its own height. Measured in game: preferred 227
    -- against an actual 188, InCombatLockdown() true on every mismatch, false on every match.
    --
    -- Note the two directions, because they are opposites and conflating them is the whole
    -- mistake: protection propagates DOWN to descendants, the refusal propagates UP to
    -- ancestors.
    ---------------------------------------------------------------------------
    describe("combat lockdown", function()
        -- A plain wrapper holding a plain child holding a secure grandchild: the shape the
        -- bug had. Nothing in the chain above the grandchild is protected.
        local function secureGrandchildTree()
            local wrapper = H.parent(300, 100)
            local mid     = H.env.CreateFrame("Frame", nil, wrapper)
            mid:SetAllPoints(wrapper)
            local secure  = H.env.CreateFrame("Button", nil, mid, "SecureUnitButtonTemplate")
            secure:SetAttribute("unit", "player")
            return wrapper, mid, secure
        end

        -- Counts a raw client event, the way the setTarget specs above do. The addon's own
        -- EventBus is a different bus and does not carry PLAYER_REGEN_*, so H.eventSpy would
        -- report zero for a working announcement.
        local function eventProbe(event)
            local probe = H.env.CreateFrame("Frame", nil, H.UIParent)
            local seen = { n = 0 }
            probe:RegisterEvent(event)
            probe:SetScript("OnEvent", function(_, ev)
                if ev == event then seen.n = seen.n + 1 end
            end)
            return seen
        end

        describe("the flag", function()
            it("is out of combat by default", function()
                expect(H.env.InCombatLockdown()).as("setup leaves the client at peace").eq(false)
                expect(H.inCombat()).eq(false)
            end)

            it("reports through InCombatLockdown once entered", function()
                H.setCombat(true)
                expect(H.env.InCombatLockdown()).eq(true)
                H.setCombat(false)
                expect(H.env.InCombatLockdown()).eq(false)
            end)

            it("announces entering with PLAYER_REGEN_DISABLED", function()
                local seen = eventProbe("PLAYER_REGEN_DISABLED")
                H.setCombat(true)
                expect(seen.n).as("state moving without the event never happens in game").eq(1)
            end)

            it("announces leaving with PLAYER_REGEN_ENABLED", function()
                H.setCombat(true)
                local seen = eventProbe("PLAYER_REGEN_ENABLED")
                H.setCombat(false)
                expect(seen.n).eq(1)
            end)

            it("announces only a real transition", function()
                H.setCombat(true)
                local seen = eventProbe("PLAYER_REGEN_DISABLED")
                H.setCombat(true)
                expect(seen.n).as("the client does not re-announce combat it is already in").eq(0)
            end)

            it("moves the flag silently when asked", function()
                local seen = eventProbe("PLAYER_REGEN_DISABLED")
                H.setCombat(true, { silent = true })
                expect(H.env.InCombatLockdown()).as("the flag still moved").eq(true)
                expect(seen.n).as("silent is for a spec about a reader ignoring the event").eq(0)
            end)
        end)

        describe("IsProtected", function()
            it("is false for a plain frame, in both values", function()
                local p = H.parent(100, 50)
                local isProtected, explicitly = p:IsProtected()
                expect(isProtected).eq(false)
                expect(explicitly).eq(false)
            end)

            it("is explicit for a frame built from a secure template", function()
                local _, _, secure = secureGrandchildTree()
                local isProtected, explicitly = secure:IsProtected()
                expect(isProtected).eq(true)
                expect(explicitly).as("its own protection, not inherited").eq(true)
            end)

            it("is inherited by a child of a protected frame", function()
                local _, _, secure = secureGrandchildTree()
                local child = H.env.CreateFrame("Frame", nil, secure)
                local isProtected, explicitly = child:IsProtected()
                expect(isProtected).as("protection propagates DOWN").eq(true)
                expect(explicitly).as("inherited, so not explicit").eq(false)
            end)

            it("is inherited across more than one generation", function()
                local _, _, secure = secureGrandchildTree()
                local mid   = H.env.CreateFrame("Frame", nil, secure)
                local deep  = H.env.CreateFrame("Frame", nil, mid)
                expect(deep:IsProtected()).eq(true)
            end)

            it("does NOT propagate up to an ancestor", function()
                local wrapper, mid = secureGrandchildTree()
                expect(wrapper:IsProtected())
                    .as("holding a secure descendant does not make a frame protected").eq(false)
                expect(mid:IsProtected()).eq(false)
            end)

            it("is answered by a region too, from its parent", function()
                local _, _, secure = secureGrandchildTree()
                local tex = secure:CreateTexture(nil, "ARTWORK")
                expect(tex:IsProtected()).eq(true)
            end)
        end)

        describe("hasProtectedDescendant", function()
            it("finds a secure grandchild", function()
                local wrapper, mid = secureGrandchildTree()
                expect(H.hasProtectedDescendant(wrapper))
                    .as("the refusal propagates UP, so the search must too").eq(true)
                expect(H.hasProtectedDescendant(mid)).eq(true)
            end)

            it("is false for a tree with none", function()
                local p = H.parent(100, 50)
                H.env.CreateFrame("Frame", nil, p)
                expect(H.hasProtectedDescendant(p)).eq(false)
            end)

            it("is false for the secure frame's own subtree", function()
                local _, _, secure = secureGrandchildTree()
                expect(H.hasProtectedDescendant(secure))
                    .as("the frame itself is not its own descendant").eq(false)
            end)
        end)

        describe("geometry on a frame with a protected descendant", function()
            it("resizes freely out of combat", function()
                local wrapper = secureGrandchildTree()
                wrapper:SetHeight(188)
                wrapper:SetHeight(227)
                expect(wrapper:GetHeight()).as("no lockdown, no refusal").eq(227)
                expect(#H.getBlockedActions()).eq(0)
            end)

            it("is refused a resize in combat", function()
                local wrapper = secureGrandchildTree()
                wrapper:SetHeight(188)
                H.setCombat(true)
                wrapper:SetHeight(227)
                expect(wrapper:GetHeight())
                    .as("the client refuses the resize and the frame keeps its old height")
                    .eq(188)
            end)

            it("refuses without raising", function()
                local wrapper = secureGrandchildTree()
                H.setCombat(true)
                expect(function() wrapper:SetSize(300, 227) end)
                    .as("the live client prints to chat, it does not error").notThrows()
            end)

            it("resizes again the moment combat ends", function()
                local wrapper = secureGrandchildTree()
                wrapper:SetHeight(188)
                H.setCombat(true)
                wrapper:SetHeight(227)
                H.setCombat(false)
                wrapper:SetHeight(227)
                expect(wrapper:GetHeight())
                    .as("which is why deferred work waits for PLAYER_REGEN_ENABLED").eq(227)
            end)

            it("refuses every geometry setter", function()
                local wrapper, mid = secureGrandchildTree()
                H.setCombat(true)
                wrapper:SetWidth(400)
                wrapper:SetHeight(400)
                wrapper:SetSize(400, 400)
                wrapper:SetPoint("TOP", H.UIParent, "TOP", 0, -5)
                wrapper:ClearAllPoints()
                wrapper:Show()
                wrapper:Hide()
                mid:SetAllPoints(wrapper)
                local seen = {}
                for _, rec in ipairs(H.getBlockedActions()) do seen[rec.action] = true end
                for _, action in ipairs({ "SetWidth", "SetHeight", "SetSize", "SetPoint",
                                         "ClearAllPoints", "Show", "Hide", "SetAllPoints" }) do
                    expect(seen[action]).as(action .. " must be refused in combat").eq(true)
                end
            end)

            it("leaves the anchors alone when a move is refused", function()
                local wrapper = secureGrandchildTree()
                local before = wrapper:GetNumPoints()
                H.setCombat(true)
                wrapper:ClearAllPoints()
                expect(wrapper:GetNumPoints())
                    .as("a refused call changes nothing at all").eq(before)
            end)

            it("keeps a hidden frame hidden when Show is refused", function()
                local wrapper = secureGrandchildTree()
                wrapper:Hide()
                H.setCombat(true)
                wrapper:Show()
                expect(wrapper:IsShown()).as("Show is protected too").eq(false)
            end)

            it("is refused on the protected frame itself", function()
                local _, _, secure = secureGrandchildTree()
                secure:SetHeight(40)
                H.setCombat(true)
                secure:SetHeight(80)
                expect(secure:GetHeight()).eq(40)
            end)
        end)

        describe("geometry on a frame with no protected descendant", function()
            it("resizes freely in combat", function()
                local p = H.parent(300, 100)
                local child = H.env.CreateFrame("Frame", nil, p)
                child:SetAllPoints(p)
                H.setCombat(true)
                p:SetHeight(227)
                expect(p:GetHeight())
                    .as("lockdown restricts protected subtrees, not every frame").eq(227)
                expect(#H.getBlockedActions()).as("and records nothing").eq(0)
            end)

            it("shows and hides freely in combat", function()
                local p = H.parent(300, 100)
                H.setCombat(true)
                p:Hide()
                expect(p:IsShown()).eq(false)
                p:Show()
                expect(p:IsShown()).eq(true)
            end)
        end)

        describe("the refusal record", function()
            it("records the call, the frame and why", function()
                local wrapper = secureGrandchildTree()
                H.setCombat(true)
                wrapper:SetSize(300, 227)
                local log = H.getBlockedActions()
                expect(#log).eq(1)
                expect(log[1].action).eq("SetSize")
                expect(log[1].frame).eq(wrapper)
                expect(log[1].protected)
                    .as("refused for its descendant, not for itself").eq(false)
            end)

            it("marks a refusal on the protected frame itself", function()
                local _, _, secure = secureGrandchildTree()
                H.setCombat(true)
                secure:SetHeight(80)
                expect(H.getBlockedActions()[1].protected).eq(true)
            end)

            it("records in call order", function()
                local wrapper = secureGrandchildTree()
                H.setCombat(true)
                wrapper:SetWidth(400)
                wrapper:SetHeight(400)
                local log = H.getBlockedActions()
                expect(log[1].action).eq("SetWidth")
                expect(log[2].action).eq("SetHeight")
            end)

            it("records nothing out of combat", function()
                local wrapper = secureGrandchildTree()
                wrapper:SetSize(300, 227)
                expect(#H.getBlockedActions()).eq(0)
            end)

            it("clears on resetBlockedActions", function()
                local wrapper = secureGrandchildTree()
                H.setCombat(true)
                wrapper:SetHeight(227)
                H.resetBlockedActions()
                expect(#H.getBlockedActions())
                    .as("so one spec can assert a second call cleanly").eq(0)
            end)

            it("hands back a copy, not the live list", function()
                local wrapper = secureGrandchildTree()
                H.setCombat(true)
                wrapper:SetHeight(227)
                local log = H.getBlockedActions()
                wrapper:SetWidth(400)
                expect(#log).as("a held list does not grow underneath a spec").eq(1)
            end)
        end)

        describe("reset", function()
            it("leaves combat", function()
                H.setCombat(true)
                H.setup()
                expect(H.env.InCombatLockdown())
                    .as("a leaked flag makes the next spec file silently unresizable").eq(false)
            end)

            it("clears the refusal record", function()
                local wrapper = secureGrandchildTree()
                H.setCombat(true)
                wrapper:SetHeight(227)
                expect(#H.getBlockedActions()).eq(1)
                H.setup()
                expect(#H.getBlockedActions())
                    .as("a leaked record lets an assertion pass before the call happens").eq(0)
            end)

            it("resizes freely again after a reset from combat", function()
                H.setCombat(true)
                H.setup()
                local wrapper = secureGrandchildTree()
                wrapper:SetHeight(227)
                expect(wrapper:GetHeight()).eq(227)
            end)
        end)
    end)

    ---------------------------------------------------------------------------
    -- Auras (UnitAura / UnitBuff / UnitDebuff)
    ---------------------------------------------------------------------------
    describe("auras", function()
        it("returns nil for a unit that does not exist", function()
            expect(H.env.UnitAura("target", 1, "HELPFUL")).isNil()
        end)

        it("returns nil for a unit with no staged auras", function()
            H.setUnit("target", { health = 50 })
            expect(H.env.UnitAura("target", 1, "HELPFUL")).isNil()
        end)

        it("returns nil past the end of the aura list", function()
            H.setAuras("player", { helpful = { { name = "Fortitude" } } })
            expect(H.env.UnitAura("player", 2, "HELPFUL")).isNil()
        end)

        it("returns all 15 values in the 2.5.4 order", function()
            H.setAuras("player", { helpful = { {
                name = "Power Word: Fortitude",
                icon = "Interface\\Icons\\Spell_Holy_WordFortitude",
                count = 0,
                debuffType = nil,
                duration = 1800,
                expirationTime = 2000,
                source = "player",
                isStealable = false,
                spellId = 1243,
                canApplyAura = true,
                isBossDebuff = false,
                castByPlayer = true,
                timeMod = 1,
            } } })
            local name, icon, count, debuffType, duration, expirationTime,
                  source, isStealable, nameplateShowPersonal, spellId,
                  canApplyAura, isBossDebuff, castByPlayer, nameplateShowAll, timeMod =
                  H.env.UnitAura("player", 1, "HELPFUL")
            expect(name).eq("Power Word: Fortitude")
            expect(icon).eq("Interface\\Icons\\Spell_Holy_WordFortitude")
            expect(count).eq(0)
            expect(debuffType).isNil()
            expect(duration).eq(1800)
            expect(expirationTime).eq(2000)
            expect(source).eq("player")
            expect(isStealable).eq(false)
            expect(nameplateShowPersonal).eq(false)
            expect(spellId).eq(1243)
            expect(canApplyAura).eq(true)
            expect(isBossDebuff).eq(false)
            expect(castByPlayer).eq(true)
            expect(nameplateShowAll).eq(false)
            expect(timeMod).eq(1)
        end)

        it("treats nil filter as HELPFUL", function()
            H.setAuras("player", {
                helpful = { { name = "Buff" } },
                harmful = { { name = "Debuff" } },
            })
            local name = H.env.UnitAura("player", 1, nil)
            expect(name).eq("Buff")
        end)

        it("filters HARMFUL correctly", function()
            H.setAuras("player", {
                helpful = { { name = "Buff" } },
                harmful = { { name = "Corruption", debuffType = "Magic" } },
            })
            local name, _, _, debuffType = H.env.UnitAura("player", 1, "HARMFUL")
            expect(name).eq("Corruption")
            expect(debuffType).eq("Magic")
        end)

        it("a non-stacking aura reports count = 0", function()
            H.setAuras("player", { helpful = { { name = "Mark of the Wild", count = 0 } } })
            local _, _, count = H.env.UnitAura("player", 1, "HELPFUL")
            expect(count).eq(0)
        end)

        it("a buff can carry a debuffType", function()
            -- Righteous Fury is a buff with Magic debuff type
            H.setAuras("player", { helpful = { { name = "Righteous Fury", debuffType = "Magic" } } })
            local name, _, _, debuffType = H.env.UnitBuff("player", 1)
            expect(name).eq("Righteous Fury")
            expect(debuffType).eq("Magic")
        end)

        it("UnitBuff is the HELPFUL form of UnitAura", function()
            H.setAuras("player", { helpful = { { name = "Renew" } } })
            local name = H.env.UnitBuff("player", 1)
            expect(name).eq("Renew")
        end)

        it("UnitDebuff is the HARMFUL form of UnitAura", function()
            H.setAuras("player", { harmful = { { name = "Shadow Word: Pain" } } })
            local name = H.env.UnitDebuff("player", 1)
            expect(name).eq("Shadow Word: Pain")
        end)

        it("fires UNIT_AURA with the unit when setAuras is called", function()
            local fired = {}
            local listener = H.env.CreateFrame("Frame", nil, H.UIParent)
            listener:RegisterEvent("UNIT_AURA")
            listener:SetScript("OnEvent", function(_, event, unit)
                fired[#fired + 1] = { event = event, unit = unit }
            end)
            H.setAuras("player", { helpful = { { name = "Buff" } } })
            expect(#fired).eq(1)
            expect(fired[1].event).eq("UNIT_AURA")
            expect(fired[1].unit).eq("player")
        end)

        it("fires UNIT_AURA when clearAuras is called", function()
            H.setAuras("player", { helpful = { { name = "Buff" } } }, { silent = true })
            local fired = {}
            local listener = H.env.CreateFrame("Frame", nil, H.UIParent)
            listener:RegisterEvent("UNIT_AURA")
            listener:SetScript("OnEvent", function(_, event, unit)
                fired[#fired + 1] = { event = event, unit = unit }
            end)
            H.clearAuras("player")
            expect(#fired).eq(1)
            expect(fired[1].unit).eq("player")
        end)

        it("suppresses UNIT_AURA with silent option", function()
            local spy = H.eventSpy("UNIT_AURA")
            H.setAuras("player", { helpful = { { name = "Buff" } } }, { silent = true })
            expect(spy.count).eq(0)
        end)

        it("clearAuras makes UnitAura return nil", function()
            H.setAuras("player", { helpful = { { name = "Buff" } } }, { silent = true })
            H.clearAuras("player", { silent = true })
            expect(H.env.UnitAura("player", 1, "HELPFUL")).isNil()
        end)

        it("rejects unknown aura fields", function()
            expect(function()
                H.setAuras("player", { helpful = { { bogusField = 1 } } })
            end).throws()
        end)
    end)

    ---------------------------------------------------------------------------
    -- CancelUnitBuff
    ---------------------------------------------------------------------------
    describe("CancelUnitBuff", function()
        it("records the call with unit and index", function()
            H.env.CancelUnitBuff("player", 3)
            local rec = H.getCancelBuff()
            expect(rec).notNil()
            expect(rec.unit).eq("player")
            expect(rec.index).eq(3)
        end)

        it("resetCancelBuff clears the record", function()
            H.env.CancelUnitBuff("player", 1)
            H.resetCancelBuff()
            expect(H.getCancelBuff()).isNil()
        end)
    end)

    ---------------------------------------------------------------------------
    -- DebuffTypeColor
    ---------------------------------------------------------------------------
    describe("DebuffTypeColor", function()
        it("provides Magic/Curse/Disease/Poison/none entries", function()
            local dtc = H.env.DebuffTypeColor
            for _, key in ipairs({ "Magic", "Curse", "Disease", "Poison", "none" }) do
                expect(dtc[key]).as(key).notNil()
                expect(dtc[key].r).as(key .. ".r").notNil()
                expect(dtc[key].g).as(key .. ".g").notNil()
                expect(dtc[key].b).as(key .. ".b").notNil()
            end
        end)

        it("can be retinted by a spec and the addon follows", function()
            H.env.DebuffTypeColor.Magic = { r = 1, g = 0, b = 0 }
            expect(H.env.DebuffTypeColor.Magic.r).eq(1)
            expect(H.env.DebuffTypeColor.Magic.g).eq(0)
        end)
    end)

    ---------------------------------------------------------------------------
    -- GameTooltip
    ---------------------------------------------------------------------------
    describe("GameTooltip", function()
        it("exists as a global frame", function()
            expect(H.env.GameTooltip).notNil()
        end)

        it("records SetOwner", function()
            local anchor = H.parent(100, 50)
            H.GameTooltip:SetOwner(anchor, "ANCHOR_RIGHT")
            local ts = H.getTooltipState()
            expect(ts.owner).eq(anchor)
            expect(ts.anchor).eq("ANCHOR_RIGHT")
        end)

        it("records SetUnitBuff", function()
            H.GameTooltip:SetOwner(H.UIParent, "ANCHOR_CURSOR")
            H.GameTooltip:SetUnitBuff("player", 2)
            local ts = H.getTooltipState()
            expect(ts.aura.unit).eq("player")
            expect(ts.aura.index).eq(2)
            expect(ts.aura.filter).eq("HELPFUL")
        end)

        it("records SetUnitDebuff", function()
            H.GameTooltip:SetOwner(H.UIParent, "ANCHOR_CURSOR")
            H.GameTooltip:SetUnitDebuff("target", 5)
            local ts = H.getTooltipState()
            expect(ts.aura.unit).eq("target")
            expect(ts.aura.index).eq(5)
            expect(ts.aura.filter).eq("HARMFUL")
        end)

        it("records SetUnitAura with explicit filter", function()
            H.GameTooltip:SetOwner(H.UIParent, "ANCHOR_CURSOR")
            H.GameTooltip:SetUnitAura("player", 1, "HARMFUL")
            local ts = H.getTooltipState()
            expect(ts.aura.filter).eq("HARMFUL")
        end)

        it("ClearLines removes the aura but keeps owner", function()
            H.GameTooltip:SetOwner(H.UIParent, "ANCHOR_LEFT")
            H.GameTooltip:SetUnitBuff("player", 1)
            H.GameTooltip:ClearLines()
            local ts = H.getTooltipState()
            expect(ts.aura).isNil()
            expect(ts.owner).eq(H.UIParent)
        end)

        it("Hide makes IsShown false", function()
            H.GameTooltip:Show()
            expect(H.GameTooltip:IsShown()).eq(true)
            H.GameTooltip:Hide()
            expect(H.GameTooltip:IsShown()).eq(false)
        end)

        it("provides ANCHOR_* globals", function()
            expect(H.env.ANCHOR_NONE).eq("ANCHOR_NONE")
            expect(H.env.ANCHOR_CURSOR).eq("ANCHOR_CURSOR")
            expect(H.env.ANCHOR_BOTTOMRIGHT).eq("ANCHOR_BOTTOMRIGHT")
        end)
    end)

    ---------------------------------------------------------------------------
    -- Cooldown frame subtype
    ---------------------------------------------------------------------------
    describe("Cooldown frame", function()
        it("CreateFrame with Cooldown type works", function()
            local cd = H.env.CreateFrame("Cooldown", nil, H.UIParent, "CooldownFrameTemplate")
            expect(cd).notNil()
            expect(cd:GetObjectType()).eq("Cooldown")
        end)

        it("SetCooldown stores start and duration", function()
            local cd = H.env.CreateFrame("Cooldown", nil, H.UIParent, "CooldownFrameTemplate")
            cd:SetCooldown(100, 30)
            local start, dur = cd:GetCooldownTimes()
            expect(start).eq(100)
            expect(dur).eq(30)
        end)

        it("Clear resets cooldown state", function()
            local cd = H.env.CreateFrame("Cooldown", nil, H.UIParent, "CooldownFrameTemplate")
            cd:SetCooldown(50, 10)
            cd:Clear()
            local start, dur = cd:GetCooldownTimes()
            expect(start).eq(0)
            expect(dur).eq(0)
        end)

        it("SetDrawSwipe/SetDrawEdge/SetHideCountdownNumbers/SetReverse store state", function()
            local cd = H.env.CreateFrame("Cooldown", nil, H.UIParent, "CooldownFrameTemplate")
            cd:SetDrawSwipe(true)
            cd:SetDrawEdge(false)
            cd:SetHideCountdownNumbers(true)
            cd:SetReverse(true)
            expect(cd._drawSwipe).eq(true)
            expect(cd._drawEdge).eq(false)
            expect(cd._hideNumbers).eq(true)
            expect(cd._reverse).eq(true)
        end)

        it("SetSwipeColor stores colour", function()
            local cd = H.env.CreateFrame("Cooldown", nil, H.UIParent, "CooldownFrameTemplate")
            cd:SetSwipeColor(0.5, 0.3, 0.1, 0.8)
            expect(cd._swipeColor[1]).near(0.5, 0.001)
            expect(cd._swipeColor[4]).near(0.8, 0.001)
        end)

        it("can be armed and then cleared (aura with no duration case)", function()
            local cd = H.env.CreateFrame("Cooldown", nil, H.UIParent, "CooldownFrameTemplate")
            cd:SetCooldown(200, 60)
            -- The aura expires or is removed: clear the swipe
            cd:Clear()
            local start, dur = cd:GetCooldownTimes()
            expect(start).eq(0)
            expect(dur).eq(0)
        end)

        it("supports all Frame methods (anchors, scripts, strata)", function()
            local cd = H.env.CreateFrame("Cooldown", nil, H.UIParent, "CooldownFrameTemplate")
            cd:SetSize(20, 20)
            cd:SetPoint("CENTER", H.UIParent, "CENTER", 0, 0)
            expect(cd:GetWidth()).eq(20)
            cd:SetFrameLevel(5)
            expect(cd:GetFrameLevel()).eq(5)
        end)
    end)

    ---------------------------------------------------------------------------
    -- state.reset clears new fields
    ---------------------------------------------------------------------------
    describe("state.reset clears aura, tooltip and cancel records", function()
        it("clears auras", function()
            H.setAuras("player", { helpful = { { name = "Buff" } } }, { silent = true })
            H.setup()
            expect(H.env.UnitAura("player", 1, "HELPFUL")).isNil()
        end)

        it("clears tooltip state", function()
            H.GameTooltip:SetOwner(H.UIParent, "ANCHOR_RIGHT")
            H.GameTooltip:SetUnitBuff("player", 1)
            H.setup()
            expect(H.getTooltipState()).isNil()
        end)

        it("clears cancelBuff record", function()
            H.env.CancelUnitBuff("player", 1)
            H.setup()
            expect(H.getCancelBuff()).isNil()
        end)
    end)

    ---------------------------------------------------------------------------
    -- GetTime advances with the harness clock
    ---------------------------------------------------------------------------
    describe("GetTime and clock", function()
        it("starts at 0", function()
            expect(H.env.GetTime()).eq(0)
        end)

        it("advances with H.tick", function()
            H.tick(1.5)
            expect(H.env.GetTime()).near(1.5, 0.001)
        end)
    end)
end)
