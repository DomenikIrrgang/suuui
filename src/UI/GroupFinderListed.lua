-- UI/GroupFinderListed.lua
-- The Group Finder's My listing page (design component GroupFinder,
-- "My listing"; GroupAdComposer): while you're listed, the second tab shows
-- your listing and an ad for chat side by side.
--   Your listing: a sunk card: "Listed", how long and how long it has left,
--   the category and activities, your roles (icons and words), play style,
--   details, voice chat; Delist and Update (primary: the game's panel).
--   Advertise in chat: the channel (180 wide), the ad in a sunk field you
--   can edit, From my listing (writes it again) and the count ("92 / 255";
--   over the limit the edge is ember and Post is off), "Last posted 6m ago"
--   and Post to <channel> (primary). Posting is always your click.
--
--   local p = UI.GroupFinderListed(parent)
--   p:SetData({
--       listing = { listedFor = "12m", left = "18m", category = "Dungeons",
--                   activities = { "Shadowfang Keep", ... }, roles = { "healer", "tank" },
--                   playstyle = "Relaxed", comment = "…", voice = "None" },
--       ad = { text = "…", channel = "LookingForGroup", channels = { { value, label } },
--              lastPost = "6m" | nil, max = 255 },
--   })
--   p.onDelist(), p.onUpdate(), p.onChannel(value), p.onText(text),
--   p.onRewrite(), p.onPost(channel, text)

local _, ns = ...

local UI, T = ns.UI, ns.Tokens
local S = T.space

local TEX = "Interface\\AddOns\\SuuUI\\Media\\Textures\\"
local GLYPHS = TEX .. "Glyphs\\"
local ROLE_TEX = { tank = TEX .. "RoleTank.tga", healer = TEX .. "RoleHealer.tga", damage = TEX .. "RoleDamage.tga" }
local ROLE_WORD = { tank = "Tank", healer = "Healer", damage = "Damage" }

local PAD = S["space-5"]
local GAP = S["space-4"]
local DT_W = 96
local BTN_H = 26
local FIELD_LINES = 5
local LINE_H = 18

local P = {}

-- A sunk card: surface-sunk in a gilt-faint edge.
local function card(parent)
    local c = CreateFrame("Frame", nil, parent)
    UI.Fill(c, "surface-sunk"):SetAllPoints()
    UI.Border(c, "gilt-faint")
    return c
end

local function rule(parent)
    local t = UI.Fill(parent, "gilt-faint", "ARTWORK")
    t:SetHeight(1)
    return t
end

-- One fact: the term at the left (96), its text beside it.
local function fact(c)
    local f = {}
    f.dt = UI.Text(c, "caption", "ink-muted")
    f.dt:SetJustifyH("LEFT")
    f.dd = UI.Text(c, "body", "ink")
    f.dd:SetJustifyH("LEFT")
    f.dd:SetWordWrap(true)
    return f
end

function P:SetData(d)
    self.data = d
    local L = d.listing or {}
    local c = self.listing
    c.time:SetValue("for " .. (L.listedFor or "a moment") .. (L.left and (" · runs out in " .. L.left) or ""))
    local width = c:GetWidth() - PAD * 2 - DT_W - GAP
    local y = PAD + T.type.header.lineHeight + GAP
    local rows = {
        { L.category or "Activities", table.concat(L.activities or {}, " · ") },
        { "Your roles", "" , true },
        { "Playstyle", L.playstyle },
        { "Details", L.comment ~= "" and L.comment or nil },
        { "Voice Chat", L.voice },
    }
    for i, r in ipairs(rows) do
        local f = c.facts[i]
        local show = r[3] or (r[2] and r[2] ~= "")
        f.dt:SetShown(show and true or false)
        f.dd:SetShown(show and true or false)
        if show then
            f.dt:SetValue(r[1])
            f.dt:ClearAllPoints()
            f.dt:SetPoint("TOPLEFT", c, "TOPLEFT", PAD, -y - 2)
            f.dd:ClearAllPoints()
            f.dd:SetPoint("TOPLEFT", c, "TOPLEFT", PAD + DT_W + GAP, -y)
            f.dd:SetWidth(math.max(40, width))
            local h
            if r[3] then
                -- the roles: icons, then their words
                local x = PAD + DT_W + GAP
                for k, role in ipairs({ "tank", "healer", "damage" }) do c.roleIcons[k]:Hide() end
                local words = {}
                for k, role in ipairs(L.roles or {}) do
                    local ic = c.roleIcons[k]
                    ic.glyph:SetTexture(ROLE_TEX[role])
                    ic:ClearAllPoints()
                    ic:SetPoint("TOPLEFT", c, "TOPLEFT", x, -y)
                    ic:Show()
                    x = x + 18 + S["space-2"]
                    words[#words + 1] = ROLE_WORD[role]
                end
                f.dd:ClearAllPoints()
                f.dd:SetPoint("TOPLEFT", c, "TOPLEFT", x + S["space-2"], -y)
                f.dd:SetValue(#words > 0 and table.concat(words, ", ") or "None chosen")
                h = 18
            else
                f.dd:SetValue(r[2])
                h = math.max(T.type.body.lineHeight, math.ceil(f.dd:GetStringHeight()))
            end
            y = y + h + GAP
        end
    end
    -- the buttons, under a rule
    c.rule:ClearAllPoints()
    c.rule:SetPoint("TOPLEFT", c, "TOPLEFT", PAD, -y)
    c.rule:SetPoint("TOPRIGHT", c, "TOPRIGHT", -PAD, -y)
    y = y + GAP
    c.update:ClearAllPoints()
    c.update:SetPoint("TOPRIGHT", c, "TOPRIGHT", -PAD, -y)
    c.delist:ClearAllPoints()
    c.delist:SetPoint("RIGHT", c.update, "LEFT", -S["space-3"], 0)
    c:SetHeight(y + BTN_H + PAD)

    -- the ad
    local A = d.ad or {}
    local a = self.ad
    a.channel:SetOptions(A.channels or {})
    a.channel:SetValue(A.channel)
    if not a.edit:HasFocus() and a.edit:GetText() ~= (A.text or "") then
        a.edit:SetText(A.text or "")
        a.edit:SetCursorPosition(0)
    end
    a.post:SetLabel("Post to " .. (A.channel or "chat"))
    a.last:SetValue(A.lastPost and ("Last posted " .. A.lastPost .. " ago") or "Not posted yet")
    self:Count()
end

-- The count, and what being over the limit turns off.
function P:Count()
    local a = self.ad
    local max = (self.data and self.data.ad and self.data.ad.max) or 255
    local text = a.edit:GetText() or ""
    local n = strlenutf8 and strlenutf8(text) or #text
    local over = n > max
    a.count:SetValue(n .. " / " .. max)
    a.count:SetColor(over and "ember-text" or "ink-faint")
    a.fieldEdge:SetColor(over and "ember" or (a.edit:HasFocus() and "arcane" or "gilt-line"))
    a.post:SetEnabledState(not over and text:match("%S") ~= nil)
end

function UI.GroupFinderListed(parent)
    local p = CreateFrame("Frame", nil, parent)
    Mixin(p, P)

    -- your listing
    local c = card(p)
    c:SetPoint("TOPLEFT")
    c:SetPoint("RIGHT", p, "CENTER", -S["space-6"] / 2, 0)
    c.dot = UI.Diamond(c, 6, "arcane")
    c.dot:SetPoint("CENTER", c, "TOPLEFT", PAD + 3, -(PAD + T.type.header.lineHeight / 2))
    c.title = UI.Text(c, "header", "gilt-text")
    c.title:SetPoint("LEFT", c, "TOPLEFT", PAD + 6 + S["space-3"], -(PAD + T.type.header.lineHeight / 2))
    c.title:SetValue("Listed")
    c.time = UI.Text(c, "caption", "ink-muted")
    c.time:SetPoint("RIGHT", c, "TOPRIGHT", -PAD, -(PAD + T.type.header.lineHeight / 2))
    c.facts = {}
    for i = 1, 5 do c.facts[i] = fact(c) end
    c.roleIcons = {}
    for i = 1, 3 do
        local ic = CreateFrame("Frame", nil, c)
        ic:SetSize(18, 18)
        UI.Fill(ic, "surface-raised"):SetAllPoints()
        UI.Border(ic, "gilt-line")
        ic.glyph = ic:CreateTexture(nil, "ARTWORK")
        ic.glyph:SetSize(12, 12)
        ic.glyph:SetPoint("CENTER")
        ic.glyph:SetVertexColor(UI.RGBA("ink"))
        ic:Hide()
        c.roleIcons[i] = ic
    end
    c.rule = rule(c)
    c.update = UI.Button(c, { text = "Update", variant = "primary", icon = "scroll",
        tooltip = { title = "Update", description = "Change your listing in the game’s panel" },
        onClick = function() if p.onUpdate then p.onUpdate() end end })
    c.update:SetHeight(BTN_H)
    c.delist = UI.Button(c, { text = "Delist", icon = "close",
        tooltip = { title = "Delist", description = "Take your listing down" },
        onClick = function() if p.onDelist then p.onDelist() end end })
    c.delist:SetHeight(BTN_H)
    p.listing = c

    -- the ad
    local a = card(p)
    a:SetPoint("TOPRIGHT")
    a:SetPoint("LEFT", p, "CENTER", S["space-6"] / 2, 0)
    a.glyph = a:CreateTexture(nil, "ARTWORK")
    a.glyph:SetTexture(GLYPHS .. "chat.tga")
    a.glyph:SetSize(14, 14)
    a.glyph:SetVertexColor(UI.RGBA("gilt-text"))
    a.glyph:SetPoint("CENTER", a, "TOPLEFT", PAD + 7, -(PAD + T.type.header.lineHeight / 2))
    a.title = UI.Text(a, "header", "gilt-text")
    a.title:SetPoint("LEFT", a.glyph, "RIGHT", S["space-3"], 0)
    a.title:SetValue("Advertise in chat")
    local y = PAD + T.type.header.lineHeight + GAP
    a.intro = UI.Text(a, "caption", "ink-muted")
    a.intro:SetPoint("TOPLEFT", a, "TOPLEFT", PAD, -y)
    a.intro:SetPoint("RIGHT", a, "RIGHT", -PAD, 0)
    a.intro:SetJustifyH("LEFT")
    a.intro:SetWordWrap(true)
    a.intro:SetValue("Your listing as one chat line. Edit it if you like; it goes only when you click Post.")
    y = y + T.type.caption.lineHeight * 2 + GAP
    a.channelLabel = UI.Text(a, "caption", "ink-muted")
    a.channelLabel:SetPoint("LEFT", a, "TOPLEFT", PAD, -(y + 15))
    a.channelLabel:SetValue("Channel")
    a.channel = UI.Select(a, { width = 180, onChange = function(v) if p.onChannel then p.onChannel(v) end end })
    a.channel:SetPoint("TOPLEFT", a, "TOPLEFT", PAD + 56, -y)
    y = y + 30 + GAP
    -- the ad's field: several lines
    a.field = CreateFrame("Frame", nil, a)
    a.field:SetPoint("TOPLEFT", a, "TOPLEFT", PAD, -y)
    a.field:SetPoint("RIGHT", a, "RIGHT", -PAD, 0)
    a.field:SetHeight(FIELD_LINES * LINE_H + S["space-3"] * 2)
    UI.Fill(a.field, "surface-sunk"):SetAllPoints()
    a.fieldEdge = UI.Border(a.field, "gilt-line")
    local e = CreateFrame("EditBox", nil, a.field)
    e:SetMultiLine(true)
    e:SetAutoFocus(false)
    -- room past the 255 a post may have (the count turns ember there);
    -- 0 cut every text to nothing (found in game)
    e:SetMaxLetters(1000)
    e:SetFontObject(ns.Fonts.Get("body"))
    e:SetTextColor(UI.RGBA("ink"))
    e:SetPoint("TOPLEFT", S["space-4"], -S["space-3"])
    e:SetPoint("BOTTOMRIGHT", -S["space-4"], S["space-3"])
    e:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    e:SetScript("OnEditFocusGained", function() p:Count() end)
    e:SetScript("OnEditFocusLost", function() p:Count() end)
    e:SetScript("OnTextChanged", function(self, user)
        p:Count()
        if user and p.onText then p.onText(self:GetText()) end
    end)
    a.field:EnableMouse(true)
    a.field:SetScript("OnMouseDown", function() e:SetFocus() end)
    a.edit = e
    y = y + a.field:GetHeight() + S["space-2"]
    a.rewrite = UI.Button(a, { text = "From my listing", icon = "reset",
        tooltip = { title = "From my listing", description = "Write it again from your listing" },
        onClick = function() if p.onRewrite then p.onRewrite() end end })
    a.rewrite:SetHeight(22)
    a.rewrite:SetPoint("TOPLEFT", a, "TOPLEFT", PAD, -y)
    a.count = UI.Text(a, "caption", "ink-faint")
    a.count:SetPoint("RIGHT", a, "TOPRIGHT", -PAD, -(y + 11))
    y = y + 22 + GAP
    a.rule = rule(a)
    a.rule:SetPoint("TOPLEFT", a, "TOPLEFT", PAD, -y)
    a.rule:SetPoint("TOPRIGHT", a, "TOPRIGHT", -PAD, -y)
    y = y + GAP
    a.last = UI.Text(a, "caption", "ink-muted")
    a.last:SetPoint("LEFT", a, "TOPLEFT", PAD, -(y + BTN_H / 2))
    a.post = UI.Button(a, { text = "Post", variant = "primary", icon = "chat",
        onClick = function()
            local d = p.data and p.data.ad
            if p.onPost and d then p.onPost(d.channel, e:GetText()) end
        end })
    a.post:SetHeight(BTN_H)
    a.post:SetPoint("TOPRIGHT", a, "TOPRIGHT", -PAD, -y)
    a:SetHeight(y + BTN_H + PAD)
    p.ad = a
    p:HookScript("OnSizeChanged", function() if p.data then p:SetData(p.data) end end)
    return p
end
