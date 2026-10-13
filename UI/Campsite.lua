-- UI/Campsite.lua
-- The campfire strip (design board "Campfire strip"): a small panel with
-- the fire glyph and a header for the phase, then what the phase holds:
--   nearby   "Campfire nearby" and how to rest
--   resting  "Resting by the fire", the time left and a bar filling up
--   rested   "Rested at the fire", the time left, the benefits (icon,
--            name, what they do)
-- and the camp cooldowns along the foot (hourglass, name, time).
--
--   local c = UI.Campsite(parent)
--   c:SetData({ phase, remaining = "0:42", progress = 0.3,
--               benefits = { { icon, label, effect } },
--               cooldowns = { { label, remaining } } })

local _, ns = ...

local UI, T = ns.UI, ns.Tokens
local S = T.space

local GLYPHS = "Interface\\AddOns\\SuuUI\\Media\\Textures\\Glyphs\\"
local WIDTH = 290
local PAD = S["space-4"]
local INNER = WIDTH - PAD * 2
local TITLES = { nearby = "Campfire nearby", resting = "Resting by the fire", rested = "Rested at the fire" }
local HINTS = {
    nearby = "Sit, kneel or lie down here for a minute to gain an hour of Camp Benefits.",
    resting = "Stay seated; you can still cast, craft and buff others.",
}

local Camp = {}

local function benefitRow(c, i)
    local r = c.rows[i]
    if r then return r end
    r = CreateFrame("Frame", nil, c)
    r:SetWidth(INNER)
    r.icon = UI.Icon(r, UI.Size("icon-md"))
    r.icon:SetPoint("TOPLEFT")
    r.label = UI.Text(r, "label", "ink")
    r.label:SetPoint("TOPLEFT", r.icon, "TOPRIGHT", S["space-4"], 0)
    r.label:SetPoint("RIGHT")
    r.effect = UI.Text(r, "caption", "ink-muted")
    r.effect:SetPoint("TOPLEFT", r.label, "BOTTOMLEFT", 0, -S["space-1"])
    r.effect:SetWidth(INNER - UI.Size("icon-md") - S["space-4"])
    r.effect:SetWordWrap(true)
    r.effect:SetJustifyH("LEFT")
    c.rows[i] = r
    return r
end

local function cooldownRow(c, i)
    local r = c.cds[i]
    if r then return r end
    r = CreateFrame("Frame", nil, c)
    r:SetSize(INNER, T.type.caption.lineHeight)
    r.glyph = r:CreateTexture(nil, "ARTWORK")
    r.glyph:SetTexture(GLYPHS .. "hourglass.tga")
    r.glyph:SetSize(12, 12)
    r.glyph:SetPoint("LEFT")
    r.glyph:SetVertexColor(UI.RGBA("ink-muted"))
    r.label = UI.Text(r, "caption", "ink-muted")
    r.label:SetPoint("LEFT", r.glyph, "RIGHT", S["space-3"], 0)
    r.time = UI.Text(r, "numeric", "ink")
    r.time:SetPoint("RIGHT")
    c.cds[i] = r
    return r
end

function Camp:SetData(d)
    local phase = d.phase or "nearby"
    self.title:SetValue(TITLES[phase] or TITLES.nearby)
    self.time:SetValue((phase ~= "nearby" and d.remaining) or "")
    local y = PAD + 22
    local function place(f, h)
        y = y + S["space-3"]
        f:ClearAllPoints()
        f:SetPoint("TOPLEFT", PAD, -y)
        f:Show()
        y = y + h
    end
    -- the resting bar
    if phase == "resting" then
        self.bar.fill:SetWidth(math.max(0.01, INNER * math.max(0, math.min(1, d.progress or 0))))
        place(self.bar, 6)
    else
        self.bar:Hide()
    end
    -- the hint
    local hint = HINTS[phase]
    if hint then
        self.hint:SetValue(hint)
        local h = math.ceil(self.hint:GetStringHeight())
        self.hintRow:SetHeight(h)
        place(self.hintRow, h)
    else
        self.hintRow:Hide()
    end
    -- the benefits
    local benefits = (phase == "rested" and d.benefits) or {}
    for i, b in ipairs(benefits) do
        local r = benefitRow(self, i)
        r.icon:SetArt(b.icon)
        r.label:SetValue(b.label or "")
        r.effect:SetValue(b.effect or "")
        local h = math.max(UI.Size("icon-md"), T.type.label.lineHeight + S["space-1"] + math.ceil(r.effect:GetStringHeight()))
        r:SetHeight(h)
        place(r, h)
    end
    for i = #benefits + 1, #self.rows do self.rows[i]:Hide() end
    -- the cooldowns
    local cds = d.cooldowns or {}
    for i, cd in ipairs(cds) do
        local r = cooldownRow(self, i)
        r.label:SetValue(cd.label or "")
        r.time:SetValue(cd.remaining or "")
        place(r, T.type.caption.lineHeight)
    end
    for i = #cds + 1, #self.cds do self.cds[i]:Hide() end
    self:SetHeight(y + PAD)
end

-- Only the times, between full updates.
function Camp:SetTimes(remaining, progress, cooldownTimes)
    self.time:SetValue(remaining or "")
    if progress and self.bar:IsShown() then
        self.bar.fill:SetWidth(math.max(0.01, INNER * math.max(0, math.min(1, progress))))
    end
    for i, t in ipairs(cooldownTimes or {}) do
        if self.cds[i] then self.cds[i].time:SetValue(t) end
    end
end

function UI.Campsite(parent)
    local c = UI.Panel(parent, { ornament = true, width = WIDTH, height = 60 })
    Mixin(c, Camp)
    c.rows, c.cds = {}, {}
    c.fire = c:CreateTexture(nil, "ARTWORK")
    c.fire:SetTexture(GLYPHS .. "campfire.tga")
    c.fire:SetSize(18, 18)
    c.fire:SetPoint("TOPLEFT", PAD, -(PAD + 2))
    c.fire:SetVertexColor(UI.RGBA("gilt"))
    c.title = UI.Text(c, "header", "gilt-text")
    c.title:SetPoint("LEFT", c.fire, "RIGHT", S["space-3"], 0)
    c.time = UI.Text(c, "numeric", "ink")
    c.time:SetPoint("RIGHT", c, "TOPRIGHT", -PAD, -(PAD + 11))
    c.bar = CreateFrame("Frame", nil, c)
    c.bar:SetSize(INNER, 6)
    UI.Fill(c.bar, "track"):SetAllPoints()
    c.bar.fill = UI.Fill(c.bar, "progress-fill", "ARTWORK")
    c.bar.fill:SetPoint("TOPLEFT")
    c.bar.fill:SetPoint("BOTTOMLEFT")
    c.hintRow = CreateFrame("Frame", nil, c)
    c.hintRow:SetWidth(INNER)
    c.hint = UI.Text(c.hintRow, "caption", "ink-muted")
    c.hint:SetPoint("TOPLEFT")
    c.hint:SetWidth(INNER)
    c.hint:SetWordWrap(true)
    c.hint:SetJustifyH("LEFT")
    c:SetData({ phase = "nearby" })
    return c
end
