-- Dependency binding for settings controls.
--
-- Some settings only mean anything while another setting is on: "hide the level at max
-- level" is not a decision to make when the level is not being shown at all. Such a
-- control states its condition in the schema and is greyed out while it is unmet:
--
--   { key = "player_hide_level_at_max", label = "Hide at Max Level", type = "toggle",
--     default = true, enabledIf = "player_show_level" }
--
-- Greyed, not hidden, and never cleared: the stored value still applies the moment the
-- dependency comes back on, and a control that vanishes leaves the player unable to see
-- what it was set to.
local ipairs = ipairs

local M = {}

--- Binds one or more handles' interactive state to another setting's truthiness.
-- No-op unless entry.enabledIf is set, so every control can call it unconditionally.
--
-- The watcher is registered under the entry's OWN control owner, not the dependency's, so
-- Settings:UnwatchControls retires it together with the control's value watcher — a
-- dependency watcher left behind would call SetEnabled on a destroyed widget.
-- @param pluginId string
-- @param entry table   Schema entry
-- @param ... table     Handles exposing SetEnabled (control, label, ...)
function M.Bind(pluginId, entry, ...)
    local dep = entry.enabledIf
    if not dep then return end

    local targets = { ... }
    SuuUI.Settings:Watch(pluginId, dep, function(value)
        local on = value and true or false
        for _, target in ipairs(targets) do
            if target and target.SetEnabled then target:SetEnabled(on) end
        end
    end, SuuUI.Settings.ControlOwner(pluginId, entry.type, entry.key), { immediate = true })
end

SuuUI._SettingsDeps = M
