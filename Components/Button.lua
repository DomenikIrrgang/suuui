local S = SuuUI.UISignals

local BtnMeta = {}
BtnMeta.__index = BtnMeta

function BtnMeta:GetWidth()      return self._f:GetWidth() end
function BtnMeta:GetHeight()     return self._f:GetHeight() end
function BtnMeta:IsShown()       return self._f:IsShown() end
function BtnMeta:GetFrame()      return self._f end

function BtnMeta:SetSize(w, h)
    self._f:SetSize(w, h)
    S:Emit(self, S.SIGNALS.SIZE_CHANGED, w, h)
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

--- Updates button label text.
-- @param text string
function BtnMeta:SetLabel(text)
    self._label:SetText(text)
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
end

--- Creates a fully custom styled button.
-- Emits CLICKED (button), MOUSE_ENTER, MOUSE_LEAVE, ENABLED_CHANGED.
-- @param props table  { label, onClick, w, h }
-- @param parent frame
-- @return table  Button handle
function SuuUI.Components.Button(props, parent)
    local f = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    f:SetSize(props.w or 100, props.h or 24)
    f:EnableMouse(true)

    -- Internal layout runs through the engine, hosted on the button's own frame
    local box = SuuUI.Layout:CreateContainer({ host = f, layout = "stack" })

    local lbl = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    lbl:SetText(props.label or "")
    box:Add(lbl, { align = "center", valign = "center" })

    local id = "btn_" .. tostring(f)
    local handle = setmetatable({
        _f=f, _label=lbl, _box=box, _eid=id, _enabled=true,
    }, BtnMeta)

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
