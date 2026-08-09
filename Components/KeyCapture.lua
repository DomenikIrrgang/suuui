local S = SuuUI.UISignals

local ignored = {
    LSHIFT=true, RSHIFT=true, LCTRL=true, RCTRL=true, LALT=true, RALT=true,
    UNKNOWN=true,
}

local KeyMeta = {}
KeyMeta.__index = KeyMeta

-- The handle wraps a Button handle rather than a frame, so GetFrame has to reach one
-- level further than the installed accessor would.
function KeyMeta:GetFrame()     return self._btn:GetFrame() end

function KeyMeta:Hide()
    self:_stop()
    self._btn:Hide()
    S:Emit(self, S.SIGNALS.VISIBILITY_CHANGED, false)
end

--- Extra per-component behaviour when enabled state changes: set the inner Button's
-- guard flag so its OnEnter/OnLeave/OnMouseUp handlers refuse interaction. We write
-- the flag directly instead of calling btn:SetEnabled, because Button has its own
-- InstallEnable whose _applyEnabled would fight over the shared frame's mouse state.
function KeyMeta:_onEnabledChanged(en)
    self._btn._enabled = en
    if not en then self:_stop() end
end

--- Returns the current binding string.
-- @return string
function KeyMeta:GetValue()
    return self._value
end

--- Sets the binding without emitting VALUE_CHANGED.
-- @param bind string
function KeyMeta:SetValue(bind)
    self._value = bind or ""
    self._btn:SetLabel(self._value ~= "" and self._value or self._placeholder)
end

function KeyMeta:ApplyTheme()
    self._btn:ApplyTheme()
    self:_applyEnabled()
end

function KeyMeta:Destroy()
    self:_stop()
    S:DisconnectAll(self)
    SuuUI.Events:Off("SUUUI_THEME_CHANGED", self._eid)
    self._catchBox:Destroy()
    self._btn:Destroy()
end

function KeyMeta:_stop()
    self._capturing = false
    self._catcher:EnableKeyboard(false)
    self._catcher:Hide()
end

-- Fills in GetWidth, GetHeight, IsShown, SetSize, Show against the wrapped Button
-- handle. GetFrame and Hide are defined above and survive.
SuuUI.Components.InstallBase(KeyMeta, "_btn")
-- Canonical enabled-state: fades the underlying frame, drops mouse, emits
-- ENABLED_CHANGED. The field is "_f" (the Button's raw frame) so EnableMouse and
-- SetAlpha reach the actual WoW frame. The Button handle carries _fade = false to
-- prevent a cascading double-fade if Button's own SetEnabled ever runs.
SuuUI.Components.InstallEnable(KeyMeta, "_f")

--- Creates a keybind capture control: a button that listens for the next keypress.
-- Emits VALUE_CHANGED (newBind, oldBind), CLICKED.
-- @param props table  { value, placeholder, w, h }
-- @param parent frame
-- @return table  KeyCapture handle
function SuuUI.Components.KeyCapture(props, parent)
    local placeholder = props.placeholder or "Not Bound"
    local value = props.value or ""

    -- No w/h: the button hugs the binding text, which can be long ("CTRL-SHIFT-F1")
    local btn = SuuUI.Components.Button({
        label = value ~= "" and value or placeholder,
        w     = props.w,
        h     = props.h,
        minW  = props.minW or 120,
    }, parent)

    -- Keyboard catcher: hidden, only enabled during capture. Sized by the engine.
    local catchBox = SuuUI.Layout:CreateContainer({ host = btn:GetFrame(), layout = "stack" })
    local catcher = CreateFrame("Frame", nil, btn:GetFrame())
    catchBox:Add(catcher)
    catcher:EnableKeyboard(false)
    catcher:SetPropagateKeyboardInput(false)
    catcher:Hide()

    local handle = setmetatable({
        _f           = btn:GetFrame(),
        _btn         = btn,
        _catcher     = catcher,
        _catchBox    = catchBox,
        _value       = value,
        _placeholder = placeholder,
        _enabled     = true,
        _capturing   = false,
    }, KeyMeta)

    -- The Button is a child of the same frame that InstallEnable fades. Suppress the
    -- Button's own fade so the two do not multiply (0.4^2 = 0.16).
    btn._fade = false
    -- KeyCapture fully owns the frame's enabled-state (alpha + mouse). Neutralise
    -- Button's _applyEnabled so its ApplyTheme path cannot fight with ours.
    btn._applyEnabled = function() end

    -- The button re-fits itself to the binding text; pass that on so parent layouts re-flow
    S:Connect(btn, S.SIGNALS.SIZE_CHANGED, function(w, h)
        S:Emit(handle, S.SIGNALS.SIZE_CHANGED, w, h)
    end)

    catcher:SetScript("OnKeyDown", function(_, key)
        if not handle._capturing then return end

        if key == "ESCAPE" then
            handle:_stop()
            handle._btn:SetLabel(handle._value ~= "" and handle._value or placeholder)
            return
        end
        if ignored[key] then return end

        local mods = ""
        if IsControlKeyDown() then mods = mods .. "CTRL-" end
        if IsAltKeyDown()     then mods = mods .. "ALT-"  end
        if IsShiftKeyDown()   then mods = mods .. "SHIFT-" end

        local old = handle._value
        handle._value = mods .. key
        handle:_stop()
        handle._btn:SetLabel(handle._value)
        S:Emit(handle, S.SIGNALS.VALUE_CHANGED, handle._value, old)
    end)

    S:Connect(btn, S.SIGNALS.CLICKED, function(button)
        if handle._enabled == false or handle._capturing then return end
        handle._capturing = true
        catcher:Show()
        catcher:EnableKeyboard(true)
        btn:SetLabel("Press key...")
        S:Emit(handle, S.SIGNALS.CLICKED, button)
    end)

    -- Listen for theme changes so _applyEnabled can track a live opacityDisabled edit.
    local eid = "keycap_" .. tostring(btn:GetFrame())
    handle._eid = eid
    SuuUI.Events:On("SUUUI_THEME_CHANGED", function() handle:ApplyTheme() end, eid)

    return handle
end
