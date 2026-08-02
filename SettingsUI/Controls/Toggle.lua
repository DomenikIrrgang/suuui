local C = SuuUI.Components
local S = SuuUI.UISignals

--- Builds a toggle control row.
-- @param entry table    Schema entry { key, label, default }
-- @param pluginId string
-- @param parent frame
-- @return table  Row container handle
local function Build(entry, pluginId, parent)
    local row = SuuUI._SettingsRow.Labelled(parent, entry.label)

    local tog = C.Toggle({
        value = SuuUI.Settings:Get(pluginId, entry.key),
    }, row:GetFrame())
    -- Size comes from the toggle's own size tokens; omitting the props keeps them
    row:Add(tog)

    S:Connect(tog, S.SIGNALS.VALUE_CHANGED, function(val)
        SuuUI.Settings:Set(pluginId, entry.key, val)
    end)

    SuuUI.Events:On("SUUUI_PROFILE_LOADED", function()
        tog:SetValue(SuuUI.Settings:Get(pluginId, entry.key))
    end, "ctrl_toggle_" .. pluginId .. "_" .. entry.key)

    return row
end

if not SuuUI._SettingsControls then SuuUI._SettingsControls = {} end
SuuUI._SettingsControls["toggle"] = Build
