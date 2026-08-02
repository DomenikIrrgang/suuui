local S = SuuUI.UISignals

local TipMeta = {}
TipMeta.__index = TipMeta

function TipMeta:SetEnabled() end
function TipMeta:GetFrame()   return self._f end
function TipMeta:GetWidth()   return self._f:GetWidth() end
function TipMeta:GetHeight()  return self._f:GetHeight() end
function TipMeta:IsShown()    return self._f:IsShown() end

function TipMeta:SetSize(w, h)
    self._f:SetSize(w, h)
    S:Emit(self, S.SIGNALS.SIZE_CHANGED, w, h)
end

function TipMeta:Destroy()
    S:DisconnectAll(self)
    SuuUI.Events:Off("SUUUI_THEME_CHANGED", self._eid)
    self._box:Destroy()
    -- The floating host is shared: drop our frame, never destroy the host
    self._host:Remove(self._f)
    self._f:Hide()
end

--- Shows the tooltip with text, following the cursor.
-- Emits VISIBILITY_CHANGED.
-- @param text string
-- @param anchorFrame frame|nil  If provided, anchors to frame instead of cursor
function TipMeta:ShowTip(text, anchorFrame)
    self._text:SetText(text or "")
    local tw = self._text:GetStringWidth() + 16
    local th = self._text:GetStringHeight() + 10

    -- Placement goes through the anchor container, never SetPoint
    if anchorFrame then
        self._host:SetChildAnchor(self._f, {
            point = "BOTTOM", relativeTo = anchorFrame, relativePoint = "TOP",
            x = 0, y = 4, width = tw, height = th,
        })
    else
        local cx, cy = GetCursorPosition()
        local scale  = UIParent:GetEffectiveScale()
        self._host:SetChildAnchor(self._f, {
            point = "BOTTOMLEFT", relativePoint = "BOTTOMLEFT",
            x = cx / scale + 12, y = cy / scale + 12, width = tw, height = th,
        })
    end

    self._f:SetFrameStrata("TOOLTIP")
    self._f:SetAlpha(0)
    self._f:Show()
    SuuUI.Anim.Presets.FadeIn(self._f, SuuUI.Theme:GetToken("animFast"))
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
    host:Add(f, { anchor = { point = "CENTER", x = 0, y = 0 } })

    local box = SuuUI.Layout:CreateContainer({ host = f, layout = "stack" })
    local text = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    text:SetWordWrap(false)
    box:Add(text, { align = "center", valign = "center" })

    local id = "tip_" .. tostring(f)
    local handle = setmetatable({ _f=f, _text=text, _host=host, _box=box, _eid=id }, TipMeta)
    handle:ApplyTheme()
    SuuUI.Events:On("SUUUI_THEME_CHANGED", function() handle:ApplyTheme() end, id)
    return handle
end
