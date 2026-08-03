local pairs, assert, type, ipairs = pairs, assert, type, ipairs

local M = {}
local schemas = {}  -- [pluginId] = { schemaEntry, ... }

local function pluginProfile(pluginId)
    local profile = SuuUI.Profiles:GetActive()
    if not profile.plugins then profile.plugins = {} end
    if not profile.plugins[pluginId] then profile.plugins[pluginId] = {} end
    return profile.plugins[pluginId]
end

local function schemaEntry(pluginId, key)
    local schema = schemas[pluginId]
    if not schema then return nil end
    for _, entry in ipairs(schema) do
        if entry.key == key then return entry end
    end
end

--- Registers a settings schema for a plugin.
-- @param pluginId string
-- @param schemaArray table  Array of schema entry tables
function M:Register(pluginId, schemaArray)
    assert(type(pluginId) == "string", "SuuUI Settings: pluginId must be string")
    assert(not schemas[pluginId], "SuuUI Settings: schema already registered for " .. pluginId)
    schemas[pluginId] = schemaArray
end

--- Returns the schema array for a plugin.
-- @param pluginId string
-- @return table
function M:GetSchema(pluginId)
    return schemas[pluginId]
end

--- Returns the current value for a setting, falling back to schema default.
-- @param pluginId string
-- @param key string
-- @return any
function M:Get(pluginId, key)
    local store = pluginProfile(pluginId)
    if store[key] ~= nil then return store[key] end
    local entry = schemaEntry(pluginId, key)
    return entry and entry.default
end

--- Writes a setting value to the active profile and fires SUUUI_SETTING_CHANGED.
-- @param pluginId string
-- @param key string
-- @param value any
function M:Set(pluginId, key, value)
    local entry = schemaEntry(pluginId, key)
    if entry and entry.validate then
        local ok, err = entry.validate(value)
        if ok == false then
            SuuUI.Debug("Settings validate failed [" .. pluginId .. "." .. key .. "]: " .. tostring(err))
            return
        end
    end
    local store = pluginProfile(pluginId)
    local old = store[key]
    store[key] = value
    SuuUI.Events:Emit("SUUUI_SETTING_CHANGED", pluginId, key, value, old)
end

--- Resets a single setting to its schema default.
-- @param pluginId string
-- @param key string
function M:Reset(pluginId, key)
    local entry = schemaEntry(pluginId, key)
    if not entry then return end
    self:Set(pluginId, key, entry.default)
end

--- Resets all settings for a plugin to their schema defaults.
-- @param pluginId string
function M:ResetAll(pluginId)
    local schema = schemas[pluginId]
    if not schema then return end
    for _, entry in ipairs(schema) do
        if entry.key and entry.key ~= "" then
            self:Set(pluginId, entry.key, entry.default)
        end
    end
end

SuuUI.Settings = M
