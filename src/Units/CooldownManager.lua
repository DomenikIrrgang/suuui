-- Units/CooldownManager.lua
-- SuuUI's own Cooldown Manager (step 1.7b): what it tracks is a setup per
-- class and spec, kept in the profile, each starting from a preset of your
-- class (Data/Presets/<CLASS>.lua). The spec is the talent tree with the most
-- points; without points the character is Unspecced. One profile can serve
-- every character of a role.
-- A built-in module written against the public API only.
--
-- Placement (2560x1440 reference): centred, space-3 above your cast bar
-- (its bottom 322px above the bottom edge), rows growing upward: Utility,
-- Essential, then the timers.
--
-- Blizzard's own Cooldown Manager isn't used: its CVar is switched off while
-- this module runs, so the two never show together.

local UI, T = SuuUI.UI, SuuUI.Tokens

local M = SuuUI.RegisterModule({
    id = "cooldowns",
    name = "Cooldown Manager",
    description = "Your cooldowns, buffs, procs and your debuffs on the target, set up per class and spec.",
    api = "0.8",
    combatSafe = true,
    defaults = {
        position = { point = "BOTTOM", x = 0, y = 322 },
        -- setups[CLASS][spec] = { preset, lists }: spec is the talent tree
        -- with the most points ("1"-"3"), "0" with none (Unspecced). One
        -- profile can hold every class and spec.
        setups = {},
        preset = "", lists = {}, -- before setups (migrated once)
        shows = "always",
        essentialSize = 40,
        utilityInline = false,
        readyPop = true,
        procHighlight = true,
        -- recent[CLASS] = { cooldown = { { name, ids } … }, aura = { … } }:
        -- what "+ Add" offers first ("Seen recently"), newest first
        recent = {},
        -- this module switched Blizzard's Cooldown Manager off (its CVar), so
        -- turning the module off switches it back on
        viewerOff = false,
    },
})

-- Essential size became 30-52px (the design's 40 by default): a size you set
-- stays, moved into the range if it was outside.
M:Migrate("essentialSize-30-52", function(values)
    local v = values.essentialSize
    if type(v) == "number" then values.essentialSize = math.max(30, math.min(52, v)) end
end)

-- Shared slots (groups) saved before every one had a uid get one, so the
-- editor can follow them through moves and renames.
M:Migrate("slot-uids", function(values)
    local function give(lists, tag)
        if type(lists) ~= "table" then return end
        for key, list in pairs(lists) do
            if type(list) == "table" then
                for i, e in ipairs(list) do
                    if type(e) == "table" and (e.group or e.collection) and not e.uid then e.uid = tag .. key .. i end
                end
            end
        end
    end
    if type(values.setups) == "table" then
        for class, specs in pairs(values.setups) do
            if type(specs) == "table" then
                for spec, s in pairs(specs) do
                    if type(s) == "table" then give(s.lists, "m" .. tostring(class) .. tostring(spec)) end
                end
            end
        end
    end
    give(values.lists, "m")
end)

-- "When missing" is each entry's own now: the list-wide Missing buffs and
-- Missing debuffs settings are gone. A choice made there goes onto every buff
-- or debuff that had none of its own (the defaults equal the old ones, so
-- untouched setups don't change).
M:Migrate("missing-per-entry", function(values)
    local old = { buffs = values.missingBuffs, debuffs = values.missingDebuffs }
    values.missingBuffs, values.missingDebuffs = nil, nil
    local function set(e, mode)
        if type(e) ~= "table" then return end
        if e.collection then
            for _, x in ipairs(e.entries or {}) do set(x, mode) end
        elseif e.missing == nil then
            e.missing = mode
        end
    end
    local function apply(lists)
        if type(lists) ~= "table" then return end
        for key, mode in pairs(old) do
            if type(mode) == "string" and type(lists[key]) == "table" then
                for _, e in ipairs(lists[key]) do set(e, mode) end
            end
        end
    end
    if type(values.setups) == "table" then
        for _, specs in pairs(values.setups) do
            if type(specs) == "table" then
                for _, s in pairs(specs) do
                    if type(s) == "table" then apply(s.lists) end
                end
            end
        end
    end
    apply(values.lists)
end)

local LIST_KEYS = { "essential", "utility", "buffs", "debuffs", "procs" }
local isSecret = issecretvalue or function() return false end
local _, CLASS = UnitClass("player")

local function presets()
    return SuuUI.CooldownPresets and SuuUI.CooldownPresets() or {}
end

local function findPreset(id)
    for _, p in ipairs(presets()) do if p.id == id then return p end end
end

-- A copy of a preset's lists, so editing them never touches the preset.
local function deepCopy(t)
    if type(t) ~= "table" then return t end
    local out = {}
    for k, v in pairs(t) do out[k] = deepCopy(v) end
    return out
end

-- Shared slots and collections get a uid the editor follows them by (fold
-- state, the Behaviour panel, matching the preset's in Changes): the same
-- one for every copy of a preset, the shared slots in a collection after it.
local function copyLists(p)
    local out = {}
    for _, key in ipairs(LIST_KEYS) do
        out[key] = {}
        for i, e in ipairs(p.lists[key] or {}) do
            local c = deepCopy(e)
            if c.group or c.collection then c.uid = c.uid or (p.id .. key .. i) end
            if c.collection then
                for j, x in ipairs(c.entries or {}) do
                    if x.group then x.uid = x.uid or (c.uid .. "." .. j) end
                end
            end
            out[key][#out[key] + 1] = c
        end
    end
    return out
end

--------------------------------------------------------------------------------
-- Spec: the talent tree with the most points (0: none spent)
--------------------------------------------------------------------------------

-- Points per tree, trees told apart by position (left to right, as Forever
-- lays out its three trees in one).
local function treePoints()
    local cfg = C_ClassTalents and C_ClassTalents.GetActiveConfigID and C_ClassTalents.GetActiveConfigID()
    local info = cfg and C_Traits and C_Traits.GetConfigInfo(cfg)
    if not (info and info.treeIDs) then return { 0, 0, 0 }, 0 end
    local nodes = {}
    for _, treeID in ipairs(info.treeIDs) do
        for _, nodeID in ipairs(C_Traits.GetTreeNodes(treeID) or {}) do
            local ni = C_Traits.GetNodeInfo(cfg, nodeID)
            if ni and ni.posX and ni.posX < 20000 then
                nodes[#nodes + 1] = { x = ni.posX, ranks = ni.ranksPurchased or ni.activeRank or ni.currentRank or 0 }
            end
        end
    end
    if #nodes == 0 then return { 0, 0, 0 }, 0 end
    local lo, hi = math.huge, -math.huge
    for _, n in ipairs(nodes) do lo, hi = math.min(lo, n.x), math.max(hi, n.x) end
    local third = (hi - lo) / 3
    local pts, total = { 0, 0, 0 }, 0
    for _, n in ipairs(nodes) do
        local r = isSecret(n.ranks) and 0 or (n.ranks or 0)
        local tree = (n.x < lo + third and 1) or (n.x < lo + 2 * third and 2) or 3
        pts[tree] = pts[tree] + r
        total = total + r
    end
    return pts, total
end

function M:DetectSpec()
    local ok, pts, total = pcall(treePoints)
    if not ok then return 0, { 0, 0, 0 } end
    if total == 0 then return 0, pts end
    local best = 1
    for t = 2, 3 do if pts[t] > pts[best] then best = t end end
    return best, pts
end

-- A spec's starting preset (the first of its tree) and its name.
local function specPreset(spec)
    for _, p in ipairs(presets()) do if (p.tree or 0) == spec then return p end end
end

local function specName(spec)
    if spec == 0 then return "Unspecced" end
    local p = specPreset(spec)
    return p and (p.name:gsub("%s*%b()", "")) or ("Tree " .. spec)
end

--------------------------------------------------------------------------------
-- Setups: this class's lists per spec, in the profile
--------------------------------------------------------------------------------

function M:EditSpec() return self.editSpec or self.spec or 0 end

local function setupKey(spec) return tostring(spec or 0) end

function M:SaveSetup(spec, setup)
    local all = deepCopy(self:Get("setups"))
    all[CLASS] = all[CLASS] or {}
    all[CLASS][setupKey(spec)] = setup
    self:Set("setups", all)
end

-- The setup for a spec; a spec seen the first time starts from its preset.
function M:Setup(spec)
    local all = self:Get("setups")
    local s = all[CLASS] and all[CLASS][setupKey(spec)]
    if s then return s end
    local p = specPreset(spec) or presets()[1]
    s = { preset = p and p.id or "", lists = p and copyLists(p) or {} }
    self:SaveSetup(spec, s)
    return s
end

function M:Lists(spec) return self:Setup(spec).lists end
function M:PresetId(spec) return self:Setup(spec).preset end

function M:SetLists(lists, spec)
    local s = deepCopy(self:Setup(spec))
    s.lists = lists
    self:SaveSetup(spec, s)
end

function M:LoadPreset(id, spec)
    local p = findPreset(id)
    if not p then return false end
    self:SaveSetup(spec, { preset = id, lists = copyLists(p) })
    return true
end

-- The lists from before setups: kept for this class's active spec, dropped
-- when they were another class's (a profile shared across classes).
function M:MigrateLists()
    local old, oldPreset = self:Get("lists"), self:Get("preset")
    if next(old) ~= nil then
        local all = self:Get("setups")
        local key = setupKey(self.spec)
        if findPreset(oldPreset) and not (all[CLASS] and all[CLASS][key]) then
            self:SaveSetup(self.spec, { preset = oldPreset, lists = deepCopy(old) })
        end
        self:Set("lists", {})
        self:Set("preset", "")
    end
end

function M:UpdateSpec()
    local spec, pts = self:DetectSpec()
    self.points = pts
    if spec ~= self.spec then
        self.spec = spec
        self.editSpec = nil -- the settings follow the new active spec
        if self.tracker and self:IsEnabled() then self:Apply() end
        self:Emit("SUUUI_COOLDOWNS_SETUP")
    end
end

function M:Apply()
    local t = self.tracker
    t:SetOptions({
        essentialSize = self:Get("essentialSize"),
        utilityInline = self:Get("utilityInline"),
        readyPop = self:Get("readyPop"),
        procHighlight = self:Get("procHighlight"),
    })
    t:SetLists(self:Lists(self.spec))
    self:ApplyVisibility()
end

-- Where and when it shows: nothing to rebuild.
function M:ApplyVisibility()
    local pos = self:Get("position")
    UI.SetVisibility(self.tracker, pos.hidden and "hidden" or self:Get("shows"))
end

--------------------------------------------------------------------------------
-- Settings
--------------------------------------------------------------------------------

-- The setup and preset bar: which spec's setup you edit (the active one by
-- default), your class's presets, Load, and what the lists are based on.
local function buildPresetBar(parent)
    local f = CreateFrame("Frame", nil, parent)
    f:SetSize(520, 112)
    local choice

    f.setup = UI.Select(f, { width = 200, onChange = function(v)
        M.editSpec = v
        M:Emit("SUUUI_COOLDOWNS_SETUP")
    end })
    f.setup:SetPoint("TOPLEFT")
    f.active = UI.Text(f, "caption", "ink-muted")
    f.active:SetPoint("LEFT", f.setup, "RIGHT", 10, 0)

    local options = {}
    for _, p in ipairs(presets()) do options[#options + 1] = { value = p.id, label = p.name } end
    f.select = UI.Select(f, { width = 200, options = options, onChange = function(v) choice = v end })
    f.select:SetPoint("TOPLEFT", f.setup, "BOTTOMLEFT", 0, -10)
    f.status = UI.Text(f, "caption", "ink-muted")
    f.status:SetPoint("TOPLEFT", f.select, "BOTTOMLEFT", 0, -6)

    local function refresh()
        local spec = M:EditSpec()
        -- the setups: Unspecced and the class's trees, the active one marked
        local specs, seen = {}, {}
        for _, p in ipairs(presets()) do
            local t = p.tree or 0
            if not seen[t] then
                seen[t] = true
                specs[#specs + 1] = { value = t, label = specName(t) .. (t == (M.spec or 0) and " (active)" or "") }
            end
        end
        table.sort(specs, function(a, b) return a.value < b.value end)
        f.setup:SetOptions(specs)
        f.setup:SetValue(spec)
        local pts = M.points or { 0, 0, 0 }
        f.active:SetValue(("This character: %s · talents %d / %d / %d"):format(specName(M.spec or 0), pts[1], pts[2], pts[3]))
        local p = findPreset(M:PresetId(spec))
        choice = choice or (p and p.id)
        f.select:SetValue(choice)
        local n = p and M:Changes() or 0
        f.status:SetValue(p and ("Based on " .. p.name .. (n > 0 and (" · " .. n .. (n == 1 and " change" or " changes")) or "")) or "No preset loaded")
    end

    f.load = UI.Button(f, { text = "Load", variant = "primary", onClick = function()
        if not choice then return end
        local spec = M:EditSpec()
        local p = findPreset(choice)
        local function load() M:LoadPreset(choice, spec); refresh() end
        -- loading over lists you've changed (or another preset's) asks first
        local changes = M:Changes()
        if choice ~= M:PresetId(spec) or changes > 0 then
            UI.Confirm({
                title = "Load " .. (p and p.name or "preset") .. "?",
                text = ("Your %s lists are replaced with %s's.%s"):format(specName(spec), p and p.name or "the preset",
                    changes > 0 and (" Your %d %s are lost."):format(changes, changes == 1 and "change" or "changes") or ""),
                confirm = "Replace", onConfirm = load })
        else
            load()
        end
    end })
    f.load:SetPoint("LEFT", f.select, "RIGHT", 8, 0)
    f.reset = UI.Button(f, { text = "Reset to preset", onClick = function()
        local spec = M:EditSpec()
        local id = M:PresetId(spec)
        local n = M:Changes()
        if id == "" or n == 0 then return end
        UI.Confirm({ title = "Reset to preset?", text = ("Your %d %s to the %s lists are undone."):format(n, n == 1 and "change" or "changes", specName(spec)),
            confirm = "Reset", onConfirm = function() M:LoadPreset(id, spec); refresh() end })
    end })
    f.reset:SetPoint("LEFT", f.load, "RIGHT", 8, 0)
    refresh()
    M:Watch("setups", refresh)
    M:On("SUUUI_COOLDOWNS_SETUP", function() choice = nil; refresh() end)
    return f
end


--------------------------------------------------------------------------------
-- The list editor (step 1.7b-2): every entry of every list, per spell
--------------------------------------------------------------------------------

local LIST_INFO = {
    essential = { label = "Essential", kind = "cooldown", note = "Your rotation and big cooldowns, the larger row." },
    utility = { label = "Utility", kind = "cooldown", note = "Interrupts, defensives, movement." },
    buffs = { label = "Buffs on you", kind = "aura", note = "From anyone, unless only yours." },
    debuffs = { label = "Your debuffs on the target", kind = "aura", note = "Only yours." },
    procs = { label = "Procs", kind = "aura", note = "Shown only while up." },
}
local TABS = { cooldowns = { "essential", "utility" }, auras = { "buffs", "debuffs", "procs" } }

local function copy(t)
    if type(t) ~= "table" then return t end
    local out = {}
    for k, v in pairs(t) do out[k] = copy(v) end
    return out
end

-- Change the lists through a copy, so the setting sees a new value.
local function mutate(fn)
    local spec = M:EditSpec()
    local lists = copy(M:Lists(spec))
    for _, key in ipairs(LIST_KEYS) do lists[key] = lists[key] or {} end
    fn(lists)
    M:SetLists(lists, spec)
end

--------------------------------------------------------------------------------
-- Entries: single spells, shared slots and collections
--------------------------------------------------------------------------------
-- A list holds single entries, shared slots ({ group = true, members }: one
-- icon; in an aura list whichever member is up, in a cooldown list the last
-- member you know) and, in aura lists only, collections ({ collection = true,
-- entries }: single entries and shared slots shown side by side, one level
-- deep). The editor names an entry by its path: { key, i } in the list, j
-- inside a collection, m a shared slot's member.

local function newUid() return tostring(time()) .. math.random(1000, 9999) end

-- The container a path points into (a list, a collection's entries or a
-- shared slot's members), the index in it, and the shared slot it's in.
local function locate(l, p)
    local t, i = l[p.key], p.i
    if t and p.j then t, i = t[p.i] and t[p.i].entries, p.j end
    if t and p.m then
        local slot = t[i]
        if not (slot and slot.group) then return nil end
        return slot.members, p.m, slot
    end
    return t, i
end

local function entryAt(l, p)
    local t, i = locate(l, p)
    return t and t[i]
end

local function samePath(a, b)
    return a.key == b.key and a.i == b.i and a.j == b.j and a.m == b.m
end

-- fn(entry, path) for every entry of a list: collections and what they
-- hold, shared slots and their members.
local function walk(list, key, fn)
    local function one(e, p)
        fn(e, p)
        if e.group then
            for m, x in ipairs(e.members or {}) do fn(x, { key = key, i = p.i, j = p.j, m = m }) end
        end
    end
    for i, e in ipairs(list or {}) do
        one(e, { key = key, i = i })
        if e.collection then
            for j, x in ipairs(e.entries or {}) do one(x, { key = key, i = i, j = j }) end
        end
    end
end

-- A shared slot's IDs: every member's, once, sorted; its icon stays one of
-- them (or a member's own icon). A fixed icon whose member left is no longer
-- fixed.
local function regroup(e)
    local seen, ids, art = {}, {}, {}
    for _, m in ipairs(e.members or {}) do
        for _, id in ipairs(m.ids or {}) do
            if not seen[id] then seen[id] = true; ids[#ids + 1] = id end
        end
        if m.icon then art[m.icon] = true end
    end
    table.sort(ids)
    e.ids = ids
    if e.icon and not (seen[e.icon] or art[e.icon]) then e.icon, e.fixedIcon = nil, nil end
    if not e.icon and e.members and e.members[1] then e.icon = e.members[1].ids[1] end
end

local SOURCE_LABEL = { mine = "only yours", others = "only others'", any = "anyone" }
-- Whose aura a list counts unless an entry says otherwise (the tracker's
-- defaults): buffs from anyone, your debuffs and procs only yours.
local LIST_SOURCE = { buffs = "any", debuffs = "mine", procs = "mine" }
local function entrySource(e, key)
    return e.source or (e.group and "mine") or (e.mine and "mine") or LIST_SOURCE[key] or "mine"
end

--------------------------------------------------------------------------------
-- Conditions: when an entry shows at all
--------------------------------------------------------------------------------
-- when = { match = "all" | "any", conditions = { cond, … } } on any entry (a
-- shared slot's member in aura lists only); no when, or no conditions:
-- always. Each cond is { type, ["not"] = true? } plus its type's values:
--   group     value = "solo" | "group" | "raid"
--   classes   classes = { "DRUID", … }, others = true?  (anyone in your
--             group, you included; others: anyone but you)
--   role      roles = { "TANK", "HEALER", "DAMAGER" }
--   stance    stances = { keys of your class's STANCES }
--   combat    (in combat; not: out of combat)
--   instance  kinds = { "none", "party", "raid", "pvp" }
--   target    kinds = { "boss", "elite", "player", "normal" }
--   talent    talents = { spellID, … }  (you have learned any of them)
-- The tracker checks them; the editor writes them and says them in words.

local CLASSES = {
    { value = "DRUID", label = "Druid" }, { value = "HUNTER", label = "Hunter" }, { value = "MAGE", label = "Mage" },
    { value = "PALADIN", label = "Paladin" }, { value = "PRIEST", label = "Priest" }, { value = "ROGUE", label = "Rogue" },
    { value = "SHAMAN", label = "Shaman" }, { value = "WARLOCK", label = "Warlock" }, { value = "WARRIOR", label = "Warrior" },
}
local ROLES = { { value = "TANK", label = "Tank" }, { value = "HEALER", label = "Healer" }, { value = "DAMAGER", label = "Damage" } }
-- Stances and forms per class: the chip, and the name in a sentence.
local STANCES = {
    WARRIOR = { { value = "battle", label = "Battle", name = "Battle Stance" }, { value = "defensive", label = "Defensive", name = "Defensive Stance" },
                { value = "berserker", label = "Berserker", name = "Berserker Stance" } },
    DRUID = { { value = "caster", label = "Caster", name = "caster form" }, { value = "bear", label = "Bear", name = "Bear Form" },
              { value = "cat", label = "Cat", name = "Cat Form" }, { value = "moonkin", label = "Moonkin", name = "Moonkin Form" },
              { value = "travel", label = "Travel", name = "Travel Form" }, { value = "aquatic", label = "Aquatic", name = "Aquatic Form" } },
    ROGUE = { { value = "stealth", label = "Stealth", name = "Stealth" } },
    PRIEST = { { value = "shadowform", label = "Shadowform", name = "Shadowform" } },
}
local INSTANCES = { { value = "none", label = "Open world", name = "the open world" }, { value = "party", label = "Dungeon", name = "a dungeon" },
                    { value = "raid", label = "Raid", name = "a raid" }, { value = "pvp", label = "Battleground", name = "a battleground" } }
local TARGETS = { { value = "boss", label = "Boss", name = "a boss" }, { value = "elite", label = "Elite", name = "an elite" },
                  { value = "player", label = "Player", name = "a player" }, { value = "normal", label = "Normal", name = "a normal enemy" } }
local CONDITION_TYPES = {
    { value = "group", label = "In a group or raid" }, { value = "classes", label = "Class in your group" },
    { value = "role", label = "Your role" }, { value = "stance", label = "Your stance / form" },
    { value = "combat", label = "In combat" }, { value = "instance", label = "Instance" }, { value = "target", label = "Target is" },
    { value = "talent", label = "Your talents" },
}

-- A new condition of a type, with a first choice made.
local function newCondition(kind)
    if kind == "group" then return { type = "group", value = "group" } end
    if kind == "classes" then return { type = "classes", classes = { CLASS } } end
    if kind == "role" then return { type = "role", roles = { "TANK" } } end
    if kind == "stance" then return { type = "stance", stances = { STANCES[CLASS] and STANCES[CLASS][1].value } } end
    if kind == "instance" then return { type = "instance", kinds = { "party" } } end
    if kind == "target" then return { type = "target", kinds = { "boss" } } end
    if kind == "talent" then return { type = "talent", talents = {} } end
    return { type = "combat" }
end

-- "a, b or c"
local function anyOf(words)
    if #words <= 1 then return words[1] end
    return table.concat(words, ", ", 1, #words - 1) .. " or " .. words[#words]
end

-- The words for a condition's choices: `field` names them in a sentence.
local function picked(values, options, field)
    local by, out = {}, {}
    for _, o in ipairs(options) do by[o.value] = o end
    for _, v in ipairs(values or {}) do
        local o = by[v]
        out[#out + 1] = o and o[field] or tostring(v):lower()
    end
    return out
end

-- A class's talents, learned or not, sorted by name: { id = spellID, name,
-- tree } each. Any class's from the generated list (SuuUI.ClassTalents);
-- without it, your own class's read live from every node of the active
-- config's trees (kept once read: the config may not be there yet right
-- after login).
local liveTalents
local function readLiveTalents()
    if liveTalents then return liveTalents end
    local out, seen = {}, {}
    pcall(function()
        local cfg = C_ClassTalents and C_ClassTalents.GetActiveConfigID and C_ClassTalents.GetActiveConfigID()
        local info = cfg and C_Traits and C_Traits.GetConfigInfo(cfg)
        for _, treeID in ipairs(info and info.treeIDs or {}) do
            for _, nodeID in ipairs(C_Traits.GetTreeNodes(treeID) or {}) do
                local ni = C_Traits.GetNodeInfo(cfg, nodeID)
                for _, entryID in ipairs(ni and ni.entryIDs or {}) do
                    local ei = C_Traits.GetEntryInfo(cfg, entryID)
                    local di = ei and ei.definitionID and C_Traits.GetDefinitionInfo(ei.definitionID)
                    local id = di and (di.spellID or di.overriddenSpellID)
                    local name = id and not isSecret(id) and C_Spell.GetSpellName(id)
                    if name and not isSecret(name) and not seen[id] then
                        seen[id] = true
                        out[#out + 1] = { id = id, name = name }
                    end
                end
            end
        end
    end)
    table.sort(out, function(x, y) return x.name < y.name end)
    if #out > 0 then liveTalents = out end
    return out
end

local function classTalents(class)
    local list = SuuUI.ClassTalents and SuuUI.ClassTalents(class)
    if type(list) == "table" and #list > 0 then
        local out = {}
        for _, t in ipairs(list) do
            if t.id then
                out[#out + 1] = { id = t.id, name = t.name or C_Spell.GetSpellName(t.id) or ("ID " .. t.id), tree = t.tree, spec = t.spec }
            end
        end
        table.sort(out, function(x, y) return x.name < y.name end)
        return out
    end
    if class == CLASS then return readLiveTalents() end
    return {}
end

local function talentName(id)
    local name = C_Spell.GetSpellName(id)
    return (name and not isSecret(name)) and name or ("ID " .. tostring(id))
end

local function stanceOptions()
    local all = {}
    for _, list in pairs(STANCES) do for _, o in ipairs(list) do all[#all + 1] = o end end
    return all
end
local ALL_STANCES = stanceOptions()

-- One condition as a phrase ("in a raid", "with a druid or warlock in your
-- group"), or nil while it has nothing chosen. `short`: the row summary's
-- words ("with a warlock", "Defensive").
local function conditionPhrase(c, inGroup, short)
    local no = c["not"]
    if c.type == "group" then
        if c.value == "solo" then return no and "in a group or raid" or (short and "solo" or "while solo") end
        return (no and "not " or "") .. "in a " .. (c.value == "raid" and "raid" or "group")
    elseif c.type == "classes" then
        local names = {}
        for _, v in ipairs(c.classes or {}) do names[#names + 1] = tostring(v):lower() end
        if #names == 0 then return nil end
        local who
        if c.others then
            -- not you: "another paladin", or "a druid or paladin besides you"
            if #names == 1 and c.classes[1] == CLASS then
                who = (no and "without another " or "with another ") .. names[1]
            else
                who = (no and "without a " or "with a ") .. anyOf(names) .. " besides you"
            end
        else
            who = (no and "without a " or "with a ") .. anyOf(names)
        end
        return short and who or (who .. (inGroup and " in it" or " in your group"))
    elseif c.type == "role" then
        local roles = picked(c.roles, ROLES, "label")
        if #roles == 0 then return nil end
        for i, r in ipairs(roles) do roles[i] = r:lower() end
        if short then return (no and "not " or "") .. anyOf(roles) end
        for i, r in ipairs(roles) do roles[i] = r == "damage" and r or ("a " .. r) end
        return (no and "unless you play " or "while you play ") .. anyOf(roles)
    elseif c.type == "stance" then
        local names = picked(c.stances, ALL_STANCES, short and "label" or "name")
        if #names == 0 then return nil end
        if short then return (no and "not " or "") .. anyOf(names) end
        return (no and "outside " or "in ") .. anyOf(names)
    elseif c.type == "combat" then
        return no and "out of combat" or "in combat"
    elseif c.type == "instance" then
        local names = picked(c.kinds, INSTANCES, "name")
        if #names == 0 then return nil end
        return (no and "outside " or "in ") .. anyOf(names)
    elseif c.type == "target" then
        local names = picked(c.kinds, TARGETS, "name")
        if #names == 0 then return nil end
        if short then return (no and "target not " or "target ") .. anyOf(names) end
        return (no and "unless your target is " or "while your target is ") .. anyOf(names)
    elseif c.type == "talent" then
        local names = {}
        for _, id in ipairs(c.talents or {}) do names[#names + 1] = talentName(id) end
        if #names == 0 then return nil end
        return (no and "without " or "with ") .. anyOf(names)
    end
end

local function phrases(when, short)
    local conds = when and when.conditions or {}
    local inGroup = false
    for _, c in ipairs(conds) do
        if c.type == "group" and not c["not"] and c.value ~= "solo" then inGroup = true end
    end
    local out = {}
    for _, c in ipairs(conds) do out[#out + 1] = conditionPhrase(c, inGroup, short) end
    return out
end

-- The conditions as one sentence: "Faerie Fire shows in a raid, with a druid
-- or warlock in it, out of combat." With none: "Always shows."
local function conditionSentence(subject, when)
    local list = phrases(when)
    if #list == 0 then return "Always shows." end
    local lead = subject and (subject .. " shows ") or "Shows "
    if when.match == "any" then
        return lead .. "when " .. (#list > 1 and ("any of these holds: " .. table.concat(list, "; ")) or list[1]) .. "."
    end
    return lead .. table.concat(list, ", ") .. "."
end

-- The conditions in a row's summary: "in a raid · with a warlock", or with
-- Any of these, "in a raid or with a warlock".
local function conditionWords(when)
    local list = phrases(when, true)
    if #list == 0 then return nil end
    if when.match == "any" then return anyOf(list) end
    return table.concat(list, " · ")
end

-- What the Behaviour panel sets on an entry (its Reset clears them all).
local BEHAVIOUR_KEYS = { "ready", "pop", "sound", "onCooldown", "show", "unusable", "border", "effect", "effectIDs", "effectName",
                         "missing", "size", "glow", "digits", "stacks", "expiring", "soundAppear", "soundStack", "soundDrop", "when", "fixedIcon" }
-- What else makes an entry differ from the preset's: shown or not, and a
-- shared slot's own settings and members (their whose and when included).
local ENTRY_KEYS = { "name", "hidden", "ids", "max", "icon", "members" }
-- A collection's own settings.
local COLLECTION_KEYS = { "name", "when", "hidden" }

local function same(a, b)
    if type(a) ~= "table" or type(b) ~= "table" then return a == b end
    for k, v in pairs(a) do if not same(v, b[k]) then return false end end
    for k in pairs(b) do if a[k] == nil then return false end end
    return true
end

-- Whether an entry differs from the preset's entry of the same name.
local function changed(e, base, key)
    if entrySource(e, key) ~= entrySource(base, key) then return true end
    for _, list in ipairs({ BEHAVIOUR_KEYS, ENTRY_KEYS }) do
        for _, k in ipairs(list) do
            if not same(e[k], base[k]) then return true end
        end
    end
    return false
end

-- How many entries differ from the preset the lists are based on: added,
-- removed, changed (shown, behaviour, a shared slot's settings), or moved
-- into or out of a collection. A collection counts once for itself (added,
-- removed, renamed or its condition); it matches the preset's by uid (a
-- preset's copy keeps the one copyLists gave it), else by name.
function M:Changes()
    local spec = self:EditSpec()
    local p = findPreset(self:PresetId(spec))
    if not p then return 0 end
    local lists, n = self:Lists(spec), 0
    for _, key in ipairs(LIST_KEYS) do
        local base, cols = {}, {}
        for i, e in ipairs(p.lists[key] or {}) do
            if e.collection then
                local uid = e.uid or (p.id .. key .. i)
                cols[#cols + 1] = { e = e, uid = uid }
                for _, x in ipairs(e.entries or {}) do base[x.name] = { e = x, parent = uid } end
            else
                base[e.name] = { e = e }
            end
        end
        local seen, used = {}, {}
        local function entry(e, parent)
            local b = base[e.name]
            seen[e.name] = true
            if not b or b.parent ~= parent or changed(e, b.e, key) then n = n + 1 end
        end
        for _, e in ipairs(lists[key] or {}) do
            if e.collection then
                local match
                for _, c in ipairs(cols) do
                    if not used[c] and c.uid == e.uid then match = c; break end
                end
                if not match then
                    for _, c in ipairs(cols) do
                        if not used[c] and c.e.name == e.name then match = c; break end
                    end
                end
                local differs = not match
                if match then
                    used[match] = true
                    for _, k in ipairs(COLLECTION_KEYS) do
                        if not same(e[k], match.e[k]) then differs = true end
                    end
                end
                if differs then n = n + 1 end
                for _, x in ipairs(e.entries or {}) do entry(x, match and match.uid or e.uid) end
            else
                entry(e, nil)
            end
        end
        for name in pairs(base) do if not seen[name] then n = n + 1 end end
        for _, c in ipairs(cols) do if not used[c] then n = n + 1 end end
    end
    return n
end

-- The rank of an entry you know, as the spellbook names it.
local function rankText(entry)
    for i = #entry.ids, 1, -1 do
        local id = entry.ids[i]
        if IsPlayerSpell and IsPlayerSpell(id) then
            local sub = C_Spell.GetSpellSubtext and C_Spell.GetSpellSubtext(id)
            return (sub and sub ~= "") and sub or "Known", id
        end
    end
    -- not learned: the preset's chosen art (what most of its ranks show),
    -- else Rank 1 (the highest IDs are often NPC versions)
    return "Not learned", entry.icon or entry.ids[1]
end

-- What "+ Add" offers: cooldowns from your spellbook (and every preset of
-- your class), auras from the presets and what is on you and your target now.
local function spellbookByName()
    local out = {}
    local lines = C_SpellBook and C_SpellBook.GetNumSpellBookSkillLines and C_SpellBook.GetNumSpellBookSkillLines() or 0
    for line = 1, lines do
        local li = C_SpellBook.GetSpellBookSkillLineInfo(line)
        if li and li.itemIndexOffset and li.numSpellBookItems then
            for i = li.itemIndexOffset + 1, li.itemIndexOffset + li.numSpellBookItems do
                local ok, it = pcall(C_SpellBook.GetSpellBookItemInfo, i, Enum.SpellBookSpellBank.Player)
                if ok and it and it.spellID and not it.isPassive and it.name then
                    out[it.name] = out[it.name] or {}
                    table.insert(out[it.name], it.spellID)
                end
            end
        end
    end
    return out
end

-- Returns spells by name (shared slots' members and what collections hold
-- included), and the presets' shared slots by name with the list each came
-- from.
-- Auras other classes' presets track ("+ Add" notes their class): name ->
-- "Priest", filled by candidates("aura"). And every candidate's chosen art
-- (the presets' and the catalog's icon: what most of its IDs show), which a
-- new entry takes along.
local auraClassNote = {}
local candidateIcon = {}

local function candidates(kind)
    local byName, groups = {}, {}
    local function add(name, ids)
        if not name then return end
        byName[name] = byName[name] or {}
        local seen = {}
        for _, id in ipairs(byName[name]) do seen[id] = true end
        for _, id in ipairs(ids or {}) do if not seen[id] then table.insert(byName[name], id); seen[id] = true end end
    end
    local keys = kind == "cooldown" and { "essential", "utility" } or { "buffs", "debuffs", "procs" }
    for _, p in ipairs(presets()) do
        for _, key in ipairs(keys) do
            walk(p.lists[key], key, function(e, path)
                if e.collection then return end
                if e.group then
                    groups[e.name] = groups[e.name] or { entry = e, key = key }
                else
                    add(e.name, e.ids)
                    if e.icon then candidateIcon[e.name] = candidateIcon[e.name] or e.icon end
                end
            end)
        end
    end
    -- every class's preset auras too (a paladin tracking Power Word: Shield)
    if kind ~= "cooldown" and SuuUI.AuraCatalog then
        for name, a in pairs(SuuUI.AuraCatalog()) do
            if not byName[name] then
                add(name, a.ids)
                auraClassNote[name] = a.classes
            end
            if a.icon then candidateIcon[name] = candidateIcon[name] or a.icon end
        end
    end
    if kind == "cooldown" then
        for name, ids in pairs(spellbookByName()) do
            local cd = GetSpellBaseCooldown and GetSpellBaseCooldown(ids[#ids])
            if byName[name] or (cd and not isSecret(cd) and cd > 0) then add(name, ids) end
        end
    elseif not InCombatLockdown() then
        for _, unit in ipairs({ "player", "target" }) do
            for _, filter in ipairs({ "HELPFUL", "HARMFUL" }) do
                for i = 1, 40 do
                    local ok, a = pcall(C_UnitAuras.GetAuraDataByIndex, unit, i, filter)
                    if not ok or isSecret(a) or not a or isSecret(a.spellId) then break end
                    add(a.name, { a.spellId })
                end
            end
        end
    end
    for _, ids in pairs(byName) do table.sort(ids) end
    return byName, groups
end

-- "Seen recently": spells you cast and auras on you and your target (out of
-- combat, when the game shows them), newest first, RECENT_MAX per kind and
-- class. A name already near the top isn't written again.
local RECENT_MAX = 12

local function remember(kind, name, id)
    if isSecret(name) or isSecret(id) or not name or not id then return end
    local all = M:Get("recent")
    local mine = all[CLASS] and all[CLASS][kind] or {}
    for i = 1, math.min(3, #mine) do
        if mine[i].name == name then return end
    end
    local list = { { name = name, ids = { id } } }
    for _, r in ipairs(mine) do
        if r.name == name then
            for _, other in ipairs(r.ids) do if other ~= id then table.insert(list[1].ids, other) end end
        elseif #list < RECENT_MAX then
            list[#list + 1] = r
        end
    end
    table.sort(list[1].ids)
    all = copy(all)
    all[CLASS] = all[CLASS] or {}
    all[CLASS][kind] = list
    M:Set("recent", all)
end

local function recent(kind)
    local all = M:Get("recent")
    return all[CLASS] and all[CLASS][kind] or {}
end

-- Out of combat: the auras on you (anyone's) and yours on the target. Only
-- names not yet in the list are added (newest first), in one write per scan.
local function rememberAuras()
    if InCombatLockdown() then return end
    local mine = recent("aura")
    local seen, fresh = {}, {}
    for _, r in ipairs(mine) do seen[r.name] = true end
    for _, scan in ipairs({ { "player", "HELPFUL" }, { "target", "HARMFUL|PLAYER" } }) do
        for i = 1, 40 do
            local ok, a = pcall(C_UnitAuras.GetAuraDataByIndex, scan[1], i, scan[2])
            if not ok or isSecret(a) or not a or isSecret(a.spellId) then break end
            local name = a.name
            if not isSecret(name) and name and not seen[name] then
                seen[name] = true
                fresh[#fresh + 1] = { name = name, ids = { a.spellId } }
            end
        end
    end
    if #fresh == 0 then return end
    for _, r in ipairs(mine) do
        if #fresh >= RECENT_MAX then break end
        fresh[#fresh + 1] = r
    end
    while #fresh > RECENT_MAX do table.remove(fresh) end
    local all = copy(M:Get("recent"))
    all[CLASS] = all[CLASS] or {}
    all[CLASS].aura = fresh
    M:Set("recent", all)
end

-- A spell you cast, if it's one of yours with a cooldown (or a preset's).
local function rememberCast(spellID)
    if isSecret(spellID) or not spellID or not (IsPlayerSpell and IsPlayerSpell(spellID)) then return end
    local cd = GetSpellBaseCooldown and GetSpellBaseCooldown(spellID)
    if cd and not isSecret(cd) and cd > 0 then
        remember("cooldown", C_Spell.GetSpellName(spellID), spellID)
    end
end

-- What a typed number finds: the spell with that ID, as "Name · ID 123".
-- Its value is "id:123"; adding it adds exactly that ID.
-- The art of a list of IDs for a dropdown: the rank you know, else the first.
local function idsArt(ids)
    if not ids or not ids[1] then return nil end
    for i = #ids, 1, -1 do
        if IsPlayerSpell and IsPlayerSpell(ids[i]) then return C_Spell.GetSpellTexture(ids[i]) end
    end
    return C_Spell.GetSpellTexture(ids[1])
end

local function spellLookup(query)
    local id = tonumber((query or ""):match("^%s*(%d+)%s*$"))
    local name = id and C_Spell.GetSpellName(id)
    if isSecret(name) or not name then return nil end
    return { { value = "id:" .. id, label = ("%s · ID %d"):format(name, id), icon = C_Spell.GetSpellTexture(id) } }
end

-- An option's value as an entry: a name (every ID it carries), "id:123", or
-- "group:Name" (a preset's shared slot, a copy with its own uid).
local function entryFor(value, byName, groups)
    local id = type(value) == "string" and tonumber(value:match("^id:(%d+)$"))
    if id then return { name = C_Spell.GetSpellName(id), ids = { id } } end
    local gname = type(value) == "string" and value:match("^group:(.+)$")
    if gname and groups and groups[gname] then
        local g = copy(groups[gname].entry)
        g.uid = newUid()
        return g
    end
    if byName and byName[value] then return { name = value, ids = byName[value], icon = candidateIcon[value] } end
end

-- A small square button with a drawn glyph: "up", "down" or "remove".
local function glyphButton(parent, kind, onClick)
    local b = CreateFrame("Button", nil, parent)
    b:SetSize(22, 22)
    local border = UI.Border(b, "gilt-line")
    border:SetShown(false)
    if kind == "remove" then
        local c = UI.Cross(b, 9, "ink-muted")
        c:SetPoint("CENTER")
    else
        local dy = kind == "up" and 1 or -1
        for _, sgn in ipairs({ -1, 1 }) do
            local t = b:CreateTexture(nil, "OVERLAY")
            t:SetColorTexture(UI.RGBA("ink-muted"))
            t:SetSize(6, 1.5)
            t:SetRotation(math.rad(45 * sgn * dy))
            t:SetPoint("CENTER", 2 * sgn, 0)
        end
    end
    b:SetScript("OnEnter", function() border:SetShown(true) end)
    b:SetScript("OnLeave", function() border:SetShown(false) end)
    b:SetScript("OnClick", onClick)
    return b
end

local ROW_H, GAP, WIDTH = 30, 4, 560
-- Nesting: each level steps in INDENT, and a rail runs down from the row it
-- belongs to, under that row's fold chevron (RAIL_X from its left edge).
local INDENT, RAIL_X = 34, 25
-- what "+ Shared slot" and "+ Collection" are named until you rename them
local NEW_SLOT, NEW_COLLECTION = "New shared slot", "New collection"

-- While an aura isn't up, each entry's own choice (there's no list-wide
-- one): buffs grey and debuffs "with a target" unless set.
local MISSING = {
    { value = "hide", label = "Hide" },
    { value = "grey", label = "Grey" },
    { value = "warn", label = "Warn" },
    { value = "remind", label = "Remind" },
}
local MISSING_DEBUFF = {
    { value = "hide", label = "Hide" },
    { value = "grey", label = "Grey" },
    { value = "target", label = "With a target" },
    { value = "warn", label = "Warn" },
    { value = "remind", label = "Remind" },
}
local MISSING_DEFAULT = { buffs = "grey", debuffs = "target", procs = "hide" }
local MISSING_LABEL = { hide = "hide", grey = "grey", target = "with a target", warn = "warn", remind = "remind" }

-- The grip at a row's left edge: two columns of three dots.
local function grip(parent)
    local g = CreateFrame("Frame", nil, parent)
    g:SetSize(10, 16)
    for col = 0, 1 do
        for row = 0, 2 do
            local d = g:CreateTexture(nil, "OVERLAY")
            d:SetColorTexture(UI.RGBA("ink-faint"))
            d:SetSize(2, 2)
            d:SetPoint("TOPLEFT", 2 + col * 4, -(2 + row * 5))
        end
    end
    return g
end

-- The fold chevron of a collection or shared slot: down while open, right
-- while folded.
local function foldButton(parent, onClick)
    local b = CreateFrame("Button", nil, parent)
    b:SetSize(18, 18)
    b.strokes = {}
    for n = 1, 2 do
        local t = b:CreateTexture(nil, "OVERLAY")
        t:SetColorTexture(1, 1, 1, 1)
        t:SetSize(6, 1.5)
        b.strokes[n] = t
    end
    function b:SetOpen(open)
        local a, c = self.strokes[1], self.strokes[2]
        a:ClearAllPoints()
        c:ClearAllPoints()
        a:SetRotation(math.rad(-45))
        c:SetRotation(math.rad(45))
        if open then
            a:SetPoint("CENTER", -2, 0)
            c:SetPoint("CENTER", 2, 0)
        else
            a:SetPoint("CENTER", 0, 2)
            c:SetPoint("CENTER", 0, -2)
        end
    end
    function b:SetColor(name)
        for _, t in ipairs(self.strokes) do t:SetVertexColor(UI.RGBA(name)) end
    end
    b:SetColor("ink-muted")
    b:SetOpen(false)
    b:SetScript("OnEnter", function(self) self:SetColor("gilt-text") end)
    b:SetScript("OnLeave", function(self) self:SetColor("ink-muted") end)
    b:SetScript("OnClick", onClick)
    return b
end

-- A shared slot's mark: two small stacked cards at its icon's corner.
local function slotMark(parent, level)
    local m = CreateFrame("Frame", nil, parent)
    m:SetFrameLevel(level)
    m:SetSize(11, 11)
    for n = 0, 1 do
        local card = CreateFrame("Frame", nil, m)
        card:SetFrameLevel(m:GetFrameLevel() + 1 + n)
        card:SetSize(8, 8)
        card:SetPoint("TOPLEFT", n * 3, -n * 3)
        UI.Fill(card, "surface-raised"):SetAllPoints()
        UI.Border(card, "gilt")
    end
    return m
end

-- A collection's glyph in place of an icon: a gilt folder outline.
local function folderGlyph(parent)
    local g = CreateFrame("Frame", nil, parent)
    g:SetSize(22, 22)
    local body = CreateFrame("Frame", nil, g)
    body:SetSize(17, 11)
    body:SetPoint("CENTER", 0, -2)
    UI.Border(body, "gilt")
    local tab = CreateFrame("Frame", nil, g)
    tab:SetSize(7, 3)
    tab:SetPoint("BOTTOMLEFT", body, "TOPLEFT", 0, -1)
    UI.Border(tab, "gilt")
    return g
end

-- A cooldown shared slot shows the last member you know (upgrades last).
local function knownMember(slot)
    local members = slot.members or {}
    for i = #members, 1, -1 do
        if rankText(members[i]) ~= "Not learned" then return members[i] end
    end
end

-- An entry's icon art: a single spell's rank you know, a shared slot's icon
-- (a cooldown slot's: the member it shows; an aura slot's, unless its icon
-- is fixed: the first member you know, else its icon).
local function artOf(e, cooldown)
    local id
    if e.group and cooldown then
        local m = knownMember(e) or (e.members or {})[1]
        if m then id = select(2, rankText(m)) end
    elseif e.group then
        if not e.fixedIcon then
            for _, m in ipairs(e.members or {}) do
                local rank, known = rankText(m)
                if rank ~= "Not learned" then id = known; break end
            end
        end
        id = id or e.icon or (e.ids or {})[1]
    elseif e.ids then
        id = select(2, rankText(e))
    end
    return id and C_Spell.GetSpellTexture(id)
end

--------------------------------------------------------------------------------
-- Moving entries: into and out of collections and shared slots
--------------------------------------------------------------------------------

-- An entry as a shared slot's member: its name and IDs, and in an aura list
-- whose it counts (only where it differs from the slot's) and its condition.
-- Its looks are the slot's.
local function asMember(e, key, fromSlot, slot, slotKey)
    local m = { name = e.name, ids = copy(e.ids) }
    if LIST_INFO[slotKey].kind == "aura" then
        local src = fromSlot and (e.source or entrySource(fromSlot, key)) or entrySource(e, key)
        if src ~= entrySource(slot, slotKey) then m.source = src end
        m.when = copy(e.when)
    end
    return m
end

-- A member leaving its shared slot, as a single entry that counts the same
-- auras (whose it was, written down where the list counts otherwise).
local function asSingle(m, slotKey, slot, key)
    local e = { name = m.name, ids = copy(m.ids) }
    if LIST_INFO[key].kind == "aura" then
        local src = m.source or entrySource(slot, slotKey)
        if src ~= LIST_SOURCE[key] then e.source = src end
        e.when = copy(m.when)
    end
    return e
end

-- Moves the entry at `from` to the position `to` (an index past the end
-- puts it last), turning it into a member or back as it enters or leaves a
-- shared slot.
local function moveEntry(l, from, to)
    local srcT, srcI, srcSlot = locate(l, from)
    local dstT, dstI, dstSlot = locate(l, to)
    if not (srcT and srcT[srcI] and dstT) then return end
    local e = table.remove(srcT, srcI)
    if srcT == dstT and dstI > srcI then dstI = dstI - 1 end
    if dstSlot and dstSlot ~= srcSlot then
        e = asMember(e, from.key, srcSlot, dstSlot, to.key)
    elseif srcSlot and not dstSlot then
        e = asSingle(e, from.key, srcSlot, to.key)
    end
    table.insert(dstT, math.min(dstI, #dstT + 1), e)
    if srcSlot then regroup(srcSlot) end
    if dstSlot and dstSlot ~= srcSlot then regroup(dstSlot) end
end

-- "Make 'A + B' a shared slot": the slot takes A's place with A and B as its
-- members, A's whose (aura lists, one at a time) and A's looks.
local function combine(l, ontoPath, fromPath, uid, names)
    local aT, aI = locate(l, ontoPath)
    local bT, bI, bSlot = locate(l, fromPath)
    local a, b = aT and aT[aI], bT and bT[bI]
    if not (a and b) or a == b or a.name ~= names[1] or b.name ~= names[2] then return end
    local key = ontoPath.key
    local slot = { group = true, uid = uid, name = a.name .. " + " .. b.name, members = {}, hidden = a.hidden }
    if LIST_INFO[key].kind == "aura" then slot.source, slot.max = entrySource(a, key), 1 end
    -- (an aura's conditions stay with it as a member; a cooldown slot's
    -- members have none, so A's become the slot's)
    local cooldown = LIST_INFO[key].kind == "cooldown"
    for _, k in ipairs(BEHAVIOUR_KEYS) do
        if k ~= "when" or cooldown then slot[k] = copy(a[k]) end
    end
    slot.members[1] = asMember(a, key, nil, slot, key)
    slot.members[2] = asMember(b, fromPath.key, bSlot, slot, key)
    table.remove(bT, bI)
    if bSlot then regroup(bSlot) end
    for n, x in ipairs(aT) do
        if x == a then aT[n] = slot; break end
    end
    regroup(slot)
end

-- Whether a dragged row may land on a target: a collection only between the
-- list's own rows, a shared slot anywhere but in another slot, a single
-- entry (or a member) anywhere, onto a single entry (a new shared slot) too.
local function accepts(from, to)
    local kind = from.kind
    local plain = kind == "entry" or kind == "member"
    if to.onto == "entry" then return plain and not samePath(from.path, to.path) end
    if to.onto == "slot" then
        local p = from.path
        return plain and not (p.m and samePath({ key = p.key, i = p.i, j = p.j }, to.path))
    end
    if to.onto == "collection" then return kind ~= "collection" end
    if to.path.m then return plain end
    if to.path.j then return kind ~= "collection" end
    return true
end

--------------------------------------------------------------------------------
-- Rows
--------------------------------------------------------------------------------

-- The rails of the rows a row sits under: { level, faint } each, a
-- collection's in gilt, a shared slot's fainter.
local function setRails(fr, rails, level)
    fr.rails = fr.rails or {}
    for n, rl in ipairs(rails) do
        local t = fr.rails[n]
        if not t then
            t = fr:CreateTexture(nil, "BACKGROUND", nil, 1)
            t:SetWidth(1)
            fr.rails[n] = t
        end
        t:SetColorTexture(UI.RGBA(rl.faint and "gilt-line" or "gilt"))
        t:ClearAllPoints()
        t:SetPoint("TOPLEFT", fr, "TOPLEFT", (rl.level - level) * INDENT + RAIL_X, 0)
        t:SetHeight(ROW_H + GAP)
        t:Show()
    end
    for n = #rails + 1, #fr.rails do fr.rails[n]:Hide() end
end

-- One row: grip, fold chevron (collections and shared slots), icon (a
-- shared slot's with its mark, a collection's folder), name and summary,
-- then (right to left) remove, Move to… (rows at the top of a list), Behaviour
-- and shown. The row drags by its grip.
local function buildEntryRow(parent)
    local r = CreateFrame("Frame", nil, parent)
    r:SetSize(WIDTH, ROW_H)
    -- lit while a dragged row would land on it
    r.dropFill = UI.Fill(r, "arcane-soft", "BACKGROUND")
    r.dropFill:SetAllPoints()
    r.dropFill:Hide()
    r.dropEdge = UI.Border(r, "arcane")
    r.dropEdge:SetShown(false)
    r.grip = grip(r)
    r.grip:SetPoint("LEFT")
    r.fold = foldButton(r, function() parent:ToggleFold(r) end)
    r.fold:SetPoint("LEFT", r.grip, "RIGHT", 6, 0)
    r.icon = UI.Icon(r, 22)
    r.icon:SetPoint("LEFT", r.fold, "RIGHT", 6, 0)
    r.mark = slotMark(r, r.icon:GetFrameLevel() + 2)
    r.mark:SetPoint("BOTTOMRIGHT", r.icon, "BOTTOMRIGHT", 4, -4)
    r.folder = folderGlyph(r)
    r.folder:SetPoint("CENTER", r.icon, "CENTER")
    r.name = UI.Text(r, "label", "ink")
    r.name:SetPoint("TOPLEFT", r.icon, "TOPRIGHT", 8, 1)
    r.name:SetFixedWidth(180)
    r.rank = UI.Text(r, "caption", "ink-muted")
    r.rank:SetFixedWidth(180)
    r.rank:SetPoint("BOTTOMLEFT", r.icon, "BOTTOMRIGHT", 8, -1)
    r.strip = {}
    r.remove = glyphButton(r, "remove", function() parent:RemoveAt(r.path) end)
    r.remove:SetPoint("RIGHT")
    r.move = UI.Select(r, { width = 104, placeholder = "Move to…", onChange = function(to)
        if not to then return end
        mutate(function(l)
            local e = table.remove(l[r.key], r.path.i)
            if e then table.insert(l[to], e) end
        end)
    end })
    r.behaviour = UI.Button(r, { text = "Behaviour", width = 96, onClick = function() parent:OpenBehaviour(r.path) end })
    r.shown = UI.Toggle(r, { onChange = function(v)
        mutate(function(l)
            local e = entryAt(l, r.path)
            if e then e.hidden = (not v) or nil end
        end)
    end })

    -- drag to reorder: the editor tracks the cursor and drops
    r:EnableMouse(true)
    r:RegisterForDrag("LeftButton")
    r:SetScript("OnEnter", function() for _, t in ipairs({ r.grip:GetRegions() }) do t:SetColorTexture(UI.RGBA("ink-muted")) end end)
    r:SetScript("OnLeave", function() for _, t in ipairs({ r.grip:GetRegions() }) do t:SetColorTexture(UI.RGBA("ink-faint")) end end)
    r:SetScript("OnDragStart", function() parent:StartDrag(r) end)
    r:SetScript("OnDragStop", function() parent:StopDrag() end)
    return r
end

-- c = { key, path, entry, kind = "entry" | "slot" | "collection" | "member",
--       level, open (folds), slot (a member's) }
local function fillEntryRow(r, c)
    local e, key, kind = c.entry, c.key, c.kind
    r.key, r.path, r.kind, r.entry = key, c.path, kind, e
    local cooldown = LIST_INFO[key].kind == "cooldown"
    local member = kind == "member"
    local parts, strip, dim = {}, {}, false
    local function add(s) if s then parts[#parts + 1] = s end end
    r.icon:SetShown(kind ~= "collection")
    r.folder:SetShown(kind == "collection")
    r.mark:SetShown(kind == "slot")
    r.fold:SetShown(kind == "slot" or kind == "collection")
    r.fold:SetOpen(c.open)

    -- the summary, in words
    if kind == "collection" then
        add("collection · " .. #(e.entries or {}))
        if not c.open then
            for _, x in ipairs(e.entries or {}) do strip[#strip + 1] = artOf(x, cooldown) or false end
        end
    elseif kind == "slot" then
        local n = #(e.members or {})
        add("1 slot")
        if cooldown then
            local known = knownMember(e)
            add(known and ("shows " .. known.name) or "none learned")
            add(n == 1 and "1 spell" or (n .. " spells"))
            dim = not known
        else
            add(n == 1 and "1 aura" or (n .. " auras"))
            add(SOURCE_LABEL[entrySource(e, key)])
        end
        if not c.open then
            for _, m in ipairs(e.members or {}) do strip[#strip + 1] = artOf(m, cooldown) or false end
        end
    else
        local rank = rankText(e)
        dim = rank == "Not learned"
        add(rank)
        if member and cooldown then
            if knownMember(c.slot) == e then add("shows now") end
        elseif member then
            add(SOURCE_LABEL[e.source or entrySource(c.slot, key)])
        elseif cooldown then
            if e.effect then add("shows " .. (e.effectName or "its effect")) end
        else
            -- whose, when it isn't the list's usual
            local src = entrySource(e, key)
            if src ~= LIST_SOURCE[key] then add(SOURCE_LABEL[src]) end
        end
    end
    -- its conditions, in words
    if not (member and cooldown) then add(conditionWords(e.when)) end
    -- what the Behaviour panel changed, at a glance
    if not cooldown and key ~= "procs" and (kind == "entry" or kind == "slot") then
        local m = e.missing and MISSING_LABEL[e.missing]
        if m then add("missing: " .. m) end
    end
    r.rank:SetValue(table.concat(parts, " · "))

    if kind == "collection" then
        -- its name in the list heads' style
        r.name:SetValue((e.name or "Collection"):upper())
        r.name:SetColor("gilt-text")
    else
        r.name:SetValue(e.name or "Shared slot")
        r.name:SetColor(dim and "ink-muted" or "ink")
        r.icon:SetArt(artOf(e, cooldown))
        r.icon:SetState(dim and "dim" or "rest")
    end

    -- right to left: remove, Move to… (top rows), Behaviour (not a cooldown
    -- slot's members: theirs is the slot's), shown (not members)
    local top = c.level == 0
    r.move:SetShown(top)
    r.behaviour:SetShown(not (member and cooldown))
    r.shown:SetShown(not member)
    local anchor, gap, used = r.remove, 6, r.remove:GetWidth()
    for _, ctl in ipairs({ r.move, r.behaviour, r.shown }) do
        if ctl:IsShown() then
            ctl:ClearAllPoints()
            ctl:SetPoint("RIGHT", anchor, "LEFT", -gap, 0)
            used = used + gap + ctl:GetWidth()
            anchor, gap = ctl, ctl == r.move and 8 or 10
        end
    end
    if top then
        local moves = {}
        for _, k in ipairs(cooldown and TABS.cooldowns or TABS.auras) do
            if k ~= key then moves[#moves + 1] = { value = k, label = LIST_INFO[k].label } end
        end
        r.move:SetOptions(moves)
        r.move:SetValue(nil)
    end
    if not member then r.shown:SetValue(not e.hidden) end

    -- folded: its members' icons after the summary, as many as fit
    for _, t in ipairs(r.strip) do t:Hide() end
    if #strip > 0 then
        local x0 = math.min(r.rank:GetUnboundedStringWidth(), 180) + 6
        local room = WIDTH - c.level * INDENT - used - 8 - 70 - x0
        local count = math.min(#strip, math.max(0, math.floor((room + 2) / 16)))
        for n = 1, count do
            local t = r.strip[n] or UI.Icon(r, 14)
            r.strip[n] = t
            t:ClearAllPoints()
            t:SetPoint("LEFT", r.rank, "LEFT", x0 + (n - 1) * 16, 0)
            t:SetArt(strip[n] or nil)
            t:Show()
        end
    end
    r:Show()
end

local function buildEditor(parent)
    local f = CreateFrame("Frame", nil, parent)
    f:SetSize(WIDTH, 100)
    f.tab = "cooldowns"
    f.tabs = UI.Segmented(f, { options = { { value = "cooldowns", label = "Cooldowns" }, { value = "auras", label = "Auras" } },
        onChange = function(v) f.tab = v; f:Refresh() end })
    f.tabs:SetPoint("TOPLEFT")
    f.tabs:SetValue("cooldowns")
    f.rows, f.heads, f.adds, f.addTos = {}, {}, {}, {}
    -- folded or open, per collection and shared slot (by uid), this session:
    -- collections start open, shared slots folded
    f.fold = {}

    local function head(i)
        local h = f.heads[i]
        if not h then
            h = CreateFrame("Frame", nil, f)
            h:SetSize(WIDTH, 34)
            h.title = UI.Text(h, "label", "gilt-text")
            h.title:SetPoint("TOPLEFT", 0, -4)
            h.note = UI.Text(h, "caption", "ink-muted")
            h.note:SetPoint("TOPLEFT", h.title, "BOTTOMLEFT", 0, -2)
            h.count = UI.Text(h, "caption", "ink-muted")
            h.count:SetPoint("TOPRIGHT", 0, -6)
            f.heads[i] = h
        end
        return h
    end

    -- The list's foot: "+ Add…" (a Select of candidates; a typed number finds
    -- any spell by its ID), "+ Shared slot" and (aura lists) "+ Collection".
    local function addRow(i)
        local a = f.adds[i]
        if not a then
            a = CreateFrame("Frame", nil, f)
            a:SetSize(WIDTH, 34)
            a.select = UI.Select(a, { width = 300, placeholder = "+ Add… (name or spell ID)", lookup = spellLookup,
                onChange = function(value)
                    local e = value and entryFor(value, a.byName, a.groups)
                    if e then mutate(function(l) table.insert(l[a.key], e) end) end
                end })
            a.select:SetPoint("LEFT")
            a.newSlot = UI.Button(a, { text = "+ Shared slot", onClick = function()
                local uid = newUid()
                f.fold[uid] = true -- open, so its "+ Add to" shows
                mutate(function(l)
                    local slot = { group = true, uid = uid, name = NEW_SLOT, members = {}, ids = {} }
                    if LIST_INFO[a.key].kind == "aura" then slot.source, slot.max = LIST_SOURCE[a.key], 1 end
                    table.insert(l[a.key], slot)
                end)
            end })
            a.newSlot:SetPoint("LEFT", a.select, "RIGHT", 8, 0)
            a.newCollection = UI.Button(a, { text = "+ Collection", onClick = function()
                mutate(function(l)
                    table.insert(l[a.key], { collection = true, uid = newUid(), name = NEW_COLLECTION, entries = {} })
                end)
            end })
            a.newCollection:SetPoint("LEFT", a.newSlot, "RIGHT", 8, 0)
            f.adds[i] = a
        end
        return a
    end

    -- "+ Add to <name>…" at the foot of an open collection or shared slot.
    local function addToRow(n)
        local a = f.addTos[n]
        if not a then
            a = CreateFrame("Frame", nil, f)
            a:SetSize(WIDTH, ROW_H)
            a.select = UI.Select(a, { width = 280, lookup = spellLookup, onChange = function(value)
                local e = value and entryFor(value, a.byName, a.groups)
                if not e then return end
                mutate(function(l)
                    local box = entryAt(l, a.path)
                    if box and box.collection then
                        box.entries = box.entries or {}
                        table.insert(box.entries, e)
                    elseif box and box.group then
                        box.members = box.members or {}
                        table.insert(box.members, { name = e.name, ids = e.ids })
                        regroup(box)
                    end
                end)
            end })
            a.select:SetPoint("LEFT")
            f.addTos[n] = a
        end
        return a
    end

    -- What an "+ Add" offers: what you cast or saw lately first, then
    -- everything by name, and (where shared slots may go) the presets'
    -- shared slots of this list. Nothing the list already has.
    local function addOptions(kind, key, byName, groups, present, slots)
        local top, taken = {}, {}
        for _, r in ipairs(recent(kind)) do
            if not present[r.name] and not taken[r.name] then
                taken[r.name] = true
                if not byName[r.name] then byName[r.name] = copy(r.ids) end
                top[#top + 1] = { value = r.name, label = r.name, icon = idsArt(r.ids) }
            end
        end
        local options = {}
        for name in pairs(byName) do
            if not present[name] and not taken[name] then
                options[#options + 1] = { value = name, label = name,
                    icon = candidateIcon[name] and C_Spell.GetSpellTexture(candidateIcon[name]) or idsArt(byName[name]),
                    note = kind ~= "cooldown" and auraClassNote[name] or nil }
            end
        end
        for name, g in pairs(slots and groups or {}) do
            if not present[name] and g.key == key then
                options[#options + 1] = { value = "group:" .. name, label = name .. " (Shared slot)",
                    icon = g.entry and (g.entry.icon and C_Spell.GetSpellTexture(g.entry.icon) or idsArt(g.entry.ids)) or nil }
            end
        end
        table.sort(options, function(x, z) return x.label < z.label end)
        if #top > 0 then
            table.insert(top, 1, { heading = "Seen recently" })
            top[#top + 1] = { heading = "All" }
            for _, o in ipairs(options) do top[#top + 1] = o end
            options = top
        end
        return options
    end

    -- Dragging: a ghost follows the cursor; an arcane line marks where the
    -- row lands, an arcane edge the row it joins.
    f.ghost = CreateFrame("Frame", nil, UIParent)
    f.ghost:SetFrameStrata("TOOLTIP")
    f.ghost:SetSize(240, ROW_H)
    UI.Fill(f.ghost, "surface-raised"):SetAllPoints()
    UI.Border(f.ghost, "arcane")
    f.ghost.icon = UI.Icon(f.ghost, 22)
    f.ghost.icon:SetPoint("LEFT", 4, 0)
    f.ghost.name = UI.Text(f.ghost, "label", "ink")
    f.ghost.name:SetPoint("LEFT", f.ghost.icon, "RIGHT", 8, 0)
    f.ghost:Hide()
    f.line = f:CreateTexture(nil, "OVERLAY")
    f.line:SetColorTexture(UI.RGBA("arcane"))
    f.line:SetHeight(2)
    f.line:Hide()

    -- Where a drop at the cursor lands, in the visible tab: { path, frame }
    -- to land at a position (the line goes over `frame`), or { onto, path,
    -- frame } to land on a row: a single entry (a new shared slot), a shared
    -- slot (joins it) or a collection (goes last in it). Rows that can take
    -- one are split in four: the top quarter is before, the middle onto,
    -- the bottom after.
    function f:DropTarget()
        local _, cy = GetCursorPosition()
        cy = cy / self:GetEffectiveScale()
        for _, key in ipairs(TABS[self.tab]) do
            local L = self.layout[key]
            local top, bottom = L and L.head:GetTop(), L and L.add:GetBottom()
            if top and bottom and cy <= top and cy >= bottom then
                local items = L.items
                local function at(n)
                    local it = items[n]
                    if it then return { path = it.before, frame = it.frame } end
                    return { path = L.endPath, frame = L.add }
                end
                for n, it in ipairs(items) do
                    local t, b = it.frame:GetTop(), it.frame:GetBottom() - GAP
                    if t and b and cy <= t and cy > b then
                        local h = t - b
                        if it.onto then
                            if cy > t - h / 4 then return at(n) end
                            if cy > b + h / 4 then return { onto = it.onto, path = it.path, frame = it.frame } end
                            return at(n + 1)
                        end
                        return cy > t - h / 2 and at(n) or at(n + 1)
                    end
                end
                if items[1] and items[1].frame:GetTop() and cy > items[1].frame:GetTop() then return at(1) end
                return at(#items + 1)
            end
        end
    end

    function f:ShowDrop(t)
        if self.lit then
            self.lit.dropFill:Hide()
            self.lit.dropEdge:SetShown(false)
            self.lit = nil
        end
        self.line:Hide()
        if not t then return end
        if t.onto then
            t.frame.dropFill:Show()
            t.frame.dropEdge:SetShown(true)
            self.lit = t.frame
        else
            self.line:ClearAllPoints()
            self.line:SetPoint("BOTTOMLEFT", t.frame, "TOPLEFT", 0, 1)
            self.line:SetPoint("BOTTOMRIGHT", t.frame, "TOPRIGHT", 0, 1)
            self.line:Show()
        end
    end

    function f:StartDrag(row)
        self.drag = { path = row.path, kind = row.kind }
        row:SetAlpha(0.4)
        self.dragRow = row
        self.ghost.icon:SetArt(row.icon:IsShown() and row.icon.art:GetTexture() or nil)
        self.ghost.name:SetValue(row.name:GetText() or "")
        self.ghost:Show()
        self:SetScript("OnUpdate", function()
            local x, y = GetCursorPosition()
            local s = UIParent:GetEffectiveScale()
            self.ghost:ClearAllPoints()
            self.ghost:SetPoint("LEFT", UIParent, "BOTTOMLEFT", x / s + 12, y / s)
            local t = self:DropTarget()
            -- a drop that isn't allowed doesn't light up
            if t and not accepts(self.drag, t) then t = nil end
            self.target = t
            self:ShowDrop(t)
        end)
    end

    function f:StopDrag()
        self:SetScript("OnUpdate", nil)
        self.ghost:Hide()
        self:ShowDrop(nil)
        if self.dragRow then self.dragRow:SetAlpha(1) end
        local from, to = self.drag, self.target
        self.drag, self.target, self.dragRow = nil, nil, nil
        if not (from and to) then return end
        if to.onto == "entry" then
            -- onto a single entry: offer a shared slot of the two
            local lists = M:Lists(M:EditSpec())
            local a, b = entryAt(lists, to.path), entryAt(lists, from.path)
            if not (a and b) then return end
            local names = { a.name, b.name }
            local cooldown = LIST_INFO[to.path.key].kind == "cooldown"
            UI.Confirm({
                title = "Make a shared slot?",
                text = ("Make \"%s + %s\" a shared slot? %s"):format(a.name, b.name, cooldown
                    and "One icon: the last of them you know shows there."
                    or "One icon: whichever is up shows there."),
                confirm = "Make shared slot",
                onConfirm = function()
                    local uid = newUid()
                    f.fold[uid] = true
                    mutate(function(l) combine(l, to.path, from.path, uid, names) end)
                end })
            return
        end
        local dest = to.path
        if to.onto == "slot" then
            dest = { key = dest.key, i = dest.i, j = dest.j, m = math.huge }
        elseif to.onto == "collection" then
            dest = { key = dest.key, i = dest.i, j = math.huge }
        end
        mutate(function(l) moveEntry(l, from.path, dest) end)
    end

    function f:RemoveAt(path)
        mutate(function(l)
            local t, i, slot = locate(l, path)
            if t and t[i] then
                table.remove(t, i)
                if slot then regroup(slot) end
            end
        end)
    end

    local function foldKey(e, p) return e.uid or (p.key .. p.i .. "." .. (p.j or "")) end

    function f:IsOpen(e, p)
        local v = self.fold[foldKey(e, p)]
        if v == nil then return e.collection and true or false end
        return v
    end

    function f:ToggleFold(r)
        self.fold[foldKey(r.entry, r.path)] = not self:IsOpen(r.entry, r.path)
        self:Refresh()
    end

    function f:Refresh()
        self.layout = {}
        for _, r in ipairs(self.rows) do r:Hide() end
        for _, h in ipairs(self.heads) do h:Hide() end
        for _, a in ipairs(self.adds) do a:Hide() end
        for _, a in ipairs(self.addTos) do a:Hide() end
        local lists = M:Lists(M:EditSpec())
        local y = -(30 + 12)
        local rowN, addN = 0, 0
        local found = {}
        for i, key in ipairs(TABS[self.tab]) do
            local info = LIST_INFO[key]
            local cooldown = info.kind == "cooldown"
            local list = lists[key] or {}
            if not found[info.kind] then found[info.kind] = { candidates(info.kind) } end
            local byName, groups = found[info.kind][1], found[info.kind][2]
            local present, spells, nested = {}, 0, false
            walk(list, key, function(e)
                if e.name then present[e.name] = true end
                if e.group or e.collection then nested = true else spells = spells + 1 end
            end)

            local h = head(i)
            h.title:SetValue(info.label)
            h.note:SetValue(info.note)
            local noun = cooldown and "spell" or "aura"
            if nested then
                h.count:SetValue(("%d %s · %d %s"):format(#list, #list == 1 and "entry" or "entries", spells, spells == 1 and noun or (noun .. "s")))
            else
                h.count:SetValue(#list == 1 and "1 spell" or (#list .. " spells"))
            end
            h:ClearAllPoints()
            h:SetPoint("TOPLEFT", 0, y)
            h:Show()
            local L = { items = {}, head = h }
            self.layout[key] = L
            y = y - 38

            local function place(fr, level, rails)
                fr:ClearAllPoints()
                fr:SetPoint("TOPLEFT", level * INDENT, y)
                fr:SetWidth(WIDTH - level * INDENT)
                setRails(fr, rails, level)
                fr:Show()
                y = y - (ROW_H + GAP)
            end
            -- c: what fillEntryRow takes, plus rails, the position before
            -- the row (where a drop over its top lands) and what may land on it
            local function row(c)
                rowN = rowN + 1
                local r = self.rows[rowN] or buildEntryRow(self)
                self.rows[rowN] = r
                c.key = key
                fillEntryRow(r, c)
                place(r, c.level, c.rails)
                L.items[#L.items + 1] = { frame = r, before = c.path, onto = c.onto, path = c.path }
            end
            local function addTo(box, path, level, rails, endPath)
                addN = addN + 1
                local a = addToRow(addN)
                a.path, a.byName, a.groups = path, byName, groups
                a.select.placeholder = "+ Add to " .. (box.name or "it") .. "…"
                a.select:SetOptions(addOptions(info.kind, key, byName, groups, present, box.collection))
                a.select:SetValue(nil)
                place(a, level, rails)
                L.items[#L.items + 1] = { frame = a, before = endPath }
            end
            -- a single entry, or a shared slot and (open) its members
            local function entryRows(e, p, level, rails)
                if not e.group then
                    row({ path = p, entry = e, kind = "entry", level = level, rails = rails, onto = "entry" })
                    return
                end
                local open = self:IsOpen(e, p)
                row({ path = p, entry = e, kind = "slot", level = level, rails = rails, open = open, onto = "slot" })
                if not open then return end
                local inner = { unpack(rails) }
                inner[#inner + 1] = { level = level, faint = true }
                local members = e.members or {}
                for m, x in ipairs(members) do
                    row({ path = { key = key, i = p.i, j = p.j, m = m }, entry = x, kind = "member", slot = e,
                          level = level + 1, rails = inner })
                end
                addTo(e, p, level + 1, inner, { key = key, i = p.i, j = p.j, m = #members + 1 })
            end

            for index, e in ipairs(list) do
                local p = { key = key, i = index }
                if e.collection then
                    local open = self:IsOpen(e, p)
                    row({ path = p, entry = e, kind = "collection", level = 0, rails = {}, open = open, onto = "collection" })
                    if open then
                        local rails = { { level = 0 } }
                        local entries = e.entries or {}
                        for j, x in ipairs(entries) do entryRows(x, { key = key, i = index, j = j }, 1, rails) end
                        addTo(e, p, 1, rails, { key = key, i = index, j = #entries + 1 })
                    end
                else
                    entryRows(e, p, 0, {})
                end
            end

            local a = addRow(i)
            a.key = key
            a.newCollection:SetShown(not cooldown) -- collections are for auras
            a.byName, a.groups = byName, groups
            a.select:SetOptions(addOptions(info.kind, key, byName, groups, present, true))
            a.select:SetValue(nil)
            a:ClearAllPoints()
            a:SetPoint("TOPLEFT", 0, y)
            a:Show()
            L.add = a
            L.endPath = { key = key, i = #list + 1 }
            y = y - 46
        end
        self:SetHeight(-y)
        if self.behaviour and self.behaviour:IsShown() then self:RefreshBehaviour() end
    end

    ---------------------------------------------------------------------------
    -- The Behaviour panel: per entry, a modal sized to what applies.
    --   cooldown: when ready, pop, sound, on cooldown, show, when unusable,
    --     edge, effect; a cooldown shared slot adds its name and shown
    --   single aura: whose, when missing, edge, size, glow, timer, stacks,
    --     amber, sounds
    --   shared slot (auras): name, how many at once, icon, then as a single aura
    --   a shared slot's member: whose only (how it looks is the slot's)
    --   collection: name
    -- and on every one of them, Conditions.
    ---------------------------------------------------------------------------

    local BP_W = 520
    local CW = BP_W - 40 -- the body's width
    local EDGES = { { value = "default", label = "By state" }, { value = "ink", label = "Ink" },
                    { value = "gilt", label = "Gilt" }, { value = "muted", label = "Muted" } }
    local SOUND_OPTIONS = { { value = "none", label = "None" }, { value = "chime", label = "Ready chime" },
                            { value = "ping", label = "Soft ping" }, { value = "proc", label = "Proc" },
                            { value = "warning", label = "Warning" } }
    local WHOSE = { { value = "mine", label = "Only yours" }, { value = "others", label = "Only others'" }, { value = "any", label = "Anyone's" } }

    -- The panel's entry in the lists, and the shared slot it's a member of:
    -- by uid (shared slots and collections have one; a member goes by its
    -- slot's), else at its path while that is still the same spell; nil
    -- once it's gone.
    local function findEntry(l)
        local b = f.behaviour
        local uid = b.slotUid or b.uid
        if uid then
            local at
            walk(l[b.key], b.key, function(e, p) if e.uid == uid and not p.m then at = p end end)
            if not at then return nil end
            b.path = b.slotUid and { key = at.key, i = at.i, j = at.j, m = b.path.m } or at
        end
        local t, i, slot = locate(l, b.path)
        local e = t and t[i]
        if e and (b.uid or e.name == b.entryName) then return e, slot end
    end

    local function mutateEntry(fn)
        mutate(function(l)
            local e, slot = findEntry(l)
            if e then
                fn(e, slot)
                if slot then regroup(slot) end
            end
        end)
    end

    ---------------------------------------------------------------------------
    -- Conditions: "Conditions" and All of these | Any of these, a row per
    -- condition (Not, its type, its control under them, ✕), "+ Add
    -- condition", then the sentence. Its height follows its rows.
    ---------------------------------------------------------------------------

    local COND_X = 56 -- a condition's control, under its type

    -- Changes the entry's conditions; with none left it has no `when`.
    local function mutateWhen(fn)
        mutateEntry(function(e)
            local w = copy(e.when) or {}
            w.match, w.conditions = w.match or "all", w.conditions or {}
            fn(w)
            e.when = #w.conditions > 0 and w or nil
        end)
    end

    local function setCondition(i, fn)
        mutateWhen(function(w)
            if w.conditions[i] then fn(w.conditions[i], w) end
        end)
    end

    -- The types the Select offers: stance / form only for a class with one
    -- (or a condition that already is one, from another class's setup).
    local function conditionTypes(current)
        local out = {}
        for _, t in ipairs(CONDITION_TYPES) do
            if t.value ~= "stance" or STANCES[CLASS] or current == "stance" then out[#out + 1] = t end
        end
        return out
    end

    local function buildConditionRow(parent)
        local r = CreateFrame("Frame", nil, parent)
        r:SetWidth(CW)
        UI.Fill(r, "surface-sunk"):SetAllPoints()
        UI.Border(r, "gilt-faint")
        -- Not turns the condition around (ember while on)
        r.notButton = CreateFrame("Button", nil, r)
        r.notButton:SetSize(40, 30)
        r.notButton:SetPoint("TOPLEFT", 8, -8)
        r.notEdge = UI.Border(r.notButton, "gilt-line")
        r.notText = UI.Text(r.notButton, "label", "ink-faint")
        r.notText:SetPoint("CENTER")
        r.notText:SetValue("Not")
        r.notButton:SetScript("OnClick", function()
            setCondition(r.index, function(c) c["not"] = (not c["not"]) or nil end)
        end)
        r.type = UI.Select(r, { width = 196, onChange = function(v)
            if not v then return end
            setCondition(r.index, function(c, w)
                if c.type == v then return end
                local new = newCondition(v)
                new["not"] = c["not"]
                w.conditions[r.index] = new
            end)
        end })
        r.type:SetPoint("LEFT", r.notButton, "RIGHT", 8, 0)
        r.remove = glyphButton(r, "remove", function()
            mutateWhen(function(w) table.remove(w.conditions, r.index) end)
        end)
        r.remove:SetPoint("TOPRIGHT", -8, -12)

        -- the type's controls, one set showing
        local top = -(8 + 30 + 6)
        local function chips(options, field)
            local c = UI.ToggleChips(r, { options = options, onChange = function(values)
                setCondition(r.index, function(cond) cond[field] = values end)
            end })
            c:SetPoint("TOPLEFT", COND_X, top)
            return c
        end
        r.group = UI.Segmented(r, { options = { { value = "solo", label = "Solo" }, { value = "group", label = "Group" }, { value = "raid", label = "Raid" } },
            onChange = function(v) setCondition(r.index, function(c) c.value = v end) end })
        r.group:SetPoint("TOPLEFT", COND_X, top)
        -- classes in two rows of chips, one list
        local function classes()
            local all = r.classesA:GetValue()
            for _, v in ipairs(r.classesB:GetValue()) do all[#all + 1] = v end
            setCondition(r.index, function(c) c.classes = all end)
        end
        r.classesA = UI.ToggleChips(r, { options = { unpack(CLASSES, 1, 5) }, onChange = classes })
        r.classesA:SetPoint("TOPLEFT", COND_X, top)
        r.classesB = UI.ToggleChips(r, { options = { unpack(CLASSES, 6, 9) }, onChange = classes })
        r.classesB:SetPoint("TOPLEFT", COND_X, top - 32)
        -- you counted or not
        r.classesOthers = UI.Segmented(r, { options = { { value = "me", label = "Counting you" }, { value = "others", label = "Others only" } },
            onChange = function(v) setCondition(r.index, function(c) c.others = (v == "others") or nil end) end })
        r.classesOthers:SetPoint("TOPLEFT", COND_X, top - 64)
        r.roles = chips(ROLES, "roles")
        r.stances = STANCES[CLASS] and chips(STANCES[CLASS], "stances")
        r.instance = chips(INSTANCES, "kinds")
        r.target = chips(TARGETS, "kinds")
        r.plain = UI.Text(r, "caption", "ink-faint")
        r.plain:SetPoint("TOPLEFT", COND_X, top - 6)
        -- talents: the chosen ones (icon, name, ✕), then a class (any: a
        -- profile may serve another character) and "+ Add talent…" of its
        -- talents (a typed number finds any spell by its ID)
        r.talentRows = {}
        r.talentClass = CLASS
        r.talentClassSelect = UI.Select(r, { width = 160, options = CLASSES, value = CLASS, onChange = function(v)
            if not v then return end
            r.talentClass = v
            r:TalentOptions()
        end })
        r.addTalent = UI.Select(r, { width = 300, placeholder = "+ Add talent…", lookup = spellLookup, onChange = function(v)
            local id = tonumber(v) or (type(v) == "string" and tonumber(v:match("^id:(%d+)$")))
            if not id then return end
            setCondition(r.index, function(c)
                c.talents = c.talents or {}
                for _, x in ipairs(c.talents) do if x == id then return end end
                c.talents[#c.talents + 1] = id
            end)
        end })
        -- the chosen class's talents, without those already chosen
        function r:TalentOptions()
            local have, options = {}, {}
            for _, id in ipairs(self.cond and self.cond.talents or {}) do have[id] = true end
            -- by tree, left to right, each under its spec's name (Data/Talents.lua;
            -- else the tree's number), then by name
            local list = {}
            for _, t in ipairs(classTalents(self.talentClass)) do
                if not have[t.id] then list[#list + 1] = t end
            end
            table.sort(list, function(x, y)
                local a, b = tonumber(x.tree) or 9, tonumber(y.tree) or 9
                if a ~= b then return a < b end
                return x.name < y.name
            end)
            local heading
            for _, t in ipairs(list) do
                local tree = t.spec or (t.tree and (type(t.tree) == "number" and ("Tree " .. t.tree) or tostring(t.tree))) or "Other"
                if tree ~= heading then
                    heading = tree
                    options[#options + 1] = { heading = tree }
                end
                options[#options + 1] = { value = t.id, label = t.name, icon = C_Spell.GetSpellTexture(t.id) }
            end
            self.addTalent:SetOptions(options)
            self.addTalent:SetValue(nil)
        end
        r.controls = { r.group, r.classesA, r.classesB, r.classesOthers, r.roles, r.instance, r.target, r.plain, r.stances,
                       r.talentClassSelect, r.addTalent }
        return r
    end

    -- A chosen talent in a talent condition: icon, name, ✕.
    local function talentRow(r, n)
        local t = r.talentRows[n]
        if t then return t end
        t = CreateFrame("Frame", nil, r)
        t:SetSize(300, 24)
        t.icon = UI.Icon(t, 20)
        t.icon:SetPoint("LEFT")
        t.name = UI.Text(t, "label", "ink")
        t.name:SetPoint("LEFT", t.icon, "RIGHT", 8, 0)
        t.name:SetFixedWidth(240)
        t.remove = glyphButton(t, "remove", function()
            setCondition(r.index, function(c)
                for i, x in ipairs(c.talents or {}) do
                    if x == t.id then table.remove(c.talents, i); break end
                end
            end)
        end)
        t.remove:SetPoint("RIGHT")
        r.talentRows[n] = t
        return t
    end

    local function fillConditionRow(r, c)
        r.notEdge:SetColor(c["not"] and "ember" or "gilt-line")
        r.notText:SetColor(c["not"] and "ember-text" or "ink-faint")
        r.type:SetOptions(conditionTypes(c.type))
        r.type:SetValue(c.type)
        r.cond = c
        for _, ctl in pairs(r.controls) do ctl:Hide() end
        for _, t in ipairs(r.talentRows) do t:Hide() end
        local h = 26
        if c.type == "group" then
            r.group:SetValue(c.value or "group")
            r.group:Show()
            h = 30
        elseif c.type == "classes" then
            r.classesA:SetValue(c.classes)
            r.classesB:SetValue(c.classes)
            r.classesOthers:SetValue(c.others and "others" or "me")
            r.classesA:Show()
            r.classesB:Show()
            r.classesOthers:Show()
            h = 64 + 30
        elseif c.type == "role" then
            r.roles:SetValue(c.roles)
            r.roles:Show()
        elseif c.type == "stance" and r.stances then
            r.stances:SetValue(c.stances)
            r.stances:Show()
        elseif c.type == "instance" then
            r.instance:SetValue(c.kinds)
            r.instance:Show()
        elseif c.type == "target" then
            r.target:SetValue(c.kinds)
            r.target:Show()
        elseif c.type == "talent" then
            local y = 8 + 30 + 6
            for n, id in ipairs(c.talents or {}) do
                local t = talentRow(r, n)
                t.id = id
                t.icon:SetArt(C_Spell.GetSpellTexture(id))
                t.name:SetValue(talentName(id))
                t:ClearAllPoints()
                t:SetPoint("TOPLEFT", COND_X, -y)
                t:Show()
                y = y + 28
            end
            r.talentClassSelect:ClearAllPoints()
            r.talentClassSelect:SetPoint("TOPLEFT", COND_X, -y)
            r.talentClassSelect:SetValue(r.talentClass)
            r.talentClassSelect:Show()
            r.addTalent:ClearAllPoints()
            r.addTalent:SetPoint("TOPLEFT", COND_X, -(y + 36))
            r:TalentOptions()
            r.addTalent:Show()
            h = y + 36 + 30 - (8 + 30 + 6)
        else
            r.plain:SetValue(c.type == "combat" and "No options: while you're in combat."
                or "Your class has no stances or forms.")
            r.plain:Show()
            h = 20
        end
        r.height = 8 + 30 + 6 + h + 8
        r:SetHeight(r.height)
    end

    local function buildConditions(b)
        local cs = CreateFrame("Frame", nil, b.inner)
        cs:SetWidth(CW)
        b.sections[#b.sections + 1] = cs
        local rule = UI.Hairline(cs, "gilt-faint")
        rule:SetPoint("TOPLEFT")
        rule:SetPoint("TOPRIGHT")
        local title = UI.Text(cs, "label", "gilt-text")
        title:SetPoint("TOPLEFT", 0, -18)
        title:SetValue("Conditions")
        b.match = UI.Segmented(cs, { options = { { value = "all", label = "All of these" }, { value = "any", label = "Any of these" } },
            onChange = function(v) mutateWhen(function(w) w.match = v end) end })
        b.match:SetPoint("TOPRIGHT", 0, -12)
        cs.rows = {}
        b.addCondition = UI.Button(cs, { text = "+ Add condition", onClick = function()
            -- the first type not used yet
            mutateWhen(function(w)
                local used, pick = {}, "combat"
                for _, c in ipairs(w.conditions) do used[c.type] = true end
                for _, t in ipairs(conditionTypes()) do
                    if not used[t.value] then pick = t.value; break end
                end
                table.insert(w.conditions, newCondition(pick))
            end)
        end })
        b.condSentence = UI.Text(cs, "body", "ink")
        b.condSentence:SetWordWrap(true)
        b.condSentence:SetJustifyH("LEFT")
        b.condSentence:SetFixedWidth(CW)
        b.condNote = UI.Text(cs, "caption", "ink-muted")
        b.cond = cs
    end

    -- subject: the entry's name in the sentence (nil: "Shows …");
    -- note: under it ("Applies to everything inside.")
    local function fillConditions(b, e, subject, note)
        local cs = b.cond
        local conds = e.when and e.when.conditions or {}
        b.match:SetValue(e.when and e.when.match or "all")
        local y = 12 + 30 + 10
        for _, r in ipairs(cs.rows) do r:Hide() end
        for i, c in ipairs(conds) do
            local r = cs.rows[i] or buildConditionRow(cs)
            cs.rows[i] = r
            r.index = i
            fillConditionRow(r, c)
            r:ClearAllPoints()
            r:SetPoint("TOPLEFT", 0, -y)
            r:Show()
            y = y + r.height + 6
        end
        b.addCondition:ClearAllPoints()
        b.addCondition:SetPoint("TOPLEFT", 0, -y)
        y = y + 30 + 10
        b.condSentence:SetValue(conditionSentence(subject, e.when))
        b.condSentence:ClearAllPoints()
        b.condSentence:SetPoint("TOPLEFT", 0, -y)
        y = y + math.max(16, b.condSentence:GetStringHeight()) + 6
        b.condNote:SetShown(note ~= nil)
        if note then
            b.condNote:SetValue(note)
            b.condNote:ClearAllPoints()
            b.condNote:SetPoint("TOPLEFT", 0, -y)
            y = y + 16 + 4
        end
        cs.height = y + 8
    end

    -- A label over a control, stacked down a section.
    local function stack(section)
        local y = 0
        return function(label, control, h)
            if label then
                local t = UI.Text(section, "caption", "ink-muted")
                t:SetPoint("TOPLEFT", 0, -y)
                t:SetValue(label)
                y = y + 18
            end
            control:SetPoint("TOPLEFT", 0, -y)
            y = y + (h or 30) + 12
            section.height = y
            return y
        end
    end

    local function section(b)
        local s = CreateFrame("Frame", nil, b.inner)
        s:SetWidth(CW)
        b.sections[#b.sections + 1] = s
        return s, stack(s)
    end

    local function buildBehaviour()
        local b = UI.Panel(SuuUI.Root, { title = "Behaviour", width = BP_W, height = 600, solid = true })
        UI.MakeModal(b)
        b.sections = {}
        -- everything scrolls once the panel would outgrow the screen (many
        -- conditions): the panel stops at most of the screen's height
        b.scroll = UI.ScrollArea(b.body, 6)
        b.scroll:SetAllPoints(b.body)
        b.inner = b.scroll.child
        b.inner:SetWidth(CW)

        -- a note on top: a member's slot, a cooldown slot's order
        -- (the box itself, then space-5 before the next section)
        b.note = section(b)
        b.note.height = 34 + T.space["space-5"]
        local box = CreateFrame("Frame", nil, b.note)
        box:SetPoint("TOPLEFT")
        box:SetPoint("TOPRIGHT")
        box:SetHeight(34)
        UI.Fill(box, "surface-sunk"):SetAllPoints()
        UI.Border(box, "gilt-faint")
        b.noteText = UI.Text(box, "caption", "ink-muted")
        b.noteText:SetPoint("LEFT", 8, 0)
        b.noteText:SetFixedWidth(CW - 16)
        b.noteText:SetJustifyH("LEFT")

        -- a shared slot's or collection's name, beside how many show at
        -- once (aura slots) or shown (cooldown slots)
        local nm = section(b)
        nm.height = 18 + 30 + 12
        local nameLabel = UI.Text(nm, "caption", "ink-muted")
        nameLabel:SetPoint("TOPLEFT")
        nameLabel:SetValue("Name")
        b.name = UI.TextField(nm, { width = 240, onChange = function(text)
            if text and text ~= "" then mutateEntry(function(e) e.name = text end) end
        end })
        b.name:SetPoint("TOPLEFT", 0, -18)
        b.sideLabel = UI.Text(nm, "caption", "ink-muted")
        b.sideLabel:SetPoint("TOPLEFT", 256, 0)
        b.max = UI.Stepper(nm, { min = 1, max = 4, step = 1, onChange = function(v) mutateEntry(function(e) e.max = v end) end })
        b.max:SetPoint("TOPLEFT", 256, -18)
        b.slotShown = UI.Toggle(nm, { onChange = function(v) mutateEntry(function(e) e.hidden = (not v) or nil end) end })
        b.slotShown:SetPoint("TOPLEFT", 256, -24)
        b.naming = nm

        -- an aura slot's icon while none of its auras is up
        local ic, addI = section(b)
        -- Automatic: what can show (the first member you know, else the
        -- icon); a member: always that one's
        b.icon = UI.Select(ic, { width = 240, placeholder = "First spell", onChange = function(v)
            if v == "auto" then
                mutateEntry(function(e) e.fixedIcon = nil end)
            elseif v then
                mutateEntry(function(e) e.icon, e.fixedIcon = v, true end)
            end
        end })
        addI("Icon when none is up", b.icon)
        b.iconSection = ic

        -- a member's whose (unless set, the slot's)
        local ms, addM = section(b)
        b.memberSource = UI.Segmented(ms, { options = WHOSE, onChange = function(v)
            mutateEntry(function(e, slot) e.source = v ~= entrySource(slot, f.behaviour.key) and v or nil end)
        end })
        addM("Whose", b.memberSource)
        b.memberSection = ms

        -- cooldowns
        local cd, add = section(b)
        b.ready = UI.Segmented(cd, { options = { { value = "normal", label = "Normal" }, { value = "glow", label = "Glow" }, { value = "pulse", label = "Pulse" } },
            onChange = function(v) mutateEntry(function(e) e.ready = v ~= "normal" and v or nil end) end })
        add("When ready", b.ready)
        b.pop = UI.Segmented(cd, { options = { { value = "default", label = "Like Display" }, { value = "on", label = "On" }, { value = "off", label = "Off" } },
            onChange = function(v) mutateEntry(function(e) if v == "default" then e.pop = nil else e.pop = (v == "on") end end) end })
        add("Pop when it comes ready", b.pop)
        b.sound = UI.Select(cd, { width = 220, options = SOUND_OPTIONS, onChange = function(v)
            mutateEntry(function(e) e.sound = v ~= "none" and v or nil end)
            if v ~= "none" then UI.TrackerSound(v) end
        end })
        add("Sound when ready", b.sound)
        b.onCooldown = UI.Segmented(cd, { options = { { value = "grey", label = "Grey" }, { value = "dim", label = "Dim" }, { value = "hide", label = "Hide" } },
            onChange = function(v) mutateEntry(function(e) e.onCooldown = v ~= "grey" and v or nil end) end })
        add("On cooldown", b.onCooldown)
        b.show = UI.Segmented(cd, { options = { { value = "always", label = "Always" }, { value = "ready", label = "Only when ready" }, { value = "cooldown", label = "Only on cooldown" } },
            onChange = function(v) mutateEntry(function(e) e.show = v ~= "always" and v or nil end) end })
        add("Show", b.show)
        b.unusable = UI.Segmented(cd, { options = { { value = "dim", label = "Dim" }, { value = "hide", label = "Hide" } },
            onChange = function(v) mutateEntry(function(e) e.unusable = v ~= "dim" and v or nil end) end })
        add("When unusable (not enough rage, wrong form)", b.unusable)
        b.cdEdge = UI.Segmented(cd, { options = EDGES, onChange = function(v)
            mutateEntry(function(e) e.border = v ~= "default" and v or nil end) end })
        add("Edge when ready", b.cdEdge)
        -- "Effect running": while the spell's buff (or your debuff on the
        -- target) is up, its aura covers the icon with its own time
        b.effect = UI.Segmented(cd, { options = { { value = "off", label = "Off" }, { value = "you", label = "Buff on you" }, { value = "target", label = "Debuff on target" } },
            onChange = function(v)
                mutateEntry(function(e) e.effect = v ~= "off" and v or nil end)
                b.effectAura:SetDisabled(v == "off")
            end })
        add("While its effect runs, show it over the icon", b.effect)
        b.effectAura = UI.Select(cd, { width = 300, lookup = spellLookup, onChange = function(v)
            if v == nil or v == "current" then return end
            mutateEntry(function(e)
                local id = tonumber(tostring(v):match("^id:(%d+)$"))
                if v == "self" then
                    e.effectIDs, e.effectName = nil, nil
                elseif id then
                    e.effectIDs, e.effectName = { id }, ("%s · ID %d"):format(C_Spell.GetSpellName(id) or "?", id)
                elseif b.auraByName and b.auraByName[v] then
                    e.effectIDs, e.effectName = copy(b.auraByName[v]), v
                end
            end)
        end })
        add("Effect (name or spell ID)", b.effectAura)
        b.cd = cd

        -- auras
        local au, addA = section(b)
        -- whose aura counts (a shared slot's own setting; its members may differ)
        b.source = UI.Segmented(au, { options = WHOSE,
            onChange = function(v)
                mutateEntry(function(e)
                    e.mine = nil
                    e.source = v ~= LIST_SOURCE[f.behaviour.key] and v or nil
                    if e.group then e.source = v end
                end)
            end })
        addA("Whose", b.source)
        -- (unset = the list's default: grey for buffs, with a target for debuffs)
        local function setMissing(v)
            mutateEntry(function(e) e.missing = v ~= MISSING_DEFAULT[f.behaviour.key] and v or nil end)
        end
        b.missing = UI.Segmented(au, { options = MISSING, onChange = setMissing })
        addA("When missing", b.missing)
        b.missingDebuff = UI.Segmented(au, { options = MISSING_DEBUFF, onChange = setMissing })
        b.missingDebuff:SetPoint(b.missing:GetPoint())
        b.auEdge = UI.Segmented(au, { options = EDGES, onChange = function(v)
            mutateEntry(function(e) e.border = v ~= "default" and v or nil end) end })
        addA("Edge", b.auEdge)
        b.size = UI.Segmented(au, { options = { { value = "small", label = "Small" }, { value = "normal", label = "Normal" }, { value = "large", label = "Large" } },
            onChange = function(v) mutateEntry(function(e) e.size = v ~= "normal" and v or nil end) end })
        addA("Size", b.size)
        -- three switches in one row
        local row = CreateFrame("Frame", nil, au)
        row:SetSize(CW, 30)
        local function switch(x, label, onChange)
            local t = UI.Toggle(row, { onChange = onChange })
            t:SetPoint("LEFT", x, 0)
            local l = UI.Text(row, "label", "ink")
            l:SetPoint("LEFT", t, "RIGHT", 8, 0)
            l:SetValue(label)
            return t
        end
        b.glow = switch(0, "Glow", function(v) mutateEntry(function(e) e.glow = v or nil end) end)
        b.digits = switch(120, "Timer", function(v) mutateEntry(function(e) e.digits = (not v) and false or nil end) end)
        b.stacks = switch(240, "Stacks", function(v) mutateEntry(function(e) e.stacks = (not v) and false or nil end) end)
        addA(nil, row)
        -- the amber threshold on one line, its label before it
        local amber = CreateFrame("Frame", nil, au)
        amber:SetSize(CW, 30)
        local amberLabel = UI.Text(amber, "caption", "ink-muted")
        amberLabel:SetPoint("LEFT")
        amberLabel:SetValue("Timer turns amber in the last")
        b.expiring = UI.Stepper(amber, { min = 1, max = 10, step = 1, unit = "s", onChange = function(v)
            mutateEntry(function(e) e.expiring = v ~= 3 and v or nil end) end })
        b.expiring:SetPoint("LEFT", amberLabel, "RIGHT", 12, 0)
        addA(nil, amber)
        -- sounds, three across: the engine plays them (registered on every
        -- tracker build)
        local sounds = CreateFrame("Frame", nil, au)
        sounds:SetSize(CW, 48)
        for n, s in ipairs({ { "soundAppear", "Sound when it appears" }, { "soundStack", "when it stacks up" }, { "soundDrop", "when it drops" } }) do
            local field = s[1]
            local t = UI.Text(sounds, "caption", "ink-muted")
            t:SetPoint("TOPLEFT", (n - 1) * 150, 0)
            t:SetValue(s[2])
            b[field] = UI.Select(sounds, { width = 140, options = SOUND_OPTIONS, onChange = function(v)
                mutateEntry(function(e) e[field] = v ~= "none" and v or nil end)
                if v ~= "none" then UI.TrackerSound(v) end
            end })
            b[field]:SetPoint("TOPLEFT", (n - 1) * 150, -18)
        end
        local h = addA(nil, sounds, 48)
        b.soundNote = UI.Text(au, "caption", "ink-muted")
        b.soundNote:SetWordWrap(true)
        b.soundNote:SetJustifyH("LEFT")
        b.soundNote:SetFixedWidth(CW)
        b.soundNote:SetPoint("TOPLEFT", 0, -(h - 6))
        b.soundNote:SetValue("The game plays these itself, in combat too, for this aura from anyone.")
        au.height = h + 22
        b.au = au

        buildConditions(b)

        b.reset = UI.Button(b.inner, { text = "Reset", width = 90, onClick = function()
            local ctx = f.behaviour.ctx
            mutateEntry(function(e)
                if ctx == "member" then
                    e.source, e.when = nil, nil
                elseif ctx == "collection" then
                    e.when = nil
                else
                    if ctx == "single" then e.source, e.mine = nil, nil end
                    for _, k in ipairs(BEHAVIOUR_KEYS) do e[k] = nil end
                end
            end)
        end })
        b.done = UI.Button(b.inner, { text = "Done", variant = "primary", width = 90, onClick = function() b:Hide() end })
        return b
    end

    function f:RefreshBehaviour()
        local b = self.behaviour
        local e, slot = findEntry(M:Lists(M:EditSpec()))
        if not e then b:Hide(); return end
        local cooldown = LIST_INFO[b.key].kind == "cooldown"
        local ctx = (e.collection and "collection") or (e.group and "slot") or (slot and "member") or "single"
        b.ctx = ctx
        local shown, meta
        if ctx == "collection" then
            local n = #(e.entries or {})
            shown, meta = { b.naming, b.cond }, ("Collection · %d %s"):format(n, n == 1 and "entry" or "entries")
        elseif ctx == "member" then
            shown, meta = { b.note, b.memberSection, b.cond }, "In " .. (slot.name or "a shared slot")
            b.noteText:SetValue("One slot: how it looks follows " .. (slot.name or "the shared slot") .. ".")
        elseif ctx == "slot" then
            local n = #(e.members or {})
            if cooldown then
                shown = { b.note, b.naming, b.cd, b.cond }
                b.noteText:SetValue("Shows the last spell in the list you know: put upgrades last.")
                meta = ("Shared slot · %d %s"):format(n, n == 1 and "spell" or "spells")
            else
                shown = { b.naming, b.iconSection, b.au, b.cond }
                meta = ("Shared slot · %d %s"):format(n, n == 1 and "aura" or "auras")
            end
        else
            shown = { cooldown and b.cd or b.au, b.cond }
            meta = cooldown and ("Cooldown · " .. LIST_INFO[b.key].label)
                or (b.path.j and "Single aura · in a collection" or "Single aura")
        end
        b:SetTitle(e.name or "Behaviour", meta)

        if ctx == "slot" or ctx == "collection" then
            b.name:SetValue(e.name or "")
            b.sideLabel:SetShown(ctx == "slot")
            b.sideLabel:SetValue(cooldown and "Shown" or "How many show at once")
            b.max:SetShown(ctx == "slot" and not cooldown)
            b.max:SetValue(e.max or 1)
            b.slotShown:SetShown(ctx == "slot" and cooldown)
            b.slotShown:SetValue(not e.hidden)
        end
        if ctx == "slot" and not cooldown then
            local iconOptions = { { value = "auto", label = "Automatic (what can show)" } }
            for _, m in ipairs(e.members or {}) do
                local art = m.icon or (m.ids and m.ids[1])
                if art then iconOptions[#iconOptions + 1] = { value = art, label = m.name, icon = C_Spell.GetSpellTexture(art) } end
            end
            b.icon:SetOptions(iconOptions)
            b.icon:SetValue(e.fixedIcon and e.icon or "auto")
        end
        if ctx == "member" then
            b.memberSource:SetValue(e.source or entrySource(slot, b.key))
        end
        if cooldown and ctx ~= "member" then
            b.ready:SetValue(e.ready or "normal")
            b.pop:SetValue(e.pop == nil and "default" or (e.pop and "on" or "off"))
            b.sound:SetValue(e.sound or "none")
            b.onCooldown:SetValue(e.onCooldown or "grey")
            b.show:SetValue(e.show or "always")
            b.unusable:SetValue(e.unusable or "dim")
            b.cdEdge:SetValue(e.border or "default")
            b.effect:SetValue(e.effect or "off")
            -- the effect: the spell itself, or any aura the presets know
            b.auraByName = candidates("aura")
            local options = { { value = "self", label = "The spell itself (" .. (e.name or "?") .. ")" } }
            local names = {}
            for name in pairs(b.auraByName) do names[#names + 1] = name end
            table.sort(names)
            for _, name in ipairs(names) do options[#options + 1] = { value = name, label = name } end
            local current = "self"
            if e.effectName then
                current = b.auraByName[e.effectName] and e.effectName or "current"
                if current == "current" then table.insert(options, 2, { value = "current", label = e.effectName }) end
            end
            b.effectAura:SetOptions(options)
            b.effectAura:SetValue(current)
            b.effectAura:SetDisabled(not e.effect)
        elseif ctx == "single" or ctx == "slot" then
            b.source:SetValue(entrySource(e, b.key))
            local debuff = b.key == "debuffs"
            b.missing:SetShown(not debuff)
            b.missingDebuff:SetShown(debuff)
            local missing = debuff and b.missingDebuff or b.missing
            missing:SetValue(e.missing or MISSING_DEFAULT[b.key])
            missing:SetAlpha(b.key == "procs" and T.opacity["opacity-disabled"] or 1)
            b.auEdge:SetValue(e.border or "default")
            b.size:SetValue(e.size or "normal")
            b.glow:SetValue(e.glow and true or false)
            b.digits:SetValue(e.digits ~= false)
            b.stacks:SetValue(e.stacks ~= false)
            b.expiring:SetValue(e.expiring or 3)
            b.soundAppear:SetValue(e.soundAppear or "none")
            b.soundStack:SetValue(e.soundStack or "none")
            b.soundDrop:SetValue(e.soundDrop or "none")
        end

        -- conditions: on every entry (a cooldown slot's members have no panel)
        fillConditions(b, e, ctx ~= "collection" and e.name or nil,
            ctx == "collection" and "Applies to everything inside." or nil)

        -- the sections that apply, stacked; Reset and Done under them
        for _, s in ipairs(b.sections) do s:Hide() end
        local h = 0
        for _, s in ipairs(shown) do
            s:ClearAllPoints()
            s:SetPoint("TOPLEFT", b.inner, "TOPLEFT", 0, -h)
            s:SetHeight(s.height)
            s:Show()
            h = h + s.height
        end
        h = h + 10
        b.reset:ClearAllPoints()
        b.reset:SetPoint("TOPLEFT", b.inner, "TOPLEFT", 0, -h)
        b.done:ClearAllPoints()
        b.done:SetPoint("TOPRIGHT", b.inner, "TOPLEFT", CW, -h)
        local content = h + 30
        b.inner:SetHeight(content)
        b:SetHeight(math.min(b:BodyTop() + content + 20, math.floor(SuuUI.Root:GetHeight() * 0.85)))
    end

    function f:OpenBehaviour(path)
        local t, i, slot = locate(M:Lists(M:EditSpec()), path)
        local e = t and t[i]
        if not e then return end
        self.behaviour = self.behaviour or buildBehaviour()
        local b = self.behaviour
        -- (b.name is the panel's Name field: the entry's name goes in entryName)
        b.key, b.path, b.uid, b.entryName, b.slotUid = path.key, path, e.uid, e.name, slot and slot.uid
        b.scroll:SetVerticalScroll(0)
        self:RefreshBehaviour()
        b:Show()
    end
    -- the panel closes with the page (and the settings window)
    f:HookScript("OnHide", function()
        if f.behaviour then f.behaviour:Hide() end
    end)
    -- "Seen recently" changes while the settings are closed
    f:HookScript("OnShow", function() f:Refresh() end)

    f:Refresh()
    M:Watch("setups", function() f:Refresh() end)
    M:On("SUUUI_COOLDOWNS_SETUP", function()
        -- another spec's lists: the Behaviour panel's entry isn't there
        if f.behaviour then f.behaviour:Hide() end
        f:Refresh()
    end)
    return f
end

local SECTION = {
    id = "cooldowns", label = "Cooldown Manager", category = "Frames", order = 26,
    groups = {
        { title = "What it shows", description = "Per specialization. A preset of your class fills the lists with its spells, every rank included. A shared slot puts several spells in one icon; a collection (auras) keeps entries together. Each entry decides for itself: shown or hidden, and what happens while it isn't up (auras): hidden (the others close up), grey in its place (debuffs: or only with a target), or Remind: grey only while it's missing and gone once it's up, out of combat (in combat the game hides which auras are up).", rows = {
            { label = "Your lists", control = "custom", build = buildPresetBar, stacked = true },
            { label = "Lists", control = "custom", build = buildEditor, stacked = true },
        } },
        { title = "How it shows", rows = {
            { key = "shows", label = "Shows", control = "segmented", options = UI.VISIBILITY_OPTIONS, combat = true,
              description = "Always, only in combat, or when the mouse is over it." },
            { key = "essentialSize", label = "Essential size", control = "slider", min = 30, max = 52, step = 2, unit = "px", live = false, combat = true,
              description = "The Essential row's icons. Utility stays at 30px unless it sits after Essential." },
            { key = "utilityInline", label = "Utility", control = "segmented", combat = true,
              options = { { value = false, label = "Own row" }, { value = true, label = "After Essential" } },
              description = "After Essential keeps the block two rows tall (the healer layout)." },
            { key = "readyPop", label = "Pop when ready", control = "toggle", description = "A cooldown coming off cooldown pops with the arcane flash." },
            { key = "procHighlight", label = "Proc highlight", control = "toggle", combat = true, description = "Procs wear the arcane edge and glow." },
        } },
    },
}

--------------------------------------------------------------------------------
-- Lifecycle
--------------------------------------------------------------------------------

function M:OnEnable()
    -- Blizzard's own manager would show beside this one (it comes back when
    -- this module turns off).
    if C_CVar and C_CVar.GetCVar and C_CVar.GetCVar("cooldownViewerEnabled") == "1" then
        if pcall(C_CVar.SetCVar, "cooldownViewerEnabled", "0") then self:Set("viewerOff", true) end
    end
    if not self.tracker then
        self.tracker = UI.CooldownTracker(SuuUI.Root, { name = "SuuUICooldownManager" })
        self.tracker.suuManagedShow = true
    else
        self.tracker:Start() -- turned on again
    end
    -- This character's spec, then the lists from before setups (once). A
    -- spec seen the first time starts from its preset (M:Setup).
    self.spec, self.points = self:DetectSpec()
    self:MigrateLists() -- before anything reads a setup (that would create it from the preset)
    self:RegisterMover(self.tracker, { key = "position", label = "Cooldown Manager" })
    self:RegisterSettings(SECTION)
    self:Apply()
    for _, key in ipairs({ "setups", "essentialSize", "utilityInline", "readyPop", "procHighlight" }) do
        self:Watch(key, function() self:Apply() end)
    end
    -- moving it or when it shows doesn't rebuild it
    for _, key in ipairs({ "shows", "position" }) do
        self:Watch(key, function() self:ApplyVisibility() end)
    end
    -- "Seen recently" for "+ Add" (aura changes settle first)
    local pending = false
    self:OnUnitEvent("UNIT_AURA", { "player", "target" }, function()
        if pending or InCombatLockdown() then return end
        pending = true
        C_Timer.After(1, function() pending = false; rememberAuras() end)
    end)
    self:OnGameEvent("PLAYER_TARGET_CHANGED", function() C_Timer.After(0.5, rememberAuras) end)
    self:OnUnitEvent("UNIT_SPELLCAST_SUCCEEDED", "player", function(_, _, _, spellID) rememberCast(spellID) end)
    -- respecs and new talent points switch the setup
    local valid = C_EventUtils and C_EventUtils.IsEventValid
    for _, e in ipairs({ "TRAIT_CONFIG_UPDATED", "TRAIT_NODE_CHANGED", "PLAYER_TALENT_UPDATE", "CHARACTER_POINTS_CHANGED",
                         "PLAYER_LEVEL_UP", "PLAYER_ENTERING_WORLD", "ACTIVE_PLAYER_SPECIALIZATION_CHANGED" }) do
        if not valid or valid(e) then
            self:OnGameEvent(e, function() C_Timer.After(0.2, function() self:UpdateSpec() end) end)
        end
    end
end

-- Off: no events, driver or aura sounds, hidden in edit and keybind mode
-- too, and Blizzard's manager back if this module switched it off.
function M:OnDisable()
    if self.tracker then
        self.tracker:Stop()
        UI.SetVisibility(self.tracker, "hidden")
    end
    if self:Get("viewerOff") then
        self:Set("viewerOff", false)
        self:RunOutOfCombat("viewer", function()
            if C_CVar and C_CVar.SetCVar then pcall(C_CVar.SetCVar, "cooldownViewerEnabled", "1") end
        end)
    end
end
