-- UI/CastBar.lua
-- A cast in progress. An enemy cast you can stop is the arcane one; everything
-- else stays neutral.
--
--   local bar = UI.CastBar(parent, "target", {
--       size = "sm",          -- "md" (cast, 24px: your own cast) or "sm" (cast-sm, 18px: under a unit frame)
--       width = 300,
--       icon = true,          -- the spell's icon as a square at the left end
--       kick = true,          -- your interrupt's state at the right end of interruptible casts
--   })
--   bar:Activate(); bar:Deactivate()
--   bar:SetIconShown(on); bar:SetKickShown(on)   -- live, from the settings
--
-- Everything the client may hide is shown without being read: the fill runs
-- from the cast's duration object (StatusBar:SetTimerDuration), the time is
-- the duration's remaining time handed to SetFormattedText, the spell name
-- and icon go straight to the text and texture, and the "can't be
-- interrupted" flag (a secret boolean in combat) sets the alpha of the arcane
-- layer and the lock through SetAlphaFromBoolean on host frames (on a texture
-- it renders invisible on this client). Your own interrupt's "ready" is the
-- readable isActive of its cooldown.

local _, ns = ...

local UI, T, Events = ns.UI, ns.Tokens, ns.Events
local S = T.space

local WHITE = "Interface\\Buttons\\WHITE8X8"
local LOCK = "Interface\\LFGFrame\\UI-LFG-ICON-LOCK"
local DIR = Enum.StatusBarTimerDirection
local isSecret = issecretvalue or function() return false end

--------------------------------------------------------------------------------
-- Your interrupt: the first of your class's interrupts you know.
--------------------------------------------------------------------------------

local INTERRUPTS = {
    ROGUE = { 1766, 1767, 1768, 1769 },                                  -- Kick
    WARRIOR = { 6552, 6554, 72, 1671, 1672 },                            -- Pummel, Shield Bash
    SHAMAN = { 8042, 8044, 8045, 8046, 10412, 10413, 10414 },            -- Earth Shock
    MAGE = { 2139 },                                                     -- Counterspell
    PRIEST = { 15487 },                                                  -- Silence
    PALADIN = { 853, 5588, 5589, 10308 },                                -- Hammer of Justice
    DRUID = { 5211, 6798, 8983 },                                        -- Bash
    HUNTER = { 19503 },                                                  -- Scatter Shot
}

-- Each interrupt's own cooldown in seconds, if the client can't tell us
-- (GetSpellBaseCooldown): vanilla values.
local BASE_COOLDOWN = {
    [1766] = 10, [1767] = 10, [1768] = 10, [1769] = 10,
    [6552] = 10, [6554] = 10, [72] = 12, [1671] = 12, [1672] = 12,
    [8042] = 6, [8044] = 6, [8045] = 6, [8046] = 6, [10412] = 6, [10413] = 6, [10414] = 6,
    [2139] = 24, [15487] = 45, [853] = 60, [5588] = 60, [5589] = 60, [10308] = 60,
    [5211] = 60, [6798] = 60, [8983] = 60, [19503] = 30,
}

local Interrupt = { spell = nil, bars = {}, usedAt = nil, cooldown = 0 }
ns.Interrupt = Interrupt

local function isInterrupt(id)
    local _, class = UnitClass("player")
    for _, x in ipairs(INTERRUPTS[class] or {}) do
        if x == id then return true end
    end
    return false
end

function Interrupt.Find()
    local _, class = UnitClass("player")
    Interrupt.spell = nil
    local list = INTERRUPTS[class] or {}
    -- the highest rank you know
    for i = #list, 1, -1 do
        local id = list[i]
        if (IsPlayerSpell and IsPlayerSpell(id)) or (IsSpellKnown and IsSpellKnown(id)) then
            Interrupt.spell = id
            break
        end
    end
end

-- Seconds left on the interrupt's own cooldown, from when you last used it:
-- your own cast, always readable. 0 when it is up.
function Interrupt.Remaining()
    if not Interrupt.usedAt then return 0 end
    return math.max(0, Interrupt.usedAt + Interrupt.cooldown - GetTime())
end

-- true (ready), false (cooling down) or nil (no interrupt known). The game's
-- "on cooldown" also covers the global cooldown after any cast; when the
-- interrupt's own cooldown is over, that is all it is, and it counts as ready.
function Interrupt.Ready()
    if not Interrupt.spell then return nil end
    local cd = C_Spell.GetSpellCooldown(Interrupt.spell)
    if not cd or isSecret(cd.isActive) then return nil end
    if not cd.isActive then return true end
    return Interrupt.Remaining() <= 0
end

Events.OnUnit("UNIT_SPELLCAST_SUCCEEDED", "player", function(_, _, _, spellID)
    if isSecret(spellID) or not spellID or not isInterrupt(spellID) then return end
    local ms = GetSpellBaseCooldown and GetSpellBaseCooldown(spellID)
    Interrupt.cooldown = (not isSecret(ms) and ms and ms > 0) and ms / 1000 or BASE_COOLDOWN[spellID] or 0
    Interrupt.usedAt = GetTime()
    for bar in pairs(Interrupt.bars) do bar:UpdateKick() end
end, "Interrupt")

local function refreshKicks()
    for bar in pairs(Interrupt.bars) do bar:UpdateKick() end
end

Events.OnGame("SPELLS_CHANGED", function() Interrupt.Find(); refreshKicks() end, "Interrupt")
Events.OnGame("PLAYER_LOGIN", function() Interrupt.Find() end, "Interrupt")
Events.OnGame("SPELL_UPDATE_COOLDOWN", refreshKicks, "Interrupt")

--------------------------------------------------------------------------------
-- Building
--------------------------------------------------------------------------------

local CB = {}

local function fillBar(parent, level, deep, top, edge)
    local b = CreateFrame("StatusBar", nil, parent)
    b:SetStatusBarTexture(WHITE)
    local tex = b:GetStatusBarTexture()
    tex:SetSnapToPixelGrid(false)
    local r1, g1, b1, a1 = UI.RGBA(deep)
    local r2, g2, b2, a2 = UI.RGBA(top)
    tex:SetGradient("HORIZONTAL", CreateColor(r1, g1, b1, a1), CreateColor(r2, g2, b2, a2))
    b:SetFrameLevel(level)
    -- the 2px edge at the fill's leading end
    local e = b:CreateTexture(nil, "OVERLAY")
    e:SetColorTexture(UI.RGBA(edge))
    e:SetPoint("TOPRIGHT", tex, "TOPRIGHT")
    e:SetPoint("BOTTOMRIGHT", tex, "BOTTOMRIGHT")
    e:SetWidth(2)
    return b
end

function UI.CastBar(parent, unit, opts)
    opts = opts or {}
    local enemy = unit ~= "player"
    local h = UI.Size(opts.size == "md" and "cast" or "cast-sm")
    local f = CreateFrame("Frame", opts.name, parent)
    Mixin(f, CB)
    f.unit, f.opts, f.enemy = unit, opts, enemy
    f:SetSize(UI.Size(opts.width or 300), h)
    f:Hide()

    local x = 0
    if opts.icon ~= false then
        f.icon = CreateFrame("Frame", nil, f)
        f.icon:SetSize(h, h)
        f.icon:SetPoint("TOPLEFT")
        UI.Fill(f.icon, "surface-sunk"):SetAllPoints()
        f.iconArt = f.icon:CreateTexture(nil, "ARTWORK")
        f.iconArt:SetPoint("TOPLEFT", 1, -1)
        f.iconArt:SetPoint("BOTTOMRIGHT", 0, 1)
        f.iconArt:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        UI.Border(f.icon, "gilt-hairline")
        x = h
    end

    -- The bar: ground, the neutral (or locked) fill, then the arcane layer.
    local bar = CreateFrame("Frame", nil, f)
    bar:SetPoint("TOPLEFT", x, 0)
    bar:SetPoint("BOTTOMRIGHT")
    f.bar = bar
    UI.Fill(bar, "surface-sunk"):SetAllPoints()
    local inner = CreateFrame("Frame", nil, bar)
    inner:SetPoint("TOPLEFT", 1, -1)
    inner:SetPoint("BOTTOMRIGHT", -1, 1)
    inner:SetClipsChildren(true)
    local level = f:GetFrameLevel()
    if enemy then
        f.fill = fillBar(inner, level + 1, "unit-fill-deep", "unit-fill", "ink-muted")
    else
        -- your own cast: transparent to ghost, an ink edge
        f.fill = fillBar(inner, level + 1, "ghost", "ghost", "ink")
        local r, g, b = UI.RGBA("ghost")
        f.fill:GetStatusBarTexture():SetGradient("HORIZONTAL", CreateColor(r, g, b, 0), CreateColor(r, g, b, 0.5))
    end
    f.fill:SetAllPoints(inner)
    f.border = UI.Border(bar, "gilt-hairline", { layer = "OVERLAY" })

    -- Everything that marks an interruptible cast lives on one host frame, so
    -- one SetAlphaFromBoolean shows or hides it all.
    if enemy then
        local host = CreateFrame("Frame", nil, f)
        host:SetAllPoints(f)
        host:SetFrameLevel(level + 2)
        f.arcane = host
        f.arcaneFill = fillBar(host, level + 2, "arcane-soft", "arcane-glow", "arcane")
        f.arcaneFill:SetPoint("TOPLEFT", inner, "TOPLEFT")
        f.arcaneFill:SetPoint("BOTTOMRIGHT", inner, "BOTTOMRIGHT")
        f.arcaneEdge = CreateFrame("Frame", nil, host)
        f.arcaneEdge:SetAllPoints(bar)
        UI.Border(f.arcaneEdge, "arcane")
        if f.icon then
            local iconEdge = CreateFrame("Frame", nil, host)
            iconEdge:SetAllPoints(f.icon)
            UI.Border(iconEdge, "arcane")
        end
        f.glow = UI.Shadow(f.arcaneEdge, "glow-arcane")
        -- the lock, on its own host, shown when the cast can't be interrupted
        f.lockHost = CreateFrame("Frame", nil, f)
        f.lockHost:SetAllPoints(bar)
        f.lockHost:SetFrameLevel(level + 4)
        local lock = f.lockHost:CreateTexture(nil, "OVERLAY")
        lock:SetTexture(LOCK)
        lock:SetDesaturated(true)
        lock:SetVertexColor(UI.RGBA("ink"))
        local ls = opts.size == "md" and 12 or 10
        lock:SetSize(ls, ls)
        lock:SetPoint("LEFT", S["space-3"], 0)
        f.lockW = ls + S["space-2"]
    end

    -- Text over everything.
    local text = CreateFrame("Frame", nil, f)
    text:SetAllPoints(bar)
    text:SetFrameLevel(level + 5)
    local pad = opts.size == "md" and S["space-4"] or S["space-3"]
    f.time = UI.Text(text, "numeric", "ink")
    f.time:SetShadowed(true)
    f.time:SetPoint("RIGHT", -pad, 0)
    f.spell = UI.Text(text, "label", "ink")
    f.spell:SetShadowed(true)
    f.spell:SetPoint("LEFT", pad + (f.lockW or 0), 0)
    -- the name gives way to the time (and the interrupt): a fixed width, so a
    -- secret name is shortened by the engine with an ellipsis
    local reserve = 40 + ((enemy and opts.kick ~= false) and 30 or 0)
    f.spell:SetWidth(UI.Size(opts.width or 300) - x - pad * 2 - (f.lockW or 0) - reserve)

    -- Your interrupt: the stop glyph (arcane when ready) and its seconds.
    if enemy and opts.kick ~= false then
        local k = CreateFrame("Frame", nil, f.arcane)
        k:SetFrameLevel(level + 6)
        k:SetSize(28, h)
        k:SetPoint("RIGHT", f.time, "LEFT", -S["space-2"], 0)
        k.glyph = UI.Diamond(k, opts.size == "md" and 8 or 7, "arcane")
        k.glyph:SetPoint("RIGHT", 0, 0)
        k.secs = UI.Text(k, "micro", "ink-muted")
        k.secs:SetShadowed(true)
        k.secs:SetPoint("RIGHT", k.glyph, "LEFT", -3, 0)
        f.kick = k
    end

    f:SetScript("OnUpdate", function(self) self:Tick() end)
    f.pad, f.h, f.totalW = pad, h, UI.Size(opts.width or 300)
    f.iconShown = f.icon ~= nil
    f.kickShown = f.kick ~= nil
    return f
end

-- Lays out the bar beside the icon (when shown), and sizes the spell name
-- to the room the time and the interrupt leave.
function CB:Arrange()
    local x = (self.icon and self.iconShown) and self.h or 0
    if self.icon then self.icon:SetShown(self.iconShown) end
    self.bar:ClearAllPoints()
    self.bar:SetPoint("TOPLEFT", x, 0)
    self.bar:SetPoint("BOTTOMRIGHT")
    local reserve = 40 + ((self.kick and self.kickShown) and 30 or 0)
    self.spell:SetWidth(self.totalW - x - self.pad * 2 - (self.lockW or 0) - reserve)
end

function CB:SetIconShown(on)
    self.iconShown = on and self.icon ~= nil
    self:Arrange()
end

function CB:SetKickShown(on)
    self.kickShown = on and self.kick ~= nil
    self:UpdateKick()
    self:Arrange()
end

--------------------------------------------------------------------------------
-- Drawing
--------------------------------------------------------------------------------

function CB:UpdateKick()
    local k = self.kick
    if not k then return end
    local ready = Interrupt.Ready()
    k:SetShown(ready ~= nil and self.kickShown ~= false)
    if ready == nil then return end
    k.glyph:SetVertexColor(UI.RGBA(ready and "arcane" or "ink-faint"))
    k.secs:SetShown(not ready)
end

function CB:Tick()
    local d = self.duration
    if not d then return end
    local remaining = d:GetRemainingDuration()
    self.time:SetFormattedText("%.1fs", remaining)
    self.time.value = nil
    if self.kick and self.kick.secs:IsShown() then
        local r = Interrupt.Remaining()
        if r > 0 then
            self.kick.secs:SetValue(tostring(math.ceil(r)))
        else
            -- the cooldown just ran out
            self:UpdateKick()
        end
    end
end

function CB:Start(channel)
    local u = self.unit
    local name, _, texture, _, _, _, a7, a8 = (channel and UnitChannelInfo or UnitCastingInfo)(u)
    -- UnitCastingInfo: …, castID, notInterruptible; UnitChannelInfo: …, notInterruptible
    local notInterruptible
    if channel then notInterruptible = a7 else notInterruptible = a8 end
    local d
    if channel then d = UnitChannelDuration(u) else d = UnitCastingDuration(u) end
    if not d then self:Stop() return end
    self.duration = d
    self.fill:SetTimerDuration(d, nil, channel and DIR.RemainingTime or DIR.ElapsedTime)
    if self.arcaneFill then
        self.arcaneFill:SetTimerDuration(d, nil, channel and DIR.RemainingTime or DIR.ElapsedTime)
    end
    self.spell:SetText(name)
    if self.iconArt then self.iconArt:SetTexture(texture) end
    self:SetInterruptible(notInterruptible)
    self:UpdateKick()
    self:Show()
    self:Tick()
end

-- notInterruptible may be a secret boolean: never tested, only handed to the engine.
function CB:SetInterruptible(notInterruptible)
    if not self.arcane then return end
    if not isSecret(notInterruptible) and notInterruptible == nil then notInterruptible = false end
    self.arcane:SetAlphaFromBoolean(notInterruptible, 0, 1)
    self.lockHost:SetAlphaFromBoolean(notInterruptible, 1, 0)
end

function CB:Stop()
    self.duration = nil
    self:Hide()
end

function CB:Refresh()
    if not UnitExists(self.unit) then return self:Stop() end
    -- Ask for the duration objects, not the spell name: the name may be a
    -- secret string, which can't be tested.
    if UnitCastingDuration(self.unit) then
        self:Start(false)
    elseif UnitChannelDuration(self.unit) then
        self:Start(true)
    else
        self:Stop()
    end
end

--------------------------------------------------------------------------------
-- Events
--------------------------------------------------------------------------------

local START = { "UNIT_SPELLCAST_START", "UNIT_SPELLCAST_DELAYED" }
local CHANNEL = { "UNIT_SPELLCAST_CHANNEL_START", "UNIT_SPELLCAST_CHANNEL_UPDATE" }
local STOP = { "UNIT_SPELLCAST_STOP", "UNIT_SPELLCAST_FAILED", "UNIT_SPELLCAST_INTERRUPTED", "UNIT_SPELLCAST_CHANNEL_STOP" }

local function onUnit(self, event, fn)
    local ok = pcall(Events.OnUnit, event, self.unit, fn, self)
    if not ok then ns.Debug("CastBar: no event", event) end
end

function CB:Activate()
    if self.active then return end
    self.active = true
    Interrupt.bars[self] = true
    for _, e in ipairs(START) do onUnit(self, e, function() self:Start(false) end) end
    for _, e in ipairs(CHANNEL) do onUnit(self, e, function() self:Start(true) end) end
    for _, e in ipairs(STOP) do onUnit(self, e, function() self:Refresh() end) end
    onUnit(self, "UNIT_SPELLCAST_INTERRUPTIBLE", function() self:SetInterruptible(false) end)
    onUnit(self, "UNIT_SPELLCAST_NOT_INTERRUPTIBLE", function() self:SetInterruptible(true) end)
    if self.unit == "target" then
        Events.OnGame("PLAYER_TARGET_CHANGED", function() self:Refresh() end, self)
    elseif self.unit == "focus" then
        Events.OnGame("PLAYER_FOCUS_CHANGED", function() self:Refresh() end, self)
    elseif self.unit:find("^boss") then
        Events.OnGame("INSTANCE_ENCOUNTER_ENGAGE_UNIT", function() self:Refresh() end, self)
    end
    self:Refresh()
end

function CB:Deactivate()
    if not self.active then return end
    self.active = false
    Interrupt.bars[self] = nil
    Events.OffAll(self)
    self:Stop()
end
