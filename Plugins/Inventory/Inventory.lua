-- The inventory plugin. Phase 5: one window over the player's live bags, opened by a slash
-- command. Blizzard's own bags are NOT suppressed yet -- that is Phase 6 -- deliberately, so this
-- window can be compared side by side with the default UI before it replaces it.
local type = type

local PLUGIN_ID = "inventory"
local W = SuuUI._InventoryWindow

local plugin
local bagsWindow

-- Every setting that changes the GRID's shape, and the applier for each. Kept as a table so a new
-- one is a row here rather than another watcher block -- and so nothing can be added to the schema
-- without a visible place for its watcher, which is the gap that once shipped a width slider that
-- did nothing until a reload.
local SHAPE = {
    columns   = function(g, v) g:SetColumns(v) end,
    cell_size = function(g, v) g:SetCellSize(v) end,
    sort_mode = function(g, v) g:SetSortMode(v) end,
}

local function window()
    if not bagsWindow then
        bagsWindow = W.New({ container = "bags" })
    end
    return bagsWindow
end

--- Opens the inventory window, building it on first use.
function SuuUI.Inventory_Open()
    window():Show()
end

--- Toggles it.
function SuuUI.Inventory_Toggle()
    window():Toggle()
end

local function teardown()
    if bagsWindow then
        bagsWindow:Destroy()
        bagsWindow = nil
    end
end

plugin = SuuUI:CreatePlugin({
    id      = "inventory",
    name    = "Inventory",
    version = "0.1",

    onInit = function(p)
        SuuUI.Settings:Register(PLUGIN_ID, {
            { key = "enabled", label = "Enable Inventory", type = "toggle", default = true },
            { key = "", label = "Layout", type = "section" },
            { key = "columns", label = "Columns", type = "slider",
              default = 10, min = 6, max = 20, step = 1 },
            { key = "cell_size", label = "Cell Size", type = "slider",
              default = 34, min = 24, max = 48, step = 1 },
            { key = "sort_mode", label = "Sort By", type = "dropdown",
              default = "quality", options = W.SORT_OPTIONS },
        })

        -- No `immediate` on the plugin's own enable watcher: Plugins:autoEnable already applies the
        -- stored value during the login pass, and an immediate callback would run onEnable from
        -- inside the init pass -- before other plugins' onInit had run.
        SuuUI.Settings:Watch(PLUGIN_ID, "enabled", function(on)
            if on then p:Enable() else p:Disable() end
        end, PLUGIN_ID)
    end,

    onEnable = function()
        -- LIVE APPLIERS rather than a rebuild. Rebuilding the window would drop its stored position
        -- and its registrations, so changing the column count would move the window as a side
        -- effect -- which is how the watch bars' width slider misbehaved.
        for key, apply in pairs(SHAPE) do
            SuuUI.Settings:Watch(PLUGIN_ID, key, function(value)
                if bagsWindow and value ~= nil then apply(bagsWindow:GetGrid(), value) end
            end, PLUGIN_ID .. ".shape")
        end
    end,

    onDisable = function()
        SuuUI.Settings:Unwatch(PLUGIN_ID .. ".shape")
        teardown()
    end,
})

-- Its OWN slash command rather than a `bags` case inside /suuui. That handler belongs to
-- SettingsWindow, and adding plugin knowledge to it would couple the two -- the same reason the
-- minimap button got a public API seam instead of calling SlashCmdList["SUUUI"]().
--
-- TEMPORARY: Phase 6 routes the B key here by replacing the client's own bag toggles, at which point
-- this stays only as a way in that does not depend on a keybind.
SLASH_SUUUIBAGS1 = "/sbags"
SLASH_SUUUIBAGS2 = "/suuuibags"
SlashCmdList["SUUUIBAGS"] = function()
    SuuUI.Inventory_Toggle()
end

SuuUI._InventoryPlugin = plugin
