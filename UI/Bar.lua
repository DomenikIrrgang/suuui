-- UI/Bar.lua
-- The status bar unit frames, casts and progress are built on. Values go
-- straight to the engine, so secret health and power display fine.
--
--   local bar = UI.StatusBar(parent, { width = 300, height = 32,
--       fill = "unit-fill", deep = "unit-fill-deep",   -- a gradient deep -> fill, left to right
--       track = "surface-sunk", border = "gilt-hairline",
--       ghost = true })                                  -- the damage ghost
--   bar:SetMinMax(0, max); bar:SetValue(v); bar:SetFill("unit-fill-low", "unit-fill-low-deep")
--
-- The ghost is a second bar behind the fill. It follows the value after a
-- 150ms hold and drains with the engine's own interpolation, so it works on
-- secret values too, where no Lua code may do the maths.

local _, ns = ...

local UI = ns.UI

local WHITE = "Interface\\Buttons\\WHITE8X8"
local HOLD = 0.15
local INTERPOLATE = Enum.StatusBarInterpolation and Enum.StatusBarInterpolation.ExponentialEaseOut

local Bar = {}

function Bar:SetFill(fill, deep)
    local tex = self.bar:GetStatusBarTexture()
    local r1, g1, b1, a1 = UI.RGBA(deep or fill)
    local r2, g2, b2, a2 = UI.RGBA(fill)
    tex:SetGradient("HORIZONTAL", CreateColor(r1, g1, b1, a1), CreateColor(r2, g2, b2, a2))
end

function Bar:SetMinMax(min, max)
    self.bar:SetMinMaxValues(min, max)
    if self.ghost then self.ghost:SetMinMaxValues(min, max) end
end

function Bar:SetValue(v)
    self.bar:SetValue(v)
    local ghost = self.ghost
    if not ghost then return end
    self.ghostTarget = v
    if not self.ghostTimer then
        self.ghostTimer = C_Timer.NewTimer(HOLD, function()
            self.ghostTimer = nil
            ghost:SetValue(self.ghostTarget, INTERPOLATE)
        end)
    end
end

-- Sets the value with no ghost, e.g. when the bar switches unit.
function Bar:SetValueNow(v)
    self.bar:SetValue(v)
    if self.ghost then
        if self.ghostTimer then self.ghostTimer:Cancel() self.ghostTimer = nil end
        self.ghost:SetValue(v)
    end
end

local function statusBar(parent, color)
    local b = CreateFrame("StatusBar", nil, parent)
    b:SetStatusBarTexture(WHITE)
    b:GetStatusBarTexture():SetSnapToPixelGrid(false)
    b:SetMinMaxValues(0, 1)
    b:SetValue(0)
    if color then b:SetStatusBarColor(UI.RGBA(color)) end
    return b
end

function UI.StatusBar(parent, opts)
    opts = opts or {}
    local f = CreateFrame("Frame", nil, parent)
    Mixin(f, Bar)
    f:SetSize(UI.Size(opts.width or "bar-lg"), UI.Size(opts.height or "unit-lg"))
    f.track = UI.Fill(f, opts.track or "surface-sunk")
    f.track:SetAllPoints()
    if opts.border ~= false then f.border = UI.Border(f, opts.border or "gilt-hairline", { layer = "OVERLAY" }) end
    local inset = opts.border ~= false and 1 or 0
    if opts.ghost then
        f.ghost = statusBar(f, "ghost")
        f.ghost:SetPoint("TOPLEFT", inset, -inset)
        f.ghost:SetPoint("BOTTOMRIGHT", -inset, inset)
    end
    f.bar = statusBar(f)
    f.bar:SetPoint("TOPLEFT", inset, -inset)
    f.bar:SetPoint("BOTTOMRIGHT", -inset, inset)
    f.bar:SetFrameLevel(f:GetFrameLevel() + 2)
    if f.ghost then f.ghost:SetFrameLevel(f:GetFrameLevel() + 1) end
    f:SetFill(opts.fill or "unit-fill", opts.deep or (opts.fill == nil and "unit-fill-deep") or nil)
    return f
end
