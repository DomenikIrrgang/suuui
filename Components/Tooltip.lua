local TipMeta = {}
TipMeta.__index = TipMeta

function TipMeta:Destroy() SuuUI.Events:Off("SUUUI_THEME_CHANGED", self._eid) end
function TipMeta:SetEnabled() end
function TipMeta:GetFrame()   return self._f end
function TipMeta:SetSize()    end
function TipMeta:SetPoint()   end
function TipMeta:IsShown()    return self._f:IsShown() end

--- Shows the tooltip with text, following the cursor.
-- @param text string
-- @param anchorFrame frame|nil  If provided, anchors to frame instead of cursor
function TipMeta:ShowTip(text, anchorFrame)
    self._text:SetText(text or "")
    local tw = self._text:GetStringWidth() + 16
    local th = self._text:GetStringHeight() + 10
    self._f:SetSize(tw, th)
    self._f:ClearAllPoints()
    if anchorFrame then
        self._f:SetPoint("BOTTOM", anchorFrame, "TOP", 0, 4)
    else
        local cx, cy = GetCursorPosition()
        local scale  = UIParent:GetEffectiveScale()
        self._f:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT",
            cx / scale + 12, cy / scale + 12)
    end
    self._f:SetFrameStrata("TOOLTIP")
    self._f:SetAlpha(0)
    self._f:Show()
    SuuUI.Anim.Presets.FadeIn(self._f, SuuUI.Theme:GetToken("animFast"))
end

--- Hides the tooltip.
function TipMeta:HideTip()
    SuuUI.Anim.Presets.FadeOut(self._f, SuuUI.Theme:GetToken("animFast"))
end

function TipMeta:Show() self._f:Show() end
function TipMeta:Hide() self._f:Hide() end

function TipMeta:ApplyTheme()
    local T  = SuuUI.Theme
    local bg = T:GetToken("colorBg")
    local bd = T:GetToken("colorBorder")
    local bw = T:GetToken("borderWidth") or 1
    local tc = T:GetToken("colorText")
    self._f:SetBackdrop({
        bgFile="Interface\\Buttons\\WHITE8x8", edgeFile="Interface\\Buttons\\WHITE8x8",
        edgeSize=bw, insets={left=bw,right=bw,top=bw,bottom=bw},
    })
    if bg then self._f:SetBackdropColor(bg[1], bg[2], bg[3], bg[4]) end
    if bd then self._f:SetBackdropBorderColor(bd[1], bd[2], bd[3], bd[4]) end
    self._text:SetFont(T:GetToken("fontFamilyMain") or "Fonts/FRIZQT__.TTF",
        T:GetToken("fontSizeSm") or 11, "")
    if tc then self._text:SetTextColor(tc[1], tc[2], tc[3], tc[4]) end
end

--- Creates a tooltip component (shared, attach to any trigger frame manually).
-- @param props table  {}
-- @param parent frame
-- @return table  Tooltip handle
function SuuUI.Components.Tooltip(props, parent)
    local f = CreateFrame("Frame", nil, parent or UIParent, "BackdropTemplate")
    f:SetSize(100, 30)
    f:Hide()

    local text = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    text:SetPoint("CENTER")
    text:SetWordWrap(false)

    local id = "tip_" .. tostring(f)
    local handle = setmetatable({ _f=f, _text=text, _eid=id }, TipMeta)
    handle:ApplyTheme()
    SuuUI.Events:On("SUUUI_THEME_CHANGED", function() handle:ApplyTheme() end, id)
    return handle
end
