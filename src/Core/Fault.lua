-- Core/Fault.lua
-- Errors players should know about. A failing callback is skipped, the rest of
-- SuuUI keeps running, and the player sees one chat line per distinct error per
-- session. "/suu errors" lists them with their stacks.

local _, ns = ...

local Fault = {}
ns.Fault = Fault

local MAX_KEPT = 50

local list = {}    -- { source, message, stack, count, time }, oldest first
local byKey = {}   -- source .. "\0" .. message -> entry

local function firstLine(msg)
    return (tostring(msg):match("^[^\n]*"))
end

-- Records an error from `source` (a module or owner name). `stack` is optional.
function Fault.Report(source, message, stack)
    source = tostring(source or "SuuUI")
    message = firstLine(message)
    local key = source .. "\0" .. message
    local entry = byKey[key]
    if entry then
        entry.count = entry.count + 1
        return
    end
    entry = { source = source, message = message, stack = stack, count = 1, time = date("%H:%M:%S") }
    byKey[key] = entry
    list[#list + 1] = entry
    if #list > MAX_KEPT then
        local old = table.remove(list, 1)
        byKey[old.source .. "\0" .. old.message] = nil
    end
    ns.Print(("|cffff9a80%s hit an error and was skipped:|r %s  (/suu errors)"):format(source, message))

    -- Kept in the saved variables too (written on /reload or logout), so the
    -- errors of a session can be read outside the game.
    if type(SuuUIDB) == "table" then
        SuuUIDB.errors = SuuUIDB.errors or {}
        local saved = SuuUIDB.errors
        saved[#saved + 1] = { time = date("%Y-%m-%d %H:%M:%S"), source = source, message = message,
            stack = stack, version = ns.version }
        while #saved > 30 do table.remove(saved, 1) end
    end
end

-- Calls fn(...) under xpcall; an error is reported against `source`.
-- Returns true plus fn's results on success, false on error. Allocates
-- nothing on success, so every event callback can go through it.
local lastStack

local function handler(err)
    lastStack = debugstack(2)
    return err
end

local function finish(source, ok, ...)
    if not ok then
        Fault.Report(source, (...), lastStack)
        return false
    end
    return true, ...
end

-- Timing (/suu perf, Perf.lua): while on, each call's own time (its nested
-- calls' taken out) is added to its source, a module's name.
local timing, spent = false, {}
local starts, childs, depth = {}, {}, 0
local clock = debugprofilestop

local function finishTimed(source, ok, ...)
    -- timing was turned off (or on again) inside this call: nothing to add
    if depth == 0 or not starts[depth] then return finish(source, ok, ...) end
    local now = clock()
    local total = now - starts[depth]
    local own = total - childs[depth]
    depth = depth - 1
    if depth > 0 then childs[depth] = childs[depth] + total end
    local rec = spent[source]
    if not rec then
        rec = { ms = 0, calls = 0, peak = 0 }
        spent[source] = rec
    end
    rec.ms, rec.calls = rec.ms + own, rec.calls + 1
    if own > rec.peak then rec.peak = own end
    return finish(source, ok, ...)
end

function Fault.Call(source, fn, ...)
    if not timing then return finish(source, xpcall(fn, handler, ...)) end
    depth = depth + 1
    starts[depth], childs[depth] = clock(), 0
    return finishTimed(source, xpcall(fn, handler, ...))
end

-- Timing on or off (on: from zero), and what it has counted:
-- { [source] = { ms, calls, peak } }.
function Fault.SetTiming(on)
    timing = on and true or false
    depth = 0
    if on then wipe(spent) end
end

function Fault.Timing()
    return timing, spent
end

function Fault.List()
    return list
end

ns.RegisterCommand("errors", "List the errors SuuUI caught this session; \"/suu errors test\" raises one on purpose.", function(arg)
    if arg == "clear" then
        wipe(list)
        wipe(byKey)
        if type(SuuUIDB) == "table" then SuuUIDB.errors = nil end
        return ns.Print("Errors cleared.")
    end
    if arg == "test" then
        ns.Events.On("SUUUI_FAULT_TEST", function() error("a deliberate test error") end, "Fault test")
        ns.Events.On("SUUUI_FAULT_TEST", function() ns.Print("The next listener still ran.") end, "Fault test (second listener)")
        ns.Events.Emit("SUUUI_FAULT_TEST")
        ns.Events.OffAll("Fault test")
        ns.Events.OffAll("Fault test (second listener)")
        return
    end
    if #list == 0 then
        ns.Print("No errors this session.")
        return
    end
    for _, e in ipairs(list) do
        ns.Print(("%s  %s: %s%s"):format(e.time, e.source, e.message, e.count > 1 and (" (x%d)"):format(e.count) or ""))
        if arg == "full" and e.stack then print(e.stack) end
    end
    if arg ~= "full" then print("  /suu errors full adds the stacks.") end
end)

-- Protected calls the game blocked in combat ("Interface action failed because
-- of an AddOn"). The game names only the function, so that is what is kept,
-- with SuuUI's stack at the moment it fired when there is one.
local blocked = CreateFrame("Frame")
blocked:RegisterEvent("ADDON_ACTION_BLOCKED")
blocked:RegisterEvent("ADDON_ACTION_FORBIDDEN")
blocked:SetScript("OnEvent", function(_, event, addon, func)
    local what = event == "ADDON_ACTION_FORBIDDEN" and "Forbidden" or "Blocked in combat"
    if addon ~= ns.name then
        -- blamed on someone else (another addon, or a name the game makes
        -- up): kept too, quietly, since SuuUI may still be the cause (found
        -- in game: closing the spells window in combat failed and nothing
        -- was logged)
        if type(SuuUIDB) == "table" then
            SuuUIDB.blocked = SuuUIDB.blocked or {}
            local saved = SuuUIDB.blocked
            saved[#saved + 1] = { time = date("%Y-%m-%d %H:%M:%S"), event = event, addon = tostring(addon), func = tostring(func),
                combat = InCombatLockdown() and true or false, stack = debugstack(2) }
            while #saved > 30 do table.remove(saved, 1) end
        end
        return
    end
    Fault.Report("Taint", ("%s: %s"):format(what, tostring(func)), debugstack(2))
end)
