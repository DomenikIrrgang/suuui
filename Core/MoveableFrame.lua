-- MoveableFrame: mixin that makes a SuuUI frame repositionable in edit mode.
-- Stores position in the plugin's Settings namespace so it is profile-aware.
local C = SuuUI.Components
local T = SuuUI.Theme

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
--
-- A frame that grows around foreign children — an attach-point publisher — is larger than
-- the thing the player actually aimed at when they dragged it. Without this the saved
-- position describes the bounding box, so a band appearing on the ANCHORED edge pushes the
-- content across the screen: the unit frame's bars jumped 26 units the moment a cast bar
-- attached below them, and jumped back on detach.
--
-- The provider is the plugin's, so it runs through pcall: it is called on every layout pass
-- and an error here would unwind into the layout engine.
-- @return number, number  top inset, bottom inset (both 0 when no provider)
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

-- Converts between the stored position (which describes the CONTENT) and the frame's own
-- anchor offset (which describes the bounding box). `sign` is 1 going out to the frame and
-- -1 coming back from it, so the two directions cannot drift apart.
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
--   pluginId    - plugin id for Settings:Get/Set
--   key         - settings key for position storage
--   displayName - label shown on overlay during edit mode
--   defaults    - { point, relPoint, x, y } default position
--   coreInset   - optional function() -> topInset, bottomInset. Supply it when the frame
--                 grows around content it does not own (attach slots), so the saved
--                 position keeps describing the frame's own content and bands extend
--                 outward instead of displacing it.
function M:Apply(frame, opts)
    local pluginId    = opts.pluginId
    local key         = opts.key
    local displayName = opts.displayName or ""
    local defaults    = opts.defaults or { point = "CENTER", relPoint = "CENTER", x = 0, y = 0 }

    -- Register with ToggleUI
    SuuUI.ToggleUI:Register(frame)

    -- UIRoot owns placement. Registering the frame as a root element is what lets the
    -- saved position be applied by the anchor strategy in the ROOT's unit space: the root
    -- carries the addon's own scale (Pixel:Attach), so anchoring to UIParent instead would
    -- resolve the same offsets against a different space and drop the frame in the wrong
    -- place at any pixel multiplier other than 1.
    if not frame._suuui_anchor and SuuUI.UIRoot:GetRoot() then
        SuuUI.UIRoot:AddElement(frame, SuuUI.UIRoot:GetLayer(frame) or "normal", {
            point         = defaults.point,
            relativePoint = defaults.relPoint,
            x             = defaults.x,
            y             = defaults.y,
        })
    end

    -- Create overlay (hidden by default). It stays on the frame's own layer and is only
    -- raised above it: promoting it to a higher layer would draw the edit-mode overlay
    -- over the settings window that carries the Edit Mode toggle.
    local overlay = CreateFrame("Frame", nil, frame)
    SuuUI.UIRoot:RaiseAbove(overlay, frame, 5)
    overlay:Hide()

    -- The overlay covers the frame, and its backdrop and label sit inside it. All three
    -- placements are the layout engine's: a stack child with no props fills its box, which
    -- is what SetAllPoints used to say by hand.
    local overlayBox = SuuUI.Layout:CreateContainer({ host = frame, layout = "stack" })
    overlayBox:Add(overlay)

    local overlayBg = overlay:CreateTexture(nil, "BACKGROUND")

    -- Accent-tinted, from a token: a hardcoded blue never follows the theme.
    local label = C.Text({
        text  = displayName,
        size  = "md",
        color = "text",
    }, overlay)

    local contentBox = SuuUI.Layout:CreateContainer({ host = overlay, layout = "stack" })
    contentBox:Add(overlayBg)
    contentBox:Add(label, { align = "center", valign = "center" })

    local function paintOverlay()
        local c = T:GetToken("colorEditOverlay") or {0, 0.6, 1, 0.2}
        overlayBg:SetColorTexture(c[1], c[2], c[3], c[4] or 0.2)
    end
    paintOverlay()

    local themeOwner = "moveable_theme_" .. pluginId .. "_" .. key
    SuuUI.Events:On("SUUUI_THEME_CHANGED", paintOverlay, themeOwner)

    -- Store references for cleanup
    frame._suuui_moveable = {
        overlay     = overlay,
        overlayBg   = overlayBg,
        label       = label,
        overlayBox  = overlayBox,
        contentBox  = contentBox,
        themeOwner  = themeOwner,
        pluginId    = pluginId,
        key         = key,
        defaults    = defaults,
        displayName = displayName,
        coreInset   = opts.coreInset,
    }

    -- Drag setup (always configured, only active in edit mode)
    frame:SetMovable(true)
    frame:SetClampedToScreen(true)

    overlay:EnableMouse(true)
    overlay:RegisterForDrag("LeftButton")
    overlay:SetScript("OnDragStart", function()
        if SuuUI.ToggleUI:IsEditMode() then
            frame:StartMoving()
        end
    end)
    overlay:SetScript("OnDragStop", function()
        frame:StopMovingOrSizing()
        -- Save position. The position watcher below would echo this write straight
        -- back into RestorePosition, so it is suppressed for the duration of our own
        -- save; only changes from elsewhere (a profile switch, a reset) should move
        -- the frame out from under the player.
        local point, _, relPoint, x, y = frame:GetPoint()
        -- The client dragged the whole frame, bands included, so GetPoint describes the
        -- bounding box. Store what the position MEANS — where the frame's own content
        -- sits — or the inset would be added a second time on the next restore and the
        -- frame would creep by one band height per drag.
        y = shiftY(frame, point, y, -1)
        local data = frame._suuui_moveable
        data._saving = true
        SuuUI.Settings:Set(pluginId, key, {
            point    = point,
            relPoint = relPoint,
            x        = x,
            y        = y,
        })
        data._saving = false
        -- A client drag is the one geometry the layout engine did not write, so the root's
        -- anchor descriptor is now stale. Restate it, or the next root re-layout snaps the
        -- frame back to where the player dragged it from.
        M:_applyAnchor(frame, { point = point, relPoint = relPoint, x = x, y = y })
    end)

    -- Edit mode drives the overlay. `immediate` matters: a frame created while edit
    -- mode is already on must show its overlay at once, not wait for the next toggle.
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
    end, "moveable_pos_" .. pluginId .. "_" .. key, { immediate = true })
end

--- Pushes a stored position into the root's anchor descriptor.
-- The single place a moveable frame's placement is stated. It goes through UIRoot so the
-- offsets are resolved by AnchorLayout against the root container — the addon's own scaled
-- unit space — rather than against UIParent, which is a different space the moment the
-- pixel multiplier is not 1.
--
-- `pos` describes the frame's own CONTENT. A frame carrying attach bands is bigger than
-- that, so the offset handed to the anchor strategy is shifted by the band on the anchored
-- edge — which is what keeps the content still while a band grows outward.
-- @param frame frame
-- @param pos table  { point, relPoint, x, y }
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
    -- Not a root element (a bare frame in a spec, or a plugin that places itself). Hand the
    -- descriptor to the anchor strategy directly against the frame's own parent, which is
    -- still the right unit space — never UIParent.
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
--
-- For a frame whose coreInset has changed without its position changing: a cast bar
-- attaching, detaching, or moving between the above and below slot alters how far the
-- frame extends past its own content, and the anchor offset has to follow or the content
-- shifts by that band's height. Nothing is written to Settings — the stored position is
-- still correct, it is only the derived offset that is stale.
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

    if data.contentBox then data.contentBox:Destroy() end
    if data.overlayBox then data.overlayBox:Destroy() end
    if frame._suuui_placeBox then
        frame._suuui_placeBox:Destroy()
        frame._suuui_placeBox = nil
    end

    frame._suuui_moveable = nil
end

SuuUI.MoveableFrame = M
