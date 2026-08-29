-- What a panel is allowed to show, as a vocabulary the PLAYER can read.
--
-- PURE: no frames, no settings reads, no client calls. The settings predicate arrives as an
-- argument, so the whole mapping is specifiable without a profile or a panel existing.
--
-- WHY A CATEGORY LAYER AT ALL. A panel's filter is a list of chat GROUPS -- `COMBAT_XP_GAIN`,
-- `MONSTER_BOSS_WHISPER`, `CHANNEL_NOTICE_USER` -- which is the right unit for routing and a
-- terrible unit for a settings page: thirty-odd checkboxes named after the client's internals, of
-- which several mean nothing on their own and three have to be ticked together to get one
-- outcome. A category is the coarser thing a player actually wants ("Loot & Money", "Experience,
-- Honour & Reputation"), and it expands to the groups that produce it.
--
-- ONE DECLARATION, TWO CONSUMERS. `CATEGORIES` is the only place a category's label, its groups
-- and its per-panel default exist. `Schema` builds the settings entries from it and `GroupsFor`
-- builds the panel filter from it, so a category cannot appear on the page without routing
-- anything, and cannot route without being switchable -- the "a token nothing reads" failure, one
-- layer up.
local ipairs, type = ipairs, type
local tinsert = table.insert

local M = {}

--- The panels whose contents the player configures.
---
--- General, Global and Log ONLY, and the omission is deliberate rather than unfinished. Guild is a
--- single-group panel, so a category page for it would be one checkbox that empties it; a
--- conversation panel is filtered by STREAM rather than by group, so a category cannot describe it
--- at all. These three are the panels that carry a MIXTURE, which is the only case a filter is a
--- question about.
M.PANELS = { "general", "global", "log" }

--- The category vocabulary, in the order the settings page renders it.
---
--- `groups` names both the chat GROUP (which is what registers the client events) and the
--- individual KINDS inside it that a record can carry, because the panel filter matches the event
--- suffix while event registration expands the group -- one list serving both, exactly as the
--- shipped panel defaults did. Listing only the group would register the events and match none of
--- them; listing only the kinds would match records that never arrive.
---
--- `general` / `global` / `log` are the DEFAULTS, and they reproduce what the panels shipped with --
--- with two deliberate changes. `system` now defaults ON for General as well: a system line is the
--- one piece of non-conversation traffic a player expects in their main window, because that is
--- where Blizzard puts it, and hiding it made General quieter at the cost of the player not being
--- told things ("you are now Rank 4", a rested-XP notice, a bag-full warning). And `channels` has
--- MOVED from General to Global, which is the whole point of Global existing -- leaving it on in
--- both would print every Trade line twice.
M.CATEGORIES = {
    { id = "say", label = "Say, Yell & Emotes", general = true, global = false, log = false,
      groups = { "SAY", "YELL", "EMOTE", "TEXT_EMOTE" } },
    { id = "party", label = "Party", general = true, global = false, log = false,
      groups = { "PARTY", "PARTY_LEADER", "MONSTER_PARTY" } },
    { id = "raid", label = "Raid & Raid Warnings", general = true, global = false, log = false,
      groups = { "RAID", "RAID_LEADER", "RAID_WARNING" } },
    -- OFF for all three by default: Guild has a panel of its own, so another panel showing it too
    -- would put every guild line on screen twice for a player who has not asked for that.
    { id = "guild", label = "Guild & Officer", general = false, global = false, log = false,
      groups = { "GUILD", "OFFICER", "GUILD_MOTD" } },
    -- GLOBAL's one category, and the reason that panel exists. `CHANNEL` is a SINGLE group covering
    -- General, Trade, LocalDefense, LookingForGroup and every custom channel the player joined --
    -- the client makes no distinction between a city channel and a joined one, they are all
    -- `CHAT_MSG_CHANNEL` told apart by their INDEX. So "all the global channels plus the custom
    -- ones" is exactly this one group, and there is no finer filter to offer without inventing a
    -- per-channel dimension the panel model does not have yet.
    { id = "channels", label = "Chat Channels", general = false, global = true, log = false,
      groups = { "CHANNEL" } },
    { id = "creatures", label = "Creatures & Bosses", general = true, global = false, log = false,
      groups = { "MONSTER_SAY", "MONSTER_YELL", "MONSTER_EMOTE", "MONSTER_WHISPER",
                 "MONSTER_BOSS_EMOTE", "MONSTER_BOSS_WHISPER" } },
    -- In General AND the Log by default. The Log keeps it because that is where a player searches
    -- for a line afterwards; General gains it because that is where they read one as it happens. A
    -- record reaching two panels is the ordinary case in this model, not a special one.
    { id = "system", label = "System Messages", general = true, global = false, log = true,
      groups = { "SYSTEM", "ERRORS" } },
    -- `CHANNEL_JOIN` and `CHANNEL_LEAVE` are named here for a reason that is not symmetry: the
    -- `CHANNEL` group registers both events, and until now no panel claimed either KIND -- so every
    -- join and leave notice fell through routing into `_render`'s never-land-nowhere fallback, which
    -- is General. They were arriving in the conversation panel by accident. Claimed here, they land
    -- in the Log with the rest of the channel bookkeeping.
    --
    -- Off for Global on purpose, even though these ARE about channels: the panel was asked for so
    -- the player can read what people are SAYING in them, and "X has joined channel Trade" is
    -- bookkeeping. It is one toggle away for anyone who wants it there.
    { id = "channel_notices", label = "Channel Joins & Notices",
      general = false, global = false, log = true,
      groups = { "CHANNEL_NOTICE", "CHANNEL_NOTICE_USER", "CHANNEL_LIST",
                 "CHANNEL_JOIN", "CHANNEL_LEAVE" } },
    { id = "loot", label = "Loot & Money", general = false, global = false, log = true,
      groups = { "LOOT", "MONEY", "CURRENCY" } },
    { id = "progress", label = "Experience, Honour & Reputation",
      general = false, global = false, log = true,
      groups = { "COMBAT_XP_GAIN", "COMBAT_HONOR_GAIN", "COMBAT_FACTION_CHANGE",
                 "COMBAT_MISC_INFO" } },
    { id = "skills", label = "Skills & Professions", general = false, global = false, log = true,
      groups = { "SKILL", "TRADESKILLS", "OPENING", "PET_INFO" } },
    { id = "battleground", label = "Battleground Announcements",
      general = false, global = false, log = true,
      groups = { "BG_SYSTEM_NEUTRAL", "BG_SYSTEM_ALLIANCE", "BG_SYSTEM_HORDE" } },
    { id = "markers", label = "Raid Target Markers", general = false, global = false, log = true,
      groups = { "TARGETICONS" } },
    { id = "ignored", label = "Ignored Players", general = false, global = false, log = true,
      groups = { "IGNORED" } },
}

--- The settings key for one panel's one category.
---
--- Built here rather than concatenated at each call site, so the schema, the watchers and the
--- filter resolution cannot disagree about a key's spelling -- the same reason `AuraBand` exposes
--- `PositionKey`/`SizeKey` instead of letting callers build them.
-- @param panelId string
-- @param catId string
-- @return string|nil
function M.Key(panelId, catId)
    if type(panelId) ~= "string" or type(catId) ~= "string" then return nil end
    return panelId .. "_show_" .. catId
end

--- One category by id.
-- @param catId string
-- @return table|nil
function M.Find(catId)
    for _, c in ipairs(M.CATEGORIES) do
        if c.id == catId then return c end
    end
    return nil
end

--- Whether a category ships ON for a panel.
---
--- Returns false for an unknown panel or category rather than nil, because it is read as a schema
--- `default` and a nil default makes a toggle render unchecked while `Get` answers nil -- two
--- spellings of off, one of which no watcher fires for.
-- @param panelId string
-- @param catId string
-- @return boolean
function M.Default(panelId, catId)
    local c = M.Find(catId)
    if not c then return false end
    return c[panelId] and true or false
end

--- The settings-schema entries for one panel's categories.
---
--- Generated rather than hand-written, so adding a category is one row in `CATEGORIES` and no edit
--- anywhere else. Every entry is a plain `toggle`, so `PageBuilder` needs no new control type.
-- @param panelId string
-- @return table  array of schema entries
function M.Schema(panelId)
    local out = {}
    for _, c in ipairs(M.CATEGORIES) do
        tinsert(out, {
            key = M.Key(panelId, c.id),
            label = c.label,
            type = "toggle",
            default = M.Default(panelId, c.id),
        })
    end
    return out
end

--- The group filter for one panel, from a predicate saying which categories are on.
---
--- ORDERED and DE-DUPLICATED, for the reason `ChatPanels` states about its own arrays: the panel
--- list is walked to build the event registration set, and an order that came out of `pairs` would
--- differ between logins -- which is exactly the non-determinism `ChatTypeGroupInverted` suffers
--- from and this model exists to avoid.
---
--- `isOn` is optional. Omitted, the shipped defaults answer -- which is what lets `ChatPanels`
--- declare its own defaults from this table instead of keeping a second copy of them.
-- @param panelId string
-- @param isOn function|nil  (catId) -> boolean; defaults to the shipped default
-- @return table  array of group names
function M.GroupsFor(panelId, isOn)
    local out, seen = {}, {}
    for _, c in ipairs(M.CATEGORIES) do
        local on
        if isOn then on = isOn(c.id) and true or false else on = M.Default(panelId, c.id) end
        if on then
            for _, g in ipairs(c.groups) do
                if not seen[g] then
                    seen[g] = true
                    tinsert(out, g)
                end
            end
        end
    end
    return out
end

--- Every category key for every configurable panel, for a caller wiring watchers.
---
--- Derived rather than listed, so a new category is watched without anyone remembering to add it --
--- the failure mode being a control that stores a value nothing reacts to, which reads as the
--- setting being broken.
-- @return table  array of settings keys
function M.Keys()
    local out = {}
    for _, panelId in ipairs(M.PANELS) do
        for _, c in ipairs(M.CATEGORIES) do
            tinsert(out, M.Key(panelId, c.id))
        end
    end
    return out
end

SuuUI.ChatCategories = M
