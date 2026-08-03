local pairs, assert, type, tostring = pairs, assert, type, tostring
local UnitName, GetRealmName = UnitName, GetRealmName

local M = {}
local DEFAULT = "Default"

local function charKey()
    return (UnitName("player") or "Unknown") .. "-" .. (GetRealmName() or "Unknown")
end

local function ensureDefault(profiles)
    if not profiles[DEFAULT] then
        profiles[DEFAULT] = { plugins = {}, themes = {} }
    end
end

--- Initialises profile system from SavedVariables. Called by core on ADDON_LOADED.
function M:Init()
    if not SuuUIProfiles then
        SuuUIProfiles = { profiles = {}, charMap = {} }
    end
    ensureDefault(SuuUIProfiles.profiles)
    local char  = charKey()
    local pname = SuuUIProfiles.charMap[char] or DEFAULT
    if not SuuUIProfiles.profiles[pname] then pname = DEFAULT end
    self._active = pname
    SuuUI.Events:Emit("SUUUI_PROFILE_LOADED", pname)
end

--- Creates a new profile copied from the Default profile.
-- @param name string
function M:Create(name)
    assert(type(name) == "string" and name ~= "", "SuuUI: profile name required")
    assert(not SuuUIProfiles.profiles[name], "SuuUI: profile already exists: " .. name)
    SuuUIProfiles.profiles[name] = SuuUI.Utils.DeepCopy(SuuUIProfiles.profiles[DEFAULT])
end

--- Deletes a profile. The Default profile cannot be deleted.
-- @param name string
function M:Delete(name)
    assert(name ~= DEFAULT, "SuuUI: cannot delete Default profile")
    assert(SuuUIProfiles.profiles[name], "SuuUI: profile not found: " .. name)
    SuuUIProfiles.profiles[name] = nil
    for char, pname in pairs(SuuUIProfiles.charMap) do
        if pname == name then SuuUIProfiles.charMap[char] = DEFAULT end
    end
    if self._active == name then self:SetActive(DEFAULT) end
end

--- Returns an array of all profile names.
-- @return table
function M:List()
    local names = {}
    for k in pairs(SuuUIProfiles.profiles) do
        names[#names + 1] = k
    end
    return names
end

--- Switches the active profile and fires SUUUI_PROFILE_LOADED.
-- @param name string
function M:SetActive(name)
    assert(SuuUIProfiles.profiles[name], "SuuUI: profile not found: " .. name)
    self._active = name
    SuuUI.Events:Emit("SUUUI_PROFILE_LOADED", name)
end

--- Returns the active profile table.
-- @return table
function M:GetActive()
    return SuuUIProfiles.profiles[self._active]
end

--- Returns the active profile name string.
-- @return string
function M:GetActiveName()
    return self._active
end

--- Links the current character to a profile.
-- @param name string
function M:LinkCharacter(name)
    assert(SuuUIProfiles.profiles[name], "SuuUI: profile not found: " .. name)
    SuuUIProfiles.charMap[charKey()] = name
end

--- Returns a raw profile table by name.
-- @param name string
-- @return table
function M:Get(name)
    return SuuUIProfiles.profiles[name]
end

--- Deep-copies the active profile into target.
-- @param targetName string
function M:CopyTo(targetName)
    assert(SuuUIProfiles.profiles[targetName], "SuuUI: profile not found: " .. targetName)
    SuuUIProfiles.profiles[targetName] = SuuUI.Utils.DeepCopy(self:GetActive())
end

SuuUI.Profiles = M
