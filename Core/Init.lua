-- Core/Init.lua
-- The addon namespace, chat output and the /suu command registry.
-- Loads first; every other file reaches the namespace through `...`.

local ADDON, ns = ...

SuuUI = ns
ns.name = ADDON
ns.version = C_AddOns.GetAddOnMetadata(ADDON, "Version") or "dev"

local PREFIX = "|cff9fd3c7SuuUI|r "

function ns.Print(...)
    print(PREFIX .. strjoin(" ", tostringall(...)))
end

--------------------------------------------------------------------------------
-- Slash commands
--
-- Modules add their own subcommands with ns.RegisterCommand; "/suu" alone
-- lists them in registration order.
--------------------------------------------------------------------------------

local commands, order = {}, {}

function ns.RegisterCommand(name, help, fn)
    assert(not commands[name], "SuuUI: duplicate command " .. name)
    commands[name] = { help = help, fn = fn }
    order[#order + 1] = name
end

local function showHelp()
    ns.Print("version " .. ns.version)
    for _, name in ipairs(order) do
        print(("  /suu %s  -  %s"):format(name, commands[name].help))
    end
end

ns.RegisterCommand("version", "Show the SuuUI and client versions.", function()
    local version, build, _, toc = GetBuildInfo()
    ns.Print(("SuuUI %s on client %s (build %s, interface %d)"):format(ns.version, version, build, toc))
end)

SLASH_SUUUI1 = "/suu"
SLASH_SUUUI2 = "/suuui"
SlashCmdList.SUUUI = function(msg)
    local name, rest = strtrim(msg or ""):match("^(%S*)%s*(.-)$")
    name = name:lower()
    local cmd = commands[name]
    if cmd then
        cmd.fn(rest)
    else
        if name ~= "" and name ~= "help" then
            ns.Print(("Unknown command \"%s\"."):format(name))
        end
        showHelp()
    end
end
