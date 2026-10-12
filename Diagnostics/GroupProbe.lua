-- Diagnostics/GroupProbe.lua
-- "/suu probe group": what party frames can read about other players, and
-- when (plan step 1.8b). For you, your target and party1-4 it records, per
-- sample, whether each value is readable, secret, nil or an error:
--   range      UnitInRange (both returns)
--   threat     UnitThreatSituation
--   role       UnitGroupRolesAssigned
--   target?    UnitIsUnit(unit, "target")
--   value      AbbreviateNumbers(UnitHealth): can a secret health be shortened?
--   aura IDs   C_UnitAuras.GetUnitAuraInstanceIDs, dispellable debuffs
--   aura data  GetAuraDataByAuraInstanceID / GetAuraDataByIndex
--   dispel     GetAuraDispelTypeColor through a colour curve
-- One sample now; then, while armed, samples 1 and 4 seconds into each fight
-- and one after it. Saved in SuuUIProbe.group on /reload.
--
--   /suu probe group        arm and sample now (solo works: you and your target)
--   /suu probe group off    stop sampling

local _, ns = ...

local Events = ns.Events

local GP = {}
ns.GroupProbe = GP

local isSecret = issecretvalue or function() return false end
local UNITS = { "player", "target", "party1", "party2", "party3", "party4" }
local MAX_SAMPLES = 24
local armed = false

-- One value as text: secret, nil, or readable (with what it was).
local function describe(v)
    if isSecret(v) then return "secret" end
    if v == nil then return "nil" end
    return "readable: " .. tostring(v)
end

-- Calls fn and describes its first (or chosen) returns; errors are kept short.
local function try(fn, ...)
    if type(fn) ~= "function" then return "missing" end
    local ok, a, b = pcall(fn, ...)
    if not ok then return "error: " .. tostring(a):sub(1, 120) end
    if b ~= nil or isSecret(b) then return describe(a) .. " / " .. describe(b) end
    return describe(a)
end

local colorCurve
local function dispelCurve()
    if colorCurve ~= nil then return colorCurve or nil end
    colorCurve = false
    local make = C_CurveUtil and (C_CurveUtil.CreateColorCurve or C_CurveUtil.CreateCurve)
    if make then
        local ok, c = pcall(make)
        if ok and c then colorCurve = c end
    end
    return colorCurve or nil
end

local function sampleUnit(unit)
    if not UnitExists(unit) then return nil end
    local r = {}
    r.name = try(UnitName, unit)
    r.range = try(UnitInRange, unit)
    r.threat = try(UnitThreatSituation, unit)
    r.role = try(UnitGroupRolesAssigned, unit)
    r.isTarget = try(UnitIsUnit, unit, "target")
    -- a secret health, shortened by the game?
    local ok, health = pcall(UnitHealth, unit)
    r.health = ok and describe(health) or "error"
    if ok then
        local ok2, text = pcall(AbbreviateNumbers, health)
        r.abbreviate = ok2 and describe(text) or ("error: " .. tostring(text):sub(1, 120))
    end
    -- auras: instance IDs, their data, their dispel colour
    local okIDs, ids = pcall(C_UnitAuras.GetUnitAuraInstanceIDs, unit, "HARMFUL|RAID_PLAYER_DISPELLABLE")
    if not okIDs then
        r.auraIDs = "error: " .. tostring(ids):sub(1, 120)
    elseif isSecret(ids) then
        r.auraIDs = "secret"
    elseif type(ids) == "table" then
        r.auraIDs = ("readable: %d dispellable"):format(#ids)
        local first = ids[1]
        if first ~= nil then
            r.firstID = describe(first)
            r.auraData = try(C_UnitAuras.GetAuraDataByAuraInstanceID, unit, first)
            local curve = dispelCurve()
            r.dispelColor = curve and try(C_UnitAuras.GetAuraDispelTypeColor, unit, first, curve) or "no colour curve"
        end
    else
        r.auraIDs = describe(ids)
    end
    local okAll, all = pcall(C_UnitAuras.GetUnitAuraInstanceIDs, unit, "HARMFUL")
    r.allDebuffIDs = not okAll and ("error: " .. tostring(all):sub(1, 120))
        or (type(all) == "table" and ("readable: %d"):format(#all)) or describe(all)
    r.byIndex = try(C_UnitAuras.GetAuraDataByIndex, unit, 1, "HARMFUL")
    return r
end

function GP.Sample(label)
    SuuUIProbe = SuuUIProbe or {}
    local store = SuuUIProbe.group or { samples = {} }
    SuuUIProbe.group = store
    local s = {
        at = date("%H:%M:%S"), label = label,
        combat = InCombatLockdown() and "in combat" or "out of combat",
        group = IsInRaid() and "raid" or (IsInGroup() and "party" or "solo"),
        instance = select(2, IsInInstance()) or "none",
        units = {},
    }
    for _, unit in ipairs(UNITS) do s.units[unit] = sampleUnit(unit) end
    table.insert(store.samples, s)
    while #store.samples > MAX_SAMPLES do table.remove(store.samples, 1) end
    return s
end

local function onFight()
    if not armed then return end
    C_Timer.After(1, function() if armed then GP.Sample("1s into the fight") end end)
    C_Timer.After(4, function()
        if armed then
            GP.Sample("4s into the fight")
            ns.Print("Group probe: fight sampled. /reload to save.")
        end
    end)
end

local function afterFight()
    if armed then C_Timer.After(1, function() if armed then GP.Sample("after the fight") end end) end
end

function GP.Command(arg)
    if arg == "off" then
        armed = false
        ns.Print("Group probe: off.")
        return
    end
    if not armed then
        armed = true
        Events.OnGame("PLAYER_REGEN_DISABLED", onFight, GP)
        Events.OnGame("PLAYER_REGEN_ENABLED", afterFight, GP)
    end
    local s = GP.Sample("on command")
    local n = 0
    for _ in pairs(s.units) do n = n + 1 end
    ns.Print(("Group probe: armed (%s, %d units). Fight something with a target; it samples 1s and 4s in. /reload to save."):format(s.group, n))
end
