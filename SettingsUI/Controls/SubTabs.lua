-- SubTabs control: a horizontal tab strip inside one plugin's settings page.
-- Each tab owns a slice of the plugin's schema and is built when it is selected, so a
-- plugin with many similar groups (one per unit frame) gets one page instead of one
-- enormous scroll.
--
-- Schema shape:
--   { key = "unit", type = "subtabs", tabs = {
--       { id = "player", label = "Player", schema = { ...entries... } },
--       { id = "target", label = "Target", schema = { ...entries... } },
--   }}
--
-- Settings declared inside a tab are indexed by Settings:Register like any other entry,
-- so each key is declared exactly once — in the tab it is rendered in.
local ipairs = ipairs
local C = SuuUI.Components
local S = SuuUI.UISignals

-- Which tab is open is UI state, not a preference. It is remembered per plugin for the
-- session so that navigating away and back returns to the tab you were on — the same
-- thing SettingsWindow does for the selected plugin — but it is deliberately not a
-- setting, so it is never written to the profile.
local lastActive = {}

--- Builds a subtabs control.
-- @param entry table    Schema entry { key, tabs }
-- @param pluginId string
-- @param parent frame
-- @return table  Container handle for the control
local function Build(entry, pluginId, parent)
    local T    = SuuUI.Theme
    local gap  = T:GetToken("spaceXs") or 4
    local tabH = T:GetControlHeight("sizeNavRow")

    local root = SuuUI.Layout:CreateContainer({
        parent = parent,
        layout = "flow",
        dir    = "vertical",
        gap    = gap,
    })

    local tabBar = SuuUI.Layout:CreateContainer({
        parent = root:GetFrame(),
        layout = "flow",
        dir    = "horizontal",
        gap    = gap,
    })
    root:Add(tabBar, { width = "fill", height = tabH })

    local tabs, byId = entry.tabs or {}, {}
    for _, tab in ipairs(tabs) do byId[tab.id] = tab end

    local buttons  = {}
    local pane     = nil   -- container holding the active tab's rows
    local activeId = nil

    --- Swaps the visible tab. The outgoing pane is destroyed and its subscriptions
    --- retired; the incoming one is a fresh container added to root, so root re-hugs.
    local function selectTab(id)
        local tabDef = byId[id]
        if not tabDef then return end

        if pane then
            -- The outgoing controls' watchers must go with the widgets they drive.
            -- Owner strings are derived from the schema, so the tab can retire exactly
            -- its own; left registered, they fire on every later write and every
            -- profile load holding a destroyed handle.
            local outgoing = byId[activeId]
            if outgoing then
                SuuUI.Settings:UnwatchControls(pluginId, outgoing.schema)
            end
            root:Remove(pane)
            pane:Destroy()
            pane = nil
        end

        activeId            = id
        lastActive[pluginId] = id
        for _, b in ipairs(buttons) do b.nav:SetSelected(b.id == id) end

        -- A container, not a bare frame. The page above only re-measures when its child
        -- reports SIZE_CHANGED, and a raw frame emits no signals — so a raw pane leaves
        -- the page sized for whichever tab happened to be open first, and a taller tab
        -- overflows it. A container hugs its rows and reports the change.
        pane = SuuUI.Layout:CreateContainer({
            parent = root:GetFrame(),
            layout = "flow",
            dir    = "vertical",
            gap    = gap,
        })
        SuuUI._PageBuilder:BuildEntries(tabDef.schema, pluginId, pane:GetFrame(), pane)
        root:Add(pane, { width = "fill" })
    end

    for _, tabDef in ipairs(tabs) do
        -- autoW: a tab hugs its label. At the nav's fixed width every tab would be as
        -- wide as the widest nav row, and a strip of unit names would run off the page.
        local nav = C.NavItem({ label = tabDef.label, h = tabH, autoW = true },
                              tabBar:GetFrame())
        tabBar:Add(nav, { height = tabH })

        local id = tabDef.id
        S:Connect(nav, S.SIGNALS.CLICKED, function()
            if activeId ~= id then selectTab(id) end
        end)
        buttons[#buttons + 1] = { id = id, nav = nav }
    end

    if #tabs > 0 then
        local remembered = lastActive[pluginId]
        selectTab(byId[remembered] and remembered or tabs[1].id)
    end

    --- Returns the id of the open tab.
    -- @return string|nil
    function root:GetActiveTab() return activeId end

    --- Opens a tab by id. No-op for an unknown id.
    -- @param id string
    function root:SetActiveTab(id)
        if id ~= activeId then selectTab(id) end
    end

    --- Returns the tab buttons in declaration order.
    -- @return table  Array of { id, nav }
    function root:GetTabButtons() return buttons end

    --- Returns the container holding the open tab's rows.
    -- @return table|nil
    function root:GetActivePane() return pane end

    return root
end

if not SuuUI._SettingsControls then SuuUI._SettingsControls = {} end
SuuUI._SettingsControls["subtabs"] = Build
