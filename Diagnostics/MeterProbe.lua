-- Diagnostics/MeterProbe.lua
-- "/suu probe meter": what Forever's damage meter API gives an addon (plan
-- step 1.12), before SuuUI builds its own meter on it. Once: the client's
-- documentation of C_DamageMeter and C_DeathRecap (functions, events,
-- tables), the globals named like the Blizzard meter, and the event names
-- found there (registered, counted while armed). Per sample: available
-- sessions, each session type's duration, and for every meter type the
-- session's shape (each field readable, secret or missing; the first sources
-- in full, the list's count), plus one source's spell breakdown and a death
-- recap if there is one. One sample now; while armed, 2 and 6 seconds into
-- each fight and after it. Saved in SuuUIProbe.meter on /reload.
--
--   /suu probe meter        arm and sample now (hit something for a while first)
--   /suu probe meter off    stop sampling

local _, ns = ...

local Events = ns.Events

local MP = {}
ns.MeterProbe = MP

local isSecret = issecretvalue or function() return false end
local isSecretTable = issecrettable or function() return false end
local MAX_SAMPLES = 10
local armed = false
local eventFrame, eventCounts, eventPayloads

-- A value's shape: "secret", "nil", "<type>: <value>" for plain ones, and
-- tables as tables of shapes (lists: the count and the first two items).
local function shape(v, depth)
    depth = depth or 0
    if isSecret(v) then return "secret" end
    if v == nil then return "nil" end
    local t = type(v)
    if t ~= "table" then return t .. ": " .. tostring(v):sub(1, 60) end
    if isSecretTable(v) then return "secret table" end
    if depth >= 4 then return "table (deeper)" end
    local out, n = {}, 0
    local count = #v
    if count > 0 then out["#"] = count end
    for k, x in pairs(v) do
        n = n + 1
        if n > 40 then out["…"] = "more fields" break end
        if not (type(k) == "number" and k > 2) then
            out[tostring(k)] = shape(x, depth + 1)
        end
    end
    return out
end

local function call(fn, ...)
    if type(fn) ~= "function" then return "missing" end
    local ok, a, b = pcall(fn, ...)
    if not ok then return "error: " .. tostring(a):sub(1, 160) end
    if b ~= nil or isSecret(b) then return { shape(a), shape(b) } end
    return shape(a)
end

-- The documentation: functions, events and tables of the meter and death recap.
local function docs()
    if not (ns.ApiDocs and ns.ApiDocs.Dump) then return "ApiDocs missing" end
    local lines, err = ns.ApiDocs.Dump({ "damagemeter", "deathrecap" })
    return lines or err
end

-- Event names from the documentation (DAMAGE_METER…, DEATH_RECAP…).
local function eventNames()
    local names = {}
    local docsTable = _G.APIDocumentation
    if not (docsTable and type(docsTable.systems) == "table") then return names end
    for _, sys in ipairs(docsTable.systems) do
        for _, e in ipairs(sys.Events or {}) do
            local n = e.LiteralName
            if type(n) == "string" and (n:find("DAMAGE_METER") or n:find("DEATH_RECAP") or n:find("COMBAT_SESSION")) then
                names[#names + 1] = n
            end
        end
    end
    return names
end

local function watchEvents()
    if eventFrame then return end
    eventFrame = CreateFrame("Frame")
    eventCounts, eventPayloads = {}, {}
    local registered = {}
    for _, n in ipairs(eventNames()) do
        if pcall(eventFrame.RegisterEvent, eventFrame, n) then registered[#registered + 1] = n end
    end
    eventFrame:SetScript("OnEvent", function(_, event, ...)
        eventCounts[event] = (eventCounts[event] or 0) + 1
        if not eventPayloads[event] then eventPayloads[event] = shape({ ... }) end
    end)
    return registered
end

-- Globals named like the Blizzard meter (frames, mixins, tables).
local function globals()
    local out = {}
    for k, v in pairs(_G) do
        if type(k) == "string" and k:find("DamageMeter") then
            local t = type(v)
            if t == "table" and v.GetObjectType then
                local ok, ot = pcall(v.GetObjectType, v)
                t = ok and ("frame " .. tostring(ot)) or "frame?"
                local okShown, shown = pcall(v.IsShown, v)
                if okShown then t = t .. (shown and ", shown" or ", hidden") end
            end
            out[k] = t
        end
    end
    return out
end

local function meterTypes()
    local list = {}
    for name, value in pairs(Enum.DamageMeterType or {}) do list[#list + 1] = { name = name, value = value } end
    table.sort(list, function(a, b) return a.value < b.value end)
    return list
end

function MP.Sample(label)
    SuuUIProbe = SuuUIProbe or {}
    local store = SuuUIProbe.meter or { samples = {} }
    SuuUIProbe.meter = store
    local DM = C_DamageMeter
    local ST = Enum.DamageMeterSessionType or {}
    local s = {
        at = date("%H:%M:%S"), label = label,
        combat = InCombatLockdown() and "in combat" or "out of combat",
        instance = select(2, IsInInstance()) or "none",
        group = IsInRaid() and "raid" or (IsInGroup() and "party" or "solo"),
    }
    if not DM then
        s.error = "no C_DamageMeter"
    else
        s.available = call(DM.IsDamageMeterAvailable)
        s.sessions = call(DM.GetAvailableCombatSessions)
        s.duration = {}
        for name, v in pairs(ST) do s.duration[name] = call(DM.GetSessionDurationSeconds, v) end
        -- every meter type of the current and the overall session
        s.current, s.overall = {}, {}
        for _, mt in ipairs(meterTypes()) do
            if ST.Current then s.current[mt.name] = call(DM.GetCombatSessionFromType, ST.Current, mt.value) end
            if ST.Overall and (mt.name == "DamageDone" or mt.name == "Deaths") then
                s.overall[mt.name] = call(DM.GetCombatSessionFromType, ST.Overall, mt.value)
            end
        end
        -- one source's breakdown: the first damage source of the current session
        local ok, sess = pcall(DM.GetCombatSessionFromType, ST.Current, Enum.DamageMeterType.DamageDone)
        local src = ok and type(sess) == "table" and not isSecretTable(sess) and type(sess.combatSources) == "table"
            and not isSecretTable(sess.combatSources) and sess.combatSources[1]
        if src then
            s.sourceBreakdown = call(DM.GetCombatSessionSourceFromType, ST.Current, Enum.DamageMeterType.DamageDone, src.sourceGUID)
            s.sourceBreakdownWithCreature = call(DM.GetCombatSessionSourceFromType, ST.Current, Enum.DamageMeterType.DamageDone,
                src.sourceGUID, src.sourceCreatureID)
        else
            s.sourceBreakdown = "no first source (" .. (ok and shape(sess) and "session read" or "session error") .. ")"
        end
        -- your own breakdown by your GUID (always readable)
        s.ownBreakdown = call(DM.GetCombatSessionSourceFromType, ST.Current, Enum.DamageMeterType.DamageDone, UnitGUID("player"))
        -- the combat restriction (lags combat's end) and Blizzard's meter switch
        if C_RestrictedActions and C_RestrictedActions.IsAddOnRestrictionActive and Enum.AddOnRestrictionType then
            s.restricted = call(C_RestrictedActions.IsAddOnRestrictionActive, Enum.AddOnRestrictionType.Combat)
        end
        s.cvarDamageMeterEnabled = call(C_CVar.GetCVar, "damageMeterEnabled")
        -- a session by ID: the first available one
        local okList, list = pcall(DM.GetAvailableCombatSessions)
        local first = okList and type(list) == "table" and not isSecretTable(list) and list[1]
        if first and first.sessionID ~= nil then
            s.byID = call(DM.GetCombatSessionFromID, first.sessionID, Enum.DamageMeterType.DamageDone)
        end
        -- a death recap, if the deaths list names one
        local okD, deaths = pcall(DM.GetCombatSessionFromType, ST.Overall, Enum.DamageMeterType.Deaths)
        local d = okD and type(deaths) == "table" and not isSecretTable(deaths) and type(deaths.combatSources) == "table"
            and not isSecretTable(deaths.combatSources) and deaths.combatSources[1]
        if d and C_DeathRecap then
            for _, fn in ipairs({ "GetRecapEvents", "GetRecapMaxHealth", "GetRecapLink", "HasRecapEvents" }) do
                if C_DeathRecap[fn] then s["deathRecap." .. fn] = call(C_DeathRecap[fn], d.deathRecapID) end
            end
        end
    end
    s.events = eventCounts and CopyTable(eventCounts) or nil
    table.insert(store.samples, s)
    while #store.samples > MAX_SAMPLES do table.remove(store.samples, 1) end
    return s
end

local function onFight()
    if not armed then return end
    C_Timer.After(2, function() if armed then MP.Sample("2s into the fight") end end)
    C_Timer.After(6, function()
        if armed then
            MP.Sample("6s into the fight")
            ns.Print("Meter probe: fight sampled. Finish it, then /reload.")
        end
    end)
end

local function afterFight()
    if armed then C_Timer.After(1, function() if armed then MP.Sample("after the fight") end end) end
end

function MP.Command(arg)
    if arg == "off" then
        armed = false
        ns.Print("Meter probe: off.")
        return
    end
    SuuUIProbe = SuuUIProbe or {}
    local store = SuuUIProbe.meter or { samples = {} }
    SuuUIProbe.meter = store
    store.docs = docs()
    store.registeredEvents = watchEvents() or store.registeredEvents
    store.eventPayloads = eventPayloads
    store.globals = globals()
    store.deathRecapAPI = C_DeathRecap and shape(C_DeathRecap) or "missing"
    if not armed then
        armed = true
        Events.OnGame("PLAYER_REGEN_DISABLED", onFight, MP)
        Events.OnGame("PLAYER_REGEN_ENABLED", afterFight, MP)
    end
    MP.Sample("on command")
    ns.Print("Meter probe: armed. Fight something for 10 seconds or more (die once if you can bear it), then /reload.")
end
