local ceil = math.ceil
local type = type

local host, probe

local M = {}

-- The space a measurement has to be taken in.
--
-- Font rasterisation is scale-dependent: the client rounds `size * effectiveScale` to a
-- whole pixel and stores glyph advances per rasterised size, so the SAME font at the SAME
-- point size reports a different width under two different effective scales. The pixel
-- grid puts a scale on the root, so a probe left on UIParent measures in a space nothing
-- renders in, and it under-reports by a fraction of a unit — which is all it takes, since
-- the client truncates with no tolerance at all.
local function measureSpace()
    local R = SuuUI.UIRoot
    local root = R and R.GetRoot and R:GetRoot()
    return root or UIParent
end

local function ensureProbe()
    local want = measureSpace()
    if probe then
        -- Re-homed rather than parented once: the first measurement can happen before
        -- UIRoot:Init() has built the root, and a probe stranded on UIParent would go on
        -- measuring in the wrong space for the rest of the session.
        if host:GetParent() ~= want then host:SetParent(want) end
        return
    end
    host = CreateFrame("Frame", "SuuUI_textMetrics_probe", want)
    host:Hide()
    probe = host:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    -- Wrap ON, which sounds wrong for an unbounded measurement and is not: the probe is never
    -- given a width, so there is no bound to wrap against and a single line is returned whole.
    -- What it buys is that an explicit newline is measured as the rows it will actually render
    -- as. With wrap off the client collapses a newline into one row, so the probe reported one
    -- row's height for a two-row string and every caller sizing a multi-row element got a box
    -- half as tall as it needed.
    probe:SetWordWrap(true)
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

--- The box a string needs in order to RENDER without the client truncating it.
--
-- Measure reports the text's metric width; this reports the width to reserve for it. The
-- two are not the same number, because the client truncates with zero tolerance — a box
-- short by any amount at all drops characters and draws an ellipsis — while whole-pixel
-- rasterisation and per-glyph advance accumulation mean the metric and the rendered
-- extent need not agree exactly. One physical pixel of allowance covers the disagreement.
--
-- Use this wherever a font string's own box is sized from its text. Measure stays the raw
-- metric, for callers that add slack of their OWN on top of it (Button, Dropdown's arrow
-- column, both +2).
--
-- Outer padding does not make a caller a Measure caller. A component that sizes itself to
-- `text + insets` and then lays the label out with those same insets has handed the whole
-- metric back to the label, so the label's box lands at exactly the metric and the client
-- truncates it — NavItem's hugging tab strip rendered "Play…" for "Player" that way, with
-- every geometry assertion passing. Ask what the font string's own box ends up being.
-- @param text string
-- @param font string   Font file path
-- @param size number
-- @param flags string  Optional outline flags
-- @return number, number  width, height to reserve
function M.Box(text, font, size, flags)
    local w, h = M.Measure(text, font, size, flags)
    local P = SuuUI.Pixel
    -- An empty string reserves nothing. A hugging label has to collapse back to zero when
    -- its text is cleared, so the allowance is for real glyphs only.
    if not P or w <= 0 then return w, h end
    -- Pixel.mult is one physical pixel expressed in units, so the allowance is one real
    -- pixel at every resolution rather than a number chosen here.
    --
    -- Width only. A box one pixel narrow drops characters outright, whereas the height
    -- Measure already ceils covers the glyphs — and padding it too would make every label
    -- a pixel taller than the token-sized control that has to contain it.
    return P.Ceil(w + (P.mult or 0)), h
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
