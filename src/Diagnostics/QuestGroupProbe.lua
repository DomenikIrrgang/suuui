-- Diagnostics/QuestGroupProbe.lua
-- "/suu probe questgroup" (asked 2026-10-18: the map's quest pins should
-- mark group quests, design "Map quest difficulty" D): whether the client
-- says a quest is a group quest for quests not in your log too. For the
-- world map's shown zone (or your zone): every quest SuuUI's data has
-- givers offering there, and every quest in your log, with
-- C_QuestLog.GetQuestTagInfo and C_QuestLog.GetSuggestedGroupSize. Saved in
-- SuuUIProbe.questGroup on /reload.

local _, ns = ...

local QG = {}
ns.QuestGroupProbe = QG

local isSecret = issecretvalue or function() return false end

local function tagOf(id)
    if not (C_QuestLog and C_QuestLog.GetQuestTagInfo) then return "missing" end
    local ok, t = pcall(C_QuestLog.GetQuestTagInfo, id)
    if not ok then return "error" end
    if type(t) ~= "table" then return tostring(t) end
    return ("tagID=%s name=%s worldQuestType=%s"):format(tostring(t.tagID), tostring(t.tagName), tostring(t.worldQuestType))
end

local function groupOf(id)
    if not (C_QuestLog and C_QuestLog.GetSuggestedGroupSize) then return "missing" end
    local ok, n = pcall(C_QuestLog.GetSuggestedGroupSize, id)
    if not ok then return "error" end
    return isSecret(n) and "SECRET" or tostring(n)
end

function QG.Command()
    local mapID = (WorldMapFrame and WorldMapFrame:IsShown() and WorldMapFrame:GetMapID()) or C_Map.GetBestMapForUnit("player")
    local starts = ns.QuestStarts or {}
    local out = { at = date("%H:%M:%S"), mapID = mapID, map = {}, log = {}, counts = { tagged = 0, grouped = 0, quests = 0 } }
    local seen = {}
    for _, row in ipairs(starts.maps and starts.maps[mapID] or {}) do
        for i = 4, #row do
            local id = row[i]
            if not seen[id] then
                seen[id] = true
                local tag, group = tagOf(id), groupOf(id)
                out.counts.quests = out.counts.quests + 1
                if tag:find("tagID=") then out.counts.tagged = out.counts.tagged + 1 end
                if tonumber(group) and tonumber(group) > 0 then out.counts.grouped = out.counts.grouped + 1 end
                local q = starts.quests and starts.quests[id]
                out.map[#out.map + 1] = ("%d %s: %s · group %s"):format(id, tostring(q and q[1]), tag, group)
            end
        end
    end
    for i = 1, (C_QuestLog.GetNumQuestLogEntries and C_QuestLog.GetNumQuestLogEntries() or 0) do
        local info = C_QuestLog.GetInfo(i)
        if info and not info.isHeader and info.questID then
            out.log[#out.log + 1] = ("%d %s: %s · group %s · suggestedGroup %s"):format(info.questID, tostring(info.title),
                tagOf(info.questID), groupOf(info.questID), tostring(info.suggestedGroup))
        end
    end
    SuuUIProbe = SuuUIProbe or {}
    SuuUIProbe.questGroup = out
    ns.Print(("Quest group probe: %d quests on map %s (%d tagged, %d with a group size), %d in your log. /reload to save it.")
        :format(out.counts.quests, tostring(mapID), out.counts.tagged, out.counts.grouped, #out.log))
end
