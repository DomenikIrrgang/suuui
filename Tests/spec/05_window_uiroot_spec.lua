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
                                     dialog = "HIGH", tooltip = "TOOLTIP" }) do
            local f = H.env.CreateFrame("Frame", nil, H.SuuUI.UIRoot:GetRoot())
            H.SuuUI.UIRoot:AddElement(f, layer, { point = "CENTER", x = 0, y = 0 })
            expect(f:GetFrameStrata()).as(layer).eq(strata)
        end
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
            H.expectSize(w._titleStrip, 400 - 2, H.controlHeight("sizeTitleBar"))
            H.expectOffset(w._titleStrip, w:GetFrame(), 1, 1)
        end)

        it("gives the content area everything below the title strip", function()
            local w = window({ w = 400, h = 300 })
            local titleH = H.controlHeight("sizeTitleBar")
            H.expectSize(w:GetContentFrame(), 400 - 2, 300 - 2 - titleH)
            H.expectOffset(w:GetContentFrame(), w:GetFrame(), 1, 1 + titleH)
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
            local size = H.token("sizeControlMd")
            H.expectSize(w._closeBtn, size, size)
            local sb, cb = H.box(w._titleStrip), H.box(w._closeBtn)
            expect(cb.right).eq(sb.right - 6)
            H.expectCenteredV(w._closeBtn, w._titleStrip)
        end)

        it("stops the drag region short of the close button", function()
            local w = window({ w = 400 })
            H.expectNoOverlap({ w._drag, w._closeBtn })
            local sb, db = H.box(w._titleStrip), H.box(w._drag)
            expect(db.right).eq(sb.right - (H.token("sizeControlMd") + 12))
        end)

        it("keeps the title text clear of the close button", function()
            local w = window({ w = 400, title = "A rather long window title here" })
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
            w:GetFrame():SetSize(600, 500)
            H.expectSize(w._titleStrip, 598, nil)
            H.expectSize(w:GetContentFrame(), 598, 500 - 2 - H.controlHeight("sizeTitleBar"))
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
            H.click(w._closeBtn)
            H.runAnimations()
            expect(w:IsShown()).falsy()
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
            H.expectTokenColor({ w._titleBar:GetColorTexture() }, "colorBgAlt")
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
