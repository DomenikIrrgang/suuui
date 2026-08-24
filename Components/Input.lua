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

-- The placeholder is a SEPARATE muted Text child, never the EditBox's own text. Putting
-- the hint in the box would make GetValue/GetText return it, so a consumer that filters
-- on the value (the inventory search field) would filter for the literal hint string.
-- It reads as "in the field" purely because it occupies the same stack cell as the box.
--
-- Shown only while the field is empty AND unfocused: a caret sitting on top of grey hint
-- text reads as content the user has to delete before typing.
function InpMeta:_updatePlaceholder()
    if self._placeholder ~= "" and not self._hasFocus
        and (self._eb:GetText() or "") == "" then
        self._phText:Show()
    else
        self._phText:Hide()
    end
end

--- Sets the hint shown while the field is empty and unfocused.
-- Silent by contract: setters never emit, so this makes no TEXT_CHANGED.
-- @param text string|nil  nil clears the placeholder
function InpMeta:SetPlaceholder(text)
    self._placeholder = text or ""
    self._phText:SetText(self._placeholder)
    self:_updatePlaceholder()
end

--- Returns the placeholder hint, or "" when none is set.
-- @return string
function InpMeta:GetPlaceholder()
    return self._placeholder
end

function InpMeta:Destroy()
    S:DisconnectAll(self)
    SuuUI.Events:Off("SUUUI_THEME_CHANGED", self._eid)
    -- Explicit, per "destroy every handle you own", even though box:Destroy() cascades into
    -- children added as handles: a component must not depend on the container's teardown
    -- order for its own cleanup. Text:Destroy is idempotent, so the double call is safe.
    self._phText:Destroy()
    self._box:Destroy()
    -- The layout box is adopted, so destroying it does not hide the frame it lays out.
    -- Without this the widget stays painted on screen after teardown.
    self._f:Hide()
end

--- Extra disabling behaviour beyond the canonical fade + mouse-drop. The EditBox
--- accepts mouse input independently of its parent frame, and hover scripts on both
--- the root frame and the edit box must be guarded so a faded input never flips its
--- border to the focus colour.
function InpMeta:_onEnabledChanged(en)
    self._eb:SetEnabled(en)
    if not en then
        -- Clear focus and hover state so the border returns to rest when disabled
        -- mid-interaction. ClearFocus fires OnEditFocusLost which resets _hasFocus.
        if self._eb:HasFocus() then self._eb:ClearFocus() end
        self._hasHover = false
        self:_paint()
    end
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
    -- The bus fires listeners newest-first, so the placeholder's own subscription has not run
    -- yet when this does. Applying it here is the ordering the component anatomy requires;
    -- the end state is identical either way (Text restyles itself a moment later), so
    -- mutation testing cannot observe this line — dropping it would silently make Input
    -- depend on the child's own subscription surviving. The colour token is declared once at
    -- construction and re-asserted by this call rather than by a second SetColor here.
    self._phText:ApplyTheme()
    self:_autosize()
    -- A live opacityDisabled edit reaches an already-disabled widget.
    self:_applyEnabled()
end

-- Fills in GetWidth, GetHeight, IsShown, GetFrame, Show, Hide. SetSize is defined
-- above and survives: it has to clear the autosize flag.
SuuUI.Components.InstallBase(InpMeta, "_f")
-- Installs SetEnabled, IsEnabled, _applyEnabled via the canonical fade mechanism.
SuuUI.Components.InstallEnable(InpMeta, "_f")

--- Creates a themed text input.
-- Emits TEXT_CHANGED (text), FOCUSED, UNFOCUSED, SUBMITTED via TEXT_CHANGED on enter.
-- Height defaults to the sizeControlMd token floored against the font size, and
-- tracks token changes. Pass h to pin it.
-- @param props table  { value, placeholder, onChange, onEnter, w, h, maxChars }
--   placeholder: muted hint shown while the field is empty and unfocused. It is a
--   separate Text child, so GetValue never returns it.
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

    -- Same stack cell and same horizontal inset as the edit box, so the hint sits exactly
    -- where the user's first character will land. Parented to f rather than eb: the box is
    -- a child frame and draws above f's regions, but it carries no backdrop of its own, so
    -- the hint underneath it is visible — the same relationship f's own backdrop has.
    local phText = SuuUI.Components.Text({
        text = props.placeholder or "", size = "md", justify = "LEFT", color = "muted",
        -- One line, like the single-line box it hints at. Word wrap is on by default, and a
        -- hint too long for the field would grow to two lines and overflow the input's
        -- height instead of truncating horizontally the way the typed text does.
        wrap = false,
    }, f)
    -- The handle, not the region: the box re-flows off its SIZE_CHANGED when a font token
    -- change re-measures the hint, so no manual Layout call is owed anywhere.
    box:Add(phText, {
        valign = "center",
        inset  = { left = insetX, right = insetX },
    })

    local id = "inp_" .. tostring(f)
    handle = setmetatable({
        _f=f, _eb=eb, _box=box, _eid=id, _enabled=true,
        _hasFocus=false, _hasHover=false, _silent=false,
        _autoH=props.h == nil,
        _phText=phText, _placeholder=props.placeholder or "",
    }, InpMeta)

    local function updateBorder() handle:_paint() end

    eb:SetScript("OnTextChanged", function()
        -- Ahead of the silent guard: visibility is not an emission, and a silent SetValue
        -- still has to drop the hint. The client fires this for a programmatic SetText too.
        handle:_updatePlaceholder()
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
        handle:_updatePlaceholder()
        S:Emit(handle, S.SIGNALS.FOCUSED)
    end)
    eb:SetScript("OnEditFocusLost", function()
        handle._hasFocus = false
        updateBorder()
        handle:_updatePlaceholder()
        S:Emit(handle, S.SIGNALS.UNFOCUSED)
    end)

    -- Hover scripts guard against the disabled state so a faded input never flips its
    -- border to the focus colour.
    local function hoverOn()
        if handle._enabled == false then return end
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
    -- props.value is set before the scripts exist, so the first visibility decision has to
    -- be made here rather than ridden in on OnTextChanged.
    handle:_updatePlaceholder()
    SuuUI.Events:On("SUUUI_THEME_CHANGED", function() handle:ApplyTheme() end, id)
    return handle
end
