-- tools/gen_quest_starts.lua
-- Writes src/Data/QuestStarts.lua: where each of Forever's quests can be
-- picked up (its quest givers' spawn points, by the game's map IDs), with
-- what the world map needs to tell whether you can take it (levels, races,
-- classes, quests before it and instead of it), and the dungeon entrances.
-- Reads QuestieDB's Forever data with its corrections applied in
-- QuestieDB's order (inherited classic fixes, the generated Forever base,
-- the Forever fixes), from the folder tools/fetch_quest_starts.sh fills.
-- Also writes src/Data/MapPlaces.lua: the town services (from NPC flags
-- and titles), mailboxes, rares and treasure chests, for the map's pins.
-- Every downloaded file runs in a sandbox without io, os or require.
--   lua tools/gen_quest_starts.lua <dir> src/Data/QuestStarts.lua src/Data/MapPlaces.lua

local dir, out, placesOut = arg[1], arg[2], arg[3]
assert(dir and out and placesOut, "usage: lua tools/gen_quest_starts.lua <dir> <quests.lua> <places.lua>")

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
for _, f in ipairs({ "constants", "zones", "expansions", "factions", "professions", "quests", "items" }) do
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
QuestieDB.itemClasses = constants.itemClasses or {}
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
local items = data("data/Forever/foreverItemDB.lua", "itemData")

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
local QK, NK, OK, IK = QuestieDB.questKeys, QuestieDB.npcKeys, QuestieDB.objectKeys, QuestieDB.itemKeys
aliases(QuestieDB.questKeys)
aliases(QuestieDB.npcKeys)
aliases(QuestieDB.objectKeys)
aliases(QuestieDB.itemKeys)
GROUPED[quests] = { [QuestieDB.questKeys.startedBy] = true, [QuestieDB.questKeys.finishedBy] = true }
GROUPED[npcs] = { [QuestieDB.npcKeys.spawns] = true, [QuestieDB.npcKeys.waypoints] = true }
GROUPED[objects] = { [QuestieDB.objectKeys.spawns] = true, [QuestieDB.objectKeys.waypoints] = true }
local C = "src/corrections/Forever/"
correct(quests, { C .. "legacy/classicQuestFixes.lua", C .. "generated/foreverBaseQuest.lua", C .. "foreverQuestFixes.lua" })
correct(npcs, { C .. "legacy/classicNPCFixes.lua", C .. "generated/foreverBaseNpc.lua", C .. "foreverNPCFixes.lua" })
correct(objects, { C .. "legacy/classicObjectFixes.lua", C .. "generated/foreverBaseObject.lua", C .. "foreverObjectFixes.lua" })
correct(items, { C .. "legacy/classicItemFixes.lua", C .. "generated/foreverBaseItem.lua", C .. "foreverItemFixes.lua" })

-- quests of events: the map shows them only while their event is on.
-- Holidays by their quest sorts (the calendar says when they're on); the
-- one-off server events Forever isn't running now (the Ahn'Qiraj War
-- Effort, the Scourge Invasion: their NPCs aren't there, and nothing in the
-- game says when they are) by their sorts, and the War Effort's hand-ins
-- filed elsewhere by name ("The Horde Needs Copper Bars!", "… Needs Your
-- Help!", commendation signets, signets for war supplies: Warlord
-- Gorchuk's quest had no Gorchuk; found in game)
local EVENT_SORT = {
    [-365] = "warEffort", [-368] = "invasion",
    [-366] = "lunarFestival", [-364] = "darkmoonFaire", [-369] = "midsummer", [-404] = "winterVeil",
    [-402] = "harvestFestival", [-378] = "childrensWeek", [-376] = "loveIsInTheAir", [-375] = "pilgrimsBounty",
    [-374] = "noblegarden", [-370] = "brewfest", [-41] = "dayOfTheDead", [-21] = "hallowsEnd",
    [-22] = "seasonal", -- a holiday's, which one the sort doesn't say
}
local eventOf = {} -- quest -> event key
local nEvent = 0
for id, q in pairs(quests) do
    local name = q[QK.name]
    local e = EVENT_SORT[q[QK.zoneOrSort]]
    if not e and type(name) == "string" and ((id >= 8490 and id <= 8800 and name:find("^The %a+ Needs ") ~= nil)
        or name:find("Commendation Signets?$") ~= nil or name:find("Signets for War Supplies$") ~= nil) then
        e = "warEffort"
    end
    if e then eventOf[id] = e; nEvent = nEvent + 1 end
end
print(string.format("gen_quest_starts: %d quests of events", nEvent))

-- area IDs to the game's map IDs (the override first)
run("support/Forever/Zones/areaIdToUiMapId.lua")
local function mapTable(s) return s and assert(load(s, "@areaIdToUiMapId", "t", {}))() or {} end
local areaToMap = mapTable(ZoneDB.private.areaIdToUiMapId)
for k, v in pairs(mapTable(ZoneDB.private.areaIdToUiMapIdOverride)) do areaToMap[k] = v end

-- each giver's spawn points as { map = { {x, y}, ... } } (at most 3 per map)
local function spawnsOf(row, key, cap)
    cap = cap or 3
    local out = {}
    for area, coords in pairs(row and row[key] or {}) do
        local map = areaToMap[area]
        if map and map > 0 and type(coords) == "table" then
            local list = out[map] or {}
            out[map] = list
            for _, c in ipairs(coords) do
                if #list < cap and type(c) == "table" and c[1] and c[1] >= 0 then list[#list + 1] = { c[1], c[2] } end
            end
        end
    end
    return out
end

local pins = {}      -- map -> "x,y,giver" -> { x, y, giver, quests }
local used = {}      -- quest IDs with a pin
local giverNames = {} -- giver (an NPC's ID, an object's as a negative) -> name
local function pin(map, x, y, qid, giver, name)
    local m = pins[map] or {}
    pins[map] = m
    local key = string.format("%.1f,%.1f,%d", x, y, giver)
    local p = m[key] or { x = x, y = y, giver = giver, quests = {} }
    m[key] = p
    p.quests[#p.quests + 1] = qid
    used[qid] = true
    if type(name) == "string" then giverNames[giver] = name end
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
                for _, c in ipairs(list) do pin(map, c[1], c[2], qid, npc, npcs[npc][NK.name]) end
            end
        end
        for _, obj in ipairs(starts[2]) do
            for map, list in pairs(spawnsOf(objects[obj], OK.spawns)) do
                for _, c in ipairs(list) do pin(map, c[1], c[2], qid, -obj, objects[obj][OK.name]) end
            end
        end
    end
end

-- the routes of quest givers who walk (Warcaller Gorlach round Orgrimmar:
-- his pin is where it starts, he's rarely there; found in game), per map,
-- thinned to a point every 0.6% of the map (the dotted line the map draws
-- while you hover his pin needs no more)
local routes = {} -- npc -> map -> { { x, y, x, y, ... }, ... }
local nRoutes = 0
local function thin(path)
    local out, lx, ly = {}, nil, nil
    for i, c in ipairs(path) do
        if type(c) == "table" and c[1] and c[1] >= 0 then
            local far = not lx or (c[1] - lx) ^ 2 + (c[2] - ly) ^ 2 >= 0.36
            if far or i == #path then
                out[#out + 1] = c[1]; out[#out + 1] = c[2]
                lx, ly = c[1], c[2]
            end
        end
    end
    return out
end
for npc in pairs(giverNames) do
    local n = npc > 0 and npcs[npc]
    for area, paths in pairs(n and type(n[NK.waypoints]) == "table" and n[NK.waypoints] or {}) do
        local map = areaToMap[area]
        if map and map > 0 and type(paths) == "table" then
            for _, path in ipairs(paths) do
                local flat = type(path) == "table" and thin(path) or {}
                -- one who only shuffles about (a box under 3% of the map) stays a pin
                local x0, x1, y0, y1 = 100, 0, 100, 0
                for i = 1, #flat, 2 do
                    x0, x1 = math.min(x0, flat[i]), math.max(x1, flat[i])
                    y0, y1 = math.min(y0, flat[i + 1]), math.max(y1, flat[i + 1])
                end
                if #flat >= 4 and math.max(x1 - x0, y1 - y0) >= 3 then
                    routes[npc] = routes[npc] or {}
                    routes[npc][map] = routes[npc][map] or {}
                    table.insert(routes[npc][map], flat)
                    nRoutes = nRoutes + 1
                end
            end
        end
    end
end

-- quests started by an item: a pin where each mob (or object) that drops
-- it lives, at most 8 of its spawn points per map. An item that drops from
-- more than 10 kinds (the Pendant of Myzrael: 246, the OOX beacons: 50 to
-- 80) is a random world drop: pins everywhere would say nothing, so none.
local MAX_DROP_SOURCES = 10
local itemStarts = {} -- quest -> { item, ... }
for qid, q in pairs(quests) do
    local starts = q[QK.startedBy]
    for _, item in ipairs(type(starts) == "table" and type(starts[3]) == "table" and starts[3] or {}) do
        itemStarts[qid] = itemStarts[qid] or {}
        table.insert(itemStarts[qid], item)
    end
end
for id, it in pairs(items) do
    local qid = it[IK.startQuest]
    if type(qid) == "number" and quests[qid] then
        itemStarts[qid] = itemStarts[qid] or {}
        local has = false
        for _, x in ipairs(itemStarts[qid]) do if x == id then has = true end end
        if not has then table.insert(itemStarts[qid], id) end
    end
end
local drops = {}      -- map -> "x,y,source,item" -> { x, y, source, item, quests }
local itemNames = {}  -- item -> name
local nDrops = 0
local function dropPin(map, x, y, source, item, qid)
    local m = drops[map] or {}
    drops[map] = m
    local key = string.format("%.1f,%.1f,%d,%d", x, y, source, item)
    local p = m[key]
    if not p then p = { x = x, y = y, source = source, item = item, quests = {} }; m[key] = p; nDrops = nDrops + 1 end
    for _, q in ipairs(p.quests) do if q == qid then return end end
    p.quests[#p.quests + 1] = qid
    used[qid] = true
end
local dropIDs = {}
for qid in pairs(itemStarts) do dropIDs[#dropIDs + 1] = qid end
table.sort(dropIDs)
for _, qid in ipairs(dropIDs) do
    for _, item in ipairs(itemStarts[qid]) do
        local it = items[item]
        local sources = it and (#(type(it[IK.npcDrops]) == "table" and it[IK.npcDrops] or {})
            + #(type(it[IK.objectDrops]) == "table" and it[IK.objectDrops] or {})) or 0
        if it and sources <= MAX_DROP_SOURCES then
            itemNames[item] = it[IK.name]
            for _, npc in ipairs(type(it[IK.npcDrops]) == "table" and it[IK.npcDrops] or {}) do
                local n = npcs[npc]
                for map, list in pairs(spawnsOf(n, NK.spawns, 8)) do
                    for _, c in ipairs(list) do dropPin(map, c[1], c[2], npc, item, qid) end
                    if type(n[NK.name]) == "string" then giverNames[npc] = n[NK.name] end
                end
            end
            for _, obj in ipairs(type(it[IK.objectDrops]) == "table" and it[IK.objectDrops] or {}) do
                local o = objects[obj]
                for map, list in pairs(spawnsOf(o, OK.spawns, 8)) do
                    for _, c in ipairs(list) do dropPin(map, c[1], c[2], -obj, item, qid) end
                    if type(o[OK.name]) == "string" then giverNames[-obj] = o[OK.name] end
                end
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
-- the list also holds later expansions' instances, Season of Discovery's
-- (not in Forever) and places that aren't instances (brawlers' pubs, the
-- tram, the PvP halls): left out. Its "Hyjal Summit" is the Caverns of
-- Time's; Forever's is in FOREVER below.
local LATER = { ["Blackrock Caverns"] = true, ["Blackwing Descent"] = true, ["Dragon Soul"] = true, ["End Time"] = true,
                ["Firelands"] = true, ["Hour of Twilight"] = true, ["Well of Eternity"] = true, ["Molten Front"] = true,
                ["Hyjal Summit"] = true, ["Old Hillsbrad Foothills"] = true, ["The Black Morass"] = true,
                ["The Culling of Stratholme"] = true, ["Scarlet Halls"] = true, ["Scarlet Enclave"] = true,
                ["Bizmo's Brawlpub"] = true, ["Brawl'gar Arena"] = true, ["Darkmoon Faire Island"] = true,
                ["Karazhan"] = true, ["Deeprun Tram"] = true, ["Champions' Hall"] = true, ["Hall of Legends"] = true,
                ["The Tainted Scar"] = true, ["Demon Fall Canyon"] = true, ["Karazhan Crypts"] = true }
local RAIDS = { ["Molten Core"] = true, ["Onyxia's Lair"] = true, ["Blackwing Lair"] = true, ["Zul'Gurub"] = true,
                ["Ruins of Ahn'Qiraj"] = true, ["Temple of Ahn'Qiraj"] = true, ["Naxxramas"] = true }
local BATTLEGROUNDS = { ["Alterac Valley"] = true, ["Arathi Basin"] = true, ["Warsong Gulch"] = true }
local seen = {}
for _, side in ipairs({ { horde, "H" }, { alliance, "A" } }) do
    for area, d in pairs(side[1]) do
        if type(d) == "table" and type(d[1]) == "string" and type(d[4]) == "table" and not LATER[d[1]] then
            for _, loc in ipairs(d[4]) do
                local map = type(loc) == "table" and areaToMap[loc[1]]
                if map and map > 0 and type(loc[2]) == "number" then
                    local key = string.format("%d,%.1f,%.1f,%s", map, loc[2], loc[3], d[1])
                    if seen[key] then seen[key].faction = nil
                    else
                        local kind = RAIDS[d[1]] and "raid" or BATTLEGROUNDS[d[1]] and "battleground" or "dungeon"
                        local e = { x = loc[2], y = loc[3], name = d[1], area = area, faction = side[2], kind = kind }
                        seen[key] = e
                        entrances[map] = entrances[map] or {}
                        table.insert(entrances[map], e)
                    end
                end
            end
        end
    end
end

-- Forever's own entrances QuestieDB doesn't have. Hyjal Summit: its door
-- isn't known yet (no one has stood at it); the middle of the Summit of
-- Eternity, the area it's in (WorldMapOverlay 4995 on Mount Hyjal's art),
-- marked approximate
local FOREVER = {
    { map = 2482, x = 80.5, y = 39.8, name = "Hyjal Summit", kind = "raid", approx = true },
}
for _, e in ipairs(FOREVER) do
    entrances[e.map] = entrances[e.map] or {}
    table.insert(entrances[e.map], e)
end

-- the map's other pins: services, mailboxes, rares, treasure chests
local NPC_FLAG = { VENDOR = 4, TRAINER = 16, SPIRIT = 32, INN = 128, BANK = 256, GUILD = 512, TABARD = 1024,
                   BATTLEMASTER = 2048, AUCTION = 4096, STABLE = 8192, REPAIR = 16384 }
local function has(flags, bit) return flags // bit % 2 == 1 end
local CLASSES = { "warrior", "paladin", "hunter", "rogue", "priest", "shaman", "mage", "warlock", "druid" }
-- a profession trainer's profession from its title ("Expert Leatherworker")
local PROFESSIONS = {
    { "alchem", "alchemy" }, { "blacksmith", "blacksmithing" }, { "armorsmith", "blacksmithing" },
    { "weaponsmith", "blacksmithing" }, { "armor crafter", "blacksmithing" }, { "weapon crafter", "blacksmithing" },
    { "enchant", "enchanting" }, { "engineer", "engineering" }, { "herbalis", "herbalism" },
    { "leather", "leatherworking" }, { "mining", "mining" }, { "miner", "mining" }, { "skinn", "skinning" },
    { "tailor", "tailoring" }, { "cook", "cooking" }, { "chef", "cooking" }, { "butcher", "cooking" },
    { "first aid", "firstAid" }, { "physician", "firstAid" }, { "medic", "firstAid" }, { "trauma surgeon", "firstAid" }, { "fish", "fishing" },
}
local FOOD = { "baker", "butcher", "meat", "fruit", "mushroom", "beverage", "bread", "cheese", "wine", "barkeep" }
local function trainerKind(title)
    local t = (title or ""):lower()
    for _, p in ipairs(PROFESSIONS) do if t:find(p[1], 1, true) then return "trainer:" .. p[2] end end
    if t:find("pet trainer", 1, true) then return "trainer:pet" end
    if t:find("weapon master", 1, true) then return "trainer:weapon" end
    if t:find("riding", 1, true) or t:find("pilot", 1, true) then return "trainer:riding" end
    if t:find("portal trainer", 1, true) then return "class:MAGE" end
    for _, c in ipairs(CLASSES) do if t:find(c, 1, true) then return "class:" .. c:upper() end end
    return "trainer:other"
end
local function vendorKind(title)
    local t = (title or ""):lower()
    for _, w in ipairs(FOOD) do if t:find(w, 1, true) then return "food" end end
    if t:find("general goods", 1, true) or t:find("general supplies", 1, true) then return "goods" end
    return "vendor"
end
-- an NPC's services, in the order the map picks the one it shows
local function servicesOf(n)
    local flags, title = n[NK.npcFlags] or 0, n[NK.subName]
    local k = {}
    if n[NK.name] == "Spirit Healer" or has(flags, NPC_FLAG.SPIRIT) then k[#k + 1] = "spirit" end
    -- the innkeeper flag also sits on mount vendors and a kennel master
    if has(flags, NPC_FLAG.INN) and (title == nil or title == "Innkeeper") then k[#k + 1] = "inn" end
    if has(flags, NPC_FLAG.BANK) then k[#k + 1] = "bank" end
    if has(flags, NPC_FLAG.AUCTION) then k[#k + 1] = "auction" end
    if has(flags, NPC_FLAG.TRAINER) then k[#k + 1] = trainerKind(title) end
    if has(flags, NPC_FLAG.BATTLEMASTER) then k[#k + 1] = "battlemaster" end
    if has(flags, NPC_FLAG.GUILD) then k[#k + 1] = "guild" end
    if has(flags, NPC_FLAG.TABARD) then k[#k + 1] = "tabard" end
    if has(flags, NPC_FLAG.STABLE) then k[#k + 1] = "stable" end
    if has(flags, NPC_FLAG.REPAIR) then k[#k + 1] = "repair" end
    if has(flags, NPC_FLAG.VENDOR) then k[#k + 1] = vendorKind(title) end
    return k
end
-- the random world chests (quest and dungeon chests are left out)
local TREASURES = { ["Battered Chest"] = true, ["Large Battered Chest"] = true, ["Tattered Chest"] = true,
                    ["Solid Chest"] = true, ["Large Solid Chest"] = true, ["Large Iron Bound Chest"] = true,
                    ["Large Mithril Bound Chest"] = true, ["Large Darkwood Chest"] = true }

local placeNpcs, placeObjects = {}, {} -- id -> row; name -> index
local services, rares, mailboxes, treasures = {}, {}, {}, {}
local function add(t, map, ...)
    t[map] = t[map] or {}
    local row = t[map]
    for _, v in ipairs({ ... }) do row[#row + 1] = v end
end
local function spawnsAll(row, key, cap)
    local out = {}
    for area, coords in pairs(row and row[key] or {}) do
        local map = areaToMap[area]
        if map and map > 0 and type(coords) == "table" then
            local list = out[map] or {}
            out[map] = list
            for _, c in ipairs(coords) do
                if #list < cap and type(c) == "table" and c[1] and c[1] >= 0 then list[#list + 1] = { c[1], c[2] } end
            end
        end
    end
    return out
end
local npcIDs = {}
for id in pairs(npcs) do npcIDs[#npcIDs + 1] = id end
table.sort(npcIDs)
local nServices, nRares = 0, 0
for _, id in ipairs(npcIDs) do
    local n = npcs[id]
    local kinds = servicesOf(n)
    local rank = n[NK.rank]
    local rare = (rank == 4 and "rare") or (rank == 2 and "rareElite") or nil
    if #kinds > 0 or rare then
        local spawns = spawnsAll(n, NK.spawns, rare and 6 or 2)
        if next(spawns) then
            placeNpcs[id] = { n[NK.name], n[NK.subName], n[NK.friendlyToFaction], #kinds > 0 and table.concat(kinds, ",") or nil,
                              rare, n[NK.minLevel], n[NK.maxLevel] }
            for map, list in pairs(spawns) do
                for _, c in ipairs(list) do
                    if #kinds > 0 then add(services, map, c[1], c[2], id); nServices = nServices + 1 end
                    if rare then add(rares, map, c[1], c[2], id); nRares = nRares + 1 end
                end
            end
        end
    end
end
local objIDs = {}
for id in pairs(objects) do objIDs[#objIDs + 1] = id end
table.sort(objIDs)
local nMail, nChests = 0, 0
for _, id in ipairs(objIDs) do
    local o = objects[id]
    local name = o[OK.name]
    if name == "Mailbox" then
        for map, list in pairs(spawnsAll(o, OK.spawns, 50)) do
            for _, c in ipairs(list) do
                -- one per place: the data repeats a mailbox a step apart
                local row, near = mailboxes[map] or {}, false
                for i = 1, #row, 2 do
                    if math.abs(row[i] - c[1]) < 1.5 and math.abs(row[i + 1] - c[2]) < 1.5 then near = true break end
                end
                if not near then add(mailboxes, map, c[1], c[2]); nMail = nMail + 1 end
            end
        end
    elseif TREASURES[name] then
        for map, list in pairs(spawnsAll(o, OK.spawns, 200)) do
            for _, c in ipairs(list) do add(treasures, map, c[1], c[2], name); nChests = nChests + 1 end
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
w("--                  exclusiveTo, nextInChain, specialFlags (1 repeatable, 2 needs an event), parentQuest,")
w("--                  breadcrumbFor, requiredSkill {skillLine, value}, minRep {faction, value}, maxRep {faction, value},")
w("--                  event (shown only while it's on: \"darkmoonFaire\", \"lunarFestival\", … a holiday; \"warEffort\",")
w("--                  \"invasion\" one-off server events; \"seasonal\" some holiday) }")
w("--   maps[uiMapID] = { { x, y, giver, questID, ... }, ... }   (x, y in percent; giver an NPC's ID, an object's negative)")
w("--   drops[uiMapID] = { { x, y, source, itemID, questID, ... }, ... }   (quests started by an item: where a mob")
w("--                    (source: an NPC's ID, an object's negative) that drops it lives)")
w("--   items[itemID] = name; givers[giver or source] = name")
w("--   entrances[uiMapID] = { { x, y, name, kind (\"dungeon\", \"raid\", \"battleground\"), faction (\"H\", \"A\" or nil), approx (true: the spot isn't known, only its area) }, ... }")
w("--   routes[npcID] = { [uiMapID] = { { x, y, x, y, ... }, ... } }   (a quest giver who walks: his paths)")
w("")
w("local _, ns = ...")
w("")
w("ns.QuestStarts = { quests = {")
for _, qid in ipairs(ids) do
    if used[qid] then
        local q = quests[qid]
        w(string.format("    [%d] = { %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s%s },", qid,
            str(q[QK.name]), num(q[QK.requiredLevel]), num(q[QK.questLevel]), num(q[QK.requiredRaces]), num(q[QK.requiredClasses]),
            list(q[QK.preQuestGroup]), list(q[QK.preQuestSingle]), list(q[QK.exclusiveTo]), num(q[QK.nextQuestInChain]),
            num(q[QK.specialFlags]), num(q[QK.parentQuest]), num(q[QK.breadcrumbForQuestId]),
            list(q[QK.requiredSkill]), list(q[QK.requiredMinRep]), list(q[QK.requiredMaxRep]),
            eventOf[qid] and (", %q"):format(eventOf[qid]) or ""))
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
        rows[#rows + 1] = string.format("{%.1f,%.1f,%d,%s}", p.x, p.y, p.giver, table.concat(p.quests, ","))
        total = total + 1
    end
    w(string.format("    [%d] = {%s},", map, table.concat(rows, ",")))
end
w("}, drops = {")
local dmaps = {}
for map in pairs(drops) do dmaps[#dmaps + 1] = map end
table.sort(dmaps)
for _, map in ipairs(dmaps) do
    local keys = {}
    for k in pairs(drops[map]) do keys[#keys + 1] = k end
    table.sort(keys)
    local rows = {}
    for _, k in ipairs(keys) do
        local p = drops[map][k]
        rows[#rows + 1] = string.format("{%.1f,%.1f,%d,%d,%s}", p.x, p.y, p.source, p.item, table.concat(p.quests, ","))
    end
    w(string.format("    [%d] = {%s},", map, table.concat(rows, ",")))
end
w("}, items = {")
local itemIDs = {}
for i in pairs(itemNames) do itemIDs[#itemIDs + 1] = i end
table.sort(itemIDs)
for _, i in ipairs(itemIDs) do if type(itemNames[i]) == "string" then w(string.format("    [%d] = %q,", i, itemNames[i])) end end
w("}, givers = {")
local giverIDs = {}
for g in pairs(giverNames) do giverIDs[#giverIDs + 1] = g end
table.sort(giverIDs)
for _, g in ipairs(giverIDs) do w(string.format("    [%d] = %q,", g, giverNames[g])) end
w("}, entrances = {")
local emaps = {}
for map in pairs(entrances) do emaps[#emaps + 1] = map end
table.sort(emaps)
local nEntrances = 0
for _, map in ipairs(emaps) do
    table.sort(entrances[map], function(a, b) return a.name < b.name end)
    local rows = {}
    for _, e in ipairs(entrances[map]) do
        rows[#rows + 1] = string.format("{%.1f,%.1f,%q,%q%s%s}", e.x, e.y, e.name, e.kind,
            (e.faction or e.approx) and (",%s"):format(e.faction and ("%q"):format(e.faction) or "nil") or "",
            e.approx and ",true" or "")
        nEntrances = nEntrances + 1
    end
    w(string.format("    [%d] = {%s},", map, table.concat(rows, ",")))
end
w("}, routes = {")
local rnpcs = {}
for npc in pairs(routes) do rnpcs[#rnpcs + 1] = npc end
table.sort(rnpcs)
for _, npc in ipairs(rnpcs) do
    local rmaps = {}
    for map in pairs(routes[npc]) do rmaps[#rmaps + 1] = map end
    table.sort(rmaps)
    local parts = {}
    for _, map in ipairs(rmaps) do
        local paths = {}
        for _, flat in ipairs(routes[npc][map]) do
            local nums = {}
            for i, v in ipairs(flat) do nums[i] = string.format("%.1f", v) end
            paths[#paths + 1] = "{" .. table.concat(nums, ",") .. "}"
        end
        parts[#parts + 1] = string.format("[%d]={%s}", map, table.concat(paths, ","))
    end
    w(string.format("    [%d] = {%s},", npc, table.concat(parts, ",")))
end
w("} }")
w("")
local f = assert(io.open(out, "wb"))
f:write(table.concat(o, "\n"))
f:close()

-- MapPlaces.lua
o = {}
w("-- Data/MapPlaces.lua (generated by tools/gen_quest_starts.lua: do not edit)")
w("-- The world map's other pins: town services, mailboxes, rares, treasure chests.")
w("--   QuestieDB Forever data with its corrections, commit " .. (sources.questiedb or "?") .. " (github.com/Questie/QuestieDB, no license stated)")
w("--   fetched " .. (sources.fetched or "?") .. "; rebuild: sh tools/update_quest_starts.sh")
w("--   npcs[id] = { name, title, friendly (\"A\", \"H\", \"AH\" or nil), services (\"inn,repair,...\" in the")
w("--               order the map picks the one it shows), rank (\"rare\" or \"rareElite\"), minLevel, maxLevel }")
w("--     services: spirit, inn, bank, auction, class:WARRIOR, trainer:alchemy (a profession, or :weapon,")
w("--               :riding, :pet, :other), battlemaster,")
w("--               guild, tabard, stable, repair, food, goods, vendor")
w("--   services[uiMapID], rares[uiMapID] = { x, y, npcID, x, y, npcID, ... }   (x, y in percent)")
w("--   mailboxes[uiMapID] = { x, y, x, y, ... }; treasures[uiMapID] = { x, y, name, ... }")
w("")
w("local _, ns = ...")
w("")
w("ns.MapPlaces = { npcs = {")
for _, id in ipairs(npcIDs) do
    local r = placeNpcs[id]
    if r then w(string.format("    [%d] = { %s, %s, %s, %s, %s, %s, %s },", id, str(r[1]), str(r[2]), str(r[3]), str(r[4]), str(r[5]), num(r[6]), num(r[7]))) end
end
local function flat(name, t, perRow)
    w("}, " .. name .. " = {")
    local ms = {}
    for map in pairs(t) do ms[#ms + 1] = map end
    table.sort(ms)
    for _, map in ipairs(ms) do
        local cells = {}
        local row = t[map]
        for i = 1, #row, perRow do
            for j = 0, perRow - 1 do
                local v = row[i + j]
                cells[#cells + 1] = j < 2 and string.format("%.1f", v) or (type(v) == "string" and string.format("%q", v) or tostring(v))
            end
        end
        w(string.format("    [%d] = {%s},", map, table.concat(cells, ",")))
    end
end
flat("services", services, 3)
flat("rares", rares, 3)
flat("mailboxes", mailboxes, 2)
flat("treasures", treasures, 3)
w("} }")
w("")
f = assert(io.open(placesOut, "wb"))
f:write(table.concat(o, "\n"))
f:close()
local nq = 0
for _ in pairs(used) do nq = nq + 1 end
print(string.format("gen_quest_starts: %d quests, %d pins on %d maps, %d entrances, %d drop pins, %d routes of %d givers -> %s", nq, total, #maps, nEntrances, nDrops, nRoutes, #rnpcs, out))
print(string.format("gen_quest_starts: %d service spawns, %d rare spawns, %d mailboxes, %d chest spawns -> %s", nServices, nRares, nMail, nChests, placesOut))
