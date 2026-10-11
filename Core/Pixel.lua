-- Core/Pixel.lua
-- Physical pixels. WoW lays out in UI units: 768 of them span the screen's
-- height at a scale of 1. A 1px hairline has to be one physical pixel at
-- whatever scale its frame ends up with.
--
-- Emits SUUUI_PIXEL_CHANGED only when the screen height or UIParent's scale
-- really changed, not on every CVar write. (Step 0.5 adds SuuUI's own root
-- frame and its rescale, which waits for the end of combat.)

local _, ns = ...

local Pixel = {}
ns.Pixel = Pixel

local Events = ns.Events

function Pixel.ScreenHeight()
    local _, h = GetPhysicalScreenSize()
    return h
end

-- The effective scale at which one UI unit is one physical pixel.
function Pixel.PerfectScale()
    return 768 / Pixel.ScreenHeight()
end

-- One physical pixel, in `region`'s own units (UIParent by default).
function Pixel.Size(region)
    return Pixel.PerfectScale() / (region or UIParent):GetEffectiveScale()
end

-- `value` rounded to whole physical pixels in `region`'s units.
function Pixel.Snap(value, region)
    local p = Pixel.Size(region)
    return math.floor(value / p + 0.5) * p
end

local lastHeight, lastScale

local function check()
    local h, s = Pixel.ScreenHeight(), UIParent:GetEffectiveScale()
    if h == lastHeight and s == lastScale then return end
    lastHeight, lastScale = h, s
    Events.Emit("SUUUI_PIXEL_CHANGED", h, s)
end

Events.OnGame("PLAYER_LOGIN", check, "Pixel")
Events.OnGame("UI_SCALE_CHANGED", check, "Pixel")
Events.OnGame("DISPLAY_SIZE_CHANGED", check, "Pixel")
Events.OnGame("CVAR_UPDATE", function(_, name)
    if name == "uiScale" or name == "useUiScale" then check() end
end, "Pixel")

ns.RegisterCommand("pixel", "Show the screen size, UI scale and the size of one pixel.", function()
    local w, h = GetPhysicalScreenSize()
    ns.Print(("Screen %dx%d, UIParent scale %.3f, pixel-perfect scale %.3f, 1px = %.3f UI units")
        :format(w, h, UIParent:GetEffectiveScale(), Pixel.PerfectScale(), Pixel.Size()))
end)
