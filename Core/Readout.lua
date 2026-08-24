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
local type, ipairs = type, ipairs

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

---------------------------------------------------------------------------
-- Money
---------------------------------------------------------------------------

-- WHY MONEY LIVES HERE. I argued in Plugins/Inventory that it does not -- that Readout spells a
-- BAR's value while money is three units with fixed divisors rather than a fraction. That reasoning
-- was about the SHAPE of the value and it missed the point of this module, which is stated at the top
-- of architecture.md's entry for it: a presentation choice the whole UI has to make the same way, so
-- two surfaces cannot disagree. Money is exactly that, and the divergence had already happened --
-- Plugins/Tooltips/Content.lua and Plugins/Inventory/InventoryWindow.lua each grew their own
-- formatter, one dropping zero units and one always printing all three. The k/M abbreviation bug this
-- module exists to prevent is the same bug: a tooltip reading `7.6k` beside a bar reading `7620`.
--
-- DROPPING A LEADING ZERO UNIT IS RIGHT AND DROPPING A TRAILING ONE IS NOT, and the asymmetry is
-- load-bearing rather than tidy: "12g 0s 88c" is noise, but "12g 88c" and "12g 88s" are DIFFERENT
-- PRICES, so once a larger denomination is present every smaller one keeps its letter. That rule was
-- learned in the tooltip and is pinned by Tests/spec/51_tooltips_spec.lua; it is preserved verbatim
-- here rather than re-derived.
local COIN_UNITS = {
    { key = "GOLD",   div = 10000, suffix = "g" },
    { key = "SILVER", div = 100,   suffix = "s" },
    { key = "COPPER", div = 1,     suffix = "c" },
}

-- Stands in for an omitted opts table so the reads below need no nil guard, and so a footer refresh
-- allocates nothing. Never written to.
local EMPTY = {}

--- Splits copper into gold, silver and copper.
-- @param copper number
-- @return number, number, number
function M.MoneyParts(copper)
    if type(copper) ~= "number" or copper ~= copper or copper < 0 then return 0, 0, 0 end
    copper = floor(copper)
    return floor(copper / 10000), floor((copper % 10000) / 100), copper % 100
end

--- Groups a number with the client's own thousands separator.
--
-- LARGE_NUMBER_SEPERATOR is Blizzard's global (misspelled in the client, kept verbatim) and it is
-- locale-correct -- a German client separates with ".", so hardcoding "," would be wrong for exactly
-- the players least likely to report it. Bare global lookup, never _G, so the harness can stage it.
-- @param n number
-- @return string
function M.GroupNumber(n)
    if type(n) ~= "number" or n ~= n then return "0" end
    local sep = LARGE_NUMBER_SEPERATOR
    if type(sep) ~= "string" or sep == "" then sep = "," end
    local out = tostring(floor(n))
    -- Insert from the right in threes. The anchor requires a digit AFTER the group so the leading
    -- run is not itself separated, and the loop repeats because one pass only moves one group.
    local count
    repeat
        out, count = out:gsub("^(-?%d+)(%d%d%d)", "%1" .. sep .. "%2")
    until count == 0
    return out
end

--- Spells an amount of copper as gold/silver/copper.
--
-- @param copper number
-- @param opts table|nil
--   colored        wrap each UNIT LETTER in its coin colour. The LETTER only, not the figure: the
--                  amount is the reading and stays in the caller's own text colour, while the letter
--                  is the label saying which denomination it is. Colouring the whole segment paints
--                  the number gold too, which is louder than the concept and buries the figure.
--                  The colour is a GAME FACT from SuuUI.Game, not a theme token -- see CoinColorCode.
--   groupThousands "1,284" rather than "1284", via the client's own separator.
--   spaceUnits     "1,284 g" rather than "1,284g".
--
-- All three default OFF, so a caller that wants the dense inline form -- a vendor price inside a
-- tooltip line -- gets it without asking, and only a readout where the money IS the subject opts in.
-- @return string|nil  nil for a non-number or a negative amount, so a caller can omit the line
function M.Money(copper, opts)
    if type(copper) ~= "number" or copper ~= copper or copper < 0 then return nil end
    opts = opts or EMPTY
    local g, s, c = M.MoneyParts(copper)
    local amounts = { g, s, c }
    local out, started = {}, false
    for i, unit in ipairs(COIN_UNITS) do
        local amount = amounts[i]
        -- Copper is always emitted: a purse of 0 has to read as "0c" rather than as an empty string.
        if amount > 0 or started or i == #COIN_UNITS then
            started = true
            local figure = opts.groupThousands and M.GroupNumber(amount) or tostring(amount)
            local suffix = unit.suffix
            if opts.colored then
                local code = SuuUI.Game and SuuUI.Game:CoinColorCode(unit.key)
                -- Degrades to uncoloured rather than raising: this runs from a footer refresh, and a
                -- missing colour is worth less than a missing readout.
                if code then suffix = code .. suffix .. "|r" end
            end
            out[#out + 1] = figure .. (opts.spaceUnits and " " or "") .. suffix
        end
    end
    return table.concat(out, " ")
end

SuuUI.Readout = M
