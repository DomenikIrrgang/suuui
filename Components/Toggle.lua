local abs = math.abs
local S = SuuUI.UISignals

-- The knob is a plain white dot with no intent colour of its own, matching the client's
-- default backdrop edge. Shared so a render allocates nothing.
local KNOB_WHITE = { 1, 1, 1, 1 }

local TogMeta = {}
TogMeta.__index = TogMeta

--- Sets an explicit size, dropping token-driven sizing.
-- @param w number
-- @param h number
function TogMeta:SetSize(w, h)
    self._autoSize = false
    self._f:SetSize(w, h)
end

function TogMeta:Destroy()
    S:DisconnectAll(self)
    SuuUI.Events:Off("SUUUI_THEME_CHANGED", self._eid)
    self._pill:Destroy()
    self._knobDisc:Destroy()
    self._knobBox:Destroy()
    self._box:Destroy()
    -- The layout box is adopted, so destroying it does not hide the frame it lays out.
    -- Without this the widget stays painted on screen after teardown.
    self._f:Hide()
end

--- Returns the current toggle value.
-- @return bool
function TogMeta:GetValue()
    return self._value
end

--- Sets the toggle value without emitting VALUE_CHANGED.
-- @param val bool
function TogMeta:SetValue(val)
    self._value = val == true
    self:_render()
end

--- Renders the current state.
-- @param snap bool  Place the knob immediately instead of animating (used on resize)
function TogMeta:_render(snap)
    local T    = SuuUI.Theme
    local on   = self._value
    -- Value flips recolour the existing pieces; no geometry is touched and no texture is
    -- replaced, so the masks that round the track survive a flip.
    self._pill:SetBg(on and "colorAccent" or "colorBgAlt")
    self._pill:SetBorder("colorBorder")

    local tw       = self._f:GetWidth()
    local th       = self._f:GetHeight()
    local knobSize = th - 4
    local knobX    = on and (tw - knobSize - 3) or 3

    local fromX = self._knobX or knobX
    self._knobX = knobX
    self._knobAnchor.width  = knobSize
    self._knobAnchor.height = knobSize

    -- The anchor descriptor stays authoritative, so the knob is correctly placed even
    -- if no animation runs. Resizes snap; value changes animate.
    self._knobAnchor.x = knobX
    if snap or fromX == knobX then
        self._knobBox:SetChildAnchor(self._knob, self._knobAnchor)
    else
        SuuUI.Anim:New({
            container = self._knobBox,
            target    = self._knob,
            anchor    = self._knobAnchor,
            property  = "x",
            from      = fromX, to = knobX,
            duration  = T:GetToken("animFast") or 0.12,
            easing    = "easeOut",
        }):Play()
    end

    self._knobDisc:SetBg(KNOB_WHITE)
end

function TogMeta:ApplyTheme()
    -- Size tokens are user-editable; re-derive unless the caller pinned a size. The
    -- frame's resize hook re-renders and emits SIZE_CHANGED.
    if self._autoSize then
        local T = SuuUI.Theme
        local w = T:GetToken("sizeToggleW") or 36
        local h = T:GetToken("sizeControlSm") or 18
        if abs((self._f:GetWidth() or 0) - w) > 0.5 or abs((self._f:GetHeight() or 0) - h) > 0.5 then
            self._f:SetSize(w, h)
        end
    end
    -- Re-derives the stadium from the current height and a changed borderWidth token;
    -- _render then recolours it. The knob's disc stretches to its frame, so it needs no
    -- geometry pass of its own.
    self._pill:Refresh()
    self:_render(true)
    -- A live edit to opacityDisabled must reach a widget that is already sitting faded.
    self:_applyEnabled()
end

-- Fills in GetWidth, GetHeight, IsShown, GetFrame, Show, Hide. SetSize is defined
-- above and survives: it has to clear the token-sizing flag.
SuuUI.Components.InstallBase(TogMeta, "_f")
-- Canonical enabled-state handling: root-frame fade + mouse drop. No _onEnabledChanged
-- hook is needed — the fade is the whole disabled visual, and _render deliberately does
-- not consult _enabled, so the track keeps its accent instead of half-greying the way the
-- old knob-only recolour did.
SuuUI.Components.InstallEnable(TogMeta, "_f")

--- Creates an animated toggle switch.
-- Emits VALUE_CHANGED (new, old), ENABLED_CHANGED, MOUSE_ENTER, MOUSE_LEAVE.
-- @param props table  { value, onChange, w, h }
-- @param parent frame
-- @return table  Toggle handle
function SuuUI.Components.Toggle(props, parent)
    -- A toggle carries no text, so its size comes straight from the size tokens and is
    -- not floored against the font size.
    local T0 = SuuUI.Theme
    local w = props.w or T0:GetToken("sizeToggleW") or 36
    local h = props.h or T0:GetToken("sizeControlSm") or 18

    local f = CreateFrame("Frame", nil, parent)
    f:SetSize(w, h)
    f:EnableMouse(true)

    -- The knob offset derives from the frame width, so re-render whenever the frame is
    -- resized, including by a parent layout. Registered before the host container
    -- adopts the frame so the container chains onto it.
    local handle
    f:SetScript("OnSizeChanged", function(_, newW, newH)
        if not (handle and handle._knobBox) then return end
        handle:_render(true)
        S:Emit(handle, S.SIGNALS.SIZE_CHANGED, newW, newH)
    end)

    -- Track fills the toggle; the knob is positioned by an anchor container
    local box = SuuUI.Layout:CreateContainer({ host = f, layout = "stack" })

    -- A stadium rather than a backdrop: a backdrop's corners are its texture's corners,
    -- so a rounded switch has to be composed from masked textures. Built before the track
    -- joins the outer box so the first layout pass already has the pieces to size.
    local track = CreateFrame("Frame", nil, f)
    local pill = SuuUI.Backdrop.Pill(track, { bg = "colorBgAlt", border = "colorBorder" })
    box:Add(track)

    local knobBox = SuuUI.Layout:CreateContainer({ host = track, layout = "anchor" })
    local knobSize = h - 4
    -- The knob is square, so the same circular mask that rounds the track's caps makes
    -- it a disc. A square knob inside a stadium reads as a rendering fault.
    local knob = CreateFrame("Frame", nil, track)
    local knobDisc = SuuUI.Backdrop.Circle(knob, { bg = KNOB_WHITE })

    local knobAnchor = {
        point = "LEFT", relativePoint = "LEFT",
        x = 3, y = 0, width = knobSize, height = knobSize,
    }
    knobBox:Add(knob, { anchor = knobAnchor })

    local id = "tog_" .. tostring(f)
    handle = setmetatable({
        _f=f, _track=track, _knob=knob, _pill=pill, _knobDisc=knobDisc,
        _box=box, _knobBox=knobBox, _knobAnchor=knobAnchor,
        _eid=id, _value=props.value == true, _enabled=true,
        _onChange=props.onChange,
        _autoSize=props.w == nil and props.h == nil,
    }, TogMeta)

    f:SetScript("OnMouseUp", function()
        if handle._enabled == false then return end
        local old = handle._value
        handle._value = not old
        handle:_render()
        if handle._onChange then handle._onChange(handle._value) end
        S:Emit(handle, S.SIGNALS.VALUE_CHANGED, handle._value, old)
    end)

    f:SetScript("OnEnter", function() S:Emit(handle, S.SIGNALS.MOUSE_ENTER) end)
    f:SetScript("OnLeave", function() S:Emit(handle, S.SIGNALS.MOUSE_LEAVE) end)

    handle:ApplyTheme()
    SuuUI.Events:On("SUUUI_THEME_CHANGED", function() handle:ApplyTheme() end, id)
    return handle
end
