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
    for _, t in ipairs({ { f.ChatTab, "Chat" }, { f.RosterTab, "Roster" }, { f.GuildInfoTab, "Info" } }) do
        local b = t[1]
        if b then
            tabs[#tabs + 1] = { button = b, label = t[2], short = t[2],
                                selected = function() return b.GetChecked and b:GetChecked() or false end }
            b:HookScript("OnClick", function() C_Timer.After(0, function() chrome:UpdateTabs() end) end)
        end
    end
    if #tabs > 0 then chrome:SetTabs(tabs) end
    -- the play-style and benefits tabs out of sight
    for _, b in ipairs({ f.GuildPreferredPlaySettingsTab, f.GuildBenefitsTab }) do
        if b then
            b:SetAlpha(0)
            b:EnableMouse(false)
        end
    end
    if f.SetDisplayMode then hooksecurefunc(f, "SetDisplayMode", function() chrome:UpdateTabs() end) end
    f:HookScript("OnShow", function() C_Timer.After(0, function() chrome:UpdateTabs() end) end)
    self.communities = chrome
end

function M:SkinAll()
    self:SkinSpells()
    self:SkinLegacy()
    self:SkinProfessions()
    self:SkinFriends()
    self:SkinSocial()
    self:SkinCommunities()
end

function M:OnEnable()
    self:SkinAll()
    -- their addons load on demand
    self:OnGameEvent("ADDON_LOADED", function() self:SkinAll() end)
    -- the spells window is protected: skinned after combat if it loaded during one
    self:OnGameEvent("PLAYER_REGEN_ENABLED", function() self:SkinAll() end)
end
