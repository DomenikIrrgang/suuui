local assert, type, ipairs, pcall, tostring = assert, type, ipairs, pcall, tostring
local tinsert = table.insert

local M = {}
local registry  = {}  -- [id] = pluginHandle
local order     = {}  -- insertion order array of ids

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

--- Called by core bootstrap to fire onInit for all registered plugins.
function M:InitAll()
    for _, id in ipairs(order) do
        local plugin = registry[id]
        if plugin._def.onInit then
            local ok, err = pcall(plugin._def.onInit, plugin)
            if not ok then
                SuuUI.Debug("Plugin onInit error [" .. id .. "]: " .. tostring(err))
            end
        end
    end
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
        SuuUI.Plugins:InitAll()
        for _, plugin in ipairs(SuuUI.Plugins:GetAll()) do
            local en = SuuUI.Settings:Get(plugin.id, "enabled")
            if en == nil or en == true then plugin:Enable() end
        end
    elseif event == "PLAYER_LOGOUT" then
        if not SuuUIConfig then SuuUIConfig = {} end
        SuuUIConfig.activeProfile = SuuUI.Profiles:GetActiveName()
    end
end)
