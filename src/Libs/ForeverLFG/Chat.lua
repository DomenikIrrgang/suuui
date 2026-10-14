-- Libs/ForeverLFG/Chat.lua
-- The chat source: the public channels (LookingForGroup, General, Trade,
-- Services) and Say/Yell, as they arrive, through the parser into the
-- store. Lines the game hides (secret values) are skipped. Probed
-- 2026-10-14: channel text reaches addons readable, also in dungeon combat.
--
-- LookingForGroup: you aren't in it by default. The library joins it at
-- start (works from a timer) and keeps it off every chat window (the game
-- puts it on one when joining), so its posts only show in the Group Finder.
--   LFG.IsHiddenChannel(name)  -- SuuUI's chat Global tab skips these
--   LFG.Chat.Leave()           -- leaves LookingForGroup again

local _, ns = ...
local LFG = ns.LFG

local CH = {}
LFG.Chat = CH

local isSecret = issecretvalue or function() return false end
local LFG_CHANNEL = "LookingForGroup"
local frame

function LFG.IsHiddenChannel(name)
    return LFG.running and LFG.config.hideLookingForGroup and type(name) == "string"
        and name:lower() == LFG_CHANNEL:lower() or false
end

-- The windows a channel is on.
local function windowsWith(channel)
    local out = {}
    for i = 1, (NUM_CHAT_WINDOWS or 10) do
        local list = { GetChatWindowChannels(i) }
        for j = 1, #list, 2 do
            if type(list[j]) == "string" and list[j]:lower() == channel:lower() then out[#out + 1] = i end
        end
    end
    return out
end

function CH.Hide()
    if not LFG.config.hideLookingForGroup or InCombatLockdown() then return end
    for _, i in ipairs(windowsWith(LFG_CHANNEL)) do
        local cf = _G["ChatFrame" .. i]
        if cf and cf.RemoveChannel then pcall(cf.RemoveChannel, cf, LFG_CHANNEL) end
    end
end

function CH.Join()
    if not LFG.config.joinLookingForGroup then return end
    local index = GetChannelName(LFG_CHANNEL)
    if not index or index == 0 then
        pcall(JoinChannelByName, LFG_CHANNEL)
        CH.joined = true
    end
    C_Timer.After(1, CH.Hide)
end

function CH.Leave()
    pcall(LeaveChannelByName, LFG_CHANNEL)
    CH.joined = false
end

local function player()
    return SuuUI and SuuUI.FullName and SuuUI.FullName("player")
end

-- One line.
function CH.Read(event, text, author, _, channelName, _, _, _, _, channelBase, _, _, guid)
    if isSecret(text) or isSecret(author) or type(text) ~= "string" or type(author) ~= "string" then return end
    local channel
    if event == "CHAT_MSG_CHANNEL" then
        channel = (type(channelBase) == "string" and channelBase ~= "" and channelBase) or channelName
        if isSecret(channel) or type(channel) ~= "string" then return end
        -- "Trade - City" and the like: the channel's first word
        channel = channel:match("^(%a+)") or channel
    else
        channel = event == "CHAT_MSG_SAY" and "SAY" or "YELL"
    end
    if not LFG.config.channels[channel] then return end
    local r = LFG.Parser.Parse(text, { languages = LFG.Languages() })
    if not r or r.confidence < (LFG.config.minConfidence or 0.5) then return end
    local key = author
    local old = LFG.Entry(key)
    local prev = old and old.sources.chat
    local class
    if not isSecret(guid) and type(guid) == "string" and GetPlayerInfoByGUID then
        local ok, _, file = pcall(GetPlayerInfoByGUID, guid)
        if ok then class = file end
    end
    LFG.Store.Put(key, "chat", {
        channel = channel, text = text, intent = r.intent, activities = r.activities, quests = r.quests,
        roles = r.roles, classes = r.classes, need = r.need, members = r.members, level = r.level,
        confidence = r.confidence, languages = r.languages, guid = not isSecret(guid) and guid or nil, class = class,
        lastPost = LFG.Now(), posts = (prev and prev.posts or 0) + 1, self = (author == player()),
    })
end

LFG.AddPart({
    Start = function()
        frame = frame or CreateFrame("Frame")
        for _, e in ipairs({ "CHAT_MSG_CHANNEL", "CHAT_MSG_SAY", "CHAT_MSG_YELL", "CHANNEL_UI_UPDATE" }) do
            frame:RegisterEvent(e)
        end
        frame:SetScript("OnEvent", function(_, event, ...)
            if event == "CHANNEL_UI_UPDATE" then
                -- joined (by anyone): off the windows again
                C_Timer.After(0.5, CH.Hide)
                return
            end
            CH.Read(event, ...)
        end)
        -- after the login's own channel joins
        C_Timer.After(5, CH.Join)
    end,
    Stop = function()
        if frame then frame:UnregisterAllEvents() end
    end,
})
