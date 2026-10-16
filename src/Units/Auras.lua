-- Units/Auras.lua
-- Auras (step 1.4). A built-in module written against the public API only;
-- everything is an engine aura container (UI.AuraContainer), because addon
-- code can't read auras in combat.
--
-- Placement (2560x1440 reference):
--   your buffs     top right, left of the minimap (224px from the right
--                  edge, space-7 down like the minimap's top), growing left
--                  (or right), 16 to a row by default; right click cancels
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
    combatSafe = true,
    reloadToToggle = true,
    defaults = {
        buffPosition = { point = "TOPRIGHT", x = -224, y = -28 },
        showBuffs = true,
        showDebuffs = true,
        showTarget = true,
        targetDebuffs = "all",  -- on your target: "all" (everyone's, yours first) or "mine"
        targetBuffs = "all",
        showFocus = true,
        showBoss = true,
        buffSize = UI.Size("icon-lg"),
        buffsPerRow = 16,
        buffGrowth = "left",    -- "left" or "right" from the holder's edge
        debuffSize = UI.Size("icon-lg"),
    },
})

-- one target setting became two (debuffs, buffs)
M:Migrate("targetSplit", function(values)
    if values.targetAuras ~= nil then
        values.targetDebuffs = values.targetDebuffs or values.targetAuras
        values.targetBuffs = values.targetBuffs or values.targetAuras
    end
    values.targetAuras = nil
end)

-- The containers that hang off a unit frame: the anchor they follow (their
-- own name by default), where (point on the container, point on the frame,
-- x, y), and which setting. `half`: as wide as half the frame, so buffs (from
-- the left edge) and debuffs (from the right) each keep their side and wrap
-- upward on it. Every debuff has an ember edge (a typed one its type's
-- colour).
local ATTACHED = {
    player = { key = "showDebuffs", at = { "BOTTOMRIGHT", "TOPRIGHT", 0, S["space-4"] }, opts = {
        size = "icon-lg", anchor = "BOTTOMRIGHT", growth = { "LEFT", "UP" }, lineWidth = 300,
        groups = { { key = "debuffs", filter = { "HARMFUL" }, max = 16, dispel = true, harmfulEdge = true } },
    } },
    -- the target's buffs, yours first ("mine" in targetBuffs: only yours).
    -- Everyone's is one list: the game hides who cast another player's
    -- buffs, and those passed both "yours" and "not yours" (each showed
    -- twice; /suu probe partyauras).
    targetBuffs = { anchor = "target", key = "showTarget", half = true, at = { "BOTTOMLEFT", "TOPLEFT", 0, S["space-4"] }, opts = {
        size = "icon-md", anchor = "BOTTOMLEFT", growth = { "RIGHT", "UP" }, lineWidth = 150,
        groups = {
            { key = "myBuffs", filter = { "HELPFUL", "PLAYER" }, max = 6, drain = "fel" },
            { key = "theirBuffs", filter = { "HELPFUL" }, max = 8 },
        },
    } },
    -- its debuffs from the right edge, yours first ("mine" in targetDebuffs
    -- sets theirs to 0)
    targetDebuffs = { anchor = "target", key = "showTarget", half = true, at = { "BOTTOMRIGHT", "TOPRIGHT", 0, S["space-4"] }, opts = {
        size = "icon-md", anchor = "BOTTOMRIGHT", growth = { "LEFT", "UP" }, lineWidth = 150,
        groups = {
            { key = "mine", filter = { "HARMFUL", "PLAYER" }, max = 12, dispel = false, harmfulEdge = true },
            { key = "theirs", filter = { "HARMFUL", "!PLAYER" }, max = 8, dispel = true, harmfulEdge = true },
        },
    } },
    -- the focus as the target: its buffs (anyone's), your debuffs
    focusBuffs = { anchor = "focus", key = "showFocus", half = true, at = { "BOTTOMLEFT", "TOPLEFT", 0, S["space-4"] }, opts = {
        size = "icon-md", anchor = "BOTTOMLEFT", growth = { "RIGHT", "UP" }, lineWidth = 100,
        groups = { { key = "buffs", filter = { "HELPFUL" }, max = 4 } },
    } },
    focusDebuffs = { anchor = "focus", key = "showFocus", half = true, at = { "BOTTOMRIGHT", "TOPRIGHT", 0, S["space-4"] }, opts = {
        size = "icon-md", anchor = "BOTTOMRIGHT", growth = { "LEFT", "UP" }, lineWidth = 100,
        groups = { { key = "mine", filter = { "HARMFUL", "PLAYER" }, max = 8, harmfulEdge = true } },
    } },
}
for i = 1, 5 do
    ATTACHED["boss" .. i] = { key = "showBoss", at = { "RIGHT", "LEFT", -S["space-2"], 0 }, opts = {
        size = "icon-md", anchor = "RIGHT", growth = { "LEFT", "DOWN" },
        groups = { { key = "mine", filter = { "HARMFUL", "PLAYER" }, max = 4, harmfulEdge = true } },
    } }
end

-- A half-width container's line: half the frame, less half the gap between
-- the two sides.
local function halfWidth(frame)
    local w = frame and frame:GetWidth() or 0
    return math.max(UI.Size("icon-md"), math.floor((w - S["space-4"]) / 2))
end

-- The container is made once (the engine never frees one) and follows the
-- anchor: when another frame is published under the name (a plugin's own
-- target frame), it moves onto that frame.
function M:Attach(name, frame)
    local def = ATTACHED[name]
    if not def then return end
    local c = self.attached[name]
    if frame and not c then
        -- your debuffs are made at the setting's size (ApplyLayout resizes them after)
        if name == "player" then def.opts.size = self:Get("debuffSize") end
        if def.half then def.opts.lineWidth = halfWidth(frame) end
        c = UI.AuraContainer(frame, def.anchor or name, def.opts)
        self.attached[name] = c
    end
    if not c then return end
    if frame and self.attachedTo[name] ~= frame then
        self.attachedTo[name] = frame
        local at = def.at
        c.container:SetParent(frame)
        c.container:ClearAllPoints()
        c.container:SetPoint(at[1], frame, at[2], at[3], at[4])
        if def.half then
            c:SetLineWidth(halfWidth(frame))
            -- the frame's width is a setting: the sides follow it
            if not frame.suuHalfHooked then
                frame.suuHalfHooked = true
                frame:HookScript("OnSizeChanged", function(f)
                    for key, d in pairs(ATTACHED) do
                        if d.half and self.attachedTo[key] == f and self.attached[key] then
                            self.attached[key]:SetLineWidth(halfWidth(f))
                        end
                    end
                end)
            end
        end
    end
    c.container:SetShown(frame ~= nil and self:Get(def.key))
end

-- Every container that follows an anchor.
function M:AttachAnchor(anchor, frame)
    for name, def in pairs(ATTACHED) do
        if (def.anchor or name) == anchor then self:Attach(name, frame) end
    end
end

function M:ApplyOptions()
    for name, def in pairs(ATTACHED) do self:Attach(name, SuuUI.GetAnchor(def.anchor or name)) end
    -- the target's: everyone's, or only yours
    local debuffs, buffs = self.attached and self.attached.targetDebuffs, self.attached and self.attached.targetBuffs
    if debuffs then debuffs:SetGroupMax("theirs", self:Get("targetDebuffs") == "all" and 8 or 0) end
    if buffs then
        local allBuffs = self:Get("targetBuffs") == "all"
        buffs:SetGroupMax("myBuffs", allBuffs and 0 or 6)
        buffs:SetGroupMax("theirBuffs", allBuffs and 8 or 0)
    end
    self:UpdateOffline()
    if self.buffs then
        local pos = self:Get("buffPosition")
        local shown = self:Get("showBuffs") and not pos.hidden
        self.buffs.container:SetShown(shown)
        -- "playerBuffs": what sits under your buffs (the campfire strip) follows the holder
        SuuUI.PublishAnchor("playerBuffs", shown and self.buffHolder or nil)
    end
end

-- An offline player's auras are stale: the target's containers go see-through.
function M:UpdateOffline()
    if not self.attached then return end
    local online = true
    if UI.Flag(UnitExists("target")) and UI.Flag(UnitIsPlayer("target")) then
        local c = UnitIsConnected("target")
        if c ~= nil and not (issecretvalue and issecretvalue(c)) then online = c and true or false end
    end
    for _, key in ipairs({ "targetBuffs", "targetDebuffs" }) do
        if self.attached[key] then self.attached[key].container:SetAlpha(online and 1 or 0) end
    end
end

-- Sizes, row length and growth, out of combat: the engine's buttons refuse a
-- resize in combat. The holder (the edit-mode outline) is a row of the
-- setting's icons, two rows tall, and the icons start at the edge they grow from.
function M:ApplyLayout()
    self:RunOutOfCombat("layout", function()
        local sp = S["space-2"]
        if self.buffs then
            local size, n = self:Get("buffSize"), self:Get("buffsPerRow")
            local w = n * (size + sp)
            self.buffHolder:SetSize(w, 2 * (size + sp))
            self.buffs:SetGroupSize("buffs", size)
            if self.buffs.SetLineWidth then self.buffs:SetLineWidth(w) end
            local c = self.buffs.container
            c:ClearAllPoints()
            if self:Get("buffGrowth") == "right" then
                c:SetPoint("TOPLEFT", self.buffHolder, "TOPLEFT")
                self.buffs:SetFlow("TOPLEFT", { "RIGHT", "DOWN" })
            else
                c:SetPoint("TOPRIGHT", self.buffHolder, "TOPRIGHT")
                self.buffs:SetFlow("TOPRIGHT", { "LEFT", "DOWN" })
            end
        end
        if self.attached.player then self.attached.player:SetGroupSize("debuffs", self:Get("debuffSize")) end
        SuuUI.EditMode.Refresh()
    end)
end

local function buffsOff()
    if not M:Get("showBuffs") then return true, "Your buffs are off." end
end

local SECTION = {
    id = "auras", label = "Auras", category = "Frames", order = 12,
    groups = {
        { title = "On you", description = "In combat the game hides which spell an aura is from addons, so the game itself fills these in: SuuUI only styles them.", rows = {
            { key = "showBuffs", label = "Your buffs", control = "toggle",
              description = "Top right, left of the minimap. Right click cancels one." },
            { key = "buffSize", label = "Buff size", control = "slider", min = 20, max = 48, step = 1, unit = "px",
              live = false, combat = true, disabled = buffsOff },
            { key = "buffsPerRow", label = "Buffs per row", control = "slider", min = 4, max = 32, step = 1,
              live = false, combat = true, disabled = buffsOff, description = "Then the next row starts below." },
            { key = "buffGrowth", label = "Buffs grow", control = "segmented", combat = true, disabled = buffsOff,
              options = { { value = "left", label = "Left" }, { value = "right", label = "Right" } },
              description = "From the right edge of their place, or from its left edge." },
            { key = "showDebuffs", label = "Your debuffs", control = "toggle",
              description = "Above the player frame; a debuff with a type wears its dispel colour." },
            { key = "debuffSize", label = "Debuff size", control = "slider", min = 20, max = 48, step = 1, unit = "px",
              live = false, combat = true,
              disabled = function() if not M:Get("showDebuffs") then return true, "Your debuffs are off." end end },
        } },
        { title = "On other frames", description = "Your focus: its buffs and your debuffs; bosses: only your debuffs. None on a player who is offline.", rows = {
            { key = "showTarget", label = "On your target", control = "toggle",
              description = "Above the target frame: its buffs from the left edge, its debuffs from the right edge, yours first on each side. A side wraps upward when it fills half the frame." },
            { key = "targetDebuffs", label = "Target's debuffs", control = "segmented",
              options = { { value = "all", label = "Everyone's" }, { value = "mine", label = "Only yours" } },
              disabled = function() if not M:Get("showTarget") then return true, "Auras on your target are off." end end },
            { key = "targetBuffs", label = "Target's buffs", control = "segmented",
              options = { { value = "all", label = "Everyone's" }, { value = "mine", label = "Only yours" } },
              disabled = function() if not M:Get("showTarget") then return true, "Auras on your target are off." end end },
            { key = "showFocus", label = "On your focus", control = "toggle", description = "Above the focus frame: its buffs on the left, your debuffs on the right." },
            { key = "showBoss", label = "On bosses", control = "toggle", description = "Your debuffs, left of each boss bar." },
        } },
    },
}

function M:OnEnable()
    SuuUI.SuppressBlizzard("BuffFrame")
    SuuUI.SuppressBlizzard("DebuffFrame")

    if not self.attached then
        self.attached, self.attachedTo = {}, {}
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
    self:ApplyLayout()

    self:On("SUUUI_ANCHOR_CHANGED", function(_, name, frame)
        self:AttachAnchor(name, frame)
        if name == "target" then self:ApplyOptions() end
    end)
    for _, key in ipairs({ "buffSize", "buffsPerRow", "buffGrowth", "debuffSize" }) do
        self:Watch(key, function() self:ApplyLayout() end)
    end
    self:OnGameEvent("PLAYER_TARGET_CHANGED", function() self:UpdateOffline() end)
    self:OnUnitEvent("UNIT_CONNECTION", { "target" }, function() self:UpdateOffline() end)
    for _, key in ipairs({ "showBuffs", "showDebuffs", "showTarget", "targetDebuffs", "targetBuffs", "showFocus", "showBoss", "buffPosition" }) do
        self:Watch(key, function() self:ApplyOptions() end)
    end
end

function M:OnDisable()
    SuuUI.PublishAnchor("playerBuffs", nil)
    if self.buffs then self.buffs.container:Hide() end
    for _, c in pairs(self.attached or {}) do c.container:Hide() end
end
