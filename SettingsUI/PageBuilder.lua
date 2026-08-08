local ipairs = ipairs
local S = SuuUI.UISignals

local M = {}

local pages      = {}   -- [contentFrame] = container handle
local pageOwners = {}   -- [contentFrame] = watcher owner prefix of the page built there
local pageConns  = {}   -- [contentFrame] = conn id on the SCROLL handle, which outlives the page

local coreTypes = {
    section         = true,
    profile_manager = true,
    theme_manager   = true,
}

-- Entries that carry a value but have no control: they exist so the key has a default
-- and a home in the profile. Listed rather than left to fall through, so the "no control
-- for type" warning below keeps meaning "this type is missing a builder".
local dataOnly = {
    internal = true,
    position = true,
}

--- Builds each schema entry into `container`, in order.
-- Shared by the page itself and by any grouping control (subtabs) that renders a slice
-- of schema, so there is one definition of how a schema entry becomes a row.
-- @param schemaArray table  Entries to build
-- @param pluginId string
-- @param parentFrame frame  Frame the rows are created inside
-- @param container table    Container handle the rows are added to
function M:BuildEntries(schemaArray, pluginId, parentFrame, container)
    for _, entry in ipairs(schemaArray) do
        if not dataOnly[entry.type] then
            local builder = SuuUI._SettingsControls and SuuUI._SettingsControls[entry.type]
            if builder then
                local row = coreTypes[entry.type]
                    and builder(entry, parentFrame)
                    or  builder(entry, pluginId, parentFrame)
                if row then
                    -- No fixed height: rows hug their content so a font token change
                    -- re-flows the page instead of clipping inside a stale row height.
                    container:Add(row, { width = "fill" })
                end
            else
                SuuUI.Debug("PageBuilder: no control for type: " .. tostring(entry.type))
            end
        end
    end
end

--- Builds the settings page for pluginId into a ScrollFrame's content area.
-- Emits CONTENT_RESIZED on the scroll handle so it can update its scrollbar.
-- @param pluginId string
-- @param scroll table  ScrollFrame handle that hosts the page
function M:Build(pluginId, scroll)
    local content = scroll:GetContent()

    -- Tear down the previous page for this content area. Its controls each registered a
    -- Settings watcher, and those must go with the widgets they drive — otherwise every
    -- nav switch leaves behind a subscriber holding a destroyed handle, which then fires
    -- on every write and every profile load.
    local previous = pages[content]
    if previous then
        if pageOwners[content] then
            SuuUI.Settings:UnwatchPrefix(pageOwners[content])
            pageOwners[content] = nil
        end
        -- The scroll frame outlives the page, so a listener registered on IT is not cleaned
        -- up by destroying the page. Left connected, every nav switch adds another callback
        -- that resizes the page it captured — a page that no longer exists.
        if pageConns[content] then
            S:Disconnect(scroll, S.SIGNALS.SIZE_CHANGED, pageConns[content])
            pageConns[content] = nil
        end
        previous:Destroy()
        pages[content] = nil
    end

    local schema = SuuUI.Settings:GetSchema(pluginId)
    if not schema then return end

    local T   = SuuUI.Theme
    local gap = T:GetToken("spaceXs") or 4
    local pad = T:GetToken("spaceSm") or 8

    local page = SuuUI.Layout:CreateContainer({
        parent  = content,
        layout  = "flow",
        dir     = "vertical",
        gap     = gap,
        w       = scroll:GetContentWidth(),
        padding = { top = pad, right = pad, bottom = pad, left = pad },
    })
    pages[content]      = page
    pageOwners[content] = SuuUI.Settings.ControlOwnerPrefix(pluginId)

    -- The page reports its own height; the scroll frame reacts to it
    S:Connect(page, S.SIGNALS.SIZE_CHANGED, function(_, h)
        S:Emit(scroll, S.SIGNALS.CONTENT_RESIZED, h)
    end)

    -- Keep the page width in step with the scroll frame. Tracked, because this one lives on
    -- the scroll handle rather than the page and must be dropped when the page goes.
    pageConns[content] = S:Connect(scroll, S.SIGNALS.SIZE_CHANGED, function()
        if pages[content] ~= page then return end
        page:SetWidth(scroll:GetContentWidth())
    end)

    self:BuildEntries(schema, pluginId, content, page)

    local _, contentHeight = page:GetContentSize()
    S:Emit(scroll, S.SIGNALS.CONTENT_RESIZED, contentHeight)
end

SuuUI._PageBuilder = M
