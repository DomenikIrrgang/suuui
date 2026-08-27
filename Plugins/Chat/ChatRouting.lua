-- Which tab a chat event belongs to. PURE: takes the client's own group tables as arguments, holds
-- no frames and reads no settings, so the whole routing model is specifiable without a tab
-- existing.
--
-- THE GROUP IS THE UNIT, never the raw event. A group is what the client persists and what a tab
-- subscribes to; expanding it to events is the last step, not the first.
local type, ipairs, pairs = type, ipairs, pairs

local M = {}

-- The four v1 tabs, ruled 2026-08-27. General is CONVERSATIONAL -- the channels where somebody is
-- talking to you or near you -- rather than the everything tab.
M.TABS = { "general", "guild", "log" }

-- Groups per tab, in an EXPLICIT ORDER. Ordered rather than a hash because the client's own
-- inverted map is built with pairs() while CHAT_MSG_AFK sits in two groups, which makes its
-- event->group answer differ between logins. Ours must not.
M.TAB_GROUPS = {
    general = {
        "SAY", "YELL", "EMOTE", "TEXT_EMOTE",
        "PARTY", "PARTY_LEADER",
        "RAID", "RAID_LEADER", "RAID_WARNING",
        "MONSTER_SAY", "MONSTER_YELL", "MONSTER_EMOTE", "MONSTER_WHISPER",
        "MONSTER_BOSS_EMOTE", "MONSTER_BOSS_WHISPER",
        "BG_SYSTEM_NEUTRAL", "BG_SYSTEM_ALLIANCE", "BG_SYSTEM_HORDE",
    },
    guild = { "GUILD", "OFFICER" },
    -- Everything that is not conversation. Window 2's six groups land here rather than in
    -- General, which is the direct answer to the default chat being unreadable because one
    -- stream carries both a whisper and a durability warning.
    log = {
        "SYSTEM", "ERRORS", "IGNORED",
        "LOOT", "MONEY", "SKILL", "CURRENCY",
        "COMBAT_XP_GAIN", "COMBAT_HONOR_GAIN", "COMBAT_MISC_INFO", "COMBAT_FACTION_CHANGE",
        "TRADESKILLS", "OPENING", "PET_INFO",
    },
}

-- Whisper groups are routed by the whisper_mode setting rather than by a fixed table, because
-- their destination is the one thing the player configures.
M.WHISPER_GROUPS = { "WHISPER", "AFK", "DND", "BN_WHISPER" }

--- Expands a group to the events it carries, from the CLIENT's own table.
---
--- Takes the table as an argument rather than reading the global, so a spec can prove the
--- expansion without staging a global -- and so a group the client declares but never fires
--- (PET_BATTLE_INFO, PING, INSTANCE_CHAT on this build) costs nothing rather than raising.
-- @param group string
-- @param groupTable table|nil  defaults to the client's ChatTypeGroup
-- @return table  array of event names, empty when the group is unknown here
function M.EventsFor(group, groupTable)
    local src = groupTable or ChatTypeGroup
    if type(src) ~= "table" then return {} end
    local list = src[group]
    if type(list) ~= "table" then return {} end
    local out = {}
    for i, e in ipairs(list) do out[i] = e end
    return out
end

--- Every event a tab needs to register, deduplicated and in a STABLE order.
---
--- Stable because the group list is ordered and dedup keeps first-seen position: an unstable
--- order would make a spec pass intermittently, which is the same hazard the DataBar registry's
--- total ordering exists to avoid.
-- @param tab string
-- @param groupTable table|nil
-- @return table array of events, table set
function M.EventsForTab(tab, groupTable)
    local groups = M.TAB_GROUPS[tab]
    local out, seen = {}, {}
    if not groups then return out, seen end
    for _, group in ipairs(groups) do
        for _, e in ipairs(M.EventsFor(group, groupTable)) do
            if not seen[e] then
                seen[e] = true
                out[#out + 1] = e
            end
        end
    end
    return out, seen
end

--- Which tab an event belongs to, built as an ordered event->tab map.
---
--- Built from the ordered TAB_GROUPS rather than by iterating the client's table with pairs(),
--- so an event that appears in two groups resolves the SAME way on every login. CHAT_MSG_AFK is
--- exactly that case: it sits in both WHISPER and AFK.
-- @param groupTable table|nil
-- @return table  event -> tab
function M.BuildEventMap(groupTable)
    local map = {}
    for _, tab in ipairs(M.TABS) do
        for _, e in ipairs(M.EventsForTab(tab, groupTable)) do
            -- First tab to claim an event keeps it: TABS is ordered, so this is deterministic.
            if map[e] == nil then map[e] = tab end
        end
    end
    return map
end

--- Where a whisper goes, from the player's setting.
---
--- Returns a LIST because "both" is a real answer -- a whisper can legitimately land in two tabs
--- at once, which is what Blizzard's popout_and_inline does. A caller that expected one tab would
--- silently drop half the modes.
-- @param mode string|nil  "general" | "panel" | "both"; unknown degrades to "both"
-- @param conversationKey string|nil  the name-realm key, when there is a conversation to route to
-- @return table  array of destinations: "general" and/or the conversation key
function M.WhisperTargets(mode, conversationKey)
    local out = {}
    if mode == "general" then
        out[1] = "general"
        return out
    end
    if mode == "panel" then
        -- With no conversation key there is nowhere to put it, so it falls back to General rather
        -- than vanishing -- a lost whisper is the worst outcome this module can produce.
        out[1] = conversationKey or "general"
        return out
    end
    -- "both", and anything unrecognised: a bad stored value must not lose a whisper.
    out[1] = "general"
    if conversationKey then out[2] = conversationKey end
    return out
end

--- Normalises a whisper partner into a conversation key.
---
--- Lowercased `name-realm`. This ONE decision fixes all three of Blizzard's documented whisper-tab
--- failures: temp frames forced to id 11+ that do not survive a session, the duplicate
--- `Name` / `Name - Servername` pair for one person, and layout re-derived on every login.
-- @param name string
-- @param realm string|nil  defaults to the player's own realm
-- @return string|nil
function M.ConversationKey(name, realm)
    if type(name) ~= "string" or name == "" then return nil end
    -- The client hands a cross-realm whisper as "Name-Realm" in one string, so split it before
    -- appending a realm, or the key becomes "name-realm-realm".
    local bare, embedded = name:match("^([^%-]+)%-(.+)$")
    if bare then name, realm = bare, embedded end
    local r = realm
    if type(r) ~= "string" or r == "" then r = "" end
    return (name .. "-" .. r):lower()
end

SuuUI.ChatRouting = M
