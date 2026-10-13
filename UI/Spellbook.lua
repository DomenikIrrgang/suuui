-- UI/Spellbook.lua
-- The Spellbook page (design board "Spellbook"): the schools as icons down
-- the left (a gilt diamond by the open one, an arcane dot on one with spells
-- to train), then the school's name, "2 spells to train" in arcane and the
-- Unlearned spells and All ranks switches; the spells in two columns, each
-- an icon and its name over "Rank 3", "Passive", "Train now · 6g 50s" (arcane)
-- or "Level 58"; a pager along the foot.
--
--   local book = UI.Spellbook(parent, { rows = 6, edgeInset = 20 })  -- the page's
--                          -- distance from the window's edge (the schools centre between)
--   book:SetSchools({ { label, icon, trainable, active } }); book.onSchool = fn(i)
--   book:SetHead(title, toTrain[, all])   -- all = { count, cost (copper),
--                          -- short (true: you can't afford it all) }: every
--                          -- school's spells to train and what they cost,
--                          -- after the school's count, as room allows
--   book:SetSwitches(showUnlearned, allRanks); book.onSwitch = fn(key, on)
--   book:SetSpells(list)   -- { label, rank, sub, icon, status = "learned" |
--                          -- "passive" | "trainable" | "future" }, a page's worth
--   book:SetPage(page, pages); book.onPage = fn(delta)
--   book.cells[i].button   -- a SecureActionButton (the owner sets what it casts)
--   book:FitRows()         -- rows to the page's height (a page holds rows × 2)
--   book:SetWidest(px)     -- the longest name anywhere: columns as wide on every page
--   book.onEnter / onLeave / onDragStart = fn(i, cell)
-- Cells are secure buttons: SetSpells changes only their look; their
-- attributes are the owner's, and only out of combat.

local _, ns = ...

local UI, T = ns.UI, ns.Tokens
local S = T.space

local ICON = 36
local TAB = 32
local COLUMNS = 2

local Book = {}

local function cell(book, i)
    local c = book.cells[i]
    if c then return c end
    c = CreateFrame("Frame", nil, book.grid)
    c:SetHeight(ICON)
    local b = CreateFrame("Button", nil, c, "SecureActionButtonTemplate")
    b:SetSize(ICON, ICON)
    b:SetPoint("LEFT")
    -- down and up: a secure button acts on the one the game's "cast on key
    -- down" option says (on by default: up alone never cast, found in game)
    b:RegisterForClicks("LeftButtonDown", "LeftButtonUp")
    b:RegisterForDrag("LeftButton")
    c.button = b
    c.icon = UI.Icon(b, ICON)
    c.icon:SetAllPoints()
    c.icon:EnableMouse(false)
    c.label = UI.Text(c, "label", "ink")
    c.label:SetPoint("TOPLEFT", b, "TOPRIGHT", S["space-4"], -2)
    c.label:SetPoint("RIGHT")
    c.label:SetJustifyH("LEFT")
    c.label:SetWordWrap(false)
    c.sub = UI.Text(c, "caption", "ink-muted")
    c.sub:SetPoint("BOTTOMLEFT", b, "BOTTOMRIGHT", S["space-4"], 2)
    c.sub:SetPoint("RIGHT")
    c.sub:SetJustifyH("LEFT")
    c.sub:SetWordWrap(false)
    b:SetScript("OnEnter", function()
        c.icon:SetBorder("gilt")
        if book.onEnter then book.onEnter(i, c) end
    end)
    b:SetScript("OnLeave", function()
        book:DrawCell(c)
        if book.onLeave then book.onLeave(i, c) end
    end)
    b:SetScript("OnDragStart", function() if book.onDragStart then book.onDragStart(i, c) end end)
    book.cells[i] = c
    return c
end

function Book:DrawCell(c)
    local s = c.spell
    if not s then return end
    local st = s.status or "learned"
    if st == "trainable" then
        c.icon:SetState("dim")
        c.icon:SetBorder("arcane")
        c.sub:SetColor("arcane")
        c.label:SetColor("ink")
    elseif st == "future" then
        c.icon:SetState("dim")
        c.icon:SetBorder("gilt-hairline")
        c.sub:SetColor("ink-muted")
        c.label:SetColor("ink-muted")
    else
        c.icon:SetState("rest")
        c.icon:SetBorder("gilt-hairline")
        c.sub:SetColor("ink-muted")
        c.label:SetColor("ink")
    end
end

function Book:SetSpells(list)
    local width = self.main:GetWidth()
    -- the columns as wide as the longest name or line on the page, the pair
    -- centred; the rows centred between the head and the pager (found in
    -- game: half-width columns left space to the right, and a gap below)
    local widest = 0
    for i = 1, self.rows * COLUMNS do
        local s = list[i]
        if s then
            local name = (s.label or "") .. ((s.status ~= "learned" and s.status ~= "passive" and s.rank) and ("  Rank " .. s.rank) or "")
            widest = math.max(widest, UI.MeasureText("label", name), UI.MeasureText("caption", s.sub or ""))
        end
    end
    -- (the owner's widest name across every school, when given: the same
    -- columns on every page, one spell alone included: found in game)
    if self.widest then widest = math.max(widest, self.widest) end
    local colW = math.min((width - S["space-6"]) / COLUMNS, ICON + S["space-4"] + math.ceil(widest) + S["space-3"])
    local used = COLUMNS * colW + (COLUMNS - 1) * S["space-6"]
    local headH = 30 + S["space-4"]
    local room = self.main:GetHeight() - headH - self.foot:GetHeight() - S["space-4"]
    local gridH = self.rows * ICON + (self.rows - 1) * S["space-4"]
    self.grid:ClearAllPoints()
    self.grid:SetPoint("TOPLEFT", self.main, "TOPLEFT", math.max(0, (width - used) / 2), -(headH + math.max(0, (room - gridH) / 2)))
    self.grid:SetSize(used, gridH)
    for i = 1, self.rows * COLUMNS do
        local c = cell(self, i)
        local s = list[i]
        c.spell = s
        if s then
            local r, col = math.floor((i - 1) / COLUMNS), (i - 1) % COLUMNS
            c:ClearAllPoints()
            c:SetPoint("TOPLEFT", self.grid, "TOPLEFT", col * (colW + S["space-6"]), -r * (ICON + S["space-4"]))
            c:SetWidth(colW)
            c.icon:SetArt(s.icon)
            -- "Healing Wave  Rank 10" for a rank not learned yet (the rank in ink-muted)
            local name = s.label or ""
            if s.status ~= "learned" and s.status ~= "passive" and s.rank then
                name = name .. "  |cff" .. T.color["ink-muted"].hex .. "Rank " .. s.rank .. "|r"
            end
            c.label:SetValue(name)
            c.sub:SetValue(s.sub or "")
            self:DrawCell(c)
            c:Show()
        else
            c:Hide()
        end
    end
    -- the rows a taller page had
    for i = self.rows * COLUMNS + 1, #self.cells do self.cells[i]:Hide() end
end

-- As many rows as the page's height holds (out of combat: the cells are
-- secure buttons). Returns the rows.
function Book:FitRows()
    local h = self.main:GetHeight()
    if not h or h <= 0 or InCombatLockdown() then return self.rows end
    local room = h - (30 + S["space-4"]) - self.foot:GetHeight() - S["space-4"]
    local rows = math.max(1, math.floor((room + S["space-4"]) / (ICON + S["space-4"])))
    if rows ~= self.rows then
        self.rows = rows
        self.grid:SetHeight(rows * ICON + (rows - 1) * S["space-4"])
    end
    return rows
end

-- The longest name the book has anywhere (columns as wide on every page).
function Book:SetWidest(px)
    self.widest = px
end

function Book:SetSchools(list)
    for i, s in ipairs(list) do
        local t = self.tabs[i]
        if not t then
            t = CreateFrame("Button", nil, self.tabColumn)
            t:SetSize(TAB, TAB)
            t.icon = UI.Icon(t, TAB)
            t.icon:SetAllPoints()
            t.icon:EnableMouse(false)
            -- the "spells to train" mark, above the icon (the icon is a frame
            -- of its own: drawn on the tab, the mark sat under it)
            local over = CreateFrame("Frame", nil, t)
            over:SetAllPoints()
            over:SetFrameLevel(t.icon:GetFrameLevel() + 3)
            over:EnableMouse(false)
            t.ring = UI.Diamond(over, 9, "surface", "OVERLAY", 6)
            t.ring:SetPoint("CENTER", t, "TOPRIGHT", -2, -2)
            t.dot = UI.Diamond(over, 7, "arcane", "OVERLAY", 7)
            t.dot:SetPoint("CENTER", t, "TOPRIGHT", -2, -2)
            t.jewel = UI.Diamond(t, 5, "gilt")
            t.jewel:SetPoint("CENTER", t, "RIGHT", S["space-4"] + 2, 0)
            t:SetScript("OnClick", function() if self.onSchool then self.onSchool(t.index) end end)
            t:SetScript("OnEnter", function(btn)
                btn:SetAlpha(1)
                UI.ShowTooltip(btn, { title = btn.label, description = btn.trainable and btn.trainable > 0
                    and (btn.trainable .. (btn.trainable == 1 and " spell" or " spells") .. " to train") or nil })
            end)
            t:SetScript("OnLeave", function(btn) btn:SetAlpha(btn.active and 1 or 0.6); UI.HideTooltip() end)
            self.tabs[i] = t
        end
        t.index, t.label, t.trainable, t.active = i, s.label, s.trainable, s.active
        t.icon:SetArt(s.icon)
        t.dot:SetShown((s.trainable or 0) > 0)
        t.ring:SetShown((s.trainable or 0) > 0)
        t.jewel:SetShown(s.active and true or false)
        t:SetAlpha(s.active and 1 or 0.6)
        t:ClearAllPoints()
        -- centred between the window's edge (edgeInset to the left) and the divider
        t:SetPoint("TOP", self.tabColumn, "TOPLEFT", (40 - self.edgeInset) / 2, -(i - 1) * (TAB + S["space-3"]))
        t:Show()
    end
    for i = #list + 1, #self.tabs do self.tabs[i]:Hide() end
end

local function hex(token) return T.color[token].hex end

-- 3g 20s: the digits in ink and the units in coin colours, or all of it in
-- ember-text when you can't afford it.
local function coinText(copper, short)
    copper = math.max(0, math.floor(tonumber(copper) or 0))
    local g, s, c = math.floor(copper / 10000), math.floor(copper / 100) % 100, copper % 100
    local plain, parts = {}, {}
    local function part(v, unit, token)
        plain[#plain + 1] = v .. unit
        parts[#parts + 1] = short and (v .. unit) or ("|cff" .. hex("ink") .. v .. "|r|cff" .. hex(token) .. unit .. "|r")
    end
    if g > 0 then part(g, "g", "coin-gold") end
    if s > 0 then part(s, "s", "coin-silver") end
    if c > 0 or #parts == 0 then part(c, "c", "coin-copper") end
    local text = table.concat(parts, " ")
    if short then text = "|cff" .. hex("ember-text") .. text .. "|r" end
    return text, table.concat(plain, " ")
end

local function spells(n) return n .. (n == 1 and " spell" or " spells") end

function Book:SetHead(title, toTrain, all)
    self.title:SetValue(title or "")
    toTrain = toTrain or 0
    local count = all and all.count or 0
    if count <= 0 then
        self.toTrain:SetValue(toTrain > 0 and (spells(toTrain) .. " to train") or "")
        return
    end
    local cost, costPlain = coinText(all.cost, all.short)
    local muted = "|cff" .. hex("ink-muted")
    -- the longest form that fits before the switches
    local forms
    if toTrain == count then
        forms = { { spells(toTrain) .. " to train", " · " }, { toTrain .. " to train", " · " } }
    elseif toTrain > 0 then
        forms = { { spells(toTrain) .. " to train", " · " .. count .. " in all · " }, { toTrain .. " to train", " · " .. count .. " in all · " },
            { count .. " to train in all", " · " } }
    else
        forms = { { "", spells(count) .. " to train in other schools · " }, { "", count .. " to train elsewhere · " } }
    end
    local room = self.unlearned:GetParent():GetLeft() and self.toTrain:GetLeft()
        and (self.unlearned:GetParent():GetLeft() - self.toTrain:GetLeft() - S["space-5"]) or math.huge
    local pick = forms[#forms]
    for _, f in ipairs(forms) do
        if UI.MeasureText("caption", f[1] .. f[2] .. costPlain) <= room then pick = f break end
    end
    self.toTrain:SetText(pick[1] .. muted .. pick[2] .. "|r" .. cost)
    self.toTrain.value = nil
end

function Book:SetSwitches(unlearned, allRanks)
    self.unlearned:SetValue(unlearned)
    self.allRanks:SetValue(allRanks)
end

function Book:SetPage(page, pages)
    self.pageText:SetValue(("Page %d of %d"):format(page, math.max(1, pages)))
    self.prev:SetEnabledState(page > 1)
    self.next:SetEnabledState(page < pages)
end

local function switch(book, parent, label, key)
    local f = CreateFrame("Frame", nil, parent)
    f.toggle = UI.Toggle(f, { onChange = function(on) if book.onSwitch then book.onSwitch(key, on) end end })
    f.toggle:SetPoint("RIGHT")
    f.text = UI.Text(f, "label", "ink-muted")
    f.text:SetPoint("RIGHT", f.toggle, "LEFT", -S["space-3"], 0)
    f.text:SetValue(label)
    f:SetSize(f.text:GetUnboundedStringWidth() + S["space-3"] + 34, 18)
    return f
end

function UI.Spellbook(parent, opts)
    opts = opts or {}
    local book = CreateFrame("Frame", nil, parent)
    Mixin(book, Book)
    book.rows = opts.rows or 6
    book.edgeInset = opts.edgeInset or 0 -- from the window's edge to the page
    book.cells, book.tabs = {}, {}
    -- the schools' column and its rule
    book.tabColumn = CreateFrame("Frame", nil, book)
    book.tabColumn:SetPoint("TOPLEFT")
    book.tabColumn:SetPoint("BOTTOMLEFT")
    book.tabColumn:SetWidth(40)
    local rule = book:CreateTexture(nil, "ARTWORK")
    rule:SetColorTexture(UI.RGBA("gilt-faint"))
    rule:SetWidth(1)
    rule:SetPoint("TOPLEFT", book.tabColumn, "TOPRIGHT", 0, 0)
    rule:SetPoint("BOTTOMLEFT", book.tabColumn, "BOTTOMRIGHT", 0, 0)
    -- the main column
    local main = CreateFrame("Frame", nil, book)
    main:SetPoint("TOPLEFT", book.tabColumn, "TOPRIGHT", S["space-5"], 0)
    main:SetPoint("BOTTOMRIGHT")
    book.main = main
    book.title = UI.Text(main, "header", "gilt-text")
    book.title:SetPoint("TOPLEFT", 0, -6)
    book.toTrain = UI.Text(main, "caption", "arcane")
    book.toTrain:SetPoint("LEFT", book.title, "RIGHT", S["space-5"], 0)
    book.allRanks = switch(book, main, "All ranks", "allRanks").toggle
    book.allRanks:GetParent():SetPoint("TOPRIGHT", 0, -6)
    book.unlearned = switch(book, main, "Unlearned spells", "unlearned").toggle
    book.unlearned:GetParent():SetPoint("RIGHT", book.allRanks:GetParent(), "LEFT", -S["space-5"], 0)
    -- the grid
    book.grid = CreateFrame("Frame", nil, main)
    book.grid:SetPoint("TOPLEFT", 0, -(30 + S["space-4"]))
    book.grid:SetPoint("RIGHT")
    book.grid:SetHeight(book.rows * ICON + (book.rows - 1) * S["space-4"])
    -- the pager over a gilt-faint rule
    local foot = CreateFrame("Frame", nil, main)
    foot:SetPoint("BOTTOMLEFT")
    foot:SetPoint("BOTTOMRIGHT")
    foot:SetHeight(30 + S["space-3"])
    local frule = foot:CreateTexture(nil, "ARTWORK")
    frule:SetColorTexture(UI.RGBA("gilt-faint"))
    frule:SetHeight(1)
    frule:SetPoint("TOPLEFT")
    frule:SetPoint("TOPRIGHT")
    book.pageText = UI.Text(foot, "caption", "ink-muted")
    book.pageText:SetPoint("BOTTOM", 0, 8)
    book.prev = UI.Button(foot, { text = "", width = 30, onClick = function() if book.onPage then book.onPage(-1) end end })
    book.prev:SetPoint("RIGHT", book.pageText, "LEFT", -S["space-5"], 0)
    book.next = UI.Button(foot, { text = "", width = 30, onClick = function() if book.onPage then book.onPage(1) end end })
    book.next:SetPoint("LEFT", book.pageText, "RIGHT", S["space-5"], 0)
    for _, pair in ipairs({ { book.prev, "chevronLeft" }, { book.next, "chevronRight" } }) do
        local g = pair[1]:CreateTexture(nil, "OVERLAY")
        g:SetTexture("Interface\\AddOns\\SuuUI\\Media\\Textures\\Glyphs\\" .. pair[2] .. ".tga")
        g:SetSize(14, 14)
        g:SetPoint("CENTER")
        g:SetVertexColor(UI.RGBA("ink"))
    end
    book.foot = foot
    return book
end
