local S = SuuUI.UISignals

local NavMeta = {}
NavMeta.__index = NavMeta

local function bgKeyFor(self)
    if self._selected then return "colorBgActive" end
    if self._hovered  then return "colorBgHover"  end
    return "colorBg"
end

function NavMeta:Destroy()
    S:DisconnectAll(self)
    SuuUI.Events:Off("SUUUI_THEME_CHANGED", self._eid)
    self._labelText:Destroy()
    self._box:Destroy()
    self._f:Hide()
end

-- SetEnabled is installed by InstallEnable below. No bespoke override needed: the
-- canonical fade + mouse-drop covers both selected and unselected states uniformly.

--- Sets the label text.
-- @param text string
function NavMeta:SetLabel(text)
    self._labelText:SetText(text)
    if self._autoW then self:_autosize() end
    S:Emit(self, S.SIGNALS.TEXT_CHANGED, text)
end

-- Sizes the item to its own label plus the same insets the label is laid out with.
-- Opt-in via props.autoW, for a horizontal tab strip where a fixed nav width would make
-- every tab as wide as the widest possible one. Measured on the shared probe, never on
-- the label: a font string's GetStringWidth is clamped to the width it was given.
--
-- Box, not Measure. The label is a STRETCHED stack child, so the insets subtracted here
-- are handed straight back to it: its own box lands at exactly this number rather than
-- this number plus padding. The client truncates with zero tolerance, so a box at the
-- bare metric drops the last characters for an ellipsis — "Player" renders "Play...".
-- Measure is for a caller that adds slack of its own on top (Button, Dropdown's arrow).
function NavMeta:_autosize()
    local T = SuuUI.Theme
    local fs = self._label
    local font, size, flags = fs:GetFont()
    local tw = SuuUI.TextMetrics.Box(fs:GetText() or "", font, size, flags)
    local insets = (T:GetToken("spaceSm") or 8) + (T:GetToken("spaceXs") or 4)
    self._f:SetWidth(SuuUI.Pixel.Ceil(tw + insets))
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
    self:_paint()
end

-- Surface, border and text colour only. Hover and selection changes take this path so
-- a state flip never rebuilds the backdrop table. The colour token lives in Text.
function NavMeta:_paint()
    local B = SuuUI.Backdrop
    B.SetBg(self._f, bgKeyFor(self))
    B.SetBorder(self._f, "colorBorder")
    self._labelText:SetColor(self._selected and "text" or "muted")
end

function NavMeta:ApplyTheme()
    SuuUI.Backdrop.Apply(self._f, { bg = bgKeyFor(self), border = "colorBorder" })
    -- The bus fires listeners newest-first, so Text's own subscription may not have run
    -- yet. Apply it here; the box re-flows off the label's SIZE_CHANGED.
    self._labelText:ApplyTheme()
    self:_paint()
    -- A font size token change moves the label's width, so a hugging item re-measures.
    if self._autoW then self:_autosize() end
    -- A live opacityDisabled edit reaches an already-disabled widget.
    self:_applyEnabled()
end

-- Fills in GetWidth, GetHeight, IsShown, GetFrame, SetSize, Show, Hide.
SuuUI.Components.InstallBase(NavMeta, "_f")
-- Installs SetEnabled, IsEnabled, _applyEnabled via the canonical fade mechanism.
SuuUI.Components.InstallEnable(NavMeta, "_f")

--- Creates a selectable navigation row with a label.
-- Emits CLICKED (button), MOUSE_ENTER, MOUSE_LEAVE, ENABLED_CHANGED.
-- @param props table  { label, selected, w, h, autoW }
--   autoW: size the item to its label instead of props.w (horizontal tab strips)
-- @param parent frame
-- @return table  NavItem handle
function SuuUI.Components.NavItem(props, parent)
    local T = SuuUI.Theme

    local f = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    f:SetSize(props.w or 160, props.h or 32)
    f:EnableMouse(true)

    -- Registered before the host container adopts the frame, so the container chains
    -- onto this rather than replacing it.
    local handle
    f:SetScript("OnSizeChanged", function(_, w, h)
        if not handle then return end
        S:Emit(handle, S.SIGNALS.SIZE_CHANGED, w, h)
    end)

    local box = SuuUI.Layout:CreateContainer({ host = f, layout = "stack" })

    -- Text owns the font and colour tokens and re-measures on a token change, which a
    -- hand-rolled font string does not. The handle is added rather than its frame, so
    -- the box re-flows off its SIZE_CHANGED instead of needing a manual Layout call.
    local labelText = SuuUI.Components.Text({
        text = props.label or "", size = "md", justify = "LEFT",
        color = props.selected == true and "text" or "muted",
    }, f)
    box:Add(labelText, {
        valign = "center",
        inset  = { left = T:GetToken("spaceSm") or 8, right = T:GetToken("spaceXs") or 4 },
    })

    local id = "nav_" .. tostring(f)
    handle = setmetatable({
        _f         = f,
        -- _label stays the font string so callers and specs reach the same region.
        _label     = labelText:GetFrame(),
        _labelText = labelText,
        _box       = box,
        _eid       = id,
        _enabled   = true,
        _selected  = props.selected == true,
        _hovered   = false,
        _autoW     = props.autoW == true,
    }, NavMeta)

    f:SetScript("OnMouseUp", function(_, btn)
        if handle._enabled == false then return end
        S:Emit(handle, S.SIGNALS.CLICKED, btn or "LeftButton")
    end)
    f:SetScript("OnEnter", function()
        if handle._enabled == false or handle._selected then return end
        handle._hovered = true
        handle:_paint()
        S:Emit(handle, S.SIGNALS.MOUSE_ENTER)
    end)
    f:SetScript("OnLeave", function()
        handle._hovered = false
        handle:_paint()
        S:Emit(handle, S.SIGNALS.MOUSE_LEAVE)
    end)

    handle:ApplyTheme()
    if handle._autoW then handle:_autosize() end
    SuuUI.Events:On("SUUUI_THEME_CHANGED", function() handle:ApplyTheme() end, id)
    return handle
end
