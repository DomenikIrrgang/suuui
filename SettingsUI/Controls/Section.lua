-- Section control: renders a labelled divider, no value storage.
local C = SuuUI.Components

--- Builds a section header row.
-- @param entry table   Schema entry { label }
-- @param parent frame
-- @return table  Row container handle
local function Build(entry, parent)
    local row = SuuUI._SettingsRow.Stacked(parent, 28)

    local div = C.Divider({ label = entry.label }, row:GetFrame())
    row:Add(div, { width = "fill", height = 28 })

    return row
end

if not SuuUI._SettingsControls then SuuUI._SettingsControls = {} end
SuuUI._SettingsControls["section"] = Build
