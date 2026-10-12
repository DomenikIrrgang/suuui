-- tools/extract_spellbooks.lua
-- Copies each character's spellbook (/suu probe spells) out of the saved
-- variables into tools/data/spellbook_<class>.tsv: id, name, rank, tab,
-- owner, passive, base cooldown in ms, and for pet spells the pet's family.
-- Which tab a spell sits in tells which talent tree (preset) it belongs to.
--   lua tools/extract_spellbooks.lua "<WTF>/SavedVariables/SuuUI.lua" tools/data
local env = {}
assert(loadfile(arg[1], "t", env))()
local chars = assert(env.SuuUIProbe and env.SuuUIProbe.spells, "no spellbooks in the saved variables")
for key, d in pairs(chars) do
    local ids = {}
    for id in pairs(d.spellbook or {}) do ids[#ids + 1] = id end
    table.sort(ids)
    local path = ("%s/spellbook_%s.tsv"):format(arg[2], (d.class or "UNKNOWN"):lower())
    local out = assert(io.open(path, "w"))
    out:write(("# %s, %s level %s, %s\n"):format(key, d.class or "?", tostring(d.level), d.spellbookAt or "?"))
    for _, id in ipairs(ids) do
        local e = d.spellbook[id]
        out:write(table.concat({ id, e.name or "", e.rank or "", e.tab or "", e.owner or "", e.passive and "passive" or "", e.cooldownMS or "", e.family or "" }, "\t"), "\n")
    end
    out:close()
    print(("%s: %d spells -> %s"):format(key, #ids, path))
end
