-- UnitFrames plugin: replaces Blizzard's unit frames with a modern, minimal design.
-- This file implements the player frame; other units will follow.
local format, floor = string.format, math.floor
local ipairs, type = ipairs, type
local C = SuuUI.Components
local S = SuuUI.UISignals
local T = SuuUI.Theme

---------------------------------------------------------------------------
-- Bar colours
---------------------------------------------------------------------------
-- Power colours are facts about the client, shared with anything else that paints one, so
-- they come from SuuUI.Game rather than being restated here.
--
-- Health is the same shape one layer up. WHICH colour a class gets is also a fact in
-- SuuUI.Game, but whether health is class-coloured at all is a look decision and lives in
-- the theme as colorUseClassColors. Theme:GetUnitColor resolves the pair, so this plugin
-- names the fallback token and nothing else — no class table, no flag check, and no second
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
local PLUGIN_ID = "unit_frames"
local INFO_FONT = "lg"  -- font size token suffix, shared by name and level

-- Settings keys for the player frame's dimensions, in one place so the watchers and the
-- metrics read the same list.
local SIZE_KEYS = { "player_width", "player_health_height", "player_power_height" }

-- Settings keys that control visibility of sub-widgets. These get their own watchers
-- rather than triggering a full relayout, because toggling a text widget doesn't
-- change bar geometry.
local VIS_KEYS = { "player_show_name", "player_show_level", "player_hide_level_at_max" }

---------------------------------------------------------------------------
-- Health readouts
--
-- Three independent slots overlaid inside the health bar, each free to show any of the
-- formats — so a player who wants the raw number on the left and the percentage on the
-- right gets that without either position being a special case.
--
-- The bar takes plain strings, so what a number MEANS is decided here. These are the only
-- formats, and the setting stores which one a slot uses rather than a format string: a
-- stored pattern would be a value nothing validates and the dropdown could not describe.
---------------------------------------------------------------------------
local HEALTH_TEXT_SLOTS = { "left", "center", "right" }

local HEALTH_TEXT = {
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

-- Fresh each call rather than one shared constant: the table is handed to three schema
-- entries and on to three Dropdown controls, and a shared options list is one aliased
-- table away from three controls editing each other's state.
local function healthTextOptions()
    return {
        { value = "none",        label = "None" },
        { value = "current_max", label = "Current / Max" },
        { value = "current",     label = "Current" },
        { value = "percent",     label = "Percent" },
    }
end

--- The settings key holding one slot's readout mode.
-- @param slot string  "left" | "center" | "right"
-- @return string
local function healthTextKey(slot)
    return "player_health_text_" .. slot
end

-- The font step the readouts render at, as a player-editable setting.
--
-- One setting for the whole bar rather than one per position: three readouts on one bar at
-- three different sizes reads as a rendering fault, not as a choice.
--
-- It stores a size KEY, so the pixel size still comes from the theme and a readout set to
-- Large follows a user's edit of `fontSizeLg`. A pixel value here would be this plugin
-- holding a font size of its own, which is the duplication the token scale exists to
-- prevent — and it would stop tracking the rest of the UI the moment the theme was scaled.
local HEALTH_TEXT_SIZE_KEY = "player_health_text_size"

-- The step a bar this tall wants, and the schema default. Declared once here so the
-- default and the option list cannot drift apart.
local BAR_TEXT_SIZE = "md"

local function healthTextSizeOptions()
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

local function metrics()
    local get = function(key) return SuuUI.Settings:Get(PLUGIN_ID, key) end
    return {
        -- widget dimensions: plugin settings
        width    = get("player_width"),
        health   = get("player_health_height"),
        resource = get("player_power_height"),
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
-- Player frame widget
---------------------------------------------------------------------------
local PlayerFrame = {}

--- The height the name row needs at the current font tokens. The row hugs its measured
--- text; before it has any text to measure, fall back to the font token so the frame is
--- never built collapsed. A hidden row contributes nothing: flow layout skips it, gap
--- included, so reporting 0 here is what keeps the height and the geometry in agreement.
-- @return number
function PlayerFrame:_infoHeight()
    if not self._infoRow:IsShown() then return 0 end
    local measured = self._infoRow:GetHeight() or 0
    if measured > 0 then return SuuUI.Pixel.Ceil(measured) end
    local m = metrics()
    return SuuUI.Pixel.Ceil(m.fontSize + m.barGap)
end

--- The bar group's height: both bar tokens plus the gap between them.
-- @return number
function PlayerFrame:_barsHeight()
    local m = metrics()
    return m.health + m.barGap + m.resource
end

--- The height one attach slot contributes. An empty or hidden slot contributes nothing —
--- flow layout skips it along with its gap, so reporting anything else would open a dead
--- band in the frame.
-- @param slot table  Container handle
-- @return number
function PlayerFrame:_slotHeight(slot)
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

--- The frame's intrinsic size: width from the plugin setting, height from whatever bands
--- are currently present — an attach slot, the name row, the bars, another attach slot.
--- Sizing flows one way, content setting the frame's height and never the reverse, so
--- there is no layout cycle to resolve even once a foreign widget has attached.
-- @return number, number  width, height
function PlayerFrame:GetPreferredSize()
    local m = metrics()
    local total, shown = 0, 0
    total, shown = addBand(total, shown, self:_slotHeight(self._slotAbove), m.infoGap)
    total, shown = addBand(total, shown, self:_infoHeight(),                m.infoGap)
    total, shown = addBand(total, shown, self:_barsHeight(),                m.infoGap)
    total, shown = addBand(total, shown, self:_slotHeight(self._slotBelow), m.infoGap)
    return m.width, total
end

--- How far the frame extends past its own content, top and bottom, because of attach
--- bands. This is what keeps the player's chosen position meaning "where my bars are"
--- rather than "where the bounding box is": a cast bar attaching below adds to the bottom
--- inset, and MoveableFrame shifts the frame down by exactly that much so the bars do not
--- move. Each band carries the row gap with it, matching GetPreferredSize.
-- @return number, number  above inset, below inset
function PlayerFrame:GetCoreInset()
    local gap = metrics().infoGap
    local above = self:_slotHeight(self._slotAbove)
    local below = self:_slotHeight(self._slotBelow)
    if above > 0 then above = above + gap end
    if below > 0 then below = below + gap end
    return above, below
end

--- Re-states placement when the attach bands changed, so the frame's own content stays
--- put. Gated on the inset actually moving: the two slots swapping which one holds the
--- band leaves the frame the same total height, so a size comparison would miss it, while
--- re-anchoring on every layout pass would fight a drag in progress.
function PlayerFrame:_syncAnchor()
    local above, below = self:GetCoreInset()
    if self._insetAbove == above and self._insetBelow == below then return end
    self._insetAbove, self._insetBelow = above, below
    SuuUI.MoveableFrame:RefreshAnchor(self._wrapper)
end

--- Resizes the wrapper to the current preferred size. The bar group fills what the name
--- row leaves, so the bars keep their token heights and only the row absorbs a font change.
function PlayerFrame:_syncSize()
    local w, h = self:GetPreferredSize()
    if math.abs((self._wrapper:GetWidth() or 0) - w) > 0.5
       or math.abs((self._wrapper:GetHeight() or 0) - h) > 0.5 then
        self._wrapper:SetSize(w, h)
    end
    self:_syncAnchor()
end

--- Re-resolves the health bar's fill colour.
--
-- Called from Relayout, so a theme switch or a live edit of either the Health primitive or
-- the Use Class Colours toggle repaints without a reload; and from UpdateAll, because the
-- player's class is not knowable until PLAYER_ENTERING_WORLD and the first paint would
-- otherwise be stuck on the fallback for the rest of the session.
function PlayerFrame:_applyHealthColor()
    self._healthBar:SetFillColor(T:GetUnitColor(HEALTH_COLOR, "player"))
end

--- Re-reads every derived metric and re-lays the frame. Bound to both
--- SUUUI_THEME_CHANGED and the size settings, so moving a slider or editing a spacing
--- token takes effect immediately instead of waiting for a reload.
function PlayerFrame:Relayout()
    local m = metrics()
    self._root:SetGap(m.infoGap)
    self._infoRow:SetGap(m.infoGap)
    self._bars:SetGap(m.barGap)
    self._slotAbove:SetGap(m.barGap)
    self._slotBelow:SetGap(m.barGap)
    self._bars:SetChildProps(self._healthBar,   { width = "fill", height = m.health })
    self._bars:SetChildProps(self._resourceBar, { width = "fill", height = m.resource })
    self._root:SetChildProps(self._bars, { width = "fill", height = self:_barsHeight() })
    self:_applyHealthColor()
    self:_syncSize()
    self._root:Layout()
end

--- Theme hook. Same work as a settings change, so it shares one path.
function PlayerFrame:ApplyTheme()
    self:Relayout()
end

--- Re-applies the name/level visibility settings and re-sizes the frame.
--- UpdateInfo already resolves both settings, so this adds only the size pass: hiding
--- both texts collapses the info row, which changes the frame's height.
function PlayerFrame:SyncVisibility()
    self:UpdateInfo()
    self:_syncSize()
end

-- One attach slot: an empty vertical band another plugin can place a widget into. Hidden
-- while empty, because flow layout skips a hidden child together with its gap — a visible
-- zero-height slot would still claim a gap and leave a dead band in the frame.
function PlayerFrame:_createSlot()
    local slot = SuuUI.Layout:CreateContainer({
        parent = self._wrapper,
        layout = "flow",
        dir    = "vertical",
        gap    = metrics().barGap,
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
function PlayerFrame:AttachChild(child, opts)
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
function PlayerFrame:DetachChild(child)
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

function PlayerFrame:Create(parent)
    local self = setmetatable({}, { __index = PlayerFrame })
    local m = metrics()
    -- Resolved by the readout watchers below, before anything reads them.
    self._healthFmt = {}

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
    -- point this plugin publishes in onEnable. Created before the frame's own content so
    -- the "above" slot really is above it: flow layout follows insertion order.
    self._slotAbove = self:_createSlot()
    self._slotBelow = self:_createSlot()

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
        fillColor = T:GetUnitColor(HEALTH_COLOR, "player"),
        bgColor   = BAR_TRACK,
        border    = false,
        -- Health moves in sparse, large steps, so a fixed-duration ease reads as the bar
        -- absorbing a hit.
        transition = "smooth",
        -- No textSize here: the readout-size watcher below runs immediately and is the
        -- single place that states it. Naming the step twice would leave the construction
        -- copy stale the moment the player changed the setting.
    }, self._bars:GetFrame())

    self._resourceBar = C.StatusBar({
        fillColor = SuuUI.Game:PowerColor(0),  -- default to mana
        bgColor   = BAR_TRACK,
        border    = false,
        -- Energy and rage tick faster than a fixed-duration ease completes, and each
        -- event would restart one — so the bar would trail its true value continuously
        -- and never settle. Constant speed converges instead.
        transition = "rate",
    }, self._bars:GetFrame())

    -- Bar heights are stated, not filled: the frame's height is derived FROM them, so a
    -- bar that sized itself from the frame would close the loop.
    --
    -- Membership only, no height: the SIZE_KEYS watcher below runs immediately and is the
    -- single place that states these heights. Repeating m.health here as well would be the
    -- duplication section 5b exists to remove -- two sites to keep in step, and the one
    -- that only runs at construction goes stale the moment a slider moves.
    self._bars:Add(self._healthBar,   { width = "fill" })
    self._bars:Add(self._resourceBar, { width = "fill" })

    -- No height on the info row: it hugs its own text, which is what makes the frame
    -- follow the font tokens. The wrapper then tracks the row through SIZE_CHANGED.
    self._root:Add(self._slotAbove, { width = "fill" })
    self._root:Add(self._infoRow,   { width = "fill" })
    self._root:Add(self._bars,      { width = "fill" })
    self._root:Add(self._slotBelow, { width = "fill" })

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

    -- Spacing and font tokens are user-editable, so the frame re-derives on a theme change
    -- rather than holding the values it was built with.
    self._themeId = "unitframes_player_" .. tostring(self._wrapper)
    SuuUI.Events:On("SUUUI_THEME_CHANGED", function() self:ApplyTheme() end, self._themeId)

    -- The dimension sliders are watched with immediate = true: the watcher callback IS
    -- the first paint — no separate seeding call. It also survives a profile switch,
    -- which rewrites these values underneath us.
    for _, key in ipairs(SIZE_KEYS) do
        SuuUI.Settings:Watch(PLUGIN_ID, key, function()
            self:Relayout()
        end, self._themeId .. "_" .. key, { immediate = true })
    end

    -- Visibility settings: toggling name or level re-applies visibility and re-syncs size.
    -- NOT immediate: UpdateAll(true) below already calls UpdateInfo, and it does strictly
    -- more (seeds bar values with snap). Adding immediate would just repeat that work.
    for _, key in ipairs(VIS_KEYS) do
        SuuUI.Settings:Watch(PLUGIN_ID, key, function()
            self:SyncVisibility()
        end, self._themeId .. "_" .. key)
    end

    -- Readout modes. Immediate, because the watcher IS what resolves _healthFmt — reading
    -- the three settings separately to seed it and then watching for changes would be two
    -- places holding the same fact, and the seed is the one that goes stale.
    for _, slot in ipairs(HEALTH_TEXT_SLOTS) do
        SuuUI.Settings:Watch(PLUGIN_ID, healthTextKey(slot), function()
            self:_syncHealthTextModes()
            self:UpdateHealthText()
        end, self._themeId .. "_" .. healthTextKey(slot), { immediate = true })
    end

    -- Readout size: one step for every slot, applied to the bar rather than per readout.
    -- Immediate for the same reason as the modes — this is the first paint of the size, so
    -- the bar is never built at a step the setting does not name.
    SuuUI.Settings:Watch(PLUGIN_ID, HEALTH_TEXT_SIZE_KEY, function(val)
        self._healthBar:SetTextSize(val)
        -- The step decides the readouts' height, and the bar's own height does not follow
        -- it — so nothing else re-flows the frame after a size change.
        self:_syncSize()
    end, self._themeId .. "_" .. HEALTH_TEXT_SIZE_KEY, { immediate = true })

    -- WoW event frame for data updates
    self._events = CreateFrame("Frame")
    self._events:RegisterEvent("UNIT_HEALTH")
    self._events:RegisterEvent("UNIT_MAXHEALTH")
    self._events:RegisterEvent("UNIT_POWER_UPDATE")
    self._events:RegisterEvent("UNIT_MAXPOWER")
    self._events:RegisterEvent("UNIT_DISPLAYPOWER")
    self._events:RegisterEvent("UNIT_LEVEL")
    self._events:RegisterEvent("PLAYER_LEVEL_UP")
    self._events:RegisterEvent("PLAYER_ENTERING_WORLD")
    self._events:SetScript("OnEvent", function(_, event, unit, ...)
        if event == "PLAYER_ENTERING_WORLD" then
            -- Every value is being established for the first time, not changing, so the
            -- bars adopt them outright instead of sweeping up from empty.
            self:UpdateAll(true)
        elseif event == "PLAYER_LEVEL_UP" then
            -- Carries the new level as its first argument, ahead of UnitLevel updating.
            self:UpdateInfo(unit)
        elseif unit == "player" or event == "UNIT_DISPLAYPOWER" then
            if event == "UNIT_HEALTH" or event == "UNIT_MAXHEALTH" then
                self:UpdateHealth()
            elseif event == "UNIT_LEVEL" then
                self:UpdateInfo()
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

    self:UpdateAll(true)
    return self
end

--- Refreshes every displayed value.
-- @param immediate bool  Skip bar transitions — for the first paint and for a change
--   that redefines what the bar means rather than moving it.
function PlayerFrame:UpdateAll(immediate)
    self:UpdateInfo()
    self:_applyHealthColor()
    self:UpdateHealth(immediate)
    self:UpdatePower(immediate)
end

--- Refreshes name and level. Visibility respects player_show_name / player_show_level,
--- and — while the level is shown — player_hide_level_at_max: at the cap the number
--- carries no information, but whether that is worth hiding is the player's call.
-- @param level number|nil  Overrides UnitLevel, for PLAYER_LEVEL_UP's payload
function PlayerFrame:UpdateInfo(level)
    local showName = SuuUI.Settings:Get(PLUGIN_ID, "player_show_name")
    local name = UnitName("player") or ""
    self._nameText:SetText(name)
    if showName then
        self._nameText:Show()
    else
        self._nameText:Hide()
    end

    local showLevel = SuuUI.Settings:Get(PLUGIN_ID, "player_show_level")
    local hideAtMax = SuuUI.Settings:Get(PLUGIN_ID, "player_hide_level_at_max")
    level = level or UnitLevel("player") or 0
    local cap = maxPlayerLevel()
    local atMax = hideAtMax and cap ~= nil and level >= cap
    if not showLevel or atMax then
        self._levelText:SetText("")
        self._levelText:Hide()
    else
        self._levelText:SetText(tostring(level))
        self._levelText:Show()
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

--- Refreshes the health bar.
-- @param immediate bool  Skip the fill transition
function PlayerFrame:UpdateHealth(immediate)
    local opts = immediate and IMMEDIATE or nil
    local cur = UnitHealth("player") or 0
    local mx  = UnitHealthMax("player") or 1
    self._healthBar:SetMax(mx, opts)
    self._healthBar:SetValue(cur, opts)
    self:UpdateHealthText(cur, mx)
end

--- Caches the formatter each readout slot is configured for.
--
-- Derived, never copied: the watcher re-resolves it — including on a profile switch, which
-- the watcher also delivers — so it cannot go stale. It exists so a health event does not
-- read three settings, since UNIT_HEALTH arrives several times a second under combat.
function PlayerFrame:_syncHealthTextModes()
    for _, slot in ipairs(HEALTH_TEXT_SLOTS) do
        self._healthFmt[slot] = HEALTH_TEXT[SuuUI.Settings:Get(PLUGIN_ID, healthTextKey(slot))]
    end
end

--- Writes the three health readouts.
--
-- A slot set to "none" resolves to no formatter, and the nil clears it — so switching a
-- readout off removes it rather than freezing it at the last value it happened to show.
-- @param cur number|nil  Current health; read from the unit when omitted
-- @param mx number|nil   Max health; read from the unit when omitted
function PlayerFrame:UpdateHealthText(cur, mx)
    cur = cur or UnitHealth("player") or 0
    mx  = mx  or UnitHealthMax("player") or 1
    for _, slot in ipairs(HEALTH_TEXT_SLOTS) do
        local fmt = self._healthFmt[slot]
        self._healthBar:SetText(slot, fmt and fmt(cur, mx) or nil)
    end
end

--- Refreshes the resource bar.
-- @param immediate bool  Skip the fill transition
function PlayerFrame:UpdatePower(immediate)
    local opts = immediate and IMMEDIATE or nil
    local powerType = UnitPowerType("player") or 0
    local cur = UnitPower("player") or 0
    local mx  = UnitPowerMax("player") or 1
    local color = SuuUI.Game:PowerColor(powerType)
    self._resourceBar:SetFillColor(color)
    self._resourceBar:SetMax(mx, opts)
    self._resourceBar:SetValue(cur, opts)
end

function PlayerFrame:GetFrame()
    return self._wrapper
end

function PlayerFrame:GetContainer()
    return self._root
end

function PlayerFrame:Destroy()
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
    self._resourceBar:Destroy()
    self._infoRow:Destroy()
    self._bars:Destroy()
    self._slotAbove:Destroy()
    self._slotBelow:Destroy()
    self._root:Destroy()
    self._wrapper:Hide()
    self._wrapper = nil
end

---------------------------------------------------------------------------
-- Blizzard frames to hide/restore
---------------------------------------------------------------------------
local BLIZZARD_PLAYER_FRAMES = {
    "PlayerFrame",
}

-- Whether THIS plugin is currently suppressing a frame. The OnShow hook below is
-- permanent -- HookScript cannot be undone -- so it asks this table on every show rather
-- than assuming it should always hide. Without the flag, restoring the frame would be
-- impossible: Show() would fire the hook and the hook would hide it straight back.
local suppressed = {}

-- Blizzard frames are permanent globals, so this never holds more than one entry per
-- name. It exists so a disable/enable cycle does not stack a second hook on the frame.
local hooked = {}

-- Deliberately NOT UnregisterAllEvents(). Nothing in the API enumerates a frame's
-- registered events, so unregistering is a one-way door: onDisable could never hand the
-- frame back alive, which is what left Blizzard's player frame dead until a reload. The
-- hook is a complete suppression mechanism on its own -- a hidden frame can only become
-- visible through a show, and every show fires OnShow -- so the registrations stay where
-- Blizzard put them and the cost of suppressing is one Hide().
local function suppress(frame)
    suppressed[frame] = true
    if not hooked[frame] then
        hooked[frame] = true
        frame:HookScript("OnShow", function(self)
            if suppressed[self] then self:Hide() end
        end)
    end
    frame:Hide()
end

-- Never touches a frame this plugin did not hide: with the player frame switched off we
-- never suppressed anything, and showing it here would override whatever else hid it.
--
-- The flag is cleared BEFORE the Show, or the hook we cannot uninstall hides it again on
-- the way out.
local function restore(frame)
    if not suppressed[frame] then return end
    suppressed[frame] = nil
    frame:Show()
end

local function hideBlizzardPlayerFrame()
    for _, name in ipairs(BLIZZARD_PLAYER_FRAMES) do
        local frame = _G[name]
        if frame then suppress(frame) end
    end
end

local function restoreBlizzardPlayerFrame()
    for _, name in ipairs(BLIZZARD_PLAYER_FRAMES) do
        local frame = _G[name]
        if frame then restore(frame) end
    end
end

---------------------------------------------------------------------------
-- Plugin registration
---------------------------------------------------------------------------
local plugin = SuuUI:CreatePlugin({
    id      = "unit_frames",
    name    = "Unit Frames",
    version = "0.1",

    onInit = function(p)
        -- The frame's own dimensions are settings, not theme tokens: they describe one
        -- plugin's widget rather than the design language, and a player wants them per
        -- profile.
        --
        -- Per-unit settings live inside that unit's tab and are declared THERE, once.
        -- Settings:Register indexes a tab's entries like top-level ones, so the default,
        -- the range and the label all sit in a single declaration — a key repeated at the
        -- top level as well would let the default and the slider range drift apart.
        SuuUI.Settings:Register("unit_frames", {
            { key = "enabled", label = "Enable Unit Frames", type = "toggle", default = true },

            -- Placement is written by MoveableFrame, not edited on the page.
            { key = "player_position", type = "position",
              default = { point = "BOTTOMLEFT", relPoint = "BOTTOMLEFT", x = 20, y = 60 } },

            -- One tab per unit frame. Only the player exists today; the rest of the units
            -- become further entries in this list.
            { key = "unit", type = "subtabs", tabs = {
                { id = "player", label = "Player", schema = {
                    { key = "", label = "General", type = "section" },
                    { key = "player_enabled",    label = "Enable Frame", type = "toggle", default = true },
                    { key = "player_show_name",  label = "Show Name",    type = "toggle", default = true },
                    { key = "player_show_level", label = "Show Level",   type = "toggle", default = true },
                    -- Only a decision while the level is shown at all, so the control is
                    -- greyed out when it is not. Default true keeps the previous behaviour.
                    { key = "player_hide_level_at_max", label = "Hide at Max Level",
                      type = "toggle", default = true, enabledIf = "player_show_level" },
                    -- Last in the section: the toggles read as one block, and the slider
                    -- is the only control here that is not one. Frame-wide, not
                    -- bar-specific — the bars and the name row all take their width from
                    -- it, so it does not belong under a single bar.
                    { key = "player_width",      label = "Frame Width",  type = "slider",
                      min = 120, max = 420, step = 2, default = 304 },

                    { key = "", label = "Health Bar", type = "section" },
                    -- One readout per position, each free to show any format. Three
                    -- independent dropdowns rather than one "show health text" toggle plus
                    -- a format: the positions are not alternatives, and a player who wants
                    -- the number left and the percentage right needs both at once.
                    --
                    -- Dropdowns as a block with the slider last, matching the General
                    -- section: controls of one kind read as one group.
                    { key = healthTextKey("left"), label = "Left Text", type = "dropdown",
                      default = "none", options = healthTextOptions() },
                    -- The one default that shows something. A bar with no readout at all
                    -- would ship the feature invisible, and the centre is where a single
                    -- readout belongs; the flanks stay off so the default stays quiet.
                    { key = healthTextKey("center"), label = "Center Text", type = "dropdown",
                      default = "current_max", options = healthTextOptions() },
                    { key = healthTextKey("right"), label = "Right Text", type = "dropdown",
                      default = "none", options = healthTextOptions() },
                    -- One step for all three readouts. A token key rather than a pixel
                    -- size, so it still follows a theme font edit.
                    { key = HEALTH_TEXT_SIZE_KEY, label = "Text Size", type = "dropdown",
                      default = BAR_TEXT_SIZE, options = healthTextSizeOptions() },
                    { key = "player_health_height", label = "Height", type = "slider",
                      min = 8, max = 60, step = 1, default = 39 },

                    { key = "", label = "Resource Bar", type = "section" },
                    { key = "player_power_height",  label = "Height", type = "slider",
                      min = 4, max = 40, step = 1, default = 22 },
                }},
            }},
        })

        -- Guard settings that require a reload
        SuuUI.ReloadGuard:Register("unit_frames", "enabled", {
            title   = "Reload Required",
            message = "Enabling or disabling Unit Frames requires a UI reload. Reload now?",
        })
        SuuUI.ReloadGuard:Register("unit_frames", "player_enabled", {
            title   = "Reload Required",
            message = "Enabling or disabling the Player Frame requires a UI reload. Reload now?",
        })
    end,

    onEnable = function(p)
        -- Hide Blizzard player frame
        if SuuUI.Settings:Get("unit_frames", "player_enabled") then
            hideBlizzardPlayerFrame()

            -- Create our player frame
            local root = SuuUI.UIRoot:GetRootContainer()
            p._playerFrame = PlayerFrame:Create(root:GetFrame())

            -- Size comes from the widget's own layout metrics — no magic numbers here.
            local frame = p._playerFrame:GetFrame()

            -- Player-facing game UI, so it belongs on the content rung — stated through the
            -- library's layer system rather than left to inherit, so a settings window or a
            -- modal is guaranteed to draw over it.
            SuuUI.UIRoot:SetLayer(frame, "normal")

            -- Make it moveable — position stored in plugin settings.
            --
            -- coreInset is what keeps the stored position describing THIS frame's content
            -- rather than its bounding box. The frame grows around whatever attaches to it,
            -- and growth happens on the edge the anchor does not pin — so without this a
            -- cast bar attaching below pushed the bars up by its own height, and detaching
            -- pushed them back down.
            local pfHandle = p._playerFrame
            SuuUI.MoveableFrame:Apply(frame, {
                pluginId    = "unit_frames",
                key         = "player_position",
                displayName = "Player",
                defaults    = { point = "BOTTOMLEFT", relPoint = "BOTTOMLEFT", x = 20, y = 60 },
                coreInset   = function() return pfHandle:GetCoreInset() end,
            })

            -- Offer the frame as an attach point. Another plugin can now place a widget
            -- inside it — a cast bar attaches here — without either plugin knowing the
            -- other exists: a consumer that loads first simply gets told when this
            -- appears. Placement stays ours, so the frame still owns its own geometry.
            local pf = p._playerFrame
            SuuUI.AttachPoints:Publish("unitframe.player", {
                frame  = frame,
                Attach = function(child, opts) return pf:AttachChild(child, opts) end,
                Detach = function(child) return pf:DetachChild(child) end,
            })
        end
    end,

    onDisable = function(p)
        -- Revoked before anything is torn down: consumers detach on the nil notification,
        -- so nothing foreign is still sitting in a slot when the containers go away.
        SuuUI.AttachPoints:Revoke("unitframe.player")

        -- Destroy our player frame (cleanup before reload or if called programmatically)
        if p._playerFrame then
            SuuUI.MoveableFrame:Remove(p._playerFrame:GetFrame())
            p._playerFrame:Destroy()
            p._playerFrame = nil
        end

        -- Hand Blizzard's frame back. A programmatic Disable has no reload behind it, so
        -- this is the only thing that undoes the suppression. Safe to call
        -- unconditionally -- restore skips any frame this plugin did not hide.
        restoreBlizzardPlayerFrame()
    end,
})
