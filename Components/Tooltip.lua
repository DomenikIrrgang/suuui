local C = SuuUI.Components
local S = SuuUI.UISignals

-- Vertical padding around the tip text. Tighter than any space token (spaceXs is 4 a
-- side, spaceSm 8), so it stays a named constant rather than forcing a token to fit.
local PAD_Y = 10

local TipMeta = {}
TipMeta.__index = TipMeta

-- SIZE_CHANGED is emitted here rather than from a frame resize hook: the tooltip's
-- frame is sized through the shared floating host on every ShowTip, and reporting
-- that as a consumer-visible resize would be noise.
function TipMeta:SetSize(w, h)
    self._f:SetSize(w, h)
    S:Emit(self, S.SIGNALS.SIZE_CHANGED, w, h)
end

function TipMeta:Destroy()
    S:DisconnectAll(self)
    SuuUI.Events:Off("SUUUI_THEME_CHANGED", self._eid)
    self._textT:Destroy()
    self._box:Destroy()
    -- The floating host is shared: drop our frame, never destroy the host
    self._host:Remove(self._f)
    self._f:Hide()
end

-- Sizes the tip to its text plus padding and re-applies the stored anchor. Measured
-- through TextMetrics, not the live font string: the layout has already assigned it the
-- previous tip's width, and GetStringWidth is clamped to that, so a longer second tip
-- would report the shorter box and never grow. The height comes off the Text handle,
-- which re-measures itself whenever a font token changes.
function TipMeta:_fit()
    local fs = self._text
    local font, size, flags = fs:GetFont()
    local mw = SuuUI.TextMetrics.Measure(fs:GetText() or "", font, size, flags)
    local padX = (SuuUI.Theme:GetToken("spaceSm") or 8) * 2

    local a = self._anchor
    a.width  = mw + padX
    a.height = (self._textT:GetHeight() or 0) + PAD_Y
    self._host:SetChildAnchor(self._f, a)
    -- A font token change resizes nothing on its own, so nothing else re-measures the
    -- centred label. Re-run the box so the client is never handed a stale text box.

end

--- Shows the tooltip with text, following the cursor.
-- Emits VISIBILITY_CHANGED.
-- @param text string
-- @param anchorFrame frame|nil  If provided, anchors to frame instead of cursor
function TipMeta:ShowTip(text, anchorFrame)
    self._textT:SetText(text or "")

    -- Placement goes through the anchor container, never SetPoint
    local T = SuuUI.Theme
    local a = self._anchor
    if anchorFrame then
        a.point, a.relativeTo, a.relativePoint = "BOTTOM", anchorFrame, "TOP"
        a.x, a.y = 0, T:GetToken("spaceXs") or 4
    else
        -- The offset is applied inside the tooltip's own container, so the cursor has to
        -- be read in the tooltip's space rather than UIParent's.
        local cx, cy = SuuUI.Pixel.CursorIn(self._f)
        local off    = T:GetToken("spaceMd") or 12
        a.point, a.relativeTo, a.relativePoint = "BOTTOMLEFT", nil, "BOTTOMLEFT"
        a.x, a.y = cx + off, cy + off
    end
    self:_fit()

    SuuUI.UIRoot:SetLayer(self._f, "tooltip")
    self._f:SetAlpha(0)
    self._f:Show()
    SuuUI.Anim.Presets.FadeIn(self._f, T:GetToken("animFast"))
    S:Emit(self, S.SIGNALS.VISIBILITY_CHANGED, true)
end

--- Hides the tooltip. Emits VISIBILITY_CHANGED.
function TipMeta:HideTip()
    SuuUI.Anim.Presets.FadeOut(self._f, SuuUI.Theme:GetToken("animFast"))
    S:Emit(self, S.SIGNALS.VISIBILITY_CHANGED, false)
end

function TipMeta:Show() self:ShowTip(self._text:GetText()) end
function TipMeta:Hide() self:HideTip() end

function TipMeta:ApplyTheme()
    SuuUI.Backdrop.Apply(self._f, { bg = "colorBg", border = "colorBorder" })
    -- Applied here rather than left to the Text component's own theme handler because
    -- the event bus fires listeners newest-first: the tip would otherwise re-fit itself
    -- against the previous font.
    self._textT:ApplyTheme()
    self:_fit()
end

-- Fills in GetWidth, GetHeight, IsShown, GetFrame. Show, Hide and SetSize are defined
-- above and survive: Show/Hide take anchor args and animate, and SetSize emits.
SuuUI.Components.InstallBase(TipMeta, "_f")

--- Creates a tooltip component. Connect MOUSE_ENTER/MOUSE_LEAVE on a trigger
-- component and call ShowTip/HideTip from the handler.
-- @param props table  {}
-- @param parent frame
-- @return table  Tooltip handle
function SuuUI.Components.Tooltip(props, parent)
    parent = parent or UIParent

    -- Shared floating host owns where the tooltip sits
    local host = SuuUI.Layout:GetFloatingHost()

    local f = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    f:SetSize(100, 30)
    f:Hide()

    -- One descriptor, rewritten in place on each ShowTip, so the tip never accumulates
    -- anchors and a re-fit can update only its size.
    local anchor = { point = "CENTER", x = 0, y = 0 }
    host:Add(f, { anchor = anchor })

    local box = SuuUI.Layout:CreateContainer({ host = f, layout = "stack" })
    -- Text owns the font and colour tokens and re-measures itself when they change,
    -- which a hand-rolled font string does not.
    local textT = C.Text({ size = "sm", color = "text", justify = "CENTER", wrap = false }, f)
    box:Add(textT, { align = "center", valign = "center" })

    local id = "tip_" .. tostring(f)
    local handle = setmetatable({
        _f = f, _host = host, _box = box, _anchor = anchor, _eid = id,
        -- _text stays the font string so callers and specs reach the same region;
        -- _textT is the Text handle that owns it.
        _textT = textT, _text = textT:GetFrame(),
    }, TipMeta)
    handle:ApplyTheme()
    SuuUI.Events:On("SUUUI_THEME_CHANGED", function() handle:ApplyTheme() end, id)
    return handle
end
