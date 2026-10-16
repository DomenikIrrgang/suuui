-- Units/WorldMap.lua
-- The world map's pins (step 3.5, stage 2; design components MapPin and
-- WorldMap): what the game doesn't draw on Forever's map (probed
-- 2026-10-15: no flight masters, no dungeon entrances, no quests to pick
-- up), and one filter menu for them, "Map filters" in the map's header:
--   Quests     quest objectives (the game's own, its questPOI setting),
--              quests to pick up, repeatable and daily, trivial quests
--   Places     dungeon and raid entrances, battleground entrances, flight
--              masters (the game's taxi nodes), campfires you found (the
--              Campfire module remembers them)
--   Services   innkeepers, repair (on); vendors, stable masters,
--              battlemasters, guild masters, tabard designers, spirit
--              healers (off)
--   Trading    mailboxes (on); auctioneers, bankers (off)
--   Trainers   your class trainer (on); profession trainers, weapon
--              masters, riding and pet trainers (off)
--   Rares and treasures
-- Quests to pick up, entrances, services, rares and chests come from
-- SuuUI's generated data (SuuUI.QuestStarts, SuuUI.MapPlaces).
-- Where pins crowd: services are small and drawn under the rest; pins of
-- one kind closer than 32 px merge into one with a count (its hover lists
-- them, a click zooms to it); merged and small pins that still overlap are
-- pushed apart; entrances, flight masters and campfires never move.
-- The pins sit on the map's canvas through a data provider and keep their
-- size at every zoom. A built-in module written against the public API only.

local DEFAULT_FILTERS = {
    quests = { "objectives", "available", "repeatable", "items" },
    places = { "unexplored", "dungeons", "battlegrounds", "flight", "campfires" },
    services = { "inn", "repair" },
    trading = { "mail" },
    trainers = { "class" },
    rares = { "rares" },
    marks = { "yours", "shared" },
}

local M = SuuUI.RegisterModule({
    id = "worldmap",
    name = "World map pins",
    description = "Pins on the world map: quests to pick up, entrances, flight masters, services, rares and treasures.",
    api = "0.14",
    defaults = { filters = DEFAULT_FILTERS, pinAlpha = 100, enlargedSize = 80 },
})

local UI, T = SuuUI.UI, SuuUI.Tokens
local S = T.space

local isSecret = issecretvalue or function() return false end
local function plain(v) return v ~= nil and not isSecret(v) end

local MERGE_RADIUS = 38 -- px on screen (the design's 32 for 22 px pins, grown with them)
local MERGE_RADIUS_CLOSEST = 6 -- zoomed all the way in: only pins on one spot (Blackrock Mountain's doors)
local CLOSEST_GROW = 1.2 -- zoomed all the way in, pins are this much larger
local PIN, PIN_SMALL = 26, 21 -- UI.MapPin's sizes
local DISC = "Interface\\AddOns\\SuuUI\\Media\\Textures\\CircleFill.tga"

--------------------------------------------------------------------------------
-- The filter menu
--------------------------------------------------------------------------------

local GROUPS = {
    { key = "quests", label = "Quests", kind = "toggles", options = {
        { value = "objectives", label = "Quest objectives" },
        { value = "available", label = "Quests to pick up" },
        { value = "repeatable", label = "Repeatable and daily" },
        { value = "items", label = "Quests from items" },
        { value = "trivial", label = "Trivial quests" },
    } },
    { key = "places", label = "Places", kind = "toggles", options = {
        { value = "unexplored", label = "Unexplored areas" },
        { value = "dungeons", label = "Dungeon and raid entrances" },
        { value = "battlegrounds", label = "Battleground entrances" },
        { value = "flight", label = "Flight masters" },
        { value = "campfires", label = "Campfires you found" },
    } },
    { key = "services", label = "Services", kind = "toggles", column = true, options = {
        { value = "inn", label = "Innkeepers" },
        { value = "repair", label = "Repair" },
        { value = "goods", label = "General goods" },
        { value = "food", label = "Food and drink" },
        { value = "vendor", label = "Other vendors" },
        { value = "stable", label = "Stable masters" },
        { value = "battlemaster", label = "Battlemasters" },
        { value = "guild", label = "Guild masters" },
        { value = "tabard", label = "Tabard designers" },
        { value = "spirit", label = "Spirit healers" },
    } },
    { key = "trading", label = "Trading", kind = "toggles", options = {
        { value = "auction", label = "Auctioneers" },
        { value = "mail", label = "Mailboxes" },
        { value = "bank", label = "Bankers" },
    } },
    { key = "trainers", label = "Trainers", kind = "toggles", column = true, options = {
        { value = "class", label = "Your class trainer" },
        { value = "professions", label = "Profession trainers" },
        { value = "weapon", label = "Weapon masters" },
        { value = "riding", label = "Riding and pet trainers" },
    } },
    { key = "rares", label = "Rares and treasures", kind = "toggles", options = {
        { value = "rares", label = "Rares" },
        { value = "treasures", label = "Treasure chests" },
    } },
    { key = "marks", label = "Marks", kind = "toggles", options = {
        { value = "yours", label = "Your marks" },
        { value = "shared", label = "Shared marks" },
    } },
}

-- The saved filters in the current groups: each saved choice goes to the
-- group that has it now (mailboxes, bankers and auctioneers moved from
-- Services to Trading, the trainers to Trainers), so an earlier layout's
-- choices carry over; new options start off.
local LEGACY = { classTrainer = { "trainers", "class" }, trainers = { "trainers", "professions" } }
local FILTERS_VERSION = 4 -- 2: quests from items, 3: unexplored areas, 4: marks (each on for everyone once)
function M:Saved()
    local saved = self:Get("filters") or DEFAULT_FILTERS
    local owner = {}
    for _, g in ipairs(GROUPS) do for _, o in ipairs(g.options) do owner[o.value] = g.key end end
    local out = {}
    for _, g in ipairs(GROUPS) do out[g.key] = {} end
    for key, list in pairs(saved) do
        for _, v in ipairs(type(list) == "table" and list or {}) do
            local legacy = key == "services" and LEGACY[v]
            local group, value = legacy and legacy[1] or owner[v], legacy and legacy[2] or v
            if group then
                local has = false
                for _, x in ipairs(out[group]) do if x == value then has = true end end
                if not has then table.insert(out[group], value) end
            end
        end
    end
    for _, new in ipairs({ { 2, "quests", "items" }, { 3, "places", "unexplored" }, { 4, "marks", "yours" }, { 4, "marks", "shared" } }) do
        if (saved.v or 1) < new[1] then
            local has = false
            for _, v in ipairs(out[new[2]]) do if v == new[3] then has = true end end
            if not has then table.insert(out[new[2]], new[3]) end
        end
    end
    return out
end

-- on[group][value] from the saved filters
function M:Layers()
    local saved = self:Saved()
    local on = {}
    for _, g in ipairs(GROUPS) do
        local set = {}
        for _, v in ipairs(saved[g.key] or {}) do set[v] = true end
        on[g.key] = set
    end
    return on
end

-- The Marks filters, for the marks module's minimap too: { yours, shared }.
function M:MarksShown()
    return self:Layers().marks or {}
end

-- the game's quest objectives follow its own setting
local function objectivesShown()
    local ok, v = pcall(GetCVarBool, "questPOI")
    return not ok or v
end

function M:MenuValue()
    local saved = self:Saved()
    local value = {}
    for _, g in ipairs(GROUPS) do
        local list = {}
        for _, v in ipairs(saved[g.key] or {}) do
            if not (g.key == "quests" and v == "objectives") then list[#list + 1] = v end
        end
        if g.key == "quests" and objectivesShown() then table.insert(list, 1, "objectives") end
        value[g.key] = list
    end
    return value
end

function M:OnFilters(value)
    local wantObjectives = false
    for _, v in ipairs(value.quests or {}) do if v == "objectives" then wantObjectives = true end end
    if wantObjectives ~= objectivesShown() and not InCombatLockdown() then
        pcall(SetCVar, "questPOI", wantObjectives and "1" or "0")
    end
    value.v = FILTERS_VERSION
    self:Set("filters", value)
    self:Refresh()
end

--------------------------------------------------------------------------------
-- What's on a map
--------------------------------------------------------------------------------

local SERVICE = {
    -- service key → filter, glyph, glyph colour
    spirit = { "spirit", "spirit", "arcane" },
    inn = { "inn", "inn" },
    bank = { "bank", "bank" },
    auction = { "auction", "gavel" },
    battlemaster = { "battlemaster", "flag" },
    guild = { "guild", "scroll" },
    tabard = { "tabard", "tabard" },
    stable = { "stable", "paw" },
    repair = { "repair", "anvil" },
    food = { "food", "mug" },
    goods = { "goods", "bag" },
    vendor = { "vendor", "coin" },
}
local SERVICE_NAMES = {
    spirit = "Spirit healer", inn = "Innkeeper", bank = "Banker", auction = "Auctioneer", battlemaster = "Battlemaster",
    guild = "Guild master", tabard = "Tabard designer", stable = "Stable master", repair = "Repair", food = "Food and drink",
    goods = "General goods", vendor = "Vendor", mail = "Mailbox", classTrainer = "Class trainer", trainer = "Trainer",
}
-- (drawn after the game's own profession icons, which players know)
local PROFESSION_GLYPH = {
    alchemy = "profAlchemy", blacksmithing = "profBlacksmithing", enchanting = "profEnchanting", engineering = "gear",
    herbalism = "profHerbalism", leatherworking = "profLeatherworking", mining = "profMining", skinning = "hide",
    tailoring = "profTailoring", cooking = "profCooking", firstAid = "profFirstAid", fishing = "profFishing",
    weapon = "sword", riding = "book", pet = "book", other = "book",
}
local PROFESSION_NAMES = {
    alchemy = "Alchemy trainer", blacksmithing = "Blacksmithing trainer", enchanting = "Enchanting trainer",
    engineering = "Engineering trainer", herbalism = "Herbalism trainer", leatherworking = "Leatherworking trainer",
    mining = "Mining trainer", skinning = "Skinning trainer", tailoring = "Tailoring trainer", cooking = "Cooking trainer",
    firstAid = "First aid trainer", fishing = "Fishing trainer", weapon = "Weapon master",
    riding = "Riding instructor", pet = "Pet trainer", other = "Trainer",
}
local QUEST_RANK = { difficult = 1, standard = 2, ["very-difficult"] = 3, impossible = 4, trivial = 5 }

-- The level at and below which a quest is grey for you, as the original
-- game had it (Forever's own colour keeps a level 3 quest green for a level
-- 15 character; found in game, Mulgore).
local function grayLevel(p)
    if p <= 5 then return 0 end
    if p <= 39 then return p - 5 - math.floor(p / 10) end
    if p <= 59 then return p - 1 - math.floor(p / 5) end
    return p - 9
end

-- A quest's difficulty for you by the original game's rule: red 5 levels
-- above, orange 3, yellow within 2, green above the grey level, then grey.
-- (Forever's own colour treats its quests as scaling and calls a level 3
-- quest yellow for a level 15 character; found in game, Mulgore.)
local function questDifficulty(level, mine)
    local diff = level - mine
    if diff >= 5 then return "impossible" end
    if diff >= 3 then return "very-difficult" end
    if diff >= -2 then return "difficult" end
    if level > grayLevel(mine) then return "standard" end
    return "trivial"
end

-- who you are, for what you can pick up and who serves you
function M:Player()
    local level = UnitLevel("player")
    local _, _, race = UnitRace("player")
    local _, class, classID = UnitClass("player")
    local faction = UnitFactionGroup("player")
    return {
        level = plain(level) and level or 1,
        raceBit = plain(race) and race and 2 ^ (race - 1) or 0,
        classBit = plain(classID) and classID and 2 ^ (classID - 1) or 0,
        class = plain(class) and class or nil,
        faction = faction == "Horde" and "H" or faction == "Alliance" and "A" or nil,
    }
end

local function maskHas(mask, bit)
    if not mask or mask == 0 or bit == 0 then return true end
    return mask % (bit * 2) >= bit
end

-- the quests you've turned in, once per refresh
local function completedSet()
    local set = {}
    local ok, list = pcall(C_QuestLog.GetAllCompletedQuestIDs)
    if ok and type(list) == "table" then for _, id in ipairs(list) do set[id] = true end end
    return set
end
local function onQuest(id)
    if C_QuestLog.IsOnQuest then
        local ok, v = pcall(C_QuestLog.IsOnQuest, id)
        if ok then return v end
    end
    local ok, i = pcall(C_QuestLog.GetLogIndexForQuestID, id)
    return ok and i ~= nil
end

-- Your profession skills by skill line (cooking 185, skinning 393, ...).
local function skillLines()
    local out = {}
    if not (GetProfessions and GetProfessionInfo) then return out end
    local ok, a, b, c, d, e, f = pcall(GetProfessions)
    if not ok then return out end
    for _, index in pairs({ a, b, c, d, e, f }) do
        local okInfo, _, _, rank, _, _, _, line = pcall(GetProfessionInfo, index)
        if okInfo and plain(line) and line and plain(rank) then out[line] = rank end
    end
    return out
end

-- Your standing with a faction (0 is the start of Neutral, 3000 Friendly,
-- as the quest data counts it); 0 for one you haven't met.
local function standing(me, faction)
    me.reps = me.reps or {}
    if me.reps[faction] then return me.reps[faction] end
    local value = 0
    if C_Reputation and C_Reputation.GetFactionDataByID then
        local ok, data = pcall(C_Reputation.GetFactionDataByID, faction)
        if ok and type(data) == "table" and plain(data.currentStanding) then value = data.currentStanding end
    elseif GetFactionInfoByID then
        local ok, _, _, _, _, _, bar = pcall(GetFactionInfoByID, faction)
        if ok and plain(bar) and bar then value = bar end
    end
    me.reps[faction] = value
    return value
end

-- Whether you can pick a quest up now: "available", "repeatable" or nil,
-- and its difficulty. Besides level, race and class: the quests before it
-- (all of a group, one of a choice), none it excludes, not past it in its
-- chain, its parent quest in your log, a breadcrumb only while the quest it
-- leads to isn't taken, the profession skill and reputation it asks, and
-- no event quests (whether an event runs can't be read).
-- Is an event on? A quest of an event shows only while it is. Holidays
-- from the game's calendar, by Forever's holiday IDs (its Holidays table;
-- the calendar's eventIDs are those): read at login and whenever the
-- calendar updates. The Darkmoon Faire is two holidays, one per site: its
-- quests show on that site's map only. One-off server events (the War
-- Effort, the Scourge Invasion) aren't running, and nothing in the game
-- would say when they are: never on.
local HOLIDAYS = {
    [141] = "winterVeil", [1879] = "winterVeil", [324] = "hallowsEnd", [327] = "lunarFestival", [341] = "midsummer",
    [335] = "loveIsInTheAir", [321] = "harvestFestival", [201] = "childrensWeek", [181] = "noblegarden",
    [263] = "darkmoonFaire", [264] = "darkmoonFaire",
}
local DARKMOON_SITE = { [263] = 1429, [264] = 1412 } -- Elwynn Forest, Mulgore
local events = { on = {} }

local function stamp(t)
    return t and (((t.year * 100 + t.month) * 100 + t.monthDay) * 100 + t.hour) * 100 + t.minute or 0
end
-- today's holidays; false while the calendar shows another month (you're
-- looking through it): what was read stays
local function readCalendar()
    local cal = C_Calendar
    local now = C_DateAndTime and C_DateAndTime.GetCurrentCalendarTime and C_DateAndTime.GetCurrentCalendarTime()
    if not (cal and cal.GetMonthInfo and cal.GetNumDayEvents and cal.GetDayEvent and now) then return false end
    local month = cal.GetMonthInfo(0)
    if not (month and month.month == now.month and month.year == now.year) then return false end
    local on, site = {}, nil
    local t = stamp(now)
    for i = 1, cal.GetNumDayEvents(0, now.monthDay) or 0 do
        local e = cal.GetDayEvent(0, now.monthDay, i)
        local key = e and e.calendarType == "HOLIDAY" and HOLIDAYS[e.eventID]
        if key and stamp(e.startTime) <= t and t < stamp(e.endTime) then
            on[key] = true
            site = DARKMOON_SITE[e.eventID] or site
        end
    end
    events.on, events.darkmoon = on, site
    return true
end

local function eventOn(key, mapID)
    if not events.on[key] then return false end
    if key == "darkmoonFaire" then return mapID == events.darkmoon end
    return true
end

local function questState(q, id, me, done)
    if onQuest(id) then return nil end
    local flags = q[10] or 0
    local repeatable = flags % 2 == 1
    if done[id] and not repeatable then return nil end
    -- an event's quest by its event; one needing an event we can't tell: never
    if q[16] then
        if not eventOn(q[16], me.mapID) then return nil end
    elseif flags % 4 >= 2 then
        return nil
    end
    if q[9] and (done[q[9]] or onQuest(q[9])) then return nil end
    if q[11] and not onQuest(q[11]) then return nil end
    if q[12] and (done[q[12]] or onQuest(q[12])) then return nil end
    if q[13] then
        me.skills = me.skills or skillLines()
        if (me.skills[q[13][1]] or 0) < (q[13][2] or 1) then return nil end
    end
    if q[14] and standing(me, q[14][1]) < q[14][2] then return nil end
    if q[15] and standing(me, q[15][1]) >= q[15][2] then return nil end
    if q[2] and q[2] > me.level then return nil end
    if not maskHas(q[4], me.raceBit) or not maskHas(q[5], me.classBit) then return nil end
    for _, pre in ipairs(q[6] or {}) do if not done[pre] then return nil end end
    if q[7] then
        local any = false
        for _, pre in ipairs(q[7]) do if done[pre] then any = true break end end
        if not any then return nil end
    end
    for _, other in ipairs(q[8] or {}) do if done[other] or onQuest(other) then return nil end end
    local level = (q[3] and q[3] > 0) and q[3] or me.level
    local difficulty = questDifficulty(level, me.level)
    -- far above you (the data often lacks the level a quest asks): the
    -- game wouldn't offer it yet
    if difficulty == "impossible" then return nil end
    return repeatable and "repeatable" or "available", difficulty, level
end

-- every pin the map would show, before merging: { x, y (0-1), key (what
-- merges with what, nil: never), small, pin (MapPin data), tip (tooltip
-- lines), rank (a merged quest pin takes the best) }
-- What an NPC should offer you now, by the map's own checks (for /suu probe
-- givers, which compares it with what the NPC does offer): every quest the
-- data has it giving, with the state the map would show it in (nil: the
-- map wouldn't), whether you're on it or have done it.
function M:QuestsFor(npcID)
    local starts = SuuUI.QuestStarts and SuuUI.QuestStarts() or {}
    local me, done = self:Player(), completedSet()
    local out, seen = {}, {}
    for mapID, rows in pairs(starts.maps or {}) do
        for _, row in ipairs(rows) do
            if row[3] == npcID then
                me.mapID = mapID
                for i = 4, #row do
                    local id = row[i]
                    if not seen[id] then
                        seen[id] = true
                        local q = starts.quests and starts.quests[id]
                        local state, difficulty
                        if q then state, difficulty = questState(q, id, me, done) end
                        out[#out + 1] = { id = id, name = q and q[1], state = state, difficulty = difficulty,
                                          onQuest = onQuest(id) and true or false, done = done[id] or false }
                    end
                end
            end
        end
    end
    return out, done
end

function M:Collect(mapID)
    local items = {}
    local on = self:Layers()
    local me = self:Player()
    me.mapID = mapID
    local starts = SuuUI.QuestStarts and SuuUI.QuestStarts() or {}
    local info = C_Map.GetMapInfo(mapID)
    local mapName = info and info.name
    local places = SuuUI.MapPlaces and SuuUI.MapPlaces() or {}

    -- quests to pick up: a pin per giver's place
    if on.quests.available or on.quests.repeatable then
        local done = completedSet()
        for _, row in ipairs(starts.maps and starts.maps[mapID] or {}) do
            local best, list, ids = nil, {}, {}
            local giver = starts.givers and starts.givers[row[3]]
            for i = 4, #row do
                local id = row[i]
                local q = starts.quests[id]
                local state, difficulty, level
                if q then state, difficulty, level = questState(q, id, me, done) end
                if state and (on.quests[state]) and (difficulty ~= "trivial" or on.quests.trivial) then
                    list[#list + 1] = { name = q[1], level = level, difficulty = difficulty, state = state }
                    ids[#ids + 1] = id
                    local rank = QUEST_RANK[difficulty] or 9
                    if not best or rank < best.rank then best = { rank = rank, difficulty = difficulty, state = state } end
                end
            end
            if best then
                local repeatable = best.state == "repeatable"
                local lines = {}
                for i, q in ipairs(list) do
                    if i > 1 then lines[#lines + 1] = { q.name .. "  |cff" .. T.color["ink-muted"].hex .. "Level " .. q.level .. "|r" } end
                end
                -- who gives it, after its level ("Level 15 · Gorrik")
                local from = giver and (" · " .. giver) or ""
                -- one who walks: his route, drawn while you hover the pin
                local route = starts.routes and starts.routes[row[3]] and starts.routes[row[3]][mapID]
                if route then
                    table.insert(lines, 1, { "|cff" .. T.color["ink-muted"].hex .. "Walks a route" .. (mapName and (" through " .. mapName) or "")
                        .. ", shown on the map|r" })
                end
                items[#items + 1] = {
                    x = row[1] / 100, y = row[2] / 100, key = repeatable and "repeatable" or "available", rank = best.rank,
                    pin = { char = "!", color = repeatable and "mana" or ("quest-" .. best.difficulty), edge = repeatable and "mana" or nil },
                    name = list[1].name, detail = (repeatable and "Repeatable · " or "") .. "Level " .. list[1].level .. from,
                    more = lines, difficulty = best.difficulty, repeatable = repeatable, uid = "g" .. row[3], quests = ids,
                    route = route,
                }
            end
        end
    end

    -- quests started by an item: where the mobs that drop it live
    if on.quests.items then
        local done = completedSet()
        local muted = "|cff" .. T.color["ink-muted"].hex
        for _, row in ipairs(starts.drops and starts.drops[mapID] or {}) do
            local source = starts.givers and starts.givers[row[3]] or "?"
            local item = starts.items and starts.items[row[4]] or "an item"
            local best, list, ids = nil, {}, {}
            for i = 5, #row do
                local id = row[i]
                local q = starts.quests[id]
                local state, difficulty, level
                if q then state, difficulty, level = questState(q, id, me, done) end
                if state and (difficulty ~= "trivial" or on.quests.trivial) then
                    list[#list + 1] = { name = q[1], level = level }
                    ids[#ids + 1] = id
                    local rank = QUEST_RANK[difficulty] or 9
                    if not best or rank < best.rank then best = { rank = rank, difficulty = difficulty } end
                end
            end
            if best then
                local lines = { { "Starts from " .. item }, { muted .. (row[3] < 0 and "Found in " or "Dropped by ") .. source .. "|r" } }
                for i = 2, #list do lines[#lines + 1] = { list[i].name .. "  " .. muted .. "Level " .. list[i].level .. "|r" } end
                items[#items + 1] = {
                    x = row[1] / 100, y = row[2] / 100, key = "itemQuest", rank = best.rank,
                    pin = { char = "!", color = "quest-" .. best.difficulty, edge = "gilt" },
                    name = list[1].name, detail = "Level " .. list[1].level,
                    listDetail = "Level " .. list[1].level .. " · " .. item .. " · " .. source,
                    more = lines, difficulty = best.difficulty, uid = "d" .. row[3] .. ":" .. row[4], kindName = "Quests from items", quests = ids,
                }
            end
        end
    end

    -- entrances, with their recommended levels (the group finder's) and
    -- the wings' own; one whose door isn't known yet is in its area's middle
    local levels = SuuUI.InstanceLevels()
    local function range(lo, hi) return lo == hi and ("level " .. lo) or ("level " .. lo .. "–" .. hi) end
    local muted = "|cff" .. T.color["ink-muted"].hex
    for _, e in ipairs(starts.entrances and starts.entrances[mapID] or {}) do
        local kind, faction = e[4], e[5]
        local show = (kind == "battleground" and on.places.battlegrounds) or (kind ~= "battleground" and on.places.dungeons)
        if show and (not faction or faction == me.faction) then
            local detail = kind == "raid" and "Raid" or kind == "battleground" and "Battleground" or "Dungeon"
            local lv = levels[kind] and levels[kind][e[3]]
            local lines = {}
            if lv then
                detail = detail .. " · " .. range(lv[1], lv[2])
                for i = 3, #lv do lines[#lines + 1] = { lv[i][1] .. "  " .. muted .. range(lv[i][2], lv[i][3]) .. "|r" } end
            end
            if e[6] then lines[#lines + 1] = { muted .. "Approximate: its door isn't known yet|r" } end
            -- entrances on one spot merge (Blackrock Mountain's four stacked,
            -- only the top one's card to read); one place's doors count once
            items[#items + 1] = { x = e[1] / 100, y = e[2] / 100, fixed = true, uid = "e" .. e[3],
                key = kind == "battleground" and "battleground" or "entrance",
                kindName = kind == "battleground" and "Battlegrounds" or "Entrances",
                pin = kind == "battleground" and { glyph = "swords" }
                    or { glyph = "swirl", spin = true, ring = kind == "raid" and "gilt" or nil },
                name = e[3], detail = detail, more = #lines > 0 and lines or nil }
        end
    end

    -- flight masters: the game's taxi nodes for this map (yours and neutral)
    if on.places.flight and C_TaxiMap and C_TaxiMap.GetTaxiNodesForMap then
        local ok, nodes = pcall(C_TaxiMap.GetTaxiNodesForMap, mapID)
        local mine = me.faction == "H" and 1 or me.faction == "A" and 2 or -1
        for _, n in ipairs(ok and type(nodes) == "table" and nodes or {}) do
            local x, y
            if n.position and n.position.GetXY then x, y = n.position:GetXY() end
            if plain(x) and plain(y) and x >= 0 and x <= 1 and y >= 0 and y <= 1 and (n.faction == 0 or n.faction == mine) then
                items[#items + 1] = { x = x, y = y, fixed = true,
                    pin = { glyph = "wing", color = n.isUndiscovered and "ink-muted" or "gilt-text" },
                    name = n.name, detail = n.isUndiscovered and "Flight master · not yet found" or "Flight master" }
            end
        end
    end

    -- campfires you found (the Campfire module's memory)
    if on.places.campfires then
        local camp = SuuUI.GetModule("campsite")
        local fires = camp and camp:IsEnabled() and camp:CharData().fires or {}
        for _, f in ipairs(fires) do
            if f.map == mapID then
                items[#items + 1] = { x = f.x, y = f.y, key = "campfire", fixed = true,
                    pin = { glyph = "campfire", color = "ember-text" }, name = "Campfire", detail = "One you found" }
            end
        end
    end

    -- services: one pin per NPC, the first of its services whose filter is on
    local npcs = places.npcs or {}
    local svc = places.services and places.services[mapID] or {}
    for i = 1, #svc, 3 do
        local id = svc[i + 2]
        local n = npcs[id]
        -- (a holiday's NPC only while it's on)
        if n and n[4] and (n[3] and me.faction and n[3]:find(me.faction, 1, true)) and (not n[8] or eventOn(n[8], mapID)) then
            for kind in n[4]:gmatch("[^,]+") do
                local item
                local class = kind:match("^class:(.+)$")
                local prof = kind:match("^trainer:(.+)$")
                if class then
                    if class == me.class and on.trainers.class then
                        local token = "class-" .. class:lower()
                        item = { key = "classTrainer", pin = { glyph = "book", color = token, edge = token, small = true },
                                 kindName = SERVICE_NAMES.classTrainer }
                    elseif class ~= me.class then
                        item = false -- another class's trainer: never
                    end
                elseif prof then
                    local layer = (prof == "weapon" and "weapon") or ((prof == "riding" or prof == "pet") and "riding") or "professions"
                    if on.trainers[layer] then
                        item = { key = "trainer:" .. prof, pin = { glyph = PROFESSION_GLYPH[prof] or "book", small = true },
                                 kindName = PROFESSION_NAMES[prof] or "Trainer" }
                    end
                else
                    local s = SERVICE[kind]
                    local group = (kind == "bank" or kind == "auction") and on.trading or on.services
                    if s and group[s[1]] then
                        item = { key = kind, pin = { glyph = s[2], color = s[3], small = true }, kindName = SERVICE_NAMES[kind] }
                    end
                end
                if item == false then break end
                if item then
                    item.x, item.y, item.small, item.uid = svc[i] / 100, svc[i + 1] / 100, true, "n" .. id
                    item.name, item.detail = n[1], n[2]
                    -- one who walks his round (Zixil, Kira Songshine): his
                    -- route while you hover, like a walking rare's
                    local route = places.routes and places.routes[id] and places.routes[id][mapID]
                    if route then
                        item.route = route
                        item.more = { { "|cff" .. T.color["ink-muted"].hex .. "Walks a route" .. (mapName and (" through " .. mapName) or "")
                            .. ", shown on the map|r" } }
                    end
                    items[#items + 1] = item
                    break
                end
            end
        end
    end
    if on.trading.mail then
        local mail = places.mailboxes and places.mailboxes[mapID] or {}
        for i = 1, #mail, 2 do
            items[#items + 1] = { x = mail[i] / 100, y = mail[i + 1] / 100, key = "mail", small = true,
                pin = { glyph = "mail", small = true }, name = "Mailbox", kindName = "Mailbox" }
        end
    end

    -- rares and treasures
    if on.rares.rares then
        local rares = places.rares and places.rares[mapID] or {}
        -- how many spots each spawns at here (hovering one rings them all)
        local spots = {}
        for i = 3, #rares, 3 do spots[rares[i]] = (spots[rares[i]] or 0) + 1 end
        local muted = "|cff" .. T.color["ink-muted"].hex
        for i = 1, #rares, 3 do
            local id = rares[i + 2]
            local n = npcs[id]
            if n and (not n[8] or eventOn(n[8], mapID)) then
                local elite = n[5] == "rareElite"
                local level = n[6] and (n[7] and n[7] ~= n[6] and (n[6] .. "-" .. n[7]) or tostring(n[6])) or nil
                local route = places.routes and places.routes[id] and places.routes[id][mapID]
                local lines = {}
                if spots[id] > 1 then lines[#lines + 1] = { muted .. "Spawns at one of " .. spots[id] .. " spots, ringed on the map|r" } end
                if route then
                    lines[#lines + 1] = { muted .. "Walks a route" .. (mapName and (" through " .. mapName) or "") .. ", shown on the map|r" }
                end
                items[#items + 1] = { x = rares[i] / 100, y = rares[i + 1] / 100, key = elite and "rareElite" or "rare",
                    pin = elite and { glyph = "skull", color = "gilt-text", edge = "gilt", ring = "gilt" }
                        or { glyph = "skull", color = "ink", edge = "coin-silver" },
                    name = n[1], detail = (elite and "Rare elite" or "Rare") .. (level and (" · level " .. level) or ""),
                    kindName = elite and "Rare elite" or "Rare", uid = "n" .. id, rare = id, route = route,
                    more = #lines > 0 and lines or nil }
            end
        end
    end
    if on.rares.treasures then
        local chests = places.treasures and places.treasures[mapID] or {}
        for i = 1, #chests, 3 do
            items[#items + 1] = { x = chests[i] / 100, y = chests[i + 1] / 100, key = "treasure",
                pin = { glyph = "chest", color = "coin-gold" }, name = chests[i + 2], detail = "Treasure (when it's there)",
                kindName = "Treasure chest" }
        end
    end
    -- your marks and shared ones (the marks module's), on their map and the
    -- maps above it; they keep their spot, and a click opens their card
    local marks = SuuUI.GetModule and SuuUI.GetModule("marks")
    if marks and marks:IsEnabled() and (on.marks.yours or on.marks.shared) then
        local muted = "|cff" .. T.color["ink-muted"].hex
        for _, mark in ipairs(marks:Marks()) do
            if (mark.from and on.marks.shared) or (not mark.from and on.marks.yours) then
                local x, y = marks:PlaceOn(mark, mapID)
                if x then
                    local where = ("%s %.1f, %.1f"):format(marks:MapName(mark.map) or "", mark.x * 100, mark.y * 100)
                    items[#items + 1] = { x = x, y = y, fixed = true, uid = "m" .. mark.id, mark = mark.id,
                        pin = marks:PinLook(mark), name = mark.name ~= "" and mark.name or "Mark", detail = where,
                        kindName = "Marks",
                        more = mark.from and { { muted .. "Shared by " .. mark.from .. "|r" } } or nil }
                end
            end
        end
    end
    return items
end

--------------------------------------------------------------------------------
-- Merging and spreading, in screen pixels at the map's zoom
--------------------------------------------------------------------------------

-- items → groups { x, y (px), items, key, fixed, small }
local function merge(items, w, h, radius)
    local groups = {}
    local r2 = radius * radius
    for _, it in ipairs(items) do
        local px, py = it.x * w, it.y * h
        local into
        if it.key then
            for _, g in ipairs(groups) do
                if g.key == it.key then
                    local dx, dy = g.x - px, g.y - py
                    if dx * dx + dy * dy < r2 then into = g break end
                end
            end
        end
        if into then
            local n = #into.items
            into.x = (into.x * n + px) / (n + 1)
            into.y = (into.y * n + py) / (n + 1)
            into.items[n + 1] = it
            into.fixed = into.fixed and it.fixed
            -- one NPC's (or quest giver's) spawn points count once
            if not (it.uid and into.uids[it.uid]) then into.distinct = into.distinct + 1 end
            if it.uid then into.uids[it.uid] = true end
        else
            groups[#groups + 1] = { x = px, y = py, items = { it }, key = it.key, fixed = it.fixed, small = it.small,
                                    distinct = 1, uids = it.uid and { [it.uid] = true } or {} }
        end
    end
    return groups
end

-- Groups of a kind within the radius join, until none are: a group's
-- middle moves as pins join it, and spreading moves groups too, so one pass
-- can leave neighbours apart (two quest pins beside each other at Camp
-- Taurajo; found in game).
local function mergeGroups(groups, radius)
    local r2 = radius * radius
    local merged = true
    while merged do
        merged = false
        for i = 1, #groups do
            local a = groups[i]
            for j = #groups, i + 1, -1 do
                local b = groups[j]
                if a.key and a.key == b.key then
                    local dx, dy = a.x - b.x, a.y - b.y
                    if dx * dx + dy * dy < r2 then
                        local na, nb = #a.items, #b.items
                        a.x = (a.x * na + b.x * nb) / (na + nb)
                        a.y = (a.y * na + b.y * nb) / (na + nb)
                        for _, it in ipairs(b.items) do
                            a.items[#a.items + 1] = it
                            if not (it.uid and a.uids[it.uid]) then a.distinct = a.distinct + 1 end
                            if it.uid then a.uids[it.uid] = true end
                        end
                        a.fixed = a.fixed and b.fixed
                        table.remove(groups, j)
                        merged = true
                    end
                end
            end
        end
    end
    return groups
end

-- pins still overlapping: the movable ones (small or merged) step apart
local function spread(groups)
    for _ = 1, 4 do
        local moved = false
        for i = 1, #groups do
            local a = groups[i]
            for j = i + 1, #groups do
                local b = groups[j]
                local aMoves = not a.fixed and (a.small or #a.items > 1)
                local bMoves = not b.fixed and (b.small or #b.items > 1)
                if aMoves or bMoves then
                    local need = ((a.small and PIN_SMALL or PIN) + (b.small and PIN_SMALL or PIN)) / 2
                    local dx, dy = b.x - a.x, b.y - a.y
                    local d = math.sqrt(dx * dx + dy * dy)
                    if d < need then
                        if d < 0.01 then dx, dy, d = 1, 0, 1 end
                        local push = (need - d)
                        local ux, uy = dx / d, dy / d
                        if aMoves and bMoves then
                            a.x, a.y = a.x - ux * push / 2, a.y - uy * push / 2
                            b.x, b.y = b.x + ux * push / 2, b.y + uy * push / 2
                        elseif aMoves then
                            a.x, a.y = a.x - ux * push, a.y - uy * push
                        else
                            b.x, b.y = b.x + ux * push, b.y + uy * push
                        end
                        moved = true
                    end
                end
            end
        end
        if not moved then break end
    end
end

--------------------------------------------------------------------------------
-- The pins on the canvas
--------------------------------------------------------------------------------

local function tipFor(g)
    local first = g.items[1]
    if g.distinct == 1 then
        local lines = {}
        if first.more and #first.more > 0 then
            for _, l in ipairs(first.more) do lines[#lines + 1] = l end
        end
        local detail = first.detail
        -- a vendor who also repairs reads "Repair" when its title doesn't say
        if first.kindName and first.small and detail and not detail:lower():find(first.kindName:lower(), 1, true) then
            detail = detail .. " · " .. first.kindName
        elseif first.kindName and first.small and not detail then
            detail = first.kindName
        end
        return { title = first.name, titleColor = first.difficulty and ("quest-" .. first.difficulty) or nil,
                 subtitle = detail, lines = #lines > 0 and lines or nil }
    end
    -- one line per name: the same NPC's spawn points, mailboxes, a chest
    -- kind read once with how many ("Mailbox ×2"; found in game)
    local seen, order = {}, {}
    for _, it in ipairs(g.items) do
        local key = (it.name or "?") .. "\0" .. (it.detail or "")
        if not seen[key] then
            seen[key] = { name = it.name or "?", detail = it.listDetail or it.detail or "", n = 0, uids = {} }
            order[#order + 1] = seen[key]
        end
        -- (one NPC's spawn points once: "Mailbox ×2" is two mailboxes)
        local e = seen[key]
        if not (it.uid and e.uids[it.uid]) then e.n = e.n + 1 end
        if it.uid then e.uids[it.uid] = true end
    end
    -- one line each, the title after the name in muted ink (two columns
    -- overlapped once titles ran long; found in game)
    local muted = "|cff" .. T.color["ink-muted"].hex
    local lines = {}
    for i, e in ipairs(order) do
        if i > 12 then lines[#lines + 1] = { ("and %d more"):format(#order - 12) } break end
        local name = e.name .. (e.n > 1 and (" ×" .. e.n) or "")
        lines[#lines + 1] = { e.detail ~= "" and (name .. "  " .. muted .. e.detail .. "|r") or name }
    end
    -- all one name: the title says it all
    if #order == 1 and order[1].detail == "" then lines = nil end
    local kind = first.kindName or (first.repeatable and "Repeatable quests") or (first.key == "available" and "Quests to pick up")
        or first.detail or ""
    return { title = kind .. " · " .. g.distinct, lines = lines, meta = "Click to zoom in" }
end

function M:Pin()
    self.free = self.free or {}
    local pin = table.remove(self.free)
    if not pin then
        pin = UI.MapPin(self.layer)
        pin:RegisterForClicks("LeftButtonUp")
        pin:SetScript("OnEnter", function(p)
            if not p.group then return end
            UI.ShowTooltip(p, tipFor(p.group))
            self:HighlightQuests(p.group)
            self:ShowRoutes(p.group)
        end)
        pin:SetScript("OnLeave", function() UI.HideTooltip(); self:HighlightQuests(nil); self:ShowRoutes(nil) end)
        pin:SetScript("OnClick", function(p)
            local g = p.group
            -- a mark: its card
            if g and g.distinct == 1 and g.items[1].mark then
                local marks = SuuUI.GetModule("marks")
                if marks then marks:OpenCard(g.items[1].mark, p) end
                return
            end
            if not (g and g.distinct > 1) then return end
            local f = self.map
            local cx, cy = 0, 0
            for _, it in ipairs(g.items) do cx, cy = cx + it.x, cy + it.y end
            f:PanAndZoomTo(cx / #g.items, cy / #g.items)
        end)
        -- a right-click goes through to the map (it zooms out)
        if pin.SetPassThroughButtons then pcall(pin.SetPassThroughButtons, pin, "RightButton") end
    end
    pin:Show()
    return pin
end

-- Hovering a quest's pin rings every pin of the same quest (its giver, all
-- the places its item drops), a rare's every spot it spawns at, and fades
-- the rest, so they show at a glance.
local function relatedOf(g)
    local quests, rares, any = {}, {}, false
    for _, it in ipairs(g.items) do
        for _, id in ipairs(it.quests or {}) do quests[id] = true; any = true end
        if it.rare then rares[it.rare] = true; any = true end
    end
    return any and { quests = quests, rares = rares } or nil
end
function M:HighlightQuests(group)
    local set = group and relatedOf(group)
    for _, pin in ipairs(self.pins or {}) do
        if not set then
            pin:SetHighlight(nil)
        else
            local related = false
            for _, it in ipairs(pin.group and pin.group.items or {}) do
                if it.rare and set.rares[it.rare] then related = true break end
                for _, id in ipairs(it.quests or {}) do if set.quests[id] then related = true break end end
                if related then break end
            end
            pin:SetHighlight(related and true or "dim")
        end
    end
end

-- A walking giver's route while you hover his pin: a dotted line in his
-- pin's colour, a dot every 9 px on a surface rim, under the pins.
local ROUTE_STEP, ROUTE_DOT = 9, 4
function M:ShowRoutes(group)
    local r = self.routes
    if not r then
        r = CreateFrame("Frame", nil, self.layer)
        r:SetFrameLevel(self.layer:GetFrameLevel())
        r.dots = {}
        self.routes = r
    end
    for _, d in ipairs(r.dots) do d.rim:Hide(); d.fill:Hide() end
    r:Hide()
    local w, h, cs = self.lw, self.lh, self.lcs
    if not (group and w and cs) then return end
    local n = 0
    local function dot(x, y, color)
        n = n + 1
        local d = r.dots[n]
        if not d then
            d = { rim = r:CreateTexture(nil, "ARTWORK", nil, 1), fill = r:CreateTexture(nil, "ARTWORK", nil, 2) }
            d.rim:SetTexture(DISC)
            d.rim:SetSize(ROUTE_DOT + 2, ROUTE_DOT + 2)
            d.rim:SetVertexColor(UI.RGBA("surface"))
            d.fill:SetTexture(DISC)
            d.fill:SetSize(ROUTE_DOT, ROUTE_DOT)
            r.dots[n] = d
        end
        d.fill:SetVertexColor(UI.RGBA(color))
        for _, t in ipairs({ d.rim, d.fill }) do
            t:ClearAllPoints()
            t:SetPoint("CENTER", r, "TOPLEFT", x, -y)
            t:Show()
        end
    end
    local drawn = {}
    for _, it in ipairs(group.items) do
        local color = it.pin and it.pin.color or "ink"
        for _, path in ipairs(it.route and not drawn[it.route] and it.route or {}) do
            -- walk the path, a dot each ROUTE_STEP px of it
            local left = 0
            for i = 1, #path - 3, 2 do
                local ax, ay = path[i] / 100 * w, path[i + 1] / 100 * h
                local bx, by = path[i + 2] / 100 * w, path[i + 3] / 100 * h
                local len = math.sqrt((bx - ax) ^ 2 + (by - ay) ^ 2)
                local t = left
                while t <= len do
                    local k = len > 0 and t / len or 0
                    dot(ax + (bx - ax) * k, ay + (by - ay) * k, color)
                    t = t + ROUTE_STEP
                end
                left = t - len
            end
        end
        if it.route then drawn[it.route] = true end
    end
    if n == 0 then return end
    r:SetScale(1 / cs)
    r:ClearAllPoints()
    r:SetPoint("TOPLEFT", self.layer, "TOPLEFT")
    r:SetSize(w, h)
    r:Show()
end

function M:ClearPins()
    self:ShowRoutes(nil)
    for _, pin in ipairs(self.pins or {}) do
        pin:Hide()
        pin:ClearAllPoints()
        pin:SetHighlight(nil)
        pin.group = nil
        table.insert(self.free, pin)
    end
    self.pins = {}
end

function M:Layout()
    self.layoutQueued = false
    local f = self.map
    if not (f and f:IsShown() and self.items) then return end
    self:ClearPins()
    local canvas = f:GetCanvas()
    local cs = f:GetCanvasScale()
    if not (cs and cs > 0) then return end
    local w, h = canvas:GetWidth() * cs, canvas:GetHeight() * cs
    if w <= 0 or h <= 0 then return end
    self.lw, self.lh, self.lcs = w, h, cs
    -- zoomed all the way in (on a map that zooms), every pin stays on its
    -- exact spot, so you find it there: none move, and only those on one
    -- spot merge (they'd hide each other)
    local items, radius, grow = self.items, MERGE_RADIUS, 1
    if f:IsAtMaxZoom() and not f:IsAtMinZoom() then
        -- (and a little larger: there's room)
        items, radius, grow = {}, MERGE_RADIUS_CLOSEST, CLOSEST_GROW
        for i, it in ipairs(self.items) do
            items[i] = setmetatable({ fixed = true }, { __index = it })
        end
    end
    local groups = merge(items, w, h, radius)
    mergeGroups(groups, radius)
    spread(groups)
    -- spreading can push two of a kind together: join them, spread again
    mergeGroups(groups, radius)
    spread(groups)
    -- small ones under the rest, places on top
    table.sort(groups, function(a, b)
        local la = a.small and 1 or (a.fixed and 3 or 2)
        local lb = b.small and 1 or (b.fixed and 3 or 2)
        if la ~= lb then return la < lb end
        return a.y < b.y
    end)
    local base = self.layer:GetFrameLevel()
    for i, g in ipairs(groups) do
        local pin = self:Pin()
        local data = g.items[1].pin
        if g.distinct > 1 then
            -- a merged quest pin takes its most useful quest's colour
            if g.key == "available" or g.key == "itemQuest" or g.key == "repeatable" then
                local best = g.items[1]
                for _, it in ipairs(g.items) do if (it.rank or 9) < (best.rank or 9) then best = it end end
                data = best.pin
            end
            data = { glyph = data.glyph, char = data.char, color = data.color, edge = data.edge, small = data.small,
                     ring = data.ring, spin = data.spin, edgeWidth = data.edgeWidth, count = g.distinct }
        end
        pin:SetData(data)
        pin:SetBaseAlpha((self:Get("pinAlpha") or 100) / 100)
        pin.group = g
        pin:SetScale(grow / cs)
        -- (three tiers in a few levels, under the game's own pins: small ones,
        -- then the rest, then places and marks; a count tab just above its pin)
        local tier = g.small and 1 or (g.fixed and 5 or 3)
        pin:SetFrameLevel(base + tier)
        pin.countTab:SetFrameLevel(base + tier + 1)
        pin:ClearAllPoints()
        pin:SetPoint("CENTER", self.layer, "TOPLEFT", g.x / grow, -g.y / grow)
        self.pins[#self.pins + 1] = pin
    end
    -- a mark's open card follows its pin
    local marks = SuuUI.GetModule and SuuUI.GetModule("marks")
    if marks and marks.cardMark then marks:AnchorCard(self:PinForMark(marks.cardMark)) end
    -- the game's quest markers sized again for the zoom (it scales its own)
    if self.map.EnumeratePinsByTemplate then
        for pin in self.map:EnumeratePinsByTemplate("QuestPinTemplate") do
            if pin.suuQuest then self:FitQuestPin(pin) end
        end
    end
end

-- The pin showing a mark (the marks module's card sits under it).
function M:PinForMark(id)
    for _, pin in ipairs(self.pins or {}) do
        local g = pin.group
        if g and g.distinct == 1 and g.items[1].mark == id then return pin end
    end
end

function M:QueueLayout()
    if self.layoutQueued then return end
    self.layoutQueued = true
    C_Timer.After(0, function() self:Layout() end)
end

--------------------------------------------------------------------------------
-- The game's quest markers in SuuUI's look (design: MapPin types objective
-- / turn-in / waypoint, states tracked and highlighted), restyled in
-- place: the game's pins keep
-- their clicks, tooltips and super-tracking; a SuuUI pin without the mouse
-- sits in each, the game's art hidden, kept up to date after each of the
-- game's style, selection and highlight changes, and sized like SuuUI's pins
-- at every zoom. The objective areas stay the game's: its area drawing
-- takes no addon texture (SuuUI's hatch and edge showed its missing-texture
-- green, with or without the extension; found in game), and their shapes
-- aren't given to addons to draw otherwise.
--------------------------------------------------------------------------------

local TEXTURES = "Interface\\AddOns\\SuuUI\\Media\\Textures\\"
local SOFT = TEXTURES .. "CircleSoft.tga"

local function questStyle(pin)
    local S = POIButtonUtil and POIButtonUtil.Style
    local style = pin.GetStyle and pin:GetStyle()
    if not S then return nil end
    if style == S.QuestComplete then return "complete" end
    if style == S.QuestInProgress then return "progress" end
    if style == S.Waypoint then return "waypoint" end
    if style == S.QuestDisabled then return "disabled" end
end

-- The game's look back (the module off).
local function unstyle(pin)
    local o = pin.suuQuest
    if o then o:Hide() end
    for _, key in ipairs({ "NormalTexture", "PushedTexture", "HighlightTexture", "Glow", "Display",
                           "UnderlayAtlas", "UnderlayBannerAtlas", "UnderlayBannerAtlasHighlight" }) do
        local r = pin[key]
        if r and r.SetAlpha then r:SetAlpha(1) end
    end
    if pin.UpdateButtonAlpha then pin:UpdateButtonAlpha() end
end

function M:UnstyleQuest()
    local f = self.map
    if not f or not f.EnumeratePinsByTemplate then return end
    for pin in f:EnumeratePinsByTemplate("QuestPinTemplate") do unstyle(pin) end
end

function M:StyleQuestPin(pin)
    if not self:IsEnabled() then unstyle(pin) return end
    local kind = questStyle(pin)
    local o = pin.suuQuest
    if not kind then
        if o then o:Hide() end
        return
    end
    if not o then
        o = CreateFrame("Frame", nil, pin)
        o:SetPoint("CENTER")
        o:SetSize(1, 1)
        o.glow = o:CreateTexture(nil, "BACKGROUND", nil, -1)
        o.glow:SetTexture(SOFT)
        o.glow:SetPoint("CENTER")
        o.pin = UI.MapPin(o)
        o.pin:EnableMouse(false)
        o.pin:SetPoint("CENTER")
        pin.suuQuest = o
        -- the game's look away; ours follows its changes
        local function hideArt()
            for _, key in ipairs({ "NormalTexture", "PushedTexture", "HighlightTexture", "Glow", "Display" }) do
                local r = pin[key]
                if r and r.SetAlpha then r:SetAlpha(0) end
            end
            for _, key in ipairs({ "UnderlayAtlas", "UnderlayBannerAtlas", "UnderlayBannerAtlasHighlight" }) do
                local r = pin[key]
                if r and r.SetAlpha then r:SetAlpha(0) end
            end
        end
        o.hideArt = hideArt
        local function restyle() self:StyleQuestPin(pin) end
        for _, fn in ipairs({ "UpdateButtonStyle", "SetSelected", "EvaluateManagedHighlight", "SetStyle" }) do
            if pin[fn] then hooksecurefunc(pin, fn, restyle) end
        end
        pin:HookScript("OnEnter", function() o.hovered = true; restyle() end)
        pin:HookScript("OnLeave", function() o.hovered = false; restyle() end)
    end
    o.hideArt()
    if kind == "disabled" then o:Hide() return end
    o:Show()
    local tracked = pin.IsSelected and pin:IsSelected()
    local lit = pin.HighlightTexture and pin.HighlightTexture:IsShown()
    local data
    if kind == "complete" then
        data = { char = "?", color = "arcane", edge = "arcane" }
    elseif kind == "waypoint" then
        data = { glyph = "dash", color = "ink", edge = "ink-muted" }
    else
        data = { glyph = "questDots", color = "ink", edge = "ink-muted" }
    end
    o.pin:SetData(data)
    -- the next step on another map: a dashed edge
    o.pin.edge:SetTexture(kind == "waypoint" and (TEXTURES .. "CircleDash.tga") or (TEXTURES .. "CircleFill.tga"))
    o.pin:SetBaseAlpha((self:Get("pinAlpha") or 100) / 100)
    o.pin:SetHighlight((tracked or lit) and true or nil)
    -- glow: arcane under a turn-in, ink at 40% while super-tracked
    local size = o.pin:PinSize()
    if tracked then
        o.glow:SetVertexColor(UI.RGBA("ink", 0.4))
        o.glow:SetSize(size + 24, size + 24)
        o.glow:Show()
    elseif kind == "complete" then
        o.glow:SetVertexColor(UI.RGBA("arcane-glow"))
        o.glow:SetSize(size + 16, size + 16)
        o.glow:Show()
    else
        o.glow:Hide()
    end
    -- SuuUI's pin size at every zoom (the game scales its own), a tenth
    -- larger while tracked or hovered
    self:FitQuestPin(pin, (tracked or o.hovered) and 1.1 or 1)
end

function M:FitQuestPin(pin, grow)
    local o = pin.suuQuest
    local f = self.map
    if not (o and f and self.layer) then return end
    o.grow = grow or o.grow or 1
    local cs = f:GetCanvasScale()
    local pe = pin:GetEffectiveScale()
    if not (cs and cs > 0 and pe and pe > 0) then return end
    local closest = f:IsAtMaxZoom() and not f:IsAtMinZoom() and CLOSEST_GROW or 1
    -- (SuuUI's pins: the layer's scale × grow / canvas scale; this sits in
    -- the game's pin, whose own scale it takes out)
    o:SetScale(self.layer:GetEffectiveScale() * closest * o.grow / cs / pe)
end

function M:StyleQuestPins()
    local f = self.map
    if not f or not f.EnumeratePinsByTemplate then return end
    for pin in f:EnumeratePinsByTemplate("QuestPinTemplate") do self:StyleQuestPin(pin) end
end

-- The game's quest pins' provider: after each of its refreshes, the look.
function M:HookQuestProviders()
    local f = self.map
    if not f or self.questHooked then return end
    self.questHooked = true
    local quest = _G.QuestDataProviderMixin
    for provider in pairs(f.dataProviders or {}) do
        if quest and provider.RefreshAllData == quest.RefreshAllData then
            hooksecurefunc(provider, "RefreshAllData", function() if self:IsEnabled() then self:StyleQuestPins() end end)
        end
    end
end

--------------------------------------------------------------------------------
-- Unexplored areas: the map's overlays you haven't explored, drawn as the
-- game draws the explored ones (Blizzard_SharedMapDataProviders, read
-- 2026-10-15), tinted a little darker and bluer so the map still says where
-- you haven't been. From SuuUI.MapOverlays (Forever's client tables).
--------------------------------------------------------------------------------

local TINT = { 0.62, 0.7, 0.92 }

function M:Reveal(mapID)
    for _, t in ipairs(self.revealUsed or {}) do t:Hide(); table.insert(self.revealFree, t) end
    self.revealUsed = {}
    local f = self.map
    local on = self:Layers()
    if not (mapID and on.places.unexplored and SuuUI.MapOverlays) then return end
    -- the overlays are the base layer's: drawn only on it
    local container = f:GetCanvasContainer()
    local layerIndex = container.GetCurrentLayerIndex and container:GetCurrentLayerIndex() or 1
    self.revealLayer = layerIndex
    if layerIndex ~= 1 then return end
    local art = C_Map.GetMapArtID and C_Map.GetMapArtID(mapID)
    local overlays = art and SuuUI.MapOverlays()[art]
    local layers = C_Map.GetMapArtLayers and C_Map.GetMapArtLayers(mapID)
    local layer = layers and layers[1]
    if not (overlays and layer) then return end
    local explored = {}
    local ok, list = pcall(C_MapExplorationInfo.GetExploredMapTextures, mapID)
    for _, e in ipairs(ok and list or {}) do
        explored[e.textureWidth .. "," .. e.textureHeight .. "," .. e.offsetX .. "," .. e.offsetY] = true
    end
    local tileW, tileH = layer.tileWidth, layer.tileHeight
    for _, o in ipairs(overlays) do
        local w, h, ox, oy = o[1], o[2], o[3], o[4]
        if not explored[w .. "," .. h .. "," .. ox .. "," .. oy] then
            local wide, tall = math.ceil(w / tileW), math.ceil(h / tileH)
            for j = 1, tall do
                local pixH, fileH = tileH, tileH
                if j == tall then
                    pixH = h % tileH
                    if pixH == 0 then pixH = tileH end
                    fileH = 16
                    while fileH < pixH do fileH = fileH * 2 end
                end
                for k = 1, wide do
                    local file = o[4 + (j - 1) * wide + k]
                    if file then
                        local pixW, fileW = tileW, tileW
                        if k == wide then
                            pixW = w % tileW
                            if pixW == 0 then pixW = tileW end
                            fileW = 16
                            while fileW < pixW do fileW = fileW * 2 end
                        end
                        local t = table.remove(self.revealFree) or self.reveal:CreateTexture(nil, "ARTWORK")
                        t:SetTexture(file, nil, nil, "TRILINEAR")
                        t:SetSize(pixW, pixH)
                        t:SetTexCoord(0, pixW / fileW, 0, pixH / fileH)
                        t:ClearAllPoints()
                        t:SetPoint("TOPLEFT", self.reveal, "TOPLEFT", ox + tileW * (k - 1), -(oy + tileH * (j - 1)))
                        t:SetVertexColor(TINT[1], TINT[2], TINT[3])
                        t:Show()
                        self.revealUsed[#self.revealUsed + 1] = t
                    end
                end
            end
        end
    end
end

function M:Refresh()
    local f = self.map
    if not (f and self:IsEnabled()) then return end
    if not f:IsShown() then self.items = nil; self:ClearPins(); return end
    local mapID = f:GetMapID()
    readCalendar()
    self:Reveal(mapID)
    self.items = mapID and self:Collect(mapID) or {}
    self:Layout()
end

--------------------------------------------------------------------------------
-- The map
--------------------------------------------------------------------------------

-- "Map filters" in the map's header (SuuUI's, when the window skin is on),
-- else over the map's top left; the game's own filter button goes.
function M:PlaceFilters()
    local f, menu = self.map, self.menu
    menu:ClearAllPoints()
    local chrome = f.suuChrome
    if chrome and chrome.head then
        menu:SetParent(chrome.head)
        -- (by its middle, on the line the row's controls share)
        menu:SetPoint("LEFT", chrome.head, "BOTTOMLEFT", S["space-5"], chrome.rowMid or (S["space-1"] + 11))
        menu:SetFrameLevel(chrome.head:GetFrameLevel() + 4)
    else
        menu:SetParent(f)
        menu:SetPoint("TOPLEFT", f:GetCanvasContainer(), "TOPLEFT", S["space-3"], -S["space-3"])
        menu:SetFrameLevel(f:GetFrameLevel() + 450)
    end
    local track = f.WorldMapTrackingOptionsButton
    if track then track:SetAlpha(0); track:EnableMouse(false) end
    -- the waypoint pin (when the game has one) moves to the menu's right
    local pin = f.WorldMapTrackingPinButton
    if pin and chrome then
        pin:ClearAllPoints()
        pin:SetPoint("LEFT", menu, "RIGHT", S["space-2"], 0)
    end
end

function M:Attach()
    local f = _G.WorldMapFrame
    if not f or self.map then return end
    self.map = f
    -- the unexplored areas, then the pins above them
    self.reveal = CreateFrame("Frame", nil, f:GetCanvas())
    self.reveal:SetAllPoints(f:GetCanvas())
    self.reveal:SetFrameLevel(f:GetCanvas():GetFrameLevel() + 1)
    self.revealFree, self.revealUsed = {}, {}
    self.layer = CreateFrame("Frame", nil, f:GetCanvas())
    self.layer:SetAllPoints(f:GetCanvas())
    -- above the game's map art (its explored areas, fog, quest areas and the
    -- map highlight, frame levels from 2000 up), under its own pins (quests,
    -- group members, you): just over the canvas the explored areas covered
    -- pins where the game draws them (a mark in lower Mulgore hovered but
    -- unseen; found in game)
    local levels = f.GetPinFrameLevelsManager and f:GetPinFrameLevelsManager()
    local above = levels and levels.GetFrameLevelStart and levels:GetFrameLevelStart("PIN_FRAME_LEVEL_MAP_HIGHLIGHT")
    self.layer:SetFrameLevel(above and (above + 1) or (f:GetCanvas():GetFrameLevel() + 2))
    self.pins = {}
    local provider = CreateFromMixins(MapCanvasDataProviderMixin)
    provider.RefreshAllData = function() self:Refresh() end
    provider.RemoveAllData = function() self.items = nil; self:ClearPins(); self:Reveal(nil) end
    provider.OnCanvasScaleChanged = function()
        self:QueueLayout()
        -- a map with zoom layers: the overlays only on the base one
        local c = f:GetCanvasContainer()
        local index = c.GetCurrentLayerIndex and c:GetCurrentLayerIndex() or 1
        if index ~= self.revealLayer then self:Reveal(f:GetMapID()) end
    end
    provider.OnCanvasSizeChanged = function() self:QueueLayout() end
    self.provider = provider
    self.menu = UI.FilterMenu(f, {
        groups = GROUPS, defaults = DEFAULT_FILTERS, value = self:MenuValue(),
        placeholder = "Map filters", style = "button", height = 22, done = true,
        onChange = function(value) self:OnFilters(value) end,
    })
    -- every time the map opens: the game's place for its filter comes back
    f:HookScript("OnShow", function()
        if not self:IsEnabled() then return end
        self.menu:SetValue(self:MenuValue())
        self:PlaceFilters()
    end)
    -- (a frame later: the window skin lays its row out on the same change)
    hooksecurefunc(f, "OnMapChanged", function()
        if self:IsEnabled() then C_Timer.After(0, function() self:PlaceFilters() end) end
    end)
end

-- Settings › World map: how solid the pins are.
function M:PreviewView(parent)
    local v = self.preview
    if not v then
        v = CreateFrame("Frame", nil, parent)
        v:SetSize(200, 60)
        UI.Fill(v, "surface-sunk"):SetAllPoints()
        UI.Border(v, "gilt-line")
        v.pins = {}
        local samples = {
            { char = "!", color = "quest-standard" },
            { glyph = "swirl" },
            { glyph = "mail", small = true },
            { glyph = "markStar", color = "mark-star", edge = "mark-star", edgeWidth = 2 },
        }
        for i, d in ipairs(samples) do
            local pin = UI.MapPin(v)
            pin:SetData(d)
            pin:EnableMouse(false)
            pin:SetPoint("CENTER", v, "LEFT", 32 + (i - 1) * 45, 0)
            v.pins[i] = pin
        end
        self.preview = v
    end
    v:SetParent(parent)
    for _, pin in ipairs(v.pins) do pin:SetBaseAlpha((self:Get("pinAlpha") or 100) / 100) end
    return v
end

local SECTION = {
    id = "worldmap", label = "World map", category = "World", order = 12,
    preview = function(parent) return M:PreviewView(parent) end,
    groups = {
        { title = "Map pins", description = "What shows is in the map's own Map filters.", rows = {
            { key = "pinAlpha", label = "Pin opacity", control = "slider", min = 20, max = 100, step = 5, unit = "%",
              description = "How solid SuuUI's pins on the world map are. Hovering one shows the pins that belong with it at full opacity." },
        } },
        { title = "Enlarged map", description = "The maximize button in the map's header enlarges the map in the middle of the screen.", rows = {
            { key = "enlargedSize", label = "Size", control = "slider", min = 50, max = 100, step = 5, unit = "%",
              description = "How tall the enlarged map is, its header included, as a share of the screen's height. It stays narrower than the screen." },
        } },
    },
}

function M:OnEnable()
    self:Attach()
    if not self.map then
        self:OnGameEvent("ADDON_LOADED", function()
            if not self.map and _G.WorldMapFrame then self:Attach(); self:OnEnable() end
        end)
        return
    end
    -- (here, past the wait for the map: this runs once)
    self:RegisterSettings(SECTION)
    self:HookQuestProviders()
    self:StyleQuestPins()
    self:Watch("pinAlpha", function()
        if self.map and self.map:IsShown() then self:Layout() end
        if self.preview then for _, pin in ipairs(self.preview.pins) do pin:SetBaseAlpha((self:Get("pinAlpha") or 100) / 100) end end
    end)
    self.map:AddDataProvider(self.provider)
    self.layer:Show()
    self.reveal:Show()
    self.menu:Show()
    self.menu:SetValue(self:MenuValue())
    self:PlaceFilters()
    -- what you can pick up changes as you level and turn quests in
    for _, event in ipairs({ "QUEST_TURNED_IN", "QUEST_ACCEPTED", "QUEST_REMOVED", "PLAYER_LEVEL_UP", "SKILL_LINES_CHANGED", "UPDATE_FACTION",
                            "MAP_EXPLORATION_UPDATED" }) do
        self:OnGameEvent(event, function() if self.map:IsShown() then C_Timer.After(0.2, function() self:Refresh() end) end end)
    end
    -- the holidays on today: the calendar loads its events after
    -- OpenCalendar (it tells with CALENDAR_UPDATE_EVENT_LIST); read again
    -- when the map opens, so a holiday that starts while you play shows
    -- marks made, renamed, shared or removed
    self:On("SUUUI_MARKS_CHANGED", function() if self.map:IsShown() then self:Refresh() end end)
    self:OnGameEvent("CALENDAR_UPDATE_EVENT_LIST", function()
        if readCalendar() and self.map:IsShown() then self:Refresh() end
    end)
    if C_Calendar and C_Calendar.OpenCalendar then pcall(C_Calendar.OpenCalendar) end
    readCalendar()
end

function M:OnDisable()
    local f = self.map
    if not f then return end
    self:UnstyleQuest()
    f:RemoveDataProvider(self.provider)
    self.items = nil
    self:ClearPins()
    self.layer:Hide()
    self:Reveal(nil)
    self.reveal:Hide()
    self.menu:Hide()
    local track = f.WorldMapTrackingOptionsButton
    if track then track:SetAlpha(1); track:EnableMouse(true) end
end
