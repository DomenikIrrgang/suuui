local S = SuuUI.UISignals

local ignored = {
    LSHIFT=true, RSHIFT=true, LCTRL=true, RCTRL=true, LALT=true, RALT=true,
    UNKNOWN=true,
}

local KeyMeta = {}
KeyMeta.__index = KeyMeta

function KeyMeta:GetWidth()     return self._btn:GetWidth() end
function KeyMeta:GetHeight()    return self._btn:GetHeight() end
function KeyMeta:IsShown()      return self._btn:IsShown() end
function KeyMeta:GetFrame()     return self._btn:GetFrame() end

function KeyMeta:SetSize(w, h)
    self._btn:SetSize(w, h)
end

function KeyMeta:Show()
    self._btn:Show()
    S:Emit(self, S.SIGNALS.VISIBILITY_CHANGED, true)
end

function KeyMeta:Hide()
    self:_stop()
    self._btn:Hide()
    S:Emit(self, S.SIGNALS.VISIBILITY_CHANGED, false)
end

--- Enables or disables capture. Emits ENABLED_CHANGED.
-- @param en bool
function KeyMeta:SetEnabled(en)
    self._enabled = en
    self._btn:SetEnabled(en)
    S:Emit(self, S.SIGNALS.ENABLED_CHANGED, en)
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
end

function KeyMeta:Destroy()
    self:_stop()
    S:DisconnectAll(self)
    self._catchBox:Destroy()
    self._btn:Destroy()
end

function KeyMeta:_stop()
    self._capturing = false
    self._catcher:EnableKeyboard(false)
    self._catcher:Hide()
end

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
        _btn         = btn,
        _catcher     = catcher,
        _catchBox    = catchBox,
        _value       = value,
        _placeholder = placeholder,
        _enabled     = true,
        _capturing   = false,
    }, KeyMeta)

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

    return handle
end
