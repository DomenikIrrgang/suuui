local C = SuuUI.Components
local S = SuuUI.UISignals

--- Builds a dropdown control row.
-- @param entry table    Schema entry { key, label, options, default, owner }
--   options: an array, OR a function returning one. The function form is resolved HERE, when the
--   panel is built, which is the whole reason it exists: an option set spanning plugins cannot be
--   frozen at schema-registration time, because whether the other plugin has registered yet depends
--   on load order. Docking uses it -- a bar's "Attach To" list has to include participants from
--   plugins that register after this one.
-- @param pluginId string
-- @param parent frame
-- @return table  Row container handle
local function Build(entry, pluginId, parent)
    local row, label = SuuUI._SettingsRow.Labelled(parent, entry.label)
    -- Data namespace only; the watcher owner stays the page's. See Controls/Toggle.lua.
    local dataId = entry.owner or pluginId

    local options = entry.options
    if type(options) == "function" then
        -- pcall'd because this now runs third-party-ish code during panel construction, and a bad
        -- provider must cost one empty dropdown rather than the whole settings page.
        local ok, resolved = pcall(options)
        options = (ok and type(resolved) == "table") and resolved or {}
        if not ok then
            SuuUI.Fault("Settings: options provider for '" .. tostring(entry.key) .. "' errored")
        end
    end

    local dd = C.Dropdown({
        options = options or {},
        w       = 140,
    }, row:GetFrame())
    -- Height omitted: the dropdown derives it from its size and font tokens
    row:Add(dd, { width = 140 })

    S:Connect(dd, S.SIGNALS.VALUE_CHANGED, function(val)
        SuuUI.Settings:Set(dataId, entry.key, val)
    end)

    SuuUI.Settings:Watch(dataId, entry.key, function(val)
        dd:SetValue(val)
    end, SuuUI.Settings.ControlOwner(pluginId, "dropdown", entry.key), { immediate = true })

    -- Greys the row out while a setting it depends on is off. No-op without enabledIf.
    -- The label is a sibling in the row, not a child of the control, so it has to be
    -- passed explicitly or half the row keeps looking live.
    SuuUI._SettingsDeps.Bind(pluginId, entry, dd, label)

    return row
end

if not SuuUI._SettingsControls then SuuUI._SettingsControls = {} end
SuuUI._SettingsControls["dropdown"] = Build
