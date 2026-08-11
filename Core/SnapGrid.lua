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
    -- Guide snap works on the frame's screen position. We need to find the nearest
    -- other element edge. Since we receive anchor offsets (TOPLEFT-relative after drag),
    -- and other frames report in screen coords, we compare in screen coords.
    local fl = frame:GetLeft()
    local ft = frame:GetTop()
    if not (fl and ft) then return x, y end

    local fw = frame:GetWidth() or 0
    local fh = frame:GetHeight() or 0
    local fr = fl + fw
    local fb = ft - fh
    local fcx = (fl + fr) * 0.5
    local fcy = (ft + fb) * 0.5

    local bestDx, snapX = GUIDE_SNAP_THRESHOLD + 1, nil
    local bestDy, snapY = GUIDE_SNAP_THRESHOLD + 1, nil

    local all = SuuUI.ToggleUI:GetAll()
    for _, other in pairs(all) do
        if other ~= frame and other:IsShown() then
            local ol = other:GetLeft()
            local or_ = other:GetRight()
            local ot = other:GetTop()
            local ob = other:GetBottom()
            if ol and or_ and ot and ob then
                local ocx = (ol + or_) * 0.5
                local ocy = (ot + ob) * 0.5

                -- Check x alignments (left-left, left-right, right-left, right-right, center-center)
                for _, ref in ipairs({ol, or_, ocx}) do
                    -- Snap our left edge to ref
                    local d = abs(fl - ref)
                    if d < bestDx then bestDx = d; snapX = x + (ref - fl) end
                    -- Snap our right edge to ref
                    d = abs(fr - ref)
                    if d < bestDx then bestDx = d; snapX = x + (ref - fr) end
                    -- Snap our center to ref
                    d = abs(fcx - ref)
                    if d < bestDx then bestDx = d; snapX = x + (ref - fcx) end
                end

                -- Check y alignments (top-top, bottom-bottom, center-center, etc.)
                for _, ref in ipairs({ot, ob, ocy}) do
                    -- Snap our top to ref
                    local d = abs(ft - ref)
                    if d < bestDy then bestDy = d; snapY = y + (ref - ft) end
                    -- Snap our bottom to ref
                    d = abs(fb - ref)
                    if d < bestDy then bestDy = d; snapY = y + (ref - fb) end
                    -- Snap our center to ref
                    d = abs(fcy - ref)
                    if d < bestDy then bestDy = d; snapY = y + (ref - fcy) end
                end
            end
        end
    end

    return snapX or x, snapY or y
end

---------------------------------------------------------------------------
-- Smart Guides
---------------------------------------------------------------------------

--- Find guide positions from all other moveable frames.
-- Returns { h = {y1, y2, ...}, v = {x1, x2, ...} } in WoW coordinate space.
-- These are the edges and centers of every OTHER visible moveable frame, so the user
-- can align the dragged frame to them visually.
-- @param frame table  The frame being dragged (excluded from results)
-- @return table
function M:FindGuides(frame)
    local result = { h = {}, v = {} }
    if not frame then return result end

    local all = SuuUI.ToggleUI:GetAll()
    for _, other in pairs(all) do
        if other ~= frame and other:IsShown() then
            local ol = other:GetLeft()
            local or_ = other:GetRight()
            local ot = other:GetTop()
            local ob = other:GetBottom()
            if ol and or_ and ot and ob then
                local ocx = (ol + or_) * 0.5
                local ocy = (ot + ob) * 0.5

                -- Horizontal guides: top, center, bottom of other frame
                tinsert(result.h, ot)
                tinsert(result.h, ocy)
                tinsert(result.h, ob)

                -- Vertical guides: left, center, right of other frame
                tinsert(result.v, ol)
                tinsert(result.v, ocx)
                tinsert(result.v, or_)
            end
        end
    end

    return result
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
