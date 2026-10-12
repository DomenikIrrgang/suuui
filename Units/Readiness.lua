-- Units/Readiness.lua
-- Readiness (step 1.13): between pulls, the big cooldowns of everyone in the
-- group who runs SuuUI (battle resurrection, mana and survival cooldowns),
-- and a Ready check button for the leader or an assistant. Each SuuUI shares
-- its own through addon messages (prefix "SuuUI": "RDY\t<id>:<seconds left>,…",
-- "RDYQ" asks everyone to send theirs). Hidden from the pull until the
-- encounter (or the fight) ends. Top right, under the minimap's place.
--
-- Cooldowns are read out of combat only (their times are secret in combat,
-- and addon messages are restricted there); what a player sent last stays,
-- counting down.

local UI, T = SuuUI.UI, SuuUI.Tokens

local M = SuuUI.RegisterModule({
    id = "readiness",
    name = "Readiness",
    description = "Between pulls: your group's big cooldowns (from everyone with SuuUI) and a Ready check button.",
    api = "0.10",
    defaults = {
        position = { point = "TOPRIGHT", x = -28, y = -300 },
        shows = "instance", -- "instance" | "group" | "always" | "off"
    },
})

local isSecret = issecretvalue or function() return false end
local function readable(v) return not isSecret(v) and type(v) == "number" end
local PREFIX = "SuuUI"
local HEARTBEAT = 30

-- The cooldowns a group plans around, per class (the first rank you know).
local MAJOR = {
    DRUID = { "Rebirth", "Innervate", "Tranquility" },
    SHAMAN = { "Mana Tide Totem", "Reincarnation" },
    WARRIOR = { "Shield Wall", "Last Stand", "Challenging Shout" },
    PALADIN = { "Lay on Hands", "Divine Intervention", "Blessing of Protection" },
    PRIEST = { "Power Infusion" },
    MAGE = { "Evocation", "Ice Block" },
    WARLOCK = {},
    ROGUE = {},
    HUNTER = {},
}

local function playerClass()
    local _, class = UnitClass("player")
    return class
end

-- Yours: { { id, left } } (left in seconds, 0 ready), or nil in combat.
function M:ReadOwn()
    if InCombatLockdown() then return nil end
    local out = {}
    for _, name in ipairs(MAJOR[playerClass()] or {}) do
        local info = C_Spell.GetSpellInfo(name)
        local id = info and info.spellID
        if readable(id) and IsPlayerSpell(id) then
            local cd = C_Spell.GetSpellCooldown(id)
            local left = 0
            if cd and readable(cd.startTime) and readable(cd.duration) and cd.duration > 1.5 then
                left = math.max(0, cd.startTime + cd.duration - GetTime())
            end
            out[#out + 1] = { id = id, left = left }
        end
    end
    return out
end

--------------------------------------------------------------------------------
-- Sharing
--------------------------------------------------------------------------------

local function channel()
    if UI.Flag(IsInRaid()) then return "RAID" end
    if UI.Flag(IsInGroup()) then return "PARTY" end
end

function M:Send(text)
    local ch = channel()
    if not ch or InCombatLockdown() then return end
    local ok, result = pcall(C_ChatInfo.SendAddonMessage, PREFIX, text, ch)
    self.lastSend = { at = date("%H:%M:%S"), ok = ok, result = isSecret(result) and "secret" or tostring(result), text = text:sub(1, 40) }
end

function M:Share()
    local own = self:ReadOwn()
    if not own then return end
    local parts = {}
    for _, c in ipairs(own) do parts[#parts + 1] = ("%d:%d"):format(c.id, math.floor(c.left + 0.5)) end
    self:Send("RDY\t" .. table.concat(parts, ","))
end

-- One share soon (a burst of cooldown events makes one message).
function M:ShareSoon()
    if self.shareQueued then return end
    self.shareQueued = true
    C_Timer.After(2, function()
        self.shareQueued = nil
        if self:IsEnabled() then self:Share() end
    end)
end

function M:OnMessage(prefix, text, _, sender)
    if prefix ~= PREFIX or isSecret(text) or type(text) ~= "string" then return end
    if isSecret(sender) or type(sender) ~= "string" then return end
    local who = Ambiguate(sender, "short")
    if who == UnitName("player") then return end
    if text == "RDYQ" then
        self:ShareSoon()
        return
    end
    local payload = text:match("^RDY\t(.*)$")
    if not payload then return end
    local now = GetTime()
    local spells = {}
    for id, left in payload:gmatch("(%d+):(%d+)") do
        spells[#spells + 1] = { id = tonumber(id), endsAt = now + tonumber(left) }
    end
    self.heard = self.heard or {}
    self.heard[who] = { at = now, spells = spells }
    self:Update()
end

--------------------------------------------------------------------------------
-- The panel
--------------------------------------------------------------------------------

-- The group's members (you first) as { name, class }.
local function roster()
    local out = { { name = UnitName("player"), class = playerClass(), you = true } }
    local function add(unit)
        if UnitExists(unit) and not UI.Flag(UnitIsUnit(unit, "player")) then
            local name = UnitName(unit)
            local _, class = UnitClass(unit)
            if not isSecret(name) and name then
                out[#out + 1] = { name = name, class = (not isSecret(class)) and class or nil }
            end
        end
    end
    if UI.Flag(IsInRaid()) then
        for i = 1, 40 do add("raid" .. i) end
    else
        for i = 1, 4 do add("party" .. i) end
    end
    return out
end

function M:Rows()
    local rows, now = {}, GetTime()
    local own = self:ReadOwn()
    if own then
        self.own = {}
        for _, c in ipairs(own) do self.own[#self.own + 1] = { id = c.id, endsAt = now + c.left } end
    end
    for order, p in ipairs(roster()) do
        local spells = p.you and self.own or (self.heard and self.heard[p.name] and self.heard[p.name].spells)
        for _, c in ipairs(spells or {}) do
            local name = C_Spell.GetSpellName(c.id)
            rows[#rows + 1] = { icon = C_Spell.GetSpellTexture(c.id), spell = name or "?", who = p.name, class = p.class,
                endsAt = (c.endsAt and c.endsAt > now) and c.endsAt or nil, order = order }
        end
    end
    -- ready first, then the soonest, then group order
    table.sort(rows, function(a, b)
        local la, lb = a.endsAt or 0, b.endsAt or 0
        if (la == 0) ~= (lb == 0) then return la == 0 end
        if la ~= lb then return la < lb end
        return a.order < b.order
    end)
    return rows
end

local function canCheck()
    return UI.Flag(IsInGroup()) and (UI.Flag(UnitIsGroupLeader("player")) or UI.Flag(UnitIsGroupAssistant("player")))
end

function M:Update()
    if not self.panel then return end
    local shows = self:Get("shows")
    local _, kind = IsInInstance()
    local where = shows == "always"
        or (shows == "group" and UI.Flag(IsInGroup()))
        or (shows == "instance" and UI.Flag(IsInGroup()) and (kind == "party" or kind == "raid"))
    local shown = where and not self:Get("position").hidden and not InCombatLockdown() and not self.encounter
    if shown then
        local rows = self:Rows()
        self.panel:SetRows(rows)
        self.panel:SetActionShown(canCheck())
        shown = #rows > 0 or canCheck()
    end
    self.panel:SetShown(shown and true or false)
end

function M:PreviewView(parent)
    if not self.preview then
        self.preview = UI.Readiness(parent, {})
        local now = GetTime()
        self.preview:SetRows({
            { icon = C_Spell.GetSpellTexture(20484), spell = "Rebirth", who = "Thessaly", class = "DRUID" },
            { icon = C_Spell.GetSpellTexture(16190), spell = "Mana Tide Totem", who = "Veyra", class = "SHAMAN" },
            { icon = C_Spell.GetSpellTexture(871), spell = "Shield Wall", who = "Brannoc", class = "WARRIOR" },
            { icon = C_Spell.GetSpellTexture(29166), spell = "Innervate", who = "Thessaly", class = "DRUID", endsAt = now + 250 },
        })
        self.preview:SetActionShown(true)
    end
    self.preview:SetParent(parent)
    return self.preview
end

local SECTION = {
    id = "readiness", label = "Readiness", category = "Insights", order = 40,
    preview = function(parent) return M:PreviewView(parent) end,
    groups = {
        { title = "Readiness", description = "Between pulls: the big cooldowns of everyone in your group who runs SuuUI, and a Ready check button for the leader or an assistant. Hidden from the pull until the fight ends.", rows = {
            { key = "shows", label = "Show", control = "segmented", stacked = true,
              options = { { value = "instance", label = "In a dungeon or raid" }, { value = "group", label = "In any group" },
                          { value = "always", label = "Always" }, { value = "off", label = "Off" } },
              description = "Always: solo too, with your own cooldowns (to see it at work)." },
        } },
    },
}

function M:OnEnable()
    if not self.panel then
        self.panel = UI.Readiness(SuuUI.Root, { onReadyCheck = function() DoReadyCheck() end })
        self.panel:SetFrameStrata("MEDIUM")
        self.panel:Hide()
    end
    self.panel.suuManagedShow = true
    self:RegisterMover(self.panel, { key = "position", label = "Readiness",
        enabled = function() return self:Get("shows") ~= "off" end })
    self:RegisterSettings(SECTION)
    self:RegisterCommand("ready", "Readiness: who shared cooldowns, and the last message sent.", function()
        local names = {}
        for name, d in pairs(self.heard or {}) do names[#names + 1] = ("%s (%d)"):format(name, #d.spells) end
        self:Print(#names > 0 and ("heard from " .. table.concat(names, ", ")) or "nobody shared yet")
        local s = self.lastSend
        self:Print(s and ("last sent %s: %s, %s (%s)"):format(s.at, s.ok and "ok" or "error", s.result, s.text) or "nothing sent yet")
    end)
    if C_ChatInfo and C_ChatInfo.RegisterAddonMessagePrefix then C_ChatInfo.RegisterAddonMessagePrefix(PREFIX) end
    self:OnGameEvent("CHAT_MSG_ADDON", function(_, ...) self:OnMessage(...) end)
    self:OnGameEvent("GROUP_ROSTER_UPDATE", function()
        self:Update()
        if channel() then self:Send("RDYQ"); self:ShareSoon() end
    end)
    self:OnGameEvent("PLAYER_ENTERING_WORLD", function() self:Update() end)
    self:OnGameEvent("SPELL_UPDATE_COOLDOWN", function()
        if not InCombatLockdown() and channel() then self:ShareSoon() end
    end)
    self:OnGameEvent("PLAYER_REGEN_DISABLED", function() self:Update() end)
    self:OnGameEvent("PLAYER_REGEN_ENABLED", function()
        C_Timer.After(1, function() if self:IsEnabled() then self:Update(); self:ShareSoon() end end)
    end)
    self:OnGameEvent("ENCOUNTER_START", function() self.encounter = true; self:Update() end)
    self:OnGameEvent("ENCOUNTER_END", function() self.encounter = nil; self:Update() end)
    self:Watch("shows", function() self:Update(); SuuUI.EditMode.Refresh() end)
    self:Watch("position", function() self:Update() end)
    -- a heartbeat: everyone's view stays fresh
    if not self.ticker then
        self.ticker = C_Timer.NewTicker(HEARTBEAT, function()
            if self:IsEnabled() and channel() and not InCombatLockdown() then self:Share() end
        end)
    end
    self:Update()
end

function M:OnDisable()
    if self.panel then self.panel:Hide() end
end
