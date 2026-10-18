-- UI/Alert.lua
-- An alert (design board "Alerts and badges"): a title in the display face
-- over a detail caption, centred, between a 1px rule above and below, with a
-- 9px diamond on each end of the band.
--
--   local a = UI.Alert(parent)
--   a:SetAlert(tone, title, detail[, ...])
--
-- tone: "danger" (ember-soft ground, ember rules and glow, ember-text title),
-- "warning" (glass ground, amber rules and title) or "info" (glass ground,
-- gilt-line rules, gilt diamonds, gilt-text title). The detail is a format
-- string when arguments follow (a target's name may be secret in a dungeon):
-- they go to SetFormattedText untouched. A detail with a secret argument
-- can't be measured, so the band then takes at least `notice-w` plus space-6
-- either side, and a longer detail is cut. A plain detail may hold several
-- lines ("\n"): the band grows down, as wide as the longest (0.12).

local _, ns = ...

local UI, T = ns.UI, ns.Tokens
local S = T.space

local isSecret = issecretvalue or function() return false end

local TONES = {
    danger = { ground = "ember-soft", line = "ember", jewel = "ember", title = "ember-text", glow = true },
    warning = { ground = "surface-glass", line = "amber", jewel = "amber", title = "amber" },
    info = { ground = "surface-glass", line = "gilt-line", jewel = "gilt", title = "gilt-text" },
}
local JEWEL = 9

local Alert = {}

function Alert:SetTone(tone)
    local t = TONES[tone] or TONES.danger
    self.tone = TONES[tone] and tone or "danger"
    UI.PaintFill(self.ground, t.ground)
    self.rules:SetColor(t.line)
    UI.Paint(self.left, t.jewel)
    UI.Paint(self.right, t.jewel)
    self.title:SetColor(t.title)
    self.glow:SetShown(t.glow and true or false)
end

-- The detail: plain text, or a format with arguments (secret ones allowed).
-- Returns the text to measure, or nil when an argument is secret.
local function setDetail(self, detail, ...)
    local n = select("#", ...)
    local secret = false
    for i = 1, n do
        if isSecret((select(i, ...))) then secret = true; break end
    end
    if not detail or detail == "" then
        self.detail:SetVisible(false)
        return ""
    end
    self.detail:SetVisible(true)
    if n > 0 then
        self.detail:SetFormattedText(detail, ...)
        self.detail.value = nil
    else
        self.detail:SetValue(detail)
    end
    if secret then return nil end
    return n > 0 and detail:format(...) or detail
end

-- The band's size from the title and the readable detail (nil: secret);
-- again after a theme changed the text styles.
function Alert:Fit()
    local text = self.detailText
    local detailW, lines
    if text then
        detailW, lines = 0, 0
        for line in (text .. "\n"):gmatch("(.-)\n") do
            lines = lines + 1
            detailW = math.max(detailW, UI.MeasureText("caption", line))
        end
    end
    lines = lines or 1
    local titleW = UI.MeasureText("alert", self.titleText)
    local inner = math.max(titleW, detailW or UI.Size("notice-w"))
    -- a secret detail: fixed width, cut at the band's edge; several lines:
    -- as wide as the longest, centred
    if lines > 1 then
        self.detail:SetWidth(math.ceil(detailW) + 2)
        self.detail:SetWordWrap(true)
    else
        self.detail:SetWidth(detailW and 0 or inner)
        self.detail:SetWordWrap(false)
    end
    local h = S["space-4"] * 2 + T.type.alert.lineHeight
    if self.detail:IsShown() then h = h + S["space-1"] + T.type.caption.lineHeight * lines end
    self:SetSize(math.ceil(inner) + S["space-6"] * 2, h)
end

local alerts = setmetatable({}, { __mode = "k" })
ns.Events.On("SUUUI_THEME_CHANGED", function()
    for a in pairs(alerts) do a:Fit() end
end, "UI.Alert")

function Alert:SetAlert(tone, title, detail, ...)
    self:SetTone(tone)
    self.title:SetValue(title or "")
    self.titleText = title or ""
    self.detailText = setDetail(self, detail, ...)
    self:Fit()
end

function UI.Alert(parent)
    local f = CreateFrame("Frame", nil, parent)
    Mixin(f, Alert)
    alerts[f] = true
    f.ground = f:CreateTexture(nil, "BACKGROUND")
    f.ground:SetAllPoints()
    f.glow = UI.Shadow(f, "glow-ember")
    -- the rules above and below (a border without its sides)
    f.rules = UI.Border(f, "ember")
    f.rules.left:Hide()
    f.rules.right:Hide()
    f.left = UI.Diamond(f, JEWEL, "ember")
    f.left:SetPoint("CENTER", f, "LEFT", 0, 0)
    f.right = UI.Diamond(f, JEWEL, "ember")
    f.right:SetPoint("CENTER", f, "RIGHT", 0, 0)
    f.title = UI.Text(f, "alert", "ember-text")
    -- the display face is small caps with no descenders: its line box
    -- centres 2px high, so it sits 2px lower
    f.title:SetPoint("TOP", 0, -S["space-4"] - 2)
    f.detail = UI.Text(f, "caption", "ink")
    f.detail:SetPoint("TOP", f.title, "BOTTOM", 0, -S["space-1"])
    f:SetAlert("danger", "")
    return f
end
