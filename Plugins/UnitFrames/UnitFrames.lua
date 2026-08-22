-- UnitFrames plugin: registration, settings, and the per-unit wiring.
--
-- The widget lives in UnitFrame.lua; this file decides which units get one, where each
-- starts, and which Blizzard frame each replaces. Adding a unit is an entry in UNITS and
-- nothing else: the widget is already unit-agnostic and the schema is derived from the
-- prefix.
local ipairs, pairs = ipairs, pairs

local PLUGIN_ID = "unit_frames"

---------------------------------------------------------------------------
-- Units
--
-- `always` marks a unit that cannot be absent. The player is the only one: every other
-- unit token can be empty, and a frame for an empty unit hides itself. Stating it per unit
-- rather than testing `unit == "player"` inside the widget keeps the widget from knowing
-- which unit is special.
--
-- Default positions mirror each other across the screen because that is where a player
-- expects to find them, and they are only DEFAULTS — MoveableFrame writes whatever the
-- player drags to.
---------------------------------------------------------------------------
local UNITS = {
    {
        id          = "player",
        unit        = "player",
        prefix      = "player_",
        label       = "Player",
        displayName = "Player",
        always      = true,
        blizzard    = { "PlayerFrame" },
        position    = { point = "BOTTOMLEFT", relPoint = "BOTTOMLEFT", x = 20, y = 60 },
        -- Where the resource bar lands the first time it is detached. Centred low, clear of
        -- the cast bar's own default, so a player who detaches it finds it rather than
        -- discovering it underneath something else.
        powerPosition = { point = "BOTTOM", relPoint = "BOTTOM", x = 0, y = 170 },
        defaults    = { width = 304, healthHeight = 39, powerHeight = 22,
                        healthCenter = "current_max", auraSize = 24 },
    },
    {
        id          = "target",
        unit        = "target",
        prefix      = "target_",
        label       = "Target",
        displayName = "Target",
        -- The one event that says "everything on this frame is now about someone else".
        changeEvent = "PLAYER_TARGET_CHANGED",
        -- TargetFrame's cast bar and its target-of-target are its own children, so they go
        -- down with it and are deliberately not listed: naming a child as well would be
        -- this plugin claiming to replace something it does not.
        blizzard    = { "TargetFrame" },
        position    = { point = "BOTTOMRIGHT", relPoint = "BOTTOMRIGHT", x = -20, y = 60 },
        powerPosition = { point = "BOTTOM", relPoint = "BOTTOM", x = 0, y = 230 },
        defaults    = { width = 304, healthHeight = 39, powerHeight = 22,
                        healthCenter = "current_max", auraSize = 24 },
    },
}

--- The field a unit's frame handle is stored under on the plugin handle.
-- Derived rather than stored twice: `_playerFrame` and `_targetFrame` are the names other
-- code and the specs already reach for, and a lookup table beside them would be a second
-- place to keep in step.
-- @param def table  A UNITS entry
-- @return string
local function handleField(def)
    return "_" .. def.id .. "Frame"
end

---------------------------------------------------------------------------
-- Blizzard frames to hide/restore
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

-- Never touches a frame this plugin did not hide: with a unit's frame switched off we
-- never suppressed anything, and showing it here would override whatever else hid it.
--
-- The flag is cleared BEFORE the Show, or the hook we cannot uninstall hides it again on
-- the way out.
local function restore(frame)
    if not suppressed[frame] then return end
    suppressed[frame] = nil
    frame:Show()
end

-- Applies fn to every Blizzard frame one unit replaces. A name absent from this client
-- generation is simply not there to hide, so it is skipped rather than reported: unlike the
-- cast bar's two spellings, these names are not alternatives for the same frame.
local function forEachBlizzardFrame(def, fn)
    for _, name in ipairs(def.blizzard or {}) do
        local frame = _G[name]
        if frame then fn(frame) end
    end
end

---------------------------------------------------------------------------
-- Per-unit lifecycle
---------------------------------------------------------------------------

--- Builds one unit's frame, makes it moveable, and offers it as an attach point.
-- @param p table    Plugin handle
-- @param def table  A UNITS entry
local function buildUnit(p, def)
    forEachBlizzardFrame(def, suppress)

    local root = SuuUI.UIRoot:GetRootContainer()
    local widget = SuuUI._UnitFrames.UnitFrame:Create(root:GetFrame(), {
        unit        = def.unit,
        pluginId    = PLUGIN_ID,
        prefix      = def.prefix,
        displayName = def.displayName,
        always      = def.always,
        changeEvent = def.changeEvent,
        -- Where a detached resource bar starts. The widget owns that bar's placement in
        -- both modes, so the default travels with the unit rather than living in the widget.
        powerPosition = def.powerPosition,
    })
    p[handleField(def)] = widget

    local frame = widget:GetFrame()

    -- Player-facing game UI, so it belongs on the content rung — stated through the
    -- library's layer system rather than left to inherit, so a settings window or a modal
    -- is guaranteed to draw over it.
    SuuUI.UIRoot:SetLayer(frame, "normal")

    -- Position stored in plugin settings, so it is profile-aware for free.
    --
    -- coreInset is what keeps the stored position describing THIS frame's content rather
    -- than its bounding box. The frame grows around whatever attaches to it, and growth
    -- happens on the edge the anchor does not pin — so without this a cast bar attaching
    -- below pushed the bars up by its own height, and detaching pushed them back down.
    SuuUI.MoveableFrame:Apply(frame, {
        pluginId    = PLUGIN_ID,
        key         = def.prefix .. "position",
        displayName = def.displayName,
        defaults    = def.position,
        coreInset   = function() return widget:GetCoreInset() end,
    })

    -- Offer the frame as an attach point. Another plugin can now place a widget inside it —
    -- a cast bar attaches here — without either plugin knowing the other exists: a consumer
    -- that loads first simply gets told when this appears. Placement stays ours, so the
    -- frame still owns its own geometry.
    SuuUI.AttachPoints:Publish("unitframe." .. def.id, {
        frame  = frame,
        Attach = function(child, opts) return widget:AttachChild(child, opts) end,
        Detach = function(child) return widget:DetachChild(child) end,
    })
end

--- Tears one unit's frame down and hands Blizzard's back.
-- @param p table    Plugin handle
-- @param def table  A UNITS entry
local function teardownUnit(p, def)
    -- Revoked before anything is torn down: consumers detach on the nil notification, so
    -- nothing foreign is still sitting in a slot when the containers go away.
    SuuUI.AttachPoints:Revoke("unitframe." .. def.id)

    local field = handleField(def)
    local widget = p[field]
    if widget then
        SuuUI.MoveableFrame:Remove(widget:GetFrame())
        widget:Destroy()
        p[field] = nil
    end

    -- A programmatic Disable has no reload behind it, so this is the only thing that undoes
    -- the suppression. Safe to call unconditionally -- restore skips any frame this plugin
    -- did not hide.
    forEachBlizzardFrame(def, restore)
end

---------------------------------------------------------------------------
-- Plugin registration
---------------------------------------------------------------------------
local plugin = SuuUI:CreatePlugin({
    id      = "unit_frames",
    name    = "Unit Frames",
    version = "0.1",

    onInit = function(p)
        -- The frames' own dimensions are settings, not theme tokens: they describe one
        -- plugin's widgets rather than the design language, and a player wants them per
        -- profile.
        --
        -- Per-unit settings live inside that unit's tab and are declared THERE, once, by
        -- UnitFrame.Schema. Settings:Register indexes a tab's entries like top-level ones,
        -- so the default, the range and the label all sit in a single declaration — a key
        -- repeated at the top level as well would let the default and the slider range
        -- drift apart.
        local schema = {
            { key = "enabled", label = "Enable Unit Frames", type = "toggle", default = true },
        }

        local tabs = {}
        for _, def in ipairs(UNITS) do
            -- Placement is written by MoveableFrame, not edited on the page, so it needs a
            -- home in the profile and no control.
            schema[#schema + 1] = {
                key = def.prefix .. "position", type = "position", default = def.position,
            }
            -- The detached resource bar's own position, written by MoveableFrame the same
            -- way. It needs a home in the profile whether or not the bar is currently
            -- detached, so the player's placement survives inlining it and detaching again.
            schema[#schema + 1] = {
                key = def.prefix .. "power_position", type = "position",
                default = def.powerPosition,
            }
            tabs[#tabs + 1] = {
                id     = def.id,
                label  = def.label,
                schema = SuuUI._UnitFrames.UnitFrame.Schema(def.prefix, {
                    width        = def.defaults.width,
                    healthHeight = def.defaults.healthHeight,
                    powerHeight  = def.defaults.powerHeight,
                    healthCenter = def.defaults.healthCenter,
                    auraSize     = def.defaults.auraSize,
                    -- What "attached" means for this unit, named after the frame the bar
                    -- would be part of. Derived from the unit's label rather than stored,
                    -- so it cannot drift from the label the tab already carries.
                    attachLabel  = def.label .. " Frame",
                }),
            }
        end

        -- One tab per unit frame, in UNITS order.
        schema[#schema + 1] = { key = "unit", type = "subtabs", tabs = tabs }

        SuuUI.Settings:Register(PLUGIN_ID, schema)

        -- Guard settings that require a reload. The master switch plus one per unit, since
        -- each builds and destroys real frames.
        SuuUI.ReloadGuard:Register(PLUGIN_ID, "enabled", {
            title   = "Reload Required",
            message = "Enabling or disabling Unit Frames requires a UI reload. Reload now?",
        })
        for _, def in ipairs(UNITS) do
            SuuUI.ReloadGuard:Register(PLUGIN_ID, def.prefix .. "enabled", {
                title   = "Reload Required",
                message = "Enabling or disabling the " .. def.label ..
                          " Frame requires a UI reload. Reload now?",
            })
        end
    end,

    onEnable = function(p)
        for _, def in ipairs(UNITS) do
            if SuuUI.Settings:Get(PLUGIN_ID, def.prefix .. "enabled") then
                buildUnit(p, def)
            end
        end
    end,

    onDisable = function(p)
        -- Every unit, not only the ones currently built: teardownUnit is a no-op for a unit
        -- that has no frame, and iterating what was built would need a second record of it.
        for _, def in ipairs(UNITS) do
            teardownUnit(p, def)
        end
    end,
})
