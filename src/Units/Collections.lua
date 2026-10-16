-- Units/Collections.lua
-- SuuUI's own collections window (plan 3.6; asked 2026-10-16: our own
-- window instead of the restyle; design: direction A, "Stage", on the board
-- "Collections · own window"). The game's journal stays closed. Probed
-- (/suu probe collown, colltiles): every mount, toy and appearance can be
-- read, the ones you lack too; SuuUI draws the models itself (a ModelScene
-- framed by the mount's own scene, DressUpModels framed by the appearance
-- cameras); summoning and toys go through SuuUI's own secure buttons.
-- Where something comes from is SuuUI's generated data
-- (SuuUI.CollectionSources(): the game gives no source for mounts, only the
-- kind for appearances, and won't list the toys you lack).
-- A built-in module written against the public API only.

local UI, T = SuuUI.UI, SuuUI.Tokens
local S = T.space

local M = SuuUI.RegisterModule({
    id = "collections",
    name = "Collections",
    description = "SuuUI's collections window: mounts, toys and appearances on a model stage, what you lack and where to get it.",
    api = "0.17",
    reloadToToggle = true,
    defaults = {},
})

local isSecret = issecretvalue or function() return false end
local function call(fn, ...)
    if type(fn) ~= "function" then return nil end
    local ok, a, b, c, d, e, f, g, h, i, j, k, l, m = pcall(fn, ...)
    if ok then return a, b, c, d, e, f, g, h, i, j, k, l, m end
end
local function plain(v) return v ~= nil and not isSecret(v) end

--------------------------------------------------------------------------------
-- Where something comes from: the best source as one line, all of it as a
-- card (design: vendor, quest, world drop, drop, object, container,
-- crafted, the game's own text, the item that teaches it; then the game's
-- source kind, then "Source unknown")
--------------------------------------------------------------------------------

local WORLD = 12
local MAX_SHOWN = 3

local function data() return SuuUI.CollectionSources() or {} end

-- "Name|Zone|Level|Faction" -> name, zone, level, faction
local function npc(id)
    local s = data().npc and data().npc[id]
    if not s then return nil end
    local name, zone, level, faction = s:match("^(.-)|(.-)|(.-)|(.*)$")
    return name, zone ~= "" and zone or nil, level ~= "" and level or nil, faction ~= "" and faction or nil
end
local function object(id)
    local s = data().obj and data().obj[id]
    if not s then return nil end
    local name, zone = s:match("^(.-)|(.*)$")
    return name, zone ~= "" and zone or nil
end
local function itemName(id)
    local name = C_Item and C_Item.GetItemNameByID and call(C_Item.GetItemNameByID, id)
    return plain(name) and name or nil
end
local function questTitle(id)
    local t = C_QuestLog and C_QuestLog.GetTitleForQuestID and call(C_QuestLog.GetTitleForQuestID, id)
    return plain(t) and t ~= "" and t or nil
end

local function place(name, zone) return zone and (name .. ", " .. zone) or name end
local function more(list) return (#list > 1) and (" +" .. (#list - 1)) or "" end

-- The game's own word for a source kind (its numbers: mounts use the pet
-- journal's, appearances the transmog ones).
local function kindName(kind, number)
    if not number or number < 0 then return nil end
    local g = kind == "appearance" and _G["TRANSMOG_SOURCE_" .. number] or _G["BATTLE_PET_SOURCE_" .. (number + 1)]
    return type(g) == "string" and g ~= "" and g or nil
end

-- src: a CollectionSources entry (or nil); kind/number: the game's source
-- kind as the fallback. -> "Vendor · Name, Zone +1" or nil
function M:SourceLine(src, kind, number)
    if src then
        if src.v and src.v[1] then
            local name, zone = npc(src.v[1])
            if name then return "Vendor · " .. place(name, zone) .. more(src.v) end
        end
        if src.q and src.q[1] then
            local title = questTitle(src.q[1])
            return "Quest" .. (title and (" · " .. title) or "") .. more(src.q)
        end
        if (src.dn or 0) > WORLD then return "World drop" end
        if src.d and src.d[1] then
            local name, zone, level = npc(src.d[1])
            if name then
                local extra = (src.dn and src.dn > 1) and (" +" .. (src.dn - 1)) or more(src.d)
                return "Drop · " .. place(name, zone) .. (level and (" · " .. level) or "") .. extra
            end
        end
        if src.o and src.o[1] then
            local name, zone = object(src.o[1])
            if name then return "Found in · " .. place(name, zone) .. more(src.o) end
        end
        if src.c and src.c[1] then return "Inside · " .. (itemName(src.c[1]) or "a container") end
        if src.p then return "Crafted · " .. src.p end
        if src.x then return src.x end
        if src.i then return "Taught by · " .. (itemName(src.i) or "an item") end
    end
    local word = kindName(kind, number)
    return word and word or "Source unknown"
end

-- The full card: { { title, lines = { … } }, … } (empty: nothing known).
function M:SourceCard(src, kind, number)
    local card = {}
    local function section(title, lines) if lines[1] then card[#card + 1] = { title = title, lines = lines } end end
    if src then
        local lines = {}
        for _, id in ipairs(src.v or {}) do
            local name, zone, _, faction = npc(id)
            if name then lines[#lines + 1] = place(name, zone) .. (faction and (" (" .. faction .. ")") or "") end
        end
        section("Sold by", lines)
        lines = {}
        for _, id in ipairs(src.q or {}) do lines[#lines + 1] = questTitle(id) or ("Quest " .. id) end
        section("Quest", lines)
        lines = {}
        if (src.dn or 0) > WORLD then
            section("World drop", { ("Dropped by %d creatures across the world"):format(src.dn) })
        else
            for _, id in ipairs(src.d or {}) do
                local name, zone, level = npc(id)
                if name then lines[#lines + 1] = place(name, zone) .. (level and (" · level " .. level) or "") end
            end
            if src.dn and src.dn > #(src.d or {}) then lines[#lines + 1] = ("and %d more"):format(src.dn - #(src.d or {})) end
            section("Dropped by", lines)
        end
        lines = {}
        for _, id in ipairs(src.o or {}) do
            local name, zone = object(id)
            if name then lines[#lines + 1] = place(name, zone) end
        end
        section("Found in", lines)
        lines = {}
        for _, id in ipairs(src.c or {}) do lines[#lines + 1] = itemName(id) or ("Item " .. id) end
        section("Inside", lines)
        if src.p then section("Crafted by", { src.p }) end
        if src.x then section("In the game", { src.x }) end
        if src.i and not card[1] then section("Taught by", { itemName(src.i) or ("Item " .. src.i) }) end
    end
    if not card[1] then
        local word = kindName(kind, number)
        if word then card[1] = { title = word, lines = { "Nothing more is known." } } end
    end
    return card
end

--------------------------------------------------------------------------------
-- What there is: mounts, toys, appearances, the ones you lack too
--------------------------------------------------------------------------------

-- Every mount this character can see (the rest: the other faction's, or no
-- model in Forever's data: probed, 49 of 139), favourites and yours first.
function M:Mounts()
    local MJ = C_MountJournal
    local out = {}
    for _, id in ipairs(MJ and call(MJ.GetMountIDs) or {}) do
        local name, spellID, icon, active, usable, sourceType, favourite, _, faction, hidden, collected = call(MJ.GetMountInfoByID, id)
        if name and not hidden then
            local display, _, _, isSelf, _, scene = call(MJ.GetMountInfoExtraByID, id)
            out[#out + 1] = {
                kind = "mount", id = id, name = name, spellID = spellID, icon = icon, active = active, usable = usable,
                favourite = favourite, collected = collected, sourceType = sourceType, faction = faction,
                display = display, scene = scene, isSelf = isSelf, source = data().mount and data().mount[id],
                learned = self:Learned("mount", id, collected),
            }
        end
    end
    table.sort(out, function(a, b)
        if a.collected ~= b.collected then return a.collected and true or false end
        if a.favourite ~= b.favourite then return a.favourite and true or false end
        return a.name < b.name
    end)
    return out
end

-- Every toy of Forever (from the client's own list: the game won't list the
-- ones you lack), yours first.
function M:Toys()
    local TB = C_ToyBox
    local out = {}
    for _, itemID in ipairs(data().toys or {}) do
        local _, name, icon, favourite = call(TB and TB.GetToyInfo, itemID)
        name = plain(name) and name or itemName(itemID) or ("Toy " .. itemID)
        local has = call(PlayerHasToy, itemID) and true or false
        out[#out + 1] = {
            kind = "toy", id = itemID, itemID = itemID, name = name, icon = icon or (C_Item and call(C_Item.GetItemIconByID, itemID)),
            favourite = favourite, collected = has, source = data().toy and data().toy[itemID],
            learned = self:Learned("toy", itemID, has),
        }
    end
    table.sort(out, function(a, b)
        if a.collected ~= b.collected then return a.collected end
        return a.name < b.name
    end)
    return out
end

-- The paper doll's slots (the game's armor categories 1-11; weapons by kind).
M.SLOTS = {
    { slot = "HEADSLOT", label = "Head", category = 1 }, { slot = "SHOULDERSLOT", label = "Shoulder", category = 2 },
    { slot = "BACKSLOT", label = "Back", category = 3 }, { slot = "CHESTSLOT", label = "Chest", category = 4 },
    { slot = "SHIRTSLOT", label = "Shirt", category = 5 }, { slot = "TABARDSLOT", label = "Tabard", category = 6 },
    { slot = "WRISTSLOT", label = "Wrist", category = 7 }, { slot = "HANDSSLOT", label = "Hands", category = 8 },
    { slot = "WAISTSLOT", label = "Waist", category = 9 }, { slot = "LEGSSLOT", label = "Legs", category = 10 },
    { slot = "FEETSLOT", label = "Feet", category = 11 },
    { slot = "MAINHANDSLOT", label = "Main hand", weapon = "main" }, { slot = "SECONDARYHANDSLOT", label = "Off hand", weapon = "off" },
    { slot = "RANGEDSLOT", label = "Ranged", weapon = "ranged" },
}

-- The weapon kinds this class can use for a hand (the game names only those).
function M:WeaponKinds(hand)
    local TC = C_TransmogCollection
    local out = {}
    for cat = 12, 30 do
        local name, isWeapon, _, canMain, canOff, canRanged = call(TC and TC.GetCategoryInfo, cat)
        if name and isWeapon and ((hand == "main" and canMain) or (hand == "off" and canOff) or (hand == "ranged" and canRanged)) then
            out[#out + 1] = { category = cat, name = name }
        end
    end
    return out
end

-- The slot's transmog location (the game asks for armor with it).
local function location(slot)
    if not (TransmogUtil and TransmogUtil.GetTransmogLocation and Enum.TransmogType) then return nil end
    local loc = call(TransmogUtil.GetTransmogLocation, slot, Enum.TransmogType.Appearance, false)
    return loc and loc.GetData and loc:GetData() or nil
end

-- What you wear in a slot: its appearance (visual) ID.
function M:Worn(slot)
    local id = call(GetInventorySlotInfo, slot)
    local itemID = id and call(GetInventoryItemID, "player", id)
    if not itemID then return nil end
    local visual = call(C_TransmogCollection.GetItemInfo, itemID)
    return visual
end

-- A category's appearances (yours first), each with its first source's item
-- and that item's source data.
function M:Appearances(category, slot)
    local TC = C_TransmogCollection
    local worn = slot and self:Worn(slot)
    local out = {}
    for _, a in ipairs(call(TC.GetCategoryAppearances, category, slot and location(slot)) or {}) do
        if not a.isHideVisual then
            local sources = call(TC.GetAppearanceSources, a.visualID) or {}
            local first
            for _, s in ipairs(sources) do
                if s.isCollected then first = s break end
                first = first or s
            end
            if first then
                out[#out + 1] = {
                    kind = "appearance", id = a.visualID, visualID = a.visualID, sourceID = first.sourceID, itemID = first.itemID,
                    name = plain(first.name) and first.name or nil, collected = a.isCollected, favourite = a.isFavorite,
                    worn = worn == a.visualID, sourceType = first.sourceType,
                    source = data().item and data().item[first.itemID],
                    camera = call(TC.GetAppearanceCameraID, a.visualID),
                }
            end
        end
    end
    table.sort(out, function(a, b)
        if a.worn ~= b.worn then return a.worn end
        if a.collected ~= b.collected then return a.collected end
        return a.visualID < b.visualID
    end)
    return out
end

--------------------------------------------------------------------------------
-- Recently collected: the game keeps no dates, so SuuUI notes the day it
-- first sees something yours (what you had before SuuUI: 0, "Before SuuUI")
--------------------------------------------------------------------------------

function M:Learned(kind, id, collected)
    if not collected then return nil end
    local d = self:CharData()
    d.learned = d.learned or {}
    local list = d.learned[kind]
    if not list then
        -- the first look at this kind: everything yours is from before SuuUI
        list = { first = time() }
        d.learned[kind] = list
    end
    if list[id] == nil then
        list[id] = (time() - list.first < 5) and 0 or time()
    end
    return list[id]
end

-- what you collected last (any kind), for the foot
function M:NoteLast(name, at)
    if not (name and at and at > 0) then return end
    local d = self:CharData()
    if not d.last or (d.last.at or 0) < at then d.last = { name = name, at = at } end
end

--------------------------------------------------------------------------------
-- The window (design CollectionsWindow, direction A "Stage"): the stage on
-- top, the strip's tools, the strip; the overview in the foot. This step:
-- Mounts (Toys and Appearances follow).
--------------------------------------------------------------------------------

local WIDTH, HEIGHT = 960, 700
local CELL, COLS, ROWS = 40, 18, 2
local CARD_W, SHADE_W = 270, 340
-- the model stands centred on the whole stage, its feet above the turn and
-- zoom buttons (seen in game: right of the card it sat off centre, legs cut)
local FLOOR = 40
local ZOOM_OUT = 1.2
local TOOLS_H = 30
local STRIP_H = CELL * ROWS + S["space-5"] + 8
local MEDIA = "Interface\\AddOns\\SuuUI\\Media\\Textures\\"
local GLYPHS = MEDIA .. "Glyphs\\"
local SOFT = MEDIA .. "CircleSoft.tga"
local DISC = MEDIA .. "CircleFill.tga"

local function day(at)
    if not at then return nil end
    if at == 0 then return "before SuuUI" end
    return date("%d %b", at):gsub("^0", "")
end

local function status(e)
    if not e.collected then return "Not collected", "ink-faint" end
    local when = day(e.learned)
    return "Collected" .. (when and (" · " .. when) or ""), "gilt-text"
end

-- A small round button (the stage's star, turn and zoom): a disc, a glyph.
local function roundButton(parent, glyph, tip, onClick)
    local b = CreateFrame("Button", nil, parent)
    b:SetSize(26, 26)
    b.disc = b:CreateTexture(nil, "BACKGROUND")
    b.disc:SetTexture(DISC)
    b.disc:SetAllPoints()
    b.disc:SetVertexColor(UI.RGBA("surface-raised"))
    b.glyph = b:CreateTexture(nil, "ARTWORK")
    b.glyph:SetTexture(GLYPHS .. glyph .. ".tga")
    b.glyph:SetSize(12, 12)
    b.glyph:SetPoint("CENTER")
    b.glyph:SetVertexColor(UI.RGBA("ink-muted"))
    b.on = false
    function b:Draw(hover)
        self.glyph:SetVertexColor(UI.RGBA(self.on and "gilt" or hover and "ink" or "ink-muted"))
    end
    b:SetScript("OnEnter", function(self) self:Draw(true); if tip then UI.ShowTooltip(self, { title = type(tip) == "function" and tip(self) or tip }) end end)
    b:SetScript("OnLeave", function(self) self:Draw(false); UI.HideTooltip() end)
    b:SetScript("OnClick", onClick)
    return b
end

-- The stage's art, under everything (design: a gradient base, the key
-- light, a floor band, a floor glow and a contact shadow, four vignette
-- edges, a gilt-faint frame; the card's shade strip at the left).
local function stageArt(stage)
    local base = stage:CreateTexture(nil, "BACKGROUND", nil, -8)
    base:SetAllPoints()
    base:SetColorTexture(1, 1, 1, 1)
    base:SetGradient("VERTICAL", CreateColor(0.051, 0.043, 0.035, 1), CreateColor(0.09, 0.078, 0.059, 1))
    local light = stage:CreateTexture(nil, "BACKGROUND", nil, -7)
    light:SetTexture(SOFT)
    light:SetPoint("TOPLEFT", stage, "TOPLEFT", 120, 120)
    light:SetPoint("BOTTOMRIGHT", stage, "TOPRIGHT", -120, -260)
    stage.light = light
    local floor = stage:CreateTexture(nil, "BACKGROUND", nil, -6)
    floor:SetColorTexture(1, 1, 1, 1)
    floor:SetGradient("VERTICAL", CreateColor(0, 0, 0, 0.45), CreateColor(0, 0, 0, 0))
    floor:SetPoint("BOTTOMLEFT")
    floor:SetPoint("BOTTOMRIGHT")
    floor:SetHeight(130)
    local pool = stage:CreateTexture(nil, "BACKGROUND", nil, -5)
    pool:SetTexture(SOFT)
    pool:SetSize(420, 90)
    pool:SetPoint("BOTTOM", stage, "BOTTOM", 0, FLOOR - 12)
    stage.pool = pool
    local shadow = stage:CreateTexture(nil, "BACKGROUND", nil, -4)
    shadow:SetTexture(SOFT)
    shadow:SetVertexColor(0, 0, 0, 0.7)
    shadow:SetSize(260, 36)
    shadow:SetPoint("BOTTOM", stage, "BOTTOM", 0, FLOOR + 4)
    -- the vignette: four edges darkening inward
    local function edge(point, horizontal, size, fromA, toA)
        local t = stage:CreateTexture(nil, "BORDER", nil, 1)
        t:SetColorTexture(1, 1, 1, 1)
        t:SetGradient(horizontal and "HORIZONTAL" or "VERTICAL", CreateColor(0, 0, 0, fromA), CreateColor(0, 0, 0, toA))
        t:SetPoint(point)
        if horizontal then t:SetPoint(point == "LEFT" and "TOPLEFT" or "TOPRIGHT"); t:SetPoint(point == "LEFT" and "BOTTOMLEFT" or "BOTTOMRIGHT"); t:SetWidth(size)
        else t:SetPoint(point == "TOP" and "TOPLEFT" or "BOTTOMLEFT"); t:SetPoint(point == "TOP" and "TOPRIGHT" or "BOTTOMRIGHT"); t:SetHeight(size) end
    end
    edge("LEFT", true, 60, 0.5, 0)
    edge("RIGHT", true, 60, 0, 0.5)
    edge("TOP", false, 50, 0, 0.45)
    edge("BOTTOM", false, 50, 0.45, 0)
    -- the card's shade strip
    local shade = stage:CreateTexture(nil, "BORDER", nil, 2)
    shade:SetColorTexture(1, 1, 1, 1)
    shade:SetGradient("HORIZONTAL", CreateColor(0, 0, 0, 0.65), CreateColor(0, 0, 0, 0))
    shade:SetPoint("TOPLEFT")
    shade:SetPoint("BOTTOMLEFT")
    shade:SetWidth(SHADE_W)
    UI.Border(stage, "gilt-faint")
end

-- The stage's tint: a faint key light and floor glow (the soft disc is
-- solid over most of its middle, so at the design's 30% the light read as
-- a yellow lamp: seen in game).
local LIGHT_A, POOL_A = 0.09, 0.08
local function tintStage(stage, token)
    local r, g, b = UI.RGBA(token)
    stage.light:SetVertexColor(r, g, b)
    stage.light:SetAlpha(LIGHT_A)
    stage.pool:SetVertexColor(r, g, b)
    stage.pool:SetAlpha(POOL_A)
end

--------------------------------------------------------------------------------
-- The card on the stage: name, status, a rule, the full source card
--------------------------------------------------------------------------------

local function buildCard(stage)
    local c = CreateFrame("Frame", nil, stage)
    c:SetPoint("TOPLEFT", S["space-6"], -S["space-6"])
    c:SetPoint("BOTTOMLEFT", S["space-6"], 52)
    c:SetWidth(CARD_W)
    c:SetFrameLevel(stage:GetFrameLevel() + 10)
    c.name = UI.Text(c, "alert", "ink")
    c.name:SetPoint("TOPLEFT")
    c.name:SetWidth(CARD_W)
    c.name:SetJustifyH("LEFT")
    c.name:SetWordWrap(true)
    c.status = UI.Text(c, "caption", "gilt-text")
    c.status:SetPoint("TOPLEFT", c.name, "BOTTOMLEFT", 0, -S["space-3"])
    c.extra = UI.Text(c, "caption", "arcane")
    c.extra:SetPoint("LEFT", c.status, "RIGHT", S["space-4"], 0)
    c.rule = UI.Hairline(c, "gilt-line", "out")
    c.rule:SetPoint("TOPLEFT", c.status, "BOTTOMLEFT", 0, -S["space-4"])
    c.rule:SetWidth(CARD_W)
    c.texts = {}
    return c
end

function M:DrawCard(c, e, extra)
    c.name:SetValue(e.name or "")
    local text, color = status(e)
    c.status:SetValue(text)
    c.status:SetColor(color)
    c.extra:SetValue(extra or "")
    for _, t in ipairs(c.texts) do t:Hide() end
    local card = self:SourceCard(e.source, e.kind == "appearance" and "appearance" or "mount", e.sourceType)
    if not card[1] then card = { { title = "Source unknown", lines = {} } } end
    local n, prev = 0, c.rule
    local function text(style, color, indent, gap)
        n = n + 1
        local t = c.texts[n]
        if not t then
            t = UI.Text(c, style, color)
            t:SetJustifyH("LEFT")
            t:SetWordWrap(true)
            c.texts[n] = t
        end
        t:SetStyle(style)
        t:SetColor(color)
        t:ClearAllPoints()
        t:SetPoint("TOPLEFT", prev, "BOTTOMLEFT", indent - (prev.suuIndent or 0), -gap)
        t:SetWidth(CARD_W - indent)
        t.suuIndent = indent
        t:Show()
        prev = t
        return t
    end
    for i, section in ipairs(card) do
        text("micro", "gilt-text", 0, i == 1 and S["space-4"] or S["space-5"]):SetValue(section.title)
        for _, line in ipairs(section.lines) do text("body", "ink", 15, S["space-2"]):SetValue(line) end
    end
end

--------------------------------------------------------------------------------
-- The strip: 40px cells, 2 rows of 18 a page
--------------------------------------------------------------------------------

local function buildCell(parent, owner)
    local b = CreateFrame("Button", nil, parent)
    b:SetSize(CELL, CELL)
    UI.Fill(b, "surface-sunk", "BACKGROUND"):SetAllPoints()
    b.icon = b:CreateTexture(nil, "ARTWORK")
    b.icon:SetPoint("TOPLEFT", 1, -1)
    b.icon:SetPoint("BOTTOMRIGHT", -1, 1)
    b.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    b.edge = UI.Border(b, "gilt-hairline", { layer = "OVERLAY" })
    b.star = b:CreateTexture(nil, "OVERLAY", nil, 2)
    b.star:SetTexture(GLYPHS .. "star.tga")
    b.star:SetSize(11, 11)
    b.star:SetPoint("TOPRIGHT", -1, -1)
    b.star:SetVertexColor(UI.RGBA("gilt-text"))
    b.new = UI.Diamond(b, 6, "ink", "OVERLAY", 3)
    b.new:SetPoint("CENTER", b, "TOPLEFT", 1, -1)
    b.jewel = UI.Diamond(b, 5, "gilt", "OVERLAY", 3)
    b.jewel:SetPoint("CENTER", b, "BOTTOM", 0, -4)
    b:SetScript("OnEnter", function(self)
        self.hover = true
        owner:DrawCell(self)
        local e = self.entry
        if not e then return end
        UI.ShowTooltip(self, { title = e.name, subtitle = e.collected and (status(e)) or nil,
            description = owner:SourceLine(e.source, e.kind == "appearance" and "appearance" or "mount", e.sourceType) })
    end)
    b:SetScript("OnLeave", function(self) self.hover = false; owner:DrawCell(self); UI.HideTooltip() end)
    b:SetScript("OnClick", function(self) owner:Choose(self.entry) end)
    b:EnableMouseWheel(true)
    b:SetScript("OnMouseWheel", function(_, delta) owner:Page(-delta) end)
    return b
end

function M:DrawCell(b)
    local e = b.entry
    if not e then b:Hide() return end
    b.icon:SetTexture(e.icon)
    local missing = not e.collected
    b.icon:SetDesaturated(missing)
    local v = missing and (b.hover and 0.8 or 0.55) or 1
    b.icon:SetVertexColor(v, v, v)
    local chosen = self.chosen and self.chosen.id == e.id
    b.edge:SetColor((chosen or b.hover) and "gilt" or missing and "gilt-faint" or "gilt-hairline")
    b.star:SetShown(e.favourite and true or false)
    b.new:SetShown(e.learned and e.learned > 0 and time() - e.learned < 7 * 86400 or false)
    b.jewel:SetShown(chosen)
    b:Show()
end

--------------------------------------------------------------------------------
-- Building it
--------------------------------------------------------------------------------

function M:Build()
    local w = UI.WindowFrame(SuuUI.Root, { name = "SuuUICollectionsWindow", title = "Collections", width = WIDTH, height = HEIGHT,
        footer = true, onClose = function(win) win:Hide() end,
        tabs = {
            { key = "mounts", label = "Mounts" },
            { key = "pets", label = "Pets", disabled = true, reason = "No pets on Forever yet" },
            { key = "toys", label = "Toys", disabled = true, reason = "Comes in the next step of SuuUI's collections." },
            { key = "heirlooms", label = "Heirlooms", disabled = true, reason = "No heirlooms on Forever yet" },
            { key = "wardrobe", label = "Appearances", disabled = true, reason = "Comes in the next step of SuuUI's collections." },
        },
        onTab = function(key) self.tab = key; self:Refresh() end })
    w:SetPoint("CENTER", UIParent, "CENTER", 0, 30)
    w:Hide()
    w.scroll:Hide()
    w:HookScript("OnShow", function() self:Refresh() end)
    self.window = w
    local body = w.body

    -- the strip at the foot of the body, its tools above it, the stage on top
    local strip = CreateFrame("Frame", nil, body)
    strip:SetPoint("BOTTOMLEFT")
    strip:SetPoint("BOTTOMRIGHT")
    strip:SetHeight(STRIP_H)
    strip:EnableMouseWheel(true)
    strip:SetScript("OnMouseWheel", function(_, delta) self:Page(-delta) end)
    self.strip = strip
    strip.prev = UI.Button(strip, { icon = "chevronLeft", width = 30, onClick = function() self:Page(-1) end })
    strip.prev:SetPoint("LEFT", 0, S["space-2"])
    strip.next = UI.Button(strip, { icon = "chevronRight", width = 30, onClick = function() self:Page(1) end })
    strip.next:SetPoint("RIGHT", 0, S["space-2"] + 8)
    strip.pageText = UI.Text(strip, "micro", "ink-muted")
    strip.pageText:SetPoint("TOP", strip.next, "BOTTOM", 0, -S["space-2"])
    strip.grid = CreateFrame("Frame", nil, strip)
    strip.grid:SetPoint("TOPLEFT", strip, "TOPLEFT", 30 + S["space-5"], 0)
    strip.grid:SetPoint("BOTTOMRIGHT", strip, "BOTTOMRIGHT", -(30 + S["space-5"]), 0)
    strip.cells = {}
    for i = 1, COLS * ROWS do strip.cells[i] = buildCell(strip.grid, self) end
    strip.empty = UI.Text(strip, "body", "ink-muted")
    strip.empty:SetPoint("CENTER")
    strip.grid:HookScript("OnSizeChanged", function() self:LayoutCells() end)

    local tools = CreateFrame("Frame", nil, body)
    tools:SetPoint("BOTTOMLEFT", strip, "TOPLEFT", 0, S["space-5"])
    tools:SetPoint("BOTTOMRIGHT", strip, "TOPRIGHT", 0, S["space-5"])
    tools:SetHeight(TOOLS_H)
    self.tools = tools
    tools.search = UI.TextField(tools, { width = 190, placeholder = "Search", onTextChanged = function() self.page = 1; self:Refresh() end })
    tools.search:SetPoint("LEFT")
    tools.have = UI.Segmented(tools, { value = "all", options = { { value = "all", label = "All" }, { value = "have", label = "Collected" },
        { value = "missing", label = "Not collected" } }, onChange = function() self.page = 1; self:Refresh() end })
    tools.have:SetPoint("LEFT", tools.search, "RIGHT", S["space-4"], 0)
    tools.list = UI.Segmented(tools, { value = "all", options = { { value = "all", label = "Mounts" }, { value = "fav", label = "Favourites" },
        { value = "recent", label = "Recent" } }, onChange = function() self.page = 1; self:Refresh() end })
    tools.list:SetPoint("LEFT", tools.have, "RIGHT", S["space-4"], 0)
    tools.count = UI.Text(tools, "numeric", "ink")
    tools.count:SetPoint("RIGHT", -70, 0)
    tools.track = UI.Fill(tools, "track", "ARTWORK")
    tools.track:SetSize(60, 2)
    tools.track:SetPoint("RIGHT")
    tools.fill = UI.Fill(tools, "gilt", "OVERLAY")
    tools.fill:SetHeight(2)
    tools.fill:SetPoint("LEFT", tools.track, "LEFT")

    -- the stage
    local stage = CreateFrame("Frame", nil, body)
    stage:SetPoint("TOPLEFT")
    stage:SetPoint("TOPRIGHT")
    stage:SetPoint("BOTTOM", tools, "TOP", 0, S["space-5"])
    stage:SetClipsChildren(true)
    stageArt(stage)
    self.stage = stage
    -- the mount: its own scene, framed by its scene ID
    local ok, scene = pcall(CreateFrame, "ModelScene", nil, stage, "ModelSceneMixinTemplate")
    if ok and scene then
        scene:SetPoint("TOPLEFT")
        scene:SetPoint("BOTTOMRIGHT", 0, FLOOR)
        scene:SetFrameLevel(stage:GetFrameLevel() + 2)
        self.scene = scene
    end
    -- loading: the icon first
    stage.loading = CreateFrame("Frame", nil, stage)
    stage.loading:SetSize(200, 120)
    stage.loading:SetPoint("CENTER", stage, "CENTER", 0, FLOOR / 2)
    stage.loading:SetFrameLevel(stage:GetFrameLevel() + 3)
    stage.loading.icon = stage.loading:CreateTexture(nil, "ARTWORK")
    stage.loading.icon:SetSize(80, 80)
    stage.loading.icon:SetPoint("TOP")
    stage.loading.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    stage.loading.text = UI.Text(stage.loading, "caption", "ink-muted")
    stage.loading.text:SetPoint("TOP", stage.loading.icon, "BOTTOM", 0, -S["space-4"])
    stage.loading.text:SetValue("Loading the model…")
    stage.loading:Hide()
    -- the empty stage
    stage.empty = CreateFrame("Frame", nil, stage)
    stage.empty:SetAllPoints()
    stage.empty:SetFrameLevel(stage:GetFrameLevel() + 4)
    stage.empty.title = UI.Text(stage.empty, "alert", "ink")
    stage.empty.title:SetPoint("TOP", 0, -S["space-7"])
    stage.empty.text = UI.Text(stage.empty, "body", "ink-muted")
    stage.empty.text:SetPoint("TOP", stage.empty.title, "BOTTOM", 0, -S["space-3"])
    stage.empty.text:SetWidth(420)
    stage.empty.text:SetWordWrap(true)
    stage.empty.text:SetJustifyH("CENTER")
    stage.empty:Hide()
    self.card = buildCard(stage)
    -- top right: the favourite star and the primary action
    stage.star = roundButton(stage, "star", function(b) return b.on and "Remove from favourites" or "Add to favourites" end,
        function() self:ToggleFavourite() end)
    stage.star:SetFrameLevel(stage:GetFrameLevel() + 12)
    -- Summon / Dismiss: SuuUI's own secure button; the look is a SuuUI button under it
    local act = CreateFrame("Button", "SuuUICollectionsAction", stage, "SecureActionButtonTemplate")
    act:SetSize(120, 30)
    act:SetPoint("TOPRIGHT", -S["space-6"], -S["space-6"])
    act:RegisterForClicks("AnyUp", "AnyDown")
    act:SetFrameLevel(stage:GetFrameLevel() + 12)
    act.look = UI.Button(act, { text = "Summon", variant = "primary", width = 120 })
    act.look:SetAllPoints()
    act.look:EnableMouse(false)
    act:HookScript("OnEnter", function(b) if b.why then UI.ShowTooltip(b, { title = b.look.label and b.look.label:GetText() or "", description = b.why }) end end)
    act:HookScript("OnLeave", function() UI.HideTooltip() end)
    self.act = act
    stage.star:SetPoint("RIGHT", act, "LEFT", -S["space-4"], 0)
    -- bottom centre of the model's area: turn left, zoom out, zoom in, turn right
    local ctl = CreateFrame("Frame", nil, stage)
    ctl:SetSize(4 * 26 + 3 * S["space-3"], 26)
    ctl:SetPoint("BOTTOM", stage, "BOTTOM", 0, S["space-4"])
    ctl:SetFrameLevel(stage:GetFrameLevel() + 12)
    local x = 0
    for _, def in ipairs({ { "turnLeft", "Turn left", function() self:Turn(-1) end }, { "minus", "Zoom out", function() self:Zoom(1) end },
                           { "plus", "Zoom in", function() self:Zoom(-1) end }, { "turnRight", "Turn right", function() self:Turn(1) end } }) do
        local glyph = def[1]
        local file = GLYPHS .. glyph .. ".tga"
        local b = roundButton(ctl, glyph, def[2], def[3])
        if not (glyph == "minus" or glyph == "plus") then
            -- turn arrows: the reset glyph, mirrored for the right
            b.glyph:SetTexture(GLYPHS .. "reset.tga")
            if glyph == "turnRight" then b.glyph:SetTexCoord(1, 0, 0, 1) end
        end
        b:SetPoint("LEFT", x, 0)
        x = x + 26 + S["space-3"]
    end
    stage.ctl = ctl
    stage.hint = UI.Text(stage, "caption", "ink-faint")
    stage.hint:SetPoint("BOTTOMRIGHT", -S["space-5"], S["space-5"])
    stage.hint:SetValue("Drag to turn · Wheel to zoom")

    -- the foot: the overview
    self.foot = UI.Text(w.footer, "caption", "ink-muted")
    self.foot:SetPoint("LEFT")
    self.last = UI.Text(w.footer, "caption", "ink-muted")
    self.last:SetPoint("RIGHT")
end

--------------------------------------------------------------------------------
-- What the strip shows: the tab's entries through the search and filters
--------------------------------------------------------------------------------

function M:Entries()
    local all = self:Mounts()
    local tools = self.tools
    local search = (tools.search.edit:GetText() or ""):lower()
    local have, list = tools.have.value or "all", tools.list.value or "all"
    local out = {}
    for _, e in ipairs(all) do
        local ok = (search == "" or e.name:lower():find(search, 1, true))
            and (have == "all" or (have == "have") == (e.collected and true or false))
            and (list ~= "fav" or e.favourite)
            and (list ~= "recent" or e.learned ~= nil)
        if ok then out[#out + 1] = e end
    end
    if list == "recent" then
        table.sort(out, function(a, b)
            local x, y = a.learned or -1, b.learned or -1
            if x == 0 then x = -1 end
            if y == 0 then y = -1 end
            if x ~= y then return x > y end
            return a.name < b.name
        end)
    end
    return out, all
end

-- The cells across the grid's width (18 a row, the space shared out between).
function M:LayoutCells()
    local grid = self.strip.grid
    local w = grid:GetWidth()
    if not w or w <= 0 or isSecret(w) then return end
    local gap = math.max(2, (w - COLS * CELL) / (COLS - 1))
    for i, b in ipairs(self.strip.cells) do
        local col, row = (i - 1) % COLS, math.floor((i - 1) / COLS)
        b:ClearAllPoints()
        b:SetPoint("TOPLEFT", col * (CELL + gap), -row * (CELL + S["space-5"]))
    end
end

function M:Page(step)
    local pages = self.pages or 1
    self.page = math.max(1, math.min(pages, (self.page or 1) + step))
    self:DrawStrip()
end

function M:DrawStrip()
    local strip, list = self.strip, self.entries or {}
    local per = COLS * ROWS
    self.pages = math.max(1, math.ceil(#list / per))
    self.page = math.max(1, math.min(self.pages, self.page or 1))
    local first = (self.page - 1) * per
    for i, b in ipairs(strip.cells) do
        b.entry = list[first + i]
        self:DrawCell(b)
    end
    local paged = self.pages > 1
    strip.prev:SetShown(paged)
    strip.next:SetShown(paged)
    strip.pageText:SetShown(paged)
    strip.prev:SetEnabledState(self.page > 1)
    strip.next:SetEnabledState(self.page < self.pages)
    strip.pageText:SetValue(self.page .. " / " .. self.pages)
    strip.empty:SetShown(#list == 0)
    strip.empty:SetValue("No mounts match.")
end

function M:Refresh()
    if not (self.window and self.window:IsShown()) then return end
    local entries, all = self:Entries()
    self.entries, self.all = entries, all
    local have = 0
    for _, e in ipairs(all) do if e.collected then have = have + 1 end end
    local tools = self.tools
    tools.count:SetValue(("%d |cff%sof %d|r"):format(have, T.color["ink-muted"].hex, #all))
    tools.fill:SetWidth(math.max(1, 60 * (#all > 0 and have / #all or 0)))
    -- the chosen one stays while it is listed; else the first
    local still = false
    for _, e in ipairs(entries) do if self.chosen and e.id == self.chosen.id then self.chosen = e; still = true end end
    if not still then self.chosen = (have > 0 or #entries > 0) and entries[1] or nil end
    if have == 0 and not self.picked then self.chosen = nil end
    self:DrawStrip()
    self:DrawStage()
    self:DrawFoot()
end

function M:Choose(e)
    if not e then return end
    self.chosen, self.picked = e, true
    self:DrawStrip()
    self:DrawStage()
end

--------------------------------------------------------------------------------
-- The stage
--------------------------------------------------------------------------------

function M:DrawStage()
    local stage, e = self.stage, self.chosen
    local none = e == nil
    stage.empty:SetShown(none)
    self.card:SetShown(not none)
    stage.star:SetShown(not none)
    stage.ctl:SetShown(not none)
    stage.hint:SetShown(not none)
    tintStage(stage, "gilt")
    if none then
        stage.empty.title:SetValue("No mounts yet")
        stage.empty.text:SetValue("Every mount is in the strip below, with where it comes from. Pick one to see it here.")
        if self.scene then self.scene:Hide() end
        stage.loading:Hide()
        self:DrawAction()
        return
    end
    self:DrawCard(self.card, e)
    stage.star.on = e.favourite and true or false
    stage.star:Draw(false)
    self:ShowMount(e)
    self:DrawAction()
end

-- The mount in its own scene; its icon until the model has loaded, then the
-- model fades in.
function M:ShowMount(e)
    local scene, stage = self.scene, self.stage
    if not scene then return end
    self.showing = e.id
    scene:SetAlpha(0)
    scene:Show()
    stage.loading.icon:SetTexture(e.icon)
    stage.loading:Show()
    call(scene.TransitionToModelSceneID, scene, e.scene or 4, CAMERA_TRANSITION_TYPE_IMMEDIATE, CAMERA_MODIFICATION_TYPE_DISCARD, true)
    local actor = call(scene.GetActorByTag, scene, "unwrapped")
    self.actor = actor
    if not actor then return end
    call(actor.SetModelByCreatureDisplayID, actor, e.display or 0)
    if e.isSelf then call(actor.SetAnimation, actor, 618) else call(actor.SetAnimation, actor, 0) end
    local id, tries = e.id, 0
    local function check()
        if self.showing ~= id then return end
        tries = tries + 1
        local loaded = call(actor.IsLoaded, actor)
        if loaded or tries > 40 then
            -- a little further out than the game's framing: the whole mount
            local cam = call(scene.GetActiveCamera, scene)
            local d = cam and call(cam.GetZoomDistance, cam)
            if d then call(cam.SetZoomDistance, cam, d * ZOOM_OUT) end
            stage.loading:Hide()
            scene:SetAlpha(1)
            SuuUI.Motion.FadeIn(scene, T.duration["dur-base"])
        else
            C_Timer.After(0.05, check)
        end
    end
    check()
end

function M:Turn(dir)
    local a = self.actor
    if not a then return end
    local yaw = call(a.GetYaw, a) or 0
    call(a.SetYaw, a, yaw + dir * 0.35)
end

function M:Zoom(dir)
    local cam = self.scene and call(self.scene.GetActiveCamera, self.scene)
    if not cam then return end
    local d = call(cam.GetZoomDistance, cam)
    if d then call(cam.SetZoomDistance, cam, d * (dir > 0 and 1.15 or 0.87)) end
end

-- A mount's favourite: the game keeps it by the mount's place in its own
-- list, so the place is looked up first.
function M:ToggleFavourite()
    local e = self.chosen
    if not (e and e.kind == "mount") then return end
    local MJ = C_MountJournal
    for i = 1, (call(MJ.GetNumDisplayedMounts) or 0) do
        if call(MJ.GetDisplayedMountID, i) == e.id then
            call(MJ.SetIsFavorite, i, not e.favourite)
            C_Timer.After(0.1, function() self:Refresh() end)
            return
        end
    end
end

-- Summon or Dismiss: the secure button's job, set out of combat (in one it
-- waits; its look says why).
function M:DrawAction()
    local act, e = self.act, self.chosen
    if not act then return end
    local mounted = IsMounted and IsMounted() or false
    local label, why = "Summon", nil
    if mounted then label = "Dismiss"
    elseif not e then why = "Choose a mount."
    elseif not e.collected then why = "You don't have this mount yet."
    elseif not e.usable then why = "You can't ride this mount here." end
    act.look.label:SetValue(label)
    act.look:SetEnabledState(why == nil)
    act.why = why
    if InCombatLockdown() then
        self.actionAfterCombat = true
        return
    end
    act:SetShown(e ~= nil or mounted)
    if mounted then
        act:SetAttribute("type", "macro")
        act:SetAttribute("macrotext", "/dismount")
    elseif why then
        act:SetAttribute("type", nil)
    else
        act:SetAttribute("type", "spell")
        act:SetAttribute("spell", e.spellID)
    end
end

function M:DrawFoot()
    local mounts, have = self.all or {}, 0
    for _, e in ipairs(mounts) do if e.collected then have = have + 1 end end
    local muted = "|cff" .. T.color["ink-muted"].hex
    self.foot:SetValue(("Mounts |cff%s%d|r%s of %d|r"):format(T.color["ink"].hex, have, muted, #mounts))
    local last = self:CharData().last
    self.last:SetValue(last and ("Last collected: |cff%s%s|r, %s"):format(T.color["ink"].hex, last.name, day(last.at)) or "Nothing collected yet")
end

--------------------------------------------------------------------------------
-- Opening it: the micro menu (SuuUI.ToggleCollections), the game's
-- Collections key (an override binding onto SuuUI's button), and the game's
-- journal when something else opens it (closed again, ours instead)
--------------------------------------------------------------------------------

function M:Toggle(tab)
    if not self.window then return end
    if self.window:IsShown() and not tab then self.window:Hide() return end
    self.window:Show()
    self.window:SetTab(tab or self.tab or "mounts")
end

function M:BindKeys()
    if not self.bindOwner then return end
    if InCombatLockdown() then self.bindAfterCombat = true return end
    ClearOverrideBindings(self.bindOwner)
    for _, key in ipairs({ GetBindingKey("TOGGLECOLLECTIONS") }) do
        if key then SetOverrideBindingClick(self.bindOwner, false, key, "SuuUICollectionsToggle") end
    end
end

function M:HookJournal()
    local f = _G.CollectionsJournal
    if not f or self.journalHooked then return end
    self.journalHooked = true
    f:HookScript("OnShow", function()
        if not self:IsEnabled() or InCombatLockdown() then return end
        HideUIPanel(f)
        self:Toggle("mounts")
    end)
end

function M:OnEnable()
    if not self.window then self:Build() end
    self.tab = self.tab or "mounts"
    if not self.toggleButton then
        self.toggleButton = CreateFrame("Button", "SuuUICollectionsToggle", UIParent)
        self.toggleButton:SetScript("OnClick", function() self:Toggle() end)
        self.bindOwner = CreateFrame("Frame")
    end
    self:BindKeys()
    self:OnGameEvent("UPDATE_BINDINGS", function() self:BindKeys() end)
    self:OnGameEvent("PLAYER_REGEN_ENABLED", function()
        if self.bindAfterCombat then self.bindAfterCombat = nil; self:BindKeys() end
        if self.actionAfterCombat then self.actionAfterCombat = nil; self:DrawAction() end
    end)
    for _, e in ipairs({ "PLAYER_MOUNT_DISPLAY_CHANGED", "COMPANION_UPDATE" }) do
        self:OnGameEvent(e, function() self:DrawAction() end)
    end
    -- something new: noted with today's date, the window redrawn
    self:OnGameEvent("NEW_MOUNT_ADDED", function(_, id)
        local name = id and call(C_MountJournal.GetMountInfoByID, id)
        self:NoteLast(name, time())
        self:Refresh()
    end)
    self:OnGameEvent("MOUNT_JOURNAL_USABILITY_CHANGED", function() self:DrawAction() end)
    self:HookJournal()
    self:OnGameEvent("ADDON_LOADED", function(_, name) if name == "Blizzard_Collections" then self:HookJournal() end end)
end

function M:OnDisable()
    if self.window then self.window:Hide() end
    if self.bindOwner and not InCombatLockdown() then ClearOverrideBindings(self.bindOwner) end
end
