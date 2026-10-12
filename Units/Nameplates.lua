-- Units/Nameplates.lua
-- Enemy nameplates (step 1.10): SuuUI's own plate laid on Blizzard's, the
-- design's Nameplate. A built-in module written against the public API only.
--
-- The technique EllesmereUI proves on this client (and /suu probe plates
-- confirmed): on NAME_PLATE_UNIT_ADDED, an attackable unit gets a pooled
-- SuuUI plate parented to Blizzard's nameplate; Blizzard's UnitFrame stays
-- (it is what you click, and moving it breaks click selection) at alpha 0,
-- its aura icons moved to a hidden frame (they trap the mouse even at alpha
-- 0). Nothing is ever written onto Blizzard's frames: SuuUI keeps its own
-- weak tables. Friendly units get a SuuUI plate in the open world: the name
-- in its class (or friendly) colour, the debuffs you can remove instead of
-- yours, a neutral cast (nothing to interrupt), no threat (they don't attack
-- you). Inside dungeons, raids, battlegrounds and arenas the game locks
-- friendly plates, so they stay Blizzard's (hidden in dungeons and raids, by
-- default). Your own plate (the personal resource display) stays Blizzard's.
--
-- The plate, top to bottom: up to four of your debuffs (icon-sm by default,
-- engine aura container), the name in its reaction colour with the state
-- badge and the health text (micro) at the right, the bar (nameplate, 10px by
-- default), the cast (cast-plate, 8px by default, the spell line under it).
-- The three sizes are settings. Everything the game may hide goes to the engine
-- unread: health to the StatusBar, the name to the text (a fixed width, so a
-- secret name is cut with "…"; in dungeons enemy names are secret), the
-- percentage through a curve, the value through AbbreviateNumbers.
-- Quest objectives: a gilt diamond left of the name (with the count, 3/8 or
-- 45%) on mobs one of your quests still needs, read from the unit's tooltip
-- data (structured lines, every value checked for secrecy), cached per
-- plate and re-read when the quest log changes.
-- Your target: an ink border, full opacity; the rest rest at opacity-plate.
-- Threat (readable on plates, also in dungeons): as a non-tank "Aggro" when
-- it attacks you; as a tank "Losing" when it is about to leave you and
-- "Aggro" when it has. Solo, everyone reads as a non-tank (a tank has no one
-- to lose a mob to): "Aggro" on what attacks you.

local UI, T = SuuUI.UI, SuuUI.Tokens
local S = T.space

local M = SuuUI.RegisterModule({
    id = "nameplates",
    name = "Nameplates",
    description = "Enemy nameplates: your debuffs, name, health, threat and casts.",
    api = "0.9",
    reloadToToggle = true,
    defaults = {
        width = 136,
        barHeight = 10,
        castHeight = 8,
        auras = 4,
        auraSize = 16,
        castBars = true,
        castTarget = true,
        castKick = true,
        dimOthers = true,
        threat = true,
        healthText = "percent", -- "percent", "value", "both" or "none", as on the unit frames
        friendlyOpenWorld = true,
        friendlyStyle = true,
        questMarks = true,
    },
})

-- "Health %" was a toggle; it is the unit frames' health text choice now
M:Migrate("healthText", function(values)
    if type(values.healthText) == "boolean" then values.healthText = values.healthText and "percent" or "none" end
end)

local isSecret = issecretvalue or function() return false end
local WHITE = "Interface\\Buttons\\WHITE8X8"
local LOW = 0.35
local NAME_H = 14
-- The health text's room at the name row's right end, per mode: a secret
-- text can't be measured, so each mode keeps a fixed width.
local PCT_W = { percent = 32, value = 36, both = 68, none = 0 }

-- SuuUI's own records, never keys on Blizzard's frames
local hidden = setmetatable({}, { __mode = "k" })   -- Blizzard UnitFrame -> true while hidden
local auraHome = setmetatable({}, { __mode = "k" }) -- moved aura frame -> its parent
local byUnit = {}                                   -- "nameplateN" -> SuuUI plate
local questCache = {}                               -- "nameplateN" -> false | count text ("" none)

local function barH() return M:Get("barHeight") end
-- the name row sits space-2 over the bar: the state badge (taller than the
-- text, centred on it) keeps a hair of air above the bar's border
local ROW_GAP = S["space-2"]
local function plateH() return NAME_H + ROW_GAP + barH() end

-- A health amount for a StatusBar: a secret one goes through untouched (a
-- secret value can't even be tested against nil), a missing one is `default`.
local function amount(v, default)
    if isSecret(v) then return v end
    return v or default or 0
end

-- Inside an instance: dungeons and raids, and with `pvp` battlegrounds and
-- arenas too.
local function inInstance(pvp)
    local _, kind = IsInInstance()
    if kind == "party" or kind == "raid" then return true end
    return pvp and (kind == "pvp" or kind == "arena") or false
end

local stash = CreateFrame("Frame")
stash:Hide()

--------------------------------------------------------------------------------
-- Blizzard's plate: hidden under ours, back for friendly units
--------------------------------------------------------------------------------

local guard = false
local hookedAlpha = setmetatable({}, { __mode = "k" })

local function hideBlizzard(uf)
    if not uf or uf:IsForbidden() then return end
    hidden[uf] = true
    uf:SetAlpha(0)
    if not hookedAlpha[uf] then
        hookedAlpha[uf] = true
        hooksecurefunc(uf, "SetAlpha", function(self)
            if hidden[self] and not guard then
                guard = true
                self:SetAlpha(0)
                guard = false
            end
        end)
    end
    -- aura icons catch the mouse even at alpha 0
    local auras = uf.AurasFrame
    if auras and not auras:IsForbidden() and auras:GetParent() ~= stash then
        auraHome[auras] = auras:GetParent()
        auras:SetParent(stash)
    end
end

local function restoreBlizzard(uf)
    if not uf or uf:IsForbidden() or not hidden[uf] then return end
    hidden[uf] = nil
    uf:SetAlpha(1)
    local auras = uf.AurasFrame
    if auras and auraHome[auras] and not auras:IsForbidden() then
        auras:SetParent(auraHome[auras])
        auraHome[auras] = nil
    end
end

--------------------------------------------------------------------------------
-- The plate
--------------------------------------------------------------------------------

local lowCurve
local function belowLow()
    if lowCurve == nil then
        lowCurve = false
        if C_CurveUtil and Enum.LuaCurveType then
            local c = C_CurveUtil.CreateCurve()
            c:SetType(Enum.LuaCurveType.Step)
            c:AddPoint(0, 1)
            c:AddPoint(LOW, 0)
            lowCurve = c
        end
    end
    return lowCurve or nil
end

local function gradient(bar, deep, fill)
    local r1, g1, b1, a1 = UI.RGBA(deep)
    local r2, g2, b2, a2 = UI.RGBA(fill)
    bar:GetStatusBarTexture():SetGradient("HORIZONTAL", CreateColor(r1, g1, b1, a1), CreateColor(r2, g2, b2, a2))
end

local Plate = {}

-- Builds a plate. `api` (previews) stands in for the game's Unit* functions.
local function buildPlate(parent, api)
    local f = CreateFrame("Frame", nil, parent)
    Mixin(f, Plate)
    f.api = api or _G
    f:EnableMouse(false)
    local w = M:Get("width")
    f:SetSize(w, plateH())

    -- the name row: name (reaction colour), badge, health text
    f.name = UI.Text(f, "unit-name-sm", "ink")
    f.name:SetShadowed(true)
    f.name:SetWordWrap(false)
    f.name:SetPoint("BOTTOMLEFT", f, "TOPLEFT", 0, -NAME_H)
    f.pct = UI.Text(f, "micro", "ink")
    f.pct:SetShadowed(true)
    f.pct:SetPoint("BOTTOMRIGHT", f, "TOPRIGHT", 0, -NAME_H)
    -- a quest objective: the gilt diamond and what you have of it
    f.quest = CreateFrame("Frame", nil, f)
    f.quest:SetHeight(NAME_H)
    f.quest:SetPoint("BOTTOMLEFT", f, "TOPLEFT", 0, -NAME_H)
    f.quest.mark = UI.Diamond(f.quest, 8, "gilt")
    f.quest.mark:SetPoint("LEFT", 0, 0)
    f.quest.count = UI.Text(f.quest, "micro", "gilt-text")
    f.quest.count:SetShadowed(true)
    f.quest.count:SetPoint("LEFT", f.quest.mark, "RIGHT", 3, 0)
    f.quest:Hide()
    f.questW = 0
    f.badge = UI.StateBadge(f, "danger", "")
    f.badge:SetPoint("RIGHT", f.pct, "LEFT", -S["space-2"], 0)
    f.badge:Hide()

    -- the bar
    local bar = CreateFrame("Frame", nil, f)
    bar:SetPoint("BOTTOMLEFT")
    bar:SetPoint("BOTTOMRIGHT")
    bar:SetHeight(barH())
    UI.Fill(bar, "surface-sunk"):SetAllPoints()
    f.bar = bar
    local inner = CreateFrame("Frame", nil, bar)
    inner:SetPoint("TOPLEFT", 1, -1)
    inner:SetPoint("BOTTOMRIGHT", -1, 1)
    inner:SetClipsChildren(true)
    f.health = CreateFrame("StatusBar", nil, inner)
    f.health:SetAllPoints()
    f.health:SetStatusBarTexture(WHITE)
    gradient(f.health, "unit-fill-deep", "unit-fill")
    f.healthLow = CreateFrame("StatusBar", nil, inner)
    f.healthLow:SetAllPoints()
    f.healthLow:SetStatusBarTexture(WHITE)
    gradient(f.healthLow, "unit-fill-low-deep", "unit-fill-low")
    f.healthLow:SetFrameLevel(f.health:GetFrameLevel() + 1)
    f.healthLow:SetAlpha(0)
    local edge = CreateFrame("Frame", nil, bar)
    edge:SetAllPoints()
    edge:SetFrameLevel(f.healthLow:GetFrameLevel() + 1)
    f.border = UI.Border(edge, "gilt-hairline")
    f.glow = UI.Shadow(bar, "glow-ember")
    f.glow:SetShown(false)

    -- the cast, under the bar
    f.cast = UI.CastBar(f, "none", { size = "plate", width = w, icon = false, target = true })
    f.cast:SetBarHeight(M:Get("castHeight"))
    f.cast:SetTargetShown(M:Get("castTarget"))
    f.cast:SetKickShown(M:Get("castKick"))
    f.cast:SetPoint("TOPLEFT", f, "BOTTOMLEFT", 0, -S["space-1"])
    return f
end

-- Your debuffs on it, above the name (the engine fills them).
local function buildAuras(f)
    f.auras = UI.AuraContainer(f, "none", { size = M:Get("auraSize"), spacing = S["space-1"], anchor = "BOTTOMLEFT", growth = { "RIGHT", "UP" },
        groups = {
            { key = "mine", filter = { "HARMFUL", "PLAYER" }, max = 4 },
            -- on friendly plates: what you can remove, with its type's border
            { key = "removable", filter = { "HARMFUL", "RAID_PLAYER_DISPELLABLE" }, max = 0, dispel = true },
        } })
    if f.auras then
        f.auras.container:SetPoint("BOTTOMLEFT", f, "TOPLEFT", 0, S["space-1"])
    end
end

function Plate:SetPlateWidth(w)
    self:SetSize(w, plateH())
    self.bar:SetHeight(barH())
    local mode = M:Get("healthText")
    local textW = PCT_W[mode] or PCT_W.percent
    -- the badge left of the health text, or at the row's end without one
    if self.textMode ~= mode then
        self.textMode = mode
        self.badge:ClearAllPoints()
        if textW > 0 then
            self.badge:SetPoint("RIGHT", self.pct, "LEFT", -S["space-2"], 0)
        else
            self.badge:SetPoint("RIGHT", self, "TOPRIGHT", 0, -NAME_H / 2)
        end
    end
    self.name:SetWidth(math.max(20, w - (self.questW or 0) - (textW > 0 and textW + S["space-2"] or 0)
        - (self.badge:IsShown() and (self.badge.knownWidth or 0) + S["space-2"] or 0)))
end

-- Is this mob one of your quest objectives, still open? Its tooltip data says:
-- a QuestTitle line (the quest's id), then QuestObjective lines (done or
-- not, have and need). Only quests in your own log count (a group member's
-- objective is in your tooltip too). Returns false, or the count to show
-- ("3/8", "45%", or "" for a single mob).
local function questObjective(unit)
    local LT = Enum.TooltipDataLineType
    local info = C_TooltipInfo.GetUnit(unit)
    if not (info and info.lines) then return false end
    local onQuest = C_QuestLog and C_QuestLog.IsOnQuest
    local questID
    for _, line in ipairs(info.lines) do
        local kind = line.type
        if not isSecret(kind) then
            if kind == LT.QuestTitle then
                local id = line.id
                questID = (not isSecret(id) and id ~= nil) and id or nil
            elseif kind == LT.QuestObjective then
                local done = line.completed
                if not isSecret(done) and done == false and (not questID or not onQuest or onQuest(questID)) then
                    local text = line.leftText
                    local pct = (not isSecret(text) and type(text) == "string") and text:match("(%d+)%s*%%")
                    if pct then return pct .. "%" end
                    local have, need = line.numFulfilled, line.numRequired
                    if not isSecret(have) and not isSecret(need) and have and need and need > 1 then
                        return have .. "/" .. need
                    end
                    return ""
                end
            end
        end
    end
    return false
end

local function questText(unit)
    local cached = questCache[unit]
    if cached ~= nil then return cached end
    local result = false
    if C_TooltipInfo and C_TooltipInfo.GetUnit and Enum.TooltipDataLineType then
        local ok, r = pcall(questObjective, unit)
        result = ok and r or false
    end
    questCache[unit] = result
    return result
end

function Plate:UpdateQuest()
    local text = false
    if M:Get("questMarks") and not self.friendly then
        if self.preview then text = self.previewQuest or false else text = questText(self.unit) end
    end
    local w = 0
    if text then
        self.quest.count:SetValue(text)
        self.quest.count:SetShown(text ~= "")
        local qw = 8 + (text ~= "" and (3 + math.ceil(self.quest.count:GetUnboundedStringWidth())) or 0)
        self.quest:SetWidth(qw)
        w = qw + S["space-2"]
    end
    self.quest:SetShown(text and true or false)
    self.questW = w
    self.name:ClearAllPoints()
    self.name:SetPoint("BOTTOMLEFT", self, "TOPLEFT", w, -NAME_H)
    self:SetPlateWidth(M:Get("width"))
end

function Plate:UpdateHealth()
    local A, u = self.api, self.unit
    local max, cur = A.UnitHealthMax(u), A.UnitHealth(u)
    self.health:SetMinMaxValues(0, amount(max, 1))
    self.health:SetValue(amount(cur))
    self.healthLow:SetMinMaxValues(0, amount(max, 1))
    self.healthLow:SetValue(amount(cur))
    local curve = belowLow()
    if curve then
        self.healthLow:SetAlpha(amount(A.UnitHealthPercent(u, true, curve)))
    else
        self.healthLow:SetAlpha(0)
    end
    -- The health text: the percentage through a curve, the value through
    -- AbbreviateNumbers (a secret health gives a secret string). Neither is
    -- ever tested: they go to the engine's formatting as they are.
    local mode = M:Get("healthText")
    local pct, value
    local hasPct = (mode == "percent" or mode == "both") and A.UnitHealthPercent ~= nil and CurveConstants ~= nil
    local hasValue = false -- a plain flag: the value itself may be secret
    if hasPct then
        pct = A.UnitHealthPercent(u, true, CurveConstants.ScaleTo100)
        if not isSecret(pct) then pct = (pct or 0) + 0.5 end
    end
    if mode == "value" or mode == "both" then
        local ok, text = pcall(AbbreviateNumbers, amount(cur))
        if ok then value, hasValue = text, true end
    end
    if mode == "both" and hasPct and hasValue then
        self.pct:SetFormattedText("%s · %d%%", value, pct)
    elseif mode ~= "percent" and hasValue then
        self.pct:SetText(value)
    elseif hasPct then
        self.pct:SetFormattedText("%d%%", pct)
    else
        self.pct:Hide()
        return
    end
    self.pct:Show()
end

local REACTION = { [1] = "reaction-hostile", [2] = "reaction-hostile", [3] = "reaction-hostile", [4] = "reaction-neutral" }

function Plate:UpdateName()
    local A, u = self.api, self.unit
    self.name:SetText(A.UnitName(u))
    local r = A.UnitReaction(u, "player")
    local color = "reaction-hostile"
    if not isSecret(r) and r ~= nil then color = REACTION[r] or "reaction-friendly" end
    self.name:SetColor(color)
    -- friendly players in their class colour (never tested: may be secret)
    if self.friendly then
        local okPlayer, player = pcall(A.UnitIsPlayer, u)
        if okPlayer and not isSecret(player) and player then
            local _, class = A.UnitClass(u)
            if type(class) ~= "nil" and C_ClassColor then
                local ok, c = pcall(C_ClassColor.GetClassColor, class)
                if ok and c then pcall(self.name.SetTextColor, self.name, c:GetRGB()) end
            end
        end
    end
end

-- Threat (readable on plates): non-tank Aggro, tank Losing / Aggro; solo
-- as a non-tank.
function Plate:UpdateThreat()
    local A, u = self.api, self.unit
    local tone, word
    if M:Get("threat") and not self.friendly then
        local status = A.UnitThreatSituation("player", u)
        if not isSecret(status) and status ~= nil then
            local tank
            if self.preview then tank = self.previewRole == "TANK" else tank = IsInGroup() and SuuUI.Role() == "TANK" end
            if tank then
                if status == 2 then tone, word = "warning", "Losing"
                elseif status <= 1 then tone, word = "danger", "Aggro" end
            elseif status >= 2 then
                tone, word = "danger", "Aggro"
            end
        end
    end
    self.state = tone
    -- the state first, while a new badge is still hidden: it fades in each
    -- time it appears
    if tone then self.badge:SetState(tone, word) end
    self.badge:SetShown(tone ~= nil)
    self:SetPlateWidth(M:Get("width"))
    self:UpdateBorder()
end

function Plate:UpdateBorder()
    local color = "gilt-hairline"
    if self.state == "danger" then color = "ember"
    elseif self.state == "warning" then color = "amber"
    elseif self.isTarget then color = "ink" end
    self.border:SetColor(color)
    self.glow:SetShown(self.state == "danger")
end

-- Your target at full opacity with an ink border; with a target, the rest dim.
function Plate:UpdateTarget()
    local A, u = self.api, self.unit
    local is = A.UnitIsUnit(u, "target")
    self.isTarget = not isSecret(is) and is or false
    local dim = M:Get("dimOthers") and not self.isTarget and (self.preview or UnitExists("target"))
    self:SetAlpha(dim and T.opacity["opacity-plate"] or 1)
    self:UpdateBorder()
end

function Plate:Refresh()
    self:UpdateQuest()
    self:UpdateName()
    self:UpdateHealth()
    self:UpdateThreat()
    self:UpdateTarget()
end

--------------------------------------------------------------------------------
-- Events per plate (its unit token changes as plates are reused)
--------------------------------------------------------------------------------

local function listen(f)
    if not f.events then
        f.events = CreateFrame("Frame")
        f.events:SetScript("OnEvent", function(_, event)
            if not f.unit then return end
            if event == "UNIT_NAME_UPDATE" then f:UpdateName()
            elseif event == "UNIT_THREAT_LIST_UPDATE" then f:UpdateThreat()
            else f:UpdateHealth() end
        end)
    end
    f.events:UnregisterAllEvents()
    for _, e in ipairs({ "UNIT_HEALTH", "UNIT_MAXHEALTH", "UNIT_NAME_UPDATE", "UNIT_THREAT_LIST_UPDATE" }) do
        pcall(f.events.RegisterUnitEvent, f.events, e, f.unit)
    end
end

--------------------------------------------------------------------------------
-- The pool
--------------------------------------------------------------------------------

local pool = {}

local function acquire()
    local f = table.remove(pool)
    if not f then
        f = buildPlate(UIParent)
        buildAuras(f)
    end
    return f
end

local function release(f)
    if f.events then f.events:UnregisterAllEvents() end
    f.cast:Deactivate()
    if f.auras then f.auras:SetUnit("none") end
    f.unit, f.friendly = nil, nil
    f:Hide()
    f:ClearAllPoints()
    f:SetParent(UIParent)
    pool[#pool + 1] = f
end

function M:OnPlateAdded(unit)
    local plate = C_NamePlate.GetNamePlateForUnit(unit)
    if not plate or plate:IsForbidden() then return end
    local uf = plate.UnitFrame
    if byUnit[unit] then release(byUnit[unit]); byUnit[unit] = nil end
    -- your own plate (the personal resource display) stays Blizzard's
    if UI.Flag(UnitIsUnit(unit, "player")) then
        restoreBlizzard(uf)
        return
    end
    local friendly = not UI.Flag(UnitCanAttack("player", unit))
    if friendly and self:FriendlyStyled() then
        -- a friendly plate now; the recheck below still turns it into an
        -- enemy's if the unit only read as friendly on its first frame
        self:Attach(unit, plate, true)
    elseif friendly then
        restoreBlizzard(uf)
    end
    if friendly then
        -- an enemy can read as not attackable on its plate's first frame:
        -- look once more
        if not self.recheck then self.recheck = {} end
        if not self.recheck[unit] then
            self.recheck[unit] = true
            C_Timer.After(0.2, function()
                self.recheck[unit] = nil
                local f = byUnit[unit]
                if self:IsEnabled() and UnitExists(unit) and UI.Flag(UnitCanAttack("player", unit)) and (not f or f.friendly) then self:OnPlateAdded(unit) end
            end)
        end
        return
    end
    self:Attach(unit, plate, false)
end

-- A plate whose unit may have changed sides (a duel): laid again only when
-- it did, otherwise just redrawn.
function M:Recheck(unit)
    local f = byUnit[unit]
    if f and f.friendly == not UI.Flag(UnitCanAttack("player", unit)) then return f:Refresh() end
    self:OnPlateAdded(unit)
end

-- SuuUI's friendly plates: open world only. Wider than the friendly CVar
-- (ApplyFriendly), on purpose: the game locks friendly plates in battlegrounds
-- and arenas too, so SuuUI's look is off there although they stay shown.
function M:FriendlyStyled()
    if not self:Get("friendlyStyle") then return false end
    return not inInstance(true)
end

-- A SuuUI plate sits on Blizzard's with the bar's middle on its centre.
local function anchor(f, plate)
    f:ClearAllPoints()
    f:SetPoint("BOTTOM", plate, "CENTER", 0, -(barH() / 2))
end

-- Lays a SuuUI plate on Blizzard's: an enemy's, or a friendly one (name,
-- bar and health text only).
function M:Attach(unit, plate, friendly)
    local uf = plate.UnitFrame
    if uf and uf:IsForbidden() then return end
    hideBlizzard(uf)
    local f = acquire()
    f.unit, f.friendly = unit, friendly
    questCache[unit] = nil
    byUnit[unit] = f
    f:SetParent(plate)
    anchor(f, plate)
    f:SetFrameLevel(plate:GetFrameLevel() + 2)
    f:SetPlateWidth(self:Get("width"))
    listen(f)
    if f.auras then
        self:ApplyAuraCount(f)
        f.auras:SetUnit(unit)
    end
    f.cast:SetNeutral(friendly)
    if self:Get("castBars") then
        f.cast:SetUnit(unit)
        if not f.cast.active then f.cast:Activate() end
    else
        f.cast:Deactivate()
    end
    f:Refresh()
    f:Show()
end

function M:OnPlateRemoved(unit)
    questCache[unit] = nil
    local f = byUnit[unit]
    if f then
        byUnit[unit] = nil
        release(f)
    end
end

function M:ApplyAuraCount(f)
    if not f.auras then return end
    local n = self:Get("auras")
    f.auras:SetGroupMax("mine", f.friendly and 0 or n)
    f.auras:SetGroupMax("removable", f.friendly and n or 0)
end

function M:ForEach(fn)
    for _, f in pairs(byUnit) do fn(f) end
    for _, f in ipairs(self.previewPlates or {}) do fn(f) end
end

-- The sizes and cast options on every live, pooled and preview plate. Aura
-- icons resize out of combat only (the engine's buttons refuse it in combat).
function M:ApplySizes()
    local function each(fn)
        for _, f in pairs(byUnit) do fn(f) end
        for _, f in ipairs(pool) do fn(f) end
    end
    local w = self:Get("width")
    local function apply(f)
        f.cast.totalW = w
        f.cast:SetWidth(w)
        f.cast:Arrange()
        f.cast:SetBarHeight(self:Get("castHeight"))
        f.cast:SetTargetShown(self:Get("castTarget"))
        f.cast:SetKickShown(self:Get("castKick"))
        f:SetPlateWidth(w)
    end
    each(apply)
    for _, f in ipairs(self.previewPlates or {}) do apply(f) end
    -- the bar's middle stays on Blizzard's plate's centre
    for _, f in pairs(byUnit) do
        local plate = f:GetParent()
        if plate then anchor(f, plate) end
    end
    self:RunOutOfCombat("auraSize", function()
        each(function(f)
            if f.auras then
                f.auras:SetGroupSize("mine", self:Get("auraSize"))
                f.auras:SetGroupSize("removable", self:Get("auraSize"))
            end
        end)
    end)
end

--------------------------------------------------------------------------------
-- Nameplate settings of the game: full alpha and scale (SuuUI dims itself),
-- out of combat only (the CVars are protected in combat)
--------------------------------------------------------------------------------

local CVARS = {
    nameplateMinAlpha = "1", nameplateMaxAlpha = "1", nameplateSelectedAlpha = "1", nameplateNotSelectedAlpha = "1",
    nameplateMinScale = "1", nameplateMaxScale = "1", nameplateSelectedScale = "1",
}

function M:ApplyGameSettings()
    self:RunOutOfCombat("cvars", function()
        for k, v in pairs(CVARS) do pcall(C_CVar.SetCVar, k, v) end
        if C_NamePlate and C_NamePlate.SetNamePlateSize then
            pcall(C_NamePlate.SetNamePlateSize, self:Get("width"), plateH() + 8)
        end
    end)
end

-- The game's "show friendly players' plates": current clients call it
-- nameplateShowFriendlyPlayers, older ones nameplateShowFriends. Written to
-- whichever this client has (an unknown name reads back nil).
local FRIENDLY_CVARS = { "nameplateShowFriendlyPlayers", "nameplateShowFriends" }

local function showFriendly(on)
    for _, name in ipairs(FRIENDLY_CVARS) do
        if C_CVar.GetCVar(name) ~= nil then pcall(C_CVar.SetCVar, name, on and "1" or "0") end
    end
end

-- Friendly players' plates in the open world only: inside a dungeon or raid
-- the game locks them, and in a group they mostly cover the fight. Narrower
-- than FriendlyStyled, on purpose: in battlegrounds and arenas they stay
-- shown (Blizzard's look). SuuUI owns the game's setting while this is on;
-- turned off (`released`), the plates come back once and the game's setting
-- is yours again.
function M:ApplyFriendly(released)
    if not self:Get("friendlyOpenWorld") and not released then return end
    self:RunOutOfCombat("friendly", function()
        -- read again: the setting may have changed while combat lasted
        showFriendly(not (self:Get("friendlyOpenWorld") and inInstance()))
    end)
end

--------------------------------------------------------------------------------
-- The preview: four made-up plates (the design's), your target first
--------------------------------------------------------------------------------

local PEOPLE = {
    { name = "Cinder Acolyte", health = 0.62, max = 13800, reaction = 2, target = true, threat = 3, debuffs = { 1978, 1130 }, cast = { name = "Flame Lash", icon = 133, progress = 0.55, time = "0.9s", target = "Kaelith", targetClass = "PRIEST" } },
    { name = "Ember Hound", health = 0.81, max = 8400, reaction = 2, threat = 2, quest = "3/8" },
    { name = "Ashbound Ritualist", health = 0.28, max = 11200, reaction = 2, threat = 0, cast = { name = "Rain of Ash", icon = 5740, progress = 0.3, time = "1.9s", locked = true } },
    { name = "Dusk Prowler", health = 1, max = 6900, reaction = 4 },
    { name = "Ysolde", health = 0.9, max = 3900, reaction = 5, friendly = true, class = "PALADIN", debuffs = { 702 }, debuffType = "Curse",
      cast = { name = "Flash of Light", icon = 19750, progress = 0.7, time = "0.4s" } },
}

local function person(unit) return PEOPLE[tonumber(unit:match("(%d)$")) or 1] end

function M:PreviewView(parent)
    if not self.previewView then
        local api = UI.UnitStandIn(person)
        api.UnitReaction = function(u) return person(u).reaction end
        api.UnitHealthPercent = function(u, _, curve)
            local h = person(u).health
            if CurveConstants and curve == CurveConstants.ScaleTo100 then return h * 100 end
            return h < LOW and 1 or 0 -- the plate's low-health curve
        end
        api.UnitThreatSituation = function(_, u) return person(u).threat end
        api.UnitIsUnit = function(u, other) return other == "target" and person(u).target or false end
        local view = CreateFrame("Frame", nil, parent)
        self.previewView, self.previewPlates = view, {}
        for i = 1, #PEOPLE do
            local f = buildPlate(view, api)
            f.unit, f.preview, f.previewRole, f.friendly = "plate" .. i, true, "TANK", PEOPLE[i].friendly
            f.previewQuest = PEOPLE[i].quest
            f.cast:Hide()
            -- a drawn cast and drawn debuffs (the engine draws the real ones)
            f.fakeCast = CreateFrame("StatusBar", nil, f)
            f.fakeCast:SetPoint("TOPLEFT", f, "BOTTOMLEFT", 0, -S["space-1"])
            f.fakeCast:SetSize(1, self:Get("castHeight"))
            f.fakeCast:SetStatusBarTexture(WHITE)
            f.fakeCastBorder = UI.Border(f.fakeCast, "gilt-hairline")
            -- the spell's icon leading the line; the lock inside the bar's left end
            f.fakeIcon = UI.Icon(f, 13)
            f.fakeIcon:SetPoint("TOPLEFT", f.fakeCast, "BOTTOMLEFT", 0, -S["space-1"])
            f.fakeLock = CreateFrame("Frame", nil, f.fakeCast)
            f.fakeLock:SetAllPoints()
            f.fakeLock:SetFrameLevel(f.fakeCast:GetFrameLevel() + 3)
            f.fakeLockArt = f.fakeLock:CreateTexture(nil, "OVERLAY")
            f.fakeLockArt:SetTexture("Interface\\LFGFrame\\UI-LFG-ICON-LOCK")
            f.fakeLockArt:SetDesaturated(true)
            f.fakeLockArt:SetVertexColor(UI.RGBA("ink"))
            f.fakeLockArt:SetPoint("LEFT", 2, 0)
            f.fakeSpell = UI.Text(f, "caption", "ink")
            f.fakeSpell:SetShadowed(true)
            f.fakeSpell:SetPoint("LEFT", f.fakeIcon, "RIGHT", S["space-2"], 0)
            f.fakeTarget = UI.Text(f, "caption", "ink")
            f.fakeTarget:SetShadowed(true)
            f.fakeTarget:SetPoint("TOPLEFT", f.fakeIcon, "BOTTOMLEFT", 13 + S["space-2"], 0)
            f.fakeTime = UI.Text(f, "caption", "ink")
            f.fakeTime:SetShadowed(true)
            f.fakeTime:SetPoint("TOPRIGHT", f.fakeCast, "BOTTOMRIGHT", 0, -S["space-1"])
            f.fakeIcons = {}
            for k = 1, 4 do
                local icon = UI.Icon(f, "icon-sm")
                icon:Hide()
                f.fakeIcons[k] = icon
            end
            self.previewPlates[i] = f
        end
    end
    self.previewView:SetParent(parent)
    self:DrawPreview()
    return self.previewView
end

function M:DrawPreview()
    if not self.previewPlates then return end
    local w, auraPx, castPx = self:Get("width"), self:Get("auraSize"), self:Get("castHeight")
    local y = 0
    for i, f in ipairs(self.previewPlates) do
        local d = PEOPLE[i]
        f:SetShown(not d.friendly or self:Get("friendlyStyle"))
        if not f:IsShown() then break end
        f:SetPlateWidth(w)
        f:Refresh()
        f:ClearAllPoints()
        local top = (d.debuffs and self:Get("auras") > 0) and (auraPx + S["space-1"] * 2) or 0
        f:SetPoint("TOPLEFT", self.previewView, "TOPLEFT", 0, -(y + top + NAME_H))
        f:Show()
        for k, icon in ipairs(f.fakeIcons) do
            local id = d.debuffs and d.debuffs[k]
            icon:SetSize(auraPx, auraPx)
            icon:ClearAllPoints()
            icon:SetPoint("BOTTOMLEFT", f, "TOPLEFT", (k - 1) * (auraPx + S["space-1"]), S["space-1"])
            icon:SetShown(id ~= nil and k <= self:Get("auras"))
            if id then icon:SetArt(C_Spell.GetSpellTexture(id)) end
            icon:SetBorder(d.debuffType and ("dispel-" .. d.debuffType:lower()) or "gilt-hairline")
        end
        local cast = d.cast and self:Get("castBars")
        f.fakeCast:SetShown(cast and true or false)
        f.fakeSpell:SetShown(cast and true or false)
        f.fakeIcon:SetShown(cast and true or false)
        local target = cast and d.cast.target and self:Get("castTarget")
        f.fakeTarget:SetShown(target and true or false)
        f.fakeTime:SetShown(cast and true or false)
        local castH = 0
        if cast then
            f.fakeCast:SetSize(w, castPx)
            f.fakeCast:SetMinMaxValues(0, 1)
            f.fakeCast:SetValue(d.cast.progress)
            local stoppable = not (d.cast.locked or d.friendly)
            f.fakeCast:SetStatusBarColor(UI.RGBA(stoppable and "arcane-glow" or "unit-fill"))
            f.fakeCastBorder:SetColor(stoppable and "arcane" or "gilt-hairline")
            f.fakeSpell:SetValue(d.cast.name)
            f.fakeIcon:SetArt(C_Spell.GetSpellTexture(d.cast.icon))
            f.fakeLock:SetShown(d.cast.locked and true or false)
            f.fakeLockArt:SetSize(math.max(8, castPx), math.max(8, castPx))
            f.fakeTime:SetValue(d.cast.time)
            castH = castPx + 13 + S["space-1"] * 2 + (target and 13 or 0)
            if target then
                local c = C_ClassColor.GetClassColor(d.cast.targetClass)
                local r, g, b = UI.RGBA("ink-muted")
                f.fakeTarget:SetText(("|cff%02x%02x%02x›|r %s"):format(r * 255, g * 255, b * 255, d.cast.target))
                f.fakeTarget:SetTextColor(c:GetRGB())
            end
        end
        y = y + top + plateH() + castH + S["space-6"]
    end
    self.previewView:SetSize(w, y)
end

--------------------------------------------------------------------------------
-- Settings
--------------------------------------------------------------------------------

-- The cast rows wait for cast bars.
local function castBarsOff()
    if not M:Get("castBars") then return true, "Turn Cast bars on first." end
    return false
end

local SECTION = {
    id = "nameplates", label = "Nameplates", category = "Frames", order = 20,
    preview = function(parent) return M:PreviewView(parent) end,
    groups = {
        { title = "Size", description = "SuuUI's plates on enemies. Turning the module off brings Blizzard's back after a reload.", rows = {
            { key = "width", label = "Width", control = "slider", min = 100, max = 200, step = 2, unit = "px", live = false },
            { key = "barHeight", label = "Health bar height", control = "slider", min = 4, max = 24, step = 1, unit = "px", live = false },
            { key = "auraSize", label = "Debuff size", control = "slider", min = 12, max = 28, step = 1, unit = "px", live = false, combat = true,
              disabled = function()
                  if M:Get("auras") == 0 then return true, "Set Debuff icons above 0 first." end
                  return false
              end },
            { key = "castHeight", label = "Cast bar height", control = "slider", min = 4, max = 20, step = 1, unit = "px", live = false,
              disabled = castBarsOff },
        } },
        { title = "Casts", rows = {
            { key = "castBars", label = "Cast bars", control = "toggle",
              description = "Under the bar: arcane when you can interrupt it, a lock when you can't." },
            { key = "castTarget", label = "Cast target", control = "toggle",
              description = "Who the spell is aimed at, under the spell name, in their class colour.", disabled = castBarsOff },
            { key = "castKick", label = "Your interrupt", control = "toggle",
              description = "On interruptible casts: a diamond in arcane when your interrupt is ready, its seconds when it isn't.", disabled = castBarsOff },
        } },
        { title = "On the plate", rows = {
            { key = "auras", label = "Debuff icons", control = "stepper", min = 0, max = 4, step = 1,
              description = "Above the name, with their time. Only yours." },
            { key = "healthText", label = "Health text", control = "segmented",
              options = { { value = "percent", label = "64%" }, { value = "value", label = "8.5k" },
                          { value = "both", label = "8.5k · 64%" }, { value = "none", label = "None" } },
              description = "At the right end of the name row: the health percentage, the current health, or both." },
            { key = "threat", label = "Threat badges", control = "toggle",
              description = "Aggro when a mob attacks you. As a tank in a group: Losing when it's about to leave you, Aggro when it has." },
            { key = "questMarks", label = "Quest objectives", control = "toggle",
              description = "A gilt mark left of the name on mobs your quests still need, with what you have (3/8)." },
            { key = "dimOthers", label = "Dim all but your target", control = "toggle",
              description = "With a target, other plates rest at 72% so yours reads first." },
        } },
        { title = "Friendly nameplates", rows = {
            { key = "friendlyOpenWorld", label = "Only in the open world", control = "toggle", combat = true,
              description = "Friendly players' plates show in the open world and hide in dungeons and raids. Turning it off brings them back everywhere; from then on the game's own nameplate setting decides." },
            { key = "friendlyStyle", label = "SuuUI's look", control = "toggle",
              description = "In the open world: the name in its class colour, the bar, the health text, the debuffs you can remove and casts. Inside dungeons, raids, battlegrounds and arenas the game keeps its own." },
        } },
    },
}

--------------------------------------------------------------------------------
-- Lifecycle
--------------------------------------------------------------------------------

function M:OnEnable()
    self:RegisterSettings(SECTION)
    self:ApplyGameSettings()
    self:ApplyFriendly()
    self:OnGameEvent("PLAYER_ENTERING_WORLD", function()
        self:ApplyFriendly()
        wipe(questCache)
    end)
    -- quest progress: read every plate's objective again (once per burst)
    local questDirty = false
    local function questsChanged()
        wipe(questCache)
        if questDirty then return end
        questDirty = true
        C_Timer.After(0.5, function()
            questDirty = false
            for _, f in pairs(byUnit) do f:UpdateQuest() end
        end)
    end
    self:OnGameEvent("QUEST_LOG_UPDATE", questsChanged)
    self:OnGameEvent("UNIT_QUEST_LOG_CHANGED", function(_, unit) if unit == "player" then questsChanged() end end)
    self:OnGameEvent("ZONE_CHANGED_NEW_AREA", function() self:ApplyFriendly() end)
    self:Watch("friendlyOpenWorld", function() self:ApplyFriendly(true) end)
    self:Watch("friendlyStyle", function()
        for i = 1, 40 do
            local unit = "nameplate" .. i
            if UnitExists(unit) then self:OnPlateAdded(unit) end
        end
        self:DrawPreview()
    end)
    -- plates (and their aura containers) made ahead, out of combat
    self:RunOutOfCombat("pool", function()
        while #pool < 12 do
            local f = buildPlate(UIParent)
            buildAuras(f)
            f:Hide()
            pool[#pool + 1] = f
        end
    end)
    -- plates already up (a reload next to mobs)
    for i = 1, 40 do
        local unit = "nameplate" .. i
        if UnitExists(unit) then self:OnPlateAdded(unit) end
    end
    self:OnGameEvent("NAME_PLATE_UNIT_ADDED", function(_, unit) self:OnPlateAdded(unit) end)
    self:OnGameEvent("NAME_PLATE_UNIT_REMOVED", function(_, unit) self:OnPlateRemoved(unit) end)
    self:OnGameEvent("PLAYER_TARGET_CHANGED", function() self:ForEach(function(f) f:UpdateTarget() end) end)
    self:OnGameEvent("GROUP_ROSTER_UPDATE", function() self:ForEach(function(f) f:UpdateThreat() end) end)
    self:OnGameEvent("PLAYER_REGEN_DISABLED", function() self:ForEach(function(f) f:UpdateThreat() end) end)
    self:OnGameEvent("PLAYER_REGEN_ENABLED", function() self:ForEach(function(f) f:UpdateThreat() end) end)
    self:On("SUUUI_ROLE_CHANGED", function() self:ForEach(function(f) f:UpdateThreat() end) end)
    -- a unit can turn attackable (a duel): re-check its plate
    self:OnGameEvent("UNIT_FACTION", function(_, unit)
        if unit and unit:find("^nameplate") and UnitExists(unit) then self:Recheck(unit) end
    end)
    for _, key in ipairs({ "width", "barHeight", "castHeight", "auraSize", "auras", "castBars", "castTarget", "castKick", "dimOthers", "threat", "healthText", "questMarks" }) do
        self:Watch(key, function()
            for unit, f in pairs(byUnit) do
                self:ApplyAuraCount(f)
                if key == "castBars" then
                    if self:Get("castBars") then f.cast:SetUnit(unit); f.cast:Activate() else f.cast:Deactivate() end
                end
                f:Refresh()
            end
            if key == "width" or key == "barHeight" or key == "castHeight" or key == "auraSize" or key == "castTarget" or key == "castKick" then
                self:ApplySizes()
                if key == "width" or key == "barHeight" then self:ApplyGameSettings() end
            end
            self:DrawPreview()
        end)
    end
end

function M:OnDisable()
    for unit, f in pairs(byUnit) do
        release(f)
        byUnit[unit] = nil
    end
    -- Blizzard's plates back (the SetAlpha hook lets go once they aren't hidden)
    for uf in pairs(hidden) do restoreBlizzard(uf) end
end
