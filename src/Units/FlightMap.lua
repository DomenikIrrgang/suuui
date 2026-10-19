-- Units/FlightMap.lua
-- The flight map (design "Flight paths", D: one map for flying): no window
-- of its own. At a flight master SuuUI's world map becomes the taxi map:
-- the continent with every flight master of yours (the ones you haven't
-- found faint, their edge dashed), the routes between those you have as
-- faint lines, each destination's flight time beside it, and the
-- destinations listed in the side panel over the quest log. Picking one
-- draws its route and puts where it stops, the cost, the time and Fly in a
-- bar at the map's bottom. In the air the same map shows your flight: the
-- part flown solid, the rest dashed, the time left at the destination.
--
-- The game's own flight map (TaxiFrame) stays open underneath, unseen and
-- without the mouse: hiding it ends the flight master's session, alpha 0
-- keeps it, and TakeTaxiNode from SuuUI's click flies (probed 2026-10-19).
-- The world map is shown outside the game's panel manager: through it, it
-- would take TaxiFrame's place (both are "left" panels) and close it.
-- Closing the map closes the flight master too. In combat the game's own
-- flight map opens as it would.
--
-- Flight times: each flight is timed, from losing control to getting it
-- back, and kept per route (the nodes it passes) for the whole account; a
-- route not flown yet is estimated from its length (SuuUI.FlightRoutes) at
-- the character's speed. That starts at 30.3 yards a second (fitted to
-- Classic's measured flight times; three flights on Forever came within
-- 0.4% of it, 2026-10-19), and each flight moves it a quarter of the way
-- toward what it measured. A flight far off its estimate (an early landing)
-- or begun before a reload teaches nothing. The speed is kept per
-- character, should Forever give one a faster flight; a route's time
-- carries the speed of whoever flew it and is scaled to yours when the two
-- differ by more than 3%.
-- A built-in module written against the public API only.

local M = SuuUI.RegisterModule({
    id = "flightmap",
    name = "Flight map",
    description = "The world map as the flight master's map: routes, costs and flight times, and your flight on the map while you fly.",
    api = "0.17",
    combatSafe = true,
    defaults = { atMaster = true, inFlight = true },
})

local UI, T = SuuUI.UI, SuuUI.Tokens
local S = T.space

local isSecret = issecretvalue or function() return false end
local function plain(v) return v ~= nil and not isSecret(v) end

local TEXTURES = "Interface\\AddOns\\SuuUI\\Media\\Textures\\"
local GLYPHS = TEXTURES .. "Glyphs\\"
local DISC = TEXTURES .. "CircleFill.tga"
local DASHED = TEXTURES .. "CircleDash.tga"

local SPEED = 30.3 -- yards a second, before a character has flown (see the header)
local LEARN = 0.25 -- how far one flight moves the speed toward what it measured
local TRUST = 0.2  -- a flight further than this off its expected time teaches nothing
local BOOST = 0.03 -- speeds further apart than this: another character's time is scaled
local KEEP = 5     -- a route's time: the mean of its last flights, up to this many
local MAX_FLIGHT = 1800 -- s: a flight kept over a reload longer than this is stale

local ROW_H = 36
local PIN = 26 -- UI.MapPin's size
local MAX_DASHES = 120 -- on one line of a route

--------------------------------------------------------------------------------
-- What the game gives
--------------------------------------------------------------------------------

-- "4:12"
local function clock(s)
    s = math.max(0, math.floor(s + 0.5))
    return ("%d:%02d"):format(s / 60, s % 60)
end

-- "1s 10c" in coin colours (a tooltip's line; built as it shows)
local function coins(copper)
    copper = math.max(0, math.floor(copper or 0))
    local g, s, c = math.floor(copper / 10000), math.floor(copper / 100) % 100, copper % 100
    local parts = {}
    local function part(v, unit, token) parts[#parts + 1] = v .. "|cff" .. T.color[token].hex .. unit .. "|r" end
    if g > 0 then part(g, "g", "coin-gold") end
    if s > 0 or (g > 0 and c > 0) then part(s, "s", "coin-silver") end
    if c > 0 or #parts == 0 then part(c, "c", "coin-copper") end
    return table.concat(parts, " ")
end

-- "Crossroads, The Barrens" → "Crossroads"
local function short(name)
    return name and name:match("^([^,]+)") or name or "?"
end

-- Taxi nodes the client still lists that no one flies to (an old copy of
-- Powderfuse Port, transports, quest flights)
local function junk(name)
    return type(name) ~= "string" or isSecret(name) or name:find("^zzOLD") ~= nil or name:find("^Transport,") ~= nil
        or name:find("^Quest Path") ~= nil
end

local function continentOf(mapID)
    local info = mapID and C_Map.GetMapInfo(mapID)
    local guard = 0
    while info and guard < 8 do
        if info.mapType == (Enum.UIMapType and Enum.UIMapType.Continent or 2) then return info.mapID end
        info = info.parentMapID and info.parentMapID > 0 and C_Map.GetMapInfo(info.parentMapID)
        guard = guard + 1
    end
end

-- Every flight master's place on a map, by nodeID (anywhere, a flight
-- master or not; a zone's map gives its continent's too, outside 0-1).
local function positions(mapID)
    local out = {}
    local ok, list = pcall(C_TaxiMap.GetTaxiNodesForMap, mapID)
    for _, n in ipairs(ok and type(list) == "table" and list or {}) do
        local x, y
        if n.position and n.position.GetXY then x, y = n.position:GetXY() end
        if plain(n.nodeID) and plain(x) and plain(y) then out[n.nodeID] = { x, y } end
    end
    return out
end

local function hopYards(a, b)
    local routes = SuuUI.FlightRoutes()
    return (routes[a] and routes[a][b]) or (routes[b] and routes[b][a])
end

-- A flight's length: its hops added up; nil when one isn't known.
local function pathYards(path)
    local total = 0
    for i = 1, #path - 1 do
        local y = hopYards(path[i], path[i + 1])
        if not y then return nil end
        total = total + y
    end
    return total
end

local function call(fn, ...)
    if type(fn) ~= "function" then return nil end
    local ok, a, b = pcall(fn, ...)
    if ok then return a, b end
end

-- The flight master's map as the game gives it: { nodes (by slot), byID,
-- current } with each node { slot, id, name, kind ("CURRENT", "REACHABLE",
-- "DISTANT"), cost, path (the nodeIDs a flight there passes, from here) };
-- nil while there's none.
function M:ReadSession()
    local n = call(NumTaxiNodes)
    if not (plain(n) and n and n > 0) then return nil end
    -- nodeIDs by slot (C_TaxiMap's nodes carry both), by name to be sure
    local ids, byName = {}, {}
    local zone = C_Map.GetBestMapForUnit("player")
    for _, m in ipairs({ zone, continentOf(zone), call(_G.GetTaxiMapID) }) do
        local list = call(C_TaxiMap.GetAllTaxiNodes, m)
        for _, node in ipairs(type(list) == "table" and list or {}) do
            if plain(node.nodeID) and plain(node.slotIndex) and node.slotIndex then ids[node.slotIndex] = ids[node.slotIndex] or node.nodeID end
            if plain(node.nodeID) and plain(node.name) and node.name then byName[node.name] = byName[node.name] or node.nodeID end
        end
        if next(ids) then break end
    end
    local s = { nodes = {}, byID = {} }
    for slot = 1, n do
        local name, kind = call(TaxiNodeName, slot), call(TaxiNodeGetType, slot)
        local id = ids[slot] or (plain(name) and byName[name])
        if plain(kind) and kind ~= "NONE" and not junk(name) and id then
            local cost = call(TaxiNodeCost, slot)
            local node = { slot = slot, id = id, name = name, kind = kind, cost = plain(cost) and cost or 0 }
            s.nodes[#s.nodes + 1] = node
            s.byID[id] = node
            if kind == "CURRENT" then s.current = node end
        end
    end
    -- each destination's hops, slot to slot, as nodeIDs
    local slotID = {}
    for _, node in ipairs(s.nodes) do slotID[node.slot] = node.id end
    for _, node in ipairs(s.nodes) do
        if node.kind == "REACHABLE" then
            local hops = call(GetNumRoutes, node.slot)
            if plain(hops) and hops and hops > 0 then
                local path = { slotID[call(TaxiGetNodeSlot, node.slot, 1, true)] }
                local whole = path[1] ~= nil
                for r = 1, hops do
                    local id = slotID[call(TaxiGetNodeSlot, node.slot, r, false)]
                    if not id then whole = false break end
                    path[r + 1] = id
                end
                if whole then node.path = path end
            end
            -- (a route the game can't trace: straight there)
            if not node.path and s.current then node.path = { s.current.id, node.id } end
        end
    end
    if not s.current then return nil end
    return s
end

--------------------------------------------------------------------------------
-- Flight times
--------------------------------------------------------------------------------

-- the routes timed, for the account: [nodeID>nodeID>…] = { t (s), n, v (the
-- flyer's speed) }
local function timed()
    local data = SuuUI.AccountData("flightmap")
    data.routes = data.routes or {}
    return data.routes
end

function M:Speed()
    return self:CharData().speed or SPEED
end

-- A flight's time in seconds and whether it was measured: one flown on
-- this route before (scaled to your speed when its flyer's differed by
-- more than BOOST), else its length at your speed; nil when neither is
-- known.
function M:FlightTime(path)
    if not path then return nil end
    local mine = self:Speed()
    local r = timed()[table.concat(path, ">")]
    if r and r.t then
        local t = r.t
        if r.v and math.abs(r.v / mine - 1) > BOOST then t = t * r.v / mine end
        return t, true
    end
    local yards = pathYards(path)
    if yards then return yards / mine, false end
end

-- A flight landed after `seconds`: its route's time, and the character's
-- speed a step toward what it flew.
function M:Learn(flight, seconds)
    local expected = flight.expected
    if flight.reloaded or seconds < 5 then return end
    if expected and math.abs(seconds / expected - 1) > TRUST then return end
    local data = self:CharData()
    local yards = pathYards(flight.path)
    if yards then
        local speed = self:Speed()
        data.speed = speed + LEARN * (yards / seconds - speed)
        data.flights = (data.flights or 0) + 1
    end
    local key = table.concat(flight.path, ">")
    local r = timed()[key] or {}
    r.n = math.min((r.n or 0) + 1, KEEP)
    r.t = r.t and (r.t + (seconds - r.t) / r.n) or seconds
    r.v = self:Speed()
    timed()[key] = r
end

--------------------------------------------------------------------------------
-- A flight: taken, in the air, landed
--------------------------------------------------------------------------------

-- TakeTaxiNode ran (SuuUI's Fly or the game's own map): the route it asked for.
function M:Taking(slot)
    local s = self.last or self:ReadSession()
    local node
    for _, n in ipairs(s and s.nodes or {}) do if n.slot == slot then node = n end end
    if not (node and node.path) then return end
    self.pending = { path = node.path, at = GetTime() }
end

function M:FlightStarted(at)
    local p = self.pending
    if not (p and GetTime() - p.at < 15 and UnitOnTaxi("player")) then return end
    self.pending = nil
    local expected, measured = self:FlightTime(p.path)
    self.flight = { path = p.path, started = at, expected = expected, measured = measured }
    -- kept over a reload, to show (not to time: the start isn't exact then)
    self:CharData().flight = { path = p.path, wall = time() - (GetTime() - at) }
    self:QueueLayout()
end

-- Landed: at the destination, its time is learned; landed early (the
-- destination far off), nothing.
function M:FlightEnded(at)
    local f = self.flight
    if not f then return end
    self.flight = nil
    self:CharData().flight = nil
    local seconds = at - f.started
    local continent = continentOf(C_Map.GetBestMapForUnit("player"))
    local to = f.path[#f.path]
    local there = true
    if continent then
        local p = positions(continent)[to]
        local me = call(C_Map.GetPlayerMapPosition, continent, "player")
        local x, y
        if me and me.GetXY then x, y = me:GetXY() end
        if p and plain(x) and plain(y) then there = math.sqrt((p[1] - x) ^ 2 + (p[2] - y) ^ 2) < 0.03 end
    end
    if there then self:Learn(f, seconds) end
    self:QueueLayout()
end

-- After a reload in the air: the flight kept, shown but not timed.
function M:ResumeFlight()
    local data = self:CharData()
    local kept = data.flight
    if not (kept and kept.path and kept.wall) then return end
    local ago = time() - kept.wall
    if not UnitOnTaxi("player") or ago > MAX_FLIGHT or ago < 0 then data.flight = nil return end
    local expected, measured = self:FlightTime(kept.path)
    self.flight = { path = kept.path, started = GetTime() - ago, expected = expected, measured = measured, reloaded = true }
end

--------------------------------------------------------------------------------
-- The game's flight map, kept open underneath
--------------------------------------------------------------------------------

-- Unseen, and neither it nor anything on it takes the mouse (an unseen
-- node button would still fly where it was clicked). Only alpha and the
-- mouse: hidden, it closes the flight master.
function M:HideGameMap()
    local tf = _G.TaxiFrame
    if not tf then return false end
    self.gameQuiet = self.gameQuiet or {}
    tf:SetAlpha(0)
    local function quiet(f, depth)
        if f:IsMouseEnabled() then
            f:EnableMouse(false)
            self.gameQuiet[#self.gameQuiet + 1] = f
        end
        if depth < 3 then for _, c in ipairs({ f:GetChildren() }) do quiet(c, depth + 1) end end
    end
    quiet(tf, 0)
    return true
end

function M:ShowGameMap()
    local tf = _G.TaxiFrame
    if not (tf and self.gameQuiet) then return end
    tf:SetAlpha(1)
    for _, f in ipairs(self.gameQuiet) do f:EnableMouse(true) end
    self.gameQuiet = nil
end

--------------------------------------------------------------------------------
-- At the flight master: the world map as the flight map
--------------------------------------------------------------------------------

function M:AtMaster()
    return self.session ~= nil
end

-- The world map module's pins away while the flight map shows, back after.
local function refreshPins()
    local wm = SuuUI.GetModule("worldmap")
    if wm and wm:IsEnabled() and wm.map and wm.map:IsShown() then wm:Refresh() end
end

function M:OnTaxiOpened()
    self.last = self:ReadSession()
    if self.session then self:LeaveMaster(false) end
    if not (self:Get("atMaster") and self.map) or InCombatLockdown() then return end
    -- unseen at once (no flicker); the world map a frame later, once the
    -- game has put its own map up (it would close the world map if that
    -- showed first)
    if not self:HideGameMap() then return end
    C_Timer.After(0, function() self:EnterMaster(true) end)
end

function M:EnterMaster(retry)
    if not self.gameQuiet then return end
    local s = self:ReadSession()
    if not s then
        -- (the nodes a moment later; else the game's own map after all)
        if retry then C_Timer.After(0.2, function() self:EnterMaster(false) end) else self:ShowGameMap() end
        return
    end
    self.last = s
    -- its new buttons, made as it showed, without the mouse too
    self:HideGameMap()
    self.session, self.selected, self.hovered = s, nil, nil
    local f = self.map
    if not f:IsShown() then f:Show() end
    local continent = continentOf(C_Map.GetBestMapForUnit("player"))
    if continent and f:GetMapID() ~= continent then f:SetMapID(continent) end
    self:FillSide()
    self:PlaceSide()
    self.side:Show()
    self:UpdateBar()
    self:SetTitle(true)
    refreshPins()
    self:QueueLayout()
end

-- The flight master closed (walked away, flown, or the map closed):
-- the game's map back as it was; the world map closed with it.
function M:LeaveMaster(closeMap)
    local was = self.session ~= nil
    self.session, self.selected, self.hovered = nil, nil, nil
    self:ShowGameMap()
    if self.side then self.side:Hide() end
    if self.bar then self.bar:Hide() end
    if not was then return end
    self:SetTitle(false)
    local f = self.map
    if closeMap and f and f:IsShown() then
        self.closing = true
        f:Hide()
        self.closing = false
    end
    refreshPins()
    self:QueueLayout()
end

-- the map's header: "Flight master · Thunder Bluff" while it's the flight
-- map, its usual "Kalimdor › Mulgore" after
function M:SetTitle(master)
    local chrome = self.map and self.map.suuChrome
    if not chrome then return end
    if master and self.session then
        chrome:SetTitle("Flight master · " .. short(self.session.current.name))
        return
    end
    local mapID = self.map:GetMapID()
    local info = mapID and C_Map.GetMapInfo(mapID)
    if not info then return end
    local continent = continentOf(mapID)
    local c = continent and continent ~= mapID and C_Map.GetMapInfo(continent)
    chrome:SetTitle(c and (c.name .. " › " .. info.name) or info.name)
end

function M:Select(node)
    if not (self.session and node and node.kind == "REACHABLE") then return end
    self.selected = node
    self:UpdateBar()
    self:UpdateRows()
    self:QueueInk()
end

function M:Fly()
    local node = self.selected
    if not (self.session and node) then return end
    TakeTaxiNode(node.slot)
end

-- a destination's time: "4:12" when timed, "~3:30" estimated; and a word
-- for its tooltip
local function timeText(t, measured, long)
    if not t then return long and "Not timed yet" or "–" end
    if measured then return clock(t) end
    return (long and "about " or "~") .. clock(t)
end

local function viaText(path, s)
    if not path or #path <= 2 then return "Direct" end
    local names = {}
    for i = 2, #path - 1 do
        local n = s.byID[path[i]]
        names[#names + 1] = n and short(n.name) or "?"
    end
    return "via " .. table.concat(names, ", ")
end

local function stopsText(path)
    local stops = path and (#path - 2) or 0
    if stops <= 0 then return "Direct" end
    return stops == 1 and "1 stop" or (stops .. " stops")
end

-- A flight master's tooltip on the flight map.
function M:Tip(node)
    local s = self.session
    if not s then return {} end
    if node.kind == "CURRENT" then
        return { title = node.name, subtitle = "Flight master · you are here" }
    end
    if node.kind ~= "REACHABLE" then
        return { title = node.name, subtitle = "Flight master · not found yet",
                 description = "Talk to its flight master once to fly there." }
    end
    local t, measured = self:FlightTime(node.path)
    local muted = "|cff" .. T.color["ink-muted"].hex
    return {
        title = node.name, subtitle = viaText(node.path, s),
        lines = { { "Cost", coins(node.cost) }, { "Time", timeText(t, measured, true) } },
        description = t and (muted .. (measured and "Timed on an earlier flight." or "Estimated from the route's length; timed once you've flown it.") .. "|r") or nil,
        meta = self.selected == node and "Fly in the bar below" or "Click to choose",
    }
end

--------------------------------------------------------------------------------
-- The side panel: the destinations
--------------------------------------------------------------------------------

function M:BuildSide()
    if self.side then return end
    local f = self.map
    local side = CreateFrame("Frame", nil, f)
    side:EnableMouse(true)
    side:Hide()
    UI.Fill(side, "surface", "BACKGROUND"):SetAllPoints()
    side.edge = UI.Border(side, "gilt-line")
    side.head = UI.SectionHeader(side, "Destinations", "")
    side.head:SetPoint("TOPLEFT", S["space-5"], -S["space-5"])
    side.head:SetPoint("TOPRIGHT", -S["space-5"], -S["space-5"])
    side.note = UI.Text(side, "caption", "ink-faint")
    side.note:SetWordWrap(true)
    side.note:SetJustifyH("LEFT")
    side.note:SetPoint("BOTTOMLEFT", S["space-5"], S["space-5"])
    side.note:SetPoint("BOTTOMRIGHT", -S["space-5"], S["space-5"])
    side.note:SetValue("Quests, services and your marks stay off while the flight master's map is open; they come back when it closes.")
    side.scroll = UI.ScrollArea(side, 2)
    side.scroll:SetPoint("TOPLEFT", side.head, "BOTTOMLEFT", 0, -S["space-4"])
    side.scroll:SetPoint("BOTTOMRIGHT", side.note, "TOPRIGHT", -S["space-3"], S["space-4"])
    side.rows = {}
    self.side = side
end

function M:Row(i)
    local side = self.side
    local row = side.rows[i]
    if row then return row end
    row = CreateFrame("Button", nil, side.scroll.child)
    row:SetHeight(ROW_H)
    row.fill = UI.Fill(row, "surface-raised", "BACKGROUND")
    row.fill:SetAllPoints()
    row.fill:Hide()
    row.edge = UI.Border(row, "gilt-line")
    row.edge:SetShown(false)
    row.glyph = row:CreateTexture(nil, "ARTWORK")
    row.glyph:SetTexture(GLYPHS .. "wing.tga")
    row.glyph:SetSize(14, 14)
    row.glyph:SetPoint("LEFT", S["space-4"], 0)
    UI.Paint(row.glyph, "gilt-text")
    row.time = UI.Text(row, "numeric", "ink")
    row.time:SetPoint("RIGHT", -S["space-4"], 0)
    -- the name over the row's middle, its stops under it; the time's
    -- room kept on the right
    local x = S["space-4"] + 14 + S["space-4"]
    row.name = UI.Text(row, "label", "ink")
    row.name:SetPoint("BOTTOMLEFT", row, "LEFT", x, 0)
    row.name:SetPoint("BOTTOMRIGHT", row, "RIGHT", -64, 0)
    row.name:SetJustifyH("LEFT")
    row.stops = UI.Text(row, "caption", "ink-muted")
    row.stops:SetPoint("TOPLEFT", row, "LEFT", x, 0)
    row:SetScript("OnEnter", function(r)
        r.hover = true
        self:PaintRow(r)
        if r.node then
            self.hovered = r.node
            self:QueueInk()
            UI.ShowTooltip(r, function() return r.node and self:Tip(r.node) or {} end)
        end
    end)
    row:SetScript("OnLeave", function(r)
        r.hover = false
        self:PaintRow(r)
        self.hovered = nil
        self:QueueInk()
        UI.HideTooltip()
    end)
    row:SetScript("OnClick", function(r) self:Select(r.node) end)
    side.rows[i] = row
    return row
end

function M:PaintRow(row)
    local chosen = row.node and row.node == self.selected
    row.fill:SetShown(row.hover or chosen)
    row.edge:SetShown(chosen)
end

-- The destinations, by name.
function M:FillSide()
    self:BuildSide()
    local s = self.session
    local list = {}
    for _, n in ipairs(s and s.nodes or {}) do
        if n.kind == "REACHABLE" then list[#list + 1] = n end
    end
    table.sort(list, function(a, b) return a.name < b.name end)
    local side = self.side
    side.head:SetLabel("Destinations", tostring(#list))
    local width = math.max(1, side.scroll:GetWidth())
    for i, node in ipairs(list) do
        local row = self:Row(i)
        row.node = node
        row:ClearAllPoints()
        row:SetPoint("TOPLEFT", side.scroll.child, "TOPLEFT", 0, -(i - 1) * ROW_H)
        row:SetWidth(width)
        row.name:SetValue(short(node.name))
        row.stops:SetValue(stopsText(node.path))
        row:Show()
    end
    for i = #list + 1, #side.rows do side.rows[i]:Hide(); side.rows[i].node = nil end
    side.scroll.child:SetSize(width, math.max(1, #list * ROW_H))
    self:UpdateRows()
end

-- the rows' times and which one is chosen
function M:UpdateRows()
    if not self.side then return end
    for _, row in ipairs(self.side.rows) do
        if row.node then
            local t, measured = self:FlightTime(row.node.path)
            row.time:SetValue(timeText(t, measured))
            row.time:SetColor(measured and "ink" or "ink-muted")
            self:PaintRow(row)
        end
    end
end

-- Over the quest log while it's open (it's the map's side panel); beside
-- the window, as wide, while it's closed.
function M:PlaceSide()
    local f, side = self.map, self.side
    if not side then return end
    local log = f.QuestLog or _G.QuestMapFrame
    side:ClearAllPoints()
    if log and log:IsShown() then
        side:SetPoint("TOPLEFT", log, "TOPLEFT", 0, 0)
        side:SetPoint("BOTTOMRIGHT", log, "BOTTOMRIGHT", 0, 0)
        side:SetFrameStrata(log:GetFrameStrata())
        side:SetFrameLevel(log:GetFrameLevel() + 100)
        side.edge:SetShown(false)
    else
        side:SetPoint("TOPLEFT", f, "TOPRIGHT", S["space-3"], 0)
        side:SetPoint("BOTTOMLEFT", f, "BOTTOMRIGHT", S["space-3"], 0)
        side:SetWidth(f.questLogWidth or 333)
        side:SetFrameLevel(f:GetFrameLevel() + 100)
        side.edge:SetShown(true)
    end
    -- the rows as wide as the list, laid out again
    C_Timer.After(0, function() if self.session and self.side:IsShown() then self:FillSide() end end)
end

--------------------------------------------------------------------------------
-- The bar at the map's bottom: the chosen destination and Fly
--------------------------------------------------------------------------------

function M:BuildBar()
    if self.bar then return end
    local f = self.map
    local bar = UI.Panel(f, { ornament = true })
    -- (over the map's pins, the game's and SuuUI's, as the status line)
    bar:SetFrameLevel(4000)
    bar.body:SetFrameLevel(4001)
    bar:EnableMouse(true)
    bar:Hide()
    local body = bar.body
    bar.glyph = body:CreateTexture(nil, "ARTWORK")
    bar.glyph:SetTexture(GLYPHS .. "wing.tga")
    bar.glyph:SetSize(15, 15)
    UI.Paint(bar.glyph, "gilt-text")
    bar.name = UI.Text(body, "unit-name", "ink")
    bar.via = UI.Text(body, "caption", "ink-muted")
    bar.rule = UI.Fill(body, "gilt-faint", "ARTWORK")
    bar.rule:SetWidth(1)
    bar.money = UI.Money(body)
    bar.clock = body:CreateTexture(nil, "ARTWORK")
    bar.clock:SetTexture(GLYPHS .. "hourglass.tga")
    bar.clock:SetSize(11, 11)
    UI.Paint(bar.clock, "ink-faint")
    bar.time = UI.Text(body, "numeric", "ink-muted")
    bar.fly = UI.Button(body, { text = "Fly", variant = "primary", icon = "wing", onClick = function() self:Fly() end,
                                tooltip = { title = "Fly", description = "Take this flight (the cost is paid at once)." } })
    self.bar = bar
end

-- The bar for the chosen destination, sized to what it says.
function M:UpdateBar()
    local s, node = self.session, self.selected
    if not (s and node) then
        if self.bar then self.bar:Hide() end
        return
    end
    self:BuildBar()
    local bar = self.bar
    local t, measured = self:FlightTime(node.path)
    bar.name:SetValue(short(node.name))
    bar.via:SetValue(viaText(node.path, s))
    bar.money:SetCopper(node.cost)
    bar.time:SetValue(timeText(t, measured, true))
    bar.fly:Remeasure()
    local gap = S["space-5"]
    local h = math.max(T.type["unit-name"].lineHeight + T.type.caption.lineHeight, 30)
    local x = 0
    bar.glyph:ClearAllPoints()
    bar.glyph:SetPoint("LEFT", bar.body, "LEFT", x, 0)
    x = x + 15 + S["space-4"]
    local textW = math.ceil(math.max(bar.name:GetUnboundedStringWidth(), bar.via:GetUnboundedStringWidth()))
    bar.name:ClearAllPoints()
    bar.name:SetPoint("BOTTOMLEFT", bar.body, "LEFT", x, 0)
    bar.via:ClearAllPoints()
    bar.via:SetPoint("TOPLEFT", bar.body, "LEFT", x, 0)
    x = x + textW + gap
    bar.rule:ClearAllPoints()
    bar.rule:SetPoint("TOPLEFT", bar.body, "TOPLEFT", x, 0)
    bar.rule:SetPoint("BOTTOMLEFT", bar.body, "BOTTOMLEFT", x, 0)
    x = x + 1 + gap
    bar.money:ClearAllPoints()
    bar.money:SetPoint("LEFT", bar.body, "LEFT", x, 0)
    x = x + bar.money:GetWidth() + gap
    bar.clock:ClearAllPoints()
    bar.clock:SetPoint("LEFT", bar.body, "LEFT", x, 0)
    x = x + 11 + S["space-2"]
    bar.time:ClearAllPoints()
    bar.time:SetPoint("LEFT", bar.body, "LEFT", x, 0)
    x = x + math.ceil(bar.time:GetUnboundedStringWidth()) + gap
    bar.fly:ClearAllPoints()
    bar.fly:SetPoint("LEFT", bar.body, "LEFT", x, 0)
    x = x + bar.fly:GetWidth()
    bar.body:SetSize(x, h)
    bar:ClearAllPoints()
    bar:SetPoint("BOTTOM", self.map.ScrollContainer or self.map, "BOTTOM", 0, S["space-5"])
    bar:Show()
end

--------------------------------------------------------------------------------
-- On the map's canvas: pins, routes, times
--------------------------------------------------------------------------------

function M:Pin()
    self.free = self.free or {}
    local pin = table.remove(self.free)
    if not pin then
        pin = UI.MapPin(self.layer)
        pin:RegisterForClicks("LeftButtonUp")
        -- the time (or "You are here") right of it, on glass
        local tag = CreateFrame("Frame", nil, pin)
        tag:SetPoint("LEFT", pin, "RIGHT", 3, 0)
        UI.Fill(tag, "surface-glass"):SetAllPoints()
        UI.Border(tag, "gilt-hairline")
        tag.text = UI.Text(tag, "micro", "ink")
        tag.text:SetPoint("CENTER", 0, 0)
        pin.tag = tag
        pin:SetScript("OnEnter", function(p)
            if not p.node then return end
            if p.node.kind == "REACHABLE" then self.hovered = p.node; self:QueueInk() end
            UI.ShowTooltip(p, function() return p.node and self:Tip(p.node) or {} end)
        end)
        pin:SetScript("OnLeave", function()
            self.hovered = nil
            self:QueueInk()
            UI.HideTooltip()
        end)
        pin:SetScript("OnClick", function(p) self:Select(p.node) end)
        -- a right-click goes through to the map (it zooms out)
        if pin.SetPassThroughButtons then pcall(pin.SetPassThroughButtons, pin, "RightButton") end
    end
    pin:Show()
    self.pins[#self.pins + 1] = pin
    return pin
end

local function setTag(tag, text, color)
    tag.text:SetValue(text)
    tag.text:SetColor(color)
    tag:SetSize(math.ceil(tag.text:GetUnboundedStringWidth()) + 10, T.type.micro.lineHeight + 2)
    tag:Show()
end

-- one line of the drawing (pooled per layer: the dark underlay under the gilt)
function M:Line(layer, x1, y1, x2, y2, thickness, token, alpha)
    local pool = self.ink.pools[layer]
    pool.n = pool.n + 1
    local line = pool[pool.n]
    if not line then
        line = self.ink:CreateLine(nil, layer)
        pool[pool.n] = line
    end
    line:SetThickness(thickness)
    UI.PaintFill(line, token, alpha)
    line:SetStartPoint("TOPLEFT", self.ink, x1, -y1)
    line:SetEndPoint("TOPLEFT", self.ink, x2, -y2)
    line:Show()
end

-- dashes along a straight line: dash px drawn, gap px left out
function M:Dashes(layer, x1, y1, x2, y2, dash, gap, thickness, token, alpha)
    local len = math.sqrt((x2 - x1) ^ 2 + (y2 - y1) ^ 2)
    if len < 0.5 then return end
    -- (zoomed far in, longer dashes: no more than MAX_DASHES on a line)
    local stretch = math.max(1, len / (dash + gap) / MAX_DASHES)
    dash, gap = dash * stretch, gap * stretch
    local ux, uy = (x2 - x1) / len, (y2 - y1) / len
    local t = 0
    while t < len do
        local e = math.min(len, t + dash)
        self:Line(layer, x1 + ux * t, y1 + uy * t, x1 + ux * e, y1 + uy * e, thickness, token, alpha)
        t = e + gap
    end
end

-- A route solid: the gilt line on a dark underlay, so it reads on any art.
function M:Solid(points, width, token)
    for i = 1, #points - 1 do
        local a, b = points[i], points[i + 1]
        self:Line("BORDER", a[1], a[2], b[1], b[2], width + 3, "surface", 0.65)
        self:Line("ARTWORK", a[1], a[2], b[1], b[2], width, token)
    end
end

-- a stop on a route in flight: a small gilt disc on a surface rim
function M:Dot(x, y)
    local n = self.ink.dotN + 1
    self.ink.dotN = n
    local d = self.ink.dots[n]
    if not d then
        d = { rim = self.ink:CreateTexture(nil, "OVERLAY", nil, 1), fill = self.ink:CreateTexture(nil, "OVERLAY", nil, 2) }
        d.rim:SetTexture(DISC)
        d.rim:SetSize(9, 9)
        UI.Paint(d.rim, "surface")
        d.fill:SetTexture(DISC)
        d.fill:SetSize(6, 6)
        UI.Paint(d.fill, "gilt-text")
        self.ink.dots[n] = d
    end
    for _, t in ipairs({ d.rim, d.fill }) do
        t:ClearAllPoints()
        t:SetPoint("CENTER", self.ink, "TOPLEFT", x, -y)
        t:Show()
    end
end

function M:ClearDrawing()
    for _, pin in ipairs(self.pins or {}) do
        pin:Hide()
        pin:ClearAllPoints()
        pin:SetHighlight(nil)
        pin.tag:Hide()
        pin.node = nil
        table.insert(self.free, pin)
    end
    self.pins = {}
    self.view = nil
    self:ClearInk()
end

function M:ClearInk()
    local ink = self.ink
    if not ink then return end
    for _, pool in pairs(ink.pools) do
        for i = 1, #pool do pool[i]:Hide() end
        pool.n = 0
    end
    for _, d in ipairs(ink.dots) do d.rim:Hide(); d.fill:Hide() end
    ink.dotN = 0
    ink.left:Hide()
end

local function inside(p) return p[1] >= -0.01 and p[1] <= 1.01 and p[2] >= -0.01 and p[2] <= 1.01 end

-- The flight master's map: a pin for every node of yours on this map,
-- the time beside each destination.
function M:DrawMaster(pos, w, h, cs)
    local s = self.session
    local base = self.layer:GetFrameLevel()
    for _, n in ipairs(s.nodes) do
        local p = pos[n.id]
        if p and inside(p) then
            local pin = self:Pin()
            pin.node = n
            if n.kind == "DISTANT" then
                pin:SetData({ glyph = "wing", color = "ink-faint", edge = "ink-faint" })
                pin.edge:SetTexture(DASHED)
                pin:SetBaseAlpha(0.8)
                pin.tag:Hide()
            else
                local here = n.kind == "CURRENT"
                pin:SetData({ glyph = "wing", color = "gilt-text", edge = here and "arcane" or "gilt-line", ring = here and "arcane" or nil })
                pin.edge:SetTexture(DISC)
                pin:SetBaseAlpha(1)
                if here then
                    setTag(pin.tag, "You are here", "arcane")
                else
                    local t, measured = self:FlightTime(n.path)
                    setTag(pin.tag, timeText(t, measured), measured and "ink" or "ink-muted")
                end
            end
            pin:SetScale(1 / cs)
            pin:SetFrameLevel(base + (n.kind == "DISTANT" and 2 or 5))
            pin.tag:SetFrameLevel(base + 7)
            pin:SetPoint("CENTER", self.layer, "TOPLEFT", p[1] * w, -p[2] * h)
        end
    end
end

-- Its lines: the routes between the ones you know faint, the hovered (else
-- the chosen) destination's route solid; that one's pin ringed.
function M:InkMaster(pos, w, h)
    local s = self.session
    local known = {}
    for _, n in ipairs(s.nodes) do
        if n.kind ~= "DISTANT" and pos[n.id] then known[#known + 1] = n end
    end
    -- the network: each hop between two you know, once
    for i = 1, #known do
        for j = i + 1, #known do
            local a, b = known[i], known[j]
            if hopYards(a.id, b.id) then
                local pa, pb = pos[a.id], pos[b.id]
                self:Dashes("ARTWORK", pa[1] * w, pa[2] * h, pb[1] * w, pb[2] * h, 4, 4, 1.5, "gilt-line")
            end
        end
    end
    -- the route of the one hovered, else the one chosen
    local shown = self.hovered or self.selected
    if shown and shown.path then
        local points = {}
        for _, id in ipairs(shown.path) do
            local p = pos[id]
            if not p then points = nil break end
            points[#points + 1] = { p[1] * w, p[2] * h }
        end
        if points then self:Solid(points, 2.5, "gilt-text") end
    end
    for _, pin in ipairs(self.pins) do
        local n = pin.node
        pin:SetHighlight(n and (n == self.selected or n == self.hovered) and true or nil)
    end
end

-- How far along the flight you are: the point on the route nearest you
-- (the game gives your place in flight), else by the time flown along its
-- hops' lengths. -> the segment it's on, and the point.
function M:Along(points, path, w, h)
    local f = self.map
    local me = call(C_Map.GetPlayerMapPosition, f:GetMapID(), "player")
    local x, y
    if me and me.GetXY then x, y = me:GetXY() end
    if plain(x) and plain(y) and (x > 0 or y > 0) then
        x, y = x * w, y * h
        local best, bk, bx, by
        for k = 1, #points - 1 do
            local a, b = points[k], points[k + 1]
            local dx, dy = b[1] - a[1], b[2] - a[2]
            local l2 = dx * dx + dy * dy
            local t = l2 > 0 and math.max(0, math.min(1, ((x - a[1]) * dx + (y - a[2]) * dy) / l2)) or 0
            local px, py = a[1] + dx * t, a[2] + dy * t
            local d = (px - x) ^ 2 + (py - y) ^ 2
            if not best or d < best then best, bk, bx, by = d, k, px, py end
        end
        if bk then return bk, bx, by end
    end
    local fl = self.flight
    local total = fl.expected
    if not total then return 1, points[1][1], points[1][2] end
    local frac = math.min(1, (GetTime() - fl.started) / total)
    local lengths, sum = {}, 0
    for k = 1, #path - 1 do
        lengths[k] = hopYards(path[k], path[k + 1]) or 1
        sum = sum + lengths[k]
    end
    local want, run = frac * sum, 0
    for k = 1, #path - 1 do
        if run + lengths[k] >= want then
            local t = (want - run) / lengths[k]
            local a, b = points[k], points[k + 1]
            return k, a[1] + (b[1] - a[1]) * t, a[2] + (b[2] - a[2]) * t
        end
        run = run + lengths[k]
    end
    local last = points[#points]
    return #points - 1, last[1], last[2]
end

-- In the air: the route flown solid, the rest dashed, a dot at each stop,
-- the time left at the destination.
function M:DrawFlight(pos, w, h)
    local fl = self.flight
    local points = {}
    for _, id in ipairs(fl.path) do
        local p = pos[id]
        if not p then return end
        points[#points + 1] = { p[1] * w, p[2] * h }
    end
    local k, qx, qy = self:Along(points, fl.path, w, h)
    local flown = {}
    for i = 1, k do flown[i] = points[i] end
    flown[#flown + 1] = { qx, qy }
    self:Solid(flown, 3, "gilt")
    local rest = { { qx, qy } }
    for i = k + 1, #points do rest[#rest + 1] = points[i] end
    for i = 1, #rest - 1 do
        local a, b = rest[i], rest[i + 1]
        self:Dashes("BORDER", a[1], a[2], b[1], b[2], 5, 5, 5, "surface", 0.65)
        self:Dashes("ARTWORK", a[1], a[2], b[1], b[2], 5, 5, 2, "gilt-text")
    end
    for _, p in ipairs(points) do self:Dot(p[1], p[2]) end
    local dest = points[#points]
    if fl.expected then
        local left = fl.expected - (GetTime() - fl.started)
        local tag = self.ink.left
        setTag(tag, (fl.measured and "" or "~") .. clock(math.max(0, left)) .. " left", "ink")
        tag:ClearAllPoints()
        tag:SetPoint("LEFT", self.ink, "TOPLEFT", dest[1] + 10, -dest[2] + PIN / 2)
    end
end

-- Everything again (the map, its zoom, the flight master): the pins, then
-- the lines.
function M:Layout()
    self.layoutQueued = false
    self:ClearDrawing()
    local f = self.map
    if not (f and f:IsShown() and self:IsEnabled()) then return end
    local flying = not self.session and self.flight and self:Get("inFlight")
    if not (self.session or flying) then return end
    local canvas = f:GetCanvas()
    local cs = f:GetCanvasScale()
    if not (cs and cs > 0) then return end
    local w, h = canvas:GetWidth() * cs, canvas:GetHeight() * cs
    if w <= 0 or h <= 0 then return end
    local ink = self.ink
    ink:SetScale(1 / cs)
    ink:ClearAllPoints()
    ink:SetPoint("TOPLEFT", self.layer, "TOPLEFT")
    ink:SetSize(w, h)
    self.view = { pos = positions(f:GetMapID()), w = w, h = h }
    if self.session then self:DrawMaster(self.view.pos, w, h, cs) end
    self:DrawInk()
end

-- The lines alone (a hover, a choice, the clock in flight): the pins under
-- the mouse stay (made again, they'd lose and regain it, over and over).
function M:DrawInk()
    self.inkQueued = false
    self:ClearInk()
    local v = self.view
    if not v then return end
    if self.session then
        self:InkMaster(v.pos, v.w, v.h)
    elseif self.flight and self:Get("inFlight") then
        self:DrawFlight(v.pos, v.w, v.h)
    end
end

function M:QueueLayout()
    if self.layoutQueued then return end
    self.layoutQueued = true
    C_Timer.After(0, function() self:Layout() end)
end

function M:QueueInk()
    if self.inkQueued or self.layoutQueued then return end
    self.inkQueued = true
    C_Timer.After(0, function() if self.inkQueued then self:DrawInk() end end)
end

--------------------------------------------------------------------------------
-- The map
--------------------------------------------------------------------------------

function M:Attach()
    local f = _G.WorldMapFrame
    if not f or self.map then return end
    self.map = f
    -- over the map's art, under the game's own pins (as the world map
    -- module's pins)
    self.layer = CreateFrame("Frame", nil, f:GetCanvas())
    self.layer:SetAllPoints(f:GetCanvas())
    local levels = f.GetPinFrameLevelsManager and f:GetPinFrameLevelsManager()
    local above = levels and levels.GetFrameLevelStart and levels:GetFrameLevelStart("PIN_FRAME_LEVEL_MAP_HIGHLIGHT")
    self.layer:SetFrameLevel(above and (above + 1) or (f:GetCanvas():GetFrameLevel() + 2))
    self.pins, self.free = {}, {}
    local ink = CreateFrame("Frame", nil, self.layer)
    ink:SetFrameLevel(self.layer:GetFrameLevel())
    ink.pools = { BORDER = { n = 0 }, ARTWORK = { n = 0 } }
    ink.dots, ink.dotN = {}, 0
    -- the time left in flight, by the destination
    ink.left = CreateFrame("Frame", nil, ink)
    ink.left:SetFrameLevel(ink:GetFrameLevel() + 8)
    UI.Fill(ink.left, "surface-glass"):SetAllPoints()
    UI.Border(ink.left, "gilt-hairline")
    ink.left.text = UI.Text(ink.left, "micro", "ink")
    ink.left.text:SetPoint("CENTER", 0, 0)
    ink.left:Hide()
    self.ink = ink
    -- the clock in flight: the time left and where you are, every second
    local wait = 0
    ink:SetScript("OnUpdate", function(_, elapsed)
        wait = wait - elapsed
        if wait > 0 then return end
        wait = 1
        if self.flight and not self.session and self:Get("inFlight") then self:DrawInk() end
    end)
    local provider = CreateFromMixins(MapCanvasDataProviderMixin)
    provider.RefreshAllData = function() self:QueueLayout() end
    provider.RemoveAllData = function() self:ClearDrawing() end
    provider.OnCanvasScaleChanged = function() self:QueueLayout() end
    provider.OnCanvasSizeChanged = function() self:QueueLayout() end
    self.provider = provider
    -- the map closed at the flight master: the flight master too
    f:HookScript("OnHide", function()
        if self.session and not self.closing then
            self:LeaveMaster(false)
            if CloseTaxiMap then CloseTaxiMap() end
        end
    end)
    -- opened in the air: the continent, where the route shows
    f:HookScript("OnShow", function()
        if self:IsEnabled() and self.flight and not self.session and self:Get("inFlight") then
            C_Timer.After(0, function()
                local continent = continentOf(C_Map.GetBestMapForUnit("player"))
                if continent and f:IsShown() and f:GetMapID() ~= continent then f:SetMapID(continent) end
            end)
        end
    end)
    -- the quest log opened or closed: the destinations go with it
    if f.SetQuestLogPanelShown then
        hooksecurefunc(f, "SetQuestLogPanelShown", function() if self.session then self:PlaceSide() end end)
    end
    -- the header keeps "Flight master" over map changes (the window skin
    -- names the map on each)
    EventRegistry:RegisterCallback("MapCanvas.MapSet", function()
        if self.session then C_Timer.After(0, function() self:SetTitle(true) end) end
    end, self)
end

-- Settings › Flight map
local SECTION = {
    id = "flightmap", label = "Flight map", category = "World", order = 13,
    groups = {
        { title = "At a flight master", rows = {
            { key = "atMaster", label = "The world map as the flight map", control = "toggle",
              description = "At a flight master SuuUI's world map shows where you can fly: every flight master, the routes between the ones you've found, and each flight's time and cost. Click a destination, then Fly. Off: the game's own flight map." },
        } },
        { title = "While flying", rows = {
            { key = "inFlight", label = "Your flight on the map", control = "toggle",
              description = "Open the map in the air to see your route: the part flown solid, the rest dashed, the time left at your destination." },
        } },
        { title = "Flight times", rows = {
            { label = "Timed flights", control = "button", text = "Forget",
              description = function() return M:TimesSummary() end,
              onClick = function()
                  UI.Confirm({ title = "Forget flight times?",
                      text = "Every route's measured time, for all your characters, and this character's flight speed. Times are estimated from the routes' lengths again until you fly them.",
                      confirm = "Forget", onConfirm = function() M:ForgetTimes() end })
              end },
        } },
    },
}

function M:TimesSummary()
    local n = 0
    for _ in pairs(timed()) do n = n + 1 end
    local flights = self:CharData().flights or 0
    local speed = ("%.1f yards a second"):format(self:Speed())
    local learned = flights > 0 and (" (from " .. flights .. (flights == 1 and " flight)" or " flights)")) or " (not flown yet)"
    return ("Each flight is timed; a route you've flown shows its time, others an estimate from their length at this character's speed: %s%s. Routes timed for the account: %d."):format(speed, learned, n)
end

function M:ForgetTimes()
    SuuUI.AccountData("flightmap").routes = {}
    local data = self:CharData()
    data.speed, data.flights = nil, nil
    if self.session then self:UpdateRows(); self:UpdateBar() end
    self:QueueLayout()
end

function M:OnEnable()
    self:Attach()
    if not self.map then
        self:OnGameEvent("ADDON_LOADED", function()
            if not self.map and _G.WorldMapFrame then self:Attach(); self:OnEnable() end
        end)
        return
    end
    self:RegisterSettings(SECTION)
    self.map:AddDataProvider(self.provider)
    self.layer:Show()
    -- every flight's route, whichever map took it (the hook stays; it
    -- does nothing while the module is off)
    if not self.takeHooked and TakeTaxiNode then
        self.takeHooked = true
        hooksecurefunc("TakeTaxiNode", function(slot) if self:IsEnabled() then self:Taking(slot) end end)
    end
    self:OnGameEvent("TAXIMAP_OPENED", function() self:OnTaxiOpened() end)
    self:OnGameEvent("TAXIMAP_CLOSED", function() self:LeaveMaster(true) end)
    -- on a taxi a moment after control goes; landed when it comes back
    self:OnGameEvent("PLAYER_CONTROL_LOST", function()
        local at = GetTime()
        C_Timer.After(0.5, function() self:FlightStarted(at) end)
    end)
    self:OnGameEvent("PLAYER_CONTROL_GAINED", function()
        local at = GetTime()
        C_Timer.After(0.3, function() if not UnitOnTaxi("player") then self:FlightEnded(at) end end)
    end)
    self:OnGameEvent("PLAYER_ENTERING_WORLD", function()
        if not self.flight then self:ResumeFlight() end
        self:QueueLayout()
    end)
    self:Watch("atMaster", function() if not self:Get("atMaster") and self.session then self:LeaveMaster(false) end end)
    self:Watch("inFlight", function() self:QueueLayout() end)
    -- a theme: the tags and the bar measured again
    self:On("SUUUI_THEME_CHANGED", function()
        if self.session then self:UpdateBar() end
        self:QueueLayout()
    end)
end

function M:OnDisable()
    -- (at a flight master: the game's own map back, the session open)
    self:LeaveMaster(false)
    self.flight, self.pending = nil, nil
    if not self.map then return end
    self.map:RemoveDataProvider(self.provider)
    self:ClearDrawing()
    self.layer:Hide()
    refreshPins()
end
