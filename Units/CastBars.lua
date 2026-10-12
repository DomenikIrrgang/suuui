-- Units/CastBars.lua
-- Cast bars (step 1.3a): your own cast, centred between the player and target
-- frames, and the casts of your target, focus and bosses under their frames,
-- each interruptible one carrying your interrupt's state. A built-in module
-- written against the public API only; it finds the unit frames through
-- their published anchors.
--
-- Placement (2560x1440 reference): your cast bar is 340px wide, centred on
-- the screen, its top 316px above the bottom edge, under the Cooldown Manager
-- and over the swing timer. The others hang space-1 under their unit's bar,
-- at its width.

local UI, T = SuuUI.UI, SuuUI.Tokens
local S = T.space

local M = SuuUI.RegisterModule({
    id = "castbars",
    name = "Cast bars",
    description = "Your cast bar, and the casts of your target, focus and bosses with your interrupt's state.",
    api = "0.6",
    reloadToToggle = true,
    defaults = {
        playerPosition = { point = "BOTTOM", x = 0, y = 292 },
        showPlayer = true,
        showTarget = true,
        showFocus = true,
        showBoss = true,
        showIcon = true,
        showKick = true,
    },
})

-- The unit frames a cast bar hangs under, and the setting that turns it off.
local ATTACH = {
    target = "showTarget", focus = "showFocus",
    boss1 = "showBoss", boss2 = "showBoss", boss3 = "showBoss", boss4 = "showBoss", boss5 = "showBoss",
}
-- Each attached bar is as wide as its unit's bar (the size tokens, never a
-- size read back from the frame).
local WIDTH = { target = "bar-lg" }

function M:Attach(name, frame)
    local key = ATTACH[name]
    if not key then return end
    local bar = self.attached[name]
    if not frame then
        if bar then bar:Deactivate() end
        return
    end
    if not bar then
        bar = UI.CastBar(frame, name, { size = "sm", width = WIDTH[name] or "bar-md", name = "SuuUI" .. name .. "CastBar" })
        self.attached[name] = bar
    end
    bar:SetParent(frame)
    bar:ClearAllPoints()
    bar:SetPoint("TOPLEFT", frame, "BOTTOMLEFT", 0, -S["space-1"])
    bar:SetIconShown(self:Get("showIcon"))
    bar:SetKickShown(self:Get("showKick"))
    if self:Get(key) then bar:Activate() else bar:Deactivate() end
end

function M:ApplyOptions()
    for name in pairs(ATTACH) do self:Attach(name, SuuUI.GetAnchor(name)) end
    self.player:SetIconShown(self:Get("showIcon"))
    -- Your cast bar runs unless it is turned off or hidden in edit mode.
    if self:Get("showPlayer") and not self:Get("playerPosition").hidden then
        -- (also when turned on mid-session: Blizzard's must not show beside it)
        SuuUI.SuppressBlizzard("PlayerCastingBarFrame")
        SuuUI.SuppressBlizzard("PetCastingBarFrame")
        self.player:Activate()
    else
        self.player:Deactivate()
    end
end

local SECTION = {
    id = "castbars", label = "Cast bars", category = "Frames", order = 20,
    groups = {
        { title = "Whose casts", rows = {
            { key = "showPlayer", label = "Your cast bar", control = "toggle",
              description = "Centred between the player and target frames. Blizzard's own comes back after a reload." },
            { key = "showTarget", label = "Target", control = "toggle", description = "Under the target frame." },
            { key = "showFocus", label = "Focus", control = "toggle", description = "Under the focus frame, so you can stop a second caster." },
            { key = "showBoss", label = "Bosses", control = "toggle", description = "Under each boss frame." },
        } },
        { title = "On every cast bar", rows = {
            { key = "showIcon", label = "Spell icon", control = "toggle", description = "The spell's icon at the left end of the bar." },
            { key = "showKick", label = "Your interrupt", control = "toggle",
              description = "On interruptible casts: a diamond in arcane when your interrupt is ready, its seconds when it isn't. Shown between pulls and in encounters alike." },
        } },
    },
}

function M:OnEnable()
    if self:Get("showPlayer") then
        SuuUI.SuppressBlizzard("PlayerCastingBarFrame")
        SuuUI.SuppressBlizzard("PetCastingBarFrame")
    end
    if not self.player then
        self.player = UI.CastBar(SuuUI.Root, "player", { size = "md", width = 340, name = "SuuUIPlayerCastBar" })
        self.player.suuManagedShow = true -- shown only while you cast
        self.attached = {}
    end
    self:RegisterMover(self.player, { key = "playerPosition", label = "Your cast bar",
        enabled = function() return self:Get("showPlayer") end })
    self:Watch("showPlayer", SuuUI.EditMode.Refresh)
    self:RegisterSettings(SECTION)
    self:ApplyOptions()

    self:On("SUUUI_ANCHOR_CHANGED", function(_, name, frame) self:Attach(name, frame) end)
    for _, key in ipairs({ "showPlayer", "showTarget", "showFocus", "showBoss", "showIcon", "showKick", "playerPosition" }) do
        self:Watch(key, function() self:ApplyOptions() end)
    end
end

function M:OnDisable()
    -- Only reached when the module errors: the module toggles on reload.
    if self.player then
        self.player:Deactivate()
        for _, bar in pairs(self.attached) do bar:Deactivate() end
    end
end
