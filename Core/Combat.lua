-- Core/Combat.lua
-- The combat queue: work that touches protected frames runs now, or waits for
-- the end of combat if the client is in lockdown. Work is keyed, so a later
-- request for the same thing replaces the one waiting (moving a bar twice in a
-- fight moves it once, to the last place).

local _, ns = ...

local Combat = {}
ns.Combat = Combat

local Fault = ns.Fault

local waiting = {}  -- key -> { fn, source }
local order = {}    -- keys, first queued first

-- Runs fn now or after combat. `source` names it in error reports.
function Combat.Run(key, fn, source)
    source = source or tostring(key)
    if not InCombatLockdown() then
        return Fault.Call(source, fn)
    end
    if not waiting[key] then order[#order + 1] = key end
    waiting[key] = { fn = fn, source = source }
end

function Combat.Pending()
    return #order
end

local function flush()
    local i = 1
    while i <= #order do
        if InCombatLockdown() then
            -- Back in combat mid-flush: keep the rest for the next regen.
            local rest = {}
            for j = i, #order do rest[#rest + 1] = order[j] end
            order = rest
            return
        end
        local key = order[i]
        local job = waiting[key]
        waiting[key] = nil
        if job then Fault.Call(job.source, job.fn) end
        i = i + 1
    end
    order = {}
end

ns.Events.OnGame("PLAYER_REGEN_ENABLED", flush, "Combat queue")
