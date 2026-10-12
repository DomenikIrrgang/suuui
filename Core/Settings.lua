-- Core/Settings.lua
-- Settings and profiles, saved account-wide in SuuUIDB.
--
-- Each module registers a namespace with its defaults. A profile stores only
-- the values that differ from the defaults, so a changed default reaches every
-- profile that never touched it. Each character uses its own profile ("Name -
-- Realm") unless it switched to another.
--
--   Settings.Register(namespace, defaults)
--   Settings.Get(namespace, key)            a copy for table values
--   Settings.Set(namespace, key, value)     -> true, or false and the veto's reason
--   Settings.Reset([namespace[, key]])
--   Settings.Watch(namespace, key, fn, owner)   fn(value, namespace, key) after a change
--   Settings.Veto(namespace, key, fn, owner)    fn(new, old) -> false, reason refuses it
--   Settings.Unwatch(owner)
--   Settings.Migrate(namespace, id, fn, owner)  fn(values) reshapes a profile's stored values once
--
-- A watcher may change the setting it is told about (clamping, reverting).
-- That newer write notifies every watcher itself, and the outer notification
-- stops, so no watcher ever hears a superseded value.

local ADDON, ns = ...

local Settings, Profiles = {}, {}
ns.Settings, ns.Profiles = Settings, Profiles

local Util, Fault, Events = ns.Util, ns.Fault, ns.Events
local Copy, Equal, OwnerName = Util.Copy, Util.Equal, Util.OwnerName

local defaults = {}    -- namespace -> { key -> default }
local watchers = {}    -- "namespace.key" -> { { fn, owner }, ... }
local vetoes = {}      -- "namespace.key" -> { { fn, owner }, ... }
local generation = {}  -- "namespace.key" -> write count
local migrations = {}  -- { namespace, id, fn, owner }, in the order they were registered

-- In each profile, the migrations it has had: "namespace/id" -> true. Not a
-- namespace any module can have (ids start with a letter), so it is never a
-- setting, and it travels with the profile's data (copies, exports).
local MIGRATED = "__migrated"

local db, profile, charKey -- bound when SuuUIDB has loaded

--------------------------------------------------------------------------------
-- Registry
--------------------------------------------------------------------------------

function Settings.Register(namespace, defs)
    assert(type(namespace) == "string", "SuuUI Settings: the namespace must be a string")
    assert(not defaults[namespace], "SuuUI Settings: namespace " .. namespace .. " is already registered")
    for k, v in pairs(defs) do
        assert(type(k) == "string" and v ~= nil, "SuuUI Settings: defaults need string keys and non-nil values")
    end
    defaults[namespace] = Copy(defs)
end

local function default(namespace, key)
    local d = defaults[namespace]
    if not d then error(("SuuUI Settings: unknown namespace %q"):format(tostring(namespace)), 3) end
    local v = d[key]
    if v == nil then error(("SuuUI Settings: %s has no setting %q"):format(namespace, tostring(key)), 3) end
    return v
end

local function stored(p, namespace, key)
    local t = p and p[namespace]
    if t then return t[key] end
end

-- A stored value of another type than the default's (an old or hand-edited
-- profile) is ignored, so the default applies.
local function current(namespace, key)
    local d = default(namespace, key)
    local v = stored(profile, namespace, key)
    if v == nil or type(v) ~= type(d) then return d end
    return v
end

function Settings.Ready()
    return profile ~= nil
end

function Settings.Get(namespace, key)
    return Copy(current(namespace, key))
end

function Settings.IsDefault(namespace, key)
    local d = default(namespace, key)
    local v = stored(profile, namespace, key)
    return v == nil or type(v) ~= type(d)
end

-- Registered namespaces and their keys, sorted, for listings.
function Settings.List()
    local out = {}
    for _, namespace in ipairs(Util.SortedKeys(defaults)) do
        out[#out + 1] = { namespace = namespace, keys = Util.SortedKeys(defaults[namespace]) }
    end
    return out
end

--------------------------------------------------------------------------------
-- Watchers and vetoes
--------------------------------------------------------------------------------

local function addTo(map, namespace, key, fn, owner)
    default(namespace, key)
    assert(type(fn) == "function" and owner ~= nil, "SuuUI Settings: a function and an owner are required")
    local id = namespace .. "." .. key
    map[id] = map[id] or {}
    table.insert(map[id], { fn = fn, owner = owner })
end

function Settings.Watch(namespace, key, fn, owner)
    addTo(watchers, namespace, key, fn, owner)
end

function Settings.Veto(namespace, key, fn, owner)
    addTo(vetoes, namespace, key, fn, owner)
end

function Settings.Unwatch(owner)
    for _, map in ipairs({ watchers, vetoes }) do
        for id, list in pairs(map) do
            for i = #list, 1, -1 do
                if list[i].owner == owner then
                    list[i].dead = true
                    table.remove(list, i)
                end
            end
            if #list == 0 then map[id] = nil end
        end
    end
end

local function notify(namespace, key)
    local id = namespace .. "." .. key
    local gen = (generation[id] or 0) + 1
    generation[id] = gen
    local list = watchers[id]
    if list then
        local snapshot = { unpack(list) }
        for _, w in ipairs(snapshot) do
            if generation[id] ~= gen then return end -- superseded by a watcher's own write
            if not w.dead then
                Fault.Call(OwnerName(w.owner), w.fn, Settings.Get(namespace, key), namespace, key)
            end
        end
    end
    if generation[id] == gen then
        Events.Emit("SUUUI_SETTING_CHANGED", namespace, key)
    end
end

--------------------------------------------------------------------------------
-- Writing
--------------------------------------------------------------------------------

local function write(namespace, key, value)
    if Equal(value, defaults[namespace][key]) then
        local t = profile[namespace]
        if t then
            t[key] = nil
            if next(t) == nil then profile[namespace] = nil end
        end
    else
        profile[namespace] = profile[namespace] or {}
        profile[namespace][key] = Copy(value)
    end
end

function Settings.Set(namespace, key, value)
    local d = default(namespace, key)
    if type(value) ~= type(d) then
        error(("SuuUI Settings: %s.%s takes a %s, not a %s"):format(namespace, key, type(d), type(value)), 2)
    end
    assert(profile, "SuuUI Settings: saved settings have not loaded yet")
    local old = current(namespace, key)
    if Equal(old, value) then return true end

    local list = vetoes[namespace .. "." .. key]
    if list then
        for _, v in ipairs({ unpack(list) }) do
            local ok, allowed, reason = Fault.Call(OwnerName(v.owner), v.fn, Copy(value), Copy(old))
            if ok and allowed == false then return false, reason end
        end
    end

    write(namespace, key, value)
    notify(namespace, key)
    return true
end

-- Resets one setting, a namespace, or (no arguments) everything in this profile.
function Settings.Reset(namespace, key)
    if namespace and key then
        return Settings.Set(namespace, key, Copy(default(namespace, key)))
    end
    local namespaces = namespace and { namespace } or Util.SortedKeys(defaults)
    for _, n in ipairs(namespaces) do
        if not defaults[n] then error(("SuuUI Settings: unknown namespace %q"):format(n), 2) end
        for _, k in ipairs(Util.SortedKeys(defaults[n])) do
            Settings.Set(n, k, Copy(defaults[n][k]))
        end
    end
    return true
end

--------------------------------------------------------------------------------
-- Profiles
--------------------------------------------------------------------------------

-- Drops the values in profile data `p` that a veto refuses (judged against
-- the default), so the default applies to them: a profile from an import,
-- an older SuuUI or a hand edit can't bring in a value a Set would refuse.
local function screen(p)
    for id, list in pairs(vetoes) do
        local namespace, key = id:match("^([^%.]+)%.(.+)$")
        local v, d = stored(p, namespace, key), defaults[namespace][key]
        if v ~= nil and type(v) == type(d) then
            for _, veto in ipairs({ unpack(list) }) do
                local ok, allowed = Fault.Call(OwnerName(veto.owner), veto.fn, Copy(v), Copy(d))
                if ok and allowed == false then
                    p[namespace][key] = nil
                    if next(p[namespace]) == nil then p[namespace] = nil end
                    break
                end
            end
        end
    end
end

--------------------------------------------------------------------------------
-- Migrations: a module renames a key or changes a value's type, and its
-- migration brings each profile's stored values into the new shape, once.
-- They run before screening and the type check, which would drop an old
-- value as the wrong type.
--------------------------------------------------------------------------------

-- Runs one migration on profile data `p` unless it has had it. `fn` sees the
-- namespace's stored values only when there are some; a profile without any
-- has nothing to migrate and counts as done. A migration that errors isn't
-- marked done, so a fixed one runs at the next load.
local function runMigration(p, m)
    local tag = m.namespace .. "/" .. m.id
    local done = p[MIGRATED]
    if type(done) == "table" and done[tag] then return end
    local values = p[m.namespace]
    if type(values) == "table" then
        if not Fault.Call(m.owner, m.fn, values) then return end
        -- what the migration left at its default isn't stored
        local defs = defaults[m.namespace]
        for k, v in pairs(values) do
            if defs[k] ~= nil and Equal(v, defs[k]) then values[k] = nil end
        end
        if next(values) == nil then p[m.namespace] = nil end
    end
    if type(p[MIGRATED]) ~= "table" then p[MIGRATED] = {} end
    p[MIGRATED][tag] = true
end

-- Every migration profile data `p` hasn't had yet, in the order they came.
local function migrate(p)
    for _, m in ipairs(migrations) do runMigration(p, m) end
end

function Settings.Migrate(namespace, id, fn, owner)
    if not defaults[namespace] then error(("SuuUI Settings: unknown namespace %q"):format(tostring(namespace)), 2) end
    assert(type(id) == "string" and id ~= "" and type(fn) == "function", "SuuUI Settings: a migration needs an id and a function")
    for _, m in ipairs(migrations) do
        assert(not (m.namespace == namespace and m.id == id), "SuuUI Settings: migration " .. namespace .. "/" .. id .. " is already registered")
    end
    local m = { namespace = namespace, id = id, fn = fn, owner = OwnerName(owner or namespace) }
    migrations[#migrations + 1] = m
    if not db then return end -- bind runs it on every profile
    -- Registered after the profiles loaded (a plugin's file): every profile
    -- now, and the watchers hear what changed in the current one.
    local before = Copy(profile[namespace])
    for _, p in pairs(db.profiles) do
        if type(p) == "table" then runMigration(p, m) end
    end
    screen(profile)
    for key in pairs(defaults[namespace]) do
        if not Equal(before and before[key], stored(profile, namespace, key)) then notify(namespace, key) end
    end
end

function Profiles.Current()
    return db and db.chars[charKey]
end

function Profiles.List()
    return db and Util.SortedKeys(db.profiles) or {}
end

-- The profile `text` names: its exact name, the same name in any letter case,
-- or the start of exactly one name. Returns the name, or nil and why not.
function Profiles.Find(text)
    text = strtrim(text or "")
    if db.profiles[text] then return text end
    local lower, exact, starts = text:lower(), nil, {}
    for name in pairs(db.profiles) do
        local l = name:lower()
        if l == lower then exact = name end
        if text ~= "" and l:sub(1, #lower) == lower then starts[#starts + 1] = name end
    end
    if exact then return exact end
    if #starts == 1 then return starts[1] end
    table.sort(starts)
    if #starts > 1 then
        return nil, ("\"%s\" could mean %s."):format(text, table.concat(starts, " or "))
    end
    return nil, ("There is no profile called \"%s\". Profiles: %s."):format(text, table.concat(Profiles.List(), ", "))
end

-- Switches this character to another profile and tells the watchers of every
-- registered setting whose value differs.
function Profiles.Use(text)
    local name, err = Profiles.Find(text)
    if not name then return false, err end
    if name == Profiles.Current() then return true end
    local target, changed = db.profiles[name], {}
    migrate(target)
    screen(target)
    for namespace, defs in pairs(defaults) do
        for key in pairs(defs) do
            if not Equal(stored(profile, namespace, key), stored(target, namespace, key)) then
                changed[#changed + 1] = { namespace, key }
            end
        end
    end
    db.chars[charKey] = name
    profile = target
    for _, c in ipairs(changed) do notify(c[1], c[2]) end
    Events.Emit("SUUUI_PROFILE_CHANGED", name)
    return true
end

-- A new profile, copied from `from` (default: the current one).
function Profiles.Create(name, from)
    name = strtrim(name or "")
    if name == "" then return false, "A profile needs a name." end
    for existing in pairs(db.profiles) do
        if existing:lower() == name:lower() then
            return false, "A profile called " .. existing .. " already exists."
        end
    end
    local source = Profiles.Current()
    if from then
        local err
        source, err = Profiles.Find(from)
        if not source then return false, err end
    end
    db.profiles[name] = Copy(db.profiles[source])
    Events.Emit("SUUUI_PROFILES_CHANGED")
    return true
end

-- Deletes a profile no character on this account is using right now; characters
-- mapped to it go back to their own profile at their next login.
function Profiles.Delete(text)
    local name, err = Profiles.Find(text)
    if not name then return false, err end
    if name == Profiles.Current() then return false, "You are using " .. name .. "; switch to another profile first." end
    db.profiles[name] = nil
    local unmapped = false
    for role, mapped in pairs(db.roleProfiles or {}) do
        if mapped == name then db.roleProfiles[role], unmapped = nil, true end
    end
    for char, mapped in pairs(db.chars) do
        if mapped == name then db.chars[char] = nil end
    end
    Events.Emit("SUUUI_PROFILES_CHANGED")
    if unmapped then Events.Emit("SUUUI_ROLE_PROFILES_CHANGED") end
    return true
end

-- Replaces the current profile's values with a copy of another profile's,
-- and tells the watchers of every registered setting that changed.
function Profiles.CopyFrom(text)
    local name, err = Profiles.Find(text)
    if not name then return false, err end
    if name == Profiles.Current() then return true end
    local data, changed = Copy(db.profiles[name]), {}
    migrate(data)
    screen(data)
    for namespace, defs in pairs(defaults) do
        for key in pairs(defs) do
            if not Equal(stored(profile, namespace, key), stored(data, namespace, key)) then
                changed[#changed + 1] = { namespace, key }
            end
        end
    end
    wipe(profile)
    for k, v in pairs(data) do profile[k] = v end
    for _, c in ipairs(changed) do notify(c[1], c[2]) end
    Events.Emit("SUUUI_PROFILE_CHANGED", Profiles.Current())
    return true
end

-- Profiles by role (account-wide): the profile each role switches to, or
-- nil to leave the profile alone. Roles: TANK, HEALER, DAMAGER.
function Profiles.RoleProfile(role)
    local name = db and db.roleProfiles and db.roleProfiles[role]
    if name and db.profiles[name] then return name end
end

function Profiles.SetRoleProfile(role, name)
    db.roleProfiles = db.roleProfiles or {}
    db.roleProfiles[role] = (name and db.profiles[name]) and name or nil
    Events.Emit("SUUUI_ROLE_PROFILES_CHANGED")
    return true
end

-- This character's role choice: "auto" (the assigned role, else talents) or
-- a role it always counts as.
function Profiles.ChosenRole()
    return db and db.charRoles and db.charRoles[charKey] or "auto"
end

function Profiles.SetChosenRole(role)
    db.charRoles = db.charRoles or {}
    db.charRoles[charKey] = role ~= "auto" and role or nil
    Events.Emit("SUUUI_ROLE_PROFILES_CHANGED")
    return true
end

-- The role this character's profile was last switched for (Roles.lua), kept
-- across sessions so a profile picked by hand survives a reload.
function Profiles.LastRole()
    return db and db.lastRoles and db.lastRoles[charKey]
end

function Profiles.SetLastRole(role)
    db.lastRoles = db.lastRoles or {}
    db.lastRoles[charKey] = role
end

-- A copy of a profile's stored values, for export.
function Profiles.Export(text)
    local name, err = Profiles.Find(text or Profiles.Current())
    if not name then return nil, err end
    return { name = name, data = Copy(db.profiles[name]) }
end

-- Keeps plain data only, brings an older SuuUI's values into today's shape
-- (migrations), then keeps for registered settings only values of the
-- default's type. Namespaces SuuUI doesn't know (a plugin that isn't
-- installed here) are kept as they are.
local function sanitize(data)
    local out = {}
    if type(data) ~= "table" then return out end
    for namespace, values in pairs(data) do
        if type(namespace) == "string" and type(values) == "table" then
            for key, v in pairs(values) do
                if type(key) == "string" then
                    out[namespace] = out[namespace] or {}
                    out[namespace][key] = Copy(v)
                end
            end
        end
    end
    migrate(out)
    for namespace, values in pairs(out) do
        local defs = defaults[namespace]
        if defs then
            for key, v in pairs(values) do
                if defs[key] ~= nil and type(v) ~= type(defs[key]) then values[key] = nil end
            end
            if next(values) == nil then out[namespace] = nil end
        end
    end
    return out
end

-- A new profile from exported data; switches to it.
function Profiles.Import(name, data)
    local ok, err = Profiles.Create(name)
    if not ok then return false, err end
    db.profiles[strtrim(name)] = sanitize(data)
    return Profiles.Use(strtrim(name))
end

local function bind()
    SuuUIDB = SuuUIDB or {}
    db = SuuUIDB
    db.version = db.version or 1
    db.profiles = db.profiles or {}
    db.chars = db.chars or {}
    charKey = UnitName("player") .. " - " .. GetRealmName()
    local name = db.chars[charKey]
    if not (name and db.profiles[name]) then name = charKey end
    db.chars[charKey] = name
    db.profiles[name] = db.profiles[name] or {}
    profile = db.profiles[name]
    -- the migrations and vetoes of every file of SuuUI are in by now
    for _, p in pairs(db.profiles) do
        if type(p) == "table" then migrate(p) end
    end
    screen(profile)
end

Events.OnGame("ADDON_LOADED", function(_, addon)
    if addon ~= ADDON then return end
    Events.Off("ADDON_LOADED", "Settings")
    bind()
    Events.Emit("SUUUI_SETTINGS_READY")
end, "Settings")

--------------------------------------------------------------------------------
-- The core's own settings
--------------------------------------------------------------------------------

Settings.Register("core", {
    debug = false, -- print SuuUI's debug lines in chat
})

function ns.Debug(...)
    if profile and current("core", "debug") then ns.Print("|cffa39b8b[debug]|r", ...) end
end

Settings.Watch("core", "debug", function(on)
    ns.Print(on and "Debug lines on." or "Debug lines off.")
end, "Core")

--------------------------------------------------------------------------------
-- Chat commands
--------------------------------------------------------------------------------

local function parse(text, like)
    local t = type(like)
    if t == "boolean" then
        local l = text:lower()
        if l == "true" or l == "on" or l == "yes" or l == "1" then return true end
        if l == "false" or l == "off" or l == "no" or l == "0" then return false end
        return nil, "expected on or off"
    elseif t == "number" then
        local n = tonumber(text)
        if n then return n end
        return nil, "expected a number"
    elseif t == "string" then
        return text
    end
    return nil, "this setting can only be changed in the settings window"
end

local function show(v)
    if type(v) == "table" then return "(table)" end
    return tostring(v)
end

local function splitPath(path)
    return path:match("^([^%.]+)%.(.+)$")
end

ns.RegisterCommand("get", "List every setting, or show one: /suu get core.debug", function(arg)
    if not profile then return ns.Print("Settings haven't loaded yet.") end
    if arg ~= "" then
        local namespace, key = splitPath(arg)
        if not (namespace and defaults[namespace] and defaults[namespace][key] ~= nil) then
            return ns.Print(("No setting called %s."):format(arg))
        end
        return ns.Print(("%s = %s%s"):format(arg, show(current(namespace, key)),
            Settings.IsDefault(namespace, key) and "" or "  (changed)"))
    end
    ns.Print(("Profile: %s"):format(Profiles.Current()))
    for _, entry in ipairs(Settings.List()) do
        for _, key in ipairs(entry.keys) do
            print(("  %s.%s = %s%s"):format(entry.namespace, key, show(current(entry.namespace, key)),
                Settings.IsDefault(entry.namespace, key) and "" or "  (changed)"))
        end
    end
end)

ns.RegisterCommand("set", "Change a setting: /suu set core.debug on", function(arg)
    if not profile then return ns.Print("Settings haven't loaded yet.") end
    local path, text = arg:match("^(%S+)%s+(.+)$")
    local namespace, key = splitPath(path or "")
    if not (namespace and defaults[namespace] and defaults[namespace][key] ~= nil) then
        return ns.Print("Usage: /suu set <namespace.key> <value>. /suu get lists them.")
    end
    local value, err = parse(text, defaults[namespace][key])
    if value == nil then return ns.Print(("%s: %s."):format(path, err)) end
    local ok, reason = Settings.Set(namespace, key, value)
    if ok then
        ns.Print(("%s = %s"):format(path, show(current(namespace, key))))
    else
        ns.Print(("%s wasn't changed: %s"):format(path, reason or "refused"))
    end
end)

ns.RegisterCommand("reset", "Reset a setting, a namespace, or everything: /suu reset core.debug | core | all", function(arg)
    if not profile then return ns.Print("Settings haven't loaded yet.") end
    if arg == "all" then
        Settings.Reset()
        return ns.Print("Every setting in " .. Profiles.Current() .. " is back to its default.")
    end
    local namespace, key = splitPath(arg)
    namespace = namespace or arg
    if not defaults[namespace] or (key and defaults[namespace][key] == nil) then
        return ns.Print("Usage: /suu reset <namespace.key> | <namespace> | all")
    end
    Settings.Reset(namespace, key)
    ns.Print(arg .. " is back to its default.")
end)

ns.RegisterCommand("profile", "Show profiles; /suu profile use|new|delete <name> (any letter case, or the start of a name)", function(arg)
    if not profile then return ns.Print("Settings haven't loaded yet.") end
    local verb, name = arg:match("^(%S+)%s+(.+)$")
    local ok, err
    if verb == "use" then
        ok, err = Profiles.Use(name)
    elseif verb == "new" then
        ok, err = Profiles.Create(name)
        if ok then ok, err = Profiles.Use(name) end
    elseif verb == "delete" then
        local full = Profiles.Find(name)
        ok, err = Profiles.Delete(name)
        if ok then ns.Print("Deleted " .. full .. ".") end
    elseif arg ~= "" then
        return ns.Print("Usage: /suu profile [use|new|delete <name>]")
    end
    if err then return ns.Print(err) end
    ns.Print("Profile: " .. Profiles.Current())
    for _, n in ipairs(Profiles.List()) do
        print(("  %s%s"):format(n, n == Profiles.Current() and "  (current)" or ""))
    end
end)
