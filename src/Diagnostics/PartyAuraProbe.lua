-- Diagnostics/PartyAuraProbe.lua
-- "/suu probe partyauras": which of a party member's (and your target's)
-- auras each of the party frames' and the target frame's aura groups lets
-- through (the engine's own filter test, and the lists the containers
-- take), and
-- how many icons each frame's aura container shows. Prints in chat and saves
-- to SuuUIProbe.partyAuras. Out of combat.

local _, ns = ...

local PA = {}
ns.PartyAuraProbe = PA

local isSecret = issecretvalue or function() return false end
local function show(v) if isSecret(v) then return "secret" end return tostring(v) end

local FILTERS = {
    dispel = "HARMFUL|RAID_PLAYER_DISPELLABLE",
    external = "HELPFUL|EXTERNAL_DEFENSIVE|!BIG_DEFENSIVE",
    defensive = "HELPFUL|BIG_DEFENSIVE",
    debuffs = "HARMFUL|!RAID_PLAYER_DISPELLABLE|RAID",
    -- the target frame's (Auras module): yours, then everyone else's
    tMine = "HARMFUL|PLAYER",
    tMyBuffs = "HELPFUL|PLAYER",
    tTheirs = "HARMFUL|!PLAYER",
    tTheirBuffs = "HELPFUL|!PLAYER",
    -- does "!" work at all: a filter no aura can pass, negated
    notCancel = "HELPFUL|!CANCELABLE",
    cancel = "HELPFUL|CANCELABLE",
}

-- The containers don't ask per aura: they take the list a filter gives
-- (GetUnitAuraInstanceIDs). The same filters, asked that way, plus the
-- plain and single-token ones to see which token lets what through.
local LISTS = {
    { "helpful", "HELPFUL" },
    { "harmful", "HARMFUL" },
    { "external", "HELPFUL|EXTERNAL_DEFENSIVE" },
    { "externalNotBig", "HELPFUL|EXTERNAL_DEFENSIVE|!BIG_DEFENSIVE" },
    { "big", "HELPFUL|BIG_DEFENSIVE" },
    { "notExternal", "HELPFUL|!EXTERNAL_DEFENSIVE" },
    { "partyBuffs", "HELPFUL|!EXTERNAL_DEFENSIVE|!BIG_DEFENSIVE" },
    { "raidBuffs", "HELPFUL|RAID" },
    { "dispel", "HARMFUL|RAID_PLAYER_DISPELLABLE" },
    { "debuffs", "HARMFUL|!RAID_PLAYER_DISPELLABLE|RAID" },
    { "tMine", "HARMFUL|PLAYER" },
    { "tMyBuffs", "HELPFUL|PLAYER" },
    { "tTheirs", "HARMFUL|!PLAYER" },
    { "tTheirBuffs", "HELPFUL|!PLAYER" },
}

local function auraName(unit, id)
    local ok, a = pcall(C_UnitAuras.GetAuraDataByAuraInstanceID, unit, id)
    if not ok or not a then return "#" .. show(id) end
    return ("%s (%s%s)"):format(show(a.name), show(a.spellId), a.isHarmful == true and ", harmful" or "")
end

local function lists(unit)
    local out = {}
    for _, l in ipairs(LISTS) do
        local ok, ids = pcall(C_UnitAuras.GetUnitAuraInstanceIDs, unit, l[2])
        local names = {}
        if ok and type(ids) == "table" then
            for _, id in ipairs(ids) do names[#names + 1] = auraName(unit, id) end
        end
        local text = l[1] .. ": " .. (ok and (#names > 0 and table.concat(names, ", ") or "none") or ("error " .. tostring(ids)))
        out[#out + 1] = text
    end
    return out
end

local function shownChildren(frame)
    -- the engine's buttons answer IsShown with a secret: those count as "?"
    local n, unknown = 0, 0
    for _, c in ipairs({ frame:GetChildren() }) do
        local shown = c:IsShown()
        if isSecret(shown) then unknown = unknown + 1 elseif shown then n = n + 1 end
    end
    return n, unknown
end

function PA.Command()
    if InCombatLockdown() then ns.Print("Party aura probe: out of combat, please.") return end
    SuuUIProbe = SuuUIProbe or {}
    local out = { at = date("%H:%M:%S") }
    SuuUIProbe.partyAuras = out
    local m = SuuUI.GetModule("party")
    for _, unit in ipairs({ "player", "party1", "party2", "party3", "party4", "target" }) do
        if UnitExists(unit) then
            local name = UnitName(unit)
            local line = { unit = unit, name = show(name), auras = {} }
            for _, base in ipairs({ "HELPFUL", "HARMFUL" }) do
                for i = 1, 40 do
                    local ok, a = pcall(C_UnitAuras.GetAuraDataByIndex, unit, i, base)
                    if not ok or not a then break end
                    local parts = {}
                    for key, filter in pairs(FILTERS) do
                        local ok2, out2 = pcall(C_UnitAuras.IsAuraFilteredOutByInstanceID, unit, a.auraInstanceID, filter)
                        parts[#parts + 1] = key .. "=" .. (ok2 and (out2 and "out" or "IN") or "err")
                    end
                    table.sort(parts)
                    local text = ("%s (%s) from %s, mine %s: %s"):format(show(a.name), show(a.spellId), show(a.sourceUnit),
                        show(a.isFromPlayerOrPlayerPet), table.concat(parts, " "))
                    line.auras[#line.auras + 1] = text
                    ns.Print(unit .. " " .. show(name) .. " · " .. text)
                end
            end
            line.lists = lists(unit)
            -- (saved only: 14 lines a unit would flood the chat)
            -- the frame's container: how many icons it shows
            if m and m.frames then
                for _, f in ipairs(m.frames) do
                    local ac = f.unit == unit and f.auras
                    if ac then
                        local n, unknown = shownChildren(ac.container)
                        line.icons, line.unknown = n, unknown
                        line.containerUnit = show(ac.unit)
                        ns.Print(("%s frame: %d icons shown (%d secret), container unit %s"):format(unit, n, unknown, line.containerUnit))
                    end
                end
            end
            out[#out + 1] = line
        end
    end
end
