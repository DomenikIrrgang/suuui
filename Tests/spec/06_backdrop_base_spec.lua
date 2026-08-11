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
