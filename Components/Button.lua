local S = SuuUI.UISignals
local max, min, abs = math.max, math.min, math.abs

local BtnMeta = {}
BtnMeta.__index = BtnMeta

function BtnMeta:GetWidth()      return self._f:GetWidth() end
function BtnMeta:GetHeight()     return self._f:GetHeight() end
function BtnMeta:IsShown()       return self._f:IsShown() end
function BtnMeta:GetFrame()      return self._f end

--- Sets an explicit size, dropping auto-sizing on both axes.
-- SIZE_CHANGED comes from the frame's resize hook, so layout-driven and explicit
-- resizes behave identically.
-- @param w number
-- @param h number
function BtnMeta:SetSize(w, h)
    self._autoW, self._autoH = false, false
    self._f:SetSize(w, h)
end

function BtnMeta:Show()
    self._f:Show()
    S:Emit(self, S.SIGNALS.VISIBILITY_CHANGED, true)
end

function BtnMeta:Hide()
    self._f:Hide()
    S:Emit(self, S.SIGNALS.VISIBILITY_CHANGED, false)
end

function BtnMeta:Destroy()
    S:DisconnectAll(self)
    SuuUI.Events:Off("SUUUI_THEME_CHANGED", self._eid)
    self._box:Destroy()
    self._f:Hide()
end

-- Pins the label to its measured size, clamped to the button's inner box, so the
-- text is centred and fully visible rather than stretched to a stale width.
function BtnMeta:_layoutLabel()
    local avail = max(0, (self._f:GetWidth() or 0) - self._padX * 2)
    local w = min(self._textW or 0, avail)
    local h = self._textH or 0
    if abs((self._lblW or -1) - w) <= 0.5 and abs((self._lblH or -1) - h) <= 0.5 then return end
    self._lblW, self._lblH = w, h
    local p = self._lblProps
    p.width, p.height = w, h
    self._box:SetChildProps(self._label, p)
end

-- Measures the label and, on any axis the caller did not pin, sizes the button to
-- the text plus padding. A parent layout that resizes the frame is not fought: that
-- path only re-clamps the label.
function BtnMeta:_autosize()
    -- Measured on the shared probe, never on the label: a font string's own
    -- GetStringWidth is clamped to the width the layout gave it, so a truncated label
    -- would keep re-measuring smaller until only an ellipsis was left.
    local tw, th = SuuUI.TextMetrics.Measure(
        self._label:GetText(), self._font, self._fontSize, self._fontFlags)
    if th <= 0 then th = self._fontSize or 13 end
    -- A pixel of slack: pinning a font string to exactly its measured width can still
    -- trip truncation on rounding.
    self._textW, self._textH = tw + 2, th

    local f = self._f
    local w = self._autoW and max(self._textW + self._padX * 2, self._minW)
              or (f:GetWidth() or 0)
    local h = self._autoH and max(self._textH + self._padY * 2, self._minH)
              or (f:GetHeight() or 0)

    if abs(w - (f:GetWidth() or 0)) > 0.5 or abs(h - (f:GetHeight() or 0)) > 0.5 then
        f:SetSize(w, h)
    end
    self:_layoutLabel()
end

--- Updates button label text. Re-fits the button to the new text.
-- @param text string
function BtnMeta:SetLabel(text)
    self._label:SetText(text)
    self:_autosize()
    S:Emit(self, S.SIGNALS.TEXT_CHANGED, text)
end

--- Returns the button label text.
-- @return string
function BtnMeta:GetLabel()
    return self._label:GetText()
end

--- Enables or disables the button. Emits ENABLED_CHANGED.
-- @param en bool
function BtnMeta:SetEnabled(en)
    self._enabled = en
    self._f:EnableMouse(en)
    self:ApplyTheme()
    S:Emit(self, S.SIGNALS.ENABLED_CHANGED, en)
end

function BtnMeta:ApplyTheme()
    local T   = SuuUI.Theme
    local bg  = T:GetToken(self._enabled ~= false and "colorBgAlt" or "colorBgActive")
    local bd  = T:GetToken("colorBorder")
    local bw  = T:GetToken("borderWidth") or 1
    local tc  = T:GetToken(self._enabled ~= false and "colorText" or "colorTextDisable")
    local font= T:GetToken("fontFamilyMain") or "Fonts/FRIZQT__.TTF"
    local sz  = T:GetToken("fontSizeMd") or 13
    self._f:SetBackdrop({
        bgFile="Interface\\Buttons\\WHITE8x8", edgeFile="Interface\\Buttons\\WHITE8x8",
        edgeSize=bw, insets={left=bw,right=bw,top=bw,bottom=bw},
    })
    if bg then self._f:SetBackdropColor(bg[1], bg[2], bg[3], bg[4]) end
    if bd then self._f:SetBackdropBorderColor(bd[1], bd[2], bd[3], bd[4]) end
    if tc then self._label:SetTextColor(tc[1], tc[2], tc[3], tc[4]) end
    self._label:SetFont(font, sz, "")

    -- Padding is token-driven and text metrics move with the font tokens, so both are
    -- re-read here and the button re-fits itself.
    self._font, self._fontSize, self._fontFlags = font, sz, ""
    self._padX = self._padXProp or (T:GetToken("spaceMd") or 8) + bw
    self._padY = self._padYProp or (T:GetToken("spaceSm") or 4) + bw
    self:_autosize()
end

--- Creates a fully custom styled button that hugs its label.
-- Width and height are measured from the text plus token padding unless w/h are
-- given. Emits CLICKED (button), MOUSE_ENTER, MOUSE_LEAVE, ENABLED_CHANGED,
-- TEXT_CHANGED, SIZE_CHANGED.
-- @param props table  { label, onClick, w, h, minW, minH, padX, padY }
-- @param parent frame
-- @return table  Button handle
function SuuUI.Components.Button(props, parent)
    local f = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    f:SetSize(props.w or 1, props.h or 1)
    f:EnableMouse(true)

    local handle

    -- Registered before the host container adopts the frame so the container chains
    -- onto this hook instead of replacing it.
    f:SetScript("OnSizeChanged", function(_, w, h)
        if not (handle and handle._box) then return end
        handle:_layoutLabel()
        S:Emit(handle, S.SIGNALS.SIZE_CHANGED, w, h)
    end)

    -- Internal layout runs through the engine, hosted on the button's own frame
    local box = SuuUI.Layout:CreateContainer({ host = f, layout = "stack" })

    local lbl = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    lbl:SetJustifyH("CENTER")
    lbl:SetJustifyV("MIDDLE")
    lbl:SetWordWrap(false)
    lbl:SetText(props.label or "")

    local id = "btn_" .. tostring(f)
    handle = setmetatable({
        _f=f, _label=lbl, _box=box, _eid=id, _enabled=true,
        _autoW = props.w == nil,
        _autoH = props.h == nil,
        _minW  = props.minW or 0,
        _minH  = props.minH or 0,
        _padXProp = props.padX,
        _padYProp = props.padY,
        _padX = 8, _padY = 4,
        _font = "Fonts/FRIZQT__.TTF", _fontSize = 13, _fontFlags = "",
        _lblProps = { align = "center", valign = "center" },
    }, BtnMeta)

    box:Add(lbl, handle._lblProps)

    local T = SuuUI.Theme
    f:SetScript("OnEnter", function()
        if handle._enabled == false then return end
        local c = T:GetToken("colorBgHover")
        if c then f:SetBackdropColor(c[1], c[2], c[3], c[4]) end
        local ac = T:GetToken("colorBorderFocus")
        if ac then f:SetBackdropBorderColor(ac[1], ac[2], ac[3], ac[4]) end
        S:Emit(handle, S.SIGNALS.MOUSE_ENTER)
    end)
    f:SetScript("OnLeave", function()
        handle:ApplyTheme()
        S:Emit(handle, S.SIGNALS.MOUSE_LEAVE)
    end)
    f:SetScript("OnMouseDown", function()
        if handle._enabled == false then return end
        local c = T:GetToken("colorBgActive")
        if c then f:SetBackdropColor(c[1], c[2], c[3], c[4]) end
        SuuUI.Anim.Presets.ScalePop(f)
    end)
    f:SetScript("OnMouseUp", function(_, btn)
        if handle._enabled == false then return end
        handle:ApplyTheme()
        if props.onClick then props.onClick() end
        S:Emit(handle, S.SIGNALS.CLICKED, btn or "LeftButton")
    end)

    handle:ApplyTheme()
    SuuUI.Events:On("SUUUI_THEME_CHANGED", function() handle:ApplyTheme() end, id)
    return handle
end
