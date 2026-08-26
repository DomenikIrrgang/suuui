local S = SuuUI.UISignals

local IcoMeta = {}
IcoMeta.__index = IcoMeta

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

--- Re-tints the art with a colour TOKEN key, or clears the tint with nil.
---
--- Stores the key rather than the resolved colour, so _paint and ApplyTheme keep re-resolving it and
--- a live theme edit reaches a button that is already sitting in its non-default colour. That is the
--- same reason `iconColor` was a key at construction rather than an RGBA.
---
--- Exists because a title-bar control that TOGGLES A MODE has to look different while the mode is
--- on -- otherwise it is a button that fires and forgets, which is exactly how the keybind control
--- read before it had this.
-- @param tokenKey string|nil  e.g. "colorAccent"
function IcoMeta:SetIconColor(tokenKey)
    self._iconColor = tokenKey
    if not self._icon then return end
    if not tokenKey then
        self._icon:SetVertexColor(1, 1, 1, 1)
        return
    end
    local col = SuuUI.Theme:GetToken(tokenKey)
    if col then self._icon:SetVertexColor(col[1], col[2], col[3], col[4]) end
end

--- The colour token the art is tinted with, or nil.
-- @return string|nil
function IcoMeta:GetIconColor()
    return self._iconColor
end

--- Marks the button as ON, for a control that toggles something rather than firing once.
---
--- TWO CHANNELS, deliberately: an accent BORDER plus an accent glyph. One channel is not enough --
--- a tint alone was reported as "it's a button right now not a toggle", because a slightly different
--- glyph colour is not a state a player reads at a glance in a title strip. The border is the same
--- "this is the live one" signal edit mode's overlay and the stance bar's active form already use.
---
--- Stored rather than applied-and-forgotten, because _paint runs on every hover and leave and would
--- otherwise reset the border to colorBorder the first time the pointer crossed the button.
-- @param on bool
function IcoMeta:SetActive(on)
    self._active = on and true or false
    self:SetIconColor(self._active and (self._activeColor or "colorAccent") or self._restColor)
    self:_paint()
end

--- Whether the button is currently marked on.
-- @return bool
function IcoMeta:IsActive()
    return self._active == true
end

-- Surface and border only, so leaving hover never rebuilds the backdrop table.
function IcoMeta:_paint()
    local B = SuuUI.Backdrop
    B.SetBg(self._f, "colorBgAlt")
    -- ACTIVE OUTRANKS THE RESTING BORDER. _paint runs on hover and on leave, so an active border
    -- applied from outside would be wiped the first time the pointer crossed the button -- the state
    -- has to be consulted here rather than painted once.
    B.SetBorder(self._f, self._active and (self._activeColor or "colorAccent") or "colorBorder")
    -- The art's tint is a token like everything else here, so it is re-resolved rather than left
    -- at whatever it was at construction. Without this, editing colorAccent moved every other
    -- accent in the UI and left the sort icon on the old hue.
    if self._iconColor and self._icon then
        local col = SuuUI.Theme:GetToken(self._iconColor)
        if col then self._icon:SetVertexColor(col[1], col[2], col[3], col[4]) end
    end
end

function IcoMeta:ApplyTheme()
    SuuUI.Backdrop.Apply(self._f, { bg = "colorBgAlt", border = "colorBorder" })
    self:_paint()
    -- A live opacityDisabled edit reaches an already-disabled widget.
    self:_applyEnabled()
end

-- Fills in GetWidth, GetHeight, IsShown, GetFrame, SetSize, Show, Hide.
SuuUI.Components.InstallBase(IcoMeta, "_f")
-- Installs SetEnabled, IsEnabled, _applyEnabled via the canonical fade mechanism.
SuuUI.Components.InstallEnable(IcoMeta, "_f")

--- Creates an icon button.
-- Emits CLICKED (button), MOUSE_ENTER, MOUSE_LEAVE, ENABLED_CHANGED.
-- @param props table  { icon, onClick, w, h, padding, coords, iconColor, scalePop }
--   scalePop: false to drop the press pop. REQUIRED for chrome positioned by a token inset -- a
--     title-bar accessory is the case. SetScale reinterprets the frame's own anchor OFFSETS in its
--     scaled space, so a button held at an inset from the strip's edge visibly SLIDES as it pops
--     rather than growing in place. Presets.lua already documented IconButton as accepting this
--     while the call was in fact unconditional.
--   coords: { left, right, top, bottom } as 0..1 fractions, for a glyph on an ATLAS -- one sheet
--     holds many icons, so the texture alone cannot say which one. See SuuUI.Icons.
--   iconColor: a colour TOKEN key to tint the art with. The shared sheet is generated white on
--     transparent precisely so the tint decides the colour, which means a theme change needs no
--     new art and a coloured sheet would ignore the theme.
-- @param parent frame
-- @return table  IconButton handle
function SuuUI.Components.IconButton(props, parent)
    -- Square by default; h is honoured when a caller wants a non-square hit area.
    local w   = props.w or 24
    local h   = props.h or w
    local pad = props.padding or 3
    local f   = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    f:SetSize(w, h)
    f:EnableMouse(true)

    -- Registered before the host container adopts the frame so the container chains
    -- onto this hook instead of replacing it. A parent layout resizes the frame
    -- directly and never calls SetSize, so this is the only place that sees it.
    local handle
    f:SetScript("OnSizeChanged", function(_, w2, h2)
        if not handle then return end
        S:Emit(handle, S.SIGNALS.SIZE_CHANGED, w2, h2)
    end)

    local box = SuuUI.Layout:CreateContainer({ host = f, layout = "stack" })

    local icon = f:CreateTexture(nil, "ARTWORK")
    if props.icon then icon:SetTexture(props.icon) end
    -- An atlas glyph needs its coordinates as well as the sheet: one texture holds many icons.
    if props.coords then
        local c = props.coords
        icon:SetTexCoord(c[1], c[2], c[3], c[4])
    end
    -- Tinted rather than drawn in colour, so the sheet stays monochrome and a theme change needs no
    -- new art. The sheet is generated white on transparent for exactly this.
    if props.iconColor then
        local col = SuuUI.Theme:GetToken(props.iconColor)
        if col then icon:SetVertexColor(col[1], col[2], col[3], col[4]) end
        -- KEPT, not applied and forgotten. A token is user-editable, so a tint resolved once at
        -- construction is stale the moment the player edits that colour -- and ApplyTheme had no
        -- way to restate a value it could not read. `_paint` re-asserts it from here.
    end
    box:Add(icon, { inset = pad })

    local id = "ico_" .. tostring(f)
    handle = setmetatable({ _f=f, _icon=icon, _box=box, _eid=id, _enabled=true,
        _iconColor=props.iconColor,
        -- The colour to RETURN to when SetActive(false) runs. Remembered separately from
        -- _iconColor, which SetActive overwrites -- without it, switching a mode off would leave the
        -- glyph on whatever it happened to be tinted at the time.
        _restColor=props.iconColor,
        -- Overridable so a control can signal "on" in something other than accent -- a danger-toned
        -- button that is currently armed, say.
        _activeColor=props.activeColor,
                            _scalePop = props.scalePop ~= false }, IcoMeta)

    f:SetScript("OnEnter", function()
        if handle._enabled == false then return end
        SuuUI.Backdrop.SetBg(f, "colorBgHover")
        S:Emit(handle, S.SIGNALS.MOUSE_ENTER)
    end)
    f:SetScript("OnLeave", function()
        handle:_paint()
        S:Emit(handle, S.SIGNALS.MOUSE_LEAVE)
    end)
    f:SetScript("OnMouseUp", function(_, btn)
        if handle._enabled == false then return end
        if handle._scalePop then SuuUI.Anim.Presets.ScalePop(f) end
        if props.onClick then props.onClick() end
        S:Emit(handle, S.SIGNALS.CLICKED, btn or "LeftButton")
    end)

    handle:ApplyTheme()
    SuuUI.Events:On("SUUUI_THEME_CHANGED", function() handle:ApplyTheme() end, id)
    return handle
end
