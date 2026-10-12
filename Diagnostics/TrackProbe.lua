-- Diagnostics/TrackProbe.lua
-- "/suu probe track": can SuuUI's own tracker work in combat? (plan step 1.7a)
--
-- 1. Capture (out of combat): your buffs are read while that is allowed (any
--    combat hides auras, the open world too); the test debuff comes from your
--    spellbook (the first debuff spell of your class you know).
-- 2. The panel shows four engine aura containers: your buffs (all), your
--    buffs filtered by a spell list to the test buff, your debuffs on the
--    target (all), and the same filtered to the test debuff. Each row counts
--    the icons the engine shows.
-- 3. In dungeon combat: if the filtered rows stay at one icon while the "all"
--    rows show more, spell lists filter in combat.
-- It also logs whether reactive abilities' "usable" state and the game's
-- proc-glow event are readable in combat. Everything is summarized per
-- context (open world / dungeon, in or out of combat) in SuuUIProbe.track,
-- saved on /reload for Claude to read.
--
--   /suu probe track        capture if possible (else reuse), show the panel
--   /suu probe track new    capture again
--   /suu probe track off    hide the panel

local _, ns = ...

local UI, T, Events = ns.UI, ns.Tokens, ns.Events
local S = T.space

local TP = {}
ns.TrackProbe = TP

local isSecret = issecretvalue or function() return false end

-- Reactive abilities by class: usable only after a dodge, parry or block, or
-- below 20% health.
local REACTIVE = {
    WARRIOR = { "Overpower", "Revenge", "Execute" },
    ROGUE = { "Riposte" },
    HUNTER = { "Mongoose Bite", "Counterattack" },
    PALADIN = { "Hammer of Wrath" },
}

-- Debuff spells by class whose aura carries the spell's own ID. The first
-- one you know becomes the test debuff.
local DEBUFFS = {
    DRUID = { "Moonfire", "Faerie Fire", "Insect Swarm", "Rake", "Rip", "Demoralizing Roar" },
    HUNTER = { "Hunter's Mark", "Serpent Sting", "Scorpid Sting", "Viper Sting", "Wing Clip" },
    WARRIOR = { "Rend", "Sunder Armor", "Demoralizing Shout", "Thunder Clap", "Hamstring" },
    ROGUE = { "Garrote", "Rupture", "Expose Armor", "Crippling Poison" },
    MAGE = { "Frostbolt", "Fireball", "Polymorph" },
    PRIEST = { "Shadow Word: Pain", "Devouring Plague", "Mind Flay" },
    WARLOCK = { "Corruption", "Curse of Agony", "Immolate", "Curse of Weakness" },
    SHAMAN = { "Flame Shock", "Frost Shock" },
    PALADIN = { "Judgement of the Crusader", "Hammer of Justice" },
}

local panel, rows, statusText, verdictText
local ticker

local function store()
    SuuUIProbe = SuuUIProbe or {}
    SuuUIProbe.track = SuuUIProbe.track or {}
    return SuuUIProbe.track
end

local function state(v)
    if isSecret(v) then return "secret" end
    if v == nil then return "nil" end
    return tostring(v)
end

--------------------------------------------------------------------------------
-- Capture
--------------------------------------------------------------------------------

-- The auras on `unit` while they can be read; nil if any read is secret.
local function readAuras(unit, filter)
    local out = {}
    for i = 1, 40 do
        local ok, a = pcall(C_UnitAuras.GetAuraDataByIndex, unit, i, filter)
        if not ok or isSecret(a) then return nil end
        if not a then break end
        if isSecret(a.spellId) or isSecret(a.name) then return nil end
        out[#out + 1] = { id = a.spellId, name = a.name }
    end
    return out
end

-- Your class's debuff spells you know, highest rank first found by name.
local function knownDebuffs()
    local _, class = UnitClass("player")
    local out = {}
    for _, name in ipairs(DEBUFFS[class] or {}) do
        local info = C_Spell.GetSpellInfo(name)
        local id = info and info.spellID
        if id and not isSecret(id) and IsPlayerSpell(id) then out[#out + 1] = { id = id, name = name } end
    end
    return out
end

function TP.Capture()
    local t = store()
    local buffs = readAuras("player", "HELPFUL")
    if not buffs then
        ns.Print("Track probe: auras can't be read in combat (the open world too). Capture out of combat.")
        return false
    end
    local debuffs = knownDebuffs()
    t.buffs, t.debuffs = buffs, debuffs
    t.pickBuff = buffs[1] and buffs[1].id or nil
    t.pickDebuff = debuffs[1] and debuffs[1].id or nil
    t.capturedAt = date("%Y-%m-%d %H:%M")
    t.samples, t.summary, t.glowEvents = {}, {}, {}
    local function names(list)
        local n = {}
        for _, a in ipairs(list) do n[#n + 1] = ("%s (%d)"):format(a.name, a.id) end
        return #n > 0 and table.concat(n, ", ") or "none"
    end
    ns.Print(("Track probe captured buffs: %s"):format(names(buffs)))
    ns.Print(("Track probe: your debuff spells it knows: %s"):format(names(debuffs)))
    if #buffs < 2 then ns.Print("Track probe: have at least two buffs on you, or the buff test can't tell anything.") end
    if debuffs[1] then
        ns.Print(("Track probe: test debuff is %s. On a mob, use it plus at least one other debuff."):format(debuffs[1].name))
    else
        ns.Print("Track probe: no known debuff spell for your class; the debuff test will stay empty.")
    end
    return true
end

--------------------------------------------------------------------------------
-- The panel
--------------------------------------------------------------------------------

-- How many icons a container shows. In combat the engine's icons are
-- forbidden (not even IsShown may be asked), so then the count comes from the
-- container's width, if the engine sizes it to its icons; else "locked".
local ICON = 24 -- icon-md
local GAP = 4   -- space-2
local function shownCount(c)
    if not c then return "n/a" end
    local n, locked = 0, false
    for _, child in ipairs({ c.container:GetChildren() }) do
        if child:IsForbidden() then locked = true break end
        local ok, shown = pcall(child.IsShown, child)
        if not ok or isSecret(shown) then locked = true break end
        if shown then n = n + 1 end
    end
    if not locked then return n end
    local ok, w = pcall(c.container.GetWidth, c.container)
    if ok and w and not isSecret(w) and w > 1 then
        return math.floor((w + GAP) / (ICON + GAP) + 0.5), "width"
    end
    return "locked"
end

local function nameOf(list, id)
    for _, a in ipairs(list or {}) do if a.id == id then return a.name end end
    return id and tostring(id) or "none"
end

local function buildPanel()
    local t = store()
    local p = UI.Panel(ns.Root, { title = "Track probe", width = 520, height = 330 })
    p:SetFrameStrata("HIGH")
    p:SetPoint("LEFT", ns.Root, "LEFT", 60, 60)
    p:EnableMouse(true)
    p:SetMovable(true)
    p:RegisterForDrag("LeftButton")
    p:SetScript("OnDragStart", p.StartMoving)
    p:SetScript("OnDragStop", p.StopMovingOrSizing)

    local defs = {
        { label = "Your buffs, all", unit = "player", filter = { "HELPFUL" } },
        { label = "Your buffs, only " .. nameOf(t.buffs, t.pickBuff), unit = "player", filter = { "HELPFUL" }, include = t.pickBuff },
        { label = "Your debuffs on the target, all", unit = "target", filter = { "HARMFUL", "PLAYER" } },
        { label = "Your debuffs on the target, only " .. nameOf(t.debuffs, t.pickDebuff), unit = "target", filter = { "HARMFUL", "PLAYER" }, include = t.pickDebuff },
    }
    rows = {}
    for i, d in ipairs(defs) do
        local y = -(56 + (i - 1) * 52)
        local label = UI.Text(p, "caption", "ink-muted")
        label:SetPoint("TOPLEFT", S["space-5"], y)
        label:SetValue(d.label)
        local count = UI.Text(p, "label", "ink")
        count:SetPoint("TOPRIGHT", -S["space-5"], y)
        local holder = CreateFrame("Frame", nil, p)
        holder:SetSize(480, 24)
        holder:SetPoint("TOPLEFT", S["space-5"], y - 16)
        local c = (d.include or not d.label:find("only")) and UI.AuraContainer(holder, d.unit, {
            size = "icon-md", anchor = "TOPLEFT", growth = { "RIGHT", "DOWN" }, lineWidth = 480,
            groups = { { key = "g", filter = d.filter, max = 12, include = d.include and { d.include } or nil } },
        }) or nil
        if c then c.container:SetPoint("TOPLEFT", holder, "TOPLEFT") end
        rows[i] = { def = d, count = count, container = c }
    end

    statusText = UI.Text(p, "caption", "ink-muted")
    statusText:SetPoint("BOTTOMLEFT", S["space-5"], 40)
    verdictText = UI.Text(p, "caption", "ink")
    verdictText:SetWordWrap(true)
    verdictText:SetJustifyH("LEFT")
    verdictText:SetFixedWidth(480)
    verdictText:SetPoint("BOTTOMLEFT", S["space-5"], S["space-5"])
    return p
end

--------------------------------------------------------------------------------
-- Sampling
--------------------------------------------------------------------------------

local function context()
    local _, kind = IsInInstance()
    local where = (kind == "party" or kind == "raid") and kind or "world"
    local fight = InCombatLockdown() and "combat" or "calm"
    local boss = UnitExists("boss1") and " boss" or ""
    return where .. " " .. fight .. boss
end

local function aurasReadable()
    local ok, a = pcall(C_UnitAuras.GetAuraDataByIndex, "player", 1, "HELPFUL")
    if not ok then return "error" end
    if isSecret(a) or (a and isSecret(a.spellId)) then return "secret" end
    return "readable"
end

local function reactiveStates()
    local _, class = UnitClass("player")
    local out = {}
    for _, name in ipairs(REACTIVE[class] or {}) do
        local info = C_Spell.GetSpellInfo(name)
        local id = info and info.spellID
        if id and not isSecret(id) then
            local ok, usable = pcall(C_Spell.IsSpellUsable, id)
            out[name] = ok and state(usable) or "error"
        end
    end
    return out
end

-- Per context: the highest count each row reached and whether reads were secret.
local function record(counts)
    local t = store()
    t.summary = t.summary or {}
    t.samples = t.samples or {}
    local ctx = context()
    local sum = t.summary[ctx] or { samples = 0, maxCounts = { 0, 0, 0, 0 }, auraReads = {}, reactive = {} }
    sum.samples = sum.samples + 1
    for i, c in ipairs(counts) do
        if type(c) == "number" then
            if c > (sum.maxCounts[i] or 0) then sum.maxCounts[i] = c end
        else
            sum.maxCounts[i] = c
        end
    end
    local r = aurasReadable()
    sum.auraReads[r] = (sum.auraReads[r] or 0) + 1
    for name, st in pairs(reactiveStates()) do
        sum.reactive[name] = sum.reactive[name] or {}
        sum.reactive[name][st] = (sum.reactive[name][st] or 0) + 1
    end
    t.summary[ctx] = sum
    if InCombatLockdown() then
        t.samples[#t.samples + 1] = { ctx = ctx, counts = counts, auras = r }
        if #t.samples > 300 then table.remove(t.samples, 1) end
    end
end

local function verdict(all, only, what)
    if type(all) ~= "number" or type(only) ~= "number" then return what .. ": counts unreadable" end
    if all < 2 then return what .. ": need 2+ to tell" end
    if only <= 1 then return what .. ": filtered (" .. only .. " of " .. all .. ")" end
    if only >= all then return what .. ": NOT filtered (" .. only .. " of " .. all .. ")" end
    return what .. ": partly (" .. only .. " of " .. all .. ")"
end

local function tick()
    if not (panel and panel:IsShown()) then return end
    local counts, methods = {}, {}
    for i, row in ipairs(rows) do
        counts[i], methods[i] = shownCount(row.container)
        row.count:SetValue(tostring(counts[i]) .. (methods[i] and " (by width)" or ""))
    end
    store().countMethod = methods[1] or methods[3] or "children"
    record(counts)
    statusText:SetValue(("%s · auras %s · %s"):format(context(), aurasReadable(), date("%H:%M:%S")))
    verdictText:SetValue(verdict(counts[1], counts[2], "Buffs") .. "   " .. verdict(counts[3], counts[4], "Target debuffs"))
end

-- The game's proc glow: does the event come, and is its spell ID readable?
local GLOW = "SPELL_ACTIVATION_OVERLAY_GLOW_SHOW"
local glowExists = not (C_EventUtils and C_EventUtils.IsEventValid) or C_EventUtils.IsEventValid(GLOW)
local glowOk = glowExists and pcall(Events.OnGame, GLOW, function(_, spellID)
    if not (panel and panel:IsShown()) then return end
    local t = store()
    t.glowEvents = t.glowEvents or {}
    local name = (not isSecret(spellID) and spellID) and C_Spell.GetSpellName(spellID) or nil
    t.glowEvents[#t.glowEvents + 1] = { ctx = context(), spellID = state(spellID), name = name }
    if #t.glowEvents > 50 then table.remove(t.glowEvents, 1) end
end, "TrackProbe")

--------------------------------------------------------------------------------
-- The command
--------------------------------------------------------------------------------

function TP.Command(arg)
    if arg == "off" then
        if panel then panel:Hide() end
        return
    end
    local t = store()
    if arg == "new" or not t.buffs then
        if not TP.Capture() then return end
        if panel then panel:Hide(); panel = nil end -- rebuilt with the new test spells
    end
    panel = panel or buildPanel()
    panel:Show()
    t.glowEventExists = glowOk and true or false
    ticker = ticker or C_Timer.NewTicker(1, function() ns.Fault.Call("TrackProbe", tick) end)
    tick()
    ns.Print("Track probe running. Fight in a dungeon with the test buff and debuff up, then /reload to save the results.")
end
