-- AttachPoints: named places one plugin offers for another plugin to attach UI to.
--
-- A cast bar has to become part of the player unit frame — take its width, move with it,
-- grow it — while living in a different plugin. Reaching into UnitFrames for its frame
-- would couple the two directly, which the plugin contract forbids, and would break on
-- load order: whichever plugin came up second would find nothing there.
--
-- So the owner of a frame PUBLISHES a named point and keeps ownership of placement, and a
-- consumer REQUESTS that name. A request is delivered immediately with the current state
-- and again on every change, so a consumer never has to know who loads first, and gets
-- told when the point goes away.
--
-- Why a subscription rather than an event: a broadcast fires once, so a consumer that
-- registered late has to call Get as well, and the two paths drift — the same duplication
-- Settings:Watch exists to remove. Request is the single path, and it always delivers.
local pairs, ipairs, type, assert, tostring = pairs, ipairs, type, assert, tostring
local tinsert, tremove = table.insert, table.remove

local M = {}

local points       = {}  -- [name] = provider
local requests     = {}  -- [name] = { { cb, owner, _dead }, ... }
local requestCount = 0

--- Delivers a provider (or nil) to every live request for a name.
-- Iterates a snapshot: a callback commonly rebuilds its own widget and therefore
-- Releases and Requests while the notify is in flight, and mutating the live list under
-- iteration silently skips subscribers. Same contract as Settings:Watch.
local function notify(name, provider)
    local list = requests[name]
    if not list or #list == 0 then return end
    local snapshot = {}
    for i = 1, #list do snapshot[i] = list[i] end
    for i = 1, #snapshot do
        local r = snapshot[i]
        if not r._dead then
            local ok, err = pcall(r.cb, provider)
            if not ok then
                SuuUI.Debug("AttachPoints:Request callback error [" .. tostring(name)
                    .. "]: " .. tostring(err))
            end
        end
    end
end

--- Publishes an attach point under a name.
--
-- The provider keeps ownership of placement: a consumer never adds itself to another
-- plugin's container, it hands its child to Attach and the publisher decides where that
-- goes and how its own frame resizes around it.
--
-- Provider shape:
--   frame  = frame                        parent to create an attaching child under
--   Attach = function(child, opts) end    child = frame, handle or container
--   Detach = function(child) end
-- `opts` is the publisher's own vocabulary — the unit frames use { position = "above" }.
--
-- Names are dotted and namespaced by the publisher: "unitframe.player".
-- @param name string
-- @param provider table
function M:Publish(name, provider)
    assert(type(name) == "string" and name ~= "", "SuuUI AttachPoints: name must be a non-empty string")
    assert(type(provider) == "table", "SuuUI AttachPoints: provider must be a table")
    assert(provider.frame, "SuuUI AttachPoints: provider.frame required")
    assert(type(provider.Attach) == "function", "SuuUI AttachPoints: provider.Attach required")
    assert(type(provider.Detach) == "function", "SuuUI AttachPoints: provider.Detach required")

    -- Overwrite rather than error. A plugin that forgot to Revoke before re-enabling
    -- would otherwise take the client down from inside its own onEnable, and the warning
    -- names the case that is genuinely a bug: two owners claiming one point.
    if points[name] and points[name] ~= provider then
        SuuUI.Debug("AttachPoints: replacing existing point " .. name)
    end
    points[name] = provider
    notify(name, provider)
end

--- Withdraws an attach point. Consumers are notified with nil so they can detach.
-- @param name string
function M:Revoke(name)
    if not points[name] then return end
    points[name] = nil
    notify(name, nil)
end

--- Returns the provider for a name, or nil when nothing has published it.
-- @param name string
-- @return table|nil
function M:Get(name)
    return points[name]
end

--- Returns whether a name is currently published.
-- @param name string
-- @return bool
function M:Has(name)
    return points[name] ~= nil
end

--- Returns the published point names.
-- @return table  Array of strings
function M:List()
    local out = {}
    for name in pairs(points) do out[#out + 1] = name end
    return out
end

--- Subscribes to an attach point by name.
--
-- The callback runs once immediately with the current provider (nil when unpublished),
-- and again whenever it is published or revoked. There is deliberately no opt-out: a
-- consumer that reads the current state separately and then subscribes has two code
-- paths for one fact, and the initial one runs before anyone can publish.
-- @param name string
-- @param cb function(provider|nil)
-- @param owner string  Handle for Release. Required.
function M:Request(name, cb, owner)
    assert(type(name) == "string" and name ~= "", "SuuUI AttachPoints: name must be a non-empty string")
    assert(type(cb) == "function", "SuuUI AttachPoints: Request cb must be a function")
    assert(type(owner) == "string" and owner ~= "",
        "SuuUI AttachPoints: Request owner must be a non-empty string")

    if not requests[name] then requests[name] = {} end
    tinsert(requests[name], { cb = cb, owner = owner })
    requestCount = requestCount + 1

    local ok, err = pcall(cb, points[name])
    if not ok then
        SuuUI.Debug("AttachPoints:Request immediate error [" .. name .. "]: " .. tostring(err))
    end
end

--- Drops every request registered under an owner.
-- @param owner string
-- @return number  How many were removed
function M:Release(owner)
    if type(owner) ~= "string" then return 0 end
    local removed = 0
    for name, list in pairs(requests) do
        for i = #list, 1, -1 do
            if list[i].owner == owner then
                -- Flagged as well as removed: a notify snapshot taken before this call
                -- must not deliver into a consumer that has since torn itself down.
                list[i]._dead = true
                tremove(list, i)
                removed = removed + 1
            end
        end
        if #list == 0 then requests[name] = nil end
    end
    requestCount = requestCount - removed
    return removed
end

--- Returns the live request count. Specs assert against it to catch subscription leaks.
-- @return number
function M:GetRequestCount()
    return requestCount
end

SuuUI.AttachPoints = M
