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

-- A readable name for an owner passed to the event bus or settings: a
-- module's name, a frame's global name, or the owner itself.
function Util.OwnerName(owner)
    if type(owner) == "table" then
        if type(owner.name) == "string" then return owner.name end
        if type(owner.id) == "string" then return owner.id end
        -- an edit mode mover (its frame's label)
        if type(owner.label) == "string" then return "Mover: " .. owner.label end
        if owner.GetName and owner:GetName() then return owner:GetName() end
        return tostring(owner)
    end
    return tostring(owner)
end
