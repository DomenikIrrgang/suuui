local C = SuuUI.Components
local S = SuuUI.UISignals

--- Builds a slider control row.
-- @param entry table    Schema entry { key, label, min, max, step, default }
-- @param pluginId string
-- @param parent frame
-- @return table  Row container handle
local function Build(entry, pluginId, parent)
    local row = SuuUI._SettingsRow.Stacked(parent, 44)

    local sld = C.Slider({
        label = entry.label,
        value = SuuUI.Settings:Get(pluginId, entry.key),
        min   = entry.min  or 0,
        max   = entry.max  or 100,
        step  = entry.step or 1,
    }, row:GetFrame())
    row:Add(sld, { width = "fill", height = 36 })

    S:Connect(sld, S.SIGNALS.VALUE_CHANGED, function(val)
        SuuUI.Settings:Set(pluginId, entry.key, val)
    end)

    SuuUI.Events:On("SUUUI_PROFILE_LOADED", function()
        sld:SetValue(SuuUI.Settings:Get(pluginId, entry.key))
    end, "ctrl_slider_" .. pluginId .. "_" .. entry.key)

    return row
end

if not SuuUI._SettingsControls then SuuUI._SettingsControls = {} end
SuuUI._SettingsControls["slider"] = Build
