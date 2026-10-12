-- Units/Threat.lua
-- The threat meter and the pull warning (step 1.11). A built-in module
-- written against the public API only.
--
-- The meter: your target's threat table, in combat with a hostile target
-- (Show "In combat"; "Always" keeps it on screen, empty without one),
-- left of the damage meter in the bottom right corner (its right edge 292px
-- from the screen's, 28px up), as tall as the damage meter (its Rows; 8
-- while that module is off). Rows by % (ranked)
-- while the client lets SuuUI compare it; when the % is secret (bosses), by
-- threat state, then group order. The state (UnitThreatSituation) stays
-- readable in combat, so the badges and the warning work everywhere.
--
-- The warning: an amber alert "You're about to pull" while you're over the
-- tank's threat but not yet holding the mob (status 1), with your threat drop
-- if it's ready; an ember "You have drawn aggro" once you hold it (status
-- 2-3) and aren't the tank: in a group, or (setting) while your pet is on the
-- mob's threat table, so a hunter or warlock pulling off the pet hears it.
-- Both go when the reason does.

local UI, T = SuuUI.UI, SuuUI.Tokens

local M = SuuUI.RegisterModule({
    id = "threat",
    name = "Threat meter",
    description = "Your target's threat in combat, and a warning before you pull.",
    api = "0.10",
    defaults = {
        position = { point = "BOTTOMRIGHT", x = -292, y = 28 },
        shows = "combat",  -- "off" | "combat" | "always"
        who = "group",     -- "group" | "tanks" | "self"
        marker = "role",   -- "role" | "class" | "none"
        raw = false,
        warnPull = true,
        aggroAlert = "pet", -- "off" | "group" | "pet" (in a group, or with your pet on the mob)
    },
})

-- The toggle "Show the threat meter" became the choice Show: Off / In combat / Always.
M:Migrate("shows", function(values)
    if type(values.shown) == "boolean" then
        values.shows = values.shown and "combat" or "off"
    end
    values.shown = nil
end)

local isSecret = issecretvalue or function() return false end
local function readable(v) return not isSecret(v) and type(v) == "number" end
local TICK = 0.2

-- What saves you from a mob you pulled, by class (the first one ready shows).
local THREAT_DROPS = {
    HUNTER = { "Feign Death" },
    ROGUE = { "Feint", "Vanish" },
    PRIEST = { "Fade" },
    MAGE = { "Ice Block" },
    DRUID = { "Cower" },
    PALADIN = { "Divine Shield" },
}

local function playerClass()
    local _, class = UnitClass("player")
    return class
end

-- The first threat drop you know and can use now, by name, or nil. A
-- cooldown's times are secret in combat, but whether it runs (isActive)
-- isn't. This client has no isOnGCD, and the global cooldown makes every
-- spell read as running: while it runs (spell 29515, Forever's GCD
-- reference) each drop keeps what it read before it started.
local GCD_SPELL = 29515
local dropReady = {}

local function running(id)
    local cd = C_Spell.GetSpellCooldown(id)
    if not cd then return nil end
    local active = cd.isActive
    if not isSecret(active) and active ~= nil then return active and true or false end
    if readable(cd.duration) then return cd.duration > 0 end
    return nil
end

local function readyDrop()
    local gcd = running(GCD_SPELL)
    for _, name in ipairs(THREAT_DROPS[playerClass()] or {}) do
        local info = C_Spell.GetSpellInfo(name)
        local id = info and info.spellID
        if id and not isSecret(id) and IsPlayerSpell(id) then
            if not gcd or dropReady[name] == nil then
                local r = running(id)
                if r ~= nil then dropReady[name] = not r end
            end
            if dropReady[name] then return name end
        end
    end
end

--------------------------------------------------------------------------------
-- Reading the threat table
--------------------------------------------------------------------------------

local function roleOf(unit)
    if unit == "player" then return SuuUI.Role() end
    local role = UnitGroupRolesAssigned(unit)
    if isSecret(role) or role == "NONE" then return nil end
    return role
end

-- One unit's row, or nil while it isn't on the target's threat table.
local function sample(unit, pet)
    if not UnitExists(unit) then return nil end
    local status = UnitThreatSituation(unit, "target")
    if isSecret(status) then status = nil end
    local ok, _, _, scaled, _, value = pcall(UnitDetailedThreatSituation, unit, "target")
    if not ok then return nil end
    -- off the table: no status and no % (a secret % may still be someone's)
    if status == nil and not isSecret(scaled) and scaled == nil then return nil end
    local _, class = UnitClass(unit)
    if isSecret(class) then class = nil end
    return {
        name = UnitName(unit), class = (not pet) and class or nil,
        role = pet and "PET" or roleOf(unit), status = status,
        percent = scaled, raw = value, you = unit == "player", unit = unit,
    }
end

-- Every row of the group (you first, pets after their owners), and whether
-- any % is secret.
local function readRows()
    local rows, secret = {}, false
    local function add(unit, pet)
        local r = sample(unit, pet)
        if r then
            rows[#rows + 1] = r
            if isSecret(r.percent) then secret = true end
        end
    end
    add("player")
    add("pet", true)
    if UI.Flag(IsInRaid()) then
        for i = 1, 40 do
            local u = "raid" .. i
            if UnitExists(u) and not UI.Flag(UnitIsUnit(u, "player")) then
                add(u)
                add("raidpet" .. i, true)
            end
        end
    else
        for i = 1, 4 do
            add("party" .. i)
            add("partypet" .. i, true)
        end
    end
    return rows, secret
end

--------------------------------------------------------------------------------
-- The meter and the warning
--------------------------------------------------------------------------------

local function hostileTarget()
    return UnitExists("target") and UI.Flag(UnitCanAttack("player", "target")) and not UI.Flag(UnitIsDeadOrGhost("target"))
end

local function inCombat()
    return InCombatLockdown() or UI.Flag(UnitAffectingCombat("player"))
end

function M:MeterOpts(byState)
    return { show = self:Get("who"), marker = self:Get("marker"), raw = self:Get("raw"), byState = byState }
end

-- Whether the aggro alert applies: in a group, or with your pet on the mob.
function M:AggroApplies(rows)
    local mode = self:Get("aggroAlert")
    if mode == "off" then return false end
    if UI.Flag(IsInGroup()) then return true end
    if mode ~= "pet" then return false end
    for _, r in ipairs(rows) do
        if r.unit == "pet" then return true end
    end
    return false
end

function M:Warn(rows)
    local me
    for _, r in ipairs(rows) do if r.you then me = r end end
    local status = me and me.status
    local tank = me and me.role == "TANK"
    if not readable(status) or tank then
        SuuUI.HideAlert("threat-pull")
        SuuUI.HideAlert("threat-aggro")
        return
    end
    local drop = readyDrop()
    local dropText = drop and (" · " .. drop .. " ready") or ""
    if status == 1 and self:Get("warnPull") then
        SuuUI.HideAlert("threat-aggro")
        -- whoever holds the mob: the first other row at 2-3
        local holder
        for _, r in ipairs(rows) do
            if not r.you and readable(r.status) and r.status >= 2 then holder = r break end
        end
        if holder then
            SuuUI.ShowAlert("threat-pull", "warning", "You're about to pull", "%s · over %s's threat%s",
                UnitName("target"), holder.name, dropText)
        else
            SuuUI.ShowAlert("threat-pull", "warning", "You're about to pull", "%s%s", UnitName("target"), dropText)
        end
    elseif status >= 2 and self:AggroApplies(rows) then
        SuuUI.HideAlert("threat-pull")
        SuuUI.ShowAlert("threat-aggro", "danger", "You have drawn aggro", "%s%s", UnitName("target"), dropText)
    else
        SuuUI.HideAlert("threat-pull")
        SuuUI.HideAlert("threat-aggro")
    end
end

function M:Update()
    local hostile = hostileTarget()
    local fighting = hostile and inCombat()
    local shows = self:Get("shows")
    local wantMeter = not self:Get("position").hidden and (shows == "always" or (shows == "combat" and fighting))
    local rows, secret = {}, false
    if hostile then rows, secret = readRows() end
    if wantMeter then
        -- the name may be secret: passed on, never tested
        if hostile then self.meter:SetTarget(UnitName("target")) else self.meter:SetTarget(nil) end
        self.meter:SetRows(rows, self:MeterOpts(secret))
        self.meter:Show()
    else
        self.meter:Hide()
    end
    if fighting then
        self:Warn(rows)
    else
        SuuUI.HideAlert("threat-pull")
        SuuUI.HideAlert("threat-aggro")
    end
end

-- A driver reads the table every TICK (threat moves all the time) in combat,
-- and out of combat too while the meter always shows.
function M:Refresh()
    self.driver:SetShown(inCombat() or self:Get("shows") == "always")
    self:Update()
end

--------------------------------------------------------------------------------
-- Settings and the preview
--------------------------------------------------------------------------------

local SAMPLE = {
    { name = "Brannoc", class = "WARRIOR", role = "TANK", status = 2, percent = 100, raw = 1842000 },
    { name = "Morrow", class = "ROGUE", role = "DAMAGER", status = 1, percent = 93, raw = 1931000 },
    { name = "Lisset", class = "MAGE", role = "DAMAGER", status = 0, percent = 70, raw = 1674000 },
    { name = "Vosk", class = "WARRIOR", role = "DAMAGER", status = 0, percent = 66, raw = 1336000 },
    { name = "Hadrin", class = "WARRIOR", role = "TANK", status = 0, percent = 58, raw = 1173000 },
    { name = "Veyra", class = "SHAMAN", role = "HEALER", status = 0, percent = 21, raw = 502000 },
}

-- The damage meter's Rows, so both meters are the same height.
local function meterRows()
    local dm = SuuUI.GetModule("damagemeter")
    return dm and dm:Get("rows") or 8
end

function M:PreviewView(parent)
    if not self.preview then
        self.preview = UI.ThreatMeter(parent, { rows = meterRows() })
        self.preview:SetTarget("Lava Surger")
    end
    self.preview:SetParent(parent)
    self.preview:SetMaxRows(meterRows())
    self:RefreshPreview()
    return self.preview
end

function M:RefreshPreview()
    if not self.preview then return end
    -- you: the healer, or yourself by name with your class
    local rows = {}
    for i, r in ipairs(SAMPLE) do
        local copy = {}
        for k, v in pairs(r) do copy[k] = v end
        copy.you = i == #SAMPLE
        rows[i] = copy
    end
    self.preview:SetRows(rows, self:MeterOpts(false))
end

local function meterOff()
    return M:Get("shows") == "off", "Show the threat meter first."
end

local SECTION = {
    id = "threat", label = "Damage & threat", category = "Insights", order = 50, merge = "damagemeter",
    preview = function(parent) return M:PreviewView(parent) end,
    previewTitle = "Live preview · Threat",
    previewNote = "Bottom right, left of the damage meter's place.",
    groups = {
        { title = "Threat meter", description = "Your target, in combat. On bosses the client lets SuuUI show each player's threat but not compare it, so the list orders by threat state.", rows = {
            { key = "shows", label = "Show", control = "segmented", stacked = true,
              options = { { value = "off", label = "Off" }, { value = "combat", label = "In combat" }, { value = "always", label = "Always" } },
              description = "In combat: while you fight a hostile target. Always: on screen all the time, empty without a hostile target." },
            { key = "who", label = "Who", control = "segmented", stacked = true, disabled = meterOff,
              options = { { value = "group", label = "Group" }, { value = "tanks", label = "Tanks and me" }, { value = "self", label = "Just me" } } },
            { key = "marker", label = "Before the name", control = "segmented", disabled = meterOff,
              options = { { value = "role", label = "Role icon" }, { value = "class", label = "Class icon" }, { value = "none", label = "None" } } },
            { key = "raw", label = "Raw threat", control = "toggle", disabled = meterOff,
              description = "The threat number before the percent (not on bosses: the client hides it there)." },
            { key = "warnPull", label = "Warn me before I pull", control = "toggle",
              description = "An alert as soon as you pass the tank's (or your pet's) threat. Works on bosses: it needs only the threat state. Needs the Alerts module." },
            { key = "aggroAlert", label = "When I draw aggro", control = "segmented", stacked = true,
              options = { { value = "off", label = "Off" }, { value = "group", label = "In a group" }, { value = "pet", label = "In a group or with my pet" } },
              description = "An ember alert once a mob turns to you and you aren't the tank. With my pet: also solo, while your pet is on the mob (not when you open on it before your pet arrives)." },
        } },
    },
}

function M:OnEnable()
    if not self.meter then
        self.meter = UI.ThreatMeter(SuuUI.Root, { rows = meterRows() })
        self.meter:SetFrameStrata("MEDIUM")
        self.meter:Hide()
        self.driver = CreateFrame("Frame")
        self.driver:Hide()
        local wait = 0
        self.driver:SetScript("OnUpdate", function(_, elapsed)
            wait = wait - elapsed
            if wait > 0 then return end
            wait = TICK
            self:Update()
        end)
    end
    self.meter.suuManagedShow = true
    self:RegisterMover(self.meter, { key = "position", label = "Threat meter",
        enabled = function() return self:Get("shows") ~= "off" end })
    self:RegisterSettings(SECTION)
    self:Watch("shows", function() SuuUI.EditMode.Refresh(); self:Refresh() end)
    for _, key in ipairs({ "who", "marker", "raw" }) do
        self:Watch(key, function() self:RefreshPreview(); if self.driver:IsShown() then self:Update() end end)
    end
    for _, key in ipairs({ "warnPull", "aggroAlert", "position" }) do
        self:Watch(key, function() if self.driver:IsShown() then self:Update() end end)
    end
    -- as tall as the damage meter
    self.meter:SetMaxRows(meterRows())
    self:On("SUUUI_SETTING_CHANGED", function(_, namespace, key)
        if namespace == "damagemeter" and key == "rows" then
            self.meter:SetMaxRows(meterRows())
            if self.preview then self.preview:SetMaxRows(meterRows()); self:RefreshPreview() end
            if self.driver:IsShown() then self:Update() end
        end
    end)
    self:OnGameEvent("PLAYER_REGEN_DISABLED", function() self:Refresh() end)
    self:OnGameEvent("PLAYER_REGEN_ENABLED", function() self:Refresh() end)
    self:OnGameEvent("PLAYER_TARGET_CHANGED", function() if self.driver:IsShown() then self:Update() end end)
    self:Refresh()
end

function M:OnDisable()
    if self.driver then self.driver:Hide() end
    if self.meter then self.meter:Hide() end
    SuuUI.HideAlert("threat-pull")
    SuuUI.HideAlert("threat-aggro")
end
