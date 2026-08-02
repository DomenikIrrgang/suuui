local IcoMeta = {}
IcoMeta.__index = IcoMeta

function IcoMeta:SetSize(w, h)  self._f:SetSize(w, h) end
function IcoMeta:SetPoint(...)  self._f:SetPoint(...) end
function IcoMeta:Show()         self._f:Show() end
function IcoMeta:Hide()         self._f:Hide() end
function IcoMeta:IsShown()      return self._f:IsShown() end
function IcoMeta:GetFrame()     return self._f end
function IcoMeta:SetEnabled(en)
    self._enabled = en
    self._f:EnableMouse(en)
    self._icon:SetDesaturated(not en)
end
function IcoMeta:Destroy()
    SuuUI.Events:Off("SUUUI_THEME_CHANGED", self._eid)
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
-- @param props table  { icon, onClick, w, h, padding }
-- @param parent frame
-- @return table  IconButton handle
function SuuUI.Components.IconButton(props, parent)
    local size = props.w or 24
    local pad  = props.padding or 3
    local f    = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    f:SetSize(size, size)
    f:EnableMouse(true)

    local icon = f:CreateTexture(nil, "ARTWORK")
    icon:SetPoint("TOPLEFT",     f, "TOPLEFT",     pad,  -pad)
    icon:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -pad,  pad)
    if props.icon then icon:SetTexture(props.icon) end

    local id = "ico_" .. tostring(f)
    local handle = setmetatable({ _f=f, _icon=icon, _eid=id, _enabled=true }, IcoMeta)

    local T = SuuUI.Theme
    f:SetScript("OnEnter", function()
        if handle._enabled == false then return end
        local c = T:GetToken("colorBgHover")
        if c then f:SetBackdropColor(c[1], c[2], c[3], c[4]) end
    end)
    f:SetScript("OnLeave", function() handle:ApplyTheme() end)
    f:SetScript("OnMouseUp", function()
        if handle._enabled == false then return end
        SuuUI.Anim.Presets.ScalePop(f)
        if props.onClick then props.onClick() end
    end)

    handle:ApplyTheme()
    SuuUI.Events:On("SUUUI_THEME_CHANGED", function() handle:ApplyTheme() end, id)
    return handle
end
