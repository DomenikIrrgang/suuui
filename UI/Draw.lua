-- UI/Draw.lua
-- Drawing helpers every component is built from: token fills, 1px borders that
-- stay one physical pixel at any scale, fading hairlines, the gilt diamond,
-- and soft glows and shadows.

local _, ns = ...

local UI = {}
ns.UI = UI

local T, Pixel, Events = ns.Tokens, ns.Pixel, ns.Events

local WHITE = "Interface\\Buttons\\WHITE8X8"
local SOFT = "Interface\\AddOns\\SuuUI\\Media\\Textures\\Soft.tga"

-- A token colour as r, g, b, a; `alpha` multiplies the token's own alpha.
function UI.RGBA(name, alpha)
    local c = T.color[name] or error("SuuUI: unknown colour token " .. tostring(name), 2)
    return c[1], c[2], c[3], c[4] * (alpha or 1)
end

-- A size token in px, or a number passed through.
function UI.Size(v)
    if type(v) == "number" then return v end
    return T.size[v] or T.space[v] or error("SuuUI: unknown size token " .. tostring(v), 2)
end

local function crisp(tex)
    tex:SetSnapToPixelGrid(false)
    tex:SetTexelSnappingBias(0)
    return tex
end

-- A solid texture in a token colour.
function UI.Fill(parent, color, layer, sublevel)
    local t = parent:CreateTexture(nil, layer or "BACKGROUND", nil, sublevel)
    t:SetColorTexture(UI.RGBA(color))
    return t
end

--------------------------------------------------------------------------------
-- Borders: four textures, `width` physical pixels thick, `inset` pixels in
-- from the frame's edge. Re-laid out when the root rescales.
--------------------------------------------------------------------------------

local borders = setmetatable({}, { __mode = "k" })

local Border = {}
Border.__index = Border

function Border:Layout()
    local px = Pixel.Size(self.frame)
    local w, i = px * self.width, px * self.inset
    local top, bottom, left, right = self.top, self.bottom, self.left, self.right
    top:ClearAllPoints()
    top:SetPoint("TOPLEFT", i, -i)
    top:SetPoint("TOPRIGHT", -i, -i)
    top:SetHeight(w)
    bottom:ClearAllPoints()
    bottom:SetPoint("BOTTOMLEFT", i, i)
    bottom:SetPoint("BOTTOMRIGHT", -i, i)
    bottom:SetHeight(w)
    left:ClearAllPoints()
    left:SetPoint("TOPLEFT", i, -i - w)
    left:SetPoint("BOTTOMLEFT", i, i + w)
    left:SetWidth(w)
    right:ClearAllPoints()
    right:SetPoint("TOPRIGHT", -i, -i - w)
    right:SetPoint("BOTTOMRIGHT", -i, i + w)
    right:SetWidth(w)
end

-- A token name (plus an optional alpha multiplier), { r, g, b, a }, or r, g, b, a.
function Border:SetColor(r, g, b, a)
    if type(r) == "string" then r, g, b, a = UI.RGBA(r, g)
    elseif type(r) == "table" then r, g, b, a = unpack(r) end
    for _, t in ipairs(self.parts) do t:SetColorTexture(r, g, b, a) end
end

function Border:SetShown(shown)
    for _, t in ipairs(self.parts) do t:SetShown(shown) end
end

function UI.Border(frame, color, opts)
    opts = opts or {}
    local b = setmetatable({ frame = frame, width = opts.width or 1, inset = opts.inset or 0 }, Border)
    local layer, sub = opts.layer or "BORDER", opts.sublevel
    b.top, b.bottom = crisp(frame:CreateTexture(nil, layer, nil, sub)), crisp(frame:CreateTexture(nil, layer, nil, sub))
    b.left, b.right = crisp(frame:CreateTexture(nil, layer, nil, sub)), crisp(frame:CreateTexture(nil, layer, nil, sub))
    b.parts = { b.top, b.bottom, b.left, b.right }
    b:SetColor(color)
    b:Layout()
    borders[b] = true
    return b
end

--------------------------------------------------------------------------------
-- Hairlines: a 1px horizontal line. fade = "out" (solid, then fading to the
-- right), "both" (fading in from the left and out to the right) or nil (solid).
--------------------------------------------------------------------------------

local hairlines = setmetatable({}, { __mode = "k" })

local function gradient(tex, r, g, b, a, fromAlpha, toAlpha)
    tex:SetColorTexture(1, 1, 1, 1)
    tex:SetGradient("HORIZONTAL", CreateColor(r, g, b, a * fromAlpha), CreateColor(r, g, b, a * toAlpha))
end

function UI.Hairline(parent, color, fade)
    local line = CreateFrame("Frame", nil, parent)
    local r, g, b, a = UI.RGBA(color)
    if fade == "both" then
        local left, right = crisp(line:CreateTexture(nil, "ARTWORK")), crisp(line:CreateTexture(nil, "ARTWORK"))
        left:SetPoint("TOPLEFT")
        left:SetPoint("BOTTOMRIGHT", line, "BOTTOM")
        right:SetPoint("TOPLEFT", line, "TOP")
        right:SetPoint("BOTTOMRIGHT")
        gradient(left, r, g, b, a, 0, 1)
        gradient(right, r, g, b, a, 1, 0)
    else
        local t = crisp(line:CreateTexture(nil, "ARTWORK"))
        t:SetAllPoints()
        if fade == "out" then
            gradient(t, r, g, b, a, 1, 0)
        else
            t:SetColorTexture(r, g, b, a)
        end
    end
    line:SetHeight(Pixel.Size(line))
    hairlines[line] = true
    return line
end

--------------------------------------------------------------------------------
-- The gilt diamond: a square turned 45 degrees (ornaments, the divider jewel,
-- active tabs, class diamonds).
--------------------------------------------------------------------------------

function UI.Diamond(parent, size, color, layer)
    local t = parent:CreateTexture(nil, layer or "OVERLAY", nil, 7)
    t:SetTexture(WHITE)
    t:SetVertexColor(UI.RGBA(color or "gilt"))
    t:SetSize(size, size)
    t:SetRotation(math.rad(45))
    return t
end

--------------------------------------------------------------------------------
-- Soft edges: the design's box shadows (glow-arcane, glow-ember, glow-ward,
-- shadow-panel), drawn behind `frame` from Soft.tga as a 3x3 slice.
--------------------------------------------------------------------------------

local SLICES = {
    -- the four corners: point, relative point, u1, u2, v1, v2
    { "TOPLEFT", "TOPLEFT", 0, 0.25, 0, 0.25 },
    { "TOPRIGHT", "TOPRIGHT", 0.75, 1, 0, 0.25 },
    { "BOTTOMLEFT", "BOTTOMLEFT", 0, 0.25, 0.75, 1 },
    { "BOTTOMRIGHT", "BOTTOMRIGHT", 0.75, 1, 0.75, 1 },
}

local SoftEdge = {}
SoftEdge.__index = SoftEdge

-- CSS blur radius B has a Gaussian sigma of B/2; Soft.tga's falloff is a
-- third of its margin, so the margin is drawn 1.5 * B wide.
function SoftEdge:SetBlur(blur, x, y)
    local s = math.max(1, blur * 1.5)
    x, y = x or 0, y or 0
    local h, f = self.holder, self.frame
    h:ClearAllPoints()
    h:SetPoint("TOPLEFT", f, "TOPLEFT", -s + x, s + y)
    h:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", s + x, -s + y)
    for i = 1, 4 do self.corners[i]:SetSize(s, s) end
end

function SoftEdge:SetColor(r, g, b, a)
    if type(r) == "string" then r, g, b, a = UI.RGBA(r, g)
    elseif type(r) == "table" then r, g, b, a = unpack(r) end
    for _, t in ipairs(self.parts) do t:SetVertexColor(r, g, b, a) end
end

function SoftEdge:SetShown(shown)
    self.holder:SetShown(shown)
end

function UI.SoftEdge(frame)
    local h = CreateFrame("Frame", nil, frame)
    h:SetFrameLevel(math.max(0, frame:GetFrameLevel() - 1))
    local e = setmetatable({ frame = frame, holder = h, corners = {}, parts = {} }, SoftEdge)
    local function part(u1, u2, v1, v2)
        local t = h:CreateTexture(nil, "BACKGROUND", nil, -8)
        t:SetTexture(SOFT)
        t:SetTexCoord(u1, u2, v1, v2)
        e.parts[#e.parts + 1] = t
        return t
    end
    for i, s in ipairs(SLICES) do
        local t = part(s[3], s[4], s[5], s[6])
        t:SetPoint(s[1], h, s[2])
        e.corners[i] = t
    end
    local tl, tr, bl, br = e.corners[1], e.corners[2], e.corners[3], e.corners[4]
    local top = part(0.25, 0.75, 0, 0.25)
    top:SetPoint("TOPLEFT", tl, "TOPRIGHT")
    top:SetPoint("BOTTOMRIGHT", tr, "BOTTOMLEFT")
    local bottom = part(0.25, 0.75, 0.75, 1)
    bottom:SetPoint("TOPLEFT", bl, "TOPRIGHT")
    bottom:SetPoint("BOTTOMRIGHT", br, "BOTTOMLEFT")
    local left = part(0, 0.25, 0.25, 0.75)
    left:SetPoint("TOPLEFT", tl, "BOTTOMLEFT")
    left:SetPoint("BOTTOMRIGHT", bl, "TOPRIGHT")
    local right = part(0.75, 1, 0.25, 0.75)
    right:SetPoint("TOPLEFT", tr, "BOTTOMLEFT")
    right:SetPoint("BOTTOMRIGHT", br, "TOPRIGHT")
    local center = part(0.25, 0.75, 0.25, 0.75)
    center:SetPoint("TOPLEFT", tl, "BOTTOMRIGHT")
    center:SetPoint("BOTTOMRIGHT", br, "TOPLEFT")
    e:SetBlur(8)
    e:SetColor(1, 1, 1, 1)
    return e
end

-- A soft edge from a shadow token's first outer layer, e.g. "glow-arcane".
function UI.Shadow(frame, token)
    local layer
    for _, l in ipairs(T.shadow[token] or error("SuuUI: unknown shadow token " .. tostring(token), 2)) do
        if not l.inset then layer = l break end
    end
    local e = UI.SoftEdge(frame)
    e:SetBlur(layer.blur, layer.x, -layer.y)
    e:SetColor(layer.color)
    return e
end

--------------------------------------------------------------------------------
-- The close glyph: two crossed strokes in a square.
--------------------------------------------------------------------------------

function UI.Cross(parent, size, color)
    local holder = CreateFrame("Frame", nil, parent)
    holder:SetSize(size, size)
    holder.strokes = {}
    for i, angle in ipairs({ 45, -45 }) do
        local t = holder:CreateTexture(nil, "OVERLAY")
        t:SetTexture(WHITE)
        t:SetSize(size * 1.15, 1.5)
        t:SetPoint("CENTER")
        t:SetRotation(math.rad(angle))
        holder.strokes[i] = t
    end
    function holder:SetColor(name)
        for _, t in ipairs(self.strokes) do t:SetVertexColor(UI.RGBA(name)) end
    end
    holder:SetColor(color or "ink-muted")
    return holder
end

--------------------------------------------------------------------------------
-- Keep every pixel-thick line one physical pixel after a rescale.
--------------------------------------------------------------------------------

Events.On("SUUUI_ROOT_SCALED", function()
    for b in pairs(borders) do b:Layout() end
    for line in pairs(hairlines) do line:SetHeight(Pixel.Size(line)) end
end, "Draw")
