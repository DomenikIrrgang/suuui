-- Units/RaidFrames.lua
-- Raid frames (step 1.9): up to forty unit frames, a secure group header per
-- raid group (1-8), so the game fills and re-sorts them in combat. A
-- built-in module written against the public API only.
--
-- One layout per profile (roles pick profiles, General > Profiles > By role):
--   groups as rows     each group a row of five, group 1 on top (the healer
--                      layout, centred between your frame and the target's)
--   groups as columns  each group a column of five, wrapping into bands (the
--                      side layout, bottom left above the chat)
-- Raids of 21-40 can use a shorter bar so the grid stays clear of the dock.
--
-- The headers make their buttons out of combat, all forty at once (the
-- startingIndex trick): aura containers can't be made in combat. Each button
-- is SuuUI's unit frame; the header sets its unit, the frame follows.
-- Inside the bar: role icon, name, the state badge at the row's end (debuff
-- types in combat too, as on the party frames), up to three aura icons at
-- the bar's right end (debuffs you can remove, externals, defensives, other
-- important debuffs; buffs come through buff indicators). Out of range fades
-- the frame.

local UI, T = SuuUI.UI, SuuUI.Tokens
local S = T.space

local M = SuuUI.RegisterModule({
    id = "raid",
    name = "Raid frames",
    description = "Your raid by group: health, roles, debuffs you can remove, aggro and range.",
    api = "0.9",
    reloadToToggle = true,
    defaults = {
        position = { point = "BOTTOMLEFT", x = 28, y = 300 },
        arrangement = "columns",   -- "columns" (side layout) or "rows" (healer layout)
        perBand = 4,               -- columns: groups side by side before the next band
        width = 108,
        height = 20,
        heightLarge = 20,          -- raids of 21-40
        gap = 4,
        groupGap = 4,
        showSolo = false,          -- your own frame while not in a group (to try them)
        power = "roles",
        healthText = "none",
        lowHealth = false,
        incoming = true,
        auras = 2,
        badges = "all",
        rangeAlpha = 0.42,
    },
})

local GROUPS = 8
local isSecret = issecretvalue or function() return false end
local HEALER_CLASS = { PRIEST = true, DRUID = true, PALADIN = true, SHAMAN = true }

local function powerFor(unit, A)
    A = A or _G
    local mode = M:Get("power")
    if mode == "all" then return true end
    if mode == "none" then return false end
    local role = A.UnitGroupRolesAssigned and A.UnitGroupRolesAssigned(unit)
    if role and not isSecret(role) and role ~= "NONE" then return role == "TANK" or role == "HEALER" end
    local _, class = A.UnitClass(unit)
    return class and not isSecret(class) and HEALER_CLASS[class] or false
end

-- The bar height for the raid's size: the shorter one from 21 players up.
local function barHeight()
    local n = GetNumGroupMembers and GetNumGroupMembers() or 0
    return (n > 20) and M:Get("heightLarge") or M:Get("height")
end

local function iconSize(h) return math.max(8, h - 6) end
local function auraReserve(h)
    local n = M:Get("auras")
    return n > 0 and (n * (iconSize(h) + S["space-1"]) + S["space-1"]) or 0
end

--------------------------------------------------------------------------------
-- A header's button, styled once when the header makes it
--------------------------------------------------------------------------------

local AURA_GROUPS = {
    { key = "dispel", filter = { "HARMFUL", "RAID_PLAYER_DISPELLABLE" }, dispel = true },
    { key = "external", filter = { "HELPFUL", "EXTERNAL_DEFENSIVE" } },
    { key = "defensive", filter = { "HELPFUL", "BIG_DEFENSIVE" } },
    -- buffs come only through buff indicators (you pick them): the game's
    -- "raid" buffs include Mark of the Wild and the like
    { key = "debuffs", filter = { "HARMFUL", "RAID", "!RAID_PLAYER_DISPELLABLE" }, dispel = true },
}

-- Up to three icons inside the bar's right end, growing left.
local function buildAuras(f, h)
    local groups = {}
    for i, g in ipairs(AURA_GROUPS) do
        groups[i] = { key = g.key, filter = g.filter, max = 3, dispel = g.dispel, drain = g.drain, digits = false }
    end
    -- the engine fills its groups in order; a clip frame as wide as the
    -- setting's icons cuts off the rest, so it is that many in total
    f.auraClip = CreateFrame("Frame", nil, f)
    f.auraClip:SetClipsChildren(true)
    f.auraClip:SetFrameLevel(f.over:GetFrameLevel() + 1)
    f.auras = UI.AuraContainer(f.auraClip, "none", { size = iconSize(h), spacing = S["space-1"], anchor = "TOPRIGHT", growth = { "LEFT", "DOWN" }, groups = groups })
    if f.auras then
        f.auras.container:SetPoint("TOPRIGHT", f.auraClip, "TOPRIGHT")
        M:ApplyAuraCount(f)
    end
end

local function buildSelected(f)
    local sel = CreateFrame("Frame", nil, f)
    sel:SetAllPoints()
    sel:SetFrameLevel(f:GetFrameLevel() + 10)
    UI.Border(sel, "arcane", { inset = 0 })
    sel:SetAlpha(0)
    f.selected = sel
end

function M:StyleButton(button)
    if button.suuStyled then return end
    button.suuStyled = true
    local h = barHeight()
    local f = UI.UnitFrame(nil, nil, {
        frame = button, size = "sm", width = self:Get("width"), height = h,
        powerFor = powerFor, textOnSmall = true, healthText = self:Get("healthText"),
        lowHealth = false, lowTint = self:Get("lowHealth"), incoming = self:Get("incoming"),
        reserveRight = auraReserve(h),
    })
    if not InCombatLockdown() then f:RegisterForClicks("AnyUp") end
    buildAuras(f, h)
    buildSelected(f)
    f:SetDispelBadges(self:Get("badges"))
    f:SetIndicators(UI.IndicatorsFor(UI.GroupIndicators(), UI.GroupTier()))
    self.buttons[#self.buttons + 1] = f
    -- the header sets the unit; the frame and its auras follow
    f:HookScript("OnAttributeChanged", function(btn, name, value)
        if name ~= "unit" then return end
        btn:SetUnit(value, true)
        if btn.auras then btn.auras:SetUnit(value or "none") end
        if value then
            if not btn.active then btn:Activate() end
            btn:Refresh()
            self:UpdateState(btn)
        end
    end)
    local unit = f:GetAttribute("unit")
    if unit then
        f:SetUnit(unit, true)
        if f.auras then f.auras:SetUnit(unit) end
        f:Activate()
    end
end

function M:ApplyAuraCount(f)
    local n = self:Get("auras")
    for _, g in ipairs(AURA_GROUPS) do f.auras:SetGroupMax(g.key, n) end
    -- the clip: n icons at the bar's right end, centred on its height
    local h = f:GetHeight()
    local size = iconSize(h)
    f.auraClip:ClearAllPoints()
    f.auraClip:SetPoint("RIGHT", f, "RIGHT", -S["space-1"] - 1, 0)
    f.auraClip:SetSize(math.max(1, n * size + math.max(0, n - 1) * S["space-1"]), size)
    f.auraClip:SetShown(n > 0)
end

--------------------------------------------------------------------------------
-- Headers
--------------------------------------------------------------------------------

-- Run by each header for each button it makes (restricted code): size and
-- click actions, then SuuUI's styling.
local INIT = [[
    local header = self:GetParent()
    self:SetWidth(header:GetAttribute("unitWidth"))
    self:SetHeight(header:GetAttribute("unitHeight"))
    self:SetAttribute("*type1", "target")
    self:SetAttribute("*type2", "togglemenu")
    header:CallMethod("SuuStyle", self:GetName())
]]

local function buildHeader(self, g)
    local h = CreateFrame("Frame", "SuuUIRaidGroup" .. g, self.holder, "SecureGroupHeaderTemplate")
    h:SetAttribute("template", "SecureUnitButtonTemplate")
    h:SetAttribute("templateType", "Button")
    h:SetAttribute("groupFilter", tostring(g))
    h:SetAttribute("showRaid", true)
    h:SetAttribute("showPlayer", true)
    h:SetAttribute("showParty", false)
    h:SetAttribute("sortMethod", "INDEX")
    h:SetAttribute("unitsPerColumn", 5)
    h:SetAttribute("maxColumns", 1)
    h:SetAttribute("initialConfigFunction", INIT)
    h.SuuStyle = function(_, name)
        local button = _G[name]
        if button then self:StyleButton(button) end
    end
    return h
end

-- All forty buttons now, out of combat: a header shows five slots from a
-- negative starting index, which makes its buttons; then back to normal.
local function precreate(self)
    self.holder:Show()
    for _, h in ipairs(self.headers) do
        h:SetAttribute("showSolo", true)
        h:SetAttribute("startingIndex", -4)
        h:Show()
        h:SetAttribute("startingIndex", 1)
        h:SetAttribute("showSolo", false)
    end
end

--------------------------------------------------------------------------------
-- Layout and options (out of combat)
--------------------------------------------------------------------------------

function M:Layout()
    local w, h, gap, groupGap = self:Get("width"), barHeight(), self:Get("gap"), self:Get("groupGap")
    local rows = self:Get("arrangement") == "rows"
    local perBand = math.max(1, self:Get("perBand"))
    for g, hd in ipairs(self.headers) do
        hd:SetAttribute("unitWidth", w)
        hd:SetAttribute("unitHeight", h)
        hd:ClearAllPoints()
        if rows then
            hd:SetAttribute("point", "LEFT")
            hd:SetAttribute("xOffset", gap)
            hd:SetAttribute("yOffset", 0)
            hd:SetPoint("TOPLEFT", self.holder, "TOPLEFT", 0, -(g - 1) * (h + groupGap))
        else
            hd:SetAttribute("point", "TOP")
            hd:SetAttribute("xOffset", 0)
            hd:SetAttribute("yOffset", -gap)
            local col, band = (g - 1) % perBand, math.floor((g - 1) / perBand)
            hd:SetPoint("TOPLEFT", self.holder, "TOPLEFT", col * (w + groupGap), -band * (5 * h + 4 * gap + groupGap * 2))
        end
    end
    if rows then
        self.holder:SetSize(5 * w + 4 * gap, GROUPS * h + (GROUPS - 1) * groupGap)
    else
        local bands = math.ceil(GROUPS / perBand)
        self.holder:SetSize(perBand * w + (perBand - 1) * groupGap, bands * (5 * h + 4 * gap) + (bands - 1) * groupGap * 2)
    end
    for _, f in ipairs(self.buttons) do
        f.opts.reserveRight = auraReserve(h)
        f:Resize(w, h)
        f:FitRow()
    end
    self.tierHeight = h
    self:DrawPreview()
end

function M:ApplyOptions()
    for _, f in ipairs(self.buttons) do
        f.opts.healthText = self:Get("healthText")
        f.opts.lowTint = self:Get("lowHealth")
        f.opts.incoming = self:Get("incoming")
        f.opts.reserveRight = auraReserve(f:GetHeight())
        if f.auras then self:ApplyAuraCount(f) end
        if f.active then f:Refresh() end
    end
    self:UpdateStates()
    self:UpdateRange()
end

function M:ApplyIndicators()
    self.indicatorTier = UI.GroupTier()
    local list = UI.IndicatorsFor(UI.GroupIndicators(), self.indicatorTier)
    for _, f in ipairs(self.buttons) do f:SetIndicators(list) end
end

function M:QueueIndicators()
    if self.indicatorTimer then self.indicatorTimer:Cancel() end
    self.indicatorTimer = C_Timer.NewTimer(1, function()
        self.indicatorTimer = nil
        self:RunOutOfCombat("indicators", function() self:ApplyIndicators() end)
    end)
end

function M:ApplyBadges()
    for _, f in ipairs(self.buttons) do f:SetDispelBadges(self:Get("badges")) end
end

function M:UpdateVisibility()
    self:RunOutOfCombat("visibility", function()
        RegisterStateDriver(self.holder, "visibility", "[group:raid] show; " .. (self:Get("showSolo") and "[nogroup] show; " or "") .. "hide")
        self.headers[1]:SetAttribute("showSolo", self:Get("showSolo"))
    end)
end

--------------------------------------------------------------------------------
-- States: aggro, your target, range
--------------------------------------------------------------------------------

function M:UpdateState(f)
    local u = f.unit
    if not u or not UnitExists(u) then return end
    local threat = UnitThreatSituation(u)
    local role = UnitGroupRolesAssigned and UnitGroupRolesAssigned(u)
    local aggro = not isSecret(threat) and threat ~= nil and threat >= 2 and not (not isSecret(role) and role == "TANK")
    f:SetState(aggro and "danger" or nil, aggro and "Aggro" or nil)
end

function M:UpdateStates()
    for _, f in ipairs(self.buttons) do self:UpdateState(f) end
end

function M:UpdateSelected()
    for _, f in ipairs(self.buttons) do
        local is = f.unit and UnitExists(f.unit) and UnitIsUnit(f.unit, "target")
        if isSecret(is) then f.selected:SetAlphaFromBoolean(is, 1, 0) else f.selected:SetAlpha(is and 1 or 0) end
    end
end

function M:UpdateRange()
    local far = self:Get("rangeAlpha")
    for _, f in ipairs(self.buttons) do
        if f:IsVisible() then
            if not f.unit or UnitIsUnit(f.unit, "player") == true then
                f:SetAlpha(1)
            else
                local inRange, checked = UnitInRange(f.unit)
                if isSecret(inRange) then
                    f:SetAlphaFromBoolean(inRange, 1, far)
                elseif checked == false then
                    f:SetAlpha(1)
                else
                    f:SetAlpha(inRange and 1 or far)
                end
            end
        end
    end
end

--------------------------------------------------------------------------------
-- The preview: a made-up raid (10, 20 or 40) in the settings window's
-- preview column, drawn by the same unit frames from stand-in data.
--------------------------------------------------------------------------------

local ROSTER = {
    { "Brannoc", "WARRIOR", "TANK" }, { "Ysolde", "PRIEST", "HEALER" }, { "Kaelith", "MAGE" }, { "Morrow", "ROGUE" }, { "Veyra", "SHAMAN", "HEALER" },
    { "Aldric", "PALADIN" }, { "Thessaly", "DRUID" }, { "Grimbolt", "WARLOCK" }, { "Sylva", "HUNTER" }, { "Oren", "PRIEST", "HEALER" },
    { "Hadrin", "WARRIOR", "TANK" }, { "Lisset", "MAGE" }, { "Corvane", "ROGUE" }, { "Tamsin", "DRUID" }, { "Eldra", "SHAMAN", "HEALER" },
    { "Vosk", "WARRIOR" }, { "Nimra", "PRIEST" }, { "Quell", "WARLOCK" }, { "Arlo", "HUNTER" }, { "Seraphe", "PALADIN", "HEALER" },
    { "Dagny", "WARRIOR" }, { "Fenn", "ROGUE" }, { "Ilsa", "MAGE" }, { "Rook", "HUNTER" }, { "Maelis", "PRIEST", "HEALER" },
    { "Torvald", "WARRIOR" }, { "Wren", "DRUID" }, { "Cassian", "MAGE" }, { "Ysra", "WARLOCK" }, { "Bellamy", "PALADIN", "HEALER" },
    { "Garrick", "ROGUE" }, { "Odessa", "SHAMAN", "HEALER" }, { "Pell", "HUNTER" }, { "Juna", "PRIEST", "HEALER" }, { "Thorne", "WARRIOR", "TANK" },
    { "Liora", "MAGE" }, { "Brask", "WARLOCK" }, { "Sefa", "DRUID" }, { "Halden", "PALADIN" }, { "Mirelle", "PRIEST", "HEALER" },
}
local HEALTH = { 64, 92, 31, 83, 88, 18, 100, 0, 76, 64, 97, 100, 58, 100, 91, 100, 85, 100, 72, 100,
                 44, 100, 100, 89, 100, 100, 67, 100, 100, 93, 100, 100, 81, 100, 100, 26, 100, 100, 100, 86 }
-- what makes the preview show every state: auras are spell textures with the
-- edge the engine would give them
local SPECIAL = {
    Brannoc = { incoming = 0.18, absorb = 0.1, auras = { { 871 } } },
    Kaelith = { aggro = true, incoming = 0.12, auras = { { 10060 } } },
    Morrow = { debuff = "Poison", auras = { { 2818, "dispel-poison" } } },
    Oren = { debuff = "Disease", removable = true, auras = { { 18278, "dispel-disease" } } },
    Grimbolt = { dead = true }, Sylva = { far = true }, Aldric = { aggro = true },
    Thessaly = { auras = { { 1022 } } }, Corvane = { incoming = 0.2 },
    Dagny = { absorb = 0.14 }, Nimra = { debuff = "Magic", removable = true, auras = { { 122, "dispel-magic" } } },
    Liora = { debuff = "Curse", auras = { { 980, "dispel-curse" } } },
    Ysolde = { selected = true, power = 0.14 },
}

local people = {}
local function person(unit)
    local i = tonumber(unit:match("^raidpreview(%d+)$")) or 1
    if not people[i] then
        local r = ROSTER[i]
        local d = { name = r[1], class = r[2], role = r[3] or "DAMAGER", health = HEALTH[i] / 100, max = 4200, power = 0.4 + (i * 13 % 60) / 100 }
        for k, v in pairs(SPECIAL[r[1]] or {}) do d[k] = v end
        if d.health == 0 then d.dead = true end
        people[i] = d
    end
    return people[i]
end

local STAND_IN = UI.UnitStandIn(person)

function M:PreviewView(parent)
    if self.previewView then
        self.previewView:SetParent(parent)
        self:DrawPreview(true)
        return self.previewView
    end
    local view = CreateFrame("Frame", nil, parent)
    view:SetSize(1, 1)
    self.previewView, self.previewFrames = view, {}
    for i = 1, 40 do
        local f = UI.UnitFrame(view, "raidpreview" .. i, { size = "sm", secure = false, api = STAND_IN, powerFor = powerFor, textOnSmall = true })
        f:SetScript("OnEnter", nil)
        f:SetScript("OnLeave", nil)
        f:EnableMouse(false)
        buildSelected(f)
        f.icons = {}
        for k = 1, 3 do
            local icon = UI.Icon(f.over, 12)
            icon:Hide()
            f.icons[k] = icon
        end
        f.dispelDecos = {}
        for _, kind in ipairs(UI.DEBUFF_TYPES) do
            local deco = f:DispelDecoration(f, kind)
            deco:Hide()
            f.dispelDecos[kind] = deco
        end
        self.previewFrames[i] = f
    end
    view:HookScript("OnShow", function() self:DrawPreview() end)
    self:DrawPreview(true)
    return view
end

function M:DrawPreview(force)
    if not self.previewView or not (force or self.previewView:IsVisible()) then return end
    local count = self.previewSize or 20
    local w, gap, groupGap = self:Get("width"), self:Get("gap"), self:Get("groupGap")
    local h = count > 20 and self:Get("heightLarge") or self:Get("height")
    local rows = self:Get("arrangement") == "rows"
    local perBand = math.max(1, self:Get("perBand"))
    local groups = math.ceil(count / 5)
    local size, far = iconSize(h), self:Get("rangeAlpha")
    local removableOnly = self:Get("badges") == "removable"
    local maxX, maxY = 0, 0
    for i, f in ipairs(self.previewFrames) do
        if i > count then
            f:Hide()
        else
            local g, slot = math.floor((i - 1) / 5) + 1, (i - 1) % 5
            local x, y
            if rows then
                x, y = slot * (w + gap), (g - 1) * (h + groupGap)
            else
                local col, band = (g - 1) % perBand, math.floor((g - 1) / perBand)
                x, y = col * (w + groupGap), band * (5 * h + 4 * gap + groupGap * 2) + slot * (h + gap)
            end
            f:ClearAllPoints()
            f:SetPoint("TOPLEFT", self.previewView, "TOPLEFT", x, -y)
            maxX, maxY = math.max(maxX, x + w), math.max(maxY, y + h)
            f.opts.healthText = self:Get("healthText")
            f.opts.lowTint = self:Get("lowHealth")
            f.opts.lowHealth = false
            f.opts.incoming = self:Get("incoming")
            f.opts.reserveRight = auraReserve(h)
            f:Resize(w, h)
            f:Refresh()
            local d = person("raidpreview" .. i)
            f:SetState(d.aggro and "danger" or nil, d.aggro and "Aggro" or nil)
            for kind, deco in pairs(f.dispelDecos) do
                deco:SetShown(d.debuff == kind and (d.removable or not removableOnly))
            end
            f:SetAlpha(d.far and far or 1)
            f.selected:SetAlpha(d.selected and 1 or 0)
            -- indicators on every third person, as if their auras were up
            local list, version = UI.GroupIndicators()
            local tier = UI.GroupTier(count)
            if f.indicatorVersion ~= version .. tier then
                f.indicatorVersion = version .. tier
                f:SetPreviewIndicators((i % 3 == 1) and UI.IndicatorsFor(list, tier) or nil)
            end
            local auras = d.auras or {}
            for k, icon in ipairs(f.icons) do
                local a = auras[k]
                if a and k <= self:Get("auras") then
                    icon:SetSize(size, size)
                    icon:SetArt(C_Spell.GetSpellTexture(a[1]))
                    icon:SetBorder(a[2])
                    icon:ClearAllPoints()
                    icon:SetPoint("RIGHT", f, "RIGHT", -(S["space-1"] + 1) - (k - 1) * (size + S["space-1"]), 0)
                    icon:Show()
                else
                    icon:Hide()
                end
            end
            f:Show()
        end
    end
    self.previewView:SetSize(math.max(1, maxX), math.max(1, maxY))
    if groups == 0 then self.previewView:SetSize(1, 1) end
end

--------------------------------------------------------------------------------
-- Settings
--------------------------------------------------------------------------------

local SECTION = {
    id = "raid", label = "Raid frames", category = "Frames", order = 13,
    preview = function(parent) return M:PreviewView(parent) end,
    groups = {
        { title = "Layout", description = "One layout per profile. Healers usually want groups as rows in the middle of the screen, tanks and DPS columns above the chat: make a profile for each and let SuuUI switch them with your role (General > Profiles > By role).", rows = {
            { label = "Preview", control = "segmented",
              options = { { value = 10, label = "10" }, { value = 20, label = "20" }, { value = 40, label = "40" } },
              description = "How many made-up people the preview shows.",
              get = function() return M.previewSize or 20 end,
              set = function(v) M.previewSize = v; M:DrawPreview(); return true end,
              isDefault = function() return (M.previewSize or 20) == 20 end,
              reset = function() M.previewSize = 20; M:DrawPreview() end },
            { key = "arrangement", label = "Groups", control = "segmented",
              options = { { value = "columns", label = "Columns" }, { value = "rows", label = "Rows" } },
              description = "Columns: each group a column of five (the side layout). Rows: each group a row of five, group 1 on top (the healer layout)." },
            { key = "perBand", label = "Columns side by side", control = "stepper", min = 1, max = 8, step = 1,
              description = "Then the next groups start a new band below. 4 keeps 40 players in two bands.",
              disabled = function() if M:Get("arrangement") ~= "columns" then return true, "Only for groups as columns." end end },
            { key = "width", label = "Width", control = "slider", min = 60, max = 200, step = 2, unit = "px", live = false },
            { key = "height", label = "Height", control = "slider", min = 14, max = 40, step = 1, unit = "px", live = false },
            { key = "heightLarge", label = "Height from 21 players", control = "slider", min = 14, max = 40, step = 1, unit = "px", live = false,
              description = "A shorter bar keeps a 40-player grid clear of the dock." },
            { key = "gap", label = "Gap", control = "slider", min = 0, max = 12, step = 1, unit = "px", live = false },
            { key = "groupGap", label = "Gap between groups", control = "slider", min = 0, max = 20, step = 1, unit = "px", live = false },
            { key = "showSolo", label = "Show when solo", control = "toggle",
              description = "Your own frame while you aren't in a group: to try the real frames. Move them in edit mode." },
        } },
        { title = "Inside the bar", rows = {
            { key = "power", label = "Power line", control = "segmented",
              options = { { value = "roles", label = "Tanks and healers" }, { value = "all", label = "Everyone" }, { value = "none", label = "None" } },
              description = "Without roles in the group, healing classes count as healers." },
            { key = "healthText", label = "Health text", control = "segmented",
              options = { { value = "none", label = "None" }, { value = "percent", label = "64%" }, { value = "value", label = "8.5k" } } },
            { key = "lowHealth", label = "Low-health tint", control = "toggle",
              description = "The empty part of the bar warms to ember from 70% down, strongest at 10%. Healers want it." },
            { key = "incoming", label = "Incoming heals and absorbs", control = "toggle" },
            { key = "auras", label = "Aura icons", control = "stepper", min = 0, max = 3, step = 1,
              description = "Inside the bar's right end, in order: debuffs you can remove, defensives on them, other important debuffs. Your heals over time and shields go in Buff indicators." },
        } },
        { title = "States", rows = {
            { key = "badges", label = "Debuff badges", control = "segmented",
              options = { { value = "all", label = "Every type" }, { value = "removable", label = "Only what you can remove" } },
              description = "Magic, Curse, Poison, Disease as a badge and border, in combat too. A debuff covers Aggro." },
            { key = "rangeAlpha", label = "Out of range", control = "slider", min = 0.2, max = 1, step = 0.05,
              format = function(v) return ("%d%%"):format(v * 100 + 0.5) end },
        } },
    },
}

--------------------------------------------------------------------------------
-- Lifecycle
--------------------------------------------------------------------------------

local function standDownBlizzard()
    if _G.CompactRaidFrameContainer then SuuUI.SuppressBlizzard("CompactRaidFrameContainer") end
end

function M:OnEnable()
    standDownBlizzard()
    if not self.holder then
        self.buttons = {}
        self.holder = CreateFrame("Frame", "SuuUIRaidFrames", SuuUI.Root, "SecureHandlerStateTemplate")
        self.holder:SetSize(1, 1)
        self.holder.suuManagedShow = true
        self.headers = {}
        for g = 1, GROUPS do self.headers[g] = buildHeader(self, g) end
    end
    self:RegisterMover(self.holder, { key = "position", label = "Raid frames" })
    SuuUI.PublishAnchor("raid", self.holder)
    self:RegisterSettings(SECTION)
    self:RunOutOfCombat("build", function()
        self:Layout()
        precreate(self)
        self:Layout()
        self:UpdateVisibility()
        self:ApplyOptions()
    end)

    for _, key in ipairs({ "arrangement", "perBand", "width", "height", "heightLarge", "gap", "groupGap", "auras" }) do
        self:Watch(key, function()
            self:DrawPreview()
            self:RunOutOfCombat("layout", function() self:Layout(); self:ApplyOptions() end)
        end)
    end
    for _, key in ipairs({ "power", "healthText", "lowHealth", "incoming", "rangeAlpha" }) do
        self:Watch(key, function() self:ApplyOptions(); self:DrawPreview() end)
    end
    self:Watch("badges", function()
        self:DrawPreview()
        self:RunOutOfCombat("badges", function() self:ApplyBadges() end)
    end)
    self:Watch("showSolo", function() self:UpdateVisibility() end)
    self:On("SUUUI_INDICATORS_CHANGED", function() self:QueueIndicators(); self:DrawPreview() end)

    self:OnGameEvent("PLAYER_TARGET_CHANGED", function() self:UpdateSelected() end)
    self:OnGameEvent("GROUP_ROSTER_UPDATE", function()
        -- a token can now be someone else: redraw, re-scan auras
        for _, f in ipairs(self.buttons) do
            if f.unit then
                if f.auras then f.auras:Refresh() end
                for _, list in pairs(f.dispelSets or {}) do for _, c in ipairs(list) do c:Refresh() end end
            end
        end
        self:UpdateStates(); self:UpdateSelected(); self:UpdateRange()
        -- someone changed raid group: "my group" missing looks follow
        for _, f in ipairs(self.buttons) do f:UpdateIndicatorPresence() end
        -- indicators limited to some group sizes
        if UI.GroupTier() ~= self.indicatorTier then self:QueueIndicators() end
        -- crossing 20 players changes the bar height (out of combat)
        if barHeight() ~= self.tierHeight then
            self:RunOutOfCombat("layout", function() self:Layout(); self:ApplyOptions() end)
        end
    end)
    self:OnGameEvent("UNIT_THREAT_SITUATION_UPDATE", function(_, unit)
        for _, f in ipairs(self.buttons) do if f.unit == unit then self:UpdateState(f) end end
    end)
    -- "while missing" indicators: read out of combat, hidden in combat
    local function presence(unit)
        for _, f in ipairs(self.buttons) do
            if not unit or f.unit == unit then f:UpdateIndicatorPresence() end
        end
    end
    self:OnGameEvent("UNIT_AURA", function(_, unit)
        if not InCombatLockdown() and unit and (unit == "player" or unit:find("^party") or unit:find("^raid")) then presence(unit) end
    end)
    self:OnGameEvent("PLAYER_REGEN_DISABLED", function() C_Timer.After(0, function() presence() end) end)
    self:OnGameEvent("PLAYER_REGEN_ENABLED", function() presence() end)
    self.rangeTicker = C_Timer.NewTicker(0.3, function()
        if self.holder:IsVisible() then self:UpdateRange() end
    end)
end

function M:OnDisable()
    -- Only reached when the module errors: the module toggles on reload.
    SuuUI.PublishAnchor("raid", nil)
    if self.rangeTicker then self.rangeTicker:Cancel() end
    for _, f in ipairs(self.buttons or {}) do f:Deactivate() end
end
