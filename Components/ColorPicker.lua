local max, min, floor, abs = math.max, math.min, math.floor, math.abs
local format = string.format

local CpMeta = {}
CpMeta.__index = CpMeta

function CpMeta:SetPoint(...)  self._f:SetPoint(...) end
function CpMeta:SetSize(w, h)  self._f:SetSize(w, h) end
function CpMeta:Show()         self._f:Show() end
function CpMeta:Hide()         self._f:Hide() end
function CpMeta:IsShown()      return self._f:IsShown() end
function CpMeta:GetFrame()     return self._f end
function CpMeta:SetEnabled(en) self._enabled = en end
function CpMeta:Destroy()      SuuUI.Events:Off("SUUUI_THEME_CHANGED", self._eid) end

--- Returns current color as r, g, b, a (0-1 each).
-- @return number, number, number, number
function CpMeta:GetValue()
    return self._r, self._g, self._b, self._a
end

--- Sets color without firing onChange.
-- @param r number  @param g number  @param b number  @param a number
function CpMeta:SetValue(r, g, b, a)
    self._r, self._g, self._b = r or 1, g or 1, b or 1
    self._a = a or 1
    self:_render()
end

-- HSV <-> RGB helpers
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

function CpMeta:_render()
    self._preview:SetColorTexture(self._r, self._g, self._b, self._a)
    self._hexInput:SetText(toHex(self._r, self._g, self._b, self._a))
end

function CpMeta:_pickFromSV(px, py)
    local fw = self._svBox:GetWidth()
    local fh = self._svBox:GetHeight()
    local bl = self._svBox:GetLeft() or 0
    local bt = self._svBox:GetTop()  or 0
    local s  = max(0, min(1, (px - bl) / fw))
    local v  = max(0, min(1, (bt - py) / fh))
    self._s, self._v = s, v
    local r, g, b = hsvToRgb(self._h, s, v)
    self._r, self._g, self._b = r, g, b
    self:_render()
    self._svThumb:SetPoint("CENTER", self._svBox, "TOPLEFT", s * fw, -v * fh)
    if self._onChange then self._onChange(r, g, b, self._a) end
end

function CpMeta:_pickFromHue(px)
    local bl = self._hueBar:GetLeft() or 0
    local bw = self._hueBar:GetWidth()
    local h  = max(0, min(1, (px - bl) / bw))
    self._h  = h
    -- update SV box gradient color (hue at full S+V)
    local hr, hg, hb = hsvToRgb(h, 1, 1)
    self._svHueTex:SetColorTexture(hr, hg, hb, 1)
    local r, g, b = hsvToRgb(h, self._s, self._v)
    self._r, self._g, self._b = r, g, b
    self:_render()
    self._hueThumb:SetPoint("CENTER", self._hueBar, "LEFT", h * bw, 0)
    if self._onChange then self._onChange(r, g, b, self._a) end
end

function CpMeta:ApplyTheme()
    local T  = SuuUI.Theme
    local bg = T:GetToken("colorBgAlt")
    local bd = T:GetToken("colorBorder")
    local bw = T:GetToken("borderWidth") or 1
    self._f:SetBackdrop({
        bgFile="Interface\\Buttons\\WHITE8x8", edgeFile="Interface\\Buttons\\WHITE8x8",
        edgeSize=bw, insets={left=bw,right=bw,top=bw,bottom=bw},
    })
    if bg then self._f:SetBackdropColor(bg[1], bg[2], bg[3], bg[4]) end
    if bd then self._f:SetBackdropBorderColor(bd[1], bd[2], bd[3], bd[4]) end
    local tc = T:GetToken("colorTextMuted")
    self._hexInput:SetFont(T:GetToken("fontFamilyMain") or "Fonts/FRIZQT__.TTF",
        T:GetToken("fontSizeSm") or 11, "")
    if tc then self._hexInput:SetTextColor(tc[1], tc[2], tc[3], tc[4]) end
end

--- Creates a custom HSV color picker panel.
-- @param props table  { value, onChange }  value = {r,g,b,a}
-- @param parent frame
-- @return table  ColorPicker handle
function SuuUI.Components.ColorPicker(props, parent)
    local initColor = props.value or {1, 1, 1, 1}
    local r0, g0, b0, a0 = initColor[1], initColor[2], initColor[3], initColor[4] or 1
    local h0, s0, v0 = rgbToHsv(r0, g0, b0)

    local f = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    f:SetSize(160, 140)

    -- SV box (saturation/value square)
    local svBox = CreateFrame("Frame", nil, f)
    svBox:SetSize(120, 90)
    svBox:SetPoint("TOPLEFT", f, "TOPLEFT", 6, -6)
    svBox:EnableMouse(true)

    -- base hue layer
    local svHueTex = svBox:CreateTexture(nil, "BACKGROUND")
    svHueTex:SetAllPoints(svBox)
    local hhr, hhg, hhb = hsvToRgb(h0, 1, 1)
    svHueTex:SetColorTexture(hhr, hhg, hhb, 1)

    -- white gradient (left=white, right=transparent)
    local svWhite = svBox:CreateTexture(nil, "ARTWORK")
    svWhite:SetAllPoints(svBox)
    svWhite:SetGradientAlpha("HORIZONTAL", 1,1,1,1, 1,1,1,0)

    -- black gradient (top=transparent, bottom=black)
    local svBlack = svBox:CreateTexture(nil, "OVERLAY")
    svBlack:SetAllPoints(svBox)
    svBlack:SetGradientAlpha("VERTICAL", 0,0,0,0, 0,0,0,1)

    -- SV thumb
    local svThumb = CreateFrame("Frame", nil, svBox)
    svThumb:SetSize(8, 8)
    svThumb:SetPoint("CENTER", svBox, "TOPLEFT", s0*120, -v0*90)
    local svTex = svThumb:CreateTexture(nil, "OVERLAY")
    svTex:SetAllPoints(svThumb)
    svTex:SetColorTexture(1, 1, 1, 0.9)

    -- Hue bar
    local hueBar = CreateFrame("Frame", nil, f)
    hueBar:SetSize(120, 10)
    hueBar:SetPoint("TOPLEFT", svBox, "BOTTOMLEFT", 0, -4)
    hueBar:EnableMouse(true)

    -- Use the Blizzard color picker hue texture — full spectrum, no custom gradient needed
    local hueTex = hueBar:CreateTexture(nil, "ARTWORK")
    hueTex:SetAllPoints(hueBar)
    hueTex:SetTexture("Interface\\TargetingFrame\\UI-TargetingFrame-ColorSwatch")

    -- hue thumb
    local hueThumb = CreateFrame("Frame", nil, hueBar)
    hueThumb:SetSize(6, 14)
    hueThumb:SetPoint("CENTER", hueBar, "LEFT", h0 * 120, 0)
    local htTex = hueThumb:CreateTexture(nil, "OVERLAY")
    htTex:SetAllPoints(hueThumb)
    htTex:SetColorTexture(1, 1, 1, 0.9)

    -- Alpha slider
    local alphaBar = CreateFrame("Frame", nil, f)
    alphaBar:SetSize(120, 10)
    alphaBar:SetPoint("TOPLEFT", hueBar, "BOTTOMLEFT", 0, -4)
    alphaBar:EnableMouse(true)
    local alphaTex = alphaBar:CreateTexture(nil, "ARTWORK")
    alphaTex:SetAllPoints(alphaBar)
    alphaTex:SetGradientAlpha("HORIZONTAL", 0,0,0,0, 1,1,1,1)
    local alphaThumb = CreateFrame("Frame", nil, alphaBar)
    alphaThumb:SetSize(6, 14)
    alphaThumb:SetPoint("CENTER", alphaBar, "LEFT", a0 * 120, 0)
    local atTex = alphaThumb:CreateTexture(nil, "OVERLAY")
    atTex:SetAllPoints(alphaThumb)
    atTex:SetColorTexture(1, 1, 1, 0.9)

    -- Preview swatch
    local preview = f:CreateTexture(nil, "ARTWORK")
    preview:SetSize(24, 24)
    preview:SetPoint("TOPRIGHT", f, "TOPRIGHT", -6, -6)
    preview:SetColorTexture(r0, g0, b0, a0)

    -- Hex input
    local hexInput = CreateFrame("EditBox", nil, f)
    hexInput:SetSize(50, 16)
    hexInput:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -6, 6)
    hexInput:SetAutoFocus(false)
    hexInput:SetMaxLetters(8)
    hexInput:SetFont("Fonts/FRIZQT__.TTF", 11, "")
    hexInput:SetText(toHex(r0, g0, b0, a0))

    local id = "cp_" .. tostring(f)
    local handle = setmetatable({
        _f=f, _svBox=svBox, _svHueTex=svHueTex,
        _svThumb=svThumb, _hueBar=hueBar, _hueThumb=hueThumb,
        _alphaBar=alphaBar, _alphaThumb=alphaThumb,
        _preview=preview, _hexInput=hexInput,
        _eid=id, _enabled=true, _onChange=props.onChange,
        _r=r0, _g=g0, _b=b0, _a=a0,
        _h=h0, _s=s0, _v=v0,
    }, CpMeta)

    svBox:SetScript("OnMouseDown", function()
        local cx, cy = GetCursorPosition()
        cx = cx / UIParent:GetEffectiveScale()
        cy = cy / UIParent:GetEffectiveScale()
        handle:_pickFromSV(cx, cy)
    end)
    svBox:SetScript("OnMouseUp", function(_, _, x, y) handle:_pickFromSV(x, y) end)

    hueBar:SetScript("OnMouseDown", function()
        local cx, _ = GetCursorPosition()
        cx = cx / UIParent:GetEffectiveScale()
        handle:_pickFromHue(cx)
    end)

    alphaBar:SetScript("OnMouseDown", function()
        local bl = alphaBar:GetLeft() or 0
        local bw = alphaBar:GetWidth()
        local cx, _ = GetCursorPosition()
        cx = cx / UIParent:GetEffectiveScale()
        local a  = max(0, min(1, (cx - bl) / bw))
        handle._a = a
        alphaThumb:SetPoint("CENTER", alphaBar, "LEFT", a * bw, 0)
        handle:_render()
        if handle._onChange then handle._onChange(handle._r, handle._g, handle._b, a) end
    end)

    hexInput:SetScript("OnEnterPressed", function()
        local hex = hexInput:GetText()
        if #hex == 8 then
            local ri = tonumber(hex:sub(1,2), 16)
            local gi = tonumber(hex:sub(3,4), 16)
            local bi = tonumber(hex:sub(5,6), 16)
            local ai = tonumber(hex:sub(7,8), 16)
            if ri and gi and bi and ai then
                handle:SetValue(ri/255, gi/255, bi/255, ai/255)
                if handle._onChange then
                    handle._onChange(handle._r, handle._g, handle._b, handle._a)
                end
            end
        end
        hexInput:ClearFocus()
    end)
    hexInput:SetScript("OnEscapePressed", function() hexInput:ClearFocus() end)

    handle:ApplyTheme()
    SuuUI.Events:On("SUUUI_THEME_CHANGED", function() handle:ApplyTheme() end, id)
    return handle
end
