-- MoveableFrame: mixin that makes a SuuUI frame repositionable in edit mode.
-- Stores position in the plugin's Settings namespace so it is profile-aware.
local C = SuuUI.Components
local T = SuuUI.Theme
local math_abs, math_floor = math.abs, math.floor

local M = {}

-- Which edge of the frame an anchor point pins vertically. Compensation depends only on
-- this, not on the horizontal half of the point: a band added above the content moves the
-- content down under a TOP* anchor and not at all under a BOTTOM* one.
local V_EDGE = {
    TOPLEFT     = "top",    TOP    = "top",    TOPRIGHT    = "top",
    BOTTOMLEFT  = "bottom", BOTTOM = "bottom", BOTTOMRIGHT = "bottom",
    LEFT        = "middle", RIGHT  = "middle", CENTER      = "middle",
}

--- How far a frame's positioned content is inset from the frame's own top and bottom edges.
local function coreInset(frame)
    local data = frame._suuui_moveable
    local fn = data and data.coreInset
    if not fn then return 0, 0 end
    local ok, top, bottom = pcall(fn)
    if not ok then
        SuuUI.Debug("MoveableFrame: coreInset error: " .. tostring(top))
        return 0, 0
    end
    return tonumber(top) or 0, tonumber(bottom) or 0
end

local function shiftY(frame, point, y, sign)
    local top, bottom = coreInset(frame)
    if top == 0 and bottom == 0 then return y end
    local edge = V_EDGE[point or ""] or "top"
    if edge == "top" then
        return y + sign * top
    elseif edge == "bottom" then
        return y - sign * bottom
    end
    return y - sign * (bottom - top) / 2
end

--- Applies moveable behaviour to a frame.
-- @param frame table  The raw WoW frame (not a component wrapper)
-- @param opts table   { pluginId, key, displayName, defaults, coreInset }
function M:Apply(frame, opts)
    local pluginId    = opts.pluginId
    local key         = opts.key
    local displayName = opts.displayName or ""
    local defaults    = opts.defaults or { point = "CENTER", relPoint = "CENTER", x = 0, y = 0 }

    -- Register with ToggleUI
    SuuUI.ToggleUI:Register(frame)

    -- UIRoot owns placement.
    if not frame._suuui_anchor and SuuUI.UIRoot:GetRoot() then
        SuuUI.UIRoot:AddElement(frame, SuuUI.UIRoot:GetLayer(frame) or "normal", {
            point         = defaults.point,
            relativePoint = defaults.relPoint,
            x             = defaults.x,
            y             = defaults.y,
        })
    end

    -- Create overlay (hidden by default). Uses BackdropTemplate for selection border.
    local overlay = CreateFrame("Frame", nil, frame, "BackdropTemplate")
    SuuUI.UIRoot:RaiseAbove(overlay, frame, 5)
    overlay:Hide()

    local overlayBox = SuuUI.Layout:CreateContainer({ host = frame, layout = "stack" })
    overlayBox:Add(overlay)

    local overlayBg = overlay:CreateTexture(nil, "BACKGROUND")

    -- Selection border: a backdrop border drawn on the overlay when selected.
    -- Applied via Backdrop so it uses the token system and border width.
    SuuUI.Backdrop.Apply(overlay, { bg = false, border = false })

    local label = C.Text({
        text  = displayName,
        size  = "md",
        color = "text",
    }, overlay)

    -- Lock badge: shown only when locked.
    local lockBadge = C.Text({
        text  = "\240\159\148\146",
        size  = "md",
        color = "text",
    }, overlay)
    lockBadge:Hide()

    local contentBox = SuuUI.Layout:CreateContainer({ host = overlay, layout = "stack" })
    contentBox:Add(overlayBg)
    contentBox:Add(label, { align = "center", valign = "center" })
    contentBox:Add(lockBadge, { align = "end", valign = "start", inset = { top = 2, right = 4 } })

    local function paintOverlay()
        local locked = M:IsLocked(frame)
        local isSelected = SuuUI.EditPanel and SuuUI.EditPanel.GetSelected
            and SuuUI.EditPanel:GetSelected() == frame

        -- Fill colour: locked gets warning tint, otherwise standard edit overlay
        local tokenKey = locked and "colorEditOverlayLocked" or "colorEditOverlay"
        local c = T:GetToken(tokenKey) or {0, 0.6, 1, 0.2}
        overlayBg:SetColorTexture(c[1], c[2], c[3], c[4] or 0.2)

        -- Selection border: accent border when selected, none otherwise
        if isSelected then
            SuuUI.Backdrop.SetBorder(overlay, "colorAccent")
        else
            SuuUI.Backdrop.SetBorder(overlay, false)
        end

        if locked then
            lockBadge:Show()
        else
            lockBadge:Hide()
        end
    end
    paintOverlay()

    local themeOwner = "moveable_theme_" .. pluginId .. "_" .. key
    SuuUI.Events:On("SUUUI_THEME_CHANGED", paintOverlay, themeOwner)

    -- Store references for cleanup
    frame._suuui_moveable = {
        overlay     = overlay,
        overlayBg   = overlayBg,
        label       = label,
        lockBadge   = lockBadge,
        overlayBox  = overlayBox,
        contentBox  = contentBox,
        themeOwner  = themeOwner,
        pluginId    = pluginId,
        key         = key,
        defaults    = defaults,
        displayName = displayName,
        coreInset   = opts.coreInset,
        paintOverlay = paintOverlay,
    }

    -- Drag setup (always configured, only active in edit mode)
    frame:SetMovable(true)
    frame:SetClampedToScreen(true)

    overlay:EnableMouse(true)
    overlay:RegisterForDrag("LeftButton")

    -- Track drag state for click-to-select detection
    local dragStartX, dragStartY = 0, 0
    local dragActive = false

    -- OnMouseDown/OnMouseUp for click-to-select: fires on every click regardless of
    -- whether the drag threshold is crossed. OnDragStart/OnDragStop only fire after the
    -- client's internal drag threshold (several pixels), so a short click never reaches
    -- OnDragStop and the selection would never happen there.
    overlay:SetScript("OnMouseDown", function(_, button)
        if button ~= "LeftButton" then return end
        local cx, cy = GetCursorPosition()
        dragStartX, dragStartY = cx, cy
    end)

    overlay:SetScript("OnMouseUp", function(_, button)
        if button ~= "LeftButton" then return end
        if not SuuUI.ToggleUI:IsEditMode() then return end
        local cx, cy = GetCursorPosition()
        local dx = math_abs(cx - dragStartX)
        local dy = math_abs(cy - dragStartY)
        -- Treat as a click if movement was minimal (under the drag threshold)
        if dx < 3 and dy < 3 then
            if SuuUI.EditPanel and SuuUI.EditPanel.Select then
                SuuUI.EditPanel:Select(frame)
            end
        end
    end)

    overlay:SetScript("OnDragStart", function()
        if not SuuUI.ToggleUI:IsEditMode() then return end
        if M:IsLocked(frame) then return end
        dragActive = true
        frame:StartMoving()
        -- Show smart guides during drag
        if SuuUI.SnapGrid and SuuUI.SnapGrid.ShowGuides then
            local guides = SuuUI.SnapGrid:FindGuides(frame)
            SuuUI.SnapGrid:ShowGuides(guides)
        end
    end)

    overlay:SetScript("OnDragStop", function()
        frame:StopMovingOrSizing()
        -- Hide smart guides
        if SuuUI.SnapGrid and SuuUI.SnapGrid.HideGuides then
            SuuUI.SnapGrid:HideGuides()
        end
        dragActive = false

        -- If locked, no position saving (drag was blocked at start)
        if M:IsLocked(frame) then return end

        -- Save position. After StopMovingOrSizing the client sets the frame's anchor
        -- to TOPLEFT with absolute offsets. We save exactly what the client gives us.
        local point, _, relPoint, x, y = frame:GetPoint()
        local data = frame._suuui_moveable

        -- Remove coreInset compensation for storage
        y = shiftY(frame, point, y, -1)

        -- Snap: grid or guides depending on snap_mode setting
        if SuuUI.SnapGrid and SuuUI.SnapGrid.Snap then
            x, y = SuuUI.SnapGrid:Snap(x, y, frame)
        end

        -- Preserve locked state
        local currentPos = SuuUI.Settings:Get(pluginId, key)
        local locked = currentPos and currentPos.locked

        data._saving = true
        SuuUI.Settings:Set(pluginId, key, {
            point    = point,
            relPoint = relPoint,
            x        = x,
            y        = y,
            locked   = locked,
        })
        data._saving = false
        M:_applyAnchor(frame, { point = point, relPoint = relPoint, x = x, y = y })
    end)

    -- Edit mode drives the overlay.
    SuuUI.Settings:Watch("_layout", "edit_mode", function(isEdit)
        if isEdit then
            overlay:Show()
        else
            overlay:Hide()
        end
    end, "moveable_" .. pluginId .. "_" .. key, { immediate = true })

    -- Position is bound the same way, so `immediate` also performs the initial restore.
    SuuUI.Settings:Watch(pluginId, key, function()
        local data = frame._suuui_moveable
        if not data or data._saving then return end
        M:RestorePosition(frame)
        -- Repaint overlay in case locked state changed via Settings:Set
        data.paintOverlay()
    end, "moveable_pos_" .. pluginId .. "_" .. key, { immediate = true })
end

--- Pushes a stored position into the root's anchor descriptor.
function M:_applyAnchor(frame, pos)
    local desc = {
        point         = pos.point,
        relativePoint = pos.relPoint,
        x             = pos.x,
        y             = shiftY(frame, pos.point, pos.y or 0, 1),
    }
    if frame._suuui_anchor and SuuUI.UIRoot:GetRoot() then
        SuuUI.UIRoot:UpdateElementAnchor(frame, desc)
        return
    end
    SuuUI._AnchorLayout.SetAnchor(frame, desc)
    local host = frame:GetParent()
    if host then
        local box = frame._suuui_placeBox
        if not box then
            box = SuuUI.Layout:CreateContainer({ host = host, layout = "anchor" })
            frame._suuui_placeBox = box
            box:Add(frame, { anchor = desc })
        else
            box:SetChildAnchor(frame, desc)
        end
    end
end

--- Restores a frame's position from Settings or defaults.
-- @param frame table
function M:RestorePosition(frame)
    local data = frame._suuui_moveable
    if not data then return end

    local pos = SuuUI.Settings:Get(data.pluginId, data.key)
    if not pos then pos = data.defaults end
    M:_applyAnchor(frame, pos)
end

--- Re-states a frame's placement from the position it already has stored.
-- @param frame table
function M:RefreshAnchor(frame)
    if not (frame and frame._suuui_moveable) then return end
    M:RestorePosition(frame)
end

--- Resets a frame's position to its defaults.
-- @param frame table
function M:ResetPosition(frame)
    local data = frame._suuui_moveable
    if not data then return end

    SuuUI.Settings:Set(data.pluginId, data.key, SuuUI.Utils.DeepCopy(data.defaults))
    M:RestorePosition(frame)
end

--- Sets the locked state for a moveable frame.
-- @param frame table
-- @param locked bool
function M:SetLocked(frame, locked)
    local data = frame._suuui_moveable
    if not data then return end

    local pos = SuuUI.Settings:Get(data.pluginId, data.key)
    if not pos then pos = SuuUI.Utils.DeepCopy(data.defaults) end
    pos.locked = locked and true or nil
    SuuUI.Settings:Set(data.pluginId, data.key, pos)
    data.paintOverlay()
end

--- Returns whether a moveable frame is locked.
-- @param frame table
-- @return bool
function M:IsLocked(frame)
    local data = frame._suuui_moveable
    if not data then return false end
    local pos = SuuUI.Settings:Get(data.pluginId, data.key)
    return pos and pos.locked and true or false
end

--- Removes moveable behaviour from a frame and cleans up.
-- @param frame table
function M:Remove(frame)
    local data = frame._suuui_moveable
    if not data then return end

    SuuUI.Settings:Unwatch("moveable_" .. data.pluginId .. "_" .. data.key)
    SuuUI.Settings:Unwatch("moveable_pos_" .. data.pluginId .. "_" .. data.key)
    SuuUI.Events:Off("SUUUI_THEME_CHANGED", data.themeOwner)
    SuuUI.ToggleUI:Unregister(frame)

    data.overlay:Hide()
    data.overlay:SetScript("OnDragStart", nil)
    data.overlay:SetScript("OnDragStop", nil)

    if data.lockBadge then data.lockBadge:Destroy() end
    if data.contentBox then data.contentBox:Destroy() end
    if data.overlayBox then data.overlayBox:Destroy() end
    if frame._suuui_placeBox then
        frame._suuui_placeBox:Destroy()
        frame._suuui_placeBox = nil
    end

    frame._suuui_moveable = nil
end

SuuUI.MoveableFrame = M
