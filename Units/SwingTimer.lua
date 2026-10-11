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
    },
})

function M:UpdateVisibility()
    local f = self.timer
    local pos = self:Get("position")
    local role = UnitGroupRolesAssigned and UnitGroupRolesAssigned("player")
    local healer = not issecretvalue(role) and role == "HEALER"
    local shown = not pos.hidden
        and not (self:Get("hideForHealers") and healer)
        and not (self:Get("inCombatOnly") and not UI.Flag(UnitAffectingCombat("player")))
    f:SetShown(shown and true or false)
end

local SECTION = {
    id = "swingtimer", label = "Swing timer", category = "Frames", order = 21,
    groups = {
        { title = "Swing timer", description = "Without the combat log SuuUI can't see parry haste or clipped swings, so it shows neither.", rows = {
            { key = "inCombatOnly", label = "In combat only", control = "toggle",
              description = "Out of combat the timer is gone." },
            { key = "hideForHealers", label = "Hide when you heal", control = "toggle",
              description = "With the healer role in a group, there is no swing timer." },
        } },
    },
}

function M:OnEnable()
    self.timer = self.timer or UI.SwingTimer(SuuUI.Root, { width = 340, name = "SuuUISwingTimer" })
    self.timer.suuManagedShow = true
    self.timer:Activate()
    self:RegisterMover(self.timer, { key = "position", label = "Swing timer" })
    self:RegisterSettings(SECTION)
    for _, e in ipairs({ "PLAYER_REGEN_DISABLED", "PLAYER_REGEN_ENABLED", "GROUP_ROSTER_UPDATE", "PLAYER_ROLES_ASSIGNED" }) do
        self:OnGameEvent(e, function() self:UpdateVisibility() end)
    end
    for _, key in ipairs({ "inCombatOnly", "hideForHealers", "position" }) do
        self:Watch(key, function() self:UpdateVisibility() end)
    end
    self:UpdateVisibility()
end

function M:OnDisable()
    if self.timer then
        self.timer:Deactivate()
        self.timer:Hide()
    end
end
