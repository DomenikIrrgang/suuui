local abs, floor, max = math.abs, math.floor, math.max
local S = SuuUI.UISignals

-- Three diagonal runs of one, two and three dots, growing towards the corner: the
-- canonical resize handle, and the same glyph the client draws on its own frames. Built
-- from square dots rather than a diagonal art file because a square lands exactly on the
-- pixel grid at any scale, while rotated or scaled line art is resampled and reads as a
-- grey smear at the one size a grip is ever drawn.
--
-- ROWS is the glyph's shape, not a measurement — the dot size and pitch come from tokens
-- below, so the spacing scale grows the grip without redrawing it.
local ROWS = 3
local DOT_COUNT = ROWS * (ROWS + 1) / 2

--- Signals a resize grip emits on top of the standard set.
-- The grip reports the gesture and nothing else: which frame resizes, in which direction,
-- and whether the result is saved are the owner's business, so a window wires StartSizing
-- to these rather than the grip reaching for a frame it does not own.
SuuUI.Components.RESIZEGRIP_SIGNALS = {
    DRAG_START = "resizegrip.drag_start",  -- Args: none
    DRAG_STOP  = "resizegrip.drag_stop",   -- Args: none
}

local GripMeta = {}
GripMeta.__index = GripMeta

-- Places the dot lattice, measured from the corner it grips.
--
-- The dot is the smallest step on the spacing scale and the pitch is the next one up,
-- which on that scale is exactly one dot plus a dot-sized gap — so the runs stay legible
-- as diagonals at any scale instead of merging into a solid triangle or drifting apart.
-- The field is centred in the box, which keeps it balanced when sizeIcon moves without a
-- second constant to tune against it.
function GripMeta:_place()
    local T = SuuUI.Theme
    local dot    = T:GetToken("spaceXxs") or 2
    local pitch  = T:GetToken("spaceXs")  or 4
    local extent = (ROWS - 1) * pitch + dot
    local insetX = max(0, floor(((self._f:GetWidth()  or 0) - extent) / 2))
    local insetY = max(0, floor(((self._f:GetHeight() or 0) - extent) / 2))

    local n = 0
    for row = 0, ROWS - 1 do
        for col = 0, ROWS - 1 - row do
            n = n + 1
            local a = self._anchors[n]
            a.x, a.y = -(insetX + col * pitch), insetY + row * pitch
            a.width, a.height = dot, dot
            self._box:SetChildAnchor(self._dots[n], a)
        end
    end
end

-- Hover is a recolour and nothing more, so grabbing the corner never re-places the
-- lattice. Idle reads as muted chrome; hovered takes the accent, the same "you can act on
-- this" cue an Input's focus ring uses.
function GripMeta:_paint()
    local c = SuuUI.Theme:GetToken(self._hovered and "colorAccent" or "colorTextMuted")
           or { 0.5, 0.5, 0.5, 1 }
    for i = 1, DOT_COUNT do
        self._dots[i]:SetColorTexture(c[1], c[2], c[3], c[4])
    end
end

-- A grip holds no text, so its size is the icon token as-is rather than floored against
-- the font metrics. Skipped when the caller pinned a size.
function GripMeta:_autosize()
    if not self._autoSize then return end
    local size = SuuUI.Theme:GetToken("sizeIcon") or 16
    if abs((self._f:GetWidth() or 0) - size) > 0.5
       or abs((self._f:GetHeight() or 0) - size) > 0.5 then
        self._f:SetSize(size, size)
    end
end

function GripMeta:ApplyTheme()
    -- Size first: the lattice is centred in the box, so it has to be placed against the
    -- settled size or a sizeIcon change leaves the dots off-centre until something else
    -- resizes the frame.
    self:_autosize()
    self:_place()
    self:_paint()
    -- opacityDisabled is user-editable, so re-assert the fade or a live token edit never
    -- reaches a grip that is already sitting disabled.
    self:_applyEnabled()
end

function GripMeta:Destroy()
    S:DisconnectAll(self)
    SuuUI.Events:Off("SUUUI_THEME_CHANGED", self._eid)
    self._box:Destroy()
    self._f:Hide()
end

--- Sets an explicit size, dropping token-driven sizing.
-- SIZE_CHANGED comes from the frame's own resize hook, not from here.
-- @param w number
-- @param h number
function GripMeta:SetSize(w, h)
    self._autoSize = false
    self._f:SetSize(w, h)
end

-- Fills in GetWidth, GetHeight, IsShown, GetFrame, Show, Hide. SetSize is defined above
-- and survives: it has to clear the token-sizing flag.
SuuUI.Components.InstallBase(GripMeta, "_f")
-- Canonical enabled state: one root-frame fade via the opacityDisabled token, plus the
-- mouse drop — which is the whole of a grip's interactivity, so nothing extra is needed
-- on the _onEnabledChanged hook.
SuuUI.Components.InstallEnable(GripMeta, "_f")

--- Creates a resize grip: a diagonal dot lattice that reports drag gestures.
--
-- The grip draws and reports; it never resizes anything itself. Connect DRAG_START and
-- DRAG_STOP to drive the owner's own sizing, so one grip serves a window, a panel, or
-- anything else with an edge to drag.
--
-- Emits DRAG_START, DRAG_STOP, MOUSE_ENTER, MOUSE_LEAVE, SIZE_CHANGED,
-- VISIBILITY_CHANGED, ENABLED_CHANGED.
-- @param props table  { size }  size: square side; omit to follow sizeIcon
-- @param parent frame
-- @return table  ResizeGrip handle
function SuuUI.Components.ResizeGrip(props, parent)
    props = props or {}
    local size = props.size or SuuUI.Theme:GetToken("sizeIcon") or 16

    local f = CreateFrame("Frame", nil, parent)
    f:SetSize(size, size)
    f:EnableMouse(true)

    -- Registered before the host container adopts the frame so the container chains onto
    -- this hook. A parent layout resizes the frame directly and never calls the handle's
    -- SetSize, so this is the only place that sees a layout-driven resize — and the
    -- lattice is centred in the box, so it has to be re-placed when the box moves.
    local handle
    f:SetScript("OnSizeChanged", function(_, w, h)
        if not (handle and handle._box) then return end
        handle:_place()
        S:Emit(handle, S.SIGNALS.SIZE_CHANGED, w, h)
    end)

    -- Anchor layout: every dot sits at a computed offset from the gripped corner, which is
    -- exactly what this strategy is for. A stack layout has no vocabulary for a lattice.
    local box = SuuUI.Layout:CreateContainer({ host = f, layout = "anchor" })

    local dots, anchors = {}, {}
    for i = 1, DOT_COUNT do
        local tex = f:CreateTexture(nil, "OVERLAY")
        -- The descriptor is kept and mutated in place, so _place re-states one table per
        -- dot rather than allocating six on every theme change and every resize.
        local a = { point = "BOTTOMRIGHT", relativePoint = "BOTTOMRIGHT", x = 0, y = 0 }
        dots[i], anchors[i] = tex, a
        box:Add(tex, { anchor = a })
    end

    local id = "grip_" .. tostring(f)
    handle = setmetatable({
        _f        = f,
        _box      = box,
        _dots     = dots,
        _anchors  = anchors,
        _eid      = id,
        _enabled  = true,
        _hovered  = false,
        _autoSize = props.size == nil,
    }, GripMeta)

    local RG = SuuUI.Components.RESIZEGRIP_SIGNALS
    f:SetScript("OnMouseDown", function()
        if handle._enabled == false then return end
        S:Emit(handle, RG.DRAG_START)
    end)
    f:SetScript("OnMouseUp", function()
        if handle._enabled == false then return end
        S:Emit(handle, RG.DRAG_STOP)
    end)
    f:SetScript("OnEnter", function()
        if handle._enabled == false then return end
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
    SuuUI.Events:On("SUUUI_THEME_CHANGED", function() handle:ApplyTheme() end, id)
    return handle
end
