-- Diagnostics/PartyAuraProbe.lua
-- "/suu probe partyauras": which of a party member's auras each of the
-- party frames' aura groups lets through (the engine's own filter test), and
-- how many icons each frame's aura container shows. Prints in chat and saves
-- to SuuUIProbe.partyAuras. Out of combat.

local _, ns = ...

local PA = {}
ns.PartyAuraProbe = PA

local isSecret = issecretvalue or function() return false end
local function show(v) if isSecret(v) then return "secret" end return tostring(v) end

local FILTERS = {
    dispel = "HARMFUL|RAID_PLAYER_DISPELLABLE",
    external = "HELPFUL|EXTERNAL_DEFENSIVE",
    defensive = "HELPFUL|BIG_DEFENSIVE",
    debuffs = "HARMFUL|!RAID_PLAYER_DISPELLABLE|RAID",
}

local function shownChildren(frame)
    local n = 0
    for _, c in ipairs({ frame:GetChildren() }) do
        if c:IsShown() then n = n + 1 end
    end
    return n
end

function PA.Command()
    if InCombatLockdown() then ns.Print("Party aura probe: out of combat, please.") return end
    SuuUIProbe = SuuUIProbe or {}
    local out = { at = date("%H:%M:%S") }
    SuuUIProbe.partyAuras = out
    local m = SuuUI.GetModule("party")
    for _, unit in ipairs({ "player", "party1", "party2", "party3", "party4" }) do
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
                    local text = ("%s (%s) from %s: %s"):format(show(a.name), show(a.spellId), show(a.sourceUnit), table.concat(parts, " "))
                    line.auras[#line.auras + 1] = text
                    ns.Print(unit .. " " .. show(name) .. " · " .. text)
                end
            end
            -- the frame's container: how many icons it shows
            if m and m.frames then
                for _, f in ipairs(m.frames) do
                    if f.unit == unit and f.auras then
                        line.icons = shownChildren(f.auras.container)
                        line.containerUnit = show(f.auras.unit)
                        ns.Print(("%s frame: %d icons shown, container unit %s"):format(unit, line.icons, line.containerUnit))
                    end
                end
            end
            out[#out + 1] = line
        end
    end
end
