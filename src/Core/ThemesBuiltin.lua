-- Core/ThemesBuiltin.lua
-- SuuUI's own themes beside its look (asked 2026-10-18: every option of the
-- design "Themes: High contrast, Class accent, Darker", for the player to
-- choose). Signal and game colours (arcane, ember, quest-*, class-*, …)
-- never change in any of them.
--   High contrast (A gilt edges, B ink edges): brighter text and edges,
--     captions and micro digits one size up
--   Class accent (C your class colour as it is, D its hue at gilt's weight):
--     worked out at login for your class
--   Darker (E near black, F OLED black): the surfaces

local _, ns = ...

local T = ns.Tokens
local Themes = ns.Themes

-- "#RRGGBB" or "#RRGGBBAA" → { r, g, b[, a] }
local function hex(s)
    local r, g, b = tonumber(s:sub(2, 3), 16) / 255, tonumber(s:sub(4, 5), 16) / 255, tonumber(s:sub(6, 7), 16) / 255
    if #s >= 9 then return { r, g, b, tonumber(s:sub(8, 9), 16) / 255 } end
    return { r, g, b }
end

local function colors(list)
    local out = {}
    for token, value in pairs(list) do out[token] = hex(value) end
    return out
end

--------------------------------------------------------------------------------
-- High contrast
--------------------------------------------------------------------------------

local CONTRAST = {
    ["ink"] = "#FFFDF7", ["ink-muted"] = "#D4CCBC", ["ink-faint"] = "#A39B8B",
    ["gilt"] = "#E3C274", ["gilt-text"] = "#F6E3AE", ["surface-glass"] = "#131116F7",
}
local CONTRAST_FONTS = { caption = { size = 12, lineHeight = 15 }, micro = { size = 10.5, lineHeight = 13 } }

local function contrast(edges)
    local list = {}
    for k, v in pairs(CONTRAST) do list[k] = v end
    for k, v in pairs(edges) do list[k] = v end
    return colors(list)
end

Themes.Register({
    id = "highcontrast", name = "High contrast",
    description = "Brighter text and gilt edges, captions and small digits a size up.",
    colors = contrast({ ["gilt-line"] = "#E3C274BF", ["gilt-hairline"] = "#E3C27499", ["gilt-faint"] = "#E3C2744D" }),
    fonts = CONTRAST_FONTS,
})
Themes.Register({
    id = "highcontrast-ink", name = "High contrast · ink edges",
    description = "Brighter text, light ink edges; gilt stays on titles, tabs and diamonds.",
    colors = contrast({ ["gilt-line"] = "#F1EADB99", ["gilt-hairline"] = "#F1EADB7A", ["gilt-faint"] = "#F1EADB38" }),
    fonts = CONTRAST_FONTS,
})

--------------------------------------------------------------------------------
-- Class accent
--------------------------------------------------------------------------------

-- the accent family's alphas (gilt's own: line, hairline, faint)
local LINE_A, HAIRLINE_A, FAINT_A = 0x61 / 255, 0x4D / 255, 0x24 / 255

local function linear(c) return c <= 0.04045 and c / 12.92 or ((c + 0.055) / 1.055) ^ 2.4 end
local function gamma(c)
    c = c <= 0.0031308 and 12.92 * c or 1.055 * c ^ (1 / 2.4) - 0.055
    return math.max(0, math.min(1, c))
end
local function luminance(r, g, b) return 0.2126 * linear(r) + 0.7152 * linear(g) + 0.0722 * linear(b) end
local function ratio(a, b)
    local la, lb = luminance(a[1], a[2], a[3]), luminance(b[1], b[2], b[3])
    if la < lb then la, lb = lb, la end
    return (la + 0.05) / (lb + 0.05)
end
local function cbrt(x) return x < 0 and -((-x) ^ (1 / 3)) or x ^ (1 / 3) end

-- sRGB → OKLab's hue (radians), and OKLCH → sRGB
local function hue(r, g, b)
    r, g, b = linear(r), linear(g), linear(b)
    local l = cbrt(0.4122214708 * r + 0.5363325363 * g + 0.0514459929 * b)
    local m = cbrt(0.2119034982 * r + 0.6806995451 * g + 0.1073969566 * b)
    local s = cbrt(0.0883024619 * r + 0.2817188376 * g + 0.6299787005 * b)
    local A = 1.9779984951 * l - 2.4285922050 * m + 0.4505937099 * s
    local B = 0.0259040371 * l + 0.7827717662 * m - 0.8086757660 * s
    return math.atan2(B, A)
end
local function oklch(L, C, h)
    local A, B = C * math.cos(h), C * math.sin(h)
    local l = (L + 0.3963377774 * A + 0.2158037573 * B) ^ 3
    local m = (L - 0.1055613458 * A - 0.0638541728 * B) ^ 3
    local s = (L - 0.0894841775 * A - 1.2914855480 * B) ^ 3
    return { gamma(4.0767416621 * l - 3.3077115913 * m + 0.2309699292 * s),
             gamma(-1.2684380046 * l + 2.6097574011 * m - 0.3413193965 * s),
             gamma(-0.0041960863 * l - 0.7034186147 * m + 1.7076147010 * s) }
end

local function family(base, text)
    return {
        ["gilt"] = { base[1], base[2], base[3] },
        ["gilt-text"] = { text[1], text[2], text[3] },
        ["gilt-line"] = { base[1], base[2], base[3], LINE_A },
        ["gilt-hairline"] = { base[1], base[2], base[3], HAIRLINE_A },
        ["gilt-faint"] = { base[1], base[2], base[3], FAINT_A },
    }
end

local function classColor(class)
    local c = class and T.color["class-" .. class:lower()]
    return c and { c[1], c[2], c[3] }
end

Themes.Register({
    id = "classaccent", name = "Class accent",
    description = "Your class colour in place of gilt, as it is (mage blue sits close to the arcane of ready things).",
    colors = function(class)
        local c = classColor(class)
        if not c then return {} end
        -- the text lightened toward white until it reads at 7:1 on surface
        local text, surface = { c[1], c[2], c[3] }, T.color["surface"]
        for _ = 1, 50 do
            if ratio(text, surface) >= 7 then break end
            for i = 1, 3 do text[i] = text[i] + (1 - text[i]) * 0.05 end
        end
        return family(c, text)
    end,
})
Themes.Register({
    id = "classhue", name = "Class accent · toned",
    description = "Your class's hue at gilt's weight: softer, and always apart from the signal colours.",
    colors = function(class)
        local c = classColor(class)
        if not c then return {} end
        local h = hue(c[1], c[2], c[3])
        return family(oklch(0.743, 0.05, h), oklch(0.852, 0.043, h))
    end,
})

--------------------------------------------------------------------------------
-- Darker
--------------------------------------------------------------------------------

Themes.Register({
    id = "darker", name = "Darker",
    description = "Warm near-black panels; the world still shows faintly through them.",
    colors = colors({ ["surface"] = "#0B0A0C", ["surface-glass"] = "#0B0A0CF2", ["surface-sunk"] = "#070608",
                      ["surface-raised"] = "#161419", ["track"] = "#1B181C" }),
})
Themes.Register({
    id = "oled", name = "OLED black",
    description = "True black, opaque panels.",
    colors = colors({ ["surface"] = "#000000", ["surface-glass"] = "#000000FF", ["surface-sunk"] = "#000000",
                      ["surface-raised"] = "#0F0E11", ["track"] = "#161418" }),
})

--------------------------------------------------------------------------------
-- From Azeroth's raids (asked 2026-10-18, design "Themes: from Azeroth's
-- raids"): each its own surfaces, accent and ink, the accent moved off the
-- signal colours it would read as (fel, ember, amber, arcane, dispel-curse,
-- ward), the edges' alphas set so a panel's edge keeps its 2.2:1
--------------------------------------------------------------------------------

Themes.Register({
    id = "blacktemple", name = "Black Temple",
    description = "Illidan's fortress: moss-fel green on shadowed violet stone.",
    colors = colors({
        ["surface"] = "#140F1B", ["surface-glass"] = "#140F1BE6", ["surface-sunk"] = "#131019",
        ["surface-raised"] = "#1B1622", ["track"] = "#231E29",
        ["gilt"] = "#7DAF61", ["gilt-text"] = "#B7CD9D", ["gilt-line"] = "#7DAF6161",
        ["gilt-hairline"] = "#7DAF614D", ["gilt-faint"] = "#7DAF6124",
        ["ink"] = "#E8EDE1", ["ink-muted"] = "#9BA192", ["ink-faint"] = "#72776A",
    }),
})
Themes.Register({
    id = "moltencore", name = "Molten Core",
    description = "Lava orange and molten gold on charred rock.",
    colors = colors({
        ["surface"] = "#190D0A", ["surface-glass"] = "#190D0AE6", ["surface-sunk"] = "#160D09",
        ["surface-raised"] = "#211510", ["track"] = "#291D18",
        ["gilt"] = "#BE5A0A", ["gilt-text"] = "#FFDF53", ["gilt-line"] = "#BE5A0A94",
        ["gilt-hairline"] = "#BE5A0A75", ["gilt-faint"] = "#BE5A0A36",
        ["ink"] = "#F6E9DA", ["ink-muted"] = "#AB9B8D", ["ink-faint"] = "#807165",
    }),
})
Themes.Register({
    id = "naxxramas", name = "Naxxramas",
    description = "The necropolis: icy teal and bone on deep slate.",
    colors = colors({
        ["surface"] = "#0A141B", ["surface-glass"] = "#0A141BE6", ["surface-sunk"] = "#0B1318",
        ["surface-raised"] = "#111B22", ["track"] = "#192329",
        ["gilt"] = "#52B1A9", ["gilt-text"] = "#92F1F3", ["gilt-line"] = "#52B1A961",
        ["gilt-hairline"] = "#52B1A94D", ["gilt-faint"] = "#52B1A924",
        ["ink"] = "#F0EBDB", ["ink-muted"] = "#95A1A4", ["ink-faint"] = "#6C777A",
    }),
})
Themes.Register({
    id = "karazhan", name = "Karazhan",
    description = "Medivh's tower: arcane violet and moonlit silver on dark plum.",
    colors = colors({
        ["surface"] = "#1A0D17", ["surface-glass"] = "#1A0D17E6", ["surface-sunk"] = "#180D17",
        ["surface-raised"] = "#22141E", ["track"] = "#281C27",
        ["gilt"] = "#8C6EBD", ["gilt-text"] = "#CACAEB", ["gilt-line"] = "#8C6EBD8A",
        ["gilt-hairline"] = "#8C6EBD6E", ["gilt-faint"] = "#8C6EBD33",
        ["ink"] = "#EBEAF3", ["ink-muted"] = "#A09CA8", ["ink-faint"] = "#77727D",
    }),
})
Themes.Register({
    id = "sunwell", name = "Sunwell",
    description = "The Sunwell Plateau: sun-yellow and white light on warm stone.",
    colors = colors({
        ["surface"] = "#272017", ["surface-glass"] = "#272017E6", ["surface-sunk"] = "#19130C",
        ["surface-raised"] = "#30291F", ["track"] = "#363026",
        ["gilt"] = "#F5DC3A", ["gilt-text"] = "#FFF365", ["gilt-line"] = "#F5DC3A47",
        ["gilt-hairline"] = "#F5DC3A3B", ["gilt-faint"] = "#F5DC3A1A",
        ["ink"] = "#FAF7EA", ["ink-muted"] = "#B5AD9D", ["ink-faint"] = "#8B8273",
    }),
})
