local C = SuuUI.Components

--- Builds a slider control row.
-- @param entry table    Schema entry { key, label, min, max, step, default }
-- @param pluginId string
-- @param parent frame
-- @return frame         Raw frame, height=44
local function Build(entry, pluginId, parent)
    local f = CreateFrame("Frame", nil, parent)
    f:SetSize(parent:GetWidth(), 44)

    local sld = C.Slider({
        label    = entry.label,
        value    = SuuUI.Settings:Get(pluginId, entry.key),
        min      = entry.min  or 0,
        max      = entry.max  or 100,
        step     = entry.step or 1,
        w        = parent:GetWidth() - 16,
        onChange = function(val)
            SuuUI.Settings:Set(pluginId, entry.key, val)
        end,
    }, f)
    sld:SetPoint("CENTER", f, "CENTER", 0, 0)

    -- Update slider when profile loads
    SuuUI.Events:On("SUUUI_PROFILE_LOADED", function()
        sld:SetValue(SuuUI.Settings:Get(pluginId, entry.key))
    end, "ctrl_slider_" .. pluginId .. "_" .. entry.key)

    return f
end

if not SuuUI._SettingsControls then SuuUI._SettingsControls = {} end
SuuUI._SettingsControls["slider"] = Build
