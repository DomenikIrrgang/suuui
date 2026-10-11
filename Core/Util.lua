-- Core/Util.lua
-- Small table helpers shared by the core.

local _, ns = ...

local Util = {}
ns.Util = Util

-- A deep copy of `v`; non-tables are returned as they are.
function Util.Copy(v)
    if type(v) ~= "table" then return v end
    local out = {}
    for k, x in pairs(v) do out[k] = Util.Copy(x) end
    return out
end

-- Deep equality for plain data (no metatables, no cycles).
function Util.Equal(a, b)
    if a == b then return true end
    if type(a) ~= "table" or type(b) ~= "table" then return false end
    for k, x in pairs(a) do
        if not Util.Equal(x, b[k]) then return false end
    end
    for k in pairs(b) do
        if a[k] == nil then return false end
    end
    return true
end

-- The keys of `t`, sorted as strings.
function Util.SortedKeys(t)
    local out = {}
    for k in pairs(t) do out[#out + 1] = k end
    table.sort(out, function(a, b) return tostring(a) < tostring(b) end)
    return out
end

-- A readable name for an owner passed to the event bus or settings.
function Util.OwnerName(owner)
    if type(owner) == "table" then return owner.name or owner.id or tostring(owner) end
    return tostring(owner)
end
