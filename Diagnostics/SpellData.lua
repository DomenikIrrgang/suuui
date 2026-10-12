-- Diagnostics/SpellData.lua
-- "/suu probe spells": verified spell and aura IDs from this client, for the
-- Cooldown Manager presets (plan step 1.7c).
--
-- Collects, per character, into SuuUIProbe.spells["Name-Realm"]:
--   spellbook   every spell in your (and your pet's) spellbook: name, rank,
--               spell ID, tab (Balance, Feral Combat, ...), passive, not yet
--               learned, base cooldown; a pet's spells with the pet's family
--               (Imp, Voidwalker, Wolf, ...). While recording, every pet you
--               summon or tame is read too, so they add up
--   casts       every spell you cast, with the exact rank ID
--   auras       every aura seen on you, your target and your pet: name, ID,
--               buff or debuff, whether it was yours, its duration
-- Auras can't be read in any combat, so they are read out of combat and in
-- the seconds right after a fight (procs such as Clearcasting often outlast
-- it). Recording keeps running across reloads until "/suu probe spells off".
--
-- The scan needs no max-level character: the client answers C_Spell queries
-- for any spell ID, learned or not, so walking the IDs finds every rank of
-- every spell, and the proc auras, with this client's own IDs. It runs in
-- small chunks (out of combat) into SuuUIProbe.spellScan.
--
--   /suu probe spells        dump the spellbook now and start recording
--   /suu probe spells scan   walk every spell ID the client knows
--   /suu probe spells scan forever   save every spell in Forever's own range
--                            (1.2 to 1.33 million) with its name and rank, to
--                            find Forever's new class spells
--   /suu probe spells scan high   count (not save) spells from 1.4 to 3 million,
--                            to check nothing lies beyond the main scan
--   /suu probe spells off    stop recording
--   /suu probe spells find <name>   every spell ID with exactly that name (any
--                            range), saved in SuuUIProbe.spellFind[name]
--   /suu probe spells clear  drop all spell data from the save file (it is
--                            copied into tools/data once Claude has read it)

local _, ns = ...

local Events = ns.Events

local SD = {}
ns.SpellData = SD

local isSecret = issecretvalue or function() return false end
local AFTER_COMBAT = 15 -- seconds of sweeps after a fight

local recording = false

local function charKey()
    local name, realm = UnitFullName("player")
    return (name or "?") .. "-" .. (realm or GetRealmName() or "?")
end

local function store()
    SuuUIProbe = SuuUIProbe or {}
    SuuUIProbe.spells = SuuUIProbe.spells or {}
    local key = charKey()
    local d = SuuUIProbe.spells[key] or { spellbook = {}, casts = {}, auras = {} }
    local _, class = UnitClass("player")
    d.class, d.level = class, UnitLevel("player")
    SuuUIProbe.spells[key] = d
    return d
end

local function readable(v)
    return v ~= nil and not isSecret(v)
end

--------------------------------------------------------------------------------
-- Spellbook
--------------------------------------------------------------------------------

local ITEM_TYPE = {}
for name, value in pairs(Enum.SpellBookItemType or {}) do ITEM_TYPE[value] = name end

local function baseCooldown(id)
    if not GetSpellBaseCooldown then return nil end
    local ok, ms = pcall(GetSpellBaseCooldown, id)
    return ok and readable(ms) and ms > 0 and ms or nil
end

local function dumpBank(d, bank, owner)
    local count = 0
    local lines = C_SpellBook.GetNumSpellBookSkillLines and C_SpellBook.GetNumSpellBookSkillLines() or 0
    local function add(index, tab)
        local ok, it = pcall(C_SpellBook.GetSpellBookItemInfo, index, bank)
        if not (ok and it and readable(it.spellID)) then return end
        local id = it.spellID
        d.spellbook[id] = {
            name = it.name or C_Spell.GetSpellName(id),
            rank = it.subName ~= "" and it.subName or (C_Spell.GetSpellSubtext and C_Spell.GetSpellSubtext(id)) or nil,
            tab = tab,
            owner = owner,
            passive = it.isPassive or nil,
            kind = ITEM_TYPE[it.itemType] or it.itemType,
            known = IsPlayerSpell and IsPlayerSpell(id) or nil,
            cooldownMS = baseCooldown(id),
            family = owner == "pet" and UnitCreatureFamily and UnitCreatureFamily("pet") or nil,
        }
        count = count + 1
    end
    if owner == "pet" then
        local n = C_SpellBook.HasPetSpells and C_SpellBook.HasPetSpells() or 0
        for i = 1, (type(n) == "number" and n or 0) do add(i, "Pet") end
    else
        for line = 1, lines do
            local li = C_SpellBook.GetSpellBookSkillLineInfo(line)
            if li and li.itemIndexOffset and li.numSpellBookItems then
                for i = li.itemIndexOffset + 1, li.itemIndexOffset + li.numSpellBookItems do add(i, li.name) end
            end
        end
    end
    return count
end

function SD.DumpSpellbook()
    if InCombatLockdown() then
        ns.Print("Spell data: the spellbook is read out of combat.")
        return 0, 0
    end
    local d = store()
    local mine = dumpBank(d, Enum.SpellBookSpellBank.Player, "player")
    local pet = Enum.SpellBookSpellBank.Pet and dumpBank(d, Enum.SpellBookSpellBank.Pet, "pet") or 0
    d.spellbookAt = date("%Y-%m-%d %H:%M")
    return mine, pet
end

--------------------------------------------------------------------------------
-- Casts and auras
--------------------------------------------------------------------------------

local function noteAura(d, unit, a, filter)
    if not (readable(a.spellId) and readable(a.name)) then return end
    local e = d.auras[a.spellId] or { name = a.name, seen = 0, on = {} }
    e.seen = e.seen + 1
    e.on[unit] = true
    e.kind = filter
    e.icon = readable(a.icon) and a.icon or e.icon
    if readable(a.duration) and a.duration > 0 then e.duration = a.duration end
    if readable(a.isFromPlayerOrPlayerPet) and a.isFromPlayerOrPlayerPet then e.mine = true end
    if readable(a.sourceUnit) and a.sourceUnit then e.source = a.sourceUnit end
    if readable(a.dispelName) and a.dispelName then e.dispel = a.dispelName end
    e.last = date("%Y-%m-%d %H:%M")
    d.auras[a.spellId] = e
end

local function sweep(unit)
    if not recording or not UnitExists(unit) then return end
    local d = store()
    for _, filter in ipairs({ "HELPFUL", "HARMFUL" }) do
        for i = 1, 40 do
            local ok, a = pcall(C_UnitAuras.GetAuraDataByIndex, unit, i, filter)
            if not ok or not a or isSecret(a) then break end
            noteAura(d, unit, a, filter)
        end
    end
end

local function sweepAll()
    if InCombatLockdown() then return end
    sweep("player"); sweep("target"); sweep("pet")
end

-- After a fight: sweep every second for a while, to catch procs and buffs
-- that outlast it.
local function afterCombat()
    for s = 0, AFTER_COMBAT do
        C_Timer.After(s, function() if recording then sweepAll() end end)
    end
end

local function noteCast(_, _, spellID)
    if not recording or not readable(spellID) then return end
    local d = store()
    local e = d.casts[spellID] or { name = C_Spell.GetSpellName(spellID), count = 0 }
    e.count = e.count + 1
    e.last = date("%Y-%m-%d %H:%M")
    d.casts[spellID] = e
end

local function start()
    if recording then return end
    recording = true
    Events.OnUnit("UNIT_AURA", { "player", "target", "pet" }, function(_, unit)
        if not InCombatLockdown() then sweep(unit) end
    end, SD)
    Events.OnGame("PLAYER_TARGET_CHANGED", sweepAll, SD)
    Events.OnGame("PLAYER_REGEN_ENABLED", afterCombat, SD)
    Events.OnUnit("UNIT_SPELLCAST_SUCCEEDED", "player", noteCast, SD)
    -- each new pet: its spellbook (once it has loaded), out of combat
    Events.OnUnit("UNIT_PET", "player", function()
        C_Timer.After(1, function()
            if recording and UnitExists("pet") and not InCombatLockdown() then
                local _, pet = SD.DumpSpellbook()
                ns.Print(("Spell data: %s's %d spells read."):format(UnitCreatureFamily("pet") or UnitName("pet") or "pet", pet))
            end
        end)
    end, SD)
    sweepAll()
end

local function stop()
    recording = false
    Events.OffAll(SD)
end

--------------------------------------------------------------------------------
-- The client's whole spell table
--------------------------------------------------------------------------------

-- Vanilla's IDs end near 30000, but Forever adds its own above a million
-- (Plainsrunning is 1259918). Below VANILLA everything is kept; above it only
-- ranked spells and names vanilla already has, plus a count and a few sample
-- names per 100k, so the client's other spells can't bloat the save.
local VANILLA = 120000
local SCAN_TO = 1400000
local BUDGET = 8 -- ms per frame
local SAMPLES = 25
local scanning = false

function SD.Scan()
    if scanning then return end
    if InCombatLockdown() then
        ns.Print("Spell data: the scan runs out of combat.")
        return
    end
    scanning = true
    SuuUIProbe = SuuUIProbe or {}
    local byName, buckets = {}, {}
    local total, kept, highest = 0, 0, 0
    local nextID = 1
    local subtext = C_Spell.GetSpellSubtext
    ns.Print("Spell data: scanning the client's spells (about a minute; it pauses in combat)…")
    local ticker
    ticker = C_Timer.NewTicker(0, function()
        if InCombatLockdown() then return end
        local stopAt = debugprofilestop() + BUDGET
        while nextID <= SCAN_TO and debugprofilestop() < stopAt do
            local id = nextID
            nextID = id + 1
            local name = C_Spell.GetSpellName(id)
            if name and not isSecret(name) and name ~= "" then
                total = total + 1
                highest = id
                local rank = subtext and subtext(id) or nil
                if isSecret(rank) or rank == "" then rank = nil end
                local keep = id < VANILLA or rank ~= nil or byName[name] ~= nil
                if id >= VANILLA then
                    local b = math.floor(id / 100000) * 100000
                    local bucket = buckets[b] or { count = 0, kept = 0, samples = {} }
                    bucket.count = bucket.count + 1
                    if keep then bucket.kept = bucket.kept + 1
                    elseif #bucket.samples < SAMPLES then bucket.samples[#bucket.samples + 1] = id .. " " .. name end
                    buckets[b] = bucket
                end
                if keep then
                    local list = byName[name]
                    if not list then list = {}; byName[name] = list end
                    list[#list + 1] = rank and { id, rank } or { id }
                    kept = kept + 1
                end
            end
        end
        if nextID > SCAN_TO then
            ticker:Cancel()
            scanning = false
            SuuUIProbe.spellScan = { at = date("%Y-%m-%d %H:%M"), scannedTo = SCAN_TO, highest = highest,
                count = total, kept = kept, buckets = buckets, byName = byName }
            ns.Print(("Spell data: %d spells found, %d kept (highest ID %d). /reload to save them."):format(total, kept, highest))
        end
    end)
end

--------------------------------------------------------------------------------
-- The command
--------------------------------------------------------------------------------

local function count(t)
    local n = 0
    for _ in pairs(t or {}) do n = n + 1 end
    return n
end

-- Forever's own spells, unfiltered: everything from 1.2 to 1.33 million.
function SD.ScanForever()
    if scanning then return end
    if InCombatLockdown() then
        ns.Print("Spell data: the scan runs out of combat.")
        return
    end
    scanning = true
    local from, to = 1200000, 1330000
    local nextID, rows = from, {}
    local subtext = C_Spell.GetSpellSubtext
    ns.Print("Spell data: saving Forever's own spells…")
    local ticker
    ticker = C_Timer.NewTicker(0, function()
        if InCombatLockdown() then return end
        local stopAt = debugprofilestop() + BUDGET
        while nextID <= to and debugprofilestop() < stopAt do
            local name = C_Spell.GetSpellName(nextID)
            if name and not isSecret(name) and name ~= "" then
                local rank = subtext and subtext(nextID) or nil
                if isSecret(rank) or rank == "" then rank = nil end
                rows[#rows + 1] = rank and { nextID, name, rank } or { nextID, name }
            end
            nextID = nextID + 1
        end
        if nextID > to then
            ticker:Cancel()
            scanning = false
            SuuUIProbe = SuuUIProbe or {}
            SuuUIProbe.spellScanForever = { at = date("%Y-%m-%d %H:%M"), from = from, to = to, rows = rows }
            ns.Print(("Spell data: %d of Forever's own spells saved. /reload to save them."):format(#rows))
        end
    end)
end

-- Only counts: is there anything above the main scan's range?
function SD.ScanHigh()
    if scanning then return end
    if InCombatLockdown() then
        ns.Print("Spell data: the scan runs out of combat.")
        return
    end
    scanning = true
    local from, to = SCAN_TO + 1, 3000000
    local nextID, total, first, last, samples = from, 0, nil, nil, {}
    ns.Print(("Spell data: counting spells from %d to %d…"):format(from, to))
    local ticker
    ticker = C_Timer.NewTicker(0, function()
        if InCombatLockdown() then return end
        local stopAt = debugprofilestop() + BUDGET
        while nextID <= to and debugprofilestop() < stopAt do
            local name = C_Spell.GetSpellName(nextID)
            if name and not isSecret(name) and name ~= "" then
                total = total + 1
                first = first or nextID
                last = nextID
                if #samples < SAMPLES then samples[#samples + 1] = nextID .. " " .. name end
            end
            nextID = nextID + 1
        end
        if nextID > to then
            ticker:Cancel()
            scanning = false
            SuuUIProbe = SuuUIProbe or {}
            SuuUIProbe.spellScanHigh = { at = date("%Y-%m-%d %H:%M"), from = from, to = to, count = total,
                first = first, last = last, samples = samples }
            ns.Print(total == 0 and ("Spell data: nothing above %d. The main scan covered everything."):format(SCAN_TO)
                or ("Spell data: %d more spells between %d and %d. /reload to save, and tell Claude."):format(total, first, last))
        end
    end)
end

-- Every ID with exactly this name, 1 to 1.4 million.
function SD.Find(name)
    if scanning then return end
    if not name or name == "" then ns.Print("Spell data: /suu probe spells find <spell name>") return end
    if InCombatLockdown() then ns.Print("Spell data: the scan runs out of combat.") return end
    scanning = true
    local target, nextID, found = name:lower(), 1, {}
    ns.Print(("Spell data: looking for %q…"):format(name))
    local ticker
    ticker = C_Timer.NewTicker(0, function()
        if InCombatLockdown() then return end
        local stopAt = debugprofilestop() + BUDGET
        while nextID <= SCAN_TO and debugprofilestop() < stopAt do
            local n = C_Spell.GetSpellName(nextID)
            if n and not isSecret(n) and n:lower() == target then found[#found + 1] = nextID end
            nextID = nextID + 1
        end
        if nextID > SCAN_TO then
            ticker:Cancel()
            scanning = false
            SuuUIProbe = SuuUIProbe or {}
            SuuUIProbe.spellFind = SuuUIProbe.spellFind or {}
            SuuUIProbe.spellFind[name] = found
            ns.Print(("Spell data: %q has %d IDs: %s. /reload to save."):format(name, #found, table.concat(found, ", ")))
        end
    end)
end

function SD.Command(arg)
    local findName = arg and arg:match("^find%s+(.+)$")
    if findName then
        SD.Find(findName)
        return
    end
    if arg == "scan forever" then
        SD.ScanForever()
        return
    end
    if arg == "clear" then
        stop()
        if SuuUIProbe then
            SuuUIProbe.spellScan, SuuUIProbe.spellScanHigh, SuuUIProbe.spells, SuuUIProbe.spellsRecording = nil, nil, nil, nil
            SuuUIProbe.spellScanForever = nil
        end
        ns.Print("Spell data: cleared. /reload to shrink the save file.")
        return
    end
    if arg == "scan high" then
        SD.ScanHigh()
        return
    end
    if arg == "scan" then
        SD.Scan()
        return
    end
    if arg == "off" then
        stop()
        if SuuUIProbe then SuuUIProbe.spellsRecording = nil end
        ns.Print("Spell data: recording stopped. /reload to save.")
        return
    end
    local mine, pet = SD.DumpSpellbook()
    SuuUIProbe = SuuUIProbe or {}
    SuuUIProbe.spellsRecording = true
    start()
    local d = store()
    ns.Print(("Spell data: %d spells in your spellbook, %d pet spells. Recording casts and auras (%d casts, %d auras so far) until /suu probe spells off."):format(
        mine, pet, count(d.casts), count(d.auras)))
    ns.Print("Play normally: cast your spells and use your cooldowns, pick up procs. /reload now and then to save.")
end

-- Recording survives reloads.
Events.OnGame("PLAYER_LOGIN", function()
    if SuuUIProbe and SuuUIProbe.spellsRecording then
        start()
        C_Timer.After(3, function() if not InCombatLockdown() then SD.DumpSpellbook() end end)
    end
end, "SpellData")
