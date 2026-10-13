-- tools/extract_forever_own.lua
-- Copies Forever's own spells (/suu probe spells scan forever) out of the
-- saved variables into tools/data/forever_own.tsv: id, name, rank.
--   lua tools/extract_forever_own.lua "<WTF>/SavedVariables/SuuUI.lua" tools/data/forever_own.tsv
local env = {}
assert(loadfile(arg[1], "t", env))()
local scan = assert(env.SuuUIProbe and env.SuuUIProbe.spellScanForever, "no Forever scan in the saved variables")
local out = assert(io.open(arg[2], "w"))
out:write(("# Forever's own spells %d-%d, %s, %d spells\n"):format(scan.from, scan.to, scan.at, #scan.rows))
for _, r in ipairs(scan.rows) do out:write(r[1], "\t", r[2], "\t", r[3] or "", "\n") end
out:close()
print(("%d spells written to %s"):format(#scan.rows, arg[2]))
