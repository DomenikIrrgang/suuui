local S = SuuUI.UISignals

local variantMap = {
    bg          = "colorBg",
    bgAlt       = "colorBgAlt",
    bgActive    = "colorBgActive",
    transparent = nil,
}

local FrameMeta = {}
FrameMeta.__index = FrameMeta

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
    if self._panel then self._panel:Destroy() end
    if self._box then self._box:Destroy() end
    self._f:Hide()
end

function FrameMeta:ApplyTheme()
    local bgKey = variantMap[self._variant]
    local borderKey = self._border ~= false and "colorBorder" or false
    -- A ROUNDED frame is drawn from masked textures rather than a backdrop, because a backdrop's
    -- corners are its texture's corners. The two are mutually exclusive: applying a backdrop as well
    -- would show its square corners through the rounding, which is why nothing calls Apply here.
    if self._panel then
        self._panel:Refresh()
        self._panel:SetBg(bgKey)
        self._panel:SetBorder(borderKey)
    else
        SuuUI.Backdrop.Apply(self._f, {
            bg     = bgKey,
            border = borderKey,
        })
    end
    -- Re-apply the fade because opacityDisabled is a user-editable token and may have
    -- changed alongside the theme switch.
    self:_applyEnabled()
end

-- Fills in GetWidth, GetHeight, IsShown, GetFrame, SetSize, Show, Hide.
SuuUI.Components.InstallBase(FrameMeta, "_f")

-- Fills in SetEnabled, IsEnabled, _applyEnabled. Frame is a passive container: it
-- never enables mouse on its own, so the remembered-mouse-state logic in InstallEnable
-- correctly avoids forcing mouse back on after a disable/enable round-trip.
SuuUI.Components.InstallEnable(FrameMeta, "_f")

--- Creates a styled frame container.
-- @param props table  { w, h, alpha, variant, border, rounded, radius }
--   variant: "bg"|"bgAlt"|"bgActive"|"transparent" (default "bg")
--   border: false to hide the border
--   rounded: true to draw a rounded surface (Backdrop.Panel) instead of a square backdrop.
--     Opt-in rather than the default: turning it on everywhere would restyle every panel in the
--     addon at once, and rounding is a per-surface decision -- a full-bleed strip like the data bar
--     wants square corners against the screen edge.
--   radius: corner radius override; defaults to the borderRadius token.
-- @param parent frame
-- @return table  Frame handle
function SuuUI.Components.Frame(props, parent)
    -- A rounded frame is built as a PLAIN frame. This is DEFENSIVE rather than the actual guard, and
    -- mutation testing proved it: restoring the template changes nothing observable, because the
    -- rounded branch in ApplyTheme never calls Backdrop.Apply, so no backdrop is ever set on it. The
    -- ApplyTheme branch is the load-bearing half and is what the spec pins. Kept anyway -- a frame
    -- carrying no backdrop template cannot later be handed one by accident.
    local f = CreateFrame("Frame", nil, parent, not props.rounded and "BackdropTemplate" or nil)
    -- Each axis is applied on its own: a caller that pins only one leaves the other for
    -- the containing layout to decide.
    if props.w then f:SetWidth(props.w) end
    if props.h then f:SetHeight(props.h) end
    if props.alpha then f:SetAlpha(props.alpha) end

    local id = "frame_" .. tostring(f)
    local handle = setmetatable({
        _f       = f,
        _eid     = id,
        _variant = props.variant or "bg",
        _border  = props.border,
    }, FrameMeta)

    -- THE RESIZE SCRIPT GOES FIRST, before anything adopts this frame. Backdrop.Panel installs its own
    -- OnSizeChanged (chaining whatever it finds) so its pieces re-derive when the frame changes size --
    -- and building the panel BEFORE this line meant this SetScript replaced that hook outright. The
    -- panel then never followed a resize: measured in game as a grid plate that kept its previous,
    -- larger size after the window shrank, drawing a dark rounded band below the window's own content.
    --
    -- Exactly the trap LAYOUT_SYSTEM.md names -- "register a frame's own resize script before adopting
    -- it" -- and the same one that had Glass not tracking its window. Both orderings are one line
    -- apart and only one of them works.
    f:SetScript("OnSizeChanged", function(_, w, h)
        S:Emit(handle, S.SIGNALS.SIZE_CHANGED, w, h)
    end)

    if props.rounded then
        handle._panel = SuuUI.Backdrop.Panel(f, { radius = props.radius })
    end

    handle:ApplyTheme()
    SuuUI.Events:On("SUUUI_THEME_CHANGED", function() handle:ApplyTheme() end, id)
    return handle
end
