-- Units/Legacy.lua
-- SuuUI's Legacy pages (step 3.2d, design boards "Legacy · Tree /
-- Challenges / Reward track") over Blizzard's Legacy window, which keeps
-- its tabs (SuuUI's look from the windows module).
-- A built-in module written against the public API only.
--
-- Forever's Legacy (probed 2026-10-14, /suu probe legacy):
--   points    the reward faction's renown is what you earned (2802), the
--             trees' currency (4225) what this character can spend and has
--             spent; GetMaxAvailableTraitCurrency the most there is
--   trees     Professions 1187, Adventure 1188, Progression 1189: one config
--             for all three, laid out left to right in the game (tiers 750
--             apart along x): shown top to bottom here like class talents;
--             "to be added in a future update" nodes counted, not drawn.
--             Planned with the game's staging; Apply is C_Traits.CommitConfig
--   challenges achievement categories (Classes, Tradeskills, Dungeons, Raids,
--             PvP, Adventure) and their sub-categories; only challenges that
--             earn Legacy points ("Earn 1 Legacy Point.")
--   rewards   the faction's renown levels and their rewards

local UI, T = SuuUI.UI, SuuUI.Tokens

local M = SuuUI.RegisterModule({
    id = "legacy",
    name = "Legacy",
    description = "SuuUI's Legacy pages: the trees, the challenges and the reward track.",
    api = "0.12",
    reloadToToggle = true,
    defaults = {},
})

local isSecret = issecretvalue or function() return false end
local function plain(v) return v ~= nil and not isSecret(v) end

local FACTION = 2802
local CURRENCY = 4225
local TREES = {
    { id = 1187, name = function() return _G.LEGACY_TREE_PROFESSIONS or "Professions" end },
    { id = 1188, name = function() return _G.LEGACY_TREE_ADVENTURE or "Adventure" end },
    { id = 1189, name = function() return _G.LEGACY_TREE_PROGRESSION or "Progression" end },
}
local STEP = 750

-- fn(...) safely, every value it returns (GetAchievementInfo returns a dozen)
local function results(ok, ...) if ok then return ... end end
local function call(fn, ...)
    if type(fn) ~= "function" then return nil end
    return results(pcall(fn, ...))
end

local function hex(token) return T.color[token].hex end

--------------------------------------------------------------------------------
-- Points
--------------------------------------------------------------------------------

function M:ConfigID()
    local id = call(C_Traits.GetConfigIDByTreeID, TREES[1].id)
    return plain(id) and id or nil
end

function M:Points()
    local earned = call(C_MajorFactions and C_MajorFactions.GetCurrentRenownLevel, FACTION) or 0
    local total = call(C_Traits.GetMaxAvailableTraitCurrency, CURRENCY, false) or 0
    local configID = self:ConfigID()
    local spent, cap, quantity = 0, 0, 0
    if configID then
        local c = call(C_Traits.GetTreeCurrencyInfo, configID, TREES[1].id, false)
        c = c and c[1]
        if c then
            spent = plain(c.spent) and c.spent or 0
            cap = plain(c.maxQuantity) and c.maxQuantity or 0
            quantity = plain(c.quantity) and c.quantity or 0
        end
    end
    return { earned = plain(earned) and earned or 0, total = plain(total) and total or 0,
        spent = spent, cap = cap, available = quantity, character = UnitName("player") }
end

--------------------------------------------------------------------------------
-- The trees
--------------------------------------------------------------------------------

local function isPlaceholder(ni, name)
    if name == "Unknown" then return true end
    local flags = plain(ni.flags) and ni.flags or 0
    return bit and bit.band and bit.band(flags, 2) ~= 0 or false
end

local function talentOf(configID, ni)
    local entryID = ni.activeEntry and ni.activeEntry.entryID or (ni.entryIDs and ni.entryIDs[1])
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

function M:Trees(configID)
    local staged = call(C_Traits.ConfigHasStagedChanges, configID) == true
    self.learned = self.learned or {}
    if not staged then self.learned = {} end
    local learned = self.learned
    local trees, all = {}, {}
    local minX, minY
    for i, def in ipairs(TREES) do
        local t = { id = def.id, name = def.name(), nodes = {}, links = {}, placeholders = 0 }
        trees[i] = t
        local currency = call(C_Traits.GetTreeCurrencyInfo, configID, def.id, false)
        t.points = currency and currency[1] and plain(currency[1].spentInTree) and currency[1].spentInTree or 0
        local byID = {}
        for _, nodeID in ipairs(call(C_Traits.GetTreeNodes, def.id) or {}) do
            local ni = call(C_Traits.GetNodeInfo, configID, nodeID)
            if ni and ni.isVisible ~= false and plain(ni.posX) and plain(ni.posY) and ni.maxRanks and ni.maxRanks > 0 then
                local talent = talentOf(configID, ni)
                if talent and isPlaceholder(ni, talent.name) then
                    t.placeholders = t.placeholders + 1
                elseif talent then
                    local current = ni.currentRank or ni.activeRank or 0
                    if not staged then learned[nodeID] = current end
                    local base = learned[nodeID]
                    if base == nil then base = math.min(ni.activeRank or 0, current) end
                    base = math.min(base, current)
                    local n = { id = nodeID, x = ni.posX, y = ni.posY, max = ni.maxRanks, rank = base, pending = current - base,
                        canPurchase = ni.canPurchaseRank and true or false,
                        open = ni.isAvailable and ni.meetsEdgeRequirements and true or false,
                        meetsEdges = ni.meetsEdgeRequirements and true or false,
                        conditions = ni.conditionIDs or {}, edges = ni.visibleEdges or {},
                        name = talent.name, icon = talent.icon, tree = t }
                    t.nodes[#t.nodes + 1] = n
                    byID[nodeID] = n
                    all[#all + 1] = n
                    minX = math.min(minX or n.x, n.x)
                    minY = math.min(minY or n.y, n.y)
                end
            end
        end
        t.byID = byID
    end
    -- top to bottom: the game's tiers (x) as rows, its rows (y) as columns
    local rows = 1
    for _, n in ipairs(all) do
        n.row = math.max(0, math.floor((n.x - minX) / STEP + 0.5))
        n.col = math.max(0, math.min(3, math.floor((n.y - minY) / STEP + 0.5)))
        rows = math.max(rows, n.row + 1)
    end
    local pending = 0
    for _, t in ipairs(trees) do
        for _, n in ipairs(t.nodes) do
            pending = pending + n.pending
            for _, e in ipairs(n.edges) do
                local to = e.targetNode and t.byID[e.targetNode]
                if to then
                    table.insert(t.links, { from = n, to = to, met = (n.rank + n.pending) >= n.max })
                    to.requires = to.requires or {}
                    table.insert(to.requires, n)
                end
            end
        end
        if t.placeholders > 0 then
            t.more = t.placeholders == 1 and "1 more talent in a future update" or (t.placeholders .. " more talents in a future update")
        end
    end
    if staged and pending == 0 then pending = 1 end
    return trees, rows, pending
end

function M:Editable()
    if InCombatLockdown() then return false, "Legacy talents can't change in combat." end
    return true
end

--------------------------------------------------------------------------------
-- Challenges
--------------------------------------------------------------------------------

-- A challenge's progress: a skill or count ("45/150"), or steps done.
local function progressOf(id)
    local n = call(GetAchievementNumCriteria, id) or 0
    if n == 1 then
        local _, _, done, quantity, required = call(GetAchievementCriteriaInfo, id, 1)
        -- once started ("0/42000" said nothing)
        if plain(quantity) and plain(required) and required and required > 1 and not done and quantity > 0 then
            return quantity .. "/" .. required
        end
    elseif n > 1 then
        local done = 0
        for k = 1, n do
            local _, _, ok = call(GetAchievementCriteriaInfo, id, k)
            if ok then done = done + 1 end
        end
        if done > 0 and done < n then return done .. "/" .. n end
    end
end

local function challengeTip(owner, id, name, description, points)
    local tip = GameTooltip
    tip:SetOwner(owner, "ANCHOR_RIGHT")
    GameTooltip_SetTitle(tip, name or "")
    if description and description ~= "" then GameTooltip_AddNormalLine(tip, description, true) end
    local n = call(GetAchievementNumCriteria, id) or 0
    if n > 1 then
        GameTooltip_AddBlankLineToTooltip(tip)
        for k = 1, math.min(n, 15) do
            local text, _, done = call(GetAchievementCriteriaInfo, id, k)
            if text and text ~= "" then
                if done then GameTooltip_AddColoredLine(tip, text, GREEN_FONT_COLOR or HIGHLIGHT_FONT_COLOR)
                else GameTooltip_AddDisabledLine(tip, text) end
            end
        end
    end
    if points then
        GameTooltip_AddBlankLineToTooltip(tip)
        GameTooltip_AddHighlightLine(tip, ("|cff%s+%d Legacy %s|r"):format(hex("gilt-text"), points, points == 1 and "point" or "points"))
    end
    tip:Show()
end

local function itemsIn(category)
    local out = {}
    local total = call(GetCategoryNumAchievements, category) or 0
    for i = 1, total do
        local id, name, _, completed, _, _, _, description, _, _, reward = call(GetAchievementInfo, category, i)
        local points = plain(reward) and reward and tonumber(reward:match("(%d+) Legacy Point"))
        if id and points then
            local item = { id = id, name = name, done = completed and true or false, points = points, order = i,
                progress = (not completed) and progressOf(id) or nil }
            item.onEnter = function(owner) challengeTip(owner, id, name, description, points) end
            item.onLeave = function() GameTooltip:Hide() end
            -- how close: progress as a fraction, for the cards' order
            local a, b = (item.progress or ""):match("(%d+)/(%d+)")
            item.closeness = (a and b and tonumber(b) > 0) and (tonumber(a) / tonumber(b)) or 0
            out[#out + 1] = item
        end
    end
    return out
end

function M:Challenges()
    local cats = call(GetCategoryList) or {}
    local children, tops = {}, {}
    for _, cat in ipairs(cats) do
        local _, parent = call(GetCategoryInfo, cat)
        if parent == -1 then tops[#tops + 1] = cat
        elseif parent then children[parent] = children[parent] or {}; table.insert(children[parent], cat) end
    end
    local list = {}
    for _, top in ipairs(tops) do
        local name = call(GetCategoryInfo, top)
        local groups = {}
        local own = itemsIn(top)
        if #own > 0 then groups[#groups + 1] = { name = "", items = own } end
        for _, sub in ipairs(children[top] or {}) do
            local items = itemsIn(sub)
            if #items > 0 then groups[#groups + 1] = { name = call(GetCategoryInfo, sub), items = items } end
        end
        local all, done = {}, 0
        for _, g in ipairs(groups) do
            g.done = 0
            for _, item in ipairs(g.items) do
                all[#all + 1] = item
                if item.done then done = done + 1; g.done = g.done + 1 end
            end
        end
        if #all > 0 then
            -- the card: what's closest first, then the rest, done last
            -- (ties keep the game's order: Novice, Experienced, Master)
            local short = {}
            for k, item in ipairs(all) do item.seq = k; short[#short + 1] = item end
            table.sort(short, function(a, b)
                if a.done ~= b.done then return not a.done end
                if a.closeness ~= b.closeness then return a.closeness > b.closeness end
                return a.seq < b.seq
            end)
            list[#list + 1] = { name = name, done = done, total = #all, items = short, groups = groups }
        end
    end
    return list
end

--------------------------------------------------------------------------------
-- The reward track
--------------------------------------------------------------------------------

local QUALITY = { [0] = "poor", "common", "uncommon", "rare", "epic", "legendary" }

function M:Rewards(earned)
    local mf = C_MajorFactions
    local stops = {}
    for _, lv in ipairs((mf and call(mf.GetRenownLevels, FACTION)) or {}) do
        local rewards = call(mf.GetRenownRewardsForLevel, FACTION, lv.level) or {}
        local r = rewards[1]
        -- the item's own name when the reward has none (found in game)
        if r and (not r.name or r.name == "") and r.itemID then
            r.name = (C_Item.GetItemNameByID and call(C_Item.GetItemNameByID, r.itemID)) or call(GetItemInfo, r.itemID)
            if not r.name and C_Item.RequestLoadItemDataByID then
                call(C_Item.RequestLoadItemDataByID, r.itemID)
                self.namesPending = true
            end
        end
        if r then
            local quality = r.itemID and C_Item.GetItemQualityByID and call(C_Item.GetItemQualityByID, r.itemID)
            local stop = { at = lv.level, name = r.name, icon = r.icon, quality = QUALITY[quality or 3] or "rare",
                collected = r.isCollected and true or false }
            stop.onEnter = function(owner)
                GameTooltip:SetOwner(owner, "ANCHOR_RIGHT")
                if r.itemID then GameTooltip:SetItemByID(r.itemID) else GameTooltip_SetTitle(GameTooltip, r.name or "") end
                if r.description and r.description ~= "" then
                    GameTooltip_AddBlankLineToTooltip(GameTooltip)
                    GameTooltip_AddNormalLine(GameTooltip, r.description, true)
                end
                GameTooltip:Show()
            end
            stop.onLeave = function() GameTooltip:Hide() end
            stops[#stops + 1] = stop
        end
    end
    local max = stops[#stops] and stops[#stops].at or 1
    local nextText
    for _, s in ipairs(stops) do
        if earned < s.at then
            nextText = ("Next reward at %d points: %s"):format(s.at, s.name or "")
            break
        end
    end
    return { earned = earned, max = max, stops = stops,
        next = nextText or "Every reward on the track is yours. Claim them from Innkeeper Wiley in Ratchet." }
end

--------------------------------------------------------------------------------
-- The pages
--------------------------------------------------------------------------------

function M:Render()
    local pages = self.pages
    if not pages then return end
    local points = self:Points()
    local configID = self:ConfigID()
    local trees, rows, pending = {}, 3, 0
    if configID then trees, rows, pending = self:Trees(configID) end
    if rows ~= self.treeRows then
        self.treeRows = rows
        if pages.tree:IsShown() and _G.LegacySystemFrame then self:Size(_G.LegacySystemFrame, "tree") end
    end
    self.configID = configID
    points.pending = pending
    for _, view in pairs(pages) do view.points:SetPoints(points) end
    if pages.tree:IsVisible() then
        local editable, why = self:Editable()
        for _, t in ipairs(trees) do
            for _, n in ipairs(t.nodes) do
                n.locked = not n.open and n.rank + n.pending == 0
                n.canSpend = editable and n.canPurchase and points.available > 0
            end
        end
        self.trees = trees
        pages.tree.body:SetData({ trees = trees, rows = rows, available = points.available, pending = pending,
            editable = editable, hint = (not editable and why) or "Click a talent to plan a point; nothing changes until you apply." })
    end
    if pages.challenges:IsVisible() then pages.challenges.body:SetCategories(self:Challenges()) end
    if pages.rewards:IsVisible() then
        self.namesPending = nil
        pages.rewards.body:SetTrack(self:Rewards(points.earned))
        -- item names still loading: once more in a moment
        self.nameTries = self.namesPending and (self.nameTries or 0) + 1 or 0
        if self.namesPending and self.nameTries <= 6 then C_Timer.After(0.5, function() self:QueueRender() end) end
    end
end

function M:QueueRender()
    if self.renderQueued then return end
    self.renderQueued = true
    C_Timer.After(0.1, function()
        self.renderQueued = nil
        if self:IsEnabled() then self:Render() end
    end)
end

function M:ShowTip(button, n)
    if not self.configID then return end
    local needs = {}
    if not n.meetsEdges then
        for _, from in ipairs(n.requires or {}) do
            if from.rank + from.pending < from.max then
                needs[#needs + 1] = ("Requires %d %s in %s"):format(from.max, from.max == 1 and "point" or "points", from.name)
            end
        end
    end
    local editable, why = self:Editable()
    UI.TraitTooltip(button, self.configID, n.id, { name = n.name, treeName = n.tree.name, conditions = n.conditions,
        canSpend = n.canSpend, pending = n.pending, needs = needs, blocked = (not editable) and why or nil })
end

-- One page: the points on top, its body under them, over Blizzard's page.
local PAGES = { tree = "TreePage", challenges = "ChallengesPage", rewards = "RewardTrackPage" }

function M:Page(f, kind)
    local blizz = f[PAGES[kind]]
    if not blizz then return nil end
    local view = CreateFrame("Frame", nil, f)
    view:SetPoint("TOPLEFT", f, "TOPLEFT", 20, -44)
    view:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -20, 16)
    view:SetFrameLevel(blizz:GetFrameLevel() + 50)
    view:EnableMouse(true)
    view.points = UI.LegacyPoints(view)
    view.points:SetPoint("TOPLEFT")
    view.points:SetPoint("TOPRIGHT")
    local S = T.space
    if kind == "tree" then
        view.body = UI.TalentTree(view)
        view.body.noSummary = true
        local body = view.body
        body.onClick = function(n)
            if not (n.canSpend and self.configID) then return end
            call(C_Traits.PurchaseRank, self.configID, n.id)
            self:Render()
        end
        body.onRemove = function(n)
            if not self.configID or n.pending <= 0 or not self:Editable() then return end
            call(C_Traits.RefundRank, self.configID, n.id)
            self:Render()
        end
        body.onEnter = function(b, n) self:ShowTip(b, n) end
        body.onLeave = function() GameTooltip:Hide() end
        body.onUndo = function()
            if self.configID then call(C_Traits.RollbackConfig, self.configID); self:Render() end
        end
        body.onApply = function()
            if not (self.configID and self:Editable()) then return end
            if call(C_Traits.CommitConfig, self.configID) == false then self:Print("The Legacy talents couldn't be applied.") end
            self:QueueRender()
        end
        body:Layout()
    elseif kind == "challenges" then
        view.body = UI.LegacyChallenges(view)
    else
        view.body = UI.LegacyRewards(view)
    end
    view.body:SetPoint("TOPLEFT", view.points, "BOTTOMLEFT", 0, -S["space-6"])
    view.body:SetPoint("BOTTOMRIGHT", view, "BOTTOMRIGHT", 0, 0)
    -- Blizzard's page off screen (still shown: it drives this one), so none
    -- of its buttons take the mouse outside SuuUI's page
    local placing = false
    local function away()
        placing = true
        blizz:ClearAllPoints()
        blizz:SetPoint("TOPLEFT", UIParent, "TOPRIGHT", 5000, 0)
        placing = false
    end
    blizz:SetAlpha(0)
    away()
    hooksecurefunc(blizz, "SetPoint", function() if not placing then C_Timer.After(0, away) end end)
    view:SetShown(blizz:IsShown())
    blizz:HookScript("OnShow", function() view:Show(); self:Size(f, kind); self:Render() end)
    blizz:HookScript("OnHide", function() view:Hide(); GameTooltip:Hide() end)
    return view
end

-- The window as tall as the page shown needs: the header, the points, the
-- page (two rows of cards; the trees and their foot; the track).
local TREE_BODY = 8 + 16 + 8 + (3 * 46 - 14) + 8 + 6 + 14 + 12 + 38
local TRACK_BODY = 36 + 12 + 6 + 8 + 16 + 28 + 20 + 14 + 12

function M:Size(f, kind)
    local S = T.space
    local body
    if kind == "tree" then body = TREE_BODY + (self.treeRows and (self.treeRows - 3) * 46 or 0)
    elseif kind == "rewards" then body = TRACK_BODY
    else body = 2 * UI.LEGACY_CARD_H + S["space-5"] end
    f:SetHeight(44 + (T.type.caption.lineHeight + 1 + 24) + S["space-6"] + body + 16)
end

function M:Build()
    local f = _G.LegacySystemFrame
    if not f or self.pages then return end
    self.pages = {}
    for kind in pairs(PAGES) do self.pages[kind] = self:Page(f, kind) end
    if not (self.pages.tree and self.pages.challenges and self.pages.rewards) then
        self.pages = nil
        return
    end
    for kind, view in pairs(self.pages) do if view:IsShown() then self:Size(f, kind) end end
    f:HookScript("OnShow", function() self:QueueRender() end)
    self:Render()
end

function M:OnEnable()
    self:Build()
    self:OnGameEvent("ADDON_LOADED", function() self:Build() end)
    local valid = C_EventUtils and C_EventUtils.IsEventValid
    for _, e in ipairs({ "TRAIT_CONFIG_UPDATED", "TRAIT_NODE_CHANGED", "TRAIT_TREE_CURRENCY_INFO_UPDATED",
                         "MAJOR_FACTION_RENOWN_LEVEL_CHANGED", "ACHIEVEMENT_EARNED", "CRITERIA_UPDATE",
                         "PLAYER_REGEN_ENABLED", "PLAYER_REGEN_DISABLED" }) do
        if not valid or valid(e) then
            self:OnGameEvent(e, function()
                if self.pages and _G.LegacySystemFrame and _G.LegacySystemFrame:IsVisible() then self:QueueRender() end
            end)
        end
    end
end
