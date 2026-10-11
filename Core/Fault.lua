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

function Fault.Call(source, fn, ...)
    return finish(source, xpcall(fn, handler, ...))
end

function Fault.List()
    return list
end

ns.RegisterCommand("errors", "List the errors SuuUI caught this session; \"/suu errors test\" raises one on purpose.", function(arg)
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
