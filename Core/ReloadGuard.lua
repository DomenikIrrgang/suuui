-- Core/ReloadGuard.lua
--
-- Generic utility for settings that require a UI reload to take effect.
-- When a guarded setting is changed via Settings:Set, a confirmation modal
-- appears. On confirm the setting is written and ReloadUI() fires. On cancel
-- the setting reverts to its previous value silently.
--
-- Usage in a plugin's onInit:
--
--   SuuUI.ReloadGuard:Register("my_plugin", "player_enabled", {
--       title   = "Reload Required",
--       message = "Disabling the player frame requires a UI reload. Reload now?",
--   })
--
-- The guard intercepts the SUUUI_SETTING_CHANGED event for that key and shows
-- the modal before the rest of the system reacts.

local M = {}
local guards = {}  -- [pluginId][key] = { title, message, ... }

--- Registers a setting key as requiring a reload confirmation.
-- @param pluginId string
-- @param key string
-- @param opts table  { title, message, confirmText, cancelText }
function M:Register(pluginId, key, opts)
    opts = opts or {}
    if not guards[pluginId] then guards[pluginId] = {} end
    guards[pluginId][key] = {
        title       = opts.title or "Reload Required",
        message     = opts.message or "This change requires a UI reload to take effect. Reload now?",
        confirmText = opts.confirmText or "Reload",
        cancelText  = opts.cancelText or "Cancel",
        _blocked    = false,
    }
end

--- Returns whether a setting key is guarded.
-- @param pluginId string
-- @param key string
-- @return bool
function M:IsGuarded(pluginId, key)
    return guards[pluginId] and guards[pluginId][key] ~= nil
end

--- Removes a guard registration.
-- @param pluginId string
-- @param key string
function M:Unregister(pluginId, key)
    if guards[pluginId] then guards[pluginId][key] = nil end
end

-- Internal: intercept setting changes for guarded keys.
-- The flow:
--   1. User changes a guarded setting via the toggle
--   2. Settings:Set fires SUUUI_SETTING_CHANGED
--   3. This listener catches it, reverts the value immediately (silently),
--      and shows the confirmation modal
--   4. On confirm: re-apply the value (blocked so we don't recurse) then ReloadUI()
--   5. On cancel: value stays reverted, nothing happens
SuuUI.Events:On("SUUUI_SETTING_CHANGED", function(pluginId, key, newValue, oldValue)
    if not guards[pluginId] then return end
    local guard = guards[pluginId][key]
    if not guard then return end

    -- If we are in a "blocked" state, this is our own re-application — let it through
    if guard._blocked then return end

    -- Revert the setting silently (mark blocked so we don't recurse)
    guard._blocked = true
    SuuUI.Settings:Set(pluginId, key, oldValue)
    guard._blocked = false

    -- Show the confirmation modal (components are loaded by runtime)
    local modal = SuuUI.Components.Modal({
        title          = guard.title,
        message        = guard.message,
        confirmText    = guard.confirmText,
        cancelText     = guard.cancelText,
        confirmVariant = "warning",
        autoDestroy    = true,
        onConfirm = function()
            -- Apply the setting for real (blocked so our listener ignores it)
            guard._blocked = true
            SuuUI.Settings:Set(pluginId, key, newValue)
            guard._blocked = false
            -- Reload the UI
            ReloadUI()
        end,
        onCancel = function()
            -- Nothing to do — value was already reverted
        end,
    })
    modal:Show()
end, "_reload_guard")

SuuUI.ReloadGuard = M
