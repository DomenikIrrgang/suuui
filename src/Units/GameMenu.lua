-- Units/GameMenu.lua
-- SuuUI's own game menu (plan 3.7, design component GameMenu): Esc shows a
-- compact panel in the middle of a dimmed screen. Return to Game first, then
-- Game (Options, Edit Mode, Macros, AddOns, SuuUI settings), Help (Support)
-- and Session (Reload UI, Log Out, Exit Game); a light info line at the
-- foot. Options and Edit Mode stay the game's own windows (decided
-- 2026-10-17); Macros and AddOns open what is open for them (SuuUI's own
-- when those modules are on).
-- Esc stays the game's: its GameMenuFrame still opens and closes on Esc,
-- out of sight, and this panel shows and hides with it. Opening each entry
-- from SuuUI's code taints nothing (/suu probe gamemenu, 2026-10-17).
-- A built-in module written against the public API only.

local UI, T = SuuUI.UI, SuuUI.Tokens
local S = T.space

local M = SuuUI.RegisterModule({
    id = "gamemenu",
    name = "Game menu",
    description = "SuuUI's game menu (Esc): Return to Game, the game's windows, Reload UI, Log Out and Exit Game in one compact panel.",
    api = "0.17",
    reloadToToggle = true,
    defaults = {},
})

local function call(fn, ...)
    if type(fn) ~= "function" then return nil end
    local ok, a, b, c, d = pcall(fn, ...)
    if ok then return a, b, c, d end
end

local WIDTH = 300
local ITEM_H = 30
local GLYPHS = "Interface\\AddOns\\SuuUI\\Media\\Textures\\Glyphs\\"

-- Closes the game's menu (this panel follows), then does what was chosen.
local function closeThen(fn, sound)
    return function()
        PlaySound(sound or SOUNDKIT.IG_MAINMENU_OPTION)
        if GameMenuFrame:IsShown() then HideUIPanel(GameMenuFrame) end
        if fn then fn() end
    end
end

local function exitBlocked()
    if StaticPopup_Visible and (StaticPopup_Visible("CAMP") or StaticPopup_Visible("QUIT")) then
        return "Already on the way out"
    end
end

local GROUPS = {
    { "Game", {
        { "Options", "gear", closeThen(function() SettingsPanel:Open() end) },
        { "Edit Mode", "pushpin", closeThen(function() ShowUIPanel(EditModeManagerFrame) end),
            function()
                if InCombatLockdown() then return "Not in combat" end
                if EditModeManagerFrame and EditModeManagerFrame.CanEnterEditMode and not EditModeManagerFrame:CanEnterEditMode() then
                    return "Not available right now"
                end
            end },
        { "Macros", "scroll", closeThen(function() ShowMacroFrame() end) },
        { "AddOns", "menu", closeThen(function() ShowUIPanel(AddonList) end) },
        { "SuuUI settings", "markDiamond", closeThen(function() SuuUI.OpenSettings() end) },
    } },
    { "Help", {
        { "Support", "chat", closeThen(function() ToggleHelpFrame() end) },
    } },
    { "Session", {
        { "Reload UI", "reset", closeThen(function() C_UI.Reload() end) },
        { "Log Out", "door", closeThen(Logout, SOUNDKIT.IG_MAINMENU_LOGOUT), exitBlocked },
        { "Exit Game", "close", closeThen(Quit, SOUNDKIT.IG_MAINMENU_QUIT), exitBlocked },
    } },
}

--------------------------------------------------------------------------------
-- The panel
--------------------------------------------------------------------------------

function M:BuildItem(parent, def)
    local b = CreateFrame("Button", nil, parent)
    b:SetHeight(ITEM_H)
    b.hover = UI.Fill(b, "surface-raised", "BACKGROUND")
    b.hover:SetAllPoints()
    b.hover:Hide()
    b.glyph = b:CreateTexture(nil, "ARTWORK")
    b.glyph:SetSize(14, 14)
    b.glyph:SetPoint("LEFT", S["space-4"], 0)
    b.glyph:SetTexture(GLYPHS .. def[2])
    b.glyph:SetVertexColor(UI.RGBA("ink-muted"))
    b.label = UI.Text(b, "label", "ink")
    b.label:SetPoint("LEFT", b.glyph, "RIGHT", S["space-4"], 0)
    b.label:SetValue(def[1])
    b.why = def[4]
    b:SetScript("OnEnter", function(self)
        self.hover:Show()
        if not self.blocked then self.glyph:SetVertexColor(UI.RGBA("gilt-text")) end
        if self.blocked then UI.ShowTooltip(self, { title = def[1], description = self.blocked }) end
    end)
    b:SetScript("OnLeave", function(self)
        self.hover:Hide()
        self.glyph:SetVertexColor(UI.RGBA("ink-muted"))
        UI.HideTooltip()
    end)
    b:SetScript("OnClick", function(self)
        if self.blocked then return end
        UI.HideTooltip()
        def[3]()
    end)
    return b
end

function M:Build()
    -- the dimmed screen under it
    local dim = CreateFrame("Frame", nil, SuuUI.Root)
    dim:SetAllPoints(UIParent)
    dim:SetFrameStrata("DIALOG")
    dim:EnableMouse(true)
    local shade = dim:CreateTexture(nil, "BACKGROUND")
    shade:SetAllPoints()
    shade:SetColorTexture(0, 0, 0, 0.55)
    dim:Hide()
    self.dim = dim

    local p = UI.Panel(dim, { title = "Game Menu", keybind = "Esc", width = WIDTH, ornament = true, solid = true })
    p:SetPoint("CENTER", UIParent, "CENTER", 0, 40)
    p:SetFrameLevel(dim:GetFrameLevel() + 5)
    self.panel = p
    local body = p.body
    local y = 0
    local back = UI.Button(body, { text = "Return to Game", variant = "primary", onClick = closeThen(nil, SOUNDKIT.IG_MAINMENU_CONTINUE) })
    back:SetHeight(34)
    back:SetPoint("TOPLEFT")
    back:SetPoint("TOPRIGHT")
    y = y + 34 + S["space-5"]
    self.items = {}
    for _, g in ipairs(GROUPS) do
        local label = UI.Text(body, "caption", "ink-faint")
        label:SetPoint("TOPLEFT", S["space-3"], -y)
        label:SetValue(g[1])
        y = y + T.type.caption.lineHeight + S["space-2"]
        for _, def in ipairs(g[2]) do
            local b = self:BuildItem(body, def)
            b:SetPoint("TOPLEFT", 0, -y)
            b:SetPoint("RIGHT")
            self.items[#self.items + 1] = b
            y = y + ITEM_H + 1
        end
        y = y + S["space-5"] - 1
    end
    -- the info line: who and where, frame rate and latency
    local rule = UI.Fill(body, "gilt-faint", "ARTWORK")
    rule:SetPoint("TOPLEFT", 0, -y)
    rule:SetPoint("TOPRIGHT", 0, -y)
    rule:SetHeight(1)
    y = y + 1 + S["space-4"]
    self.who = UI.Text(body, "caption", "ink-muted")
    self.who:SetPoint("TOPLEFT", 0, -y)
    self.perf = UI.Text(body, "caption", "ink-faint")
    self.perf:SetPoint("TOPRIGHT", 0, -y)
    y = y + T.type.caption.lineHeight
    body:SetSize(WIDTH - 2 * S["space-5"], y)
    p:Fit()
end

function M:Draw()
    for _, b in ipairs(self.items) do
        b.blocked = b.why and b.why() or nil
        b:SetAlpha(b.blocked and 0.45 or 1)
    end
    local name, realm = UnitFullName("player")
    self.who:SetValue((name or "") .. ((realm and realm ~= "") and (" · " .. realm) or ""))
    self:DrawPerf()
end

function M:DrawPerf()
    local fps = math.floor((GetFramerate() or 0) + 0.5)
    local _, _, home, world = GetNetStats()
    self.perf:SetValue(("%d fps · %d ms"):format(fps, world or home or 0))
end

--------------------------------------------------------------------------------
-- With the game's menu
--------------------------------------------------------------------------------

function M:Away(frame)
    if self.away then return end
    self.away = true
    local placing = false
    local function away()
        if not self:IsEnabled() then return end
        placing = true
        frame:SetAlpha(0)
        frame:ClearAllPoints()
        frame:SetPoint("TOPLEFT", UIParent, "TOPRIGHT", 5000, 0)
        placing = false
    end
    away()
    hooksecurefunc(frame, "SetPoint", function() if not placing then C_Timer.After(0, away) end end)
end

function M:OnEnable()
    local g = _G.GameMenuFrame
    if not g then return end
    if not self.panel then self:Build() end
    self:Away(g)
    g:HookScript("OnShow", function()
        if not self:IsEnabled() then return end
        self:Away(g)
        self:Draw()
        self.dim:Show()
        if not self.ticker then
            self.ticker = C_Timer.NewTicker(1, function() if self.dim:IsShown() then self:DrawPerf() end end)
        end
    end)
    g:HookScript("OnHide", function()
        self.dim:Hide()
        if self.ticker then self.ticker:Cancel(); self.ticker = nil end
    end)
    for _, e in ipairs({ "PLAYER_REGEN_DISABLED", "PLAYER_REGEN_ENABLED" }) do
        self:OnGameEvent(e, function() if self.dim:IsShown() then self:Draw() end end)
    end
end

function M:OnDisable()
    if self.dim then self.dim:Hide() end
end
