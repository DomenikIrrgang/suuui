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

    describe("frame clipping", function()
        -- A short window over taller content: the shape an Accordion collapses through. The
        -- body keeps its full height while the window shrinks over it, so with no clip its
        -- rows would draw straight over whatever sits below the window.
        local function windowAndBody(windowH, bodyH)
            local host   = H.parent(200, 400)
            local window = H.env.CreateFrame("Frame", nil, host)
            window:SetPoint("TOPLEFT", host, "TOPLEFT", 0, 0)
            window:SetSize(200, windowH or 40)
            local body = H.env.CreateFrame("Frame", nil, window)
            body:SetPoint("TOPLEFT", window, "TOPLEFT", 0, 0)
            body:SetSize(200, bodyH or 100)
            return window, body, host
        end

        it("does not clip by default", function()
            local window, body = windowAndBody(40, 100)
            expect(H.clipsChildren(window)).as("clipping is opt-in, as in the client").eq(false)
            expect(window:DoesClipChildren()).eq(false)
            expect(H.clipAncestor(body)).isNil()
            expect(H.isClipped(body)).as("a taller child spills when nothing clips it").eq(false)
            expect(H.visibleBox(body)).deepEq(H.box(body))
        end)

        it("leaves a child that fits entirely inside its window unclipped", function()
            local window, body = windowAndBody(100, 40)
            window:SetClipsChildren(true)
            expect(window:DoesClipChildren()).eq(true)
            expect(H.clipAncestor(body)).eq(window)
            expect(H.isClipped(body)).eq(false)
            expect(H.visibleBox(body))
                .as("wholly inside, so the visible box is the box").deepEq(H.box(body))
        end)

        it("cuts a child taller than its window down to the overlap", function()
            local window, body = windowAndBody(40, 100)
            window:SetClipsChildren(true)
            local wb, bb = H.box(window), H.box(body)
            expect(bb.height).as("the body still reports the height it was assigned").eq(100)
            expect(H.isClipped(body)).eq(true)
            local vis = H.visibleBox(body)
            expect(vis).notNil()
            expect(vis.left).eq(bb.left)
            expect(vis.width).eq(bb.width)
            expect(vis.top).as("the window's top edge, measured downward").eq(wb.top)
            expect(vis.height).as("only the band inside the window draws").eq(wb.height)
            expect(vis.bottom).eq(wb.bottom)
        end)

        it("reports no visible box for a child pushed entirely outside its window", function()
            local window, body = windowAndBody(40, 40)
            window:SetClipsChildren(true)
            body:ClearAllPoints()
            body:SetPoint("TOPLEFT", window, "BOTTOMLEFT", 0, -10)
            expect(H.box(body)).as("the solver still places it").notNil()
            expect(H.visibleBox(body)).as("none of it draws").isNil()
            expect(H.isClipped(body)).eq(true)
        end)

        it("intersects nested clips on both axes", function()
            -- Outer clips vertically (60 tall), inner clips horizontally (120 wide). Either
            -- clip alone leaves the body wrong on the other axis, so the answer has to be
            -- the intersection of both.
            local host  = H.parent(200, 400)
            local outer = H.env.CreateFrame("Frame", nil, host)
            outer:SetPoint("TOPLEFT", host, "TOPLEFT", 0, 0)
            outer:SetSize(200, 60)
            outer:SetClipsChildren(true)
            local inner = H.env.CreateFrame("Frame", nil, outer)
            inner:SetPoint("TOPLEFT", outer, "TOPLEFT", 0, 0)
            inner:SetSize(120, 200)
            inner:SetClipsChildren(true)
            local body = H.env.CreateFrame("Frame", nil, inner)
            body:SetPoint("TOPLEFT", inner, "TOPLEFT", 0, 0)
            body:SetSize(200, 200)

            expect(H.clipAncestor(body)).as("nearest first").eq(inner)
            local vis = H.visibleBox(body)
            expect(vis).notNil()
            expect(vis.width).as("width comes from the inner clip").eq(120)
            expect(vis.height).as("height comes from the outer clip").eq(60)
            expect(H.isClipped(body)).eq(true)
        end)

        it("applies a clip three generations up", function()
            local window = windowAndBody(40, 100)
            window:SetClipsChildren(true)
            local a = H.env.CreateFrame("Frame", nil, window)
            a:SetPoint("TOPLEFT", window, "TOPLEFT", 0, 0)
            a:SetSize(200, 100)
            local b = H.env.CreateFrame("Frame", nil, a)
            b:SetPoint("TOPLEFT", a, "TOPLEFT", 0, 0)
            b:SetSize(200, 100)
            local leaf = H.env.CreateFrame("Frame", nil, b)
            leaf:SetPoint("TOPLEFT", b, "TOPLEFT", 0, 0)
            leaf:SetSize(200, 100)

            expect(H.clipAncestor(leaf))
                .as("the walk does not stop at the direct parent").eq(window)
            expect(H.isClipped(leaf)).eq(true)
            expect(H.visibleBox(leaf).height).eq(40)
        end)

        it("walks past a non-clipping frame in between", function()
            local window = windowAndBody(40, 100)
            window:SetClipsChildren(true)
            local mid = H.env.CreateFrame("Frame", nil, window)
            mid:SetPoint("TOPLEFT", window, "TOPLEFT", 0, 0)
            mid:SetSize(200, 100)
            mid:SetClipsChildren(false)
            local leaf = H.env.CreateFrame("Frame", nil, mid)
            leaf:SetPoint("TOPLEFT", mid, "TOPLEFT", 0, 0)
            leaf:SetSize(200, 100)

            expect(H.clipsChildren(mid)).eq(false)
            expect(H.clipAncestor(leaf))
                .as("a frame that does not clip is stepped over, not the end of the walk").eq(window)
            expect(H.visibleBox(leaf).height).eq(40)
            expect(H.isClipped(leaf)).eq(true)
        end)

        it("restores the unclipped answer when the clip is turned off", function()
            local window, body = windowAndBody(40, 100)
            window:SetClipsChildren(true)
            expect(H.isClipped(body)).eq(true)
            window:SetClipsChildren(false)
            expect(H.clipsChildren(window)).eq(false)
            expect(window:DoesClipChildren()).eq(false)
            expect(H.clipAncestor(body)).isNil()
            expect(H.isClipped(body)).eq(false)
            expect(H.visibleBox(body)).deepEq(H.box(body))
        end)

        it("does not count a frame's own clip against itself", function()
            local window = windowAndBody(40, 100)
            window:SetClipsChildren(true)
            expect(H.clipsChildren(window)).as("it clips what is inside it").eq(true)
            expect(H.clipAncestor(window))
                .as("SetClipsChildren clips descendants, never the frame's own rect").isNil()
            expect(H.isClipped(window)).eq(false)
            expect(H.visibleBox(window)).deepEq(H.box(window))
        end)

        it("clips by parentage, not by the anchor chain", function()
            local window = windowAndBody(40, 100)
            local host = window:GetParent()
            window:SetClipsChildren(true)
            local outsider = H.env.CreateFrame("Frame", nil, host)
            outsider:SetPoint("TOPLEFT", window, "TOPLEFT", 0, 0)
            outsider:SetSize(200, 100)
            expect(H.clipAncestor(outsider))
                .as("anchoring to a window does not put a frame inside it").isNil()
            expect(H.isClipped(outsider)).eq(false)
            expect(H.visibleBox(outsider)).deepEq(H.box(outsider))
        end)

        it("clips a region, which has no children of its own to clip", function()
            local window = windowAndBody(40, 100)
            window:SetClipsChildren(true)
            local tex = window:CreateTexture(nil, "ARTWORK")
            tex:SetPoint("TOPLEFT", window, "TOPLEFT", 0, 0)
            tex:SetSize(200, 100)
            expect(H.clipsChildren(tex)).as("a texture answers false, it does not raise").eq(false)
            expect(H.clipAncestor(tex)).eq(window)
            expect(H.visibleBox(tex).height).eq(40)
        end)

        it("resolves a container and a component handle through GetFrame", function()
            local host   = H.parent(200, 200)
            local window = H.Layout:CreateContainer({
                parent = host, layout = "anchor", w = 200, h = 10,
            })
            local wf = window:GetFrame()
            wf:SetClipsChildren(true)
            expect(H.clipsChildren(window)).as("a container handle answers for its frame").eq(true)

            local btn = H.C.Button({ label = "OK" }, wf)
            window:Add(btn, { anchor = {
                point = "TOPLEFT", relativePoint = "TOPLEFT", x = 0, y = 0,
            } })
            expect(H.clipAncestor(btn)).as("a handle walks its own frame's parents").eq(wf)
            expect(H.isClipped(btn)).as("a control taller than a 10px window").eq(true)
            expect(H.visibleBox(btn).height).eq(H.box(wf).height)
        end)

        it("leaves H.box reporting the assigned rect, clip or no clip", function()
            local window, body = windowAndBody(40, 100)
            local before = H.box(body)
            window:SetClipsChildren(true)
            expect(H.box(body))
                .as("the solver must not start clipping: specs measure assigned rects")
                .deepEq(before)
            H.expectSize(body, 200, 100)
            -- The overflow is still THERE in the assigned rect, which is the whole point:
            -- only H.visibleBox knows about the clip. Stated as the overflow rather than
            -- with expectInside, which ASSERTS containment and would be asserting the
            -- body does not overflow — the opposite of what this spec is about.
            expect(H.box(body).bottom)
                .as("bottom measures downward, so an overflowing child reports the larger value")
                .gt(H.box(window).bottom)
            expect(H.isClipped(body)).as("and the clip is reported separately").eq(true)
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

        it("collapses an explicit newline onto one row when wrap is off", function()
            -- The client's behaviour, measured in game: SetWordWrap(false) renders a SINGLE
            -- row and folds an embedded newline into it rather than breaking on it. A
            -- FontString holding "Local  22:21\nRealm  22:20" reported GetStringHeight() = 13
            -- -- one row -- and drew both halves concatenated.
            --
            -- The model used to split on the newline whatever the flag said, which is how a
            -- two-row tooltip shipped rendering "Local  22:17..." with every assertion about
            -- its placement and its text content passing.
            local p = H.parent(400, 100)
            local fs = p:CreateFontString(nil, "OVERLAY", "GameFontNormal")
            fs:SetFont("Fonts/FRIZQT__.TTF", 12, "")
            fs:SetText("Local  22:21\nRealm  22:20")

            fs:SetWordWrap(false)
            expect(fs:GetNumLines()).as("one row: the newline buys nothing").eq(1)
            expect(fs:GetStringHeight()).eq(H.lineHeight(12))

            fs:SetWordWrap(true)
            expect(fs:GetNumLines()).as("two rows once wrapping is allowed").eq(2)
            expect(fs:GetStringHeight()).eq(H.lineHeight(12) * 2)
        end)

        it("needs the whole string on one row to be unclipped when wrap is off", function()
            -- The width half of the same rule: with one row there is no newline relief, so a
            -- box wide enough for the widest LINE is still a clip.
            local p = H.parent(400, 100)
            local fs = p:CreateFontString(nil, "OVERLAY", "GameFontNormal")
            fs:SetFont("Fonts/FRIZQT__.TTF", 12, "")
            fs:SetText("Local  22:21\nRealm  22:20")
            fs:SetWordWrap(false)
            fs:SetSize(H.textBox("Local  22:21", 12), H.lineHeight(12))
            expect(fs:IsTextClipped()).as("the second half has nowhere to go").truthy()
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

    ---------------------------------------------------------------------------
    -- The wall clock time() and date() report, and the realm clock GetGameTime does.
    --
    -- Load-bearing for any clock widget: date() is MODELLED rather than delegated, and it
    -- forces UTC, so "what does the clock say" is the same answer on every machine. A spec
    -- asserting "14:32" would otherwise pass in London and fail in Berlin.
    ---------------------------------------------------------------------------
    describe("wall clock and realm clock", function()
        -- 2026-08-22 14:32:07 UTC, the reset default. Named once here so a change to
        -- state.wallClock fails in this block rather than mysteriously in a widget spec.
        local DEFAULT = 1787409127

        it("starts at the documented default instant", function()
            expect(H.env.time()).eq(DEFAULT)
            expect(H.env.date("%Y-%m-%d %H:%M:%S")).eq("2026-08-22 14:32:07")
        end)

        it("reads 14:32 on an unconfigured clock", function()
            -- The value every clock spec leans on, stated on its own so the dependency is
            -- visible from here.
            expect(H.env.date("%H:%M")).eq("14:32")
        end)

        it("formats in UTC, not in the timezone of the machine running the suite", function()
            -- The invariant: every format is answered as though "!" had been prepended.
            for _, fmt in ipairs({ "%H:%M", "%H:%M:%S", "%Y-%m-%d", "%I:%M %p", "%c" }) do
                expect(H.env.date(fmt)).as(fmt).eq(os.date("!" .. fmt, DEFAULT))
            end
            -- And the non-vacuous half, which only bites when the machine is off UTC: a
            -- delegating implementation would answer the local hour here. On a machine
            -- already set to UTC the two agree and this can only pass, which is exactly why
            -- the fixed "14:32" assertion above is stated as well.
            if os.date("%H", DEFAULT) ~= os.date("!%H", DEFAULT) then
                expect(H.env.date("%H")).as("the local hour is not what the harness reports")
                    .neq(os.date("%H", DEFAULT))
            end
        end)

        it("does not double-prefix a format that already asks for UTC", function()
            expect(H.env.date("!%H:%M")).eq("14:32")
        end)

        it("formats an explicit instant rather than the wall clock", function()
            expect(H.env.date("%H:%M", DEFAULT + 3600)).eq("15:32")
            expect(H.env.time()).as("and reading one does not move the other").eq(DEFAULT)
        end)

        it("moves with H.setClock, which returns the epoch now in force", function()
            expect(H.setClock(DEFAULT + 60)).eq(DEFAULT + 60)
            expect(H.env.time()).eq(DEFAULT + 60)
            expect(H.env.date("%H:%M")).eq("14:33")
        end)

        it("takes a table of UTC parts that agrees with the epoch form", function()
            -- Both forms name the same instant, so they must produce the same number: the
            -- table form exists for readability, not for a second definition of "now".
            local fromTable = H.setClock({
                year = 2026, month = 8, day = 22, hour = 14, min = 32, sec = 7,
            })
            expect(fromTable).as("the parts of the default instant").eq(DEFAULT)
            local fromEpoch = H.setClock(DEFAULT)
            expect(fromTable).eq(fromEpoch)
            expect(H.env.date("%Y-%m-%d %H:%M:%S")).eq("2026-08-22 14:32:07")
        end)

        it("round-trips a table of parts back through date()", function()
            -- Covers the month-length and leap-year arithmetic the table form does by hand
            -- rather than through os.time, which would read the parts as local time.
            local cases = {
                { year = 1970, month = 1,  day = 1,  hour = 0,  min = 0,  sec = 0 },
                { year = 2000, month = 2,  day = 29, hour = 12, min = 0,  sec = 0 },
                { year = 2024, month = 2,  day = 29, hour = 23, min = 59, sec = 59 },
                -- The day AFTER February, which is the only place February's own length is
                -- read: a case inside February never consults it, so a spec built only from
                -- leap DAYS asserts nothing about leap years.
                { year = 2024, month = 3,  day = 1,  hour = 0,  min = 0,  sec = 1 },
                { year = 2000, month = 3,  day = 1,  hour = 1,  min = 0,  sec = 0 },
                { year = 2026, month = 12, day = 31, hour = 0,  min = 5,  sec = 0 },
                -- 2100 is divisible by 100 but not 400, so it is NOT a leap year — the
                -- century rule, in the direction opposite to 2000.
                { year = 2100, month = 3,  day = 1,  hour = 6,  min = 30, sec = 15 },
            }
            for _, parts in ipairs(cases) do
                H.setClock(parts)
                local want = string.format("%04d-%02d-%02d %02d:%02d:%02d",
                    parts.year, parts.month, parts.day, parts.hour, parts.min, parts.sec)
                expect(H.env.date("%Y-%m-%d %H:%M:%S")).as(want).eq(want)
            end
        end)

        it("defaults omitted parts to the start of the epoch", function()
            expect(H.setClock({})).eq(0)
            expect(H.env.date("%Y-%m-%d %H:%M:%S")).eq("1970-01-01 00:00:00")
        end)

        it("is not GetTime: neither clock moves the other", function()
            local uptime = H.env.GetTime()
            H.setClock(DEFAULT + 86400)
            expect(H.env.GetTime()).as("uptime is untouched by the wall clock").eq(uptime)

            local wall = H.env.time()
            H.tick(5)
            expect(H.env.time()).as("and a frame does not move the wall clock").eq(wall)
            expect(H.env.GetTime()).near(uptime + 5, 0.001)
        end)

        it("is reset by H.setup, so a moved clock cannot leak into the next spec", function()
            H.setClock(0)
            H.setup()
            expect(H.env.time()).eq(DEFAULT)
        end)

        it("has GetGameTime agree with the wall clock until a spec says otherwise", function()
            local hour, minute = H.env.GetGameTime()
            expect(hour).eq(14)
            expect(minute).eq(32)
            H.setClock({ year = 2026, month = 8, day = 22, hour = 3, min = 7, sec = 0 })
            hour, minute = H.env.GetGameTime()
            expect(hour).as("still following the wall clock").eq(3)
            expect(minute).eq(7)
        end)

        it("diverges the realm clock with H.setRealmTime", function()
            -- The divergence a clock widget's hover exists to show: a realm need not agree
            -- with the player's own clock.
            H.setRealmTime(3, 7)
            local hour, minute = H.env.GetGameTime()
            expect(hour).eq(3)
            expect(minute).eq(7)
            expect(H.env.date("%H:%M")).as("the wall clock did not move").eq("14:32")
        end)

        it("clears the realm clock back to the wall clock with a nil hour", function()
            H.setRealmTime(3, 7)
            H.setRealmTime(nil)
            local hour, minute = H.env.GetGameTime()
            expect(hour).eq(14)
            expect(minute).eq(32)
        end)

        it("resets the realm clock on H.setup", function()
            H.setRealmTime(3, 7)
            H.setup()
            local hour = H.env.GetGameTime()
            expect(hour).as("a staged realm clock cannot leak into the next spec").eq(14)
        end)
    end)

    ---------------------------------------------------------------------------
    -- The performance readings GetFramerate() and GetNetStats() report.
    --
    -- Same kind of coverage as the clock block above, for the same reason: a fixed reset
    -- default is what lets an unconfigured readout render the same thing in every run, and
    -- a staged one that leaked would put the next spec file's readout in its warning colour
    -- and pass for the wrong reason.
    --
    -- Both are POLLED rather than announced — no event fires when either changes, which is
    -- why a widget reading them declares an `update` interval instead of an event.
    ---------------------------------------------------------------------------
    describe("performance readouts (GetFramerate / GetNetStats)", function()
        it("reports 60 fps on an unconfigured client", function()
            expect(H.env.GetFramerate()).eq(60)
        end)

        it("moves with H.setFramerate", function()
            H.setFramerate(12.5)
            expect(H.env.GetFramerate()).eq(12.5)
            H.setFramerate(144)
            expect(H.env.GetFramerate()).as("and again, so it is read live not cached").eq(144)
            -- The other 60 in the client: the reset default is one source, GetFramerate's own
            -- `or 60` guard is the other, and only a nil reading reaches the second. Without
            -- this line an assertion on 60 cannot tell the two apart.
            H.setFramerate(nil)
            expect(H.env.GetFramerate()).as("a cleared reading falls back to 60").eq(60)
        end)

        it("defaults to four returns, all zero", function()
            expect(select("#", H.env.GetNetStats()))
                .as("the newer client's four-value shape").eq(4)
            local down, up, home, world = H.env.GetNetStats()
            expect(down).eq(0)
            expect(up).eq(0)
            expect(home).eq(0)
            expect(world).eq(0)
        end)

        it("stages all four values, each in its own position", function()
            -- Four DISTINCT values on purpose. A test that only checked the set of values
            -- would pass with home and world transposed, and a reader indexes these by
            -- position — the third slot is the one that exists on both API generations.
            H.setNetStats(11, 22, 33, 44)
            local down, up, home, world = H.env.GetNetStats()
            expect(down).as("1st return: bandwidth in").eq(11)
            expect(up).as("2nd return: bandwidth out").eq(22)
            expect(home).as("3rd return: home latency").eq(33)
            expect(world).as("4th return: world latency").eq(44)
        end)

        it("falls back to zero in every slot when nothing is staged", function()
            H.setNetStats(500, 400, 300, 200)
            H.setNetStats()
            expect(select("#", H.env.GetNetStats())).as("still four returns").eq(4)
            local down, up, home, world = H.env.GetNetStats()
            expect(down).eq(0)
            expect(up).eq(0)
            expect(home).eq(0)
            expect(world).eq(0)
        end)

        it("returns exactly three values for world = false, the older client", function()
            -- The shape a reader has to survive: one latency in the third slot and NOTHING
            -- in the fourth. Asserted as an arity, because a reader has a branch for it and
            -- "absent" is a different fact from "present and zero".
            H.setNetStats(11, 22, 33, false)
            expect(select("#", H.env.GetNetStats()))
                .as("the older API has no fourth return").eq(3)
            local down, up, home, world = H.env.GetNetStats()
            expect(down).eq(11)
            expect(up).eq(22)
            expect(home).as("the single latency stays in the third slot").eq(33)
            expect(world).as("absent, not zero").isNil()
        end)

        it("distinguishes an absent fourth return from a zero one", function()
            -- The two cases are provably different, which is the whole reason `false` exists
            -- as a value: passing 0 is a client reporting no world lag, passing false is a
            -- client that cannot report one at all.
            H.setNetStats(11, 22, 33, 0)
            local zeroArity = select("#", H.env.GetNetStats())
            local _, _, _, zeroWorld = H.env.GetNetStats()
            expect(zeroArity).as("a zero world latency is still four returns").eq(4)
            expect(zeroWorld).as("and it is a 0, not a nil").eq(0)

            H.setNetStats(11, 22, 33, false)
            expect(select("#", H.env.GetNetStats()))
                .as("false is the only thing that drops the fourth return").eq(3)
        end)

        it("is reset by H.setup, so a warning-state reading cannot leak", function()
            H.setFramerate(7)
            H.setNetStats(900, 800, 640, false)
            H.setup()
            expect(H.env.GetFramerate()).as("framerate back to 60").eq(60)
            -- The arity matters as much as the values: a leaked netLatencyWorld = false
            -- would leave every later spec reading the three-return client.
            expect(select("#", H.env.GetNetStats()))
                .as("and back to the four-return shape").eq(4)
            local down, up, home, world = H.env.GetNetStats()
            expect(down).eq(0)
            expect(up).eq(0)
            expect(home).eq(0)
            expect(world).eq(0)
        end)

        it("is polled, not announced: a staged change reads back with no event fired", function()
            -- Every harness setter that announces does it through H.fireEvent (H.setTarget,
            -- H.setAuras, H.setCombat all route there), so recording that call states
            -- "silent" over the whole event vocabulary instead of against a guessed list of
            -- names. H.setTarget is the positive control: without it a recorder that never
            -- worked would make the silence assertion vacuous.
            local seen = {}
            local realFire = H.fireEvent
            H.fireEvent = function(event, ...)
                seen[#seen + 1] = event
                return realFire(event, ...)
            end
            H.setFramerate(9)
            H.setNetStats(1, 2, 3, 4)
            local afterStaging = #seen
            local framerate = H.env.GetFramerate()
            local _, _, home = H.env.GetNetStats()
            H.setTarget({ name = "Onyxia" })
            local afterControl = #seen
            -- Restored before anything can throw, so a failing assertion cannot leave the
            -- patch installed for the rest of the file.
            H.fireEvent = realFire

            expect(afterStaging).as("neither setter announced anything").eq(0)
            expect(framerate).as("yet the new framerate is there on the next read").eq(9)
            expect(home).as("and so is the new latency").eq(3)
            expect(afterControl)
                .as("the recorder does catch an announcement, so the silence above is real")
                .gt(0)
        end)
    end)

    ---------------------------------------------------------------------------
    -- What embedded third-party code needs from the simulated client.
    --
    -- SuuUI embeds LibStub, CallbackHandler-1.0, LibDataBroker-1.1 and LibDBIcon-1.0 under
    -- Libs/, listed at the top of the toc, so the harness loads them into its sandbox like
    -- any other addon file. Six additions to the client were needed before that load
    -- behaved, and each is pinned here rather than only covered by consequence through the
    -- specs of the code that uses it. The harness is load-bearing: a regression in one of
    -- these has to fail HERE, next to the rule it breaks, instead of surfacing as an
    -- unexplained failure in a component spec — or, worse, as a green suite exercising a
    -- branch the game never takes.
    ---------------------------------------------------------------------------

    describe("GameTooltip as a frame type", function()
        -- It was a plain Frame with the tooltip verbs bolted onto api.lua's singleton, so
        -- CreateFrame("GameTooltip", ...) raised ("does not simulate type GameTooltip") and
        -- a second instance was impossible. Embedded code creates its own tooltip at load
        -- (LibDBIcon makes LibDBIconTooltip), so the load died before the type existed.
        local function ownTooltip(name)
            return H.env.CreateFrame("GameTooltip", name, H.UIParent, "GameTooltipTemplate")
        end

        it("is a type CreateFrame accepts, and the shared global is one of them", function()
            local tip = ownTooltip("SpecOwnTooltip")
            expect(tip:GetObjectType())
                .as("a real frame type, not a Frame with verbs added").eq("GameTooltip")
            expect(tip:IsObjectType("GameTooltip")).eq(true)
            expect(H.env.GameTooltip:GetObjectType())
                .as("the shared tooltip is the same type as one an addon creates")
                .eq(tip:GetObjectType())
            expect(getmetatable(H.env.GameTooltip))
                .as("and the same implementation, so the two cannot drift apart")
                .eq(getmetatable(tip))
            expect(H.env.SpecOwnTooltip).as("a named frame registers its global").eq(tip)
            expect(H.GameTooltip)
                .as("H.GameTooltip is that shared global").eq(H.env.GameTooltip)
        end)

        it("is a frame, so it anchors and sizes like one", function()
            local tip = ownTooltip()
            tip:SetSize(H.token("sizeTooltipMaxWidth") or 200, H.lineHeight(H.token("fontSizeMd")))
            tip:SetPoint("TOPLEFT", H.UIParent, "TOPLEFT", 0, 0)
            expect(tip:GetHeight())
                .as("a GameTooltip inherits FrameMeta, so geometry works")
                .eq(H.lineHeight(H.token("fontSizeMd")))
            expect(H.box(tip)).notNil()
        end)

        it("round-trips its owner and anchor through the getters", function()
            local tip    = ownTooltip()
            local anchor = H.parent(100, 50)
            tip:SetOwner(anchor, H.env.ANCHOR_RIGHT)
            expect(tip:GetOwner()).eq(anchor)
            expect(tip:GetAnchorType())
                .as("the anchor constant the caller passed").eq(H.env.ANCHOR_RIGHT)
        end)

        it("accumulates a line per AddLine and reads each one back", function()
            local tip = ownTooltip()
            tip:SetOwner(H.UIParent, H.env.ANCHOR_CURSOR)
            expect(tip:NumLines()).as("a fresh owner starts with no content").eq(0)

            local texts = { "SuuUI", "Left-click to open settings", "Right-click for help" }
            for i, text in ipairs(texts) do
                tip:AddLine(text)
                expect(tip:NumLines()).as("one line per AddLine, in order").eq(i)
                expect((tip:GetLine(i))).eq(text)
            end
            expect(tip:GetLine(#texts + 1))
                .as("nothing past the last line").isNil()
        end)

        it("records both halves of an AddDoubleLine", function()
            local tip = ownTooltip()
            tip:SetOwner(H.UIParent, H.env.ANCHOR_CURSOR)
            tip:AddLine("SuuUI")
            tip:AddDoubleLine("Latency", "42 ms")
            expect(tip:NumLines()).as("a double line is still one line").eq(2)
            local left, right = tip:GetLine(2)
            expect(left).eq("Latency")
            expect(right).as("the right half is the second return").eq("42 ms")
            expect(select(2, tip:GetLine(1)))
                .as("a plain AddLine has no right half").isNil()
        end)

        it("replaces every line with SetText and empties with ClearLines", function()
            local tip = ownTooltip()
            tip:SetOwner(H.UIParent, H.env.ANCHOR_CURSOR)
            tip:AddLine("first")
            tip:AddLine("second")
            tip:SetText("only")
            expect(tip:NumLines()).as("SetText is a reset, not an append").eq(1)
            expect((tip:GetLine(1))).eq("only")
            tip:ClearLines()
            expect(tip:NumLines()).eq(0)
            expect(tip:GetLine(1)).isNil()
        end)

        it("resets the lines on SetOwner, so a second hover starts clean", function()
            -- The client's own contract, and the one a reader depends on: pointing a
            -- tooltip at a new owner discards what the previous owner put in it. Without
            -- it, a spec asserting a two-line tooltip passes after any earlier hover.
            local tip = ownTooltip()
            local a, b = H.parent(50, 20), H.parent(50, 20)
            tip:SetOwner(a, H.env.ANCHOR_CURSOR)
            tip:AddLine("about a")
            tip:AddLine("more about a")
            expect(tip:NumLines()).eq(2)
            tip:SetOwner(b, H.env.ANCHOR_CURSOR)
            expect(tip:NumLines()).as("the previous owner's lines are gone").eq(0)
            expect(tip:GetOwner()).eq(b)
        end)

        it("tracks its own shown state", function()
            local tip = ownTooltip()
            expect(tip:IsShown()).as("a tooltip starts hidden, unlike a plain frame").eq(false)
            tip:Show()
            expect(tip:IsShown()).eq(true)
            tip:Hide()
            expect(tip:IsShown()).eq(false)
        end)

        it("still records the aura setters into the shared tooltip state", function()
            -- Every aura spec reads H.getTooltipState() rather than the frame, so moving
            -- the verbs onto a type had to keep that recording — from ANY instance, which
            -- is the new part: state.tooltip is the last interaction, whichever tooltip
            -- it came from.
            local tip = ownTooltip()
            tip:SetOwner(H.UIParent, H.env.ANCHOR_CURSOR)

            tip:SetUnitBuff("player", 2)
            local ts = H.getTooltipState()
            expect(ts.owner).as("SetOwner recorded through an addon's own tooltip").eq(H.UIParent)
            expect(ts.aura.unit).eq("player")
            expect(ts.aura.index).eq(2)
            expect(ts.aura.filter).as("SetUnitBuff means HELPFUL").eq("HELPFUL")

            tip:SetUnitDebuff("target", 5)
            ts = H.getTooltipState()
            expect(ts.aura.index).eq(5)
            expect(ts.aura.filter).as("SetUnitDebuff means HARMFUL").eq("HARMFUL")

            tip:SetUnitAura("player", 1, "HARMFUL")
            expect(H.getTooltipState().aura.filter)
                .as("SetUnitAura takes the filter it is given").eq("HARMFUL")

            tip:ClearLines()
            expect(H.getTooltipState().aura)
                .as("ClearLines drops the aura it was describing").isNil()
        end)
    end)

    ---------------------------------------------------------------------------
    -- AnimationGroups.
    --
    -- SuuUI never creates one: it runs its own shared-OnUpdate animator by design. This
    -- exists because embedded code does — LibDBIcon builds a fade group for its minimap
    -- button at register time and the load dies without CreateAnimationGroup.
    --
    -- Deliberately a CONFIGURATION RECORDER: it stores what was asked for and tracks
    -- whether the group is playing, and it does NOT tick. H.tick drives SuuUI's animator,
    -- never this, so the only observable effect modelled is the client's SetToFinalAlpha
    -- contract on Finish.
    ---------------------------------------------------------------------------
    describe("AnimationGroup", function()
        it("is created by a frame, which owns it and lists it", function()
            local f = H.parent(50, 50)
            expect(#f:GetAnimationGroups()).as("a fresh frame has none").eq(0)
            local a = f:CreateAnimationGroup("SpecFadeGroup")
            local b = f:CreateAnimationGroup()
            expect(a:GetObjectType()).eq("AnimationGroup")
            expect(a:IsObjectType("AnimationGroup")).eq(true)
            expect(a:GetParent()).as("the frame that created it").eq(f)
            local groups = f:GetAnimationGroups()
            expect(#groups).eq(2)
            expect(groups[1]).as("creation order").eq(a)
            expect(groups[2]).eq(b)
        end)

        it("round-trips an Alpha animation's whole configuration", function()
            local f = H.parent(50, 50)
            local g = f:CreateAnimationGroup()
            local a = g:CreateAnimation("Alpha")
            expect(a:GetObjectType()).as("the kind it was asked for").eq("Alpha")

            -- A round-trip cares only that the getter answers what the setter was given;
            -- the durations come from theme tokens so the file carries no magic numbers.
            local dur, delay = H.token("animFast"), H.token("animFast") / 2
            a:SetDuration(dur)
            a:SetStartDelay(delay)
            a:SetOrder(2)
            a:SetFromAlpha(1)
            a:SetToAlpha(0)
            expect(a:GetDuration()).eq(dur)
            expect(a:GetStartDelay()).eq(delay)
            expect(a:GetOrder()).eq(2)
            expect(a:GetFromAlpha()).eq(1)
            expect(a:GetToAlpha()).eq(0)
        end)

        it("answers the client's defaults for an unconfigured animation", function()
            local g = H.parent(50, 50):CreateAnimationGroup()
            local a = g:CreateAnimation("Alpha")
            expect(a:GetDuration()).as("no duration set yet").eq(0)
            expect(a:GetStartDelay()).eq(0)
            expect(a:GetOrder()).as("the client's first order is 1, not 0").eq(1)
            expect(a:GetFromAlpha()).as("unset rather than assumed").isNil()
            expect(a:GetToAlpha()).isNil()
            expect(g:GetDuration()).as("and the group's span is zero").eq(0)
        end)

        it("defaults CreateAnimation to Alpha, which is what the client does", function()
            local g = H.parent(50, 50):CreateAnimationGroup()
            expect(g:CreateAnimation():GetObjectType()).eq("Alpha")
        end)

        it("tracks playing and done across Play, Pause and Stop", function()
            local g = H.parent(50, 50):CreateAnimationGroup()
            expect(g:IsPlaying()).as("a fresh group is idle").eq(false)
            expect(g:IsDone()).as("and therefore done").eq(true)
            g:Play()
            expect(g:IsPlaying()).eq(true)
            expect(g:IsDone()).as("done is the negation of playing here").eq(false)
            g:Pause()
            expect(g:IsPlaying()).as("a paused group is not playing").eq(false)
            g:Play()
            g:Stop()
            expect(g:IsPlaying()).eq(false)
            expect(g:IsDone()).eq(true)
        end)

        it("fires OnPlay, OnStop and OnFinished with the group as self", function()
            local g = H.parent(50, 50):CreateAnimationGroup()
            local order, selves = {}, {}
            for _, name in ipairs({ "OnPlay", "OnStop", "OnFinished" }) do
                g:SetScript(name, function(self)
                    order[#order + 1] = name
                    selves[name] = self
                end)
            end
            g:Play()
            g:Stop()
            g:Play()
            g:Finish()
            expect(order).deepEq({ "OnPlay", "OnStop", "OnPlay", "OnFinished" })
            expect(selves.OnFinished).as("the handler is called with the group").eq(g)
            expect(selves.OnPlay).eq(g)
            expect(g:GetScript("OnPlay")).as("and the script reads back").notNil()
        end)

        it("raises for a script name the client has no such thing as", function()
            local g = H.parent(50, 50):CreateAnimationGroup()
            expect(function() g:SetScript("OnFinish", function() end) end)
                .as("OnFinish is not OnFinished, and a typo must fail rather than never run")
                .throws("AnimationGroup has no script")
            expect(g:HasScript("OnFinished")).eq(true)
            expect(g:HasScript("OnFinish")).eq(false)
        end)

        it("spans the longest delay-plus-duration, not the longest duration", function()
            -- Three ways to compute this and only one is right: the longest duration
            -- (misses the delay), the sum (double-counts parallel animations), and the
            -- max of delay + duration. The numbers below tell all three apart — the
            -- animation with the SHORTER duration finishes last because of its delay.
            local fast = H.token("animFast")
            local g = H.parent(50, 50):CreateAnimationGroup()
            local first  = g:CreateAnimation("Alpha")
            first:SetDuration(fast)
            local second = g:CreateAnimation("Alpha")
            second:SetDuration(fast / 2)
            second:SetStartDelay(fast)

            expect(second:GetDuration()).as("the shorter animation").lt(first:GetDuration())
            expect(g:GetDuration())
                .as("the group ends when its last animation ends")
                .near(second:GetStartDelay() + second:GetDuration(), 1e-9)
            expect(g:GetDuration()).as("which is longer than any single duration").gt(fast)
            expect(g:GetDuration())
                .as("and shorter than the sum, which would double-count")
                .lt(first:GetDuration() + second:GetStartDelay() + second:GetDuration())
        end)

        it("leaves the end alpha on the parent when SetToFinalAlpha is on", function()
            -- The one effect this model reproduces, and the reason it exists: LibDBIcon
            -- fades its button out and expects the button to STAY faded.
            local f = H.parent(50, 50)
            local g = f:CreateAnimationGroup()
            g:SetToFinalAlpha(true)
            expect(g:IsSetToFinalAlpha()).eq(true)
            local a = g:CreateAnimation("Alpha")
            a:SetFromAlpha(f:GetAlpha())
            a:SetToAlpha(0)

            local before = f:GetAlpha()
            g:Play()
            g:Finish()
            expect(f:GetAlpha())
                .as("the target keeps the animation's end value").eq(a:GetToAlpha())
            expect(f:GetAlpha()).as("which is not where it started").neq(before)
            expect(g:IsPlaying()).as("Finish also ends the group").eq(false)
        end)

        it("leaves the parent's alpha untouched when SetToFinalAlpha is off", function()
            local f = H.parent(50, 50)
            local g = f:CreateAnimationGroup()
            g:SetToFinalAlpha(false)
            expect(g:IsSetToFinalAlpha()).eq(false)
            local a = g:CreateAnimation("Alpha")
            a:SetToAlpha(0)
            local before = f:GetAlpha()
            g:Play()
            g:Finish()
            expect(f:GetAlpha())
                .as("without the flag the client reverts, so nothing is written")
                .eq(before)
            expect(f:GetAlpha()).neq(a:GetToAlpha())
        end)

        it("is not driven by H.tick, which is the whole shape of this model", function()
            -- Stated as an assertion rather than only as a comment, because it is the
            -- property every reader of this model has to know: ticking the clock moves
            -- SuuUI's animator and does nothing at all here.
            local f = H.parent(50, 50)
            local g = f:CreateAnimationGroup()
            g:SetToFinalAlpha(true)
            local a = g:CreateAnimation("Alpha")
            a:SetDuration(H.token("animFast"))
            a:SetToAlpha(0)
            local before = f:GetAlpha()
            g:Play()
            H.runAnimations()
            expect(g:IsPlaying()).as("still playing: no clock advances this group").eq(true)
            expect(f:GetAlpha()).as("and the target never moved").eq(before)
        end)

        xit("interpolates an animation over its duration", function()
            -- NOT MODELLED, deliberately. There is no per-frame progress here: GetProgress
            -- answers 0 while playing and 1 once stopped, and nothing between Play and
            -- Finish ever changes the target. So no spec may read a mid-flight alpha,
            -- scale, offset or rotation from this model and believe it — a value read
            -- halfway through would be whatever the recorder happens to store, not what
            -- the client would draw.
            --
            -- Closing the gap means driving groups from H.tick, which would make the
            -- harness a second animator alongside SuuUI's own. Worth doing only if the
            -- addon itself ever adopts client animation groups; today nothing but embedded
            -- third-party code creates one, and that code only needs the configuration to
            -- round-trip and the final alpha to stick.
        end)
    end)

    describe("Lua stdlib globals the client predefines", function()
        -- WoW ships these as globals, so their absence was a harness inaccuracy rather
        -- than a choice: code written for the client may use any of them, and embedded
        -- libraries do (LibStub reaches for strmatch). The sandbox falls through to the
        -- real _G, where they do NOT exist, so each has to be stated in api.lua.
        it("does not inherit them from the real Lua global table", function()
            -- The premise. Without this line every assertion below could be passing on a
            -- fallthrough rather than on anything api.lua states.
            for _, name in ipairs({ "strmatch", "strfind", "strsub", "strlower", "strupper",
                                    "strlen", "strrep", "format", "gsub", "gmatch",
                                    "tinsert", "tremove", "sort" }) do
                expect(rawget(_G, name))
                    .as("_G." .. name .. " is a WoW invention, not a Lua one").isNil()
                expect(rawget(H.env, name))
                    .as("so the sandbox states " .. name .. " itself").notNil()
            end
        end)

        it("aliases the string library, matching its behaviour exactly", function()
            local s = "LibDBIcon-1.0"
            expect(H.env.strmatch(s, "^(%a+)")).eq(s:match("^(%a+)"))
            expect(H.env.strfind(s, "-", 1, true)).eq(s:find("-", 1, true))
            expect(H.env.strsub(s, 1, 3)).eq(s:sub(1, 3))
            expect(H.env.strlower(s)).eq(s:lower())
            expect(H.env.strupper(s)).eq(s:upper())
            expect(H.env.strlen(s)).eq(#s)
            expect(H.env.strrep("ab", 3)).eq(("ab"):rep(3))
            expect(H.env.format("%s v%d", s, 56)).eq(string.format("%s v%d", s, 56))
            expect((H.env.gsub(s, "%-", "_"))).eq((s:gsub("%-", "_")))
        end)

        it("aliases gmatch as an iterator, not just as a value", function()
            local parts = {}
            for word in H.env.gmatch("LibStub CallbackHandler LibDBIcon", "%a+") do
                parts[#parts + 1] = word
            end
            expect(#parts).as("one entry per match").eq(3)
            expect(parts[1]).eq("LibStub")
            expect(parts[#parts]).eq("LibDBIcon")
        end)

        it("aliases the table library, mutating the caller's table", function()
            local t = { "b" }
            H.env.tinsert(t, "c")
            H.env.tinsert(t, 1, "a")
            expect(t).as("appended and inserted in place").deepEq({ "a", "b", "c" })
            expect(H.env.tremove(t)).as("tremove answers what it removed").eq("c")
            expect(H.env.tremove(t, 1)).eq("a")
            expect(t).deepEq({ "b" })

            local unsorted = { 3, 1, 2 }
            local reference = { 3, 1, 2 }
            table.sort(reference)
            H.env.sort(unsorted)
            expect(unsorted).as("sort orders the same way table.sort does")
                .deepEq(reference)
        end)
    end)

    describe("which client this is (WOW_PROJECT_ID)", function()
        -- The highest-value of the six. Libraries branch on
        -- `WOW_PROJECT_ID == WOW_PROJECT_MAINLINE` to pick retail behaviour, and with BOTH
        -- names undefined that comparison is `nil == nil` — TRUE. So the suite exercised
        -- the retail path on every one of those branches while the game takes the Classic
        -- one, and a spec asserting Classic behaviour would have passed for the wrong
        -- reason. Defining only one of the two names would have been enough to fix the
        -- comparison, which is exactly why the assertion below has to name both.
        local function tocInterface()
            local f = assert(io.open(H.root .. "/SuuUI.toc", "r"))
            local body = f:read("*a")
            f:close()
            return tonumber(body:match("##%s*Interface:%s*(%d+)"))
        end

        it("agrees with the interface version the toc targets", function()
            local interface = tocInterface()
            expect(interface).as("the toc declares an interface version").notNil()
            -- The client's own encoding: the leading digits are the expansion, so 20504 is
            -- TBC. Derived from the toc rather than restated, so retargeting the addon
            -- fails here instead of leaving the harness on the wrong client.
            local expansion = math.floor(interface / 10000)
            local projectForExpansion = {
                [1]  = H.env.WOW_PROJECT_CLASSIC,
                [2]  = H.env.WOW_PROJECT_BURNING_CRUSADE_CLASSIC,
                [3]  = H.env.WOW_PROJECT_WRATH_CLASSIC,
                [4]  = H.env.WOW_PROJECT_CATACLYSM_CLASSIC,
                [11] = H.env.WOW_PROJECT_MAINLINE,
            }
            expect(H.env.WOW_PROJECT_ID)
                .as("the client the harness claims to be must match the toc's target")
                .eq(projectForExpansion[expansion])
            expect(H.env.WOW_PROJECT_ID)
                .as("SuuUI targets TBC Anniversary")
                .eq(H.env.WOW_PROJECT_BURNING_CRUSADE_CLASSIC)
        end)

        it("is explicitly NOT mainline, and both names are defined", function()
            expect(H.env.WOW_PROJECT_MAINLINE)
                .as("undefined here is what made nil == nil read as retail").notNil()
            expect(H.env.WOW_PROJECT_ID).notNil()
            expect(H.env.WOW_PROJECT_ID)
                .as("a library asking `is this retail?` must be told no")
                .neq(H.env.WOW_PROJECT_MAINLINE)
            expect(H.env.WOW_PROJECT_ID == H.env.WOW_PROJECT_MAINLINE)
                .as("the comparison libraries actually write").eq(false)
        end)

        it("gives every project constant a distinct id", function()
            local seen = {}
            for _, name in ipairs({ "WOW_PROJECT_MAINLINE", "WOW_PROJECT_CLASSIC",
                                    "WOW_PROJECT_BURNING_CRUSADE_CLASSIC",
                                    "WOW_PROJECT_WRATH_CLASSIC",
                                    "WOW_PROJECT_CATACLYSM_CLASSIC" }) do
                local id = H.env[name]
                expect(id).as(name .. " is defined").notNil()
                expect(seen[id]).as(name .. " does not collide with another project").isNil()
                seen[id] = name
            end
        end)
    end)

    describe("securecallfunction and math.atan2", function()
        it("calls through securecallfunction, passing arguments and returns back", function()
            -- Nothing in the harness is tainted, so this is a plain call — but third-party
            -- code calls it unconditionally, so it has to exist and it has to be
            -- transparent in both directions.
            local seen
            local a, b = H.env.securecallfunction(function(x, y)
                seen = { x, y }
                return y, x
            end, "first", "second")
            expect(seen).as("the arguments reached the function").deepEq({ "first", "second" })
            expect(a).as("and both returns came back, in order").eq("second")
            expect(b).eq("first")
        end)

        it("provides math.atan2, which Lua 5.3 removed", function()
            -- LibDBIcon's drag handler reads it to turn a cursor offset into an angle.
            --
            -- This one has to be asserted the awkward way. The Lua this suite runs on may
            -- ship atan2 natively -- a 5.4 built with the 5.1 compat flag does, and there
            -- it is literally the same function object as math.atan -- so simply reading
            -- math.atan2 proves nothing about the harness: the assertion passes with
            -- api.lua's fallback deleted. Deleting it and rebuilding the client is what
            -- exercises the fallback, and it is the only form of this spec that can fail.
            local native = math.atan2
            math.atan2 = nil
            H.setup()
            local restored = math.atan2
            expect(type(restored))
                .as("a client build without atan2 gets one from the harness").eq("function")
            expect(type(H.env.math.atan2))
                .as("and the sandbox sees the same math table").eq("function")
            -- Against the mathematical definition, so it holds for the native function and
            -- for the alias onto math.atan alike.
            expect(restored(1, 1)).as("a 45 degree offset").near(math.pi / 4, 1e-9)
            expect(restored(0, -1)).as("straight left is pi").near(math.pi, 1e-9)
            expect(restored(1, 0))
                .as("straight up is a quarter turn, with no divide by zero")
                .near(math.pi / 2, 1e-9)
            math.atan2 = native
        end)
    end)

    describe("a Button is mouse-enabled by default", function()
        -- The client's own default: only a plain Frame has to ask. Withholding it dropped
        -- every click from any button that relies on the default — and third-party code
        -- does, so its clicks were silently lost while the frame still reported as
        -- present, sized and shown, and every other assertion about it passed.
        it("reports a fresh Button as mouse-enabled and a fresh Frame as not", function()
            local btn   = H.env.CreateFrame("Button", nil, H.UIParent)
            local plain = H.env.CreateFrame("Frame", nil, H.UIParent)
            expect(btn:IsMouseEnabled())
                .as("a Button takes mouse input without EnableMouse").eq(true)
            expect(plain:IsMouseEnabled())
                .as("a plain Frame still has to opt in").eq(false)
        end)

        it("delivers a click to a Button that never called EnableMouse", function()
            local btn = H.env.CreateFrame("Button", nil, H.UIParent)
            local clicks = 0
            btn:SetScript("OnClick", function() clicks = clicks + 1 end)
            expect(H.click(btn)).as("input routing accepts it").eq(true)
            expect(clicks).as("and the handler ran").eq(1)
        end)

        it("does not deliver a click to a Frame that never called EnableMouse", function()
            local plain = H.env.CreateFrame("Frame", nil, H.UIParent)
            local fired = false
            plain:SetScript("OnMouseUp", function() fired = true end)
            expect(H.click(plain)).eq(false)
            expect(fired).as("the default differs by type, which is the point").eq(false)
        end)

        it("lets an explicit EnableMouse(false) beat the Button default", function()
            local btn = H.env.CreateFrame("Button", nil, H.UIParent)
            local clicks = 0
            btn:SetScript("OnClick", function() clicks = clicks + 1 end)
            btn:EnableMouse(false)
            expect(btn:IsMouseEnabled())
                .as("an explicit answer wins over the type's default").eq(false)
            expect(H.click(btn)).eq(false)
            expect(clicks).eq(0)
            btn:EnableMouse(true)
            expect(btn:IsMouseEnabled()).as("and back again").eq(true)
            expect(H.click(btn)).eq(true)
            expect(clicks).eq(1)
        end)
    end)

    describe("RegisterForClicks is case-insensitive", function()
        -- The client treats "anyUp", "AnyUp" and "ANYUP" as one registration, and
        -- third-party code freely uses the lower-cased spelling (LibDBIcon registers
        -- "anyUp"). Matching case-sensitively dropped every click from such a button while
        -- it still reported as present, sized and mouse-enabled — the same silent shape as
        -- the Button default above.
        local function clickRecorder(...)
            local btn = H.env.CreateFrame("Button", nil, H.UIParent)
            if select("#", ...) > 0 then btn:RegisterForClicks(...) end
            local log = {}
            btn:SetScript("OnClick", function(_, button, down)
                log[#log + 1] = { button = button, down = down }
            end)
            return btn, log
        end

        it("takes the lower-cased spelling for both mouse buttons", function()
            local btn, log = clickRecorder("anyUp")
            H.click(btn, "LeftButton")
            H.click(btn, "RightButton")
            expect(#log).as("anyUp means any button, whatever its case").eq(2)
            expect(log[1].button).eq("LeftButton")
            expect(log[2].button).eq("RightButton")
            expect(log[2].down).as("and Up means the release phase").eq(false)
        end)

        it("takes the shouted spelling too", function()
            local btn, log = clickRecorder("ANYUP")
            H.click(btn, "LeftButton")
            H.click(btn, "RightButton")
            expect(#log).eq(2)
        end)

        it("agrees with the canonical spelling, click for click", function()
            -- The rule stated as an equivalence rather than as a count per casing: every
            -- spelling has to behave identically to the one the harness always understood,
            -- so the expectation comes from a canonical button given the same input rather
            -- than from a number written here.
            local buttons = { "LeftButton", "MiddleButton", "RightButton" }
            for _, spelling in ipairs({ "anyUp", "ANYUP", "anyup", "AnYuP" }) do
                local canonical, canonicalLog = clickRecorder("AnyUp")
                local variant,   variantLog   = clickRecorder(spelling)
                for _, button in ipairs(buttons) do
                    H.click(canonical, button)
                    H.click(variant, button)
                end
                expect(#canonicalLog)
                    .as("the canonical button is the control, and it does deliver")
                    .eq(#buttons)
                expect(variantLog).as(spelling .. " delivers exactly what AnyUp delivers")
                    .deepEq(canonicalLog)
            end
        end)

        it("still delivers left-up only when nothing is registered", function()
            local btn, log = clickRecorder()
            H.click(btn, "RightButton")
            expect(#log).as("a right click needs registering for").eq(0)
            H.click(btn, "LeftButton")
            expect(#log).as("left-up is the default").eq(1)
            expect(log[1].down).as("the release phase, not the press").eq(false)
        end)

        it("keeps the legacy button-name-only spelling meaning the up phase", function()
            for _, spelling in ipairs({ "RightButton", "rightbutton" }) do
                local btn, log = clickRecorder(spelling)
                H.click(btn, "LeftButton")
                expect(#log).as(spelling .. " does not register the left button").eq(0)
                H.click(btn, "RightButton")
                expect(#log).as(spelling .. " names a button and means Up").eq(1)
                expect(log[1].down).as("so the press does not fire, the release does").eq(false)
            end
        end)

        it("does not fire the down phase for an Up registration, in any case", function()
            -- The half a case-insensitive comparison could get wrong in the other
            -- direction: lower-casing both sides must not make "anyUp" match the press.
            local btn, log = clickRecorder("anyUp")
            local atDown
            btn:SetScript("OnMouseDown", function() atDown = #log end)
            H.click(btn, "LeftButton")
            expect(atDown).as("nothing had fired by the time the button went down").eq(0)
            expect(#log).as("and exactly one click by the time it came up").eq(1)
        end)
    end)

    describe("stored Button and strata state third-party code writes", function()
        -- Stored, not drawn: none of these change a rect, and the harness models geometry.
        -- They exist because embedded code calls them unconditionally, so a missing one is
        -- a load failure. Readable rather than write-only, because a write-only flag
        -- cannot be asserted — which is exactly how SetClipsChildren once hid a bug.
        it("round-trips every Button texture slot", function()
            local btn = H.env.CreateFrame("Button", nil, H.UIParent)
            local slots = {
                { set = "SetNormalTexture",    get = "GetNormalTexture" },
                { set = "SetHighlightTexture", get = "GetHighlightTexture" },
                { set = "SetPushedTexture",    get = "GetPushedTexture" },
                { set = "SetDisabledTexture",  get = "GetDisabledTexture" },
            }
            for _, slot in ipairs(slots) do
                expect(btn[slot.get](btn)).as(slot.get .. " starts empty").isNil()
                local path = "Interface\\AddOns\\SuuUI\\Media\\" .. slot.set
                btn[slot.set](btn, path)
                expect(btn[slot.get](btn)).as(slot.get .. " answers what was set").eq(path)
            end
            -- Each slot is its own store: one setter must not overwrite another, which a
            -- shared field would do while every single-slot assertion still passed.
            for _, slot in ipairs(slots) do
                expect(btn[slot.get](btn))
                    .as(slot.get .. " survived the other three")
                    .eq("Interface\\AddOns\\SuuUI\\Media\\" .. slot.set)
            end
        end)

        it("tracks the highlight lock a drag gesture holds", function()
            local btn = H.env.CreateFrame("Button", nil, H.UIParent)
            expect(btn:IsHighlightLocked()).eq(false)
            btn:LockHighlight()
            expect(btn:IsHighlightLocked()).as("held for the duration of a drag").eq(true)
            btn:UnlockHighlight()
            expect(btn:IsHighlightLocked()).eq(false)
        end)

        it("round-trips SetMotionScriptsWhileDisabled", function()
            local btn = H.env.CreateFrame("Button", nil, H.UIParent)
            btn:SetMotionScriptsWhileDisabled(true)
            expect(btn._motionWhileDisabled).eq(true)
            btn:SetMotionScriptsWhileDisabled(false)
            expect(btn._motionWhileDisabled).as("false, not nil").eq(false)
        end)

        it("round-trips the fixed strata and level flags independently", function()
            local f = H.parent(20, 20)
            expect(f:HasFixedFrameStrata()).eq(false)
            expect(f:HasFixedFrameLevel()).eq(false)
            f:SetFixedFrameStrata(true)
            expect(f:HasFixedFrameStrata()).eq(true)
            expect(f:HasFixedFrameLevel())
                .as("the two flags are separate stores").eq(false)
            f:SetFixedFrameLevel(true)
            f:SetFixedFrameStrata(false)
            expect(f:HasFixedFrameStrata()).eq(false)
            expect(f:HasFixedFrameLevel()).as("and clearing one leaves the other").eq(true)
        end)
    end)

    -- Whether a region inside a protected frame is itself protected. It is NOT, and the
    -- distinction decides whether a component may update a readout during a fight.
    describe("regions inside a protected frame", function()
        before_each(function() H.setup() end)

        local function secureButton()
            local b = H.env.CreateFrame("Button", nil, H.env.UIParent,
                "SecureActionButtonTemplate")
            b:SetSize(32, 32)
            b:SetPoint("TOPLEFT", H.env.UIParent, "TOPLEFT", 0, 0)
            return b
        end

        it("lets a font string be hidden mid-combat", function()
            -- Blizzard's own action buttons rely on this: a potion's stack count appears and
            -- disappears as it is used, which is a font string inside a protected button being
            -- shown and hidden during a fight.
            local b = secureButton()
            local fs = b:CreateFontString(nil, "OVERLAY")
            H.setCombat(true)
            H.resetBlockedActions()
            fs:Hide()
            expect(#H.getBlockedActions()).as("a region carries no protection").eq(0)
            expect(fs:IsShown()).falsy()
        end)

        it("lets a texture be resized and repositioned mid-combat", function()
            local b = secureButton()
            local tex = b:CreateTexture(nil, "ARTWORK")
            H.setCombat(true)
            H.resetBlockedActions()
            tex:SetSize(8, 8)
            tex:SetPoint("TOPLEFT", b, "TOPLEFT", 0, 0)
            expect(#H.getBlockedActions()).eq(0)
        end)

        it("still refuses a FRAME inside a protected frame", function()
            -- The narrow half of the same rule, and the one that matters: this is what caught
            -- ActionButton hiding its icon frame on every action pickup.
            local b = secureButton()
            local child = H.env.CreateFrame("Frame", nil, b)
            H.setCombat(true)
            H.resetBlockedActions()
            child:Hide()
            expect(#H.getBlockedActions()).as("a frame is protected by its ancestor").eq(1)
            expect(H.getBlockedActions()[1].action).eq("Hide")
        end)

        it("still refuses geometry on the protected frame itself", function()
            local b = secureButton()
            H.setCombat(true)
            H.resetBlockedActions()
            b:SetSize(48, 48)
            expect(#H.getBlockedActions()).eq(1)
        end)
    end)

    -- Action slots. The shape here was measured in game, not assumed: 12 buttons across 6
    -- pages, and GetActionInfo answering ("spell", 143, "spell") for slot 1.
    describe("action slots", function()
        before_each(function() H.setup() end)

        -- H.eventSpy watches SuuUI's own EventBus, which does not carry CLIENT events -- the
        -- same reason the combat lockdown block above cannot use it for PLAYER_REGEN_*. A
        -- client event is observed the way the addon observes one: a frame with a handler.
        local function clientEventSpy(event)
            local rec = { count = 0, args = {} }
            local f = H.env.CreateFrame("Frame")
            f:RegisterEvent(event)
            f:SetScript("OnEvent", function(_, _, ...)
                rec.count = rec.count + 1
                rec.args[rec.count] = { ... }
            end)
            return rec
        end

        describe("an empty slot", function()
            it("answers no to HasAction and nil to every describing call", function()
                expect(H.env.HasAction(1)).falsy()
                expect(H.env.GetActionInfo(1)).isNil()
                expect(H.env.GetActionTexture(1)).isNil()
                expect(H.env.GetActionText(1)).isNil()
            end)

            it("answers 0, 0, 0 to GetActionCooldown rather than nil", function()
                -- The client does, and a Cooldown frame handed nil errors instead of
                -- clearing -- so nil here would fail in game and pass in a spec.
                local start, duration, enable = H.env.GetActionCooldown(1)
                expect(start).eq(0)
                expect(duration).eq(0)
                expect(enable).eq(0)
            end)

            it("is not usable, and is not short of mana either", function()
                local usable, noMana = H.env.IsUsableAction(1)
                expect(usable).falsy()
                expect(noMana).as("an empty slot is not a mana problem").falsy()
            end)

            it("counts 0, and is neither current nor auto-repeating", function()
                expect(H.env.GetActionCount(1)).eq(0)
                expect(H.env.IsCurrentAction(1)).falsy()
                expect(H.env.IsAutoRepeatAction(1)).falsy()
            end)
        end)

        describe("a staged slot", function()
            it("reports the type, id and subType it was given", function()
                H.setAction(1, { type = "spell", id = 143, subType = "spell" })
                expect(H.env.HasAction(1)).truthy()
                local kind, id, sub = H.env.GetActionInfo(1)
                expect(kind).eq("spell")
                expect(id).eq(143)
                expect(sub).eq("spell")
            end)

            it("fills unstated fields from the defaults", function()
                H.setAction(2, { id = 99 })
                local kind, id = H.env.GetActionInfo(2)
                expect(kind).as("defaulted to a spell").eq("spell")
                expect(id).eq(99)
                expect(H.env.GetActionTexture(2)).notNil()
            end)

            it("has no macro text unless it is a macro", function()
                H.setAction(3, { type = "spell", id = 5 })
                expect(H.env.GetActionText(3)).as("a spell carries no name").isNil()
                H.setAction(4, { type = "macro", id = 7, text = "Pull" })
                expect(H.env.GetActionText(4)).eq("Pull")
            end)

            it("distinguishes out of range from range being no question at all", function()
                -- The nil is load-bearing. A self buff has no range, and a button must not
                -- paint that the same as a target standing too far away.
                H.setAction(5, { id = 1 })
                expect(H.env.IsActionInRange(5)).as("unstated means not a question").isNil()
                H.setAction(6, { id = 2, inRange = false })
                expect(H.env.IsActionInRange(6)).as("staged false is out of range").eq(false)
                H.setAction(7, { id = 3, inRange = true })
                expect(H.env.IsActionInRange(7)).eq(true)
            end)

            it("reports not-enough-mana separately from not-usable", function()
                H.setAction(8, { id = 4, usable = false, notEnoughMana = true })
                local usable, noMana = H.env.IsUsableAction(8)
                expect(usable).falsy()
                expect(noMana).truthy()
            end)

            it("carries a cooldown, with enable defaulting to 1", function()
                H.setAction(9, { id = 5, cooldownStart = 100, cooldownDuration = 30 })
                local start, duration, enable = H.env.GetActionCooldown(9)
                expect(start).eq(100)
                expect(duration).eq(30)
                expect(enable).as("a cooldown is enabled unless said otherwise").eq(1)
            end)
        end)

        describe("H.setAction", function()
            it("fires ACTIONBAR_SLOT_CHANGED with the slot", function()
                local seen
                local f = H.env.CreateFrame("Frame")
                f:RegisterEvent("ACTIONBAR_SLOT_CHANGED")
                f:SetScript("OnEvent", function(_, _, slot) seen = slot end)
                H.setAction(12, { id = 8 })
                expect(seen).as("the slot came through as the payload").eq(12)
            end)

            it("stays quiet with the silent option", function()
                local spy = clientEventSpy("ACTIONBAR_SLOT_CHANGED")
                H.setAction(12, { id = 8 }, { silent = true })
                expect(spy.count).eq(0)
            end)

            it("merges into what the slot already held", function()
                -- So a spec can put a spell in a slot and then start its cooldown without
                -- restating the spell.
                H.setAction(1, { type = "macro", id = 4, text = "Pull" }, { silent = true })
                H.setAction(1, { cooldownDuration = 10 }, { silent = true })
                expect(H.env.GetActionText(1)).as("kept the macro name").eq("Pull")
                local _, duration = H.env.GetActionCooldown(1)
                expect(duration).eq(10)
            end)

            it("rejects an unknown field rather than ignoring it", function()
                expect(function() H.setAction(1, { bogusField = 1 }) end).throws()
            end)

            it("clearAction empties the slot and announces it", function()
                H.setAction(1, { id = 4 }, { silent = true })
                local spy = clientEventSpy("ACTIONBAR_SLOT_CHANGED")
                H.clearAction(1)
                expect(H.env.HasAction(1)).falsy()
                expect(spy.count).eq(1)
            end)
        end)

        describe("drag and drop", function()
            it("takes the slot's contents onto the cursor, leaving it empty", function()
                H.setAction(1, { type = "spell", id = 143 }, { silent = true })
                H.env.PickupAction(1)
                expect(H.env.HasAction(1)).as("the slot emptied").falsy()
                expect(H.getPickedUpAction()).notNil()
                expect(H.getPickedUpAction().id).eq(143)
            end)

            it("SWAPS when dropped onto an occupied slot, rather than overwriting", function()
                -- The cursor carries contents, not a reference, so PlaceAction hands back
                -- whatever was already there. A button that assumed overwrite would lose an
                -- action every time a player rearranged their bar.
                H.setAction(1, { type = "spell", id = 143 }, { silent = true })
                H.setAction(2, { type = "macro", id = 7 }, { silent = true })
                H.env.PickupAction(1)
                H.env.PlaceAction(2)
                local _, id = H.env.GetActionInfo(2)
                expect(id).as("slot 2 took the spell").eq(143)
                expect(H.getPickedUpAction().id).as("the macro came back to the cursor").eq(7)
            end)

            it("announces both slots it touched", function()
                H.setAction(1, { id = 1 }, { silent = true })
                local spy = clientEventSpy("ACTIONBAR_SLOT_CHANGED")
                H.env.PickupAction(1)
                H.env.PlaceAction(2)
                expect(spy.count).eq(2)
            end)
        end)

        describe("paging", function()
            it("starts on page 1 and reports the shape measured in game", function()
                expect(H.env.GetActionBarPage()).eq(1)
                expect(H.env.NUM_ACTIONBAR_BUTTONS).eq(12)
                expect(H.env.NUM_ACTIONBAR_PAGES).eq(6)
            end)

            it("moves page and fires ACTIONBAR_PAGE_CHANGED", function()
                local spy = clientEventSpy("ACTIONBAR_PAGE_CHANGED")
                H.setActionBarPage(3)
                expect(H.env.GetActionBarPage()).eq(3)
                expect(spy.count).eq(1)
            end)
        end)

        describe("bindings", function()
            it("answers GetBindingKey only for a command that was bound", function()
                expect(H.env.GetBindingKey("ACTIONBUTTON1")).isNil()
                H.setBinding("ACTIONBUTTON1", "1")
                expect(H.env.GetBindingKey("ACTIONBUTTON1")).eq("1")
            end)

            it("records override bindings in call order", function()
                H.env.SetOverrideBindingClick(H.env.UIParent, true, "F1", "SuuUIButton1")
                H.env.SetOverrideBindingClick(H.env.UIParent, false, "F2", "SuuUIButton2")
                local list = H.getOverrideBindings()
                expect(#list).eq(2)
                expect(list[1].key).eq("F1")
                expect(list[1].isPriority).truthy()
                expect(list[2].button).eq("SuuUIButton2")
            end)

            it("clears only the bindings of the owner named", function()
                local other = H.env.CreateFrame("Frame")
                H.env.SetOverrideBindingClick(H.env.UIParent, true, "F1", "A")
                H.env.SetOverrideBindingClick(other, true, "F2", "B")
                H.env.ClearOverrideBindings(H.env.UIParent)
                local list = H.getOverrideBindings()
                expect(#list).eq(1)
                expect(list[1].key).eq("F2")
            end)

            it("reports the bars unlocked by default, as a string", function()
                -- A CVar-backed plain global, so "0"/"1" rather than a boolean. A component
                -- testing it for truthiness would find "0" truthy in Lua.
                expect(H.env.LOCK_ACTIONBAR).eq("0")
                H.setActionBarLocked(true)
                expect(H.env.LOCK_ACTIONBAR).eq("1")
            end)
        end)

        describe("secure state drivers", function()
            it("records the conditional string without evaluating it", function()
                -- Deliberately a recorder. Resolving a macro conditional here would mean the
                -- harness guessing what the client decides, and a spec would then be
                -- asserting against the guess.
                local header = H.env.CreateFrame("Frame", nil, H.env.UIParent,
                    "SecureHandlerStateTemplate")
                H.env.RegisterStateDriver(header, "page", "[bonusbar:1] 7; [shapeshift] 2; 1")
                expect(H.getStateDriver(header, "page"))
                    .eq("[bonusbar:1] 7; [shapeshift] 2; 1")
            end)

            it("keeps drivers apart per frame and per state name", function()
                local a = H.env.CreateFrame("Frame", nil, H.env.UIParent, "SecureHandlerStateTemplate")
                local b = H.env.CreateFrame("Frame", nil, H.env.UIParent, "SecureHandlerStateTemplate")
                H.env.RegisterStateDriver(a, "page", "1")
                H.env.RegisterStateDriver(b, "page", "2")
                H.env.RegisterStateDriver(a, "visibility", "[combat] hide; show")
                expect(H.getStateDriver(a, "page")).eq("1")
                expect(H.getStateDriver(b, "page")).eq("2")
                expect(H.getStateDriver(a, "visibility")).eq("[combat] hide; show")
            end)

            it("forgets one on unregister, leaving the others", function()
                local h = H.env.CreateFrame("Frame", nil, H.env.UIParent, "SecureHandlerStateTemplate")
                H.env.RegisterStateDriver(h, "page", "1")
                H.env.RegisterStateDriver(h, "visibility", "show")
                H.env.UnregisterStateDriver(h, "page")
                expect(H.getStateDriver(h, "page")).isNil()
                expect(H.getStateDriver(h, "visibility")).eq("show")
            end)

            it("answers nil for a frame that never registered one", function()
                local plain = H.env.CreateFrame("Frame")
                expect(H.getStateDriver(plain, "page")).isNil()
            end)
        end)

        describe("the client's own handler for an action button", function()
            local function actionButton(slot)
                local b = H.env.CreateFrame("Button", nil, H.env.UIParent,
                    "SecureActionButtonTemplate")
                b:SetSize(32, 32)
                b:SetPoint("TOPLEFT", H.env.UIParent, "TOPLEFT", 0, 0)
                b:SetAttribute("type", "action")
                b:SetAttribute("action", slot)
                return b
            end

            it("uses the slot named by the action attribute", function()
                local b = actionButton(7)
                H.click(b)
                local used = H.getUsedAction()
                expect(used).as("the client was asked to use a slot").notNil()
                expect(used.slot).eq(7)
                expect(used.button).eq("LeftButton")
            end)

            it("is protected, being built from a Secure template", function()
                local b = actionButton(1)
                expect(b:IsProtected()).truthy()
            end)

            it("gets no right click at all until the button registers for one", function()
                -- Found by this spec failing. A button receives LeftButtonUp by default and
                -- NOTHING else, so an ActionButton that wants right-click must say so --
                -- otherwise every secondary action silently does nothing, in game and here.
                local b = actionButton(1)
                b:SetAttribute("action2", 55)
                H.click(b, "RightButton")
                expect(H.getUsedAction()).as("no handler ran").isNil()
            end)

            it("honours a per-button action attribute once registered", function()
                local b = actionButton(1)
                b:RegisterForClicks("AnyUp")
                b:SetAttribute("action2", 55)
                H.click(b, "RightButton")
                expect(H.getUsedAction().slot).as("right click took action2").eq(55)
            end)

            it("normalises a string slot, as a secure snippet would write it", function()
                local b = actionButton("13")
                H.click(b)
                expect(H.getUsedAction().slot).eq(13)
            end)

            it("fires PreClick and PostClick around the action", function()
                local order = {}
                local b = actionButton(1)
                b:SetScript("PreClick", function() order[#order + 1] = "pre" end)
                b:SetScript("PostClick", function() order[#order + 1] = "post" end)
                H.click(b)
                expect(order).deepEq({ "pre", "post" })
            end)

            it("does nothing for a type it does not know", function()
                local b = actionButton(1)
                b:SetAttribute("type", "somethingelse")
                H.click(b)
                expect(H.getUsedAction()).isNil()
            end)

            it("resetUsedAction lets one spec assert a second click", function()
                local b = actionButton(3)
                H.click(b)
                H.resetUsedAction()
                expect(H.getUsedAction()).isNil()
                H.click(b)
                expect(H.getUsedAction().slot).eq(3)
            end)
        end)

        describe("reset", function()
            it("clears every action store, so nothing leaks into the next spec", function()
                -- A leaked slot would let "the button drew an icon" pass before a spec staged
                -- anything, and a leaked cursor would make the next PlaceAction appear to work.
                H.setAction(1, { id = 4 }, { silent = true })
                H.setAction(2, { id = 5 }, { silent = true })
                H.setActionBarPage(4, { silent = true })
                H.setBinding("ACTIONBUTTON1", "1")
                H.setActionBarLocked(true)
                -- Slot 2, deliberately NOT slot 1: PickupAction empties the slot it takes
                -- from, so picking up slot 1 would leave the HasAction check below passing
                -- because this test emptied it rather than because reset did. That exact
                -- vacuity was caught by mutation testing, not by review.
                H.env.PickupAction(2)
                H.env.SetOverrideBindingClick(H.env.UIParent, true, "F1", "A")
                local header = H.env.CreateFrame("Frame", nil, H.env.UIParent, "SecureHandlerStateTemplate")
                H.env.RegisterStateDriver(header, "page", "1")
                local b = H.env.CreateFrame("Button", nil, H.env.UIParent, "SecureActionButtonTemplate")
                b:SetSize(32, 32)
                b:SetPoint("TOPLEFT", H.env.UIParent, "TOPLEFT", 0, 0)
                b:SetAttribute("type", "action")
                b:SetAttribute("action", 9)
                H.click(b)

                -- Every store below is genuinely dirty at this point.
                expect(H.env.HasAction(1)).as("staged before the reload").truthy()
                expect(H.getPickedUpAction()).as("cursor loaded before the reload").notNil()
                expect(H.getUsedAction()).as("a click happened before the reload").notNil()
                expect(H.getOverrideBindings()).as("a binding was installed").len(1)
                expect(H.getStateDriver(header, "page")).notNil()

                H.setup()

                expect(H.env.HasAction(1)).falsy()
                expect(H.env.GetActionBarPage()).eq(1)
                expect(H.env.GetBindingKey("ACTIONBUTTON1")).isNil()
                expect(H.env.LOCK_ACTIONBAR).eq("0")
                expect(H.getPickedUpAction()).isNil()
                expect(H.getOverrideBindings()).len(0)
                expect(H.getUsedAction()).isNil()
                expect(H.getStateDriver(header, "page")).as("frame-keyed store dropped").isNil()
            end)

            it("clears the stance and pet stores too", function()
                -- Same reasoning as the action stores, with a sharper failure mode: these two
                -- decide whether a bar EXISTS AT ALL, so a leak would render a stance bar for a
                -- mage and a pet bar for a warrior in the next spec file.
                H.setStanceForm(1, { spellID = 2458 }, { silent = true })
                H.setPetAction(1, { name = "Attack" }, { silent = true })
                H.setPetActionBar(true, { silent = true })
                H.setBonusBarOffset(2, { silent = true })
                H.env.CastShapeshiftForm(1)
                H.env.TogglePetAutocast(1)

                expect(H.env.GetNumShapeshiftForms()).as("staged before the reload").eq(1)
                expect(H.env.GetPetActionInfo(1)).notNil()
                expect(H.env.PetHasActionBar()).truthy()
                expect(H.getCastStance()).notNil()
                expect(H.getPetAutocastToggles()).len(1)

                H.setup()

                expect(H.env.GetNumShapeshiftForms()).eq(0)
                expect(H.env.GetShapeshiftForm()).eq(0)
                expect(H.env.GetPetActionInfo(1)).isNil()
                expect(H.env.PetHasActionBar()).falsy()
                expect(H.env.GetBonusBarOffset()).eq(0)
                expect(H.getCastStance()).isNil()
                expect(H.getPetAutocastToggles()).len(0)
            end)
        end)

        describe("shapeshift forms", function()
            it("reports no forms for a class that has none", function()
                -- The signal the whole stance bar hides on. There is no class check anywhere --
                -- a mage is simply a count of zero.
                expect(H.env.GetNumShapeshiftForms()).eq(0)
                expect(H.env.GetShapeshiftForm()).eq(0)
                expect(H.env.GetShapeshiftFormInfo(1)).isNil()
            end)

            it("counts staged forms and returns their info in the client's order", function()
                H.setStanceForm(1, { spellID = 2457, texture = "battle" })
                H.setStanceForm(2, { spellID = 2458, texture = "berserker" })
                expect(H.env.GetNumShapeshiftForms()).eq(2)
                -- texture, isActive, isCastable, spellID -- the order ElvUI destructures.
                local texture, isActive, isCastable, spellID = H.env.GetShapeshiftFormInfo(2)
                expect(texture).eq("berserker")
                expect(isActive).falsy()
                expect(isCastable).as("castable unless staged otherwise").truthy()
                expect(spellID).eq(2458)
            end)

            it("derives the active form rather than storing it separately", function()
                -- One source of truth: the client cannot report form 2 active while form 2's own
                -- info disagrees, so the harness must not be able to either.
                H.setStanceForm(1, { spellID = 1 })
                H.setStanceForm(2, { spellID = 2, isActive = true })
                expect(H.env.GetShapeshiftForm()).eq(2)
                local _, isActive = H.env.GetShapeshiftFormInfo(2)
                expect(isActive).truthy()
            end)

            it("makes a newly active form deactivate the others", function()
                H.setStanceForm(1, { isActive = true })
                H.setStanceForm(2, {})
                expect(H.env.GetShapeshiftForm()).eq(1)
                H.setStanceForm(2, { isActive = true })
                expect(H.env.GetShapeshiftForm()).as("only one form at a time").eq(2)
                local _, firstActive = H.env.GetShapeshiftFormInfo(1)
                expect(firstActive).falsy()
            end)

            it("REFUSES a gap, because the client cannot express one", function()
                -- GetNumShapeshiftForms answers a COUNT and consumers loop 1..count, so form 3
                -- with no form 2 would be unreachable while still being staged.
                expect(function() H.setStanceForm(3, { spellID = 9 }) end).throws("contiguous")
            end)

            it("fires the PLURAL event when the form set changes and the SINGULAR when it does not",
                function()
                    -- The distinction is load-bearing: a bar listening only to the plural rebuilds
                    -- its buttons but never restyles them, and one listening only to the singular
                    -- never grows a button.
                    local forms, form = 0, 0
                    local f = H.env.CreateFrame("Frame", nil, H.env.UIParent)
                    f:RegisterEvent("UPDATE_SHAPESHIFT_FORMS")
                    f:RegisterEvent("UPDATE_SHAPESHIFT_FORM")
                    f:SetScript("OnEvent", function(_, e)
                        if e == "UPDATE_SHAPESHIFT_FORMS" then forms = forms + 1 else form = form + 1 end
                    end)

                    H.setStanceForm(1, { spellID = 1 })
                    expect(forms).as("creating a form changed the set").eq(1)
                    expect(form).eq(0)

                    H.setStanceForm(1, { isActive = true })
                    expect(forms).as("updating one did not change the set").eq(1)
                    expect(form).eq(1)

                    H.popStanceForm()
                    expect(forms).as("removing shrank the set").eq(2)
                    expect(H.env.GetNumShapeshiftForms())
                        .as("and the count actually dropped, not just the event").eq(0)
                end)

            it("returns a numeric cooldown active flag, not a boolean", function()
                -- ElvUI tests `active and active ~= 0`, so answering false here would let a
                -- consumer that only checks truthiness pass while the real client, sending 0,
                -- made it fail.
                local _, _, active = H.env.GetShapeshiftFormCooldown(1)
                expect(active).eq(0)
                H.setStanceForm(1, { cooldownStart = 100, cooldownDuration = 30, cooldownActive = 1 })
                local start, duration, act = H.env.GetShapeshiftFormCooldown(1)
                expect(start).eq(100)
                expect(duration).eq(30)
                expect(act).eq(1)
            end)

            it("records a cast rather than enacting it", function()
                -- Enacting would mean the harness deciding what changing form does to every other
                -- reading; a spec asserts the cast and stages the consequence it cares about.
                H.setStanceForm(1, { spellID = 2458 })
                H.env.CastShapeshiftForm(1)
                expect(H.getCastStance()).eq(1)
                expect(H.env.GetShapeshiftForm()).as("form did not change itself").eq(0)
            end)
        end)

        describe("pet actions", function()
            it("answers nil for an unstaged slot and false for no pet bar", function()
                expect(H.env.GetPetActionInfo(1)).isNil()
                expect(H.env.PetHasActionBar()).falsy()
                expect(H.env.GetPetActionSlotUsable(1)).falsy()
            end)

            it("returns all seven values in the client's order", function()
                H.setPetAction(1, {
                    name = "Attack", texture = "tex", isActive = true,
                    autoCastAllowed = true, autoCastEnabled = true, spellID = 6991,
                })
                local name, texture, isToken, isActive, allowed, enabled, spellID =
                    H.env.GetPetActionInfo(1)
                expect(name).eq("Attack")
                expect(texture).eq("tex")
                expect(isToken).as("not a token unless staged").falsy()
                expect(isActive).truthy()
                expect(allowed).truthy()
                expect(enabled).truthy()
                expect(spellID).eq(6991)
            end)

            it("treats a staged slot as usable unless told otherwise", function()
                -- The default matters: a bar that greys every button because the harness answered
                -- "not usable" for a perfectly good slot looks like a tint bug, not a data bug.
                H.setPetAction(1, { name = "Claw" })
                expect(H.env.GetPetActionSlotUsable(1)).as("usable by default").truthy()
                H.setPetAction(1, { usable = false })
                expect(H.env.GetPetActionSlotUsable(1)).falsy()
            end)

            it("does NOT resolve a token, because resolving it is the consumer's job", function()
                -- The trap: with isToken true, name and texture are the NAMES OF GLOBALS. A
                -- harness that quietly resolved them would let a consumer that forgot the lookup
                -- pass here and then draw a blank icon in game.
                H.env.PET_ACTION_FOLLOW_NAME = "Follow"
                H.setPetAction(1, { name = "PET_ACTION_FOLLOW_NAME", isToken = true })
                local name, _, isToken = H.env.GetPetActionInfo(1)
                expect(isToken).truthy()
                expect(name).as("handed back unresolved").eq("PET_ACTION_FOLLOW_NAME")
                expect(H.env[name]).as("the consumer resolves it").eq("Follow")
            end)

            it("keeps the pet's existence separate from its bar being usable", function()
                -- Two mechanisms with different outcomes: a present pet with an unusable bar greys
                -- its icons, an absent pet hides the bar. Collapsing them gets one case wrong.
                H.setUnit("pet", { exists = true })
                expect(H.env.UnitExists("pet")).truthy()
                expect(H.env.PetHasActionBar()).as("present but bar unusable").falsy()
                H.setPetActionBar(true)
                expect(H.env.PetHasActionBar()).truthy()
            end)

            it("toggles autocast and announces it, since the consequence is unambiguous", function()
                H.setPetAction(1, { name = "Claw", autoCastAllowed = true })
                local updates = 0
                local f = H.env.CreateFrame("Frame", nil, H.env.UIParent)
                f:RegisterEvent("PET_BAR_UPDATE")
                f:SetScript("OnEvent", function() updates = updates + 1 end)

                H.env.TogglePetAutocast(1)
                local _, _, _, _, _, enabled = H.env.GetPetActionInfo(1)
                expect(enabled).as("flipped on").truthy()
                expect(updates).eq(1)

                H.env.TogglePetAutocast(1)
                local _, _, _, _, _, again = H.env.GetPetActionInfo(1)
                expect(again).as("flipped back off").falsy()
                expect(H.getPetAutocastToggles()).len(2)
            end)

            it("SETS the state when given one, rather than flipping", function()
                -- TogglePetAutocast(slotID, enabled) takes two arguments on this client, per the
                -- client's own API stub, and the second is a state not a nudge. A model that always
                -- flipped would be indistinguishable from this as long as every caller passed the
                -- opposite of the current value -- which ours does, so the difference has to be
                -- asserted directly or it is untested.
                H.setPetAction(1, { name = "Claw", autoCastEnabled = false }, { silent = true })
                H.env.TogglePetAutocast(1, false)
                local _, _, _, _, _, enabled = H.env.GetPetActionInfo(1)
                expect(enabled).as("setting false on false leaves it false").falsy()
                H.env.TogglePetAutocast(1, true)
                local _, _, _, _, _, on = H.env.GetPetActionInfo(1)
                expect(on).truthy()
            end)

            it("still flips when no state is given, for a one-argument caller", function()
                H.setPetAction(1, { name = "Claw", autoCastEnabled = true }, { silent = true })
                H.env.TogglePetAutocast(1)
                local _, _, _, _, _, enabled = H.env.GetPetActionInfo(1)
                expect(enabled).falsy()
            end)

            it("fires UNIT_PET with unit player, which is what consumers filter on", function()
                -- UNIT_PET is filtered on "player" and UNIT_FLAGS on "pet". The wrong way round
                -- silently kills every update, so the unit this sends is pinned here.
                local seen
                local f = H.env.CreateFrame("Frame", nil, H.env.UIParent)
                f:RegisterEvent("UNIT_PET")
                f:SetScript("OnEvent", function(_, _, unit) seen = unit end)
                H.setPetActionBar(true)
                expect(seen).eq("player")
            end)

            it("rejects an unknown field rather than ignoring it", function()
                expect(function() H.setPetAction(1, { txture = "typo" }) end).throws("unknown pet field")
                expect(function() H.setStanceForm(1, { spel = 1 }) end).throws("unknown stance field")
            end)
        end)
    end)

    ---------------------------------------------------------------------------
    -- StatusBar as a real type
    ---------------------------------------------------------------------------
    -- SuuUI's own StatusBar component never uses the client's -- it drives fractional stack
    -- children through the layout engine on purpose -- so this type was a bare Frame with no
    -- SetValue anywhere in the harness. It became load-bearing the moment a BLIZZARD status
    -- bar had to be driven: GameTooltipStatusBar is the client's.
    describe("StatusBar", function()
        local function bar()
            return H.env.CreateFrame("StatusBar", nil, H.env.UIParent)
        end

        it("carries the value verbs a bare Frame did not", function()
            local b = bar()
            expect(type(b.SetValue)).eq("function")
            expect(type(b.SetMinMaxValues)).eq("function")
            expect(type(b.SetStatusBarColor)).eq("function")
        end)

        it("reads a value back", function()
            local b = bar()
            b:SetMinMaxValues(0, 200)
            b:SetValue(140)
            expect(b:GetValue()).eq(140)
            local min, max = b:GetMinMaxValues()
            expect(min).eq(0)
            expect(max).eq(200)
        end)

        it("CLAMPS to the range, as the client does", function()
            -- Load-bearing: a consumer computing a fraction from GetValue would read past 1
            -- for an over-max write, and a health bar handed a stale max does exactly that.
            local b = bar()
            b:SetMinMaxValues(0, 100)
            b:SetValue(500)
            expect(b:GetValue()).as("clamped to max").eq(100)
            b:SetValue(-20)
            expect(b:GetValue()).as("clamped to min").eq(0)
        end)

        it("re-clamps when the range narrows under a value", function()
            local b = bar()
            b:SetMinMaxValues(0, 1000)
            b:SetValue(900)
            b:SetMinMaxValues(0, 100)
            expect(b:GetValue()).eq(100)
        end)

        it("fires OnValueChanged only when the value actually moves", function()
            local n = 0
            local b = bar()
            b:SetMinMaxValues(0, 100)
            b:SetScript("OnValueChanged", function() n = n + 1 end)
            b:SetValue(50)
            expect(n).eq(1)
            b:SetValue(50)
            expect(n).as("an unchanged write is silent").eq(1)
            b:SetValue(60)
            expect(n).eq(2)
        end)

        it("ignores a non-number and a NaN write", function()
            local b = bar()
            b:SetValue(40)
            b:SetValue("70")
            expect(b:GetValue()).eq(40)
            b:SetValue(0 / 0)
            expect(b:GetValue()).as("NaN left it alone").eq(40)
        end)

        it("reads its colour back", function()
            local b = bar()
            b:SetStatusBarColor(0.2, 0.4, 0.6)
            local r, g, bl, a = b:GetStatusBarColor()
            expect(r).eq(0.2)
            expect(g).eq(0.4)
            expect(bl).eq(0.6)
            expect(a).as("alpha defaults to 1").eq(1)
        end)
    end)

    ---------------------------------------------------------------------------
    -- Tooltip scripts actually fire
    ---------------------------------------------------------------------------
    -- The four tooltip scripts were stored by SetScript and fired by NOTHING, so the only way
    -- a spec could reach a handler was to invoke it by hand -- which passes while nothing in
    -- production ever calls it. That mistake shipped a dead micro-menu button once already.
    describe("tooltip content setters fire the client's scripts", function()
        local function tip() return H.env.GameTooltip end

        local function watch(name)
            local hits = { n = 0 }
            tip():SetScript(name, function() hits.n = hits.n + 1 end)
            return hits
        end

        it("SetUnit fires OnTooltipSetUnit and records the unit", function()
            local hits = watch("OnTooltipSetUnit")
            H.setUnit("target", { name = "Illidan" })
            tip():SetUnit("target")
            expect(hits.n).eq(1)
            expect(H.getTooltipState().unit).eq("target")
        end)

        it("GetUnit answers a name and the unit id, in that order", function()
            H.setUnit("target", { name = "Illidan" })
            tip():SetUnit("target")
            local name, unit = tip():GetUnit()
            expect(name).eq("Illidan")
            expect(unit).eq("target")
        end)

        it("GetUnit answers nothing before a unit is set", function()
            local name, unit = tip():GetUnit()
            expect(name).isNil()
            expect(unit).isNil()
        end)

        it("SetHyperlink fires OnTooltipSetItem and records the link", function()
            local hits = watch("OnTooltipSetItem")
            tip():SetHyperlink("|cffa335ee|Hitem:12345|h[Thing]|h|r")
            expect(hits.n).eq(1)
            expect(H.getTooltipState().item).eq("|cffa335ee|Hitem:12345|h[Thing]|h|r")
        end)

        it("SetSpellByID fires OnTooltipSetSpell and GetSpell answers the id", function()
            local hits = watch("OnTooltipSetSpell")
            tip():SetSpellByID(27071)
            expect(hits.n).eq(1)
            local _, id = tip():GetSpell()
            expect(id).eq(27071)
        end)

        it("ClearLines fires OnTooltipCleared", function()
            -- A consumer resets its per-show state here -- a quality border, reserved
            -- padding -- so a silent model would let the reset be asserted by hand while
            -- production never reached it.
            local hits = watch("OnTooltipCleared")
            tip():AddLine("something")
            tip():ClearLines()
            expect(hits.n).eq(1)
            expect(tip():NumLines()).eq(0)
        end)

        it("SetInventoryItem reports whether there was an item", function()
            local hasItem = tip():SetInventoryItem("player", 5)
            expect(type(hasItem)).eq("boolean")
        end)

        it("each setter fires only its OWN script", function()
            local unitHits = watch("OnTooltipSetUnit")
            local itemHits = watch("OnTooltipSetItem")
            tip():SetHyperlink("|Hitem:1|h[x]|h")
            expect(itemHits.n).eq(1)
            expect(unitHits.n).as("an item did not fire the unit script").eq(0)
        end)
    end)

    ---------------------------------------------------------------------------
    -- Tooltip padding, double lines, NineSlice
    ---------------------------------------------------------------------------
    describe("tooltip padding and structure", function()
        local function tip() return H.env.GameTooltip end

        it("reads padding back in the client's argument order", function()
            -- Measured in game: both the two-arg and four-arg forms are accepted, and
            -- GetPadding answers, which is what makes reserving space verifiable rather
            -- than guessed.
            tip():SetPadding(1, 24, 3, 4)
            local right, bottom, left, top = tip():GetPadding()
            expect(right).eq(1)
            expect(bottom).eq(24)
            expect(left).eq(3)
            expect(top).eq(4)
        end)

        it("accepts the two-argument form and zeroes the rest", function()
            tip():SetPadding(0, 24)
            local right, bottom, left, top = tip():GetPadding()
            expect(right).eq(0)
            expect(bottom).eq(24)
            expect(left).eq(0)
            expect(top).eq(0)
        end)

        it("starts at no padding", function()
            local right, bottom = tip():GetPadding()
            expect(right).eq(0)
            expect(bottom).eq(0)
        end)

        it("keeps AddDoubleLine's RIGHT-hand colours", function()
            -- They used to be accepted and discarded, which made every assertion about a
            -- right-hand value's colour vacuous -- and the right-hand slot is exactly where
            -- a tone-coloured reading goes.
            tip():AddDoubleLine("Item Level", "154", 1, 1, 1, 0.2, 0.4, 0.6)
            local left, right = tip():GetLine(1)
            expect(left).eq("Item Level")
            expect(right).eq("154")
            local lr, lg, lb, rr, rg, rb = tip():GetLineColor(1)
            expect(lr).eq(1)
            expect(lg).eq(1)
            expect(lb).eq(1)
            expect(rr).as("right r survived").eq(0.2)
            expect(rg).as("right g survived").eq(0.4)
            expect(rb).as("right b survived").eq(0.6)
        end)

        it("carries a NineSlice, so hiding it is a reachable branch", function()
            -- MEASURED present on this client, against an earlier guess that it was absent.
            -- A reskin that only calls SetBackdrop leaves this drawing underneath and the
            -- player sees a double frame, so the hide must not be dead code.
            expect(tip().NineSlice).truthy()
            tip().NineSlice:SetAlpha(0)
            expect(tip().NineSlice:GetAlpha()).eq(0)
        end)

        it("answers IsForbidden, which Blizzard checks at every entry point", function()
            expect(tip():IsForbidden()).eq(false)
        end)
    end)

    ---------------------------------------------------------------------------
    -- GameTooltipStatusBar
    ---------------------------------------------------------------------------
    describe("GameTooltipStatusBar", function()
        it("exists, is a StatusBar, and is parented to the tooltip", function()
            local sb = H.env.GameTooltipStatusBar
            expect(sb).truthy()
            expect(type(sb.SetValue)).eq("function")
            expect(sb:GetParent()).eq(H.env.GameTooltip)
        end)

        it("takes a value and a colour the addon supplies", function()
            -- The client ships this bar with NO text and NO colour; both are the addon's to
            -- provide, which is the whole reason a spec has to read them back.
            local sb = H.env.GameTooltipStatusBar
            sb:SetMinMaxValues(0, 15240)
            sb:SetValue(7620)
            sb:SetStatusBarColor(0.25, 0.78, 0.92)
            expect(sb:GetValue()).eq(7620)
            local r = select(1, sb:GetStatusBarColor())
            expect(r).eq(0.25)
        end)

        it("is rebuilt per setup, so a staged value cannot leak between tests", function()
            expect(H.env.GameTooltipStatusBar:GetValue()).eq(100)
        end)
    end)

    ---------------------------------------------------------------------------
    -- Tooltip Font objects
    ---------------------------------------------------------------------------
    describe("tooltip Font objects", function()
        it("ships the three the client inherits tooltip text from", function()
            expect(H.env.GameTooltipText).truthy()
            expect(H.env.GameTooltipHeaderText).truthy()
            expect(H.env.GameTooltipTextSmall).truthy()
        end)

        it("is settable, which is what makes one call cover unborn lines", function()
            -- The sanctioned way to restyle tooltip text: assign these three once rather
            -- than walking GameTooltipTextLeft1..N, because the client creates line objects
            -- on demand and a walk has to be redone on every show forever.
            H.env.GameTooltipText:SetFont("Fonts/ARIALN.TTF", 14, "")
            local path, size = H.env.GameTooltipText:GetFont()
            expect(path).eq("Fonts/ARIALN.TTF")
            expect(size).eq(14)
        end)

        it("RAISES on an unloadable asset, exactly as FontString:SetFont does", function()
            -- Same trap, same reason: modelling this as a return value once let an error
            -- unwind out of a PLAYER_LOGIN handler. Anything probing paths must pcall.
            expect(function()
                H.env.GameTooltipHeaderText:SetFont("Fonts/NOPE.TTF", 12, "")
            end).throws("Invalid font asset")
        end)

        it("keeps the three independent, so the header can carry its own size", function()
            H.env.GameTooltipText:SetFont("Fonts/ARIALN.TTF", 11, "")
            H.env.GameTooltipHeaderText:SetFont("Fonts/FRIZQT__.TTF", 17, "")
            expect(select(2, H.env.GameTooltipText:GetFont())).eq(11)
            expect(select(2, H.env.GameTooltipHeaderText:GetFont())).eq(17)
        end)

        it("is visible to the GetFonts harvest like every other font object", function()
            local seen = {}
            for _, n in ipairs(H.env.GetFonts()) do seen[n] = true end
            expect(seen.GameTooltipText).truthy()
            expect(seen.GameTooltipHeaderText).truthy()
        end)
    end)

    ---------------------------------------------------------------------------
    -- Harness-only helpers must not leak into shipped code
    ---------------------------------------------------------------------------
    -- This exists because the leak ALREADY HAPPENED and a green suite could not see it.
    -- `GetLine` is a convenience this harness provides so a spec can read a tooltip's text back.
    -- The real GameTooltip has no such method -- so Plugins/Tooltips/Content.lua calling it
    -- raised "attempt to call a nil value" on the first mouseover in game while 4325 assertions
    -- stayed green, because the harness supplied exactly what production was missing.
    --
    -- That is the worst shape of harness bug: the model is not merely thin, it is GENEROUS, and a
    -- generous model makes production look correct. No assertion about behaviour can catch it,
    -- because in the harness the behaviour IS correct. So this reads the shipped files.
    describe("harness-only helpers stay out of shipped code", function()
        -- Methods that exist ONLY on the simulated client. Add to this list whenever a
        -- harness-only convenience is introduced.
        local HARNESS_ONLY = {
            "GetLine", "GetLineColor", "_lineFontString", "_fire",
        }

        -- The files the client really loads, read from the .toc rather than globbed: a file that
        -- is not in the .toc is not shipped, and Tests/ is deliberately absent from it.
        local function shippedFiles()
            local out = {}
            local toc = io.open("SuuUI.toc", "r")
            if not toc then return out end
            for line in toc:lines() do
                local path = line:match("^%s*([%w_/%.%-]+%.lua)%s*$")
                -- Libs/ is vendored third-party code and exempt by the same rule that exempts it
                -- from every other convention here.
                if path and not path:match("^Libs/") then out[#out + 1] = path end
            end
            toc:close()
            return out
        end

        it("reads a non-empty file list from the .toc", function()
            -- Without this the whole block passes vacuously by checking nothing -- the exact
            -- failure mode it exists to prevent.
            expect(#shippedFiles()).gt(20)
        end)

        it("no shipped file CALLS a harness-only method", function()
            local offenders = {}
            for _, path in ipairs(shippedFiles()) do
                local f = io.open(path, "r")
                if f then
                    local src = f:read("*a")
                    f:close()
                    -- Strip line comments first: these names are legitimately DISCUSSED in the
                    -- comments that explain why they must not be called.
                    src = src:gsub("%-%-[^\n]*", "")
                    for _, name in ipairs(HARNESS_ONLY) do
                        -- A CALL, not a definition: `:name(` or `.name(`. Our own methods of the
                        -- same name defined with `function M.name(` are not matched.
                        if src:find("[:%.]" .. name .. "%s*%(") then
                            offenders[#offenders + 1] = path .. " calls " .. name
                        end
                    end
                end
            end
            expect(table.concat(offenders, "; ")).as("harness-only calls in shipped code").eq("")
        end)
    end)
end)

-- Containers, the bank gate and the cursor. Every fact asserted here was MEASURED on this
-- client 2026-08-24 (see .kiro/specs/inventory.md section 0), so these tests pin the client
-- rather than a convenient model -- which is the whole reason the default mode changed.
describe("harness: containers and the bank", function()
    before_each(function() H.setup() end)

    -- The defect this block exists for. The default used to be "legacy", which modelled a client
    -- with the bare globals and NO C_Container -- the exact opposite of what was measured, so
    -- every bags spec ran against a shape that does not exist.
    describe("the default API mode is modern", function()
        it("exposes C_Container", function()
            expect(type(H.env.C_Container)).as("C_Container is a table").eq("table")
            expect(type(H.env.C_Container.GetContainerItemInfo)).eq("function")
        end)

        it("does NOT expose the bare globals", function()
            expect(H.env.GetContainerNumSlots).as("bare numSlots is nil").falsy()
            expect(H.env.GetContainerItemInfo).as("bare itemInfo is nil").falsy()
            expect(H.env.UseContainerItem).as("bare use is nil").falsy()
            expect(H.env.PickupContainerItem).as("bare pickup is nil").falsy()
        end)

        it("swaps cleanly to legacy and back, with the other shape removed each time", function()
            H.setBagApi("legacy")
            expect(H.env.C_Container).as("no namespace on legacy").falsy()
            expect(type(H.env.GetContainerItemInfo)).eq("function")
            H.setBagApi("modern")
            expect(H.env.GetContainerItemInfo).as("bare form gone again").falsy()
            expect(type(H.env.C_Container)).eq("table")
        end)

        it("removes both shapes for 'none'", function()
            H.setBagApi("none")
            expect(H.env.C_Container).falsy()
            expect(H.env.GetContainerItemInfo).falsy()
        end)

        -- The property that makes two modes worth modelling at all. A legacy mode handing back the
        -- modern TABLE under an old name cannot exercise a positional reader, so a spec written
        -- against it would pass while the real legacy client fed eleven values nothing unpacked.
        it("legacy returns the POSITIONAL tuple, not the modern table", function()
            H.setBagItem(0, 1, { itemID = 22832, itemName = "Arcane Powder", stackCount = 12,
                                 iconFileID = 134129, quality = 1 })
            local modern = H.env.C_Container.GetContainerItemInfo(0, 1)
            expect(type(modern)).as("modern is a table").eq("table")

            H.setBagApi("legacy")
            local icon, count, locked, quality = H.env.GetContainerItemInfo(0, 1)
            expect(type(icon)).as("legacy first return is the icon, not a table").eq("number")
            expect(icon).eq(134129)
            expect(count).eq(12)
            expect(locked).eq(false)
            expect(quality).eq(1)
            -- The id sits at position 10, which is the whole reason a positional reader has to
            -- count rather than guess.
            expect(select(10, H.env.GetContainerItemInfo(0, 1))).as("itemID is 10th").eq(22832)
        end)
    end)

    describe("GetContainerItemInfo", function()
        it("answers nil for an empty slot rather than a record of zeroes", function()
            expect(H.env.C_Container.GetContainerItemInfo(0, 1)).as("empty slot").eq(nil)
        end)

        it("returns the measured field set", function()
            H.setBagItem(0, 1, { itemID = 22832, itemName = "Arcane Powder",
                                 hyperlink = "|cffffffff|Hitem:22832|h[Arcane Powder]|h|r",
                                 iconFileID = 134129, quality = 1, stackCount = 12 })
            local i = H.env.C_Container.GetContainerItemInfo(0, 1)
            expect(i.itemID).eq(22832)
            expect(i.itemName).eq("Arcane Powder")
            expect(i.stackCount).eq(12)
            expect(i.quality).eq(1)
            expect(i.iconFileID).eq(134129)
            -- Booleans are present-and-false rather than absent, as the client reports them.
            expect(i.isLocked).as("isLocked defaults false, not nil").eq(false)
            expect(i.hasNoValue).eq(false)
        end)

        it("returns a FRESH table per call, so a caller cannot reach into the store", function()
            H.setBagItem(0, 1, { itemID = 22832, stackCount = 12 })
            local a = H.env.C_Container.GetContainerItemInfo(0, 1)
            a.stackCount = 999
            local b = H.env.C_Container.GetContainerItemInfo(0, 1)
            expect(b.stackCount).as("store untouched by a mutated copy").eq(12)
        end)

        it("MERGES on re-stage, so locking a slot keeps the item in it", function()
            H.setBagItem(0, 1, { itemID = 22832, stackCount = 12 })
            H.setBagItem(0, 1, { isLocked = true })
            local i = H.env.C_Container.GetContainerItemInfo(0, 1)
            expect(i.itemID).as("item survived the merge").eq(22832)
            expect(i.isLocked).eq(true)
        end)

        it("raises on an unknown field rather than dropping it", function()
            expect(function() H.setBagItem(0, 1, { stackCoutn = 4 }) end).throws()
        end)

        it("clearBagItem empties the slot", function()
            H.setBagItem(0, 1, { itemID = 22832 })
            H.clearBagItem(0, 1)
            expect(H.env.C_Container.GetContainerItemInfo(0, 1)).eq(nil)
        end)
    end)

    -- The pair that matters: the slot COUNT survives a shut bank, the CONTENTS do not. That is
    -- what makes "28 slots, 0 free" the signature of no data rather than of an empty bank.
    describe("the bank is gated on its frame being open", function()
        before_each(function()
            H.setBagItem(-1, 1, { itemID = 22832, itemName = "Arcane Powder", stackCount = 20 },
                         { silent = true })
        end)

        it("hides contents while shut and reveals them when open", function()
            expect(H.env.C_Container.GetContainerItemInfo(-1, 1)).as("shut").eq(nil)
            H.setBankOpen(true)
            local i = H.env.C_Container.GetContainerItemInfo(-1, 1)
            expect(i and i.itemID).as("open").eq(22832)
            H.setBankOpen(false)
            expect(H.env.C_Container.GetContainerItemInfo(-1, 1)).as("shut again").eq(nil)
        end)

        it("still answers the slot count while shut", function()
            expect(H.env.C_Container.GetContainerNumSlots(-1)).as("shut").eq(28)
            H.setBankOpen(true)
            expect(H.env.C_Container.GetContainerNumSlots(-1)).as("open").eq(28)
        end)

        it("reports zero free while shut even with slots staged", function()
            H.setBags({ [-1] = { free = 12, slots = 28 } }, { silent = true })
            expect(H.env.C_Container.GetContainerNumFreeSlots(-1)).as("shut").eq(0)
            H.setBankOpen(true)
            expect(H.env.C_Container.GetContainerNumFreeSlots(-1)).as("open").eq(12)
        end)

        it("gates the bank BAGS too, not only container -1", function()
            H.setBagItem(5, 3, { itemID = 21877 }, { silent = true })
            expect(H.env.C_Container.GetContainerItemInfo(5, 3)).as("shut").eq(nil)
            H.setBankOpen(true)
            expect(H.env.C_Container.GetContainerItemInfo(5, 3)).as("open").truthy()
        end)

        it("leaves the player's own bags alone in both states", function()
            H.setBagItem(0, 1, { itemID = 33470 }, { silent = true })
            expect(H.env.C_Container.GetContainerItemInfo(0, 1)).as("bags shut").truthy()
            H.setBankOpen(true)
            expect(H.env.C_Container.GetContainerItemInfo(0, 1)).as("bags open").truthy()
        end)

        it("fires the bracketing events only on a real transition", function()
            local seen = {}
            local f = H.env.CreateFrame("Frame")
            f:RegisterEvent("BANKFRAME_OPENED")
            f:RegisterEvent("BANKFRAME_CLOSED")
            f:SetScript("OnEvent", function(_, e) seen[#seen + 1] = e end)
            H.setBankOpen(true)
            H.setBankOpen(true)
            H.setBankOpen(false)
            expect(#seen).as("two transitions, not three calls").eq(2)
            expect(seen[1]).eq("BANKFRAME_OPENED")
            expect(seen[2]).eq("BANKFRAME_CLOSED")
        end)
    end)

    describe("the cursor carries a slot's contents", function()
        it("picks an item up and reports it as the client does", function()
            H.setBagItem(0, 1, { itemID = 27860, stackCount = 5,
                                 hyperlink = "|cffffffff|Hitem:27860|h[Purified Draenic Water]|h|r" })
            H.env.C_Container.PickupContainerItem(0, 1)
            expect(H.env.CursorHasItem()).truthy()
            local kind, id, link = H.env.GetCursorInfo()
            expect(kind).as("measured triple: item, id, link").eq("item")
            expect(id).eq(27860)
            expect(link).eq("|cffffffff|Hitem:27860|h[Purified Draenic Water]|h|r")
            expect(H.env.C_Container.GetContainerItemInfo(0, 1)).as("slot emptied").eq(nil)
        end)

        it("SWAPS onto an occupied slot instead of overwriting", function()
            H.setBagItem(0, 1, { itemID = 111 })
            H.setBagItem(0, 2, { itemID = 222 })
            H.env.C_Container.PickupContainerItem(0, 1)
            H.env.C_Container.PickupContainerItem(0, 2)
            expect(H.env.C_Container.GetContainerItemInfo(0, 2).itemID).as("placed").eq(111)
            -- The previous occupant came BACK to the cursor. A cell assuming overwrite would have
            -- destroyed it, which is an item lost on every rearrange.
            expect(select(2, H.env.GetCursorInfo())).as("previous occupant returned").eq(222)
        end)

        it("splits a stack onto the cursor and leaves the remainder", function()
            H.setBagItem(0, 1, { itemID = 22832, stackCount = 20 })
            H.env.C_Container.SplitContainerItem(0, 1, 5)
            expect(select(2, H.env.GetCursorInfo())).eq(22832)
            expect(H.getCursorItem().stackCount).eq(5)
            expect(H.env.C_Container.GetContainerItemInfo(0, 1).stackCount).as("remainder").eq(15)
        end)

        it("ClearCursor drops what it was holding", function()
            H.setBagItem(0, 1, { itemID = 22832 })
            H.env.C_Container.PickupContainerItem(0, 1)
            H.env.ClearCursor()
            expect(H.env.CursorHasItem()).falsy()
            expect(H.env.GetCursorInfo()).eq(nil)
        end)

        it("refuses to pick up out of a shut bank", function()
            H.setBagItem(-1, 1, { itemID = 22832 }, { silent = true })
            H.env.C_Container.PickupContainerItem(-1, 1)
            expect(H.env.CursorHasItem()).as("nothing lifted from a shut bank").falsy()
        end)
    end)

    -- BOTH halves of the gate. UseContainerItem SELLS at a merchant and USES the item away from
    -- one, and the use path is protected on this client -- so the same call has two outcomes and a
    -- spec asserting only the working one would not notice the block at all.
    describe("UseContainerItem has two protection profiles", function()
        before_each(function()
            H.setBagItem(0, 1, { itemID = 22832, quality = 0, stackCount = 1 })
        end)

        -- ESTABLISHED TWICE, by different routes, and briefly retracted in between: a probe raising
        -- ForceTaint_Strong, and then -- after the probe was wrongly dismissed as invalid because a
        -- chat-box `/run` is not a hardware event -- a real right-click raising the player-facing
        -- `SuuUI has been blocked from an action only available to the Blizzard UI` popup. The flaw in
        -- the dismissal is that a hardware event does not launder taint: an addon's OnClick is tainted
        -- code whatever triggered it.
        --
        -- Modelling the refusal is what makes an ungated production call a detectable defect. With it
        -- removed, the change that put that popup on screen passed a green suite.
        it("is REFUSED away from a merchant, and recorded as blocked", function()
            H.resetBlockedActions()
            H.env.C_Container.UseContainerItem(0, 1)
            local blocked = H.getBlockedActions()
            expect(#blocked).as("one refusal recorded").eq(1)
            expect(blocked[1].action).eq("UseContainerItem")
            expect(H.env.C_Container.GetContainerItemInfo(0, 1)).as("item untouched").truthy()
            expect(#H.getUsedContainerItems()).as("nothing sold").eq(0)
        end)

        it("is ACCEPTED at a merchant, and consumes the slot", function()
            H.setMerchantOpen(true)
            H.resetBlockedActions()
            H.env.C_Container.UseContainerItem(0, 1)
            expect(#H.getBlockedActions()).as("not refused at a merchant").eq(0)
            local used = H.getUsedContainerItems()
            expect(#used).eq(1)
            expect(used[1].bag).eq(0)
            expect(used[1].slot).eq(1)
            expect(used[1].via).as("a sale, not a use").eq("merchant")
            expect(H.env.C_Container.GetContainerItemInfo(0, 1)).as("slot emptied").eq(nil)
        end)

        it("is ACCEPTED at an open bank, and reports the transfer distinctly", function()
            H.setBankOpen(true)
            H.resetBlockedActions()
            H.env.C_Container.UseContainerItem(0, 1)
            expect(#H.getBlockedActions()).as("not refused at a bank").eq(0)
            local used = H.getUsedContainerItems()
            expect(#used).eq(1)
            expect(used[1].via).as("a transfer, not a sale").eq("bank")
        end)

        it("hands back a COPY of the sale record", function()
            H.setMerchantOpen(true)
            H.env.C_Container.UseContainerItem(0, 1)
            local a = H.getUsedContainerItems()
            a[1].slot = 99
            expect(H.getUsedContainerItems()[1].slot).as("record untouched").eq(1)
        end)
    end)

    describe("reset clears the container stores", function()
        it("drops contents, the cursor, the gates and the sale record", function()
            H.setBagItem(0, 1, { itemID = 22832 })
            H.env.C_Container.PickupContainerItem(0, 1)
            H.setBankOpen(true)
            H.setMerchantOpen(true)
            H.setup()
            expect(H.env.CursorHasItem()).as("cursor").falsy()
            expect(H.env.C_Container.GetContainerItemInfo(0, 1)).as("contents").eq(nil)
            expect(#H.getUsedContainerItems()).as("sales").eq(0)
            -- The bank gate must reset to SHUT, because that is the state the snapshot design
            -- depends on: a leaked open bank would make every later "not readable" assertion pass
            -- for the wrong reason.
            H.setBagItem(-1, 1, { itemID = 22832 }, { silent = true })
            expect(H.env.C_Container.GetContainerItemInfo(-1, 1)).as("bank shut again").eq(nil)
        end)

        it("restores the modern API mode", function()
            H.setBagApi("none")
            H.setup()
            expect(type(H.env.C_Container)).as("back to modern").eq("table")
        end)
    end)
end)

-- The assertion framework itself, not the simulated client. Same reasoning as the block
-- above: a spec's failure MESSAGE is load-bearing, because a formatter that dies takes the
-- diagnosis with it and leaves you debugging the harness instead of the code.
describe("harness: assertion framework", function()
    local fw = require("harness.framework")

    before_each(function() H.setup() end)

    describe("fmt", function()
        it("renders scalars and shallow tables readably", function()
            expect(fw.fmt(3)).eq("3")
            expect(fw.fmt("hi")).eq('"hi"')
            expect(fw.fmt({ 1, 2 })).eq("{1, 2}")
            expect(fw.fmt({ a = 1 })).eq("{a=1}")
        end)

        it("stops at a depth cap instead of walking the whole tree", function()
            local deep = { l1 = { l2 = { l3 = { l4 = { l5 = "too far" } } } }, }
            local s = fw.fmt(deep)
            expect(s:find("%.%.%.", 1) ~= nil)
                .as("past the cap it prints an elision, not the next level").eq(true)
            expect(s:find("too far", 1, true))
                .as("the leaf beyond the cap is never reached").isNil()
        end)

        it("marks a cycle instead of following it", function()
            local a = {}
            a.self = a
            expect(fw.fmt(a):find("<cycle>", 1, true))
                .as("a table that contains itself terminates").notNil()
        end)

        it("formats a widget handle without overflowing the stack", function()
            -- The regression this cap exists for. A handle's fields reach frames, which
            -- point back at their parent and across at every sibling, so formatting one
            -- naively recursed until the stack went — and `expect(handleA).eq(handleB)`
            -- then reported "stack overflow" rather than a diagnosis, exactly when a spec
            -- most needed one. Found while mutation-testing AccordionGroup.
            local host = H.parent(300, 200)
            local tog  = H.mount(H.C.Toggle({}, host))
            local ok, out = pcall(fw.fmt, tog)
            expect(ok).as("formatting a live handle must not raise").eq(true)
            expect(type(out)).eq("string")
            expect(#out < 4000)
                .as("and it stays short enough to read in a failure line").eq(true)
        end)

        it("formats two frames well enough to tell them apart", function()
            local a = H.parent(10, 10)
            local b = H.parent(20, 20)
            local ok = pcall(function() return fw.fmt(a) .. fw.fmt(b) end)
            expect(ok).eq(true)
        end)
    end)
end)

describe("harness: key bindings", function()
    before_each(function() H.setup() end)

    local function eventProbe(event)
        local probe = H.env.CreateFrame("Frame", nil, H.UIParent)
        local seen = { n = 0 }
        probe:RegisterEvent(event)
        probe:SetScript("OnEvent", function(_, ev)
            if ev == event then seen.n = seen.n + 1 end
        end)
        return seen
    end

    describe("reading", function()
        it("answers every key bound to a command, not just the first", function()
            H.setBinding("ACTIONBUTTON1", "1")
            H.addBinding("ACTIONBUTTON1", "CTRL-F9")
            local a, b = H.env.GetBindingKey("ACTIONBUTTON1")
            expect(a).eq("1")
            expect(b)
                .as("measured in game 2026-08-26: GetBindingKey answered `1 CTRL-F9`").eq("CTRL-F9")
        end)

        it("answers nil for a command holding no keys", function()
            expect(H.env.GetBindingKey("ACTIONBUTTON1")).eq(nil)
        end)

        it("names the command that owns a key", function()
            H.setBinding("ACTIONBUTTON4", "CTRL-4")
            expect(H.env.GetBindingAction("CTRL-4")).eq("ACTIONBUTTON4")
        end)

        it("answers the empty string for an unowned key, not nil", function()
            expect(H.env.GetBindingAction("CTRL-4"))
                .as("Blizzard's documented shape, and the ONE thing here not measured in game -- "
                    .. "so production has to treat nil and \"\" alike").eq("")
        end)
    end)

    describe("writing", function()
        it("binds a key and reports success", function()
            expect(H.env.SetBinding("SHIFT-Q", "ACTIONBUTTON3")).eq(true)
            expect(H.env.GetBindingKey("ACTIONBUTTON3")).eq("SHIFT-Q")
        end)

        it("fires UPDATE_BINDINGS, which is what re-routes every bar", function()
            local seen = eventProbe("UPDATE_BINDINGS")
            H.env.SetBinding("SHIFT-Q", "ACTIONBUTTON3")
            expect(seen.n)
                .as("measured: the event printed BEFORE SetBinding's own return value. Without it "
                    .. "the keybind mode would need re-route code of its own").eq(1)
        end)

        it("unbinds when the command is omitted", function()
            H.setBinding("ACTIONBUTTON1", "1")
            expect(H.env.SetBinding("1")).as("this is the ESC-clear mechanism").eq(true)
            expect(H.env.GetBindingKey("ACTIONBUTTON1")).eq(nil)
        end)

        it("takes the key off whichever command already held it", function()
            H.setBinding("ACTIONBUTTON1", "M")
            H.env.SetBinding("M", "ACTIONBUTTON2")
            expect(H.env.GetBindingKey("ACTIONBUTTON1"))
                .as("a key belongs to exactly one command -- this steal is what the conflict "
                    .. "warning exists to announce").eq(nil)
            expect(H.env.GetBindingKey("ACTIONBUTTON2")).eq("M")
        end)

        it("appends rather than replacing, so a command can hold several keys", function()
            H.env.SetBinding("1", "ACTIONBUTTON1")
            H.env.SetBinding("CTRL-F9", "ACTIONBUTTON1")
            expect(select("#", H.env.GetBindingKey("ACTIONBUTTON1"))).eq(2)
        end)

        it("drops a command entirely once its last key is stolen", function()
            H.setBinding("ACTIONBUTTON1", "M")
            H.env.SetBinding("M", "ACTIONBUTTON2")
            H.env.SaveBindings(1)
            expect(H.getSavedBindings(1).ACTIONBUTTON1)
                .as("an emptied command must be ABSENT, not an empty list -- both read as "
                    .. "unbound through GetBindingKey today, so only the stored shape can catch "
                    .. "it, and a later `if state.bindings[cmd] then` would find {} truthy")
                .eq(nil)
        end)
    end)

    describe("in combat", function()
        it("refuses the write and returns false rather than raising", function()
            H.setCombat(true)
            local ok, ret = pcall(H.env.SetBinding, "SHIFT-Z", "ACTIONBUTTON5")
            expect(ok)
                .as("measured `setbind true false`: the pcall SUCCEEDED, so a pcall wrapper "
                    .. "catches nothing and production must gate on InCombatLockdown").eq(true)
            expect(ret).eq(false)
        end)

        it("leaves the bindings untouched", function()
            H.setBinding("ACTIONBUTTON5", "5")
            H.setCombat(true)
            H.env.SetBinding("SHIFT-Z", "ACTIONBUTTON5")
            local keys = H.getBindings("ACTIONBUTTON5")
            expect(#keys).eq(1)
            expect(keys[1]).eq("5")
        end)

        it("does not fire UPDATE_BINDINGS", function()
            H.setCombat(true)
            local seen = eventProbe("UPDATE_BINDINGS")
            H.env.SetBinding("SHIFT-Z", "ACTIONBUTTON5")
            expect(seen.n).as("a refused write changed nothing, so nothing should re-route").eq(0)
        end)
    end)

    describe("the saved set", function()
        it("starts on the account-wide set", function()
            expect(H.env.GetCurrentBindingSet())
                .as("measured 1 on the reference character").eq(1)
        end)

        it("SaveBindings copies the live bindings to disk", function()
            H.setBinding("ACTIONBUTTON1", "1")
            H.env.SaveBindings(1)
            expect(H.getSavedBindings(1).ACTIONBUTTON1[1]).eq("1")
        end)

        it("SaveBindings does not fire UPDATE_BINDINGS", function()
            local seen = eventProbe("UPDATE_BINDINGS")
            H.env.SaveBindings(1)
            expect(seen.n)
                .as("measured: a line calling SetBinding then SaveBindings produced exactly ONE "
                    .. "event, and SetBinding is the one that fires it").eq(0)
        end)

        it("LoadBindings reverts a live edit, which is how Discard works", function()
            H.setBinding("ACTIONBUTTON1", "1")
            H.env.SaveBindings(1)
            H.env.SetBinding("CTRL-F9", "ACTIONBUTTON1")
            expect(select("#", H.env.GetBindingKey("ACTIONBUTTON1"))).eq(2)

            H.env.LoadBindings(1)
            local a, b = H.env.GetBindingKey("ACTIONBUTTON1")
            expect(a).eq("1")
            expect(b)
                .as("the saved set IS the snapshot, so Discard needs no snapshot table of ours")
                .eq(nil)
        end)

        it("LoadBindings fires UPDATE_BINDINGS", function()
            H.env.SaveBindings(1)
            local seen = eventProbe("UPDATE_BINDINGS")
            H.env.LoadBindings(1)
            expect(seen.n)
                .as("measured: the event fired before `after discard 1` printed").eq(1)
        end)

        it("keeps the account-wide and character sets apart", function()
            H.setBinding("ACTIONBUTTON1", "1")
            H.env.SaveBindings(1)
            H.setBinding("ACTIONBUTTON1", "SHIFT-1")
            H.env.SaveBindings(2)

            H.env.LoadBindings(1)
            expect(H.env.GetBindingKey("ACTIONBUTTON1")).eq("1")
            H.env.LoadBindings(2)
            expect(H.env.GetBindingKey("ACTIONBUTTON1"))
                .as("the panel's per-character toggle switches between these two").eq("SHIFT-1")
        end)
    end)

    describe("the meta modifier", function()
        it("is reported by IsMetaKeyDown", function()
            expect(H.env.IsMetaKeyDown()).eq(false)
            H.mods({ meta = true })
            expect(H.env.IsMetaKeyDown())
                .as("Cmd is live on this client and the reference machine is macOS").eq(true)
        end)

        it("counts as a modifier", function()
            H.mods({ meta = true })
            expect(H.env.IsModifierKeyDown()).eq(true)
        end)

        it("is cleared by setup, so a held modifier cannot leak between spec files", function()
            H.mods({ shift = true, meta = true })
            H.setup()
            expect(H.env.IsShiftKeyDown())
                .as("a leaked modifier turns a staged \"F\" into \"SHIFT-F\"").eq(false)
            expect(H.env.IsMetaKeyDown()).eq(false)
        end)
    end)

    describe("H.keyUp", function()
        it("delivers a release to a keyboard-enabled frame", function()
            local f = H.parent(40, 40)
            f:EnableKeyboard(true)
            local got
            f:SetScript("OnKeyUp", function(_, k) got = k end)
            expect(H.keyUp(f, "SHIFT-P")).eq(true)
            expect(got)
                .as("keybind capture reads the key on RELEASE, so a modifier still held is part "
                    .. "of the combination").eq("SHIFT-P")
        end)

        it("refuses a frame whose keyboard input is released", function()
            local f = H.parent(40, 40)
            f:EnableKeyboard(false)
            local got
            f:SetScript("OnKeyUp", function(_, k) got = k end)
            expect(H.keyUp(f, "SHIFT-P"))
                .as("this gate is what makes \"the overlay only listens while hovered\" assertable")
                .eq(false)
            expect(got).eq(nil)
        end)
    end)
end)
