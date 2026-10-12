-- Units/UnitFrames.lua
-- The unit frames: player and target (step 1.1), target of target, focus,
-- pet and boss frames (step 1.2). A built-in module written against the
-- public API only.
--
-- Placement follows the cockpit on the 2560x1440 reference (tanks and DPS;
-- the healer profile moves the player and target in step 1.8):
--   player   right edge 200px left of the centre line, top 340px above the bottom
--   target   mirrors it on the right
--   target of target  space-5 right of the target, centred on it
--   focus    in that column, its top 520px above the bottom
--   pet      under the player frame (space-5), right-aligned to it
--   bosses   top right, left of the objective tracker (300px from the right
--            edge, 260px down, level with the tracker), stacked space-5 apart
--
-- Blizzard's frames are stood down; only a reload brings them back, so this
-- module turns off or on after a reload.

local UI, Motion, T = SuuUI.UI, SuuUI.Motion, SuuUI.Tokens
local S = T.space

local BAR_CHILDREN = { "healthbar", "healthBar", "HealthBar", "HealthBarsContainer.healthBar", "manabar", "ManaBar" }
local function children(extra)
    local list = { unpack(BAR_CHILDREN) }
    for _, c in ipairs(extra or {}) do list[#list + 1] = c end
    return list
end

local M = SuuUI.RegisterModule({
    id = "unitframes",
    name = "Unit frames",
    description = "Player, target, target of target, focus, pet and boss frames: the bar is the frame.",
    api = "0.5",
    reloadToToggle = true,
    defaults = {
        playerPosition = { point = "BOTTOM", x = -350, y = 308 },
        targetPosition = { point = "BOTTOM", x = 350, y = 308 },
        totPosition = { point = "BOTTOM", x = 582, y = 312 },
        focusPosition = { point = "BOTTOM", x = 612, y = 492 },
        petPosition = { point = "BOTTOM", x = -300, y = 268 },
        bossPosition = { point = "TOPRIGHT", x = -300, y = -260 },
        showToT = true,
        showFocus = true,
        showPet = true,
        showBoss = true,
        fadeOutOfCombat = true,
        showPower = true,
        healthText = "percent",
        nameColor = "game",
        showMeta = true,
        comboPoints = true,
        debuffBadges = "all",   -- your frame: "all" debuff types, "removable", "off"
    },
})

-- Every frame this module draws. `show` names the setting that turns it off.
local FRAMES = {
    { key = "player", unit = "player", label = "Player", position = "playerPosition",
      -- No "you" badge here (the design has one): the player frame is always you.
      -- Target of target keeps it, where it tells you a mob is on you.
      opts = { size = "lg", anchor = true, name = "SuuUIPlayerFrame" } },
    { key = "target", unit = "target", label = "Target", position = "targetPosition", watch = true,
      opts = { size = "lg", meta = true, name = "SuuUITargetFrame" } },
    { key = "tot", unit = "targettarget", label = "Target of target", position = "totPosition", watch = true, show = "showToT",
      opts = { size = "sm", width = "bar-tot", power = false, youWhenPlayer = true, poll = 0.2, name = "SuuUITargetTargetFrame" } },
    { key = "focus", unit = "focus", label = "Focus", position = "focusPosition", watch = true, show = "showFocus",
      opts = { size = "md", meta = true, name = "SuuUIFocusFrame" } },
    { key = "pet", unit = "pet", label = "Pet", position = "petPosition", watch = true, show = "showPet",
      opts = { size = "md", meta = "family", name = "SuuUIPetFrame" } },
}

local BOSSES = 5

--------------------------------------------------------------------------------
-- Blizzard's frames
--------------------------------------------------------------------------------

local function standDownBlizzard()
    SuuUI.SuppressBlizzard("PlayerFrame", { children = children({ "powerBarAlt", "PowerBarAlt" }) })
    SuuUI.SuppressBlizzard("TargetFrame", { children = children({ "spellbar", "castBar", "BuffFrame", "AurasFrame", "DebuffFrame", "totFrame", "CcRemoverFrame" }) })
    SuuUI.SuppressBlizzard("TargetFrameToT", { keepParent = true })
    SuuUI.SuppressBlizzard("ComboFrame", { keepParent = true })
    if M:Get("showFocus") then
        SuuUI.SuppressBlizzard("FocusFrame", { children = children({ "spellbar", "castBar", "BuffFrame", "AurasFrame", "totFrame" }) })
    end
    if M:Get("showPet") then
        SuuUI.SuppressBlizzard("PetFrame", { children = children() })
    end
    if M:Get("showBoss") then
        SuuUI.SuppressBlizzard("BossTargetFrameContainer")
        for i = 1, BOSSES do
            SuuUI.SuppressBlizzard("Boss" .. i .. "TargetFrame", { children = children({ "spellbar", "castBar", "BuffFrame", "AurasFrame" }) })
        end
    end
end

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

-- Step curves: pip i is lit from i points up (UnitPowerPercent's 0-1 input).
local pipCurves = {}
local function pipCurve(i)
    if not pipCurves[i] then
        local c = C_CurveUtil.CreateCurve()
        c:SetType(Enum.LuaCurveType.Step)
        c:AddPoint(0, 0)
        c:AddPoint((i - 0.5) / 5, 1)
        pipCurves[i] = c
    end
    return pipCurves[i]
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
        local lit = UI.Diamond(f, 6, "ink", "ARTWORK", 3)
        lit:SetPoint("CENTER", outer, "CENTER")
        f.pips[i] = { outer = outer, inner = inner, lit = lit }
    end
    function f:Update()
        local shown = M:Get("comboPoints") and comboClass() and UnitExists("target") and UI.Flag(UnitCanAttack("player", "target"))
        self:SetShown(shown and true or false)
        if not shown then return end
        local n = GetComboPoints and GetComboPoints("player", "target")
        if issecretvalue(n) then
            -- Hidden in combat: each pip's alpha comes from an engine step curve.
            local cp = Enum.PowerType.ComboPoints
            for i, p in ipairs(self.pips) do
                p.outer:SetVertexColor(UI.RGBA("gilt-line"))
                p.inner:SetVertexColor(UI.RGBA("surface-sunk"))
                p.lit:SetVertexColor(UI.RGBA("ink"))
                p.lit:SetAlpha(UnitPowerPercent("player", cp, false, pipCurve(i)))
            end
            return
        end
        n = n or 0
        local full = n >= 5
        for i, p in ipairs(self.pips) do
            local on = i <= n
            p.outer:SetVertexColor(UI.RGBA(full and "arcane" or "gilt-line"))
            p.inner:SetVertexColor(UI.RGBA("surface-sunk"))
            p.lit:SetVertexColor(UI.RGBA(full and "arcane" or "ink"))
            p.lit:SetAlpha(on and 1 or 0)
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

-- Out of combat at full health, the frames rest at opacity-ooc. Boss frames
-- exist only in encounters and never fade.
function M:UpdateFade()
    local hovered = false
    for _, d in ipairs(FRAMES) do
        local f = self.frames[d.key]
        if f:IsVisible() and f:IsMouseOver() then hovered = true end
    end
    local resting = self:Get("fadeOutOfCombat") and not UI.Flag(UnitAffectingCombat("player")) and playerFull() and not hovered
    local alpha = resting and T.opacity["opacity-ooc"] or 1
    for _, d in ipairs(FRAMES) do
        Motion.AlphaTo(self.frames[d.key], alpha, T.duration["dur-slow"])
    end
end

-- Danger: a non-tank holding aggro in a group. Solo, everyone tanks their own.
function M:UpdateThreat()
    local status = UnitThreatSituation("player")
    local role = UnitGroupRolesAssigned and UnitGroupRolesAssigned("player")
    -- issecretvalue first: a truth test on a secret value would error.
    local danger = IsInGroup() and not issecretvalue(status) and status ~= nil and status >= 2
        and role ~= "TANK"
    self.frames.player:SetState(danger and "danger" or nil, danger and "Aggro" or nil)
end

--------------------------------------------------------------------------------
-- Showing, hiding and options
--------------------------------------------------------------------------------

-- A unit frame follows its unit (RegisterUnitWatch) unless it is turned off
-- in the settings or hidden in edit mode.
local function follow(self, frame, on)
    self:RunOutOfCombat("watch:" .. frame:GetName(), function()
        if on then
            RegisterUnitWatch(frame)
        else
            UnregisterUnitWatch(frame)
            frame:Hide()
        end
    end)
end

function M:UpdateVisibility()
    for _, d in ipairs(FRAMES) do
        if d.watch then
            local pos = self:Get(d.position)
            follow(self, self.frames[d.key], not pos.hidden and (not d.show or self:Get(d.show)))
        end
    end
    local bossOn = self:Get("showBoss") and not self:Get("bossPosition").hidden
    for i = 1, BOSSES do follow(self, self.bosses[i], bossOn) end
end

function M:ApplyOptions()
    for _, f in pairs(self.allFrames) do
        f.opts.power = (f.opts.size ~= "sm") and self:Get("showPower")
        f.opts.healthText = self:Get("healthText")
        f.opts.nameColor = self:Get("nameColor")
        if f.metaKind == "level" then f.opts.meta = self:Get("showMeta") end
        if f.active then f:Refresh() end
    end
    self.combo:Update()
    self:UpdateFade()
end

--------------------------------------------------------------------------------
-- Settings
--------------------------------------------------------------------------------

local SECTION = {
    id = "unitframes", label = "Unit frames", category = "Frames", order = 10,
    groups = {
        { title = "Frames", description = "Turning a frame off brings Blizzard's back after a reload.", rows = {
            { key = "showToT", label = "Target of target", control = "toggle", description = "Right of the target, centred on it." },
            { key = "showFocus", label = "Focus", control = "toggle", description = "Right of centre, above the target of target." },
            { key = "showPet", label = "Pet", control = "toggle", description = "Under the player frame, with its focus or mana." },
            { key = "showBoss", label = "Boss frames", control = "toggle", description = "Top right, left of the tracker, one per boss." },
        } },
        { title = "Every frame", description = "The bar is the frame: name, state and health inside it, power along its foot.", rows = {
            { key = "fadeOutOfCombat", label = "Fade out of combat", control = "toggle",
              description = "Rest at 60% while you are out of combat at full health; full again in combat or on hover." },
            { key = "showPower", label = "Power line", control = "toggle",
              description = "Mana, rage, energy or focus along the bottom of each bar. Low mana turns it amber." },
            { key = "healthText", label = "Health text", control = "segmented",
              options = { { value = "percent", label = "64%" }, { value = "value", label = "8.5k" },
                          { value = "both", label = "8.5k · 64%" }, { value = "none", label = "None" } },
              description = "At the right end of each bar: the health percentage, the current health, or both." },
            { key = "nameColor", label = "Name colour", control = "segmented",
              options = { { value = "game", label = "Class" }, { value = "ink", label = "Plain" } },
              description = "Players in their class colour, hostile and neutral NPCs in their reaction colour." },
            { key = "showMeta", label = "Level and classification", control = "toggle",
              description = "After the name on the target, focus and boss frames: \"60 Elite\", \"?? Boss\"." },
        } },
        { title = "Debuffs on you", rows = {
            { key = "debuffBadges", label = "Debuff badges", control = "segmented",
              options = { { value = "all", label = "Every type" }, { value = "removable", label = "Only what you can remove" }, { value = "off", label = "Off" } },
              description = "Magic, Curse, Poison, Disease on your frame as a badge and border, in combat too." },
        } },
        { title = "Combo points", rows = {
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

local function build(self)
    self.frames, self.allFrames = {}, {}
    for _, d in ipairs(FRAMES) do
        local f = UI.UnitFrame(SuuUI.Root, d.unit, d.opts)
        f.metaKind = d.opts.meta == true and "level" or nil
        if d.watch then f.suuManagedShow = true end
        self.frames[d.key] = f
        self.allFrames[d.key] = f
    end
    -- The boss stack: one holder, moved as one in edit mode.
    local holder = CreateFrame("Frame", "SuuUIBossFrames", SuuUI.Root)
    local w, h = UI.Size("bar-md"), UI.Size("unit-md")
    -- each boss leaves room under its bar for its cast (space-1, cast-sm)
    local pitch = h + S["space-1"] + UI.Size("cast-sm") + S["space-5"]
    holder:SetSize(w, BOSSES * pitch - S["space-5"])
    self.bossHolder, self.bosses = holder, {}
    for i = 1, BOSSES do
        local f = UI.UnitFrame(holder, "boss" .. i, { size = "md", meta = true, name = "SuuUIBoss" .. i .. "Frame" })
        f.metaKind = "level"
        f:SetPoint("TOPRIGHT", holder, "TOPRIGHT", 0, -(i - 1) * pitch)
        self.bosses[i] = f
        self.allFrames["boss" .. i] = f
    end
    self.combo = buildCombo(self.frames.target)
end

function M:OnEnable()
    standDownBlizzard()
    if not self.frames then build(self) end

    self.frames.player:Show()
    for _, f in pairs(self.allFrames) do f:Activate() end
    -- A frame turned off in the settings gets no mover in edit mode.
    for _, d in ipairs(FRAMES) do
        self:RegisterMover(self.frames[d.key], { key = d.position, label = d.label,
            enabled = d.show and function() return self:Get(d.show) end or nil })
        if d.show then self:Watch(d.show, SuuUI.EditMode.Refresh) end
    end
    self:RegisterMover(self.bossHolder, { key = "bossPosition", label = "Boss frames",
        enabled = function() return self:Get("showBoss") end })
    self:Watch("showBoss", SuuUI.EditMode.Refresh)
    -- Published, so other modules (cast bars, auras) and plugins can attach to them.
    for _, d in ipairs(FRAMES) do SuuUI.PublishAnchor(d.unit, self.frames[d.key]) end
    for i = 1, BOSSES do SuuUI.PublishAnchor("boss" .. i, self.bosses[i]) end
    self.bossHolder.suuManagedShow = true
    self:RegisterSettings(SECTION)
    self:UpdateVisibility()
    self:ApplyOptions()

    local player = self.frames.player
    player.onHealth = function() self:UpdateFade() end
    for _, e in ipairs({ "PLAYER_REGEN_DISABLED", "PLAYER_REGEN_ENABLED" }) do
        self:OnGameEvent(e, function() self:UpdateFade() end)
    end
    for _, d in ipairs(FRAMES) do
        local f = self.frames[d.key]
        f:HookScript("OnEnter", function() self:UpdateFade() end)
        f:HookScript("OnLeave", function() self:UpdateFade() end)
    end

    self:OnUnitEvent("UNIT_THREAT_SITUATION_UPDATE", "player", function() self:UpdateThreat() end)
    self:OnGameEvent("GROUP_ROSTER_UPDATE", function() self:UpdateThreat() end)
    self:OnUnitEvent("UNIT_POWER_UPDATE", "player", function() self.combo:Update() end)
    self:OnUnitEvent("UNIT_DISPLAYPOWER", "player", function() self.combo:Update() end)
    self:OnGameEvent("PLAYER_TARGET_CHANGED", function() self.combo:Update() end)

    for _, key in ipairs({ "fadeOutOfCombat", "showPower", "healthText", "nameColor", "showMeta", "comboPoints" }) do
        self:Watch(key, function() self:ApplyOptions() end)
    end
    for _, key in ipairs({ "showToT", "showFocus", "showPet", "showBoss", "targetPosition", "totPosition",
                           "focusPosition", "petPosition", "bossPosition" }) do
        self:Watch(key, function() self:UpdateVisibility() end)
    end
    self:UpdateThreat()
    self:RunOutOfCombat("debuffBadges", function() self.frames.player:SetDispelBadges(self:Get("debuffBadges")) end)
    self:Watch("debuffBadges", function()
        self:RunOutOfCombat("debuffBadges", function() self.frames.player:SetDispelBadges(self:Get("debuffBadges")) end)
    end)
end

function M:OnDisable()
    -- Only reached when the module errors: the module toggles on reload.
    if self.frames then
        -- Withdraw the anchors, so nothing stays attached to frames that are gone.
        for _, d in ipairs(FRAMES) do SuuUI.PublishAnchor(d.unit, nil) end
        for i = 1, BOSSES do SuuUI.PublishAnchor("boss" .. i, nil) end
        for _, f in pairs(self.allFrames) do
            f:Deactivate()
            UnregisterUnitWatch(f)
            f:Hide()
        end
    end
end
