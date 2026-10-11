-- Core/Fonts.lua
-- One Font object per text style in the tokens (SuuUIFont_body, SuuUIFont_header, ...),
-- so text everywhere is set by style name and changes with the design.
--
-- Sizes are the design's px values used as UI units for now; step 0.5 decides
-- how the design's 2560x1440 reference maps onto other screens.
-- WoW has no letter spacing, so the styles' letterSpacing is not applied.

local _, ns = ...

local Fonts = {}
ns.Fonts = Fonts

local T = ns.Tokens
local objects = {}

local function build(name, style)
    local font = CreateFont("SuuUIFont_" .. name:gsub("%-", "_"))
    font:SetFont(style.file, style.size, "")
    font:SetSpacing(style.lineHeight - style.size)
    font:SetTextColor(unpack(T.color.ink))
    font:SetJustifyH("LEFT")
    return font
end

for name, style in pairs(T.type) do
    objects[name] = build(name, style)
end

-- The Font object for a text style, e.g. Fonts.Get("label").
function Fonts.Get(name)
    return objects[name] or error("SuuUI: unknown text style " .. tostring(name), 2)
end

-- Sets a FontString to a text style.
function Fonts.Apply(fontString, name)
    fontString:SetFontObject(Fonts.Get(name))
end
