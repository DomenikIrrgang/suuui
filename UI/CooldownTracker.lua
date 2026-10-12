-- UI/CooldownTracker.lua
-- SuuUI's own Cooldown Manager (step 1.7b): tracked procs, buffs and your
-- debuffs on the target as icons on top, then Essential and Utility
-- cooldowns. Blizzard's CooldownViewer isn't used.
--
--   local t = UI.CooldownTracker(parent, { name = "SuuUICooldownManager" })
--   t:SetLists(lists)     -- { essential, utility, buffs, debuffs, procs }:
--                         -- entries { name, ids = { ... }, mine }
--   t:SetOptions(opts)    -- { essentialSize, utilityInline, readyPop,
--                         -- procHighlight }; "when missing" is each aura
--                         -- entry's own (entry.missing: buffs "grey",
--                         -- debuffs "target" unless set)
--   t:Stop(), t:Start()   -- 0.9: off (no events, aura sounds or containers in
--                         -- use) and on again; a new tracker starts running
--
-- Cooldowns are SuuUI's own icons: whether a cooldown runs stays readable in
-- combat, and its sweep comes from the engine's duration object. Each entry
-- uses the highest rank you know; an entry you don't know isn't drawn.
--   ready      full colour, arcane edge (no glow); coming off cooldown it
--              pops with the arcane flash
--   cooldown   desaturated, sweep, digits in micro
--   unusable   opacity-disabled
--   use now    reactive abilities (Overpower, Revenge, Riposte, Mongoose
--              Bite, Counterattack, Hammer of Wrath, Victory Rush): arcane
--              ring and glow, while the game says they're usable (if it says
--              so in combat)
--   effect     (per entry, opt-in) while the spell's effect runs, its aura
--              covers the icon: a one-icon engine container over the cell,
--              gilt edge and ward glow, with the aura's own time and drain.
--              entry.effect = "you" (a buff on you) or "target" (your debuff
--              on the target); entry.effectIDs, else the spell's own IDs.
--
-- Auras are engine containers with spell lists (verified in dungeon combat).
-- Addon code can't read, count or measure them, so:
--   grey     each entry gets a fixed slot with a grey placeholder under the
--            live icon (never empty, so never a gap)
--   hide     the list packs into one container, a group per entry in list
--            order, and the engine closes the gaps itself
--   remind   shown grey only while the aura is NOT up, out of combat (the
--            only time SuuUI can read auras); hidden in combat
-- A group entry ({ group = true, name, members, ids = all members' IDs,
-- source = "mine"|"others"|"any", max = 1..4, icon, fixedIcon }) is one slot
-- for several spells: the engine shows whichever members are up (up to max),
-- each with its own icon and time; with none up the slot's icon follows "when
-- missing". That icon is `icon` when fixedIcon is set; otherwise automatic:
-- the first member (in order, those its conditions leave in) that you know,
-- else the first whose `when` is met now (none: met), else `icon`; a
-- member's art is its own `icon`, else its first ID. Picked at each build
-- (a learned rank or a static condition's change rebuilds). Source maps to
-- the filter: PLAYER, !PLAYER (verified valid), or none. A member may have
-- its own source ({ name, ids, icon, source, when }): members of different
-- sources become one engine group per source in the same slot, each with the
-- slot's max.
-- In a cooldown list a group is one cell: the LAST member you know (members
-- in order of preference: Divine Protection, then Divine Shield once
-- learned), with the group's behaviour; its effect is effectIDs, else that
-- member's IDs. None known: not drawn.
-- A collection ({ collection = true, uid, name, when, hidden, entries },
-- aura lists only) is its entries in its place, in order, each with its own
-- behaviour; its `hidden` and `when` apply to all of them. Its fixed slots
-- (grey, remind) sit apart from their neighbours: a hairline in a wider gap.
-- Conditions (`when` on any entry: a cooldown, a single aura, a group, a
-- group's member, a collection):
--   when = { match = "all"|"any" (default "all"), conditions = {
--     { type = "group", value = "solo"|"group"|"raid" },  -- a raid is a group
--     { type = "classes", classes = { "DRUID", ... }, others = true? },
--                                   -- someone in your group, you too; with
--                                   -- others, only the others
--     { type = "talent", talents = { spellID, ... } },  -- you've learned any
--                                   -- of them (any class's: another's is
--                                   -- never learned)
--     { type = "role", roles = { "TANK"|"HEALER"|"DAMAGER", ... } },  -- SuuUI's
--     { type = "stance", stances = { "battle"|"defensive"|"berserker"|"caster"|
--       "bear"|"cat"|"moonkin"|"travel"|"aquatic"|"stealth"|"shadowform", ... } },
--     { type = "combat" },
--     { type = "instance", kinds = { "none"|"party"|"raid"|"pvp", ... } },
--                                   -- an arena is pvp
--     { type = "target", kinds = { "boss"|"elite"|"player"|"normal", ... } },
--                                   -- one kind each: a player, else a
--                                   -- boss (worldboss, level ??, or the
--                                   -- game says so), else elite (rare
--                                   -- elite too), else normal; no target:
--                                   -- none
--   } }
-- ["not"] = true turns one around. No conditions: always. A condition with
-- nothing chosen (an empty list) counts as absent. A collection's `when`
-- applies to its entries (with each one's own: both must hold); a member's
-- only to that member. Not met: left out (no grey slot, no reminder; a
-- member: out of its slot).
--   static   group, classes, role, instance, talent: checked when the tracker
--            builds; a roster, role, zone or talent change that changes them
--            rebuilds, after combat. An entry they rule out isn't built.
--            Talents learned are read from the active talent config (a node
--            with a rank, its entry's spell), kept until the talents or the
--            spellbook change; a spell you know (IsPlayerSpell) counts too.
--   live     stance, combat, target: an entry that turns on them is built
--            and shown or hidden in place, in combat too, and its row closes
--            up. Cells, fixed slots and reminders are SuuUI's frames. A
--            packed entry ("hide" when missing, procs), a slot's member with
--            a live condition (an engine group of its own in the slot) and a
--            cell's effect are engine groups: their max goes to 0 and back.
--            LIMIT (untested in game): if the engine refuses that change in
--            combat, it applies when combat ends. Aura sounds stay registered
--            for an entry hidden by a live condition.
--   In a cooldown list a group's member's `when` rules it out (the cell
--   shows the last one you know of the rest); a live one hides the cell.
--   UI.CooldownConditionMet(when)   -- whether a `when` is met now
-- The timers row centres on its divider, since a packed list's width can't
-- be known: buffs and procs grow left of it, your debuffs right. Order from
-- the divider outward: grey slots, reminders, then the packed ones.

local _, ns = ...

local UI, T, Events, Motion = ns.UI, ns.Tokens, ns.Events, ns.Motion
local S = T.space

local isSecret = issecretvalue or function() return false end
local function known(v, fallback)
    if isSecret(v) or v == nil then return fallback end
    return v
end

local CROP = 0.08
local AURA = "icon-lg"

local REACTIVE = {
    ["Overpower"] = true, ["Revenge"] = true, ["Riposte"] = true, ["Mongoose Bite"] = true,
    ["Counterattack"] = true, ["Hammer of Wrath"] = true, ["Execute"] = true,
    ["Victory Rush"] = true,
}

local TR = {}

--------------------------------------------------------------------------------
-- Cooldown cells
--------------------------------------------------------------------------------

-- The rank of an entry you know (highest ID first), or nil.
local function knownRank(entry)
    for i = #entry.ids, 1, -1 do
        local id = entry.ids[i]
        if IsPlayerSpell and IsPlayerSpell(id) then return id end
    end
end

-- Whether you know an entry's spell: a rank of it, or (a group) of any of
-- its members. Auras cast by something else than your spell (totem buffs,
-- Demonic Sacrifice's) read as unknown: they only show while up.
local function knowsEntry(entry)
    if not entry.group then return knownRank(entry) ~= nil end
    for _, m in ipairs(entry.members or {}) do
        if knownRank(m) then return true end
    end
    return false
end

-- A group in a cooldown list is one cell: the last member you know (members
-- are in order of preference), as an entry with the group's behaviour and
-- that member's name and spells. Nil when you know none.
local function cooldownMember(entry)
    local members = entry.members or {}
    for i = #members, 1, -1 do
        local m = members[i]
        if m.ids and #m.ids > 0 and knownRank(m) then
            local e = {}
            for k, v in pairs(entry) do e[k] = v end
            e.group, e.members, e.icon = nil, nil, nil
            e.name, e.ids, e.memberWhen = m.name, m.ids, m.when
            return e
        end
    end
end

-- An entry's art: the rank you know, else its lowest ID (Rank 1, the
-- player's spell; the highest IDs are often NPC versions with other art).
local function iconFor(entry)
    local id = entry.icon or knownRank(entry) or entry.ids[1]
    return C_Spell.GetSpellTexture(id)
end

local digitFonts = {}
local function digitFont(px)
    local key = math.floor(px)
    if not digitFonts[key] then
        local name = "SuuUITrackerDigits" .. key
        CreateFont(name):SetFont(T.type["micro"].file, px, "OUTLINE")
        digitFonts[key] = name
    end
    return digitFonts[key]
end

local Cell = {}

-- Per-entry looks (the Behaviour panel): edge colours and sounds.
local EDGE = { ink = "ink", gilt = "gilt", muted = "ink-muted" }
-- Interface sounds every client has. The engine's aura sounds take files only
-- (C_UnitAuras.AddAuraSound: unitToken, spellID, soundFileID), and Forever
-- resolves no file paths, so they are file IDs; the sound kit is the fallback
-- for cooldowns and previews when a file won't play.
local SOUNDS = {
    chime = { file = 567409, kit = "READY_CHECK" },
    ping = { file = 567416, kit = "MAP_PING" },
    proc = { file = 567458, kit = "ALARM_CLOCK_WARNING_2" },
    warning = { file = 567397, kit = "RAID_WARNING" },
}

function UI.TrackerSound(key)
    local s = SOUNDS[key]
    if not s then return end
    local ok, willPlay = pcall(PlaySoundFile, s.file, "Master")
    if not (ok and willPlay) and SOUNDKIT and SOUNDKIT[s.kit] then
        pcall(PlaySound, SOUNDKIT[s.kit], "Master")
    end
end

-- Aura sounds: registered with the engine, which plays them itself when the
-- aura appears, stacks up or drops (in combat too). Any caster's aura of
-- those spells counts: the engine takes no filter here.
local soundIDs, soundWhat = {}, {}

-- For "/suu probe sound play": the files, and what is registered.
function UI.TrackerSoundFiles() return SOUNDS end
function UI.TrackerAuraSounds() return soundIDs, soundWhat end

local function clearAuraSounds()
    for _, id in ipairs(soundIDs) do pcall(C_UnitAuras.RemoveAuraSound, id) end
    soundIDs, soundWhat = {}, {}
end

local function addAuraSounds(entry, unit)
    if not (C_UnitAuras and C_UnitAuras.AddAuraSound and Enum.UnitAuraSoundTrigger) then return end
    local T = Enum.UnitAuraSoundTrigger
    for field, trigger in pairs({ soundAppear = T.Added, soundStack = T.ApplicationsIncreased, soundDrop = T.Removed }) do
        local file = entry[field] and SOUNDS[entry[field]] and SOUNDS[entry[field]].file
        if file and trigger then
            for _, spellID in ipairs(entry.ids or {}) do
                local ok, id = pcall(C_UnitAuras.AddAuraSound, trigger,
                    { unitToken = unit, spellID = spellID, soundFileID = file, outputChannel = "Master" })
                if ok and id then
                    soundIDs[#soundIDs + 1] = id
                    soundWhat[#soundIDs] = ("%s %s %d (%s)"):format(entry.name or "?", field, spellID, unit)
                elseif not ok then
                    soundWhat.error = tostring(id)
                end
            end
        end
    end
end

function Cell:Update(opts)
    local id, e = self.spellID, self.entry
    local info = C_Spell.GetSpellCooldown(id)
    local active = info and known(info.isActive, false) or false
    local gcd = info and known(info.isOnGCD, false) or false
    if active then
        local d = C_Spell.GetSpellCooldownDuration and C_Spell.GetSpellCooldownDuration(id)
        if d then self.cooldown:SetCooldownFromDurationObject(d) end
        self.cooldown:SetHideCountdownNumbers(gcd)
    else
        self.cooldown:Clear()
    end
    local onCooldown = active and not gcd
    if self.onCooldown and not onCooldown then
        -- came ready: the pop (per entry, else the global setting) and its sound
        local pop = e.pop
        if pop == nil then pop = opts.readyPop ~= false end
        if pop then
            self.icon:Pop()
            self.flash:SetAlpha(1)
            Motion.AlphaTo(self.flash, 0, T.duration["dur-slow"])
        end
        if e.sound then UI.TrackerSound(e.sound) end
    end
    self.onCooldown = onCooldown

    local usable, noMana = C_Spell.IsSpellUsable(id)
    local canUse = known(usable, true) and not known(noMana, false)
    -- A reactive ability lights up only while the game says it's usable. In
    -- combat that answer can be secret: then it looks neither ready nor
    -- "use now", just neutral.
    local unsure = self.reactive and not onCooldown and isSecret(usable)
    local useNow = self.reactive and not onCooldown and not isSecret(usable) and usable == true

    -- whether it shows at all: only when ready / only on cooldown, and hide
    -- on cooldown or while unusable
    local show, want = e.show or "always", true
    if (show == "ready" and onCooldown) or (show == "cooldown" and not onCooldown) then want = false end
    if onCooldown and e.onCooldown == "hide" then want = false end
    if not onCooldown and not canUse and e.unusable == "hide" then want = false end
    -- and its live conditions (stance, combat, target), when it has any
    self.wantShown = want and self.condOK ~= false

    local ready = e.ready or "normal"
    local pulse = false
    if onCooldown then
        self.icon:SetBorder(nil)
        -- grey (desaturated) or dim (full colour, faded)
        self.icon:SetState(e.onCooldown == "dim" and "rest" or "dim")
        self.icon:SetGlow(nil)
    elseif useNow then
        self.icon:SetBorder(nil)
        self.icon:SetState("ready")
    elseif unsure then
        self.icon:SetState("rest")
        self.icon:SetBorder(nil)
        self.icon:SetGlow(nil)
    else
        self.icon:SetState("rest")
        self.icon:SetBorder(EDGE[e.border] or "arcane")
        self.icon:SetGlow((ready == "glow" or ready == "pulse") and "glow-arcane" or nil)
        pulse = ready == "pulse"
    end
    -- "Pulse" keeps breathing across updates (they come many times a
    -- second): it starts once and stops only when the cell leaves it
    if pulse and not self.pulse:IsPlaying() then
        self.pulse:Play()
    elseif not pulse and self.pulse:IsPlaying() then
        self.pulse:Stop()
        self.icon:SetAlpha(1)
    end
    self.ring:SetShown(useNow and true or false)
    local alpha = 1
    if onCooldown and e.onCooldown == "dim" then alpha = T.opacity["opacity-oor"]
    elseif not onCooldown and not canUse then alpha = T.opacity["opacity-disabled"] end
    self:SetAlpha(alpha)
end

-- A cell of one size, not yet holding a spell (TR:Cell fills it).
local function newCell(parent, size)
    local f = CreateFrame("Frame", nil, parent)
    Mixin(f, Cell)
    f:SetSize(size, size)
    f.icon = UI.Icon(f, size)
    f.icon:SetAllPoints()
    f.cooldown = CreateFrame("Cooldown", nil, f.icon, "CooldownFrameTemplate")
    f.cooldown:SetPoint("TOPLEFT", 1, -1)
    f.cooldown:SetPoint("BOTTOMRIGHT", -1, 1)
    f.cooldown:SetDrawEdge(false)
    f.cooldown:SetDrawBling(false)
    f.cooldown:SetSwipeColor(0, 0, 0, 0.7)
    f.cooldown:SetHideCountdownNumbers(false)
    if f.cooldown.SetCountdownFont then pcall(f.cooldown.SetCountdownFont, f.cooldown, digitFont(size >= 30 and 12 or T.type["micro"].size)) end
    f.cooldown:HookScript("OnCooldownDone", function() f.dirty = true end)
    local over = CreateFrame("Frame", nil, f)
    over:SetAllPoints()
    over:SetFrameLevel(f.cooldown:GetFrameLevel() + 2)
    f.ring = UI.Border(over, "arcane", { inset = 3, layer = "OVERLAY" })
    f.ring:SetShown(false)
    f.flash = over:CreateTexture(nil, "OVERLAY", nil, 3)
    f.flash:SetAllPoints()
    f.flash:SetColorTexture(UI.RGBA("arcane", 0.35))
    f.flash:SetAlpha(0)
    -- "Pulse" when ready: the icon breathes
    f.pulse = f.icon:CreateAnimationGroup()
    f.pulse:SetLooping("BOUNCE")
    local a = f.pulse:CreateAnimation("Alpha")
    a:SetFromAlpha(1)
    a:SetToAlpha(0.55)
    a:SetDuration(0.6)
    f:EnableMouse(false)
    return f
end

--------------------------------------------------------------------------------
-- Conditions ("Show only when")
--------------------------------------------------------------------------------

local AURA_LISTS = { buffs = true, debuffs = true, procs = true }

-- Static types are checked when the tracker builds (and again when the
-- group, role, zone or talents change); live ones in place, in combat too.
local LIVE = { stance = true, combat = true, target = true }

-- The list a condition chooses from; with nothing chosen it counts as absent.
local CHOICES = { classes = "classes", role = "roles", stance = "stances", instance = "kinds", target = "kinds",
                  talent = "talents" }

-- Shapeshift forms by spell (checked against Forever's spell scan); the
-- names of these spells, in the client's language, catch other IDs.
local FORMS = {
    [2457] = "battle", [71] = "defensive", [2458] = "berserker",
    [5487] = "bear", [9634] = "bear", [768] = "cat", [24858] = "moonkin",
    [783] = "travel", [1066] = "aquatic", [1784] = "stealth", [15473] = "shadowform",
}
local formNames
local function formByName(name)
    if not formNames then
        formNames = {}
        for id, key in pairs(FORMS) do
            local n = C_Spell.GetSpellName(id)
            if n and not isSecret(n) then formNames[n] = key end
        end
    end
    return formNames[name]
end

-- Your stance or form as a key: "caster" in none; a rogue in any form is in
-- Stealth (every rank).
local function currentStance()
    local index = GetShapeshiftForm and GetShapeshiftForm()
    if index == nil or isSecret(index) then return nil end
    if index == 0 then return "caster" end
    local _, class = UnitClass("player")
    if class == "ROGUE" then return "stealth" end
    local _, _, _, spellID = GetShapeshiftFormInfo(index)
    if spellID == nil or isSecret(spellID) then return nil end
    if FORMS[spellID] then return FORMS[spellID] end
    local name = C_Spell.GetSpellName(spellID)
    if name and not isSecret(name) then return formByName(name) end
end

-- Your target as one kind: player, boss, elite or normal (nil: none).
-- Anything the game keeps secret reads as not that.
local function targetKind()
    if not known(UnitExists("target"), false) then return nil end
    if known(UnitIsPlayer("target"), false) then return "player" end
    local class = known(UnitClassification("target"), nil)
    if class == "worldboss" or known(UnitLevel("target"), 0) == -1
        or (UnitIsBossMob and known(UnitIsBossMob("target"), false)) then
        return "boss"
    end
    if class == "elite" or class == "rareelite" then return "elite" end
    return "normal"
end

-- IsInInstance's type as a kind (an arena is pvp, a scenario a dungeon);
-- the design's names are taken too.
local INSTANCE = { none = "none", party = "party", raid = "raid", pvp = "pvp", arena = "pvp", scenario = "party" }
local INSTANCE_ALIAS = { world = "none", dungeon = "party", battleground = "pvp" }
local function instanceKind()
    local inside, kind = IsInInstance()
    if not known(inside, false) then return "none" end
    return INSTANCE[known(kind, "none")] or "none"
end

-- The classes in your group as a set: you included, or (others) only the
-- others. A class the game keeps secret counts as nobody's.
local function rosterClasses(others)
    local set = {}
    local function add(unit)
        if others and known(UnitIsUnit(unit, "player"), false) then return end
        local _, class = UnitClass(unit)
        if not isSecret(class) and class then set[class] = true end
    end
    if not others then add("player") end
    if known(IsInRaid and IsInRaid(), false) then
        for i = 1, 40 do add("raid" .. i) end
    else
        for i = 1, 4 do add("party" .. i) end
    end
    return set
end

-- The talents you've learned, as a set of spell IDs: every node of the
-- active talent config with a rank (Forever lays the three trees out in one),
-- its chosen entry's spell (else every entry's). Read once and kept until
-- the talents or the spellbook change (forgetTalents); nil while there's no
-- config to read (right after login), so it's read again next time.
local talentCache

local function hasRank(ni)
    for _, k in ipairs({ "ranksPurchased", "activeRank", "currentRank" }) do
        local r = ni[k]
        if r ~= nil and not isSecret(r) and r > 0 then return true end
    end
    return false
end

local function readTalents()
    local cfg = C_ClassTalents and C_ClassTalents.GetActiveConfigID and C_ClassTalents.GetActiveConfigID()
    if cfg == nil or isSecret(cfg) or not C_Traits then return nil end
    local info = C_Traits.GetConfigInfo(cfg)
    if not (info and info.treeIDs) then return nil end
    local set = {}
    local function addEntry(entryID)
        if entryID == nil or isSecret(entryID) then return end
        local ei = C_Traits.GetEntryInfo(cfg, entryID)
        local def = ei and ei.definitionID
        local di = def and not isSecret(def) and C_Traits.GetDefinitionInfo(def)
        if not di then return end
        if di.spellID and not isSecret(di.spellID) then set[di.spellID] = true end
        if di.overriddenSpellID and not isSecret(di.overriddenSpellID) then set[di.overriddenSpellID] = true end
    end
    for _, treeID in ipairs(info.treeIDs) do
        for _, nodeID in ipairs(C_Traits.GetTreeNodes(treeID) or {}) do
            local ni = C_Traits.GetNodeInfo(cfg, nodeID)
            if ni and hasRank(ni) then
                local active = ni.activeEntry and ni.activeEntry.entryID
                if active ~= nil and not isSecret(active) then
                    addEntry(active)
                else
                    for _, entryID in ipairs(ni.entryIDs or {}) do addEntry(entryID) end
                end
            end
        end
    end
    return set
end

local function learnedTalents()
    if not talentCache then
        local ok, set = pcall(readTalents)
        talentCache = ok and set or nil
    end
    return talentCache or {}
end

local function forgetTalents() talentCache = nil end

-- What a pass over many conditions looks up once (ctx[key], from fn).
local function look(ctx, key, fn)
    local v = ctx[key]
    if v == nil then
        v = fn()
        if v == nil then v = false end
        ctx[key] = v
    end
    return v
end

local function has(list, value, alias)
    for _, v in ipairs(list) do
        if v == value or (alias and alias[v] == value) then return true end
    end
    return false
end

-- Each type's test, before "not". ctx.combat, when set, is the tracker's
-- own idea of combat (it knows the moment combat starts and ends).
local TEST = {
    group = function(c)
        local raid = known(IsInRaid and IsInRaid(), false)
        if c.value == "raid" then return raid end
        local group = raid or known(IsInGroup and IsInGroup(), false)
        if c.value == "solo" then return not group end
        return group
    end,
    classes = function(c, ctx)
        local others = c.others and true or false
        local roster = look(ctx, others and "rosterOthers" or "roster", function() return rosterClasses(others) end)
        for _, class in ipairs(c.classes) do
            if roster[class] then return true end
        end
        return false
    end,
    role = function(c, ctx)
        return has(c.roles, look(ctx, "role", function() return ns.Roles and ns.Roles.Current() end))
    end,
    instance = function(c, ctx)
        return has(c.kinds, look(ctx, "instance", instanceKind), INSTANCE_ALIAS)
    end,
    stance = function(c, ctx)
        return has(c.stances, look(ctx, "stance", currentStance))
    end,
    combat = function(_, ctx)
        if ctx.combat ~= nil then return ctx.combat end
        return InCombatLockdown() or known(UnitAffectingCombat("player"), false)
    end,
    target = function(c, ctx)
        return has(c.kinds, look(ctx, "target", targetKind))
    end,
    -- any of them learned: in the talent config, else a spell you know
    talent = function(c, ctx)
        local learned = look(ctx, "talents", learnedTalents)
        for _, id in ipairs(c.talents) do
            if type(id) == "number" then
                if learned[id] then return true end
                if IsPlayerSpell and known(IsPlayerSpell(id), false) then return true end
            end
        end
        return false
    end,
}

-- A condition that counts: a known type, and something chosen.
local function counts(c)
    if type(c) ~= "table" or not TEST[c.type] then return false end
    local field = CHOICES[c.type]
    return not field or (type(c[field]) == "table" and #c[field] > 0)
end

local function test(c, ctx)
    local r = TEST[c.type](c, ctx) and true or false
    if c["not"] then return not r end
    return r
end

-- Whether a `when` is met now (no conditions: always).
local function conditionMet(when, ctx)
    if type(when) ~= "table" or type(when.conditions) ~= "table" then return true end
    ctx = ctx or {}
    local any, counted = when.match == "any", false
    for _, c in ipairs(when.conditions) do
        if counts(c) then
            counted = true
            local r = test(c, ctx)
            if any and r then return true end
            if not any and not r then return false end
        end
    end
    return not (any and counted)
end

function UI.CooldownConditionMet(when) return conditionMet(when, {}) end

-- A `when` as the build sees it, from its static conditions alone: "met",
-- "unmet", or "live" (it turns on stance, combat or the target: built, and
-- shown or hidden in place). With "any", one static condition met is enough;
-- otherwise it is live while a live one could still make it true.
local function staticState(when, ctx)
    if type(when) ~= "table" or type(when.conditions) ~= "table" then return "met" end
    local any, counted, live = when.match == "any", false, false
    for _, c in ipairs(when.conditions) do
        if counts(c) then
            if LIVE[c.type] then
                live = true
            else
                counted = true
                local r = test(c, ctx)
                if any and r then return "met" end
                if not any and not r then return "unmet" end
            end
        end
    end
    if live then return "live" end
    return (any and counted) and "unmet" or "met"
end

-- Several `when`s that must all hold (a collection's and its entry's, a
-- slot's and its member's): their list with `when` added (nil ones left out).
local function chain(whens, when)
    local out = {}
    for _, w in ipairs(whens or {}) do out[#out + 1] = w end
    if when then out[#out + 1] = when end
    return out
end

local function stateOf(whens, ctx)
    local live = false
    for _, w in ipairs(whens) do
        local s = staticState(w, ctx)
        if s == "unmet" then return "unmet" end
        if s == "live" then live = true end
    end
    return live and "live" or "met"
end

local function allMet(whens, ctx)
    for _, w in ipairs(whens) do
        if not conditionMet(w, ctx) then return false end
    end
    return true
end

-- A group without the members whose condition can't be met now: a copy,
-- its IDs their union. Anything else as it is. (Members with a live
-- condition stay: auraParts gives each its own engine group.)
local function withMetMembers(entry, ctx)
    if not entry.group then return entry end
    local conditional = false
    for _, m in ipairs(entry.members or {}) do
        if m.when then conditional = true; break end
    end
    if not conditional then return entry end
    local e, members, ids, seen = {}, {}, {}, {}
    for k, v in pairs(entry) do e[k] = v end
    for _, m in ipairs(entry.members) do
        if staticState(m.when, ctx) ~= "unmet" then
            members[#members + 1] = m
            for _, id in ipairs(m.ids or {}) do
                if not seen[id] then seen[id] = true; ids[#ids + 1] = id end
            end
        end
    end
    table.sort(ids)
    e.members, e.ids = members, ids
    return e
end

--------------------------------------------------------------------------------
-- Aura slots
--------------------------------------------------------------------------------

-- An aura entry's size and looks (the Behaviour panel).
local AURA_SIZE = { small = "icon-md", normal = "icon-lg", large = "cdm-essential" }
local function auraSize(entry) return UI.Size(AURA_SIZE[entry.size or "normal"] or "icon-lg") end
local function auraLook(entry, base)
    local look = {}
    for k, v in pairs(base or {}) do look[k] = v end
    if entry.border and EDGE[entry.border] then look.border = EDGE[entry.border] end
    if entry.glow then look.glow = "glow-arcane" end
    look.digits, look.stacks = entry.digits, entry.stacks
    look.expiring = entry.expiring
    return look
end

-- The art of a fixed slot or reminder while nothing is up: a single aura's
-- (iconFor); a shared slot's `icon` when fixedIcon is set, else automatic:
-- the first member (of those its conditions leave in) that you know, else
-- the first whose `when` is met now (none: met), else `icon`. A member's art
-- is its own `icon`, else its first ID.
local function slotArt(entry, ctx)
    if not entry.group or entry.fixedIcon then return iconFor(entry) end
    local members = entry.members or {}
    local function art(m) return C_Spell.GetSpellTexture(m.icon or m.ids[1]) end
    for _, m in ipairs(members) do
        if m.ids and #m.ids > 0 and knownRank(m) then return art(m) end
    end
    for _, m in ipairs(members) do
        if m.ids and #m.ids > 0 and conditionMet(m.when, ctx) then return art(m) end
    end
    return iconFor(entry)
end

-- A fixed slot: the grey placeholder, and over it a one-icon container that
-- shows the entry's aura while it's up (`copts`, its options). TR:Slot sets
-- the placeholder's art.
local function newSlot(parent, warn, max, size, unit, copts)
    local f = CreateFrame("Frame", nil, parent)
    f:SetSize(max * size + (max - 1) * S["space-2"], size)
    -- the placeholder sits under the first place (where the first member lands)
    f.placeholder = CreateFrame("Frame", nil, f)
    f.placeholder:SetPoint("TOPLEFT")
    f.placeholder:SetSize(size, size)
    local art = f.placeholder:CreateTexture(nil, "ARTWORK")
    art:SetPoint("TOPLEFT", 1, -1)
    art:SetPoint("BOTTOMRIGHT", -1, 1)
    art:SetTexCoord(CROP, 1 - CROP, CROP, 1 - CROP)
    art:SetDesaturated(true)
    f.art = art
    UI.Fill(f.placeholder, "surface-sunk", "BACKGROUND"):SetAllPoints()
    UI.Border(f.placeholder, "gilt-hairline", { layer = "OVERLAY" })
    f.placeholder:SetAlpha(T.opacity["opacity-oor"])
    -- Warn: an ember edge inside the square that pulses slowly
    if warn then
        UI.Border(f.placeholder, "ember", { inset = 1, layer = "OVERLAY" })
        local pulse = f.placeholder:CreateAnimationGroup()
        pulse:SetLooping("BOUNCE")
        local a = pulse:CreateAnimation("Alpha")
        a:SetFromAlpha(1)
        a:SetToAlpha(0.45)
        a:SetDuration(0.9)
        f.placeholder:SetAlpha(0.85)
        pulse:Play()
    end
    f.container = UI.AuraContainer(f, unit, copts)
    if f.container then
        f.container.container:SetPoint("TOPLEFT", f, "TOPLEFT")
        f.container.container:SetFrameLevel(f.placeholder:GetFrameLevel() + 2)
    end
    return f
end

-- A reminder: the grey icon alone, no live aura. Shown while the aura isn't
-- up, out of combat. TR:Reminder sets what it reminds of.
local function newReminder(parent, size)
    local f = CreateFrame("Frame", nil, parent)
    f:SetSize(size, size)
    local art = f:CreateTexture(nil, "ARTWORK")
    art:SetPoint("TOPLEFT", 1, -1)
    art:SetPoint("BOTTOMRIGHT", -1, 1)
    art:SetTexCoord(CROP, 1 - CROP, CROP, 1 - CROP)
    art:SetDesaturated(true)
    f.art = art
    UI.Fill(f, "surface-sunk", "BACKGROUND"):SetAllPoints()
    UI.Border(f, "gilt-hairline", { layer = "OVERLAY" })
    f:SetAlpha(T.opacity["opacity-oor"])
    return f
end

-- Whether any of a reminder's IDs is on its unit (out of combat only), each
-- source's under its own filter; a member whose live condition isn't met
-- doesn't count.
local function auraUp(r, ctx)
    for _, check in ipairs(r.checks) do
        local counted = not check.when or conditionMet(check.when, ctx)
        for i = 1, counted and 40 or 0 do
            local ok, a = pcall(C_UnitAuras.GetAuraDataByIndex, r.unit, i, check.filter)
            if not ok or isSecret(a) or not a then break end
            if not isSecret(a.spellId) and check.ids[a.spellId] then return true end
        end
    end
    return false
end

-- The filter for an entry: kind ("HELPFUL"/"HARMFUL") plus its source.
-- An entry's own source (the Behaviour panel, or a group's), else the list's
-- default (a preset's "mine" on a buff counts as its own).
local function sourceFilter(kind, entry, default)
    local source = entry.source or (entry.group and "mine") or (entry.mine and "mine") or default
    if source == "mine" then return { kind, "PLAYER" } end
    if source == "others" then return { kind, "!PLAYER" } end
    return { kind }
end

-- An aura entry's engine groups, { filter, ids, when } each: one for a
-- single aura or a group whose members share a source; else one per source
-- its members use (a member's own, else the group's), in member order. A
-- member with a live condition gets a group of its own, carrying its `when`
-- (the group's max is how it's shown or hidden).
local function auraParts(kind, entry, default, ctx)
    local single = { { filter = sourceFilter(kind, entry, default), ids = entry.ids } }
    if not entry.group then return single end
    local own = entry.source or "mine"
    local parts, bySource = {}, {}
    for i, m in ipairs(entry.members or {}) do
        local source = m.source or own
        local live = m.when and staticState(m.when, ctx or {}) == "live"
        local key = live and (source .. "#" .. i) or source
        local p = bySource[key]
        if not p then
            p = { filter = sourceFilter(kind, { source = source }, default), ids = {}, seen = {}, when = live and m.when or nil }
            bySource[key] = p
            parts[#parts + 1] = p
        end
        for _, id in ipairs(m.ids or {}) do
            if not p.seen[id] then p.seen[id] = true; p.ids[#p.ids + 1] = id end
        end
    end
    local out = {}
    for _, p in ipairs(parts) do
        if #p.ids > 0 then out[#out + 1] = { filter = p.filter, ids = p.ids, when = p.when } end
    end
    return (#out > 1 or (out[1] and out[1].when)) and out or single
end

--------------------------------------------------------------------------------
-- Building
--------------------------------------------------------------------------------

-- Rebuilds reuse what earlier builds made: an engine aura container can
-- never be freed, and cells and slots would pile up too. Each is kept under a
-- key of everything fixed when it was made (for a container: its unit, size,
-- flow and every group setting); a build takes a spare with the same key, or
-- makes one. Clear hands everything back (containers released: no unit,
-- hidden, deaf).

-- Everything about a container that is fixed at creation, as one string.
local function containerKey(unit, opts)
    local parts = { unit, tostring(opts.size), tostring(opts.anchor), table.concat(opts.growth or {}, ",") }
    for _, g in ipairs(opts.groups) do
        parts[#parts + 1] = table.concat({ g.key, table.concat(g.filter, ","), tostring(g.max),
            table.concat(g.include or {}, ","), table.concat(g.dispelTypes or {}, ","),
            tostring(g.border), tostring(g.glow), tostring(g.drain), tostring(g.digits),
            tostring(g.stacks), tostring(g.expiring), tostring(g.size) }, "/")
    end
    return table.concat(parts, ";")
end

-- A spare made under `key`, else a new one from make() (nil if it makes
-- none); the second value is true for a new one.
function TR:Take(key, make)
    local spare = self.spare[key]
    local thing = spare and table.remove(spare)
    local fresh = not thing
    if fresh then thing = make() end
    if not thing then return nil end
    self.taken[#self.taken + 1] = { key = key, thing = thing }
    return thing, fresh
end

-- A spare container's groups back at their own max (a live condition may
-- have set one to 0).
local function resetMax(ac, groups)
    for _, g in ipairs(groups) do ac:SetGroupMax(g.key, g.max or 16) end
end

-- An aura container on the tracker.
function TR:Aura(unit, opts)
    local ac, fresh = self:Take("aura|" .. containerKey(unit, opts), function() return UI.AuraContainer(self, unit, opts) end)
    if ac and not fresh then
        resetMax(ac, opts.groups)
        ac:SetUnit(unit)
    end
    return ac
end

-- Live conditions (stance, combat, target): a cell, slot or reminder that
-- shows only while its `whens` all hold (nil: always; UpdateLive decides).
function TR:Watch(thing, whens)
    thing.whens, thing.condOK = whens, nil
    if whens then self.liveFrames[#self.liveFrames + 1] = thing end
end

-- The engine groups of a container that carry `whens` (a packed entry's, a
-- live member's, an effect's): UpdateLive sets each one's max to 0 or back.
function TR:WatchGroups(ac, groups)
    if not ac then return end
    for _, g in ipairs(groups) do
        if g.whens then
            self.liveGroups[#self.liveGroups + 1] = { ac = ac, key = g.key, max = g.max or 16, applied = g.max or 16, whens = g.whens }
        end
    end
end

-- A cooldown cell for an entry: a clean state (a reused cell must not pop
-- as "ready"), and its effect.
function TR:Cell(entry, spellID, size)
    local f = self:Take("cell|" .. size, function() return newCell(self, size) end)
    f.entry, f.spellID = entry, spellID
    f.reactive = REACTIVE[entry.name] or false
    f.icon:SetArt(C_Spell.GetSpellTexture(spellID))
    f.onCooldown, f.dirty, f.wantShown = nil, nil, nil
    f.whens, f.condOK = nil, nil
    if f.pulse:IsPlaying() then f.pulse:Stop() end
    f.icon:SetAlpha(1)
    Motion.AlphaTo(f.flash, 0, 0)
    f.cooldown:Clear()
    f:SetAlpha(1)
    f:Show()
    -- "Effect running": the effect's aura over the icon, above the sweep and
    -- below the ready ring and flash. It hangs on the tracker, not the cell,
    -- so a cell hidden or dimmed on cooldown leaves the effect full.
    f.container = nil
    local fx = entry.effect == "you" and "player" or (entry.effect == "target" and "target")
    local fxIDs = entry.effectIDs and #entry.effectIDs > 0 and entry.effectIDs or entry.ids
    if fx and fxIDs and #fxIDs > 0 then
        f.container = self:Aura(fx, {
            size = size, anchor = "TOPLEFT", growth = { "RIGHT", "DOWN" },
            groups = { { key = "fx", filter = { fx == "player" and "HELPFUL" or "HARMFUL", "PLAYER" }, max = 1,
                         include = fxIDs, border = "gilt", glow = "glow-ward" } },
        })
        if f.container then
            local c = f.container.container
            c:ClearAllPoints()
            c:SetPoint("TOPLEFT", f, "TOPLEFT")
            c:SetFrameLevel(f.cooldown:GetFrameLevel() + 1)
        end
    end
    return f
end

-- A fixed slot for an aura entry: an engine group per part (auraParts); a
-- part with a live member's condition is watched.
function TR:Slot(entry, unit, parts, size, look)
    look = look or {}
    local max = entry.group and math.max(1, math.min(4, entry.max or 1)) or 1
    local groups = {}
    for i, p in ipairs(parts) do
        groups[i] = { key = i == 1 and "e" or ("e" .. i), filter = p.filter, max = max, include = p.ids,
                      border = look.border, glow = look.glow, drain = look.drain,
                      digits = look.digits, stacks = look.stacks, expiring = look.expiring,
                      whens = p.when and { p.when } or nil }
    end
    local copts = { size = size, anchor = "TOPLEFT", growth = { "RIGHT", "DOWN" }, groups = groups }
    local warn = entry.missing == "warn"
    local f, fresh = self:Take(("slot|%s|%s"):format(tostring(warn), containerKey(unit, copts)),
        function() return newSlot(self, warn, max, size, unit, copts) end)
    if not fresh then
        f:Show()
        if f.container then
            resetMax(f.container, groups)
            f.container:SetUnit(unit)
        end
    end
    self:WatchGroups(f.container, groups)
    f.art:SetTexture(slotArt(entry, {}))
    f.withTarget, f.coll, f.whens, f.condOK = nil, nil, nil, nil
    return f
end

-- A reminder for an aura entry (hidden until UpdateReminders shows it): its
-- parts' IDs, each under its filter.
function TR:Reminder(entry, unit, parts, size)
    local f = self:Take("remind|" .. size, function() return newReminder(self, size) end)
    f.art:SetTexture(slotArt(entry, {}))
    f.unit, f.checks, f.coll, f.whens, f.condOK = unit, {}, nil, nil, nil
    for _, p in ipairs(parts) do
        local ids = {}
        for _, id in ipairs(p.ids) do ids[id] = true end
        f.checks[#f.checks + 1] = { filter = table.concat(p.filter, "|"), ids = ids, when = p.when }
    end
    f:Hide()
    return f
end

-- Hands back everything built (kept for the next build).
function TR:Clear()
    for _, t in ipairs(self.taken or {}) do
        local thing = t.thing
        if t.key:find("^aura|") then
            thing:Release()
        else
            thing:Hide()
            -- a slot's own container goes with it
            if t.key:find("^slot|") and thing.container then thing.container:Release() end
        end
        self.spare[t.key] = self.spare[t.key] or {}
        table.insert(self.spare[t.key], thing)
    end
    self.taken = {}
    self.built = { essential = {}, utility = {}, buffs = {}, debuffs = {}, remindBuffs = {}, remindDebuffs = {} }
    self.cells = {}
    self.liveFrames, self.liveGroups = {}, {}
    self.leftFlow, self.rightFlow = nil, nil
end

-- Builds the rows from the lists. Out of combat (it creates engine containers,
-- or takes spare ones).
function TR:Build()
    self:Clear()
    local opts = self.opts or {}
    -- Entries without spells (a group just made) are skipped: an empty spell
    -- list would let the engine show every aura.
    -- Aura lists: a collection's entries take its place (unless it's
    -- hidden), and a hidden entry is left out. Every list: an entry whose
    -- conditions can't be met now (its own, or its collection's) is left
    -- out, as is a group's member whose condition can't; one that turns on a
    -- live condition is built and watched (whensOf: the `when`s it waits
    -- for). collOf: the collection an entry came from.
    local lists, collOf, whensOf, ctx = {}, {}, {}, {}
    for key, list in pairs(self.lists or {}) do
        lists[key] = {}
        local aurasList = AURA_LISTS[key]
        local function add(e, coll)
            -- turned off in the lists (presets ship some auras off)
            if aurasList and e.hidden then return end
            local whens = chain(coll and { coll.when }, e.when)
            local state = stateOf(whens, ctx)
            if state == "unmet" then return end
            e = withMetMembers(e, ctx)
            if e.ids and #e.ids > 0 then
                table.insert(lists[key], e)
                collOf[e] = coll
                if state == "live" then whensOf[e] = whens end
            end
        end
        for _, e in ipairs(list) do
            if not e.collection then
                add(e)
            elseif aurasList and not e.hidden and staticState(e.when, ctx) ~= "unmet" then
                for _, sub in ipairs(e.entries or {}) do
                    if not sub.collection then add(sub, e) end
                end
            end
        end
    end
    local aura = UI.Size(AURA)
    local essential = opts.essentialSize or UI.Size("cdm-essential")
    local utility = UI.Size(opts.utilityInline and essential or "icon-lg")

    for _, key in ipairs({ "essential", "utility" }) do
        for _, listed in ipairs(lists[key] or {}) do
            -- a group: the cell of the last member you know
            local entry = listed.group and cooldownMember(listed) or (not listed.group and listed)
            local id = entry and not entry.hidden and knownRank(entry)
            if id then
                local cell = self:Cell(entry, id, key == "essential" and essential or utility)
                -- its conditions, and the shown member's if live
                local whens = whensOf[listed]
                if entry.memberWhen and staticState(entry.memberWhen, ctx) == "live" then
                    whens = chain(whens, entry.memberWhen)
                end
                self:Watch(cell, whens)
                -- its effect hides with it
                if whens and cell.container then
                    self:WatchGroups(cell.container, { { key = "fx", max = 1, whens = whens } })
                end
                table.insert(self.built[key], cell)
                self.cells[#self.cells + 1] = cell
            end
        end
    end

    local proc = opts.procHighlight ~= false and { border = "arcane", glow = "glow-arcane" } or nil
    -- an entry's engine groups in a packed container, one per part; with a
    -- live condition (the entry's, or a member's) each carries its `whens`
    local function auraGroups(out, key, entry, parts, base)
        local look = auraLook(entry, base)
        for i, p in ipairs(parts) do
            local whens = whensOf[entry]
            if p.when then whens = chain(whens, p.when) end
            out[#out + 1] = { key = i == 1 and key or (key .. "s" .. i), filter = p.filter,
                max = entry.group and (entry.max or 1) or 1, include = p.ids,
                border = look.border, glow = look.glow, digits = look.digits, stacks = look.stacks,
                expiring = look.expiring, size = auraSize(entry), whens = whens }
        end
    end

    -- Buffs: grey keeps a fixed slot per entry (never empty: the placeholder
    -- shows); hide packs them into one container the engine closes up. The
    -- left side grows away from the divider, procs after the buffs.
    -- Each entry's "when missing" (its own, else the list's): grey keeps a
    -- fixed slot, hide joins the packed container beyond the fixed ones.
    local leftGroups = {}
    -- A buff you don't know gets no grey slot or reminder (a level 12 priest
    -- isn't reminded of Shadow Protection); it packs with the hidden ones.
    for i, entry in ipairs(lists.buffs or {}) do
        local parts = auraParts("HELPFUL", entry, "any", ctx)
        local mode = entry.missing or "grey"
        if mode == "hide" or not knowsEntry(entry) then
            auraGroups(leftGroups, "b" .. i, entry, parts)
        elseif mode == "remind" then
            local r = self:Reminder(entry, "player", parts, auraSize(entry))
            r.coll = collOf[entry]
            self:Watch(r, whensOf[entry])
            table.insert(self.built.remindBuffs, r)
        else
            local slot = self:Slot(entry, "player", parts, auraSize(entry), auraLook(entry))
            slot.coll = collOf[entry]
            self:Watch(slot, whensOf[entry])
            table.insert(self.built.buffs, slot)
        end
    end
    for i, entry in ipairs(lists.procs or {}) do
        auraGroups(leftGroups, "p" .. i, entry, auraParts("HELPFUL", entry, "mine", ctx), proc)
    end
    if #leftGroups > 0 then
        self.leftFlow = self:Aura("player", { size = aura, anchor = "BOTTOMRIGHT", growth = { "LEFT", "UP" }, groups = leftGroups })
        self:WatchGroups(self.leftFlow, leftGroups)
    end

    -- Your debuffs on the target: hide packs them, growing right of the
    -- divider; grey and "with a target" keep fixed slots.
    -- A debuff from a spell you know no rank of gets no grey slot (it would
    -- remind you of something you can't cast); it packs with the hidden ones.
    local groups = {}
    for i, entry in ipairs(lists.debuffs or {}) do
        local mode = entry.missing or "target"
        local parts = auraParts("HARMFUL", entry, "mine", ctx)
        -- a single debuff you know no rank of gets no grey slot; groups always
        -- do (their members are often auras you don't cast directly, such as
        -- the judgements that "Judgement" puts on the target)
        if mode == "hide" or (not entry.group and not knownRank(entry)) then
            auraGroups(groups, "d" .. i, entry, parts)
        elseif mode == "remind" then
            local r = self:Reminder(entry, "target", parts, auraSize(entry))
            r.coll = collOf[entry]
            self:Watch(r, whensOf[entry])
            table.insert(self.built.remindDebuffs, r)
        else
            local slot = self:Slot(entry, "target", parts, auraSize(entry), auraLook(entry))
            -- grey (and a warning's pulse) only while you have a hostile target:
            -- a debuff can't be missing from nothing
            slot.withTarget = mode == "target" or mode == "warn"
            slot.coll = collOf[entry]
            self:Watch(slot, whensOf[entry])
            table.insert(self.built.debuffs, slot)
        end
    end
    if #groups > 0 then
        self.rightFlow = self:Aura("target", { size = aura, anchor = "BOTTOMLEFT", growth = { "RIGHT", "UP" }, groups = groups })
        self:WatchGroups(self.rightFlow, groups)
    end
    -- the timers row is as tall as its largest icon
    self.rowH = aura
    for _, key in ipairs({ "buffs", "debuffs", "procs" }) do
        for _, entry in ipairs(lists[key] or {}) do self.rowH = math.max(self.rowH, auraSize(entry)) end
    end
    self.hasLeft = #(lists.buffs or {}) + #(lists.procs or {}) > 0
    self.hasRight = #(lists.debuffs or {}) > 0

    -- the aura sounds of every aura entry
    clearAuraSounds()
    for _, entry in ipairs(lists.buffs or {}) do addAuraSounds(entry, "player") end
    for _, entry in ipairs(lists.procs or {}) do addAuraSounds(entry, "player") end
    for _, entry in ipairs(lists.debuffs or {}) do addAuraSounds(entry, "target") end

    self.knownSig = self:KnownSignature()
    self.condSig = self:ConditionSignature()
    self:UpdateLive(true)
    self:UpdateReminders(true)
    self:Layout()
    self:UpdateMissing()
    self:UpdateCooldowns()
end

-- Centred rows, top to bottom: timers, Essential, Utility (or Utility after
-- Essential with a gilt divider).
function TR:Layout()
    local opts = self.opts or {}
    local aura = UI.Size(AURA)
    local gapRow = S["space-3"]

    local function shown(list)
        local out = {}
        for _, f in ipairs(list) do if f:IsShown() then out[#out + 1] = f end end
        return out
    end
    -- a cell hidden on cooldown keeps its place while it has an effect to
    -- show there (the effect hangs on the tracker, over the cell's spot);
    -- one whose live conditions aren't met doesn't
    local function cells(list)
        local out = {}
        for _, f in ipairs(list) do
            if f.condOK ~= false and (f:IsShown() or (f.container and f.onCooldown)) then out[#out + 1] = f end
        end
        return out
    end
    -- fixed slots whose live conditions are met (the rest close up)
    local function present(list)
        local out = {}
        for _, f in ipairs(list) do if f.condOK ~= false then out[#out + 1] = f end end
        return out
    end
    local ess, util = cells(self.built.essential), cells(self.built.utility)
    local function rowWidth(cells, gap)
        local w = 0
        for i, c in ipairs(cells) do w = w + c:GetWidth() + (i > 1 and gap or 0) end
        return w
    end
    local essW = rowWidth(ess, S["space-3"])
    local utilW = rowWidth(util, S["space-2"])
    local inline = opts.utilityInline and #util > 0
    local bottomW = inline and (essW + (essW > 0 and S["space-4"] * 2 + 1 or 0) + utilW) or essW

    -- the timers row centres on its divider: buffs and procs to its left,
    -- your debuffs to its right (packed lists grow away from it)
    -- outward from the divider: grey slots, then reminders (then the packed)
    local left, right = {}, {}
    for _, c in ipairs(present(self.built.buffs)) do left[#left + 1] = c end
    for _, c in ipairs(shown(self.built.remindBuffs)) do left[#left + 1] = c end
    for _, c in ipairs(present(self.built.debuffs)) do right[#right + 1] = c end
    for _, c in ipairs(shown(self.built.remindDebuffs)) do right[#right + 1] = c end
    -- a collection's fixed slots sit apart from their neighbours: a hairline
    -- with space-2 plus space-1 either side of it
    local SIDE = S["space-2"] + S["space-1"]
    local function apart(a, b) return (a.coll or b.coll) and a.coll ~= b.coll end
    local function gap(a, b) return apart(a, b) and (SIDE * 2 + 1) or S["space-2"] end
    -- slots can be wider than one icon (a group showing several members)
    local function span(list)
        local w = 0
        for i, c in ipairs(list) do w = w + c:GetWidth() + (i > 1 and gap(list[i - 1], c) or 0) end
        return w
    end
    local leftW = span(left)
    local rightW = span(right)
    local half = math.max(leftW, rightW) + S["space-4"]
    local timersW = (self.hasLeft or self.hasRight) and (half * 2 + 1) or 0

    local width = math.max(timersW, bottomW, inline and 0 or utilW, aura)
    local y = 0
    local function place(cells, gap, rowW, bottomY, startX)
        local x = startX or (width - rowW) / 2
        for _, c in ipairs(cells) do
            c:ClearAllPoints()
            c:SetPoint("BOTTOMLEFT", self, "BOTTOMLEFT", math.floor(x + 0.5), bottomY)
            x = x + c:GetWidth() + gap
        end
        return x
    end

    -- Utility row (own row) at the bottom
    if not inline and #util > 0 then
        place(util, S["space-2"], utilW, y)
        y = y + UI.Size("icon-lg") + gapRow
    end
    -- Essential (and inline Utility)
    self.divider:Hide()
    if #ess > 0 or inline then
        local x = place(ess, S["space-3"], bottomW, y)
        if inline then
            self.divider:ClearAllPoints()
            local h = (opts.essentialSize or UI.Size("cdm-essential"))
            self.divider:SetSize(1, h)
            self.divider:SetPoint("BOTTOMLEFT", self, "BOTTOMLEFT", math.floor(x - S["space-3"] + S["space-4"] + 0.5), y)
            self.divider:Show()
            place(util, S["space-2"], utilW, y, x - S["space-3"] + S["space-4"] * 2 + 1)
        end
        y = y + (opts.essentialSize or UI.Size("cdm-essential")) + gapRow
    end
    -- Timers
    self.auraDivider:Hide()
    for _, side in ipairs({ self.sepLeft, self.sepRight }) do
        for _, h in ipairs(side.lines) do h:Hide() end
        side.used = 0
    end
    -- a hairline on a side's layer, its left edge at x
    local function hairline(side, x, y)
        side.used = side.used + 1
        local h = side.lines[side.used]
        if not h then
            h = UI.Fill(side, "gilt-hairline", "ARTWORK")
            side.lines[side.used] = h
        end
        h:ClearAllPoints()
        h:SetSize(1, aura - S["space-2"] * 2)
        h:SetPoint("BOTTOMLEFT", self, "BOTTOMLEFT", math.floor(x + 0.5), y + S["space-2"])
        h:Show()
    end
    if self.hasLeft or self.hasRight then
        local mid = math.floor(width / 2)
        if self.hasLeft and self.hasRight then
            self.auraDivider:ClearAllPoints()
            self.auraDivider:SetSize(1, self.rowH or aura)
            self.auraDivider:SetPoint("BOTTOMLEFT", self, "BOTTOMLEFT", mid, y)
            self.auraDivider:Show()
        end
        -- left side: fixed buff slots end space-4 left of the divider, the
        -- packed buffs and procs continue left of them
        local leftEnd = mid - S["space-4"]
        -- outward from the divider: grey slots, then reminders, then packed
        local x = leftEnd
        for i, c in ipairs(left) do
            if i > 1 then
                if apart(left[i - 1], c) then hairline(self.sepLeft, x - SIDE - 1, y) end
                x = x - gap(left[i - 1], c)
            end
            x = x - c:GetWidth()
            c:ClearAllPoints()
            c:SetPoint("BOTTOMLEFT", self, "BOTTOMLEFT", x, y)
        end
        if self.leftFlow then
            local edge = #left > 0 and (x - S["space-2"]) or leftEnd
            self.leftFlow.container:ClearAllPoints()
            self.leftFlow.container:SetPoint("BOTTOMRIGHT", self, "BOTTOMLEFT", edge, y)
        end
        -- right side: debuffs start space-4 right of the divider
        local rightStart = mid + 1 + S["space-4"]
        local rx = rightStart
        for i, c in ipairs(right) do
            if i > 1 then
                if apart(right[i - 1], c) then hairline(self.sepRight, rx + SIDE, y) end
                rx = rx + gap(right[i - 1], c)
            end
            c:ClearAllPoints()
            c:SetPoint("BOTTOMLEFT", self, "BOTTOMLEFT", math.floor(rx + 0.5), y)
            rx = rx + c:GetWidth()
        end
        if self.rightFlow then
            local edge = #right > 0 and (rx + S["space-2"]) or rightStart
            self.rightFlow.container:ClearAllPoints()
            self.rightFlow.container:SetPoint("BOTTOMLEFT", self, "BOTTOMLEFT", edge, y)
        end
        y = y + (self.rowH or aura)
    end

    self:SetSize(math.max(width, 1), math.max(y, 1))
end

-- The grey placeholders: per list, hidden or shown (debuffs optionally only
-- while you have a hostile target; that test may be secret, so the engine
-- applies it as an alpha).
function TR:UpdateMissing()
    local opts = self.opts or {}
    -- fixed slots are the grey ones: their placeholder always shows; a
    -- "with a target" list shows its debuff slots only on a hostile target
    for _, slot in ipairs(self.built.buffs) do slot.placeholder:Show() end
    -- the hairline goes with them when every debuff slot waits for a target
    local allTarget = #self.built.debuffs > 0
    for _, slot in ipairs(self.built.debuffs) do
        if not slot.withTarget then allTarget = false end
    end
    if self.sepRight then self.sepRight.withTarget = allTarget end
    -- the debuff side's collection hairlines too: they'd stand alone between
    -- hidden slots
    local slots = { self.sepRight }
    for _, slot in ipairs(self.built.debuffs) do slots[#slots + 1] = slot end
    for _, slot in ipairs(slots) do
        if slot.placeholder then slot.placeholder:Show() end
        if slot.withTarget then
            local hostile = UnitExists("target") and UnitCanAttack("player", "target")
            if slot.SetAlphaFromBoolean and (isSecret(hostile) or hostile ~= nil) then
                slot:SetAlphaFromBoolean(hostile, 1, 0)
            else
                slot:SetAlpha(UI.Flag(hostile) and 1 or 0)
            end
        else
            slot:SetAlpha(1)
        end
    end
end

-- Reminders show while their aura isn't up, out of combat; in combat SuuUI
-- can't read auras, so they hide. A change of what shows relays the row.
-- Debuff reminders need a hostile target.
function TR:UpdateReminders(noLayout)
    local changed = false
    local fight = self.inFight or InCombatLockdown()
    local hostile = UnitExists("target") and UI.Flag(UnitCanAttack("player", "target"))
    local ctx = { combat = fight and true or false }
    local function update(list, needTarget)
        for _, r in ipairs(list) do
            local show = not fight and r.condOK ~= false and (not needTarget or hostile) and not auraUp(r, ctx)
            if show ~= r:IsShown() then r:SetShown(show); changed = true end
        end
    end
    update(self.built.remindBuffs, false)
    update(self.built.remindDebuffs, true)
    if changed and not noLayout then self:Layout() end
end

function TR:UpdateCooldowns(noLayout)
    local changed = false
    for _, cell in ipairs(self.cells or {}) do
        cell:Update(self.opts or {})
        if cell.wantShown ~= cell:IsShown() then
            cell:SetShown(cell.wantShown)
            changed = true
        end
    end
    if changed and not noLayout then self:Layout() end
    return changed
end

-- Live conditions (stance or form, combat, the target), in combat too.
-- SuuUI's own cells, slots and reminders show or hide and the rows close
-- up. A packed entry (and a slot's live member, and an effect) is an engine
-- group: its max goes to 0 and back. If the engine refuses that call (in
-- combat), it's tried again when combat ends: `applied` is what took.
function TR:UpdateLive(noLayout)
    if #self.liveFrames == 0 and #self.liveGroups == 0 then return end
    local ctx = { combat = (self.inFight or InCombatLockdown()) and true or false }
    local changed = false
    for _, f in ipairs(self.liveFrames) do
        local ok = allMet(f.whens, ctx)
        if ok ~= f.condOK then f.condOK = ok; changed = true end
    end
    for _, g in ipairs(self.liveGroups) do
        local n = allMet(g.whens, ctx) and g.max or 0
        if n ~= g.applied then
            local c = g.ac.container
            if pcall(c.SetAuraGroupMaxFrameCount, c, g.key, n) then
                g.applied = n
                g.ac:Refresh()
            end
        end
    end
    -- fixed slots show or hide here; cells and reminders by their updates
    for _, key in ipairs({ "buffs", "debuffs" }) do
        for _, slot in ipairs(self.built[key]) do
            if slot.condOK ~= nil then slot:SetShown(slot.condOK) end
        end
    end
    if changed and not noLayout then
        self:UpdateReminders(true)
        self:UpdateCooldowns(true)
        self:Layout()
    end
end

-- Which ranks of the listed cooldowns, buffs and debuffs you know, as one
-- string (a group's per member: in a cooldown list the member shown can
-- change; collections' entries too).
function TR:KnownSignature()
    local parts = {}
    local function walk(entry)
        if entry.collection then
            for _, e in ipairs(entry.entries or {}) do walk(e) end
        elseif entry.group then
            for _, m in ipairs(entry.members or {}) do
                parts[#parts + 1] = tostring(m.ids and knownRank(m) or 0)
            end
        elseif entry.ids then
            parts[#parts + 1] = tostring(knownRank(entry) or 0)
        end
    end
    for _, key in ipairs({ "essential", "utility", "buffs", "debuffs" }) do
        for _, entry in ipairs((self.lists or {})[key] or {}) do walk(entry) end
    end
    return table.concat(parts, ",")
end

-- What the static conditions in every list say now (met, unmet or live:
-- staticState), as one string (collections, entries, groups' members, in
-- list order). A change rebuilds.
function TR:ConditionSignature()
    local parts, ctx = {}, {}
    local function mark(when)
        if when then parts[#parts + 1] = staticState(when, ctx):sub(1, 1) end
    end
    local function walk(entry)
        mark(entry.when)
        for _, m in ipairs(entry.members or {}) do mark(m.when) end
        if entry.collection then
            for _, e in ipairs(entry.entries or {}) do walk(e) end
        end
    end
    for _, key in ipairs({ "essential", "utility", "buffs", "debuffs", "procs" }) do
        for _, entry in ipairs((self.lists or {})[key] or {}) do walk(entry) end
    end
    return table.concat(parts)
end

function TR:SetLists(lists)
    self.lists = lists
    self.rebuild = true
end

function TR:SetOptions(opts)
    self.opts = opts
    self.rebuild = true
end

-- Running: the driver and the game's events. Start rebuilds from the lists
-- (if it has any); Stop takes the aura sounds back and hands back everything
-- built, so a stopped tracker costs nothing. Out of combat.
function TR:Start()
    if self.running then return end
    self.running = true
    self.dirty = true
    if self.lists then self.rebuild = true end
    self.driver:Show()
    local t = self
    local function mark() t.dirty = true end
    -- Only events this client has (Forever renamed or dropped some).
    local valid = C_EventUtils and C_EventUtils.IsEventValid
    for _, e in ipairs({ "SPELL_UPDATE_COOLDOWN", "SPELL_UPDATE_USABLE", "SPELL_UPDATE_CHARGES",
                         "ACTIONBAR_UPDATE_USABLE", "UPDATE_SHAPESHIFT_FORM", "PLAYER_ENTERING_WORLD" }) do
        if not valid or valid(e) then Events.OnGame(e, mark, t) end
    end
    Events.OnUnit("UNIT_POWER_FREQUENT", "player", mark, t)
    Events.OnGame("PLAYER_TARGET_CHANGED", function() t:UpdateLive(); t:UpdateMissing(); t:UpdateReminders(); mark() end, t)
    Events.OnUnit("UNIT_AURA", { "player", "target" }, function()
        if not (t.inFight or InCombatLockdown()) then t:UpdateReminders() end
    end, t)
    Events.OnGame("PLAYER_REGEN_DISABLED", function() t.inFight = true; t:UpdateLive(); t:UpdateReminders() end, t)
    Events.OnGame("PLAYER_REGEN_ENABLED", function()
        t.inFight = false
        -- live conditions, and engine maxes refused in combat
        t:UpdateLive()
        C_Timer.After(0, function() t:UpdateReminders() end)
    end, t)
    -- live conditions: stance or form (combat and target above)
    for _, e in ipairs({ "UPDATE_SHAPESHIFT_FORM", "UPDATE_SHAPESHIFT_FORMS" }) do
        if not valid or valid(e) then Events.OnGame(e, function() t:UpdateLive() end, t) end
    end
    -- Learning a rank rebuilds; the spellbook "changing" with a shapeshift
    -- (same ranks known) doesn't.
    for _, e in ipairs({ "SPELLS_CHANGED", "LEARNED_SPELL_IN_SKILL_LINE", "LEARNED_SPELL_IN_TAB" }) do
        if not valid or valid(e) then Events.OnGame(e, function()
            local sig = t:KnownSignature()
            if sig ~= t.knownSig then t.rebuild = true end
        end, t) end
    end
    -- Static conditions: a group, role, zone or talent change that changes
    -- what they say rebuilds (after combat, like any rebuild). These come in
    -- bursts: one look half a second after the first.
    local function static()
        if t.condPending then return end
        t.condPending = true
        C_Timer.After(0.5, function()
            t.condPending = false
            if t.running and t.condSig and t:ConditionSignature() ~= t.condSig then t.rebuild = true end
        end)
    end
    for _, e in ipairs({ "GROUP_ROSTER_UPDATE", "PLAYER_ENTERING_WORLD", "ZONE_CHANGED_NEW_AREA" }) do
        if not valid or valid(e) then Events.OnGame(e, static, t) end
    end
    Events.On("SUUUI_ROLE_CHANGED", static, t)
    -- talents learned or unlearned: read them again, then the same look
    for _, e in ipairs({ "TRAIT_CONFIG_UPDATED", "TRAIT_NODE_CHANGED", "PLAYER_TALENT_UPDATE",
                         "CHARACTER_POINTS_CHANGED", "SPELLS_CHANGED" }) do
        if not valid or valid(e) then Events.OnGame(e, function() forgetTalents(); static() end, t) end
    end
end

function TR:Stop()
    if not self.running then return end
    self.running = false
    self.driver:Hide()
    Events.OffAll(self)
    clearAuraSounds()
    self:Clear()
    self.knownSig, self.condSig = nil, nil
end

function UI.CooldownTracker(parent, opts)
    local t = CreateFrame("Frame", opts and opts.name, parent)
    Mixin(t, TR)
    t:SetSize(1, 1)
    t.divider = UI.Fill(t, "gilt-line", "ARTWORK")
    t.divider:Hide()
    t.auraDivider = UI.Fill(t, "gilt-line", "ARTWORK")
    t.auraDivider:Hide()
    -- the collections' hairlines, a layer per side (the debuff side's fades
    -- with its slots)
    for _, key in ipairs({ "sepLeft", "sepRight" }) do
        t[key] = CreateFrame("Frame", nil, t)
        t[key]:SetAllPoints()
        t[key].lines, t[key].used = {}, 0
    end
    t.spare, t.taken = {}, {}
    t:Clear()

    -- One light pass per frame at most: rebuilds wait for the end of combat.
    -- The driver is its own frame, so it runs while the tracker is hidden
    -- (shown only in combat, or faded out on mouseover).
    t.driver = CreateFrame("Frame")
    t.driver:Hide()
    t.driver:SetScript("OnUpdate", function()
        local self = t
        if self.rebuild and not InCombatLockdown() then
            self.rebuild = false
            ns.Fault.Call("Cooldown Manager", self.Build, self)
            self.dirty = false
            return
        end
        local again = self.dirty
        for _, cell in ipairs(self.cells or {}) do
            if cell.dirty then cell.dirty = false; again = true end
        end
        if again then
            self.dirty = false
            ns.Fault.Call("Cooldown Manager", self.UpdateCooldowns, self)
        end
    end)
    t:Start()
    return t
end
