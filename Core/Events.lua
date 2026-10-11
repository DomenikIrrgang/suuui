-- Core/Events.lua
-- One bus for SuuUI's own messages and the game's events.
--
--   Events.On(name, fn, owner)                  SuuUI message, delivered by Events.Emit
--   Events.OnGame(event, fn, owner)             a game event
--   Events.OnUnit(event, units, fn, owner)      a unit event for the given unit(s), through
--                                               RegisterUnitEvent so other units never wake it
--   Events.Off(name, owner) / Events.OffAll(owner)
--
-- Every callback is fn(name, ...) and runs isolated: an error is reported
-- through Fault against its owner and the other listeners still run.
-- Listeners added during a dispatch first hear the next one; listeners removed
-- during a dispatch are skipped from then on. Dispatch allocates nothing.

local _, ns = ...

local Events = {}
ns.Events = Events

local Fault, OwnerName = ns.Fault, ns.Util.OwnerName

-- channel key -> { list = { {fn, owner, name}, ... }, depth = n, dirty = bool, registered = bool }
local channels = {}

local function channel(key)
    local c = channels[key]
    if not c then
        c = { list = {}, depth = 0, dirty = false }
        channels[key] = c
    end
    return c
end

local function compact(c)
    local list, j = c.list, 0
    for i = 1, #list do
        local l = list[i]
        if not l.dead then
            j = j + 1
            list[j] = l
        end
    end
    for i = #list, j + 1, -1 do list[i] = nil end
    c.dirty = false
end

local function dispatch(c, name, ...)
    local list = c.list
    local n = #list
    c.depth = c.depth + 1
    for i = 1, n do
        local l = list[i]
        if not l.dead then
            Fault.Call(l.name, l.fn, name, ...)
        end
    end
    c.depth = c.depth - 1
    if c.depth == 0 and c.dirty then compact(c) end
end

local function add(key, fn, owner)
    assert(type(fn) == "function", "SuuUI Events: callback must be a function")
    assert(owner ~= nil, "SuuUI Events: an owner is required, so the listener can be removed")
    local c = channel(key)
    c.list[#c.list + 1] = { fn = fn, owner = owner, name = OwnerName(owner) }
    return c
end

-- Marks every listener of `owner` on channel `key` dead; returns how many are left.
local function remove(key, owner)
    local c = channels[key]
    if not c then return 0 end
    local live = 0
    for _, l in ipairs(c.list) do
        if not l.dead and l.owner == owner then
            l.dead = true
            c.dirty = true
        elseif not l.dead then
            live = live + 1
        end
    end
    if c.depth == 0 and c.dirty then compact(c) end
    return live
end

--------------------------------------------------------------------------------
-- SuuUI messages
--------------------------------------------------------------------------------

-- SuuUI's own messages are named SUUUI_*, so they never collide with game events.
function Events.On(name, fn, owner)
    assert(name:find("^SUUUI_"), "SuuUI Events: message names start with SUUUI_")
    add("msg:" .. name, fn, owner)
end

function Events.Emit(name, ...)
    local c = channels["msg:" .. name]
    if c and #c.list > 0 then dispatch(c, name, ...) end
end

--------------------------------------------------------------------------------
-- Game events
--------------------------------------------------------------------------------

local gameFrame = CreateFrame("Frame")
gameFrame:SetScript("OnEvent", function(_, event, ...)
    local c = channels["game:" .. event]
    if c then dispatch(c, event, ...) end
end)

function Events.OnGame(event, fn, owner)
    local c = add("game:" .. event, fn, owner)
    if not c.registered then
        gameFrame:RegisterEvent(event)
        c.registered = true
    end
end

-- Unit events get a frame per registration, because RegisterUnitEvent filters
-- per frame. Freed frames are reused.
local unitFrames = {}   -- { event, owner } -> frame
local spareFrames = {}

function Events.OnUnit(event, units, fn, owner)
    assert(type(fn) == "function", "SuuUI Events: callback must be a function")
    assert(owner ~= nil, "SuuUI Events: an owner is required, so the listener can be removed")
    if type(units) == "string" then units = { units } end
    local f = table.remove(spareFrames) or CreateFrame("Frame")
    local name = OwnerName(owner)
    f:SetScript("OnEvent", function(_, e, ...) Fault.Call(name, fn, e, ...) end)
    f:RegisterUnitEvent(event, unpack(units))
    unitFrames[{ event = event, owner = owner }] = f
end

--------------------------------------------------------------------------------
-- Removal
--------------------------------------------------------------------------------

function Events.Off(name, owner)
    remove("msg:" .. name, owner)
    local game = channels["game:" .. name]
    if game and remove("game:" .. name, owner) == 0 and game.registered then
        gameFrame:UnregisterEvent(name)
        game.registered = false
    end
    for reg, f in pairs(unitFrames) do
        if reg.event == name and reg.owner == owner then
            f:UnregisterAllEvents()
            f:SetScript("OnEvent", nil)
            unitFrames[reg] = nil
            spareFrames[#spareFrames + 1] = f
        end
    end
end

function Events.OffAll(owner)
    local names = {}
    for key, c in pairs(channels) do
        for _, l in ipairs(c.list) do
            if l.owner == owner and not l.dead then
                names[key:match("^%a+:(.*)$")] = true
            end
        end
    end
    for reg in pairs(unitFrames) do
        if reg.owner == owner then names[reg.event] = true end
    end
    for name in pairs(names) do Events.Off(name, owner) end
end
