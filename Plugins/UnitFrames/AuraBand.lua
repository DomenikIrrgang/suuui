-- AuraBand: one wrapping band of aura icons, for one unit and one aura filter.
--
-- A band is the feature minus its placement. It reads the unit's auras, keeps a row of
-- icons in step with them, wraps onto as many rows as the frame's width needs, and reports
-- its measured height through the container's SIZE_CHANGED. Where the band SITS is the unit
-- frame's decision, which is why nothing in here knows whether it is above or below
-- anything -- the frame states that by ordering its root column and by handing the band a
-- line order.
--
-- One implementation serves buffs and debuffs. They differ in four fields -- the filter,
-- which tooltip method describes them, whether a right-click cancels, and whether the
-- dispel type colours the border -- so those are a table, not a second copy of this file.
local ipairs, pairs, next, type = ipairs, pairs, next, type
local C = SuuUI.Components
local S = SuuUI.UISignals
local T = SuuUI.Theme

---------------------------------------------------------------------------
-- Kinds
---------------------------------------------------------------------------

-- Buffs and debuffs answer different questions with the same pixel, which is why `border`
-- is a function per kind rather than a shared flag.
--
-- A DEBUFF's border answers "what removes this", and every debuff gets one: the four dispel
-- types, then red for an untyped one. Red is not a fallback in practice -- most debuffs in
-- this game carry no dispel type at all, every physical one included, so it is the common
-- case, and it is the client's own `none` colour so it matches what the player reads
-- everywhere else.
--
-- A BUFF's border answers "can I take this off them". It deliberately does NOT read the
-- dispel type on its own: the client reports one for helpful auras too -- Righteous Fury
-- comes back as "Magic" -- so a type-coloured buff bar rings every blessing you carry in
-- blue while telling you nothing you can act on. `isStealable` is the client's own answer,
-- computed against YOUR class and THAT unit, so it is false across your own bar and true
-- exactly where a purge or a spellsteal would land.
local KINDS = {
    { id = "buffs",   filter = "HELPFUL", label = "Buffs",   position = "above",
      tip = "SetUnitBuff",   cancel = true,
      border = function(dispel, stealable)
          if not stealable then return nil end
          return SuuUI.Game:DebuffTypeColor(dispel)
      end },
    { id = "debuffs", filter = "HARMFUL", label = "Debuffs", position = "below",
      tip = "SetUnitDebuff", cancel = false,
      border = function(dispel)
          return SuuUI.Game:DebuffTypeColor(dispel) or SuuUI.Game:UntypedDebuffColor()
      end },
}

-- A loop bound, not a cap the player can reach: the read below stops at the first empty
-- index, so this only matters if a client ever answers for every index it is asked about.
-- The client's own buff limit is well inside it.
local MAX_INDEX = 40

-- Duration text is redrawn on a throttled ticker rather than per frame. 10/sec is fast
-- enough that a tenth-of-a-second readout never visibly skips a value.
local TICK_THROTTLE = 0.1

---------------------------------------------------------------------------
-- Shared duration ticker
--
-- ONE OnUpdate for every band in the addon, registered only while at least one band has a
-- timed aura on screen and unregistered the moment none does -- the same shape SnapGrid's
-- drag ticker uses, and for the same reason: a permanently registered OnUpdate costs a
-- frame's time forever, and four bands would each pay it.
---------------------------------------------------------------------------
local ticking, tickAccum, ticker = {}, 0, nil

local function onTick(_, elapsed)
    tickAccum = tickAccum + elapsed
    if tickAccum < TICK_THROTTLE then return end
    tickAccum = 0
    -- Iterating a hash allocates nothing, and each band's own tick reuses its slot tables.
    for band in pairs(ticking) do
        band:_tickDurations()
    end
end

local function setTicking(band, on)
    if on then
        if ticking[band] then return end
        ticking[band] = true
        if not ticker then ticker = CreateFrame("Frame") end
        ticker:SetScript("OnUpdate", onTick)
    else
        if not ticking[band] then return end
        ticking[band] = nil
        if next(ticking) == nil and ticker then
            ticker:SetScript("OnUpdate", nil)
        end
    end
end

---------------------------------------------------------------------------
-- Band widget
---------------------------------------------------------------------------
local AuraBand = {}

AuraBand.KINDS = KINDS

--- The settings key holding one band's placement.
-- @param prefix string  Unit key prefix, e.g. "target_"
-- @param kind string    "buffs" | "debuffs"
-- @return string
function AuraBand.PositionKey(prefix, kind)
    return prefix .. kind .. "_position"
end

--- The settings key holding one band's icon size.
-- @param prefix string
-- @param kind string
-- @return string
function AuraBand.SizeKey(prefix, kind)
    return prefix .. kind .. "_size"
end

--- The placement options, fresh each call: the table is handed to a Dropdown control, and
--- a shared list is one aliased table away from four controls editing each other's state.
-- @return table
function AuraBand.PositionOptions()
    return {
        { value = "above",  label = "Above Frame" },
        { value = "below",  label = "Below Frame" },
        { value = "hidden", label = "Hidden" },
    }
end

--- Where this band currently sits: "above", "below" or "hidden".
--
-- Read from the store on every ask rather than cached. The frame reads the same key to
-- order its column, and two copies of one setting is the drift section 5b exists to remove.
-- @return string
function AuraBand:Position()
    return SuuUI.Settings:Get(self._cfg.pluginId,
                              AuraBand.PositionKey(self._cfg.prefix, self._cfg.kind.id))
end

--- Whether the band is showing at all.
-- @return bool
function AuraBand:IsActive()
    return self:Position() ~= "hidden"
end

-- The icon edge, in the unit's own settings namespace. A widget dimension, so a plugin
-- setting rather than a theme token -- the spacing BETWEEN icons is design language and
-- comes from a token instead.
function AuraBand:_iconSize()
    return SuuUI.Settings:Get(self._cfg.pluginId,
                              AuraBand.SizeKey(self._cfg.prefix, self._cfg.kind.id))
end

--- The container the frame places in its column.
-- @return table
function AuraBand:GetContainer()
    return self._box
end

--- How many icons are currently on screen.
-- @return number
function AuraBand:GetCount()
    return self._count or 0
end

--- The band's contribution to the frame's height: nothing at all while it is empty.
--
-- Reported as zero rather than as the container's own height because flow layout skips a
-- hidden child together with the gap that would follow it, so a band claiming height while
-- hidden would open a dead gap above the bars.
-- @return number
function AuraBand:GetHeight()
    if not (self._box and self._box:IsShown()) then return 0 end
    local _, h = self._box:GetContentSize()
    return SuuUI.Pixel.Ceil(h or 0)
end

--- Sets which end of the band the first row sits at.
--
-- A band ABOVE the frame lays its rows bottom-up, so row one stays against the frame and a
-- new row grows away from it. Laid top-down there, gaining a row would shift every icon
-- already on screen -- the band's top edge is the one that moves.
-- @param order string|nil  "reverse" for bottom-up
function AuraBand:SetLineOrder(order)
    self._box:SetLineOrder(order)
end

---------------------------------------------------------------------------
-- Icons
---------------------------------------------------------------------------

-- Icons are kept, never destroyed: an aura set changes several times a second in combat and
-- the surplus is hidden instead, which flow layout skips along with its gap. The array IS
-- the pool -- a shared Pool would buy nothing here, since a band's icons are never handed to
-- another band (each has its own parent frame and its own icon size) and every acquire
-- would pay a re-parent and a re-size for it.
function AuraBand:_iconAt(pos, size)
    local h = self._icons[pos]
    if h then return h end

    h = C.AuraIcon({ size = size }, self._box:GetFrame())
    self._icons[pos] = h
    self._slots[pos] = {}

    -- The BAND knows which aura a slot describes and which unit it belongs to; the icon
    -- knows neither, which is what keeps it a general component. So the tooltip and the
    -- cancel are wired out here, off the icon's signals.
    S:Connect(h, S.SIGNALS.MOUSE_ENTER, function() self:_showTip(pos) end)
    S:Connect(h, S.SIGNALS.MOUSE_LEAVE, function() self:_hideTip() end)
    S:Connect(h, S.SIGNALS.CLICKED, function(btn) self:_onClick(pos, btn) end)

    self._box:Add(h, { width = size, height = size })
    return h
end

-- Points one icon at one aura. Everything here is a property patch: the icon is reused
-- across updates, so nothing is rebuilt and no geometry moves unless the aura count did.
function AuraBand:_paint(pos, index, size, icon, count, dispel, duration, expiration,
                         stealable)
    local h    = self:_iconAt(pos, size)
    local slot = self._slots[pos]

    h:SetIcon(icon)
    h:SetCount(count)

    -- Only re-arm the swipe when the timer actually moved. UNIT_AURA fires for every aura
    -- change on the unit, so an unchanged aura is re-read many times over a single cast --
    -- and re-stating an identical cooldown restarts the sweep for nothing.
    if slot.duration ~= duration or slot.expiration ~= expiration then
        h:SetTimer(duration, expiration)
    end
    slot.index      = index
    slot.duration   = duration
    slot.expiration = expiration

    -- The kind decides what its border means; see the note on KINDS. nil returns the ring
    -- to the neutral icon token.
    h:SetTypeColor(self._cfg.kind.border(dispel, stealable))

    if not h:IsShown() then h:Show() end
end

--- Re-reads the unit's auras and brings the icon row into step with them.
--
-- Called from UNIT_AURA, from a target swap, and from the settings that decide whether the
-- band exists at all -- so it must be correct from any state, including "the unit is gone".
function AuraBand:Update()
    local cfg  = self._cfg
    local size = self:_iconSize()
    local n    = 0

    if self:IsActive() and type(UnitAura) == "function" then
        for i = 1, MAX_INDEX do
            -- The 2.5.4 client returns no `rank`, so icon is the second value. isStealable
            -- is the eighth, and it is the client's own verdict on whether a purge or a
            -- spellsteal would take this aura off this unit -- not something derivable from
            -- the dispel type, which is why it is read rather than inferred.
            local name, icon, count, dispel, duration, expiration, _, stealable =
                UnitAura(cfg.unit, i, cfg.kind.filter)
            if not name then break end
            n = n + 1
            self:_paint(n, i, size, icon, count, dispel, duration, expiration, stealable)
        end
    end

    -- The tail keeps its icons and simply stops taking part in the layout.
    for i = n + 1, #self._icons do
        local h = self._icons[i]
        if h:IsShown() then h:Hide() end
    end

    local was = self._count or 0
    self._count = n

    -- Shown or hidden as one subtree, so the icons resolve their anchors when the band
    -- appears. Safe in this direction -- unlike an attach point, the icons are parented to
    -- the very container they are anchored to, so showing it dirties them too.
    if n > 0 then
        if not self._box:IsShown() then self._box:Show() end
    elseif self._box:IsShown() then
        self._box:Hide()
    end

    -- Only the count moving changes any geometry. Icon art, stacks and timers do not, and
    -- UNIT_AURA arrives often enough in combat that re-flowing on every one of them would
    -- be work with nothing to show for it.
    if n ~= was then self._box:Layout() end

    self:_syncTicker()
end

--- Re-derives everything that comes from settings or tokens: the icon edge and the gap
--- between icons. Bound to both the size slider and SUUUI_THEME_CHANGED.
function AuraBand:Relayout()
    local size = self:_iconSize()
    -- One token for both axes: not passing lineGap leaves it tracking gap, so a band's rows
    -- and its columns are spaced alike without a second value to keep in step.
    self._box:SetGap(T:GetToken("spaceXxs"))
    for i = 1, #self._icons do
        self._box:SetChildProps(self._icons[i], { width = size, height = size })
    end
    self._box:Layout()
end

---------------------------------------------------------------------------
-- Duration readouts
---------------------------------------------------------------------------

-- One GetTime for the whole band rather than one per icon: every icon in it is measuring
-- against the same instant.
function AuraBand:_tickDurations()
    local now = (type(GetTime) == "function") and GetTime() or 0
    for i = 1, self._count or 0 do
        local slot, h = self._slots[i], self._icons[i]
        if slot and h and slot.duration and slot.duration > 0 and slot.expiration then
            local left = slot.expiration - now
            h:SetTimeLeft(left > 0 and left or nil)
        end
    end
end

-- A band with nothing timed on screen leaves the ticker alone. A permanent buff has a
-- duration of 0, so a bar of paladin blessings costs no ticks at all.
function AuraBand:_syncTicker()
    local timed = false
    for i = 1, self._count or 0 do
        local slot = self._slots[i]
        if slot and slot.duration and slot.duration > 0 then
            timed = true
            break
        end
    end
    setTicking(self, timed)
    -- Painted now rather than on the next tick: a readout that appears a tenth of a second
    -- after its icon reads as a glitch, and the same immediacy is what lets a spec assert
    -- the text without advancing a clock.
    if timed then self:_tickDurations() end
end

---------------------------------------------------------------------------
-- Tooltip and cancel
--
-- Blizzard's own tooltip, deliberately. It is the only thing that can describe an aura --
-- the spell's text, its remaining time, who cast it -- because no API hands that out for a
-- themed tooltip to re-render. So this is game data plumbing, not our UI, and it is the
-- same carve-out that lets this plugin read UnitHealth.
---------------------------------------------------------------------------

function AuraBand:_showTip(pos)
    local slot = self._slots[pos]
    if not (slot and slot.index) then return end
    local tip = GameTooltip
    if type(tip) ~= "table" or not tip.SetOwner then return end
    tip:SetOwner(self._icons[pos]:GetFrame(), "ANCHOR_RIGHT")
    -- Indexed by the aura index the last Update recorded, never by the icon's position.
    -- They agree today because nothing is filtered out; reading the position would make a
    -- filter silently describe the wrong aura.
    local fn = tip[self._cfg.kind.tip]
    if fn then fn(tip, self._cfg.unit, slot.index) end
    tip:Show()
end

function AuraBand:_hideTip()
    local tip = GameTooltip
    if type(tip) == "table" and tip.Hide then tip:Hide() end
end

function AuraBand:_onClick(pos, btn)
    if btn ~= "RightButton" then return end
    -- Only a buff can be cancelled, and only on yourself. The client refuses the rest, so
    -- the guard belongs here rather than in the error log.
    if not self._cfg.kind.cancel or self._cfg.unit ~= "player" then return end
    local slot = self._slots[pos]
    if not (slot and slot.index) then return end
    if type(CancelUnitBuff) == "function" then
        CancelUnitBuff(self._cfg.unit, slot.index)
    end
    -- No repaint here: cancelling fires UNIT_AURA, and that is the one path that repaints.
end

---------------------------------------------------------------------------
-- Lifecycle
---------------------------------------------------------------------------

--- Creates a band.
-- @param parent frame  The unit frame's wrapper
-- @param cfg table  { unit, pluginId, prefix, kind }
--   kind: an entry from AuraBand.KINDS
-- @return table  AuraBand handle
function AuraBand:Create(parent, cfg)
    local self = setmetatable({ _cfg = cfg, _icons = {}, _slots = {}, _count = 0 },
                              { __index = AuraBand })

    self._box = SuuUI.Layout:CreateContainer({
        parent = parent,
        layout = "flow",
        dir    = "horizontal",
        gap    = T:GetToken("spaceXxs"),
        wrap   = true,
    })
    -- Empty until the unit has an aura. Hidden rather than zero-height: flow layout skips a
    -- hidden child and the gap after it, while a visible empty one still claims its gap.
    self._box:Hide()

    return self
end

function AuraBand:Destroy()
    setTicking(self, false)
    for i = 1, #self._icons do
        -- DisconnectAll happens inside the icon's own Destroy, which retires the tooltip
        -- and cancel connections this band made on it.
        self._icons[i]:Destroy()
    end
    self._icons, self._slots, self._count = {}, {}, 0
    self._box:Destroy()
    self._box = nil
end

SuuUI._UnitFrames = SuuUI._UnitFrames or {}
SuuUI._UnitFrames.AuraBand = AuraBand
