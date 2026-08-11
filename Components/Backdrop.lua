local type, ipairs, setmetatable = type, ipairs, setmetatable

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

SuuUI.Backdrop = M
