-- Diagnostics/ChatProbe.lua
-- "/suu probe chat": where this client keeps its chat window functions
-- (adding and removing channels and message groups, opening and naming
-- windows). Globals, ChatFrameUtil, ChatFrame1's own methods and C_ChatInfo
-- whose names mention channels, message groups or chat windows, plus what
-- each chat window holds. Saved in SuuUIProbe.chat on /reload.

local _, ns = ...

local CP = {}
ns.ChatProbe = CP

local isSecret = issecretvalue or function() return false end
local WORDS = { "channel", "messagegroup", "chatwindow", "fcf_", "chatframe_" }

local function matches(name)
    local low = name:lower()
    for _, w in ipairs(WORDS) do if low:find(w, 1, true) then return true end end
    return false
end

local function functionsIn(t, filter)
    local out = {}
    if type(t) ~= "table" then return out end
    for k, v in pairs(t) do
        if type(k) == "string" and type(v) == "function" and (not filter or matches(k)) then out[#out + 1] = k end
    end
    table.sort(out)
    return out
end

function CP.Command()
    SuuUIProbe = SuuUIProbe or {}
    local out = { at = date("%H:%M:%S") }
    local globals = {}
    for k, v in pairs(_G) do
        if type(k) == "string" and type(v) == "function" and matches(k) then globals[#globals + 1] = k end
    end
    table.sort(globals)
    out.globals = globals
    out.ChatFrameUtil = functionsIn(_G.ChatFrameUtil)
    out.ChatFrame1 = functionsIn(ChatFrame1, true)
    local mt = getmetatable(ChatFrame1)
    out.ChatFrame1Meta = mt and type(mt.__index) == "table" and functionsIn(mt.__index, true) or "none"
    out.C_ChatInfo = functionsIn(C_ChatInfo, true)
    -- the windows and what they hold
    out.windows = {}
    for i = 1, (NUM_CHAT_WINDOWS or 10) do
        local name, size, _, _, _, _, shown, locked, docked = GetChatWindowInfo(i)
        local w = { name = isSecret(name) and "secret" or tostring(name), shown = tostring(shown), docked = tostring(docked) }
        local ok, channels = pcall(function() return { GetChatWindowChannels(i) } end)
        w.channels = ok and table.concat((function()
            local t = {}
            for _, v in ipairs(channels) do t[#t + 1] = tostring(v) end
            return t
        end)(), ", ") or "error"
        local okG, groups = pcall(function() return { GetChatWindowMessages(i) } end)
        w.groups = okG and table.concat((function()
            local t = {}
            for _, v in ipairs(groups) do t[#t + 1] = tostring(v) end
            return t
        end)(), ", ") or "error"
        out.windows[i] = w
    end
    local list = { GetChannelList() }
    local chans = {}
    for i = 1, #list, 3 do chans[#chans + 1] = tostring(list[i]) .. ":" .. tostring(list[i + 1]) end
    out.channelList = table.concat(chans, ", ")
    SuuUIProbe.chat = out
    ns.Print(("Chat probe: %d global functions found. /reload to save."):format(#globals))
end
