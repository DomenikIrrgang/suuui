-- SuuUI's own action bars.
--
-- PHASE 4a: bar 1 only, and NOTHING of Blizzard's is hidden. That split is deliberate. Phase
-- 4 as planned bundled "SuuUI's bar works" with "Blizzard's bottom cluster disappears", and
-- those have very different blast radii: if suppression lands and the secure button path does
-- not, the player is mid-session with no action bars at all. So this phase renders a working
-- bar ALONGSIDE the client's, which is additive and verifiable, and suppression follows once
-- the buttons are proven in game.
--
-- Bars 2..5, the B3 dock and the attach points are Phase 5. The slot blocks they own were
-- measured in game -- see the Round 3 table in .kiro/specs/bottom-ui-replacement.md.
local ipairs = ipairs

local PLUGIN_ID = "action_bars"
local OWNER     = "action_bars"

-- Bar 1 is the PAGED main bar. Slots 1..12 at page 1, and pages 2..6 are 13..24, 25..36,
-- 37..48, 49..60, 61..72 -- which means pages 3..6 are exactly the blocks the four multibars
-- own. Measured, not assumed: ActionButton1.action reported 1 in game.
--
-- Nothing here re-points a slot. The secure state driver does that, inside the secure
-- environment, in Phase 5; every button reads its slot back off its own attribute.
local FIRST_SLOT   = 1
local MAX_BUTTONS  = 12
local DISPLAY_NAME = "Action Bar 1"

-- Bottom centre, above where Blizzard's own bar sits, so the two do not overlap while both
-- are on screen this phase. Phase 4b moves it down once the client's is gone.
local DEFAULT_POSITION = { point = "BOTTOM", relPoint = "BOTTOM", x = 0, y = 120 }

local function slotsFor(count)
    local out = {}
    for i = 1, count do out[i] = FIRST_SLOT + i - 1 end
    return out
end

-- The client's own binding command for main-bar button i. Bar 1 is the only bar whose
-- commands are ACTIONBUTTON*; the multibars use MULTIACTIONBAR*BUTTON*, which is Phase 5.
local function bindingsFor(count)
    local out = {}
    for i = 1, count do out[i] = "ACTIONBUTTON" .. i end
    return out
end

local function get(key, fallback)
    local v = SuuUI.Settings:Get(PLUGIN_ID, key)
    if v == nil then return fallback end
    return v
end

---------------------------------------------------------------------------
-- Bar lifecycle
---------------------------------------------------------------------------

local function buildBar(p)
    if p._bar then return end

    local count = get("bar1_buttons", MAX_BUTTONS)
    local root  = SuuUI.UIRoot:GetRootContainer()

    local grid = SuuUI.Components.ActionBarGrid({
        slots         = slotsFor(count),
        bindings      = bindingsFor(count),
        rows          = get("bar1_rows", 1),
        buttonSize    = get("bar1_button_size", 32),
        spacing       = get("bar1_spacing", 0),
        showHotkeys   = get("bar1_show_hotkeys", true),
        showMacroText = get("bar1_show_macro_text", true),
        showCount     = get("bar1_show_count", true),
        -- Named so /framestack can identify them and a click-casting addon can bind them.
        namePrefix    = "SuuUIActionButton",
    }, root:GetFrame())
    p._bar = grid

    local frame = grid:GetFrame()
    -- Player-facing game UI, so the content rung -- stated through the library's layer system
    -- rather than left to inherit, so a settings window or modal is guaranteed to draw over it.
    SuuUI.UIRoot:SetLayer(frame, "normal")

    -- No coreInset: a bar is its buttons and nothing else, so its bounding box already
    -- describes the thing the player positioned. A unit frame needs one because it grows a
    -- cast bar and aura rows around its core.
    SuuUI.MoveableFrame:Apply(frame, {
        pluginId    = PLUGIN_ID,
        key         = "bar1_position",
        displayName = DISPLAY_NAME,
        defaults    = DEFAULT_POSITION,
    })
end

local function destroyBar(p)
    local grid = p._bar
    if not grid then return end
    p._bar = nil
    SuuUI.MoveableFrame:Remove(grid:GetFrame())
    grid:Destroy()
end

-- Every setting that changes the bar's SHAPE, and therefore its geometry. Each of these lands
-- in ActionBarGrid, which defers the whole change when InCombatLockdown() is true and catches
-- up on PLAYER_REGEN_ENABLED -- so a player dragging a slider mid-fight sees it apply when the
-- fight ends rather than getting "Interface action failed because of an AddOn".
local SHAPE = {
    { key = "bar1_buttons", apply = function(grid, v)
        local n = v or MAX_BUTTONS
        grid:SetSlots(slotsFor(n), bindingsFor(n))
    end },
    { key = "bar1_rows",        apply = function(grid, v) grid:SetRows(v or 1) end },
    { key = "bar1_button_size", apply = function(grid, v) grid:SetButtonSize(v or 32) end },
    { key = "bar1_spacing",     apply = function(grid, v) grid:SetSpacing(v or 0) end },
}

-- Readout toggles. These touch no geometry at all -- a font string showing or hiding is not a
-- protected operation -- so they apply immediately, in combat included.
local READOUTS = {
    { key = "bar1_show_hotkeys",    apply = function(grid, v) grid:SetShowHotkeys(v ~= false) end },
    { key = "bar1_show_macro_text", apply = function(grid, v) grid:SetShowMacroText(v ~= false) end },
    { key = "bar1_show_count",      apply = function(grid, v) grid:SetShowCount(v ~= false) end },
}

local function watchSettings(p)
    for _, entry in ipairs(SHAPE) do
        SuuUI.Settings:Watch(PLUGIN_ID, entry.key, function(v)
            if p._bar then entry.apply(p._bar, v) end
        end, OWNER .. "." .. entry.key)
    end
    for _, entry in ipairs(READOUTS) do
        SuuUI.Settings:Watch(PLUGIN_ID, entry.key, function(v)
            if p._bar then entry.apply(p._bar, v) end
        end, OWNER .. "." .. entry.key)
    end
    SuuUI.Settings:Watch(PLUGIN_ID, "bar1_enabled", function(on)
        if on then buildBar(p) else destroyBar(p) end
    end, OWNER .. ".bar1_enabled", { immediate = true })
end

local function unwatchSettings()
    for _, entry in ipairs(SHAPE) do
        SuuUI.Settings:Unwatch(OWNER .. "." .. entry.key)
    end
    for _, entry in ipairs(READOUTS) do
        SuuUI.Settings:Unwatch(OWNER .. "." .. entry.key)
    end
    SuuUI.Settings:Unwatch(OWNER .. ".bar1_enabled")
end

---------------------------------------------------------------------------
-- Settings schema
---------------------------------------------------------------------------

local function schema()
    return {
        -- Before the first section, so it stays on the page itself: a player must not have to
        -- open a group to find the switch that turns the plugin off.
        { key = "enabled", label = "Enable Action Bars", type = "toggle", default = true },

        -- No control of its own; the drag and the properties panel write it.
        { key = "bar1_position", type = "position", default = DEFAULT_POSITION },

        { key = "", label = "Bar 1", type = "section" },
        -- Toggles as one block, sliders after: mixing them reads as a broken list.
        { key = "bar1_enabled", label = "Enable Bar", type = "toggle", default = true },
        { key = "bar1_show_hotkeys", label = "Show Hotkeys", type = "toggle", default = true,
          enabledIf = "bar1_enabled" },
        { key = "bar1_show_macro_text", label = "Show Macro Names", type = "toggle",
          default = true, enabledIf = "bar1_enabled" },
        { key = "bar1_show_count", label = "Show Counts", type = "toggle", default = true,
          enabledIf = "bar1_enabled" },

        { key = "bar1_buttons", label = "Buttons", type = "slider",
          min = 1, max = MAX_BUTTONS, step = 1, default = MAX_BUTTONS,
          enabledIf = "bar1_enabled" },
        { key = "bar1_rows", label = "Rows", type = "slider",
          min = 1, max = 4, step = 1, default = 1, enabledIf = "bar1_enabled" },
        -- Width and height are one shape decision, so the two dimension controls sit together
        -- rather than being split by something else.
        { key = "bar1_button_size", label = "Button Size", type = "slider",
          min = 20, max = 64, step = 1, default = 32, enabledIf = "bar1_enabled" },
        -- 0 is the seamless look, and the only spacing that draws dividers between cells.
        { key = "bar1_spacing", label = "Spacing", type = "slider",
          min = 0, max = 12, step = 1, default = 0, enabledIf = "bar1_enabled" },
    }
end

---------------------------------------------------------------------------
-- Plugin
---------------------------------------------------------------------------

SuuUI:CreatePlugin({
    id      = PLUGIN_ID,
    name    = "Action Bars",
    version = "0.1",

    onInit = function(p)
        SuuUI.Settings:Register(PLUGIN_ID, schema())

        -- No `immediate` here on purpose. Plugins:autoEnable already applies the stored value
        -- during the login pass, and an immediate callback would run onEnable from inside the
        -- init pass -- before other plugins' onInit had run, which is the ordering the two
        -- phases exist to guarantee.
        SuuUI.Settings:Watch(PLUGIN_ID, "enabled", function(on)
            if on then p:Enable() else p:Disable() end
        end, OWNER .. ".enabled")
    end,

    onEnable = function(p)
        -- The bar1_enabled watcher is immediate, so it builds the bar on the way in.
        watchSettings(p)
    end,

    onDisable = function(p)
        unwatchSettings()
        destroyBar(p)
    end,
})

SuuUI._ActionBars = SuuUI._ActionBars or {}
SuuUI._ActionBars.slotsFor = slotsFor
SuuUI._ActionBars.bindingsFor = bindingsFor
SuuUI._ActionBars.DEFAULT_POSITION = DEFAULT_POSITION
