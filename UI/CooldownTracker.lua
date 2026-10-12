-- UI/CooldownTracker.lua
-- SuuUI's own Cooldown Manager (step 1.7b): tracked procs, buffs and your
-- debuffs on the target as icons on top, then Essential and Utility
-- cooldowns. Blizzard's CooldownViewer isn't used.
--
--   local t = UI.CooldownTracker(parent, { name = "SuuUICooldownManager" })
--   t:SetLists(lists)     -- { essential, utility, buffs, debuffs, procs }:
--                         -- entries { name, ids = { ... }, mine }
--   t:SetOptions(opts)    -- { essentialSize, utilityInline, missingBuffs
--                         -- ("hide"|"grey"), missingDebuffs ("hide"|"grey"|
--                         -- "target"), readyPop, procHighlight }
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
-- source = "mine"|"others"|"any", max = 1..4, icon }) is one slot for several
-- spells: the engine shows whichever members are up (up to max), each with
-- its own icon and time; with none up the group's icon follows "when
-- missing". Source maps to the filter: PLAYER, !PLAYER (verified valid), or
-- none.
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
    self.wantShown = want

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

-- Whether any of a reminder's IDs is on its unit (out of combat only).
local function auraUp(r)
    for i = 1, 40 do
        local ok, a = pcall(C_UnitAuras.GetAuraDataByIndex, r.unit, i, r.filter)
        if not ok or isSecret(a) or not a then return false end
        if not isSecret(a.spellId) and r.ids[a.spellId] then return true end
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

-- An aura container on the tracker.
function TR:Aura(unit, opts)
    local ac, fresh = self:Take("aura|" .. containerKey(unit, opts), function() return UI.AuraContainer(self, unit, opts) end)
    if ac and not fresh then ac:SetUnit(unit) end
    return ac
end

-- A cooldown cell for an entry: a clean state (a reused cell must not pop
-- as "ready"), and its effect.
function TR:Cell(entry, spellID, size)
    local f = self:Take("cell|" .. size, function() return newCell(self, size) end)
    f.entry, f.spellID = entry, spellID
    f.reactive = REACTIVE[entry.name] or false
    f.icon:SetArt(C_Spell.GetSpellTexture(spellID))
    f.onCooldown, f.dirty, f.wantShown = nil, nil, nil
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

-- A fixed slot for an aura entry.
function TR:Slot(entry, unit, filter, size, look)
    look = look or {}
    local max = entry.group and math.max(1, math.min(4, entry.max or 1)) or 1
    local copts = {
        size = size, anchor = "TOPLEFT", growth = { "RIGHT", "DOWN" },
        groups = { { key = "e", filter = filter, max = max, include = entry.ids,
                     border = look.border, glow = look.glow, drain = look.drain,
                     digits = look.digits, stacks = look.stacks, expiring = look.expiring } },
    }
    local warn = entry.missing == "warn"
    local f, fresh = self:Take(("slot|%s|%s"):format(tostring(warn), containerKey(unit, copts)),
        function() return newSlot(self, warn, max, size, unit, copts) end)
    if not fresh then
        f:Show()
        if f.container then f.container:SetUnit(unit) end
    end
    f.art:SetTexture(iconFor(entry))
    f.entryGrey = nil
    return f
end

-- A reminder for an aura entry (hidden until UpdateReminders shows it).
function TR:Reminder(entry, unit, filter, size)
    local f = self:Take("remind|" .. size, function() return newReminder(self, size) end)
    f.art:SetTexture(iconFor(entry))
    f.unit, f.filter = unit, table.concat(filter, "|")
    f.ids = {}
    for _, id in ipairs(entry.ids) do f.ids[id] = true end
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
    self.leftFlow, self.rightFlow = nil, nil
end

-- Builds the rows from the lists. Out of combat (it creates engine containers,
-- or takes spare ones).
function TR:Build()
    self:Clear()
    local opts = self.opts or {}
    -- Entries without spells (a group just made) are skipped: an empty spell
    -- list would let the engine show every aura.
    local lists = {}
    for key, list in pairs(self.lists or {}) do
        lists[key] = {}
        for _, e in ipairs(list) do
            if e.ids and #e.ids > 0 then table.insert(lists[key], e) end
        end
    end
    local aura = UI.Size(AURA)
    local essential = opts.essentialSize or UI.Size("cdm-essential")
    local utility = UI.Size(opts.utilityInline and essential or "icon-lg")

    for _, key in ipairs({ "essential", "utility" }) do
        for _, entry in ipairs(lists[key] or {}) do
            local id = not entry.hidden and knownRank(entry)
            if id then
                local cell = self:Cell(entry, id, key == "essential" and essential or utility)
                table.insert(self.built[key], cell)
                self.cells[#self.cells + 1] = cell
            end
        end
    end

    local proc = opts.procHighlight ~= false and { border = "arcane", glow = "glow-arcane" } or nil
    local function auraGroup(key, entry, filter, base)
        local look = auraLook(entry, base)
        return { key = key, filter = filter, max = entry.group and (entry.max or 1) or 1, include = entry.ids,
                 border = look.border, glow = look.glow, digits = look.digits, stacks = look.stacks,
                 expiring = look.expiring, size = auraSize(entry) }
    end

    -- Buffs: grey keeps a fixed slot per entry (never empty: the placeholder
    -- shows); hide packs them into one container the engine closes up. The
    -- left side grows away from the divider, procs after the buffs.
    -- Each entry's "when missing" (its own, else the list's): grey keeps a
    -- fixed slot, hide joins the packed container beyond the fixed ones.
    local leftGroups = {}
    for i, entry in ipairs(lists.buffs or {}) do
        local filter = sourceFilter("HELPFUL", entry, "any")
        local mode = entry.missing or opts.missingBuffs
        if mode == "hide" then
            leftGroups[#leftGroups + 1] = auraGroup("b" .. i, entry, filter)
        elseif mode == "remind" then
            table.insert(self.built.remindBuffs, self:Reminder(entry, "player", filter, auraSize(entry)))
        else
            table.insert(self.built.buffs, self:Slot(entry, "player", filter, auraSize(entry), auraLook(entry)))
        end
    end
    for i, entry in ipairs(lists.procs or {}) do
        leftGroups[#leftGroups + 1] = auraGroup("p" .. i, entry, sourceFilter("HELPFUL", entry, "mine"), proc)
    end
    if #leftGroups > 0 then
        self.leftFlow = self:Aura("player", { size = aura, anchor = "BOTTOMRIGHT", growth = { "LEFT", "UP" }, groups = leftGroups })
    end

    -- Your debuffs on the target: hide packs them, growing right of the
    -- divider; grey and "with a target" keep fixed slots.
    -- A debuff from a spell you know no rank of gets no grey slot (it would
    -- remind you of something you can't cast); it packs with the hidden ones.
    local groups = {}
    for i, entry in ipairs(lists.debuffs or {}) do
        local mode = entry.missing or opts.missingDebuffs
        local filter = sourceFilter("HARMFUL", entry, "mine")
        -- a single debuff you know no rank of gets no grey slot; groups always
        -- do (their members are often auras you don't cast directly, such as
        -- the judgements that "Judgement" puts on the target)
        if mode == "hide" or (not entry.group and not knownRank(entry)) then
            groups[#groups + 1] = auraGroup("d" .. i, entry, filter)
        elseif mode == "remind" then
            table.insert(self.built.remindDebuffs, self:Reminder(entry, "target", filter, auraSize(entry)))
        else
            local slot = self:Slot(entry, "target", filter, auraSize(entry), auraLook(entry))
            slot.entryGrey = entry.missing == "grey" -- grey on its own: always shown
            table.insert(self.built.debuffs, slot)
        end
    end
    if #groups > 0 then
        self.rightFlow = self:Aura("target", { size = aura, anchor = "BOTTOMLEFT", growth = { "RIGHT", "UP" }, groups = groups })
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
    -- show there (the effect hangs on the tracker, over the cell's spot)
    local function cells(list)
        local out = {}
        for _, f in ipairs(list) do
            if f:IsShown() or (f.container and f.onCooldown) then out[#out + 1] = f end
        end
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
    local buffs, debuffs = self.built.buffs, self.built.debuffs
    local remindL, remindR = shown(self.built.remindBuffs), shown(self.built.remindDebuffs)
    -- slots can be wider than one icon (a group showing several members)
    local function span(...)
        local w, n = 0, 0
        for _, list in ipairs({ ... }) do
            for _, c in ipairs(list) do w = w + c:GetWidth(); n = n + 1 end
        end
        return w + math.max(0, n - 1) * S["space-2"]
    end
    local leftW = span(buffs, remindL)
    local rightW = span(debuffs, remindR)
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
        for _, c in ipairs(buffs) do
            x = x - c:GetWidth()
            c:ClearAllPoints()
            c:SetPoint("BOTTOMLEFT", self, "BOTTOMLEFT", x, y)
            x = x - S["space-2"]
        end
        for _, c in ipairs(remindL) do
            x = x - c:GetWidth()
            c:ClearAllPoints()
            c:SetPoint("BOTTOMLEFT", self, "BOTTOMLEFT", x, y)
            x = x - S["space-2"]
        end
        if self.leftFlow then
            local edge = (#buffs + #remindL > 0) and x or leftEnd
            self.leftFlow.container:ClearAllPoints()
            self.leftFlow.container:SetPoint("BOTTOMRIGHT", self, "BOTTOMLEFT", edge, y)
        end
        -- right side: debuffs start space-4 right of the divider
        local rightStart = mid + 1 + S["space-4"]
        local rx = place(debuffs, S["space-2"], rightW, y, rightStart)
        rx = place(remindR, S["space-2"], rightW, y, rx)
        if self.rightFlow then
            local edge = (#debuffs + #remindR > 0) and rx or rightStart
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
    local mode = opts.missingDebuffs or "target"
    for _, slot in ipairs(self.built.debuffs) do
        slot.placeholder:Show()
        if mode == "target" and not slot.entryGrey then
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
    local function update(list, needTarget)
        for _, r in ipairs(list) do
            local show = not fight and (not needTarget or hostile) and not auraUp(r)
            if show ~= r:IsShown() then r:SetShown(show); changed = true end
        end
    end
    update(self.built.remindBuffs, false)
    update(self.built.remindDebuffs, true)
    if changed and not noLayout then self:Layout() end
end

function TR:UpdateCooldowns()
    local changed = false
    for _, cell in ipairs(self.cells or {}) do
        cell:Update(self.opts or {})
        if cell.wantShown ~= cell:IsShown() then
            cell:SetShown(cell.wantShown)
            changed = true
        end
    end
    if changed then self:Layout() end
end

-- Which ranks of the listed cooldowns and debuffs you know, as one string.
function TR:KnownSignature()
    local parts = {}
    for _, key in ipairs({ "essential", "utility" }) do
        for _, entry in ipairs((self.lists or {})[key] or {}) do parts[#parts + 1] = tostring(knownRank(entry) or 0) end
    end
    for _, entry in ipairs((self.lists or {}).debuffs or {}) do parts[#parts + 1] = tostring(knownRank(entry) or 0) end
    return table.concat(parts, ",")
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
    Events.OnGame("PLAYER_TARGET_CHANGED", function() t:UpdateMissing(); t:UpdateReminders(); mark() end, t)
    Events.OnUnit("UNIT_AURA", { "player", "target" }, function()
        if not (t.inFight or InCombatLockdown()) then t:UpdateReminders() end
    end, t)
    Events.OnGame("PLAYER_REGEN_DISABLED", function() t.inFight = true; t:UpdateReminders() end, t)
    Events.OnGame("PLAYER_REGEN_ENABLED", function()
        t.inFight = false
        C_Timer.After(0, function() t:UpdateReminders() end)
    end, t)
    -- Learning a rank rebuilds; the spellbook "changing" with a shapeshift
    -- (same ranks known) doesn't.
    for _, e in ipairs({ "SPELLS_CHANGED", "LEARNED_SPELL_IN_SKILL_LINE", "LEARNED_SPELL_IN_TAB" }) do
        if not valid or valid(e) then Events.OnGame(e, function()
            local sig = t:KnownSignature()
            if sig ~= t.knownSig then t.rebuild = true end
        end, t) end
    end
end

function TR:Stop()
    if not self.running then return end
    self.running = false
    self.driver:Hide()
    Events.OffAll(self)
    clearAuraSounds()
    self:Clear()
    self.knownSig = nil
end

function UI.CooldownTracker(parent, opts)
    local t = CreateFrame("Frame", opts and opts.name, parent)
    Mixin(t, TR)
    t:SetSize(1, 1)
    t.divider = UI.Fill(t, "gilt-line", "ARTWORK")
    t.divider:Hide()
    t.auraDivider = UI.Fill(t, "gilt-line", "ARTWORK")
    t.auraDivider:Hide()
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
