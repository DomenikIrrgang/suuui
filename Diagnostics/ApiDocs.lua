-- Diagnostics/ApiDocs.lua
-- "/suu probe api [words]": reads the client's own API documentation (what
-- the in-game /api command shows) and saves every system, function, event,
-- table and field whose name matches, with argument and field types, into
-- SuuUIProbe.apiDocs. Default words: aura, candidate, container, filter.
-- Use: find out what the engine really offers (e.g. aura container filter
-- options) instead of guessing from other addons.

local _, ns = ...

local AD = {}
ns.ApiDocs = AD

local DOC_ADDONS = { "Blizzard_APIDocumentationBasic", "Blizzard_APIDocumentation", "Blizzard_APIDocumentationGenerated" }

local function load()
    for _, name in ipairs(DOC_ADDONS) do
        if C_AddOns.DoesAddOnExist and C_AddOns.DoesAddOnExist(name) and not C_AddOns.IsAddOnLoaded(name) then
            pcall(C_AddOns.LoadAddOn, name)
        end
    end
    return _G.APIDocumentation
end

local function typeText(v)
    local t = tostring(v.Type or "?")
    if v.InnerType then t = t .. "<" .. tostring(v.InnerType) .. ">" end
    if v.Mixin then t = t .. "(" .. tostring(v.Mixin) .. ")" end
    if v.Nilable then t = t .. "?" end
    if v.Default ~= nil then t = t .. " = " .. tostring(v.Default) end
    if v.EnumValue ~= nil then t = t .. " = " .. tostring(v.EnumValue) end
    return t
end

local function fields(list)
    local parts = {}
    for _, v in ipairs(list or {}) do parts[#parts + 1] = tostring(v.Name) .. ": " .. typeText(v) end
    return table.concat(parts, ", ")
end

local function matches(name, words)
    name = tostring(name or ""):lower()
    for _, w in ipairs(words) do
        if name:find(w, 1, true) then return true end
    end
    return false
end

function AD.Dump(words)
    local docs = load()
    if not docs or type(docs.systems) ~= "table" then
        return nil, "the client's API documentation didn't load"
    end
    local lines = {}
    local function add(s) lines[#lines + 1] = s end
    for _, sys in ipairs(docs.systems) do
        local sysName = (sys.Namespace or sys.Name or "?")
        local whole = matches(sys.Name, words) or matches(sys.Namespace, words)
        local header = false
        local function head()
            if not header then
                header = true
                add(("== %s (%s, %s)"):format(tostring(sys.Name), tostring(sys.Namespace or "-"), tostring(sys.Type or "System")))
            end
        end
        for _, f in ipairs(sys.Functions or {}) do
            if whole or matches(f.Name, words) then
                head()
                add(("  fn %s.%s(%s) -> %s"):format(sysName, tostring(f.Name), fields(f.Arguments), fields(f.Returns)))
            end
        end
        for _, e in ipairs(sys.Events or {}) do
            if whole or matches(e.Name, words) or matches(e.LiteralName, words) then
                head()
                add(("  event %s(%s)"):format(tostring(e.LiteralName or e.Name), fields(e.Payload)))
            end
        end
        for _, t in ipairs(sys.Tables or {}) do
            if whole or matches(t.Name, words) then
                head()
                add(("  %s %s { %s }"):format(tostring(t.Type or "Table"), tostring(t.Name), fields(t.Fields or t.Values)))
            end
        end
    end
    return lines
end

--------------------------------------------------------------------------------
-- "/suu probe runtime": what the running client really has, where the
-- documentation is silent: every Enum and global table whose name mentions
-- aura, candidate or filter (with its keys and values), and the methods of a
-- live aura container.
--------------------------------------------------------------------------------

local RUNTIME_WORDS = { "aura", "candidate", "filter" }

local function keysOf(t)
    local out = {}
    for k, v in pairs(t) do
        out[#out + 1] = tostring(k) .. (type(v) == "function" and "()" or (type(v) == "table" and " {…}" or (" = " .. tostring(v))))
    end
    table.sort(out)
    return table.concat(out, ", ")
end

function AD.Runtime()
    local lines = {}
    local function add(s) lines[#lines + 1] = s end

    -- Enums
    for name, t in pairs(Enum or {}) do
        if type(t) == "table" and matches(name, RUNTIME_WORDS) then add("Enum." .. name .. " { " .. keysOf(t) .. " }") end
    end
    -- global tables and functions (mixins, constants, utilities)
    for name, v in pairs(_G) do
        if type(name) == "string" and matches(name, RUNTIME_WORDS) then
            -- some globals are forbidden objects: reading them errors
            pcall(function()
                if type(v) == "table" and not (v.GetObjectType) then
                    add("global table " .. name .. " { " .. keysOf(v) .. " }")
                elseif type(v) == "function" then
                    add("global function " .. name .. "()")
                end
            end)
        end
    end
    -- a live aura container's methods (and its mixin's)
    if not C_AddOns.IsAddOnLoaded("Blizzard_AuraContainer") then pcall(C_AddOns.LoadAddOn, "Blizzard_AuraContainer") end
    local ok, c = pcall(CreateFrame, "AuraContainer", nil, UIParent, "CustomAuraContainerTemplate")
    if ok and c then
        local mt = getmetatable(c)
        local methods = {}
        if mt and type(mt.__index) == "table" then
            for k, v in pairs(mt.__index) do if type(v) == "function" then methods[#methods + 1] = k end end
        end
        for k, v in pairs(c) do if type(v) == "function" then methods[#methods + 1] = k .. " (mixin)" end end
        table.sort(methods)
        add("AuraContainer methods: " .. table.concat(methods, ", "))
        c:Hide()
    else
        add("AuraContainer: couldn't create one (" .. tostring(c) .. ")")
    end
    -- C_ namespaces with aura in their name: their functions
    for name, v in pairs(_G) do
        if type(name) == "string" and name:find("^C_") and matches(name, { "aura" }) and type(v) == "table" then
            pcall(function() add("namespace " .. name .. " { " .. keysOf(v) .. " }") end)
        end
    end
    table.sort(lines)
    SuuUIProbe = SuuUIProbe or {}
    SuuUIProbe.runtime = { at = date("%Y-%m-%d %H:%M"), lines = lines }
    ns.Print(("Runtime probe: %d entries saved. /reload to save them."):format(#lines))
end

-- "/suu probe filters": every aura filter word the game knows
-- (AuraUtil.AuraFilters) and whether test filter strings are valid, the
-- negated ones ("!PLAYER": not mine) above all.
local FILTER_TESTS = {
    "HELPFUL", "HARMFUL", "HELPFUL|PLAYER", "HARMFUL|PLAYER",
    "HELPFUL|!PLAYER", "HARMFUL|!PLAYER", "!PLAYER|HARMFUL", "HARMFUL|!RAID",
    "HELPFUL|!CANCELABLE", "HARMFUL|INCLUDE_NAME_PLATE_ONLY", "HELPFUL|EXTERNAL_DEFENSIVE",
    "HARMFUL|CROWD_CONTROL", "HELPFUL|BIG_DEFENSIVE", "HELPFUL|IMPORTANT", "HELPFUL|NOTAFILTER",
}

function AD.Filters()
    local lines = {}
    local AU = AuraUtil or {}
    local function dump(name, t, depth)
        if type(t) ~= "table" or depth > 2 then return end
        for k, v in pairs(t) do
            if type(v) == "table" then dump(name .. "." .. tostring(k), v, depth + 1)
            elseif type(v) ~= "function" then lines[#lines + 1] = ("%s.%s = %s"):format(name, tostring(k), tostring(v)) end
        end
    end
    dump("AuraUtil.AuraFilters", AU.AuraFilters, 0)
    lines[#lines + 1] = "AuraUtil.AuraFilterNegationPrefix = " .. tostring(AU.AuraFilterNegationPrefix)
    for _, f in ipairs(FILTER_TESTS) do
        local ok, valid = pcall(AU.IsValidFilterString or function() return "n/a" end, f)
        lines[#lines + 1] = ("valid %-34s %s"):format(f, ok and tostring(valid) or ("error: " .. tostring(valid)))
    end
    -- the same, as the engine sees it: does a container take the group?
    if not C_AddOns.IsAddOnLoaded("Blizzard_AuraContainer") then pcall(C_AddOns.LoadAddOn, "Blizzard_AuraContainer") end
    local ok, c = pcall(CreateFrame, "AuraContainer", nil, UIParent, "CustomAuraContainerTemplate")
    if ok and c then
        for i, f in ipairs({ "HARMFUL|!PLAYER", "HELPFUL|!PLAYER", "HELPFUL|NOTAFILTER" }) do
            local added, err = pcall(c.AddAuraGroup, c, "t" .. i, f, { maxFrameCount = 1 })
            lines[#lines + 1] = ("container takes %-24s %s"):format(f, added and "yes" or ("no: " .. tostring(err)))
        end
        c:Hide()
    end
    SuuUIProbe = SuuUIProbe or {}
    SuuUIProbe.filters = { at = date("%Y-%m-%d %H:%M"), lines = lines }
    ns.Print(("Filter probe: %d lines saved. /reload to save them."):format(#lines))
end

-- "/suu probe sound": what C_UnitAuras.AddAuraSound wants. It isn't
-- documented, so this calls it with growing argument tables and keeps the
-- engine's error messages (they name what is missing), and removes any sound
-- it manages to add.
-- "/suu probe sound play": plays each tracker sound, one every 2 seconds and
-- named in chat: first the sound kit (the sound it should be), then candidate
-- file IDs (what aura sounds need), saying whether the game will play each.
-- Also lists the aura sounds the tracker registered.
local FILE_CANDIDATES = {
    chime = { 567409, 567478 },
    ping = { 567416 },
    proc = { 567458, 567399 },
    warning = { 567397 },
}

function AD.SoundPlay()
    local lines = {}
    local steps = {}
    local files = ns.UI.TrackerSoundFiles and ns.UI.TrackerSoundFiles() or {}
    for _, key in ipairs({ "chime", "ping", "proc", "warning" }) do
        local s = files[key]
        if s then
            steps[#steps + 1] = { key = key, kit = s.kit }
            for _, id in ipairs(FILE_CANDIDATES[key] or { s.file }) do steps[#steps + 1] = { key = key, file = id } end
        end
    end
    for i, step in ipairs(steps) do
        C_Timer.After((i - 1) * 2, function()
            local ok, willPlay, label
            if step.kit then
                label = ("%s: sound kit %s"):format(step.key, step.kit)
                ok, willPlay = pcall(PlaySound, SOUNDKIT and SOUNDKIT[step.kit] or 0, "Master")
            else
                label = ("%s: file %d"):format(step.key, step.file)
                ok, willPlay = pcall(PlaySoundFile, step.file, "Master")
            end
            local line = ("%d. %s -> %s"):format(i, label, ok and tostring(willPlay) or ("error " .. tostring(willPlay)))
            lines[#lines + 1] = line
            ns.Print("Sound check " .. line)
            SuuUIProbe.auraSoundPlay.lines = lines
        end)
    end
    local ids, what = {}, {}
    if ns.UI.TrackerAuraSounds then ids, what = ns.UI.TrackerAuraSounds() end
    lines[#lines + 1] = ("%d aura sounds registered"):format(#ids)
    for i, id in ipairs(ids) do lines[#lines + 1] = ("  #%s %s"):format(tostring(id), tostring(what[i])) end
    if what.error then lines[#lines + 1] = "last error: " .. what.error end
    SuuUIProbe = SuuUIProbe or {}
    SuuUIProbe.auraSoundPlay = { at = date("%Y-%m-%d %H:%M"), lines = lines }
    ns.Print(("Sound check: %d lines saved. /reload to save them."):format(#lines))
end

function AD.Sound()
    local lines = {}
    local U = C_UnitAuras or {}
    local trig = Enum.UnitAuraSoundTrigger and Enum.UnitAuraSoundTrigger.Added or 0
    local id = 1126 -- Mark of the Wild, rank 1
    -- unitToken is required (round 1); now the sound field's name
    local base = function(extra)
        local t = { spellID = id, unitToken = "player" }
        for k, v in pairs(extra) do t[k] = v end
        return t
    end
    local tries = {
        { "soundKitID", base({ soundKitID = 8960 }) },
        { "soundKit", base({ soundKit = 8960 }) },
        { "soundID", base({ soundID = 8960 }) },
        { "soundFileID", base({ soundFileID = 567478 }) },
        { "fileID", base({ fileID = 567478 }) },
        { "soundFileName", base({ soundFileName = "Sound\\Interface\\RaidWarning.ogg" }) },
        { "soundFile", base({ soundFile = "Sound\\Interface\\RaidWarning.ogg" }) },
        { "soundKitID outputChannel", base({ soundKitID = 8960, outputChannel = "Master" }) },
        { "soundFileID outputChannel", base({ soundFileID = 567478, outputChannel = "Master" }) },
        { "soundFileName outputChannel", base({ soundFileName = "Sound\\Interface\\RaidWarning.ogg", outputChannel = "Master" }) },
        { "spellID as name", { spellID = "Mark of the Wild", unitToken = "player", soundKitID = 8960 } },
    }
    for _, t in ipairs(tries) do
        local ok, res = pcall(U.AddAuraSound, trig, t[2])
        lines[#lines + 1] = ("AddAuraSound(trigger, {%s}) -> %s"):format(t[1], ok and ("ok, " .. tostring(res)) or ("error: " .. tostring(res)))
        if ok and res and U.RemoveAuraSound then pcall(U.RemoveAuraSound, res) end
    end
    local ok, res = pcall(U.AddPrivateAuraAppliedSound, {})
    lines[#lines + 1] = "AddPrivateAuraAppliedSound({}) -> " .. (ok and ("ok, " .. tostring(res)) or ("error: " .. tostring(res)))
    SuuUIProbe = SuuUIProbe or {}
    SuuUIProbe.auraSound = { at = date("%Y-%m-%d %H:%M"), lines = lines }
    ns.Print(("Sound probe: %d tries saved. /reload to save them."):format(#lines))
end

function AD.Command(arg)
    local words = {}
    for w in tostring(arg or ""):gmatch("%S+") do words[#words + 1] = w:lower() end
    if #words == 0 then words = { "aura", "candidate", "container", "filter" } end
    local lines, err = AD.Dump(words)
    if not lines then
        ns.Print("API docs: " .. err)
        return
    end
    SuuUIProbe = SuuUIProbe or {}
    SuuUIProbe.apiDocs = { at = date("%Y-%m-%d %H:%M"), words = words, lines = lines }
    ns.Print(("API docs: %d lines about %s saved. /reload to save them."):format(#lines, table.concat(words, ", ")))
end
