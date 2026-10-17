-- Core/Perf.lua
-- "/suu perf" (plan 4.2): how much time each SuuUI module takes. The game
-- measures only whole addons, so SuuUI times its own work: every module's
-- events, setting watchers, timers and commands run through Fault.Call,
-- which, while measuring, adds each call's own time (nested calls taken
-- out) to its module, and the memory each call allocated (what later
-- becomes garbage, unless kept). Frame scripts a module sets itself
-- (OnUpdate) aren't counted. Memory in use is the whole addon's (the game
-- can't split it); besides, SuuUI's memory at the start and at the report,
-- and how often it was collected in between, show the garbage it makes.
--   /suu perf         start measuring; again: the report so far
--   /suu perf stop    the report, and stop measuring
-- The report goes to the chat and to SuuUIProbe.perf (on /reload).

local _, ns = ...

local Fault = ns.Fault

local Perf = {}
ns.Perf = Perf

local startedAt, startKB
local TOP = 12

-- All SuuUI allocates, frame scripts included: its memory once a second,
-- each rise added up (a fall is a collection). Rises within a second that a
-- collection then undoes go unseen, so it reads low too.
local sampler, lastKB, risenKB, collections

local function memory()
    if UpdateAddOnMemoryUsage then pcall(UpdateAddOnMemoryUsage) end
    local ok, kb = pcall(GetAddOnMemoryUsage, ns.name)
    return ok and kb or nil
end

-- SuuUI's share of the time the game spends on addons, when its profiler runs.
local function share()
    local P, metric = C_AddOnProfiler, Enum.AddOnProfilerMetric and Enum.AddOnProfilerMetric.RecentAverageTime
    if not (P and metric and P.IsEnabled and P.IsEnabled()) then return nil end
    local ok1, mine = pcall(P.GetAddOnMetric, ns.name, metric)
    local ok2, app = pcall(P.GetApplicationMetric, metric)
    if ok1 and ok2 and mine and app and app > 0 then return mine, mine / app * 100 end
end

function Perf.Report()
    local on, spent = Fault.Timing()
    local seconds = startedAt and math.max(1, GetTime() - startedAt) or 1
    local rows, total = {}, 0
    for source, r in pairs(spent) do
        rows[#rows + 1] = { source = source, ms = r.ms, calls = r.calls, peak = r.peak, kb = r.kb or 0 }
        total = total + r.ms
    end
    table.sort(rows, function(a, b) return a.ms > b.ms end)
    local out = { at = date("%Y-%m-%d %H:%M:%S"), seconds = math.floor(seconds), total = total, modules = {} }
    ns.Print(("Perf over %d s: %.1f ms in all (%.2f ms a second)."):format(seconds, total, total / seconds))
    for i, r in ipairs(rows) do
        local line = ("%s: %.1f ms (%.3f ms/s), %d calls, slowest %.2f ms, %s allocated"):format(r.source, r.ms, r.ms / seconds,
            r.calls, r.peak, r.kb >= 1024 and ("%.1f MB"):format(r.kb / 1024) or ("%.0f KB"):format(r.kb))
        out.modules[i] = line
        if i <= TOP then ns.Print("  " .. line) end
    end
    if #rows > TOP then ns.Print(("  … %d more in SuuUIProbe.perf"):format(#rows - TOP)) end
    -- what allocates most: the garbage makers
    table.sort(rows, function(a, b) return a.kb > b.kb end)
    local alloc, allocKB = {}, 0
    for i, r in ipairs(rows) do
        allocKB = allocKB + r.kb
        if i <= TOP and r.kb >= 1 then
            alloc[#alloc + 1] = ("%s %.0f KB (%.1f KB/s)"):format(r.source, r.kb, r.kb / seconds)
        end
    end
    out.allocated = alloc
    out.allocatedKB = math.floor(allocKB)
    ns.Print(("Allocated: %.1f MB (%.1f KB a second); most: %s"):format(allocKB / 1024, allocKB / seconds,
        table.concat(alloc, ", ", 1, math.min(5, #alloc))))
    if risenKB then
        out.allocatedAll = ("%.1f MB (%.1f KB a second), %d collections"):format(risenKB / 1024, risenKB / seconds, collections)
        ns.Print("Allocated by all of SuuUI (frame scripts too): " .. out.allocatedAll)
    end
    local kb = memory()
    if kb then
        out.memory = ("%.1f MB"):format(kb / 1024)
        out.memoryAtStart = startKB and ("%.1f MB"):format(startKB / 1024)
        ns.Print("Memory (all of SuuUI): " .. out.memory .. (startKB and (" (" .. out.memoryAtStart .. " at the start)") or ""))
    end
    local ms, pct = share()
    if ms then
        out.share = ("%.2f ms a frame, %.1f%% of the frame"):format(ms, pct)
        ns.Print("The game's profiler: " .. out.share)
    end
    -- a dev build (wowlua dev): its profiler's busiest functions and its
    -- monitor's scripts and timers, where the frequent work (and so the
    -- garbage) is
    local wl = ns.__wowlua
    if wl and wl.prof and wl.prof.stats then
        local function top(stats, by, n, fmt)
            local list = {}
            for name, st in pairs(stats) do list[#list + 1] = { name = name, s = st } end
            table.sort(list, function(a, b) return (a.s[by] or 0) > (b.s[by] or 0) end)
            local lines = {}
            for i = 1, math.min(n, #list) do lines[i] = fmt(list[i].name, list[i].s) end
            return lines
        end
        local function fn(name, st)
            return ("%s: %d calls, self %.1f ms, total %.1f ms%s"):format(name, st.calls or 0, st.self or 0, st.total or 0,
                st.location and (" (" .. st.location .. ")") or "")
        end
        local function hit(name, st)
            return ("%s: %d, %.1f ms%s"):format(name, st.count or 0, st.total or 0, st.detail and (" (" .. tostring(st.detail) .. ")") or "")
        end
        out.dev = {
            byCalls = top(wl.prof.stats, "calls", 40, fn),
            bySelf = top(wl.prof.stats, "self", 25, fn),
            scripts = wl.mon and top(wl.mon.scripts or {}, "count", 25, hit),
            timers = wl.mon and top(wl.mon.timers or {}, "count", 15, hit),
            events = wl.mon and top(wl.mon.events or {}, "count", 25, hit),
        }
        ns.Print("Dev build: the profiler's and monitor's busiest are in SuuUIProbe.perf.dev.")
    end
    SuuUIProbe = SuuUIProbe or {}
    SuuUIProbe.perf = out
    return out
end

ns.RegisterCommand("perf", "Time each SuuUI module: /suu perf starts, again shows the report, /suu perf stop ends it.", function(arg)
    local on = Fault.Timing()
    if arg == "stop" then
        if on then Perf.Report() end
        Fault.SetTiming(false)
        startedAt, startKB = nil, nil
        if sampler then sampler:Cancel(); sampler = nil end
        lastKB, risenKB = nil, nil
        ns.Print("Perf: stopped.")
        return
    end
    if not on then
        Fault.SetTiming(true)
        startedAt = GetTime()
        -- a dev build's profiler and monitor count from now too
        local wl = ns.__wowlua
        if wl and wl.prof and wl.prof.reset then pcall(wl.prof.reset) end
        if wl and wl.mon and wl.mon.reset then pcall(wl.mon.reset) end
        startKB = memory()
        lastKB, risenKB, collections = startKB, 0, 0
        if sampler then sampler:Cancel() end
        sampler = C_Timer.NewTicker(1, function()
            local now = memory()
            if not (now and lastKB) then return end
            if now >= lastKB then risenKB = risenKB + (now - lastKB) else collections = collections + 1 end
            lastKB = now
        end)
        ns.Print("Perf: measuring. Play a while (a fight, a city), then /suu perf for the report.")
        return
    end
    Perf.Report()
end)
