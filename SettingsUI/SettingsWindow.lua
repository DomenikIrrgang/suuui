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

local function buildNav()
    local T   = SuuUI.Theme
    local gap = T:GetToken("spaceXs") or 4

    local previousId = activeId

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
    S:Connect(navScroll, S.SIGNALS.SIZE_CHANGED, function()
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
    local contentW, contentH = content:GetWidth(), content:GetHeight()

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

SLASH_SUUUI1 = "/suuui"
SlashCmdList["SUUUI"] = function(msg)
    local cmd = (msg or ""):lower():match("^%s*(.-)%s*$")
    if cmd == "toggle" then
        SuuUI.ToggleUI:Toggle()
    elseif cmd == "lock" then
        SuuUI.ToggleUI:Disable()
    elseif cmd == "unlock" then
        SuuUI.ToggleUI:Enable()
    else
        if not win then
            registerCoreSchemas()
            createWindow()
            buildNav()
        end
        win:Toggle()
    end
end

-- Minimap launcher. Built once core is up so it is themed from the start, and
-- placed by an anchor container rather than by hand.
SuuUI.Events:On("SUUUI_CORE_READY", function()
    local host = SuuUI.Layout:CreateContainer({ host = Minimap, layout = "anchor" })
    local size = SuuUI.Theme:GetToken("sizeControlSm") or 18
    local btn = C.IconButton({
        icon = "Interface\\Icons\\INV_Misc_Gem_01",
        w    = size,
    }, Minimap)
    host:Add(btn, {
        anchor = {
            point = "TOPRIGHT", relativePoint = "TOPRIGHT",
            x = -2, y = -2, width = size, height = size,
        },
    })
    S:Connect(btn, S.SIGNALS.CLICKED, function()
        SlashCmdList["SUUUI"]()
    end)
end, "settings_minimap")

-- Rebuild nav when plugin list changes
SuuUI.Events:On("SUUUI_PLUGIN_ENABLED", function()
    if win then buildNav() end
end, "settings_rebuild")

SuuUI.Events:On("SUUUI_PLUGIN_DISABLED", function()
    if win then buildNav() end
end, "settings_rebuild_disabled")
