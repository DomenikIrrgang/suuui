local C = SuuUI.Components
local S = SuuUI.UISignals

--- Builds a slider control row.
-- @param entry table    Schema entry { key, label, min, max, step, default, owner }
-- @param pluginId string
-- @param parent frame
-- @return table  Row container handle
local function Build(entry, pluginId, parent)
    local row = SuuUI._SettingsRow.Stacked(parent)
    -- Data namespace only; the watcher owner stays the page's. See Controls/Toggle.lua.
    local dataId = entry.owner or pluginId

    local sld = C.Slider({
        label = entry.label,
        min   = entry.min  or 0,
        max   = entry.max  or 100,
        step  = entry.step or 1,
    }, row:GetFrame())
    row:Add(sld, { width = "fill" })

    S:Connect(sld, S.SIGNALS.VALUE_CHANGED, function(val)
        SuuUI.Settings:Set(dataId, entry.key, val)
    end)

    SuuUI.Settings:Watch(dataId, entry.key, function(val)
        sld:SetValue(val)
    end, SuuUI.Settings.ControlOwner(pluginId, "slider", entry.key), { immediate = true })

    -- Greys the row out while a setting it depends on is off. No-op without enabledIf.
    -- Only the slider is passed: it owns its own label strip, so the root-frame fade
    -- already covers the text.
    SuuUI._SettingsDeps.Bind(pluginId, entry, sld)

    return row
end

if not SuuUI._SettingsControls then SuuUI._SettingsControls = {} end
SuuUI._SettingsControls["slider"] = Build
