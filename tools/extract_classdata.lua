-- tools/extract_classdata.lua
-- Copies each class's data (/suu probe class) out of the saved variables into
-- tools/data/class_<class>.tsv, one line per talent or trainer spell:
--   source  tree  spellID  name  rank  level  active  cooldown  description  cost
-- (cost: a trainer spell's training cost in copper)
-- source is "talent" or "trainer"; tree is the talent tree by position (1, 2,
-- 3 from left to right); trainer lines carry the required level. The
-- generator takes talent IDs from here (some aren't in the scans).
--   lua tools/extract_classdata.lua "<WTF>/SavedVariables/SuuUI.lua" tools/data
local env = {}
assert(loadfile(arg[1], "t", env))()
local all = assert(env.SuuUIProbe and env.SuuUIProbe.classData, "no class data in the saved variables")
-- one line of text: tabs and line breaks would break the columns
local function flat(text)
    return (tostring(text or ""):gsub("[\t\r\n]+", " "))
end

for class, d in pairs(all) do
    -- trees by x: the three columns of nodes, left to right
    local xs = {}
    for _, t in ipairs(d.talents or {}) do if t.x and t.x < 20000 then xs[#xs + 1] = t.x end end
    table.sort(xs)
    local lo, hi = xs[1] or 0, xs[#xs] or 0
    local function tree(x)
        if not x or x >= 20000 then return "?" end
        local third = (hi - lo) / 3
        if x < lo + third then return 1 elseif x < lo + 2 * third then return 2 else return 3 end
    end
    local path = ("%s/class_%s.tsv"):format(arg[2], class:lower())
    local out = assert(io.open(path, "w"))
    out:write(("# %s: %s, level %s %s; talents %s, trainer %s (%s, up to level %s)\n"):format(class,
        tostring(d.character), tostring(d.level), tostring(d.race), d.talentsAt or "-", d.trainerAt or "-",
        tostring(d.trainerNPC), tostring(d.trainerMaxLevel)))
    for _, t in ipairs(d.talents or {}) do
        out:write(table.concat({ "talent", tree(t.x), t.spellID, t.name or "", "", "", t.passive and "passive" or "active",
            t.cooldown and tostring(t.cooldown) or "", flat(t.description), "" }, "\t"), "\n")
    end
    for _, s in ipairs(d.trainer or {}) do
        out:write(table.concat({ "trainer", "", "", s.name or "", s.rank or "", tostring(s.level or ""), "", "", flat(s.description),
            s.cost and tostring(s.cost) or "" }, "\t"), "\n")
    end
    out:close()
    print(("%s: %d talents, %d trainer spells -> %s"):format(class, #(d.talents or {}), #(d.trainer or {}), path))
end
