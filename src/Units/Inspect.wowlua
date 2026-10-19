-- Units/Inspect.lua
-- SuuUI's own inspect window (plan 3.7, design component InspectWindow,
-- direction B "Side panel", chosen 2026-10-17): the inspected player's name,
-- level, race, class and guild; their gear on the Character window's paper
-- doll with each item's level; their 3D model; beside it the item level,
-- Player vs. Player and the guild. "Compare with mine" puts the difference
-- to your own item on each slot. The game's InspectFrame still runs the
-- inspect (it asks the server, closes when the target changes) but stays
-- out of sight; this window opens and closes with it. Nothing here is
-- protected (/suu probe windows, 2026-10-17).
-- View Talents opens SuuUI's Talents window with their talents, read only
-- (Forever's own inspect has no talents button: probed 2026-10-17).
-- A built-in module written against the public API only.

local UI, T = SuuUI.UI, SuuUI.Tokens
local S = T.space

local M = SuuUI.RegisterModule({
    id = "inspect",
    name = "Inspect",
    description = "SuuUI's inspect window: the player's gear with item levels, their model, item level, PvP and guild at a glance, and a comparison with your own gear.",
    api = "0.17",
    reloadToToggle = true,
    defaults = {},
})

local isSecret = issecretvalue or function() return false end
local function plain(v) return v ~= nil and not isSecret(v) end
local function call(fn, ...)
    if type(fn) ~= "function" then return nil end
    local ok, a, b, c, d, e, f, g, h, i = pcall(fn, ...)
    if ok then return a, b, c, d, e, f, g, h, i end
end

local SLOT = T.size["slot"]
local SIDE_W = 230
local MODEL_W = 300
local QUALITY = { [0] = "poor", "common", "uncommon", "rare", "epic", "legendary", "legendary", "legendary" }

-- the paper doll: the Character window's columns, weapons under the model
local LEFT = { "Head", "Neck", "Shoulder", "Back", "Chest", "Shirt", "Tabard", "Wrist" }
local RIGHT = { "Hands", "Waist", "Legs", "Feet", "Finger0", "Finger1", "Trinket0", "Trinket1" }
local WEAPONS = { "MainHand", "SecondaryHand", "Ranged" }
local LABEL = { Head = "Head", Neck = "Neck", Shoulder = "Shoulder", Back = "Back", Chest = "Chest", Shirt = "Shirt",
                Tabard = "Tabard", Wrist = "Wrist", Hands = "Hands", Waist = "Waist", Legs = "Legs", Feet = "Feet",
                Finger0 = "Finger", Finger1 = "Finger", Trinket0 = "Trinket", Trinket1 = "Trinket",
                MainHand = "Main hand", SecondaryHand = "Off hand", Ranged = "Ranged" }

-- The window fits what it holds: the identity line, the tools, the paper doll
-- (eight slots high, the weapons under it) beside the side panel.
local TOOLS_H = 26
local COL_H = #LEFT * SLOT + (#LEFT - 1) * S["space-2"]
local DOLL_W = 2 * (SLOT + S["space-4"]) + MODEL_W
local BODY_H = T.type["unit-name-lg"].lineHeight + S["space-4"] + TOOLS_H + S["space-5"] + COL_H + S["space-4"] + SLOT
local WIDTH = S["space-5"] + DOLL_W + S["space-6"] + SIDE_W + S["space-5"]
local HEIGHT = S["space-5"] + T.type.header.lineHeight + S["space-4"] + 1 + S["space-4"] + BODY_H + S["space-5"]

local function itemLevel(link)
    if not plain(link) then return nil end
    local lvl = call(C_Item and C_Item.GetDetailedItemLevelInfo or GetDetailedItemLevelInfo, link)
    return plain(lvl) and lvl > 0 and lvl or nil
end

-- the rank's name as the game's own inspect window words it
local function rankName(unit, rank)
    if not rank or rank <= 0 then return PVP_RANK_0_NAME or "Civilian" end
    local affix = (UnitFactionGroup(unit) == "Alliance") and "_1" or "_0"
    local key = "PVP_RANK_" .. tostring(((Enum.PvPRanks and Enum.PvPRanks.Rank_1) or 5) + rank - 1) .. affix
    local name = call(GetText, key, UnitSex(unit))
    if not plain(name) then return tostring(rank) end
    return PVP_RANK_NUMBER_AND_TITLE and PVP_RANK_NUMBER_AND_TITLE:format(rank, name) or name
end

--------------------------------------------------------------------------------
-- The window
--------------------------------------------------------------------------------

function M:BuildSlot(parent, key)
    local id = GetInventorySlotInfo(key .. "Slot")
    local b = UI.ItemSlot(parent, SLOT)
    b.slotID, b.key = id, key
    b:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    -- the slot's initial, while it's empty
    b.initial = UI.Text(b, "micro", "ink-faint", "OVERLAY")
    b.initial:SetPoint("CENTER")
    b.initial:SetValue(LABEL[key]:sub(1, 1))
    -- the item level, bottom left
    b.level = UI.Text(b, "micro", "ink", "OVERLAY")
    b.level:SetPoint("BOTTOMLEFT", 2, 1)
    b.level:SetShadowed(true)
    -- the difference to yours, a chip at the top right
    b.delta = CreateFrame("Frame", nil, b)
    b.delta:SetFrameLevel(b:GetFrameLevel() + 3)
    b.delta:SetPoint("TOPRIGHT", 3, 4)
    b.delta:SetSize(20, 12)
    UI.Fill(b.delta, "surface-sunk"):SetAllPoints()
    UI.Border(b.delta, "gilt-faint")
    b.delta.text = UI.Text(b.delta, "micro", "gilt-text", "OVERLAY")
    b.delta.text:SetPoint("CENTER", 0, 0)
    b.delta:Hide()
    b:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        if not (M.unit and GameTooltip:SetInventoryItem(M.unit, self.slotID)) then
            GameTooltip:SetText(LABEL[self.key])
        end
        GameTooltip:Show()
    end)
    b:SetScript("OnLeave", function() GameTooltip:Hide() end)
    b:SetScript("OnClick", function(self)
        local link = M.unit and GetInventoryItemLink(M.unit, self.slotID)
        if link then HandleModifiedItemClick(link) end
    end)
    self.slots[#self.slots + 1] = b
    return b
end

-- One block of the side panel: a header and rows under it.
local function block(parent, title)
    local f = CreateFrame("Frame", nil, parent)
    f.head = UI.Text(f, "header", "gilt-text")
    f.head:SetPoint("TOPLEFT")
    f.head:SetValue(title)
    f.y = T.type.header.lineHeight + S["space-3"]
    return f
end

local function row(f, label)
    local l = UI.Text(f, "caption", "ink-muted")
    l:SetPoint("TOPLEFT", 0, -f.y)
    local v = UI.Text(f, "numeric", "ink")
    v:SetPoint("TOPRIGHT", 0, -f.y + 1)
    l:SetValue(label)
    f.y = f.y + T.type.numeric.lineHeight + S["space-3"]
    return v
end

-- The item level's big figure and the block's height: from the text styles,
-- so again when a theme changes them.
function M:SizeItemLevel()
    local il = self.ilvl
    il.big:SetFont(T.type.numeric.file, 28, "")
    il:SetHeight(il.y + 34 + T.type.caption.lineHeight)
end

function M:Build()
    self.slots = {}
    local w = UI.WindowFrame(SuuUI.Root, { name = "SuuUIInspectWindow", title = "Inspect", width = WIDTH, height = HEIGHT,
        onClose = function(win) win:Hide() end })
    w:SetPoint("TOPLEFT", UIParent, "TOPLEFT", 16, -116)
    w:Hide()
    w.scroll:Hide()
    self.window = w
    w:HookScript("OnHide", function()
        local f = _G.InspectFrame
        if f and f:IsShown() then HideUIPanel(f) end
        self.unit, self.loading = nil, nil
    end)
    local body = w.body

    -- the identity: class diamond, the name in its class colour, the line, the guild
    local id = CreateFrame("Frame", nil, body)
    id:SetPoint("TOPLEFT")
    id:SetPoint("TOPRIGHT")
    id:SetHeight(T.type["unit-name-lg"].lineHeight)
    id.diamond = UI.Diamond(id, 7, "ink", "OVERLAY")
    id.diamond:SetPoint("CENTER", id, "LEFT", 4, 0)
    id.name = UI.Text(id, "unit-name-lg", "ink")
    id.name:SetPoint("LEFT", 8 + S["space-3"], 0)
    id.line = UI.Text(id, "caption", "ink-muted")
    id.line:SetPoint("LEFT", id.name, "RIGHT", S["space-4"], -1)
    id.guild = UI.Text(id, "caption", "gilt-text")
    id.guild:SetPoint("LEFT", id.line, "RIGHT", S["space-4"], 0)
    self.idRow = id

    -- the tools: Compare with mine; View in Dressing Room and View Talents
    local tools = CreateFrame("Frame", nil, body)
    tools:SetPoint("TOPLEFT", id, "BOTTOMLEFT", 0, -S["space-4"])
    tools:SetPoint("TOPRIGHT", id, "BOTTOMRIGHT", 0, -S["space-4"])
    tools:SetHeight(TOOLS_H)
    self.compareToggle = UI.Toggle(tools, { value = self.compare, onChange = function(on)
        self.compare = on
        self:Draw()
    end })
    self.compareToggle:SetPoint("LEFT")
    local cl = CreateFrame("Button", nil, tools)
    cl.text = UI.Text(cl, "label", "ink")
    cl.text:SetPoint("LEFT")
    cl.text:SetValue("Compare with mine")
    cl:SetSize(UI.MeasureText("label", "Compare with mine"), TOOLS_H)
    cl:SetPoint("LEFT", self.compareToggle, "RIGHT", S["space-4"], 0)
    cl:SetScript("OnClick", function() self.compareToggle:Click() end)
    self.talentsButton = UI.Button(tools, { text = "View Talents", icon = "tree", onClick = function()
        if self.unit then SuuUI.ShowTalentsOf(self.unit) end
    end })
    self.talentsButton:SetHeight(TOOLS_H)
    self.talentsButton:SetPoint("RIGHT")
    self.dressButton = UI.Button(tools, { text = "View in Dressing Room", icon = "person", onClick = function()
        local list = call(C_TransmogCollection.GetInspectItemTransmogInfoList)
        if list then DressUpItemTransmogInfoList(list) end
    end })
    self.dressButton:SetHeight(TOOLS_H)
    self.dressButton:SetPoint("RIGHT", self.talentsButton, "LEFT", -S["space-4"], 0)

    -- the side panel: item level, Player vs. Player, guild
    local side = CreateFrame("Frame", nil, body)
    side:SetPoint("TOPRIGHT", tools, "BOTTOMRIGHT", 0, -S["space-5"])
    side:SetPoint("BOTTOMRIGHT")
    side:SetWidth(SIDE_W)
    self.side = side
    local il = block(side, "Item level")
    il:SetPoint("TOPLEFT")
    il:SetPoint("TOPRIGHT")
    il.big = UI.Text(il, "numeric", "ink")
    il.big:SetPoint("TOPLEFT", 0, -il.y)
    il.note = UI.Text(il, "caption", "ink-muted")
    il.note:SetPoint("TOPLEFT", 0, -(il.y + 34))
    self.ilvl = il
    self:SizeItemLevel()
    local pvp = block(side, "Player vs. Player")
    pvp:SetPoint("TOPLEFT", il, "BOTTOMLEFT", 0, -S["space-6"])
    pvp:SetPoint("TOPRIGHT", il, "BOTTOMRIGHT", 0, -S["space-6"])
    pvp.rank = row(pvp, "Rank")
    pvp.rank:SetStyle("label")
    pvp.points = row(pvp, "Rank points")
    pvp.bar = UI.StatusBar(pvp, { width = SIDE_W, height = 6, fill = "progress-fill", deep = false })
    pvp.bar:SetPoint("TOPLEFT", 0, -pvp.y)
    pvp.y = pvp.y + 6 + S["space-3"]
    pvp.today = row(pvp, "Honorable kills today")
    pvp.lifetime = row(pvp, "Lifetime")
    pvp:SetHeight(pvp.y)
    self.pvp = pvp
    local guild = block(side, "Guild")
    guild:SetPoint("TOPLEFT", pvp, "BOTTOMLEFT", 0, -S["space-6"])
    guild:SetPoint("TOPRIGHT", pvp, "BOTTOMRIGHT", 0, -S["space-6"])
    guild.icon = UI.Icon(guild, "icon-lg")
    guild.icon:SetPoint("TOPLEFT", 0, -guild.y)
    guild.icon:SetArt("Interface\\AddOns\\SuuUI\\Media\\Textures\\Glyphs\\tabard")
    guild.name = UI.Text(guild, "label", "ink")
    guild.name:SetPoint("TOPLEFT", guild.icon, "TOPRIGHT", S["space-4"], -2)
    guild.line = UI.Text(guild, "caption", "ink-muted")
    guild.line:SetPoint("TOPLEFT", guild.name, "BOTTOMLEFT", 0, -2)
    guild.none = UI.Text(guild, "caption", "ink-muted")
    guild.none:SetPoint("TOPLEFT", 0, -guild.y)
    guild.none:SetValue("Not in a guild")
    guild:SetHeight(guild.y + 40)
    self.guild = guild

    -- the paper doll: two slot columns, the model between, weapons under it
    local doll = CreateFrame("Frame", nil, body)
    doll:SetPoint("TOPLEFT", tools, "BOTTOMLEFT", 0, -S["space-5"])
    doll:SetPoint("BOTTOMRIGHT", side, "BOTTOMLEFT", -S["space-6"], 0)
    local prev
    for _, key in ipairs(LEFT) do
        local b = self:BuildSlot(doll, key)
        b:SetPoint("TOPLEFT", prev or doll, prev and "BOTTOMLEFT" or "TOPLEFT", 0, prev and -S["space-2"] or 0)
        prev = b
    end
    prev = nil
    for _, key in ipairs(RIGHT) do
        local b = self:BuildSlot(doll, key)
        b:SetPoint("TOPRIGHT", prev or doll, prev and "BOTTOMRIGHT" or "TOPRIGHT", 0, prev and -S["space-2"] or 0)
        prev = b
    end
    local box = CreateFrame("Frame", nil, doll)
    box:SetPoint("TOPLEFT", SLOT + S["space-4"], 0)
    box:SetPoint("TOPRIGHT", -(SLOT + S["space-4"]), 0)
    box:SetHeight(COL_H)
    UI.Fill(box, "surface-sunk"):SetAllPoints()
    UI.Border(box, "gilt-faint")
    box:SetClipsChildren(true)
    local model = CreateFrame("PlayerModel", nil, box)
    model:SetPoint("TOPLEFT", 1, -1)
    model:SetPoint("BOTTOMRIGHT", -1, 1)
    model:EnableMouse(true)
    model:EnableMouseWheel(true)
    -- drag to turn, the wheel to zoom
    model:SetScript("OnMouseDown", function(m, button) if button == "LeftButton" then m.turning = GetCursorPosition() end end)
    model:SetScript("OnMouseUp", function(m) m.turning = nil end)
    model:SetScript("OnUpdate", function(m)
        if not m.turning then return end
        local x = GetCursorPosition()
        m:SetFacing((m:GetFacing() or 0) + (x - m.turning) * 0.01)
        m.turning = x
    end)
    model:SetScript("OnMouseWheel", function(m, delta)
        m.zoom = math.max(0, math.min(0.8, (m.zoom or 0) + delta * 0.1))
        m:SetPortraitZoom(m.zoom)
    end)
    self.model = model
    box.note = UI.Text(box, "caption", "ink-muted", "OVERLAY")
    box.note:SetPoint("CENTER", 0, -30)
    box.loading = UI.LoadingMark(box, { size = 40 })
    box.loading:SetPoint("CENTER", 0, 10)
    self.box = box
    local weapons = CreateFrame("Frame", nil, doll)
    weapons:SetSize(#WEAPONS * SLOT + (#WEAPONS - 1) * S["space-2"], SLOT)
    weapons:SetPoint("TOP", box, "BOTTOM", 0, -S["space-4"])
    prev = nil
    for _, key in ipairs(WEAPONS) do
        local b = self:BuildSlot(weapons, key)
        b:SetPoint("LEFT", prev or weapons, prev and "RIGHT" or "LEFT", prev and S["space-2"] or 0, 0)
        prev = b
    end
end

--------------------------------------------------------------------------------
-- Drawing
--------------------------------------------------------------------------------

function M:DrawSlot(b)
    local unit, s = self.unit, b.skin
    local texture = unit and not self.loading and GetInventoryItemTexture(unit, b.slotID)
    b.delta:Hide()
    b.level:SetValue("")
    if not texture then
        s:SetItem(nil)
        b.initial:SetShown(not self.loading)
        b:SetAlpha(self.loading and 0.6 or 1)
        return
    end
    b:SetAlpha(1)
    b.initial:Hide()
    local quality = GetInventoryItemQuality(unit, b.slotID)
    s:SetItem({ icon = texture, quality = QUALITY[quality] })
    local level = itemLevel(GetInventoryItemLink(unit, b.slotID))
    if level then b.level:SetValue(level) end
    if self.compare and level then
        local mine = itemLevel(GetInventoryItemLink("player", b.slotID))
        local d = mine and level - mine or 0
        if d ~= 0 then
            b.delta.text:SetValue((d > 0 and "▲" or "▼") .. math.abs(d))
            b.delta.text:SetColor(d > 0 and "gilt-text" or "ember-text")
            b.delta:SetWidth(UI.MeasureText("micro", b.delta.text:GetText() or "") + 6)
            b.delta:Show()
        end
    end
end

function M:Draw()
    local unit, w = self.unit, self.window
    if not unit or not w then return end
    -- who
    local name = GetUnitName(unit, true)
    local _, class = UnitClass(unit)
    local token = class and "class-" .. class:lower()
    if token and T.color[token] then
        UI.Paint(self.idRow.diamond, token)
        self.idRow.name:SetColor(token)
    end
    self.idRow.name:SetValue(plain(name) and name or "")
    local parts = {}
    local level = UnitLevel(unit)
    parts[#parts + 1] = "Level " .. ((plain(level) and level > 0) and level or "??")
    local race = UnitRace(unit)
    if plain(race) then parts[#parts + 1] = race end
    local className = UnitClass(unit)
    if plain(className) then parts[#parts + 1] = className end
    self.idRow.line:SetValue(table.concat(parts, " · "))
    local _, members, guildName = call(C_PaperDollInfo.GetInspectGuildInfo, unit)
    if self.loading or not plain(guildName) or guildName == "" then guildName = nil end
    self.idRow.guild:SetValue(guildName and ("<" .. guildName .. ">") or "")
    -- gear
    for _, b in ipairs(self.slots) do self:DrawSlot(b) end
    -- the model, or why there's none
    if self.loading then
        self.model:Hide()
        self.box.loading:Show()
        self.box.loading:Start()
        self.box.note:SetValue("Reading their gear…")
    else
        self.box.loading:Stop()
        self.box.loading:Hide()
        -- SetUnit says nothing on Forever: whether the game has them in sight does
        local near = UnitIsVisible(unit)
        near = not plain(near) or near
        if near then self.model:SetUnit(unit) end
        self.model:SetShown(near and true or false)
        self.box.note:SetValue(near and "" or "Too far away to show")
    end
    -- item level
    local il = self.ilvl
    local avg
    if not self.loading then avg = call(C_PaperDollInfo.GetInspectItemLevel, unit) end
    il.big:SetValue((plain(avg) and avg > 0) and math.floor(avg + 0.5) or "—")
    local mine = call(GetAverageItemLevel)
    if self.compare and plain(mine) then
        il.note:SetValue("Yours: " .. math.floor(mine + 0.5))
    else
        il.note:SetValue("Average of what they wear")
    end
    -- Player vs. Player
    local today, lifetime, rank, points, nextAt
    if not self.loading then
        local t, _, _, _, l, _, r, p, n = call(GetInspectHonorData)
        today, lifetime, rank, points, nextAt = t, l, r, p, n
    end
    local pvp = self.pvp
    pvp.rank:SetValue(rankName(unit, plain(rank) and rank or 0))
    points, nextAt = plain(points) and points or 0, (plain(nextAt) and nextAt > 0) and nextAt or 0
    pvp.points:SetValue(nextAt > 0 and (points .. " / " .. nextAt) or tostring(points))
    pvp.bar:SetValueNow(nextAt > 0 and math.min(1, points / nextAt) or 0)
    pvp.today:SetValue(plain(today) and today or 0)
    pvp.lifetime:SetValue(plain(lifetime) and lifetime or 0)
    -- guild
    local g = self.guild
    g.icon:SetShown(guildName ~= nil)
    g.name:SetValue(guildName or "")
    local _, faction = UnitFactionGroup(unit)
    local line = plain(faction) and INSPECT_GUILD_FACTION and INSPECT_GUILD_FACTION:format(faction) or ""
    if plain(members) and members > 0 and INSPECT_GUILD_NUM_MEMBERS then
        line = line .. (line ~= "" and " · " or "") .. INSPECT_GUILD_NUM_MEMBERS:format(members)
    end
    g.line:SetValue(guildName and line or "")
    g.none:SetShown(guildName == nil and not self.loading)
    -- the buttons wait for the gear
    self.dressButton:SetEnabledState(not self.loading)
    local module = SuuUI.GetModule("talents")
    local why
    if self.loading then why = "Waiting for their gear."
    elseif not (module and module:IsEnabled()) then why = "SuuUI's Talents module is off."
    elseif not call(C_Traits.HasValidInspectData) then why = "Their talents aren't available." end
    self.talentsButton:SetEnabledState(why == nil)
    self.talentsButton.tooltip = why and { title = "View Talents", description = why } or nil
end

--------------------------------------------------------------------------------
-- With the game's inspect frame
--------------------------------------------------------------------------------

-- The game's frame out of sight: see-through and off screen, still shown,
-- and back off screen whenever the game places it again.
function M:Away(frame)
    if not frame or self.away then return end
    self.away = true
    local placing = false
    local function away()
        if not self:IsEnabled() then return end
        placing = true
        frame:SetAlpha(0)
        frame:ClearAllPoints()
        frame:SetPoint("TOPLEFT", UIParent, "TOPRIGHT", 5000, 0)
        placing = false
    end
    away()
    hooksecurefunc(frame, "SetPoint", function() if not placing then C_Timer.After(0, away) end end)
    frame:HookScript("OnShow", function() C_Timer.After(0, away) end)
end

-- Asked: the window opens at once, waiting for the gear.
function M:Asked(unit)
    local f = _G.InspectFrame
    if not (f and f.unit) then return end
    self.unit, self.loading = f.unit, true
    self:Away(f)
    self.window:Show()
    self:Draw()
    -- the answer comes with INSPECT_READY; if it never does, show what there is
    local asked = self.unit
    C_Timer.After(5, function()
        if self.loading and self.unit == asked and self.window:IsShown() then
            self.loading = false
            self:Draw()
        end
    end)
end

function M:Ready()
    local f = _G.InspectFrame
    if not (f and f.unit) then return end
    self.unit, self.loading = f.unit, false
    self:Away(f)
    if not self.window:IsShown() then self.window:Show() end
    self:Draw()
end

function M:HookInspect()
    local f = _G.InspectFrame
    if not f or self.hooked then return end
    self.hooked = true
    hooksecurefunc("InspectFrame_Show", function(unit)
        if self:IsEnabled() then self:Asked(unit) end
    end)
    f:HookScript("OnShow", function()
        if self:IsEnabled() then self:Ready() end
    end)
    f:HookScript("OnHide", function()
        if self:IsEnabled() and self.window:IsShown() and not self.loading then self.window:Hide() end
    end)
end

function M:OnEnable()
    if not self.window then self:Build() end
    self:HookInspect()
    self:OnGameEvent("ADDON_LOADED", function(_, name) if name == "Blizzard_InspectUI" then self:HookInspect() end end)
    self:OnGameEvent("INSPECT_READY", function(_, guid)
        if self.unit and self.window:IsShown() and UnitGUID(self.unit) == guid then
            self.loading = false
            self:Draw()
        end
    end)
    -- a new target while waiting: the game drops the question, so does this
    self:OnGameEvent("PLAYER_TARGET_CHANGED", function()
        if self.unit == "target" and self.loading and self.window:IsShown() then self.window:Hide() end
    end)
    for _, e in ipairs({ "UNIT_INVENTORY_CHANGED", "UNIT_MODEL_CHANGED", "UNIT_LEVEL" }) do
        self:OnGameEvent(e, function(_, unit)
            if unit and unit == self.unit and self.window:IsShown() then self:Draw() end
        end)
    end
    for _, e in ipairs({ "INSPECT_HONOR_UPDATE", "PLAYER_EQUIPMENT_CHANGED", "GET_ITEM_INFO_RECEIVED" }) do
        self:OnGameEvent(e, function() if self.window:IsShown() then self:Draw() end end)
    end
    self:On("SUUUI_THEME_CHANGED", function() self:SizeItemLevel() end)
end

function M:OnDisable()
    if self.window then self.window:Hide() end
end
