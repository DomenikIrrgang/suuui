-- tools/extract_found.lua
-- Adds the results of "/suu probe spells find <name>" to tools/data/found.tsv
-- (id<TAB>name), which the preset generator reads next to the scans.
--   lua tools/extract_found.lua "<WTF>/SavedVariables/SuuUI.lua" tools/data/found.tsv
local env = {}
assert(loadfile(arg[1], "t", env))()
local found = env.SuuUIProbe and env.SuuUIProbe.spellFind or {}
local rows, seen = {}, {}
local old = io.open(arg[2])
if old then
    for line in old:lines() do
        local id, name = line:match("^(%d+)\t(.+)$")
        if id then seen[id .. name] = true; rows[#rows + 1] = { tonumber(id), name } end
    end
    old:close()
end
for name, ids in pairs(found) do
    for _, id in ipairs(ids) do
        if not seen[id .. name] then seen[id .. name] = true; rows[#rows + 1] = { id, name } end
    end
end
table.sort(rows, function(a, b) return a[1] < b[1] end)
local out = assert(io.open(arg[2], "w"))
out:write("# spells found by name (/suu probe spells find)\n")
for _, r in ipairs(rows) do out:write(r[1], "\t", r[2], "\n") end
out:close()
print(("%d found spells in %s"):format(#rows, arg[2]))
