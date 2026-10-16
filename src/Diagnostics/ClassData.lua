-- Diagnostics/ClassData.lua
-- "/suu probe class": what this class really gets on Forever, for the
-- Cooldown Manager presets (plan step 1.7c). Works at level 1:
--   talents   every node of the class's talent trees, learned or not, with
--             its spell ID (through C_Traits, as Forever's talents are built),
--             its description and base cooldown (read a moment later: the
--             client loads spell text on demand)
--   trainer   when a class trainer's window opens: every spell it lists,
--             unavailable ones included, with rank, required level,
--             description and training cost (copper)
-- Saved per class in SuuUIProbe.classData[CLASS] on /reload.
--
--   /suu probe class    read the talents now; then talk to the class trainer

local _, ns = ...

local Events = ns.Events

local CD = {}
ns.ClassData = CD

local isSecret = issecretvalue or function() return false end
local listening = false

local function store()
    SuuUIProbe = SuuUIProbe or {}
    SuuUIProbe.classData = SuuUIProbe.classData or {}
    local _, class = UnitClass("player")
    local d = SuuUIProbe.classData[class] or {}
    d.character = UnitName("player")
    d.level = UnitLevel("player")
    d.race = select(2, UnitRace("player"))
    SuuUIProbe.classData[class] = d
    return d, class
end

local function call(fn, ...)
    if type(fn) ~= "function" then return nil end
    local ok, a, b, c, d = pcall(fn, ...)
    if ok then return a, b, c, d end
end

--------------------------------------------------------------------------------
-- Talents
--------------------------------------------------------------------------------

-- The config to read the trees from: the active one, else the spec's.
local function configID()
    local id = C_ClassTalents and call(C_ClassTalents.GetActiveConfigID)
    if id then return id end
    local spec = C_SpecializationInfo and call(C_SpecializationInfo.GetSpecialization) or 1
    local specID = C_SpecializationInfo and call(C_SpecializationInfo.GetSpecializationInfo, spec)
    if specID and C_ClassTalents then
        local ids = call(C_ClassTalents.GetConfigIDsBySpecID, specID)
        if type(ids) == "table" and ids[1] then return ids[1] end
        local treeID = call(C_ClassTalents.GetTraitTreeForSpec, specID)
        if treeID then return call(C_Traits.GetConfigIDByTreeID, treeID) end
    end
end

function CD.ReadTalents()
    local d = store()
    local talents = {}
    local cfg = configID()
    local info = cfg and C_Traits and call(C_Traits.GetConfigInfo, cfg)
    if not (info and info.treeIDs) then
        d.talentsError = "no talent config (C_ClassTalents/C_Traits gave nothing)"
        return 0
    end
    for _, treeID in ipairs(info.treeIDs) do
        local nodes = call(C_Traits.GetTreeNodes, treeID) or {}
        for _, nodeID in ipairs(nodes) do
            local ni = call(C_Traits.GetNodeInfo, cfg, nodeID)
            if ni and ni.entryIDs then
                for _, entryID in ipairs(ni.entryIDs) do
                    local ei = call(C_Traits.GetEntryInfo, cfg, entryID)
                    local di = ei and ei.definitionID and call(C_Traits.GetDefinitionInfo, ei.definitionID)
                    local spellID = di and (di.spellID or di.overriddenSpellID)
                    if spellID and not isSecret(spellID) then
                        talents[#talents + 1] = {
                            spellID = spellID,
                            name = C_Spell.GetSpellName(spellID),
                            tree = treeID, node = nodeID,
                            subTree = ni.subTreeID, x = ni.posX, y = ni.posY,
                            maxRanks = ni.maxRanks, passive = C_Spell.IsSpellPassive and call(C_Spell.IsSpellPassive, spellID) or nil,
                        }
                    end
                end
            end
        end
    end
    d.talents, d.talentsAt, d.talentsError = talents, date("%Y-%m-%d %H:%M"), nil
    CD.Describe(talents)
    return #talents
end

-- What each talent does and its base cooldown: Forever's own talents have no
-- other source. The client loads spell text on demand, so ask for all of it
-- first and read it a moment later.
function CD.Describe(talents)
    for _, t in ipairs(talents) do
        if C_Spell.RequestLoadSpellData then pcall(C_Spell.RequestLoadSpellData, t.spellID) end
    end
    C_Timer.After(2, function()
        local n = 0
        for _, t in ipairs(talents) do
            local desc = call(C_Spell.GetSpellDescription, t.spellID)
            if type(desc) == "string" and not isSecret(desc) and desc ~= "" then
                t.description = desc
                n = n + 1
            end
            local cd = GetSpellBaseCooldown and call(GetSpellBaseCooldown, t.spellID)
            if type(cd) == "number" and not isSecret(cd) and cd > 0 then t.cooldown = cd end
        end
        ns.Print(("Class data: %d of %d talent descriptions read. /reload to save."):format(n, #talents))
    end)
end

--------------------------------------------------------------------------------
-- Trainer
--------------------------------------------------------------------------------

function CD.ReadTrainer()
    local d = store()
    if not GetNumTrainerServices then
        d.trainerError = "no trainer API"
        return 0, 0
    end
    -- every service, not only what you can learn now (onTrainer switched
    -- the filters on and waited for the game to apply them)
    if ExpandTrainerSkillLine then pcall(ExpandTrainerSkillLine, 0) end
    local spells, maxLevel = {}, 0
    local n = call(GetNumTrainerServices) or 0
    for i = 1, n do
        -- this client answers name, availability, icon (no rank); older ones
        -- name, rank, availability
        local name, a, b = call(GetTrainerServiceInfo, i)
        local rank, kind, icon
        if a == "available" or a == "unavailable" or a == "used" or a == "header" then
            kind, icon = a, b
        else
            rank, kind = a, b
        end
        if name and kind ~= "header" then
            local level = GetTrainerServiceLevelReq and call(GetTrainerServiceLevelReq, i) or nil
            if type(level) == "number" and level > maxLevel then maxLevel = level end
            local link = GetTrainerServiceItemLink and call(GetTrainerServiceItemLink, i) or nil
            local desc = GetTrainerServiceDescription and call(GetTrainerServiceDescription, i) or nil
            local cost = GetTrainerServiceCost and call(GetTrainerServiceCost, i) or nil
            spells[#spells + 1] = { index = i, name = name, rank = rank ~= "" and rank or nil, kind = kind, icon = icon, level = level, link = link,
                skill = GetTrainerServiceSkillLine and call(GetTrainerServiceSkillLine, i) or nil,
                description = type(desc) == "string" and not isSecret(desc) and desc ~= "" and desc or nil,
                cost = type(cost) == "number" and not isSecret(cost) and cost or nil }
        end
    end
    -- C_Trainer, if this client has it (names only, for later)
    local api = {}
    for k in pairs(C_Trainer or {}) do api[#api + 1] = k end
    table.sort(api)
    d.trainer, d.trainerAt, d.trainerMaxLevel, d.trainerAPI, d.trainerError = spells, date("%Y-%m-%d %H:%M"), maxLevel, api, nil
    -- the game loads a description on demand: the ones still missing once
    -- more, a moment later (a spell new today came back without one); and
    -- each service's spell ID, from its tooltip (a new spell has none in
    -- SuuUI's ID scans yet)
    C_Timer.After(1.5, function()
        for i, sp in ipairs(spells) do
            if sp.index and C_TooltipInfo and C_TooltipInfo.GetTrainerService then
                local data = call(C_TooltipInfo.GetTrainerService, sp.index)
                local id = data and data.id
                if type(id) == "number" and not isSecret(id) then sp.spellID = id end
            end
            if not sp.description and sp.index and GetTrainerServiceDescription then
                local desc = call(GetTrainerServiceDescription, sp.index)
                if type(desc) == "string" and not isSecret(desc) and desc ~= "" then sp.description = desc end
            end
            -- some have none in the trainer's data (Salvation, new on
            -- 2026-10-16) but show one in their tooltip: its last long line
            if not sp.description and sp.index and C_TooltipInfo and C_TooltipInfo.GetTrainerService then
                local data = call(C_TooltipInfo.GetTrainerService, sp.index)
                local lines = data and data.lines or {}
                for k = #lines, 2, -1 do
                    local text = lines[k].leftText
                    if type(text) == "string" and not isSecret(text) and #text > 30 and not text:find("^Requires") then
                        sp.description = text
                        sp.descriptionFrom = "tooltip"
                        break
                    end
                end
            end
        end
        local ids = 0
        for _, sp in ipairs(spells) do if sp.spellID then ids = ids + 1 end end
        ns.Print(("Class data: done, %d of %d with their spell ID. /reload to save."):format(ids, #spells))
    end)
    d.trainerNPC = UnitName("npc")
    return #spells, maxLevel
end

-- Every service shows only once the game applied the filters: switch them
-- all on, then read on its next TRAINER_UPDATE (or after two seconds). Read
-- at once, the list lacked what you already know (Used was off a moment ago).
local function allFilters()
    local changed = false
    if SetTrainerServiceTypeFilter then
        for _, kind in ipairs({ "available", "unavailable", "used" }) do
            if GetTrainerServiceTypeFilter and not GetTrainerServiceTypeFilter(kind) then changed = true end
            pcall(SetTrainerServiceTypeFilter, kind, true)
        end
    end
    return changed
end

local function onTrainer()
    if not listening then return end
    local waited = false
    local function read()
        if waited then return end
        waited = true
        local count, maxLevel = CD.ReadTrainer()
        ns.Print(("Class data: the trainer lists %d spells, up to level %d. Reading their IDs and descriptions…"):format(count, maxLevel))
        if count > 0 and maxLevel < 50 then
            ns.Print("Class data: this trainer stops early; a city trainer may list the rest.")
        end
    end
    C_Timer.After(0.2, function()
        if allFilters() then
            Events.OnGame("TRAINER_UPDATE", function() C_Timer.After(0.2, read) end, CD)
            C_Timer.After(2, read)
        else
            read()
        end
    end)
end

function CD.Command()
    local count = CD.ReadTalents()
    local _, class = store()
    ns.Print(("Class data (%s): %d talents read. Now talk to your class trainer."):format(class, count))
    if not listening then
        listening = true
        Events.OnGame("TRAINER_SHOW", onTrainer, CD)
    end
end
