-- Diagnostics/GiverProbe.lua
-- "/suu probe givers": while it's on, every NPC whose quests you open (its
-- gossip, its quest greeting, a quest it offers straight away) is checked
-- against the world map's pins: what the NPC offers next to what the map
-- says it should (WorldMap:QuestsFor, the pins' own checks). A difference is
-- printed in chat and kept in SuuUIProbe.givers on /reload, with the quests
-- before and instead of each one, done or not, so the reason shows.
--   /suu probe givers        on or off
--   /suu probe givers clear  forget what was recorded

local _, ns = ...

local GP = {}
ns.GiverProbe = GP

local isSecret = issecretvalue or function() return false end
local function plain(v) return v ~= nil and not isSecret(v) end

local function store()
    SuuUIProbe = SuuUIProbe or {}
    SuuUIProbe.givers = SuuUIProbe.givers or { npcs = {}, checked = 0, differences = 0 }
    return SuuUIProbe.givers
end

-- the NPC you're talking to: its ID from its GUID ("Creature-0-…-<id>-…")
local function npc()
    local ok, guid = pcall(UnitGUID, "npc")
    if not (ok and plain(guid)) then return nil end
    local kind, id = guid:match("^(%a+)%-%d+%-%d+%-%d+%-%d+%-(%d+)")
    if kind ~= "Creature" and kind ~= "Vehicle" then return nil end
    local okName, name = pcall(UnitName, "npc")
    return tonumber(id), okName and plain(name) and name or "?"
end

-- the quests it offers now: { [questID] = title }
local function offered(event)
    local out = {}
    if event == "GOSSIP_SHOW" and C_GossipInfo and C_GossipInfo.GetAvailableQuests then
        local ok, list = pcall(C_GossipInfo.GetAvailableQuests)
        for _, q in ipairs(ok and type(list) == "table" and list or {}) do
            if plain(q.questID) then out[q.questID] = q.title or "?" end
        end
    elseif event == "QUEST_GREETING" then
        local ok, n = pcall(GetNumAvailableQuests)
        for i = 1, ok and plain(n) and n or 0 do
            local okInfo, a, b, c, d, id = pcall(GetAvailableQuestInfo, i)
            local okTitle, title = pcall(GetAvailableTitle, i)
            -- (the quest ID is GetAvailableQuestInfo's fifth value)
            if okInfo and plain(id) and type(id) == "number" then out[id] = okTitle and title or "?" end
        end
    elseif event == "QUEST_DETAIL" then
        local ok, id = pcall(GetQuestID)
        local okTitle, title = pcall(GetTitleText)
        if ok and plain(id) and id > 0 then out[id] = okTitle and title or "?" end
    end
    return out
end

-- the quests before one and instead of it, done or not ("97246 done")
local function why(id, done)
    local q = SuuUI.QuestStarts().quests[id]
    if not q then return "not in the data" end
    local parts = {}
    local function list(label, ids)
        local items = {}
        for _, pre in ipairs(ids or {}) do items[#items + 1] = pre .. (done[pre] and " done" or " not done") end
        if #items > 0 then parts[#parts + 1] = label .. " " .. table.concat(items, ", ") end
    end
    list("after all of", q[6])
    list("after one of", q[7])
    list("not with", q[8])
    parts[#parts + 1] = ("level %s (from %s)"):format(tostring(q[3]), tostring(q[2]))
    if q[16] then parts[#parts + 1] = "event " .. q[16] end
    return table.concat(parts, "; ")
end

function GP.Check(event)
    local map = SuuUI.GetModule and SuuUI.GetModule("worldmap")
    if not (map and map.QuestsFor) then return end
    local id, name = npc()
    if not id then return end
    local offers = offered(event)
    -- a quest offered straight away is one of several, maybe: only check
    -- that it's expected, not that nothing else is
    local partial = event == "QUEST_DETAIL"
    local expected, done = map:QuestsFor(id)
    local s = store()
    s.checked = s.checked + 1
    local missing, extra = {}, {}
    local shown = {}
    for _, q in ipairs(expected) do
        if q.state then
            shown[q.id] = true
            if not offers[q.id] and not partial then
                missing[#missing + 1] = { id = q.id, name = q.name, why = why(q.id, done) }
            end
        end
    end
    -- (a quest 5 levels or more above you the map hides on purpose: noted, not a difference)
    local red = {}
    local myLevel = UnitLevel("player")
    local data = SuuUI.QuestStarts().quests
    for qid, title in pairs(offers) do
        local q = data[qid]
        if not shown[qid] and q and q[3] and plain(myLevel) and q[3] >= myLevel + 5 then
            red[#red + 1] = qid .. " " .. title
        elseif not shown[qid] then
            local known = false
            for _, q in ipairs(expected) do if q.id == qid then known = true end end
            extra[#extra + 1] = { id = qid, name = title, why = known and why(qid, done) or "not given by this NPC in the data" }
        end
    end
    local entry = {
        name = name, at = date("%Y-%m-%d %H:%M"), level = UnitLevel("player"), event = event,
        offered = {}, missing = missing, extra = extra, red = red,
    }
    for qid, title in pairs(offers) do entry.offered[#entry.offered + 1] = qid .. " " .. title end
    s.npcs[id] = entry
    if #missing > 0 or #extra > 0 then
        s.differences = s.differences + 1
        for _, q in ipairs(missing) do
            ns.Print(("Givers: %s doesn't offer %s (%d), the map shows it."):format(name, tostring(q.name), q.id))
        end
        for _, q in ipairs(extra) do
            ns.Print(("Givers: %s offers %s (%d), the map doesn't show it."):format(name, tostring(q.name), q.id))
        end
    end
end

function GP.Command(rest)
    local s = store()
    if rest == "clear" then
        SuuUIProbe.givers = nil
        ns.Print("Givers: forgotten.")
        return
    end
    local f = GP.frame
    if not f then
        f = CreateFrame("Frame")
        f:SetScript("OnEvent", function(_, event)
            -- (the gossip's quests are there a moment after it shows)
            C_Timer.After(0, function() GP.Check(event) end)
        end)
        GP.frame = f
    end
    GP.on = not GP.on
    if GP.on then
        for _, e in ipairs({ "GOSSIP_SHOW", "QUEST_GREETING", "QUEST_DETAIL" }) do f:RegisterEvent(e) end
        ns.Print(("Givers: on. Talk to quest givers; differences show here. %d checked so far; /suu probe givers again to stop."):format(s.checked))
    else
        f:UnregisterAllEvents()
        ns.Print(("Givers: off. %d checked, %d with differences; /reload saves them."):format(s.checked, s.differences))
    end
end
