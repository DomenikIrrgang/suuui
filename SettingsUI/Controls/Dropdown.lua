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
        value   = SuuUI.Settings:Get(pluginId, entry.key),
        w       = 140,
    }, row:GetFrame())
    -- Height omitted: the dropdown derives it from its size and font tokens
    row:Add(dd, { width = 140 })

    S:Connect(dd, S.SIGNALS.VALUE_CHANGED, function(val)
        SuuUI.Settings:Set(pluginId, entry.key, val)
    end)

    SuuUI.Events:On("SUUUI_PROFILE_LOADED", function()
        dd:SetValue(SuuUI.Settings:Get(pluginId, entry.key))
    end, "ctrl_dropdown_" .. pluginId .. "_" .. entry.key)

    return row
end

if not SuuUI._SettingsControls then SuuUI._SettingsControls = {} end
SuuUI._SettingsControls["dropdown"] = Build
