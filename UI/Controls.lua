-- UI/Controls.lua
-- Button and StateBadge.

local _, ns = ...

local UI, T, Motion = ns.UI, ns.Tokens, ns.Motion
local S = T.space

--------------------------------------------------------------------------------
-- Button
--
--   UI.Button(parent, { text = "Ready check", variant = "primary", onClick = fn,
--       width = nil, disabled = false, tooltip = { title = …, description = … } })
--
-- quiet (default): surface-raised, gilt-line border, ink label; hover turns the
-- border gilt. primary: arcane fill, on-signal label, arcane glow on hover;
-- at most one per view. 30px tall, space-5 side padding; press moves the label
-- 1px down; disabled sits at opacity-disabled.
--------------------------------------------------------------------------------

local Button = {}

function Button:SetLabel(text)
    self.label:SetValue(text)
    if not self.fixedWidth then
        self:SetWidth(self.label:GetUnboundedStringWidth() + S["space-5"] * 2)
    end
end

function Button:SetEnabledState(enabled)
    self:SetEnabled(enabled)
    self:SetAlpha(enabled and 1 or T.opacity["opacity-disabled"])
end

local function onEnter(self)
    if self.variant == "primary" then
        self.glow:SetShown(true)
    else
        self.border:SetColor("gilt")
    end
    if self.tooltip then UI.ShowTooltip(self, self.tooltip) end
end

local function onLeave(self)
    if self.variant == "primary" then
        self.glow:SetShown(false)
    else
        self.border:SetColor("gilt-line")
    end
    if self.tooltip then UI.HideTooltip() end
end

function UI.Button(parent, opts)
    opts = opts or {}
    local b = CreateFrame("Button", nil, parent)
    Mixin(b, Button)
    b.variant = opts.variant or "quiet"
    local primary = b.variant == "primary"
    b:SetHeight(30)
    b.bg = UI.Fill(b, primary and "arcane" or "surface-raised")
    b.bg:SetAllPoints()
    b.border = UI.Border(b, primary and "arcane" or "gilt-line")
    if primary then
        b.glow = UI.Shadow(b, "glow-arcane")
        b.glow:SetShown(false)
    end
    b.label = UI.Text(b, "label", primary and "on-signal" or "ink")
    b.label:SetPoint("CENTER", 0, 0)
    b.fixedWidth = opts.width
    if opts.width then b:SetWidth(opts.width) end
    b:SetLabel(opts.text or "")
    b.tooltip = opts.tooltip

    b:SetScript("OnEnter", onEnter)
    b:SetScript("OnLeave", onLeave)
    b:SetScript("OnMouseDown", function(self) if self:IsEnabled() then self.label:SetPoint("CENTER", 0, -1) end end)
    b:SetScript("OnMouseUp", function(self) self.label:SetPoint("CENTER", 0, 0) end)
    b:SetScript("OnClick", function(self) if opts.onClick then opts.onClick(self) end end)
    b:SetEnabledState(not opts.disabled)
    return b
end

--------------------------------------------------------------------------------
-- StateBadge: one or two words naming a state, on the state's fill.
--
--   UI.StateBadge(parent, "danger", "Aggro")
--   tones: danger, warning, magic, curse, poison, disease, ward, info, neutral
--------------------------------------------------------------------------------

local TONE_FILL = {
    danger = "ember", warning = "amber",
    magic = "dispel-magic", curse = "dispel-curse", poison = "dispel-poison", disease = "dispel-disease",
    ward = "ward", info = "gilt-text", neutral = "surface-raised",
}

local Badge = {}

function Badge:SetState(tone, text)
    tone = TONE_FILL[tone] and tone or "neutral"
    self.bg:SetColorTexture(UI.RGBA(TONE_FILL[tone]))
    self.label:SetColor(tone == "neutral" and "ink" or "on-signal")
    self.edge:SetShown(tone == "neutral")
    local wasShown = self:IsShown() and self.text ~= nil
    self.label:SetValue(text)
    self.text, self.tone = text, tone
    self:SetWidth(self.label:GetUnboundedStringWidth() + 10)
    if not wasShown then Motion.FadeIn(self, T.duration["dur-fast"]) end
end

function UI.StateBadge(parent, tone, text)
    local f = CreateFrame("Frame", nil, parent)
    Mixin(f, Badge)
    f:SetHeight(T.type.badge.lineHeight)
    f.bg = UI.Fill(f, "surface-raised")
    f.bg:SetAllPoints()
    f.edge = UI.Border(f, "gilt-hairline")
    f.label = UI.Text(f, "badge", "on-signal")
    f.label:SetPoint("CENTER", 0, 0)
    f:SetState(tone, text or "")
    return f
end
