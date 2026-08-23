-- Dependency binding for settings controls.
--
-- Some settings only mean anything while another setting has a particular value: "hide the
-- level at max level" is not a decision to make when the level is not being shown at all,
-- and a cast bar's width is not editable while the bar takes its width from the frame it
-- is attached to. Such a control states its condition in the schema and is greyed out
-- while it is unmet:
--
--   { key = "player_hide_level_at_max", label = "Hide at Max Level", type = "toggle",
--     default = true, enabledIf = "player_show_level" }
--
--   { key = "player_width", label = "Width", type = "slider", default = 304,
--     enabledIf = { key = "player_anchor", equals = "detached" } }
--
-- Three forms, because truthiness alone cannot express the second case — and a control
-- that needs "enabled while the OTHER one is off" is otherwise forced to invert the
-- setting it depends on, which distorts the schema to suit the binder:
--
--   enabledIf = "key"                          the key is truthy
--   enabledIf = { key = "k", equals = v }       the key equals v (v may be false)
--   enabledIf = { key = "k", notEquals = v }    the key is anything but v
--
-- Greyed, not hidden, and never cleared: the stored value still applies the moment the
-- dependency comes back on, and a control that vanishes leaves the player unable to see
-- what it was set to.
--
-- On an entry carrying `owner` — one plugin's setting rendered on another's page — the
-- dependency key is read from the OWNER's namespace, because a condition and the value it
-- gates belong to the same store.
local ipairs, type = ipairs, type

local M = {}

-- Resolves a declaration into the key to watch plus the predicate that decides whether
-- the control is live. One place decides what each form means, so a new form cannot be
-- understood differently by two callers.
-- @return string|nil, function|nil
local function resolve(dep)
    if type(dep) == "string" and dep ~= "" then
        return dep, function(v) return v and true or false end
    end
    if type(dep) ~= "table" or type(dep.key) ~= "string" or dep.key == "" then
        return nil, nil
    end
    -- `~= nil` rather than truthiness: `equals = false` is the common case for a toggle
    -- dependency, and testing the value's truth here would silently drop it.
    if dep.equals ~= nil then
        local want = dep.equals
        return dep.key, function(v) return v == want end
    end
    if dep.notEquals ~= nil then
        local want = dep.notEquals
        return dep.key, function(v) return v ~= want end
    end
    return dep.key, function(v) return v and true or false end
end

--- Binds one or more handles' interactive state to another setting.
-- No-op unless entry.enabledIf is set, so every control can call it unconditionally.
--
-- The watcher is registered under the entry's OWN control owner, not the dependency's, so
-- Settings:UnwatchControls retires it together with the control's value watcher — a
-- dependency watcher left behind would call SetEnabled on a destroyed widget.
-- @param pluginId string
-- @param entry table   Schema entry
-- @param ... table     Handles exposing SetEnabled (control, label, ...)
function M.Bind(pluginId, entry, ...)
    if not entry.enabledIf then return end

    local key, test = resolve(entry.enabledIf)
    if not key then
        SuuUI.Debug("SettingsDeps: malformed enabledIf on " .. tostring(pluginId)
            .. "." .. tostring(entry.key))
        return
    end

    -- A foreign-owned entry's dependency lives beside its value, in the OWNER's namespace:
    -- both halves of "this control is only live while that one is on" have to be read from
    -- the same store, or a contributed control would gate on a key the page happens to
    -- share the name of. The watcher OWNER string stays derived from the PAGE's pluginId
    -- for the reason spelled out in Controls/Toggle.lua — it is what UnwatchPrefix and
    -- UnwatchControls match on, so keying it to the contributor leaks a watcher per rebuild.
    local dataId = entry.owner or pluginId

    local targets = { ... }
    SuuUI.Settings:Watch(dataId, key, function(value)
        local on = test(value)
        for _, target in ipairs(targets) do
            if target and target.SetEnabled then target:SetEnabled(on) end
        end
    end, SuuUI.Settings.ControlOwner(pluginId, entry.type, entry.key), { immediate = true })
end

SuuUI._SettingsDeps = M
