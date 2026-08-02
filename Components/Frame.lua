local type = type

local FrameMeta = {}
FrameMeta.__index = FrameMeta

function FrameMeta:SetSize(w, h)   self._f:SetSize(w, h) end
function FrameMeta:SetPoint(...)   self._f:SetPoint(...) end
function FrameMeta:Show()          self._f:Show() end
function FrameMeta:Hide()          self._f:Hide() end
function FrameMeta:IsShown()       return self._f:IsShown() end
function FrameMeta:GetFrame()      return self._f end

function FrameMeta:SetEnabled(en)
    self._enabled = en
    local T   = SuuUI.Theme
    local col = T:GetToken(en and "colorBg" or "colorBgActive")
    if col then self._f:SetBackdropColor(col[1], col[2], col[3], col[4]) end
end

function FrameMeta:Destroy()
    SuuUI.Events:Off("SUUUI_THEME_CHANGED", self._eid)
    self._f:Hide()
    self._f:SetParent(nil)
end

function FrameMeta:ApplyTheme()
    local T  = SuuUI.Theme
    local bg = T:GetToken("colorBg")
    local bd = T:GetToken("colorBorder")
    local bw = T:GetToken("borderWidth") or 1
    self._f:SetBackdrop({
        bgFile   = "Interface\\Buttons\\WHITE8x8",
        edgeFile = "Interface\\Buttons\\WHITE8x8",
        edgeSize = bw,
        insets   = { left=bw, right=bw, top=bw, bottom=bw },
    })
    if bg then self._f:SetBackdropColor(bg[1], bg[2], bg[3], bg[4]) end
    if bd then self._f:SetBackdropBorderColor(bd[1], bd[2], bd[3], bd[4]) end
end

--- Creates a styled frame container.
-- @param props table  { w, h, alpha }
-- @param parent frame
-- @return table  Frame handle
function SuuUI.Components.Frame(props, parent)
    local f = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    if props.w and props.h then f:SetSize(props.w, props.h) end
    if props.alpha then f:SetAlpha(props.alpha) end

    local id = "frame_" .. tostring(f)
    local handle = setmetatable({ _f=f, _eid=id, _enabled=true }, FrameMeta)
    handle:ApplyTheme()
    SuuUI.Events:On("SUUUI_THEME_CHANGED", function() handle:ApplyTheme() end, id)
    return handle
end
