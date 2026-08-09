-- UnitFrames plugin: replaces Blizzard's unit frames with a modern, minimal design.
-- This file implements the player frame; other units will follow.
local C = SuuUI.Components
local S = SuuUI.UISignals
local T = SuuUI.Theme

---------------------------------------------------------------------------
-- Power type colour map (standard WoW colours)
---------------------------------------------------------------------------
local POWER_COLORS = {
    [0] = {0.00, 0.44, 0.87, 1},  -- Mana (blue)
    [1] = {0.77, 0.12, 0.23, 1},  -- Rage (red)
    [2] = {1.00, 0.50, 0.25, 1},  -- Focus (orange)
    [3] = {1.00, 0.96, 0.41, 1},  -- Energy (yellow)
    [4] = {0.00, 0.44, 0.87, 1},  -- Combo Points (blue, fallback)
    [5] = {0.50, 0.50, 0.50, 1},  -- Runes (grey)
    [6] = {0.00, 0.82, 1.00, 1},  -- Runic Power (cyan)
}

-- Health bar colour: a modern green
local HEALTH_COLOR = {0.22, 0.78, 0.32, 1}

-- The empty part of a bar. Neutral black at a token opacity rather than a panel colour:
-- the frame has no backing plate, so this is the only surface behind the fill. It shares
-- the fill's box exactly (StatusBar insets nothing when there is no border), so a full bar
-- covers its track and an empty one occupies the same footprint.
local function barTrackColor()
    return {0, 0, 0, T:GetToken("opacityBarTrack")}
end

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

--- The frame's intrinsic size, entirely token-derived: width from the size token, height
--- from the name row plus the bar group. Sizing flows one way — content sets the frame's
--- height, never the reverse — so there is no layout cycle to resolve.
-- @return number, number  width, height
function PlayerFrame:GetPreferredSize()
    local m = metrics()
    local infoH = self:_infoHeight()
    local gapAboveBars = infoH > 0 and m.infoGap or 0
    return m.width, infoH + gapAboveBars + self:_barsHeight()
end

--- Resizes the wrapper to the current preferred size. The bar group fills what the name
--- row leaves, so the bars keep their token heights and only the row absorbs a font change.
function PlayerFrame:_syncSize()
    local w, h = self:GetPreferredSize()
    if math.abs((self._wrapper:GetWidth() or 0) - w) > 0.5
       or math.abs((self._wrapper:GetHeight() or 0) - h) > 0.5 then
        self._wrapper:SetSize(w, h)
    end
end

--- Re-reads every derived metric and re-lays the frame. Bound to both
--- SUUUI_THEME_CHANGED and the size settings, so moving a slider or editing a spacing
--- token takes effect immediately instead of waiting for a reload.
function PlayerFrame:Relayout()
    local m = metrics()
    self._root:SetGap(m.infoGap)
    self._infoRow:SetGap(m.infoGap)
    self._bars:SetGap(m.barGap)
    self._bars:SetChildProps(self._healthBar,   { width = "fill", height = m.health })
    self._bars:SetChildProps(self._resourceBar, { width = "fill", height = m.resource })
    self._root:SetChildProps(self._bars, { width = "fill", height = self:_barsHeight() })
    self._healthBar:SetBgColor(barTrackColor())
    self._resourceBar:SetBgColor(barTrackColor())
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

function PlayerFrame:Create(parent)
    local self = setmetatable({}, { __index = PlayerFrame })
    local m = metrics()

    -- Bare grouping frame: no styling and no backdrop, so nothing draws behind the bars.
    -- Sized up front because the containers below lay out against a real geometry; the
    -- height is provisional until the name row has measured itself.
    self._wrapper = CreateFrame("Frame", nil, parent)
    self._wrapper:SetSize(m.width, m.infoGap + m.health + m.barGap + m.resource)

    -- Root column: info row on top, bar group below.
    self._root = SuuUI.Layout:CreateContainer({
        host   = self._wrapper,
        layout = "flow",
        dir    = "vertical",
        gap    = m.infoGap,
    })

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
        fillColor = HEALTH_COLOR,
        bgColor   = barTrackColor(),
        border    = false,
        -- Health moves in sparse, large steps, so a fixed-duration ease reads as the bar
        -- absorbing a hit.
        transition = "smooth",
    }, self._bars:GetFrame())

    self._resourceBar = C.StatusBar({
        fillColor = POWER_COLORS[0],  -- default to mana
        bgColor   = barTrackColor(),
        border    = false,
        -- Energy and rage tick faster than a fixed-duration ease completes, and each
        -- event would restart one — so the bar would trail its true value continuously
        -- and never settle. Constant speed converges instead.
        transition = "rate",
    }, self._bars:GetFrame())

    -- Bar heights are stated, not filled: the frame's height is derived FROM them, so a
    -- bar that sized itself from the frame would close the loop.
    self._bars:Add(self._healthBar,   { width = "fill", height = m.health })
    self._bars:Add(self._resourceBar, { width = "fill", height = m.resource })

    -- No height on the info row: it hugs its own text, which is what makes the frame
    -- follow the font tokens. The wrapper then tracks the row through SIZE_CHANGED.
    self._root:Add(self._infoRow, { width = "fill" })
    self._root:Add(self._bars,    { width = "fill", height = self:_barsHeight() })

    S:Connect(self._infoRow, S.SIGNALS.SIZE_CHANGED, function()
        self:_syncSize()
    end)

    -- Spacing and font tokens are user-editable, so the frame re-derives on a theme change
    -- rather than holding the values it was built with.
    self._themeId = "unitframes_player_" .. tostring(self._wrapper)
    SuuUI.Events:On("SUUUI_THEME_CHANGED", function() self:ApplyTheme() end, self._themeId)

    -- The dimension sliders are watched the same way: a settings change re-lays the frame
    -- immediately and survives a profile switch, which rewrites these values underneath us.
    for _, key in ipairs(SIZE_KEYS) do
        SuuUI.Settings:Watch(PLUGIN_ID, key, function()
            self:Relayout()
        end, self._themeId .. "_" .. key)
    end

    -- Visibility settings: toggling name or level re-applies visibility and re-syncs size.
    for _, key in ipairs(VIS_KEYS) do
        SuuUI.Settings:Watch(PLUGIN_ID, key, function()
            self:SyncVisibility()
        end, self._themeId .. "_" .. key)
    end

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
    self:_syncSize()
    return self
end

--- Refreshes every displayed value.
-- @param immediate bool  Skip bar transitions — for the first paint and for a change
--   that redefines what the bar means rather than moving it.
function PlayerFrame:UpdateAll(immediate)
    self:UpdateInfo()
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
end

--- Refreshes the resource bar.
-- @param immediate bool  Skip the fill transition
function PlayerFrame:UpdatePower(immediate)
    local opts = immediate and IMMEDIATE or nil
    local powerType = UnitPowerType("player") or 0
    local cur = UnitPower("player") or 0
    local mx  = UnitPowerMax("player") or 1
    local color = POWER_COLORS[powerType] or POWER_COLORS[0]
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
    for _, key in ipairs(SIZE_KEYS) do
        SuuUI.Settings:Unwatch(self._themeId .. "_" .. key)
    end
    for _, key in ipairs(VIS_KEYS) do
        SuuUI.Settings:Unwatch(self._themeId .. "_" .. key)
    end
    self._events:UnregisterAllEvents()
    self._events:Hide()
    self._nameText:Destroy()
    self._levelText:Destroy()
    self._healthBar:Destroy()
    self._resourceBar:Destroy()
    self._infoRow:Destroy()
    self._bars:Destroy()
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

local function hideBlizzardPlayerFrame()
    for _, name in ipairs(BLIZZARD_PLAYER_FRAMES) do
        local frame = _G[name]
        if frame then
            frame:UnregisterAllEvents()
            frame:Hide()
        end
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

            -- Make it moveable — position stored in plugin settings
            SuuUI.MoveableFrame:Apply(frame, {
                pluginId    = "unit_frames",
                key         = "player_position",
                displayName = "Player",
                defaults    = { point = "BOTTOMLEFT", relPoint = "BOTTOMLEFT", x = 20, y = 60 },
            })
        end
    end,

    onDisable = function(p)
        -- Destroy our player frame (cleanup before reload or if called programmatically)
        if p._playerFrame then
            SuuUI.MoveableFrame:Remove(p._playerFrame:GetFrame())
            p._playerFrame:Destroy()
            p._playerFrame = nil
        end
        -- Blizzard frames are restored by the reload — no manual restore needed
    end,
})
