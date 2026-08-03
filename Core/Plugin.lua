local assert, type, ipairs, pcall, tostring = assert, type, ipairs, pcall, tostring
local tinsert = table.insert

local M = {}
local registry  = {}  -- [id] = pluginHandle
local order     = {}  -- insertion order array of ids
local ready     = false  -- true once the core has finished its login pass

-- Runs a plugin's onInit at most once. Init is a property of the plugin, not of the
-- call that triggers it, so InitAll is safe to re-run and a late registration can be
-- initialised on its own without re-entering anyone else's onInit.
local function initPlugin(plugin)
    if plugin._inited then return end
    plugin._inited = true
    if plugin._def.onInit then
        local ok, err = pcall(plugin._def.onInit, plugin)
        if not ok then
            SuuUI.Debug("Plugin onInit error [" .. plugin.id .. "]: " .. tostring(err))
        end
    end
end

-- The one place that decides whether a plugin should be running: absent or true means
-- enabled, so a plugin with no "enabled" setting is on by default.
local function autoEnable(plugin)
    local en = SuuUI.Settings:Get(plugin.id, "enabled")
    if en == nil or en == true then plugin:Enable() end
end

local PluginMeta = {}
PluginMeta.__index = PluginMeta

--- Returns the plugin's live settings from the active profile.
-- @return table
function PluginMeta:GetSettings()
    local profile = SuuUI.Profiles:GetActive()
    if not profile.plugins then profile.plugins = {} end
    if not profile.plugins[self.id] then profile.plugins[self.id] = {} end
    return profile.plugins[self.id]
end

--- Returns the plugin's full profile sub-table.
-- @return table
function PluginMeta:GetProfile()
    return self:GetSettings()
end

--- Returns whether the plugin is currently enabled.
-- @return bool
function PluginMeta:IsEnabled()
    return self._enabled
end

--- Enables the plugin, firing onEnable if not already enabled.
function PluginMeta:Enable()
    if self._enabled then return end
    self._enabled = true
    if self._def.onEnable then
        local ok, err = pcall(self._def.onEnable, self)
        if not ok then SuuUI.Debug("Plugin onEnable error [" .. self.id .. "]: " .. tostring(err)) end
    end
    SuuUI.Events:Emit("SUUUI_PLUGIN_ENABLED", self.id)
end

--- Disables the plugin, firing onDisable if enabled.
function PluginMeta:Disable()
    if not self._enabled then return end
    self._enabled = false
    if self._def.onDisable then
        local ok, err = pcall(self._def.onDisable, self)
        if not ok then SuuUI.Debug("Plugin onDisable error [" .. self.id .. "]: " .. tostring(err)) end
    end
    SuuUI.Events:Emit("SUUUI_PLUGIN_DISABLED", self.id)
end

--- Creates and registers a plugin with SuuUI.
-- @param def table  { id, name, version, onInit, onEnable, onDisable }
-- @return table  Plugin handle
function SuuUI:CreatePlugin(def)
    assert(type(def) == "table",          "SuuUI: CreatePlugin requires a table")
    assert(type(def.id) == "string",      "SuuUI: plugin id must be a string")
    assert(type(def.name) == "string",    "SuuUI: plugin name must be a string")
    assert(not registry[def.id],          "SuuUI: plugin already registered: " .. def.id)

    local plugin = setmetatable({
        id       = def.id,
        name     = def.name,
        version  = def.version or "",
        _def     = def,
        _enabled = false,
    }, PluginMeta)

    registry[def.id] = plugin
    tinsert(order, def.id)

    -- An addon that loads after our login pass would otherwise never be initialised.
    -- Bring it up immediately: every other plugin is already up, so there is no
    -- init-before-enable ordering left to respect.
    if ready then
        initPlugin(plugin)
        autoEnable(plugin)
    end

    return plugin
end

--- Returns a registered plugin handle by id.
-- @param id string
-- @return table|nil
function M:Get(id)
    return registry[id]
end

--- Returns all registered plugins in registration order.
-- @return table  Array of plugin handles
function M:GetAll()
    local list = {}
    for _, id in ipairs(order) do
        list[#list + 1] = registry[id]
    end
    return list
end

--- Fires onInit for every plugin that has not been initialised yet.
-- Idempotent: calling it again is a no-op for plugins already initialised. A plugin
-- registered during another plugin's onInit is picked up by the same pass.
function M:InitAll()
    for _, id in ipairs(order) do
        initPlugin(registry[id])
    end
end

--- Returns whether a plugin has had its onInit run.
-- @param id string
-- @return bool
function M:IsInitialised(id)
    local plugin = registry[id]
    return plugin ~= nil and plugin._inited == true
end

SuuUI.Plugins = M

-- Bootstrap frame: drives init lifecycle
local bootFrame = CreateFrame("Frame")
bootFrame:RegisterEvent("ADDON_LOADED")
bootFrame:RegisterEvent("PLAYER_LOGIN")
bootFrame:RegisterEvent("PLAYER_LOGOUT")
bootFrame:SetScript("OnEvent", function(_, event, arg1)
    if event == "ADDON_LOADED" and arg1 == "SuuUI" then
        SuuUI.Profiles:Init()
        SuuUI.Theme:Init()  -- This now loads activeTheme from profile
        SuuUI.UIRoot:Init()  -- Initialize global UI root
        
        -- Core subsystems (profiles, theme, UI root) are now usable
        SuuUI.Events:Emit("SUUUI_CORE_READY")

        -- Listen for profile changes to apply theme
        SuuUI.Events:On("SUUUI_PROFILE_LOADED", function()
            local prof = SuuUI.Profiles:GetActive()
            local themeName = prof.activeTheme or "Modern"
            -- Verify theme exists
            if not SuuUI.Theme:IsBuiltin(themeName) and not (prof.themes and prof.themes[themeName]) then
                themeName = "Modern"
            end
            SuuUI.Theme:SetActive(themeName)
        end, "_theme_profile_boot")
    elseif event == "PLAYER_LOGIN" then
        -- Two phases on purpose: every onInit runs before any onEnable, so a plugin's
        -- onEnable can rely on another plugin's settings and events already existing.
        SuuUI.Plugins:InitAll()
        for _, plugin in ipairs(SuuUI.Plugins:GetAll()) do
            autoEnable(plugin)
        end
        ready = true
        SuuUI.Events:Emit("SUUUI_READY")
    elseif event == "PLAYER_LOGOUT" then
        if not SuuUIConfig then SuuUIConfig = {} end
        SuuUIConfig.activeProfile = SuuUI.Profiles:GetActiveName()
    end
end)
