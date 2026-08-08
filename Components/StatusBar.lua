local type = type

local S = SuuUI.UISignals

local StatusBarMeta = {}
StatusBarMeta.__index = StatusBarMeta

--- How far the fill and the track sit inside the bar frame.
--- A bordered bar insets both by the border width so neither paints under the edge. A
--- borderless bar insets by nothing: there is no edge to avoid, and an inset there would
--- leave the track showing as a hairline ring around a full bar and make an empty bar a
--- pixel wider on every side than the fill that replaces it.
-- @return number
function StatusBarMeta:_inset()
    if not self._showBorder then return 0 end
    return SuuUI.Pixel.Line(SuuUI.Theme:GetToken("borderWidth") or 1)
end

--- Restates the fill's inset on the host container. Border width is a token, so this has
--- to be re-stated on a theme change rather than fixed at construction. The fill's
--- position and size are the container's business; this only says how far in it sits.
function StatusBarMeta:_anchorFill()
    if not self._fillBox then return end
    self._fillBox:SetChildProps(self._fillFrame, {
        inset          = self:_inset(),
        align          = "start",
        valign         = "stretch",
        widthFraction  = self._pct or 0,
    })
end

--- Recolours the bar fill and background.
function StatusBarMeta:_paint()
    local B = SuuUI.Backdrop
    B.SetBg(self._f, self._bgColor or "colorBgAlt")
    B.SetBorder(self._f, self._showBorder and "colorBorder" or false)
    local r, g, b, a = self._fillColor[1], self._fillColor[2], self._fillColor[3], self._fillColor[4] or 1
    self._bar:SetColorTexture(r, g, b, a)
end

--- Updates the bar fill from the current value/max.
-- The pixel width is the layout engine's job: the fill is a fractional child of the
-- track, so stating the fraction is the whole update. It then stays correct across
-- resizes and border-width changes without this ever running again.
function StatusBarMeta:_updateFill()
    local pct = 0
    if self._max > 0 then
        pct = self._value / self._max
        if pct < 0 then pct = 0 end
        if pct > 1 then pct = 1 end
    end
    self._pct = pct
    if not self._fillBox then return end

    self._fillBox:SetChildFraction(self._fillFrame, "width", pct)
    self:_syncFillVisibility()
end

--- Hides the fill when it rounds below half a pixel.
-- A sub-pixel fill renders as a sliver of colour pinned to the left edge, which reads as
-- a rendering artefact rather than an empty bar.
function StatusBarMeta:_syncFillVisibility()
    if not self._fillFrame then return end
    if (self._fillFrame:GetWidth() or 0) < 0.5 then
        self._fillFrame:Hide()
    else
        self._fillFrame:Show()
    end
end

--- Restyles for theme changes.
function StatusBarMeta:ApplyTheme()
    SuuUI.Backdrop.Apply(self._f, {
        bg     = self._bgColor or "colorBgAlt",
        border = self._showBorder and "colorBorder" or false,
        inset  = self:_inset(),
    })
    self:_anchorFill()
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
    if self._barBox  then self._barBox:Destroy();  self._barBox  = nil end
    if self._fillBox then self._fillBox:Destroy(); self._fillBox = nil end
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

    -- Fill frame: a child frame holding the fill texture. Both are placed by host
    -- containers below, never by hand — the fill is a fractional child of the track.
    local fillFrame = CreateFrame("Frame", nil, f)

    local bar = fillFrame:CreateTexture(nil, "ARTWORK")
    bar:SetTexture(WHITE)

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

    -- The track hosts the fill; the fill hosts its texture. Two adopted containers, no
    -- extra frames, and not one point set by this component.
    handle._fillBox = SuuUI.Layout:CreateContainer({ host = f, layout = "stack" })
    handle._fillBox:Add(fillFrame, {
        inset         = handle:_inset(),
        align         = "start",
        valign        = "stretch",
        widthFraction = 0,
    })
    handle._barBox = SuuUI.Layout:CreateContainer({ host = fillFrame, layout = "stack" })
    handle._barBox:Add(bar)

    -- Chain the container's own resize handler rather than replacing it: the container
    -- must re-flow the fill first, so the visibility check below reads a fresh width.
    local prevSize = f:GetScript("OnSizeChanged")
    f:SetScript("OnSizeChanged", function(self_, w, h)
        if prevSize then prevSize(self_, w, h) end
        handle:_syncFillVisibility()
        S:Emit(handle, S.SIGNALS.SIZE_CHANGED, w, h)
    end)

    handle:ApplyTheme()
    SuuUI.Events:On("SUUUI_THEME_CHANGED", function() handle:ApplyTheme() end, id)
    return handle
end
