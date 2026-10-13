-- Units/CharacterWindow.lua
-- The Character window in SuuUI's look (step 3.1, design boards
-- "Character", "Window frame"): Blizzard's own window (Forever's, with its
-- mode tabs, left and right panes; probed 2026-10-13) restyled in place, so
-- equipping, the model, every tab and Escape stay Blizzard's.
--   3.1a: the shell: SuuUI's header (icon, title, key chip, close) and the
--         mode tabs as text tabs along the top, in the design's order
--         (Character, Reputation, Currency, Player vs. Player, Skills,
--         Statistics); Blizzard's metal frame, portrait and pane
--         backgrounds out of sight.
-- A built-in module written against the public API only.

local UI = SuuUI.UI

local M = SuuUI.RegisterModule({
    id = "character",
    name = "Character window",
    description = "The Character window (C) and its tabs in SuuUI's look.",
    api = "0.12",
    reloadToToggle = true,
    defaults = {},
})

-- Blizzard's mode tabs (CharacterFrameModeTab1-6) by the pane they open, in
-- the design's order.
local TABS = {
    { index = 1, pane = "PaperDollFrame", label = "Character", short = "Character" },
    { index = 2, pane = "ReputationFrame", label = "Reputation", short = "Reputation" },
    { index = 5, pane = "TokenFrame", label = "Currency", short = "Currency" },
    { index = 4, pane = "PVPRankFrame", label = "Player vs. Player", short = "PvP" },
    { index = 3, pane = "SkillsFrame", label = "Skills", short = "Skills" },
    { index = 6, pane = "StatisticsFrame", label = "Statistics", short = "Stats" },
}

local function shown(name)
    local f = _G[name]
    return f and f:IsShown() or false
end

function M:Skin()
    local cf = _G.CharacterFrame
    if not cf or self.chrome then return end
    -- the panes' own backgrounds (the first texture of each host)
    local hide = { cf.NineSlice, cf.PortraitContainer, cf.TitleContainer }
    for _, host in ipairs({ _G.CharacterFrameLeftPaneHost, _G.CharacterFrameRightPaneHost }) do
        if host then
            for _, r in ipairs({ host:GetRegions() }) do hide[#hide + 1] = r end
            -- the right pane's divider strip
            for _, c in ipairs({ host:GetChildren() }) do hide[#hide + 1] = c end
        end
    end
    self.chrome = UI.SkinWindow(cf, {
        title = "Character", icon = "person", binding = "TOGGLECHARACTER0",
        close = _G.CharacterFrameCloseButton, hide = hide, topInset = 20,
    })
    local list = {}
    for _, t in ipairs(TABS) do
        local button = _G["CharacterFrameModeTab" .. t.index]
        if button then
            list[#list + 1] = { button = button, label = t.label, short = t.short,
                selected = function()
                    if button.SelectedTexture then return button.SelectedTexture:IsShown() end
                    return shown(t.pane)
                end }
        end
    end
    self.chrome:SetTabs(list)
    -- a tab switched: the selected look follows
    hooksecurefunc("ToggleCharacter", function() if self.chrome then self.chrome:UpdateTabs() end end)
    cf:HookScript("OnShow", function() self.chrome:LayoutTabs() end)
end

function M:OnEnable()
    if _G.CharacterFrame then
        self:Skin()
    else
        -- the window's addon loads later on some clients
        self:OnGameEvent("ADDON_LOADED", function() if _G.CharacterFrame then self:Skin() end end)
    end
end
