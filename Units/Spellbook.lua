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
-- the level of a rank you know is that rank; the ones above follow it.
--
-- Each learned spell is a SecureActionButton (type "spell"): clicking casts
-- it, dragging puts it on a bar (C_SpellBook.PickupSpellBookItem, allowed
-- for addons: probed 2026-10-13). The buttons are set out of combat only:
-- switching school or page waits for the end of combat.

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

-- The schools: { name, icon, first, count } (General, then the specs).
function M:Schools()
    local out = {}
    for i = 1, C_SpellBook.GetNumSpellBookSkillLines() do
        local info = C_SpellBook.GetSpellBookSkillLineInfo(i)
        if info and not info.shouldHide and not info.isGuild then
            out[#out + 1] = { name = info.name, icon = info.iconID, first = info.itemIndexOffset + 1,
                count = info.numSpellBookItems }
        end
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
    local known = {} -- name -> { levels = set, maxRank, ranked }
    for _, s in ipairs(learnedAll) do
        local k = known[s.label] or { levels = {}, maxRank = 0 }
        known[s.label] = k
        if s.level then k.levels[s.level] = true end
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
        local k = known[name] or { levels = {}, maxRank = 0 }
        local ranked = k.ranked or #list > 1
        local next = k.maxRank
        for _, t in ipairs(list) do
            if not k.levels[t.level] then
                next = next + 1
                local trainable = t.level <= level
                out[#out + 1] = { label = name, rank = ranked and next or nil, icon = t.icon, text = t.text, cost = t.cost,
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
    for i, s in ipairs(schools) do
        local list, n = self:SchoolList(s, trainer)
        tabs[i] = { label = s.name, icon = s.icon, trainable = n, active = i == self.school }
        if i == self.school then current, toTrain = list, n end
    end
    self.book:SetSchools(tabs)
    self.book:SetHead(schools[self.school].name, toTrain)
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
    local book = UI.Spellbook(page, { rows = 6 })
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
            UI.ShowTooltip(c.button, { title = s.label, subtitle = s.rank and ("Rank " .. s.rank) or nil, description = s.text,
                meta = s.status == "trainable" and ("Train now at your class trainer · " .. coins(s.cost)) or ("Learn at level " .. s.level) })
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
    book:HookScript("OnShow", function() self:Shorten(); self:Render() end)
    book:HookScript("OnHide", function() self:Restore() end)
    -- Blizzard's UpdateSize sets the height again right after the window
    -- shows (in the same frame): shortened at once, so the tall one is never
    -- drawn (the flicker, found with /suu probe flicker)
    local function again()
        if not self.sizing and page:IsShown() then self:Shorten() end
    end
    hooksecurefunc(f, "SetHeight", again)
    hooksecurefunc(f, "SetSize", again)
    book:HookScript("OnSizeChanged", function() if book:IsVisible() then self:Render() end end)
    self:Render()
end

-- The Spellbook tab as tall as the Character window (asked for in game);
-- Blizzard's height back for the other tabs. Out of combat (protected).
local SHORT = 484

function M:Shorten()
    local f = _G.PlayerSpellsFrame
    if not f or InCombatLockdown() then return end
    -- the Character window's height on screen, in this window's own scale
    -- (they differ: found in game). Blizzard sets the Character window's
    -- scale when it first opens, so its height on screen is measured then
    -- and kept (per character); until then the design's height.
    local screen = self:CharData().characterHeight
    local target = screen and (screen / f:GetEffectiveScale()) or SHORT
    if math.abs(f:GetHeight() - target) < 1 then return end
    self.blizzHeight = f:GetHeight()
    self.sizing = true
    f:SetHeight(target)
    self.sizing = false
end

-- The Character window's height on screen, whenever it shows or resizes.
function M:MeasureCharacter()
    local cf = _G.CharacterFrame
    if not cf or not cf:IsVisible() then return end
    local h = cf:GetHeight() * cf:GetEffectiveScale()
    if h and h > 0 then
        self:CharData().characterHeight = h
        if self.book and self.book:IsVisible() then self:Shorten() end
    end
end

function M:Restore()
    local f = _G.PlayerSpellsFrame
    if not f or not self.blizzHeight or InCombatLockdown() then return end
    self.sizing = true
    f:SetHeight(self.blizzHeight)
    self.sizing = false
    self.blizzHeight = nil
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
        self:OnGameEvent(e, function() if self.book then self:Render() end end)
    end
    self:OnGameEvent("PLAYER_REGEN_ENABLED", function()
        if not self.book then self:Build() end
        if self.renderAfterCombat then
            self.renderAfterCombat = false
            self:Render()
        end
    end)
end
