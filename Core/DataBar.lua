-- DataBar: the registry of bar widgets, and the height the bar occupies.
--
-- Both live in Core rather than in Plugins/DataBar, for the same reason: each has to answer
-- when the bar plugin is absent, disabled, or simply loaded later than whoever is talking to
-- it. A plugin registers its widget whenever it likes and the renderer picks it up, exactly
-- as AttachPoints lets a consumer arrive before its publisher.
--
-- It is deliberately NOT an attach point, and the difference is shape rather than intent: an
-- attach point is ONE provider per name, while this is MANY ordered entries across three
-- fixed sections. Expressing a list through a single-provider registry would mean one point
-- name per widget and no ordering at all.
--
-- The occupied height sits here for the mirror-image reason. Everything that used to hug the
-- top of the screen has to move down by it — Blizzard's minimap and buff frame today, a SuuUI
-- replacement for either later — and a consumer reading the renderer's frame directly would
-- break the moment the player switched the bar off, which is precisely when the answer needs
-- to be 0 rather than an error.
local pairs, ipairs, type, assert, tostring = pairs, ipairs, type, assert, tostring
local tinsert, tremove, tsort = table.insert, table.remove, table.sort

local M = {}

--- The sections a widget may sit in, in screen order.
M.SECTIONS = { "left", "center", "right" }

local isSection = { left = true, center = true, right = true }
local sectionRank = { left = 1, center = 2, right = 3 }

local DEFAULT_SECTION = "left"
local DEFAULT_ORDER   = 100

local widgets  = {}   -- [id] = def, exactly as the plugin handed it over
-- The two ordering keys, snapshotted at registration. The registry sorts on THESE rather
-- than on the live def, so a plugin mutating its own def.order has no effect until it
-- re-registers — which makes "re-register to change your placement" true by construction
-- instead of by convention. Without it, `List()[1].order = 999` reorders the bar silently
-- and invisibly, taking effect at whatever unrelated registration next triggers a resort.
--
-- Copying the whole def instead would break identity, which the replacement check in
-- RegisterWidget and every plugin holding its own table depend on.
local meta     = {}   -- [id] = { section, order }
local sorted   = {}   -- array of ids, section then order then id
local subs     = {}   -- { { cb, owner, _dead }, ... }
local subCount = 0

local hSubs     = {}
local hSubCount = 0
local occupied  = 0

-- Section, then order, then id. The id is the final key so the result is total rather than
-- merely partial: two widgets sharing a section and an order would otherwise come out in
-- table order, which is hash order, which differs between runs — a bar whose fields swap
-- places on some logins, and a spec that passes intermittently.
local function byPlacement(a, b)
    local ma, mb = meta[a], meta[b]
    local ra, rb = sectionRank[ma.section] or 1, sectionRank[mb.section] or 1
    if ra ~= rb then return ra < rb end
    if ma.order ~= mb.order then return ma.order < mb.order end
    return a < b
end

local function resort()
    for i = #sorted, 1, -1 do sorted[i] = nil end
    for id in pairs(widgets) do sorted[#sorted + 1] = id end
    tsort(sorted, byPlacement)
end

-- Iterates a snapshot with a dead flag. A subscriber commonly rebuilds itself in response,
-- and a rebuild that unsubscribes and resubscribes while the live list is being walked
-- silently skips whoever came after it. Same contract as AttachPoints and Settings:Watch.
local function notify(list, count, ...)
    if count == 0 then return end
    local snapshot = {}
    for i = 1, #list do snapshot[i] = list[i] end
    for i = 1, #snapshot do
        local s = snapshot[i]
        if not s._dead then
            local ok, err = pcall(s.cb, ...)
            if not ok then
                SuuUI.Debug("DataBar: subscriber error [" .. tostring(s.owner) .. "]: "
                    .. tostring(err))
            end
        end
    end
end

local function dropOwner(list, owner)
    local removed = 0
    for i = #list, 1, -1 do
        if list[i].owner == owner then
            -- Flagged as well as removed: a notify snapshot taken before this call must not
            -- deliver into a subscriber that has since torn itself down.
            list[i]._dead = true
            tremove(list, i)
            removed = removed + 1
        end
    end
    return removed
end

---------------------------------------------------------------------------
-- Widget registry
---------------------------------------------------------------------------

--- Registers a bar widget.
--
-- The definition is data, not UI: the renderer owns the field, its tokens, its divider and
-- its hover rail, so a plugin describes what to show and never builds a frame. `Build` is
-- the escape hatch for a widget whose visuals genuinely have no textual form.
--
-- Definition:
--   id       string    required, unique. Namespace it with your plugin id.
--   label    string    human name. Nothing renders it yet; it is the key a future
--                      reorder UI would list the widget under.
--   prefix   string    optional muted text drawn before the value ("GOLD")
--   section  string    "left" | "center" | "right" (default "left")
--   order    number    within the section, ascending (default 100)
--   events   table     game events that should refresh this widget
--   update   number    seconds between refreshes, for a widget nothing announces
--   GetText  function  returns the value string, and OPTIONALLY a tone as a second value:
--                      nil | "success" | "warning" | "danger". The tone says what the READING
--                      means and lets the theme decide what that looks like; a widget
--                      composing its own colour escape would hardcode a hue and bypass a
--                      retint. Returned together with the value rather than from a separate
--                      hook, so the two come from one reading and cannot disagree.
--                      Required unless Build is given
--   Build    function(parent) -> handle   custom visuals instead of a text field
--   Refresh  function(handle)             refresh hook for a Build widget, called
--                                         where GetText would be
--   OnClick  function(field, button)
--   OnEnter  function(field)
--   OnLeave  function(field)
--
-- There is deliberately no `schema` field. Settings:Register is called once per plugin in
-- onInit, while a widget may register at any point — during login, from a toggle, from an
-- addon that loads minutes later — so there is no moment at which this page could splice in
-- a stranger's schema. A widget's settings therefore live under its OWN plugin id, on its
-- own page. The built-in clock is the only exception, and only because one plugin owns both
-- sides of it.
-- @param def table
function M:RegisterWidget(def)
    assert(type(def) == "table", "SuuUI DataBar: widget definition must be a table")
    assert(type(def.id) == "string" and def.id ~= "",
        "SuuUI DataBar: widget id must be a non-empty string")
    assert(type(def.GetText) == "function" or type(def.Build) == "function",
        "SuuUI DataBar: widget " .. def.id .. " needs GetText or Build")

    if def.section == nil then
        def.section = DEFAULT_SECTION
    else
        assert(isSection[def.section],
            "SuuUI DataBar: widget " .. def.id .. " has unknown section " .. tostring(def.section))
    end
    if def.order == nil then def.order = DEFAULT_ORDER end
    assert(type(def.order) == "number", "SuuUI DataBar: widget " .. def.id .. " order must be a number")

    -- Overwrite rather than error, exactly as AttachPoints:Publish does. A plugin that
    -- re-registers on re-enable would otherwise take the client down from inside its own
    -- onEnable, and the warning still names the case that is a genuine bug: two owners
    -- claiming one id.
    if widgets[def.id] and widgets[def.id] ~= def then
        SuuUI.Debug("DataBar: replacing existing widget " .. def.id)
    end

    widgets[def.id] = def
    meta[def.id] = { section = def.section, order = def.order }
    resort()
    -- No payload: a subscriber re-reads the set. Handing over the def that changed would
    -- invite acting on a single entry while the ordering it belongs to has moved, and the
    -- renderer's rebuild is a handful of frames rather than something worth optimising.
    -- Every registration during login therefore costs one rebuild, which is measured in
    -- microseconds and happens once.
    notify(subs, subCount)
end

--- Removes a widget by id. Subscribers are notified so the bar drops its field.
-- @param id string
function M:UnregisterWidget(id)
    if not widgets[id] then return end
    widgets[id] = nil
    meta[id] = nil
    resort()
    notify(subs, subCount)
end

--- Returns a widget definition, or nil.
-- @param id string
-- @return table|nil
function M:GetWidget(id)
    return widgets[id]
end

--- Returns whether a widget id is registered.
-- @param id string
-- @return bool
function M:Has(id)
    return widgets[id] ~= nil
end

--- Every registered widget, ordered by section then order then id.
-- A fresh array each call: the internal one is what the renderer's next pass reads, so a
-- caller mutating it would reorder the bar with no rebuild behind it. Same reasoning as
-- Container:GetPadding returning a copy.
-- @return table  Array of definitions
function M:List()
    local out = {}
    for i = 1, #sorted do out[i] = widgets[sorted[i]] end
    return out
end

--- The widgets in one section, in order.
-- @param section string  "left" | "center" | "right"
-- @return table  Array of definitions
function M:ListSection(section)
    local out = {}
    for i = 1, #sorted do
        local id = sorted[i]
        if meta[id].section == section then out[#out + 1] = widgets[id] end
    end
    return out
end

--- Subscribes to changes in the widget set.
--
-- The callback runs once immediately and again on every register and unregister. There is
-- deliberately no opt-out: a subscriber that reads the current set separately and then
-- subscribes has two code paths for one fact, and the initial read happens before anyone
-- else has had a chance to register.
-- @param cb function()
-- @param owner string  Handle for Unsubscribe. Required.
function M:Subscribe(cb, owner)
    assert(type(cb) == "function", "SuuUI DataBar: Subscribe cb must be a function")
    assert(type(owner) == "string" and owner ~= "",
        "SuuUI DataBar: Subscribe owner must be a non-empty string")
    tinsert(subs, { cb = cb, owner = owner })
    subCount = subCount + 1

    local ok, err = pcall(cb)
    if not ok then
        SuuUI.Debug("DataBar:Subscribe immediate error [" .. owner .. "]: " .. tostring(err))
    end
end

--- Drops every widget-set subscription registered under an owner.
-- @param owner string
-- @return number  How many were removed
function M:Unsubscribe(owner)
    if type(owner) ~= "string" then return 0 end
    local removed = dropOwner(subs, owner)
    subCount = subCount - removed
    return removed
end

--- Live subscription count. Specs assert against it to catch leaks.
-- @return number
function M:GetSubscriberCount()
    return subCount
end

---------------------------------------------------------------------------
-- Occupied height
---------------------------------------------------------------------------

--- Reports how much vertical space the bar occupies, in the UI root's units.
--
-- Called by the renderer. 0 means nothing is there, which is what every consumer sees while
-- the plugin is disabled — so a consumer needs no second code path for "no bar".
-- @param h number  Height in root units
function M:SetOccupiedHeight(h)
    -- `h ~= h` is the NaN test, and it is not paranoia: NaN IS a number and `NaN < 0` is
    -- false, so without it a NaN stores verbatim. That poisons every consumer, since this is
    -- a length they add to a y offset — and because `NaN ~= NaN`, the unchanged-value guard
    -- below would then never fire again, so every later write would re-lay out the whole UI.
    if type(h) ~= "number" or h ~= h or h < 0 then h = 0 end
    if occupied == h then return end
    occupied = h
    notify(hSubs, hSubCount, occupied)
end

--- The bar's occupied height in the UI root's units, or 0 when there is no bar.
--
-- This is a length in OUR coordinate space. Handing it straight to a frame anchored to
-- UIParent is wrong by the ratio between the two effective scales — convert it with
-- SuuUI.Pixel.Convert first. See Core/Pixel.lua.
-- @return number
function M:GetOccupiedHeight()
    return occupied
end

--- Subscribes to the occupied height. Fires immediately and on every change.
-- @param cb function(height)
-- @param owner string  Handle for UnwatchHeight. Required.
function M:WatchHeight(cb, owner)
    assert(type(cb) == "function", "SuuUI DataBar: WatchHeight cb must be a function")
    assert(type(owner) == "string" and owner ~= "",
        "SuuUI DataBar: WatchHeight owner must be a non-empty string")
    tinsert(hSubs, { cb = cb, owner = owner })
    hSubCount = hSubCount + 1

    local ok, err = pcall(cb, occupied)
    if not ok then
        SuuUI.Debug("DataBar:WatchHeight immediate error [" .. owner .. "]: " .. tostring(err))
    end
end

--- Drops every height subscription registered under an owner.
-- @param owner string
-- @return number  How many were removed
function M:UnwatchHeight(owner)
    if type(owner) ~= "string" then return 0 end
    local removed = dropOwner(hSubs, owner)
    hSubCount = hSubCount - removed
    return removed
end

--- Live height-subscription count. Specs assert against it to catch leaks.
-- @return number
function M:GetHeightWatcherCount()
    return hSubCount
end

SuuUI.DataBar = M
