local abs = math.abs
local S = SuuUI.UISignals

-- Size keys resolve through Theme:GetFontSize — the single map from "sm".."xl" onto the
-- font size tokens. Colours still map here because they are Text-specific aliases.
local colmap  = {
    text      = "colorText",
    muted     = "colorTextMuted",
    textMuted = "colorTextMuted",
    disable   = "colorTextDisabled",
    accent    = "colorAccent",
    -- Intent colours, for a label whose value carries state: a readout that is fine, close
    -- to a threshold, or past it. Named for the intent rather than the hue so a retint moves
    -- them with every other warning in the UI.
    success   = "colorSuccess",
    warning   = "colorWarning",
    danger    = "colorDanger",
}

local TextMeta = {}
TextMeta.__index = TextMeta

-- Text opts OUT of the alpha fade. A label that is already disabled-grey (the
-- colourTextDisabled token) fades to unreadable at 0.40 alpha. The colour change alone
-- satisfies the design rule because colorTextDisabled is visually distinct from every
-- enabled colour key in both shipped themes.
TextMeta._fade = false

function TextMeta:GetWidth()     return self._fs:GetWidth()  end
function TextMeta:GetHeight()    return self._fs:GetHeight() end
function TextMeta:IsShown()      return self._fs:IsShown()   end
function TextMeta:GetFrame()     return self._fs end

function TextMeta:SetSize(w, h)
    self._fs:SetSize(w, h)
    S:Emit(self, S.SIGNALS.SIZE_CHANGED, w, h)
end

function TextMeta:Show()
    self._fs:Show()
    S:Emit(self, S.SIGNALS.VISIBILITY_CHANGED, true)
end

function TextMeta:Hide()
    self._fs:Hide()
    S:Emit(self, S.SIGNALS.VISIBILITY_CHANGED, false)
end

--- Sets the text colour token suffix and restyles.
-- @param color string  "text"|"muted"|"disable"|"accent"
function TextMeta:SetColor(color)
    self._color = color
    self:ApplyTheme()
end

--- Hook called by InstallEnable after the enabled state changes. Swaps to the
-- disabled-grey colour token (or restores the base colour) and repaints.
function TextMeta:_onEnabledChanged(en)
    self._color = en and (self._baseColor or "text") or "disable"
    self:ApplyTheme()
end

function TextMeta:Destroy()
    S:DisconnectAll(self)
    SuuUI.Events:Off("SUUUI_THEME_CHANGED", self._eid)
end

--- Sets the displayed text. Emits TEXT_CHANGED.
-- @param text string
function TextMeta:SetText(text)
    self._fs:SetText(text)
    self:_measure()
    S:Emit(self, S.SIGNALS.TEXT_CHANGED, text)
end

-- A parent layout pins the font string to an explicit height measured at the font
-- size in force at the time. Font tokens change at runtime, so re-measure and report
-- the new height; the containing layout re-flows off SIZE_CHANGED.
function TextMeta:_measure()
    if self._fixed then return end
    local h = self._fs:GetStringHeight()
    if not h or h <= 0 then
        -- The client reports nothing for a font string it has not laid out yet, which is
        -- every label built inside a window that has never been shown. Measure it instead
        -- of leaving the height at zero, where it would silently never draw.
        local font, size, flags = self._fs:GetFont()
        if not (font and size) then return end
        h = select(2, SuuUI.TextMetrics.Box(self._fs:GetText() or "", font, size, flags))
        if not h or h <= 0 then return end
    end
    if abs((self._fs:GetHeight() or 0) - h) <= 0.5 then return end
    self._fs:SetHeight(h)
    S:Emit(self, S.SIGNALS.SIZE_CHANGED, self._fs:GetWidth(), h)
end

--- Returns the displayed text.
-- @return string
function TextMeta:GetText()
    return self._fs:GetText()
end

--- Overrides the face with an explicit font path, or clears the override with nil.
-- Only for text that has to render in a face other than the theme's — a font picker
-- showing each option in its own face. Size and colour still follow the tokens, and the
-- element re-measures, so a taller face reports its new height.
-- @param path string|nil  Font file path, resolved through SuuUI.Fonts
function TextMeta:SetFont(path)
    self._font = path
    self:ApplyTheme()
end

--- Returns the explicit face override, or nil when the text follows the theme token.
-- @return string|nil
function TextMeta:GetFontOverride()
    return self._font
end

--- Switches which font-size step the text renders at, and re-measures.
--
-- The step stays a token KEY rather than becoming a number: the pixel size still comes
-- from the theme, so text set to "lg" follows a user's edit of `fontSizeLg` exactly as
-- text built that way does. This is the sibling of SetFont — that one overrides the face,
-- this one the step — and it exists because a size chosen by a setting has to be
-- changeable after construction.
-- @param size string  "sm" | "md" | "lg" | "xl"
function TextMeta:SetFontSize(size)
    if self._size == size then return end
    self._size = size
    self:ApplyTheme()
end

--- Returns the font-size step key the text renders at.
-- @return string
function TextMeta:GetFontSize()
    return self._size
end

function TextMeta:ApplyTheme()
    local T     = SuuUI.Theme
    -- An override comes from a caller, so it is resolved rather than trusted: SetFont
    -- raises on an asset the client cannot load, and this runs from a theme-change
    -- callback where an error would stop every later element restyling.
    local font  = self._font and SuuUI.Fonts:Path(self._font)
                  or T:GetToken("fontFamilyMain") or "Fonts/FRIZQT__.TTF"
    local size  = T:GetFontSize(self._size) or 13
    local ckey  = colmap[self._color] or "colorText"
    local col   = T:GetToken(ckey) or {0.92, 0.92, 0.92, 1}
    self._fs:SetFont(font, size, self._flags or "")
    self._fs:SetTextColor(col[1], col[2], col[3], col[4])
    self:_measure()
end

-- Text cannot use the generic InstallEnable because its root element is a FontString,
-- which has no EnableMouse/IsMouseEnabled. The fade is already opted out (_fade = false)
-- and a label never receives clicks, so manual definitions give the same contract
-- (SetEnabled, IsEnabled, _applyEnabled, ENABLED_CHANGED signal) without the mouse path.
function TextMeta:_applyEnabled()
    -- No alpha fade (_fade = false) and no mouse to toggle on a FontString.
    -- Exists so ApplyTheme can call it uniformly if desired.
end

function TextMeta:SetEnabled(en)
    self._enabled = en ~= false
    self:_applyEnabled()
    if self._onEnabledChanged then self:_onEnabledChanged(self._enabled) end
    S:Emit(self, S.SIGNALS.ENABLED_CHANGED, self._enabled)
end

function TextMeta:IsEnabled()
    return self._enabled ~= false
end

--- Creates a themed text element.
-- @param props table  { text, size, color, flags, w, h, justify, wrap, font }
--   size: "sm"|"md"|"lg"|"xl"   color: "text"|"muted"|"disable"|"accent"
--   justify: "LEFT"|"CENTER"|"RIGHT" (default: "LEFT")
--   font: explicit face path, overriding the theme token. Omit in normal use.
-- @param parent frame
-- @return table  Text handle
function SuuUI.Components.Text(props, parent)
    local fs = parent:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    -- WIDTH ALONE IS HONOURED, and for a while it was not: this read
    -- `if props.w and props.h then fs:SetSize(...)`, so a caller passing only `w` got NO width at
    -- all. That is worse than it looks, because a FontString with no width CANNOT WRAP -- the client
    -- draws one long line and the parent clips it, which reads as an ellipsis. It cost three
    -- truncation bugs in one sitting (two counters and the keybind change rows) before the cause was
    -- read here rather than guessed at the call sites.
    --
    -- Height is deliberately still optional: `_fixed` stays false when only `w` is given, so
    -- _measure keeps owning the height and a wrapped label grows to the lines it needs. There is no
    -- height-only branch for the same reason -- _measure would overwrite it on the next SetText, so
    -- it would be a line that reads as intent and does nothing.
    if props.w and props.h then
        fs:SetSize(props.w, props.h)
    elseif props.w then
        fs:SetWidth(props.w)
    end
    if props.text then fs:SetText(props.text) end
    fs:SetJustifyH(props.justify or "LEFT")
    fs:SetJustifyV("MIDDLE")
    if props.wrap ~= nil then fs:SetWordWrap(props.wrap) end

    local id = "text_" .. tostring(fs)
    local handle = setmetatable({
        _fs        = fs,
        _eid       = id,
        _size      = props.size  or "md",
        _color     = props.color or "text",
        _baseColor = props.color or "text",
        _flags     = props.flags or "",
        _font      = props.font,
        _fixed     = (props.w and props.h) and true or false,
    }, TextMeta)
    handle:ApplyTheme()
    SuuUI.Events:On("SUUUI_THEME_CHANGED", function() handle:ApplyTheme() end, id)
    return handle
end
