local tinsert, ipairs, pairs = table.insert, ipairs, pairs
local C = SuuUI.Components

--- Builds a theme manager control with theme selection and management.
-- @param entry table    Schema entry (no specific props needed)
-- @param parent frame
-- @return frame         Raw frame with container-based layout
local function Build(entry, parent)
    local T = SuuUI.Theme
    local f = CreateFrame("Frame", nil, parent)
    
    local gap = T:GetToken("spaceMd") or 8
    local tokenInputs = {}

    -- Root container for all elements
    local rootContainer = SuuUI.Layout:CreateContainer({
        parent  = f,
        layout  = "flow",
        dir     = "vertical",
        gap     = gap,
        padding = {
            top    = 0,
            right  = 0,
            bottom = 0,
            left   = 0,
        },
    })
    rootContainer:GetFrame():SetAllPoints(f)

    -- Current theme display row
    local currentRow = CreateFrame("Frame", nil, f)
    currentRow:SetSize(f:GetWidth(), 24)
    currentRow:Show()
    
    local currentLbl = C.Text({ text="Active Theme:", size="sm", color="muted" }, currentRow)
    currentLbl:GetFrame():SetPoint("LEFT", currentRow, "LEFT", 0, 0)
    currentLbl:Show()
    
    local currentName = C.Text({ 
        text=SuuUI.Theme:GetActive(), 
        size="md", 
        color="accent" 
    }, currentRow)
    currentName:GetFrame():SetPoint("LEFT", currentLbl:GetFrame(), "RIGHT", 8, 0)
    currentName:Show()
    
    rootContainer:Add(currentRow, { width = "fill", height = 24 })

    -- Theme dropdown
    local themeDD
    local function updateDropdown()
        local themes = SuuUI.Theme:List()
        local options = {}
        for _, name in ipairs(themes) do
            tinsert(options, { value=name, label=name })
        end
        return options
    end
    
    -- Function to update control enabled state based on theme
    local function updateInputsEnabled()
        local active = SuuUI.Theme:GetActive()
        local isBuiltin = SuuUI.Theme:IsBuiltin(active)
        
        for _, data in pairs(tokenInputs) do
            data.control:SetEnabled(not isBuiltin)
        end
    end

    themeDD = C.Dropdown({
        options  = updateDropdown(),
        value    = SuuUI.Theme:GetActive(),
        w        = 200,
        onChange = function(val)
            SuuUI.Theme:SetActive(val)
            currentName:SetText(val)
            updateInputsEnabled()
        end,
    }, f)
    rootContainer:Add(themeDD:GetFrame(), { height = 32 })

    -- Button row
    local btnRow = CreateFrame("Frame", nil, f)
    btnRow:SetSize(f:GetWidth(), 24)
    btnRow:Show()
    
    local btnW = 80

    local createBtn = C.Button({
        label = "Create",
        w = btnW, h = 24,
        onClick = function()
            local modal = C.Modal({
                title      = "Create Theme",
                message    = "Enter new theme name:",
                input      = true,
                confirmText = "Create",
                onConfirm  = function(name)
                    if name and name ~= "" then
                        local ok, err = pcall(SuuUI.Theme.CreateUserTheme, SuuUI.Theme, name, "Modern")
                        if ok then
                            themeDD:SetOptions(updateDropdown())
                            themeDD:SetValue(name)
                            SuuUI.Theme:SetActive(name)
                            currentName:SetText(name)
                            updateInputsEnabled()
                        else
                            print("|cffff0000SuuUI:|r " .. tostring(err))
                        end
                    end
                end,
            })
            modal:Show()
        end,
    }, btnRow)
    createBtn:GetFrame():SetPoint("LEFT", btnRow, "LEFT", 0, 0)

    local deleteBtn = C.Button({
        label = "Delete",
        w = btnW, h = 24,
        onClick = function()
            local active = SuuUI.Theme:GetActive()
            
            if SuuUI.Theme:IsBuiltin(active) then
                print("|cffff0000SuuUI:|r Cannot delete built-in theme")
                return
            end
            
            local modal = C.Modal({
                title      = "Delete Theme",
                message    = "Delete '" .. active .. "'? This cannot be undone.",
                confirmText = "Delete",
                onConfirm  = function()
                    local ok, err = pcall(SuuUI.Theme.DeleteUserTheme, SuuUI.Theme, active)
                    if ok then
                        themeDD:SetOptions(updateDropdown())
                        themeDD:SetValue(SuuUI.Theme:GetActive())
                        currentName:SetText(SuuUI.Theme:GetActive())
                        updateInputsEnabled()
                    else
                        print("|cffff0000SuuUI:|r " .. tostring(err))
                    end
                end,
            })
            modal:Show()
        end,
    }, btnRow)
    deleteBtn:GetFrame():SetPoint("LEFT", createBtn:GetFrame(), "RIGHT", 8, 0)
    
    local resetBtn = C.Button({
        label = "Reset",
        w = btnW, h = 24,
        onClick = function()
            local active = SuuUI.Theme:GetActive()
            
            if SuuUI.Theme:IsBuiltin(active) then
                print("|cffff0000SuuUI:|r Cannot reset built-in theme")
                return
            end
            
            local modal = C.Modal({
                title      = "Reset Theme",
                message    = "Reset '" .. active .. "' to default Modern theme values?",
                confirmText = "Reset",
                onConfirm  = function()
                    local ok, err = pcall(SuuUI.Theme.ResetUserTheme, SuuUI.Theme, active)
                    if ok then
                        -- Refresh all token inputs
                        for key, data in pairs(tokenInputs) do
                            data.updateValue()
                        end
                        print("|cff00ff00SuuUI:|r Theme reset to defaults")
                    else
                        print("|cffff0000SuuUI:|r " .. tostring(err))
                    end
                end,
            })
            modal:Show()
        end,
    }, btnRow)
    resetBtn:GetFrame():SetPoint("LEFT", deleteBtn:GetFrame(), "RIGHT", 8, 0)
    
    rootContainer:Add(btnRow, { width = "fill", height = 24 })

    -- Info text
    local infoText = C.Text({
        text  = "Built-in themes (Default, Modern) cannot be edited.\nCreate a new theme to customize tokens.",
        size  = "sm",
        color = "muted",
    }, f)
    infoText:GetFrame():SetHeight(32)
    rootContainer:Add(infoText:GetFrame(), { width = "fill", height = 32 })

    -- Token editor section (always visible)
    local tokenEditorFrame = CreateFrame("Frame", nil, f)
    
    local tokenRowsContainer = SuuUI.Layout:CreateContainer({
        parent  = tokenEditorFrame,
        layout  = "flow",
        dir     = "vertical",
        gap     = 4,
        padding = {top=0, right=0, bottom=0, left=0},
    })
    tokenRowsContainer:GetFrame():SetAllPoints(tokenEditorFrame)

    -- Create token editor rows with appropriate controls
    local editableTokens = {
        -- Colors (use ColorPicker)
        {key="colorBg", label="Background", type="color"},
        {key="colorBgAlt", label="Background Alt", type="color"},
        {key="colorBgHover", label="Background Hover", type="color"},
        {key="colorBgActive", label="Background Active", type="color"},
        {key="colorBlue400", label="Blue 400", type="color"},
        {key="colorBlue500", label="Blue 500", type="color"},
        {key="colorGreen400", label="Green 400", type="color"},
        {key="colorRed400", label="Red 400", type="color"},
        {key="colorYellow400", label="Yellow 400", type="color"},
        {key="colorText", label="Text", type="color"},
        {key="colorTextMuted", label="Text Muted", type="color"},
        {key="colorTextDisable", label="Text Disabled", type="color"},
        {key="colorBorder", label="Border", type="color"},
        -- Font sizes (use Slider)
        {key="fontSizeSm", label="Font Size Small", type="number", min=8, max=20, step=1},
        {key="fontSizeMd", label="Font Size Medium", type="number", min=10, max=24, step=1},
        {key="fontSizeLg", label="Font Size Large", type="number", min=12, max=28, step=1},
        {key="fontSizeXl", label="Font Size XL", type="number", min=14, max=32, step=1},
        -- Spacing (use Slider)
        {key="spaceSm", label="Space Small", type="number", min=0, max=16, step=1},
        {key="spaceMd", label="Space Medium", type="number", min=0, max=24, step=1},
        {key="spaceLg", label="Space Large", type="number", min=0, max=32, step=1},
        {key="spaceXl", label="Space XL", type="number", min=0, max=48, step=1},
        -- Other (use Slider)
        {key="borderWidth", label="Border Width", type="number", min=1, max=4, step=1},
        {key="borderRadius", label="Border Radius", type="number", min=0, max=16, step=1},
        {key="animFast", label="Animation Fast", type="number", min=0.05, max=0.5, step=0.05},
        {key="animMid", label="Animation Mid", type="number", min=0.1, max=0.8, step=0.05},
        {key="animSlow", label="Animation Slow", type="number", min=0.2, max=1.0, step=0.05},
    }
    
    for _, tokenDef in ipairs(editableTokens) do
        local tokenRow = CreateFrame("Frame", nil, tokenEditorFrame)
        
        -- Label on the left, vertically centered
        local label = C.Text({
            text  = tokenDef.label,
            size  = "sm",
            color = "text",
        }, tokenRow)
        label:GetFrame():SetPoint("LEFT", tokenRow, "LEFT", 0, 0)
        label:GetFrame():SetWidth(150)
        
        local control
        
        if tokenDef.type == "color" then
            -- Use simple color swatch + hex input for color tokens
            local currentValue = T:GetToken(tokenDef.key)
            
            -- Color swatch button
            local swatchBtn = CreateFrame("Button", nil, tokenRow)
            swatchBtn:SetSize(24, 24)
            swatchBtn:SetPoint("RIGHT", tokenRow, "RIGHT", -4, 0)
            swatchBtn:EnableMouse(true)
            swatchBtn:RegisterForClicks("LeftButtonDown")
            
            local swatchTex = swatchBtn:CreateTexture(nil, "ARTWORK")
            swatchTex:SetAllPoints()
            swatchTex:SetColorTexture(currentValue[1], currentValue[2], currentValue[3], currentValue[4])
            
            -- Border for swatch
            local swatchBorder = swatchBtn:CreateTexture(nil, "BORDER")
            swatchBorder:SetColorTexture(0.3, 0.3, 0.3, 1)
            swatchBorder:SetPoint("TOPLEFT", swatchBtn, "TOPLEFT", -1, 1)
            swatchBorder:SetPoint("BOTTOMRIGHT", swatchBtn, "BOTTOMRIGHT", 1, -1)
            swatchTex:SetDrawLayer("ARTWORK", 1)
            
            -- Hex input next to swatch
            local hexInput = C.Input({
                value = string.format("%02X%02X%02X", 
                    currentValue[1]*255, currentValue[2]*255, currentValue[3]*255),
                w = 80,
                h = 22,
                onEnter = function(text)
                    local active = SuuUI.Theme:GetActive()
                    if SuuUI.Theme:IsBuiltin(active) then return end
                    
                    -- Parse hex color
                    local hex = text:match("^#?(%x+)$")
                    if hex and #hex == 6 then
                        local r = tonumber(hex:sub(1,2), 16) / 255
                        local g = tonumber(hex:sub(3,4), 16) / 255
                        local b = tonumber(hex:sub(5,6), 16) / 255
                        
                        local ok, err = pcall(SuuUI.Theme.SetUserToken, SuuUI.Theme, active, tokenDef.key, {r, g, b, currentValue[4]})
                        if ok then
                            swatchTex:SetColorTexture(r, g, b, currentValue[4])
                        else
                            print("|cffff0000SuuUI:|r " .. tostring(err))
                        end
                    end
                end,
            }, tokenRow)
            hexInput:GetFrame():SetPoint("RIGHT", swatchBtn, "LEFT", -4, 0)
            
            -- Color picker modal
            local colorPickerPanel
            
            -- Click swatch to open color picker
            swatchBtn:SetScript("OnClick", function()
                print("Swatch clicked for " .. tokenDef.key)  -- Debug
                local active = SuuUI.Theme:GetActive()
                if SuuUI.Theme:IsBuiltin(active) then 
                    print("Cannot edit built-in theme")
                    return 
                end
                
                if not colorPickerPanel then
                    print("Creating color picker panel")  -- Debug
                    colorPickerPanel = C.ColorPicker({
                        value = currentValue,
                        onChange = function(r, g, b, a)
                            print("Color changed:", r, g, b, a)  -- Debug
                            -- Update the theme token
                            local ok, err = pcall(SuuUI.Theme.SetUserToken, SuuUI.Theme, active, tokenDef.key, {r, g, b, a})
                            if ok then
                                swatchTex:SetColorTexture(r, g, b, a)
                                hexInput:SetValue(string.format("%02X%02X%02X", r*255, g*255, b*255))
                                currentValue = {r, g, b, a}
                            else
                                print("|cffff0000SuuUI:|r " .. tostring(err))
                            end
                        end,
                    }, UIParent)
                    -- Set high strata so it appears above the settings window
                    colorPickerPanel:GetFrame():SetFrameStrata("FULLSCREEN_DIALOG")
                    colorPickerPanel:GetFrame():SetFrameLevel(100)
                    colorPickerPanel:Hide()
                    
                    -- Close picker when clicking outside
                    colorPickerPanel:OnRequestClose(function()
                        colorPickerPanel:Hide()
                    end)
                end
                
                -- Toggle visibility
                if colorPickerPanel:IsShown() then
                    print("Hiding color picker")
                    colorPickerPanel:Hide()
                else
                    print("Showing color picker")
                    local cv = T:GetToken(tokenDef.key)
                    colorPickerPanel:SetValue(cv[1], cv[2], cv[3], cv[4])
                    
                    -- Position at mouse cursor
                    local cx, cy = GetCursorPosition()
                    local scale = UIParent:GetEffectiveScale()
                    cx = cx / scale
                    cy = cy / scale
                    
                    colorPickerPanel:GetFrame():ClearAllPoints()
                    colorPickerPanel:GetFrame():SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", cx, cy)
                    
                    colorPickerPanel:Show()
                end
            end)
            
            swatchBtn:SetScript("OnEnter", function()
                swatchBtn:SetAlpha(0.8)
            end)
            swatchBtn:SetScript("OnLeave", function()
                swatchBtn:SetAlpha(1.0)
            end)
            
            tokenRow:SetHeight(28)
            
            tokenInputs[tokenDef.key] = {
                control = hexInput,
                swatch = swatchTex,
                updateValue = function()
                    local val = T:GetToken(tokenDef.key)
                    swatchTex:SetColorTexture(val[1], val[2], val[3], val[4])
                    hexInput:SetValue(string.format("%02X%02X%02X", val[1]*255, val[2]*255, val[3]*255))
                end
            }
            
        elseif tokenDef.type == "number" then
            -- Use Slider for numeric tokens
            local currentValue = T:GetToken(tokenDef.key)
            control = C.Slider({
                value = currentValue,
                min = tokenDef.min,
                max = tokenDef.max,
                step = tokenDef.step,
                w = 200,
                onChange = function(val)
                    local active = SuuUI.Theme:GetActive()
                    if SuuUI.Theme:IsBuiltin(active) then return end
                    
                    local ok, err = pcall(SuuUI.Theme.SetUserToken, SuuUI.Theme, active, tokenDef.key, val)
                    if not ok then
                        print("|cffff0000SuuUI:|r " .. tostring(err))
                    end
                end,
            }, tokenRow)
            control:GetFrame():SetPoint("RIGHT", tokenRow, "RIGHT", 0, 0)
            tokenRow:SetHeight(44)
            
            tokenInputs[tokenDef.key] = {
                control = control,
                updateValue = function()
                    local val = T:GetToken(tokenDef.key)
                    control:SetValue(val)
                end
            }
        end
        
        tokenRowsContainer:Add(tokenRow, { width = "fill", height = tokenRow:GetHeight() })
    end
    
    -- Calculate tokenEditorFrame height based on token rows
    local _, tokenRowsHeight = tokenRowsContainer:GetContentSize()
    tokenEditorFrame:SetSize(f:GetWidth(), tokenRowsHeight)
    
    rootContainer:Add(tokenEditorFrame, { width = "fill", height = tokenRowsHeight })

    -- Set initial height including all elements
    local _, totalHeight = rootContainer:GetContentSize()
    f:SetHeight(totalHeight)

    -- Initialize input enabled state based on current theme
    updateInputsEnabled()

    -- Listen for theme changes to update UI and control values
    SuuUI.Events:On("SUUUI_THEME_CHANGED", function(name)
        currentName:SetText(name)
        themeDD:SetValue(name)
        themeDD:SetOptions(updateDropdown())
        updateInputsEnabled()
        
        -- Update all control values when theme changes
        for key, data in pairs(tokenInputs) do
            data.updateValue()
        end
    end, "theme_mgr_ui")

    return f
end

if not SuuUI._SettingsControls then SuuUI._SettingsControls = {} end
SuuUI._SettingsControls["theme_manager"] = Build
