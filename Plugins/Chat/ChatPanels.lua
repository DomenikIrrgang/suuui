local ipairs, pairs, type, tostring = ipairs, pairs, type, tostring
local tinsert, tremove = table.insert, table.remove

local M = {}

--[[ ===========================================================================================
     PANELS. Pure: no frames, no client calls.

     A panel is DATA -- an id, a name, and a FILTER describing what it accepts. It is not a
     hardcoded tab and it does not own messages; ChatStore owns those, and a panel is a view.

     Two properties are the whole point, and the first build had neither:

       * A MESSAGE FANS OUT TO EVERY PANEL THAT ACCEPTS IT. ChatRouting.BuildEventMap mapped an
         event to exactly ONE tab, first-tab-wins, so a whisper could not be in its conversation
         AND in General -- which is a setting the player already has. Accept returns per panel, so
         one record reaching three panels is the ordinary case rather than a special case.
       * WHAT A PANEL SHOWS IS EDITABLE. The filter is stored data, so re-pointing a panel is a
         settings write plus a re-render from the store. Nothing is lost, because the store holds
         records rather than the strings a previous filter produced.

     `first-tab-wins` is gone, and its reason is preserved rather than dropped: it existed because
     CHAT_MSG_AFK sits in two ChatTypeGroups and Blizzard builds its inverted map with `pairs`,
     making the mapping non-deterministic across logins. Determinism here comes from ordered
     arrays plus DE-DUPLICATION inside Accept -- a panel listing both WHISPER and AFK accepts an
     AFK line once, not twice.

     Filters are deliberately a small closed vocabulary rather than a stored predicate: a Lua
     function cannot go into SavedVariables, and a filter the player edits has to be inspectable
     by the settings UI. Adding a dimension later means one more optional field plus one clause in
     Accept -- which is what "extendable for filters" has to mean for something that persists.
     =========================================================================================== ]]

--- The shipped starting layout. DEFAULTS, not the only possible set: the player may add, remove,
--- rename and re-point panels, and this is what a profile with no stored panels gets.
---
--- Every group list is an ordered ARRAY, never a hash, for the reason above.
M.DEFAULTS = {
    {
        id = "general", name = "General", initial = "#",
        -- CONVERSATION only. Not an everything-tab: loot, XP and system lines go to the Log, so
        -- what is left is what a person said to you.
        groups = { "SAY", "YELL", "EMOTE", "TEXT_EMOTE", "PARTY", "PARTY_LEADER",
                   "RAID", "RAID_LEADER", "RAID_WARNING", "MONSTER_SAY", "MONSTER_YELL",
                   "MONSTER_EMOTE", "MONSTER_WHISPER", "MONSTER_PARTY",
                   -- CHANNEL is here because leaving it out LOST EVERY NUMBERED-CHANNEL LINE.
                   -- The event list is built from the panels' groups, so a group no panel claims is
                   -- never registered at all -- and with Blizzard's chat suppressed the player simply
                   -- never sees `/1` or `/2 Trade` again. A channel is people TALKING, so General is
                   -- where it belongs under the same rule that keeps loot and XP in the Log.
                   --
                   -- A joined channel may still be given its OWN panel, which is what the ruling
                   -- asked for; this is the floor, not a replacement for that.
                   "CHANNEL" },
        -- Channel traffic fades out of a frameless log; a conversation does not (see the plan).
        fade = true,
        -- Frameless. The concept gives CHROME to conversations only -- a channel is a firehose you
        -- glance at, a conversation is history you read, so only the latter earns a panel.
        chrome = false,
        -- A neutral disc: General is not one channel, so no channel's colour is honest for it.
        color = "colorGray600",
    },
    {
        id = "guild", name = "Guild", initial = "G",
        groups = { "GUILD", "OFFICER" },
        fade = true, chrome = false,
        color = "GUILD",
    },
    {
        id = "log", name = "Log", initial = "L",
        -- Everything that is not someone talking. One panel rather than a scattering of them,
        -- because the player never wants to READ this -- only to find one line in it afterwards.
        groups = { "SYSTEM", "CHANNEL_NOTICE", "CHANNEL_NOTICE_USER", "CHANNEL_LIST",
                   "LOOT", "MONEY", "COMBAT_XP_GAIN", "COMBAT_HONOR_GAIN", "COMBAT_FACTION_CHANGE",
                   "COMBAT_MISC_INFO", "SKILL", "TRADESKILLS", "OPENING", "PET_INFO",
                   "BG_SYSTEM_NEUTRAL", "BG_SYSTEM_ALLIANCE", "BG_SYSTEM_HORDE",
                   "IGNORED", "TARGETICONS" },
        -- Does NOT fade: the Log exists to be searched after the fact, and a faded line cannot be.
        fade = false, chrome = false,
        color = "colorGray600",
    },
}

--- Builds a conversation panel definition for one whisper partner.
---
--- Filtered by STREAM rather than by group, which is the whole reason `streams` exists: a
--- conversation holds whatever that person sent -- a whisper, an AFK reply, a DND reply -- and
--- those are three different groups reaching one panel.
---
--- Chromed and non-fading, per the concept: a conversation is history, not a firehose.
-- @param key string   ConversationKey output, e.g. "sylvaine-goldensands"
-- @param name string  display name
-- @return table
function M.Conversation(key, name)
    return {
        id      = "whisper:" .. key,
        name    = name or key,
        initial = (name or key):sub(1, 1):upper(),
        streams = { "whisper:" .. key },
        fade    = false,
        chrome  = true,
        -- The rail colour is the partner's CLASS colour where the client will say, which it only
        -- can once a GUID has been seen; nil leaves the caller's own fallback in charge.
        color   = nil,
        conversation = key,
    }
end

--- The groups a whisper belongs to. Separate because a whisper's panel is decided by a THREE-WAY
--- setting rather than by a fixed panel list -- General only, its own conversation panel only, or
--- both. See WhisperPanels.
M.WHISPER_GROUPS = { "WHISPER", "WHISPER_INFORM", "AFK", "DND", "BN_WHISPER", "BN_WHISPER_INFORM" }

local function copyArray(t)
    local out = {}
    if type(t) == "table" then
        for i = 1, #t do out[i] = t[i] end
    end
    return out
end

--- Deep-copies a panel definition, so a caller cannot mutate the defaults in place.
local function copyPanel(p)
    return {
        id     = p.id,
        name   = p.name,
        initial = p.initial,
        color  = p.color,
        groups = copyArray(p.groups),
        senders = p.senders and copyArray(p.senders) or nil,
        streams = p.streams and copyArray(p.streams) or nil,
        fade   = p.fade and true or false,
        chrome = p.chrome and true or false,
        conversation = p.conversation,
        depth  = p.depth,
    }
end

--- The panel list for a profile: the stored one, else the defaults.
---
--- Returns COPIES. The defaults are module state shared by every profile, so handing them out live
--- would let one profile's edit reach every other -- and the caller is the settings layer, which
--- mutates what it is given.
-- @param stored table|nil
-- @return table
--- Removes a CONVERSATION panel from the list, in place. Returns whether one was removed.
---
--- Conversations only, and the refusal is the point: General, Guild and Log are the fixed spine of
--- the window, so a gesture that could remove one would leave the player with a chat they cannot get
--- back without a reload. A conversation is different -- it was created by someone whispering, and a
--- new whisper recreates it.
---
--- The STORE is deliberately untouched. The stream keyed by this conversation keeps its records, so
--- reopening shows the history rather than an empty panel, and closing a window is not a request to
--- delete what was said.
-- @param panels table
-- @param id string
-- @return boolean
function M.Remove(panels, id)
    if type(panels) ~= "table" or type(id) ~= "string" then return false end
    for i = 1, #panels do
        local panel = panels[i]
        if panel.id == id then
            if not panel.conversation then return false end
            tremove(panels, i)
            return true
        end
    end
    return false
end

function M.Panels(stored)
    local out = {}
    local src = (type(stored) == "table" and #stored > 0) and stored or M.DEFAULTS
    for _, p in ipairs(src) do
        if type(p) == "table" and p.id then tinsert(out, copyPanel(p)) end
    end
    -- A stored list that parsed to nothing falls back rather than leaving the player with no
    -- panels at all: an empty chat window is indistinguishable from a broken addon.
    if #out == 0 then
        for _, p in ipairs(M.DEFAULTS) do tinsert(out, copyPanel(p)) end
    end
    return out
end

function M.Find(panels, id)
    for _, p in ipairs(panels or {}) do
        if p.id == id then return p end
    end
    return nil
end

--- Which panels a whisper goes to, for a three-way `whisper_mode`.
---
--- Never returns empty. An unrecognised stored mode still delivers to General, because a lost
--- whisper is the worst outcome this module can produce -- worse than one shown in the wrong
--- place, which the player can at least see and correct.
-- @param mode string   "general" | "panel" | "both"
-- @param conversation string|nil  the conversation panel's id
-- @return table  array of panel ids
function M.WhisperPanels(mode, conversation)
    local convo = (type(conversation) == "string" and conversation ~= "") and conversation or nil
    if mode == "panel" and convo then return { convo } end
    if mode == "both" and convo then return { "general", convo } end
    return { "general" }
end

--- Whether a panel accepts a record.
---
--- Every clause is an AND, and an ABSENT clause matches everything -- so a panel naming only
--- `groups` is filtered by group alone. That is what keeps adding a dimension cheap: a new
--- optional field plus one clause here, with every existing stored panel unaffected because it
--- does not carry the field.
-- @param panel table
-- @param rec table
-- @return boolean
function M.Accept(panel, rec)
    if type(panel) ~= "table" or type(rec) ~= "table" then return false end

    -- An explicit stream list wins over the group filter, and is how a conversation panel is
    -- expressed: it shows one stream regardless of which groups the whispers in it belong to.
    if panel.streams and #panel.streams > 0 then
        local ok = false
        for _, key in ipairs(panel.streams) do
            if key == rec.stream then ok = true break end
        end
        if not ok then return false end
    elseif panel.groups and #panel.groups > 0 then
        local ok = false
        for _, g in ipairs(panel.groups) do
            if g == rec.kind then ok = true break end
        end
        if not ok then return false end
    end

    -- Sender filter: the first dimension beyond the group, and the shape every later one follows.
    if panel.senders and #panel.senders > 0 then
        local who = (rec.sender or ""):lower()
        local ok = false
        for _, s in ipairs(panel.senders) do
            if tostring(s):lower() == who then ok = true break end
        end
        if not ok then return false end
    end

    return true
end

--- Every panel that accepts the record, in panel order.
---
--- DE-DUPLICATED by panel id, which is what replaces first-tab-wins: a panel listing two groups
--- that both contain one event must show it once. Returns ids rather than panels so the caller
--- cannot mutate a definition through the result.
-- @param panels table
-- @param rec table
-- @return table  array of panel ids
function M.Route(panels, rec)
    local out, seen = {}, {}
    for _, p in ipairs(panels or {}) do
        if not seen[p.id] and M.Accept(p, rec) then
            seen[p.id] = true
            tinsert(out, p.id)
        end
    end
    return out
end

--- The CHAT_MSG_* events to register: the union of every panel's groups, plus the whisper groups.
---
--- The union rather than a fixed list, because a group no panel wants should not be subscribed at
--- all -- which is also why an unroutable event cannot normally reach the handler.
---
--- Whisper groups are always included regardless of the panels, because whisper delivery is
--- decided by `whisper_mode` at RECEIPT time rather than by a panel's stored filter: a
--- conversation panel does not exist until someone whispers you, so a union over panels alone
--- would never register the event that creates it.
-- @param panels table
-- @param groupTable table|nil  ChatTypeGroup; injectable for specs
-- @return table array, table set
function M.Events(panels, groupTable)
    groupTable = groupTable or _G.ChatTypeGroup or {}
    local out, seen = {}, {}

    local function addGroup(group)
        local events = groupTable[group]
        if type(events) ~= "table" then
            -- A declared group with no events on this client -- PET_BATTLE_INFO, INSTANCE_CHAT,
            -- CURRENCY. Tolerated silently: the group list is shared across client generations,
            -- and a dead group is not a bug in the panel that names it.
            return
        end
        for _, e in ipairs(events) do
            if not seen[e] then seen[e] = true tinsert(out, e) end
        end
    end

    for _, p in ipairs(panels or {}) do
        for _, g in ipairs(p.groups or {}) do addGroup(g) end
    end
    for _, g in ipairs(M.WHISPER_GROUPS) do addGroup(g) end
    return out, seen
end

SuuUI.ChatPanels = M
