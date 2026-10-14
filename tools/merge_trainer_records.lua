-- tools/merge_trainer_records.lua
-- The profession trainers SuuUI recorded in game (the Professions module, on
-- TRAINER_SHOW: what each trainer teaches and the skill it needs) from one or
-- more SavedVariables files, merged into tools/data/trainer_records.tsv: one
-- line per trainer and recipe. Lines already in the file stay; a trainer
-- recorded again replaces its own lines. The SavedVariables run in an empty
-- sandbox (no io, no os).
--   lua tools/merge_trainer_records.lua tools/data/trainer_records.tsv <SuuUI.lua> [<SuuUI.lua> ...]
local out = arg[1]
assert(out and arg[2], "usage: merge_trainer_records.lua <out.tsv> <SuuUI.lua> [...]")

local COLUMNS = { "profession", "recipe", "skill", "cost", "level", "item", "npcID", "npc", "zone", "subzone", "faction", "at" }

local function clean(v)
    return (tostring(v == nil and "" or v):gsub("[\t\n\r]", " "))
end

-- what's there already, by trainer
local byTrainer, order = {}, {}
local function keep(key, row)
    if not byTrainer[key] then
        byTrainer[key] = { rows = {}, at = row.at }
        order[#order + 1] = key
    end
    local t = byTrainer[key]
    t.rows[#t.rows + 1] = row
end
local f = io.open(out, "r")
if f then
    local header
    for line in f:lines() do
        if not line:match("^#") then
            local cells = {}
            for c in (line .. "\t"):gmatch("([^\t]*)\t") do cells[#cells + 1] = c end
            if not header then
                header = cells
            else
                local row = {}
                for i, name in ipairs(header) do row[name] = cells[i] end
                keep(row.npcID ~= "" and row.npcID or row.npc, row)
            end
        end
    end
    f:close()
end

-- the recordings: a newer one of a trainer replaces what was kept
local added = 0
for i = 2, #arg do
    local env = {}
    local chunk = assert(loadfile(arg[i], "t", env))
    chunk()
    local db = env.SuuUIDB or {}
    for _, char in pairs(db.charData or {}) do
        for _, rec in pairs((char.professions or {}).trainers or {}) do
            local key = tostring(rec.npcID or rec.npc)
            local old = byTrainer[key]
            if not old or (rec.at or "") >= (old.at or "") then
                if not old then order[#order + 1] = key end
                local rows = {}
                for _, sv in ipairs(rec.services or {}) do
                    rows[#rows + 1] = {
                        profession = rec.profession, recipe = sv.name, skill = sv.rank, cost = sv.cost,
                        level = sv.level, item = sv.item, npcID = rec.npcID, npc = rec.npc, zone = rec.zone,
                        subzone = rec.subzone, faction = rec.faction, at = rec.at,
                    }
                end
                byTrainer[key] = { rows = rows, at = rec.at }
                added = added + 1
            end
        end
    end
end

table.sort(order)
local w = assert(io.open(out, "w"))
w:write("# Profession trainers recorded in game by SuuUI (tools/merge_trainer_records.lua): what each teaches and the skill it needs\n")
w:write(table.concat(COLUMNS, "\t"), "\n")
local lines = 0
for _, key in ipairs(order) do
    for _, row in ipairs(byTrainer[key].rows) do
        local cells = {}
        for j, c in ipairs(COLUMNS) do cells[j] = clean(row[c]) end
        w:write(table.concat(cells, "\t"), "\n")
        lines = lines + 1
    end
end
w:close()
print(("%d trainers merged or updated; %d trainers, %d lines in %s"):format(added, #order, lines, out))
