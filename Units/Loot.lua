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
end

function M:OnDisable()
    if self.window then self.window:Hide() end
end
