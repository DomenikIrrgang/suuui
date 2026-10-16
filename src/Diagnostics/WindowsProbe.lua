-- Diagnostics/WindowsProbe.lua
-- "/suu probe windows": what the remaining windows (3.6: mail, merchant,
-- trainer, auction house, collections; 3.7, asked 2026-10-17: gossip, the
-- quest dialog, the dressing room, inspect and the inspected player's
-- talents) are on Forever, for their designs. "/suu probe windows now"
-- saves whatever is open (a window it doesn't know by name).
-- Saved in SuuUIProbe.windows on /reload; kept across runs, one entry per
-- window, so visit them one by one.
--   * now: which of their frames and APIs exist, and how the client's own
--     API documentation flags the functions behind buying, sending,
--     training and bidding (restrictions)
--   * then, for 30 minutes, each window as it opens: its frame tree (frames
--     and texts, sizes, anchors, protected or not), the frames it shows,
--     and a sample of what its APIs give (three merchant items, mails,
--     trainer services, the auction house's state, collection counts)
--
--   /suu probe windows    then visit a vendor, a mailbox, a class trainer,
--                         the auction house, open Collections; then /reload

local _, ns = ...

local WP = {}
ns.WindowsProbe = WP

local isSecret = issecretvalue or function() return false end

local function show(v, depth)
    depth = depth or 0
    if isSecret(v) then return "secret" end
    if v == nil then return "nil" end
    if type(v) == "table" then
        if depth > 2 then return "{…}" end
        local parts = {}
        for k, x in pairs(v) do
            if type(x) ~= "function" then parts[#parts + 1] = tostring(k) .. "=" .. show(x, depth + 1) end
            if #parts > 40 then break end
        end
        table.sort(parts)
        return "{" .. table.concat(parts, ", ") .. "}"
    end
    return tostring(v)
end

-- a call's every result, or why it failed
local function call(fn, ...)
    if type(fn) ~= "function" then return "missing" end
    local res = { pcall(fn, ...) }
    if not res[1] then return "error: " .. tostring(res[2]):sub(1, 160) end
    local parts = {}
    for i = 2, math.max(2, select("#", unpack(res))) do parts[#parts + 1] = show(res[i]) end
    return table.concat(parts, " | ")
end

local function raw(fn, ...)
    if type(fn) ~= "function" then return nil end
    local ok, a = pcall(fn, ...)
    if ok then return a end
end

-- "C_MountJournal.GetNumMounts" -> the function, or nil
local function resolve(path)
    local t = _G
    for part in path:gmatch("[^%.]+") do
        if type(t) ~= "table" then return nil end
        t = t[part]
    end
    return t
end

local function anchorOf(r)
    local ok, point, rel, relPoint, x, y = pcall(r.GetPoint, r, 1)
    if not ok or not point then return "" end
    local relName = rel and ((rel.GetName and rel:GetName()) or rel.suuProbeKey or "?") or "nil"
    return (" @%s>%s.%s %d,%d"):format(point, tostring(relName), tostring(relPoint), math.floor(x or 0), math.floor(y or 0))
end

-- frames and texts (no textures: the trees are long enough), 700 lines at most
local function tree(f, depth, out, prefix)
    if depth > 7 or not f or not f.GetChildren or #out >= 700 then return end
    local keys = {}
    for k, v in pairs(f) do if type(k) == "string" and type(v) == "table" and v.GetObjectType then keys[v] = k end end
    for _, r in ipairs({ f:GetRegions() }) do
        if r:GetObjectType() == "FontString" and #out < 700 then
            local text = r:GetText()
            if text and text ~= "" then
                out[#out + 1] = ("%s. %s [FS] shown=%s %dx%d \"%s\""):format(prefix, r:GetName() or keys[r] or "?",
                    show(r:IsShown()), math.floor(r:GetWidth() or 0), math.floor(r:GetHeight() or 0), show(text):sub(1, 60))
            end
        end
    end
    for _, c in ipairs({ f:GetChildren() }) do
        if #out >= 700 then return end
        c.suuProbeKey = keys[c]
        local okP, protected = pcall(c.IsProtected, c)
        out[#out + 1] = ("%s%s [%s] shown=%s %dx%d%s%s"):format(prefix, c:GetName() or keys[c] or "?", c:GetObjectType(),
            show(c:IsShown()), math.floor(c:GetWidth() or 0), math.floor(c:GetHeight() or 0), anchorOf(c),
            (okP and protected) and " PROTECTED" or "")
        tree(c, depth + 1, out, prefix .. "  ")
    end
end

-- The windows: their frames (classic and modern names, whichever exist),
-- their load-on-demand addons, the events they open on, their APIs.
local WINDOWS = {
    mail = {
        frames = { "MailFrame", "InboxFrame", "OpenMailFrame", "SendMailFrame" },
        events = { "MAIL_SHOW" },
        apis = { "GetInboxNumItems", "GetInboxHeaderInfo", "GetInboxItem", "GetInboxItemLink", "GetInboxText",
                 "TakeInboxItem", "TakeInboxMoney", "AutoLootMailItem", "DeleteInboxItem", "ReturnInboxItem",
                 "SendMail", "SetSendMailMoney", "SetSendMailCOD", "ClickSendMailItemButton", "GetSendMailPrice",
                 "CheckInbox", "HasNewMail", "C_Mail.CanCheckInbox", "C_Mail.HasInboxMoney", "C_Mail.IsCommandPending" },
    },
    merchant = {
        frames = { "MerchantFrame", "MerchantBuyBackItem", "MerchantRepairAllButton", "MerchantRepairItemButton",
                   "MerchantGuildBankRepairButton", "MerchantFrameLootFilter", "MerchantItem1" },
        events = { "MERCHANT_SHOW" },
        apis = { "GetMerchantNumItems", "GetMerchantItemInfo", "GetMerchantItemLink", "GetMerchantItemCostInfo",
                 "GetMerchantItemCostItem", "GetMerchantItemMaxStack", "BuyMerchantItem", "BuybackItem",
                 "GetNumBuybackItems", "GetBuybackItemInfo", "CanMerchantRepair", "RepairAllItems", "GetRepairAllCost",
                 "CanGuildBankRepair", "GetMerchantFilter", "SetMerchantFilter", "C_MerchantFrame.GetItemInfo",
                 "C_MerchantFrame.GetBuybackItemID", "C_MerchantFrame.IsMerchantItemRefundable", "C_Container.UseContainerItem" },
    },
    trainer = {
        frames = { "ClassTrainerFrame", "ClassTrainerFrameSkillStepButton", "ClassTrainerTrainButton",
                   "ClassTrainerFrameFilterDropdown", "ClassTrainerFrameScrollFrame" },
        addons = { "Blizzard_TrainerUI" },
        events = { "TRAINER_SHOW" },
        apis = { "GetNumTrainerServices", "GetTrainerServiceInfo", "GetTrainerServiceCost", "GetTrainerServiceDescription",
                 "GetTrainerServiceIcon", "GetTrainerServiceLevelReq", "GetTrainerServiceSkillReq", "GetTrainerServiceItemLink",
                 "GetTrainerServiceNumAbilityReq", "GetTrainerServiceAbilityReq", "GetTrainerServiceTypeFilter",
                 "SetTrainerServiceTypeFilter", "BuyTrainerService", "SelectTrainerService", "GetTrainerSelectionIndex",
                 "GetTrainerGreetingText", "IsTradeskillTrainer", "C_Trainer" },
    },
    auction = {
        frames = { "AuctionFrame", "AuctionFrameBrowse", "AuctionFrameBid", "AuctionFrameAuctions",
                   "AuctionHouseFrame", "AuctionHouseFrameBuyTab", "AuctionHouseFrameSellTab", "AuctionHouseFrameAuctionsTab" },
        addons = { "Blizzard_AuctionUI", "Blizzard_AuctionHouseUI" },
        events = { "AUCTION_HOUSE_SHOW" },
        apis = { "QueryAuctionItems", "CanSendAuctionQuery", "GetNumAuctionItems", "GetAuctionItemInfo", "GetAuctionItemLink",
                 "PlaceAuctionBid", "PostAuction", "StartAuction", "CalculateAuctionDeposit", "GetAuctionSellItemInfo",
                 "ClickAuctionSellItemButton", "SortAuctionItems", "GetOwnerAuctionItems",
                 "C_AuctionHouse.SendBrowseQuery", "C_AuctionHouse.ReplicateItems", "C_AuctionHouse.GetNumReplicateItems",
                 "C_AuctionHouse.PostItem", "C_AuctionHouse.PostCommodity", "C_AuctionHouse.PlaceBid",
                 "C_AuctionHouse.StartCommoditiesPurchase", "C_AuctionHouse.GetBrowseResults",
                 "C_AuctionHouse.IsThrottledMessageSystemReady", "C_AuctionHouse.GetAvailablePostCount",
                 "C_AuctionHouse.CalculateItemDeposit", "C_AuctionHouse.QueryOwnedAuctions" },
    },
    collections = {
        frames = { "CollectionsJournal", "MountJournal", "PetJournal", "ToyBox", "HeirloomsJournal", "WardrobeCollectionFrame",
                   "CollectionsJournalTab1", "CollectionsJournalTab2", "CollectionsJournalTab3", "CollectionsJournalTab4",
                   "CollectionsJournalTab5", "CollectionsJournalTab6" },
        addons = { "Blizzard_Collections" },
        apis = { "C_MountJournal.GetNumMounts", "C_MountJournal.GetNumDisplayedMounts", "C_MountJournal.GetMountIDs",
                 "C_MountJournal.SummonByID", "C_PetJournal.GetNumPets", "C_PetJournal.SummonPetByGUID",
                 "C_ToyBox.GetNumToys", "C_ToyBox.GetNumLearnedDisplayedToys", "C_Heirloom.GetNumHeirlooms",
                 "C_TransmogCollection.GetAllAppearanceSources", "C_TransmogCollection.GetCategoryCollectedCount",
                 "C_AccountStore", "C_MountJournal", "C_PetJournal", "C_ToyBox", "C_Heirloom", "C_TransmogCollection" },
    },
}
WINDOWS.gossip = {
    frames = { "GossipFrame", "GossipFrameGreetingPanel", "GossipGreetingText" },
    events = { "GOSSIP_SHOW" },
    apis = { "C_GossipInfo.GetText", "C_GossipInfo.GetOptions", "C_GossipInfo.GetAvailableQuests", "C_GossipInfo.GetActiveQuests",
             "C_GossipInfo.SelectOption", "C_GossipInfo.SelectAvailableQuest", "C_GossipInfo.SelectActiveQuest",
             "C_GossipInfo.CloseGossip", "C_GossipInfo.GetNumOptions", "C_GossipInfo.GetFriendshipReputation" },
}
WINDOWS.quest = {
    frames = { "QuestFrame", "QuestFrameDetailPanel", "QuestFrameProgressPanel", "QuestFrameRewardPanel", "QuestFrameGreetingPanel",
               "QuestModelScene", "QuestNPCModel" },
    events = { "QUEST_DETAIL", "QUEST_PROGRESS", "QUEST_COMPLETE", "QUEST_GREETING" },
    apis = { "GetTitleText", "GetQuestText", "GetObjectiveText", "GetProgressText", "GetRewardText", "GetGreetingText",
             "AcceptQuest", "DeclineQuest", "CompleteQuest", "GetQuestReward", "IsQuestCompletable", "GetNumQuestChoices",
             "GetNumQuestRewards", "GetQuestItemInfo", "GetQuestItemLink", "GetRewardMoney", "GetRewardXP", "GetNumQuestItems",
             "GetNumAvailableQuests", "GetNumActiveQuests", "GetAvailableTitle", "GetActiveTitle", "SelectAvailableQuest",
             "SelectActiveQuest", "GetQuestPortraitGiver", "C_QuestOffer.GetQuestRewardCurrencyInfo" },
}
WINDOWS.dressup = {
    frames = { "DressUpFrame", "DressUpFrameResetButton", "DressUpFrameCancelButton", "SideDressUpFrame", "DressUpFrameOutfitDropdown" },
    apis = { "DressUpItemLink", "DressUpVisual", "DressUpFrame_Show", "C_TransmogSets", "C_Transmog" },
}
WINDOWS.inspect = {
    frames = { "InspectFrame", "InspectPaperDollFrame", "InspectPVPFrame", "InspectTalentFrame", "InspectGuildFrame",
               "InspectFrameTab1", "InspectFrameTab2", "InspectFrameTab3", "InspectFrameTab4", "InspectModelFrame" },
    addons = { "Blizzard_InspectUI" },
    events = { "INSPECT_READY" },
    apis = { "NotifyInspect", "CanInspect", "ClearInspectPlayer", "GetInspectSpecialization", "C_PaperDollInfo.GetInspectItemLevel",
             "GetInventoryItemLink", "C_Traits.GetConfigInfo", "C_ClassTalents", "GetTalentInfo", "GetNumTalentTabs",
             "GetTalentTabInfo", "C_SpecializationInfo" },
}
local ORDER = { "mail", "merchant", "trainer", "auction", "collections", "gossip", "quest", "dressup", "inspect" }

-- Every large window open now (named or by its parent's key), to find the
-- ones the probe doesn't know by name (the inspected player's talents).
local function openWindows()
    local out = {}
    for _, f in ipairs({ UIParent:GetChildren() }) do
        local okS, shown = pcall(f.IsShown, f)
        if okS and shown and not f:IsForbidden() then
            local w, h = f:GetWidth() or 0, f:GetHeight() or 0
            if not (issecretvalue and (issecretvalue(w) or issecretvalue(h))) and w >= 250 and h >= 200 then
                local okP, protected = pcall(f.IsProtected, f)
                out[#out + 1] = ("%s [%s] %dx%d%s"):format(f:GetName() or "?", f:GetObjectType(), math.floor(w), math.floor(h),
                    (okP and protected) and " PROTECTED" or "")
            end
        end
    end
    table.sort(out)
    return out
end
WP.OpenWindows = openWindows

local function frameInfo(name)
    local f = _G[name]
    if not f then return "missing" end
    if type(f) ~= "table" or not f.GetObjectType then return "not a frame: " .. type(f) end
    local okP, protected = pcall(f.IsProtected, f)
    return ("%s shown=%s protected=%s %dx%d"):format(f:GetObjectType(), show(f:IsShown()), show(okP and protected),
        math.floor(f:GetWidth() or 0), math.floor(f:GetHeight() or 0))
end

local function apiInfo(path)
    local v = resolve(path)
    if v == nil then return "missing" end
    if type(v) == "table" then
        local n = {}
        for k, x in pairs(v) do if type(x) == "function" then n[#n + 1] = k end end
        table.sort(n)
        return "namespace: " .. table.concat(n, ", ")
    end
    return type(v)
end

-- The client's API documentation for these functions: every flag on them
-- (restrictions and the like), not their arguments.
local function docFlags(names)
    for _, a in ipairs({ "Blizzard_APIDocumentationBasic", "Blizzard_APIDocumentation", "Blizzard_APIDocumentationGenerated" }) do
        if C_AddOns.DoesAddOnExist and C_AddOns.DoesAddOnExist(a) and not C_AddOns.IsAddOnLoaded(a) then
            pcall(C_AddOns.LoadAddOn, a)
        end
    end
    local docs = _G.APIDocumentation
    if not (docs and docs.systems) then return "no APIDocumentation" end
    local want = {}
    for _, n in ipairs(names) do want[n] = true end
    local out = {}
    for _, sys in ipairs(docs.systems) do
        for _, fn in ipairs(sys.Functions or {}) do
            local full = (sys.Namespace and (sys.Namespace .. ".") or "") .. tostring(fn.Name)
            if want[full] or want[fn.Name] then
                local flags = {}
                for k, v in pairs(fn) do
                    if type(v) ~= "table" and type(v) ~= "function" and k ~= "Name" and k ~= "Type" then
                        flags[#flags + 1] = tostring(k) .. "=" .. tostring(v)
                    end
                end
                table.sort(flags)
                out[full] = #flags > 0 and table.concat(flags, " ") or "(no flags)"
            end
        end
    end
    return out
end

-- What each window's APIs give while it's open.
local SAMPLES = {
    mail = function(s)
        local n = raw(GetInboxNumItems) or 0
        s.inbox = call(GetInboxNumItems)
        s.headers = {}
        for i = 1, math.min(3, n) do s.headers[i] = call(GetInboxHeaderInfo, i) end
        s.sendPrice = call(GetSendMailPrice)
    end,
    merchant = function(s)
        local n = raw(GetMerchantNumItems) or 0
        s.items = call(GetMerchantNumItems)
        s.sample = {}
        for i = 1, math.min(3, n) do
            s.sample[i] = {
                info = call(GetMerchantItemInfo, i),
                infoC = C_MerchantFrame and call(C_MerchantFrame.GetItemInfo, i) or "no C_MerchantFrame",
                link = call(GetMerchantItemLink, i),
                cost = call(GetMerchantItemCostInfo, i),
                maxStack = call(GetMerchantItemMaxStack, i),
            }
        end
        s.buyback = call(GetNumBuybackItems)
        s.buyback1 = call(GetBuybackItemInfo, 1)
        s.repair = call(CanMerchantRepair)
        s.repairCost = call(GetRepairAllCost)
        s.guildRepair = call(CanGuildBankRepair)
        s.filter = call(GetMerchantFilter)
    end,
    trainer = function(s)
        local n = raw(GetNumTrainerServices) or 0
        s.services = call(GetNumTrainerServices)
        s.greeting = call(GetTrainerGreetingText)
        s.tradeskill = call(IsTradeskillTrainer)
        s.filters = {}
        for _, f in ipairs({ "available", "unavailable", "used" }) do s.filters[f] = call(GetTrainerServiceTypeFilter, f) end
        s.sample = {}
        for i = 1, math.min(4, n) do
            s.sample[i] = {
                info = call(GetTrainerServiceInfo, i),
                cost = call(GetTrainerServiceCost, i),
                level = call(GetTrainerServiceLevelReq, i),
                skill = call(GetTrainerServiceSkillReq, i),
                abilityReqs = call(GetTrainerServiceNumAbilityReq, i),
                desc = call(GetTrainerServiceDescription, i),
            }
        end
    end,
    auction = function(s)
        s.canQuery = type(CanSendAuctionQuery) == "function" and call(CanSendAuctionQuery) or "missing"
        s.listed = call(GetNumAuctionItems, "list")
        s.owner = call(GetNumAuctionItems, "owner")
        local ah = C_AuctionHouse
        if ah then
            s.throttleReady = call(ah.IsThrottledMessageSystemReady)
            s.replicate = call(ah.GetNumReplicateItems)
            s.postCount = call(ah.GetAvailablePostCount)
        end
    end,
    gossip = function(s)
        s.text = call(C_GossipInfo.GetText)
        s.options = call(C_GossipInfo.GetOptions)
        s.available = call(C_GossipInfo.GetAvailableQuests)
        s.active = call(C_GossipInfo.GetActiveQuests)
    end,
    quest = function(s)
        s.title = call(GetTitleText)
        s.text = call(GetQuestText)
        s.objective = call(GetObjectiveText)
        s.progress = call(GetProgressText)
        s.reward = call(GetRewardText)
        s.choices = call(GetNumQuestChoices)
        s.rewards = call(GetNumQuestRewards)
        s.firstChoice = call(GetQuestItemInfo, "choice", 1)
        s.firstReward = call(GetQuestItemInfo, "reward", 1)
        s.money = call(GetRewardMoney)
        s.xp = call(GetRewardXP)
        s.completable = call(IsQuestCompletable)
        s.portrait = call(GetQuestPortraitGiver)
    end,
    dressup = function(s) end,
    inspect = function(s)
        s.canInspect = call(CanInspect, "target")
        s.itemLevel = call(C_PaperDollInfo and C_PaperDollInfo.GetInspectItemLevel, "target")
        s.head = call(GetInventoryItemLink, "target", 1)
        s.talentTabs = call(GetNumTalentTabs, true)
        s.firstTab = call(GetTalentTabInfo, 1, true)
    end,
    collections = function(s)
        s.mounts = C_MountJournal and call(C_MountJournal.GetNumMounts) or "missing"
        s.mountsShown = C_MountJournal and call(C_MountJournal.GetNumDisplayedMounts) or "missing"
        s.pets = C_PetJournal and call(C_PetJournal.GetNumPets) or "missing"
        s.toys = C_ToyBox and call(C_ToyBox.GetNumToys) or "missing"
        s.heirlooms = C_Heirloom and call(C_Heirloom.GetNumHeirlooms) or "missing"
        local j = _G.CollectionsJournal
        s.tabs = {}
        for i = 1, 8 do
            local t = _G["CollectionsJournalTab" .. i]
            if t then
                local fs = t.Text or (t.GetFontString and t:GetFontString())
                s.tabs[i] = ("%s shown=%s"):format(show(fs and fs:GetText()), show(t:IsShown()))
            end
        end
        s.selectedTab = j and show(j.selectedTab) or "no journal"
    end,
}

local function store()
    SuuUIProbe = SuuUIProbe or {}
    if type(SuuUIProbe.windows) ~= "table" then SuuUIProbe.windows = {} end
    return SuuUIProbe.windows
end

-- One window as it shows now.
function WP.Snapshot(key)
    local def = WINDOWS[key]
    local s = { at = date("%Y-%m-%d %H:%M:%S"), combat = InCombatLockdown() }
    s.frames = {}
    for _, name in ipairs(def.frames) do s.frames[name] = frameInfo(name) end
    local ok, err = pcall(SAMPLES[key], s)
    if not ok then s.sampleError = tostring(err) end
    s.openWindows = openWindows()
    -- the open window's tree: the first of its frames that shows
    for _, name in ipairs(def.frames) do
        local f = _G[name]
        if type(f) == "table" and f.IsShown and f:IsShown() then
            local out = {}
            tree(f, 1, out, "")
            s.treeOf, s.tree = name, out
            break
        end
    end
    -- every named frame of its family that shows (popups, side panels)
    local prefix = def.frames[1]:gsub("Frame$", ""):gsub("Journal$", "")
    local named = {}
    for k, v in pairs(_G) do
        if type(k) == "string" and k:find("^" .. prefix) and type(v) == "table" and v.IsShown and v.GetObjectType
            and not k:find("%d$") then
            local okS, shown = pcall(v.IsShown, v)
            if okS and shown then named[#named + 1] = k .. " [" .. v:GetObjectType() .. "]" end
            if #named > 80 then break end
        end
    end
    table.sort(named)
    s.shownNamed = named
    store()[key] = s
    ns.Print(("Windows probe: %s saved (%s lines of its frames); /reload when you're done."):format(key, s.tree and #s.tree or 0))
end

-- What exists now, before any window opens.
function WP.Static()
    local w = store()
    w.static = { at = date("%Y-%m-%d %H:%M:%S") }
    local names = {}
    for _, key in ipairs(ORDER) do
        local def = WINDOWS[key]
        local s = { frames = {}, apis = {}, addons = {} }
        for _, a in ipairs(def.addons or {}) do
            s.addons[a] = ("exists=%s loaded=%s lod=%s"):format(
                show(C_AddOns.DoesAddOnExist and C_AddOns.DoesAddOnExist(a)), show(C_AddOns.IsAddOnLoaded(a)),
                show(C_AddOns.IsAddOnLoadOnDemand and C_AddOns.IsAddOnLoadOnDemand(a)))
        end
        for _, name in ipairs(def.frames) do s.frames[name] = frameInfo(name) end
        for _, api in ipairs(def.apis) do
            s.apis[api] = apiInfo(api)
            names[#names + 1] = api
        end
        w.static[key] = s
    end
    w.static.docs = docFlags(names)
end

-- For 30 minutes: each window as it opens (a moment after, when its
-- lists are filled); Collections when its journal shows.
function WP.Arm()
    local f = WP.frame or CreateFrame("Frame")
    WP.frame = f
    f:UnregisterAllEvents()
    local byEvent = {}
    for _, key in ipairs(ORDER) do
        for _, e in ipairs(WINDOWS[key].events or {}) do
            byEvent[e] = key
            pcall(f.RegisterEvent, f, e)
        end
    end
    local untilT = GetTime() + 30 * 60
    f:SetScript("OnEvent", function(_, event)
        if GetTime() > untilT then f:UnregisterAllEvents() return end
        local key = byEvent[event]
        if key then C_Timer.After(0.6, function() WP.Snapshot(key) end) end
    end)
    local function hookJournal()
        local j = _G.CollectionsJournal
        if j and not WP.journalHooked then
            WP.journalHooked = true
            j:HookScript("OnShow", function()
                if GetTime() <= untilT then C_Timer.After(0.6, function() WP.Snapshot("collections") end) end
            end)
        end
    end
    hookJournal()
    local d = _G.DressUpFrame
    if d and not WP.dressHooked then
        WP.dressHooked = true
        d:HookScript("OnShow", function()
            if GetTime() <= untilT then C_Timer.After(0.6, function() WP.Snapshot("dressup") end) end
        end)
    end
    if not WP.journalHooked and EventUtil and EventUtil.ContinueOnAddOnLoaded then
        EventUtil.ContinueOnAddOnLoaded("Blizzard_Collections", hookJournal)
    end
end

-- Whatever is open now: every large window and the tree of each.
function WP.Now()
    local s = { at = date("%Y-%m-%d %H:%M:%S"), combat = InCombatLockdown(), openWindows = openWindows(), trees = {} }
    for _, f in ipairs({ UIParent:GetChildren() }) do
        local okS, shown = pcall(f.IsShown, f)
        local w, h = f:GetWidth() or 0, f:GetHeight() or 0
        if okS and shown and not f:IsForbidden() and not (issecretvalue and (issecretvalue(w) or issecretvalue(h)))
            and w >= 250 and h >= 200 and f:GetName() and not f:GetName():find("^SuuUI") then
            local out = {}
            tree(f, 1, out, "")
            s.trees[f:GetName()] = out
        end
    end
    store().now = s
    ns.Print(("Windows probe: %d open windows saved; /reload to save them."):format(#s.openWindows))
end

function WP.Command(rest)
    if rest == "now" then return WP.Now() end
    WP.Static()
    WP.Arm()
    ns.Print("Windows probe: the frames and APIs saved. For 30 minutes, each window is saved as it opens: visit a vendor, a mailbox, a class trainer, the auction house and open Collections, then /reload.")
end
