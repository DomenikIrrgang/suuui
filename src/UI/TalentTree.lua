-- UI/TalentTree.lua
-- The Talents page (design boards "Talents" and "Talent nodes"): the class's
-- trees side by side, each a panel on surface-sunk with its name and points,
-- the talents on a 4-column grid (32px icons, a rank badge at the bottom
-- right) with prerequisite arrows; above, the spec's name and the points per
-- tree; below, the points to spend, what is planned, Undo and Apply.
--
--   local tt = UI.TalentTree(parent)
--   tt:SetSpecs(list, viewing)  -- { { label, name, active, locked } } or nil
--                               -- (one spec: no row); viewing: an index
--   tt:SetData({ name, available, pending, editable, hint, rows (7),
--       trees = { { name, points, more, nodes = { node }, links = { link } } } })
--     more: a line under the tree ("2 more talents in a future update")
--   tt.noSummary = true   -- no summary line (a page with its own head)
--   tt.fillPanels = true  -- the trees' panels down to the foot (a taller page)
--     node = { row, col, rank, pending, max, icon, locked, canSpend, ... }
--     link = { from = node, to = node, met }
--   tt.onClick(node) / onRemove(node) / onEnter(button, node) / onLeave()
--   tt.onApply() / onUndo() / onSpec(i) / onActivate()
--
-- A node: full or partly learned in ink; one that can take a point in arcane
-- with a glow; planned points (not applied yet) with an arcane badge; locked
-- dim on a faint edge.

local _, ns = ...

local UI, T = ns.UI, ns.Tokens
local S = T.space

local CW, RH, OX, NS = 44, 46, 20, 32   -- column and row step, left inset, node size
local ROWS = 7
local GRAPH_W = 200
local function graphH(rows) return rows * RH - (RH - NS) end
local GRAPH_H = graphH(ROWS)
local PAD = S["space-4"]
local GAP = S["space-6"]
local HEAD_H = 16
local FOOT_H = 38
local GLYPHS = "Interface\\AddOns\\SuuUI\\Media\\Textures\\Glyphs\\"

-- The width the page needs: three panels and their gaps.
local PANEL_W = GRAPH_W + PAD * 2
UI.TALENT_TREE_W = PANEL_W * 3 + GAP * 2

local function hex(token) return T.color[token].hex end

local TT = {}

--------------------------------------------------------------------------------
-- A node
--------------------------------------------------------------------------------

local function drawNode(b)
    local d = b.data
    if not d then return end
    local total = (d.rank or 0) + (d.pending or 0)
    local full = total >= (d.max or 1)
    local some = total > 0
    local canSpend = d.canSpend and not full and not d.locked
    local border
    if (d.pending or 0) > 0 then border = "arcane"
    elseif canSpend then border = "arcane"
    elseif d.locked then border = "gilt-faint"
    elseif some then border = "ink"
    else border = "gilt-hairline" end
    if b.hover and not d.locked then border = "gilt" end
    b.icon:SetState((d.locked or not some) and "dim" or "rest")
    b.icon:SetBorder(border)
    b.icon:SetGlow(canSpend and "glow-arcane" or nil)
    local badge = b.badge
    badge.text:SetValue(total .. "/" .. (d.max or 1))
    badge:SetWidth(math.ceil(badge.text:GetUnboundedStringWidth()) + 6)
    if (d.pending or 0) > 0 then
        badge.bg:SetColorTexture(UI.RGBA("arcane"))
        badge.edge:SetColor("arcane")
        badge.text:SetColor("on-signal")
    else
        badge.bg:SetColorTexture(UI.RGBA("surface"))
        badge.edge:SetColor(canSpend and "arcane" or "gilt-line")
        badge.text:SetColor(canSpend and "arcane" or (some and "ink" or "ink-muted"))
    end
end

local function makeNode(tt, graph)
    local b = CreateFrame("Button", nil, graph)
    b:SetSize(NS, NS)
    b:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    b.icon = UI.Icon(b, NS)
    b.icon:SetAllPoints()
    b.badge = CreateFrame("Frame", nil, b)
    b.badge:SetFrameLevel(b:GetFrameLevel() + 3)
    b.badge:SetHeight(12)
    b.badge:SetPoint("BOTTOMRIGHT", b, "BOTTOMRIGHT", 6, -6)
    b.badge.bg = b.badge:CreateTexture(nil, "BACKGROUND")
    b.badge.bg:SetAllPoints()
    b.badge.edge = UI.Border(b.badge, "gilt-line")
    b.badge.text = UI.Text(b.badge, "micro", "ink-muted")
    b.badge.text:SetPoint("CENTER", 0, 0)
    b:SetScript("OnClick", function(self, button)
        if not self.data then return end
        if button == "RightButton" then
            if tt.onRemove then tt.onRemove(self.data) end
        elseif tt.onClick then
            tt.onClick(self.data)
        end
    end)
    b:SetScript("OnEnter", function(self)
        self.hover = true
        drawNode(self)
        if tt.onEnter and self.data then tt.onEnter(self, self.data) end
    end)
    b:SetScript("OnLeave", function(self)
        self.hover = false
        drawNode(self)
        if tt.onLeave then tt.onLeave() end
    end)
    return b
end

--------------------------------------------------------------------------------
-- A tree panel
--------------------------------------------------------------------------------

local function makePanel(tt)
    local p = CreateFrame("Frame", nil, tt.treesRow)
    UI.Fill(p, "surface-sunk"):SetAllPoints()
    UI.Border(p, "gilt-faint")
    p.name = UI.Text(p, "header", "gilt-text")
    p.name:SetPoint("TOPLEFT", PAD, -PAD)
    p.points = UI.Text(p, "numeric", "ink")
    p.points:SetPoint("TOPRIGHT", -PAD, -PAD)
    p.graph = CreateFrame("Frame", nil, p)
    p.graph:SetSize(GRAPH_W, GRAPH_H)
    p.graph:SetPoint("TOP", p, "TOP", 0, -(PAD + HEAD_H + PAD))
    p.more = UI.Text(p, "caption", "ink-muted")
    p.more:SetPoint("BOTTOM", p, "BOTTOM", 0, PAD)
    p.nodes, p.lines, p.heads = {}, {}, {}
    return p
end

-- A prerequisite arrow from one node to another (down, or sideways in a row).
local function drawLink(p, i, l)
    local line = p.lines[i]
    if not line then
        line = p.graph:CreateLine(nil, "ARTWORK")
        line:SetThickness(2)
        p.lines[i] = line
        local head = p.graph:CreateTexture(nil, "ARTWORK", nil, 1)
        head:SetSize(8, 8)
        p.heads[i] = head
    end
    local head = p.heads[i]
    local a, b = l.from, l.to
    local x1, y1, x2, y2
    local glyph
    if a.row == b.row then
        local right = b.col > a.col
        x1 = a.col * CW + OX + (right and NS or 0)
        x2 = b.col * CW + OX + (right and -1 or NS + 1)
        y1, y2 = a.row * RH + NS / 2, a.row * RH + NS / 2
        glyph = right and "chevronRight" or "chevronLeft"
    else
        x1 = a.col * CW + OX + NS / 2
        x2 = b.col * CW + OX + NS / 2
        y1 = a.row * RH + NS
        y2 = b.row * RH - 1
        glyph = "chevronDown"
    end
    local token = l.met and "ink-muted" or "gilt-line"
    line:SetColorTexture(UI.RGBA(token))
    line:SetStartPoint("TOPLEFT", p.graph, x1, -y1)
    line:SetEndPoint("TOPLEFT", p.graph, x2, -y2)
    line:Show()
    head:SetTexture(GLYPHS .. glyph .. ".tga")
    head:SetVertexColor(UI.RGBA(token))
    head:ClearAllPoints()
    head:SetPoint("CENTER", p.graph, "TOPLEFT", x2, -y2 + (glyph == "chevronDown" and 3 or 0))
    head:Show()
end

local function fillPanel(tt, p, t)
    p.more:SetValue(t.more or "")
    p.more:SetShown(t.more ~= nil)
    p.name:SetValue(t.name or "")
    p.points:SetValue(tostring(t.points or 0))
    local nodes = t.nodes or {}
    for i, d in ipairs(nodes) do
        local b = p.nodes[i] or makeNode(tt, p.graph)
        p.nodes[i] = b
        b.data = d
        b:ClearAllPoints()
        b:SetPoint("TOPLEFT", p.graph, "TOPLEFT", d.col * CW + OX, -(d.row * RH))
        b.icon:SetArt(d.icon or 134400)
        drawNode(b)
        b:Show()
    end
    for i = #nodes + 1, #p.nodes do p.nodes[i]:Hide(); p.nodes[i].data = nil end
    local links = t.links or {}
    for i, l in ipairs(links) do drawLink(p, i, l) end
    for i = #links + 1, #p.lines do p.lines[i]:Hide(); p.heads[i]:Hide() end
end

--------------------------------------------------------------------------------
-- The page
--------------------------------------------------------------------------------

function TT:SetSpecs(list, viewing)
    self.specList = list
    local show = list and #list > 1
    self.specRow:SetShown(show and true or false)
    if show then
        if not self.segmented or self.segmentedFor ~= #list then
            if self.segmented then self.segmented:Hide() end
            local options = {}
            for i, s in ipairs(list) do
                options[i] = { value = i, label = s.label .. (s.name and s.name ~= "" and (": " .. s.name) or ""), disabled = s.locked }
            end
            self.segmented = UI.Segmented(self.specRow, {
                options = options,
                onChange = function(v) if self.onSpec then self.onSpec(v) end end,
            })
            self.segmented:SetPoint("LEFT")
            self.segmentedFor = #list
        end
        self.segmented:SetValue(viewing or 1)
        local spec = list[viewing or 1] or {}
        self.activeBadge:SetShown(spec.active and true or false)
        self.activate:SetShown(not spec.active)
        if not spec.active then self.activate:SetLabel("Activate " .. (spec.name ~= "" and spec.name or spec.label or "")) end
    end
    self:Layout()
end

function TT:Layout()
    local top = 0
    if self.specRow:IsShown() then
        self.specRow:ClearAllPoints()
        self.specRow:SetPoint("TOPLEFT", self, "TOPLEFT", 0, 0)
        self.specRow:SetPoint("TOPRIGHT", self, "TOPRIGHT", 0, 0)
        top = top + 30 + S["space-5"]
    end
    self.summary:ClearAllPoints()
    self.summary:SetPoint("TOPLEFT", self, "TOPLEFT", 0, -top)
    self.summary:SetShown(not self.noSummary)
    if not self.noSummary then top = top + T.type.label.lineHeight + S["space-5"] end
    self.treesRow:ClearAllPoints()
    self.treesRow:SetPoint("TOPLEFT", self, "TOPLEFT", 0, -top)
    self.treesRow:SetPoint("BOTTOMRIGHT", self, "BOTTOMRIGHT", 0, FOOT_H + S["space-5"])
end

function TT:SetData(d)
    d = d or {}
    self.data = d
    local trees = d.trees or {}
    -- the summary: the spec, the points per tree
    local per, total = {}, 0
    for i, t in ipairs(trees) do per[i] = tostring(t.points or 0); total = total + (t.points or 0) end
    self.summaryName:SetValue(d.name or "")
    self.summaryPoints:SetValue(#per > 0 and (table.concat(per, " / ") .. " · " .. total .. " spent") or "")
    -- the trees, side by side, as wide as the row allows
    local width = self.treesRow:GetWidth()
    if not width or width <= 0 then width = UI.TALENT_TREE_W end
    local n = math.max(1, #trees)
    local panelW = math.max(PANEL_W, math.floor((width - GAP * (n - 1)) / n))
    local rows = d.rows or ROWS
    local anyMore = false
    for _, t in ipairs(trees) do if t.more then anyMore = true end end
    for i, t in ipairs(trees) do
        local p = self.panels[i] or makePanel(self)
        self.panels[i] = p
        p:ClearAllPoints()
        p:SetPoint("TOPLEFT", self.treesRow, "TOPLEFT", (i - 1) * (panelW + GAP), 0)
        p.graph:SetHeight(graphH(rows))
        local h = PAD + HEAD_H + PAD + graphH(rows) + PAD + (anyMore and (S["space-3"] + T.type.caption.lineHeight) or 0)
        if self.fillPanels then
            local room = self.treesRow:GetHeight()
            if room and room > h then h = room end
        end
        p:SetSize(panelW, h)
        fillPanel(self, p, t)
        p:Show()
    end
    for i = #trees + 1, #self.panels do self.panels[i]:Hide() end
    -- the foot
    local available = d.available or 0
    self.unspent:SetText(("|cff%s%d|r %s"):format(hex("ink"), available, available == 1 and "point to spend" or "points to spend"))
    local pending = d.pending or 0
    if pending > 0 then
        self.status:SetColor("arcane")
        self.status:SetValue(pending .. (pending == 1 and " point" or " points") .. " not applied yet · right-click to take one back")
    else
        self.status:SetColor("ink-muted")
        self.status:SetValue(d.hint or "Click a talent to plan a point. Nothing changes until you apply.")
    end
    self.undo:SetEnabledState(pending > 0)
    self.apply:SetEnabledState(pending > 0 and d.editable ~= false)
end

function UI.TalentTree(parent)
    local f = CreateFrame("Frame", nil, parent)
    Mixin(f, TT)
    f.panels = {}
    -- the specs (two talent groups only)
    f.specRow = CreateFrame("Frame", nil, f)
    f.specRow:SetHeight(30)
    f.activeBadge = UI.StateBadge(f.specRow, "neutral", "Active")
    f.activate = UI.Button(f.specRow, { text = "Activate", variant = "quiet",
        onClick = function() if f.onActivate then f.onActivate() end end })
    f.activeBadge:SetPoint("RIGHT", f.specRow, "RIGHT", 0, 0)
    f.activate:SetPoint("RIGHT", f.specRow, "RIGHT", 0, 0)
    f.specRow:Hide()
    -- the summary
    f.summary = CreateFrame("Frame", nil, f)
    f.summary:SetSize(1, T.type.label.lineHeight)
    f.summaryName = UI.Text(f.summary, "label", "ink")
    f.summaryName:SetPoint("LEFT")
    f.summaryPoints = UI.Text(f.summary, "caption", "ink-muted")
    f.summaryPoints:SetPoint("LEFT", f.summaryName, "RIGHT", S["space-5"], 0)
    -- the trees
    f.treesRow = CreateFrame("Frame", nil, f)
    -- the foot: a faint rule, the points, the status, Undo and Apply
    f.foot = CreateFrame("Frame", nil, f)
    f.foot:SetPoint("BOTTOMLEFT")
    f.foot:SetPoint("BOTTOMRIGHT")
    f.foot:SetHeight(FOOT_H)
    local rule = UI.Fill(f.foot, "gilt-faint", "ARTWORK")
    rule:SetHeight(1)
    rule:SetPoint("TOPLEFT")
    rule:SetPoint("TOPRIGHT")
    f.apply = UI.Button(f.foot, { text = "Apply", variant = "primary",
        onClick = function() if f.onApply then f.onApply() end end })
    f.apply:SetPoint("BOTTOMRIGHT", f.foot, "BOTTOMRIGHT", 0, 0)
    f.undo = UI.Button(f.foot, { text = "Undo", variant = "quiet",
        onClick = function() if f.onUndo then f.onUndo() end end })
    f.undo:SetPoint("RIGHT", f.apply, "LEFT", -S["space-3"], 0)
    f.unspent = UI.Text(f.foot, "caption", "ink-muted")
    f.unspent:SetPoint("LEFT", f.foot, "BOTTOMLEFT", 0, 15)
    f.status = UI.Text(f.foot, "caption", "ink-muted")
    f.status:SetPoint("LEFT", f.unspent, "RIGHT", S["space-5"], 0)
    f.status:SetPoint("RIGHT", f.undo, "LEFT", -S["space-5"], 0)
    f.status:SetJustifyH("LEFT")
    f:Layout()
    f:SetData({})
    return f
end

--------------------------------------------------------------------------------
-- A talent's tooltip: the game's own, as Blizzard's talent buttons build it
--------------------------------------------------------------------------------
--   UI.TraitTooltip(owner, configID, nodeID, {
--       name, treeName,      -- the title; the tree, for the game's "spend N
--                            -- more points in the X tree" lines
--       conditions,          -- the node's condition IDs
--       canSpend, pending,   -- a click plans a point; planned ranks
--       needs = { text },    -- more red lines (a talent above it)
--       blocked = text,      -- why nothing can change now
--   })
-- The title, "Rank 2/5", the talent's text at this rank and the next, what a
-- click does, what it still needs.

local function plainValue(v) return v ~= nil and not (issecretvalue and issecretvalue(v)) end

function UI.TraitTooltip(owner, configID, nodeID, o)
    o = o or {}
    local ok, ni = pcall(C_Traits.GetNodeInfo, configID, nodeID)
    if not ok or not ni then return end
    local tip = GameTooltip
    tip:SetOwner(owner, "ANCHOR_RIGHT")
    GameTooltip_SetTitle(tip, o.name or "")
    local current = plainValue(ni.currentRank) and ni.currentRank or 0
    local max = plainValue(ni.maxRanks) and ni.maxRanks or 1
    GameTooltip_AddHighlightLine(tip, (TALENT_BUTTON_TOOLTIP_RANK_FORMAT or "Rank %s/%s"):format(current, max))
    local increased = plainValue(ni.ranksIncreased) and ni.ranksIncreased or 0
    if ni.activeEntry and ni.activeEntry.entryID then
        GameTooltip_AddBlankLineToTooltip(tip)
        tip:AppendInfo("GetTraitEntry", ni.activeEntry.entryID, (ni.activeEntry.rank or 0) + increased)
    end
    if ni.nextEntry and ni.nextEntry.entryID and (ni.ranksPurchased or 0) > 0 then
        GameTooltip_AddBlankLineToTooltip(tip)
        GameTooltip_AddHighlightLine(tip, TALENT_BUTTON_TOOLTIP_NEXT_RANK or "Next Rank:")
        tip:AppendInfo("GetTraitEntry", ni.nextEntry.entryID, (ni.nextEntry.rank or 0) + increased)
    end
    if o.canSpend then
        GameTooltip_AddBlankLineToTooltip(tip)
        GameTooltip_AddInstructionLine(tip, TALENT_BUTTON_TOOLTIP_PURCHASE_INSTRUCTIONS or "Click to learn")
    elseif (o.pending or 0) > 0 then
        GameTooltip_AddBlankLineToTooltip(tip)
        GameTooltip_AddDisabledLine(tip, "Right-click to take a planned point back")
    end
    local spacer = true
    local function need(text, isError)
        if spacer then GameTooltip_AddBlankLineToTooltip(tip); spacer = false end
        if isError then GameTooltip_AddErrorLine(tip, text) else GameTooltip_AddHighlightLine(tip, text) end
    end
    local best
    for _, condID in ipairs(o.conditions or {}) do
        local okC, c = pcall(C_Traits.GetConditionInfo, configID, condID, false, o.treeName)
        if okC and c and c.isMet == false and plainValue(c.tooltipText) and c.tooltipText ~= "" then
            if not best or (c.spentAmountRequired or 0) > (best.spentAmountRequired or 0) then best = c end
        end
    end
    if best then need(best.tooltipText) end
    for _, text in ipairs(o.needs or {}) do need(text, true) end
    if o.blocked then need(o.blocked, true) end
    tip:Show()
end

