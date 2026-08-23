local C = SuuUI.Components
local S = SuuUI.UISignals

--- Builds a dropdown control row.
-- @param entry table    Schema entry { key, label, options, default, owner }
-- @param pluginId string
-- @param parent frame
-- @return table  Row container handle
local function Build(entry, pluginId, parent)
    local row, label = SuuUI._SettingsRow.Labelled(parent, entry.label)
    -- Data namespace only; the watcher owner stays the page's. See Controls/Toggle.lua.
    local dataId = entry.owner or pluginId

    local dd = C.Dropdown({
        options = entry.options or {},
        w       = 140,
    }, row:GetFrame())
    -- Height omitted: the dropdown derives it from its size and font tokens
    row:Add(dd, { width = 140 })

    S:Connect(dd, S.SIGNALS.VALUE_CHANGED, function(val)
        SuuUI.Settings:Set(dataId, entry.key, val)
    end)

    SuuUI.Settings:Watch(dataId, entry.key, function(val)
        dd:SetValue(val)
    end, SuuUI.Settings.ControlOwner(pluginId, "dropdown", entry.key), { immediate = true })

    -- Greys the row out while a setting it depends on is off. No-op without enabledIf.
    -- The label is a sibling in the row, not a child of the control, so it has to be
    -- passed explicitly or half the row keeps looking live.
    SuuUI._SettingsDeps.Bind(pluginId, entry, dd, label)

    return row
end

if not SuuUI._SettingsControls then SuuUI._SettingsControls = {} end
SuuUI._SettingsControls["dropdown"] = Build
