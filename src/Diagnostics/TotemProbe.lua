-- Diagnostics/TotemProbe.lua
-- "/suu probe totems" (on a shaman, asked 2026-10-18: a totem bar in the
-- stance bar's place, the design's TotemBar: earth, fire, water, air, each
-- slot its totem with time left and a drain, or empty). What the client
-- gives: each slot's totem (GetTotemInfo, GetTotemTimeLeft, GetTotemDuration,
-- GetTotemCannotDismiss), which of those are secret in combat (run it again
-- in a fight), how often PLAYER_TOTEM_UPDATE fires, the game's own totem
-- frames (TotemFrame, the multi-cast bar) and the stance bar's forms (Ghost
-- Wolf). "/suu probe totems destroy" tries DestroyTotem on the first slot
-- with a totem (a right click to dismiss), "check" saves what happened.
-- Saved in SuuUIProbe.totems on /reload.

local _, ns = ...

local TP = {}
ns.TotemProbe = TP

local isSecret = issecretvalue or function() return false end

local function show(v)
    if isSecret(v) then return "SECRET" end
    if type(v) == "table" or type(v) == "userdata" then return type(v) end
    return tostring(v)
end

local function call(fn, ...)
    if type(fn) ~= "function" then return "missing" end
    local res = { pcall(fn, ...) }
    if not res[1] then return "error " .. tostring(res[2]):sub(1, 120) end
    local parts = {}
    for i = 2, math.max(2, #res) do parts[#parts + 1] = show(res[i]) end
    return table.concat(parts, ", ")
end

local function frameInfo(name)
    local f = _G[name]
    if not f then return "missing" end
    return ("%s shown=%s visible=%s protected=%s"):format(f:GetObjectType(), tostring(f:IsShown()), tostring(f:IsVisible()), tostring(f:IsProtected()))
end

-- The totem event, counted from the first run on.
local events = { count = 0, slots = {} }
local listener

local function record()
    local out = { at = date("%H:%M:%S"), combat = InCombatLockdown() and true or false }
    local _, class = UnitClass("player")
    out.class, out.level = class, UnitLevel("player")
    out.numSlots = call(GetNumTotemSlots)
    out.maxTotems = tostring(MAX_TOTEMS)
    out.slotConstants = ("earth=%s fire=%s water=%s air=%s"):format(tostring(EARTH_TOTEM_SLOT), tostring(FIRE_TOTEM_SLOT),
        tostring(WATER_TOTEM_SLOT), tostring(AIR_TOTEM_SLOT))
    out.priorities = SHAMAN_TOTEM_PRIORITIES and table.concat(SHAMAN_TOTEM_PRIORITIES, ",") or "missing"
    out.slots = {}
    for slot = 1, 4 do
        local s = {}
        s.info = call(GetTotemInfo, slot)
        s.timeLeft = call(GetTotemTimeLeft, slot)
        s.cannotDismiss = call(GetTotemCannotDismiss, slot)
        local ok, d = pcall(GetTotemDuration, slot)
        s.duration = ok and (d and (type(d) .. (isSecret(d) and " SECRET" or "")) or "nil") or ("error " .. tostring(d):sub(1, 80))
        if ok and d and not isSecret(d) and (type(d) == "table" or type(d) == "userdata") then
            -- what a duration object answers (the cooldown sweep and the drain take it)
            s.durationRemaining = call(d.GetRemainingDuration, d)
            s.durationTotal = call(d.GetTotalDuration, d)
        end
        out.slots[slot] = s
    end
    out.frames = {}
    for _, name in ipairs({ "TotemFrame", "MultiCastActionBarFrame", "MultiCastSlotButton1", "MultiCastSummonSpellButton",
                            "StanceBar", "StanceButton1" }) do
        out.frames[name] = frameInfo(name)
    end
    out.hasMultiCastBar = call(HasMultiCastActionBar)
    out.multiCastActive = tostring(MultiCastActionBarFrame and MultiCastActionBarFrame.numActiveSlots)
    out.multiCastSpells = {}
    for slot = 1, 4 do
        local ok, n = pcall(function() return select("#", GetMultiCastTotemSpells(slot)) end)
        out.multiCastSpells[slot] = ok and n or "error"
    end
    out.forms = call(GetNumShapeshiftForms)
    for i = 1, 10 do
        local ok, icon, active, castable, spellID = pcall(GetShapeshiftFormInfo, i)
        if not ok or not icon then break end
        out["form" .. i] = ("spell=%s active=%s %s"):format(show(spellID), show(active),
            spellID and not isSecret(spellID) and (C_Spell.GetSpellName(spellID) or "") or "")
    end
    out.tooltipSetTotem = GameTooltip.SetTotem and "present" or "missing"
    out.events = { count = events.count, slots = events.slots }
    return out
end

function TP.Command(rest)
    SuuUIProbe = SuuUIProbe or {}
    local all = SuuUIProbe.totems or {}
    SuuUIProbe.totems = all
    if not listener then
        listener = CreateFrame("Frame")
        listener:RegisterEvent("PLAYER_TOTEM_UPDATE")
        listener:SetScript("OnEvent", function(_, _, slot)
            events.count = events.count + 1
            local key = tostring(isSecret(slot) and "secret" or slot)
            events.slots[key] = (events.slots[key] or 0) + 1
        end)
    end
    if rest == "destroy" then
        all.destroy = { at = date("%H:%M:%S"), combat = InCombatLockdown() and true or false }
        for slot = 1, 4 do
            local ok, have = pcall(GetTotemInfo, slot)
            if ok and have and not isSecret(have) then
                all.destroy.slot = slot
                all.destroy.result = call(DestroyTotem, slot)
                break
            end
        end
        all.destroy.slot = all.destroy.slot or "no totem down"
        ns.Print("Totem probe: tried to dismiss a totem. Did it go? Then /suu probe totems check and /reload.")
        return
    end
    if rest == "check" then
        all.check = record()
        all.check.blocked = {}
        for _, e in ipairs(SuuUIDB and SuuUIDB.blocked or {}) do
            if all.destroy and e.time and e.time >= date("%Y-%m-%d ") .. all.destroy.at then
                all.check.blocked[#all.check.blocked + 1] = tostring(e.event) .. " " .. tostring(e.func)
            end
        end
        ns.Print("Totem probe: checked. /reload to save it.")
        return
    end
    local out = record()
    all[out.combat and "inCombat" or "outOfCombat"] = out
    ns.Print(("Totem probe: recorded %s (%s, %d totem events so far). Drop totems and run it again, once in a fight; /reload to save.")
        :format(out.combat and "in combat" or "out of combat", tostring(out.class), events.count))
end
