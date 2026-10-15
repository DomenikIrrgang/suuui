-- Units/Marks.lua
-- Your own marks on the map (3.5, stage 3): a spot you keep, with a name
-- and one of eight symbols, saved per character. Ctrl+click on the world
-- map drops one (the gesture the game uses for its own waypoint: SuuUI's
-- takes it). A mark can show the way (the game's waypoint and navigation
-- arrow) and be posted to your group: a chat line with the game's own map
-- pin link, which anyone can click, and the mark itself to group members
-- with SuuUI, who keep it as a shared mark until they remove it.
--
-- The world map draws the marks (WorldMap), the minimap too; both read
-- them here and hear SUUUI_MARKS_CHANGED.
--
-- A mark: { id, map (uiMapID), x, y (0-1), name, symbol, from (who shared
-- it; nil: yours), at (time made) }.

local M = SuuUI.RegisterModule({
    id = "marks",
    name = "Map marks",
    description = "Your own marks on the world map and minimap: Ctrl+click the map to make one, name it, follow it, post it to your group.",
    api = "0.15",
})

local UI = SuuUI.UI

local isSecret = issecretvalue or function() return false end
local function plain(v) return v ~= nil and not isSecret(v) end

M.SYMBOLS = { "star", "circle", "diamond", "triangle", "moon", "square", "cross", "skull" }
local SYMBOL = {}
for i, s in ipairs(M.SYMBOLS) do SYMBOL[s] = i end

local MAX_MARKS = 200 -- yours and shared together; the oldest shared go first
local PREFIX = "SuuUI"

--------------------------------------------------------------------------------
-- The marks
--------------------------------------------------------------------------------

local function store(self)
    local data = self:CharData()
    data.marks = data.marks or {}
    data.nextID = data.nextID or 1
    return data
end

function M:Marks()
    return store(self).marks
end

function M:Get(id)
    for _, m in ipairs(self:Marks()) do if m.id == id then return m end end
end

local function changed(self)
    self:Emit("SUUUI_MARKS_CHANGED")
end

-- (room for one more: the oldest shared mark goes, then the oldest)
local function makeRoom(list)
    if #list < MAX_MARKS then return end
    for i, m in ipairs(list) do
        if m.from then table.remove(list, i) return end
    end
    table.remove(list, 1)
end

function M:Add(map, x, y, fields)
    local data = store(self)
    makeRoom(data.marks)
    local mark = { id = data.nextID, map = map, x = x, y = y, name = "", symbol = "star", at = time() }
    for k, v in pairs(fields or {}) do mark[k] = v end
    if not SYMBOL[mark.symbol] then mark.symbol = "star" end
    data.nextID = data.nextID + 1
    table.insert(data.marks, mark)
    changed(self)
    return mark
end

function M:Update(id, fields)
    local mark = self:Get(id)
    if not mark then return end
    for k, v in pairs(fields) do mark[k] = v end
    if not SYMBOL[mark.symbol] then mark.symbol = "star" end
    changed(self)
    return mark
end

function M:Remove(id)
    local list = self:Marks()
    for i, m in ipairs(list) do
        if m.id == id then
            table.remove(list, i)
            if self.following == id then self:Follow(nil) end
            changed(self)
            return
        end
    end
end

-- A mark's place on another map (a zone's mark on its continent): through
-- the world's coordinates; nil when that map doesn't hold it.
function M:PlaceOn(mark, mapID)
    if mark.map == mapID then return mark.x, mark.y end
    if not (C_Map.GetWorldPosFromMapPos and C_Map.GetMapPosFromWorldPos and CreateVector2D) then return end
    local ok, continent, world = pcall(C_Map.GetWorldPosFromMapPos, mark.map, CreateVector2D(mark.x, mark.y))
    if not (ok and plain(continent) and world) then return end
    local ok2, onMap, pos = pcall(C_Map.GetMapPosFromWorldPos, continent, world, mapID)
    if not (ok2 and onMap == mapID and pos) then return end
    local x, y = pos:GetXY()
    if plain(x) and plain(y) and x >= 0 and x <= 1 and y >= 0 and y <= 1 then return x, y end
end

--------------------------------------------------------------------------------
-- Showing the way: the game's waypoint and its navigation arrow
--------------------------------------------------------------------------------

-- The game draws its navigation indicator only with showInGameNavigation
-- on, and Forever has it off (/suu probe marks nav: the indicator shown at
-- opacity 0). On while a mark shows the way, your own value back after
-- (kept in the saved data, so a /reload on the way still puts it back).
local NAV_CVAR = "showInGameNavigation"
local function navigation(self, on)
    local data = store(self)
    if on then
        if data.navWas == nil then data.navWas = GetCVar(NAV_CVAR) or "0" end
        if GetCVar(NAV_CVAR) ~= "1" then pcall(SetCVar, NAV_CVAR, "1") end
    elseif data.navWas ~= nil then
        pcall(SetCVar, NAV_CVAR, data.navWas)
        data.navWas = nil
    end
end

function M:Follow(id)
    local mark = id and self:Get(id)
    if mark and UiMapPoint and C_Map.CanSetUserWaypointOnMap and C_Map.CanSetUserWaypointOnMap(mark.map) then
        C_Map.SetUserWaypoint(UiMapPoint.CreateFromCoordinates(mark.map, mark.x, mark.y))
        if C_SuperTrack and C_SuperTrack.SetSuperTrackedUserWaypoint then C_SuperTrack.SetSuperTrackedUserWaypoint(true) end
        self.following = id
        store(self).following = id
        navigation(self, true)
        if self.waypointProvider and self.waypointProvider:GetMap():IsShown() then self.waypointProvider:RefreshAllData() end
    else
        if self.following and C_Map.ClearUserWaypoint then C_Map.ClearUserWaypoint() end
        self.following = nil
        store(self).following = nil
        navigation(self, false)
    end
    changed(self)
end

function M:Following() return self.following end

function M:HideGamePin(provider)
    local pin = provider and provider.pin
    if not pin then return end
    local hide = self:IsEnabled() and self.following ~= nil
    pin:SetAlpha(hide and 0 or 1)
    pin:EnableMouse(not hide)
end

--------------------------------------------------------------------------------
-- Posting: a chat line anyone can use, and the mark to SuuUI players
--------------------------------------------------------------------------------

-- The group's chat: instance, raid or party; nil when you're not in one.
function M:GroupChannel()
    if UI.Flag(IsInGroup(LE_PARTY_CATEGORY_INSTANCE)) then return "INSTANCE_CHAT" end
    if UI.Flag(IsInRaid()) then return "RAID" end
    if UI.Flag(IsInGroup()) then return "PARTY" end
end

-- The game's own map pin link for a spot ("[Map Pin Location]"): it makes
-- links only for its waypoint, so the waypoint is set for a moment and put
-- back as it was (with its navigation).
local function linkFor(mark)
    if not (UiMapPoint and C_Map.SetUserWaypoint and C_Map.GetUserWaypointHyperlink) then return end
    local had = C_Map.GetUserWaypoint and C_Map.GetUserWaypoint()
    local tracking = C_SuperTrack and C_SuperTrack.IsSuperTrackingUserWaypoint and C_SuperTrack.IsSuperTrackingUserWaypoint()
    local ok = pcall(C_Map.SetUserWaypoint, UiMapPoint.CreateFromCoordinates(mark.map, mark.x, mark.y))
    local link = ok and C_Map.GetUserWaypointHyperlink() or nil
    if had then C_Map.SetUserWaypoint(had) else C_Map.ClearUserWaypoint() end
    if tracking and C_SuperTrack.SetSuperTrackedUserWaypoint then C_SuperTrack.SetSuperTrackedUserWaypoint(true) end
    return link
end

-- (names and the like can't break the message: no tabs or newlines)
local function clean(s) return (tostring(s or ""):gsub("[\t\n\r|]", " ")) end

-- From a click only: the game sends chat from a click.
function M:Post(id)
    local mark = self:Get(id)
    local channel = self:GroupChannel()
    if not (mark and channel) or InCombatLockdown() then return false end
    local link = linkFor(mark)
    local name = clean(mark.name)
    local text = (name ~= "" and (name .. " · ") or "") .. (link or ("%s %.1f, %.1f"):format(self:MapName(mark.map) or "", mark.x * 100, mark.y * 100))
    local send = (C_ChatInfo and C_ChatInfo.SendChatMessage) or SendChatMessage
    pcall(send, text, channel)
    -- the mark itself to group members with SuuUI
    if C_ChatInfo and C_ChatInfo.SendAddonMessage then
        local msg = ("MARK\t%d\t%.4f\t%.4f\t%s\t%s"):format(mark.map, mark.x, mark.y, mark.symbol, name)
        pcall(C_ChatInfo.SendAddonMessage, PREFIX, msg, channel)
    end
    return true
end

function M:MapName(map)
    local info = map and C_Map.GetMapInfo(map)
    return info and info.name
end

-- A shared mark from a group member: kept until you remove it; the same
-- one posted again (same place, same sender) only updates its name.
function M:OnMessage(prefix, text, channel, sender)
    if prefix ~= PREFIX or not plain(text) or not plain(sender) then return end
    local tag, map, x, y, symbol, name = strsplit("\t", text)
    if tag ~= "MARK" then return end
    map, x, y = tonumber(map), tonumber(x), tonumber(y)
    if not (map and x and y and x >= 0 and x <= 1 and y >= 0 and y <= 1) then return end
    -- your own post coming back (the sender comes as "Name Surname" or
    -- "Name-Realm": found with /suu probe marks)
    local name0, realm = UnitFullName("player")
    if sender == name0 or (realm and (sender == name0 .. "-" .. realm or sender == name0 .. " " .. realm)) then return end
    local who = sender
    for _, m in ipairs(self:Marks()) do
        if m.from == who and m.map == map and math.abs(m.x - x) < 0.0005 and math.abs(m.y - y) < 0.0005 then
            self:Update(m.id, { name = name or "", symbol = symbol })
            return
        end
    end
    self:Add(map, x, y, { name = name or "", symbol = symbol, from = who })
end

--------------------------------------------------------------------------------
-- On the minimap: a mark in range where it is, one further away on the
-- ring's edge pointing its way. World coordinates: UnitPosition's first
-- value (and a world vector's x) runs north, its second (y) west (found
-- with /suu probe marks: both agree to the yard); the minimap shows
-- C_Minimap.GetViewRadius() yards from its middle to its edge, turned with
-- you when rotateMinimap is on.
--------------------------------------------------------------------------------

local EDGE_REACH = 0.86 -- an edge mark sits at this much of the radius

-- a mark's world position, cached ({ continent, north, west })
local worldCache = setmetatable({}, { __mode = "k" })
local function worldOf(mark)
    local w = worldCache[mark]
    if w == nil then
        w = false
        if C_Map.GetWorldPosFromMapPos and CreateVector2D then
            local ok, continent, pos = pcall(C_Map.GetWorldPosFromMapPos, mark.map, CreateVector2D(mark.x, mark.y))
            if ok and plain(continent) and pos then
                local n, wv = pos:GetXY()
                if plain(n) and plain(wv) then w = { continent, n, wv } end
            end
        end
        worldCache[mark] = w
    end
    return w or nil
end

-- Where each mark goes on the minimap: { mark, x, y (px from the middle),
-- edge (true: out of range, on the ring), angle (radians, 0 = up, the way
-- to it) }.
function M:MinimapPlaces()
    local mm = _G.Minimap
    if not (mm and C_Minimap and C_Minimap.GetViewRadius) then return {} end
    local okP, north, west, _, instance = pcall(UnitPosition, "player")
    if not (okP and plain(north) and plain(west) and plain(instance)) then return {} end
    local yards = C_Minimap.GetViewRadius()
    if not (plain(yards) and yards > 0) then return {} end
    local half = mm:GetWidth() / 2
    local turn = 0
    if GetCVar("rotateMinimap") == "1" and GetPlayerFacing then
        local f = GetPlayerFacing()
        if plain(f) then turn = -f end
    end
    local out = {}
    for _, mark in ipairs(self:Marks()) do
        local w = worldOf(mark)
        if w and w[1] == instance then
            -- east and north of you, in yards
            local east, up = west - w[3], w[2] - north
            if turn ~= 0 then
                local c, sn = math.cos(turn), math.sin(turn)
                east, up = east * c - up * sn, east * sn + up * c
            end
            local dist = math.sqrt(east * east + up * up)
            local px, py = east / yards * half, up / yards * half
            local reach = half * EDGE_REACH
            local edge = math.sqrt(px * px + py * py) > reach
            if edge then
                local k = reach / math.sqrt(px * px + py * py)
                px, py = px * k, py * k
            end
            out[#out + 1] = { mark = mark, x = px, y = py, edge = edge, angle = math.atan2(east, up), yards = dist }
        end
    end
    return out
end

-- The minimap's layer: its pins placed ten times a second while it shows
-- (you move, it turns). MinimapPin(parent) makes one (see the look below).
function M:UpdateMinimap()
    local mm = _G.Minimap
    if not mm then return end
    local layer = self.mmLayer
    if not layer then
        layer = CreateFrame("Frame", nil, mm)
        layer:SetAllPoints()
        layer:SetFrameLevel(mm:GetFrameLevel() + 5)
        layer.pins = {}
        local wait = 0
        layer:SetScript("OnUpdate", function(_, elapsed)
            wait = wait - elapsed
            if wait > 0 then return end
            wait = 0.1
            self:PlaceMinimapPins()
        end)
        self.mmLayer = layer
    end
    layer:SetShown(self:IsEnabled())
    self:PlaceMinimapPins()
end

function M:PlaceMinimapPins()
    local layer = self.mmLayer
    if not (layer and layer:IsShown()) then return end
    local places = self:Filtered(self:MinimapPlaces())
    for i, p in ipairs(places) do
        local pin = layer.pins[i]
        if not pin then
            pin = self:MinimapPin(layer)
            layer.pins[i] = pin
        end
        pin:SetMark(p.mark, p.edge, p.angle)
        pin:ClearAllPoints()
        pin:SetPoint("CENTER", layer, "CENTER", p.x, p.y)
        pin:Show()
    end
    for i = #places + 1, #layer.pins do layer.pins[i]:Hide() end
end

-- Only the marks the map's filters show (Marks › Your marks, Shared marks).
function M:Filtered(places)
    local map = SuuUI.GetModule and SuuUI.GetModule("worldmap")
    local on = map and map.MarksShown and map:MarksShown() or { yours = true, shared = true }
    local out = {}
    for _, p in ipairs(places) do
        if (p.mark.from and on.shared) or (not p.mark.from and on.yours) then out[#out + 1] = p end
    end
    return out
end

--------------------------------------------------------------------------------
-- The look (design: MapPin type "mark", MarkCard, Minimap marks)
--------------------------------------------------------------------------------

local GLYPHS = "Interface\\AddOns\\SuuUI\\Media\\Textures\\Glyphs\\"
local DISC = "Interface\\AddOns\\SuuUI\\Media\\Textures\\CircleFill.tga"
local function glyphOf(symbol) return "mark" .. symbol:sub(1, 1):upper() .. symbol:sub(2) end
local function colorOf(symbol) return "mark-" .. symbol end

-- A mark's map pin: its symbol in its colour on a 2 px edge of its colour
-- (other pins' are 1 px); the open one ringed in its colour.
function M:PinLook(mark)
    local c = colorOf(mark.symbol)
    return { glyph = glyphOf(mark.symbol), color = c, edge = c, edgeWidth = 2,
             ring = self.cardMark == mark.id and c or nil }
end

-- On the minimap: a 16 px surface disc with a 1.5 px edge and an 11 px
-- glyph in the mark's colour; out of range it sits on the ring (0.86 of the
-- radius, MinimapPlaces) with a 6 px arrow in its colour just outside,
-- pointing at the mark.
local MiniPin = {}
function MiniPin:SetMark(mark, edge, angle)
    local c = colorOf(mark.symbol)
    self.edge:SetVertexColor(UI.RGBA(c))
    self.glyph:SetTexture(GLYPHS .. glyphOf(mark.symbol) .. ".tga")
    self.glyph:SetVertexColor(UI.RGBA(c))
    self.arrow:SetShown(edge)
    if edge then
        self.arrow:SetVertexColor(UI.RGBA(c))
        -- (the arrow points up at angle 0; SetRotation turns counter-clockwise)
        self.arrow:SetRotation(-angle)
        self.arrow:ClearAllPoints()
        self.arrow:SetPoint("CENTER", self, "CENTER", math.sin(angle) * 12, math.cos(angle) * 12)
    end
    self.mark = mark
end
function M:MinimapPin(parent)
    local b = CreateFrame("Frame", nil, parent)
    Mixin(b, MiniPin)
    b:SetSize(16, 16)
    b.edge = b:CreateTexture(nil, "BORDER", nil, 1)
    b.edge:SetTexture(DISC)
    b.edge:SetAllPoints()
    b.fill = b:CreateTexture(nil, "BORDER", nil, 2)
    b.fill:SetTexture(DISC)
    b.fill:SetPoint("CENTER")
    b.fill:SetSize(13, 13)
    b.fill:SetVertexColor(UI.RGBA("surface"))
    b.glyph = b:CreateTexture(nil, "ARTWORK")
    b.glyph:SetPoint("CENTER")
    b.glyph:SetSize(11, 11)
    b.arrow = b:CreateTexture(nil, "ARTWORK")
    b.arrow:SetTexture(GLYPHS .. "markArrow.tga")
    b.arrow:SetSize(8, 8)
    b:EnableMouse(true)
    b:SetScript("OnEnter", function(self)
        local m = self.mark
        if not m then return end
        UI.ShowTooltip(self, { title = m.name ~= "" and m.name or "Mark",
            subtitle = ("%s · %.1f, %.1f"):format(M:MapName(m.map) or "", m.x * 100, m.y * 100),
            lines = m.from and { { "Shared by " .. m.from } } or nil })
    end)
    b:SetScript("OnLeave", function() UI.HideTooltip() end)
    return b
end

--------------------------------------------------------------------------------
-- The mark card: name, symbol, where, Show the way, Delete and Post (a
-- shared mark's: its name and symbol to read, who shared it, Show the way,
-- Remove). Over the world map, under the mark (above it in the map's lower
-- half), kept inside the map.
--------------------------------------------------------------------------------

local CARD_W, PAD, ROW = 256, 12, 8

local function symbolButton(card, i, symbol)
    local b = CreateFrame("Button", nil, card)
    b:SetSize(24, 24)
    b.edge = b:CreateTexture(nil, "BORDER", nil, 1)
    b.edge:SetTexture(DISC)
    b.edge:SetAllPoints()
    b.fill = b:CreateTexture(nil, "BORDER", nil, 2)
    b.fill:SetTexture(DISC)
    b.fill:SetPoint("CENTER")
    b.glyph = b:CreateTexture(nil, "ARTWORK")
    b.glyph:SetTexture(GLYPHS .. glyphOf(symbol) .. ".tga")
    b.glyph:SetVertexColor(UI.RGBA(colorOf(symbol)))
    b.glyph:SetSize(16, 16)
    b.glyph:SetPoint("CENTER")
    b.symbol = symbol
    function b:SetChosen(on)
        self.edge:SetVertexColor(UI.RGBA(on and colorOf(symbol) or "gilt-line"))
        self.fill:SetSize(on and 20 or 22, on and 20 or 22)
        self.fill:SetVertexColor(UI.RGBA(on and "surface-raised" or "surface-sunk"))
    end
    b:SetScript("OnClick", function() card:Choose(symbol) end)
    b:SetScript("OnEnter", function(self) UI.ShowTooltip(self, { title = symbol:sub(1, 1):upper() .. symbol:sub(2) }) end)
    b:SetScript("OnLeave", function() UI.HideTooltip() end)
    return b
end

function M:Card()
    if self.card then return self.card end
    local map = _G.WorldMapFrame
    local card = CreateFrame("Frame", nil, map)
    card:SetFrameStrata(map:GetFrameStrata())
    card:SetFrameLevel(map:GetFrameLevel() + 600)
    card:SetWidth(CARD_W)
    card:EnableMouse(true)
    UI.Fill(card, "surface"):SetAllPoints()
    UI.Border(card, "gilt-line")
    UI.Shadow(card, "shadow-panel")
    local jewel = UI.Diamond(card, 7, "gilt")
    jewel:SetPoint("CENTER", card, "TOPLEFT", 0, 0)

    -- yours: the name to edit and the symbols to choose
    card.name = UI.TextField(card, { width = CARD_W - 2 * PAD, placeholder = "Name this mark",
        onChange = function(text) if card.id then self:Update(card.id, { name = text }) end end })
    card.symbols = {}
    for i, sym in ipairs(M.SYMBOLS) do
        local b = symbolButton(card, i, sym)
        card.symbols[i] = b
    end
    function card.Choose(_, symbol)
        if not card.id then return end
        self.lastSymbol = symbol
        self:Update(card.id, { symbol = symbol })
        for _, b in ipairs(card.symbols) do b:SetChosen(b.symbol == symbol) end
    end
    -- shared: its symbol and name to read, who shared it
    card.sharedDisc = CreateFrame("Frame", nil, card)
    card.sharedDisc:SetSize(21, 21)
    card.sharedDisc.edge = card.sharedDisc:CreateTexture(nil, "BORDER", nil, 1)
    card.sharedDisc.edge:SetTexture(DISC)
    card.sharedDisc.edge:SetAllPoints()
    card.sharedDisc.fill = card.sharedDisc:CreateTexture(nil, "BORDER", nil, 2)
    card.sharedDisc.fill:SetTexture(DISC)
    card.sharedDisc.fill:SetSize(17, 17)
    card.sharedDisc.fill:SetPoint("CENTER")
    card.sharedDisc.fill:SetVertexColor(UI.RGBA("surface"))
    card.sharedDisc.glyph = card.sharedDisc:CreateTexture(nil, "ARTWORK")
    card.sharedDisc.glyph:SetSize(14, 14)
    card.sharedDisc.glyph:SetPoint("CENTER")
    card.sharedName = UI.Text(card, "label", "ink")
    card.sharedBy = UI.Text(card, "caption", "ink-muted")

    card.where = UI.Text(card, "caption", "ink-muted")
    card.wayLabel = UI.Text(card, "body", "ink")
    card.wayLabel:SetValue("Show the way")
    card.way = UI.Toggle(card)
    card.way.onChange = function(on) if card.id then self:Follow(on and card.id or nil) end end
    card.rule = UI.Hairline(card, "gilt-faint")
    card.delete = UI.Button(card, { text = "Delete", onClick = function()
        local id = card.id
        self:CloseCard()
        if id then self:Remove(id) end
    end })
    card.post = UI.Button(card, { text = "Post to party", onClick = function()
        if card.id then self:Post(card.id) end
    end })
    card.postNote = UI.Text(card, "caption", "ink-faint")
    card.postNote:SetValue("Join a group to post it.")
    card:Hide()
    self.card = card
    return card
end

-- Lays the card out for a mark of yours or a shared one; returns its height.
local function layout(card, shared)
    local y = -PAD
    local function row(frame, h, x)
        frame:ClearAllPoints()
        frame:SetPoint("TOPLEFT", x or PAD, y)
        y = y - h - ROW
    end
    card.name:SetShown(not shared)
    for _, b in ipairs(card.symbols) do b:SetShown(not shared) end
    card.sharedDisc:SetShown(shared)
    card.sharedName:SetShown(shared)
    card.sharedBy:SetShown(shared)
    if shared then
        card.sharedDisc:ClearAllPoints()
        card.sharedDisc:SetPoint("TOPLEFT", PAD, y)
        card.sharedName:ClearAllPoints()
        card.sharedName:SetPoint("LEFT", card.sharedDisc, "RIGHT", 8, 0)
        y = y - 21 - ROW
        row(card.sharedBy, 14)
    else
        row(card.name, 30)
        local gap = (CARD_W - 2 * PAD - 8 * 24) / 7
        for i, b in ipairs(card.symbols) do
            b:ClearAllPoints()
            b:SetPoint("TOPLEFT", PAD + (i - 1) * (24 + gap), y)
        end
        y = y - 24 - ROW
    end
    row(card.where, 14)
    card.wayLabel:ClearAllPoints()
    card.wayLabel:SetPoint("TOPLEFT", PAD, y - 2)
    card.way:ClearAllPoints()
    card.way:SetPoint("TOPRIGHT", -PAD, y)
    y = y - 18 - ROW
    card.rule:ClearAllPoints()
    card.rule:SetPoint("TOPLEFT", PAD, y)
    card.rule:SetPoint("TOPRIGHT", -PAD, y)
    y = y - ROW
    card.delete:ClearAllPoints()
    card.delete:SetPoint("TOPLEFT", PAD, y)
    card.post:ClearAllPoints()
    card.post:SetPoint("TOPRIGHT", -PAD, y)
    card.post:SetShown(not shared)
    y = y - 30
    return y
end

function M:OpenCard(id, anchor)
    local mark = self:Get(id)
    local map = _G.WorldMapFrame
    if not (mark and map) then return end
    local card = self:Card()
    card.id = nil -- (no writes while it's set up)
    local shared = mark.from ~= nil
    local y = layout(card, shared)
    if shared then
        local c = colorOf(mark.symbol)
        card.sharedDisc.edge:SetVertexColor(UI.RGBA(c))
        card.sharedDisc.glyph:SetTexture(GLYPHS .. glyphOf(mark.symbol) .. ".tga")
        card.sharedDisc.glyph:SetVertexColor(UI.RGBA(c))
        card.sharedName:SetValue(mark.name ~= "" and mark.name or "Mark")
        card.sharedBy:SetValue("Shared by " .. mark.from)
        card.delete:SetLabel("Remove")
    else
        card.name:SetValue(mark.name)
        for _, b in ipairs(card.symbols) do b:SetChosen(b.symbol == mark.symbol) end
        card.delete:SetLabel("Delete")
        local channel = self:GroupChannel()
        local label = channel == "RAID" and "Post to raid" or channel == "INSTANCE_CHAT" and "Post to instance" or "Post to party"
        card.post:SetLabel(label)
        card.post:SetEnabledState(channel ~= nil)
        card.post.tooltip = channel == nil and { title = "Join a group to post it." } or nil
        card.postNote:SetShown(channel == nil)
        if channel == nil then
            card.postNote:ClearAllPoints()
            card.postNote:SetPoint("TOPRIGHT", card.post, "BOTTOMRIGHT", 0, -4)
            y = y - 18
        end
    end
    card.where:SetValue(("%s · %.1f, %.1f"):format(self:MapName(mark.map) or "", mark.x * 100, mark.y * 100))
    card.way:SetValue(self.following == id)
    card:SetHeight(-y + PAD)
    card.id = id
    self.cardMark = id
    card:Show()
    self:AnchorCard(anchor)
    self:Emit("SUUUI_MARKS_CHANGED")
    return card
end

-- Under its mark's pin, above it in the map's lower half, inside the map;
-- again whenever the map lays its pins out (a pin may now be another's).
-- No pin (the mark isn't on this map): the card closes.
function M:AnchorCard(anchor)
    local card, map = self.card, _G.WorldMapFrame
    if not (card and card:IsShown() and map) then return end
    if not anchor then self:CloseCard() return end
    card:ClearAllPoints()
    local scroll = map.ScrollContainer
    if scroll then
        local _, ay = anchor:GetCenter()
        local _, sy = scroll:GetCenter()
        local below = not (ay and sy) or ay * anchor:GetEffectiveScale() >= sy * scroll:GetEffectiveScale()
        if below then card:SetPoint("TOP", anchor, "BOTTOM", 0, -6) else card:SetPoint("BOTTOM", anchor, "TOP", 0, 6) end
        card:SetClampedToScreen(false)
        -- (inside the map: nudged back when it runs past an edge)
        C_Timer.After(0, function()
            local l, r, sl, sr = card:GetLeft(), card:GetRight(), scroll:GetLeft(), scroll:GetRight()
            if l and sl and l < sl then card:AdjustPointsOffset(sl - l + 4, 0) end
            if r and sr and r > sr then card:AdjustPointsOffset(sr - r - 4, 0) end
        end)
    else
        card:SetPoint("TOP", anchor, "BOTTOM", 0, -6)
    end
end

function M:CloseCard()
    local card = self.card
    if not (card and card:IsShown()) then return end
    card.name.edit:ClearFocus()
    card.id = nil
    card:Hide()
    self.cardMark = nil
    self:Emit("SUUUI_MARKS_CHANGED")
end

--------------------------------------------------------------------------------
-- Ctrl+click on the world map
--------------------------------------------------------------------------------

-- (before the game's own waypoint, priority 90, which then never sees it)
local CLICK_PRIORITY = 100

function M:Hook()
    local f = _G.WorldMapFrame
    if not f or self.clickHandler then return end
    self.clickHandler = function(map, button, cx, cy)
        if not self:IsEnabled() or button ~= "LeftButton" then return false end
        -- a plain click elsewhere closes the card (and goes on to the map)
        if not IsControlKeyDown() then self:CloseCard() return false end
        local mapID = map:GetMapID()
        if not (mapID and plain(cx) and plain(cy)) then return false end
        local mark = self:Add(mapID, cx, cy, { symbol = self.lastSymbol or "star" })
        -- its card once its pin is there, the name to type
        C_Timer.After(0.05, function()
            local wm = SuuUI.GetModule("worldmap")
            local card = self:OpenCard(mark.id, wm and wm.PinForMark and wm:PinForMark(mark.id))
            if card then card.name.edit:SetFocus() end
        end)
        return true
    end
    f:AddCanvasClickHandler(self.clickHandler, CLICK_PRIORITY)
    -- the card goes with the map
    f:HookScript("OnHide", function() self:CloseCard() end)
    -- the game draws its own waypoint pin where its waypoint is: while that
    -- is a mark showing the way, the mark is drawn already (found in game:
    -- the two on top of each other); a waypoint of your own stays
    for provider in pairs(f.dataProviders or {}) do
        if provider.GetPinTemplate and provider:GetPinTemplate() == "WaypointLocationPinTemplate" then
            self.waypointProvider = provider
            hooksecurefunc(provider, "RefreshAllData", function(p) self:HideGamePin(p) end)
        end
    end
    -- a quiet hint after the header's waypoint pin: how to place one
    local pin = f.WorldMapTrackingPinButton
    if pin then
        local hint = UI.Text(pin, "caption", "ink-faint")
        hint:SetPoint("LEFT", pin, "RIGHT", 8, 0)
        hint:SetValue("Ctrl+click to place a mark")
        self.hint = hint
    end
end

function M:OnEnable()
    self:On("SUUUI_MARKS_CHANGED", function() self:UpdateMinimap() end)
    if C_ChatInfo and C_ChatInfo.RegisterAddonMessagePrefix then C_ChatInfo.RegisterAddonMessagePrefix(PREFIX) end
    self:OnGameEvent("CHAT_MSG_ADDON", function(_, ...) self:OnMessage(...) end)
    -- after a /reload: still following while the game kept its waypoint and
    -- the mark is there; else the setting back as it was
    local data = store(self)
    local kept = data.following and self:Get(data.following) and C_Map.HasUserWaypoint and C_Map.HasUserWaypoint()
        and C_SuperTrack and C_SuperTrack.IsSuperTrackingUserWaypoint and C_SuperTrack.IsSuperTrackingUserWaypoint()
    if kept then
        self.following = data.following
        navigation(self, true)
    else
        data.following = nil
        navigation(self, false)
    end
    if self.hint then self.hint:Show() end
    if _G.WorldMapFrame then
        self:Hook()
    else
        self:OnGameEvent("ADDON_LOADED", function() if _G.WorldMapFrame then self:Hook() end end)
    end
    -- the game's waypoint cleared or replaced: you're no longer following
    self:OnGameEvent("USER_WAYPOINT_UPDATED", function()
        -- (still on the followed mark? a waypoint of your own in its place ends it)
        local mark = self.following and self:Get(self.following)
        local wp = C_Map.GetUserWaypoint and C_Map.GetUserWaypoint()
        local onMark = mark and wp and wp.uiMapID == mark.map and wp.position
            and math.abs(wp.position.x - mark.x) < 0.001 and math.abs(wp.position.y - mark.y) < 0.001
        if self.following and not onMark then
            self.following = nil
            store(self).following = nil
            navigation(self, false)
            changed(self)
        end
    end)
    changed(self)
end

function M:OnDisable()
    if self.hint then self.hint:Hide() end
    self:CloseCard()
    if self.mmLayer then self.mmLayer:Hide() end
    changed(self)
end
