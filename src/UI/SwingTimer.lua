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
--
-- Auto Shot (the ranged row): the last half second of a shot is a cast you
-- must stand still for, drawn as a hatched window at the bar's end. Moving
-- inside it turns the edge, the window and the digits amber ("Moving"), and
-- the shot waits until you stop. Whether Forever's client has that cast is
-- learned: if shots keep firing on time while you run through the window,
-- the window goes away (t:SetAutoShotWindow(on), opts.onNoAutoShotCast).
--   t:SetAutoShotWindow(on)
--   t:SetBarWidth(px)    -- 0.9: live (it follows your cast bar's width)

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

local DIGITS_W = 40
local QUEUE = 16
local HATCH = "Interface\\AddOns\\SuuUI\\Media\\Textures\\Hatch.tga"
local CAST = 0.5   -- Auto Shot's stand-still cast, seconds
local GRACE = 0.35 -- a shot this late still counts as on time

local ST = {}

--------------------------------------------------------------------------------
-- Rows
--------------------------------------------------------------------------------

-- The stand-still window at the end of the ranged bar: a hatch with a 1px
-- left edge, ink at rest, amber while you move inside it.
local function buildWindow(r)
    local w = CreateFrame("Frame", nil, r)
    w:SetPoint("TOPRIGHT", -1, -1)
    w:SetPoint("BOTTOMRIGHT", -1, 1)
    w:SetFrameLevel(r.bar:GetFrameLevel() + 1)
    w.hatch = w:CreateTexture(nil, "ARTWORK")
    w.hatch:SetAllPoints()
    w.hatch:SetTexture(HATCH, "REPEAT", "REPEAT")
    w.hatch:SetHorizTile(true)
    w.hatch:SetVertTile(true)
    w.edge = w:CreateTexture(nil, "OVERLAY")
    w.edge:SetPoint("TOPLEFT")
    w.edge:SetPoint("BOTTOMLEFT")
    w.edge:SetWidth(1)
    w:Hide()
    r.window = w
end

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
    UI.PaintGradient(tex, "HORIZONTAL", "ghost", "ghost", 0)
    bar:SetMinMaxValues(0, 1)
    bar:SetValue(0)
    r.spark = bar:CreateTexture(nil, "OVERLAY")
    UI.PaintFill(r.spark, "ink")
    r.spark:SetPoint("TOPRIGHT", tex, "TOPRIGHT")
    r.spark:SetPoint("BOTTOMRIGHT", tex, "BOTTOMRIGHT")
    r.spark:SetWidth(2)
    r.bar = bar
    r.border = UI.Border(r, "gilt-hairline", { layer = "OVERLAY" })
    -- the landed flash: an ink sliver at the end that fades over dur-fast
    r.flash = r:CreateTexture(nil, "OVERLAY", nil, 2)
    UI.PaintFill(r.flash, "ink")
    r.flash:SetPoint("TOPRIGHT")
    r.flash:SetPoint("BOTTOMRIGHT")
    r.flash:SetWidth(3)
    r.flash:SetAlpha(0)
    r.digits = UI.Text(t, "micro", "ink")
    r.digits:SetShadowed(true)
    -- the digits hang directly off the bar's end; the main hand's move past
    -- the queued spell's icon while one waits (ST:UpdateQueued)
    r.digits:SetJustifyH("LEFT")
    r.digits:SetWidth(DIGITS_W)
    r.digits:SetPoint("LEFT", r, "RIGHT", S["space-2"], 0)
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
    buildWindow(t.rows[SWING.Ranged])
    t.autoShotWindow = opts.autoShotWindow ~= false
    t.onNoAutoShotCast = opts.onNoAutoShotCast
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
-- Only the off hand can lack one (the ranged row shows while you shoot).
local function canSwing(kind)
    if kind ~= SWING.OffHand then return true end
    local _, oh = UnitAttackSpeed("player")
    if isSecret(oh) then return nil end
    return type(oh) == "number" and oh > 0
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

-- Delayed (moving inside the window) or at rest: colours of the ranged row.
function ST:SetDelayed(r, delayed)
    if r.delayed == delayed then return end
    r.delayed = delayed
    local token = delayed and "amber" or "ink-muted"
    UI.Paint(r.window.hatch, token, delayed and 0.6 or 0.2)
    UI.PaintFill(r.window.edge, token)
    r.border:SetColor(delayed and "amber" or "gilt-hairline")
    UI.PaintFill(r.spark, delayed and "amber" or "ink")
    r.digits:SetColor(delayed and "amber" or "ink")
end

function ST:SetBarWidth(w)
    self.barW = UI.Size(w)
    self:SetWidth(self.barW)
    for kind, r in pairs(self.rows) do
        r:SetWidth(self.barW)
        -- a shot in flight keeps its window's share of the new width
        if kind == SWING.Ranged and r.window:IsShown() and r.endsAt and r.length then
            r.window:SetWidth(math.max(2, (self.barW - 2) * math.min(1, CAST / r.length)))
        end
    end
end

function ST:SetAutoShotWindow(on)
    self.autoShotWindow = on and true or false
    local r = self.rows[SWING.Ranged]
    if not self.autoShotWindow then
        r.window:Hide()
        self:SetDelayed(r, false)
    end
end

-- A shot just landed: did it come on time although you ran through the whole
-- window? Twice in a row means this client has no stand-still cast.
function ST:LearnAutoShot(r, now)
    if not (self.autoShotWindow and r.live and r.endsAt) then return end
    local ranThrough = self.movingSince and self.movingSince <= r.endsAt - CAST
    if not ranThrough then return end
    if now <= r.endsAt + GRACE then
        self.onTimeWhileMoving = (self.onTimeWhileMoving or 0) + 1
        if self.onTimeWhileMoving >= 2 then
            self:SetAutoShotWindow(false)
            if self.onNoAutoShotCast then self.onNoAutoShotCast() end
        end
    else
        self.onTimeWhileMoving = 0 -- the shot waited: the cast is real
    end
end

function ST:Swing(length, kind)
    if isSecret(length) or isSecret(kind) then return end
    local r = self.rows[kind]
    if not r or type(length) ~= "number" or length <= 0 then return end
    local now = GetTime()
    if kind == SWING.Ranged then
        self:LearnAutoShot(r, now)
        if self.autoShotWindow then
            r.window:SetWidth(math.max(2, (self.barW - 2) * math.min(1, CAST / length)))
            r.window:Show()
        end
        self:SetDelayed(r, false)
    end
    if r.live then
        -- the previous swing landed: the ink sliver flashes at the end
        r.flash:SetAlpha(1)
        r.flashAt = now
    end
    r.live, r.endsAt, r.length = true, now + length, length
    r:SetAlpha(1)
    r.duration:SetTimeFromStart(now, length)
    r.bar:SetTimerDuration(r.duration, IMMEDIATE, DIR.ElapsedTime)
    -- Forever links the timers: a melee swing restarts Auto Shot too.
    self:UpdateRows()
    self:UpdateQueued()
end

function ST:Tick()
    local now = GetTime()
    for kind, r in pairs(self.rows) do
        if r.live and kind == SWING.Ranged and self.autoShotWindow and self.shooting then
            -- Auto Shot: moving inside the window holds the shot.
            local left = r.endsAt - now
            local delayed = self.moving and left <= CAST
            self:SetDelayed(r, delayed)
            if delayed then
                r.digits:SetValue("Moving")
            elseif left > 0 then
                r.digits:SetValue(("%.1f"):format(left))
            elseif not self.moving and now - math.max(r.endsAt, (self.stoppedAt or 0) + CAST) > GRACE then
                -- standing still past the cast and still no shot: Auto Shot ended
                r.live = false
                r.window:Hide()
                r:SetAlpha(T.opacity["opacity-oor"])
                r.digits:SetValue("–")
                r.bar:SetValue(0)
                self:UpdateRows()
            end
        elseif r.live then
            local left = r.endsAt - now
            if left <= 0 then
                r.live = false
                if r.window then r.window:Hide(); self:SetDelayed(r, false) end
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
    local digits = self.rows[SWING.MainHand].digits
    digits:ClearAllPoints()
    digits:SetPoint("LEFT", self.rows[SWING.MainHand], "RIGHT", S["space-2"] + (found and (QUEUE + S["space-2"]) or 0), 0)
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
    -- Auto Shot: whether you shoot, and whether you move.
    Events.OnGame("START_AUTOREPEAT_SPELL", function() self.shooting = true end, self)
    Events.OnGame("STOP_AUTOREPEAT_SPELL", function() self.shooting = false end, self)
    Events.OnGame("PLAYER_STARTED_MOVING", function() self.moving = true; self.movingSince = GetTime() end, self)
    Events.OnGame("PLAYER_STOPPED_MOVING", function()
        self.moving, self.movingSince, self.stoppedAt = false, nil, GetTime()
    end, self)
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
