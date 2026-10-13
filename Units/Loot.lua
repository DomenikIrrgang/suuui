-- Units/Loot.lua
-- The loot window (step 2.6a, design board "Loot window and loot rolls"):
-- what a corpse (a chest, a fishing catch) holds, beside the cursor with
-- the first item under it, or at its own place (edit mode). Click a row to
-- take it, shift-click to link; the tooltip is the game's.
-- A built-in module written against the public API only.
--
-- Blizzard's loot frame keeps opening and closing (Esc, bind confirmations
-- and auto loot stay the game's), off screen and see-through; SuuUI's
-- window follows LOOT_OPENED / LOOT_SLOT_CLEARED / LOOT_CLOSED. Taking an
-- item is LootSlot, which the game lets an addon call (probed 2026-10-13).
-- With auto loot on, the window shows only if something stays behind (bags
-- full, a bind confirmation).
--
-- Loot rolls (step 2.6b): each group roll is a request in the notification
-- stack (shown in combat too): the item, Need / Greed / (Disenchant) /
-- Pass with how many chose each (hover for who), your choice pressed in
-- arcane, the time left and a drain, amber under 10 s. Votes and the result
-- come from the game's loot lines in chat; the result follows as a note
-- that goes by itself. Blizzard's roll frames keep running off screen.
-- Choosing is RollOnLoot; a bind confirmation is the game's popup (hosted
-- by the notifications). Needs the Notifications module; without it,
-- Blizzard's roll frames show as always.

local UI, T = SuuUI.UI, SuuUI.Tokens

local M = SuuUI.RegisterModule({
    id = "loot",
    name = "Loot",
    description = "SuuUI's loot window, beside the cursor.",
    api = "0.12",
    reloadToToggle = true,
    defaults = {
        position = { point = "CENTER", x = -320, y = 60 },
        atCursor = true,
        rolls = true,
    },
})

local isSecret = issecretvalue or function() return false end
local function plain(v) return v ~= nil and not isSecret(v) end
local QUALITY = { [0] = "poor", "common", "uncommon", "rare", "epic", "legendary", "legendary", "legendary" }
local SLOT_MONEY = (Enum.LootSlotType and Enum.LootSlotType.Money) or 2

-- "42 Silver\n3 Copper" (the game's money slot name) → copper, or nil.
local function copperOf(text)
    if type(text) ~= "string" then return nil end
    local units = { [(GOLD or "Gold"):lower()] = 10000, [(SILVER or "Silver"):lower()] = 100, [(COPPER or "Copper"):lower()] = 1 }
    local total, found = 0, false
    for n, unit in text:gmatch("(%d+)%s+(%a+)") do
        local mult = units[unit:lower()]
        if mult then total, found = total + tonumber(n) * mult, true end
    end
    return found and total or nil
end

--------------------------------------------------------------------------------
-- What the corpse holds
--------------------------------------------------------------------------------

function M:Items()
    local items = {}
    local n = GetNumLootItems()
    if not plain(n) then return items end
    for slot = 1, n do
        local icon, name, count, _, quality, locked = GetLootSlotInfo(slot)
        if plain(icon) and icon then
            local item = { index = slot, icon = icon, label = plain(name) and name or "",
                count = plain(count) and count or 1, quality = plain(quality) and QUALITY[quality] or "common",
                locked = plain(locked) and locked or false }
            if GetLootSlotType(slot) == SLOT_MONEY then
                item.copper = copperOf(name)
                item.count = nil
                if not item.copper then item.label = (item.label or ""):gsub("\n", " ") end
            end
            items[#items + 1] = item
        end
    end
    return items
end

-- Whose loot: the dead target's name, "Fishing", or nothing.
local function sourceName()
    if IsFishingLoot and IsFishingLoot() then return "Fishing" end
    local guid = GetLootSourceInfo and GetLootSourceInfo(1)
    if plain(guid) and guid and plain(UnitGUID("target")) and UnitGUID("target") == guid then
        local name = UnitName("target")
        if plain(name) then return name end
    end
    return ""
end

function M:Update()
    local items = self:Items()
    self.window:SetItems(items)
    return #items
end

-- Beside the cursor with the first item under it, or at its place.
function M:Place()
    local w = self.window
    w:ClearAllPoints()
    if self:Get("atCursor") then
        local x, y = GetCursorPosition()
        local scale = w:GetEffectiveScale()
        local dx, dy = w:FirstSlotOffset()
        w:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", x / scale - dx, y / scale + dy)
    else
        local pos = self:Get("position")
        w:SetPoint(pos.point or "CENTER", SuuUI.Root, pos.point or "CENTER", pos.x or 0, pos.y or 0)
    end
end

function M:Open()
    if self:Update() == 0 then return end
    self.window:SetSource(sourceName())
    self:Place()
    self.window:Show()
end

--------------------------------------------------------------------------------
-- Blizzard's loot frame, off screen
--------------------------------------------------------------------------------

function M:Away()
    local f = _G.LootFrame
    if not f then return end
    f:SetAlpha(0)
    self.moving = true
    f:ClearAllPoints()
    f:SetPoint("BOTTOMRIGHT", UIParent, "TOPLEFT", -200, 200)
    self.moving = false
end

function M:HideBlizzardLoot()
    local f = _G.LootFrame
    if not f or self.hooked then return end
    self.hooked = true
    f:SetClampedToScreen(false)
    hooksecurefunc(f, "SetPoint", function()
        if self.moving or not self:IsEnabled() then return end
        f:SetAlpha(0)
        C_Timer.After(0, function() if self:IsEnabled() then self:Away() end end)
    end)
    f:HookScript("OnShow", function() if self:IsEnabled() then self:Away() end end)
    self:Away()
end

--------------------------------------------------------------------------------
-- Loot rolls
--------------------------------------------------------------------------------

local CHOICES = {
    { key = "need", label = "Need", type = LOOT_ROLL_TYPE_NEED or 1 },
    { key = "greed", label = "Greed", type = LOOT_ROLL_TYPE_GREED or 2 },
    { key = "disenchant", label = "Disenchant", type = LOOT_ROLL_TYPE_DISENCHANT or 3 },
    { key = "pass", label = "Pass", type = LOOT_ROLL_TYPE_PASS or 0 },
}
local CHOICE_BY_TYPE = {}
for _, c in ipairs(CHOICES) do CHOICE_BY_TYPE[c.type] = c end

-- The game's loot line formats as patterns: { pattern, order of captures }.
-- "%s has selected Need for: %s" → "^(.+) has selected Need for: (.+)$".
local function pattern(fmt)
    if type(fmt) ~= "string" then return nil end
    local out, order, auto, i = { "^" }, {}, 0, 1
    while i <= #fmt do
        local c = fmt:sub(i, i)
        if c == "%" then
            local pos, t = fmt:match("^%%(%d)%$([sd])", i)
            if pos then
                order[#order + 1] = tonumber(pos)
                out[#out + 1] = t == "d" and "(%d+)" or "(.+)"
                i = i + 4
            else
                t = fmt:match("^%%([sd])", i)
                if t then
                    auto = auto + 1
                    order[#order + 1] = auto
                    out[#out + 1] = t == "d" and "(%d+)" or "(.+)"
                else
                    out[#out + 1] = "%%" -- "%%": a percent sign
                end
                i = i + 2
            end
        else
            out[#out + 1] = c:find("[%^%$%(%)%.%[%]%*%+%-%?]") and ("%" .. c) or c
            i = i + 1
        end
    end
    out[#out + 1] = "$"
    return { table.concat(out), order }
end

local function match(pat, text)
    if not pat then return nil end
    local caps = { text:match(pat[1]) }
    if #caps == 0 then return nil end
    local out = {}
    for i, at in ipairs(pat[2]) do out[at] = caps[i] end
    return out
end

local LINES
local function lines()
    if LINES then return LINES end
    local me = UnitName("player")
    LINES = {}
    local function add(global, fn) local p = pattern(_G[global]); if p then LINES[#LINES + 1] = { p, fn } end end
    -- votes: (who, item)
    add("LOOT_ROLL_NEED", function(c) return "vote", c[1], c[2], "need" end)
    add("LOOT_ROLL_GREED", function(c) return "vote", c[1], c[2], "greed" end)
    add("LOOT_ROLL_DISENCHANT", function(c) return "vote", c[1], c[2], "disenchant" end)
    add("LOOT_ROLL_PASSED", function(c) return "vote", c[1], c[2], "pass" end)
    add("LOOT_ROLL_PASSED_AUTO", function(c) return "vote", c[1], c[2], "pass" end)
    add("LOOT_ROLL_PASSED_AUTO_FEMALE", function(c) return "vote", c[1], c[2], "pass" end)
    add("LOOT_ROLL_NEED_SELF", function(c) return "vote", me, c[1], "need" end)
    add("LOOT_ROLL_GREED_SELF", function(c) return "vote", me, c[1], "greed" end)
    add("LOOT_ROLL_DISENCHANT_SELF", function(c) return "vote", me, c[1], "disenchant" end)
    add("LOOT_ROLL_PASSED_SELF", function(c) return "vote", me, c[1], "pass" end)
    add("LOOT_ROLL_PASSED_SELF_AUTO", function(c) return "vote", me, c[1], "pass" end)
    -- the numbers: (value, item, who)
    add("LOOT_ROLL_ROLLED_NEED", function(c) return "rolled", c[3], c[2], "need", tonumber(c[1]) end)
    add("LOOT_ROLL_ROLLED_GREED", function(c) return "rolled", c[3], c[2], "greed", tonumber(c[1]) end)
    add("LOOT_ROLL_ROLLED_DE", function(c) return "rolled", c[3], c[2], "disenchant", tonumber(c[1]) end)
    -- the end
    add("LOOT_ROLL_WON", function(c) return "won", c[1], c[2] end)
    add("LOOT_ROLL_YOU_WON", function(c) return "won", me, c[1] end)
    add("LOOT_ROLL_ALL_PASSED", function(c) return "allPassed", nil, c[1] end)
    return LINES
end

local function itemKey(link)
    return type(link) == "string" and link:match("item:(%d+)") or link
end

local function short(name)
    return type(name) == "string" and (name:match("^([^%-]+)") or name) or name
end

-- A group member's class ("MAGE"), by name.
local function classOf(name)
    if short(name) == UnitName("player") then return select(2, UnitClass("player")) end
    local prefix, n = IsInRaid() and "raid" or "party", GetNumGroupMembers()
    for i = 1, n do
        local unit = prefix .. i
        local un = UnitName(unit)
        if plain(un) and un == short(name) then return select(2, UnitClass(unit)) end
    end
end

local function classColored(name, known)
    local class = (known and known[short(name)]) or classOf(name)
    local c = class and T.color["class-" .. class:lower()]
    return c and ("|cff" .. c.hex .. short(name) .. "|r") or short(name)
end

-- Everyone in your group but you, by name (the roll's own list in a test).
local function roster(roll)
    if roll.roster then return roll.roster end
    local out = {}
    if IsInRaid() then
        for i = 1, GetNumGroupMembers() do
            local name = UnitName("raid" .. i)
            if plain(name) and name and not UnitIsUnit("raid" .. i, "player") then out[#out + 1] = name end
        end
    else
        for i = 1, GetNumSubgroupMembers() do
            local name = UnitName("party" .. i)
            if plain(name) and name then out[#out + 1] = name end
        end
    end
    return out
end

local WAITING_SHOWN = 4

-- The roll's card, made again from what is known.
function M:ShowRoll(roll)
    local actions = {}
    for _, c in ipairs(CHOICES) do
        if c.key ~= "disenchant" or roll.canDisenchant then
            local who = roll.votes[c.key]
            local names = {}
            for _, name in ipairs(who) do names[#names + 1] = classColored(name, roll.classes) end
            local can = roll.can[c.key] ~= false
            actions[#actions + 1] = {
                label = c.label, count = #who, pressed = roll.choice == c.key,
                disabled = (roll.choice ~= nil and roll.choice ~= c.key) or not can,
                variant = "quiet",
                tooltip = (#who > 0 and { title = c.label .. " · " .. #who, description = table.concat(names, ", ") })
                    or (not can and roll.reason[c.key] and { title = c.label, description = roll.reason[c.key] }) or nil,
                onClick = function() self:Choose(roll, c) end,
            }
        end
    end
    -- who hasn't chosen yet: by name, in class colours (you aren't listed:
    -- your own buttons say whether you have)
    local chose = {}
    for _, c in ipairs(CHOICES) do
        for _, name in ipairs(roll.votes[c.key]) do chose[short(name)] = true end
    end
    local waiting = {}
    for _, name in ipairs(roster(roll)) do
        if not chose[short(name)] then waiting[#waiting + 1] = classColored(name, roll.classes) end
    end
    local body = {}
    if roll.bind then body[#body + 1] = roll.bind end
    local tip
    if #waiting > 0 then
        local shown = {}
        for i = 1, math.min(#waiting, WAITING_SHOWN) do shown[i] = waiting[i] end
        local line = "Waiting on " .. table.concat(shown, ", ")
        if #waiting > WAITING_SHOWN then line = line .. (" and %d more"):format(#waiting - WAITING_SHOWN) end
        body[#body + 1] = line
        tip = { title = "Still choosing · " .. #waiting, description = table.concat(waiting, ", ") }
    end
    local q = T.color["quality-" .. (roll.quality or "common")]
    SuuUI.Notify({
        id = "suu:roll:" .. roll.id, kind = "roll", category = "Loot roll",
        icon = { texture = roll.icon, tooltip = function(owner) self:ItemTip(owner, roll) end },
        title = (q and roll.quality ~= "common") and ("|cff" .. q.hex .. roll.name .. "|r") or roll.name,
        body = #body > 0 and table.concat(body, "\n") or nil, bodyTooltip = tip,
        duration = roll.duration, remaining = roll.remaining(),
        actions = actions,
    })
end

-- The item's tooltip: the game's for an open roll, else from its link.
function M:ItemTip(owner, roll, ended)
    GameTooltip:SetOwner(owner, "ANCHOR_RIGHT")
    if not ended and not roll.test and self.rolls[roll.id] and GameTooltip.SetLootRollItem then
        GameTooltip:SetLootRollItem(roll.id)
    else
        local ref = type(roll.link) == "string" and (roll.link:match("|H(item:[^|]+)|h") or roll.link)
        if not ref then GameTooltip:Hide() return end
        GameTooltip:SetHyperlink(ref)
    end
    GameTooltip:Show()
end

function M:Choose(roll, choice)
    if roll.choice then return end
    if roll.test then
        roll.choice = choice.key
        table.insert(roll.votes[choice.key], UnitName("player"))
        self:ShowRoll(roll)
        return
    end
    RollOnLoot(roll.id, choice.type)
    roll.choice = choice.key
    self:ShowRoll(roll)
end

local QUALITY_NAMES = QUALITY
function M:StartRoll(rollID, rollTime)
    if not plain(rollID) then return end
    local icon, name, count, quality, bop, canNeed, canGreed, canDE, reasonNeed, reasonGreed, reasonDE = GetLootRollItemInfo(rollID)
    if not plain(name) or not name then return end
    local function reason(r) return plain(r) and r and r > 0 and _G["LOOT_ROLL_INELIGIBLE_REASON" .. r] or nil end
    local start, duration = GetTime(), (plain(rollTime) and rollTime or 60000) / 1000
    local roll = {
        id = rollID, icon = icon, name = name, quality = plain(quality) and QUALITY_NAMES[quality] or "common",
        link = GetLootRollItemLink(rollID), duration = duration,
        bind = (plain(bop) and bop) and (ITEM_BIND_ON_PICKUP or "Binds when picked up") or nil,
        can = { need = plain(canNeed) and canNeed or false, greed = plain(canGreed) and canGreed or false, pass = true },
        canDisenchant = plain(canDE) and canDE or false,
        reason = { need = reason(reasonNeed), greed = reason(reasonGreed), disenchant = reason(reasonDE) },
        votes = { need = {}, greed = {}, disenchant = {}, pass = {} }, rolled = {},
        group = IsInGroup() and GetNumGroupMembers() or nil,
    }
    roll.can.disenchant = roll.canDisenchant
    roll.remaining = function()
        local left = GetLootRollTimeLeft(rollID)
        if plain(left) and left then return math.max(0, left / 1000) end
        return math.max(0, duration - (GetTime() - start))
    end
    self.rolls[rollID] = roll
    self:ShowRoll(roll)
end

function M:EndRoll(rollID)
    local roll = self.rolls[rollID]
    if not roll then return end
    self.rolls[rollID] = nil
    SuuUI.DismissNotification("suu:roll:" .. rollID)
    -- kept a moment for the result line, which can come after
    self.ended[#self.ended + 1] = roll
    roll.endedAt = GetTime()
    while #self.ended > 10 do table.remove(self.ended, 1) end
end

-- The roll a chat line is about: the oldest open one for that item (else
-- one just ended, for the result).
function M:RollFor(link, who, field)
    local key = itemKey(link)
    local best
    for _, roll in pairs(self.rolls) do
        if itemKey(roll.link) == key and (not field or not roll[field] or not roll[field][who]) then
            if not best or roll.id < best.id then best = roll end
        end
    end
    if best then return best end
    for i = #self.ended, 1, -1 do
        local roll = self.ended[i]
        if itemKey(roll.link) == key and GetTime() - roll.endedAt < 30 then return roll end
    end
end

function M:Result(roll, winner)
    local title, body
    local me = UnitName("player")
    if winner then
        local r = roll.rolled[short(winner)]
        title = (short(winner) == me and "You" or short(winner)) .. " won " .. roll.name
        local parts = {}
        if r then parts[#parts + 1] = r.label .. " " .. r.value end
        local mine = roll.rolled[me]
        if mine and short(winner) ~= me then parts[#parts + 1] = "you rolled " .. mine.label .. " " .. mine.value end
        body = #parts > 0 and table.concat(parts, " · ") or nil
    else
        title = "Everyone passed on " .. roll.name
    end
    SuuUI.Notify({ id = "suu:rollresult:" .. roll.id, kind = "timed", duration = 6, category = "Loot",
        icon = { texture = roll.icon, tooltip = function(owner) self:ItemTip(owner, roll, true) end },
        title = title, body = body })
end

function M:OnLootLine(text)
    if not plain(text) or type(text) ~= "string" then return end
    for _, line in ipairs(lines()) do
        local caps = match(line[1], text)
        if caps then
            local what, who, link, choice, value = line[2](caps)
            if what == "vote" then
                local roll = self:RollFor(link)
                if roll then
                    for _, c in ipairs(CHOICES) do
                        for i = #roll.votes[c.key], 1, -1 do
                            if roll.votes[c.key][i] == short(who) then table.remove(roll.votes[c.key], i) end
                        end
                    end
                    table.insert(roll.votes[choice], short(who))
                    if short(who) == UnitName("player") then roll.choice = choice end
                    if self.rolls[roll.id] then self:ShowRoll(roll) end
                end
            elseif what == "rolled" then
                local roll = self:RollFor(link)
                if roll then
                    local c
                    for _, x in ipairs(CHOICES) do if x.key == choice then c = x end end
                    roll.rolled[short(who)] = { label = c and c.label or choice, value = value }
                end
            elseif what == "won" or what == "allPassed" then
                local roll = self:RollFor(link)
                if roll and not roll.reported then
                    roll.reported = true
                    self:Result(roll, what == "won" and who or nil)
                end
            end
            return
        end
    end
end

-- Blizzard's roll frames off screen while SuuUI shows the rolls.
function M:HideBlizzardRolls()
    local f = _G.GroupLootContainer
    if not f or self.rollsHooked then return end
    self.rollsHooked = true
    local function away()
        f:SetAlpha(0)
        self.movingRolls = true
        f:ClearAllPoints()
        f:SetPoint("BOTTOMRIGHT", UIParent, "TOPLEFT", -200, 200)
        self.movingRolls = false
    end
    f:SetClampedToScreen(false)
    hooksecurefunc(f, "SetPoint", function()
        if self.movingRolls then return end
        f:SetAlpha(0)
        C_Timer.After(0, away)
    end)
    f:HookScript("OnShow", away)
    away()
end

-- A made-up 40-player raid: 39 others, votes coming in over the roll.
local RAID_NAMES = { "Ysolde", "Brannoc", "Morrow", "Kaelith", "Thessaly", "Veyra", "Orrin", "Ashka", "Doran", "Elspeth",
    "Fenwick", "Garra", "Hollis", "Isolde", "Jorund", "Kestra", "Lunara", "Maelis", "Nerith", "Oskar", "Perrin", "Quilla",
    "Rhosyn", "Sable", "Torvald", "Ulla", "Varek", "Wren", "Xandra", "Yorick", "Zephra", "Aldric", "Brisa", "Corin",
    "Delphine", "Eamon", "Faela", "Gideon", "Halvard" }
local RAID_CLASSES = { "WARRIOR", "PALADIN", "HUNTER", "ROGUE", "PRIEST", "SHAMAN", "MAGE", "WARLOCK", "DRUID" }

function M:TestRaidRoll(roll, id)
    roll.roster, roll.classes = {}, {}
    for i, name in ipairs(RAID_NAMES) do
        roll.roster[i] = name
        roll.classes[name] = RAID_CLASSES[(i * 7) % #RAID_CLASSES + 1]
    end
    roll.votes = { need = {}, greed = {}, disenchant = {}, pass = {} }
    roll.group = 40
    -- a shuffled order, most choose within 25 s, a few never do
    local order = {}
    for i, name in ipairs(RAID_NAMES) do order[i] = name end
    for i = #order, 2, -1 do
        local j = math.random(i)
        order[i], order[j] = order[j], order[i]
    end
    local picks = { "pass", "pass", "pass", "greed", "greed", "need" }
    for i = 1, #order - 3 do
        C_Timer.After(1 + i * 0.6, function()
            if not self.rolls[id] then return end
            table.insert(roll.votes[picks[math.random(#picks)]], order[i])
            self:ShowRoll(roll)
        end)
    end
end

-- /suu lootroll [raid]: a roll that isn't one (made-up votes; "raid": 40 players).
function M:TestRoll(arg)
    if not (SuuUI.GetModule("notifications") and SuuUI.GetModule("notifications"):IsEnabled()) then
        self:Print("Rolls show in the notification stack: turn the Notifications module on.")
        return
    end
    self.testRolls = (self.testRolls or 0) + 1
    local id = -self.testRolls
    local start = GetTime()
    local roll = {
        id = id, test = true, icon = 134939, name = "Plans: Protector's Silvered Chain Helm", quality = "rare",
        link = "item:251382",
        classes = { Ysolde = "PRIEST", Brannoc = "WARRIOR", Morrow = "ROGUE", Kaelith = "MAGE", Thessaly = "DRUID" },
        roster = { "Ysolde", "Brannoc", "Morrow", "Kaelith", "Thessaly" },
        duration = 30, bind = ITEM_BIND_ON_PICKUP or "Binds when picked up",
        can = { need = true, greed = true, pass = true }, reason = {},
        votes = { need = { "Ysolde" }, greed = { "Brannoc", "Morrow" }, disenchant = {}, pass = {} }, rolled = {}, group = 5,
    }
    roll.remaining = function() return math.max(0, 30 - (GetTime() - start)) end
    self.rolls[id] = roll
    if arg == "raid" then
        self:TestRaidRoll(roll, id)
    else
        -- someone makes up their mind, to see the waiting line change
        C_Timer.After(8, function()
            if not self.rolls[id] then return end
            table.insert(roll.votes.greed, "Kaelith")
            self:ShowRoll(roll)
        end)
    end
    self:ShowRoll(roll)
    C_Timer.After(30, function()
        if not self.rolls[id] then return end
        self:EndRoll(id)
        roll.rolled = { Ysolde = { label = "Need", value = 87 }, [UnitName("player")] = { label = "Need", value = 42 } }
        self:Result(roll, "Ysolde")
    end)
end

--------------------------------------------------------------------------------
-- Settings
--------------------------------------------------------------------------------

function M:PreviewView(parent)
    if not self.preview then
        local w = UI.LootWindow(parent)
        w.onClose = function() end
        w:SetSource("Ember Hound")
        w:SetItems({
            { icon = 133784, copper = 4203 },
            { icon = 134367, label = "Ember-touched Pelt", count = 2 },
            { icon = 135033, label = "Duskwater Mantle", quality = "uncommon" },
            { icon = 133722, label = "Broken Boar Tusk", quality = "poor" },
        })
        self.preview = w
    end
    self.preview:SetParent(parent)
    return self.preview
end

local SECTION = {
    id = "loot", label = "Loot", category = "General", order = 22,
    preview = function(parent) return M:PreviewView(parent) end,
    groups = {
        { title = "Loot window", description = "What a corpse, chest or catch holds. Click a row to take it, shift-click to link it. Auto loot works as always: the window shows only when something stays behind.", rows = {
            { key = "atCursor", label = "Beside the cursor", control = "toggle",
              description = "The first item opens under your cursor. Off: at its own place, which you move in edit mode." },
        } },
        { title = "Loot rolls", description = "Group rolls as requests in the notification stack, in combat too: Need, Greed or Pass with how many chose each (hover for who), the time left, and who won after. /suu lootroll shows a test roll.", rows = {
            { key = "rolls", label = "Rolls in the notification stack", control = "toggle",
              description = "Off, or with the Notifications module off: Blizzard's roll frames. Takes effect after a reload." },
        } },
    },
}

--------------------------------------------------------------------------------
-- Lifecycle
--------------------------------------------------------------------------------

function M:OnEnable()
    if not self.window then
        self.window = UI.LootWindow(SuuUI.Root, { name = "SuuUILoot" })
        self.window:SetFrameStrata("HIGH")
        self.window:SetToplevel(true)
        self.window:EnableMouse(true)
        self.window:SetClampedToScreen(true)
        self.window:Hide()
        self.window.suuManagedShow = true -- shown while you loot
        self.window.onClose = function() CloseLoot() end
        self.window.onClick = self:Guard(function(slot)
            if IsModifiedClick() then
                local link = GetLootSlotLink(slot)
                if link and HandleModifiedItemClick(link) then return end
            end
            LootSlot(slot)
        end)
        self.window.onEnter = function(slot, row)
            GameTooltip:SetOwner(row, "ANCHOR_RIGHT")
            local kind = GetLootSlotType(slot)
            if kind == SLOT_MONEY then
                GameTooltip:Hide()
                return
            end
            if kind == ((Enum.LootSlotType and Enum.LootSlotType.Currency) or 3) and GameTooltip.SetLootCurrency then
                GameTooltip:SetLootCurrency(slot)
            else
                GameTooltip:SetLootItem(slot)
            end
            GameTooltip:Show()
        end
        self.window.onLeave = function() GameTooltip:Hide() end
    end
    self:HideBlizzardLoot()
    self:RegisterMover(self.window, { key = "position", label = "Loot" })
    self:RegisterSettings(SECTION)
    self:OnGameEvent("LOOT_OPENED", function(_, autoLoot)
        self.open = true
        if plain(autoLoot) and autoLoot then
            -- auto loot: only what stays behind
            C_Timer.After(0.3, function() if self.open and not self.window:IsShown() then self:Open() end end)
        else
            self:Open()
        end
    end)
    for _, e in ipairs({ "LOOT_SLOT_CLEARED", "LOOT_SLOT_CHANGED" }) do
        self:OnGameEvent(e, function() if self.window:IsShown() then self:Update() end end)
    end
    self:OnGameEvent("LOOT_CLOSED", function()
        self.open = false
        self.window:Hide()
        GameTooltip:Hide()
    end)
    -- rolls
    self.rolls, self.ended = self.rolls or {}, self.ended or {}
    self:RegisterCommand("lootroll", "A test loot roll in the notification stack; \"/suu lootroll raid\": in a 40-player raid.",
        function(arg) self:TestRoll(arg) end)
    if self:RollsOn() then
        self:HideBlizzardRolls()
        self:OnGameEvent("START_LOOT_ROLL", function(_, rollID, rollTime) self:StartRoll(rollID, rollTime) end)
        self:OnGameEvent("CANCEL_LOOT_ROLL", function(_, rollID) if plain(rollID) then self:EndRoll(rollID) end end)
        self:OnGameEvent("CANCEL_ALL_LOOT_ROLLS", function()
            for id in pairs(self.rolls) do if id > 0 then self:EndRoll(id) end end
        end)
        self:OnGameEvent("CHAT_MSG_LOOT", function(_, text) self:OnLootLine(text) end)
        -- rolls already running (a /reload mid-roll)
        if GetActiveLootRollIDs then
            local ok, ids = pcall(GetActiveLootRollIDs)
            if ok and type(ids) == "table" then
                for _, id in ipairs(ids) do
                    local left = GetLootRollTimeLeft(id)
                    self:StartRoll(id, plain(left) and left or nil)
                end
            end
        end
    end
end

function M:RollsOn()
    local n = SuuUI.GetModule("notifications")
    return self:Get("rolls") and n and n:IsEnabled()
end

function M:OnDisable()
    if self.window then self.window:Hide() end
end
