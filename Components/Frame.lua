local S = SuuUI.UISignals

local variantMap = {
    bg          = "colorBg",
    bgAlt       = "colorBgAlt",
    bgActive    = "colorBgActive",
    transparent = nil,
}

local FrameMeta = {}
FrameMeta.__index = FrameMeta

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
    local bgKey = variantMap[self._variant]
    if self._enabled == false then bgKey = "colorBgDisabled" end
    SuuUI.Backdrop.Apply(self._f, {
        bg     = bgKey,
        border = self._border ~= false and "colorBorder" or false,
    })
end

-- Fills in GetWidth, GetHeight, IsShown, GetFrame, SetSize, Show, Hide.
SuuUI.Components.InstallBase(FrameMeta, "_f")

--- Creates a styled frame container.
-- @param props table  { w, h, alpha, variant, border }
--   variant: "bg"|"bgAlt"|"bgActive"|"transparent" (default "bg")
--   border: false to hide the border
-- @param parent frame
-- @return table  Frame handle
function SuuUI.Components.Frame(props, parent)
    local f = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    -- Each axis is applied on its own: a caller that pins only one leaves the other for
    -- the containing layout to decide.
    if props.w then f:SetWidth(props.w) end
    if props.h then f:SetHeight(props.h) end
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
