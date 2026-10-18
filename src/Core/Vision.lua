-- Core/Vision.lua
-- Colour vision presets (plan 4.1, decided 2026-10-17): Normal, Red-green
-- (protanopia and deuteranopia) and Blue-yellow (tritanopia). A preset
-- replaces SuuUI's signal colours (danger, low health, healing, warnings,
-- the dispel types, reactions…) with the design's values for that vision;
-- shapes, badges and labels never change. Account-wide (it is about your
-- eyes, not a role or a character), applied when the saved settings load,
-- before any frame draws, and again with the theme when it changes
-- (Themes.Apply: the tokens go back to the design's first).
--
-- The values come from the design system's tokens (Tokens.lua's T.vision,
-- generated with the rest): { [mode] = { [token] = { r, g, b, a, hex } } }.
-- Each replaces the token's colour in place, so every table that holds it
-- sees the new one; the glows built on a signal colour follow it.

local _, ns = ...

local T = ns.Tokens

local Vision = {}
ns.Vision = Vision

Vision.MODES = { "normal", "redgreen", "blueyellow" }
Vision.LABEL = { normal = "Normal", redgreen = "Red-green", blueyellow = "Blue-yellow" }
Vision.HINT = {
    normal = "SuuUI's own colours.",
    redgreen = "For protanopia and deuteranopia: red and green signals moved apart.",
    blueyellow = "For tritanopia: blue and yellow signals moved apart.",
}

-- The glows drawn in a signal colour, and the token each follows.
local GLOWS = { ["glow-arcane"] = "arcane", ["glow-ember"] = "ember", ["glow-ward"] = "ward", ["focus-ring"] = "arcane" }

local applied = "normal"

-- Whether the design has given a preset its values yet.
function Vision.Available(mode)
    if mode == "normal" then return true end
    local set = T.vision and T.vision[mode]
    return set ~= nil and next(set) ~= nil
end

-- The preset in effect.
function Vision.Applied()
    return applied
end

function Vision.Apply(mode)
    mode = Vision.Available(mode or "normal") and mode or "normal"
    applied = mode
    if mode == "normal" then return end
    for name, c in pairs(T.vision[mode]) do
        local token = T.color[name]
        if token then
            -- keep the token's own alpha (gilt-line style tokens carry theirs)
            token[1], token[2], token[3] = c[1], c[2], c[3]
            if c[4] then token[4] = c[4] end
            token.hex = c.hex or token.hex
        end
    end
    Vision.SyncGlows()
end

-- The glows drawn in a signal colour take that colour's current value (after
-- colour vision or a theme changed it).
function Vision.SyncGlows()
    for glow, name in pairs(GLOWS) do
        local layers, c = T.shadow and T.shadow[glow], T.color[name]
        for _, layer in ipairs(layers or {}) do
            -- the focus ring's dark inner layer keeps its colour
            if layer.color and not (glow == "focus-ring" and layer.spread == 1) then
                layer.color[1], layer.color[2], layer.color[3] = c[1], c[2], c[3]
            end
        end
    end
end
