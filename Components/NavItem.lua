local S = SuuUI.UISignals

local NavMeta = {}
NavMeta.__index = NavMeta

function NavMeta:GetWidth()     return self._f:GetWidth() end
function NavMeta:GetHeight()    return self._f:GetHeight() end
function NavMeta:IsShown()      return self._f:IsShown() end
function NavMeta:GetFrame()     return self._f end

function NavMeta:SetSize(w, h)
    self._f:SetSize(w, h)
    S:Emit(self, S.SIGNALS.SIZE_CHANGED, w, h)
end

function NavMeta:Show()
    self._f:Show()
    S:Emit(self, S.SIGNALS.VISIBILITY_CHANGED, true)
end

function NavMeta:Hide()
    self._f:Hide()
    S:Emit(self, S.SIGNALS.VISIBILITY_CHANGED, false)
end

function NavMeta:Destroy()
    S:DisconnectAll(self)
    SuuUI.Events:Off("SUUUI_THEME_CHANGED", self._eid)
    self._box:Destroy()
    self._f:Hide()
end

--- Enables or disables the item. Emits ENABLED_CHANGED.
-- @param en bool
function NavMeta:SetEnabled(en)
    self._enabled = en
    self._f:EnableMouse(en)
    self:ApplyTheme()
    S:Emit(self, S.SIGNALS.ENABLED_CHANGED, en)
end

--- Sets the label text.
-- @param text string
function NavMeta:SetLabel(text)
    self._label:SetText(text)
    S:Emit(self, S.SIGNALS.TEXT_CHANGED, text)
end

--- Returns whether the item is selected.
-- @return bool
function NavMeta:IsSelected()
    return self._selected
end

--- Sets the selected state. Does not emit VALUE_CHANGED.
-- @param selected bool
function NavMeta:SetSelected(selected)
    self._selected = selected == true
    self._hovered  = false
    self:ApplyTheme()
end

function NavMeta:ApplyTheme()
    local T  = SuuUI.Theme
    local bw = T:GetToken("borderWidth") or 1
    local bgKey
    if self._selected then
        bgKey = "colorBgActive"
    elseif self._hovered then
        bgKey = "colorBgHover"
    else
        bgKey = "colorBg"
    end
    local bg = T:GetToken(bgKey)
    local tc = T:GetToken(self._selected and "colorText" or "colorTextMuted")
    local bd = T:GetToken("colorBorder")

    self._f:SetBackdrop({
        bgFile="Interface\\Buttons\\WHITE8x8",
        edgeFile="Interface\\Buttons\\WHITE8x8",
        edgeSize=bw, insets={left=bw,right=bw,top=bw,bottom=bw},
    })
    if bg then self._f:SetBackdropColor(bg[1], bg[2], bg[3], bg[4]) end
    if bd then self._f:SetBackdropBorderColor(bd[1], bd[2], bd[3], bd[4]) end
    if tc then self._label:SetTextColor(tc[1], tc[2], tc[3], tc[4]) end
    self._label:SetFont(
        T:GetToken("fontFamilyMain") or "Fonts/FRIZQT__.TTF",
        T:GetToken("fontSizeMd") or 13, "")
end

--- Creates a selectable navigation row with a label.
-- Emits CLICKED (button), MOUSE_ENTER, MOUSE_LEAVE, ENABLED_CHANGED.
-- @param props table  { label, selected, w, h }
-- @param parent frame
-- @return table  NavItem handle
function SuuUI.Components.NavItem(props, parent)
    local T = SuuUI.Theme

    local f = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    f:SetSize(props.w or 160, props.h or 32)
    f:EnableMouse(true)

    local box = SuuUI.Layout:CreateContainer({ host = f, layout = "stack" })

    local label = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    label:SetJustifyH("LEFT")
    label:SetText(props.label or "")
    box:Add(label, {
        valign = "center",
        inset  = { left = T:GetToken("spaceSm") or 8, right = T:GetToken("spaceXs") or 4 },
    })

    local id = "nav_" .. tostring(f)
    local handle = setmetatable({
        _f        = f,
        _label    = label,
        _box      = box,
        _eid      = id,
        _enabled  = true,
        _selected = props.selected == true,
        _hovered  = false,
    }, NavMeta)

    f:SetScript("OnMouseUp", function(_, btn)
        if handle._enabled == false then return end
        S:Emit(handle, S.SIGNALS.CLICKED, btn or "LeftButton")
    end)
    f:SetScript("OnEnter", function()
        if handle._enabled == false or handle._selected then return end
        handle._hovered = true
        handle:ApplyTheme()
        S:Emit(handle, S.SIGNALS.MOUSE_ENTER)
    end)
    f:SetScript("OnLeave", function()
        handle._hovered = false
        handle:ApplyTheme()
        S:Emit(handle, S.SIGNALS.MOUSE_LEAVE)
    end)

    handle:ApplyTheme()
    SuuUI.Events:On("SUUUI_THEME_CHANGED", function() handle:ApplyTheme() end, id)
    return handle
end
