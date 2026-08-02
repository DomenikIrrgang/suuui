local C = SuuUI.Components
local S = SuuUI.UISignals

--- Builds a keybind capture control row.
-- @param entry table    Schema entry { key, label, default }
-- @param pluginId string
-- @param parent frame
-- @return table  Row container handle
local function Build(entry, pluginId, parent)
    local row = SuuUI._SettingsRow.Labelled(parent, entry.label)

    local bind = C.KeyCapture({
        value = SuuUI.Settings:Get(pluginId, entry.key) or "",
        minW  = 120,
    }, row:GetFrame())
    row:Add(bind)

    S:Connect(bind, S.SIGNALS.VALUE_CHANGED, function(val)
        SuuUI.Settings:Set(pluginId, entry.key, val)
    end)

    SuuUI.Events:On("SUUUI_PROFILE_LOADED", function()
        bind:SetValue(SuuUI.Settings:Get(pluginId, entry.key) or "")
    end, "ctrl_bind_" .. pluginId .. entry.key)

    return row
end

if not SuuUI._SettingsControls then SuuUI._SettingsControls = {} end
SuuUI._SettingsControls["keybind"] = Build
