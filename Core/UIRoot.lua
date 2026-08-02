local M = {}

local root = nil
local rootContainer = nil
local layers = {}

--- Initializes the global UI root that holds all SuuUI elements.
-- Called once during addon initialization.
function M:Init()
    if root then return end  -- Already initialized
    
    -- Create the root frame that covers the entire screen
    root = CreateFrame("Frame", "SuuUI_UIRoot", UIParent)
    root:SetAllPoints(UIParent)
    root:SetFrameStrata("MEDIUM")
    
    -- Create root container using anchor layout for absolute positioning
    rootContainer = SuuUI.Layout:CreateContainer({
        parent  = root,
        layout  = "anchor",
        fill    = true,
        padding = {top=0, right=0, bottom=0, left=0},
    })

    -- Initialize layers for different UI element types
    layers = {
        background = {},  -- Background elements (lowest)
        normal     = {},  -- Normal windows and frames
        dialog     = {},  -- Modals and dialogs
        tooltip    = {},  -- Tooltips (highest)
    }
    
    SuuUI.Debug("UI Root initialized")
end

--- Adds a UI element to the root at a specific layer.
-- @param element frame  The frame to add
-- @param layer string   Layer name: "background", "normal", "dialog", "tooltip"
-- @param anchorDesc table  Anchor descriptor: { point, x, y, width, height }
--   point: "TOPLEFT", "CENTER", etc.
--   x, y: offset from anchor point
--   width, height: optional size (if not set, uses element's size)
function M:AddElement(element, layer, anchorDesc)
    assert(root, "SuuUI UIRoot: Init() must be called before AddElement()")
    assert(element, "SuuUI UIRoot: element required")
    layer = layer or "normal"
    assert(layers[layer], "SuuUI UIRoot: invalid layer: " .. tostring(layer))
    
    -- Set frame strata based on layer
    local strata = {
        background = "LOW",
        normal     = "MEDIUM",
        dialog     = "HIGH",
        tooltip    = "TOOLTIP",
    }
    element:SetFrameStrata(strata[layer])
    
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
