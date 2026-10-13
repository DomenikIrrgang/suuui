-- Units/Campsite.lua
-- The campfire strip (step 2.8, design board "Campfire strip"): while a
-- fire is near, a small strip under your buffs says where you are with it.
-- Camping has no window: everything comes from your own auras (probed
-- 2026-10-13) and your campfire kit's cooldown.
--   Campfire Nearby (1283391)      → "Campfire nearby", how to rest
--   Welcoming Campfire (1229739)   → "Resting by the fire": the minute
--                                    seated, filling up
--   Camp Benefits (1229741)        → "Rested at the fire": the hour left
--                                    and what the benefits do (the aura's
--                                    own tooltip line)
--   Basic Campfire Kit (279981)    → its cooldown in the foot
-- Fires you pass (not the ones you light: those go out) are remembered per
-- character for the world map (3.5).
-- A built-in module written against the public API only.

local UI, T = SuuUI.UI, SuuUI.Tokens

local M = SuuUI.RegisterModule({
    id = "campsite",
    name = "Campfire",
    description = "A strip under your buffs while a campfire is near: resting, Camp Benefits, your kit's cooldown.",
    api = "0.12",
    defaults = {
        underBuffs = true,
        position = { point = "TOPRIGHT", x = -28, y = -260 },
    },
})

local isSecret = issecretvalue or function() return false end
local function plain(v) return v ~= nil and not isSecret(v) end

local NEARBY, WELCOMING, BENEFITS = 1283391, 1229739, 1229741
local LIGHT_FIRE = 1307227 -- Basic Campfire (the kit's spell)
local KIT = 279981
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

-- What Camp Benefits does: its tooltip's second line (out of combat), kept.
local effectCache = {}
local function effectOf(a)
    local id = a.auraInstanceID
    if not plain(id) then return nil end
    if effectCache[id] then return effectCache[id] end
    if not (C_TooltipInfo and C_TooltipInfo.GetUnitBuffByAuraInstanceID) then return nil end
    local ok, data = pcall(C_TooltipInfo.GetUnitBuffByAuraInstanceID, "player", id)
    if not ok or not data or type(data.lines) ~= "table" then return nil end
    for i = 2, #data.lines do
        local text = data.lines[i].leftText
        if plain(text) and text and text ~= "" then
            effectCache[id] = text
            return text
        end
    end
end

--------------------------------------------------------------------------------
-- The state
--------------------------------------------------------------------------------

function M:KitCooldown()
    local count = C_Item and C_Item.GetItemCount and C_Item.GetItemCount(KIT)
    if not plain(count) or not count or count == 0 then return nil end
    local start, duration = C_Container.GetItemCooldown(KIT)
    if plain(duration) and duration and duration > 0 and plain(start) then
        return math.max(0, start + duration - GetTime())
    end
    return 0
end

-- The strip's data, or nil (no fire near); unchanged when auras can't be read.
function M:Read()
    local near, welcoming, benefits = aura(NEARBY), aura(WELCOMING), aura(BENEFITS)
    if near == false or welcoming == false or benefits == false then return self.last end
    if not near and not welcoming then return nil end
    local d = { cooldowns = {} }
    local now = GetTime()
    if welcoming then
        d.phase = "resting"
        local x, dur = welcoming.expirationTime, welcoming.duration
        if plain(x) and plain(dur) and dur and dur > 0 then
            d.endsAt, d.duration = x, dur
        end
    elseif benefits then
        d.phase = "rested"
        if plain(benefits.expirationTime) and benefits.expirationTime then d.endsAt = benefits.expirationTime end
        d.benefits = { { icon = plain(benefits.icon) and benefits.icon or nil,
            label = plain(benefits.name) and benefits.name or "Camp Benefits", effect = effectOf(benefits) } }
    else
        d.phase = "nearby"
    end
    if d.endsAt then d.remaining = clock(d.endsAt - now) end
    if d.duration then d.progress = 1 - (d.endsAt - now) / d.duration end
    local kit = self:KitCooldown()
    if kit then d.cooldowns[1] = { label = "Campfire kit", left = kit, remaining = kit > 0 and clock(kit) or "Ready" } end
    return d
end

function M:Update()
    local d = self.test or self:Read()
    self.last = d
    if not d then
        self.strip:Hide()
        if self.ticker then self.ticker:Cancel(); self.ticker = nil end
        return
    end
    self.strip:SetData(d)
    self.strip:Show()
    if not self.ticker then
        self.ticker = C_Timer.NewTicker(0.5, function() self:Tick() end)
    end
end

-- The times, twice a second.
function M:Tick()
    local d = self.last
    if not d or d.test or not self.strip:IsShown() then return end
    local now = GetTime()
    local remaining, progress
    if d.endsAt then
        remaining = clock(d.endsAt - now)
        if d.duration then progress = 1 - (d.endsAt - now) / d.duration end
    end
    local times = {}
    local kit = not d.test and self:KitCooldown()
    if kit then times[1] = kit > 0 and clock(kit) or "Ready" end
    self.strip:SetTimes(remaining, progress, times)
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
-- Place
--------------------------------------------------------------------------------

function M:Attached()
    return self:Get("underBuffs") and SuuUI.GetAnchor("playerBuffs") or nil
end

function M:Place()
    local buffs = self:Attached()
    self.strip:ClearAllPoints()
    if buffs then
        self.strip:SetPoint("TOPRIGHT", buffs, "BOTTOMRIGHT", 0, -T.space["space-5"])
    else
        local pos = self:Get("position")
        self.strip:SetPoint(pos.point or "TOPRIGHT", SuuUI.Root, pos.point or "TOPRIGHT", pos.x or 0, pos.y or 0)
    end
    SuuUI.EditMode.Refresh()
end

--------------------------------------------------------------------------------
-- Settings and a look without a fire
--------------------------------------------------------------------------------

local SAMPLES = {
    nearby = { phase = "nearby", cooldowns = { { label = "Campfire kit", remaining = "Ready" } } },
    resting = { phase = "resting", remaining = "0:42", progress = 0.3 },
    rested = { phase = "rested", remaining = "58m",
        benefits = { { icon = 7808144, label = "Camp Benefits", effect = "Rested at a campfire: the camp's features strengthen you for an hour." } },
        cooldowns = { { label = "Campfire kit", remaining = "3:12" } } },
}

function M:PreviewView(parent)
    if not self.preview then
        self.preview = UI.Campsite(parent)
        self.preview:SetData(SAMPLES.rested)
    end
    self.preview:SetParent(parent)
    return self.preview
end

local SECTION = {
    id = "campsite", label = "Campfire", category = "General", order = 26,
    preview = function(parent) return M:PreviewView(parent) end,
    groups = {
        { title = "Campfire strip", description = "While a campfire is near: how to rest by it, the minute seated, then the hour of Camp Benefits and your kit's cooldown. /suu campsite nearby, resting or rested shows it without a fire.", rows = {
            { key = "underBuffs", label = "Under your buffs", control = "toggle",
              description = "Off, or with your buffs hidden: at its own place, which you move in edit mode." },
        } },
    },
}

--------------------------------------------------------------------------------
-- Lifecycle
--------------------------------------------------------------------------------

function M:OnEnable()
    if not self.strip then
        self.strip = UI.Campsite(SuuUI.Root)
        self.strip:SetFrameStrata("MEDIUM")
        self.strip:Hide()
        self.strip.suuManagedShow = true -- shown while a fire is near
    end
    self:RegisterMover(self.strip, { key = "position", label = "Campfire strip",
        enabled = function() return self:Attached() == nil end,
        place = function() self:Place() end })
    self:RegisterSettings(SECTION)
    self:Watch("underBuffs", function() self:Place() end)
    self:On("SUUUI_ANCHOR_CHANGED", function(_, name) if name == "playerBuffs" then self:Place() end end)
    self:Place()
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
    for _, e in ipairs({ "BAG_UPDATE_COOLDOWN", "PLAYER_ENTERING_WORLD", "PLAYER_REGEN_ENABLED" }) do
        self:OnGameEvent(e, function() self:Update() end)
    end
    self:RegisterCommand("campsite", "The campfire strip without a fire: /suu campsite nearby, resting or rested (again to hide).", function(arg)
        local sample = SAMPLES[arg or ""] or SAMPLES.nearby
        if self.test == sample then self.test = nil else self.test = sample end
        if self.test then self.test.test = true end
        self:Update()
    end)
    self.near = aura(NEARBY) and true or false
    self:Update()
end

function M:OnDisable()
    if self.strip then self.strip:Hide() end
    if self.ticker then self.ticker:Cancel(); self.ticker = nil end
end
