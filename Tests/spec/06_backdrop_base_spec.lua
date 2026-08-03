local H = require("harness")

describe("Backdrop", function()
    local host, f

    local function newFrame()
        local frame = H.env.CreateFrame("Frame", nil, host, "BackdropTemplate")
        frame:SetSize(100, 40)
        return frame
    end

    before_each(function()
        H.setup()
        host = H.parent(300, 200)
        f = newFrame()
    end)

    it("resolves a token key for bg and border", function()
        H.SuuUI.Backdrop.Apply(f, { bg = "colorBgAlt", border = "colorBorder" })
        H.expectTokenColor(H.backdropColor(f), "colorBgAlt")
        H.expectTokenColor(H.borderColor(f), "colorBorder")
    end)

    it("passes a literal colour table through untouched", function()
        local want = { 0.1, 0.2, 0.3, 0.4 }
        H.SuuUI.Backdrop.Apply(f, { bg = want, border = { 0.5, 0.6, 0.7, 0.8 } })
        expect(H.backdropColor(f)).deepEq(want)
        expect(H.borderColor(f)).deepEq({ 0.5, 0.6, 0.7, 0.8 })
    end)

    it("defaults a literal colour's missing alpha to opaque", function()
        H.SuuUI.Backdrop.Apply(f, { bg = { 0.1, 0.2, 0.3 } })
        expect(H.backdropColor(f)).deepEq({ 0.1, 0.2, 0.3, 1 })
    end)

    it("treats false as fully transparent", function()
        H.SuuUI.Backdrop.Apply(f, { bg = false, border = false })
        expect(H.backdropColor(f)).deepEq({ 0, 0, 0, 0 })
        expect(H.borderColor(f)).deepEq({ 0, 0, 0, 0 })
    end)

    it("treats nil as fully transparent", function()
        H.SuuUI.Backdrop.Apply(f, {})
        expect(H.backdropColor(f)).deepEq({ 0, 0, 0, 0 })
        expect(H.borderColor(f)).deepEq({ 0, 0, 0, 0 })
    end)

    it("treats an unknown token key as fully transparent", function()
        H.SuuUI.Backdrop.Apply(f, { bg = "colorNoSuchToken" })
        expect(H.backdropColor(f)).deepEq({ 0, 0, 0, 0 })
    end)

    it("takes no opts table at all", function()
        expect(function() H.SuuUI.Backdrop.Apply(f) end).notThrows()
        expect(H.backdropColor(f)).deepEq({ 0, 0, 0, 0 })
    end)

    it("drives edgeSize and insets from the borderWidth token by default", function()
        H.SuuUI.Backdrop.Apply(f, { bg = "colorBg", border = "colorBorder" })
        local bw = H.token("borderWidth")
        local bd = f:GetBackdrop()
        expect(bd.edgeSize).eq(bw)
        expect(bd.insets).deepEq({ left = bw, right = bw, top = bw, bottom = bw })
    end)

    it("drives edgeSize and insets from an explicit borderWidth", function()
        local bw = H.token("borderWidth") + 2
        H.SuuUI.Backdrop.Apply(f, { bg = "colorBg", borderWidth = bw })
        local bd = f:GetBackdrop()
        expect(bd.edgeSize).eq(bw)
        expect(bd.insets).deepEq({ left = bw, right = bw, top = bw, bottom = bw })
    end)

    it("follows the borderWidth token when the theme changes it", function()
        H.T:CreateUserTheme("Wide", "Modern")
        H.T:SetActive("Wide")
        H.T:SetUserToken("Wide", "borderWidth", H.token("borderWidth") + 3)
        H.SuuUI.Backdrop.Apply(f, { bg = "colorBg" })
        expect(f:GetBackdrop().edgeSize).eq(H.token("borderWidth"))
    end)

    it("uses the same white texture for fill and edge", function()
        H.SuuUI.Backdrop.Apply(f, { bg = "colorBg" })
        local bd = f:GetBackdrop()
        expect(bd.bgFile).eq(bd.edgeFile)
        expect(bd.bgFile).contains("WHITE8x8")
    end)

    it("does not rebuild the backdrop from SetBg", function()
        H.SuuUI.Backdrop.Apply(f, { bg = "colorBg", border = "colorBorder" })
        local before = f:GetBackdrop()
        H.SuuUI.Backdrop.SetBg(f, "colorBgHover")
        expect(f:GetBackdrop()).as("same backdrop table, not a fresh one").eq(before)
        H.expectTokenColor(H.backdropColor(f), "colorBgHover")
        H.expectTokenColor(H.borderColor(f), "colorBorder")
    end)

    it("does not rebuild the backdrop from SetBorder", function()
        H.SuuUI.Backdrop.Apply(f, { bg = "colorBg", border = "colorBorder" })
        local before = f:GetBackdrop()
        H.SuuUI.Backdrop.SetBorder(f, "colorAccent")
        expect(f:GetBackdrop()).as("same backdrop table, not a fresh one").eq(before)
        H.expectTokenColor(H.borderColor(f), "colorAccent")
        H.expectTokenColor(H.backdropColor(f), "colorBg")
    end)

    it("accepts literals and false in SetBg and SetBorder too", function()
        H.SuuUI.Backdrop.Apply(f, { bg = "colorBg", border = "colorBorder" })
        H.SuuUI.Backdrop.SetBg(f, { 0.9, 0.8, 0.7, 0.6 })
        H.SuuUI.Backdrop.SetBorder(f, false)
        expect(H.backdropColor(f)).deepEq({ 0.9, 0.8, 0.7, 0.6 })
        expect(H.borderColor(f)).deepEq({ 0, 0, 0, 0 })
    end)
end)

describe("Theme:ApplyToFrame", function()
    local host

    before_each(function()
        H.setup()
        host = H.parent(300, 200)
    end)

    it("styles a raw frame with the surface and border tokens", function()
        local f = H.env.CreateFrame("Frame", nil, host, "BackdropTemplate")
        H.T:ApplyToFrame(f)
        H.expectTokenColor(H.backdropColor(f), "colorBg")
        H.expectTokenColor(H.borderColor(f), "colorBorder")
    end)

    it("builds the backdrop table rather than assuming one exists", function()
        local f = H.env.CreateFrame("Frame", nil, host, "BackdropTemplate")
        expect(f:GetBackdrop()).isNil()
        H.T:ApplyToFrame(f)
        expect(f:GetBackdrop().edgeSize).eq(H.token("borderWidth"))
    end)
end)

describe("Components.InstallBase", function()
    local host, widget

    local function handleOn(meta)
        return setmetatable({ _f = widget }, meta)
    end

    before_each(function()
        H.setup()
        host = H.parent(300, 200)
        widget = H.env.CreateFrame("Frame", nil, host)
        widget:SetSize(120, 30)
    end)

    it("fills in every standard accessor", function()
        local meta = {}
        meta.__index = meta
        H.C.InstallBase(meta)
        for _, name in ipairs({ "GetWidth", "GetHeight", "IsShown", "GetFrame",
                                "SetSize", "Show", "Hide" }) do
            expect(meta[name]).as(name).notNil()
        end
    end)

    it("reads geometry and visibility off the widget", function()
        local meta = {}
        meta.__index = meta
        H.C.InstallBase(meta)
        local h = handleOn(meta)
        expect(h:GetWidth()).eq(120)
        expect(h:GetHeight()).eq(30)
        expect(h:GetFrame()).eq(widget)
        expect(h:IsShown()).truthy()
        h:Hide()
        expect(h:IsShown()).falsy()
    end)

    it("resizes the widget from SetSize", function()
        local meta = {}
        meta.__index = meta
        H.C.InstallBase(meta)
        local h = handleOn(meta)
        h:SetSize(200, 50)
        expect(widget:GetWidth()).eq(200)
        expect(widget:GetHeight()).eq(50)
    end)

    it("does not emit SIZE_CHANGED from SetSize", function()
        local meta = {}
        meta.__index = meta
        H.C.InstallBase(meta)
        local h = handleOn(meta)
        local spy = H.signalSpy(h, H.S.SIGNALS.SIZE_CHANGED)
        h:SetSize(200, 50)
        expect(spy.count).as("SIZE_CHANGED comes from the frame's resize hook").eq(0)
    end)

    it("emits VISIBILITY_CHANGED from Show and Hide", function()
        local meta = {}
        meta.__index = meta
        H.C.InstallBase(meta)
        local h = handleOn(meta)
        local spy = H.signalSpy(h, H.S.SIGNALS.VISIBILITY_CHANGED)
        h:Hide()
        expect(spy.count).eq(1)
        expect(spy:arg(1)).falsy()
        h:Show()
        expect(spy.count).eq(2)
        expect(spy:arg(1)).truthy()
    end)

    it("never overwrites a method the metatable already defines", function()
        local calls = 0
        local meta = {}
        meta.__index = meta
        function meta:SetSize(w, h) calls = calls + 1 end
        function meta:Show() calls = calls + 1 end
        local mine = { SetSize = meta.SetSize, Show = meta.Show }
        H.C.InstallBase(meta)
        expect(meta.SetSize).as("custom SetSize survives").eq(mine.SetSize)
        expect(meta.Show).as("custom Show survives").eq(mine.Show)
        local h = handleOn(meta)
        h:SetSize(1, 1)
        h:Show()
        expect(calls).eq(2)
        expect(widget:GetWidth()).as("the custom SetSize ran, not the installed one").eq(120)
    end)

    it("targets a custom handle field", function()
        local meta = {}
        meta.__index = meta
        H.C.InstallBase(meta, "_fs")
        local h = setmetatable({ _fs = widget }, meta)
        expect(h:GetFrame()).eq(widget)
        expect(h:GetWidth()).eq(120)
    end)

    it("leaves Text's own emitting SetSize in place", function()
        -- Text wraps a FontString, which has no OnSizeChanged, so its SetSize is the
        -- only place SIZE_CHANGED can come from. The gap-fill rule must not clobber it.
        local t = H.C.Text({ text = "Hello" }, host)
        local spy = H.signalSpy(t, H.S.SIGNALS.SIZE_CHANGED)
        t:SetSize(80, 14)
        expect(spy.count).eq(1)
        expect(spy:arg(1)).eq(80)
        expect(spy:arg(2)).eq(14)
    end)
end)

describe("Components.Frame on the shared primitives", function()
    local host

    before_each(function()
        H.setup()
        host = H.parent(300, 200)
    end)

    it("keeps the standard accessors", function()
        local fr = H.C.Frame({ w = 120, h = 40 }, host)
        H.expectSize(fr, 120, 40)
        expect(fr:GetFrame()).notNil()
        expect(fr:IsShown()).truthy()
    end)

    it("emits VISIBILITY_CHANGED from Show and Hide", function()
        local fr = H.C.Frame({ w = 120, h = 40 }, host)
        local spy = H.signalSpy(fr, H.S.SIGNALS.VISIBILITY_CHANGED)
        fr:Hide()
        fr:Show()
        expect(spy.count).eq(2)
    end)

    it("makes a transparent variant fully transparent", function()
        local fr = H.C.Frame({ w = 120, h = 40, variant = "transparent" }, host)
        expect(H.backdropColor(fr)).deepEq({ 0, 0, 0, 0 })
    end)

    it("makes border = false fully transparent", function()
        local fr = H.C.Frame({ w = 120, h = 40, border = false }, host)
        expect(H.borderColor(fr)).deepEq({ 0, 0, 0, 0 })
    end)

    it("still derives the backdrop insets from the borderWidth token", function()
        local fr = H.C.Frame({ w = 120, h = 40 }, host)
        local bw = H.token("borderWidth")
        expect(fr:GetFrame():GetBackdrop().insets)
            .deepEq({ left = bw, right = bw, top = bw, bottom = bw })
    end)
end)

describe("Components.NavItem on the shared primitives", function()
    local host

    before_each(function()
        H.setup()
        host = H.parent(300, 200)
    end)

    it("recolours on hover without rebuilding the backdrop", function()
        local n = H.C.NavItem({ label = "General" }, host)
        local before = n:GetFrame():GetBackdrop()
        H.hover(n)
        H.expectTokenColor(H.backdropColor(n), "colorBgHover")
        expect(n:GetFrame():GetBackdrop()).as("hover reuses the backdrop table").eq(before)
    end)

    it("recolours on selection without rebuilding the backdrop", function()
        local n = H.C.NavItem({ label = "General" }, host)
        local before = n:GetFrame():GetBackdrop()
        n:SetSelected(true)
        H.expectTokenColor(H.backdropColor(n), "colorBgActive")
        H.expectTokenColor(H.textColor(n._label), "colorText")
        expect(n:GetFrame():GetBackdrop()).as("selection reuses the backdrop table").eq(before)
    end)

    it("keeps its border on the border token across state changes", function()
        local n = H.C.NavItem({ label = "General" }, host)
        H.hover(n)
        H.expectTokenColor(H.borderColor(n), "colorBorder")
        n:SetSelected(true)
        H.expectTokenColor(H.borderColor(n), "colorBorder")
    end)

    it("emits SIZE_CHANGED when the layout resizes its frame", function()
        local col = H.Layout:CreateContainer({ parent = host, layout = "flow", dir = "vertical" })
        local n = H.C.NavItem({ label = "General" }, col:GetFrame())
        local spy = H.signalSpy(n, H.S.SIGNALS.SIZE_CHANGED)
        col:Add(n, { width = "fill", height = H.token("sizeNavRow") })
        expect(spy.count).as("a layout-driven resize reports itself").gt(0)
        expect(n:GetWidth()).eq(col:GetWidth())
    end)

    it("emits SIZE_CHANGED from an explicit SetSize", function()
        local n = H.C.NavItem({ label = "General" }, host)
        local spy = H.signalSpy(n, H.S.SIGNALS.SIZE_CHANGED)
        n:SetSize(200, 40)
        expect(spy.count).eq(1)
        expect(spy:arg(1)).eq(200)
        expect(spy:arg(2)).eq(40)
    end)
end)

describe("Components.Button on the shared primitives", function()
    local host

    before_each(function()
        H.setup()
        host = H.parent(300, 200)
    end)

    it("recolours on hover without rebuilding the backdrop", function()
        local b = H.C.Button({ label = "Hover" }, host)
        local before = b:GetFrame():GetBackdrop()
        H.hover(b)
        H.expectTokenColor(H.backdropColor(b), "colorBgHover")
        H.expectTokenColor(H.borderColor(b), "colorBorderFocus")
        expect(b:GetFrame():GetBackdrop()).as("hover reuses the backdrop table").eq(before)
    end)

    it("restores on leave without rebuilding the backdrop", function()
        local b = H.C.Button({ label = "Hover" }, host)
        local before = b:GetFrame():GetBackdrop()
        H.hover(b)
        H.unhover(b)
        H.expectTokenColor(H.backdropColor(b), "colorBgAlt")
        H.expectTokenColor(H.borderColor(b), "colorBorder")
        expect(b:GetFrame():GetBackdrop()).as("leaving reuses the backdrop table").eq(before)
    end)

    it("presses and releases without rebuilding the backdrop", function()
        local b = H.C.Button({ label = "Press" }, host)
        local before = b:GetFrame():GetBackdrop()
        H.mouseDown(b)
        H.expectTokenColor(H.borderColor(b), "colorAccentHover")
        H.mouseUp(b)
        H.expectTokenColor(H.borderColor(b), "colorBorder")
        expect(b:GetFrame():GetBackdrop()).as("a press reuses the backdrop table").eq(before)
    end)

    it("keeps a variant's intent tint through a hover and back", function()
        local b = H.C.Button({ label = "V", variant = "danger" }, host)
        H.hover(b)
        H.unhover(b)
        H.expectTokenColor(H.borderColor(b), "colorDanger")
        H.expectTokenColor(H.textColor(b._label), "colorDanger")
        H.expectTokenColor(H.backdropColor(b), "colorBgAlt")
    end)

    it("derives the backdrop insets from the borderWidth token", function()
        local b = H.C.Button({ label = "Edge" }, host)
        local bw = H.token("borderWidth")
        expect(b:GetFrame():GetBackdrop().insets)
            .deepEq({ left = bw, right = bw, top = bw, bottom = bw })
    end)
end)

describe("Components.IconButton on the shared primitives", function()
    local host

    before_each(function()
        H.setup()
        host = H.parent(300, 200)
    end)

    it("restores on leave without rebuilding the backdrop", function()
        local b = H.C.IconButton({ w = 24 }, host)
        local before = b:GetFrame():GetBackdrop()
        H.hover(b)
        H.expectTokenColor(H.backdropColor(b), "colorBgHover")
        H.unhover(b)
        H.expectTokenColor(H.backdropColor(b), "colorBgAlt")
        H.expectTokenColor(H.borderColor(b), "colorBorder")
        expect(b:GetFrame():GetBackdrop()).as("leaving reuses the backdrop table").eq(before)
    end)

    it("follows the borderWidth token when the theme changes it", function()
        local b = H.C.IconButton({ w = 24 }, host)
        H.T:CreateUserTheme("Thick", "Modern")
        H.T:SetUserToken("Thick", "borderWidth", 3)
        H.T:SetActive("Thick")
        expect(b:GetFrame():GetBackdrop().edgeSize).eq(3)
    end)
end)

describe("Components.Toggle on the shared primitives", function()
    local host

    before_each(function()
        H.setup()
        host = H.parent(300, 200)
    end)

    it("recolours the track on a value change without rebuilding the backdrop", function()
        local t = H.C.Toggle({ value = false }, host)
        local before = t._track:GetBackdrop()
        H.expectTokenColor(H.backdropColor(t._track), "colorBgAlt")
        t:SetValue(true)
        H.expectTokenColor(H.backdropColor(t._track), "colorAccent")
        expect(t._track:GetBackdrop()).as("a value flip reuses the backdrop table").eq(before)
    end)

    it("borders the track with the border token", function()
        local t = H.C.Toggle({}, host)
        H.expectTokenColor(H.borderColor(t._track), "colorBorder")
    end)

    it("follows the borderWidth token on the track and the knob", function()
        local t = H.C.Toggle({}, host)
        H.T:CreateUserTheme("Thick", "Modern")
        H.T:SetUserToken("Thick", "borderWidth", 3)
        H.T:SetActive("Thick")
        expect(t._track:GetBackdrop().edgeSize).as("track edge").eq(3)
        expect(t._knob:GetBackdrop().edgeSize).as("knob edge").eq(3)
    end)

    it("keeps the knob edge matching its fill so it reads as a solid dot", function()
        local t = H.C.Toggle({}, host)
        expect(H.borderColor(t._knob)).deepEq(H.backdropColor(t._knob))
    end)
end)

describe("Components.ColorSwatch on the shared primitives", function()
    local host

    before_each(function()
        H.setup()
        host = H.parent(300, 200)
    end)

    it("insets the fill by the borderWidth token, not a pixel literal", function()
        H.T:CreateUserTheme("Thick", "Modern")
        H.T:SetUserToken("Thick", "borderWidth", 3)
        H.T:SetActive("Thick")
        local s = H.mount(H.C.ColorSwatch({ value = { 1, 0, 0, 1 }, w = 20, h = 20 }, host))
        H.expectSize(s._swatch, 14, 14)
        H.expectOffset(s._swatch, s:GetFrame(), 3, 3)
        H.expectInside(s._swatch, s:GetFrame())
    end)

    it("re-insets the fill when the borderWidth token changes", function()
        local s = H.mount(H.C.ColorSwatch({ value = { 1, 0, 0, 1 }, w = 20, h = 20 }, host))
        H.T:CreateUserTheme("Thick", "Modern")
        H.T:SetUserToken("Thick", "borderWidth", 4)
        H.T:SetActive("Thick")
        H.expectSize(s._swatch, 12, 12)
        H.expectOffset(s._swatch, s:GetFrame(), 4, 4)
    end)
end)
