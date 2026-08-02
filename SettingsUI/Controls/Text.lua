local C = SuuUI.Components

--- Builds a text input control row.
-- @param entry table    Schema entry { key, label, default }
-- @param pluginId string
-- @param parent frame
-- @return frame         Raw frame, height=32
local function Build(entry, pluginId, parent)
    local f = CreateFrame("Frame", nil, parent)
    f:SetSize(parent:GetWidth(), 32)

    local lbl = C.Text({ text = entry.label, size = "md" }, f)
    lbl:SetPoint("LEFT", f, "LEFT", 8, 0)

    local inp = C.Input({
        value    = SuuUI.Settings:Get(pluginId, entry.key) or "",
        w        = 140,
        h        = 22,
        onChange = function(val)
            SuuUI.Settings:Set(pluginId, entry.key, val)
        end,
    }, f)
    inp:SetPoint("RIGHT", f, "RIGHT", -8, 0)

    -- sync on profile switch
    SuuUI.Events:On("SUUUI_PROFILE_LOADED", function()
        inp:SetValue(SuuUI.Settings:Get(pluginId, entry.key) or "")
    end, "ctrl_text_" .. pluginId .. entry.key)

    return f
end

if not SuuUI._SettingsControls then SuuUI._SettingsControls = {} end
SuuUI._SettingsControls["text"] = Build
