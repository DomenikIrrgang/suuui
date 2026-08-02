local ipairs, tinsert, abs = ipairs, table.insert, math.abs

-- Dimensions
local WIN_W, WIN_H = 780, 520
local NAV_W        = 180
local CONTENT_W    = WIN_W - NAV_W - 3  -- 3px divider

local win, navScroll, contentScroll
local navItems   = {}   -- array of { pluginId, btnFrame }
local activeId   = nil

local function applyNavItemTheme(item, selected)
    local T   = SuuUI.Theme
    local bg  = T:GetToken(selected and "colorBgActive" or "colorBg")
    local tc  = T:GetToken(selected and "colorText" or "colorTextMuted")
    local bw  = T:GetToken("borderWidth") or 1
    item.btn:SetBackdrop({
        bgFile="Interface\\Buttons\\WHITE8x8",
        edgeFile="Interface\\Buttons\\WHITE8x8",
        edgeSize=bw, insets={left=bw,right=bw,top=bw,bottom=bw},
    })
    if bg then item.btn:SetBackdropColor(bg[1], bg[2], bg[3], bg[4]) end
    local bdc = T:GetToken("colorBorder")
    if bdc then item.btn:SetBackdropBorderColor(bdc[1], bdc[2], bdc[3], bdc[4]) end
    if tc  then item.lbl:SetTextColor(tc[1], tc[2], tc[3], tc[4]) end
end

local function selectPlugin(id)
    if activeId == id then return end
    activeId = id

    for _, item in ipairs(navItems) do
        applyNavItemTheme(item, item.id == id)
    end

    -- rebuild content page
    local content = contentScroll:GetContent()
    local scrollHeight = contentScroll:GetFrame():GetHeight()
    SuuUI._PageBuilder:Build(id, content, scrollHeight)
    contentScroll:ScrollToTop()

    -- animate content fade
    SuuUI.Anim.Presets.FadeIn(contentScroll:GetFrame(),
        SuuUI.Theme:GetToken("animFast"))
end

local function buildNav()
    local T       = SuuUI.Theme
    local navCont = navScroll:GetContent()
    local rowH    = 32
    local gap     = T:GetToken("spaceSm") or 4
    local pad     = T:GetToken("spaceSm") or 4
    local contentWidth = navScroll:GetContentWidth()

    -- clear old items
    for _, item in ipairs(navItems) do item.btn:Hide() end
    navItems  = {}
    activeId  = nil   -- reset so auto-select fires correctly

    -- Create a container for proper layout
    local container = SuuUI.Layout:CreateContainer({
        parent  = navCont,
        layout  = "flow",
        dir     = "vertical",
        gap     = gap,
        padding = {
            top    = pad,
            right  = pad,
            bottom = pad,
            left   = pad,
        },
    })
    container:GetFrame():SetAllPoints(navCont)

    local plugins = SuuUI.Plugins:GetAll()

    -- Insert core entries first
    tinsert(plugins, 1, { id = "_profiles", name = "Profiles" })
    tinsert(plugins, 1, { id = "_theme", name = "Theme" })

    for _, plugin in ipairs(plugins) do
        local btn = CreateFrame("Frame", nil, navCont, "BackdropTemplate")
        btn:SetHeight(rowH)
        btn:EnableMouse(true)

        local lbl = btn:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        lbl:SetPoint("LEFT", btn, "LEFT", 8, 0)
        lbl:SetText(plugin.name)
        lbl:SetFont(T:GetToken("fontFamilyMain") or "Fonts/FRIZQT__.TTF",
            T:GetToken("fontSizeMd") or 13, "")

        local item = { id = plugin.id, btn = btn, lbl = lbl }
        tinsert(navItems, item)
        applyNavItemTheme(item, false)

        local pid = plugin.id
        btn:SetScript("OnMouseUp", function() selectPlugin(pid) end)
        btn:SetScript("OnEnter", function()
            if activeId == pid then return end
            local hov = T:GetToken("colorBgHover")
            if hov then btn:SetBackdropColor(hov[1], hov[2], hov[3], hov[4]) end
        end)
        btn:SetScript("OnLeave", function()
            applyNavItemTheme(item, activeId == pid)
        end)

        -- Add to container with fill width
        container:Add(btn, { width = "fill" })
    end

    -- Calculate total height for scroll content
    local totalHeight = (#plugins * rowH) + ((#plugins - 1) * gap)
    navCont:SetHeight(totalHeight)

    -- auto-select first
    if #navItems > 0 and not activeId then
        selectPlugin(navItems[1].id)
    end
end

local function buildCoreSettingsSchema()
    -- Theme settings
    if not SuuUI.Settings:GetSchema("_theme") then
        SuuUI.Settings:Register("_theme", {
            { key="theme_mgr", type="theme_manager" },
        })
    end
    
    -- Profile settings
    if not SuuUI.Settings:GetSchema("_profiles") then
        SuuUI.Settings:Register("_profiles", {
            { key="profile_mgr", type="profile_manager" },
        })
    end
end

local function createWindow()
    local T = SuuUI.Theme

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

    -- Nav panel background (anchored to left edge and full height)
    local navBg = CreateFrame("Frame", nil, content, "BackdropTemplate")
    navBg:SetPoint("TOPLEFT",    content, "TOPLEFT",    0,  0)
    navBg:SetPoint("BOTTOMLEFT", content, "BOTTOMLEFT", 0,  0)
    navBg:SetWidth(NAV_W)

    -- Nav scroll (fills entire navBg)
    navScroll = SuuUI.Components.ScrollFrame({ w=NAV_W, h=100 }, navBg)
    navScroll:GetFrame():SetPoint("TOPLEFT", navBg, "TOPLEFT", 0, 0)
    navScroll:GetFrame():SetPoint("BOTTOMRIGHT", navBg, "BOTTOMRIGHT", 0, 0)
    
    -- Ensure navScroll resizes when window resizes
    navBg:SetScript("OnSizeChanged", function(self, width, height)
        navScroll:SetSize(width, height)
    end)

    -- Divider between nav and content (full height)
    local div = SuuUI.Components.Divider({ dir="vertical", h=100 }, content)
    div:SetPoint("TOPLEFT", content, "TOPLEFT", NAV_W, 0)
    div:SetPoint("BOTTOMLEFT", content, "BOTTOMLEFT", NAV_W, 0)

    -- Content scroll (fills remaining space to the right of divider)
    contentScroll = SuuUI.Components.ScrollFrame({ w=100, h=100 }, content)
    contentScroll:GetFrame():SetPoint("TOPLEFT", content, "TOPLEFT", NAV_W + 3, 0)
    contentScroll:GetFrame():SetPoint("BOTTOMRIGHT", content, "BOTTOMRIGHT", 0, 0)
    
    -- Ensure ScrollFrame resizes when window resizes
    content:SetScript("OnSizeChanged", function(self, width, height)
        local scrollWidth = width - NAV_W - 3
        local scrollHeight = height
        contentScroll:SetSize(scrollWidth, scrollHeight)
    end)

    -- Theme navBg
    local function styleNavBg()
        local bg = T:GetToken("colorBgAlt")
        local bd = T:GetToken("colorBorder")
        local bw = T:GetToken("borderWidth") or 1
        navBg:SetBackdrop({
            bgFile="Interface\\Buttons\\WHITE8x8",
            edgeFile="Interface\\Buttons\\WHITE8x8",
            edgeSize=bw, insets={left=bw,right=bw,top=bw,bottom=bw},
        })
        if bg then navBg:SetBackdropColor(bg[1], bg[2], bg[3], bg[4]) end
        if bd then navBg:SetBackdropBorderColor(bd[1], bd[2], bd[3], bd[4]) end
    end
    styleNavBg()
    SuuUI.Events:On("SUUUI_THEME_CHANGED", styleNavBg, "settings_navbg")
end

-- Slash command
SLASH_SUUUI1 = "/suuui"
SlashCmdList["SUUUI"] = function()
    if not win then
        buildCoreSettingsSchema()
        createWindow()
        buildNav()
    end
    win:Toggle()
end

-- Minimap button (simple texture button on Minimap)
local minimapBtn = CreateFrame("Button", "SuuUI_MinimapButton", Minimap)
minimapBtn:SetSize(20, 20)
minimapBtn:SetPoint("TOPRIGHT", Minimap, "TOPRIGHT", -2, -2)
minimapBtn:SetFrameStrata("HIGH")
minimapBtn:SetNormalTexture("Interface\\Icons\\INV_Misc_Gem_01")
minimapBtn:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")
minimapBtn:SetScript("OnClick", function()
    SlashCmdList["SUUUI"]()
end)

-- Rebuild nav after all plugins have initialised
SuuUI.Events:On("SUUUI_PLUGIN_ENABLED", function()
    if win then buildNav() end
end, "settings_rebuild")
