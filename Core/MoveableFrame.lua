-- MoveableFrame: mixin that makes a SuuUI frame repositionable in edit mode.
-- Stores position in the plugin's Settings namespace so it is profile-aware.
local C = SuuUI.Components
local T = SuuUI.Theme

local M = {}

--- Applies moveable behaviour to a frame.
-- @param frame table  The raw WoW frame (not a component wrapper)
-- @param opts table   { pluginId, key, displayName, defaults }
--   pluginId    - plugin id for Settings:Get/Set
--   key         - settings key for position storage
--   displayName - label shown on overlay during edit mode
--   defaults    - { point, relPoint, x, y } default position
function M:Apply(frame, opts)
    local pluginId    = opts.pluginId
    local key         = opts.key
    local displayName = opts.displayName or ""
    local defaults    = opts.defaults or { point = "CENTER", relPoint = "CENTER", x = 0, y = 0 }

    -- Register with ToggleUI
    SuuUI.ToggleUI:Register(frame)

    -- Create overlay (hidden by default). It stays on the frame's own layer and is only
    -- raised above it: promoting it to a higher layer would draw the edit-mode overlay
    -- over the settings window that carries the Edit Mode toggle.
    local overlay = CreateFrame("Frame", nil, frame)
    overlay:SetAllPoints(frame)
    SuuUI.UIRoot:RaiseAbove(overlay, frame, 5)
    overlay:Hide()

    -- Overlay backdrop (semi-transparent blue)
    local overlayBg = overlay:CreateTexture(nil, "BACKGROUND")
    overlayBg:SetAllPoints(overlay)
    overlayBg:SetColorTexture(0, 0.6, 1, 0.2)

    -- Overlay label
    local label = overlay:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    label:SetPoint("CENTER", overlay, "CENTER", 0, 0)
    label:SetText(displayName)

    -- Store references for cleanup
    frame._suuui_moveable = {
        overlay     = overlay,
        overlayBg   = overlayBg,
        label       = label,
        pluginId    = pluginId,
        key         = key,
        defaults    = defaults,
        displayName = displayName,
    }

    -- Drag setup (always configured, only active in edit mode)
    frame:SetMovable(true)
    frame:SetClampedToScreen(true)

    overlay:EnableMouse(true)
    overlay:RegisterForDrag("LeftButton")
    overlay:SetScript("OnDragStart", function()
        if SuuUI.ToggleUI:IsEditMode() then
            frame:StartMoving()
        end
    end)
    overlay:SetScript("OnDragStop", function()
        frame:StopMovingOrSizing()
        -- Save position. The position watcher below would echo this write straight
        -- back into RestorePosition, so it is suppressed for the duration of our own
        -- save; only changes from elsewhere (a profile switch, a reset) should move
        -- the frame out from under the player.
        local point, _, relPoint, x, y = frame:GetPoint()
        local data = frame._suuui_moveable
        data._saving = true
        SuuUI.Settings:Set(pluginId, key, {
            point    = point,
            relPoint = relPoint,
            x        = x,
            y        = y,
        })
        data._saving = false
    end)

    -- Edit mode drives the overlay. `immediate` matters: a frame created while edit
    -- mode is already on must show its overlay at once, not wait for the next toggle.
    SuuUI.Settings:Watch("_layout", "edit_mode", function(isEdit)
        if isEdit then
            overlay:Show()
        else
            overlay:Hide()
        end
    end, "moveable_" .. pluginId .. "_" .. key, { immediate = true })

    -- Position is bound the same way, so `immediate` also performs the initial restore.
    SuuUI.Settings:Watch(pluginId, key, function()
        local data = frame._suuui_moveable
        if not data or data._saving then return end
        M:RestorePosition(frame)
    end, "moveable_pos_" .. pluginId .. "_" .. key, { immediate = true })
end

--- Restores a frame's position from Settings or defaults.
-- @param frame table
function M:RestorePosition(frame)
    local data = frame._suuui_moveable
    if not data then return end

    local pos = SuuUI.Settings:Get(data.pluginId, data.key)
    if not pos then pos = data.defaults end
    frame:ClearAllPoints()
    frame:SetPoint(pos.point, UIParent, pos.relPoint, pos.x, pos.y)
end

--- Resets a frame's position to its defaults.
-- @param frame table
function M:ResetPosition(frame)
    local data = frame._suuui_moveable
    if not data then return end

    SuuUI.Settings:Set(data.pluginId, data.key, SuuUI.Utils.DeepCopy(data.defaults))
    M:RestorePosition(frame)
end

--- Removes moveable behaviour from a frame and cleans up.
-- @param frame table
function M:Remove(frame)
    local data = frame._suuui_moveable
    if not data then return end

    SuuUI.Settings:Unwatch("moveable_" .. data.pluginId .. "_" .. data.key)
    SuuUI.Settings:Unwatch("moveable_pos_" .. data.pluginId .. "_" .. data.key)
    SuuUI.ToggleUI:Unregister(frame)

    data.overlay:Hide()
    data.overlay:SetScript("OnDragStart", nil)
    data.overlay:SetScript("OnDragStop", nil)

    frame._suuui_moveable = nil
end

SuuUI.MoveableFrame = M
