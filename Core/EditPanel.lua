-- EditPanel: side panel properties inspector for edit mode.
-- Shows position, lock/snap controls, grid settings, and an element list.
-- Appears on the right edge of the screen when edit mode is active.
local C = SuuUI.Components
local T = SuuUI.Theme
local S = SuuUI.UISignals
local floor = math.floor
local tostring, tonumber = tostring, tonumber

local M = {}
local panelWin, panelFrame, panelBox, scroll
local posXInput, posYInput, anchorDropdown
local lockToggle
local gridSizeSlider, showGridToggle
local resetBtn
local elemList, elemContainer
local selectedFrame = nil
local elemItems = {} -- array of { frame = moveableFrame, item = navItem }

local PANEL_WIDTH = 200

local ANCHORS = {
    { value = "TOPLEFT",     label = "Top Left" },
    { value = "TOP",         label = "Top" },
    { value = "TOPRIGHT",    label = "Top Right" },
    { value = "LEFT",        label = "Left" },
    { value = "CENTER",      label = "Center" },
    { value = "RIGHT",       label = "Right" },
    { value = "BOTTOMLEFT",  label = "Bottom Left" },
    { value = "BOTTOM",      label = "Bottom" },
    { value = "BOTTOMRIGHT", label = "Bottom Right" },
}

---------------------------------------------------------------------------
-- Helpers
---------------------------------------------------------------------------

local function getPosition(frame)
    local data = frame._suuui_moveable
    if not data then return nil end
    local pos = SuuUI.Settings:Get(data.pluginId, data.key)
    if not pos then pos = data.defaults end
    return pos
end

local function refreshFields()
    if not selectedFrame then
        if posXInput then posXInput:SetValue("") end
        if posYInput then posYInput:SetValue("") end
        if anchorDropdown then anchorDropdown:SetValue("CENTER") end
        if lockToggle then lockToggle:SetValue(false) end
        return
    end

    local pos = getPosition(selectedFrame)
    if not pos then return end

    if posXInput then posXInput:SetValue(tostring(floor(pos.x or 0))) end
    if posYInput then posYInput:SetValue(tostring(floor(pos.y or 0))) end
    if anchorDropdown then anchorDropdown:SetValue(pos.point or "CENTER") end
    if lockToggle then lockToggle:SetValue(SuuUI.MoveableFrame:IsLocked(selectedFrame)) end
end

local function highlightList()
    for _, entry in ipairs(elemItems) do
        if entry.frame == selectedFrame then
            entry.item:SetSelected(true)
        else
            entry.item:SetSelected(false)
        end
    end
end

local function rebuildElementList()
    -- Clear old items
    if elemContainer then elemContainer:Clear() end
    for _, entry in ipairs(elemItems) do
        if entry.item and entry.item.Destroy then entry.item:Destroy() end
    end
    elemItems = {}

    if not elemContainer then return end

    local all = SuuUI.ToggleUI:GetAll()
    for _, frame in ipairs(all) do
        local data = frame._suuui_moveable
        if data then
            local displayName = data.displayName or "Element"
            local item = C.NavItem({
                label = displayName,
            }, elemContainer:GetFrame())
            elemItems[#elemItems + 1] = { frame = frame, item = item }
            elemContainer:Add(item, { width = "fill" })

            -- Click to select
            S:Connect(item, S.SIGNALS.CLICKED, function()
                M:Select(frame)
            end)
        end
    end

    highlightList()
end

---------------------------------------------------------------------------
-- Public API
---------------------------------------------------------------------------

--- Select a frame for inspection in the panel.
-- @param frame table  A moveable frame (must have _suuui_moveable)
function M:Select(frame)
    if frame and not frame._suuui_moveable then return end
    local prev = selectedFrame
    selectedFrame = frame
    refreshFields()
    highlightList()
    -- Repaint overlays so the selected frame gets a different colour
    if prev and prev._suuui_moveable and prev._suuui_moveable.paintOverlay then
        prev._suuui_moveable.paintOverlay()
    end
    if frame and frame._suuui_moveable and frame._suuui_moveable.paintOverlay then
        frame._suuui_moveable.paintOverlay()
    end
end

--- Returns the currently selected frame, or nil.
-- @return table|nil
function M:GetSelected()
    return selectedFrame
end

--- Refresh displayed values from the selected frame's current position.
function M:Refresh()
    refreshFields()
end

---------------------------------------------------------------------------
-- Panel Construction
---------------------------------------------------------------------------

--- Initialise the edit panel. Called after UIRoot:Init() and after SnapGrid:Init().
function M:Init()
    -- Defer full construction to the first time edit mode activates.
    -- This avoids creating components (which may fire animations) during login when
    -- the panel is never shown.
    local built = false

    SuuUI.Settings:Watch("_layout", "edit_mode", function(isEdit)
        if isEdit and not built then
            built = true
            M:_build()
        end
        if panelWin then
            if isEdit then
                rebuildElementList()
                panelWin:Show()
                -- Auto-select the first element so the panel is never empty
                if not selectedFrame and #elemItems > 0 then
                    M:Select(elemItems[1].frame)
                end
            else
                panelWin:Hide()
                selectedFrame = nil
            end
        end
    end, "_editpanel_mode", { immediate = true })
end

function M:_build()
    local root = SuuUI.UIRoot:GetRoot()
    if not root then return end

    local PANEL_HEIGHT = 480

    -- Use a proper Window so the panel is draggable and feels like a tool palette.
    local win = SuuUI.Layout:CreateWindow({
        id        = "edit_panel",
        title     = "Properties",
        w         = PANEL_WIDTH,
        h         = PANEL_HEIGHT,
        resizable = false,
        centered  = false,
    })
    panelWin = win
    panelFrame = win:GetFrame()

    -- Closing the Properties window exits edit mode.
    -- The _building flag prevents the initial Hide() from triggering this.
    local buildingDone = false
    S:Connect(win, S.SIGNALS.VISIBILITY_CHANGED, function(isVisible)
        if not buildingDone then return end
        if not isVisible and SuuUI.ToggleUI:IsEditMode() then
            SuuUI.ToggleUI:Disable()
        end
    end)

    -- The window starts hidden; the Init watcher shows it.
    win:Hide()
    buildingDone = true

    local winContent = win:GetContentFrame()

    -- Fill container to position the scroll frame inside the window's content area
    local winBox = SuuUI.Layout:CreateContainer({
        host = winContent, layout = "flow", dir = "vertical",
        fill = true,
    })

    -- The scroll frame fills the window's content area. Use fixed initial size;
    -- the fill container tracks resizes from window dragging.
    scroll = C.ScrollFrame({
        w = PANEL_WIDTH - 4,
        h = PANEL_HEIGHT - 34,
    }, winContent)
    winBox:Add(scroll, { width = "fill", height = "fill" })

    local scrollContent = scroll:GetContent()
    panelBox = SuuUI.Layout:CreateContainer({
        parent  = scrollContent,
        layout  = "flow",
        dir     = "vertical",
        gap     = T:GetToken("spaceXs"),
        padding = {
            top    = T:GetToken("spaceSm"),
            right  = T:GetToken("spaceSm"),
            bottom = T:GetToken("spaceSm"),
            left   = T:GetToken("spaceSm"),
        },
    })

    -- Track content height for scroll
    S:Connect(panelBox, S.SIGNALS.SIZE_CHANGED, function(_, h)
        scrollContent:SetHeight(h)
        S:Emit(scroll, S.SIGNALS.CONTENT_RESIZED, h)
    end)

    -- === Header ===
    local header = C.Text({ text = "Properties", size = "lg", color = "text" }, scrollContent)
    panelBox:Add(header, { width = "fill" })

    panelBox:Add(C.Divider({}, scrollContent), { width = "fill" })

    -- === Position Section ===
    local posLabel = C.Text({ text = "Position", size = "sm", color = "textMuted" }, scrollContent)
    panelBox:Add(posLabel, { width = "fill" })

    -- X row
    local xRow = SuuUI.Layout:CreateContainer({
        parent = scrollContent, layout = "flow", dir = "horizontal",
        gap = T:GetToken("spaceXs"), align = "center",
    })
    local xLabel = C.Text({ text = "X", size = "sm", color = "textMuted" }, scrollContent)
    posXInput = C.Input({ w = 60, value = "0" }, scrollContent)
    xRow:Add(xLabel, { width = 20 })
    xRow:Add(posXInput, { width = "fill" })
    panelBox:Add(xRow, { width = "fill" })

    -- Y row
    local yRow = SuuUI.Layout:CreateContainer({
        parent = scrollContent, layout = "flow", dir = "horizontal",
        gap = T:GetToken("spaceXs"), align = "center",
    })
    local yLabel = C.Text({ text = "Y", size = "sm", color = "textMuted" }, scrollContent)
    posYInput = C.Input({ w = 60, value = "0" }, scrollContent)
    yRow:Add(yLabel, { width = 20 })
    yRow:Add(posYInput, { width = "fill" })
    panelBox:Add(yRow, { width = "fill" })

    -- Anchor dropdown
    local anchorRow = SuuUI.Layout:CreateContainer({
        parent = scrollContent, layout = "flow", dir = "horizontal",
        gap = T:GetToken("spaceXs"), align = "center",
    })
    local anchorLabel = C.Text({ text = "Anchor", size = "sm", color = "textMuted" }, scrollContent)
    anchorDropdown = C.Dropdown({ options = ANCHORS, value = "CENTER", w = 110 }, scrollContent)
    anchorRow:Add(anchorLabel, { width = "fill" })
    anchorRow:Add(anchorDropdown)
    panelBox:Add(anchorRow, { width = "fill" })

    panelBox:Add(C.Divider({}, scrollContent), { width = "fill" })

    -- === Behaviour Section ===
    local behLabel = C.Text({ text = "Behaviour", size = "sm", color = "textMuted" }, scrollContent)
    panelBox:Add(behLabel, { width = "fill" })

    -- Lock toggle row
    local lockRow = SuuUI.Layout:CreateContainer({
        parent = scrollContent, layout = "flow", dir = "horizontal",
        gap = T:GetToken("spaceXs"), align = "center",
    })
    local lockLabel = C.Text({ text = "Lock Position", size = "sm", color = "text" }, scrollContent)
    lockToggle = C.Toggle({ value = false }, scrollContent)
    lockRow:Add(lockLabel, { width = "fill" })
    lockRow:Add(lockToggle)
    panelBox:Add(lockRow, { width = "fill" })

    -- Snap mode dropdown row
    local snapRow = SuuUI.Layout:CreateContainer({
        parent = scrollContent, layout = "flow", dir = "horizontal",
        gap = T:GetToken("spaceXs"), align = "center",
    })
    local snapLabel = C.Text({ text = "Snap Mode", size = "sm", color = "text" }, scrollContent)
    local snapModeDropdown = C.Dropdown({
        options = {
            { value = "none",   label = "None" },
            { value = "grid",   label = "Grid" },
            { value = "guides", label = "Guides" },
        },
        value = "grid",
        w = 90,
    }, scrollContent)
    snapRow:Add(snapLabel, { width = "fill" })
    snapRow:Add(snapModeDropdown)
    panelBox:Add(snapRow, { width = "fill" })

    panelBox:Add(C.Divider({}, scrollContent), { width = "fill" })

    -- === Grid Section ===
    local gridLabel = C.Text({ text = "Grid", size = "sm", color = "textMuted" }, scrollContent)
    panelBox:Add(gridLabel, { width = "fill" })

    -- Grid size slider
    gridSizeSlider = C.Slider({
        label = "Grid Size",
        min = 4, max = 64, step = 4, value = 16,
    }, scrollContent)
    panelBox:Add(gridSizeSlider, { width = "fill" })

    -- Show grid toggle
    local showRow = SuuUI.Layout:CreateContainer({
        parent = scrollContent, layout = "flow", dir = "horizontal",
        gap = T:GetToken("spaceXs"), align = "center",
    })
    local showLabel = C.Text({ text = "Show Grid", size = "sm", color = "text" }, scrollContent)
    showGridToggle = C.Toggle({ value = true }, scrollContent)
    showRow:Add(showLabel, { width = "fill" })
    showRow:Add(showGridToggle)
    panelBox:Add(showRow, { width = "fill" })

    panelBox:Add(C.Divider({}, scrollContent), { width = "fill" })

    -- === Reset Button ===
    resetBtn = C.Button({ label = "Reset Position" }, scrollContent)
    panelBox:Add(resetBtn, { width = "fill" })

    panelBox:Add(C.Divider({}, scrollContent), { width = "fill" })

    -- === Element List ===
    local listLabel = C.Text({ text = "Elements", size = "sm", color = "textMuted" }, scrollContent)
    panelBox:Add(listLabel, { width = "fill" })

    elemContainer = SuuUI.Layout:CreateContainer({
        parent = scrollContent, layout = "flow", dir = "vertical",
        gap = T:GetToken("spaceXxs"),
    })
    panelBox:Add(elemContainer, { width = "fill" })

    ---------------------------------------------------------------------------
    -- Wiring
    ---------------------------------------------------------------------------

    -- X/Y input -> move frame
    S:Connect(posXInput, SuuUI.Components.INPUT_SIGNALS.SUBMITTED, function(text)
        if not selectedFrame then return end
        local data = selectedFrame._suuui_moveable
        if not data then return end
        local newX = tonumber(text)
        if not newX then return end
        local pos = getPosition(selectedFrame)
        if not pos then return end
        -- Copy to avoid in-place mutation being dropped by Settings' equality check
        local newPos = { point = pos.point, relPoint = pos.relPoint, x = newX, y = pos.y, locked = pos.locked }
        SuuUI.Settings:Set(data.pluginId, data.key, newPos)
    end)

    S:Connect(posYInput, SuuUI.Components.INPUT_SIGNALS.SUBMITTED, function(text)
        if not selectedFrame then return end
        local data = selectedFrame._suuui_moveable
        if not data then return end
        local newY = tonumber(text)
        if not newY then return end
        local pos = getPosition(selectedFrame)
        if not pos then return end
        -- Copy to avoid in-place mutation being dropped by Settings' equality check
        local newPos = { point = pos.point, relPoint = pos.relPoint, x = pos.x, y = newY, locked = pos.locked }
        SuuUI.Settings:Set(data.pluginId, data.key, newPos)
    end)

    -- Anchor dropdown -> change anchor point
    -- Changing anchor changes what x/y mean, so we reset offsets to 0 (places the frame
    -- at the new anchor's origin). The user can then adjust x/y from there.
    S:Connect(anchorDropdown, S.SIGNALS.VALUE_CHANGED, function(newVal)
        if not selectedFrame then return end
        local data = selectedFrame._suuui_moveable
        if not data then return end
        local pos = getPosition(selectedFrame)
        if not pos then return end
        local newPos = { point = newVal, relPoint = newVal, x = 0, y = 0, locked = pos.locked }
        SuuUI.Settings:Set(data.pluginId, data.key, newPos)
    end)

    -- Lock toggle -> lock/unlock selected frame
    S:Connect(lockToggle, S.SIGNALS.VALUE_CHANGED, function(val)
        if not selectedFrame then return end
        SuuUI.MoveableFrame:SetLocked(selectedFrame, val)
        highlightList()
    end)

    -- Snap toggle <-> Settings
    -- Snap mode dropdown <-> Settings
    S:Connect(snapModeDropdown, S.SIGNALS.VALUE_CHANGED, function(val)
        SuuUI.Settings:Set("_layout", "snap_mode", val)
    end)
    SuuUI.Settings:Watch("_layout", "snap_mode", function(val)
        snapModeDropdown:SetValue(val or "grid")
    end, "_editpanel_snap", { immediate = true })

    -- Grid size slider <-> Settings
    S:Connect(gridSizeSlider, S.SIGNALS.VALUE_CHANGED, function(val)
        SuuUI.Settings:Set("_layout", "grid_size", val)
    end)
    SuuUI.Settings:Watch("_layout", "grid_size", function(val)
        gridSizeSlider:SetValue(val or 16)
    end, "_editpanel_gridsize", { immediate = true })

    -- Show grid toggle <-> Settings
    S:Connect(showGridToggle, S.SIGNALS.VALUE_CHANGED, function(val)
        SuuUI.Settings:Set("_layout", "show_grid", val)
    end)
    SuuUI.Settings:Watch("_layout", "show_grid", function(val)
        showGridToggle:SetValue(val and true or false)
    end, "_editpanel_showgrid", { immediate = true })

    -- Reset button
    S:Connect(resetBtn, S.SIGNALS.CLICKED, function()
        if not selectedFrame then return end
        SuuUI.MoveableFrame:ResetPosition(selectedFrame)
        refreshFields()
    end)

    -- Edit mode drives the panel (visibility managed by the outer SUUUI_READY watcher)

    -- Watch for position changes on the selected frame (refresh fields on drag)
    -- This is done lazily: refresh on every SUUUI_SETTING_CHANGED for the selected frame.
    SuuUI.Events:On("SUUUI_SETTING_CHANGED", function(pluginId, changedKey)
        if not selectedFrame then return end
        local data = selectedFrame._suuui_moveable
        if data and data.pluginId == pluginId and data.key == changedKey then
            refreshFields()
            highlightList()
        end
    end, "_editpanel_setting_watch")

    -- Rebuild element list when a frame is registered or unregistered (e.g. resource bar
    -- switching between attached/detached mode).
    SuuUI.Events:On("SUUUI_MOVEABLE_LIST_CHANGED", function()
        if not panelWin or not panelFrame:IsShown() then return end
        -- If the selected frame was removed, clear selection
        if selectedFrame and not selectedFrame._suuui_moveable then
            selectedFrame = nil
        end
        rebuildElementList()
        -- Auto-select first if nothing selected
        if not selectedFrame and #elemItems > 0 then
            M:Select(elemItems[1].frame)
        end
    end, "_editpanel_list_watch")
end

SuuUI.EditPanel = M
