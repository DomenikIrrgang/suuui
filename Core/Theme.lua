local pairs, assert, type, ipairs = pairs, assert, type, ipairs
local max, floor = math.max, math.floor
local format = string.format

local M = {}
local builtins  = {}   -- [name] = tokenTable  (read-only)
local active    = nil  -- current theme name
local resolved  = {}   -- flat resolved token cache for active theme
local rawTokens = {}   -- merged token table before resolution, for the theme editor

-- Tokens renamed or dropped when the palette moved to a two-tier scale. User themes
-- stored under the old keys are translated on read so saved overrides keep working.
-- false means the token no longer exists and the override is discarded.
local migrations = {
    colorTextDisable = "colorTextDisabled",
    shadowAlpha      = "opacityOverlay",
    spaceSm          = "spaceXs",   -- old Sm was 4px, now spaceXs
    spaceMd          = "spaceSm",   -- old Md was 8px, now spaceSm
    borderRadius     = false,       -- never implemented
    fontFamilyMono   = false,       -- WoW ships no monospace face
}

-- A token value may be:
--   a literal (number, string path, RGBA array)
--   an alias: the string key of another token
--   a derived colour: { ref = tokenKey, alpha = tokenKey|number }
local function resolve(tokens, key, depth)
    depth = depth or 0
    if depth > 8 then return nil end
    local v = tokens[key]
    if type(v) == "string" and tokens[v] then
        return resolve(tokens, v, depth + 1)
    end
    if type(v) == "table" and v.ref then
        local base = resolve(tokens, v.ref, depth + 1)
        if type(base) ~= "table" then return nil end
        local a = v.alpha
        if type(a) == "string" then a = resolve(tokens, a, depth + 1) end
        return { base[1], base[2], base[3], a or base[4] or 1 }
    end
    return v
end

-- fontFamilyMain stores a font *name*, so the choice survives a media addon moving its
-- file. Consumers want a path, so the name is resolved once per cache build rather than
-- on every GetToken. A literal path passes straight through, which is what the built-in
-- themes carry and what a hand-edited SavedVariable may hold.
local function fontPath(value)
    if SuuUI.Fonts then return SuuUI.Fonts:Path(value) end
    return value
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
    -- Themes saved before the two-tier palette carry no version stamp; their keys are
    -- translated. Stamped themes are already using current names.
    local legacy = userTheme._tokenVersion == nil
    for k, v in pairs(userTheme) do
        if k ~= "_base" and k ~= "_tokenVersion" then
            local target = k
            if legacy and migrations[k] ~= nil then target = migrations[k] end
            if target then merged[target] = v end
        end
    end
    for k in pairs(merged) do
        resolved[k] = resolve(merged, k)
    end
    rawTokens = merged
    resolved.fontFamilyMain = fontPath(resolved.fontFamilyMain)
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

--- Returns a token's stored value, before alias, derivation and font resolution.
-- The theme editor needs this: fontFamilyMain stores a font name while GetToken hands
-- consumers the resolved file path.
-- @param key string
-- @return any
function M:GetTokenRaw(key)
    return rawTokens[key]
end

--- Returns a colour token as a WoW chat escape prefix, e.g. "|cffff4040".
-- Lets chat output use the theme's intent colours instead of hardcoded literals.
-- @param key string  Colour token key
-- @return string
function M:GetColorCode(key)
    local c = resolved[key]
    if type(c) ~= "table" then return "|cffffffff" end
    return format("|cff%02x%02x%02x",
        floor(c[1] * 255 + 0.5), floor(c[2] * 255 + 0.5), floor(c[3] * 255 + 0.5))
end

-- Maps the component size keys onto the font size tokens. One table, so nothing has to
-- rebuild a token name from a size key and get the casing wrong.
local fontSizeTokens = {
    sm = "fontSizeSm", md = "fontSizeMd", lg = "fontSizeLg", xl = "fontSizeXl",
}

--- Returns the resolved font size for a component size key ("sm".."xl").
-- Use this instead of composing the token name yourself when you need the pixel size of
-- the same step a Text element renders at.
-- @param sizeKey string  "sm"|"md"|"lg"|"xl"; unknown keys fall back to md
-- @return number
function M:GetFontSize(sizeKey)
    return resolved[fontSizeTokens[sizeKey] or "fontSizeMd"]
end

--- Returns a control height token floored against the current font metrics.
-- Font sizes are user-editable, so a control that holds text must not be pinned to a
-- fixed height or the text clips once the font grows past it. Controls with no text
-- (toggles, swatches) should read the size token directly instead.
-- @param sizeKey string   Size token, e.g. "sizeControlMd"
-- @param fontKey string   Optional font size token, defaults to "fontSizeMd"
-- @return number
function M:GetControlHeight(sizeKey, fontKey)
    local base = resolved[sizeKey] or 22
    local font = resolved[fontKey or "fontSizeMd"] or 13
    local pad  = resolved.spaceXs or 4
    -- Ceil onto the pixel grid rather than round: a control that lands half a pixel
    -- short of its own text clips the glyphs. Tokens are user-editable, so this cannot
    -- assume the inputs were integers.
    return SuuUI.Pixel.Ceil(max(base, font + pad * 2))
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
    profile.themes[name] = { _base = baseTheme, _tokenVersion = 2 }
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
    
    -- Keep only the meta fields, clear all token overrides
    local baseTheme = profile.themes[name]._base or "Modern"
    profile.themes[name] = { _base = baseTheme, _tokenVersion = 2 }
    
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
    profile.themes[themeName]._tokenVersion = 2
    if active == themeName then 
        buildCache(themeName)
        SuuUI.Events:Emit("SUUUI_THEME_CHANGED", themeName)
    end
end

--- Applies bg and border tokens to a raw WoW frame.
-- Resolved at call time: Components/Backdrop.lua loads after this file.
-- @param frame frame
function M:ApplyToFrame(frame)
    SuuUI.Backdrop.Apply(frame, { bg = "colorBg", border = "colorBorder" })
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
        rawTokens = base
        resolved.fontFamilyMain = fontPath(resolved.fontFamilyMain)
    end
    active = themeName

    -- A media addon can load after SuuUI, so a font name that fell back at boot may
    -- become resolvable later. Rebuild and restyle only when the path actually moved.
    SuuUI.Events:On("SUUUI_FONTS_CHANGED", function()
        if not active then return end
        local before = resolved.fontFamilyMain
        buildCache(active)
        if resolved.fontFamilyMain ~= before then
            SuuUI.Events:Emit("SUUUI_THEME_CHANGED", active)
        end
    end, "_theme_fonts")

    -- A resolution or scale change moves the pixel grid, which changes what every
    -- token-derived size snaps to. Restyling is the same work a theme change needs.
    SuuUI.Events:On("SUUUI_PIXEL_GRID_CHANGED", function()
        if active then SuuUI.Events:Emit("SUUUI_THEME_CHANGED", active) end
    end, "_theme_pixel")
end

SuuUI.Theme = M
