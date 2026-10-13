-- Diagnostics/CharacterProbe.lua
-- "/suu probe character": what Forever's Character window is made of (step
-- 3.1). Saved in SuuUIProbe.character on /reload.
--   * now: CharacterFrame (protected?, panel attributes, size, art, its
--     keyed children two levels deep), its tabs (name, text, shown), the
--     equipment slots, the side panes, the functions and C_ namespaces the
--     window uses (equipment sets, reputation, currency, skills, honor)
--   * each time you run it again: which of its panels show (run it once per
--     tab with the window open)
--   * from now until /reload, a log: tab and panel switches (the functions
--     Blizzard calls), the window opening and closing, blocked actions
--
--   /suu probe character   with the Character window open on each tab in
--                          turn (Character, Reputation, Currency, Honor or
--                          PvP, Skills, any others), then /reload

local _, ns = ...

local CP = {}
ns.CharacterProbe = CP

local isSecret = issecretvalue or function() return false end
local function show(v)
    if isSecret(v) then return "secret" end
    if v == nil then return "nil" end
    return tostring(v)
end

local function namesIn(t)
    local out = {}
    if type(t) ~= "table" then return { "missing" } end
    for k, v in pairs(t) do if type(k) == "string" and type(v) == "function" then out[#out + 1] = k end end
    table.sort(out)
    return out
end

local function keyedChildren(f)
    local out = {}
    for k, v in pairs(f) do
        if type(k) == "string" and type(v) == "table" and v.GetObjectType and not (v.IsForbidden and v:IsForbidden()) then
            out[#out + 1] = k
        end
    end
    table.sort(out)
    return out
end

local function frameLine(f)
    if type(f) ~= "table" or not f.GetObjectType then return "missing" end
    local w, h = f:GetSize()
    return ("%s shown=%s protected=%s size=%dx%d strata=%s"):format(f:GetObjectType(), show(f:IsShown()),
        show(f:IsProtected()), w or 0, h or 0, show(f:GetFrameStrata()))
end

-- A frame and its keyed children, two levels deep.
local function tree(f, depth)
    if type(f) ~= "table" or not f.GetObjectType then return "missing" end
    local node = { info = frameLine(f) }
    if depth > 0 then
        node.children = {}
        for _, k in ipairs(keyedChildren(f)) do
            node.children[k] = (depth > 1) and tree(f[k], depth - 1) or frameLine(f[k])
        end
    end
    return node
end

local SLOTS = { "Head", "Neck", "Shoulder", "Back", "Chest", "Shirt", "Tabard", "Wrist", "Hands", "Waist", "Legs",
                "Feet", "Finger0", "Finger1", "Trinket0", "Trinket1", "MainHand", "SecondaryHand", "Ranged", "Ammo" }

local PANES = { "PaperDollFrame", "CharacterStatsPane", "PaperDollItemsFrame", "PaperDollSidebarTabs",
                "PaperDollTitlesPane", "PaperDollEquipmentManagerPane", "GearManagerDialog", "CharacterModelScene",
                "CharacterModelFrame", "CharacterFrameInset", "CharacterFrameInsetRight", "ReputationFrame",
                "ReputationDetailFrame", "TokenFrame", "TokenFramePopup", "CurrencyTransferMenu", "SkillFrame",
                "HonorFrame", "PVPFrame", "PVPUIFrame", "CharacterFrameTitleText", "PaperDollFrame_UpdateStats",
                "StatisticsFrame", "AchievementFrame", "LegacyFrame" }

local FUNCS = { "ToggleCharacter", "CharacterFrame_ShowSubFrame", "CharacterFrameTab_OnClick", "PaperDollFrame_SetSidebar",
                "PaperDollFrame_UpdateStats", "ReputationFrame_Update", "TokenFrame_Update", "SkillFrame_Update",
                "ToggleTokenFrame", "TogglePVPUI", "TogglePVPFrame", "ToggleHonorFrame", "PanelTemplates_SetTab",
                "PanelTemplates_TabResize", "CharacterFrame_Collapse", "CharacterFrame_Expand", "ShowUIPanel", "HideUIPanel" }

local store
local function note(s)
    local log = store and store.log
    if not log then return end
    log[#log + 1] = date("%H:%M:%S") .. (InCombatLockdown() and " [combat] " or " ") .. s
    while #log > 300 do table.remove(log, 1) end
end

local logging = false
local function startLog()
    if logging then return end
    logging = true
    for _, name in ipairs({ "ToggleCharacter", "CharacterFrame_ShowSubFrame", "CharacterFrameTab_OnClick", "PaperDollFrame_SetSidebar",
                            "ToggleTokenFrame", "TogglePVPUI", "TogglePVPFrame", "ToggleHonorFrame", "PanelTemplates_SetTab",
                            "CharacterFrame_Collapse", "CharacterFrame_Expand" }) do
        if type(_G[name]) == "function" then
            hooksecurefunc(name, function(a, b)
                local function label(v)
                    if type(v) == "table" and v.GetName then return v:GetName() or "frame" end
                    return show(v)
                end
                note(name .. "(" .. label(a) .. ", " .. label(b) .. ")")
            end)
        end
    end
    local cf = _G.CharacterFrame
    if cf then
        cf:HookScript("OnShow", function() note("CharacterFrame shown") end)
        cf:HookScript("OnHide", function() note("CharacterFrame hidden") end)
    end
    local f = CreateFrame("Frame")
    for _, e in ipairs({ "ADDON_ACTION_BLOCKED", "ADDON_ACTION_FORBIDDEN", "PLAYER_EQUIPMENT_CHANGED", "EQUIPMENT_SETS_CHANGED",
                         "UPDATE_FACTION", "CURRENCY_DISPLAY_UPDATE", "SKILL_LINES_CHANGED" }) do
        pcall(f.RegisterEvent, f, e)
    end
    f:SetScript("OnEvent", function(_, e, a, b) note(e .. " " .. show(a) .. " " .. show(b)) end)
end

function CP.Sample()
    SuuUIProbe = SuuUIProbe or {}
    store = SuuUIProbe.character or {}
    SuuUIProbe.character = store
    store.at = date("%Y-%m-%d %H:%M:%S")
    local cf = _G.CharacterFrame
    store.frame = tree(cf, 2)
    if cf then
        store.panel = {}
        for _, key in ipairs({ "UIPanelLayout-defined", "UIPanelLayout-area", "UIPanelLayout-pushable", "UIPanelLayout-width",
                               "UIPanelLayout-whileDead" }) do
            store.panel[key] = show(cf:GetAttribute(key))
        end
        store.panelWindows = UIPanelWindows and UIPanelWindows.CharacterFrame and "listed" or "not in UIPanelWindows"
        store.numTabs = show(cf.numTabs)
        store.selectedTab = show(cf.selectedTab)
        local regions = {}
        for _, r in ipairs({ cf:GetRegions() }) do
            regions[#regions + 1] = (r:GetDebugName() or "?"):gsub("^.*%.", "") .. "(" .. r:GetObjectType() .. ")"
        end
        store.regions = table.concat(regions, " ")
    end
    store.tabs = {}
    for i = 1, 10 do
        local t = _G["CharacterFrameTab" .. i]
        if t then
            store.tabs[i] = ("%s text=%s shown=%s enabled=%s protected=%s"):format(t:GetName(), show(t:GetText()),
                show(t:IsShown()), show(t:IsEnabled()), show(t:IsProtected()))
        end
    end
    store.slots = {}
    for _, s in ipairs(SLOTS) do
        local b = _G["Character" .. s .. "Slot"]
        store.slots[s] = b and ("%s protected=%s id=%s"):format(b:GetObjectType(), show(b:IsProtected()), show(b:GetID())) or "missing"
    end
    store.panes = {}
    for _, name in ipairs(PANES) do
        local v = _G[name]
        store.panes[name] = type(v) == "table" and frameLine(v) or type(v)
    end
    store.funcs = {}
    for _, name in ipairs(FUNCS) do store.funcs[name] = type(_G[name]) end
    store.C_EquipmentSet = namesIn(C_EquipmentSet)
    store.C_Reputation = namesIn(C_Reputation)
    store.C_CurrencyInfo = namesIn(C_CurrencyInfo)
    store.C_PaperDollInfo = namesIn(C_PaperDollInfo)
    -- anything model- or HD-like in the window
    local found = {}
    local function scan(f, path, depth)
        if depth > 3 or type(f) ~= "table" or not f.GetObjectType then return end
        for _, k in ipairs(keyedChildren(f)) do
            local l = k:lower()
            if l:find("model") or l:find("hd") or l:find("toggle") or l:find("quality") then
                found[#found + 1] = path .. "." .. k .. " " .. frameLine(f[k])
            end
            scan(f[k], path .. "." .. k, depth + 1)
        end
    end
    if cf then scan(cf, "CharacterFrame", 0) end
    store.modelThings = found
    -- what shows right now (one entry per run: run it on each tab)
    store.views = store.views or {}
    local view = { at = date("%H:%M:%S"), selectedTab = show(cf and cf.selectedTab), shown = {} }
    for _, name in ipairs(PANES) do
        local v = _G[name]
        if type(v) == "table" and v.IsVisible and v:IsVisible() then view.shown[#view.shown + 1] = name end
    end
    table.insert(store.views, view)
    while #store.views > 10 do table.remove(store.views, 1) end
    store.log = store.log or {}
    startLog()
end

function CP.Command()
    CP.Sample()
    ns.Print("Character probe: sampled. Run it again with the Character window open on each tab in turn, then /reload.")
end
