-- Core/Modules.lua
-- Every SuuUI feature is a module, built in or from a plugin addon, and every
-- module goes through this registry:
--
--   local M = SuuUI.RegisterModule({
--       id = "hello",                 -- lower case; also its settings namespace
--       name = "Hello",
--       description = "One line for the module list.",
--       api = "0.1",                  -- the oldest SuuUI API it works with
--       defaults = { greeting = "Hi" },
--       enabledByDefault = true,
--       reloadToToggle = false,       -- true for modules that replace protected frames
--       combatSafe = false,           -- true when it makes no secure or protected
--                                     -- frames: it starts at once after a reload
--                                     -- in combat instead of when the fight ends
--       OnInitialize = function(self) end,  -- once, before the first enable
--       OnEnable = function(self) end,
--       OnDisable = function(self) end,
--   })
--   M:Migrate("renameFoo", function(values) ... end) -- once per profile, at file load
--
-- A module that is off is never initialised: no frames, no events. Its
-- "enabled" setting lives in its own namespace, so it is saved per profile.
-- Everything a module registers through its own methods (events, setting
-- watchers, chat commands) belongs to it and is removed when it turns off;
-- register those in OnEnable. Turning a module on or off waits for the end
-- of combat. A module whose callback errors is marked errored and turned off;
-- SuuUI and the other modules keep running.

local _, ns = ...

local Modules = {}
ns.Modules = Modules

local Events, Settings, Fault, Combat, Util = ns.Events, ns.Settings, ns.Fault, ns.Combat, ns.Util

ns.API_VERSION = "0.13.0"

local RESERVED = { core = true, ui = true, layout = true }

local list, byId = {}, {}
local started = false

--------------------------------------------------------------------------------
-- API versions
--------------------------------------------------------------------------------

local function parseVersion(v)
    local major, minor, patch = tostring(v):match("^(%d+)%.?(%d*)%.?(%d*)$")
    if not major then return nil end
    return tonumber(major), tonumber(minor) or 0, tonumber(patch) or 0
end

-- True when this SuuUI's API can serve a module written for `wanted`: the
-- same major version, and at least that minor and patch.
function Modules.APIAtLeast(wanted)
    local a, b, c = parseVersion(ns.API_VERSION)
    local x, y, z = parseVersion(wanted)
    if not x then return false end
    if a ~= x then return false end
    if b ~= y then return b > y end
    return c >= z
end

--------------------------------------------------------------------------------
-- The module object
--------------------------------------------------------------------------------

local Module = {}
Module.__index = Module

function Module:Get(key) return Settings.Get(self.id, key) end
function Module:Set(key, value) return Settings.Set(self.id, key, value) end
function Module:Reset(key) return Settings.Reset(self.id, key) end
-- 0.11: the module's own data for this character (a table it fills;
-- saved, never part of a profile)
function Module:CharData() return Settings.CharData(self.id) end
function Module:AllCharData() return Settings.AllCharData(self.id) end
function Module:CharKey() return Settings.CharKey() end
function Module:ForgetCharData(key) return Settings.ForgetCharData(self.id, key) end
-- fn wrapped so an error in it is reported (SuuUIDB.errors, /suu errors)
-- under the module's name, as errors in its events are: for UI callbacks.
function Module:Guard(fn) return function(...) return Fault.Call(self.name, fn, ...) end end
function Module:Watch(key, fn) Settings.Watch(self.id, key, fn, self) end
function Module:Veto(key, fn) Settings.Veto(self.id, key, fn, self) end

-- fn(values) reshapes one profile's stored values of this module (a renamed
-- key, a changed type), once per profile. Call it right after RegisterModule,
-- at file load, so it runs before the old values are judged by type.
function Module:Migrate(id, fn) Settings.Migrate(self.id, id, fn, self) end

function Module:On(message, fn) Events.On(message, fn, self) end
function Module:Off(message) Events.Off(message, self) end
function Module:Emit(message, ...) Events.Emit(message, ...) end
function Module:OnGameEvent(event, fn) Events.OnGame(event, fn, self) end
function Module:OnUnitEvent(event, units, fn) Events.OnUnit(event, units, fn, self) end

-- Keys get an "m:" prefix so a module's never collide with the core's own.
function Module:RunOutOfCombat(key, fn)
    Combat.Run("m:" .. self.id .. ":" .. tostring(key), fn, self.name)
end

function Module:RegisterCommand(name, help, fn)
    ns.RegisterCommand(name, help, fn, self)
end

-- A settings section for this module: its rows read and write the module's
-- own namespace, and the section goes away when the module turns off.
function Module:RegisterSettings(def)
    def.namespace = def.namespace or self.id
    return ns.SettingsRegistry.Register(def, self)
end

-- An edit-mode handle for one of the module's frames. opts.key names a
-- position setting in the module's defaults (default "position").
function Module:RegisterMover(frame, opts)
    opts = opts or {}
    opts.namespace = self.id
    opts.label = opts.label or self.name
    return ns.EditMode.Register(frame, opts, self)
end

function Module:Print(...)
    ns.Print("|cffa39b8b" .. self.name .. ":|r", ...)
end

function Module:IsEnabled()
    return self.state == "enabled"
end

--------------------------------------------------------------------------------
-- Lifecycle
--------------------------------------------------------------------------------

local function cleanup(m)
    Events.OffAll(m)
    Settings.Unwatch(m)
    ns.UnregisterCommands(m)
    if ns.SettingsRegistry then ns.SettingsRegistry.Unregister(m) end
    if ns.EditMode then ns.EditMode.Unregister(m) end
end

local function fail(m, phase)
    m.state = "errored"
    m.error = phase .. " failed"
    -- Undo what a failed OnEnable got as far as building (frames shown,
    -- anchors published). Fault.Call reports an error here and carries on.
    if phase == "OnEnable" and m.OnDisable then Fault.Call(m.name, m.OnDisable, m) end
    cleanup(m)
    Events.Emit("SUUUI_MODULE_ERRORED", m.id)
end

local function enable(m)
    if m.state == "enabled" or m.state == "incompatible" then return end
    if not m.initialized then
        if m.OnInitialize and not Fault.Call(m.name, m.OnInitialize, m) then return fail(m, "OnInitialize") end
        m.initialized = true
    end
    if m.OnEnable and not Fault.Call(m.name, m.OnEnable, m) then return fail(m, "OnEnable") end
    m.state, m.error = "enabled", nil
    Events.Emit("SUUUI_MODULE_ENABLED", m.id)
end

local function disable(m)
    if m.state ~= "enabled" then
        if m.state ~= "incompatible" then m.state = "disabled" end
        return
    end
    if m.OnDisable then Fault.Call(m.name, m.OnDisable, m) end
    cleanup(m)
    m.state = "disabled"
    Events.Emit("SUUUI_MODULE_DISABLED", m.id)
end

-- Brings the module in line with its "enabled" setting.
local function apply(m)
    if m.state == "incompatible" then return end
    local want = Settings.Get(m.id, "enabled")
    if m.reloadToToggle then
        -- an errored module that is still on retries at the next load
        m.pendingReload = (want ~= m.enabledAtLoad or (want and m.state == "errored")) or nil
        return
    end
    Combat.Run("module:" .. m.id, function()
        if Settings.Get(m.id, "enabled") then enable(m) else disable(m) end
    end, m.name)
end

local function start(m)
    m.enabledAtLoad = Settings.Get(m.id, "enabled")
    Settings.Watch(m.id, "enabled", function() apply(m) end, "Modules")
    if m.state == "incompatible" then return end
    if m.enabledAtLoad then
        -- after a reload in combat a module waits for the fight's end, unless
        -- it makes no secure frames (found in game: buffs and the Cooldown
        -- Manager were missing until the fight ended)
        if m.combatSafe and InCombatLockdown() then
            Fault.Call(m.name, function() enable(m) end)
        else
            Combat.Run("module:" .. m.id, function() enable(m) end, m.name)
        end
    else
        m.state = "disabled"
    end
end

Events.OnGame("PLAYER_LOGIN", function()
    started = true
    for _, m in ipairs(list) do start(m) end
end, "Modules")

--------------------------------------------------------------------------------
-- Registration
--------------------------------------------------------------------------------

-- The addon whose file called RegisterModule, from the call stack: the first
-- frame of another addon, else SuuUI itself. SuuUI's own frames are skipped
-- by addon, not by file, so this also holds when wowlua bundles SuuUI into
-- one file.
local function sourceAddon()
    local stack = debugstack(1, 8, 0) or ""
    local own = false
    for addon in stack:gmatch("AddOns[/\\]([^/\\]+)[/\\]") do
        if addon ~= ns.name then return addon end
        own = true
    end
    return own and ns.name or "?"
end

function Modules.Register(def)
    assert(type(def) == "table", "SuuUI.RegisterModule takes a table")
    local id = def.id
    assert(type(id) == "string" and id:find("^%l[%l%d_]*$"),
        "SuuUI.RegisterModule: id must be lower case letters, digits and _, starting with a letter")
    assert(not byId[id] and not RESERVED[id], "SuuUI.RegisterModule: the id " .. id .. " is taken")
    local defaults = Util.Copy(def.defaults or {})
    assert(defaults.enabled == nil, "SuuUI.RegisterModule: \"enabled\" is SuuUI's own setting; use enabledByDefault")
    defaults.enabled = def.enabledByDefault ~= false

    local m = setmetatable({
        id = id,
        name = def.name or id,
        description = def.description,
        api = def.api,
        reloadToToggle = def.reloadToToggle and true or false,
        combatSafe = def.combatSafe and true or false,
        OnInitialize = def.OnInitialize,
        OnEnable = def.OnEnable,
        OnDisable = def.OnDisable,
        source = def.addon or sourceAddon(),
        state = "registered",
    }, Module)
    m.builtIn = (m.source == ns.name)

    Settings.Register(id, defaults)
    if def.api and not Modules.APIAtLeast(def.api) then
        m.state = "incompatible"
        m.error = ("needs SuuUI API %s; this SuuUI has %s"):format(tostring(def.api), ns.API_VERSION)
        ns.Print(("%s (%s) can't load: it %s."):format(m.name, m.source, m.error))
    end

    list[#list + 1] = m
    byId[id] = m
    Events.Emit("SUUUI_MODULE_REGISTERED", id)
    if started then start(m) end
    return m
end

function Modules.Get(id)
    return byId[id]
end

function Modules.All()
    return list
end

-- The module `text` names: its id or name, in any letter case.
function Modules.Find(text)
    text = strtrim(text or ""):lower()
    for _, m in ipairs(list) do
        if m.id == text or m.name:lower() == text then return m end
    end
end

--------------------------------------------------------------------------------
-- Chat commands
--------------------------------------------------------------------------------

local STATE_TEXT = {
    enabled = "|cff3fd0ffon|r",
    disabled = "|cffa39b8boff|r",
    errored = "|cffff9a80errored|r",
    incompatible = "|cffff9a80incompatible|r",
    registered = "|cffa39b8bwaiting for login|r",
}

local function describe(m)
    local state = STATE_TEXT[m.state] or m.state
    if m.pendingReload then
        local retry = m.state == "errored" and Settings.Get(m.id, "enabled")
        local after = (retry and "retries") or (m.enabledAtLoad and "off") or "on"
        state = state .. (" |cffffb23f(%s after /reload)|r"):format(after)
    end
    local line = ("  %s  %s  %s  - %s"):format(m.id, m.name, state, m.builtIn and "built in" or m.source)
    if m.error then line = line .. "  (" .. m.error .. ")" end
    return line
end

ns.RegisterCommand("modules", "List every module, built in and from plugins, with its state.", function()
    ns.Print(("%d modules, API %s:"):format(#list, ns.API_VERSION))
    for _, m in ipairs(list) do print(describe(m)) end
end)

local function toggle(arg, on)
    local m = Modules.Find(arg)
    if not m then return ns.Print(("No module called \"%s\". /suu modules lists them."):format(arg)) end
    if m.state == "incompatible" then return ns.Print(m.name .. " " .. m.error .. ".") end
    if on and m.state == "errored" then
        -- Turning an errored module on again is a retry; one that replaces
        -- protected frames can only retry from a fresh load.
        if m.reloadToToggle then
            Settings.Set(m.id, "enabled", true)
            m.pendingReload = true
            ns.Print(("%s tries again after a /reload."):format(m.name))
            return print(describe(m))
        end
        m.state = "disabled"
        if Settings.Get(m.id, "enabled") then apply(m) end
    end
    Settings.Set(m.id, "enabled", on)
    if m.reloadToToggle and m.pendingReload then
        ns.Print(("%s turns %s after a /reload."):format(m.name, on and "on" or "off"))
    elseif InCombatLockdown() then
        ns.Print(("%s turns %s when combat ends."):format(m.name, on and "on" or "off"))
    end
    print(describe(m))
end

ns.RegisterCommand("enable", "Turn a module on: /suu enable <id>", function(arg) toggle(arg, true) end)
ns.RegisterCommand("disable", "Turn a module off: /suu disable <id>", function(arg) toggle(arg, false) end)
