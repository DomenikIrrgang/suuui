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
--   Services   innkeepers, repair, mailboxes, your class trainer (on);
--              profession trainers, bankers, auctioneers, vendors, stable
--              masters, battlemasters, guild masters, tabard designers,
--              spirit healers (off)
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
    quests = { "objectives", "available", "repeatable" },
    places = { "dungeons", "battlegrounds", "flight", "campfires" },
    services = { "inn", "repair", "mail", "classTrainer" },
    rares = { "rares" },
}

local M = SuuUI.RegisterModule({
    id = "worldmap",
    name = "World map pins",
    description = "Pins on the world map: quests to pick up, entrances, flight masters, services, rares and treasures.",
    api = "0.14",
    defaults = { filters = DEFAULT_FILTERS },
})

local UI, T = SuuUI.UI, SuuUI.Tokens
local S = T.space

local isSecret = issecretvalue or function() return false end
local function plain(v) return v ~= nil and not isSecret(v) end

local MERGE_RADIUS = 32 -- px on screen

--------------------------------------------------------------------------------
-- The filter menu
--------------------------------------------------------------------------------

local GROUPS = {
    { key = "quests", label = "Quests", kind = "toggles", options = {
        { value = "objectives", label = "Quest objectives" },
        { value = "available", label = "Quests to pick up" },
        { value = "repeatable", label = "Repeatable and daily" },
        { value = "trivial", label = "Trivial quests" },
    } },
    { key = "places", label = "Places", kind = "toggles", options = {
        { value = "dungeons", label = "Dungeon and raid entrances" },
        { value = "battlegrounds", label = "Battleground entrances" },
        { value = "flight", label = "Flight masters" },
        { value = "campfires", label = "Campfires you found" },
    } },
    { key = "services", label = "Services", kind = "toggles", column = true, options = {
        { value = "inn", label = "Innkeepers" },
        { value = "repair", label = "Repair" },
        { value = "mail", label = "Mailboxes" },
        { value = "classTrainer", label = "Your class trainer" },
        { value = "trainers", label = "Profession trainers" },
        { value = "bank", label = "Bankers" },
        { value = "auction", label = "Auctioneers" },
        { value = "goods", label = "General goods" },
        { value = "food", label = "Food and drink" },
        { value = "vendor", label = "Other vendors" },
        { value = "stable", label = "Stable masters" },
        { value = "battlemaster", label = "Battlemasters" },
        { value = "guild", label = "Guild masters" },
        { value = "tabard", label = "Tabard designers" },
        { value = "spirit", label = "Spirit healers" },
    } },
    { key = "rares", label = "Rares and treasures", kind = "toggles", column = true, options = {
        { value = "rares", label = "Rares" },
        { value = "treasures", label = "Treasure chests" },
    } },
}

-- on[group][value] from the saved filters
function M:Layers()
    local saved = self:Get("filters") or {}
    local on = {}
    for _, g in ipairs(GROUPS) do
        local set = {}
        for _, v in ipairs(saved[g.key] or {}) do set[v] = true end
        on[g.key] = set
    end
    return on
end

-- the game's quest objectives follow its own setting
local function objectivesShown()
    local ok, v = pcall(GetCVarBool, "questPOI")
    return not ok or v
end

function M:MenuValue()
    local saved = self:Get("filters") or {}
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
local PROFESSION_GLYPH = {
    alchemy = "flask", blacksmithing = "hammer", enchanting = "star", engineering = "gear", herbalism = "leaf",
    leatherworking = "hide", mining = "pick", skinning = "knife", tailoring = "needle", cooking = "pot",
    firstAid = "bandage", fishing = "fish", other = "book",
}
local PROFESSION_NAMES = {
    alchemy = "Alchemy trainer", blacksmithing = "Blacksmithing trainer", enchanting = "Enchanting trainer",
    engineering = "Engineering trainer", herbalism = "Herbalism trainer", leatherworking = "Leatherworking trainer",
    mining = "Mining trainer", skinning = "Skinning trainer", tailoring = "Tailoring trainer", cooking = "Cooking trainer",
    firstAid = "First aid trainer", fishing = "Fishing trainer", other = "Trainer",
}
local QUEST_RANK = { difficult = 1, standard = 2, ["very-difficult"] = 3, impossible = 4, trivial = 5 }

-- The game's difficulty colour for a level, as the design's token suffix.
local DIFFICULTY_FONTS = {
    { "VeryDifficult", "very-difficult" }, { "Impossible", "impossible" }, { "Difficult", "difficult" },
    { "Standard", "standard" }, { "Trivial", "trivial" },
}
local function difficultyOf(level)
    if not (plain(level) and GetQuestDifficultyColor) then return "standard" end
    local ok, c = pcall(GetQuestDifficultyColor, level)
    local font = ok and type(c) == "table" and c.font
    if type(font) ~= "string" then return "standard" end
    for _, d in ipairs(DIFFICULTY_FONTS) do
        if font:find(d[1], 1, true) then return d[2] end
    end
    return "standard"
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

-- Whether you can pick a quest up now: "available", "repeatable" or nil,
-- and its difficulty.
local function questState(q, id, me, done)
    if onQuest(id) then return nil end
    local repeatable = q[10] and q[10] % 2 == 1
    if done[id] and not repeatable then return nil end
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
    return repeatable and "repeatable" or "available", difficultyOf(level), level
end

-- every pin the map would show, before merging: { x, y (0-1), key (what
-- merges with what, nil: never), small, pin (MapPin data), tip (tooltip
-- lines), rank (a merged quest pin takes the best) }
function M:Collect(mapID)
    local items = {}
    local on = self:Layers()
    local me = self:Player()
    local starts = SuuUI.QuestStarts and SuuUI.QuestStarts() or {}
    local places = SuuUI.MapPlaces and SuuUI.MapPlaces() or {}

    -- quests to pick up: a pin per giver's place
    if on.quests.available or on.quests.repeatable then
        local done = completedSet()
        for _, row in ipairs(starts.maps and starts.maps[mapID] or {}) do
            local best, list = nil, {}
            for i = 3, #row do
                local id = row[i]
                local q = starts.quests[id]
                local state, difficulty, level = q and questState(q, id, me, done)
                if state and (on.quests[state]) and (difficulty ~= "trivial" or on.quests.trivial) then
                    list[#list + 1] = { name = q[1], level = level, difficulty = difficulty, state = state }
                    local rank = QUEST_RANK[difficulty] or 9
                    if not best or rank < best.rank then best = { rank = rank, difficulty = difficulty, state = state } end
                end
            end
            if best then
                local repeatable = best.state == "repeatable"
                local lines = {}
                for i, q in ipairs(list) do
                    if i > 1 then lines[#lines + 1] = { q.name, "Level " .. q.level } end
                end
                items[#items + 1] = {
                    x = row[1] / 100, y = row[2] / 100, key = repeatable and "repeatable" or "available", rank = best.rank,
                    pin = { char = "!", color = repeatable and "mana" or ("quest-" .. best.difficulty), edge = repeatable and "mana" or nil },
                    name = list[1].name, detail = (repeatable and "Repeatable · " or "") .. "Level " .. list[1].level,
                    more = lines, difficulty = best.difficulty, repeatable = repeatable,
                }
            end
        end
    end

    -- entrances
    for _, e in ipairs(starts.entrances and starts.entrances[mapID] or {}) do
        local kind, faction = e[4], e[5]
        local show = (kind == "battleground" and on.places.battlegrounds) or (kind ~= "battleground" and on.places.dungeons)
        if show and (not faction or faction == me.faction) then
            items[#items + 1] = { x = e[1] / 100, y = e[2] / 100, fixed = true,
                pin = { glyph = kind == "raid" and "gate" or kind == "battleground" and "swords" or "door" },
                name = e[3], detail = kind == "raid" and "Raid" or kind == "battleground" and "Battleground" or "Dungeon" }
        end
    end

    -- flight masters: the game's taxi nodes for this map (yours and neutral)
    if on.places.flight and C_TaxiMap and C_TaxiMap.GetTaxiNodesForMap then
        local ok, nodes = pcall(C_TaxiMap.GetTaxiNodesForMap, mapID)
        local mine = me.faction == "H" and 1 or me.faction == "A" and 2 or -1
        for _, n in ipairs(ok and type(nodes) == "table" and nodes or {}) do
            local x, y = n.position and n.position.GetXY and n.position:GetXY()
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
        if n and n[4] and (n[3] and me.faction and n[3]:find(me.faction, 1, true)) then
            for kind in n[4]:gmatch("[^,]+") do
                local item
                local class = kind:match("^class:(.+)$")
                local prof = kind:match("^trainer:(.+)$")
                if class then
                    if class == me.class and on.services.classTrainer then
                        local token = "class-" .. class:lower()
                        item = { key = "classTrainer", pin = { glyph = "book", color = token, edge = token, small = true },
                                 kindName = SERVICE_NAMES.classTrainer }
                    elseif class ~= me.class then
                        item = false -- another class's trainer: never
                    end
                elseif prof then
                    if on.services.trainers then
                        item = { key = "trainer:" .. prof, pin = { glyph = PROFESSION_GLYPH[prof] or "book", small = true },
                                 kindName = PROFESSION_NAMES[prof] or "Trainer" }
                    end
                else
                    local s = SERVICE[kind]
                    if s and on.services[s[1]] then
                        item = { key = kind, pin = { glyph = s[2], color = s[3], small = true }, kindName = SERVICE_NAMES[kind] }
                    end
                end
                if item == false then break end
                if item then
                    item.x, item.y, item.small = svc[i] / 100, svc[i + 1] / 100, true
                    item.name, item.detail = n[1], n[2]
                    items[#items + 1] = item
                    break
                end
            end
        end
    end
    if on.services.mail then
        local mail = places.mailboxes and places.mailboxes[mapID] or {}
        for i = 1, #mail, 2 do
            items[#items + 1] = { x = mail[i] / 100, y = mail[i + 1] / 100, key = "mail", small = true,
                pin = { glyph = "mail", small = true }, name = "Mailbox", kindName = "Mailbox" }
        end
    end

    -- rares and treasures
    if on.rares.rares then
        local rares = places.rares and places.rares[mapID] or {}
        for i = 1, #rares, 3 do
            local n = npcs[rares[i + 2]]
            if n then
                local elite = n[5] == "rareElite"
                local level = n[6] and (n[7] and n[7] ~= n[6] and (n[6] .. "-" .. n[7]) or tostring(n[6])) or nil
                items[#items + 1] = { x = rares[i] / 100, y = rares[i + 1] / 100, key = elite and "rareElite" or "rare",
                    pin = elite and { glyph = "skull", color = "gilt-text", edge = "gilt", ring = "gilt" }
                        or { glyph = "skull", color = "ink", edge = "coin-silver" },
                    name = n[1], detail = (elite and "Rare elite" or "Rare") .. (level and (" · level " .. level) or ""),
                    kindName = elite and "Rare elite" or "Rare", npc = rares[i + 2] }
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
    return items
end

--------------------------------------------------------------------------------
-- Merging and spreading, in screen pixels at the map's zoom
--------------------------------------------------------------------------------

-- items → groups { x, y (px), items, key, fixed, small }
local function merge(items, w, h)
    local groups = {}
    local r2 = MERGE_RADIUS * MERGE_RADIUS
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
        else
            groups[#groups + 1] = { x = px, y = py, items = { it }, key = it.key, fixed = it.fixed, small = it.small }
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
                    local need = ((a.small and 17 or 22) + (b.small and 17 or 22)) / 2
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
    if #g.items == 1 then
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
    local lines = {}
    for i, it in ipairs(g.items) do
        if i > 12 then lines[#lines + 1] = { ("and %d more"):format(#g.items - 12) } break end
        lines[#lines + 1] = { it.name or "?", it.detail or "" }
    end
    local kind = first.kindName or (first.repeatable and "Repeatable quests") or (first.key == "available" and "Quests to pick up")
        or first.detail or ""
    return { title = kind .. " · " .. #g.items, lines = lines, meta = "Click to zoom in" }
end

function M:Pin()
    self.free = self.free or {}
    local pin = table.remove(self.free)
    if not pin then
        pin = UI.MapPin(self.layer)
        pin:RegisterForClicks("LeftButtonUp")
        pin:SetScript("OnEnter", function(p) if p.group then UI.ShowTooltip(p, tipFor(p.group)) end end)
        pin:SetScript("OnLeave", function() UI.HideTooltip() end)
        pin:SetScript("OnClick", function(p)
            local g = p.group
            if not (g and #g.items > 1) then return end
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

function M:ClearPins()
    for _, pin in ipairs(self.pins or {}) do
        pin:Hide()
        pin:ClearAllPoints()
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
    local groups = merge(self.items, w, h)
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
        if #g.items > 1 then
            -- a merged quest pin takes its most useful quest's colour
            if g.key == "available" then
                local best = g.items[1]
                for _, it in ipairs(g.items) do if (it.rank or 9) < (best.rank or 9) then best = it end end
                data = best.pin
            end
            data = { glyph = data.glyph, char = data.char, color = data.color, edge = data.edge, small = data.small,
                     ring = data.ring, count = #g.items }
        end
        pin:SetData(data)
        pin.group = g
        pin:SetScale(1 / cs)
        pin:SetFrameLevel(base + i)
        pin:ClearAllPoints()
        pin:SetPoint("CENTER", self.layer, "TOPLEFT", g.x, -g.y)
        self.pins[#self.pins + 1] = pin
    end
end

function M:QueueLayout()
    if self.layoutQueued then return end
    self.layoutQueued = true
    C_Timer.After(0, function() self:Layout() end)
end

function M:Refresh()
    local f = self.map
    if not (f and self:IsEnabled()) then return end
    if not f:IsShown() then self.items = nil; self:ClearPins(); return end
    local mapID = f:GetMapID()
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
        menu:SetPoint("BOTTOMLEFT", chrome.head, "BOTTOMLEFT", S["space-5"], S["space-1"])
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
    self.layer = CreateFrame("Frame", nil, f:GetCanvas())
    self.layer:SetAllPoints(f:GetCanvas())
    self.layer:SetFrameLevel(f:GetCanvas():GetFrameLevel() + 1)
    self.pins = {}
    local provider = CreateFromMixins(MapCanvasDataProviderMixin)
    provider.RefreshAllData = function() self:Refresh() end
    provider.RemoveAllData = function() self.items = nil; self:ClearPins() end
    provider.OnCanvasScaleChanged = function() self:QueueLayout() end
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

function M:OnEnable()
    self:Attach()
    if not self.map then
        self:OnGameEvent("ADDON_LOADED", function()
            if not self.map and _G.WorldMapFrame then self:Attach(); self:OnEnable() end
        end)
        return
    end
    self.map:AddDataProvider(self.provider)
    self.layer:Show()
    self.menu:Show()
    self.menu:SetValue(self:MenuValue())
    self:PlaceFilters()
    -- what you can pick up changes as you level and turn quests in
    for _, event in ipairs({ "QUEST_TURNED_IN", "QUEST_ACCEPTED", "QUEST_REMOVED", "PLAYER_LEVEL_UP" }) do
        self:OnGameEvent(event, function() if self.map:IsShown() then C_Timer.After(0.2, function() self:Refresh() end) end end)
    end
end

function M:OnDisable()
    local f = self.map
    if not f then return end
    f:RemoveDataProvider(self.provider)
    self.items = nil
    self:ClearPins()
    self.layer:Hide()
    self.menu:Hide()
    local track = f.WorldMapTrackingOptionsButton
    if track then track:SetAlpha(1); track:EnableMouse(true) end
end
