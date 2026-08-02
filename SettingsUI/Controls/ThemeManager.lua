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
    
    -- Function to update input enabled state based on theme
    local function updateInputsEnabled()
        local active = SuuUI.Theme:GetActive()
        local isBuiltin = SuuUI.Theme:IsBuiltin(active)
        
        for _, data in pairs(tokenInputs) do
            data.input:SetEnabled(not isBuiltin)
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

    -- Create token editor rows
    local editableTokens = {
        -- Colors
        {key="colorBg", label="Background"},
        {key="colorBgAlt", label="Background Alt"},
        {key="colorBgHover", label="Background Hover"},
        {key="colorBgActive", label="Background Active"},
        {key="colorBlue400", label="Blue 400"},
        {key="colorBlue500", label="Blue 500"},
        {key="colorGreen400", label="Green 400"},
        {key="colorRed400", label="Red 400"},
        {key="colorYellow400", label="Yellow 400"},
        {key="colorText", label="Text"},
        {key="colorTextMuted", label="Text Muted"},
        {key="colorTextDisable", label="Text Disabled"},
        {key="colorBorder", label="Border"},
        -- Fonts
        {key="fontSizeSm", label="Font Size Small"},
        {key="fontSizeMd", label="Font Size Medium"},
        {key="fontSizeLg", label="Font Size Large"},
        {key="fontSizeXl", label="Font Size XL"},
        -- Spacing
        {key="spaceSm", label="Space Small"},
        {key="spaceMd", label="Space Medium"},
        {key="spaceLg", label="Space Large"},
        {key="spaceXl", label="Space XL"},
        -- Other
        {key="borderWidth", label="Border Width"},
        {key="borderRadius", label="Border Radius"},
        {key="animFast", label="Animation Fast"},
        {key="animMid", label="Animation Mid"},
        {key="animSlow", label="Animation Slow"},
    }
    
    for _, tokenDef in ipairs(editableTokens) do
        local tokenRow = CreateFrame("Frame", nil, tokenEditorFrame)
        tokenRow:SetHeight(28)
        
        -- Label on the left, vertically centered
        local label = C.Text({
            text  = tokenDef.label,
            size  = "sm",
            color = "text",
        }, tokenRow)
        label:GetFrame():SetPoint("LEFT", tokenRow, "LEFT", 0, 0)
        label:GetFrame():SetWidth(150)
        
        local function updateInputValue()
            local currentValue = T:GetToken(tokenDef.key)
            local valueType = type(currentValue)
            local valueStr = ""
            
            if valueType == "table" then
                valueStr = string.format("%.2f, %.2f, %.2f, %.2f", 
                    currentValue[1] or 0, currentValue[2] or 0, 
                    currentValue[3] or 0, currentValue[4] or 1)
            else
                valueStr = tostring(currentValue)
            end
            
            return valueStr
        end
        
        local valueStr = updateInputValue()
        
        -- Input on the right, vertically centered
        local input = C.Input({
            value = valueStr,
            w     = 200,
            h     = 22,
            onEnter = function(text)
                local active = SuuUI.Theme:GetActive()
                if SuuUI.Theme:IsBuiltin(active) then return end
                
                -- Get current value type
                local currentValue = T:GetToken(tokenDef.key)
                local currentType = type(currentValue)
                
                -- Parse and set the token value
                local newValue
                if currentType == "table" then
                    -- Parse RGBA color string
                    local r, g, b, a = text:match("([%d%.]+),%s*([%d%.]+),%s*([%d%.]+),%s*([%d%.]+)")
                    if r and g and b and a then
                        newValue = {tonumber(r), tonumber(g), tonumber(b), tonumber(a)}
                    end
                elseif currentType == "number" then
                    newValue = tonumber(text)
                else
                    newValue = text
                end
                
                if newValue then
                    local ok, err = pcall(SuuUI.Theme.SetUserToken, SuuUI.Theme, active, tokenDef.key, newValue)
                    if not ok then
                        print("|cffff0000SuuUI:|r " .. tostring(err))
                    end
                end
            end,
        }, tokenRow)
        input:GetFrame():SetPoint("RIGHT", tokenRow, "RIGHT", 0, 0)
        
        tokenRowsContainer:Add(tokenRow, { width = "fill", height = 28 })
        
        tokenInputs[tokenDef.key] = {
            input = input,
            updateValue = updateInputValue
        }
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

    -- Listen for theme changes to update UI and input values
    SuuUI.Events:On("SUUUI_THEME_CHANGED", function(name)
        currentName:SetText(name)
        themeDD:SetValue(name)
        themeDD:SetOptions(updateDropdown())
        updateInputsEnabled()
        
        -- Update all input values when theme changes
        for key, data in pairs(tokenInputs) do
            local valueStr = data.updateValue()
            data.input:SetValue(valueStr)
        end
    end, "theme_mgr_ui")

    return f
end

if not SuuUI._SettingsControls then SuuUI._SettingsControls = {} end
SuuUI._SettingsControls["theme_manager"] = Build
