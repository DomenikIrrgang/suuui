local max, min, floor = math.max, math.min, math.floor
local format = string.format
local C = SuuUI.Components
local S = SuuUI.UISignals

-- ColorPicker-specific signals
C.COLORPICKER_SIGNALS = {
    COLOR_PICKED  = "colorpicker.color_picked",   -- Args: r, g, b, a
    REQUEST_CLOSE = "colorpicker.request_close",  -- Args: none
}

local COLOR_PICKED  = C.COLORPICKER_SIGNALS.COLOR_PICKED
local REQUEST_CLOSE = C.COLORPICKER_SIGNALS.REQUEST_CLOSE

-- Panel geometry. None of these have a matching theme token, so they stay named
-- constants rather than being bent onto a token that does not fit.
--
-- PANEL_W is the sum of the parts at the default spacing tokens: padding, the
-- saturation square, the inner gap, the right-hand column, padding. PANEL_H is the
-- padded height of the square plus the two bar rows.
local PANEL_W    = 240
local PANEL_H    = 180
-- Side of the square saturation/value field.
local SV_SIZE    = 120
-- Bar rows: the label column, then the bar filling the rest of the panel width.
local LABEL_W    = 35
local BAR_W      = 185
local BAR_H      = 14
-- Right-hand column holding the preview swatch above the hex field.
local COL_W      = 96
-- Thumbs. The bar thumb is a tall thin sliver that deliberately overhangs its bar;
-- its height is the small-control token, its width has no token.
local BAR_THUMB_W = 6
local SV_THUMB    = 8

local CpMeta = {}
CpMeta.__index = CpMeta

local function barThumbH()
    return SuuUI.Theme:GetToken("sizeControlSm") or 18
end

function CpMeta:SetEnabled(en) self._enabled = en end

-- SIZE_CHANGED is emitted here rather than from a frame resize hook: the panel is a
-- floating popup at a fixed size, never stretched by a parent layout.
function CpMeta:SetSize(w, h)
    self._f:SetSize(w, h)
    S:Emit(self, S.SIGNALS.SIZE_CHANGED, w, h)
end

function CpMeta:Show()
    self._f:Show()
    if self._clickAway then self._clickAway:Arm() end
    S:Emit(self, S.SIGNALS.VISIBILITY_CHANGED, true)
end

function CpMeta:Hide()
    self._f:SetScript("OnUpdate", nil)
    self._f:Hide()
    if self._clickAway then self._clickAway:Disarm() end
    S:Emit(self, S.SIGNALS.VISIBILITY_CHANGED, false)
end

function CpMeta:Destroy()
    S:DisconnectAll(self)
    SuuUI.Events:Off("SUUUI_THEME_CHANGED", self._eid)
    self._f:SetScript("OnUpdate", nil)
    if self._clickAway then
        self._clickAway:Destroy()
        self._clickAway = nil
    end
    self._root:Destroy()
    self._f:Hide()
end

local function rgbToHsv(r, g, b)
    local mx = max(r, g, b)
    local mn = min(r, g, b)
    local d  = mx - mn
    local h, s, v = 0, 0, mx
    if mx ~= 0 then s = d / mx end
    if d ~= 0 then
        if mx == r then h = (g - b) / d % 6
        elseif mx == g then h = (b - r) / d + 2
        else h = (r - g) / d + 4 end
        h = h / 6
    end
    return h, s, v
end

local function hsvToRgb(h, s, v)
    local i = floor(h * 6)
    local f = h * 6 - i
    local p = v * (1 - s)
    local q = v * (1 - f * s)
    local t = v * (1 - (1 - f) * s)
    local r, g, b
    i = i % 6
    if     i == 0 then r,g,b = v,t,p
    elseif i == 1 then r,g,b = q,v,p
    elseif i == 2 then r,g,b = p,v,t
    elseif i == 3 then r,g,b = p,q,v
    elseif i == 4 then r,g,b = t,p,v
    else               r,g,b = v,p,q end
    return r, g, b
end

local function toHex(r, g, b, a)
    return format("%02X%02X%02X%02X",
        floor(r*255+0.5), floor(g*255+0.5),
        floor(b*255+0.5), floor(a*255+0.5))
end

--- Returns current color as r, g, b, a (0-1 each).
-- @return number, number, number, number
function CpMeta:GetValue()
    return self._r, self._g, self._b, self._a
end

--- Sets color without emitting VALUE_CHANGED.
-- @param r number  @param g number  @param b number  @param a number
function CpMeta:SetValue(r, g, b, a)
    self._r, self._g, self._b = r or 1, g or 1, b or 1
    self._a = a or 1
    self._h, self._s, self._v = rgbToHsv(self._r, self._g, self._b)
    self:_syncThumbs()
    self:_render()
end

-- All thumb placement goes through anchor containers
function CpMeta:_syncThumbs()
    local hr, hg, hb = hsvToRgb(self._h, 1, 1)
    self._svHueTex:SetColorTexture(hr, hg, hb, 1)

    -- The square runs unsaturated to saturated left to right, and bright to black top to
    -- bottom. Value is therefore an offset *down* from the top by its inverse, matching
    -- how _pickFromSV reads it back from the cursor.
    self._svAnchor.x = self._s * SV_SIZE
    self._svAnchor.y = -(1 - self._v) * SV_SIZE
    self._svBox:SetChildAnchor(self._svThumb, self._svAnchor)

    self._hueAnchor.x = self._h * BAR_W
    self._hueBox:SetChildAnchor(self._hueThumb, self._hueAnchor)

    self._alphaAnchor.x = self._a * BAR_W
    self._alphaBox:SetChildAnchor(self._alphaThumb, self._alphaAnchor)
end

function CpMeta:_render()
    self._preview:SetColorTexture(self._r, self._g, self._b, self._a)
    self._hexInput:SetValue(toHex(self._r, self._g, self._b, self._a))
end

function CpMeta:_commit()
    self:_render()
    if self._onChange then self._onChange(self._r, self._g, self._b, self._a) end
    S:Emit(self, S.SIGNALS.VALUE_CHANGED, { self._r, self._g, self._b, self._a })
    S:Emit(self, COLOR_PICKED, self._r, self._g, self._b, self._a)
end

-- Cursor coordinates are bottom-up, so (top - py) is the distance *down* from the top
-- edge. Value runs bright at the top to black at the bottom, hence the inversion.
function CpMeta:_pickFromSV(px, py)
    local bl = self._svFrame:GetLeft() or 0
    local bt = self._svFrame:GetTop()  or 0
    self._s = max(0, min(1, (px - bl) / SV_SIZE))
    self._v = max(0, min(1, 1 - (bt - py) / SV_SIZE))
    self._r, self._g, self._b = hsvToRgb(self._h, self._s, self._v)
    self:_syncThumbs()
    self:_commit()
end

function CpMeta:_pickFromHue(px)
    local bl = self._hueFrame:GetLeft() or 0
    self._h = max(0, min(1, (px - bl) / BAR_W))
    self._r, self._g, self._b = hsvToRgb(self._h, self._s, self._v)
    self:_syncThumbs()
    self:_commit()
end

function CpMeta:_pickFromAlpha(px)
    local bl = self._alphaFrame:GetLeft() or 0
    self._a = max(0, min(1, (px - bl) / BAR_W))
    self:_syncThumbs()
    self:_commit()
end

function CpMeta:ApplyTheme()
    SuuUI.Backdrop.Apply(self._f, { bg = "colorBgAlt", border = "colorBorder" })
    -- The bar thumbs ride the small-control token, so re-apply it on a theme change.
    local th = barThumbH()
    self._hueAnchor.height   = th
    self._alphaAnchor.height = th
    self._hueBox:SetChildAnchor(self._hueThumb, self._hueAnchor)
    self._alphaBox:SetChildAnchor(self._alphaThumb, self._alphaAnchor)
end

-- Fills in GetWidth, GetHeight, IsShown, GetFrame. Show, Hide and SetSize are defined
-- above and survive: Show/Hide arm the click-away watcher, and SetSize emits.
SuuUI.Components.InstallBase(CpMeta, "_f")

-- Builds a labelled bar row (hue / alpha) and returns frame + anchor container + thumb
local function barRow(parent, root, labelText, gap, thumbTex)
    local row = SuuUI.Layout:CreateContainer({
        parent = parent, layout = "flow", dir = "horizontal",
        gap = gap, align = "center", h = BAR_H,
    })
    local label = C.Text({ text = labelText, size = "sm", color = "muted" }, row:GetFrame())
    row:Add(label, { width = LABEL_W, height = BAR_H })

    local bar = CreateFrame("Frame", nil, row:GetFrame())
    bar:EnableMouse(true)
    row:Add(bar, { width = BAR_W, height = BAR_H })

    local texBox = SuuUI.Layout:CreateContainer({ host = bar, layout = "stack" })
    local tex = bar:CreateTexture(nil, "ARTWORK")
    texBox:Add(tex)

    local thumbBox = SuuUI.Layout:CreateContainer({ host = bar, layout = "anchor" })
    local thumb = CreateFrame("Frame", nil, bar)
    local anchor = {
        point = "CENTER", relativePoint = "LEFT", x = 0, y = 0,
        width = BAR_THUMB_W, height = barThumbH(),
    }
    thumbBox:Add(thumb, { anchor = anchor })

    local tBox = SuuUI.Layout:CreateContainer({ host = thumb, layout = "stack" })
    local tTex = thumb:CreateTexture(nil, "OVERLAY")
    tTex:SetColorTexture(1, 1, 1, 0.9)
    tBox:Add(tTex)

    root:Add(row, { width = "fill", height = BAR_H })
    return bar, tex, thumbBox, thumb, anchor
end

--- Creates a custom HSV color picker panel.
-- Emits VALUE_CHANGED ({r,g,b,a}), COLOR_PICKED (r,g,b,a), REQUEST_CLOSE.
-- @param props table  { value, onChange }  value = {r,g,b,a}
-- @param parent frame
-- @return table  ColorPicker handle
function SuuUI.Components.ColorPicker(props, parent)
    local T   = SuuUI.Theme
    local gap = T:GetToken("spaceXs") or 4
    local pad = T:GetToken("spaceSm") or 8

    local init = props.value or {1, 1, 1, 1}
    local r0, g0, b0, a0 = init[1], init[2], init[3], init[4] or 1
    local h0, s0, v0 = rgbToHsv(r0, g0, b0)

    local f = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    f:SetSize(PANEL_W, PANEL_H)

    local root = SuuUI.Layout:CreateContainer({
        host    = f,
        layout  = "flow",
        dir     = "vertical",
        gap     = gap,
        padding = { top=pad, right=pad, bottom=pad, left=pad },
    })

    -- Top row: SV square + preview/hex column
    local topRow = SuuUI.Layout:CreateContainer({
        parent = f, layout = "flow", dir = "horizontal", gap = pad, h = SV_SIZE,
    })

    local svFrame = CreateFrame("Frame", nil, topRow:GetFrame())
    svFrame:EnableMouse(true)
    topRow:Add(svFrame, { width = SV_SIZE, height = SV_SIZE })

    -- Three stacked gradient layers fill the square
    local svLayers = SuuUI.Layout:CreateContainer({ host = svFrame, layout = "stack" })
    local svHueTex = svFrame:CreateTexture(nil, "BACKGROUND")
    local hhr, hhg, hhb = hsvToRgb(h0, 1, 1)
    svHueTex:SetColorTexture(hhr, hhg, hhb, 1)
    svLayers:Add(svHueTex)

    local svWhite = svFrame:CreateTexture(nil, "ARTWORK")
    svWhite:SetTexture("Interface\\Buttons\\WHITE8x8")
    svWhite:SetGradient("HORIZONTAL", CreateColor(1,1,1,1), CreateColor(1,1,1,0))
    svLayers:Add(svWhite)

    -- A VERTICAL gradient runs its first colour along the bottom edge, so black goes
    -- first: the square is bright at the top and black at the bottom, which is what
    -- _pickFromSV and _syncThumbs both assume.
    local svBlack = svFrame:CreateTexture(nil, "OVERLAY")
    svBlack:SetTexture("Interface\\Buttons\\WHITE8x8")
    svBlack:SetGradient("VERTICAL", CreateColor(0,0,0,1), CreateColor(0,0,0,0))
    svLayers:Add(svBlack)

    local svBox = SuuUI.Layout:CreateContainer({ host = svFrame, layout = "anchor" })
    local svThumb = CreateFrame("Frame", nil, svFrame)
    -- Offsets are left at zero: _syncThumbs runs before the picker is first shown and
    -- owns the mapping from colour to thumb position, so duplicating it here would only
    -- create a second formula to keep in step.
    local svAnchor = {
        point = "CENTER", relativePoint = "TOPLEFT",
        x = 0, y = 0, width = SV_THUMB, height = SV_THUMB,
    }
    svBox:Add(svThumb, { anchor = svAnchor })
    local svThumbBox = SuuUI.Layout:CreateContainer({ host = svThumb, layout = "stack" })
    local svTex = svThumb:CreateTexture(nil, "OVERLAY")
    svTex:SetColorTexture(1, 1, 1, 0.9)
    svThumbBox:Add(svTex)

    -- Right column: preview swatch + hex field
    local rightCol = SuuUI.Layout:CreateContainer({
        parent = topRow:GetFrame(), layout = "flow", dir = "vertical", gap = gap, h = SV_SIZE,
    })
    local previewFrame = CreateFrame("Frame", nil, rightCol:GetFrame())
    local previewBox = SuuUI.Layout:CreateContainer({ host = previewFrame, layout = "stack" })
    local preview = previewFrame:CreateTexture(nil, "ARTWORK")
    preview:SetColorTexture(r0, g0, b0, a0)
    previewBox:Add(preview)
    -- The preview absorbs whatever height the hex field does not need, so a larger font
    -- token grows the field instead of overflowing the fixed-height column.
    rightCol:Add(previewFrame, { width = COL_W, height = "fill" })

    local hexInput = C.Input({ value = toHex(r0,g0,b0,a0), w = COL_W, maxChars = 8 },
        rightCol:GetFrame())
    rightCol:Add(hexInput, { width = COL_W })

    topRow:Add(rightCol, { width = COL_W, height = SV_SIZE })
    root:Add(topRow, { width = "fill", height = SV_SIZE })

    local hueFrame, hueTex, hueBox, hueThumb, hueAnchor =
        barRow(f, root, "Hue:", gap)
    hueTex:SetTexture("Interface\\TargetingFrame\\UI-TargetingFrame-ColorSwatch")

    local alphaFrame, alphaTex, alphaBox, alphaThumb, alphaAnchor =
        barRow(f, root, "Alpha:", gap)
    alphaTex:SetTexture("Interface\\Buttons\\WHITE8x8")
    alphaTex:SetGradient("HORIZONTAL",
        CreateColor(0.5, 0.5, 0.5, 0), CreateColor(0.5, 0.5, 0.5, 1))

    local id = "cp_" .. tostring(f)
    local handle = setmetatable({
        _f=f, _root=root,
        _svFrame=svFrame, _svLayers=svLayers, _svHueTex=svHueTex,
        _svBox=svBox, _svThumb=svThumb, _svAnchor=svAnchor,
        _hueFrame=hueFrame, _hueBox=hueBox, _hueThumb=hueThumb, _hueAnchor=hueAnchor,
        _alphaFrame=alphaFrame, _alphaBox=alphaBox, _alphaThumb=alphaThumb, _alphaAnchor=alphaAnchor,
        _preview=preview, _hexInput=hexInput,
        _eid=id, _enabled=true, _onChange=props.onChange,
        _r=r0, _g=g0, _b=b0, _a=a0, _h=h0, _s=s0, _v=v0,
    }, CpMeta)

    handle:_syncThumbs()

    -- Drag tracking: OnUpdate registered only while a control is held
    local mode = nil
    local function onUpdate()
        local scale = UIParent:GetEffectiveScale()
        local cx, cy = GetCursorPosition()
        cx, cy = cx / scale, cy / scale
        if     mode == "sv"    then handle:_pickFromSV(cx, cy)
        elseif mode == "hue"   then handle:_pickFromHue(cx)
        elseif mode == "alpha" then handle:_pickFromAlpha(cx) end
    end
    local function startDrag(which)
        mode = which
        onUpdate()
        f:SetScript("OnUpdate", onUpdate)
    end
    local function stopDrag()
        mode = nil
        f:SetScript("OnUpdate", nil)
    end

    svFrame:SetScript("OnMouseDown",    function() startDrag("sv") end)
    svFrame:SetScript("OnMouseUp",      stopDrag)
    hueFrame:SetScript("OnMouseDown",   function() startDrag("hue") end)
    hueFrame:SetScript("OnMouseUp",     stopDrag)
    alphaFrame:SetScript("OnMouseDown", function() startDrag("alpha") end)
    alphaFrame:SetScript("OnMouseUp",   stopDrag)
    f:SetScript("OnMouseUp",            stopDrag)
    f:SetScript("OnHide",               stopDrag)

    S:Connect(hexInput, C.INPUT_SIGNALS.SUBMITTED, function(hex)
        hex = hex:match("^#?(%x+)$")
        if not hex then return end
        if #hex == 6 then hex = hex .. "FF" end
        if #hex ~= 8 then return end
        handle:SetValue(
            tonumber(hex:sub(1,2), 16)/255, tonumber(hex:sub(3,4), 16)/255,
            tonumber(hex:sub(5,6), 16)/255, tonumber(hex:sub(7,8), 16)/255)
        handle:_commit()
    end)

    handle._clickAway = SuuUI.Components.ClickAway({
        frame     = f,
        onOutside = function() S:Emit(handle, REQUEST_CLOSE) end,
    })

    handle:ApplyTheme()
    SuuUI.Events:On("SUUUI_THEME_CHANGED", function() handle:ApplyTheme() end, id)
    return handle
end
