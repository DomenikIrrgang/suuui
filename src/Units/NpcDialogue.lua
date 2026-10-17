-- Units/NpcDialogue.lua
-- SuuUI's NPC dialogue (plan 3.7, design component NpcDialogue, direction
-- C1 "Cinematic bar", chosen 2026-10-17): talking to an NPC becomes a scene
-- docked at the bottom centre, over the action bars. The speaker as a live
-- 3D portrait breaking out above the bar (a PlayerModel on the "npc" unit:
-- /suu probe npcportrait, 2026-10-17, every NPC drawn, with its talk
-- animations), a name plate with their role; what they say types in, with
-- the talk animation while it does; your answers numbered under it: the
-- gossip options, their quests, Goodbye last. The quest flow speaks the
-- same way: a quest's text as their line, what they ask and the rewards as
-- cards, then Accept or Decline; progress with your counts; the reward to
-- choose. 1-9 answer, Space shows the whole line, Enter accepts or
-- completes, Esc leaves.
-- The game's GossipFrame and QuestFrame keep running the conversation, shown
-- but out of sight (closing either ends the interaction); their data
-- functions are free and the quest buttons are the game's own, clicked
-- (Accept keeps its PvP confirmation, Complete its money one). Nothing here
-- is protected (/suu probe windows, 2026-10-17).
-- A built-in module written against the public API only.

local UI, T = SuuUI.UI, SuuUI.Tokens
local S = T.space

local M = SuuUI.RegisterModule({
    id = "npcdialogue",
    name = "NPC dialogue",
    description = "Talking to an NPC as a scene: their live portrait, what they say, your answers numbered below; quests in the same voice.",
    api = "0.17",
    reloadToToggle = true,
    defaults = {},
})

local isSecret = issecretvalue or function() return false end
local function plain(v) return v ~= nil and not isSecret(v) end
local function call(fn, ...)
    if type(fn) ~= "function" then return nil end
    local ok, a, b, c, d, e, f, g, h, i = pcall(fn, ...)
    if ok then return a, b, c, d, e, f, g, h, i end
end

local BAR_W = 1080
local PAD, PAD_R = S["space-6"], S["space-7"]
local PORT_W, PORT_H, RISE = 236, 268, 110
local PLATE_H = 52
local YOU = 64
local GAP = S["space-7"]
local ANS_H = 34
local SPEECH_MAX = 140
local CARD_W, CARD_H = 150, 104
local ZOOM = 0.75
local CPS = 90 -- characters a second while a line types in
local ANIM_TALK, ANIM_IDLE = 60, 0
local GLYPHS = "Interface\\AddOns\\SuuUI\\Media\\Textures\\Glyphs\\"
local SOFT = "Interface\\AddOns\\SuuUI\\Media\\Textures\\CircleSoft.tga"
local QUALITY = { [0] = "poor", "common", "uncommon", "rare", "epic", "legendary", "legendary", "legendary" }

-- the game's gossip icons as SuuUI glyphs (the icon itself where unknown)
local OPTION_GLYPH = {
    [132050] = "bank", [132051] = "swords", [132052] = "inn", [132053] = "chat", [132055] = "scroll",
    [132056] = "tabard", [132057] = "wing", [132058] = "book", [132060] = "bag",
}

-- an item's equip slot, for "Upgrade" on a reward
local EQUIP_SLOTS = {
    INVTYPE_HEAD = { 1 }, INVTYPE_NECK = { 2 }, INVTYPE_SHOULDER = { 3 }, INVTYPE_BODY = { 4 }, INVTYPE_CHEST = { 5 },
    INVTYPE_ROBE = { 5 }, INVTYPE_WAIST = { 6 }, INVTYPE_LEGS = { 7 }, INVTYPE_FEET = { 8 }, INVTYPE_WRIST = { 9 },
    INVTYPE_HAND = { 10 }, INVTYPE_FINGER = { 11, 12 }, INVTYPE_TRINKET = { 13, 14 }, INVTYPE_CLOAK = { 15 },
    INVTYPE_WEAPON = { 16, 17 }, INVTYPE_SHIELD = { 17 }, INVTYPE_2HWEAPON = { 16 }, INVTYPE_WEAPONMAINHAND = { 16 },
    INVTYPE_WEAPONOFFHAND = { 17 }, INVTYPE_HOLDABLE = { 17 }, INVTYPE_RANGED = { 18 }, INVTYPE_RANGEDRIGHT = { 18 },
    INVTYPE_THROWN = { 18 }, INVTYPE_RELIC = { 18 }, INVTYPE_TABARD = { 19 },
}

local function itemLevel(link)
    local lvl = link and call(C_Item.GetDetailedItemLevelInfo, link)
    return plain(lvl) and lvl or nil
end

-- Whether an item would raise the item level of what you wear there.
local function upgrade(link)
    if not link then return false end
    local _, _, _, _, _, _, _, _, equipLoc = C_Item.GetItemInfo(link)
    local slots = equipLoc and EQUIP_SLOTS[equipLoc]
    local mine = itemLevel(link)
    if not (slots and mine) then return false end
    local lowest
    for _, s in ipairs(slots) do
        local worn = itemLevel(GetInventoryItemLink("player", s)) or 0
        lowest = lowest and math.min(lowest, worn) or worn
    end
    return mine > (lowest or 0)
end

-- A text's characters' byte ends, to type it in without cutting one.
local function charEnds(text)
    local ends, i = {}, 1
    while i <= #text do
        local c = text:byte(i)
        local n = c < 0x80 and 1 or c < 0xE0 and 2 or c < 0xF0 and 3 or 4
        -- colour codes and textures appear whole
        if text:sub(i, i + 1) == "|c" then n = 10
        elseif text:sub(i, i + 1) == "|r" then n = 2
        elseif text:sub(i, i + 1) == "|T" then local e = text:find("|t", i, true); n = e and (e - i + 2) or n end
        i = i + n
        ends[#ends + 1] = math.min(i - 1, #text)
    end
    return ends
end

--------------------------------------------------------------------------------
-- The bar
--------------------------------------------------------------------------------

-- One answer: its key, a glyph or a quest mark, the text, a tag, why it's off.
function M:BuildAnswer(parent)
    local b = CreateFrame("Button", nil, parent)
    b:SetHeight(ANS_H)
    b.hover = b:CreateTexture(nil, "BACKGROUND")
    b.hover:SetAllPoints()
    b.hover:SetColorTexture(1, 1, 1, 1)
    local r, g, bl = UI.RGBA("arcane")
    b.hover:SetGradient("HORIZONTAL", CreateColor(r, g, bl, 0.18), CreateColor(r, g, bl, 0.03))
    b.hover:Hide()
    b.edge = UI.Fill(b, "arcane", "ARTWORK")
    b.edge:SetPoint("TOPLEFT")
    b.edge:SetPoint("BOTTOMLEFT")
    b.edge:SetWidth(3)
    b.edge:Hide()
    b.key = UI.KeyChip(b, "1")
    b.key:SetPoint("LEFT", S["space-4"], 0)
    b.glyph = b:CreateTexture(nil, "ARTWORK")
    b.glyph:SetSize(15, 15)
    b.glyph:SetPoint("LEFT", S["space-4"] + 22 + S["space-4"] + 2, 0)
    b.mark = UI.Text(b, "alert", "gilt-text")
    b.mark:SetPoint("CENTER", b.glyph, "CENTER", 0, 0)
    b.text = UI.Text(b, "body", "ink")
    b.text:SetFont(T.type.body.file, 14, "")
    b.text:SetPoint("LEFT", b.glyph, "RIGHT", S["space-4"] + 2, 0)
    b.text:SetJustifyH("LEFT")
    b.text:SetWordWrap(false)
    b.tag = UI.Text(b, "micro", "gilt-text")
    b.tag:SetPoint("LEFT", b.text, "RIGHT", S["space-4"], 0)
    b.why = UI.Text(b, "caption", "ember-text")
    b.why:SetPoint("RIGHT", -S["space-5"], 0)
    function b:Lit(on)
        on = on and not self.off
        self.hover:SetShown(on)
        self.edge:SetShown(on)
        self.key.text:SetColor(on and "arcane" or "ink-muted")
    end
    b:SetScript("OnEnter", function(self) self:Lit(true) end)
    b:SetScript("OnLeave", function(self) self:Lit(false) end)
    b:SetScript("OnClick", function(self)
        if self.off or not self.act then return end
        PlaySound(SOUNDKIT.IG_QUEST_LIST_SELECT)
        self.act()
    end)
    return b
end

-- One card: an item to choose, receive or hand over.
function M:BuildCard(parent)
    local c = CreateFrame("Button", nil, parent)
    c:SetSize(CARD_W, CARD_H)
    c.bg = UI.Fill(c, "surface-sunk", "BACKGROUND")
    c.bg:SetAllPoints()
    c.border = UI.Border(c, "gilt-faint")
    c.slot = UI.ItemSlot(c, 36)
    c.slot:SetPoint("TOPLEFT", S["space-4"], -S["space-4"])
    c.slot:EnableMouse(false)
    c.up = UI.Text(c, "micro", "arcane")
    c.up:SetPoint("TOPRIGHT", -S["space-3"], -S["space-3"])
    c.name = UI.Text(c, "label", "ink")
    c.name:SetPoint("TOPLEFT", c.slot, "BOTTOMLEFT", 0, -S["space-2"])
    c.name:SetPoint("RIGHT", -S["space-4"], 0)
    c.name:SetJustifyH("LEFT")
    c.name:SetWordWrap(true)
    c.name:SetMaxLines(2)
    c.note = UI.Text(c, "caption", "ink-muted")
    c.note:SetPoint("BOTTOMLEFT", S["space-4"], S["space-3"])
    c:SetScript("OnEnter", function(self)
        if not self.on then self.border:SetColor("gilt-line") end
        if self.kind then
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT", S["space-4"], 0)
            GameTooltip:SetQuestItem(self.kind, self.index)
            GameTooltip:Show()
        end
    end)
    c:SetScript("OnLeave", function(self)
        if not self.on then self.border:SetColor("gilt-faint") end
        GameTooltip:Hide()
    end)
    c:SetScript("OnClick", function(self)
        if self.kind == "choice" and self.choosable then
            self.choose(self.index)
        elseif self.link then
            HandleModifiedItemClick(self.link)
        end
    end)
    function c:SetOn(on)
        self.on = on
        self.border:SetColor(on and "arcane" or "gilt-faint")
        self.bg:SetColorTexture(UI.RGBA(on and "arcane-soft" or "surface-sunk"))
    end
    return c
end

function M:BuildPortrait(parent)
    local p = CreateFrame("Frame", nil, parent)
    p:SetSize(PORT_W, PORT_H)
    p:SetClipsChildren(true)
    local base = p:CreateTexture(nil, "BACKGROUND", nil, -8)
    base:SetAllPoints()
    base:SetColorTexture(1, 1, 1, 1)
    base:SetGradient("VERTICAL", CreateColor(0.047, 0.039, 0.031, 1), CreateColor(0.129, 0.110, 0.090, 1))
    local light = p:CreateTexture(nil, "BACKGROUND", nil, -7)
    light:SetTexture(SOFT)
    light:SetBlendMode("ADD")
    light:SetPoint("TOPLEFT", -24, PORT_H * 0.35)
    light:SetPoint("BOTTOMRIGHT", 24, PORT_H * 0.35 - PORT_H)
    local r, g, b = UI.RGBA("gilt")
    light:SetVertexColor(r * 0.1, g * 0.1, b * 0.1)
    p.model = CreateFrame("PlayerModel", nil, p)
    p.model:SetPoint("TOPLEFT", 1, -1)
    p.model:SetPoint("BOTTOMRIGHT", -1, 1)
    -- the vignette over the model: the bottom and the sides darker
    local over = CreateFrame("Frame", nil, p)
    over:SetAllPoints()
    over:SetFrameLevel(p.model:GetFrameLevel() + 2)
    local bottom = over:CreateTexture(nil, "ARTWORK")
    bottom:SetColorTexture(1, 1, 1, 1)
    bottom:SetGradient("VERTICAL", CreateColor(0, 0, 0, 0.7), CreateColor(0, 0, 0, 0))
    bottom:SetPoint("BOTTOMLEFT")
    bottom:SetPoint("BOTTOMRIGHT")
    bottom:SetHeight(PORT_H * 0.4)
    for _, side in ipairs({ "LEFT", "RIGHT" }) do
        local t = over:CreateTexture(nil, "ARTWORK")
        t:SetColorTexture(1, 1, 1, 1)
        t:SetGradient("HORIZONTAL", CreateColor(0, 0, 0, side == "LEFT" and 0.35 or 0), CreateColor(0, 0, 0, side == "LEFT" and 0 or 0.35))
        t:SetPoint("TOP" .. side)
        t:SetPoint("BOTTOM" .. side)
        t:SetWidth(PORT_W * 0.25)
    end
    UI.Border(over, "gilt-line")
    return p
end

function M:Build()
    -- the scene: a light vignette over the world, the bar on it
    local root = CreateFrame("Frame", "SuuUINpcDialogue", SuuUI.Root)
    root:SetAllPoints(UIParent)
    root:SetFrameStrata("DIALOG")
    root:Hide()
    local vig = root:CreateTexture(nil, "BACKGROUND")
    vig:SetColorTexture(1, 1, 1, 1)
    vig:SetGradient("VERTICAL", CreateColor(0, 0, 0, 0.65), CreateColor(0, 0, 0, 0))
    vig:SetPoint("BOTTOMLEFT")
    vig:SetPoint("BOTTOMRIGHT")
    vig:SetPoint("TOP", root, "CENTER", 0, -40)
    self.root = root

    local bar = CreateFrame("Frame", nil, root)
    bar:SetWidth(BAR_W)
    bar:SetPoint("BOTTOM", UIParent, "BOTTOM", 0, 28)
    bar:EnableMouse(true)
    UI.Fill(bar, "surface", "BACKGROUND"):SetAllPoints()
    UI.Border(bar, "gilt-faint")
    local edge = UI.Hairline(bar, "gilt", "both")
    edge:SetPoint("TOPLEFT", 0, 0)
    edge:SetPoint("TOPRIGHT", 0, 0)
    self.bar = bar

    -- the speaker: the portrait breaking out above the bar, the plate under it
    local port = self:BuildPortrait(bar)
    port:SetPoint("TOPLEFT", bar, "TOPLEFT", PAD, -PAD + RISE)
    port:SetFrameLevel(bar:GetFrameLevel() + 5)
    self.portrait = port
    local plate = CreateFrame("Frame", nil, bar)
    plate:SetPoint("TOPLEFT", port, "BOTTOMLEFT", 0, 1)
    plate:SetPoint("TOPRIGHT", port, "BOTTOMRIGHT", 0, 1)
    plate:SetHeight(PLATE_H)
    plate:SetFrameLevel(port:GetFrameLevel() + 3)
    UI.Fill(plate, "surface", "BACKGROUND"):SetAllPoints()
    UI.Border(plate, "gilt-line")
    plate.edge = UI.Fill(plate, "reaction-friendly", "ARTWORK")
    plate.edge:SetPoint("TOPLEFT")
    plate.edge:SetPoint("BOTTOMLEFT")
    plate.edge:SetWidth(3)
    plate.name = UI.Text(plate, "alert", "ink")
    plate.name:SetFont(T.type.alert.file, 20, "")
    plate.name:SetShadowOffset(0, -1)
    plate.name:SetPoint("TOPLEFT", S["space-5"], -S["space-3"])
    plate.name:SetPoint("RIGHT", -S["space-4"], 0)
    plate.name:SetJustifyH("LEFT")
    plate.name:SetWordWrap(false)
    plate.role = UI.Text(plate, "caption", "gilt-text")
    plate.role:SetPoint("TOPLEFT", plate.name, "BOTTOMLEFT", 0, -1)
    self.plate = plate

    -- you, at the right (the gossip and the greeting)
    local you = CreateFrame("Frame", nil, bar)
    you:SetSize(YOU, YOU + S["space-2"] + T.type.caption.lineHeight)
    you:SetPoint("BOTTOMRIGHT", -PAD_R, PAD)
    local youBox = CreateFrame("Frame", nil, you)
    youBox:SetSize(YOU, YOU)
    youBox:SetPoint("TOP")
    youBox:SetClipsChildren(true)
    UI.Fill(youBox, "surface-sunk", "BACKGROUND"):SetAllPoints()
    you.model = CreateFrame("PlayerModel", nil, youBox)
    you.model:SetAllPoints()
    UI.Border(youBox, "gilt-line")
    you.name = UI.Text(you, "caption", "ink-muted")
    you.name:SetPoint("BOTTOM")
    self.you = you

    UI.CloseButton(bar, function() self:Leave() end):SetPoint("TOPRIGHT", -S["space-4"], -S["space-4"])

    -- what is said and answered
    local talk = CreateFrame("Frame", nil, bar)
    talk:SetPoint("TOPLEFT", PAD + PORT_W + GAP, -PAD)
    self.talk = talk
    -- a quest's head: its title and level
    local qhead = CreateFrame("Frame", nil, talk)
    qhead:SetHeight(T.type["unit-name-lg"].lineHeight)
    qhead.glyph = qhead:CreateTexture(nil, "ARTWORK")
    qhead.glyph:SetSize(14, 14)
    qhead.glyph:SetPoint("LEFT")
    qhead.glyph:SetTexture(GLYPHS .. "questDots")
    qhead.glyph:SetVertexColor(UI.RGBA("gilt-text"))
    qhead.title = UI.Text(qhead, "unit-name-lg", "gilt-text")
    qhead.title:SetPoint("LEFT", qhead.glyph, "RIGHT", S["space-3"], 0)
    qhead.level = UI.Text(qhead, "caption", "ink-muted")
    qhead.level:SetPoint("RIGHT", -28, 0)
    self.qhead = qhead
    -- their line: a gilt quote mark, the text (scrolls when long)
    local speech = CreateFrame("Button", nil, talk)
    speech:SetScript("OnClick", function() self:RevealAll() end)
    speech.quote = UI.Text(speech, "alert", "gilt")
    speech.quote:SetFont(T.type.alert.file, 44, "")
    speech.quote:SetAlpha(0.8)
    speech.quote:SetPoint("TOPLEFT", 0, 6)
    speech.scroll = UI.ScrollArea(speech, S["space-3"])
    speech.scroll:SetPoint("TOPLEFT", 28, 0)
    speech.scroll:SetPoint("BOTTOMRIGHT", -(S["space-3"] + 3), 0)
    speech.text = UI.Text(speech.scroll.child, "body", "ink")
    speech.text:SetFont(T.type.body.file, 15.5, "")
    speech.text:SetSpacing(5)
    speech.text:SetJustifyH("LEFT")
    speech.text:SetWordWrap(true)
    speech.text:SetPoint("TOPLEFT")
    speech.skip = UI.Text(speech, "caption", "ink-faint")
    speech.skip:SetPoint("BOTTOMRIGHT", 0, -14)
    speech.skip:SetValue("Space  show it all")
    self.speech = speech
    -- what they ask (a quest's objectives)
    local ask = CreateFrame("Frame", nil, talk)
    UI.Fill(ask, "surface-sunk", "BACKGROUND"):SetAllPoints()
    local askEdge = UI.Fill(ask, "gilt-line", "ARTWORK")
    askEdge:SetPoint("TOPLEFT")
    askEdge:SetPoint("BOTTOMLEFT")
    askEdge:SetWidth(2)
    ask.head = UI.Text(ask, "header", "gilt-text")
    ask.head:SetPoint("TOPLEFT", S["space-5"], -S["space-4"])
    ask.head:SetValue("What they ask")
    ask.text = UI.Text(ask, "body", "ink")
    ask.text:SetPoint("TOPLEFT", ask.head, "BOTTOMLEFT", 0, -S["space-2"])
    ask.text:SetJustifyH("LEFT")
    ask.text:SetWordWrap(true)
    self.ask = ask
    -- the cards and what comes with them (money, experience)
    local cards = CreateFrame("Frame", nil, talk)
    cards.caption = UI.Text(cards, "caption", "ink-muted")
    cards.caption:SetPoint("TOPLEFT")
    cards.list = {}
    cards.gains = CreateFrame("Frame", nil, cards)
    cards.gains:SetSize(140, CARD_H)
    cards.money = UI.Money(cards.gains)
    cards.xp = UI.Text(cards.gains, "caption", "ink-muted")
    self.cards = cards
    -- the answers
    self.answers = {}

    -- keys: 1-9, Space, Enter; everything else goes on to the game
    bar:EnableKeyboard(true)
    if not InCombatLockdown() then bar:SetPropagateKeyboardInput(true) end
    bar:SetScript("OnKeyDown", function(f, key)
        if InCombatLockdown() then return end
        local handled = self:Key(key)
        f:SetPropagateKeyboardInput(not handled)
    end)
    -- typing the line in
    bar:SetScript("OnUpdate", function(_, elapsed) self:Type(elapsed) end)
end

--------------------------------------------------------------------------------
-- What is shown
--------------------------------------------------------------------------------

-- The speaker: portrait, name, role, friend or foe.
function M:DrawSpeaker()
    local unit = UnitExists("npc") and "npc" or nil
    local name = unit and UnitName(unit)
    self.plate.name:SetValue(plain(name) and name or "")
    -- the role: the tooltip's line under the name (Weapons Merchant), unless
    -- it's the level line
    local role
    local info = unit and C_TooltipInfo and C_TooltipInfo.GetUnit and call(C_TooltipInfo.GetUnit, unit)
    local line = info and info.lines and info.lines[2]
    local text = line and line.leftText
    if plain(text) and text ~= "" and not text:find("^" .. (LEVEL or "Level")) then role = text end
    self.plate.role:SetValue(role or "")
    local hostile = unit and UnitCanAttack("player", unit)
    self.plate.edge:SetColorTexture(UI.RGBA(hostile and "reaction-hostile" or "reaction-friendly"))
    local m = self.portrait.model
    -- a new speaker only: setting the unit again restarts the model
    local guid = unit and UnitGUID(unit)
    if unit and (not plain(guid) or guid ~= self.speakerGUID) then
        self.speakerGUID = plain(guid) and guid or nil
        self.talking = nil
        m:ClearModel()
        m:SetUnit(unit)
        m:SetPortraitZoom(ZOOM)
    end
    m:SetShown(unit ~= nil)
    m.canTalk = call(m.HasAnimation, m, ANIM_TALK) ~= false
end

-- The answers: { label, glyph | mark = { "!", token }, tag, act, off = why }.
function M:DrawAnswers(list, y, width)
    for i, a in ipairs(list) do
        local b = self.answers[i] or self:BuildAnswer(self.talk)
        self.answers[i] = b
        b:ClearAllPoints()
        b:SetPoint("TOPLEFT", 0, -y)
        b:SetWidth(width)
        local key = a.key or (i <= 9 and tostring(i) or "")
        b.key:SetKey(key)
        b.key:SetShown(key ~= "")
        if a.mark then
            b.glyph:Hide()
            b.mark:Show()
            b.mark:SetValue(a.mark[1])
            b.mark:SetColor(a.mark[2])
        else
            b.mark:Hide()
            b.glyph:Show()
            if type(a.glyph) == "number" then
                b.glyph:SetTexture(a.glyph)
                b.glyph:SetVertexColor(1, 1, 1)
            else
                b.glyph:SetTexture(GLYPHS .. (a.glyph or "chat"))
                b.glyph:SetVertexColor(UI.RGBA((a.leave or a.off) and "ink-muted" or "gilt-text"))
            end
        end
        b.text:SetValue(a.label or "")
        b.text:SetColor((a.off and "ink-faint") or (a.leave and "ink-muted") or "ink")
        b.text:SetWidth(math.min(UI.MeasureText("body", a.label or "") * 14 / 13 + 4, width - 200))
        b.tag:SetValue(a.tag and a.tag[1] or "")
        b.tag:SetColor(a.tag and a.tag[2] or "gilt-text")
        b.why:SetValue(a.off or "")
        b.off, b.act = a.off, a.act
        b:Lit(b:IsMouseOver())
        b:Show()
        y = y + ANS_H + 2
    end
    for i = #list + 1, #self.answers do self.answers[i]:Hide() end
    self.answerList = list
    return y
end

-- The cards: items to choose or receive, or to hand over.
function M:DrawCards(y, width, items, caption, gains)
    local cards = self.cards
    cards:ClearAllPoints()
    cards:SetPoint("TOPLEFT", 0, -y)
    cards:SetWidth(width)
    cards.caption:SetValue(caption or "")
    local top = (caption and caption ~= "") and (T.type.caption.lineHeight + S["space-3"]) or 0
    local perRow = math.max(1, math.floor((width - 140 + S["space-4"]) / (CARD_W + S["space-4"])))
    for i, it in ipairs(items) do
        local c = cards.list[i] or self:BuildCard(cards)
        cards.list[i] = c
        local row, col = math.floor((i - 1) / perRow), (i - 1) % perRow
        c:ClearAllPoints()
        c:SetPoint("TOPLEFT", col * (CARD_W + S["space-4"]), -(top + row * (CARD_H + S["space-4"])))
        c.slot.skin:SetItem({ icon = it.icon, count = it.count, quality = QUALITY[it.quality] })
        c.name:SetValue(it.name or "…")
        local q = QUALITY[it.quality]
        c.name:SetColor(q and ("quality-" .. q) or "ink")
        c.note:SetValue(it.note or "")
        c.note:SetColor(it.noteColor or "ink-muted")
        c.up:SetValue(it.upgrade and "▲ Upgrade" or "")
        c.kind, c.index, c.link = it.kind, it.index, it.link
        c.choosable, c.choose = it.choosable, it.choose
        c:SetOn(it.on)
        c:Show()
    end
    for i = #items + 1, #cards.list do cards.list[i]:Hide() end
    local rows = math.max(1, math.ceil(#items / perRow))
    -- money and experience beside the first row
    local g = cards.gains
    g:ClearAllPoints()
    g:SetPoint("TOPLEFT", math.min(#items, perRow) * (CARD_W + S["space-4"]), -top)
    cards.money:ClearAllPoints()
    cards.xp:ClearAllPoints()
    local gy = S["space-4"]
    if gains and gains.money and gains.money > 0 then
        cards.money:SetPoint("TOPLEFT", S["space-3"], -gy)
        cards.money:SetCopper(gains.money)
        cards.money:Show()
        gy = gy + 20
    else
        cards.money:Hide()
    end
    if gains and gains.xp and gains.xp > 0 then
        cards.xp:SetPoint("TOPLEFT", S["space-3"], -gy)
        cards.xp:SetValue(BreakUpLargeNumbers(gains.xp) .. " XP")
        cards.xp:Show()
    else
        cards.xp:Hide()
    end
    local h = (#items > 0 or (gains and (gains.money or 0) + (gains.xp or 0) > 0)) and (top + rows * CARD_H + (rows - 1) * S["space-4"]) or 0
    cards:SetHeight(math.max(1, h))
    cards:SetShown(h > 0)
    return h
end

-- A reward or required item from the quest frame's lists.
local function questItem(kind, i)
    local name, icon, count, quality, _, itemID = GetQuestItemInfo(kind, i)
    local link = GetQuestItemLink(kind, i)
    return { kind = kind, index = i, name = plain(name) and name or nil, icon = icon, count = (count or 0) > 1 and count or nil,
        quality = quality, itemID = itemID, link = plain(link) and link or nil }
end

-- The rewards: what to choose from, what comes anyway, money and experience.
function M:Rewards(choosing)
    local items = {}
    local choices = GetNumQuestChoices() or 0
    for i = 1, choices do
        local it = questItem("choice", i)
        it.upgrade = upgrade(it.link)
        if choosing and choices > 1 then
            it.choosable = true
            it.on = self.chosen == i
            it.choose = function(n) self.chosen = n; self:Draw() end
        end
        items[#items + 1] = it
    end
    for i = 1, GetNumQuestRewards() or 0 do
        local it = questItem("reward", i)
        it.note = "You receive this"
        items[#items + 1] = it
    end
    local caption
    if choices > 1 then caption = choosing and "Choose your reward" or "You may choose one" end
    return items, caption, { money = GetRewardMoney and GetRewardMoney() or 0, xp = GetRewardXP and GetRewardXP() or 0 }
end

-- What the conversation is now: gossip, greeting, detail, progress or reward.
function M:View()
    if self.questView and QuestFrame and QuestFrame:IsShown() then return self.questView end
    if GossipFrame and GossipFrame:IsShown() then return "gossip" end
    return nil
end

function M:Draw()
    local view = self:View()
    if not view then self.root:Hide() return end
    self.root:Show()
    self:DrawSpeaker()
    local gossipLike = view == "gossip" or view == "greeting"
    local you = self.you
    you:SetShown(gossipLike)
    if gossipLike then
        if not self.youSet then
            you.model:SetUnit("player")
            you.model:SetPortraitZoom(1)
            self.youSet = true
        end
        you.name:SetValue(UnitName("player") or "")
    end
    local width = BAR_W - PAD - PORT_W - GAP - PAD_R - (gossipLike and (YOU + GAP) or 0)
    self.talk:SetWidth(width)

    local text, answers, ask = "", {}, nil
    local items, caption, gains
    local qtitle, qlevel
    if view == "gossip" then
        text = call(C_GossipInfo.GetText) or ""
        local options = call(C_GossipInfo.GetOptions) or {}
        if GossipOptionSort then table.sort(options, GossipOptionSort) end
        for _, o in ipairs(options) do
            local icon = o.overrideIconID or o.icon
            answers[#answers + 1] = { label = o.name, glyph = OPTION_GLYPH[icon] or icon or "chat",
                act = function() C_GossipInfo.SelectOptionByIndex(o.orderIndex) end }
        end
        for _, q in ipairs(call(C_GossipInfo.GetActiveQuests) or {}) do
            answers[#answers + 1] = { label = q.title, mark = { "?", q.isComplete and "gilt-text" or "ink-faint" },
                tag = q.isComplete and { "Ready", "gilt-text" } or nil,
                act = function() C_GossipInfo.SelectActiveQuest(q.questID) end }
        end
        for _, q in ipairs(call(C_GossipInfo.GetAvailableQuests) or {}) do
            local daily = q.frequency and q.frequency > 0
            answers[#answers + 1] = { label = q.title, mark = { "!", (daily or q.repeatable) and "arcane" or (q.isTrivial and "ink-faint") or "gilt-text" },
                tag = daily and { "Daily", "arcane" } or q.repeatable and { "Repeatable", "arcane" } or nil,
                act = function() C_GossipInfo.SelectAvailableQuest(q.questID) end }
        end
        answers[#answers + 1] = { key = "Esc", label = "Goodbye", glyph = "door", leave = true, act = function() self:Leave() end }
    elseif view == "greeting" then
        text = GetGreetingText() or ""
        for i = 1, GetNumActiveQuests() or 0 do
            local title, done = GetActiveTitle(i)
            answers[#answers + 1] = { label = title, mark = { "?", done and "gilt-text" or "ink-faint" },
                tag = done and { "Ready", "gilt-text" } or nil, act = function() SelectActiveQuest(i) end }
        end
        for i = 1, GetNumAvailableQuests() or 0 do
            local trivial, frequency, repeatable = GetAvailableQuestInfo(i)
            local daily = frequency and frequency > 0
            answers[#answers + 1] = { label = GetAvailableTitle(i), mark = { "!", (daily or repeatable) and "arcane" or (trivial and "ink-faint") or "gilt-text" },
                tag = daily and { "Daily", "arcane" } or repeatable and { "Repeatable", "arcane" } or nil,
                act = function() SelectAvailableQuest(i) end }
        end
        answers[#answers + 1] = { key = "Esc", label = "Goodbye", glyph = "door", leave = true, act = function() self:Leave() end }
    elseif view == "detail" then
        qtitle = GetTitleText()
        local id = GetQuestID and GetQuestID()
        qlevel = id and C_QuestLog and C_QuestLog.GetQuestDifficultyLevel and call(C_QuestLog.GetQuestDifficultyLevel, id)
        text = GetQuestText() or ""
        ask = GetObjectiveText()
        items, caption, gains = self:Rewards(false)
        answers = {
            { label = "Accept", glyph = "check", act = function() QuestFrameAcceptButton:Click() end },
            { label = "Decline", glyph = "close", leave = true, act = function() QuestFrameDeclineButton:Click() end },
        }
    elseif view == "progress" then
        qtitle = GetTitleText()
        text = GetProgressText() or ""
        items = {}
        local short
        for i = 1, GetNumQuestItems() or 0 do
            local it = questItem("required", i)
            local need = select(3, GetQuestItemInfo("required", i)) or 0
            local have = it.itemID and C_Item.GetItemCount(it.itemID) or 0
            it.count = nil
            it.note = have .. " / " .. need
            it.noteColor = have < need and "ember-text" or "gilt-text"
            if have < need and not short then short = ("You need %d more %s"):format(need - have, it.name or "") end
            items[#items + 1] = it
        end
        local money = GetQuestMoneyToGet and GetQuestMoneyToGet() or 0
        if money > 0 and GetMoney() < money and not short then short = "You don't have enough money" end
        local can = IsQuestCompletable()
        local why = not can and (short or "Not done yet") or nil
        answers = {
            { label = "Hand them over", glyph = "check", off = why, act = function() QuestFrameCompleteButton:Click() end },
            { label = "I'll be back", glyph = "chat", leave = true, act = function() QuestFrameGoodbyeButton:Click() end },
        }
        if #items == 0 then answers[1].label = "Continue" end
        gains = { money = money }
    elseif view == "reward" then
        qtitle = GetTitleText()
        text = GetRewardText() or ""
        if (GetNumQuestChoices() or 0) == 1 then self.chosen = 1 end
        items, caption, gains = self:Rewards(true)
        local need = (GetNumQuestChoices() or 0) > 1 and not self.chosen
        answers = {
            { label = "Complete quest", glyph = "check", off = need and "Choose a reward first" or nil, act = function()
                if QuestInfoFrame then QuestInfoFrame.itemChoice = self.chosen or 0 end
                QuestFrameCompleteQuestButton:Click()
            end },
        }
    end

    -- lay it out, top to bottom
    local y = 0
    local qhead = self.qhead
    qhead:SetShown(qtitle ~= nil)
    if qtitle then
        qhead:ClearAllPoints()
        qhead:SetPoint("TOPLEFT", 0, 0)
        qhead:SetWidth(width)
        qhead.title:SetValue(qtitle)
        qhead.level:SetValue((plain(qlevel) and qlevel > 0) and ("Level " .. qlevel) or "")
        y = y + qhead:GetHeight() + S["space-5"]
    end
    -- the line
    local sp = self.speech
    sp:ClearAllPoints()
    sp:SetPoint("TOPLEFT", 0, -y)
    sp:SetWidth(width)
    sp.text:SetWidth(width - 28 - S["space-3"] - 3)
    sp.quote:SetValue("“")
    if text ~= self.fullText then
        self.fullText = text
        self.ends = charEnds(text)
        self.shown = (SuuUI.Motion.Reduced() or text == "") and #self.ends or 0
        self.typed = 0
        sp.scroll:SetVerticalScroll(0)
    end
    sp.text:SetValue(text)
    local th = sp.text:GetStringHeight()
    sp.scroll.child:SetHeight(th)
    local sh = math.max(T.type.body.lineHeight, math.min(th, SPEECH_MAX))
    sp:SetHeight(sh)
    self:ShowTyped()
    y = y + sh + S["space-5"]
    -- what they ask
    local a = self.ask
    a:SetShown(ask ~= nil and ask ~= "")
    if a:IsShown() then
        a:ClearAllPoints()
        a:SetPoint("TOPLEFT", 0, -y)
        a:SetWidth(width)
        a.text:SetWidth(width - 2 * S["space-5"])
        a.text:SetValue(ask)
        local h = S["space-4"] + T.type.header.lineHeight + S["space-2"] + a.text:GetStringHeight() + S["space-4"]
        a:SetHeight(h)
        y = y + h + S["space-5"]
    end
    -- the cards
    local ch = self:DrawCards(y, width, items or {}, caption, gains)
    if ch > 0 then y = y + ch + S["space-5"] end
    -- the answers
    y = self:DrawAnswers(answers, y, width)
    self.talk:SetHeight(math.max(1, y))

    local speaker = PORT_H + PLATE_H - RISE
    self.bar:SetHeight(math.max(speaker, y, gossipLike and (YOU + T.type.caption.lineHeight) or 0) + 2 * PAD)
end

--------------------------------------------------------------------------------
-- The line, typing in
--------------------------------------------------------------------------------

function M:ShowTyped()
    local ends, n = self.ends or {}, self.shown or 0
    local sp = self.speech
    local full = n >= #ends
    if full then
        sp.text:SetText(self.fullText or "")
    else
        sp.text:SetText((self.fullText or ""):sub(1, ends[n] or 0))
    end
    sp.skip:SetShown(not full)
    local m = self.portrait.model
    local talking = not full
    if m.canTalk and talking ~= self.talking then
        self.talking = talking
        m:SetAnimation(talking and ANIM_TALK or ANIM_IDLE)
    end
end

function M:Type(elapsed)
    local ends = self.ends
    if not ends or (self.shown or 0) >= #ends then return end
    self.typed = (self.typed or 0) + elapsed * CPS
    local n = math.min(#ends, math.floor(self.typed))
    if n ~= self.shown then
        self.shown = n
        self:ShowTyped()
    end
end

function M:RevealAll()
    if not self.ends then return false end
    if (self.shown or 0) >= #self.ends then return false end
    self.shown = #self.ends
    self:ShowTyped()
    return true
end

--------------------------------------------------------------------------------
-- Keys and leaving
--------------------------------------------------------------------------------

function M:Key(key)
    local list = self.answerList or {}
    if key == "SPACE" then return self:RevealAll() end
    local n = tonumber(key)
    if n and n >= 1 and n <= 9 then
        local a = list[n]
        if a and a.key ~= "Esc" then
            if not a.off and a.act then PlaySound(SOUNDKIT.IG_QUEST_LIST_SELECT); a.act() end
            return true
        end
        return false
    end
    if key == "ENTER" then
        local view = self:View()
        if view == "detail" or view == "progress" or view == "reward" then
            local a = list[1]
            if a and not a.off and a.act then a.act() end
            return true
        end
    end
    return false
end

-- Goodbye: the game's frames close, and the conversation with them.
function M:Leave()
    if QuestFrame and QuestFrame:IsShown() then HideUIPanel(QuestFrame) end
    if GossipFrame and GossipFrame:IsShown() then HideUIPanel(GossipFrame) end
    self.root:Hide()
end

--------------------------------------------------------------------------------
-- With the game's frames
--------------------------------------------------------------------------------

function M:PutAway(frame)
    if not self:IsEnabled() then return end
    self.placing = true
    frame:SetAlpha(0)
    frame:ClearAllPoints()
    frame:SetPoint("TOPLEFT", UIParent, "TOPRIGHT", 5000, 0)
    self.placing = false
end

-- A game frame out of sight whenever it shows or is placed.
function M:Away(frame)
    hooksecurefunc(frame, "SetPoint", function() if not self.placing then C_Timer.After(0, function() self:PutAway(frame) end) end end)
    hooksecurefunc(frame, "SetAlpha", function(_, a) if not self.placing and a ~= 0 then C_Timer.After(0, function() self:PutAway(frame) end) end end)
    frame:HookScript("OnShow", function()
        if not self:IsEnabled() then return end
        self:PutAway(frame)
        C_Timer.After(0, function() self:PutAway(frame) end)
    end)
    frame:HookScript("OnHide", function()
        -- the conversation over: the next one starts fresh
        if not ((GossipFrame and GossipFrame:IsShown()) or (QuestFrame and QuestFrame:IsShown())) then
            self.speakerGUID, self.questView = nil, nil
        end
        self:QueueDraw()
    end)
end

function M:QueueDraw()
    if self.queued then return end
    self.queued = true
    C_Timer.After(0, function()
        self.queued = nil
        if self:IsEnabled() then self:Draw() end
    end)
end

function M:Hook()
    if self.hooked then return end
    self.hooked = true
    local g, q = _G.GossipFrame, _G.QuestFrame
    if g then
        self:Away(g)
        if g.Update then hooksecurefunc(g, "Update", function() self:QueueDraw() end) end
        g:HookScript("OnShow", function() self:QueueDraw() end)
    end
    if q then
        self:Away(q)
        local panels = { greeting = _G.QuestFrameGreetingPanel, detail = _G.QuestFrameDetailPanel,
                         progress = _G.QuestFrameProgressPanel, reward = _G.QuestFrameRewardPanel }
        for view, panel in pairs(panels) do
            if panel then panel:HookScript("OnShow", function()
                self.questView = view
                if view == "reward" then self.chosen = nil end
                self:QueueDraw()
            end) end
        end
    end
end

function M:OnEnable()
    if not self.root then self:Build() end
    self:Hook()
    for _, e in ipairs({ "QUEST_ITEM_UPDATE", "QUEST_LOG_UPDATE", "GET_ITEM_INFO_RECEIVED", "BAG_UPDATE_DELAYED" }) do
        self:OnGameEvent(e, function() if self.root:IsShown() then self:QueueDraw() end end)
    end
    -- in combat the keys stay the game's (a frame's key handling can't change then)
    self:OnGameEvent("PLAYER_REGEN_DISABLED", function() if self.bar then self.bar:EnableKeyboard(false) end end)
    self:OnGameEvent("PLAYER_REGEN_ENABLED", function()
        if self.bar then
            self.bar:EnableKeyboard(true)
            self.bar:SetPropagateKeyboardInput(true)
        end
    end)
end

function M:OnDisable()
    if self.root then self.root:Hide() end
end
