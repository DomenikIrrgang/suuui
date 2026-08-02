local C = SuuUI.Components

local function modString(ctrl, alt, shift)
    local s = ""
    if ctrl  then s = s .. "CTRL-"  end
    if alt   then s = s .. "ALT-"   end
    if shift then s = s .. "SHIFT-" end
    return s
end

--- Builds a keybind capture control row.
-- @param entry table    Schema entry { key, label, default }
-- @param pluginId string
-- @param parent frame
-- @return frame         Raw frame, height=32
local function Build(entry, pluginId, parent)
    local f = CreateFrame("Frame", nil, parent)
    f:SetSize(parent:GetWidth(), 32)

    local lbl = C.Text({ text = entry.label, size = "md" }, f)
    lbl:SetPoint("LEFT", f, "LEFT", 8, 0)

    local btn = C.Button({
        label = SuuUI.Settings:Get(pluginId, entry.key) or "Not Bound",
        w = 120, h = 22,
    }, f)
    btn:SetPoint("RIGHT", f, "RIGHT", -8, 0)

    local capturing = false

    -- Capture frame for key detection
    local capture = CreateFrame("Frame", nil, f)
    capture:SetAllPoints(f)
    capture:EnableKeyboard(false)
    capture:SetPropagateKeyboardInput(false)

    capture:SetScript("OnKeyDown", function(_, key)
        if key == "ESCAPE" then
            capturing = false
            capture:EnableKeyboard(false)
            btn:SetLabel(SuuUI.Settings:Get(pluginId, entry.key) or "Not Bound")
            return
        end
        if key == "LSHIFT" or key == "RSHIFT" or
           key == "LCTRL"  or key == "RCTRL"  or
           key == "LALT"   or key == "RALT"   then return end

        local mods = modString(IsControlKeyDown(), IsAltKeyDown(), IsShiftKeyDown())
        local bind = mods .. key
        capturing = false
        capture:EnableKeyboard(false)
        SuuUI.Settings:Set(pluginId, entry.key, bind)
        btn:SetLabel(bind)
    end)

    btn:GetFrame():SetScript("OnMouseUp", function()
        if capturing then return end
        capturing = true
        capture:EnableKeyboard(true)
        btn:SetLabel("Press key...")
    end)

    SuuUI.Events:On("SUUUI_PROFILE_LOADED", function()
        btn:SetLabel(SuuUI.Settings:Get(pluginId, entry.key) or "Not Bound")
    end, "ctrl_bind_" .. pluginId .. entry.key)

    return f
end

if not SuuUI._SettingsControls then SuuUI._SettingsControls = {} end
SuuUI._SettingsControls["keybind"] = Build
