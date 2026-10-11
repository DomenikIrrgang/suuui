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

-- "secret", "readable", "none" (no value) or "error"; never keeps the value.
local function sample(fn, ...)
    if type(fn) ~= "function" then return "missing" end
    local ok, v = pcall(fn, ...)
    if not ok then return "error" end
    if isSecret(v) then return "secret" end
    if v == nil then return "none" end
    return "readable"
end

local function sampleAura(unit)
    local get = C_UnitAuras and C_UnitAuras.GetAuraDataByIndex
    if not get then return "missing" end
    local ok, data = pcall(get, unit, 1, "HELPFUL")
    if not ok then return "error" end
    if isSecret(data) then return "secret" end
    if data == nil then return "none" end
    if isSecretTable(data) then return "secret table" end
    if isSecret(data.spellId) then return "secret spellId" end
    return "readable"
end

local function sampleUnits()
    local out = {}
    for _, unit in ipairs(SAMPLE_UNITS) do
        if UnitExists(unit) then
            out[unit] = {
                name = sample(UnitName, unit),
                health = sample(UnitHealth, unit),
                healthMax = sample(UnitHealthMax, unit),
                healthPercent = sample(UnitHealthPercent, unit),
                power = sample(UnitPower, unit),
                cast = sample(UnitCastingInfo, unit),
                aura = sampleAura(unit),
                threat = unit ~= "player" and sample(UnitThreatSituation, "player", unit) or nil,
            }
        end
    end
    return out
end

local function sampleCooldowns()
    local out = {}
    local get = C_Spell and C_Spell.GetSpellCooldown
    for _, id in ipairs(SAMPLE_SPELLS) do
        local state = "missing"
        if get then
            local ok, cd = pcall(get, id)
            if not ok then state = "error"
            elseif isSecret(cd) then state = "secret"
            elseif cd == nil then state = "none"
            elseif isSecret(cd.startTime) or isSecret(cd.duration) then state = "secret fields"
            else state = "readable" end
        end
        out[tostring(id)] = state
    end
    return out
end

-- Calls the no-argument Is*/In* queries the messaging scan found.
local function sampleMessaging(saved)
    local out = {}
    for _, path in ipairs(saved.scans["Messaging lockdown APIs"] or {}) do
        local short = path:match("%.(%w+)$")
        if short and (short:find("^Is") or short:find("^In")) then
            out[short] = sample(resolve(path))
        end
    end
    return out
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
    for _, unit in ipairs(SAMPLE_UNITS) do
        local u = samples.units[unit]
        if u then
            report[#report + 1] = ("  %s: name %s, health %s, health%% %s, power %s, cast %s, aura %s%s")
                :format(unit, u.name, u.health, u.healthPercent, u.power, u.cast, u.aura,
                    u.threat and (", threat " .. u.threat) or "")
        end
    end
    for id, state in pairs(samples.cooldowns) do
        report[#report + 1] = ("  spell %s cooldown: %s"):format(id, state)
    end
    for name, state in pairs(samples.messaging) do
        report[#report + 1] = ("  %s: %s"):format(name, state)
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

ns.RegisterCommand("probe", "Check which client APIs SuuUI depends on exist here; \"/suu probe show\" reopens the last report.", function(arg)
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
end)
