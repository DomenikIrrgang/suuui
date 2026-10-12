-- Units/SwingTimer.lua
-- The swing timer (step 1.3b), directly under your cast bar and exactly as
-- wide: main hand, then off hand; the ranged bar while you shoot. A built-in
-- module written against the public API only.
--
-- Placement (2560x1440 reference): 340px wide, centred, its top space-2 under
-- the cast bar (288px above the bottom edge). Healers have none by default.

local UI, T = SuuUI.UI, SuuUI.Tokens

local M = SuuUI.RegisterModule({
    id = "swingtimer",
    name = "Swing timer",
    description = "When your next swing or shot lands, from the game's own swing timer.",
    api = "0.6",
    defaults = {
        position = { point = "BOTTOM", x = 0, y = 271 },
        inCombatOnly = true,
        hideForHealers = true,
        autoShotWindow = true,
        autoShotNoCast = false, -- learned: this client's Auto Shot fires while moving
    },
})

function M:ApplyAutoShot()
    self.timer:SetAutoShotWindow(self:Get("autoShotWindow") and not self:Get("autoShotNoCast"))
end

function M:UpdateVisibility()
    local f = self.timer
    local pos = self:Get("position")
    -- SuuUI's role (chosen, assigned or from talents), in a group only
    local healer = IsInGroup() and SuuUI.Role() == "HEALER"
    local shown = not pos.hidden
        and not (self:Get("hideForHealers") and healer)
        and not (self:Get("inCombatOnly") and not UI.Flag(UnitAffectingCombat("player")))
    f:SetShown(shown and true or false)
end

local SECTION = {
    id = "swingtimer", label = "Swing timer", category = "Frames", order = 21,
    groups = {
        { title = "When it shows", description = "Without the combat log SuuUI can't see parry haste or clipped swings, so it shows neither.", rows = {
            { key = "inCombatOnly", label = "In combat only", control = "toggle",
              description = "Out of combat the timer is gone." },
            { key = "hideForHealers", label = "Hide when you heal", control = "toggle",
              description = "With the healer role in a group, there is no swing timer." },
            { key = "autoShotWindow", label = "Auto Shot window", control = "toggle",
              description = "The last half second of a shot, when you must stand still, hatched at the end of the ranged bar; it turns amber while you move. It switches itself off if this client's Auto Shot fires while moving.",
              disabled = function()
                  if M:Get("autoShotNoCast") then return true, "This client's Auto Shot fires while you move, so there is no window." end
              end },
        } },
    },
}

function M:OnEnable()
    self.timer = self.timer or UI.SwingTimer(SuuUI.Root, { width = 340, name = "SuuUISwingTimer",
        onNoAutoShotCast = function()
            self:Set("autoShotNoCast", true)
            self:Print("Auto Shot fired on time while you ran, so this client has no stand-still cast: the Auto Shot window is off.")
        end })
    self:ApplyAutoShot()
    self.timer.suuManagedShow = true
    self.timer:Activate()
    self:RegisterMover(self.timer, { key = "position", label = "Swing timer" })
    self:RegisterSettings(SECTION)
    for _, e in ipairs({ "PLAYER_REGEN_DISABLED", "PLAYER_REGEN_ENABLED", "GROUP_ROSTER_UPDATE" }) do
        self:OnGameEvent(e, function() self:UpdateVisibility() end)
    end
    self:On("SUUUI_ROLE_CHANGED", function() self:UpdateVisibility() end)
    for _, key in ipairs({ "inCombatOnly", "hideForHealers", "position" }) do
        self:Watch(key, function() self:UpdateVisibility() end)
    end
    self:Watch("autoShotWindow", function() self:ApplyAutoShot() end)
    self:UpdateVisibility()
end

function M:OnDisable()
    if self.timer then
        self.timer:Deactivate()
        self.timer:Hide()
    end
end
