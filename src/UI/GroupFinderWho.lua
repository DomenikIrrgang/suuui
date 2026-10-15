-- UI/GroupFinderWho.lua
-- The Group Finder's Who page (design component GroupFinder, "Who"): who is
-- online, by name, guild, zone or level range.
--   The bar: the search field (300), Search (primary), Filter (the game's
--   own menu: Class, Race, Zone, Sort), "24 players found" at the right
--   ("· showing the first 50" when the server caps it).
--   The list: a sunk box with Name (a class diamond, the name in class
--   colour), Level, Race, Class, <Guild>, Zone; 24px rows; the selected one
--   arcane-soft with an arcane edge; right-click for the game's player menu.
--   Before a search: "Who is online?"; nothing found: "No players found".
--   The foot: Add friend, then Whisper and Invite (primary), for the
--   selected player (off until one is chosen).
--
--   local w = UI.GroupFinderWho(parent)
--   w:SetData({ state = "idle" | "results" | "none", query = "", total = n, capped = bool,
--               results = { { name, level, race, class (file), className, guild, zone } } })
--   w.onSearch(text), w.onFilter(button), w.onAddFriend(row), w.onWhisper(row),
--   w.onInvite(row), w.onMenu(row)

local _, ns = ...

local UI, T = ns.UI, ns.Tokens
local S = T.space

local GLYPHS = "Interface\\AddOns\\SuuUI\\Media\\Textures\\Glyphs\\"

local BAR_H = 30
local HEAD_H = 22
local ROW_H = 24
local FOOT_H = 26
local LEVEL_W = 44
-- the columns' shares of what's left (Name, Race, Class, Guild, Zone)
local SHARES = { name = 24, race = 14, class = 14, guild = 26, zone = 26 }
local ORDER = { "name", "level", "race", "class", "guild", "zone" }
local LABEL = { name = "Name", level = "Level", race = "Race", class = "Class", guild = "Guild", zone = "Zone" }

local W = {}

-- Each column's x and width in a row this wide.
local function columns(width)
    local gap = S["space-4"]
    local inner = width - S["space-5"] - S["space-4"] - gap * 5 - LEVEL_W
    local total = 0
    for _, v in pairs(SHARES) do total = total + v end
    local out, x = {}, S["space-5"]
    for _, key in ipairs(ORDER) do
        local w = key == "level" and LEVEL_W or math.floor(inner * SHARES[key] / total)
        out[key] = { x = x, w = w }
        x = x + w + gap
    end
    return out
end

local function cell(parent, style, color)
    local fs = UI.Text(parent, style, color)
    fs:SetWordWrap(false)
    fs:SetJustifyH("LEFT")
    return fs
end

local function makeRow(w)
    local r = CreateFrame("Button", nil, w.list.child)
    r:SetHeight(ROW_H)
    r:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    r.selected = UI.Fill(r, "arcane-soft", "BACKGROUND")
    r.selected:SetAllPoints()
    r.edge = UI.Fill(r, "arcane", "ARTWORK")
    r.edge:SetWidth(2)
    r.edge:SetPoint("TOPLEFT")
    r.edge:SetPoint("BOTTOMLEFT")
    r.hover = UI.Fill(r, "gilt-faint", "BACKGROUND", 1)
    r.hover:SetAllPoints()
    r.hover:Hide()
    r.dia = UI.Diamond(r, 6, "ink")
    r.name = cell(r, "label", "ink")
    r.level = cell(r, "caption", "ink")
    r.level:SetJustifyH("RIGHT")
    r.race = cell(r, "caption", "ink")
    r.class = cell(r, "caption", "ink")
    r.guild = cell(r, "caption", "ink")
    r.zone = cell(r, "caption", "ink")
    r:SetScript("OnEnter", function(self) self.hover:Show() end)
    r:SetScript("OnLeave", function(self) self.hover:Hide() end)
    r:SetScript("OnClick", function(self, button)
        if not self.data then return end
        if button == "RightButton" then
            if w.onMenu then w.onMenu(self.data) end
        else
            w.selected = self.index
            w:Draw()
        end
    end)
    return r
end

function W:SetData(d)
    self.data = d
    -- a new search: nothing chosen
    if d.results ~= self.lastResults then self.selected = nil end
    self.lastResults = d.results
    local count
    if d.state ~= "idle" then
        local n = d.total or #(d.results or {})
        count = n .. (n == 1 and " player found" or " players found") .. ((d.capped or n > 50) and " · showing the first 50" or "")
    end
    self.count:SetValue(count or "")
    self:Draw()
end

function W:Draw()
    local d = self.data or { state = "idle" }
    local width = math.max(1, self.list:GetWidth())
    self.list.child:SetWidth(width)
    local cols = columns(self.box:GetWidth())
    for _, key in ipairs(ORDER) do
        local h = self.heads[key]
        h:ClearAllPoints()
        h:SetPoint("LEFT", self.headRow, "LEFT", cols[key].x, 0)
        h:SetWidth(cols[key].w)
    end
    local rows = d.state == "results" and d.results or {}
    for i, row in ipairs(rows) do
        local r = self.rows[i] or makeRow(self)
        self.rows[i] = r
        r.index, r.data = i, row
        r:ClearAllPoints()
        r:SetPoint("TOPLEFT", self.list.child, "TOPLEFT", 0, -(i - 1) * ROW_H)
        r:SetWidth(width)
        local on = self.selected == i
        r.selected:SetShown(on)
        r.edge:SetShown(on)
        local token = row.class and T.color["class-" .. row.class:lower()] and ("class-" .. row.class:lower()) or "ink"
        r.dia:SetVertexColor(UI.RGBA(token))
        r.dia:ClearAllPoints()
        r.dia:SetPoint("CENTER", r, "LEFT", cols.name.x - 8, 0)
        local function place(fs, key, text)
            fs:ClearAllPoints()
            fs:SetPoint("LEFT", r, "LEFT", cols[key].x, 0)
            fs:SetWidth(cols[key].w)
            fs:SetValue(text or "")
        end
        place(r.name, "name", row.name)
        r.name:SetColor(token)
        place(r.level, "level", row.level and tostring(row.level) or "")
        place(r.race, "race", row.race)
        place(r.class, "class", row.className)
        place(r.guild, "guild", (row.guild and row.guild ~= "") and ("<" .. row.guild .. ">") or "")
        place(r.zone, "zone", row.zone)
        r:Show()
    end
    for i = #rows + 1, #self.rows do self.rows[i]:Hide() end
    self.list.child:SetHeight(math.max(1, #rows * ROW_H))
    -- before a search, or nothing found
    local empty = d.state ~= "results"
    self.empty:SetShown(empty)
    if empty then
        local none = d.state == "none"
        self.empty.title:SetValue(none and "No players found" or "Who is online?")
        self.empty.text:SetValue(none
            and ("Nobody online matches “" .. (d.query or "") .. "” and your filters. Try fewer words, or check the Filter menu.")
            or "Search for players by name, guild, zone or level range, e.g. 20-30")
    end
    -- the foot acts on the chosen player
    local chosen = self.selected and rows[self.selected]
    for _, b in ipairs({ self.addFriend, self.whisper, self.invite }) do
        b:SetEnabledState(chosen ~= nil)
        b.tooltip = not chosen and { title = b.label:GetText(), description = "Choose a player first" } or nil
    end
end

function W:Chosen()
    local d = self.data
    return d and d.state == "results" and self.selected and d.results[self.selected] or nil
end

function UI.GroupFinderWho(parent)
    local w = CreateFrame("Frame", nil, parent)
    Mixin(w, W)
    w.rows, w.heads = {}, {}
    -- the bar
    local function search() if w.onSearch then w.onSearch(w.query:GetValue()) end end
    w.query = UI.TextField(w, { width = 300, placeholder = "Search Name, Guilds, Levels", onChange = function() end })
    w.query:SetPoint("TOPLEFT")
    w.query.edit:HookScript("OnEnterPressed", search)
    w.search = UI.Button(w, { text = "Search", variant = "primary", icon = "search", onClick = search })
    w.search:SetHeight(BAR_H)
    w.search:SetPoint("LEFT", w.query, "RIGHT", S["space-4"], 0)
    w.filter = UI.Button(w, { text = "Filter", icon = "filter",
        onClick = function(self) if w.onFilter then w.onFilter(self) end end })
    w.filter:SetHeight(BAR_H)
    w.filter:SetPoint("LEFT", w.search, "RIGHT", S["space-4"], 0)
    w.filter.chev = UI.Chevron(w.filter, "ink-muted")
    w.filter.chev:SetPoint("RIGHT", -S["space-4"], 0)
    w.filter:SetWidth(w.filter:GetWidth() + 12 + S["space-1"])
    w.filter.label:SetPoint("CENTER", w.filter.shift - 7, 0)
    w.count = UI.Text(w, "caption", "ink-muted")
    w.count:SetPoint("RIGHT", w, "TOPRIGHT", 0, -BAR_H / 2)
    -- the list
    w.box = CreateFrame("Frame", nil, w)
    w.box:SetPoint("TOPLEFT", 0, -(BAR_H + S["space-4"]))
    w.box:SetPoint("BOTTOMRIGHT", 0, FOOT_H + S["space-4"])
    UI.Fill(w.box, "surface-sunk"):SetAllPoints()
    UI.Border(w.box, "gilt-faint")
    w.headRow = CreateFrame("Frame", nil, w.box)
    w.headRow:SetPoint("TOPLEFT", 1, -1)
    w.headRow:SetPoint("TOPRIGHT", -1, -1)
    w.headRow:SetHeight(HEAD_H)
    local rule = UI.Fill(w.headRow, "gilt-faint", "ARTWORK")
    rule:SetHeight(1)
    rule:SetPoint("BOTTOMLEFT")
    rule:SetPoint("BOTTOMRIGHT")
    for _, key in ipairs(ORDER) do
        local h = cell(w.headRow, "caption", "ink-muted")
        if key == "level" then h:SetJustifyH("RIGHT") end
        h:SetValue(LABEL[key])
        w.heads[key] = h
    end
    w.list = UI.ScrollArea(w.box, 2)
    w.list:SetPoint("TOPLEFT", w.headRow, "BOTTOMLEFT", 0, 0)
    w.list:SetPoint("BOTTOMRIGHT", -S["space-2"], S["space-2"])
    w.list:HookScript("OnSizeChanged", function() w:Draw() end)
    -- empty
    local e = CreateFrame("Frame", nil, w.box)
    e:SetSize(380, 100)
    e:SetPoint("CENTER", 0, -HEAD_H / 2)
    e.glyph = e:CreateTexture(nil, "ARTWORK")
    e.glyph:SetTexture(GLYPHS .. "search.tga")
    e.glyph:SetSize(24, 24)
    e.glyph:SetVertexColor(UI.RGBA("ink-faint"))
    e.glyph:SetPoint("TOP")
    e.title = UI.Text(e, "label", "ink")
    e.title:SetPoint("TOP", e.glyph, "BOTTOM", 0, -S["space-3"])
    e.text = UI.Text(e, "caption", "ink-muted")
    e.text:SetWidth(380)
    e.text:SetJustifyH("CENTER")
    e.text:SetPoint("TOP", e.title, "BOTTOM", 0, -S["space-3"])
    w.empty = e
    -- the foot
    local function act(name) return function() local c = w:Chosen(); if c and w[name] then w[name](c) end end end
    w.addFriend = UI.Button(w, { text = "Add friend", icon = "userPlus", onClick = act("onAddFriend") })
    w.addFriend:SetHeight(FOOT_H)
    w.addFriend:SetPoint("BOTTOMLEFT")
    w.invite = UI.Button(w, { text = "Invite", variant = "primary", icon = "plus", onClick = act("onInvite") })
    w.invite:SetHeight(FOOT_H)
    w.invite:SetPoint("BOTTOMRIGHT")
    w.whisper = UI.Button(w, { text = "Whisper", icon = "chat", onClick = act("onWhisper") })
    w.whisper:SetHeight(FOOT_H)
    w.whisper:SetPoint("RIGHT", w.invite, "LEFT", -S["space-3"], 0)
    -- disabled, they still say why
    for _, b in ipairs({ w.addFriend, w.whisper, w.invite }) do b:SetMotionScriptsWhileDisabled(true) end
    w:SetData({ state = "idle" })
    return w
end
