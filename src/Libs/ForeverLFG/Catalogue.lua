-- Libs/ForeverLFG/Catalogue.lua
-- What a group can be for. The table below knows no language: stable keys,
-- kinds, the tool's activity IDs (probed on Forever, 2026-10-14: they don't
-- change with the client's language) and sizes. Names and level ranges come
-- from the tool at run time (in the client's language); what players type
-- besides the names (abbreviations, nicknames) comes from the language
-- modules (Lang/*). Activities the tool offers that aren't below (raids at
-- higher levels, new content) join as "tool:<id>" with the tool's name.
--
--   LFG.Catalogue.Get(key)            -- the activity
--   LFG.Catalogue.ForTool(activityID) -- the key for a tool activity
--   LFG.Catalogue.All(kind)           -- every activity (of a kind)
--   LFG.Catalogue.Expand(key)         -- an umbrella ("dungeon:sm") as its parts
--   LFG.Catalogue.ReadTool()          -- names, levels, new activities from the tool

local _, ns = ...
local LFG = ns.LFG

local C = {}
LFG.Catalogue = C

local byKey, byTool = {}, {}

local function add(key, kind, tool, size, extra)
    local a = { key = key, kind = kind, toolActivity = tool, size = size }
    for k, v in pairs(extra or {}) do a[k] = v end
    byKey[key] = a
    if tool then byTool[tool] = key end
    return a
end

-- Dungeons (category 2 on Forever), the tool's IDs
local DUNGEONS = {
    { "rfc", 798 }, { "wc", 796 }, { "dm", 799 }, { "sfk", 800 }, { "bfd", 801 }, { "stocks" },
    { "gnomer", 803 }, { "rfk", 804 }, { "smgy", 805 }, { "smlib", 829 }, { "smarm", 827 }, { "smcath", 828 },
    { "rfd", 806 }, { "ulda", 807 }, { "zf", 808 }, { "mara", 809 }, { "st", 810 }, { "brd", 811 },
    { "lbrs", 812 }, { "ubrs", 837, 10 }, { "dme", 813 }, { "dmw", 814 }, { "dmn", 815 },
    { "stratlive", 816 }, { "stratud", 1603 }, { "scholo", 797 },
    -- Forever's own
    { "excavation", 1981 }, { "lordaeron", 1982 }, { "dalaran", 1983 }, { "thanes", 1984 },
}
for _, d in ipairs(DUNGEONS) do add("dungeon:" .. d[1], "dungeon", d[2], d[3] or 5) end

-- Umbrellas: a word that means any of several ("SM", "Strat", "DM" for Dire Maul)
local UMBRELLAS = {
    ["dungeon:sm"] = { "dungeon:smgy", "dungeon:smlib", "dungeon:smarm", "dungeon:smcath" },
    ["dungeon:strat"] = { "dungeon:stratlive", "dungeon:stratud" },
    ["dungeon:diremaul"] = { "dungeon:dme", "dungeon:dmw", "dungeon:dmn" },
    ["boss:dragons"] = { "boss:ysondre", "boss:lethon", "boss:emeriss", "boss:taerar" },
}
for key, parts in pairs(UMBRELLAS) do add(key, key:match("^(%a+)"), nil, nil, { parts = parts }) end

-- Raids (no tool category for them at low levels yet)
for _, r in ipairs({ { "mc", 40, 60 }, { "ony", 40, 60 }, { "bwl", 40, 60 }, { "zg", 20, 60 }, { "aq20", 20, 60 },
                     { "aq40", 40, 60 }, { "naxx", 40, 60 } }) do
    add("raid:" .. r[1], "raid", nil, r[2], { level = { r[3], r[3] } })
end

-- World bosses
for _, b in ipairs({ "azuregos", "kazzak", "ysondre", "lethon", "emeriss", "taerar" }) do
    add("boss:" .. b, "boss", nil, 40, { level = { 60, 60 } })
end

-- Zones (Quests & Zones, category 116), the tool's IDs
local ZONES = {
    elwynn = 853, westfall = 854, duskwood = 855, dunmorogh = 856, lochmodan = 857, wetlands = 858,
    stranglethorn = 859, blastedlands = 860, swampofsorrows = 861, redridge = 862, burningsteppes = 863,
    searinggorge = 864, badlands = 865, arathi = 866, hillsbrad = 867, hinterlands = 868,
    westernplaguelands = 869, easternplaguelands = 870, tirisfal = 871, silverpine = 872, alterac = 873,
    durotar = 874, mulgore = 875, barrens = 876, stonetalon = 877, thousandneedles = 878, desolace = 879,
    feralas = 880, dustwallow = 881, tanaris = 882, ungoro = 883, silithus = 884, teldrassil = 885,
    darkshore = 886, ashenvale = 887, felwood = 888, azshara = 889, winterspring = 890,
    riverglades = 1989, hyjal = 1991,
}
for slug, id in pairs(ZONES) do add("zone:" .. slug, "zone", id, nil) end

add("custom", "custom", 1064, nil)

--------------------------------------------------------------------------------

function C.Get(key) return byKey[key] end
function C.ForTool(activityID) return byTool[activityID] end

function C.All(kind)
    local out = {}
    for _, a in pairs(byKey) do
        if (not kind or a.kind == kind) and not a.parts then out[#out + 1] = a end
    end
    table.sort(out, function(x, y) return x.key < y.key end)
    return out
end

function C.Expand(key)
    local a = byKey[key]
    if a and a.parts then return a.parts end
    return { key }
end

-- The tool's categories as kinds; anything new by its size.
local CATEGORY_KIND = { [2] = "dungeon", [116] = "zone", [120] = "custom" }

-- From the tool: each activity's name (client language), its level range,
-- its category; new activities join. Names go to the parser as words.
function C.ReadTool()
    local lfg = C_LFGList
    if not (lfg and lfg.GetAvailableCategories) then return end
    local okCats, cats = pcall(lfg.GetAvailableCategories)
    for _, cat in ipairs(okCats and cats or {}) do
        local acts, seen = {}, {}
        local okG, groups = pcall(lfg.GetAvailableActivityGroups, cat)
        for _, g in ipairs(okG and groups or {}) do
            local okA, ga = pcall(lfg.GetAvailableActivities, cat, g)
            for _, id in ipairs(okA and ga or {}) do if not seen[id] then seen[id] = true; acts[#acts + 1] = id end end
        end
        local okA, all = pcall(lfg.GetAvailableActivities, cat, nil)
        for _, id in ipairs(okA and all or {}) do if not seen[id] then seen[id] = true; acts[#acts + 1] = id end end
        for _, id in ipairs(acts) do
            local okT, t = pcall(lfg.GetActivityInfoTable, id)
            if okT and type(t) == "table" then
                local key = byTool[id]
                if not key then
                    local kind = CATEGORY_KIND[cat] or ((t.maxNumPlayers or 0) > 5 and "raid" or "other")
                    key = "tool:" .. id
                    add(key, kind, id, t.maxNumPlayers ~= 0 and t.maxNumPlayers or nil)
                end
                local a = byKey[key]
                a.name = t.fullName
                a.category = cat
                a.toolGroup = t.groupFinderActivityGroupID
                if (t.maxLevelSuggestion or 0) > 0 then a.level = { t.minLevelSuggestion or 0, t.maxLevelSuggestion } end
                if LFG.Parser and t.fullName then LFG.Parser.AddName(key, t.fullName) end
                if LFG.Parser and t.shortName and t.shortName ~= t.fullName then LFG.Parser.AddName(key, t.shortName) end
            end
        end
    end
    C.read = true
end
