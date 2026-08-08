-- ToggleUI: central edit-mode manager for repositioning SuuUI frames.
-- Provides a registry for moveable frames and the toggle/lock/unlock commands.
--
-- State: the authoritative edit-mode value is Settings("_layout", "edit_mode"), a
-- transient (non-persisted) key. There is NO local shadow variable — reads go through
-- Settings:Get, writes through Settings:Set, and subscribers use Settings:Watch, so
-- the slash command, the settings toggle and every overlay cannot disagree.
local pairs = pairs

local M = {}
local registry = {}  -- [frame] = true

--- Returns whether edit mode is currently active.
-- @return bool
function M:IsEditMode()
    return SuuUI.Settings:Get("_layout", "edit_mode") or false
end

--- Toggles edit mode on/off.
function M:Toggle()
    SuuUI.Settings:Set("_layout", "edit_mode", not self:IsEditMode())
end

--- Enables edit mode explicitly.
function M:Enable()
    SuuUI.Settings:Set("_layout", "edit_mode", true)
end

--- Disables edit mode explicitly.
function M:Disable()
    SuuUI.Settings:Set("_layout", "edit_mode", false)
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
--
-- edit_mode is `transient`: session state, never written to SavedVariables. Edit mode
-- is a mode the player is currently in, not a preference — persisting it would log
-- them back in with every frame draggable, and a profile switch would silently
-- enter or leave it.
SuuUI.Settings:Register("_layout", {
    { key = "",          label = "Edit Mode",        type = "section" },
    { key = "edit_mode", label = "Toggle Edit Mode", type = "toggle", default = false,
      transient = true },
})

-- Deprecated. SUUUI_EDIT_MODE_CHANGED was the public edit-mode event before edit mode
-- became a watched setting, and third-party plugins may still listen for it. New code
-- should watch the setting instead:
--   SuuUI.Settings:Watch("_layout", "edit_mode", cb, owner, { immediate = true })
SuuUI.Settings:Watch("_layout", "edit_mode", function(isEdit)
    SuuUI.Events:Emit("SUUUI_EDIT_MODE_CHANGED", isEdit and true or false)
end, "_toggleui_deprecated_event")
