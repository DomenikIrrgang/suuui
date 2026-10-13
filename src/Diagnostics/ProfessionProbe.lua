-- Diagnostics/ProfessionProbe.lua
-- "/suu probe professions": what Forever's professions give an addon, for
-- SuuUI's own Professions window (step 3.3). Saved in SuuUIProbe.professions
-- on /reload.
--   * your professions (GetProfessions, GetProfessionInfo) and each one's
--     spells in the spellbook (Find Herbs, Fishing, Basic Campfire)
--   * the open trade skill (C_TradeSkillUI): which one, ready, its recipes'
--     info, categories, schematics (reagents and products), requirements
--     (tools), cooldowns, tracked, descriptions; your counts of the reagents
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
    SuuUIProbe.professions = store
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
    ns.Print(("Profession probe: %d professions, %d recipes in the open window (ready: %s). /reload to save."):format(
        #store.professions, store.recipeCount or 0, tostring(store.ready)))
end
