-- Diagnostics/MapPinsProbe.lua
-- "/suu probe mappins" (asked 2026-10-19: the little houses the game draws
-- on the world map, to hide them): every pin the game's map shows on the
-- map open now, by template, with what each says it is (its POI's name,
-- atlas and ID, its own textures' atlases).
-- Saved in SuuUIProbe.mapPins on /reload. Values the game hides read SECRET.

local _, ns = ...

local MP = {}
ns.MapPinsProbe = MP

local isSecret = issecretvalue or function() return false end
local function show(v)
    if isSecret(v) then return "SECRET" end
    return tostring(v)
end

-- the atlases (or files) of a pin's own textures
local function art(pin)
    local out = {}
    for _, r in ipairs({ pin:GetRegions() }) do
        if r.GetAtlas and r:IsShown() then
            local a = r:GetAtlas()
            local t = not a and r.GetTexture and r:GetTexture()
            if a or t then out[#out + 1] = show(a or t) end
        end
    end
    return table.concat(out, ", ")
end

local function describe(pin)
    local parts = {}
    for _, key in ipairs({ "poiInfo", "areaPoiInfo", "vignetteInfo", "plotInfo", "taxiNodeData" }) do
        local i = pin[key]
        if type(i) == "table" then
            parts[#parts + 1] = ("%s: name %s, atlas %s, id %s"):format(key, show(i.name), show(i.atlasName),
                show(i.areaPoiID or i.poiID or i.vignetteID or i.plotDataID or i.nodeID))
        end
    end
    local x, y = pin.GetPosition and pin:GetPosition()
    parts[#parts + 1] = ("at %s,%s"):format(show(x), show(y))
    parts[#parts + 1] = "art " .. art(pin)
    return table.concat(parts, "; ")
end

function MP.Command()
    local f = WorldMapFrame
    if not (f and f:IsShown()) then
        ns.Print("Map pins probe: open the world map on the map with the houses first, then run it again.")
        return
    end
    SuuUIProbe = SuuUIProbe or {}
    local o = { at = date("%H:%M:%S"), map = f:GetMapID(), templates = {} }
    local n = 0
    for template, pool in pairs(f.pinPools or {}) do
        local list = {}
        for pin in pool:EnumerateActive() do
            if #list < 6 then list[#list + 1] = describe(pin) end
            n = n + 1
        end
        if #list > 0 then o.templates[template] = list end
    end
    SuuUIProbe.mapPins = SuuUIProbe.mapPins or {}
    table.insert(SuuUIProbe.mapPins, o)
    ns.Print(("Map pins probe: %d of the game's pins on map %s recorded. /reload to save it."):format(n, show(o.map)))
end
