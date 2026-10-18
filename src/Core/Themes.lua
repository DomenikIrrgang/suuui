-- Core/Themes.lua
-- Themes (plan 4.3, asked 2026-10-18; after a reload, agreed): a plugin
-- registers one with SuuUI.RegisterTheme, the player picks it in Settings ›
-- General › Appearance (for every character, like colour vision), and it
-- applies at login, just before SuuUI's modules build their frames:
--   colors = { [token] = { r, g, b[, a] } }   a design token's colour (its
--                                             own alpha kept unless given);
--            or function(class) → that table  (worked out at login for your
--                                             class: "MAGE", "DRUID", …)
--   fonts = { [style] = { file, size, lineHeight } }  a text style's face,
--                                             size and line height
-- Plugins load after SuuUI's saved settings, so a theme can't apply where
-- colour vision does (Settings' bind); colour vision is applied again after
-- it, so its signal colours always win. A change applies at once (asked
-- 2026-10-19): the tokens go back to the design's, the theme and colour
-- vision go on top, every colour kept by UI.Paint is set again, and
-- SUUUI_THEME_CHANGED tells the rest (colour codes in text, colours worked
-- out from a token, sizes from a text style's line height).

local _, ns = ...

local T = ns.Tokens

-- the design's own colours and text styles, before any theme or colour
-- vision (this file loads before the saved settings apply either)
local design = { color = {}, type = {} }
for name, c in pairs(T.color) do design.color[name] = { c[1], c[2], c[3], c[4], hex = c.hex } end
for name, s in pairs(T.type) do design.type[name] = { file = s.file, size = s.size, lineHeight = s.lineHeight } end

local function reset()
    for name, d in pairs(design.color) do
        local c = T.color[name]
        c[1], c[2], c[3], c[4], c.hex = d[1], d[2], d[3], d[4], d.hex
    end
    for name, d in pairs(design.type) do
        local s = T.type[name]
        s.file, s.size, s.lineHeight = d.file, d.size, d.lineHeight
    end
end

local Themes = {}
ns.Themes = Themes

Themes.DEFAULT = "suuui"
local list = { { id = Themes.DEFAULT, name = "SuuUI", description = "SuuUI's own colours and type.", colors = {}, fonts = {} } }
local byId = { [Themes.DEFAULT] = list[1] }
local applied = Themes.DEFAULT

function Themes.Register(def)
    assert(type(def) == "table" and type(def.id) == "string" and def.id ~= "", "SuuUI.RegisterTheme: a theme needs an id")
    assert(not byId[def.id], "SuuUI.RegisterTheme: the theme " .. def.id .. " is taken")
    if type(def.colors) == "table" then
        for token in pairs(def.colors) do
            if not T.color[token] then error(("SuuUI.RegisterTheme: %s has no colour token %q"):format(def.id, tostring(token)), 2) end
        end
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

-- The chosen theme (a missing one: SuuUI's), then the chosen colour vision
-- on top: at login, before the modules start, and again whenever either
-- setting changes.
function Themes.Apply()
    reset()
    local id = ns.Settings.Account("theme") or Themes.DEFAULT
    local theme = byId[id] or byId[Themes.DEFAULT]
    applied = theme.id
    local colors = theme.colors
    if type(colors) == "function" then
        local _, class = UnitClass("player")
        local ok, t = pcall(colors, class)
        colors = ok and type(t) == "table" and t or {}
    end
    for name, c in pairs(colors) do
        local token = T.color[name]
        -- (a worked-out table may name a token that isn't one: skipped)
        if token then
            token[1], token[2], token[3] = c[1], c[2], c[3]
            if c[4] then token[4] = c[4] end
            token.hex = hex(c[1], c[2], c[3])
        end
    end
    for style, f in pairs(theme.fonts) do
        local s = T.type[style]
        if f.file then s.file = f.file end
        if f.size then s.size = f.size end
        if f.lineHeight then s.lineHeight = f.lineHeight end
    end
    if ns.Vision then ns.Vision.Apply(ns.Settings.Account("colorVision")) end
    ns.Fonts.Refresh()
    ns.UI.Repaint()
    ns.Events.Emit("SUUUI_THEME_CHANGED", applied)
end
