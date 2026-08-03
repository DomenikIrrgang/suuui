-- Verifies the code examples printed in .kiro/steering/TESTING.md and UI_SIGNALS.md.
-- A steering example that does not work teaches the wrong thing.
local H = require("harness")

describe("steering doc examples", function()
    local host
    before_each(function()
        H.setup()
        host = H.parent(300, 200)
    end)

    it("TESTING.md: unmounted component has unresolvable inner geometry", function()
        local nav = H.C.NavItem({ label = "General" }, host)
        expect(H.box(nav._label)).as("the anti-example really does fail").isNil()
    end)

    it("TESTING.md: H.mount makes inner geometry assertable", function()
        local nav = H.mount(H.C.NavItem({ label = "General" }, host))
        H.expectCenteredV(nav._label, nav:GetFrame())
    end)

    it("TESTING.md: adding to a container also resolves it", function()
        local col = H.Layout:CreateContainer({ parent = host, layout = "flow", dir = "vertical" })
        local nav = H.C.NavItem({ label = "General" }, col:GetFrame())
        col:Add(nav, { width = "fill", height = H.token("sizeNavRow") })
        H.expectCenteredV(nav._label, nav:GetFrame())
    end)

    it("TESTING.md: the button size derivation is correct", function()
        local btn = H.C.Button({ label = "OK" }, host)
        local size = H.token("fontSizeMd")
        local padX = H.token("spaceSm") + H.token("borderWidth")
        local padY = H.token("spaceXs") + H.token("borderWidth")
        H.expectSize(btn, H.textWidth("OK", size) + 2 + padX * 2,
                          H.lineHeight(size) + padY * 2)
    end)

    it("TESTING.md: width='fill' produces the container width", function()
        local container = H.Layout:CreateContainer({ parent = host, layout = "flow",
                                                    dir = "vertical" })
        local child = H.C.Frame({ w = 10, h = 20 }, container:GetFrame())
        container:Add(child, { width = "fill", height = 20 })
        H.expectSize(child, container:GetWidth(), nil)
    end)

    it("TESTING.md: H.runAnimations settles queued animations", function()
        local f = H.parent(10, 10)
        H.SuuUI.Anim.Presets.FadeIn(f, 0.2)
        H.runAnimations()
        expect(f:GetAlpha()).eq(1)
    end)

    it("UI_SIGNALS.md: the toggle signal spy example", function()
        local tog = H.C.Toggle({}, host)
        local spy = H.signalSpy(tog, H.S.SIGNALS.VALUE_CHANGED)
        H.click(tog)
        expect(spy:arg(1)).truthy()
        expect(spy:arg(2)).falsy()
        tog:SetValue(false)
        expect(spy.count).as("setters do not emit").eq(1)
    end)

    it("TESTING.md: disabled controls stop client input and hold internally", function()
        local btn = H.C.Button({ label = "Go" }, host)
        btn:SetEnabled(false)
        expect(H.click(btn)).falsy()
        expect(function() H.forceClick(btn) end).notThrows()
    end)

    it("TESTING.md: a face swap is measurable", function()
        expect(H.textWidth("hello", 12, "Fonts/ARIALN.TTF")).lt(H.textWidth("hello", 12))
    end)

    it("plugin-authoring.md: the font dropdown preview example", function()
        local options = H.SuuUI.Fonts:Options()
        for _, opt in ipairs(options) do opt.font = H.SuuUI.Fonts:Path(opt.value) end
        local dd = H.mount(H.C.Dropdown({ options = options }, host))
        H.click(dd)
        for i, opt in ipairs(options) do
            expect((dd._rows[i]._lbl:GetFont())).as(opt.label).eq(opt.font)
        end
    end)

    it("plugin-authoring.md: resolving a stored font name to a path", function()
        H.SuuUI.Settings:Register("doc_font_plugin",
            { { key = "font", label = "Font", type = "text", default = "Arial Narrow" } })
        local path = H.SuuUI.Fonts:Path(H.SuuUI.Settings:Get("doc_font_plugin", "font"))
        expect(path).eq("Fonts/ARIALN.TTF")
    end)
end)

-- The "Anatomy of a Component" skeleton in coding-standards.md is the template every new
-- component is built from, so it is the one example that must not rot. This is a
-- transcription of it: if the recipe stops working, or a primitive it leans on changes
-- shape, these fail and the doc gets fixed with the code.
describe("coding-standards.md: Anatomy of a Component", function()
    local host

    -- Verbatim from the doc, retargeted onto the sandboxed globals the harness exposes.
    local function defineThing()
        local S = H.S
        local CompMeta = {}
        CompMeta.__index = CompMeta

        function CompMeta:_paint()
            local B = H.SuuUI.Backdrop
            B.SetBg(self._f, self._hovered and "colorBgHover" or "colorBgAlt")
            B.SetBorder(self._f, "colorBorder")
            self._labelText:SetColor(self._enabled == false and "disable" or "text")
        end

        function CompMeta:_autosize()
            if not self._autoH then return end
            local h = H.T:GetControlHeight("sizeControlMd")
            if math.abs((self._f:GetHeight() or 0) - h) <= 0.5 then return end
            self._f:SetHeight(h)
        end

        function CompMeta:ApplyTheme()
            H.SuuUI.Backdrop.Apply(self._f, { bg = "colorBgAlt", border = "colorBorder" })
            self._labelText:ApplyTheme()
            self:_paint()
            self:_autosize()
        end

        function CompMeta:SetSize(w, h)
            self._autoH = false
            self._f:SetSize(w, h)
        end

        function CompMeta:Destroy()
            S:DisconnectAll(self)
            H.SuuUI.Events:Off("SUUUI_THEME_CHANGED", self._eid)
            self._labelText:Destroy()
            self._box:Destroy()
            self._f:Hide()
        end

        H.C.InstallBase(CompMeta, "_f")

        return function(props, parent)
            local T = H.T
            local f = H.env.CreateFrame("Frame", nil, parent, "BackdropTemplate")
            f:SetSize(props.w or 160, props.h or T:GetControlHeight("sizeControlMd"))
            f:EnableMouse(true)

            local handle
            f:SetScript("OnSizeChanged", function(_, w, h)
                if not handle then return end
                S:Emit(handle, S.SIGNALS.SIZE_CHANGED, w, h)
            end)

            local box = H.Layout:CreateContainer({ host = f, layout = "stack" })

            local labelText = H.C.Text({
                text = props.label or "", size = "md", justify = "LEFT",
            }, f)
            box:Add(labelText, {
                valign = "center",
                inset  = { left = T:GetToken("spaceSm"), right = T:GetToken("spaceXs") },
            })

            local id = "thing_" .. tostring(f)
            handle = setmetatable({
                _f = f, _box = box, _eid = id, _enabled = true,
                _autoH = props.h == nil,
                _label = labelText:GetFrame(), _labelText = labelText,
            }, CompMeta)

            f:SetScript("OnMouseUp", function(_, btn)
                if handle._enabled == false then return end
                S:Emit(handle, S.SIGNALS.CLICKED, btn or "LeftButton")
            end)

            handle:ApplyTheme()
            H.SuuUI.Events:On("SUUUI_THEME_CHANGED", function() handle:ApplyTheme() end, id)
            return handle
        end
    end

    local Thing

    before_each(function()
        H.setup()
        host = H.parent(300, 200)
        Thing = defineThing()
    end)

    it("derives its height from the control token, floored by the font", function()
        local t = Thing({ label = "Hello" }, host)
        H.expectSize(t, 160, H.controlHeight("sizeControlMd"))
    end)

    it("gets the standard accessors from InstallBase", function()
        local t = Thing({ label = "Hello" }, host)
        for _, name in ipairs({ "GetWidth", "GetHeight", "IsShown", "GetFrame",
                                "SetSize", "Show", "Hide" }) do
            expect(t[name]).as(name).notNil()
        end
        expect(t:GetFrame()).notNil()
    end)

    it("paints itself from the surface and border tokens", function()
        local t = Thing({ label = "Hello" }, host)
        H.expectTokenColor(H.backdropColor(t), "colorBgAlt")
        H.expectTokenColor(H.borderColor(t), "colorBorder")
    end)

    it("recolours on hover without rebuilding the backdrop table", function()
        local t = Thing({ label = "Hello" }, host)
        local before = t:GetFrame():GetBackdrop()
        t._hovered = true
        t:_paint()
        H.expectTokenColor(H.backdropColor(t), "colorBgHover")
        expect(t:GetFrame():GetBackdrop()).as("_paint reuses the table").eq(before)
    end)

    it("emits CLICKED through the signal bus", function()
        local t = H.mount(Thing({ label = "Hello" }, host))
        local spy = H.signalSpy(t, H.S.SIGNALS.CLICKED)
        expect(H.click(t)).as("the frame takes mouse input").truthy()
        expect(spy.count).eq(1)
        expect(spy:arg(1)).eq("LeftButton")
    end)

    it("emits SIZE_CHANGED when a parent layout resizes it", function()
        local col = H.Layout:CreateContainer({ parent = host, layout = "flow",
                                               dir = "vertical" })
        local t = Thing({ label = "Hello" }, col:GetFrame())
        local spy = H.signalSpy(t, H.S.SIGNALS.SIZE_CHANGED)
        col:Add(t, { width = "fill" })
        expect(spy.count).as("a layout-driven resize reports itself").gt(0)
        expect(t:GetWidth()).eq(col:GetWidth())
    end)

    it("re-measures its label when a font token changes", function()
        local t = H.mount(Thing({ label = "Hello" }, host))
        local before = t._label:GetHeight()
        H.T:CreateUserTheme("Big", "Modern")
        H.T:SetUserToken("Big", "fontSizeMd", 28)
        H.T:SetActive("Big")

        local _, size = t._label:GetFont()
        expect(size).as("the label follows the font token").eq(28)
        expect(t._label:GetHeight()).gt(before)
        H.expectSize(t._label, nil, H.lineHeight(28))
        H.expectTextNotClipped(t._label)
    end)

    it("insets its label with the space tokens", function()
        local t = H.mount(Thing({ label = "Hello" }, host))
        H.expectOffset(t._label, t:GetFrame(), H.token("spaceSm"), nil)
        H.expectInside(t._label, t:GetFrame())
    end)

    it("re-flows on a child's re-measure with no manual Layout call", function()
        -- The recipe adds the Text *handle*, so Container:Add connects to its
        -- SIZE_CHANGED and re-runs layout itself. This is why ApplyTheme carries no
        -- box:Layout(). Pin it: the doc tells people to rely on this.
        local t = H.mount(Thing({ label = "Hello" }, host))
        local layouts = 0
        local box = t._box
        local realLayout = box.Layout
        box.Layout = function(...) layouts = layouts + 1 return realLayout(...) end

        H.T:CreateUserTheme("Big", "Modern")
        H.T:SetUserToken("Big", "fontSizeMd", 28)
        H.T:SetActive("Big")

        expect(layouts).as("the container re-laid out on its own").gt(0)
        H.expectSize(t._label, nil, H.lineHeight(28))
        -- _autosize regrew the frame, so the taller label still fits and stays centred.
        H.expectSize(t, nil, H.controlHeight("sizeControlMd"))
        H.expectCenteredV(t._label, t:GetFrame())
        H.expectInside(t._label, t:GetFrame())
        box.Layout = realLayout
    end)

    it("regrows its own height when the font token outgrows the control token", function()
        local t = H.mount(Thing({ label = "Hello" }, host))
        local before = t:GetHeight()
        H.T:CreateUserTheme("Tall", "Modern")
        H.T:SetUserToken("Tall", "fontSizeMd", 30)
        H.T:SetActive("Tall")
        expect(t:GetHeight()).as("the frame followed the font token").gt(before)
        H.expectSize(t, nil, H.controlHeight("sizeControlMd"))
        H.expectTextNotClipped(t._label)
        H.expectInside(t._label, t:GetFrame())
    end)

    it("stops deriving its height once the caller pins one", function()
        local t = H.mount(Thing({ label = "Hello", h = 40 }, host))
        H.T:CreateUserTheme("Tall2", "Modern")
        H.T:SetUserToken("Tall2", "fontSizeMd", 30)
        H.T:SetActive("Tall2")
        H.expectSize(t, nil, 40)
    end)

    it("does not re-flow on a re-measure when only the raw region was added", function()
        -- The counter-case the doc warns about: adding labelText:GetFrame() puts the
        -- connection on the frame, which never emits Text's re-measure, so a manual
        -- box:Layout() becomes the component's responsibility.
        local f = H.env.CreateFrame("Frame", nil, host, "BackdropTemplate")
        f:SetSize(160, H.controlHeight("sizeControlMd"))
        local box = H.Layout:CreateContainer({ host = f, layout = "stack" })
        local label = H.C.Text({ text = "Hello", size = "md" }, f)
        box:Add(label:GetFrame(), { valign = "center" })

        local layouts = 0
        local realLayout = box.Layout
        box.Layout = function(...) layouts = layouts + 1 return realLayout(...) end
        label:ApplyTheme()
        H.T:CreateUserTheme("Big2", "Modern")
        H.T:SetUserToken("Big2", "fontSizeMd", 28)
        H.T:SetActive("Big2")
        expect(layouts).as("the raw region hides the re-measure from the container").eq(0)
        box.Layout = realLayout
    end)

    it("drops its signals and theme subscription on Destroy", function()
        local t = Thing({ label = "Hello" }, host)
        H.signalSpy(t, H.S.SIGNALS.CLICKED)
        t:Destroy()
        expect(H.S:HasConnections(t, H.S.SIGNALS.CLICKED)).falsy()
        expect(t:IsShown()).falsy()
        expect(function() H.T:SetActive("Default") end)
            .as("a destroyed component must not restyle").notThrows()
    end)
end)
