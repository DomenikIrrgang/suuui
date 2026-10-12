-- Units/Timeline.lua
-- The encounter timeline (step 1.13): top centre, 28px down, now at the
-- left, the next 30 seconds to the right. It shows whatever the game's
-- encounter timeline holds (C_EncounterTimeline): boss abilities if the game
-- sends them (Forever has the feature off, 2026-10-12) and the timers addons
-- add to it, SuuUI's pull countdown first. Hidden while nothing is on it.
--
-- The pull countdown: "/suu pull [seconds]" (default 10; 0 cancels). It
-- rides the timeline as "Pull", counts down the last five seconds as an
-- alert (out of combat too) and says "Pull!" at zero. In a group the leader
-- (or an assistant) sends it to everyone with SuuUI. Combat cancels it.

local UI, T = SuuUI.UI, SuuUI.Tokens

local M = SuuUI.RegisterModule({
    id = "timeline",
    name = "Encounter timeline",
    description = "Upcoming boss abilities and SuuUI's pull countdown riding toward now, top centre.",
    api = "0.10",
    defaults = {
        position = { point = "TOP", x = 0, y = -28 },
        variant = "track",   -- "track" | "list" | "off"
        pullSeconds = 10,
    },
})

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

-- Every event the game's timeline holds, as the component's list. One whose
-- time is secret can't be placed, so it's left out.
function M:Read()
    local list = {}
    if not ET then return list end
    local ok, ids = pcall(ET.GetEventList)
    if not ok or type(ids) ~= "table" then return list end
    local now = GetTime()
    for _, id in ipairs(ids) do
        local okS, state = pcall(ET.GetEventState, id)
        local okR, left = pcall(ET.GetEventTimeRemaining, id)
        local okI, info = pcall(ET.GetEventInfo, id)
        if okS and okR and okI and readable(state) and (state == ACTIVE or state == PAUSED) and readable(left)
           and (left > 0 or state == PAUSED) and type(info) == "table" then
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

function M:CancelPull(quiet)
    if self.pullID and ET then pcall(ET.CancelScriptEvent, self.pullID) end
    self.pullID = nil
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
    local detail = from and ("from " .. from) or nil
    -- the last five seconds as an alert, then "Pull!"
    self.pullTicker = C_Timer.NewTicker(0.25, function()
        local left = endsAt - GetTime()
        if left <= 0 then
            SuuUI.ShowAlert("pull", "info", "Pull!", detail)
            C_Timer.After(1.5, function() SuuUI.HideAlert("pull") end)
            self.pullTicker:Cancel()
            self.pullTicker = nil
            self.pullID = nil
        elseif left <= 5 then
            SuuUI.ShowAlert("pull", "info", ("Pull in %d"):format(math.ceil(left)), detail)
        end
    end)
    self:Refresh()
end

-- Who may start one for the group: the leader or an assistant (anyone in a
-- party without a leader flag).
local function canLead()
    if not UI.Flag(IsInGroup()) then return true end
    if UI.Flag(UnitIsGroupLeader("player")) or UI.Flag(UnitIsGroupAssistant("player")) then return true end
    return not UI.Flag(IsInRaid())
end

function M:Pull(arg)
    local seconds = tonumber(arg) or self:Get("pullSeconds")
    if UI.Flag(IsInGroup()) then
        if not canLead() then
            self:Print("Only the leader or an assistant can start a pull countdown in a raid.")
            return
        end
        local channel = UI.Flag(IsInRaid()) and "RAID" or "PARTY"
        pcall(C_ChatInfo.SendAddonMessage, PREFIX, ("PULL\t%d"):format(seconds), channel)
    end
    self:StartPull(seconds)
end

function M:OnMessage(prefix, text, _, sender)
    if prefix ~= PREFIX or type(text) ~= "string" or isSecret(text) then return end
    local seconds = text:match("^PULL\t(%-?%d+)$")
    if not seconds then return end
    if isSecret(sender) or type(sender) ~= "string" then return end
    -- our own message comes back: already started
    local me = UnitName("player")
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
        { title = "Pull countdown", description = "/suu pull starts it (/suu pull 15 for 15 seconds, /suu pull 0 cancels). In a group the leader's or an assistant's reaches everyone with SuuUI; combat ends it.", rows = {
            { key = "pullSeconds", label = "Length", control = "slider", min = 5, max = 30, step = 1, unit = "s" },
            { label = "Start one", control = "button", text = "Start a pull countdown",
              onClick = function() M:Pull() end },
        } },
    },
}

function M:OnEnable()
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
    self:CancelPull(true)
    if self.timeline then self.timeline:Hide() end
end
