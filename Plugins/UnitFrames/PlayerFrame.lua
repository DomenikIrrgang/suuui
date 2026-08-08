-- UnitFrames plugin: replaces Blizzard's unit frames with a modern, minimal design.
-- This file implements the player frame; other units will follow.
local C = SuuUI.Components
local S = SuuUI.UISignals
local T = SuuUI.Theme

---------------------------------------------------------------------------
-- Power type colour map (standard WoW colours)
---------------------------------------------------------------------------
local POWER_COLORS = {
    [0] = {0.00, 0.44, 0.87, 1},  -- Mana (blue)
    [1] = {0.77, 0.12, 0.23, 1},  -- Rage (red)
    [2] = {1.00, 0.50, 0.25, 1},  -- Focus (orange)
    [3] = {1.00, 0.96, 0.41, 1},  -- Energy (yellow)
    [4] = {0.00, 0.44, 0.87, 1},  -- Combo Points (blue, fallback)
    [5] = {0.50, 0.50, 0.50, 1},  -- Runes (grey)
    [6] = {0.00, 0.82, 1.00, 1},  -- Runic Power (cyan)
}

-- Health bar colour: a modern green
local HEALTH_COLOR = {0.22, 0.78, 0.32, 1}

---------------------------------------------------------------------------
-- Player frame widget
---------------------------------------------------------------------------
local PlayerFrame = {}

function PlayerFrame:Create(parent)
    local self = setmetatable({}, { __index = PlayerFrame })

    local pad = T:GetToken("spaceXs") or 4
    local gap = 2  -- tight gap between health and resource bars

    -- Background frame for the whole unit frame
    self._bg = C.Frame({
        variant = "bgAlt",
        border  = true,
    }, parent)

    -- Attach the container inside the background frame
    self._container = SuuUI.Layout:CreateContainer({
        host    = self._bg:GetFrame(),
        layout  = "flow",
        dir     = "vertical",
        gap     = gap,
        fill    = true,
        padding = { top = pad, right = pad, bottom = pad, left = pad },
    })

    -- Info row: name on left, level on right
    self._infoRow = SuuUI.Layout:CreateContainer({
        parent  = self._bg:GetFrame(),
        layout  = "flow",
        dir     = "horizontal",
        gap     = T:GetToken("spaceXs") or 4,
        align   = "center",
    })

    self._nameText = C.Text({
        text  = "",
        size  = "sm",
        color = "text",
    }, self._infoRow:GetFrame())

    self._levelText = C.Text({
        text  = "",
        size  = "sm",
        color = "textMuted",
    }, self._infoRow:GetFrame())

    self._infoRow:Add(self._nameText, { width = "fill" })
    self._infoRow:Add(self._levelText)

    -- Health bar
    self._healthBar = C.StatusBar({
        fillColor = HEALTH_COLOR,
        bgColor   = "colorBg",
        border    = false,
    }, self._bg:GetFrame())

    -- Resource bar
    self._resourceBar = C.StatusBar({
        fillColor = POWER_COLORS[0],  -- default to mana
        bgColor   = "colorBg",
        border    = false,
    }, self._bg:GetFrame())

    -- Assemble layout
    self._container:Add(self._infoRow,     { width = "fill", height = 14 })
    self._container:Add(self._healthBar,   { width = "fill", height = 16 })
    self._container:Add(self._resourceBar, { width = "fill", height = 10 })

    -- WoW event frame for data updates
    self._events = CreateFrame("Frame")
    self._events:RegisterEvent("UNIT_HEALTH")
    self._events:RegisterEvent("UNIT_MAXHEALTH")
    self._events:RegisterEvent("UNIT_POWER_UPDATE")
    self._events:RegisterEvent("UNIT_MAXPOWER")
    self._events:RegisterEvent("UNIT_DISPLAYPOWER")
    self._events:RegisterEvent("PLAYER_ENTERING_WORLD")
    self._events:SetScript("OnEvent", function(_, event, unit, ...)
        if event == "PLAYER_ENTERING_WORLD" then
            self:UpdateAll()
        elseif unit == "player" or event == "UNIT_DISPLAYPOWER" then
            if event == "UNIT_HEALTH" or event == "UNIT_MAXHEALTH" then
                self:UpdateHealth()
            elseif event == "UNIT_POWER_UPDATE" or event == "UNIT_MAXPOWER" or event == "UNIT_DISPLAYPOWER" then
                self:UpdatePower()
            end
        end
    end)

    self:UpdateAll()
    return self
end

function PlayerFrame:UpdateAll()
    self:UpdateInfo()
    self:UpdateHealth()
    self:UpdatePower()
end

function PlayerFrame:UpdateInfo()
    local name = UnitName("player") or ""
    local level = UnitLevel("player") or 0
    self._nameText:SetText(name)
    self._levelText:SetText(tostring(level))
end

function PlayerFrame:UpdateHealth()
    local cur = UnitHealth("player") or 0
    local mx  = UnitHealthMax("player") or 1
    self._healthBar:SetMax(mx)
    self._healthBar:SetValue(cur)
end

function PlayerFrame:UpdatePower()
    local powerType = UnitPowerType("player") or 0
    local cur = UnitPower("player") or 0
    local mx  = UnitPowerMax("player") or 1
    local color = POWER_COLORS[powerType] or POWER_COLORS[0]
    self._resourceBar:SetFillColor(color)
    self._resourceBar:SetMax(mx)
    self._resourceBar:SetValue(cur)
end

function PlayerFrame:GetFrame()
    return self._bg:GetFrame()
end

function PlayerFrame:GetContainer()
    return self._container
end

function PlayerFrame:Destroy()
    self._events:UnregisterAllEvents()
    self._events:Hide()
    self._nameText:Destroy()
    self._levelText:Destroy()
    self._healthBar:Destroy()
    self._resourceBar:Destroy()
    self._infoRow:Destroy()
    self._container:Destroy()
    self._bg:Destroy()
end

---------------------------------------------------------------------------
-- Blizzard frames to hide/restore
---------------------------------------------------------------------------
local BLIZZARD_PLAYER_FRAMES = {
    "PlayerFrame",
}

local function hideBlizzardPlayerFrame()
    for _, name in ipairs(BLIZZARD_PLAYER_FRAMES) do
        local frame = _G[name]
        if frame then
            frame:UnregisterAllEvents()
            frame:Hide()
        end
    end
end

---------------------------------------------------------------------------
-- Plugin registration
---------------------------------------------------------------------------
local plugin = SuuUI:CreatePlugin({
    id      = "unit_frames",
    name    = "Unit Frames",
    version = "0.1",

    onInit = function(p)
        SuuUI.Settings:Register("unit_frames", {
            { key = "enabled",        label = "Enable Unit Frames",   type = "toggle", default = true },
            { key = "",               label = "Player Frame",         type = "section" },
            { key = "player_enabled", label = "Enable Player Frame",  type = "toggle", default = true },
            { key = "player_position", type = "position", default = { point = "BOTTOMLEFT", relPoint = "BOTTOMLEFT", x = 20, y = 60 } },
        })

        -- Guard settings that require a reload
        SuuUI.ReloadGuard:Register("unit_frames", "enabled", {
            title   = "Reload Required",
            message = "Enabling or disabling Unit Frames requires a UI reload. Reload now?",
        })
        SuuUI.ReloadGuard:Register("unit_frames", "player_enabled", {
            title   = "Reload Required",
            message = "Enabling or disabling the Player Frame requires a UI reload. Reload now?",
        })
    end,

    onEnable = function(p)
        -- Hide Blizzard player frame
        if SuuUI.Settings:Get("unit_frames", "player_enabled") then
            hideBlizzardPlayerFrame()

            -- Create our player frame
            local root = SuuUI.UIRoot:GetRootContainer()
            p._playerFrame = PlayerFrame:Create(root:GetFrame())

            -- Size the frame explicitly (MoveableFrame handles positioning)
            local frame = p._playerFrame:GetFrame()
            frame:SetSize(180, 50)

            -- Make it moveable — position stored in plugin settings
            SuuUI.MoveableFrame:Apply(frame, {
                pluginId    = "unit_frames",
                key         = "player_position",
                displayName = "Player",
                defaults    = { point = "BOTTOMLEFT", relPoint = "BOTTOMLEFT", x = 20, y = 60 },
            })
        end
    end,

    onDisable = function(p)
        -- Destroy our player frame (cleanup before reload or if called programmatically)
        if p._playerFrame then
            SuuUI.MoveableFrame:Remove(p._playerFrame:GetFrame())
            p._playerFrame:Destroy()
            p._playerFrame = nil
        end
        -- Blizzard frames are restored by the reload — no manual restore needed
    end,
})
