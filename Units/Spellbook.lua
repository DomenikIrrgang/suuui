-- Units/Spellbook.lua
-- SuuUI's Spellbook page (step 3.2b, design board "Spellbook") inside the
-- spells window's Spellbook tab, in place of Blizzard's page: the schools
-- down the left, two columns of spells, the unlearned ones too.
-- A built-in module written against the public API only.
--
-- What you know comes from the spellbook (C_SpellBook: every rank, the
-- flyouts' spells unpacked); what you don't from the class trainer's list
-- (Data/Trainer, from /suu probe class: name, level, cost, school, icon,
-- description). Ranks for those are worked out by level: a trainer entry at
-- or below the level of your best rank is yours (the book may hold only the
-- best one); the ones above follow it.
--
-- Each learned spell is a SecureActionButton (type "spell"): clicking casts
-- it, dragging puts it on a bar (C_SpellBook.PickupSpellBookItem, allowed
-- for addons: probed 2026-10-13). The buttons are set out of combat only:
-- switching school or page waits for the end of combat.
--
-- A level-up shows what it brings: the level-up card (UI.LevelUp, through
-- SuuUI.ShowLevelUp) in the alerts' place, out of combat (a level gained in
-- combat waits for its end). /suu levelup [level] shows it without one.

local UI, T = SuuUI.UI, SuuUI.Tokens

local M = SuuUI.RegisterModule({
    id = "spellbook",
    name = "Spellbook",
    description = "SuuUI's Spellbook page: your spells by school, the ones to train and still to come.",
    api = "0.12",
    reloadToToggle = true,
    defaults = {
        unlearned = true,
        allRanks = false,
        levelUp = true,     -- the level-up card
        untrained = false,  -- it lists earlier levels' spells still to train too
        trainingCost = true, -- what training it all costs: the page's head, the micro menu
        levelUpFor = 0,     -- seconds it stays; 0: 4 and 1 more for each spell shown
    },
})

local isSecret = issecretvalue or function() return false end
local function plain(v) return v ~= nil and not isSecret(v) end

local function coins(copper)
    copper = tonumber(copper) or 0
    local g, s, c = math.floor(copper / 10000), math.floor(copper / 100) % 100, copper % 100
    local parts = {}
    if g > 0 then parts[#parts + 1] = g .. "g" end
    if s > 0 then parts[#parts + 1] = s .. "s" end
    if c > 0 or #parts == 0 then parts[#parts + 1] = c .. "c" end
    return table.concat(parts, " ")
end

local function rankOf(sub)
    return type(sub) == "string" and tonumber(sub:match("(%d+)")) or nil
end

--------------------------------------------------------------------------------
-- What you know
--------------------------------------------------------------------------------

local BANK = Enum.SpellBookSpellBank and Enum.SpellBookSpellBank.Player or 0
local ITEM = Enum.SpellBookItemType or { Spell = 1, FutureSpell = 2, PetAction = 3, Flyout = 4 }

-- The schools: { name, icon, first, count } (General, then the three talent
-- trees). A tree you have no spell in yet (at level 1) is there too, from
-- the class's talents and the trainer's list: its spells to come show with
-- their level (asked for in game).
function M:Schools()
    local book, byName = {}, {}
    for i = 1, C_SpellBook.GetNumSpellBookSkillLines() do
        local info = C_SpellBook.GetSpellBookSkillLineInfo(i)
        if info and not info.shouldHide and not info.isGuild then
            local s = { name = info.name, icon = info.iconID, first = info.itemIndexOffset + 1, count = info.numSpellBookItems }
            book[#book + 1] = s
            byName[s.name] = s
        end
    end
    -- the trees, in order
    local _, class = UnitClass("player")
    local trees = {}
    for _, t in ipairs(SuuUI.ClassTalents and SuuUI.ClassTalents(class) or {}) do
        if t.tree and t.spec and not trees[t.tree] then trees[t.tree] = t.spec end
    end
    -- a tree's own icon: the game's spec info (when its name is the tree's),
    -- else the tree's earliest trainer spell (alphabetical was wrong: found
    -- in game)
    local _, _, classID = UnitClass("player")
    local function treeIcon(name, tree)
        local tries = {
            function() local _, n, _, icon = GetSpecializationInfoForClassID(classID, tree); return n, icon end,
            function() local _, n, _, icon = C_SpecializationInfo.GetSpecializationInfo(tree); return n, icon end,
        }
        for _, try in ipairs(tries) do
            local ok, n, icon = pcall(try)
            if ok and icon and n == name then return icon end
        end
        local best
        for _, t in ipairs(SuuUI.TrainerSpells() or {}) do
            if t.school == name and t.icon and (not best or t.level < best.level) then best = t end
        end
        return best and best.icon
    end
    local out, used = {}, {}
    if book[1] then out[1] = book[1]; used[book[1]] = true end
    for tree = 1, 3 do
        local name = trees[tree]
        if name then
            local s = byName[name] or { name = name, icon = treeIcon(name, tree) or 134400, first = 1, count = 0 }
            out[#out + 1] = s
            used[s] = true
        end
    end
    -- anything else the spellbook has (another client's lines)
    for _, s in ipairs(book) do
        if not used[s] then out[#out + 1] = s end
    end
    return out
end

-- A school's learned spells, in the spellbook's order, flyouts unpacked.
function M:Learned(school)
    local list = {}
    for slot = school.first, school.first + school.count - 1 do
        local info = C_SpellBook.GetSpellBookItemInfo(slot, BANK)
        if info and info.itemType == ITEM.Flyout and GetFlyoutInfo and info.actionID then
            local _, _, n = GetFlyoutInfo(info.actionID)
            for j = 1, n or 0 do
                local spellID, _, known, name = GetFlyoutSlotInfo(info.actionID, j)
                if known and spellID then
                    local sub = C_Spell.GetSpellSubtext and C_Spell.GetSpellSubtext(spellID) or nil
                    list[#list + 1] = { label = name, spellID = spellID, rank = rankOf(sub), sub = sub,
                        icon = C_Spell.GetSpellTexture(spellID), status = "learned",
                        level = C_Spell.GetSpellLevelLearned and C_Spell.GetSpellLevelLearned(spellID) or 0 }
                end
            end
        elseif info and info.itemType == ITEM.Spell then
            local passive = info.isPassive and true or false
            list[#list + 1] = { label = info.name, spellID = info.spellID, slot = slot, rank = rankOf(info.subName),
                sub = passive and "Passive" or ((info.subName and info.subName ~= "") and info.subName or nil),
                icon = info.iconID, status = passive and "passive" or "learned",
                lowRank = C_SpellBook.IsSpellBookItemLowRank and C_SpellBook.IsSpellBookItemLowRank(slot, BANK) or false,
                level = C_Spell.GetSpellLevelLearned and info.spellID and C_Spell.GetSpellLevelLearned(info.spellID) or 0 }
        end
    end
    -- "Racial Passive" and the like keep their own words
    for _, s in ipairs(list) do
        if s.status == "passive" and s.rank == nil then
            local info = s.slot and C_SpellBook.GetSpellBookItemInfo(s.slot, BANK)
            if info and info.subName and info.subName ~= "" then s.sub = info.subName end
        end
    end
    return list
end

--------------------------------------------------------------------------------
-- What the trainer still has for you
--------------------------------------------------------------------------------

-- Trainer entries by school name (unknown schools go to General).
function M:TrainerBySchool(schools)
    local names = {}
    for _, s in ipairs(schools) do names[s.name] = true end
    local general = schools[1] and schools[1].name
    local by = {}
    for _, t in ipairs(SuuUI.TrainerSpells() or {}) do
        local school = names[t.school] and t.school or general
        if school then
            by[school] = by[school] or {}
            table.insert(by[school], t)
        end
    end
    return by
end

-- The ranks you don't have yet, from the trainer's entries for each name.
function M:Unlearned(entries, learnedAll)
    local known = {} -- name -> { levels = set, maxLevel, maxRank, ranked }
    for _, s in ipairs(learnedAll) do
        local k = known[s.label] or { levels = {}, maxRank = 0, maxLevel = 0 }
        known[s.label] = k
        if s.level then
            k.levels[s.level] = true
            if s.level > k.maxLevel then k.maxLevel = s.level end
        end
        if s.rank and s.rank > k.maxRank then k.maxRank = s.rank end
        if s.rank then k.ranked = true end
    end
    local byName, order = {}, {}
    for _, t in ipairs(entries or {}) do
        if not byName[t.name] then byName[t.name] = {}; order[#order + 1] = t.name end
        table.insert(byName[t.name], t)
    end
    local out, level = {}, UnitLevel("player") or 1
    for _, name in ipairs(order) do
        local list = byName[name]
        table.sort(list, function(a, b) return a.level < b.level end)
        local k = known[name] or { levels = {}, maxRank = 0, maxLevel = 0 }
        local ranked = k.ranked or #list > 1
        local next = k.maxRank
        for _, t in ipairs(list) do
            -- a rank at or below your best one's level is yours: the game
            -- drops lower ranks from the book once a higher one is learned
            -- (found in game: Devotion Aura Rank 3 alone at level 21 made
            -- the level 1 and 10 ranks "Rank 4 and 5" to train)
            if not k.levels[t.level] and t.level > k.maxLevel then
                next = next + 1
                local trainable = t.level <= level
                out[#out + 1] = { label = name, rank = ranked and next or nil, icon = t.icon, text = t.text, cost = t.cost,
                    fresh = known[name] == nil,
                    level = t.level, status = trainable and "trainable" or "future",
                    sub = trainable and ("Train now · " .. coins(t.cost)) or ("Level " .. t.level) }
            end
        end
    end
    table.sort(out, function(a, b)
        if a.status ~= b.status then return a.status == "trainable" end
        if a.level ~= b.level then return a.level < b.level end
        return a.label < b.label
    end)
    return out
end

-- A trainer rank's own spell ID, for the game's spell tooltip: of every ID
-- with its name (Data/Trainer, from the ID scan), the one the game says is
-- learned at that level; its rank and icon settle a tie. nil when none fits
-- (SuuUI's own tooltip then).
function M:SpellIDFor(s)
    local name, level = s.label or s.name, s.level
    if not name or not level then return nil end
    self.ids = self.ids or {}
    local key = name .. "#" .. level
    if self.ids[key] then return self.ids[key] end
    local best, bestScore = nil, 0
    for _, id in ipairs(SuuUI.TrainerSpellIDs()[name] or {}) do
        local score = 0
        local ok, learned = pcall(C_Spell.GetSpellLevelLearned, id)
        if ok and learned == level then score = score + 4 end
        if s.rank and C_Spell.GetSpellSubtext then
            local okR, sub = pcall(C_Spell.GetSpellSubtext, id)
            if okR and sub == ("Rank " .. s.rank) then score = score + 2 end
        end
        if s.icon and C_Spell.GetSpellTexture(id) == s.icon then score = score + 1 end
        if score > bestScore then best, bestScore = id, score end
    end
    -- the level, or the rank and icon together (a miss isn't kept: the
    -- game may not have loaded the spell's data yet)
    if bestScore < 3 then return nil end
    self.ids[key] = best
    return best
end

-- The last line of an unlearned spell's tooltip: train now (arcane) and the
-- cost in coin colours, or the level it comes at.
local function hex(token) return T.color[token].hex end
local function coinText(copper)
    copper = tonumber(copper) or 0
    local g, s, c = math.floor(copper / 10000), math.floor(copper / 100) % 100, copper % 100
    local parts = {}
    if g > 0 then parts[#parts + 1] = g .. "|cff" .. hex("coin-gold") .. "g|r" end
    if s > 0 then parts[#parts + 1] = s .. "|cff" .. hex("coin-silver") .. "s|r" end
    if c > 0 or #parts == 0 then parts[#parts + 1] = c .. "|cff" .. hex("coin-copper") .. "c|r" end
    return table.concat(parts, " ")
end
function M:TrainLine(s)
    if s.level and s.level <= (UnitLevel("player") or 1) then
        return "|cff" .. hex("arcane") .. "Train now at your class trainer|r  |cff" .. hex("ink") .. coinText(s.cost) .. "|r"
    end
    return "|cff" .. hex("ink-muted") .. "Learn at level " .. tostring(s.level) .. " · |r" .. coinText(s.cost)
end

-- An unlearned spell's tooltip: the game's own when its ID is found, with
-- the training line under it; else SuuUI's.
function M:ShowUnlearnedTip(owner, s)
    local id = self:SpellIDFor(s)
    if id then
        UI.SpellTooltip(owner, id, self:TrainLine(s))
        return
    end
    UI.ShowTooltip(owner, { title = s.label, subtitle = s.rank and ("Rank " .. s.rank) or nil, description = s.text,
        meta = s.status == "trainable" and ("Train now at your class trainer · " .. coins(s.cost)) or ("Learn at level " .. s.level) })
end

--------------------------------------------------------------------------------
-- The page
--------------------------------------------------------------------------------

-- The list a school shows, with the switches applied.
function M:SchoolList(school, trainer)
    local learned = self:Learned(school)
    local shown = {}
    if self:Get("allRanks") then
        shown = learned
    else
        -- only each spell's best rank (the spellbook marks lower ones; flyout
        -- spells by name)
        local best = {}
        for _, s in ipairs(learned) do
            if not s.lowRank then
                local b = best[s.label]
                if not b or (s.rank or 0) > (b.rank or 0) then best[s.label] = s end
            end
        end
        for _, s in ipairs(learned) do
            if best[s.label] == s then shown[#shown + 1] = s end
        end
    end
    local unlearned = self:Unlearned(trainer[school.name], learned)
    local list = {}
    for _, s in ipairs(shown) do list[#list + 1] = s end
    local toTrain, nextShown = 0, {}
    for _, s in ipairs(unlearned) do
        if s.status == "trainable" then toTrain = toTrain + 1 end
        if self:Get("unlearned") then
            -- without All ranks: only each spell's next rank to come
            if self:Get("allRanks") or not nextShown[s.label] then
                list[#list + 1] = s
                nextShown[s.label] = true
            end
        end
    end
    return list, toTrain
end

function M:Render()
    if not self.book or not self.book:IsVisible() then return end
    if InCombatLockdown() then
        self.renderAfterCombat = true
        return
    end
    local schools = self:Schools()
    if #schools == 0 then return end
    self.school = math.min(self.school or 2, #schools)
    if self.school < 1 then self.school = 1 end
    local trainer = self:TrainerBySchool(schools)
    local tabs = {}
    local current, toTrain
    local widest = 0
    for i, s in ipairs(schools) do
        local list, n = self:SchoolList(s, trainer)
        for _, sp in ipairs(list) do
            local name = (sp.label or "") .. ((sp.status ~= "learned" and sp.status ~= "passive" and sp.rank) and ("  Rank " .. sp.rank) or "")
            widest = math.max(widest, UI.MeasureText("label", name), UI.MeasureText("caption", sp.sub or ""))
        end
        tabs[i] = { label = s.name, icon = s.icon, trainable = n, active = i == self.school }
        if i == self.school then current, toTrain = list, n end
    end
    -- the window as wide as two columns of the longest name across every
    -- school (steady while paging): page insets 2 × 20, the schools' column
    -- 40 and its gap 12, two columns of icon 36 + 8 + text + 6, 20 apart;
    -- at least 560 (the head's switches), at most Blizzard's 809
    local want = math.floor(math.min(809, math.max(560, 40 + 52 + 2 * (50 + math.ceil(widest)) + 20)))
    if want ~= self.wantWidth then
        self.wantWidth = want
        self:Shorten()
    end
    self.book:SetWidest(widest)
    self.book:SetSchools(tabs)
    local okAll, count, cost = pcall(self.CountToTrain, self)
    local all = okAll and self:Get("trainingCost") and { count = count, cost = cost, short = (GetMoney() or 0) < cost } or nil
    self.book:SetHead(schools[self.school].name, toTrain, all)
    self.book:SetSwitches(self:Get("unlearned"), self:Get("allRanks"))
    -- as many as the page holds
    local perPage = self.book:FitRows() * 2
    local pages = math.max(1, math.ceil(#current / perPage))
    self.page = math.min(math.max(1, self.page or 1), pages)
    local slice = {}
    for i = 1, perPage do slice[i] = current[(self.page - 1) * perPage + i] end
    self.slice = slice
    self.book:SetSpells(slice)
    self.book:SetPage(self.page, pages)
    -- what each button casts: learned spells only
    for i, c in ipairs(self.book.cells) do
        local s = slice[i]
        local b = c.button
        if s and s.status == "learned" and s.spellID then
            b:SetAttribute("type", "spell")
            b:SetAttribute("spell", s.spellID)
        else
            b:SetAttribute("type", nil)
            b:SetAttribute("spell", nil)
        end
    end
end

--------------------------------------------------------------------------------
-- Building it into the spells window
--------------------------------------------------------------------------------

function M:Build()
    local f = _G.PlayerSpellsFrame
    local page = f and (f.SpellBookFrame or f.SpellbookFrame)
    if not page or self.book or InCombatLockdown() then return end
    -- Blizzard's page out of sight (still there underneath; SuuUI's covers it)
    for _, key in ipairs({ "CategoryTabSystem", "PagedSpellsFrame", "PagingControls", "SearchBox", "SearchBoxIcon",
                           "SettingsDropdown", "SettingsTopFaceIcon", "AssistedCombatRotationSpellFrame", "HelpPlateButton",
                           "SearchPreviewContainer", "PreviousCategoryIcon", "NextCategoryIcon" }) do
        local part = page[key]
        if part and part.SetAlpha then part:SetAlpha(0) end
    end
    for _, r in ipairs({ page:GetRegions() }) do if r:GetObjectType() == "Texture" then r:SetAlpha(0) end end
    local book = UI.Spellbook(page, { rows = 6, edgeInset = 20 })
    -- on the window itself (the window is shortened while this tab shows;
    -- Blizzard's page keeps its own, taller size)
    book:SetPoint("TOPLEFT", f, "TOPLEFT", 20, -44)
    book:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -20, 16)
    book:SetFrameLevel(page:GetFrameLevel() + 50)
    book:EnableMouse(true) -- Blizzard's buttons underneath get no clicks
    self.book = book
    book.onSchool = function(i)
        if InCombatLockdown() then return end
        self.school, self.page = i, 1
        self:Render()
    end
    book.onPage = function(delta)
        if InCombatLockdown() then return end
        self.page = (self.page or 1) + delta
        self:Render()
    end
    book.onSwitch = function(key, on)
        self:Set(key == "unlearned" and "unlearned" or "allRanks", on)
        self.page = 1
        self:Render()
    end
    book.onEnter = function(i, c)
        local s = self.slice and self.slice[i]
        if not s then return end
        if s.status == "learned" or s.status == "passive" then
            GameTooltip:SetOwner(c.button, "ANCHOR_RIGHT")
            if s.slot then GameTooltip:SetSpellBookItem(s.slot, BANK) else GameTooltip:SetSpellByID(s.spellID) end
            GameTooltip:Show()
        else
            self:ShowUnlearnedTip(c.button, s)
        end
    end
    book.onLeave = function()
        GameTooltip:Hide()
        UI.HideTooltip()
    end
    book.onDragStart = function(i)
        local s = self.slice and self.slice[i]
        if not s or s.status ~= "learned" then return end
        if s.slot then
            C_SpellBook.PickupSpellBookItem(s.slot, BANK)
        elseif C_Spell.PickupSpell then
            C_Spell.PickupSpell(s.spellID)
        end
    end
    -- Blizzard's maximise/minimise switches its own book between one and two
    -- pages: nothing to do with SuuUI's page, so it goes while this tab shows
    local function maxMin(on)
        local mm = f.MaximizeMinimizeButton
        if not mm then return end
        mm:SetAlpha(on and 1 or 0)
        if InCombatLockdown() then return end -- (inside a protected window)
        for _, b in ipairs({ mm:GetChildren() }) do b:EnableMouse(on) end
    end
    book:HookScript("OnShow", function() maxMin(false); self:Shorten(); self:Render() end)
    book:HookScript("OnHide", function() maxMin(true); self:Restore() end)
    -- Blizzard's UpdateSize sets the height again right after the window
    -- shows (in the same frame): shortened at once, so the tall one is never
    -- drawn (the flicker, found with /suu probe flicker)
    local function again()
        if not self.sizing and page:IsShown() then self:Shorten() end
    end
    hooksecurefunc(f, "SetHeight", again)
    hooksecurefunc(f, "SetWidth", again)
    hooksecurefunc(f, "SetSize", again)
    book:HookScript("OnSizeChanged", function() if book:IsVisible() then self:Render() end end)
    self:Render()
end

-- The Spellbook tab as tall as the Character window (asked for in game);
-- Blizzard's height back for the other tabs. Out of combat (protected).
local SHORT = 484
local TALL = SHORT + 44
-- as wide as the Character window with its stats pane: two columns of spell
-- names need no more (Blizzard's 809 left space to the right: found in game)
local NARROW = 631

function M:Shorten()
    local f = _G.PlayerSpellsFrame
    if not f or InCombatLockdown() then return end
    -- the Character window's open height and one row of spells more (36px
    -- icons, 8px apart: 44), asked for in game; no longer tied to the
    -- Character window
    local target = TALL
    local width = self.wantWidth or NARROW
    local narrow = math.abs(f:GetWidth() - width) < 1
    if math.abs(f:GetHeight() - target) < 1 and narrow then return end
    if math.abs(f:GetHeight() - target) >= 1 then self.blizzHeight = f:GetHeight() end
    if not narrow then self.blizzWidth = f:GetWidth() end
    self.sizing = true
    f:SetHeight(target)
    f:SetWidth(width)
    self.sizing = false
end

-- How many spells you could train now, across every school; said to the
-- rest of SuuUI (the micro menu marks its Spellbook button) whenever it may
-- have changed. Needs no window: the spellbook and trainer data are there.
-- Returns the count and what training all of it costs (copper).
function M:CountToTrain()
    local schools = self:Schools()
    local trainer = self:TrainerBySchool(schools)
    local total, cost = 0, 0
    for _, s in ipairs(schools) do
        for _, e in ipairs(self:Unlearned(trainer[s.name], self:Learned(s))) do
            if e.status == "trainable" then
                total = total + 1
                cost = cost + (tonumber(e.cost) or 0)
            end
        end
    end
    return total, cost
end

function M:SayToTrain()
    if self.sayTimer then return end
    self.sayTimer = C_Timer.NewTimer(1, function()
        self.sayTimer = nil
        if not self:IsEnabled() then return end
        local ok, n, cost = pcall(self.CountToTrain, self)
        if ok then self:Emit("SUUUI_SPELLS_TO_TRAIN", n, self:Get("trainingCost") and cost or nil) end
    end)
end

--------------------------------------------------------------------------------
-- What a level brings
--------------------------------------------------------------------------------

local LEVEL_UP = "suu:levelup"
local SHOWN = 10

-- The spells and ranks the trainer has for levels from..to that you don't
-- have, and with the Untrained setting the earlier levels' ones too (their
-- level as a note): this level's first, new spells first, then by name.
function M:NewBetween(from, to)
    local schools = self:Schools()
    local trainer = self:TrainerBySchool(schools)
    local older = self:Get("untrained")
    local list = {}
    for _, school in ipairs(schools) do
        for _, e in ipairs(self:Unlearned(trainer[school.name], self:Learned(school))) do
            local now = e.level >= from and e.level <= to
            if now or (older and e.level < from) then
                list[#list + 1] = { icon = e.icon, name = e.label, rank = e.rank, isNew = e.fresh, cost = tonumber(e.cost) or 0,
                    text = e.text, meta = self:TrainLine(e),
                    spellID = self:SpellIDFor(e), level = e.level,
                    old = not now, note = not now and ("Level " .. e.level) or nil }
            end
        end
    end
    table.sort(list, function(a, b)
        if a.old ~= b.old then return b.old end
        if a.isNew ~= b.isNew then return a.isNew end
        if a.name ~= b.name then return a.name < b.name end
        return (a.rank or 0) < (b.rank or 0)
    end)
    return list
end

local function spells(n) return n == 1 and "1 spell" or (n .. " spells") end

-- The card's content for reaching `level` (and any level since `from`); nil
-- when the trainer has nothing for you.
function M:LevelUpCard(level, from)
    local list = self:NewBetween(from or level, level)
    if #list == 0 then return nil end
    local cost, fresh, old = 0, 0, 0
    for _, sp in ipairs(list) do
        cost = cost + sp.cost
        if sp.old then old = old + 1 else fresh = fresh + 1 end
    end
    local detail
    if old == 0 then detail = (fresh == 1 and "1 new spell" or (fresh .. " new spells")) .. " to train"
    elseif fresh == 0 then detail = spells(old) .. " still to train"
    else detail = (fresh == 1 and "1 new spell" or (fresh .. " new spells")) .. ", " .. old .. " still to train" end
    local n = #list
    return {
        title = "Level " .. level,
        detail = detail,
        spells = list,
        more = n > SHOWN and ("+ " .. (n - SHOWN) .. " more in your Spellbook") or nil,
        cost = cost,
    }, n
end

-- The next level that brings the trainer something (for the preview and
-- /suu levelup).
function M:NextLevelUp()
    for l = (UnitLevel("player") or 1) + 1, 80 do
        local def = self:LevelUpCard(l)
        if def then return def end
    end
end

-- The card for reaching `level`; false when the trainer has nothing for you.
function M:ShowLevelUp(level, from)
    local def, n = self:LevelUpCard(level, from)
    if not def then return false end
    SuuUI.ShowLevelUp(LEVEL_UP, def)
    -- the setting's seconds, or 4 s and 1 more for each spell shown (14 at most)
    if self.levelTimer then self.levelTimer:Cancel() end
    local stay = tonumber(self:Get("levelUpFor")) or 0
    if stay <= 0 then stay = 4 + math.min(n, SHOWN) end
    self.levelTimer = C_Timer.NewTimer(stay, function()
        self.levelTimer = nil
        SuuUI.HideAlert(LEVEL_UP)
    end)
    return true
end

-- A level gained: now, or once combat ends.
function M:LevelGained(level)
    level = tonumber(level) or UnitLevel("player")
    self.levelFrom = math.min(self.levelFrom or level, level)
    self.levelTo = math.max(self.levelTo or level, level)
    if InCombatLockdown() then return end
    C_Timer.After(0.5, function()
        if not self.levelTo or InCombatLockdown() then return end
        local from, to = self.levelFrom, self.levelTo
        self.levelFrom, self.levelTo = nil, nil
        if self:Get("levelUp") then pcall(self.ShowLevelUp, self, to, from) end
    end)
end

-- The next level's card on screen (the settings' button, /suu levelup).
function M:PreviewLevelUp()
    for l = (UnitLevel("player") or 1) + 1, 80 do
        if self:ShowLevelUp(l) then return end
    end
    self:Print("Nothing left to learn from the trainer.")
end

-- The settings' preview: the next level's card at its real size.
function M:PreviewView(parent)
    if not self.previewView then
        local view = CreateFrame("Frame", nil, parent)
        view.card = UI.LevelUp(view)
        view.card:SetPoint("TOPLEFT")
        view.card:HookScript("OnSizeChanged", function(c) view:SetSize(c:GetWidth(), c:GetHeight()) end)
        self.previewView = view
        self:On("SUUUI_SETTING_CHANGED", function(_, namespace)
            if namespace == self.id and view:IsVisible() then self:DrawPreview() end
        end)
    end
    self.previewView:SetParent(parent)
    self:DrawPreview()
    return self.previewView
end

function M:DrawPreview()
    local view = self.previewView
    if not view then return end
    local ok, def = pcall(self.NextLevelUp, self)
    view.card:SetLevelUp(ok and def or { title = "Level " .. ((UnitLevel("player") or 1) + 1), detail = "Nothing left to learn from the trainer" })
    view:SetSize(view.card:GetWidth(), view.card:GetHeight())
end

local SECTION = {
    id = "spellbook", label = "Spellbook", category = "General", order = 27,
    preview = function(parent) return M:PreviewView(parent) end,
    previewNote = "Your next level that brings spells, as the card will show it.",
    groups = {
        { title = "Spells to train", description = "What your class trainer has for you now, across every school.", rows = {
            { key = "trainingCost", label = "Training cost", control = "toggle",
              description = "How many spells you can train in all and what that costs: in the Spellbook's head (in ember when you can't afford it all) and the micro menu's Spellbook tooltip." },
        } },
        { title = "Level up", description = "When you reach a level, a card where the alerts show lists what your class trainer now has for you, and what training all of it costs. Out of combat; a level gained in a fight waits for its end. It needs the Alerts module.", rows = {
            { key = "levelUp", label = "Level-up card", control = "toggle",
              description = "The new spells and ranks your trainer has for you when you reach a level." },
            { key = "levelUpFor", label = "Card stays", control = "slider", min = 0, max = 60, step = 5,
              format = function(v) return v == 0 and "By spells" or (v .. " s") end,
              description = "By spells: 4 seconds and one more for each spell on the card. Or always this many seconds.",
              disabled = function() if not M:Get("levelUp") then return true, "The level-up card is off." end end },
            { key = "untrained", label = "Spells still to train", control = "toggle",
              description = "The card lists the spells from earlier levels you haven't trained yet too, with the level they came at, until you train them.",
              disabled = function() if not M:Get("levelUp") then return true, "The level-up card is off." end end },
            { label = "Try it", control = "button", text = "Show the card",
              description = "Your next level's card on screen now.",
              onClick = function() M:PreviewLevelUp() end },
        } },
    },
}

-- The Character window resized while the Spellbook shows: the same height.
function M:MeasureCharacter()
    if self.book and self.book:IsVisible() then self:Shorten() end
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

function M:OnEnable()
    local cf = _G.CharacterFrame
    if cf then
        cf:HookScript("OnShow", function() C_Timer.After(0, function() self:MeasureCharacter() end) end)
        cf:HookScript("OnSizeChanged", function() self:MeasureCharacter() end)
    end
    self:Build()
    self:OnGameEvent("ADDON_LOADED", function() self:Build() end)
    for _, e in ipairs({ "SPELLS_CHANGED", "PLAYER_LEVEL_UP" }) do
        self:OnGameEvent(e, function()
            if self.book then self:Render() end
            self:SayToTrain()
        end)
    end
    self:OnGameEvent("PLAYER_ENTERING_WORLD", function() self:SayToTrain() end)
    -- the cost in ember when your money no longer covers it, and the setting
    self:OnGameEvent("PLAYER_MONEY", function()
        if self.book and self.book:IsVisible() then self:Render() end
    end)
    self:On("SUUUI_SETTING_CHANGED", function(_, namespace, key)
        if namespace ~= self.id or key ~= "trainingCost" then return end
        if self.book then self:Render() end
        self:SayToTrain()
    end)
    SuuUI.AllowAlertOutOfCombat(LEVEL_UP)
    self:RegisterSettings(SECTION)
    self:OnGameEvent("PLAYER_LEVEL_UP", function(_, level) self:LevelGained(level) end)
    -- as if you went from where you are now to that level: everything the
    -- levels in between bring, your settings applied (the card on or off
    -- aside), in combat too
    self:RegisterCommand("levelup", "Simulate reaching a level from where you are now: /suu levelup <level> (no level: the next one that brings spells).", function(arg)
        local level = tonumber(arg and arg:match("%d+"))
        if not level then return self:PreviewLevelUp() end
        local now = UnitLevel("player") or 1
        local from = level > now and (now + 1) or level
        if not self:ShowLevelUp(level, from) then
            self:Print(("Nothing from the trainer between level %d and %d."):format(from, level))
        end
    end)
    self:SayToTrain()
    self:OnGameEvent("PLAYER_REGEN_ENABLED", function()
        if self.levelTo then self:LevelGained(self.levelTo) end
        if not self.book then self:Build() end
        if self.renderAfterCombat then
            self.renderAfterCombat = false
            self:Render()
        end
    end)
end
