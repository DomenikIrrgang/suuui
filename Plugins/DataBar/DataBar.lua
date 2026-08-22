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
        -- The clock declares its own settings; the plugin only splices the slice in, so the
        -- widget owns everything about itself including its section header.
        for _, entry in ipairs(SuuUI._DataBar.TimeWidget.Schema()) do
            schema[#schema + 1] = entry
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
        SuuUI._DataBar.TimeWidget.Enable()

        -- Re-assert on the events that re-run Blizzard's own layout. PLAYER_ENTERING_WORLD
        -- covers a login or a zone change applying a layout; the two display events cover the
        -- conversion changing under us, since the offset is scale-dependent.
        p._evt = CreateFrame("Frame")
        p._evt:RegisterEvent("PLAYER_ENTERING_WORLD")
        p._evt:RegisterEvent("DISPLAY_SIZE_CHANGED")
        p._evt:RegisterEvent("UI_SCALE_CHANGED")
        p._evt:SetScript("OnEvent", function() reapplyAll() end)

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

        SuuUI._DataBar.TimeWidget.Disable()
        if p._bar then
            p._bar:Destroy()
            p._bar = nil
        end
    end,
})
