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
-- Remaining time
---------------------------------------------------------------------------

--- How long something has left, spelled for a human: "2h", "30m", "45s", "0.4s".
--
-- HERE RATHER THAN IN A COMPONENT, for the reason Money below is here. It lived as a file-local
-- `formatDuration` in Components/AuraIcon.lua, whose own comment named the hazard correctly --
-- "every consumer of an aura remaining-time would write the same three-tier format otherwise" --
-- and then drew the boundary one step too small. A second SURFACE is the same hazard as a second
-- consumer, and an action button's cooldown countdown is that second surface: two readouts of "how
-- long until this is available again" sitting inches apart on screen must not spell it differently.
--
-- EVERY STEP FLOORS RATHER THAN ROUNDS, so a readout never shows time that has already gone.
-- @param seconds number
-- @return string  "" for a non-number or NaN, since this runs from a ticker
function M.Duration(seconds)
    if type(seconds) ~= "number" or seconds ~= seconds then return "" end
    if seconds >= 3600 then
        return format("%dh", floor(seconds / 3600))
    elseif seconds >= 60 then
        return format("%dm", floor(seconds / 60))
    elseif seconds >= 1 then
        return format("%ds", floor(seconds))
    end
    -- Below one second is the only band where a decimal carries information: the whole-second form
    -- would read "0s" for the entire final second. Floored rather than rounded, because "%.1f" on
    -- 0.99 prints "1.0s" -- contradicting the branch that chose it, and a glyph wider than anything
    -- else this formatter can produce.
    return format("%.1fs", floor(seconds * 10) / 10)
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

--- How long ago something was read, spelled for a human.
--
-- HERE RATHER THAN IN THE INVENTORY, for the reason Money is here: it is neither a game fact nor a
-- theme token but a PRESENTATION CHOICE the whole UI has to make the same way. The snapshot strip is
-- the first consumer; the account tooltip section and the ledger tab both show the same freshness and
-- must not disagree about how to say it.
--
-- COARSE ON PURPOSE. The question a freshness stamp answers is "should I trust this", and that is
-- answered by "3 weeks ago" exactly as well as by a timestamp -- while a precise one invites the
-- reader to believe the contents are precise too, which for a cached bag they are not. Anything under
-- a minute reads "just now" rather than counting seconds nobody acts on.
--
-- @param when number|nil  a unix time, or nil when the thing was never read
-- @param now number|nil   override for the current time; tests pass it, callers do not
-- @return string
function M.Age(when, now)
    if type(when) ~= "number" then return "never" end
    now = now or (time and time()) or when
    local secs = now - when
    if secs < 0 then secs = 0 end
    if secs < 60 then return "just now" end
    local mins = floor(secs / 60)
    if mins < 60 then return mins == 1 and "1 minute ago" or (mins .. " minutes ago") end
    local hours = floor(mins / 60)
    if hours < 24 then return hours == 1 and "1 hour ago" or (hours .. " hours ago") end
    local days = floor(hours / 24)
    if days < 7 then return days == 1 and "1 day ago" or (days .. " days ago") end
    local weeks = floor(days / 7)
    return weeks == 1 and "1 week ago" or (weeks .. " weeks ago")
end

--- The same freshness, in the narrowest form that still says it: "now", "14m", "3h", "2d", "1w".
---
--- A SECOND format rather than a parameter on Age, because the two answer in different places: Age
--- reads inside a sentence ("captured 3 minutes ago") while this one sits in a fixed right-hand
--- column beside a name, where "14 minutes ago" is wider than the name it belongs to and pushes the
--- list past the panel.
---
--- It lives HERE, next to Age, for the reason Age itself does: it is a presentation choice, and a
--- second compact form invented at a call site is how two surfaces end up disagreeing about how to
--- say the same thing. Same coarseness rule -- anything under a minute is "now", because a chat
--- roster is scanned rather than read.
-- @param when number|nil
-- @param now number|nil   override for the current time; tests pass it, callers do not
-- @return string
function M.AgeShort(when, now)
    if type(when) ~= "number" then return "" end
    now = now or (time and time()) or when
    local secs = now - when
    if secs < 0 then secs = 0 end
    if secs < 60 then return "now" end
    local mins = floor(secs / 60)
    if mins < 60 then return mins .. "m" end
    local hours = floor(mins / 60)
    if hours < 24 then return hours .. "h" end
    local days = floor(hours / 24)
    if days < 7 then return days .. "d" end
    return floor(days / 7) .. "w"
end

SuuUI.Readout = M
