-- DataBar plugin: owns the bar, the built-in clock, and moving Blizzard's frames out from
-- under it.
local ipairs, pairs, type, pcall, tostring = ipairs, pairs, type, pcall, tostring

local PLUGIN_ID = "data_bar"
local OWNER     = "data_bar"

---------------------------------------------------------------------------
-- Blizzard frames that hug the top of the screen
---------------------------------------------------------------------------
-- Measured on this client: both are anchored TOPRIGHT to UIParent TOPRIGHT, the minimap at
-- (0, 0) and the buff frame at (-187, -13).
--
-- TemporaryEnchantFrame is absent here, so it is deliberately NOT listed: on a client that
-- has it, it may well be anchored relative to BuffFrame, and moving both would offset it
-- twice. Adding a frame to this list is a measurement, not a guess.
local TOP_FRAMES = { "MinimapCluster", "BuffFrame" }

-- What THIS plugin is currently offsetting, and the anchor each frame had before we touched
-- it. The offset is always computed from the ORIGINAL y, never from the current one, or every
-- re-assert would stack another bar height onto it.
local managed  = {}
local hooked   = {}
local applying = false

local function rootFrame()
    local R = SuuUI.UIRoot
    return R and R.GetRoot and R:GetRoot()
end

-- The bar's height is a length in the UI root's units, and the root carries the addon's pixel
-- scale while these frames are anchored to UIParent. Handing the raw number over is the
-- vertical-only failure the pixel docs warn about: the minimap would move down by not quite
-- the right amount, and only on some resolutions.
local function offsetIn(frame)
    local h = SuuUI.DataBar:GetOccupiedHeight()
    if h <= 0 then return 0 end
    return SuuUI.Pixel.Convert(h, rootFrame(), frame)
end

-- SetPoint on a frame we do not own, in a plugin file. That is the same carve-out as
-- frame:Hide() in onEnable: a Blizzard frame is not our UI, it cannot be put in one of our
-- containers (reparenting it taints), and the layout engine has no way to place it. The rule
-- that SetPoint belongs to the four strategies is about OUR frames.
local function place(frame, y)
    applying = true
    frame:ClearAllPoints()
    local o = managed[frame]
    frame:SetPoint(o.point, o.relTo, o.relPoint, o.x, y)
    applying = false
end

local function reapply(frame)
    local o = managed[frame]
    if not o then return end
    place(frame, o.y - offsetIn(frame))
end

local function reapplyAll()
    for frame in pairs(managed) do reapply(frame) end
end

-- Edit Mode exists on this client (EditModeManagerFrame is present), so these frames are
-- layout-managed: Blizzard re-anchors them on login, on a layout change, and whenever
-- UIParent_ManageFramePositions runs. A one-shot SetPoint is therefore reverted at a moment
-- the player will read as "the addon randomly stopped working".
--
-- hooksecurefunc cannot be undone, exactly like HookScript, so the hook asks `managed` on
-- every call rather than assuming it should always re-offset — which is what lets onDisable
-- hand the frame back. `applying` is the recursion guard: our own SetPoint re-enters here.
local function claim(frame)
    if not hooked[frame] then
        hooked[frame] = true
        hooksecurefunc(frame, "SetPoint", function(f)
            if applying or not managed[f] then return end
            reapply(f)
        end)
    end
end

local function suppressTop()
    for _, name in ipairs(TOP_FRAMES) do
        local frame = _G[name]
        if frame and not managed[frame] and frame.GetNumPoints and frame:GetNumPoints() > 0 then
            local point, relTo, relPoint, x, y = frame:GetPoint(1)
            managed[frame] = {
                point = point, relTo = relTo, relPoint = relPoint, x = x or 0, y = y or 0,
            }
            claim(frame)
            reapply(frame)
        end
    end
end

local function restoreTop()
    for frame, o in pairs(managed) do
        -- Cleared BEFORE the placement, or the hook we cannot uninstall re-offsets the frame
        -- on the way out. Same ordering rule as clearing the suppression flag before Show().
        managed[frame] = nil
        applying = true
        frame:ClearAllPoints()
        frame:SetPoint(o.point, o.relTo, o.relPoint, o.x, o.y)
        applying = false
    end
end

---------------------------------------------------------------------------
-- Built-in widgets
---------------------------------------------------------------------------
-- The clock, the framerate and latency readouts, and the addon-button tray. All four are
-- BUILT-INS rather than plugins of their own, so their settings live under this plugin's id
-- and their schema slices are spliced straight into the page. Resolved lazily rather than
-- captured at file scope, so the .toc's load order is not a second thing to keep in step.
local function builtins()
    local D = SuuUI._DataBar
    return { D.TimeWidget, D.FpsWidget, D.LatencyWidget, D.TrayWidget, D.MicroMenu }
end

local function collector()
    return SuuUI._DataBar.ButtonCollector
end

local function refreshTray()
    local W = SuuUI._DataBar.TrayWidget
    if W then W.Refresh() end
end

-- Whether the tray is on. The FIELD being registered is that fact: the `tray_enabled` watcher
-- both registers and unregisters it, so asking the registry avoids a second flag that could
-- drift from the setting. Without this gate the bar would keep collecting buttons off the ring
-- for a tray that is switched off -- the mirror image of the bug the toggle fix removed.
local function trayActive()
    local W = SuuUI._DataBar.TrayWidget
    return (W and W.ID and SuuUI.DataBar:Has(W.ID)) and true or false
end

-- Said once per session, and only when the conflict is real. MinimapButtonButton collects the
-- same frames by the same mechanism, so two collectors reparenting one button take it in
-- turns and the player watches an icon flicker between two homes. The tray stands down rather
-- than fighting; this is what tells the player why the field reads nothing.
local warned
local function warnAboutRival()
    if warned then return end
    local C = collector()
    if not C or not C.RivalLoaded() then return end
    warned = true
    SuuUI.Components.Notice({
        title   = "Addon Buttons conflict",
        message = C.RIVAL_ADDON .. " is loaded and collects the same minimap buttons.\n\n"
               .. "Disable one of the two: either turn off " .. C.RIVAL_ADDON
               .. ", or switch off Show Addon Buttons on this page. SuuUI has left the "
               .. "buttons alone for now.",
        tone    = "warning",
    })
end

-- A sweep a moment later. Not every minimap button announces itself: a hand-rolled one is just
-- a frame somebody parented to the minimap, with no event and no library callback behind it,
-- and plenty of addons build theirs a beat after the login pass.
local function sweepSoon(delay)
    local timer = _G.C_Timer
    if not (timer and type(timer.After) == "function") then return end
    pcall(timer.After, delay, function()
        local C = collector()
        if C then C.Collect() end
        refreshTray()
    end)
end

---------------------------------------------------------------------------
-- Settings contributed by widgets this plugin does not own
---------------------------------------------------------------------------
-- A widget registered by ANOTHER plugin may carry a `schema`, and those controls belong on
-- THIS page rather than on the contributor's: a player looking for a setting about a strip of
-- text they can see comes to the data bar. The VALUES stay in the contributor's own namespace,
-- which is what each entry's `owner` field says -- this plugin splices entries in and takes
-- them out again, and never reads or writes them.
--
-- Reconciled from the registry rather than stated once, because Settings:Register has already
-- run by the time a widget registers. Keyed by widget id so an unregister retracts exactly its
-- own keys and nothing else.
local contributed = {}

local function reconcileSchemas()
    local present = {}

    for _, def in ipairs(SuuUI.DataBar:List()) do
        present[def.id] = true
        if type(def.schema) == "table" and not contributed[def.id] then
            local keys = {}
            for _, entry in ipairs(def.schema) do
                if type(entry) == "table" and entry.key and entry.key ~= "" then
                    keys[#keys + 1] = entry.key
                end
            end
            -- Extend skips a key the page already declares, so a widget re-registering on
            -- re-enable cannot produce a page carrying two of every control.
            SuuUI.Settings:Extend(PLUGIN_ID, def.schema)
            contributed[def.id] = keys
        end
    end

    for id, keys in pairs(contributed) do
        if not present[id] then
            -- Retract also drops a section header the removal emptied, so switching a widget
            -- off does not leave a titled group with nothing inside it.
            SuuUI.Settings:Retract(PLUGIN_ID, keys)
            contributed[id] = nil
        end
    end
end

---------------------------------------------------------------------------
-- Events
---------------------------------------------------------------------------
local function onEvent(event)
    -- Blizzard re-runs its own layout on these, and the offset is scale-dependent, so the
    -- reposition is re-asserted rather than computed once at login.
    if event == "PLAYER_ENTERING_WORLD" or event == "DISPLAY_SIZE_CHANGED"
       or event == "UI_SCALE_CHANGED" then
        reapplyAll()
    end

    local C = collector()
    if not C or not trayActive() then return end

    if event == "PLAYER_ENTERING_WORLD" then
        C.Collect()
        warnAboutRival()
        -- LibDBIcon builds anything registered before PLAYER_LOGIN only afterwards and
        -- announces each one, which its callback covers. These two catch the buttons that
        -- announce nothing at all.
        sweepSoon(1)
        sweepSoon(5)
    elseif event == "ADDON_LOADED" or event == "PLAYER_REGEN_ENABLED" then
        -- ADDON_LOADED is the likeliest moment for a new button. PLAYER_REGEN_ENABLED matters
        -- because a button built from a secure template cannot be reparented in combat and the
        -- client refuses silently, so that collection is deferred rather than attempted.
        C.Collect()
    end

    refreshTray()
end

---------------------------------------------------------------------------
-- Plugin
---------------------------------------------------------------------------
local plugin = SuuUI:CreatePlugin({
    id      = "data_bar",
    name    = "Data Bar",
    version = "0.1",

    onInit = function(p)
        local schema = {
            { key = "enabled", label = "Enable Data Bar", type = "toggle", default = true },
            { key = "move_blizzard", label = "Move Minimap and Buffs Down",
              type = "toggle", default = true },
        }
        -- Each built-in declares its own settings and this plugin only splices the slices in,
        -- so a widget owns everything about itself including its section header. These are
        -- built-ins, so their entries carry no `owner` and their values live under this
        -- plugin's id; a third-party widget's schema arrives later through the registry (see
        -- reconcileSchemas) and does carry one.
        for _, widget in ipairs(builtins()) do
            for _, entry in ipairs(widget.Schema()) do
                schema[#schema + 1] = entry
            end
        end
        SuuUI.Settings:Register(PLUGIN_ID, schema)

        -- No `immediate` here on purpose. Plugins:autoEnable already applies the stored value
        -- during the login pass, and an immediate callback would run onEnable from inside the
        -- init pass — before other plugins' onInit had run, which is the ordering the two
        -- phases exist to guarantee. The bar tears down cleanly, so this needs no reload
        -- guard: the watcher covers every later change.
        SuuUI.Settings:Watch(PLUGIN_ID, "enabled", function(on)
            if on then p:Enable() else p:Disable() end
        end, OWNER .. ".enabled")
    end,

    onEnable = function(p)
        p._bar = SuuUI._DataBar.Bar:Create(SuuUI.UIRoot:GetRootContainer():GetFrame())
        for _, widget in ipairs(builtins()) do widget.Enable() end

        -- A widget from another plugin may register at any moment, so the page's schema is
        -- reconciled from the registry rather than stated once. Subscribe delivers immediately
        -- with whatever is already registered, so there is no separate initial pass.
        SuuUI.DataBar:Subscribe(reconcileSchemas, OWNER .. ".schema")

        local C = collector()
        if C then
            -- A held button that moves, shows or hides itself changes the roster, and the
            -- panel may be open while it happens.
            C.SetChangeCallback(refreshTray)
        end
        -- Deliberately no Watch() or Collect() here. Whether buttons are collected belongs to
        -- the tray's own `tray_enabled` toggle, whose watcher fires immediately on enable --
        -- arming it here as well would collect the ring for a tray the player has switched off.

        -- One frame for every event this plugin cares about: the three that re-run Blizzard's
        -- layout, plus the two that mean a minimap button may have appeared.
        p._evt = CreateFrame("Frame")
        p._evt:RegisterEvent("PLAYER_ENTERING_WORLD")
        p._evt:RegisterEvent("DISPLAY_SIZE_CHANGED")
        p._evt:RegisterEvent("UI_SCALE_CHANGED")
        p._evt:RegisterEvent("ADDON_LOADED")
        p._evt:RegisterEvent("PLAYER_REGEN_ENABLED")
        p._evt:SetScript("OnEvent", function(_, event) onEvent(event) end)

        -- The height moves when a font or size token is edited, so the offset follows it
        -- rather than being computed once at login.
        SuuUI.DataBar:WatchHeight(function() reapplyAll() end, OWNER)

        SuuUI.Settings:Watch(PLUGIN_ID, "move_blizzard", function(on)
            if on then suppressTop() else restoreTop() end
        end, OWNER .. ".move", { immediate = true })
    end,

    onDisable = function(p)
        SuuUI.Settings:Unwatch(OWNER .. ".move")
        SuuUI.DataBar:UnwatchHeight(OWNER)
        -- Restored before the bar goes, so the frames land at their original anchors rather
        -- than at an offset derived from a height that is about to become 0.
        restoreTop()

        if p._evt then
            p._evt:UnregisterAllEvents()
            p._evt:SetScript("OnEvent", nil)
            p._evt = nil
        end

        SuuUI.DataBar:Unsubscribe(OWNER .. ".schema")

        local C = collector()
        if C then
            C.SetChangeCallback(nil)
            C.Unwatch()
        end

        for _, widget in ipairs(builtins()) do widget.Disable() end

        -- The ring gets its buttons back. Not optional and not only a path to a reload: a
        -- Disable from a settings watcher runs with nothing behind it, and a button left
        -- parented into a destroyed panel is invisible for the rest of the session.
        if C then C.Restore() end

        if p._bar then
            p._bar:Destroy()
            p._bar = nil
        end
    end,
})
