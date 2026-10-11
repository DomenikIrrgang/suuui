-- Core/Root.lua
-- SuuUIRoot: the frame every SuuUI frame on the screen lives in.
--
-- The design is drawn in pixels on a 2560x1440 reference and places each
-- cluster from the screen edge or the centre it belongs to. The root runs at
-- pixel-perfect scale, so one unit is one physical pixel and design sizes can
-- be used as they are: on another resolution the frames keep their size and
-- only the space between clusters changes. ui.scale multiplies that (0 is
-- automatic: 1 up to 1440p, larger on taller screens).
--
-- The root will hold secure frames, so a rescale waits for the end of combat.

local _, ns = ...

local Settings, Events, Combat, Pixel = ns.Settings, ns.Events, ns.Combat, ns.Pixel

local root = CreateFrame("Frame", "SuuUIRoot", UIParent)
root:SetIgnoreParentScale(true)
root:SetAllPoints(UIParent)
ns.Root = root

Settings.Register("ui", {
    scale = 0,             -- 0: automatic; otherwise 0.5 to 2
    reducedMotion = false, -- drop decorative motion, keep every value change
})

Settings.Veto("ui", "scale", function(v)
    if v ~= 0 and (v < 0.5 or v > 2) then return false, "the scale is 0 (automatic) or between 0.5 and 2" end
end, "Root")

-- The scale core.scale = 0 picks: 1 up to 1440p, then in quarter steps.
local function autoScale()
    local h = Pixel.ScreenHeight()
    if h <= 1440 then return 1 end
    return math.floor(h / 1440 * 4 + 0.5) / 4
end

function ns.UserScale()
    local s = Settings.Ready() and Settings.Get("ui", "scale") or 0
    return s == 0 and autoScale() or s
end

local applied

local function apply()
    local scale = Pixel.PerfectScale() * ns.UserScale()
    if scale == applied then return end
    Combat.Run("root:scale", function()
        root:SetScale(scale)
        applied = scale
        Events.Emit("SUUUI_ROOT_SCALED", scale)
    end, "Root")
end

Events.On("SUUUI_SETTINGS_READY", apply, "Root")
Events.On("SUUUI_PIXEL_CHANGED", apply, "Root")
Settings.Watch("ui", "scale", apply, "Root")
