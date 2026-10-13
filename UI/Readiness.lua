-- UI/Readiness.lua
-- Readiness (design board "Insight · Readiness"): a glass panel 340px wide,
-- "Readiness" and "before pull" in its head, one row per shared cooldown:
-- its icon (dim while it cools down), the spell, who has it (class diamond
-- and name), and "Ready" in arcane or the time left. A Ready check button in
-- the foot for whoever may start one.
--
--   local r = UI.Readiness(parent, { onReadyCheck = fn })
--   r:SetRows({ { icon, spell, who, class, endsAt (GetTime() it's ready; nil: ready) }, ... })
--   r:SetActionShown(on)

local _, ns = ...

local UI, T = ns.UI, ns.Tokens
local S = T.space

local WIDTH = 340
local ROW_H = UI.Size("icon-md") + S["space-3"] * 2

local function fmtLeft(s)
    s = math.max(0, math.ceil(s))
    if s >= 60 then return ("%d:%02d"):format(math.floor(s / 60), s % 60) end
    return ("%ds"):format(s)
end

local Readiness = {}

local function buildRow(r, i)
    local row = CreateFrame("Frame", nil, r.body)
    row:SetSize(WIDTH - S["space-5"] * 2, ROW_H)
    row.rule = row:CreateTexture(nil, "BORDER")
    row.rule:SetColorTexture(UI.RGBA("gilt-faint"))
    row.rule:SetPoint("TOPLEFT")
    row.rule:SetPoint("TOPRIGHT")
    row.rule:SetHeight(1)
    row.icon = UI.Icon(row, "icon-md")
    row.icon:SetPoint("LEFT", 0, 0)
    row.spell = UI.Text(row, "label", "ink")
    row.spell:SetPoint("LEFT", row.icon, "RIGHT", S["space-4"], 0)
    row.spell:SetWordWrap(false)
    row.diamond = UI.Diamond(row, 5, "gilt")
    row.diamond:SetPoint("LEFT", row.spell, "RIGHT", S["space-4"] + 2, 0)
    row.who = UI.Text(row, "caption", "ink-muted")
    row.who:SetPoint("LEFT", row.diamond, "RIGHT", S["space-3"], 0)
    row.who:SetWordWrap(false)
    row.status = UI.Text(row, "label", "arcane")
    row.status:SetPoint("RIGHT", 0, 0)
    row.status:SetJustifyH("RIGHT")
    r.rows[i] = row
    return row
end

function Readiness:Update()
    local now = GetTime()
    for i, d in ipairs(self.data) do
        local row = self.rows[i]
        local left = d.endsAt and d.endsAt - now or 0
        if left > 0 then
            row.icon:SetState("dim")
            row.status:SetStyle("numeric")
            row.status:SetColor("ink-muted")
            row.status:SetValue(fmtLeft(left))
        else
            row.icon:SetState("rest")
            row.status:SetStyle("label")
            row.status:SetColor("arcane")
            row.status:SetValue("Ready")
        end
    end
end

function Readiness:SetRows(list)
    self.data = list or {}
    local y = 0
    for i, d in ipairs(self.data) do
        local row = self.rows[i] or buildRow(self, i)
        row:ClearAllPoints()
        row:SetPoint("TOPLEFT", 0, -y)
        row.rule:SetShown(i > 1)
        row.icon:SetArt(d.icon or 134400)
        row.spell:SetValue(d.spell or "")
        row.who:SetValue(d.who or "")
        local c = d.class and T.color["class-" .. d.class:lower()] and ("class-" .. d.class:lower())
        row.diamond:SetShown(c and true or false)
        if c then row.diamond:SetVertexColor(UI.RGBA(c)) end
        row:Show()
        y = y + ROW_H
    end
    for i = #self.data + 1, #self.rows do self.rows[i]:Hide() end
    self:Update()
    self:Layout(y)
end

function Readiness:SetActionShown(on)
    self.actionShown = on and true or false
    self:Layout(self.listH or 0)
end

function Readiness:Layout(listH)
    self.listH = listH
    local foot = 0
    self.footRule:SetShown(self.actionShown)
    self.action:SetShown(self.actionShown)
    if self.actionShown then
        self.footRule:ClearAllPoints()
        self.footRule:SetPoint("TOPLEFT", self.body, "TOPLEFT", 0, -(listH + S["space-4"]))
        self.footRule:SetPoint("TOPRIGHT", self.body, "TOPRIGHT", 0, -(listH + S["space-4"]))
        self.action:ClearAllPoints()
        self.action:SetPoint("TOPRIGHT", self.footRule, "BOTTOMRIGHT", 0, -S["space-4"])
        foot = S["space-4"] * 2 + 1 + 30
    end
    self.body:SetSize(WIDTH - S["space-5"] * 2, math.max(1, listH + foot))
    self:Fit()
end

function UI.Readiness(parent, opts)
    opts = opts or {}
    local r = UI.Panel(parent, { title = "Readiness", meta = "before pull", width = WIDTH })
    Mixin(r, Readiness)
    r.rows, r.data = {}, {}
    r.footRule = r.body:CreateTexture(nil, "BORDER")
    r.footRule:SetColorTexture(UI.RGBA("gilt-faint"))
    r.footRule:SetHeight(1)
    r.action = UI.Button(r.body, { variant = "primary", text = "Ready check",
        onClick = function() if opts.onReadyCheck then opts.onReadyCheck() end end })
    r.actionShown = false
    local wait = 0
    r:SetScript("OnUpdate", function(self, elapsed)
        wait = wait - elapsed
        if wait > 0 then return end
        wait = 0.5
        self:Update()
    end)
    r:SetRows({})
    return r
end
