-- Framerate readout for the data bar.
--
-- Nothing fires an event when the frame rate changes, so this is the `update` case the widget
-- contract exists for. It is the second ticking widget on the bar and runs at a different
-- interval from the clock, which is what actually exercises the shared ticker's per-record
-- accumulator rather than a single entry that can never disagree with the loop.
local floor, type, tostring = math.floor, type, tostring

SuuUI._Performance = SuuUI._Performance or {}

local PLUGIN_ID = "performance"
local WIDGET_ID = "performance.fps"
local OWNER     = "performance.fps"

local M = { ID = WIDGET_ID }

local lastValue, lastText, lastTone

-- Guarded for existence like every other client global this addon reads, and for NaN: a
-- framerate is a number the client computes, and `v ~= v` is the only test that catches a
-- non-finite one — every comparison against NaN is false, so a range check alone lets it past.
local function reading()
    if type(GetFramerate) ~= "function" then return nil end
    local f = GetFramerate()
    if type(f) ~= "number" or f ~= f then return nil end
    if f < 0 then return nil end
    return floor(f)
end

local function toneFor(v)
    local danger = SuuUI.Settings:Get(PLUGIN_ID, "fps_danger")
    local warn   = SuuUI.Settings:Get(PLUGIN_ID, "fps_warn")
    if type(danger) == "number" and v <= danger then return "danger" end
    if type(warn) == "number" and v <= warn then return "warning" end
    return "success"
end

-- Formatted only when the displayed integer or its tone actually moves, per the performance
-- rule: this is called from a shared ticker, so the common tick must allocate nothing. The
-- TONE is part of the comparison rather than derived separately, which is what makes a
-- threshold slider repaint on the next tick instead of waiting for the framerate to change.
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
    label   = "Framerate",
    prefix  = "FPS",
    section = "right",
    order   = 210,
    update  = 1,
    GetText = function() return currentText() end,
}

--- The widget's settings, rendered on the Performance page.
--
-- The thresholds are settings rather than constants because "bad" is not a fact about the
-- client: a player on a laptop and a player on a desktop disagree about what 40 fps means, and
-- a fixed threshold would paint one of them permanently red.
-- @return table
function M.Schema()
    return {
        { key = "", label = "Framerate", type = "section" },
        { key = "fps_enabled", label = "Show Framerate", type = "toggle", default = true },
        { key = "fps_warn", label = "Warn Below", type = "slider", default = 50,
          min = 15, max = 120, step = 1, enabledIf = "fps_enabled" },
        { key = "fps_danger", label = "Danger Below", type = "slider", default = 30,
          min = 5, max = 100, step = 1, enabledIf = "fps_enabled" },
    }
end

--- Registers the widget and keeps it in step with its enable toggle.
function M.Enable()
    SuuUI.Settings:Watch(PLUGIN_ID, "fps_enabled", function(on)
        if on then
            SuuUI.DataBar:RegisterWidget(def)
        else
            SuuUI.DataBar:UnregisterWidget(WIDGET_ID)
        end
    end, OWNER, { immediate = true })
end

--- Drops the widget and its watcher.
function M.Disable()
    SuuUI.Settings:Unwatch(OWNER)
    SuuUI.DataBar:UnregisterWidget(WIDGET_ID)
    lastValue, lastText, lastTone = nil, nil, nil
end

SuuUI._Performance.FpsWidget = M
