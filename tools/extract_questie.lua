-- tools/extract_questie.lua
-- QuestieDB's Forever items, NPCs and objects (github.com/Questie/QuestieDB,
-- no license stated) with its Forever corrections applied, as the TSV files
-- tools/gen_recipes.py reads: questie_items.tsv, questie_npcs.tsv,
-- questie_objects.tsv. Its files run in an empty sandbox (no io, no os).
--   lua tools/extract_questie.lua <dir>/questiedb <dir>
local root, out = arg[1], arg[2]

local function stub()
  return setmetatable({}, { __index = function(t, k)
                              if type(k) == "number" then return nil end
                              if type(k) == "string" and k:match("^[%u%d_]+$") then return k end
                              local s = stub(); rawset(t, k, s); return s end,
                            __call = function() return stub() end })
end
local modules = {}
local function sandbox()
  local QuestieDB = { itemKeys = {}, npcKeys = {}, objectKeys = {} }
  modules.QuestieDB = QuestieDB
  local loader = {
    ImportModule = function(_, name) modules[name] = modules[name] or stub(); return modules[name] end,
    CreateModule = function(_, name) modules[name] = {}; return modules[name] end,
  }
  return { QuestieLoader = loader, pairs = pairs, ipairs = ipairs, setmetatable = setmetatable,
           tostring = tostring, tonumber = tonumber, type = type, table = { insert = table.insert } }
end
local env = sandbox()
local QuestieDB = modules.QuestieDB

local function run(path)
  local f = assert(loadfile(root .. "/" .. path, "t", env))
  f()
end
local function data(field)
  return assert(load(QuestieDB[field], field, "t", {}))()
end

run("data/Forever/foreverItemDB.lua")
run("data/Forever/foreverNpcDB.lua")
run("data/Forever/foreverObjectDB.lua")
local items, npcs, objects = data("itemData"), data("npcData"), data("objectData")

-- corrections address fields by name: key tables give back the name itself
local fieldIndex = { item = {}, npc = {}, object = {} }
for name, i in pairs(QuestieDB.itemKeys) do fieldIndex.item[name] = i end
for name, i in pairs(QuestieDB.npcKeys) do fieldIndex.npc[name] = i end
for name, i in pairs(QuestieDB.objectKeys) do fieldIndex.object[name] = i end
local named = setmetatable({}, { __index = function(_, k) return k end })
QuestieDB.itemKeys, QuestieDB.npcKeys, QuestieDB.objectKeys = named, named, named
QuestieDB.itemClasses, QuestieDB.npcFlags, QuestieDB.waypointPresets = named, named, named

local function apply(db, kind, corrections, stats)
  local idx = fieldIndex[kind]
  for id, fields in pairs(corrections) do
    local row = db[id]
    if not row then row = {}; db[id] = row; stats.new = stats.new + 1 end
    for key, value in pairs(fields) do
      local base, op = tostring(key):match("^(.-)_(%a+)$")
      if not (op == "add" or op == "remove") then base, op = key, "set" end
      local i = idx[base]
      if i then
        if op == "set" then row[i] = value
        elseif type(value) == "table" then
          local list = row[i] or {}
          if op == "add" then
            local have = {} for _, v in ipairs(list) do have[v] = true end
            for _, v in ipairs(value) do if not have[v] then list[#list + 1] = v end end
          else
            local drop = {} for _, v in ipairs(value) do drop[v] = true end
            local kept = {} for _, v in ipairs(list) do if not drop[v] then kept[#kept + 1] = v end end
            list = kept
          end
          row[i] = list
        end
        stats.fields = stats.fields + 1
      else
        stats.unknown[tostring(key)] = true
      end
    end
  end
end

local layers = {
  { "item", items, "src/corrections/Forever/generated/foreverBaseItem.lua", "ForeverBaseItem" },
  { "item", items, "src/corrections/Forever/foreverItemFixes.lua", "ForeverItemFixes" },
  { "item", items, "src/corrections/Forever/traces/foreverItemTraces.lua", "ForeverItemTraces" },
  { "npc", npcs, "src/corrections/Forever/generated/foreverBaseNpc.lua", "ForeverBaseNpc" },
  { "npc", npcs, "src/corrections/Forever/foreverNPCFixes.lua", "ForeverNpcFixes" },
}
for _, l in ipairs(layers) do
  local ok, err = pcall(run, l[3])
  local mod = modules[l[4]]
  if ok and mod and mod.Load then
    local ok2, corr = pcall(mod.Load, mod, named, stub())
    if ok2 and type(corr) == "table" then
      local stats = { new = 0, fields = 0, unknown = {} }
      apply(l[2], l[1], corr, stats)
      local unk = {} for k in pairs(stats.unknown) do unk[#unk + 1] = k end
      io.stderr:write(("%s: %d fields, %d new rows, unknown keys: %s\n"):format(l[3], stats.fields, stats.new, table.concat(unk, ",")))
    else io.stderr:write(l[3] .. ": Load failed: " .. tostring(corr) .. "\n") end
  else io.stderr:write(l[3] .. ": " .. tostring(err) .. "\n") end
end

local function list(v)
  if type(v) ~= "table" then return v ~= nil and tostring(v) or "" end
  local t = {} for _, x in ipairs(v) do t[#t + 1] = tostring(x) end
  return table.concat(t, ",")
end
local function clean(s) return (tostring(s or ""):gsub("[\t\n]", " ")) end

local I = fieldIndex.item
local f = assert(io.open(out .. "/questie_items.tsv", "w"))
f:write("id\tname\tnpcDrops\tobjectDrops\titemDrops\tvendors\tquestRewards\tstartQuest\n")
for id, r in pairs(items) do
  f:write(table.concat({ id, clean(r[I.name]), list(r[I.npcDrops]), list(r[I.objectDrops]), list(r[I.itemDrops]),
    list(r[I.vendors]), list(r[I.questRewards]), list(r[I.startQuest]) }, "\t"), "\n")
end
f:close()
local N = fieldIndex.npc
f = assert(io.open(out .. "/questie_npcs.tsv", "w"))
f:write("id\tname\tsubName\tzoneID\tfriendly\tminLevel\tmaxLevel\n")
for id, r in pairs(npcs) do
  f:write(table.concat({ id, clean(r[N.name]), clean(r[N.subName]), list(r[N.zoneID]), clean(r[N.friendlyToFaction]),
    list(r[N.minLevel]), list(r[N.maxLevel]) }, "\t"), "\n")
end
f:close()
local O = fieldIndex.object
f = assert(io.open(out .. "/questie_objects.tsv", "w"))
f:write("id\tname\tzoneID\n")
for id, r in pairs(objects) do f:write(table.concat({ id, clean(r[O.name]), list(r[O.zoneID]) }, "\t"), "\n") end
f:close()
