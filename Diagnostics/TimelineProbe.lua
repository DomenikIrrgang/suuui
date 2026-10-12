-- Diagnostics/TimelineProbe.lua
-- "/suu probe timeline": what Forever's encounter timeline gives an addon
-- (plan step 1.13). Once: the client's documentation of C_EncounterTimeline
-- (functions, events, tables), its enums, whether the feature is available
-- and enabled, the view type, and the timeline's events (registered, counted
-- with their first payloads). Per sample: tracks (info, type, longest
-- event), events (info, state, time left and gone, timer, track, colour,
-- blocked, highlight time), each value readable, secret or missing.
--
--   /suu probe timeline        arm: samples now, 3 and 10 seconds into each
--                              boss (ENCOUNTER_START) and fight, and when
--                              timeline events arrive; /reload to save
--   /suu probe timeline demo   solo: Blizzard's Edit Mode sample events and
--                              one scripted event of SuuUI's own (adds them,
--                              samples 1 and 4 seconds later, removes them),
--                              plus every console variable about the timeline
--   /suu probe timeline off    stop sampling

local _, ns = ...

local Events = ns.Events

local TP = {}
ns.TimelineProbe = TP

local isSecret = issecretvalue or function() return false end
local isSecretTable = issecrettable or function() return false end
local MAX_SAMPLES = 14
local MAX_EVENTS = 8
local armed = false
local eventFrame, eventCounts, eventPayloads
local lastEventSample = 0

local function shape(v, depth)
    depth = depth or 0
    if isSecret(v) then return "secret" end
    if v == nil then return "nil" end
    local t = type(v)
    if t ~= "table" then return t .. ": " .. tostring(v):sub(1, 80) end
    if isSecretTable(v) then return "secret table" end
    if depth >= 4 then return "table (deeper)" end
    local out, n = {}, 0
    local count = #v
    if count > 0 then out["#"] = count end
    for k, x in pairs(v) do
        n = n + 1
        if n > 40 then out["…"] = "more fields" break end
        if not (type(k) == "number" and k > 3) then out[tostring(k)] = shape(x, depth + 1) end
    end
    return out
end

local function call(fn, ...)
    if type(fn) ~= "function" then return "missing" end
    local ok, a, b, c = pcall(fn, ...)
    if not ok then return "error: " .. tostring(a):sub(1, 160) end
    if b ~= nil or c ~= nil or isSecret(b) or isSecret(c) then return { shape(a), shape(b), shape(c) } end
    return shape(a)
end

local function eventNames()
    local names = {}
    local docs = _G.APIDocumentation
    if not (docs and type(docs.systems) == "table") then return names end
    for _, sys in ipairs(docs.systems) do
        for _, e in ipairs(sys.Events or {}) do
            local n = e.LiteralName
            if type(n) == "string" and n:find("ENCOUNTER_TIMELINE") then names[#names + 1] = n end
        end
    end
    for _, n in ipairs({ "ENCOUNTER_START", "ENCOUNTER_END", "BOSS_KILL" }) do names[#names + 1] = n end
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
        if not armed then return end
        if event == "ENCOUNTER_START" then
            C_Timer.After(3, function() if armed then TP.Sample("3s into the boss") end end)
            C_Timer.After(10, function()
                if armed then
                    TP.Sample("10s into the boss")
                    ns.Print("Timeline probe: boss sampled. /reload after the fight to save.")
                end
            end)
        elseif event:find("ENCOUNTER_TIMELINE") and GetTime() - lastEventSample > 5 then
            lastEventSample = GetTime()
            C_Timer.After(0.5, function() if armed then TP.Sample("after " .. event) end end)
        end
    end)
    return registered
end

local function enums()
    local out = {}
    for k, v in pairs(Enum) do
        if type(k) == "string" and k:find("^EncounterTimeline") and not k:find("Meta$") then out[k] = shape(v) end
    end
    return out
end

-- One event in full.
local function describeEvent(id)
    local ET = C_EncounterTimeline
    return {
        id = shape(id),
        info = call(ET.GetEventInfo, id),
        state = call(ET.GetEventState, id),
        remaining = call(ET.GetEventTimeRemaining, id),
        elapsed = call(ET.GetEventTimeElapsed, id),
        timer = call(ET.GetEventTimer, id),
        track = call(ET.GetEventTrack, id),
        color = call(ET.GetEventColor, id),
        blocked = call(ET.IsEventBlocked, id),
        highlight = call(ET.GetEventHighlightTime, id),
    }
end

function TP.Sample(label)
    SuuUIProbe = SuuUIProbe or {}
    local store = SuuUIProbe.timeline or { samples = {} }
    SuuUIProbe.timeline = store
    local ET = C_EncounterTimeline
    local s = {
        at = date("%H:%M:%S"), label = label,
        combat = InCombatLockdown() and "in combat" or "out of combat",
        instance = select(2, IsInInstance()) or "none",
        group = IsInRaid() and "raid" or (IsInGroup() and "party" or "solo"),
    }
    if not ET then
        s.error = "no C_EncounterTimeline"
    else
        s.available = call(ET.IsFeatureAvailable)
        s.enabled = call(ET.IsFeatureEnabled)
        s.viewType = call(ET.GetViewType)
        s.now = call(ET.GetCurrentTime)
        s.hasAny = call(ET.HasAnyEvents)
        s.hasActive = call(ET.HasActiveEvents)
        s.hasVisible = call(ET.HasVisibleEvents)
        s.hasPaused = call(ET.HasPausedEvents)
        -- tracks
        s.tracks = {}
        local okT, tracks = pcall(ET.GetTrackList)
        s.trackList = okT and shape(tracks) or ("error: " .. tostring(tracks))
        if okT and type(tracks) == "table" and not isSecretTable(tracks) then
            for i, t in ipairs(tracks) do
                if i > 6 then break end
                s.tracks[i] = { id = shape(t), info = call(ET.GetTrackInfo, t), type = call(ET.GetTrackType, t),
                    longest = call(ET.GetTrackMaxEventDuration, t) }
            end
        end
        -- events
        s.events = {}
        local okE, list = pcall(ET.GetEventList)
        s.eventList = okE and shape(list) or ("error: " .. tostring(list))
        s.sortedList = call(ET.GetSortedEventList)
        if okE and type(list) == "table" and not isSecretTable(list) then
            for i, id in ipairs(list) do
                if i > MAX_EVENTS then break end
                s.events[i] = describeEvent(id)
            end
        end
    end
    s.eventCounts = eventCounts and CopyTable(eventCounts) or nil
    table.insert(store.samples, s)
    while #store.samples > MAX_SAMPLES do table.remove(store.samples, 1) end
    return s
end

-- Console variables whose name mentions the timeline or encounters.
local function cvars()
    local out = {}
    if not (C_Console and C_Console.GetAllCommands) then return "no C_Console.GetAllCommands" end
    local ok, all = pcall(C_Console.GetAllCommands)
    if not ok or type(all) ~= "table" then return "error" end
    for _, c in ipairs(all) do
        local name = c.command
        if type(name) == "string" then
            local low = name:lower()
            if low:find("timeline") or low:find("encounter") or low:find("bossmod") or low:find("raidwarn") then
                local okV, v = pcall(C_CVar.GetCVar, name)
                out[name] = okV and tostring(v) or "(command)"
            end
        end
    end
    return out
end

local function prepare()
    SuuUIProbe = SuuUIProbe or {}
    local store = SuuUIProbe.timeline or { samples = {} }
    SuuUIProbe.timeline = store
    if ns.ApiDocs and ns.ApiDocs.Dump then store.docs = ns.ApiDocs.Dump({ "encountertimeline" }) end
    store.enums = enums()
    store.registeredEvents = watchEvents() or store.registeredEvents
    store.eventPayloads = eventPayloads
    store.blizzardAddon = C_AddOns.IsAddOnLoaded("Blizzard_EncounterTimeline") and "loaded" or "not loaded"
    store.cvars = cvars()
    return store
end

function TP.Command(arg)
    if arg == "off" then
        armed = false
        ns.Print("Timeline probe: off.")
        return
    end
    prepare()
    local ET = C_EncounterTimeline
    if arg == "demo" then
        if not ET then ns.Print("Timeline probe: no C_EncounterTimeline.") return end
        TP.Sample("before the demo")
        SuuUIProbe.timeline.demoAdd = call(ET.AddEditModeEvents)
        -- one event of our own: Shield Wall's spell and art, 10 seconds
        local okS, id = pcall(ET.AddScriptEvent, { spellID = 871, iconFileID = 132362, duration = 10, overrideName = "SuuUI test" })
        SuuUIProbe.timeline.scriptAdd = okS and shape(id) or ("error: " .. tostring(id))
        local scriptID = okS and not isSecret(id) and id or nil
        C_Timer.After(1, function()
            TP.Sample("demo, 1s")
            C_Timer.After(3, function()
                TP.Sample("demo, 4s")
                SuuUIProbe.timeline.demoCancel = call(ET.CancelEditModeEvents)
                if scriptID then SuuUIProbe.timeline.scriptCancel = call(ET.CancelScriptEvent, scriptID) end
                ns.Print("Timeline probe: demo sampled. /reload to save.")
            end)
        end)
        ns.Print("Timeline probe: demo events added; sampling for 4 seconds.")
        return
    end
    if not armed then
        armed = true
        Events.OnGame("PLAYER_REGEN_DISABLED", function()
            if not armed then return end
            C_Timer.After(3, function() if armed then TP.Sample("3s into the fight") end end)
        end, TP)
    end
    TP.Sample("on command")
    ns.Print("Timeline probe: armed. Fight a dungeon boss, then /reload. (Solo first look: /suu probe timeline demo)")
end
