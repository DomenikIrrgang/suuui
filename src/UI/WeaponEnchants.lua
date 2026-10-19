-- UI/WeaponEnchants.lua
-- Temporary weapon enchants: a shaman's imbues, a rogue's poisons, stones and
-- oils. They aren't auras, and unlike auras they stay readable in combat
-- (/suu probe weaponenchants: C_Item.GetWeaponEnchantInfo is plain), so SuuUI
-- reads them itself and draws them as its own icons, with the buffs' look.
--
--   UI.WeaponEnchant(slot)        -- 0.17: "main" | "off" | "ranged": the
--                                 -- enchant on that weapon, or nil:
--                                 -- { slot, icon, expires (GetTime), duration
--                                 -- (s: what it had when first seen), charges,
--                                 -- name, weapon, spellID }
--   UI.WeaponEnchantable(slot)    -- 0.17: whether a weapon is in that slot
--                                 -- (a shield or a totem isn't one)
--   UI.WeaponEnchantSpell(slot)   -- 0.17: the spell seen putting the last
--                                 -- enchant on that weapon (this session), or nil
--   UI.WeaponEnchantIcon(parent, size)   -- 0.17: an icon for one weapon:
--       icon:SetSlot(slot)
--       icon:SetMissing(mode)     -- with no enchant: nil (nothing drawn),
--                                 -- "grey", or "warn" (the ember edge, pulsing)
--       icon:SetTag(shown)        -- MH / OH / R on the top-left corner
--       icon:Refresh()            -- -> true while the weapon has an enchant
--       icon:SetPreview(texture)  -- a made-up enchant (edit mode); nil ends it
-- SUUUI_WEAPON_ENCHANTS_CHANGED: one came, went, or changed (charges, weapon).
--
-- An enchant's name is the spell cast just before it appeared (the imbue or
-- poison: the cast comes a moment before the change), else the weapon
-- tooltip's line ("Rockbiter 2 (60 min)" reads "Rockbiter"). Removing one is
-- forbidden to addons (C_Spell.CancelItemTempEnchantment: tried, refused), so
-- a click does nothing and the tooltip says so.

local _, ns = ...

local UI, T, Events = ns.UI, ns.Tokens, ns.Events
local S = T.space

local isSecret = issecretvalue or function() return false end
local WHITE = "Interface\\Buttons\\WHITE8X8"
local CROP = 0.08
local AMBER = 60 -- seconds: the digits turn amber and blink below this

local SLOTS = {
    main = { ws = 0, inv = 16, tag = "MH", label = "Main hand" },
    off = { ws = 1, inv = 17, tag = "OH", label = "Off hand" },
    ranged = { ws = 2, inv = 18, tag = "R", label = "Ranged" },
}
local ORDER = { "main", "off", "ranged" }

--------------------------------------------------------------------------------
-- Reading
--------------------------------------------------------------------------------

local state = {}      -- slot -> info, or false
local seen = {}       -- slot -> { id, duration } of the enchant on it
local spellFor = {}   -- slot -> the spell that put its enchant on
local tipNames = {}   -- "slot:enchantID" -> the tooltip's name
local lastArt = {}    -- slot -> the art of the enchant it had last (grey while missing)
local weapons = {}    -- slot -> the item in it, at the last look
local lastCast        -- { id, at }: the player's last successful cast

local function plain(v) return v ~= nil and not isSecret(v) end

-- The temporary enchant in a weapon slot's list: the entry with time left
-- (a permanent enchant has none).
local function read(ws)
    if not (C_Item and C_Item.GetWeaponEnchantInfo) then return nil end
    local ok, list = pcall(C_Item.GetWeaponEnchantInfo, ws)
    if not ok or isSecret(list) or type(list) ~= "table" then return nil end
    for _, e in pairs(list) do
        if type(e) == "table" and not isSecret(e) and plain(e.hasEnchant) and e.hasEnchant
            and plain(e.timeLeft) and e.timeLeft > 0 then
            return e
        end
    end
end

-- "Rockbiter 2 (60 min)" -> "Rockbiter": the weapon tooltip's timed line.
local function tooltipName(inv)
    if not (C_TooltipInfo and C_TooltipInfo.GetInventoryItem) then return nil end
    local ok, data = pcall(C_TooltipInfo.GetInventoryItem, "player", inv)
    if not ok or isSecret(data) or type(data) ~= "table" or type(data.lines) ~= "table" then return nil end
    for _, l in ipairs(data.lines) do
        local text = l.leftText
        if plain(text) and type(text) == "string" and text:find("%(%d+ [%a ]+%)") then
            local name = text:gsub("%s*%(.*%)%s*$", ""):gsub("%s+%d+$", "")
            if name ~= "" then return name end
        end
    end
end

local function itemName(inv)
    local link = GetInventoryItemLink("player", inv)
    return plain(link) and link and link:match("%[(.-)%]") or nil
end

function UI.WeaponEnchantable(slot)
    local s = SLOTS[slot]
    if not s then return false end
    if state[slot] then return true end
    local id = GetInventoryItemID("player", s.inv)
    if not plain(id) or not id then return false end
    local classID = select(6, C_Item.GetItemInfoInstant(id))
    return classID == (Enum.ItemClass and Enum.ItemClass.Weapon or 2)
end

function UI.WeaponEnchant(slot) return state[slot] or nil end
function UI.WeaponEnchantSpell(slot) return spellFor[slot] end

local ticker
local scan

-- Every weapon again; a change (an enchant on or off, another enchant, its
-- charges, another weapon) is announced once.
scan = function()
    local now, changed, any = GetTime(), false, false
    for _, slot in ipairs(ORDER) do
        local s = SLOTS[slot]
        local e = read(s.ws)
        local old = state[slot]
        local weapon = GetInventoryItemID("player", s.inv)
        weapon = plain(weapon) and weapon or nil
        if e then
            any = true
            local id = plain(e.enchantID) and e.enchantID or 0
            local left = e.timeLeft / 1000
            local prev = seen[slot]
            -- new: none before, another enchant, or put on again (more time
            -- than expected)
            local fresh = not old or not prev or prev.id ~= id or left > old.expires - now + 2
            if fresh then
                seen[slot] = { id = id, duration = left }
                if lastCast and now - lastCast.at < 1.5 then
                    spellFor[slot] = lastCast.id
                    lastCast = nil
                end
            end
            local key = slot .. ":" .. id
            if tipNames[key] == nil then tipNames[key] = tooltipName(s.inv) or false end
            local spell = spellFor[slot]
            local spellName = spell and C_Spell.GetSpellName(spell)
            local info = {
                slot = slot, enchantID = id, weaponID = weapon,
                icon = plain(e.enchantIconID) and e.enchantIconID ~= 0 and e.enchantIconID or GetInventoryItemTexture("player", s.inv),
                expires = now + left, duration = math.max(seen[slot].duration, left),
                charges = plain(e.charges) and e.charges or 0,
                name = (plain(spellName) and spellName) or tipNames[key] or nil,
                weapon = itemName(s.inv), spellID = spell,
            }
            if not old or old.enchantID ~= id or old.charges ~= info.charges or fresh then changed = true end
            state[slot] = info
            lastArt[slot] = info.icon
        else
            if old then changed = true end
            state[slot] = false
        end
        if weapons[slot] ~= weapon then changed = true end
        weapons[slot] = weapon
    end
    -- while one is up, a look each second (its charges, the end)
    if any and not ticker then
        ticker = C_Timer.NewTicker(1, function() scan() end)
    elseif not any and ticker then
        ticker:Cancel()
        ticker = nil
    end
    if changed then Events.Emit("SUUUI_WEAPON_ENCHANTS_CHANGED") end
end

local function later() C_Timer.After(0, scan) end
for _, e in ipairs({ "WEAPON_ENCHANT_CHANGED", "PLAYER_EQUIPMENT_CHANGED", "PLAYER_ENTERING_WORLD" }) do
    if not C_EventUtils or not C_EventUtils.IsEventValid or C_EventUtils.IsEventValid(e) then
        Events.OnGame(e, later, "WeaponEnchants")
    end
end
Events.OnUnit("UNIT_INVENTORY_CHANGED", "player", later, "WeaponEnchants")
Events.OnUnit("UNIT_SPELLCAST_SUCCEEDED", "player", function(_, _, _, spellID)
    if plain(spellID) and spellID then lastCast = { id = spellID, at = GetTime() } end
end, "WeaponEnchants")

--------------------------------------------------------------------------------
-- The icon: the buff icon's look (well, art, hairline, digits over a dark
-- fade, charges in the stack corner, the draining bar), and a weapon tag.
--------------------------------------------------------------------------------

-- 42, 1:30, 5m, 1h: the buff digits' format
local function digits(left)
    if left < 60 then return ("%d"):format(math.ceil(left)) end
    if left < 600 then
        local s = math.ceil(left)
        return ("%d:%02d"):format(math.floor(s / 60), s % 60)
    end
    if left < 3600 then return ("%dm"):format(math.floor(left / 60)) end
    return ("%dh"):format(math.floor(left / 3600))
end

-- 52 min, 1 h 5 min, 40 sec: the tooltip's
local function longTime(left)
    if left >= 3600 then
        return ("%d h %d min"):format(math.floor(left / 3600), math.floor(left % 3600 / 60))
    end
    if left >= 60 then return ("%d min"):format(math.floor(left / 60)) end
    return ("%d sec"):format(math.ceil(left))
end

local Icon = {}

function Icon:SetSlot(slot)
    self.slot = slot
    local text = SLOTS[slot] and SLOTS[slot].tag or ""
    self.tag.text:SetValue(text)
    self.tag:SetSize(math.ceil(UI.MeasureText("micro", text)) + 6, 11)
end
function Icon:SetMissing(mode) self.missing = mode end

function Icon:SetTag(shown)
    self.showTag = shown and true or false
    self.tag:SetShown(self.showTag and self.body:IsShown())
end

-- Another size: the bar, the fade and the digits follow (numeric digits from
-- 30 px, as on a buff).
function Icon:Resize(size)
    size = UI.Size(size)
    if size == self.size then return end
    self.size = size
    self:SetSize(size, size)
    local barH = size >= 30 and 3 or 2
    self.drain:SetHeight(barH)
    self.scrim:SetHeight(math.floor(size * 0.6))
    ns.Fonts.Apply(self.duration, size >= 30 and "numeric" or "micro")
    local path, height = self.duration:GetFont()
    if path then self.duration:SetFont(path, height, "OUTLINE") end
    self.duration:ClearAllPoints()
    self.duration:SetPoint("BOTTOM", 0, 1 + barH + (size >= 30 and 1 or 0))
end

local function setWarn(self, on)
    self.warnEdge:SetShown(on)
    if on and not self.warnPulse:IsPlaying() then
        self.warnPulse:Play()
    elseif not on and self.warnPulse:IsPlaying() then
        self.warnPulse:Stop()
    end
end

-- The digits, the bar and the amber blink, from the time left.
function Icon:Tick()
    local info = self.info
    if not info then return end
    local left = info.expires - GetTime()
    if left <= 0 then
        -- ended: look again (the game's event may come a moment later)
        self.info = nil
        scan()
        return
    end
    self.duration:SetText(digits(left))
    local amber = left < AMBER
    if amber ~= self.amber then
        self.amber = amber
        UI.Paint(self.duration, amber and "amber" or "ink")
        if amber then self.blink:Play() else self.blink:Stop(); self.text:SetAlpha(1) end
    end
    self.drain:SetValue(info.duration > 0 and math.min(1, left / info.duration) or 0)
end

function Icon:Refresh()
    if self.preview then return true end
    local info = self.slot and state[self.slot] or nil
    self.info = info
    if info then
        self.art:SetTexture(info.icon)
        self.art:SetDesaturated(false)
        self.art:SetVertexColor(1, 1, 1)
        self.body:SetAlpha(1)
        self.text:Show()
        self.drain:Show()
        self.stacks:SetText(info.charges > 0 and tostring(info.charges) or "")
        setWarn(self, false)
        self.amber = nil
        self:Tick()
        self:SetScript("OnUpdate", function(f, elapsed)
            f.acc = (f.acc or 0) + elapsed
            if f.acc >= 0.1 then f.acc = 0; f:Tick() end
        end)
        self.body:Show()
        self.tag:SetShown(self.showTag)
        return true
    end
    self:SetScript("OnUpdate", nil)
    self.blink:Stop()
    self.text:Hide()
    self.drain:Hide()
    if self.missing then
        -- the enchant it had (this session), else the weapon, in grey
        local s = SLOTS[self.slot]
        self.art:SetTexture(lastArt[self.slot] or (s and GetInventoryItemTexture("player", s.inv)) or 134400)
        self.art:SetDesaturated(true)
        self.body:SetAlpha(self.missing == "warn" and 0.85 or T.opacity["opacity-oor"])
        setWarn(self, self.missing == "warn")
        self.body:Show()
    else
        setWarn(self, false)
        self.body:Hide()
    end
    self.tag:SetShown(self.showTag and self.body:IsShown())
    return false
end

-- A made-up enchant for edit mode's preview: its art, 52m, three-quarters
-- left. Nil goes back to the real one.
function Icon:SetPreview(texture)
    self.preview = texture and true or nil
    if not texture then return self:Refresh() end
    self:SetScript("OnUpdate", nil)
    self.info = nil
    self.art:SetTexture(texture)
    self.art:SetDesaturated(false)
    self.art:SetVertexColor(1, 1, 1)
    self.body:SetAlpha(1)
    self.body:Show()
    self.text:Show()
    self.text:SetAlpha(1)
    self.blink:Stop()
    self.duration:SetText("52m")
    UI.Paint(self.duration, "ink")
    self.amber = nil
    self.stacks:SetText("")
    self.drain:Show()
    self.drain:SetValue(0.87)
    setWarn(self, false)
    self.tag:SetShown(self.showTag)
    return true
end

local function showTip(self)
    local slot = self.slot
    local s = SLOTS[slot]
    if not s or self.preview then return end
    local info = state[slot]
    local weapon = itemName(s.inv)
    local sub = weapon and (s.label .. " · " .. weapon) or s.label
    if info then
        local lines = { { "Time left", longTime(math.max(0, info.expires - GetTime())) } }
        if info.charges > 0 then lines[#lines + 1] = { "Charges", tostring(info.charges) } end
        UI.ShowTooltip(self, { title = info.name or (s.label .. " enchant"), subtitle = sub, lines = lines,
            meta = "Can't be removed from SuuUI: the game only lets you replace it." })
    else
        local spell = spellFor[slot]
        local spellName = spell and C_Spell.GetSpellName(spell)
        spellName = plain(spellName) and spellName or nil
        UI.ShowTooltip(self, { title = spellName or (s.label .. " enchant"), subtitle = sub,
            lines = { { "Not on the weapon" } },
            meta = spellName and ("Cast " .. spellName .. " to put it back.") or nil })
    end
end

function UI.WeaponEnchantIcon(parent, size)
    size = UI.Size(size or "icon-lg")
    local f = CreateFrame("Frame", nil, parent)
    Mixin(f, Icon)
    f:SetSize(size, size)
    f.size = size
    -- the icon itself (body), so a missing one can fade without its tag
    local body = CreateFrame("Frame", nil, f)
    body:SetAllPoints()
    f.body = body
    UI.Fill(body, "surface-sunk", "BACKGROUND"):SetAllPoints()
    f.art = body:CreateTexture(nil, "ARTWORK")
    f.art:SetPoint("TOPLEFT", 1, -1)
    f.art:SetPoint("BOTTOMRIGHT", -1, 1)
    f.art:SetTexCoord(CROP, 1 - CROP, CROP, 1 - CROP)
    local over = CreateFrame("Frame", nil, body)
    over:SetAllPoints()
    over:SetFrameLevel(body:GetFrameLevel() + 2)
    UI.Border(over, "gilt-hairline")
    -- Warn: an ember edge inside the square that pulses slowly (the
    -- Cooldown Manager's missing aura)
    f.warnEdge = UI.Border(over, "ember", { inset = 1, layer = "OVERLAY" })
    f.warnEdge:SetShown(false)
    f.warnPulse = body:CreateAnimationGroup()
    f.warnPulse:SetLooping("BOUNCE")
    local p = f.warnPulse:CreateAnimation("Alpha")
    p:SetFromAlpha(1)
    p:SetToAlpha(0.45)
    p:SetDuration(0.9)

    -- the duration bar inside the bottom edge, as on a buff
    local barH = size >= 30 and 3 or 2
    f.drain = CreateFrame("StatusBar", nil, body)
    f.drain:SetPoint("BOTTOMLEFT", 1, 1)
    f.drain:SetPoint("BOTTOMRIGHT", -1, 1)
    f.drain:SetHeight(barH)
    f.drain:SetStatusBarTexture(WHITE)
    f.drain:SetMinMaxValues(0, 1)
    UI.Paint(f.drain, "ink")
    f.drain:SetFrameLevel(body:GetFrameLevel() + 6)

    f.text = CreateFrame("Frame", nil, body)
    f.text:SetAllPoints()
    f.text:SetFrameLevel(body:GetFrameLevel() + 5)
    local scrim = f.text:CreateTexture(nil, "BACKGROUND")
    scrim:SetPoint("BOTTOMLEFT", 1, 1)
    scrim:SetPoint("BOTTOMRIGHT", -1, 1)
    scrim:SetHeight(math.floor(size * 0.6))
    scrim:SetColorTexture(1, 1, 1, 1)
    scrim:SetGradient("VERTICAL", CreateColor(0, 0, 0, 0.8), CreateColor(0, 0, 0, 0))
    f.scrim = scrim
    f.duration = f.text:CreateFontString(nil, "OVERLAY")
    ns.Fonts.Apply(f.duration, size >= 30 and "numeric" or "micro")
    f.duration:SetPoint("BOTTOM", 0, 1 + barH + (size >= 30 and 1 or 0))
    f.stacks = f.text:CreateFontString(nil, "OVERLAY")
    ns.Fonts.Apply(f.stacks, "micro")
    f.stacks:SetPoint("TOPRIGHT", -2, -1)
    for _, fs in ipairs({ f.duration, f.stacks }) do
        fs:SetShadowColor(0, 0, 0, 1)
        fs:SetShadowOffset(0, -1)
        local path, height = fs:GetFont()
        if path then fs:SetFont(path, height, "OUTLINE") end
    end
    UI.Paint(f.duration, "ink")
    UI.Paint(f.stacks, "ink")
    -- under a minute the digits blink
    f.blink = f.text:CreateAnimationGroup()
    f.blink:SetLooping("BOUNCE")
    local b = f.blink:CreateAnimation("Alpha")
    b:SetFromAlpha(1)
    b:SetToAlpha(0.35)
    b:SetDuration(0.5)

    -- the weapon's tag on the top-left corner, over the edge
    local tag = CreateFrame("Frame", nil, f)
    tag:SetFrameLevel(body:GetFrameLevel() + 8)
    tag:SetPoint("TOPLEFT", f, "TOPLEFT", -2, 3)
    UI.Fill(tag, "surface", "BACKGROUND"):SetAllPoints()
    UI.Border(tag, "gilt-line")
    tag.text = UI.Text(tag, "micro", "gilt-text")
    tag.text:SetPoint("CENTER", 0, 0)
    tag:SetSize(16, 11)
    f.tag = tag
    f.showTag = true

    -- a tooltip, no clicks: removing an enchant is forbidden
    if not pcall(f.SetMouseMotionEnabled, f, true) then f:EnableMouse(true) end
    pcall(f.SetMouseClickEnabled, f, false)
    f:SetScript("OnEnter", showTip)
    f:SetScript("OnLeave", function() UI.HideTooltip() end)
    return f
end

scan()
