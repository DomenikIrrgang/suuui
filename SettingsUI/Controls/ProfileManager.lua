local tinsert, ipairs = table.insert, ipairs
local C = SuuUI.Components

--- Builds a profile manager control with list, buttons, and actions.
-- @param entry table    Schema entry (no specific props needed)
-- @param parent frame
-- @return frame         Raw frame with container-based layout
local function Build(entry, parent)
    local T = SuuUI.Theme
    local f = CreateFrame("Frame", nil, parent)
    f:SetSize(parent:GetWidth(), 180)

    local gap = T:GetToken("spaceMd") or 8

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

    -- Current profile display row with frames for proper sizing
    local currentRow = CreateFrame("Frame", nil, f)
    currentRow:SetSize(f:GetWidth(), 24)
    currentRow:Show()
    
    local currentLbl = C.Text({ text="Current Profile:", size="sm", color="muted" }, currentRow)
    currentLbl:GetFrame():SetPoint("LEFT", currentRow, "LEFT", 0, 0)
    currentLbl:Show()
    
    local currentName = C.Text({ 
        text=SuuUI.Profiles:GetActiveName(), 
        size="md", 
        color="accent" 
    }, currentRow)
    currentName:GetFrame():SetPoint("LEFT", currentLbl:GetFrame(), "RIGHT", 8, 0)
    currentName:Show()
    
    rootContainer:Add(currentRow, { width = "fill", height = 24 })

    -- Profile dropdown
    local profileDD
    local function updateDropdown()
        local profiles = SuuUI.Profiles:List()
        local options = {}
        for _, name in ipairs(profiles) do
            tinsert(options, { value=name, label=name })
        end
        return options
    end

    profileDD = C.Dropdown({
        options  = updateDropdown(),
        value    = SuuUI.Profiles:GetActiveName(),
        w        = 200,
        onChange = function(val)
            SuuUI.Profiles:SetActive(val)
            SuuUI.Profiles:LinkCharacter(val)
            currentName:SetText(val)
        end,
    }, f)
    rootContainer:Add(profileDD:GetFrame(), { height = 32 })

    -- Button row with frames for proper sizing
    local btnRow = CreateFrame("Frame", nil, f)
    btnRow:SetSize(f:GetWidth(), 24)
    btnRow:Show()
    
    local btnW = 80

    local createBtn = C.Button({
        label = "Create",
        w = btnW, h = 24,
        onClick = function()
            local modal = C.Modal({
                title      = "Create Profile",
                message    = "Enter new profile name:",
                input      = true,
                confirmText = "Create",
                onConfirm  = function(name)
                    if name and name ~= "" then
                        local ok, err = pcall(SuuUI.Profiles.Create, SuuUI.Profiles, name)
                        if ok then
                            profileDD:SetOptions(updateDropdown())
                            profileDD:SetValue(name)
                            SuuUI.Profiles:SetActive(name)
                            SuuUI.Profiles:LinkCharacter(name)
                            currentName:SetText(name)
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

    local copyBtn = C.Button({
        label = "Copy",
        w = btnW, h = 24,
        onClick = function()
            local modal = C.Modal({
                title      = "Copy Profile",
                message    = "Copy '" .. SuuUI.Profiles:GetActiveName() .. "' to:",
                input      = true,
                confirmText = "Copy",
                onConfirm  = function(name)
                    if name and name ~= "" then
                        local ok, err = pcall(function()
                            SuuUI.Profiles:Create(name)
                            SuuUI.Profiles:CopyTo(name)
                        end)
                        if ok then
                            profileDD:SetOptions(updateDropdown())
                            profileDD:SetValue(name)
                            SuuUI.Profiles:SetActive(name)
                            SuuUI.Profiles:LinkCharacter(name)
                            currentName:SetText(name)
                        else
                            print("|cffff0000SuuUI:|r " .. tostring(err))
                        end
                    end
                end,
            })
            modal:Show()
        end,
    }, btnRow)
    copyBtn:GetFrame():SetPoint("LEFT", createBtn:GetFrame(), "RIGHT", 8, 0)

    local deleteBtn = C.Button({
        label = "Delete",
        w = btnW, h = 24,
        onClick = function()
            local active = SuuUI.Profiles:GetActiveName()
            if active == "Default" then
                print("|cffff0000SuuUI:|r Cannot delete Default profile")
                return
            end
            local modal = C.Modal({
                title      = "Delete Profile",
                message    = "Delete '" .. active .. "'? This cannot be undone.",
                confirmText = "Delete",
                onConfirm  = function()
                    local ok, err = pcall(SuuUI.Profiles.Delete, SuuUI.Profiles, active)
                    if ok then
                        profileDD:SetOptions(updateDropdown())
                        profileDD:SetValue(SuuUI.Profiles:GetActiveName())
                        currentName:SetText(SuuUI.Profiles:GetActiveName())
                    else
                        print("|cffff0000SuuUI:|r " .. tostring(err))
                    end
                end,
            })
            modal:Show()
        end,
    }, btnRow)
    deleteBtn:GetFrame():SetPoint("LEFT", copyBtn:GetFrame(), "RIGHT", 8, 0)
    
    rootContainer:Add(btnRow, { width = "fill", height = 24 })

    -- Reset button
    local resetAllBtn = C.Button({
        label = "Reset All Settings",
        w = 160, h = 24,
        onClick = function()
            local modal = C.Modal({
                title      = "Reset Settings",
                message    = "Reset all settings to defaults?",
                confirmText = "Reset",
                onConfirm  = function()
                    local plugins = SuuUI.Plugins:GetAll()
                    for _, plugin in ipairs(plugins) do
                        SuuUI.Settings:ResetAll(plugin.id)
                    end
                    print("|cff00ff00SuuUI:|r Profile settings reset to defaults")
                end,
            })
            modal:Show()
        end,
    }, f)
    rootContainer:Add(resetAllBtn:GetFrame(), { height = 24 })

    -- Listen for profile changes to update UI
    SuuUI.Events:On("SUUUI_PROFILE_LOADED", function(name)
        currentName:SetText(name)
        profileDD:SetValue(name)
        profileDD:SetOptions(updateDropdown())
    end, "profile_mgr_ui")

    return f
end

if not SuuUI._SettingsControls then SuuUI._SettingsControls = {} end
SuuUI._SettingsControls["profile_manager"] = Build
