local tinsert, ipairs, pairs, pcall = table.insert, ipairs, pairs, pcall
local C = SuuUI.Components
local S = SuuUI.UISignals

local function themeOptions()
    local options = {}
    for _, name in ipairs(SuuUI.Theme:List()) do
        tinsert(options, { value = name, label = name })
    end
    return options
end

local function report(ok, err)
    if not ok then print("|cffff0000SuuUI:|r " .. tostring(err)) end
    return ok
end

local function setToken(key, value)
    local active = SuuUI.Theme:GetActive()
    if SuuUI.Theme:IsBuiltin(active) then return false end
    return report(pcall(SuuUI.Theme.SetUserToken, SuuUI.Theme, active, key, value))
end

-- Builds one colour token row: label, hex input, swatch
local function colourRow(parent, def, editors)
    local T = SuuUI.Theme
    local row, _ = SuuUI._SettingsRow.Labelled(parent, def.label, 28)
    local value  = T:GetToken(def.key) or {1, 1, 1, 1}

    local swatch = C.ColorSwatch({ value = value, w = 24 }, row:GetFrame())
    local hex    = C.Input({ value = "", w = 80, h = 22 }, row:GetFrame())
    hex:SetValue(swatch:GetHex())

    row:Add(hex,    { width = 80, height = 22 })
    row:Add(swatch, { width = 24, height = 24 })

    local function applyColor(r, g, b, a)
        if setToken(def.key, { r, g, b, a }) then
            swatch:SetValue(r, g, b, a)
            hex:SetValue(swatch:GetHex())
        end
    end

    S:Connect(swatch, S.SIGNALS.CLICKED, function()
        SuuUI._ColorPopup.Open(swatch, { swatch:GetValue() }, applyColor)
    end)

    S:Connect(hex, C.INPUT_SIGNALS.SUBMITTED, function(text)
        local digits = text:match("^#?(%x%x%x%x%x%x)$")
        if not digits then
            hex:SetValue(swatch:GetHex())
            return
        end
        local _, _, _, a = swatch:GetValue()
        applyColor(
            tonumber(digits:sub(1,2), 16) / 255,
            tonumber(digits:sub(3,4), 16) / 255,
            tonumber(digits:sub(5,6), 16) / 255, a)
    end)

    editors[def.key] = {
        control = hex,
        refresh = function()
            local v = T:GetToken(def.key) or {1, 1, 1, 1}
            swatch:SetValue(v[1], v[2], v[3], v[4])
            hex:SetValue(swatch:GetHex())
        end,
    }
    return row
end

-- Builds one numeric token row: slider with inline label
local function numberRow(parent, def, editors)
    local T   = SuuUI.Theme
    local row = SuuUI._SettingsRow.Stacked(parent, 44)

    local sld = C.Slider({
        label = def.label,
        value = T:GetToken(def.key) or def.min,
        min   = def.min, max = def.max, step = def.step,
    }, row:GetFrame())
    row:Add(sld, { width = "fill", height = 36 })

    S:Connect(sld, S.SIGNALS.VALUE_CHANGED, function(val)
        setToken(def.key, val)
    end)

    editors[def.key] = {
        control = sld,
        refresh = function() sld:SetValue(T:GetToken(def.key) or def.min) end,
    }
    return row
end

--- Builds the theme manager page section.
-- @param entry table    Schema entry (no specific props needed)
-- @param parent frame
-- @return table  Root container handle
local function Build(entry, parent)
    local T   = SuuUI.Theme
    local gap = T:GetToken("spaceMd") or 8
    local pad = T:GetToken("spaceMd") or 8
    local editors = {}

    local root = SuuUI.Layout:CreateContainer({
        parent  = parent,
        layout  = "flow",
        dir     = "vertical",
        gap     = gap,
        padding = { top = 0, right = pad, bottom = 0, left = pad },
    })

    -- Active theme row
    local currentRow = SuuUI.Layout:CreateContainer({
        parent = root:GetFrame(),
        layout = "flow", dir = "horizontal", gap = gap, align = "center", h = 24,
    })
    local currentLbl  = C.Text({ text="Active Theme:", size="sm", color="muted" }, currentRow:GetFrame())
    local currentName = C.Text({ text=T:GetActive(), size="md", color="accent" }, currentRow:GetFrame())
    currentRow:Add(currentLbl,  { width = 100 })
    currentRow:Add(currentName, { width = "fill" })
    root:Add(currentRow, { width = "fill", height = 24 })

    local themeDD = C.Dropdown({
        options = themeOptions(), value = T:GetActive(), w = 200,
    }, root:GetFrame())
    root:Add(themeDD, { width = 200, height = 24 })

    local function syncEditable()
        local builtin = SuuUI.Theme:IsBuiltin(SuuUI.Theme:GetActive())
        for _, editor in pairs(editors) do
            editor.control:SetEnabled(not builtin)
        end
    end

    local function refreshAll()
        for _, editor in pairs(editors) do editor.refresh() end
    end

    S:Connect(themeDD, S.SIGNALS.VALUE_CHANGED, function(val)
        SuuUI.Theme:SetActive(val)
    end)

    -- Action buttons
    local btnRow = SuuUI.Layout:CreateContainer({
        parent = root:GetFrame(),
        layout = "flow", dir = "horizontal", gap = gap, h = 24,
    })
    local createBtn = C.Button({ label="Create", w=80, h=24 }, btnRow:GetFrame())
    local deleteBtn = C.Button({ label="Delete", w=80, h=24 }, btnRow:GetFrame())
    local resetBtn  = C.Button({ label="Reset",  w=80, h=24 }, btnRow:GetFrame())
    btnRow:Add(createBtn, { width = 80, height = 24 })
    btnRow:Add(deleteBtn, { width = 80, height = 24 })
    btnRow:Add(resetBtn,  { width = 80, height = 24 })
    root:Add(btnRow, { width = "fill", height = 24 })

    S:Connect(createBtn, S.SIGNALS.CLICKED, function()
        C.Modal({
            title="Create Theme", message="Enter new theme name:",
            input=true, confirmText="Create",
            onConfirm = function(name)
                if not name or name == "" then return end
                if report(pcall(SuuUI.Theme.CreateUserTheme, SuuUI.Theme, name, "Modern")) then
                    themeDD:SetOptions(themeOptions())
                    themeDD:SetValue(name)
                    SuuUI.Theme:SetActive(name)
                end
            end,
        }):Show()
    end)

    S:Connect(deleteBtn, S.SIGNALS.CLICKED, function()
        local active = SuuUI.Theme:GetActive()
        if SuuUI.Theme:IsBuiltin(active) then
            print("|cffff0000SuuUI:|r Cannot delete built-in theme")
            return
        end
        C.Modal({
            title="Delete Theme",
            message="Delete '" .. active .. "'? This cannot be undone.",
            confirmText="Delete",
            onConfirm = function()
                if report(pcall(SuuUI.Theme.DeleteUserTheme, SuuUI.Theme, active)) then
                    themeDD:SetOptions(themeOptions())
                    themeDD:SetValue(SuuUI.Theme:GetActive())
                end
            end,
        }):Show()
    end)

    S:Connect(resetBtn, S.SIGNALS.CLICKED, function()
        local active = SuuUI.Theme:GetActive()
        if SuuUI.Theme:IsBuiltin(active) then
            print("|cffff0000SuuUI:|r Cannot reset built-in theme")
            return
        end
        C.Modal({
            title="Reset Theme",
            message="Reset '" .. active .. "' to its base theme values?",
            confirmText="Reset",
            onConfirm = function()
                if report(pcall(SuuUI.Theme.ResetUserTheme, SuuUI.Theme, active)) then
                    refreshAll()
                    print("|cff00ff00SuuUI:|r Theme reset to defaults")
                end
            end,
        }):Show()
    end)

    local info = C.Text({
        text  = "Built-in themes (Default, Modern) cannot be edited.\nCreate a new theme to customise tokens.",
        size  = "sm", color = "muted", wrap = true,
    }, root:GetFrame())
    root:Add(info, { width = "fill", height = 32 })

    -- Token editors
    for _, def in ipairs(SuuUI._ThemeEditableTokens) do
        local row
        if def.type == "color" then
            row = colourRow(root:GetFrame(), def, editors)
        else
            row = numberRow(root:GetFrame(), def, editors)
        end
        root:Add(row, { width = "fill", height = row:GetHeight() })
    end

    syncEditable()

    SuuUI.Events:On("SUUUI_THEME_CHANGED", function(name)
        currentName:SetText(name)
        themeDD:SetOptions(themeOptions())
        themeDD:SetValue(name)
        syncEditable()
        refreshAll()
    end, "theme_mgr_ui")

    return root
end

if not SuuUI._SettingsControls then SuuUI._SettingsControls = {} end
SuuUI._SettingsControls["theme_manager"] = Build
