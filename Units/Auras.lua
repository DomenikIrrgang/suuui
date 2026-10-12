-- Units/Auras.lua
-- Auras (step 1.4). A built-in module written against the public API only;
-- everything is an engine aura container (UI.AuraContainer), because addon
-- code can't read auras in combat.
--
-- Placement (2560x1440 reference):
--   your buffs     top right, left of the minimap (224px from the right
--                  edge, space-7 down like the minimap's top), growing left;
--                  right click cancels
--   your debuffs   above the player frame, right-aligned, growing left
--   on the target  your debuffs (and, on a friend, your buffs: HoTs,
--                  shields) above the target frame, growing right
--   focus          your debuffs after its bar
--   bosses         your debuffs left of each boss bar, growing left
--
-- Blizzard's BuffFrame and DebuffFrame are stood down; they come back after
-- a reload, so this module turns off or on with a reload. Temporary weapon
-- enchants (poisons, oils) aren't shown yet.

local UI, T = SuuUI.UI, SuuUI.Tokens
local S = T.space

local M = SuuUI.RegisterModule({
    id = "auras",
    name = "Auras",
    description = "Your buffs and debuffs, and your debuffs on your target, focus and bosses.",
    api = "0.6",
    reloadToToggle = true,
    defaults = {
        buffPosition = { point = "TOPRIGHT", x = -224, y = -28 },
        showBuffs = true,
        showDebuffs = true,
        showTarget = true,
        showFocus = true,
        showBoss = true,
    },
})

-- The containers that hang off a unit frame: where, and which setting.
local ATTACHED = {
    player = { key = "showDebuffs", build = function(frame)
        local c = UI.AuraContainer(frame, "player", {
            size = "icon-lg", anchor = "BOTTOMRIGHT", growth = { "LEFT", "UP" }, lineWidth = 300,
            groups = { { key = "debuffs", filter = { "HARMFUL" }, max = 16, dispel = true } },
        })
        if c then c.container:SetPoint("BOTTOMRIGHT", frame, "TOPRIGHT", 0, S["space-4"]) end
        return c
    end },
    target = { key = "showTarget", build = function(frame)
        local c = UI.AuraContainer(frame, "target", {
            size = "icon-md", anchor = "BOTTOMLEFT", growth = { "RIGHT", "UP" }, lineWidth = 220,
            groups = {
                { key = "mine", filter = { "HARMFUL", "PLAYER" }, max = 12, dispel = false },
                { key = "myBuffs", filter = { "HELPFUL", "PLAYER" }, max = 6, drain = "fel" },
            },
        })
        if c then c.container:SetPoint("BOTTOMLEFT", frame, "TOPLEFT", 0, S["space-4"]) end
        return c
    end },
    focus = { key = "showFocus", build = function(frame)
        local c = UI.AuraContainer(frame, "focus", {
            size = "icon-md", anchor = "LEFT", growth = { "RIGHT", "DOWN" },
            groups = { { key = "mine", filter = { "HARMFUL", "PLAYER" }, max = 4 } },
        })
        if c then c.container:SetPoint("LEFT", frame, "RIGHT", S["space-2"], 0) end
        return c
    end },
}
for i = 1, 5 do
    ATTACHED["boss" .. i] = { key = "showBoss", build = function(frame)
        local c = UI.AuraContainer(frame, "boss" .. i, {
            size = "icon-md", anchor = "RIGHT", growth = { "LEFT", "DOWN" },
            groups = { { key = "mine", filter = { "HARMFUL", "PLAYER" }, max = 4 } },
        })
        if c then c.container:SetPoint("RIGHT", frame, "LEFT", -S["space-2"], 0) end
        return c
    end }
end

function M:Attach(name, frame)
    local def = ATTACHED[name]
    if not def then return end
    local c = self.attached[name]
    if frame and not c then
        c = def.build(frame)
        self.attached[name] = c
    end
    if c then c.container:SetShown(frame ~= nil and self:Get(def.key)) end
end

function M:ApplyOptions()
    for name in pairs(ATTACHED) do self:Attach(name, SuuUI.GetAnchor(name)) end
    if self.buffs then
        local pos = self:Get("buffPosition")
        self.buffs.container:SetShown(self:Get("showBuffs") and not pos.hidden)
    end
end

local SECTION = {
    id = "auras", label = "Auras", category = "Frames", order = 15,
    groups = {
        { title = "Auras", description = "In combat the game hides which spell an aura is from addons, so the game itself fills these in: SuuUI only styles them.", rows = {
            { key = "showBuffs", label = "Your buffs", control = "toggle",
              description = "Top right, left of the minimap. Right click cancels one." },
            { key = "showDebuffs", label = "Your debuffs", control = "toggle",
              description = "Above the player frame; a debuff with a type wears its dispel colour." },
            { key = "showTarget", label = "On your target", control = "toggle",
              description = "Your debuffs on it, and your buffs on a friend (HoTs, shields), above the target frame." },
            { key = "showFocus", label = "On your focus", control = "toggle", description = "Your debuffs, after the focus bar." },
            { key = "showBoss", label = "On bosses", control = "toggle", description = "Your debuffs, left of each boss bar." },
        } },
    },
}

function M:OnEnable()
    SuuUI.SuppressBlizzard("BuffFrame")
    SuuUI.SuppressBlizzard("DebuffFrame")

    if not self.attached then
        self.attached = {}
        -- Your buffs: their own movable holder, top right.
        local holder = CreateFrame("Frame", "SuuUIPlayerBuffs", SuuUI.Root)
        holder:SetSize(16 * (UI.Size("icon-lg") + S["space-2"]), 2 * (UI.Size("icon-lg") + S["space-2"]))
        self.buffHolder = holder
        self.buffs = UI.AuraContainer(holder, "player", {
            size = "icon-lg", anchor = "TOPRIGHT", growth = { "LEFT", "DOWN" }, lineWidth = holder:GetWidth(),
            groups = { { key = "buffs", filter = { "HELPFUL" }, max = 32, cancel = true } },
        })
        if self.buffs then self.buffs.container:SetPoint("TOPRIGHT", holder, "TOPRIGHT") end
    end
    self.buffHolder.suuManagedShow = true
    self:RegisterMover(self.buffHolder, { key = "buffPosition", label = "Your buffs",
        enabled = function() return self:Get("showBuffs") end })
    self:Watch("showBuffs", SuuUI.EditMode.Refresh)
    self:RegisterSettings(SECTION)
    self:ApplyOptions()

    self:On("SUUUI_ANCHOR_CHANGED", function(_, name, frame) self:Attach(name, frame) end)
    for _, key in ipairs({ "showBuffs", "showDebuffs", "showTarget", "showFocus", "showBoss", "buffPosition" }) do
        self:Watch(key, function() self:ApplyOptions() end)
    end
end

function M:OnDisable()
    if self.buffs then self.buffs.container:Hide() end
    for _, c in pairs(self.attached or {}) do c.container:Hide() end
end
