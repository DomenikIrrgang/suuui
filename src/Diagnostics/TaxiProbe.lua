-- Diagnostics/TaxiProbe.lua
-- "/suu probe taxi" (asked 2026-10-19: flight path tracking and the flight
-- master's window in SuuUI's look; the designs wait on it): what Forever
-- tells about flight paths.
--   now:   the client's own API documentation for taxi and flight; the
--          nodes C_TaxiMap gives for your zone and its continent away from a
--          flight master (GetAllTaxiNodes, GetTaxiNodesForMap) and whether
--          you're on a taxi
--   then (this session, by itself): each time a flight master's map opens,
--          every node with its name, state, cost, place and route hops; and
--          your next flights, timed from losing control to getting it back
-- Saved in SuuUIProbe.taxi on /reload. Values the game hides read SECRET.

local _, ns = ...

local TP = {}
ns.TaxiProbe = TP

local isSecret = issecretvalue or function() return false end
local function show(v)
    if isSecret(v) then return "SECRET" end
    if type(v) == "table" and v.x then return ("%.4f,%.4f"):format(v.x, v.y) end
    return tostring(v)
end

-- A function that may not exist, may error or may answer secret.
local function call(fn, ...)
    if type(fn) ~= "function" then return "missing" end
    local ok, a, b, c, d = pcall(fn, ...)
    if not ok then return "error: " .. tostring(a):sub(1, 120) end
    return a, b, c, d
end

local function nodeList(list)
    if type(list) ~= "table" then return show(list) end
    if isSecret(list) then return "SECRET" end
    local out = {}
    for i, n in ipairs(list) do
        local parts = {}
        for k, v in pairs(n) do parts[#parts + 1] = tostring(k) .. "=" .. show(v) end
        table.sort(parts)
        out[i] = table.concat(parts, "  ")
    end
    return out
end

local function out()
    SuuUIProbe = SuuUIProbe or {}
    SuuUIProbe.taxi = SuuUIProbe.taxi or {}
    return SuuUIProbe.taxi
end

-- Away from a flight master: the zone's and the continent's nodes.
local function snapshot()
    local o = out()
    local T = C_TaxiMap or {}
    local zone = C_Map.GetBestMapForUnit("player")
    local shown = WorldMapFrame and WorldMapFrame:IsShown() and WorldMapFrame:GetMapID() or nil
    local continent = zone
    local info = zone and C_Map.GetMapInfo(zone)
    while info and info.mapType and Enum.UIMapType and info.mapType > Enum.UIMapType.Continent and info.parentMapID do
        continent = info.parentMapID
        info = C_Map.GetMapInfo(continent)
    end
    local s = { at = date("%H:%M:%S"), zone = zone, continent = continent, shownMap = shown,
        onTaxi = show(call(UnitOnTaxi, "player")), taxiNodes = show(call(NumTaxiNodes)),
        api = {} }
    for _, name in ipairs({ "GetAllTaxiNodes", "GetTaxiNodesForMap", "ShouldMapShowTaxiNodes", "GetTaxiNodeInfo" }) do
        s.api[name] = type(T[name]) == "function" and "yes" or "missing"
    end
    for _, name in ipairs({ "NumTaxiNodes", "TaxiNodeName", "TaxiNodeGetType", "TaxiNodeCost", "TaxiNodePosition",
            "GetNumRoutes", "TaxiGetNodeSlot", "TakeTaxiNode", "UnitOnTaxi", "TaxiRequestEarlyLanding", "CloseTaxiMap" }) do
        s.api[name] = type(_G[name]) == "function" and "yes" or "missing"
    end
    for _, m in ipairs({ zone, continent, shown }) do
        if m then
            s["all " .. m] = nodeList(call(T.GetAllTaxiNodes, m))
            s["forMap " .. m] = nodeList(call(T.GetTaxiNodesForMap, m))
            s["shouldShow " .. m] = show(call(T.ShouldMapShowTaxiNodes, m))
        end
    end
    o.away = s
    -- the documentation
    if ns.ApiDocs and ns.ApiDocs.Dump then
        local lines, err = ns.ApiDocs.Dump({ "taxi", "flight" })
        o.docs = lines or err
    end
end

-- At a flight master: every node and its routes.
local function atMaster()
    local o = out()
    local n = call(NumTaxiNodes)
    local s = { at = date("%H:%M:%S"), count = show(n), zone = C_Map.GetBestMapForUnit("player"), nodes = {} }
    if type(n) == "number" and not isSecret(n) then
        for i = 1, n do
            local x, y = call(TaxiNodePosition, i)
            local routes = call(GetNumRoutes, i)
            local hops = {}
            if type(routes) == "number" and not isSecret(routes) then
                for r = 1, routes do
                    hops[#hops + 1] = show(call(TaxiGetNodeSlot, i, r, true)) .. ">" .. show(call(TaxiGetNodeSlot, i, r, false))
                end
            end
            s.nodes[i] = ("%d %s: type %s, cost %s, at %s,%s, routes %s [%s]"):format(i, show(call(TaxiNodeName, i)),
                show(call(TaxiNodeGetType, i)), show(call(TaxiNodeCost, i)), show(x), show(y), show(routes),
                table.concat(hops, " "))
        end
    end
    local T = C_TaxiMap or {}
    local map = s.zone
    if map then s.allHere = nodeList(call(T.GetAllTaxiNodes, map)) end
    o.masters = o.masters or {}
    o.masters[#o.masters + 1] = s
    ns.Print(("Taxi probe: the flight master's %s nodes recorded."):format(show(n)))
end

-- A flight, from losing control to getting it back.
local flight
local function flightStart()
    local on = call(UnitOnTaxi, "player")
    if on ~= true then return end
    flight = { started = GetTime(), at = date("%H:%M:%S"), from = C_Map.GetBestMapForUnit("player") }
end

local function flightEnd()
    if not flight then return end
    local o = out()
    flight.seconds = ("%.1f"):format(GetTime() - flight.started)
    flight.to = C_Map.GetBestMapForUnit("player")
    flight.started = nil
    o.flights = o.flights or {}
    o.flights[#o.flights + 1] = ("%s: %s s, map %s to %s"):format(flight.at, flight.seconds, show(flight.from), show(flight.to))
    ns.Print(("Taxi probe: a flight of %s s recorded."):format(flight.seconds))
    flight = nil
end

local listening
local function listen()
    if listening then return end
    listening = CreateFrame("Frame")
    for _, e in ipairs({ "TAXIMAP_OPENED", "PLAYER_CONTROL_LOST", "PLAYER_CONTROL_GAINED" }) do
        pcall(listening.RegisterEvent, listening, e)
    end
    listening:SetScript("OnEvent", function(_, event)
        if event == "TAXIMAP_OPENED" then
            -- the map's nodes are in a moment after it opens
            C_Timer.After(0.2, atMaster)
        elseif event == "PLAYER_CONTROL_LOST" then
            -- on a taxi a moment after control goes
            C_Timer.After(0.5, flightStart)
        else
            flightEnd()
        end
    end)
end

function TP.Command()
    snapshot()
    listen()
    ns.Print("Taxi probe: recorded what the game gives here. Now open a flight master's map (and take a flight or two if you like); then /reload to save it.")
end
