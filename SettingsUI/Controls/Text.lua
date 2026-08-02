local C = SuuUI.Components
local S = SuuUI.UISignals

--- Builds a text input control row.
-- @param entry table    Schema entry { key, label, default }
-- @param pluginId string
-- @param parent frame
-- @return table  Row container handle
local function Build(entry, pluginId, parent)
    local row = SuuUI._SettingsRow.Labelled(parent, entry.label, 32)

    local inp = C.Input({
        value = SuuUI.Settings:Get(pluginId, entry.key) or "",
        w     = 140,
        h     = 22,
    }, row:GetFrame())
    row:Add(inp, { width = 140, height = 22 })

    S:Connect(inp, S.SIGNALS.TEXT_CHANGED, function(text)
        SuuUI.Settings:Set(pluginId, entry.key, text)
    end)

    SuuUI.Events:On("SUUUI_PROFILE_LOADED", function()
        inp:SetValue(SuuUI.Settings:Get(pluginId, entry.key) or "")
    end, "ctrl_text_" .. pluginId .. entry.key)

    return row
end

if not SuuUI._SettingsControls then SuuUI._SettingsControls = {} end
SuuUI._SettingsControls["text"] = Build
