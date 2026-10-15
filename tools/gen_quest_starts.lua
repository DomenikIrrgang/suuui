-- tools/gen_quest_starts.lua
-- Writes src/Data/QuestStarts.lua: where each of Forever's quests can be
-- picked up (its quest givers' spawn points, by the game's map IDs), with
-- what the world map needs to tell whether you can take it (levels, races,
-- classes, quests before it and instead of it), and the dungeon entrances.
-- Reads QuestieDB's Forever data with its corrections applied in
-- QuestieDB's order (inherited classic fixes, the generated Forever base,
-- the Forever fixes), from the folder tools/fetch_quest_starts.sh fills.
-- Every downloaded file runs in a sandbox without io, os or require.
--   lua tools/gen_quest_starts.lua <dir> src/Data/QuestStarts.lua

local dir, out = arg[1], arg[2]
assert(dir and out, "usage: lua tools/gen_quest_starts.lua <dir> <out.lua>")

local function read(path)
    local f = assert(io.open(dir .. "/" .. path, "rb"), "missing " .. path .. " (run tools/fetch_quest_starts.sh)")
    local s = f:read("a")
    f:close()
    return s
end

-- An endless table for anything the files reach for that we don't model.
local function stub()
    return setmetatable({}, {
        __index = function(t, k) local s = stub(); rawset(t, k, s); return s end,
        __call = function() return stub() end,
    })
end
local function isStub(v) return type(v) == "table" and getmetatable(v) ~= nil end

-- The modules the files share (QuestieLoader's registry).
local modules = {}
local function module(name)
    modules[name] = modules[name] or { private = {} }
    return modules[name]
end
local QuestieLoader = {
    CreateModule = function(_, name) return module(name) end,
    ImportModule = function(_, name) return module(name) end,
}
-- l10n is called like a function (a translation: the text as it is)
modules.l10n = setmetatable({ private = {} }, { __call = function(_, s) return s end, __index = function() return stub() end })
-- phases: only spawn details we don't use
modules.Phasing = { private = {}, phases = stub() }

local env = setmetatable({
    QuestieLoader = QuestieLoader,
    l10n = setmetatable({}, { __call = function(_, s) return s end }),
    UnitFactionGroup = function() return "Horde" end,
    pairs = pairs, ipairs = ipairs, next = next, type = type, tostring = tostring, tonumber = tonumber,
    select = select, unpack = table.unpack, table = table, string = string, math = math,
    setmetatable = setmetatable, getmetatable = getmetatable, rawget = rawget, rawset = rawset,
    error = error, assert = assert, pcall = pcall, print = function() end,
}, { __index = function(t, k) local s = stub(); rawset(t, k, s); return s end })

local function run(path, ...)
    local chunk = assert(load(read(path), "@" .. path, "t", env))
    return chunk(...)
end

-- the enums (constants.lua first: raceMaskById)
-- (constants.lua puts its own table in lib.Enum; the others fill it)
local lib = {}
for _, f in ipairs({ "constants", "zones", "expansions", "factions", "professions", "quests" }) do
    run("src/corrections/enum/" .. f .. ".lua", "QuestieDB", lib)
end
local constants = lib.Enum
local byExp = constants.byExpansion or {}
local function merged(key)
    local t = {}
    for k, v in pairs((byExp.Classic or {})[key] or {}) do t[k] = v end
    for k, v in pairs((byExp.Forever or {})[key] or {}) do t[k] = v end
    return t
end

local QuestieDB = module("QuestieDB")
QuestieDB.raceKeys = merged("raceKeys")
QuestieDB.classKeys = merged("classKeys")
QuestieDB.npcFlags = merged("npcFlags")
QuestieDB.waypointPresets = merged("waypointPresets")
QuestieDB.sortKeys = constants.sortKeys or {}
QuestieDB.specialFlags = constants.specialFlags or {}
QuestieDB.questFlags = constants.questFlags or {}
QuestieDB.factionIDs = constants.factionIDs or {}
local ZoneDB = module("ZoneDB")
ZoneDB.zoneIDs = constants.zoneIDs or {}
local Professions = module("QuestieProfessions")
Professions.professionKeys = constants.professionKeys or {}
Professions.specializationKeys = constants.specializationKeys or {}
Professions.rankNames = constants.rankNames or {}
local Corrections = module("QuestieCorrections")
for _, k in ipairs({ "itemObjectiveFirst", "killCreditObjectiveFirst", "objectObjectiveFirst" }) do Corrections[k] = {} end

-- the data (the files set QuestieDB.questKeys and a "return {…}" string)
local function data(path, field)
    run(path)
    local chunk = assert(load(QuestieDB[field], "@" .. path, "t", {}))
    return chunk()
end
local quests = data("data/Forever/foreverQuestDB.lua", "questData")
local npcs = data("data/Forever/foreverNpcDB.lua", "npcData")
local objects = data("data/Forever/foreverObjectDB.lua", "objectData")

-- Correction keys also come as "<field>_add" (+1000) and "<field>_remove"
-- (-1000): table operations (QuestieDB docs/adr/0016). Lists add missing
-- values and remove exact ones; grouped fields (givers by kind, spawns by
-- zone) do that within each group they name.
local function aliases(keys)
    local base = {}
    for name, i in pairs(keys or {}) do if type(i) == "number" then base[name] = i end end
    for name, i in pairs(base) do keys[name .. "_add"] = i + 1000; keys[name .. "_remove"] = i - 1000 end
end
local function same(a, b)
    if type(a) ~= "table" or type(b) ~= "table" then return a == b end
    for k, v in pairs(a) do if not same(v, b[k]) then return false end end
    for k in pairs(b) do if a[k] == nil then return false end end
    return true
end
local function listAdd(list, values)
    list = type(list) == "table" and list or {}
    for _, v in ipairs(values) do
        local found = false
        for _, x in ipairs(list) do if same(x, v) then found = true break end end
        if not found then list[#list + 1] = v end
    end
    return list
end
local function listRemove(list, values)
    if type(list) ~= "table" then return list end
    local out = {}
    for _, x in ipairs(list) do
        local drop = false
        for _, v in ipairs(values) do if same(x, v) then drop = true break end end
        if not drop then out[#out + 1] = x end
    end
    return out
end
local GROUPED = {} -- per db: field index -> true (filled once the keys are known)
local function operate(db, row, k, v)
    local add = k > 1000
    local field = add and (k - 1000) or (k + 1000)
    if type(v) ~= "table" then return end
    local cur = row[field]
    if GROUPED[db] and GROUPED[db][field] then
        cur = type(cur) == "table" and cur or {}
        for g, values in pairs(v) do
            if type(values) == "table" then
                cur[g] = add and listAdd(cur[g], values) or listRemove(cur[g], values)
            end
        end
        row[field] = cur
    else
        row[field] = add and listAdd(cur, v) or listRemove(cur, v)
    end
end

-- the corrections, in QuestieDB's order
local function correct(db, files)
    for _, f in ipairs(files) do
        local before = {}
        for name in pairs(modules) do before[name] = true end
        run(f)
        for name, m in pairs(modules) do
            if not before[name] and type(rawget(m, "Load")) == "function" then
                local ok, fixes = pcall(m.Load, m)
                if ok and type(fixes) == "table" then
                    for id, fields in pairs(fixes) do
                        if type(id) == "number" and type(fields) == "table" then
                            local row = db[id] or {}
                            for k, v in pairs(fields) do
                                if type(k) == "number" and not isStub(v) then
                                    if k > 1000 or k < 0 then operate(db, row, k, v) else row[k] = v end
                                end
                            end
                            db[id] = row
                        end
                    end
                elseif not ok then
                    io.stderr:write("gen_quest_starts: ", f, ": ", tostring(fixes), "\n")
                end
            end
        end
    end
end
local QK, NK, OK = QuestieDB.questKeys, QuestieDB.npcKeys, QuestieDB.objectKeys
aliases(QuestieDB.questKeys)
aliases(QuestieDB.npcKeys)
aliases(QuestieDB.objectKeys)
GROUPED[quests] = { [QuestieDB.questKeys.startedBy] = true, [QuestieDB.questKeys.finishedBy] = true }
GROUPED[npcs] = { [QuestieDB.npcKeys.spawns] = true, [QuestieDB.npcKeys.waypoints] = true }
GROUPED[objects] = { [QuestieDB.objectKeys.spawns] = true, [QuestieDB.objectKeys.waypoints] = true }
local C = "src/corrections/Forever/"
correct(quests, { C .. "legacy/classicQuestFixes.lua", C .. "generated/foreverBaseQuest.lua", C .. "foreverQuestFixes.lua" })
correct(npcs, { C .. "legacy/classicNPCFixes.lua", C .. "generated/foreverBaseNpc.lua", C .. "foreverNPCFixes.lua" })
correct(objects, { C .. "legacy/classicObjectFixes.lua", C .. "generated/foreverBaseObject.lua", C .. "foreverObjectFixes.lua" })

-- area IDs to the game's map IDs (the override first)
run("support/Forever/Zones/areaIdToUiMapId.lua")
local function mapTable(s) return s and assert(load(s, "@areaIdToUiMapId", "t", {}))() or {} end
local areaToMap = mapTable(ZoneDB.private.areaIdToUiMapId)
for k, v in pairs(mapTable(ZoneDB.private.areaIdToUiMapIdOverride)) do areaToMap[k] = v end

-- each giver's spawn points as { map = { {x, y}, ... } } (at most 3 per map)
local function spawnsOf(row, key)
    local out = {}
    for area, coords in pairs(row and row[key] or {}) do
        local map = areaToMap[area]
        if map and map > 0 and type(coords) == "table" then
            local list = out[map] or {}
            out[map] = list
            for _, c in ipairs(coords) do
                if #list < 3 and type(c) == "table" and c[1] and c[1] >= 0 then list[#list + 1] = { c[1], c[2] } end
            end
        end
    end
    return out
end

local pins = {}      -- map -> "x,y" -> { x, y, quests }
local used = {}      -- quest IDs with a pin
local function pin(map, x, y, qid)
    local m = pins[map] or {}
    pins[map] = m
    local key = string.format("%.1f,%.1f", x, y)
    local p = m[key] or { x = x, y = y, quests = {} }
    m[key] = p
    p.quests[#p.quests + 1] = qid
    used[qid] = true
end

-- who starts each quest: the quest's own givers, and every NPC or object
-- that names it among its questStarts (corrections add to either side)
local giversOf = {}
local function giver(qid, kind, id)
    local g = giversOf[qid] or { {}, {} }
    giversOf[qid] = g
    for _, x in ipairs(g[kind]) do if x == id then return end end
    g[kind][#g[kind] + 1] = id
end
for qid, q in pairs(quests) do
    local starts = q[QK.startedBy]
    if type(starts) == "table" then
        for _, npc in ipairs(type(starts[1]) == "table" and starts[1] or {}) do giver(qid, 1, npc) end
        for _, obj in ipairs(type(starts[2]) == "table" and starts[2] or {}) do giver(qid, 2, obj) end
    end
end
for id, n in pairs(npcs) do
    for _, qid in ipairs(type(n[NK.questStarts]) == "table" and n[NK.questStarts] or {}) do if quests[qid] then giver(qid, 1, id) end end
end
for id, o in pairs(objects) do
    for _, qid in ipairs(type(o[OK.questStarts]) == "table" and o[OK.questStarts] or {}) do if quests[qid] then giver(qid, 2, id) end end
end

local ids = {}
for id in pairs(quests) do ids[#ids + 1] = id end
table.sort(ids)
for _, qid in ipairs(ids) do
    local starts = giversOf[qid]
    if starts then
        for _, npc in ipairs(starts[1]) do
            for map, list in pairs(spawnsOf(npcs[npc], NK.spawns)) do
                for _, c in ipairs(list) do pin(map, c[1], c[2], qid) end
            end
        end
        for _, obj in ipairs(starts[2]) do
            for map, list in pairs(spawnsOf(objects[obj], OK.spawns)) do
                for _, c in ipairs(list) do pin(map, c[1], c[2], qid) end
            end
        end
    end
end

-- dungeon and raid entrances, per map: read once as each faction (a few
-- differ: the battlegrounds)
local entrances = {}
-- Forever's content is the original game's: the later expansions' changes
-- to entrances (Expansions.Current >= Wotlk) don't apply
local Expansions = module("Expansions")
Expansions.Era, Expansions.Tbc, Expansions.Wotlk, Expansions.Cata, Expansions.MoP = 1, 2, 3, 4, 5
Expansions.Current = 1
local function readDungeons(faction)
    env.UnitFactionGroup = function() return faction end
    ZoneDB.private.dungeons = nil
    run("support/Forever/Zones/dungeons.lua")
    return ZoneDB.private.dungeons or {}
end
local horde, alliance = readDungeons("Horde"), readDungeons("Alliance")
local seen = {}
for _, side in ipairs({ { horde, "H" }, { alliance, "A" } }) do
    for area, d in pairs(side[1]) do
        if type(d) == "table" and type(d[1]) == "string" and type(d[4]) == "table" then
            for _, loc in ipairs(d[4]) do
                local map = type(loc) == "table" and areaToMap[loc[1]]
                if map and map > 0 and type(loc[2]) == "number" then
                    local key = string.format("%d,%.1f,%.1f,%s", map, loc[2], loc[3], d[1])
                    if seen[key] then seen[key].faction = nil
                    else
                        local e = { x = loc[2], y = loc[3], name = d[1], area = area, faction = side[2] }
                        seen[key] = e
                        entrances[map] = entrances[map] or {}
                        table.insert(entrances[map], e)
                    end
                end
            end
        end
    end
end

-- write
local function list(t)
    if type(t) ~= "table" or #t == 0 then return "nil" end
    local s = {}
    for _, v in ipairs(t) do if type(v) == "number" then s[#s + 1] = tostring(v) end end
    return #s > 0 and ("{" .. table.concat(s, ",") .. "}") or "nil"
end
local function num(v) return type(v) == "number" and string.format("%d", v) or "nil" end
local function str(v) return type(v) == "string" and string.format("%q", v) or "nil" end

local sources = {}
for line in read("SOURCES"):gmatch("[^\n]+") do local k, v = line:match("^(%S+)\t(.*)$"); if k then sources[k] = v end end

local o = {}
local function w(s) o[#o + 1] = s end
w("-- Data/QuestStarts.lua (generated by tools/gen_quest_starts.lua: do not edit)")
w("-- Where each of Forever's quests is picked up, for the world map.")
w("--   QuestieDB Forever data with its corrections, commit " .. (sources.questiedb or "?") .. " (github.com/Questie/QuestieDB, no license stated)")
w("--   fetched " .. (sources.fetched or "?") .. "; rebuild: sh tools/update_quest_starts.sh")
w("--   quests[id] = { name, minLevel, level, races (mask), classes (mask), preGroup (all), preSingle (any),")
w("--                  exclusiveTo, nextInChain, specialFlags, parentQuest, breadcrumbFor }")
w("--   maps[uiMapID] = { { x, y, questID, ... }, ... }   (x, y in percent)")
w("--   entrances[uiMapID] = { { x, y, name, faction (\"H\", \"A\" or nil) }, ... }   (dungeons and raids)")
w("")
w("local _, ns = ...")
w("")
w("ns.QuestStarts = { quests = {")
for _, qid in ipairs(ids) do
    if used[qid] then
        local q = quests[qid]
        w(string.format("    [%d] = { %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s },", qid,
            str(q[QK.name]), num(q[QK.requiredLevel]), num(q[QK.questLevel]), num(q[QK.requiredRaces]), num(q[QK.requiredClasses]),
            list(q[QK.preQuestGroup]), list(q[QK.preQuestSingle]), list(q[QK.exclusiveTo]), num(q[QK.nextQuestInChain]),
            num(q[QK.specialFlags]), num(q[QK.parentQuest]), num(q[QK.breadcrumbForQuestId])))
    end
end
w("}, maps = {")
local maps = {}
for map in pairs(pins) do maps[#maps + 1] = map end
table.sort(maps)
local total = 0
for _, map in ipairs(maps) do
    local keys = {}
    for k in pairs(pins[map]) do keys[#keys + 1] = k end
    table.sort(keys)
    local rows = {}
    for _, k in ipairs(keys) do
        local p = pins[map][k]
        rows[#rows + 1] = string.format("{%.1f,%.1f,%s}", p.x, p.y, table.concat(p.quests, ","))
        total = total + 1
    end
    w(string.format("    [%d] = {%s},", map, table.concat(rows, ",")))
end
w("}, entrances = {")
local emaps = {}
for map in pairs(entrances) do emaps[#emaps + 1] = map end
table.sort(emaps)
local nEntrances = 0
for _, map in ipairs(emaps) do
    table.sort(entrances[map], function(a, b) return a.name < b.name end)
    local rows = {}
    for _, e in ipairs(entrances[map]) do
        rows[#rows + 1] = string.format("{%.1f,%.1f,%q%s}", e.x, e.y, e.name, e.faction and (",%q"):format(e.faction) or "")
        nEntrances = nEntrances + 1
    end
    w(string.format("    [%d] = {%s},", map, table.concat(rows, ",")))
end
w("} }")
w("")
local f = assert(io.open(out, "wb"))
f:write(table.concat(o, "\n"))
f:close()
local nq = 0
for _ in pairs(used) do nq = nq + 1 end
print(string.format("gen_quest_starts: %d quests, %d pins on %d maps, %d entrances -> %s", nq, total, #maps, nEntrances, out))
