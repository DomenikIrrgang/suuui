-- UI/SwingTimer.lua
-- Your auto-attack: when the next swing or shot lands, drawn from Forever's
-- own swing timer (PLAYER_SWING; the combat log is closed to addons).
--
--   local t = UI.SwingTimer(parent, { width = 340 })
--   t:Activate(); t:Deactivate()
--
-- One row per weapon in use: main hand (swing, 8px), off hand (swing-oh, 5px)
-- under it, space-2 apart; while you shoot, the ranged row takes the main
-- hand's place. The fill is the player cast bar's (a ghost gradient with an
-- ink edge) and runs from a duration object, so the engine animates it. The
-- seconds hang off the bar's right end, with the queued on-next-swing spell
-- (Heroic Strike, Cleave, Maul, Raptor Strike) before them. A landed swing
-- flashes an ink sliver at the bar's end. An idle row rests at opacity-oor
-- with "–". If the client hides a swing's length, that swing isn't drawn:
-- never a number SuuUI can't read.

local _, ns = ...

local UI, T, Events = ns.UI, ns.Tokens, ns.Events
local S = T.space

local WHITE = "Interface\\Buttons\\WHITE8X8"
local SWING = Enum.PlayerSwingType
local DIR = Enum.StatusBarTimerDirection
local IMMEDIATE = Enum.StatusBarInterpolation and Enum.StatusBarInterpolation.Immediate
local isSecret = issecretvalue or function() return false end

-- On-next-swing attacks by class.
local NEXT_SWING = {
    WARRIOR = { 78, 284, 285, 1608, 11564, 11565, 11566, 11567, 845, 7369, 11608, 11609 }, -- Heroic Strike, Cleave
    DRUID = { 6807, 6808, 6809, 8972, 9745, 9880, 9881 },                                  -- Maul
    HUNTER = { 2973, 14260, 14261, 14262, 14263, 14264, 14265, 14266 },                    -- Raptor Strike
}

local DIGITS_W = 28
local QUEUE = 16

local ST = {}

--------------------------------------------------------------------------------
-- Rows
--------------------------------------------------------------------------------

local function buildRow(t, height)
    local r = CreateFrame("Frame", nil, t)
    r:SetSize(t.barW, height)
    UI.Fill(r, "surface-sunk"):SetAllPoints()
    local inner = CreateFrame("Frame", nil, r)
    inner:SetPoint("TOPLEFT", 1, -1)
    inner:SetPoint("BOTTOMRIGHT", -1, 1)
    inner:SetClipsChildren(true)
    local bar = CreateFrame("StatusBar", nil, inner)
    bar:SetAllPoints()
    bar:SetStatusBarTexture(WHITE)
    local tex = bar:GetStatusBarTexture()
    tex:SetSnapToPixelGrid(false)
    local cr, cg, cb = UI.RGBA("ghost")
    tex:SetGradient("HORIZONTAL", CreateColor(cr, cg, cb, 0), CreateColor(cr, cg, cb, 0.5))
    bar:SetMinMaxValues(0, 1)
    bar:SetValue(0)
    r.spark = bar:CreateTexture(nil, "OVERLAY")
    r.spark:SetColorTexture(UI.RGBA("ink"))
    r.spark:SetPoint("TOPRIGHT", tex, "TOPRIGHT")
    r.spark:SetPoint("BOTTOMRIGHT", tex, "BOTTOMRIGHT")
    r.spark:SetWidth(2)
    r.bar = bar
    r.border = UI.Border(r, "gilt-hairline", { layer = "OVERLAY" })
    -- the landed flash: an ink sliver at the end that fades over dur-fast
    r.flash = r:CreateTexture(nil, "OVERLAY", nil, 2)
    r.flash:SetColorTexture(UI.RGBA("ink"))
    r.flash:SetPoint("TOPRIGHT")
    r.flash:SetPoint("BOTTOMRIGHT")
    r.flash:SetWidth(3)
    r.flash:SetAlpha(0)
    r.digits = UI.Text(t, "micro", "ink")
    r.digits:SetShadowed(true)
    r.digits:SetJustifyH("RIGHT")
    r.digits:SetWidth(DIGITS_W)
    r.digits:SetPoint("LEFT", r, "RIGHT", S["space-2"] + QUEUE + S["space-2"], 0)
    r.duration = C_DurationUtil.CreateDuration()
    r:SetAlpha(T.opacity["opacity-oor"])
    r.digits:SetValue("–")
    return r
end

function UI.SwingTimer(parent, opts)
    opts = opts or {}
    local t = CreateFrame("Frame", opts.name, parent)
    Mixin(t, ST)
    t.barW = UI.Size(opts.width or 340)
    local mh, oh, gap = UI.Size("swing"), UI.Size("swing-oh"), S["space-2"]
    t:SetSize(t.barW, mh + gap + oh)
    t.rows = {
        [SWING.MainHand] = buildRow(t, mh),
        [SWING.OffHand] = buildRow(t, oh),
        [SWING.Ranged] = buildRow(t, mh),
    }
    t.rows[SWING.MainHand]:SetPoint("TOPLEFT")
    t.rows[SWING.Ranged]:SetPoint("TOPLEFT")
    t.rows[SWING.OffHand]:SetPoint("TOPLEFT", 0, -(mh + gap))

    -- the queued attack, hanging off the main hand's right end
    t.queued = CreateFrame("Frame", nil, t)
    t.queued:SetSize(QUEUE, QUEUE)
    t.queued:SetPoint("LEFT", t.rows[SWING.MainHand], "RIGHT", S["space-2"], 0)
    t.queued.art = t.queued:CreateTexture(nil, "ARTWORK")
    t.queued.art:SetPoint("TOPLEFT", 1, -1)
    t.queued.art:SetPoint("BOTTOMRIGHT", -1, 1)
    t.queued.art:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    UI.Border(t.queued, "ink")
    t.queued:Hide()

    t:SetScript("OnUpdate", function(self) self:Tick() end)
    return t
end

--------------------------------------------------------------------------------
-- Drawing
--------------------------------------------------------------------------------

-- Whether a slot has a weapon that swings; nil when the client won't say.
local function canSwing(kind)
    if kind == SWING.MainHand then return true end
    local _, oh, ranged = UnitAttackSpeed("player")
    local speed = kind == SWING.OffHand and oh or ranged
    if isSecret(speed) then return nil end
    return type(speed) == "number" and speed > 0
end

function ST:UpdateRows()
    for kind, r in pairs(self.rows) do
        local can = canSwing(kind)
        if can ~= nil then r.canSwing = can end
    end
    local shooting = self.rows[SWING.Ranged].live
    self.rows[SWING.MainHand]:SetShown(not shooting)
    self.rows[SWING.Ranged]:SetShown(shooting and true or false)
    self.rows[SWING.OffHand]:SetShown(self.rows[SWING.OffHand].canSwing and not shooting and true or false)
    self.rows[SWING.MainHand].digits:SetShown(not shooting)
    self.rows[SWING.Ranged].digits:SetShown(shooting and true or false)
    self.rows[SWING.OffHand].digits:SetShown(self.rows[SWING.OffHand]:IsShown())
end

function ST:Swing(length, kind)
    if isSecret(length) or isSecret(kind) then return end
    local r = self.rows[kind]
    if not r or type(length) ~= "number" or length <= 0 then return end
    local now = GetTime()
    if r.live then
        -- the previous swing landed: the ink sliver flashes at the end
        r.flash:SetAlpha(1)
        r.flashAt = now
    end
    r.live, r.endsAt = true, now + length
    r:SetAlpha(1)
    r.duration:SetTimeFromStart(now, length)
    r.bar:SetTimerDuration(r.duration, IMMEDIATE, DIR.ElapsedTime)
    -- Forever links the timers: a melee swing restarts Auto Shot too.
    self:UpdateRows()
    self:UpdateQueued()
end

function ST:Tick()
    local now = GetTime()
    for _, r in pairs(self.rows) do
        if r.live then
            local left = r.endsAt - now
            if left <= 0 then
                r.live = false
                r:SetAlpha(T.opacity["opacity-oor"])
                r.digits:SetValue("–")
                r.bar:SetValue(0)
                self:UpdateRows()
            else
                r.digits:SetValue(("%.1f"):format(left))
            end
        end
        if r.flashAt then
            local a = 1 - (now - r.flashAt) / T.duration["dur-fast"]
            if a <= 0 then r.flashAt = nil a = 0 end
            r.flash:SetAlpha(a)
        end
    end
end

function ST:UpdateQueued()
    local ids = self.nextSwing
    local found
    if ids and C_Spell.IsCurrentSpell then
        for _, id in ipairs(ids) do
            local on = C_Spell.IsCurrentSpell(id)
            if not isSecret(on) and on then found = id break end
        end
    end
    if found then
        self.queued.art:SetTexture(C_Spell.GetSpellTexture(found))
        if not self.queued:IsShown() then ns.Motion.Pop(self.queued) end
    end
    self.queued:SetShown(found ~= nil)
end

--------------------------------------------------------------------------------
-- Events
--------------------------------------------------------------------------------

function ST:Activate()
    if self.active then return end
    self.active = true
    local _, class = UnitClass("player")
    self.nextSwing = NEXT_SWING[class]
    Events.OnGame("PLAYER_SWING", function(_, length, kind) self:Swing(length, kind) end, self)
    Events.OnGame("WEAPON_SLOT_CHANGED", function() self:UpdateRows() end, self)
    Events.OnGame("PLAYER_ENTERING_WORLD", function() self:UpdateRows() end, self)
    Events.OnUnit("UNIT_ATTACK_SPEED", "player", function() self:UpdateRows() end, self)
    if self.nextSwing then
        Events.OnGame("ACTIONBAR_UPDATE_STATE", function() self:UpdateQueued() end, self)
    end
    self:UpdateRows()
end

function ST:Deactivate()
    if not self.active then return end
    self.active = false
    Events.OffAll(self)
end
