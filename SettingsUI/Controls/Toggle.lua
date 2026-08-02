local C = SuuUI.Components

--- Builds a toggle control row.
-- @param entry table    Schema entry { key, label, default }
-- @param pluginId string
-- @param parent frame
-- @return frame         Raw frame, height=28
local function Build(entry, pluginId, parent)
    local f = CreateFrame("Frame", nil, parent)
    f:SetSize(parent:GetWidth(), 28)

    local lbl = C.Text({ text = entry.label, size = "md" }, f)
    lbl:SetPoint("LEFT", f, "LEFT", 8, 0)

    local tog = C.Toggle({
        value    = SuuUI.Settings:Get(pluginId, entry.key),
        onChange = function(val)
            SuuUI.Settings:Set(pluginId, entry.key, val)
        end,
    }, f)
    tog:SetPoint("RIGHT", f, "RIGHT", -8, 0)

    -- Update toggle when profile loads
    SuuUI.Events:On("SUUUI_PROFILE_LOADED", function()
        tog:SetValue(SuuUI.Settings:Get(pluginId, entry.key))
    end, "ctrl_toggle_" .. pluginId .. "_" .. entry.key)

    return f
end

if not SuuUI._SettingsControls then SuuUI._SettingsControls = {} end
SuuUI._SettingsControls["toggle"] = Build
