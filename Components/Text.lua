local sizemap = { sm="fontSizeSm", md="fontSizeMd", lg="fontSizeLg", xl="fontSizeXl" }
local colmap  = {
    text    = "colorText",
    muted   = "colorTextMuted",
    disable = "colorTextDisable",
    accent  = "colorAccent",
}

local TextMeta = {}
TextMeta.__index = TextMeta

function TextMeta:SetSize(w, h)  self._fs:SetSize(w, h) end
function TextMeta:SetPoint(...)  self._fs:SetPoint(...) end
function TextMeta:Show()         self._fs:Show() end
function TextMeta:Hide()         self._fs:Hide() end
function TextMeta:IsShown()      return self._fs:IsShown() end
function TextMeta:GetFrame()     return self._fs end
function TextMeta:SetEnabled()   end
function TextMeta:Destroy()      SuuUI.Events:Off("SUUUI_THEME_CHANGED", self._eid) end

--- Sets the displayed text.
-- @param text string
function TextMeta:SetText(text)
    self._fs:SetText(text)
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
-- @param props table  { text, size, color, flags, w, h }
--   size: "sm"|"md"|"lg"|"xl"   color: "text"|"muted"|"disable"|"accent"
-- @param parent frame
-- @return table  Text handle
function SuuUI.Components.Text(props, parent)
    local fs = parent:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    if props.w and props.h then fs:SetSize(props.w, props.h) end
    if props.text then fs:SetText(props.text) end

    local id = "text_" .. tostring(fs)
    local handle = setmetatable({
        _fs    = fs,
        _eid   = id,
        _size  = props.size  or "md",
        _color = props.color or "text",
        _flags = props.flags or "",
    }, TextMeta)
    handle:ApplyTheme()
    SuuUI.Events:On("SUUUI_THEME_CHANGED", function() handle:ApplyTheme() end, id)
    return handle
end
