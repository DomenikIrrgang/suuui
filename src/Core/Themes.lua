-- Core/Themes.lua
-- Themes (plan 4.3, asked 2026-10-18; after a reload, agreed): a plugin
-- registers one with SuuUI.RegisterTheme, the player picks it in Settings ›
-- General › Appearance (for every character, like colour vision), and it
-- applies at login, just before SuuUI's modules build their frames:
--   colors = { [token] = { r, g, b[, a] } }   a design token's colour (its
--                                             own alpha kept unless given)
--   fonts = { [style] = { file, size } }      a text style's face and size
-- Plugins load after SuuUI's saved settings, so a theme can't apply where
-- colour vision does (Settings' bind); colour vision is applied again after
-- it, so its signal colours always win. Changes take a reload: SuuUI reads
-- colours when it builds its frames.

local _, ns = ...

local T = ns.Tokens

local Themes = {}
ns.Themes = Themes

Themes.DEFAULT = "suuui"
local list = { { id = Themes.DEFAULT, name = "SuuUI", description = "SuuUI's own colours and type." } }
local byId = { [Themes.DEFAULT] = list[1] }
local applied = Themes.DEFAULT

function Themes.Register(def)
    assert(type(def) == "table" and type(def.id) == "string" and def.id ~= "", "SuuUI.RegisterTheme: a theme needs an id")
    assert(not byId[def.id], "SuuUI.RegisterTheme: the theme " .. def.id .. " is taken")
    for token in pairs(def.colors or {}) do
        if not T.color[token] then error(("SuuUI.RegisterTheme: %s has no colour token %q"):format(def.id, tostring(token)), 2) end
    end
    for style in pairs(def.fonts or {}) do
        if not T.type[style] then error(("SuuUI.RegisterTheme: %s has no text style %q"):format(def.id, tostring(style)), 2) end
    end
    local theme = { id = def.id, name = def.name or def.id, description = def.description, colors = def.colors or {}, fonts = def.fonts or {} }
    list[#list + 1] = theme
    byId[def.id] = theme
    return theme
end

function Themes.List()
    return list
end

function Themes.Get(id)
    return byId[id]
end

-- The theme in effect this session.
function Themes.Applied()
    return applied
end

local function hex(r, g, b)
    return ("%02x%02x%02x"):format(math.floor(r * 255 + 0.5), math.floor(g * 255 + 0.5), math.floor(b * 255 + 0.5))
end

-- The chosen theme (a missing one: SuuUI's), then colour vision on top.
-- Called once, at login, before the modules start.
function Themes.Apply()
    local id = ns.Settings.Account("theme") or Themes.DEFAULT
    local theme = byId[id] or byId[Themes.DEFAULT]
    applied = theme.id
    for name, c in pairs(theme.colors) do
        local token = T.color[name]
        token[1], token[2], token[3] = c[1], c[2], c[3]
        if c[4] then token[4] = c[4] end
        token.hex = hex(c[1], c[2], c[3])
    end
    local fonts = false
    for style, f in pairs(theme.fonts) do
        local s = T.type[style]
        if f.file then s.file = f.file end
        if f.size then s.size = f.size end
        fonts = true
    end
    if fonts then ns.Fonts.Refresh() end
    if theme.id ~= Themes.DEFAULT and ns.Vision then ns.Vision.Apply(ns.Vision.Applied()) end
    if ns.Vision then ns.Vision.SyncGlows() end
end
