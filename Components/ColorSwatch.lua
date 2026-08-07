local floor  = math.floor
local abs    = math.abs
local format = string.format
local S = SuuUI.UISignals

local SwMeta = {}
SwMeta.__index = SwMeta

--- Sets an explicit size, dropping token-driven sizing.
-- SIZE_CHANGED comes from the frame's resize hook.
-- @param w number
-- @param h number
function SwMeta:SetSize(w, h)
    self._autoSize = false
    self._f:SetSize(w, h)
end

function SwMeta:Destroy()
    S:DisconnectAll(self)
    SuuUI.Events:Off("SUUUI_THEME_CHANGED", self._eid)
    self._box:Destroy()
    self._f:Hide()
end

--- Enables or disables interaction. Emits ENABLED_CHANGED.
-- @param en bool
function SwMeta:SetEnabled(en)
    self._enabled = en
    self._f:EnableMouse(en)
    self._f:SetAlpha(en and 1 or 0.4)
    S:Emit(self, S.SIGNALS.ENABLED_CHANGED, en)
end

--- Returns the swatch colour as r, g, b, a.
-- @return number, number, number, number
function SwMeta:GetValue()
    local c = self._color
    return c[1], c[2], c[3], c[4]
end

--- Sets the swatch colour without emitting VALUE_CHANGED.
-- @param r number  @param g number  @param b number  @param a number
function SwMeta:SetValue(r, g, b, a)
    self._color = { r or 1, g or 1, b or 1, a or 1 }
    self._swatch:SetColorTexture(self._color[1], self._color[2], self._color[3], self._color[4])
end

--- Returns the colour as a 6-digit uppercase hex string.
-- @return string
function SwMeta:GetHex()
    local c = self._color
    return format("%02X%02X%02X",
        floor(c[1]*255 + 0.5), floor(c[2]*255 + 0.5), floor(c[3]*255 + 0.5))
end

function SwMeta:ApplyTheme()
    local T  = SuuUI.Theme
    local bd = T:GetToken("colorBorder")
    if bd then self._border:SetColorTexture(bd[1], bd[2], bd[3], bd[4]) end

    -- The visible border is the colour texture showing through the inset, so the inset
    -- is the border width token rather than a pixel literal, snapped to the pixel grid.
    local bw = SuuUI.Pixel.Line(T:GetToken("borderWidth") or 1)
    if self._swatchProps.inset ~= bw then
        self._swatchProps.inset = bw
        self._box:SetChildProps(self._swatch, self._swatchProps)
    end

    -- A swatch holds no text, so its size comes straight from the token rather than
    -- being floored against the font size.
    if self._autoSize then
        local size = T:GetToken("sizeControlMd") or 22
        if abs((self._f:GetWidth() or 0) - size) > 0.5 then
            self._f:SetSize(size, size)
        end
    end
end

-- Fills in GetWidth, GetHeight, IsShown, GetFrame, Show, Hide. SetSize is defined
-- above and survives: it has to clear the token-sizing flag.
SuuUI.Components.InstallBase(SwMeta, "_f")

--- Creates a clickable colour swatch.
-- Emits CLICKED (button), MOUSE_ENTER, MOUSE_LEAVE, ENABLED_CHANGED.
-- Size defaults to the sizeControlMd token and tracks token changes.
-- @param props table  { value = {r,g,b,a}, w, h }
-- @param parent frame
-- @return table  ColorSwatch handle
function SuuUI.Components.ColorSwatch(props, parent)
    local size = props.w or SuuUI.Theme:GetToken("sizeControlMd") or 22
    local col  = props.value or {1, 1, 1, 1}

    local f = CreateFrame("Frame", nil, parent)
    f:SetSize(size, props.h or size)
    f:EnableMouse(true)

    -- Registered before the host container adopts the frame so the container chains
    -- onto this hook. A parent layout resizes the frame directly, never via SetSize.
    local handle
    f:SetScript("OnSizeChanged", function(_, w2, h2)
        if not handle then return end
        S:Emit(handle, S.SIGNALS.SIZE_CHANGED, w2, h2)
    end)

    local box = SuuUI.Layout:CreateContainer({ host = f, layout = "stack" })

    local border = f:CreateTexture(nil, "BACKGROUND")
    box:Add(border)

    local swatch = f:CreateTexture(nil, "ARTWORK")
    swatch:SetColorTexture(col[1], col[2], col[3], col[4] or 1)
    local swatchProps = {
        inset = SuuUI.Pixel.Line(SuuUI.Theme:GetToken("borderWidth") or 1),
    }
    box:Add(swatch, swatchProps)

    local id = "swatch_" .. tostring(f)
    handle = setmetatable({
        _f       = f,
        _swatch  = swatch,
        _border  = border,
        _box     = box,
        _swatchProps = swatchProps,
        _eid     = id,
        _enabled = true,
        _autoSize = props.w == nil and props.h == nil,
        _color   = { col[1], col[2], col[3], col[4] or 1 },
    }, SwMeta)

    f:SetScript("OnMouseUp", function(_, btn)
        if handle._enabled == false then return end
        S:Emit(handle, S.SIGNALS.CLICKED, btn or "LeftButton")
    end)
    f:SetScript("OnEnter", function()
        if handle._enabled == false then return end
        f:SetAlpha(0.8)
        S:Emit(handle, S.SIGNALS.MOUSE_ENTER)
    end)
    f:SetScript("OnLeave", function()
        f:SetAlpha(handle._enabled == false and 0.4 or 1)
        S:Emit(handle, S.SIGNALS.MOUSE_LEAVE)
    end)

    handle:ApplyTheme()
    SuuUI.Events:On("SUUUI_THEME_CHANGED", function() handle:ApplyTheme() end, id)
    return handle
end
