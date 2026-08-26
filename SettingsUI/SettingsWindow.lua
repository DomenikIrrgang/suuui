local ipairs, tinsert = ipairs, table.insert
local C = SuuUI.Components
local S = SuuUI.UISignals

-- Preferred size, not a guarantee: the window caps itself to the screen, so a small
-- display opens it smaller rather than off the bottom edge. Sized for a 1080p panel,
-- where the pixel grid gives 1920x1080 units.
local WIN_W, WIN_H = 1248, 832
local NAV_W, DIV_W = 180, 3

-- Nav rows hold text, so their height is floored against the font size token
local function navRowHeight()
    return SuuUI.Theme:GetControlHeight("sizeNavRow")
end

local win, navScroll, contentScroll, navList
local navScrollConn = nil
local navItems = {}
local activeId = nil

local function selectPlugin(id)
    if activeId == id then return end
    activeId = id

    for _, item in ipairs(navItems) do
        item.nav:SetSelected(item.id == id)
    end

    SuuUI._PageBuilder:Build(id, contentScroll)
    contentScroll:ScrollToTop()
    SuuUI.Anim.Presets.FadeIn(contentScroll:GetFrame(), SuuUI.Theme:GetToken("animFast"))
end

-- A page already on screen has no other way to learn that its schema has GROWN. The data bar's
-- page does exactly that: a widget contributed by another plugin may register at any moment and
-- splice its controls in, and without this the controls appear only on the player's next visit
-- to the page -- which reads as the setting having failed to register at all.
--
-- Guarded on the page being the one that changed, so an unrelated plugin extending its own
-- schema does not rebuild whatever the player is currently reading.
SuuUI.Events:On("SUUUI_SCHEMA_CHANGED", function(pluginId)
    if not (activeId and contentScroll) then return end
    if pluginId ~= activeId then return end
    SuuUI._PageBuilder:Build(activeId, contentScroll)
end, "settings_window.schema")

local function buildNav()
    local T   = SuuUI.Theme
    local gap = T:GetToken("spaceXs") or 4

    local previousId = activeId

    -- The scroll frame survives a nav rebuild, so its listener has to be released by hand.
    -- Left connected, every plugin enable/disable stacks another callback on it.
    if navScrollConn then
        S:Disconnect(navScroll, S.SIGNALS.SIZE_CHANGED, navScrollConn)
        navScrollConn = nil
    end
    if navList then navList:Destroy() end
    for _, item in ipairs(navItems) do item.nav:Destroy() end
    navItems = {}
    activeId = nil

    navList = SuuUI.Layout:CreateContainer({
        parent  = navScroll:GetContent(),
        layout  = "flow",
        dir     = "vertical",
        gap     = gap,
        w       = navScroll:GetContentWidth(),
        padding = { top = gap, right = gap, bottom = gap, left = gap },
    })

    S:Connect(navList, S.SIGNALS.SIZE_CHANGED, function(_, h)
        S:Emit(navScroll, S.SIGNALS.CONTENT_RESIZED, h)
    end)

    -- Keep the nav list width in step with the scroll frame (scrollbar appearing
    -- changes the usable content width)
    navScrollConn = S:Connect(navScroll, S.SIGNALS.SIZE_CHANGED, function()
        if navList then navList:SetWidth(navScroll:GetContentWidth()) end
    end)

    local entries = SuuUI.Plugins:GetAll()
    tinsert(entries, 1, { id = "_profiles", name = "Profiles" })
    tinsert(entries, 1, { id = "_layout",   name = "Layout" })
    tinsert(entries, 1, { id = "_theme",    name = "Theme" })

    local rowH = navRowHeight()
    local restoredId = nil
    for _, entry in ipairs(entries) do
        local nav = C.NavItem({ label = entry.name, h = rowH }, navList:GetFrame())
        navList:Add(nav, { width = "fill", height = rowH })

        local pid = entry.id
        S:Connect(nav, S.SIGNALS.CLICKED, function() selectPlugin(pid) end)
        tinsert(navItems, { id = pid, nav = nav })
        if pid == previousId then restoredId = pid end
    end

    if restoredId then
        selectPlugin(restoredId)
    elseif #navItems > 0 then
        selectPlugin(navItems[1].id)
    end
end

local function registerCoreSchemas()
    if not SuuUI.Settings:GetSchema("_theme") then
        SuuUI.Settings:Register("_theme", {
            { key = "theme_mgr", type = "theme_manager" },
        })
    end
    if not SuuUI.Settings:GetSchema("_profiles") then
        SuuUI.Settings:Register("_profiles", {
            { key = "profile_mgr", type = "profile_manager" },
        })
    end
end

local function createWindow()
    win = SuuUI.Layout:CreateWindow({
        id        = "settings",
        title     = "SuuUI Settings",
        w         = WIN_W,
        h         = WIN_H,
        resizable = true,
        centered  = true,
        minW      = 600,
        minH      = 400,
    })

    local content = win:GetContentFrame()
    -- Read the real content box rather than WIN_W/WIN_H: the window caps itself to the
    -- screen, so the constants are only a request and can overshoot on a small display.
    local contentW, contentH = win:GetContentSize()

    -- Nav | divider | page, tracking the window as it resizes
    local main = SuuUI.Layout:CreateContainer({
        parent  = content,
        layout  = "flow",
        dir     = "horizontal",
        gap     = 0,
        fill    = true,
        padding = { top = 0, right = 0, bottom = 0, left = 0 },
    })

    local navPanel  = C.Frame({ variant = "bgAlt" }, main:GetFrame())
    local divider   = C.Divider({ dir = "vertical" }, main:GetFrame())
    local pagePanel = C.Frame({ variant = "transparent", border = false }, main:GetFrame())

    main:Add(navPanel,  { width = NAV_W, height = "fill" })
    main:Add(divider,   { width = DIV_W, height = "fill" })
    main:Add(pagePanel, { width = "fill", height = "fill" })

    -- Scroll areas fill their panels through nested fill containers
    local navBox = SuuUI.Layout:CreateContainer({
        parent = navPanel:GetFrame(),
        layout = "flow",
        dir    = "vertical",
        fill   = true,
    })
    navScroll = C.ScrollFrame({ w = NAV_W, h = contentH }, navPanel:GetFrame())
    navBox:Add(navScroll, { width = "fill", height = "fill" })

    local pageBox = SuuUI.Layout:CreateContainer({
        parent = pagePanel:GetFrame(),
        layout = "flow",
        dir    = "vertical",
        fill   = true,
    })
    contentScroll = C.ScrollFrame({ w = contentW - NAV_W - DIV_W, h = contentH },
                                  pagePanel:GetFrame())
    pageBox:Add(contentScroll, { width = "fill", height = "fill" })
end

--- The settings window's public entry points.
--
-- Exists because the window is built LAZILY -- the first open registers the core schemas,
-- creates the window and builds the nav -- and that sequence lived inside the slash
-- handler. Anything else wanting to open the window therefore had to call
-- `SlashCmdList["SUUUI"]()`, which is reaching into a global command table for behaviour
-- that has no other name. The minimap button is a separate plugin now, so it needs a seam
-- that is part of the addon's API; both callers go through this one, so the lazy build has
-- a single implementation.
SuuUI.SettingsWindow = {}

local function ensureWindow()
    if not win then
        registerCoreSchemas()
        createWindow()
        buildNav()
    end
    return win
end

--- Opens the window, building it on first use.
function SuuUI.SettingsWindow.Open()
    ensureWindow():Show()
end

--- Opens the window if closed, closes it if open.
function SuuUI.SettingsWindow.Toggle()
    ensureWindow():Toggle()
end

--- Whether the window exists and is currently shown.
function SuuUI.SettingsWindow.IsShown()
    return win ~= nil and win:IsShown()
end

SLASH_SUUUI1 = "/suuui"
SlashCmdList["SUUUI"] = function(msg)
    local cmd = (msg or ""):lower():match("^%s*(.-)%s*$")
    if cmd == "toggle" then
        SuuUI.ToggleUI:Toggle()
    elseif cmd == "lock" then
        SuuUI.ToggleUI:Disable()
    elseif cmd == "unlock" then
        SuuUI.ToggleUI:Enable()
    -- A CORE mode, so it belongs here beside the edit-mode verbs. A plugin's command would not:
    -- Plugins/Inventory/Inventory.lua gave /sbags its own handler precisely to keep plugin
    -- knowledge out of this one.
    elseif cmd == "keybind" or cmd == "kb" then
        if SuuUI.KeybindMode then
            -- Both the refusal and a normal close leave the mode inactive, so the WARNING has to
            -- be conditioned on what we were trying to do. Comparing before with after is the
            -- only way to tell "combat refused me" from "the player just closed it".
            local wasActive = SuuUI.KeybindMode:IsActive()
            local nowActive = SuuUI.KeybindMode:Toggle()
            if not wasActive and not nowActive then
                -- Components/Notice.lua's own header prescribes this over printing to chat, and
                -- the addon has no chat output anywhere -- so a print here would have invented a
                -- convention. "warning" is its tone for a blocked but EXPECTED action, which a
                -- combat refusal is.
                SuuUI.Components.Notice({
                    title   = "Keybind Mode",
                    message = "Keybinds cannot be changed in combat. Try again once you are out "
                        .. "of the fight.",
                    tone    = "warning",
                })
            end
        end
    else
        SuuUI.SettingsWindow.Toggle()
    end
end

-- Rebuild nav when plugin list changes
SuuUI.Events:On("SUUUI_PLUGIN_ENABLED", function()
    if win then buildNav() end
end, "settings_rebuild")

SuuUI.Events:On("SUUUI_PLUGIN_DISABLED", function()
    if win then buildNav() end
end, "settings_rebuild_disabled")
