-- Diagnostics/RaidProbe.lua
-- "/suu probe raid" (asked 2026-10-19: a raid planner that arranges the real
-- raid into saved groups; the build waits on it): what Forever lets an addon
-- read and change about a raid's groups.
--   now:     whether you lead or assist, the roster (every GetRaidRosterInfo
--            return and how many there are, each member's role), which
--            group functions exist, and the client's documentation for them
--            with what it says of their restrictions
--   move:    one member (the last one that isn't you, in a group that isn't
--            full) to another group with room (SetRaidSubgroup): first from
--            the chat command, then once more from a button's click
--   swap:    two members of different groups traded (SwapRaidSubgroup), the
--            same two ways
--   burst:   three SetRaidSubgroup moves in one frame: how many land
--   inspect: an inspect of your target: what it gives for talents, how long
--            INSPECT_READY takes, and whether it works out of range
-- Each test records whether the call errored, whether the game blocked it
-- (ADDON_ACTION_BLOCKED or _FORBIDDEN), when GROUP_ROSTER_UPDATE came and
-- whether the groups really changed (at the first update and after 2 s).
-- Nothing is moved in combat. Saved in SuuUIProbe.raid on /reload. Values
-- the game hides read SECRET.
--
--   /suu probe raid           the roster and the documentation
--   /suu probe raid move      move one member
--   /suu probe raid swap      swap two members
--   /suu probe raid burst     three moves at once
--   /suu probe raid inspect   inspect your target

local _, ns = ...

local RP = {}
ns.RaidProbe = RP

local isSecret = issecretvalue or function() return false end
local function show(v)
    if isSecret(v) then return "SECRET" end
    return tostring(v)
end

-- A function that may not exist, may error or may answer secret.
local function call(fn, ...)
    if type(fn) ~= "function" then return "missing" end
    local ok, a, b, c, d = pcall(fn, ...)
    if not ok then return "error: " .. tostring(a):sub(1, 120) end
    return a, b, c, d
end

-- Every return of a call, shown, and how many there were.
local function pack(ok, ...) return ok, select("#", ...), { ... } end
local function every(fn, ...)
    if type(fn) ~= "function" then return "missing", 0 end
    local ok, n, res = pack(pcall(fn, ...))
    if not ok then return "error: " .. tostring(res[1]):sub(1, 120), 0 end
    local parts = {}
    for i = 1, n do parts[i] = show(res[i]) end
    return table.concat(parts, ", "), n
end

local function plain(v) return v ~= nil and not isSecret(v) end

local function out()
    SuuUIProbe = SuuUIProbe or {}
    SuuUIProbe.raid = SuuUIProbe.raid or {}
    return SuuUIProbe.raid
end

local GROUPS = NUM_RAID_GROUPS or 8
local FUNCTIONS = { "SetRaidSubgroup", "SwapRaidSubgroup", "ConvertToRaid", "ConvertToParty", "GetRaidRosterInfo",
    "PromoteToAssistant", "DemoteAssistant", "SetEveryoneIsAssistant", "IsEveryoneAssistant", "NotifyInspect",
    "ClearInspectPlayer", "CanInspect", "GetInspectSpecialization", "GetTalentTabInfo", "GetNumTalentTabs" }

--------------------------------------------------------------------------------
-- The roster
--------------------------------------------------------------------------------

-- The roster as plain values (members whose name or group is secret are
-- left out), and how many are in each group.
local function roster()
    local list, counts = {}, {}
    for g = 1, GROUPS do counts[g] = 0 end
    local n = call(GetNumGroupMembers)
    if not (type(n) == "number" and plain(n)) then return list, counts end
    for i = 1, n do
        local name, _, group = call(GetRaidRosterInfo, i)
        if type(name) == "string" and plain(name) and type(group) == "number" and plain(group) then
            local okMe, me = pcall(UnitIsUnit, "raid" .. i, "player")
            list[#list + 1] = { index = i, name = name, group = group, me = okMe and plain(me) and me == true }
            counts[group] = (counts[group] or 0) + 1
        end
    end
    return list, counts
end

-- Each named member's group now (by name: the indexes may change with the roster).
local function groupsOf(members)
    local list = roster()
    local at = {}
    for _, m in ipairs(list) do at[m.name] = m.group end
    local now = {}
    for i, m in ipairs(members) do now[i] = m.name .. " in " .. show(at[m.name]) end
    return now, at
end

local function snapshot()
    local o = out()
    local s = { at = date("%H:%M:%S"), inRaid = show(call(IsInRaid)), inGroup = show(call(IsInGroup)),
        leader = show(call(UnitIsGroupLeader, "player")), assistant = show(call(UnitIsGroupAssistant, "player")),
        everyoneAssistant = show(call(IsEveryoneAssistant)), members = show(call(GetNumGroupMembers)),
        inCombat = InCombatLockdown() and true or false, api = {}, roster = {} }
    for _, name in ipairs(FUNCTIONS) do s.api[name] = type(_G[name]) == "function" and "yes" or "missing" end
    local P = C_PartyInfo or {}
    for _, name in ipairs({ "ConvertToRaid", "ConvertToParty", "SetRaidSubgroup", "SwapRaidSubgroup" }) do
        s.api["C_PartyInfo." .. name] = type(P[name]) == "function" and "yes" or "missing"
    end
    -- every return of GetRaidRosterInfo, so the planner knows what it has
    local n = call(GetNumGroupMembers)
    if type(n) == "number" and plain(n) and call(IsInRaid) == true then
        for i = 1, n do
            local text, count = every(GetRaidRosterInfo, i)
            s.roster[i] = ("raid%d: %d returns: %s; role %s"):format(i, count, text,
                show(call(UnitGroupRolesAssigned, "raid" .. i)))
        end
    end
    o.now = s
    -- the documentation, and what it says beyond the types
    if ns.ApiDocs and ns.ApiDocs.Dump then
        local lines, err = ns.ApiDocs.Dump({ "subgroup", "raidroster", "rosterinfo", "converttoraid", "converttoparty", "assistant" })
        o.docs = lines or err
        local flags, ferr = ns.ApiDocs.Flags(FUNCTIONS)
        o.docFlags = flags or ferr
    end
    return s
end

--------------------------------------------------------------------------------
-- Moving members
--------------------------------------------------------------------------------

-- The first group other than `except` with room, from group 1.
local function roomIn(counts, except)
    for g = 1, GROUPS do
        if g ~= except and (counts[g] or 0) < 5 then return g end
    end
end

-- The last member who isn't you (or in `skip`), in a group that isn't full,
-- and a group they can go to.
local function pickMove(list, counts, skip)
    for i = #list, 1, -1 do
        local m = list[i]
        if not m.me and not (skip and skip[m.name]) and counts[m.group] < 5 then
            local to = roomIn(counts, m.group)
            if to then return m, to end
        end
    end
end

local test -- the test waiting for its answer
local listener, again
local inspectReady

local function finish(t)
    if test ~= t then return end
    test = nil
    local o = out()
    local now, at = groupsOf(t.members)
    t.after2s = now
    local landed = 0
    for _, m in ipairs(t.members) do
        if at[m.name] == m.to then landed = landed + 1 end
    end
    t.landed = ("%d of %d"):format(landed, #t.members)
    t.started = nil
    o.tests = o.tests or {}
    o.tests[#o.tests + 1] = t
    ns.Print(("Raid probe: %s (%s): %s landed, %d blocked, %d roster updates."):format(t.kind, t.via, t.landed,
        #t.blocked, #t.rosterUpdates))
end

local function listen()
    if listener then return end
    listener = CreateFrame("Frame")
    for _, e in ipairs({ "GROUP_ROSTER_UPDATE", "ADDON_ACTION_BLOCKED", "ADDON_ACTION_FORBIDDEN", "UI_ERROR_MESSAGE", "INSPECT_READY" }) do
        pcall(listener.RegisterEvent, listener, e)
    end
    listener:SetScript("OnEvent", function(_, event, a, b)
        if event == "INSPECT_READY" then return inspectReady(a) end
        local t = test
        if not t then return end
        local dt = ("%.2f s"):format(GetTime() - t.started)
        if event == "GROUP_ROSTER_UPDATE" then
            t.rosterUpdates[#t.rosterUpdates + 1] = dt
            if not t.atFirstUpdate then t.atFirstUpdate = (groupsOf(t.members)) end
        elseif event == "UI_ERROR_MESSAGE" then
            t.uiErrors[#t.uiErrors + 1] = dt .. " " .. show(a) .. " " .. show(b)
        else
            -- anyone's, marked when it is SuuUI's
            t.blocked[#t.blocked + 1] = ("%s %s %s %s%s"):format(dt, event, show(a), show(b), a == ns.name and " (SuuUI)" or "")
        end
    end)
end

-- One test: which members, to where, and the calls that move them.
local function plan(kind, list, counts)
    local members, calls = {}, {}
    if kind == "move" then
        local m, to = pickMove(list, counts)
        if m then
            members[1] = { name = m.name, from = m.group, to = to }
            calls[1] = { label = ("SetRaidSubgroup(%d, %d)"):format(m.index, to), fn = SetRaidSubgroup, args = { m.index, to } }
        end
    elseif kind == "swap" then
        -- two others if there are; else you and another (a raid of two)
        local a, b
        for _, withMe in ipairs({ false, true }) do
            a, b = nil, nil
            for i = #list, 1, -1 do
                local m = list[i]
                if withMe or not m.me then
                    if not a then a = m elseif m.group ~= a.group then b = m break end
                end
            end
            if b then break end
        end
        if a and b then
            members[1] = { name = a.name, from = a.group, to = b.group }
            members[2] = { name = b.name, from = b.group, to = a.group }
            calls[1] = { label = ("SwapRaidSubgroup(%d, %d)"):format(a.index, b.index), fn = SwapRaidSubgroup, args = { a.index, b.index } }
        end
    elseif kind == "burst" then
        local skip = {}
        for _ = 1, 3 do
            local m, to = pickMove(list, counts, skip)
            if not m then break end
            skip[m.name] = true
            counts[m.group] = counts[m.group] - 1
            counts[to] = counts[to] + 1
            members[#members + 1] = { name = m.name, from = m.group, to = to }
            calls[#calls + 1] = { label = ("SetRaidSubgroup(%d, %d)"):format(m.index, to), fn = SetRaidSubgroup, args = { m.index, to } }
        end
        -- fewer than three to move (a small raid): the last one on again, group
        -- after group, in the same frame; landed means it reached the last
        local last = members[#members]
        while last and #calls < 3 do
            local to
            for g = last.to + 1, GROUPS do
                if (counts[g] or 0) < 5 then to = g break end
            end
            if not to then break end
            counts[last.to] = counts[last.to] - 1
            counts[to] = counts[to] + 1
            local index = calls[#calls].args[1]
            calls[#calls + 1] = { label = ("SetRaidSubgroup(%d, %d) again"):format(index, to), fn = SetRaidSubgroup, args = { index, to } }
            last.to = to
        end
    end
    return members, calls
end

local function run(kind, via)
    if InCombatLockdown() then
        ns.Print("Raid probe: not in combat. Moving raid members waits until the fight is over; try again then.")
        return
    end
    if call(IsInRaid) ~= true then
        ns.Print("Raid probe: you're not in a raid. Make one (you as leader or assistant, a few members) and try again.")
        return
    end
    if test then
        ns.Print("Raid probe: the last test is still waiting for its answer (2 s).")
        return
    end
    local list, counts = roster()
    local members, calls = plan(kind, list, counts)
    if #calls == 0 then
        ns.Print(kind == "swap"
            and "Raid probe: no two members (other than you) in different groups to swap."
            or "Raid probe: no member (other than you) with a group that has room to go to.")
        return
    end
    local t = { kind = kind, via = via, at = date("%H:%M:%S"),
        leader = show(call(UnitIsGroupLeader, "player")), assistant = show(call(UnitIsGroupAssistant, "player")),
        members = members, calls = {}, blocked = {}, uiErrors = {}, rosterUpdates = {} }
    for _, m in ipairs(members) do t.calls[#t.calls + 1] = ("%s: group %d to %d"):format(m.name, m.from, m.to) end
    listen()
    test = t
    t.started = GetTime()
    -- all in this frame (the burst's point)
    for _, c in ipairs(calls) do
        local ok, err = pcall(c.fn, unpack(c.args))
        t.calls[#t.calls + 1] = c.label .. ": " .. (ok and "ran" or ("error: " .. tostring(err):sub(1, 120)))
    end
    C_Timer.After(2, function() finish(t) end)
    if t.leader ~= "true" and t.assistant ~= "true" then
        ns.Print("Raid probe: you're neither leader nor assistant; tried anyway, to record what the game says.")
    end
    return t
end

-- The same test once more, from a button's click (a hardware event).
local function offerClick(kind)
    local b = again or CreateFrame("Button", nil, UIParent, "UIPanelButtonTemplate")
    again = b
    b:SetSize(320, 30)
    b:ClearAllPoints()
    b:SetPoint("CENTER", UIParent, "CENTER", 0, 160)
    b:SetFrameStrata("DIALOG")
    b:SetText(("Raid probe: click to %s again"):format(kind))
    b:SetScript("OnClick", function(self)
        if run(kind, "button click") then self:Hide() end
    end)
    b:Show()
end

--------------------------------------------------------------------------------
-- Inspecting a raid member
--------------------------------------------------------------------------------

-- Constants.TraitConsts.INSPECT_TRAIT_CONFIG_ID: the inspected player's
-- talents, as SuuUI's Talents window reads them (after INSPECT_READY).
local INSPECT_CONFIG = Constants and Constants.TraitConsts and Constants.TraitConsts.INSPECT_TRAIT_CONFIG_ID or -1
local inspecting

-- What the inspect gives for talents and spec, read as the Talents window does.
local function talentsOf(unit)
    local s = { hasValidData = show(call(C_Traits and C_Traits.HasValidInspectData)),
        spec = show(call(GetInspectSpecialization, unit)), itemLevel = show(call(C_PaperDollInfo and C_PaperDollInfo.GetInspectItemLevel, unit)),
        tabs = show(call(GetNumTalentTabs, true)) }
    -- the old talent tabs, for the inspected player
    s.talentTabs = {}
    for i = 1, 3 do s.talentTabs[i] = (every(GetTalentTabInfo, i, true)) end
    -- the trait tree: its groups' points and how many nodes have ranks
    local info = C_Traits and call(C_Traits.GetConfigInfo, INSPECT_CONFIG)
    local treeID = type(info) == "table" and info.treeIDs and info.treeIDs[1]
    s.configType = type(info) == "table" and show(info.type) or show(info)
    s.treeID = show(treeID)
    if type(treeID) == "number" then
        local displays = call(C_Traits.GetGroupDisplayInfoByTreeID, treeID)
        local ids, names = {}, {}
        if type(displays) == "table" then
            for i, d in ipairs(displays) do ids[i] = d.groupID; names[d.groupID] = show(d.displayName) end
        end
        s.groups = {}
        local groups = #ids > 0 and call(C_Traits.GetGroupCurrencyInfo, INSPECT_CONFIG, ids)
        if type(groups) == "table" then
            for _, g in ipairs(groups) do
                local c = g.currencyInfos and g.currencyInfos[1]
                s.groups[#s.groups + 1] = ("%s: spent %s"):format(names[g.traitNodeGroupID] or show(g.traitNodeGroupID), c and show(c.spent) or "?")
            end
        else
            s.groups = show(groups)
        end
        local nodes = call(C_Traits.GetTreeNodes, treeID)
        local ranked, total, secret = 0, 0, 0
        if type(nodes) == "table" then
            for _, nodeID in ipairs(nodes) do
                local ni = call(C_Traits.GetNodeInfo, INSPECT_CONFIG, nodeID)
                if type(ni) == "table" then
                    total = total + 1
                    local r = ni.activeRank or ni.currentRank
                    if isSecret(r) then secret = secret + 1 elseif type(r) == "number" and r > 0 then ranked = ranked + 1 end
                end
            end
        end
        s.nodes = ("%d nodes, %d with ranks, %d secret"):format(total, ranked, secret)
    end
    return s
end

inspectReady = function(guid)
    local t = inspecting
    if not t then return end
    local okG, target = pcall(UnitGUID, t.unit)
    if not (okG and plain(target) and plain(guid) and target == guid) then
        t.otherReady = (t.otherReady or 0) + 1
        return
    end
    inspecting = nil
    t.ready = ("%.2f s"):format(GetTime() - t.started)
    t.talents = talentsOf(t.unit)
    t.started = nil
    -- the game's inspect window keeps its player; this one is let go
    if not (_G.InspectFrame and _G.InspectFrame:IsShown()) then call(ClearInspectPlayer) end
    ns.Print(("Raid probe: INSPECT_READY after %s; what it gave is recorded. /reload to save it."):format(t.ready))
end

local function inspect()
    local unit = "target"
    if not UnitExists(unit) or not UnitIsPlayer(unit) then
        ns.Print("Raid probe: target a player first (a raid member; one near you, then one far away).")
        return
    end
    local o = out()
    o.inspects = o.inspects or {}
    local okN, name = pcall(GetUnitName, unit, true)
    local t = { at = date("%H:%M:%S"), unit = unit, name = okN and show(name) or "?",
        inRaid = show(call(UnitInRaid, unit)), canInspect = show(call(CanInspect, unit)),
        visible = show(call(UnitIsVisible, unit)), connected = show(call(UnitIsConnected, unit)),
        inRange = (every(UnitInRange, unit)), interact = show(call(CheckInteractDistance, unit, 1)),
        inCombat = InCombatLockdown() and true or false }
    listen()
    inspecting = t
    t.started = GetTime()
    local ok, err = pcall(NotifyInspect, unit)
    t.notify = ok and "called" or ("error: " .. tostring(err):sub(1, 120))
    o.inspects[#o.inspects + 1] = t
    C_Timer.After(10, function()
        if inspecting == t then
            inspecting = nil
            t.ready = "no INSPECT_READY in 10 s"
            t.talents = talentsOf(unit)
            t.started = nil
            ns.Print("Raid probe: no INSPECT_READY for your target in 10 s; recorded. /reload to save it.")
        end
    end)
    ns.Print(("Raid probe: inspecting %s (in range: %s); waiting for INSPECT_READY."):format(t.name, t.inRange))
end

function RP.Command(arg)
    if arg == "inspect" then return inspect() end
    if arg == "move" or arg == "swap" or arg == "burst" then
        snapshot()
        local t = run(arg, "chat command (no button click)")
        if not t then return end
        if arg == "burst" then
            ns.Print(("Raid probe: %d moves sent in one frame; the answer in 2 s."):format(#t.members))
        else
            offerClick(arg)
            ns.Print(("Raid probe: %s sent from this chat command; the answer in 2 s. Then click the button above the middle to %s again from a click; then /reload."):format(arg, arg))
        end
        return
    end
    local s = snapshot()
    ns.Print(("Raid probe: %s members recorded (leader %s, assistant %s). In a raid you lead, try /suu probe raid move, swap and burst, and /suu probe raid inspect on a member; then /reload to save it."):format(
        s.members, s.leader, s.assistant))
end
