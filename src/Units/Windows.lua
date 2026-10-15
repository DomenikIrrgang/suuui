-- Units/Windows.lua
-- Blizzard's other windows in SuuUI's WindowFrame look (Phase 3), restyled
-- in place through UI.SkinWindow: their clicks, tabs and panes stay
-- Blizzard's. Each window is skinned when its addon has loaded.
--   3.2a: the spells window (PlayerSpellsFrame: Specialization, Talents,
--         Spellbook; protected, so its parts move only out of combat) and the
--         Legacy window (LegacySystemFrame: Tree, Challenges, Reward track):
--         SuuUI's header, the tabs as text tabs along the top, Blizzard's
--         metal frame, portrait and title strip out of sight. Both open
--         lined up under the micro menu (the protected spells window moved
--         only out of combat). The Legacy window opens in the middle of the
--         screen instead (asked for in game), like SuuUI's Talents window.
--   3.3:  the professions window (ProfessionsFrame), in the middle too.
-- A built-in module written against the public API only.

local UI, T = SuuUI.UI, SuuUI.Tokens
local S = T.space

local M = SuuUI.RegisterModule({
    id = "windows",
    name = "Blizzard windows",
    description = "The spells and Legacy windows in SuuUI's look.",
    api = "0.12",
    reloadToToggle = true,
    defaults = {},
})

local GLYPHS = "Interface\\AddOns\\SuuUI\\Media\\Textures\\Glyphs\\"

-- A tab button's own label ("Talents").
local function label(b)
    local fs = b.Text or b.text
    local t = fs and fs:GetText()
    return type(t) == "string" and t or nil
end

--------------------------------------------------------------------------------
-- The spells window
--------------------------------------------------------------------------------

-- The key each tab opens with.
local SPELL_BINDINGS = { Spellbook = "TOGGLESPELLBOOK", Talents = "TOGGLETALENTS", Specialization = "TOGGLESPECIALIZATION" }

-- Blizzard's maximise/minimise pair, next to the key chip: a gilt plus or
-- minus on SuuUI's edge.
local function skinMaxMin(chrome, mm)
    if not mm then return end
    for _, key in ipairs({ "MaximizeButton", "MinimizeButton" }) do
        local b = mm[key]
        if b then
            for _, get in ipairs({ "GetNormalTexture", "GetPushedTexture", "GetHighlightTexture", "GetDisabledTexture" }) do
                local t = b[get] and b[get](b)
                if t then t:SetAlpha(0) end
            end
            for _, r in ipairs({ b:GetRegions() }) do r:SetAlpha(0) end
            local glyph = b:CreateTexture(nil, "OVERLAY", nil, 7)
            glyph:SetTexture(GLYPHS .. (key == "MaximizeButton" and "plus" or "minus") .. ".tga")
            glyph:SetSize(12, 12)
            glyph:SetPoint("CENTER")
            glyph:SetVertexColor(UI.RGBA("ink-muted"))
            local edge = UI.Border(b, "gilt-line")
            edge:SetShown(false)
            b:HookScript("OnEnter", function() edge:SetShown(true); glyph:SetVertexColor(UI.RGBA("ink")) end)
            b:HookScript("OnLeave", function() edge:SetShown(false); glyph:SetVertexColor(UI.RGBA("ink-muted")) end)
            b:SetSize(22, 22)
        end
    end
    mm:SetSize(22, 22)
    mm:ClearAllPoints()
    local right = chrome.key or chrome.close
    mm:SetPoint("RIGHT", right, "LEFT", -S["space-3"], 0)
    mm:SetFrameLevel(chrome.head:GetFrameLevel() + 3)
end

function M:SkinSpells()
    local f = _G.PlayerSpellsFrame
    if not f or f.suuChrome or InCombatLockdown() then return end
    local chrome = UI.SkinWindow(f, {
        title = "Talents", icon = "book", binding = "TOGGLETALENTS",
        close = _G.PlayerSpellsFrameCloseButton, topInset = 20,
        -- under the micro menu like the others (found in game: Blizzard's
        -- place put SuuUI's header against the top of the screen)
        under = "microMenu",
        hide = { f.NineSlice, f.PortraitContainer, f.TitleContainer, _G.PlayerSpellsFrameBg, f.TopTileStreaks },
    })
    -- the tabs (Blizzard's tab system, bottom left) along the top
    local system = f.TabSystem or f.tabSystem
    local list = {}
    if system then
        for _, b in ipairs({ system:GetChildren() }) do
            if b:IsObjectType("Button") and label(b) then
                list[#list + 1] = { button = b, label = label(b), short = label(b),
                    selected = function() return b.LeftActive and b.LeftActive:IsShown() or false end }
            end
        end
        table.sort(list, function(a, b) return (a.button:GetLeft() or 0) < (b.button:GetLeft() or 0) end)
        system:SetAlpha(1)
    end
    chrome:SetTabs(list)
    -- the title and key chip follow the open tab
    local function follow()
        local title = _G.PlayerSpellsFrameTitleText and _G.PlayerSpellsFrameTitleText:GetText()
        for _, def in ipairs(list) do
            if def.selected() then
                title = def.label
                chrome:SetBinding(SPELL_BINDINGS[def.label])
            end
        end
        if type(title) == "string" then chrome:SetTitle(title) end
        chrome:UpdateTabs()
    end
    if _G.PlayerSpellsFrameTitleText then hooksecurefunc(_G.PlayerSpellsFrameTitleText, "SetText", follow) end
    for _, def in ipairs(list) do def.button:HookScript("OnClick", function() C_Timer.After(0, follow) end) end
    f:HookScript("OnShow", function() C_Timer.After(0, follow) end)
    skinMaxMin(chrome, f.MaximizeMinimizeButton)
    follow()
    self.spells = chrome
end

--------------------------------------------------------------------------------
-- The Legacy window
--------------------------------------------------------------------------------

local LEGACY_TABS = {
    { name = "LegacyTreeTab", label = "Tree" },
    { name = "LegacyChallengeTab", label = "Challenges" },
    { name = "LegacyRewardTrackTab", label = "Reward track", short = "Rewards", track = true },
}

function M:SkinLegacy()
    local f = _G.LegacySystemFrame
    if not f or f.suuChrome then return end
    local chrome = UI.SkinWindow(f, {
        title = "Legacy", icon = "trophy", close = _G.LegacySystemFrameCloseButton, topInset = 20,
        under = "microMenu",
        hide = { f.NineSlice, f.PortraitContainer, f.TitleContainer, _G.LegacySystemFrameBg, f.TopTileStreaks },
    })
    -- SuuUI's Legacy pages put the reward track along the window's foot:
    -- then no tab for it (its button out of sight)
    local legacy = SuuUI.GetModule("legacy")
    local ownTrack = legacy and legacy:Get("enabled")
    local list = {}
    for _, t in ipairs(LEGACY_TABS) do
        -- fields of the window on Forever, not globals (found in game: no tabs)
        local b = f[t.name] or _G[t.name]
        if b and ownTrack and t.track then
            b:SetAlpha(0)
            b:EnableMouse(false)
            b:ClearAllPoints()
            b:SetPoint("TOPLEFT", UIParent, "TOPRIGHT", 5000, 0)
        elseif b then
            list[#list + 1] = { button = b, label = t.label, short = t.short or t.label }
        end
    end
    for _, def in ipairs(list) do
        local b = def.button
        def.selected = function() return b.SelectedTexture and b.SelectedTexture:IsShown() or false end
    end
    chrome:SetTabs(list)
    f:HookScript("OnShow", function() C_Timer.After(0, function() chrome:UpdateTabs() end) end)
    -- in the middle of the screen, like the Talents window (asked for in game)
    UI.CenterWindow(f, true)
    self.legacy = chrome
end

--------------------------------------------------------------------------------
-- Lifecycle
--------------------------------------------------------------------------------

--------------------------------------------------------------------------------
-- The professions window (3.3): SuuUI's header; the Professions module puts
-- its pages over Blizzard's. In the middle of the screen, like Talents and
-- Legacy.
--------------------------------------------------------------------------------

function M:SkinProfessions()
    local f = _G.ProfessionsFrame
    if not f or f.suuChrome or InCombatLockdown() then return end
    local chrome = UI.SkinWindow(f, {
        title = "Professions", icon = "hammer", binding = "TOGGLEPROFESSIONBOOK",
        close = f.CloseButton, topInset = 20, under = "microMenu",
        hide = { f.NineSlice, f.PortraitContainer, f.TitleContainer, f.Bg, f.TopTileStreaks },
    })
    UI.CenterWindow(f, true)
    self.professions = chrome
end

--------------------------------------------------------------------------------
-- The friends window (3.4): SuuUI's header; Contacts and Raid as tabs (the
-- Social module puts its pages over Blizzard's); Quick Join left out
-- (asked: not used on Forever).
--------------------------------------------------------------------------------

local FRIENDS_TABS = {
    { name = "FriendsFrameTab1", label = "Contacts", tab = 1 },
    { name = "FriendsFrameTab3", label = "Raid", tab = 3 },
}

function M:SkinFriends()
    local f = _G.FriendsFrame
    if not f or f.suuChrome then return end
    local chrome = UI.SkinWindow(f, {
        title = "Social", icon = "people", binding = "TOGGLESOCIAL", close = _G.FriendsFrameCloseButton,
        topInset = 20, under = "microMenu",
        hide = { f.NineSlice, f.PortraitContainer, f.TitleContainer, _G.FriendsFrameInset, f.Bg, f.TopTileStreaks },
    })
    local list = {}
    for _, t in ipairs(FRIENDS_TABS) do
        local b = _G[t.name]
        if b then
            local index = t.tab
            list[#list + 1] = { button = b, label = t.label, short = t.label,
                selected = function() return (f.selectedTab or (PanelTemplates_GetSelectedTab and PanelTemplates_GetSelectedTab(f))) == index end }
        end
    end
    chrome:SetTabs(list)
    -- Quick Join's tab out of sight
    local qj = _G.FriendsFrameTab4
    if qj then
        qj:SetAlpha(0)
        qj:EnableMouse(false)
        qj:ClearAllPoints()
        qj:SetPoint("TOPLEFT", UIParent, "TOPRIGHT", 5000, 0)
    end
    f:HookScript("OnShow", function() C_Timer.After(0, function() chrome:UpdateTabs() end) end)
    if PanelTemplates_SetTab then
        hooksecurefunc("PanelTemplates_SetTab", function(frame) if frame == f then chrome:UpdateTabs() end end)
    end
    self.friends = chrome
end

-- Forever's own social window (SocialUIFrame, O): SuuUI's header; its
-- tabs down the right side stay Blizzard's for now.
function M:SkinSocial()
    local f = _G.SocialUIFrame
    if not f or f.suuChrome then return end
    local chrome = UI.SkinWindow(f, {
        title = "Social", icon = "people", binding = "TOGGLESOCIAL", close = _G.SocialUIFrameCloseButton,
        topInset = 20, under = "microMenu",
        hide = { f.NineSlice, f.PortraitContainer, f.TitleContainer, _G.SocialUIFrameInset, _G.SocialUIFrameBg, f.TopTileStreaks },
    })
    -- every other texture of the window's own away too: one behind the
    -- content (under the Battle.net bar) darkened half the page, found in
    -- game; SuuUI's glass stays
    for _, region in ipairs({ f:GetRegions() }) do
        if region ~= chrome.bg and region.GetObjectType and region:GetObjectType() == "Texture" then region:SetAlpha(0) end
    end
    -- its four tab buttons down the right side as text tabs along the header,
    -- like every other window (asked for in game); top to bottom they open
    -- the friends list, Recent Allies, Friend Requests and Raid. Which one is
    -- lit follows the content actually shown. Set up when the window opens
    -- (the buttons aren't there, or have no size, when it's skinned at login)
    f:HookScript("OnShow", function() C_Timer.After(0, function() self:SocialTabs() end) end)
    if f:IsShown() then self:SocialTabs() end
    self.social = chrome
end

function M:SocialTabs()
    local f = _G.SocialUIFrame
    local chrome = f and f.suuChrome
    if not chrome then return end
    if chrome.tabs then chrome:UpdateTabs() return end
    local function friendsList()
        for _, c in ipairs({ f:GetChildren() }) do
            if c.FilterBar and c ~= f.RecentAlliesList and c ~= f.FriendRequestsList then return c end
        end
    end
    -- the side buttons: f's own unnamed buttons, about 54 square (the close
    -- button has a name)
    local buttons = {}
    for _, c in ipairs({ f:GetChildren() }) do
        if c:GetObjectType() == "Button" and not c:GetName() then
            local w, h = c:GetWidth() or 0, c:GetHeight() or 0
            if w > 40 and w < 70 and h > 40 and h < 70 then buttons[#buttons + 1] = c end
        end
    end
    if #buttons < 4 then return end
    table.sort(buttons, function(a, b) return (a:GetTop() or 0) > (b:GetTop() or 0) end)
    local pages = {
        { label = "Friends", frame = friendsList() },
        { label = "Recent allies", short = "Allies", frame = f.RecentAlliesList },
        { label = "Requests", frame = f.FriendRequestsList },
        { label = "Raid", frame = f.RaidFrame },
    }
    local tabs = {}
    for i, b in ipairs(buttons) do
        local page = pages[i]
        if page then
            tabs[#tabs + 1] = { button = b, label = page.label, short = page.short or page.label,
                                selected = function() return page.frame and page.frame:IsShown() or false end }
            if page.frame then page.frame:HookScript("OnShow", function() chrome:UpdateTabs() end) end
        end
    end
    chrome:SetTabs(tabs)
end

--------------------------------------------------------------------------------
-- The guild window (Blizzard's Communities window, J; 3.4): SuuUI's header,
-- every texture of its own away, its side tabs (Chat, Roster, Info) as text
-- tabs along the header; the play-style tab left out for now. The Guild
-- module puts its pages over Blizzard's.
--------------------------------------------------------------------------------

function M:SkinCommunities()
    local f = _G.CommunitiesFrame
    if not f or f.suuChrome then return end
    local chrome = UI.SkinWindow(f, {
        title = "Guild", icon = "flag", binding = "TOGGLEGUILDTAB", close = _G.CommunitiesFrameCloseButton,
        topInset = 20, under = "microMenu",
        hide = { f.NineSlice, f.PortraitContainer, f.TitleContainer, _G.CommunitiesFrameInset, f.Bg, f.TopTileStreaks,
                 f.PortraitOverlay },
    })
    for _, region in ipairs({ f:GetRegions() }) do
        if region ~= chrome.bg and region.GetObjectType and region:GetObjectType() == "Texture" then region:SetAlpha(0) end
    end
    skinMaxMin(chrome, f.MaxMinButtonFrame)
    local tabs = {}
    -- the guild module's Log page (asked for in game: the log as a tab):
    -- while it shows, Blizzard's own tabs aren't the lit one
    local function guild()
        local g = SuuUI.GetModule("guild")
        return g and g:IsEnabled() and g or nil
    end
    -- the guild module's own pages (Log, Settings): while one shows,
    -- Blizzard's tabs aren't the lit one
    local function own(key) local g = guild(); return g and g.ownPage == key or false end
    local function anyOwn() local g = guild(); return g and g.ownPage ~= nil or false end
    for _, t in ipairs({ { f.ChatTab, "Chat" }, { f.RosterTab, "Roster" }, { f.GuildInfoTab, "Info" } }) do
        local b = t[1]
        if b then
            -- check buttons: the restyle pass made them checkboxes (found in
            -- game); they're tabs, drawn by SetTabs
            b.suuOwn = true
            tabs[#tabs + 1] = { button = b, label = t[2], short = t[2],
                                selected = function() return not anyOwn() and b.GetChecked and b:GetChecked() or false end }
            b:HookScript("OnClick", function()
                local g = guild()
                if g and g.ShowOwn then g:ShowOwn(nil) end
                C_Timer.After(0, function() chrome:UpdateTabs() end)
            end)
        end
    end
    local gm = SuuUI.GetModule("guild")
    if gm and gm:Get("enabled") then
        local function ownTab(key, label)
            local b = CreateFrame("Button", nil, f)
            b:SetScript("OnClick", function()
                local g = guild()
                if g and g.ShowOwn then g:ShowOwn(key) end
                chrome:UpdateTabs()
            end)
            tabs[#tabs + 1] = { button = b, label = label, short = label, selected = function() return own(key) end }
            return b
        end
        chrome.logTab = ownTab("log", "Log")
        -- Settings: the Guild Master's (the ranks and what each may do)
        if IsGuildLeader and IsGuildLeader() then chrome.settingsTab = ownTab("settings", "Settings") end
    end
    if #tabs > 0 then chrome:SetTabs(tabs) end
    -- the play-style and benefits tabs out of sight
    for _, b in ipairs({ f.GuildPreferredPlaySettingsTab, f.GuildBenefitsTab }) do
        if b then
            b.suuOwn = true
            b:SetAlpha(0)
            b:EnableMouse(false)
        end
    end
    if f.SetDisplayMode then hooksecurefunc(f, "SetDisplayMode", function() chrome:UpdateTabs() end) end
    f:HookScript("OnShow", function() C_Timer.After(0, function() chrome:UpdateTabs() end) end)
    self.communities = chrome
end

--------------------------------------------------------------------------------
-- The group finder window (LFGParentFrame, the vanilla-style one on Forever;
-- probed 2026-10-14): SuuUI's header, wider (the Group Finder module's
-- Browse page lists tool and chat entries side by side), its own art away,
-- its three side tabs (frames that switch on a click's release:
-- LFGParentFrame_SetActiveTab) as text tabs along the header: Browse, List
-- yourself, Who. The Group Finder module puts its pages over Blizzard's.
--------------------------------------------------------------------------------

M.GROUP_FINDER_SIZE = { 960, 600 }

function M:SkinGroupFinder()
    local f = _G.LFGParentFrame
    if not f or f.suuChrome then return end
    f:SetSize(M.GROUP_FINDER_SIZE[1], M.GROUP_FINDER_SIZE[2])
    local chrome = UI.SkinWindow(f, {
        title = "Group Finder", icon = "search", binding = "TOGGLEGROUPFINDER", close = _G.LFGParentFrameCloseButton,
        topInset = 20, under = "microMenu",
        hide = { f.NineSlice, f.PortraitContainer, f.TitleContainer, _G.LFGParentFramePortrait, f.Inset, f.Bg, f.TopTileStreaks },
    })
    for _, region in ipairs({ f:GetRegions() }) do
        if region ~= chrome.bg and region.GetObjectType and region:GetObjectType() == "Texture" then region:SetAlpha(0) end
    end
    -- the eye (strata HIGH, over the header's tabs) out of sight and out of the way
    local eye = _G.LFGParentFramePortrait
    if eye then eye:SetAlpha(0); eye:EnableMouse(false) end
    local browse, listing, who = _G.LFGBrowseFrame, _G.LFGListingFrame, _G.LFGWhoListFrame
    -- each page is a whole Blizzard frame of its own over the window (found in
    -- game): its metal frame, portrait ring, "Looking For Group" title and
    -- backdrops away; its controls stay
    for _, page in ipairs({ browse, listing, who }) do
        for _, key in ipairs({ "NineSlice", "PortraitContainer", "TitleContainer", "Bg", "TopTileStreaks", "BackgroundArt",
                               "headerBackground", "insideFrame", "BarTop", "BarMiddle", "Inset", "RolesSection",
                               "DividerFrame" }) do
            local part = page[key]
            if part and part.SetAlpha then part:SetAlpha(0) end
        end
    end
    local tabs = {}
    for _, t in ipairs({ { f.BrowsingTab, "Browse", browse }, { f.ListingTab, "List yourself", listing, "List" },
                         { f.WhoListingTab, "Who", who } }) do
        if t[1] then
            tabs[#tabs + 1] = { button = t[1], label = t[2], short = t[4] or t[2],
                                selected = function() return t[3] and t[3]:IsShown() or false end }
            if t[3] then t[3]:HookScript("OnShow", function() chrome:UpdateTabs() end) end
        end
    end
    chrome:SetTabs(tabs)
    self.groupFinder = chrome
    -- the second tab says My listing while you're listed
    local listingTab
    for _, t in ipairs(tabs) do if t.button == f.ListingTab then listingTab = t end end
    local function relabel()
        if not listingTab then return end
        local listed = C_LFGList and C_LFGList.HasActiveEntryInfo and C_LFGList.HasActiveEntryInfo()
        listingTab.label = listed and "My listing" or "List yourself"
        listingTab.short = listed and "Listing" or "List"
        chrome:LayoutTabs()
    end
    self:OnGameEvent("LFG_LIST_ACTIVE_ENTRY_UPDATE", relabel)
    relabel()
    -- the tab row's right: a gear that opens Settings › Group Finder
    local gear = CreateFrame("Button", nil, chrome.head)
    gear:SetSize(22, 22)
    gear:SetPoint("BOTTOMRIGHT", chrome.head, "BOTTOMRIGHT", -S["space-5"], S["space-1"])
    gear:SetFrameLevel(chrome.head:GetFrameLevel() + 3)
    local glyph = gear:CreateTexture(nil, "ARTWORK")
    glyph:SetTexture(GLYPHS .. "gear.tga")
    glyph:SetSize(14, 14)
    glyph:SetPoint("CENTER")
    glyph:SetVertexColor(UI.RGBA("ink-muted"))
    local edge = UI.Border(gear, "gilt-line")
    edge:SetShown(false)
    gear:SetScript("OnEnter", function(b)
        edge:SetShown(true); glyph:SetVertexColor(UI.RGBA("ink"))
        UI.ShowTooltip(b, { title = "Group Finder settings", description = "Channels, languages, your ad and the notifications" })
    end)
    gear:SetScript("OnLeave", function()
        edge:SetShown(false); glyph:SetVertexColor(UI.RGBA("ink-muted")); UI.HideTooltip()
    end)
    gear:SetScript("OnClick", function() SuuUI.OpenSettings("groupfinder") end)
    chrome.gear = gear
end

--------------------------------------------------------------------------------
-- The world map (3.5, stage 1; source read 2026-10-15: WorldMapFrame isn't
-- protected, its quest log is QuestMapFrame docked as a 333px side panel):
-- SuuUI's header with "Continent › Zone", the game's border, portrait and
-- title away, the quest log and its details restyled in place (their
-- clicks stay the game's), the game's own filter menu, side-panel toggle
-- and maximize in SuuUI's look, and a status line: the coordinates under
-- the cursor (yours when it's off the map) and zoom. Left where the game
-- places it (it has a maximized mode of its own).
--------------------------------------------------------------------------------

-- "Kalimdor › Durotar": the map's continent before its name.
local function mapTitle(mapID)
    local info = mapID and C_Map.GetMapInfo(mapID)
    if not info then return "World map" end
    local continent
    local parent = info.parentMapID
    local guard = 0
    while parent and parent > 0 and guard < 6 do
        local p = C_Map.GetMapInfo(parent)
        if not p then break end
        if p.mapType == (Enum.UIMapType and Enum.UIMapType.Continent or 2) then continent = p.name break end
        parent, guard = p.parentMapID, guard + 1
    end
    return continent and (continent .. " › " .. info.name) or info.name
end

function M:RestyleQuestLog()
    local q = _G.QuestMapFrame
    if not q then return end
    UI.Reskin(q)
    local d = q.DetailsFrame
    if d then
        for _, key in ipairs({ "Bg", "SealMaterialBG" }) do if d[key] and d[key].SetAlpha then d[key]:SetAlpha(0) end end
        if d.BorderFrame then d.BorderFrame:SetAlpha(0) end
    end
end

function M:SkinWorldMap()
    local f = _G.WorldMapFrame
    if not f or f.suuChrome then return end
    local b = f.BorderFrame
    local chrome = UI.SkinWindow(f, {
        title = mapTitle(f:GetMapID()), icon = "map", binding = "TOGGLEWORLDMAP",
        close = (b and b.CloseButton) or _G.WorldMapFrameCloseButton, topInset = 24,
        hide = { b and b.NineSlice, b and b.PortraitContainer, b and b.TitleContainer, b and b.Bg, f.BorderFrame and f.BorderFrame.Bg,
                 b and b.TopTileStreaks, b and b.InsetBorderTop },
    })
    -- the help-plate button: away
    if b and b.Tutorial then b.Tutorial:SetAlpha(0); b.Tutorial:EnableMouse(false) end
    if b and b.MaximizeMinimizeFrame then skinMaxMin(chrome, b.MaximizeMinimizeFrame) end
    -- the title follows the map
    EventRegistry:RegisterCallback("MapCanvas.MapSet", function(_, mapID)
        if f:IsShown() then chrome:SetTitle(mapTitle(mapID)) end
    end, self)
    -- the game's filter menu and the side-panel toggle in SuuUI's look
    if f.WorldMapTrackingOptionsButton then UI.ReskinDropdown(f.WorldMapTrackingOptionsButton) end
    local toggle = f.SidePanelToggle
    if toggle then
        for _, key in ipairs({ "OpenButton", "CloseButton" }) do
            local btn = toggle[key]
            if btn then
                for _, get in ipairs({ "GetNormalTexture", "GetPushedTexture", "GetHighlightTexture" }) do
                    local t = btn[get] and btn[get](btn)
                    if t then t:SetAlpha(0) end
                end
                UI.Fill(btn, "surface-raised", "BACKGROUND", 7):SetAllPoints()
                UI.Border(btn, "gilt-line")
                local g = btn:CreateTexture(nil, "OVERLAY")
                g:SetTexture(GLYPHS .. (key == "OpenButton" and "chevronLeft" or "chevronRight") .. ".tga")
                g:SetSize(12, 12)
                g:SetPoint("CENTER")
                g:SetVertexColor(UI.RGBA("ink-muted"))
            end
        end
    end
    -- the quest log: restyled now and whenever the game lays it out again
    self:RestyleQuestLog()
    if _G.QuestLogQuests_Update then hooksecurefunc("QuestLogQuests_Update", function() self:RestyleQuestLog() end) end
    if _G.QuestMapFrame_ShowQuestDetails then
        hooksecurefunc("QuestMapFrame_ShowQuestDetails", function() C_Timer.After(0, function() self:RestyleQuestLog() end) end)
    end
    -- the status line: coordinates and zoom, over the map's bottom left
    local status = CreateFrame("Frame", nil, f)
    status:SetFrameLevel(f:GetFrameLevel() + 450)
    status:SetSize(220, 26)
    status:SetPoint("BOTTOMLEFT", f.ScrollContainer or f, "BOTTOMLEFT", S["space-3"], S["space-3"])
    UI.Fill(status, "surface-glass"):SetAllPoints()
    UI.Border(status, "gilt-line")
    local coord = UI.Text(status, "numeric", "ink")
    coord:SetPoint("LEFT", S["space-4"], 0)
    local zoomIn = UI.Button(status, { text = "", width = 22, onClick = function() f:ZoomIn() end,
        tooltip = { title = "Zoom in" } })
    zoomIn:SetHeight(22)
    zoomIn:SetPoint("RIGHT", -2, 0)
    local zoomOut = UI.Button(status, { text = "", width = 22, onClick = function() f:ZoomOut() end,
        tooltip = { title = "Zoom out" } })
    zoomOut:SetHeight(22)
    zoomOut:SetPoint("RIGHT", zoomIn, "LEFT", -S["space-2"], 0)
    for btn, glyph in pairs({ [zoomIn] = "plus", [zoomOut] = "minus" }) do
        local g = btn:CreateTexture(nil, "OVERLAY")
        g:SetTexture(GLYPHS .. glyph .. ".tga")
        g:SetSize(12, 12)
        g:SetPoint("CENTER")
        g:SetVertexColor(UI.RGBA("ink"))
    end
    local wait = 0
    status:SetScript("OnUpdate", function(_, elapsed)
        wait = wait - elapsed
        if wait > 0 then return end
        wait = 0.05
        local x, y, you
        if f.IsCanvasMouseFocus and f:IsCanvasMouseFocus() then
            x, y = f:GetNormalizedCursorPosition()
        else
            local pos = C_Map.GetPlayerMapPosition(f:GetMapID(), "player")
            if pos then x, y = pos:GetXY(); you = true end
        end
        if x and y and (x > 0 or y > 0) then
            coord:SetValue(("%.1f, %.1f"):format(x * 100, y * 100) .. (you and "  |cff" .. T.color["ink-muted"].hex .. "you|r" or ""))
        else
            coord:SetValue("")
        end
    end)
    chrome.status = status
    self.worldMap = chrome
end

function M:SkinAll()
    self:SkinSpells()
    self:SkinLegacy()
    self:SkinProfessions()
    self:SkinFriends()
    self:SkinSocial()
    self:SkinCommunities()
    self:SkinGroupFinder()
    self:SkinWorldMap()
end

function M:OnEnable()
    self:SkinAll()
    -- their addons load on demand
    self:OnGameEvent("ADDON_LOADED", function() self:SkinAll() end)
    -- the spells window is protected: skinned after combat if it loaded during one
    self:OnGameEvent("PLAYER_REGEN_ENABLED", function() self:SkinAll() end)
end
