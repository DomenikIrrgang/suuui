local C = SuuUI.Components
local S = SuuUI.UISignals

--- Builds a colour control row: label plus a swatch that opens the shared picker.
-- @param entry table    Schema entry { key, label, default }
-- @param pluginId string
-- @param parent frame
-- @return table  Row container handle
local function Build(entry, pluginId, parent)
    local row = SuuUI._SettingsRow.Labelled(parent, entry.label)

    local current = SuuUI.Settings:Get(pluginId, entry.key) or entry.default or {1, 1, 1, 1}

    local swatch = C.ColorSwatch({ value = current, w = 22 }, row:GetFrame())
    row:Add(swatch, { width = 22, height = 22 })

    S:Connect(swatch, S.SIGNALS.CLICKED, function()
        local val = SuuUI.Settings:Get(pluginId, entry.key) or entry.default or {1, 1, 1, 1}
        SuuUI._ColorPopup.Open(swatch, val, function(r, g, b, a)
            SuuUI.Settings:Set(pluginId, entry.key, { r, g, b, a })
        end)
    end)

    SuuUI.Events:On("SUUUI_SETTING_CHANGED", function(pid, key, val)
        if pid == pluginId and key == entry.key and val then
            swatch:SetValue(val[1], val[2], val[3], val[4] or 1)
        end
    end, "ctrl_color_" .. pluginId .. entry.key)

    return row
end

if not SuuUI._SettingsControls then SuuUI._SettingsControls = {} end
SuuUI._SettingsControls["color"] = Build
