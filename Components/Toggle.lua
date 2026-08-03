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
    self._box:Destroy()
end

--- Sets the enabled/interactive state. Emits ENABLED_CHANGED.
-- @param en bool
function TogMeta:SetEnabled(en)
    self._enabled = en
    self._f:EnableMouse(en)
    self:_render()
    S:Emit(self, S.SIGNALS.ENABLED_CHANGED, en)
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
    local B    = SuuUI.Backdrop
    local on   = self._value
    local en   = self._enabled ~= false
    -- Value and enabled flips recolour only, so the backdrop table is never rebuilt.
    B.SetBg(self._track, on and "colorAccent" or "colorBgAlt")
    B.SetBorder(self._track, "colorBorder")

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

    B.SetBg(self._knob, en and KNOB_WHITE or "colorTextDisabled")
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
    -- The full Apply picks up a changed borderWidth token; _render then recolours.
    local B = SuuUI.Backdrop
    B.Apply(self._track, { bg = "colorBgAlt", border = "colorBorder" })
    B.Apply(self._knob,  { bg = KNOB_WHITE,   border = KNOB_WHITE })
    self:_render(true)
end

-- Fills in GetWidth, GetHeight, IsShown, GetFrame, Show, Hide. SetSize is defined
-- above and survives: it has to clear the token-sizing flag.
SuuUI.Components.InstallBase(TogMeta, "_f")

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

    local track = CreateFrame("Frame", nil, f, "BackdropTemplate")
    box:Add(track)

    local knobBox = SuuUI.Layout:CreateContainer({ host = track, layout = "anchor" })
    local knobSize = h - 4
    local knob = CreateFrame("Frame", nil, track, "BackdropTemplate")

    local knobAnchor = {
        point = "LEFT", relativePoint = "LEFT",
        x = 3, y = 0, width = knobSize, height = knobSize,
    }
    knobBox:Add(knob, { anchor = knobAnchor })

    local id = "tog_" .. tostring(f)
    handle = setmetatable({
        _f=f, _track=track, _knob=knob,
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
