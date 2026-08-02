local ipairs = ipairs

local M = {}

local activeContainers = {}  -- track containers per contentFrame for cleanup

--- Builds the settings page for pluginId into contentFrame.
-- Clears existing children first. Uses schema order for render order.
-- @param pluginId string
-- @param contentFrame frame  Inner frame of a ScrollFrame content area
-- @param scrollHeight number  Visible height of the scroll area (optional)
function M:Build(pluginId, contentFrame, scrollHeight)
    -- clean up previous container
    local containerId = tostring(contentFrame)
    if activeContainers[containerId] then
        local children = activeContainers[containerId]._children
        for _, child in ipairs(children) do child:Hide() end
    end

    local schema = SuuUI.Settings:GetSchema(pluginId)
    if not schema then return end

    local T   = SuuUI.Theme
    local gap = T:GetToken("spaceSm") or 4
    local pad = T:GetToken("spaceMd") or 8

    -- Create container for proper layout
    local container = SuuUI.Layout:CreateContainer({
        parent     = contentFrame,
        layout     = "flow",
        dir        = "vertical",
        gap        = gap,
        fillWidth  = true,  -- Fill parent width automatically
        padding = {
            top    = pad,
            right  = pad,
            bottom = pad,
            left   = pad,
        },
    })
    -- Root container inside ScrollFrame needs minimal positioning (exception to no-SetPoint rule)
    container:GetFrame():SetPoint("TOPLEFT", contentFrame, "TOPLEFT", 0, 0)
    activeContainers[containerId] = container

    for _, entry in ipairs(schema) do
        local builder = SuuUI._SettingsControls and SuuUI._SettingsControls[entry.type]
        if builder then
            local row
            if entry.type == "section" or entry.type == "profile_manager" or entry.type == "theme_manager" then
                row = builder(entry, contentFrame)
            else
                row = builder(entry, pluginId, contentFrame)
            end
            if row then
                -- Use row's natural height instead of fixed ROW_HEIGHTS
                local height = row:GetHeight()
                -- Add with fill width to use all available space
                container:Add(row, { width = "fill", height = height })
            end
        else
            SuuUI.Debug("PageBuilder: no control for type: " .. tostring(entry.type))
        end
    end

    -- Resize content frame AND container so scroll works correctly
    local _, contentHeight = container:GetContentSize()
    container:GetFrame():SetHeight(contentHeight)
    -- Content frame should be at least as tall as the scroll area to fill visible space
    local minHeight = scrollHeight or contentHeight
    local finalHeight = math.max(contentHeight, minHeight)
    contentFrame:SetHeight(finalHeight)
end

SuuUI._PageBuilder = M
