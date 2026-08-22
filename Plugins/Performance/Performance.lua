-- Performance plugin: framerate and latency readouts for the data bar.
--
-- The first plugin that contributes to the data bar WITHOUT owning it. The clock lives inside
-- the DataBar plugin, so until now the registry's whole reason for existing — a plugin adding a
-- field to a bar it knows nothing about — had never actually happened. Note what this file does
-- NOT contain: any reference to the data_bar plugin, its frame, or its load order. It registers
-- widgets into Core and stops.
--
-- Both readouts are polled rather than announced, so both declare an `update` interval and
-- neither registers a game event.
local ipairs = ipairs

local PLUGIN_ID = "performance"
local OWNER     = "performance"

local plugin = SuuUI:CreatePlugin({
    id      = "performance",
    name    = "Performance",
    version = "0.1",

    onInit = function(p)
        local schema = {
            { key = "enabled", label = "Enable Performance Widgets", type = "toggle",
              default = true },
        }
        -- Each widget declares its own settings and this file only splices the slices in, so a
        -- widget owns everything about itself including its section header. Registered under
        -- THIS plugin's id, on this plugin's page — a widget cannot hand a schema slice to the
        -- data bar's page, because Settings:Register has already run for that plugin by the
        -- time a widget registers.
        for _, entry in ipairs(SuuUI._Performance.FpsWidget.Schema()) do
            schema[#schema + 1] = entry
        end
        for _, entry in ipairs(SuuUI._Performance.LatencyWidget.Schema()) do
            schema[#schema + 1] = entry
        end
        SuuUI.Settings:Register(PLUGIN_ID, schema)

        -- No `immediate`: Plugins:autoEnable already applies the stored value during the login
        -- pass, and an immediate callback would run onEnable from inside the init pass, before
        -- other plugins' onInit had run. The widgets unregister cleanly, so this needs no
        -- reload guard.
        SuuUI.Settings:Watch(PLUGIN_ID, "enabled", function(on)
            if on then p:Enable() else p:Disable() end
        end, OWNER .. ".enabled")
    end,

    onEnable = function()
        SuuUI._Performance.FpsWidget.Enable()
        SuuUI._Performance.LatencyWidget.Enable()
    end,

    onDisable = function()
        SuuUI._Performance.FpsWidget.Disable()
        SuuUI._Performance.LatencyWidget.Disable()
    end,
})
