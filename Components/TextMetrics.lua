local ceil = math.ceil
local type = type

local host, probe

local M = {}

local function ensureProbe()
    if probe then return end
    host = CreateFrame("Frame", "SuuUI_textMetrics_probe", UIParent)
    host:Hide()
    probe = host:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    probe:SetWordWrap(false)
end

--- Measures a string at an explicit font, free of any layout-imposed width.
-- Never measure a font string a layout has already sized: GetStringWidth is clamped
-- to the assigned width, so a truncated label reports the truncated width and any
-- fit-to-text pass ratchets it down until only an ellipsis is left. The probe font
-- string here is never sized or anchored, so it always reports the real text width.
-- @param text string
-- @param font string   Font file path
-- @param size number
-- @param flags string  Optional outline flags
-- @return number, number  width, height in pixels
function M.Measure(text, font, size, flags)
    ensureProbe()
    if font and size then probe:SetFont(font, size, flags or "") end
    probe:SetText(text or "")

    local w = probe.GetUnboundedStringWidth and probe:GetUnboundedStringWidth()
              or probe:GetStringWidth()
    local h = probe:GetStringHeight()
    return ceil(w or 0), ceil(h or 0)
end

--- Reports whether the client can load a font file.
-- SetFont returns false and leaves the font untouched when the file is missing or not a
-- usable face, which is the only way to test a path — there is no filesystem API. The
-- probe's own font is restored so a validation pass never disturbs the next measurement.
-- @param path string  Font file path
-- @return bool
function M.CanLoadFont(path)
    if type(path) ~= "string" or path == "" then return false end
    ensureProbe()
    local font, size, flags = probe:GetFont()
    local ok = probe:SetFont(path, size or 12, flags or "")
    if font and size then probe:SetFont(font, size, flags or "") end
    return ok and true or false
end

SuuUI.TextMetrics = M
