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
        missingBuffs = "grey",
        missingDebuffs = "target",
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

local function copyLists(p)
    local out = {}
    for _, key in ipairs(LIST_KEYS) do
        out[key] = {}
        for i, e in ipairs(p.lists[key] or {}) do
            local c = deepCopy(e)
            if c.group then c.uid = c.uid or (p.id .. key .. i) end
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
        missingBuffs = self:Get("missingBuffs"),
        missingDebuffs = self:Get("missingDebuffs"),
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

-- A group's IDs: every member's, once, sorted; its icon stays one of them.
local function regroup(e)
    local seen, ids = {}, {}
    for _, m in ipairs(e.members or {}) do
        for _, id in ipairs(m.ids or {}) do
            if not seen[id] then seen[id] = true; ids[#ids + 1] = id end
        end
    end
    table.sort(ids)
    e.ids = ids
    if e.icon and not seen[e.icon] then e.icon = nil end
    if not e.icon and e.members and e.members[1] then e.icon = e.members[1].ids[1] end
end

local SOURCE_LABEL = { mine = "only yours", others = "only others'", any = "from anyone" }
-- Whose aura a list counts unless an entry says otherwise (the tracker's
-- defaults): buffs from anyone, your debuffs and procs only yours.
local LIST_SOURCE = { buffs = "any", debuffs = "mine", procs = "mine" }
local function entrySource(e, key)
    return e.source or (e.group and "mine") or (e.mine and "mine") or LIST_SOURCE[key] or "mine"
end

-- What the Behaviour panel sets on an entry (its Reset clears them all).
local BEHAVIOUR_KEYS = { "ready", "pop", "sound", "onCooldown", "show", "unusable", "border", "effect", "effectIDs", "effectName",
                         "missing", "size", "glow", "digits", "stacks", "expiring", "soundAppear", "soundStack", "soundDrop" }
-- What else makes an entry differ from the preset's: shown or not, and a
-- group's own settings (its name is how it's matched).
local ENTRY_KEYS = { "hidden", "ids", "max", "icon", "members" }

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
-- removed, or changed (shown, behaviour, a group's settings).
function M:Changes()
    local spec = self:EditSpec()
    local p = findPreset(self:PresetId(spec))
    if not p then return 0 end
    local lists, n = self:Lists(spec), 0
    for _, key in ipairs(LIST_KEYS) do
        local base, now = {}, {}
        for _, e in ipairs(p.lists[key] or {}) do base[e.name] = e end
        for _, e in ipairs(lists[key] or {}) do
            now[e.name] = true
            if not base[e.name] or changed(e, base[e.name], key) then n = n + 1 end
        end
        for name in pairs(base) do if not now[name] then n = n + 1 end end
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
    return "Not learned", entry.ids[1] -- Rank 1: the highest IDs are often NPC versions
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

-- Returns spells by name, and (auras) the presets' groups by name with the
-- list each came from.
local function candidates(kind)
    local byName, groups = {}, {}
    local function add(name, ids)
        if not name then return end
        byName[name] = byName[name] or {}
        local seen = {}
        for _, id in ipairs(byName[name]) do seen[id] = true end
        for _, id in ipairs(ids) do if not seen[id] then table.insert(byName[name], id); seen[id] = true end end
    end
    local keys = kind == "cooldown" and { "essential", "utility" } or { "buffs", "debuffs", "procs" }
    for _, p in ipairs(presets()) do
        for _, key in ipairs(keys) do
            for _, e in ipairs(p.lists[key] or {}) do
                if e.group then
                    groups[e.name] = groups[e.name] or { entry = e, key = key }
                else
                    add(e.name, e.ids)
                end
            end
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
local function spellLookup(query)
    local id = tonumber((query or ""):match("^%s*(%d+)%s*$"))
    local name = id and C_Spell.GetSpellName(id)
    if isSecret(name) or not name then return nil end
    return { { value = "id:" .. id, label = ("%s · ID %d"):format(name, id) } }
end

-- An option's value as an entry: a name (every ID it carries) or "id:123".
local function entryFor(value, byName, groups)
    local id = type(value) == "string" and tonumber(value:match("^id:(%d+)$"))
    if id then return { name = C_Spell.GetSpellName(id), ids = { id } } end
    local gname = type(value) == "string" and value:match("^group:(.+)$")
    if gname and groups and groups[gname] then
        local g = copy(groups[gname].entry)
        g.uid = tostring(time()) .. math.random(1000, 9999)
        return g
    end
    if byName and byName[value] then return { name = value, ids = byName[value] } end
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

local ROW_H, WIDTH = 30, 560
local NEW_GROUP = "New group" -- a new group's name until you give it one

local MISSING = {
    { value = "list", label = "List" },
    { value = "hide", label = "Hide" },
    { value = "grey", label = "Grey" },
    { value = "warn", label = "Warn" },
    { value = "remind", label = "Remind" },
}
local MISSING_LABEL = { hide = "hide", grey = "grey", warn = "warn", remind = "remind" }

-- One entry: icon, name, rank, then (right to left) remove, move, down, up,
-- and shown (cooldowns) or when missing (auras).
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

-- One entry: grip, icon, name, rank, then (right to left) remove, move, and
-- shown (cooldowns) or when missing (auras). The row drags to reorder, into
-- any list of the same tab.
local function buildEntryRow(parent)
    local r = CreateFrame("Frame", nil, parent)
    r:SetSize(WIDTH, ROW_H)
    r.grip = grip(r)
    r.grip:SetPoint("LEFT")
    r.icon = UI.Icon(r, 22)
    r.icon:SetPoint("LEFT", r.grip, "RIGHT", 6, 0)
    r.name = UI.Text(r, "label", "ink")
    r.name:SetPoint("TOPLEFT", r.icon, "TOPRIGHT", 8, 1)
    r.name:SetFixedWidth(180)
    r.rank = UI.Text(r, "caption", "ink-muted")
    r.rank:SetFixedWidth(180)
    r.rank:SetPoint("BOTTOMLEFT", r.icon, "BOTTOMRIGHT", 8, -1)
    r.remove = glyphButton(r, "remove", function() mutate(function(l) table.remove(l[r.key], r.index) end) end)
    r.remove:SetPoint("RIGHT")
    r.move = UI.Select(r, { width = 104, placeholder = "Move to…", onChange = function(to)
        if not to then return end
        mutate(function(l)
            local e = table.remove(l[r.key], r.index)
            table.insert(l[to], e)
        end)
    end })
    r.move:SetPoint("RIGHT", r.remove, "LEFT", -6, 0)
    r.edit = UI.Button(r, { text = "Edit group", width = 104, onClick = function() parent:OpenGroup(r.key, r.index) end })
    r.edit:SetPoint("RIGHT", r.remove, "LEFT", -6, 0)
    r.behaviour = UI.Button(r, { text = "Behaviour", width = 96, onClick = function() parent:OpenBehaviour(r.key, r.index) end })
    r.behaviour:SetPoint("RIGHT", r.move, "LEFT", -8, 0)
    r.shown = UI.Toggle(r, { onChange = function(v)
        mutate(function(l) l[r.key][r.index].hidden = (not v) or nil end)
    end })
    r.shown:SetPoint("RIGHT", r.behaviour, "LEFT", -10, 0)

    -- drag to reorder: the editor tracks the cursor and drops
    r:EnableMouse(true)
    r:RegisterForDrag("LeftButton")
    r:SetScript("OnEnter", function() r.grip:SetAlpha(1); for _, t in ipairs({ r.grip:GetRegions() }) do t:SetColorTexture(UI.RGBA("ink-muted")) end end)
    r:SetScript("OnLeave", function() for _, t in ipairs({ r.grip:GetRegions() }) do t:SetColorTexture(UI.RGBA("ink-faint")) end end)
    r:SetScript("OnDragStart", function() parent:StartDrag(r) end)
    r:SetScript("OnDragStop", function() parent:StopDrag() end)
    return r
end

local function fillEntryRow(r, key, index, entry)
    r.key, r.index = key, index
    local info = LIST_INFO[key]
    if entry.group then
        local n = #(entry.members or {})
        r.icon:SetArt(C_Spell.GetSpellTexture(entry.icon or (entry.ids or {})[1]))
        r.icon:SetState("rest")
        r.name:SetValue(entry.name or "Group")
        r.name:SetColor(UI.RGBA("ink"))
        r.rank:SetValue(("%d %s"):format(n, n == 1 and "spell" or "spells"))
    else
        local rank, id = rankText(entry)
        r.icon:SetArt(C_Spell.GetSpellTexture(id))
        r.icon:SetState(rank == "Not learned" and "dim" or "rest")
        r.name:SetValue(entry.name)
        r.name:SetColor(UI.RGBA(rank == "Not learned" and "ink-muted" or "ink"))
        -- whose, when it isn't the list's usual
        local src = info.kind == "aura" and entrySource(entry, key)
        local extra = src and src ~= LIST_SOURCE[key] and (" · " .. SOURCE_LABEL[src]) or ""
        r.rank:SetValue(rank .. extra)
    end
    r.move:SetShown(not entry.group)
    r.edit:SetShown(entry.group and true or false)
    local moves = {}
    for _, k in ipairs(info.kind == "cooldown" and TABS.cooldowns or TABS.auras) do
        if k ~= key then moves[#moves + 1] = { value = k, label = LIST_INFO[k].label } end
    end
    r.move:SetOptions(moves)
    r.move:SetValue(nil)
    local cooldown = info.kind == "cooldown"
    r.shown:SetShown(cooldown)
    if cooldown then r.shown:SetValue(not entry.hidden) end
    -- what the Behaviour panel changed, at a glance
    if not cooldown and key ~= "procs" then
        local m = entry.missing and MISSING_LABEL[entry.missing]
        if m then r.rank:SetValue(r.rank:GetText() .. " · missing: " .. m) end
    elseif cooldown and entry.effect then
        r.rank:SetValue(r.rank:GetText() .. " · shows " .. (entry.effectName or "its effect"))
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
    f.rows, f.heads, f.adds = {}, {}, {}

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

    -- "+ Add" at a list's foot: a Select of candidates, and a spell ID field.
    local function addRow(i)
        local a = f.adds[i]
        if not a then
            a = CreateFrame("Frame", nil, f)
            a:SetSize(WIDTH, 34)
            -- names from your spellbook and the presets; a typed number finds
            -- any spell by its ID
            a.select = UI.Select(a, { width = 300, placeholder = "+ Add… (name or spell ID)", lookup = spellLookup,
                onChange = function(value)
                    local e = value and entryFor(value, a.byName, a.groups)
                    if e then mutate(function(l) table.insert(l[a.key], e) end) end
                end })
            a.select:SetPoint("LEFT")
            a.newGroup = UI.Button(a, { text = "+ New group", width = 120, onClick = function()
                local index
                mutate(function(l)
                    table.insert(l[a.key], { group = true, uid = tostring(time()) .. math.random(1000, 9999),
                        name = NEW_GROUP, source = "mine", max = 1, members = {}, ids = {} })
                    index = #l[a.key]
                end)
                f:OpenGroup(a.key, index)
            end })
            a.newGroup:SetPoint("LEFT", a.select, "RIGHT", 8, 0)
            f.adds[i] = a
        end
        return a
    end

    -- Dragging: a ghost follows the cursor, an arcane line marks the drop.
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

    -- Where a drop at the cursor lands: { key, index } in the visible tab.
    function f:DropTarget()
        local _, cy = GetCursorPosition()
        cy = cy / self:GetEffectiveScale()
        local best
        for _, key in ipairs(TABS[self.tab]) do
            local L = self.layout[key]
            local top, bottom = L and L.head:GetTop(), L and L.add:GetBottom()
            if top and bottom and cy <= top and cy >= bottom then
                local index = 1
                for _, row in ipairs(L.rows) do
                    local mid = (row:GetTop() + row:GetBottom()) / 2
                    if cy < mid then index = index + 1 end
                end
                best = { key = key, index = index }
            end
        end
        return best
    end

    function f:StartDrag(row)
        self.drag = { key = row.key, index = row.index }
        row:SetAlpha(0.4)
        self.dragRow = row
        self.ghost.icon:SetArt(row.icon.art:GetTexture())
        self.ghost.name:SetValue(row.name:GetText() or "")
        self.ghost:Show()
        self:SetScript("OnUpdate", function()
            local x, y = GetCursorPosition()
            local s = UIParent:GetEffectiveScale()
            self.ghost:ClearAllPoints()
            self.ghost:SetPoint("LEFT", UIParent, "BOTTOMLEFT", x / s + 12, y / s)
            local t = self:DropTarget()
            self.target = t
            if t then
                local L = self.layout[t.key]
                local anchor = L.rows[t.index]
                self.line:ClearAllPoints()
                self.line:SetPoint("LEFT", self, "LEFT", 0, 0)
                self.line:SetWidth(WIDTH)
                if anchor then
                    self.line:SetPoint("BOTTOM", anchor, "TOP", 0, 1)
                else
                    self.line:SetPoint("BOTTOM", L.add, "TOP", 0, 3)
                end
                self.line:Show()
            else
                self.line:Hide()
            end
        end)
    end

    function f:StopDrag()
        self:SetScript("OnUpdate", nil)
        self.ghost:Hide()
        self.line:Hide()
        if self.dragRow then self.dragRow:SetAlpha(1) end
        local from, to = self.drag, self.target
        self.drag, self.target, self.dragRow = nil, nil, nil
        if not (from and to) then return end
        local index = to.index
        if to.key == from.key and index > from.index then index = index - 1 end
        if to.key == from.key and index == from.index then return end
        mutate(function(l)
            local e = table.remove(l[from.key], from.index)
            table.insert(l[to.key], math.min(index, #l[to.key] + 1), e)
        end)
    end

    function f:Refresh()
        self.layout = {}
        for _, r in ipairs(self.rows) do r:Hide() end
        for _, h in ipairs(self.heads) do h:Hide() end
        for _, a in ipairs(self.adds) do a:Hide() end
        local lists = M:Lists(M:EditSpec())
        local y = -(30 + 12)
        local rowN = 0
        for i, key in ipairs(TABS[self.tab]) do
            local info = LIST_INFO[key]
            local list = lists[key] or {}
            local h = head(i)
            h.title:SetValue(info.label)
            h.note:SetValue(info.note)
            h.count:SetValue(#list == 1 and "1 spell" or (#list .. " spells"))
            h:ClearAllPoints()
            h:SetPoint("TOPLEFT", 0, y)
            h:Show()
            local L = { rows = {}, head = h }
            self.layout[key] = L
            y = y - 38
            for index, entry in ipairs(list) do
                rowN = rowN + 1
                local r = self.rows[rowN] or buildEntryRow(self)
                self.rows[rowN] = r
                fillEntryRow(r, key, index, entry)
                r:ClearAllPoints()
                r:SetPoint("TOPLEFT", 0, y)
                L.rows[#L.rows + 1] = r
                y = y - (ROW_H + 4)
            end
            local a = addRow(i)
            a.key = key
            a.newGroup:SetShown(info.kind == "aura")
            local present = {}
            for _, e in ipairs(list) do present[e.name] = true end
            a.byName, a.groups = candidates(info.kind)
            -- what you cast or saw lately first, then everything by name
            local top, taken = {}, {}
            for _, r in ipairs(recent(info.kind)) do
                if not present[r.name] and not taken[r.name] then
                    taken[r.name] = true
                    if not a.byName[r.name] then a.byName[r.name] = copy(r.ids) end
                    top[#top + 1] = { value = r.name, label = r.name }
                end
            end
            local options = {}
            for name in pairs(a.byName) do
                if not present[name] and not taken[name] then options[#options + 1] = { value = name, label = name } end
            end
            -- the presets' groups that belong in this list, marked as groups
            for name, g in pairs(a.groups or {}) do
                if not present[name] and g.key == key then
                    options[#options + 1] = { value = "group:" .. name, label = name .. " (Group)" }
                end
            end
            table.sort(options, function(x, z) return x.label < z.label end)
            if #top > 0 then
                table.insert(top, 1, { heading = "Seen recently" })
                top[#top + 1] = { heading = "All" }
                for _, o in ipairs(options) do top[#top + 1] = o end
                options = top
            end
            a.select:SetOptions(options)
            a.select:SetValue(nil)
            a:ClearAllPoints()
            a:SetPoint("TOPLEFT", 0, y)
            a:Show()
            L.add = a
            y = y - 46
        end
        self:SetHeight(-y)
        if self.group and self.group:IsShown() then self:RefreshGroup() end
        if self.behaviour and self.behaviour:IsShown() then self:RefreshBehaviour() end
    end

    ---------------------------------------------------------------------------
    -- The group panel: name, source, how many at once, icon, members
    ---------------------------------------------------------------------------

    local GP_W = 380
    local MEMBER_ROWS = 6
    local function groupEntry()
        local g = f.group
        local list = M:Lists(M:EditSpec())[g.key] or {}
        for i, e in ipairs(list) do
            if e.group and e.uid == g.uid then g.index = i; return e end
        end
    end
    local function mutateGroup(fn)
        local g = f.group
        mutate(function(l)
            for _, e in ipairs(l[g.key] or {}) do
                if e.group and e.uid == g.uid then fn(e); regroup(e) end
            end
        end)
    end

    local function buildGroupPanel()
        local g = UI.Panel(SuuUI.Root, { title = "Group", width = GP_W, height = 520, solid = true })
        UI.MakeModal(g) -- centred, over a dimmed screen; Esc or a click outside closes
        local b = g.body
        local y = 0
        local function label(text)
            local t = UI.Text(b, "caption", "ink-muted")
            t:SetPoint("TOPLEFT", 0, -y)
            t:SetValue(text)
            y = y + 18
        end
        label("Name")
        g.name = UI.TextField(b, { width = GP_W - 40, onChange = function(text)
            if text and text ~= "" then mutateGroup(function(e) e.name = text end) end
        end })
        g.name:SetPoint("TOPLEFT", 0, -y); y = y + 40
        label("Whose")
        g.source = UI.Segmented(b, { options = {
            { value = "mine", label = "Only yours" }, { value = "others", label = "Only others'" }, { value = "any", label = "Anyone" } },
            onChange = function(v) mutateGroup(function(e) e.source = v end) end })
        g.source:SetPoint("TOPLEFT", 0, -y); y = y + 40
        label("How many at once")
        g.max = UI.Stepper(b, { min = 1, max = 4, step = 1, onChange = function(v) mutateGroup(function(e) e.max = v end) end })
        g.max:SetPoint("TOPLEFT", 0, -y); y = y + 40
        label("Icon when none is up")
        g.icon = UI.Select(b, { width = GP_W - 40, placeholder = "First spell", onChange = function(v)
            if v then mutateGroup(function(e) e.icon = v end) end
        end })
        g.icon:SetPoint("TOPLEFT", 0, -y); y = y + 40
        label("Spells")
        g.membersTop = y
        g.memberRows = {}
        g.offset = 0
        -- the spells: at most MEMBER_ROWS visible, the wheel scrolls
        g.track = b:CreateTexture(nil, "ARTWORK")
        g.track:SetColorTexture(UI.RGBA("gilt-faint"))
        g.thumb = b:CreateTexture(nil, "OVERLAY")
        g.thumb:SetColorTexture(UI.RGBA("ink-muted"))
        g.wheel = CreateFrame("Frame", nil, b)
        g.wheel:EnableMouseWheel(true)
        g.wheel:SetScript("OnMouseWheel", function(_, delta)
            g.offset = (g.offset or 0) - delta
            f:RefreshGroup()
        end)
        g.add = UI.Select(b, { width = GP_W - 40, placeholder = "+ Add a spell (name or spell ID)", lookup = spellLookup,
            onChange = function(value)
                local m = value and entryFor(value, g.byName)
                if m then
                    mutateGroup(function(e)
                        e.members = e.members or {}
                        table.insert(e.members, m)
                    end)
                end
            end })
        g.done = UI.Button(b, { text = "Done", variant = "primary", width = 90, onClick = function() g:Hide() end })
        -- "+ New group" closed (Done, Esc, a click outside) before it got a
        -- spell or a name: nothing to keep
        g:HookScript("OnHide", function()
            local e = groupEntry()
            if e and #(e.members or {}) == 0 and (e.name or NEW_GROUP) == NEW_GROUP then
                mutate(function(l)
                    for i, x in ipairs(l[g.key] or {}) do
                        if x.group and x.uid == g.uid then table.remove(l[g.key], i); break end
                    end
                end)
            end
        end)
        return g
    end

    function f:RefreshGroup()
        local g = self.group
        local e = groupEntry()
        if not e then g:Hide(); return end
        g:SetTitle(e.name or "Group")
        g.name:SetValue(e.name or "")
        g.source:SetValue(e.source or "mine")
        g.max:SetValue(e.max or 1)
        local iconOptions = {}
        for _, m in ipairs(e.members or {}) do iconOptions[#iconOptions + 1] = { value = m.ids[1], label = m.name } end
        g.icon:SetOptions(iconOptions)
        g.icon:SetValue(e.icon)
        -- members, each with a remove button; MEMBER_ROWS at a time
        for _, row in ipairs(g.memberRows) do row:Hide() end
        local members = e.members or {}
        local maxOffset = math.max(0, #members - MEMBER_ROWS)
        g.offset = math.max(0, math.min(g.offset or 0, maxOffset))
        local y = g.membersTop
        for i = 1, math.min(MEMBER_ROWS, #members) do
            local index = g.offset + i
            local m = members[index]
            local row = g.memberRows[i]
            if not row then
                row = CreateFrame("Frame", nil, g.body)
                row:SetSize(GP_W - 40, 26)
                row.icon = UI.Icon(row, 20)
                row.icon:SetPoint("LEFT")
                row.label = UI.Text(row, "body", "ink")
                row.label:SetPoint("LEFT", row.icon, "RIGHT", 8, 0)
                row.remove = glyphButton(row, "remove", function()
                    mutateGroup(function(x) table.remove(x.members, row.index) end)
                end)
                row.remove:SetPoint("RIGHT")
                g.memberRows[i] = row
            end
            row.index = index
            row:SetWidth(GP_W - 40 - (maxOffset > 0 and 10 or 0))
            row.icon:SetArt(C_Spell.GetSpellTexture(m.ids[1]))
            row.label:SetValue(m.name)
            row:ClearAllPoints()
            row:SetPoint("TOPLEFT", 0, -y)
            row:Show()
            y = y + 28
        end
        -- the scroll area and its bar
        local areaH = math.max(1, y - g.membersTop)
        g.wheel:ClearAllPoints()
        g.wheel:SetPoint("TOPLEFT", 0, -g.membersTop)
        g.wheel:SetSize(GP_W - 40, areaH)
        g.wheel:SetFrameLevel(g.body:GetFrameLevel())
        g.track:SetShown(maxOffset > 0)
        g.thumb:SetShown(maxOffset > 0)
        if maxOffset > 0 then
            g.track:ClearAllPoints()
            g.track:SetPoint("TOPRIGHT", g.body, "TOPLEFT", GP_W - 40, -g.membersTop)
            g.track:SetSize(3, areaH)
            local thumbH = math.max(14, areaH * MEMBER_ROWS / #members)
            g.thumb:ClearAllPoints()
            g.thumb:SetPoint("TOP", g.track, "TOP", 0, -(areaH - thumbH) * g.offset / maxOffset)
            g.thumb:SetSize(3, thumbH)
        end
        g.add:ClearAllPoints()
        g.add:SetPoint("TOPLEFT", 0, -(y + 4))
        -- Done under "+ Add a spell", and the panel as tall as its contents
        local doneY = y + 4 + 30 + 16
        g.done:ClearAllPoints()
        g.done:SetPoint("TOPRIGHT", g.body, "TOPLEFT", GP_W - 40, -doneY)
        g:SetHeight(g:BodyTop() + doneY + 30 + 20)
        g.byName = candidates("aura")
        local present = {}
        for _, m in ipairs(e.members or {}) do present[m.name] = true end
        local options = {}
        for name in pairs(g.byName) do
            if not present[name] then options[#options + 1] = { value = name, label = name } end
        end
        table.sort(options, function(x, z) return x.label < z.label end)
        g.add:SetOptions(options)
        g.add:SetValue(nil)
    end

    ---------------------------------------------------------------------------
    -- The Behaviour panel: per entry, a modal. Cooldowns: when ready, pop,
    -- sound, on cooldown, show, when unusable, edge. Auras: when missing,
    -- edge, size, glow, digits, stacks, amber, sounds.
    ---------------------------------------------------------------------------

    local BP_W = 420
    local EDGES = { { value = "default", label = "By state" }, { value = "ink", label = "Ink" },
                    { value = "gilt", label = "Gilt" }, { value = "muted", label = "Muted" } }
    local SOUND_OPTIONS = { { value = "none", label = "None" }, { value = "chime", label = "Ready chime" },
                            { value = "ping", label = "Soft ping" }, { value = "proc", label = "Proc" },
                            { value = "warning", label = "Warning" } }

    -- The panel's entry in a list: by its uid (groups have one), else at its
    -- index while that is still the same spell; nil once it's gone.
    local function findEntry(list)
        local b = f.behaviour
        if b.uid then
            for i, e in ipairs(list or {}) do
                if e.uid == b.uid then b.index = i; return e end
            end
            return nil
        end
        local e = (list or {})[b.index]
        if e and e.name == b.name then return e end
    end

    local function mutateEntry(fn)
        local b = f.behaviour
        mutate(function(l)
            local e = findEntry(l[b.key])
            if e then fn(e) end
        end)
    end

    -- A label over a control, stacked down the panel's body.
    local function stack(panel)
        local y = 0
        return function(label, control, h)
            if label then
                local t = UI.Text(panel.body, "caption", "ink-muted")
                t:SetPoint("TOPLEFT", 0, -y)
                t:SetValue(label)
                y = y + 18
            end
            control:SetPoint("TOPLEFT", 0, -y)
            y = y + (h or 30) + 12
            return y
        end
    end

    local function buildBehaviour()
        local b = UI.Panel(SuuUI.Root, { title = "Behaviour", width = BP_W, height = 600, solid = true })
        UI.MakeModal(b)
        -- cooldowns
        local cd = CreateFrame("Frame", nil, b.body)
        cd:SetAllPoints(b.body)
        local add = stack({ body = cd })
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
        b.cdHeight = add("Effect (name or spell ID)", b.effectAura)
        b.cd = cd

        -- auras
        local au = CreateFrame("Frame", nil, b.body)
        au:SetAllPoints(b.body)
        local addA = stack({ body = au })
        -- whose aura counts (a group's is the same setting as in its panel)
        b.source = UI.Segmented(au, { options = { { value = "mine", label = "Only yours" }, { value = "others", label = "Only others'" }, { value = "any", label = "Anyone's" } },
            onChange = function(v)
                mutateEntry(function(e)
                    e.mine = nil
                    e.source = v ~= LIST_SOURCE[f.behaviour.key] and v or nil
                    if e.group then e.source = v end
                end)
            end })
        addA("Whose", b.source)
        b.missing = UI.Segmented(au, { options = MISSING, onChange = function(v)
            mutateEntry(function(e) e.missing = v ~= "list" and v or nil end) end })
        addA("When missing", b.missing)
        b.auEdge = UI.Segmented(au, { options = EDGES, onChange = function(v)
            mutateEntry(function(e) e.border = v ~= "default" and v or nil end) end })
        addA("Edge", b.auEdge)
        b.size = UI.Segmented(au, { options = { { value = "small", label = "Small" }, { value = "normal", label = "Normal" }, { value = "large", label = "Large" } },
            onChange = function(v) mutateEntry(function(e) e.size = v ~= "normal" and v or nil end) end })
        addA("Size", b.size)
        -- three switches in one row
        local row = CreateFrame("Frame", nil, au)
        row:SetSize(BP_W - 40, 30)
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
        b.expiring = UI.Stepper(au, { min = 1, max = 10, step = 1, unit = "s", onChange = function(v)
            mutateEntry(function(e) e.expiring = v ~= 3 and v or nil end) end })
        addA("Timer turns amber in the last", b.expiring)
        -- sounds: the engine plays them (registered on every tracker build)
        local function soundSelect(field)
            return UI.Select(au, { width = 220, options = SOUND_OPTIONS, onChange = function(v)
                mutateEntry(function(e) e[field] = v ~= "none" and v or nil end)
                if v ~= "none" then UI.TrackerSound(v) end
            end })
        end
        b.soundAppear = soundSelect("soundAppear")
        addA("Sound when it appears", b.soundAppear)
        b.soundStack = soundSelect("soundStack")
        addA("Sound when it stacks up", b.soundStack)
        b.soundDrop = soundSelect("soundDrop")
        b.auHeight = addA("Sound when it drops", b.soundDrop)
        b.soundNote = UI.Text(au, "caption", "ink-muted")
        b.soundNote:SetWordWrap(true)
        b.soundNote:SetJustifyH("LEFT")
        b.soundNote:SetFixedWidth(BP_W - 40)
        b.soundNote:SetPoint("TOPLEFT", 0, -(b.auHeight - 6))
        b.soundNote:SetValue("The game plays these itself, in combat too, for this aura from anyone.")
        b.au = au

        b.reset = UI.Button(b.body, { text = "Reset", width = 90, onClick = function()
            mutateEntry(function(e)
                if not e.group then e.source, e.mine = nil, nil end
                for _, k in ipairs(BEHAVIOUR_KEYS) do e[k] = nil end
            end)
        end })
        b.done = UI.Button(b.body, { text = "Done", variant = "primary", width = 90, onClick = function() b:Hide() end })
        return b
    end

    function f:RefreshBehaviour()
        local b = self.behaviour
        local e = findEntry(M:Lists(M:EditSpec())[b.key])
        if not e then b:Hide(); return end
        local cooldown = LIST_INFO[b.key].kind == "cooldown"
        b:SetTitle(e.name or "Behaviour")
        b.cd:SetShown(cooldown)
        b.au:SetShown(not cooldown)
        if cooldown then
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
        else
            b.source:SetValue(entrySource(e, b.key))
            b.missing:SetValue(e.missing or "list")
            b.missing:SetAlpha(b.key == "procs" and T.opacity["opacity-disabled"] or 1)
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
        local h = cooldown and b.cdHeight or (b.auHeight + 34)
        b.reset:ClearAllPoints()
        b.reset:SetPoint("TOPLEFT", b.body, "TOPLEFT", 0, -h)
        b.done:ClearAllPoints()
        b.done:SetPoint("TOPRIGHT", b.body, "TOPLEFT", BP_W - 40, -h)
        b:SetHeight(b:BodyTop() + h + 30 + 20)
    end

    function f:OpenBehaviour(key, index)
        local e = (M:Lists(M:EditSpec())[key] or {})[index]
        if not e then return end
        self.behaviour = self.behaviour or buildBehaviour()
        local b = self.behaviour
        b.key, b.index, b.uid, b.name = key, index, e.uid, e.name
        self:RefreshBehaviour()
        b:Show()
    end

    function f:OpenGroup(key, index)
        local e = (M:Lists(M:EditSpec())[key] or {})[index]
        if not (e and e.group) then return end
        if not e.uid then
            -- older groups (presets) get an id the panel can follow
            mutate(function(l) l[key][index].uid = tostring(time()) .. math.random(1000, 9999) end)
            e = M:Lists(M:EditSpec())[key][index]
        end
        self.group = self.group or buildGroupPanel()
        self.group.key, self.group.uid, self.group.index = key, e.uid, index
        self:RefreshGroup()
        self.group:Show()
    end
    -- the panels close with the page (and the settings window)
    f:HookScript("OnHide", function()
        if f.group then f.group:Hide() end
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
        { title = "What it shows", description = "Per specialization. A preset of your class fills the lists with its spells, every rank included. Per spell: shown or hidden (cooldowns), and what happens while it isn't up (auras): the list's choice, hidden (the others close up), grey in its place, or Remind: grey only while it's missing and gone once it's up, out of combat (in combat the game hides which auras are up).", rows = {
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
            { key = "missingBuffs", label = "Missing buffs", control = "segmented", combat = true,
              options = { { value = "hide", label = "Hide" }, { value = "grey", label = "Show grey" }, { value = "remind", label = "Remind" } },
              description = "A tracked buff that isn't up: hidden (the others close up), grey in its place, or Remind: grey only while it's missing, out of combat." },
            { key = "missingDebuffs", label = "Missing debuffs", control = "segmented", combat = true,
              options = { { value = "hide", label = "Hide" }, { value = "grey", label = "Show grey" }, { value = "target", label = "With a target" }, { value = "remind", label = "Remind" } },
              description = "Your debuffs that aren't on the target: hidden (the others close up), grey, grey only while you have a hostile target, or Remind: grey only while it's missing from a hostile target, out of combat." },
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
    for _, key in ipairs({ "setups", "essentialSize", "utilityInline", "missingBuffs", "missingDebuffs", "readyPop", "procHighlight" }) do
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
