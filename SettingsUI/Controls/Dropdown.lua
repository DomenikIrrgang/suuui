local C = SuuUI.Components

--- Builds a dropdown control row.
-- @param entry table    Schema entry { key, label, options, default }
-- @param pluginId string
-- @param parent frame
-- @return frame         Raw frame, height=32
local function Build(entry, pluginId, parent)
    local f = CreateFrame("Frame", nil, parent)
    f:SetSize(parent:GetWidth(), 32)

    local lbl = C.Text({ text = entry.label, size = "md" }, f)
    lbl:SetPoint("LEFT", f, "LEFT", 8, 0)

    local dd = C.Dropdown({
        options  = entry.options or {},
        value    = SuuUI.Settings:Get(pluginId, entry.key),
        w        = 140,
        onChange = function(val)
            SuuUI.Settings:Set(pluginId, entry.key, val)
        end,
    }, f)
    dd:SetPoint("RIGHT", f, "RIGHT", -8, 0)

    -- Update dropdown when profile loads
    SuuUI.Events:On("SUUUI_PROFILE_LOADED", function()
        dd:SetValue(SuuUI.Settings:Get(pluginId, entry.key))
    end, "ctrl_dropdown_" .. pluginId .. "_" .. entry.key)

    return f
end

if not SuuUI._SettingsControls then SuuUI._SettingsControls = {} end
SuuUI._SettingsControls["dropdown"] = Build
