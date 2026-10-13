-- UI/LevelUp.lua
-- The level-up card (design board "Level up · new spells"): the alert's
-- family, taller. A title in the display face ("Level 20") over a muted
-- caption, a faint rule, the new spells (an icon with the name beside it and
-- the rank under the name; a spell you never had says New in arcane), an
-- optional "+ 3 more" line, another rule and what training all of it costs.
-- Glass ground, gilt rules above and below, a gilt diamond on each end level
-- with the title.
--
--   local c = UI.LevelUp(parent)
--   c:SetLevelUp({ title, detail, spells = { { icon, name, rank, isNew, note } },
--                  more, cost (copper) })
--
-- note: a few words after the rank in ink-faint ("Level 18": a spell from an
-- earlier level still to train). Hovering a spell shows the game's spell
-- tooltip when it carries `spellID` (then `meta` as a last line: what
-- training it costs), else SuuUI's: its name, rank, `text` and `meta`. The card takes
-- the mouse: c:IsHovered() says whether it is under it (it stays then); a
-- click on it calls c.onClick (its owner dismisses it).
--
-- One column for up to four spells, two from five; at most ten rows (the
-- caller says how many more in `more`).

local _, ns = ...

local UI, T = ns.UI, ns.Tokens
local S = T.space

local MAX = 10
local ICON = "icon-lg"
local COL_GAP = 24
local ROW_GAP = S["space-4"]
local PAD_X, PAD_TOP, PAD_BOTTOM = 28, 10, 12
local JEWEL = 9

local function hex(token) return T.color[token].hex end

local function coins(copper)
    copper = math.max(0, math.floor(tonumber(copper) or 0))
    local g, s, c = math.floor(copper / 10000), math.floor(copper / 100) % 100, copper % 100
    local parts = {}
    local function part(v, unit, token)
        parts[#parts + 1] = "|cff" .. hex(token) .. v .. unit .. "|r"
    end
    if g > 0 then part(g, "g", "coin-gold") end
    if s > 0 then part(s, "s", "coin-silver") end
    if c > 0 or #parts == 0 then part(c, "c", "coin-copper") end
    return table.concat(parts, " ")
end

-- "Rank 3", "Rank 1 · New", "New" or "Rank 2 · Level 18"
local function rankLine(s)
    local parts = {}
    if s.rank then parts[#parts + 1] = "|cff" .. hex("ink-muted") .. "Rank " .. s.rank .. "|r" end
    if s.isNew then parts[#parts + 1] = "|cff" .. hex("arcane") .. "New|r" end
    if s.note then parts[#parts + 1] = "|cff" .. hex("ink-faint") .. s.note .. "|r" end
    return table.concat(parts, "|cff" .. hex("ink-faint") .. " · |r")
end

local Card = {}

function Card:Row(i)
    local r = self.rows[i]
    if r then return r end
    r = CreateFrame("Frame", nil, self)
    r.icon = UI.Icon(r, ICON)
    r.icon:SetPoint("LEFT")
    r.name = UI.Text(r, "label", "ink")
    r.name:SetPoint("TOPLEFT", r.icon, "TOPRIGHT", S["space-4"], 0)
    r.rank = UI.Text(r, "caption", "ink-muted")
    r.rank:SetPoint("TOPLEFT", r.name, "BOTTOMLEFT", 0, 0)
    r:EnableMouse(true)
    r:SetScript("OnEnter", function()
        local s = r.spell
        if not s then return end
        if s.spellID then
            UI.SpellTooltip(r, s.spellID, s.meta)
            return
        end
        UI.ShowTooltip(r, { title = s.name, subtitle = s.rank and ("Rank " .. s.rank) or nil, description = s.text, meta = s.meta })
    end)
    r:SetScript("OnLeave", function() GameTooltip:Hide(); UI.HideTooltip() end)
    r:SetScript("OnMouseUp", function() if self.onClick then self.onClick() end end)
    self.rows[i] = r
    return r
end

-- Under the mouse: the card or one of its spells is what the mouse is on.
-- Not its rectangle (IsMouseOver): turning the camera with a mouse button
-- held hides the cursor where it was, over the card, and it never "left"
-- (found in game: the card stayed).
function Card:IsHovered()
    if not self:IsVisible() or (IsMouselooking and IsMouselooking()) then return false end
    local foci = GetMouseFoci and GetMouseFoci() or { GetMouseFocus and GetMouseFocus() }
    for _, f in ipairs(foci) do
        if f == self or (f and f.GetParent and f:GetParent() == self) then return true end
    end
    return false
end

function Card:SetLevelUp(d)
    d = d or {}
    local spells = d.spells or {}
    local n = math.min(#spells, MAX)
    local cols = n > 4 and 2 or 1
    self.title:SetValue(d.title or "")
    self.detail:SetValue(d.detail or "")
    local iconPx = UI.Size(ICON)
    -- each column as wide as its widest row
    local colW = { 0, 0 }
    for i = 1, n do
        local s = spells[i]
        local r = self:Row(i)
        r.spell = s
        r.icon:SetArt(s.icon or 134400)
        r.name:SetValue(s.name or "")
        r.rank:SetText(rankLine(s))
        local w = iconPx + S["space-4"] + math.max(UI.MeasureText("label", s.name or ""), UI.MeasureText("caption", r.rank:GetText() or ""))
        local c = (i - 1) % cols + 1
        colW[c] = math.max(colW[c], math.ceil(w) + 2)
    end
    for i = n + 1, #self.rows do self.rows[i]:Hide() end
    local gridW = colW[1] + (cols > 1 and (COL_GAP + colW[2]) or 0)
    local lines = math.ceil(n / cols)
    local gridH = lines > 0 and (lines * iconPx + (lines - 1) * ROW_GAP) or 0
    self.more:SetValue(d.more or "")
    self.more:SetVisible(d.more and d.more ~= "" and true or false)
    self.cost:SetText(coins(d.cost))
    local foot = UI.MeasureText("caption", self.label:GetText() or "") + UI.MeasureText("numeric", self.cost:GetText() or "")
    self.foot:SetSize(math.ceil(foot) + 2, T.type.caption.lineHeight)
    local inner = math.max(UI.MeasureText("alert", d.title or ""), UI.MeasureText("caption", d.detail or ""), gridW,
        self.more:IsShown() and UI.MeasureText("caption", d.more) or 0, foot)
    local width = math.max(UI.Size("notice-w"), math.ceil(inner) + PAD_X * 2)
    -- the rows, centred under the title
    local left = math.floor((width - gridW) / 2)
    for i = 1, n do
        local r = self.rows[i]
        local c, line = (i - 1) % cols, math.floor((i - 1) / cols)
        r:ClearAllPoints()
        r:SetPoint("TOPLEFT", self, "TOPLEFT", left + (c == 1 and (colW[1] + COL_GAP) or 0), -(self.gridTop + line * (iconPx + ROW_GAP)))
        r:SetSize(colW[c + 1], iconPx)
        r:Show()
    end
    -- below the grid: the more line, the rule, the cost
    local y = self.gridTop + gridH + S["space-4"]
    if self.more:IsShown() then
        self.more:ClearAllPoints()
        self.more:SetPoint("TOP", self, "TOP", 0, -y)
        y = y + T.type.caption.lineHeight + S["space-4"]
    end
    self.rule2:ClearAllPoints()
    self.rule2:SetPoint("TOPLEFT", PAD_X, -y)
    self.rule2:SetPoint("TOPRIGHT", -PAD_X, -y)
    y = y + 1 + S["space-4"]
    self.foot:ClearAllPoints()
    self.foot:SetPoint("TOP", self, "TOP", 0, -y)
    y = y + T.type.caption.lineHeight + PAD_BOTTOM
    self:SetSize(width, y)
end

function UI.LevelUp(parent)
    local f = CreateFrame("Frame", nil, parent)
    Mixin(f, Card)
    f.rows = {}
    f:EnableMouse(true)
    f:SetScript("OnHide", function()
        UI.HideTooltip()
        local owner = GameTooltip:GetOwner()
        if owner and owner.GetParent and owner:GetParent() == f then GameTooltip:Hide() end
    end)
    f:SetScript("OnMouseUp", function() if f.onClick then f.onClick() end end)
    f.ground = f:CreateTexture(nil, "BACKGROUND")
    f.ground:SetAllPoints()
    f.ground:SetColorTexture(UI.RGBA("surface-glass"))
    f.rules = UI.Border(f, "gilt-line")
    f.rules.left:Hide()
    f.rules.right:Hide()
    local titleMid = PAD_TOP + T.type.alert.lineHeight / 2
    f.left = UI.Diamond(f, JEWEL, "gilt")
    f.left:SetPoint("CENTER", f, "TOPLEFT", 0, -titleMid)
    f.right = UI.Diamond(f, JEWEL, "gilt")
    f.right:SetPoint("CENTER", f, "TOPRIGHT", 0, -titleMid)
    f.title = UI.Text(f, "alert", "gilt-text")
    -- the display face sits 2px low in its line box (as on the alert)
    f.title:SetPoint("TOP", 0, -PAD_TOP - 2)
    f.detail = UI.Text(f, "caption", "ink-muted")
    local detailTop = PAD_TOP + T.type.alert.lineHeight + S["space-4"] - 6
    f.detail:SetPoint("TOP", 0, -detailTop)
    local ruleTop = detailTop + T.type.caption.lineHeight + S["space-4"]
    f.rule1 = UI.Fill(f, "gilt-faint", "ARTWORK")
    f.rule1:SetHeight(1)
    f.rule1:SetPoint("TOPLEFT", PAD_X, -ruleTop)
    f.rule1:SetPoint("TOPRIGHT", -PAD_X, -ruleTop)
    f.gridTop = ruleTop + 1 + S["space-4"]
    f.more = UI.Text(f, "caption", "ink-muted")
    f.rule2 = UI.Fill(f, "gilt-faint", "ARTWORK")
    f.rule2:SetHeight(1)
    f.foot = CreateFrame("Frame", nil, f)
    f.label = UI.Text(f.foot, "caption", "ink-muted")
    f.label:SetPoint("LEFT")
    f.label:SetText("Train all at your class trainer · ")
    f.cost = UI.Text(f.foot, "numeric", "ink")
    f.cost:SetPoint("LEFT", f.label, "RIGHT", 0, 0)
    f:SetLevelUp({ title = "" })
    return f
end
