-- Diagnostics/PowerProbe.lua
-- "/suu probe power" (asked 2026-10-19: the Cooldown Manager's resource bar
-- with combo points over the cast bar, design B): what the game tells about
-- your power, in and out of combat.
--   now, 2 s into each fight (up to 6) and at the first combo point change
--   of each fight: UnitPowerType (both returns), UnitPower, UnitPowerMax and
--          UnitPowerPercent, plain and for Mana, Rage, Energy and Combo
--          points; GetComboPoints("player", "target"); and whether a
--          StatusBar takes the combo points (five hidden bars, bar i at
--          SetMinMaxValues(i - 1, i), as pips would be; SetValue in a pcall,
--          GetValue read back) and the energy (0 to UnitPowerMax)
--   then (this session, by itself): UNIT_POWER_FREQUENT and
--          UNIT_POWER_UPDATE for you (how many, the most in one second, by
--          power token, their arguments), UNIT_MAXPOWER, UNIT_DISPLAYPOWER,
--          PLAYER_TARGET_CHANGED; the time between power events per token
--          (energy ticks every ~2 s: a rhythm may show from the timing
--          alone, without reading the amount), with the amount when it reads
--          plain; your casts (UNIT_SPELLCAST_SUCCEEDED) with
--          C_Spell.GetSpellPowerCost, and for mana the seconds since your
--          last cast at each power event (the five-second rule); form changes
--          (UPDATE_SHAPESHIFT_FORM): whether UnitPowerType reads in combat
-- Saved in SuuUIProbe.power on /reload. Values the game hides read SECRET.

local _, ns = ...

local PP = {}
ns.PowerProbe = PP

local isSecret = issecretvalue or function() return false end
local function show(v)
    if isSecret(v) then return "SECRET" end
    if type(v) == "number" and v ~= math.floor(v) then return ("%.3f"):format(v) end
    return tostring(v)
end

-- A function that may not exist, may error or may answer secret.
local function call(fn, ...)
    if type(fn) ~= "function" then return "missing" end
    local ok, a, b, c, d = pcall(fn, ...)
    if not ok then return "error: " .. tostring(a):sub(1, 120) end
    return a, b, c, d
end

local function plain(v) return v ~= nil and not isSecret(v) end

local function out()
    SuuUIProbe = SuuUIProbe or {}
    SuuUIProbe.power = SuuUIProbe.power or {}
    return SuuUIProbe.power
end

local function push(list, line, cap)
    if #list < (cap or 60) then list[#list + 1] = line end
end

local PT = Enum and Enum.PowerType or {}
local TYPES = {
    { name = "Mana", id = PT.Mana or 0 },
    { name = "Rage", id = PT.Rage or 1 },
    { name = "Energy", id = PT.Energy or 3 },
    { name = "ComboPoints", id = PT.ComboPoints or 4 },
}
local COMBO = PT.ComboPoints or 4
local ENERGY = PT.Energy or 3

--------------------------------------------------------------------------------
-- A snapshot of every value, and the StatusBar test
--------------------------------------------------------------------------------

local bars
local function testBars()
    if not bars then
        bars = {}
        for i = 1, 6 do
            local b = CreateFrame("StatusBar", nil, UIParent)
            b:SetSize(10, 10)
            b:Hide()
            bars[i] = b
        end
    end
    local res = {}
    -- the combo points as five pips: bar i is full from i points on
    local sources = {
        { "UnitPower(ComboPoints)", (call(UnitPower, "player", COMBO)) },
        { "GetComboPoints", (call(GetComboPoints, "player", "target")) },
    }
    for _, src in ipairs(sources) do
        local value = src[2]
        local pips = {}
        for i = 1, 5 do
            local b = bars[i]
            b:SetMinMaxValues(i - 1, i)
            local ok, err = pcall(b.SetValue, b, value)
            local back = b:GetValue()
            pips[i] = ok and ("ok, reads %s"):format(show(back)) or ("error: " .. tostring(err):sub(1, 80))
        end
        res[#res + 1] = ("%s = %s → pips: %s"):format(src[1], show(value), table.concat(pips, " | "))
    end
    -- the energy bar: 0 to its max, both as the game gives them
    local b = bars[6]
    local max, now = call(UnitPowerMax, "player", ENERGY), call(UnitPower, "player", ENERGY)
    local okMax, errMax = pcall(b.SetMinMaxValues, b, 0, max)
    local okValue, errValue = pcall(b.SetValue, b, now)
    res[#res + 1] = ("energy bar: SetMinMaxValues(0, %s) %s, SetValue(%s) %s, reads %s"):format(show(max),
        okMax and "ok" or ("error: " .. tostring(errMax):sub(1, 80)), show(now),
        okValue and "ok" or ("error: " .. tostring(errValue):sub(1, 80)), show(b:GetValue()))
    return res
end

local function snapshot(label)
    local s = { at = date("%H:%M:%S"), what = label, combat = tostring(InCombatLockdown()) }
    local pType, pToken = call(UnitPowerType, "player")
    s.powerType = ("%s, %s"):format(show(pType), show(pToken))
    s.form = show(call(GetShapeshiftForm))
    s.plain = ("UnitPower %s, UnitPowerMax %s, UnitPowerPercent %s"):format(show(call(UnitPower, "player")),
        show(call(UnitPowerMax, "player")), show(call(UnitPowerPercent, "player")))
    s.types = {}
    for _, t in ipairs(TYPES) do
        s.types[#s.types + 1] = ("%s (%d): UnitPower %s, UnitPowerMax %s, UnitPowerPercent %s"):format(t.name, t.id,
            show(call(UnitPower, "player", t.id)), show(call(UnitPowerMax, "player", t.id)),
            show(call(UnitPowerPercent, "player", t.id)))
    end
    s.comboPoints = ("GetComboPoints(player, target) %s; target %s"):format(show(call(GetComboPoints, "player", "target")),
        show(call(UnitExists, "target")))
    s.bars = testBars()
    return s
end

--------------------------------------------------------------------------------
-- The session's events
--------------------------------------------------------------------------------

local start, lastCast, fight
local seconds = {}      -- [event] = { second = n, count = n }
local lastAt = {}       -- [token] = GetTime() of its last power event
local lastAmount = {}   -- [token] = the last plain amount

local function rate(e, event)
    local now = math.floor(GetTime())
    local s = seconds[event]
    if not s or s.second ~= now then
        s = { second = now, count = 0 }
        seconds[event] = s
    end
    s.count = s.count + 1
    e.maxPerSecond = e.maxPerSecond or {}
    if s.count > (e.maxPerSecond[event] or 0) then e.maxPerSecond[event] = s.count end
end

local TOKEN_TYPE = { MANA = PT.Mana or 0, RAGE = PT.Rage or 1, ENERGY = PT.Energy or 3, COMBO_POINTS = COMBO }

local function onPower(o, event, token)
    local e = o.events
    local key = plain(token) and tostring(token) or "SECRET"
    e.byToken[event .. " " .. key] = (e.byToken[event .. " " .. key] or 0) + 1
    -- the timing per token (UNIT_POWER_FREQUENT only, so one event per change)
    if event ~= "UNIT_POWER_FREQUENT" then return end
    local now = GetTime()
    local amount
    local id = TOKEN_TYPE[key]
    if id then amount = call(UnitPower, "player", id) end
    local amountText = show(amount)
    local delta = ""
    if plain(amount) and type(amount) == "number" then
        if lastAmount[key] then delta = (" (%+d)"):format(amount - lastAmount[key]) end
        lastAmount[key] = amount
    end
    local t = o.timing[key] or { intervals = {}, histogram = {} }
    o.timing[key] = t
    if lastAt[key] then
        local gap = now - lastAt[key]
        local line = ("%.2f s, amount %s%s, combat %s"):format(gap, amountText, delta, tostring(InCombatLockdown()))
        if key == "MANA" and lastCast then line = line .. (", %.1f s since your last cast"):format(now - lastCast) end
        push(t.intervals, line, 80)
        local bucket = ("%.1f"):format(math.floor(gap * 10 + 0.5) / 10)
        t.histogram[bucket] = (t.histogram[bucket] or 0) + 1
    end
    lastAt[key] = now
    -- the first combo point change of a fight: a full snapshot
    if key == "COMBO_POINTS" and fight and not fight.comboSeen then
        fight.comboSeen = true
        fight.combo = snapshot("the fight's first combo point change")
    end
end

local function costText(spellID)
    local costs = call(C_Spell and C_Spell.GetSpellPowerCost, spellID)
    if isSecret(costs) then return "SECRET" end
    if type(costs) ~= "table" then return show(costs) end
    local list = {}
    for _, c in ipairs(costs) do
        if isSecret(c) then list[#list + 1] = "SECRET" else
            list[#list + 1] = ("type %s %s: cost %s, min %s, percent %s, per sec %s"):format(show(c.type), show(c.name),
                show(c.cost), show(c.minCost), show(c.costPercent), show(c.costPerSec))
        end
    end
    return #list > 0 and table.concat(list, " | ") or "no cost"
end

local listening
local function listen()
    if listening then return end
    listening = CreateFrame("Frame")
    local f = listening
    for _, event in ipairs({ "UNIT_POWER_FREQUENT", "UNIT_POWER_UPDATE", "UNIT_MAXPOWER", "UNIT_DISPLAYPOWER",
                             "UNIT_SPELLCAST_SUCCEEDED" }) do
        pcall(f.RegisterUnitEvent, f, event, "player")
    end
    for _, event in ipairs({ "PLAYER_TARGET_CHANGED", "UPDATE_SHAPESHIFT_FORM", "PLAYER_REGEN_DISABLED",
                             "PLAYER_REGEN_ENABLED" }) do
        pcall(f.RegisterEvent, f, event)
    end
    f:SetScript("OnEvent", function(_, event, a, b, c)
        local o = out()
        local e = o.events
        e.counts[event] = (e.counts[event] or 0) + 1
        e.seconds = ("%.0f s since the probe began"):format(GetTime() - start)
        rate(e, event)
        e.args[event] = e.args[event] or {}
        if event ~= "UNIT_SPELLCAST_SUCCEEDED" then
            push(e.args[event], ("%.1fs %s %s %s"):format(GetTime() - start, show(a), show(b), show(c)), 20)
        end
        if event == "UNIT_POWER_FREQUENT" or event == "UNIT_POWER_UPDATE" then
            onPower(o, event, b)
        elseif event == "UNIT_DISPLAYPOWER" or event == "UPDATE_SHAPESHIFT_FORM" then
            local pType, pToken = call(UnitPowerType, "player")
            push(o.forms, ("%s %s: form %s, UnitPowerType %s, %s, UnitPower %s / %s, combat %s"):format(date("%H:%M:%S"), event,
                show(call(GetShapeshiftForm)), show(pType), show(pToken), show(call(UnitPower, "player")),
                show(call(UnitPowerMax, "player")), tostring(InCombatLockdown())), 40)
        elseif event == "UNIT_SPELLCAST_SUCCEEDED" then
            lastCast = GetTime()
            push(o.casts, ("%s %s (spell %s): %s; combat %s"):format(date("%H:%M:%S"), show(call(C_Spell.GetSpellName, c)),
                show(c), costText(c), tostring(InCombatLockdown())), 40)
        elseif event == "PLAYER_REGEN_DISABLED" then
            if #o.fights >= 6 then fight = nil return end
            fight = { started = date("%H:%M:%S") }
            local mine = fight
            o.fights[#o.fights + 1] = mine
            C_Timer.After(2, function()
                mine.twoSeconds = snapshot("2 s into the fight")
                if #o.fights == 1 then
                    ns.Print("Power probe: first fight recorded. A few more (up to 6), then /reload to save it.")
                end
            end)
        elseif event == "PLAYER_REGEN_ENABLED" then
            if fight then fight.ended = date("%H:%M:%S") end
            fight = nil
        end
    end)
end

function PP.Command()
    local o = out()
    o.now = snapshot("now")
    if not listening then
        start = GetTime()
        o.session = date("%Y-%m-%d %H:%M:%S")
        o.events = { counts = {}, byToken = {}, args = {} }
        o.timing = {}
        o.forms = {}
        o.casts = {}
        o.fights = {}
    end
    listen()
    local _, class = UnitClass("player")
    local hint
    if class == "DRUID" then
        hint = "Fight in cat form (energy, combo points), in bear form (rage) and in caster form (mana), and change forms during a fight."
    elseif class == "ROGUE" then
        hint = "Fight a few mobs with combo point builders and a finisher."
    elseif class == "PALADIN" then
        hint = "Fight a few mobs and cast between them (mana, the five-second rule); combo points stay 0 here, so a druid in cat form shows those."
    else
        hint = "Fight a few mobs."
    end
    ns.Print(("Power probe: recorded your power now. %s Up to 6 fights are recorded; then /reload to save it."):format(hint))
end
