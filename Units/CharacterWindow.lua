-- Units/CharacterWindow.lua
-- The Character window in SuuUI's look (step 3.1, design boards
-- "Character", "Window frame"): Blizzard's own window (Forever's, with its
-- mode tabs, left and right panes; probed 2026-10-13) restyled in place, so
-- equipping, the model, every tab and Escape stay Blizzard's.
--   3.1a: the shell: SuuUI's header (icon, title, key chip, close) and the
--         mode tabs as text tabs along the top, in the design's order
--         (Character, Reputation, Currency, Player vs. Player, Skills,
--         Statistics); Blizzard's metal frame, portrait and pane
--         backgrounds out of sight. The window opens lined up under the
--         micro menu.
--   3.1b: the Character tab as the design: the identity line (class
--         diamond, name, level, race, class), the gear slots as SuuUI item
--         slots (quality edge, empty ones dimmed), the model in a gilt-faint
--         box without Blizzard's zoom and turn buttons, the stats as a
--         StatList (gilt-text heads, ink-muted labels, ink values, gilt-faint
--         rules), the side buttons (Stats, Titles, Sets) as a segmented row.
-- A built-in module written against the public API only.

local UI, T = SuuUI.UI, SuuUI.Tokens
local S = T.space
local isSecret = issecretvalue or function() return false end
local function plain(v) return v ~= nil and not isSecret(v) end
local QUALITY = { [0] = "poor", "common", "uncommon", "rare", "epic", "legendary", "legendary", "legendary" }

local SLOTS = { "Head", "Neck", "Shoulder", "Back", "Chest", "Shirt", "Tabard", "Wrist", "Hands", "Waist", "Legs",
                "Feet", "Finger0", "Finger1", "Trinket0", "Trinket1", "MainHand", "SecondaryHand", "Ranged" }

local M = SuuUI.RegisterModule({
    id = "character",
    name = "Character window",
    description = "The Character window (C) and its tabs in SuuUI's look.",
    api = "0.12",
    reloadToToggle = true,
    defaults = {},
})

-- Blizzard's mode tabs (CharacterFrameModeTab1-6) by the pane they open, in
-- the design's order.
local TABS = {
    { index = 1, pane = "PaperDollFrame", label = "Character", short = "Character" },
    { index = 2, pane = "ReputationFrame", label = "Reputation", short = "Reputation" },
    { index = 5, pane = "TokenFrame", label = "Currency", short = "Currency" },
    { index = 4, pane = "PVPRankFrame", label = "Player vs. Player", short = "PvP" },
    { index = 3, pane = "SkillsFrame", label = "Skills", short = "Skills" },
    { index = 6, pane = "StatisticsFrame", label = "Statistics", short = "Stats" },
}

local function shown(name)
    local f = _G[name]
    return f and f:IsShown() or false
end

function M:Skin()
    local cf = _G.CharacterFrame
    if not cf or self.chrome then return end
    -- the panes' own backgrounds (the first texture of each host)
    local hide = { cf.NineSlice, cf.PortraitContainer, cf.TitleContainer }
    for _, host in ipairs({ _G.CharacterFrameLeftPaneHost, _G.CharacterFrameRightPaneHost }) do
        if host then
            for _, r in ipairs({ host:GetRegions() }) do hide[#hide + 1] = r end
            -- the right pane's divider strip
            for _, c in ipairs({ host:GetChildren() }) do hide[#hide + 1] = c end
        end
    end
    self.chrome = UI.SkinWindow(cf, {
        title = "Character", icon = "person", binding = "TOGGLECHARACTER0",
        close = _G.CharacterFrameCloseButton, hide = hide, topInset = 20, under = "microMenu",
    })
    local list = {}
    for _, t in ipairs(TABS) do
        local button = _G["CharacterFrameModeTab" .. t.index]
        if button then
            list[#list + 1] = { button = button, label = t.label, short = t.short,
                selected = function()
                    if button.SelectedTexture then return button.SelectedTexture:IsShown() end
                    return shown(t.pane)
                end }
        end
    end
    self.chrome:SetTabs(list)
    -- a tab switched: the selected look follows
    hooksecurefunc("ToggleCharacter", function() if self.chrome then self.chrome:UpdateTabs() end end)
    cf:HookScript("OnShow", function() self.chrome:LayoutTabs(); self:UpdateIdentity() end)
    self:SkinPaperDoll()
end

--------------------------------------------------------------------------------
-- The Character tab
--------------------------------------------------------------------------------

local function alphaRegions(f, keep)
    if not f then return end
    for _, r in ipairs({ f:GetRegions() }) do
        if r ~= keep then r:SetAlpha(0) end
    end
end

-- "◆ Suther   Level 21 · Undead · Paladin", over the left pane.
function M:BuildIdentity()
    local host = _G.CharacterFrameLeftPaneHost
    if not host or self.identity then return end
    local id = CreateFrame("Frame", nil, host)
    id:SetPoint("TOPLEFT", S["space-5"], -S["space-3"])
    id:SetPoint("TOPRIGHT", -44, -S["space-3"])
    id:SetHeight(T.type["unit-name-lg"].lineHeight)
    id:SetFrameLevel(host:GetFrameLevel() + 520)
    -- the class diamond, centred on the name's line
    id.diamond = UI.Diamond(id, 7, "ink", "OVERLAY")
    id.diamond:SetPoint("CENTER", id, "LEFT", 4, 0)
    id.name = UI.Text(id, "unit-name-lg", "ink")
    id.name:SetPoint("LEFT", 8 + S["space-3"], 0)
    id.line = UI.Text(id, "caption", "ink-muted")
    id.line:SetPoint("LEFT", id.name, "RIGHT", S["space-4"], -1)
    self.identity = id
    -- Blizzard's strip and its "Level 21 Paladin"
    local strip = _G.PaperDollFrame and _G.PaperDollFrame.TopBackgroundStripHost
    if strip then strip:SetAlpha(0) end
    if _G.PaperDollLevelInfo then _G.PaperDollLevelInfo:SetAlpha(0) end
    if _G.PaperDollPetLevelInfo then _G.PaperDollPetLevelInfo:SetAlpha(0) end
    -- only on the Character tab
    if _G.PaperDollFrame then
        _G.PaperDollFrame:HookScript("OnShow", function() id:Show(); self:UpdateIdentity() end)
        _G.PaperDollFrame:HookScript("OnHide", function() id:Hide() end)
        id:SetShown(_G.PaperDollFrame:IsShown())
    end
end

function M:UpdateIdentity()
    local id = self.identity
    if not id then return end
    local _, class = UnitClass("player")
    local c = class and T.color["class-" .. class:lower()]
    if c then id.diamond:SetVertexColor(c[1], c[2], c[3], 1) end
    id.name:SetValue(UnitName("player") or "")
    local parts = { "Level " .. (UnitLevel("player") or "?") }
    local race = UnitRace("player")
    if race then parts[#parts + 1] = race end
    local className = UnitClass("player")
    if className then parts[#parts + 1] = className end
    id.line:SetValue(table.concat(parts, " · "))
end

-- An equipment slot in SuuUI's look; its border follows what Blizzard shows.
function M:SkinSlot(b)
    if self.slotSkins[b] then return end
    local skin = UI.SkinItemSlot(b)
    self.slotSkins[b] = skin
    local updating = false
    local function update()
        if updating then return end
        updating = true
        local id = b:GetID()
        local link = GetInventoryItemLink("player", id)
        local q = GetInventoryItemQuality("player", id)
        local icon = skin.icon:GetTexture()
        skin:SetItem({ icon = icon, quality = (plain(q) and q and QUALITY[q]) or "common", dim = not link })
        updating = false
    end
    hooksecurefunc(skin.icon, "SetTexture", update)
    b:HookScript("OnShow", update)
    self.slotUpdates[#self.slotUpdates + 1] = update
    update()
end

-- The arrows beside the slots in Sets mode (each slot's popout button): a
-- gilt chevron pointing away from the slot.
local LEFT_COLUMN = { Head = true, Neck = true, Shoulder = true, Back = true, Chest = true, Shirt = true, Tabard = true, Wrist = true }
local WEAPONS = { MainHand = true, SecondaryHand = true, Ranged = true }
local GLYPH_DIR = "Interface\\AddOns\\SuuUI\\Media\\Textures\\Glyphs\\"

function M:SkinPopout(slotName, b)
    local p = b.popoutButton
    if not p or p.suuSkinned then return end
    p.suuSkinned = true
    local glyph = p:CreateTexture(nil, "OVERLAY", nil, 7)
    glyph:SetSize(12, 12)
    glyph:SetPoint("CENTER")
    glyph:SetVertexColor(UI.RGBA("gilt-text"))
    if WEAPONS[slotName] then
        glyph:SetTexture(GLYPH_DIR .. "chevronDown.tga")
        glyph:SetRotation(math.pi)
    else
        glyph:SetTexture(GLYPH_DIR .. (LEFT_COLUMN[slotName] and "chevronRight" or "chevronLeft") .. ".tga")
    end
    local function hideArt()
        for _, get in ipairs({ "GetNormalTexture", "GetPushedTexture", "GetHighlightTexture", "GetDisabledTexture" }) do
            local t = p[get] and p[get](p)
            if t then t:SetAlpha(0) end
        end
        for _, r in ipairs({ p:GetRegions() }) do
            if r ~= glyph and r:GetObjectType() == "Texture" then r:SetAlpha(0) end
        end
    end
    hideArt()
    p:HookScript("OnShow", hideArt)
    p:HookScript("OnEnter", function() glyph:SetVertexColor(UI.RGBA("gilt")) end)
    p:HookScript("OnLeave", function() glyph:SetVertexColor(UI.RGBA("gilt-text")) end)
end

-- The flyout of items for a slot: glass behind, SuuUI item slots.
function M:SkinFlyout()
    local fly = _G.EquipmentFlyoutFrame
    if not fly or self.flyoutSkinned then return end
    self.flyoutSkinned = true
    local function skinButtons()
        local holder = fly.buttonFrame or fly
        for _, r in ipairs({ holder:GetRegions() }) do
            if r:GetObjectType() == "Texture" and not r.suuArt then r:SetAlpha(0) end
        end
        if fly.Highlight then
            for _, r in ipairs({ fly.Highlight:GetRegions() }) do r:SetAlpha(0) end
        end
        if not holder.suuBg then
            holder.suuBg = holder:CreateTexture(nil, "BACKGROUND", nil, -8)
            holder.suuBg.suuArt = true
            holder.suuBg:SetColorTexture(UI.RGBA("surface-glass"))
            holder.suuBg:SetAllPoints()
            UI.Border(holder, "gilt-line")
        end
        for i = 1, 40 do
            local b = _G["EquipmentFlyoutFrameButton" .. i]
            if not b then break end
            if not self.flyoutSkins[b] then self.flyoutSkins[b] = UI.SkinItemSlot(b) end
            local icon = self.flyoutSkins[b].icon
            self.flyoutSkins[b]:SetItem(icon and icon:GetTexture() and { icon = icon:GetTexture() } or nil)
        end
    end
    self.flyoutSkins = {}
    fly:HookScript("OnShow", function() C_Timer.After(0, skinButtons) end)
    if type(_G.EquipmentFlyout_DisplayButton) == "function" then
        hooksecurefunc("EquipmentFlyout_DisplayButton", function() C_Timer.After(0, skinButtons) end)
    end
end

-- The new-set popup (name, icon, Okay, Cancel): glass in a gilt edge, its
-- input, buttons and scrollbar through UI.Reskin; the icons stay.
function M:SkinSetPopup()
    local pop = _G.GearManagerPopupFrame or (_G.PaperDollFrame and _G.PaperDollFrame.GearManagerPopupFrame)
    if not pop or pop.suuSkinned then return end
    pop.suuSkinned = true
    local function art(f)
        if not f then return end
        if f.NineSlice then f.NineSlice:SetAlpha(0) end
        for _, r in ipairs({ f:GetRegions() }) do
            if r:GetObjectType() == "Texture" then r:SetAlpha(0) end
        end
    end
    art(pop)
    art(pop.BorderBox)
    if pop.BorderBox then
        for _, c in ipairs({ pop.BorderBox:GetChildren() }) do
            if c:GetObjectType() == "Frame" then art(c) end
        end
    end
    local bg = pop:CreateTexture(nil, "BACKGROUND", nil, -8)
    bg:SetColorTexture(UI.RGBA("surface-glass"))
    bg:SetAllPoints()
    local edge = CreateFrame("Frame", nil, pop)
    edge:SetAllPoints()
    edge:EnableMouse(false)
    UI.Border(edge, "gilt-line")
    local jewel = UI.Diamond(edge, 7, "gilt")
    jewel:SetPoint("CENTER", pop, "TOPLEFT", 0, 0)
    -- the chosen icon (top right) and the grid's icons: SuuUI's icon buttons
    -- (the chosen icon: whichever button with an Icon sits outside the grid)
    local function findChosen(f, depth)
        if depth > 4 or f == pop.IconSelector then return nil end
        if f ~= pop and f:GetObjectType() == "Button" and (f.Icon or f.icon) then return f end
        for _, c in ipairs({ f:GetChildren() }) do
            local hit = findChosen(c, depth + 1)
            if hit then return hit end
        end
    end
    local chosen
    local function icons()
        chosen = chosen or findChosen(pop, 0)
        if chosen then UI.ReskinIconButton(chosen) end
        local sb = pop.IconSelector and (pop.IconSelector.ScrollBox or pop.IconSelector)
        if sb and sb.ForEachFrame then
            sb:ForEachFrame(function(b) UI.ReskinIconButton(b) end)
        end
    end
    local sb = pop.IconSelector and pop.IconSelector.ScrollBox
    if sb then
        if sb.Update then hooksecurefunc(sb, "Update", icons) end
        if sb.RegisterCallback and sb.Event and sb.Event.OnDataRangeChanged then
            sb:RegisterCallback(sb.Event.OnDataRangeChanged, icons, self)
        end
    end
    -- lined up with the window: its header's top, its bottom, space-4 beside it
    local cf = _G.CharacterFrame
    local placing = false
    local function place()
        if placing or not cf then return end
        placing = true
        pop:ClearAllPoints()
        pop:SetPoint("TOPLEFT", cf, "TOPRIGHT", S["space-4"], (UI.WINDOW_HEAD_H or 61) - 20)
        pop:SetPoint("BOTTOMLEFT", cf, "BOTTOMRIGHT", S["space-4"], 0)
        placing = false
    end
    hooksecurefunc(pop, "SetPoint", function() if not placing then C_Timer.After(0, place) end end)
    -- the icon grid ends above Okay and Cancel (Blizzard's art hid the overlap)
    local box = pop.BorderBox
    local okay = box and (box.OkayButton or box.OkButton)
    local grid = pop.IconSelector
    local function fit()
        if grid and okay then
            grid:SetPoint("BOTTOMRIGHT", pop, "BOTTOMRIGHT", -S["space-5"], (okay:GetTop() and pop:GetBottom())
                and (okay:GetTop() - pop:GetBottom() + S["space-4"]) or 44)
        end
    end
    pop:HookScript("OnShow", function()
        place()
        C_Timer.After(0, function()
            UI.Reskin(pop)
            fit()
            icons()
        end)
    end)
end

function M:UpdateSlots()
    for _, u in ipairs(self.slotUpdates) do u() end
end

-- The model in a gilt-faint box between the slot columns, without the
-- zoom and turn buttons (drag the model to turn it).
function M:SkinModel()
    local scene = _G.CharacterModelScene
    local head, hands = _G.CharacterHeadSlot, _G.CharacterHandsSlot
    if not (scene and head and hands) or self.modelBox then return end
    local box = CreateFrame("Frame", nil, _G.CharacterFrameLeftPaneHost)
    box:SetPoint("TOPLEFT", head, "TOPRIGHT", S["space-4"], 0)
    box:SetPoint("BOTTOMRIGHT", _G.CharacterTrinket1Slot or hands, "BOTTOMLEFT", -S["space-4"], 0)
    box:SetFrameLevel(math.max(1, scene:GetFrameLevel() - 1))
    UI.Fill(box, "surface-sunk"):SetAllPoints()
    UI.Border(box, "gilt-faint")
    self.modelBox = box
    local controls = scene.ControlFrame
    if controls then
        controls:SetAlpha(0)
        controls:EnableMouse(false)
        for _, c in ipairs({ controls:GetChildren() }) do
            c:EnableMouse(false)
        end
    end
    if _G.PaperDollFrame then
        _G.PaperDollFrame:HookScript("OnShow", function() box:Show() end)
        _G.PaperDollFrame:HookScript("OnHide", function() box:Hide() end)
        box:SetShown(_G.PaperDollFrame:IsShown())
    end
end

--------------------------------------------------------------------------------
-- Stats: a StatList
--------------------------------------------------------------------------------

local function isWhite(r, g, b) return r and r > 0.9 and g > 0.9 and b > 0.9 end
local function isGreen(r, g, b) return r and g > 0.7 and r < 0.5 and b < 0.5 end
local function isRed(r, g, b) return r and r > 0.8 and g < 0.4 and b < 0.4 end

-- A row of the stats pane: a category head (one text, a banner) or a stat
-- (its label left, its value right).
function M:SkinStatRow(row)
    local texts = {}
    for _, r in ipairs({ row:GetRegions() }) do
        if r:GetObjectType() == "Texture" then
            r:SetAlpha(0)
        elseif r:GetObjectType() == "FontString" and r:IsShown() then
            texts[#texts + 1] = r
        end
    end
    for _, c in ipairs({ row:GetChildren() }) do
        for _, r in ipairs({ c:GetRegions() }) do
            if r:GetObjectType() == "Texture" then
                r:SetAlpha(0)
            elseif r:GetObjectType() == "FontString" and r:IsShown() then
                texts[#texts + 1] = r
            end
        end
    end
    if not row.suuRule then
        row.suuRule = row:CreateTexture(nil, "ARTWORK")
        row.suuRule:SetColorTexture(UI.RGBA("gilt-faint"))
        row.suuRule:SetHeight(1)
        row.suuRule:SetPoint("TOPLEFT")
        row.suuRule:SetPoint("TOPRIGHT")
    end
    local head = #texts == 1 or row:GetHeight() > 30
    row.suuRule:SetShown(not head)
    if head then
        for _, t in ipairs(texts) do
            SuuUI.Fonts.Apply(t, "header")
            t:SetTextColor(UI.RGBA("gilt-text"))
            t:SetShadowOffset(0, 0)
        end
        return
    end
    table.sort(texts, function(a, b) return (a:GetLeft() or 0) < (b:GetLeft() or 0) end)
    local label, value = texts[1], texts[#texts]
    if label then
        SuuUI.Fonts.Apply(label, "body")
        label:SetTextColor(UI.RGBA("ink-muted"))
        label:SetShadowOffset(0, 0)
    end
    if value and value ~= label then
        local r, g, b = value:GetTextColor()
        SuuUI.Fonts.Apply(value, "numeric")
        if isGreen(r, g, b) then value:SetTextColor(UI.RGBA("fel"))
        elseif isRed(r, g, b) then value:SetTextColor(UI.RGBA("ember-text"))
        else value:SetTextColor(UI.RGBA("ink")) end
        value:SetShadowOffset(0, 0)
    end
end

function M:SkinStatsPane()
    for _, name in ipairs({ "CharacterStatsPaneScrollBox", "CharacterStatsPanePetScrollBox" }) do
        local pane = _G[name]
        if pane and not pane.suuSkinned then
            pane.suuSkinned = true
            alphaRegions(pane)
            local box = pane.ScrollBox
            if box then
                local function skinAll()
                    if box.ForEachFrame then
                        box:ForEachFrame(function(row) self:SkinStatRow(row) end)
                    else
                        for _, row in ipairs({ box.ScrollTarget and box.ScrollTarget:GetChildren() }) do self:SkinStatRow(row) end
                    end
                end
                if box.Update then hooksecurefunc(box, "Update", skinAll) end
                if box.RegisterCallback and box.Event and box.Event.OnDataRangeChanged then
                    box:RegisterCallback(box.Event.OnDataRangeChanged, skinAll, self)
                end
                pane:HookScript("OnShow", function() C_Timer.After(0, skinAll) end)
                skinAll()
            end
            self:SkinScrollBar(pane.ScrollBar)
        end
    end
end

-- Blizzard's thin scrollbar: no track art, a gilt-line thumb.
function M:SkinScrollBar(bar)
    if not bar or bar.suuSkinned then return end
    bar.suuSkinned = true
    local track = bar.Track
    if track then
        alphaRegions(track)
        local thumb = track.Thumb
        if thumb then
            alphaRegions(thumb)
            local t = thumb:CreateTexture(nil, "OVERLAY")
            t:SetColorTexture(UI.RGBA("gilt-line"))
            t:SetPoint("TOP")
            t:SetPoint("BOTTOM")
            t:SetWidth(2)
        end
    end
    for _, key in ipairs({ "Back", "Forward" }) do
        if bar[key] then bar[key]:SetAlpha(0) end
    end
end

--------------------------------------------------------------------------------
-- The side buttons: Stats | Titles | Sets as a segmented row
--------------------------------------------------------------------------------

-- Blizzard's second side button is the equipment sets, the third the
-- titles (found in game); shown as Stats | Sets | Titles.
local SIDE = { { tab = 1, label = "Stats" }, { tab = 2, label = "Sets" }, { tab = 3, label = "Titles" } }

function M:SkinSidebar()
    local tabs = _G.PaperDollSidebarTabs
    if not tabs or self.sidebar then return end
    alphaRegions(tabs)
    local row = CreateFrame("Frame", nil, tabs)
    row:SetHeight(26)
    row:SetPoint("TOPLEFT", S["space-5"], -S["space-4"])
    row:SetPoint("TOPRIGHT", -S["space-5"], -S["space-4"])
    UI.Fill(row, "surface-sunk"):SetAllPoints()
    UI.Border(row, "gilt-line")
    self.sidebar = { row = row, buttons = {} }
    local prev
    local w = 0
    for _, def in ipairs(SIDE) do
        local b = _G["PaperDollSidebarTab" .. def.tab]
        if b then
            b.suuNoCheck = true
            alphaRegions(b)
            if b.Icon then b.Icon:SetAlpha(0) end
            for _, get in ipairs({ "GetNormalTexture", "GetPushedTexture", "GetHighlightTexture", "GetCheckedTexture" }) do
                local t = b[get] and b[get](b)
                if t then t:SetAlpha(0) end
            end
            b.suuFill = UI.Fill(b, "arcane-soft", "BACKGROUND", 7)
            b.suuFill:SetAllPoints()
            b.suuEdge = UI.Border(b, "arcane")
            b.suuLabel = UI.Text(b, "label", "ink-muted")
            b.suuLabel:SetPoint("CENTER")
            b.suuLabel:SetValue(def.label)
            b.suuSelected = select(3, b:GetRegions())
            b:SetFrameLevel(row:GetFrameLevel() + 2)
            b:HookScript("OnEnter", function() self:UpdateSidebar(b) end)
            b:HookScript("OnLeave", function() self:UpdateSidebar() end)
            self.sidebar.buttons[#self.sidebar.buttons + 1] = b
        end
    end
    local function layout()
        local n = #self.sidebar.buttons
        local inner = row:GetWidth() - 6
        if inner <= 0 then return end
        local each = (inner - (n - 1) * 2) / n
        for i, b in ipairs(self.sidebar.buttons) do
            self.placingSide = true
            b:ClearAllPoints()
            b:SetSize(each, 20)
            b:SetPoint("TOPLEFT", row, "TOPLEFT", 3 + (i - 1) * (each + 2), -3)
            self.placingSide = false
        end
    end
    row:SetScript("OnSizeChanged", layout)
    for _, b in ipairs(self.sidebar.buttons) do
        hooksecurefunc(b, "SetPoint", function()
            if self.placingSide then return end
            C_Timer.After(0, layout)
        end)
    end
    layout()
    hooksecurefunc("PaperDollFrame_SetSidebar", function(_, index)
        self.sideIndex = index
        self:UpdateSidebar()
    end)
    self.sideIndex = 1
    self:UpdateSidebar()
end

function M:UpdateSidebar(hover)
    if not self.sidebar then return end
    for i, b in ipairs(self.sidebar.buttons) do
        local on = (SIDE[i] and SIDE[i].tab) == self.sideIndex
        b.suuFill:SetShown(on)
        b.suuEdge:SetShown(on)
        b.suuLabel:SetColor(on and "arcane" or (b == hover and "ink" or "ink-muted"))
    end
end

-- New Set (its own button, centred above Equip and Save: probed 2026-10-13)
-- exactly as wide as the two together, so the edges line up (asked for).
function M:AlignSetList()
    local new, equip, save = _G.PaperDollFrameNewSet, _G.PaperDollFrameEquipSet, _G.PaperDollFrameSaveSet
    if not (new and equip and save and equip:GetLeft() and save:GetRight()) then return end
    new:SetWidth(save:GetRight() - equip:GetLeft())
end

function M:SkinPaperDoll()
    self.slotSkins, self.slotUpdates = {}, {}
    self:BuildIdentity()
    self:UpdateIdentity()
    for _, s in ipairs(SLOTS) do
        local b = _G["Character" .. s .. "Slot"]
        if b then
            self:SkinSlot(b)
            self:SkinPopout(s, b)
        end
    end
    self:SkinFlyout()
    self:SkinSetPopup()
    local pane = _G.PaperDollFrame and _G.PaperDollFrame.EquipmentManagerPane
    if pane then
        pane:HookScript("OnShow", function() C_Timer.After(0, function() self:AlignSetList() end) end)
    end
    self:SkinModel()
    self:SkinStatsPane()
    self:SkinSidebar()
    -- the toggle for the right pane: a small square with SuuUI's edge and a
    -- chevron pointing the way the pane goes
    local toggle = _G.CharacterFrameRightPaneToggleButton
    if toggle then
        local function hideArt()
            for _, get in ipairs({ "GetNormalTexture", "GetPushedTexture", "GetHighlightTexture", "GetDisabledTexture" }) do
                local t = toggle[get] and toggle[get](toggle)
                if t then t:SetAlpha(0) end
            end
            for _, r in ipairs({ toggle:GetRegions() }) do
                if r ~= toggle.suuChevron and r:GetObjectType() == "Texture" then r:SetAlpha(0) end
            end
        end
        local edge = UI.Border(toggle, "gilt-line")
        local chev = toggle:CreateTexture(nil, "OVERLAY", nil, 7)
        chev:SetSize(14, 14)
        chev:SetPoint("CENTER")
        chev:SetVertexColor(UI.RGBA("ink-muted"))
        toggle.suuChevron = chev
        local right = _G.CharacterFrameRightPaneHost
        local function draw()
            hideArt()
            chev:SetAlpha(1)
            local open = right and right:IsShown()
            chev:SetTexture("Interface\\AddOns\\SuuUI\\Media\\Textures\\Glyphs\\" .. (open and "chevronLeft" or "chevronRight") .. ".tga")
        end
        toggle:SetSize(22, 22)
        toggle:HookScript("OnEnter", function() edge:SetColor("gilt"); chev:SetVertexColor(UI.RGBA("ink")) end)
        toggle:HookScript("OnLeave", function() edge:SetColor("gilt-line"); chev:SetVertexColor(UI.RGBA("ink-muted")) end)
        toggle:HookScript("OnClick", function() C_Timer.After(0, draw) end)
        if right then
            right:HookScript("OnShow", draw)
            right:HookScript("OnHide", draw)
        end
        draw()
    end
    self:SkinPanes()
end

--------------------------------------------------------------------------------
-- The other tabs, the titles and the equipment sets: Blizzard's lists and
-- detail panes through UI.Reskin (rows, category bars, bars, check buttons)
--------------------------------------------------------------------------------

local PANES = { "ReputationFrame", "SkillsFrame", "PVPRankFrame", "TokenFrame", "StatisticsFrame" }

function M:SkinPanes()
    local function watch(f)
        if not f or f.suuPane then return end
        f.suuPane = true
        f:HookScript("OnShow", function() C_Timer.After(0, function() UI.Reskin(f) end) end)
        if f:IsShown() then UI.Reskin(f) end
    end
    for _, name in ipairs(PANES) do watch(_G[name]) end
    local pd = _G.PaperDollFrame
    if pd then
        watch(pd.TitleManagerPane)
        watch(pd.EquipmentManagerPane)
    end
end

function M:OnEnable()
    self:OnGameEvent("PLAYER_EQUIPMENT_CHANGED", function() if self.slotUpdates then self:UpdateSlots() end end)
    self:OnGameEvent("PLAYER_LEVEL_UP", function() self:UpdateIdentity() end)
    if _G.CharacterFrame then
        self:Skin()
    else
        -- the window's addon loads later on some clients
        self:OnGameEvent("ADDON_LOADED", function() if _G.CharacterFrame then self:Skin() end end)
    end
end
