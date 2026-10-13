-- Units/Tooltips.lua
-- Blizzard's tooltips in SuuUI's look (step 2.7, design board "Tooltips"):
-- the game tooltip, the compare tooltips and the item link tooltip on
-- surface-glass with a gilt edge and diamond, SuuUI's type (the title in
-- Marcellus, the lines in Figtree), at SuuUI's scale; a unit's name in its
-- class colour (players) or reaction (the rest); the health bar in the
-- unit fill. Where the game puts a tooltip with no owner of its own can be
-- SuuUI's: a place you move in edit mode, above the bags while they're open.
-- A built-in module written against the public API only.
--
-- Everything stays Blizzard's tooltip: its lines, its set functions, its
-- compare logic. SuuUI adds art, swaps the three tooltip fonts, and reads
-- the unit after TooltipDataProcessor's post call; nothing it reads may be
-- secret (a line's colour can be, even out of combat: probed 2026-10-13),
-- and a secret unit is left as Blizzard coloured it.
--
-- A group member's auras (step 2.7b): hovering a party or raid member (on
-- SuuUI's frames or in the world) lists their debuffs and buffs out of
-- combat, each with its icon and time left. In combat addon code can't read
-- auras at all (see the plan's client facts), so a small panel under the
-- tooltip shows them instead, drawn by the game's own aura container: icons
-- and timers, no names.

local UI, T = SuuUI.UI, SuuUI.Tokens

local M = SuuUI.RegisterModule({
    id = "tooltips",
    name = "Tooltips",
    description = "Blizzard's tooltips in SuuUI's look: art, type, name colours, where they open.",
    api = "0.12",
    reloadToToggle = true,
    defaults = {
        nameColors = true,
        groupAuras = true,
        anchor = "suuui", -- "suuui" (its own place, above the bags) or "blizzard"
        position = { point = "BOTTOMRIGHT", x = -28, y = 96 },
    },
})

local isSecret = issecretvalue or function() return false end
local function plain(v) return v ~= nil and not isSecret(v) end

local TOOLTIPS = { "GameTooltip", "ShoppingTooltip1", "ShoppingTooltip2", "ItemRefTooltip",
                   "ItemRefShoppingTooltip1", "ItemRefShoppingTooltip2" }

--------------------------------------------------------------------------------
-- Type and scale
--------------------------------------------------------------------------------

-- Blizzard's three tooltip fonts in SuuUI's styles: the title, the lines,
-- the small print.
local FONTS = { GameTooltipHeaderText = "unit-name-lg", GameTooltipText = "body", GameTooltipTextSmall = "caption" }

function M:ApplyFonts()
    for object, style in pairs(FONTS) do
        local font = _G[object]
        local s = T.type[style]
        if font and font.SetFont and s then font:SetFont(s.file, s.size, "") end
    end
end

-- The tooltips at SuuUI's scale (they live under UIParent; SuuUI's frames
-- under its pixel-perfect root), so type and edges match the rest.
function M:ApplyScale()
    local ui = UIParent:GetEffectiveScale()
    if not ui or ui == 0 then return end
    local scale = SuuUI.Root:GetEffectiveScale() / ui
    for _, name in ipairs(TOOLTIPS) do
        local tt = _G[name]
        if tt then tt:SetScale(scale) end
    end
end

--------------------------------------------------------------------------------
-- The unit's name and the health bar
--------------------------------------------------------------------------------

local function reactionToken(r)
    if r <= 3 then return "reaction-hostile" end
    if r == 4 then return "reaction-neutral" end
    return "reaction-friendly"
end

function M:ColorUnit(tooltip)
    if not self:Get("nameColors") or not tooltip.GetUnit then return end
    local ok, _, unit = pcall(tooltip.GetUnit, tooltip)
    if not ok or not plain(unit) or not unit then return end
    local token
    local isPlayer = UnitIsPlayer(unit)
    if not plain(isPlayer) then return end
    if isPlayer then
        local _, class = UnitClass(unit)
        if plain(class) and class then token = "class-" .. class:lower() end
    else
        local r = UnitReaction(unit, "player")
        if plain(r) and r then token = reactionToken(r) end
    end
    if not (token and T.color[token]) then return end
    local name = tooltip:GetName()
    local line = name and _G[name .. "TextLeft1"]
    if line then line:SetTextColor(UI.RGBA(token)) end
end

function M:SkinStatusBar()
    local bar = _G.GameTooltipStatusBar
    if not bar or self.barSkinned then return end
    self.barSkinned = true
    bar:SetStatusBarTexture("Interface\\Buttons\\WHITE8X8")
    bar:SetHeight(4)
    local track = bar:CreateTexture(nil, "BACKGROUND")
    track:SetColorTexture(UI.RGBA("surface-sunk"))
    track:SetAllPoints()
    local fill = { UI.RGBA("unit-fill") }
    bar:SetStatusBarColor(unpack(fill))
    local setting = false
    hooksecurefunc(bar, "SetStatusBarColor", function(b)
        if setting then return end
        setting = true
        b:SetStatusBarColor(unpack(fill))
        setting = false
    end)
end

--------------------------------------------------------------------------------
-- A group member's auras
--------------------------------------------------------------------------------

local MAX_LINES = 12
local PER_ROW = 8

local function groupUnit(unit)
    if type(unit) ~= "string" then return false end
    if unit:match("^party%d") or unit:match("^raid%d") then return true end
    return unit == "player" and IsInGroup()
end

local function timeLeft(a)
    local d, x = a.duration, a.expirationTime
    if not (plain(d) and plain(x)) or not d or d <= 0 or not x then return "" end
    local left = x - GetTime()
    if left <= 0 then return "" end
    if left < 60 then return ("%d"):format(left) end
    if left < 3600 then return ("%dm"):format(left / 60) end
    return ("%dh"):format(left / 3600)
end

-- Out of combat: the auras as lines (debuffs first, in ember), at most 12.
function M:AddAuraLines(tooltip, unit)
    local list = {}
    for _, filter in ipairs({ "HARMFUL", "HELPFUL" }) do
        for i = 1, 40 do
            local ok, a = pcall(C_UnitAuras.GetAuraDataByIndex, unit, i, filter)
            if not ok or not a then break end
            if plain(a.name) and a.name then list[#list + 1] = { a = a, harmful = filter == "HARMFUL" } end
        end
    end
    if #list == 0 then return end
    local ink, ember, muted = T.color["ink"], T.color["ember-text"], T.color["ink-muted"]
    tooltip:AddLine(" ")
    for i = 1, math.min(#list, MAX_LINES) do
        local a, harmful = list[i].a, list[i].harmful
        local icon = plain(a.icon) and a.icon and ("|T" .. a.icon .. ":0:0:0:0:64:64:5:59:5:59|t ") or ""
        local mine = plain(a.isFromPlayerOrPlayerPet) and a.isFromPlayerOrPlayerPet and not harmful
        local c = harmful and ember or ink
        local name = a.name .. (mine and (" |cff" .. muted.hex .. "(yours)|r") or "")
        local count = plain(a.applications) and a.applications and a.applications > 1 and (" ×" .. a.applications) or ""
        tooltip:AddDoubleLine(icon .. name .. count, timeLeft(a), c[1], c[2], c[3], muted[1], muted[2], muted[3])
    end
    if #list > MAX_LINES then
        tooltip:AddLine(("+%d more"):format(#list - MAX_LINES), muted[1], muted[2], muted[3])
    end
    tooltip:Show()
end

-- In combat: the game's aura container in a small panel under the tooltip.
function M:AuraPanel()
    if self.auraPanel then return self.auraPanel end
    local size = UI.Size("icon-md")
    local gap = T.space["space-2"]
    local w = PER_ROW * size + (PER_ROW - 1) * gap
    local p = UI.Panel(SuuUI.Root, { ornament = true, width = w + T.space["space-4"] * 2,
        height = 3 * size + 2 * gap + T.space["space-4"] * 2 + T.type.caption.lineHeight + T.space["space-2"] })
    p:SetFrameStrata("TOOLTIP")
    p:Hide()
    p.caption = UI.Text(p, "caption", "ink-muted")
    p.caption:SetPoint("TOPLEFT", T.space["space-4"], -T.space["space-4"])
    p.caption:SetValue("Auras")
    p.holder = CreateFrame("Frame", nil, p)
    p.holder:SetPoint("TOPLEFT", p.caption, "BOTTOMLEFT", 0, -T.space["space-2"])
    p.holder:SetSize(w, 3 * size + 2 * gap)
    p.auras = UI.AuraContainer(p.holder, "none", { size = "icon-md", spacing = gap, anchor = "TOPLEFT",
        growth = { "RIGHT", "DOWN" }, lineWidth = w,
        groups = {
            { key = "debuffs", filter = { "HARMFUL" }, max = PER_ROW, dispel = true },
            { key = "buffs", filter = { "HELPFUL" }, max = PER_ROW * 2 },
        } })
    if p.auras then p.auras.container:SetPoint("TOPLEFT", p.holder, "TOPLEFT") end
    self.auraPanel = p
    return p
end

function M:ShowAuraPanel(tooltip, unit)
    local p = self:AuraPanel()
    if not p.auras then return end
    p.auras:SetUnit(unit)
    p:ClearAllPoints()
    local bar = _G.GameTooltipStatusBar
    local below = (bar and bar:IsShown() and bar:GetParent() == tooltip) and bar or tooltip
    p:SetPoint("TOPLEFT", below, "BOTTOMLEFT", 0, -T.space["space-2"])
    p:Show()
    self.auraFor = tooltip
end

function M:HideAuraPanel()
    if self.auraPanel and self.auraPanel:IsShown() then
        self.auraPanel:Hide()
        if self.auraPanel.auras then self.auraPanel.auras:SetUnit("none") end
    end
    self.auraFor = nil
end

function M:GroupAuras(tooltip)
    if not self:Get("groupAuras") or tooltip ~= GameTooltip or not tooltip.GetUnit then return end
    local ok, _, unit = pcall(tooltip.GetUnit, tooltip)
    if not ok or not plain(unit) or not groupUnit(unit) then return end
    if InCombatLockdown() then
        self:ShowAuraPanel(tooltip, unit)
    else
        self:AddAuraLines(tooltip, unit)
    end
end

--------------------------------------------------------------------------------
-- Where a tooltip without an owner of its own opens
--------------------------------------------------------------------------------

function M:Anchor(tooltip)
    if self:Get("anchor") ~= "suuui" or tooltip ~= GameTooltip then return end
    tooltip:ClearAllPoints()
    local bags = _G.SuuUIBags
    if bags and bags:IsVisible() then
        tooltip:SetPoint("BOTTOMRIGHT", bags, "TOPRIGHT", 0, T.space["space-4"])
    else
        tooltip:SetPoint("BOTTOMRIGHT", self.anchorFrame, "BOTTOMRIGHT")
    end
end

--------------------------------------------------------------------------------
-- Settings
--------------------------------------------------------------------------------

local SECTION = {
    id = "tooltips", label = "Tooltips", category = "General", order = 24,
    groups = {
        { title = "Tooltips", description = "Blizzard's tooltips in SuuUI's look: items, spells, units and the compare tooltips. What they say stays the game's.", rows = {
            { key = "nameColors", label = "Name colours", control = "toggle",
              description = "A player's name in their class colour, everyone else's in hostile, neutral or friendly." },
            { key = "groupAuras", label = "Group members' auras", control = "toggle",
              description = "Hovering a party or raid member lists their debuffs and buffs with the time left. In combat the game lets SuuUI show them only as icons: a small panel under the tooltip." },
            { key = "anchor", label = "Where they open", control = "segmented",
              options = { { value = "suuui", label = "SuuUI's place" }, { value = "blizzard", label = "Blizzard's" } },
              description = "For tooltips with no place of their own (the world, units). SuuUI's place: bottom right, above your bags while they're open; move it in edit mode." },
        } },
    },
}

--------------------------------------------------------------------------------
-- Lifecycle
--------------------------------------------------------------------------------

function M:OnEnable()
    for _, name in ipairs(TOOLTIPS) do
        if _G[name] then UI.SkinTooltip(_G[name]) end
    end
    self:ApplyFonts()
    self:ApplyScale()
    self:SkinStatusBar()
    if not self.anchorFrame then
        -- the place edit mode moves (tooltips open from its bottom right)
        self.anchorFrame = CreateFrame("Frame", "SuuUITooltipAnchor", SuuUI.Root)
        self.anchorFrame:SetSize(220, 90)
    end
    self:RegisterMover(self.anchorFrame, { key = "position", label = "Tooltips" })
    self:RegisterSettings(SECTION)
    if not self.hooked then
        self.hooked = true
        if TooltipDataProcessor and TooltipDataProcessor.AddTooltipPostCall and Enum.TooltipDataType then
            TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Unit, function(tooltip)
                if not self:IsEnabled() then return end
                pcall(self.ColorUnit, self, tooltip)
                self:Guard(self.GroupAuras)(self, tooltip)
            end)
        end
        GameTooltip:HookScript("OnHide", function() self:HideAuraPanel() end)
        -- another unit (or no unit) on the same tooltip: the panel goes
        GameTooltip:HookScript("OnTooltipCleared", function() self:HideAuraPanel() end)
        if type(GameTooltip_SetDefaultAnchor) == "function" then
            hooksecurefunc("GameTooltip_SetDefaultAnchor", function(tooltip)
                if self:IsEnabled() then self:Anchor(tooltip) end
            end)
        end
    end
    -- the aura panel's container made out of combat, ready for a fight
    if not InCombatLockdown() then self:AuraPanel() end
    for _, e in ipairs({ "UI_SCALE_CHANGED", "DISPLAY_SIZE_CHANGED" }) do
        self:OnGameEvent(e, function() C_Timer.After(0, function() self:ApplyScale() end) end)
    end
    self:On("SUUUI_ROOT_SCALED", function() self:ApplyScale() end)
end
