local M = {}

local root = nil
local rootContainer = nil
local layers = {}

-- The z-order ladder, in order. Plugin content sits at `normal` — that is also the root's
-- own strata, so a plugin frame parented to the root inherits it without asking. Windows
-- get their own rung ABOVE it: a window is chrome the player opened, so it must cover the
-- unit frames and bars it is used to configure, and frame level cannot be relied on for
-- that (a frame nested one level deeper than the window outranks it inside a shared
-- strata, which is exactly how the player frame ended up drawn over the settings window).
-- `dialog` in turn outranks a window so a modal or popup opened FROM a window lands on top.
local LAYER_STRATA = {
    background = "LOW",
    normal     = "MEDIUM",
    window     = "HIGH",
    dialog     = "DIALOG",
    tooltip    = "TOOLTIP",
}

--- Initializes the global UI root that holds all SuuUI elements.
-- Called once during addon initialization.
function M:Init()
    if root then return end  -- Already initialized
    
    -- Create the root frame that covers the entire screen
    root = CreateFrame("Frame", "SuuUI_UIRoot", UIParent)
    root:SetAllPoints(UIParent)
    -- The root sits on the `normal` rung, which is what makes plain frames parented to it
    -- (a plugin's unit frame, say) inherit the content rung without asking. Windows and
    -- dialogs are raised off it explicitly through their own layers.
    M:SetLayer(root, "normal")

    -- The single place a scale is set. Driving it here rather than on UIParent keeps the
    -- pixel grid ours: Blizzard frames and other addons are left where they were, and
    -- the 0.64 floor on the uiScale CVar does not apply to a frame scale.
    SuuUI.Pixel:Attach(root)
    
    -- Create root container using anchor layout for absolute positioning
    rootContainer = SuuUI.Layout:CreateContainer({
        parent  = root,
        layout  = "anchor",
        fill    = true,
        padding = {top=0, right=0, bottom=0, left=0},
    })

    -- Initialize layers for different UI element types. Derived from the strata ladder so
    -- a new rung cannot be added in one place and forgotten in the other.
    layers = {}
    for layer in pairs(LAYER_STRATA) do layers[layer] = {} end
    
    SuuUI.Debug("UI Root initialized")
end

--- Returns the frame strata a layer maps to. Readable before Init(), so a frame that has
--- to set its own strata (a window created before the root exists) can still agree with
--- the ladder instead of hardcoding a guess.
-- @param layer string
-- @return string|nil
function M:GetLayerStrata(layer)
    return LAYER_STRATA[layer or "normal"]
end

--- Puts an element on a layer WITHOUT taking over its placement.
--
-- The z-order half of AddElement, for the frames the root does not position: a plugin
-- frame the player drags around, a modal that fills its parent, a dropdown panel anchored
-- to its own field. Callers name a layer and never touch the client's strata themselves,
-- so the ladder stays the single place z-order is decided and the rest of the library
-- stays free of raw strata strings.
--
-- Usable before Init() — it only reads the ladder, it does not need the root frame.
-- @param element frame
-- @param layer string  Layer name: "background", "normal", "window", "dialog", "tooltip"
-- @return string  The strata applied
function M:SetLayer(element, layer)
    assert(element, "SuuUI UIRoot: element required")
    layer = layer or "normal"
    local strata = LAYER_STRATA[layer]
    assert(strata, "SuuUI UIRoot: invalid layer: " .. tostring(layer))
    element:SetFrameStrata(strata)
    element._suuui_layer = layer
    return strata
end

--- Returns the layer an element was assigned, or nil if it was never given one.
-- @param element frame
-- @return string|nil
function M:GetLayer(element)
    return element and element._suuui_layer or nil
end

--- Keeps an element on its host's layer but draws it above the host.
--
-- For decoration that belongs TO a frame — an edit-mode overlay, a close button, a resize
-- grip. Ordering inside a layer is a frame-level concern, so raising a layer here would be
-- wrong: an overlay promoted to `dialog` would cover the settings window that owns the
-- toggle for it. Same rung, higher level.
-- @param element frame
-- @param host frame   The frame to stay above
-- @param steps number|nil  Levels to rise (default 1)
function M:RaiseAbove(element, host, steps)
    assert(element, "SuuUI UIRoot: element required")
    assert(host, "SuuUI UIRoot: host required")
    local hostLayer = M:GetLayer(host)
    if hostLayer then M:SetLayer(element, hostLayer) end
    element:SetFrameLevel((host:GetFrameLevel() or 0) + (steps or 1))
end

--- Adds a UI element to the root at a specific layer.
-- @param element frame  The frame to add
-- @param layer string   Layer name: "background", "normal", "window", "dialog", "tooltip"
-- @param anchorDesc table  Anchor descriptor: { point, x, y, width, height }
--   point: "TOPLEFT", "CENTER", etc.
--   x, y: offset from anchor point
--   width, height: optional size (if not set, uses element's size)
function M:AddElement(element, layer, anchorDesc)
    assert(root, "SuuUI UIRoot: Init() must be called before AddElement()")
    assert(element, "SuuUI UIRoot: element required")
    layer = layer or "normal"
    assert(layers[layer], "SuuUI UIRoot: invalid layer: " .. tostring(layer))
    
    -- The layer owns the z-order: this OVERWRITES any strata the element set for itself,
    -- so a caller that wants to sit higher asks for a higher layer, not a raw strata.
    M:SetLayer(element, layer)
    
    -- Store anchor descriptor on the element
    element._suuui_anchor = anchorDesc or {
        point = "CENTER",
        x = 0,
        y = 0,
    }
    
    -- Add to layer tracking
    table.insert(layers[layer], element)
    
    -- Add to root container. AnchorLayout reads the descriptor from _layoutProps.
    rootContainer:Add(element, { anchor = element._suuui_anchor })
end

--- Removes a UI element from the root.
-- @param element frame
function M:RemoveElement(element)
    if not element then return end
    
    -- Remove from layer tracking
    for layerName, layerElements in pairs(layers) do
        for i = #layerElements, 1, -1 do
            if layerElements[i] == element then
                table.remove(layerElements, i)
                break
            end
        end
    end
    
    -- Remove from container
    rootContainer:Remove(element)
end

--- Updates the anchor position of an element.
-- @param element frame
-- @param anchorDesc table  New anchor descriptor
function M:UpdateElementAnchor(element, anchorDesc)
    if not element or not anchorDesc then return end

    element._suuui_anchor = anchorDesc
    -- AnchorLayout resolves from _layoutProps.anchor, so keep both in step
    if element._layoutProps then
        element._layoutProps.anchor = anchorDesc
    else
        element._layoutProps = { anchor = anchorDesc }
    end

    rootContainer:Layout()
end

--- Returns the root frame.
-- @return frame
function M:GetRoot()
    return root
end

--- Returns the root container.
-- @return table
function M:GetRootContainer()
    return rootContainer
end

--- Returns all elements in a specific layer.
-- @param layer string
-- @return table
function M:GetLayerElements(layer)
    return layers[layer] or {}
end

SuuUI.UIRoot = M
