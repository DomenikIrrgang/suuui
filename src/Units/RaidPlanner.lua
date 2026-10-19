-- Units/RaidPlanner.lua
-- The raid planner (asked 2026-10-19, design "Raid planner", A1 "Workbench"):
-- a setup is a saved raid layout made of slots, each asking for a class (or
-- any), maybe a spec and a role, in one of the eight groups. Load a setup and
-- the people in the raid fill their slots by themselves, out of combat,
-- whenever the raid changes; a player placed by hand stays (pinned). What
-- doesn't fit shows as open slots and players without a slot. Arrange
-- groups moves the real raid into the slots' groups (the leader or an
-- assistant, out of combat). Coverage: raid-wide (counted once) and
-- party-wide (per group of five), only what Settings › Raid planner tracks
-- (the catalog: SuuUI.RaidCatalog(), Data/RaidPlanner.lua).
-- Opens from Social › Raid › Plan and /suu raid.
--
-- Probed on Forever (/suu probe raid, 2026-10-19): the roster reads out of
-- combat (GetRaidRosterInfo, 12 values); SetRaidSubgroup and SwapRaidSubgroup
-- work for the leader from a click or a command, the roster update follows
-- 0.4-0.7 s later, three moves in one frame all land, a full group needs a
-- swap; an inspect answers in about half a second with the talent groups'
-- points (the spec). Specs: from an inspect (one player at a time, out of
-- combat), or from a raid member's own SuuUI (addon message, prefix "SuuUI":
-- "RPSPEC\t<tree>", "RPSPECQ" asks everyone). Until known a player fills
-- provisionally, spec "?" (shown with their class's icon, not a spec's).
-- Setups are account-wide (SuuUI.AccountData); what's tracked follows the
-- profile. A built-in module written against the public API only.

local UI = SuuUI.UI

local M = SuuUI.RegisterModule({
    id = "raidplanner",
    name = "Raid planner",
    description = "Plan raids as setups of slots: the raid fills them, Arrange groups moves everyone, and coverage shows the buffs, debuffs and dispels you track.",
    api = "0.17",
    combatSafe = true,
    defaults = {
        preset = "essentials", -- "all" | "essentials" | "custom"
        tracked = {},          -- custom: { [item key] = true }
        fill = "instant",      -- "instant" (as the raid changes) | "review" (Fill slots)
        inspect = "auto",      -- "auto" (while the planner is open) | "click"
        flagDoubled = true,
        shareSpec = true,
    },
})

local isSecret = issecretvalue or function() return false end
local function plain(v) return v ~= nil and not isSecret(v) end

local function call(fn, ...)
    if type(fn) ~= "function" then return nil end
    local ok, a, b, c, d, e, f, g, h, i, j, k, l = pcall(fn, ...)
    if ok then return a, b, c, d, e, f, g, h, i, j, k, l end
end

local function copy(t)
    if type(t) ~= "table" then return t end
    local out = {}
    for k, v in pairs(t) do out[k] = copy(v) end
    return out
end

local PREFIX = "SuuUI"
local MAX_GROUP = 5
local SIZES = { 40, 20, 10 }
local ROLE_WORD = { TANK = "tank", HEALER = "healer", DAMAGER = "damage" }
local ROLE_NAME = { TANK = "Tank", HEALER = "Healer", DAMAGER = "Damage" }
local INSPECT_CONFIG = Constants and Constants.TraitConsts and Constants.TraitConsts.INSPECT_TRAIT_CONFIG_ID or -1
local SPEC_FRESH = 24 * 3600 -- a spec heard or inspected counts for a day
local BLESSINGS = 3 -- Kings, Might or Wisdom, Light: one per paladin (Salvation isn't one on Forever)

-- A name as a key: the realm only for another realm's players.
local function key(name)
    if type(name) ~= "string" then return nil end
    return Ambiguate(name, "none")
end

--------------------------------------------------------------------------------
-- The catalog
--------------------------------------------------------------------------------

local CLASSES, CLASS, ITEMS, ITEM, FAMILIES = {}, {}, {}, {}, {}

local function loadCatalog()
    if #ITEMS > 0 then return end
    local cat = SuuUI.RaidCatalog()
    for _, c in ipairs(cat.classes or {}) do
        CLASSES[#CLASSES + 1] = c
        CLASS[c.file] = c
    end
    for _, f in ipairs(cat.families or {}) do FAMILIES[#FAMILIES + 1] = f end
    for _, it in ipairs(cat.items or {}) do
        ITEMS[#ITEMS + 1] = it
        ITEM[it.key] = it
    end
end

local function familyOf(key)
    for _, f in ipairs(FAMILIES) do if f.key == key then return f end end
end

-- A class's trees that can take a role (Feral tanks too).
local function canPlay(class, tree, role)
    local c = CLASS[class]
    if not c then return false end
    for t = 1, 3 do
        if (not tree or t == tree) and (c.roles[t] == role or (role == "TANK" and class == "DRUID" and t == 2)) then return true end
    end
    return false
end

local function plural(class)
    local c = CLASS[class]
    return c and (c.name:lower() .. "s") or "?"
end

local function joinAnd(list, word)
    if #list <= 1 then return list[1] or "" end
    return table.concat(list, ", ", 1, #list - 1) .. " " .. (word or "and") .. " " .. list[#list]
end

--------------------------------------------------------------------------------
-- What's tracked (per profile)
--------------------------------------------------------------------------------

local function presetSet(preset)
    local out = {}
    for _, it in ipairs(ITEMS) do
        if preset == "all" or it.essential then out[it.key] = true end
    end
    return out
end

local function sameSet(a, b)
    for k in pairs(a) do if not b[k] then return false end end
    for k in pairs(b) do if not a[k] then return false end end
    return true
end

function M:TrackedSet()
    local preset = self:Get("preset")
    if preset == "custom" then
        local out = {}
        for k, on in pairs(self:Get("tracked")) do if on and ITEM[k] then out[k] = true end end
        return out
    end
    return presetSet(preset == "all" and "all" or "essentials")
end

-- While the window is drawn, the set is read once (trackCache).
function M:IsTracked(itemKey)
    local set = self.trackCache or self:TrackedSet()
    return set[itemKey] == true
end

-- Writes a set: back to a preset when it is one, Custom otherwise.
function M:SetTrackedSet(set)
    if sameSet(set, presetSet("essentials")) then
        self:Set("tracked", {})
        self:Set("preset", "essentials")
    elseif sameSet(set, presetSet("all")) then
        self:Set("tracked", {})
        self:Set("preset", "all")
    else
        self:Set("tracked", set)
        self:Set("preset", "custom")
    end
end

function M:SetTracked(itemKey, on)
    local set = self:TrackedSet()
    set[itemKey] = on and true or nil
    self:SetTrackedSet(set)
end

function M:TrackedCount()
    local n = 0
    for _ in pairs(self:TrackedSet()) do n = n + 1 end
    return n
end

--------------------------------------------------------------------------------
-- Setups (account-wide): data.setups[id], and the loaded one being worked on
-- (data.work, a copy: Save writes it back)
--------------------------------------------------------------------------------

function M:Data()
    local d = SuuUI.AccountData("raidplanner")
    d.setups = d.setups or {}
    d.nextId = d.nextId or 1
    d.specs = d.specs or {}
    d.treeIcons = d.treeIcons or {}
    d.size = d.size or 40
    return d
end

local function newSetup(name, size)
    return { name = name, size = size or 40, slots = {}, nextSlot = 1 }
end

function M:Work()
    local d = self:Data()
    if not d.work then d.work = newSetup(self:UniqueName("New setup"), d.size) end
    return d.work
end

function M:UniqueName(base)
    local taken = {}
    for _, s in pairs(self:Data().setups) do taken[s.name] = true end
    local w = self:Data().work
    if w then taken[w.name] = true end
    if not taken[base] then return base end
    for n = 2, 99 do
        local name = ("%s %d"):format(base, n)
        if not taken[name] then return name end
    end
    return base
end

local SLOT_FIELDS = { "g", "class", "spec", "role", "label", "pin" }

-- The layout of a setup, for comparing the loaded one with its saved self.
local function sameLayout(a, b)
    if not (a and b) or a.name ~= b.name or a.size ~= b.size or #a.slots ~= #b.slots then return false end
    for i, s in ipairs(a.slots) do
        for _, f in ipairs(SLOT_FIELDS) do
            if s[f] ~= b.slots[i][f] then return false end
        end
    end
    return true
end

function M:Changed()
    local w = self:Work()
    return not (w.id and sameLayout(w, self:Data().setups[w.id]))
end

function M:SlotById(id)
    for _, s in ipairs(self:Work().slots) do if s.id == id then return s end end
end

function M:SlotsIn(g)
    local out = {}
    for _, s in ipairs(self:Work().slots) do if s.g == g then out[#out + 1] = s end end
    return out
end

-- A copy as saved (no ids of the work's own).
local function saved(setup)
    local s = copy(setup)
    s.id = nil
    return s
end

function M:Load(id)
    local d = self:Data()
    local s = d.setups[id]
    if not s then return end
    local function load()
        d.work = copy(s)
        d.work.id = id
        d.size = s.size
        self:Refill(true)
    end
    if self:Changed() and #self:Work().slots > 0 and self:Work().id ~= id then
        UI.Confirm({ title = "Load " .. s.name .. "?", text = ("The changes to %s aren't saved."):format(self:Work().name),
            confirm = "Load", onConfirm = load })
    else
        load()
    end
end

function M:Save()
    local d = self:Data()
    local w = self:Work()
    if not w.id or not d.setups[w.id] then
        w.id = d.nextId
        d.nextId = d.nextId + 1
    end
    local s = saved(w)
    s.saved = time()
    d.setups[w.id] = s
    w.saved = s.saved
    self:Render()
end

function M:SaveAsNew()
    local w = self:Work()
    UI.Confirm({ title = "Save as new", text = "A new setup from this one, under its own name.", confirm = "Save",
        input = { label = "Name", value = self:UniqueName(w.name) },
        onConfirm = function(name)
            w.name = name
            w.id = nil
            self:Save()
        end })
end

function M:Duplicate(id)
    local d = self:Data()
    local src = (id and d.setups[id]) or self:Work()
    local s = saved(src)
    s.name = self:UniqueName(src.name .. " (copy)")
    s.saved = time()
    d.setups[d.nextId] = s
    d.nextId = d.nextId + 1
    self:Print(("%s saved as %s."):format(src.name, s.name))
    self:Render()
end

function M:Delete(id)
    local d = self:Data()
    local w = self:Work()
    id = id or w.id
    local s = id and d.setups[id]
    if not s then
        -- the unsaved one: start again
        if #w.slots == 0 then return end
        UI.Confirm({ title = "Discard " .. w.name .. "?", text = "It was never saved.", confirm = "Discard",
            onConfirm = function() d.work = nil; self:Refill(true) end })
        return
    end
    UI.Confirm({ title = "Delete " .. s.name .. "?", text = "The setup is gone for every character.", confirm = "Delete",
        onConfirm = function()
            d.setups[id] = nil
            -- the loaded one stays open, unsaved
            if w.id == id then w.id = nil end
            self:Render()
        end })
end

function M:Rename(id, name)
    if not name or name == "" then return self:Render() end
    local d = self:Data()
    local w = self:Work()
    if id == "work" or w.id == id then w.name = name end
    -- a saved setup takes its new name at once (not a change to save)
    if d.setups[id] then d.setups[id].name = name end
    self:Render()
end

-- A new setup: empty, or the raid as it is (each player a slot in their
-- group, asking for their class and spec; nobody pinned).
function M:New(fromRaid)
    local d = self:Data()
    local function make()
        local w = newSetup(self:UniqueName("New setup"), d.size)
        if fromRaid then
            -- big enough for everyone and for the highest group in use
            local need = #self.roster
            for _, m in ipairs(self.roster) do need = math.max(need, m.group * 5) end
            w.size = need > 20 and 40 or need > 10 and 20 or 10
            d.size = w.size
            for _, m in ipairs(self.roster) do
                if #self:SlotsInOf(w, m.group) < MAX_GROUP and m.group <= w.size / 5 then
                    w.slots[#w.slots + 1] = { id = w.nextSlot, g = m.group, class = m.class, spec = m.tree,
                        role = m.role or (m.tree and CLASS[m.class] and CLASS[m.class].roles[m.tree]) or nil }
                    w.nextSlot = w.nextSlot + 1
                end
            end
        end
        d.work = w
        self:Refill(true)
    end
    if self:Changed() and #self:Work().slots > 0 then
        UI.Confirm({ title = "A new setup?", text = ("The changes to %s aren't saved."):format(self:Work().name),
            confirm = "New setup", onConfirm = make })
    else
        make()
    end
end

function M:SlotsInOf(w, g)
    local out = {}
    for _, s in ipairs(w.slots) do if s.g == g then out[#out + 1] = s end end
    return out
end

--------------------------------------------------------------------------------
-- Sharing a setup as text: "SuuRaid1;name;size;g,class,spec,role,label,pin;…"
--------------------------------------------------------------------------------

local function esc(text) return (tostring(text or ""):gsub("[%%;,|]", function(ch) return ("%%%02X"):format(ch:byte()) end)) end
local function unesc(text) return (text:gsub("%%(%x%x)", function(h) return string.char(tonumber(h, 16)) end)) end

function M:ExportText(setup)
    local parts = { "SuuRaid1", esc(setup.name), tostring(setup.size) }
    for _, s in ipairs(setup.slots) do
        parts[#parts + 1] = table.concat({ s.g, s.class or "", s.spec or "", s.role or "", esc(s.label), esc(s.pin) }, ",")
    end
    return table.concat(parts, ";")
end

function M:ImportText(text)
    local fields = {}
    for f in (strtrim(text or "") .. ";"):gmatch("([^;]*);") do fields[#fields + 1] = f end
    if fields[1] ~= "SuuRaid1" then return nil, "That isn't a raid planner setup." end
    local size = tonumber(fields[3])
    if size ~= 40 and size ~= 20 and size ~= 10 then return nil, "The setup's raid size is wrong." end
    local w = newSetup(unesc(fields[2] or ""), size)
    if w.name == "" then w.name = "Imported setup" end
    local per = {}
    for i = 4, #fields do
        local g, class, spec, role, label, pin = strsplit(",", fields[i])
        g, spec = tonumber(g), tonumber(spec)
        if g and g >= 1 and g <= size / 5 and (per[g] or 0) < MAX_GROUP then
            per[g] = (per[g] or 0) + 1
            local s = { id = w.nextSlot, g = g }
            w.nextSlot = w.nextSlot + 1
            s.class = CLASS[class or ""] and class or nil
            s.spec = (s.class and spec and spec >= 1 and spec <= 3) and spec or nil
            s.role = ROLE_WORD[role or ""] and role or nil
            s.label = label and unesc(label) or nil
            if s.label == "" then s.label = nil end
            s.pin = pin and pin ~= "" and unesc(pin) or nil
            w.slots[#w.slots + 1] = s
        end
    end
    w.name = self:UniqueName(w.name)
    return w
end

function M:Export(id)
    local d = self:Data()
    local s = (id and d.setups[id]) or self:Work()
    local p = UI.Confirm({ title = "Export " .. s.name, text = "Copy the text (Ctrl+C) and share it; Import from text makes the same setup.",
        confirm = "Done", input = { label = "Setup as text", value = self:ExportText(s) } })
    if p and p.field and p.field.edit then p.field.edit:HighlightText() end
end

function M:Import()
    UI.Confirm({ title = "Import a setup", text = "Paste a setup's text (from Export as text).", confirm = "Import",
        input = { label = "Setup as text", placeholder = "SuuRaid1;…" },
        onConfirm = function(text)
            local w, why = self:ImportText(text)
            if not w then return self:Print(why) end
            local d = self:Data()
            local s = saved(w)
            s.saved = time()
            d.setups[d.nextId] = s
            d.nextId = d.nextId + 1
            self:Print(("Imported %s."):format(s.name))
            self:Load(d.nextId - 1)
        end })
end

--------------------------------------------------------------------------------
-- Slots
--------------------------------------------------------------------------------

function M:AddSlot(g, req, pin)
    local w = self:Work()
    if g > w.size / 5 or #self:SlotsIn(g) >= MAX_GROUP then return end
    w.nextSlot = w.nextSlot or (#w.slots + 1)
    local s = { id = w.nextSlot, g = g }
    w.nextSlot = w.nextSlot + 1
    if req then s.class, s.spec, s.role = req.class, req.spec, req.role end
    if pin then self:Unpin(pin); s.pin = pin end
    w.slots[#w.slots + 1] = s
    return s
end

function M:RemoveSlot(id)
    local w = self:Work()
    for i, s in ipairs(w.slots) do
        if s.id == id then table.remove(w.slots, i) break end
    end
end

-- Nobody else keeps `name` pinned.
function M:Unpin(name)
    local k = key(name)
    for _, s in ipairs(self:Work().slots) do
        if s.pin and key(s.pin) == k then s.pin = nil end
    end
end

-- The slot asks for a spec from the palette (or any of a class, or a role).
function M:SetRequirement(s, req)
    s.class, s.spec, s.role = req.class, req.spec, req.role
    if s.spec and not s.role and CLASS[s.class] then s.role = CLASS[s.class].roles[s.spec] end
    local m = s.pin and self.byKey[key(s.pin)]
    if m and s.class and m.class ~= s.class then s.pin = nil end
end

function M:ChangeSlot(id, changes)
    local s = self:SlotById(id)
    if not s then return end
    for k, v in pairs(changes) do
        if v == false then v = nil end
        if k == "class" then
            if v ~= s.class then s.spec = nil end
            s.class = v
        elseif k == "spec" then
            s.spec = v
            -- a spec brings its role (the healer of a Restoration shaman)
            if v and CLASS[s.class] then s.role = CLASS[s.class].roles[v] end
        elseif k == "pin" then
            if v then self:Unpin(v) end
            s.pin = v
        else
            s[k] = v
        end
    end
    if s.label == "" then s.label = nil end
    self:Refill()
end

-- What was dragged where (UI.RaidPlanner's onDrop).
function M:Drop(what, where)
    if what.spec then
        if where.slot then
            local s = self:SlotById(where.slot)
            if s then self:SetRequirement(s, what.spec) end
        elseif where.group then
            local s = self:AddSlot(where.group)
            if s then self:SetRequirement(s, what.spec) end
        end
    elseif what.player then
        local name = what.player
        local m = self.byKey[key(name)]
        if where.unplaced then
            self:Unpin(name)
            self.letGo = self.letGo or {}
            self.letGo[key(name)] = true
        elseif where.slot then
            local target = self:SlotById(where.slot)
            if not target then return end
            local from = what.from and self:SlotById(what.from)
            local there = self.fill and self.fill.slot[target.id]
            local displaced = (there and there.m.name) or target.pin
            self:Unpin(name)
            target.pin = name
            -- onto another player: the two swap
            if from and from ~= target and displaced and key(displaced) ~= key(name) then
                self:Unpin(displaced)
                from.pin = displaced
            end
        elseif where.group and m then
            local tree = m.tree
            self:AddSlot(where.group, { class = m.class, spec = tree, role = tree and CLASS[m.class] and CLASS[m.class].roles[tree] or nil }, name)
        end
        if self.letGo and not where.unplaced then self.letGo[key(name)] = nil end
    end
    self:Refill()
end

--------------------------------------------------------------------------------
-- The raid
--------------------------------------------------------------------------------

-- A player's tree (1-3), when known: yours from your talents, others' from
-- an inspect or their own SuuUI.
function M:KnownTree(name, you)
    if you then
        local tree = SuuUI.Spec()
        return tree and tree > 0 and tree or nil
    end
    local specs = self:Data().specs
    local e = specs[key(name)] or specs[Ambiguate(name, "short")]
    if e and e.tree and time() - (e.at or 0) < SPEC_FRESH then return e.tree end
end

-- Out of combat only (roster values may be secret in combat).
function M:ReadRoster()
    local out, byKey = {}, {}
    if InCombatLockdown() or not UI.Flag(IsInRaid()) then
        if not UI.Flag(IsInRaid()) then self.roster, self.byKey = out, byKey end
        return self.roster or out
    end
    for i = 1, GetNumGroupMembers() do
        local name, rank, group, _, _, file, _, online, _, _, _, combatRole = call(GetRaidRosterInfo, i)
        if plain(name) and name and plain(file) and file and plain(group) and group then
            local unit = "raid" .. i
            local role = plain(combatRole) and combatRole ~= "NONE" and combatRole ~= "" and combatRole or nil
            if not role then
                local r = call(UnitGroupRolesAssigned, unit)
                role = plain(r) and r ~= "NONE" and r or nil
            end
            local you = UI.Flag(UnitIsUnit(unit, "player"))
            local m = { index = i, unit = unit, name = name, key = key(name), class = file, group = group,
                online = plain(online) and online and true or false, you = you, role = role,
                lead = plain(rank) and rank == 2, assist = plain(rank) and rank == 1 }
            m.tree = self:KnownTree(name, you)
            out[#out + 1] = m
            byKey[m.key] = m
        end
    end
    self.roster, self.byKey = out, byKey
    return out
end

local function roleOf(m)
    if m.role then return m.role, "set" end
    local c = CLASS[m.class]
    if m.tree and c then return c.roles[m.tree], "spec" end
    return c and c.likely, "likely"
end

-- How a player fits a slot: "exact", "provisional" (their spec or role isn't
-- known yet, so it may not be them), or nil.
local function fit(s, m)
    if s.class and s.class ~= m.class then return nil end
    local sure = true
    if s.spec then
        if m.tree then
            if m.tree ~= s.spec then return nil end
        else
            sure = false
        end
    end
    if s.role then
        if m.role then
            if m.role ~= s.role then return nil end
        elseif m.tree then
            if not canPlay(m.class, m.tree, s.role) then return nil end
        else
            if not canPlay(m.class, nil, s.role) then return nil end
            sure = false
        end
    end
    return sure and "exact" or "provisional"
end

-- How picky a slot is: the pickiest fill first.
local function strictness(s)
    return (s.class and 4 or 0) + (s.spec and 2 or 0) + (s.role and 1 or 0)
end

-- Fills the slots from the raid: the pinned first, then the pickiest slots
-- with whoever fits best (sure over provisional, the class's likely role,
-- already in that slot or group, fitting the fewest other slots). With
-- `keepOnly` (review mode until Fill slots), only who was placed stays.
function M:RunFill(keepOnly)
    local w = self:Work()
    local roster = self.roster or {}
    local prev = self.fill and self.fill.placed or {}
    local fill = { slot = {}, placed = {}, conflict = {}, unplaced = {} }
    local used = {}
    -- pinned players in the raid take their slots
    for _, s in ipairs(w.slots) do
        local m = s.pin and self.byKey[key(s.pin)]
        if m and not used[m.key] then
            used[m.key] = true
            fill.slot[s.id] = { m = m, how = "pinned" }
            fill.placed[m.key] = s.id
        end
    end
    -- how many slots each player fits
    local options = {}
    for _, m in ipairs(roster) do
        local n = 0
        for _, s in ipairs(w.slots) do if not s.pin and fit(s, m) then n = n + 1 end end
        options[m.key] = n
    end
    local order = {}
    for i, s in ipairs(w.slots) do
        if not s.pin then order[#order + 1] = { s = s, i = i } end
    end
    table.sort(order, function(a, b)
        local x, y = strictness(a.s), strictness(b.s)
        if x ~= y then return x > y end
        return a.i < b.i
    end)
    local letGo = self.letGo or {}
    for _, o in ipairs(order) do
        local s = o.s
        local best, bestScore, bestHow
        for _, m in ipairs(roster) do
            local how = not used[m.key] and not letGo[m.key] and fit(s, m)
            if how and keepOnly and prev[m.key] ~= s.id then how = nil end
            if how then
                local score = (how == "exact" and 100 or 0) - options[m.key]
                if prev[m.key] == s.id then score = score + 20 end
                if m.group == s.g then score = score + 4 end
                if s.role and not m.role and not m.tree and CLASS[m.class] and CLASS[m.class].likely == s.role then score = score + 10 end
                if not best or score > bestScore then best, bestScore, bestHow = m, score, how end
            end
        end
        if best then
            used[best.key] = true
            fill.slot[s.id] = { m = best, how = bestHow }
            fill.placed[best.key] = s.id
        end
    end
    for _, m in ipairs(roster) do
        if not used[m.key] then fill.unplaced[#fill.unplaced + 1] = m end
    end
    -- two fit one slot: someone left over fits a slot as well as its player
    for _, s in ipairs(w.slots) do
        local f = fill.slot[s.id]
        if f and f.how ~= "pinned" then
            for _, m in ipairs(fill.unplaced) do
                local how = not letGo[m.key] and fit(s, m)
                if how and (how == "exact" or f.how == "provisional") then
                    fill.conflict[s.id] = m
                    break
                end
            end
        end
    end
    self.fill = fill
end

-- Fills again (out of combat) and draws. `force`: review mode's Fill slots.
function M:Refill(force)
    if InCombatLockdown() then
        self:RunOutOfCombat("fill", function() self:Refill(force) end)
        self:Render()
        return
    end
    self:NoteOwnTreeIcons()
    self:ReadRoster()
    local review = self:Get("fill") == "review"
    self:RunFill(review and not force and self.fill ~= nil)
    self:Render()
end

-- The roster changes in bursts: one fill once it settles.
function M:RefillSoon()
    if self.refillQueued then return end
    self.refillQueued = true
    C_Timer.After(0.5, function()
        self.refillQueued = nil
        if self:IsEnabled() then self:Refill() end
    end)
end

--------------------------------------------------------------------------------
-- Specs: inspecting, one player at a time
--------------------------------------------------------------------------------

-- The tree whose talent group has the most points spent, by its name (the
-- inspect config, as the Talents window reads it); else the spec ID's name.
local function treeByName(class, name)
    local c = CLASS[class]
    if not (c and plain(name) and type(name) == "string") then return nil end
    local n = name:lower()
    for t, spec in ipairs(c.specs) do
        local s = spec:lower()
        if s == n or s:find(n, 1, true) or n:find(s, 1, true) then return t end
    end
end

--------------------------------------------------------------------------------
-- Spec icons
--------------------------------------------------------------------------------

-- A tree's icon: the game's own (its talent group's in the class's trait
-- tree, seen in your talents or an inspect, kept for the account), else the
-- catalog's. Forever's spec IDs are one per class (probed: 1491 "Warrior",
-- with the class icon; an inspected druid's is 1484 whatever the tree), so
-- GetSpecializationInfoByID can't tell the trees apart.
function M:TreeIcon(class, tree)
    if not (class and tree) then return nil end
    local seen = self:Data().treeIcons[class]
    if seen and seen[tree] then return seen[tree] end
    local c = CLASS[class]
    return c and c.icons and c.icons[tree] or nil
end

local QUESTION_MARK = 134400

-- Keeps the icons of a class's talent groups (GetGroupDisplayInfoByTreeID).
function M:NoteTreeIcons(class, displays)
    if not CLASS[class] or type(displays) ~= "table" then return end
    local icons = self:Data().treeIcons
    for _, d in ipairs(displays) do
        local tree = type(d) == "table" and treeByName(class, d.displayName)
        local icon = tree and d.icon
        if plain(icon) and ((type(icon) == "number" and icon > 0 and icon ~= QUESTION_MARK) or (type(icon) == "string" and icon ~= "")) then
            icons[class] = icons[class] or {}
            icons[class][tree] = icon
        end
    end
end

-- Your own class's, from your talents (once they're there).
function M:NoteOwnTreeIcons()
    if self.ownIconsRead then return end
    local _, class = UnitClass("player")
    local traits = C_Traits or {}
    local cfg = C_ClassTalents and call(C_ClassTalents.GetActiveConfigID)
    if not plain(cfg) or not cfg then return end
    local info = call(traits.GetConfigInfo, cfg)
    local treeID = type(info) == "table" and info.treeIDs and info.treeIDs[1]
    if not (plain(treeID) and treeID) then return end
    local displays = call(traits.GetGroupDisplayInfoByTreeID, treeID)
    if type(displays) == "table" and #displays > 0 then
        self.ownIconsRead = true
        self:NoteTreeIcons(class, displays)
    end
end

function M:InspectedTree(unit, class)
    local best, bestSpent
    local traits = C_Traits or {}
    local info = call(traits.GetConfigInfo, INSPECT_CONFIG)
    local treeID = type(info) == "table" and info.treeIDs and info.treeIDs[1]
    if plain(treeID) and treeID then
        local ids, names = {}, {}
        local displays = call(traits.GetGroupDisplayInfoByTreeID, treeID)
        for i, d in ipairs(type(displays) == "table" and displays or {}) do
            ids[i] = d.groupID
            names[d.groupID] = d.displayName
        end
        self:NoteTreeIcons(class, displays)
        local groups = #ids > 0 and call(traits.GetGroupCurrencyInfo, INSPECT_CONFIG, ids)
        for _, g in ipairs(type(groups) == "table" and groups or {}) do
            local c = g.currencyInfos and g.currencyInfos[1]
            local spent = c and c.spent
            if plain(spent) and type(spent) == "number" and spent > (bestSpent or 0) then
                best, bestSpent = names[g.traitNodeGroupID], spent
            end
        end
    end
    local tree = treeByName(class, best)
    if tree then return tree end
    local getSpec = (C_SpecializationInfo and C_SpecializationInfo.GetInspectSpecialization) or GetInspectSpecialization
    local id = call(getSpec, unit)
    if plain(id) and type(id) == "number" and id > 0 then
        local _, name = call(GetSpecializationInfoByID, id)
        return treeByName(class, name)
    end
end

function M:NoteSpec(name, tree, from)
    if not (name and tree and tree >= 1 and tree <= 3) then return end
    local specs = self:Data().specs
    local e = { tree = tree, at = time(), from = from }
    specs[key(name)] = e
    local short = Ambiguate(name, "short")
    if short ~= key(name) then specs[short] = e end
end

-- Who still lacks a spec: in the raid, online, not you, not failed lately.
function M:SpecQueue()
    local out = {}
    self.inspectFailed = self.inspectFailed or {}
    for _, m in ipairs(self.roster or {}) do
        local failed = self.inspectFailed[m.key]
        if not m.tree and not m.you and m.online and not (failed and GetTime() - failed < 60) then out[#out + 1] = m end
    end
    return out
end

function M:UnknownSpecs()
    local n = 0
    for _, m in ipairs(self.roster or {}) do if not m.tree and m.online then n = n + 1 end end
    return n
end

-- Inspects the next player in the queue (while asked to: automatically with
-- the planner open, or the Inspect button's round).
function M:InspectNext()
    if self.inspecting or InCombatLockdown() or not UI.Flag(IsInRaid()) then return end
    local auto = self:Get("inspect") == "auto" and self.window and self.window:IsShown()
    if not (auto or self.inspectRound) then return end
    -- never over the player's own inspect
    if _G.InspectFrame and _G.InspectFrame:IsShown() then
        C_Timer.After(5, function() if self:IsEnabled() then self:InspectNext() end end)
        return
    end
    local target
    for _, m in ipairs(self:SpecQueue()) do
        if UI.Flag(call(CanInspect, m.unit)) and key(call(GetUnitName, m.unit, true)) == m.key then target = m break end
        self.inspectFailed[m.key] = GetTime()
    end
    if not target then
        self.inspectRound = nil
        self:Render()
        -- those out of reach: tried again in a while, while the planner is open
        if auto and #self:SpecQueue() < self:UnknownSpecs() and not self.retryQueued then
            self.retryQueued = true
            C_Timer.After(30, function()
                self.retryQueued = nil
                if self:IsEnabled() then self:InspectNext() end
            end)
        end
        return
    end
    local guid = call(UnitGUID, target.unit)
    if not plain(guid) then self.inspectFailed[target.key] = GetTime(); return self:InspectNext() end
    local job = { m = target, guid = guid }
    self.inspecting = job
    call(NotifyInspect, target.unit)
    C_Timer.After(5, function()
        if self.inspecting ~= job then return end
        self.inspecting = nil
        self.inspectFailed[target.key] = GetTime()
        if self:IsEnabled() then self:InspectNext() end
    end)
end

function M:OnInspectReady(guid)
    local job = self.inspecting
    if not (job and plain(guid) and guid == job.guid) then return end
    self.inspecting = nil
    local tree = self:InspectedTree(job.m.unit, job.m.class)
    if tree then
        self:NoteSpec(job.m.name, tree, "inspect")
    else
        self.inspectFailed[job.m.key] = GetTime()
    end
    -- the game's own inspect keeps its player; this one is let go
    if not (_G.InspectFrame and _G.InspectFrame:IsShown()) then call(ClearInspectPlayer) end
    self:RefillSoon()
    -- slowly, so the game allows it
    C_Timer.After(1.5, function() if self:IsEnabled() then self:InspectNext() end end)
end

--------------------------------------------------------------------------------
-- Specs from raid members' own SuuUI
--------------------------------------------------------------------------------

local function chatRestricted()
    local f = C_ChatInfo and (C_ChatInfo.AreOutgoingAddonChatMessagesRestricted or C_ChatInfo.InChatMessagingLockdown)
    if not f then return false end
    local r = call(f)
    if isSecret(r) then return true end
    return r and true or false
end

function M:Send(text)
    if InCombatLockdown() or not UI.Flag(IsInRaid()) or chatRestricted() then return end
    call(C_ChatInfo.SendAddonMessage, PREFIX, text, "RAID")
end

function M:ShareSpec()
    if not self:Get("shareSpec") then return end
    local tree = SuuUI.Spec()
    if tree and tree > 0 then self:Send("RPSPEC\t" .. tree) end
end

function M:ShareSoon(delay)
    if self.shareQueued then return end
    self.shareQueued = true
    C_Timer.After(delay or 2, function()
        self.shareQueued = nil
        if self:IsEnabled() then self:ShareSpec() end
    end)
end

-- Asks everyone's SuuUI for their spec, at most twice a minute.
function M:AskSpecs()
    if self:UnknownSpecs() == 0 then return end
    if self.askedAt and GetTime() - self.askedAt < 30 then return end
    self.askedAt = GetTime()
    self:Send("RPSPECQ")
end

function M:OnMessage(prefix, text, _, sender)
    if prefix ~= PREFIX or not plain(text) or type(text) ~= "string" then return end
    if not plain(sender) or type(sender) ~= "string" then return end
    if text == "RPSPECQ" then
        if key(sender) ~= key(SuuUI.FullName("player")) then self:ShareSoon() end
        return
    end
    local tree = tonumber(text:match("^RPSPEC\t(%d)$") or "")
    if not tree then return end
    self:NoteSpec(sender, tree, "message")
    self:RefillSoon()
end

--------------------------------------------------------------------------------
-- Coverage
--------------------------------------------------------------------------------

-- Whether someone (a player, or what a slot asks for) brings an item:
-- "yes", "maybe" (their spec isn't known) or nil.
local function provides(item, p)
    local maybe = false
    for _, b in ipairs(item.by) do
        if b[1] == p.class then
            if not b[2] then return "yes" end
            if p.tree then
                if p.tree == b[2] then return "yes" end
            else
                maybe = true
            end
        end
    end
    return maybe and "maybe" or nil
end

local function isMelee(p)
    local c = CLASS[p.class]
    if not c then return false end
    if p.tree then return c.melee[p.tree] and true or false end
    return c.melee[1] and c.melee[2] and c.melee[3] and true or false
end

local function uses(item, p)
    if item.users == "melee" then return isMelee(p) end
    if item.users == "hunter" then return p.class == "HUNTER" end
    if item.users == "healer" then return (roleOf(p)) == "HEALER" end
    return false
end

local function shortSpec(class, tree)
    local c = CLASS[class]
    return c and tree and c.short[tree] or nil
end

-- The people coverage counts: everyone in the raid; out of a raid, what
-- the slots ask for (a plan to look at). And the open slots.
function M:People()
    local people, open = {}, {}
    local w = self:Work()
    local inRaid = #(self.roster or {}) > 0
    for _, s in ipairs(w.slots) do
        local f = self.fill and self.fill.slot[s.id]
        if f then
            people[#people + 1] = { name = f.m.name, class = f.m.class, tree = f.m.tree, role = f.m.role, g = s.g }
        elseif s.class then
            local p = { class = s.class, tree = s.spec, role = s.role, g = s.g, slot = s }
            if inRaid then open[#open + 1] = p else people[#people + 1] = p end
        end
    end
    if inRaid then
        for _, m in ipairs(self.fill and self.fill.unplaced or {}) do
            people[#people + 1] = { name = m.name, class = m.class, tree = m.tree, role = m.role }
        end
    end
    return people, open, inRaid
end

local function names(list, max)
    local out = {}
    for i, p in ipairs(list) do
        if i > (max or 3) then out[#out] = ("%d more"):format(#list - (max or 3) + 1) break end
        local spec = shortSpec(p.class, p.tree)
        out[#out + 1] = (p.name or plural(p.class)) .. (spec and (" (" .. spec .. ")") or "")
    end
    return joinAnd(out)
end

local function classesOf(item, list, word)
    local seen, out = {}, {}
    for _, p in ipairs(list) do
        if not seen[p.class] then seen[p.class] = true; out[#out + 1] = plural(p.class) end
    end
    if #out == 0 then
        for _, b in ipairs(item.by) do
            if not seen[b[1]] then seen[b[1]] = true; out[#out + 1] = plural(b[1]) end
        end
    end
    return joinAnd(out, word)
end

-- One raid-wide item: { n, warn, detail, lines }.
function M:RaidItem(item, people, open)
    local yes, maybe, slots = {}, {}, {}
    for _, p in ipairs(people) do
        local how = provides(item, p)
        if how == "yes" then yes[#yes + 1] = p elseif how == "maybe" then maybe[#maybe + 1] = p end
    end
    for _, p in ipairs(open) do if provides(item, p) then slots[#slots + 1] = p end end
    local talent = item.by[1] and item.by[1].talent
    local r = { lines = {} }
    if item.ask then
        r.n, r.detail = "ask", "from books, not trainers: ask your " .. classesOf(item, yes)
        return r
    end
    if item.count == "blessings" then
        r.n = ("%d of %d"):format(math.min(#yes, BLESSINGS), BLESSINGS)
        r.warn = #yes == 0 or (#yes < BLESSINGS and #slots > 0)
    else
        r.n = #yes
        r.warn = #yes == 0
    end
    local bits = {}
    if #yes == 0 then
        if #maybe > 0 then
            bits[1] = "if specced: " .. names(maybe)
        elseif #slots > 0 then
            bits[1] = "needs the open " .. (CLASS[slots[1].class] and CLASS[slots[1].class].name:lower() or "") .. " slot"
        else
            bits[1] = "none: no " .. classesOf(item, {}, "or")
        end
    else
        bits[1] = item.detail or (talent and names(yes) or classesOf(item, yes))
        if #maybe > 0 then bits[#bits + 1] = ("+%d if specced"):format(#maybe) end
        if #slots > 0 then bits[#bits + 1] = ("+%d in open slots"):format(#slots) end
    end
    r.detail = table.concat(bits, " · ")
    for _, p in ipairs(yes) do r.lines[#r.lines + 1] = { p.name or "a slot", CLASS[p.class] and CLASS[p.class].name or "" } end
    return r
end

-- The raid-wide rows: tracked items, those sharing a line in one row.
function M:RaidWide(people, open)
    local rows, byLine = {}, {}
    for _, item in ipairs(ITEMS) do
        local fam = familyOf(item.family)
        if fam and fam.scope == "raid" and self:IsTracked(item.key) then
            local r = self:RaidItem(item, people, open)
            local row = item.line and byLine[item.line]
            if row then
                row.items[#row.items + 1] = item
                row.parts[#row.parts + 1] = r
            else
                row = { items = { item }, parts = { r } }
                rows[#rows + 1] = row
                if item.line then byLine[item.line] = row end
            end
        end
    end
    local out = {}
    for _, row in ipairs(rows) do
        local labels, ns, details, warn, lines = {}, {}, {}, false, {}
        local single = #row.items == 1
        for i, item in ipairs(row.items) do
            local r = row.parts[i]
            labels[i] = single and item.label or item.short
            ns[i] = tostring(r.n)
            if r.detail and r.detail ~= "" then
                local d = single and r.detail or (item.short .. ": " .. r.detail)
                details[#details + 1] = d
            end
            warn = warn or r.warn
            lines[#lines + 1] = { item.label, tostring(r.n) }
        end
        -- one count when they all say the same (Fortitude and Spirit: every priest)
        local sameN = true
        for i = 2, #ns do if ns[i] ~= ns[1] then sameN = false end end
        local sameDetail = #row.parts > 1
        for i = 2, #row.parts do if row.parts[i].detail ~= row.parts[1].detail then sameDetail = false end end
        out[#out + 1] = {
            label = table.concat(labels, " · "),
            n = sameN and ns[1] or table.concat(ns, " · "),
            detail = sameDetail and row.parts[1].detail or table.concat(details, "; "),
            warn = warn,
            tip = { description = table.concat(details, "\n"), lines = lines },
        }
    end
    return out
end

-- A group's party-wide chips.
function M:PartyChips(g, people, open)
    local chips = {}
    local flag = self:Get("flagDoubled")
    local here, slots = {}, {}
    for _, p in ipairs(people) do if p.g == g then here[#here + 1] = p end end
    for _, p in ipairs(open) do if p.g == g then slots[#slots + 1] = p end end
    if #here == 0 and #slots == 0 then return chips end
    for _, item in ipairs(ITEMS) do
        if item.family == "party" and self:IsTracked(item.key) then
            local yes, maybe, users, slot = {}, {}, 0, nil
            for _, p in ipairs(here) do
                local how = provides(item, p)
                if how == "yes" then yes[#yes + 1] = p elseif how == "maybe" then maybe[#maybe + 1] = p end
                if uses(item, p) then users = users + 1 end
            end
            for _, p in ipairs(slots) do if not slot and provides(item, p) then slot = p end end
            if #yes >= 2 and item.single and flag then
                chips[#chips + 1] = { text = item.short .. " ×" .. #yes .. ": one wasted", tone = "warn", tip = names(yes) .. ": one is enough in a group." }
            elseif #yes >= 1 then
                chips[#chips + 1] = { text = item.short, tone = "ok", tip = names(yes) }
            elseif #maybe >= 1 then
                chips[#chips + 1] = { text = item.short .. "?", tone = "ok", tip = "If specced: " .. names(maybe) }
            elseif slot then
                chips[#chips + 1] = { text = item.short .. ": slot open", tone = "open", tip = "Its slot is open: " .. (CLASS[slot.class] and CLASS[slot.class].name or "") }
            elseif users > 0 then
                chips[#chips + 1] = { text = "No " .. item.short, tone = "warn",
                    tip = ("%d in this group use it; no %s here."):format(users, classesOf(item, {}, "or")) }
            end
        end
    end
    return chips
end

--------------------------------------------------------------------------------
-- What the window shows
--------------------------------------------------------------------------------

local function reqText(s)
    local parts = {}
    local c = s.class and CLASS[s.class]
    if c then
        parts[1] = c.name
        if s.spec then parts[2] = c.specs[s.spec] elseif s.role then parts[2] = ROLE_NAME[s.role] end
    else
        parts[1] = s.role and ("Any " .. ROLE_WORD[s.role]) or "Any"
    end
    if s.label and s.label ~= "" then parts[#parts + 1] = s.label end
    return table.concat(parts, " · ")
end

local function ago(t)
    if not t then return "" end
    local s = math.max(0, time() - t)
    if s < 120 then return "just now" end
    if s < 3600 then return math.floor(s / 60) .. "m ago" end
    if s < 86400 then return math.floor(s / 3600) .. "h ago" end
    if s < 14 * 86400 then return math.floor(s / 86400) .. "d ago" end
    return math.floor(s / (7 * 86400)) .. "w ago"
end

-- What a setup asks for: "2 tanks · 10 healers".
local function summary(setup)
    local tanks, healers = 0, 0
    for _, s in ipairs(setup.slots or {}) do
        local role = s.role or (s.spec and CLASS[s.class] and CLASS[s.class].roles[s.spec])
        if role == "TANK" then tanks = tanks + 1 elseif role == "HEALER" then healers = healers + 1 end
    end
    return ("%d slots · %d tank%s · %d healer%s"):format(#(setup.slots or {}), tanks, tanks == 1 and "" or "s", healers, healers == 1 and "" or "s")
end

-- A group's caption from what its slots ask for.
local function groupKind(slots)
    if #slots == 0 then return "" end
    local count, any = {}, 0
    for _, s in ipairs(slots) do
        local c = s.class and CLASS[s.class]
        local role = s.role or (s.spec and c and c.roles[s.spec])
        local kind
        if role == "TANK" then kind = "tanks"
        elseif role == "HEALER" then kind = "healers"
        elseif s.class == "HUNTER" then kind = "hunters"
        elseif c and ((s.spec and c.melee[s.spec]) or (not s.spec and c.melee[1] and c.melee[2])) then kind = "melee"
        elseif c then kind = "casters"
        else any = any + 1 end
        if kind then count[kind] = (count[kind] or 0) + 1 end
    end
    if count.tanks then return "tanks" end
    local best, n = nil, 0
    for k, v in pairs(count) do if v > n then best, n = k, v end end
    if best and n >= 3 then return best end
    return any >= 3 and "flex" or "mixed"
end

function M:CanArrange()
    if not UI.Flag(IsInRaid()) then return false, "Not in a raid." end
    if not (UI.Flag(UnitIsGroupLeader("player")) or UI.Flag(UnitIsGroupAssistant("player"))) then
        return false, "Only the raid leader or an assistant can move players."
    end
    if InCombatLockdown() then return false, "Not in combat." end
    if #self:Moves() == 0 then return false, "Everyone is in their slot's group already." end
    return true
end

-- Who goes from which group to which: everyone placed in a slot of another group.
function M:Moves()
    local out = {}
    if not self.fill then return out end
    for _, s in ipairs(self:Work().slots) do
        local f = self.fill.slot[s.id]
        if f and f.m.group ~= s.g then
            out[#out + 1] = { name = f.m.name, class = f.m.class, icon = self:TreeIcon(f.m.class, f.m.tree), known = f.m.tree ~= nil,
                from = f.m.group, to = s.g, m = f.m }
        end
    end
    return out
end

function M:ViewData()
    local d = self:Data()
    local w = self:Work()
    local fill = self.fill or { slot = {}, conflict = {}, unplaced = {}, placed = {} }
    local roster = self.roster or {}
    local inRaid = #roster > 0
    local changed = self:Changed()
    local people, open = self:People()
    local v = {}

    v.meta = w.name .. (not w.id and " · not saved" or (changed and " · changed" or ""))
    v.size = d.size

    -- setups of the chosen size, the loaded one marked
    local list = {}
    if not w.id and w.size == d.size then
        list[1] = { id = "work", name = w.name, meta = "loaded · not saved", loaded = true, changed = true }
    end
    local stored = {}
    for id, s in pairs(d.setups) do
        if s.size == d.size then stored[#stored + 1] = { id = id, s = s } end
    end
    table.sort(stored, function(a, b) return a.s.name:lower() < b.s.name:lower() end)
    for _, e in ipairs(stored) do
        local loaded = w.id == e.id
        local meta = loaded and ("loaded" .. (changed and " · changed" or "") .. " · saved " .. ago(e.s.saved))
            or (summary(e.s) .. " · " .. ago(e.s.saved))
        list[#list + 1] = { id = e.id, name = loaded and w.name or e.s.name, meta = meta, loaded = loaded, changed = loaded and changed }
    end
    v.setups = list

    -- the palette
    v.palette = {}
    for _, c in ipairs(CLASSES) do
        local specs = {}
        for t = 1, 3 do specs[t] = { spec = t, label = c.short[t], name = c.specs[t], role = c.roles[t], icon = self:TreeIcon(c.file, t) } end
        v.palette[#v.palette + 1] = { class = c.file, name = c.name, specs = specs }
    end

    -- the groups and their slots
    local nOpen, nConflict = 0, 0
    local openList = {}
    v.groups = {}
    for g = 1, w.size / 5 do
        local slots = self:SlotsIn(g)
        local cards = {}
        for i, s in ipairs(slots) do
            local f = fill.slot[s.id]
            local req = reqText(s)
            -- open or away: the icon of what the slot asks for (drawn dimmed)
            local card = { id = s.id, req = req, icon = self:TreeIcon(s.class, s.spec), iconClass = s.class }
            if f then
                local m = f.m
                card.who, card.class, card.player = m.name, m.class, m.name
                card.spec = shortSpec(m.class, m.tree) or "?"
                -- their spec's icon; their class's while the spec isn't known
                card.icon, card.iconClass = self:TreeIcon(m.class, m.tree), m.class
                card.pinned = f.how == "pinned"
                card.state = f.how == "provisional" and "provisional" or "filled"
                if card.pinned then card.req = "Pinned · " .. req end
                local tips = {}
                if not m.tree then tips[#tips + 1] = "Spec not known yet: filled provisionally until inspected." end
                if card.pinned then tips[#tips + 1] = "Placed by hand: stays here until you move them." end
                local role, from = roleOf(m)
                if s.role and from == "likely" then tips[#tips + 1] = ("Role: likely %s (the class's usual role)."):format(ROLE_WORD[role] or "?") end
                local other = fill.conflict[s.id]
                if other then
                    card.state = "conflict"
                    card.req = req .. " · 2 fit: " .. m.name .. ", " .. other.name
                    tips[#tips + 1] = ("%s fits too: drag them here to swap."):format(other.name)
                    nConflict = nConflict + 1
                end
                card.tip = table.concat(tips, " ")
            elseif s.pin then
                card.who, card.state, card.pinned = s.pin, "away", true
                card.req = "Pinned · not in the raid · " .. req
                card.tip = s.pin .. " is pinned here but isn't in the raid."
                nOpen = nOpen + 1
                openList[#openList + 1] = { label = ("Group %d · %s"):format(g, req), detail = s.pin .. " (pinned) isn't in the raid" }
            else
                card.state = "open"
                card.tip = inRaid and "Nobody in the raid fits: " .. req or "Fills with the raid."
                if inRaid then
                    nOpen = nOpen + 1
                    local brings = {}
                    for _, item in ipairs(ITEMS) do
                        if self:IsTracked(item.key) and s.class and provides(item, { class = s.class, tree = s.spec }) == "yes" then
                            brings[#brings + 1] = item.short
                        end
                    end
                    openList[#openList + 1] = { label = ("Group %d · %s"):format(g, req),
                        detail = #brings > 0 and table.concat(brings, ", ", 1, math.min(#brings, 4)) or "nobody in the raid fits" }
                end
            end
            cards[i] = card
        end
        v.groups[g] = { n = g, kind = groupKind(slots), slots = cards, canAdd = #slots < MAX_GROUP,
            chips = self:PartyChips(g, people, open) }
    end
    v.open = openList

    -- players without a slot, and why
    v.unplaced = {}
    for _, m in ipairs(fill.unplaced or {}) do
        local c = CLASS[m.class]
        local spec = m.tree and c and c.specs[m.tree] or "spec ?"
        local why
        for _, s in ipairs(w.slots) do
            local other = fill.conflict[s.id] == m and fill.slot[s.id]
            if other then why = ("fits group %d's \"%s\" with %s: drag to swap"):format(s.g, reqText(s), other.m.name) break end
        end
        if not why then
            if self.letGo and self.letGo[m.key] then
                why = "let go by hand: drag onto a slot"
            else
                local asks = 0
                for _, s in ipairs(w.slots) do if s.class == m.class then asks = asks + 1 end end
                why = asks > 0 and ("the %d %s slot%s %s full: drag onto a slot or add one"):format(asks, c and c.name:lower() or "", asks == 1 and "" or "s", asks == 1 and "is" or "are")
                    or ("no slot asks for a %s: drag onto a slot or add one"):format(c and c.name:lower() or "player")
            end
        end
        v.unplaced[#v.unplaced + 1] = { name = m.name, class = m.class, icon = self:TreeIcon(m.class, m.tree), known = m.tree ~= nil,
            detail = (c and c.name or "") .. " · " .. spec .. " · " .. why }
    end

    -- coverage
    v.raidWide = self:RaidWide(people, open)
    v.raidWideMeta = inRaid and "tracked only" or "from the slots"
    v.raidWideEmpty = "Nothing raid-wide is tracked (Settings › Raid planner)."

    -- the status line
    local tracked = self:TrackedCount()
    if inRaid then
        local placed = 0
        for _ in pairs(fill.placed or {}) do placed = placed + 1 end
        local unknown = self:UnknownSpecs()
        v.stats = {
            { n = #roster, label = "in raid" },
            { n = placed, label = "placed" },
            { n = unknown, label = self.inspecting and "spec ? (inspecting)" or "spec ? (inspect pending)" },
            { n = nOpen, label = "open slots", warn = nOpen > 0 },
            { n = nConflict, label = "two fit one slot", warn = nConflict > 0 },
            { n = #(fill.unplaced or {}), label = "without a slot" },
        }
    else
        v.stats = { { n = #w.slots, label = "slots" }, { n = 0, label = "in raid" } }
    end
    local how = self:Get("fill") == "review" and "Fills when you click Fill slots" or "Fills as the raid changes"
    if InCombatLockdown() then how = "In combat: fills when it ends" end
    if not inRaid then how = "Not in a raid: coverage from what the slots ask for" end
    v.note = ("%s · %d tracked"):format(how, tracked)

    v.hint = "Click a slot to edit it; right-click for actions. Drag a spec onto a slot, a player onto another to swap."
    local canArrange, why = self:CanArrange()
    v.arrange = { enabled = canArrange, reason = why }
    local unknown = inRaid and #self:SpecQueue() or 0
    local inspectWhy
    if InCombatLockdown() then inspectWhy = "Not in combat." elseif self.inspecting or self.inspectRound then inspectWhy = "Inspecting, one player at a time." end
    v.inspect = { shown = unknown > 0, label = ("Inspect the %d"):format(unknown), enabled = inspectWhy == nil, reason = inspectWhy }
    v.fill = { shown = self:Get("fill") == "review" and inRaid, enabled = not InCombatLockdown(), reason = "Not in combat." }
    return v
end

function M:Render()
    if not (self.window and self.window:IsShown()) then return end
    self.trackCache = self:TrackedSet()
    local v = self:ViewData()
    self.trackCache = nil
    self.window:SetData(v)
    local editing = self.window:EditingSlot()
    if editing then
        if self:SlotById(editing) then self:OpenEditor(editing) else self.window:CloseEditor() end
    end
end

--------------------------------------------------------------------------------
-- The slot editor and the menus
--------------------------------------------------------------------------------

function M:OpenEditor(id, card)
    local s = self:SlotById(id)
    if not s then return end
    local classes = { { value = "any", label = "Any class" } }
    for _, c in ipairs(CLASSES) do classes[#classes + 1] = { value = c.file, label = c.name } end
    local specs = { { value = "any", label = "Any" } }
    local c = s.class and CLASS[s.class]
    if c then for t = 1, 3 do specs[#specs + 1] = { value = t, label = c.short[t] } end end
    local who = { { value = "any", label = "Anyone who fits" } }
    local listed = {}
    local people = {}
    for _, m in ipairs(self.roster or {}) do
        if not s.class or m.class == s.class then people[#people + 1] = m end
    end
    if #people > 0 then
        who[#who + 1] = { heading = s.class and ("Pin a %s in the raid"):format(c.name:lower()) or "Pin a player in the raid" }
        for _, m in ipairs(people) do
            who[#who + 1] = { value = m.name, label = m.name }
            listed[m.key] = true
        end
    end
    if s.pin and not listed[key(s.pin)] then who[#who + 1] = { value = s.pin, label = s.pin .. " (not in the raid)" } end
    local slots = self:SlotsIn(s.g)
    local pos = 1
    for i, x in ipairs(slots) do if x == s then pos = i end end
    self.window:EditSlot({ id = id, title = "Slot · group " .. s.g, meta = ("%d of %d"):format(pos, #slots),
        class = s.class, spec = s.spec, role = s.role, label = s.label, who = s.pin, classes = classes, specs = specs,
        whoOptions = who }, card)
end

local function whisper(name)
    local tell = (ChatFrameUtil and ChatFrameUtil.SendTell) or ChatFrame_SendTell
    if tell then tell(name) end
end

function M:SlotMenu(id, owner)
    local s = self:SlotById(id)
    if not s then return end
    local f = self.fill and self.fill.slot[id]
    local name = (f and f.m.name) or s.pin
    UI.ContextMenuFrom(owner, function(_, root)
        root:CreateTitle(name or reqText(s))
        root:CreateButton("Edit slot", function() self:OpenEditor(id, owner) end)
        if f then
            root:CreateButton("Whisper", function() whisper(f.m.name) end)
            if f.how == "pinned" then
                root:CreateButton("Unpin", function() s.pin = nil; self:Refill() end)
            else
                root:CreateButton("Pin " .. f.m.name, function() self:Unpin(f.m.name); s.pin = f.m.name; self:Refill() end)
            end
        elseif s.pin then
            root:CreateButton("Invite " .. s.pin, function()
                local invite = (C_PartyInfo and C_PartyInfo.InviteUnit) or InviteUnit
                if invite then call(invite, s.pin) end
            end)
            root:CreateButton("Whisper", function() whisper(s.pin) end)
            root:CreateButton("Unpin", function() s.pin = nil; self:Refill() end)
        end
        root:CreateDivider()
        root:CreateButton("Clear (any player)", function()
            s.class, s.spec, s.role, s.label, s.pin = nil, nil, nil, nil, nil
            self:Refill()
        end)
        root:CreateButton("Remove slot", function() self:RemoveSlot(id); self:Refill() end)
    end, "raidPlannerSlot", { slot = id, player = name })
end

function M:SetupMenu(id, owner)
    local d = self:Data()
    local w = self:Work()
    local s = id == "work" and w or d.setups[id]
    if not s then return end
    local loaded = id == "work" or w.id == id
    UI.ContextMenuFrom(owner, function(_, root)
        root:CreateTitle(s.name)
        if not loaded then root:CreateButton("Load", function() self:Load(id) end) end
        if loaded then root:CreateButton("Save", function() self:Save() end) end
        root:CreateButton("Save as new…", function()
            if not loaded then self:Load(id) end
            self:SaveAsNew()
        end)
        root:CreateDivider()
        root:CreateButton("Rename", function() self.window:Rename(id) end)
        if id ~= "work" then root:CreateButton("Duplicate", function() self:Duplicate(id) end) end
        root:CreateButton("Export as text", function() self:Export(id ~= "work" and id or nil) end)
        root:CreateDivider()
        root:CreateButton(id == "work" and "Discard…" or "Delete…", function() self:Delete(id ~= "work" and id or nil) end)
    end, "raidPlannerSetup", { setup = id })
end

function M:NewMenu(owner)
    UI.ContextMenuFrom(owner, function(_, root)
        root:CreateTitle("New setup")
        root:CreateButton(("Empty (%d players)"):format(self:Data().size), function() self:New(false) end)
        root:CreateButton("From the raid as it is", function() self:New(true) end):SetEnabled(#(self.roster or {}) > 0)
        root:CreateDivider()
        root:CreateButton("Import from text…", function() self:Import() end)
    end, "raidPlannerNew")
end

function M:PersonMenu(name, owner)
    local m = self.byKey[key(name)]
    UI.ContextMenuFrom(owner, function(_, root)
        root:CreateTitle(name)
        root:CreateButton("Whisper", function() whisper(name) end)
        if m then
            root:CreateButton("Add a slot for them", function()
                local w = self:Work()
                -- their own group if it has room, else the first that has
                local g = (m.group <= w.size / 5 and #self:SlotsIn(m.group) < MAX_GROUP) and m.group or nil
                for x = 1, w.size / 5 do if not g and #self:SlotsIn(x) < MAX_GROUP then g = x end end
                if not g then return self:Print("Every group has five slots.") end
                local tree = m.tree
                self:AddSlot(g, { class = m.class, spec = tree, role = tree and CLASS[m.class].roles[tree] or nil }, m.name)
                if self.letGo then self.letGo[m.key] = nil end
                self:Refill()
            end)
        end
    end, "raidPlannerPlayer", { player = name })
end

--------------------------------------------------------------------------------
-- Arrange groups
--------------------------------------------------------------------------------

function M:Arrange()
    local ok, why = self:CanArrange()
    if not ok then return self:Print(why) end
    self.window:ShowMoves({ moves = self:Moves(),
        note = "Open slots stay open; a player without a slot moves only when a full group needs their place. You lead; out of combat. The raid sees the moves." },
        function() self:RunMoves(1) end)
end

-- One round of moves: into a group with room, a set; into a full one, a swap
-- with someone there who doesn't belong (whose own group is best). Then,
-- once the raid has caught up, another round for what's left (a few at most).
function M:RunMoves(round)
    if InCombatLockdown() or round > 4 then return end
    local ok = self:CanArrange()
    if not ok then return end
    self:ReadRoster()
    local roster = self.roster
    local count, target = {}, {}
    for _, m in ipairs(roster) do count[m.group] = (count[m.group] or 0) + 1 end
    for _, s in ipairs(self:Work().slots) do
        local f = self.fill.slot[s.id]
        if f then target[f.m.key] = s.g end
    end
    local plan, done = {}, {}
    for _, m in ipairs(roster) do
        local to = target[m.key]
        if to and to ~= m.group and not done[m.key] then
            if (count[to] or 0) < MAX_GROUP then
                plan[#plan + 1] = { set = true, a = m.index, g = to }
                count[m.group] = count[m.group] - 1
                count[to] = (count[to] or 0) + 1
                m.group = to
            else
                local swap
                for _, x in ipairs(roster) do
                    if x.group == to and not done[x.key] and target[x.key] ~= to then
                        if target[x.key] == m.group then swap = x break end
                        swap = swap or x
                    end
                end
                if swap then
                    plan[#plan + 1] = { a = m.index, b = swap.index }
                    swap.group, m.group = m.group, to
                    done[swap.key] = target[swap.key] == swap.group
                end
            end
            done[m.key] = true
        end
    end
    if #plan == 0 then return end
    for i, p in ipairs(plan) do
        C_Timer.After((i - 1) * 0.1, function()
            if InCombatLockdown() then return end
            if p.set then call(SetRaidSubgroup, p.a, p.g) else call(SwapRaidSubgroup, p.a, p.b) end
        end)
    end
    -- the roster update comes 0.4-0.7 s after a move (probed)
    C_Timer.After(#plan * 0.1 + 1.5, function()
        if not self:IsEnabled() then return end
        self:Refill()
        if #self:Moves() > 0 then self:RunMoves(round + 1) end
    end)
end

--------------------------------------------------------------------------------
-- The window
--------------------------------------------------------------------------------

function M:Build()
    local w = UI.RaidPlanner(SuuUI.Root)
    self.window = w
    w.onSize = function(size) self:Data().size = size; self:Render() end
    -- the loaded one's row does nothing (a load would drop its changes)
    w.onSetup = function(id) if id ~= "work" and id ~= self:Work().id then self:Load(id) end end
    w.onSetupMenu = function(id, owner) self:SetupMenu(id, owner) end
    w.onNew = function(owner) self:NewMenu(owner) end
    w.onRename = function(id, text) self:Rename(id, text) end
    w.onSave = function() self:Save() end
    w.onSaveAsNew = function() self:SaveAsNew() end
    w.onDuplicate = function() self:Duplicate(self:Work().id) end
    w.onDelete = function() self:Delete(nil) end
    w.onSlot = function(id, owner, button)
        if button == "RightButton" then self:SlotMenu(id, owner) else self:OpenEditor(id, owner) end
    end
    w.onAdd = function(g)
        local s = self:AddSlot(g)
        if s then self:Refill(); self:OpenEditor(s.id, w:CardFor(s.id)) end
    end
    w.onDrop = function(what, where) self:Drop(what, where) end
    w.onPerson = function(name, owner, button) if button == "RightButton" then self:PersonMenu(name, owner) end end
    w.onSlotChange = function(id, changes) self:ChangeSlot(id, changes) end
    w.onSlotRemove = function(id) self:RemoveSlot(id); self:Refill() end
    w.onInspect = function()
        self.inspectRound = true
        self:InspectNext()
        self:Render()
    end
    w.onArrange = function() self:Arrange() end
    w.onFill = function() self:Refill(true) end
    w:HookScript("OnShow", function()
        if not self:IsEnabled() then return end
        self:Refill()
        self:AskSpecs()
        self:InspectNext()
    end)
end

function M:Toggle()
    if not self.window then self:Build() end
    if self.window:IsShown() then self.window:Hide() else self.window:Show() end
end

--------------------------------------------------------------------------------
-- Settings › Raid planner
--------------------------------------------------------------------------------

-- A family's items as checkboxes, two columns, each with its small print.
local function familyChecks(family)
    return function(parent)
        local f = CreateFrame("Frame", nil, parent)
        local width = math.max(400, parent:GetWidth())
        local colW = math.floor(width / 2)
        f.boxes = {}
        local row = 0
        for _, item in ipairs(ITEMS) do
            if item.family == family then
                local i = #f.boxes
                local b = UI.Checkbox(f, { label = item.label, onChange = function(on) M:SetTracked(item.key, on) end })
                b:SetPoint("TOPLEFT", (i % 2) * colW, -(math.floor(i / 2) * 26))
                b.item = item
                if item.note then
                    b.note = UI.Text(b, "caption", "ink-muted")
                    b.note:SetPoint("LEFT", b.label, "RIGHT", 6, 0)
                    b.note:SetValue(item.note)
                    b:SetWidth(b:GetWidth() + 6 + UI.MeasureText("caption", item.note))
                end
                -- the spell's own tooltip: what it is
                b:HookScript("OnEnter", function(self)
                    if self.item.spell then UI.SpellTooltip(self, self.item.spell, self.item.detail) end
                end)
                b:HookScript("OnLeave", function() GameTooltip:Hide() end)
                f.boxes[#f.boxes + 1] = b
                row = math.floor(i / 2) + 1
            end
        end
        f:SetSize(width, row * 26)
        function f:SetValue(set)
            for _, b in ipairs(self.boxes) do b:SetValue(set and set[b.item.key]) end
        end
        function f:SetDisabled() end
        return f
    end
end

local function familyCounts(family)
    local on, all = 0, 0
    local set = M:TrackedSet()
    for _, item in ipairs(ITEMS) do
        if item.family == family then
            all = all + 1
            if set[item.key] then on = on + 1 end
        end
    end
    return on, all
end

local function familyIsDefault(family)
    local set, essential = M:TrackedSet(), presetSet("essentials")
    for _, item in ipairs(ITEMS) do
        if item.family == family and (set[item.key] or false) ~= (essential[item.key] or false) then return false end
    end
    return true
end

local function resetFamily(family)
    local set, essential = M:TrackedSet(), presetSet("essentials")
    for _, item in ipairs(ITEMS) do
        if item.family == family then set[item.key] = essential[item.key] end
    end
    M:SetTrackedSet(set)
end

local ESSENTIALS_TEXT = "The essentials: Fortitude, Mark, Intellect, Blessings, Salvation, Battle Shout, Windfury, Mana Tide, Trueshot Aura, Sunder, the warlock curses, Faerie Fire, decursing and magic dispels, Rebirth, Soulstone, Innervate. Changing a box below makes it Custom."

function M:Section()
    local groups = {
        { title = "Raid planner", description = "Plan raids as setups of slots; the raid fills them. Open it from Social › Raid › Plan or /suu raid. Only what's tracked below shows in coverage and counts.",
          rows = {
            { label = "Open the planner", control = "button", text = "Raid planner",
              description = "Setups are saved for the account; what's tracked follows this profile.",
              onClick = function() SuuUI.ToggleSettings(); self:Toggle() end },
            { label = "Track", control = "segmented", stacked = true, description = ESSENTIALS_TEXT,
              options = { { value = "all", label = "Everything" }, { value = "essentials", label = "The essentials" }, { value = "custom", label = "Custom" } },
              get = function() return self:Get("preset") end,
              set = function(v)
                  if v == "custom" then
                      self:Set("tracked", self:TrackedSet())
                      return self:Set("preset", "custom")
                  end
                  self:Set("tracked", {})
                  return self:Set("preset", v)
              end,
              isDefault = function() return self:Get("preset") == "essentials" end,
              reset = function() self:Reset("tracked"); self:Reset("preset") end },
            { key = "fill", label = "Auto-fill", control = "segmented",
              options = { { value = "instant", label = "As the raid changes" }, { value = "review", label = "After review" } },
              description = "As the raid changes: slots fill at once, out of combat; players you placed by hand stay. After review: who is placed stays, newcomers wait for Fill slots." },
            { key = "inspect", label = "Inspect missing specs", control = "segmented",
              options = { { value = "auto", label = "Automatically" }, { value = "click", label = "On click" } },
              description = "Automatically: while the planner is open, one player at a time, out of combat, slowly so the game allows it. On click: only from the planner's Inspect button." },
            { key = "flagDoubled", label = "Flag doubled party-wide buffs", control = "toggle",
              description = "Two Trueshot Auras or two Blood Pacts in one group: one is wasted." },
            { key = "shareSpec", label = "Share my spec", control = "toggle",
              description = "Tell raid members who use SuuUI your spec, out of combat, so their planner needn't inspect you." },
        } },
    }
    for _, fam in ipairs(FAMILIES) do
        local key = fam.key
        groups[#groups + 1] = { title = fam.title, description = fam.description, rows = {
            { label = "Tracked", control = "custom", stacked = true, build = familyChecks(key),
              description = function()
                  local on, all = familyCounts(key)
                  return ("%d of %d tracked."):format(on, all)
              end,
              get = function() return self:TrackedSet() end,
              isDefault = function() return familyIsDefault(key) end,
              reset = function() resetFamily(key) end },
        } }
    end
    return { id = "raidplanner", label = "Raid planner", category = "Insights", order = 45, groups = groups }
end

--------------------------------------------------------------------------------
-- Lifecycle
--------------------------------------------------------------------------------

function M:OnEnable()
    loadCatalog()
    self.roster, self.byKey = self.roster or {}, self.byKey or {}
    -- specs older than a day are forgotten (a respec)
    local specs = self:Data().specs
    for k, e in pairs(specs) do
        if type(e) ~= "table" or time() - (e.at or 0) > SPEC_FRESH then specs[k] = nil end
    end
    self:RegisterSettings(self:Section())
    self:Provide("raidplanner", {
        Toggle = function() self:Toggle() end,
        Show = function() if not self.window then self:Build() end; self.window:Show() end,
        IsShown = function() return self.window and self.window:IsShown() or false end,
    })
    self:RegisterCommand("raid", "The raid planner: setups of slots the raid fills, and Arrange groups.", function() self:Toggle() end)
    if C_ChatInfo and C_ChatInfo.RegisterAddonMessagePrefix then C_ChatInfo.RegisterAddonMessagePrefix(PREFIX) end
    local valid = C_EventUtils and C_EventUtils.IsEventValid
    local function on(event, fn) if not valid or valid(event) then self:OnGameEvent(event, fn) end end
    on("CHAT_MSG_ADDON", function(_, ...) self:OnMessage(...) end)
    self.wasInRaid = UI.Flag(IsInRaid())
    on("GROUP_ROSTER_UPDATE", function()
        self:RefillSoon()
        local inRaid = UI.Flag(IsInRaid())
        -- your spec to the raid once, as you join (later only when asked)
        if inRaid and not self.wasInRaid then self:ShareSoon(3) end
        self.wasInRaid = inRaid
        if inRaid and self.window and self.window:IsShown() then
            C_Timer.After(1, function() if self:IsEnabled() then self:AskSpecs(); self:InspectNext() end end)
        end
    end)
    for _, e in ipairs({ "PLAYER_ROLES_ASSIGNED", "PARTY_LEADER_CHANGED", "UNIT_CONNECTION" }) do
        on(e, function() self:RefillSoon() end)
    end
    on("INSPECT_READY", function(_, guid) self:OnInspectReady(guid) end)
    self:OnGameEvent("PLAYER_REGEN_DISABLED", function() self:Render() end)
    self:OnGameEvent("PLAYER_REGEN_ENABLED", function()
        C_Timer.After(1, function()
            if not self:IsEnabled() then return end
            self:Render()
            self:InspectNext()
        end)
    end)
    self:On("SUUUI_SPEC_CHANGED", function() self:ShareSoon(); self:RefillSoon() end)
    -- tracking, fill mode and doubled flags: drawn again
    for _, k in ipairs({ "preset", "tracked", "flagDoubled" }) do self:Watch(k, function() self:Render() end) end
    self:Watch("fill", function() self:Refill(true) end)
    self:Watch("inspect", function() self:InspectNext(); self:Render() end)
    self:Watch("shareSpec", function(on) if on then self:ShareSoon() end end)
    self:Refill()
end

function M:OnDisable()
    if self.window then self.window:Hide() end
    self.inspecting, self.inspectRound = nil, nil
end
