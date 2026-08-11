local floor, ceil, max, abs = math.floor, math.ceil, math.max, math.abs
local type, pairs, pcall = type, pairs, pcall

-- The engine lays the UI out in units, not pixels: the drawing area is always 768 units
-- tall, so one unit spans physicalHeight / 768 pixels. At the default scale that is a
-- fraction (1.40625 at 1080p), which is why a 1-unit border straddles a pixel boundary
-- and renders grey instead of crisp.
--
-- Two things follow, and both are needed. The scale on our root frame makes one unit an
-- exact whole number of pixels, and Snap keeps every coordinate on that grid, because a
-- perfect grid is worth nothing if the layout hands SetPoint 13.7.
local BASE_UNITS = 768

-- The auto multiplier aims for roughly this much vertical space in units. At 1x a 4K
-- panel would give 2160 units and a window would occupy a quarter of the screen, so
-- high-DPI displays step up to an integer multiple instead: every unit is still a whole
-- number of pixels, so the UI stays exactly as crisp while being physically usable.
local TARGET_UNITS = 1000

local M = {
    enabled        = true,
    physicalHeight = BASE_UNITS,
    multiplier     = 1,
    scale          = 1,
    mult           = 1,
    grid           = 1,
}

local hosts    = {}    -- [frame] = true, frames whose scale this module drives
local userMult = nil   -- explicit override, nil means auto

local function readPhysicalHeight()
    if type(GetPhysicalScreenSize) == "function" then
        local ok, _, h = pcall(GetPhysicalScreenSize)
        if ok and type(h) == "number" and h > 0 then return h end
    end
    -- No physical size available: fall back to unit space, which yields a 1:1 grid and
    -- makes every operation here a no-op rather than a wrong guess.
    if type(GetScreenHeight) == "function" then
        local ok, h = pcall(GetScreenHeight)
        if ok and type(h) == "number" and h > 0 then return h end
    end
    return BASE_UNITS
end

local function autoMultiplier(physH)
    return max(1, floor(physH / TARGET_UNITS + 0.5))
end

-- Drives a frame's effective scale to exactly `scale`. SetIgnoreParentScale detaches it
-- from the player's UI Scale slider outright; where the client lacks it, the parent
-- chain is divided back out so both paths land on the same effective scale.
local function applyScale(f, scale)
    if f.SetIgnoreParentScale then pcall(f.SetIgnoreParentScale, f, true) end
    f:SetScale(scale)
    local eff = f.GetEffectiveScale and f:GetEffectiveScale()
    if type(eff) == "number" and eff > 0 and abs(eff - scale) > 1e-6 then
        f:SetScale(scale * scale / eff)
    end
end

-- Effective scale the grid is measured against when this module is not driving it.
local function referenceScale()
    for f in pairs(hosts) do
        local eff = f.GetEffectiveScale and f:GetEffectiveScale()
        if type(eff) == "number" and eff > 0 then return eff end
    end
    if UIParent and UIParent.GetEffectiveScale then
        local eff = UIParent:GetEffectiveScale()
        if type(eff) == "number" and eff > 0 then return eff end
    end
    return 1
end

-- How far off a grid multiple a value may sit and still be treated as being ON it.
--
-- Geometry does not survive a round trip through the client unscathed: the root's scale is
-- physH-derived and rarely a binary-exact fraction (768/1440 = 8/15), so the client stores
-- a size in screen space and hands it back divided by that scale. SetSize(w, 22) reads back
-- as 21.99996948242 — one or two ULPs short of 22.
--
-- Floor and Ceil are the two operations that turn that noise into a WHOLE UNIT of error:
-- Floor(21.99996948242) is 21, so a stretched child comes out a pixel short of the box it
-- was told to fill, and the missing row shows as a gap against whatever sits against that
-- edge. Snap is immune, since rounding absorbs the noise.
--
-- The tolerance is orders of magnitude above the observed noise (3e-5) and far below any
-- offset a caller could mean, so it recovers the intended integer without ever masking a
-- real fraction.
local GRID_EPS = 0.01

--- Snaps a value to the pixel grid. Everything the layout engine hands SetPoint,
--- SetSize or SetWidth passes through here.
-- @param v number
-- @return number
function M.Snap(v)
    if not v or v == 0 then return 0 end
    local g = M.grid
    if g == 1 then return floor(v + 0.5) end
    return g * floor(v / g + 0.5)
end

--- Snaps down. Use for a size that must not overflow the space it was given.
-- Tolerates GRID_EPS above the multiple, so a value the client handed back a hair short of
-- a whole unit is not truncated by a full one.
-- @param v number
-- @return number
function M.Floor(v)
    if not v or v == 0 then return 0 end
    local g = M.grid
    if g == 1 then return floor(v + GRID_EPS) end
    return g * floor(v / g + GRID_EPS)
end

--- Snaps up. Use for a size that must not clip its content.
-- Tolerates GRID_EPS below the multiple, so a value a hair OVER a whole unit does not gain
-- a full one — the same round-trip noise in the other direction.
-- @param v number
-- @return number
function M.Ceil(v)
    if not v or v == 0 then return 0 end
    local g = M.grid
    if g == 1 then return ceil(v - GRID_EPS) end
    return g * ceil(v / g - GRID_EPS)
end

--- Cursor position expressed in a frame's own coordinate space.
--
-- GetCursorPosition reports raw screen coordinates, which have to be divided by the
-- effective scale of the frame the result is compared against. Dividing by UIParent's
-- instead happens to work only while nothing in the chain carries a scale — and the
-- pixel grid puts one on the root, so a frame under it would read the cursor off by the
-- ratio between the two. Every hit test and drag goes through here.
-- @param frame frame  The frame whose GetLeft/GetBottom the result is compared against
-- @return number, number  x, y
function M.CursorIn(frame)
    local cx, cy = GetCursorPosition()
    local scale = frame and frame.GetEffectiveScale and frame:GetEffectiveScale()
    if type(scale) ~= "number" or scale <= 0 then scale = 1 end
    return (cx or 0) / scale, (cy or 0) / scale
end

--- Snaps a line thickness without ever rounding it out of existence.
-- A border that snaps to zero is worse than a blurry one, so the grid quantum is the
-- floor: the thinnest line the display can draw crisply.
-- @param v number
-- @return number
function M.Line(v)
    return max(M.grid, M.Snap(v or 0))
end

--- Recomputes the grid from the current resolution and applies it to attached frames.
-- Emits SUUUI_PIXEL_GRID_CHANGED when the grid actually moved, so nothing restyles for
-- a resolution event that changed no geometry.
function M:Refresh()
    local physH = readPhysicalHeight()
    local beforeGrid, beforeScale = self.grid, self.scale

    self.physicalHeight = physH
    self.multiplier     = userMult or autoMultiplier(physH)

    if self.enabled then
        self.scale = self.multiplier * BASE_UNITS / physH
        for f in pairs(hosts) do applyScale(f, self.scale) end
        -- One unit is now exactly `multiplier` pixels, so whole units are pixel-aligned
        -- and the grid is 1. Snapping to fractions of a unit would also be crisp but
        -- buys nothing and would leave every measurement non-integral.
        self.mult = 1 / self.multiplier
        self.grid = 1
    else
        local eff = referenceScale()
        self.scale = eff
        self.mult  = BASE_UNITS / (physH * eff)
        -- Off-grid by definition, so snap to real pixels instead of whole units.
        self.grid  = self.mult
    end

    if abs(beforeGrid - self.grid) > 1e-9 or abs(beforeScale - self.scale) > 1e-9 then
        if SuuUI.Events then SuuUI.Events:Emit("SUUUI_PIXEL_GRID_CHANGED", self.grid) end
    end
end

--- Registers a frame whose scale this module drives. UIRoot attaches the single root.
-- @param frame frame
function M:Attach(frame)
    if not frame then return end
    hosts[frame] = true
    if self.enabled then applyScale(frame, self.scale) end
end

--- Stops driving a frame's scale and restores it.
-- @param frame frame
function M:Detach(frame)
    if not frame then return end
    hosts[frame] = nil
    if frame.SetIgnoreParentScale then pcall(frame.SetIgnoreParentScale, frame, false) end
    frame:SetScale(1)
end

--- Turns pixel scaling on or off. Snapping stays active either way: with scaling off the
--- grid becomes the real pixel size in units, which is the best available alignment.
-- @param on bool
function M:SetEnabled(on)
    on = on and true or false
    if self.enabled == on then return end
    self.enabled = on
    if not on then
        for f in pairs(hosts) do
            if f.SetIgnoreParentScale then pcall(f.SetIgnoreParentScale, f, false) end
            f:SetScale(1)
        end
    end
    self:Refresh()
end

--- Overrides the integer scale multiplier. Pass nil to return to automatic selection.
-- @param n number|nil  Whole number >= 1
function M:SetMultiplier(n)
    if n == nil then
        userMult = nil
    else
        assert(type(n) == "number" and n >= 1, "SuuUI Pixel: multiplier must be >= 1")
        -- A fractional multiplier would put units back between pixels, which is the
        -- exact problem this module exists to remove.
        userMult = floor(n + 0.5)
    end
    self:Refresh()
end

--- Returns the multiplier chosen automatically for a given physical height.
-- @param physH number
-- @return number
function M:AutoMultiplier(physH)
    return autoMultiplier(physH or self.physicalHeight)
end

--- Computes the grid and starts tracking resolution and scale changes.
function M:Init()
    self:Refresh()

    if self._watcher then return end
    self._watcher = CreateFrame("Frame", "SuuUI_pixel_watcher")
    self._watcher:RegisterEvent("DISPLAY_SIZE_CHANGED")
    self._watcher:RegisterEvent("UI_SCALE_CHANGED")
    self._watcher:RegisterEvent("CVAR_UPDATE")
    self._watcher:SetScript("OnEvent", function() M:Refresh() end)
end

SuuUI.Pixel = M
