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

function MP.Command()
    if not _G.WorldMapFrame then
        ns.Print("Map probe: open the map once (M), then run it again.")
        return
    end
    MP.Snapshot()
end
