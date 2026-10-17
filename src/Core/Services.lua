-- Core/Services.lua
-- What one module does for the others (plan 4.3, 2026-10-18): open the bags,
-- show a player's talents, post a notification… A module provides a service
-- by name with a table of functions; whoever needs it asks for the name, not
-- for the module. A plugin that replaces a module (`replaces`) provides the
-- same services, and every caller reaches it. A module's services go away
-- when it turns off. Built in: bags, talents, collections, professions,
-- notifications, alerts (their functions in Docs/API.md).

local _, ns = ...

local Events = ns.Events

local Services = {}
ns.Services = Services

local providers = {} -- name -> { impl, owner }

function Services.Provide(name, impl, owner)
    assert(type(name) == "string", "SuuUI Provide: a service name is required")
    assert(type(impl) == "table", "SuuUI Provide: a table of functions is required")
    providers[name] = { impl = impl, owner = owner }
    Events.Emit("SUUUI_SERVICE_CHANGED", name)
end

-- The service's functions, or nil while nothing provides it.
function Services.Get(name)
    local p = providers[name]
    return p and p.impl
end

function Services.Unregister(owner)
    for name, p in pairs(providers) do
        if p.owner == owner then
            providers[name] = nil
            Events.Emit("SUUUI_SERVICE_CHANGED", name)
        end
    end
end
