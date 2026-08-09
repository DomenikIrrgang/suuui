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

-- A blocked but expected action: the user asked for something the rules disallow.
local function warn(message)
    C.Notice({ title = "Not Allowed", message = message, tone = "warning" })
end

-- Something actually failed. Surfaced in danger colours so it reads differently to warn.
local function report(ok, err)
    if not ok then
        C.Notice({ title = "Error", message = tostring(err), tone = "danger" })
    end
    return ok
end

-- Completed actions confirm in chat rather than blocking on a dialog
local function say(message)
    print(SuuUI.Theme:GetColorCode("colorSuccess") .. "SuuUI:|r " .. message)
end

local function setToken(key, value)
    local active = SuuUI.Theme:GetActive()
    if SuuUI.Theme:IsBuiltin(active) then return false end
    return report(pcall(SuuUI.Theme.SetUserToken, SuuUI.Theme, active, key, value))
end

-- Builds one colour token row: label, hex input, swatch
local function colourRow(parent, def, editors)
    local T = SuuUI.Theme
    local row, _ = SuuUI._SettingsRow.Labelled(parent, def.label)
    local value  = T:GetToken(def.key) or {1, 1, 1, 1}

    local swatch = C.ColorSwatch({ value = value }, row:GetFrame())
    local hex    = C.Input({ value = "", w = 80 }, row:GetFrame())
    hex:SetValue(swatch:GetHex())

    -- Heights omitted: both controls derive them from the size tokens they are editing
    row:Add(hex, { width = 80 })
    row:Add(swatch)

    local function applyColor(r, g, b, a)
        if setToken(def.key, { r, g, b, a }) then
            swatch:SetValue(r, g, b, a)
            hex:SetValue(swatch:GetHex())
        end
    end

    S:Connect(swatch, S.SIGNALS.CLICKED, function()
        SuuUI._ColorPopup.Open(swatch, { swatch:GetValue() }, applyColor)
    end)

    -- The shared picker anchors to this swatch and holds applyColor. Rebuilding the theme
    -- page while it is open would leave it writing tokens through a destroyed row.
    local rowDestroy = row.Destroy
    row.Destroy = function(selfRow)
        SuuUI._ColorPopup.CloseFor(swatch)
        rowDestroy(selfRow)
    end

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
        controls = { hex },
        refresh = function()
            local v = T:GetToken(def.key) or {1, 1, 1, 1}
            swatch:SetValue(v[1], v[2], v[3], v[4])
            hex:SetValue(swatch:GetHex())
        end,
    }
    return row
end

-- Builds one boolean token row: label left, switch right.
--
-- The only non-visual token form in the editor. "Colour this by class" is a mode rather
-- than a value, so it gets a switch instead of a swatch — and modelling it as a boolean is
-- what keeps every colour token in this list a real colour.
local function toggleRow(parent, def, editors)
    local T   = SuuUI.Theme
    local row = SuuUI._SettingsRow.Labelled(parent, def.label)

    local tog = C.Toggle({ value = T:GetToken(def.key) == true }, row:GetFrame())
    row:Add(tog)

    S:Connect(tog, S.SIGNALS.VALUE_CHANGED, function(val)
        setToken(def.key, val == true)
    end)

    editors[def.key] = {
        controls = { tog },
        -- SetValue is silent by contract, so writing the stored value back here cannot
        -- loop into the VALUE_CHANGED handler above.
        refresh = function() tog:SetValue(T:GetToken(def.key) == true) end,
    }
    return row
end

-- Builds one numeric token row: slider with inline label
local function numberRow(parent, def, editors)
    local T   = SuuUI.Theme
    local row = SuuUI._SettingsRow.Stacked(parent)

    local sld = C.Slider({
        label = def.label,
        value = T:GetToken(def.key) or def.min,
        min   = def.min, max = def.max, step = def.step,
    }, row:GetFrame())
    row:Add(sld, { width = "fill" })

    S:Connect(sld, S.SIGNALS.VALUE_CHANGED, function(val)
        setToken(def.key, val)
    end)

    editors[def.key] = {
        controls = { sld },
        refresh = function() sld:SetValue(T:GetToken(def.key) or def.min) end,
    }
    return row
end

-- Each option renders in the face it names, so the list is a preview rather than a set
-- of labels the user has to try one at a time.
local function fontOptions()
    local options = SuuUI.Fonts:Options()
    for _, opt in ipairs(options) do
        opt.font = SuuUI.Fonts:Path(opt.value)
    end
    return options
end

-- Builds the font token row: a dropdown of every face the client and any media addon
-- expose, plus an entry for a path nothing registered. The token stores the name, so the
-- display value is the name too — resolved from the raw token, falling back to a reverse
-- lookup for a theme that stores a path.
local function fontRow(parent, def, editors)
    local T = SuuUI.Theme
    local row = SuuUI._SettingsRow.Labelled(parent, def.label)

    local function currentName()
        return SuuUI.Fonts:Name(T:GetTokenRaw(def.key))
            or SuuUI.Fonts:Name(T:GetToken(def.key))
    end

    local dd = C.Dropdown({
        options = fontOptions(), value = currentName(), w = 200,
    }, row:GetFrame())
    local addBtn = C.Button({ label = "Add" }, row:GetFrame())
    row:Add(dd, { width = 200 })
    row:Add(addBtn)

    local function repopulate()
        dd:SetOptions(fontOptions())
        dd:SetValue(currentName())
    end

    S:Connect(dd, S.SIGNALS.VALUE_CHANGED, function(name)
        setToken(def.key, name)
    end)

    -- A font dropped into an addon folder that no media addon registered is invisible to
    -- every discovery source, since WoW exposes no way to list files. Taking the path
    -- directly is the only route to it.
    S:Connect(addBtn, S.SIGNALS.CLICKED, function()
        C.Modal({
            title   = "Add Font",
            message = "Font file path, for example:\n"
                   .. "Interface/AddOns/MyMedia/fonts/mine.ttf",
            input = true, confirmText = "Add", confirmVariant = "success",
            onConfirm = function(path)
                path = (path or ""):gsub("^%s+", ""):gsub("%s+$", "")
                if path == "" then return end

                local name = SuuUI.Fonts:Add(path)
                if not name then
                    C.Notice({
                        title   = "Font Not Loaded",
                        message = "The client could not load:\n" .. path
                               .. "\n\nCheck the path, and that the file is a TTF or OTF "
                               .. "inside your WoW folder.",
                        tone = "warning",
                    })
                    return
                end
                repopulate()
                if setToken(def.key, name) then dd:SetValue(name) end
            end,
        }):Show()
    end)

    editors[def.key] = { controls = { dd, addBtn }, refresh = repopulate }
    return row
end

--- Builds the theme manager page section.
-- @param entry table    Schema entry (no specific props needed)
-- @param parent frame
-- @return table  Root container handle
local function Build(entry, parent)
    local T   = SuuUI.Theme
    local gap = T:GetToken("spaceSm") or 8
    local pad = T:GetToken("spaceSm") or 8
    local editors = {}

    local root = SuuUI.Layout:CreateContainer({
        parent  = parent,
        layout  = "flow",
        dir     = "vertical",
        gap     = gap,
        padding = { top = 0, right = pad, bottom = 0, left = pad },
    })

    -- Active theme row
    local rowH = T:GetControlHeight("sizeControlLg")
    local currentRow = SuuUI.Layout:CreateContainer({
        parent = root:GetFrame(),
        layout = "flow", dir = "horizontal", gap = gap, align = "center", h = rowH,
    })
    local currentLbl  = C.Text({ text="Active Theme:", size="sm", color="muted" }, currentRow:GetFrame())
    local currentName = C.Text({ text=T:GetActive(), size="md", color="accent" }, currentRow:GetFrame())
    currentRow:Add(currentLbl,  { width = 100 })
    currentRow:Add(currentName, { width = "fill" })
    root:Add(currentRow, { width = "fill", height = rowH })

    local themeDD = C.Dropdown({
        options = themeOptions(), value = T:GetActive(), w = 200,
    }, root:GetFrame())
    root:Add(themeDD, { width = 200 })

    -- Built-in themes are read-only, so every control that writes a token goes dead
    -- rather than silently discarding the edit.
    local function syncEditable()
        local builtin = SuuUI.Theme:IsBuiltin(SuuUI.Theme:GetActive())
        for _, editor in pairs(editors) do
            for _, control in ipairs(editor.controls) do
                control:SetEnabled(not builtin)
            end
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
        layout = "flow", dir = "horizontal", gap = gap, align = "center",
    })
    -- Buttons size themselves to their labels; the row hugs them
    -- These buttons only open a dialog; the intent colour belongs on the confirm button
    -- inside it, where the action is actually committed.
    local createBtn = C.Button({ label="Create", minW = 80 }, btnRow:GetFrame())
    local deleteBtn = C.Button({ label="Delete", minW = 80 }, btnRow:GetFrame())
    local resetBtn  = C.Button({ label="Reset",  minW = 80 }, btnRow:GetFrame())
    btnRow:Add(createBtn)
    btnRow:Add(deleteBtn)
    btnRow:Add(resetBtn)
    root:Add(btnRow, { width = "fill" })

    S:Connect(createBtn, S.SIGNALS.CLICKED, function()
        C.Modal({
            title="Create Theme", message="Enter new theme name:",
            input=true, confirmText="Create", confirmVariant="success",
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
            warn("Built-in themes cannot be deleted. Create your own theme to customise it.")
            return
        end
        C.Modal({
            title="Delete Theme",
            message="Delete '" .. active .. "'? This cannot be undone.",
            confirmText="Delete", confirmVariant="danger",
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
            warn("Built-in themes have no overrides to reset.")
            return
        end
        C.Modal({
            title="Reset Theme",
            message="Reset '" .. active .. "' to its base theme values?",
            confirmText="Reset", confirmVariant="danger",
            onConfirm = function()
                if report(pcall(SuuUI.Theme.ResetUserTheme, SuuUI.Theme, active)) then
                    refreshAll()
                    say("Theme reset to defaults")
                end
            end,
        }):Show()
    end)

    local info = C.Text({
        text  = "Built-in themes (Default, Modern) cannot be edited.\nCreate a new theme to customise tokens.",
        size  = "sm", color = "muted", wrap = true,
    }, root:GetFrame())
    root:Add(info, { width = "fill" })

    -- Token editors hug their content: font size tokens change their height at runtime
    for _, def in ipairs(SuuUI._ThemeEditableTokens) do
        local row
        if def.type == "color" then
            row = colourRow(root:GetFrame(), def, editors)
        elseif def.type == "font" then
            row = fontRow(root:GetFrame(), def, editors)
        elseif def.type == "toggle" then
            row = toggleRow(root:GetFrame(), def, editors)
        else
            row = numberRow(root:GetFrame(), def, editors)
        end
        root:Add(row, { width = "fill" })
    end

    syncEditable()

    -- One owner for every listener this page registers. Dropped first, so rebuilding the
    -- page on a nav switch replaces its subscribers instead of stacking another set on top
    -- of widgets that are about to be destroyed.
    local OWNER = "theme_mgr_ui"
    SuuUI.Events:OffAll(OWNER)

    SuuUI.Events:On("SUUUI_THEME_CHANGED", function(name)
        currentName:SetText(name)
        themeDD:SetOptions(themeOptions())
        themeDD:SetValue(name)
        syncEditable()
        refreshAll()
    end, OWNER)

    -- A media addon can register fonts after this page was built, so the font row has
    -- to repopulate rather than keep the option list it opened with.
    SuuUI.Events:On("SUUUI_FONTS_CHANGED", refreshAll, OWNER)

    -- Teardown symmetry: the page owns this container, so destroying the page has to drop
    -- the bus listeners too. A Settings watcher is cleaned up by owner prefix; an event
    -- listener has no such sweep, so it is released here or not at all.
    local containerDestroy = root.Destroy
    root.Destroy = function(selfRoot)
        SuuUI.Events:OffAll(OWNER)
        containerDestroy(selfRoot)
    end

    return root
end

if not SuuUI._SettingsControls then SuuUI._SettingsControls = {} end
SuuUI._SettingsControls["theme_manager"] = Build
