local C = SuuUI.Components
local S = SuuUI.UISignals

--- Builds a colour control row: label plus a swatch that opens the shared picker.
-- @param entry table    Schema entry { key, label, default }
-- @param pluginId string
-- @param parent frame
-- @return table  Row container handle
local function Build(entry, pluginId, parent)
    local row = SuuUI._SettingsRow.Labelled(parent, entry.label)

    -- Size comes from the swatch's own size token
    local swatch = C.ColorSwatch({}, row:GetFrame())
    row:Add(swatch)

    S:Connect(swatch, S.SIGNALS.CLICKED, function()
        local val = SuuUI.Settings:Get(pluginId, entry.key) or entry.default or {1, 1, 1, 1}
        SuuUI._ColorPopup.Open(swatch, val, function(r, g, b, a)
            SuuUI.Settings:Set(pluginId, entry.key, { r, g, b, a })
        end)
    end)

    SuuUI.Settings:Watch(pluginId, entry.key, function(val)
        -- A colour must always resolve to something paintable: an unset key would
        -- otherwise leave the swatch with no colour at all.
        local c = val or entry.default or {1, 1, 1, 1}
        swatch:SetValue(c[1], c[2], c[3], c[4] or 1)
    end, SuuUI.Settings.ControlOwner(pluginId, "color", entry.key), { immediate = true })

    return row
end

if not SuuUI._SettingsControls then SuuUI._SettingsControls = {} end
SuuUI._SettingsControls["color"] = Build
