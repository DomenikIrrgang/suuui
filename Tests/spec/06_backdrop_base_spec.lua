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

describe("Backdrop.Panel", function()
    local host, f, p

    -- A rounded rectangle is seven pieces per layer: four r x r corners, a strip spanning
    -- the gap between them along the top and the bottom, and a band filling the full width
    -- in between. Each corner's mask is 2r square on the SAME outer corner, so the corner
    -- shows a true quarter circle -- Pill's cap technique with the radius no longer tied to
    -- the height.
    local function build(w, h, opts)
        f = H.env.CreateFrame("Frame", nil, host)
        f:SetSize(w, h)
        f:SetPoint("TOPLEFT", host, "TOPLEFT", 0, 0)
        p = H.SuuUI.Backdrop.Panel(f, opts or { bg = "colorBgAlt", border = "colorBorder" })
        return p
    end

    -- Inside + no overlap + exactly the frame's own area means the seven pieces TILE the
    -- box: no seam from an overlap, and no hairline gap showing whatever sits behind.
    -- 4r^2 + 2r(w-2r) + w(h-2r) reduces to w*h for every r, so this holds at any radius.
    local function expectTiles(layer, w, h)
        local area = 0
        for _, tex in ipairs(layer.texes) do
            H.expectInside(tex, f)
            local b = H.box(tex)
            area = area + b.width * b.height
        end
        H.expectNoOverlap(layer.texes)
        expect(area).as("the seven pieces sum to the area they cover").eq(w * h)
    end

    -- Each corner's mask must be 2r square AND share the piece's OUTER corner. Size alone is
    -- not enough: a correctly-sized mask offset from that corner shows a slice that is not
    -- centred on the circle's centre, so the corner is not circular either.
    local function expectQuarterCircles(layer, r)
        local outer = {
            TL = { "left", "top" },    TR = { "right", "top" },
            BL = { "left", "bottom" }, BR = { "right", "bottom" },
        }
        for _, key in ipairs({ "TL", "TR", "BL", "BR" }) do
            local tex = layer[key]
            local m = tex:GetMaskTextures()[1]
            expect(m).as(key .. " is masked").notNil()
            -- 2r square, so the r x r piece covers one QUARTER of it. Sized to the piece's
            -- own box instead, the mask would be a circle of radius r/2 and the corner would
            -- not be round at all -- the trap Pill's caps document.
            H.expectSize(m, r * 2, r * 2)
            for _, edge in ipairs(outer[key]) do
                expect(H.box(m)[edge])
                    .as(key .. " mask shares the piece's " .. edge .. " edge")
                    .eq(H.box(tex)[edge])
            end
        end
    end

    before_each(function()
        H.setup()
        host = H.parent(300, 200)
    end)

    it("returns the same handle shape as Pill", function()
        build(34, 34)
        for _, name in ipairs({ "SetBg", "SetBorder", "Refresh", "Destroy" }) do
            expect(p[name]).as(name).notNil()
        end
    end)

    describe("ring geometry", function()
        it("rounds each corner with an r x r piece from the borderRadius token", function()
            build(34, 34)
            local r = H.token("borderRadius")
            expect(r).as("the token is wired, not nil").gt(0)
            for _, key in ipairs({ "TL", "TR", "BL", "BR" }) do
                H.expectSize(p._ring[key], r, r)
            end
            local fb = H.box(f)
            expect(H.box(p._ring.TL).left).eq(fb.left)
            expect(H.box(p._ring.TL).top).eq(fb.top)
            expect(H.box(p._ring.BR).right).eq(fb.right)
            expect(H.box(p._ring.BR).bottom).eq(fb.bottom)
        end)

        it("masks each corner with a 2r circle on its own outer corner, not a stretched one", function()
            build(34, 34)
            local r, fb = H.token("borderRadius"), H.box(f)
            expectQuarterCircles(p._ring, r)
            -- The ring spans the full box, so its corner masks sit on the frame's own corners.
            expect(H.box(p._ring.TL:GetMaskTextures()[1]).left).eq(fb.left)
            expect(H.box(p._ring.BR:GetMaskTextures()[1]).bottom).eq(fb.bottom)
        end)

        it("meets every ring piece edge to edge, never overlapping", function()
            build(34, 34)
            local r, fb = H.token("borderRadius"), H.box(f)
            local tl, t, tr = H.box(p._ring.TL), H.box(p._ring.T), H.box(p._ring.TR)
            expect(t.left).as("top strip starts where the TL corner ends").eq(tl.right)
            expect(t.right).as("top strip ends where the TR corner starts").eq(tr.left)
            expect(t.left - fb.left).eq(r)
            local mb = H.box(p._ring.M)
            expect(mb.top).as("the band starts where the top row ends").eq(tl.bottom)
            expect(mb.bottom).as("the band ends where the bottom row starts")
                .eq(H.box(p._ring.BL).top)
            expect(mb.left).as("the band spans the full width").eq(fb.left)
            expect(mb.right).eq(fb.right)
            -- Overlap is invisible for an opaque colour and blends against itself along every
            -- join for a translucent one, which every surface token here is.
            expectTiles(p._ring, 34, 34)
        end)
    end)

    describe("fill geometry", function()
        it("insets the fill by the borderWidth token and rounds it concentrically", function()
            build(34, 34)
            local bw, r, fb = H.token("borderWidth"), H.token("borderRadius"), H.box(f)
            expect(H.box(p._fill.TL).left).eq(fb.left + bw)
            expect(H.box(p._fill.TL).top).eq(fb.top + bw)
            expect(H.box(p._fill.BR).right).eq(fb.right - bw)
            -- Concentric: r - bw, so the ring stays bw thick all the way round a corner
            -- instead of pinching at 45 degrees.
            H.expectSize(p._fill.TL, r - bw, r - bw)
            -- The fill's masks must be pinned to the INSET corner, not the frame's. Asserting
            -- only the mask's size let a mutation that dropped the inset survive: the slice
            -- showing is then off-centre from the circle, so the corner is not round.
            expectQuarterCircles(p._fill, r - bw)
            expect(H.box(p._fill.TL:GetMaskTextures()[1]).left).eq(fb.left + bw)
            expectTiles(p._fill, 34 - bw * 2, 34 - bw * 2)
        end)

        it("covers the whole box when inset is 0", function()
            build(34, 34, { bg = "colorBgAlt", border = false, inset = 0 })
            local r = H.token("borderRadius")
            H.expectSize(p._fill.TL, r, r)
            expect(H.box(p._fill.TL).left).eq(H.box(f).left)
            expectTiles(p._fill, 34, 34)
        end)

        it("draws the fill above the ring", function()
            build(34, 34)
            expect(p._ring.M:GetDrawLayer()).eq("BACKGROUND")
            expect(p._fill.M:GetDrawLayer()).eq("BORDER")
        end)
    end)

    describe("the radius clamp", function()
        it("clamps to half the smaller dimension on a frame too small for the radius", function()
            build(34, 10, { bg = "colorBgAlt", border = "colorBorder", radius = 8 })
            -- Half the smaller dimension. Any larger and the corner art would be taller than
            -- the frame it is rounding, and the top and bottom corners would overlap.
            H.expectSize(p._ring.TL, 5, 5)
            H.expectSize(p._ring.TL:GetMaskTextures()[1], 10, 10)
            expectTiles(p._ring, 34, 10)
        end)

        it("degrades to a disc rather than corner art larger than the frame", function()
            build(8, 8, { bg = "colorBgAlt", border = "colorBorder", radius = 12 })
            -- At the clamp the four corners meet: the strips and the band are zero-sized and
            -- the four quarter circles are the whole surface.
            H.expectSize(p._ring.TL, 4, 4)
            expect(p._ring.T:GetWidth()).as("no flat run left between the corners").eq(0)
            expect(p._ring.M:GetHeight()).eq(0)
            expectTiles(p._ring, 8, 8)
        end)

        it("takes a radius of 0 as square corners", function()
            build(34, 34, { bg = "colorBgAlt", border = "colorBorder", radius = 0 })
            H.expectSize(p._ring.TL, 0, 0)
            H.expectBox(p._ring.M, H.box(f))
            expectTiles(p._ring, 34, 34)
        end)
    end)

    describe("colour", function()
        it("tints all seven fill pieces with one SetBg", function()
            build(34, 34)
            p:SetBg("colorAccent")
            for i, tex in ipairs(p._fill.texes) do
                H.expectTokenColor(H.vertexColor(tex), "colorAccent")
                expect(tex:GetColorTexture())
                    .as("fill piece " .. i .. " is tinted, never recoloured").isNil()
            end
        end)

        it("tints all seven ring pieces with one SetBorder", function()
            build(34, 34)
            for i, tex in ipairs(p._ring.texes) do
                H.expectTokenColor(H.vertexColor(tex), "colorBorder")
                expect(tex:GetColorTexture()).as("ring piece " .. i).isNil()
            end
        end)

        it("recolours without rebuilding the pieces or losing the masks", function()
            build(34, 34)
            local before = p._fill.TL
            p:SetBg("colorAccent")
            p:SetBorder("colorAccentHover")
            expect(p._fill.TL).as("the same texture, not a fresh one").eq(before)
            -- SetColorTexture would REPLACE the texture and take the mask with it, which is a
            -- silently square surface rather than a visible error.
            for _, key in ipairs({ "TL", "TR", "BL", "BR" }) do
                expect(p._fill[key]:GetMaskTextures()).as("fill " .. key .. " still masked").len(1)
                expect(p._ring[key]:GetMaskTextures()).as("ring " .. key .. " still masked").len(1)
            end
            H.expectTokenColor(H.vertexColor(p._fill.M), "colorAccent")
            H.expectTokenColor(H.vertexColor(p._ring.M), "colorAccentHover")
        end)

        it("passes a literal colour through and accepts false as transparent", function()
            build(34, 34, { bg = { 0.1, 0.2, 0.3, 0.4 }, border = false })
            expect(H.vertexColor(p._fill.M)).deepEq({ 0.1, 0.2, 0.3, 0.4 })
            expect(H.vertexColor(p._ring.M)).deepEq({ 0, 0, 0, 0 })
        end)
    end)

    describe("reacting to size and tokens", function()
        it("re-derives the geometry from a new size with no call from the owner", function()
            build(34, 34, { bg = "colorBgAlt", border = "colorBorder", radius = 8 })
            expect(p._ring.T:GetWidth()).eq(34 - 16)
            f:SetSize(60, 40)
            H.expectSize(p._ring.TL, 8, 8)
            expect(p._ring.T:GetWidth()).as("the flat run followed the new width").eq(60 - 16)
            expect(H.box(p._ring.T).left).eq(H.box(f).left + 8)
            expect(H.box(p._ring.BR).bottom).eq(H.box(f).bottom)
            expectTiles(p._ring, 60, 40)
        end)

        it("re-clamps the radius when a resize makes the frame too small for it", function()
            build(60, 40, { bg = "colorBgAlt", border = "colorBorder", radius = 8 })
            H.expectSize(p._ring.TL, 8, 8)
            f:SetSize(60, 10)
            H.expectSize(p._ring.TL, 5, 5)
            expectTiles(p._ring, 60, 10)
        end)

        it("chains onto a resize handler the frame already had", function()
            local seen = 0
            f = H.env.CreateFrame("Frame", nil, host)
            f:SetSize(34, 34)
            f:SetPoint("TOPLEFT", host, "TOPLEFT", 0, 0)
            f:SetScript("OnSizeChanged", function() seen = seen + 1 end)
            p = H.SuuUI.Backdrop.Panel(f, { bg = "colorBgAlt", border = "colorBorder", radius = 8 })
            f:SetSize(60, 40)
            expect(seen).as("the frame's own handler survived adoption").gte(1)
            expect(p._ring.T:GetWidth()).as("and the panel still re-derived").eq(60 - 16)
        end)

        it("follows the borderRadius token through Refresh", function()
            build(34, 34)
            H.expectSize(p._ring.TL, H.token("borderRadius"), H.token("borderRadius"))
            H.T:CreateUserTheme("Round", "Modern")
            H.T:SetUserToken("Round", "borderRadius", 8)
            H.T:SetActive("Round")
            expect(H.token("borderRadius")).as("the token really moved").eq(8)
            H.expectSize(p._ring.TL, 3, 3)
            p:Refresh()
            H.expectSize(p._ring.TL, 8, 8)
            H.expectSize(p._ring.TL:GetMaskTextures()[1], 16, 16)
            expect(H.box(p._ring.T).left).eq(H.box(f).left + 8)
            expectTiles(p._ring, 34, 34)
        end)

        it("follows the borderWidth token through Refresh", function()
            build(34, 34, { bg = "colorBgAlt", border = "colorBorder", radius = 8 })
            H.T:CreateUserTheme("Thick", "Modern")
            H.T:SetUserToken("Thick", "borderWidth", 3)
            H.T:SetActive("Thick")
            p:Refresh()
            expect(H.box(p._fill.TL).left).eq(H.box(f).left + 3)
            H.expectSize(p._fill.TL, 8 - 3, 8 - 3)
            expectTiles(p._fill, 34 - 6, 34 - 6)
        end)

        it("survives a frame smaller than twice the border", function()
            build(2, 1)
            H.expectInside(p._fill.M, f)
            for _, tex in ipairs(p._fill.texes) do
                expect(tex:GetWidth()).gte(0)
                expect(tex:GetHeight()).gte(0)
            end
        end)
    end)

    it("degrades to square corners when the client has no mask API", function()
        f = H.env.CreateFrame("Frame", nil, host)
        f:SetSize(34, 34)
        f:SetPoint("TOPLEFT", host, "TOPLEFT", 0, 0)
        -- The harness has no switch for this and a spec may not add one, so the method is
        -- shadowed on the instance: CircleMask guards on frame.CreateMaskTexture being
        -- truthy, which is exactly the state a client missing it produces.
        f.CreateMaskTexture = false
        p = H.SuuUI.Backdrop.Panel(f, { bg = "colorBgAlt", border = "colorBorder" })
        for _, key in ipairs({ "TL", "TR", "BL", "BR" }) do
            expect(p._ring[key]:GetMaskTextures()).as(key .. " is unmasked").len(0)
        end
        -- A worse look, not a broken widget: the pieces still tile the box, so the surface is
        -- a plain rectangle rather than nothing at all.
        expectTiles(p._ring, 34, 34)
        H.expectTokenColor(H.vertexColor(p._ring.M), "colorBorder")
        H.expectTokenColor(H.vertexColor(p._fill.M), "colorBgAlt")
        expect(p._ring.TL:GetTexture()).as("still a solid fill to tint").contains("WHITE8x8")
    end)

    it("drops its layout box on Destroy", function()
        build(34, 34)
        p:Destroy()
        expect(p._box._destroyed).as("the container is gone").truthy()
        expect(function() f:SetSize(60, 40) end)
            .as("a later resize must not reach through the dead box").notThrows()
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

    -- BUILT WITHOUT THE COLOURS, deliberately bypassing `build` above -- which fills the three in
    -- from DEFAULTS, and is precisely why nothing here caught the footgun. Stored verbatim, an
    -- omitted colour produced a fully-formed handle whose body drew NOTHING: the inventory window
    -- shipped with no surface at all and the game world showing through it, while every "did it
    -- build" assertion passed because the handle was non-nil.
    describe("colours omitted entirely", function()
        local function bare(opts)
            local fr = H.env.CreateFrame("Frame", nil, host)
            fr:SetSize(200, 40)
            fr:SetPoint("TOPLEFT", host, "TOPLEFT", 0, 0)
            return H.SuuUI.Backdrop.Glass(fr, opts or {})
        end

        it("still paints, defaulting to the glass tokens", function()
            local g = bare({ border = "colorBorder" })
            expect(g:IsGradient()).as("a gradient was built").truthy()
            local grad = g._body:GetGradient()
            expect(grad).as("the body carries a gradient").truthy()
            H.expectTokenColor(stop(grad.to), "colorGlass")
            H.expectTokenColor(stop(grad.from), "colorGlassFade")
            g:Destroy()
        end)

        it("treats false as a suppression rather than an omission", function()
            -- nil means "the usual one"; false means "none". Collapsing the two would make the
            -- default unavoidable and take `border = false` with it.
            local g = bare({ sheen = false, border = false })
            expect(g._sheen).as("suppressed").eq(false)
            expect(g._from).as("body still defaulted").eq("colorGlass")
            g:Destroy()
        end)
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

describe("the borderRadius token", function()
    -- Same reasoning as the glass tokens above: RegisterBuiltin stores whatever it is handed
    -- and GetToken answers nil in silence, so a radius added to Default alone leaves every
    -- Panel in production with square corners and no error anywhere.
    before_each(function()
        H.setup()
    end)

    for _, theme in ipairs({ "Default", "Modern" }) do
        it("resolves borderRadius in the " .. theme .. " theme", function()
            H.T:SetActive(theme)
            local v = H.token("borderRadius")
            expect(v).as(theme .. " is missing borderRadius").notNil()
            expect(type(v)).as("borderRadius is a number").eq("number")
            expect(v).as("a soft corner, not a stadium").between(1, 8)
        end)
    end

    it("is editable in the theme editor", function()
        local listed = {}
        for _, def in ipairs(H.SuuUI._ThemeEditableTokens) do listed[def.key] = def end
        expect(listed.borderRadius).as("borderRadius is editable").notNil()
        expect(listed.borderRadius.type).eq("number")
        -- 0 must be reachable: it is how the rounding is turned off UI-wide without a code
        -- change, the same escape hatch animPopScale = 1 gives the press animation.
        expect(listed.borderRadius.min).eq(0)
    end)

    it("drives Panel's corners, so an edit reaches the surface", function()
        local host = H.parent(300, 200)
        local f = H.env.CreateFrame("Frame", nil, host)
        f:SetSize(34, 34)
        f:SetPoint("TOPLEFT", host, "TOPLEFT", 0, 0)
        H.T:CreateUserTheme("Sharp", "Modern")
        H.T:SetUserToken("Sharp", "borderRadius", 6)
        H.T:SetActive("Sharp")
        local p = H.SuuUI.Backdrop.Panel(f, { bg = "colorBgAlt", border = "colorBorder" })
        H.expectSize(p._ring.TL, 6, 6)
    end)
end)
