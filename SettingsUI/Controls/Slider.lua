local C = SuuUI.Components
local S = SuuUI.UISignals

--- Builds a slider control row.
-- @param entry table    Schema entry { key, label, min, max, step, default }
-- @param pluginId string
-- @param parent frame
-- @return table  Row container handle
local function Build(entry, pluginId, parent)
    local row = SuuUI._SettingsRow.Stacked(parent)

    local sld = C.Slider({
        label = entry.label,
        min   = entry.min  or 0,
        max   = entry.max  or 100,
        step  = entry.step or 1,
    }, row:GetFrame())
    row:Add(sld, { width = "fill" })

    S:Connect(sld, S.SIGNALS.VALUE_CHANGED, function(val)
        SuuUI.Settings:Set(pluginId, entry.key, val)
    end)

    SuuUI.Settings:Watch(pluginId, entry.key, function(val)
        sld:SetValue(val)
    end, SuuUI.Settings.ControlOwner(pluginId, "slider", entry.key), { immediate = true })

    return row
end

if not SuuUI._SettingsControls then SuuUI._SettingsControls = {} end
SuuUI._SettingsControls["slider"] = Build
