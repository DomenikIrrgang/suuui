-- Latency readout for the data bar, with a hover breakdown of home against world.
--
-- Polled on a slower interval than the framerate: the client only refreshes its network
-- statistics every few seconds, so asking every second would be work with nothing to show for
-- it. The two intervals side by side are what put the shared ticker's accumulator under load.
local floor, type, tostring, format = math.floor, type, tostring, string.format

SuuUI._DataBar = SuuUI._DataBar or {}

local PLUGIN_ID = "data_bar"
local WIDGET_ID = "databar.latency"
local OWNER     = "databar.latency"

local M = { ID = WIDGET_ID }

local tooltip
local lastValue, lastText, lastTone

-- Two client shapes, and this is the boundary the widget has to survive rather than assume.
-- The older API returns THREE values with a single latency in the third slot; the newer returns
-- FOUR, splitting home from world. World latency is the one that describes how the game feels,
-- so it is preferred where present and the single value is the fallback — reading the fourth
-- slot unconditionally would report nil on the older client, and reading only the third would
-- throw away the more useful number on the newer one.
local function readStats()
    if type(GetNetStats) ~= "function" then return nil end
    local down, up, home, world = GetNetStats()
    local function clean(v)
        if type(v) ~= "number" or v ~= v or v < 0 then return nil end
        return v
    end
    return clean(down), clean(up), clean(home), clean(world)
end

local function reading()
    local _, _, home, world = readStats()
    -- A world latency of 0 means "not measured", which is a different fact from a fast
    -- connection, so it falls through to home rather than rendering an implausible 0 ms.
    local ms = (world and world > 0) and world or home
    if not ms then return nil end
    return floor(ms)
end

local function toneFor(v)
    local danger = SuuUI.Settings:Get(PLUGIN_ID, "ms_danger")
    local warn   = SuuUI.Settings:Get(PLUGIN_ID, "ms_warn")
    if type(danger) == "number" and v >= danger then return "danger" end
    if type(warn) == "number" and v >= warn then return "warning" end
    return "success"
end

-- Same cache shape as the framerate widget: formatted only when the integer or its tone moves,
-- with the tone in the comparison so a threshold slider takes effect on the next tick.
local function currentText()
    local v = reading()
    if not v then return "—", nil end
    local tone = toneFor(v)
    if v ~= lastValue or tone ~= lastTone then
        lastValue, lastTone = v, tone
        lastText = tostring(v)
    end
    return lastText, lastTone
end

local def = {
    id      = WIDGET_ID,
    label   = "Latency",
    prefix  = "MS",
    section = "right",
    order   = 200,
    update  = 5,
    GetText = function() return currentText() end,

    -- The breakdown is the reason this field is worth hovering: home latency is the trip to
    -- the login/chat server and world latency the trip to the game server, so which of the two
    -- is high tells a player whether the problem is theirs or the realm's. The bar shows one
    -- number; the hover explains it.
    OnEnter = function(field)
        if not tooltip then
            tooltip = SuuUI.Components.Tooltip({}, SuuUI.UIRoot:GetRootContainer():GetFrame())
        end
        local down, up, home, world = readStats()
        local lines = {}
        if home  then lines[#lines + 1] = format("Home   %d ms", floor(home)) end
        if world and world > 0 then lines[#lines + 1] = format("World  %d ms", floor(world)) end
        if down or up then
            lines[#lines + 1] = format("Traffic  %.1f / %.1f KB/s", down or 0, up or 0)
        end
        if #lines == 0 then lines[1] = "No network data" end
        tooltip:ShowTip(table.concat(lines, "\n"), field:GetFrame())
    end,

    OnLeave = function()
        if tooltip then tooltip:HideTip() end
    end,
}

--- The widget's settings, rendered on the Performance page.
-- Thresholds are settings for the same reason the framerate's are: a player on a 200 ms
-- baseline should not sit permanently in red.
-- @return table
function M.Schema()
    return {
        { key = "", label = "Latency", type = "section" },
        { key = "ms_enabled", label = "Show Latency", type = "toggle", default = true },
        { key = "ms_warn", label = "Warn Above", type = "slider", default = 150,
          min = 50, max = 1000, step = 10, enabledIf = "ms_enabled" },
        { key = "ms_danger", label = "Danger Above", type = "slider", default = 300,
          min = 100, max = 2000, step = 10, enabledIf = "ms_enabled" },
    }
end

--- Registers the widget and keeps it in step with its enable toggle.
function M.Enable()
    SuuUI.Settings:Watch(PLUGIN_ID, "ms_enabled", function(on)
        if on then
            SuuUI.DataBar:RegisterWidget(def)
        else
            SuuUI.DataBar:UnregisterWidget(WIDGET_ID)
        end
    end, OWNER, { immediate = true })
end

--- Drops the widget, its watcher and its tooltip.
function M.Disable()
    SuuUI.Settings:Unwatch(OWNER)
    SuuUI.DataBar:UnregisterWidget(WIDGET_ID)
    if tooltip then
        tooltip:Destroy()
        tooltip = nil
    end
    lastValue, lastText, lastTone = nil, nil, nil
end

SuuUI._DataBar.LatencyWidget = M
