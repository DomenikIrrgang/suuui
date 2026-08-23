local pairs, type = pairs, type
local tinsert = table.insert

SuuUI = {
    version    = "0.1.0",
    _debug     = false,
    Components = {},
    Layout     = {},
    Utils      = {},
}

--- Prints a debug message when debug mode is enabled.
-- @param msg string
function SuuUI.Debug(msg)
    if SuuUI._debug then
        print("|cff888888[SuuUI]|r " .. tostring(msg))
    end
end

--- Reports a FAULT the player needs to know about, whether or not debug mode is on.
--
-- The distinction from Debug is the point. Debug is for tracing -- a chatty stream nobody wants by
-- default. This is for "something the addon was asked to do did not happen": a component that threw
-- while being built, a plugin that failed to enable. Those leave a visible hole in the UI, and a hole
-- with no message is indistinguishable from a feature that was never written.
--
-- Learned the hard way in Phase 6: a stance button raised during construction, the exception was
-- caught by a Settings watcher's pcall and logged through Debug, and the player saw no bar and no
-- error. Two rounds of diagnosis went into that silence before anyone thought to switch Debug on.
--
-- Deduplicated by message, because a watcher can fire repeatedly on a profile load and the same
-- fault printed twenty times is its own kind of unusable.
local seenFaults = {}
function SuuUI.Fault(msg)
    msg = tostring(msg)
    if seenFaults[msg] then return end
    seenFaults[msg] = true
    print("|cffff5555[SuuUI]|r " .. msg)
end

--- Clears the fault dedup set. For tests, and for a reload-like reset.
function SuuUI.ClearFaults()
    seenFaults = {}
end

--- Deep-copies a table. Does not copy metatables.
-- @param t table
-- @return table
function SuuUI.Utils.DeepCopy(t)
    local copy = {}
    for k, v in pairs(t) do
        copy[k] = (type(v) == "table") and SuuUI.Utils.DeepCopy(v) or v
    end
    return copy
end

--- Shallow-merges src into target in place. Returns target.
-- @param target table
-- @param src table
-- @return table
function SuuUI.Utils.Merge(target, src)
    for k, v in pairs(src) do target[k] = v end
    return target
end

--- Returns the first value in t for which predFn(v) is true.
-- @param t table
-- @param predFn function
-- @return any|nil
function SuuUI.Utils.Find(t, predFn)
    for _, v in pairs(t) do
        if predFn(v) then return v end
    end
end

--- Returns an array of all keys in t.
-- @param t table
-- @return table
function SuuUI.Utils.Keys(t)
    local keys = {}
    for k in pairs(t) do tinsert(keys, k) end
    return keys
end
