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

describe("Backdrop.CircleMask", function()
    local host, f

    before_each(function()
        H.setup()
        host = H.parent(300, 200)
        f = H.env.CreateFrame("Frame", nil, host)
        f:SetSize(20, 20)
    end)

    it("attaches a mask to the texture", function()
        local tex = f:CreateTexture(nil, "ARTWORK")
        local mask = H.SuuUI.Backdrop.CircleMask(f, tex)
        expect(mask).notNil()
        expect(tex:GetMaskTextures()).len(1)
        expect(tex:GetMaskTextures()[1]).eq(mask)
    end)

    it("gives the texture the solid fill a mask needs in order to cut anything", function()
        local tex = f:CreateTexture(nil, "ARTWORK")
        H.SuuUI.Backdrop.CircleMask(f, tex)
        expect(tex:GetTexture()).eq("Interface\\Buttons\\WHITE8x8")
    end)

    it("wraps the mask so it cuts rather than tiles", function()
        local tex = f:CreateTexture(nil, "ARTWORK")
        local mask = H.SuuUI.Backdrop.CircleMask(f, tex)
        -- Without CLAMPTOBLACKADDITIVE on both axes the mask leaves the texture untouched,
        -- which is a silently square control rather than a visible error.
        expect(mask._wrapH).eq("CLAMPTOBLACKADDITIVE")
        expect(mask._wrapV).eq("CLAMPTOBLACKADDITIVE")
    end)
end)

describe("Backdrop.Circle", function()
    local host, f

    before_each(function()
        H.setup()
        host = H.parent(300, 200)
        f = H.env.CreateFrame("Frame", nil, host)
        f:SetSize(20, 20)
        f:SetPoint("TOPLEFT", host, "TOPLEFT", 0, 0)
    end)

    it("fills the frame with a masked texture", function()
        local c = H.SuuUI.Backdrop.Circle(f, { bg = "colorAccent" })
        H.expectSize(c._tex, 20, 20)
        expect(c._tex:GetMaskTextures()).len(1)
    end)

    it("keeps the mask exactly on the texture so the disc is a circle", function()
        local c = H.SuuUI.Backdrop.Circle(f, { bg = "colorAccent" })
        H.expectBox(c._mask, H.box(c._tex))
    end)

    it("tints rather than recolours, so the mask survives", function()
        local c = H.SuuUI.Backdrop.Circle(f, { bg = "colorAccent" })
        H.expectTokenColor(H.vertexColor(c._tex), "colorAccent")
        expect(c._tex:GetMaskTextures()).as("still masked after tinting").len(1)
    end)

    it("passes a literal colour through and accepts false as transparent", function()
        local c = H.SuuUI.Backdrop.Circle(f, { bg = { 0.1, 0.2, 0.3, 0.4 } })
        expect(H.vertexColor(c._tex)).deepEq({ 0.1, 0.2, 0.3, 0.4 })
        c:SetBg(false)
        expect(H.vertexColor(c._tex)).deepEq({ 0, 0, 0, 0 })
    end)

    it("re-stretches onto a resized frame without being told", function()
        local c = H.SuuUI.Backdrop.Circle(f, { bg = "colorAccent" })
        f:SetSize(40, 40)
        H.expectSize(c._tex, 40, 40)
        H.expectBox(c._mask, H.box(c._tex))
    end)
end)

describe("Backdrop.Pill", function()
    local host, f, p

    -- A stadium is a rectangle plus an outer half-disc at each end. The caps are half the
    -- height wide; their masks span the full height, so each cap shows the outer half of a
    -- true circle rather than a stretched ellipse.
    local function build(w, h, opts)
        f = H.env.CreateFrame("Frame", nil, host)
        f:SetSize(w, h)
        f:SetPoint("TOPLEFT", host, "TOPLEFT", 0, 0)
        p = H.SuuUI.Backdrop.Pill(f, opts or { bg = "colorBgAlt", border = "colorBorder" })
        return p
    end

    before_each(function()
        H.setup()
        host = H.parent(300, 200)
    end)

    describe("ring geometry", function()
        it("caps the ring at half the height on each end", function()
            build(60, 20)
            H.expectSize(p._edgeL, 10, 20)
            H.expectSize(p._edgeR, 10, 20)
            H.expectOffset(p._edgeL, f, 0, 0)
            expect(H.box(p._edgeR).right).eq(H.box(f).right)
        end)

        it("masks each cap with a full-height circle, not a stretched one", function()
            build(60, 20)
            local lm = p._edgeL:GetMaskTextures()[1]
            H.expectSize(lm, 20, 20)
            expect(H.box(lm).left).as("outer half of the circle shows").eq(H.box(f).left)
        end)

        it("meets the middle to the caps edge to edge, never overlapping", function()
            build(60, 20)
            local fb, lb, mb, rb = H.box(f), H.box(p._edgeL), H.box(p._edgeM), H.box(p._edgeR)
            expect(mb.left).as("middle starts where the left cap ends").eq(lb.right)
            expect(mb.right).as("middle ends where the right cap starts").eq(rb.left)
            -- Overlap is invisible for an opaque colour and blends against itself at both
            -- ends for a translucent one, which is why the caps are half-width.
            expect(mb.left - fb.left).eq(10)
        end)

        it("spans the full height with every ring piece", function()
            build(60, 20)
            for name, piece in pairs({ L = p._edgeL, M = p._edgeM, R = p._edgeR }) do
                expect(piece:GetHeight()).as("ring piece " .. name).eq(20)
            end
        end)
    end)

    describe("fill geometry", function()
        it("insets the fill by the borderWidth token on every edge", function()
            build(60, 20)
            local bw = H.token("borderWidth")
            H.expectOffset(p._fillL, f, bw, bw)
            expect(p._fillL:GetHeight()).eq(20 - bw * 2)
            expect(H.box(p._fillR).right).eq(H.box(f).right - bw)
        end)

        it("caps the fill at half its own inset height, keeping the caps square", function()
            build(60, 20)
            local hF = 20 - H.token("borderWidth") * 2
            H.expectSize(p._fillL, math.floor(hF / 2), hF)
            H.expectSize(p._fillL:GetMaskTextures()[1], hF, hF)
        end)

        it("keeps every fill piece inside the frame", function()
            build(60, 20)
            H.expectInside(p._fillL, f)
            H.expectInside(p._fillM, f)
            H.expectInside(p._fillR, f)
        end)

        it("meets the fill middle to the fill caps edge to edge", function()
            build(60, 20)
            local lb, mb, rb = H.box(p._fillL), H.box(p._fillM), H.box(p._fillR)
            expect(mb.left).eq(lb.right)
            expect(mb.right).eq(rb.left)
        end)

        it("covers the whole box when inset is 0", function()
            build(60, 20, { bg = "colorBgAlt", border = false, inset = 0 })
            local fb = H.box(f)
            expect(H.box(p._fillL).left).eq(fb.left)
            expect(p._fillL:GetHeight()).eq(20)
        end)
    end)

    describe("colour", function()
        it("tints all three fill pieces with one SetBg", function()
            build(60, 20)
            p:SetBg("colorAccent")
            H.expectTokenColor(H.vertexColor(p._fillL), "colorAccent")
            H.expectTokenColor(H.vertexColor(p._fillM), "colorAccent")
            H.expectTokenColor(H.vertexColor(p._fillR), "colorAccent")
        end)

        it("tints all three ring pieces with one SetBorder", function()
            build(60, 20)
            H.expectTokenColor(H.vertexColor(p._edgeL), "colorBorder")
            H.expectTokenColor(H.vertexColor(p._edgeM), "colorBorder")
            H.expectTokenColor(H.vertexColor(p._edgeR), "colorBorder")
        end)

        it("keeps the caps masked across a recolour", function()
            build(60, 20)
            p:SetBg("colorAccent")
            expect(p._fillL:GetMaskTextures()).len(1)
            expect(p._fillR:GetMaskTextures()).len(1)
        end)

        it("draws the fill above the ring", function()
            build(60, 20)
            expect(p._edgeM:GetDrawLayer()).eq("BACKGROUND")
            expect(p._fillM:GetDrawLayer()).eq("BORDER")
        end)
    end)

    describe("reacting to size and tokens", function()
        it("re-derives the caps from a new height with no call from the owner", function()
            build(60, 20)
            f:SetSize(80, 40)
            H.expectSize(p._edgeL, 20, 40)
            H.expectSize(p._edgeL:GetMaskTextures()[1], 40, 40)
            expect(H.box(p._edgeM).left).eq(H.box(f).left + 20)
        end)

        it("follows the borderWidth token through Refresh", function()
            build(60, 20)
            H.T:CreateUserTheme("Thick", "Modern")
            H.T:SetUserToken("Thick", "borderWidth", 3)
            H.T:SetActive("Thick")
            p:Refresh()
            expect(p._fillL:GetHeight()).eq(20 - 6)
            expect(H.box(p._fillL).left).eq(H.box(f).left + 3)
        end)

        it("chains onto a resize handler the frame already had", function()
            local seen = 0
            f = H.env.CreateFrame("Frame", nil, host)
            f:SetSize(60, 20)
            f:SetPoint("TOPLEFT", host, "TOPLEFT", 0, 0)
            f:SetScript("OnSizeChanged", function() seen = seen + 1 end)
            p = H.SuuUI.Backdrop.Pill(f, { bg = "colorBgAlt", border = "colorBorder" })
            f:SetSize(80, 40)
            expect(seen).as("the frame's own handler survived adoption").gte(1)
            H.expectSize(p._edgeL, 20, 40)
        end)

        it("survives a height smaller than twice the border", function()
            build(60, 1)
            expect(p._fillL:GetHeight()).gte(0)
            H.expectInside(p._fillM, f)
        end)
    end)
end)

describe("Components.Toggle on the shared primitives", function()
    local host

    before_each(function()
        H.setup()
        host = H.parent(300, 200)
    end)

    it("recolours the track's fill on a value change without remasking it", function()
        local t = H.C.Toggle({ value = false }, host)
        H.expectTokenColor(H.vertexColor(t._pill._fillM), "colorBgAlt")
        t:SetValue(true)
        H.expectTokenColor(H.vertexColor(t._pill._fillM), "colorAccent")
        expect(t._pill._fillL:GetMaskTextures())
            .as("a value flip must not replace the masked texture").len(1)
    end)

    it("borders the track with the border token", function()
        local t = H.C.Toggle({}, host)
        H.expectTokenColor(H.vertexColor(t._pill._edgeM), "colorBorder")
    end)

    it("follows the borderWidth token on the track", function()
        local t = H.C.Toggle({}, host)
        local h = t:GetHeight()
        H.T:CreateUserTheme("Thick", "Modern")
        H.T:SetUserToken("Thick", "borderWidth", 3)
        H.T:SetActive("Thick")
        expect(t._pill._fillL:GetHeight()).as("fill inset by the new width").eq(h - 6)
    end)

    it("draws the knob as a disc, not a square", function()
        local t = H.mount(H.C.Toggle({}, host))
        local disc = t._knobDisc
        expect(disc._tex:GetMaskTextures()).as("knob is masked round").len(1)
        H.expectBox(disc._mask, H.box(disc._tex))
        expect(H.vertexColor(disc._tex)).as("a solid white dot").deepEq({ 1, 1, 1, 1 })
    end)

    it("rounds the track ends, so no piece is a full-width rectangle", function()
        local t = H.mount(H.C.Toggle({}, host))
        local w, h = t:GetWidth(), t:GetHeight()
        -- The rounding lives in the caps: a single full-width piece would mean square ends.
        expect(t._pill._edgeM:GetWidth()).as("middle stops short of both ends").lt(w)
        expect(t._pill._edgeL:GetWidth()).eq(math.floor(h / 2))
        expect(t._pill._edgeL:GetMaskTextures()).len(1)
        expect(t._pill._edgeR:GetMaskTextures()).len(1)
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

describe("Backdrop.Glass", function()
    local host, f, gl

    local DEFAULTS = {
        from = "colorGlass", to = "colorGlassFade", sheen = "colorGlassSheen",
    }

    local function build(w, h, opts)
        f = H.env.CreateFrame("Frame", nil, host)
        f:SetSize(w, h)
        f:SetPoint("TOPLEFT", host, "TOPLEFT", 0, 0)
        local o = opts or {}
        for k, v in pairs(DEFAULTS) do
            if o[k] == nil then o[k] = v end
        end
        gl = H.SuuUI.Backdrop.Glass(f, o)
        return gl
    end

    -- A gradient endpoint as {r,g,b,a}, so it can go through expectTokenColor like any
    -- other colour. The client hands these back as CreateColor objects, not arrays.
    local function stop(c)
        local r, g, b, a = c:GetRGBA()
        return { r, g, b, a }
    end

    -- Draw order between two textures on ONE frame is the draw LAYER. H.expectDrawsAbove
    -- compares frame strata and cannot answer this -- it fails on a texture, which has no
    -- GetFrameStrata. Ranked low to high, in the client's own order.
    local LAYER_RANK = { BACKGROUND = 1, BORDER = 2, ARTWORK = 3, OVERLAY = 4, HIGHLIGHT = 5 }
    local function expectLayerAbove(above, below, note)
        -- Parenthesised: GetDrawLayer returns layer AND sublayer, and an unparenthesised
        -- call in an index position would carry both.
        local a = LAYER_RANK[(above:GetDrawLayer())]
        local b = LAYER_RANK[(below:GetDrawLayer())]
        expect(a).as(note .. ": upper layer is a known one").notNil()
        expect(b).as(note .. ": lower layer is a known one").notNil()
        expect(a).as(note).gt(b)
    end

    before_each(function()
        H.setup()
        host = H.parent(300, 200)
    end)

    describe("the gradient body", function()
        it("runs the DENSE colour along the top edge, not the bottom", function()
            build(200, 40, { inset = 0 })
            local grad = gl._body:GetGradient()
            expect(grad).as("the body took the gradient path").notNil()
            expect(grad.orientation).eq("VERTICAL")
            -- The whole point of this test. SetGradient's FIRST colour runs along the
            -- BOTTOM for a VERTICAL gradient, so the faded end is passed first and the
            -- dense end second. Swap them and the plate inverts -- still a gradient, still
            -- looks deliberate, and wrong.
            H.expectTokenColor(stop(grad.from), "colorGlassFade")
            H.expectTokenColor(stop(grad.to), "colorGlass")
        end)

        it("leaves the vertex colour white, so the plate is not tinted twice", function()
            build(200, 40, { inset = 0 })
            -- A gradient multiplies with the vertex colour. Anything but white here
            -- darkens the whole plate by a second factor.
            expect(H.vertexColor(gl._body)).deepEq({ 1, 1, 1, 1 })
            expect(gl:IsGradient()).truthy()
        end)

        it("covers the frame's whole box at inset 0", function()
            build(200, 40, { inset = 0 })
            H.expectBox(gl._body, H.box(f))
        end)

        it("insets the body by the borderWidth token when no inset is given", function()
            build(200, 40)
            local bw = H.token("borderWidth")
            H.expectOffset(gl._body, f, bw, bw)
            H.expectSize(gl._body, 200 - bw * 2, 40 - bw * 2)
        end)
    end)

    describe("without the gradient API", function()
        it("falls back to a flat fill at the midpoint alpha", function()
            H.setGradientSupported(false)
            build(200, 40, { inset = 0 })
            expect(gl:IsGradient()).as("took the fallback path").falsy()
            expect(gl._body.GetGradient).as("the client really has no gradient API").isNil()

            local mid = (H.token("opacityGlass") + H.token("opacityGlassFade")) / 2
            local c = H.vertexColor(gl._body)
            expect(c[4]).as("alpha is the midpoint of the two ends").near(mid, 0.0001)
            -- RGB comes from the dense end; both ends ref the same neutral, so this is the
            -- plate's colour either way.
            local dense = H.token("colorGlass")
            expect(c[1]).near(dense[1], 0.0001)
        end)

        it("still draws a body, rather than nothing at all", function()
            H.setGradientSupported(false)
            build(200, 40, { inset = 0 })
            H.expectBox(gl._body, H.box(f))
            expect(H.vertexColor(gl._body)[4]).as("not transparent").gt(0)
        end)

        it("is restored for the next spec by setup, not left absent", function()
            -- The leak this guards against: an absent API leaking forward turns every
            -- later gradient assertion vacuous instead of failing.
            H.setGradientSupported(false)
            H.setup()
            host = H.parent(300, 200)
            build(200, 40, { inset = 0 })
            expect(gl:IsGradient()).truthy()
        end)
    end)

    describe("the sheen", function()
        it("is one grid unit tall along the top edge", function()
            build(200, 40, { inset = 0 })
            local hair = H.SuuUI.Pixel.Line(0)
            expect(gl._sheenTex:GetHeight()).eq(hair)
            expect(H.box(gl._sheenTex).top).eq(H.box(f).top)
            expect(gl._sheenTex:GetWidth()).eq(200)
        end)

        it("is LIGHTER than the body, which is what makes it read as a lit edge", function()
            build(200, 40, { inset = 0 })
            H.expectTokenColor(H.vertexColor(gl._sheenTex), "colorGlassSheen")
            -- The semantic, not just the token: a sheen refs the lightest neutral while
            -- the body refs the darkest. Copy gray950 into it and this fails.
            local sheen, body = H.token("colorGlassSheen"), H.token("colorGlass")
            expect(sheen[1]).as("sheen is brighter than the plate").gt(body[1])
        end)

        it("draws above the body", function()
            build(200, 40, { inset = 0 })
            expectLayerAbove(gl._sheenTex, gl._body, "sheen over body")
            expect(gl._body:GetDrawLayer()).eq("BACKGROUND")
            expect(gl._sheenTex:GetDrawLayer()).eq("BORDER")
        end)

        it("sits inside the border rather than over it", function()
            build(200, 40, { border = "colorBorder" })
            local bw = H.token("borderWidth")
            expect(H.box(gl._sheenTex).top).eq(H.box(f).top + bw)
            H.expectInside(gl._sheenTex, f)
        end)
    end)

    describe("the border", function()
        it("draws four hairline edges over everything else", function()
            build(200, 40, { border = "colorBorder" })
            local bw = H.token("borderWidth")
            expect(gl._edgeT:GetHeight()).eq(bw)
            expect(gl._edgeB:GetHeight()).eq(bw)
            expect(gl._edgeL:GetWidth()).eq(bw)
            expect(gl._edgeR:GetWidth()).eq(bw)
            for _, e in ipairs(gl._edges) do
                H.expectTokenColor(H.vertexColor(e), "colorBorder")
                expectLayerAbove(e, gl._sheenTex, "border over sheen")
            end
        end)

        it("spans the full box on each side", function()
            build(200, 40, { border = "colorBorder" })
            local fb = H.box(f)
            expect(gl._edgeT:GetWidth()).eq(200)
            expect(gl._edgeB:GetWidth()).eq(200)
            expect(H.box(gl._edgeT).top).eq(fb.top)
            expect(H.box(gl._edgeB).bottom).eq(fb.bottom)
            expect(H.box(gl._edgeL).left).eq(fb.left)
            expect(H.box(gl._edgeR).right).eq(fb.right)
        end)

        it("is transparent rather than absent when no border is asked for", function()
            build(200, 40, { border = false, inset = 0 })
            -- Same contract as Apply's border = false: a real 0,0,0,0 rather than a
            -- missing texture, so there is no geometry branch to reason about.
            for _, e in ipairs(gl._edges) do
                expect(H.vertexColor(e)).deepEq({ 0, 0, 0, 0 })
            end
        end)
    end)

    describe("reacting to tokens", function()
        it("re-derives the inset when borderWidth changes", function()
            build(200, 40)
            H.T:CreateUserTheme("Thick", "Modern")
            H.T:SetUserToken("Thick", "borderWidth", 3)
            H.T:SetActive("Thick")
            gl:Refresh()
            H.expectOffset(gl._body, f, 3, 3)
            H.expectSize(gl._body, 194, 34)
        end)

        it("re-resolves the gradient after a theme change", function()
            build(200, 40, { inset = 0 })
            H.T:CreateUserTheme("Faint", "Modern")
            H.T:SetUserToken("Faint", "opacityGlass", 0.5)
            H.T:SetActive("Faint")
            gl:Refresh()
            local grad = gl._body:GetGradient()
            expect(stop(grad.to)[4]).as("dense end followed the token").near(0.5, 0.0001)
        end)

        it("keeps a colour left out of SetColors", function()
            build(200, 40, { inset = 0 })
            gl:SetColors({ sheen = "colorAccent" })
            H.expectTokenColor(H.vertexColor(gl._sheenTex), "colorAccent")
            -- from/to were not named, so the body must be untouched.
            H.expectTokenColor(stop(gl._body:GetGradient().to), "colorGlass")
        end)
    end)

    it("takes no mouse input of its own", function()
        build(200, 40, { inset = 0 })
        -- The plate spans the gaps between buttons. Enabling mouse on it would make those
        -- gaps swallow clicks meant for the world behind them.
        expect(f:IsMouseEnabled()).falsy()
    end)

    it("drops its layout box on Destroy", function()
        build(200, 40)
        gl:Destroy()
        expect(gl._box._destroyed).as("the container is gone").truthy()
    end)
end)

describe("the glass tokens", function()
    -- There is no other theme/token spec in this suite, and nothing validates that the two
    -- shipped themes declare the same keys: RegisterBuiltin stores whatever it is handed and
    -- GetToken answers nil in silence. Modern is the theme that actually loads, so a token
    -- added to Default alone is nil in production and every glass surface renders
    -- transparent with no error anywhere.
    local PRIMITIVES = { "opacityGlass", "opacityGlassFade", "opacityGlassSheen" }
    local DERIVATIONS = { "colorGlass", "colorGlassFade", "colorGlassSheen" }

    before_each(function()
        H.setup()
    end)

    for _, theme in ipairs({ "Default", "Modern" }) do
        it("resolves every glass token in the " .. theme .. " theme", function()
            H.T:SetActive(theme)
            for _, key in ipairs(PRIMITIVES) do
                local v = H.token(key)
                expect(v).as(theme .. " is missing " .. key).notNil()
                expect(type(v)).as(key .. " is a number").eq("number")
                expect(v).as(key .. " is a usable alpha").between(0, 1)
            end
            for _, key in ipairs(DERIVATIONS) do
                local c = H.token(key)
                -- A derivation whose ref is missing resolves to nil, not to an error, so
                -- this is the only place that failure becomes visible.
                expect(c).as(theme .. " is missing " .. key).notNil()
                expect(type(c)).as(key .. " resolved to a colour").eq("table")
                expect(#c).as(key .. " has four components").eq(4)
            end
        end)

        it("gives the " .. theme .. " plate a real gradient, not two equal ends", function()
            H.T:SetActive(theme)
            -- The plate's legibility is the DIFFERENCE between its ends. Equal alphas make
            -- it a flat panel, which is the look it exists to replace.
            expect(H.token("opacityGlass")).gt(H.token("opacityGlassFade"))
            expect(H.token("opacityGlassSheen")).as("a sheen, not a white line").lt(0.25)
        end)
    end

    it("drives the derivations from the primitives, so an edit cascades", function()
        H.T:CreateUserTheme("Cascade", "Modern")
        H.T:SetUserToken("Cascade", "opacityGlass", 0.42)
        H.T:SetActive("Cascade")
        expect(H.token("colorGlass")[4]).as("alpha followed the primitive").near(0.42, 0.0001)
    end)

    it("exposes the three opacities in the theme editor and none of the derivations", function()
        local listed = {}
        for _, def in ipairs(H.SuuUI._ThemeEditableTokens) do listed[def.key] = def end
        for _, key in ipairs(PRIMITIVES) do
            expect(listed[key]).as(key .. " is editable").notNil()
            expect(listed[key].type).eq("number")
        end
        -- Deliberate: the editor's colour row reads the RESOLVED value and writes back a
        -- flat literal, which would replace the { ref, alpha } cascade with a fixed colour.
        for _, key in ipairs(DERIVATIONS) do
            expect(listed[key]).as(key .. " must NOT be editable").isNil()
        end
    end)
end)
