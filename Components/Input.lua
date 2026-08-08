-- EditBox is a Blizzard-required component. This wraps it with SuuUI theming.
local abs = math.abs
local S = SuuUI.UISignals

-- Input-specific signals
SuuUI.Components.INPUT_SIGNALS = {
    SUBMITTED = "input.submitted",  -- Args: text
}

local SUBMITTED = SuuUI.Components.INPUT_SIGNALS.SUBMITTED

local InpMeta = {}
InpMeta.__index = InpMeta

--- Sets an explicit size, dropping token-driven height.
-- SIZE_CHANGED comes from the frame's resize hook.
-- @param w number
-- @param h number
function InpMeta:SetSize(w, h)
    self._autoH = false
    self._f:SetSize(w, h)
end

-- Font size tokens are user-editable, so an input pinned to a fixed height clips its
-- own text once the font outgrows it. Re-derive from tokens unless the caller pinned
-- the height; the resize hook reports the new size so the containing layout re-flows.
function InpMeta:_autosize()
    if not self._autoH then return end
    local h = SuuUI.Theme:GetControlHeight("sizeControlMd")
    if abs((self._f:GetHeight() or 0) - h) <= 0.5 then return end
    self._f:SetHeight(h)
end

function InpMeta:Destroy()
    S:DisconnectAll(self)
    SuuUI.Events:Off("SUUUI_THEME_CHANGED", self._eid)
    self._box:Destroy()
    -- The layout box is adopted, so destroying it does not hide the frame it lays out.
    -- Without this the widget stays painted on screen after teardown.
    self._f:Hide()
end

--- Enables or disables text input. Emits ENABLED_CHANGED.
-- @param en bool
function InpMeta:SetEnabled(en)
    self._enabled = en
    self._eb:SetEnabled(en)
    S:Emit(self, S.SIGNALS.ENABLED_CHANGED, en)
end

--- Returns current text value.
-- @return string
function InpMeta:GetValue()
    return self._eb:GetText()
end

--- Sets text value without emitting TEXT_CHANGED.
-- @param text string
function InpMeta:SetValue(text)
    self._silent = true
    self._eb:SetText(text or "")
    -- SetText parks the cursor at the end, which scrolls the view and shows only the
    -- tail of the value. Rewind unless the user is actively editing the field.
    if not self._eb:HasFocus() then self._eb:SetCursorPosition(0) end
    self._silent = false
end

--- Sets keyboard focus to the input field.
function InpMeta:SetFocus()
    self._eb:SetFocus()
end

-- Surface and border colour only. Focus and hover changes take this path so a state
-- flip never rebuilds the backdrop table.
function InpMeta:_paint()
    local B = SuuUI.Backdrop
    B.SetBg(self._f, "colorBgAlt")
    B.SetBorder(self._f, (self._hasFocus or self._hasHover)
        and "colorBorderFocus" or "colorBorder")
end

function InpMeta:ApplyTheme()
    local T  = SuuUI.Theme
    local tc = T:GetToken("colorText")
    SuuUI.Backdrop.Apply(self._f, { bg = "colorBgAlt", border = "colorBorder" })
    -- Re-assert the live state: a theme change must not drop the focus ring.
    self:_paint()
    self._eb:SetFont(T:GetToken("fontFamilyMain") or "Fonts/FRIZQT__.TTF",
        T:GetToken("fontSizeMd") or 13, "")
    if tc then self._eb:SetTextColor(tc[1], tc[2], tc[3], tc[4]) end
    self:_autosize()
end

-- Fills in GetWidth, GetHeight, IsShown, GetFrame, Show, Hide. SetSize is defined
-- above and survives: it has to clear the autosize flag.
SuuUI.Components.InstallBase(InpMeta, "_f")

--- Creates a themed text input.
-- Emits TEXT_CHANGED (text), FOCUSED, UNFOCUSED, SUBMITTED via TEXT_CHANGED on enter.
-- Height defaults to the sizeControlMd token floored against the font size, and
-- tracks token changes. Pass h to pin it.
-- @param props table  { value, onChange, onEnter, w, h, maxChars }
-- @param parent frame
-- @return table  Input handle
function SuuUI.Components.Input(props, parent)
    local w = props.w or 160
    local h = props.h or SuuUI.Theme:GetControlHeight("sizeControlMd")

    local f = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    f:SetSize(w, h)
    -- The edit box is inset inside the border, so the frame owns the surrounding ring.
    -- Without mouse input there, hovering the border would not highlight the field.
    f:EnableMouse(true)

    -- Registered before the host container adopts the frame so the container chains
    -- onto this hook. A parent layout resizes the frame directly, never via SetSize.
    local handle
    f:SetScript("OnSizeChanged", function(_, w2, h2)
        if not handle then return end
        S:Emit(handle, S.SIGNALS.SIZE_CHANGED, w2, h2)
    end)

    local box = SuuUI.Layout:CreateContainer({ host = f, layout = "stack" })

    local eb = CreateFrame("EditBox", nil, f)
    -- The vertical inset has no matching space token (2px), so it stays a literal.
    local insetX = SuuUI.Theme:GetToken("spaceXs") or 4
    box:Add(eb, { inset = { left = insetX, right = insetX, top = 2, bottom = 2 } })
    eb:SetAutoFocus(false)
    eb:SetMaxLetters(props.maxChars or 255)
    if props.value then eb:SetText(props.value) end

    local id = "inp_" .. tostring(f)
    handle = setmetatable({
        _f=f, _eb=eb, _box=box, _eid=id, _enabled=true,
        _hasFocus=false, _hasHover=false, _silent=false,
        _autoH=props.h == nil,
    }, InpMeta)

    local function updateBorder() handle:_paint() end

    eb:SetScript("OnTextChanged", function()
        if handle._silent then return end
        local text = eb:GetText()
        if props.onChange then props.onChange(text) end
        S:Emit(handle, S.SIGNALS.TEXT_CHANGED, text)
    end)
    eb:SetScript("OnEnterPressed", function()
        eb:ClearFocus()
        local text = eb:GetText()
        if props.onEnter then props.onEnter(text) end
        S:Emit(handle, SUBMITTED, text)
    end)
    eb:SetScript("OnEscapePressed", function() eb:ClearFocus() end)
    eb:SetScript("OnEditFocusGained", function()
        handle._hasFocus = true
        updateBorder()
        S:Emit(handle, S.SIGNALS.FOCUSED)
    end)
    eb:SetScript("OnEditFocusLost", function()
        handle._hasFocus = false
        updateBorder()
        S:Emit(handle, S.SIGNALS.UNFOCUSED)
    end)

    local function hoverOn()
        handle._hasHover = true
        updateBorder()
        S:Emit(handle, S.SIGNALS.MOUSE_ENTER)
    end
    local function hoverOff()
        handle._hasHover = false
        updateBorder()
        S:Emit(handle, S.SIGNALS.MOUSE_LEAVE)
    end
    f:SetScript("OnEnter", hoverOn)
    f:SetScript("OnLeave", hoverOff)
    eb:SetScript("OnEnter", hoverOn)
    eb:SetScript("OnLeave", hoverOff)

    handle:ApplyTheme()
    SuuUI.Events:On("SUUUI_THEME_CHANGED", function() handle:ApplyTheme() end, id)
    return handle
end
