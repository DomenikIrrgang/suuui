local S = SuuUI.UISignals

local variantMap = {
    bg          = "colorBg",
    bgAlt       = "colorBgAlt",
    bgActive    = "colorBgActive",
    transparent = nil,
}

local FrameMeta = {}
FrameMeta.__index = FrameMeta

function FrameMeta:GetWidth()      return self._f:GetWidth() end
function FrameMeta:GetHeight()     return self._f:GetHeight() end
function FrameMeta:IsShown()       return self._f:IsShown() end
function FrameMeta:GetFrame()      return self._f end

function FrameMeta:SetSize(w, h)
    self._f:SetSize(w, h)
    S:Emit(self, S.SIGNALS.SIZE_CHANGED, w, h)
end

function FrameMeta:Show()
    self._f:Show()
    S:Emit(self, S.SIGNALS.VISIBILITY_CHANGED, true)
end

function FrameMeta:Hide()
    self._f:Hide()
    S:Emit(self, S.SIGNALS.VISIBILITY_CHANGED, false)
end

--- Enables or disables the frame. Emits ENABLED_CHANGED.
-- @param en bool
function FrameMeta:SetEnabled(en)
    self._enabled = en
    self:ApplyTheme()
    S:Emit(self, S.SIGNALS.ENABLED_CHANGED, en)
end

--- Returns a container that lays out children inside this frame.
-- @param props table  Optional container props (layout, dir, gap, padding, align)
-- @return table  Container handle
function FrameMeta:GetContainer(props)
    if not self._box then
        props = props or {}
        props.host = self._f
        self._box = SuuUI.Layout:CreateContainer(props)
    end
    return self._box
end

function FrameMeta:Destroy()
    S:DisconnectAll(self)
    SuuUI.Events:Off("SUUUI_THEME_CHANGED", self._eid)
    if self._box then self._box:Destroy() end
    self._f:Hide()
end

function FrameMeta:ApplyTheme()
    local T  = SuuUI.Theme
    local bw = T:GetToken("borderWidth") or 1
    self._f:SetBackdrop({
        bgFile   = "Interface\\Buttons\\WHITE8x8",
        edgeFile = "Interface\\Buttons\\WHITE8x8",
        edgeSize = bw,
        insets   = { left=bw, right=bw, top=bw, bottom=bw },
    })

    local bgKey = variantMap[self._variant]
    if self._enabled == false then bgKey = "colorBgActive" end
    local bg = bgKey and T:GetToken(bgKey)
    if bg then
        self._f:SetBackdropColor(bg[1], bg[2], bg[3], bg[4])
    else
        self._f:SetBackdropColor(0, 0, 0, 0)
    end

    if self._border == false then
        self._f:SetBackdropBorderColor(0, 0, 0, 0)
    else
        local bd = T:GetToken("colorBorder")
        if bd then self._f:SetBackdropBorderColor(bd[1], bd[2], bd[3], bd[4]) end
    end
end

--- Creates a styled frame container.
-- @param props table  { w, h, alpha, variant, border }
--   variant: "bg"|"bgAlt"|"bgActive"|"transparent" (default "bg")
--   border: false to hide the border
-- @param parent frame
-- @return table  Frame handle
function SuuUI.Components.Frame(props, parent)
    local f = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    if props.w and props.h then f:SetSize(props.w, props.h) end
    if props.alpha then f:SetAlpha(props.alpha) end

    local id = "frame_" .. tostring(f)
    local handle = setmetatable({
        _f       = f,
        _eid     = id,
        _enabled = true,
        _variant = props.variant or "bg",
        _border  = props.border,
    }, FrameMeta)

    -- Translate the Blizzard resize script into a signal
    f:SetScript("OnSizeChanged", function(_, w, h)
        S:Emit(handle, S.SIGNALS.SIZE_CHANGED, w, h)
    end)

    handle:ApplyTheme()
    SuuUI.Events:On("SUUUI_THEME_CHANGED", function() handle:ApplyTheme() end, id)
    return handle
end
