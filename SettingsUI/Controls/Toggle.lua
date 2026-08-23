local C = SuuUI.Components
local S = SuuUI.UISignals

--- Builds a toggle control row.
-- @param entry table    Schema entry { key, label, default, owner }
-- @param pluginId string
-- @param parent frame
-- @return table  Row container handle
local function Build(entry, pluginId, parent)
    local row, label = SuuUI._SettingsRow.Labelled(parent, entry.label)

    -- `owner` names the plugin whose NAMESPACE this entry's value lives in, for an entry
    -- rendered on someone else's page: a data bar widget contributed by another plugin is
    -- configured here, while its settings stay that plugin's own data — profile-scoped to
    -- it, and surviving the widget being unregistered.
    --
    -- It changes the DATA namespace only, never the watcher OWNER string. PageBuilder
    -- retires a rebuilt page's watchers with UnwatchPrefix(ControlOwnerPrefix(pluginId)),
    -- and SubTabs retires a swapped tab's with UnwatchControls(pluginId, schema) — both
    -- derived from the PAGE's pluginId. Keying a watcher to the contributor instead would
    -- leak one on every rebuild, and the leaked watcher then fires into a destroyed widget
    -- on every write to that key and on every profile switch.
    local dataId = entry.owner or pluginId

    local tog = C.Toggle({}, row:GetFrame())
    -- Size comes from the toggle's own size tokens; omitting the props keeps them
    row:Add(tog)

    S:Connect(tog, S.SIGNALS.VALUE_CHANGED, function(val)
        SuuUI.Settings:Set(dataId, entry.key, val)
    end)

    -- The watcher is the only thing that sets the displayed value, initial state
    -- included, so the widget cannot start out disagreeing with the store.
    SuuUI.Settings:Watch(dataId, entry.key, function(val)
        tog:SetValue(val)
    end, SuuUI.Settings.ControlOwner(pluginId, "toggle", entry.key), { immediate = true })

    -- Greys the row out while a setting it depends on is off. No-op without enabledIf.
    SuuUI._SettingsDeps.Bind(pluginId, entry, tog, label)

    return row
end

if not SuuUI._SettingsControls then SuuUI._SettingsControls = {} end
SuuUI._SettingsControls["toggle"] = Build
