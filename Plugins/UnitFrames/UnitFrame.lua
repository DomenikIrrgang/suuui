-- UnitFrames plugin: the unit frame widget.
--
-- One implementation serves every unit. A unit differs only by its config — which unit
-- token to read, which settings prefix its keys carry, whether it is always there — so
-- nothing about the player is baked in here and target, focus or party need no new widget
-- code. This is the same split CastBar.lua uses, and for the same reason: the second copy
-- is the one that drifts.
--
-- Layout, top to bottom: the aura bands and an attach band, a name/level row, the health
-- and resource bars, then the same bands again on the other side. Which side each aura band
-- takes is a setting, so the column's order is restated rather than fixed -- see _stack.
local format, floor = string.format, math.floor
local ipairs, type = ipairs, type
local C = SuuUI.Components
local S = SuuUI.UISignals
local T = SuuUI.Theme
-- Loaded ahead of this file by the .toc, which is how every dependency in the addon is
-- expressed. The band owns everything about an aura row; this file owns only where it sits.
local AuraBand = SuuUI._UnitFrames.AuraBand

---------------------------------------------------------------------------
-- Bar colours
---------------------------------------------------------------------------
-- Power colours are facts about the client, shared with anything else that paints one, so
-- they come from SuuUI.Game rather than being restated here.
--
-- Health is the same shape one layer up. WHICH colour a unit gets — its class, or its
-- reaction when it has no class — is a fact in SuuUI.Game, while whether health is
-- coloured that way at all is a look decision living in the theme as colorUseClassColors.
-- Theme:GetUnitColor resolves the chain, so this widget names the fallback token and
-- nothing else: no class table, no reaction table, no flag check, and therefore no second
-- copy of that policy for the target frame to drift from.
local HEALTH_COLOR = "colorHealth"

-- The empty part of a bar is the colorBarTrack semantic, passed to StatusBar as a token
-- KEY rather than a resolved colour: the bar re-resolves it on every theme change, so
-- editing the token or switching theme repaints the track with no work here.
local BAR_TRACK = "colorBarTrack"

---------------------------------------------------------------------------
-- Layout metrics
--
-- Two sources, split by what the value actually is:
--   * this widget's own dimensions come from the plugin's Settings, so they are
--     profile-aware and tunable on the Unit Frames page;
--   * spacing, font size and track opacity come from theme tokens, because they are
--     design language shared with the rest of the UI.
-- Nothing here is a literal: a width in code is a width nobody can change.
---------------------------------------------------------------------------
local INFO_FONT = "lg"  -- font size token suffix, shared by name and level

-- Settings key suffixes for a frame's dimensions, in one place so the watchers and the
-- metrics read the same list. Each is prefixed with the unit's own prefix.
--
-- power_width is here rather than in a list of its own even though it only means anything
-- while the resource bar is detached: Relayout is the single place that states geometry in
-- either mode, so watching it alongside the rest costs one no-op pass while attached and
-- removes a second watcher group that could drift from this one.
local SIZE_KEYS = { "width", "health_height", "power_height", "power_width" }

-- Suffixes that control visibility of sub-widgets. These get their own watchers rather
-- than triggering a full relayout, because toggling a text widget doesn't change bar
-- geometry.
local VIS_KEYS = { "show_name", "show_level", "hide_level_at_max" }

-- The level a unit reports when the client will not say — a mob far enough above the
-- player that its level is hidden behind a skull. It is a sentinel from the client, not a
-- number, so it is displayed as one.
local LEVEL_UNKNOWN      = -1
local LEVEL_UNKNOWN_TEXT = "??"

---------------------------------------------------------------------------
-- Bar readouts
--
-- Three independent slots overlaid inside a bar, each free to show any of the formats — so
-- a player who wants the raw number on the left and the percentage on the right gets that
-- without either position being a special case.
--
-- Both bars share one implementation. Health and power are the same question asked of two
-- numbers, so the formats, the slot loop, the watchers and the option lists are written
-- once and parameterised by the bar; a second copy is the thing that drifts, and the two
-- bars would end up offering different formats after the first change to either.
--
-- The bar takes plain strings, so what a number MEANS is decided here. These are the only
-- formats, and the setting stores which one a slot uses rather than a format string: a
-- stored pattern would be a value nothing validates and the dropdown could not describe.
---------------------------------------------------------------------------
local TEXT_SLOTS = { "left", "center", "right" }

local BAR_TEXT = {
    current_max = function(cur, mx) return format("%d / %d", cur, mx) end,
    current     = function(cur) return format("%d", cur) end,
    -- Floored, never rounded: a unit one hit from dead must not read 100%, and the moment
    -- a bar stops saying full is the whole reason to show a percentage.
    percent     = function(cur, mx)
        return format("%d%%", mx > 0 and floor(cur / mx * 100) or 0)
    end,
    -- "none" is deliberately absent: an unresolved mode leaves no formatter, which is what
    -- clears the slot. A no-op function here would need its own branch at every call site.
}

-- The bars that carry readouts, and where each reads its numbers from. The `id` is also
-- the settings key infix, so it matches the height keys already on the page
-- (`<unit>_health_height`, `<unit>_power_height`) rather than inventing a second spelling.
--
-- The value readers take the unit, so one table serves every frame: baking "player" in
-- here is exactly what made this file player-only.
local READOUT_BARS = {
    { id = "health", field = "_healthBar", label = "Health Bar",
      value = function(unit) return UnitHealth(unit) or 0, UnitHealthMax(unit) or 1 end },
    { id = "power",  field = "_resourceBar", label = "Resource Bar",
      value = function(unit) return UnitPower(unit) or 0, UnitPowerMax(unit) or 1 end },
}

-- Indexed by id for the update path, which is handed a bar name rather than iterating.
local READOUT_BARS_BY_ID = {}
for _, def in ipairs(READOUT_BARS) do READOUT_BARS_BY_ID[def.id] = def end

-- Fresh each call rather than one shared constant: the table is handed to a schema entry
-- and on to a Dropdown control — eight of them per unit — and a shared options list is one
-- aliased table away from those controls editing each other's state.
local function textOptions()
    return {
        { value = "none",        label = "None" },
        { value = "current_max", label = "Current / Max" },
        { value = "current",     label = "Current" },
        { value = "percent",     label = "Percent" },
    }
end

--- The settings key holding one slot's readout mode.
-- @param prefix string  Unit key prefix, e.g. "player_"
-- @param bar string     "health" | "power"
-- @param slot string    "left" | "center" | "right"
-- @return string
local function textKey(prefix, bar, slot)
    return prefix .. bar .. "_text_" .. slot
end

--- The settings key holding one bar's readout font step.
--
-- One setting per bar rather than one per position: three readouts on one bar at three
-- different sizes reads as a rendering fault, not as a choice. Per BAR rather than one for
-- the frame, because the two bars are different heights and the taller one can carry a
-- bigger step.
--
-- It stores a size KEY, so the pixel size still comes from the theme and a readout set to
-- Large follows a user's edit of `fontSizeLg`. A pixel value here would be this plugin
-- holding a font size of its own, which is the duplication the token scale exists to
-- prevent — and it would stop tracking the rest of the UI the moment the theme was scaled.
-- @param prefix string  Unit key prefix, e.g. "player_"
-- @param bar string     "health" | "power"
-- @return string
local function textSizeKey(prefix, bar)
    return prefix .. bar .. "_text_size"
end

-- The step both bars start at, and the schema default. Declared once here so a default and
-- the option list cannot drift apart.
local BAR_TEXT_SIZE = "md"

local function textSizeOptions()
    return {
        { value = "sm", label = "Small" },
        { value = "md", label = "Medium" },
        { value = "lg", label = "Large" },
        { value = "xl", label = "Extra Large" },
    }
end

-- Shared opts table for a transition-free bar write. Allocated once: these calls happen
-- on game events, and a fresh table per update would allocate under combat load.
local IMMEDIATE = { immediate = true }

local function metrics(cfg)
    local get = function(key) return SuuUI.Settings:Get(cfg.pluginId, cfg.prefix .. key) end
    return {
        -- widget dimensions: plugin settings
        width    = get("width"),
        health   = get("health_height"),
        resource = get("power_height"),
        -- Only consulted while the resource bar is detached: attached, the bar fills the
        -- frame and asking would let a stale slider override the frame's own width.
        resourceWidth = get("power_width"),
        -- design language: theme tokens
        infoGap  = T:GetToken("spaceXs"),
        barGap   = T:GetToken("spaceXxs"),
        fontSize = T:GetFontSize(INFO_FONT),
    }
end

---------------------------------------------------------------------------
-- Max level for this client
--
-- No single API covers every flavour: retail and recent classic builds expose
-- GetMaxLevelForPlayerExpansion, older ones only the MAX_PLAYER_LEVEL global. Probe in
-- order and return nil when none answers — an unknown cap shows the level rather than
-- hiding it, since a visible level is the safer wrong answer.
---------------------------------------------------------------------------
local function maxPlayerLevel()
    if type(GetMaxLevelForPlayerExpansion) == "function" then
        local lvl = GetMaxLevelForPlayerExpansion()
        if type(lvl) == "number" and lvl > 0 then return lvl end
    end
    if type(GetMaxPlayerLevel) == "function" then
        local lvl = GetMaxPlayerLevel()
        if type(lvl) == "number" and lvl > 0 then return lvl end
    end
    if type(MAX_PLAYER_LEVEL_TABLE) == "table" and type(GetExpansionLevel) == "function" then
        local lvl = MAX_PLAYER_LEVEL_TABLE[GetExpansionLevel()]
        if type(lvl) == "number" and lvl > 0 then return lvl end
    end
    if type(MAX_PLAYER_LEVEL) == "number" and MAX_PLAYER_LEVEL > 0 then
        return MAX_PLAYER_LEVEL
    end
    return nil
end

---------------------------------------------------------------------------
-- Unit frame widget
---------------------------------------------------------------------------
local UnitFrame = {}

--- The height the name row needs at the current font tokens. The row hugs its measured
--- text; before it has any text to measure, fall back to the font token so the frame is
--- never built collapsed. A hidden row contributes nothing: flow layout skips it, gap
--- included, so reporting 0 here is what keeps the height and the geometry in agreement.
-- @return number
function UnitFrame:_infoHeight()
    if not self._infoRow:IsShown() then return 0 end
    local measured = self._infoRow:GetHeight() or 0
    if measured > 0 then return SuuUI.Pixel.Ceil(measured) end
    local m = metrics(self._cfg)
    return SuuUI.Pixel.Ceil(m.fontSize + m.barGap)
end

--- The bar group's height: both bar tokens plus the gap between them, or the health bar
--- alone once the resource bar has been detached out of the group.
--
-- Derived from the mode rather than from the group's own content size: the frame's height
-- is what sizes the group, so measuring the group here would close the loop.
-- @return number
function UnitFrame:_barsHeight()
    local m = metrics(self._cfg)
    if self:_resourceDetached() then return m.health end
    return m.health + m.barGap + m.resource
end

--- The height one attach slot contributes. An empty or hidden slot contributes nothing —
--- flow layout skips it along with its gap, so reporting anything else would open a dead
--- band in the frame.
-- @param slot table  Container handle
-- @return number
function UnitFrame:_slotHeight(slot)
    if not (slot and slot:IsShown()) then return 0 end
    local _, h = slot:GetContentSize()
    return SuuUI.Pixel.Ceil(h or 0)
end

-- Accumulates one stacked band into a running height, adding the row gap only between
-- bands that are actually present. Written as a plain function rather than a closure so
-- GetPreferredSize allocates nothing: it runs on every layout pass.
-- @return number, number  running total, count of bands added
local function addBand(total, shown, h, gap)
    if h <= 0 then return total, shown end
    if shown > 0 then total = total + gap end
    return total + h, shown + 1
end

--- The height one entry of the stacking order contributes.
--
-- Dispatched on a string rather than a stored closure so the stack table can be built once
-- and reused: this runs for every entry on every layout pass, and a closure per entry would
-- allocate on each rebuild.
-- @param e table  A _stack entry
-- @return number
function UnitFrame:_entryHeight(e)
    local what = e.what
    if what == "info" then return self:_infoHeight() end
    if what == "bars" then return self:_barsHeight() end
    if what == "aura" then return e.band:GetHeight() end
    return self:_slotHeight(e.child)
end

--- The frame's intrinsic size: width from the plugin setting, height from whatever bands
--- are currently present. Sizing flows one way, content setting the frame's height and
--- never the reverse, so there is no layout cycle to resolve even once a foreign widget has
--- attached or the unit has picked up thirty buffs.
-- @return number, number  width, height
function UnitFrame:GetPreferredSize()
    local m = metrics(self._cfg)
    local total, shown = 0, 0
    for i = 1, #self._stack do
        total, shown = addBand(total, shown, self:_entryHeight(self._stack[i]), m.infoGap)
    end
    return m.width, total
end

--- How far the frame extends past its own content, top and bottom, because of the bands
--- stacked outside it. This is what keeps the player's chosen position meaning "where my
--- bars are" rather than "where the bounding box is": a cast bar attaching below — or a
--- second row of debuffs appearing mid-fight — adds to the inset, and MoveableFrame shifts
--- the frame by exactly that much so the bars do not move.
---
--- Each present band carries the row gap with it, matching GetPreferredSize: flow layout
--- puts one gap between each pair of present children, so a band's real contribution to the
--- distance between the frame's edge and its content is its height plus one gap.
-- @return number, number  above inset, below inset
function UnitFrame:GetCoreInset()
    local gap = metrics(self._cfg).infoGap
    local above, below, seenCore = 0, 0, false
    for i = 1, #self._stack do
        local e = self._stack[i]
        if e.core then
            seenCore = true
        else
            local h = self:_entryHeight(e)
            if h > 0 then
                if seenCore then
                    below = below + h + gap
                else
                    above = above + h + gap
                end
            end
        end
    end
    return above, below
end

--- Re-states placement when the attach bands changed, so the frame's own content stays
--- put. Gated on the inset actually moving: the two slots swapping which one holds the
--- band leaves the frame the same total height, so a size comparison would miss it, while
--- re-anchoring on every layout pass would fight a drag in progress.
function UnitFrame:_syncAnchor()
    local above, below = self:GetCoreInset()
    if self._insetAbove == above and self._insetBelow == below then return end
    self._insetAbove, self._insetBelow = above, below
    SuuUI.MoveableFrame:RefreshAnchor(self._wrapper)
end

--- Resizes the wrapper to the current preferred size. The bar group fills what the name
--- row leaves, so the bars keep their token heights and only the row absorbs a font change.
function UnitFrame:_syncSize()
    local w, h = self:GetPreferredSize()
    if math.abs((self._wrapper:GetWidth() or 0) - w) > 0.5
       or math.abs((self._wrapper:GetHeight() or 0) - h) > 0.5 then
        self._wrapper:SetSize(w, h)
    end
    self:_syncAnchor()
    self:_syncClickArea()
end

--- Re-derives the click surface's rect from the frame it covers.
--
--- Absolute rather than anchored, because an anchor to the wrapper is the same dependency as
--- being its child: the client refuses to resize a frame whose movement would move a
--- protected one, and it does not care whether the link is parentage or an anchor point.
--- Proven in game by clearing that one anchor, after which the frame resized mid-combat for
--- the first time -- preferred 227 against an actual 226.99996948242, InCombatLockdown() true.
---
--- The cost of absolute placement is that this has to be re-derived whenever the frame moves
--- or resizes, which is why it is called from _syncSize AND from a watcher on the frame's
--- stored position. Skipped in combat, since the surface is itself protected: an attempt
--- costs the player a chat error for a call we already know is refused. Catching up on
--- PLAYER_REGEN_ENABLED costs at most that a band strip which appeared mid-fight is not
--- click-to-target until the fight ends; clicking the bars works throughout.
function UnitFrame:_syncClickArea()
    if not (self._clickArea and self._clickBox) then return end
    if type(InCombatLockdown) == "function" and InCombatLockdown() then
        self._clickDeferred = true
        return
    end
    self._clickDeferred = nil

    local root = SuuUI.UIRoot:GetRootContainer():GetFrame()
    local wl, wt = self._wrapper:GetLeft(), self._wrapper:GetTop()
    local rl, rt = root:GetLeft(), root:GetTop()
    -- A frame the client has not laid out yet reports nothing. Leaving the surface where it
    -- was is right: the next pass re-derives it, and a wrong rect is worse than a stale one.
    if not (wl and wt and rl and rt) then return end

    -- Root space: x grows right, and AnchorLayout's y grows DOWN from the top edge, while
    -- the client's GetTop grows up -- hence wt - rt, which is zero or negative.
    local x, y = wl - rl, wt - rt
    local w, h = self._wrapper:GetWidth() or 0, self._wrapper:GetHeight() or 0
    local a = self._clickAnchor
    if a.x == x and a.y == y and a.width == w and a.height == h then return end
    a.x, a.y, a.width, a.height = x, y, w, h
    self._clickBox:SetChildAnchor(self._clickArea, a)
end

---------------------------------------------------------------------------
-- Column order
--
-- The frame's own content — the name row and the bars — never moves in the column. What
-- moves is what sits OUTSIDE it: two aura bands, each of which the player can put above the
-- frame, below it, or nowhere. So the order is restated from the settings rather than fixed
-- at construction, and it is stated ONCE: this list is what the column is built from, what
-- the frame's height is summed from, and what the core inset is measured against. Three
-- copies of a stacking order is three chances for the height to disagree with the layout.
--
-- Outward from the bars on each side: the attach slot first (a cast bar is a bar, so it
-- belongs against the frame's own bars), then buffs, then debuffs. Buffs sit inside debuffs
-- because that is where the player asked for them.
---------------------------------------------------------------------------

-- Ordered outermost-first for the "above" side. Reversed on the way out for "below", so one
-- list states the nesting for both sides and they cannot drift apart.
local BAND_NESTING = { "debuffs", "buffs" }

--- Rebuilds the column and the stacking order from the current placement settings.
--
-- Cheap to call and only called when placement actually changes -- construction, a position
-- dropdown, a profile switch. Container:Remove is a membership operation: it neither hides
-- nor unparents, so a child that keeps its place is re-seated rather than disturbed.
function UnitFrame:_restackRoot()
    local stack, n = {}, 0
    local function push(entry)
        n = n + 1
        stack[n] = entry
    end

    for i = 1, #BAND_NESTING do
        local band = self._bands[BAND_NESTING[i]]
        if band:Position() == "above" then push({ what = "aura", band = band }) end
    end
    push({ what = "slot", child = self._slotAbove })
    push({ what = "info", child = self._infoRow, core = true })
    push({ what = "bars", child = self._bars,    core = true })
    push({ what = "slot", child = self._slotBelow })
    for i = #BAND_NESTING, 1, -1 do
        local band = self._bands[BAND_NESTING[i]]
        if band:Position() == "below" then push({ what = "aura", band = band }) end
    end

    self._stack = stack

    -- Re-seat the column. Removing by frame because that is what GetChildren reports.
    local current = self._root:GetChildren()
    for i = #current, 1, -1 do
        self._root:Remove(current[i])
    end
    for i = 1, n do
        local e = stack[i]
        local child = e.band and e.band:GetContainer() or e.child
        -- The bar group is the one child whose height is stated rather than hugged, and it
        -- is stated here as well as in Relayout so a restack never leaves it collapsed
        -- waiting for the next settings change.
        if e.what == "bars" then
            self._root:Add(child, { width = "fill", height = self:_barsHeight() })
        else
            self._root:Add(child, { width = "fill" })
        end
    end
end

--- Brings the aura bands into agreement with their placement settings.
function UnitFrame:SyncAuraPlacement()
    self:_restackRoot()
    for i = 1, #AuraBand.KINDS do
        local band = self._bands[AuraBand.KINDS[i].id]
        -- A band above the frame stacks its rows bottom-up, so row one stays against the
        -- frame and a new row grows away from it rather than shoving the first row along.
        band:SetLineOrder(band:Position() == "above" and "reverse" or nil)
        -- A band switched on may have been skipped by every update while it was hidden.
        band:Update()
    end
    self:_syncSize()
    self._root:Layout()
end

--- Re-reads both aura bands. Driven by UNIT_AURA and by anything that changes which unit
--- the frame describes.
function UnitFrame:UpdateAuras()
    for i = 1, #AuraBand.KINDS do
        self._bands[AuraBand.KINDS[i].id]:Update()
    end
    -- A band that gained or lost a row changed the frame's height, and the inset with it.
    self:_syncSize()
end

---------------------------------------------------------------------------
-- Resource bar placement
--
-- The resource bar is either INLINE — a child of the bar group, directly under the health
-- bar, taking the frame's width and moving with it — or DETACHED, parented to the UI root
-- with its own width and its own edit-mode position. Same split the cast bar draws, and
-- for the same reason: a player who wants their resource somewhere else on the screen is
-- not asking for a different bar, only for a different place to put it.
--
-- A mode change REBUILDS the bar rather than re-parenting it, which is the one thing here
-- that is not a property patch: the bar's parent differs between the modes and no property
-- expresses that. It is lossless — every value is re-read from the unit on the way out —
-- and it only ever runs on a deliberate settings change, never on a game event.
---------------------------------------------------------------------------

--- Whether the resource bar is currently living outside the frame.
-- @return bool
function UnitFrame:_resourceDetached()
    return self._resourceMode == "detached"
end

-- The mode the settings ask for. Anything other than "detached" is inline, so a
-- hand-edited SavedVariable holding a value this version does not know still resolves to
-- the bar being where the player can see it.
function UnitFrame:_wantedResourceMode()
    local anchor = SuuUI.Settings:Get(self._cfg.pluginId, self._cfg.prefix .. "power_anchor")
    return anchor == "detached" and "detached" or "attached"
end

--- Re-derives everything about the resource bar that lives in Settings rather than on the
--- bar itself: its readout font step, its three formatters, and its current value.
--
-- Needed because a rebuild replaces the widget the readout watchers already fired against.
-- Nothing is cached here — both this and those watchers read the store — so the two paths
-- cannot disagree about what the settings say.
function UnitFrame:_adoptResourceBar()
    local cfg = self._cfg
    self._resourceBar:SetTextSize(
        SuuUI.Settings:Get(cfg.pluginId, textSizeKey(cfg.prefix, "power")))
    self:_syncTextModes("power")
    -- Establishing values on a new bar, not moving them, so it adopts them outright rather
    -- than sweeping up from empty.
    self:UpdatePower(true)
end

--- Shows or hides a detached resource bar to match the frame's own presence.
--
-- An inline bar needs none of this: it is inside the wrapper, so hiding the wrapper takes
-- it down as part of the subtree. A detached bar is parented to the root instead, which is
-- exactly what puts it outside that guarantee — a target's resource bar left on screen
-- with nothing targeted would be showing numbers for a unit that is not there.
function UnitFrame:_syncResourcePresence()
    if not (self:_resourceDetached() and self._resourceBar) then return end
    if self._present then
        self._resourceWrapper:Show()
    else
        self._resourceWrapper:Hide()
    end
end

-- Destroys the current resource bar and releases whatever the mode it was in had claimed.
function UnitFrame:_teardownResourceBar()
    if not self._resourceBar then return end
    if self:_resourceDetached() then
        SuuUI.MoveableFrame:Remove(self._resourceWrapper)
        SuuUI.UIRoot:RemoveElement(self._resourceWrapper)
        -- Handle then container, as everywhere else in this file. The container destroys
        -- its children too, so the bar takes a second Destroy — which StatusBar guards
        -- every field access against, exactly as _healthBar and _bars already rely on.
        self._resourceBar:Destroy()
        self._resourceBox:Destroy()
        self._resourceWrapper:Hide()
        self._resourceWrapper, self._resourceBox = nil, nil
    else
        self._bars:Remove(self._resourceBar)
        self._resourceBar:Destroy()
    end
    self._resourceBar  = nil
    self._resourceMode = nil
end

-- The props every resource bar carries, in either mode. One table so detaching cannot
-- quietly change how the bar looks — only where it is.
function UnitFrame:_resourceBarProps()
    return {
        fillColor = SuuUI.Game:PowerColor(0),  -- default to mana; UpdatePower re-resolves
        bgColor   = BAR_TRACK,
        border    = false,
        -- Energy and rage tick faster than a fixed-duration ease completes, and each
        -- event would restart one — so the bar would trail its true value continuously
        -- and never settle. Constant speed converges instead.
        transition = "rate",
    }
end

-- Builds the resource bar in the given mode. The caller has already torn down whatever
-- was there.
function UnitFrame:_buildResourceBar(mode)
    local cfg = self._cfg
    local m = metrics(cfg)

    if mode ~= "detached" then
        self._resourceBar = C.StatusBar(self:_resourceBarProps(), self._bars:GetFrame())
        -- Membership only, no height: Relayout below is the single place that states it,
        -- and it runs on the way out of every path that reaches here.
        --
        -- Added after the health bar, which never leaves the group, so insertion order puts
        -- the resource bar back underneath it on every re-inline.
        self._bars:Add(self._resourceBar, { width = "fill" })
        self._resourceMode = "attached"
        self:_adoptResourceBar()
        self:Relayout()
        return
    end

    -- Detached: a bare wrapper carries the drag and the saved position, and the bar fills
    -- it. MoveableFrame hosts its own overlay container on the frame it is given, so it
    -- gets a frame of its own rather than the bar's — which already hosts one.
    local root = SuuUI.UIRoot:GetRootContainer()
    self._resourceWrapper = CreateFrame("Frame", nil, root:GetFrame())
    self._resourceWrapper:SetSize(m.resourceWidth, m.resource)

    self._resourceBox = SuuUI.Layout:CreateContainer({
        host   = self._resourceWrapper,
        layout = "stack",
    })

    self._resourceBar = C.StatusBar(self:_resourceBarProps(), self._resourceWrapper)
    self._resourceBox:Add(self._resourceBar)

    -- Player-facing game UI, so the content rung — stated rather than inherited, so a
    -- settings window or a modal is guaranteed to draw over it.
    SuuUI.UIRoot:SetLayer(self._resourceWrapper, "normal")

    -- Its own position key, so the bar remembers where it was dragged independently of the
    -- frame it came out of. No coreInset: nothing attaches to this, so its bounding box and
    -- its content are the same thing.
    SuuUI.MoveableFrame:Apply(self._resourceWrapper, {
        pluginId    = cfg.pluginId,
        key         = cfg.prefix .. "power_position",
        displayName = cfg.displayName .. " Resource Bar",
        defaults    = cfg.powerPosition,
    })

    self._resourceMode = "detached"
    self:_adoptResourceBar()
    -- Presence is resolved for the frame already, and a bar built while the unit is absent
    -- must not appear just because it was rebuilt.
    self:_syncResourcePresence()
    self:Relayout()
end

--- Brings the resource bar's placement into agreement with the settings.
--
-- Gated on the mode actually changing: this runs from a watcher that also fires on a
-- profile switch, and rebuilding a bar that is already in the right place would drop the
-- fill mid-transition for nothing.
function UnitFrame:SyncResourcePlacement()
    local want = self:_wantedResourceMode()
    if want == self._resourceMode then return end
    self:_teardownResourceBar()
    self:_buildResourceBar(want)
end

---------------------------------------------------------------------------
-- Presence
--
-- A frame for a unit that is not there is not an empty frame, it is no frame: the client
-- has nothing to put in it, and Blizzard's own target frame disappears for the same
-- reason. Edit mode is the exception — the player has to be able to find and drag the
-- target frame while nothing is targeted — which is the same reason a cast bar shows a
-- preview rather than vanishing.
--
-- A unit that always exists (the player) skips the whole question through cfg.always, so
-- nothing about the player frame depends on UnitExists being answerable.
---------------------------------------------------------------------------

--- Whether the unit this frame describes is currently there.
-- @return bool
function UnitFrame:UnitPresent()
    if self._cfg.always then return true end
    return type(UnitExists) == "function" and UnitExists(self._cfg.unit) == true
end

--- Whether the frame should be on screen at all.
-- @return bool
function UnitFrame:_shouldShow()
    if self:UnitPresent() then return true end
    return SuuUI.ToggleUI:IsEditMode() == true
end

--- Shows or hides the whole frame to match the unit's presence.
--
-- The WRAPPER is what gets hidden, not the containers inside it. Hiding an inner container
-- would leave the attach slots anchored to a frame with no rect, which is how an attached
-- cast bar ends up permanently invisible; hiding the wrapper takes the slots and anything
-- attached into them down as one subtree, and showing it dirties that whole subtree so
-- every child resolves again.
function UnitFrame:_syncPresence()
    local show = self:_shouldShow()
    if show == self._present then return end
    self._present = show
    if show then
        self._wrapper:Show()
        -- Every value is being established rather than changing, so the bars adopt them
        -- outright instead of sweeping up from wherever the last unit left them.
        self:UpdateAll(true)
    else
        self._wrapper:Hide()
        -- The unit is gone and nothing else will say so: UNIT_AURA does not fire for a unit
        -- that stopped existing, and the change event's own repaint is skipped precisely
        -- because the frame is now absent. Left alone the bands keep the old unit's icons —
        -- and, the part that costs something, keep their slots in the shared duration
        -- ticker, so a dropped target goes on paying ten ticks a second to count down auras
        -- on a unit nobody can see. The bars need no equivalent: they are read on their own
        -- unit events, and a hidden bar showing a stale fill costs nothing.
        self:UpdateAuras()
    end
    -- A detached bar is not inside the wrapper, so hiding the wrapper does not reach it.
    self:_syncResourcePresence()
end

--- Re-resolves the health bar's fill colour.
--
-- Called from Relayout, so a theme switch or a live edit of either the Health primitive or
-- the Use Class Colours toggle repaints without a reload; from UpdateAll, because a unit's
-- class is not knowable until it exists and the first paint would otherwise be stuck on
-- the fallback; and on UNIT_FACTION, because a unit's reaction can change under you — a
-- neutral mob you attack becomes hostile without ever changing class.
function UnitFrame:_applyHealthColor()
    self._healthBar:SetFillColor(T:GetUnitColor(HEALTH_COLOR, self._cfg.unit))
end

--- Re-reads every derived metric and re-lays the frame. Bound to both
--- SUUUI_THEME_CHANGED and the size settings, so moving a slider or editing a spacing
--- token takes effect immediately instead of waiting for a reload.
function UnitFrame:Relayout()
    local m = metrics(self._cfg)
    self._root:SetGap(m.infoGap)
    self._infoRow:SetGap(m.infoGap)
    self._bars:SetGap(m.barGap)
    self._slotAbove:SetGap(m.barGap)
    self._slotBelow:SetGap(m.barGap)
    -- The bands hold their own spacing token and their icon size, so they re-derive
    -- themselves rather than being told what either is from out here.
    for i = 1, #AuraBand.KINDS do
        self._bands[AuraBand.KINDS[i].id]:Relayout()
    end
    self._bars:SetChildProps(self._healthBar,   { width = "fill", height = m.health })
    -- The resource bar's geometry depends on who owns its width. Inline it fills the frame
    -- and only its height is stated; detached it owns both, so the wrapper carries them and
    -- the bar fills that instead. Guarded because Relayout also runs from the theme hook,
    -- which can fire before the placement watcher has built anything.
    if self:_resourceDetached() then
        self._resourceWrapper:SetSize(m.resourceWidth, m.resource)
        self._resourceBox:Layout()
    elseif self._resourceBar then
        self._bars:SetChildProps(self._resourceBar, { width = "fill", height = m.resource })
    end
    self._root:SetChildProps(self._bars, { width = "fill", height = self:_barsHeight() })
    self:_applyHealthColor()
    self:_syncSize()
    self._root:Layout()
end

--- Theme hook. Same work as a settings change, so it shares one path.
function UnitFrame:ApplyTheme()
    self:Relayout()
end

--- Re-applies the name/level visibility settings and re-sizes the frame.
--- UpdateInfo already resolves both settings, so this adds only the size pass: hiding
--- both texts collapses the info row, which changes the frame's height.
function UnitFrame:SyncVisibility()
    self:UpdateInfo()
    self:_syncSize()
end

-- One attach slot: an empty vertical band another plugin can place a widget into. Hidden
-- while empty, because flow layout skips a hidden child together with its gap — a visible
-- zero-height slot would still claim a gap and leave a dead band in the frame.
function UnitFrame:_createSlot()
    local slot = SuuUI.Layout:CreateContainer({
        parent = self._wrapper,
        layout = "flow",
        dir    = "vertical",
        gap    = metrics(self._cfg).barGap,
    })
    slot:Hide()
    return slot
end

--- Places a foreign widget into one of the frame's attach slots.
--
-- This frame keeps ownership of placement: a consumer hands over its child and never
-- touches this plugin's containers, which is what keeps the two plugins uncoupled. The
-- child is stretched to the frame's content width, so an attached widget is exactly as
-- wide as the unit frame and follows the width slider without knowing it exists.
-- @param child frame|table  Frame, component handle or container
-- @param opts table|nil     { position = "above"|"below" } — default "below"
-- @return table  The slot container the child landed in
function UnitFrame:AttachChild(child, opts)
    local slot = (opts and opts.position == "above") and self._slotAbove or self._slotBelow
    -- Shown BEFORE the child is added, and the order is the whole fix.
    --
    -- A hidden frame has no rect in this client, and a child anchored to a frame with no
    -- rect never resolves one of its own: GetTop() stays nil for ever while the child
    -- reports the size it was assigned, claims to be shown and visible, and draws nothing.
    -- Adding first left the very first attached cast bar permanently invisible.
    --
    -- The failure was hard to see because it is first-attach only: the slot stays shown
    -- afterwards, so every later attach anchors to a frame that already has a rect — which
    -- is why detaching and re-attaching by hand always appeared to "fix" it, and why the
    -- simulated client, which resolves an anchor chain the real one leaves unresolved, was
    -- green throughout.
    if not slot:IsShown() then slot:Show() end
    slot:Add(child, { width = "fill" })
    self:_syncSize()
    self._root:Layout()
    return slot
end

--- Removes a previously attached widget.
--
-- The child is left visible and parented where it was, exactly as Container:Remove
-- leaves it — the consumer owns that widget and decides what becomes of it.
-- @param child frame|table
-- @return bool  Whether the child was found in a slot
function UnitFrame:DetachChild(child)
    local target = (type(child) == "table" and child.GetFrame) and child:GetFrame() or child
    local found = false
    for i = 1, 2 do
        local slot = (i == 1) and self._slotAbove or self._slotBelow
        local children = slot:GetChildren()
        for j = 1, #children do
            if children[j] == target then
                slot:Remove(child)
                if #slot:GetChildren() == 0 and slot:IsShown() then slot:Hide() end
                found = true
                break
            end
        end
    end
    self:_syncSize()
    self._root:Layout()
    return found
end

--- Creates a unit frame.
-- @param parent frame
-- @param cfg table  { unit, pluginId, prefix, displayName, always, changeEvent }
--   unit:        unit token to read, e.g. "target"
--   prefix:      settings key prefix, e.g. "target_"
--   always:      true when the unit always exists, so presence is never in question
--   changeEvent: the event announcing that the unit became a different one, if any
--   powerPosition: default { point, relPoint, x, y } for a DETACHED resource bar
-- @return table  UnitFrame handle
function UnitFrame:Create(parent, cfg)
    local self = setmetatable({ _cfg = cfg }, { __index = UnitFrame })
    local m = metrics(cfg)
    -- Resolved by the readout watchers below, before anything reads them. One slot table
    -- per bar, allocated here so a watcher never has to check whether its bar exists yet.
    self._fmt = {}
    for _, def in ipairs(READOUT_BARS) do self._fmt[def.id] = {} end

    -- Bare grouping frame: no styling and no backdrop, so nothing draws behind the bars.
    -- Sized up front because the containers below lay out against a real geometry; the
    -- height is provisional until the name row has measured itself.
    self._wrapper = CreateFrame("Frame", nil, parent)
    self._wrapper:SetSize(m.width, m.infoGap + m.health + m.barGap + m.resource)

    -- Root column: an attach slot, the info row, the bar group, another attach slot.
    self._root = SuuUI.Layout:CreateContainer({
        host   = self._wrapper,
        layout = "flow",
        dir    = "vertical",
        gap    = m.infoGap,
    })

    -- Bands another plugin can place a widget into — a cast bar, say — through the attach
    -- point this plugin publishes in onEnable.
    self._slotAbove = self:_createSlot()
    self._slotBelow = self:_createSlot()

    -- One aura band per kind. Which side each takes is a setting, so they are created here
    -- and placed by _restackRoot — nothing about their order is decided at construction.
    self._bands = {}
    for _, kind in ipairs(AuraBand.KINDS) do
        self._bands[kind.id] = AuraBand:Create(self._wrapper, {
            unit     = cfg.unit,
            pluginId = cfg.pluginId,
            prefix   = cfg.prefix,
            kind     = kind,
        })
    end

    -- Info row: name, then level immediately beside it. Both hug their own text, so the
    -- level sits against the name instead of being pushed to the far edge.
    self._infoRow = SuuUI.Layout:CreateContainer({
        parent = self._wrapper,
        layout = "flow",
        dir    = "horizontal",
        gap    = m.infoGap,
        align  = "center",
    })

    self._nameText = C.Text({
        text  = "",
        size  = INFO_FONT,
        color = "text",
    }, self._infoRow:GetFrame())

    self._levelText = C.Text({
        text  = "",
        size  = INFO_FONT,
        color = "textMuted",
    }, self._infoRow:GetFrame())

    self._infoRow:Add(self._nameText,  { width = "auto" })
    self._infoRow:Add(self._levelText, { width = "auto" })

    -- Bar group: also frameless. The bars are the only painted surfaces in the widget.
    self._bars = SuuUI.Layout:CreateContainer({
        parent = self._wrapper,
        layout = "flow",
        dir    = "vertical",
        gap    = m.barGap,
    })

    self._healthBar = C.StatusBar({
        fillColor = T:GetUnitColor(HEALTH_COLOR, cfg.unit),
        bgColor   = BAR_TRACK,
        border    = false,
        -- Health moves in sparse, large steps, so a fixed-duration ease reads as the bar
        -- absorbing a hit.
        transition = "smooth",
        -- No textSize here: the readout-size watcher below runs immediately and is the
        -- single place that states it. Naming the step twice would leave the construction
        -- copy stale the moment the player changed the setting.
    }, self._bars:GetFrame())

    -- No resource bar here: where it goes is a setting, so the placement watcher below is
    -- the single place that builds it — inline in this group, or detached under the root.
    -- Building one here as well would be a second declaration, and the construction copy is
    -- the one that goes stale the moment the player detaches it.

    -- Bar heights are stated, not filled: the frame's height is derived FROM them, so a
    -- bar that sized itself from the frame would close the loop.
    --
    -- Membership only, no height: the SIZE_KEYS watcher below runs immediately and is the
    -- single place that states these heights. Repeating m.health here as well would be the
    -- duplication section 5b exists to remove -- two sites to keep in step, and the one
    -- that only runs at construction goes stale the moment a slider moves.
    self._bars:Add(self._healthBar, { width = "fill" })

    -- No height on the info row: it hugs its own text, which is what makes the frame
    -- follow the font tokens. The wrapper then tracks the row through SIZE_CHANGED.
    --
    -- The column is seated by _restackRoot rather than by four Add calls here, because the
    -- order is not a constant: two of its children are aura bands whose side is a setting.
    -- It also builds _stack, which GetPreferredSize reads — so it has to run before any
    -- watcher below can trigger a layout.
    self:_restackRoot()

    S:Connect(self._infoRow, S.SIGNALS.SIZE_CHANGED, function()
        self:_syncSize()
    end)

    -- A slot's height is set by whatever attached into it, so the frame has to follow it
    -- the same way it follows the name row — otherwise attaching a cast bar lays it out
    -- correctly inside a wrapper that is still too short for it.
    S:Connect(self._slotAbove, S.SIGNALS.SIZE_CHANGED, function()
        self:_syncSize()
    end)
    S:Connect(self._slotBelow, S.SIGNALS.SIZE_CHANGED, function()
        self:_syncSize()
    end)

    -- Same reasoning for the aura bands, and it matters more often: a band gains and loses
    -- rows during a fight, not just when the player changes a setting.
    for _, kind in ipairs(AuraBand.KINDS) do
        S:Connect(self._bands[kind.id]:GetContainer(), S.SIGNALS.SIZE_CHANGED, function()
            self:_syncSize()
        end)
    end

    -- A frame the player can click, the way the client's own unit frames answer one: left
    -- to target, right for the unit's context menu. Both actions are protected, so neither
    -- is a callback this plugin could write — the surface states them as secure attributes
    -- and the client performs them. See Components/UnitClickArea.lua.
    --
    -- IT IS NEITHER A CHILD OF THE WRAPPER NOR ANCHORED TO IT, and both halves matter.
    --
    -- A frame built from a secure template is protected, and the client refuses addon-driven
    -- geometry on anything whose movement would move that protected frame while in combat --
    -- answering with "Interface action failed because of an AddOn". Parentage is the obvious
    -- route, and it was the first one found: with the surface inside the wrapper, every
    -- _syncSize during a fight was refused, so a debuff landing mid-combat could not grow the
    -- frame and the band was carved out of a box frozen at its pre-combat height, shoving the
    -- bars down by the band's height.
    --
    -- Moving it out was not enough, and that cost another round of in-game measurement: an
    -- ANCHOR is the same dependency by another name. A surface still anchored to the wrapper
    -- kept the wrapper frozen exactly as parentage had. Proven by clearing that one anchor in
    -- game, whereupon the frame resized mid-combat for the first time: preferred 227 against
    -- an actual 226.99996948242, with InCombatLockdown() true.
    --
    -- So the surface hangs off the ROOT at an absolute position instead, and _syncClickArea
    -- re-derives that position from the wrapper's rect whenever it is legal to do so. Nothing
    -- about the wrapper's geometry depends on this frame in either direction.
    local rootFrame = SuuUI.UIRoot:GetRootContainer():GetFrame()
    -- A container that mirrors the root, so a TOPLEFT child offset IS a root-space
    -- coordinate. `fill` tracks the root, and the root only resizes with the screen.
    self._clickBox = SuuUI.Layout:CreateContainer({
        parent = rootFrame,
        layout = "anchor",
        fill   = true,
    })
    self._clickArea = C.UnitClickArea({
        unit = cfg.unit,
        name = "SuuUI_" .. cfg.pluginId .. "_click_" .. cfg.unit,
    }, self._clickBox:GetFrame())
    -- relativeTo stays nil: the container's own frame, never the wrapper.
    self._clickAnchor = {
        point         = "TOPLEFT",
        relativePoint = "TOPLEFT",
        x = 0, y = 0,
    }
    self._clickBox:Add(self._clickArea, { anchor = self._clickAnchor })
    -- Same rung as the frame it covers. Stated rather than inherited, so a settings window
    -- or a modal is guaranteed to draw over it, exactly as the wrapper does.
    SuuUI.UIRoot:SetLayer(self._clickArea:GetFrame(), "normal")

    -- Spacing and font tokens are user-editable, so the frame re-derives on a theme change
    -- rather than holding the values it was built with.
    self._themeId = "unitframes_" .. cfg.unit .. "_" .. tostring(self._wrapper)
    SuuUI.Events:On("SUUUI_THEME_CHANGED", function() self:ApplyTheme() end, self._themeId)

    -- Placement FIRST, and the order is load-bearing: this watcher is what builds the
    -- resource bar, and every watcher below it states something about a bar that has to
    -- exist already. `immediate` is therefore doing two jobs — it performs the initial
    -- build, and it re-places the bar on a profile switch, which can move it without
    -- anyone touching the dropdown.
    SuuUI.Settings:Watch(cfg.pluginId, cfg.prefix .. "power_anchor", function()
        self:SyncResourcePlacement()
    end, self._themeId .. "_power_anchor", { immediate = true })

    -- The click surface is placed in absolute root coordinates, so unlike an anchored one it
    -- does not follow the frame for free: every move has to re-derive it. This key is written
    -- by a drag, by a reset and by a profile switch, which is every way the frame moves.
    SuuUI.Settings:Watch(cfg.pluginId, cfg.prefix .. "position", function()
        -- Order matters here and watcher order is NOT ours to rely on: MoveableFrame watches
        -- this same key and may run before or after us. Apply the placement explicitly first,
        -- then derive the surface from the rect that produced -- otherwise we measure the
        -- frame's old position and leave the surface behind. RefreshAnchor reads the stored
        -- position and re-applies from scratch, so doing it here costs nothing when
        -- MoveableFrame's own watcher does it again.
        SuuUI.MoveableFrame:RefreshAnchor(self._wrapper)
        self:_syncClickArea()
    end, self._themeId .. "_click_pos")

    -- Aura bands. Placement first and immediate, for the same reason the resource bar's is:
    -- this watcher is what seats the bands in the column and gives each its line order, and
    -- it re-seats them on a profile switch, which can move them without the dropdown moving.
    for _, kind in ipairs(AuraBand.KINDS) do
        SuuUI.Settings:Watch(cfg.pluginId, AuraBand.PositionKey(cfg.prefix, kind.id),
            function()
                self:SyncAuraPlacement()
            end, self._themeId .. "_" .. kind.id .. "_position", { immediate = true })

        SuuUI.Settings:Watch(cfg.pluginId, AuraBand.SizeKey(cfg.prefix, kind.id), function()
            local band = self._bands[kind.id]
            band:Relayout()
            -- A bigger icon can re-flow the rows, which changes the band's height.
            self:_syncSize()
        end, self._themeId .. "_" .. kind.id .. "_size", { immediate = true })
    end

    -- The dimension sliders are watched with immediate = true: the watcher callback IS
    -- the first paint — no separate seeding call. It also survives a profile switch,
    -- which rewrites these values underneath us.
    for _, key in ipairs(SIZE_KEYS) do
        SuuUI.Settings:Watch(cfg.pluginId, cfg.prefix .. key, function()
            self:Relayout()
        end, self._themeId .. "_" .. key, { immediate = true })
    end

    -- Visibility settings: toggling name or level re-applies visibility and re-syncs size.
    -- NOT immediate: UpdateAll(true) below already calls UpdateInfo, and it does strictly
    -- more (seeds bar values with snap). Adding immediate would just repeat that work.
    for _, key in ipairs(VIS_KEYS) do
        SuuUI.Settings:Watch(cfg.pluginId, cfg.prefix .. key, function()
            self:SyncVisibility()
        end, self._themeId .. "_" .. key)
    end

    -- Readouts, per bar. Immediate, because the watcher IS what resolves the formatter
    -- table and the font step — reading the settings separately to seed them and then
    -- watching for changes would be two places holding the same fact, and the seed is the
    -- one that goes stale.
    for _, def in ipairs(READOUT_BARS) do
        for _, slot in ipairs(TEXT_SLOTS) do
            SuuUI.Settings:Watch(cfg.pluginId, textKey(cfg.prefix, def.id, slot), function()
                self:_syncTextModes(def.id)
                self:UpdateReadouts(def.id)
            end, self._themeId .. "_" .. textKey(cfg.prefix, def.id, slot), { immediate = true })
        end

        -- One step for every slot on this bar, applied to the bar rather than per readout.
        SuuUI.Settings:Watch(cfg.pluginId, textSizeKey(cfg.prefix, def.id), function(val)
            local widget = self[def.field]
            if widget then widget:SetTextSize(val) end
            -- The step decides the readouts' height, and a bar's own height does not follow
            -- it — so nothing else re-flows the frame after a size change.
            self:_syncSize()
        end, self._themeId .. "_" .. textSizeKey(cfg.prefix, def.id), { immediate = true })
    end

    -- Edit mode decides whether a frame with no unit is shown, so the player can position
    -- it. `immediate` matters twice over: a frame created while edit mode is already on has
    -- to appear at once rather than wait for the next toggle, AND this callback is the
    -- single place presence is ever resolved — including the first time. Reading the state
    -- separately to seed it and then watching for changes is the duplication section 5b
    -- exists to remove, and the seed is the copy that goes stale.
    --
    -- A unit that always exists still subscribes and the callback simply always resolves
    -- to shown, which is cheaper than a branch that has to stay in step with cfg.always.
    SuuUI.Settings:Watch("_layout", "edit_mode", function()
        self:_syncPresence()
    end, self._themeId .. "_edit_mode", { immediate = true })

    -- WoW event frame for data updates
    self._events = CreateFrame("Frame")
    self._events:RegisterEvent("UNIT_HEALTH")
    self._events:RegisterEvent("UNIT_MAXHEALTH")
    self._events:RegisterEvent("UNIT_POWER_UPDATE")
    self._events:RegisterEvent("UNIT_MAXPOWER")
    self._events:RegisterEvent("UNIT_DISPLAYPOWER")
    self._events:RegisterEvent("UNIT_LEVEL")
    -- A unit's standing can change without its class changing: a neutral mob you attack
    -- turns hostile, and a reaction-coloured bar that ignored this would keep painting it
    -- yellow through the fight.
    self._events:RegisterEvent("UNIT_FACTION")
    -- Every aura change on the unit arrives as one event, with no indication of what moved,
    -- so the bands re-read rather than trying to patch a single icon.
    self._events:RegisterEvent("UNIT_AURA")
    -- Leaving combat is the moment a deferred click-surface resize becomes legal again.
    -- The frame itself needs nothing here: it was resized correctly all along.
    self._events:RegisterEvent("PLAYER_REGEN_ENABLED")
    self._events:RegisterEvent("PLAYER_ENTERING_WORLD")
    -- Player-only, and deliberately not registered for anything else: PLAYER_LEVEL_UP
    -- carries the PLAYER's new level as its first argument, so a target frame handling it
    -- would write the player's level into the target's row.
    if cfg.unit == "player" then
        self._events:RegisterEvent("PLAYER_LEVEL_UP")
    end
    -- The unit became a different unit. Everything on screen is now about someone else, so
    -- this is a full re-read rather than a change to any one value.
    if cfg.changeEvent then
        self._events:RegisterEvent(cfg.changeEvent)
    end
    self._events:SetScript("OnEvent", function(_, event, unit, ...)
        if event == "PLAYER_REGEN_ENABLED" then
            -- Only catches up a surface that was refused mid-fight; a no-op otherwise.
            if self._clickDeferred then self:_syncClickArea() end
            return
        end
        if event == "PLAYER_ENTERING_WORLD" then
            -- Every value is being established for the first time, not changing, so the
            -- bars adopt them outright instead of sweeping up from empty.
            self:_syncPresence()
            self:UpdateAll(true)
        elseif event == cfg.changeEvent then
            self:_syncPresence()
            -- _syncPresence only repaints when presence CHANGED, and swapping one target
            -- for another leaves it unchanged while every value on screen is now wrong.
            if self._present then self:UpdateAll(true) end
        elseif event == "PLAYER_LEVEL_UP" then
            -- Carries the new level as its first argument, ahead of UnitLevel updating.
            self:UpdateInfo(unit)
        elseif unit == cfg.unit then
            if event == "UNIT_HEALTH" or event == "UNIT_MAXHEALTH" then
                self:UpdateHealth()
            elseif event == "UNIT_LEVEL" then
                self:UpdateInfo()
            elseif event == "UNIT_FACTION" then
                self:_applyHealthColor()
            elseif event == "UNIT_AURA" then
                self:UpdateAuras()
            elseif event == "UNIT_DISPLAYPOWER" then
                -- The resource changed identity — rage to energy on a form swap — so the
                -- old fill and the new one measure different things. Sliding between them
                -- animates a quantity that does not exist.
                self:UpdatePower(true)
            elseif event == "UNIT_POWER_UPDATE" or event == "UNIT_MAXPOWER" then
                self:UpdatePower()
            end
        end
    end)

    -- Presence is already resolved: the edit_mode watcher above ran immediately and is the
    -- only place that decides it.
    self:UpdateAll(true)
    return self
end

--- Refreshes every displayed value.
-- @param immediate bool  Skip bar transitions — for the first paint and for a change
--   that redefines what the bar means rather than moving it.
function UnitFrame:UpdateAll(immediate)
    self:UpdateInfo()
    self:_applyHealthColor()
    self:UpdateHealth(immediate)
    self:UpdatePower(immediate)
    -- The unit's auras are part of "everything displayed": a target swap replaces the whole
    -- set, and nothing else re-reads them until the next UNIT_AURA — which may be a long
    -- way off for a unit standing still.
    self:UpdateAuras()
end

--- The text the level slot should carry, or nil to hide it.
--
-- Three answers, not two. The client reports -1 for a unit whose level it will not tell
-- you — a mob far enough above the player to show a skull — and that is a sentinel, not a
-- number: printing it gives the player "-1" where the rest of their UI says "??".
-- @param level number
-- @return string|nil
function UnitFrame:_levelDisplay(level)
    if not SuuUI.Settings:Get(self._cfg.pluginId, self._cfg.prefix .. "show_level") then
        return nil
    end
    if level == LEVEL_UNKNOWN then return LEVEL_UNKNOWN_TEXT end
    local hideAtMax = SuuUI.Settings:Get(self._cfg.pluginId,
                                         self._cfg.prefix .. "hide_level_at_max")
    local cap = maxPlayerLevel()
    if hideAtMax and cap ~= nil and level >= cap then return nil end
    return tostring(level)
end

--- Refreshes name and level. Visibility respects <unit>_show_name / <unit>_show_level,
--- and — while the level is shown — <unit>_hide_level_at_max: at the cap the number
--- carries no information, but whether that is worth hiding is the player's call.
-- @param level number|nil  Overrides UnitLevel, for PLAYER_LEVEL_UP's payload
function UnitFrame:UpdateInfo(level)
    local cfg = self._cfg
    local showName = SuuUI.Settings:Get(cfg.pluginId, cfg.prefix .. "show_name")
    -- The display name stands in while the unit is absent, so an edit-mode frame says what
    -- it is instead of being an unlabelled pair of empty bars.
    local name = (self:UnitPresent() and UnitName(cfg.unit)) or nil
    if not name then name = self._present and cfg.displayName or "" end
    self._nameText:SetText(name)
    if showName then
        self._nameText:Show()
    else
        self._nameText:Hide()
    end

    local text = nil
    if self:UnitPresent() then
        text = self:_levelDisplay(level or UnitLevel(cfg.unit) or 0)
    end
    if text then
        self._levelText:SetText(text)
        self._levelText:Show()
    else
        self._levelText:SetText("")
        self._levelText:Hide()
    end

    -- Both texts hug their content, so the row has to re-measure after a text change.
    self._infoRow:Layout()

    -- An empty row is removed from the layout, not merely emptied: flow layout skips
    -- hidden children *and* the gap that would follow them, but a visible zero-height
    -- child still gets its gap — which would leave a dead band above the bars.
    if self._nameText:IsShown() or self._levelText:IsShown() then
        if not self._infoRow:IsShown() then self._infoRow:Show() end
    elseif self._infoRow:IsShown() then
        self._infoRow:Hide()
    end
end

-- What a bar reads while its unit is absent: full, so an edit-mode frame shows the shape
-- the player is positioning rather than two empty tracks. A max of 1 and a value of 1
-- rather than the unit's real numbers, because there are none to read.
local ABSENT_VALUE, ABSENT_MAX = 1, 1

--- Refreshes the health bar.
-- @param immediate bool  Skip the fill transition
function UnitFrame:UpdateHealth(immediate)
    local opts = immediate and IMMEDIATE or nil
    local cur, mx = ABSENT_VALUE, ABSENT_MAX
    if self:UnitPresent() then
        cur = UnitHealth(self._cfg.unit) or 0
        mx  = UnitHealthMax(self._cfg.unit) or 1
    end
    -- A dead or not-yet-loaded unit can report a max of 0, and every readout divides by it.
    if mx <= 0 then mx = 1 end
    self._healthBar:SetMax(mx, opts)
    self._healthBar:SetValue(cur, opts)
    self:UpdateReadouts("health", cur, mx)
end

--- Caches the formatter each readout slot is configured for, for one bar.
--
-- Derived, never copied: the watcher re-resolves it — including on a profile switch, which
-- the watcher also delivers — so it cannot go stale. It exists so a game event does not
-- read three settings, since UNIT_HEALTH and UNIT_POWER_UPDATE arrive several times a
-- second under combat.
-- @param bar string  "health" | "power"
function UnitFrame:_syncTextModes(bar)
    local slots = self._fmt[bar]
    for _, slot in ipairs(TEXT_SLOTS) do
        slots[slot] = BAR_TEXT[SuuUI.Settings:Get(self._cfg.pluginId,
                                                  textKey(self._cfg.prefix, bar, slot))]
    end
end

--- Writes one bar's three readouts.
--
-- A slot set to "none" resolves to no formatter, and the nil clears it — so switching a
-- readout off removes it rather than freezing it at the last value it happened to show.
-- @param bar string     "health" | "power"
-- @param cur number|nil Current value; read from the unit when omitted
-- @param mx number|nil  Max value; read from the unit when omitted
function UnitFrame:UpdateReadouts(bar, cur, mx)
    local def = READOUT_BARS_BY_ID[bar]
    local widget = self[def.field]
    if not widget then return end
    if not (cur and mx) then
        local c, m = def.value(self._cfg.unit)
        cur, mx = cur or c, mx or m
    end
    local slots = self._fmt[bar]
    -- An absent unit has no numbers, so a readout showing any would be inventing them.
    local blank = not self:UnitPresent()
    for _, slot in ipairs(TEXT_SLOTS) do
        local fmt = slots[slot]
        widget:SetText(slot, (fmt and not blank) and fmt(cur, mx) or nil)
    end
end

--- Refreshes the resource bar.
-- @param immediate bool  Skip the fill transition
function UnitFrame:UpdatePower(immediate)
    local opts = immediate and IMMEDIATE or nil
    local cur, mx = ABSENT_VALUE, ABSENT_MAX
    local powerType = 0
    if self:UnitPresent() then
        powerType = UnitPowerType(self._cfg.unit) or 0
        cur = UnitPower(self._cfg.unit) or 0
        mx  = UnitPowerMax(self._cfg.unit) or 1
    end
    -- A mob with no mana reports a max of 0, and every readout divides by it.
    if mx <= 0 then mx = 1 end
    self._resourceBar:SetFillColor(SuuUI.Game:PowerColor(powerType))
    self._resourceBar:SetMax(mx, opts)
    self._resourceBar:SetValue(cur, opts)
    self:UpdateReadouts("power", cur, mx)
end

function UnitFrame:GetFrame()
    return self._wrapper
end

function UnitFrame:GetContainer()
    return self._root
end

function UnitFrame:Destroy()
    SuuUI.Events:Off("SUUUI_THEME_CHANGED", self._themeId)
    -- Every watcher this frame registered shares the id as its owner prefix, so one call
    -- retires the lot. Enumerating the key lists instead means a new group of watchers can
    -- be added without its teardown, and a leaked watcher fires into a destroyed handle on
    -- every write and every profile switch.
    SuuUI.Settings:UnwatchPrefix(self._themeId)
    self._events:UnregisterAllEvents()
    self._events:Hide()
    self._nameText:Destroy()
    self._levelText:Destroy()
    self._healthBar:Destroy()
    -- Goes through the placement teardown, not a bare Destroy: a detached bar also holds a
    -- MoveableFrame registration and a root element, and leaking either leaves a draggable
    -- ghost on screen after the plugin is disabled.
    self:_teardownResourceBar()
    self._clickArea:Destroy()
    -- Each band retires its own shared-ticker registration and its icons. Left alive, a
    -- band would keep ticking against a destroyed frame after the plugin was disabled.
    for i = 1, #AuraBand.KINDS do
        self._bands[AuraBand.KINDS[i].id]:Destroy()
    end
    self._bands = nil
    self._infoRow:Destroy()
    self._bars:Destroy()
    self._slotAbove:Destroy()
    self._slotBelow:Destroy()
    self._clickBox:Destroy()
    self._root:Destroy()
    self._wrapper:Hide()
    self._wrapper = nil
end

---------------------------------------------------------------------------
-- Shared with the plugin file
--
-- The schema builder lives beside the widget deliberately: the readout keys, their option
-- lists and their defaults are the widget's own vocabulary, and a schema written in the
-- plugin file would be a second declaration of them.
---------------------------------------------------------------------------

--- Builds the settings schema for one unit's tab.
--
-- Every key is derived from the prefix, so a new unit is one entry in the plugin's UNITS
-- list and nothing else. The defaults are arguments rather than constants here because a
-- target frame is not the same size as the player's, while the RANGE of each slider is a
-- property of the control and stays here.
-- @param prefix string   Unit key prefix, e.g. "target_"
-- @param opts table      { label, width, healthHeight, powerHeight, healthCenter,
--                          attachLabel, auraSize }
-- @return table  Schema array for the tab
function UnitFrame.Schema(prefix, opts)
    local schema = {
        { key = "", label = "General", type = "section" },
        { key = prefix .. "enabled",    label = "Enable Frame", type = "toggle", default = true },
        { key = prefix .. "show_name",  label = "Show Name",    type = "toggle", default = true },
        { key = prefix .. "show_level", label = "Show Level",   type = "toggle", default = true },
        -- Only a decision while the level is shown at all, so the control is greyed out
        -- when it is not.
        { key = prefix .. "hide_level_at_max", label = "Hide at Max Level",
          type = "toggle", default = true, enabledIf = prefix .. "show_level" },
        -- Last in the section: the toggles read as one block, and the slider is the only
        -- control here that is not one. Frame-wide, not bar-specific — the bars and the
        -- name row all take their width from it, so it does not belong under a single bar.
        { key = prefix .. "width",      label = "Frame Width",  type = "slider",
          min = 120, max = 420, step = 2, default = opts.width },

        { key = "", label = "Health Bar", type = "section" },
        -- One readout per position, each free to show any format. Three independent
        -- dropdowns rather than one "show health text" toggle plus a format: the positions
        -- are not alternatives, and a player who wants the number left and the percentage
        -- right needs both at once.
        --
        -- Dropdowns as a block with the slider last, matching the General section:
        -- controls of one kind read as one group.
        { key = textKey(prefix, "health", "left"), label = "Left Text", type = "dropdown",
          default = "none", options = textOptions() },
        -- The one default that shows something. A bar with no readout at all would ship
        -- the feature invisible, and the centre is where a single readout belongs; the
        -- flanks stay off so the default stays quiet.
        { key = textKey(prefix, "health", "center"), label = "Center Text", type = "dropdown",
          default = opts.healthCenter, options = textOptions() },
        { key = textKey(prefix, "health", "right"), label = "Right Text", type = "dropdown",
          default = "none", options = textOptions() },
        -- One step for all three readouts. A token key rather than a pixel size, so it
        -- still follows a theme font edit.
        { key = textSizeKey(prefix, "health"), label = "Text Size", type = "dropdown",
          default = BAR_TEXT_SIZE, options = textSizeOptions() },
        -- Ranges are the control's own, so both units share them: what differs between a
        -- player frame and a target frame is the DEFAULT, which arrives in opts. The ceiling
        -- is generous deliberately — a health bar is the one bar people build a whole layout
        -- around, and 60 was low enough that the slider ran out before the taste did.
        { key = prefix .. "health_height", label = "Height", type = "slider",
          min = 8, max = 150, step = 1, default = opts.healthHeight },

        { key = "", label = "Resource Bar", type = "section" },
        -- The same four controls as the health bar, from the same helpers: the two bars are
        -- one question asked of two numbers, and a player who learns the health readouts
        -- has already learnt these.
        --
        -- Every position defaults to None here. The resource bar is the shorter of the two
        -- and the one a player is least often reading a number off, so it stays clean
        -- unless asked otherwise.
        { key = textKey(prefix, "power", "left"), label = "Left Text", type = "dropdown",
          default = "none", options = textOptions() },
        { key = textKey(prefix, "power", "center"), label = "Center Text", type = "dropdown",
          default = "none", options = textOptions() },
        { key = textKey(prefix, "power", "right"), label = "Right Text", type = "dropdown",
          default = "none", options = textOptions() },
        { key = textSizeKey(prefix, "power"), label = "Text Size", type = "dropdown",
          default = BAR_TEXT_SIZE, options = textSizeOptions() },
        -- Where the bar lives, in the same vocabulary the cast bar uses — "attached" means
        -- part of this frame, under the health bar. A player detaching their resource is not
        -- asking for a different bar, only for somewhere else to put it, so everything above
        -- keeps applying in either mode.
        --
        -- Placement comes before the two size sliders so Width and Height end up adjacent:
        -- they are one decision about the bar's shape, and the control that decides whether
        -- Width is even live belongs above the pair rather than between them.
        { key = prefix .. "power_anchor", label = "Attach To", type = "dropdown",
          default = "attached", options = {
            { value = "attached", label = opts.attachLabel },
            { value = "detached", label = "Detached" },
          } },
        -- An inline bar takes its width from the frame it is part of, so the slider is
        -- greyed out rather than silently ignored. Defaulted to the frame's own width so
        -- detaching does not resize it.
        { key = prefix .. "power_width", label = "Width", type = "slider",
          min = 80, max = 500, step = 2, default = opts.width,
          enabledIf = { key = prefix .. "power_anchor", equals = "detached" } },
        { key = prefix .. "power_height",  label = "Height", type = "slider",
          min = 4, max = 40, step = 1, default = opts.powerHeight },
    }

    -- One section per aura band, derived from the same list the widget builds its bands
    -- from: a third band would be one entry in AuraBand.KINDS and no schema edit at all.
    --
    -- Two controls, because there are only two decisions. How many rows a band takes is not
    -- one of them -- it follows from the icon size and the frame's width, and the band wraps
    -- to as many rows as the auras need.
    for _, kind in ipairs(AuraBand.KINDS) do
        local posKey = AuraBand.PositionKey(prefix, kind.id)
        schema[#schema + 1] = { key = "", label = kind.label, type = "section" }
        schema[#schema + 1] = {
            key = posKey, label = "Position", type = "dropdown",
            -- Buffs above and debuffs below by default: the arrangement most players
            -- already read, and it keeps each side to one band until they ask otherwise.
            default = kind.position, options = AuraBand.PositionOptions(),
        }
        schema[#schema + 1] = {
            key = AuraBand.SizeKey(prefix, kind.id), label = "Icon Size", type = "slider",
            min = 8, max = 48, step = 1, default = opts.auraSize,
            -- Dead while the band is not on screen, rather than silently ignored.
            enabledIf = { key = posKey, notEquals = "hidden" },
        }
    end

    return schema
end

SuuUI._UnitFrames = SuuUI._UnitFrames or {}
SuuUI._UnitFrames.UnitFrame = UnitFrame
