-- Section control: renders a labelled divider, no value storage.
local C = SuuUI.Components

--- Builds a section header row.
-- @param entry table   Schema entry { label }
-- @param parent frame
-- @return frame        Raw frame, height=28
local function Build(entry, parent)
    local f = CreateFrame("Frame", nil, parent)
    f:SetSize(parent:GetWidth(), 28)

    local div = C.Divider({ label = entry.label, w = parent:GetWidth() - 16 }, f)
    div:SetPoint("CENTER", f, "CENTER", 0, 0)

    return f
end

if not SuuUI._SettingsControls then SuuUI._SettingsControls = {} end
SuuUI._SettingsControls["section"] = Build
