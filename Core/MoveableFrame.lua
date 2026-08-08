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

    -- Create overlay (hidden by default)
    local overlay = CreateFrame("Frame", nil, frame)
    overlay:SetAllPoints(frame)
    overlay:SetFrameStrata("DIALOG")
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
        -- Save position
        local point, _, relPoint, x, y = frame:GetPoint()
        SuuUI.Settings:Set(pluginId, key, {
            point    = point,
            relPoint = relPoint,
            x        = x,
            y        = y,
        })
    end)

    -- Respond to edit mode changes
    SuuUI.Events:On("SUUUI_EDIT_MODE_CHANGED", function(isEdit)
        if isEdit then
            overlay:Show()
        else
            overlay:Hide()
        end
    end, "moveable_" .. pluginId .. "_" .. key)

    -- Restore saved position (or apply defaults)
    M:RestorePosition(frame)

    -- Respond to profile changes
    SuuUI.Events:On("SUUUI_PROFILE_LOADED", function()
        M:RestorePosition(frame)
    end, "moveable_pos_" .. pluginId .. "_" .. key)
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

    SuuUI.Events:Off("SUUUI_EDIT_MODE_CHANGED", "moveable_" .. data.pluginId .. "_" .. data.key)
    SuuUI.Events:Off("SUUUI_PROFILE_LOADED", "moveable_pos_" .. data.pluginId .. "_" .. data.key)
    SuuUI.ToggleUI:Unregister(frame)

    data.overlay:Hide()
    data.overlay:SetScript("OnDragStart", nil)
    data.overlay:SetScript("OnDragStop", nil)

    frame._suuui_moveable = nil
end

SuuUI.MoveableFrame = M
