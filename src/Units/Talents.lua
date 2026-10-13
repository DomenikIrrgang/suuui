-- Units/Talents.lua
-- SuuUI's Talents page (step 3.2c, design boards "Talents" and "Talent
-- nodes") over Blizzard's Talents tab of the spells window: the class's
-- three trees side by side, points planned until you apply them.
-- A built-in module written against the public API only.
--
-- Forever keeps a class's talents as one trait tree (C_Traits; probed
-- 2026-10-13 on a warrior: tree 1117, 52 nodes): the three classic trees are
-- its groups (C_Traits.GetGroupDisplayInfoByTreeID: name, icon; their points
-- from GetGroupCurrencyInfo), laid out left to right, 600 apart on a 4 × 7
-- grid; tier requirements are node conditions ("spend 20 points"), the
-- arrows its edges. Planning uses the game's own staging, as Blizzard's page
-- does: a click is C_Traits.PurchaseRank, a right-click RefundRank (planned
-- ranks only: learned ones are unlearned at a trainer), Undo RollbackConfig,
-- Apply C_ClassTalents.CommitConfig. Out of combat only.

local UI, T = SuuUI.UI, SuuUI.Tokens

local M = SuuUI.RegisterModule({
    id = "talents",
    name = "Talents",
    description = "SuuUI's Talents page: the three trees side by side, points planned until you apply them.",
    api = "0.12",
    reloadToToggle = true,
    defaults = {},
})

local isSecret = issecretvalue or function() return false end
local function plain(v) return v ~= nil and not isSecret(v) end

local STEP = 600          -- the grid's step in the tree's coordinates
local TREE_GAP = 1500     -- more than this between columns: another tree
-- the spells window's height on this tab: the header's 44 and the foot's
-- 16 around the page (summary, trees, foot: 426), and the specs' row with
-- two talent groups
local PAGE_H = 426
local SPECS_H = 42

--------------------------------------------------------------------------------
-- The game's data
--------------------------------------------------------------------------------

local function call(fn, ...)
    if type(fn) ~= "function" then return nil end
    local ok, a, b, c = pcall(fn, ...)
    if ok then return a, b, c end
end

-- The talent groups (two with dual spec): 1 is the primary.
function M:SpecGroups()
    local n = call(GetNumSpecGroups) or 1
    local active = call(C_SpecializationInfo and C_SpecializationInfo.GetActiveSpecGroup) or 1
    return plain(n) and n or 1, plain(active) and active or 1
end

function M:ConfigID()
    local groups, active = self:SpecGroups()
    local view = self.viewing or active
    if groups > 1 and view ~= active and C_SpecializationInfo and C_SpecializationInfo.GetCombatConfigIDForSpecGroup then
        local id = call(C_SpecializationInfo.GetCombatConfigIDForSpecGroup, view)
        if plain(id) and id then return id end
    end
    local id = call(C_ClassTalents.GetActiveConfigID)
    return plain(id) and id or nil
end

-- A node's talent: name, icon, spell, entry.
local function talentOf(configID, info)
    local entryID = info.activeEntry and info.activeEntry.entryID or (info.entryIDs and info.entryIDs[1])
    if not entryID then return nil end
    local entry = call(C_Traits.GetEntryInfo, configID, entryID)
    local def = entry and entry.definitionID and call(C_Traits.GetDefinitionInfo, entry.definitionID)
    local spellID = def and def.spellID
    local name = def and def.overrideName
    if (not name or name == "") and spellID then name = C_Spell.GetSpellName(spellID) end
    local icon = def and def.overrideIcon
    if (not icon or icon == 0) and spellID then icon = C_Spell.GetSpellTexture(spellID) end
    return { entryID = entryID, spellID = spellID, name = name or "?", icon = icon }
end

-- Everything the page shows, for the config viewed.
function M:Collect()
    local configID = self:ConfigID()
    if not configID then return nil end
    local info = call(C_Traits.GetConfigInfo, configID)
    local treeID = info and info.treeIDs and info.treeIDs[1]
    if not treeID then return nil end
    -- what is learned: each node's rank while nothing is planned (the
    -- game's committed rank counts planned ones too on Forever: found in
    -- game, Apply stayed off and right-click did nothing)
    local staged = call(C_Traits.ConfigHasStagedChanges, configID) == true
    self.learned = self.learned or {}
    if not staged or self.learnedFor ~= configID then
        self.learnedFor = configID
        if not staged then self.learned = {} end
    end
    local learned = self.learned
    -- the nodes, placed
    local nodes, byID = {}, {}
    local minY
    for _, nodeID in ipairs(call(C_Traits.GetTreeNodes, treeID) or {}) do
        local ni = call(C_Traits.GetNodeInfo, configID, nodeID)
        if ni and ni.isVisible ~= false and plain(ni.posX) and plain(ni.posY) and ni.maxRanks and ni.maxRanks > 0 then
            local talent = talentOf(configID, ni)
            if talent then
                local current = ni.currentRank or ni.activeRank or 0
                if not staged then learned[nodeID] = current end
                local base = learned[nodeID]
                if base == nil then base = math.min(ni.activeRank or 0, current) end
                base = math.min(base, current)
                local n = {
                    id = nodeID, x = ni.posX, y = ni.posY, max = ni.maxRanks,
                    rank = base, pending = current - base,
                    canPurchase = ni.canPurchaseRank and true or false,
                    canRefund = ni.canRefundRank and true or false,
                    open = ni.isAvailable and ni.meetsEdgeRequirements and true or false,
                    meetsEdges = ni.meetsEdgeRequirements and true or false,
                    conditions = ni.conditionIDs or {}, edges = ni.visibleEdges or {},
                    groups = ni.groupIDs,
                    name = talent.name, icon = talent.icon, spellID = talent.spellID, entryID = talent.entryID,
                }
                nodes[#nodes + 1] = n
                byID[nodeID] = n
                minY = math.min(minY or n.y, n.y)
            end
        end
    end
    if #nodes == 0 then return nil end
    -- the trees: columns more than TREE_GAP apart start a new one (left to
    -- right, as Blizzard draws the group headers)
    table.sort(nodes, function(a, b) if a.x ~= b.x then return a.x < b.x end return a.y < b.y end)
    local clusters, last = {}, nil
    for _, n in ipairs(nodes) do
        if not last or n.x - last > TREE_GAP then clusters[#clusters + 1] = { nodes = {} } end
        local c = clusters[#clusters]
        c.nodes[#c.nodes + 1] = n
        c.minX = math.min(c.minX or n.x, n.x)
        c.maxX = math.max(c.maxX or n.x, n.x)
        last = n.x
    end
    -- their names and points: the tree's groups, in order
    local displays = call(C_Traits.GetGroupDisplayInfoByTreeID, treeID) or {}
    local groupIDs = {}
    for i, d in ipairs(displays) do groupIDs[i] = d.groupID end
    local spentBy = {}
    for _, g in ipairs((#groupIDs > 0 and call(C_Traits.GetGroupCurrencyInfo, configID, groupIDs)) or {}) do
        local c = g.currencyInfos and g.currencyInfos[1]
        if c and plain(c.spent) then spentBy[g.traitNodeGroupID] = c.spent end
    end
    local trees = {}
    for i, c in ipairs(clusters) do
        -- the 4 columns: from the leftmost, or so the rightmost is column 3
        local base = math.min(c.minX, c.maxX - 3 * STEP)
        local display = displays[i]
        local t = { name = display and display.displayName or ("Tree " .. i), icon = display and display.icon,
            groupID = display and display.groupID, nodes = {}, links = {} }
        local points = 0
        for _, n in ipairs(c.nodes) do
            n.col = math.max(0, math.min(3, math.floor((n.x - base) / STEP + 0.5)))
            n.row = math.max(0, math.floor((n.y - minY) / STEP + 0.5))
            n.tree = t
            t.nodes[#t.nodes + 1] = n
            points = points + n.rank + n.pending
        end
        -- the game's count when it has one (planned points not in it)
        local spent = t.groupID and spentBy[t.groupID]
        t.points = spent and math.max(spent, points) or points
        trees[i] = t
    end
    -- the arrows (and who requires whom)
    for _, n in ipairs(nodes) do
        for _, e in ipairs(n.edges) do
            local to = e.targetNode and byID[e.targetNode]
            if to and to.tree == n.tree then
                local link = { from = n, to = to, met = (n.rank + n.pending) >= n.max }
                table.insert(n.tree.links, link)
                to.requires = to.requires or {}
                table.insert(to.requires, n)
            end
        end
    end
    -- the points to spend
    local available = 0
    local currency = call(C_Traits.GetTreeCurrencyInfo, configID, treeID, false)
    if currency and currency[1] and plain(currency[1].quantity) then available = currency[1].quantity end
    local pending = 0
    for _, n in ipairs(nodes) do pending = pending + n.pending end
    -- planned changes the counts can't see still make Apply and Undo work
    if staged and pending == 0 then pending = 1; self.unseenStaged = true else self.unseenStaged = nil end
    return { configID = configID, treeID = treeID, trees = trees, available = available, pending = pending, info = info, staged = staged }
end

-- Why a node can't take a point: the tree's points, or a talent above it.
function M:Requires(configID, n)
    for _, condID in ipairs(n.conditions) do
        local c = call(C_Traits.GetConditionInfo, configID, condID)
        if c and c.isMet == false and plain(c.spentAmountRequired) and c.spentAmountRequired > 0 then
            return ("Requires %d points in %s"):format(c.spentAmountRequired, n.tree.name)
        end
    end
    if not n.meetsEdges then
        for _, from in ipairs(n.requires or {}) do
            if from.rank + from.pending < from.max then
                return ("Requires %d %s in %s"):format(from.max, from.max == 1 and "point" or "points", from.name)
            end
        end
    end
end

-- Can talents change now? (Out of combat; Blizzard's own check.)
function M:Editable()
    if InCombatLockdown() then return false, "Talents can't change in combat." end
    local can, reason = call(C_ClassTalents.CanChangeTalents)
    if can == false then return false, plain(reason) and reason or nil end
    local _, active = self:SpecGroups()
    if (self.viewing or active) ~= active then return false, "Activate this specialization to change its talents." end
    return true
end

--------------------------------------------------------------------------------
-- The page
--------------------------------------------------------------------------------

-- The pages shown: SuuUI's own window, and the page over Blizzard's tab
-- (when something opens that: a tutorial, a toast).
function M:Pages()
    local out = {}
    for _, page in ipairs({ self.windowPage, self.page }) do
        if page and page:IsVisible() then out[#out + 1] = page end
    end
    return out
end

function M:Render()
    local pages = self:Pages()
    if #pages == 0 then return end
    local data = self:Collect()
    self.data = data
    self:FitWindow()
    for _, page in ipairs(pages) do self:Fill(page, data) end
end

function M:Fill(page, data)
    -- the specs: only with two talent groups
    local groups, active = self:SpecGroups()
    if groups > 1 then
        local list = {}
        for g = 1, groups do
            list[g] = { label = g == 1 and "Primary" or "Secondary", name = "", active = g == active }
        end
        page:SetSpecs(list, self.viewing or active)
    else
        page:SetSpecs(nil)
    end
    if not data then
        page:SetData({ hint = "No talents to show yet." })
        return
    end
    local editable, why = self:Editable()
    local trees = {}
    for i, t in ipairs(data.trees) do
        for _, n in ipairs(t.nodes) do
            n.locked = not n.open and n.rank + n.pending == 0
            n.canSpend = editable and n.canPurchase and data.available > 0
        end
        trees[i] = t
    end
    -- the spec's name: the tree with the most points
    local best
    for _, t in ipairs(trees) do if not best or t.points > best.points then best = t end end
    page:SetData({
        name = (best and best.points > 0) and best.name or (UnitClass("player")),
        trees = trees, available = data.available, pending = data.pending, editable = editable,
        hint = (not editable and why) or "Click a talent to plan a point; nothing changes until you apply.",
    })
end

function M:QueueRender()
    if self.renderQueued then return end
    self.renderQueued = true
    C_Timer.After(0, function()
        self.renderQueued = nil
        if self:IsEnabled() then self:Render() end
    end)
end

-- A node's tooltip: the game's own, built as Blizzard's talent buttons build
-- it (the title, "Rank 2/5", the talent's text at this rank and the next,
-- what a click does, what it still needs in red); asked for in game.
function M:ShowTip(button, n)
    local data = self.data
    if not data then return end
    local needs = {}
    if not n.meetsEdges then
        for _, from in ipairs(n.requires or {}) do
            if from.rank + from.pending < from.max then
                needs[#needs + 1] = ("Requires %d %s in %s"):format(from.max, from.max == 1 and "point" or "points", from.name)
            end
        end
    end
    local editable, why = self:Editable()
    UI.TraitTooltip(button, data.configID, n.id, { name = n.name, treeName = n.tree.name, conditions = n.conditions,
        canSpend = n.canSpend, pending = n.pending, needs = needs, blocked = (not editable) and why or nil })
end

function M:Purchase(n)
    local data = self.data
    if not data or not n.canSpend then return end
    call(C_Traits.PurchaseRank, data.configID, n.id)
    self:Render()
end

function M:Refund(n)
    local data = self.data
    if not data or n.pending <= 0 or not self:Editable() then return end
    call(C_Traits.RefundRank, data.configID, n.id)
    self:Render()
end

function M:Undo()
    local data = self.data
    if not data or data.pending <= 0 then return end
    call(C_Traits.RollbackConfig, data.configID)
    self:Render()
end

function M:Apply()
    local data = self.data
    if not data or data.pending <= 0 or not self:Editable() then return end
    local ok
    if C_ClassTalents.CommitConfig then ok = call(C_ClassTalents.CommitConfig, data.configID)
    else ok = call(C_Traits.CommitConfig, data.configID) end
    if ok == false then self:Print("The talents couldn't be applied.") end
    self:QueueRender()
end

--------------------------------------------------------------------------------
-- SuuUI's own Talents window (asked for in game: open beside the Spellbook,
-- which Blizzard's spells window can't: one tab at a time). N and the micro
-- menu's Talents button open it; in the middle of the screen.
--------------------------------------------------------------------------------

local HEAD_RISE = 40 -- the header above the window's top (SkinWindow, topInset 20)

function M:WindowHeight()
    return 44 + PAGE_H + 16 + (self:SpecGroups() > 1 and SPECS_H or 0)
end

function M:FitWindow()
    local w = self.window
    if w then w:SetSize(UI.TALENT_TREE_W + 40, self:WindowHeight()) end
end

function M:BuildWindow()
    if self.window then return end
    local f = CreateFrame("Frame", "SuuUITalents", UIParent)
    f:SetToplevel(true)
    f:EnableMouse(true)
    f:SetClampedToScreen(true)
    f:Hide()
    f:SetPoint("CENTER", UIParent, "CENTER", 0, -HEAD_RISE / 2)
    local close = CreateFrame("Button", nil, f)
    close:SetScript("OnClick", function() f:Hide() end)
    -- in the window row's middle group: beside the Legacy window when both
    -- are open (asked for in game)
    UI.SkinWindow(f, { title = "Talents", icon = "tree", binding = "TOGGLETALENTS", close = close, topInset = 20, under = "microMenu" })
    UI.CenterWindow(f, true)
    local page = UI.TalentTree(f)
    page:SetPoint("TOPLEFT", f, "TOPLEFT", 20, -44)
    page:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -20, 16)
    self:Wire(page)
    self.windowPage = page
    self.window = f
    self:FitWindow()
    -- added beside the window row's own (SetScript replaced them: opening
    -- Talents didn't close Legacy, found in game)
    f:HookScript("OnShow", function()
        PlaySound(SOUNDKIT and SOUNDKIT.IG_CHARACTER_INFO_OPEN or 839)
        self:Render()
        self:Emit("SUUUI_TALENTS_SHOWN", true)
    end)
    f:HookScript("OnHide", function()
        PlaySound(SOUNDKIT and SOUNDKIT.IG_CHARACTER_INFO_CLOSE or 840)
        GameTooltip:Hide()
        self:Emit("SUUUI_TALENTS_SHOWN", false)
    end)
    -- Esc closes it
    tinsert(UISpecialFrames, "SuuUITalents")
    -- the key: N (whatever opens Blizzard's talents) opens this one instead
    local toggle = CreateFrame("Button", "SuuUITalentsToggle", UIParent)
    toggle:SetScript("OnClick", function() self:Toggle() end)
    self.bindOwner = CreateFrame("Frame")
    self:BindKeys()
end

function M:Toggle()
    if not self.window then return end
    self.window:SetShown(not self.window:IsShown())
end

-- The talents key as an override binding onto SuuUI's button (out of combat:
-- bindings can't change in one).
function M:BindKeys()
    if not self.bindOwner then return end
    if InCombatLockdown() then self.bindAfterCombat = true return end
    ClearOverrideBindings(self.bindOwner)
    for _, key in ipairs({ GetBindingKey("TOGGLETALENTS") }) do
        if key then SetOverrideBindingClick(self.bindOwner, false, key, "SuuUITalentsToggle") end
    end
end

--------------------------------------------------------------------------------
-- Into the spells window
--------------------------------------------------------------------------------

-- The window at this tab's size (out of combat: it is protected); Blizzard's
-- size back when another tab shows.
function M:Size()
    local f = _G.PlayerSpellsFrame
    if not f or InCombatLockdown() then return end
    local width = UI.TALENT_TREE_W + 40
    local tall = 44 + PAGE_H + 16 + (self:SpecGroups() > 1 and SPECS_H or 0)
    local h, w = f:GetHeight(), f:GetWidth()
    if math.abs(h - tall) < 1 and math.abs(w - width) < 1 then return end
    if math.abs(h - tall) >= 1 then self.blizzHeight = h end
    if math.abs(w - width) >= 1 then self.blizzWidth = w end
    self.sizing = true
    f:SetHeight(tall)
    f:SetWidth(width)
    self.sizing = false
end

function M:Restore()
    local f = _G.PlayerSpellsFrame
    if not f or InCombatLockdown() or not (self.blizzHeight or self.blizzWidth) then return end
    self.sizing = true
    if self.blizzHeight then f:SetHeight(self.blizzHeight) end
    if self.blizzWidth then f:SetWidth(self.blizzWidth) end
    self.sizing = false
    self.blizzHeight, self.blizzWidth = nil, nil
end

function M:Wire(page)
    page.onClick = function(n) self:Purchase(n) end
    page.onRemove = function(n) self:Refund(n) end
    page.onEnter = function(b, n) self:ShowTip(b, n) end
    page.onLeave = function() GameTooltip:Hide() end
    page.onApply = function() self:Apply() end
    page.onUndo = function() self:Undo() end
    page.onSpec = function(i) self.viewing = i; self:Render() end
    page.onActivate = function()
        if InCombatLockdown() or not self.viewing then return end
        call(C_SpecializationInfo.SetActiveSpecGroup, self.viewing)
    end
end

function M:Build()
    local f = _G.PlayerSpellsFrame
    local tab = f and f.TalentsFrame
    if not tab or self.page or InCombatLockdown() then return end
    -- Blizzard's tab out of sight: see-through and off screen, still shown
    -- (its OnShow and OnHide drive this page). Only see-through, its 1212 ×
    -- 681 stuck out of the smaller window, and its talent buttons took the
    -- mouse there (tooltips, no camera: found in game). Back off screen
    -- whenever Blizzard places it again (out of combat: the window is
    -- protected).
    tab:SetAlpha(0)
    local function away()
        if InCombatLockdown() then self.awayAfterCombat = true return end
        self.placingTab = true
        tab:ClearAllPoints()
        tab:SetPoint("TOPLEFT", UIParent, "TOPRIGHT", 5000, 0)
        self.placingTab = false
    end
    self.away = away
    away()
    hooksecurefunc(tab, "SetPoint", function()
        if not self.placingTab then C_Timer.After(0, away) end
    end)
    local page = UI.TalentTree(f)
    page:SetPoint("TOPLEFT", f, "TOPLEFT", 20, -44)
    page:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -20, 16)
    page:SetFrameLevel(tab:GetFrameLevel() + 50)
    page:EnableMouse(true) -- Blizzard's buttons underneath get no clicks
    page:SetShown(tab:IsShown())
    self.page = page
    self:Wire(page)
    -- shown with Blizzard's tab
    -- in the middle of the screen while this tab shows (asked for in game);
    -- the other tabs stay in the row under the micro menu
    tab:HookScript("OnShow", function()
        page:Show()
        self:Size()
        UI.CenterWindow(f, true)
        self:Render()
    end)
    tab:HookScript("OnHide", function()
        page:Hide()
        GameTooltip:Hide()
        self:Restore()
        UI.CenterWindow(f, false)
    end)
    -- Blizzard sets the window's size again right after it shows
    local function again()
        if not self.sizing and tab:IsShown() then self:Size() end
    end
    hooksecurefunc(f, "SetHeight", again)
    hooksecurefunc(f, "SetWidth", again)
    hooksecurefunc(f, "SetSize", again)
    page:HookScript("OnSizeChanged", function() if page:IsVisible() then self:QueueRender() end end)
    if tab:IsShown() then self:Size(); UI.CenterWindow(f, true) end
    self:Render()
end

function M:OnEnable()
    self:BuildWindow()
    self:Build()
    self:OnGameEvent("UPDATE_BINDINGS", function() self:BindKeys() end)
    self:OnGameEvent("ADDON_LOADED", function() self:Build() end)
    local valid = C_EventUtils and C_EventUtils.IsEventValid
    for _, e in ipairs({ "TRAIT_CONFIG_UPDATED", "TRAIT_NODE_CHANGED", "TRAIT_TREE_CURRENCY_INFO_UPDATED",
                         "TRAIT_CONFIG_LIST_UPDATED", "ACTIVE_COMBAT_CONFIG_CHANGED", "PLAYER_TALENT_UPDATE",
                         "CHARACTER_POINTS_CHANGED", "PLAYER_LEVEL_UP", "PLAYER_REGEN_DISABLED" }) do
        if not valid or valid(e) then self:OnGameEvent(e, function() self:QueueRender() end) end
    end
    self:OnGameEvent("PLAYER_REGEN_ENABLED", function()
        if not self.page then self:Build() end
        if self.awayAfterCombat and self.away then self.awayAfterCombat = nil; self.away() end
        if self.bindAfterCombat then self.bindAfterCombat = nil; self:BindKeys() end
        if self.page and self.page:IsVisible() then self:Size() end
        self:QueueRender()
    end)
end
