-- Core/Init.lua
-- The addon's private namespace, chat output and the /suu command registry.
-- Loads first; every other file reaches the namespace through `...`.
--
-- The global SuuUI is the public API (filled in by Core/API.lua), the one
-- surface built-in modules and plugin addons are written against. Everything
-- else lives in this private namespace.

local ADDON, ns = ...

SuuUI = {}
ns.API = SuuUI
ns.name = ADDON
ns.version = C_AddOns.GetAddOnMetadata(ADDON, "Version") or "dev"
-- components' method tables by name (UnitFrame = UF…), for SuuUI.Raw
ns.Mixins = {}

local PREFIX = "|cff9fd3c7SuuUI|r "

function ns.Print(...)
    print(PREFIX .. strjoin(" ", tostringall(...)))
end

--------------------------------------------------------------------------------
-- Slash commands
--
-- Core files and modules add subcommands with ns.RegisterCommand. "/suu"
-- alone opens the settings window; "/suu help" lists the commands in
-- registration order. A command registered with an owner (a module) is
-- removed again with ns.UnregisterCommands(owner). `args`, optional: the
-- words that can follow it (a list, or a function returning one), for the
-- chat's command palette.
--------------------------------------------------------------------------------

local commands, order = {}, {}

function ns.RegisterCommand(name, help, fn, owner, args)
    name = name:lower()
    assert(not commands[name], "SuuUI: the command /suu " .. name .. " already exists")
    commands[name] = { help = help, fn = fn, owner = owner, args = args }
    order[#order + 1] = name
end

-- Every /suu subcommand in registration order: { { name, help, args } },
-- args a list of words (or nil).
function ns.Commands()
    local out = {}
    for _, name in ipairs(order) do
        local c = commands[name]
        local args = c.args
        if type(args) == "function" then
            local ok, list = pcall(args)
            args = ok and type(list) == "table" and list or nil
        end
        out[#out + 1] = { name = name, help = c.help, args = args }
    end
    return out
end

function ns.UnregisterCommands(owner)
    for i = #order, 1, -1 do
        local name = order[i]
        if commands[name].owner == owner then
            commands[name] = nil
            table.remove(order, i)
        end
    end
end

local function showHelp()
    ns.Print("version " .. ns.version)
    for _, name in ipairs(order) do
        print(("  /suu %s  -  %s"):format(name, commands[name].help))
    end
end

ns.RegisterCommand("version", "Show the SuuUI and client versions.", function()
    local version, build, _, toc = GetBuildInfo()
    ns.Print(("SuuUI %s (API %s) on client %s (build %s, interface %d)")
        :format(ns.version, tostring(ns.API_VERSION), version, build, toc))
end)

SLASH_SUUUI1 = "/suu"
SLASH_SUUUI2 = "/suuui"
SlashCmdList.SUUUI = function(msg)
    local name, rest = strtrim(msg or ""):match("^(%S*)%s*(.-)$")
    name = name:lower()
    local cmd = commands[name]
    if name == "" and ns.SettingsWindow then
        ns.SettingsWindow.Toggle()
    elseif cmd then
        if ns.Fault then
            ns.Fault.Call("/suu " .. name, cmd.fn, rest)
        else
            cmd.fn(rest)
        end
    else
        if name ~= "help" then
            ns.Print(("Unknown command \"%s\"."):format(name))
        end
        showHelp()
    end
end
