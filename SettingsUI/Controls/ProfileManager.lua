local tinsert, ipairs, pcall = table.insert, ipairs, pcall
local C = SuuUI.Components
local S = SuuUI.UISignals

local function profileOptions()
    local options = {}
    for _, name in ipairs(SuuUI.Profiles:List()) do
        tinsert(options, { value = name, label = name })
    end
    return options
end

local function report(ok, err)
    if not ok then print("|cffff0000SuuUI:|r " .. tostring(err)) end
    return ok
end

--- Builds the profile manager page section.
-- @param entry table    Schema entry (no specific props needed)
-- @param parent frame
-- @return table  Root container handle
local function Build(entry, parent)
    local T   = SuuUI.Theme
    local gap = T:GetToken("spaceMd") or 8
    local pad = T:GetToken("spaceMd") or 8

    local root = SuuUI.Layout:CreateContainer({
        parent  = parent,
        layout  = "flow",
        dir     = "vertical",
        gap     = gap,
        padding = { top = 0, right = pad, bottom = 0, left = pad },
    })

    -- Current profile row
    local currentRow = SuuUI.Layout:CreateContainer({
        parent = root:GetFrame(),
        layout = "flow",
        dir    = "horizontal",
        gap    = gap,
        align  = "center",
        h      = 24,
    })
    local currentLbl = C.Text({ text = "Current Profile:", size = "sm", color = "muted" },
        currentRow:GetFrame())
    local currentName = C.Text({ text = SuuUI.Profiles:GetActiveName(), size = "md", color = "accent" },
        currentRow:GetFrame())
    currentRow:Add(currentLbl, { width = 100 })
    currentRow:Add(currentName, { width = "fill" })
    root:Add(currentRow, { width = "fill", height = 24 })

    -- Profile selector
    local profileDD = C.Dropdown({
        options = profileOptions(),
        value   = SuuUI.Profiles:GetActiveName(),
        w       = 200,
    }, root:GetFrame())
    root:Add(profileDD, { width = 200, height = 24 })

    local function switchTo(name)
        SuuUI.Profiles:SetActive(name)
        SuuUI.Profiles:LinkCharacter(name)
        currentName:SetText(name)
    end

    S:Connect(profileDD, S.SIGNALS.VALUE_CHANGED, function(val)
        switchTo(val)
    end)

    local function refreshOptions(selected)
        profileDD:SetOptions(profileOptions())
        profileDD:SetValue(selected or SuuUI.Profiles:GetActiveName())
    end

    -- Action buttons
    local btnRow = SuuUI.Layout:CreateContainer({
        parent = root:GetFrame(),
        layout = "flow",
        dir    = "horizontal",
        gap    = gap,
        align  = "center",
    })

    -- Buttons size themselves to their labels; the row hugs them
    local createBtn = C.Button({ label = "Create", minW = 80 }, btnRow:GetFrame())
    local copyBtn   = C.Button({ label = "Copy",   minW = 80 }, btnRow:GetFrame())
    local deleteBtn = C.Button({ label = "Delete", minW = 80 }, btnRow:GetFrame())
    btnRow:Add(createBtn)
    btnRow:Add(copyBtn)
    btnRow:Add(deleteBtn)
    root:Add(btnRow, { width = "fill" })

    S:Connect(createBtn, S.SIGNALS.CLICKED, function()
        C.Modal({
            title = "Create Profile", message = "Enter new profile name:",
            input = true, confirmText = "Create",
            onConfirm = function(name)
                if not name or name == "" then return end
                if report(pcall(SuuUI.Profiles.Create, SuuUI.Profiles, name)) then
                    refreshOptions(name)
                    switchTo(name)
                end
            end,
        }):Show()
    end)

    S:Connect(copyBtn, S.SIGNALS.CLICKED, function()
        C.Modal({
            title = "Copy Profile",
            message = "Copy '" .. SuuUI.Profiles:GetActiveName() .. "' to:",
            input = true, confirmText = "Copy",
            onConfirm = function(name)
                if not name or name == "" then return end
                local ok, err = pcall(function()
                    SuuUI.Profiles:Create(name)
                    SuuUI.Profiles:CopyTo(name)
                end)
                if report(ok, err) then
                    refreshOptions(name)
                    switchTo(name)
                end
            end,
        }):Show()
    end)

    S:Connect(deleteBtn, S.SIGNALS.CLICKED, function()
        local active = SuuUI.Profiles:GetActiveName()
        if active == "Default" then
            print("|cffff0000SuuUI:|r Cannot delete Default profile")
            return
        end
        C.Modal({
            title = "Delete Profile",
            message = "Delete '" .. active .. "'? This cannot be undone.",
            confirmText = "Delete",
            onConfirm = function()
                if report(pcall(SuuUI.Profiles.Delete, SuuUI.Profiles, active)) then
                    refreshOptions()
                    currentName:SetText(SuuUI.Profiles:GetActiveName())
                end
            end,
        }):Show()
    end)

    -- Reset everything
    local resetBtn = C.Button({ label = "Reset All Settings" }, root:GetFrame())
    root:Add(resetBtn)

    S:Connect(resetBtn, S.SIGNALS.CLICKED, function()
        C.Modal({
            title = "Reset Settings", message = "Reset all settings to defaults?",
            confirmText = "Reset",
            onConfirm = function()
                for _, plugin in ipairs(SuuUI.Plugins:GetAll()) do
                    SuuUI.Settings:ResetAll(plugin.id)
                end
                print("|cff00ff00SuuUI:|r Profile settings reset to defaults")
            end,
        }):Show()
    end)

    SuuUI.Events:On("SUUUI_PROFILE_LOADED", function(name)
        currentName:SetText(name)
        refreshOptions(name)
    end, "profile_mgr_ui")

    return root
end

if not SuuUI._SettingsControls then SuuUI._SettingsControls = {} end
SuuUI._SettingsControls["profile_manager"] = Build
