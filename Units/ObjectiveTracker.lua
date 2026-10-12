-- Units/ObjectiveTracker.lua
-- The objective tracker (step 2.3): your tracked quests on the world under
-- the minimap, top right (28px in, 300px down, under its clock), 260px wide. Titles in their
-- difficulty colour (the game's own: GetQuestDifficultyColor), objectives
-- with their counts, "Ready to turn in" once a quest is done; the mouse
-- wheel scrolls what doesn't fit the height (not in combat while quest
-- items show: their secure buttons can't move then). Blizzard's tracker is hidden
-- while this runs. A built-in module written against the public API only.
--
-- Quest items: SuuUI's secure action buttons (type "item") left of their
-- quest's title; a click is a secure use, so they work in combat. Secure
-- buttons are placed and set up out of combat only: in combat the quests
-- keep their places (a quest's height only grows) so a button never ends up
-- beside the wrong quest; everything is laid out again when combat ends.
-- During a boss fight (a boss unit exists: a secure state driver, so it
-- works in combat) the tracker collapses to its head and the item buttons
-- hide, out of the boss frames' way. The head's toggle is secure too.
-- Left click a quest: its details on the map; right click: focus, share,
-- stop tracking.

local UI, T = SuuUI.UI, SuuUI.Tokens
local S = T.space

local M = SuuUI.RegisterModule({
    id = "tracker",
    name = "Objective tracker",
    description = "Your tracked quests under the minimap, with quest items you can use in combat.",
    api = "0.11",
    reloadToToggle = true,
    defaults = {
        -- under the minimap's clock (it ends 271px down), space-6 clear
        position = { point = "TOPRIGHT", x = -28, y = -300 },
        shows = "always",
        maxHeight = 440,
        collapsed = false,            -- the head's toggle
        collapseInBossFights = true,
        items = true,                 -- quest items beside their quests
    },
})

local WIDTH = 260
local isSecret = issecretvalue or function() return false end
local function plain(v) return v ~= nil and not isSecret(v) end
local ITEM = UI.Size("icon-md")

--------------------------------------------------------------------------------
-- Quests from the game
--------------------------------------------------------------------------------

-- The game's difficulty colour, by its font name, as the design's token.
local DIFFICULTY_FONTS = {
    { "VeryDifficult", "very-difficult" }, { "Impossible", "impossible" }, { "Difficult", "difficult" },
    { "Standard", "standard" }, { "Trivial", "trivial" },
}
local function difficultyOf(level)
    if not (plain(level) and GetQuestDifficultyColor) then return "standard" end
    local ok, c = pcall(GetQuestDifficultyColor, level)
    local font = ok and type(c) == "table" and c.font
    if type(font) ~= "string" then return "standard" end
    for _, d in ipairs(DIFFICULTY_FONTS) do
        if font:find(d[1], 1, true) then return d[2] end
    end
    return "standard"
end

-- "0/2 Handful of Cattails" or "Cattails: 0/2" → the text and its count.
local function splitObjective(text)
    local count, rest = text:match("^(%d+%s*/%s*%d+)%s+(.+)$")
    if count then return rest, count end
    rest, count = text:match("^(.-):?%s+(%d+%s*/%s*%d+)$")
    if count then return rest, count end
    return text, nil
end

local function objectivesOf(questID)
    local out = {}
    local ok, list = pcall(C_QuestLog.GetQuestObjectives, questID)
    if not ok or type(list) ~= "table" then return out end
    for _, o in ipairs(list) do
        local text = plain(o.text) and o.text or ""
        local shown, count = splitObjective(text)
        out[#out + 1] = { text = shown, progress = count, done = plain(o.finished) and o.finished == true }
    end
    return out
end

-- One tracked quest as the tracker draws it (nil: not in the log).
local function questOf(questID)
    local logIndex = C_QuestLog.GetLogIndexForQuestID(questID)
    if not plain(logIndex) or not logIndex then return nil end
    local info = C_QuestLog.GetInfo(logIndex)
    if type(info) ~= "table" or info.isHeader or info.isHidden then return nil end
    local q = {
        questID = questID,
        logIndex = logIndex,
        title = plain(info.title) and info.title or "",
        difficulty = difficultyOf(info.difficultyLevel or info.level),
    }
    local complete = C_QuestLog.IsComplete(questID) or C_QuestLog.ReadyForTurnIn(questID)
    q.complete = plain(complete) and complete == true
    local failed = C_QuestLog.IsFailed and C_QuestLog.IsFailed(questID)
    q.failed = plain(failed) and failed == true
    if not q.complete then q.objectives = objectivesOf(questID) end
    -- a quest with nothing to count, not complete (rare): its text instead
    if q.complete and GetQuestLogCompletionText then
        local text = GetQuestLogCompletionText(logIndex)
        if plain(text) and text and text ~= "" then q.tooltip = { title = q.title, description = text } end
    end
    -- its usable item
    if GetQuestLogSpecialItemInfo then
        local ok, link, icon, charges, showWhenComplete = pcall(GetQuestLogSpecialItemInfo, logIndex)
        if ok and plain(link) and link and (not q.complete or showWhenComplete) then
            q.item = { link = link, icon = icon, charges = plain(charges) and charges or 0 }
        end
    end
    return q
end

function M:TrackedQuests()
    local out = {}
    local n = C_QuestLog.GetNumQuestWatches()
    if not plain(n) then return out end
    for i = 1, n do
        local id = C_QuestLog.GetQuestIDForQuestWatchIndex(i)
        if plain(id) and id then
            local q = questOf(id)
            if q then out[#out + 1] = q end
        end
    end
    return out
end

--------------------------------------------------------------------------------
-- Quest item buttons (secure)
--------------------------------------------------------------------------------

local function itemCooldown(b)
    if not b.logIndex or not GetQuestLogSpecialItemCooldown then return end
    local ok, start, duration, enable = pcall(GetQuestLogSpecialItemCooldown, b.logIndex)
    if ok and start and duration then
        pcall(b.cooldown.SetCooldown, b.cooldown, start, duration)
        local on = plain(duration) and duration > 1.5
        b.coolingDown = on and true or false
    else
        b.cooldown:Clear()
        b.coolingDown = false
    end
    b:UpdateArt()
end

-- In the quest's area: the design's "suggested" look (an arcane border, its
-- glow and an arcane ring just inside).
local function setSuggested(b, on)
    on = on and true or false
    if b.suggested == on then return end
    b.suggested = on
    if not b.suggest then
        b.suggest = CreateFrame("Frame", nil, b.over)
        b.suggest:SetAllPoints()
        UI.Border(b.suggest, "arcane", { layer = "OVERLAY" })
        UI.Border(b.suggest, "arcane", { inset = 2, layer = "OVERLAY" })
        UI.Shadow(b.suggest, "glow-arcane")
    end
    b.suggest:SetShown(on)
end

function M:ItemButton(i)
    self.itemButtons = self.itemButtons or {}
    local b = self.itemButtons[i]
    if b then return b end
    b = UI.ActionButton(self.holder, "SuuUIQuestItem" .. i, "icon-md")
    -- both: a secure button acts on the one the game's ActionButtonUseKeyDown names
    b:RegisterForClicks("AnyDown", "AnyUp")
    b:SetAttribute("type", "item")
    b:SetHotkey("")
    b.hasAction = true
    b.UpdateCooldown = itemCooldown
    b.ShowTooltip = function(self)
        if self.logIndex and GameTooltip.SetQuestLogSpecialItem then
            pcall(GameTooltip.SetQuestLogSpecialItem, GameTooltip, self.logIndex)
        elseif self.link then
            GameTooltip:SetHyperlink(self.link)
        end
    end
    self.itemButtons[i] = b
    return b
end

-- The buttons beside their quests (out of combat only).
function M:LayoutItems(quests)
    if InCombatLockdown() then self.pendingItems = true return end
    self.pendingItems = nil
    local used = 0
    -- placed even while collapsed: the holder hides them, and shows them
    -- in place when the tracker opens again, in combat too
    if self:Get("items") then
        for _, q in ipairs(quests) do
            local top = q.item and self.tracker:QuestTop(q.questID)
            if top then
                used = used + 1
                local b = self:ItemButton(used)
                b.logIndex, b.link = q.logIndex, q.item.link
                b:SetAttribute("item", q.item.link)
                b.art:SetTexture(q.item.icon)
                b.art:Show()
                b.count:SetText((q.item.charges or 0) > 1 and q.item.charges or "")
                b:ClearAllPoints()
                b:SetPoint("TOPRIGHT", self.holder, "TOPLEFT", -S["space-3"], -(top - 2))
                b:Show()
                itemCooldown(b)
            end
        end
    end
    for i = used + 1, #(self.itemButtons or {}) do
        local b = self.itemButtons[i]
        b:Hide()
        b:SetAttribute("item", nil)
        b.logIndex, b.link = nil, nil
    end
    self.itemsShown = used
end

-- Cooldowns and range, a few times a second while items show.
function M:TickItems()
    for i = 1, self.itemsShown or 0 do
        local b = self.itemButtons[i]
        if b.logIndex and IsQuestLogSpecialItemInRange then
            local ok, r = pcall(IsQuestLogSpecialItemInRange, b.logIndex)
            setSuggested(b, ok and plain(r) and r == 1)
        end
    end
end

--------------------------------------------------------------------------------
-- Collapsing: the head's toggle and boss fights (secure, so in combat too)
--------------------------------------------------------------------------------

local function bossDriver(on)
    return on and "[@boss1,exists] 1; 0" or "0"
end

function M:BuildSecure()
    -- the item buttons' holder at the tracker's top left; it hides while a
    -- boss exists or the tracker is collapsed
    local h = CreateFrame("Frame", "SuuUIObjectiveTrackerItems", self.frame, "SecureHandlerStateTemplate")
    h:SetPoint("TOPLEFT")
    h:SetSize(1, 1)
    h:SetAttribute("_onstate-boss", [=[
        if newstate == "1" or self:GetAttribute("usercollapsed") then self:Hide() else self:Show() end
    ]=])
    self.holder = h
    -- the head's toggle
    local b = CreateFrame("Button", "SuuUIObjectiveTrackerToggle", self.frame, "SecureHandlerClickTemplate")
    b:SetPoint("TOPLEFT")
    b:RegisterForClicks("LeftButtonUp")
    b:SetFrameRef("holder", h)
    b:SetAttribute("_onclick", [=[
        local h = self:GetFrameRef("holder")
        local collapsed = not h:GetAttribute("usercollapsed")
        h:SetAttribute("usercollapsed", collapsed)
        if collapsed or h:GetAttribute("state-boss") == "1" then h:Hide() else h:Show() end
    ]=])
    b:HookScript("OnClick", function()
        self:Set("collapsed", h:GetAttribute("usercollapsed") and true or false)
        self:ApplyCollapse()
    end)
    h:HookScript("OnAttributeChanged", function(_, name)
        if name == "state-boss" then self:ApplyCollapse() end
    end)
    self.toggle = b
end

function M:InBossFight()
    return self.holder:GetAttribute("state-boss") == "1" or (self.encounter and self:Get("collapseInBossFights"))
end

function M:ApplyCollapse()
    local collapsed = self:Get("collapsed") or self:InBossFight()
    self.tracker:SetCollapsed(collapsed and true or false)
end

-- The saved collapse and the boss setting, into the secure side (out of combat).
function M:ApplySecure()
    if InCombatLockdown() then self.pendingSecure = true return end
    self.pendingSecure = nil
    self.holder:SetAttribute("usercollapsed", self:Get("collapsed") and true or false)
    UnregisterStateDriver(self.holder, "boss")
    RegisterStateDriver(self.holder, "boss", bossDriver(self:Get("collapseInBossFights")))
    self:ApplyCollapse()
end

--------------------------------------------------------------------------------
-- Clicks on a quest
--------------------------------------------------------------------------------

function M:QuestClick(questID, button, row)
    if button == "LeftButton" then
        if QuestMapFrame_OpenToQuestDetails then pcall(QuestMapFrame_OpenToQuestDetails, questID) end
        return
    end
    if not (MenuUtil and MenuUtil.CreateContextMenu) then return end
    MenuUtil.CreateContextMenu(row, function(_, root)
        local title = C_QuestLog.GetTitleForQuestID and C_QuestLog.GetTitleForQuestID(questID)
        if plain(title) and title then root:CreateTitle(title) end
        if C_SuperTrack and C_SuperTrack.SetSuperTrackedQuestID then
            local focused = C_SuperTrack.GetSuperTrackedQuestID and C_SuperTrack.GetSuperTrackedQuestID() == questID
            root:CreateButton(focused and "Stop focusing" or "Focus", function()
                pcall(C_SuperTrack.SetSuperTrackedQuestID, focused and 0 or questID)
            end)
        end
        local pushable = C_QuestLog.IsPushableQuest and C_QuestLog.IsPushableQuest(questID)
        if plain(pushable) and pushable and IsInGroup() and QuestLogPushQuest then
            root:CreateButton("Share", function()
                if C_QuestLog.SetSelectedQuest then C_QuestLog.SetSelectedQuest(questID) end
                pcall(QuestLogPushQuest)
            end)
        end
        root:CreateButton("Open in quest log", function()
            if QuestMapFrame_OpenToQuestDetails then pcall(QuestMapFrame_OpenToQuestDetails, questID) end
        end)
        root:CreateButton("Stop tracking", function()
            pcall(C_QuestLog.RemoveQuestWatch, questID)
        end)
    end)
end

--------------------------------------------------------------------------------
-- Drawing
--------------------------------------------------------------------------------

function M:Refresh()
    self.refreshQueued = nil
    if not self.tracker then return end
    local quests = self:TrackedQuests()
    local combat = InCombatLockdown()
    -- in combat, with item buttons placed: keep everyone where they are
    local freeze = combat and (self.itemsShown or 0) > 0
    self.tracker:SetQuests(quests, freeze)
    local n = #quests
    self.tracker:SetMeta(n == 1 and "1 quest" or (n .. " quests"))
    self.quests = quests
    if combat then
        self.pendingItems = true
        -- the ones placed keep their cooldowns current
        for i = 1, self.itemsShown or 0 do itemCooldown(self.itemButtons[i]) end
    else
        self:LayoutItems(quests)
    end
    -- nothing tracked: nothing shown (the frame itself stays: it holds
    -- secure buttons, and its visibility is the Shows setting's)
    self.tracker:SetAlpha(n == 0 and 0 or 1)
    self.toggle:SetAlpha(n == 0 and 0 or 1)
end

-- Many quest events come at once: one refresh on the next frame.
function M:QueueRefresh()
    if self.refreshQueued then return end
    self.refreshQueued = true
    C_Timer.After(0, function() if self:IsEnabled() then self:Refresh() end end)
end

function M:ApplySize()
    if InCombatLockdown() then self.pendingSize = true return end
    self.pendingSize = nil
    local h = self:Get("maxHeight")
    self.frame:SetSize(WIDTH, h)
    self.tracker:SetMaxHeight(h)
    self:Refresh()
end

function M:ApplyShows()
    UI.SetVisibility(self.frame, self:Get("position").hidden and "hidden" or self:Get("shows"))
end

--------------------------------------------------------------------------------
-- Settings
--------------------------------------------------------------------------------

local PREVIEW_QUESTS = {
    { questID = 1, title = "The Ashmaw Den", difficulty = "difficult", objectives = {
        { text = "Ashmaw Ravager slain", progress = "3/8" },
        { text = "Ember Pelt", progress = "5/5", done = true },
    }, item = { preview = true, icon = 134075 } },
    { questID = 2, title = "Letters for the Crossroads", difficulty = "standard", complete = true },
    { questID = 3, title = "Speargrass Cuttings", difficulty = "trivial", objectives = {
        { text = "Handful of Cattails", progress = "0/2" },
        { text = "Speargrass Cuttings", progress = "1/4" },
    } },
}

function M:PreviewView(parent)
    if not self.preview then
        self.preview = UI.ObjectiveTracker(parent, { width = WIDTH })
        self.preview:SetQuests(PREVIEW_QUESTS)
        self.preview:SetMeta("3 quests")
    end
    self.preview:SetParent(parent)
    return self.preview
end

local SECTION = {
    id = "tracker", label = "Objective tracker", category = "World", order = 15,
    preview = function(parent) return M:PreviewView(parent) end,
    groups = {
        { title = "Objective tracker", description = "Your tracked quests under the minimap. Left click a quest for its details on the map; right click to focus, share or stop tracking it. Move it in edit mode.", rows = {
            { key = "shows", label = "Shows", control = "segmented", options = UI.VISIBILITY_OPTIONS, combat = true,
              description = "Always, only in combat, or when the mouse is over it." },
            { key = "maxHeight", label = "Height", control = "slider", min = 160, max = 800, step = 10, unit = "px", combat = true,
              description = "The most it takes down the screen; scroll with the mouse wheel for the quests below." },
            { key = "items", label = "Quest items", control = "toggle", combat = true,
              description = "A quest's usable item left of its title: click it to use, in combat too." },
            { key = "collapseInBossFights", label = "Collapse in boss fights", control = "toggle", combat = true,
              description = "Only the head while a boss is up (its quest items hide too); back after the fight." },
        } },
    },
}

--------------------------------------------------------------------------------
-- Lifecycle
--------------------------------------------------------------------------------

function M:OnEnable()
    if not C_QuestLog or not C_QuestLog.GetNumQuestWatches then return end
    if not self.frame then
        -- the placed frame: the tracker's whole height, so its secure parts'
        -- anchors never move in combat
        self.frame = CreateFrame("Frame", "SuuUIObjectiveTracker", SuuUI.Root)
        self.frame:SetFrameStrata("LOW")
        self:BuildSecure()
        self.tracker = UI.ObjectiveTracker(self.frame, { width = WIDTH, toggle = self.toggle })
        self.tracker:SetPoint("TOPLEFT")
        self.tracker.onQuestClick = function(id, button, row) self:QuestClick(id, button, row) end
        -- the items follow the list (out of combat: in combat it's locked
        -- while items show)
        self.tracker.onScroll = function()
            if not InCombatLockdown() and self.quests then self:LayoutItems(self.quests) end
        end
        self.toggle:SetFrameLevel(self.tracker:GetFrameLevel() + 5)
        local wait = 0
        self.frame:SetScript("OnUpdate", function(_, elapsed)
            wait = wait - elapsed
            if wait > 0 then return end
            wait = 0.25
            self:TickItems()
        end)
    end
    self.frame.suuManagedShow = true
    -- Blizzard's tracker out of sight while this runs
    if ObjectiveTrackerFrame and not self.blizzardHidden then
        self.blizzardHidden = true
        SuuUI.SuppressBlizzard(ObjectiveTrackerFrame)
    end
    self:RegisterMover(self.frame, { key = "position", label = "Objective tracker" })
    self:RegisterSettings(SECTION)
    self:ApplyShows()
    self:ApplySize()
    self:ApplySecure()
    self:Watch("shows", function() self:ApplyShows() end)
    self:Watch("position", function() self:ApplyShows() end)
    self:Watch("maxHeight", function() self:ApplySize() end)
    self:Watch("items", function() self:Refresh() end)
    self:Watch("collapseInBossFights", function() self:ApplySecure() end)
    local valid = C_EventUtils and C_EventUtils.IsEventValid
    for _, e in ipairs({ "QUEST_LOG_UPDATE", "QUEST_WATCH_LIST_CHANGED", "QUEST_WATCH_UPDATE", "QUEST_ACCEPTED",
                         "QUEST_REMOVED", "QUEST_TURNED_IN", "QUEST_ITEM_UPDATE", "PLAYER_LEVEL_UP",
                         "PLAYER_ENTERING_WORLD", "BAG_UPDATE_COOLDOWN" }) do
        if not valid or valid(e) then self:OnGameEvent(e, function() self:QueueRefresh() end) end
    end
    -- nearest first, as Blizzard's tracker sorts them (its own is off now)
    for _, e in ipairs({ "ZONE_CHANGED_NEW_AREA", "PLAYER_ENTERING_WORLD" }) do
        if not valid or valid(e) then
            self:OnGameEvent(e, function()
                if C_QuestLog.SortQuestWatches then pcall(C_QuestLog.SortQuestWatches) end
            end)
        end
    end
    -- a boss fight without a boss unit: the tracker (not its items) collapses
    for _, e in ipairs({ "ENCOUNTER_START", "ENCOUNTER_END" }) do
        if not valid or valid(e) then
            self:OnGameEvent(e, function(event)
                self.encounter = event == "ENCOUNTER_START"
                self:ApplyCollapse()
            end)
        end
    end
    -- secure item buttons can't move in combat: neither does the list then
    self:OnGameEvent("PLAYER_REGEN_DISABLED", function()
        self.tracker:SetScrollLocked((self.itemsShown or 0) > 0)
    end)
    self:OnGameEvent("PLAYER_REGEN_ENABLED", function()
        self.tracker:SetScrollLocked(false)
        if self.pendingSecure then self:ApplySecure() end
        if self.pendingSize then self:ApplySize() end
        self:Refresh()
    end)
end

function M:OnDisable()
    if self.frame then self.frame:Hide() end
end
