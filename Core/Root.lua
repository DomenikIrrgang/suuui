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
    hideIssueReporter = false, -- the beta's bug report button (Blizzard_PTRFeedback)
})

Settings.Veto("ui", "scale", function(v)
    if v ~= 0 and (v < 0.5 or v > 2) then return false, "the scale is 0 (automatic) or between 0.5 and 2" end
end, "Root")

-- The scale ui.scale = 0 picks: 1 up to 1440p, then in quarter steps.
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

-- The scale is read when the job runs, so a change queued in combat and then
-- changed back still ends on the latest value.
local function apply()
    Combat.Run("root:scale", function()
        local scale = Pixel.PerfectScale() * ns.UserScale()
        if scale == applied then return end
        root:SetScale(scale)
        applied = scale
        Events.Emit("SUUUI_ROOT_SCALED", scale)
    end, "Root")
end

Events.On("SUUUI_SETTINGS_READY", apply, "Root")
Events.On("SUUUI_PIXEL_CHANGED", apply, "Root")
Settings.Watch("ui", "scale", apply, "Root")

-- The beta's issue reporter (Blizzard_PTRFeedback's PTR_IssueReporter, the
-- bug report button): kept hidden while ui.hideIssueReporter is on, shown
-- again when it's turned off. It may load after SuuUI: looked for again on
-- ADDON_LOADED.
local reporterHooked = false
local function issueReporter()
    local f = _G.PTR_IssueReporter
    if not f then return end
    local hide = ns.Settings.Get("ui", "hideIssueReporter")
    if not reporterHooked then
        reporterHooked = true
        hooksecurefunc(f, "Show", function(self)
            if ns.Settings.Get("ui", "hideIssueReporter") then self:Hide() end
        end)
    end
    if hide then f:Hide() else f:Show() end
end
ns.Events.OnGame("ADDON_LOADED", function(_, name) if name == "Blizzard_PTRFeedback" then issueReporter() end end, "Root")
ns.Events.OnGame("PLAYER_LOGIN", issueReporter, "Root")
ns.Settings.Watch("ui", "hideIssueReporter", issueReporter, "Root")

