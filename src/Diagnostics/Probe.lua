-- Diagnostics/Probe.lua
-- /suu probe: reports which client APIs, frames and Blizzard addons the design
-- depends on exist on this client, and which unit values are secret right now.
--
-- The report opens in a copyable window and is saved to SuuUIProbe, so it can
-- be read from WTF\...\SavedVariables\SuuUI.lua after a /reload. API results
-- are overwritten on every run; the secret-value samples are kept per context
-- (combat or not, instance type, group type), so running it in a dungeon pull
-- adds to what a run in the open world found.
--
-- Read-only by design: it never calls anything that changes game state, and
-- it never compares or stores a value that might be secret, only the boolean
-- issecretvalue() returns for it.

local _, ns = ...

--------------------------------------------------------------------------------
-- What to check, grouped by the part of the design that depends on it
--
-- Item kinds:
--   api    a function at a dotted path
--   ns     a C_ namespace; reports how many functions it has
--   frame  a global frame
--   addon  a Blizzard addon: loaded, on demand or absent
--   enum   an Enum table; reports how many values it has
--   method a widget method, { widgetType, methodName }
--   scan   globals and Enum names containing any of `find` (case-insensitive),
--          minus any containing one of `skip`; `within` limits it to one
--          namespace's functions
--------------------------------------------------------------------------------

local SECTIONS = {
    { title = "Client", items = {
        { scan = "Game type APIs", find = { "gamerules", "gamemode", "loadgametype", "gametype" } },
    } },
    { title = "Secret values", items = {
        { api = "issecretvalue" },
        { api = "canaccessvalue" },
        { api = "issecrettable" },
        { api = "UnitHealthPercent" },
        { api = "UnitPowerPercent" },
        { api = "C_CurveUtil.CreateColorCurve" },
        { api = "C_CurveUtil.EvaluateColorValueFromBoolean" },
        { api = "C_DurationUtil.CreateDuration" },
        { method = { "Texture", "SetAlphaFromBoolean" } },
        { method = { "Texture", "SetVertexColorFromBoolean" } },
        { method = { "StatusBar", "SetTimerDuration" } },
        { method = { "Cooldown", "SetCooldownFromDurationObject" } },
    } },
    { title = "Unit frames and auras", items = {
        { api = "CreateUnitHealPredictionCalculator" },
        { api = "UnitGetDetailedHealPrediction" },
        { api = "UnitGetIncomingHeals" },
        { api = "UnitGetTotalAbsorbs" },
        { api = "UnitGetTotalHealAbsorbs" },
        { api = "UnitGroupRolesAssigned" },
        { api = "C_UnitAuras.GetAuraDataByIndex" },
        { api = "C_UnitAuras.GetAuraDataByAuraInstanceID" },
        { api = "C_UnitAuras.GetAuraDuration" },
        { scan = "Dispel-type APIs", within = "C_UnitAuras", find = { "dispel" } },
    } },
    { title = "Casts and nameplates", items = {
        { api = "UnitCastingDuration" },
        { api = "UnitChannelDuration" },
        { api = "C_NamePlate.GetNamePlateForUnit" },
        { frame = "NamePlateDriverFrame" },
        { frame = "PlayerCastingBarFrame" },
    } },
    { title = "Threat", items = {
        { api = "UnitThreatSituation" },
        { api = "UnitDetailedThreatSituation" },
        { api = "GetThreatStatusColor" },
    } },
    { title = "Swing timer", items = {
        { ns = "C_SwingTimer" },
        { enum = "PlayerSwingType" },
        { addon = "Blizzard_SwingTimer" },
    } },
    { title = "Cooldown Manager", items = {
        { ns = "C_CooldownViewer" },
        { enum = "CooldownViewerCategory" },
        { addon = "Blizzard_CooldownViewer" },
        { frame = "EssentialCooldownViewer" },
        { frame = "UtilityCooldownViewer" },
        { frame = "BuffIconCooldownViewer" },
        { frame = "BuffBarCooldownViewer" },
    } },
    { title = "Damage meter", items = {
        { ns = "C_DamageMeter" },
        { enum = "DamageMeterType" },
        { enum = "DamageMeterSessionType" },
        { addon = "Blizzard_DamageMeter" },
    } },
    { title = "Encounter timeline", items = {
        { ns = "C_EncounterTimeline" },
        { addon = "Blizzard_EncounterTimeline" },
        { scan = "Timeline APIs", find = { "timeline" } },
    } },
    { title = "Action bars", items = {
        { ns = "C_ActionBar" },
        { api = "C_ActionBar.GetActionCooldownDuration" },
        { enum = "EditModeActionBarSystemIndices" },
        { frame = "MainActionBar" },
        { frame = "MainMenuBar" },
        { frame = "MultiBarBottomLeft" },
        { frame = "MultiBarBottomRight" },
        { frame = "MultiBarRight" },
        { frame = "MultiBarLeft" },
        { frame = "MultiBar5" },
        { frame = "MultiBar6" },
        { frame = "MultiBar7" },
        { frame = "MultiBar8" },
        { frame = "StanceBar" },
        { frame = "PetActionBar" },
    } },
    { title = "Edit Mode", items = {
        { ns = "C_EditMode" },
        { frame = "EditModeManagerFrame" },
    } },
    { title = "Group sync (readiness)", items = {
        { api = "C_ChatInfo.SendAddonMessage" },
        { api = "C_ChatInfo.RegisterAddonMessagePrefix" },
        { scan = "Messaging lockdown APIs", within = "C_ChatInfo", find = { "lockdown", "restrict" } },
    } },
    { title = "Loot", items = {
        { ns = "C_LootHistory" },
        { api = "GetLootRollItemInfo" },
        { frame = "GroupLootContainer" },
        { frame = "LootFrame" },
    } },
    { title = "Talents and specializations", items = {
        { api = "GetSpecialization" },
        { ns = "C_SpecializationInfo" },
        { ns = "C_ClassTalents" },
        { ns = "C_Traits" },
        { addon = "Blizzard_PlayerSpells" },
        { addon = "Blizzard_TalentUI" },
    } },
    { title = "Legacy", items = {
        { scan = "Legacy APIs and frames", find = { "legacy" } },
    } },
    { title = "Professions", items = {
        { ns = "C_TradeSkillUI" },
        { ns = "C_ProfSpecs" },
        { addon = "Blizzard_Professions" },
        { addon = "Blizzard_ProfessionsBook" },
    } },
    { title = "Group Finder and social", items = {
        { ns = "C_LFGList" },
        { ns = "C_FriendList" },
        { ns = "C_BattleNet" },
        { ns = "C_Club" },
        { addon = "Blizzard_GroupFinder" },
        { addon = "Blizzard_Communities" },
    } },
    { title = "Map and quests", items = {
        { ns = "C_Map" },
        { api = "C_QuestLog.GetQuestsOnMap" },
        { ns = "C_QuestLine" },
        { ns = "C_TaskQuest" },
        { ns = "C_SuperTrack" },
        { frame = "WorldMapFrame" },
        { frame = "ObjectiveTrackerFrame" },
        { frame = "QuestWatchFrame" },
    } },
    { title = "Campsite", items = {
        { scan = "Camping APIs and frames", find = { "camp", "bonfire" }, skip = { "campaign" } },
    } },
    { title = "Bags, bank and tooltips", items = {
        { ns = "C_Container" },
        { ns = "C_Bank" },
        { api = "TooltipDataProcessor.AddTooltipPostCall" },
        { ns = "C_TooltipInfo" },
        { frame = "ContainerFrameCombinedBags" },
        { frame = "BankFrame" },
    } },
    { title = "Blizzard frames SuuUI will replace", items = {
        { frame = "PlayerFrame" }, { frame = "TargetFrame" }, { frame = "FocusFrame" },
        { frame = "TargetFrameToT" }, { frame = "PetFrame" }, { frame = "PartyFrame" },
        { frame = "CompactRaidFrameContainer" }, { frame = "BossTargetFrameContainer" },
        { frame = "BuffFrame" }, { frame = "DebuffFrame" }, { frame = "MinimapCluster" },
        { frame = "MicroMenuContainer" }, { frame = "BagsBar" }, { frame = "StatusTrackingBarManager" },
        { frame = "ChatFrame1" }, { frame = "StaticPopup1" }, { frame = "AlertFrame" },
        { frame = "CharacterFrame" }, { frame = "SpellBookFrame" }, { frame = "PlayerSpellsFrame" },
        { frame = "FriendsFrame" }, { frame = "GameTooltip" },
    } },
}

-- Widget methods whose names match these are listed in full in the saved data.
local METHOD_HINTS = { "boolean", "duration", "secret", "curve", "timer" }
local METHOD_WIDGETS = { "Frame", "StatusBar", "Cooldown", "Texture", "FontString" }

-- Console variables whose names match these are listed in the saved data.
local CVAR_HINTS = { "swing", "timeline", "damagemeter", "cooldownviewer", "encounter", "camp" }

-- Units sampled for secret values, and the spells whose cooldown is sampled:
-- 29515 is Forever's global cooldown reference, 61304 retail's.
local SAMPLE_UNITS = { "player", "target", "focus", "pet", "party1", "raid1", "boss1", "nameplate1" }
local SAMPLE_SPELLS = { 29515, 61304 }

--------------------------------------------------------------------------------
-- Helpers
--------------------------------------------------------------------------------

local function resolve(path)
    local v = _G
    for part in path:gmatch("[^%.]+") do
        if type(v) ~= "table" then return nil end
        v = v[part]
    end
    return v
end

local function sortedKeys(t, filter)
    local out = {}
    for k, v in pairs(t) do
        if type(k) == "string" and (not filter or filter(k, v)) then
            out[#out + 1] = k
        end
    end
    table.sort(out)
    return out
end

local function functionNames(t)
    return sortedKeys(t, function(_, v) return type(v) == "function" end)
end

local function matchesAny(lower, needles)
    for _, n in ipairs(needles) do
        if lower:find(n, 1, true) then return true end
    end
    return false
end

local function scan(item)
    local function wanted(name)
        local lower = name:lower()
        return matchesAny(lower, item.find) and not (item.skip and matchesAny(lower, item.skip))
    end
    local hits = {}
    if item.within then
        local t = resolve(item.within)
        if type(t) == "table" then
            for _, name in ipairs(functionNames(t)) do
                if wanted(name) then hits[#hits + 1] = item.within .. "." .. name end
            end
        end
        return hits
    end
    for name, v in pairs(_G) do
        local t = type(v)
        if type(name) == "string" and (t == "function" or t == "table")
            and not name:find("^SuuUI") and wanted(name) then
            hits[#hits + 1] = name
        end
    end
    for name in pairs(Enum) do
        if type(name) == "string" and wanted(name) then hits[#hits + 1] = "Enum." .. name end
    end
    table.sort(hits)
    return hits
end

local function addonState(name)
    local ok, exists = pcall(C_AddOns.DoesAddOnExist, name)
    if not ok or not exists then return false, "absent" end
    if C_AddOns.IsAddOnLoaded(name) then return true, "loaded" end
    if C_AddOns.IsAddOnLoadOnDemand and C_AddOns.IsAddOnLoadOnDemand(name) then
        return true, "on demand"
    end
    return true, "present, not loaded"
end

local widgets
local function widget(kind)
    if not widgets then
        local host = CreateFrame("Frame")
        host:Hide()
        widgets = {
            Frame = host,
            StatusBar = CreateFrame("StatusBar", nil, host),
            Cooldown = CreateFrame("Cooldown", nil, host),
            Texture = host:CreateTexture(),
            FontString = host:CreateFontString(),
        }
    end
    return widgets[kind]
end

local function methodsOf(kind)
    local mt = getmetatable(widget(kind))
    local index = mt and mt.__index
    return type(index) == "table" and index or {}
end

local function preview(list, limit)
    if #list <= limit then return table.concat(list, ", ") end
    local head = {}
    for i = 1, limit do head[i] = list[i] end
    return table.concat(head, ", ") .. (", +%d more"):format(#list - limit)
end

--------------------------------------------------------------------------------
-- Checks
--------------------------------------------------------------------------------

-- Returns ok, label, detail for one item; `saved` collects the full lists.
local function check(item, saved)
    if item.api then
        return type(resolve(item.api)) == "function", item.api
    elseif item.ns then
        local t = resolve(item.ns)
        if type(t) ~= "table" then return false, item.ns end
        local names = functionNames(t)
        saved.namespaces[item.ns] = names
        return true, item.ns, ("%d functions"):format(#names)
    elseif item.frame then
        return type(_G[item.frame]) == "table", item.frame
    elseif item.addon then
        local ok, state = addonState(item.addon)
        return ok, item.addon, state
    elseif item.enum then
        local label = "Enum." .. item.enum
        local t = Enum[item.enum]
        if type(t) ~= "table" then return false, label end
        local copy, n = {}, 0
        for k, v in pairs(t) do copy[k] = v; n = n + 1 end
        saved.enums[item.enum] = copy
        return true, label, ("%d values"):format(n)
    elseif item.method then
        local kind, name = item.method[1], item.method[2]
        return type(methodsOf(kind)[name]) == "function", kind .. ":" .. name
    elseif item.scan then
        local hits = scan(item)
        saved.scans[item.scan] = hits
        if #hits == 0 then return false, item.scan, "nothing found" end
        return true, item.scan, preview(hits, 6)
    end
end

local function collectMethods()
    local out = {}
    for _, kind in ipairs(METHOD_WIDGETS) do
        out[kind] = sortedKeys(methodsOf(kind), function(k, v)
            return type(v) == "function" and matchesAny(k:lower(), METHOD_HINTS)
        end)
    end
    return out
end

local function collectCVars()
    if not (C_Console and C_Console.GetAllCommands) then return nil end
    local ok, all = pcall(C_Console.GetAllCommands)
    if not ok or type(all) ~= "table" then return nil end
    local out = {}
    for _, info in ipairs(all) do
        local name = info.command
        if type(name) == "string" and matchesAny(name:lower(), CVAR_HINTS) then
            out[#out + 1] = name
        end
    end
    table.sort(out)
    return out
end

--------------------------------------------------------------------------------
-- Secret-value samples for the current context
--------------------------------------------------------------------------------

local isSecret = issecretvalue or function() return false end
local isSecretTable = issecrettable or function() return false end

local function errText(msg)
    return (tostring(msg):gsub("^Interface\\[^:]*:%d+: ", "")):sub(1, 160)
end

-- "secret", "readable" or "none" for one value; never keeps the value.
local function state(v)
    if isSecret(v) then return "secret" end
    if v == nil then return "none" end
    return "readable"
end

-- The state of every string-keyed field of a table the client returned, or
-- the state of a non-table value.
local function describe(t)
    if isSecret(t) or type(t) ~= "table" then return state(t) end
    if isSecretTable(t) then return "secret table" end
    local out = {}
    local ok, err = pcall(function()
        for k, v in pairs(t) do
            if type(k) == "string" then
                out[k] = isSecret(v) and "secret" or (v == nil and "none" or "readable")
            end
        end
    end)
    if not ok then return "error: " .. errText(err) end
    return out
end

-- Calls fn and describes its first result; errors become "error: <message>".
local function call(fn, ...)
    if type(fn) ~= "function" then return "missing" end
    local ok, v = pcall(fn, ...)
    if not ok then return "error: " .. errText(v) end
    return describe(v)
end

local UNIT_FIELDS = {
    { "name", function(u) return UnitName(u) end },
    { "class", function(u) return (select(2, UnitClass(u))) end },
    { "level", UnitLevel },
    { "classification", UnitClassification },
    { "reaction", function(u) return UnitReaction(u, "player") end },
    { "dead", UnitIsDeadOrGhost },
    { "role", UnitGroupRolesAssigned },
    { "health", UnitHealth },
    { "healthMax", UnitHealthMax },
    { "healthPercent", UnitHealthPercent },
    { "healthPercentScaled", function(u) return UnitHealthPercent(u, true, CurveConstants.ScaleTo100) end },
    { "powerPercentScaled", function(u) return UnitPowerPercent(u, UnitPowerType(u), true, CurveConstants.ScaleTo100) end },
    { "power", UnitPower },
    { "powerType", UnitPowerType },
    { "absorbs", UnitGetTotalAbsorbs },
    { "incomingHeals", UnitGetIncomingHeals },
    { "threat", function(u) return UnitThreatSituation("player", u) end },
    { "castName", UnitCastingInfo },
    { "castNotInterruptible", function(u) return (select(8, UnitCastingInfo(u))) end },
    { "castDuration", UnitCastingDuration },
}

-- The first aura of each filter, read three ways: by index, through the slot
-- API that Blizzard's AuraUtil uses, and as a list.
local function sampleAuras(unit)
    local A = C_UnitAuras or {}
    local out = {}
    for _, filter in ipairs({ "HELPFUL", "HARMFUL" }) do
        out["byIndex " .. filter] = call(A.GetAuraDataByIndex, unit, 1, filter)
        if A.GetAuraSlots then
            local ok, tokenOrError, slot = pcall(A.GetAuraSlots, unit, filter)
            if not ok then
                out["slots " .. filter] = "error: " .. errText(tokenOrError)
            else
                out["slots " .. filter] = state(slot)
                if slot ~= nil and not isSecret(slot) then
                    out["bySlot " .. filter] = call(A.GetAuraDataBySlot, unit, slot)
                end
            end
        end
        if A.GetUnitAuras then
            local ok, list = pcall(A.GetUnitAuras, unit, filter, 1)
            if not ok then
                out["list " .. filter] = "error: " .. errText(list)
            elseif type(list) == "table" and not isSecret(list) and not isSecretTable(list) then
                out["list " .. filter] = describe(list[1])
            else
                out["list " .. filter] = describe(list)
            end
        end
    end
    return out
end

local function sampleUnits()
    local out = {}
    for _, unit in ipairs(SAMPLE_UNITS) do
        if UnitExists(unit) then
            local fields = {}
            for _, f in ipairs(UNIT_FIELDS) do
                if not (f[1] == "threat" and unit == "player") then
                    fields[f[1]] = call(f[2], unit)
                end
            end
            out[unit] = { fields = fields, auras = sampleAuras(unit) }
        end
    end
    return out
end

-- The GCD reference spells, then up to three actions on the current bar 1.
local function sampleCooldowns()
    local out = {}
    for _, id in ipairs(SAMPLE_SPELLS) do
        out["spell " .. id] = call(C_Spell and C_Spell.GetSpellCooldown, id)
    end
    local AB = C_ActionBar or {}
    local hasAction = HasAction or AB.HasAction
    local n = 0
    for slot = 1, 12 do
        if n < 3 and hasAction and hasAction(slot) then
            n = n + 1
            out["action " .. slot] = call(AB.GetActionCooldown, slot)
            out["action " .. slot .. " duration object"] = call(AB.GetActionCooldownDuration, slot)
        end
    end
    return out
end

-- Calls the no-argument queries the messaging scan found and keeps their
-- answer when it is readable.
local function sampleMessaging(saved)
    local out = {}
    for _, path in ipairs(saved.scans["Messaging lockdown APIs"] or {}) do
        local short = path:match("%.(%w+)$")
        if short and (short:find("^Is") or short:find("^In") or short:find("^Are")) then
            local ok, v = pcall(resolve(path))
            if not ok then out[short] = "error: " .. errText(v)
            elseif isSecret(v) then out[short] = "secret"
            else out[short] = tostring(v) end
        end
    end
    return out
end

-- One report line from a describe() result: fields grouped by state, then
-- each error with its message.
local function summarize(label, d)
    if type(d) ~= "table" then return { ("  %s: %s"):format(label, d) } end
    local groups, errors = {}, {}
    for _, k in ipairs(sortedKeys(d)) do
        local v = d[k]
        if type(v) == "table" then v = "table" end
        if v:find("^error") then
            errors[#errors + 1] = ("    %s %s"):format(k, v)
        else
            groups[v] = groups[v] or {}
            table.insert(groups[v], k)
        end
    end
    local parts = {}
    for _, s in ipairs({ "readable", "secret", "secret table", "none", "missing", "table" }) do
        if groups[s] then parts[#parts + 1] = s .. " " .. table.concat(groups[s], ", ") end
    end
    local lines = { ("  %s: %s"):format(label, #parts > 0 and table.concat(parts, " · ") or "nothing") }
    for _, e in ipairs(errors) do lines[#lines + 1] = e end
    return lines
end

local function context()
    local _, instance = IsInInstance()
    local group = IsInRaid() and "raid" or IsInGroup() and "party" or "solo"
    local combat = InCombatLockdown()
    return {
        time = date("%Y-%m-%d %H:%M:%S"),
        combat = combat,
        instance = instance or "none",
        group = group,
        size = GetNumGroupMembers(),
        zone = GetRealZoneText(),
        level = UnitLevel("player"),
        class = select(2, UnitClass("player")),
        key = ("%s%s · %s"):format(combat and "combat · " or "", instance or "none", group),
    }
end

local function clientInfo()
    local version, build, buildDate, toc = GetBuildInfo()
    local w, h = GetPhysicalScreenSize()
    return {
        version = version, build = build, date = buildDate, toc = toc,
        locale = GetLocale(),
        screen = ("%dx%d"):format(w, h),
        uiScale = UIParent:GetScale(),
        useUiScale = GetCVar("useUiScale"),
    }
end

--------------------------------------------------------------------------------
-- Run and report
--------------------------------------------------------------------------------

local function run()
    local saved = { namespaces = {}, enums = {}, scans = {} }
    local report, found, total = {}, 0, 0
    local client, ctx = clientInfo(), context()

    report[#report + 1] = ("SuuUI probe %s · %s"):format(ns.version, ctx.time)
    report[#report + 1] = ("Client %s build %s (interface %d), %s, screen %s, UI scale %.2f (useUiScale %s)")
        :format(client.version, client.build, client.toc, client.locale, client.screen, client.uiScale, tostring(client.useUiScale))
    report[#report + 1] = ("Context: %s, level %d %s, %s")
        :format(ctx.key, ctx.level, ctx.class or "?", ctx.zone or "?")

    local sections = {}
    for _, section in ipairs(SECTIONS) do
        report[#report + 1] = ""
        report[#report + 1] = section.title
        local rows = {}
        for _, item in ipairs(section.items) do
            local ok, label, detail = check(item, saved)
            total = total + 1
            if ok then found = found + 1 end
            rows[#rows + 1] = { label = label, ok = ok, detail = detail }
            report[#report + 1] = ("  [%s] %s%s"):format(ok and "ok" or "--", label, detail and ("  (" .. detail .. ")") or "")
        end
        sections[#sections + 1] = { title = section.title, rows = rows }
    end

    local samples = {
        context = ctx,
        units = sampleUnits(),
        cooldowns = sampleCooldowns(),
        messaging = sampleMessaging(saved),
    }

    report[#report + 1] = ""
    report[#report + 1] = "Secret values right now (" .. ctx.key .. ")"
    local function add(lines)
        for _, line in ipairs(lines) do report[#report + 1] = line end
    end
    for _, unit in ipairs(SAMPLE_UNITS) do
        local u = samples.units[unit]
        if u then
            add(summarize(unit, u.fields))
            for _, k in ipairs(sortedKeys(u.auras)) do
                add(summarize("  " .. unit .. " aura " .. k, u.auras[k]))
            end
        end
    end
    for _, k in ipairs(sortedKeys(samples.cooldowns)) do
        add(summarize(k, samples.cooldowns[k]))
    end
    for _, k in ipairs(sortedKeys(samples.messaging)) do
        report[#report + 1] = ("  %s: %s"):format(k, samples.messaging[k])
    end

    report[#report + 1] = ""
    report[#report + 1] = ("Found %d of %d."):format(found, total)

    SuuUIProbe = SuuUIProbe or {}
    local db = SuuUIProbe
    db.version = ns.version
    db.client = client
    db.sections = sections
    db.namespaces = saved.namespaces
    db.enums = saved.enums
    db.scans = saved.scans
    db.methods = collectMethods()
    db.cvars = collectCVars()
    db.allNamespaces = sortedKeys(_G, function(k, v) return type(v) == "table" and k:find("^C_") ~= nil end)
    db.runs = db.runs or {}
    db.runs[ctx.key] = samples
    db.lastReport = table.concat(report, "\n")

    return db.lastReport, found, total
end

--------------------------------------------------------------------------------
-- Report window: a plain, movable frame holding a read-only edit box, so the
-- text can be selected and copied. It is a diagnostic, not part of the design.
--------------------------------------------------------------------------------

local window

local function buildWindow()
    local f = CreateFrame("Frame", "SuuUIProbeFrame", UIParent, "BackdropTemplate")
    f:SetSize(720, 540)
    f:SetPoint("CENTER")
    f:SetFrameStrata("DIALOG")
    f:SetClampedToScreen(true)
    f:EnableMouse(true)
    f:SetMovable(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", f.StartMoving)
    f:SetScript("OnDragStop", f.StopMovingOrSizing)
    f:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8", edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 1 })
    f:SetBackdropColor(0.06, 0.07, 0.09, 0.96)
    f:SetBackdropBorderColor(0.62, 0.50, 0.28, 1)

    local title = f:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("TOPLEFT", 14, -12)
    title:SetText("SuuUI probe")

    local hint = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    hint:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -4)
    hint:SetText("Ctrl+A, Ctrl+C copies the report. /reload also saves it to SavedVariables\\SuuUI.lua.")

    local close = CreateFrame("Button", nil, f, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", -2, -2)

    local scroll = CreateFrame("ScrollFrame", nil, f, "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", 14, -56)
    scroll:SetPoint("BOTTOMRIGHT", -34, 14)

    local edit = CreateFrame("EditBox", nil, scroll)
    edit:SetMultiLine(true)
    edit:SetAutoFocus(false)
    edit:SetFontObject(ChatFontNormal)
    edit:SetWidth(660)
    edit:SetScript("OnEscapePressed", function() f:Hide() end)
    -- Read-only: typing puts the report back.
    edit:SetScript("OnTextChanged", function(self, userInput)
        if userInput then self:SetText(f.report or "") end
    end)
    scroll:SetScrollChild(edit)

    f.edit = edit
    tinsert(UISpecialFrames, "SuuUIProbeFrame")
    return f
end

local function show(text)
    window = window or buildWindow()
    window.report = text
    window.edit:SetText(text)
    window.edit:SetCursorPosition(0)
    window:Show()
    window.edit:SetFocus()
    window.edit:HighlightText()
end

-- Run by the diagnostics module's /suu probe.
ns.Probe = {}

function ns.Probe.Hide()
    if window then window:Hide() end
end

function ns.Probe.Command(arg)
    -- a full stop or comma copied along with the command is dropped
    local sub, rest = (arg or ""):gsub("[%.,;:!]+%s*$", ""):match("^(%S*)%s*(.-)$")
    if sub == "track" then
        ns.TrackProbe.Command(rest)
        return
    end
    if sub == "spells" then
        ns.SpellData.Command(rest)
        return
    end
    if sub == "plates" then
        ns.PlateProbe.Command(rest)
        return
    end
    if sub == "meter" then
        ns.MeterProbe.Command(rest)
        return
    end
    if sub == "timeline" then
        ns.TimelineProbe.Command(rest)
        return
    end
    if sub == "micro" then
        ns.MicroProbe.Command(rest)
        return
    end
    if sub == "minimap" then
        ns.MinimapProbe.Command(rest)
        return
    end
    if sub == "chat" then
        ns.ChatProbe.Command(rest)
        return
    end
    if sub == "quest" then
        ns.QuestProbe.Command(rest)
        return
    end
    if sub == "popups" then
        ns.PopupProbe.Command(rest)
        return
    end
    if sub == "bags" then
        ns.BagProbe.Command(rest)
        return
    end
    if sub == "loot" then
        ns.LootProbe.Command(rest)
        return
    end
    if sub == "tooltips" then
        ns.TooltipProbe.Command(rest)
        return
    end
    if sub == "camp" then
        ns.CampProbe.Command(rest)
        return
    end
    if sub == "partyauras" then
        ns.PartyAuraProbe.Command(rest)
        return
    end
    if sub == "hovertip" then
        ns.HoverTipProbe.Command(rest)
        return
    end
    if sub == "character" then
        ns.CharacterProbe.Command(rest)
        return
    end
    if sub == "tree" then
        ns.TreeProbe.Command(rest)
        return
    end
    if sub == "spellbook" then
        ns.SpellbookProbe.Command(rest)
        return
    end
    if sub == "flicker" then
        ns.FlickerProbe.Command(rest)
        return
    end
    if sub == "professions" then
        ns.ProfessionProbe.Command(rest)
        return
    end
    if sub == "unlearn" then
        ns.UnlearnProbe.Command(rest)
        return
    end
    if sub == "social" then
        ns.SocialProbe.Command(rest)
        return
    end
    if sub == "lfg" then
        ns.LfgProbe.Command(rest)
        return
    end
    if sub == "map" then
        ns.MapProbe.Command(rest)
        return
    end
    if sub == "calendar" then
        ns.CalendarProbe.Command(rest)
        return
    end
    if sub == "proficons" then
        ns.ProfIconProbe.Command(rest)
        return
    end
    if sub == "givers" then
        ns.GiverProbe.Command(rest)
        return
    end
    if sub == "marks" then
        ns.MarkProbe.Command(rest)
        return
    end
    if sub == "windows" then
        ns.WindowsProbe.Command(rest)
        return
    end
    if sub == "npcportrait" then
        ns.NpcPortraitProbe.Command(rest)
        return
    end
    if sub == "support" then
        ns.SupportProbe.Command(rest)
        return
    end
    if sub == "gamemenu" then
        ns.GameMenuProbe.Command(rest)
        return
    end
    if sub == "unitmenu" then
        ns.MenuProbe.Command(rest)
        return
    end
    if sub == "dragon" then
        ns.DragonProbe.Command(rest)
        return
    end
    if sub == "taxi" then
        ns.TaxiProbe.Command(rest)
        return
    end
    if sub == "raid" then
        ns.RaidProbe.Command(rest)
        return
    end
    if sub == "skysight" then
        ns.SkysightProbe.Command(rest)
        return
    end
    if sub == "mappins" then
        ns.MapPinsProbe.Command(rest)
        return
    end
    if sub == "durability" then
        ns.DurabilityProbe.Command(rest)
        return
    end
    if sub == "deathrecap" then
        ns.DeathRecapProbe.Command(rest)
        return
    end
    if sub == "questgroup" then
        ns.QuestGroupProbe.Command(rest)
        return
    end
    if sub == "casttarget" then
        ns.CastTargetProbe.Command(rest)
        return
    end
    if sub == "totems" then
        ns.TotemProbe.Command(rest)
        return
    end
    if sub == "garbage" then
        ns.GarbageProbe.Command(rest)
        return
    end
    if sub == "memory" then
        ns.MemoryProbe.Command(rest)
        return
    end
    if sub == "bankslots" then
        ns.BankSlotsProbe.Command(rest)
        return
    end
    if sub == "toymodels" then
        ns.ToyModelProbe.Command(rest)
        return
    end
    if sub == "mountfeet" then
        ns.MountFeetProbe.Command(rest)
        return
    end
    if sub == "mountframe" then
        ns.MountFrameProbe.Command(rest)
        return
    end
    if sub == "collown" then
        ns.CollectionsOwnProbe.Command(rest)
        return
    end
    if sub == "colltiles" then
        ns.CollectionsTilesProbe.Command(rest)
        return
    end
    if sub == "collart" then
        ns.CollectionsArtProbe.Command(rest)
        return
    end
    if sub == "ahscan" then
        ns.AhScanProbe.Command(rest)
        return
    end
    if sub == "ahpost" then
        ns.AhPostProbe.Command(rest)
        return
    end
    if sub == "ahdata" then
        ns.AhDataProbe.Command(rest)
        return
    end
    if sub == "legacy" then
        ns.LegacyProbe.Command(rest)
        return
    end
    if sub == "taint" then
        ns.TaintProbe.Command(rest)
        return
    end
    if sub == "hold" then
        ns.HoldProbe.Command(rest)
        return
    end
    if sub == "talents" then
        ns.TalentProbe.Command(rest)
        return
    end
    if sub == "group" then
        ns.GroupProbe.Command(rest)
        return
    end
    if sub == "class" then
        ns.ClassData.Command(rest)
        return
    end
    if sub == "icons" then
        ns.IconProbe.Command(rest)
        return
    end
    if sub == "api" then
        ns.ApiDocs.Command(rest)
        return
    end
    if sub == "runtime" then
        ns.ApiDocs.Runtime()
        return
    end
    if sub == "filters" then
        ns.ApiDocs.Filters()
        return
    end
    if sub == "sound" then
        if rest == "play" then ns.ApiDocs.SoundPlay() else ns.ApiDocs.Sound() end
        return
    end
    if arg == "show" then
        if SuuUIProbe and SuuUIProbe.lastReport then
            show(SuuUIProbe.lastReport)
        else
            ns.Print("No probe report yet. Run /suu probe.")
        end
        return
    end
    local text, found, total = run()
    show(text)
    ns.Print(("Probe found %d of %d. /reload to save it for Claude to read."):format(found, total))
end
