-- Libs/ForeverLFG/LFG.lua
-- ForeverLFG: groups and players looking for groups, from the game's group
-- finder ("the tool") and the public chat channels, as one list. A library
-- inside SuuUI with no UI of its own (Docs/ForeverLFG.md): SuuUI's Group
-- Finder module and its notifications are built on it through SuuUI.LFG,
-- like any plugin would be.
--
-- Nothing runs until LFG.Start() (the Group Finder module calls it when
-- enabled), so a disabled module leaves the channels and the tool alone.
--
--   LFG.On(event, fn) / LFG.Off(event, fn)
--   LFG.Configure({ ... })      -- see LFG.config
--   LFG.Start() / LFG.Stop()
-- The rest lives in the other files: Catalogue, Parser, Lang/*, Store,
-- Chat, Tool, Interest.

local _, ns = ...

ns.LFG = {}
local LFG = ns.LFG

LFG.version = "0.1.0"

-- Settings the library works by; the Group Finder module passes the
-- player's own through LFG.Configure.
LFG.config = {
    channels = { LookingForGroup = true, General = true, Trade = true, Services = true, SAY = true, YELL = true },
    joinLookingForGroup = true,   -- join it at start
    hideLookingForGroup = true,   -- and keep it off every chat window
    chatExpiry = 300,             -- seconds a chat post stays without a new one
    staleAfter = 300,             -- tool results older than this are stale (while listed or watching)
    expiringSoon = 120,           -- your listing's seconds left that count as "runs out soon"
    minConfidence = 0.5,          -- chat lines read below this are dropped
    extraLanguages = {},          -- { deDE = true, ... }: Latin-script modules besides yours
}

function LFG.Configure(t)
    for k, v in pairs(t or {}) do LFG.config[k] = v end
    if LFG.OnConfigure then LFG.OnConfigure() end
end

--------------------------------------------------------------------------------
-- Events
--------------------------------------------------------------------------------

local listeners = {}
local unpack = unpack or table.unpack

function LFG.On(event, fn)
    listeners[event] = listeners[event] or {}
    table.insert(listeners[event], fn)
    return fn
end

function LFG.Off(event, fn)
    local list = listeners[event]
    if not list then return end
    for i = #list, 1, -1 do if list[i] == fn then table.remove(list, i) end end
end

-- Every listener runs, whatever another one does.
function LFG.Fire(event, ...)
    local list = listeners[event]
    if not list then return end
    for _, fn in ipairs({ unpack(list) }) do
        local ok, err = pcall(fn, ...)
        if not ok and geterrorhandler then geterrorhandler()(err) end
    end
end

--------------------------------------------------------------------------------
-- Start and stop
--------------------------------------------------------------------------------

LFG.parts = {}       -- { Start = fn, Stop = fn } each, registered by the other files

function LFG.AddPart(part)
    LFG.parts[#LFG.parts + 1] = part
    if LFG.running and part.Start then part.Start() end
end

function LFG.Start()
    if LFG.running then return end
    LFG.running = true
    for _, part in ipairs(LFG.parts) do if part.Start then part.Start() end end
end

function LFG.Stop()
    if not LFG.running then return end
    LFG.running = false
    for i = #LFG.parts, 1, -1 do
        local part = LFG.parts[i]
        if part.Stop then part.Stop() end
    end
end

-- A clock that works in game and in the offline tools.
function LFG.Now()
    return (GetTime and GetTime()) or os.time()
end
