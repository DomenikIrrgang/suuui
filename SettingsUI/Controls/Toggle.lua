local C = SuuUI.Components
local S = SuuUI.UISignals

--- Builds a toggle control row.
-- @param entry table    Schema entry { key, label, default }
-- @param pluginId string
-- @param parent frame
-- @return table  Row container handle
local function Build(entry, pluginId, parent)
    local row, label = SuuUI._SettingsRow.Labelled(parent, entry.label)

    local tog = C.Toggle({}, row:GetFrame())
    -- Size comes from the toggle's own size tokens; omitting the props keeps them
    row:Add(tog)

    S:Connect(tog, S.SIGNALS.VALUE_CHANGED, function(val)
        SuuUI.Settings:Set(pluginId, entry.key, val)
    end)

    -- The watcher is the only thing that sets the displayed value, initial state
    -- included, so the widget cannot start out disagreeing with the store.
    SuuUI.Settings:Watch(pluginId, entry.key, function(val)
        tog:SetValue(val)
    end, SuuUI.Settings.ControlOwner(pluginId, "toggle", entry.key), { immediate = true })

    -- Greys the row out while a setting it depends on is off. No-op without enabledIf.
    SuuUI._SettingsDeps.Bind(pluginId, entry, tog, label)

    return row
end

if not SuuUI._SettingsControls then SuuUI._SettingsControls = {} end
SuuUI._SettingsControls["toggle"] = Build
