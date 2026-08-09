    local C = SuuUI.Components
local S = SuuUI.UISignals

--- Builds a text input control row.
-- @param entry table    Schema entry { key, label, default }
-- @param pluginId string
-- @param parent frame
-- @return table  Row container handle
local function Build(entry, pluginId, parent)
    local row, label = SuuUI._SettingsRow.Labelled(parent, entry.label)

    local inp = C.Input({
        w = 140,
    }, row:GetFrame())
    -- Height omitted: the input derives it from its size and font tokens
    row:Add(inp, { width = 140 })

    S:Connect(inp, S.SIGNALS.TEXT_CHANGED, function(text)
        SuuUI.Settings:Set(pluginId, entry.key, text)
    end)

    SuuUI.Settings:Watch(pluginId, entry.key, function(val)
        inp:SetValue(val or "")
    end, SuuUI.Settings.ControlOwner(pluginId, "text", entry.key), { immediate = true })

    -- Greys the row out while a setting it depends on is off. No-op without enabledIf.
    -- The label is a sibling in the row, not a child of the control, so it has to be
    -- passed explicitly or half the row keeps looking live.
    SuuUI._SettingsDeps.Bind(pluginId, entry, inp, label)

    return row
end

if not SuuUI._SettingsControls then SuuUI._SettingsControls = {} end
SuuUI._SettingsControls["text"] = Build
