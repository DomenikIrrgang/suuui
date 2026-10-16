-- Units/PartyFrames.lua
-- Party frames (step 1.8): you and up to four party members, one unit frame
-- each. A built-in module written against the public API only.
--
-- One layout per profile: SuuUI switches profiles by role (General >
-- Profiles > By role), so a healer profile can put the party in the middle
-- of the screen with the low-health tint, and a tank or DPS profile bottom
-- left above the chat, without the frames knowing about roles themselves.
--
-- The frames show in a party and hide in a raid (raid frames are step 1.9)
-- and solo. The settings window's preview column shows a made-up party,
-- so every setting can be tried solo. Each follows its unit (RegisterUnitWatch); party units fill from
-- party1 up, so the slots never have gaps. Placement and size change only
-- out of combat: the frames are secure buttons (click to target).
--
-- Auras are the engine's (aura containers): debuffs you can remove first
-- (dispel-coloured edge), then defensives, then the other debuffs raid
-- frames show; buffs come only through buff indicators. Debuff types (Magic, Curse, Poison,
-- Disease) are slots: per type a one-aura container
-- filtered to that type, whose button carries that type's border and badge
-- across the whole frame. The engine shows and hides it, so it works in
-- combat, where addon code can't read auras. Aggro comes from the threat
-- state, which stays readable.

local UI, T = SuuUI.UI, SuuUI.Tokens
local S = T.space

local M = SuuUI.RegisterModule({
    id = "party",
    name = "Party frames",
    description = "You and your party: health, power, auras you can remove, aggro and range.",
    api = "0.17",
    reloadToToggle = true,
    defaults = {
        position = { point = "BOTTOMLEFT", x = 28, y = 300 },
        showSelf = true,
        showSolo = false,       -- your own frame while not in a group
        direction = "up",       -- "up", "down", "right"
        width = 200,
        height = 28,
        gap = 6,
        power = "roles",        -- "roles" (tanks and healers), "all", "none"
        healthText = "percent",
        nameColor = "game",     -- "game" (class colour) or "ink", as on the unit frames
        raidMarkers = true,
        lowHealth = true,
        incoming = true,
        buffIcons = 2,          -- defensives on them (the Defensives list)
        debuffIcons = 3,        -- debuffs, the ones you can remove first
        auraSide = "right",
        debuffBadges = "all",   -- "all" debuff types, "removable" or "off"
        rangeAlpha = 0.25,
    },
})

-- one aura row (Aura icons, Show buffs) became defensives and debuffs, each
-- with its count; they start at the new defaults
M:Migrate("auraSplit", function(values)
    values.auras, values.showBuffs = nil, nil
end)

-- "badges" is "debuffBadges" now, as on the unit frames
M:Migrate("debuffBadges", function(values)
    if values.badges ~= nil and values.debuffBadges == nil then values.debuffBadges = values.badges end
    values.badges = nil
end)

local SLOTS = { "player", "party1", "party2", "party3", "party4" }
local isSecret = issecretvalue or function() return false end

-- Healing classes, for the power line when the group gives no roles.
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

--------------------------------------------------------------------------------
-- Building
--------------------------------------------------------------------------------

-- Auras after the bar, clipped to the number the settings allow: the engine
-- fills its groups in order, and what doesn't fit is cut off.
-- Beside the bar, one row the engine lays out: defensives (the Defensives
-- list's spells, Frames › Defensives: the game hides who cast another
-- player's buffs, and its own defensive filters then let every buff
-- through), then debuffs, the ones you can remove first, right after
-- however many defensives show, `space-4` apart. On your own frame the
-- debuffs you can remove come first; on everyone else's they're one list
-- (the game hides who cast another player's auras, and those then pass both
-- "removable" and "not removable", so each showed twice). Defensives are always left
-- of debuffs: on the left side the debuffs come first from the bar. No
-- other buffs: those come through buff indicators.
local GAP_SETS = S["space-4"]
local AURA_GROUPS = {
    { key = "defensives", set = "buffIcons", filter = { "HELPFUL" }, list = "all", border = "ward", glow = "glow-ward", drain = "ward" },
    { key = "dispel", set = "debuffIcons", who = "me", filter = { "HARMFUL", "RAID_PLAYER_DISPELLABLE" }, dispel = true, harmfulEdge = true },
    -- every other debuff (Forbearance, Weakened Soul…)
    { key = "debuffs", set = "debuffIcons", who = "me", filter = { "HARMFUL", "!RAID_PLAYER_DISPELLABLE" }, dispel = true, harmfulEdge = true },
    -- everyone else's frames: all their debuffs, once
    { key = "all", set = "debuffIcons", who = "others", filter = { "HARMFUL" }, dispel = true, harmfulEdge = true },
}
-- each group's place from the bar: defensives first on the right, last on the left
local ORDER = {
    right = { defensives = 1, dispel = 2, debuffs = 3, all = 4 },
    left = { dispel = 1, debuffs = 2, all = 3, defensives = 4 },
}

-- A group's count on a frame: its setting, on the frames it is for.
local function groupMax(f, g)
    if g.who and g.who ~= (f.unit == "player" and "me" or "others") then return 0 end
    return M:Get(g.set)
end

local function buildAuras(f)
    local defensives = UI.GroupDefensives()
    local clip = CreateFrame("Frame", nil, f)
    clip:SetClipsChildren(true)
    local groups = {}
    for i, g in ipairs(AURA_GROUPS) do
        groups[i] = { key = g.key, filter = g.filter, max = groupMax(f, g), dispel = g.dispel, drain = g.drain,
            harmfulEdge = g.harmfulEdge, border = g.border, glow = g.glow,
            include = g.list and defensives[g.list] }
    end
    f.auraClip = clip
    f.auras = UI.AuraContainer(clip, f.unit, { size = M:Get("height"), anchor = "TOPLEFT", growth = { "RIGHT", "DOWN" }, groups = groups })
    if f.auras then f.auras.container:SetPoint("TOPLEFT", clip, "TOPLEFT") end
end

-- The row's width: both sets' icons, and the gap when both have room.
local function rowWidth(self, h, buffs, debuffs)
    local n = buffs + debuffs
    if n == 0 then return 0 end
    return n * h + (n - 1) * S["space-2"] + ((buffs > 0 and debuffs > 0) and (GAP_SETS - S["space-2"]) or 0)
end

-- The selected border (your target): its own frame, so a secret "is it the
-- target?" can set its alpha through the engine.
local function buildSelected(f)
    local sel = CreateFrame("Frame", nil, f)
    sel:SetAllPoints()
    sel:SetFrameLevel(f:GetFrameLevel() + 10)
    UI.Border(sel, "arcane", { inset = 0 })
    sel:SetAlpha(0)
    f.selected = sel
end

--------------------------------------------------------------------------------
-- The preview (the settings window's preview column): a made-up party drawn
-- by the same unit frames, from stand-in data instead of the game
-- (UnitFrame's opts.api). Not secure, so it follows every setting at once.
--------------------------------------------------------------------------------

-- Five people: you, then a tank, a healer, a mage with aggro, a rogue out of
-- range. Auras are spell textures with the edge the engine would give them.
local PEOPLE = {
    { you = true, health = 0.92, power = 0.7, auras = {} },
    { name = "Brannoc", class = "WARRIOR", role = "TANK", health = 0.64, max = 8800, power = 0.4, incoming = 0.18, absorb = 0.1,
      marker = 8, auras = { { 871 } } },
    { name = "Ysolde", class = "PRIEST", role = "HEALER", health = 0.83, max = 3900, power = 0.14, selected = true,
      debuff = "Magic", removable = true, auras = { { 122, "dispel-magic" } } },
    { name = "Kaelith", class = "MAGE", role = "DAMAGER", health = 0.28, max = 3600, power = 0.55, incoming = 0.12, aggro = true,
      auras = { { 1022 } } },
    { name = "Morrow", class = "ROGUE", role = "DAMAGER", health = 0.76, max = 4600, power = 0.8, far = true,
      debuff = "Poison", removable = false, auras = { { 2818, "dispel-poison" } } },
}

local function person(unit)
    local i = tonumber(unit:match("^preview(%d)$"))
    local d = PEOPLE[i or 1]
    if d.you and not d.name then
        d.name = UnitName("player")
        local _, class = UnitClass("player")
        d.class = class
        d.role = SuuUI.Role()
        local max = UnitHealthMax("player")
        d.max = (not isSecret(max) and max and max > 0) and max or 4200
    end
    return d
end

local STAND_IN = UI.UnitStandIn(person)

-- The view the settings window shows (built once, on its first showing):
-- the frames' holder, and room beside it for the aura sets.
function M:PreviewView(parent)
    if self.previewView then
        self.previewView:SetParent(parent)
        self:DrawPreview(true)
        return self.previewView
    end
    local view = CreateFrame("Frame", nil, parent)
    view:SetSize(1, 1)
    local holder = CreateFrame("Frame", nil, view)
    self.previewView, self.previewHolder, self.previewFrames = view, holder, {}
    for i = 1, #SLOTS do
        local f = UI.UnitFrame(holder, "preview" .. i, { size = "md", secure = false, api = STAND_IN, powerFor = powerFor })
        f:SetScript("OnEnter", nil)
        f:SetScript("OnLeave", nil)
        f:EnableMouse(false)
        -- the row as the live frames have it, icons drawn instead of the engine's
        f.auraClip = CreateFrame("Frame", nil, f)
        f.auraClip:SetClipsChildren(true)
        f.icons = {}
        for k = 1, 8 do
            f.icons[k] = UI.Icon(f.auraClip, 24)
            f.icons[k]:Hide()
        end
        buildSelected(f)
        f.dispelDecos = {}
        for _, kind in ipairs(UI.DEBUFF_TYPES) do
            local deco = f:DispelDecoration(f, kind)
            deco:Hide()
            f.dispelDecos[kind] = deco
        end
        f.wardDeco = f:WardDecoration(f)
        f.wardDeco:SetWarded(false)
        self.previewFrames[i] = f
    end
    view:HookScript("OnShow", function() self:DrawPreview() end)
    self:DrawPreview(true)
    return view
end

-- Draws the made-up party with the current settings.
function M:DrawPreview(force)
    if not self.previewView or not (force or self.previewView:IsVisible()) then return end
    self:LayoutFrames(self.previewFrames, self.previewHolder)
    local h, far = self:Get("height"), self:Get("rangeAlpha")
    local badges = self:Get("debuffBadges")
    local defensives = UI.GroupDefensives()
    local listed, warding = {}, {}
    for _, id in ipairs(defensives.all) do listed[id] = true end
    for _, id in ipairs(defensives.warded) do warding[id] = true end
    -- each person's auras by set: listed defensives, and debuffs (a dispel
    -- edge); other buffs don't show on party frames
    local function split(d)
        local out = { buffs = {}, debuffs = {} }
        for _, a in ipairs(d.auras) do
            if a[2] then out.debuffs[#out.debuffs + 1] = a
            elseif listed[a[1]] then out.buffs[#out.buffs + 1] = a end
        end
        return out
    end
    -- the view: the holder, with room on its side for the auras the made-up
    -- people actually show (not the empty slots), so it centres on what's seen
    local auraW = 0
    for _, d in ipairs(PEOPLE) do
        local parts = split(d)
        local w = rowWidth(self, h, math.min(#parts.buffs, self:Get("buffIcons")), math.min(#parts.debuffs, self:Get("debuffIcons")))
        auraW = math.max(auraW, w > 0 and (S["space-2"] + w) or 0)
    end
    local hw, hh = self.previewHolder:GetSize()
    local right = self:Get("auraSide") == "right"
    self.previewHolder:ClearAllPoints()
    self.previewHolder:SetPoint("TOPLEFT", self.previewView, "TOPLEFT", right and 0 or auraW, 0)
    self.previewView:SetSize(hw + auraW, hh)
    for i, f in ipairs(self.previewFrames) do
        local d = person("preview" .. i)
        f.opts.healthText = self:Get("healthText")
        f.opts.nameColor = self:Get("nameColor")
        f.opts.raidMarker = self:Get("raidMarkers")
        f.opts.lowHealth = false
        f.opts.lowTint = self:Get("lowHealth")
        f.opts.incoming = self:Get("incoming")
        f:Refresh()
        f:SetState(d.aggro and "danger" or nil, d.aggro and "Aggro" or nil)
        for kind, deco in pairs(f.dispelDecos) do
            deco:SetShown(badges ~= "off" and d.debuff == kind and (d.removable or badges ~= "removable"))
        end
        local warded = false
        for _, a in ipairs(d.auras) do warded = warded or warding[a[1]] == true end
        f.wardDeco:SetWarded(warded)
        f:SetAlpha(d.far and far or 1)
        f.selected:SetAlpha(d.selected and 1 or 0)
        local list, version = UI.GroupIndicators()
        if f.indicatorVersion ~= version then
            f.indicatorVersion = version
            f:SetPreviewIndicators((i >= 2 and i <= 4) and UI.IndicatorsFor(list, "5") or nil)
        end
        -- the row from the bar outward, as the engine lays it out
        local parts = split(d)
        local row = {}
        local sets = right and { "buffs", "debuffs" } or { "debuffs", "buffs" }
        for si, key in ipairs(sets) do
            local limit = self:Get(key == "buffs" and "buffIcons" or "debuffIcons")
            for k = 1, math.min(#parts[key], limit) do
                row[#row + 1] = { aura = parts[key][k], gap = k == 1 and si == 2 and #row > 0 }
            end
        end
        local x = 0
        for k, icon in ipairs(f.icons) do
            local e = row[k]
            if e then
                if e.gap then x = x + GAP_SETS - S["space-2"] end
                icon:SetSize(h, h)
                icon:SetArt(C_Spell.GetSpellTexture(e.aura[1]))
                icon:SetBorder(e.aura[2] or "ward")
                icon:SetGlow(e.aura[2] == nil and "glow-ward" or nil)
                icon:ClearAllPoints()
                if right then
                    icon:SetPoint("TOPLEFT", f.auraClip, "TOPLEFT", x, 0)
                else
                    icon:SetPoint("TOPRIGHT", f.auraClip, "TOPRIGHT", -x, 0)
                end
                x = x + h + S["space-2"]
                icon:Show()
            else
                icon:Hide()
            end
        end
    end
end

local function build(self)
    local holder = CreateFrame("Frame", "SuuUIPartyFrames", SuuUI.Root, "SecureHandlerStateTemplate")
    holder:SetSize(1, 1)
    holder.suuManagedShow = true -- its state driver shows it, not edit mode
    self.holder, self.frames = holder, {}
    for i, unit in ipairs(SLOTS) do
        local f = UI.UnitFrame(holder, unit, {
            size = "md", name = "SuuUIParty" .. (i == 1 and "Player" or (i - 1)) .. "Frame",
            youWhenPlayer = false, powerFor = powerFor,
        })
        f.suuManagedShow = true
        buildAuras(f)
        buildSelected(f)
        self.frames[i] = f
    end
end

--------------------------------------------------------------------------------
-- Layout and options (out of combat)
--------------------------------------------------------------------------------

-- Places a set of frames (the real ones, or the preview's) in their holder.
function M:LayoutFrames(frames, holder)
    local w, h, gap = self:Get("width"), self:Get("height"), self:Get("gap")
    local dir = self:Get("direction")
    local n = #SLOTS
    local auraRight = self:Get("auraSide") == "right"
    local first = self:Get("showSelf") and 1 or 2
    local count = n - first + 1
    if dir == "right" then
        holder:SetSize(count * w + (count - 1) * gap, h)
    else
        holder:SetSize(w, count * h + (count - 1) * gap)
    end
    for i, f in ipairs(frames) do
        f:Resize(w, h)
        f:ClearAllPoints()
        local slot = i - first -- 0-based; the player's slot is -1 when hidden
        if slot >= 0 then
            if dir == "right" then
                f:SetPoint("TOPLEFT", holder, "TOPLEFT", slot * (w + gap), 0)
            elseif dir == "down" then
                f:SetPoint("TOPLEFT", holder, "TOPLEFT", 0, -slot * (h + gap))
            else
                f:SetPoint("BOTTOMLEFT", holder, "BOTTOMLEFT", 0, slot * (h + gap))
            end
        else
            f:SetPoint("TOPLEFT", holder, "TOPLEFT")
        end
        if holder ~= self.holder then f:SetShown(slot >= 0) end
        -- the row beside the bar, space-2 away, growing away from it
        local buffs, debuffs = self:Get("buffIcons"), self:Get("debuffIcons")
        f.auraClip:ClearAllPoints()
        f.auraClip:SetSize(math.max(1, rowWidth(self, h, buffs, debuffs)), h)
        if auraRight then
            f.auraClip:SetPoint("LEFT", f, "RIGHT", S["space-2"], 0)
        else
            f.auraClip:SetPoint("RIGHT", f, "LEFT", -S["space-2"], 0)
        end
        f.auraClip:SetShown(buffs + debuffs > 0)
        if f.auras then
            -- the icons are as tall as the bar (Layout runs out of combat,
            -- where the engine's buttons take a resize); each group's count,
            -- and its place: the space before a set's first group
            local order = ORDER[auraRight and "right" or "left"]
            for _, g in ipairs(AURA_GROUPS) do
                f.auras:SetGroupSize(g.key, h)
                f.auras:SetGroupMax(g.key, groupMax(f, g))
                f.auras:SetGroupPlace(g.key, order[g.key], order[g.key] > 1 and (GAP_SETS - S["space-2"]) or nil)
            end
            local c = f.auras.container
            c:ClearAllPoints()
            if auraRight then
                c:SetPoint("TOPLEFT", f.auraClip, "TOPLEFT")
                f.auras:SetFlow("TOPLEFT", { "RIGHT", "DOWN" })
            else
                c:SetPoint("TOPRIGHT", f.auraClip, "TOPRIGHT")
                f.auras:SetFlow("TOPRIGHT", { "LEFT", "DOWN" })
            end
        end
    end
end

function M:Layout()
    self:LayoutFrames(self.frames, self.holder)
    self:DrawPreview()
end

function M:ApplyOptions()
    for _, f in ipairs(self.frames) do
        f.opts.healthText = self:Get("healthText")
        f.opts.nameColor = self:Get("nameColor")
        f.opts.raidMarker = self:Get("raidMarkers")
        f.opts.lowHealth = false
        f.opts.lowTint = self:Get("lowHealth")
        f.opts.incoming = self:Get("incoming")
        if f.active then f:Refresh() end
    end
    self:UpdateStates()
    self:UpdateRange()
    self:UpdateOffline()
end

-- An offline member's auras are stale: their icons go see-through.
function M:UpdateOffline()
    for _, f in ipairs(self.frames) do
        local online = true
        if UI.Flag(UnitExists(f.unit)) then
            local c = UnitIsConnected(f.unit)
            if c ~= nil and not isSecret(c) then online = c and true or false end
        end
        if f.auras then f.auras.container:SetAlpha(online and 1 or 0) end
    end
end

--------------------------------------------------------------------------------
-- Showing: in a party, not in a raid
--------------------------------------------------------------------------------

function M:UpdateVisibility()
    self:RunOutOfCombat("visibility", function()
        local solo = self:Get("showSolo") and self:Get("showSelf") and "show" or "hide"
        RegisterStateDriver(self.holder, "visibility", "[group:raid] hide; [group:party] show; " .. solo)
        local first = self:Get("showSelf") and 1 or 2
        for i, f in ipairs(self.frames) do
            if i >= first then
                RegisterUnitWatch(f)
            else
                UnregisterUnitWatch(f)
                f:Hide()
            end
        end
    end)
end



--------------------------------------------------------------------------------
-- States: aggro, debuff types, your target, range
--------------------------------------------------------------------------------

function M:UpdateState(f)
    local u = f.unit
    if not UnitExists(u) then return end
    -- aggro: a non-tank the enemy is attacking
    local threat = UnitThreatSituation(u)
    local role = UnitGroupRolesAssigned and UnitGroupRolesAssigned(u)
    local aggro = not isSecret(threat) and threat ~= nil and threat >= 2 and not (not isSecret(role) and role == "TANK")
    f:SetState(aggro and "danger" or nil, aggro and "Aggro" or nil)
end

-- Debuff-type badges (the unit frame's slots): every type, only what you
-- can remove, or none. Out of combat (it may create the slots).
function M:ApplyBadges()
    for _, f in ipairs(self.frames) do f:SetDispelBadges(self:Get("debuffBadges")) end
end

-- The Defensives list: the slots' spells and Warded, out of combat.
function M:ApplyDefensives()
    local d = UI.GroupDefensives()
    for _, f in ipairs(self.frames) do
        if f.auras then
            for _, g in ipairs(AURA_GROUPS) do
                if g.list then f.auras:SetGroupSpells(g.key, d[g.list]) end
            end
        end
        f:SetWardSpells(d.warded)
    end
end

-- Buff indicators (the Buff indicators module's list), out of combat; a
-- burst of edits applies once.
function M:ApplyIndicators()
    self.indicatorTier = UI.GroupTier()
    local list = UI.IndicatorsFor(UI.GroupIndicators(), self.indicatorTier)
    for _, f in ipairs(self.frames) do f:SetIndicators(list) end
end

function M:QueueIndicators()
    if self.indicatorTimer then self.indicatorTimer:Cancel() end
    self.indicatorTimer = C_Timer.NewTimer(1, function()
        self.indicatorTimer = nil
        self:RunOutOfCombat("indicators", function() self:ApplyIndicators() end)
    end)
end

function M:UpdateStates()
    for _, f in ipairs(self.frames) do self:UpdateState(f) end
end

function M:UpdateSelected()
    for _, f in ipairs(self.frames) do
        local is = UnitExists(f.unit) and UnitIsUnit(f.unit, "target")
        if isSecret(is) then
            f.selected:SetAlphaFromBoolean(is, 1, 0)
        else
            f.selected:SetAlpha(is and 1 or 0)
        end
    end
end

-- Out of range: the whole frame fades. The answer may be secret in combat;
-- the engine applies it as an alpha then.
function M:UpdateRange()
    local far = self:Get("rangeAlpha")
    for _, f in ipairs(self.frames) do
        if f.unit == "player" or not UnitExists(f.unit) then
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

--------------------------------------------------------------------------------
-- Settings
--------------------------------------------------------------------------------

local SECTION = {
    id = "party", label = "Party frames", category = "Frames", order = 14,
    -- the preview column: a made-up party with every setting applied
    preview = function(parent) return M:PreviewView(parent) end,
    groups = {
        { title = "Layout", description = "One layout per profile. For a healer and a tank or DPS layout, make a profile for each and let SuuUI switch them with your role (General > Profiles > By role). Move the frames in edit mode (General > Appearance > Edit layout).", rows = {
            { key = "showSelf", label = "Show yourself", control = "toggle", combat = true, description = "You first, then your party." },
            { key = "showSolo", label = "Show when solo", control = "toggle", combat = true,
              description = "Your own frame while you aren't in a group: to try the frames (a debuff on you shows its badge).",
              disabled = function() if not M:Get("showSelf") then return true, "Turn on Show yourself first." end end },
            { key = "direction", label = "Direction", control = "segmented", combat = true,
              options = { { value = "up", label = "Up" }, { value = "down", label = "Down" }, { value = "right", label = "Across" } },
              description = "Up suits frames above the chat; across, a row in the middle of the screen." },
            { key = "width", label = "Width", control = "slider", min = 80, max = 300, step = 2, unit = "px", live = false, combat = true },
            { key = "height", label = "Height", control = "slider", min = 18, max = 48, step = 1, unit = "px", live = false, combat = true,
              description = "The aura icons are as tall as the bars." },
            { key = "gap", label = "Gap", control = "slider", min = 0, max = 20, step = 1, unit = "px", live = false, combat = true },
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
        } },
        { title = "Auras and states", rows = {
            { key = "buffIcons", label = "Defensive icons", control = "stepper", min = 0, max = 4, step = 1, combat = true,
              description = "Beside each bar: their externals, then their own defensives, from Frames › Defensives (Blessing of Protection, Shield Wall…). Other buffs show through Buff indicators. None while someone is offline." },
            { key = "debuffIcons", label = "Debuff icons", control = "stepper", min = 0, max = 4, step = 1, combat = true,
              description = "After the defensives: debuffs you can remove first, then the rest." },
            { key = "auraSide", label = "Aura side", control = "segmented", combat = true,
              options = { { value = "right", label = "Right" }, { value = "left", label = "Left" } },
              description = "Which side of the bar the icons sit on. Defensives are always left of debuffs.",
              disabled = function() if M:Get("buffIcons") + M:Get("debuffIcons") == 0 then return true, "No aura icons." end end },
            { key = "debuffBadges", label = "Debuff badges", control = "segmented", combat = true,
              options = { { value = "all", label = "Every type" }, { value = "removable", label = "Only what you can remove" }, { value = "off", label = "Off" } },
              description = "Magic, Curse, Poison, Disease as a badge and border on the frame, in combat too. Several at once: Magic shows over Curse, Poison, Disease." },
            -- step 0.01: the default is the design's opacity-oor (0.42)
            { key = "rangeAlpha", label = "Out of range", control = "slider", min = 0.2, max = 1, step = 0.01,
              format = function(v) return ("%d%%"):format(v * 100 + 0.5) end,
              description = "How faint a party member out of your range is." },
        } },
    },
}

--------------------------------------------------------------------------------
-- Lifecycle
--------------------------------------------------------------------------------

local function standDownBlizzard()
    for _, name in ipairs({ "PartyFrame", "CompactPartyFrame" }) do
        if _G[name] then SuuUI.SuppressBlizzard(name) end
    end
end

function M:OnEnable()
    standDownBlizzard()
    if not self.frames then build(self) end
    for _, f in ipairs(self.frames) do f:Activate() end
    self:RegisterMover(self.holder, { key = "position", label = "Party frames" })
    SuuUI.PublishAnchor("party", self.holder)
    self:RegisterSettings(SECTION)
    self:RunOutOfCombat("layout", function() self:Layout() end)
    self:UpdateVisibility()
    self:RunOutOfCombat("badges", function() self:ApplyBadges() end)
    self:RunOutOfCombat("indicators", function() self:ApplyIndicators() end)
    self:On("SUUUI_INDICATORS_CHANGED", function() self:QueueIndicators(); self:DrawPreview() end)
    self:RunOutOfCombat("defensives", function() self:ApplyDefensives() end)
    self:On("SUUUI_DEFENSIVES_CHANGED", function()
        self:RunOutOfCombat("defensives", function() self:ApplyDefensives() end)
        self:DrawPreview()
    end)
    self:ApplyOptions()
    self:UpdateSelected()

    for _, key in ipairs({ "width", "height", "gap", "direction", "showSelf", "buffIcons", "debuffIcons", "auraSide" }) do
        self:Watch(key, function()
            self:RunOutOfCombat("layout", function() self:Layout() end)
            if key == "showSelf" then self:UpdateVisibility() end
        end)
    end
    self:Watch("showSolo", function() self:UpdateVisibility() end)
    self:OnGameEvent("UNIT_CONNECTION", function() self:UpdateOffline() end)
    for _, key in ipairs({ "power", "healthText", "nameColor", "raidMarkers", "lowHealth", "incoming", "debuffBadges", "rangeAlpha" }) do
        self:Watch(key, function() self:ApplyOptions(); self:DrawPreview() end)
    end
    self:Watch("debuffBadges", function() self:RunOutOfCombat("badges", function() self:ApplyBadges() end) end)
    -- the preview follows layout changes at once (the real frames wait for
    -- the end of combat)
    for _, key in ipairs({ "width", "height", "gap", "direction", "showSelf", "buffIcons", "debuffIcons", "auraSide" }) do
        self:Watch(key, function() self:DrawPreview() end)
    end

    self:OnGameEvent("PLAYER_TARGET_CHANGED", function() self:UpdateSelected() end)
    self:OnGameEvent("GROUP_ROSTER_UPDATE", function()
        self:UpdateStates(); self:UpdateSelected(); self:UpdateRange(); self:UpdateOffline()
        -- someone changed raid group: "my group" missing looks follow
        for _, f in ipairs(self.frames) do f:UpdateIndicatorPresence() end
        -- indicators limited to some group sizes
        if UI.GroupTier() ~= self.indicatorTier then self:QueueIndicators() end
    end)

    -- the game event: a unit event registers at most two units
    self:OnGameEvent("UNIT_THREAT_SITUATION_UPDATE", function(_, unit)
        for _, f in ipairs(self.frames) do if f.unit == unit then self:UpdateState(f) end end
    end)
    -- "while missing" indicators: read out of combat, hidden in combat
    local function presence(unit)
        for _, f in ipairs(self.frames) do
            if not unit or f.unit == unit then f:UpdateIndicatorPresence() end
        end
    end
    self:OnGameEvent("UNIT_AURA", function(_, unit)
        if not InCombatLockdown() and unit and (unit == "player" or unit:find("^party") or unit:find("^raid")) then presence(unit) end
    end)
    self:OnGameEvent("PLAYER_REGEN_DISABLED", function() C_Timer.After(0, function() presence() end) end)
    self:OnGameEvent("PLAYER_REGEN_ENABLED", function() presence() end)
    -- range has no event worth trusting: a light poll while shown
    self.rangeTicker = C_Timer.NewTicker(0.25, function()
        if self.holder:IsVisible() then self:UpdateRange() end
    end)
end

function M:OnDisable()
    -- Only reached when the module errors: the module toggles on reload.
    SuuUI.PublishAnchor("party", nil)
    if self.rangeTicker then self.rangeTicker:Cancel() end
    if self.frames then
        for _, f in ipairs(self.frames) do
            f:Deactivate()
            UnregisterUnitWatch(f)
            f:Hide()
        end
    end
end
