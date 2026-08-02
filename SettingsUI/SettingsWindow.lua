local ipairs, tinsert = ipairs, table.insert
local C = SuuUI.Components
local S = SuuUI.UISignals

local WIN_W, WIN_H = 780, 520
local NAV_W, DIV_W = 180, 3
local ROW_H        = 32

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
    local gap = T:GetToken("spaceSm") or 4

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

    local entries = SuuUI.Plugins:GetAll()
    tinsert(entries, 1, { id = "_profiles", name = "Profiles" })
    tinsert(entries, 1, { id = "_theme",    name = "Theme" })

    for _, entry in ipairs(entries) do
        local nav = C.NavItem({ label = entry.name, h = ROW_H }, navList:GetFrame())
        navList:Add(nav, { width = "fill", height = ROW_H })

        local pid = entry.id
        S:Connect(nav, S.SIGNALS.CLICKED, function() selectPlugin(pid) end)
        tinsert(navItems, { id = pid, nav = nav })
    end

    if #navItems > 0 then
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
        minW      = 600,
        minH      = 400,
    })

    local content = win:GetContentFrame()

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
    navScroll = C.ScrollFrame({ w = NAV_W, h = WIN_H }, navPanel:GetFrame())
    navBox:Add(navScroll, { width = "fill", height = "fill" })

    local pageBox = SuuUI.Layout:CreateContainer({
        parent = pagePanel:GetFrame(),
        layout = "flow",
        dir    = "vertical",
        fill   = true,
    })
    contentScroll = C.ScrollFrame({ w = WIN_W - NAV_W - DIV_W, h = WIN_H }, pagePanel:GetFrame())
    pageBox:Add(contentScroll, { width = "fill", height = "fill" })
end

SLASH_SUUUI1 = "/suuui"
SlashCmdList["SUUUI"] = function()
    if not win then
        registerCoreSchemas()
        createWindow()
        buildNav()
    end
    win:Toggle()
end

-- Minimap launcher. Built once core is up so it is themed from the start, and
-- placed by an anchor container rather than by hand.
SuuUI.Events:On("SUUUI_CORE_READY", function()
    local host = SuuUI.Layout:CreateContainer({ host = Minimap, layout = "anchor" })
    local btn = C.IconButton({
        icon = "Interface\\Icons\\INV_Misc_Gem_01",
        w    = 20,
    }, Minimap)
    host:Add(btn, {
        anchor = {
            point = "TOPRIGHT", relativePoint = "TOPRIGHT",
            x = -2, y = -2, width = 20, height = 20,
        },
    })
    S:Connect(btn, S.SIGNALS.CLICKED, function()
        SlashCmdList["SUUUI"]()
    end)
end, "settings_minimap")

-- Rebuild nav once plugins have registered
SuuUI.Events:On("SUUUI_PLUGIN_ENABLED", function()
    if win then buildNav() end
end, "settings_rebuild")
