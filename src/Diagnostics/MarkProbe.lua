-- Diagnostics/MarkProbe.lua
-- "/suu probe marks": what your own map marks (3.5, stage 3) can build on.
-- Saved in SuuUIProbe.marks on /reload. Out of combat, outdoors.
--   * the game's user waypoint: set one where you stand, read it back, its
--     chat link, super-tracking it (the navigation arrow), then your own
--     waypoint as it was
--   * positions: yours on the map and in the world, the map/world
--     conversions both ways, your facing (secret or not)
--   * the minimap: its map, view radius, zoom, rotation, size
--   * addon messages: a prefix, and one whispered to yourself (does it come
--     back? within 3 s)

local _, ns = ...

local KP = {}
ns.MarkProbe = KP

local isSecret = issecretvalue or function() return false end

local function show(v, depth)
    depth = depth or 0
    if isSecret(v) then return "<secret>" end
    if type(v) ~= "table" then return tostring(v) end
    if depth > 1 then return "{…}" end
    local parts = {}
    for k, x in pairs(v) do
        if type(x) ~= "function" then
            parts[#parts + 1] = tostring(k) .. "=" .. (isSecret(x) and "<secret>" or (type(x) == "table" and show(x, depth + 1) or tostring(x)))
        end
    end
    table.sort(parts)
    return "{" .. table.concat(parts, ", ") .. "}"
end

local function call(t, name, ...)
    if not (t and type(t[name]) == "function") then return "missing" end
    local ok, a, b, c, d = pcall(t[name], ...)
    if not ok then return "error: " .. tostring(a) end
    return a, b, c, d
end

local function xy(v)
    if type(v) == "table" and v.GetXY then
        local ok, x, y = pcall(v.GetXY, v)
        if ok then return show({ x, y }) end
    end
    return show(v)
end

function KP.Snapshot()
    SuuUIProbe = SuuUIProbe or {}
    local s = { at = date("%Y-%m-%d %H:%M:%S"), combat = InCombatLockdown() }
    SuuUIProbe.marks = s
    local cm = C_Map

    -- where you are
    local map = call(cm, "GetBestMapForUnit", "player")
    s.mapID = show(map)
    local pos = type(map) == "number" and call(cm, "GetPlayerMapPosition", map, "player")
    s.mapPosition = xy(pos)
    s.unitPosition = show({ call(_G, "UnitPosition", "player") })
    s.facing = show((call(_G, "GetPlayerFacing")))

    -- map <-> world
    if type(pos) == "table" then
        local continent, world = call(cm, "GetWorldPosFromMapPos", map, pos)
        s.worldFromMap = show(continent) .. " " .. xy(world)
        if type(continent) == "number" and type(world) == "table" then
            local backMap, back = call(cm, "GetMapPosFromWorldPos", continent, world, map)
            s.mapFromWorld = show(backMap) .. " " .. xy(back)
        end
    end

    -- the user waypoint: yours as it was, one where you stand, back
    local had = call(cm, "GetUserWaypoint")
    s.waypointBefore = show(had)
    s.canSet = show((type(map) == "number" and call(cm, "CanSetUserWaypointOnMap", map)))
    if type(map) == "number" and type(pos) == "table" and UiMapPoint and UiMapPoint.CreateFromVector2D then
        local point = UiMapPoint.CreateFromVector2D(map, pos)
        s.set = show((call(cm, "SetUserWaypoint", point)))
        s.has = show((call(cm, "HasUserWaypoint")))
        s.waypoint = show((call(cm, "GetUserWaypoint")))
        local link = call(cm, "GetUserWaypointHyperlink")
        s.link = show(link)
        -- (its parts, with the pipes made visible)
        s.linkEscaped = type(link) == "string" and link:gsub("|", "||") or show(link)
        if type(link) == "string" then
            s.fromLink = show((call(cm, "GetUserWaypointFromHyperlink", link)))
        end
        local st = C_SuperTrack
        s.superTrackBefore = show((call(st, "IsSuperTrackingUserWaypoint")))
        s.superTrackSet = show((call(st, "SetSuperTrackedUserWaypoint", true)))
        s.superTracking = show((call(st, "IsSuperTrackingUserWaypoint")))
        call(st, "SetSuperTrackedUserWaypoint", false)
        -- yours back as it was
        if type(had) == "table" then call(cm, "SetUserWaypoint", had) else call(cm, "ClearUserWaypoint") end
        s.waypointAfter = show((call(cm, "GetUserWaypoint")))
    else
        s.set = "skipped (no map, position or UiMapPoint)"
    end

    -- the minimap
    local mm = C_Minimap
    s.minimap = {
        uiMap = show((call(mm, "GetUiMapID"))),
        viewRadius = show((call(mm, "GetViewRadius"))),
        zoom = show((call(_G.Minimap, "GetZoom", _G.Minimap))),
        zoomLevels = show((call(_G.Minimap, "GetZoomLevels", _G.Minimap))),
        size = _G.Minimap and (math.floor(_G.Minimap:GetWidth()) .. "x" .. math.floor(_G.Minimap:GetHeight())) or "none",
        rotate = show((call(_G, "GetCVar", "rotateMinimap"))),
        indoors = show((call(_G, "IsIndoors"))),
    }

    -- addon messages: a prefix, one whispered to yourself
    local chat = C_ChatInfo
    s.prefix = show((call(chat, "RegisterAddonMessagePrefix", "SuuUIProbe")))
    local name, realm = UnitFullName("player")
    local me = name and realm and realm ~= "" and (name .. "-" .. realm) or name
    s.addonWhisperTo = show(me)
    s.addonReceived = "no (waited 3 s)"
    local f = KP.frame or CreateFrame("Frame")
    KP.frame = f
    f:RegisterEvent("CHAT_MSG_ADDON")
    f:SetScript("OnEvent", function(_, _, prefix, text, channel, sender)
        if prefix == "SuuUIProbe" then
            s.addonReceived = show({ text = text, channel = channel, sender = sender })
            f:UnregisterAllEvents()
        end
    end)
    s.addonSend = show({ call(chat, "SendAddonMessage", "SuuUIProbe", "mark:test", "WHISPER", me) })
    C_Timer.After(3, function()
        f:UnregisterAllEvents()
        ns.Print("Mark probe: done; /reload saves it.")
    end)
    ns.Print(("Mark probe: waypoint %s, link %s, world %s; waiting 3 s for the addon message…"):format(
        s.set, type(s.link) == "string" and s.link ~= "nil" and "yes" or "no", s.worldFromMap and "yes" or "no"))
end

-- "/suu probe marks nav": with a mark's Show the way on, what the game's
-- navigation does (its setting, its frame, the on-screen indicator).
function KP.Nav()
    SuuUIProbe = SuuUIProbe or {}
    local s = { at = date("%Y-%m-%d %H:%M:%S") }
    SuuUIProbe.marksNav = s
    s.cvar = show((call(_G, "GetCVar", "showInGameNavigation")))
    s.cvarDefault = show((call(_G, "GetCVarDefault", "showInGameNavigation")))
    s.hasWaypoint = show((call(C_Map, "HasUserWaypoint")))
    s.superTrackingWaypoint = show((call(C_SuperTrack, "IsSuperTrackingUserWaypoint")))
    s.superTrackingAnything = show((call(C_SuperTrack, "IsSuperTrackingAnything")))
    s.highestType = show((call(C_SuperTrack, "GetHighestPrioritySuperTrackingType")))
    local nav = C_Navigation
    s.navExists = nav ~= nil
    s.navFrame = show((call(nav, "GetFrame")))
    s.distance = show((call(nav, "GetDistance")))
    s.targetState = show((call(nav, "GetTargetState")))
    s.validScreen = show((call(nav, "HasValidScreenPosition")))
    s.wasClamped = show((call(nav, "WasClampedToScreen")))
    local f = _G.SuperTrackedFrame
    s.frame = f and { shown = f:IsShown(), visible = f:IsVisible(), alpha = f:GetAlpha(),
        parent = f:GetParent() and (f:GetParent():GetName() or "?") or "none",
        effAlpha = f:GetEffectiveAlpha() } or "no SuperTrackedFrame"
    s.loaded = show((call(C_AddOns, "IsAddOnLoaded", "Blizzard_QuestNavigation")))
    ns.Print(("Navigation: setting %s, frame %s, distance %s, indicator %s; /reload saves it."):format(
        s.cvar, s.navFrame, s.distance, type(s.frame) == "table" and (s.frame.visible and "visible" or "hidden") or "none"))
end

function KP.Command(rest)
    if rest == "nav" then KP.Nav() return end
    if InCombatLockdown() then
        ns.Print("Mark probe: out of combat, please.")
        return
    end
    KP.Snapshot()
end
