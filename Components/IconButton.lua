local S = SuuUI.UISignals

local IcoMeta = {}
IcoMeta.__index = IcoMeta

function IcoMeta:GetWidth()     return self._f:GetWidth() end
function IcoMeta:GetHeight()    return self._f:GetHeight() end
function IcoMeta:IsShown()      return self._f:IsShown() end
function IcoMeta:GetFrame()     return self._f end

function IcoMeta:SetSize(w, h)
    self._f:SetSize(w, h)
    S:Emit(self, S.SIGNALS.SIZE_CHANGED, w, h)
end

function IcoMeta:Show()
    self._f:Show()
    S:Emit(self, S.SIGNALS.VISIBILITY_CHANGED, true)
end

function IcoMeta:Hide()
    self._f:Hide()
    S:Emit(self, S.SIGNALS.VISIBILITY_CHANGED, false)
end

--- Enables or disables the button. Emits ENABLED_CHANGED.
-- @param en bool
function IcoMeta:SetEnabled(en)
    self._enabled = en
    self._f:EnableMouse(en)
    self._icon:SetDesaturated(not en)
    S:Emit(self, S.SIGNALS.ENABLED_CHANGED, en)
end

function IcoMeta:Destroy()
    S:DisconnectAll(self)
    SuuUI.Events:Off("SUUUI_THEME_CHANGED", self._eid)
    self._box:Destroy()
    self._f:Hide()
end

--- Sets the icon texture path.
-- @param path string
function IcoMeta:SetIcon(path)
    self._icon:SetTexture(path)
end

function IcoMeta:ApplyTheme()
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
end

--- Creates an icon button.
-- Emits CLICKED (button), MOUSE_ENTER, MOUSE_LEAVE, ENABLED_CHANGED.
-- @param props table  { icon, onClick, w, h, padding }
-- @param parent frame
-- @return table  IconButton handle
function SuuUI.Components.IconButton(props, parent)
    local size = props.w or 24
    local pad  = props.padding or 3
    local f    = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    f:SetSize(size, size)
    f:EnableMouse(true)

    local box = SuuUI.Layout:CreateContainer({ host = f, layout = "stack" })

    local icon = f:CreateTexture(nil, "ARTWORK")
    if props.icon then icon:SetTexture(props.icon) end
    box:Add(icon, { inset = pad })

    local id = "ico_" .. tostring(f)
    local handle = setmetatable({ _f=f, _icon=icon, _box=box, _eid=id, _enabled=true }, IcoMeta)

    local T = SuuUI.Theme
    f:SetScript("OnEnter", function()
        if handle._enabled == false then return end
        local c = T:GetToken("colorBgHover")
        if c then f:SetBackdropColor(c[1], c[2], c[3], c[4]) end
        S:Emit(handle, S.SIGNALS.MOUSE_ENTER)
    end)
    f:SetScript("OnLeave", function()
        handle:ApplyTheme()
        S:Emit(handle, S.SIGNALS.MOUSE_LEAVE)
    end)
    f:SetScript("OnMouseUp", function(_, btn)
        if handle._enabled == false then return end
        SuuUI.Anim.Presets.ScalePop(f)
        if props.onClick then props.onClick() end
        S:Emit(handle, S.SIGNALS.CLICKED, btn or "LeftButton")
    end)

    handle:ApplyTheme()
    SuuUI.Events:On("SUUUI_THEME_CHANGED", function() handle:ApplyTheme() end, id)
    return handle
end
