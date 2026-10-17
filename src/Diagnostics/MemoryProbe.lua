-- Diagnostics/MemoryProbe.lua
-- "/suu probe memory" (asked 2026-10-18: SuuUI showed 68 MB): where SuuUI's
-- memory goes. Records SuuUI's memory before and after a full garbage
-- collection (what was only garbage), then an estimate of what each part
-- holds, walked once so nothing counts twice: the saved variables
-- (SuuUIProbe, then SuuUIDB's profiles and each character's data), each
-- module, then the namespace's tables (the bundled data: quest givers,
-- collection sources…).
-- Estimates use Lua 5.1's sizes (a table's header, array and hash parts; each
-- string once); what no walk reaches (closures, upvalues, the frames' own
-- objects) is the rest. Saved in SuuUIProbe.memory on /reload.

local _, ns = ...

local MemP = {}
ns.MemoryProbe = MemP

local ADDON = "SuuUI"

local function addonKB()
    UpdateAddOnMemoryUsage()
    return GetAddOnMemoryUsage(ADDON)
end

-- A walker with one seen set: a table or string reached again costs nothing.
local function walker(seen)
    local function size(v)
        local t = type(v)
        if t == "string" then
            if seen[v] then return 0 end
            seen[v] = true
            return 25 + #v
        elseif t == "function" then
            if seen[v] then return 0 end
            seen[v] = true
            return 40
        elseif t ~= "table" then
            return 0
        end
        if seen[v] then return 0 end
        seen[v] = true
        -- a frame: its own fields only, never into the game's frames
        if type(rawget(v, 0)) == "userdata" and v.IsForbidden and v:IsForbidden() then return 0 end
        local arr, hash, n = 0, 0, 56
        -- a table the game guards (secret keys) can't be walked: counted empty
        pcall(function()
            arr = #v
            for k, x in pairs(v) do
                if not (type(k) == "number" and k >= 1 and k <= arr and k % 1 == 0) then hash = hash + 1 end
                n = n + size(k) + size(x)
            end
        end)
        local slots = 0
        if hash > 0 then slots = 1; while slots < hash do slots = slots * 2 end end
        return n + 16 * arr + 40 * slots
    end
    return size
end

local function kb(bytes) return math.floor(bytes / 1024 + 0.5) end

-- The largest entries of a table, each its own size (walked in order, so a
-- table shared by two counts for the first).
local function biggest(size, t, limit)
    local rows = {}
    for k, v in pairs(t) do
        if type(v) == "table" then rows[#rows + 1] = { k = tostring(k), v = v } end
    end
    table.sort(rows, function(a, b) return a.k < b.k end)
    local total = 0
    for _, r in ipairs(rows) do r.n = size(r.v); total = total + r.n end
    table.sort(rows, function(a, b) return a.n > b.n end)
    local out = {}
    for i = 1, math.min(limit, #rows) do
        if rows[i].n >= 10240 then out[#out + 1] = ("%s %d KB"):format(rows[i].k, kb(rows[i].n)) end
    end
    return out, total
end

-- Down the biggest branch of a table: each level's largest fields, then
-- into the largest, for up to `depth` levels (a list's items count as one
-- field, "[n]", the size of all of them, shown with the first's breakdown).
local function drill(gameFrames, t, depth)
    local out = {}
    for level = 1, depth do
        if type(t) ~= "table" then break end
        local seen = setmetatable({}, { __index = gameFrames })
        seen[t] = true
        local size = walker(seen)
        local rows, items, itemN, first = {}, 0, 0, nil
        for k, v in pairs(t) do
            if type(k) == "number" then
                items = items + 1
                itemN = itemN + size(v)
                first = first or v
            elseif type(v) == "table" or type(v) == "string" then
                rows[#rows + 1] = { k = tostring(k), v = v, n = size(v) }
            end
        end
        if items > 0 then rows[#rows + 1] = { k = "[" .. items .. "]", v = first, n = itemN } end
        table.sort(rows, function(a, b) return a.n > b.n end)
        local line = {}
        for i = 1, math.min(6, #rows) do line[#line + 1] = ("%s %d KB"):format(rows[i].k, kb(rows[i].n)) end
        out[level] = table.concat(line, ", ")
        t = rows[1] and rows[1].v
    end
    return out
end

-- An aura container's buttons: how many the engine made per group (and
-- distinct buttons, in case it initialises one twice), against the maxima.
local function containerInfo(c)
    if not (c and c.buttons) then return "none" end
    local per, distinct, n = {}, {}, 0
    for _, b in ipairs(c.buttons) do
        per[b.key] = (per[b.key] or 0) + 1
        if not distinct[b.button] then distinct[b.button] = true; n = n + 1 end
    end
    local maxima = {}
    for _, g in ipairs(c.opts and c.opts.groups or {}) do
        local cur = c.container.GetAuraGroupMaxFrameCount and select(2, pcall(c.container.GetAuraGroupMaxFrameCount, c.container, g.key))
        maxima[#maxima + 1] = ("%s made=%d max=%s now=%s"):format(tostring(g.key), per[g.key] or 0, tostring(g.max), tostring(cur))
    end
    return ("%d entries, %d buttons: %s"):format(#c.buttons, n, table.concat(maxima, "; "))
end

function MemP.Command()
    local out = { at = date("%Y-%m-%d %H:%M:%S") }
    out.before = math.floor(addonKB())
    out.allAddonsBefore = math.floor(collectgarbage("count"))
    collectgarbage("collect")
    out.after = math.floor(addonKB())
    out.allAddonsAfter = math.floor(collectgarbage("count"))
    out.garbage = out.before - out.after

    -- the game's named frames are the game's: never walked
    local gameFrames = {}
    for name, v in pairs(_G) do
        if type(v) == "table" and type(rawget(v, 0)) == "userdata"
            and not (type(name) == "string" and name:find("^SuuUI")) then gameFrames[v] = true end
    end
    local seen = setmetatable({}, { __index = gameFrames })
    local size = walker(seen)
    local walked = 0

    -- the probe data first, so the rest never counts it
    local probe = SuuUIProbe
    local last = probe and probe.memory
    if probe then probe.memory = nil end
    out.probe, out.probeKB = biggest(size, probe or {}, 12)
    out.probeKB = kb(out.probeKB)
    walked = walked + out.probeKB
    if probe then probe.memory = last end

    local db = SuuUIDB or {}
    local dbKB
    out.db, dbKB = biggest(size, db, 12)
    out.dbKB = kb(dbKB)
    walked = walked + out.dbKB
    -- each profile and character on its own (strings they share count in each)
    out.profiles = biggest(walker({}), db.profiles or {}, 12)
    out.chars = biggest(walker({}), db.charData or {}, 12)
    -- inside the biggest profile and character, one level down
    for _, which in ipairs({ "profiles", "charData" }) do
        local best, bestN
        for k, v in pairs(db[which] or {}) do
            local n = walker({})(v)
            if not bestN or n > bestN then best, bestN = k, n end
        end
        if best then out[which .. "Inside"] = { name = tostring(best), (biggest(walker({}), db[which][best], 10)) } end
    end

    -- each module, its frames included
    local mods = {}
    for _, m in ipairs(ns.Modules and ns.Modules.All() or {}) do mods[tostring(m.id)] = m end
    local modKB
    out.modules, modKB = biggest(size, mods, 25)
    out.modulesKB = kb(modKB)
    walked = walked + out.modulesKB
    -- the biggest modules, down their biggest branch
    out.drill = {}
    for _, id in ipairs({ "raid", "party", "auras", "cooldowns", "actionbars" }) do
        if mods[id] then out.drill[id] = drill(gameFrames, mods[id], 6) end
    end

    -- the namespace: bundled data, shared tables
    local nsTables = {}
    for k, v in pairs(ns) do
        if type(v) == "table" and type(rawget(v, 0)) ~= "userdata" then nsTables[k] = v end
    end
    local nsKB
    out.ns, nsKB = biggest(size, nsTables, 25)
    out.nsKB = kb(nsKB)
    walked = walked + out.nsKB

    -- the aura containers that hold the most
    local raid, party, auras = mods.raid, mods.party, mods.auras
    out.containers = {
        raid1 = containerInfo(raid and raid.buttons and raid.buttons[1] and raid.buttons[1].auras),
        raid40 = containerInfo(raid and raid.buttons and raid.buttons[40] and raid.buttons[40].auras),
        party1 = containerInfo(party and party.frames and party.frames[1] and party.frames[1].auras),
        targetDebuffs = containerInfo(auras and auras.attached and auras.attached.targetDebuffs),
        player = containerInfo(auras and auras.attached and auras.attached.player),
    }

    out.walkedKB = walked
    out.rest = out.after - walked
    collectgarbage("collect")

    SuuUIProbe = SuuUIProbe or {}
    SuuUIProbe.memory = out
    ns.Print(("Memory probe: SuuUI %.1f MB (%.1f MB after collecting garbage); probe data ~%.1f MB, saved settings ~%.1f MB, data ~%.1f MB, modules ~%.1f MB. /reload to save it.")
        :format(out.before / 1024, out.after / 1024, out.probeKB / 1024, out.dbKB / 1024, out.nsKB / 1024, out.modulesKB / 1024))
end
