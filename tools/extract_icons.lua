-- tools/extract_icons.lua
-- Copies the preset spells' art (/suu probe icons) out of the saved
-- variables into tools/data/icons.tsv: spell ID, icon file ID. The preset
-- generator gives each entry the art most of its ranks share.
--   lua tools/extract_icons.lua "<WTF>/SavedVariables/SuuUI.lua" tools/data/icons.tsv
local env = {}
assert(loadfile(arg[1], "t", env))()
local data = assert(env.SuuUIProbe and env.SuuUIProbe.icons, "no icons in the saved variables (/suu probe icons)")
local ids = {}
for id in pairs(data.icons or {}) do ids[#ids + 1] = id end
table.sort(ids)
local out = assert(io.open(arg[2], "w"))
out:write(("# preset spell art, %s\n"):format(data.at or "?"))
for _, id in ipairs(ids) do out:write(id, "\t", data.icons[id], "\n") end
out:close()
print(("%d spells' art -> %s"):format(#ids, arg[2]))
