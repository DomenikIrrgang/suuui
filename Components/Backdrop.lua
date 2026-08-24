local type, ipairs, setmetatable, min = type, ipairs, setmetatable, math.min

local WHITE = "Interface\\Buttons\\WHITE8x8"

local M = {}

-- A colour argument is a token key, a literal {r,g,b,a}, or false/nil meaning
-- fully transparent. Several components deliberately want no bg or no border, and
-- that has to be a real 0,0,0,0 rather than "leave whatever was there".
local function resolveColor(value)
    local c = value
    if type(c) == "string" then c = SuuUI.Theme:GetToken(c) end
    if type(c) ~= "table" then return 0, 0, 0, 0 end
    return c[1] or 0, c[2] or 0, c[3] or 0, c[4] == nil and 1 or c[4]
end

--- Applies the standard bg+border backdrop, resolving theme tokens.
-- @param frame frame  must be a BackdropTemplate frame
-- @param opts table   { bg = tokenKey|color|false, border = tokenKey|color|false,
--                       borderWidth = number|nil, inset = number|nil }
--   inset: how far the background sits inside the frame. Defaults to the border width so
--          a bordered surface does not paint under its own edge. Pass 0 for a borderless
--          surface that has to cover its whole box — otherwise its background is a pixel
--          smaller on every side than the frame, and anything drawn flush to the frame
--          (a bar fill) no longer lines up with it.
function M.Apply(frame, opts)
    opts = opts or {}
    -- Snapped to the pixel grid, with the grid step as the floor. A 1-unit border spans
    -- 1.4 pixels at 1080p on the default scale, which the rasteriser resolves as a grey
    -- smear rather than a line; Line() makes it exactly one pixel and never zero.
    local bw = SuuUI.Pixel.Line(opts.borderWidth or SuuUI.Theme:GetToken("borderWidth") or 1)
    local inset = opts.inset or bw
    frame:SetBackdrop({
        bgFile   = WHITE,
        edgeFile = WHITE,
        edgeSize = bw,
        insets   = { left = inset, right = inset, top = inset, bottom = inset },
    })
    M.SetBg(frame, opts.bg)
    M.SetBorder(frame, opts.border)
end

--- Sets only the background colour, leaving the backdrop table intact.
-- @param frame frame
-- @param tokenKeyOrColor string|table|false
function M.SetBg(frame, tokenKeyOrColor)
    frame:SetBackdropColor(resolveColor(tokenKeyOrColor))
end

--- Sets only the border colour, leaving the backdrop table intact.
-- @param frame frame
-- @param tokenKeyOrColor string|table|false
function M.SetBorder(frame, tokenKeyOrColor)
    frame:SetBackdropBorderColor(resolveColor(tokenKeyOrColor))
end

--------------------------------------------------------------------------------
-- Rounded surfaces
--------------------------------------------------------------------------------
-- A backdrop cannot be rounded: its corners are the texture's corners. Anything with a
-- round edge is therefore composed from textures and cut with an alpha mask, which is
-- why these return a handle instead of painting a frame in place.

-- A round asset that ships with every Classic client, used as an alpha mask rather than
-- as art. CLAMPTOBLACKADDITIVE wrapping is required for it to cut a circle out of the
-- texture it is attached to; with the default wrap mode it leaves the texture untouched.
local CIRCLE_MASK = "Interface\\Minimap\\UI-Minimap-Background"

--- Rounds a texture into a circle by attaching a circular alpha mask.
-- Also sets the solid white fill the texture needs in order to be tinted, since a mask
-- only cuts what is already drawn.
-- @param frame frame   the frame that owns the mask region
-- @param tex texture   the texture to round
-- @return texture|nil  the mask, for the caller's container to size onto the texture.
--   nil when the client has no mask API, in which case the texture stays square rather
--   than rendering nothing — square corners are a worse look, not a broken control.
function M.CircleMask(frame, tex)
    tex:SetTexture(WHITE)
    if not (frame.CreateMaskTexture and tex.AddMaskTexture) then return nil end
    local mask = frame:CreateMaskTexture()
    mask:SetTexture(CIRCLE_MASK, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
    tex:AddMaskTexture(mask)
    return mask
end

local CircleMeta = {}
CircleMeta.__index = CircleMeta

--- Sets the disc colour.
-- @param tokenKeyOrColor string|table|false
function CircleMeta:SetBg(tokenKeyOrColor)
    self._tex:SetVertexColor(resolveColor(tokenKeyOrColor))
end

--- Drops the layout box. Textures cannot be destroyed; they go when their frame does.
function CircleMeta:Destroy()
    self._box:Destroy()
end

--- Fills a frame with a solid disc.
-- The frame must be square. A rectangular one yields an ellipse, which is exactly why a
-- pill is a separate primitive rather than a wide Circle.
-- @param frame frame  plain Frame — a disc is drawn from textures, not from a backdrop
-- @param opts table   { bg = tokenKey|color|false }
-- @return table  handle { SetBg, Destroy }
function M.Circle(frame, opts)
    opts = opts or {}
    local box = SuuUI.Layout:CreateContainer({ host = frame, layout = "stack" })
    local tex = frame:CreateTexture(nil, "ARTWORK")
    local mask = M.CircleMask(frame, tex)
    box:Add(tex)
    -- The mask is placed by the same strategy as the texture, so it tracks every resize.
    if mask then box:Add(mask) end

    local handle = setmetatable({
        _f = frame, _box = box, _tex = tex, _mask = mask,
    }, CircleMeta)
    handle:SetBg(opts.bg)
    return handle
end

local PillMeta = {}
PillMeta.__index = PillMeta

--- Sets the colour of the rounded interior.
-- @param tokenKeyOrColor string|table|false
function PillMeta:SetBg(tokenKeyOrColor)
    local r, g, b, a = resolveColor(tokenKeyOrColor)
    self._fillL:SetVertexColor(r, g, b, a)
    self._fillM:SetVertexColor(r, g, b, a)
    self._fillR:SetVertexColor(r, g, b, a)
end

--- Sets the colour of the ring around the interior.
-- @param tokenKeyOrColor string|table|false
function PillMeta:SetBorder(tokenKeyOrColor)
    local r, g, b, a = resolveColor(tokenKeyOrColor)
    self._edgeL:SetVertexColor(r, g, b, a)
    self._edgeM:SetVertexColor(r, g, b, a)
    self._edgeR:SetVertexColor(r, g, b, a)
end

-- Every piece is sized from the frame's current height, so all six are re-derived
-- together. The props tables are the ones handed to Add, so mutating them in place is
-- what the next Layout() pass reads — no allocation, and no SetChildProps per piece,
-- which would run a whole layout each time.
function PillMeta:_geom()
    local pxfloor = SuuUI.Pixel.Floor
    local h   = self._f:GetHeight() or 0
    local ins = self._inset

    -- Ring: the full box. Each cap texture is half the height wide and shows the outer
    -- half of a mask circle that spans the full height, so the caps meet the middle
    -- rectangle edge to edge instead of overlapping it. Overlap would be invisible for
    -- an opaque colour and blend against itself at both ends for a translucent one.
    local rE = pxfloor(h / 2)
    self._pEdgeL.width       = rE
    self._pEdgeR.width       = rE
    self._pEdgeLM.width      = h
    self._pEdgeRM.width      = h
    self._pEdgeM.inset.left  = rE
    self._pEdgeM.inset.right = rE

    -- Fill: the same stadium inset on every edge, which is what leaves the ring visible.
    local hF = h - ins * 2
    if hF < 0 then hF = 0 end
    local rF = pxfloor(hF / 2)
    self._pFillL.width  = rF
    self._pFillR.width  = rF
    self._pFillLM.width = hF
    self._pFillRM.width = hF
    self._pFillL.inset.left    = ins
    self._pFillLM.inset.left   = ins
    self._pFillR.inset.right   = ins
    self._pFillRM.inset.right  = ins
    self._pFillM.inset.left    = ins + rF
    self._pFillM.inset.right   = ins + rF
    for _, p in ipairs(self._vInset) do
        p.inset.top, p.inset.bottom = ins, ins
    end
end

--- Re-derives every piece from the current size and the borderWidth token.
-- Resizes are picked up on their own; call this after a theme change.
function PillMeta:Refresh()
    local bw = SuuUI.Pixel.Line(self._bwProp or SuuUI.Theme:GetToken("borderWidth") or 1)
    self._inset = self._insetProp or bw
    self:_geom()
    self._box:Layout()
end

--- Drops the layout box. Textures cannot be destroyed; they go when their frame does.
function PillMeta:Destroy()
    self._box:Destroy()
end

local function midPiece(frame, box, layer, props)
    local tex = frame:CreateTexture(nil, layer)
    tex:SetTexture(WHITE)
    box:Add(tex, props)
    return tex
end

local function capPiece(frame, box, layer, texProps, maskProps)
    local tex  = frame:CreateTexture(nil, layer)
    local mask = M.CircleMask(frame, tex)
    box:Add(tex, texProps)
    if mask then box:Add(mask, maskProps) end
    return tex
end

--- Fills a frame with a stadium: a rectangle with a fully rounded cap at each end.
-- Mirrors Apply's vocabulary, so a component swapping a square surface for a rounded one
-- changes the call and nothing else.
-- @param frame frame  plain Frame — a stadium is drawn from textures, not from a backdrop
-- @param opts table   { bg = tokenKey|color|false, border = tokenKey|color|false,
--                       borderWidth = number|nil, inset = number|nil }
--   inset: how far the fill sits inside the frame, which is the visible ring thickness.
--          Defaults to the border width, exactly as Apply's does. Pass 0 for a
--          borderless surface that has to cover its whole box.
-- @return table  handle { SetBg, SetBorder, Refresh, Destroy }
function M.Pill(frame, opts)
    opts = opts or {}
    local self = setmetatable({
        _f = frame, _bwProp = opts.borderWidth, _insetProp = opts.inset, _inset = 0,
    }, PillMeta)

    -- Cap width follows the frame height, so re-derive on resize. Registered BEFORE the
    -- host container adopts the frame: the container chains onto this handler, so its own
    -- Layout() pass applies whatever this mutated without a second pass of its own.
    local prev = frame:GetScript("OnSizeChanged")
    frame:SetScript("OnSizeChanged", function(f_, w, h)
        if prev then prev(f_, w, h) end
        self:_geom()
    end)

    local box = SuuUI.Layout:CreateContainer({ host = frame, layout = "stack" })
    self._box = box

    self._pEdgeM  = { inset = {} }
    self._pEdgeL  = { align = "start", valign = "stretch", width = 0 }
    self._pEdgeLM = { align = "start", valign = "stretch", width = 0 }
    self._pEdgeR  = { align = "end",   valign = "stretch", width = 0 }
    self._pEdgeRM = { align = "end",   valign = "stretch", width = 0 }
    self._pFillM  = { inset = {} }
    self._pFillL  = { align = "start", valign = "stretch", width = 0, inset = {} }
    self._pFillLM = { align = "start", valign = "stretch", width = 0, inset = {} }
    self._pFillR  = { align = "end",   valign = "stretch", width = 0, inset = {} }
    self._pFillRM = { align = "end",   valign = "stretch", width = 0, inset = {} }
    -- Only the fill layer is inset vertically; the ring spans the whole box.
    self._vInset = { self._pFillM, self._pFillL, self._pFillLM, self._pFillR, self._pFillRM }

    self._edgeM = midPiece(frame, box, "BACKGROUND", self._pEdgeM)
    self._edgeL = capPiece(frame, box, "BACKGROUND", self._pEdgeL, self._pEdgeLM)
    self._edgeR = capPiece(frame, box, "BACKGROUND", self._pEdgeR, self._pEdgeRM)
    self._fillM = midPiece(frame, box, "BORDER", self._pFillM)
    self._fillL = capPiece(frame, box, "BORDER", self._pFillL, self._pFillLM)
    self._fillR = capPiece(frame, box, "BORDER", self._pFillR, self._pFillRM)

    self:Refresh()
    self:SetBg(opts.bg)
    self:SetBorder(opts.border)
    return self
end

--------------------------------------------------------------------------------
-- Panel
--------------------------------------------------------------------------------
-- A rounded RECTANGLE, as opposed to Pill's stadium. Pill's radius is half its height by
-- construction, which is the wrong shape for a 34x34 cell that wants a 3-unit corner, so
-- the radius here is its own value and the flat run between the corners is what varies.

local PanelMeta = {}
PanelMeta.__index = PanelMeta

--- Sets the colour of the rounded interior.
-- @param tokenKeyOrColor string|table|false
function PanelMeta:SetBg(tokenKeyOrColor)
    local r, g, b, a = resolveColor(tokenKeyOrColor)
    -- SetVertexColor, never SetColorTexture: the latter replaces the texture and takes the
    -- corner mask with it, which is a silently square surface rather than a visible error.
    for _, tex in ipairs(self._fill.texes) do tex:SetVertexColor(r, g, b, a) end
end

--- Sets the colour of the ring around the interior.
-- @param tokenKeyOrColor string|table|false
function PanelMeta:SetBorder(tokenKeyOrColor)
    local r, g, b, a = resolveColor(tokenKeyOrColor)
    for _, tex in ipairs(self._ring.texes) do tex:SetVertexColor(r, g, b, a) end
end

-- The four corners, each named for the box edges it hugs. `h` and `v` are the inset keys
-- those edges use, so one loop places every corner with no branch per corner.
local CORNERS = {
    { key = "TL", align = "start", valign = "start", h = "left",  v = "top"    },
    { key = "TR", align = "end",   valign = "start", h = "right", v = "top"    },
    { key = "BL", align = "start", valign = "end",   h = "left",  v = "bottom" },
    { key = "BR", align = "end",   valign = "end",   h = "right", v = "bottom" },
}

-- Seven pieces on one draw layer: four square corners, a strip spanning the gap between
-- them along the top and along the bottom, and a band filling the full width in between.
-- Both layers are the same seven, so they are built by one function and differ only in
-- draw layer and in how far in from the frame's edges they sit.
local function buildLayer(frame, box, layer)
    local L = { corners = {}, texes = {} }
    for _, c in ipairs(CORNERS) do
        local p = { align = c.align, valign = c.valign, width = 0, height = 0, inset = {} }
        local m = { align = c.align, valign = c.valign, width = 0, height = 0, inset = {} }
        L[c.key] = capPiece(frame, box, layer, p, m)
        L.corners[#L.corners + 1] = { p = p, m = m, h = c.h, v = c.v }
        L.texes[#L.texes + 1] = L[c.key]
    end
    L.pT = { valign = "start", height = 0, inset = {} }
    L.pB = { valign = "end",   height = 0, inset = {} }
    L.pM = { inset = {} }
    L.T = midPiece(frame, box, layer, L.pT)
    L.B = midPiece(frame, box, layer, L.pB)
    L.M = midPiece(frame, box, layer, L.pM)
    L.texes[#L.texes + 1] = L.T
    L.texes[#L.texes + 1] = L.B
    L.texes[#L.texes + 1] = L.M
    return L
end

-- Places one layer at corner radius r, inset ins from every edge of the frame. The props
-- tables are the ones handed to Add, so mutating them in place is what the next Layout()
-- pass reads — no allocation, and no SetChildProps per piece, which would run a whole
-- layout each time.
--
-- The seven pieces TILE the box and meet EDGE TO EDGE. Overlap would be invisible for an
-- opaque colour and blend against itself along every join for a translucent one, which is
-- what a surface opacity token makes of every panel here — the same reason Pill's caps are
-- half-width rather than laid over its middle.
--
-- Each corner's mask is 2r square on the SAME outer corner as its piece, so the piece
-- shows one true quarter of a circle. A mask stretched over the piece's own r x r box
-- would be an ellipse of radius r/2 instead: exactly the trap Pill's caps document.
local function shapeLayer(L, r, ins)
    local d = r * 2
    for _, c in ipairs(L.corners) do
        c.p.width,  c.p.height  = r, r
        c.m.width,  c.m.height  = d, d
        c.p.inset[c.h], c.p.inset[c.v] = ins, ins
        c.m.inset[c.h], c.m.inset[c.v] = ins, ins
    end
    L.pT.height, L.pB.height = r, r
    L.pT.inset.top,    L.pT.inset.left, L.pT.inset.right = ins, ins + r, ins + r
    L.pB.inset.bottom, L.pB.inset.left, L.pB.inset.right = ins, ins + r, ins + r
    L.pM.inset.left, L.pM.inset.right  = ins, ins
    L.pM.inset.top,  L.pM.inset.bottom = ins + r, ins + r
end

-- A radius over half the smaller dimension would ask for corner art larger than the frame
-- it is rounding, so it is clamped there: at the clamp the corners meet and the surface
-- degrades to a pill or a disc, which is a shape rather than a defect.
local function clampRadius(r, w, h)
    local cap = SuuUI.Pixel.Floor(min(w, h) / 2)
    if r > cap then r = cap end
    if r < 0 then r = 0 end
    return r
end

-- Every piece is derived from the frame's current size, so all fourteen are re-derived
-- together.
function PanelMeta:_geom()
    local w, h = self._f:GetWidth() or 0, self._f:GetHeight() or 0
    local ins = self._inset

    -- Ring: the full box.
    shapeLayer(self._ring, clampRadius(self._radius, w, h), 0)

    -- Fill: the same shape inset on every edge, which is what leaves the ring visible.
    local wF, hF = w - ins * 2, h - ins * 2
    if wF < 0 then wF = 0 end
    if hF < 0 then hF = 0 end
    -- Concentric — the inner radius is the outer one less the ring it sits inside, so the
    -- ring keeps an even thickness round a corner instead of pinching at 45 degrees.
    shapeLayer(self._fill, clampRadius(self._radius - ins, wF, hF), ins)
end

--- Re-derives every piece from the current size, the borderWidth and borderRadius tokens.
-- Resizes are picked up on their own; call this after a theme change.
function PanelMeta:Refresh()
    local T = SuuUI.Theme
    local bw = SuuUI.Pixel.Line(self._bwProp or T:GetToken("borderWidth") or 1)
    self._inset = self._insetProp or bw
    -- Floored onto the grid: a radius half a pixel off it rounds the corner art and the
    -- strip that meets it to different edges, which shows as a notch at the join.
    self._radius = SuuUI.Pixel.Floor(self._radiusProp or T:GetToken("borderRadius") or 0)
    self:_geom()
    self._box:Layout()
end

--- Drops the layout box. Textures cannot be destroyed; they go when their frame does.
function PanelMeta:Destroy()
    self._box:Destroy()
end

--- Fills a frame with a rounded rectangle: a rectangle with a quarter-circle at each corner.
-- Mirrors Apply's vocabulary, so a component swapping a square surface for a rounded one
-- changes the call and nothing else.
-- @param frame frame  plain Frame — a rounded surface is drawn from textures, and a
--   backdrop underneath it would show its own square corners through the rounding
-- @param opts table   { bg = tokenKey|color|false, border = tokenKey|color|false,
--                       borderWidth = number|nil, inset = number|nil, radius = number|nil }
--   inset:  how far the fill sits inside the frame, which is the visible ring thickness.
--           Defaults to the border width, exactly as Apply's does. Pass 0 for a
--           borderless surface that has to cover its whole box.
--   radius: corner radius, defaulting to the borderRadius token. Clamped to half the
--           smaller dimension; 0 is square corners.
-- @return table  handle { SetBg, SetBorder, Refresh, Destroy }
function M.Panel(frame, opts)
    opts = opts or {}
    local self = setmetatable({
        _f = frame, _bwProp = opts.borderWidth, _insetProp = opts.inset,
        _radiusProp = opts.radius, _inset = 0, _radius = 0,
    }, PanelMeta)

    -- Corner size follows the frame, so re-derive on resize. Registered BEFORE the host
    -- container adopts the frame: the container chains onto this handler, so its own
    -- Layout() pass applies whatever this mutated without a second pass of its own.
    local prev = frame:GetScript("OnSizeChanged")
    frame:SetScript("OnSizeChanged", function(f_, w, h)
        if prev then prev(f_, w, h) end
        self:_geom()
    end)

    local box = SuuUI.Layout:CreateContainer({ host = frame, layout = "stack" })
    self._box = box

    self._ring = buildLayer(frame, box, "BACKGROUND")
    self._fill = buildLayer(frame, box, "BORDER")

    self:Refresh()
    self:SetBg(opts.bg)
    self:SetBorder(opts.border)
    return self
end

--------------------------------------------------------------------------------
-- Glass
--------------------------------------------------------------------------------
-- A translucent plate: a vertical gradient body, a hairline sheen along its top edge, and
-- optionally a hairline border. Those three things together are what reads as glass on
-- this client.
--
-- WoW HAS NO BLUR. There is no backdrop-filter equivalent, so frosted glass is not
-- reachable and this primitive does not approximate it — the gradient and the lit top
-- edge are the whole effect.
--
-- Composed from textures for the same reason Pill is: a backdrop paints one flat colour,
-- and the gradient is the entire point.

local GlassMeta = {}
GlassMeta.__index = GlassMeta

-- The sheen is a hairline by definition rather than a scaled border, so it takes the grid
-- quantum: Line() floors at exactly one device pixel for any value at or below it.
local function sheenHeight()
    return SuuUI.Pixel.Line(0)
end

-- Paints the body, and reports whether it got a real gradient.
--
-- The trap here is orientation: for a VERTICAL gradient the client runs the FIRST colour
-- along the BOTTOM edge — Components/ColorPicker.lua depends on exactly that to put black
-- at the bottom of its value square. A glass plate's dense edge is its TOP, so `from` is
-- passed SECOND. Swapping these silently inverts the plate, which still looks like a
-- gradient and so survives a glance.
local function paintBody(tex, from, to)
    local fr, fg, fb, fa = resolveColor(from)
    local tr, tg, tb, ta = resolveColor(to)
    if type(tex.SetGradient) == "function" and type(CreateColor) == "function" then
        -- A gradient multiplies with the vertex colour, so that has to be reset to white
        -- or a plate built by the fallback path first would stay tinted twice.
        tex:SetVertexColor(1, 1, 1, 1)
        tex:SetGradient("VERTICAL", CreateColor(tr, tg, tb, ta), CreateColor(fr, fg, fb, fa))
        return true
    end
    -- No gradient API: a flat fill at the midpoint alpha. It takes `from`'s RGB, which
    -- costs nothing while both ends share a hue — and they are meant to, since the pair
    -- exists to vary alpha rather than colour.
    tex:SetVertexColor(fr, fg, fb, (fa + ta) / 2)
    return false
end

--- Sets the plate's colours, keeping any key left out.
-- @param opts table|nil  { from, to, sheen } — each a tokenKey|color|false
function GlassMeta:SetColors(opts)
    opts = opts or {}
    if opts.from  ~= nil then self._from  = opts.from  end
    if opts.to    ~= nil then self._to    = opts.to    end
    if opts.sheen ~= nil then self._sheen = opts.sheen end
    self._isGradient = paintBody(self._body, self._from, self._to)
    self._sheenTex:SetVertexColor(resolveColor(self._sheen))
end

--- Sets the border colour, or false for no border.
-- false resolves to a fully transparent edge rather than a missing one, exactly as
-- Apply's border does, so there is no branch and no geometry difference to reason about.
-- @param tokenKeyOrColor string|table|false
function GlassMeta:SetBorder(tokenKeyOrColor)
    self._border = tokenKeyOrColor
    local r, g, b, a = resolveColor(tokenKeyOrColor)
    for _, tex in ipairs(self._edges) do
        tex:SetVertexColor(r, g, b, a)
    end
end

--- True when the body is a real gradient, false when it fell back to a flat fill.
-- Reported rather than inferred: nothing about the finished plate says which path a
-- client took, and a spec has to be able to assert the fallback is reachable.
function GlassMeta:IsGradient()
    return self._isGradient == true
end

-- The props tables are the ones handed to Add, so mutating them in place is what the next
-- Layout() pass reads — no allocation, and no SetChildProps per piece, which would run a
-- whole layout each time.
function GlassMeta:_geom()
    local ins, bw = self._inset, self._bw

    self._pBody.inset.left,  self._pBody.inset.right  = ins, ins
    self._pBody.inset.top,   self._pBody.inset.bottom = ins, ins

    -- On the body's own top edge, inside the border rather than over it.
    self._pSheen.height = sheenHeight()
    self._pSheen.inset.left, self._pSheen.inset.right = ins, ins
    self._pSheen.inset.top = ins

    self._pEdgeT.height = bw
    self._pEdgeB.height = bw
    self._pEdgeL.width  = bw
    self._pEdgeR.width  = bw
end

--- Re-derives thickness from the borderWidth token and re-resolves every colour.
-- Resizes are the container's job; call this after a theme change.
function GlassMeta:Refresh()
    self._bw = SuuUI.Pixel.Line(self._bwProp or SuuUI.Theme:GetToken("borderWidth") or 1)
    self._inset = self._insetProp or self._bw
    self:_geom()
    self:SetColors()
    self:SetBorder(self._border)
    self._box:Layout()
end

--- Drops the layout box. Textures cannot be destroyed; they go when their frame does.
function GlassMeta:Destroy()
    self._box:Destroy()
end

--- Fills a frame with a translucent gradient plate.
-- @param frame frame  plain Frame — a plate is drawn from textures, not from a backdrop
-- @param opts table   { from = tokenKey|color, to = tokenKey|color,
--                       sheen = tokenKey|color|false, border = tokenKey|color|false,
--                       borderWidth = number|nil, inset = number|nil }
--   from:  the colour at the plate's dense edge, which is its TOP.
--   to:    the colour at its open edge, the bottom.
--   inset: how far the body sits inside the frame, with the same meaning and the same
--          default as Apply's — the border width, so a bordered plate does not paint
--          under its own edge. Pass 0 for a borderless plate that has to cover its whole
--          box, or its body is a pixel short on every side and anything drawn flush to
--          the frame no longer lines up with it.
-- @return table  handle { SetColors, SetBorder, IsGradient, Refresh, Destroy }
function M.Glass(frame, opts)
    opts = opts or {}
    local self = setmetatable({
        _f      = frame,
        _from   = opts.from,  _to        = opts.to,     _sheen     = opts.sheen,
        _border = opts.border, _bwProp   = opts.borderWidth, _insetProp = opts.inset,
        _bw     = 0,          _inset     = 0,
    }, GlassMeta)

    local box = SuuUI.Layout:CreateContainer({ host = frame, layout = "stack" })
    self._box = box

    self._pBody  = { inset = {} }
    self._pSheen = { valign = "start",   height = 0, inset = {} }
    self._pEdgeT = { valign = "start",   height = 0 }
    self._pEdgeB = { valign = "end",     height = 0 }
    self._pEdgeL = { align  = "start",   valign = "stretch", width = 0 }
    self._pEdgeR = { align  = "end",     valign = "stretch", width = 0 }

    -- Three layers, bottom up: the body, the sheen on its top edge, then the border over
    -- both. The border is last because it is the plate's outline — a sheen drawn over it
    -- would put a lighter pixel on top of the edge in the top corners.
    self._body     = midPiece(frame, box, "BACKGROUND", self._pBody)
    self._sheenTex = midPiece(frame, box, "BORDER",     self._pSheen)
    self._edgeT    = midPiece(frame, box, "ARTWORK",    self._pEdgeT)
    self._edgeB    = midPiece(frame, box, "ARTWORK",    self._pEdgeB)
    self._edgeL    = midPiece(frame, box, "ARTWORK",    self._pEdgeL)
    self._edgeR    = midPiece(frame, box, "ARTWORK",    self._pEdgeR)
    -- Named for the specs and iterable for SetBorder; the same four textures either way.
    self._edges    = { self._edgeT, self._edgeB, self._edgeL, self._edgeR }

    self:Refresh()
    return self
end

SuuUI.Backdrop = M
