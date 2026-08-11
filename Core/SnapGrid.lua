-- SnapGrid: visible grid overlay and snap logic for edit mode.
-- Draws faint lines on the UI root at a configurable grid step, and provides snap
-- functions for MoveableFrame to round positions onto the grid. Also computes smart
-- guide lines showing alignment with other registered moveable frames.
local pairs = pairs
local floor, abs = math.floor, math.abs
local tinsert = table.insert

local M = {}

-- Grid line pools (reused textures)
local hLines = {}
local vLines = {}
-- Smart guide line pool
local guideHLines = {}
local guideVLines = {}

local gridFrame  -- the invisible frame that owns the grid textures
local guidesFrame -- the invisible frame that owns the guide textures
local isShowing = false

-- How close to another element's edge/center to trigger a guide (in units)
local GUIDE_THRESHOLD = 2

---------------------------------------------------------------------------
-- Snap
---------------------------------------------------------------------------

-- How close (in units) a position must be to a guide line to snap to it.
local GUIDE_SNAP_THRESHOLD = 6

-- Which of our edges pairs with which of theirs. Index 1 = the low edge (left / bottom),
-- 2 = the high edge (right / top), 3 = centre, so one table serves both axes.
--
-- Enumerated rather than looped so the ADJACENT pairings are explicit: our bottom against
-- their top is what stacking two bars means, and it has to be a candidate alongside
-- bottom-to-bottom.
--
-- No pairing carries a seam correction, and that is deliberate. Measured in game at
-- multiplier 1, where one unit IS one physical pixel: a flush snap leaves a one-pixel
-- seam, and nudging by one pixel produces a one-pixel OVERLAP instead. Those are adjacent
-- integer offsets, so no placement lands the two fills reading as touching -- the boundary
-- row is blended by the rasteriser, not misplaced. Flush is the correct geometry, and both
-- directions were tried in game before settling on it.
local EDGE_PAIRINGS = {
    { 1, 1 },   -- low    to low     (left/left, bottom/bottom)
    { 2, 2 },   -- high   to high    (right/right, top/top)
    { 3, 3 },   -- centre to centre
    { 1, 3 },   -- low    to centre
    { 2, 3 },   -- high   to centre
    { 3, 1 },   -- centre to low
    { 3, 2 },   -- centre to high
    { 1, 2 },   -- our low edge meets their high edge: stacking, we sit after them
    { 2, 1 },   -- our high edge meets their low edge: stacking, we sit before them
}

--- Snap x, y based on the current snap mode setting.
-- "grid" rounds to grid multiples. "guides" snaps to other elements' edges/centers.
-- "none" returns input unchanged.
-- @param x number
-- @param y number
-- @param frame table  The frame being snapped (needed for guide mode to find others)
-- @return number, number
function M:Snap(x, y, frame)
    local mode = SuuUI.Settings:Get("_layout", "snap_mode") or "none"
    if mode == "grid" then
        local step = SuuUI.Settings:Get("_layout", "grid_size") or 16
        if step < 1 then return x, y end
        return floor(x / step + 0.5) * step, floor(y / step + 0.5) * step
    elseif mode == "guides" and frame then
        return M:_snapToGuides(x, y, frame)
    end
    return x, y
end

--- Snap to the nearest guide line (other element's edge/center) if within threshold.
-- Only snaps if within GUIDE_SNAP_THRESHOLD of a guide position.
-- @param x number  The x offset (anchor-relative, not screen-space)
-- @param y number  The y offset
-- @param frame table  The frame being dragged
-- @return number, number
function M:_snapToGuides(x, y, frame)
    -- Guide snap works on the frame's screen position. We receive anchor offsets
    -- (TOPLEFT-relative after a drag) and shift them by the delta needed to put one of
    -- our edges onto another element's edge; a pure delta is correct regardless of the
    -- coreInset compensation applied around this call.
    local fl, fr, ft, fb, fcx, fcy = M._edgesOf(frame)
    if not fl then return x, y end

    local bestDx, snapX = GUIDE_SNAP_THRESHOLD + 1, nil
    local bestDy, snapY = GUIDE_SNAP_THRESHOLD + 1, nil

    -- Low edge first, so index 1/2/3 means the same thing on both axes: for y the low
    -- edge is the BOTTOM, because WoW's y counts upward.
    local oursX,  oursY  = { fl, fr, fcx }, { fb, ft, fcy }
    local theirX, theirY = {}, {}

    local all = SuuUI.ToggleUI:GetAll()
    for i = 1, #all do
        local other = all[i]
        if other ~= frame and other:IsShown() then
            local ol, or_, ot, ob, ocx, ocy = M._edgesOf(other)
            if ol then
                theirX[1], theirX[2], theirX[3] = ol, or_, ocx
                theirY[1], theirY[2], theirY[3] = ob, ot, ocy

                for p = 1, #EDGE_PAIRINGS do
                    local pair = EDGE_PAIRINGS[p]
                    local mine, theirs = pair[1], pair[2]

                    local ours, ref = oursX[mine], theirX[theirs]
                    local d = abs(ours - ref)
                    if d < bestDx then
                        bestDx = d
                        snapX = x + (ref - ours)
                    end

                    ours, ref = oursY[mine], theirY[theirs]
                    d = abs(ours - ref)
                    if d < bestDy then
                        bestDy = d
                        snapY = y + (ref - ours)
                    end
                end
            end
        end
    end

    -- Quantise onto the pixel grid before returning.
    --
    -- The delta that lands our edge on a guide is generally fractional, and the value we
    -- return is handed to AnchorLayout, which snaps every coordinate it passes to
    -- SetPoint. Returning a fractional offset therefore gets rounded downstream by up to
    -- half a grid step AFTER we aimed it at the line — which is exactly the one-pixel gap
    -- between a frame and the guide it was supposed to sit flush against.
    --
    -- Snapping here instead makes the value we store already grid-aligned, so the layout
    -- engine's own snap is idempotent and cannot move the frame off the guide.
    if snapX then snapX = SuuUI.Pixel.Snap(snapX) end
    if snapY then snapY = SuuUI.Pixel.Snap(snapY) end

    return snapX or x, snapY or y
end

---------------------------------------------------------------------------
-- Smart Guides
---------------------------------------------------------------------------

-- Scratch arrays reused across calls. FindGuides runs repeatedly while a drag is in
-- flight, so a fresh result table per call would allocate on every tick.
local guideScratch = { h = {}, v = {} }

local function truncate(t)
    for i = #t, 1, -1 do t[i] = nil end
end

--- A frame's edges and centres, in WoW screen space (y counts upward).
-- Shared by the guide finder and the snap so a drawn line and a magnet can never
-- disagree about where an element's edge is.
-- @return number,number,number,number,number,number  left, right, top, bottom, cx, cy
local function edgesOf(f)
    local l, t = f:GetLeft(), f:GetTop()
    if not (l and t) then return nil end
    local w, h = f:GetWidth() or 0, f:GetHeight() or 0
    local r, b = l + w, t - h
    return l, r, t, b, (l + r) * 0.5, (t + b) * 0.5
end

-- Published on the module because the snap is defined earlier in the file than this
-- helper. Both paths MUST measure edges the same way or a guide line and its magnet
-- drift apart, which is the class of bug this sharing exists to prevent.
M._edgesOf = edgesOf

-- Whether any of our three candidate edges is close enough to `ref` to snap to it.
local function nearAny(a, b, c, ref)
    return abs(a - ref) <= GUIDE_SNAP_THRESHOLD
        or abs(b - ref) <= GUIDE_SNAP_THRESHOLD
        or abs(c - ref) <= GUIDE_SNAP_THRESHOLD
end

--- Find the guide positions the dragged frame is currently close enough to snap to.
-- Returns { h = {y1, ...}, v = {x1, ...} } in WoW coordinate space.
--
-- Deliberately NEAR-only rather than every edge of every frame: a drawn guide is a
-- promise that releasing here lands on that line, so drawing lines that are out of
-- magnet range is what made the guides look like they "made no sense". The same
-- GUIDE_SNAP_THRESHOLD gates both, so a visible line always has a magnet behind it.
--
-- The returned table is reused between calls — read it, do not keep it.
-- @param frame table  The frame being dragged (excluded from results)
-- @return table
function M:FindGuides(frame)
    local out = guideScratch
    truncate(out.h)
    truncate(out.v)
    if not frame then return out end

    local fl, fr, ft, fb, fcx, fcy = edgesOf(frame)
    if not fl then return out end

    local all = SuuUI.ToggleUI:GetAll()
    for i = 1, #all do
        local other = all[i]
        if other ~= frame and other:IsShown() then
            local ol, or_, ot, ob, ocx, ocy = edgesOf(other)
            if ol then
                -- Vertical guides: left, centre, right of the other frame
                if nearAny(fl, fr, fcx, ol)  then out.v[#out.v + 1] = ol  end
                if nearAny(fl, fr, fcx, ocx) then out.v[#out.v + 1] = ocx end
                if nearAny(fl, fr, fcx, or_) then out.v[#out.v + 1] = or_ end

                -- Horizontal guides: top, centre, bottom of the other frame
                if nearAny(ft, fb, fcy, ot)  then out.h[#out.h + 1] = ot  end
                if nearAny(ft, fb, fcy, ocy) then out.h[#out.h + 1] = ocy end
                if nearAny(ft, fb, fcy, ob)  then out.h[#out.h + 1] = ob  end
            end
        end
    end

    return out
end

---------------------------------------------------------------------------
-- Grid Drawing
---------------------------------------------------------------------------

local function ensureFrames()
    if gridFrame then return end

    local root = SuuUI.UIRoot and SuuUI.UIRoot:GetRoot()
    if not root then return end

    gridFrame = CreateFrame("Frame", nil, root)
    gridFrame:SetAllPoints(root)
    gridFrame:Hide()

    guidesFrame = CreateFrame("Frame", nil, root)
    guidesFrame:SetAllPoints(root)
    guidesFrame:Hide()

    -- Both frames sit on the normal layer but above plugin content by level
    if SuuUI.UIRoot.RaiseAbove then
        SuuUI.UIRoot:RaiseAbove(gridFrame, root, 2)
        SuuUI.UIRoot:RaiseAbove(guidesFrame, root, 3)
    end
end

local function getGridColor()
    local c = SuuUI.Theme:GetToken("colorGrid")
    if type(c) == "table" then return c[1], c[2], c[3], c[4] or 1 end
    return 0.25, 0.55, 1.0, 0.08
end

local function getGuideColor()
    local c = SuuUI.Theme:GetToken("colorGuide")
    if type(c) == "table" then return c[1], c[2], c[3], c[4] or 1 end
    return 0.25, 0.55, 1.0, 0.40
end

local function hideAllLines()
    for i = 1, #hLines do hLines[i]:Hide() end
    for i = 1, #vLines do vLines[i]:Hide() end
end

local function drawGrid()
    ensureFrames()
    if not gridFrame then return end

    hideAllLines()

    local step = SuuUI.Settings:Get("_layout", "grid_size") or 16
    if step < 1 then return end

    local root = SuuUI.UIRoot:GetRoot()
    local w = root:GetWidth() or 0
    local h = root:GetHeight() or 0
    if w == 0 or h == 0 then return end

    local r, g, b, a = getGridColor()
    local lineThick = SuuUI.Pixel and SuuUI.Pixel.Line(1) or 1

    -- Horizontal lines
    local hCount = floor(h / step)
    for i = 1, hCount do
        local line = hLines[i]
        if not line then
            line = gridFrame:CreateTexture(nil, "OVERLAY")
            hLines[i] = line
        end
        line:SetColorTexture(r, g, b, a)
        line:ClearAllPoints()
        line:SetPoint("TOPLEFT", gridFrame, "TOPLEFT", 0, -(i * step))
        line:SetPoint("TOPRIGHT", gridFrame, "TOPRIGHT", 0, -(i * step))
        line:SetHeight(lineThick)
        line:Show()
    end
    -- Hide excess
    for i = hCount + 1, #hLines do hLines[i]:Hide() end

    -- Vertical lines
    local vCount = floor(w / step)
    for i = 1, vCount do
        local line = vLines[i]
        if not line then
            line = gridFrame:CreateTexture(nil, "OVERLAY")
            vLines[i] = line
        end
        line:SetColorTexture(r, g, b, a)
        line:ClearAllPoints()
        line:SetPoint("TOPLEFT", gridFrame, "TOPLEFT", i * step, 0)
        line:SetPoint("BOTTOMLEFT", gridFrame, "BOTTOMLEFT", i * step, 0)
        line:SetWidth(lineThick)
        line:Show()
    end
    for i = vCount + 1, #vLines do vLines[i]:Hide() end
end

local function updateVisibility()
    ensureFrames()
    if not gridFrame then return end

    local editMode = SuuUI.Settings:Get("_layout", "edit_mode")
    local showGrid = SuuUI.Settings:Get("_layout", "show_grid")

    if editMode and showGrid then
        if not isShowing then
            isShowing = true
            gridFrame:Show()
            drawGrid()
        end
    else
        if isShowing then
            isShowing = false
            gridFrame:Hide()
        end
    end
end

---------------------------------------------------------------------------
-- Guide Line Display (for drag feedback)
---------------------------------------------------------------------------

--- Show smart guide lines for the given positions.
-- Called by MoveableFrame during a drag to display alignment lines.
-- @param guides table  { h = {y1,...}, v = {x1,...} } in root space
-- Note: h values are WoW y-coordinates (bottom-up), v values are x-coordinates (left-right).
function M:ShowGuides(guides)
    ensureFrames()
    if not guidesFrame then return end

    local r, g, b, a = getGuideColor()
    local lineThick = SuuUI.Pixel and SuuUI.Pixel.Line(1) or 1

    -- The root's height, needed to convert WoW y (bottom-up) to TOPLEFT offset (top-down)
    local rootH = guidesFrame:GetHeight() or 0

    -- Horizontal guide lines (drawn at a y position)
    -- WoW y is bottom-up; TOPLEFT offset is top-down, so offset = rootH - y
    local hi = 0
    if guides.h then
        for _, y in ipairs(guides.h) do
            hi = hi + 1
            local line = guideHLines[hi]
            if not line then
                line = guidesFrame:CreateTexture(nil, "OVERLAY")
                guideHLines[hi] = line
            end
            line:SetColorTexture(r, g, b, a)
            line:ClearAllPoints()
            local topOffset = -(rootH - y)
            line:SetPoint("TOPLEFT", guidesFrame, "TOPLEFT", 0, topOffset)
            line:SetPoint("TOPRIGHT", guidesFrame, "TOPRIGHT", 0, topOffset)
            line:SetHeight(lineThick)
            line:Show()
        end
    end
    for i = hi + 1, #guideHLines do guideHLines[i]:Hide() end

    -- Vertical guide lines
    local vi = 0
    if guides.v then
        for _, x in ipairs(guides.v) do
            vi = vi + 1
            local line = guideVLines[vi]
            if not line then
                line = guidesFrame:CreateTexture(nil, "OVERLAY")
                guideVLines[vi] = line
            end
            line:SetColorTexture(r, g, b, a)
            line:ClearAllPoints()
            line:SetPoint("TOPLEFT", guidesFrame, "TOPLEFT", x, 0)
            line:SetPoint("BOTTOMLEFT", guidesFrame, "BOTTOMLEFT", x, 0)
            line:SetWidth(lineThick)
            line:Show()
        end
    end
    for i = vi + 1, #guideVLines do guideVLines[i]:Hide() end

    guidesFrame:Show()
end

--- Hide all smart guide lines.
function M:HideGuides()
    if not guidesFrame then return end
    for i = 1, #guideHLines do guideHLines[i]:Hide() end
    for i = 1, #guideVLines do guideVLines[i]:Hide() end
    guidesFrame:Hide()
end

-- Guides are recomputed WHILE the drag runs. Computing them once at drag start freezes
-- them at the position the frame was picked up from, so the lines describe where the
-- element used to be — which is what made them look unrelated to what was on screen.
local GUIDE_TICK = 0.05
local dragTicker, dragFrame
local tickAccum = 0

local function onDragTick(_, dt)
    tickAccum = tickAccum + dt
    if tickAccum < GUIDE_TICK then return end
    tickAccum = 0
    if not dragFrame then return end
    -- FindGuides reuses a scratch table, so this loop does not allocate per tick.
    -- ToggleUI:GetAll() does build a list; the throttle bounds that to 20/sec and only
    -- while a drag is actually in flight.
    M:ShowGuides(M:FindGuides(dragFrame))
end

--- Start showing live alignment guides for a frame being dragged.
-- @param frame table
function M:BeginGuides(frame)
    if not frame then return end
    dragFrame, tickAccum = frame, 0
    ensureFrames()
    M:ShowGuides(M:FindGuides(frame))
    if not dragTicker then dragTicker = CreateFrame("Frame") end
    dragTicker:SetScript("OnUpdate", onDragTick)
end

--- Stop the guide ticker and clear the lines.
-- The OnUpdate is unregistered rather than left idling, per the performance rules.
function M:EndGuides()
    dragFrame = nil
    if dragTicker then dragTicker:SetScript("OnUpdate", nil) end
    M:HideGuides()
end

---------------------------------------------------------------------------
-- Lifecycle
---------------------------------------------------------------------------

--- Initialise the grid system. Called after UIRoot:Init().
function M:Init()
    ensureFrames()

    -- Watch edit mode and show_grid to toggle visibility
    SuuUI.Settings:Watch("_layout", "edit_mode", function()
        updateVisibility()
    end, "_snapgrid_edit", { immediate = true })

    SuuUI.Settings:Watch("_layout", "show_grid", function()
        updateVisibility()
    end, "_snapgrid_show", { immediate = true })

    -- Redraw when grid_size changes
    SuuUI.Settings:Watch("_layout", "grid_size", function()
        if isShowing then drawGrid() end
    end, "_snapgrid_size", { immediate = true })

    -- Restyle on theme change (colour tokens may have moved)
    SuuUI.Events:On("SUUUI_THEME_CHANGED", function()
        if isShowing then drawGrid() end
    end, "_snapgrid_theme")

    -- Redraw on pixel grid change (screen size, UI scale)
    SuuUI.Events:On("SUUUI_PIXEL_GRID_CHANGED", function()
        if isShowing then drawGrid() end
    end, "_snapgrid_pixel")
end

SuuUI.SnapGrid = M
