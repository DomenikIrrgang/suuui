-- Units/Timeline.lua
-- The encounter timeline (step 1.13): top centre, 28px down, now at the
-- left, the next 30 seconds to the right. It shows whatever the game's
-- encounter timeline holds (C_EncounterTimeline): boss abilities if the game
-- sends them (Forever has the feature off, 2026-10-12) and the timers addons
-- add to it, SuuUI's pull countdown first. Hidden while nothing is on it.
--
-- The pull countdown: "/suu pull [seconds]" (default 10; 0 cancels). It
-- rides the timeline as "Pull", counts down as an alert (out of combat too;
-- setting: the whole countdown, the last ten seconds or none) and says
-- "Pull!" at zero. Combat cancels it.
-- It is Blizzard's own countdown (C_PartyInfo.DoCountdown, the /countdown
-- one), which DBM and BigWigs use too: a countdown anyone starts (SuuUI, DBM,
-- BigWigs, /countdown) shows here, and SuuUI's shows in theirs and, without
-- any addon, as Blizzard's numbers. While SuuUI's alert shows the countdown,
-- Blizzard's own numbers (TimerTracker) stay away, as BigWigs does it. On a
-- client without it, SuuUI sends its own message to everyone with SuuUI.

local UI, T = SuuUI.UI, SuuUI.Tokens

local M = SuuUI.RegisterModule({
    id = "timeline",
    name = "Encounter timeline",
    description = "Upcoming boss abilities and SuuUI's pull countdown riding toward now, top centre.",
    api = "0.10",
    combatSafe = true,
    defaults = {
        position = { point = "TOP", x = 0, y = -28 },
        variant = "track",   -- "track" | "list" | "off"
        pullSeconds = 10,
        pullAlert = "all",   -- "all" | "last10" | "off": the countdown as an alert
        pullVoice = "Bella", -- a voice in Media/Sounds/Countdown, or "off": the last ten seconds spoken
        source = "suui",     -- "suui" | "dbm" | "bigwigs": where boss timers come from
        hideTheirs = true,   -- with a boss mod as the source: its own bars (and DBM's warnings) hidden
        dbmWarningsWas = "", -- DBM's HideDBMWarnings before SuuUI set it ("" none)
    },
})

-- The first voices (borrowed for a day) gave way to SuuUI's own.
M:Migrate("pullVoice-kokoro-3", function(values)
    local v = values.pullVoice
    if v == "David" or v == "Male" or v == "Fenrir" or v == "Puck" then values.pullVoice = "Michael"
    elseif v == "Jim" or v == "Female" then values.pullVoice = "Bella" end
end)

-- "Last 5 seconds" became "Last 10 seconds".
M:Migrate("pullAlert-last10", function(values)
    if values.pullAlert == "last5" then values.pullAlert = "last10" end
end)

local isSecret = issecretvalue or function() return false end
local function readable(v) return not isSecret(v) and type(v) == "number" end

local PREFIX = "SuuUI"
local PULL_SPELL, PULL_ICON = 100, 132337 -- Charge's spell and art
local ET = C_EncounterTimeline

-- The role and danger icons an ability carries (EncounterEventIconmask, one
-- bit per Enum.EncounterTimelineIconSet value), as the design's badges.
local BADGES = {
    { "TankAlert", "warning", "Tank" }, { "Deadly", "danger", "Lethal" }, { "HealerAlert", "info", "Healer" },
    { "Dispel", "magic", "Dispel" }, { "Enrage", "warning", "Enrage" },
}
local function badgeOf(mask)
    if not readable(mask) or mask == 0 or not Enum.EncounterTimelineIconSet then return nil end
    for _, b in ipairs(BADGES) do
        local v = Enum.EncounterTimelineIconSet[b[1]]
        if v and bit.band(mask, bit.lshift(1, v)) ~= 0 then return { tone = b[2], text = b[3] } end
    end
end

--------------------------------------------------------------------------------
-- The timeline's events
--------------------------------------------------------------------------------

local ACTIVE, PAUSED = 0, 1

--------------------------------------------------------------------------------
-- Boss mods as a source: DBM's timer callbacks, BigWigs' bar messages. Only
-- the ones loaded are offered; a source that's gone falls back to SuuUI.
--------------------------------------------------------------------------------

local function plain(v) return not isSecret(v) and type(v) == "string" and v ~= "" end
local function iconOf(v)
    if isSecret(v) then return nil end
    return tonumber(v) or (type(v) == "string" and v ~= "" and v) or nil
end
-- a boss mod's own pull bar: SuuUI's countdown shows the pull already
local function isPull(text) return plain(text) and text:lower():find("^pull") ~= nil end

local SOURCES = {
    dbm = { label = "DBM", loaded = function() return DBM and DBM.RegisterCallback and true or false end },
    bigwigs = { label = "BigWigs", loaded = function() return BigWigsLoader and BigWigsLoader.RegisterMessage and true or false end },
}

function M:SourceOptions()
    local opts = { { value = "suui", label = "SuuUI" } }
    for _, key in ipairs({ "dbm", "bigwigs" }) do
        if SOURCES[key].loaded() then opts[#opts + 1] = { value = key, label = SOURCES[key].label } end
    end
    return opts
end

-- The boss mod's timers, by its own id: { label, icon, badge, endsAt or paused }
function M:AddonTimer(source, id, text, seconds, icon, badge)
    if self:Get("source") ~= source or not readable(seconds) or seconds <= 0 or isPull(text) then return end
    self.addonTimers = self.addonTimers or {}
    self.addonTimers[id] = { id = "addon:" .. tostring(id), label = plain(text) and text or "", icon = iconOf(icon),
                             badge = badge, endsAt = GetTime() + seconds }
    self:Refresh()
end

function M:AddonTimerStop(source, id)
    if self:Get("source") ~= source or not self.addonTimers then return end
    if id == nil then self.addonTimers = {} else self.addonTimers[id] = nil end
    self:Refresh()
end

function M:AddonTimerPause(source, id, paused)
    local t = self:Get("source") == source and self.addonTimers and self.addonTimers[id]
    if not t then return end
    if paused and t.endsAt then
        t.paused, t.endsAt = math.max(0, t.endsAt - GetTime()), nil
    elseif not paused and t.paused then
        t.endsAt, t.paused = GetTime() + t.paused, nil
    end
    self:Refresh()
end

--------------------------------------------------------------------------------
-- Their own display, hidden while they feed the timeline (setting).
-- DBM: its HideDBMWarnings option (warnings and announces; kept and handed
-- back), and each bar DBT makes kept at alpha 0 (its HideDBMBars would stop
-- the timers themselves, callbacks included). BigWigs: each LibCandyBar bar
-- it starts kept at alpha 0. BigWigs' messages have no way in from outside.
--------------------------------------------------------------------------------

function M:Suppressing(source)
    return self:IsEnabled() and self:Get("hideTheirs") and self:Get("source") == source
end

-- keep a frame invisible while `test()` says so (one hook per frame)
local function keepHidden(frame, test)
    if not frame then return end
    frame.suuHideTest = test
    if not frame.suuHideHooked then
        frame.suuHideHooked = true
        hooksecurefunc(frame, "SetAlpha", function(f, a)
            if a > 0 and f.suuHideTest and f.suuHideTest() then f:SetAlpha(0) end
        end)
    end
    if test() then frame:SetAlpha(0) end
end

function M:ApplySuppression()
    -- DBM's warnings: on while DBM feeds the timeline, your own setting back otherwise
    if DBM and DBM.Options then
        local want = self:Suppressing("dbm")
        local was = self:Get("dbmWarningsWas")
        if want and was == "" then
            self:Set("dbmWarningsWas", DBM.Options.HideDBMWarnings and "true" or "false")
            DBM.Options.HideDBMWarnings = true
        elseif not want and was ~= "" then
            DBM.Options.HideDBMWarnings = was == "true"
            self:Set("dbmWarningsWas", "")
        end
    end
end

-- Each part once, as soon as its library is there (BigWigs loads its
-- plugins, LibCandyBar with them, on demand: tried again on ADDON_LOADED).
function M:HookDisplays()
    self.hookedParts = self.hookedParts or {}
    local hooked = self.hookedParts
    -- DBM's bars
    if not hooked.dbt and DBT and type(DBT.CreateBar) == "function" then
        hooked.dbt = true
        local create = DBT.CreateBar
        DBT.CreateBar = function(dbt, ...)
            local bar = create(dbt, ...)
            if type(bar) == "table" and bar.frame then
                keepHidden(bar.frame, function() return M:Suppressing("dbm") end)
            end
            return bar
        end
    end
    -- BigWigs' bars (LibCandyBar, shared: only bars BigWigs tags as its own)
    local candy = not hooked.candy and LibStub and LibStub("LibCandyBar-3.0", true)
    if candy and candy.barPrototype and candy.barPrototype.Start then
        hooked.candy = true
        hooksecurefunc(candy.barPrototype, "Start", function(bar)
            if bar.Get and bar:Get("bigwigs:module") ~= nil then
                keepHidden(bar, function() return M:Suppressing("bigwigs") end)
            else
                -- the pool is shared: another addon's bar shows as it likes
                bar.suuHideTest = nil
            end
        end)
    end
end

-- DBM's timer types (colorId): 4 interrupt, 5 role (tank).
local DBM_BADGE = { [4] = { tone = "info", text = "Kick" }, [5] = { tone = "warning", text = "Tank" } }

function M:HookSources()
    if self.hooked then return end
    self.hooked = true
    if SOURCES.dbm.loaded() then
        pcall(DBM.RegisterCallback, DBM, "DBM_TimerBegin", function(_, id, msg, timer, icon, _, _, colorId)
            self:AddonTimer("dbm", id, msg, timer, icon, readable(colorId) and DBM_BADGE[colorId] or nil)
        end)
        pcall(DBM.RegisterCallback, DBM, "DBM_TimerStop", function(_, id) self:AddonTimerStop("dbm", id) end)
        pcall(DBM.RegisterCallback, DBM, "DBM_TimerPause", function(_, id) self:AddonTimerPause("dbm", id, true) end)
        pcall(DBM.RegisterCallback, DBM, "DBM_TimerResume", function(_, id) self:AddonTimerPause("dbm", id, false) end)
        pcall(DBM.RegisterCallback, DBM, "DBM_TimerUpdate", function(_, id, elapsed, total)
            local t = self:Get("source") == "dbm" and self.addonTimers and self.addonTimers[id]
            if t and readable(elapsed) and readable(total) then
                t.endsAt, t.paused = GetTime() + math.max(0, total - elapsed), nil
                self:Refresh()
            end
        end)
    end
    if SOURCES.bigwigs.loaded() then
        -- BigWigs keys its bars by module and text
        local owner = {}
        local function key(module, text) return tostring(module) .. "\31" .. (plain(text) and text or "?") end
        local reg = BigWigsLoader.RegisterMessage
        pcall(reg, owner, "BigWigs_StartBar", function(_, module, _, text, time, icon)
            self:AddonTimer("bigwigs", key(module, text), text, time, icon)
        end)
        pcall(reg, owner, "BigWigs_StopBar", function(_, module, text) self:AddonTimerStop("bigwigs", key(module, text)) end)
        pcall(reg, owner, "BigWigs_StopBars", function() self:AddonTimerStop("bigwigs", nil) end)
        pcall(reg, owner, "BigWigs_PauseBar", function(_, module, text) self:AddonTimerPause("bigwigs", key(module, text), true) end)
        pcall(reg, owner, "BigWigs_ResumeBar", function(_, module, text) self:AddonTimerPause("bigwigs", key(module, text), false) end)
    end
end

-- Everything on the timeline, as the component's list: the game's timeline
-- (with a boss mod as the source, only SuuUI's own timers from it: the pull)
-- and the chosen boss mod's timers. One whose time is secret can't be
-- placed, so it's left out.
function M:Read()
    local list = {}
    local now = GetTime()
    local source = self:Get("source")
    if source ~= "suui" then
        for id, t in pairs(self.addonTimers or {}) do
            if t.paused or (t.endsAt and t.endsAt > now) then list[#list + 1] = t else self.addonTimers[id] = nil end
        end
    end
    if not ET then return list end
    local ok, ids = pcall(ET.GetEventList)
    if not ok or type(ids) ~= "table" then return list end
    local SCRIPT = Enum.EncounterTimelineEventSource and Enum.EncounterTimelineEventSource.Script
    for _, id in ipairs(ids) do
        local okS, state = pcall(ET.GetEventState, id)
        local okR, left = pcall(ET.GetEventTimeRemaining, id)
        local okI, info = pcall(ET.GetEventInfo, id)
        if okS and okR and okI and readable(state) and (state == ACTIVE or state == PAUSED) and readable(left)
           and (left > 0 or state == PAUSED) and type(info) == "table"
           and (source == "suui" or not readable(info.source) or info.source == SCRIPT) then
            local label = info.spellName
            if isSecret(label) or type(label) ~= "string" then label = nil end
            local e = { id = id, label = (self.labels and self.labels[id]) or label or "", icon = readable(info.iconFileID) and info.iconFileID or nil,
                        badge = (self.badges and self.badges[id]) or badgeOf(info.icons) }
            if state == PAUSED then e.paused = left else e.endsAt = now + left end
            list[#list + 1] = e
        end
    end
    return list
end

function M:Refresh()
    if not self.timeline then return end
    local variant = self:Get("variant")
    local events = self:Read()
    local shown = variant ~= "off" and not self:Get("position").hidden and #events > 0
    if shown then
        self.timeline:SetVariant(variant)
        self.timeline:SetEvents(events)
    else
        self.timeline:SetEvents({})
    end
    self.timeline:SetShown(shown and true or false)
    -- read again when the soonest one runs out (it leaves the timeline)
    local soonest
    for _, e in ipairs(events) do
        if e.endsAt and (not soonest or e.endsAt < soonest) then soonest = e.endsAt end
    end
    if soonest then
        local token = {}
        self.refreshToken = token
        C_Timer.After(math.max(0.05, soonest - GetTime() + 0.05), function()
            if self.refreshToken == token and self:IsEnabled() then self:Refresh() end
        end)
    end
end

--------------------------------------------------------------------------------
-- The pull countdown
--------------------------------------------------------------------------------

--------------------------------------------------------------------------------
-- The countdown voice: the last ten seconds and "Pull!" spoken
-- (Media/Sounds/Countdown: SuuUI's own, generated with Kokoro-82M, Apache-2.0
-- weights, see its license.txt and tools/gen_countdown_voice.py). Addon
-- sound files play on Forever (game-data paths don't). Quiet while a boss
-- mod feeds the timeline: it counts out loud itself then.
--------------------------------------------------------------------------------

local VOICES = { Heart = true, Bella = true, Michael = true }
local VOICE_PATH = "Interface\\AddOns\\SuuUI\\Media\\Sounds\\Countdown\\%s\\%s.ogg"

-- n: 1-10, or "pull"
function M:Speak(n, voice)
    voice = voice or self:Get("pullVoice")
    if not VOICES[voice] then return end
    if n ~= "pull" and (n < 1 or n > 10) then return end
    pcall(PlaySoundFile, VOICE_PATH:format(voice, tostring(n)), "Master")
end

-- Each of the last ten seconds on the second, then "Pull!".
function M:ScheduleVoice(seconds, token)
    local voice = self:Get("pullVoice")
    if not VOICES[voice] or self:Get("source") ~= "suui" then return end
    for n = math.min(10, math.floor(seconds)), 1, -1 do
        C_Timer.After(seconds - n, function()
            if self.voiceToken == token then self:Speak(n, voice) end
        end)
    end
    C_Timer.After(seconds, function()
        if self.voiceToken == token then self:Speak("pull", voice) end
    end)
end

function M:CancelPull(quiet)
    self.voiceToken = nil
    if self.pullID and ET then pcall(ET.CancelScriptEvent, self.pullID) end
    self.pullID = nil
    self.pullEnds = nil
    if self.pullTicker then self.pullTicker:Cancel(); self.pullTicker = nil end
    SuuUI.HideAlert("pull")
    if not quiet then self:Refresh() end
end

function M:StartPull(seconds, from)
    self:CancelPull(true)
    seconds = math.floor(tonumber(seconds) or 0)
    if seconds <= 0 then
        self:Refresh()
        return
    end
    seconds = math.min(seconds, 60)
    if ET and ET.AddScriptEvent then
        local ok, id = pcall(ET.AddScriptEvent, { spellID = PULL_SPELL, iconFileID = PULL_ICON, duration = seconds, overrideName = "Pull" })
        if ok and readable(id) then
            self.pullID = id
            self.labels = self.labels or {}
            self.labels[id] = "Pull"
        end
    end
    local endsAt = GetTime() + seconds
    self.pullEnds = endsAt
    local token = {}
    self.voiceToken = token
    self:ScheduleVoice(seconds, token)
    local detail = from and ("from " .. from) or nil
    -- the countdown as an alert (all of it, or the last ten seconds), then "Pull!"
    local mode = self:Get("pullAlert")
    local function tick()
        local left = endsAt - GetTime()
        if left <= 0 then
            if mode ~= "off" then
                SuuUI.ShowAlert("pull", "info", "Pull!", detail)
                C_Timer.After(1.5, function() SuuUI.HideAlert("pull") end)
            end
            if self.pullTicker then self.pullTicker:Cancel() end
            self.pullTicker = nil
            self.pullID = nil
            self.pullEnds = nil
        elseif mode == "all" or (mode == "last10" and left <= 10) then
            SuuUI.ShowAlert("pull", "info", ("Pull in %d"):format(math.ceil(left)), detail)
        end
    end
    self.pullTicker = C_Timer.NewTicker(0.25, tick)
    tick()
    self:Refresh()
end

-- Who may start one for the group: the leader or an assistant (anyone in a
-- party without a leader flag).
local function canLead()
    if not UI.Flag(IsInGroup()) then return true end
    if UI.Flag(UnitIsGroupLeader("player")) or UI.Flag(UnitIsGroupAssistant("player")) then return true end
    return not UI.Flag(IsInRaid())
end

local function blizzardCountdown()
    return C_PartyInfo and C_PartyInfo.DoCountdown
end

function M:Pull(arg)
    local seconds = math.floor(tonumber(arg) or self:Get("pullSeconds"))
    if UI.Flag(IsInGroup()) and not canLead() then
        self:Print("Only the leader or an assistant can start a pull countdown in a raid.")
        return
    end
    -- Blizzard's countdown: everyone's START_PLAYER_COUNTDOWN (ours too) starts it
    local doCountdown = blizzardCountdown()
    if doCountdown then
        -- armed before the call: the client fires START_PLAYER_COUNTDOWN inside
        -- it, before it returns (2026-10-12); without that event, ours anyway
        local token = {}
        self.awaiting = token
        if pcall(doCountdown, math.max(0, seconds)) then
            if seconds <= 0 then self.awaiting = nil; self:CancelPull() return end
            C_Timer.After(0.5, function()
                if self.awaiting == token then
                    self.awaiting = nil
                    if not self.pullEnds then self:StartPull(seconds) end
                end
            end)
            return
        end
        self.awaiting = nil
    end
    if UI.Flag(IsInGroup()) then
        local channel = UI.Flag(IsInRaid()) and "RAID" or "PARTY"
        pcall(C_ChatInfo.SendAddonMessage, PREFIX, ("PULL\t%d"):format(seconds), channel)
    end
    self:StartPull(seconds)
end

-- Blizzard's countdown started or cancelled (by anyone: SuuUI, DBM,
-- BigWigs, /countdown).
function M:OnCountdown(guid, seconds, ...)
    -- what the client sends (kept for /reload: SuuUIProbe.countdown)
    SuuUIProbe = SuuUIProbe or {}
    SuuUIProbe.countdown = SuuUIProbe.countdown or {}
    local args = { guid, seconds, ... }
    local shown = {}
    for i = 1, select("#", ...) + 2 do
        local v = args[i]
        shown[i] = isSecret(v) and "secret" or tostring(v)
    end
    table.insert(SuuUIProbe.countdown, { at = GetTime(), args = shown })
    while #SuuUIProbe.countdown > 12 do table.remove(SuuUIProbe.countdown, 1) end
    -- ours arrived (or anyone's): no fallback start
    self.awaiting = nil
    if isSecret(guid) or isSecret(seconds) or not readable(seconds) then return end
    if InCombatLockdown() then return end
    -- the same countdown again (the event can come more than once): keep it
    if self.pullEnds and math.abs(GetTime() + seconds - self.pullEnds) < 1.5 then return end
    local from
    if type(guid) == "string" and guid ~= UnitGUID("player") and GetPlayerInfoByGUID then
        local ok, _, _, _, _, _, name = pcall(GetPlayerInfoByGUID, guid)
        if ok and not isSecret(name) and type(name) == "string" then from = name end
    end
    self:StartPull(seconds, from)
end

-- Blizzard's big countdown numbers, kept away while SuuUI's alert counts.
function M:BlizzardNumbers(show)
    local tracker = TimerTracker
    if not tracker then return end
    if show then
        if self.trackerOff then
            pcall(tracker.RegisterEvent, tracker, "START_PLAYER_COUNTDOWN")
            pcall(tracker.RegisterEvent, tracker, "CANCEL_PLAYER_COUNTDOWN")
            self.trackerOff = nil
        end
    elseif not self.trackerOff then
        pcall(tracker.UnregisterEvent, tracker, "START_PLAYER_COUNTDOWN")
        pcall(tracker.UnregisterEvent, tracker, "CANCEL_PLAYER_COUNTDOWN")
        self.trackerOff = true
    end
end

function M:OnMessage(prefix, text, _, sender)
    if prefix ~= PREFIX or type(text) ~= "string" or isSecret(text) then return end
    local seconds = text:match("^PULL\t(%-?%d+)$")
    if not seconds then return end
    if isSecret(sender) or type(sender) ~= "string" then return end
    -- our own message comes back: already started
    local me = Ambiguate(SuuUI.FullName("player"), "short")
    if Ambiguate(sender, "short") == me then return end
    self:StartPull(tonumber(seconds), Ambiguate(sender, "short"))
end

--------------------------------------------------------------------------------
-- A test: four abilities and one past the window, on the real timeline
--------------------------------------------------------------------------------

local TEST = {
    { 871, 132362, 4, "Shield Wall", { tone = "warning", text = "Tank" } },
    { 122, 135848, 11, "Frost Nova" },
    { 5740, 136186, 19, "Rain of Fire", { tone = "info", text = "Spread" } },
    { 6789, 136145, 26, "Death Coil", { tone = "danger", text = "Lethal" } },
    { 1680, 132369, 44, "Whirlwind" },
}

function M:Test()
    if not (ET and ET.AddScriptEvent) then
        self:Print("This client has no encounter timeline.")
        return
    end
    self.labels, self.badges = self.labels or {}, self.badges or {}
    for _, t in ipairs(TEST) do
        local ok, id = pcall(ET.AddScriptEvent, { spellID = t[1], iconFileID = t[2], duration = t[3], overrideName = t[4] })
        if ok and readable(id) then
            self.labels[id], self.badges[id] = t[4], t[5]
        end
    end
    self:Refresh()
end

--------------------------------------------------------------------------------
-- Settings
--------------------------------------------------------------------------------

function M:PreviewView(parent)
    if not self.preview then
        self.preview = UI.EncounterTimeline(parent, { variant = "track" })
    end
    local p = self.preview
    p:SetParent(parent)
    local variant = self:Get("variant")
    p:SetVariant(variant == "list" and "list" or "track")
    local now = GetTime()
    local list = {}
    for i, t in ipairs(TEST) do list[i] = { id = -i, label = t[4], icon = t[2], badge = t[5], paused = t[3] } end
    p:SetEvents(list)
    p:SetMeta("Ashmaw the Devourer")
    return p
end

local SECTION = {
    id = "timeline", label = "Timeline", category = "Insights", order = 30,
    preview = function(parent) return M:PreviewView(parent) end,
    groups = {
        { title = "Encounter timeline", description = "What's coming, riding toward now: boss abilities when the game sends them (Forever doesn't yet) and SuuUI's pull countdown. Hidden while nothing is on it.", rows = {
            { key = "variant", label = "Show", control = "segmented", stacked = true,
              options = { { value = "track", label = "Timeline" }, { value = "list", label = "List" }, { value = "off", label = "Off" } },
              description = "Timeline: a line across the top of the screen, the next 30 seconds. List: the older panel, soonest first." },
            { label = "Try it", control = "button", text = "Show a test timeline",
              description = "Five abilities on the real timeline, the last one past its 30 seconds.",
              onClick = function() M:Test() end },
        } },
        { title = "Boss timers", rows = {
            { key = "source", label = "From", control = "segmented", stacked = true,
              options = { { value = "suui", label = "SuuUI" } },
              description = function()
                  local missing = {}
                  for _, key in ipairs({ "dbm", "bigwigs" }) do
                      if not SOURCES[key].loaded() then missing[#missing + 1] = SOURCES[key].label end
                  end
                  local text = "SuuUI: the game's own timeline (Forever sends no boss data yet) and SuuUI's timers. A boss mod: its boss timers ride the timeline, SuuUI's pull countdown too; you can turn its own bars off in its settings."
                  if #missing > 0 then text = text .. " Install " .. table.concat(missing, " or ") .. " to use " .. (#missing > 1 and "theirs" or "its") .. "." end
                  return text
              end },
            { key = "hideTheirs", label = "Hide their bars", control = "toggle",
              disabled = function() return M:Get("source") == "suui", "Choose DBM or BigWigs first." end,
              description = "While a boss mod feeds the timeline, its own timer bars stay hidden; DBM's warnings too (its \"Hide DBM warnings\" option, given back when you switch). BigWigs' messages can't be hidden from outside: turn them off in BigWigs if you like." },
        } },
        { title = "Pull countdown", description = "/suu pull starts it (/suu pull 15 for 15 seconds, /suu pull 0 cancels). It is the game's own countdown, the one DBM and BigWigs use: in a group, the leader's or an assistant's reaches everyone (their boss mods show it, players without addons see the game's numbers), and theirs shows here. Combat ends it.", rows = {
            { key = "pullSeconds", label = "Length", control = "slider", min = 5, max = 30, step = 1, unit = "s" },
            { key = "pullAlert", label = "Alert", control = "segmented", stacked = true,
              options = { { value = "all", label = "Whole countdown" }, { value = "last10", label = "Last 10 seconds" }, { value = "off", label = "Off" } },
              description = "The countdown in the middle of the screen, then \"Pull!\". Off: only on the timeline." },
            { key = "pullVoice", label = "Voice", control = "segmented",
              options = { { value = "Bella", label = "Bella" }, { value = "Heart", label = "Heart" }, { value = "Michael", label = "Michael" },
                          { value = "off", label = "Off" } }, stacked = true,
              description = "The last ten seconds and \"Pull!\" spoken. Quiet while DBM or BigWigs feeds the timeline (Boss timers): it counts out loud itself then." },
            { label = "Listen", control = "button", text = "Hear the voice",
              disabled = function() return M:Get("pullVoice") == "off", "Choose a voice first." end,
              onClick = function()
                  local voice = M:Get("pullVoice")
                  for i, n in ipairs({ 3, 2, 1, "pull" }) do C_Timer.After(i - 1, function() M:Speak(n, voice) end) end
              end },
            { label = "Start one", control = "button", text = "Start a pull countdown",
              onClick = function() M:Pull() end },
        } },
    },
}

function M:OnEnable()
    -- the boss mods loaded now; a chosen one that's gone: back to SuuUI
    local options = self:SourceOptions()
    local available = {}
    for _, o in ipairs(options) do available[o.value] = true end
    if not available[self:Get("source")] then self:Set("source", "suui") end
    for _, g in ipairs(SECTION.groups) do
        for _, row in ipairs(g.rows) do
            if row.key == "source" then row.options = options end
        end
    end
    self:HookSources()
    self:HookDisplays()
    self:ApplySuppression()
    self:OnGameEvent("ADDON_LOADED", function() self:HookDisplays() end)
    if not self.timeline then
        self.timeline = UI.EncounterTimeline(SuuUI.Root, { variant = self:Get("variant") == "list" and "list" or "track" })
        self.timeline:SetFrameStrata("MEDIUM")
        self.timeline:Hide()
    end
    self.timeline.suuManagedShow = true
    self:RegisterMover(self.timeline, { key = "position", label = "Encounter timeline",
        enabled = function() return self:Get("variant") ~= "off" end })
    self:RegisterSettings(SECTION)
    self:RegisterCommand("pull", "Start a pull countdown: /suu pull [seconds] (0 cancels).", function(arg) self:Pull(arg) end)
    SuuUI.AllowAlertOutOfCombat("pull")
    if C_ChatInfo and C_ChatInfo.RegisterAddonMessagePrefix then C_ChatInfo.RegisterAddonMessagePrefix(PREFIX) end
    self:OnGameEvent("CHAT_MSG_ADDON", function(_, ...) self:OnMessage(...) end)
    local valid = C_EventUtils and C_EventUtils.IsEventValid
    for _, e in ipairs({ "ENCOUNTER_TIMELINE_EVENT_ADDED", "ENCOUNTER_TIMELINE_EVENT_REMOVED", "ENCOUNTER_TIMELINE_EVENT_STATE_CHANGED",
                         "ENCOUNTER_TIMELINE_EVENT_TRACK_CHANGED", "ENCOUNTER_TIMELINE_STATE_UPDATED" }) do
        if not valid or valid(e) then self:OnGameEvent(e, function() self:Refresh() end) end
    end
    self:OnGameEvent("PLAYER_REGEN_DISABLED", function() if self.pullTicker then self:CancelPull() end end)
    if not valid or valid("START_PLAYER_COUNTDOWN") then
        self:OnGameEvent("START_PLAYER_COUNTDOWN", function(_, ...) self:OnCountdown(...) end)
        self:OnGameEvent("CANCEL_PLAYER_COUNTDOWN", function() self:CancelPull() end)
    end
    self:BlizzardNumbers(self:Get("pullAlert") == "off")
    self:Watch("pullAlert", function() self:BlizzardNumbers(self:Get("pullAlert") == "off") end)
    self:Watch("source", function() self.addonTimers = {}; self:ApplySuppression(); self:Refresh() end)
    self:Watch("hideTheirs", function() self:ApplySuppression() end)
    for _, key in ipairs({ "variant", "position" }) do
        self:Watch(key, function()
            self:Refresh()
            SuuUI.EditMode.Refresh()
            if self.preview and self.preview:IsVisible() then self:PreviewView(self.preview:GetParent()) end
        end)
    end
    self:Refresh()
end

function M:OnDisable()
    self:BlizzardNumbers(true)
    -- DBM's own setting back (Suppressing is false once disabled)
    if DBM and DBM.Options and self:Get("dbmWarningsWas") ~= "" then
        DBM.Options.HideDBMWarnings = self:Get("dbmWarningsWas") == "true"
        self:Set("dbmWarningsWas", "")
    end
    self:CancelPull(true)
    if self.timeline then self.timeline:Hide() end
end
