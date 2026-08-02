local ipairs = ipairs
local S = SuuUI.UISignals

local M = {}

local pages = {}   -- [contentFrame] = container handle

local coreTypes = {
    section         = true,
    profile_manager = true,
    theme_manager   = true,
}

--- Builds the settings page for pluginId into a ScrollFrame's content area.
-- Emits CONTENT_RESIZED on the scroll handle so it can update its scrollbar.
-- @param pluginId string
-- @param scroll table  ScrollFrame handle that hosts the page
function M:Build(pluginId, scroll)
    local content = scroll:GetContent()

    -- Tear down the previous page for this content area
    local previous = pages[content]
    if previous then
        previous:Destroy()
        pages[content] = nil
    end

    local schema = SuuUI.Settings:GetSchema(pluginId)
    if not schema then return end

    local T   = SuuUI.Theme
    local gap = T:GetToken("spaceSm") or 4
    local pad = T:GetToken("spaceMd") or 8

    local page = SuuUI.Layout:CreateContainer({
        parent  = content,
        layout  = "flow",
        dir     = "vertical",
        gap     = gap,
        w       = scroll:GetContentWidth(),
        padding = { top = pad, right = pad, bottom = pad, left = pad },
    })
    pages[content] = page

    -- The page reports its own height; the scroll frame reacts to it
    S:Connect(page, S.SIGNALS.SIZE_CHANGED, function(_, h)
        S:Emit(scroll, S.SIGNALS.CONTENT_RESIZED, h)
    end)

    -- Keep the page width in step with the scroll frame
    S:Connect(scroll, S.SIGNALS.SIZE_CHANGED, function()
        page:SetWidth(scroll:GetContentWidth())
    end)

    for _, entry in ipairs(schema) do
        local builder = SuuUI._SettingsControls and SuuUI._SettingsControls[entry.type]
        if builder then
            local row = coreTypes[entry.type]
                and builder(entry, content)
                or  builder(entry, pluginId, content)
            if row then
                -- No fixed height: rows hug their content so a font token change
                -- re-flows the page instead of clipping inside a stale row height.
                page:Add(row, { width = "fill" })
            end
        else
            SuuUI.Debug("PageBuilder: no control for type: " .. tostring(entry.type))
        end
    end

    local _, contentHeight = page:GetContentSize()
    S:Emit(scroll, S.SIGNALS.CONTENT_RESIZED, contentHeight)
end

SuuUI._PageBuilder = M
