-- tools/gen_presets.lua
-- Generates Data/Presets/<CLASS>.lua from tools/presets_source.lua and the
-- Forever spell scan (tools/data/forever_spells.tsv): every name becomes all
-- the spell IDs that carry exactly that name in the client. A name the client
-- doesn't have stops the run, so nothing unverified reaches the presets.
--   lua tools/gen_presets.lua            (from the addon folder)
--   lua tools/gen_presets.lua MAGE       (one class only)

-- The main scan, plus Forever's own spells (1.2-1.33 million) in full.
local SCANS = { "tools/data/forever_spells.tsv", "tools/data/forever_own.tsv", "tools/data/found.tsv" }
local SOURCE = "tools/presets_source.lua"
local OUT = "Data/Presets/%s.lua"
local LISTS = { "essential", "utility", "buffs", "debuffs", "procs" }

-- name -> sorted ids
local byName, scanLine = {}, nil
for _, path in ipairs(SCANS) do
    local seen = {}
    local exists = io.open(path)
    if exists then exists:close() end
    for line in (exists and io.lines(path) or function() return nil end) do
        if line:sub(1, 1) == "#" then
            scanLine = scanLine or line
        else
            local id, name = line:match("^(%d+)\t([^\t]*)")
            if id then
                id = tonumber(id)
                local list = byName[name]
                if not list then list = {}; byName[name] = list end
                list[#list + 1] = id
            end
        end
    end
end
-- Class data (/suu probe class): talent IDs some scans lack, and which spells
-- a class really has (trainer + talents), to warn about presets offering
-- spells the class can't get on Forever.
local classSpells = {}
-- per class: the IDs of passive talents (an aura entry leaves them out: a
-- passive can sit on you as a hidden aura, which would read as always up)
-- and the IDs the class really has (talents, spellbooks: a group's icon)
local passiveIDs, knownIDs = {}, {}
for _, class in ipairs({ "DRUID", "HUNTER", "MAGE", "PALADIN", "PRIEST", "ROGUE", "SHAMAN", "WARLOCK", "WARRIOR" }) do
    local f = io.open(("tools/data/class_%s.tsv"):format(class:lower()))
    if f then
        local set, passive, known = {}, {}, {}
        passiveIDs[class], knownIDs[class] = passive, known
        for line in f:lines() do
            if line:sub(1, 1) ~= "#" then
                local source, _, id, name, _, _, active = line:match("^([^\t]*)\t([^\t]*)\t([^\t]*)\t([^\t]*)\t([^\t]*)\t([^\t]*)\t([^\t]*)")
                if not source then source, _, id, name = line:match("^([^\t]*)\t([^\t]*)\t([^\t]*)\t([^\t]*)") end
                if source == "talent" and tonumber(id) then
                    known[tonumber(id)] = true
                    if active == "passive" then passive[tonumber(id)] = true end
                end
                if name and name ~= "" then
                    set[name] = true
                    if source == "talent" and tonumber(id) then
                        byName[name] = byName[name] or {}
                        table.insert(byName[name], tonumber(id))
                    end
                end
            end
        end
        f:close()
        -- a character's spellbook too: trainers don't list what it already knows
        local book = io.open(("tools/data/spellbook_%s.tsv"):format(class:lower()))
        if book then
            for line in book:lines() do
                local id, name = line:match("^(%d+)\t([^\t]*)")
                if name then set[name] = true; known[tonumber(id)] = true end
            end
            book:close()
        end
        classSpells[class] = set
    end
end

-- sorted, without duplicates (the two scans overlap above 1.2 million)
for name, list in pairs(byName) do
    table.sort(list)
    local out = {}
    for _, id in ipairs(list) do if out[#out] ~= id then out[#out + 1] = id end end
    byName[name] = out
end

local missing, resolved = {}, {}
local source = dofile(SOURCE)

-- Behaviour an entry may carry (the Cooldown Manager's Behaviour panel keys,
-- copied as they are), and how each is written out.
local BEHAVIOUR = { "ready", "pop", "sound", "onCooldown", "show", "unusable", "border", "effect", "missing", "size",
                    "glow", "digits", "stacks", "expiring", "soundAppear", "soundStack", "soundDrop", "hidden", "source" }

-- An aura's IDs without the class's passive talents (when anything else is
-- left; otherwise warned about: the aura's own ID is still to be found).
local AURA_LISTS = { buffs = true, debuffs = true, procs = true }
local passiveOnly = {}
local function auraIDs(class, ids, where)
    local passive = passiveIDs[class]
    if not passive then return ids end
    local out = {}
    for _, id in ipairs(ids) do if not passive[id] then out[#out + 1] = id end end
    if #out == 0 then
        passiveOnly[#passiveOnly + 1] = where
        return ids
    end
    return out
end

-- The ID a group shows when none of its members is up: one the class really
-- has (the lowest ID can be an NPC version with other art).
local function iconID(class, ids)
    local known = knownIDs[class]
    if known then
        for _, id in ipairs(ids) do if known[id] then return id end end
    end
    return ids[1]
end

-- Mistakes in the source's structure (a collection where it can't be, a
-- condition the tracker doesn't know); they stop the run like unknown names.
local invalid = {}

-- Conditions (`when`), as the tracker reads them (UI/CooldownTracker.lua):
-- each type's field and the values it takes.
local CLASS_TOKENS = { "WARRIOR", "PALADIN", "HUNTER", "ROGUE", "PRIEST", "SHAMAN", "MAGE", "WARLOCK", "DRUID" }
local WHEN = {
    group = { field = "value", values = { "solo", "group", "raid" }, one = true },
    classes = { field = "classes", values = CLASS_TOKENS },
    role = { field = "roles", values = { "TANK", "HEALER", "DAMAGER" } },
    stance = { field = "stances", values = { "battle", "defensive", "berserker", "caster", "bear", "cat", "moonkin",
                                             "travel", "aquatic", "stealth", "shadowform" } },
    combat = {},
    instance = { field = "kinds", values = { "none", "party", "raid", "pvp" } },
    target = { field = "kinds", values = { "boss", "elite", "player", "normal" } },
}
for _, t in pairs(WHEN) do
    t.set = {}
    for _, v in ipairs(t.values or {}) do t.set[v] = true end
end

-- A source entry's `when`, checked (every mistake into invalid) and copied
-- with only the keys the tracker reads; nil without one.
local function checkWhen(when, where)
    if when == nil then return nil end
    local w = where .. ": when"
    if type(when) ~= "table" or type(when.conditions) ~= "table" then
        invalid[#invalid + 1] = w .. " needs conditions = { ... }"
        return nil
    end
    if when.match ~= nil and when.match ~= "all" and when.match ~= "any" then
        invalid[#invalid + 1] = ("%s: match %q isn't \"all\" or \"any\""):format(w, tostring(when.match))
    end
    local out = { match = when.match, conditions = {} }
    for i, c in ipairs(when.conditions) do
        local cw = ("%s condition %d"):format(w, i)
        local t = type(c) == "table" and WHEN[c.type]
        if not t then
            invalid[#invalid + 1] = ("%s: unknown type %q"):format(cw, tostring(type(c) == "table" and c.type or c))
        else
            local copy = { type = c.type, ["not"] = c["not"] and true or nil }
            if t.one then
                if not t.set[c[t.field]] then
                    invalid[#invalid + 1] = ("%s: %s %q isn't one of %s"):format(cw, t.field, tostring(c[t.field]), table.concat(t.values, ", "))
                end
                copy[t.field] = c[t.field]
            elseif t.field then
                local list = c[t.field]
                if type(list) ~= "table" or #list == 0 then
                    invalid[#invalid + 1] = ("%s: %s needs a list of %s"):format(cw, t.field, table.concat(t.values, ", "))
                else
                    for _, v in ipairs(list) do
                        if not t.set[v] then
                            invalid[#invalid + 1] = ("%s: %s %q isn't one of %s"):format(cw, t.field, tostring(v), table.concat(t.values, ", "))
                        end
                    end
                    copy[t.field] = list
                end
            end
            out.conditions[#out.conditions + 1] = copy
        end
    end
    return out
end

-- The behaviour fields of a source entry; effectName (an aura's name) becomes
-- effectIDs, every ID with that name, like any entry's.
local function behaviour(entry, where, class)
    local b = {}
    if type(entry) ~= "table" then return b end
    for _, k in ipairs(BEHAVIOUR) do
        if entry[k] ~= nil and not (k == "source" and entry.group) then b[k] = entry[k] end
    end
    if entry.effectName then
        local ids = byName[entry.effectName]
        if not ids then
            missing[#missing + 1] = ("%s: effectName %q"):format(where, entry.effectName)
        else
            b.effectIDs, b.effectName = class and auraIDs(class, ids, where .. " effect") or ids, entry.effectName
        end
    end
    return b
end

-- A group member: a name, or { "Name", source = "mine"|"others"|"any" } (its
-- own source; else the group's).
local function memberName(m) return type(m) == "table" and m[1] or m end

-- A group: every member resolved, the union as its IDs. In aura lists the
-- members leave out the class's passive talents; in cooldown lists they
-- don't (a cooldown group shows the last member the player knows).
local function resolveGroup(entry, key, where, class)
    local cooldowns = not AURA_LISTS[key]
    local gwhere = ("%s / group %s"):format(where, entry.group)
    local g = { group = true, name = entry.group, cooldowns = cooldowns, source = entry.source or "mine", max = entry.max or 1,
        members = {}, behaviour = behaviour(entry, gwhere, class), when = checkWhen(entry.when, gwhere) }
    local union, seen = {}, {}
    for _, m in ipairs(entry.members) do
        local mname = memberName(m)
        local mwhere = ("%s / group %s: %q"):format(where, entry.group, tostring(mname))
        local ids = byName[mname]
        if ids and not cooldowns then ids = auraIDs(class, ids, mwhere) end
        if not ids then
            missing[#missing + 1] = mwhere
        else
            g.members[#g.members + 1] = { name = mname, ids = ids, source = type(m) == "table" and m.source or nil,
                when = type(m) == "table" and checkWhen(m.when, mwhere) or nil }
            for _, id in ipairs(ids) do if not seen[id] then seen[id] = true; union[#union + 1] = id end end
            if mname == entry.icon then g.icon = iconID(class, ids) end
        end
    end
    table.sort(union)
    g.ids = union
    g.icon = g.icon or (g.members[1] and iconID(class, g.members[1].ids))
    return g
end

-- A single entry: a name, or { "Name", behaviour... }.
local function resolveSingle(entry, key, where, class)
    local name = type(entry) == "table" and entry[1] or entry
    local ids = byName[name]
    local w = ("%s: %q"):format(where, tostring(name))
    if ids and AURA_LISTS[key] then ids = auraIDs(class, ids, w) end
    if not ids then
        missing[#missing + 1] = w
        return nil
    end
    return { name = name, ids = ids, mine = type(entry) == "table" and entry.mine or nil, behaviour = behaviour(entry, w, class),
             when = type(entry) == "table" and checkWhen(entry.when, w) or nil }
end

-- Any entry of a list: a collection (aura lists only, one level: its
-- entries are single entries and groups), a group, or a single entry.
local function resolveEntry(entry, key, where, class, inCollection)
    if type(entry) == "table" and entry.collection then
        local cwhere = ("%s / collection %s"):format(where, tostring(entry.collection))
        if inCollection then
            invalid[#invalid + 1] = cwhere .. ": a collection inside a collection"
            return nil
        end
        if not AURA_LISTS[key] then
            invalid[#invalid + 1] = cwhere .. ": collections go in buffs, debuffs or procs only"
            return nil
        end
        local c = { collection = true, name = entry.collection, hidden = entry.hidden, entries = {},
                    when = checkWhen(entry.when, cwhere) }
        for _, sub in ipairs(entry.entries or {}) do
            c.entries[#c.entries + 1] = resolveEntry(sub, key, cwhere, class, true)
        end
        return c
    elseif type(entry) == "table" and entry.group then
        return resolveGroup(entry, key, where, class)
    end
    return resolveSingle(entry, key, where, class)
end

-- Resolve every entry first; report every unknown name at once.
resolved = {}
local classes = {}
-- one class only with an argument (lua tools/gen_presets.lua MAGE)
for class in pairs(source) do
    if not arg[1] or arg[1]:upper() == class then classes[#classes + 1] = class end
end
table.sort(classes)
for _, class in ipairs(classes) do
    resolved[class] = {}
    for _, preset in ipairs(source[class]) do
        local p = { id = preset.id, name = preset.name, tree = preset.tree or 0, lists = {} }
        for _, key in ipairs(LISTS) do
            local out = {}
            for _, entry in ipairs(preset[key] or {}) do
                out[#out + 1] = resolveEntry(entry, key, ("%s / %s / %s"):format(class, preset.name, key), class)
            end
            p.lists[key] = out
        end
        table.insert(resolved[class], p)
    end
end

-- Cooldowns the class can't learn on Forever (only for classes with data).
for _, class in ipairs(classes) do
    local set = classSpells[class]
    if set then
        for _, preset in ipairs(source[class]) do
            for _, key in ipairs({ "essential", "utility" }) do
                for _, entry in ipairs(preset[key] or {}) do
                    -- a group: each member (a collection here is reported
                    -- as misplaced)
                    local names = { type(entry) == "table" and entry[1] or entry }
                    if type(entry) == "table" and entry.collection then
                        names = {}
                    elseif type(entry) == "table" and entry.group then
                        names = {}
                        for _, m in ipairs(entry.members or {}) do names[#names + 1] = memberName(m) end
                    end
                    for _, name in ipairs(names) do
                        if not set[name] then
                            io.stderr:write(("warning: %s / %s / %s: %q isn't in the class's trainer or talents\n"):format(class, preset.name, key, tostring(name)))
                        end
                    end
                end
            end
        end
    end
end

-- Auras that resolve only to a passive talent's ID: their own aura ID is
-- missing (find it in game: /suu probe spells while the proc is up, or
-- /suu probe spells find <name>, then tools/data/found.tsv).
if #passiveOnly > 0 then
    io.stderr:write(("%d auras resolve only to a passive talent's ID:\n"):format(#passiveOnly))
    for _, w in ipairs(passiveOnly) do io.stderr:write("  ", w, "\n") end
end

if #invalid > 0 then
    io.stderr:write(("%d mistakes in the source (misplaced entries, unknown conditions):\n"):format(#invalid))
    for _, m in ipairs(invalid) do io.stderr:write("  ", m, "\n") end
end
if #missing > 0 then
    io.stderr:write(("%d names aren't in the client:\n"):format(#missing))
    for _, m in ipairs(missing) do io.stderr:write("  ", m, "\n") end
end
if #missing > 0 or #invalid > 0 then os.exit(1) end

-- Behaviour fields as Lua: " key = value," each, in a fixed order.
local function behaviourText(b)
    local parts = {}
    for _, k in ipairs(BEHAVIOUR) do
        local v = b and b[k]
        if type(v) == "string" then parts[#parts + 1] = (" %s = %q,"):format(k, v)
        elseif v ~= nil then parts[#parts + 1] = (" %s = %s,"):format(k, tostring(v)) end
    end
    if b and b.effectIDs then
        local ids = {}
        for _, id in ipairs(b.effectIDs) do ids[#ids + 1] = tostring(id) end
        parts[#parts + 1] = (" effectName = %q, effectIDs = { %s },"):format(b.effectName, table.concat(ids, ", "))
    end
    return table.concat(parts)
end

-- A `when` as Lua: " when = { ... }," (empty without one). Keys in a fixed
-- order: match, then each condition's type, its choice, not.
local function whenText(when)
    if not when then return "" end
    local function list(values)
        local parts = {}
        for _, v in ipairs(values) do parts[#parts + 1] = ("%q"):format(v) end
        return "{ " .. table.concat(parts, ", ") .. " }"
    end
    local conds = {}
    for _, c in ipairs(when.conditions) do
        local parts = { ("type = %q"):format(c.type) }
        local t = WHEN[c.type]
        if t.field and c[t.field] ~= nil then
            parts[#parts + 1] = ("%s = %s"):format(t.field, t.one and ("%q"):format(c[t.field]) or list(c[t.field]))
        end
        if c["not"] then parts[#parts + 1] = '["not"] = true' end
        conds[#conds + 1] = "{ " .. table.concat(parts, ", ") .. " }"
    end
    return (" when = {%s conditions = { %s } },"):format(when.match and (" match = %q,"):format(when.match) or "",
        table.concat(conds, ", "))
end

local function idList(ids)
    local parts = {}
    for _, id in ipairs(ids) do parts[#parts + 1] = tostring(id) end
    return table.concat(parts, ", ")
end

-- An entry as Lua lines at `indent`: a collection (its entries one level
-- in), a group (a cooldown list's without source and max), or a single one.
local function writeEntry(lines, e, indent)
    if e.collection then
        lines[#lines + 1] = ("%s{ collection = true, name = %q,%s%s entries = {"):format(indent, e.name, e.hidden and " hidden = true," or "", whenText(e.when))
        for _, sub in ipairs(e.entries) do writeEntry(lines, sub, indent .. "    ") end
        lines[#lines + 1] = indent .. "} },"
    elseif e.group then
        local slot = e.cooldowns and "" or (" source = %q, max = %d,"):format(e.source, e.max)
        lines[#lines + 1] = ("%s{ group = true, name = %q,%s icon = %d,%s%s members = {"):format(indent, e.name, slot, e.icon or 0, behaviourText(e.behaviour), whenText(e.when))
        for _, m in ipairs(e.members) do
            lines[#lines + 1] = ("%s    { name = %q,%s%s ids = { %s } },"):format(indent, m.name, m.source and (" source = %q,"):format(m.source) or "", whenText(m.when), idList(m.ids))
        end
        lines[#lines + 1] = ("%s}, ids = { %s } },"):format(indent, idList(e.ids))
    else
        lines[#lines + 1] = ("%s{ name = %q,%s%s%s ids = { %s } },"):format(indent, e.name, e.mine and " mine = true," or "", behaviourText(e.behaviour), whenText(e.when), idList(e.ids))
    end
end

for _, class in ipairs(classes) do
    local lines = {
        ("-- Data/Presets/%s.lua"):format(class),
        "-- Generated by tools/gen_presets.lua from tools/presets_source.lua and the",
        ("-- Forever spell scan (%s). Don't edit by hand."):format((scanLine or ""):gsub("^#%s*", "")),
        "-- Every entry carries all the IDs with its exact name in the client: every",
        "-- rank, plus NPC versions, which never match (they are never yours, and the",
        "-- tracker only uses the ranks you know). Only your class's file loads.",
        "",
        "local _, ns = ...",
        "",
        "local _, class = UnitClass(\"player\")",
        ("if class ~= %q then return end"):format(class),
        "",
        "ns.CooldownPresets = {",
    }
    for _, p in ipairs(resolved[class]) do
        lines[#lines + 1] = ("    { id = %q, name = %q, tree = %d, lists = {"):format(p.id, p.name, p.tree)
        for _, key in ipairs(LISTS) do
            lines[#lines + 1] = ("        %s = {"):format(key)
            for _, e in ipairs(p.lists[key]) do writeEntry(lines, e, "            ") end
            lines[#lines + 1] = "        },"
        end
        lines[#lines + 1] = "    } },"
    end
    lines[#lines + 1] = "}"
    local f = assert(io.open(OUT:format(class), "w"))
    f:write(table.concat(lines, "\n"), "\n")
    f:close()
    local n = 0
    for _, p in ipairs(resolved[class]) do for _, key in ipairs(LISTS) do n = n + #p.lists[key] end end
    print(("%-8s %d presets, %d entries -> %s"):format(class, #resolved[class], n, OUT:format(class)))
end
