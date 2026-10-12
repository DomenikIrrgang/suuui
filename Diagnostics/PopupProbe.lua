-- Diagnostics/PopupProbe.lua
-- "/suu probe popups": what SuuUI's notifications (step 2.4) can take over
-- from Blizzard's popups. Saved in SuuUIProbe.popups on /reload.
--   * Blizzard's popup dialogs (StaticPopupDialogs) for the requests the plan
--     names: buttons, whether they time out or show while dead, edit boxes
--   * the popup frames and their buttons: do they exist, are they protected
--   * the other request frames (dungeon ready, battleground entry, ready check)
--   * the answer functions: present, and their API documentation's flags
--   * from now until /reload: every popup Blizzard shows (which, its text)
--     and every request event (with its arguments)
--
--   /suu probe popups        sample, and start logging popups and events
--   /suu probe popups try    out of combat: calls the answers that do nothing
--                            without a request (accept an invite, a
--                            resurrection, a summon, a duel; delete the item
--                            on the cursor with nothing on it) one by one and
--                            notes which the game blocks. Blizzard's "blocked"
--                            message may show for those: that's the answer.
--   /suu probe popups host   hosting test: the next logout countdown (/camp)
--                            or delete question moves Blizzard's popup over a
--                            SuuUI test panel at the left, everything but its
--                            buttons invisible. Click Cancel (or No): does the
--                            game take it as Blizzard's? Then /reload.

local _, ns = ...

local PP = {}
ns.PopupProbe = PP

local isSecret = issecretvalue or function() return false end

local function show(v)
    if isSecret(v) then return "secret" end
    if v == nil then return "nil" end
    if type(v) == "function" then return "function" end
    if type(v) == "table" then return "table" end
    return tostring(v)
end

local DIALOGS = {
    "PARTY_INVITE", "PARTY_INVITE_XREALM", "GROUP_INVITE_CONFIRMATION", "RESURRECT", "RESURRECT_NO_SICKNESS",
    "RESURRECT_NO_TIMER", "CONFIRM_SUMMON", "CONFIRM_SUMMON_SCENARIO", "CONFIRM_SUMMON_STARTING_AREA",
    "DUEL_REQUESTED", "DUEL_OUTOFBOUNDS", "TRADE", "DEATH", "RECOVER_CORPSE", "RECOVER_CORPSE_INSTANCE",
    "AREA_SPIRIT_HEAL", "DELETE_ITEM", "DELETE_GOOD_ITEM", "DELETE_QUEST_ITEM", "DELETE_GOOD_QUEST_ITEM",
    "CAMP", "QUIT", "LOOT_BIND", "EQUIP_BIND", "USE_BIND", "CONFIRM_LOOT_ROLL", "ABANDON_QUEST",
    "CONFIRM_BATTLEFIELD_ENTRY", "BFMGR_INVITED_TO_ENTER", "CONFIRM_XP_LOSS", "XP_LOSS", "INSTANCE_BOOT",
    "INSTANCE_LOCK", "CONFIRM_TALENT_WIPE", "QUEST_ACCEPT", "PARTY_INVITE_CANCEL", "BIND_ENCHANT", "REPLACE_ENCHANT",
}

local FRAMES = {
    "StaticPopup1", "StaticPopup2", "StaticPopup3", "StaticPopup4", "StaticPopup1Button1", "StaticPopup1Button2",
    "LFGDungeonReadyPopup", "LFGDungeonReadyDialog", "PVPReadyDialog", "ReadyCheckFrame", "ReadyCheckListenerFrame",
    "LFGListInviteDialog", "RolePollPopup", "GroupLootContainer", "LootFrame", "TradeFrame", "GhostFrame",
}

local ANSWERS = {
    "AcceptGroup", "DeclineGroup", "C_PartyInfo.ConfirmInviteUnit", "C_PartyInfo.InviteUnit",
    "AcceptResurrect", "DeclineResurrect", "ResurrectHasSickness", "ResurrectGetOfferer", "ResurrectHasTimer",
    "C_SummonInfo.ConfirmSummon", "C_SummonInfo.CancelSummon", "C_SummonInfo.GetSummonConfirmTimeLeft",
    "C_SummonInfo.GetSummonConfirmSummoner", "C_SummonInfo.GetSummonConfirmAreaName",
    "AcceptDuel", "CancelDuel", "StartDuel", "RepopMe", "RetrieveCorpse", "AcceptAreaSpiritHeal", "CancelAreaSpiritHeal",
    "AcceptTrade", "CancelTrade", "InitiateTrade", "BeginTrade", "CancelTradeAccept",
    "AcceptBattlefieldPort", "GetBattlefieldStatus", "GetBattlefieldPortExpiration",
    "DeleteCursorItem", "ClearCursor", "Logout", "Quit", "CancelLogout", "ForceQuit",
    "ConfirmLootRoll", "ConfirmLootSlot", "ConfirmBindOnUse", "BindEnchant", "ReplaceEnchant",
    "AcceptXPLoss", "ConfirmTalentWipe", "AcceptQuest", "ConfirmAcceptQuest",
    "StaticPopup_Show", "StaticPopup_Hide", "StaticPopup_FindVisible", "StaticPopup_Visible",
    "ConfirmReadyCheck", "C_PartyInfo.DoReadyCheck", "AcceptProposal", "RejectProposal",
    "CompleteLFGRoleCheck", "C_LFGList.AcceptInvite", "C_LFGList.DeclineInvite",
}

local EVENTS = {
    "PARTY_INVITE_REQUEST", "PARTY_INVITE_CANCEL", "GROUP_INVITE_CONFIRMATION", "RESURRECT_REQUEST",
    "CONFIRM_SUMMON", "CANCEL_SUMMON", "DUEL_REQUESTED", "DUEL_OUTOFBOUNDS", "DUEL_INBOUNDS", "DUEL_FINISHED",
    "TRADE_REQUEST", "TRADE_REQUEST_CANCEL", "TRADE_SHOW", "TRADE_CLOSED", "UPDATE_BATTLEFIELD_STATUS",
    "PLAYER_DEAD", "PLAYER_ALIVE", "PLAYER_UNGHOST", "CORPSE_IN_RANGE", "CORPSE_OUT_OF_RANGE",
    "AREA_SPIRIT_HEALER_IN_RANGE", "DELETE_ITEM_CONFIRM", "PLAYER_CAMPING", "PLAYER_QUITING", "LOGOUT_CANCEL",
    "LOOT_BIND_CONFIRM", "EQUIP_BIND_CONFIRM", "USE_BIND_CONFIRM", "CONFIRM_LOOT_ROLL", "START_LOOT_ROLL",
    "READY_CHECK", "READY_CHECK_FINISHED", "LFG_PROPOSAL_SHOW", "LFG_ROLE_CHECK_SHOW", "QUEST_ACCEPT_CONFIRM",
    "CONFIRM_XP_LOSS", "BIND_ENCHANT", "REPLACE_ENCHANT", "INSTANCE_BOOT_START", "INSTANCE_LOCK_START",
    "SPELL_CONFIRMATION_PROMPT", "ADDON_ACTION_BLOCKED", "ADDON_ACTION_FORBIDDEN",
}

local function lookup(path)
    local v = _G
    for part in path:gmatch("[^%.]+") do
        if type(v) ~= "table" then return nil end
        v = v[part]
    end
    return v
end

-- A function's entry in the client's API documentation: every key that
-- isn't its name, arguments, returns or prose (its flags).
local docIndex
local function docFlags(path)
    if docIndex == nil then
        docIndex = false
        for _, name in ipairs({ "Blizzard_APIDocumentationBasic", "Blizzard_APIDocumentation", "Blizzard_APIDocumentationGenerated" }) do
            if C_AddOns.DoesAddOnExist and C_AddOns.DoesAddOnExist(name) and not C_AddOns.IsAddOnLoaded(name) then
                pcall(C_AddOns.LoadAddOn, name)
            end
        end
        local docs = _G.APIDocumentation
        if docs and type(docs.systems) == "table" then
            docIndex = {}
            for _, sys in ipairs(docs.systems) do
                for _, f in ipairs(sys.Functions or {}) do
                    local key = (sys.Namespace and (sys.Namespace .. ".") or "") .. tostring(f.Name)
                    docIndex[key] = f
                end
            end
        end
    end
    if not docIndex then return "no docs" end
    local f = docIndex[path]
    if not f then return "not documented" end
    local parts = {}
    for k, v in pairs(f) do
        if k ~= "Name" and k ~= "Arguments" and k ~= "Returns" and k ~= "Documentation" and k ~= "System" and type(v) ~= "function" then
            parts[#parts + 1] = tostring(k) .. "=" .. (type(v) == "table" and "{…}" or tostring(v))
        end
    end
    table.sort(parts)
    return #parts > 0 and table.concat(parts, ", ") or "no flags"
end

local function frameInfo(name)
    local f = _G[name]
    if not f then return "missing" end
    local out = {}
    local ok, p = pcall(f.IsProtected, f)
    out[#out + 1] = "protected=" .. (ok and show(p) or "?")
    if f.IsForbidden then out[#out + 1] = "forbidden=" .. show(f:IsForbidden()) end
    if f.GetObjectType then out[#out + 1] = f:GetObjectType() end
    local kids = {}
    for k, v in pairs(f) do
        if type(k) == "string" and type(v) == "table" and v.GetObjectType then
            local okP, prot = pcall(v.IsProtected, v)
            kids[#kids + 1] = k .. ((okP and prot) and "(protected)" or "")
        end
    end
    table.sort(kids)
    if #kids > 0 then out[#out + 1] = "children: " .. table.concat(kids, " ") end
    return table.concat(out, ", ")
end

local function args(...)
    local parts = {}
    for i = 1, select("#", ...) do parts[#parts + 1] = show((select(i, ...))) end
    return table.concat(parts, " | ")
end

-- the log, from the first sample until /reload
local logging = false
local function startLog(store)
    if logging then return end
    logging = true
    store.log = store.log or {}
    local function note(s)
        local log = SuuUIProbe.popups and SuuUIProbe.popups.log
        if not log then return end
        log[#log + 1] = date("%H:%M:%S") .. (InCombatLockdown() and " [combat] " or " ") .. s
        while #log > 200 do table.remove(log, 1) end
    end
    if StaticPopup_Show then
        hooksecurefunc("StaticPopup_Show", function(which, text1, text2, data)
            note("StaticPopup_Show " .. show(which) .. " | " .. show(text1) .. " | " .. show(text2) .. " | data " .. show(data))
        end)
    end
    if StaticPopup_Hide then
        hooksecurefunc("StaticPopup_Hide", function(which) note("StaticPopup_Hide " .. show(which)) end)
    end
    local f = CreateFrame("Frame")
    local valid = C_EventUtils and C_EventUtils.IsEventValid
    for _, e in ipairs(EVENTS) do
        if not valid or valid(e) then f:RegisterEvent(e) end
    end
    f:SetScript("OnEvent", function(_, event, ...) note(event .. " " .. args(...)) end)
end

function PP.Sample()
    SuuUIProbe = SuuUIProbe or {}
    local store = SuuUIProbe.popups or {}
    SuuUIProbe.popups = store
    store.at = date("%H:%M:%S")
    store.dialogs = {}
    local dialogs = StaticPopupDialogs or {}
    local total = 0
    for _ in pairs(dialogs) do total = total + 1 end
    store.dialogCount = total
    for _, which in ipairs(DIALOGS) do
        local d = dialogs[which]
        if d then
            store.dialogs[which] = ("button1=%s button2=%s button3=%s timeout=%s whileDead=%s hideOnEscape=%s exclusive=%s editBox=%s OnAccept=%s OnCancel=%s OnShow=%s"):format(
                show(d.button1), show(d.button2), show(d.button3), show(d.timeout), show(d.whileDead), show(d.hideOnEscape),
                show(d.exclusive), show(d.hasEditBox), show(d.OnAccept), show(d.OnCancel), show(d.OnShow))
        else
            store.dialogs[which] = "missing"
        end
    end
    store.frames = {}
    for _, name in ipairs(FRAMES) do store.frames[name] = frameInfo(name) end
    if StaticPopup1 and StaticPopup1.ButtonContainer then
        local bc = StaticPopup1.ButtonContainer
        store.frames["StaticPopup1.ButtonContainer"] = "children: " .. (function()
            local kids = {}
            for k, v in pairs(bc) do
                if type(v) == "table" and v.GetObjectType then
                    local ok, p = pcall(v.IsProtected, v)
                    kids[#kids + 1] = tostring(k) .. ((ok and p) and "(protected)" or "")
                end
            end
            table.sort(kids)
            return table.concat(kids, " ")
        end)()
    end
    store.answers = {}
    for _, path in ipairs(ANSWERS) do
        local fn = lookup(path)
        store.answers[path] = (type(fn) == "function" and "function" or "missing") .. " · " .. docFlags(path)
    end
    local valid = C_EventUtils and C_EventUtils.IsEventValid
    store.events = {}
    for _, e in ipairs(EVENTS) do store.events[e] = valid and show(valid(e)) or "unknown" end
    store.cvars = { autoAcceptQuickJoinRequests = show(GetCVar("autoAcceptQuickJoinRequests")) }
    startLog(store)
    return store
end

-- Calls the answers that do nothing without a request, one per half second,
-- noting which the game blocks.
local TRIES = {
    { "AcceptGroup" }, { "DeclineGroup" }, { "AcceptResurrect" }, { "DeclineResurrect" },
    { "C_SummonInfo.ConfirmSummon" }, { "C_SummonInfo.CancelSummon" }, { "AcceptDuel" }, { "CancelDuel" },
    { "DeleteCursorItem", needsEmptyCursor = true }, { "ConfirmReadyCheck", args = { true } },
    { "AcceptAreaSpiritHeal" }, { "CancelAreaSpiritHeal" }, { "RetrieveCorpse", needsAlive = true },
    { "RepopMe", needsAlive = true }, { "CancelLogout" }, { "AcceptTrade", needsNoTrade = true },
    { "CancelTrade", needsNoTrade = true }, { "AcceptProposal" }, { "RejectProposal" },
    { "AcceptBattlefieldPort", args = { 1, false }, needsNoQueue = true },
}

function PP.Try()
    if InCombatLockdown() then ns.Print("Popup probe: out of combat, please.") return end
    local store = PP.Sample()
    store.tries = {}
    local current
    local watch = CreateFrame("Frame")
    watch:RegisterEvent("ADDON_ACTION_BLOCKED")
    watch:RegisterEvent("ADDON_ACTION_FORBIDDEN")
    watch:SetScript("OnEvent", function(_, event, addon, fn)
        if current then
            store.tries[current] = (store.tries[current] or "") .. " " .. event .. "(" .. show(fn) .. ")"
        end
    end)
    local i = 0
    local function step()
        i = i + 1
        local t = TRIES[i]
        if not t then
            current = nil
            watch:UnregisterAllEvents()
            ns.Print("Popup probe: tried them all. /reload to save.")
            return
        end
        local path = t[1]
        current = path
        local fn = lookup(path)
        if type(fn) ~= "function" then
            store.tries[path] = "missing"
        elseif t.needsEmptyCursor and GetCursorInfo() then
            store.tries[path] = "skipped: something on the cursor"
        elseif t.needsAlive and UnitIsDeadOrGhost("player") then
            store.tries[path] = "skipped: dead"
        elseif t.needsNoTrade and TradeFrame and TradeFrame:IsShown() then
            store.tries[path] = "skipped: trading"
        elseif t.needsNoQueue and GetBattlefieldStatus and GetBattlefieldStatus(1) ~= "none" then
            store.tries[path] = "skipped: queued"
        else
            store.tries[path] = ""
            local ok, err = pcall(fn, unpack(t.args or {}))
            -- a block noted while it ran stays (it comes inside the call)
            store.tries[path] = (ok and "called" or ("error: " .. tostring(err):sub(1, 160))) .. store.tries[path]
        end
        C_Timer.After(0.5, step)
    end
    ns.Print("Popup probe: trying the answers (a Blizzard \"blocked\" message for some is expected)…")
    step()
end

-- Hosting: Blizzard's popup moved over SuuUI's panel, only its buttons
-- showing (its texts, art and other parts at alpha 0). Nothing written on
-- Blizzard's frames but points and alpha.
local HOSTED = { CAMP = true, QUIT = true, DELETE_ITEM = true, DELETE_GOOD_ITEM = true,
                 DELETE_QUEST_ITEM = true, DELETE_GOOD_QUEST_ITEM = true }
local hostPanel, hostArmed, hostHooked

local function hostNote(s)
    local p = SuuUIProbe.popups
    if not p then return end
    p.host = p.host or {}
    p.host[#p.host + 1] = date("%H:%M:%S") .. " " .. s
end

local function host(which)
    local dialog = StaticPopup_FindVisible and StaticPopup_FindVisible(which)
    if not dialog then hostNote("no visible dialog for " .. tostring(which)) return end
    if not hostPanel then
        hostPanel = CreateFrame("Frame", nil, UIParent, "BackdropTemplate")
        hostPanel:SetSize(340, 110)
        hostPanel:SetPoint("LEFT", 60, 80)
        hostPanel:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8", edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 1 })
        hostPanel:SetBackdropColor(0.05, 0.05, 0.07, 0.92)
        hostPanel:SetBackdropBorderColor(0.6, 0.5, 0.3, 0.8)
        hostPanel.text = hostPanel:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        hostPanel.text:SetPoint("TOPLEFT", 12, -12)
        hostPanel.text:SetPoint("TOPRIGHT", -12, -12)
        hostPanel.text:SetJustifyH("LEFT")
    end
    hostPanel.text:SetText("SuuUI hosting test (" .. which .. "): Blizzard's buttons below are its own. Click Cancel or No.")
    hostPanel:Show()
    -- everything but the buttons invisible
    for _, region in ipairs({ dialog:GetRegions() }) do region:SetAlpha(0) end
    for _, child in ipairs({ dialog:GetChildren() }) do
        if child ~= dialog.ButtonContainer then child:SetAlpha(0) end
    end
    dialog:ClearAllPoints()
    dialog:SetPoint("BOTTOM", hostPanel, "BOTTOM", 0, -10)
    hostNote("hosted " .. which .. " on " .. tostring(dialog:GetName()))
end

local function hostTest()
    SuuUIProbe = SuuUIProbe or {}
    local store = PP.Sample()
    store.host = {}
    hostArmed = true
    if not hostHooked then
        hostHooked = true
        hooksecurefunc("StaticPopup_Show", function(which)
            if hostArmed and HOSTED[which] then
                hostArmed = false
                C_Timer.After(0, function() host(which) end)
            end
        end)
        if StaticPopup_Hide then
            hooksecurefunc("StaticPopup_Hide", function(which)
                if HOSTED[which] then
                    hostNote("hidden " .. tostring(which))
                    if hostPanel then hostPanel:Hide() end
                end
            end)
        end
        local f = CreateFrame("Frame")
        for _, e in ipairs({ "PLAYER_CAMPING", "LOGOUT_CANCEL", "ADDON_ACTION_BLOCKED", "ADDON_ACTION_FORBIDDEN", "DELETE_ITEM_CONFIRM" }) do
            f:RegisterEvent(e)
        end
        f:SetScript("OnEvent", function(_, event, a, b) hostNote(event .. " " .. show(a) .. " " .. show(b)) end)
    end
    ns.Print("Popup probe: hosting armed. Type /camp (or start deleting an item), then click Cancel / No on the moved popup. /reload after.")
end

function PP.Command(arg)
    if arg == "try" then return PP.Try() end
    if arg == "host" then return hostTest() end
    local s = PP.Sample()
    ns.Print(("Popup probe: %d popup kinds. Logging popups and request events until /reload."):format(s.dialogCount or 0))
end
