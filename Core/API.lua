-- Core/API.lua
-- The public API: the global SuuUI. Built-in modules and plugin addons use
-- only what is published here (documented in Docs/API.md). Anything a module
-- needs from the core is added here, never reached for in the private
-- namespace. Loads after the rest of Core.

local _, ns = ...

local API = ns.API
local Modules = ns.Modules

API.API_VERSION = ns.API_VERSION
API.version = ns.version

-- Modules
API.RegisterModule = Modules.Register
API.APIAtLeast = Modules.APIAtLeast

function API.GetModule(id)
    return Modules.Get(id)
end

-- A snapshot of every module: { id, name, description, state, source, builtIn, error }.
function API.ListModules()
    local out = {}
    for _, m in ipairs(Modules.All()) do
        out[#out + 1] = {
            id = m.id, name = m.name, description = m.description, state = m.state,
            source = m.source, builtIn = m.builtIn, error = m.error, pendingReload = m.pendingReload,
        }
    end
    return out
end

-- Design tokens (read only: never change them) and text styles
API.Tokens = ns.Tokens
API.Fonts = {
    Get = ns.Fonts.Get,
    Apply = ns.Fonts.Apply,
}

-- Physical pixels
API.Pixel = {
    Size = ns.Pixel.Size,
    Snap = ns.Pixel.Snap,
    PerfectScale = ns.Pixel.PerfectScale,
}

-- Blizzard frames
API.SuppressBlizzard = ns.SuppressBlizzard
API.RestoreBlizzard = ns.RestoreBlizzard
