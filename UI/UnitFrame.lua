-- UI/UnitFrame.lua
-- The unit frame: the bar is the frame. One bar with the unit's name, meta,
-- state badge and health % inside it, its power as a line along the bottom.
--
--   local f = UI.UnitFrame(parent, "target", {
--       size = "lg",        -- lg (player, target), md (party, focus, boss, pet), sm (raid, target of target)
--       width = nil,        -- default: the size's bar token
--       anchor = false,     -- the player frame's double gilt frame and two diamonds
--       you = false,        -- the "you" badge
--       meta = false,       -- level and classification after the name
--       power = true,       -- the power line
--       healthText = "percent", -- or "none"
--       nameColor = "game", -- class colour (players) or reaction colour (NPCs); "ink" for plain names
--       secure = true,      -- a SecureUnitButtonTemplate button: left click targets, right click opens the menu
--       name = "SuuUIPlayerFrame",
--   })
--   f:Activate()   -- starts listening to the unit's events and draws it
--   f:Deactivate()
--   f:SetState(tone, word)   -- a state border and badge ("danger", "Aggro"); nil clears it
--   f:Refresh()
--
-- Secret values: health, max health, power, incoming heals and absorbs go
-- straight to StatusBars, which take them as they are. The health % text is
-- UnitHealthPercent through CurveConstants.ScaleTo100, which the engine
-- evaluates and returns as a clean 0-100. The low-health fill and low-mana
-- amber are second bars whose alpha comes from a step curve evaluated by the
-- engine, so no Lua code ever compares a value that might be secret.

local _, ns = ...

local UI, T, Events, Fault = ns.UI, ns.Tokens, ns.Events, ns.Fault
local S = T.space

local WHITE = "Interface\\Buttons\\WHITE8X8"
local HATCH = "Interface\\AddOns\\SuuUI\\Media\\Textures\\Hatch.tga"
local ROLE_ICON = {
    TANK = "Interface\\AddOns\\SuuUI\\Media\\Textures\\RoleTank.tga",
    HEALER = "Interface\\AddOns\\SuuUI\\Media\\Textures\\RoleHealer.tga",
    DAMAGER = "Interface\\AddOns\\SuuUI\\Media\\Textures\\RoleDamage.tga",
}

local SIZES = {
    lg = { height = "unit-lg", width = "bar-lg", name = "unit-name-lg", role = 14, pad = S["space-4"], gap = S["space-3"] },
    md = { height = "unit-md", width = "bar-md", name = "unit-name", role = 12, pad = S["space-4"], gap = S["space-3"] },
    sm = { height = "unit-sm", width = "bar-sm", name = "unit-name-sm", role = 10, pad = S["space-3"], gap = S["space-2"] },
}

local LOW_HEALTH = 0.35 -- the design's lowAt
local LOW_MANA = 0.25
local GHOST_HOLD = 0.15
local INTERPOLATE = Enum.StatusBarInterpolation and Enum.StatusBarInterpolation.ExponentialEaseOut

local POWER_TOKEN = { MANA = "mana", RAGE = "rage", ENERGY = "energy", FOCUS = "focus" }

local isSecret = issecretvalue or function() return false end

-- nil becomes 0; a secret value passes through untouched (never `v or 0`,
-- which would test a secret value's truth).
local function amount(v)
    if isSecret(v) then return v end
    return v or 0
end

--------------------------------------------------------------------------------
-- Curves: built once, evaluated by the engine with the unit's health or power.
--------------------------------------------------------------------------------

local curves = {}

-- A step curve that is 1 below `at` (a 0-1 fraction) and 0 from it up.
local function belowCurve(at)
    if not curves[at] then
        local c = C_CurveUtil.CreateCurve()
        c:SetType(Enum.LuaCurveType.Step)
        c:AddPoint(0, 1)
        c:AddPoint(at, 0)
        curves[at] = c
    end
    return curves[at]
end

local function healthPercent(unit)
    if UnitHealthPercent and CurveConstants then
        return UnitHealthPercent(unit, true, CurveConstants.ScaleTo100)
    end
end

--------------------------------------------------------------------------------
-- Building
--------------------------------------------------------------------------------

local UF = {}

local function bar(f, level, color)
    local b = CreateFrame("StatusBar", nil, f.inner)
    b:SetStatusBarTexture(WHITE)
    b:GetStatusBarTexture():SetSnapToPixelGrid(false)
    b:SetFrameLevel(f:GetFrameLevel() + level)
    b:SetMinMaxValues(0, 1)
    b:SetValue(0)
    if color then b:SetStatusBarColor(UI.RGBA(color)) end
    return b
end

local function gradient(b, deep, fill)
    local r1, g1, b1, a1 = UI.RGBA(deep)
    local r2, g2, b2, a2 = UI.RGBA(fill)
    b:GetStatusBarTexture():SetGradient("HORIZONTAL", CreateColor(r1, g1, b1, a1), CreateColor(r2, g2, b2, a2))
end

function UI.UnitFrame(parent, unit, opts)
    opts = opts or {}
    local size = SIZES[opts.size or "md"]
    local f = CreateFrame("Button", opts.name, parent, opts.secure ~= false and "SecureUnitButtonTemplate" or nil)
    Mixin(f, UF)
    f.unit, f.opts, f.size = unit, opts, size
    local w, h = UI.Size(opts.width or size.width), UI.Size(size.height)
    f:SetSize(w, h)

    if opts.secure ~= false then
        f:SetAttribute("unit", unit)
        f:SetAttribute("*type1", "target")
        f:SetAttribute("*type2", "togglemenu")
        f:RegisterForClicks("AnyUp")
    end
    f:SetScript("OnEnter", function(self)
        GameTooltip_SetDefaultAnchor(GameTooltip, self)
        GameTooltip:SetUnit(self.unit)
        GameTooltip:Show()
    end)
    f:SetScript("OnLeave", function() GameTooltip:Hide() end)

    -- The ground and, clipped inside the 1px border, the bars.
    f.ground = UI.Fill(f, "surface-sunk")
    f.ground:SetAllPoints()
    f.inner = CreateFrame("Frame", nil, f)
    f.inner:SetPoint("TOPLEFT", 1, -1)
    f.inner:SetPoint("BOTTOMRIGHT", -1, 1)
    f.inner:SetClipsChildren(true)

    f.ghost = bar(f, 1, "ghost")
    f.ghost:SetAllPoints(f.inner)
    f.health = bar(f, 2)
    f.health:SetAllPoints(f.inner)
    gradient(f.health, "unit-fill-deep", "unit-fill")
    f.healthLow = bar(f, 3)
    f.healthLow:SetAllPoints(f.inner)
    gradient(f.healthLow, "unit-fill-low-deep", "unit-fill-low")
    f.healthLow:SetAlpha(0)

    -- Incoming heals, then absorbs, each starting where the one before ends.
    f.incoming = bar(f, 4, "fel-incoming")
    f.incoming:SetPoint("TOPLEFT", f.health:GetStatusBarTexture(), "TOPRIGHT")
    f.incoming:SetPoint("BOTTOMLEFT", f.health:GetStatusBarTexture(), "BOTTOMRIGHT")
    f.incoming:SetWidth(w - 2)
    f.absorb = bar(f, 5)
    f.absorb:SetStatusBarTexture(HATCH)
    local hatch = f.absorb:GetStatusBarTexture()
    hatch:SetHorizTile(true)
    hatch:SetVertTile(true)
    f.absorb:SetStatusBarColor(UI.RGBA("ward-absorb"))
    f.absorb:SetPoint("TOPLEFT", f.incoming:GetStatusBarTexture(), "TOPRIGHT")
    f.absorb:SetPoint("BOTTOMLEFT", f.incoming:GetStatusBarTexture(), "BOTTOMRIGHT")
    f.absorb:SetWidth(w - 2)

    -- The power line: along the bottom; inside the anchor frame on the player.
    f.power = bar(f, 6, "mana")
    f.powerLow = bar(f, 7, "amber")
    f.powerLow:SetAlpha(0)
    local inset = opts.anchor and 3 or 0
    for _, b in ipairs({ f.power, f.powerLow }) do
        b:ClearAllPoints()
        b:SetPoint("BOTTOMLEFT", f.inner, "BOTTOMLEFT", inset, inset)
        b:SetPoint("BOTTOMRIGHT", f.inner, "BOTTOMRIGHT", -inset, inset)
        b:SetHeight(S["space-1"])
    end

    -- Everything drawn over the bars: border, anchor frame, text, badges.
    local o = CreateFrame("Frame", nil, f)
    o:SetAllPoints()
    o:SetFrameLevel(f:GetFrameLevel() + 9)
    f.over = o
    f.border = UI.Border(o, opts.anchor and "gilt-line" or "gilt-hairline")
    if opts.anchor then
        local rings = T.shadow["inset-anchor"]
        UI.Border(o, rings[1].color, { width = rings[1].spread, inset = 1 })
        UI.Border(o, rings[2].color, { width = 1, inset = 1 + rings[1].spread })
        UI.Diamond(o, 7, "gilt"):SetPoint("CENTER", f, "TOPLEFT", 0, 0)
        UI.Diamond(o, 7, "gilt"):SetPoint("CENTER", f, "BOTTOMRIGHT", 0, 0)
    end
    f.glow = UI.Shadow(f, "glow-ember")
    f.glow:SetShown(false)

    -- The row (marker, name, meta, badges) is clipped where the health % slot
    -- begins, so a long name never runs into it, even when it is secret.
    f.row = CreateFrame("Frame", nil, o)
    f.row:SetPoint("TOPLEFT", size.pad, 0)
    f.row:SetPoint("BOTTOMRIGHT", -(size.pad + (opts.size == "sm" and 0 or 34 + size.gap)), 0)
    f.row:SetClipsChildren(true)
    f.role = o:CreateTexture(nil, "OVERLAY")
    f.role:SetSize(size.role, size.role)
    f.classDot = UI.Diamond(o, opts.size == "sm" and 4 or 5, "ink")
    f.name = UI.Text(f.row, size.name, "ink")
    f.name:SetShadowed(true)
    f.name:SetWordWrap(false)
    f.meta = UI.Text(f.row, "caption", "ink")
    f.meta:SetShadowed(true)
    f.badge = UI.StateBadge(f.row, "danger", "")
    f.badge:Hide()
    f.you = UI.StateBadge(f.row, "neutral", "you")
    f.you:SetShown(opts.you == true)
    f.right = UI.Text(o, "numeric", "ink")
    f.right:SetShadowed(true)
    f.right:SetPoint("RIGHT", -size.pad, 0)
    f.rightW = 0
    return f
end

--------------------------------------------------------------------------------
-- Drawing
--------------------------------------------------------------------------------

function UF:UpdateHealth(instant)
    local u = self.unit
    local dead = UnitIsDeadOrGhost(u)
    local max, cur = UnitHealthMax(u), UnitHealth(u)
    for _, b in ipairs({ self.health, self.healthLow, self.ghost, self.incoming, self.absorb }) do
        b:SetMinMaxValues(0, amount(max))
    end
    cur = dead and 0 or amount(cur)
    self.health:SetValue(cur)
    self.healthLow:SetValue(cur)
    self.healthLow:SetAlpha(dead and 0 or amount(UnitHealthPercent(u, true, belowCurve(LOW_HEALTH))))

    -- The ghost trails the fill: after a hold, the engine eases it down.
    if instant or not INTERPOLATE then
        if self.ghostTimer then self.ghostTimer:Cancel() self.ghostTimer = nil end
        self.ghost:SetValue(cur)
    else
        self.ghostValue = cur
        if not self.ghostTimer then
            self.ghostTimer = C_Timer.NewTimer(GHOST_HOLD, function()
                self.ghostTimer = nil
                self.ghost:SetValue(self.ghostValue, INTERPOLATE)
            end)
        end
    end

    self.incoming:SetValue(dead and 0 or amount(UnitGetIncomingHeals and UnitGetIncomingHeals(u)))
    self.absorb:SetValue(dead and 0 or amount(UnitGetTotalAbsorbs and UnitGetTotalAbsorbs(u)))

    if dead then
        self.right:SetStyle("caption")
        self.right:SetColor("ink-muted")
        self.right:SetValue(UnitIsGhost(u) and "Ghost" or "Dead")
    elseif self.opts.healthText ~= "none" and self.opts.size ~= "sm" then
        self.right:SetStyle("numeric")
        self.right:SetColor("ink")
        local pct = healthPercent(u)
        if isSecret(pct) then
            self.right:SetFormattedText("%d%%", pct)
            self.right.value = nil
        else
            self.right:SetValue(pct and ("%d%%"):format(pct + 0.5) or "")
        end
    else
        self.right:SetValue("")
    end
    if self.dead ~= dead then
        self.dead = dead
        self:UpdateIdentity()
    end
    if self.onHealth then self.onHealth(self) end
end

function UF:UpdatePower()
    local u = self.unit
    if self.opts.power == false then
        self.power:Hide()
        self.powerLow:Hide()
        return
    end
    local pType, token = UnitPowerType(u)
    local max = UnitPowerMax(u, pType)
    local shown = isSecret(max) or (max or 0) > 0
    self.power:SetShown(shown)
    self.powerLow:SetShown(shown and token == "MANA")
    if not shown then return end
    self.power:SetStatusBarColor(UI.RGBA(POWER_TOKEN[token] or "mana"))
    self.power:SetMinMaxValues(0, amount(max))
    self.power:SetValue(amount(UnitPower(u, pType)))
    if token == "MANA" then
        self.powerLow:SetMinMaxValues(0, amount(max))
        self.powerLow:SetValue(amount(UnitPower(u, pType)))
        self.powerLow:SetAlpha(amount(UnitPowerPercent(u, pType, true, belowCurve(LOW_MANA))))
    end
end

local CLASSIFICATION = { worldboss = "Boss", elite = "Elite", rareelite = "Rare Elite", rare = "Rare" }

local function metaText(u)
    local level = UnitLevel(u)
    local c = UnitClassification(u)
    if isSecret(level) or isSecret(c) then return "" end
    local lv = (level and level > 0) and tostring(level) or "??"
    if c == "worldboss" then return "?? Boss" end
    local word = CLASSIFICATION[c]
    return word and (lv .. " " .. word) or lv
end

function UF:UpdateIdentity()
    local u = self.unit
    if not UnitExists(u) then return end
    local size = self.size

    -- The marker before the name: a role icon, else the class diamond.
    local role = UnitGroupRolesAssigned and UnitGroupRolesAssigned(u)
    local isPlayer = UnitIsPlayer(u)
    local _, class = UnitClass(u)
    local classColor = isPlayer and not isSecret(class) and class and T.color["class-" .. class:lower()]
    self.role:Hide()
    self.classDot:Hide()
    local marker
    if role and not isSecret(role) and ROLE_ICON[role] then
        self.role:SetTexture(ROLE_ICON[role])
        self.role:SetVertexColor(UI.RGBA(role == "DAMAGER" and "ink-muted" or "ink"))
        self.role:Show()
        marker = self.role
    elseif classColor then
        self.classDot:SetVertexColor(unpack(classColor))
        self.classDot:Show()
        marker = self.classDot
    end

    -- The name: class colour for players, reaction colour for hostile and
    -- neutral NPCs, ink for friendly ones; ink-faint when dead.
    self.name:SetValue(UnitName(u))
    if self.dead then
        self.name:SetColor("ink-faint")
    elseif self.opts.nameColor == "ink" then
        self.name:SetColor("ink")
    elseif classColor then
        self.name:SetTextColor(unpack(classColor))
    else
        local r = UnitReaction(u, "player")
        if isSecret(r) or not r then
            self.name:SetColor("ink")
        elseif r <= 3 then
            self.name:SetColor("reaction-hostile")
        elseif r == 4 then
            self.name:SetColor("reaction-neutral")
        else
            self.name:SetColor("ink")
        end
    end
    self.meta:SetValue(self.opts.meta and metaText(u) or "")
    self:LayoutRow(marker)
end

-- marker, name, meta, badges ... health %, in one row; the name gives way.
function UF:LayoutRow(marker)
    local size = self.size
    local x = 0
    for _, m in ipairs({ self.role, self.classDot }) do m:ClearAllPoints() end
    if marker then
        marker:SetPoint("LEFT", self.row, "LEFT", marker == self.classDot and 2 or 0, 0)
        x = (marker == self.role and size.role or 5) + size.gap
    end

    local badges = {}
    if self.badge:IsShown() then badges[#badges + 1] = self.badge end
    if self.you:IsShown() then badges[#badges + 1] = self.you end
    local tailW = 0
    if self.meta:GetText() ~= "" then tailW = tailW + size.gap + self.meta:GetUnboundedStringWidth() end
    for _, b in ipairs(badges) do tailW = tailW + size.gap + b:GetWidth() end

    -- The name sizes itself to its text, so the meta and badges follow it
    -- directly, secret or not. A readable name that would crowd them out is
    -- given a width, which adds the ellipsis; a secret one can't be measured
    -- and is simply clipped where the row ends.
    local natural = self.name:GetUnboundedStringWidth()
    local room = self.row:GetWidth() - x - tailW
    self.name:ClearAllPoints()
    self.name:SetPoint("LEFT", self.row, "LEFT", x, 0)
    if not isSecret(natural) and natural > room and room > 20 then
        self.name:SetWidth(room)
    else
        self.name:SetWidth(0)
    end

    local prev = self.name
    if self.meta:GetText() ~= "" then
        self.meta:ClearAllPoints()
        self.meta:SetPoint("LEFT", prev, "RIGHT", size.gap, 0)
        prev = self.meta
    end
    for _, b in ipairs(badges) do
        b:ClearAllPoints()
        b:SetPoint("LEFT", prev, "RIGHT", size.gap, 0)
        prev = b
    end
end

-- A state border and its badge: "danger", "warning", "magic", "curse",
-- "poison", "disease", "ward" or nil.
local STATE_BORDER = {
    danger = "ember", warning = "amber", ward = "ward",
    magic = "dispel-magic", curse = "dispel-curse", poison = "dispel-poison", disease = "dispel-disease",
}

function UF:SetState(tone, word)
    if tone == self.stateTone and word == self.stateWord then return end
    self.stateTone, self.stateWord = tone, word
    self.border:SetColor(STATE_BORDER[tone] or (self.opts.anchor and "gilt-line" or "gilt-hairline"))
    self.glow:SetShown(tone == "danger")
    if tone and word then
        self.badge:SetState(tone, word)
        self.badge:Show()
    else
        self.badge:Hide()
    end
    self:LayoutRow(self.role:IsShown() and self.role or (self.classDot:IsShown() and self.classDot) or nil)
end

function UF:Refresh()
    if not UnitExists(self.unit) then return end
    self.dead = UnitIsDeadOrGhost(self.unit)
    self:UpdateIdentity()
    self:UpdateHealth(true)
    self:UpdatePower()
end

--------------------------------------------------------------------------------
-- Events
--------------------------------------------------------------------------------

local HEALTH_EVENTS = { "UNIT_HEALTH", "UNIT_MAXHEALTH", "UNIT_HEAL_PREDICTION", "UNIT_ABSORB_AMOUNT_CHANGED" }
local POWER_EVENTS = { "UNIT_POWER_UPDATE", "UNIT_MAXPOWER", "UNIT_DISPLAYPOWER" }
local IDENTITY_EVENTS = { "UNIT_NAME_UPDATE", "UNIT_LEVEL", "UNIT_FACTION", "UNIT_CLASSIFICATION_CHANGED", "UNIT_CONNECTION" }

-- Registers a unit event if this client has it (a few retail events may not).
local function onUnit(f, event, fn)
    local ok = pcall(Events.OnUnit, event, f.unit, fn, f)
    if not ok then ns.Debug("UnitFrame: no event", event) end
end

function UF:Activate()
    if self.active then return end
    self.active = true
    for _, e in ipairs(HEALTH_EVENTS) do onUnit(self, e, function() self:UpdateHealth() end) end
    for _, e in ipairs(POWER_EVENTS) do onUnit(self, e, function() self:UpdatePower() end) end
    for _, e in ipairs(IDENTITY_EVENTS) do onUnit(self, e, function() self:UpdateIdentity() end) end
    Events.OnGame("PLAYER_ENTERING_WORLD", function() self:Refresh() end, self)
    Events.OnGame("GROUP_ROSTER_UPDATE", function() self:UpdateIdentity() end, self)
    Events.OnGame("PLAYER_ROLES_ASSIGNED", function() self:UpdateIdentity() end, self)
    if self.unit == "target" then
        Events.OnGame("PLAYER_TARGET_CHANGED", function() self:Refresh() end, self)
    elseif self.unit == "focus" then
        Events.OnGame("PLAYER_FOCUS_CHANGED", function() self:Refresh() end, self)
    end
    self:Refresh()
end

function UF:Deactivate()
    if not self.active then return end
    self.active = false
    Events.OffAll(self)
end
