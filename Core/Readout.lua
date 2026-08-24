-- How a bar's value is SPELLED. Shared by every bar that carries a readout.
--
-- This is neither a game fact nor design language, which is why it is here rather than in
-- Core/Game.lua or the theme: "7620 / 15240" is a presentation choice, but it is a choice the
-- whole UI has to make the same way. A unit frame's health bar and a tooltip's health bar reading
-- the same numbers differently is the inconsistency this module exists to prevent -- and it very
-- nearly shipped, with the tooltip abbreviating to "7.6k / 15.2k" while the unit frame beside it
-- printed the exact figures.
--
-- It lived as a file-local BAR_TEXT in Plugins/UnitFrames/UnitFrame.lua, whose own comment named
-- the hazard exactly: "a second copy is the thing that drifts, and the two bars would end up
-- offering different formats after the first change to either." A second CONSUMER is the same
-- hazard, and a plugin may not reach into another plugin for it.
--
-- The component never sees any of this. A StatusBar takes plain strings, so what a number MEANS
-- stays with whoever owns the value -- these are just the agreed spellings.
local format, floor = string.format, math.floor

local M = {}

-- The slots a bar can carry a readout in, in screen order.
M.SLOTS = { "left", "center", "right" }

-- The only formats. The SETTING stores which one a slot uses rather than a format string: a
-- stored pattern would be a value nothing validates and a dropdown could not describe.
--
-- "none" is deliberately ABSENT rather than a no-op. An unresolved mode leaves no formatter, and
-- that nil is what CLEARS a slot -- so switching a readout off removes it instead of freezing it
-- at the last value it showed. A no-op function here would need its own branch at every caller.
M.FORMATS = {
    current_max = function(cur, mx) return format("%d / %d", cur, mx) end,
    current     = function(cur) return format("%d", cur) end,
    -- Floored, never rounded: a unit one hit from dead must not read 100%, and the moment a bar
    -- stops saying full is the whole reason to show a percentage.
    percent     = function(cur, mx)
        return format("%d%%", mx > 0 and floor(cur / mx * 100) or 0)
    end,
}

--- The formatter for a mode, or nil for a mode that clears the slot.
-- @param mode string|nil  "current_max" | "current" | "percent" | "none" | nil
-- @return function|nil
function M.Formatter(mode)
    if type(mode) ~= "string" then return nil end
    return M.FORMATS[mode]
end

--- Formats a pair through one mode. Returns nil when the mode clears the slot, which is what
--- callers hand straight to SetText.
-- @return string|nil
function M.Format(mode, cur, mx)
    local fmt = M.Formatter(mode)
    if not fmt then return nil end
    if type(cur) ~= "number" or type(mx) ~= "number" then return nil end
    return fmt(cur, mx)
end

--- Dropdown options for a readout slot, in a fixed order.
--
-- Built here so two pages cannot offer different labels for one mode, and so a mode added above
-- appears on every page at once rather than only the one somebody remembered to edit.
-- @return table  array of { value, label }
function M.Options()
    return {
        { value = "none",        label = "None" },
        { value = "current_max", label = "Current / Max" },
        { value = "current",     label = "Current" },
        { value = "percent",     label = "Percent" },
    }
end

SuuUI.Readout = M
