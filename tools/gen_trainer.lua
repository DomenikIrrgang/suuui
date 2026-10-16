-- tools/gen_trainer.lua
-- Generates Data/Trainer/<CLASS>.lua from each class's trainer list (/suu
-- probe class, at that class's trainer): every spell the trainer teaches with
-- its required level, cost in copper, school (the trainer's skill line), icon
-- and description. No ranks: Forever's trainers give none, and a spell's
-- first rank is often known from level 1 (Holy Light), so SuuUI's Spellbook
-- works ranks out in game from the ranks you know (by level).
-- Also every spell ID the client has for each of those names (the ID scan,
-- /suu probe spells scan: SuuUIProbe.spellScan.byName, and the Forever range
-- scan's rows), as
-- ns.TrainerSpellIDs[name]: the Spellbook picks a rank's own ID in game by
-- the level the game says it is learned at, for the game's spell tooltip.
-- A class whose data file exists is merged with it: a spell you already
-- know comes back from the trainer with level 0 (the probe asks the game
-- for its level from its spell ID; only where that failed), so its levels,
-- rank by rank from the lowest, come from the file (right only when the file
-- has every rank: it says so when it doesn't); prices
-- stay the file's base ones (a trainer gives a character a reputation
-- discount), and a new spell's price is taken back up by that discount.
--   lua tools/gen_trainer.lua "<WTF>/SavedVariables/SuuUI.lua" [CLASS]   (from src/)

local env = {}
assert(loadfile(arg[1], "t", env))()
local all = assert(env.SuuUIProbe and env.SuuUIProbe.classData, "no class data in the saved variables")
local byName = env.SuuUIProbe.spellScan and env.SuuUIProbe.spellScan.byName or {}
-- and Forever's own range (/suu probe spells scan forever: { id, name } rows)
local forever = env.SuuUIProbe.spellScanForever and env.SuuUIProbe.spellScanForever.rows or {}
for _, row in ipairs(forever) do
    local id, name = row[1], row[2]
    if type(id) == "number" and type(name) == "string" then
        byName[name] = byName[name] or {}
        local have = false
        for _, r in pairs(byName[name]) do if (type(r) == "table" and r[1] or r) == id then have = true end end
        if not have then table.insert(byName[name], { id }) end
    end
end

local function q(s)
    return string.format("%q", tostring(s or "")):gsub("\\\n", "\\n")
end

local classes = {}
for class, d in pairs(all) do
    if not arg[2] or arg[2]:upper() == class then classes[#classes + 1] = class end
end
table.sort(classes)

-- The class's data file as it is: { name, level, cost, school, icon, text } list.
local function existing(class)
    local chunk = loadfile(("Data/Trainer/%s.lua"):format(class), "t", {
        UnitClass = function() return class, class end,
    })
    if not chunk then return {} end
    local ns = {}
    chunk(nil, ns)
    return ns.TrainerSpells or {}
end

-- The fresh list merged with the file (see the head of this file).
local function merge(class, list)
    local old = existing(class)
    if #old == 0 then return list end
    local byName, cost = {}, {}
    for _, t in ipairs(old) do
        byName[t.name] = byName[t.name] or {}
        table.insert(byName[t.name], t)
        cost[t.name .. "@" .. t.level] = t
    end
    for _, ranks in pairs(byName) do table.sort(ranks, function(a, b) return a.level < b.level end) end
    -- known ranks: their levels from the file, lowest first
    local used, counts = {}, {}
    for _, t in ipairs(list) do counts[t.name] = (counts[t.name] or 0) + 1 end
    for _, t in ipairs(list) do
        if t.level == 0 then
            local i = (used[t.name] or 0) + 1
            used[t.name] = i
            local o = byName[t.name] and byName[t.name][i]
            if o and #(byName[t.name]) < (counts[t.name] or 0) then
                print(class, "file lacks ranks of " .. t.name .. ": its level is a guess, check it")
            end
            if o then
                t.level = o.level
                if (t.cost or 0) == 0 then t.cost = o.cost end
                t.text = t.text or o.text
            else
                print(class, "known spell not in the file, level unknown: " .. t.name)
            end
        end
    end
    -- the trainer's discount: the fresh price over the file's, where both have one
    local ratios = {}
    for _, t in ipairs(list) do
        local o = cost[t.name .. "@" .. t.level]
        if o and o.cost > 0 and (t.cost or 0) > 0 then ratios[#ratios + 1] = t.cost / o.cost end
    end
    table.sort(ratios)
    local ratio = ratios[math.ceil(#ratios / 2)] or 1
    for _, t in ipairs(list) do
        local o = cost[t.name .. "@" .. t.level]
        if o then
            t.cost = o.cost
            -- the game's own text unfilled ("$w1" for Thorns' damage):
            -- the file's, which had the numbers
            if t.text and t.text:find("%$%a+%d") and o.text and not o.text:find("%$%a+%d") then t.text = o.text end
            t.text = t.text or o.text
        elseif ratio < 0.995 and (t.cost or 0) > 0 then
            t.cost = math.floor(t.cost / ratio + 0.5)
        end
    end
    if ratio < 0.995 then print(class, ("prices at %d%%: new spells' taken back to base"):format(math.floor(ratio * 100 + 0.5))) end
    return list
end

for _, class in ipairs(classes) do
    local d = all[class]
    local list = {}
    for _, t in ipairs(d.trainer or {}) do
        -- this client answered name, availability, icon: the probe kept the
        -- availability as `rank` and the icon as `kind`
        local icon = type(t.kind) == "number" and t.kind or (type(t.icon) == "number" and t.icon) or nil
        if t.name and t.level then
            list[#list + 1] = { name = t.name, level = t.level, cost = t.cost or 0, school = t.skill or "", icon = icon,
                text = t.description }
        end
    end
    list = merge(class, list)
    table.sort(list, function(a, b)
        if a.school ~= b.school then return a.school < b.school end
        if a.name ~= b.name then return a.name < b.name end
        return a.level < b.level
    end)
    if #list > 0 then
        local out = {}
        out[#out + 1] = "-- Data/Trainer/" .. class .. ".lua"
        out[#out + 1] = ("-- Generated by tools/gen_trainer.lua from the %s trainer (%s, %s). Don't edit by hand."):format(
            class, tostring(d.trainerNPC or "?"), tostring(d.trainerAt or "?"))
        out[#out + 1] = "-- What the class trainer teaches: name, required level, cost in copper,"
        out[#out + 1] = "-- school (skill line), icon, description. Only your class's file loads."
        out[#out + 1] = ""
        out[#out + 1] = "local _, ns = ..."
        out[#out + 1] = ""
        out[#out + 1] = "local _, class = UnitClass(\"player\")"
        out[#out + 1] = "if class ~= \"" .. class .. "\" then return end"
        out[#out + 1] = ""
        out[#out + 1] = "ns.TrainerSpells = {"
        for _, t in ipairs(list) do
            out[#out + 1] = ("    { name = %s, level = %d, cost = %d, school = %s, icon = %s, text = %s },"):format(
                q(t.name), t.level, t.cost, q(t.school), t.icon and tostring(t.icon) or "nil", t.text and q(t.text) or "nil")
        end
        out[#out + 1] = "}"
        out[#out + 1] = ""
        out[#out + 1] = "-- Every spell ID with each name (players' ranks and the rest: picked in game)."
        out[#out + 1] = "ns.TrainerSpellIDs = {"
        local names, seen = {}, {}
        for _, t in ipairs(list) do
            if not seen[t.name] then seen[t.name] = true; names[#names + 1] = t.name end
        end
        table.sort(names)
        local missing = 0
        -- the IDs the trainer's tooltips gave (/suu probe class), too
        local fromTrainer = {}
        for _, t in ipairs(d.trainer or {}) do
            if t.name and type(t.spellID) == "number" then
                fromTrainer[t.name] = fromTrainer[t.name] or {}
                fromTrainer[t.name][t.spellID] = true
            end
        end
        for _, name in ipairs(names) do
            local ids, have = {}, {}
            for _, row in pairs(byName[name] or {}) do
                local id = type(row) == "table" and row[1] or row
                if type(id) == "number" and not have[id] then ids[#ids + 1] = id; have[id] = true end
            end
            for id in pairs(fromTrainer[name] or {}) do
                if not have[id] then ids[#ids + 1] = id; have[id] = true end
            end
            table.sort(ids)
            if #ids == 0 then missing = missing + 1 end
            out[#out + 1] = ("    [%s] = { %s },"):format(q(name), table.concat(ids, ", "))
        end
        out[#out + 1] = "}"
        if missing > 0 then print(class, "names without IDs: " .. missing) end
        local f = assert(io.open(("Data/Trainer/%s.lua"):format(class), "w"))
        f:write(table.concat(out, "\n"), "\n")
        f:close()
        print(class, #list)
    end
end
