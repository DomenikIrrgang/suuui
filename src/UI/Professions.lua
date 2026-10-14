-- UI/Professions.lua
-- The Professions window's body (design boards "Professions · Overview" and
-- "Professions · Alchemy"): a rail of tabs down the right (the overview,
-- then each crafting profession), and the page:
--   overview  "Primary professions  2 of 2": two cards; "Secondary
--             professions": a row of cards. A card: the profession's icon,
--             name and rank, its skill bar, its spells (icon and name)
--   crafting  the skill bar and rank; the recipes (search, filters, by
--             category, in the game's difficulty colours, how many you can
--             make, an eye on tracked ones) beside the chosen recipe: its
--             product, what it needs (tools), its reagents (have / need), a
--             cooldown, Track, a quantity, Create all and Create
--
--   local p = UI.Professions(parent, { edgeInset = 20 })  -- the page's distance
--                          -- from the window's edge (the rail's tabs centre between)
--   p:SetTabs({ { key, label, icon, glyph } }, selected)   p.onTab(key)
--   p:SetOverview({ primary = { card }, secondary = { card } })
--     card = { name, rank, icon, skill, max, crafting, recipes = { learned,
--       total } (nil: not counted yet), spells = { spell } },
--       or { name, rank, icon, untrained = true, hint } for one not learned
--       (dimmed, the hint where the skill bar goes)
--     spell = { name, icon, active, onClick, onEnter(owner), onLeave, onDrag }
--     card.onDrag()           -- the card dragged (its profession's own spell)
--     card.onUnlearn()        -- a learned one: the trash glyph in its corner
--     p.onOpen(card)          -- a crafting profession's card clicked
--   p:SetCrafting({ name, rank, skill, max, recipes = { learned, total },
--       categories = { { name, recipes } },
--       selected (recipe id) })
--     recipe = { id, name, difficulty (0 optimal .. 3 trivial), canMake,
--       tracked, learned }
--   p:SetRecipe(r)            -- the chosen recipe, or nil
--     r = { name, quality (0-5), qualityName ("rare"), icon, makes, desc,
--       tools = { { name, met } }, reagents = { { name, icon, quality,
--       qualityName, have, need } }, cooldown (text), source (where to
--       learn it: { item = { icon, name, quality, qualityName, note,
--       onEnter(owner) }, lines = { text } }), tracked,
--       canMake, ready, why, onProduct(owner), onReagent(i, owner) }
--   p.onSelect(id), p.onRecipeEnter(recipe, owner), p.onSearch(text),
--   p.onFilters(list of "learned" | "unlearned" | "materials" | "skillup"), p.onTrack(on),
--   p.onCreate(count), p.onCreateAll()

local _, ns = ...

local UI, T = ns.UI, ns.Tokens
local S = T.space

local GLYPHS = "Interface\\AddOns\\SuuUI\\Media\\Textures\\Glyphs\\"
local RAIL_W = 44
local LIST_W = 250
local ROW_H = 20
local QUALITY = { [0] = "quality-poor", "quality-common", "quality-uncommon", "quality-rare", "quality-epic", "quality-legendary" }
-- the game's difficulty colours (the ones quest titles use)
local DIFFICULTY = { [0] = "quest-very-difficult", "quest-difficult", "quest-standard", "quest-trivial" }

UI.PROFESSIONS_W, UI.PROFESSIONS_H = 720, 600

local P = {}

-- a thin bar with its numbers ("83 / 150"), a caption before it ("Skill")
local BAR_LABEL_W = 50
local function skillBar(parent, label)
    local f = CreateFrame("Frame", nil, parent)
    f:SetHeight(T.type.numeric.lineHeight)
    f.num = UI.Text(f, "numeric", "ink")
    f.num:SetPoint("RIGHT")
    f.track = UI.Fill(f, "track", "ARTWORK")
    f.track:SetHeight(6)
    if label then
        f.label = UI.Text(f, "caption", "ink-muted")
        f.label:SetPoint("LEFT")
        f.label:SetValue(label)
        f.track:SetPoint("LEFT", f, "LEFT", BAR_LABEL_W, 0)
    else
        f.track:SetPoint("LEFT")
    end
    f.track:SetPoint("RIGHT", f.num, "LEFT", -S["space-4"], 0)
    f.fill = UI.Fill(f, "progress-fill", "ARTWORK", 1)
    f.fill:SetHeight(6)
    f.fill:SetPoint("LEFT", f.track, "LEFT")
    function f:SetSkill(skill, max)
        self.skill, self.max = skill or 0, max or 0
        self.num:SetValue(self.skill .. " / " .. self.max)
        self:Draw()
    end
    -- the fill from the numbers kept (the width settles after the first
    -- layout: drawn again then, the numbers untouched)
    function f:Draw()
        local frac = (self.max or 0) > 0 and math.min(1, (self.skill or 0) / self.max) or 0
        local w = self.track:GetWidth()
        self.fill:SetShown(frac > 0 and w > 0)
        if w > 0 then self.fill:SetWidth(math.max(0.01, w * frac)) end
    end
    f:SetScript("OnSizeChanged", function(self) if self.max then self:Draw() end end)
    return f
end

--------------------------------------------------------------------------------
-- The rail
--------------------------------------------------------------------------------

function P:SetTabs(list, selected)
    self.tabList = list or {}
    for i, t in ipairs(self.tabList) do
        local b = self.tabs[i]
        if not b then
            b = CreateFrame("Button", nil, self.rail)
            b:SetSize(32, 32)
            b.icon = UI.Icon(b, 28)
            b.icon:SetPoint("CENTER")
            b.glyph = b:CreateTexture(nil, "OVERLAY")
            b.glyph:SetSize(16, 16)
            b.glyph:SetPoint("CENTER")
            b.jewel = UI.Diamond(b, 7, "gilt")
            b.jewel:SetPoint("CENTER", b, "LEFT", -6, 0)
            b:SetScript("OnClick", function(self) if self.key and self.owner.onTab then self.owner.onTab(self.key) end end)
            b:SetScript("OnEnter", function(self)
                GameTooltip:SetOwner(self, "ANCHOR_LEFT")
                GameTooltip_SetTitle(GameTooltip, self.label or "")
                GameTooltip:Show()
            end)
            b:SetScript("OnLeave", function() GameTooltip:Hide() end)
            self.tabs[i] = b
        end
        b.owner, b.key, b.label = self, t.key, t.label
        b:ClearAllPoints()
        -- centred between the divider and the window's edge (edgeInset past
        -- the page), as the Spellbook's schools are
        b:SetPoint("TOP", self.rail, "TOP", self.edgeInset / 2, -(i - 1) * (32 + S["space-4"]))
        if t.icon then
            b.icon:SetArt(t.icon)
            b.icon:Show()
            b.glyph:Hide()
        else
            b.icon:SetArt(nil)
            b.icon:Show()
            b.glyph:SetTexture(GLYPHS .. (t.glyph or "book") .. ".tga")
            b.glyph:SetVertexColor(UI.RGBA("gilt-text"))
            b.glyph:Show()
        end
        local on = t.key == selected
        b.icon:SetBorder(on and "gilt" or "gilt-hairline")
        b.jewel:SetShown(on)
        b:Show()
    end
    for i = #self.tabList + 1, #self.tabs do self.tabs[i]:Hide() end
end

--------------------------------------------------------------------------------
-- Overview
--------------------------------------------------------------------------------

local function makeSpell(parent)
    local s = CreateFrame("Button", nil, parent)
    s:SetSize(120, 22)
    s.icon = UI.Icon(s, 20)
    s.icon:SetPoint("LEFT")
    s.label = UI.Text(s, "caption", "ink-muted")
    s.label:SetPoint("LEFT", s.icon, "RIGHT", S["space-3"], 0)
    s:SetScript("OnClick", function(self) if self.spell and self.spell.onClick then self.spell.onClick() end end)
    -- a gilt edge under the mouse: it does something (asked for in game)
    s:SetScript("OnEnter", function(self)
        self.icon:SetBorder("gilt")
        if self.spell and self.spell.onEnter then self.spell.onEnter(self) end
    end)
    s:SetScript("OnLeave", function(self)
        self.icon:SetBorder(self.spell and self.spell.active and "arcane" or nil)
        if self.spell and self.spell.onLeave then self.spell.onLeave() end
    end)
    -- onto an action bar (Disenchant: asked for in game)
    s:RegisterForDrag("LeftButton")
    s:SetScript("OnDragStart", function(self) if self.spell and self.spell.onDrag then self.spell.onDrag() end end)
    return s
end

local function makeCard(view)
    local c = CreateFrame("Button", nil, view.overview)
    UI.Fill(c, "surface-sunk"):SetAllPoints()
    c.border = UI.Border(c, "gilt-faint")
    c.icon = UI.Icon(c, "icon-lg")
    c.icon:SetPoint("TOPLEFT", S["space-5"], -S["space-5"])
    c.name = UI.Text(c, "header", "gilt-text")
    c.name:SetPoint("TOPLEFT", c.icon, "TOPRIGHT", S["space-4"], -1)
    c.rank = UI.Text(c, "caption", "ink-muted")
    c.rank:SetPoint("TOPLEFT", c.name, "BOTTOMLEFT", 0, -1)
    c.open = UI.Text(c, "caption", "gilt-text")
    c.open:SetPoint("TOPRIGHT", -S["space-5"], -S["space-5"] - 2)
    c.skill = skillBar(c, "Skill")
    c.skill:SetPoint("TOPLEFT", c.icon, "BOTTOMLEFT", 0, -S["space-4"])
    c.skill:SetPoint("RIGHT", c, "RIGHT", -S["space-5"], 0)
    -- a crafting profession's recipes: learned of all (counted when it was
    -- last open)
    c.recipes = skillBar(c, "Recipes")
    c.recipes:SetPoint("TOPLEFT", c.skill, "BOTTOMLEFT", 0, -S["space-3"])
    c.recipes:SetPoint("RIGHT", c, "RIGHT", -S["space-5"], 0)
    c.recipesHint = UI.Text(c, "caption", "ink-faint")
    c.recipesHint:SetPoint("LEFT", c.recipes, "LEFT", 0, 0)
    c.spells = {}
    c.empty = UI.Text(c, "caption", "ink-muted")
    c.empty:SetPoint("CENTER")
    c.hint = UI.Text(c, "caption", "ink-faint")
    c.hint:SetPoint("LEFT", c.skill, "LEFT", 0, 0)
    -- Unlearn: a quiet trash glyph in the bottom right corner of a learned
    -- one (always there: shown only on hover, it never showed in game);
    -- the game's own confirmation
    c.unlearn = CreateFrame("Button", nil, c)
    c.unlearn:SetSize(22, 22)
    c.unlearn:SetPoint("BOTTOMRIGHT", -S["space-4"], S["space-4"])
    c.unlearn.edge = UI.Border(c.unlearn, "gilt-line")
    c.unlearn.edge:SetShown(false)
    c.unlearn.glyph = c.unlearn:CreateTexture(nil, "ARTWORK")
    c.unlearn.glyph:SetTexture(GLYPHS .. "trash.tga")
    c.unlearn.glyph:SetSize(14, 14) -- even, like the button: whole pixels each side
    c.unlearn.glyph:SetPoint("CENTER")
    c.unlearn.glyph:SetVertexColor(UI.RGBA("ink-faint"))
    c.unlearn:SetFrameLevel(c:GetFrameLevel() + 5)
    c.unlearn:Hide()
    c.unlearn:SetScript("OnEnter", function(self)
        self.edge:SetShown(true)
        self.glyph:SetVertexColor(UI.RGBA("ember-text"))
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip_SetTitle(GameTooltip, "Unlearn " .. (c.card and c.card.name or ""))
        GameTooltip_AddNormalLine(GameTooltip, "Your skill and recipes in it are lost.")
        GameTooltip:Show()
    end)
    c.unlearn:SetScript("OnLeave", function(self)
        self.edge:SetShown(false)
        self.glyph:SetVertexColor(UI.RGBA("ink-faint"))
        GameTooltip:Hide()
    end)
    c.unlearn:SetScript("OnClick", function() if c.card and c.card.onUnlearn then c.card.onUnlearn() end end)
    c:SetScript("OnEnter", function(self)
        if self.card and self.card.crafting then self.border:SetColor("gilt-line") end
        if self.card and self.card.onDrag then self.icon:SetBorder("gilt") end
    end)
    c:SetScript("OnLeave", function(self)
        self.border:SetColor("gilt-faint")
        self.icon:SetBorder(nil)
    end)
    c:SetScript("OnClick", function(self) if self.card and self.card.crafting and view.onOpen then view.onOpen(self.card) end end)
    -- the card dragged: the profession's own spell (Enchanting) onto a bar
    c:RegisterForDrag("LeftButton")
    c:SetScript("OnDragStart", function(self) if self.card and self.card.onDrag then self.card.onDrag() end end)
    return c
end

-- a card's height: its head and bars, then its spells one under another
-- (side by side they ran into the Unlearn glyph: found in game), as many
-- rows as the profession with the most has
local SPELL_H = 22
local function cardHeight(rows)
    rows = math.max(1, rows or 1)
    return S["space-5"] * 2 + 30 + S["space-4"] + T.type.numeric.lineHeight * 2 + S["space-3"] + S["space-4"]
        + rows * SPELL_H + (rows - 1) * S["space-2"]
end

local function fillCard(c, card, empty)
    c.card = card
    local has = card ~= nil
    c.icon:SetShown(has); c.name:SetShown(has); c.rank:SetShown(has); c.skill:SetShown(has); c.open:SetShown(has and card.crafting)
    c.empty:SetShown(not has)
    if not has then
        c.empty:SetValue(empty or "Learn a profession from a trainer")
        c.hint:Hide()
        c.unlearn:Hide()
        c.recipes:Hide(); c.recipesHint:Hide()
        for _, s in ipairs(c.spells) do s:Hide() end
        return
    end
    c.icon:SetArt(card.icon)
    c.name:SetValue(card.name or "")
    c.rank:SetValue(card.rank or "")
    c.open:SetValue("Recipes")
    -- not learned: dimmed, how to learn it where the skill bar goes
    local off = card.untrained and true or false
    c.icon:SetState(off and "dim" or "rest")
    c.name:SetColor(off and "ink-muted" or "gilt-text")
    c.skill:SetShown(not off)
    c.hint:SetShown(off)
    c.hint:SetValue(card.hint or "")
    c.skill:SetSkill(card.skill, card.max)
    local counted = card.crafting and not off and card.recipes
    c.recipes:SetShown(counted and true or false)
    if counted then c.recipes:SetSkill(card.recipes.learned, card.recipes.total) end
    c.recipesHint:SetShown(card.crafting and not off and not counted or false)
    c.recipesHint:SetValue("Recipes: open it once to count them")
    c.unlearn:SetShown(card.onUnlearn ~= nil)
    local below = (card.crafting and not off) and c.recipes or c.skill
    local y = S["space-4"]
    for i, sp in ipairs(card.spells or {}) do
        local s = c.spells[i] or makeSpell(c)
        c.spells[i] = s
        s.spell = sp
        s.icon:SetArt(sp.icon)
        s.icon:SetBorder(sp.active and "arcane" or nil)
        s.icon:SetGlow(sp.active and "glow-arcane" or nil)
        s.label:SetValue(sp.name or "")
        s.label:SetColor(sp.active and "arcane" or (sp.onClick and "ink" or "ink-muted"))
        local w = 20 + S["space-3"] + math.ceil(s.label:GetUnboundedStringWidth()) + 2
        s:SetWidth(w)
        s:ClearAllPoints()
        s:SetPoint("TOPLEFT", below, "BOTTOMLEFT", 0, -y)
        s:Show()
        y = y + SPELL_H + S["space-2"]
    end
    for i = #(card.spells or {}) + 1, #c.spells do c.spells[i]:Hide() end
end

function P:SetOverview(d)
    d = d or {}
    self.mode = "overview"
    self.overview:Show()
    self.crafting:Hide()
    local w = self.overview:GetWidth()
    if not w or w <= 0 then w = UI.PROFESSIONS_W - 40 - RAIL_W - S["space-5"] end
    local rows = 1
    for _, list in ipairs({ d.primary or {}, d.secondary or {} }) do
        for _, card in pairs(list) do rows = math.max(rows, #(card.spells or {})) end
    end
    local cardH = cardHeight(rows)
    local gap = S["space-5"]
    local y = 0
    self.primaryHead:ClearAllPoints()
    self.primaryHead:SetPoint("TOPLEFT", self.overview, "TOPLEFT", 0, -y)
    self.primaryHead:SetValue("Primary professions")
    self.primaryCount:SetValue(#(d.primary or {}) .. " of 2")
    y = y + T.type.header.lineHeight + S["space-4"]
    local half = math.floor((w - gap) / 2)
    for i = 1, 2 do
        local c = self.cards[i] or makeCard(self)
        self.cards[i] = c
        c:ClearAllPoints()
        c:SetPoint("TOPLEFT", self.overview, "TOPLEFT", (i - 1) * (half + gap), -y)
        c:SetSize(half, cardH)
        fillCard(c, d.primary and d.primary[i])
        c:Show()
    end
    y = y + cardH + S["space-6"]
    self.secondaryHead:ClearAllPoints()
    self.secondaryHead:SetPoint("TOPLEFT", self.overview, "TOPLEFT", 0, -y)
    self.secondaryHead:SetValue("Secondary professions")
    y = y + T.type.header.lineHeight + S["space-4"]
    local sec = d.secondary or {}
    local n = math.max(1, #sec)
    local third = math.floor((w - gap * 2) / 3)
    for i = 1, math.max(n, 3) do
        local c = self.cards[2 + i] or makeCard(self)
        self.cards[2 + i] = c
        local col, row = (i - 1) % 3, math.floor((i - 1) / 3)
        c:ClearAllPoints()
        c:SetPoint("TOPLEFT", self.overview, "TOPLEFT", col * (third + gap), -(y + row * (cardH + gap)))
        c:SetSize(third, cardH)
        if sec[i] then
            fillCard(c, sec[i])
            c:Show()
        else
            c:Hide()
        end
    end
    for i = 2 + math.max(n, 3) + 1, #self.cards do self.cards[i]:Hide() end
end

--------------------------------------------------------------------------------
-- Crafting: the recipe list
--------------------------------------------------------------------------------

local function makeListRow(view)
    local r = CreateFrame("Button", nil, view.list.child)
    r:SetHeight(ROW_H)
    r.sel = UI.Fill(r, "arcane-soft", "BACKGROUND")
    r.sel:SetAllPoints()
    r.selEdge = UI.Fill(r, "arcane", "ARTWORK")
    r.selEdge:SetWidth(2)
    r.selEdge:SetPoint("TOPLEFT")
    r.selEdge:SetPoint("BOTTOMLEFT")
    r.hover = UI.Fill(r, "gilt-faint", "BACKGROUND", 1)
    r.hover:SetAllPoints()
    r.hover:Hide()
    r.chevron = r:CreateTexture(nil, "ARTWORK")
    r.chevron:SetSize(10, 10)
    r.chevron:SetPoint("LEFT", 2, 0)
    r.chevron:SetVertexColor(UI.RGBA("gilt-text"))
    r.eye = r:CreateTexture(nil, "ARTWORK")
    r.eye:SetTexture(GLYPHS .. "eye.tga")
    r.eye:SetSize(12, 12)
    r.eye:SetPoint("RIGHT", -S["space-3"], 0)
    r.eye:SetVertexColor(UI.RGBA("gilt-text"))
    r.count = UI.Text(r, "caption", "ink-muted")
    r.count:SetPoint("RIGHT", r.eye, "LEFT", -S["space-3"], 0)
    r.label = UI.Text(r, "label", "ink")
    r.label:SetPoint("LEFT", r, "LEFT", S["space-5"], 0)
    r.label:SetPoint("RIGHT", r.count, "LEFT", -S["space-3"], 0)
    r.label:SetJustifyH("LEFT")
    r:SetScript("OnEnter", function(self)
        self.hover:Show()
        if self.recipe and view.onRecipeEnter then view.onRecipeEnter(self.recipe, self) end
    end)
    r:SetScript("OnLeave", function(self) self.hover:Hide(); GameTooltip:Hide() end)
    r:SetScript("OnClick", function(self)
        if self.category then
            view.folded[self.category] = not view.folded[self.category]
            view:DrawList()
        elseif self.recipe and view.onSelect then
            view.onSelect(self.recipe.id)
        end
    end)
    return r
end

function P:DrawList()
    local d = self.craftData
    if not d then return end
    local child = self.list.child
    child:SetWidth(math.max(1, self.list:GetWidth()))
    local y, n = 0, 0
    local function row()
        n = n + 1
        local r = self.listRows[n] or makeListRow(self)
        self.listRows[n] = r
        r:ClearAllPoints()
        r:SetPoint("TOPLEFT", child, "TOPLEFT", 0, -y)
        r:SetPoint("RIGHT", child, "RIGHT", -S["space-4"], 0)
        r:Show()
        y = y + ROW_H
        return r
    end
    for _, cat in ipairs(d.categories or {}) do
        local r = row()
        local folded = self.folded[cat.name]
        r.category, r.recipe = cat.name, nil
        r.chevron:SetTexture(GLYPHS .. (folded and "chevronRight" or "chevronDown") .. ".tga")
        r.chevron:Show()
        r.eye:Hide()
        r.sel:Hide(); r.selEdge:Hide()
        r.label:SetStyle("header")
        r.label:SetColor("gilt-text")
        r.label:SetValue(cat.name or "")
        r.count:SetValue(tostring(#(cat.recipes or {})))
        if not folded then
            for _, rec in ipairs(cat.recipes or {}) do
                local rr = row()
                rr.category, rr.recipe = nil, rec
                rr.chevron:Hide()
                rr.label:SetStyle("label")
                rr.label:SetColor(rec.learned == false and "ink-faint" or (DIFFICULTY[rec.difficulty or 3] or "quest-trivial"))
                rr.label:SetValue(rec.name or "")
                rr.count:SetValue((rec.canMake or 0) > 0 and ("[" .. rec.canMake .. "]") or "")
                rr.eye:SetShown(rec.tracked and true or false)
                local on = rec.id == d.selected
                rr.sel:SetShown(on); rr.selEdge:SetShown(on)
            end
        end
        y = y + S["space-2"]
    end
    for i = n + 1, #self.listRows do self.listRows[i]:Hide() end
    self.listEmpty:SetShown(n == 0)
    child:SetHeight(math.max(1, y))
end

--------------------------------------------------------------------------------
-- Crafting: the chosen recipe
--------------------------------------------------------------------------------

local function makeReagent(view)
    local r = CreateFrame("Frame", nil, view.recipe)
    r:SetHeight(32)
    r.slot = UI.ItemSlot(r, 30)
    r.slot:SetPoint("LEFT")
    r.slot:SetScript("OnEnter", function(self) if view.recipeData and view.recipeData.onReagent then view.recipeData.onReagent(self.index, self) end end)
    r.slot:SetScript("OnLeave", function() GameTooltip:Hide() end)
    r.count = UI.Text(r, "numeric", "ink")
    r.count:SetPoint("RIGHT")
    r.name = UI.Text(r, "label", "ink")
    r.name:SetPoint("LEFT", r.slot, "RIGHT", S["space-4"], 0)
    r.name:SetPoint("RIGHT", r.count, "LEFT", -S["space-4"], 0)
    r.name:SetJustifyH("LEFT")
    return r
end

function P:SetRecipe(r)
    self.recipeData = r
    local v = self.recipe
    v.none:SetShown(r == nil)
    for _, part in ipairs({ v.product, v.title, v.makes, v.desc, v.reagentHead, v.foot }) do part:SetShown(r ~= nil) end
    if not r then
        for _, x in ipairs(v.tools) do x:Hide() end
        for _, x in ipairs(v.reagents) do x:Hide() end
        v.cooldown:Hide()
        v.source:Hide()
        v.sourceHead:Hide()
        v.sourceItem:Hide()
        v.why:Hide()
        return
    end
    v.product.skin:SetItem({ icon = r.icon, quality = r.qualityName })
    v.title:SetValue(r.name or "")
    v.title:SetColor(QUALITY[r.quality or 1] or "ink")
    v.makes:SetValue((r.makes and r.makes > 1) and ("Makes " .. r.makes) or "")
    v.desc:SetValue(r.desc or "")
    local y = 36 + S["space-4"]
    local dh = (r.desc and r.desc ~= "") and v.desc:GetStringHeight() or 0
    y = math.max(y, T.type["unit-name-lg"].lineHeight + T.type.caption.lineHeight + dh + S["space-4"])
    -- what it needs
    for i, t in ipairs(r.tools or {}) do
        local line = v.tools[i]
        if not line then
            line = CreateFrame("Frame", nil, v)
            line:SetHeight(T.type.caption.lineHeight + 2)
            line.glyph = line:CreateTexture(nil, "ARTWORK")
            line.glyph:SetSize(11, 11)
            line.glyph:SetPoint("LEFT")
            line.text = UI.Text(line, "caption", "ink-muted")
            line.text:SetPoint("LEFT", line.glyph, "RIGHT", S["space-3"], 0)
            v.tools[i] = line
        end
        line:ClearAllPoints()
        line:SetPoint("TOPLEFT", v, "TOPLEFT", 0, -y)
        line:SetPoint("RIGHT", v, "RIGHT")
        line.glyph:SetTexture(GLYPHS .. (t.met and "check" or "close") .. ".tga")
        line.glyph:SetVertexColor(UI.RGBA(t.met and "fel" or "ember-text"))
        line.text:SetValue("Requires " .. (t.name or ""))
        line.text:SetColor(t.met and "ink-muted" or "ember-text")
        line:Show()
        y = y + T.type.caption.lineHeight + 2
    end
    for i = #(r.tools or {}) + 1, #v.tools do v.tools[i]:Hide() end
    -- where a recipe not learned yet is learned: its recipe item (hover
    -- for its tooltip) and where that is, or a trainer
    local src = r.source
    v.sourceHead:SetShown(src ~= nil)
    v.sourceItem:SetShown(src ~= nil and src.item ~= nil)
    v.source:SetShown(src ~= nil and src.lines ~= nil and #src.lines > 0)
    if src then
        y = y + S["space-5"]
        v.sourceHead:ClearAllPoints()
        v.sourceHead:SetPoint("TOPLEFT", v, "TOPLEFT", 0, -y)
        y = y + T.type.header.lineHeight + S["space-3"]
        local item = src.item
        if item then
            local row = v.sourceItem
            row:ClearAllPoints()
            row:SetPoint("TOPLEFT", v, "TOPLEFT", 0, -y)
            row:SetPoint("RIGHT", v, "RIGHT")
            row.slot.skin:SetItem({ icon = item.icon, quality = item.qualityName })
            row.name:SetValue(item.name or "…")
            row.name:SetColor(QUALITY[item.quality or 1] or "ink")
            row.count:SetValue(item.note or "")
            row.count:SetColor("fel")
            y = y + 32 + S["space-2"]
        end
        if src.lines and #src.lines > 0 then
            v.source:ClearAllPoints()
            v.source:SetPoint("TOPLEFT", v, "TOPLEFT", 0, -y)
            v.source:SetWidth(math.max(100, v:GetWidth()))
            v.source:SetValue(table.concat(src.lines, "\n"))
            y = y + v.source:GetStringHeight()
        end
    end
    y = y + S["space-5"]
    v.reagentHead:ClearAllPoints()
    v.reagentHead:SetPoint("TOPLEFT", v, "TOPLEFT", 0, -y)
    y = y + T.type.header.lineHeight + S["space-4"]
    for i, g in ipairs(r.reagents or {}) do
        local row = v.reagents[i] or makeReagent(self)
        v.reagents[i] = row
        row.slot.index = i
        row:ClearAllPoints()
        row:SetPoint("TOPLEFT", v, "TOPLEFT", 0, -y)
        row:SetPoint("RIGHT", v, "RIGHT")
        local short = (g.have or 0) < (g.need or 0)
        row.slot.skin:SetItem({ icon = g.icon, quality = g.qualityName, dim = short })
        row.name:SetValue(g.name or "…")
        row.name:SetColor(short and "ink-muted" or (QUALITY[g.quality or 1] or "ink"))
        row.count:SetValue((g.have or 0) .. " / " .. (g.need or 0))
        row.count:SetColor(short and "ember-text" or "ink")
        row:Show()
        y = y + 32 + S["space-2"]
    end
    for i = #(r.reagents or {}) + 1, #v.reagents do v.reagents[i]:Hide() end
    v.cooldown:SetShown(r.cooldown ~= nil)
    if r.cooldown then
        v.cooldown:ClearAllPoints()
        v.cooldown:SetPoint("TOPLEFT", v, "TOPLEFT", 0, -(y + S["space-3"]))
        v.cooldown:SetValue("Cooldown " .. r.cooldown)
    end
    v.track:SetValue(r.tracked and true or false)
    local ready = r.ready and true or false
    v.create:SetEnabledState(ready)
    v.createAll:SetEnabledState(ready and (r.canMake or 0) > 1)
    v.createAll:SetLabel("Create all" .. ((r.canMake or 0) > 1 and (" (" .. r.canMake .. ")") or ""))
    v.qty.max = math.max(1, r.canMake or 1)
    if (v.qty.value or 1) > v.qty.max then v.qty:SetValue(v.qty.max) end
    v.qty:SetDisabled(not ready)
    v.why:SetShown(not ready and r.why ~= nil)
    v.why:SetValue(r.why or "")
end

-- Learned only and Unlearned only shut each other out: the one just picked
-- stays.
function P:FiltersChanged(list)
    local had, has = {}, {}
    for _, k in ipairs(self.filterList or {}) do had[k] = true end
    for _, k in ipairs(list or {}) do has[k] = true end
    if has.learned and has.unlearned then
        local drop = had.learned and "learned" or "unlearned"
        local kept = {}
        for _, k in ipairs(list) do if k ~= drop then kept[#kept + 1] = k end end
        list = kept
        self.filters:SetValue(list)
    end
    self.filterList = list
    if self.onFilters then self.onFilters(list) end
end

function P:SetCrafting(d)
    d = d or {}
    self.mode = "crafting"
    self.craftData = d
    self.overview:Hide()
    self.crafting:Show()
    self.craftName:SetValue(d.name or "")
    self.craftRank:SetValue(d.rank or "")
    self.craftSkill:SetSkill(d.skill, d.max)
    self.craftRecipes:SetShown(d.recipes ~= nil)
    if d.recipes then self.craftRecipes:SetSkill(d.recipes.learned, d.recipes.total) end
    -- the two bars share what the name and rank leave
    local gap = S["space-5"]
    local room = (self.crafting:GetWidth() or 0) - self.craftName:GetUnboundedStringWidth()
        - self.craftRank:GetUnboundedStringWidth() - gap * 3
    local bar = d.recipes and math.floor((room - gap) / 2) or room
    self.craftSkill:SetWidth(math.max(80, bar))
    self.craftRecipes:SetWidth(math.max(80, bar))
    self:DrawList()
end

--------------------------------------------------------------------------------
-- The whole
--------------------------------------------------------------------------------

function UI.Professions(parent, opts)
    local f = CreateFrame("Frame", nil, parent)
    Mixin(f, P)
    f.edgeInset = opts and opts.edgeInset or 20
    f.tabs, f.cards, f.listRows, f.folded = {}, {}, {}, {}
    -- the rail
    f.rail = CreateFrame("Frame", nil, f)
    f.rail:SetPoint("TOPRIGHT")
    f.rail:SetPoint("BOTTOMRIGHT")
    f.rail:SetWidth(RAIL_W)
    local divider = UI.Fill(f, "gilt-faint", "ARTWORK")
    divider:SetWidth(1)
    divider:SetPoint("TOPRIGHT", f.rail, "TOPLEFT", 0, 0)
    divider:SetPoint("BOTTOMRIGHT", f.rail, "BOTTOMLEFT", 0, 0)
    f.main = CreateFrame("Frame", nil, f)
    f.main:SetPoint("TOPLEFT")
    f.main:SetPoint("BOTTOMRIGHT", f.rail, "BOTTOMLEFT", -S["space-5"], 0)
    -- the overview
    f.overview = CreateFrame("Frame", nil, f.main)
    f.overview:SetAllPoints()
    f.primaryHead = UI.Text(f.overview, "header", "gilt-text")
    f.primaryCount = UI.Text(f.overview, "caption", "ink-muted")
    f.primaryCount:SetPoint("LEFT", f.primaryHead, "RIGHT", S["space-4"], 0)
    f.secondaryHead = UI.Text(f.overview, "header", "gilt-text")
    -- crafting
    f.crafting = CreateFrame("Frame", nil, f.main)
    f.crafting:SetAllPoints()
    f.crafting:Hide()
    f.craftRank = UI.Text(f.crafting, "caption", "ink-muted")
    f.craftRank:SetPoint("TOPRIGHT", 0, 0)
    f.craftName = UI.Text(f.crafting, "header", "gilt-text")
    f.craftName:SetPoint("TOPLEFT", 0, 0)
    f.craftSkill = skillBar(f.crafting, "Skill")
    f.craftSkill:SetPoint("LEFT", f.craftName, "RIGHT", S["space-5"], 0)
    f.craftRecipes = skillBar(f.crafting, "Recipes")
    f.craftRecipes:SetPoint("LEFT", f.craftSkill, "RIGHT", S["space-5"] * 2, 0)
    -- the list: search and filters, then the recipes
    f.search = UI.TextField(f.crafting, { width = LIST_W - 96 - S["space-3"], placeholder = "Search recipes",
        onTextChanged = function(text) if f.onSearch then f.onSearch(text) end end })
    f.search:SetPoint("TOPLEFT", f.crafting, "TOPLEFT", 0, -(T.type.header.lineHeight + S["space-5"]))
    f.filters = UI.Select(f.crafting, { multiple = true, width = 96, placeholder = "Filters", maxShown = 0,
        options = { { value = "learned", label = "Learned only" }, { value = "unlearned", label = "Unlearned only" },
            { value = "materials", label = "Have materials" }, { value = "skillup", label = "Skill up" } },
        value = { "learned" }, onChange = function(v) f:FiltersChanged(v) end })
    f.filterList = { "learned" }
    f.filters:SetPoint("LEFT", f.search, "RIGHT", S["space-3"], 0)
    f.listBox = CreateFrame("Frame", nil, f.crafting)
    f.listBox:SetPoint("TOPLEFT", f.search, "BOTTOMLEFT", 0, -S["space-4"])
    f.listBox:SetPoint("BOTTOM", f.crafting, "BOTTOM", 0, 0)
    f.listBox:SetWidth(LIST_W)
    UI.Fill(f.listBox, "surface-sunk"):SetAllPoints()
    UI.Border(f.listBox, "gilt-faint")
    f.list = UI.ScrollArea(f.listBox, 2)
    f.list:SetPoint("TOPLEFT", S["space-2"], -S["space-3"])
    f.list:SetPoint("BOTTOMRIGHT", -S["space-4"], S["space-3"])
    f.listEmpty = UI.Text(f.listBox, "caption", "ink-muted")
    f.listEmpty:SetPoint("CENTER")
    f.listEmpty:SetValue("No recipes match")
    f.listEmpty:Hide()
    -- the recipe
    local v = CreateFrame("Frame", nil, f.crafting)
    f.recipe = v
    v:SetPoint("TOPLEFT", f.listBox, "TOPRIGHT", S["space-6"], 0)
    v:SetPoint("BOTTOMRIGHT", f.crafting, "BOTTOMRIGHT", 0, 0)
    v.none = UI.Text(v, "caption", "ink-muted")
    v.none:SetPoint("CENTER")
    v.none:SetValue("Choose a recipe")
    v.product = UI.ItemSlot(v, 36)
    v.product:SetPoint("TOPLEFT")
    v.product:SetScript("OnEnter", function(self) if f.recipeData and f.recipeData.onProduct then f.recipeData.onProduct(self) end end)
    v.product:SetScript("OnLeave", function() GameTooltip:Hide() end)
    v.title = UI.Text(v, "unit-name-lg", "ink")
    v.title:SetPoint("TOPLEFT", v.product, "TOPRIGHT", S["space-5"], 0)
    v.title:SetPoint("RIGHT", v, "RIGHT")
    v.title:SetJustifyH("LEFT")
    v.makes = UI.Text(v, "caption", "ink-muted")
    v.makes:SetPoint("TOPLEFT", v.title, "BOTTOMLEFT", 0, -1)
    v.desc = UI.Text(v, "caption", "ink-muted")
    v.desc:SetPoint("TOPLEFT", v.makes, "BOTTOMLEFT", 0, -1)
    v.desc:SetPoint("RIGHT", v, "RIGHT")
    v.desc:SetJustifyH("LEFT")
    v.desc:SetWordWrap(true)
    v.tools, v.reagents = {}, {}
    v.reagentHead = UI.Text(v, "header", "gilt-text")
    v.reagentHead:SetValue("Reagents")
    v.cooldown = UI.Text(v, "caption", "amber")
    v.source = UI.Text(v, "caption", "ink-muted")
    v.source:SetJustifyH("LEFT")
    v.source:SetWordWrap(true)
    v.source:SetSpacing(2)
    v.sourceHead = UI.Text(v, "header", "gilt-text")
    v.sourceHead:SetValue("Source")
    v.sourceItem = makeReagent(f)
    v.sourceItem.slot:SetScript("OnEnter", function(self)
        local src = f.recipeData and f.recipeData.source
        if src and src.item and src.item.onEnter then src.item.onEnter(self) end
    end)
    v.sourceItem:Hide()
    -- the foot: Track, quantity, Create all, Create
    v.foot = CreateFrame("Frame", nil, v)
    v.foot:SetPoint("BOTTOMLEFT")
    v.foot:SetPoint("BOTTOMRIGHT")
    v.foot:SetHeight(30)
    v.create = UI.Button(v.foot, { text = "Create", variant = "primary",
        onClick = function() if f.onCreate then f.onCreate(v.qty.value or 1) end end })
    v.create:SetPoint("BOTTOMRIGHT")
    v.createAll = UI.Button(v.foot, { text = "Create all", variant = "quiet",
        onClick = function() if f.onCreateAll then f.onCreateAll() end end })
    v.createAll:SetPoint("RIGHT", v.create, "LEFT", -S["space-3"], 0)
    v.qty = UI.Stepper(v.foot, { min = 1, max = 1, value = 1 })
    v.qty:SetPoint("RIGHT", v.createAll, "LEFT", -S["space-3"], 0)
    v.track = UI.Checkbox(v.foot, { label = "Track", onChange = function(on) if f.onTrack then f.onTrack(on) end end })
    v.track:SetPoint("LEFT", v.foot, "LEFT", 0, 0)
    v.why = UI.Text(v, "caption", "ember-text")
    v.why:SetPoint("BOTTOMRIGHT", v.foot, "TOPRIGHT", 0, S["space-3"])
    f:SetRecipe(nil)
    return f
end
