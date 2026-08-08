local H = require("harness")

describe("UIRoot", function()
    before_each(function() H.setup() end)

    it("creates one fullscreen root under UIParent", function()
        local root = H.SuuUI.UIRoot:GetRoot()
        expect(root:GetName()).eq("SuuUI_UIRoot")
        expect(root:GetParent()).eq(H.UIParent)
        H.expectSize(root, H.UIParent:GetWidth(), H.UIParent:GetHeight())
    end)

    it("is idempotent", function()
        local root = H.SuuUI.UIRoot:GetRoot()
        H.SuuUI.UIRoot:Init()
        expect(H.SuuUI.UIRoot:GetRoot()).eq(root)
    end)

    it("places an element at the requested offset", function()
        local f = H.env.CreateFrame("Frame", nil, H.SuuUI.UIRoot:GetRoot())
        f:SetSize(100, 50)
        H.SuuUI.UIRoot:AddElement(f, "normal", { point = "TOPLEFT", x = 30, y = -40 })
        H.expectBox(f, { left = 30, top = 40, width = 100, height = 50 })
    end)

    it("takes width and height from the anchor descriptor", function()
        local f = H.env.CreateFrame("Frame", nil, H.SuuUI.UIRoot:GetRoot())
        H.SuuUI.UIRoot:AddElement(f, "normal",
            { point = "TOPLEFT", x = 0, y = 0, width = 250, height = 120 })
        H.expectSize(f, 250, 120)
    end)

    it("maps each layer to its frame strata", function()
        for layer, strata in pairs({ background = "LOW", normal = "MEDIUM",
                                     window = "HIGH", dialog = "DIALOG",
                                     tooltip = "TOOLTIP" }) do
            local f = H.env.CreateFrame("Frame", nil, H.SuuUI.UIRoot:GetRoot())
            H.SuuUI.UIRoot:AddElement(f, layer, { point = "CENTER", x = 0, y = 0 })
            expect(f:GetFrameStrata()).as(layer).eq(strata)
        end
    end)

    it("reads a layer's strata without touching a frame", function()
        expect(H.SuuUI.UIRoot:GetLayerStrata("window")).eq("HIGH")
        expect(H.SuuUI.UIRoot:GetLayerStrata("dialog")).eq("DIALOG")
        expect(H.SuuUI.UIRoot:GetLayerStrata(nil)).eq("MEDIUM")
        expect(H.SuuUI.UIRoot:GetLayerStrata("nowhere")).isNil()
    end)

    it("puts the root itself on the normal layer so plain children inherit it", function()
        local root = H.SuuUI.UIRoot:GetRoot()
        expect(root:GetFrameStrata()).eq("MEDIUM")
        local child = H.env.CreateFrame("Frame", nil, H.SuuUI.UIRoot:GetRootContainer():GetFrame())
        expect(child:GetFrameStrata()).eq("MEDIUM")
    end)

    it("orders the layers so each rung covers the one below", function()
        local frames = {}
        for _, layer in ipairs({ "background", "normal", "window", "dialog", "tooltip" }) do
            local f = H.env.CreateFrame("Frame", nil, H.SuuUI.UIRoot:GetRoot())
            H.SuuUI.UIRoot:SetLayer(f, layer)
            frames[#frames + 1] = f
        end
        for i = 2, #frames do
            H.expectDrawsAbove(frames[i], frames[i - 1])
        end
    end)

    describe("SetLayer", function()
        it("applies a layer's strata without positioning the frame", function()
            local f = H.env.CreateFrame("Frame", nil, H.SuuUI.UIRoot:GetRoot())
            expect(H.SuuUI.UIRoot:SetLayer(f, "window")).eq("HIGH")
            expect(f:GetFrameStrata()).eq("HIGH")
            expect(f:GetPoint()).isNil()
        end)

        it("records the layer for later reads", function()
            local f = H.env.CreateFrame("Frame", nil, H.SuuUI.UIRoot:GetRoot())
            H.SuuUI.UIRoot:SetLayer(f, "dialog")
            expect(H.SuuUI.UIRoot:GetLayer(f)).eq("dialog")
        end)

        it("defaults to the normal layer", function()
            local f = H.env.CreateFrame("Frame", nil, H.SuuUI.UIRoot:GetRoot())
            H.SuuUI.UIRoot:SetLayer(f)
            expect(f:GetFrameStrata()).eq("MEDIUM")
        end)

        it("rejects an unknown layer", function()
            local f = H.env.CreateFrame("Frame", nil, H.SuuUI.UIRoot:GetRoot())
            expect(function() H.SuuUI.UIRoot:SetLayer(f, "nowhere") end).throws("invalid layer")
        end)

        it("tags an element added through AddElement too", function()
            local f = H.env.CreateFrame("Frame", nil, H.SuuUI.UIRoot:GetRoot())
            H.SuuUI.UIRoot:AddElement(f, "dialog", { point = "CENTER", x = 0, y = 0 })
            expect(H.SuuUI.UIRoot:GetLayer(f)).eq("dialog")
        end)
    end)

    describe("RaiseAbove", function()
        it("keeps decoration on its host's layer and above it", function()
            local host = H.env.CreateFrame("Frame", nil, H.SuuUI.UIRoot:GetRoot())
            H.SuuUI.UIRoot:SetLayer(host, "normal")
            local deco = H.env.CreateFrame("Frame", nil, host)
            H.SuuUI.UIRoot:RaiseAbove(deco, host, 5)
            expect(deco:GetFrameStrata()).eq("MEDIUM")
            expect(deco:GetFrameLevel()).eq(host:GetFrameLevel() + 5)
            H.expectDrawsAbove(deco, host)
        end)

        it("does not promote decoration over a window", function()
            local host = H.env.CreateFrame("Frame", nil, H.SuuUI.UIRoot:GetRoot())
            H.SuuUI.UIRoot:SetLayer(host, "normal")
            local deco = H.env.CreateFrame("Frame", nil, host)
            H.SuuUI.UIRoot:RaiseAbove(deco, host, 5)
            local win = H.Layout:CreateWindow({ id = "spec_raise_win" })
            H.expectDrawsAbove(win:GetFrame(), deco)
        end)

        it("rises one level by default", function()
            local host = H.env.CreateFrame("Frame", nil, H.SuuUI.UIRoot:GetRoot())
            local deco = H.env.CreateFrame("Frame", nil, host)
            H.SuuUI.UIRoot:RaiseAbove(deco, host)
            expect(deco:GetFrameLevel()).eq(host:GetFrameLevel() + 1)
        end)
    end)

    it("defaults to the normal layer", function()
        local f = H.env.CreateFrame("Frame", nil, H.SuuUI.UIRoot:GetRoot())
        H.SuuUI.UIRoot:AddElement(f, nil, { point = "CENTER", x = 0, y = 0 })
        expect(f:GetFrameStrata()).eq("MEDIUM")
    end)

    it("rejects an unknown layer", function()
        local f = H.env.CreateFrame("Frame", nil, H.SuuUI.UIRoot:GetRoot())
        expect(function() H.SuuUI.UIRoot:AddElement(f, "nowhere", {}) end)
            .throws("invalid layer")
    end)

    it("requires an element", function()
        expect(function() H.SuuUI.UIRoot:AddElement(nil, "normal", {}) end)
            .throws("element required")
    end)

    it("moves an element through UpdateElementAnchor", function()
        local f = H.env.CreateFrame("Frame", nil, H.SuuUI.UIRoot:GetRoot())
        f:SetSize(50, 50)
        H.SuuUI.UIRoot:AddElement(f, "normal", { point = "TOPLEFT", x = 0, y = 0 })
        H.SuuUI.UIRoot:UpdateElementAnchor(f, { point = "TOPLEFT", x = 100, y = -200 })
        H.expectBox(f, { left = 100, top = 200 })
    end)

    it("removes an element", function()
        local f = H.env.CreateFrame("Frame", nil, H.SuuUI.UIRoot:GetRoot())
        f:SetSize(50, 50)
        H.SuuUI.UIRoot:AddElement(f, "normal", { point = "TOPLEFT", x = 0, y = 0 })
        expect(function() H.SuuUI.UIRoot:RemoveElement(f) end).notThrows()
    end)
end)

describe("Layout.Window", function()
    before_each(function() H.setup() end)

    local function window(props)
        props = props or {}
        props.id = props.id or "spec_win"
        return H.Layout:CreateWindow(props)
    end

    describe("construction", function()
        it("requires an id", function()
            expect(function() H.Layout:CreateWindow({}) end).throws("id required")
        end)

        it("defaults to 400x300", function()
            H.expectSize(window(), 400, 300)
        end)

        it("honours explicit dimensions", function()
            H.expectSize(window({ w = 800, h = 560 }), 800, 560)
        end)

        it("names the frame after its id", function()
            expect(window({ id = "settings" }):GetFrame():GetName()).eq("SuuUI_win_settings")
        end)

        it("sits on the window layer", function()
            local f = window():GetFrame()
            expect(H.SuuUI.UIRoot:GetLayer(f)).eq("window")
            expect(f:GetFrameStrata()).eq("HIGH")
        end)

        it("draws over a plugin frame parented to the root", function()
            -- How a plugin frame is mounted (UnitFrames' player frame): a plain frame on the
            -- root container, inheriting the content rung. It is nested one level deeper than
            -- the window, so a shared strata would let it cover the window.
            local plugin = H.env.CreateFrame("Frame", nil,
                H.SuuUI.UIRoot:GetRootContainer():GetFrame())
            plugin:SetSize(180, 52)
            H.expectDrawsAbove(window():GetFrame(), plugin)
        end)

        it("draws under a dialog opened from it", function()
            local win = window()
            local popup = H.env.CreateFrame("Frame", nil, H.SuuUI.UIRoot:GetRoot())
            H.SuuUI.UIRoot:AddElement(popup, "dialog", { point = "CENTER", x = 0, y = 0 })
            H.expectDrawsAbove(popup, win:GetFrame())
        end)

        it("honours an explicit layer", function()
            local f = window({ id = "spec_dialog_win", layer = "dialog" }):GetFrame()
            expect(f:GetFrameStrata()).eq("DIALOG")
        end)

        it("keeps its chrome above the window on the same layer", function()
            local win = window({ resizable = true })
            local f = win:GetFrame()
            for name, part in pairs({ close = win._closeBtn:GetFrame(), grip = win._grip }) do
                expect(part).as(name).notNil()
                expect(part:GetFrameStrata()).as(name).eq(f:GetFrameStrata())
                H.expectDrawsAbove(part, f)
            end
        end)

        it("parents itself to the UI root, not UIParent", function()
            expect(window():GetFrame():GetParent()).eq(H.SuuUI.UIRoot:GetRoot())
        end)

        it("centres itself when there is no saved position", function()
            local w = window({ w = 400, h = 300 })
            H.expectCenteredH(w:GetFrame(), H.SuuUI.UIRoot:GetRoot())
            H.expectCenteredV(w:GetFrame(), H.SuuUI.UIRoot:GetRoot())
        end)

        it("is movable and clamped to the screen", function()
            local w = window()
            expect(w:GetFrame():IsMovable()).truthy()
            expect(w:GetFrame()._clamped).truthy()
        end)

        it("registers itself so it can be looked up by id", function()
            window({ id = "lookup_me" })
            expect(H.Layout:GetWindow("lookup_me")).notNil()
        end)
    end)

    describe("chrome layout", function()
        it("puts a token-height title strip across the top, inside the border", function()
            local w = window({ w = 400, h = 300 })
            local bw = H.token("borderWidth")
            H.expectSize(w._titleStrip, 400 - bw * 2, H.controlHeight("sizeTitleBar"))
            H.expectOffset(w._titleStrip, w:GetFrame(), bw, bw)
        end)

        it("insets the chrome by the border width token", function()
            H.T:CreateUserTheme("Thick", "Modern")
            H.T:SetUserToken("Thick", "borderWidth", 4)
            H.T:SetActive("Thick")
            local bw = H.token("borderWidth")
            expect(bw).as("the theme edit landed").eq(4)

            local w = window({ w = 400, h = 300 })
            H.expectSize(w._titleStrip, 400 - bw * 2, nil)
            H.expectOffset(w._titleStrip, w:GetFrame(), bw, bw)
            H.expectSize(w:GetContentFrame(), 400 - bw * 2,
                         300 - bw * 2 - H.controlHeight("sizeTitleBar"))
            H.expectInside(w._titleStrip, w:GetFrame())
            H.expectInside(w:GetContentFrame(), w:GetFrame())
        end)

        it("gives the content area everything below the title strip", function()
            local w = window({ w = 400, h = 300 })
            local bw = H.token("borderWidth")
            local titleH = H.controlHeight("sizeTitleBar")
            H.expectSize(w:GetContentFrame(), 400 - bw * 2, 300 - bw * 2 - titleH)
            H.expectOffset(w:GetContentFrame(), w:GetFrame(), bw, bw + titleH)
        end)

        it("keeps the title strip and content from overlapping", function()
            local w = window()
            H.expectNoOverlap({ w._titleStrip, w:GetContentFrame() })
        end)

        it("shows the title text on the left of the strip", function()
            local w = window({ title = "SuuUI Settings" })
            expect(w._titleText:GetText()).eq("SuuUI Settings")
            expect(w._titleText:GetJustifyH()).eq("LEFT")
            H.expectOffset(w._titleText, w._titleStrip, 10, nil)
        end)

        it("falls back to the id as the title", function()
            expect(window({ id = "fallback" })._titleText:GetText()).eq("fallback")
        end)

        it("pins the close button to the right of the strip", function()
            local w = window({ w = 400 })
            -- The button holds a glyph, so its box is floored against the font metrics
            local size = H.controlHeight("sizeControlMd")
            H.expectSize(w._closeBtn, size, size)
            local sb, cb = H.box(w._titleStrip), H.box(w._closeBtn)
            expect(cb.right).eq(sb.right - 6)
            H.expectCenteredV(w._closeBtn, w._titleStrip)
            H.expectInside(w._closeBtn, w._titleStrip)
        end)

        it("grows the close button with the font token instead of clipping the glyph",
        function()
            local w = window({ w = 400 })
            local before = w._closeBtn:GetWidth()
            H.T:CreateUserTheme("Big", "Modern")
            H.T:SetUserToken("Big", "fontSizeMd", 24)
            H.T:SetActive("Big")

            local size = H.controlHeight("sizeControlMd")
            expect(size).as("the control height follows the font token").gt(before)
            H.expectSize(w._closeBtn, size, size)
            H.expectTextNotClipped(w._closeText)
            H.expectInside(w._closeText, w._closeBtn)
            H.expectInside(w._closeBtn, w._titleStrip)
        end)

        it("draws the close mark with a glyph the game font can render", function()
            local w = window()
            local text = w._closeText:GetText()
            expect(text).notNil()
            expect(#text).as("multi-byte glyphs are missing from FRIZQT__.TTF").eq(1)
            expect(text:match("^[\32-\126]$")).as("ASCII printable").notNil()
        end)

        it("gives the close mark a box big enough for its own font", function()
            local w = window({ w = 400 })
            H.expectTextNotClipped(w._closeText)
            local _, size = w._closeText:GetFont()
            expect(size).eq(H.token("fontSizeMd"))
            expect(w._closeText:GetWidth()).gte(H.textWidth(w._closeText:GetText(), size))
            H.expectSize(w._closeText, nil, H.lineHeight(size))
        end)

        it("centres the close mark inside the close button", function()
            local w = window({ w = 400 })
            H.expectCenteredH(w._closeText, w._closeBtn)
            H.expectCenteredV(w._closeText, w._closeBtn)
            H.expectInside(w._closeText, w._closeBtn)
        end)

        it("re-measures the close mark when the font token changes", function()
            local w = window({ w = 400 })
            H.T:CreateUserTheme("Big", "Modern")
            H.T:SetUserToken("Big", "fontSizeMd", 24)
            H.T:SetActive("Big")
            H.expectTextNotClipped(w._closeText)
            expect(w._closeText:GetWidth()).gte(H.textWidth(w._closeText:GetText(), 24))
            H.expectSize(w._closeText, nil, H.lineHeight(24))
        end)

        it("stops the drag region short of the close button", function()
            local w = window({ w = 400 })
            H.expectNoOverlap({ w._drag, w._closeBtn })
            local sb, db = H.box(w._titleStrip), H.box(w._drag)
            expect(db.right)
                .eq(sb.right - (H.controlHeight("sizeControlMd") + H.token("spaceMd")))
        end)

        it("keeps the title text clear of the close button", function()
            local w = window({ w = 400, title = "A rather long window title here" })
            H.expectNoOverlap({ w._titleText, w._closeBtn })
            -- The gutter is expressed from the close button's own size, so it still
            -- clears once a font token widens the button.
            local sb, tb = H.box(w._titleStrip), H.box(w._titleText)
            expect(sb.right - tb.right)
                .eq(H.controlHeight("sizeControlMd") + 6 + H.token("spaceMd"))
        end)

        it("re-measures the title when the font size token changes", function()
            local w = window({ w = 400, title = "SuuUI Settings" })
            local before = w._titleText:GetHeight()
            H.T:CreateUserTheme("Big", "Modern")
            H.T:SetUserToken("Big", "fontSizeMd", 32)
            H.T:SetActive("Big")

            local _, size = w._titleText:GetFont()
            expect(size).as("the title follows the font token").eq(32)
            expect(w._titleText:GetHeight()).gt(before)
            H.expectSize(w._titleText, nil, H.lineHeight(32))
            H.expectTextNotClipped(w._titleText)
            H.expectCenteredV(w._titleText, w._titleStrip)
            H.expectInside(w._titleText, w._titleStrip)
            -- The gutter is derived from the close button, so a bigger font widens both
            -- and the title still stops short of it.
            H.expectNoOverlap({ w._titleText, w._closeBtn })
            local sb, tb = H.box(w._titleStrip), H.box(w._titleText)
            expect(sb.right - tb.right)
                .eq(H.controlHeight("sizeControlMd") + 6 + H.token("spaceMd"))
        end)

        it("re-measures the title when SetTitle lengthens it", function()
            local w = window({ w = 400, title = "Old" })
            w:SetTitle("A considerably longer window title")
            H.expectTextNotClipped(w._titleText)
            H.expectNoOverlap({ w._titleText, w._closeBtn })
        end)

        it("grows the title strip with the font size token", function()
            local w = window()
            local before = w._titleStrip:GetHeight()
            H.T:CreateUserTheme("Big", "Modern")
            H.T:SetUserToken("Big", "fontSizeMd", 40)
            H.T:SetActive("Big")
            expect(w._titleStrip:GetHeight()).gt(before)
            H.expectSize(w._titleStrip, nil, H.controlHeight("sizeTitleBar"))
        end)

        it("re-flows the content area when the title strip grows", function()
            local w = window({ w = 400, h = 300 })
            H.T:CreateUserTheme("Big", "Modern")
            H.T:SetUserToken("Big", "fontSizeMd", 40)
            H.T:SetActive("Big")
            H.expectSize(w:GetContentFrame(), nil, 300 - 2 - H.controlHeight("sizeTitleBar"))
            H.expectNoOverlap({ w._titleStrip, w:GetContentFrame() })
        end)

        it("re-flows the chrome when the window is resized", function()
            local w = window({ w = 400, h = 300, resizable = true })
            local bw = H.token("borderWidth")
            w:GetFrame():SetSize(600, 500)
            H.expectSize(w._titleStrip, 600 - bw * 2, nil)
            H.expectSize(w:GetContentFrame(), 600 - bw * 2,
                         500 - bw * 2 - H.controlHeight("sizeTitleBar"))
        end)
    end)

    describe("resize grip", function()
        it("adds no grip unless resizable", function()
            expect(window()._gripBox).isNil()
        end)

        it("puts the grip in the bottom-right corner when resizable", function()
            local w = window({ w = 400, h = 300, resizable = true })
            expect(w._gripBox).notNil()
            local grip = w._gripBox:GetChildren()[1]
            local size = H.token("sizeIcon")
            H.expectSize(grip, size, size)
            local wb, gb = H.box(w:GetFrame()), H.box(grip)
            expect(gb.right).eq(wb.right)
            expect(gb.bottom).eq(wb.bottom)
        end)

        it("marks the frame resizable", function()
            expect(window({ resizable = true }):GetFrame():IsResizable()).truthy()
        end)
    end)

    describe("resize bounds", function()
        local function resizable(props)
            props = props or {}
            props.resizable = true
            props.w, props.h = props.w or 400, props.h or 300
            props.minW, props.minH = props.minW or 300, props.minH or 250
            props.maxW, props.maxH = props.maxW or 900, props.maxH or 700
            local w = window(props)
            w:Show()
            return w, w._gripBox:GetChildren()[1]
        end

        it("hands the limits to the client so the drag stops at them", function()
            local w = resizable()
            local minW, minH, maxW, maxH = w:GetFrame():GetResizeBounds()
            expect(minW).eq(300)
            expect(minH).eq(250)
            expect(maxW).eq(900)
            expect(maxH).eq(700)
        end)

        it("stops a shrink drag at the minimum instead of snapping back", function()
            local w, grip = resizable()
            expect(H.dragResize(grip, -400, -400)).as("the grip takes mouse input").truthy()
            H.expectSize(w, 300, 250)
        end)

        it("stops a grow drag at the maximum", function()
            local w, grip = resizable()
            H.dragResize(grip, 5000, 5000)
            H.expectSize(w, 900, 700)
        end)

        it("resizes freely between the bounds", function()
            local w, grip = resizable()
            H.dragResize(grip, 120, 90)
            H.expectSize(w, 520, 390)
        end)

        it("re-flows the chrome to the clamped size", function()
            local w, grip = resizable()
            H.dragResize(grip, -400, -400)
            H.expectSize(w._titleStrip, 300 - 2, H.controlHeight("sizeTitleBar"))
            H.expectSize(w:GetContentFrame(), 300 - 2,
                         250 - 2 - H.controlHeight("sizeTitleBar"))
            H.expectInside(w:GetContentFrame(), w:GetFrame())
        end)

        it("defaults the bounds when none are given", function()
            local w = window({ resizable = true })
            local root = H.SuuUI.UIRoot:GetRoot()
            local minW, minH, maxW, maxH = w:GetFrame():GetResizeBounds()
            expect(minW).eq(200)
            expect(minH).eq(200)
            -- No explicit max, so the screen is the ceiling rather than a magic constant
            expect(maxW).eq(math.floor(root:GetWidth() * 0.9))
            expect(maxH).eq(math.floor(root:GetHeight() * 0.9))
        end)

        it("sets no bounds on a non-resizable window", function()
            expect(window():GetFrame():GetResizeBounds()).isNil()
        end)

        it("opens no smaller than its minimum", function()
            H.expectSize(window({ w = 100, h = 80, resizable = true,
                                  minW = 300, minH = 250 }), 300, 250)
        end)

        it("opens no larger than its maximum", function()
            H.expectSize(window({ w = 3000, h = 3000, resizable = true,
                                  maxW = 900, maxH = 700 }), 900, 700)
        end)

        it("saves the position after a resize drag", function()
            local w, grip = resizable({ id = "resized" })
            H.dragResize(grip, -400, -400)
            expect(H.env.SuuUIConfig.windows["resized"]).notNil()
        end)
    end)

    describe("visibility", function()
        it("fades in on Show", function()
            local w = window()
            w:Show()
            expect(w:IsShown()).truthy()
            H.runAnimations()
            expect(w:GetFrame():GetAlpha()).eq(1)
        end)

        it("fades out then hides", function()
            local w = window()
            w:Show()
            H.runAnimations()
            w:Hide()
            H.runAnimations()
            expect(w:IsShown()).falsy()
        end)

        it("toggles both ways", function()
            local w = window()
            w:Toggle()
            expect(w:IsShown()).truthy()
            w:Toggle()
            H.runAnimations()
            expect(w:IsShown()).falsy()
        end)

        it("emits VISIBILITY_CHANGED", function()
            local w = window()
            local spy = H.signalSpy(w, H.S.SIGNALS.VISIBILITY_CHANGED)
            w:Show()
            w:Hide()
            expect(spy.count).eq(2)
        end)

        it("closes when the close button is clicked", function()
            local w = window()
            w:Show()
            H.runAnimations()
            expect(H.click(w._closeBtn)).as("the close button takes mouse input").truthy()
            H.runAnimations()
            expect(w:IsShown()).falsy()
        end)

        it("drives the close through the button's CLICKED signal", function()
            local w = window()
            w:Show()
            H.runAnimations()
            local spy = H.signalSpy(w._closeBtn, H.S.SIGNALS.CLICKED)
            H.click(w._closeBtn)
            expect(spy.count).eq(1)
            expect(spy:arg(1)).eq("LeftButton")
            H.runAnimations()
            expect(w:IsShown()).falsy()
        end)

        it("cannot be closed while hidden", function()
            local w = window()
            expect(H.click(w._closeBtn)).as("hidden chrome takes no input").falsy()
        end)
    end)

    describe("position persistence", function()
        it("writes the position to per-character config", function()
            local w = window({ id = "persist_me" })
            w:SavePosition()
            local saved = H.env.SuuUIConfig.windows["persist_me"]
            expect(saved).notNil()
            expect(saved.x).eq(w:GetFrame():GetLeft())
            expect(saved.y).eq(w:GetFrame():GetTop() - H.state.screenHeight)
        end)

        it("saves after a drag ends", function()
            local w = window({ id = "dragged" })
            w:Show()
            expect(H.mouseDown(w._drag)).as("the drag strip takes mouse input").truthy()
            H.mouseUp(w._drag)
            expect(H.env.SuuUIConfig.windows["dragged"]).notNil()
        end)

        it("cannot be dragged while hidden", function()
            local w = window({ id = "hidden_drag" })
            expect(w:IsShown()).as("windows are built hidden").falsy()
            expect(H.mouseDown(w._drag)).falsy()
        end)

        it("keeps the root anchor in step with the saved position", function()
            local w = window({ id = "anchored" })
            local before = H.box(w:GetFrame())
            w:SavePosition()
            H.SuuUI.UIRoot:GetRoot():SetSize(H.UIParent:GetWidth(), H.UIParent:GetHeight())
            H.expectBox(w:GetFrame(), { left = before.left, top = before.top })
        end)
    end)

    describe("centered option", function()
        it("centres the window even when a saved position exists", function()
            H.env.SuuUIConfig = { windows = { centered_win = { x = 50, y = -50 } } }
            local w = window({ id = "centered_win", w = 400, h = 300, centered = true })
            H.expectCenteredH(w:GetFrame(), H.SuuUI.UIRoot:GetRoot())
            H.expectCenteredV(w:GetFrame(), H.SuuUI.UIRoot:GetRoot())
        end)

        it("re-centres on every open, so a drag does not stick", function()
            local w = window({ id = "recentre", w = 400, h = 300, centered = true })
            w:Show()
            local centre = H.box(w:GetFrame())

            -- Move it the way the client does, behind the layout's back
            w:GetFrame():SetPoint("TOPLEFT", H.SuuUI.UIRoot:GetRoot(), "TOPLEFT", 12, -12)
            expect(H.box(w:GetFrame()).left).as("the move landed").eq(12)

            w:Hide()
            w:Show()
            H.expectBox(w:GetFrame(), { left = centre.left, top = centre.top })
        end)

        it("does not save position after a drag", function()
            local w = window({ id = "centered_drag", centered = true })
            w:Show()
            expect(H.mouseDown(w._drag)).as("the drag strip takes mouse input").truthy()
            expect(H.mouseUp(w._drag)).as("the release is delivered").truthy()
            local saved = H.env.SuuUIConfig and H.env.SuuUIConfig.windows
                          and H.env.SuuUIConfig.windows["centered_drag"]
            expect(saved).as("no position saved for a centered window").falsy()
        end)

        it("does not save position after a resize drag", function()
            local w = window({ id = "centered_resize", w = 400, h = 300,
                               centered = true, resizable = true })
            w:Show()
            local grip = w._gripBox:GetChildren()[1]
            expect(grip).as("the resize grip exists").notNil()
            expect(H.dragResize(grip, -80, -60)).as("the resize drag ran").truthy()
            expect(w:GetFrame():GetWidth()).as("the window actually resized").eq(320)
            local saved = H.env.SuuUIConfig and H.env.SuuUIConfig.windows
                          and H.env.SuuUIConfig.windows["centered_resize"]
            expect(saved).as("no position saved for a centered window").falsy()
        end)

        it("still saves position for a window that is not centered", function()
            local w = window({ id = "not_centered" })
            w:Show()
            expect(H.mouseDown(w._drag)).truthy()
            H.mouseUp(w._drag)
            expect(H.env.SuuUIConfig.windows["not_centered"]).notNil()
        end)
    end)

    describe("screen fit", function()
        local function rootSize()
            local root = H.SuuUI.UIRoot:GetRoot()
            return root:GetWidth(), root:GetHeight()
        end

        it("caps a request that is taller than the screen", function()
            local _, rh = rootSize()
            local w = window({ w = 400, h = rh + 200 })
            expect(w:GetFrame():GetHeight()).as("height capped below the root").lt(rh)
        end)

        it("caps a request that is wider than the screen", function()
            local rw = rootSize()
            local w = window({ w = rw + 200, h = 300 })
            expect(w:GetFrame():GetWidth()).as("width capped below the root").lt(rw)
        end)

        it("leaves a request that already fits alone", function()
            H.expectSize(window({ w = 400, h = 300 }), 400, 300)
        end)

        it("caps a resizable window and its resize bounds together", function()
            local rw, rh = rootSize()
            local w = window({ w = rw + 500, h = rh + 500, resizable = true })
            local _, _, maxW, maxH = w:GetFrame():GetResizeBounds()
            expect(maxW).lt(rw)
            expect(maxH).lt(rh)
            H.expectSize(w, maxW, maxH)
        end)

        it("honours an explicit max over the screen cap", function()
            H.expectSize(window({ w = 3000, h = 3000, resizable = true,
                                  maxW = 900, maxH = 700 }), 900, 700)
        end)

        it("never caps below the declared minimum", function()
            local _, rh = rootSize()
            local w = window({ w = 400, h = rh + 500, resizable = true, minH = rh })
            expect(w:GetFrame():GetHeight()).as("the minimum wins").eq(rh)
        end)
    end)

    describe("content container", function()
        it("memoises the content container", function()
            local w = window()
            local box = w:GetContentContainer({ layout = "flow" })
            expect(w:GetContentContainer()).eq(box)
            expect(box:GetFrame()).eq(w:GetContentFrame())
        end)

        it("lays children out inside the content area", function()
            local w = window({ w = 400, h = 300 })
            local box = w:GetContentContainer({ layout = "flow", dir = "vertical", gap = 4 })
            local rows = {}
            for i = 1, 3 do
                rows[i] = H.C.Frame({ w = 10, h = 30 }, box:GetFrame())
                box:Add(rows[i], { width = "fill", height = 30 })
            end
            H.expectStackedVertically(rows, 4)
            for _, row in ipairs(rows) do H.expectInside(row, w:GetContentFrame()) end
        end)
    end)

    describe("theming", function()
        it("uses the base surface and border tokens", function()
            local w = window()
            H.expectTokenColor(H.backdropColor(w:GetFrame()), "colorBg")
            H.expectTokenColor(H.borderColor(w:GetFrame()), "colorBorder")
        end)

        it("paints the title bar with the alt surface", function()
            local w = window()
            H.expectTokenColor(H.backdropColor(w._titleStrip), "colorBgAlt")
        end)

        it("uses the medium font for the title", function()
            local w = window()
            local _, size = w._titleText:GetFont()
            expect(size).eq(H.token("fontSizeMd"))
        end)

        it("changes the title with SetTitle", function()
            local w = window({ title = "Old" })
            w:SetTitle("New")
            expect(w._titleText:GetText()).eq("New")
        end)
    end)
end)

describe("Settings window", function()
    before_each(function() H.setup() end)

    it("registers the /suuui slash command", function()
        expect(H.env.SLASH_SUUUI1).eq("/suuui")
        expect(type(H.env.SlashCmdList["SUUUI"])).eq("function")
    end)

    it("builds the window lazily on first use", function()
        expect(H.Layout:GetWindow("settings")).isNil()
        H.env.SlashCmdList["SUUUI"]()
        expect(H.Layout:GetWindow("settings")).notNil()
    end)

    it("opens centred", function()
        H.env.SlashCmdList["SUUUI"]()
        local win = H.Layout:GetWindow("settings")
        H.expectCenteredH(win:GetFrame(), H.SuuUI.UIRoot:GetRoot())
        H.expectCenteredV(win:GetFrame(), H.SuuUI.UIRoot:GetRoot())
    end)

    it("re-opens centred after being dragged away", function()
        H.env.SlashCmdList["SUUUI"]()
        local win = H.Layout:GetWindow("settings")
        local centre = H.box(win:GetFrame())

        win:GetFrame():SetPoint("TOPLEFT", H.SuuUI.UIRoot:GetRoot(), "TOPLEFT", 5, -5)
        expect(H.box(win:GetFrame()).left).as("the drag landed").eq(5)

        H.env.SlashCmdList["SUUUI"]()   -- close
        H.runAnimations()
        H.env.SlashCmdList["SUUUI"]()   -- open again
        H.expectBox(win:GetFrame(), { left = centre.left, top = centre.top })
    end)

    it("fits on screen at every supported resolution", function()
        for _, res in ipairs({ { 1366, 768 }, { 1280, 800 }, { 1440, 900 },
                              { 1920, 1080 }, { 2560, 1440 }, { 3840, 2160 } }) do
            H.setup({ physicalWidth = res[1], physicalHeight = res[2] })
            H.env.SlashCmdList["SUUUI"]()
            local f = H.Layout:GetWindow("settings"):GetFrame()
            local root = H.SuuUI.UIRoot:GetRoot()
            local label = res[1] .. "x" .. res[2]
            expect(f:GetWidth()).as(label .. " width fits").lte(root:GetWidth())
            expect(f:GetHeight()).as(label .. " height fits").lte(root:GetHeight())
        end
    end)

    it("is bigger than the pre-scaling 780x520 on a 1080p panel", function()
        H.setup({ physicalWidth = 1920, physicalHeight = 1080 })
        H.env.SlashCmdList["SUUUI"]()
        local f = H.Layout:GetWindow("settings"):GetFrame()
        expect(f:GetWidth()).as("wider than the old default").gt(780)
        expect(f:GetHeight()).as("taller than the old default").gt(520)
    end)

    it("toggles the window on repeated invocations", function()
        H.env.SlashCmdList["SUUUI"]()
        local win = H.Layout:GetWindow("settings")
        expect(win:IsShown()).truthy()
        H.env.SlashCmdList["SUUUI"]()
        H.runAnimations()
        expect(win:IsShown()).falsy()
    end)

    it("builds the nav with the core pages first", function()
        H.env.SlashCmdList["SUUUI"]()
        local win = H.Layout:GetWindow("settings")
        local labels = {}
        local function walk(frame)
            for _, child in ipairs(frame._childFrames) do
                for _, region in ipairs(child._regions) do
                    if region._kind == "FontString" and region:GetText() ~= "" then
                        labels[region:GetText()] = true
                    end
                end
                walk(child)
            end
        end
        walk(win:GetFrame())
        expect(labels["Theme"]).truthy()
        expect(labels["Profiles"]).truthy()
    end)

    it("keeps the settings page inside the window content area", function()
        H.env.SlashCmdList["SUUUI"]()
        local win = H.Layout:GetWindow("settings")
        local content = win:GetContentFrame()
        for _, child in ipairs(content._childFrames) do
            H.expectInside(child, content)
        end
    end)

    it("places a minimap launcher in the corner of the minimap", function()
        local size = H.token("sizeControlSm")
        local launcher
        for _, child in ipairs(H.Minimap._childFrames) do
            if math.abs(child:GetWidth() - size) < 0.5 then launcher = child end
        end
        expect(launcher).as("a token-sized button on the minimap").notNil()
        local mb, lb = H.box(H.Minimap), H.box(launcher)
        expect(lb.right).eq(mb.right - 2)
        expect(lb.top).eq(mb.top + 2)
    end)

    it("opens the settings window from the minimap launcher", function()
        local size = H.token("sizeControlSm")
        local launcher
        for _, child in ipairs(H.Minimap._childFrames) do
            if math.abs(child:GetWidth() - size) < 0.5 then launcher = child end
        end
        H.click(launcher)
        expect(H.Layout:GetWindow("settings")).notNil()
        expect(H.Layout:GetWindow("settings"):IsShown()).truthy()
    end)
end)
