-- Diagnostics/DeathRecapProbe.lua
-- "/suu probe deathrecap" (asked 2026-10-18: SuuUI's own death recap,
-- design "Death recap" A): after a death, what the game's recap gives for
-- it: whether it has events, the max health, and each event's fields with
-- their values (secret or not), so the window reads the right names (the
-- event's table isn't documented on Forever). Saved in
-- SuuUIProbe.deathRecap on /reload.

local _, ns = ...

local DR = {}
ns.DeathRecapProbe = DR

local isSecret = issecretvalue or function() return false end

local function show(v)
    if isSecret(v) then return "SECRET" end
    return tostring(v)
end

function DR.Command()
    SuuUIProbe = SuuUIProbe or {}
    local out = { at = date("%H:%M:%S"), combat = InCombatLockdown() and true or false, dead = UnitIsDeadOrGhost("player") and true or false }
    local api = C_DeathRecap
    if not api then
        out.api = "missing"
    else
        local okH, has = pcall(api.HasRecapEvents)
        out.hasEvents = okH and show(has) or "error"
        local okM, maxHP = pcall(api.GetRecapMaxHealth)
        out.maxHealth = okM and show(maxHP) or "error"
        local okL, link = pcall(api.GetRecapLink)
        out.link = okL and show(link) or "error"
        local okE, events = pcall(api.GetRecapEvents)
        out.secretTable = okE and issecrettable and issecrettable(events) and true or false
        out.events = {}
        if okE and type(events) == "table" and not out.secretTable then
            for i, e in ipairs(events) do
                if i > 6 then break end
                local fields = {}
                for k, v in pairs(e) do fields[#fields + 1] = tostring(k) .. "=" .. show(v) end
                table.sort(fields)
                out.events[i] = table.concat(fields, "  ")
            end
        end
    end
    SuuUIProbe.deathRecap = out
    ns.Print(("Death recap probe: %s events, max health %s. /reload to save it."):format(tostring(out.hasEvents), tostring(out.maxHealth)))
end
