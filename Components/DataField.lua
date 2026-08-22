local S = SuuUI.UISignals

local DataMeta = {}
DataMeta.__index = DataMeta

-- At rest the field paints nothing. The bar already draws one continuous surface beneath it,
-- so a field with a background of its own would either match that surface exactly (a wasted
-- draw) or blend a second translucent panel colour against it and leave a visible seam at
-- every field edge — the same trap Accordion's header and body avoid by being siblings.
local function bgKeyFor(self)
    if self._hovered then return "colorBgHover" end
    return false
end

-- The prefix and the value share ONE font string, coloured with an inline escape.
--
-- Two font strings at two font sizes is the obvious build and it is subtly wrong: flow
-- layout centres their BOXES, and a font's ascent is roughly 0.75 of its line height rather
-- than half, so centring two different line heights leaves the baselines about
-- (h2 - h1) * 0.28 apart — a whole pixel once the grid rounds it, visible as a step between
-- the label and the number in every field on the bar. One font string has one baseline by
-- construction, needs no ascent metric the client does not expose, and halves the font
-- strings the shared ticker rewrites.
--
-- The cost is that the separator can only be a space character, since a single string has a
-- single font: the gap is one space rather than a spacing token.
local function compose(self)
    local value = self._value or ""
    local prefix = self._prefix
    if not prefix or prefix == "" then return value end
    local code = SuuUI.Theme.GetColorCode and SuuUI.Theme:GetColorCode("colorTextMuted")
    if not code then return prefix .. " " .. value end
    if value == "" then return code .. prefix .. "|r" end
    return code .. prefix .. "|r " .. value
end

-- Surface and rail visibility only. A hover flip takes this path so it never rebuilds the
-- backdrop table or re-resolves a token.
function DataMeta:_paint()
    SuuUI.Backdrop.SetBg(self._f, bgKeyFor(self))
    -- The rail is tied to the hovered state rather than to a flag of its own, so it cannot
    -- survive a MOUSE_LEAVE that some other paint path forgot about.
    if self._hovered and self._rail then
        self._railTex:Show()
    else
        self._railTex:Hide()
    end
end

-- Sizes the field to its own text plus the insets the text is laid out with.
--
-- Box, not Measure. The label is a STRETCHED stack child, so the insets subtracted here are
-- handed straight back to it and its own box lands at exactly this metric — where the client
-- truncates with zero tolerance and draws an ellipsis instead. That is how NavItem's tab
-- strip rendered "Play…" for "Player" with every geometry assertion passing.
--
-- Measuring the composed string is safe: the client ignores colour escapes when measuring,
-- and the harness font model strips them too, so both agree on the width.
function DataMeta:_autosize()
    if not self._autoW then return end
    local fs = self._label
    local font, size, flags = fs:GetFont()
    local tw = SuuUI.TextMetrics.Box(fs:GetText() or "", font, size, flags)
    local pad = (SuuUI.Theme:GetToken("spaceMd") or 12) * 2
    local w = SuuUI.Pixel.Ceil(tw + pad)
    if self._minW and w < self._minW then w = self._minW end
    if math.abs((self._f:GetWidth() or 0) - w) <= 0.5 then return end
    -- Setting the width fires the frame's own OnSizeChanged, which the host container chains
    -- onto — so the label re-fits and SIZE_CHANGED reaches the bar without a call here.
    self._f:SetWidth(w)
end

-- The height counterpart, and it exists for the same reason the width hug does: font tokens
-- are user-editable, so a height taken once at construction goes stale and the glyphs hang
-- out of the box unclipped. Only for a field the caller did not pin a height on — on the bar
-- the field is a stretched child and the bar owns its height.
--
-- GetControlHeight alone is not enough at large font sizes: it reserves fontSize + spaceXs*2,
-- while a face's line height is a larger multiple of its point size, so the measured label is
-- taken as the floor.
function DataMeta:_autosizeH()
    if not self._autoH then return end
    local h = SuuUI.Theme:GetControlHeight("sizeRow")
    local lh = self._labelText:GetHeight() or 0
    if lh > h then h = SuuUI.Pixel.Ceil(lh) end
    if math.abs((self._f:GetHeight() or 0) - h) <= 0.5 then return end
    self._f:SetHeight(h)
end

--- Sets the value shown after the prefix. Emits TEXT_CHANGED.--
-- An unchanged write is dropped. A readout is rewritten on every game event and on every
-- tick of the shared ticker, and usually says exactly what it said last time; re-measuring
-- and re-laying out for that would be the bar's whole cost. Same guard as StatusBar's
-- overlay readouts.
-- @param value string
function DataMeta:SetText(value)
    value = value or ""
    if self._value == value then return end
    self._value = value
    self._labelText:SetText(compose(self))
    self:_autosize()
    S:Emit(self, S.SIGNALS.TEXT_CHANGED, value)
end

--- Returns the value, without the prefix or its colour escape.
-- @return string
function DataMeta:GetText()
    return self._value or ""
end

--- Sets the muted prefix drawn before the value. Pass nil or "" for none.
-- @param prefix string|nil
function DataMeta:SetPrefix(prefix)
    prefix = prefix or ""
    if self._prefix == prefix then return end
    self._prefix = prefix
    self._labelText:SetText(compose(self))
    self:_autosize()
end

--- Returns the prefix.
-- @return string
function DataMeta:GetPrefix()
    return self._prefix or ""
end

--- Turns the hover rail on or off for this field.
-- A field with no hover behaviour of its own should not advertise one, since the rail is
-- what tells the player a field can be interacted with.
-- @param on bool
function DataMeta:SetRail(on)
    self._rail = on ~= false
    self:_paint()
end

--- Whether the field is currently hovered.
-- @return bool
function DataMeta:IsHovered()
    return self._hovered == true
end

function DataMeta:ApplyTheme()
    local T = SuuUI.Theme
    -- Borderless, so the background covers the whole box: inset would otherwise leave it a
    -- pixel short on every side and the hover fill would not meet its own dividers. Same
    -- reason a frameless StatusBar passes inset = 0.
    SuuUI.Backdrop.Apply(self._f, { bg = bgKeyFor(self), border = false, inset = 0 })

    -- The bus fires listeners newest-first, so Text's own subscription may not have run yet;
    -- applying it here keeps this field from measuring against the previous font.
    self._labelText:ApplyTheme()
    -- Recomposed, not just restyled: the prefix's colour is baked into the string as an
    -- escape, so a colorTextMuted edit reaches the screen only by rebuilding it.
    self._labelText:SetText(compose(self))

    local rc = T:GetToken("colorAccent")
    if rc then self._railTex:SetColorTexture(rc[1], rc[2], rc[3], rc[4]) end
    self._railH = SuuUI.Pixel.Line(T:GetToken("sizeRail") or 2)
    self._railProps.height = self._railH

    local pad = T:GetToken("spaceMd") or 12
    self._labelProps.inset.left  = pad
    self._labelProps.inset.right = pad

    self._box:Layout()
    self:_paint()
    -- A live opacityDisabled edit has to reach a field that is already disabled.
    self:_applyEnabled()
    -- A font token change moves the text's width, so a hugging field re-measures.
    self:_autosize()
    self:_autosizeH()
end

function DataMeta:Destroy()
    S:DisconnectAll(self)
    SuuUI.Events:Off("SUUUI_THEME_CHANGED", self._eid)
    self._labelText:Destroy()
    self._box:Destroy()
    -- The layout box is adopted, so destroying it does not hide the frame it lays out.
    self._f:Hide()
end

--- A caller pinning a size opts out of hugging its own text, on both axes.
function DataMeta:SetSize(w, h)
    self._autoW = false
    self._autoH = false
    self._f:SetSize(w, h)
end

-- Fills in GetWidth, GetHeight, IsShown, GetFrame, Show, Hide. SetSize is defined above and
-- survives, because InstallBase only fills gaps.
SuuUI.Components.InstallBase(DataMeta, "_f")
-- Installs SetEnabled, IsEnabled, _applyEnabled via the canonical fade + mouse drop.
SuuUI.Components.InstallEnable(DataMeta, "_f")

--- Creates a data-bar field: a muted prefix, a value, and an accent rail on hover.
--
-- Hugs its own text unless `w` is given; its HEIGHT comes from whatever lays it out, which
-- on the bar is a stretched flow child, so a field is exactly as tall as the bar.
-- Emits CLICKED (button), MOUSE_ENTER, MOUSE_LEAVE, SIZE_CHANGED, TEXT_CHANGED.
-- @param props table  { prefix, text, w, h, minW, rail, size }
--   rail: draw the accent underline on hover (default true)
--   size: font step key for the value (default "md")
-- @param parent frame
-- @return table  DataField handle
function SuuUI.Components.DataField(props, parent)
    local T = SuuUI.Theme

    local f = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    f:SetSize(props.w or 60, props.h or T:GetControlHeight("sizeRow"))
    f:EnableMouse(true)

    -- Registered before the host container adopts the frame, so the container chains onto
    -- this instead of replacing it. A parent layout resizes the frame directly and never
    -- calls the handle's SetSize, so this is the only place a layout-driven resize is seen.
    local handle
    f:SetScript("OnSizeChanged", function(_, w, h)
        if not handle then return end
        S:Emit(handle, S.SIGNALS.SIZE_CHANGED, w, h)
    end)

    local box = SuuUI.Layout:CreateContainer({ host = f, layout = "stack" })

    -- Text owns the font and colour tokens and re-measures on a token change. The handle is
    -- added rather than its frame so the box re-flows off its SIZE_CHANGED.
    --
    -- wrap = false is load-bearing. A field is one line by construction, and with the
    -- client's default of wrap ON a box one pixel short does not truncate visibly — it breaks
    -- a word onto a second line that a one-line-tall field then hides, so the value is silently
    -- wrong instead of visibly clipped. It also makes the clip check exact: with wrap on, the
    -- width a string is judged against is the widest WORD, so a full-line shortfall registers
    -- as no clip at all.
    local labelText = SuuUI.Components.Text({
        text = "", size = props.size or "md", justify = "LEFT", color = "text",
        wrap = false,
    }, f)
    local pad = T:GetToken("spaceMd") or 12
    -- Kept as an upvalue so ApplyTheme can re-state the padding when the token moves,
    -- without allocating a props table per theme change.
    local labelProps = { valign = "center", inset = { left = pad, right = pad } }
    box:Add(labelText, labelProps)

    -- The hover affordance: a full-width underline along the bottom edge. A texture rather
    -- than a backdrop edge, because a backdrop border draws on all four sides.
    local railTex = f:CreateTexture(nil, "ARTWORK")
    local railProps = { valign = "end", height = SuuUI.Pixel.Line(T:GetToken("sizeRail") or 2) }
    box:Add(railTex, railProps)
    railTex:Hide()

    local id = "datafield_" .. tostring(f)
    handle = setmetatable({
        _f          = f,
        -- _label stays the font string so callers and specs reach the same region.
        _label      = labelText:GetFrame(),
        _labelText  = labelText,
        _box        = box,
        _eid        = id,
        _enabled    = true,
        _hovered    = false,
        _value      = props.text or "",
        _prefix     = props.prefix or "",
        _rail       = props.rail ~= false,
        _minW       = props.minW,
        _autoW      = props.w == nil,
        _autoH      = props.h == nil,
        _railTex    = railTex,
        _railProps  = railProps,
        _labelProps = labelProps,
    }, DataMeta)

    labelText:SetText(compose(handle))

    f:SetScript("OnMouseUp", function(_, btn)
        if handle._enabled == false then return end
        S:Emit(handle, S.SIGNALS.CLICKED, btn or "LeftButton")
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
