local ceil = math.ceil

local host, probe

local M = {}

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
    if not probe then
        host = CreateFrame("Frame", "SuuUI_textMetrics_probe", UIParent)
        host:Hide()
        probe = host:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        probe:SetWordWrap(false)
    end
    if font and size then probe:SetFont(font, size, flags or "") end
    probe:SetText(text or "")

    local w = probe.GetUnboundedStringWidth and probe:GetUnboundedStringWidth()
              or probe:GetStringWidth()
    local h = probe:GetStringHeight()
    return ceil(w or 0), ceil(h or 0)
end

SuuUI.TextMetrics = M
