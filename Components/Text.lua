local S = SuuUI.UISignals

local sizemap = { sm="fontSizeSm", md="fontSizeMd", lg="fontSizeLg", xl="fontSizeXl" }
local colmap  = {
    text      = "colorText",
    muted     = "colorTextMuted",
    textMuted = "colorTextMuted",
    disable   = "colorTextDisable",
    accent    = "colorAccent",
}

local TextMeta = {}
TextMeta.__index = TextMeta

function TextMeta:GetWidth()     return self._fs:GetWidth() end
function TextMeta:GetHeight()    return self._fs:GetHeight() end
function TextMeta:IsShown()      return self._fs:IsShown() end
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

function TextMeta:SetEnabled(en)
    self._color = en and (self._baseColor or "text") or "disable"
    self:ApplyTheme()
    S:Emit(self, S.SIGNALS.ENABLED_CHANGED, en)
end

function TextMeta:Destroy()
    S:DisconnectAll(self)
    SuuUI.Events:Off("SUUUI_THEME_CHANGED", self._eid)
end

--- Sets the displayed text. Emits TEXT_CHANGED.
-- @param text string
function TextMeta:SetText(text)
    self._fs:SetText(text)
    S:Emit(self, S.SIGNALS.TEXT_CHANGED, text)
end

--- Returns the displayed text.
-- @return string
function TextMeta:GetText()
    return self._fs:GetText()
end

function TextMeta:ApplyTheme()
    local T     = SuuUI.Theme
    local font  = T:GetToken("fontFamilyMain") or "Fonts/FRIZQT__.TTF"
    local skey  = sizemap[self._size] or "fontSizeMd"
    local size  = T:GetToken(skey) or 13
    local ckey  = colmap[self._color] or "colorText"
    local col   = T:GetToken(ckey) or {0.92, 0.92, 0.92, 1}
    self._fs:SetFont(font, size, self._flags or "")
    self._fs:SetTextColor(col[1], col[2], col[3], col[4])
end

--- Creates a themed text element.
-- @param props table  { text, size, color, flags, w, h, justify, wrap }
--   size: "sm"|"md"|"lg"|"xl"   color: "text"|"muted"|"disable"|"accent"
--   justify: "LEFT"|"CENTER"|"RIGHT" (default: "LEFT")
-- @param parent frame
-- @return table  Text handle
function SuuUI.Components.Text(props, parent)
    local fs = parent:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    if props.w and props.h then fs:SetSize(props.w, props.h) end
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
    }, TextMeta)
    handle:ApplyTheme()
    SuuUI.Events:On("SUUUI_THEME_CHANGED", function() handle:ApplyTheme() end, id)
    return handle
end
