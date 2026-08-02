local TogMeta = {}
TogMeta.__index = TogMeta

function TogMeta:SetPoint(...)  self._f:SetPoint(...) end
function TogMeta:Show()         self._f:Show() end
function TogMeta:Hide()         self._f:Hide() end
function TogMeta:IsShown()      return self._f:IsShown() end
function TogMeta:GetFrame()     return self._f end
function TogMeta:SetSize(w, h)  self._f:SetSize(w, h) end
function TogMeta:Destroy()      SuuUI.Events:Off("SUUUI_THEME_CHANGED", self._eid) end

--- Sets the enabled/interactive state.
-- @param en bool
function TogMeta:SetEnabled(en)
    self._enabled = en
    self._f:EnableMouse(en)
    self:_render()
end

--- Returns the current toggle value.
-- @return bool
function TogMeta:GetValue()
    return self._value
end

--- Sets the toggle value without firing onChange.
-- @param val bool
function TogMeta:SetValue(val)
    self._value = val == true
    self:_render()
end

function TogMeta:_render()
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
    -- animate using offset stored on handle, not GetLeft() (which is screen-space)
    local fromX = self._knobX or knobX
    self._knobX = knobX
    SuuUI.Anim:New({
        target=self._knob, property="x",
        from=fromX, to=knobX,
        duration=T:GetToken("animFast") or 0.12, easing="easeOut",
    }):Play()
    local kc = en and {1,1,1,1} or T:GetToken("colorTextDisable") or {0.4,0.4,0.4,1}
    self._knob:SetBackdropColor(kc[1], kc[2], kc[3], kc[4])
end

function TogMeta:ApplyTheme()
    self:_render()
end

--- Creates an animated toggle switch.
-- @param props table  { value, onChange, w, h }
-- @param parent frame
-- @return table  Toggle handle
function SuuUI.Components.Toggle(props, parent)
    local w = props.w or 36
    local h = props.h or 18

    local f = CreateFrame("Frame", nil, parent)
    f:SetSize(w, h)
    f:EnableMouse(true)

    local track = CreateFrame("Frame", nil, f, "BackdropTemplate")
    track:SetAllPoints(f)

    local knobSize = h - 4
    local knob = CreateFrame("Frame", nil, f, "BackdropTemplate")
    knob:SetSize(knobSize, knobSize)
    knob:SetPoint("LEFT", f, "LEFT", 3, 0)
    knob:SetBackdrop({
        bgFile="Interface\\Buttons\\WHITE8x8",
        edgeFile="Interface\\Buttons\\WHITE8x8",
        edgeSize=1, insets={left=1,right=1,top=1,bottom=1},
    })

    local id = "tog_" .. tostring(f)
    local handle = setmetatable({
        _f=f, _track=track, _knob=knob,
        _eid=id, _value=props.value == true, _enabled=true,
        _onChange=props.onChange,
    }, TogMeta)

    track:SetBackdrop({
        bgFile="Interface\\Buttons\\WHITE8x8",
        edgeFile="Interface\\Buttons\\WHITE8x8",
        edgeSize=1, insets={left=1,right=1,top=1,bottom=1},
    })

    f:SetScript("OnMouseUp", function()
        if handle._enabled == false then return end
        handle._value = not handle._value
        handle:_render()
        if handle._onChange then handle._onChange(handle._value) end
    end)

    handle:_render()
    SuuUI.Events:On("SUUUI_THEME_CHANGED", function() handle:ApplyTheme() end, id)
    return handle
end
