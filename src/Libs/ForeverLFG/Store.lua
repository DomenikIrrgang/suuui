-- Libs/ForeverLFG/Store.lua
-- The merged list. One entry per leader (their whole name, "Suther
-- Stargazer"): what the tool says about them and what they posted in chat,
-- side by side in entry.sources, merged into the entry's own fields with
-- the tool's word first. Chat posts expire (LFG.config.chatExpiry) unless
-- posted again; tool results go when a search no longer has them.
--
--   LFG.Entries(filter) / LFG.Entry(key)
--   events: EntryAdded(entry), EntryUpdated(entry), EntryRemoved(entry, reason)
--
-- entry = {
--   key, intent ("group" | "player"), activities = { key }, quests = { id },
--   roles = { needed = { tank = n|true, healer, damage }, offered = { ... } },
--   classes = { WARRIOR = true, ... }, need, members = { have, max },
--   level = { min, max }, leader = { name, class, level, guid },
--   text, confidence, firstSeen, lastSeen, you,
--   sources = { tool = { ... } | nil, chat = { ... } | nil },
-- }

local _, ns = ...
local LFG = ns.LFG

local S = {}
LFG.Store = S

local entries = {}

local function union(into, list, seen)
    for _, v in ipairs(list or {}) do
        if not seen[v] then seen[v] = true; into[#into + 1] = v end
    end
end

-- A short fingerprint of what a viewer sees, to tell an update from a repost.
local function signature(e)
    local parts = { e.intent or "", table.concat(e.activities, ","), e.text or "", tostring(e.need),
                    e.members and (e.members[1] .. "/" .. e.members[2]) or "" }
    for _, side in ipairs({ "needed", "offered" }) do
        for _, role in ipairs({ "tank", "healer", "damage" }) do parts[#parts + 1] = tostring(e.roles[side][role]) end
    end
    return table.concat(parts, "|")
end

-- The entry's own fields from its sources (the tool's first).
local function rebuild(e)
    local tool, chat = e.sources.tool, e.sources.chat
    local acts, seen = {}, {}
    union(acts, tool and tool.activities, seen)
    union(acts, chat and chat.activities, seen)
    e.activities = acts
    local quests, seenQ = {}, {}
    union(quests, chat and chat.quests, seenQ)
    e.quests = quests
    e.intent = (tool and tool.intent) or (chat and chat.intent)
    e.roles = { needed = {}, offered = {} }
    if tool then
        for k, v in pairs(tool.needed or {}) do e.roles.needed[k] = v end
        for k, v in pairs(tool.offered or {}) do e.roles.offered[k] = v end
    elseif chat then
        local side = chat.intent == "player" and "offered" or "needed"
        for k, v in pairs(chat.roles or {}) do e.roles[side][k] = v end
    end
    e.classes = (chat and chat.classes) or {}
    e.need = (tool and tool.need) or (chat and chat.need)
    e.members = (tool and tool.members) or (chat and chat.members)
    e.level = (chat and chat.level) or (tool and tool.leader and tool.leader.level and { tool.leader.level, tool.leader.level })
    e.leader = (tool and tool.leader) or { name = e.key, guid = chat and chat.guid, class = chat and chat.class }
    e.leader.name = e.leader.name or e.key
    local comment = tool and tool.comment
    e.text = (comment and comment ~= "") and comment or (chat and chat.text) or ""
    e.confidence = tool and 1 or (chat and chat.confidence) or 0
    e.you = (tool and tool.self) or (chat and chat.self) or false
end

function S.Put(key, source, data)
    if not key or key == "" then return end
    local now = LFG.Now()
    local e = entries[key]
    local new = not e
    if new then
        e = { key = key, sources = {}, firstSeen = now }
        entries[key] = e
    end
    local before = not new and signature(e)
    e.sources[source] = data
    e.lastSeen = now
    rebuild(e)
    if new then
        LFG.Fire("EntryAdded", e)
    elseif signature(e) ~= before then
        LFG.Fire("EntryUpdated", e)
    else
        -- the same again (a repost): only fresher
        LFG.Fire("EntryRefreshed", e)
    end
    return e
end

function S.Drop(key, source, reason)
    local e = entries[key]
    if not (e and e.sources[source]) then return end
    e.sources[source] = nil
    if not next(e.sources) then
        entries[key] = nil
        LFG.Fire("EntryRemoved", e, reason)
    else
        rebuild(e)
        LFG.Fire("EntryUpdated", e)
    end
end

-- A key changing (a tool result whose leader's name came later).
function S.Rename(old, new)
    local e = entries[old]
    if not e or old == new then return end
    entries[old] = nil
    local other = entries[new]
    if other then
        for source, data in pairs(e.sources) do other.sources[source] = other.sources[source] or data end
        rebuild(other)
        LFG.Fire("EntryRemoved", e, "merged")
        LFG.Fire("EntryUpdated", other)
    else
        e.key = new
        entries[new] = e
        rebuild(e)
        LFG.Fire("EntryUpdated", e)
    end
end

function S.Each(fn)
    for key, e in pairs(entries) do fn(key, e) end
end

function S.Clear()
    for key, e in pairs(entries) do
        entries[key] = nil
        LFG.Fire("EntryRemoved", e, "stopped")
    end
end

-- Chat posts out of date.
function S.Expire()
    local now, limit = LFG.Now(), LFG.config.chatExpiry or 300
    local gone = {}
    for key, e in pairs(entries) do
        local chat = e.sources.chat
        if chat and now - (chat.lastPost or 0) > limit then gone[#gone + 1] = key end
    end
    for _, key in ipairs(gone) do S.Drop(key, "chat", "expired") end
end

--------------------------------------------------------------------------------
-- Reading the list
--------------------------------------------------------------------------------

function LFG.Entry(key) return entries[key] end

-- filter = { intent, kinds = { dungeon = true, ... }, activities = { key = true },
--            sources = { tool = true, chat = true }, minConfidence, search, notYou }
function LFG.Entries(filter)
    filter = filter or {}
    local wanted
    if filter.activities then
        wanted = {}
        for key in pairs(filter.activities) do
            for _, k in ipairs(LFG.Catalogue.Expand(key)) do wanted[k] = true end
        end
    end
    local out = {}
    for _, e in pairs(entries) do
        local keep = true
        if filter.intent and e.intent ~= filter.intent then keep = false end
        if keep and filter.notYou and e.you then keep = false end
        if keep and filter.minConfidence and e.confidence < filter.minConfidence then keep = false end
        if keep and filter.sources then
            keep = false
            for source in pairs(e.sources) do if filter.sources[source] then keep = true end end
        end
        if keep and (filter.kinds or wanted) then
            keep = false
            for _, key in ipairs(e.activities) do
                for _, k in ipairs(LFG.Catalogue.Expand(key)) do
                    local a = LFG.Catalogue.Get(k)
                    if (not filter.kinds or (a and filter.kinds[a.kind])) and (not wanted or wanted[k]) then keep = true end
                end
            end
            if not keep and filter.kinds and filter.kinds.quest and #e.quests > 0 then keep = true end
        end
        if keep and filter.search and filter.search ~= "" then
            local hay = (e.key .. " " .. (e.text or "")):lower()
            keep = hay:find(filter.search:lower(), 1, true) ~= nil
        end
        if keep then out[#out + 1] = e end
    end
    table.sort(out, function(a, b) return (a.lastSeen or 0) > (b.lastSeen or 0) end)
    return out
end
