-- Diagnostics/MapProbe.lua
-- "/suu probe map": what Forever's world map is made of and what an addon
-- can read for SuuUI's world map (step 3.5). Saved in SuuUIProbe.map on
-- /reload. Open the map once first (M), ideally in a zone with quests in
-- your log, and in a group if you can.
--   * WorldMapFrame: its parts, size, whether it's protected, its quest
--     panel, the pin kinds the game draws (its pin pools) and its data
--     providers
--   * where you are: the map, its parents and children, your position
--     (secret or not), group members' positions
--   * quests: the log's entries (fields), quests on this map with their
--     positions (C_QuestLog.GetQuestsOnMap), quest lines to pick up
--     (C_QuestLine), the next waypoint
--   * places: flight masters (C_TaxiMap), dungeon entrances
--     (C_EncounterJournal), user waypoints (C_Map), map areas
--   * the map's own filters (its tracking menu's CVars)

local _, ns = ...

local MP = {}
ns.MapProbe = MP

local isSecret = issecretvalue or function() return false end

local function show(v, depth)
    depth = depth or 0
    if isSecret(v) then return "<secret>" end
    if type(v) ~= "table" then return tostring(v) end
    if depth > 1 then return "{…}" end
    local parts = {}
    for k, x in pairs(v) do
        parts[#parts + 1] = tostring(k) .. "=" .. (isSecret(x) and "<secret>" or (type(x) == "table" and show(x, depth + 1) or tostring(x)))
    end
    table.sort(parts)
    return "{" .. table.concat(parts, ", ") .. "}"
end

local function call(t, name, ...)
    if not (t and type(t[name]) == "function") then return "missing" end
    local ok, a, b, c = pcall(t[name], ...)
    if not ok then return "error: " .. tostring(a) end
    return a, b, c
end

function MP.Snapshot()
    SuuUIProbe = SuuUIProbe or {}
    local s = { at = date("%Y-%m-%d %H:%M:%S") }
    SuuUIProbe.map = s

    -- the window
    local f = _G.WorldMapFrame
    s.frame = { exists = f ~= nil }
    if f then
        local w = s.frame
        w.protected = f:IsProtected() and true or false
        w.shown = f:IsShown()
        w.size = math.floor(f:GetWidth()) .. "x" .. math.floor(f:GetHeight())
        w.keys = {}
        for k, v in pairs(f) do
            if type(k) == "string" and type(v) == "table" and v.GetObjectType then w.keys[#w.keys + 1] = k .. " (" .. v:GetObjectType() .. ")" end
        end
        table.sort(w.keys)
        w.pinPools = {}
        for template in pairs(f.pinPools or {}) do w.pinPools[#w.pinPools + 1] = tostring(template) end
        table.sort(w.pinPools)
        w.providers = 0
        for _ in pairs(f.dataProviders or {}) do w.providers = w.providers + 1 end
        w.mapID = call(f, "GetMapID", f)
        w.quest = { QuestMapFrame = _G.QuestMapFrame ~= nil, QuestLogFrame = _G.QuestLogFrame ~= nil,
                    QuestScrollFrame = _G.QuestScrollFrame ~= nil }
        w.overlays = {}
        for _, frame in ipairs(f.overlayFrames or {}) do w.overlays[#w.overlays + 1] = frame:GetName() or frame:GetObjectType() end
    end

    -- where you are
    local cm = C_Map
    local map = call(cm, "GetBestMapForUnit", "player")
    s.mapID = show(map)
    if type(map) == "number" and not isSecret(map) then
        s.mapInfo = show((call(cm, "GetMapInfo", map)))
        local pos = call(cm, "GetPlayerMapPosition", map, "player")
        s.position = type(pos) == "table" and show({ pos:GetXY() }) or show(pos)
        local kids = call(cm, "GetMapChildrenInfo", map)
        s.children = type(kids) == "table" and #kids or show(kids)
        local groups = call(cm, "GetMapGroupID", map)
        s.mapGroup = show(groups)
        s.party = {}
        for i = 1, 4 do
            if UnitExists("party" .. i) then
                local p = call(cm, "GetPlayerMapPosition", map, "party" .. i)
                s.party[#s.party + 1] = "party" .. i .. " " .. (type(p) == "table" and show({ p:GetXY() }) or show(p))
            end
        end
        -- quests on this map
        local ql = C_QuestLog
        local on = call(ql, "GetQuestsOnMap", map)
        s.questsOnMap = type(on) == "table" and { count = #on, first = on[1] and show(on[1]) or "none" } or show(on)
        local lines = C_QuestLine and call(C_QuestLine, "GetAvailableQuestLines", map)
        s.questLines = type(lines) == "table" and { count = #lines, first = lines[1] and show(lines[1]) or "none" } or show(lines)
        local poi = C_QuestLine and call(C_QuestLine, "GetQuestLineQuests")
        s.questLineFn = poi ~= "missing"
        -- places
        local taxi = C_TaxiMap and call(C_TaxiMap, "GetTaxiNodesForMap", map)
        s.taxi = type(taxi) == "table" and { count = #taxi, first = taxi[1] and show(taxi[1]) or "none" } or show(taxi)
        local ej = C_EncounterJournal and call(C_EncounterJournal, "GetDungeonEntrancesForMap", map)
        s.dungeons = type(ej) == "table" and { count = #ej, first = ej[1] and show(ej[1]) or "none" } or show(ej)
        s.userWaypoint = { can = show((call(cm, "CanSetUserWaypointOnMap", map))), has = show((call(cm, "HasUserWaypoint"))) }
        local areas = C_MapExplorationInfo and call(C_MapExplorationInfo, "GetExploredAreaIDsAtPosition", map, CreateVector2D and CreateVector2D(0.5, 0.5))
        s.exploration = show(areas)
    end

    -- the quest log
    local ql = C_QuestLog
    local n = call(ql, "GetNumQuestLogEntries")
    s.questLog = { entries = show(n), sample = {} }
    if type(n) == "number" and not isSecret(n) then
        for i = 1, math.min(n, 12) do
            local info = call(ql, "GetInfo", i)
            if type(info) == "table" and not info.isHeader then
                local id = info.questID
                local entry = { info = show(info) }
                entry.difficultyLevel = show(info.difficultyLevel)
                entry.objectives = show((call(ql, "GetQuestObjectives", id)))
                entry.complete = show((call(ql, "IsComplete", id)))
                entry.waypoint = show({ call(C_QuestLog, "GetNextWaypoint", id) })
                entry.uiMap = show((call(GetQuestUiMapID and _G or {}, "GetQuestUiMapID", id)))
                s.questLog.sample[#s.questLog.sample + 1] = entry
                if #s.questLog.sample >= 4 then break end
            end
        end
    end

    -- the map's filters (its tracking menu)
    s.cvars = {}
    for _, cv in ipairs({ "questPOI", "showQuestObjectivesOnMap", "trivialQuests", "showDungeonEntrancesOnMap",
                          "questHelper", "mapFade", "showTamers", "primaryProfessionsFilter", "worldQuestFilterResources" }) do
        local ok, v = pcall(GetCVar, cv)
        s.cvars[cv] = ok and show(v) or "error"
    end
    ns.Print(("Map probe: %s pin kinds, %s quests on this map, %s flight masters; /reload."):format(
        tostring(s.frame.pinPools and #s.frame.pinPools or 0),
        tostring(type(s.questsOnMap) == "table" and s.questsOnMap.count or s.questsOnMap),
        tostring(type(s.taxi) == "table" and s.taxi.count or s.taxi)))
end

-- "/suu probe map areas": why the game draws no quest objective area (it
-- draws the followed quest's and the one hovered in the log).
function MP.Areas()
    SuuUIProbe = SuuUIProbe or {}
    local s = { at = date("%Y-%m-%d %H:%M:%S") }
    SuuUIProbe.mapAreas = s
    local f = _G.WorldMapFrame
    s.mapID = f and show((call(f, "GetMapID", f)))
    s.questPOI = show((call(_G, "GetCVar", "questPOI")))
    s.superTracked = show((call(C_SuperTrack, "GetSuperTrackedQuestID")))
    s.superTrackingWaypoint = show((call(C_SuperTrack, "IsSuperTrackingUserWaypoint")))
    s.highestType = show((call(C_SuperTrack, "GetHighestPrioritySuperTrackingType")))
    s.pins = {}
    if f and f.EnumeratePinsByTemplate then
        for pin in f:EnumeratePinsByTemplate("QuestBlobPinTemplate") do
            s.pins[#s.pins + 1] = {
                shown = pin:IsShown(), visible = pin:IsVisible(), alpha = pin:GetAlpha(), level = pin:GetFrameLevel(),
                size = math.floor(pin:GetWidth()) .. "x" .. math.floor(pin:GetHeight()),
                questID = show(pin.questID), focused = show(pin.focusedQuestID), highlighted = show(pin.highlightedQuestID),
                mapAllowsBlobs = show(pin.mapAllowsBlobs), map = show((call(pin, "GetMapID", pin))),
            }
        end
    end
    -- the quests on this map: do they have an area here?
    local map = f and f:GetMapID()
    local on = map and call(C_QuestLog, "GetQuestsOnMap", map)
    s.questsOnMap = {}
    for _, q in ipairs(type(on) == "table" and on or {}) do
        s.questsOnMap[#s.questsOnMap + 1] = show(q)
        if #s.questsOnMap >= 8 then break end
    end
    s.ourLayer = SuuUI.GetModule and SuuUI.GetModule("worldmap") and SuuUI.GetModule("worldmap").layer
        and SuuUI.GetModule("worldmap").layer:GetFrameLevel() or "none"
    ns.Print(("Areas: questPOI %s, followed quest %s, %d area pins (%s); /reload saves it."):format(
        s.questPOI, s.superTracked, #s.pins, s.pins[1] and ((s.pins[1].visible and "visible" or "hidden") .. ", allowed " .. s.pins[1].mapAllowsBlobs) or "none"))
end

-- "/suu probe map log": where the quest log's parts sit, to line them up
-- (the list centred, the search box with it): each part's left and right
-- from the panel's left (the map's right edge), its width, whether it
-- shows, and its anchors.
local function where(obj, x0)
    if not (obj and obj.GetLeft) then return nil end
    local ok, l, r = pcall(function() return obj:GetLeft(), obj:GetRight() end)
    local out = { shown = obj.IsShown and obj:IsShown() or false, kind = obj.GetObjectType and obj:GetObjectType() or "?" }
    if ok and l and r then
        out.left, out.right, out.width = math.floor(l - x0 + 0.5), math.floor(r - x0 + 0.5), math.floor(r - l + 0.5)
    end
    local points = {}
    for i = 1, (obj.GetNumPoints and obj:GetNumPoints() or 0) do
        local pt, rel, relPt, x, y = obj:GetPoint(i)
        local name = rel and (rel.GetName and rel:GetName()) or nil
        if not name and rel and rel.GetParent and rel:GetParent() then
            for k, v in pairs(rel:GetParent()) do if v == rel then name = "$parent." .. tostring(k) end end
        end
        points[#points + 1] = ("%s>%s %s %s,%s"):format(pt, tostring(relPt), tostring(name or rel), tostring(x and math.floor(x + 0.5)), tostring(y and math.floor(y + 0.5)))
    end
    out.points = table.concat(points, "; ")
    return out
end

function MP.Log()
    SuuUIProbe = SuuUIProbe or {}
    local f, q = _G.WorldMapFrame, _G.QuestMapFrame
    local s = { at = date("%Y-%m-%d %H:%M:%S") }
    SuuUIProbe.mapLog = s
    local x0 = f.ScrollContainer and f.ScrollContainer:GetRight() or 0
    s.window = where(f, x0)
    s.mapArea = where(f.ScrollContainer, x0)
    s.enlarged = SuuUI.GetModule("windows") and SuuUI.GetModule("windows"):Get("mapEnlarged")
    if not q then ns.Print("Map log: no quest log.") return end
    s.questMapFrame = where(q, x0)
    -- each part one level down, by its key, in the log, its quests frame and its list
    local function walk(label, t)
        if not t then return end
        s[label] = {}
        for k, v in pairs(t) do
            if type(v) == "table" and type(k) == "string" and v.GetLeft and k ~= "GetParent" then
                s[label][k] = where(v, x0)
            end
        end
    end
    walk("log", q)
    walk("quests", q.QuestsFrame)
    walk("list", q.QuestsFrame and q.QuestsFrame.ScrollFrame or _G.QuestScrollFrame)
    local list = _G.QuestScrollFrame
    walk("contents", list and list.Contents)
    -- the first rows of each kind
    s.rows = {}
    for _, key in ipairs({ "headerFramePool", "campaignHeaderMinimalFramePool", "titleFramePool", "objectiveFramePool" }) do
        local pool = list and list[key]
        if pool and pool.EnumerateActive then
            for row in pool:EnumerateActive() do s.rows[key] = where(row, x0) break end
        end
    end
    local sb = list and list.SearchBox
    ns.Print(("Map log: panel %s px wide; list %s..%s; search box %s..%s; /reload saves it."):format(
        tostring(s.window and s.window.right), tostring(s.rows.headerFramePool and s.rows.headerFramePool.left),
        tostring(s.rows.headerFramePool and s.rows.headerFramePool.right),
        tostring(sb and where(sb, x0).left), tostring(sb and where(sb, x0).right)))
end

function MP.Command(rest)
    if rest == "log" then
        if not (_G.WorldMapFrame and _G.WorldMapFrame:IsShown()) then ns.Print("Map probe: open the map with its quest log, then run it again.") return end
        MP.Log()
        return
    end
    if rest == "areas" then
        if not _G.WorldMapFrame then ns.Print("Map probe: open the map once (M), then run it again.") return end
        MP.Areas()
        return
    end
    if not _G.WorldMapFrame then
        ns.Print("Map probe: open the map once (M), then run it again.")
        return
    end
    MP.Snapshot()
end
