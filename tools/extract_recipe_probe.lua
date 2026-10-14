-- tools/extract_recipe_probe.lua
-- The game's recipe lists (/suu probe professions, one per profession) and
-- each character's recipe totals out of the saved variables, for
-- tools/match_recipes.py.
--   lua tools/extract_recipe_probe.lua "<WTF>/SavedVariables/SuuUI.lua" <probe.tsv>
local env = {}
assert(loadfile(arg[1], "t", env))()
local out = assert(io.open(arg[2], "w"))
for char, d in pairs(env.SuuUIDB.charData or {}) do
  for sl, v in pairs(d.professions and d.professions.recipes or {}) do out:write(("total\t%s\t%s\t%s\t%s\n"):format(char, sl, v.learned, v.total)) end
end
local P = env.SuuUIProbe and env.SuuUIProbe.professions or {}
if P.at then io.stderr:write("old single-profession layout; probe again with the new build\n") P = {} end
for sl, s in pairs(P) do
  out:write(("probed\t%s\t%s\t%s\t%s\n"):format(sl, tostring(s.name), #(s.all or {}), s.at))
  for _, line in ipairs(s.all or {}) do out:write(("recipe\t%s\t%s\n"):format(sl, (line:gsub("|", "\t")))) end
end
out:close()
