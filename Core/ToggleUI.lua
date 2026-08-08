-- ToggleUI: central edit-mode manager for repositioning SuuUI frames.
-- Provides a registry for moveable frames, a toggle command, and events.
local pairs = pairs

local M = {}
local registry = {}  -- [frame] = true
local editMode = false

--- Returns whether edit mode is currently active.
-- @return bool
function M:IsEditMode()
    return editMode
end

--- Toggles edit mode on/off, notifying all registered frames.
function M:Toggle()
    editMode = not editMode
    SuuUI.Events:Emit("SUUUI_EDIT_MODE_CHANGED", editMode)
end

--- Enables edit mode explicitly.
function M:Enable()
    if editMode then return end
    editMode = true
    SuuUI.Events:Emit("SUUUI_EDIT_MODE_CHANGED", true)
end

--- Disables edit mode explicitly.
function M:Disable()
    if not editMode then return end
    editMode = false
    SuuUI.Events:Emit("SUUUI_EDIT_MODE_CHANGED", false)
end

--- Registers a frame with the toggle UI system.
-- @param frame table  The WoW frame to track
function M:Register(frame)
    registry[frame] = true
end

--- Unregisters a frame from the toggle UI system.
-- @param frame table  The WoW frame to remove
function M:Unregister(frame)
    registry[frame] = nil
end

--- Returns all registered frames.
-- @return table
function M:GetAll()
    local list = {}
    for frame in pairs(registry) do
        list[#list + 1] = frame
    end
    return list
end

SuuUI.ToggleUI = M

-- Register the layout settings schema so the toggle is available in the settings panel
-- and position data can be reset from the UI.
SuuUI.Settings:Register("_layout", {
    { key = "",          label = "Edit Mode",        type = "section" },
    { key = "edit_mode", label = "Toggle Edit Mode", type = "toggle", default = false },
})

-- Sync: when the _layout.edit_mode setting is changed (from the settings panel),
-- update the ToggleUI state to match.
SuuUI.Events:On("SUUUI_SETTING_CHANGED", function(pluginId, key, value)
    if pluginId == "_layout" and key == "edit_mode" then
        if value and not editMode then
            editMode = true
            SuuUI.Events:Emit("SUUUI_EDIT_MODE_CHANGED", true)
        elseif not value and editMode then
            editMode = false
            SuuUI.Events:Emit("SUUUI_EDIT_MODE_CHANGED", false)
        end
    end
end, "_toggleui_settings_sync")

-- Sync: when edit mode is toggled via slash command or API, update the setting.
SuuUI.Events:On("SUUUI_EDIT_MODE_CHANGED", function(isEdit)
    -- Only update if the setting differs to avoid infinite loop
    local current = SuuUI.Settings:Get("_layout", "edit_mode")
    if current ~= isEdit then
        SuuUI.Settings:Set("_layout", "edit_mode", isEdit)
    end
end, "_toggleui_setting_write")
