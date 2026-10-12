-- Units/Threat.lua
-- The threat meter and the pull warning (step 1.11). A built-in module
-- written against the public API only.
--
-- The meter: your target's threat table, in combat with a hostile target,
-- left of the damage meter's slot in the bottom right corner (its right edge
-- 292px from the screen's, 28px up), always 8 rows tall. Rows by % (ranked)
-- while the client lets SuuUI compare it; when the % is secret (bosses), by
-- threat state, then group order. The state (UnitThreatSituation) stays
-- readable in combat, so the badges and the warning work everywhere.
--
-- The warning: an amber alert "You're about to pull" while you're over the
-- tank's threat but not yet holding the mob (status 1), with your threat drop
-- if it's ready; in a group, an ember "You have drawn aggro" once you hold it
-- (status 2-3) and aren't the tank. Both go when the reason does.

local UI, T = SuuUI.UI, SuuUI.Tokens

local M = SuuUI.RegisterModule({
    id = "threat",
    name = "Threat meter",
    description = "Your target's threat in combat, and a warning before you pull.",
    api = "0.10",
    defaults = {
        position = { point = "BOTTOMRIGHT", x = -292, y = 28 },
        shown = true,
        who = "group",     -- "group" | "tanks" | "self"
        marker = "role",   -- "role" | "class" | "none"
        raw = false,
        warnPull = true,
    },
})

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
-- cooldown's times are secret in combat, but whether it runs isn't.
local function readyDrop()
    for _, name in ipairs(THREAT_DROPS[playerClass()] or {}) do
        local info = C_Spell.GetSpellInfo(name)
        local id = info and info.spellID
        if id and not isSecret(id) and IsPlayerSpell(id) then
            local cd = C_Spell.GetSpellCooldown(id)
            if cd then
                local active, gcd = cd.isActive, cd.isOnGCD
                if not isSecret(gcd) and gcd then return name end
                if not isSecret(active) and active ~= nil then
                    if not active then return name end
                elseif readable(cd.duration) and cd.duration <= 1.5 then
                    return name
                end
            end
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

function M:Warn(rows)
    if not self:Get("warnPull") then
        SuuUI.HideAlert("threat-pull")
        SuuUI.HideAlert("threat-aggro")
        return
    end
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
    if status == 1 then
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
    elseif status >= 2 and UI.Flag(IsInGroup()) then
        SuuUI.HideAlert("threat-pull")
        SuuUI.ShowAlert("threat-aggro", "danger", "You have drawn aggro", "%s%s", UnitName("target"), dropText)
    else
        SuuUI.HideAlert("threat-pull")
        SuuUI.HideAlert("threat-aggro")
    end
end

function M:Update()
    local active = inCombat() and hostileTarget()
    local wantMeter = active and self:Get("shown") and not self:Get("position").hidden
    if not active then
        self.meter:Hide()
        SuuUI.HideAlert("threat-pull")
        SuuUI.HideAlert("threat-aggro")
        return
    end
    local rows, secret = readRows()
    if wantMeter then
        self.meter:SetTarget(UnitName("target"))
        self.meter:SetRows(rows, self:MeterOpts(secret))
        self.meter:Show()
    else
        self.meter:Hide()
    end
    self:Warn(rows)
end

-- In combat a driver reads the table every TICK (threat moves all the time);
-- out of combat everything goes.
function M:SetRunning(on)
    self.driver:SetShown(on and true or false)
    if on then
        self:Update()
    else
        self.meter:Hide()
        SuuUI.HideAlert("threat-pull")
        SuuUI.HideAlert("threat-aggro")
    end
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

function M:PreviewView(parent)
    if not self.preview then
        self.preview = UI.ThreatMeter(parent, { rows = 8 })
        self.preview:SetTarget("Lava Surger")
    end
    self.preview:SetParent(parent)
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
    return not M:Get("shown"), "Show the threat meter first."
end

local SECTION = {
    id = "threat", label = "Damage & threat", category = "Insights", order = 50,
    preview = function(parent) return M:PreviewView(parent) end,
    previewTitle = "Live preview · Threat",
    previewNote = "Bottom right, left of the damage meter's place, in combat with a hostile target.",
    groups = {
        { title = "Threat meter", description = "Your target, in combat. On bosses the client lets SuuUI show each player's threat but not compare it, so the list orders by threat state.", rows = {
            { key = "shown", label = "Show the threat meter", control = "toggle" },
            { key = "who", label = "Who", control = "segmented", stacked = true, disabled = meterOff,
              options = { { value = "group", label = "Group" }, { value = "tanks", label = "Tanks and me" }, { value = "self", label = "Just me" } } },
            { key = "marker", label = "Before the name", control = "segmented", disabled = meterOff,
              options = { { value = "role", label = "Role icon" }, { value = "class", label = "Class icon" }, { value = "none", label = "None" } } },
            { key = "raw", label = "Raw threat", control = "toggle", disabled = meterOff,
              description = "The threat number before the percent (not on bosses: the client hides it there)." },
            { key = "warnPull", label = "Warn me before I pull", control = "toggle",
              description = "An alert as soon as you pass the tank's threat, and when you've drawn aggro in a group. Works on bosses: it needs only the threat state. Needs the Alerts module." },
        } },
    },
}

function M:OnEnable()
    if not self.meter then
        self.meter = UI.ThreatMeter(SuuUI.Root, { rows = 8 })
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
        enabled = function() return self:Get("shown") end })
    self:RegisterSettings(SECTION)
    self:Watch("shown", SuuUI.EditMode.Refresh)
    for _, key in ipairs({ "who", "marker", "raw" }) do
        self:Watch(key, function() self:RefreshPreview(); if self.driver:IsShown() then self:Update() end end)
    end
    for _, key in ipairs({ "shown", "warnPull", "position" }) do
        self:Watch(key, function() if self.driver:IsShown() then self:Update() end end)
    end
    self:OnGameEvent("PLAYER_REGEN_DISABLED", function() self:SetRunning(true) end)
    self:OnGameEvent("PLAYER_REGEN_ENABLED", function() self:SetRunning(false) end)
    self:OnGameEvent("PLAYER_TARGET_CHANGED", function() if self.driver:IsShown() then self:Update() end end)
    self:SetRunning(inCombat())
end

function M:OnDisable()
    if self.driver then self.driver:Hide() end
    if self.meter then self.meter:Hide() end
    SuuUI.HideAlert("threat-pull")
    SuuUI.HideAlert("threat-aggro")
end
