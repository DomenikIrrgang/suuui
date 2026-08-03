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
