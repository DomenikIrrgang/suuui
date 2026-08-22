local ipairs = ipairs
local S = SuuUI.UISignals

local M = {}

local pages      = {}   -- [contentFrame] = container handle
local pageOwners = {}   -- [contentFrame] = watcher owner prefix of the page built there
local pageConns  = {}   -- [contentFrame] = conn id on the SCROLL handle, which outlives the page
local pageGroups = {}   -- [contentFrame] = AccordionGroup of the page built there

-- Which accordion is open, per page or subtab pane, keyed by the caller's memoKey and
-- held by LABEL. Session UI state, not a preference: the same call SubTabs makes for the
-- open tab, so navigating away and back returns you to the group you were reading, and
-- nothing about it is written to the profile.
local lastOpen = {}

local coreTypes = {
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
--
-- A `section` entry is not a row. It opens an Accordion, and every entry after it is built
-- into that accordion's body until the next section — so grouping is derived from the
-- schema the plugins already declare, and no plugin had to be edited to gain it. Entries
-- BEFORE the first section stay on the page itself, which is where a plugin-level toggle
-- belongs: it is not part of any group.
--
-- Shared by the page and by any grouping control (subtabs) that renders a slice of schema,
-- so there is one definition of how a schema entry becomes a row — and one definition of
-- how a section becomes a group. Each call gets its OWN AccordionGroup: which group is open
-- in the Player tab has nothing to say about the Target tab.
-- @param schemaArray table  Entries to build
-- @param pluginId string
-- @param parentFrame frame  Frame the accordions are created inside
-- @param container table    Container handle the accordions and ungrouped rows are added to
-- @param opts table|nil     { memoKey = string } to remember the open group for the session
-- @return table|nil  The AccordionGroup, when the schema had any sections
function M:BuildEntries(schemaArray, pluginId, parentFrame, container, opts)
    local C = SuuUI.Components
    local group, accs = nil, {}
    -- Where rows are going right now: the page itself, or the current accordion's body.
    local target, targetFrame = container, parentFrame

    for _, entry in ipairs(schemaArray) do
        if entry.type == "section" then
            group = group or C.AccordionGroup()
            local acc = C.Accordion({ label = entry.label }, parentFrame)
            -- The handle, not its frame: the container connects to what it is handed, and
            -- only the handle re-emits the column's SIZE_CHANGED as the group grows.
            container:Add(acc, { width = "fill" })
            group:Add(acc)
            accs[#accs + 1] = acc
            target, targetFrame = acc:GetBody(), acc:GetBody():GetFrame()

        elseif not dataOnly[entry.type] then
            local builder = SuuUI._SettingsControls and SuuUI._SettingsControls[entry.type]
            if builder then
                local row = coreTypes[entry.type]
                    and builder(entry, targetFrame)
                    or  builder(entry, pluginId, targetFrame)
                if row then
                    -- No fixed height: rows hug their content so a font token change
                    -- re-flows the page instead of clipping inside a stale row height.
                    target:Add(row, { width = "fill" })
                end
            else
                SuuUI.Debug("PageBuilder: no control for type: " .. tostring(entry.type))
            end
        end
    end

    if group then
        local memoKey = opts and opts.memoKey
        local wanted  = memoKey and lastOpen[memoKey]
        local pick
        for _, acc in ipairs(accs) do
            if wanted and not pick and acc:GetLabel() == wanted then pick = acc end
        end
        -- Snapped, never animated: a page opening with one group already sliding down
        -- animates something the player did not ask for, and it would run during the
        -- login pass for a page they may never open.
        group:Open(pick or accs[1], { animate = false })

        if memoKey then
            S:Connect(group, C.ACCORDION_SIGNALS.OPEN_CHANGED, function(acc)
                lastOpen[memoKey] = acc and acc:GetLabel() or nil
            end)
        end
    end
    return group
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
        -- The group holds a click subscription per member and may have a transition in
        -- flight. Its members are destroyed by the page's own cascade; this retires the
        -- arbitration around them.
        if pageGroups[content] then
            pageGroups[content]:Destroy()
            pageGroups[content] = nil
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

    -- The page reports its own height; the scroll frame reacts to it. This is also what
    -- carries an accordion's reveal outward: the group grows, the page re-hugs, and the
    -- scrollbar re-ranges on every tick of the animation without anyone driving it.
    S:Connect(page, S.SIGNALS.SIZE_CHANGED, function(_, h)
        S:Emit(scroll, S.SIGNALS.CONTENT_RESIZED, h)
    end)

    -- Keep the page width in step with the scroll frame. Tracked, because this one lives on
    -- the scroll handle rather than the page and must be dropped when the page goes.
    pageConns[content] = S:Connect(scroll, S.SIGNALS.SIZE_CHANGED, function()
        if pages[content] ~= page then return end
        page:SetWidth(scroll:GetContentWidth())
    end)

    pageGroups[content] = self:BuildEntries(schema, pluginId, content, page,
                                           { memoKey = pluginId })

    local _, contentHeight = page:GetContentSize()
    S:Emit(scroll, S.SIGNALS.CONTENT_RESIZED, contentHeight)
end

SuuUI._PageBuilder = M
