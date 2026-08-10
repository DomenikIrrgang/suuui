-- CastBars plugin: registration, settings, and the per-unit wiring.
--
-- The widget lives in CastBar.lua; this file decides where each unit's bar goes. A bar is
-- either ATTACHED — handed to the unit frame that published an attach point, which then
-- owns its width and drags it around as part of itself — or DETACHED, parented to the UI
-- root with its own width and its own edit-mode position.
local ipairs, pairs = ipairs, pairs
local tconcat = table.concat

local PLUGIN_ID = "cast_bars"

-- One entry per unit. Adding focus is an entry here and nothing else: the widget is
-- unit-agnostic and the schema is derived from the prefix.
local UNITS = {
    {
        id          = "player",
        unit        = "player",
        prefix      = "player_",
        label       = "Player",
        displayName = "Player Cast Bar",
        attachPoint = "unitframe.player",
        attachLabel = "Player Frame",
        -- The player cast bar's global name is a property of the client, not a constant: it
        -- is `PlayerCastingBarFrame` once Edit Mode reaches a client generation and
        -- `CastingBarFrame` before that. Both are listed because one addon has to run on
        -- both, and the one that is absent is simply not there to hide.
        --
        -- Only the player's own bar: hiding the pet bar as well would suppress something
        -- this plugin does not replace yet.
        blizzard    = { "PlayerCastingBarFrame", "CastingBarFrame" },
        position    = { point = "BOTTOM", relPoint = "BOTTOM", x = 0, y = 200 },
        defaults    = { width = 304, height = 22 },
    },
    {
        id          = "target",
        unit        = "target",
        prefix      = "target_",
        label       = "Target",
        displayName = "Target Cast Bar",
        attachPoint = "unitframe.target",
        attachLabel = "Target Frame",
        -- Everything on the bar is now someone else's cast, so the widget re-reads the unit.
        changeEvent = "PLAYER_TARGET_CHANGED",
        -- A child of TargetFrame, so the unit frames plugin already takes it down when it
        -- replaces that frame — but suppressed here as well, because this plugin must not
        -- depend on that one being enabled.
        blizzard    = { "TargetFrameSpellBar" },
        position    = { point = "BOTTOM", relPoint = "BOTTOM", x = 0, y = 260 },
        defaults    = { width = 304, height = 22 },
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

    -- One cfg for both modes: they differ only in who owns the width, so building the table
    -- twice would be two places to add the next field to.
    local cfg = {
        unit        = def.unit,
        pluginId    = PLUGIN_ID,
        prefix      = def.prefix,
        displayName = def.displayName,
        changeEvent = def.changeEvent,
        attached    = mode == "attached",
    }

    if mode == "attached" then
        local provider = self._provider
        local bar = CastBar:Create(provider.frame, cfg)
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
    local bar = CastBar:Create(root:GetFrame(), cfg)
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
--
-- Which frames a unit replaces is a property of that unit, so the list lives in its UNITS
-- entry. A name absent from this client generation is simply not there to hide.
---------------------------------------------------------------------------

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
-- frame back alive, which is what left Blizzard's bar dead until a reload. The hook is a
-- complete suppression mechanism on its own -- a hidden frame can only become visible
-- through a show, and every show fires OnShow -- so the registrations stay where Blizzard
-- put them and the cost of suppressing is one Hide().
local function suppress(frame)
    suppressed[frame] = true
    -- Unregistering would close the routes the bar shows itself through, but an Edit Mode
    -- client re-shows a system frame when a layout is applied and never asks us first.
    -- The hook is the only form that survives a Show this plugin did not predict, and
    -- HookScript keeps Blizzard's own handler rather than replacing it.
    if not hooked[frame] then
        hooked[frame] = true
        frame:HookScript("OnShow", function(self)
            if suppressed[self] then self:Hide() end
        end)
    end
    frame:Hide()
end

-- Never touches a frame this plugin did not hide: with the player cast bar switched off
-- we never suppressed anything, and showing it here would override whatever else hid it.
--
-- The flag is cleared BEFORE the Show, or the hook we cannot uninstall hides it again on
-- the way out.
local function restore(frame)
    if not suppressed[frame] then return end
    suppressed[frame] = nil
    frame:Show()
end

local function forEachBlizzardCastFrame(def, fn)
    local found = false
    for _, name in ipairs(def.blizzard or {}) do
        local frame = _G[name]
        if frame then
            fn(frame)
            found = true
        end
    end
    return found
end

local function hideBlizzardCastBar(def)
    -- Say so rather than passing over it. A bare `if frame then` is what let this ship
    -- looking for the pre-Edit-Mode name alone: nothing errored, nothing happened, and
    -- Blizzard's cast bar stayed on screen underneath ours.
    if not forEachBlizzardCastFrame(def, suppress) then
        SuuUI.Debug("CastBars: no Blizzard " .. def.unit .. " cast bar found to hide "
            .. "(looked for " .. tconcat(def.blizzard or {}, ", ") .. ")")
    end
end

local function restoreBlizzardCastBar(def)
    forEachBlizzardCastFrame(def, restore)
end

---------------------------------------------------------------------------
-- Plugin registration
---------------------------------------------------------------------------
local plugin = SuuUI:CreatePlugin({
    id      = "cast_bars",
    name    = "Cast Bars",
    version = "0.1",

    onInit = function(p)
        -- Per-unit settings live inside that unit's tab and are declared THERE, once, by
        -- CastBar.Schema: Settings:Register indexes a tab's entries exactly like top-level
        -- ones, so the default, the range and the label all sit in a single declaration.
        local schema = {
            { key = "enabled", label = "Enable Cast Bars", type = "toggle", default = true },
        }

        local tabs = {}
        for _, def in ipairs(UNITS) do
            -- Written by MoveableFrame while detached, never edited on the page.
            schema[#schema + 1] = {
                key = def.prefix .. "position", type = "position", default = def.position,
            }
            local opts = {
                attachLabel = def.attachLabel,
                width       = def.defaults.width,
                height      = def.defaults.height,
            }
            tabs[#tabs + 1] = {
                id     = def.id,
                label  = def.label,
                schema = SuuUI._CastBars.CastBar.Schema(def.prefix, opts),
            }
        end

        schema[#schema + 1] = { key = "unit", type = "subtabs", tabs = tabs }

        SuuUI.Settings:Register(PLUGIN_ID, schema)

        SuuUI.ReloadGuard:Register(PLUGIN_ID, "enabled", {
            title   = "Reload Required",
            message = "Enabling or disabling Cast Bars requires a UI reload. Reload now?",
        })
        for _, def in ipairs(UNITS) do
            SuuUI.ReloadGuard:Register(PLUGIN_ID, def.prefix .. "enabled", {
                title   = "Reload Required",
                message = "Enabling or disabling the " .. def.displayName ..
                          " requires a UI reload. Reload now?",
            })
        end
    end,

    onEnable = function(p)
        p._controllers = {}
        for _, def in ipairs(UNITS) do
            if SuuUI.Settings:Get(PLUGIN_ID, def.prefix .. "enabled") then
                hideBlizzardCastBar(def)
                local ctl = newController(def)
                p._controllers[def.id] = ctl
                ctl:Start()
            end
        end
    end,

    onDisable = function(p)
        -- Hand Blizzard's bars back before anything else: a programmatic Disable has no
        -- reload behind it, so this is the only thing that undoes the suppression. Safe to
        -- call unconditionally -- restore skips any frame this plugin did not hide.
        for _, def in ipairs(UNITS) do
            restoreBlizzardCastBar(def)
        end

        if not p._controllers then return end
        for _, ctl in pairs(p._controllers) do ctl:Stop() end
        p._controllers = nil
    end,
})
