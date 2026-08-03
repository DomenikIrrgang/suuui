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
    if font and size then
        -- The client raises on an invalid asset, and a measurement is never worth a Lua
        -- error. Degrade to the probe's current face and name the culprit instead.
        local ok = pcall(probe.SetFont, probe, font, size, flags or "")
        if not ok then
            SuuUI.Debug("TextMetrics: cannot load font " .. tostring(font))
        end
    end
    probe:SetText(text or "")

    local w = probe.GetUnboundedStringWidth and probe:GetUnboundedStringWidth()
              or probe:GetStringWidth()
    local h = probe:GetStringHeight()
    return ceil(w or 0), ceil(h or 0)
end

--- Reports whether the client can load a font file.
-- Applying the font is the only way to test it — there is no filesystem API. The client
-- **raises** on an invalid asset ("Invalid font asset (X): file not found") rather than
-- just returning false, so the probe is protected: an unguarded one takes down whatever
-- was iterating font candidates. The probe's own font is restored either way, so a
-- validation pass never disturbs the next measurement.
-- @param path string  Font file path
-- @return bool
function M.CanLoadFont(path)
    if type(path) ~= "string" or path == "" then return false end
    ensureProbe()
    local font, size, flags = probe:GetFont()
    local ok, applied = pcall(probe.SetFont, probe, path, size or 12, flags or "")
    if font and size then pcall(probe.SetFont, probe, font, size, flags or "") end
    return ok and applied ~= false
end

SuuUI.TextMetrics = M
