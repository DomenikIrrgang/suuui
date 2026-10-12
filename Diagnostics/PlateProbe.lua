-- Diagnostics/PlateProbe.lua
-- "/suu probe plates": what nameplates allow on Forever (plan step 1.10),
-- before SuuUI builds its own. Per sample, for every visible nameplate:
-- whether the plate and Blizzard's unit frame on it are forbidden, whether
-- the unit is attackable, and which values are readable, secret or missing
-- (health, name, threat on you, "is it your target?", a cast). Once: the
-- nameplate APIs and enums SuuUI would use, the nameplate CVars, and other
-- nameplate addons that are loaded (two would fight over the plates).
-- One sample now; while armed, 1 and 4 seconds into each fight and after it.
-- Saved in SuuUIProbe.plates on /reload.
--
--   /suu probe plates        arm and sample now (stand near mobs or players)
--   /suu probe plates off    stop sampling

local _, ns = ...

local Events = ns.Events

local PP = {}
ns.PlateProbe = PP

local isSecret = issecretvalue or function() return false end
local MAX_SAMPLES = 12
local armed = false

local function describe(v)
    if isSecret(v) then return "secret" end
    if v == nil then return "nil" end
    return "readable: " .. tostring(v)
end

local function try(fn, ...)
    if type(fn) ~= "function" then return "missing" end
    local ok, a, b = pcall(fn, ...)
    if not ok then return "error: " .. tostring(a):sub(1, 120) end
    if b ~= nil or isSecret(b) then return describe(a) .. " / " .. describe(b) end
    return describe(a)
end

local function forbidden(frame)
    if not frame then return "none" end
    local ok, f = pcall(frame.IsForbidden, frame)
    if not ok then return "error" end
    return f and "forbidden" or "ok"
end

-- The APIs, enums and CVars SuuUI's plates would use.
local function environment()
    local env = {}
    local function has(name, value) env[name] = value ~= nil and (type(value) == "function" and "function" or "present") or "missing" end
    has("C_NamePlate.GetNamePlateForUnit", C_NamePlate and C_NamePlate.GetNamePlateForUnit)
    has("C_NamePlate.GetNamePlates", C_NamePlate and C_NamePlate.GetNamePlates)
    has("C_NamePlate.SetNamePlateSize", C_NamePlate and C_NamePlate.SetNamePlateSize)
    has("C_NamePlateManager", C_NamePlateManager)
    has("C_NamePlateManager.SetNamePlateHitTestInsets", C_NamePlateManager and C_NamePlateManager.SetNamePlateHitTestInsets)
    has("Enum.NamePlateType", Enum.NamePlateType)
    has("Enum.NamePlateStackType", Enum.NamePlateStackType)
    has("NamePlateDriverFrame", NamePlateDriverFrame)
    has("NamePlateDriverFrame.OnNamePlateAdded", NamePlateDriverFrame and NamePlateDriverFrame.OnNamePlateAdded)
    has("UnitCastingDuration", UnitCastingDuration)
    has("UnitChannelDuration", UnitChannelDuration)
    has("C_CurveUtil.EvaluateColorValueFromBoolean", C_CurveUtil and C_CurveUtil.EvaluateColorValueFromBoolean)
    has("C_Secrets.ShouldAurasBeSecret", C_Secrets and C_Secrets.ShouldAurasBeSecret)
    for _, cvar in ipairs({ "nameplateShowAll", "nameplateShowEnemies", "nameplateShowFriends", "nameplateSize",
                            "nameplateMaxDistance", "nameplateOverlapV", "nameplateMinAlpha", "nameplateMaxAlpha",
                            "nameplateShowFriendlyNPCs", "nameplateMotion" }) do
        local ok, v = pcall(C_CVar.GetCVar, cvar)
        env["cvar " .. cvar] = ok and tostring(v) or "missing"
    end
    -- other nameplate addons: two would fight over the same plates
    local loaded = {}
    for _, name in ipairs({ "EllesmereUINameplates", "Plater", "Kui_Nameplates", "TidyPlates_ThreatPlates", "Platynator", "NeatPlates" }) do
        if C_AddOns.IsAddOnLoaded(name) then loaded[#loaded + 1] = name end
    end
    env.otherPlateAddons = #loaded > 0 and table.concat(loaded, ", ") or "none"
    return env
end

local function samplePlate(unit)
    local plate = C_NamePlate.GetNamePlateForUnit(unit)
    local r = {}
    r.plate = forbidden(plate)
    if plate and r.plate == "ok" then
        local uf = plate.UnitFrame
        r.unitFrame = forbidden(uf)
        r.stackingBounds = plate.SetStackingBoundsFrame and "function" or "missing"
    end
    r.name = try(UnitName, unit)
    r.attackable = try(UnitCanAttack, "player", unit)
    r.health = try(UnitHealth, unit)
    r.healthPercent = (UnitHealthPercent and CurveConstants) and try(UnitHealthPercent, unit, true, CurveConstants.ScaleTo100) or "missing"
    r.threatOnYou = try(UnitThreatSituation, "player", unit)
    r.isTarget = try(UnitIsUnit, unit, "target")
    r.reaction = try(UnitReaction, unit, "player")
    local okCast, castName, _, _, _, _, _, _, notInterruptible = pcall(UnitCastingInfo, unit)
    r.casting = not okCast and "error" or (isSecret(castName) and "secret" or (castName and ("readable: " .. castName) or "none"))
    if okCast and castName ~= nil then r.castInterruptible = describe(notInterruptible) end
    r.castDuration = UnitCastingDuration and try(UnitCastingDuration, unit) or "missing"
    return r
end

function PP.Sample(label)
    SuuUIProbe = SuuUIProbe or {}
    local store = SuuUIProbe.plates or { samples = {} }
    SuuUIProbe.plates = store
    store.environment = environment()
    local s = {
        at = date("%H:%M:%S"), label = label,
        combat = InCombatLockdown() and "in combat" or "out of combat",
        instance = select(2, IsInInstance()) or "none",
        group = IsInRaid() and "raid" or (IsInGroup() and "party" or "solo"),
        plates = {},
    }
    local count = 0
    for i = 1, 40 do
        local unit = "nameplate" .. i
        if UnitExists(unit) then
            s.plates[unit] = samplePlate(unit)
            count = count + 1
            if count >= 8 then break end
        end
    end
    s.count = count
    table.insert(store.samples, s)
    while #store.samples > MAX_SAMPLES do table.remove(store.samples, 1) end
    return s
end

local function onFight()
    if not armed then return end
    C_Timer.After(1, function() if armed then PP.Sample("1s into the fight") end end)
    C_Timer.After(4, function()
        if armed then
            PP.Sample("4s into the fight")
            ns.Print("Plate probe: fight sampled. /reload to save.")
        end
    end)
end

local function afterFight()
    if armed then C_Timer.After(1, function() if armed then PP.Sample("after the fight") end end) end
end

function PP.Command(arg)
    if arg == "off" then
        armed = false
        ns.Print("Plate probe: off.")
        return
    end
    if not armed then
        armed = true
        Events.OnGame("PLAYER_REGEN_DISABLED", onFight, PP)
        Events.OnGame("PLAYER_REGEN_ENABLED", afterFight, PP)
    end
    local s = PP.Sample("on command")
    ns.Print(("Plate probe: armed (%d plates now). Fight something (a caster if you can), then /reload."):format(s.count))
end
