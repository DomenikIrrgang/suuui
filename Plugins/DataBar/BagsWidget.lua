-- The bag field — Phase 9.
--
-- Blizzard's bag bar is six buttons: a backpack, four bag slots and a keyring. SuuUI replaces the whole
-- row with ONE field reading "BAGS 27", because the buttons' only jobs are opening the bags and showing
-- what is in them, and a free-slot count does the second better than five icons do. Clicking does the
-- first.
--
-- A BUILT-IN WIDGET, not a plugin of its own, and that is a correctness decision rather than tidiness.
-- Its first version was a separate `bag_bar` plugin, which put its settings on their own page instead of
-- with every other field's, and broke its own enable toggle: the plugin registered the toggle's watcher
-- under its owner prefix and then called `UnwatchPrefix` on that same prefix when disabled, destroying
-- the watcher that would have switched it back on. A built-in widget cannot make that mistake -- its
-- toggle is an ordinary setting inside the data bar's own schema, and the plugin re-runs `Enable` for it.
local type, tostring, ipairs = type, tostring, ipairs

SuuUI._DataBar = SuuUI._DataBar or {}

local PLUGIN_ID = "data_bar"
local WIDGET_ID = "databar.bags"
local OWNER     = "databar.bags"

local M = { ID = WIDGET_ID }

-- Blizzard's own count when the constant is missing: the backpack plus four bag slots.
local FALLBACK_BAG_SLOTS = 4

local function get(k, fallback)
    local v = SuuUI.Settings:Get(PLUGIN_ID, k)
    if v == nil then return fallback end
    return v
end

---------------------------------------------------------------------------
-- Reading the bags
---------------------------------------------------------------------------

--- The container API, whichever of the two shapes this client has.
--
-- THE SAME TRAP THE REPUTATION BAR FELL INTO, on this same client. The modern backend moved these onto
-- `C_Container` and may not carry the bare globals at all -- ElvUI dereferences
-- `C_Container.GetContainerNumFreeSlots` at file scope with no nil guard and works here, which is how we
-- know the namespace exists. Reading only the globals would have produced a silently empty field.
--
-- Bare `C_Container`, not `_G.C_Container`, so it resolves through the chunk environment -- the real
-- globals in game, the harness's table under test.
-- @return function|nil freeFn, function|nil slotsFn
local function containerApi()
    local C = C_Container
    if C and type(C.GetContainerNumFreeSlots) == "function" then
        return C.GetContainerNumFreeSlots, C.GetContainerNumSlots
    end
    if type(GetContainerNumFreeSlots) == "function" then
        return GetContainerNumFreeSlots, GetContainerNumSlots
    end
    return nil, nil
end

--- Free and total GENERAL-PURPOSE slots across the backpack and bag slots.
--
-- SPECIALISED BAGS ARE EXCLUDED, and on this client that is not a nicety: TBC has quivers, ammo pouches
-- and soul shard bags, whose free slots cannot hold loot. Counting them would tell a hunter with an empty
-- quiver that they have room for twenty more items when they have none. `GetContainerNumFreeSlots`
-- returns the bag's type as its second value, and a type of 0 (or absent) means general-purpose -- the
-- same test ElvUI applies.
-- @return number|nil free, number|nil total  nil when the client exposes no container API
local function readBags()
    local freeFn, slotsFn = containerApi()
    if not freeFn or not slotsFn then return nil end

    local free, total = 0, 0
    local last = type(NUM_BAG_SLOTS) == "number" and NUM_BAG_SLOTS or FALLBACK_BAG_SLOTS
    for bag = 0, last do
        local f, bagType = freeFn(bag)
        if (not bagType or bagType == 0) and type(f) == "number" then
            free = free + f
            total = total + (slotsFn(bag) or 0)
        end
    end
    return free, total
end

---------------------------------------------------------------------------
-- What the field says
---------------------------------------------------------------------------

--- The tone for a free-slot count, from the player's own thresholds.
--
-- Tones rather than colours, because the contract says a widget reports what the reading MEANS and the
-- theme decides how that looks -- a widget picking a hue would survive a retint and then be wrong.
--
-- Compared against FREE SLOTS rather than a percentage: "four slots left" is the same problem whether
-- the character has one bag or five, and a percentage would call a nearly-full 100-slot inventory fine.
local function toneFor(free)
    if free <= get("bags_danger_at", 0) then return "danger" end
    if free <= get("bags_warn_at", 5) then return "warning" end
    return nil
end

--- @return string text, string|nil tone
local function currentText()
    local free, total = readBags()
    if not free then
        -- A missing API is a FAULT, not an empty field. "No container API" and "no free slots" would
        -- otherwise render identically -- the conflation that hid the reputation bar for a whole round.
        SuuUI.Fault("DataBar bags: no container API on this client "
            .. "(neither C_Container.GetContainerNumFreeSlots nor GetContainerNumFreeSlots)")
        return "", nil
    end

    if get("bags_show_total", false) then
        return tostring(free) .. " / " .. tostring(total), toneFor(free)
    end
    return tostring(free), toneFor(free)
end

--- Opens the bags.
--
-- `ToggleAllBags` is the client's own toggle and it exists here -- ElvUI secure-hooks that exact global
-- on this build, which it could not do if the function were absent. Guarded anyway, and loudly: a dead
-- click with no explanation is the worst of the three outcomes.
local function onClick()
    if type(ToggleAllBags) == "function" then ToggleAllBags() return end
    -- Fallbacks in descending order of confidence, for a build that spells it differently.
    if type(OpenAllBags) == "function" then OpenAllBags() return end
    if type(ToggleBackpack) == "function" then ToggleBackpack() return end
    SuuUI.Fault("DataBar bags: no way to open the bags on this client "
        .. "(tried ToggleAllBags, OpenAllBags, ToggleBackpack)")
end

local def = {
    id      = WIDGET_ID,
    label   = "Bags",
    prefix  = "BAGS",
    section = "right",
    -- First in the right section (addon buttons 190, latency 200, fps 210), so the gameplay reading sits
    -- nearest the centre and the diagnostics keep the far edge.
    order   = 180,
    -- BAG_UPDATE_DELAYED is the one that matters: BAG_UPDATE fires per container and would rebuild the
    -- string five times for one loot. PLAYER_ENTERING_WORLD is here because nothing else announces the
    -- bags a character logs in with.
    events  = { "BAG_UPDATE_DELAYED", "PLAYER_ENTERING_WORLD" },
    GetText = function() return currentText() end,
    OnClick = function() onClick() end,
}

---------------------------------------------------------------------------
-- Settings
---------------------------------------------------------------------------

--- The widget's settings, rendered on the data bar's page with every other field's.
-- @return table
function M.Schema()
    return {
        { key = "", label = "Bags", type = "section" },
        { key = "bags_enabled", label = "Show Free Bag Slots", type = "toggle", default = true },
        -- Off by default: "27" is the reading a player acts on, and "27 / 80" spends width on a number
        -- that only moves when bags themselves change.
        { key = "bags_show_total", label = "Show Total Slots", type = "toggle", default = false,
          enabledIf = "bags_enabled" },
        -- Thresholds on FREE slots. The defaults say "warn me with five left, shout at zero".
        { key = "bags_warn_at", label = "Warn At Free Slots", type = "slider", default = 5,
          min = 0, max = 40, step = 1, enabledIf = "bags_enabled" },
        { key = "bags_danger_at", label = "Danger At Free Slots", type = "slider", default = 0,
          min = 0, max = 40, step = 1, enabledIf = "bags_enabled",
          -- Danger must not sit above warning, or the warning band vanishes and the field jumps straight
          -- from fine to danger with nothing in between.
          validate = function(v)
              return type(v) ~= "number" or v <= get("bags_warn_at", 5)
          end },
    }
end

--- Registers the widget and keeps it in step with its settings.
function M.Enable()
    SuuUI.Settings:Watch(PLUGIN_ID, "bags_enabled", function(on)
        if on then
            SuuUI.DataBar:RegisterWidget(def)
        else
            SuuUI.DataBar:UnregisterWidget(WIDGET_ID)
        end
    end, OWNER .. ".enabled", { immediate = true })

    -- Re-registered on a display or threshold change, because the same count can mean something
    -- different afterwards and no bag event will fire to prompt a repaint. Re-registering is the
    -- available refresh: the registry has no per-widget refresh call, and RegisterWidget overwrites by
    -- id and notifies the renderer, exactly as AttachPoints:Publish does.
    for _, k in ipairs({ "bags_show_total", "bags_warn_at", "bags_danger_at" }) do
        SuuUI.Settings:Watch(PLUGIN_ID, k, function()
            if SuuUI.DataBar:Has(WIDGET_ID) then SuuUI.DataBar:RegisterWidget(def) end
        end, OWNER .. "." .. k)
    end
end

--- Drops the widget and its watchers.
--
-- UnwatchPrefix over the widget's own owner prefix is safe HERE, unlike in the plugin this started as:
-- the data bar re-runs Enable when it comes back, so the enable watcher is rebuilt. A plugin dropping
-- its own enable watcher has nothing to rebuild it.
function M.Disable()
    SuuUI.Settings:UnwatchPrefix(OWNER .. ".")
    SuuUI.DataBar:UnregisterWidget(WIDGET_ID)
end

SuuUI._DataBar.BagsWidget = M

-- Kept for the spec, which asserts the reading rules directly rather than through the rendered field.
SuuUI._BagBar = {
    readBags = readBags,
    toneFor  = toneFor,
    GetText  = currentText,
    OnClick  = onClick,
}
