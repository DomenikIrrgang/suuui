-- Diagnostics/TaxiProbe.lua
-- "/suu probe taxi" (asked 2026-10-19: flight path tracking and the flight
-- master's window in SuuUI's look; the designs wait on it): what Forever
-- tells about flight paths.
--   now:   the client's own API documentation for taxi and flight; the
--          nodes C_TaxiMap gives for your zone and its continent away from a
--          flight master (GetAllTaxiNodes, GetTaxiNodesForMap) and whether
--          you're on a taxi
--   then (this session, by itself): each time a flight master's map opens,
--          which of the game's maps shows (TaxiFrame, FlightMapFrame), every
--          node with its name, state, cost, place, route hops and its
--          C_TaxiMap nodeID (matched by name: route lengths are keyed by
--          from and to nodeID); and your next flights, timed from losing
--          control to getting it back, with your map position and UnitOnTaxi
--          every 5 s on the way
--   take (asked 2026-10-19: SuuUI's world map as the one map for flying):
--          at the next flight master (or the open one), two SuuUI buttons:
--          "Fly to <the first reachable node>" calls TakeTaxiNode from a
--          click, "Hide the game's map" hides it and records whether that
--          ends the taxi session (TAXIMAP_CLOSED, NumTaxiNodes after)
-- Saved in SuuUIProbe.taxi on /reload. Values the game hides read SECRET.
--
--   /suu probe taxi        snapshot and listen
--   /suu probe taxi take   also the two buttons at the flight master

local _, ns = ...

local TP = {}
ns.TaxiProbe = TP

local isSecret = issecretvalue or function() return false end
local function show(v)
    if isSecret(v) then return "SECRET" end
    if type(v) == "table" and v.x then
        if isSecret(v.x) or isSecret(v.y) then return "SECRET,SECRET" end
        return ("%.4f,%.4f"):format(v.x, v.y)
    end
    return tostring(v)
end

-- A function that may not exist, may error or may answer secret.
local function call(fn, ...)
    if type(fn) ~= "function" then return "missing" end
    local ok, a, b, c, d = pcall(fn, ...)
    if not ok then return "error: " .. tostring(a):sub(1, 120) end
    return a, b, c, d
end

local function plain(v) return v ~= nil and not isSecret(v) end

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

local function continentOf(zone)
    local continent = zone
    local info = zone and C_Map.GetMapInfo(zone)
    while info and info.mapType and Enum.UIMapType and info.mapType > Enum.UIMapType.Continent and info.parentMapID do
        continent = info.parentMapID
        info = C_Map.GetMapInfo(continent)
    end
    return continent
end

-- Which of the game's taxi maps exist and show.
local function frames()
    local parts = {}
    for _, name in ipairs({ "TaxiFrame", "FlightMapFrame" }) do
        local f = _G[name]
        if f then
            local ok, shown = pcall(f.IsShown, f)
            parts[#parts + 1] = name .. " shown " .. (ok and show(shown) or "?")
        else
            parts[#parts + 1] = name .. " missing"
        end
    end
    local loaded = C_AddOns and C_AddOns.IsAddOnLoaded and call(C_AddOns.IsAddOnLoaded, "Blizzard_FlightMap")
    parts[#parts + 1] = "Blizzard_FlightMap loaded " .. show(loaded)
    return table.concat(parts, ", ")
end

-- Away from a flight master: the zone's and the continent's nodes.
local function snapshot()
    local o = out()
    local T = C_TaxiMap or {}
    local zone = C_Map.GetBestMapForUnit("player")
    local shown = WorldMapFrame and WorldMapFrame:IsShown() and WorldMapFrame:GetMapID() or nil
    local continent = continentOf(zone)
    local s = { at = date("%H:%M:%S"), zone = zone, continent = continent, shownMap = shown,
        onTaxi = show(call(UnitOnTaxi, "player")), taxiNodes = show(call(NumTaxiNodes)),
        api = {} }
    for _, name in ipairs({ "GetAllTaxiNodes", "GetTaxiNodesForMap", "ShouldMapShowTaxiNodes", "GetTaxiNodeInfo" }) do
        s.api[name] = type(T[name]) == "function" and "yes" or "missing"
    end
    for _, name in ipairs({ "NumTaxiNodes", "TaxiNodeName", "TaxiNodeGetType", "TaxiNodeCost", "TaxiNodePosition",
            "GetNumRoutes", "TaxiGetNodeSlot", "TakeTaxiNode", "UnitOnTaxi", "TaxiRequestEarlyLanding", "CloseTaxiMap",
            "GetTaxiMapID" }) do
        s.api[name] = type(_G[name]) == "function" and "yes" or "missing"
    end
    -- what TaxiRequestEarlyLanding is, wherever it lives
    s.earlyLanding = ("global %s, C_TaxiMap %s"):format(type(_G.TaxiRequestEarlyLanding), type(T.TaxiRequestEarlyLanding))
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
        local flags, ferr = ns.ApiDocs.Flags({ "TakeTaxiNode", "TaxiRequestEarlyLanding", "CloseTaxiMap", "TaxiNodeName",
            "NumTaxiNodes", "GetAllTaxiNodes", "GetPlayerMapPosition" })
        o.docFlags = flags or ferr
    end
end

-- The C_TaxiMap entries for the master's maps, by name (and by slotIndex,
-- when the entries carry one).
local function nodeIDs(zone)
    local T = C_TaxiMap or {}
    local byName, bySlot = {}, {}
    local maps = { zone, continentOf(zone) }
    local taxiMap = call(GetTaxiMapID)
    if type(taxiMap) == "number" then maps[#maps + 1] = taxiMap end
    for _, m in ipairs(maps) do
        local list = m and call(T.GetAllTaxiNodes, m)
        if type(list) == "table" and not isSecret(list) then
            for _, n in ipairs(list) do
                if plain(n.name) and plain(n.nodeID) and not byName[n.name] then byName[n.name] = n.nodeID end
                if plain(n.slotIndex) and plain(n.nodeID) and n.slotIndex then bySlot[n.slotIndex] = n.nodeID end
            end
        end
    end
    return byName, bySlot, taxiMap
end

-- At a flight master: every node and its routes.
local function atMaster()
    local o = out()
    local n = call(NumTaxiNodes)
    local s = { at = date("%H:%M:%S"), count = show(n), zone = C_Map.GetBestMapForUnit("player"), nodes = {},
        frames = frames() }
    local byName, bySlot, taxiMap = nodeIDs(s.zone)
    s.taxiMapID = show(taxiMap)
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
            local name = call(TaxiNodeName, i)
            local id = plain(name) and byName[name]
            s.nodes[i] = ("%d %s: type %s, cost %s, at %s,%s, routes %s [%s], nodeID %s (by name), %s (by slot)"):format(i,
                show(name), show(call(TaxiNodeGetType, i)), show(call(TaxiNodeCost, i)), show(x), show(y), show(routes),
                table.concat(hops, " "), show(id), show(bySlot[i]))
        end
    end
    local T = C_TaxiMap or {}
    local map = s.zone
    if map then s.allHere = nodeList(call(T.GetAllTaxiNodes, map)) end
    o.masters = o.masters or {}
    o.masters[#o.masters + 1] = s
    ns.Print(("Taxi probe: the flight master's %s nodes recorded."):format(show(n)))
end

--------------------------------------------------------------------------------
-- "take": flying from SuuUI's own button, and the game's map hidden
--------------------------------------------------------------------------------

local takeMode = false
local flyButton, hideButton
local take -- this master's take test: what the clicks did

local function button(text, y, onClick)
    local b = CreateFrame("Button", nil, UIParent, "UIPanelButtonTemplate")
    b:SetSize(300, 30)
    b:SetPoint("CENTER", UIParent, "CENTER", 0, y)
    b:SetFrameStrata("FULLSCREEN_DIALOG")
    b:SetText(text)
    b:SetScript("OnClick", onClick)
    return b
end

local function hideButtons()
    if flyButton then flyButton:Hide() end
    if hideButton then hideButton:Hide() end
end

-- What the game says while a click's call runs and just after.
local watch
local function watchFor(t)
    watch = watch or CreateFrame("Frame")
    watch:UnregisterAllEvents()
    for _, e in ipairs({ "ADDON_ACTION_BLOCKED", "ADDON_ACTION_FORBIDDEN", "UI_ERROR_MESSAGE", "TAXIMAP_CLOSED" }) do
        pcall(watch.RegisterEvent, watch, e)
    end
    watch:SetScript("OnEvent", function(_, event, a, b)
        t.events[#t.events + 1] = ("%.2f s %s %s %s%s"):format(GetTime() - t.started, event, show(a), show(b),
            a == ns.name and " (SuuUI)" or "")
    end)
    local mine = {}
    watch.owner = mine
    C_Timer.After(3, function() if watch.owner == mine then watch:UnregisterAllEvents() end end)
end

local function fly(slot, name)
    local t = { at = date("%H:%M:%S"), what = ("TakeTaxiNode(%d) to %s, from a click"):format(slot, show(name)),
        before = ("frames %s, nodes %s"):format(frames(), show(call(NumTaxiNodes))), events = {}, started = GetTime() }
    take.fly = t
    watchFor(t)
    local ok, err = pcall(TakeTaxiNode, slot)
    t.call = ok and "ran" or ("error: " .. tostring(err):sub(1, 120))
    C_Timer.After(3, function()
        t.onTaxi = show(call(UnitOnTaxi, "player"))
        t.started = nil
        ns.Print(("Taxi probe: TakeTaxiNode %s; on a taxi 3 s later: %s."):format(t.call, t.onTaxi))
    end)
    hideButtons()
end

local function hideMap()
    local t = { at = date("%H:%M:%S"), before = ("frames %s, nodes %s"):format(frames(), show(call(NumTaxiNodes))),
        events = {}, started = GetTime() }
    take.hide = t
    take.hiding = true
    watchFor(t)
    local f = _G.TaxiFrame
    if f then
        local ok, err = pcall(f.Hide, f)
        t.call = ok and "TaxiFrame:Hide() ran" or ("error: " .. tostring(err):sub(1, 120))
    else
        t.call = "no TaxiFrame"
    end
    -- the flight map, when that is the one showing
    local fm = _G.FlightMapFrame
    if fm and fm:IsShown() then
        local ok, err = pcall(fm.Hide, fm)
        t.call = t.call .. "; FlightMapFrame:Hide() " .. (ok and "ran" or ("error: " .. tostring(err):sub(1, 120)))
    end
    C_Timer.After(0.5, function()
        t.after = ("frames %s, nodes %s"):format(frames(), show(call(NumTaxiNodes)))
        t.started = nil
        ns.Print(("Taxi probe: the game's map hidden; after it: %s. Now click Fly to see whether a flight still starts."):format(t.after))
    end)
    if hideButton then hideButton:Hide() end
end

-- At the master, in take mode: the first reachable node, and the buttons.
local function offerTake()
    local n = call(NumTaxiNodes)
    if not (type(n) == "number" and plain(n)) then return end
    local slot, name
    for i = 1, n do
        if call(TaxiNodeGetType, i) == "REACHABLE" then slot, name = i, call(TaxiNodeName, i) break end
    end
    local o = out()
    take = { at = date("%H:%M:%S"), frames = frames(), node = slot and ("%d %s"):format(slot, show(name)) or "none reachable" }
    o.take = o.take or {}
    o.take[#o.take + 1] = take
    if not slot then
        ns.Print("Taxi probe: no reachable node from this flight master; try another.")
        return
    end
    flyButton = flyButton or button("", 200, nil)
    flyButton:SetText("Fly to " .. show(name))
    flyButton:SetScript("OnClick", function() fly(slot, name) end)
    flyButton:Show()
    hideButton = hideButton or button("Hide the game's map", 160, nil)
    hideButton:SetScript("OnClick", hideMap)
    hideButton:Show()
    ns.Print(("Taxi probe: two buttons above the middle. Click \"Hide the game's map\" first, then \"Fly to %s\" (how SuuUI's own map would fly); if hiding closed the flight master, open it again and click Fly alone. Then /reload."):format(show(name)))
end

-- A flight, from losing control to getting it back; where you are every 5 s.
local flight
local MAX_FLIGHT_SAMPLES = 60
local function flightSample()
    if not flight or #flight.samples >= MAX_FLIGHT_SAMPLES then return end
    local zone = C_Map.GetBestMapForUnit("player")
    local continent = continentOf(zone)
    flight.samples[#flight.samples + 1] = ("%.0f s: onTaxi %s, map %s at %s, continent %s at %s"):format(
        GetTime() - flight.started, show(call(UnitOnTaxi, "player")), show(zone),
        show(zone and call(C_Map.GetPlayerMapPosition, zone, "player")), show(continent),
        show(continent and call(C_Map.GetPlayerMapPosition, continent, "player")))
end

local function flightStart()
    local on = call(UnitOnTaxi, "player")
    if on ~= true then return end
    flight = { started = GetTime(), at = date("%H:%M:%S"), from = C_Map.GetBestMapForUnit("player"), samples = {} }
    flightSample()
    flight.ticker = C_Timer.NewTicker(5, flightSample)
end

local function flightEnd()
    if not flight then return end
    local o = out()
    flight.seconds = ("%.1f"):format(GetTime() - flight.started)
    flight.to = C_Map.GetBestMapForUnit("player")
    if flight.ticker then flight.ticker:Cancel() end
    o.flights = o.flights or {}
    o.flights[#o.flights + 1] = { summary = ("%s: %s s, map %s to %s"):format(flight.at, flight.seconds, show(flight.from), show(flight.to)),
        positions = flight.samples }
    ns.Print(("Taxi probe: a flight of %s s recorded."):format(flight.seconds))
    flight = nil
end

local listening
local function listen()
    if listening then return end
    listening = CreateFrame("Frame")
    for _, e in ipairs({ "TAXIMAP_OPENED", "TAXIMAP_CLOSED", "PLAYER_CONTROL_LOST", "PLAYER_CONTROL_GAINED" }) do
        pcall(listening.RegisterEvent, listening, e)
    end
    listening:SetScript("OnEvent", function(_, event, a)
        if event == "TAXIMAP_OPENED" then
            -- the map's nodes are in a moment after it opens
            local o = out()
            o.opened = o.opened or {}
            o.opened[#o.opened + 1] = ("%s TAXIMAP_OPENED %s; at once: %s"):format(date("%H:%M:%S"), show(a), frames())
            C_Timer.After(0.2, function()
                atMaster()
                if takeMode then offerTake() end
            end)
        elseif event == "TAXIMAP_CLOSED" then
            local o = out()
            o.closed = o.closed or {}
            o.closed[#o.closed + 1] = ("%s TAXIMAP_CLOSED; nodes %s%s"):format(date("%H:%M:%S"), show(call(NumTaxiNodes)),
                take and take.hiding and " (after the hide button)" or "")
            -- walked away: the buttons go; closed by the hide button: Fly stays, to try it
            if not (take and take.hiding) then hideButtons() end
        elseif event == "PLAYER_CONTROL_LOST" then
            -- on a taxi a moment after control goes
            C_Timer.After(0.5, flightStart)
        else
            flightEnd()
        end
    end)
end

function TP.Command(arg)
    snapshot()
    listen()
    if arg == "take" then
        takeMode = true
        local n = call(NumTaxiNodes)
        if type(n) == "number" and plain(n) and n > 0 then
            offerTake()
        else
            ns.Print("Taxi probe: take mode on. Open a flight master's map: SuuUI's own Fly button and a hide button come up.")
        end
        return
    end
    ns.Print("Taxi probe: recorded what the game gives here. Now open a flight master's map (and take a flight or two if you like); then /reload to save it.")
end
