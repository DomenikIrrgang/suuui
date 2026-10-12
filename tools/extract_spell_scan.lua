-- tools/extract_spell_scan.lua
-- Copies the client spell scan (/suu probe spells scan) out of the saved
-- variables into tools/data/forever_spells.tsv: one line per spell ID,
-- "id<TAB>name<TAB>rank", sorted by ID. The presets are checked against it.
--   lua tools/extract_spell_scan.lua "<WTF>/SavedVariables/SuuUI.lua" tools/data/forever_spells.tsv
local env = {}
assert(loadfile(arg[1], "t", env))()
local scan = assert(env.SuuUIProbe and env.SuuUIProbe.spellScan, "no spell scan in the saved variables")
local rows = {}
for name, list in pairs(scan.byName) do
    for _, e in ipairs(list) do rows[#rows + 1] = { e[1], name, e[2] or "" } end
end
table.sort(rows, function(a, b) return a[1] < b[1] end)
local out = assert(io.open(arg[2], "w"))
out:write(("# Forever client spell scan, %s, %d of %d spells kept, highest ID %d\n"):format(scan.at, scan.kept or #rows, scan.count, scan.highest))
for _, r in ipairs(rows) do out:write(r[1], "\t", r[2], "\t", r[3], "\n") end
out:close()
print(("%d spells written to %s"):format(#rows, arg[2]))
