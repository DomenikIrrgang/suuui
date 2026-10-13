-- Units/Campsite.lua
-- Campfires (step 2.8): what a fire does for you, said through SuuUI's
-- alerts (the band in the middle of the screen that warns of aggro), as
-- each phase begins. Camping has no window: everything comes from your own
-- auras (probed 2026-10-13).
--   Campfire Nearby (1283391)      → "Campfire nearby", until you rest
--                                    (or for General › Campfire's seconds)
--   Welcoming Campfire (1229739)   → "Resting by the fire", counting down
--                                    the minute seated
--   Camp Benefits (1229741)        → "Camp Benefits" for a few seconds
-- Camp Benefits wins over Welcoming Campfire (it comes back every minute
-- while you stay seated). Combat alerts outrank these (info tone), and
-- combat ending clears them. Fires you pass (not the ones you light: those
-- go out) are remembered per character for the world map (3.5).
-- A built-in module written against the public API only.

local M = SuuUI.RegisterModule({
    id = "campsite",
    name = "Campfire",
    description = "Alerts at a campfire: one is near, resting by it, Camp Benefits gained.",
    api = "0.12",
    defaults = {
        nearbyFor = 0, -- seconds the "Campfire nearby" alert stays; 0: until you rest or walk away
    },
})

local isSecret = issecretvalue or function() return false end
local function plain(v) return v ~= nil and not isSecret(v) end

local KEY = "suu:campfire"
local NEARBY, WELCOMING, BENEFITS = 1283391, 1229739, 1229741
local LIGHT_FIRE = 1307227 -- Basic Campfire (the kit's spell)
local BRIEF = 6            -- seconds a "nearby" or "benefits" alert stays
local MAX_FIRES = 100

local function clock(s)
    s = math.max(0, math.floor(s + 0.5))
    if s >= 3600 then return ("%dh"):format(s / 3600) end
    if s >= 600 then return ("%dm"):format(s / 60) end
    return ("%d:%02d"):format(s / 60, s % 60)
end

-- One of your auras by spell, or nil; false when it can't be read (combat).
local function aura(spellID)
    local ok, a = pcall(C_UnitAuras.GetPlayerAuraBySpellID, spellID)
    if not ok then return false end
    return a
end

--------------------------------------------------------------------------------
-- Phases and their alerts
--------------------------------------------------------------------------------

-- "nearby", "resting", "rested" or nil; false when auras can't be read.
function M:Phase()
    local near, welcoming, benefits = aura(NEARBY), aura(WELCOMING), aura(BENEFITS)
    if near == false or welcoming == false or benefits == false then return false end
    if not near and not welcoming then return nil, nil end
    if benefits then return "rested", benefits end
    if welcoming then return "resting", welcoming end
    return "nearby", nil
end

local function restLeft(a)
    if not a then return nil end
    local x = a.expirationTime
    if plain(x) and x and x > 0 then return x - GetTime() end
end

function M:Alert(phase, a)
    if self.briefTimer then self.briefTimer:Cancel(); self.briefTimer = nil end
    if self.ticker then self.ticker:Cancel(); self.ticker = nil end
    if phase == "nearby" then
        -- stays until you rest (or walk away), or for the setting's seconds
        SuuUI.ShowAlert(KEY, "info", "Campfire nearby", "Sit for a minute: an hour of Camp Benefits")
        local stay = self:Get("nearbyFor")
        if not stay or stay <= 0 then return end
        self.briefTimer = C_Timer.NewTimer(stay, function()
            self.briefTimer = nil
            SuuUI.HideAlert(KEY)
        end)
        return
    elseif phase == "resting" then
        local function show()
            local left = restLeft(a)
            SuuUI.ShowAlert(KEY, "info", "Resting by the fire", left and ("Camp Benefits in " .. clock(left)) or "Stay seated for a minute")
        end
        show()
        self.ticker = C_Timer.NewTicker(0.5, show)
        return
    elseif phase == "rested" then
        local left = restLeft(a)
        SuuUI.ShowAlert(KEY, "info", "Camp Benefits", (left and left < 3500) and (clock(left) .. " left") or "For the next hour")
    else
        SuuUI.HideAlert(KEY)
        return
    end
    self.briefTimer = C_Timer.NewTimer(BRIEF, function()
        self.briefTimer = nil
        SuuUI.HideAlert(KEY)
    end)
end

function M:Update()
    local phase, a = self:Phase()
    if phase == false then return end -- in combat: as it was
    if phase == self.phase then return end
    local was = self.phase
    self.phase = phase
    -- walking away while resting or rested: nothing to say
    if not phase then
        if self.ticker or self.briefTimer then self:Alert(nil) end
        return
    end
    -- a fire you just walked up to while already rested: say how long is left
    if was == nil and phase == "rested" then
        self:Alert("rested", a)
        return
    end
    self:Alert(phase, a)
end

--------------------------------------------------------------------------------
-- Fires you pass, for the map
--------------------------------------------------------------------------------

function M:RememberFire()
    -- a fire you just lit yourself goes out: not one to remember
    if self.litAt and GetTime() - self.litAt < 10 then return end
    local map = C_Map.GetBestMapForUnit("player")
    if not plain(map) or not map then return end
    local pos = C_Map.GetPlayerMapPosition(map, "player")
    if not pos then return end
    local x, y = pos:GetXY()
    if not (plain(x) and plain(y) and x and y) then return end
    local data = self:CharData()
    data.fires = data.fires or {}
    for _, f in ipairs(data.fires) do
        if f.map == map and math.abs(f.x - x) < 0.01 and math.abs(f.y - y) < 0.01 then
            f.seen = time()
            return
        end
    end
    table.insert(data.fires, { map = map, x = x, y = y, seen = time() })
    while #data.fires > MAX_FIRES do table.remove(data.fires, 1) end
end

--------------------------------------------------------------------------------
-- Settings and a look without a fire
--------------------------------------------------------------------------------

function M:Sample(phase)
    local fake = { expirationTime = GetTime() + (phase == "resting" and 42 or 3600) }
    self:Alert(phase or "nearby", fake)
    if phase ~= "rested" then
        -- a sample doesn't stay
        self.briefTimer = C_Timer.NewTimer(BRIEF, function()
            self.briefTimer = nil
            if self.ticker then self.ticker:Cancel(); self.ticker = nil end
            SuuUI.HideAlert(KEY)
        end)
    end
end

local SECTION = {
    id = "campsite", label = "Campfire", category = "General", order = 26,
    groups = {
        { title = "Campfire alerts", description = "At a campfire SuuUI's alerts say what it does for you: a fire is near, the minute seated counting down, then Camp Benefits gained. They need the Alerts module; combat alerts come first.", rows = {
            { key = "nearbyFor", label = "\"Campfire nearby\" stays", control = "slider", min = 0, max = 60, step = 5,
              format = function(v) return v == 0 and "Until you rest" or (v .. " s") end,
              description = "Until you sit down and rest (or walk away), or only this many seconds." },
            { label = "Show them", control = "button", text = "Nearby, resting, rested",
              description = "Each alert in turn, without a fire.",
              onClick = function()
                  M:Sample("nearby")
                  C_Timer.After(BRIEF + 0.5, function() M:Sample("resting") end)
                  C_Timer.After(BRIEF * 2 + 1, function() M:Sample("rested") end)
              end },
        } },
    },
}

--------------------------------------------------------------------------------
-- Lifecycle
--------------------------------------------------------------------------------

function M:OnEnable()
    SuuUI.AllowAlertOutOfCombat(KEY)
    self:RegisterSettings(SECTION)
    self:OnUnitEvent("UNIT_AURA", { "player" }, function()
        local wasNear = self.near
        local near = aura(NEARBY)
        if near ~= false then
            self.near = near and true or false
            if self.near and not wasNear then self:RememberFire() end
        end
        self:Update()
    end)
    self:OnUnitEvent("UNIT_SPELLCAST_SUCCEEDED", { "player" }, function(_, _, _, spellID)
        if plain(spellID) and spellID == LIGHT_FIRE then self.litAt = GetTime() end
    end)
    -- combat ending clears every alert: say again what still holds (after the
    -- Alerts module has cleared)
    self:OnGameEvent("PLAYER_REGEN_ENABLED", function()
        C_Timer.After(0.2, function() self.phase = "unknown"; self:Update() end)
    end)
    self:RegisterCommand("campsite", "The campfire alerts without a fire: /suu campsite nearby, resting or rested.", function(arg)
        self:Sample((arg == "resting" or arg == "rested") and arg or "nearby")
    end)
    -- what's true now, without an alert for it
    self.near = aura(NEARBY) and true or false
    local phase = self:Phase()
    if phase ~= false then self.phase = phase end
end

function M:OnDisable()
    if self.ticker then self.ticker:Cancel(); self.ticker = nil end
    if self.briefTimer then self.briefTimer:Cancel(); self.briefTimer = nil end
    SuuUI.HideAlert(KEY)
end
