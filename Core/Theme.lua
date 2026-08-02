local pairs, assert, type, ipairs = pairs, assert, type, ipairs

local M = {}
local builtins  = {}   -- [name] = tokenTable  (read-only)
local active    = nil  -- current theme name
local resolved  = {}   -- flat resolved token cache for active theme

local function resolve(tokens, key, depth)
    depth = depth or 0
    if depth > 8 then return nil end
    local v = tokens[key]
    if type(v) == "string" and tokens[v] then
        return resolve(tokens, v, depth + 1)
    end
    return v
end

local function buildCache(themeName)
    resolved = {}
    local profile = SuuUI.Profiles:GetActive()
    local userTheme = (profile and profile.themes and profile.themes[themeName]) or {}
    
    -- Determine base theme: if user theme has _base, use it; otherwise use themeName
    local baseName = userTheme._base or themeName
    local base = builtins[baseName] or {}
    
    local merged = {}
    for k, v in pairs(base) do merged[k] = v end
    -- Apply user overrides (skip _base meta key)
    for k, v in pairs(userTheme) do 
        if k ~= "_base" then
            merged[k] = v 
        end
    end
    for k in pairs(merged) do
        resolved[k] = resolve(merged, k)
    end
end

--- Registers a built-in (read-only) theme. Called by Themes/*.lua files.
-- @param name string
-- @param tokens table
function M:RegisterBuiltin(name, tokens)
    builtins[name] = tokens
end

--- Returns the resolved value of a theme token.
-- @param key string
-- @return any
function M:GetToken(key)
    return resolved[key]
end

--- Sets the active theme and fires SUUUI_THEME_CHANGED.
-- @param name string
function M:SetActive(name)
    assert(builtins[name] or (SuuUI.Profiles:GetActive().themes or {})[name],
        "SuuUI Theme: unknown theme: " .. tostring(name))
    active = name
    
    -- Save to profile
    local profile = SuuUI.Profiles:GetActive()
    profile.activeTheme = name
    
    buildCache(name)
    SuuUI.Events:Emit("SUUUI_THEME_CHANGED", name)
end

--- Returns the active theme name.
-- @return string
function M:GetActive()
    return active
end

--- Returns all available theme names (built-in + user).
-- @return table
function M:List()
    local names = {}
    for k in pairs(builtins) do names[#names + 1] = k end
    local userThemes = (SuuUI.Profiles:GetActive().themes) or {}
    for k in pairs(userThemes) do
        if not builtins[k] then names[#names + 1] = k end
    end
    return names
end

--- Returns whether a theme is built-in (read-only).
-- @param name string
-- @return bool
function M:IsBuiltin(name)
    return builtins[name] ~= nil
end

--- Creates a user-editable theme based on a built-in.
-- @param name string
-- @param baseTheme string  Must be a built-in theme name
function M:CreateUserTheme(name, baseTheme)
    assert(builtins[baseTheme], "SuuUI Theme: base must be a built-in theme")
    local profile = SuuUI.Profiles:GetActive()
    if not profile.themes then profile.themes = {} end
    assert(not profile.themes[name] and not builtins[name],
        "SuuUI Theme: theme already exists: " .. name)
    profile.themes[name] = { _base = baseTheme }
end

--- Deletes a user theme. Built-in themes cannot be deleted.
-- @param name string
function M:DeleteUserTheme(name)
    assert(not builtins[name], "SuuUI Theme: cannot delete built-in theme")
    local profile = SuuUI.Profiles:GetActive()
    if profile.themes then profile.themes[name] = nil end
    if active == name then self:SetActive("Modern") end
end

--- Resets a user theme to its base theme defaults by clearing all overrides.
-- @param name string
function M:ResetUserTheme(name)
    assert(not builtins[name], "SuuUI Theme: cannot reset built-in theme")
    local profile = SuuUI.Profiles:GetActive()
    assert(profile.themes and profile.themes[name],
        "SuuUI Theme: user theme not found: " .. name)
    
    -- Keep only the _base field, clear all token overrides
    local baseTheme = profile.themes[name]._base or "Modern"
    profile.themes[name] = { _base = baseTheme }
    
    if active == name then 
        buildCache(name)
        SuuUI.Events:Emit("SUUUI_THEME_CHANGED", name)
    end
end

--- Sets a token override in a user theme.
-- @param themeName string
-- @param key string
-- @param value any
function M:SetUserToken(themeName, key, value)
    assert(not builtins[themeName], "SuuUI Theme: cannot edit built-in theme")
    local profile = SuuUI.Profiles:GetActive()
    assert(profile.themes and profile.themes[themeName],
        "SuuUI Theme: user theme not found: " .. themeName)
    profile.themes[themeName][key] = value
    if active == themeName then 
        buildCache(themeName)
        SuuUI.Events:Emit("SUUUI_THEME_CHANGED", themeName)
    end
end

--- Applies bg and border tokens to a raw WoW frame.
-- @param frame frame
function M:ApplyToFrame(frame)
    local bg = resolved.colorBg
    if bg then frame:SetBackdropColor(bg[1], bg[2], bg[3], bg[4]) end
    local bd = resolved.colorBorder
    if bd then frame:SetBackdropBorderColor(bd[1], bd[2], bd[3], bd[4]) end
end

--- Initialises theme system; called after profiles are ready.
function M:Init()
    -- Guard: profile may not exist yet on very first login
    local themeName = "Modern"
    local ok = pcall(function()
        local profile = SuuUI.Profiles:GetActive()
        -- Load saved theme from profile, default to Modern
        themeName = profile.activeTheme or "Modern"
        
        -- Verify theme still exists
        if not builtins[themeName] and not (profile.themes and profile.themes[themeName]) then
            themeName = "Modern"
        end
        
        buildCache(themeName)
    end)
    if not ok then
        -- Profiles not ready yet; build from builtins only
        resolved = {}
        local base = builtins["Modern"] or {}
        for k in pairs(base) do
            resolved[k] = resolve(base, k)
        end
    end
    active = themeName
end

SuuUI.Theme = M
