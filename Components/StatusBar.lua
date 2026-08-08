local type = type
local max = math.max

local S = SuuUI.UISignals

local StatusBarMeta = {}
StatusBarMeta.__index = StatusBarMeta

--- Recolours the bar fill and background.
function StatusBarMeta:_paint()
    local B = SuuUI.Backdrop
    B.SetBg(self._f, self._bgColor or "colorBgAlt")
    B.SetBorder(self._f, self._showBorder and "colorBorder" or false)
    local r, g, b, a = self._fillColor[1], self._fillColor[2], self._fillColor[3], self._fillColor[4] or 1
    self._bar:SetColorTexture(r, g, b, a)
end

--- Updates the bar fill width based on current value/max.
function StatusBarMeta:_updateFill()
    local pct = 0
    if self._max > 0 then
        pct = self._value / self._max
        if pct < 0 then pct = 0 end
        if pct > 1 then pct = 1 end
    end
    self._pct = pct
    -- Fill is positioned by the host container's anchor strategy. We set the fill
    -- frame's width as a fraction of the outer frame's width.
    local totalW = self._f:GetWidth() or 0
    local bw = SuuUI.Pixel.Line(SuuUI.Theme:GetToken("borderWidth") or 1)
    local innerW = max(totalW - bw * 2, 0)
    local fillW = SuuUI.Pixel.Floor(innerW * pct)
    if fillW < 0.5 then
        self._fillFrame:Hide()
    else
        self._fillFrame:SetWidth(fillW)
        self._fillFrame:Show()
    end
end

--- Restyles for theme changes.
function StatusBarMeta:ApplyTheme()
    SuuUI.Backdrop.Apply(self._f, {
        bg     = self._bgColor or "colorBgAlt",
        border = self._showBorder and "colorBorder" or false,
    })
    self:_paint()
    self:_updateFill()
end

--- Sets the current value. Clamps to [0, max].
-- @param v number
function StatusBarMeta:SetValue(v)
    v = v or 0
    if v < 0 then v = 0 end
    if v > self._max then v = self._max end
    local old = self._value
    self._value = v
    self:_updateFill()
    if old ~= v then
        S:Emit(self, S.SIGNALS.VALUE_CHANGED, v, old)
    end
end

--- Sets the maximum value.
-- @param m number
function StatusBarMeta:SetMax(m)
    m = m or 1
    if m < 0 then m = 0 end
    self._max = m
    self:_updateFill()
end

--- Returns the current value.
-- @return number
function StatusBarMeta:GetValue()
    return self._value
end

--- Returns the current max.
-- @return number
function StatusBarMeta:GetMax()
    return self._max
end

--- Returns the current fill percentage (0..1).
-- @return number
function StatusBarMeta:GetPercent()
    return self._pct
end

--- Sets the fill colour as a literal {r,g,b,a} table.
-- @param color table  {r, g, b, a}
function StatusBarMeta:SetFillColor(color)
    self._fillColor = color or {1, 1, 1, 1}
    self:_paint()
end

--- Sets the background colour token or literal.
-- @param color string|table|false
function StatusBarMeta:SetBgColor(color)
    self._bgColor = color
    self:_paint()
end

function StatusBarMeta:Destroy()
    S:DisconnectAll(self)
    SuuUI.Events:Off("SUUUI_THEME_CHANGED", self._eid)
    self._f:Hide()
end

SuuUI.Components.InstallBase(StatusBarMeta, "_f")

local WHITE = "Interface\\Buttons\\WHITE8x8"

--- Creates a status bar (health/mana/energy/rage bar).
-- @param props table  { w, h, value, max, fillColor, bgColor, border }
--   fillColor: {r,g,b,a} literal colour for the bar fill
--   bgColor: token key or literal for the background (default "colorBgAlt")
--   border: bool whether to show border (default true)
-- @param parent frame
-- @return table  StatusBar handle
function SuuUI.Components.StatusBar(props, parent)
    props = props or {}
    local f = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    if props.w then f:SetWidth(props.w) end
    if props.h then f:SetHeight(props.h) end

    -- Fill texture frame: a child frame holding a texture, anchored inside the border
    local fillFrame = CreateFrame("Frame", nil, f)
    local bw = SuuUI.Pixel.Line(SuuUI.Theme:GetToken("borderWidth") or 1)
    fillFrame:SetPoint("TOPLEFT", f, "TOPLEFT", bw, -bw)
    fillFrame:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", bw, bw)
    fillFrame:SetWidth(0)

    local bar = fillFrame:CreateTexture(nil, "ARTWORK")
    bar:SetTexture(WHITE)
    bar:SetAllPoints(fillFrame)

    local id = "statusbar_" .. tostring(f)
    local handle = setmetatable({
        _f          = f,
        _fillFrame  = fillFrame,
        _bar        = bar,
        _eid        = id,
        _value      = props.value or 0,
        _max        = props.max or 1,
        _pct        = 0,
        _fillColor  = props.fillColor or {1, 1, 1, 1},
        _bgColor    = props.bgColor or "colorBgAlt",
        _showBorder = props.border ~= false,
    }, StatusBarMeta)

    f:SetScript("OnSizeChanged", function(_, w, h)
        handle:_updateFill()
        S:Emit(handle, S.SIGNALS.SIZE_CHANGED, w, h)
    end)

    handle:ApplyTheme()
    handle:_updateFill()
    SuuUI.Events:On("SUUUI_THEME_CHANGED", function() handle:ApplyTheme() end, id)
    return handle
end
