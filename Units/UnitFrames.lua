-- Units/UnitFrames.lua
-- The player and target frames (step 1.1). A built-in module written against
-- the public API only.
--
-- Placement (tanks and DPS; the healer profile moves them in step 1.8): the
-- player frame's right edge 200px left of the centre line and its top 340px
-- above the bottom edge; the target mirrors it on the right.
--
-- Blizzard's PlayerFrame and TargetFrame are stood down; only a reload brings
-- them back, so turning this module off or on takes effect after a reload.
-- TargetFrame also carries the target's cast bar, its auras and the target of
-- target; SuuUI's own arrive in steps 1.2 to 1.4.

local UI, Motion, T = SuuUI.UI, SuuUI.Motion, SuuUI.Tokens
local S = T.space

local PLAYER_CHILDREN = {
    "healthbar", "healthBar", "HealthBar", "HealthBarsContainer.healthBar", "manabar", "ManaBar",
    "powerBarAlt", "PowerBarAlt", "PlayerFrameContent.PlayerFrameContentMain.HealthBarsContainer.HealthBar",
}
local TARGET_CHILDREN = {
    "healthbar", "healthBar", "HealthBar", "HealthBarsContainer.healthBar", "manabar", "ManaBar",
    "spellbar", "castBar", "auraPools", "BuffFrame", "AurasFrame", "DebuffFrame", "totFrame", "CcRemoverFrame",
}

local M = SuuUI.RegisterModule({
    id = "unitframes",
    name = "Unit frames",
    description = "The player and target frames: the bar is the frame.",
    api = "0.5",
    reloadToToggle = true,
    defaults = {
        playerPosition = { point = "BOTTOM", x = -350, y = 308 },
        targetPosition = { point = "BOTTOM", x = 350, y = 308 },
        fadeOutOfCombat = true,
        showPower = true,
        healthText = "percent",
        nameColor = "game",
        showMeta = true,
        comboPoints = true,
    },
})

--------------------------------------------------------------------------------
-- Combo points: five diamonds over the target frame's right end. Forever's
-- combo points belong to the target, and Blizzard's own display sits on its
-- TargetFrame, so SuuUI draws them. (Not in the design yet.)
--------------------------------------------------------------------------------

local function comboClass()
    local _, class = UnitClass("player")
    if class == "ROGUE" then return true end
    if class == "DRUID" then
        local _, token = UnitPowerType("player")
        return token == "ENERGY"
    end
    return false
end

local function buildCombo(target)
    local f = CreateFrame("Frame", nil, target)
    f:SetSize(5 * 12, 12)
    f:SetPoint("BOTTOMRIGHT", target, "TOPRIGHT", -2, S["space-3"])
    f.pips = {}
    for i = 1, 5 do
        local outer = UI.Diamond(f, 9, "gilt-line", "ARTWORK", 1)
        outer:SetPoint("CENTER", f, "LEFT", 6 + (i - 1) * 12, 0)
        local inner = UI.Diamond(f, 6, "surface-sunk", "ARTWORK", 2)
        inner:SetPoint("CENTER", outer, "CENTER")
        f.pips[i] = { outer = outer, inner = inner }
    end
    function f:Update()
        local shown = M:Get("comboPoints") and comboClass() and UnitExists("target") and UnitCanAttack("player", "target")
        self:SetShown(shown and true or false)
        if not shown then return end
        local n = GetComboPoints and GetComboPoints("player", "target") or 0
        local full = n >= 5
        for i, p in ipairs(self.pips) do
            local on = i <= n
            p.outer:SetVertexColor(UI.RGBA(full and "arcane" or "gilt-line"))
            p.inner:SetVertexColor(UI.RGBA(full and "arcane" or (on and "ink" or "surface-sunk")))
        end
    end
    return f
end

--------------------------------------------------------------------------------
-- Combat-reactive fade and the aggro state
--------------------------------------------------------------------------------

local function playerFull()
    local pct = UnitHealthPercent and CurveConstants and UnitHealthPercent("player", true, CurveConstants.ScaleTo100)
    if issecretvalue and issecretvalue(pct) then return true end -- can't tell: rest on combat state alone
    return (pct or 100) >= 100
end

function M:UpdateFade()
    local resting = self:Get("fadeOutOfCombat") and not UnitAffectingCombat("player") and playerFull()
        and not (self.player:IsMouseOver() or (self.target:IsShown() and self.target:IsMouseOver()))
    local alpha = resting and T.opacity["opacity-ooc"] or 1
    Motion.AlphaTo(self.player, alpha, T.duration["dur-slow"])
    Motion.AlphaTo(self.target, alpha, T.duration["dur-slow"])
end

-- Danger: a non-tank holding aggro in a group. Solo, everyone tanks their own.
function M:UpdateThreat()
    local status = UnitThreatSituation("player")
    local role = UnitGroupRolesAssigned and UnitGroupRolesAssigned("player")
    -- issecretvalue first: a truth test on a secret value would error.
    local danger = IsInGroup() and not issecretvalue(status) and status ~= nil and status >= 2
        and role ~= "TANK"
    self.player:SetState(danger and "danger" or nil, danger and "Aggro" or nil)
end

--------------------------------------------------------------------------------
-- Settings
--------------------------------------------------------------------------------

local function applyOptions(self)
    for _, f in ipairs({ self.player, self.target }) do
        f.opts.power = self:Get("showPower")
        f.opts.healthText = self:Get("healthText")
        f.opts.nameColor = self:Get("nameColor")
        f:Refresh()
    end
    self.target.opts.meta = self:Get("showMeta")
    self.target:Refresh()
    self.combo:Update()
    self:UpdateFade()
end

local SECTION = {
    id = "unitframes", label = "Player & target", category = "Frames", order = 10,
    groups = {
        { title = "Player and target", description = "The bar is the frame: name, state and health inside it, power along its foot.", rows = {
            { key = "fadeOutOfCombat", label = "Fade out of combat", control = "toggle",
              description = "Rest at 60% while you are out of combat at full health; full again in combat or on hover." },
            { key = "showPower", label = "Power line", control = "toggle",
              description = "Mana, rage, energy or focus along the bottom of each bar. Low mana turns it amber." },
            { key = "healthText", label = "Health text", control = "segmented",
              options = { { value = "percent", label = "64%" }, { value = "none", label = "None" } },
              description = "The health percentage at the right end of each bar." },
            { key = "nameColor", label = "Name colour", control = "segmented",
              options = { { value = "game", label = "Class" }, { value = "ink", label = "Plain" } },
              description = "Players in their class colour, hostile and neutral NPCs in their reaction colour." },
        } },
        { title = "Target", rows = {
            { key = "showMeta", label = "Level and classification", control = "toggle",
              description = "After the name: \"60 Elite\", \"?? Boss\"." },
            { key = "comboPoints", label = "Combo points", control = "toggle",
              description = "Five diamonds over the target frame; all arcane at five.",
              disabled = function()
                  local _, class = UnitClass("player")
                  if class ~= "ROGUE" and class ~= "DRUID" then return true, "Only rogues and druids use combo points." end
                  return false
              end },
        } },
    },
}

--------------------------------------------------------------------------------
-- Lifecycle
--------------------------------------------------------------------------------

function M:OnEnable()
    SuuUI.SuppressBlizzard("PlayerFrame", { children = PLAYER_CHILDREN })
    SuuUI.SuppressBlizzard("TargetFrame", { children = TARGET_CHILDREN })
    SuuUI.SuppressBlizzard("ComboFrame", { keepParent = true })

    if not self.player then
        self.player = UI.UnitFrame(SuuUI.Root, "player", { size = "lg", anchor = true, you = true, name = "SuuUIPlayerFrame" })
        self.target = UI.UnitFrame(SuuUI.Root, "target", { size = "lg", meta = true, name = "SuuUITargetFrame" })
        self.target.suuManagedShow = true
        self.combo = buildCombo(self.target)
    end
    RegisterUnitWatch(self.target)
    self.player:Show()

    self.player:Activate()
    self.target:Activate()
    self:RegisterMover(self.player, { key = "playerPosition", label = "Player" })
    self:RegisterMover(self.target, { key = "targetPosition", label = "Target" })
    self:RegisterSettings(SECTION)
    applyOptions(self)

    self.player.onHealth = function() self:UpdateFade() end
    for _, e in ipairs({ "PLAYER_REGEN_DISABLED", "PLAYER_REGEN_ENABLED" }) do
        self:OnGameEvent(e, function() self:UpdateFade() end)
    end
    self.player:HookScript("OnEnter", function() self:UpdateFade() end)
    self.player:HookScript("OnLeave", function() self:UpdateFade() end)
    self.target:HookScript("OnEnter", function() self:UpdateFade() end)
    self.target:HookScript("OnLeave", function() self:UpdateFade() end)

    self:OnUnitEvent("UNIT_THREAT_SITUATION_UPDATE", "player", function() self:UpdateThreat() end)
    self:OnGameEvent("GROUP_ROSTER_UPDATE", function() self:UpdateThreat() end)
    self:OnUnitEvent("UNIT_POWER_UPDATE", "player", function() self.combo:Update() end)
    self:OnUnitEvent("UNIT_DISPLAYPOWER", "player", function() self.combo:Update() end)
    self:OnGameEvent("PLAYER_TARGET_CHANGED", function() self.combo:Update() end)

    for _, key in ipairs({ "fadeOutOfCombat", "showPower", "healthText", "nameColor", "showMeta", "comboPoints" }) do
        self:Watch(key, function() applyOptions(self) end)
    end
    -- Hiding the target frame in edit mode stops it following the target.
    self:Watch("targetPosition", function(pos)
        self:RunOutOfCombat("targetWatch", function()
            if pos.hidden then UnregisterUnitWatch(self.target); self.target:Hide()
            else RegisterUnitWatch(self.target) end
        end)
    end)
    self:UpdateThreat()
end

function M:OnDisable()
    -- Only reached when the module errors: the module toggles on reload.
    if self.player then
        self.player:Deactivate()
        self.target:Deactivate()
        UnregisterUnitWatch(self.target)
        self.player:Hide()
        self.target:Hide()
    end
end
