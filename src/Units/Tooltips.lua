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
        ids = true,           -- spell IDs, and who cast a buff or debuff
        anchor = "suuui", -- "suuui" (its own place, above the bags) or "blizzard"
        unitMenus = true, -- the game's right-click menus on units in SuuUI's look
        position = { point = "BOTTOMRIGHT", x = -30, y = 260 },
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
        -- yours: you (or your pet) cast it (isFromPlayerOrPlayerPet is true for
        -- every aura on you, found in game)
        local src = a.sourceUnit
        local mine = not harmful and plain(src) and src ~= nil and (UnitIsUnit(src, "player") or UnitIsUnit(src, "pet"))
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
-- Any of Blizzard's tooltips, the first time it shows something
--------------------------------------------------------------------------------

-- Tooltips SuuUI doesn't know by name (the aura buttons' own one, an
-- addon's) get the look the first time they show the game's data.
function M:SkinAny(tooltip)
    if UI.IsTooltipSkinned(tooltip) then return end
    if tooltip.IsForbidden and tooltip:IsForbidden() then return end
    if tooltip.GetObjectType and tooltip:GetObjectType() ~= "GameTooltip" then return end
    local name = tooltip:GetName()
    -- a tooltip inside another one keeps its host's look
    if name and name:find("Embedded") then return end
    UI.SkinTooltip(tooltip)
    local ui = UIParent:GetEffectiveScale()
    if ui and ui > 0 and tooltip:GetParent() == UIParent then
        tooltip:SetScale(SuuUI.Root:GetEffectiveScale() / ui)
    end
end

--------------------------------------------------------------------------------
-- The aura buttons' own tooltip
--------------------------------------------------------------------------------

-- The game's aura buttons (buffs, the target's, party and raid auras) show
-- a tooltip of the engine's that addon code can't touch; the engine takes a
-- style for it instead (AuraContainerInbound.SetTooltipBackdrop, its options
-- from the client's API documentation, 2026-10-13): surface-glass inside a
-- 1px gilt-line edge. Its text stays the game's (no spell ID there).
function M:StyleAuraTooltip()
    local inbound = _G.AuraContainerInbound
    if not (inbound and inbound.SetTooltipBackdrop and CreateColor) then return end
    -- one physical pixel in UIParent units
    local h = select(2, GetPhysicalScreenSize())
    local scale = UIParent:GetEffectiveScale()
    local px = (h and h > 0 and scale > 0) and (768 / h / scale) or 1
    local bg, edge = { UI.RGBA("surface-glass") }, { UI.RGBA("gilt-line") }
    local ok, err = pcall(inbound.SetTooltipBackdrop, {
        backdropInfo = {
            bgFile = "Interface\\Buttons\\WHITE8X8",
            edgeFile = "Interface\\Buttons\\WHITE8X8",
            edgeSize = px,
            insets = { left = px, right = px, top = px, bottom = px },
        },
        centerColor = CreateColor(unpack(bg)),
        borderColor = CreateColor(unpack(edge)),
    })
    if not ok then self:Print("couldn't style the aura tooltips: " .. tostring(err)) end
end

--------------------------------------------------------------------------------
-- Spell IDs, and who cast an aura
--------------------------------------------------------------------------------

function M:AddSpellID(tooltip, data)
    if not self:Get("ids") then return end
    local id = data and data.id
    if not plain(id) or type(id) ~= "number" then return end
    local m = T.color["ink-faint"]
    tooltip:AddDoubleLine("Spell ID", tostring(id), m[1], m[2], m[3], m[1], m[2], m[3])
    tooltip:Show()
end

-- After SetUnitAura & co: "From" and the caster in their class colour.
function M:AddSource(tooltip, unit, auraInstanceID, index, filter)
    if not self:Get("ids") then return end
    if not plain(unit) or not unit then return end
    local ok, a
    if auraInstanceID then
        ok, a = pcall(C_UnitAuras.GetAuraDataByAuraInstanceID, unit, auraInstanceID)
    else
        ok, a = pcall(C_UnitAuras.GetAuraDataByIndex, unit, index, filter)
    end
    if not ok or not a then return end
    local src = a.sourceUnit
    if not plain(src) or not src then return end
    local name = UnitName(src)
    if not plain(name) or not name then return end
    local color = T.color["ink"]
    if UI.Flag(UnitIsPlayer(src)) then
        local _, class = UnitClass(src)
        if plain(class) and class and T.color["class-" .. class:lower()] then color = T.color["class-" .. class:lower()] end
    end
    if UI.Flag(UnitIsUnit(src, "player")) then name = name .. " (you)" end
    local m = T.color["ink-faint"]
    tooltip:AddDoubleLine("From", name, m[1], m[2], m[3], color[1], color[2], color[3])
    tooltip:Show()
end

function M:HookAuraSources()
    local api = getmetatable(GameTooltip)
    api = api and api.__index
    if type(api) ~= "table" then return end
    local function hook(method, byID, defaultFilter)
        if type(api[method]) ~= "function" then return end
        hooksecurefunc(api, method, function(tooltip, unit, a2, a3)
            if not self:IsEnabled() or (tooltip.IsForbidden and tooltip:IsForbidden()) then return end
            if byID then
                self:Guard(self.AddSource)(self, tooltip, unit, a2)
            else
                self:Guard(self.AddSource)(self, tooltip, unit, nil, a2, a3 or defaultFilter)
            end
        end)
    end
    hook("SetUnitAura", false, "HELPFUL")
    hook("SetUnitBuff", false, "HELPFUL")
    hook("SetUnitDebuff", false, "HARMFUL")
    hook("SetUnitBuffByAuraInstanceID", true)
    hook("SetUnitDebuffByAuraInstanceID", true)
    hook("SetUnitAuraByAuraInstanceID", true)
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
            { key = "ids", label = "Spell IDs and casters", control = "toggle",
              description = "A spell's or ability's ID at the foot of its tooltip; on a buff or debuff also who cast it, in their class colour." },
            { key = "unitMenus", label = "Unit menus", control = "toggle",
              description = "The game's right-click menu on a unit (you, your target, party and raid members, players in the world) in SuuUI's look; its choices stay the game's." },
            { key = "anchor", label = "Where they open", control = "segmented",
              options = { { value = "suuui", label = "SuuUI's place" }, { value = "blizzard", label = "Blizzard's" } },
              description = "For tooltips with no place of their own (the world, units). SuuUI's place: bottom right, above your bags while they're open; move it in edit mode." },
        } },
    },
}

--------------------------------------------------------------------------------
-- Lifecycle
--------------------------------------------------------------------------------

-- The game's unit menus (UnitPopupManager:OpenMenu, every "MENU_UNIT_…"
-- menu: you, your target, party, raid, players in the world) in SuuUI's
-- look: hooked after the game opened one, so its choices stay the game's.
-- Its submenus follow (UI.ReskinMenu restyles the menus a restyled one opens).
function M:HookUnitMenus()
    local mgr = _G.UnitPopupManager
    if self.unitMenusHooked or not (mgr and mgr.OpenMenu) then return end
    self.unitMenusHooked = true
    hooksecurefunc(mgr, "OpenMenu", function()
        if not (self:IsEnabled() and self:Get("unitMenus")) then return end
        local manager = Menu and Menu.GetManager and Menu.GetManager()
        local menu = manager and manager.GetOpenMenu and manager:GetOpenMenu()
        if not menu then return end
        UI.ReskinMenu(menu)
        -- its rows may come a frame later
        C_Timer.After(0, function() if menu:IsShown() then UI.ReskinMenu(menu) end end)
    end)
end

function M:OnEnable()
    for _, name in ipairs(TOOLTIPS) do
        if _G[name] then UI.SkinTooltip(_G[name]) end
    end
    self:HookUnitMenus()
    self:OnGameEvent("ADDON_LOADED", function() self:HookUnitMenus() end)
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
            TooltipDataProcessor.AddTooltipPostCall(TooltipDataProcessor.AllTypes or "ALL", function(tooltip)
                if self:IsEnabled() then pcall(self.SkinAny, self, tooltip) end
            end)
            for _, kind in ipairs({ Enum.TooltipDataType.Spell, Enum.TooltipDataType.UnitAura }) do
                if kind then
                    TooltipDataProcessor.AddTooltipPostCall(kind, function(tooltip, data)
                        if self:IsEnabled() then self:Guard(self.AddSpellID)(self, tooltip, data) end
                    end)
                end
            end
            self:HookAuraSources()
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
    self:StyleAuraTooltip()
    -- the aura panel's container made out of combat, ready for a fight
    if not InCombatLockdown() then self:AuraPanel() end
    for _, e in ipairs({ "UI_SCALE_CHANGED", "DISPLAY_SIZE_CHANGED" }) do
        self:OnGameEvent(e, function() C_Timer.After(0, function() self:ApplyScale(); self:StyleAuraTooltip() end) end)
    end
    self:On("SUUUI_ROOT_SCALED", function() self:ApplyScale() end)
end
