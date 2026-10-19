-- Diagnostics/SkysightProbe.lua
-- "/suu probe skysight" (asked 2026-10-19: a world map filter for the
-- Convergences of Elements, the tornadoes a Skyborne uses Skysight at; no
-- data names their places but one): what the game tells about them.
--   now:   Skysight in your spellbook (its spell ID, whether it's usable
--          here, its cooldown); vignettes on your map and their places;
--          the map's area POIs; achievements whose criteria name a
--          convergence, Skysight or a tornado (a list of them, if one has it)
--   then (this session, by itself): every Skysight cast (the spell ID,
--          where you stood, your target or mouseover); the vignettes as
--          they come and go (VIGNETTE_MINIMAP_UPDATED), with their places
-- Saved in SuuUIProbe.skysight on /reload. Values the game hides read SECRET.

local _, ns = ...

local SP = {}
ns.SkysightProbe = SP

local isSecret = issecretvalue or function() return false end
local function show(v)
    if isSecret(v) then return "SECRET" end
    if type(v) == "table" and v.x then return ("%.4f,%.4f"):format(v.x, v.y) end
    return tostring(v)
end

local function call(fn, ...)
    if type(fn) ~= "function" then return nil end
    local ok, a, b, c, d = pcall(fn, ...)
    if ok then return a, b, c, d end
end

local function out()
    SuuUIProbe = SuuUIProbe or {}
    SuuUIProbe.skysight = SuuUIProbe.skysight or {}
    return SuuUIProbe.skysight
end

local NAMES = { "skysight", "convergen", "tornado", "cyclone" }
local function matches(text)
    if type(text) ~= "string" or isSecret(text) then return false end
    local low = text:lower()
    for _, n in ipairs(NAMES) do
        if low:find(n, 1, true) then return true end
    end
    return false
end

local function here()
    local map = C_Map.GetBestMapForUnit("player")
    local pos = map and call(C_Map.GetPlayerMapPosition, map, "player")
    return ("map %s at %s"):format(show(map), show(pos))
end

-- Skysight in the spellbook, by name
local function findSkysight()
    local SB = C_SpellBook
    if not (SB and SB.GetNumSpellBookSkillLines) then return "no C_SpellBook" end
    local bank = Enum.SpellBookSpellBank and Enum.SpellBookSpellBank.Player
    for line = 1, call(SB.GetNumSpellBookSkillLines) or 0 do
        local info = call(SB.GetSpellBookSkillLineInfo, line)
        if type(info) == "table" and info.itemIndexOffset and info.numSpellBookItems then
            for i = info.itemIndexOffset + 1, info.itemIndexOffset + info.numSpellBookItems do
                local item = call(SB.GetSpellBookItemInfo, i, bank)
                if type(item) == "table" and matches(item.name) then
                    local id = item.spellID or item.actionID
                    local usable, noMana = call(C_Spell.IsSpellUsable, id)
                    local cd = call(C_Spell.GetSpellCooldown, id)
                    return ("%s (spell %s, line %s): usable here %s/%s, cooldown %s"):format(show(item.name), show(id),
                        show(info.name), show(usable), show(noMana),
                        type(cd) == "table" and ("start %s, duration %s"):format(show(cd.startTime), show(cd.duration)) or show(cd))
                end
            end
        end
    end
    return "not in the spellbook"
end

local function vignettes()
    local list = {}
    local map = C_Map.GetBestMapForUnit("player")
    for _, guid in ipairs(call(C_VignetteInfo and C_VignetteInfo.GetVignettes) or {}) do
        local v = call(C_VignetteInfo.GetVignetteInfo, guid)
        if type(v) == "table" then
            local pos = map and call(C_VignetteInfo.GetVignettePosition, guid, map)
            list[#list + 1] = ("%s: vignetteID %s, atlas %s, onMinimap %s, onWorldMap %s, at %s"):format(show(v.name),
                show(v.vignetteID), show(v.atlasName), show(v.onMinimap), show(v.onWorldMap), show(pos))
        end
    end
    return list
end

local function areaPOIs()
    local list = {}
    local map = C_Map.GetBestMapForUnit("player")
    for _, id in ipairs(map and call(C_AreaPoiInfo and C_AreaPoiInfo.GetAreaPOIForMap, map) or {}) do
        local p = call(C_AreaPoiInfo.GetAreaPOIInfo, map, id)
        if type(p) == "table" then
            list[#list + 1] = ("%s (%s): atlas %s, at %s"):format(show(p.name), show(id), show(p.atlasName), show(p.position))
        end
    end
    return list
end

-- achievements with a criterion naming one (the game's own list of them)
local function achievements()
    local found = {}
    local A = C_AchievementInfo
    if not (GetCategoryList and GetCategoryNumAchievements and GetAchievementInfo) then return "no achievement API" end
    for _, cat in ipairs(call(GetCategoryList) or {}) do
        for i = 1, (call(GetCategoryNumAchievements, cat, true)) or 0 do
            local id, name = call(GetAchievementInfo, cat, i)
            if id then
                local hit = matches(name)
                local crit = {}
                for c = 1, (call(GetAchievementNumCriteria, id)) or 0 do
                    local text, _, done = call(GetAchievementCriteriaInfo, id, c)
                    if matches(text) or hit then crit[#crit + 1] = ("%s%s"):format(show(text), done and " (done)" or "") end
                end
                if hit or #crit > 0 then found[#found + 1] = { id = id, name = show(name), criteria = crit } end
            end
        end
    end
    if A then found.api = "C_AchievementInfo present" end
    return found
end

local function snapshot()
    local o = out()
    o.now = { at = date("%H:%M:%S"), where = here(), spell = findSkysight(), vignettes = vignettes(), areaPOIs = areaPOIs(),
              achievements = achievements() }
end

local listening
local function listen()
    if listening then return end
    listening = CreateFrame("Frame")
    pcall(listening.RegisterUnitEvent, listening, "UNIT_SPELLCAST_SUCCEEDED", "player")
    pcall(listening.RegisterEvent, listening, "VIGNETTE_MINIMAP_UPDATED")
    pcall(listening.RegisterEvent, listening, "VIGNETTES_UPDATED")
    listening:SetScript("OnEvent", function(_, event, a, b, c)
        local o = out()
        if event == "UNIT_SPELLCAST_SUCCEEDED" then
            local name = call(C_Spell.GetSpellName, c)
            if not matches(name) then return end
            o.casts = o.casts or {}
            o.casts[#o.casts + 1] = ("%s: %s (spell %s) %s; target %s, mouseover %s; vignettes: %s"):format(date("%H:%M:%S"),
                show(name), show(c), here(), show(call(UnitName, "target")), show(call(UnitName, "mouseover")),
                table.concat(vignettes(), " | "))
            ns.Print(("Skysight probe: %s recorded where you stand."):format(show(name)))
        else
            o.vignetteEvents = o.vignetteEvents or {}
            if #o.vignetteEvents < 80 then
                o.vignetteEvents[#o.vignetteEvents + 1] = ("%s %s %s %s; %s"):format(date("%H:%M:%S"), event, show(a), show(b),
                    table.concat(vignettes(), " | "))
            end
        end
    end)
end

function SP.Command()
    snapshot()
    listen()
    ns.Print("Skysight probe: recorded what the game gives here. Now go to a Convergence of Elements and use Skysight there (one or two); then /reload to save it.")
end
