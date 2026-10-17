-- Core/Perf.lua
-- "/suu perf" (plan 4.2): how much time each SuuUI module takes. The game
-- measures only whole addons, so SuuUI times its own work: every module's
-- events, setting watchers, timers and commands run through Fault.Call,
-- which, while measuring, adds each call's own time (nested calls taken
-- out) to its module. Frame scripts a module sets itself (OnUpdate) aren't
-- counted. Memory is the whole addon's (the game can't split it).
--   /suu perf         start measuring; again: the report so far
--   /suu perf stop    the report, and stop measuring
-- The report goes to the chat and to SuuUIProbe.perf (on /reload).

local _, ns = ...

local Fault = ns.Fault

local Perf = {}
ns.Perf = Perf

local startedAt
local TOP = 12

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
        rows[#rows + 1] = { source = source, ms = r.ms, calls = r.calls, peak = r.peak }
        total = total + r.ms
    end
    table.sort(rows, function(a, b) return a.ms > b.ms end)
    local out = { at = date("%Y-%m-%d %H:%M:%S"), seconds = math.floor(seconds), total = total, modules = {} }
    ns.Print(("Perf over %d s: %.1f ms in all (%.2f ms a second)."):format(seconds, total, total / seconds))
    for i, r in ipairs(rows) do
        local line = ("%s: %.1f ms (%.3f ms/s), %d calls, slowest %.2f ms"):format(r.source, r.ms, r.ms / seconds, r.calls, r.peak)
        out.modules[i] = line
        if i <= TOP then ns.Print("  " .. line) end
    end
    if #rows > TOP then ns.Print(("  … %d more in SuuUIProbe.perf"):format(#rows - TOP)) end
    local kb = memory()
    if kb then
        out.memory = ("%.1f MB"):format(kb / 1024)
        ns.Print("Memory (all of SuuUI): " .. out.memory)
    end
    local ms, pct = share()
    if ms then
        out.share = ("%.2f ms a frame, %.1f%% of the frame"):format(ms, pct)
        ns.Print("The game's profiler: " .. out.share)
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
        startedAt = nil
        ns.Print("Perf: stopped.")
        return
    end
    if not on then
        Fault.SetTiming(true)
        startedAt = GetTime()
        ns.Print("Perf: measuring. Play a while (a fight, a city), then /suu perf for the report.")
        return
    end
    Perf.Report()
end)
