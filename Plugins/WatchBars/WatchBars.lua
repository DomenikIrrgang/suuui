-- The two watch bars: experience and the watched faction's reputation.
--
-- ONE WIDGET SHAPE, TWO INSTANCES. Rested experience and the reputation standing are the only
-- differences that reach the component, which is why `StatusBar` grew a secondary fill rather than
-- this plugin stacking a second bar of its own.
--
-- BOTH HIDE WHEN THEY HAVE NOTHING TO SAY, and the conditions are NOT the same shape:
--   * Experience: max level, OR experience switched off (a trial account). Two separate reasons, and a
--     bar that only checked the level would still show for the second.
--   * Reputation: nothing watched. `GetWatchedFactionInfo()` answers nil, which is the whole test.
--
-- Hiding is a plain Show/Hide, not a state driver: neither bar holds a protected button, so there is
-- nothing the client would refuse mid-combat. That is the difference from the pet bar.
local ipairs, type, math = ipairs, type, math

local PLUGIN_ID = "watch_bars"
local OWNER     = "watch_bars"

local BARS = {
    {
        id = "xp", label = "Experience", order = 10,
        position = { point = "BOTTOM", relPoint = "BOTTOM", x = 0, y = 8 },
    },
    {
        id = "rep", label = "Reputation", order = 20,
        position = { point = "BOTTOM", relPoint = "BOTTOM", x = 0, y = 20 },
    },
}

local function key(def, name)
    return def.id .. "_" .. name
end

local function get(k, fallback)
    local v = SuuUI.Settings:Get(PLUGIN_ID, k)
    if v == nil then return fallback end
    return v
end

---------------------------------------------------------------------------
-- Readings
---------------------------------------------------------------------------

--- The experience reading, or nil when the bar has nothing to say.
-- @return table|nil  { value, max, rested }
local function readXP()
    if type(UnitXP) ~= "function" or type(UnitXPMax) ~= "function" then return nil end
    -- Switched off deliberately. Checked BEFORE the level, because it is a different reason for the
    -- same outcome and a level check alone would miss it.
    if type(IsXPUserDisabled) == "function" and IsXPUserDisabled() then return nil end

    local max = UnitXPMax("player") or 0
    -- Max level reports a max of 0, so this one test covers both "capped" and "no data yet".
    if max <= 0 then return nil end

    return {
        value  = UnitXP("player") or 0,
        max    = max,
        -- nil, not 0, when there is no bonus -- the client distinguishes them and so does the ghost
        -- fill, which must be absent rather than empty.
        rested = type(GetXPExhaustion) == "function" and GetXPExhaustion() or nil,
    }
end

--- The watched faction, read through whichever API this client actually has.
--
-- TWO SHAPES EXIST AND THIS CLIENT COULD BE EITHER. The modern backend replaced the positional
-- `GetWatchedFactionInfo()` with `C_Reputation.GetWatchedFactionData()`, which returns a TABLE.
-- ElvUI carries the same shim on this exact client, which is where the field names come from rather
-- than from memory:
--
--   name, reaction, currentReactionThreshold, nextReactionThreshold, currentStanding, factionID
--
-- SIX values, not five. The old five-value read here happened to map correctly (min = the band's
-- floor, max = its ceiling, value = the raw total), but it could not see the table form at all -- and
-- a nil `name` from a table return read as "nothing is watched", so the bar hid itself on a character
-- that had a faction tracked.
-- @return table|nil, string|nil  the raw fields, or nil plus WHY there is nothing
local function readWatchedFaction()
    -- A BARE global lookup, not `_G.C_Reputation`. A chunk resolves a bare name through its own
    -- environment, which is the real globals in game and the harness's table under test -- while an
    -- explicit `_G.` reaches past that environment to a table the tests do not control.
    local C = C_Reputation
    if C and type(C.GetWatchedFactionData) == "function" then
        local d = C.GetWatchedFactionData()
        if type(d) ~= "table" or not d.name then return nil, "unwatched" end
        return {
            name     = d.name,
            reaction = d.reaction or d.standingID,
            min      = d.currentReactionThreshold,
            max      = d.nextReactionThreshold,
            value    = d.currentStanding,
        }
    end

    if type(GetWatchedFactionInfo) == "function" then
        local name, reaction, min, max, value = GetWatchedFactionInfo()
        if not name then return nil, "unwatched" end
        return { name = name, reaction = reaction, min = min, max = max, value = value }
    end

    -- NEITHER API EXISTS, which is not the same statement as "no faction is watched" and must not look
    -- like it. A silent hide here is indistinguishable from a working bar with nothing to show, and
    -- that is precisely how this went unnoticed.
    return nil, "no_api"
end

--- The reputation reading, or nil when nothing is watched.
-- @return table|nil  { name, standing, value, max, capped }
local function readRep()
    local d, why = readWatchedFaction()
    if not d then
        if why == "no_api" then
            SuuUI.Fault("WatchBars: no reputation API on this client "
                .. "(neither C_Reputation.GetWatchedFactionData nor GetWatchedFactionInfo)")
        end
        return nil
    end

    local min, max, value = d.min or 0, d.max or 0, d.value or 0
    -- Reaction 0 is a real reading the client gives, and every standing table is 1-based.
    local standing = d.reaction
    if not standing or standing == 0 then standing = 1 end

    -- MAX STANDING IS A FULL BAR, NOT A MISSING ONE.
    --
    -- At the top standing the client reports the SAME value for the band's floor and its ceiling, so
    -- the span is zero. The old guard returned nil on that, which hid the bar completely -- so an
    -- Exalted faction looked exactly like no faction at all. ElvUI forces the floor to 0 for the same
    -- reason, and its comment says so outright: "the min will match max when a rep is maxed and cause
    -- the bar to be 0%".
    --
    -- Reported as capped so the readouts can say the standing instead of "42000 / 42000", which is a
    -- number nobody needs once there is nothing left to earn.
    if max <= min then
        return { name = d.name, standing = standing, value = 1, max = 1, capped = true }
    end

    -- The client reports the standing's own band, not a 0..max range, so the bar's span is
    -- max - min and the value is offset into it. Using `value` against `max` directly would make
    -- every standing above Neutral look nearly full.
    return {
        name     = d.name,
        standing = standing,
        value    = math.max(0, value - min),
        max      = max - min,
    }
end

---------------------------------------------------------------------------
-- Readout slots
---------------------------------------------------------------------------
-- The same dropdown pattern the unit frames use. `remaining` and `rested` are experience-only, and
-- `faction` and `standing` are reputation-only -- offering all of them everywhere would put a slot on
-- screen that reads as broken half the time.

local SLOTS = { "left", "center", "right" }

local STANDING_NAMES = {
    "Hated", "Hostile", "Unfriendly", "Neutral", "Honored", "Revered", "Exalted", "Paragon",
}

-- `capped` only ever appears on a reputation reading at max standing, where the span was collapsed to
-- 1/1 so the bar could draw full. These two would then read "1 / 1" and "0", which are numbers about
-- the workaround rather than about the character, so they say nothing instead. Percent is left alone:
-- 100% is true and useful.
local function fmtCurrentMax(r)
    if r.capped then return "" end
    return tostring(r.value) .. " / " .. tostring(r.max)
end
local function fmtPercent(r)
    if r.max <= 0 then return "" end
    return string.format("%.0f%%", (r.value / r.max) * 100)
end
local function fmtRemaining(r)
    if r.capped then return "" end
    return tostring(math.max(0, r.max - r.value))
end

local READOUTS = {
    none        = function() return "" end,
    current_max = fmtCurrentMax,
    percent     = fmtPercent,
    remaining   = fmtRemaining,
    rested      = function(r)
        -- Blank rather than "0" when there is no bonus: a zero here would read as "you have no rested
        -- experience left", which is a different statement from "resting is not a factor right now".
        if not r.rested or r.rested <= 0 then return "" end
        return "+" .. tostring(r.rested)
    end,
    faction     = function(r) return r.name or "" end,
    standing    = function(r) return STANDING_NAMES[r.standing or 4] or "" end,
}

local XP_SLOT_OPTIONS = {
    { value = "none",        label = "None" },
    { value = "current_max", label = "Current / Max" },
    { value = "percent",     label = "Percent" },
    { value = "remaining",   label = "Remaining" },
    { value = "rested",      label = "Rested Bonus" },
}

local REP_SLOT_OPTIONS = {
    { value = "none",        label = "None" },
    { value = "faction",     label = "Faction" },
    { value = "standing",    label = "Standing" },
    { value = "current_max", label = "Current / Max" },
    { value = "percent",     label = "Percent" },
    { value = "remaining",   label = "Remaining" },
}

---------------------------------------------------------------------------
-- Bar lifecycle
---------------------------------------------------------------------------

-- The experience bar's two colours, resolved from tokens.
--
-- `StatusBar` takes a LITERAL {r,g,b,a} for a colour, not a token key -- passing the key silently leaves
-- the bar at its white default, which is exactly how this shipped looking wrong. Resolved here rather
-- than at construction so a theme change can re-resolve them.
--
-- NOT the accent. Blue is WoW's RESTED colour, so an accent-blue fill told the player they had a rested
-- bonus whenever they had any progress at all; the rested region is the only thing entitled to be blue.
local function xpFill()
    return SuuUI.Theme:GetToken("colorXp") or { 1, 1, 1, 1 }
end

local function xpRestedFill()
    return SuuUI.Theme:GetToken("colorXpRested") or { 0.25, 0.55, 1.00, 0.55 }
end

local function readingFor(def)
    if def.id == "xp" then return readXP() end
    return readRep()
end

local function paint(p, def)
    local bar = p._bars[def.id]
    if not bar then return end
    local r = readingFor(def)

    -- NOTHING TO SAY MEANS GONE. Flow layout skips a hidden child, so the other bar closes the gap
    -- rather than leaving a hole where this one was.
    if not r then
        bar:Hide()
        return
    end
    bar:Show()

    bar:SetMax(r.max)
    bar:SetValue(r.value)

    -- The ghost. Set from the ABSOLUTE rested amount converted to a fraction of the level, and
    -- offset by current progress, because rested experience extends from where you are.
    if def.id == "xp" then
        if r.rested and r.rested > 0 and r.max > 0 then
            bar:SetSecondary((r.value + r.rested) / r.max)
        else
            bar:SetSecondary(0)
        end
    end

    -- Reputation takes the client's OWN standing colour. Not a theme token: the bands are a game fact
    -- a player already knows by sight, and inventing our own palette for them would be worse than
    -- matching. Core/Game.lua already maps standing onto the client's table.
    if def.id == "rep" then
        local c = SuuUI.Game:ReactionColor(r.standing)
        if c then bar:SetFillColor(c) end
    else
        -- Re-resolved on every paint rather than only at construction, so a theme change moves it.
        -- Cheap: SetFillColor is a texture recolour, not a layout pass.
        bar:SetFillColor(xpFill())
        -- The rested region gets its OWN colour rather than a paler copy of the fill, which is what
        -- makes "rested" legible as a distinct state instead of just more progress.
        bar:SetSecondaryColor(xpRestedFill())
    end

    for _, slot in ipairs(SLOTS) do
        local mode = get(key(def, "slot_" .. slot), slot == "center" and "percent" or "none")
        local fn = READOUTS[mode] or READOUTS.none
        bar:SetText(slot, fn(r))
    end
end

--- Applies the stored width/height to a bar that already exists.
--
-- IN PLACE, never by rebuilding. A rebuild would drop the bar's moveable registration and reset its
-- position (and, once these bars can dock, its dock membership), so the player would see it jump for
-- what was meant to be a resize. `SetSize` comes from InstallBase and pokes the frame, whose own
-- OnSizeChanged emits SIZE_CHANGED -- which is what will let a dock restack around the new span
-- without this function needing to know a dock exists.
local function applySize(p, def)
    local bar = p._bars[def.id]
    if not bar then return end
    -- NO REPAINT NEEDED HERE. `SetSize` pokes the frame, and StatusBar's own OnSizeChanged clears both
    -- pixel caches and re-asserts the current fraction -- the fill follows the new width without this
    -- plugin asking. An explicit paint() call here was dead code, and mutation testing is what showed
    -- it: removing it changed nothing. The same handler emits SIZE_CHANGED, which is what will let a
    -- dock restack around the new span without this function needing to know a dock exists.
    bar:SetSize(get(key(def, "width"), 400), get(key(def, "height"), 10))
end

local function buildBar(p, def)
    if p._bars[def.id] then return end
    local root = SuuUI.UIRoot:GetRootContainer()

    local bar = SuuUI.Components.StatusBar({
        w          = get(key(def, "width"), 400),
        h          = get(key(def, "height"), 10),
        max        = 1,
        -- NO `fillColor` HERE, deliberately. `paint` sets it on every pass -- which is what makes the
        -- bar follow a theme change, since StatusBar stores this prop as a LITERAL captured at
        -- construction and would otherwise keep re-applying the colour the old theme had. Mutation
        -- testing confirmed a construction value cannot matter: `paint` runs before the first frame.
        --
        -- The original bug was passing a token KEY as `fill`, which is neither the right prop nor the
        -- right type, so the bar silently stayed white.
        -- `border`, not `showBorder`: the latter is the internal field name and passing it leaves the
        -- default in place. The SCHEMA default is what actually takes effect -- Settings:Get resolves
        -- through it, so the fallback here never runs once the key is declared.
        border     = get(key(def, "border"), false),
        transition = "instant",
    }, root:GetFrame())
    p._bars[def.id] = bar

    SuuUI.UIRoot:SetLayer(bar:GetFrame(), "normal")
    SuuUI.MoveableFrame:Apply(bar:GetFrame(), {
        pluginId    = PLUGIN_ID,
        key         = key(def, "position"),
        displayName = def.label,
        defaults    = def.position,
    })

    paint(p, def)
end

local function destroyBar(p, def)
    local bar = p._bars[def.id]
    if not bar then return end
    p._bars[def.id] = nil
    if bar:GetFrame()._suuui_moveable then
        SuuUI.MoveableFrame:Remove(bar:GetFrame())
    end
    bar:Destroy()
end

---------------------------------------------------------------------------
-- Settings
---------------------------------------------------------------------------

local function barTab(def)
    local isXP = def.id == "xp"
    local schema = {
        { key = "", label = "General", type = "section" },
        { key = key(def, "enabled"), label = "Enable Bar", type = "toggle", default = true },
        -- Default OFF. A hairline box around a 10px bar reads as a panel rather than a progress
        -- track. Note the SCHEMA default is what takes effect -- Settings:Get resolves through it, so
        -- the fallback passed at the call site never runs once a key is declared here.
        { key = key(def, "border"), label = "Show Border", type = "toggle",
          default = false, enabledIf = key(def, "enabled") },
    }
    for _, slot in ipairs(SLOTS) do
        schema[#schema + 1] = {
            key = key(def, "slot_" .. slot),
            label = slot:sub(1, 1):upper() .. slot:sub(2) .. " Text",
            type = "dropdown",
            default = slot == "center" and "percent" or "none",
            enabledIf = key(def, "enabled"),
            options = isXP and XP_SLOT_OPTIONS or REP_SLOT_OPTIONS,
        }
    end
    schema[#schema + 1] = { key = key(def, "width"), label = "Width", type = "slider",
        min = 100, max = 1200, step = 10, default = 400, enabledIf = key(def, "enabled") }
    schema[#schema + 1] = { key = key(def, "height"), label = "Height", type = "slider",
        min = 4, max = 40, step = 1, default = 10, enabledIf = key(def, "enabled") }
    schema[#schema + 1] = { key = key(def, "position"), type = "position", default = def.position }
    return { id = def.id, label = def.label, schema = schema }
end

local function schema()
    local s = {
        { key = "enabled", label = "Enable Watch Bars", type = "toggle", default = true },
    }
    local tabs = {}
    for i, def in ipairs(BARS) do tabs[i] = barTab(def) end
    s[#s + 1] = { key = "", type = "subtabs", tabs = tabs }
    return s
end

---------------------------------------------------------------------------
-- Plugin
---------------------------------------------------------------------------

-- Every event that can change either reading. Registered as one set rather than per bar: the cost is
-- one repaint of two bars, and splitting them would mean deciding which bar owns SPELLS_CHANGED.
local EVENTS = {
    "PLAYER_XP_UPDATE",
    "UPDATE_EXHAUSTION",
    "PLAYER_LEVEL_UP",
    "UPDATE_FACTION",
    "PLAYER_ENTERING_WORLD",
}

SuuUI:CreatePlugin({
    id      = PLUGIN_ID,
    name    = "Watch Bars",
    version = "0.1",

    onInit = function(p)
        p._bars = {}
        SuuUI.Settings:Register(PLUGIN_ID, schema())
        SuuUI.Settings:Watch(PLUGIN_ID, "enabled", function(on)
            if on then p:Enable() else p:Disable() end
        end, OWNER .. ".enabled")
    end,

    onEnable = function(p)
        p._bars = p._bars or {}

        -- PLAYER_ENTERING_WORLD is in the list for the same reason the stance bar needed it: at build
        -- time the client can still answer 0 for the level's max, and nothing else would fire for a
        -- character who is simply logging in already levelled.
        p._evt = p._evt or CreateFrame("Frame")
        p._evt:SetScript("OnEvent", function()
            for _, def in ipairs(BARS) do paint(p, def) end
        end)
        for _, e in ipairs(EVENTS) do
            pcall(p._evt.RegisterEvent, p._evt, e)
        end

        -- A theme change moves the XP fill, which is resolved from a token rather than stored.
        SuuUI.Events:On("SUUUI_THEME_CHANGED", function()
            for _, def in ipairs(BARS) do paint(p, def) end
        end, OWNER .. ".theme")

        for _, def in ipairs(BARS) do
            SuuUI.Settings:Watch(PLUGIN_ID, key(def, "enabled"), function(on)
                if on then buildBar(p, def) else destroyBar(p, def) end
            end, OWNER .. "." .. def.id, { immediate = true })

            -- Repaint-only settings. Separate from the build watcher so changing a readout does not
            -- tear the bar down and put it back.
            for _, name in ipairs({ "slot_left", "slot_center", "slot_right" }) do
                SuuUI.Settings:Watch(PLUGIN_ID, key(def, name), function()
                    paint(p, def)
                end, OWNER .. "." .. def.id .. "." .. name)
            end

            -- GEOMETRY AND CHROME, which had NO watcher at all. The values were read once in buildBar,
            -- so dragging the width slider did nothing until the bar was rebuilt -- which only happened
            -- on a reload or on toggling the bar off and on. A setting that appears to be ignored is
            -- worse than one that is missing: the player assumes the feature is broken.
            for _, name in ipairs({ "width", "height" }) do
                SuuUI.Settings:Watch(PLUGIN_ID, key(def, name), function()
                    applySize(p, def)
                end, OWNER .. "." .. def.id .. "." .. name)
            end

            SuuUI.Settings:Watch(PLUGIN_ID, key(def, "border"), function(on)
                local bar = p._bars[def.id]
                if bar then bar:SetBorderShown(on and true or false) end
            end, OWNER .. "." .. def.id .. ".border")
        end
    end,

    onDisable = function(p)
        SuuUI.Settings:UnwatchPrefix(OWNER .. ".")
        SuuUI.Events:Off("SUUUI_THEME_CHANGED", OWNER .. ".theme")
        if p._evt then
            p._evt:UnregisterAllEvents()
            p._evt:SetScript("OnEvent", nil)
        end
        for _, def in ipairs(BARS) do destroyBar(p, def) end
    end,
})

SuuUI._WatchBars = {
    BARS = BARS,
    READOUTS = READOUTS,
    STANDING_NAMES = STANDING_NAMES,
    readXP = readXP,
    readRep = readRep,
}
