-- CastBars plugin: registration, settings, and the per-unit wiring.
--
-- The widget lives in CastBar.lua; this file decides where each unit's bar goes. A bar is
-- either ATTACHED — handed to the unit frame that published an attach point, which then
-- owns its width and drags it around as part of itself — or DETACHED, parented to the UI
-- root with its own width and its own edit-mode position.
local ipairs, pairs = ipairs, pairs
local tconcat = table.concat

local PLUGIN_ID = "cast_bars"

-- One entry per unit. Adding target or focus is an entry here plus a tab in the schema:
-- the widget itself is already unit-agnostic.
local UNITS = {
    {
        id          = "player",
        unit        = "player",
        prefix      = "player_",
        displayName = "Player Cast Bar",
        attachPoint = "unitframe.player",
        position    = { point = "BOTTOM", relPoint = "BOTTOM", x = 0, y = 200 },
    },
}

---------------------------------------------------------------------------
-- Per-unit controller
--
-- Owns one bar's placement. It reacts to two things: the anchor setting, and whether the
-- attach point it wants exists yet — which is why it subscribes rather than reads. A
-- consumer that looked the point up once would find nothing whenever the unit frames
-- plugin happened to load second.
---------------------------------------------------------------------------
local Controller = {}
Controller.__index = Controller

local function newController(def)
    return setmetatable({
        _def   = def,
        _owner = "castbars_ctl:" .. def.id,
    }, Controller)
end

-- The mode the settings ask for, given what is actually available. "attached" with nothing
-- published resolves to nil: there is no frame to be part of, and falling back to detached
-- would drop a bar the player never positioned into the middle of their screen.
function Controller:_targetMode()
    local anchor = SuuUI.Settings:Get(PLUGIN_ID, self._def.prefix .. "anchor")
    if anchor == "detached" then return "detached" end
    if self._provider then return "attached" end
    return nil
end

function Controller:_teardown()
    local bar = self._bar
    if not bar then return end
    -- Detached through the provider that took it, not the current one: when a unit frame
    -- revokes its point, the notification arrives with nil while the slot still exists,
    -- and that is exactly the moment the child has to come out.
    if self._attachedTo then
        self._attachedTo.Detach(bar)
        self._attachedTo = nil
    end
    if self._mode == "detached" then
        local frame = bar:GetFrame()
        SuuUI.MoveableFrame:Remove(frame)
        SuuUI.UIRoot:RemoveElement(frame)
    end
    bar:Destroy()
    self._bar  = nil
    self._mode = nil
end

function Controller:_build(mode)
    local def = self._def
    local CastBar = SuuUI._CastBars.CastBar

    if mode == "attached" then
        local provider = self._provider
        local bar = CastBar:Create(provider.frame, {
            unit        = def.unit,
            pluginId    = PLUGIN_ID,
            prefix      = def.prefix,
            displayName = def.displayName,
            attached    = true,
        })
        -- The frame owns placement and sizing from here: it stretches the bar to its own
        -- width, so the width slider is greyed out and the bar needs no idea how wide it is.
        provider.Attach(bar, {
            position = SuuUI.Settings:Get(PLUGIN_ID, def.prefix .. "attach_position"),
        })
        self._attachedTo = provider
        self._bar, self._mode = bar, mode
        return
    end

    local root = SuuUI.UIRoot:GetRootContainer()
    local bar = CastBar:Create(root:GetFrame(), {
        unit        = def.unit,
        pluginId    = PLUGIN_ID,
        prefix      = def.prefix,
        displayName = def.displayName,
        attached    = false,
    })
    local frame = bar:GetFrame()
    -- Player-facing game UI, so the content rung — stated rather than inherited, so a
    -- settings window or a modal is guaranteed to draw over it.
    SuuUI.UIRoot:SetLayer(frame, "normal")
    SuuUI.MoveableFrame:Apply(frame, {
        pluginId    = PLUGIN_ID,
        key         = def.prefix .. "position",
        displayName = def.displayName,
        defaults    = def.position,
    })
    self._bar, self._mode = bar, mode
end

-- Brings the bar into agreement with the settings and the available attach points.
--
-- A mode change rebuilds rather than re-parents, which is the one place this plugin does
-- not patch a single property: the widget's PARENT differs between the two modes, and no
-- property patch expresses that. It is lossless — the new widget reads UnitCastingInfo in
-- its constructor, so a cast in flight carries straight over — and it only ever runs on a
-- deliberate settings change, never on a game event.
function Controller:Sync()
    local want = self:_targetMode()
    if want == self._mode and (want ~= "attached" or self._attachedTo == self._provider) then
        -- Same mode and same host: nothing structural changed. Placement inside the host
        -- still might have, so restate it.
        if want == "attached" and self._bar then
            self._attachedTo.Detach(self._bar)
            self._attachedTo.Attach(self._bar, {
                position = SuuUI.Settings:Get(PLUGIN_ID, self._def.prefix .. "attach_position"),
            })
        end
        return
    end
    self:_teardown()
    if want then self:_build(want) end
end

function Controller:Start()
    local def = self._def

    -- The attach point may appear later, disappear on a plugin disable, or never exist.
    -- All three arrive through the same callback.
    SuuUI.AttachPoints:Request(def.attachPoint, function(provider)
        self._provider = provider
        self:Sync()
    end, self._owner)

    for _, key in ipairs({ "anchor", "attach_position" }) do
        SuuUI.Settings:Watch(PLUGIN_ID, def.prefix .. key, function()
            self:Sync()
        end, self._owner .. ":" .. key)
    end
end

function Controller:Stop()
    SuuUI.AttachPoints:Release(self._owner)
    SuuUI.Settings:UnwatchPrefix(self._owner)
    self:_teardown()
end

--- Returns the live bar handle, or nil while there is nowhere to put one.
-- @return table|nil
function Controller:GetBar()
    return self._bar
end

--- Returns the placement currently in force: "attached", "detached" or nil.
-- @return string|nil
function Controller:GetMode()
    return self._mode
end

---------------------------------------------------------------------------
-- Blizzard frames to hide
---------------------------------------------------------------------------
-- The player cast bar's global name is a property of the client, not a constant: it is
-- `PlayerCastingBarFrame` once Edit Mode reaches a client generation and
-- `CastingBarFrame` before that. Both are listed because one addon has to run on both,
-- and the one that is absent is simply not there to hide.
--
-- Only the player's own bar: hiding the pet bar as well would suppress something this
-- plugin does not replace yet.
local BLIZZARD_CAST_FRAMES = { "PlayerCastingBarFrame", "CastingBarFrame" }

-- Blizzard frames are permanent globals, so this never holds more than one entry per
-- name. It exists so a disable/enable cycle does not stack a second hook on the frame.
local hooked = {}

local function suppress(frame)
    frame:UnregisterAllEvents()
    frame:Hide()
    -- Unregistering closes every route the bar shows itself through on its own, but an
    -- Edit Mode client re-shows a system frame when a layout is applied and never asks
    -- us first. The hook is the only form that survives a Show this plugin did not
    -- predict, and HookScript keeps Blizzard's own handler rather than replacing it.
    if not hooked[frame] then
        hooked[frame] = true
        frame:HookScript("OnShow", function(self) self:Hide() end)
    end
end

local function hideBlizzardCastBar()
    local found = false
    for _, name in ipairs(BLIZZARD_CAST_FRAMES) do
        local frame = _G[name]
        if frame then
            suppress(frame)
            found = true
        end
    end
    -- Say so rather than passing over it. A bare `if frame then` is what let this ship
    -- looking for the pre-Edit-Mode name alone: nothing errored, nothing happened, and
    -- Blizzard's cast bar stayed on screen underneath ours.
    if not found then
        SuuUI.Debug("CastBars: no Blizzard player cast bar found to hide (looked for "
            .. tconcat(BLIZZARD_CAST_FRAMES, ", ") .. ")")
    end
end

---------------------------------------------------------------------------
-- Plugin registration
---------------------------------------------------------------------------
local plugin = SuuUI:CreatePlugin({
    id      = "cast_bars",
    name    = "Cast Bars",
    version = "0.1",

    onInit = function(p)
        -- Per-unit settings live inside that unit's tab and are declared THERE, once:
        -- Settings:Register indexes a tab's entries exactly like top-level ones, so the
        -- default, the range and the label all sit in a single declaration.
        SuuUI.Settings:Register(PLUGIN_ID, {
            { key = "enabled", label = "Enable Cast Bars", type = "toggle", default = true },

            -- Written by MoveableFrame while detached, never edited on the page.
            { key = "player_position", type = "position",
              default = { point = "BOTTOM", relPoint = "BOTTOM", x = 0, y = 200 } },

            { key = "unit", type = "subtabs", tabs = {
                { id = "player", label = "Player", schema = {
                    { key = "", label = "General", type = "section" },
                    { key = "player_enabled",   label = "Enable Cast Bar", type = "toggle", default = true },
                    { key = "player_show_icon", label = "Show Icon",       type = "toggle", default = true },
                    { key = "player_show_name", label = "Show Spell Name", type = "toggle", default = true },
                    { key = "player_show_time", label = "Show Cast Time",  type = "toggle", default = true },
                    -- Information rather than decoration, so it defaults on — but a player
                    -- who finds the outline noisy can switch it off.
                    { key = "player_show_shield", label = "Mark Uninterruptible Casts",
                      type = "toggle", default = true },

                    { key = "", label = "Placement", type = "section" },
                    { key = "player_anchor", label = "Attach To", type = "dropdown",
                      default = "attached", options = {
                        { value = "attached", label = "Player Frame" },
                        { value = "detached", label = "Detached" },
                      } },
                    -- Only meaningful while attached: a detached bar sits wherever it was
                    -- dragged, so above/below has nothing to be relative to.
                    { key = "player_attach_position", label = "Position", type = "dropdown",
                      default = "below", options = {
                        { value = "above", label = "Above Frame" },
                        { value = "below", label = "Below Frame" },
                      },
                      enabledIf = { key = "player_anchor", equals = "attached" } },
                    -- An attached bar takes its width from the frame it is part of, so the
                    -- slider is greyed out rather than silently ignored. Defaulted to the
                    -- player frame's own width so detaching does not resize it.
                    { key = "player_width", label = "Width", type = "slider",
                      min = 80, max = 500, step = 2, default = 304,
                      enabledIf = { key = "player_anchor", equals = "detached" } },

                    { key = "", label = "Appearance", type = "section" },
                    { key = "player_icon_position", label = "Icon Side", type = "dropdown",
                      default = "left", options = {
                        { value = "left",  label = "Left" },
                        { value = "right", label = "Right" },
                      } },
                    { key = "player_time_format", label = "Cast Time", type = "dropdown",
                      default = "remaining", options = {
                        { value = "remaining", label = "Remaining (1.4)" },
                        { value = "elapsed",   label = "Elapsed (1.1)" },
                        { value = "both",      label = "Elapsed / Total (1.1 / 2.5)" },
                        { value = "percent",   label = "Percent (44%)" },
                      } },
                    { key = "player_height", label = "Height", type = "slider",
                      min = 12, max = 48, step = 1, default = 22 },

                    { key = "", label = "Colour", type = "section" },
                    -- School colouring is the default because it carries information the
                    -- fixed colours cannot. The pickers below stay, greyed, because they
                    -- are still the fallback for a spell whose school nothing has reported
                    -- — and because a fixed bar colour matching the rest of someone's UI is
                    -- a legitimate taste rather than a worse choice.
                    { key = "player_school_color", label = "Colour by Spell School",
                      type = "toggle", default = true },
                    { key = "player_cast_color",    label = "Cast",    type = "color",
                      default = { 0.85, 0.63, 0.17, 1 },
                      enabledIf = { key = "player_school_color", equals = false } },
                    { key = "player_channel_color", label = "Channel", type = "color",
                      default = { 0.25, 0.55, 0.85, 1 },
                      enabledIf = { key = "player_school_color", equals = false } },
                }},
            }},
        })

        SuuUI.ReloadGuard:Register(PLUGIN_ID, "enabled", {
            title   = "Reload Required",
            message = "Enabling or disabling Cast Bars requires a UI reload. Reload now?",
        })
        SuuUI.ReloadGuard:Register(PLUGIN_ID, "player_enabled", {
            title   = "Reload Required",
            message = "Enabling or disabling the Player Cast Bar requires a UI reload. Reload now?",
        })
    end,

    onEnable = function(p)
        p._controllers = {}
        for _, def in ipairs(UNITS) do
            if SuuUI.Settings:Get(PLUGIN_ID, def.prefix .. "enabled") then
                if def.unit == "player" then hideBlizzardCastBar() end
                local ctl = newController(def)
                p._controllers[def.id] = ctl
                ctl:Start()
            end
        end
    end,

    onDisable = function(p)
        if not p._controllers then return end
        for _, ctl in pairs(p._controllers) do ctl:Stop() end
        p._controllers = nil
        -- Blizzard frames are restored by the reload — no manual restore needed
    end,
})
