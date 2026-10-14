-- Units/Professions.lua
-- SuuUI's Professions pages (step 3.3, design boards "Professions ·
-- Overview" and "Professions · Alchemy") over Blizzard's professions window,
-- the way the Legacy pages sit over theirs: K, the micro menu, Esc and the
-- trade skill's own opening and closing stay Blizzard's, the window is in
-- SuuUI's look (the windows module), and Blizzard's pages and tabs are off
-- screen (still shown: they drive this one).
--   overview  your primary and secondary professions: rank, skill, their
--             spells (a tracking spell toggles its tracking)
--   crafting  the open trade skill's recipes (C_TradeSkillUI): by category,
--             searched and filtered, and the chosen one: reagents, tools,
--             cooldown, Track, Create (CraftRecipe)
-- The rail switches pages: the overview is SuuUI's own; a profession opens
-- its trade skill (C_TradeSkillUI.OpenTradeSkill).
-- A built-in module written against the public API only.

local UI, T = SuuUI.UI, SuuUI.Tokens

local M = SuuUI.RegisterModule({
    id = "professions",
    name = "Professions",
    description = "SuuUI's Professions pages: your professions at a glance, and the recipes of the one you open.",
    api = "0.12",
    reloadToToggle = true,
    defaults = {},
})

local isSecret = issecretvalue or function() return false end
local function plain(v) return v ~= nil and not isSecret(v) end

local function call(fn, ...)
    if type(fn) ~= "function" then return nil end
    local ok, a, b, c, d, e, f, g, h, i, j, k = pcall(fn, ...)
    if ok then return a, b, c, d, e, f, g, h, i, j, k end
end

local W, H = 720, 600

-- "a" or "an" before a word, by its first letter's sound ("an Engineering
-- trainer", "a Blacksmithing trainer"; asked for in game)
local function article(word)
    return (word or ""):match("^[AEIOUaeiou]") and "an" or "a"
end

-- "1 more vendor", "3 more vendors"
local function more(n, noun)
    return "and " .. n .. " more " .. noun .. (n == 1 and "" or "s")
end
local QUALITY_NAME = { [0] = "poor", "common", "uncommon", "rare", "epic", "legendary" }
-- the rank a skill cap stands for (a profession's first spell says it too)
local RANKS = { [75] = "Apprentice", [150] = "Journeyman", [225] = "Expert", [300] = "Artisan" }

--------------------------------------------------------------------------------
-- Your professions
--------------------------------------------------------------------------------

-- Tracking (Find Minerals, Find Herbs): the minimap's list, by spell or name.
local function trackingFor(spellID, name)
    local mm = C_Minimap
    if not (mm and mm.GetNumTrackingTypes and mm.GetTrackingInfo) then return nil end
    for i = 1, (call(mm.GetNumTrackingTypes) or 0) do
        local a, _, c, _, _, f = call(mm.GetTrackingInfo, i)
        local tName, active, tSpell
        if type(a) == "table" then
            tName, active, tSpell = a.name, a.active, a.spellID
        else
            tName, active, tSpell = a, c, f
        end
        if (spellID and tSpell == spellID) or (name and tName == name) then return i, active and true or false end
    end
end

function M:Profession(index)
    if not index then return nil end
    local name, icon, skill, max, numSpells, offset, skillLine = call(GetProfessionInfo, index)
    if not plain(name) then return nil end
    local card = { name = name, icon = icon, skill = skill, max = max, skillLine = skillLine, spells = {} }
    local bank = Enum.SpellBookSpellBank and Enum.SpellBookSpellBank.Player
    local own, ownCrafts, craftSpell
    for k = 1, (tonumber(numSpells) or 0) do
        local info = call(C_SpellBook.GetSpellBookItemInfo, (tonumber(offset) or 0) + k, bank)
        if info and info.spellID then
            -- the profession's own spell: the one with its name (Skinning,
            -- Fishing, Blacksmithing), else the one that opens its crafting
            -- window (Smelting for Mining). Not the first, nor any crafting
            -- one: on Forever the camp abilities (Tanning, Bait and Tackle)
            -- come first and open the crafting window too (found in game)
            local crafts = call(C_TradeSkillUI.CanTradeSkillShowCraftingUI, info.spellID) and true or false
            card.crafting = card.crafting or crafts
            if not info.isPassive then
                if info.name == name then
                    own, ownCrafts = info, crafts
                elseif crafts and not craftSpell then
                    craftSpell = info
                end
            end
            local spell = { name = info.name, icon = info.iconID, spellID = info.spellID }
            local track, on = trackingFor(info.spellID, info.name)
            if track then
                spell.active = on
                spell.onClick = function()
                    call(C_Minimap.SetTracking, track, not on)
                    self:QueueRender()
                end
            end
            spell.onEnter = function(owner) UI.SpellTooltip(owner, info.spellID) end
            spell.onLeave = function() GameTooltip:Hide() end
            spell.onDrag = function() self:Pickup(info.spellID) end
            card.spells[#card.spells + 1] = spell
        end
    end
    if own and own.subName and own.subName ~= "" then card.rank = own.subName end
    card.rank = card.rank or RANKS[max] or ""
    -- the card dragged onto a bar opens the profession's window, as
    -- Blacksmithing's own spell does: its own spell, else the spell that
    -- opens it (Mining: Smelting). When a spell with the profession's name
    -- only casts (Fishing, Skinning) and another opens the window (Bait and
    -- Tackle, Tanning), a macro with the profession's name and icon that
    -- casts the opener (asked for in game: the default UI can't either)
    if own and ownCrafts then
        card.spellID = own.spellID
        local id = own.spellID
        card.onDrag = function() self:Pickup(id) end
    elseif own and craftSpell then
        card.spellID = craftSpell.spellID
        local opener = craftSpell.spellID
        card.onDrag = function() self:PickupOpener(name, icon, opener) end
    elseif craftSpell then
        card.spellID = craftSpell.spellID
        local id = craftSpell.spellID
        card.onDrag = function() self:Pickup(id) end
    elseif own then
        card.spellID = own.spellID
        local id = own.spellID
        card.onDrag = function() self:Pickup(id) end
    end
    -- unlearning: SuuUI's confirmation, then the game's (M:Unlearn)
    if skillLine then
        card.onUnlearn = function() self:Unlearn(name, skillLine) end
    end
    -- its recipes, as counted when it was last open
    local counts = skillLine and self:CharData().recipes
    card.recipes = counts and counts[skillLine]
    -- every spell stays listed, its own included (Fishing was missing
    -- under Fishing: found in game)
    return card
end

-- Unlearning: SuuUI's modal confirmation (asked for in game), then the
-- game's C_SkillInfo.AbandonSkill.
function M:Unlearn(name, skillLine)
    UI.Confirm({
        title = "Unlearn " .. name .. "?",
        text = "You lose your " .. name .. " skill and every " .. name .. " recipe you know. If you learn it again, you start at 1.",
        confirm = "Unlearn",
        cancel = "Keep it",
        -- as the game's own asks (found in game)
        typeToConfirm = "UNLEARN",
        onConfirm = function()
            -- Forever's is C_SkillInfo.AbandonSkill (the old global is
            -- gone: "attempt to call a nil value", /suu probe unlearn)
            local abandon = (C_SkillInfo and C_SkillInfo.AbandonSkill) or AbandonSkill
            local ok, err = pcall(abandon, skillLine)
            if not ok then self:Print(name .. " couldn't be unlearned: " .. tostring(err)) end
            self:QueueRender()
        end,
    })
end

-- The secondary professions, always shown, learned or not (as Blizzard's
-- book does: asked for in game), in its order.
local SECONDARY = {
    { skillLine = 185, name = "Cooking", icon = 133971 },
    { skillLine = 356, name = "Fishing", icon = 136245 },
    { skillLine = 129, name = "First Aid", icon = 135966 },
}
local EMPTY_ICON = 134939 -- INV_Scroll_04, Blizzard's empty slot

local function untrained(def)
    local name = def.name
    local shown = call(C_TradeSkillUI.GetTradeSkillDisplayName, def.skillLine)
    if plain(shown) and shown ~= "" then name = shown end
    return { name = name, icon = call(C_TradeSkillUI.GetTradeSkillTexture, def.skillLine) or def.icon,
             skillLine = def.skillLine, untrained = true, rank = "Not learned",
             hint = "Learn it from " .. article(name) .. " " .. name .. " trainer" }
end

-- A profession's spell on the cursor, to put on an action bar.
function M:Pickup(spellID)
    if not spellID then return end
    if C_Spell and C_Spell.PickupSpell then
        C_Spell.PickupSpell(spellID)
    elseif PickupSpell then
        PickupSpell(spellID)
    end
end

-- A character macro that opens a profession's window by casting the spell
-- that does, under the profession's name and icon; one already made (same
-- text) is used again.
function M:PickupOpener(name, icon, spellID)
    local spell = call(C_Spell.GetSpellName, spellID)
    if not spell then return end
    local body = "/cast " .. spell
    local first = (MAX_ACCOUNT_MACROS or 120) + 1
    local _, chars = GetNumMacros()
    for i = first, first + (chars or 0) - 1 do
        if GetMacroBody(i) and strtrim(GetMacroBody(i)) == body then
            PickupMacro(i)
            return
        end
    end
    if InCombatLockdown() then self:Print("Macros can't be made in combat. Drag it again after the fight.") return end
    local ok, index = pcall(CreateMacro, name:sub(1, 16), icon or 134400, body, true)
    if not ok or not index then
        self:Print("No free character macro slot for " .. name .. ".")
        return
    end
    PickupMacro(index)
end

-- Primary (two slots, an empty one says how to fill it), then secondary.
-- By skill line, not by GetProfessions' slots (Forever's order is its own:
-- First Aid third).
function M:Professions()
    local out = { primary = {}, secondary = {} }
    local learned = {}
    local slots = { call(GetProfessions) }
    for i = 1, 6 do
        local c = self:Profession(slots[i])
        if c and c.skillLine and not learned[c.skillLine] then
            learned[c.skillLine] = c
            local secondary = false
            for _, def in ipairs(SECONDARY) do if def.skillLine == c.skillLine then secondary = true end end
            if not secondary then out.primary[#out.primary + 1] = c end
        end
    end
    for i = #out.primary + 1, 2 do
        out.primary[i] = { name = "Primary profession", icon = EMPTY_ICON, untrained = true, rank = "Not learned",
                           hint = "Learn one from a profession trainer" }
    end
    for _, def in ipairs(SECONDARY) do out.secondary[#out.secondary + 1] = learned[def.skillLine] or untrained(def) end
    return out
end

--------------------------------------------------------------------------------
-- The open trade skill
--------------------------------------------------------------------------------

local function itemCount(itemID)
    return call(C_Item.GetItemCount, itemID) or 0
end

-- The reagents a recipe needs (the required slots) and how many times you
-- can make it from your bags.
function M:Reagents(id)
    local sch = call(C_TradeSkillUI.GetRecipeSchematic, id, false)
    local list, can = {}, math.huge
    for _, slot in ipairs(sch and sch.reagentSlotSchematics or {}) do
        local reagent = slot.reagents and slot.reagents[1]
        if reagent and reagent.itemID and slot.required ~= false then
            local need = slot.quantityRequired or 1
            local have = itemCount(reagent.itemID)
            list[#list + 1] = { itemID = reagent.itemID, need = need, have = have }
            can = math.min(can, math.floor(have / math.max(1, need)))
        end
    end
    if can == math.huge then can = 0 end
    return list, can, sch
end

-- The header a category sits under (GetCategoryInfo's parentCategoryID up
-- to the top).
function M:RootOf(catID)
    self.roots = self.roots or {}
    if self.roots[catID] ~= nil then return self.roots[catID] end
    local id, root, guard = catID, false, 0
    while id and id ~= 0 and guard < 8 do
        local ci = call(C_TradeSkillUI.GetCategoryInfo, id)
        if not ci then break end
        root = ci
        id = ci.parentCategoryID
        guard = guard + 1
    end
    self.roots[catID] = root
    return root
end

-- A recipe of this game: in a category, and not under another header than
-- the profession's own. Forever's lists carry Season of Discovery's recipes
-- under their own header (Blacksmithing: 507 recipes, probed 2026-10-14),
-- which this realm doesn't have, and one of them in no category at all
-- (Mining's Smelt Obsidian-Infused Thorium Bar, the only recipe without one
-- across all twelve professions).
function M:InGame(info, profession)
    if not info.categoryID or info.categoryID == 0 then return false end
    local root = self:RootOf(info.categoryID)
    if not root or root.type ~= "header" or not profession then return true end
    return root.name == profession
end

-- The game's relativeDifficulty (0 optimal .. 3 trivial) as the filter's keys.
local DIFFICULTY_KEYS = { [0] = "optimal", "medium", "easy", "trivial" }

-- The skill a recipe requires: its recipe item's, the trainers' (this
-- account's recordings first, else the shipped data); nil if not known.
function M:SkillFor(id, profession, name)
    local need
    local mine = self:Recorded(profession, name)
    for _, src in ipairs(SuuUI.RecipeSources(id) or {}) do
        local skill = src.s
        if src.t == "t" and mine and mine.skill then skill = mine.skill end
        if skill and (not need or skill < need) then need = skill end
    end
    if not need and mine and mine.skill then need = mine.skill end
    return need
end

-- The level the item a recipe makes requires; nil when it makes none or
-- the item isn't loaded yet (asked for, then sorted again).
function M:UseLevel(id)
    local sch = call(C_TradeSkillUI.GetRecipeSchematic, id, false)
    local out = sch and sch.outputItemID
    if not out then return nil end
    local name, _, _, _, minLevel = call(C_Item.GetItemInfo, out)
    if not name then
        self.waitingItems = true
        call(C_Item.RequestLoadItemDataByID, out)
        return nil
    end
    return minLevel or 0
end

function M:Recipes()
    local base = call(C_TradeSkillUI.GetBaseProfessionInfo) or {}
    local data = { name = base.professionName, skill = base.skillLevel, max = base.maxSkillLevel,
                   skillLine = base.professionID }  -- no rank here: the overview has it (asked for in game)
    local cats, byCat = {}, {}
    local search = self.search and self.search ~= "" and self.search:lower() or nil
    -- the filters (FilterMenu groups): show one of all/learned/unlearned;
    -- difficulty and product quality, none chosen = any; other toggles
    local f = self.filters or UI.PROFESSION_FILTER_DEFAULTS
    local function set(list)
        local out = {}
        for _, v in ipairs(list or {}) do out[v] = true end
        return out
    end
    local difficulties, qualities, other = set(f.difficulty), set(f.quality), set(f.other)
    local anyDifficulty, anyQuality = next(difficulties) == nil, next(qualities) == nil
    local first
    local learned, total = 0, 0
    for _, id in ipairs(call(C_TradeSkillUI.GetAllRecipeIDs) or {}) do
        local info = call(C_TradeSkillUI.GetRecipeInfo, id)
        if info and plain(info.name) and not info.isDummyRecipe and self:InGame(info, data.name) then
            total = total + 1
            if info.learned then learned = learned + 1 end
            local _, can = self:Reagents(id)
            local diff = info.relativeDifficulty or 3
            -- the product's quality is in the recipe's link ("|cnIQ3:")
            local quality = type(info.hyperlink) == "string" and tonumber(info.hyperlink:match("IQ(%d)")) or nil
            local keep = (f.show ~= "learned" or info.learned)
                and (f.show ~= "unlearned" or not info.learned)
                and (anyDifficulty or difficulties[DIFFICULTY_KEYS[diff] or "trivial"])
                and (anyQuality or (quality ~= nil and qualities[quality]))
                and (not other.materials or can > 0)
                and (not other.skillup or (info.canSkillUp ~= false and diff < 3 and info.learned))
                and (not search or info.name:lower():find(search, 1, true))
            if keep then
                local catID = info.categoryID or 0
                local cat = byCat[catID]
                if not cat then
                    local ci = catID ~= 0 and call(C_TradeSkillUI.GetCategoryInfo, catID)
                    cat = { name = (ci and ci.name) or "Other", order = (ci and ci.uiOrder) or 9999, recipes = {} }
                    byCat[catID] = cat
                    cats[#cats + 1] = cat
                end
                cat.recipes[#cat.recipes + 1] = { id = id, name = info.name, difficulty = diff, canMake = can,
                    learned = info.learned and true or false, tracked = call(C_TradeSkillUI.IsRecipeTracked, id, false) and true or false,
                    need = (self.sort == "skill" or self.sort == "level") and self:SkillFor(id, data.name, info.name) or nil,
                    use = self.sort == "level" and self:UseLevel(id) or nil }
                first = first or id
            end
        end
    end
    table.sort(cats, function(a, b) if a.order ~= b.order then return a.order < b.order end return a.name < b.name end)
    -- the sort orders recipes inside their categories, which stay
    local sort = self.sort or "category"
    local function byName(a, b) return a.name < b.name end
    local orders = {
        category = function(a, b)
            if a.learned ~= b.learned then return a.learned end
            if a.difficulty ~= b.difficulty then return a.difficulty < b.difficulty end
            return byName(a, b)
        end,
        difficulty = function(a, b)
            if a.difficulty ~= b.difficulty then return a.difficulty < b.difficulty end
            return byName(a, b)
        end,
        -- a skill not known yet goes last
        skill = function(a, b)
            local x, y = a.need or math.huge, b.need or math.huge
            if x ~= y then return x < y end
            return byName(a, b)
        end,
        -- the level the product needs to be used; none (enchants) or not
        -- loaded yet goes last
        -- the same level (level 0: reagents, tools): by the skill required
        -- (asked for in game), then the name
        level = function(a, b)
            local x, y = a.use or math.huge, b.use or math.huge
            if x ~= y then return x < y end
            x, y = a.need or math.huge, b.need or math.huge
            if x ~= y then return x < y end
            return byName(a, b)
        end,
        name = byName,
    }
    -- by category: each category's own; any other sort runs across them
    -- all, one list without headers (asked for in game)
    if sort ~= "category" and orders[sort] then
        local all = {}
        for _, cat in ipairs(cats) do
            for _, r in ipairs(cat.recipes) do all[#all + 1] = r end
        end
        cats = #all > 0 and { { recipes = all, flat = true } } or {}
    end
    for _, cat in ipairs(cats) do table.sort(cat.recipes, orders[sort] or orders.category) end
    data.categories = cats
    -- learned of all, kept for the overview (it can only ask the open one)
    if data.skillLine and total > 0 then
        data.recipes = { learned = learned, total = total }
        local saved = self:CharData()
        saved.recipes = saved.recipes or {}
        saved.recipes[data.skillLine] = data.recipes
    end
    -- the one chosen in this profession, else the first; a recipe asked for
    -- (SuuUI.OpenRecipe) when it's in the list
    local key = data.skillLine or 0
    if self.pendingRecipe then
        for _, cat in ipairs(cats) do
            for _, r in ipairs(cat.recipes) do
                if r.id == self.pendingRecipe then
                    self.chosen[key] = r.id
                    if cat.name then self.view.folded[cat.name] = nil end
                end
            end
        end
        if self.chosen[key] == self.pendingRecipe then self.pendingRecipe = nil end
    end
    local chosen = self.chosen[key]
    local found = false
    for _, cat in ipairs(cats) do for _, r in ipairs(cat.recipes) do if r.id == chosen then found = true end end end
    if not found then
        chosen = cats[1] and cats[1].recipes[1] and cats[1].recipes[1].id or nil
        self.chosen[key] = chosen
    end
    data.selected = chosen
    return data
end

local function itemTip(owner, itemID)
    if not itemID then return end
    GameTooltip:SetOwner(owner, "ANCHOR_RIGHT")
    GameTooltip:SetItemByID(itemID)
    GameTooltip:Show()
end

-- Where a recipe not learned yet is learned, from SuuUI's recipe data (the
-- game has none: GetRecipeSourceText is nil): its recipe item and where
-- that is (vendors of your faction, drops, chests, quests, packages), a
-- trainer, or that it isn't known yet.
local MY_FACTION = ({ Alliance = "A", Horde = "H" })[UnitFactionGroup("player") or ""]

local function inkText(s) return "|cff" .. T.color.ink.hex .. s .. "|r" end

local function place(name, zone)
    if zone and zone ~= "" then return inkText(name) .. ", " .. zone end
    return inkText(name)
end

-- What the trainers this account recorded teach (every character's), by
-- profession and recipe name: the skill and the trainers. Built once,
-- again after a new recording.
function M:Recorded(profession, recipe)
    if not self.recordedIndex then
        local index = {}
        for _, data in pairs(self:AllCharData()) do
            for _, rec in pairs(data.trainers or {}) do
                local faction = ({ Alliance = "A", Horde = "H" })[rec.faction or ""] or ""
                local where = (rec.npc or "?") .. "|" .. (rec.zone or "") .. "|" .. faction
                for _, sv in ipairs(rec.services or {}) do
                    if sv.name then
                        local key = (rec.profession or "") .. "\0" .. sv.name:lower()
                        local t = index[key] or { trainers = {} }
                        index[key] = t
                        if sv.rank and (not t.skill or sv.rank < t.skill) then t.skill = sv.rank end
                        if not tContains(t.trainers, where) then t.trainers[#t.trainers + 1] = where end
                    end
                end
            end
        end
        self.recordedIndex = index
    end
    return profession and recipe and self.recordedIndex[profession .. "\0" .. recipe:lower()]
end

function M:Source(id)
    local craft = self.view and self.view.craftData
    local profession = craft and craft.name
    -- the shipped data, with what this account's own characters recorded
    -- at trainers on top (it shows at once, before any update)
    local list = SuuUI.RecipeSources(id)
    local info = call(C_TradeSkillUI.GetRecipeInfo, id)
    local mine = self:Recorded(profession, info and info.name)
    if mine then
        local merged, found = {}, false
        for i, src in ipairs(list or {}) do
            if src.t == "t" then
                local names = {}
                for _, n in ipairs(mine.trainers) do names[#names + 1] = n end
                for _, n in ipairs(src.n or {}) do if not tContains(names, n) then names[#names + 1] = n end end
                merged[i] = { t = "t", s = mine.skill or src.s, n = names }
                found = true
            else
                merged[i] = src
            end
        end
        if not found then merged[#merged + 1] = { t = "t", s = mine.skill, n = mine.trainers } end
        list = merged
    end
    if not list then return { lines = { "Where this recipe is learned isn't known yet." } } end
    local out = { lines = {} }
    local lines = out.lines
    -- the skill it needs (on its recipe item, or recorded at trainers), as
    -- the game words it; ember while yours is short
    local need
    for _, s in ipairs(list) do if s.s and (not need or s.s < need) then need = s.s end end
    if need then
        local short = craft and (craft.skill or 0) < need
        lines[#lines + 1] = (short and "|cff" .. T.color["ember-text"].hex or "|cff" .. T.color.ink.hex)
            .. "Requires " .. (profession or "skill") .. " (" .. need .. ")|r"
    else
        -- a trainer recipe nobody has recorded yet (Forever's new ones)
        for _, s in ipairs(list) do
            if s.t == "t" then
                lines[#lines + 1] = "The skill it requires isn't known yet"
                break
            end
        end
    end
    for _, s in ipairs(list) do
        if s.t == "t" then
            -- any trainer of the profession: there are many, in every city
            -- (asked for in game: no names)
            lines[#lines + 1] = "From " .. (profession and (article(profession) .. " " .. profession .. " trainer") or "a profession trainer")
        elseif s.t == "a" then
            lines[#lines + 1] = "Learned automatically with the profession"
        elseif s.t == "i" and s.i then
            local name, _, quality, _, _, _, _, _, _, icon = call(C_Item.GetItemInfo, s.i)
            if not name then self.waitingItems = true; call(C_Item.RequestLoadItemDataByID, s.i) end
            local have = call(C_Item.GetItemCount, s.i, true) or 0
            local itemID = s.i
            out.item = { icon = icon or call(C_Item.GetItemIconByID, s.i), name = name, quality = quality,
                         qualityName = quality and QUALITY_NAME[quality], note = have > 0 and "In your bags" or nil,
                         onEnter = function(owner) itemTip(owner, itemID) end }
            local known = false
            -- vendors: yours, else say the other faction's sell it
            local mine, theirs = {}, 0
            for _, v in ipairs(s.v or {}) do
                local vName, zone, faction = strsplit("|", v)
                if faction == "" or not MY_FACTION or faction:find(MY_FACTION, 1, true) then
                    mine[#mine + 1] = place(vName, zone)
                else
                    theirs = theirs + 1
                end
            end
            for i = 1, math.min(3, #mine) do lines[#lines + 1] = "Sold by " .. mine[i] end
            if #mine > 3 then lines[#lines + 1] = more(#mine - 3, "vendor") end
            if #mine == 0 and theirs > 0 then lines[#lines + 1] = "Sold only by the other faction's vendors" end
            known = known or #mine > 0 or theirs > 0
            -- drops: the first two, how many more
            local drops = s.d or {}
            local total = s.dn or #drops
            if total > 8 then
                lines[#lines + 1] = ("A world drop from %d creatures, such as %s"):format(total, place(strsplit("|", drops[1] or "")))
            else
                for i = 1, math.min(2, #drops) do
                    local dName, zone = strsplit("|", drops[i])
                    lines[#lines + 1] = "Dropped by " .. place(dName, zone)
                end
                if total > 2 then lines[#lines + 1] = more(total - 2, "creature") end
            end
            known = known or total > 0
            for i, o in ipairs(s.o or {}) do
                if i > 2 then break end
                local oName, zone = strsplit("|", o)
                lines[#lines + 1] = "Found in " .. place(oName, zone)
                known = true
            end
            for _, q in ipairs(s.q or {}) do
                local title = call(C_QuestLog.GetTitleForQuestID, q)
                if not title then call(C_QuestLog.RequestLoadQuestByID, q) end
                lines[#lines + 1] = "Rewarded by the quest " .. inkText(title or ("#" .. q))
                known = true
            end
            for _, c in ipairs(s.c or {}) do
                local cName = call(C_Item.GetItemNameByID, c)
                if not cName then self.waitingItems = true; call(C_Item.RequestLoadItemDataByID, c) end
                lines[#lines + 1] = "Inside " .. inkText(cName or "a container")
                known = true
            end
            if not known then lines[#lines + 1] = "Where to get it isn't known yet." end
        end
    end
    return out
end

function M:Recipe(id)
    if not id then return nil end
    local info = call(C_TradeSkillUI.GetRecipeInfo, id)
    if not info then return nil end
    local reagents, can, sch = self:Reagents(id)
    local r = { name = info.name, icon = info.icon, canMake = can, reagents = {}, tools = {} }
    local out = sch and sch.outputItemID
    if out then
        local name, _, quality, _, _, _, _, _, _, icon = call(C_Item.GetItemInfo, out)
        r.name = name or info.name
        r.quality = quality
        r.qualityName = quality and QUALITY_NAME[quality]
        r.icon = icon or info.icon
        if not name then self.waitingItems = true; call(C_Item.RequestLoadItemDataByID, out) end
        r.onProduct = function(owner) itemTip(owner, out) end
    else
        r.desc = call(C_TradeSkillUI.GetRecipeDescription, id, {})
    end
    local lo, hi = sch and sch.quantityMin, sch and sch.quantityMax
    if lo and hi and hi > 1 then r.makes = hi end
    for i, g in ipairs(reagents) do
        local name, _, quality, _, _, _, _, _, _, icon = call(C_Item.GetItemInfo, g.itemID)
        if not name then self.waitingItems = true; call(C_Item.RequestLoadItemDataByID, g.itemID) end
        r.reagents[i] = { name = name, icon = icon or call(C_Item.GetItemIconByID, g.itemID), quality = quality,
                          qualityName = quality and QUALITY_NAME[quality], have = g.have, need = g.need }
    end
    r.onReagent = function(i, owner) itemTip(owner, reagents[i] and reagents[i].itemID) end
    local toolsMet = true
    -- one line per tool: the game can list one twice (Hoof-Shaped Foot
    -- Pedal: Arclight Spanner, found in game); met if any of them is
    local byName = {}
    for _, t in ipairs(call(C_TradeSkillUI.GetRecipeRequirements, id) or {}) do
        local line = t.name and byName[t.name]
        if line then
            line.met = line.met or (t.met and true or false)
        else
            line = { name = t.name, met = t.met and true or false }
            r.tools[#r.tools + 1] = line
            if t.name then byName[t.name] = line end
        end
    end
    for _, t in ipairs(r.tools) do if not t.met then toolsMet = false end end
    local cd = call(C_TradeSkillUI.GetRecipeCooldown, id)
    if cd and cd > 0 then r.cooldown = SecondsToTime and SecondsToTime(cd) or (math.ceil(cd) .. " s") end
    r.tracked = call(C_TradeSkillUI.IsRecipeTracked, id, false) and true or false
    if not info.learned then
        r.source = self:Source(id)
        r.why = "Not learned yet"
    elseif r.cooldown then
        r.why = "On cooldown"
    elseif not toolsMet then
        r.why = "Requires " .. (r.tools[1] and r.tools[1].name or "a tool")
    elseif can <= 0 then
        r.why = "Missing reagents"
    end
    r.ready = r.why == nil
    return r
end

--------------------------------------------------------------------------------
-- The page
--------------------------------------------------------------------------------

function M:Tabs(profs)
    local tabs = { { key = "overview", label = "Overview", icon = "Interface\\ICONS\\INV_SideTab_Professions_c60" } }
    for _, list in ipairs({ profs.primary, profs.secondary }) do
        for _, c in ipairs(list) do
            if c.crafting then tabs[#tabs + 1] = { key = c.skillLine, label = c.name, icon = c.icon, card = c } end
        end
    end
    return tabs
end

function M:Render()
    local view = self.view
    if not (view and view:IsVisible()) then return end
    self.waitingItems = false
    local profs = self:Professions()
    self.tabList = self:Tabs(profs)
    local crafting = self.mode == "crafting" and call(C_TradeSkillUI.IsTradeSkillReady)
    if crafting then
        local data = self:Recipes()
        view:SetTabs(self.tabList, data.skillLine)
        view:SetCrafting(data)
        view:SetRecipe(self:Recipe(data.selected))
    else
        view:SetTabs(self.tabList, "overview")
        view:SetOverview(profs)
    end
end

function M:QueueRender()
    if self.renderQueued then return end
    self.renderQueued = true
    C_Timer.After(0.1, function()
        self.renderQueued = nil
        if self:IsEnabled() then self:Render() end
    end)
end

-- A profession's recipes: its trade skill, opened (Blizzard's window then
-- shows its crafting page, and this one follows).
function M:Open(skillLine)
    local base = call(C_TradeSkillUI.GetBaseProfessionInfo)
    if base and base.professionID == skillLine and call(C_TradeSkillUI.IsTradeSkillReady) then
        self.mode = "crafting"
        self:Render()
        return
    end
    if InCombatLockdown() then self:Print("Professions open out of combat.") return end
    local ok, err = pcall(C_TradeSkillUI.OpenTradeSkill, skillLine)
    if not ok then self:Print("That profession couldn't be opened here: " .. tostring(err)) end
end

-- A link into the chat line being typed, or a new one opened with it.
function M:ToChat(link)
    local util = ChatFrameUtil
    local insert = (util and util.InsertLink) or ChatEdit_InsertLink
    if insert and insert(link) then return end
    local open = (util and util.OpenChat) or ChatFrame_OpenChat
    if open then open(link) end
end

-- A recipe opened (the tracker's click): its profession's window, and the
-- recipe chosen once its list is there.
-- Not C_TradeSkillUI.OpenRecipe: it's protected (an addon's call is
-- blocked, found in game); the profession's trade skill opened the way the
-- rail does, then the recipe chosen.
function M:OpenRecipe(recipeID)
    if not recipeID then return end
    if InCombatLockdown() then self:Print("Professions open out of combat.") return end
    self.pendingRecipe = recipeID
    local line, _, parent = call(C_TradeSkillUI.GetTradeSkillLineForRecipe, recipeID)
    local skillLine = (parent and parent ~= 0) and parent or line
    if not skillLine then
        self:Print("That recipe's profession couldn't be found.")
        return
    end
    self:Open(skillLine)
end

function M:Craft(count)
    local id = self.view and self.view.craftData and self.view.craftData.selected
    if not id or InCombatLockdown() then return end
    call(C_TradeSkillUI.CraftRecipe, id, math.max(1, count or 1))
end

function M:Wire(view)
    view.onTab = function(key)
        if key == "overview" then
            self.mode = "overview"
            self:Render()
        else
            self:Open(key)
        end
    end
    view.onOpen = function(card) if card.skillLine then self:Open(card.skillLine) end end
    view.onSelect = function(id)
        local key = view.craftData and view.craftData.skillLine or 0
        self.chosen[key] = id
        self:Render()
    end
    view.onRecipeEnter = function(rec, owner)
        local sch = call(C_TradeSkillUI.GetRecipeSchematic, rec.id, false)
        if sch and sch.outputItemID then itemTip(owner, sch.outputItemID) end
    end
    view.onSearch = function(text)
        self.search = text
        self:QueueRender()
    end
    -- the filters and the sort, kept for this character
    view.onFilters = function(value)
        self.filters = value
        self:CharData().filters = value
        self:Render()
    end
    view.onSort = function(key)
        self.sort = key
        self:CharData().sort = key
        self:Render()
    end
    view.onTrack = function(on)
        local id = view.craftData and view.craftData.selected
        if id then call(C_TradeSkillUI.SetRecipeTracked, id, on and true or false, false) end
        self:QueueRender()
    end
    view.onCreate = function(count) self:Craft(count) end
    view.onLink = function()
        local link = call(C_TradeSkillUI.GetTradeSkillListLink)
        if link then self:ToChat(link) else self:Print("This profession can't be linked here.") end
    end
    view.onLinkRecipe = function(id)
        local link = call(C_TradeSkillUI.GetRecipeLink, id)
        if link then self:ToChat(link) end
    end
    view.onCreateAll = function()
        local r = view.recipeData
        if r then self:Craft(r.canMake) end
    end
end

--------------------------------------------------------------------------------
-- Over Blizzard's window
--------------------------------------------------------------------------------

-- A Blizzard part out of sight: see-through and off screen, still shown,
-- and back off screen whenever Blizzard places it again. Out of combat (the
-- window may hold secure spell buttons).
function M:Away(part)
    if not part or self.awayParts[part] then return end
    self.awayParts[part] = true
    part:SetAlpha(0)
    local placing = false
    local function away()
        if InCombatLockdown() then self.awayAfterCombat = true return end
        placing = true
        part:ClearAllPoints()
        part:SetPoint("TOPLEFT", UIParent, "TOPRIGHT", 5000, 0)
        placing = false
    end
    self.awayFns[#self.awayFns + 1] = away
    away()
    hooksecurefunc(part, "SetPoint", function() if not placing then C_Timer.After(0, away) end end)
end

-- The window at SuuUI's size (Blizzard sizes it per page).
function M:Size()
    local f = _G.ProfessionsFrame
    if not f or InCombatLockdown() then return end
    if math.abs(f:GetWidth() - W) < 1 and math.abs(f:GetHeight() - H) < 1 then return end
    self.sizing = true
    f:SetSize(W, H)
    self.sizing = false
end

function M:Build()
    local f = _G.ProfessionsFrame
    if not f or self.view or InCombatLockdown() then return end
    self.awayParts, self.awayFns, self.chosen = {}, {}, {}
    local saved = self:CharData()
    self.filters, self.sort = saved.filters or UI.PROFESSION_FILTER_DEFAULTS, saved.sort or "category"
    local view = UI.Professions(f)
    view:SetPoint("TOPLEFT", f, "TOPLEFT", 20, -44)
    view:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -20, 16)
    view:SetFrameLevel(f:GetFrameLevel() + 100)
    view:EnableMouse(true) -- Blizzard's buttons underneath get no clicks
    self.view = view
    self:Wire(view)
    view:SetFilters(self.filters)
    view:SetSort(self.sort)
    -- Blizzard's pages and tabs out of sight
    self:Away(f.BookPage)
    self:Away(f.CraftingPage)
    self:Away(f.ProfessionsOverviewTab)
    for _, tab in ipairs(f.rightProfessionTabs or {}) do self:Away(tab) end
    self:Away(f.TabSystem)
    -- the page follows Blizzard's: its book is the overview, its crafting
    -- page the open trade skill
    local function follow()
        if f.CraftingPage and f.CraftingPage:IsShown() then self.mode = "crafting" else self.mode = "overview" end
        self:QueueRender()
    end
    for _, page in ipairs({ f.BookPage, f.CraftingPage }) do
        page:HookScript("OnShow", follow)
        page:HookScript("OnHide", follow)
    end
    follow()
    f:HookScript("OnShow", function() self:Size(); follow() end)
    f:HookScript("OnHide", function() GameTooltip:Hide() end)
    local function again() if not self.sizing and f:IsShown() then C_Timer.After(0, function() self:Size() end) end end
    hooksecurefunc(f, "SetWidth", again)
    hooksecurefunc(f, "SetHeight", again)
    hooksecurefunc(f, "SetSize", again)
    view:HookScript("OnSizeChanged", function() if view:IsVisible() then self:QueueRender() end end)
    self:Size()
end

--------------------------------------------------------------------------------
-- Profession trainers, recorded: what each teaches and the skill it asks
-- for (the game keeps that on the server: no data file has it). Saved per
-- character (CharData().trainers, by the trainer's NPC ID), quietly: players
-- who send their SavedVariables help fill in the recipe data
-- (tools/merge_trainer_records.lua, tools/update_recipe_sources.sh).
--------------------------------------------------------------------------------

local PROFESSION_NAMES = {}
for _, n in ipairs({ "Alchemy", "Blacksmithing", "Enchanting", "Engineering", "Herbalism", "Leatherworking",
                     "Mining", "Skinning", "Tailoring", "Cooking", "First Aid", "Fishing" }) do PROFESSION_NAMES[n] = true end

function M:RecordTrainer()
    if self.recording or not GetNumTrainerServices then return end
    self.recording = true
    -- every service, not only what you can learn now; the trainer's own
    -- filters back afterwards
    local kinds, before = { "available", "unavailable", "used" }, {}
    if SetTrainerServiceTypeFilter then
        for _, k in ipairs(kinds) do
            before[k] = GetTrainerServiceTypeFilter and call(GetTrainerServiceTypeFilter, k)
            pcall(SetTrainerServiceTypeFilter, k, 1)
        end
    end
    local services, profession = {}, nil
    for i = 1, (call(GetNumTrainerServices) or 0) do
        -- this client answers name, availability, icon
        local name, a, b = call(GetTrainerServiceInfo, i)
        local kind = (a == "available" or a == "unavailable" or a == "used" or a == "header") and a or b
        if plain(name) and kind ~= "header" then
            local skillName, skillRank = call(GetTrainerServiceSkillReq, i)
            local link = GetTrainerServiceItemLink and call(GetTrainerServiceItemLink, i)
            local cost = call(GetTrainerServiceCost, i)
            local level = GetTrainerServiceLevelReq and call(GetTrainerServiceLevelReq, i)
            local line = GetTrainerServiceSkillLine and call(GetTrainerServiceSkillLine, i)
            if plain(skillName) and PROFESSION_NAMES[skillName] then profession = profession or skillName end
            if plain(line) and PROFESSION_NAMES[line] then profession = profession or line end
            services[#services + 1] = {
                name = name, skill = plain(skillName) and skillName or nil,
                rank = plain(skillRank) and tonumber(skillRank) or nil,
                cost = plain(cost) and tonumber(cost) or nil, level = plain(level) and tonumber(level) or nil,
                item = plain(link) and type(link) == "string" and tonumber(link:match("item:(%d+)")) or nil,
                line = plain(line) and line or nil,
            }
        end
    end
    if SetTrainerServiceTypeFilter then
        for _, k in ipairs(kinds) do
            if before[k] ~= nil then pcall(SetTrainerServiceTypeFilter, k, before[k] and 1 or 0) end
        end
    end
    self.recording = false
    -- a class trainer, a riding trainer: not ours (unless the game says
    -- it's a profession trainer and only the skill's name is missing)
    if not profession and IsTradeskillTrainer and call(IsTradeskillTrainer) then profession = "?" end
    if not profession or #services == 0 then return end
    local guid = UnitGUID("npc")
    local npcID = guid and tonumber((select(6, strsplit("-", guid))))
    local saved = self:CharData()
    saved.trainers = saved.trainers or {}
    self.recordedIndex = nil
    saved.trainers[npcID or UnitName("npc") or "?"] = {
        npc = UnitName("npc"), npcID = npcID, zone = GetRealZoneText(), subzone = GetSubZoneText(),
        faction = UnitFactionGroup("player"), profession = profession,
        at = date("%Y-%m-%d %H:%M"), services = services,
    }
end

function M:OnEnable()
    self:Build()
    self:OnGameEvent("ADDON_LOADED", function() self:Build() end)
    self:OnGameEvent("PLAYER_REGEN_ENABLED", function()
        if not self.view then self:Build() end
        if self.awayAfterCombat then
            self.awayAfterCombat = nil
            for _, fn in ipairs(self.awayFns or {}) do fn() end
        end
        self:Size()
    end)
    local valid = C_EventUtils and C_EventUtils.IsEventValid
    for _, e in ipairs({ "TRADE_SKILL_LIST_UPDATE", "TRADE_SKILL_DATA_SOURCE_CHANGED", "TRADE_SKILL_SHOW",
                         "TRADE_SKILL_CLOSE", "SKILL_LINES_CHANGED", "BAG_UPDATE_DELAYED", "TRACKED_RECIPE_UPDATE",
                         "MINIMAP_UPDATE_TRACKING", "NEW_RECIPE_LEARNED", "QUEST_DATA_LOAD_RESULT" }) do
        if not valid or valid(e) then
            self:OnGameEvent(e, function() if self.view and self.view:IsVisible() then self:QueueRender() end end)
        end
    end
    -- profession trainers: what they teach, recorded once they've listed it
    self:OnGameEvent("TRAINER_SHOW", function() C_Timer.After(0.3, function() self:RecordTrainer() end) end)
    -- item names the game hadn't loaded yet
    self:OnGameEvent("GET_ITEM_INFO_RECEIVED", function()
        if self.waitingItems and self.view and self.view:IsVisible() then self:QueueRender() end
    end)
end
