local pairs, assert, type, ipairs, tostring = pairs, assert, type, ipairs, tostring
local tinsert, tremove = table.insert, table.remove

local M = {}
local schemas        = {}  -- [pluginId] = { schemaEntry, ... }
local entryIndex     = {}  -- [pluginId][key] = schemaEntry
local transientKeys  = {}  -- [pluginId][key] = true    session state, never persisted
local transientStore = {}  -- [pluginId][key] = value   lives for one UI session
local watchers       = {}  -- [bucketKey] = { { cb, owner, pluginId, key }, ... }
local watcherCount   = 0

-- Watchers are bucketed by pluginId+key so a write notifies only its own subscribers.
-- A flat list would make every Set a full scan, and this system backs every frame in
-- every unit-frame group, not just the settings panel.
local function bucketKey(pluginId, key)
    return tostring(pluginId) .. "\0" .. tostring(key)
end

local MAX_EQ_DEPTH = 4

--- Value equality that treats tables structurally.
-- Positions and colours are stored as fresh tables on every write, so reference
-- equality would report every save as a change and echo it back to the writer.
local function valuesEqual(a, b, depth)
    if a == b then return true end
    -- NaN is the one value that is not equal to itself, so a NaN setting would read as
    -- "changed" on every write and re-notify every watcher forever. Two NaNs are the same
    -- setting as far as this guard is concerned.
    if a ~= a and b ~= b then return true end
    if type(a) ~= "table" or type(b) ~= "table" then return false end
    depth = (depth or 0) + 1
    if depth > MAX_EQ_DEPTH then return false end
    for k, v in pairs(a) do
        if not valuesEqual(v, b[k], depth) then return false end
    end
    for k in pairs(b) do
        if a[k] == nil then return false end
    end
    return true
end

local function isTransient(pluginId, key)
    local keys = transientKeys[pluginId]
    return keys ~= nil and keys[key] == true
end

--- Returns the table a key's value is stored in.
-- Transient keys resolve to a session table that is never written to SavedVariables;
-- everything else resolves to the active profile.
local function storeFor(pluginId, key)
    if isTransient(pluginId, key) then
        if not transientStore[pluginId] then transientStore[pluginId] = {} end
        return transientStore[pluginId]
    end
    local profile = SuuUI.Profiles:GetActive()
    if not profile.plugins then profile.plugins = {} end
    if not profile.plugins[pluginId] then profile.plugins[pluginId] = {} end
    return profile.plugins[pluginId]
end

local function defaultFor(pluginId, key)
    local idx = entryIndex[pluginId]
    local entry = idx and idx[key]
    return entry and entry.default
end

--- The value a reader would see for a candidate write.
-- Writing nil clears the stored value, which means the schema default becomes
-- visible again — so nil must be resolved before anything is told a value changed.
local function effectiveOf(pluginId, key, value)
    if value ~= nil then return value end
    return defaultFor(pluginId, key)
end

--- Notifies watchers of a key with the effective value.
-- Iterates a snapshot: a callback may Watch or Unwatch while it runs (rebuilding a
-- settings page does exactly that), and mutating the live list under iteration
-- silently skips subscribers.
local function notifyWatchers(pluginId, key, value)
    local list = watchers[bucketKey(pluginId, key)]
    if not list or #list == 0 then return end
    local snapshot = {}
    for i = 1, #list do snapshot[i] = list[i] end
    for i = 1, #snapshot do
        local w = snapshot[i]
        if not w._dead then
            local ok, err = pcall(w.cb, value)
            if not ok then
                SuuUI.Debug("Settings:Watch callback error [" .. tostring(pluginId)
                    .. "." .. tostring(key) .. "]: " .. tostring(err))
            end
        end
    end
end

local MAX_SCHEMA_DEPTH = 6

--- Calls fn(entry) for every entry in a schema, descending into grouped entries.
-- A grouping control (subtabs) carries its children in `tabs[i].schema`, and those
-- children are real settings: they must be indexed, reset and torn down exactly like a
-- top-level entry, or a setting would only work when it happens to be declared flat.
-- Declaring a key once, in the group it is rendered in, is the point.
-- @param schemaArray table
-- @param fn function(entry)
-- @param depth number|nil
local function eachEntry(schemaArray, fn, depth)
    depth = (depth or 0) + 1
    if depth > MAX_SCHEMA_DEPTH or type(schemaArray) ~= "table" then return end
    for _, entry in ipairs(schemaArray) do
        fn(entry)
        if type(entry.tabs) == "table" then
            for _, tab in ipairs(entry.tabs) do
                eachEntry(tab.schema, fn, depth)
            end
        end
    end
end

--- Registers a settings schema for a plugin.
-- @param pluginId string
-- @param schemaArray table  Array of schema entry tables
function M:Register(pluginId, schemaArray)
    assert(type(pluginId) == "string", "SuuUI Settings: pluginId must be string")
    assert(not schemas[pluginId], "SuuUI Settings: schema already registered for " .. pluginId)
    schemas[pluginId] = schemaArray

    local idx, trans = {}, {}
    eachEntry(schemaArray, function(entry)
        local key = entry.key
        if not key or key == "" then return end
        local existing = idx[key]
        if existing and existing ~= entry then
            -- Two declarations of one key is a drift bug waiting to happen: the reader
            -- would take its default from one and its range from the other. Name it.
            if existing.default ~= nil and entry.default ~= nil
               and not valuesEqual(existing.default, entry.default) then
                SuuUI.Debug("Settings: conflicting defaults declared for "
                    .. pluginId .. "." .. key)
            end
            if existing.default == nil and entry.default ~= nil then idx[key] = entry end
        else
            idx[key] = entry
        end
        if entry.transient then trans[key] = true end
    end)
    entryIndex[pluginId]    = idx
    transientKeys[pluginId] = trans
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
    local store = storeFor(pluginId, key)
    if store[key] ~= nil then return store[key] end
    return defaultFor(pluginId, key)
end

--- Returns whether a key is session state rather than profile state.
-- @param pluginId string
-- @param key string
-- @return bool
function M:IsTransient(pluginId, key)
    return isTransient(pluginId, key)
end

--- Writes a setting value, notifies watchers, then fires SUUUI_SETTING_CHANGED.
--
-- Both the watcher payload and the event carry EFFECTIVE values — the value a
-- reader would get from Get — never the raw stored value. A key that has never
-- been written stores nil while reading as its schema default, so handing out the
-- raw value tells subscribers the setting is nil when it is not.
--
-- A write that does not change the effective value is dropped: no store write, no
-- watcher call, no event.
-- @param pluginId string
-- @param key string
-- @param value any
function M:Set(pluginId, key, value)
    local idx = entryIndex[pluginId]
    local entry = idx and idx[key]
    if entry and entry.validate then
        local ok, err = entry.validate(value)
        if ok == false then
            SuuUI.Debug("Settings validate failed [" .. pluginId .. "." .. key .. "]: " .. tostring(err))
            return
        end
    end

    local oldEffective = self:Get(pluginId, key)
    local newEffective = effectiveOf(pluginId, key, value)
    if valuesEqual(oldEffective, newEffective) then return end

    storeFor(pluginId, key)[key] = value
    notifyWatchers(pluginId, key, newEffective)
    SuuUI.Events:Emit("SUUUI_SETTING_CHANGED", pluginId, key, newEffective, oldEffective)
end

--- Subscribes to changes of one pluginId + key.
--
-- The callback receives the effective value. It fires when Set changes the value and
-- on profile switches, so a bound widget cannot drift from the store regardless of
-- what caused the change.
--
-- @param pluginId string
-- @param key string
-- @param cb function(value)
-- @param owner string   Handle for Unwatch / UnwatchPrefix. Required.
-- @param opts table     { immediate = true } fires cb once now with the current value
function M:Watch(pluginId, key, cb, owner, opts)
    assert(type(cb) == "function", "Settings:Watch cb must be a function")
    assert(type(owner) == "string" and owner ~= "", "Settings:Watch owner must be a non-empty string")

    local bk = bucketKey(pluginId, key)
    if not watchers[bk] then watchers[bk] = {} end
    tinsert(watchers[bk], { cb = cb, owner = owner, pluginId = pluginId, key = key })
    watcherCount = watcherCount + 1

    if opts and opts.immediate then
        local ok, err = pcall(cb, self:Get(pluginId, key))
        if not ok then
            SuuUI.Debug("Settings:Watch immediate error [" .. tostring(pluginId)
                .. "." .. tostring(key) .. "]: " .. tostring(err))
        end
    end
end

local function dropWatchers(match)
    local removed = 0
    for bk, list in pairs(watchers) do
        for i = #list, 1, -1 do
            if match(list[i].owner) then
                -- Marked as well as removed: a notify snapshot taken before this call
                -- must not deliver to a subscriber that has since been torn down.
                list[i]._dead = true
                tremove(list, i)
                removed = removed + 1
            end
        end
        if #list == 0 then watchers[bk] = nil end
    end
    watcherCount = watcherCount - removed
    return removed
end

--- Unsubscribes every watcher registered under an exact owner.
-- @param owner string
-- @return number  How many were removed
function M:Unwatch(owner)
    if type(owner) ~= "string" then return 0 end
    return dropWatchers(function(o) return o == owner end)
end

--- Unsubscribes every watcher whose owner starts with a prefix.
-- Lets a surface that built many watchers drop them all without tracking each one.
-- @param prefix string
-- @return number  How many were removed
function M:UnwatchPrefix(prefix)
    if type(prefix) ~= "string" or prefix == "" then return 0 end
    local n = #prefix
    return dropWatchers(function(o) return o:sub(1, n) == prefix end)
end

--- Owner prefix shared by every control on one plugin's settings page.
-- @param pluginId string
-- @return string
function M.ControlOwnerPrefix(pluginId)
    return "page:" .. tostring(pluginId) .. ":"
end

--- Owner string for a single settings-page control.
-- @param pluginId string
-- @param kind string  Control type, e.g. "toggle"
-- @param key string
-- @return string
function M.ControlOwner(pluginId, kind, key)
    return M.ControlOwnerPrefix(pluginId) .. tostring(kind) .. ":" .. tostring(key)
end

--- Drops the watchers that the controls for a slice of schema registered.
--
-- Every control file subscribes under `ControlOwner(pluginId, entry.type, entry.key)`,
-- so the owner string is derivable from the schema alone. That lets a surface which
-- built *part* of a page (one subtab) retire exactly its own subscriptions without
-- tracking each one — an owner prefix cannot do this, because the controls are not
-- registered under a prefix that says which group they came from.
--
-- Without this, swapping a group's contents leaves a watcher bound to a destroyed
-- widget; the next write, and every profile load, then calls into it.
-- @param pluginId string
-- @param schemaArray table  The entries whose controls are going away
-- @return number  How many watchers were removed
function M:UnwatchControls(pluginId, schemaArray)
    local removed = 0
    eachEntry(schemaArray, function(entry)
        if entry.key and entry.key ~= "" and entry.type then
            removed = removed + self:Unwatch(M.ControlOwner(pluginId, entry.type, entry.key))
        end
    end)
    return removed
end

--- Returns the live watcher count. Used by tests to catch subscription leaks.
-- @return number
function M:GetWatcherCount()
    return watcherCount
end

--- Resets a single setting to its schema default.
-- @param pluginId string
-- @param key string
function M:Reset(pluginId, key)
    local idx = entryIndex[pluginId]
    local entry = idx and idx[key]
    if not entry then return end
    self:Set(pluginId, key, entry.default)
end

--- Resets all settings for a plugin to their schema defaults.
-- Descends into grouped entries, so a setting declared inside a subtab resets like any
-- other rather than being silently skipped.
-- @param pluginId string
function M:ResetAll(pluginId)
    local schema = schemas[pluginId]
    if not schema then return end
    eachEntry(schema, function(entry)
        if entry.key and entry.key ~= "" then
            self:Set(pluginId, entry.key, entry.default)
        end
    end)
end

SuuUI.Settings = M

-- A profile switch changes every persisted value at once, so watchers are re-notified
-- centrally rather than each subscriber listening for the profile event itself.
-- Transient keys are session state and are deliberately left alone.
SuuUI.Events:On("SUUUI_PROFILE_LOADED", function()
    for _, list in pairs(watchers) do
        local snapshot = {}
        for i = 1, #list do snapshot[i] = list[i] end
        for i = 1, #snapshot do
            local w = snapshot[i]
            if not w._dead and not isTransient(w.pluginId, w.key) then
                local ok, err = pcall(w.cb, M:Get(w.pluginId, w.key))
                if not ok then
                    SuuUI.Debug("Settings:Watch profile-reload error ["
                        .. tostring(w.pluginId) .. "." .. tostring(w.key) .. "]: " .. tostring(err))
                end
            end
        end
    end
end, "_settings_watch_profile")
