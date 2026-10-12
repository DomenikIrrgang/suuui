-- Core/Roles.lua
-- Your role, and profiles by role. The role is the one you chose for this
-- character, else the one assigned to you (role check, group finder), else
-- your talents: the tree with the most points, read as a role per class.
-- Each role can name a profile (Profiles.RoleProfile); when your role
-- changes, SuuUI switches to that profile, out of combat only. A profile you
-- pick by hand stays until the role changes again, across reloads too: the
-- role last switched for is saved per character.
--
--   ns.Roles.Current()   -> "TANK" | "HEALER" | "DAMAGER", and where it came
--                           from: "chosen", "assigned" or "talents"
--   ns.Roles.Spec()      -> the talent tree with the most points (1-3), 0
--                           with none spent, and the points per tree

local _, ns = ...

local Roles = {}
ns.Roles = Roles

local Events, Profiles, Combat = ns.Events, ns.Profiles, ns.Combat

local isSecret = issecretvalue or function() return false end
local _, CLASS = UnitClass("player")

-- Each class's trees, left to right, as roles. Feral counts as damage (cat
-- and bear share the tree): bear tanks choose Tank for the character.
local TREE_ROLE = {
    DRUID = { "DAMAGER", "DAMAGER", "HEALER" },
    PALADIN = { "HEALER", "TANK", "DAMAGER" },
    PRIEST = { "HEALER", "HEALER", "DAMAGER" },
    SHAMAN = { "DAMAGER", "DAMAGER", "HEALER" },
    WARRIOR = { "DAMAGER", "DAMAGER", "TANK" },
}

Roles.LABEL = { TANK = "Tank", HEALER = "Healer", DAMAGER = "DPS" }

-- Points per tree. Forever lays the three trees out side by side in one, so
-- they are told apart by position (posX in thirds; far-off nodes excluded).
local function treePoints()
    local cfg = C_ClassTalents and C_ClassTalents.GetActiveConfigID and C_ClassTalents.GetActiveConfigID()
    local info = cfg and C_Traits and C_Traits.GetConfigInfo(cfg)
    if not (info and info.treeIDs) then return { 0, 0, 0 }, 0 end
    local nodes = {}
    for _, treeID in ipairs(info.treeIDs) do
        for _, nodeID in ipairs(C_Traits.GetTreeNodes(treeID) or {}) do
            local ni = C_Traits.GetNodeInfo(cfg, nodeID)
            if ni and ni.posX and ni.posX < 20000 then
                nodes[#nodes + 1] = { x = ni.posX, ranks = ni.ranksPurchased or ni.activeRank or ni.currentRank or 0 }
            end
        end
    end
    if #nodes == 0 then return { 0, 0, 0 }, 0 end
    local lo, hi = math.huge, -math.huge
    for _, n in ipairs(nodes) do lo, hi = math.min(lo, n.x), math.max(hi, n.x) end
    local third = (hi - lo) / 3
    local pts, total = { 0, 0, 0 }, 0
    for _, n in ipairs(nodes) do
        local r = isSecret(n.ranks) and 0 or (n.ranks or 0)
        local tree = (n.x < lo + third and 1) or (n.x < lo + 2 * third and 2) or 3
        pts[tree] = pts[tree] + r
        total = total + r
    end
    return pts, total
end

function Roles.Spec()
    local ok, pts, total = pcall(treePoints)
    if not ok or total == 0 then return 0, ok and pts or { 0, 0, 0 } end
    local best = 1
    for t = 2, 3 do if pts[t] > pts[best] then best = t end end
    return best, pts
end

function Roles.Current()
    local chosen = Profiles.ChosenRole()
    if chosen ~= "auto" and Roles.LABEL[chosen] then return chosen, "chosen" end
    local assigned = UnitGroupRolesAssigned and UnitGroupRolesAssigned("player")
    if assigned and not isSecret(assigned) and Roles.LABEL[assigned] then return assigned, "assigned" end
    local spec = Roles.Spec()
    local roles = TREE_ROLE[CLASS]
    return (roles and roles[spec]) or "DAMAGER", "talents"
end

-- Switches to the role's profile when the role differs from the one saved
-- for this character (or when `force`: a mapping or role choice changed), and
-- tells everyone when the spec or role changed (SUUUI_SPEC_CHANGED,
-- SUUUI_ROLE_CHANGED).
local lastRole, lastSpec
local function apply(force)
    local spec = Roles.Spec()
    if spec ~= lastSpec then
        lastSpec = spec
        Events.Emit("SUUUI_SPEC_CHANGED", spec)
    end
    local role, source = Roles.Current()
    -- Right after login the talents can read as unspent for a moment: a
    -- character past level 10 with no tree read is that, not a real DPS role.
    -- Wait for the talent events instead of switching away and back.
    if source == "talents" and spec == 0 and UnitLevel("player") >= 10 then return end
    if role ~= lastRole then
        lastRole = role
        Events.Emit("SUUUI_ROLE_CHANGED", role)
    end
    if role == Profiles.LastRole() and not force then return end
    Profiles.SetLastRole(role)
    local name = Profiles.RoleProfile(role)
    if not name or name == Profiles.Current() then return end
    Combat.Run("roleProfile", function()
        -- the role may have changed again while combat lasted
        local now = Profiles.RoleProfile(Roles.Current())
        if now and now ~= Profiles.Current() and Profiles.Use(now) then
            ns.Print(("%s role: switched to the profile %s."):format(Roles.LABEL[Roles.Current()], now))
        end
    end, "Profiles by role")
end

-- Events come in bursts (a roster update fires several); settle first. A
-- forced check stays forced when an unforced one is already waiting.
local pending, pendingForce = false, false
local function soon(force)
    pendingForce = pendingForce or force == true
    if pending then return end
    pending = true
    C_Timer.After(0.5, function()
        local f = pendingForce
        pending, pendingForce = false, false
        apply(f)
    end)
end

local valid = C_EventUtils and C_EventUtils.IsEventValid
local function on(event, fn)
    if not valid or valid(event) then Events.OnGame(event, fn, "Roles") end
end

Events.On("SUUUI_SETTINGS_READY", function()
    on("PLAYER_ENTERING_WORLD", function() soon() end)
    for _, e in ipairs({ "PLAYER_ROLES_ASSIGNED", "GROUP_ROSTER_UPDATE", "TRAIT_CONFIG_UPDATED", "TRAIT_NODE_CHANGED",
                         "PLAYER_TALENT_UPDATE", "CHARACTER_POINTS_CHANGED", "ACTIVE_PLAYER_SPECIALIZATION_CHANGED" }) do
        on(e, function() soon() end)
    end
    -- a new mapping or role choice applies at once
    Events.On("SUUUI_ROLE_PROFILES_CHANGED", function() soon(true) end, "Roles")
end, "Roles")
