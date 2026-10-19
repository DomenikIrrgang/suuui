-- Diagnostics/TalentBuildProbe.lua
-- "/suu probe talentbuilds" (asked 2026-10-19: talent builds to save and
-- switch, plan ahead as a guide while levelling, share as text, per talent
-- group, and for other classes too, kept for the account): what Forever's
-- loadouts give an addon. Saved in SuuUIProbe.talentbuilds on /reload.
-- (Forever's API docs mark only C_ClassTalents.SwitchTo* as restricted; the
-- talents probe found one spec per class and its tree with cannotRefund.)
--
--   /suu probe talentbuilds          read only: the loadout functions and
--         what they return, your configs, the export string, talent groups
--         (dual spec), respec functions; every other class's tree, read with
--         your config and through the game's view loadout (and whether a
--         point can be planned there, undone at once)
--   /suu probe talentbuilds export   your talents as a text string; then
--         imported back as a new saved loadout and deleted again
--   /suu probe talentbuilds save     a new named loadout saved from your
--         talents, then deleted again
--   /suu probe talentbuilds switch   with two saved loadouts: load the
--         other and back (asks to run it twice: it may change your talents)
-- Every step records blocked actions, UI errors and the talent events. Not
-- in combat. Values the game hides read "secret".

local _, ns = ...

local TB = {}
ns.TalentBuildProbe = TB

local isSecret = issecretvalue or function() return false end

local function show(v)
    if isSecret(v) then return "secret" end
    if v == nil then return "nil" end
    if type(v) == "table" then
        local parts = {}
        for k, x in pairs(v) do
            local val
            if isSecret(x) then val = "secret"
            elseif type(x) == "table" then
                local inner = {}
                for k2, y in pairs(x) do
                    inner[#inner + 1] = tostring(k2) .. ":" .. (isSecret(y) and "secret" or type(y) == "table" and "{…}" or tostring(y))
                    if #inner > 8 then break end
                end
                val = "{" .. table.concat(inner, " ") .. "}"
            else val = tostring(x) end
            parts[#parts + 1] = tostring(k) .. "=" .. val
            if #parts > 24 then break end
        end
        table.sort(parts)
        return "{" .. table.concat(parts, ", ") .. "}"
    end
    return tostring(v)
end

-- every return as text ("missing" for no function, "error: …")
local function call(fn, ...)
    if type(fn) ~= "function" then return "missing" end
    local res = { pcall(fn, ...) }
    if not res[1] then return "error: " .. tostring(res[2]):sub(1, 160) end
    local parts = {}
    for i = 2, math.max(2, select("#", unpack(res))) do parts[#parts + 1] = show(res[i]) end
    return table.concat(parts, " | ")
end

-- the first return itself, or nil
local function get(fn, ...)
    if type(fn) ~= "function" then return nil end
    local ok, a, b = pcall(fn, ...)
    if ok then return a, b end
end

local function plain(v) return v ~= nil and not isSecret(v) end

local function push(list, line, most)
    if #list < (most or 60) then list[#list + 1] = line end
end

local function out()
    SuuUIProbe = SuuUIProbe or {}
    SuuUIProbe.talentbuilds = SuuUIProbe.talentbuilds or {}
    return SuuUIProbe.talentbuilds
end

local CT = C_ClassTalents or {}
local TR = C_Traits or {}

local VIEW_ID = Constants and Constants.TraitConsts and Constants.TraitConsts.VIEW_TRAIT_CONFIG_ID

--------------------------------------------------------------------------------
-- Watching: blocked actions, UI errors and the talent events
--------------------------------------------------------------------------------

local EVENTS = {
    "ADDON_ACTION_BLOCKED", "ADDON_ACTION_FORBIDDEN", "UI_ERROR_MESSAGE", "TRAIT_CONFIG_CREATED",
    "TRAIT_CONFIG_DELETED", "TRAIT_CONFIG_UPDATED", "TRAIT_CONFIG_LIST_UPDATED", "TRAIT_TREE_CHANGED",
    "ACTIVE_COMBAT_CONFIG_CHANGED", "CONFIG_COMMIT_FAILED", "PLAYER_TALENT_UPDATE", "ACTIVE_TALENT_GROUP_CHANGED",
    "PLAYER_SPECIALIZATION_CHANGED", "SELECTED_LOADOUT_CHANGED", "STARTER_BUILD_ACTIVATION_FAILED",
}

local watcher, step, t0
local createdIDs = {}

local function watch(name)
    local o = out()
    step = { at = date("%H:%M:%S"), events = {}, blocked = {}, steps = {} }
    o[name] = step
    t0 = GetTime()
    if not watcher then
        watcher = CreateFrame("Frame")
        for _, e in ipairs(EVENTS) do pcall(watcher.RegisterEvent, watcher, e) end
        watcher:SetScript("OnEvent", function(_, event, a, b)
            if not step then return end
            local line = ("%.2fs %s %s %s"):format(GetTime() - t0, event, show(a), show(b))
            push(step.events, line, 80)
            if event == "ADDON_ACTION_BLOCKED" or event == "ADDON_ACTION_FORBIDDEN" or event == "UI_ERROR_MESSAGE"
                or event == "CONFIG_COMMIT_FAILED" then
                push(step.blocked, line, 20)
            end
            if event == "TRAIT_CONFIG_CREATED" and type(a) == "table" and plain(a.ID) then
                createdIDs[#createdIDs + 1] = a.ID
            end
        end)
    end
    return step
end

local function note(text) push(step.steps, ("%.2fs %s"):format(GetTime() - t0, text), 60) end

local function refuseCombat()
    if InCombatLockdown() then
        out().combatTry = date("%H:%M:%S") .. ": refused in combat"
        ns.Print("Talent builds probe: out of combat, please.")
        return true
    end
end

--------------------------------------------------------------------------------
-- Your spec, configs and trees
--------------------------------------------------------------------------------

-- Forever has one spec per class: its ID, by the player's spec index first
local function mySpecID()
    local SI = C_SpecializationInfo or {}
    local index = get(SI.GetSpecialization) or get(GetSpecialization) or 1
    local id = get(SI.GetSpecializationInfo, index) or get(GetSpecializationInfo, index)
    if plain(id) and type(id) == "number" then return id end
    local _, _, classID = UnitClass("player")
    id = get(GetSpecializationInfoForClassID, classID, 1)
    if plain(id) then return id end
end

local function classSpecID(classID)
    local id = get(GetSpecializationInfoForClassID, classID, 1)
    if plain(id) and type(id) == "number" then return id, "GetSpecializationInfoForClassID" end
    local SI = C_SpecializationInfo or {}
    local list = get(SI.GetSpecIDs, classID)
    if type(list) == "table" and plain(list[1]) then return list[1], "C_SpecializationInfo.GetSpecIDs" end
end

local function savedConfigs(specID)
    local list = specID and get(CT.GetConfigIDsBySpecID, specID)
    local outList = {}
    if type(list) == "table" then
        for _, id in ipairs(list) do if plain(id) then outList[#outList + 1] = id end end
    end
    return outList
end

-- The nodes you bought, as ImportLoadout takes them.
local function entriesOf(configID, treeID)
    local entries = {}
    for _, nodeID in ipairs(get(TR.GetTreeNodes, treeID) or {}) do
        local n = get(TR.GetNodeInfo, configID, nodeID)
        if type(n) == "table" and plain(n.ranksPurchased) and n.ranksPurchased > 0 then
            local entryID = n.activeEntry and n.activeEntry.entryID or (n.entryIDs and n.entryIDs[1])
            -- ranksGranted is required (the first run failed on it: "Current Field: [ranksGranted]")
            entries[#entries + 1] = { nodeID = nodeID, ranksPurchased = n.ranksPurchased, selectionEntryID = entryID,
                                      ranksGranted = plain(n.ranksGranted) and n.ranksGranted or 0,
                                      isChoiceNode = n.type == (Enum.TraitNodeType and Enum.TraitNodeType.Selection) }
        end
    end
    return entries
end

local function activeTree(configID)
    local info = configID and get(TR.GetConfigInfo, configID)
    return info and info.treeIDs and info.treeIDs[1], info
end

-- A node, briefly: what a planner needs.
local function nodeLine(configID, nodeID)
    local n = get(TR.GetNodeInfo, configID, nodeID)
    if type(n) ~= "table" then return show(nodeID) .. ": no info" end
    local spells = {}
    for _, entryID in ipairs(n.entryIDs or {}) do
        local entry = get(TR.GetEntryInfo, configID, entryID)
        local def = entry and entry.definitionID and get(TR.GetDefinitionInfo, entry.definitionID)
        spells[#spells + 1] = ("%s→%s"):format(show(entryID), show(def and def.spellID))
    end
    return ("%s: pos %s,%s ranks %s/%s purchased %s, entries %s, edges %d, conditions %s, visible %s, canPurchase %s"):format(
        show(nodeID), show(n.posX), show(n.posY), show(n.currentRank), show(n.maxRanks), show(n.ranksPurchased),
        table.concat(spells, " "), n.visibleEdges and #n.visibleEdges or 0, show(n.conditionIDs), show(n.isVisible),
        show(n.canPurchaseRank))
end

-- How much of a tree reads: node count, positions and spells readable.
local function treeSummary(configID, treeID)
    local nodes = get(TR.GetTreeNodes, treeID)
    if type(nodes) ~= "table" then return { nodes = "GetTreeNodes: " .. call(TR.GetTreeNodes, treeID) } end
    local s = { nodes = #nodes, withPos = 0, withSpell = 0, withInfo = 0, sample = {} }
    for i, nodeID in ipairs(nodes) do
        local n = get(TR.GetNodeInfo, configID, nodeID)
        if type(n) == "table" and plain(n.ID) and n.ID ~= 0 then
            s.withInfo = s.withInfo + 1
            if plain(n.posX) and n.posX ~= 0 then s.withPos = s.withPos + 1 end
            local entryID = n.entryIDs and n.entryIDs[1]
            local entry = entryID and get(TR.GetEntryInfo, configID, entryID)
            local def = entry and entry.definitionID and get(TR.GetDefinitionInfo, entry.definitionID)
            if def and plain(def.spellID) and def.spellID ~= 0 then s.withSpell = s.withSpell + 1 end
        end
        if i <= 3 then s.sample[#s.sample + 1] = nodeLine(configID, nodeID) end
    end
    -- a gate ("5 points in …"): the first condition found
    for _, nodeID in ipairs(nodes) do
        local n = get(TR.GetNodeInfo, configID, nodeID)
        local cid = n and n.conditionIDs and n.conditionIDs[1]
        if cid then s.gate = show(cid) .. " " .. call(TR.GetConditionInfo, configID, cid) break end
    end
    return s
end

--------------------------------------------------------------------------------
-- now: read only
--------------------------------------------------------------------------------

local function functionList()
    local names = {}
    for _, n in ipairs({ "GetConfigIDsBySpecID", "GetActiveConfigID", "GetLastSelectedSavedConfigID", "CanCreateNewConfig",
                         "CanChangeTalents", "CanEditTalents", "GetHasStarterBuild", "GetStarterBuildActive",
                         "ImportLoadout", "ViewLoadout", "InitializeViewLoadout", "RequestNewConfig", "SaveConfig",
                         "LoadConfig", "DeleteConfig", "RenameConfig", "GetTraitTreeForSpec", "CommitConfig",
                         "GetLoadoutExportString" }) do
        names[#names + 1] = ("C_ClassTalents.%s: %s"):format(n, type(CT[n]))
    end
    for _, n in ipairs({ "GenerateImportString", "GenerateSearchString", "GetLoadoutSerializationVersion", "GetTreeHash",
                         "GetConfigsByType", "ResetTree", "ResetTreeByCurrency", "StageConfig", "CanEditConfig",
                         "TryPurchaseToNode", "PurchaseRank", "RollbackConfig" }) do
        names[#names + 1] = ("C_Traits.%s: %s"):format(n, type(TR[n]))
    end
    for _, n in ipairs({ "GetNumTalentGroups", "GetActiveTalentGroup", "GetNumSpecGroups", "GetActiveSpecGroup",
                         "SetActiveTalentGroup", "LearnDualSpec", "GetTalentResetCost", "GetTalentWipeCost",
                         "CheckTalentMasterDist", "ConfirmTalentWipe", "GetSpecializationInfoForClassID" }) do
        names[#names + 1] = ("%s: %s"):format(n, type(_G[n]))
    end
    local SI = C_SpecializationInfo or {}
    for _, n in ipairs({ "GetActiveSpecGroup", "GetNumSpecGroups", "SetActiveSpecGroup", "GetSpecIDs" }) do
        names[#names + 1] = ("C_SpecializationInfo.%s: %s"):format(n, type(SI[n]))
    end
    return names
end

local function snapshot()
    local o = out()
    local now = { at = date("%Y-%m-%d %H:%M:%S"), level = UnitLevel("player"), class = select(2, UnitClass("player")),
                  combat = InCombatLockdown(), money = GetMoney() }
    o.now = now
    now.functions = functionList()
    local specID = mySpecID()
    now.specID = show(specID)
    now.viewConfigID = show(VIEW_ID)
    local activeID = get(CT.GetActiveConfigID)
    now.active = show(activeID)
    now.lastSelected = specID and call(CT.GetLastSelectedSavedConfigID, specID) or "no spec"
    now.canCreateNew = call(CT.CanCreateNewConfig)
    now.canChange = call(CT.CanChangeTalents)
    now.canEdit = call(CT.CanEditTalents)
    now.starter = ("has %s, active %s"):format(call(CT.GetHasStarterBuild), call(CT.GetStarterBuildActive))
    now.unspent = call(CT.HasUnspentTalentPoints)
    now.treeForSpec = specID and call(CT.GetTraitTreeForSpec, specID) or "no spec"
    now.serialization = call(TR.GetLoadoutSerializationVersion)
    -- the configs: the active one, the saved ones, every one by type
    now.saved = {}
    for _, id in ipairs(savedConfigs(specID)) do
        now.saved[#now.saved + 1] = show(id) .. " " .. call(TR.GetConfigInfo, id)
    end
    local treeID, info = activeTree(activeID)
    now.activeInfo = show(info)
    if treeID then
        now.tree = ("%s: %s; hash %s"):format(show(treeID), call(TR.GetTreeInfo, activeID, treeID),
            (function() local h = get(TR.GetTreeHash, treeID) return type(h) == "table" and (#h .. " numbers") or show(h) end)())
        now.currency = call(TR.GetTreeCurrencyInfo, activeID, treeID, false)
        now.boughtNodes = #entriesOf(activeID, treeID)
    end
    now.byType = {}
    if Enum.TraitConfigType then
        for name, value in pairs(Enum.TraitConfigType) do
            local list = get(TR.GetConfigsByType, value)
            now.byType[#now.byType + 1] = ("%s (%s): %s"):format(name, show(value), show(list))
        end
        table.sort(now.byType)
    end
    -- the export string, read only
    if activeID then
        local s = get(TR.GenerateImportString, activeID)
        now.exportString = plain(s) and type(s) == "string" and ("%d chars: %s"):format(#s, s:sub(1, 120))
            or ("GenerateImportString: " .. call(TR.GenerateImportString, activeID))
    end
    -- talent groups (dual spec) and respec
    local SI = C_SpecializationInfo or {}
    now.groups = {
        numTalentGroups = call(GetNumTalentGroups),
        activeTalentGroup = call(GetActiveTalentGroup),
        numSpecGroups = call(GetNumSpecGroups),
        activeSpecGroup = call(GetActiveSpecGroup),
        siActiveSpecGroup = call(SI.GetActiveSpecGroup, false, false),
        siNumSpecGroups = call(SI.GetNumSpecGroups),
    }
    now.respec = {
        resetCost = call(GetTalentResetCost),
        wipeCost = call(GetTalentWipeCost),
        masterDist = call(CheckTalentMasterDist),
    }
    return now
end

--------------------------------------------------------------------------------
-- Other classes: their trees, with your config and in the view loadout
--------------------------------------------------------------------------------

local function otherClasses()
    local o = out()
    local list = {}
    o.otherClasses = list
    local activeID = get(CT.GetActiveConfigID)
    local _, _, myClassID = UnitClass("player")
    local viewTried
    for classID = 1, 13 do
        local name, file = get(GetClassInfo, classID)
        if plain(name) and name then
            local c = { class = ("%s (%s)"):format(show(file), classID), mine = classID == myClassID }
            local specID, how = classSpecID(classID)
            c.specID = ("%s via %s"):format(show(specID), show(how))
            local treeID = specID and get(CT.GetTraitTreeForSpec, specID)
            c.treeID = show(treeID)
            if plain(treeID) and treeID then
                c.withYourConfig = activeID and treeSummary(activeID, treeID) or "no config"
                -- the game's view loadout: another spec's tree to look at
                -- (and plan in?) without touching yours
                if type(CT.InitializeViewLoadout) == "function" and VIEW_ID then
                    c.initView = call(CT.InitializeViewLoadout, specID, 60)
                    c.viewLoadout = call(CT.ViewLoadout, {})
                    c.inView = treeSummary(VIEW_ID, treeID)
                    c.viewCanEdit = call(TR.CanEditConfig, VIEW_ID)
                    c.viewCurrency = call(TR.GetTreeCurrencyInfo, VIEW_ID, treeID, false)
                    -- plan one point there and undo it (once, on the first
                    -- other class): may an addon plan another class's build?
                    if not viewTried and classID ~= myClassID then
                        viewTried = true
                        for _, nodeID in ipairs(get(TR.GetTreeNodes, treeID) or {}) do
                            local n = get(TR.GetNodeInfo, VIEW_ID, nodeID)
                            if type(n) == "table" and n.canPurchaseRank then
                                c.viewPlan = {
                                    node = nodeLine(VIEW_ID, nodeID),
                                    purchase = call(TR.PurchaseRank, VIEW_ID, nodeID),
                                    after = nodeLine(VIEW_ID, nodeID),
                                    staged = call(TR.ConfigHasStagedChanges, VIEW_ID),
                                    rollback = call(TR.RollbackConfig, VIEW_ID),
                                }
                                break
                            end
                        end
                        c.viewPlan = c.viewPlan or "no node to plan in the view loadout"
                    end
                end
            end
            list[#list + 1] = c
        end
    end
    -- no tree from the spec: a short scan around the known warrior tree
    -- (1117) for trees the game answers
    local found = false
    for _, c in ipairs(list) do if c.treeID ~= "nil" then found = true end end
    if not found then
        local scan = {}
        for treeID = 1100, 1140 do
            local nodes = get(TR.GetTreeNodes, treeID)
            if type(nodes) == "table" and #nodes > 0 then scan[#scan + 1] = ("%d: %d nodes"):format(treeID, #nodes) end
        end
        o.treeScan = scan
    end
    -- the view loadout back to your own spec (harmless either way)
    local specID = mySpecID()
    if specID and type(CT.InitializeViewLoadout) == "function" then pcall(CT.InitializeViewLoadout, specID, UnitLevel("player")) end
end

--------------------------------------------------------------------------------
-- export: the string, then imported as a new saved loadout and deleted
--------------------------------------------------------------------------------

local NAME = "SuuUI probe"

-- the configs that came since `before` (a list of IDs)
local function newSince(before)
    local had, out_ = {}, {}
    for _, id in ipairs(before) do had[id] = true end
    for _, id in ipairs(savedConfigs(mySpecID())) do if not had[id] then out_[#out_ + 1] = id end end
    for _, id in ipairs(createdIDs) do if not had[id] and not tContains(out_, id) then out_[#out_ + 1] = id end end
    return out_
end

-- every config named NAME: the spec's saved ones and each config type's (a
-- probe left behind by an early /reload)
local function leftovers()
    local ids, seen = {}, {}
    local function add(id)
        if not plain(id) or seen[id] then return end
        seen[id] = true
        local info = get(TR.GetConfigInfo, id)
        if type(info) == "table" and info.name == NAME then ids[#ids + 1] = id end
    end
    for _, id in ipairs(savedConfigs(mySpecID())) do add(id) end
    for _, value in pairs(Enum.TraitConfigType or {}) do
        local list = get(TR.GetConfigsByType, value)
        if type(list) == "table" then for _, id in ipairs(list) do add(id) end end
    end
    for _, id in ipairs(createdIDs) do add(id) end
    return ids
end

local function deleteNew(before, label)
    local made = newSince(before)
    note(("%s: new configs %s"):format(label, show(made)))
    for _, id in ipairs(made) do
        note(("config %s: %s"):format(show(id), call(TR.GetConfigInfo, id)))
        note(("DeleteConfig(%s): %s"):format(show(id), call(CT.DeleteConfig, id)))
    end
    C_Timer.After(1, function()
        note(("after delete: saved %s"):format(show(savedConfigs(mySpecID()))))
        step.money = ("%s → %s"):format(show(step.moneyBefore), show(GetMoney()))
        ns.Print(("Talent builds probe: %s done%s. Next step, or /reload to save."):format(label,
            #step.blocked > 0 and (" (" .. step.blocked[1] .. ")") or ", nothing blocked"))
    end)
end

function TB.Export()
    local s = watch("export")
    s.moneyBefore = GetMoney()
    local activeID = get(CT.GetActiveConfigID)
    local treeID = activeTree(activeID)
    if not (activeID and treeID) then ns.Print("Talent builds probe: no active talent config.") return end
    local str = get(TR.GenerateImportString, activeID)
    s.string = plain(str) and type(str) == "string" and ("%d chars: %s"):format(#str, str:sub(1, 200))
        or ("GenerateImportString: " .. call(TR.GenerateImportString, activeID))
    local entries = entriesOf(activeID, treeID)
    s.entries = #entries
    -- the string as a preview (the view loadout), read only
    s.viewFromString = call(CT.ViewLoadout, entries, plain(str) and str or nil)
    local can = get(CT.CanCreateNewConfig)
    s.canCreateNew = show(can)
    if not can then
        ns.Print("Talent builds probe: export recorded. The game won't make a new loadout here (CanCreateNewConfig), so no import. /reload to save.")
        return
    end
    ns.Print("Talent builds probe: importing that string as a new saved loadout \"" .. NAME .. "\", then deleting it again (your talents stay).")
    local before = savedConfigs(mySpecID())
    wipe(createdIDs)
    note("ImportLoadout(active, entries, name, string): " .. call(CT.ImportLoadout, activeID, entries, NAME, plain(str) and str or ""))
    C_Timer.After(2, function() deleteNew(before, "import") end)
end

function TB.Save()
    local s = watch("save")
    s.moneyBefore = GetMoney()
    local can = get(CT.CanCreateNewConfig)
    s.canCreateNew = show(can)
    if not can then
        ns.Print("Talent builds probe: the game won't make a new loadout here (CanCreateNewConfig false). /reload to save.")
        return
    end
    ns.Print("Talent builds probe: making a new saved loadout \"" .. NAME .. "\" from your talents, then deleting it again (your talents stay).")
    local before = savedConfigs(mySpecID())
    wipe(createdIDs)
    note("RequestNewConfig(name): " .. call(CT.RequestNewConfig, NAME))
    C_Timer.After(1.5, function()
        local made = newSince(before)
        for _, id in ipairs(made) do
            note(("SaveConfig(%s): %s"):format(show(id), call(CT.SaveConfig, id)))
            note(("in saved list: %s"):format(show(tContains(savedConfigs(mySpecID()), id))))
        end
        -- deleted right away: the first run's /reload came before a later delete
        deleteNew(before, "save")
    end)
end

--------------------------------------------------------------------------------
-- switch: load the other saved loadout and back (asked twice)
--------------------------------------------------------------------------------

local armedSwitch

function TB.Switch()
    local specID = mySpecID()
    local saved = savedConfigs(specID)
    local last = specID and get(CT.GetLastSelectedSavedConfigID, specID)
    local other
    for _, id in ipairs(saved) do if id ~= last then other = id break end end
    if #saved < 2 or not other then
        local s = watch("switch")
        s.skipped = ("%d saved loadouts (last selected %s): needs two"):format(#saved, show(last))
        ns.Print("Talent builds probe: switch needs two saved loadouts; you have " .. #saved .. ". Skipped.")
        return
    end
    if not armedSwitch or GetTime() - armedSwitch > 20 then
        armedSwitch = GetTime()
        ns.Print(("Talent builds probe: this loads your saved loadout %s and then %s again: it changes your talents and may cost gold. Run /suu probe talentbuilds switch again within 20 s to do it."):format(
            show(other), show(last or "your current one")))
        return
    end
    armedSwitch = nil
    local s = watch("switch")
    s.moneyBefore = GetMoney()
    s.from, s.to = show(last), show(other)
    note(("LoadConfig(%s, true): %s"):format(show(other), call(CT.LoadConfig, other, true)))
    C_Timer.After(3, function()
        note(("active now %s, last selected %s"):format(call(CT.GetActiveConfigID), call(CT.GetLastSelectedSavedConfigID, specID)))
        if last then note(("LoadConfig(%s, true) back: %s"):format(show(last), call(CT.LoadConfig, last, true))) end
        C_Timer.After(3, function()
            note(("active now %s, last selected %s"):format(call(CT.GetActiveConfigID), call(CT.GetLastSelectedSavedConfigID, specID)))
            s.money = ("%s → %s"):format(show(s.moneyBefore), show(GetMoney()))
            ns.Print(("Talent builds probe: switch done%s. /reload to save."):format(
                #s.blocked > 0 and (" (" .. s.blocked[1] .. ")") or ", nothing blocked"))
        end)
    end)
end

function TB.Command(arg)
    if refuseCombat() then return end
    arg = (arg or ""):lower()
    if arg == "export" then return TB.Export() end
    if arg == "save" then return TB.Save() end
    if arg == "switch" then return TB.Switch() end
    if arg == "cleanup" then
        local s = watch("cleanup")
        local ids = leftovers()
        s.found = show(ids)
        for _, id in ipairs(ids) do note(("DeleteConfig(%s): %s"):format(show(id), call(CT.DeleteConfig, id))) end
        C_Timer.After(1, function()
            note(("left: %s"):format(show(leftovers())))
            ns.Print(("Talent builds probe: cleanup deleted %d loadout(s) named \"%s\". /reload to save."):format(#ids, NAME))
        end)
        return
    end
    watch("readOnly")
    snapshot()
    otherClasses()
    local o = out()
    local left = leftovers()
    o.now.leftovers = show(left)
    if #left > 0 then
        ns.Print(("Talent builds probe: a loadout named \"%s\" is left from an earlier run; /suu probe talentbuilds cleanup deletes it."):format(NAME))
    end
    ns.Print(("Talent builds probe: recorded (spec %s, %d saved loadouts, %d classes). Next: /suu probe talentbuilds export, then save, then switch; /reload to save."):format(
        o.now.specID, #o.now.saved, #o.otherClasses))
end
