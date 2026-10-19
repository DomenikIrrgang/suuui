-- Diagnostics/ProfessionProbe.lua
-- "/suu probe professions": what Forever's professions give an addon, for
-- SuuUI's own Professions window (step 3.3). Saved in
-- SuuUIProbe.professions[skillLine] on /reload, one per profession probed.
--   * your professions (GetProfessions, GetProfessionInfo) and each one's
--     spells in the spellbook (Find Herbs, Fishing, Basic Campfire)
--   * the open trade skill (C_TradeSkillUI): which one, ready, its recipes'
--     info, categories, schematics (reagents and products), requirements
--     (tools), cooldowns, tracked, descriptions, sources (where an unlearned
--     one is learned); your counts of the reagents
--   * every recipe of the open trade skill in one line (id, name, category,
--     learned, skill line ability, grey level; Forever's recipe info has no
--     yellow level)
--   * C_TradeSkillUI's functions
--
--   /suu probe professions   with a profession's window open (cooking, first
--                            aid, a crafting one), then /reload

local _, ns = ...

local PP = {}
ns.ProfessionProbe = PP

local isSecret = issecretvalue or function() return false end

local function show(v, depth)
    depth = depth or 0
    if isSecret(v) then return "secret" end
    if v == nil then return "nil" end
    if type(v) == "table" then
        if depth > 3 then return "{…}" end
        local parts = {}
        for k, x in pairs(v) do
            parts[#parts + 1] = tostring(k) .. "=" .. show(x, depth + 1)
            if #parts > 40 then break end
        end
        table.sort(parts)
        return "{" .. table.concat(parts, ", ") .. "}"
    end
    return tostring(v)
end

local function call(fn, ...)
    if type(fn) ~= "function" then return "missing" end
    local res = { pcall(fn, ...) }
    if not res[1] then return "error: " .. tostring(res[2]):sub(1, 160) end
    local parts = {}
    for i = 2, math.max(2, select("#", unpack(res))) do parts[#parts + 1] = show(res[i]) end
    return table.concat(parts, " | ")
end

local function raw(fn, ...)
    if type(fn) ~= "function" then return nil end
    local res = { pcall(fn, ...) }
    if res[1] then return select(2, unpack(res)) end
end

local function namesIn(t)
    local out = {}
    if type(t) ~= "table" then return { "missing" } end
    for k, v in pairs(t) do if type(k) == "string" and type(v) == "function" then out[#out + 1] = k end end
    table.sort(out)
    return out
end

function PP.Sample()
    SuuUIProbe = SuuUIProbe or {}
    local store = { at = date("%Y-%m-%d %H:%M:%S"), level = UnitLevel("player"), class = select(2, UnitClass("player")) }
    -- one per profession (its skill line), so each open window keeps its own;
    -- a probe from before that layout (a single one) is dropped
    local saved = SuuUIProbe.professions
    if type(saved) ~= "table" or saved.at then saved = {} end
    SuuUIProbe.professions = saved
    store.api = namesIn(C_TradeSkillUI)
    -- your professions
    local list = { raw(GetProfessions) }
    store.professions = {}
    for slot = 1, 6 do
        local index = list[slot]
        local p = { slot = slot, index = show(index) }
        if index then
            local name, icon, skill, maxSkill, numAbilities, offset, skillLine, mod, spec, specOffset = raw(GetProfessionInfo, index)
            p.info = ("name=%s icon=%s skill=%s/%s abilities=%s offset=%s skillLine=%s mod=%s spec=%s specOffset=%s"):format(
                show(name), show(icon), show(skill), show(maxSkill), show(numAbilities), show(offset), show(skillLine), show(mod), show(spec), show(specOffset))
            p.bySkillLine = call(C_TradeSkillUI.GetProfessionInfoBySkillLineID, skillLine)
            p.spells = {}
            for k = 1, (tonumber(numAbilities) or 0) do
                local slotIndex = (tonumber(offset) or 0) + k
                p.spells[#p.spells + 1] = call(C_SpellBook.GetSpellBookItemInfo, slotIndex, Enum.SpellBookSpellBank.Player)
            end
        end
        store.professions[#store.professions + 1] = p
    end
    -- the open trade skill
    store.ready = call(C_TradeSkillUI.IsTradeSkillReady)
    store.base = call(C_TradeSkillUI.GetBaseProfessionInfo)
    local base = raw(C_TradeSkillUI.GetBaseProfessionInfo)
    store.name = base and base.professionName
    saved[base and base.professionID or 0] = store
    store.child = call(C_TradeSkillUI.GetChildProfessionInfo)
    store.isNPC = call(C_TradeSkillUI.IsNPCCrafting)
    store.isGuild = call(C_TradeSkillUI.IsTradeSkillGuild)
    store.linked = call(C_TradeSkillUI.IsTradeSkillLinked)
    store.canShow = call(C_TradeSkillUI.CanTradeSkillShowCraftingUI)
    local ids = raw(C_TradeSkillUI.GetAllRecipeIDs) or {}
    local filtered = raw(C_TradeSkillUI.GetFilteredRecipeIDs) or {}
    store.recipeCount, store.filteredCount = #ids, #filtered
    store.categories = {}
    local cats = { raw(C_TradeSkillUI.GetCategories) }
    for _, c in ipairs(cats) do
        if #store.categories < 30 then store.categories[#store.categories + 1] = show(c) .. " " .. call(C_TradeSkillUI.GetCategoryInfo, c) end
    end
    -- every recipe's category up to its header, and how many under each
    -- and every recipe, one line each: id|name|category|learned|ability|grey
    store.tree, store.perRoot, store.all = {}, {}, {}
    local seenCat = {}
    for _, id in ipairs(ids) do
        local info = raw(C_TradeSkillUI.GetRecipeInfo, id)
        if info then
            store.all[#store.all + 1] = ("%d|%s|%d|%d|%d|%d"):format(id, show(info.name), tonumber(info.categoryID) or 0,
                info.learned and 1 or 0, tonumber(info.skillLineAbilityID) or 0,
                tonumber(info.maxTrivialLevel) or 0)
        else
            store.all[#store.all + 1] = ("%d|nil"):format(id)
        end
        local cat = info and info.categoryID
        local chain, root = {}, nil
        local guard = 0
        while cat and cat ~= 0 and guard < 8 do
            local ci = raw(C_TradeSkillUI.GetCategoryInfo, cat)
            if not ci then break end
            if not seenCat[cat] then
                seenCat[cat] = true
                if #store.tree < 120 then store.tree[#store.tree + 1] = show(cat) .. " " .. show(ci) end
            end
            root = ci.name
            chain[#chain + 1] = cat
            cat = ci.parentCategoryID
            guard = guard + 1
        end
        local key = tostring(root) .. (info and info.learned and " learned" or "")
        store.perRoot[key] = (store.perRoot[key] or 0) + 1
        -- duplicates by name, disabled ones, past the level-60 range
        if info then
            local r = tostring(root)
            store.names = store.names or {}
            store.names[r] = store.names[r] or {}
            local seen = store.names[r]
            if seen[info.name] then
                store.perRoot[r .. " duplicate names"] = (store.perRoot[r .. " duplicate names"] or 0) + 1
                store.dupes = store.dupes or {}
                if #store.dupes < 40 then store.dupes[#store.dupes + 1] = ("%s: %s and %s"):format(info.name, show(seen[info.name]), show(id)) end
            else
                seen[info.name] = id
            end
            if info.disabled then store.perRoot[r .. " disabled"] = (store.perRoot[r .. " disabled"] or 0) + 1 end
            if (info.maxTrivialLevel or 0) > 300 then store.perRoot[r .. " trivial past 300"] = (store.perRoot[r .. " trivial past 300"] or 0) + 1 end
            if (info.itemLevel or 0) > 70 then store.perRoot[r .. " item level past 70"] = (store.perRoot[r .. " item level past 70"] or 0) + 1 end
        end
    end
    store.names = nil
    store.recipes = {}
    for i, id in ipairs(ids) do
        if i > 25 then break end
        local r = { id = id }
        r.info = call(C_TradeSkillUI.GetRecipeInfo, id)
        r.schematic = call(C_TradeSkillUI.GetRecipeSchematic, id, false)
        r.requirements = call(C_TradeSkillUI.GetRecipeRequirements, id)
        r.cooldown = call(C_TradeSkillUI.GetRecipeCooldown, id)
        r.tracked = call(C_TradeSkillUI.IsRecipeTracked, id, false)
        r.description = call(C_TradeSkillUI.GetRecipeDescription, id, {})
        r.outputLink = call(C_TradeSkillUI.GetRecipeItemLink, id)
        r.numMade = call(C_TradeSkillUI.GetRecipeNumItemsProduced, id)
        r.tools = call(C_TradeSkillUI.GetRecipeTools, id)
        r.source = call(C_TradeSkillUI.GetRecipeSourceText, id)
        -- your counts of its reagents
        local sch = raw(C_TradeSkillUI.GetRecipeSchematic, id, false)
        local counts = {}
        for _, slot in ipairs(sch and sch.reagentSlotSchematics or {}) do
            local reagent = slot.reagents and slot.reagents[1]
            local itemID = reagent and reagent.itemID
            if itemID then
                counts[#counts + 1] = ("%s x%s have=%s name=%s"):format(show(itemID), show(slot.quantityRequired),
                    call(C_Item.GetItemCount, itemID, true, false, true), show(raw(C_Item.GetItemNameByID, itemID)))
            end
        end
        r.counts = counts
        store.recipes[#store.recipes + 1] = r
    end
    return store
end

function PP.Command()
    local store = PP.Sample()
    ns.Print(("Profession probe: %s, %d recipes saved (ready: %s). /reload to save."):format(
        tostring(store.name or "no profession window open"), #store.all, tostring(store.ready)))
end
