-- Diagnostics/GarbageProbe.lua
-- "/suu probe garbage" (asked 2026-10-18: SuuUI makes about 0.5 MB of
-- garbage a second, most of it outside the module calls /suu perf counts):
-- what each of SuuUI's frequent jobs allocates per call. Each job runs a
-- few times with the garbage collector held, and Lua's memory count before
-- and after gives its allocation exactly; how often each runs comes from a
-- dev build's profiler (/suu perf), so together they give KB a second.
-- Jobs that can't be found (a module off) are skipped. Saved in
-- SuuUIProbe.garbage on /reload.

local _, ns = ...

local GP = {}
ns.GarbageProbe = GP

local RUNS = 10

local function mod(id)
    local m = ns.Modules and ns.Modules.Get(id)
    return m and m.IsEnabled and m:IsEnabled() and m or nil
end

-- The action buttons SuuUI made (bars 1-8).
local function actionButtons()
    local out = {}
    for bar = 1, 8 do
        for i = 1, 12 do
            local b = _G["SuuUIActionBar" .. bar .. "Button" .. i]
            if b then out[#out + 1] = b end
        end
    end
    return out
end

local function eachMethod(list, method)
    return function()
        for _, b in ipairs(list) do
            if b[method] then b[method](b) end
        end
    end
end

-- name = { fn, what one call is }
local function jobs()
    local out = {}
    local function add(name, fn, unit) if fn then out[#out + 1] = { name = name, fn = fn, unit = unit or "call" } end end
    local buttons = actionButtons()
    if #buttons > 0 then
        for _, method in ipairs({ "UpdateCooldown", "UpdateUsable", "UpdateActive", "UpdateArt", "UpdateEmpty", "UpdateCount", "UpdateHotkey", "Update" }) do
            add("ActionButton:" .. method, eachMethod(buttons, method), #buttons .. " buttons")
        end
    end
    local stance = _G.SuuUIStanceBar
    if stance and stance.buttons then add("Stance button Update", eachMethod(stance.buttons, "Update"), #stance.buttons .. " buttons") end
    local chat = mod("chat")
    if chat then
        add("Chat:Tick", function() chat:Tick() end)
        add("Chat:UpdateTabs", function() chat:UpdateTabs() end)
    end
    local threat = mod("threat")
    if threat then add("Threat:Update", function() threat:Update() end) end
    local micro = mod("micromenu")
    if micro then add("MicroMenu:UpdateActive", function() micro:UpdateActive() end) end
    local notes = mod("notifications")
    if notes then add("Notifications:Tick", function() notes:Tick() end) end
    local tracker = mod("tracker")
    if tracker then
        add("ObjectiveTracker:Refresh", function() tracker:Refresh() end)
        add("ObjectiveTracker:TickItems", function() tracker:TickItems() end)
    end
    local ready = mod("readiness")
    if ready then add("Readiness:Update", function() ready:Update() end) end
    local cds = mod("cooldowns")
    if cds and cds.tracker then
        add("CooldownTracker:UpdateCooldowns", function() cds.tracker:UpdateCooldowns(true) end)
        add("CooldownManager:Lists", function() cds:Lists(cds:EditSpec()) end)
    end
    local party = mod("party")
    if party then add("Party:UpdateRange", function() party:UpdateRange() end) end
    local raid = mod("raid")
    if raid then add("Raid:UpdateRange", function() raid:UpdateRange() end) end
    local swing = _G.SuuUISwingTimer
    if swing and swing.Tick then add("SwingTimer:Tick", function() swing:Tick() end) end
    for _, name in ipairs({ "SuuUIPlayerFrame", "SuuUITargetFrame", "SuuUITargetTargetFrame" }) do
        local f = _G[name]
        if f and f.UpdateHealth then
            add(name .. ":UpdateHealth", function() f:UpdateHealth(true) end)
            add(name .. ":UpdatePower", function() f:UpdatePower() end)
        end
    end
    -- the settings: a position (a table, copied) and a number
    add("Settings.Get (table)", function() ns.Settings.Get("unitframes", "playerPosition") end)
    add("Settings.Get (number)", function() ns.Settings.Get("cooldowns", "essentialSize") end)
    return out
end

function GP.Command()
    local out = { at = date("%Y-%m-%d %H:%M:%S"), inCombat = InCombatLockdown() and true or false, jobs = {} }
    local rows = {}
    collectgarbage("collect")
    collectgarbage("stop")
    for _, job in ipairs(jobs()) do
        -- one run first: a job's first call may build what it then keeps
        local ok, err = pcall(job.fn)
        if not ok then
            rows[#rows + 1] = { name = job.name, line = job.name .. ": error " .. tostring(err):sub(1, 120), kb = -1 }
        else
            local before = collectgarbage("count")
            for _ = 1, RUNS do pcall(job.fn) end
            local per = (collectgarbage("count") - before) / RUNS
            rows[#rows + 1] = { name = job.name, kb = per,
                line = ("%s: %.2f KB a call (%s)"):format(job.name, per, job.unit) }
        end
    end
    collectgarbage("restart")
    table.sort(rows, function(a, b) return a.kb > b.kb end)
    for i, r in ipairs(rows) do out.jobs[i] = r.line end
    SuuUIProbe = SuuUIProbe or {}
    SuuUIProbe.garbage = out
    ns.Print(("Garbage probe: %d jobs measured. /reload to save it."):format(#rows))
    for i = 1, math.min(6, #rows) do ns.Print("  " .. rows[i].line) end
end
