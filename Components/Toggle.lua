local S = SuuUI.UISignals

local TogMeta = {}
TogMeta.__index = TogMeta

function TogMeta:GetWidth()     return self._f:GetWidth() end
function TogMeta:GetHeight()    return self._f:GetHeight() end
function TogMeta:IsShown()      return self._f:IsShown() end
function TogMeta:GetFrame()     return self._f end

function TogMeta:SetSize(w, h)
    self._f:SetSize(w, h)
end

function TogMeta:Show()
    self._f:Show()
    S:Emit(self, S.SIGNALS.VISIBILITY_CHANGED, true)
end

function TogMeta:Hide()
    self._f:Hide()
    S:Emit(self, S.SIGNALS.VISIBILITY_CHANGED, false)
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
    local on   = self._value
    local en   = self._enabled ~= false
    local track = on and T:GetToken("colorAccent") or T:GetToken("colorBgAlt")
    local bord  = T:GetToken("colorBorder")
    if track then self._track:SetBackdropColor(track[1], track[2], track[3], track[4]) end
    if bord  then self._track:SetBackdropBorderColor(bord[1], bord[2], bord[3], bord[4]) end

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

    local kc = en and {1,1,1,1} or T:GetToken("colorTextDisable") or {0.4,0.4,0.4,1}
    self._knob:SetBackdropColor(kc[1], kc[2], kc[3], kc[4])
end

function TogMeta:ApplyTheme()
    self:_render(true)
end

--- Creates an animated toggle switch.
-- Emits VALUE_CHANGED (new, old), ENABLED_CHANGED, MOUSE_ENTER, MOUSE_LEAVE.
-- @param props table  { value, onChange, w, h }
-- @param parent frame
-- @return table  Toggle handle
function SuuUI.Components.Toggle(props, parent)
    local w = props.w or 36
    local h = props.h or 18

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
    track:SetBackdrop({
        bgFile="Interface\\Buttons\\WHITE8x8",
        edgeFile="Interface\\Buttons\\WHITE8x8",
        edgeSize=1, insets={left=1,right=1,top=1,bottom=1},
    })
    box:Add(track)

    local knobBox = SuuUI.Layout:CreateContainer({ host = track, layout = "anchor" })
    local knobSize = h - 4
    local knob = CreateFrame("Frame", nil, track, "BackdropTemplate")
    knob:SetBackdrop({
        bgFile="Interface\\Buttons\\WHITE8x8",
        edgeFile="Interface\\Buttons\\WHITE8x8",
        edgeSize=1, insets={left=1,right=1,top=1,bottom=1},
    })

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

    handle:_render(true)
    SuuUI.Events:On("SUUUI_THEME_CHANGED", function() handle:ApplyTheme() end, id)
    return handle
end
