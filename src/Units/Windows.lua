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
--   3.6:  the trainer window (ClassTrainerFrame), under the micro menu.
-- A built-in module written against the public API only.

local UI, T = SuuUI.UI, SuuUI.Tokens
local S = T.space

local M = SuuUI.RegisterModule({
    id = "windows",
    name = "Blizzard windows",
    description = "The spells and Legacy windows in SuuUI's look.",
    api = "0.12",
    reloadToToggle = true,
    -- (the world map enlarged: its maximize button)
    defaults = { mapEnlarged = true },
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
-- the cursor (yours when it's off the map). Small, in the window row under
-- the micro menu; maximized, SuuUI's enlarged map in the screen's middle.
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

local trackEyes = setmetatable({}, { __mode = "k" })

-- The map's top: the game keeps 67px over it for its breadcrumb bar
-- (TITLE_CANVAS_SPACER_FRAME_HEIGHT); SuuUI's starts it right under the
-- header, level with the quest log's top (the game's QuestMapFrame at -25,
-- moved down with it). The header's second row (filters, the log's search)
-- is ROW_EXTRA taller than other windows' (asked: a taller search box).
-- The window is as much shorter, so the map keeps its shape; the quest
-- log and its details run down to its bottom.
local ROW_EXTRA = 8
local GAME_MAP_TOP, MAP_TOP = 67, 25 + ROW_EXTRA
local CUT = GAME_MAP_TOP - MAP_TOP
-- the second row's controls, their middles on one line in it, the
-- chrome's rowMid (anchored by their bottoms, controls of different heights
-- sat at different heights: found in game)
local ROW_MID = S["space-1"] + 11 + ROW_EXTRA / 2
local SEARCH_H = 26

-- A button in the header's second row: a glyph, its edge on hover.
local function glyphButton(b, glyphName)
    for _, r in ipairs({ b:GetRegions() }) do r:SetAlpha(0) end
    for _, get in ipairs({ "GetNormalTexture", "GetPushedTexture", "GetHighlightTexture", "GetDisabledTexture" }) do
        local t = b[get] and b[get](b)
        if t then t:SetAlpha(0) end
    end
    local glyph = b:CreateTexture(nil, "OVERLAY", nil, 7)
    glyph:SetTexture(GLYPHS .. glyphName .. ".tga")
    glyph:SetSize(14, 14)
    glyph:SetPoint("CENTER")
    glyph:SetVertexColor(UI.RGBA("ink-muted"))
    local edge = UI.Border(b, "gilt-line")
    edge:SetShown(false)
    b:HookScript("OnEnter", function() edge:SetShown(true); glyph:SetVertexColor(UI.RGBA("ink")) end)
    b:HookScript("OnLeave", function() edge:SetShown(false); glyph:SetVertexColor(UI.RGBA("ink-muted")) end)
    b:SetSize(22, 22)
end

-- The quest log's search box in the header's second row: as tall as the
-- row's controls allow, SuuUI's search glyph in front (the reskin hid the
-- game's), its × a glyph (the reskin had made it a button: a bare square).
local function styleQuestSearch(sb)
    sb:SetHeight(SEARCH_H)
    -- (Forever sets it to 200 x 20 on every count update; its width is
    -- SuuUI's anchors')
    if _G.QuestLogQuests_ShowQuestCount then
        hooksecurefunc("QuestLogQuests_ShowQuestCount", function() sb:SetHeight(SEARCH_H) end)
    end
    local icon = sb.searchIcon or sb.SearchIcon
    if icon then
        icon:SetTexture(GLYPHS .. "search.tga")
        icon:SetTexCoord(0, 1, 0, 1)
        icon:SetSize(12, 12)
        icon:ClearAllPoints()
        icon:SetPoint("LEFT", sb, "LEFT", S["space-1"], 0)
        icon:SetAlpha(1)
        icon:SetVertexColor(UI.RGBA("ink-muted"))
        -- (the game tints it on focus)
        sb:HookScript("OnEditFocusGained", function() icon:SetVertexColor(UI.RGBA("ink")) end)
        sb:HookScript("OnEditFocusLost", function() icon:SetVertexColor(UI.RGBA("ink-muted")) end)
    end
    if sb.Instructions then
        sb.Instructions:SetFontObject(SuuUI.Fonts.Get("body"))
        sb.Instructions:SetTextColor(UI.RGBA("ink-muted"))
    end
    local x = sb.clearButton
    if x then
        for _, r in ipairs({ x:GetRegions() }) do if r:GetObjectType() == "Texture" then r:SetAlpha(0) end end
        local glyph = x:CreateTexture(nil, "OVERLAY", nil, 7)
        glyph:SetTexture(GLYPHS .. "close.tga")
        glyph:SetSize(10, 10)
        glyph:SetPoint("CENTER")
        glyph:SetVertexColor(UI.RGBA("ink-muted"))
        x:HookScript("OnEnter", function() glyph:SetVertexColor(UI.RGBA("ink")) end)
        x:HookScript("OnLeave", function() glyph:SetVertexColor(UI.RGBA("ink-muted")) end)
    end
    sb.suuSearch = true
end

-- The quest list's rows measured again: the game sizes each quest's row
-- for the fonts it had, the reskin gives SuuUI's after, and long
-- objectives wrapped onto more lines than their row had (into the next
-- quest; found in game). The game's sums (QuestLogQuests_AddQuestButton):
-- 8 + the title, each objective 3 (the first) or 2 under the one before,
-- 4 without objectives, 6 for the marker; then the list stacked again.
local function fitQuestRows(list)
    local titles, lines = list.titleFramePool, list.objectiveFramePool
    if not (titles and titles.EnumerateActive and list.Contents and list.Contents.Layout) then return end
    local below = {}
    if lines and lines.EnumerateActive then
        for line in lines:EnumerateActive() do
            local id = line.questID
            if id and line.Text then
                local h = line.Text:GetStringHeight()
                line:SetHeight(h)
                below[id] = (below[id] or 0) + h + (below[id] and 2 or 3)
            end
        end
    end
    local objectives = GetCVarBool("showQuestObjectivesInLog")
    local changed = false
    for row in titles:EnumerateActive() do
        if row.questID and row.Text then
            local h = 8 + row.Text:GetStringHeight() + (objectives and (below[row.questID] or 0) or 4) + 6
            if math.abs(row:GetHeight() - h) > 0.5 then
                row:SetHeight(h)
                changed = true
            end
        end
    end
    if changed then list.Contents:Layout() end
end

function M:RestyleQuestLog()
    local q = _G.QuestMapFrame
    if not q then return end
    local sb = _G.QuestScrollFrame and _G.QuestScrollFrame.SearchBox
    -- (its × not made a button by the reskin)
    if sb and sb.clearButton then sb.clearButton.suuNoButton = true end
    UI.Reskin(q)
    if sb and not sb.suuSearch then styleQuestSearch(sb) end
    local d = q.DetailsFrame
    if d then
        for _, key in ipairs({ "Bg", "SealMaterialBG" }) do if d[key] and d[key].SetAlpha then d[key]:SetAlpha(0) end end
        if d.BorderFrame then d.BorderFrame:SetAlpha(0) end
        if not d.suuStyled then
            d.suuStyled = true
            -- the game sizes the details for its own window (502 px, its
            -- text 430, from the log's top 1 px down): to the log's bottom
            -- instead, 3 px above it as the game's, so they fit the small
            -- window and run all the way down the enlarged one (fixed, they
            -- stopped two thirds down it, found in game); the text to the
            -- game's 29 px above the details' bottom
            d:SetPoint("BOTTOMRIGHT", 0, 3)
            if d.ScrollFrame then d.ScrollFrame:SetPoint("BOTTOMLEFT", d, "BOTTOMLEFT", 5, 29) end
            -- Abandon / Share / Track and the rewards centred in the column
            -- the details sit in, between the map and the window's edge,
            -- measured as they show (lined up with the details alone they
            -- sat left: the column runs on past them over the text's scroll
            -- bar; found in game). The game's dividers between them away.
            for _, btn in ipairs({ d.AbandonButton, d.ShareButton, d.TrackButton }) do
                for _, r in ipairs(btn and { btn:GetRegions() } or {}) do
                    local atlas = r:GetObjectType() == "Texture" and r.GetAtlas and r:GetAtlas()
                    if atlas and atlas:find("BtnDiv") then r:SetAlpha(0) end
                end
            end
            -- (a frame after showing, when the positions are there; again when
            -- the window changes size: fullscreen)
            local function place() C_Timer.After(0, function() M:PlaceQuestDetails() end) end
            d:HookScript("OnShow", place)
            if _G.WorldMapFrame then _G.WorldMapFrame:HookScript("OnSizeChanged", place) end
            -- the strip with Back: its art away, a hairline under it
            local back = d.BackFrame
            if back then
                for _, r in ipairs({ back:GetRegions() }) do if r:GetObjectType() == "Texture" then r:SetAlpha(0) end end
                local line = UI.Hairline(back, "gilt-line")
                line:SetPoint("BOTTOMLEFT", 6, 8)
                line:SetPoint("BOTTOMRIGHT", -6, 8)
            end
            -- the rewards: surface instead of the brown art (still opaque:
            -- the text scrolls under it), a hairline on top, the label in ink
            local rewards = d.RewardsFrameContainer and d.RewardsFrameContainer.RewardsFrame
            if rewards then
                for _, key in ipairs({ "Top", "Bottom", "Background" }) do if rewards[key] then rewards[key]:SetAlpha(0) end end
                local fill = UI.Fill(rewards, "surface", "BACKGROUND")
                fill:SetAllPoints()
                local line = UI.Hairline(rewards, "gilt-line")
                line:SetPoint("TOPLEFT", 6, 0)
                line:SetPoint("TOPRIGHT", -6, 0)
                if rewards.Label then
                    rewards.Label:SetFontObject(SuuUI.Fonts.Get("label"))
                    rewards.Label:SetTextColor(UI.RGBA("ink"))
                end
            end
        end
    end
    -- the list's ornate frame and parchment away
    local list = _G.QuestScrollFrame
    if list then
        for _, key in ipairs({ "BorderFrame", "Background" }) do if list[key] and list[key].SetAlpha then list[key]:SetAlpha(0) end end
        if not list.suuPlaced then
            list.suuPlaced = true
            self:PlaceQuestList(q, list)
        end
        -- the zone headers in label ink, hovered or not (the game switches a
        -- header's font on hover, so a header first seen hovered read as a
        -- title; found in game)
        -- (their own font in ink: the button takes its font's colour on hover)
        local label = _G.SuuUIQuestHeaderFont
        if not label then
            label = CreateFont("SuuUIQuestHeaderFont")
            label:CopyFontObject(SuuUI.Fonts.Get("label"))
            label:SetTextColor(UI.RGBA("ink"))
        end
        for _, pool in ipairs({ list.headerFramePool, list.campaignHeaderMinimalFramePool }) do
            if pool and pool.EnumerateActive then
                for row in pool:EnumerateActive() do
                    if row.SetNormalFontObject then
                        row:SetNormalFontObject(label)
                        row:SetHighlightFontObject(label)
                        row:SetDisabledFontObject(label)
                    end
                    for _, r in ipairs({ row:GetRegions() }) do
                        if r:GetObjectType() == "FontString" then r:SetFontObject(label); r:SetTextColor(UI.RGBA("ink")) end
                    end
                    local fs = row.ButtonText or (row.GetFontString and row:GetFontString())
                    if fs then fs:SetFontObject(label); fs:SetTextColor(UI.RGBA("ink")) end
                end
            end
        end
        -- a tracked quest: the drawing's eye, not the game's yellow tick
        local pool = list.titleFramePool
        if pool and pool.EnumerateActive then
            for row in pool:EnumerateActive() do
                local cb = row.Checkbox
                if cb then
                    local eye = trackEyes[cb]
                    if not eye then
                        for _, r in ipairs({ cb:GetRegions() }) do if r:GetObjectType() == "Texture" then r:SetAlpha(0) end end
                        eye = cb:CreateTexture(nil, "OVERLAY", nil, 7)
                        eye:SetTexture(GLYPHS .. "eye.tga")
                        eye:SetSize(14, 14)
                        eye:SetPoint("CENTER")
                        eye:SetVertexColor(UI.RGBA("ink-muted"))
                        trackEyes[cb] = eye
                    end
                    eye:SetShown(cb.CheckMark and cb.CheckMark:IsShown() or false)
                end
            end
        end
        fitQuestRows(list)
    end
end

-- The quest list centred in the panel beside the map: the game keeps 22px
-- right of it for its scroll bar, which left its headers 12px from the
-- map and 35px from the window's edge (measured in game: /suu probe map
-- log). The list moves right by half the difference, the scroll bar into
-- the margin it leaves; the search box (fixed at 200px from the quest
-- count leftwards, it ran 10px over the map) starts where the headers do.
local LIST_SHIFT = 11
local HEADER_X = 9 -- the game's zone headers, from the list's left
function M:PlaceQuestList(q, list)
    local quests = q.QuestsFrame
    if quests then
        list:ClearAllPoints()
        list:SetPoint("TOPLEFT", quests, "TOPLEFT", LIST_SHIFT, 0)
        list:SetPoint("BOTTOMRIGHT", quests, "BOTTOMRIGHT", LIST_SHIFT, 0)
    end
    -- (its 8px in the middle of the 24px between the headers and the edge)
    local bar = list.ScrollBar
    if bar then
        bar:ClearAllPoints()
        bar:SetPoint("TOPLEFT", list, "TOPRIGHT", -2, 2)
        bar:SetPoint("BOTTOMLEFT", list, "BOTTOMRIGHT", -2, -4)
    end
    -- the search box: its left (SuuUI's edge 4px outside it) under the
    -- headers' left (the log is questLogWidth wide at the window's right),
    -- its right by the count, its middle on the row's
    local sb, count = list.SearchBox, _G.QuestLogCount
    local head = _G.WorldMapFrame and _G.WorldMapFrame.suuChrome and _G.WorldMapFrame.suuChrome.head
    if not (sb and count and head) then return end
    local fromRight = (_G.WorldMapFrame.questLogWidth or 333) - LIST_SHIFT - HEADER_X - 4
    sb:ClearAllPoints()
    sb:SetPoint("LEFT", head, "BOTTOMRIGHT", -fromRight, ROW_MID)
    sb:SetPoint("RIGHT", count, "LEFT", -S["space-3"], 0)
end

-- The quest details' buttons and rewards, centred between the map and the
-- window's edge with the same margin either side.
function M:PlaceQuestDetails()
    local f, q = _G.WorldMapFrame, _G.QuestMapFrame
    local d = q and q.DetailsFrame
    if not (f and d and d:IsVisible() and f.ScrollContainer) then return end
    local mapRight, edge, left = f.ScrollContainer:GetRight(), f:GetRight(), d:GetLeft()
    if not (mapRight and edge and left) then return end
    local MARGIN, GAP = 11, 4
    local x0, x1 = mapRight + MARGIN - left, edge - MARGIN - left
    local ab, sh, tr = d.AbandonButton, d.ShareButton, d.TrackButton
    if ab and sh and tr then
        local w = math.floor((x1 - x0 - 2 * GAP) / 3)
        ab:ClearAllPoints()
        ab:SetPoint("BOTTOMLEFT", x0, 0)
        sh:ClearAllPoints()
        sh:SetPoint("LEFT", ab, "RIGHT", GAP, 0)
        tr:ClearAllPoints()
        tr:SetPoint("LEFT", sh, "RIGHT", GAP, 0)
        for _, btn in ipairs({ ab, sh, tr }) do btn:SetWidth(w) end
    end
    -- (the rewards start at the details' left: as wide as puts their middle
    -- in the column's)
    local box = d.RewardsFrameContainer
    if box then
        box:SetWidth(x0 + x1)
        if box.RewardsFrame then box.RewardsFrame:SetWidth(x0 + x1) end
    end
end

function M:SkinWorldMap()
    local f = _G.WorldMapFrame
    if not f or f.suuChrome then return end
    local b = f.BorderFrame
    local chrome = UI.SkinWindow(f, {
        title = mapTitle(f:GetMapID()), icon = "map", binding = "TOGGLEWORLDMAP",
        close = (b and b.CloseButton) or _G.WorldMapFrameCloseButton, topInset = 24 + ROW_EXTRA, headExtra = ROW_EXTRA,
        under = "microMenu",
        hide = { b and b.NineSlice, b and b.PortraitContainer, b and b.TitleContainer, b and b.Bg, f.BorderFrame and f.BorderFrame.Bg,
                 b and b.TopTileStreaks, b and b.InsetBorderTop },
    })
    -- the help-plate button: away
    if b and b.Tutorial then b.Tutorial:SetAlpha(0); b.Tutorial:EnableMouse(false) end
    if b and b.MaximizeMinimizeFrame then skinMaxMin(chrome, b.MaximizeMinimizeFrame) end
    -- the title follows the map; a click on it goes up a level (as a
    -- right-click on the map does): the header names the place, so the
    -- game's breadcrumb bar goes, and its strip with it
    local up = CreateFrame("Button", nil, chrome.head)
    up:SetPoint("TOPLEFT", chrome.title, "TOPLEFT", -2, 2)
    up:SetPoint("BOTTOMRIGHT", chrome.title, "BOTTOMRIGHT", 2, -2)
    up:SetFrameLevel(chrome.head:GetFrameLevel() + 2)
    up:SetScript("OnClick", function()
        local info = C_Map.GetMapInfo(f:GetMapID())
        if info and info.parentMapID and info.parentMapID > 0 then f:SetMapID(info.parentMapID) end
    end)
    up:SetScript("OnEnter", function(self)
        local info = C_Map.GetMapInfo(f:GetMapID())
        local parent = info and info.parentMapID and C_Map.GetMapInfo(info.parentMapID)
        if parent then UI.ShowTooltip(self, { title = "Up to " .. parent.name, description = "Or right-click the map" }) end
        chrome.title:SetColor("ink")
    end)
    up:SetScript("OnLeave", function() UI.HideTooltip(); chrome.title:SetColor("gilt-text") end)
    EventRegistry:RegisterCallback("MapCanvas.MapSet", function(_, mapID)
        if f:IsShown() then chrome:SetTitle(mapTitle(mapID)) end
    end, self)
    -- (left where the game puts it, which it measures itself against:
    -- see-through, and its buttons, made again on every map change, without
    -- the mouse so they don't take clicks over the map's top)
    local function quietNav()
        local nb = f.NavBar
        if not nb then return end
        nb:SetAlpha(0)
        nb:EnableMouse(false)
        for _, btn in ipairs(nb.navList or {}) do btn:EnableMouse(false) end
        for _, key in ipairs({ "home", "overflowButton" }) do if nb[key] then nb[key]:EnableMouse(false) end end
    end
    quietNav()
    hooksecurefunc(f, "OnMapChanged", quietNav)
    -- the map right under the header (the game sets its top whenever the
    -- quest log opens or closes)
    local spacer = f.TitleCanvasSpacerFrame
    local function placeSpacer()
        local log = f.QuestLog and f.QuestLog:IsShown() and (f.questLogWidth or 0) or 0
        spacer:SetPoint("BOTTOMRIGHT", f, "TOPRIGHT", -3 - log, -MAP_TOP)
        f:OnFrameSizeChanged()
    end
    if spacer and f.UpdateSpacerFrameAnchoring then
        hooksecurefunc(f, "UpdateSpacerFrameAnchoring", placeSpacer)
        placeSpacer()
        -- the breadcrumb bar measures itself between the spacer's top and
        -- bottom (25px under its top): kept as tall as it was
        local nb = f.NavBar
        if nb then
            local x = WorldMapConstants and WorldMapConstants.NAVBAR_X_OFFSET or 0
            nb:SetPoint("BOTTOMRIGHT", spacer, "BOTTOMRIGHT", x, 9 - CUT)
        end
    end
    -- the game's own coordinates (SuuUI's status line shows them)
    for _, o in ipairs(f.overlayFrames or {}) do
        if o.PlayerCoords and o.CursorCoords then o:SetAlpha(0) end
    end
    -- the header's second row: the game's filter menu (its reset × away)
    -- and waypoint pin on the left, the quest log's search, count and
    -- settings on the right
    local track, pin = f.WorldMapTrackingOptionsButton, f.WorldMapTrackingPinButton
    local function placeRow()
        if track then
            track:ClearAllPoints()
            track:SetPoint("LEFT", chrome.head, "BOTTOMLEFT", S["space-5"], ROW_MID)
            track:SetFrameLevel(chrome.head:GetFrameLevel() + 3)
        end
        if pin then
            pin:ClearAllPoints()
            if track then pin:SetPoint("LEFT", track, "RIGHT", S["space-2"], 0)
            else pin:SetPoint("LEFT", chrome.head, "BOTTOMLEFT", S["space-5"], ROW_MID) end
            pin:SetFrameLevel(chrome.head:GetFrameLevel() + 3)
        end
    end
    if track then
        UI.ReskinDropdown(track, { glyph = "filter" })
        track:SetSize(22, 22)
        if track.ResetButton then track.ResetButton:SetAlpha(0); track.ResetButton:EnableMouse(false) end
    end
    if pin then glyphButton(pin, "pushpin") end
    placeRow()
    -- the game anchors them over the map again on every map change
    hooksecurefunc(f, "OnMapChanged", placeRow)
    if f.AdjustOverlayFrames then hooksecurefunc(f, "AdjustOverlayFrames", placeRow) end
    local list = _G.QuestScrollFrame
    if list then
        -- the log's top level with the map's (the game's -25)
        local q = _G.QuestMapFrame
        if q and q:GetParent() == f then q:SetPoint("TOPRIGHT", f, "TOPRIGHT", -3, -MAP_TOP) end
        -- the list starts level with the map (the search row was over it)
        list:SetPoint("TOPLEFT", 0, 0)
        local gear, count, search = list.SettingsDropdown, _G.QuestLogCount, list.SearchBox
        local right = chrome.head
        if gear then
            UI.ReskinDropdown(gear, { glyph = "gear" })
            gear:SetSize(22, 22)
            gear:ClearAllPoints()
            gear:SetPoint("RIGHT", chrome.head, "BOTTOMRIGHT", -S["space-5"], ROW_MID)
            -- its menu under the header's rule, not over the row
            if gear.SetMenuAnchor and _G.AnchorUtil then
                gear:SetMenuAnchor(AnchorUtil.CreateAnchor("TOPRIGHT", gear, "BOTTOMRIGHT", 0, -(ROW_MID - 11 + S["space-2"])))
            end
            right = gear
        end
        if count then
            count:ClearAllPoints()
            if gear then count:SetPoint("RIGHT", gear, "LEFT", -S["space-3"], 0)
            else count:SetPoint("RIGHT", chrome.head, "BOTTOMRIGHT", -S["space-5"], ROW_MID) end
            right = count
        end
        if search and right ~= chrome.head then
            search:ClearAllPoints()
            search:SetPoint("RIGHT", right, "LEFT", -S["space-3"], 0)
        end
    end
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
    -- the status line: the coordinates, over the map's bottom left (no zoom
    -- buttons: the mouse wheel zooms, asked in game)
    local status = CreateFrame("Frame", nil, f)
    -- (over the map's pins, the game's and SuuUI's: frame levels 2000 up)
    status:SetFrameLevel(4000)
    -- (as wide as its text, at least as "00.0, 00.0": the zoom buttons it
    -- once held are gone)
    local minW = math.ceil(UI.MeasureText("numeric", "00.0, 00.0"))
    status:SetSize(minW + 2 * S["space-4"], 26)
    status:SetPoint("BOTTOMLEFT", f.ScrollContainer or f, "BOTTOMLEFT", S["space-3"], S["space-3"])
    UI.Fill(status, "surface-glass"):SetAllPoints()
    UI.Border(status, "gilt-line")
    local coord = UI.Text(status, "numeric", "ink")
    coord:SetPoint("LEFT", S["space-4"], 0)
    local wait = 0
    status:SetScript("OnUpdate", function(_, elapsed)
        wait = wait - elapsed
        if wait > 0 then return end
        wait = 0.05
        local x, y, you
        -- the cursor's spot while it's over the map, over a pin too (the
        -- canvas loses the mouse focus to the pin: it read your position;
        -- found in game); yours off the map
        local over = f.ScrollContainer and f.ScrollContainer:IsMouseOver()
        if over then
            x, y = f:GetNormalizedCursorPosition()
            if not (x and y and x >= 0 and x <= 1 and y >= 0 and y <= 1) then x, y = nil, nil end
        end
        if not x then
            local pos = C_Map.GetPlayerMapPosition(f:GetMapID(), "player")
            if pos then x, y = pos:GetXY(); you = true end
        end
        if x and y and (x > 0 or y > 0) then
            local text = ("%.1f, %.1f"):format(x * 100, y * 100)
            local w = math.ceil(UI.MeasureText("numeric", text .. (you and "  you" or "")))
            coord:SetValue(text .. (you and "  |cff" .. T.color["ink-muted"].hex .. "you|r" or ""))
            status:SetWidth(math.max(minW, w) + 2 * S["space-4"])
            status:SetAlpha(1)
        else
            coord:SetValue("")
            status:SetAlpha(0)
        end
    end)
    chrome.status = status
    -- the window's size around the map's new top: windowed, shorter by the
    -- room the game kept over the map. Enlarged (the maximize button): the
    -- same window larger, in the screen's middle, the quest log beside it as
    -- you left it, the world around it seen and clickable (asked in game).
    -- The game's own fullscreen isn't used: its black backdrop
    -- blocks the world and it shows the map alone.
    local mm = b and b.MaximizeMinimizeFrame
    local rise = chrome.riseH or 0
    local function enlarged() return M:Get("mapEnlarged") end
    local function share()
        local wm = SuuUI.GetModule("worldmap")
        return ((wm and wm:Get("enlargedSize")) or 80) / 100
    end
    local function fit()
        if f.IsMaximized and f:IsMaximized() then return end
        local log = f.QuestLog and f.QuestLog:IsShown() and (f.questLogWidth or 0) or 0
        if not enlarged() then
            if f.minimizedWidth then f:SetWidth(f.minimizedWidth + log) end
            if f.minimizedHeight then f:SetHeight(f.minimizedHeight - CUT) end
            f:OnFrameSizeChanged()
            return
        end
        -- the map keeps the windowed map's shape; the window, header
        -- included, the setting's share of the screen's height, and narrower
        -- than the screen
        local w0, h0 = (f.minimizedWidth or 702) - 5, (f.minimizedHeight or 534) - GAME_MAP_TOP - 2
        local margin = S["space-3"]
        local mapH = UIParent:GetHeight() * share() - rise - MAP_TOP - 2
        local mapW = mapH * w0 / h0
        local roomW = UIParent:GetWidth() - 2 * margin - 5 - log
        if mapW > roomW then mapW, mapH = roomW, roomW * h0 / w0 end
        f:SetSize(math.floor(mapW + 5 + log), math.floor(mapH + MAP_TOP + 2))
        f:OnFrameSizeChanged()
    end
    local function setEnlarged(on)
        M:Set("mapEnlarged", on)
        if mm then if on then mm:SetMinimizedLook() else mm:SetMaximizedLook() end end
        fit()
        -- enlarged in the middle of the screen, small in the window row
        -- under the micro menu
        UI.CenterWindow(f, on)
    end
    if mm then
        -- the game minimizes on every open (to its own state): only the
        -- buttons' clicks change the size
        mm:SetOnMaximizedCallback(function() end)
        mm:SetOnMinimizedCallback(function() end)
        if mm.MaximizeButton then mm.MaximizeButton:HookScript("OnClick", function() setEnlarged(true) end) end
        if mm.MinimizeButton then mm.MinimizeButton:HookScript("OnClick", function() setEnlarged(false) end) end
    end
    -- the game's fullscreen, chosen before (its setting): enlarged instead
    if not GetCVarBool("miniWorldMap") then
        SetCVar("miniWorldMap", 1)
        M:Set("mapEnlarged", true)
    end
    hooksecurefunc(f, "Minimize", fit)
    if f.SetQuestLogPanelShown then hooksecurefunc(f, "SetQuestLogPanelShown", fit) end
    UI.CenterWindow(f, enlarged())
    f:HookScript("OnShow", function()
        if mm then if enlarged() then mm:SetMinimizedLook() else mm:SetMaximizedLook() end end
        fit()
    end)
    self:On("SUUUI_SETTING_CHANGED", function(_, namespace, key)
        if namespace == "worldmap" and key == "enlargedSize" and f:IsShown() then fit() end
    end)
    fit()
    self.worldMap = chrome
end

--------------------------------------------------------------------------------
-- The trainer window (3.6): restyled in place, the game's list and Train
-- (Blizzard_TrainerUI, loaded on demand); the trainer's name in the title.
--------------------------------------------------------------------------------

-- One service row after the game filled it: flat, a hairline under it, the
-- hover and the choice in SuuUI's colours, a 32px icon in an edge, the price
-- as SuuUI's money (ember digits while you can't afford it), and the name
-- and rank fitted again for SuuUI's type.
local function styleTrainerRow(b)
    if not b or not b.icon then return end
    if not b.suuRow then
        b.suuRow = true
        local n = b:GetNormalTexture()
        if n then n:SetAlpha(0) end
        if b.disabledBG then b.disabledBG:SetAlpha(0) end
        local hl = b:GetHighlightTexture()
        if hl then
            hl:SetColorTexture(UI.RGBA("surface-raised"))
            hl:SetBlendMode("BLEND")
            hl:SetAlpha(0.6)
        end
        if b.selectedTex then
            b.selectedTex:SetColorTexture(UI.RGBA("arcane-soft"))
            b.selectedTex:SetBlendMode("BLEND")
            b.selectedTex:ClearAllPoints()
            b.selectedTex:SetAllPoints()
        end
        b.suuRule = b:CreateTexture(nil, "ARTWORK")
        b.suuRule:SetColorTexture(UI.RGBA("gilt-faint"))
        b.suuRule:SetHeight(1)
        b.suuRule:SetPoint("BOTTOMLEFT", S["space-2"], 0)
        b.suuRule:SetPoint("BOTTOMRIGHT", -S["space-2"], 0)
        b.icon:SetSize(32, 32)
        b.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        b.suuIconEdge = CreateFrame("Frame", nil, b)
        b.suuIconEdge:SetAllPoints(b.icon)
        UI.Border(b.suuIconEdge, "gilt-hairline")
        if b.money then b.money:SetAlpha(0) end
        b.suuMoney = UI.Money(b)
        b.suuMoney:SetPoint("TOPRIGHT", -S["space-4"], -S["space-3"])
        -- the row's texts are styled here, once: the general pass leaves them
        -- (it chose a font by each text's length, so rows differed)
        SuuUI.Fonts.Apply(b.name, "label")
        SuuUI.Fonts.Apply(b.nameSubText, "caption")
        SuuUI.Fonts.Apply(b.subText, "caption")
        b.name:SetTextColor(UI.RGBA("ink"))
        b.nameSubText:SetTextColor(UI.RGBA("ink-muted"))
        b.subText:SetTextColor(UI.RGBA("ink-muted"))
        for _, fs in ipairs({ b.name, b.nameSubText, b.subText, b.alternateCost }) do
            fs.suuSkip = true
            fs:SetShadowOffset(0, 0)
        end
        if b.alternateCost then SuuUI.Fonts.Apply(b.alternateCost, "caption") end
        -- the requirements: one line under the name, to the row's right edge
        b.subText:ClearAllPoints()
        b.subText:SetPoint("TOPLEFT", b.name, "BOTTOMLEFT", 0, -4)
        b.subText:SetPoint("RIGHT", b, "RIGHT", -S["space-4"], 0)
        b.subText:SetHeight(14)
        b.subText:SetWordWrap(false)
        b.subText:SetJustifyV("TOP")
    end
    -- the price (the game's frame stays, see-through: it still reports its state)
    local cost = b.money and b.money:IsShown() and GetTrainerServiceCost and GetTrainerServiceCost(b:GetID())
    if cost and cost > 0 then
        b.suuMoney:SetCopper(cost)
        b.suuMoney.text:SetTextColor(UI.RGBA((GetMoney() or 0) >= cost and "ink" or "ember-text"))
        b.suuMoney:Show()
    else
        b.suuMoney:Hide()
    end
    -- name and rank in the room the price leaves
    local priceW = b.suuMoney:IsShown() and (b.suuMoney:GetWidth() + S["space-4"]) or 0
    local room = b:GetWidth() - (6 + 32 + 6) - priceW - S["space-4"]
    local nameW = math.max(1, math.min(b.name:GetUnboundedStringWidth(), room))
    b.name:SetWidth(nameW)
    local sub = b.nameSubText:GetText()
    local subRoom = room - nameW - 5
    if sub and sub ~= "" and subRoom > 8 then
        b.nameSubText:SetWordWrap(false)
        b.nameSubText:SetWidth(math.min(b.nameSubText:GetUnboundedStringWidth(), subRoom))
        b.nameSubText:Show()
    else
        b.nameSubText:Hide()
    end
end

-- A category row: its name as a SuuUI heading over a gilt-faint rule.
local function styleTrainerCategory(c)
    if not c or c.suuHead then return end
    c.suuHead = true
    for _, key in ipairs({ "LeftPiece", "RightPiece", "CenterPiece" }) do
        if c[key] then c[key]:SetAlpha(0) end
    end
    if c.Label then
        SuuUI.Fonts.Apply(c.Label, "header")
        c.Label:SetTextColor(UI.RGBA("gilt-text"))
    end
    if c.CollapseIcon then c.CollapseIcon:SetVertexColor(UI.RGBA("gilt-text")) end
    c.suuRule = c:CreateTexture(nil, "ARTWORK")
    c.suuRule:SetColorTexture(UI.RGBA("gilt-faint"))
    c.suuRule:SetHeight(1)
    c.suuRule:SetPoint("BOTTOMLEFT", S["space-2"], 1)
    c.suuRule:SetPoint("BOTTOMRIGHT", -S["space-2"], 1)
    -- the game sets its own fonts on hover: back to SuuUI's after
    c:HookScript("OnEnter", function() SuuUI.Fonts.Apply(c.Label, "header"); c.Label:SetTextColor(UI.RGBA("ink")) end)
    c:HookScript("OnLeave", function() SuuUI.Fonts.Apply(c.Label, "header"); c.Label:SetTextColor(UI.RGBA("gilt-text")) end)
end

function M:SkinTrainer()
    local f = _G.ClassTrainerFrame
    if not f or f.suuChrome then return end
    if _G.ClassTrainerFrame_InitServiceButton then
        hooksecurefunc("ClassTrainerFrame_InitServiceButton", function(b) styleTrainerRow(b) end)
    end
    if _G.ClassTrainerFrame_InitCategoryButton then
        hooksecurefunc("ClassTrainerFrame_InitCategoryButton", function(c) styleTrainerCategory(c) end)
    end
    -- a profession's next rank (Journeyman Blacksmith) sits over the list as
    -- a row of its own, filled by the list's update
    if _G.ClassTrainerFrame_Update then
        hooksecurefunc("ClassTrainerFrame_Update", function()
            local step = _G.ClassTrainerFrameSkillStepButton
            if step and step:IsShown() then styleTrainerRow(step) end
        end)
    end
    local chrome = UI.SkinWindow(f, {
        title = "Trainer", icon = "book", close = _G.ClassTrainerFrameCloseButton, topInset = 20, under = "microMenu",
        hide = { f.NineSlice, f.PortraitContainer, f.TitleContainer, f.Bg, f.TopTileStreaks,
                 _G.ClassTrainerFrameInset and _G.ClassTrainerFrameInset.NineSlice, _G.ClassTrainerFrameInsetBg,
                 _G.ClassTrainerFrameMoneyBg, _G.ClassTrainerFrameBottomInset },
    })
    -- the frame's own art away (SuuUI's glass stays)
    for _, region in ipairs({ f:GetRegions() }) do
        if region ~= chrome.bg and region.GetObjectType and region:GetObjectType() == "Texture" then region:SetAlpha(0) end
    end
    if f.ScrollBox then UI.ReskinScrollBox(f.ScrollBox) end
    if f.ScrollBar then UI.ReskinScrollBar(f.ScrollBar) end
    if _G.ClassTrainerStatusBar then UI.ReskinStatusBar(_G.ClassTrainerStatusBar) end
    if f.FilterDropdown then UI.ReskinDropdown(f.FilterDropdown) end
    if _G.ClassTrainerTrainButton then UI.ReskinButton(_G.ClassTrainerTrainButton) end
    -- your money in SuuUI's money at the foot, the game's away
    local money = f.money or _G.ClassTrainerFrameMoney
    if money then money:SetAlpha(0) end
    local mine = UI.Money(f)
    mine:SetPoint("BOTTOMLEFT", S["space-5"], 9)
    local function title()
        local name = UnitName("npc")
        if type(name) == "string" and name ~= "" then chrome:SetTitle(name) end
        UI.Reskin(f)
        mine:SetCopper(GetMoney() or 0)
    end
    f:HookScript("OnEvent", function(_, event) if event == "PLAYER_MONEY" or event == "TRAINER_UPDATE" then mine:SetCopper(GetMoney() or 0) end end)
    f:HookScript("OnShow", function() C_Timer.After(0, title) end)
    if f:IsShown() then title() end
    self.trainer = chrome
end

function M:SkinAll()
    self:SkinTrainer()
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
