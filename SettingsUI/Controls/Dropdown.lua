local C = SuuUI.Components
local S = SuuUI.UISignals

--- Builds a dropdown control row.
-- @param entry table    Schema entry { key, label, options, default }
-- @param pluginId string
-- @param parent frame
-- @return table  Row container handle
local function Build(entry, pluginId, parent)
    local row = SuuUI._SettingsRow.Labelled(parent, entry.label)

    local dd = C.Dropdown({
        options = entry.options or {},
        w       = 140,
    }, row:GetFrame())
    -- Height omitted: the dropdown derives it from its size and font tokens
    row:Add(dd, { width = 140 })

    S:Connect(dd, S.SIGNALS.VALUE_CHANGED, function(val)
        SuuUI.Settings:Set(pluginId, entry.key, val)
    end)

    SuuUI.Settings:Watch(pluginId, entry.key, function(val)
        dd:SetValue(val)
    end, SuuUI.Settings.ControlOwner(pluginId, "dropdown", entry.key), { immediate = true })

    return row
end

if not SuuUI._SettingsControls then SuuUI._SettingsControls = {} end
SuuUI._SettingsControls["dropdown"] = Build
