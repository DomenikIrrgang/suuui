-- The clock: the one built-in data bar widget, and the reference for what a widget
-- definition looks like. It builds no frames and knows nothing about the bar's layout,
-- dividers, fonts or colours — it answers "what should this field say".
local date, time, floor, type = date, time, math.floor, type

SuuUI._DataBar = SuuUI._DataBar or {}

local PLUGIN_ID = "data_bar"
local WIDGET_ID = "databar.time"
local OWNER     = "databar.time"

local M = { ID = WIDGET_ID }

local tooltip
local lastKey, lastText

-- No prefix: "14:32" is self-evident, and a muted "TIME" in front of it would be noise.
-- The contract makes the prefix optional for exactly this reason.

local function fmt12()
    return SuuUI.Settings:Get(PLUGIN_ID, "time_format") == "12"
end

local function showSeconds()
    return SuuUI.Settings:Get(PLUGIN_ID, "time_seconds") == true
end

-- A number identifying the string that SHOULD be on screen right now.
--
-- The ticker asks twice a second so a seconds display stays smooth, but the string only
-- changes once a second at most and usually once a minute — so this is the cheap comparison
-- that decides whether to format at all. `time()` returns a number and allocates nothing,
-- where `date("*t")` would allocate a table on every tick.
--
-- Both settings are folded in so a format change repaints on the next tick rather than
-- waiting for the next minute boundary, which is what a cache keyed on the clock alone
-- would do.
local function displayKey(twelve, secs)
    local t = time() or 0
    if not secs then t = t - (t % 60) end
    return t * 4 + (secs and 2 or 0) + (twelve and 1 or 0)
end

local function build(twelve, secs)
    if twelve then
        -- %I is zero-padded, and a leading zero on a 12-hour clock reads as a 24-hour one.
        -- Parenthesised because gsub returns two values and the second would leak into
        -- whatever this feeds.
        return (date(secs and "%I:%M:%S %p" or "%I:%M %p"):gsub("^0", ""))
    end
    return date(secs and "%H:%M:%S" or "%H:%M")
end

-- Pre-built and cached rather than formatted per call, per the performance rule: the string
-- is rebuilt only when the value behind it actually moves.
local function currentText()
    local twelve, secs = fmt12(), showSeconds()
    local key = displayKey(twelve, secs)
    if key == lastKey and lastText then return lastText end
    lastKey  = key
    lastText = build(twelve, secs)
    return lastText
end

local function realmText()
    -- Guarded for EXISTENCE, not just for what it answers. Called unconditionally, an absent
    -- global raises inside the bar's pcall and the whole OnEnter is lost — so the player gets
    -- no tooltip at all rather than the local time it could still have shown.
    if type(GetGameTime) ~= "function" then return nil end
    local h, m = GetGameTime()
    if type(h) ~= "number" or type(m) ~= "number" then return nil end
    if fmt12() then
        local suffix = h >= 12 and "PM" or "AM"
        local hr = h % 12
        if hr == 0 then hr = 12 end
        return string.format("%d:%02d %s", hr, m, suffix)
    end
    return string.format("%02d:%02d", h, m)
end

local def = {
    id      = WIDGET_ID,
    label   = "Clock",
    section = "center",
    order   = 100,
    -- Nothing announces the passing of a second, so this is the clock case the `update` field
    -- exists for. Twice a second keeps a seconds display from visibly stuttering; the cache
    -- above means most of those ticks format nothing and the field drops the unchanged write.
    update  = 0.5,

    GetText = function()
        return currentText()
    end,

    OnEnter = function(field)
        if not tooltip then
            tooltip = SuuUI.Components.Tooltip({}, SuuUI.UIRoot:GetRootContainer():GetFrame())
        end
        -- Local time is on the bar, so the hover carries the one a player cannot read off it.
        local realm = realmText()
        local text = "Local  " .. currentText()
        if realm then text = text .. "\nRealm  " .. realm end
        tooltip:ShowTip(text, field:GetFrame())
    end,

    OnLeave = function()
        if tooltip then tooltip:HideTip() end
    end,
}

--- The clock's settings, rendered on the DataBar page.
-- Declared here rather than in the plugin so the widget owns everything about itself; the
-- plugin only splices the slice into its schema.
-- @return table
function M.Schema()
    return {
        { key = "", label = "Clock", type = "section" },
        { key = "time_enabled", label = "Show Clock", type = "toggle", default = true },
        { key = "time_format", label = "Format", type = "dropdown", default = "24",
          options = {
              { value = "24", label = "24-hour (14:32)" },
              { value = "12", label = "12-hour (2:32 PM)" },
          } },
        { key = "time_seconds", label = "Show Seconds", type = "toggle", default = false },
    }
end

--- Registers the widget and keeps it in step with its enable toggle.
-- Watched rather than read once, so switching the clock off removes the field immediately and
-- the registry's unregister path is the one the player actually exercises.
function M.Enable()
    SuuUI.Settings:Watch(PLUGIN_ID, "time_enabled", function(on)
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
    lastKey, lastText = nil, nil
end

SuuUI._DataBar.TimeWidget = M
