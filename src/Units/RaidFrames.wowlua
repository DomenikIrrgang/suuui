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
        sort = "group",            -- within each group: "group" (raid order) or "role"
        perBand = 4,               -- columns: groups side by side before the next band
        width = 108,
        height = 19,
        heightLarge = 20,          -- raids of 21-40
        gap = 8,
        groupGap = 4,
        showSolo = false,          -- your own frame while not in a group (to try them)
        power = "roles",
        healthText = "none",
        nameColor = "game",        -- "game" (class colour) or "ink", as on the unit frames
        raidMarkers = true,
        lowHealth = true,
        incoming = true,
        buffIcons = 1,             -- defensives (the Defensives list), inside the bar's right end
        debuffIcons = 2,           -- debuffs at the very end, the ones you can remove first
        debuffBadges = "all",      -- "all" debuff types, "removable" or "off"
        rangeAlpha = 0.25,
    },
})

-- "badges" is "debuffBadges" now, as on the unit frames
-- one aura count became defensives and debuffs, each with its own; they
-- start at the new defaults
M:Migrate("auraSplit", function(values) values.auras = nil end)

M:Migrate("debuffBadges", function(values)
    if values.badges ~= nil and values.debuffBadges == nil then values.debuffBadges = values.badges end
    values.badges = nil
end)

local GROUPS = 8
local isSecret = issecretvalue or function() return false end
local HEALER_CLASS = { PRIEST = true, DRUID = true, PALADIN = true, SHAMAN = true }

local function powerFor(unit, A)
    A = A or _G
    local mode = M:Get("power")
    if mode == "all" then return true end
    if mode == "none" then return false end
    local role = A.UnitGroupRolesAssigned and A.UnitGroupRolesAssigned(unit)
    if not isSecret(role) and role and role ~= "NONE" then return role == "TANK" or role == "HEALER" end
    local _, class = A.UnitClass(unit)
    return not isSecret(class) and class and HEALER_CLASS[class] or false
end

-- The bar height for the raid's size: the shorter one from 21 players up.
local function barHeight()
    local n = GetNumGroupMembers and GetNumGroupMembers() or 0
    return (n > 20) and M:Get("heightLarge") or M:Get("height")
end

local function iconSize(h) return math.max(8, h - 6) end

-- Inside the bar's right end, one row the engine lays out leftward:
-- debuffs at the very end (the ones you can remove first), then right before
-- them however many defensives show (the Defensives list's spells, Frames ›
-- Defensives: the game hides who cast another player's buffs, and its own
-- defensive filters then let every buff through), `space-2` apart. On your
-- own frame the debuffs you can remove come first; on everyone else's
-- they're one list (the game hides who cast another player's auras, and
-- those then pass both "removable" and "not removable": each showed twice).
local GAP_SETS = S["space-2"]
-- The first group serves whoever the frame shows (its filter follows: the
-- debuffs you can remove on yours, all of them on everyone else's), so a
-- frame keeps two groups (the engine makes ten buttons for each, whatever
-- its count) and the second, your other debuffs, comes only on a frame
-- that has shown you.
local AURA_GROUPS = {
    { key = "debuffs", set = "debuffIcons", filters = { me = { "HARMFUL", "RAID_PLAYER_DISPELLABLE" }, others = { "HARMFUL" } },
      dispel = true, harmfulEdge = true },
    -- every other debuff on yours (Forbearance, Weakened Soul…); buffs come
    -- only through buff indicators (you pick them)
    { key = "rest", set = "debuffIcons", who = "me", filter = { "HARMFUL", "!RAID_PLAYER_DISPELLABLE" }, dispel = true, harmfulEdge = true,
      gap = GAP_SETS - S["space-1"] },
    { key = "defensives", set = "buffIcons", filter = { "HELPFUL" }, list = "all", border = "ward", drain = "ward",
      gap = GAP_SETS - S["space-1"] },
}

-- The row's width at a bar height: both sets' icons, and the gap when both
-- have room.
local function rowWidth(h)
    local size = iconSize(h)
    local buffs, debuffs = M:Get("buffIcons"), M:Get("debuffIcons")
    local n = buffs + debuffs
    if n == 0 then return 0 end
    return n * size + (n - 1) * S["space-1"] + ((buffs > 0 and debuffs > 0) and (GAP_SETS - S["space-1"]) or 0)
end

local function auraReserve(h)
    local w = rowWidth(h)
    return w > 0 and (w + 2 * S["space-1"] + 1) or 0
end

--------------------------------------------------------------------------------
-- A header's button, styled once when the header makes it
--------------------------------------------------------------------------------

-- The row: a clip as wide as the settings' icons (the engine fills its
-- groups to their counts; the clip cuts off the rest) and one engine
-- container growing left from the bar's right end.
-- A group's count on a button: its setting, on the frames it is for (you:
-- read when the unit changes; unknown counts as someone else).
local function groupMax(f, g)
    if g.who and g.who ~= (f.isMe and "me" or "others") then return 0 end
    return M:Get(g.set)
end

-- A group's filter on a button, for whoever it shows now.
local function groupFilter(f, g)
    return g.filters and g.filters[f.isMe and "me" or "others"] or g.filter
end

-- Which debuff groups a button uses, and their filters, for whoever it
-- shows now.
local function applyWho(f)
    if not f.auras then return end
    for _, g in ipairs(AURA_GROUPS) do
        if g.filters then f.auras:SetGroupFilter(g.key, groupFilter(f, g)) end
        if g.who then f.auras:SetGroupMax(g.key, groupMax(f, g)) end
    end
end

local function buildAuras(f, h)
    local defensives = UI.GroupDefensives()
    local groups = {}
    for i, g in ipairs(AURA_GROUPS) do
        groups[i] = { key = g.key, filter = groupFilter(f, g), max = groupMax(f, g), dispel = g.dispel, drain = g.drain, digits = false,
            harmfulEdge = g.harmfulEdge, border = g.border, gap = g.gap, include = g.list and defensives[g.list] }
    end
    f.auraClip = CreateFrame("Frame", nil, f)
    f.auraClip:SetClipsChildren(true)
    f.auraClip:SetFrameLevel(f.over:GetFrameLevel() + 1)
    f.auras = UI.AuraContainer(f.auraClip, "none", { size = iconSize(h), spacing = S["space-1"], anchor = "TOPRIGHT", growth = { "LEFT", "DOWN" }, groups = groups, lazy = true })
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

-- Whether a button's unit is you, read when its unit changes and after a
-- fight: UnitIsUnit may be secret in combat, and a secret answer keeps the
-- last one.
local function updateIsMe(f)
    local me = f.unit and UnitIsUnit(f.unit, "player")
    if not isSecret(me) then f.isMe = me and true or false end
end

function M:StyleButton(button)
    if button.suuStyled then return end
    button.suuStyled = true
    local h = barHeight()
    local f = UI.UnitFrame(nil, nil, {
        frame = button, size = "sm", width = self:Get("width"), height = h,
        powerFor = powerFor, textOnSmall = true, healthText = self:Get("healthText"),
        nameColor = self:Get("nameColor"), raidMarker = self:Get("raidMarkers"),
        lowHealth = false, lowTint = self:Get("lowHealth"), incoming = self:Get("incoming"),
        reserveRight = auraReserve(h),
    })
    SuuUI.TagInstance(f, { module = M.id, role = "raid" })
    if not InCombatLockdown() then f:RegisterForClicks("AnyUp") end
    buildAuras(f, h)
    buildSelected(f)
    f:SetDispelBadges(self:Get("debuffBadges"))
    f:SetIndicators(UI.IndicatorsFor(UI.GroupIndicators(), UI.GroupTier()))
    f:SetWardSpells(UI.GroupDefensives().warded)
    self.buttons[#self.buttons + 1] = f
    -- the header sets the unit; the frame and its auras follow
    f:HookScript("OnAttributeChanged", function(btn, name, value)
        if name ~= "unit" then return end
        btn:SetUnit(value, true)
        updateIsMe(btn)
        applyWho(btn)
        if btn.auras then btn.auras:SetUnit(value or "none") end
        M:UpdateOffline()
        if value then
            if not btn.active then btn:Activate() end
            btn:Refresh()
            self:UpdateState(btn)
        end
    end)
    local unit = f:GetAttribute("unit")
    if unit then
        f:SetUnit(unit, true)
        updateIsMe(f)
        applyWho(f)
        if f.auras then f.auras:SetUnit(unit) end
        f:Activate()
    end
end

function M:ApplyAuraCount(f)
    -- each group's count, and the clip: the row at the bar's right end,
    -- centred on its height
    local h = f:GetHeight()
    local size = iconSize(h)
    for _, g in ipairs(AURA_GROUPS) do
        f.auras:SetGroupMax(g.key, groupMax(f, g))
        -- the icons follow the bar's height (from 21 players too); the height
        -- only changes out of combat, where the engine's buttons take a resize
        if not InCombatLockdown() then f.auras:SetGroupSize(g.key, size) end
    end
    local w = rowWidth(h)
    f.auraClip:ClearAllPoints()
    f.auraClip:SetPoint("RIGHT", f, "RIGHT", -S["space-1"] - 1, 0)
    f.auraClip:SetSize(math.max(1, w), size)
    f.auraClip:SetShown(w > 0)
end

--------------------------------------------------------------------------------
-- Headers
--------------------------------------------------------------------------------

-- Sorting within each group. groupBy only orders the units the header's
-- groupFilter (its group number) lets in: the header filters first, then
-- sorts what passed by groupingOrder, and anyone whose role isn't listed
-- goes last. groupingOrder goes first: a header with groupBy and no
-- groupingOrder errors on its next update.
local ROLE_ORDER = "TANK,HEALER,DAMAGER,NONE"

function M:ApplySort()
    local byRole = self:Get("sort") == "role"
    for _, hd in ipairs(self.headers) do
        if byRole then
            hd:SetAttribute("groupingOrder", ROLE_ORDER)
            hd:SetAttribute("groupBy", "ASSIGNEDROLE")
        else
            hd:SetAttribute("groupBy", nil)
            hd:SetAttribute("groupingOrder", nil)
        end
    end
end

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
        -- as tall as eight groups of a full raid (heightLarge) whatever the
        -- raid's size: the rows hang from its top, so the top edge stays put
        -- (the healer layout sits between the player and target frames, tops
        -- level) and it ends above the dock's stance and pet bars (seen in
        -- game: sized for eight rows at the 20-player height it reached them)
        local tall = self:Get("heightLarge")
        self.holder:SetSize(5 * w + 4 * gap, GROUPS * tall + (GROUPS - 1) * groupGap)
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
        f.opts.nameColor = self:Get("nameColor")
        f.opts.raidMarker = self:Get("raidMarkers")
        f.opts.lowTint = self:Get("lowHealth")
        f.opts.incoming = self:Get("incoming")
        f.opts.reserveRight = auraReserve(f:GetHeight())
        if f.auras then self:ApplyAuraCount(f) end
        if f.active then f:Refresh() end
    end
    self:UpdateStates()
    self:UpdateRange()
    self:UpdateOffline()
end

-- An offline player's auras are stale: their icons go see-through.
function M:UpdateOffline()
    for _, f in ipairs(self.buttons or {}) do
        local online = true
        local unit = f.unit
        if unit and UI.Flag(UnitExists(unit)) then
            local c = UnitIsConnected(unit)
            if c ~= nil and not isSecret(c) then online = c and true or false end
        end
        if f.auras then f.auras.container:SetAlpha(online and 1 or 0) end
    end
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
    for _, f in ipairs(self.buttons) do f:SetDispelBadges(self:Get("debuffBadges")) end
end

-- The Defensives list: the inline icons' spells and Warded, out of combat.
function M:ApplyDefensives()
    local d = UI.GroupDefensives()
    for _, f in ipairs(self.buttons) do
        if f.auras then
            for _, g in ipairs(AURA_GROUPS) do
                if g.list then f.auras:SetGroupSpells(g.key, d[g.list]) end
            end
        end
        f:SetWardSpells(d.warded)
    end
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
            if not f.unit or f.isMe then
                f:SetAlpha(1)
            else
                local inRange, checked = UnitInRange(f.unit)
                if isSecret(inRange) then
                    f:SetAlphaFromBoolean(inRange, 1, far)
                elseif not isSecret(checked) and checked == false then
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
    Brannoc = { incoming = 0.18, absorb = 0.1, marker = 8, auras = { { 871 } } },
    Kaelith = { aggro = true, incoming = 0.12, auras = { { 10060 } } },
    Morrow = { debuff = "Poison", auras = { { 2818, "dispel-poison" } } },
    Oren = { debuff = "Disease", removable = true, auras = { { 18278, "dispel-disease" } } },
    Grimbolt = { dead = true }, Sylva = { far = true }, Aldric = { aggro = true },
    Thessaly = { auras = { { 1022 } } }, Corvane = { incoming = 0.2 },
    Dagny = { absorb = 0.14 }, Nimra = { debuff = "Magic", removable = true, auras = { { 122, "dispel-magic" } } },
    Liora = { debuff = "Curse", auras = { { 980, "dispel-curse" } } },
    Ysolde = { selected = true, power = 0.14 },
    Hadrin = { marker = 7 }, Veyra = { offline = true },
}

local ROLE_RANK = { TANK = 1, HEALER = 2, DAMAGER = 3 }

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

-- A set of 40 made-up frames on a view: the settings window's, and edit
-- mode's group preview (on the real frames' place).
function M:BuildSet(parent)
    local view = CreateFrame("Frame", nil, parent)
    view:SetSize(1, 1)
    local set = { view = view, frames = {} }
    for i = 1, 40 do
        local f = UI.UnitFrame(view, "raidpreview" .. i, { size = "sm", secure = false, api = STAND_IN, powerFor = powerFor, textOnSmall = true })
        f:SetScript("OnEnter", nil)
        f:SetScript("OnLeave", nil)
        f:EnableMouse(false)
        buildSelected(f)
        f.icons = {}
        for k = 1, 4 do
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
        f.wardDeco = f:WardDecoration(f)
        f.wardDeco:SetWarded(false)
        set.frames[i] = f
    end
    return set
end

function M:PreviewView(parent)
    if self.previewView then
        self.previewView:SetParent(parent)
        self:DrawPreview(true)
        return self.previewView
    end
    self.previewSet = self:BuildSet(parent)
    self.previewView = self.previewSet.view
    self.previewView:HookScript("OnShow", function() self:DrawPreview() end)
    self:DrawPreview(true)
    return self.previewView
end

-- Both previews: the settings window's (while it shows) and edit mode's.
function M:DrawPreview(force)
    local set = self.previewSet
    if set and (force or set.view:IsVisible()) then self:DrawSet(set) end
    if self.screenSet and self.screenSet.view:IsShown() then self:DrawSet(self.screenSet) end
end


-- The group preview's "with buffs and debuffs": everyone carries a
-- defensive or two from the Defensives list and a debuff of every type.
local function fullAuras()
    local out = {}
    local list = UI.GroupDefensives().all or {}
    for i = 1, math.min(4, #list) do out[#out + 1] = { list[i] } end
    for _, a in ipairs({ { 122, "dispel-magic" }, { 980, "dispel-curse" }, { 2818, "dispel-poison" }, { 18278, "dispel-disease" } }) do
        out[#out + 1] = a
    end
    return out
end

-- Edit mode's group preview: a made-up raid of `count` on the real frames'
-- place, the real ones see-through meanwhile; 0 or fewer than 6 ends it.
function M:ScreenPreview(count, auras)
    if not self.holder then return end
    if not count or count <= 5 then
        if self.screenSet then self.screenSet.view:Hide() end
        self.holder:SetAlpha(1)
        return
    end
    local set = self.screenSet
    if not set then
        set = self:BuildSet(SuuUI.Root)
        self.screenSet = set
    end
    set.count = count
    set.allAuras = auras and fullAuras() or nil
    set.view:SetFrameStrata(self.holder:GetFrameStrata())
    set.view:SetFrameLevel(self.holder:GetFrameLevel() + 20)
    set.view:ClearAllPoints()
    set.view:SetPoint("TOPLEFT", self.holder, "TOPLEFT")
    set.view:Show()
    self:DrawSet(set)
    self.holder:SetAlpha(0)
end

function M:DrawSet(set)
    local count = set.count or self.previewSize or 20
    local w, gap, groupGap = self:Get("width"), self:Get("gap"), self:Get("groupGap")
    local h = count > 20 and self:Get("heightLarge") or self:Get("height")
    local rows = self:Get("arrangement") == "rows"
    local perBand = math.max(1, self:Get("perBand"))
    local groups = math.ceil(count / 5)
    local size, far = iconSize(h), self:Get("rangeAlpha")
    local badges = self:Get("debuffBadges")
    local defensives = UI.GroupDefensives()
    local listed, warding = {}, {}
    for _, id in ipairs(defensives.all) do listed[id] = true end
    for _, id in ipairs(defensives.warded) do warding[id] = true end
    -- each person's place in their group: raid order, or by role as the
    -- headers sort (tanks, healers, then damage; raid order within a role)
    local slotOf = {}
    for g = 1, groups do
        local members = {}
        for i = (g - 1) * 5 + 1, math.min(g * 5, count) do members[#members + 1] = i end
        if self:Get("sort") == "role" then
            table.sort(members, function(a, b)
                local ra, rb = ROLE_RANK[person("raidpreview" .. a).role] or 4, ROLE_RANK[person("raidpreview" .. b).role] or 4
                if ra ~= rb then return ra < rb end
                return a < b
            end)
        end
        for slot, i in ipairs(members) do slotOf[i] = slot - 1 end
    end
    local maxX, maxY = 0, 0
    for i, f in ipairs(set.frames) do
        if i > count then
            f:Hide()
        else
            local g, slot = math.floor((i - 1) / 5) + 1, slotOf[i]
            local x, y
            if rows then
                x, y = slot * (w + gap), (g - 1) * (h + groupGap)
            else
                local col, band = (g - 1) % perBand, math.floor((g - 1) / perBand)
                x, y = col * (w + groupGap), band * (5 * h + 4 * gap + groupGap * 2) + slot * (h + gap)
            end
            f:ClearAllPoints()
            f:SetPoint("TOPLEFT", set.view, "TOPLEFT", x, -y)
            maxX, maxY = math.max(maxX, x + w), math.max(maxY, y + h)
            f.opts.healthText = self:Get("healthText")
            f.opts.nameColor = self:Get("nameColor")
            f.opts.raidMarker = self:Get("raidMarkers")
            f.opts.lowTint = self:Get("lowHealth")
            f.opts.lowHealth = false
            f.opts.incoming = self:Get("incoming")
            f.opts.reserveRight = auraReserve(h)
            f:Resize(w, h)
            f:Refresh()
            local d = person("raidpreview" .. i)
            f:SetState(d.aggro and "danger" or nil, d.aggro and "Aggro" or nil)
            for kind, deco in pairs(f.dispelDecos) do
                deco:SetShown(badges ~= "off" and d.debuff == kind and (d.removable or badges ~= "removable"))
            end
            local warded = false
            local auras = set.allAuras or d.auras or {}
            for _, a in ipairs(auras) do warded = warded or warding[a[1]] == true end
            f.wardDeco:SetWarded(warded)
            f:SetAlpha(d.far and far or 1)
            f.selected:SetAlpha(d.selected and 1 or 0)
            -- indicators on every third person, as if their auras were up
            local list, version = UI.GroupIndicators()
            local tier = UI.GroupTier(count)
            if f.indicatorVersion ~= version .. tier then
                f.indicatorVersion = version .. tier
                f:SetPreviewIndicators((i % 3 == 1) and UI.IndicatorsFor(list, tier) or nil)
            end
            -- debuffs (a dispel edge) at the end, listed defensives before
            -- them; other buffs don't show
            local bySet = { debuffs = {}, buffs = {} }
            for _, a in ipairs(auras) do
                if a[2] then bySet.debuffs[#bySet.debuffs + 1] = a
                elseif listed[a[1]] then bySet.buffs[#bySet.buffs + 1] = a end
            end
            -- the row from the right end: debuffs, then the defensives
            local used, x = 0, S["space-1"] + 1
            for si, key in ipairs({ "debuffs", "buffs" }) do
                local limit = self:Get(key == "buffs" and "buffIcons" or "debuffIcons")
                for k = 1, math.min(#bySet[key], limit) do
                    local a = bySet[key][k]
                    if k == 1 and si == 2 and used > 0 then x = x + GAP_SETS - S["space-1"] end
                    used = used + 1
                    local icon = f.icons[used]
                    icon:SetSize(size, size)
                    icon:SetArt(C_Spell.GetSpellTexture(a[1]))
                    icon:SetBorder(a[2] or "ward")
                    icon:ClearAllPoints()
                    icon:SetPoint("RIGHT", f, "RIGHT", -x, 0)
                    icon:Show()
                    x = x + size + S["space-1"]
                end
            end
            for k = used + 1, #f.icons do f.icons[k]:Hide() end
            f:Show()
        end
    end
    set.view:SetSize(math.max(1, maxX), math.max(1, maxY))
    if groups == 0 then set.view:SetSize(1, 1) end
end

--------------------------------------------------------------------------------
-- Settings
--------------------------------------------------------------------------------

local SECTION = {
    id = "raid", label = "Raid frames", category = "Frames", order = 16,
    preview = function(parent) return M:PreviewView(parent) end,
    groups = {
        { title = "Layout", description = "One layout per profile. Healers usually want groups as rows in the middle of the screen, tanks and DPS columns above the chat: make a profile for each and let SuuUI switch them with your role (General > Profiles > By role). Move the frames in edit mode (General > Appearance > Edit layout).", rows = {
            { key = "showSolo", label = "Show when solo", control = "toggle", combat = true,
              description = "Your own frame while you aren't in a group: to try the frames (a debuff on you shows its badge)." },
            { label = "Preview", control = "segmented",
              options = { { value = 10, label = "10" }, { value = 20, label = "20" }, { value = 40, label = "40" } },
              description = "How many made-up people the preview shows.",
              get = function() return M.previewSize or 20 end,
              -- not a setting: no reset, never counts as a change
              set = function(v) M.previewSize = v; M:DrawPreview(); return true end },
            { key = "arrangement", label = "Groups", control = "segmented", combat = true,
              options = { { value = "columns", label = "Columns" }, { value = "rows", label = "Rows" } },
              description = "Columns: each group a column of five (the side layout). Rows: each group a row of five, group 1 on top (the healer layout)." },
            { key = "sort", label = "Sort", control = "segmented", combat = true,
              options = { { value = "group", label = "Group order" }, { value = "role", label = "Role" } },
              description = "Within each group: the raid's order, or tanks, healers, then damage. Everyone stays in their own group." },
            { key = "perBand", label = "Columns side by side", control = "stepper", min = 1, max = 8, step = 1, combat = true,
              description = "Then the next groups start a new band below. 4 keeps 40 players in two bands.",
              disabled = function() if M:Get("arrangement") ~= "columns" then return true, "Only for groups as columns." end end },
            { key = "width", label = "Width", control = "slider", min = 60, max = 200, step = 2, unit = "px", live = false, combat = true,
              description = "Each frame's width; groups as rows are five frames wide." },
            { key = "height", label = "Height", control = "slider", min = 14, max = 40, step = 1, unit = "px", live = false, combat = true,
              description = "Up to 20 players; the aura icons inside the bar follow it." },
            { key = "heightLarge", label = "Height from 21 players", control = "slider", min = 14, max = 40, step = 1, unit = "px", live = false, combat = true,
              description = "A shorter bar keeps a 40-player grid clear of the dock." },
            { key = "gap", label = "Gap", control = "slider", min = 0, max = 20, step = 1, unit = "px", live = false, combat = true },
            { key = "groupGap", label = "Gap between groups", control = "slider", min = 0, max = 20, step = 1, unit = "px", live = false, combat = true },
        } },
        { title = "Inside the bar", rows = {
            { key = "power", label = "Power line", control = "segmented",
              options = { { value = "roles", label = "Tanks and healers" }, { value = "all", label = "Everyone" }, { value = "none", label = "None" } },
              description = "Without roles in the group, healing classes count as healers." },
            { key = "healthText", label = "Health text", control = "segmented",
              options = { { value = "percent", label = "64%" }, { value = "value", label = "8.5k" },
                          { value = "both", label = "8.5k · 64%" }, { value = "none", label = "None" } },
              description = "At the right end of each bar: the health percentage, the current health, or both." },
            { key = "nameColor", label = "Name colour", control = "segmented",
              options = { { value = "game", label = "Class" }, { value = "ink", label = "Plain" } },
              description = "Players in their class colour, hostile and neutral NPCs in their reaction colour." },
            { key = "raidMarkers", label = "Raid markers", control = "toggle",
              description = "A skull, cross or other raid marker over the top edge of the frame, in combat too." },
            { key = "lowHealth", label = "Low-health tint", control = "toggle",
              description = "The empty part of the bar warms to ember from 70% down, strongest at 10%, so the lowest stand out in a full grid. Healers want it." },
            { key = "incoming", label = "Incoming heals and absorbs", control = "toggle",
              description = "Heals on their way, past the health, then shields, hatched." },
            { key = "buffIcons", label = "Defensive icons", control = "stepper", min = 0, max = 2, step = 1, combat = true,
              description = "Inside the bar's right end: their externals, then their own defensives, from Frames › Defensives. Your heals over time and shields go in Buff indicators." },
            { key = "debuffIcons", label = "Debuff icons", control = "stepper", min = 0, max = 2, step = 1, combat = true,
              description = "At the bar's very end, after the defensives: debuffs you can remove first, then the rest." },
        } },
        { title = "States", rows = {
            { key = "debuffBadges", label = "Debuff badges", control = "segmented", combat = true,
              options = { { value = "all", label = "Every type" }, { value = "removable", label = "Only what you can remove" }, { value = "off", label = "Off" } },
              description = "Magic, Curse, Poison, Disease as a badge and border, in combat too. A debuff covers Aggro." },
            -- step 0.01: the default is the design's opacity-oor (0.42)
            { key = "rangeAlpha", label = "Out of range", control = "slider", min = 0.2, max = 1, step = 0.01,
              format = function(v) return ("%d%%"):format(v * 100 + 0.5) end,
              description = "How faint a raid member out of your range is." },
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
        self:ApplySort()
        self:UpdateVisibility()
        self:ApplyOptions()
    end)

    for _, key in ipairs({ "arrangement", "perBand", "width", "height", "heightLarge", "gap", "groupGap", "buffIcons", "debuffIcons" }) do
        self:Watch(key, function()
            self:DrawPreview()
            self:RunOutOfCombat("layout", function() self:Layout(); self:ApplyOptions() end)
        end)
    end
    for _, key in ipairs({ "power", "healthText", "nameColor", "raidMarkers", "lowHealth", "incoming", "rangeAlpha" }) do
        self:Watch(key, function() self:ApplyOptions(); self:DrawPreview() end)
    end
    self:Watch("debuffBadges", function()
        self:DrawPreview()
        self:RunOutOfCombat("badges", function() self:ApplyBadges() end)
    end)
    self:Watch("showSolo", function() self:UpdateVisibility() end)
    self:Watch("sort", function()
        self:DrawPreview()
        self:RunOutOfCombat("sort", function() self:ApplySort() end)
    end)
    self:On("SUUUI_INDICATORS_CHANGED", function() self:QueueIndicators(); self:DrawPreview() end)
    -- edit mode's group preview: a made-up raid on the real frames' place
    self:On("SUUUI_EDITMODE_GROUP_PREVIEW", function(_, size, auras) self:ScreenPreview(size, auras) end)
    self:On("SUUUI_DEFENSIVES_CHANGED", function()
        self:RunOutOfCombat("defensives", function() self:ApplyDefensives() end)
        self:DrawPreview()
    end)

    self:OnGameEvent("PLAYER_TARGET_CHANGED", function() self:UpdateSelected() end)
    self:OnGameEvent("UNIT_CONNECTION", function() self:UpdateOffline() end)
    self:OnGameEvent("GROUP_ROSTER_UPDATE", function()
        -- a token can now be someone else: redraw, re-scan auras (the
        -- indicators' too)
        for _, f in ipairs(self.buttons) do
            if f.unit then
                updateIsMe(f)
                applyWho(f)
                if f.auras then f.auras:Refresh() end
                for _, list in pairs(f.dispelSets or {}) do for _, c in ipairs(list) do c:Refresh() end end
                for _, c in ipairs(f.indicatorContainers or {}) do c:Refresh() end
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
    self:OnGameEvent("PLAYER_REGEN_ENABLED", function()
        presence()
        for _, f in ipairs(self.buttons) do updateIsMe(f); applyWho(f) end
    end)
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
