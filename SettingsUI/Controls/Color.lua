local C = SuuUI.Components

--- Builds a color picker control row with inline swatch + expand button.
-- @param entry table    Schema entry { key, label, default }
-- @param pluginId string
-- @param parent frame
-- @return frame         Raw frame, height=32
local function Build(entry, pluginId, parent)
    local f = CreateFrame("Frame", nil, parent)
    f:SetSize(parent:GetWidth(), 32)

    local lbl = C.Text({ text = entry.label, size = "md" }, f)
    lbl:SetPoint("LEFT", f, "LEFT", 8, 0)

    -- Swatch showing current color
    local swatch = CreateFrame("Frame", nil, f, "BackdropTemplate")
    swatch:SetSize(22, 22)
    swatch:SetPoint("RIGHT", f, "RIGHT", -8, 0)
    swatch:SetBackdrop({
        bgFile="Interface\\Buttons\\WHITE8x8",
        edgeFile="Interface\\Buttons\\WHITE8x8",
        edgeSize=1, insets={left=1,right=1,top=1,bottom=1},
    })
    swatch:EnableMouse(true)

    local current = SuuUI.Settings:Get(pluginId, entry.key) or entry.default or {1,1,1,1}
    swatch:SetBackdropColor(current[1], current[2], current[3], current[4] or 1)

    -- Expanded picker panel (hidden by default)
    local picker = C.ColorPicker({
        value    = current,
        onChange = function(r, g, b, a)
            swatch:SetBackdropColor(r, g, b, a)
            SuuUI.Settings:Set(pluginId, entry.key, {r, g, b, a})
        end,
    }, UIParent)
    picker:SetPoint("TOPRIGHT", swatch, "BOTTOMRIGHT", 0, -4)
    picker:Hide()

    swatch:SetScript("OnMouseUp", function()
        if picker:IsShown() then
            SuuUI.Anim.Presets.FadeOut(picker:GetFrame(), SuuUI.Theme:GetToken("animFast"))
        else
            picker:GetFrame():SetAlpha(0)
            picker:Show()
            SuuUI.Anim.Presets.FadeIn(picker:GetFrame(), SuuUI.Theme:GetToken("animFast"))
        end
    end)

    -- Update swatch if setting changes externally (e.g. profile switch)
    SuuUI.Events:On("SUUUI_SETTING_CHANGED", function(pid, key, val)
        if pid == pluginId and key == entry.key and val then
            swatch:SetBackdropColor(val[1], val[2], val[3], val[4] or 1)
        end
    end, "ctrl_color_" .. pluginId .. entry.key)

    return f
end

if not SuuUI._SettingsControls then SuuUI._SettingsControls = {} end
SuuUI._SettingsControls["color"] = Build
